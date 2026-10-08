import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/config_page.dart';
import 'package:mclash/models.dart';
import 'package:mclash/proxy_platform_service.dart';

class _Service implements ProxyPlatformService {
  bool updated = false;
  bool fail = false;
  static const profile = ConfigProfile(
      id: 'airport',
      name: 'Airport',
      type: 'subscription',
      active: true,
      exists: true,
      updatedAt: 0,
      url: 'https://example.org/sub');

  @override
  Future<List<ConfigProfile>> getConfigs() async => [profile];
  @override
  Future<String> getConfigContent(String id) async => updated
      ? 'proxies: [{name: Changed, type: http, port: 81}, {name: Added, type: http}]'
      : 'proxies: [{name: Changed, type: http, port: 80}, {name: Removed, type: http}]';
  @override
  Future<List<ConfigProfile>> addSubscription(
      {required String name,
      required String url,
      Map<String, String>? subscriptionNames}) async {
    updated = true;
    return [
      profile,
      ConfigProfile(
          id: 'new-airport',
          name: name,
          type: 'subscription',
          active: false,
          exists: true,
          updatedAt: 0,
          url: url)
    ];
  }

  @override
  Future<List<ConfigProfile>> editSubscriptionAirport(String id,
      {String? oldUrl, String? name, String? url, List<String>? order}) async {
    if (fail) throw StateError('更新失败');
    updated = true;
    return [profile];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('first subscription download reports all nodes as added',
      (tester) async {
    final service = _Service();
    await tester.pumpWidget(
        MaterialApp(home: ConfigPage(proxyRunning: false, service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加机场配置'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '配置名称'), '新配置');
    await tester.enterText(find.widgetWithText(TextField, '机场 1 名称'), '新机场');
    await tester.enterText(
        find.widgetWithText(TextField, '机场 1 订阅链接'), 'https://example.org/new');
    await tester.tap(find.text('添加并下载'));
    await tester.pumpAndSettle();
    expect(find.text('订阅已添加'), findsOneWidget);
    expect(find.text('新增（2）'), findsOneWidget);
    expect(find.text('Changed'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('变动（0）'), findsOneWidget);
    expect(find.text('删除（0）'), findsOneWidget);
    expect(find.text('配置已保存，新配置将在下次启动时应用。'), findsNothing);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows airport update shows actual diff only after success',
      (tester) async {
    final service = _Service();
    await tester.pumpWidget(
        MaterialApp(home: ConfigPage(proxyRunning: false, service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Airport').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('订阅管理'));
    await tester.tap(find.text('订阅管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更新机场'));
    await tester.pumpAndSettle();
    expect(find.text('新增（1）'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('变动（1）'), findsOneWidget);
    expect(find.text('Changed'), findsOneWidget);
    expect(find.text('删除（1）'), findsOneWidget);
    expect(find.text('Removed'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    service.fail = true;
    await tester.tap(find.byTooltip('更新机场'));
    await tester.pumpAndSettle();
    expect(find.text('新增（1）'), findsNothing);
    expect(find.textContaining('更新失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
