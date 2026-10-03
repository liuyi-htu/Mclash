import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/home_page.dart';
import 'package:mclash/models.dart';
import 'package:mclash/proxy_platform_service.dart';
import 'package:mclash/proxy_panel_page.dart';

class _Service implements ProxyPlatformService {
  @override
  Future<bool> getUsageNoticeAccepted() async => true;
  @override
  Future<ConfigInfo> getConfigInfo() async => const ConfigInfo(exists: false);
  @override
  Future<List<ConfigProfile>> getConfigs() async => [];
  @override
  Future<bool> isRunning() async => false;
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
  for (final width in [360.0, 900.0]) {
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
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('更新内核'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.getCenter(find.byType(AlertDialog)).dy, closeTo(400, 1));
        expect(find.text('检测版本'), findsOneWidget);
        expect(tester.takeException(), isNull);
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
