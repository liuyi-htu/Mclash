import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core/models.dart';
import 'package:mclash/shared/app_appearance.dart';
import 'package:mclash/shared/subscription_management_page.dart';

ConfigProfile airports(List<String> links) => ConfigProfile(
      id: 'stack',
      name: '配置',
      type: 'subscription',
      active: true,
      exists: true,
      updatedAt: 0,
      url: links.join('\n'),
      subscriptionNames: const {
        'https://example.org/a': '机场甲',
        'https://example.org/b': '机场乙',
        'https://example.org/c': '机场丙'
      },
    );
const links = [
  'https://example.org/a',
  'https://example.org/b',
  'https://example.org/c'
];

void main() {
  testWidgets(
      'embedded stack expands for actions and keeps reordered airports on collapse',
      (tester) async {
    List<String>? order;
    String? updated;
    var current = airports(links);
    await tester.pumpWidget(MaterialApp(
        theme: buildPulseTheme(Brightness.light),
        home: Scaffold(
            body: SingleChildScrollView(
                child: SubscriptionManagementPage(
          embedded: true,
          profile: current,
          proxyRunning: false,
          onEdit: (profile, link) async => profile,
          onUpdate: (profile, link) async {
            updated = link;
            return profile;
          },
          onReorder: (profile, value) async {
            order = value;
            current = airports(value);
            return current;
          },
        )))));
    expect(find.text('3 个机场'), findsOneWidget);
    expect(find.byTooltip('更新机场'), findsNothing);
    final collapsedHeight =
        tester.getSize(find.byType(SubscriptionManagementPage)).height;
    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('更新机场'), findsNWidgets(3));
    expect(tester.getSize(find.byType(SubscriptionManagementPage)).height,
        greaterThan(collapsedHeight));
    await tester.tap(find.byTooltip('更新机场').last);
    await tester.pumpAndSettle();
    expect(updated, links.last);
    final handles = find.byType(ReorderableDragStartListener);
    final gesture = await tester.startGesture(tester.getCenter(handles.last));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -5));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(handles.first));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(order, [links[2], links[0], links[1]]);
    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(find.text('机场丙 · 机场甲 · 机场乙'), findsOneWidget);
    expect(find.byTooltip('更新机场'), findsNothing);
    expect(tester.getSize(find.byType(SubscriptionManagementPage)).height,
        collapsedHeight);
    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('机场丙')).dy,
        lessThan(tester.getTopLeft(find.text('机场甲')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending update cannot collapse and deletion to one airport removes stack controls',
      (tester) async {
    final pending = Completer<ConfigProfile?>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SubscriptionManagementPage(
      embedded: true,
      profile: airports(links.take(2).toList()),
      proxyRunning: false,
      onEdit: (profile, link) async => profile,
      onUpdate: (profile, link) => pending.future,
      onDelete: (profile, link) async => airports([links.first]),
      onReorder: (profile, value) async => profile,
    )))));
    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更新机场').first);
    await tester.pump();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '收起'))
            .onPressed,
        isNull);
    pending.complete(airports(links.take(2).toList()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除机场').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('更新机场'), findsOneWidget);
    expect(find.text('机场甲'), findsOneWidget);
    expect(find.text('展开'), findsNothing);
    expect(find.text('收起'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'many airports stay compact at narrow width and large text while running',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final many = List.generate(30, (i) => 'https://example.org/$i');
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: SubscriptionManagementPage(
              embedded: true,
              profile: airports(many),
              proxyRunning: true,
              onEdit: (profile, link) async => profile,
              onUpdate: (profile, link) async => profile,
              onReorder: (profile, value) async => profile,
            ))))));
    expect(tester.getSize(find.byType(SubscriptionManagementPage)).height,
        lessThan(200));
    expect(find.byTooltip('更新机场'), findsNothing);
    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('更新机场'), findsNWidgets(30));
    for (final button
        in tester.widgetList<IconButton>(find.byType(IconButton))) {
      expect(button.onPressed, isNull);
    }
    expect(tester.takeException(), isNull);
  });
}
