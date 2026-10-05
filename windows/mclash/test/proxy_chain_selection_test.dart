import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/proxy_chain_dialog.dart';

void main() {
  testWidgets(
      'chain and target selections exclude each other and release deselected nodes',
      (tester) async {
    List<String>? savedTargets;
    List<String>? savedChain;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => TextButton(
                onPressed: () => showProxyChainDialog(
                  context: context,
                  nodes: ['A', 'B', 'C'],
                  prepend: true,
                  initialNodes: ['A'],
                  initialTargets: ['B'],
                  onSave: (current, other) async {
                    savedTargets = current;
                    savedChain = other;
                  },
                ),
                child: const Text('打开'),
              )),
    ));
    Future<void> open(String label) async {
      await tester.tap((label.startsWith('选择')
          ? find.byTooltip(label)
          : find.textContaining(label).last));
      await tester.pumpAndSettle();
    }

    Finder node(String name) => find.widgetWithText(CheckboxListTile, name);
    await open('打开');
    await open('选择前置节点');
    expect(node('A'), findsOneWidget);
    expect(node('B'), findsNothing);
    expect(node('C'), findsOneWidget);
    await open('全选');
    await open('确定');
    await open('选择作用节点');
    expect(node('A'), findsNothing);
    expect(node('C'), findsNothing);
    expect(node('B'), findsOneWidget);
    await tester.tap(node('B'));
    await open('确定');
    await open('选择前置节点');
    expect(node('B'), findsOneWidget);
    await tester.tap(node('C'));
    await open('确定');
    await open('选择作用节点');
    expect(node('A'), findsNothing);
    expect(node('C'), findsOneWidget);
    await tester.tap(node('C'));
    await open('确定');
    await open('选择前置节点');
    expect(node('C'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await open('保存');
    expect(savedChain, ['A']);
    expect(savedTargets, ['C']);
  });
}
