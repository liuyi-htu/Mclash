import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/config_management_page.dart';
import 'package:mclash/config_management.dart';
import 'package:mclash/subscription_filter.dart';
import 'package:yaml/yaml.dart';
import 'config_management_test.dart' show source;

void main() {
  testWidgets('regional groups hide delete actions and lock only their names',
      (tester) async {
    final content = source
        .replaceAll('name: 自选', 'name: 🌍 国外')
        .replaceAll('example.org,自选', 'example.org,🌍 国外');
    await tester.pumpWidget(MaterialApp(
        home: ConfigManagementPage(
            content: content,
            mode: ConfigManagementMode.groups,
            onSave: (value) async {})));
    expect(find.byTooltip('删除代理组'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
    for (final name in ['🚀 国内', '🌍 国外']) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField).first).enabled,
          false);
      expect(find.text('保存'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('new group uses an empty regex and automatically saves',
      (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
        home: ConfigManagementPage(
            content: source,
            mode: ConfigManagementMode.groups,
            onSave: (value) async {
              saved = value;
            })));
    await tester.tap(find.byTooltip('新增代理组'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新建');
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(configGroups(saved!).last['proxies'], ['北京', 'JP']);
    expect(readSubscriptionFilters(saved!)['新建'], '');
    expect(find.text('新建'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'editing a group shows only current members without selection controls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ConfigManagementPage(
            content: source,
            mode: ConfigManagementMode.groups,
            onSave: (value) async {})));
    await tester.tap(find.text('自选'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('JP'), findsOneWidget);
    expect(find.text('北京'), findsNothing);
    expect(find.textContaining('保存正则后重新匹配'), findsWidgets);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rule add and drag ordering persist correctly', (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
        home: ConfigManagementPage(
            content: source,
            mode: ConfigManagementMode.rules,
            onSave: (value) async {
              saved = value;
            })));
    await tester.tap(find.byTooltip('新增规则'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new.example');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(configRules(saved!)[1], 'DOMAIN-SUFFIX,new.example,DIRECT');
    expect(configRules(saved!).last, 'MATCH,DIRECT');
    final first = tester.getCenter(find.byIcon(Icons.drag_handle).first);
    final gesture = await tester
        .startGesture(tester.getCenter(find.byIcon(Icons.drag_handle).at(1)));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveTo(first - const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(configRules(saved!).first, 'DOMAIN-SUFFIX,new.example,DIRECT');
    expect(tester.takeException(), isNull);
  });
  testWidgets('regex settings edits any named group', (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
        home: ConfigManagementPage(
            content: source,
            mode: ConfigManagementMode.groups,
            onSave: (value) async {
              saved = value;
            })));
    await tester.tap(find.text('自选'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '节点名称匹配规则'), '^北');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(readSubscriptionFilters(saved!)['自选'], '^北');
    expect(loadYaml(saved!)['proxy-groups'][1]['proxies'], ['北京']);
    expect(find.text('编辑代理组'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('invalid regex stays in the edit dialog without saving',
      (tester) async {
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
        home: ConfigManagementPage(
            content: source,
            mode: ConfigManagementMode.groups,
            onSave: (value) async {
              saves++;
            })));
    await tester.tap(find.text('自选'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '节点名称匹配规则'), '[');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('编辑代理组'), findsOneWidget);
    expect(find.textContaining('FormatException'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '节点名称匹配规则'), '^JP');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('编辑代理组'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save keeps the existing configuration', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ConfigManagementPage(
            content: source,
            mode: ConfigManagementMode.rules,
            onSave: (value) async {
              throw StateError('内核校验失败');
            })));
    await tester.tap(find.byTooltip('删除规则').first);
    await tester.pumpAndSettle();
    expect(find.text('DOMAIN-SUFFIX,example.org,自选'), findsOneWidget);
    expect(find.textContaining('内核校验失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('group dialog scrolls on a small screen with the keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.reset);
    final content =
        source.replaceAll('name: 自选, type: select', 'name: 自选, type: url-test');
    await tester.pumpWidget(MaterialApp(
        home: ConfigManagementPage(
            content: content,
            mode: ConfigManagementMode.groups,
            onSave: (value) async {})));
    await tester.tap(find.text('自选'));
    await tester.pumpAndSettle();
    expect(find.text('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}
