import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/pages/app_selector_page.dart';
import 'package:mclash/shared/app_appearance.dart';

void main() {
  const channel = MethodChannel('mclash/native');
  Map<Object?, Object?>? saved;
  setUp(() {
    saved = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getInstalledApps':
          return [
            {
              'packageName': 'org.example.browser',
              'label': '一个很长的浏览器应用名称用于检查字体显示',
              'isSystemApp': false
            },
            {
              'packageName': 'org.example.system',
              'label': '系统应用',
              'isSystemApp': true
            },
          ];
        case 'getSelectedPackages':
          return ['org.example.system'];
        case 'getMode':
          return 'excludeSelected';
        case 'saveAppFilter':
          saved = Map<Object?, Object?>.from(call.arguments as Map);
          return null;
      }
      throw StateError('Unexpected method: ${call.method}');
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  testWidgets(
      'application fonts and mode selection fit small screens and large text',
      (tester) async {
    addTearDown(tester.view.reset);
    for (final size in [
      const Size(320, 480),
      const Size(390, 844),
      const Size(1024, 768)
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 1.6]) {
          await tester.pumpWidget(MaterialApp(
              key: UniqueKey(),
              theme: buildPulseTheme(brightness),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: const AppSelectorPage()));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('仅代理选中的'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.enterText(find.byType(TextField), 'browser');
          await tester.pumpAndSettle();
          expect(find.text('系统应用'), findsNothing);
          expect(find.text('org.example.browser'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          await tester.tap(find.text('保存'));
          await tester.pumpAndSettle();
          expect(saved!['mode'], 'onlySelected');
          expect(saved!['packageNames'],
              containsAll(['org.example.system', 'org.example.browser']));
        }
      }
    }
  });
}
