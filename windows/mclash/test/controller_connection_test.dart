import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/models.dart';
import 'package:mclash/windows_proxy_platform_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'health checks use active runtime address and secret despite pending settings',
      () async {
    HttpOverrides.global = null;
    final directory =
        await Directory.systemTemp.createTemp('mclash-controller-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var authenticated = false;
    server.listen((request) async {
      authenticated = request.uri.path == '/version' &&
          request.headers.value(HttpHeaders.authorizationHeader) ==
              'Bearer active-test';
      request.response.statusCode = authenticated ? 200 : 401;
      request.response.write(jsonEncode({'version': 'v1.19.33'}));
      await request.response.close();
    });
    try {
      await File('${directory.path}\\config.yaml').writeAsString(
          'external-controller: 0.0.0.0:${server.port}\nsecret: active-test\nmixed-port: 7890\n');
      await File('${directory.path}\\settings.json').writeAsString(jsonEncode({
        'coreConnection': {
          'controller': '127.0.0.1:1',
          'secret': 'pending-test',
          'mixedPort': 7892
        }
      }));
      final service = WindowsProxyPlatformService(
          dataDir: directory.path,
          serviceProcessRunner: (_, __) async => ProcessResult(
              1, 0, jsonEncode({'state': 'running', 'mihomoPid': 42}), ''));
      expect(await service.getProxyStatus(), ProxyStatus.running);
      expect(authenticated, true);
      expect(
          (await service.getCoreConnectionSettings()).secret, 'pending-test');
    } finally {
      await server.close(force: true);
      for (final entry in directory.parent.listSync()) {
        if (entry.path.startsWith('${directory.path}\\')) {
          await entry.delete(recursive: true);
        }
      }
      await directory.delete(recursive: true);
    }
  });
}
