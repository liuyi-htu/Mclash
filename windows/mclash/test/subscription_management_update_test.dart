import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/models.dart';
import 'package:mclash/subscription_management_page.dart';

const profile = ConfigProfile(
  id: 'test',
  name: '测试',
  type: 'subscription',
  active: false,
  exists: true,
  updatedAt: 0,
  url: 'https://example.org/a\nhttps://example.org/b',
  subscriptionNames: {
    'https://example.org/a': '机场甲',
    'https://example.org/b': '机场乙'
  },
);

void main() {
  testWidgets(
      'only updating airport shows progress and failed update can retry',
      (tester) async {
    final pending = Completer<ConfigProfile?>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: SubscriptionManagementPage(
      profile: profile,
      proxyRunning: false,
      onEdit: (current, link) async => current,
      onReorder: (current, order) async => current,
      onDelete: (current, link) async => current,
      onUpdate: (current, link) async {
        expect(link, 'https://example.org/b');
        calls++;
        return calls == 1 ? pending.future : current;
      },
    )));
    await tester.tap(find.byTooltip('更新机场').last);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        find.descendant(
            of: find.byTooltip('更新机场').first,
            matching: find.byType(CircularProgressIndicator)),
        findsNothing);
    for (final button in tester
        .widgetList<IconButton>(find.byType(IconButton))
        .where((button) => button.tooltip == '删除机场')) {
      expect(button.onPressed, isNull);
    }
    pending.completeError(StateError('更新失败'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('更新失败'), findsOneWidget);
    await tester.tap(find.byTooltip('更新机场').last);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.textContaining('更新失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'progress pauses beneath update confirmation and clears on dismiss',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => SubscriptionManagementPage(
                  profile: profile,
                  proxyRunning: false,
                  onEdit: (current, link) async => current,
                  onReorder: (current, order) async => current,
                  onUpdate: (current, link) async {
                    await showDialog<void>(
                        context: context,
                        builder: (context) =>
                            const AlertDialog(title: Text('已更新')));
                    return current;
                  },
                ))));
    await tester.tap(find.byTooltip('更新机场').first);
    await tester.pumpAndSettle();
    expect(find.text('已更新'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
