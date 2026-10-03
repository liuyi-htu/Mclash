import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/pages/config_page.dart';
import 'package:mclash/shared/proxy_chain.dart';
import 'package:yaml/yaml.dart';

const source = '''
proxies:
  - {name: A, type: http, server: a.example, port: 80}
  - {name: B, type: http, server: b.example, port: 80}
  - {name: C, type: http, server: c.example, port: 80}
proxy-groups:
  - {name: Group, type: select, proxies: [A, B, C]}
rules: ['MATCH,Group']
''';

void main() {
  const channel = MethodChannel('mclash/native');
  const profile = {
    'id': 'airport',
    'name': 'Airport',
    'type': 'subscription',
    'active': true,
    'exists': true,
    'updatedAt': 0,
  };

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final prepend in [true]) {
    const side = '链式';
    testWidgets('clear $side proxy saves zero nodes and removes the chain',
        (tester) async {
      var saved = setGlobalProxyChain(source, ['B'],
          prepend: prepend, targets: ['A', 'C']);
      var saves = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getConfigs') return [profile];
        if (call.method == 'getConfigContent') return saved;
        if (call.method == 'saveConfigContent') {
          expect(call.arguments['id'], 'airport');
          saved = call.arguments['content'] as String;
          saves++;
          return [profile];
        }
        throw StateError('Unexpected call: ${call.method}');
      });
      await tester
          .pumpWidget(const MaterialApp(home: ConfigPage(proxyRunning: false)));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Airport'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('链式节点'));
      await tester.tap(find.text('链式节点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('链式节点 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择前置节点（已选 1 个）'));
      await tester.pumpAndSettle();
      expect(find.text('清空'), findsNothing);
      await tester.tap(find.text('清除链式节点'));
      await tester.pumpAndSettle();
      expect(find.text('选择前置节点（已选 0 个）'), findsOneWidget);
      expect(saves, 0);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
              .onPressed,
          isNotNull);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(loadYaml(saved), loadYaml(source));
      expect(readProxyChainSets(saved), isEmpty);
      expect(find.text('链式节点 1'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('订阅管理'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
