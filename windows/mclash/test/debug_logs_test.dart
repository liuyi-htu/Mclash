import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/windows_proxy_platform_service.dart';

void main() {
  late Directory temporaryDirectory;
  late WindowsProxyPlatformService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'mclash-debug-logs-',
    );
    service = WindowsProxyPlatformService(
      dataDir: temporaryDirectory.path,
      serviceProcessRunner: (executable, arguments) async {
        if (arguments.first == 'clear-runtime-message') {
          final runtime = File(
            '${temporaryDirectory.path}\\runtime-state.json',
          );
          final decoded = await runtime.exists()
              ? jsonDecode(await runtime.readAsString()) as Map<String, dynamic>
              : <String, dynamic>{};
          decoded['message'] = '';
          await runtime.writeAsString(jsonEncode(decoded));
        }
        return ProcessResult(1, 0, '', '');
      },
    );
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('lists and reads each supported log independently', () async {
    final logs = await service.getDebugLogs();
    expect(logs.map((log) => log.id), <String>[
      'service.log',
      'mihomo.log',
      'sing-box.log',
      'update.log',
    ]);
    expect(logs.first.displayName, 'Mclash.log');

    final directory = Directory('${temporaryDirectory.path}\\logs');
    await directory.create(recursive: true);
    await File('${directory.path}\\service.log').writeAsString('service entry');
    await File('${directory.path}\\mihomo.log').writeAsString('mihomo entry');

    expect(await service.getDebugLogContent('service.log'), 'service entry');
    expect(await service.getDebugLogContent('mihomo.log'), 'mihomo entry');
  });

  test(
    'rejects unknown log names and clears logs plus startup error',
    () async {
      final directory = Directory('${temporaryDirectory.path}\\logs');
      await directory.create(recursive: true);
      await File(
        '${directory.path}\\service.log',
      ).writeAsString('service entry');
      await File('${directory.path}\\mihomo.log').writeAsString('mihomo entry');
      await File('${directory.path}\\update.log').writeAsString('update entry');
      await File(
        '${temporaryDirectory.path}\\runtime-state.json',
      ).writeAsString(
        jsonEncode(<String, dynamic>{
          'mihomoPid': 123,
          'message': 'startup failed',
        }),
      );

      await expectLater(
        service.getDebugLogContent('..\\config.yaml'),
        throwsArgumentError,
      );
      await service.clearDebugLogs();

      expect(
        await File('${directory.path}\\service.log').readAsString(),
        isEmpty,
      );
      expect(
        await File('${directory.path}\\mihomo.log').readAsString(),
        isEmpty,
      );
      expect(
        await File('${directory.path}\\update.log').readAsString(),
        isEmpty,
      );
      final state =
          jsonDecode(
                await File(
                  '${temporaryDirectory.path}\\runtime-state.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(state['message'], isEmpty);
      expect(state['mihomoPid'], 123);
    },
  );
}
