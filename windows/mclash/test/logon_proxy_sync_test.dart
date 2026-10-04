import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/windows_proxy_platform_service.dart';

void main() {
  test(
      'autostart registers a non-elevated per-user logon sync and removes it on disable',
      () async {
    final registry = <List<String>>[];
    final commands = <String>[];
    final service = WindowsProxyPlatformService(
        dataDir: r'C:\Program Files\Mclash\data',
        systemProxyBackupPath: r'C:\Users\User\Mclash\backup.json',
        registryProcessRunner: (_, args) async {
          registry.add(args);
          return ProcessResult(1, 0, '', '');
        },
        serviceProcessRunner: (_, args) async {
          commands.add(args.first);
          return ProcessResult(
              1,
              0,
              args.first == 'status-json'
                  ? '{"installed":true,"state":"stopped"}'
                  : '',
              '');
        });
    await service.setServiceAutoStartEnabled(true);
    expect(registry.single.first, 'add');
    final command = registry.single[registry.single.indexOf('/d') + 1];
    expect(command, contains('sync-user-proxy'));
    expect(command, contains('--data-dir "C:\\Program Files\\Mclash\\data"'));
    expect(command,
        contains('--proxy-backup "C:\\Users\\User\\Mclash\\backup.json"'));
    expect(command, isNot(contains('--elevated')));
    await service.setServiceAutoStartEnabled(false);
    expect(registry.last.first, 'delete');
    expect(commands,
        containsAllInOrder(['enable-autostart', 'disable-autostart']));
  });
  test('failed logon registration rolls back service autostart', () async {
    final commands = <String>[];
    final service = WindowsProxyPlatformService(
        registryProcessRunner: (_, args) async =>
            ProcessResult(1, 1, '', 'access denied'),
        serviceProcessRunner: (_, args) async {
          commands.add(args.first);
          return ProcessResult(
              1,
              0,
              args.first == 'status-json'
                  ? '{"installed":true,"state":"stopped"}'
                  : '',
              '');
        });
    await expectLater(
        service.setServiceAutoStartEnabled(true), throwsStateError);
    expect(commands,
        containsAllInOrder(['enable-autostart', 'disable-autostart']));
  });
}
