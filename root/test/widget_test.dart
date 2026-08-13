import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/main.dart';

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
}
