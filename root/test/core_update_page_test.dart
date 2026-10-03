import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/pages/core_update_page.dart';

void main() {
  const channel = MethodChannel('mclash/native');
  var status = 'stopped';
  var updates = 0;
  var fail = false;
  Completer<Map<String, Object>>? pending;

  setUp(() {
    status = 'stopped';
    updates = 0;
    fail = false;
    pending = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkCoreUpdate':
          return {'currentVersion': 'v1.19.31', 'latestVersion': 'v1.19.32'};
        case 'getProxyStatus':
          return status;
        case 'updateCore':
          updates++;
          if (fail) {
            throw PlatformException(code: 'native_error', message: '校验失败');
          }
          return pending?.future ??
              {'version': 'v1.19.32', 'installed': true, 'updated': true};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CoreUpdateDialog()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检测版本'));
    await tester.pumpAndSettle();
    expect(find.text('当前 v1.19.31 / 官方 v1.19.32'), findsOneWidget);
  }

  testWidgets('updates version and prevents duplicate updates while busy',
      (tester) async {
    pending = Completer<Map<String, Object>>();
    await open(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(updates, 1);
    pending!
        .complete({'version': 'v1.19.32', 'installed': true, 'updated': true});
    await tester.pumpAndSettle();
    expect(find.text('当前 v1.19.32 / 官方 v1.19.32'), findsOneWidget);
    expect(find.text('mihomo 内核更新完成，下次启动代理时生效'), findsOneWidget);
  });

  testWidgets('running proxy blocks download', (tester) async {
    status = 'running';
    await open(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(updates, 0);
    expect(find.textContaining('请先停止代理再更新内核'), findsOneWidget);
  });

  testWidgets('failed update retains version and allows retry', (tester) async {
    fail = true;
    await open(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('当前 v1.19.31 / 官方 v1.19.32'), findsOneWidget);
    expect(find.textContaining('校验失败'), findsOneWidget);
    fail = false;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('当前 v1.19.32 / 官方 v1.19.32'), findsOneWidget);
  });
}
