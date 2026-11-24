import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/pages/app_selector_page.dart';

void main() {
  testWidgets(
      'loads real icons and caches them through selection and search; missing icons fall back',
      (tester) async {
    const channel = MethodChannel('mclash/native');
    final requests = <String, int>{};
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getInstalledApps':
          return [
            for (final name in ['Browser', 'Missing', 'Broken'])
              {
                'packageName': 'org.example.$name',
                'label': name,
                'isSystemApp': false
              }
          ];
        case 'getSelectedPackages':
          return <String>[];
        case 'getMode':
          return 'excludeSelected';
        case 'getAppIcon':
          final name = (call.arguments as Map)['packageName'] as String;
          requests[name] = (requests[name] ?? 0) + 1;
          if (name.endsWith('Broken')) {
            throw PlatformException(code: 'icon_unavailable');
          }
          return name.endsWith('Browser') ? bytes : null;
        default:
          throw StateError('Unexpected call: ${call.method}');
      }
    });
    try {
      await tester.pumpWidget(
          const MaterialApp(home: AppSelectorPage(proxyRunning: true)));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(((image.image as ResizeImage).imageProvider as MemoryImage).bytes,
          bytes);
      expect(find.byIcon(Icons.android_rounded), findsNWidgets(2));
      await tester.tap(find.text('Browser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Browser');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(requests, {
        'org.example.Browser': 1,
        'org.example.Missing': 1,
        'org.example.Broken': 1
      });
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}
