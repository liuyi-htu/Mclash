import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/models.dart';
import 'package:mclash/windows_proxy_platform_service.dart';

void main() {
  late Directory dataDir;
  late WindowsProxyPlatformService service;

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('mclash-core-state-');
    await Directory(
      '${dataDir.path}${Platform.pathSeparator}profiles',
    ).create(recursive: true);
    service = WindowsProxyPlatformService(
        dataDir: dataDir.path,
        serviceProcessRunner: (_, args) async =>
            ProcessResult(1, 0, '{"state":"stopped"}', ''));
  });

  tearDown(() async {
    await dataDir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> readState() async {
    final file = File('${dataDir.path}${Platform.pathSeparator}settings.json');
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  }

  for (final settingsFile in ['settings.json', 'state.json']) {
    test('migrates legacy sing-box selection from $settingsFile', () async {
      const yaml = 'mixed-port: 7890\nproxies: []\n';
      await File('${dataDir.path}\\profiles\\home.yaml').writeAsString(yaml);
      final legacyProfile = File('${dataDir.path}\\profiles\\box.json');
      await legacyProfile.writeAsString('{"inbounds": []}');
      await File('${dataDir.path}\\$settingsFile').writeAsString(jsonEncode({
        'coreType': 'sing-box',
        'activeProfile': 'box.json',
        'activeMihomoProfile': 'home.yaml',
        'activeSingBoxProfile': 'box.json',
        'networkMode': 'tun',
        'debugLoggingEnabled': true,
        'profileNames': {'home.yaml': 'Home', 'box.json': 'Box'},
        if (settingsFile == 'state.json') 'mihomoPid': 42,
        if (settingsFile == 'state.json') 'message': 'legacy runtime message',
      }));

      expect(await service.getCoreType(), CoreType.mihomo);
      final profiles = await service.getConfigs();
      expect(profiles.map((p) => p.id), ['home.yaml']);
      expect(profiles.single.active, isTrue);
      final state = await readState();
      expect(state['coreType'], 'mihomo');
      expect(state['activeProfile'], 'home.yaml');
      expect(state['debugLoggingEnabled'], isTrue);
      expect(state.containsKey('activeSingBoxProfile'), isFalse);
      expect(state.containsKey('mihomoPid'), isFalse);
      expect(state.containsKey('message'), isFalse);
      final runtime = await File('${dataDir.path}\\config.yaml').readAsString();
      expect(runtime, contains('enable: true'));
      expect(await legacyProfile.readAsString(), '{"inbounds": []}');
      await expectLater(service.selectConfig('box.json'), throwsArgumentError);
      await expectLater(
          service.saveConfigContent(id: 'box.json', content: '{}'),
          throwsArgumentError);
    });
  }

  test('restores remembered YAML when legacy core has no active profile',
      () async {
    await File('${dataDir.path}\\profiles\\home.yaml')
        .writeAsString('mixed-port: 7890\nproxies: []\n');
    await File('${dataDir.path}\\settings.json').writeAsString(jsonEncode({
      'coreType': 'sing-box',
      'activeProfile': null,
      'activeMihomoProfile': 'home.yaml',
    }));
    expect(await service.getCoreType(), CoreType.mihomo);
    expect((await readState())['activeProfile'], 'home.yaml');
    expect((await service.getConfigInfo()).exists, isTrue);
  });

  test('clears legacy JSON selection when no Mihomo profile was saved',
      () async {
    await File('${dataDir.path}\\settings.json').writeAsString(jsonEncode({
      'coreType': 'sing-box',
      'activeProfile': 'box.json',
      'activeSingBoxProfile': 'box.json',
    }));
    expect(await service.getCoreType(), CoreType.mihomo);
    final state = await readState();
    expect(state['activeProfile'], isNull);
    expect(state.containsKey('activeSingBoxProfile'), isFalse);
    expect((await service.getConfigInfo()).exists, isFalse);
  });

  test('changing only network mode keeps the current profile', () async {
    final separator = Platform.pathSeparator;
    await File(
      '${dataDir.path}${separator}profiles${separator}selected.yaml',
    ).writeAsString('mixed-port: 7890\nproxies: []\n');
    await File('${dataDir.path}${separator}state.json').writeAsString(
      jsonEncode(<String, dynamic>{
        'coreType': 'mihomo',
        'activeProfile': 'selected.yaml',
        'activeMihomoProfile': 'older.yaml',
      }),
    );

    await service.setCoreType(CoreType.mihomo);

    final state = await readState();
    expect(state['activeProfile'], 'selected.yaml');
    expect(state['activeMihomoProfile'], 'selected.yaml');
  });

  test('deleted default profile is not generated again', () async {
    final separator = Platform.pathSeparator;
    final runtime = File('${dataDir.path}${separator}config.yaml');
    final defaultProfile = File(
      '${dataDir.path}${separator}profiles${separator}default.yaml',
    );
    await runtime.writeAsString('mixed-port: 7890\nproxies: []\n');

    var profiles = await service.getConfigs();
    expect(profiles.map((profile) => profile.id), <String>['default.yaml']);
    expect(profiles.single.active, isTrue);

    profiles = await service.deleteConfig('default.yaml');
    expect(profiles, isEmpty);
    expect(await defaultProfile.exists(), isFalse);
    expect(await runtime.exists(), isFalse);
    var state = await readState();
    expect(state['defaultProfileDeleted'], isTrue);
    expect(state['activeProfile'], isNull);
    expect(state['activeMihomoProfile'], isNull);

    // Even if a runtime config appears again, changing modes must not recreate
    // the deleted generated profile.
    await runtime.writeAsString('mixed-port: 7890\nproxies: []\n');
    await service.setNetworkMode(NetworkMode.tun);
    await service.setCoreType(CoreType.mihomo);
    profiles = await service.getConfigs();

    expect(profiles, isEmpty);
    expect(await defaultProfile.exists(), isFalse);
    state = await readState();
    expect(state['defaultProfileDeleted'], isTrue);
  });
}
