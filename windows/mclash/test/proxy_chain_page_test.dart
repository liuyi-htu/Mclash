import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/proxy_chain.dart';
import 'package:mclash/proxy_chain_page.dart';
import 'config_management_test.dart' show source;

void main() {
  testWidgets(
      'chain page keeps failed edits and refreshes after save and cancel',
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
    await tester.tap(find.textContaining('选择前置节点（已选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(readProxyChains(saved!), {'北京': 'JP'});
    expect(find.text('链式节点 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
