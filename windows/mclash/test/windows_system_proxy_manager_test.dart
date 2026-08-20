import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/windows_system_proxy_manager.dart';

void main() {
  late Directory temporaryDirectory;
  late File backup;
  late List<List<String>> commands;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'mclash-system-proxy-',
    );
    backup = File('${temporaryDirectory.path}\\proxy-backup.json');
    commands = <List<String>>[];
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  ProcessResult result(int exitCode, [String stdout = '', String stderr = '']) =>
      ProcessResult(1, exitCode, stdout, stderr);

  test('backs up existing values once and restores them', () async {
    final registry = <String, (String, String)>{
      'ProxyEnable': ('REG_DWORD', '0x1'),
      'ProxyServer': ('REG_SZ', 'proxy.example:8080'),
      'ProxyOverride': ('REG_SZ', '<local>;intranet.example'),
    };
    final original = Map<String, (String, String)>.from(registry);
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments,
    ) async {
      commands.add(List<String>.from(arguments));
      if (arguments.first == 'query') {
        final name = arguments.last;
        final value = registry[name];
        if (value == null) return result(1);
        return result(0, '    $name    ${value.$1}    ${value.$2}\r\n');
      }
      final name = arguments[3];
      if (arguments.first == 'add') {
        registry[name] = (arguments[5], arguments[7]);
      } else if (arguments.first == 'delete') {
        registry.remove(name);
      }
      return result(0);
    }

    final manager = WindowsSystemProxyManager(
      backupPath: backup.path,
      processRunner: runner,
    );
    await manager.enable(port: 7890, bypass: '<local>;192.168.*');
    await manager.enable(port: 7891, bypass: '<local>;10.*');

    // Three reads create the original backup; the repeated enable performs one
    // ownership check without replacing that original snapshot.
    expect(commands.where((item) => item.first == 'query'), hasLength(4));
    expect(await backup.exists(), isTrue);
    await manager.restore();

    expect(await backup.exists(), isFalse);
    for (final entry in original.entries) {
      expect(
        commands,
        contains(
          equals(<String>[
            'add',
            WindowsSystemProxyManager.internetSettingsKey,
            '/v',
            entry.key,
            '/t',
            entry.value.$1,
            '/d',
            entry.value.$2,
            '/f',
          ]),
        ),
      );
    }
  });

  test('removes registry values that did not originally exist', () async {
    final registry = <String, (String, String)>{};
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments,
    ) async {
      commands.add(List<String>.from(arguments));
      final name = arguments[3];
      if (arguments.first == 'query') {
        final value = registry[name];
        if (value == null) return result(1);
        return result(0, '    $name    ${value.$1}    ${value.$2}\r\n');
      }
      if (arguments.first == 'add') {
        registry[name] = (arguments[5], arguments[7]);
      } else if (arguments.first == 'delete') {
        registry.remove(name);
      }
      return result(0);
    }

    final manager = WindowsSystemProxyManager(
      backupPath: backup.path,
      processRunner: runner,
    );
    await manager.enable(port: 7890, bypass: '<local>');
    final saved = jsonDecode(await backup.readAsString()) as Map;
    expect(saved['version'], 2);
    expect(saved['original'], <String, dynamic>{
      'ProxyEnable': null,
      'ProxyServer': null,
      'ProxyOverride': null,
    });

    await manager.restore();
    expect(commands.where((item) => item.first == 'delete'), hasLength(3));
  });

  test('does not change the registry when no backup exists', () async {
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments,
    ) async {
      commands.add(List<String>.from(arguments));
      return result(0);
    }

    final manager = WindowsSystemProxyManager(
      backupPath: backup.path,
      processRunner: runner,
    );
    await manager.restore();

    expect(commands, isEmpty);
  });

  test('does not overwrite a proxy changed by another application', () async {
    final registry = <String, (String, String)>{
      'ProxyEnable': ('REG_DWORD', '0x0'),
      'ProxyServer': ('REG_SZ', 'old.example:8080'),
      'ProxyOverride': ('REG_SZ', '<local>'),
    };
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments,
    ) async {
      commands.add(List<String>.from(arguments));
      final name = arguments[3];
      if (arguments.first == 'query') {
        final value = registry[name];
        if (value == null) return result(1);
        return result(0, '    $name    ${value.$1}    ${value.$2}\r\n');
      }
      if (arguments.first == 'add') {
        registry[name] = (arguments[5], arguments[7]);
      } else if (arguments.first == 'delete') {
        registry.remove(name);
      }
      return result(0);
    }

    final manager = WindowsSystemProxyManager(
      backupPath: backup.path,
      processRunner: runner,
    );
    await manager.enable(port: 7890, bypass: '<local>');
    registry['ProxyServer'] = ('REG_SZ', 'other.example:1080');
    commands.clear();

    await manager.restore();

    expect(await backup.exists(), isFalse);
    expect(
      commands.where(
        (item) => item.first == 'add' || item.first == 'delete',
      ),
      isEmpty,
    );
    expect(registry['ProxyServer']?.$2, 'other.example:1080');
  });

  test('restores a legacy backup when the current proxy is Mclash', () async {
    await backup.writeAsString(
      jsonEncode(<String, dynamic>{
        'ProxyEnable': <String, String>{
          'type': 'REG_DWORD',
          'data': '0x0',
        },
        'ProxyServer': <String, String>{
          'type': 'REG_SZ',
          'data': 'old.example:8080',
        },
        'ProxyOverride': null,
      }),
    );
    final registry = <String, (String, String)>{
      'ProxyEnable': ('REG_DWORD', '0x1'),
      'ProxyServer': ('REG_SZ', '127.0.0.1:7890'),
      'ProxyOverride': ('REG_SZ', '<local>'),
    };
    Future<ProcessResult> runner(
      String executable,
      List<String> arguments,
    ) async {
      final name = arguments[3];
      if (arguments.first == 'query') {
        final value = registry[name];
        if (value == null) return result(1);
        return result(0, '    $name    ${value.$1}    ${value.$2}\r\n');
      }
      if (arguments.first == 'add') {
        registry[name] = (arguments[5], arguments[7]);
      } else if (arguments.first == 'delete') {
        registry.remove(name);
      }
      return result(0);
    }

    final manager = WindowsSystemProxyManager(
      backupPath: backup.path,
      processRunner: runner,
    );
    await manager.restore();

    expect(registry['ProxyEnable']?.$2, '0x0');
    expect(registry['ProxyServer']?.$2, 'old.example:8080');
    expect(registry.containsKey('ProxyOverride'), isFalse);
  });
}
