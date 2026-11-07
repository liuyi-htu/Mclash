import 'package:mclash/core_connection_settings.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/windows_proxy_platform_service.dart';
import 'package:mclash/models.dart';
import 'package:yaml/yaml.dart';

class _Service extends WindowsProxyPlatformService {
  _Service(String dir, ServiceProcessRunner runner)
      : super(dataDir: dir, serviceProcessRunner: runner);
  @override
  Future<void> syncSystemProxy() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
      'running subscription and name edits preserve current snapshot until next start',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('mclash-deferred-config-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var host = 'old.example';
    var fail = false;
    server.listen((request) async {
      request.response.statusCode = fail ? 503 : 200;
      request.response
          .write('proxies: [{name: A, type: http, server: $host, port: 80}]');
      await request.response.close();
    });
    var state = 'stopped';
    var starts = 0;
    final service = _Service(dir.path, (_, args) async {
      if (args.first == 'start') {
        starts++;
        state = 'running';
      }
      return ProcessResult(
          1, 0, jsonEncode({'state': state, 'installed': true}), '');
    });
    final settings = File('${dir.path}\\settings.json');
    try {
      await service.addSubscription(
          name: '旧配置', url: 'http://127.0.0.1:${server.port}/sub');
      final saved =
          jsonDecode(await settings.readAsString()) as Map<String, dynamic>;
      final id = saved['activeProfile'] as String;
      await settings.writeAsString(jsonEncode(saved));
      final runtime = File('${dir.path}\\config.yaml');
      final before = await runtime.readAsString();
      state = 'running';
      final previousConnection =
          await service.getRunningCoreConnectionSettings();
      const pending = CoreConnectionSettings(
          controller: '0.0.0.0:9191', secret: 'test:# secret', mixedPort: 7891);
      await service.saveCoreConnectionSettings(pending);
      expect(
          (await service.getCoreConnectionSettings()).toMap(), pending.toMap());
      expect((await service.getRunningCoreConnectionSettings()).toMap(),
          previousConnection.toMap());
      await service.setNetworkMode(NetworkMode.tun);
      await service.setIpv6Enabled(true);
      await service.setBypassLanEnabled(false);
      expect(await service.getNetworkMode(), NetworkMode.tun);
      expect((await service.getConfigInfo()).runtimeMode, 'proxy');
      final pendingState = jsonDecode(await settings.readAsString());
      expect(pendingState['runningBypassLanEnabled'], true);
      expect(pendingState['bypassLanEnabled'], false);
      expect(await runtime.readAsString(), before);
      host = 'new.example';
      await service.refreshSubscription(id);
      expect(await runtime.readAsString(), before);
      expect(await service.getRuntimeConfigContent(), before);
      expect(await service.getConfigContent(id), contains('new.example'));
      expect(starts, 0);
      await service.renameConfig(id: id, name: '新配置');
      expect((await service.getConfigInfo()).fileName, '旧配置');
      fail = true;
      final draft = await service.getConfigContent(id);
      await expectLater(
          service.refreshSubscription(id), throwsA(isA<HttpException>()));
      expect(await service.getConfigContent(id), draft);
      expect(await runtime.readAsString(), before);
      expect((await service.getConfigInfo()).fileName, '旧配置');
      state = 'stopped';
      await service.start();
      expect(starts, 1);
      expect((await service.getConfigInfo()).runtimeMode, 'tun');
      final currentRuntime = loadYaml(await service.getRuntimeConfigContent());
      expect(currentRuntime['tun']['enable'], true);
      expect(currentRuntime['ipv6'], true);
      expect(currentRuntime['external-controller'], pending.controller);
      expect(currentRuntime['secret'], pending.secret);
      expect(currentRuntime['mixed-port'], pending.mixedPort);
      expect((await service.getRunningCoreConnectionSettings()).toMap(),
          pending.toMap());
      expect(jsonDecode(await settings.readAsString())['runtimeController'],
          pending.toMap());
      expect(
          jsonDecode(await settings.readAsString())['runningBypassLanEnabled'],
          false);
      expect((await service.getConfigInfo()).fileName, '新配置');
      expect(await service.getRuntimeConfigContent(), contains('new.example'));
      expect(await service.getRuntimeConfigContent(),
          isNot(contains('old.example')));
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
