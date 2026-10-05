import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/models.dart';
import 'package:mclash/add_action_button.dart';
import 'package:mclash/add_node_page.dart';
import 'package:mclash/subscription_management_page.dart';

void main() {
  testWidgets('node dialog uses compact type and fits large text and keyboard',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 100);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final scenario in [
      (const Size(320, 640), 1.0),
      (const Size(320, 640), 1.8),
      (const Size(900, 360), 1.4),
    ]) {
      tester.view.physicalSize = scenario.$1;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scenario.$2),
          ),
          child: child!,
        ),
        home: AddNodePage(
          nodes: const [],
          onDelete: (_) async => [],
          onSave: (_) async =>
              throw const FormatException('节点链接无效，请检查协议、地址和端口后重新粘贴完整的节点链接。'),
        ),
      ));
      await tester.tap(find.byTooltip('添加节点'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.titleTextStyle!.fontSize, 18);
      expect(
          tester.widget<TextField>(find.byType(TextField)).style!.fontSize, 14);
      expect(
          tester
              .getCenter(find
                  .descendant(
                      of: find.byType(AlertDialog),
                      matching: find.byType(Material))
                  .first)
              .dx,
          closeTo(scenario.$1.width / 2, 1));
      expect(
          tester
              .getCenter(find
                  .descendant(
                      of: find.byType(AlertDialog),
                      matching: find.byType(Material))
                  .first)
              .dy,
          closeTo((scenario.$1.height - 100) / 2, 1));
      await tester.enterText(find.byType(TextField), 'invalid://node');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('节点链接无效'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
  });

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
    final buttonRect = tester.getRect(find.byType(AddActionButton));
    final pageRect = tester.getRect(find.byType(Scaffold));
    expect(buttonRect.center.dx, greaterThan(700));
    // Reserve navigation bar space independently of the button's size.
    expect(pageRect.bottom - buttonRect.bottom,
        closeTo(80 + kFloatingActionButtonMargin, 1));
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
