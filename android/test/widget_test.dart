import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/main.dart';
import 'package:mclash/pages/config_page.dart';

void main() {
  const channel = MethodChannel('mclash/native');
  var running = false;
  var hideFromRecents = false;
  var rejectRecentsSave = false;
  var recentsSaves = 0;

  setUp(() {
    running = false;
    hideFromRecents = false;
    rejectRecentsSave = false;
    recentsSaves = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setHideFromRecents') {
        recentsSaves++;
        if (rejectRecentsSave) {
          throw PlatformException(code: 'save_failed', message: '保存最近任务失败');
        }
        hideFromRecents = (call.arguments as Map)['enabled'] as bool;
        return null;
      }
      return switch (call.method) {
        'getUsageNoticeAccepted' => true,
        'getDeveloperModeEnabled' => false,
        'getConfigInfo' => <String, Object?>{},
        'isRunning' => running,
        'getHideFromRecents' => hideFromRecents,
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

    expect(find.text('Mclash'), findsNothing);
    expect(find.text('代理'), findsOneWidget);
    expect(find.text('规则'), findsOneWidget);
  });

  testWidgets(
      'recents visibility can change while running and survives reopening',
      (tester) async {
    running = true;
    final toggle = find.descendant(
      of: find.byKey(const ValueKey('hide-from-recents')),
      matching: find.byType(Switch),
    );
    Future<void> openSettings() async {
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(toggle, findsNothing);
      await tester.ensureVisible(find.text('隐藏多任务卡片'));
      await tester.tap(find.text('隐藏多任务卡片'));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    await openSettings();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(hideFromRecents, isTrue);
    expect(recentsSaves, 1);
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(find.text('关闭'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(toggle, findsNothing);
    expect(recentsSaves, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    await openSettings();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(hideFromRecents, isFalse);
    expect(recentsSaves, 2);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(running, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed recents save keeps previous value and allows retry',
      (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    final toggle = find.descendant(
      of: find.byKey(const ValueKey('hide-from-recents')),
      matching: find.byType(Switch),
    );
    expect(toggle, findsNothing);
    await tester.ensureVisible(find.text('隐藏多任务卡片'));
    await tester.tap(find.text('隐藏多任务卡片'));
    await tester.pumpAndSettle();
    rejectRecentsSave = true;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
    expect(find.textContaining('保存最近任务失败'), findsOneWidget);
    rejectRecentsSave = false;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(recentsSaves, 2);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
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
    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pump();
    await tester.tap(find.text('配置'));
    await tester.pump();
    await tester.tap(find.text('首页'));
    await tester.pump();
    expect(find.text('正在启动'), findsOneWidget);
    await tester.tap(find.text('配置'));
    await tester.pump();
    expect(tester.widget<ConfigPage>(find.byType(ConfigPage)).proxyRunning,
        isTrue);
    permission.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<ConfigPage>(find.byType(ConfigPage)).proxyRunning,
        isFalse);
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
    expect(tester.widget<ConfigPage>(find.byType(ConfigPage)).proxyRunning,
        isTrue);
    nativeStatus = 'stopped';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.widget<ConfigPage>(find.byType(ConfigPage)).proxyRunning,
        isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home uses core rates and totals and clears them when stopped',
      (tester) async {
    var running = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'getUsageNoticeAccepted' => true,
        'getDeveloperModeEnabled' => false,
        'getConfigInfo' => <String, Object?>{},
        'getProxyStatus' => running ? 'running' : 'stopped',
        'getDebugLoggingEnabled' => false,
        'getTrafficStats' => <String, int>{
            'rxBytes': running ? 3 * 1024 * 1024 : 0,
            'txBytes': running ? 4 * 1024 : 0,
            'rxBytesPerSecond': running ? 1024 * 1024 : 0,
            'txBytesPerSecond': running ? 2 * 1024 : 0,
          },
        _ => null,
      };
    });
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    // Totals stay constant, so rates must come from the core sample.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('1.0 MB/s'), findsOneWidget);
    expect(find.text('2.0 KB/s'), findsOneWidget);
    expect(find.text('本次 3.0 MB'), findsOneWidget);
    expect(find.text('本次 4.0 KB'), findsOneWidget);
    running = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('0 B/s'), findsNWidgets(2));
    expect(find.text('本次 0 B'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });
}
