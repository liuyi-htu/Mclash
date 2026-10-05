import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/node_link.dart';
import 'package:mclash/add_node_page.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
      'manual order survives serialization and preserves airport and chain data',
      () {
    const content = '# Mclash 手动节点: ["A", "B"]\n'
        '# Mclash 链路代理组: {"Chain":["A","B"]}\n'
        'proxies: [{name: A, type: http, server: a, port: 80}, '
        '{name: Airport, type: http, server: sub, port: 80}, '
        '{name: B, type: http, server: b, port: 80, dialer-proxy: A}]\n'
        'proxy-groups: [{name: Select, type: select, proxies: [A, Airport, B]}, '
        '{name: Chain, type: select, proxies: [A, B]}]';
    final result = reorderManualNodes(content, ['B', 'A']);
    expect(savedManualNodeNames(result), ['B', 'A']);
    final parsed = loadYaml(result);
    expect([for (final node in parsed['proxies']) node['name']],
        ['B', 'Airport', 'A']);
    expect(parsed['proxies'][0]['dialer-proxy'], 'A');
    expect(parsed['proxy-groups'][0]['proxies'], ['B', 'Airport', 'A']);
    expect(parsed['proxy-groups'][1]['proxies'], ['A', 'B']);
    expect(
        () => reorderManualNodes(content, ['A', 'A']), throwsFormatException);
    expect(() => reorderManualNodes(content, ['Airport', 'A']),
        throwsFormatException);
  });

  testWidgets('node reorder saves and failed saves retain the displayed order',
      (tester) async {
    var reject = false;
    List<String>? saved;
    await tester.pumpWidget(MaterialApp(
        home: AddNodePage(
      nodes: const ['A', 'B'],
      onDelete: (_) async => [],
      onSave: (_) async => [],
      onReorder: (order) async {
        if (reject) throw StateError('排序保存失败');
        saved = order;
        return order;
      },
    )));
    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ReorderableDragStartListener).first));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 5));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(saved, ['B', 'A']);
    expect(tester.getTopLeft(find.text('B')).dy,
        lessThan(tester.getTopLeft(find.text('A')).dy));
    reject = true;
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        // ignore: deprecated_member_use
        .onReorder!(0, 2);
    await tester.pumpAndSettle();
    expect(find.textContaining('排序保存失败'), findsOneWidget);
    expect(tester.getTopLeft(find.text('B')).dy,
        lessThan(tester.getTopLeft(find.text('A')).dy));
  });
}
