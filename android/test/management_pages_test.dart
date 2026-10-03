import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core/models.dart';
import 'package:mclash/shared/add_action_button.dart';
import 'package:mclash/shared/add_node_page.dart';
import 'package:mclash/shared/subscription_management_page.dart';

void main() {
  testWidgets(
      'node page adds through its floating button and refreshes its list',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AddNodePage(
        nodes: const [],
        onSave: (link) async {
          if (link != 'valid') throw const FormatException('节点链接无效');
          return ['新节点'];
        },
        onDelete: (name) async => [],
      ),
    ));
    expect(find.text('添加节点（0）'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    final position = tester.getCenter(find.byType(AddActionButton));
    expect(position.dx, greaterThan(700));
    expect(position.dy, greaterThan(400));
    await tester.tap(find.byTooltip('添加节点'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('节点链接无效'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'valid');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('新节点'), findsOneWidget);
    expect(find.text('添加节点（1）'), findsOneWidget);
    await tester.tap(find.byTooltip('删除手动节点'));
    await tester.pumpAndSettle();
    expect(find.text('暂无手动节点'), findsOneWidget);
    expect(find.text('添加节点（0）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'subscription page refreshes after adding through its floating button',
      (tester) async {
    ConfigProfile profile(String urls) => ConfigProfile(
        id: 'test',
        name: '测试',
        type: 'subscription',
        active: false,
        exists: true,
        updatedAt: 0,
        url: urls);
    await tester.pumpWidget(MaterialApp(
      home: SubscriptionManagementPage(
        profile: profile('https://example.org/a'),
        proxyRunning: false,
        onEdit: (current, link) async {
          expect(link, isNull);
          return profile('${current.url}\nhttps://example.org/b');
        },
        onReorder: (current, order) async => profile(order.join('\n')),
      ),
    ));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ReorderableDragStartListener), findsOneWidget);
    await tester.tap(find.byTooltip('添加机场'));
    await tester.pumpAndSettle();
    expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));
    expect(find.byType(AddActionButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
