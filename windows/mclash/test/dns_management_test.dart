import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:mclash/dns_management.dart';
import 'package:mclash/config_management.dart';
import 'package:mclash/config_page.dart';
import 'package:mclash/models.dart';
import 'package:mclash/proxy_platform_service.dart';

class _Service implements ProxyPlatformService {
  _Service(this.save, {required this.active});
  final bool active;
  String? latest;
  final void Function(String) save;
  @override
  Future<List<ConfigProfile>> getConfigs() async => [
        if (!active)
          const ConfigProfile(
              id: 'other',
              name: '当前配置',
              type: 'local',
              active: true,
              exists: true,
              updatedAt: 0),
        ConfigProfile(
            id: 'test',
            name: '测试配置',
            type: 'local',
            active: active,
            exists: true,
            updatedAt: 0)
      ];
  @override
  Future<String> getRuntimeConfigContent() async {
    expect(active, isTrue);
    return latest == null
        ? runtime
        : updateConfigDns(runtime, configDnsText(latest!));
  }

  @override
  Future<String> getConfigContent(String id) async {
    expect(id, 'test');
    return latest ?? source;
  }

  @override
  Future<List<ConfigProfile>> saveConfigContent(
      {required String id, required String content}) async {
    expect(id, 'test');
    latest = content;
    save(content);
    return getConfigs();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const source =
    '# metadata\nproxies: []\ndns:\n  enable: true\n  nameserver: [https://dns.example/dns-query]\nrules: [MATCH,DIRECT]\n';
const runtime =
    'proxies: [{name: injected, type: dns}]\ndns: {enable: true, ipv6: false, nameserver: [9.9.9.9]}\nrules: [MATCH,REJECT]\n';

void main() {
  test('DNS editing preserves other sections and supports missing DNS', () {
    final next =
        updateConfigDns(source, 'enable: false\nnameserver: [1.1.1.1]');
    expect(loadYaml(next)['dns']['enable'],
        managedDnsKeys.contains('enable') ? true : false);
    expect(loadYaml(next)['rules'], loadYaml(source)['rules']);
    expect(next, startsWith('# metadata\nproxies: []\n'));
    expect(loadYaml(configDnsText(source)), {
      for (final entry in (loadYaml(source)['dns'] as Map).entries)
        if (!managedDnsKeys.contains(entry.key)) entry.key: entry.value
    });
    expect(loadYaml(updateConfigDns('rules: []\n', '{}'))['dns'], isEmpty);
    for (final text in ['[1, 2]', 'enable: [', '', 'null']) {
      expect(() => updateConfigDns(source, text), throwsFormatException);
    }
  });
  test('fields managed by other controls are hidden and cannot be overwritten',
      () {
    const text =
        'dns: {enable: true, ipv6: true, listen: "0.0.0.0:1053", enhanced-mode: redir-host, nameserver: [1.1.1.1]}\nrules: []\n';
    final displayed = loadYaml(configDnsText(text)) as Map;
    for (final key in managedDnsKeys) {
      expect(displayed.containsKey(key), false);
    }
    final edited = updateConfigDns(text,
        'nameserver: [8.8.8.8]\nenable: false\nipv6: false\nlisten: "127.0.0.1:5555"\nenhanced-mode: fake-ip');
    final saved = loadYaml(edited)['dns'] as Map;
    for (final key in managedDnsKeys) {
      expect(saved[key], loadYaml(text)['dns'][key]);
    }
    expect(saved['nameserver'], ['8.8.8.8']);
  });
  test('DNS management always follows rules regardless of YAML order', () {
    for (final content in [source, 'dns: {}\nrules: []\nproxies: []\n']) {
      final actions = configActionOrder(content);
      expect(actions[actions.indexOf('rules') + 1], 'dns');
    }
  });
  testWidgets('dialog validates DNS and keeps failed drafts', (tester) async {
    var calls = 0;
    var fail = true;
    var saved = '';
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      child: const Text('打开'),
                      onPressed: () => showDnsManagementDialog(
                            context: context,
                            content: source,
                            onSave: (text) async {
                              calls++;
                              if (fail) throw StateError('保存失败');
                              saved = updateConfigDns(source, text);
                            },
                          )),
                ))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).controller!.text,
        contains('nameserver'));
    await tester.enterText(field, '[invalid]');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('DNS 配置必须是 YAML 映射'), findsOneWidget);
    await tester.enterText(field, 'nameserver: [8.8.4.4]');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text,
        'nameserver: [8.8.4.4]');
    fail = false;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(loadYaml(saved)['dns']['nameserver'], ['8.8.4.4']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final active in [true, false]) {
    testWidgets(
        'DNS menu opens editor and saves the selected profile active=$active',
        (tester) async {
      String? saved;
      final service = _Service((text) => saved = text, active: active);
      await tester.pumpWidget(
          MaterialApp(home: ConfigPage(proxyRunning: false, service: service)));
      await tester.pumpAndSettle();
      if (active) {
        await tester.tap(find.text('测试配置').first);
      } else {
        await tester.tap(find.byKey(const ValueKey('toggle-config-stack')));
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(
            of: find.byKey(const ValueKey('config-card-test')),
            matching: find.byTooltip('管理配置')));
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('DNS 管理'));
      expect(tester.getTopLeft(find.text('DNS 管理')).dy,
          greaterThan(tester.getTopLeft(find.text('规则管理')).dy));
      await tester.tap(find.text('DNS 管理'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
          loadYaml(tester
              .widget<TextField>(find.byType(TextField))
              .controller!
              .text),
          loadYaml(configDnsText(active ? runtime : source)));
      await tester.enterText(
          find.byType(TextField), 'enable: false\nnameserver: [8.8.8.8]');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(loadYaml(saved!)['dns']['nameserver'], ['8.8.8.8']);
      expect(loadYaml(saved!)['rules'], loadYaml(source)['rules']);
      expect(loadYaml(saved!)['proxies'], isEmpty);
      // The menu is restored after saving; re-opening reads the synchronized DNS.
      await tester.ensureVisible(find.text('DNS 管理'));
      await tester.tap(find.text('DNS 管理'));
      await tester.pumpAndSettle();
      expect(
          loadYaml(tester
              .widget<TextField>(find.byType(TextField))
              .controller!
              .text)['nameserver'],
          ['8.8.8.8']);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('DNS dialog fits a small screen with keyboard and cancels safely',
      (tester) async {
    tester.view.physicalSize = const Size(320, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      child: const Text('打开'),
                      onPressed: () => showDnsManagementDialog(
                            context: context,
                            content: source,
                            onSave: (_) async {
                              calls++;
                            },
                          )),
                ))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 230);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '[invalid]');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
