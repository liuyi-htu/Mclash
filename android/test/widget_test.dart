import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/main.dart';
import 'package:mclash/pages/config_page.dart';

void main() {
  const channel = MethodChannel('mclash/native');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'getUsageNoticeAccepted' => true,
            'getDeveloperModeEnabled' => false,
            'getConfigInfo' => <String, Object?>{},
            'isRunning' => false,
            'getDebugLoggingEnabled' => false,
            'getTrafficStats' => <String, int>{'rxBytes': 0, 'txBytes': 0},
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows current home actions', (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pump();

    expect(find.text('Mclash'), findsOneWidget);
    expect(find.text('代理面板'), findsOneWidget);
    expect(find.text('代理规则'), findsOneWidget);
  });

  testWidgets('shows embedded bottom navigation', (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pump();

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('配置'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('returning home during VPN authorization keeps configs locked', (
    tester,
  ) async {
    final permission = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'getUsageNoticeAccepted' => true,
            'getDeveloperModeEnabled' => false,
            'getConfigInfo' => <String, Object?>{
              'exists': true,
              'fileName': 'Test',
            },
            'getConfigs' => <Object>[],
            'getProxyStatus' => 'stopped',
            'getDebugLoggingEnabled' => false,
            'getTrafficStats' => <String, int>{'rxBytes': 0, 'txBytes': 0},
            'prepareVpn' => permission.future,
            _ => null,
          };
        });
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('配置'));
    await tester.pump();
    await tester.tap(find.text('首页'));
    await tester.pump();
    expect(find.text('正在启动'), findsOneWidget);
    await tester.tap(find.text('配置'));
    await tester.pump();
    expect(tester.widget<ConfigPage>(find.byType(ConfigPage)).proxyRunning, isTrue);
    permission.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<ConfigPage>(find.byType(ConfigPage)).proxyRunning, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native startup locks configs when opening the app', (
    tester,
  ) async {
    var nativeStatus = 'starting';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'getUsageNoticeAccepted' => true,
            'getDeveloperModeEnabled' => false,
            'getConfigInfo' => <String, Object?>{'exists': true},
            'getConfigs' => <Object>[],
            'getProxyStatus' => nativeStatus,
            'getDebugLoggingEnabled' => false,
            'getTrafficStats' => <String, int>{'rxBytes': 0, 'txBytes': 0},
            _ => null,
          };
        });
    await tester.pumpWidget(const MclashApp());
    await tester.pump();
    await tester.pump();
    expect(find.text('正在启动'), findsOneWidget);
    await tester.tap(find.text('配置'));
    await tester.pump();
    expect(tester.widget<ConfigPage>(find.byType(ConfigPage)).proxyRunning, isTrue);
    nativeStatus = 'stopped';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.widget<ConfigPage>(find.byType(ConfigPage)).proxyRunning, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
