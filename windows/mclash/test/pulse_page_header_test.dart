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
}
