import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core/models.dart';
import 'package:mclash/shared/subscription_management_page.dart';
import 'package:mclash/shared/config_management_page.dart';
import 'package:mclash/shared/management_style.dart';
import 'package:mclash/shared/app_appearance.dart';
import 'config_management_test.dart' show source;

void main() {
  testWidgets('management cards fit small windows, large text and tablets',
      (tester) async {
    addTearDown(tester.view.reset);
    const profile = ConfigProfile(
        id: 'test',
        name: '测试',
        type: 'subscription',
        active: false,
        exists: true,
        updatedAt: 0,
        url: 'https://example.org/a',
        subscriptionNames: {'https://example.org/a': '较长的机场名称用于检查小窗显示'},
        subscriptionUserInfo:
            'upload=0;download=0;total=1073741824;expire=1893456000');
    for (final size in [const Size(320, 540), const Size(1024, 768)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 1.4]) {
          for (final page in [
            SubscriptionManagementPage(
                profile: profile,
                proxyRunning: false,
                onEdit: (current, link) async => current,
                onReorder: (current, order) async => current,
                onUpdate: (current, link) async => current,
                onDelete: (current, link) async => current),
            ConfigManagementPage(
                content: source,
                mode: ConfigManagementMode.groups,
                onSave: (_) async {}),
            ConfigManagementPage(
                content: source,
                mode: ConfigManagementMode.rules,
                onSave: (_) async {}),
          ]) {
            await tester.pumpWidget(MaterialApp(
              theme: buildPulseTheme(brightness),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: page,
            ));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (final tile
                in tester.widgetList<ListTile>(find.byType(ListTile))) {
              if (tile.title == null) continue;
              final titles = tile.title is Text
                  ? find.byWidget(tile.title!)
                  : find.descendant(
                      of: find.byWidget(tile.title!),
                      matching: find.byType(Text));
              for (final text in titles.evaluate()) {
                final paragraph = tester
                    .renderObject<RenderParagraph>(find.byWidget(text.widget));
                expect(paragraph.text.style!.fontWeight, FontWeight.w400);
              }
            }
            final airport = find.text('较长的机场名称用于检查小窗显示');
            if (airport.evaluate().isNotEmpty) {
              expect(
                  tester
                      .renderObject<RenderParagraph>(airport)
                      .text
                      .style!
                      .fontWeight,
                  FontWeight.w400);
            }
            for (final element in find.byType(ManagementCard).evaluate()) {
              final width = tester.getSize(find.byWidget(element.widget)).width;
              expect(width, lessThanOrEqualTo(808));
              expect(width, lessThanOrEqualTo(size.width - 32));
            }
          }
        }
      }
    }
  });
}
