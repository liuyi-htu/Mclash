import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/main.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  const channel = MethodChannel('mclash/native');
  var running = false;
  var developerModeEnabled = false;
  var registrationReads = 0;
  var registrationExports = 0;

  setUp(() {
    running = false;
    developerModeEnabled = false;
    registrationReads = 0;
    registrationExports = 0;
    PackageInfo.setMockInitialValues(
      appName: 'Mclash Root',
      packageName: 'com.liuyihtu.mclash.root',
      version: '2.3.0',
      buildNumber: '2',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDeviceRegistration') {
        registrationReads++;
        return <String, Object>{
          'json': '{"format":"mclash-device-registration"}',
          'installationId': 'root-installation-test',
          'fingerprint': 'root-fingerprint-test',
          'createdAtEpochSeconds': 1,
        };
      }
      if (call.method == 'exportDeviceRegistration') {
        registrationExports++;
        return 'content://test/root-device.json';
      }
      if (call.method == 'enableDeveloperMode') {
        developerModeEnabled = true;
        return null;
      }
      if (call.method == 'disableDeveloperMode') {
        developerModeEnabled = false;
        return null;
      }
      return switch (call.method) {
        'getUsageNoticeAccepted' => true,
        'getDeveloperModeEnabled' => developerModeEnabled,
        'getConfigInfo' => <String, Object?>{},
        'getRootSettings' => <String, Object?>{'bypassLan': true},
        'isRunning' => running,
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

    expect(find.text('Mclash Root'), findsOneWidget);
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

  testWidgets(
      'hidden developer mode unlocks after five taps and can be disabled',
      (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pump();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('开发者模式'), findsNothing);
    await tester.tap(find.text('关于 Mclash Root'));
    await tester.pumpAndSettle();
    final title = find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Mclash Root'));
    for (var i = 0; i < 4; i++) {
      await tester.tap(title);
      await tester.pump();
    }
    expect(developerModeEnabled, isFalse);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(developerModeEnabled, isTrue);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开发者模式'));
    await tester.pumpAndSettle();
    expect(find.text('设备登记'), findsOneWidget);
    await tester.tap(find.text('关闭开发者模式'));
    await tester.pumpAndSettle();
    expect(developerModeEnabled, isFalse);
    expect(find.text('开发者模式'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('refreshes service status when returning to the foreground',
      (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pump();
    expect(find.text('未启动'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    running = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.text('已连接'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    running = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.text('未启动'), findsOneWidget);
  });

  testWidgets('developer menu opens device registration and exports JSON',
      (tester) async {
    developerModeEnabled = true;
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开发者模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设备登记'));
    await tester.pumpAndSettle();
    expect(registrationReads, 1);
    expect(find.text('设备身份已就绪'), findsOneWidget);
    expect(find.text('root-installation-test'), findsOneWidget);
    expect(find.text('root-fingerprint-test'), findsOneWidget);
    await tester.tap(find.text('导出设备登记 JSON'));
    await tester.pumpAndSettle();
    expect(registrationExports, 1);
    expect(find.text('已保存：content://test/root-device.json'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('running proxy locks settings while keeping logs readable',
      (tester) async {
    running = true;
    developerModeEnabled = true;
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    for (final title in ['TProxy 参数', '分应用代理', '开发者模式']) {
      final tile =
          find.ancestor(of: find.text(title), matching: find.byType(InkWell));
      expect(tester.widget<InkWell>(tile).onTap, isNull);
    }
    await tester.tap(find.text('调试日志'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull);
    expect(
        tester
            .widget<TextButton>(find.ancestor(
              of: find.text('清除'),
              matching: find.byWidgetPredicate((widget) => widget is TextButton),
            ))
            .onPressed,
        isNull);
    expect(find.text('Mclash.log'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    running = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final apps =
        find.ancestor(of: find.text('分应用代理'), matching: find.byType(InkWell));
    expect(tester.widget<InkWell>(apps).onTap, isNotNull);
  });
  testWidgets(
      'Root settings expose TProxy parameters without VPN tunnel controls',
      (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pump();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TProxy 参数'));
    await tester.pumpAndSettle();
    expect(find.text('清理残留规则'), findsNothing);
    expect(find.text('绕过局域网'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('VPN MTU'), findsNothing);
    expect(find.text('启用 IPv6'), findsNothing);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
