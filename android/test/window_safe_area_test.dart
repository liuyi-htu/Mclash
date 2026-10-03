import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/window_safe_area.dart';

void main() {
  const channel = MethodChannel('mclash/window');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  testWidgets(
      'small window removes duplicate top space and restores fullscreen',
      (tester) async {
    double? inset;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => inset);
    MediaQueryData? observed;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.fromLTRB(8, 30, 8, 20),
          viewPadding: const EdgeInsets.fromLTRB(8, 30, 8, 20),
          viewInsets: const EdgeInsets.only(bottom: 100),
        ),
        child: WindowSafeArea(child: child!),
      ),
      home: Builder(builder: (context) {
        observed = MediaQuery.of(context);
        return const Scaffold(body: Text('内容'));
      }),
    ));
    await tester.pumpAndSettle();
    expect(observed!.padding.top, 30);
    inset = 0;
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(observed!.padding, const EdgeInsets.fromLTRB(8, 0, 8, 20));
    expect(observed!.viewPadding.top, 0);
    expect(observed!.viewInsets.bottom, 100);
    // Preserve a real caption/cutout inset still overlapping the content.
    inset = 12;
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(observed!.padding.top, 12);
    // Native layout can settle after Flutter's resize notification.
    inset = 0;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'mclash/window',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('windowChanged'),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(observed!.padding.top, 0);
    expect(observed!.viewPadding.top, 0);
    // Exiting the small window restores the original fullscreen safe area.
    inset = null;
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(observed!.padding.top, 30);
    expect(observed!.viewPadding.top, 30);
    await tester.pumpWidget(const SizedBox());
  });
}
