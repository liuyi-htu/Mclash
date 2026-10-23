import 'package:mclash/shared/glass_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/pulse_dashboard.dart';

void main() {
  testWidgets(
      'portrait page titles share height and vertical position at all text sizes',
      (tester) async {
    for (final size in [const Size(390, 850)]) {
      for (final scale in [1.0, 1.8]) {
        double? top, height;
        for (final title in ['Mclash', '配置与订阅', '设置', '代理面板']) {
          await tester.pumpWidget(MaterialApp(
              home: MediaQuery(
            data: MediaQueryData(
                size: size, textScaler: TextScaler.linear(scale)),
            child: Builder(
                builder: (context) => Scaffold(
                      appBar: pulseAppBar(context,
                          title: title,
                          badge: 'ROOT',
                          actions: title == '代理面板'
                              ? [
                                  IconButton(
                                      onPressed: () {},
                                      icon: const Icon(Icons.speed))
                                ]
                              : []),
                      body: const SizedBox(key: ValueKey('page-body')),
                    )),
          )));
          await tester.pumpAndSettle();
          final currentTop = tester.getTopLeft(find.text(title)).dy;
          final currentHeight =
              tester.getTopLeft(find.byKey(const ValueKey('page-body'))).dy;
          expect(currentTop, closeTo(22, 1));
          top ??= currentTop;
          height ??= currentHeight;
          expect(currentTop, closeTo(top, .1));
          expect(currentHeight, closeTo(height, .1));
          expect(tester.takeException(), isNull);
        }
      }
    }
  });
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
      final hidden = size.width > size.height;
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
          expect(find.byKey(const ValueKey('pulse-page-title')),
              hidden && !withActions ? findsNothing : findsOneWidget);
          if (title == 'Mclash') {
            expect(find.text('ROOT'), hidden ? findsNothing : findsOneWidget);
          }
          if (hidden && !withActions) {
            expect(
                tester.getTopLeft(find.byKey(const ValueKey('page-body'))).dy,
                24);
          }
          if (withActions) {
            expect(find.text('测速进度'), findsOneWidget);
            await tester.tap(find.byTooltip('全部测速'));
            expect(taps, 1);
            if (hidden) {
              expect(
                  tester.getTopLeft(find.byKey(const ValueKey('page-body'))).dy,
                  closeTo(
                      24 +
                          (23 * scale * 1.45).clamp(48.0, double.infinity) +
                          30,
                      .01));
            }
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
  testWidgets('rail page headers align in both orientations and respect insets',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(900, 420),
      const Size(800, 1200),
      const Size(750, 1100),
    ]) {
      tester.view.physicalSize = size;
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
                size: size,
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
                        ? Builder(
                            builder: (pageContext) => Scaffold(
                                appBar: pulseAppBar(pageContext, title: title),
                                body: body))
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
          expect(page.right, size.width - insets.right);
          if (size.width > size.height) {
            expect(find.byKey(const ValueKey('pulse-page-title')),
                title == '代理面板' ? findsOneWidget : findsNothing);
            expect(page.top,
                title == '代理面板' ? greaterThan(insets.top) : insets.top);
          } else {
            expect(tester.getTopLeft(find.text(title).last).dx,
                greaterThan(rail.right));
            final firstIcon = find.descendant(
                of: find.byType(NavigationRail),
                matching: find.byIcon(PulseBottomBar.icons.first));
            expect(tester.getCenter(find.text(title).last).dy,
                closeTo(tester.getCenter(firstIcon).dy, 1));
          }
          for (var i = 0; i < PulseBottomBar.labels.length; i++) {
            await tester.tap(find.descendant(
                of: find.byType(NavigationRail),
                matching: find.text(PulseBottomBar.labels[i])));
            expect(selected, i);
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
  });
}
