import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/proxy_chain.dart';
import 'package:mclash/shared/proxy_chain_page.dart';
import 'config_management_test.dart' show source;

void main() {
  testWidgets(
      'chain page keeps failed edits and refreshes after save and clear',
      (tester) async {
    var reject = true;
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: ProxyChainPage(
        content: setProxyChainSet(source, '1', ['JP'],
            prepend: true, targets: ['北京']),
        onSave: (content) async {
          if (reject) throw StateError('保存失败');
          saved = content;
        },
      ),
    ));
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('链式节点 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    reject = false;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(readProxyChains(saved!), {'北京': 'JP'});
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('链式节点 1'), findsOneWidget);
    await tester.tap(find.text('链式节点 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择前置节点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(readProxyChains(saved!), isEmpty);
    expect(find.text('链式节点 1'), findsNothing);
    expect(find.text('暂无链式节点，点击右下角加号添加。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'chain deletion cancels safely and removes only the selected chain',
      (tester) async {
    final expanded = source.replaceFirst(
        'type: http}]', 'type: http}, {name: W, type: http}]');
    final first =
        setProxyChainSet(expanded, '1', ['JP'], prepend: true, targets: ['北京']);
    final initial =
        setProxyChainSet(first, '2', ['JP'], prepend: true, targets: ['W']);
    var reject = true;
    var attempts = 0;
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: ProxyChainPage(
        content: initial,
        onSave: (content) async {
          attempts++;
          if (reject) throw StateError('删除保存失败');
          saved = content;
        },
      ),
    ));
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    await tester.tap(find.byTooltip('删除链式节点').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(attempts, 0);
    expect(find.text('链式节点 1'), findsOneWidget);
    await tester.tap(find.byTooltip('删除链式节点').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(saved, isNull);
    expect(find.textContaining('删除保存失败'), findsOneWidget);
    expect(find.text('链式节点 1'), findsOneWidget);
    reject = false;
    await tester.tap(find.byTooltip('删除链式节点').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(readProxyChainSets(saved!).keys, ['2']);
    expect(readProxyChains(saved!), {'W': 'JP'});
    expect(find.text('链式节点 1'), findsNothing);
    expect(find.text('链式节点 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
