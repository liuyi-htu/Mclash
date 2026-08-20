import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'models.dart';
import 'proxy_platform_service.dart';
import 'windows_system_proxy_manager.dart';

typedef ServiceProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class WindowsProxyPlatformService implements ProxyPlatformService {
  WindowsProxyPlatformService({
    String? dataDir,
    String? systemProxyBackupPath,
    RegistryProcessRunner? registryProcessRunner,
    ServiceProcessRunner? serviceProcessRunner,
  }) : _dataDirOverride = dataDir,
       _systemProxyBackupPathOverride = systemProxyBackupPath,
       _registryProcessRunner = registryProcessRunner,
       _serviceProcessRunner = serviceProcessRunner;

  final String? _dataDirOverride;
  final String? _systemProxyBackupPathOverride;
  final RegistryProcessRunner? _registryProcessRunner;
  final ServiceProcessRunner? _serviceProcessRunner;

  static const _loopbackProxyBypass = <String>['localhost', '127.*'];
  static const _privateNetworkCidrs = <String>[
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '169.254.0.0/16',
    'fc00::/7',
    'fe80::/10',
  ];
  static const _privateProxyBypass = <String>[
    '<local>',
    ..._loopbackProxyBypass,
    '10.*',
    '192.168.*',
    '169.254.*',
    '172.16.*',
    '172.17.*',
    '172.18.*',
    '172.19.*',
    '172.20.*',
    '172.21.*',
    '172.22.*',
    '172.23.*',
    '172.24.*',
    '172.25.*',
    '172.26.*',
    '172.27.*',
    '172.28.*',
    '172.29.*',
    '172.30.*',
    '172.31.*',
  ];
  static const _managedSingBoxIpv6Address = 'fdfe:dcba:9876::1/126';
  static const _defaultProfileId = 'default.yaml';

  String get _dataDir =>
      _dataDirOverride ??
      '${File(Platform.resolvedExecutable).parent.path}\\data';
  String get _profilesDir => '$_dataDir\\profiles';
  String get _logsDir => '$_dataDir\\logs';
  String get _settingsPath => '$_dataDir\\settings.json';
  String get _legacyStatePath => '$_dataDir\\state.json';
  String get _configPath => '$_dataDir\\config.yaml';
  String get _singBoxConfigPath => '$_dataDir\\sing-box.json';
  String get _serviceExe =>
      '${File(Platform.resolvedExecutable).parent.path}\\MclashService.exe';
  String get _systemProxyBackupPath =>
      _systemProxyBackupPathOverride ??
      '${Platform.environment['LOCALAPPDATA'] ?? _dataDir}\\Mclash\\system-proxy-backup.json';
  WindowsSystemProxyManager get _systemProxyManager =>
      WindowsSystemProxyManager(
        backupPath: _systemProxyBackupPath,
        processRunner: _registryProcessRunner,
      );

  Future<void> _ensureDirectories() async {
    await Directory(_profilesDir).create(recursive: true);
    await Directory(_logsDir).create(recursive: true);
  }

  Future<Map<String, dynamic>?> _readJsonMap(File file) async {
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('${file.path} must contain a JSON object.');
    }
    return decoded;
  }

  Future<void> _writeSettings(Map<String, dynamic> settings) async {
    await _ensureDirectories();
    final temporary = File('$_settingsPath.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings),
      flush: true,
    );
    await temporary.rename(_settingsPath);
  }

  Future<Map<String, dynamic>> _readSettings() async {
    final current = await _readJsonMap(File(_settingsPath));
    if (current != null) return current;

    final legacy = await _readJsonMap(File(_legacyStatePath));
    if (legacy == null) return <String, dynamic>{};
    legacy.remove('mihomoPid');
    legacy.remove('message');
    await _writeSettings(legacy);
    return legacy;
  }

  Future<void> _updateSettings(Map<String, dynamic> changes) async {
    final settings = await _readSettings()..addAll(changes);
    await _writeSettings(settings);
  }

  Future<Map<String, dynamic>> _status() async {
    final result = await _runService('status-json', allowFailure: true);
    try {
      final decoded = jsonDecode(result.stdout.toString().trim());
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    if (!File(_serviceExe).existsSync()) {
      throw StateError('MclashService.exe was not found next to Mclash.exe.');
    }
    throw StateError(
      result.stderr.toString().trim().isEmpty
          ? 'Unable to read the Windows service status.'
          : result.stderr.toString().trim(),
    );
  }

  Future<ProcessResult> _runService(
    String command, {
    bool allowFailure = false,
  }) async {
    if (_serviceProcessRunner == null && !await File(_serviceExe).exists()) {
      throw StateError('MclashService.exe was not found next to Mclash.exe.');
    }
    final arguments = <String>[
      command,
      '--base',
      File(_serviceExe).parent.path,
      '--data-dir',
      _dataDir,
    ];
    final result = await (_serviceProcessRunner?.call(
          _serviceExe,
          arguments,
        ) ??
        Process.run(_serviceExe, arguments, runInShell: false));
    if (!allowFailure && result.exitCode != 0) {
      final message = result.stderr.toString().trim();
      throw StateError(
        message.isEmpty ? '$command failed (${result.exitCode}).' : message,
      );
    }
    return result;
  }

  @override
  Future<bool> isRunning() async => (await _status())['state'] == 'running';

  @override
  Future<void> start() async {
    final status = await _status();
    if (status['installed'] != true) await _runService('install');
    try {
      await _runService('start');
      await syncSystemProxy();
    } catch (_) {
      await _setSystemProxyEnabled(false);
      await _runService('stop', allowFailure: true);
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    await _setSystemProxyEnabled(false);
    await _runService('stop');
  }

  @override
  Future<void> restart() async {
    await _setSystemProxyEnabled(false);
    await _runService('restart');
    try {
      await syncSystemProxy();
    } catch (_) {
      await _runService('stop', allowFailure: true);
      rethrow;
    }
  }

  @override
  Future<void> syncSystemProxy() async {
    final shouldEnable =
        await getNetworkMode() == NetworkMode.proxy && await isRunning();
    await _setSystemProxyEnabled(shouldEnable);
  }

  Future<void> _setSystemProxyEnabled(bool enabled) async {
    if (enabled) {
      final port = await _systemProxyPort();
      final bypassLan = await getBypassLanEnabled();
      await _systemProxyManager.enable(
        port: port,
        bypass: (bypassLan ? _privateProxyBypass : _loopbackProxyBypass).join(
          ';',
        ),
      );
    } else {
      await _systemProxyManager.restore();
    }
    await _notifySystemProxyChanged();
  }

  Future<int> _systemProxyPort() async {
    if (await getCoreType() == CoreType.singBox) {
      final document = jsonDecode(
        await File(_singBoxConfigPath).readAsString(),
      );
      if (document is Map) {
        final inbounds = document['inbounds'];
        if (inbounds is List) {
          for (final inbound in inbounds.whereType<Map>()) {
            if (inbound['type'] == 'mixed' || inbound['type'] == 'http') {
              final value = inbound['listen_port'];
              final port = value is int
                  ? value
                  : int.tryParse(value?.toString() ?? '');
              if (port != null && port > 0 && port <= 65535) return port;
            }
          }
        }
      }
      throw StateError('sing-box 系统代理模式需要 mixed 或 http 入站。');
    }
    if (!await File(_configPath).exists()) {
      throw StateError('mihomo configuration does not exist.');
    }
    final document = loadYaml(await File(_configPath).readAsString());
    if (document is! YamlMap) {
      throw const FormatException('mihomo configuration must be a YAML map.');
    }
    for (final key in const <String>['mixed-port', 'port']) {
      final value = document[key];
      final port = value is int ? value : int.tryParse(value?.toString() ?? '');
      if (port != null && port >= 1 && port <= 65535) return port;
    }
    throw StateError('代理模式需要在配置中设置 mixed-port 或 port。');
  }

  Future<void> _notifySystemProxyChanged() async {
    const script = r'''
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WinInetProxy {
  [DllImport("wininet.dll", SetLastError = true)]
  public static extern bool InternetSetOption(IntPtr hInternet, int option, IntPtr buffer, int length);
}
'@
[WinInetProxy]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
[WinInetProxy]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
''';
    final result = await Process.run('powershell.exe', const <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ], runInShell: false);
    if (result.exitCode != 0) {
      throw StateError('Windows 系统代理已写入，但刷新系统设置失败。');
    }
  }

  @override
  Future<NetworkMode> getNetworkMode() async =>
      (await _readSettings())['networkMode'] == 'tun'
      ? NetworkMode.tun
      : NetworkMode.proxy;

  @override
  Future<void> setNetworkMode(NetworkMode mode) async {
    await _ensureDirectories();
    final state = await _readSettings();
    final preferences = _runtimePreferencesFromState(state);
    final core = await getCoreType();
    final active = state['activeProfile']?.toString();
    File? source;
    if (core == CoreType.mihomo && active != null) {
      final profile = File(_profilePath(active));
      if (await profile.exists()) source = profile;
    }
    source ??=
        await File(
          core == CoreType.singBox ? _singBoxConfigPath : _configPath,
        ).exists()
        ? File(core == CoreType.singBox ? _singBoxConfigPath : _configPath)
        : null;

    if (source != null) {
      final content = await source.readAsString();
      if (core == CoreType.singBox) {
        await File(
          _singBoxConfigPath,
        ).writeAsString(
          _singBoxRuntimeConfig(
            content,
            mode,
            ipv6Enabled: preferences.ipv6Enabled,
            bypassLanEnabled: preferences.bypassLanEnabled,
          ),
          flush: true,
        );
      } else {
        await File(
          _configPath,
        ).writeAsString(
          _runtimeConfig(
            content,
            mode,
            ipv6Enabled: preferences.ipv6Enabled,
            bypassLanEnabled: preferences.bypassLanEnabled,
          ),
          flush: true,
        );
      }
    }
    await _updateSettings(<String, dynamic>{
      'networkMode': mode == NetworkMode.tun ? 'tun' : 'proxy',
    });
  }

  @override
  Future<bool> getIpv6Enabled() async =>
      (await _readSettings())['ipv6Enabled'] == true;

  @override
  Future<void> setIpv6Enabled(bool enabled) async {
    await _updateSettings(<String, dynamic>{'ipv6Enabled': enabled});
    await _refreshRuntimeConfig();
  }

  @override
  Future<bool> getBypassLanEnabled() async =>
      (await _readSettings())['bypassLanEnabled'] != false;

  @override
  Future<void> setBypassLanEnabled(bool enabled) async {
    await _updateSettings(<String, dynamic>{'bypassLanEnabled': enabled});
    await _refreshRuntimeConfig();
  }

  _RuntimePreferences _runtimePreferencesFromState(
    Map<String, dynamic> state,
  ) => _RuntimePreferences(
    ipv6Enabled: state['ipv6Enabled'] == true,
    bypassLanEnabled: state['bypassLanEnabled'] != false,
  );

  List<String> _routeExcludes(Object? existing, bool bypassLanEnabled) {
    final result = existing is Iterable
        ? existing.map((value) => value.toString()).toList()
        : <String>[];
    result.removeWhere(_privateNetworkCidrs.contains);
    if (bypassLanEnabled) result.addAll(_privateNetworkCidrs);
    return result;
  }

  Object? _plainYamlValue(Object? value) {
    if (value is YamlMap) {
      return _plainYamlMap(value);
    }
    if (value is YamlList) {
      return <Object?>[
        for (final item in value) _plainYamlValue(item),
      ];
    }
    return value;
  }

  Map<Object?, Object?> _plainYamlMap(YamlMap value) => <Object?, Object?>{
    for (final key in value.keys)
      _plainYamlValue(key): _plainYamlValue(value[key]),
  };

  Future<void> _refreshRuntimeConfig() async {
    final state = await _readSettings();
    final active = state['activeProfile']?.toString();
    final singBox = state['coreType'] == 'sing-box';
    File? source;
    if (active != null && active.isNotEmpty) {
      final profile = File(_profilePath(active));
      if (await profile.exists()) source = profile;
    }
    final resolvedSource =
        source ?? File(singBox ? _singBoxConfigPath : _configPath);
    if (!await resolvedSource.exists()) return;
    final content = await resolvedSource.readAsString();
    final mode = state['networkMode'] == 'tun'
        ? NetworkMode.tun
        : NetworkMode.proxy;
    final preferences = _runtimePreferencesFromState(state);
    if (singBox) {
      await File(_singBoxConfigPath).writeAsString(
        _singBoxRuntimeConfig(
          content,
          mode,
          ipv6Enabled: preferences.ipv6Enabled,
          bypassLanEnabled: preferences.bypassLanEnabled,
        ),
        flush: true,
      );
    } else {
      await File(_configPath).writeAsString(
        _runtimeConfig(
          content,
          mode,
          ipv6Enabled: preferences.ipv6Enabled,
          bypassLanEnabled: preferences.bypassLanEnabled,
        ),
        flush: true,
      );
    }
  }

  @override
  Future<CoreType> getCoreType() async =>
      (await _readSettings())['coreType'] == 'sing-box'
      ? CoreType.singBox
      : CoreType.mihomo;

  bool _profileMatchesCore(String? id, CoreType core) {
    if (id == null || id.isEmpty) return false;
    return core == CoreType.singBox
        ? id.toLowerCase().endsWith('.json')
        : RegExp(r'\.(yaml|yml)$', caseSensitive: false).hasMatch(id);
  }

  String _activeProfileKey(CoreType core) =>
      core == CoreType.singBox ? 'activeSingBoxProfile' : 'activeMihomoProfile';

  @override
  Future<void> setCoreType(CoreType core) async {
    final state = await _readSettings();
    final currentCore = state['coreType'] == 'sing-box'
        ? CoreType.singBox
        : CoreType.mihomo;
    final currentActive = state['activeProfile']?.toString();
    final currentActiveKey = _activeProfileKey(currentCore);
    final targetActiveKey = _activeProfileKey(core);
    final rememberedTarget = state[targetActiveKey]?.toString();

    // Preserve the selected profile when only switching TUN/system proxy.
    // When switching cores, remember the current core's profile and restore
    // the last profile used by the target core.
    final targetActive =
        currentCore == core && _profileMatchesCore(currentActive, core)
        ? currentActive
        : _profileMatchesCore(rememberedTarget, core)
        ? rememberedTarget
        : null;

    final changes = <String, dynamic>{
      'coreType': core == CoreType.singBox ? 'sing-box' : 'mihomo',
      'activeProfile': targetActive,
    };
    if (_profileMatchesCore(currentActive, currentCore)) {
      changes[currentActiveKey] = currentActive;
    }
    await _updateSettings(changes);
  }

  @override
  Future<ConfigInfo> getConfigInfo() async {
    final state = await _readSettings();
    final core = await getCoreType();
    final exists = await File(
      core == CoreType.singBox ? _singBoxConfigPath : _configPath,
    ).exists();
    final active = state['activeProfile']?.toString();
    final names = state['profileNames'];
    final displayName = names is Map && active != null
        ? names[active]?.toString()
        : null;
    return ConfigInfo(
      exists: exists,
      fileName:
          displayName ??
          (exists
              ? (core == CoreType.singBox ? 'sing-box.json' : 'config.yaml')
              : null),
    );
  }

  String _profilePath(String id) {
    if (!RegExp(
      r'^[A-Za-z0-9._-]+\.(yaml|yml|json)$',
      caseSensitive: false,
    ).hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid profile id');
    }
    return '$_profilesDir\\$id';
  }

  Map<String, dynamic> _stateMap(Map<String, dynamic> state, String key) =>
      Map<String, dynamic>.from(
        state[key] is Map ? state[key] as Map : const {},
      );

  @override
  Future<List<ConfigProfile>> getConfigs() async {
    await _ensureDirectories();
    final core = await getCoreType();
    var state = await _readSettings();
    var active = state['activeProfile']?.toString();
    final defaultProfile = File(_profilePath(_defaultProfileId));
    if (active == null &&
        state['defaultProfileDeleted'] != true &&
        await File(_configPath).exists() &&
        !await defaultProfile.exists()) {
      await File(_configPath).copy(defaultProfile.path);
      final names = _stateMap(state, 'profileNames')
        ..[_defaultProfileId] = 'Default';
      await _updateSettings(<String, dynamic>{
        'activeProfile': _defaultProfileId,
        'activeMihomoProfile': _defaultProfileId,
        'profileNames': names,
      });
      state = await _readSettings();
      active = _defaultProfileId;
    }
    final rawNames = state['profileNames'];
    final names = rawNames is Map ? rawNames : const <String, dynamic>{};
    final types = _stateMap(state, 'profileTypes');
    final urls = _stateMap(state, 'profileUrls');
    final files = await Directory(_profilesDir)
        .list()
        .where(
          (entity) =>
              entity is File &&
              (core == CoreType.mihomo
                  ? RegExp(
                      r'\.(yaml|yml)$',
                      caseSensitive: false,
                    ).hasMatch(entity.path)
                  : entity.path.toLowerCase().endsWith('.json')),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    final profiles = <ConfigProfile>[];
    for (final file in files) {
      final id = file.uri.pathSegments.last;
      if (!names.containsKey(id) && active != id) {
        continue;
      }
      final stat = await file.stat();
      profiles.add(
        ConfigProfile(
          id: id,
          name: names[id]?.toString() ?? id.substring(0, id.lastIndexOf('.')),
          type: types[id]?.toString() == 'subscription'
              ? 'subscription'
              : 'local',
          url: urls[id]?.toString(),
          active: active == id,
          exists: true,
          updatedAt: stat.modified.millisecondsSinceEpoch,
        ),
      );
    }
    return profiles;
  }

  @override
  Future<List<ConfigProfile>> importConfigs() async {
    if (await isRunning()) {
      throw StateError('代理运行中，不能导入配置文件。');
    }
    await _ensureDirectories();
    final core = await getCoreType();
    final script = core == CoreType.mihomo
        ? r'''Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = 'mihomo YAML (*.yaml;*.yml)|*.yaml;*.yml'
$dialog.Multiselect = $true
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  $dialog.FileNames | ForEach-Object { [Console]::Out.WriteLine($_) }
}'''
        : r'''Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = 'sing-box JSON (*.json)|*.json'
$dialog.Multiselect = $true
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  $dialog.FileNames | ForEach-Object { [Console]::Out.WriteLine($_) }
}''';
    final picked = await Process.run('powershell.exe', <String>[
      '-NoProfile',
      '-STA',
      '-Command',
      script,
    ]);
    if (picked.exitCode != 0) throw StateError(picked.stderr.toString());
    final paths = const LineSplitter()
        .convert(picked.stdout.toString())
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (paths.isEmpty) return getConfigs();
    if (await isRunning()) {
      throw StateError('代理已启动，配置文件未导入。请停止代理后重试。');
    }
    final state = await _readSettings();
    final names = Map<String, dynamic>.from(
      state['profileNames'] is Map ? state['profileNames'] as Map : const {},
    );
    String? importedProfileId;
    for (final sourcePath in paths) {
      final source = File(sourcePath);
      final lowerPath = source.path.toLowerCase();
      final extension = core == CoreType.singBox
          ? '.json'
          : lowerPath.endsWith('.yml')
          ? '.yml'
          : '.yaml';
      if (core == CoreType.mihomo &&
          !RegExp(
            r'\.(yaml|yml)$',
            caseSensitive: false,
          ).hasMatch(source.path)) {
        throw ArgumentError('mihomo 内核只能导入 YAML 配置。');
      }
      if (core == CoreType.singBox && !lowerPath.endsWith('.json')) {
        throw ArgumentError('sing-box 内核只能导入 JSON 配置。');
      }
      final content = await source.readAsString();
      if (core == CoreType.mihomo) {
        final document = loadYaml(content);
        if (document is! YamlMap) {
          throw const FormatException('mihomo 配置必须是 YAML 对象。');
        }
      } else {
        final document = jsonDecode(content);
        if (document is! Map<String, dynamic>) {
          throw const FormatException('sing-box 配置必须是 JSON 对象。');
        }
      }
      var id = source.uri.pathSegments.last.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      if (!id.toLowerCase().endsWith(extension)) id = '$id$extension';
      var candidate = id;
      var suffix = 2;
      while (await File(_profilePath(candidate)).exists()) {
        candidate = '${id.substring(0, id.lastIndexOf('.'))}-$suffix$extension';
        suffix++;
      }
      await source.copy(_profilePath(candidate));
      names[candidate] = id.substring(0, id.lastIndexOf('.'));
      importedProfileId = candidate;
    }
    await _updateSettings(<String, dynamic>{'profileNames': names});
    if (importedProfileId != null) {
      await selectConfig(importedProfileId);
    }
    return getConfigs();
  }

  String _secureController(String content) {
    var result = content.replaceAll(
      RegExp(r'^\s*external-controller\s*:.*$', multiLine: true),
      'external-controller: 127.0.0.1:9090',
    );
    if (!RegExp(
      r'^\s*external-controller\s*:',
      multiLine: true,
    ).hasMatch(result)) {
      result = '$result\nexternal-controller: 127.0.0.1:9090\n';
    }
    result = result.replaceAll(
      RegExp(r'^\s*secret\s*:.*$', multiLine: true),
      'secret: ""',
    );
    if (!RegExp(r'^\s*secret\s*:', multiLine: true).hasMatch(result)) {
      result = '$result\nsecret: ""\n';
    }
    return result;
  }

  String _runtimeConfig(
    String content,
    NetworkMode mode, {
    bool ipv6Enabled = false,
    bool bypassLanEnabled = true,
  }) {
    final secured = _secureController(content);
    final document = loadYaml(secured);
    if (document is! YamlMap) {
      throw const FormatException('mihomo configuration must be a YAML map.');
    }

    try {
      final editor = YamlEditor(secured);
      editor.update(<Object>['ipv6'], ipv6Enabled);
      final dns = document['dns'];
      if (dns is YamlMap) {
        editor.update(<Object>['dns', 'ipv6'], ipv6Enabled);
      }
      final enabled = mode == NetworkMode.tun;
      final tun = document['tun'];
      if (tun is YamlMap) {
        editor.update(<Object>['tun', 'enable'], enabled);
        editor.update(
          <Object>['tun', 'route-exclude-address'],
          _routeExcludes(tun['route-exclude-address'], bypassLanEnabled),
        );
        if (enabled) {
          if (!tun.containsKey('stack')) {
            editor.update(<Object>['tun', 'stack'], 'mixed');
          }
          if (!tun.containsKey('auto-route')) {
            editor.update(<Object>['tun', 'auto-route'], true);
          }
          if (!tun.containsKey('auto-detect-interface')) {
            editor.update(<Object>['tun', 'auto-detect-interface'], true);
          }
        }
      } else {
        editor.update(
          <Object>['tun'],
          <String, dynamic>{
            'enable': enabled,
            'route-exclude-address': bypassLanEnabled
                ? _privateNetworkCidrs
                : const <String>[],
            if (enabled) ...<String, dynamic>{
              'stack': 'mixed',
              'auto-route': true,
              'auto-detect-interface': true,
            },
          },
        );
      }
      return '${editor.toString().trimRight()}\n';
    } on AliasException {
      return _runtimeConfigWithExpandedAliases(
        document,
        mode,
        ipv6Enabled: ipv6Enabled,
        bypassLanEnabled: bypassLanEnabled,
      );
    }
  }

  String _runtimeConfigWithExpandedAliases(
    YamlMap document,
    NetworkMode mode, {
    required bool ipv6Enabled,
    required bool bypassLanEnabled,
  }) {
    final runtime = _plainYamlMap(document);
    runtime['ipv6'] = ipv6Enabled;
    final dns = runtime['dns'];
    if (dns is Map) dns['ipv6'] = ipv6Enabled;

    final enabled = mode == NetworkMode.tun;
    final tun = runtime['tun'];
    if (tun is Map) {
      tun['enable'] = enabled;
      tun['route-exclude-address'] = _routeExcludes(
        tun['route-exclude-address'],
        bypassLanEnabled,
      );
      if (enabled) {
        tun.putIfAbsent('stack', () => 'mixed');
        tun.putIfAbsent('auto-route', () => true);
        tun.putIfAbsent('auto-detect-interface', () => true);
      }
    } else {
      runtime['tun'] = <String, dynamic>{
        'enable': enabled,
        'route-exclude-address': bypassLanEnabled
            ? _privateNetworkCidrs
            : const <String>[],
        if (enabled) ...<String, dynamic>{
          'stack': 'mixed',
          'auto-route': true,
          'auto-detect-interface': true,
        },
      };
    }

    final editor = YamlEditor('{}');
    editor.update(const <Object>[], runtime);
    return '${editor.toString().trimRight()}\n';
  }

  String _singBoxRuntimeConfig(
    String content,
    NetworkMode mode, {
    bool ipv6Enabled = false,
    bool bypassLanEnabled = true,
  }) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('sing-box 配置必须是 JSON 对象。');
    }
    final inbounds = List<dynamic>.from(
      decoded['inbounds'] is List
          ? decoded['inbounds'] as List
          : const <dynamic>[],
    );
    inbounds.removeWhere(
      (entry) =>
          entry is Map &&
          entry['type'] == 'tun' &&
          entry['tag'] == 'mclash-tun',
    );
    for (var index = 0; index < inbounds.length; index++) {
      final entry = inbounds[index];
      if (entry is! Map || entry['type'] != 'tun') continue;
      final updated = Map<String, dynamic>.from(entry);
      final addresses = List<String>.from(
        updated['address'] is List
            ? (updated['address'] as List).map((value) => value.toString())
            : const <String>[],
      );
      if (ipv6Enabled) {
        if (!addresses.any((address) => address.contains(':'))) {
          addresses.add(_managedSingBoxIpv6Address);
        }
      } else {
        addresses.removeWhere((address) => address.contains(':'));
      }
      if (updated['address'] is List || addresses.isNotEmpty) {
        updated['address'] = addresses;
      }
      updated['route_exclude_address'] = _routeExcludes(
        updated['route_exclude_address'],
        bypassLanEnabled,
      );
      inbounds[index] = updated;
    }
    if (mode == NetworkMode.tun) {
      final hasTun = inbounds.any(
        (entry) => entry is Map && entry['type'] == 'tun',
      );
      if (!hasTun) {
        inbounds.insert(0, <String, dynamic>{
          'type': 'tun',
          'tag': 'mclash-tun',
          'interface_name': 'Mclash',
          'address': <String>[
            '172.19.0.1/30',
            if (ipv6Enabled) _managedSingBoxIpv6Address,
          ],
          'auto_route': true,
          'strict_route': true,
          'route_exclude_address': bypassLanEnabled
              ? _privateNetworkCidrs
              : const <String>[],
        });
      }
    }
    decoded['inbounds'] = inbounds;

    final route = Map<String, dynamic>.from(
      decoded['route'] is Map ? decoded['route'] as Map : const {},
    );
    final ruleSets = List<dynamic>.from(
      route['rule_set'] is List ? route['rule_set'] as List : const [],
    );
    const bundledRuleSets = <String>[
      'geoip-cn',
      'geosite-cn',
      'geosite-private',
      'geosite-category-ads-all',
      'geosite-geolocation-!cn',
    ];
    final existingTags = ruleSets
        .whereType<Map>()
        .map((entry) => entry['tag']?.toString())
        .whereType<String>()
        .toSet();
    for (final tag in bundledRuleSets) {
      if (existingTags.contains(tag)) continue;
      ruleSets.add(<String, dynamic>{
        'type': 'local',
        'tag': tag,
        'format': 'binary',
        'path': 'rulesets/$tag.srs',
      });
    }
    route['rule_set'] = ruleSets;
    decoded['route'] = route;
    return '${const JsonEncoder.withIndent('  ').convert(decoded)}\n';
  }

  Future<String> _runtimeConfigForCurrentMode(String content) async {
    final state = await _readSettings();
    final preferences = _runtimePreferencesFromState(state);
    return _runtimeConfig(
      content,
      state['networkMode'] == 'tun' ? NetworkMode.tun : NetworkMode.proxy,
      ipv6Enabled: preferences.ipv6Enabled,
      bypassLanEnabled: preferences.bypassLanEnabled,
    );
  }

  Future<String> _singBoxRuntimeConfigForCurrentMode(String content) async {
    final state = await _readSettings();
    final preferences = _runtimePreferencesFromState(state);
    return _singBoxRuntimeConfig(
      content,
      state['networkMode'] == 'tun' ? NetworkMode.tun : NetworkMode.proxy,
      ipv6Enabled: preferences.ipv6Enabled,
      bypassLanEnabled: preferences.bypassLanEnabled,
    );
  }

  @override
  Future<ConfigInfo> selectConfig(String id) async {
    final source = File(_profilePath(id));
    if (!await source.exists()) {
      throw StateError('The selected profile no longer exists.');
    }
    final content = await source.readAsString();
    final isJSON = id.toLowerCase().endsWith('.json');
    if (isJSON) {
      await File(
        _singBoxConfigPath,
      ).writeAsString(await _singBoxRuntimeConfigForCurrentMode(content));
    } else {
      await File(
        _configPath,
      ).writeAsString(await _runtimeConfigForCurrentMode(content));
    }
    await _updateSettings(<String, dynamic>{
      'activeProfile': id,
      if (isJSON) 'activeSingBoxProfile': id else 'activeMihomoProfile': id,
      'coreType': isJSON ? 'sing-box' : 'mihomo',
    });
    return getConfigInfo();
  }

  @override
  Future<String> getConfigContent(String id) =>
      File(_profilePath(id)).readAsString();

  @override
  Future<List<ConfigProfile>> saveConfigContent({
    required String id,
    required String content,
  }) async {
    if (content.trim().isEmpty) {
      throw ArgumentError('Configuration cannot be empty.');
    }
    await File(_profilePath(id)).writeAsString(content);
    final state = await _readSettings();
    if (state['activeProfile'] == id) {
      if (id.toLowerCase().endsWith('.json')) {
        await File(
          _singBoxConfigPath,
        ).writeAsString(await _singBoxRuntimeConfigForCurrentMode(content));
      } else {
        await File(
          _configPath,
        ).writeAsString(await _runtimeConfigForCurrentMode(content));
      }
    }
    return getConfigs();
  }

  @override
  Future<List<ConfigProfile>> renameConfig({
    required String id,
    required String name,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Profile name cannot be empty.');
    }
    final state = await _readSettings();
    final names = Map<String, dynamic>.from(
      state['profileNames'] is Map ? state['profileNames'] as Map : const {},
    );
    names[id] = name.trim();
    await _updateSettings(<String, dynamic>{'profileNames': names});
    return getConfigs();
  }

  @override
  Future<List<ConfigProfile>> deleteConfig(String id) async {
    final state = await _readSettings();
    final deletingDefault = id.toLowerCase() == _defaultProfileId;
    final deletingActive = state['activeProfile'] == id;
    if (deletingActive && !deletingDefault) {
      throw StateError(
        'Select another profile before deleting the active profile.',
      );
    }
    final file = File(_profilePath(id));
    if (await file.exists()) await file.delete();
    final names = Map<String, dynamic>.from(
      state['profileNames'] is Map ? state['profileNames'] as Map : const {},
    )..remove(id);
    final types = _stateMap(state, 'profileTypes')..remove(id);
    final urls = _stateMap(state, 'profileUrls')..remove(id);
    final changes = <String, dynamic>{
      'profileNames': names,
      'profileTypes': types,
      'profileUrls': urls,
      if (deletingDefault) 'defaultProfileDeleted': true,
      if (deletingActive) 'activeProfile': null,
      if (state['activeMihomoProfile'] == id) 'activeMihomoProfile': null,
    };
    if (deletingActive && !id.toLowerCase().endsWith('.json')) {
      final runtime = File(_configPath);
      if (await runtime.exists()) await runtime.delete();
    }
    await _updateSettings(changes);
    return getConfigs();
  }

  @override
  Future<List<DebugLogFile>> getDebugLogs() async => const <DebugLogFile>[
    DebugLogFile(
      id: 'service.log',
      displayName: 'Mclash.log',
      description: '服务启动、停止和控制日志',
    ),
    DebugLogFile(
      id: 'mihomo.log',
      displayName: 'mihomo.log',
      description: 'mihomo 内核运行日志',
    ),
    DebugLogFile(
      id: 'sing-box.log',
      displayName: 'sing-box.log',
      description: 'sing-box 内核运行日志',
    ),
    DebugLogFile(
      id: 'update.log',
      displayName: 'update.log',
      description: 'mihomo/sing-box 内核检测与更新日志',
    ),
  ];

  @override
  Future<String> getDebugLogContent(String id) async {
    final logs = await getDebugLogs();
    if (!logs.any((log) => log.id == id)) {
      throw ArgumentError.value(id, 'id', 'Unknown debug log');
    }
    final file = File('$_logsDir\\$id');
    if (!await file.exists()) return '暂无日志内容。';
    final content = await file.readAsString();
    return content.isEmpty ? '暂无日志内容。' : content;
  }

  @override
  Future<bool> getUsageNoticeAccepted() async =>
      (await _readSettings())['usageNoticeAccepted'] == true;
  @override
  Future<void> acceptUsageNotice() =>
      _updateSettings(<String, dynamic>{'usageNoticeAccepted': true});
  @override
  Future<bool> getDebugLoggingEnabled() async =>
      (await _readSettings())['debugLoggingEnabled'] == true;
  @override
  Future<void> setDebugLoggingEnabled(bool enabled) =>
      _updateSettings(<String, dynamic>{'debugLoggingEnabled': enabled});
  @override
  Future<void> clearDebugLogs() async {
    for (final name in const <String>[
      'service.log',
      'mihomo.log',
      'sing-box.log',
      'update.log',
    ]) {
      final file = File('$_logsDir\\$name');
      if (await file.exists()) await file.writeAsString('');
    }
    await _runService('clear-runtime-message');
  }

  @override
  Future<bool> getServiceAutoStartEnabled() async {
    final result = await _runService('autostart-json');
    final decoded = jsonDecode(result.stdout.toString().trim());
    return decoded is Map<String, dynamic> && decoded['enabled'] == true;
  }

  @override
  Future<void> setServiceAutoStartEnabled(bool enabled) async {
    final status = await _status();
    if (status['installed'] != true) {
      if (!enabled) return;
      await _runService('install');
    }
    await _runService(enabled ? 'enable-autostart' : 'disable-autostart');
  }

  @override
  Future<CoreUpdateInfo> checkCoreUpdate(CoreType core) async {
    final result = await _runService(
      core == CoreType.mihomo ? 'core-update-json' : 'singbox-update-json',
    );
    final decoded = jsonDecode(result.stdout.toString().trim());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid core update response.');
    }
    return CoreUpdateInfo.fromMap(decoded);
  }

  @override
  Future<void> updateCore(CoreType core) => _runService(
    core == CoreType.mihomo ? 'update-core' : 'update-singbox',
  ).then((_) {});

  Uri _subscriptionUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError('请输入有效的 HTTP 或 HTTPS 订阅链接。');
    }
    return uri;
  }

  bool _looksLikeMihomoConfig(String content) => RegExp(
    r'^\s*(proxies|proxy-providers|proxy-groups|rules|mixed-port|port|socks-port|redir-port|tproxy-port)\s*:',
    caseSensitive: false,
    multiLine: true,
  ).hasMatch(content);

  Future<_SubscriptionDownload> _downloadSubscription(String url) async {
    final uri = _subscriptionUri(url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'clash.meta';
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = true;
        request.maxRedirects = 5;
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/yaml, text/yaml, text/plain, */*',
        );
        request.headers.set(HttpHeaders.userAgentHeader, 'clash.meta');
        final stopwatch = Stopwatch()..start();
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 16 * 1024 * 1024) {
            throw StateError('订阅内容超过 16 MB 限制。');
          }
        }
        stopwatch.stop();
        final contentType = response.headers.contentType?.mimeType;
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('订阅服务器返回 HTTP ${response.statusCode}。', uri: uri);
        }
        String content;
        try {
          content = utf8.decode(bytes);
        } on FormatException {
          throw const FormatException('订阅内容不是有效的 UTF-8 文本。');
        }
        if (content.startsWith('\uFEFF')) content = content.substring(1);
        if (content.trim().isEmpty) {
          throw StateError('订阅服务器返回了空内容。');
        }
        if (!_looksLikeMihomoConfig(content)) {
          throw StateError('订阅内容不是 mihomo/Clash YAML 配置，请检查订阅链接类型。');
        }
        return _SubscriptionDownload(
          content: content,
          responseTimeMs: stopwatch.elapsedMilliseconds,
          statusCode: response.statusCode,
          contentType: contentType,
          contentLength: bytes.length,
        );
      })().timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw StateError('连接订阅服务器超时。');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _writeSubscription(String id, String content) async {
    await _ensureDirectories();
    final target = File(_profilePath(id));
    final temporary = File('${target.path}.download');
    await temporary.writeAsString(content, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  String _newSubscriptionId() =>
      'subscription-${DateTime.now().microsecondsSinceEpoch}.yaml';

  @override
  Future<List<ConfigProfile>> addSubscription({
    required String name,
    required String url,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('请输入订阅名称。');
    final cleanUrl = _subscriptionUri(url).toString();
    final download = await _downloadSubscription(cleanUrl);
    final id = _newSubscriptionId();
    await _writeSubscription(id, download.content);
    final state = await _readSettings();
    final names = _stateMap(state, 'profileNames')..[id] = cleanName;
    final types = _stateMap(state, 'profileTypes')..[id] = 'subscription';
    final urls = _stateMap(state, 'profileUrls')..[id] = cleanUrl;
    await _updateSettings(<String, dynamic>{
      'profileNames': names,
      'profileTypes': types,
      'profileUrls': urls,
    });
    return getConfigs();
  }

  @override
  Future<List<ConfigProfile>> updateSubscription({
    required String id,
    required String name,
    required String url,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('请输入订阅名称。');
    final state = await _readSettings();
    if (_stateMap(state, 'profileTypes')[id] != 'subscription') {
      throw StateError('所选配置不是机场订阅。');
    }
    final cleanUrl = _subscriptionUri(url).toString();
    final download = await _downloadSubscription(cleanUrl);
    await _writeSubscription(id, download.content);
    final names = _stateMap(state, 'profileNames')..[id] = cleanName;
    final urls = _stateMap(state, 'profileUrls')..[id] = cleanUrl;
    await _updateSettings(<String, dynamic>{
      'profileNames': names,
      'profileUrls': urls,
    });
    if (state['activeProfile'] == id) {
      await File(_configPath).writeAsString(
        await _runtimeConfigForCurrentMode(download.content),
        flush: true,
      );
    }
    return getConfigs();
  }

  @override
  Future<List<ConfigProfile>> refreshSubscription(String id) async {
    final state = await _readSettings();
    if (_stateMap(state, 'profileTypes')[id] != 'subscription') {
      throw StateError('所选配置不是机场订阅。');
    }
    final url = _stateMap(state, 'profileUrls')[id]?.toString();
    if (url == null || url.isEmpty) throw StateError('订阅链接不存在。');
    final download = await _downloadSubscription(url);
    await _writeSubscription(id, download.content);
    if (state['activeProfile'] == id) {
      await File(_configPath).writeAsString(
        await _runtimeConfigForCurrentMode(download.content),
        flush: true,
      );
    }
    return getConfigs();
  }

  @override
  Future<SubscriptionUrlTestResult> testSubscriptionUrl(String id) async {
    final state = await _readSettings();
    final url = _stateMap(state, 'profileUrls')[id]?.toString();
    if (url == null || url.isEmpty) throw StateError('订阅链接不存在。');
    try {
      final result = await _downloadSubscription(url);
      return SubscriptionUrlTestResult(
        success: true,
        responseTimeMs: result.responseTimeMs,
        statusCode: result.statusCode,
        contentLength: result.contentLength,
        contentType: result.contentType,
        message: '订阅链接有效，内容为 mihomo/Clash YAML 配置。',
      );
    } catch (error) {
      return SubscriptionUrlTestResult(
        success: false,
        message: error.toString().replaceFirst('Bad state: ', ''),
      );
    }
  }
}

class _SubscriptionDownload {
  const _SubscriptionDownload({
    required this.content,
    required this.responseTimeMs,
    required this.statusCode,
    required this.contentLength,
    required this.contentType,
  });

  final String content;
  final int responseTimeMs;
  final int statusCode;
  final int contentLength;
  final String? contentType;
}

class _RuntimePreferences {
  const _RuntimePreferences({
    required this.ipv6Enabled,
    required this.bypassLanEnabled,
  });

  final bool ipv6Enabled;
  final bool bypassLanEnabled;
}
