import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/windows_proxy_platform_service.dart';
import 'package:mclash/subscription_filter.dart';
import 'package:mclash/subscription_host.dart';
import 'package:mclash/proxy_chain.dart';
import 'package:yaml/yaml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('slow streaming subscription succeeds while chunks keep arriving',
      () async {
    final dir = await Directory.systemTemp.createTemp('slow-subscription-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final chunks = [
      'proxies: [',
      '{name: KR slow, type: http, server: example.org, port: 80}',
      ']'
    ];
    server.listen((request) async {
      request.response.bufferOutput = false;
      for (final chunk in chunks) {
        request.response.write(chunk);
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
      await request.response.close();
    });
    final service = WindowsProxyPlatformService(
        dataDir: dir.path,
        subscriptionIdleTimeout: const Duration(seconds: 1),
        serviceProcessRunner: (_, __) async =>
            ProcessResult(1, 0, '{"state":"stopped"}', ''));
    final elapsed = Stopwatch()..start();
    try {
      await service.addSubscription(
          name: 'Slow', url: 'http://127.0.0.1:${server.port}/slow');
      expect(elapsed.elapsed, greaterThan(const Duration(seconds: 1)));
      final state =
          jsonDecode(await File('${dir.path}\\settings.json').readAsString());
      final id = (state['profileUrls'] as Map).keys.single as String;
      expect(loadYaml(await service.getConfigContent(id))['proxies'][0]['name'],
          'KR slow');
    } finally {
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });

  test(
      'fresh installation is empty; manually added subscriptions support Host and chains',
      () async {
    final dir = await Directory.systemTemp.createTemp('default-subscription-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.write(
          'proxies: [{name: KR default, type: vmess, network: http, server: example.org}, {name: KR ws, type: vmess, network: ws, server: example.org}]');
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/subscription';
    final service = WindowsProxyPlatformService(
      dataDir: dir.path,
      serviceProcessRunner: (_, __) async =>
          ProcessResult(1, 0, '{"state":"stopped"}', ''),
    );
    try {
      expect((await service.getConfigInfo()).exists, isFalse);
      expect(await service.getConfigs(), isEmpty);
      expect((await service.getConfigInfo()).exists, isFalse);
      expect(await service.getConfigs(), isEmpty);
      expect(requests, 0);
      expect(await File('${dir.path}\\config.yaml').exists(), isFalse);
      expect(
          await File('${dir.path}\\profiles\\default.yaml').exists(), isFalse);
      await service.addSubscription(name: 'Manual', url: url);
      final state =
          jsonDecode(await File('${dir.path}\\settings.json').readAsString());
      final id = (state['profileUrls'] as Map).keys.single as String;
      expect(state['profileNames'][id], 'Manual');
      expect(state['profileTypes'][id], 'subscription');
      expect(state['profileUrls'][id], url);
      await service.selectConfig(id);
      final runtime =
          loadYaml(await File('${dir.path}\\config.yaml').readAsString());
      expect(runtime['proxies'][0]['name'], 'KR default');
      expect(runtime['proxy-providers'], isNull);
      expect(runtime['proxy-groups'][1]['filter'], isNull);
      expect(runtime['proxy-groups'][1]['proxies'], ['KR default', 'KR ws']);
      final profile = File('${dir.path}\\profiles\\$id');
      await service.saveConfigContent(
        id: id,
        content:
            editSubscriptionHost(await profile.readAsString(), 'new.example'),
      );
      expect(requests, 1); // Saving Host must not download the subscription.
      final saved = loadYaml(await profile.readAsString());
      final applied =
          loadYaml(await File('${dir.path}\\config.yaml').readAsString());
      final preview = loadYaml(await service.getRuntimeConfigContent());
      for (final config in [saved, applied, preview]) {
        expect(config['proxies'][0]['http-opts']['headers']['Host'],
            ['new.example']);
        expect(
            config['proxies'][1]['ws-opts']['headers']['Host'], 'new.example');
      }
      await service.saveConfigContent(
        id: id,
        content: setProxyChain(
            await profile.readAsString(), 'KR default', 'KR ws',
            prepend: true),
      );
      final chainedFile =
          loadYaml(await File('${dir.path}\\config.yaml').readAsString());
      final chainedPreview = loadYaml(await service.getRuntimeConfigContent());
      expect(chainedFile['proxies'][0]['dialer-proxy'], 'KR ws');
      expect(chainedPreview['proxies'][0]['dialer-proxy'], 'KR ws');
      expect(chainedFile['proxy-groups'], applied['proxy-groups']);
      await service.getConfigs();
      expect(requests, 1);
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
  test(
      'download, refresh and edit embed nodes; failed refresh keeps saved config',
      () async {
    final dir = await Directory.systemTemp.createTemp('subscription-download-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var response = 'proxies: [{name: HK first, type: ss, server: example.org}]';
    String? userInfo = 'upload=10;download=100;total=1000;expire=2000000000';
    server.listen((request) async {
      if (userInfo != null) {
        request.response.headers.set('Subscription-Userinfo', userInfo);
      }
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
      expect(settings['profileSubscriptionInfo'][id], userInfo);
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
      expect(runtime['proxy-groups'][0]['filter'], isNull);
      expect(readSubscriptionFilter(await file.readAsString(), domesticGroup),
          '广州');
      response =
          'proxies: [{name: 广州 refreshed, type: ss, server: example.org}]';
      userInfo = 'upload=10;download=200;total=1000;expire=2000000000';
      await service.refreshSubscription(id);
      final refreshedSettings =
          jsonDecode(await File('${dir.path}\\settings.json').readAsString());
      expect(refreshedSettings['profileSubscriptionInfo'][id], userInfo);
      config = loadYaml(await file.readAsString());
      expect(config['proxy-groups'][0]['proxies'], ['DIRECT', '广州 refreshed']);
      expect(config['proxy-groups'][0]['filter'], isNull);
      response = 'proxies: [{name: 韩国 edited, type: ss, server: example.org}]';
      userInfo = null;
      await service.updateSubscription(id: id, name: 'edited', url: url);
      final editedSettings =
          jsonDecode(await File('${dir.path}\\settings.json').readAsString());
      expect(editedSettings['profileSubscriptionInfo'][id], isNull);
      expect(loadYaml(await file.readAsString())['proxies'][0]['name'],
          '韩国 edited');
      final before = await file.readAsString();
      response = 'proxies: []';
      userInfo = 'total=123';
      await expectLater(service.refreshSubscription(id), throwsFormatException);
      expect(await file.readAsString(), before);
      final failedSettings =
          jsonDecode(await File('${dir.path}\\settings.json').readAsString());
      expect(failedSettings['profileSubscriptionInfo'][id], isNull);
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
