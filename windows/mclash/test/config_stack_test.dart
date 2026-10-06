import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/config_page.dart';
import 'package:mclash/models.dart';
import 'package:mclash/proxy_platform_service.dart';

class _Service implements ProxyPlatformService {
  _Service(this.read, this.select);
  final List<Map<String, Object>> Function() read;
  final void Function(String) select;
  @override
  Future<List<ConfigProfile>> getConfigs() async =>
      read().map(ConfigProfile.fromMap).toList();
  @override
  Future<ConfigInfo> selectConfig(String id) async {
    select(id);
    return const ConfigInfo(exists: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object> profile(int i, {bool active = false}) => {
      'id': '$i',
      'name': '配置$i',
      'type': 'local',
      'active': active,
      'exists': true,
      'updatedAt': 0,
    };

void main() {
  testWidgets('existing lone subscription without a selection shows airports',
      (tester) async {
    var profiles = [
      {
        ...profile(1),
        'type': 'subscription',
        'url': 'https://example.org/subscription',
        'subscriptionNames': {'https://example.org/subscription': '已有机场'},
      }
    ];
    final service = _Service(() => profiles, (id) {
      profiles = [
        for (final p in profiles) {...p, 'active': p['id'] == id}
      ];
    });
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: ConfigPage(proxyRunning: false, service: service)));
    await tester.pumpAndSettle();
    expect(profiles.single['active'], isTrue);
    expect(find.text('机场订阅'), findsOneWidget);
    expect(find.text('已有机场'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Windows shows airport information after selecting a subscription',
      (tester) async {
    var profiles = [
      profile(1, active: true),
      {
        ...profile(2),
        'type': 'subscription',
        'url': 'https://example.org/subscription',
        'subscriptionNames': {'https://example.org/subscription': '测试机场'},
        'subscriptionInfos': {
          'https://example.org/subscription':
              'upload=0; download=1073741824; total=10737418240; expire=1893456000'
        },
      },
    ];
    final service = _Service(() => profiles, (id) {
      profiles = [
        for (final p in profiles) {...p, 'active': p['id'] == id}
      ];
    });
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: ConfigPage(proxyRunning: false, service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-config-stack')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配置2'));
    await tester.pumpAndSettle();
    expect(find.text('机场订阅'), findsOneWidget);
    expect(find.text('测试机场'), findsOneWidget);
    expect(find.textContaining('9.00 GB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active configuration leads the stack and switching collapses it',
      (tester) async {
    var profiles = [profile(1), profile(2, active: true), profile(3)];
    final service = _Service(() => profiles, (id) {
      profiles = [
        for (final p in profiles) {...p, 'active': p['id'] == id}
      ];
    });
    await tester.pumpWidget(
        MaterialApp(home: ConfigPage(proxyRunning: false, service: service)));
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
    final service = _Service(() => profiles, (id) {
      profiles = [
        for (final p in profiles) {...p, 'active': p['id'] == id}
      ];
    });
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: ConfigPage(proxyRunning: true, service: service))));
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
    expect(find.text('配置0'), findsNothing);
    expect(tester.widget<TextButton>(toggle).onPressed, isNull);
    final cardInk = find
        .descendant(
            of: find.byKey(const ValueKey('config-card-29')),
            matching: find.byType(InkWell))
        .first;
    expect(tester.widget<InkWell>(cardInk).onLongPress, isNull);
    expect(find.byKey(const ValueKey('config-profile-stack')), findsOneWidget);
    expect(find.text('配置0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'single configuration has no stack controls and no active falls back to first',
      (tester) async {
    var profiles = [profile(1)];
    final service = _Service(() => profiles, (id) {
      profiles = [
        for (final p in profiles) {...p, 'active': p['id'] == id}
      ];
    });
    await tester.pumpWidget(
        MaterialApp(home: ConfigPage(proxyRunning: false, service: service)));
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
  testWidgets(
      'starting proxy collapses an already expanded configuration stack',
      (tester) async {
    final service =
        _Service(() => [profile(1, active: true), profile(2)], (_) {});
    await tester.pumpWidget(
        MaterialApp(home: ConfigPage(proxyRunning: false, service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-config-stack')));
    await tester.pumpAndSettle();
    expect(find.text('配置2'), findsOneWidget);
    await tester.pumpWidget(
        MaterialApp(home: ConfigPage(proxyRunning: true, service: service)));
    await tester.pumpAndSettle();
    expect(find.text('配置2'), findsNothing);
    expect(find.byKey(const ValueKey('config-profile-stack')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('stack body opens management and only top right button expands',
      (tester) async {
    final service =
        _Service(() => [profile(1, active: true), profile(2)], (_) {});
    await tester.pumpWidget(
        MaterialApp(home: ConfigPage(proxyRunning: false, service: service)));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('toggle-config-stack'));
    final card = find.byKey(const ValueKey('config-card-1'));
    expect(tester.getCenter(toggle).dx, greaterThan(tester.getCenter(card).dx));
    expect(tester.getTopLeft(toggle).dy - tester.getTopLeft(card).dy,
        lessThan(30));
    await tester.tap(find.text('配置1'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('config-profile-stack')), findsOneWidget);
    expect(find.text('配置2'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('配置2'), findsOneWidget);
    expect(find.byTooltip('管理配置'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
