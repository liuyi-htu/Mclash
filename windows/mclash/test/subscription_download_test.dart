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
  test(
      'multiple airports prefix nodes; single refresh retains other caches and failed refresh is atomic',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('multiple-subscriptions-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final counts = <String, int>{};
    var secondName = '香港';
    var failSecond = false;
    var firstUsage = 'upload=0;download=10;total=1000;expire=0';
    var secondUsage = 'upload=0;download=20;total=2000;expire=0';
    server.listen((request) async {
      final path = request.uri.path;
      counts[path] = (counts[path] ?? 0) + 1;
      if (path == '/b' && failSecond) {
        request.response.statusCode = 503;
      } else {
        request.response.headers.set(
            'Subscription-Userinfo', path == '/a' ? firstUsage : secondUsage);
        final name = path == '/a' ? '香港' : secondName;
        request.response.write(
            'proxies: [{name: $name, type: http, server: example.org, port: 80}]');
      }
      await request.response.close();
    });
    final service = WindowsProxyPlatformService(
        dataDir: dir.path,
        serviceProcessRunner: (_, __) async =>
            ProcessResult(1, 0, '{"state":"stopped"}', ''));
    final first = 'http://127.0.0.1:${server.port}/a';
    final second = 'http://127.0.0.1:${server.port}/b';
    try {
      await service.addSubscription(
          name: '合并',
          url: '$first\n$second',
          subscriptionNames: {first: '第一机场', second: '第二机场'});
      final settings = File('${dir.path}\\settings.json');
      final state = jsonDecode(await settings.readAsString());
      final id = (state['profileUrls'] as Map).keys.single as String;
      expect(state['profileUrls'][id], '$first\n$second');
      expect(state['profileSubscriptionNames'][id],
          {first: '第一机场', second: '第二机场'});
      expect(state['profileSubscriptionInfos'][id],
          {first: firstUsage, second: secondUsage});
      final profile = File('${dir.path}\\profiles\\$id');
      final cache = File('${profile.path}.subscriptions.json');
      List<String> names(String content) =>
          (loadYaml(content)['proxies'] as List)
              .map((node) => node['name'] as String)
              .toList();
      expect(names(await profile.readAsString()), ['1-香港', '2-香港']);
      await service.selectConfig(id);
      secondName = '日本';
      final savedFirstUsage = firstUsage;
      firstUsage =
          'total=9000;expire=0'; // An unselected airport must not be downloaded.
      secondUsage = 'upload=0;download=30;total=2000;expire=0';
      await service.refreshSubscription(id, url: second);
      expect(counts, {'/a': 1, '/b': 2});
      expect(
          jsonDecode(await settings.readAsString())['profileSubscriptionInfos']
              [id],
          {first: savedFirstUsage, second: secondUsage});
      expect(
          jsonDecode(await settings.readAsString())['profileSubscriptionNames']
              [id],
          {first: '第一机场', second: '第二机场'});
      expect(names(await profile.readAsString()), ['1-香港', '2-日本']);
      final runtime = File('${dir.path}\\config.yaml');
      expect(names(await runtime.readAsString()), ['1-香港', '2-日本']);
      final before = await profile.readAsString();
      final beforeCache = await cache.readAsString();
      final beforeSettings = await settings.readAsString();
      final beforeRuntime = await runtime.readAsString();
      failSecond = true;
      await expectLater(
          service.refreshSubscription(id, url: second), throwsStateError);
      expect(counts, {'/a': 1, '/b': 3});
      expect(await profile.readAsString(), before);
      expect(await cache.readAsString(), beforeCache);
      expect(await settings.readAsString(), beforeSettings);
      expect(await runtime.readAsString(), beforeRuntime);
      final testResult = await service.testSubscriptionUrl(id);
      expect(testResult.success, isFalse);
      expect(await cache.readAsString(), beforeCache);
      failSecond = false;
      final beforeOrderRequests = Map<String, int>.from(counts);
      await service.editSubscriptionAirport(id, order: [second, first]);
      expect(counts,
          beforeOrderRequests); // Reordering uses the existing node cache.
      expect(names(await profile.readAsString()), ['1-日本', '2-香港']);
      await service.editSubscriptionAirport(id,
          oldUrl: first, name: '第一机场更名', url: first);
      expect(counts['/b'], beforeOrderRequests['/b']);
      expect(counts['/a'], beforeOrderRequests['/a']! + 1);
      expect(
          jsonDecode(await settings.readAsString())['profileSubscriptionNames']
              [id],
          {first: '第一机场更名', second: '第二机场'});
      expect(
          jsonDecode(await settings.readAsString())['profileSubscriptionInfos']
              [id],
          {first: firstUsage, second: secondUsage});
      final third = 'http://127.0.0.1:${server.port}/c';
      await service.editSubscriptionAirport(id,
          oldUrl: first, name: '第三机场', url: third);
      expect(counts['/c'], 1);
      expect(counts['/b'], beforeOrderRequests['/b']);
      expect(
          jsonDecode(await settings.readAsString())['profileSubscriptionNames']
              [id],
          {third: '第三机场', second: '第二机场'});
      expect(
          jsonDecode(await settings.readAsString())['profileSubscriptionInfos']
              [id],
          {third: secondUsage, second: secondUsage});
      final beforeDeletion = Map<String, int>.from(counts);
      await service.editSubscriptionAirport(id, oldUrl: third);
      expect(counts, beforeDeletion);
      expect(names(await profile.readAsString()), ['日本']);
      expect(
          jsonDecode(await settings.readAsString())['profileSubscriptionNames']
              [id],
          {second: '第二机场'});
      expect(
          jsonDecode(await settings.readAsString())['profileSubscriptionInfos']
              [id],
          {second: secondUsage});
      await service.editSubscriptionAirport(id, name: '重新添加', url: first);
      expect(counts['/b'], beforeDeletion['/b']);
      expect(names(await profile.readAsString()), ['1-日本', '2-香港']);
      expect(
          jsonDecode(await settings.readAsString())['profileSubscriptionNames']
              [id],
          {second: '第二机场', first: '重新添加'});
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
