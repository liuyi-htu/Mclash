import 'dart:convert';
import 'dart:io';

typedef RegistryProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class WindowsSystemProxyManager {
  WindowsSystemProxyManager({
    required this.backupPath,
    RegistryProcessRunner? processRunner,
  }) : _processRunner = processRunner ?? _defaultProcessRunner;

  static const internetSettingsKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const managedValues = <String>[
    'ProxyEnable',
    'ProxyServer',
    'ProxyOverride',
  ];

  final String backupPath;
  final RegistryProcessRunner _processRunner;

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments, runInShell: false);

  Future<void> enable({required int port, required String bypass}) async {
    final owned = <String, _RegistryValue>{
      'ProxyEnable': const _RegistryValue(type: 'REG_DWORD', data: '1'),
      'ProxyServer': _RegistryValue(
        type: 'REG_SZ',
        data: '127.0.0.1:$port',
      ),
      'ProxyOverride': _RegistryValue(type: 'REG_SZ', data: bypass),
    };
    await _backupForEnable(owned);
    await _writeValue('ProxyServer', 'REG_SZ', '127.0.0.1:$port');
    await _writeValue('ProxyOverride', 'REG_SZ', bypass);
    await _writeValue('ProxyEnable', 'REG_DWORD', '1');
  }

  Future<void> restore() async {
    final backup = File(backupPath);
    if (!await backup.exists()) {
      // A repeated stop/sync must not disable a proxy that was already restored
      // or that belongs to another application.
      return;
    }

    final decoded = _decodeBackup(await backup.readAsString());
    final original = decoded.original;
    final owned = decoded.owned;
    final stillOwned = owned == null
        ? await _looksLikeLegacyMclashProxy()
        : await _isOwnedByMclash(owned);
    if (!stillOwned) {
      // Another application or the user changed the proxy after Mclash. Do not
      // overwrite that newer choice, and relinquish the stale backup.
      await backup.delete();
      return;
    }
    for (final name in managedValues) {
      final saved = original[name];
      if (saved == null) {
        await _deleteValue(name);
        continue;
      }
      await _writeValue(name, saved.type, saved.data);
    }
    await backup.delete();
  }

  Future<void> _backupForEnable(
    Map<String, _RegistryValue> desiredOwnership,
  ) async {
    final backup = File(backupPath);
    Map<String, _RegistryValue?> original;
    if (await backup.exists()) {
      final existing = _decodeBackup(await backup.readAsString());
      final stillOwned = existing.owned == null
          ? await _looksLikeLegacyMclashProxy()
          : await _isOwnedByMclash(existing.owned!);
      original = stillOwned
          ? existing.original
          : await _readManagedValues();
    } else {
      original = await _readManagedValues();
    }

    await backup.parent.create(recursive: true);
    await _writeBackup(
      backup,
      <String, dynamic>{
        'version': 2,
        'original': _valuesToJson(original),
        'owned': _valuesToJson(desiredOwnership),
      },
    );
  }

  Future<Map<String, _RegistryValue?>> _readManagedValues() async {
    final values = <String, _RegistryValue?>{};
    for (final name in managedValues) {
      values[name] = await _readValue(name);
    }
    return values;
  }

  Future<void> _writeBackup(
    File backup,
    Map<String, dynamic> payload,
  ) async {
    final temporary = File('${backup.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    await temporary.rename(backup.path);
  }

  Map<String, dynamic> _valuesToJson(
    Map<String, _RegistryValue?> values,
  ) => <String, dynamic>{
    for (final name in managedValues) name: values[name]?.toJson(),
  };

  _ProxyBackup _decodeBackup(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid system proxy backup.');
    }
    // Version 1 backups stored the original values at the top level.
    final originalSource = decoded['original'] ?? decoded;
    final ownedSource = decoded['owned'];
    return _ProxyBackup(
      original: _decodeValues(originalSource),
      owned: ownedSource == null ? null : _decodeValues(ownedSource),
    );
  }

  Map<String, _RegistryValue?> _decodeValues(Object? source) {
    if (source is! Map) {
      throw const FormatException('Invalid system proxy backup values.');
    }
    final values = <String, _RegistryValue?>{};
    for (final name in managedValues) {
      final saved = source[name];
      if (saved == null) {
        values[name] = null;
      } else if (saved is Map &&
          saved['type'] is String &&
          saved['data'] is String) {
        values[name] = _RegistryValue(
          type: saved['type'] as String,
          data: saved['data'] as String,
        );
      } else {
        throw const FormatException('Invalid system proxy backup value.');
      }
    }
    return values;
  }

  Future<bool> _isOwnedByMclash(
    Map<String, _RegistryValue?> expected,
  ) async {
    final expectedServer = expected['ProxyServer'];
    if (expectedServer == null) return false;
    final currentServer = await _readValue('ProxyServer');
    return currentServer != null &&
        currentServer.sameValue(expectedServer) &&
        expectedServer.data.startsWith('127.0.0.1:');
  }

  Future<bool> _looksLikeLegacyMclashProxy() async {
    final server = await _readValue('ProxyServer');
    final enabled = await _readValue('ProxyEnable');
    return server != null &&
        RegExp(r'^127\.0\.0\.1:\d+$').hasMatch(server.data) &&
        enabled != null &&
        enabled.asDword() == 1;
  }

  Future<_RegistryValue?> _readValue(String name) async {
    final result = await _processRunner('reg.exe', <String>[
      'query',
      internetSettingsKey,
      '/v',
      name,
    ]);
    if (result.exitCode != 0) return null;
    final pattern = RegExp(
      '^\\s+${RegExp.escape(name)}\\s+(REG_[A-Z0-9_]+)\\s*(.*)\\s*\$',
      caseSensitive: false,
      multiLine: true,
    );
    final match = pattern.firstMatch(result.stdout.toString());
    if (match == null) {
      throw StateError('Unable to parse Windows proxy setting $name.');
    }
    return _RegistryValue(
      type: match.group(1)!.toUpperCase(),
      data: match.group(2)!.trimRight(),
    );
  }

  Future<void> _writeValue(String name, String type, String data) async {
    final result = await _processRunner('reg.exe', <String>[
      'add',
      internetSettingsKey,
      '/v',
      name,
      '/t',
      type,
      '/d',
      data,
      '/f',
    ]);
    if (result.exitCode != 0) {
      final message = result.stderr.toString().trim();
      throw StateError(message.isEmpty ? '更新 Windows 系统代理失败。' : message);
    }
  }

  Future<void> _deleteValue(String name) async {
    final result = await _processRunner('reg.exe', <String>[
      'delete',
      internetSettingsKey,
      '/v',
      name,
      '/f',
    ]);
    // reg.exe returns 1 when the value is already absent, which is the desired
    // restored state.
    if (result.exitCode != 0 && result.exitCode != 1) {
      final message = result.stderr.toString().trim();
      throw StateError(message.isEmpty ? '恢复 Windows 系统代理失败。' : message);
    }
  }
}

class _RegistryValue {
  const _RegistryValue({required this.type, required this.data});

  final String type;
  final String data;

  bool sameValue(_RegistryValue other) {
    if (type.toUpperCase() != other.type.toUpperCase()) return false;
    final leftDword = asDword();
    final rightDword = other.asDword();
    if (leftDword != null && rightDword != null) {
      return leftDword == rightDword;
    }
    return data == other.data;
  }

  int? asDword() {
    if (type.toUpperCase() != 'REG_DWORD') return null;
    final normalized = data.trim().toLowerCase();
    return normalized.startsWith('0x')
        ? int.tryParse(normalized.substring(2), radix: 16)
        : int.tryParse(normalized);
  }

  Map<String, String> toJson() => <String, String>{
    'type': type,
    'data': data,
  };
}

class _ProxyBackup {
  const _ProxyBackup({required this.original, required this.owned});

  final Map<String, _RegistryValue?> original;
  final Map<String, _RegistryValue?>? owned;
}
