import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/pulse_dashboard.dart';

void main() {
  testWidgets(
      'home contains service, traffic and modes without connection tests',
      (tester) async {
    String? selected;
    var toggles = 0;
    Widget dashboard({bool running = true, bool busy = false}) => MaterialApp(
        home: Scaffold(
            body: PulseDashboard(
                running: running,
                busy: busy,
                status: '运行中',
                download: '1 MB/s',
                upload: '2 KB/s',
                mode: 'rule',
                changingMode: false,
                onToggle: () => toggles++,
                onMode: (v) => selected = v,
                onRefresh: () async {})));
    await tester.pumpWidget(dashboard());
    expect(find.text('平台连接检测'), findsNothing);
    expect(find.text('全部检测'), findsNothing);
    expect(find.textContaining('出口节点'), findsNothing);
    expect(find.text('1 MB/s'), findsOneWidget);
    await tester.tap(find.text('全局'));
    expect(selected, 'global');
    await tester.tap(find.byIcon(Icons.power_settings_new));
    expect(toggles, 1);
    selected = null;
    await tester.pumpWidget(dashboard(running: false));
    await tester.tap(find.text('直连'));
    expect(selected, isNull);
    await tester.pumpWidget(dashboard(busy: true));
    await tester.tap(find.byIcon(Icons.power_settings_new));
    expect(toggles, 1);
  });

  testWidgets('desktop rail adapts to wide and narrow screens', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: SizedBox(
            width: 900,
            child: PulseNavigation(
                index: 0, onSelected: (_) {}, child: const Text('Body')))));
    expect(find.byType(NavigationRail), findsOneWidget);
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: PulseNavigation(
            index: 0, onSelected: (_) {}, child: const Text('Body'))));
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('small screen and enlarged text have no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: Scaffold(
                body: PulseDashboard(
                    running: false,
                    busy: false,
                    status: '未启动',
                    download: '0 B/s',
                    upload: '0 B/s',
                    mode: null,
                    changingMode: false,
                    onToggle: () {},
                    onMode: (_) {},
                    onRefresh: () async {})))));
    expect(tester.takeException(), isNull);
  });
}
