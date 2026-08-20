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
    service = WindowsProxyPlatformService(dataDir: dataDir.path);
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

  test('remembers the active profile for each core', () async {
    final separator = Platform.pathSeparator;
    await File(
      '${dataDir.path}${separator}profiles${separator}home.yaml',
    ).writeAsString('mixed-port: 7890\nproxies: []\n');
    await File(
      '${dataDir.path}${separator}profiles${separator}box.json',
    ).writeAsString('{"inbounds": []}\n');
    await File('${dataDir.path}${separator}state.json').writeAsString(
      jsonEncode(<String, dynamic>{
        'coreType': 'mihomo',
        'activeProfile': 'home.yaml',
        'mihomoPid': 42,
        'message': 'legacy runtime message',
        'profileNames': <String, dynamic>{
          'home.yaml': 'Home',
          'box.json': 'Box',
        },
      }),
    );

    await service.setCoreType(CoreType.singBox);
    var state = await readState();
    expect(
      await File(
        '${dataDir.path}${separator}settings.json',
      ).exists(),
      isTrue,
    );
    expect(state.containsKey('mihomoPid'), isFalse);
    expect(state.containsKey('message'), isFalse);
    expect(state['activeMihomoProfile'], 'home.yaml');
    expect(state['activeProfile'], isNull);

    await service.selectConfig('box.json');
    await service.setCoreType(CoreType.mihomo);
    state = await readState();
    expect(state['activeProfile'], 'home.yaml');

    await service.setCoreType(CoreType.singBox);
    state = await readState();
    expect(state['activeProfile'], 'box.json');
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
    await service.setCoreType(CoreType.singBox);
    await service.setCoreType(CoreType.mihomo);
    profiles = await service.getConfigs();

    expect(profiles, isEmpty);
    expect(await defaultProfile.exists(), isFalse);
    state = await readState();
    expect(state['defaultProfileDeleted'], isTrue);
  });
}
