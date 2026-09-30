import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/pages/config_page.dart';
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
    for (final name in ['国内正则表达式', '国外正则表达式']) {
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
    expect(yaml['proxy-groups'][0]['filter'], '上海|广州');
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
}
