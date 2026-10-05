import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core_update_panel.dart';
import 'package:mclash/app_appearance.dart';

void main() {
  testWidgets('core panel fits narrow windows and large text in all states',
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
          for (final busy in [false, true]) {
            await tester.pumpWidget(MaterialApp(
                theme: buildPulseTheme(brightness),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: Scaffold(
                    body: AlertDialog(
                  insetPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  title: const Text('更新内核', style: TextStyle(fontSize: 18)),
                  contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  content: SizedBox(
                      width: 400,
                      child: SingleChildScrollView(
                          child: CoreUpdatePanel(
                        currentVersion: 'v1.19.32-alpha-long-version',
                        latestVersion: 'v1.19.33',
                        busy: busy,
                        updating: busy,
                        proxyEnabled: !busy,
                        message: '更新失败：网络连接中断，请检查代理连接后重试。',
                        onCheck: () {},
                        onUpdate: () {},
                      ))),
                ))));
            await tester.pump();
            expect(tester.takeException(), isNull);
            final button = tester.widget<FilledButton>(
                find.widgetWithText(FilledButton, busy ? '正在更新…' : '更新内核'));
            expect(button.onPressed, busy ? isNull : isNotNull);
            if (size.width == 320) {
              expect(
                  tester.getTopLeft(find.byType(FilledButton)).dy,
                  greaterThan(
                      tester.getBottomLeft(find.byType(OutlinedButton)).dy));
            }
          }
        }
      }
    }
  });
}
