import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/windows_proxy_platform_service.dart';
import 'package:mclash/models.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory dir;
  late File profile;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('config-save-');
    profile = File('${dir.path}\\profiles\\test.yaml');
    await profile.writeAsString('rules: [MATCH,DIRECT]\n');
  });
  tearDown(() async {
    // Windows separators are literal filename characters on Linux.
    for (final entry in dir.parent.listSync()) {
      if (entry.path.startsWith('${dir.path}\\')) {
        await entry.delete(recursive: true);
      }
    }
    await dir.delete(recursive: true);
  });
  test('invalid YAML never overwrites an inactive profile', () async {
    final service = WindowsProxyPlatformService(dataDir: dir.path);
    final before = await profile.readAsString();
    await expectLater(
        service.saveConfigContent(id: 'test.yaml', content: 'rules: ['),
        throwsA(isA<Exception>()));
    expect(await profile.readAsString(), before);
  });
  test('core rejection leaves original file intact', () async {
    final service = WindowsProxyPlatformService(
        dataDir: dir.path,
        serviceProcessRunner: (_, args) async =>
            ProcessResult(1, 1, '', 'invalid rule'));
    final before = await profile.readAsString();
    await expectLater(
        service.saveConfigContent(id: 'test.yaml', content: 'rules: [bad]\n'),
        throwsFormatException);
    expect(await profile.readAsString(), before);
  });
  test('successful validation replaces profile and preserves backup', () async {
    final service = WindowsProxyPlatformService(
        dataDir: dir.path,
        serviceProcessRunner: (_, args) async {
          expect(args.first, '-t');
          expect(await File(args.last).exists(), isTrue);
          return ProcessResult(1, 0, 'configuration test successful', '');
        });
    final before = await profile.readAsString();
    await service.saveConfigContent(id: 'test.yaml', content: 'rules: []\n');
    expect(await profile.readAsString(), 'rules: []\n');
    expect(await File('${profile.path}.bak').readAsString(), before);
  });
  test('controller override preserves nested secret and YAML comments',
      () async {
    final config = File('${dir.path}\\config.yaml');
    await config
        .writeAsString('# Keep me\ncustom:\n  secret: nested\nsecret: old\n');
    final service = WindowsProxyPlatformService(dataDir: dir.path);
    await service.setNetworkMode(NetworkMode.proxy);
    final content = await config.readAsString();
    final yaml = loadYaml(content);
    expect(yaml['custom']['secret'], 'nested');
    expect(yaml['secret'], '');
    expect(yaml['external-controller'], '127.0.0.1:9090');
    expect(content, contains('# Keep me'));
  });
}
