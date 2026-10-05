import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/pages/config_page.dart';
import 'package:mclash/shared/proxy_chain_dialog.dart';
import 'package:mclash/shared/proxy_chain.dart';
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
    'subscriptionUserInfo': 'upload=0;download=0;total=1073741824;expire=0',
  };
  const content = '''
# Mclash 国内正则: "上海"
# Mclash 国外正则: "KR"
proxies: [{name: 上海, type: ss}, {name: KR, type: ss}]
proxy-groups:
  - {name: 🚀 国内, type: select, proxies: [DIRECT, 上海]}
  - {name: 🌍 国外, type: select, proxies: [KR]}
rules: ["MATCH,DIRECT"]
''';
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'adding a subscription uses a scrollable dialog without ordering notes',
      (tester) async {
    Map<Object?, Object?>? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      if (call.method == 'addSubscription') {
        saved = Map<Object?, Object?>.from(call.arguments as Map);
        return [profile];
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(const MaterialApp(home: ConfigPage(proxyRunning: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加配置'));
    await tester.pumpAndSettle();
    expect(find.text('添加本地配置'), findsOneWidget);
    await tester.tap(find.text('添加机场配置'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('拖动调整机场顺序'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, '配置名称'), '测试配置');
    await tester.enterText(find.widgetWithText(TextField, '机场 1 名称'), '机场甲');
    await tester.enterText(
        find.widgetWithText(TextField, '机场 1 订阅链接'), 'https://example.org/a');
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('添加并下载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(saved, {
      'name': '测试配置',
      'url': 'https://example.org/a',
      'subscriptionNames': {'https://example.org/a': '机场甲'},
    });
    expect(find.text('订阅已添加'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'configuration menu follows YAML section order and handles unreadable files',
      (tester) async {
    const defaults = ['添加节点', '修改 Host', '链式节点', '代理组管理', '规则集管理', '规则管理'];
    final cases = <String?>[
      content,
      '# proxies: comment only\nrules: ["MATCH,DIRECT"]\nproxy-groups: []\nproxies: []\n',
      null,
    ];
    for (var index = 0; index < cases.length; index++) {
      final current = cases[index];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getConfigs') return [profile];
        if (call.method == 'getConfigContent') {
          expect(call.arguments['id'], 'airport');
          if (current == null) throw PlatformException(code: 'missing_profile');
          return current;
        }
        throw StateError('Unexpected mutation: ${call.method}');
      });
      await tester.pumpWidget(MaterialApp(
          key: ValueKey(index), home: const ConfigPage(proxyRunning: false)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Airport').first);
      await tester.pumpAndSettle();
      final expected = index == 1
          ? ['规则集管理', '规则管理', '代理组管理', '添加节点', '修改 Host', '链式节点']
          : defaults;
      for (var position = 1; position < expected.length; position++) {
        expect(
            tester.getTopLeft(find.text(expected[position]).last).dy,
            greaterThan(
                tester.getTopLeft(find.text(expected[position - 1]).last).dy));
      }
      expect(find.text('正则设置'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'subscription rename sits below divider and above subscription management',
      (tester) async {
    String? renamed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      if (call.method == 'getConfigContent') return content;
      if (call.method == 'renameConfig') {
        expect(call.arguments['id'], 'airport');
        renamed = call.arguments['name'] as String;
        return [
          {...profile, 'name': renamed}
        ];
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    await tester
        .pumpWidget(const MaterialApp(home: ConfigPage(proxyRunning: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('修改配置名称')).dy,
        greaterThan(tester.getTopLeft(find.byType(Divider).first).dy));
    expect(tester.getTopLeft(find.text('修改配置名称')).dy,
        lessThan(tester.getTopLeft(find.text('订阅管理')).dy));
    await tester.tap(find.text('修改配置名称'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Airport');
    await tester.enterText(find.byType(TextField), '新配置名称');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(renamed, '新配置名称');
    expect(find.text('新配置名称'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'airport menu opens rule management and saves the selected profile',
      (tester) async {
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
        return [profile];
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    await tester
        .pumpWidget(const MaterialApp(home: ConfigPage(proxyRunning: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    expect(find.text('修改配置文件'), findsNothing);
    await tester.ensureVisible(find.text('规则管理').last);
    await tester.tap(find.text('规则管理').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增规则'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new.example');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(loadYaml(saved!)['rules'],
        ['DOMAIN-SUFFIX,new.example,DIRECT', 'MATCH,DIRECT']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ruleset menu saves the selected configuration', (tester) async {
    String? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      if (call.method == 'getConfigContent') return saved ?? content;
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
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('规则集管理'));
    await tester.tap(find.text('规则集管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增规则集'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), 'remote');
    await tester.enterText(find.widgetWithText(TextField, '下载链接'),
        'https://example.org/rules.yaml');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(loadYaml(saved!)['rule-providers']['remote']['interval'], 86400);
    expect(loadYaml(saved!)['rules'], loadYaml(content)['rules']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('regex editing is disabled while the proxy is running',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      throw StateError('Unexpected mutation: ${call.method}');
    });
    await tester
        .pumpWidget(const MaterialApp(home: ConfigPage(proxyRunning: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    expect(find.text('修改配置文件'), findsNothing);
    expect(
        find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('1. 剩余流量：1.00 GB · 到期时间：不限时')),
        findsNothing);
    expect(find.text('https://example.org/sub'), findsNothing);
    for (final name in [
      '规则管理',
      '代理组管理',
      '修改 Host',
      '添加节点',
      '链式节点',
    ]) {
      final tile = tester.widget<ListTile>(
          find.ancestor(of: find.text(name), matching: find.byType(ListTile)));
      expect(tile.enabled, isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('region regex dialogs default to empty without saved filters',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      if (call.method == 'getConfigContent') {
        return content
            .split('\n')
            .where((line) => !line.startsWith('# Mclash '))
            .join('\n');
      }
      throw StateError('Unexpected mutation: ${call.method}');
    });
    await tester
        .pumpWidget(const MaterialApp(home: ConfigPage(proxyRunning: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    expect(find.text('国内正则表达式'), findsNothing);
    expect(find.text('国外正则表达式'), findsNothing);
    await tester.ensureVisible(find.text('代理组管理').last);
    await tester.tap(find.text('代理组管理').last);
    await tester.pumpAndSettle();
    for (final title in ['🚀 国内', '🌍 国外']) {
      await tester.ensureVisible(find.text(title));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '正则表达式'))
              .controller!
              .text,
          isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
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
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    expect(find.text('国内正则表达式'), findsNothing);
    expect(find.text('国外正则表达式'), findsNothing);
    await tester.ensureVisible(find.text('代理组管理').last);
    await tester.tap(find.text('代理组管理').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('🚀 国内'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '正则表达式'))
            .controller!
            .text,
        '上海');
    await tester.enterText(find.widgetWithText(TextField, '正则表达式'), '上海|广州');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final yaml = loadYaml(saved!);
    expect(yaml['proxy-groups'][0]['filter'], isNull);
    expect(yaml['proxy-groups'][0]['proxies'], ['DIRECT', '上海']);
    expect(saved, contains('上海|广州'));
    expect(yaml['rules'], loadYaml(content)['rules']);
    expect(saves, 1);
    expect(find.text('代理组管理').last, findsOneWidget);
    await tester.tap(find.text('🌍 国外'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '正则表达式'))
            .controller!
            .text,
        'KR');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('订阅管理'), findsOneWidget);
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
    await tester.tap(find.text('Airport').first);
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
    expect(find.text('订阅管理'), findsOneWidget);
    await tester.ensureVisible(find.text('修改 Host'));
    await tester.tap(find.text('修改 Host'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'new.example');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('订阅管理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'node dialog lists only manual nodes and deletes them without downloading',
      (tester) async {
    var saved =
        '# Mclash 手动节点: ["上海手动"]\nproxies: [{name: KR机场, type: http, server: airport.example, port: 80}, {name: 上海手动, type: http, server: manual.example, port: 80}]\nproxy-groups: [{name: 🚀 国内, type: select, proxies: [DIRECT, 上海手动]}, {name: 🌍 国外, type: select, proxies: [KR机场]}]';
    var deletes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      if (call.method == 'getConfigContent') return saved;
      if (call.method == 'saveConfigContent') {
        saved = call.arguments['content'] as String;
        deletes++;
        return [profile];
      }
      throw StateError('Unexpected subscription request: ${call.method}');
    });
    await tester
        .pumpWidget(const MaterialApp(home: ConfigPage(proxyRunning: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加节点'));
    await tester.pumpAndSettle();
    expect(find.text('添加节点（1）'), findsOneWidget);
    expect(find.text('上海手动'), findsOneWidget);
    expect(find.text('KR机场'), findsNothing);
    await tester.tap(find.byTooltip('删除手动节点'));
    await tester.pumpAndSettle();
    expect(find.text('暂无手动节点'), findsOneWidget);
    expect(deletes, 1);
    expect(loadYaml(saved)['proxies'].length, 1);
    expect(loadYaml(saved)['proxies'][0]['name'], 'KR机场');
    await tester.pageBack();
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加节点'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byTooltip('添加节点'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('添加节点（0）'), findsOneWidget);
    expect(find.text('上海'), findsNothing);
    expect(find.text('KR'), findsNothing);
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
        config['proxies'][0]['ws-opts']['headers']['Host'], 'preset.example');
    expect(config['proxy-groups'][0]['proxies'], ['DIRECT', '上海手动', '上海']);
    expect(find.text('上海手动'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('订阅管理'), findsOneWidget);
    expect(find.text('订阅管理'), findsOneWidget);
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
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('链式节点').last);
    await tester.tap(find.text('链式节点').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('新增链式节点'), findsOneWidget);
    await tester.tap(find.byTooltip('新增链式节点'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('选择前置节点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KR').last);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.textContaining('选择当前节点'), findsNothing);
    expect(find.textContaining('本机 →'), findsNothing);
    await tester.tap(find.byTooltip('选择作用节点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上海'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(loadYaml(saved!)['proxies'][0]['dialer-proxy'], 'KR');
    expect(saves, 1);
    expect(find.text('链式节点 1'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('订阅管理'), findsOneWidget);
    await tester.ensureVisible(find.text('链式节点').last);
    await tester.tap(find.text('链式节点').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('链式节点 1'));
    await tester.pumpAndSettle();
    expect(find.text('前置节点（1）'), findsOneWidget);
    expect(find.text('KR'), findsOneWidget);
    await tester.tap(find.byTooltip('选择前置节点'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'KR'))
            .value,
        isTrue);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('链式节点 1'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('订阅管理'), findsOneWidget);
    expect(saves, 1);
    expect(find.text('添加后置代理'), findsNothing);
    expect(saves, 1);
    expect(find.text('订阅管理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('front chain chooser creates and edits independent numbered sets',
      (tester) async {
    final expanded = content.replaceFirst('type: ss}]',
        'type: ss}, {name: wap, type: http}, {name: front2, type: http}]');
    var saved = setProxyChainSet(expanded, '1', ['wap'],
        prepend: true, targets: ['上海']);
    var saves = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [profile];
      if (call.method == 'getConfigContent') return saved;
      if (call.method == 'saveConfigContent') {
        saved = call.arguments['content'] as String;
        saves++;
        return [profile];
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    await tester
        .pumpWidget(const MaterialApp(home: ConfigPage(proxyRunning: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('链式节点').last);
    await tester.tap(find.text('链式节点').last);
    await tester.pumpAndSettle();
    expect(find.text('链式节点 1'), findsOneWidget);
    await tester.tap(find.byTooltip('新增链式节点'));
    await tester.pumpAndSettle();
    expect(find.text('链式节点 2'), findsOneWidget);
    await tester.tap(find.byTooltip('选择前置节点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('front2'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择作用节点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KR'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(readProxyChains(saved), {'上海': 'wap', 'KR': 'front2'});
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('链式节点 1'), findsOneWidget);
    expect(find.text('链式节点 2'), findsOneWidget);
    await tester.tap(find.text('链式节点 2'));
    await tester.pumpAndSettle();
    expect(find.text('front2'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });

  Future<void> openAirports(WidgetTester tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: ConfigPage(proxyRunning: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('订阅管理'));
    await tester.tap(find.text('订阅管理'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('添加机场'), findsOneWidget);
  }

  Future<void> confirmAirportUpdate(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
  }

  final multiProfile = {
    ...profile,
    'url': 'https://example.org/a\nhttps://example.org/b',
    'subscriptionNames': {
      'https://example.org/a': '第一机场',
      'https://example.org/b': '第二机场'
    },
    'subscriptionInfos': {
      'https://example.org/a': 'upload=0;download=0;total=1073741824;expire=0',
      'https://example.org/b': 'upload=0;download=0;total=2147483648;expire=0'
    },
  };

  testWidgets(
      'airport info opens two fields; editing name and URL updates only that airport',
      (tester) async {
    var current = Map<String, Object>.from(profile);
    var updates = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [current];
      if (call.method == 'getConfigContent') return content;
      if (call.method == 'editSubscriptionAirport') {
        updates++;
        expect(call.arguments['oldUrl'], 'https://example.org/sub');
        expect(call.arguments['name'], '新机场');
        expect(call.arguments['url'], 'https://example.org/new');
        current = {
          ...current,
          'url': call.arguments['url'] as String,
          'subscriptionNames': {'https://example.org/new': '新机场'}
        };
        return [current];
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    await openAirports(tester);
    expect(find.text('修改订阅'), findsNothing);
    expect(find.text('更新订阅'), findsNothing);
    expect(find.text('检测订阅链接'), findsNothing);
    expect(find.text('1. 剩余流量：1.00 GB · 到期时间：不限时'), findsOneWidget);
    await tester.tap(find.text('Airport').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.tapAt(const Offset(5, 5)); // Dismiss without saving.
    await tester.pumpAndSettle();
    expect(updates, 0);
    await tester.tap(find.text('Airport').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '机场名称'), '新机场');
    await tester.enterText(
        find.widgetWithText(TextField, '订阅链接'), 'https://example.org/new');
    await tester.tap(find.text('保存并更新'));
    await confirmAirportUpdate(tester);
    expect(find.text('新机场'), findsOneWidget);
    expect(updates, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'all airport names and usage are shown; update sends the clicked link only',
      (tester) async {
    Map<Object?, Object?>? args;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [multiProfile];
      if (call.method == 'getConfigContent') return content;
      if (call.method == 'editSubscriptionAirport') {
        args = Map<Object?, Object?>.from(call.arguments as Map);
        return [multiProfile];
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    await openAirports(tester);
    expect(find.text('第一机场'), findsOneWidget);
    expect(find.text('第二机场'), findsOneWidget);
    expect(find.text('1. 剩余流量：1.00 GB · 到期时间：不限时'), findsOneWidget);
    expect(find.text('2. 剩余流量：2.00 GB · 到期时间：不限时'), findsOneWidget);
    await tester.tap(find.text('第二机场'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '订阅链接'))
            .controller!
            .text,
        'https://example.org/b');
    await tester.tap(find.text('保存并更新'));
    await confirmAirportUpdate(tester);
    expect(args, {
      'id': 'airport',
      'oldUrl': 'https://example.org/b',
      'name': '第二机场',
      'url': 'https://example.org/b'
    });
    expect(find.text('第二机场'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'airport refresh updates the clicked link without opening the editor',
      (tester) async {
    Map<Object?, Object?>? args;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [multiProfile];
      if (call.method == 'getConfigContent') return content;
      if (call.method == 'editSubscriptionAirport') {
        args = Map<Object?, Object?>.from(call.arguments as Map);
        return [multiProfile];
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    await openAirports(tester);
    await tester.tap(find.byTooltip('更新机场').last);
    await confirmAirportUpdate(tester);
    expect(args, {
      'id': 'airport',
      'oldUrl': 'https://example.org/b',
      'name': '第二机场',
      'url': 'https://example.org/b',
    });
    expect(find.byType(TextField), findsNothing);
    expect(find.text('第二机场'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'airport deletion removes the clicked link and retains the other airport',
      (tester) async {
    var current = Map<String, Object>.from(multiProfile);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [current];
      if (call.method == 'getConfigContent') return content;
      if (call.method == 'editSubscriptionAirport') {
        expect(call.arguments,
            {'id': 'airport', 'oldUrl': 'https://example.org/b'});
        current = {
          ...current,
          'url': 'https://example.org/a',
          'subscriptionNames': {'https://example.org/a': '第一机场'},
          'subscriptionInfos': {
            'https://example.org/a':
                'upload=0;download=0;total=1073741824;expire=0'
          }
        };
        return [current];
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    await openAirports(tester);
    await tester.tap(find.byTooltip('删除机场').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('第一机场'), findsOneWidget);
    expect(find.text('第二机场'), findsNothing);
    expect(find.text('1. 剩余流量：1.00 GB · 到期时间：不限时'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'airport info can be dragged and names follow the reordered links',
      (tester) async {
    var current = Map<String, Object>.from(multiProfile);
    List<String>? savedOrder;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return [current];
      if (call.method == 'getConfigContent') return content;
      if (call.method == 'editSubscriptionAirport') {
        savedOrder = List<String>.from(call.arguments['order'] as List);
        current = {...current, 'url': savedOrder!.join('\n')};
        return [current];
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    await openAirports(tester);
    final handle = find.byType(ReorderableDragStartListener).last;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -5));
    await tester.pump();
    await gesture.moveTo(
        tester.getCenter(find.byType(ReorderableDragStartListener).first));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(savedOrder, ['https://example.org/b', 'https://example.org/a']);
    expect(find.text('第二机场'), findsOneWidget);
    expect(find.text('第一机场'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('batch proxies require manually selected targets',
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
    await tester.tap(find.byTooltip('选择前置节点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((tile) => tile.value == true),
        isTrue);
    await tester.tap(find.text('清空选择'));
    await tester.pumpAndSettle();
    expect(find.text('前置节点（0）'), findsOneWidget);
    await tester.tap(find.byTooltip('选择前置节点'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(4));
    expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((tile) => tile.value == false),
        isTrue);
    await tester.tap(find.text('C'));
    await tester.tap(find.text('D'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('选择作用节点'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((tile) => tile.value == false),
        isTrue);
    await tester.tap(find.text('A'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(targets, ['A']);
    expect(proxies, ['C', 'D']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved chain order survives selection and can be dragged',
      (tester) async {
    for (final prepend in [true, false]) {
      List<String>? savedOrder;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () => showProxyChainDialog(
                      context: context,
                      nodes: ['A', 'B', 'C', 'D'],
                      initialNodes: ['D', 'C'],
                      initialTargets: ['A'],
                      prepend: prepend,
                      onSave: (current, other) async => savedOrder = other),
                  child: const Text('打开')))));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<ListTile>(find.descendant(
                  of: find.byType(ReorderableListView),
                  matching: find.byType(ListTile)))
              .map((tile) => (tile.key as ValueKey<String>).value),
          ['D', 'C']);
      await tester.tap(find.byTooltip(prepend ? '选择前置节点' : '选择后置节点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<ListTile>(find.descendant(
                  of: find.byType(ReorderableListView),
                  matching: find.byType(ListTile)))
              .map((tile) => (tile.key as ValueKey<String>).value),
          ['D', 'C']);
      final handle = find.byType(ReorderableDragStartListener).last;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -5));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('C')).dy,
          lessThan(tester.getTopLeft(find.text('D')).dy));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(savedOrder, ['C', 'D']);
    }
  });

  testWidgets('chain cycle failures keep the dialog open', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () => showProxyChainDialog(
                    context: context,
                    nodes: ['A', 'B'],
                    initialTargets: ['A'],
                    prepend: false,
                    onSave: (_, __) async =>
                        throw const FormatException('代理链路形成循环'),
                  ),
                  child: const Text('打开'),
                ))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择后置节点'));
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
