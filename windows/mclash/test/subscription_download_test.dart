import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/windows_proxy_platform_service.dart';
import 'package:mclash/subscription_filter.dart';
import 'package:yaml/yaml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
      'download, refresh and edit embed nodes; failed refresh keeps saved config',
      () async {
    final dir = await Directory.systemTemp.createTemp('subscription-download-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var response = 'proxies: [{name: HK first, type: ss, server: example.org}]';
    server.listen((request) async {
      request.response.write(response);
      await request.response.close();
    });
    final service = WindowsProxyPlatformService(
      dataDir: dir.path,
      serviceProcessRunner: (_, __) async =>
          ProcessResult(1, 0, '{"state":"stopped"}', ''),
    );
    try {
      final url = 'http://127.0.0.1:${server.port}/subscription';
      await service.addSubscription(name: 'airport', url: url);
      final settings =
          jsonDecode(await File('${dir.path}\\settings.json').readAsString());
      final id = (settings['profileUrls'] as Map).keys.single as String;
      final file = File('${dir.path}\\profiles\\$id');
      var config = loadYaml(await file.readAsString());
      expect(config['proxy-providers'], isNull);
      expect(config['proxies'][0]['name'], 'HK first');
      expect(config['rules'].last, 'MATCH,🌍 国外');
      // Save through the same route as the menu; the active runtime must follow.
      settings['activeProfile'] = id;
      await File('${dir.path}\\settings.json')
          .writeAsString(jsonEncode(settings));
      await service.saveConfigContent(
          id: id,
          content: editSubscriptionFilter(
              await file.readAsString(), domesticGroup, '广州'));
      final runtime =
          loadYaml(await File('${dir.path}\\config.yaml').readAsString());
      expect(runtime['proxy-groups'][0]['filter'], '广州');
      response =
          'proxies: [{name: 广州 refreshed, type: ss, server: example.org}]';
      await service.refreshSubscription(id);
      config = loadYaml(await file.readAsString());
      expect(config['proxy-groups'][0]['proxies'], ['DIRECT']);
      expect(config['proxy-groups'][0]['filter'], '广州');
      response = 'proxies: [{name: 韩国 edited, type: ss, server: example.org}]';
      await service.updateSubscription(id: id, name: 'edited', url: url);
      expect(loadYaml(await file.readAsString())['proxies'][0]['name'],
          '韩国 edited');
      final before = await file.readAsString();
      response = 'proxies: []';
      await expectLater(service.refreshSubscription(id), throwsFormatException);
      expect(await file.readAsString(), before);
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
