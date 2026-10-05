import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/pulse_dashboard.dart';

void main() {
  testWidgets(
      'four page titles share height and vertical position at all text sizes',
      (tester) async {
    for (final scale in [1.0, 1.8]) {
      double? top, height;
      for (final title in ['Mclash', '配置与订阅', '设置', '代理面板']) {
        await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
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
        top ??= currentTop;
        height ??= currentHeight;
        expect(currentTop, closeTo(top, .1));
        expect(currentHeight, closeTo(height, .1));
        expect(tester.takeException(), isNull);
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
              ? Theme.of(context).colorScheme.primary
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
        expect(tester.getTopLeft(find.text(title).last).dx,
            greaterThan(rail.right));
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
