import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/main.dart';
import 'package:mclash/shared/app_appearance.dart';

void main() {
  const channel = MethodChannel('mclash/native');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => switch (call.method) {
                  'getUsageNoticeAccepted' => true,
                  'getConfigInfo' => <String, Object?>{},
                  'getConfigProfiles' => <Object>[],
                  'getProxyStatus' => 'stopped',
                  'isRunning' => false,
                  'getDeveloperModeEnabled' => false,
                  'getDebugLoggingEnabled' => false,
                  'getTrafficStats' => {'rxBytes': 0, 'txBytes': 0},
                  _ => null,
                });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  testWidgets('Pulse is the only theme with uniform arrow-free settings cards',
      (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .destinations
            .length,
        4);
    expect(find.text('平台连接检测'), findsNothing);
    expect(find.text('代理规则'), findsNothing);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('Pulse'), findsOneWidget);
    expect(find.text('Simple'), findsNothing);
    expect(find.byType(SettingsCard), findsNWidgets(5));
    expect(find.byType(ListTile), findsNWidgets(6));
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('配置'));
    await tester.pumpAndSettle();
    expect(find.text('配置中心'), findsNothing);
    await tester.tap(find.text('代理'));
    await tester.pumpAndSettle();
    expect(find.text('代理面板'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
