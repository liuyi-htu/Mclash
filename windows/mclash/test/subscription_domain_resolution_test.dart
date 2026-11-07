import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/windows_proxy_platform_service.dart';
import 'package:yaml/yaml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
      'per-airport setting survives reload and refresh, keeps raw cache and restores domains when disabled',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('mclash-domain-subscription-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.write(
          'proxies: [{name: Node, type: trojan, server: localhost, port: 443, password: test}]');
      await request.response.close();
    });
    WindowsProxyPlatformService service() => WindowsProxyPlatformService(
        dataDir: dir.path,
        serviceProcessRunner: (_, __) async =>
            ProcessResult(1, 0, '{"state":"stopped"}', ''));
    final first = 'http://127.0.0.1:${server.port}/a';
    final second = 'http://127.0.0.1:${server.port}/b';
    try {
      var instance = service();
      await instance.addSubscription(
          name: '机场', url: first, subscriptionResolveDomains: {first: true});
      final settingsFile = File('${dir.path}\\settings.json');
      final id =
          (jsonDecode(await settingsFile.readAsString())['profileUrls'] as Map)
              .keys
              .single as String;
      Map<String, dynamic> resolutions() =>
          Map<String, dynamic>.from(jsonDecode(settingsFile.readAsStringSync())[
              'profileSubscriptionResolveDomains'][id]);
      final profile = File('${dir.path}\\profiles\\$id');
      final cache = File('${profile.path}.subscriptions.json');
      List<dynamic> nodes() =>
          (loadYaml(profile.readAsStringSync())['proxies'] as List);
      expect(nodes()[0]['server'], '127.0.0.1');
      expect(nodes()[0]['sni'], 'localhost');
      expect(
          loadYaml(jsonDecode(await cache.readAsString())[first])['proxies'][0]
              ['server'],
          'localhost');
      instance = service();
      expect(resolutions()[first], isTrue);
      await instance.refreshSubscription(id);
      expect(nodes()[0]['server'], '127.0.0.1');
      await instance.editSubscriptionAirport(id, name: '第二机场', url: second);
      expect(nodes()[0]['server'], '127.0.0.1');
      expect(nodes()[1]['server'], 'localhost');
      await instance.refreshSubscription(id, url: second);
      expect(nodes()[0]['server'], '127.0.0.1');
      expect(nodes()[1]['server'], 'localhost');
      await instance.editSubscriptionAirport(id,
          oldUrl: first, name: '第一机场', url: first, resolveDomains: false);
      expect(nodes()[0]['server'], 'localhost');
      expect(nodes()[0]['sni'], isNull);
      expect(resolutions()[first], isFalse);
      await instance.editSubscriptionAirport(id,
          oldUrl: first, name: '第一机场', url: first, resolveDomains: true);
      final moved = '$first?new';
      await instance.editSubscriptionAirport(id,
          oldUrl: first, name: '第一机场', url: moved);
      final settings = resolutions();
      expect(settings[moved], isTrue);
      expect(settings.containsKey(first), isFalse);
      await instance.editSubscriptionAirport(id, oldUrl: moved);
      expect(resolutions().containsKey(moved), isFalse);
      expect(nodes().single['server'], 'localhost');
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
