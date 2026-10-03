import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/subscription_host_dialog.dart';
import 'package:mclash/shared/proxy_chain_dialog.dart';
import 'package:mclash/shared/add_node_page.dart';

void main() {
  for (final host in [true, false]) {
    testWidgets('${host ? 'Host' : 'chain'} dialog cancels on an outside tap',
        (tester) async {
      var saves = 0;
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () async {
                    result = host
                        ? await showSubscriptionHostDialog(
                            context: context,
                            initialHost: 'example.org',
                            onSave: (_) async {
                              saves++;
                            })
                        : await showProxyChainDialog(
                            context: context,
                            nodes: ['A', 'B'],
                            prepend: true,
                            initialNodes: ['B'],
                            initialTargets: ['A'],
                            onSave: (_, other) async {
                              saves++;
                            });
                  },
                  child: const Text('打开'),
                )),
      ));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
      expect(result, false);
      expect(saves, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('add-node dialog cancels on an outside tap without saving',
      (tester) async {
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
        home: AddNodePage(
      nodes: const [],
      onDelete: (_) async => [],
      onSave: (_) async {
        saves++;
        return [];
      },
    )));
    await tester.tap(find.byTooltip('添加节点'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'unsaved');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('添加节点（0）'), findsOneWidget);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });
}
