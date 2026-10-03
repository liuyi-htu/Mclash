import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/home_page.dart';
import 'package:mclash/models.dart';
import 'package:mclash/proxy_platform_service.dart';
import 'package:mclash/proxy_panel_page.dart';

class _Service implements ProxyPlatformService {
  bool running = false;
  bool failStatus = false;
  ProxyStatus? statusOverride;
  Completer<ProxyStatus>? statusGate;
  int statusCalls = 0;
  int versionChecks = 0;
  int updates = 0;
  bool alreadyLatest = false;
  Completer<void>? updateGate;
  @override
  Future<CoreUpdateInfo> checkCoreUpdate(CoreType core) async {
    versionChecks++;
    return CoreUpdateInfo(
        currentVersion: alreadyLatest ? '2.0.0' : '1.0.0',
        latestVersion: '2.0.0',
        updateAvailable: !alreadyLatest);
  }

  @override
  Future<void> updateCore(CoreType core) async {
    updates++;
    if (updateGate != null) await updateGate!.future;
    alreadyLatest = true;
  }

  @override
  Future<String> getDelayResults() async => '{}';
  @override
  Future<void> setDelayResults(String json) async {}
  @override
  Future<List<String>> getProxyGroupOrder() async => [];
  @override
  Future<String> getRuntimeConfigContent() async => 'proxy-groups: []';
  @override
  Future<bool> getUsageNoticeAccepted() async => true;
  @override
  Future<ConfigInfo> getConfigInfo() async => const ConfigInfo(exists: false);
  @override
  Future<List<ConfigProfile>> getConfigs() async => [];
  @override
  Future<bool> isRunning() async => running;
  @override
  Future<ProxyStatus> getProxyStatus() async {
    statusCalls++;
    if (failStatus) throw StateError('检测超时');
    if (statusGate != null) return statusGate!.future;
    return statusOverride ??
        (running ? ProxyStatus.running : ProxyStatus.stopped);
  }

