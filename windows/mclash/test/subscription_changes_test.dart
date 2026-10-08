import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/subscription_changes.dart';

void main() {
  test(
      'compares full nested parameters independently of YAML formatting and map order',
      () {
    const before = """
proxies:
  - {name: Changed, type: vmess, server: old, ws-opts: {headers: {Host: [a, b]}}}
  - {name: Same, type: ss, port: 80}
  - {name: Removed, type: http}
""";
    const after = """
# Metadata changes do not affect node comparison.
proxies:
  - {port: 80, type: ss, name: Same}
  - {name: Added, type: http}
  - {name: Changed, type: vmess, server: old, ws-opts: {headers: {Host: [a, c]}}}
""";
    final changes = SubscriptionChanges.compare(before, after);
    expect(changes.added, ['Added']);
    expect(changes.changed, ['Changed']);
    expect(changes.deleted, ['Removed']);
    final same = SubscriptionChanges.compare(before, before);
    expect(same.added, isEmpty);
    expect(same.changed, isEmpty);
    expect(same.deleted, isEmpty);
    expect(SubscriptionChanges.compare('rules: []', after).added,
        ['Same', 'Added', 'Changed']);
  });

  testWidgets('report orders sections and scrolls on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showSubscriptionChanges(context,
                    message: '订阅更新成功',
                    changes: SubscriptionChanges(
                        added: List.generate(60, (index) => '新增节点 $index'),
                        changed: ['变动节点'],
                        deleted: ['删除节点'])),
                child: const Text('更新')))));
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('新增（60）')).dy,
        lessThan(tester.getTopLeft(find.text('变动（1）')).dy));
    expect(tester.getTopLeft(find.text('变动（1）')).dy,
        lessThan(tester.getTopLeft(find.text('删除（1）')).dy));
    await tester.ensureVisible(find.text('删除节点'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('unchanged update still reports all three sections',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showSubscriptionChanges(context,
                    message: '订阅更新成功',
                    changes: const SubscriptionChanges(
                        added: [], changed: [], deleted: [])),
                child: const Text('更新')))));
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(find.text('新增（0）'), findsOneWidget);
    expect(find.text('变动（0）'), findsOneWidget);
    expect(find.text('删除（0）'), findsOneWidget);
    expect(find.text('节点没有变化。'), findsNothing);
    expect(find.text('配置已保存，新配置将在下次启动时应用。'), findsNothing);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
  });
}
