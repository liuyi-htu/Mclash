import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/rule_provider_page.dart';
import 'package:mclash/shared/rule_provider_management.dart';
import 'package:mclash/shared/app_appearance.dart';

void main() {
  testWidgets('add remote ruleset, edit and delete persist correctly',
      (tester) async {
    var content = 'rules: [MATCH,DIRECT]\n';
    await tester.pumpWidget(MaterialApp(
        theme: buildPulseTheme(Brightness.light),
        home: RuleProviderPage(
            content: content, onSave: (value) async => content = value)));
    await tester.tap(find.byTooltip('新增规则集'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), 'local');
    expect(find.text('来源'), findsNothing);
    expect(find.text('内嵌规则（每行一条）'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, '下载链接'),
        'https://example.org/rules.yaml');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(configRuleProviders(content)['local']!['type'], 'http');
    expect(configRuleProviders(content)['local']!['interval'], 86400);
    await tester.tap(find.text('local'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), 'renamed');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(configRuleProviders(content).keys, ['renamed']);
    await tester.tap(find.byTooltip('删除规则集 renamed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(configRuleProviders(content), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('ruleset dialog fits small windows, dark mode and large text',
      (tester) async {
    addTearDown(tester.view.reset);
    for (final size in [const Size(320, 480), const Size(1024, 768)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(MaterialApp(
            theme: buildPulseTheme(brightness),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(1.4)),
                child: child!),
            home: RuleProviderPage(
                content: 'rules: []\n', onSave: (_) async {})));
        await tester.tap(find.byTooltip('新增规则集'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextField, '名称'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding();
      }
    }
  });
  testWidgets(
      'converting local ruleset requires a URL and clears inline payload',
      (tester) async {
    var content =
        'rule-providers: {local: {type: inline, behavior: domain, payload: [example.org]}}\nrules: []\n';
    await tester.pumpWidget(MaterialApp(
        home: RuleProviderPage(
            content: content, onSave: (value) async => content = value)));
    await tester.tap(find.text('local'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请输入有效的 HTTP / HTTPS 下载链接'), findsOneWidget);
    expect(configRuleProviders(content)['local']!['type'], 'inline');
    await tester.enterText(find.widgetWithText(TextField, '下载链接'),
        'https://example.org/rules.yaml');
    await tester.enterText(find.widgetWithText(TextField, '更新间隔（秒）'), '0');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('更新间隔必须是正整数'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '更新间隔（秒）'), '3600');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final provider = configRuleProviders(content)['local']!;
    expect(provider['type'], 'http');
    expect(provider['interval'], 3600);
    expect(provider.containsKey('payload'), false);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed save keeps draft and original configuration',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: RuleProviderPage(
            content: 'rules: []\n',
            onSave: (_) async => throw StateError('保存失败'))));
    await tester.tap(find.byTooltip('新增规则集'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), 'test');
    await tester.enterText(find.widgetWithText(TextField, '下载链接'),
        'https://example.org/rules.yaml');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '名称'))
            .controller!
            .text,
        'test');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
