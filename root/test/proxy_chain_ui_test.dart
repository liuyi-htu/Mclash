import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/proxy_chain_dialog.dart';

void main() {
  Future<void> open(WidgetTester tester,
      {List<String> chain = const ['A', 'B'],
      Future<void> Function(List<String>, List<String>)? save}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => TextButton(
                onPressed: () => showProxyChainDialog(
                  context: context,
                  nodes: const ['A', 'B', 'C', 'D'],
                  prepend: true,
                  initialNodes: chain,
                  initialTargets: const ['C'],
                  onSave: save ?? (targets, chain) async {},
                ),
                child: const Text('打开'),
              )),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('search and select all preserve hidden selections',
      (tester) async {
    List<String>? saved;
    await open(tester, chain: ['A'], save: (_, chain) async => saved = chain);
    await tester.tap(find.byTooltip('选择前置节点'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'd');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'D'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'A'), findsNothing);
    expect(find.widgetWithText(CheckboxListTile, 'C'), findsNothing);
    await tester.tap(find.text('全选'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('前置节点（2）'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, ['A', 'D']);
  });

  testWidgets('drag order and inline removal persist on save', (tester) async {
    List<String>? saved;
    await open(tester, save: (_, chain) async => saved = chain);
    final handle = find.byIcon(Icons.drag_handle);
    final gesture = await tester.startGesture(tester.getCenter(handle.last));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    final list =
        tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    final ordered = List.generate(
        list.itemCount,
        (index) => list.itemBuilder(
            tester.element(find.byType(ReorderableListView)), index));
    expect(ordered.map((tile) => tile.key),
        [const ValueKey('B'), const ValueKey('A')]);
    await tester.tap(find.byTooltip('移除前置节点 A'));
    await tester.pumpAndSettle();
    expect(find.text('前置节点（1）'), findsOneWidget);
    await tester.tap(find.byTooltip('移除作用节点 C'));
    await tester.pumpAndSettle();
    expect(find.text('作用节点（0）'), findsOneWidget);
    await tester.tap(find.byTooltip('选择作用节点'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'A'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'B'), findsNothing);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'C'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, ['B']);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 480), const Size(1024, 768)]) {
    testWidgets('chain dialog fits $size and search keyboard', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await open(tester);
      expect(find.text('作用节点（1）'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('选择前置节点'));
      await tester.tap(find.byTooltip('选择前置节点'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('暂无匹配节点'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
