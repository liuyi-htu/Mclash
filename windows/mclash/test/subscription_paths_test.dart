import 'package:mclash/subscription_config.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/windows_proxy_platform_service.dart';
import 'package:yaml/yaml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('subscription builder emits clean paths on creation and regeneration',
      () {
    final template =
        File('../../assets/default-config.yaml').readAsStringSync();
    const source =
        r'proxies: [{name: Node, type: vmess, server: example.org, port: 80, uuid: test, network: http, http-opts: {path: ["\/"]}}]';
    String? previous;
    for (var generation = 0; generation < 3; generation++) {
      final generated =
          buildSubscriptionConfig(template, source, previousConfig: previous);
      expect(generated, isNot(contains(r'\/')));
      expect(loadYaml(generated)['proxies'][0]['http-opts']['path'], ['/']);
      previous = generated;
    }
  });
  test('airport creation and automatic regeneration keep clean path values',
      () async {
    HttpOverrides.global = null;
    final dir =
        await Directory.systemTemp.createTemp('mclash-subscription-paths-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.write(
          r'proxies: [{name: Node, type: vmess, server: example.org, port: 80, uuid: test, network: http, http-opts: {path: ["\/"]}}]');
      await request.response.close();
    });
    final service = WindowsProxyPlatformService(
        dataDir: dir.path,
        serviceProcessRunner: (_, __) async =>
            ProcessResult(1, 0, '{"state":"stopped"}', ''));
    try {
      await service.addSubscription(
          name: '机场', url: 'http://127.0.0.1:${server.port}/sub');
      final id =
          jsonDecode(await File('${dir.path}\\settings.json').readAsString())[
              'activeProfile'] as String;
      for (var generation = 0; generation < 3; generation++) {
        if (generation > 0) await service.refreshSubscription(id);
        final content = await service.getConfigContent(id);
        expect(content, isNot(contains(r'\/')));
        expect(loadYaml(content)['proxies'][0]['http-opts']['path'], ['/']);
        expect(await service.getRuntimeConfigContent(), isNot(contains(r'\/')));
      }
    } finally {
      await server.close(force: true);
      for (final entry in dir.parent.listSync()) {
        if (entry.path.startsWith('${dir.path}\\')) {
          await entry.delete(recursive: true);
        }
      }
      await dir.delete(recursive: true);
    }
  });
}
