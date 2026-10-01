import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/pages/config_page.dart';
import 'package:mclash/shared/proxy_chain_dialog.dart';
import 'package:yaml/yaml.dart';

void main() {
  const channel = MethodChannel('mclash/native');
  const profile = {
    'id': 'airport',
    'name': 'Airport',
    'type': 'subscription',
    'active': true,
    'exists': true,
    'updatedAt': 0,
    'url': 'https://example.org/sub',
  };
  const content = '''
proxies: [{name: 上海, type: ss}, {name: KR, type: ss}]
proxy-groups:
  - {name: 🚀 国内, type: select, proxies: [DIRECT, 上海]}
  - {name: 🌍 国外, type: select, proxies: [KR]}
rules: [MATCH,DIRECT]
''';
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('regex editing is disabled while the VPN is running',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      throw StateError('Unexpected mutation: ${call.method}');
    });
    await tester
        .pumpWidget(const MaterialApp(home: ConfigPage(proxyRunning: true)));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Airport'));
    await tester.pumpAndSettle();
    expect(find.text('修改配置文件'), findsNothing);
    for (final name in [
      '国内正则表达式',
      '国外正则表达式',
      '修改 Host',
      '添加节点',
      '添加前置代理',
      '添加后置代理'
    ]) {
      final tile = tester.widget<ListTile>(
          find.ancestor(of: find.text(name), matching: find.byType(ListTile)));
      expect(tile.enabled, isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'long press edits the corresponding subscription and cancel does not save',
      (tester) async {
    var saves = 0;
    String? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      if (call.method == 'getConfigContent') {
        expect(call.arguments['id'], 'airport');
        return saved ?? content;
      }
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
    expect(find.text('国内正则表达式'), findsOneWidget);
    expect(find.text('国外正则表达式'), findsOneWidget);
    await tester.ensureVisible(find.text('国内正则表达式'));
    await tester.tap(find.text('国内正则表达式'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '上海');
    await tester.enterText(find.byType(TextField), '上海|广州');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final yaml = loadYaml(saved!);
    expect(yaml['proxy-groups'][0]['filter'], isNull);
    expect(yaml['proxy-groups'][0]['proxies'], ['DIRECT', '上海']);
    expect(saved, contains('上海|广州'));
    expect(yaml['rules'], loadYaml(content)['rules']);
    expect(saves, 1);
    await tester.longPress(find.text('Airport'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('国外正则表达式'));
    await tester.tap(find.text('国外正则表达式'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'KR');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Host menu validates, saves the selected profile and cancels safely',
      (tester) async {
    String? saved;
    var saves = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      if (call.method == 'getConfigContent') {
        return saved ?? 'proxies: [{name: KR, type: vmess, network: ws}]';
      }
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
    await tester.ensureVisible(find.text('修改 Host'));
    await tester.tap(find.text('修改 Host'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'http://example.com');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.errorText,
        isNotNull);
    await tester.enterText(find.byType(TextField), 'new.example');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(loadYaml(saved!)['proxies'][0]['ws-opts']['headers']['Host'],
        'new.example');
    expect(saves, 1);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.longPress(find.text('Airport'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('修改 Host'));
    await tester.tap(find.text('修改 Host'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'new.example');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'add node uses configured Host without a Host input or subscription request',
      (tester) async {
    String? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      if (call.method == 'getConfigContent') {
        return '# Mclash HTTP/WS Host: "preset.example"\n$content';
      }
      if (call.method == 'saveConfigContent') {
        expect(call.arguments['id'], 'airport');
        saved = call.arguments['content'] as String;
        return [profile];
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    await tester
        .pumpWidget(const MaterialApp(home: ConfigPage(proxyRunning: false)));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Airport'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加节点'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('已添加的节点（2）'), findsOneWidget);
    expect(find.text('上海'), findsOneWidget);
    expect(find.text('KR'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'vmess://bad');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    final link = 'vmess://${base64Encode(utf8.encode(jsonEncode({
          'ps': '上海手动',
          'add': 'example.org',
          'port': '443',
          'id': '00000000-0000-4000-8000-000000000001',
          'net': 'ws',
          'host': 'link.example'
        })))}';
    await tester.enterText(find.byType(TextField), link);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final config = loadYaml(saved!);
    expect(
        config['proxies'][2]['ws-opts']['headers']['Host'], 'preset.example');
    expect(config['proxy-groups'][0]['proxies'], ['DIRECT', '上海', '上海手动']);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'proxy chain selects saved nodes, saves the correct profile and cancels safely',
      (tester) async {
    String? saved;
    var saves = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      if (call.method == 'getConfigContent') return saved ?? content;
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
    await tester.ensureVisible(find.text('添加前置代理'));
    await tester.tap(find.text('添加前置代理'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNull);
    await tester.tap(find.textContaining('选择前置节点（已选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KR').last);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.textContaining('选择当前节点'), findsNothing);
    expect(find.textContaining('本机 →'), findsNothing);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(loadYaml(saved!)['proxies'][0]['dialer-proxy'], 'KR');
    expect(saves, 1);
    await tester.longPress(find.text('Airport'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加后置代理'));
    await tester.tap(find.text('添加后置代理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('batch proxies default to every remaining saved node',
      (tester) async {
    List<String>? targets;
    List<String>? proxies;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showProxyChainDialog(
                    context: context,
                    nodes: ['A', 'B', 'C', 'D'],
                    prepend: true,
                    onSave: (current, other) async {
                      targets = current;
                      proxies = other;
                    }),
                child: const Text('打开')))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('选择前置节点（已选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((tile) => tile.value == true),
        isTrue);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((tile) => tile.value == false),
        isTrue);
    await tester.tap(find.text('C'));
    await tester.tap(find.text('D'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(targets, ['A', 'B']);
    expect(proxies, ['C', 'D']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chain cycle failures keep the dialog open', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () => showProxyChainDialog(
                    context: context,
                    nodes: ['A', 'B'],
                    prepend: false,
                    onSave: (_, __) async =>
                        throw const FormatException('代理链路形成循环'),
                  ),
                  child: const Text('打开'),
                ))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('选择后置节点（已选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B').last);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('代理链路形成循环'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
