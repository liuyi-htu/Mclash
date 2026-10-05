import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mclash/pages/config_page.dart';

Map<String, Object> profile(int i, {bool active = false}) => {
      'id': '$i',
      'name': '配置$i',
      'type': 'local',
      'active': active,
      'exists': true,
      'updatedAt': 0,
    };

void main() {
  testWidgets('active configuration leads the stack and switching collapses it',
      (tester) async {
    var profiles = [profile(1), profile(2, active: true), profile(3)];
    const channel = MethodChannel('mclash/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return profiles;
      if (call.method == 'selectConfig') {
        final id = (call.arguments as Map)['id'];
        profiles = [
          for (final p in profiles) {...p, 'active': p['id'] == id}
        ];
        return {'exists': true};
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester
        .pumpWidget(MaterialApp(home: const ConfigPage(proxyRunning: false)));
    await tester.pumpAndSettle();
    expect(find.text('配置工具'), findsNothing);
    for (final title in ['手动节点', '链式节点', '规则管理', '代理组管理']) {
      expect(find.text(title), findsNothing);
    }
    expect(find.text('配置2'), findsOneWidget);
    expect(find.text('配置1'), findsNothing);
    expect(find.text('配置3'), findsNothing);
    final cardHeight =
        tester.getSize(find.byKey(const ValueKey('config-card-2'))).height;
    final toggle = find.byKey(const ValueKey('toggle-config-stack'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    for (final id in ['1', '2', '3']) {
      expect(tester.getSize(find.byKey(ValueKey('config-card-$id'))).height,
          closeTo(cardHeight, .1));
    }
    expect(find.text('收起'), findsNothing);
    expect(find.text('3 个配置'), findsNothing);
    expect(tester.getTopLeft(find.text('配置2')).dy,
        lessThan(tester.getTopLeft(find.text('配置1')).dy));
    expect(tester.getTopLeft(find.text('配置1')).dy,
        lessThan(tester.getTopLeft(find.text('配置3')).dy));
    await tester.tap(find.text('配置3'));
    await tester.pumpAndSettle();
    expect(profiles.singleWhere((p) => p['active'] == true)['id'], '3');
    expect(find.text('配置3'), findsOneWidget);
    expect(find.text('配置2'), findsNothing);
    expect(find.byKey(const ValueKey('config-profile-stack')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('many configurations remain compact while running at large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var profiles = List.generate(30, (i) => profile(i, active: i == 29));
    const channel = MethodChannel('mclash/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return profiles;
      if (call.method == 'selectConfig') {
        final id = (call.arguments as Map)['id'];
        profiles = [
          for (final p in profiles) {...p, 'active': p['id'] == id}
        ];
        return {'exists': true};
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: const ConfigPage(proxyRunning: true))));
    await tester.pumpAndSettle();
    expect(find.text('配置29'), findsOneWidget);
    expect(find.text('配置0'), findsNothing);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('config-profile-stack')))
            .height,
        lessThan(220));
    final toggle = find.byKey(const ValueKey('toggle-config-stack'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('配置0'), findsOneWidget);
    expect(
        tester.getSize(find.byKey(const ValueKey('config-card-0'))).height,
        closeTo(
            tester.getSize(find.byKey(const ValueKey('config-card-29'))).height,
            .1));
    await tester.tap(find.text('配置29'));
    await tester.pumpAndSettle();
    expect(find.text('配置0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'single configuration has no stack controls and no active falls back to first',
      (tester) async {
    var profiles = [profile(1)];
    const channel = MethodChannel('mclash/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigs') return profiles;
      if (call.method == 'selectConfig') {
        final id = (call.arguments as Map)['id'];
        profiles = [
          for (final p in profiles) {...p, 'active': p['id'] == id}
        ];
        return {'exists': true};
      }
      throw StateError('Unexpected call: ${call.method}');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester
        .pumpWidget(MaterialApp(home: const ConfigPage(proxyRunning: false)));
    await tester.pumpAndSettle();
    expect(find.text('配置1'), findsOneWidget);
    expect(find.byKey(const ValueKey('toggle-config-stack')), findsNothing);
    expect(find.byKey(const ValueKey('config-profile-stack')), findsNothing);
    profiles = [profile(1), profile(2)];
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('config-profile-stack')), findsOneWidget);
    expect(find.text('配置1'), findsOneWidget);
    expect(find.text('配置2'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
