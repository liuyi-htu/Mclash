import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/models.dart';
import 'package:mclash/windows_proxy_platform_service.dart';

void main() {
  test('configuration selection and import reject transitional service states',
      () async {
    for (final state in [
      'running',
      'start_pending',
      'stop_pending',
      'unknown'
    ]) {
      final service = WindowsProxyPlatformService(
          serviceProcessRunner: (_, args) async =>
              ProcessResult(1, 0, '{"state":"$state"}', ''));
      await expectLater(service.selectConfig('test.yaml'), throwsStateError);
      await expectLater(service.importConfigs(), throwsStateError);
    }
  });

  test('service state alone is insufficient; PID and controller must be ready',
      () async {
    var snapshot = '{"state":"running","mihomoPid":0}';
    var healthy = false;
    final service = WindowsProxyPlatformService(
      serviceProcessRunner: (_, args) async =>
          ProcessResult(1, 0, snapshot, ''),
      controllerHealthCheck: () async => healthy,
    );
    expect(await service.getProxyStatus(), ProxyStatus.recovering);
    snapshot = '{"state":"running","mihomoPid":123}';
    expect(await service.getProxyStatus(), ProxyStatus.recovering);
    healthy = true;
    expect(await service.getProxyStatus(), ProxyStatus.running);
    for (final entry in {
      'stopped': ProxyStatus.stopped,
      'not_installed': ProxyStatus.stopped,
      'start_pending': ProxyStatus.starting,
      'stop_pending': ProxyStatus.stopping
    }.entries) {
      snapshot = '{"state":"${entry.key}"}';
      expect(await service.getProxyStatus(), entry.value);
    }
    snapshot = '{"state":"unknown","message":"access denied"}';
    await expectLater(service.getProxyStatus(), throwsStateError);
  });

  test('parallel status reads share one process and time out', () async {
    var calls = 0;
    final result = Completer<ProcessResult>();
    final service = WindowsProxyPlatformService(
      statusTimeout: const Duration(milliseconds: 20),
      serviceProcessRunner: (_, args) {
        calls++;
        return result.future;
      },
    );
    final first = service.getProxyStatus();
    final second = service.getProxyStatus();
    await Future.wait([
      expectLater(first, throwsA(isA<TimeoutException>())),
      expectLater(second, throwsA(isA<TimeoutException>())),
    ]);
    expect(calls, 1);
    result.complete(ProcessResult(1, 0, '{"state":"stopped"}', ''));
    expect(await service.getProxyStatus(), ProxyStatus.stopped);
    expect(calls, 2);
  });

  test(
      'service rejects concurrent core updates and releases lock after failure',
      () async {
    final gate = Completer<ProcessResult>();
    var calls = 0;
    final service =
        WindowsProxyPlatformService(serviceProcessRunner: (_, args) {
      calls++;
      return calls == 1
          ? gate.future
          : Future.value(ProcessResult(1, 0, '', ''));
    });
    final first = service.updateCore(CoreType.mihomo);
    await expectLater(service.updateCore(CoreType.mihomo), throwsStateError);
    expect(calls, 1);
    gate.complete(ProcessResult(1, 1, '', 'update failed'));
    await expectLater(first, throwsStateError);
    await service.updateCore(CoreType.mihomo);
    expect(calls, 2);
  });
}