  @override
  Future<bool> getDebugLoggingEnabled() async => false;
  @override
  Future<bool> getServiceAutoStartEnabled() async => false;
  @override
  Future<bool> getIpv6Enabled() async => false;
  @override
  Future<bool> getBypassLanEnabled() async => true;
  @override
  Future<NetworkMode> getNetworkMode() async => NetworkMode.proxy;
  @override
  Future<CoreType> getCoreType() async => CoreType.mihomo;
  @override
  Future<void> syncSystemProxy() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> openUpdate(WidgetTester tester, _Service service) async {
    await tester.pumpWidget(MaterialApp(home: HomePage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更新内核'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'update is locked until completion and installed version refreshes',
      (tester) async {
    final service = _Service()
      ..running = true
      ..updateGate = Completer<void>();
    await openUpdate(tester, service);
    await tester.tap(find.widgetWithText(FilledButton, '更新内核'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.updates, 1);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '关闭'))
            .onPressed,
        isNull);
    await tester.tapAt(const Offset(5, 5));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(service.updates, 1);
    service.updateGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('当前 2.0.0 / 官方 2.0.0'), findsOneWidget);
    expect(find.text('mihomo 内核更新完成'), findsOneWidget);
    expect(service.versionChecks, 2);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更新内核'));
    await tester.pumpAndSettle();
    expect(find.text('当前 2.0.0 / 官方 2.0.0'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '更新内核'));
    await tester.pumpAndSettle();
    expect(find.text('当前已是最新稳定版'), findsOneWidget);
    expect(service.updates, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'startup probe does not overlap and exposes failure then recovery',
      (tester) async {
    final gate = Completer<ProxyStatus>();
    final service = _Service()..statusGate = gate;
    await tester.pumpWidget(MaterialApp(home: HomePage(service: service)));
    await tester.pump();
    expect(find.text('检测中'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(service.statusCalls, 1);
    service.statusGate = null;
    gate.complete(ProxyStatus.running);
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);
    service.failStatus = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('检测失败'), findsOneWidget);
    expect(find.textContaining('状态检测失败：'), findsOneWidget);
    service.failStatus = false;
    service.statusOverride = ProxyStatus.recovering;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('恢复中'), findsOneWidget);
    service.statusOverride = ProxyStatus.running;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('已连接'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('open proxy panel follows stop and reconnect', (tester) async {
    final service = _Service();
    await tester.pumpWidget(MaterialApp(home: HomePage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('代理面板'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<ProxyPanelPage>(find.byType(ProxyPanelPage)).proxyRunning,
        false);
    service.running = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(
        tester.widget<ProxyPanelPage>(find.byType(ProxyPanelPage)).proxyRunning,
        true);
    service.running = false;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(
        tester.widget<ProxyPanelPage>(find.byType(ProxyPanelPage)).proxyRunning,
        false);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '全部测速'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets(
      'core update buttons follow connection changes while dialog is open',
      (tester) async {
    final service = _Service();
    await tester.pumpWidget(MaterialApp(home: HomePage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更新内核'));
    await tester.pumpAndSettle();
    void expectEnabled(bool enabled) {
      expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          enabled ? isNotNull : isNull);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '更新内核'))
              .onPressed,
          enabled ? isNotNull : isNull);
    }

    expectEnabled(false);
    service.running = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expectEnabled(true);
    service.running = false;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expectEnabled(false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  for (final width in [320.0, 360.0, 900.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('Windows navigation at $width in $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: brightness),
          home: HomePage(service: _Service()),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(Switch), findsOneWidget);
        expect(find.text('0 B/s'), findsNWidgets(2));
        await tester.tap(find.text('配置'));
        await tester.pumpAndSettle();
        expect(find.text('配置中心'), findsOneWidget);
        expect(find.byTooltip('添加配置'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(find.text('常规设置'), findsOneWidget);
        expect(find.text('系统代理'), findsOneWidget);
        expect(find.text('更新内核'), findsOneWidget);
        await tester.tap(find.text('常规设置'));
        await tester.pumpAndSettle();
        final sheet = find.byType(AlertDialog);
        expect(sheet, findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.getCenter(sheet).dy, closeTo(400, 1));
        expect(
            find.descendant(of: sheet, matching: find.byType(SwitchListTile)),
            findsNWidgets(3));
        for (final title in ['开机自启', '启用 IPv6', '绕过局域网']) {
          expect(find.descendant(of: sheet, matching: find.text(title)),
              findsOneWidget);
        }
        for (final title in ['运行模式', '更新内核', '调试日志', '关于']) {
          expect(find.descendant(of: sheet, matching: find.text(title)),
              findsNothing);
        }
        expect(find.widgetWithText(FilledButton, '关闭'), findsOneWidget);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('更新内核'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.getCenter(find.byType(AlertDialog)).dy, closeTo(400, 1));
        expect(find.text('检测版本'), findsOneWidget);
        for (final button in [
          find.widgetWithText(OutlinedButton, '检测版本'),
          find.widgetWithText(FilledButton, '更新内核'),
        ]) {
          final text = find.descendant(of: button, matching: find.byType(Text));
          final paragraph = tester.renderObject<RenderParagraph>(text);
          final label = tester.widget<Text>(text).data!;
          final lines = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length));
          expect(lines.map((box) => box.top).toSet(), hasLength(1));
        }
        expect(
            tester
                .widget<OutlinedButton>(find.byType(OutlinedButton))
                .onPressed,
            isNull);
        expect(
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, '更新内核'))
                .onPressed,
            isNull);
        expect(tester.takeException(), isNull);
        expect(find.widgetWithText(FilledButton, '关闭'), findsOneWidget);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('首页'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('代理面板'));
        await tester.pumpAndSettle();
        expect(find.byType(ProxyPanelPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
}
