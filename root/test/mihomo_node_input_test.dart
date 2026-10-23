import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:mclash/shared/add_node_page.dart';
import 'package:mclash/shared/mihomo_node_input.dart';
import 'package:mclash/shared/node_link.dart';

const base = '''
proxies: [{name: Existing, type: direct}]
proxy-groups: [{name: Select, type: select, proxies: [Existing, DIRECT]}]
rules: [MATCH,Select]
''';

void main() {
  test('accepts flow/block mappings, lists, wrapper and multiple documents',
      () {
    for (final text in [
      '{name: A, type: direct}',
      'name: A\ntype: direct',
      '- {name: A, type: direct}',
      '[{name: A, type: direct}]',
      'proxies: [{name: A, type: direct}]\nrules: []',
      '\uFEFF---\nname: A\ntype: direct\n---\n',
    ]) {
      expect(parseMihomoNodes(text), [
        {'name': 'A', 'type': 'direct'}
      ]);
      expect(savedManualNodeNames(addNodeLink(base, text)), ['A']);
    }
    expect(
        parseMihomoNodes('name: A\ntype: direct\n---\nname: B\ntype: dns')
            .length,
        2);
  });

  test('expands nested aliases and merge precedence with arbitrary protocols',
      () {
    const text = '''
headers: &headers {Host: example.test, X-Auth: 12345}
addons: &addons
  type: http
  port: 443
  headers: *headers
other: &other {port: 80, udp: true}
proxies:
  - name: A
    server: one.example
    <<: [*addons, *other]
    port: 8443
  - {name: B, server: two.example, <<: *addons}
  - name: Future
    type: future-core-protocol
    arbitrary-options: {peers: [{ip: '::1', allowed: ['0.0.0.0/0']}], enabled: true}
''';
    final nodes = parseMihomoNodes(text);
    expect(nodes[0]['port'], 8443);
    expect(nodes[0]['headers'], {'Host': 'example.test', 'X-Auth': 12345});
    expect(nodes[0]['udp'], true);
    expect(nodes[1]['port'], 443);
    expect(nodes[0].containsKey('<<'), false);
    final saved = loadYaml(addNodeLink(base, text));
    expect(saved['proxies'].take(3).toList(), nodes);
    expect(saved['proxies'][2]['arbitrary-options']['peers'][0]['allowed'],
        ['0.0.0.0/0']);
    expect(saved['rules'], ['MATCH', 'Select']);
    expect(saved['proxy-groups'][0]['proxies'],
        ['A', 'B', 'Future', 'Existing', 'DIRECT']);
  });

  test('earlier merge sources win and explicit nested values override', () {
    final nodes = parseMihomoNodes('''
a: &a {type: http, port: 443, headers: {Host: original}}
b: &b {<<: *a, port: 80}
proxies:
  - {name: A, <<: [*a, *b], headers: {Host: explicit}}
''');
    expect(nodes.single['port'], 443);
    expect(nodes.single['headers'], {'Host': 'explicit'});
  });

  test('batch renaming reserves group and builtin names and remaps dialers',
      () {
    final result = addNodeLink(base, '''
- {name: Existing, type: direct}
- {name: Select, type: custom, dialer-proxy: Existing}
- {name: DIRECT, type: direct}
- {name: Existing (2), type: custom, dialer-proxy: Select}
''');
    expect(savedManualNodeNames(result),
        ['Existing (2)', 'Select (2)', 'DIRECT (2)', 'Existing (2) (2)']);
    final nodes = loadYaml(result)['proxies'];
    expect(nodes[1]['dialer-proxy'], 'Existing (2)');
    expect(nodes[3]['dialer-proxy'], 'Select (2)');
    expect(mergeManualNodes([], result), nodes.take(4).toList());
    expect(savedManualNodeNames(deleteManualNode(result, 'Select (2)')),
        ['Existing (2)', 'DIRECT (2)', 'Existing (2) (2)']);
  });

  test('YAML credentials and transports are not rewritten by subscription Host',
      () {
    const text = '''
name: Custom
 type: vmess
''';
    expect(() => parseMihomoNodes(text), throwsFormatException);
    final updated = addNodeLink('# Mclash HTTP/WS Host: "override.test"\n$base',
        '{name: WS, type: vmess, network: ws, ws-opts: {headers: {Host: original.test}}, password: secret}');
    expect(loadYaml(updated)['proxies'][0]['ws-opts']['headers']['Host'],
        'original.test');
  });

  test('invalid batches fail without exposing source or accepting partial data',
      () {
    for (final text in [
      '',
      'proxies: {}',
      'rules: []',
      'name: A',
      'type: http',
      '[{name: A, type: direct}, {name: B}]',
      '[{name: A, type: direct}, {name: A, type: direct}]',
      '{name: A, type: http, <<: *missing}',
      '{name: A, type: http, <<: 123}',
      'name: A\ntype: http\npassword: [private-secret',
      'name: A\ntype: http\noptions: &loop [*loop]',
    ]) {
      try {
        addNodeLink(base, text);
        fail('Expected invalid input to fail');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains('private-secret')));
      }
    }
    expect(() => parseMihomoNodes('x' * (maxNodeInputBytes + 1)),
        throwsFormatException);
  });

  testWidgets(
      'file fills editor and batch saves through existing node workflow',
      (tester) async {
    const snippet = '- {name: A, type: direct}\n- {name: B, type: dns}';
    await tester.pumpWidget(MaterialApp(
        home: AddNodePage(
      nodes: const [],
      onDelete: (_) async => [],
      onReadFile: () async => snippet,
      onSave: (value) async => savedManualNodeNames(addNodeLink(base, value)),
    )));
    await tester.tap(find.byTooltip('添加节点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        snippet);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('添加节点（2）'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled file picker preserves pasted text', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: AddNodePage(
      nodes: const [],
      onDelete: (_) async => [],
      onSave: (_) async => [],
      onReadFile: () async => null,
    )));
    await tester.tap(find.byTooltip('添加节点'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'name: A\ntype: direct');
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'name: A\ntype: direct');
    expect(find.text('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
