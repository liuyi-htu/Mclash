import 'package:mclash/glass_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/pulse_dashboard.dart';

void main() {
  testWidgets(
      'landscape headers hide home badges and restore the proxy panel title',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in [
      const Size(390, 850),
      const Size(600, 390),
      const Size(900, 420),
      const Size(800, 1200)
    ]) {
      tester.view.physicalSize = size;
      for (final scale in [1.0, 1.8]) {
        for (final title in ['Mclash', '配置与订阅', '设置', '代理面板']) {
          var taps = 0;
          final withActions = title == '代理面板';
          await tester.pumpWidget(MaterialApp(
              home: MediaQuery(
            data: MediaQueryData(
                size: size,
                padding: const EdgeInsets.only(top: 24),
                textScaler: TextScaler.linear(scale)),
            child: Builder(
                builder: (context) => Scaffold(
                      appBar: pulseAppBar(context,
                          title: title,
                          badge: 'ROOT',
                          actions: withActions
                              ? [
                                  IconButton(
                                      tooltip: '全部测速',
                                      onPressed: () => taps++,
                                      icon: const Icon(Icons.speed))
                                ]
                              : [],
                          bottom: withActions
                              ? const PreferredSize(
                                  preferredSize: Size.fromHeight(30),
                                  child:
                                      SizedBox(height: 30, child: Text('测速进度')))
                              : null),
                      body: const SizedBox.expand(key: ValueKey('page-body')),
                    )),
          )));
          await tester.pumpAndSettle();
          expect(
              find.byKey(const ValueKey('pulse-page-title')),
              size.width > size.height && withActions
                  ? findsOneWidget
                  : findsNothing);
          if (title == 'Mclash') {
            expect(find.text('ROOT'),
                size.width > size.height ? findsNothing : findsOneWidget);
          }
          if (!withActions && (title != 'Mclash' || size.width > size.height)) {
            expect(
                tester.getTopLeft(find.byKey(const ValueKey('page-body'))).dy,
                24);
          }
          if (withActions) {
            expect(find.text('测速进度'), findsOneWidget);
            await tester.tap(find.byTooltip('全部测速'));
            expect(taps, 1);
            expect(
                tester.getTopLeft(find.byKey(const ValueKey('page-body'))).dy,
                closeTo(
                    24 +
                        (size.width > size.height
                            ? (23 * scale * 1.45).clamp(48.0, double.infinity)
                            : 48) +
                        30,
                    .01));
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('home power button reflects running stopped and pending states',
      (tester) async {
    var calls = 0;
    for (final state in [
      (false, false),
      (true, false),
      (true, true),
      (false, true)
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PulseDashboard(
        running: state.$1,
        busy: state.$2,
        status: state.$1 ? '运行中' : '未启动',
        mode: 'rule',
        download: '0 B/s',
        upload: '0 B/s',
        changingMode: false,
        onToggle: () => calls++,
        onMode: (_) {},
        onRefresh: () async {},
      ))));
      await tester.pump();
      final button = find.descendant(
          of: find.byKey(const ValueKey('service-toggle')),
          matching: find.byType(IconButton));
      expect(
          tester.widget<IconButton>(button).tooltip,
          state.$2
              ? '处理中'
              : state.$1
                  ? '停止服务'
                  : '启动服务');
      expect(tester.widget<IconButton>(button).onPressed == null, state.$2);
      expect(
          find.descendant(
              of: button, matching: find.byType(CircularProgressIndicator)),
          state.$2 ? findsOneWidget : findsNothing);
      final context = tester.element(button);
      expect(
          tester
              .widget<Material>(find.byKey(const ValueKey('service-toggle')))
              .color,
          state.$1 && !state.$2
              ? pulseGlassFill(context)
              : Theme.of(context).colorScheme.surfaceContainerLow);
      if (!state.$2) await tester.tap(button);
    }
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('landscape page headers keep navigation fixed and usable',
      (tester) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final insets in [
      const EdgeInsets.fromLTRB(28, 24, 48, 0),
      const EdgeInsets.fromLTRB(48, 24, 28, 0),
    ]) {
      Rect? initialRail;
      for (final title in ['Mclash', '配置与订阅', '设置', '代理面板']) {
        int? selected;
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(900, 420),
              padding: insets,
              viewPadding: insets,
            ),
            child: Builder(builder: (context) {
              final header = pulseAppBar(context, title: title);
              const body = SizedBox.expand(key: ValueKey('page-body'));
              return Scaffold(
                body: PulseNavigation(
                  index: 0,
                  onSelected: (index) => selected = index,
                  appBar: title == '代理面板' ? null : header,
                  child: title == '代理面板'
                      ? Scaffold(appBar: header, body: body)
                      : body,
                ),
              );
            }),
          ),
        ));
        await tester.pumpAndSettle();
        final rail = tester.getRect(find.byType(NavigationRail));
        initialRail ??= rail;
        expect(rail, initialRail);
        expect(rail.left, insets.left);
        expect(rail.top, insets.top);
        final page = tester.getRect(find.byKey(const ValueKey('page-body')));
        expect(page.left, greaterThanOrEqualTo(rail.right));
        expect(page.right, 900 - insets.right);
        expect(find.byKey(const ValueKey('pulse-page-title')),
            title == '代理面板' ? findsOneWidget : findsNothing);
        expect(
            page.top, title == '代理面板' ? greaterThan(insets.top) : insets.top);
        for (var i = 0; i < PulseBottomBar.labels.length; i++) {
          await tester.tap(find.descendant(
              of: find.byType(NavigationRail),
              matching: find.text(PulseBottomBar.labels[i])));
          expect(selected, i);
        }
        expect(tester.takeException(), isNull);
      }
    }
  });
}
