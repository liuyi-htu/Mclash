import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core/models.dart';
import 'package:mclash/pages/network_sharing_dialog.dart';

void main() {
  const channel = MethodChannel('mclash/native');
  late ValueNotifier<ProxyStatus> status;
  var enabled = false;
  var fail = false;
  var selected = <String>[];
  var writes = <Map>[];

  setUp(() {
    status = ValueNotifier(ProxyStatus.running);
    enabled = false;
    fail = false;
    selected = [];
    writes = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setNetworkSharing') {
        final args = call.arguments as Map;
        writes.add(args);
        if (fail) throw PlatformException(code: 'sharing', message: '更新失败');
        enabled = args['enabled'] as bool;
        selected = (args['interfaces'] as List).cast<String>();
      }
      return {
        'enabled': enabled,
        'interfaces': selected,
        'availableInterfaces': enabled ? ['wlan2', 'rndis0'] : <String>[],
      };
    });
  });

  tearDown(() {
    status.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NetworkSharingDialog(proxyStatus: status)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('enable starts empty and disabling preserves selected interfaces',
      (tester) async {
    await open(tester);
    expect(find.text('wlan2'), findsNothing);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('wlan2'), findsOneWidget);
    expect(selected, isEmpty);
    expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((tile) => tile.value == false),
        true);
    await tester.tap(find.text('wlan2'));
    await tester.pumpAndSettle();
    expect(selected, ['wlan2']);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(enabled, false);
    expect(selected, ['wlan2']);
    expect(find.byType(CheckboxListTile), findsNothing);
    status.value = ProxyStatus.stopped;
    await tester.pumpAndSettle();
    status.value = ProxyStatus.running;
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(selected, ['wlan2']);
    final wlan = tester.widget<CheckboxListTile>(find.ancestor(
        of: find.text('wlan2'), matching: find.byType(CheckboxListTile)));
    expect(wlan.value, true);
  });

  testWidgets('enabled state and selections restore after restart and reopen',
      (tester) async {
    enabled = true;
    selected = ['wlan2'];
    await open(tester);
    expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, true);
    status.value = ProxyStatus.stopped;
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false);
    status.value = ProxyStatus.running;
    await tester.pumpAndSettle();
    expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, true);
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, true);
    expect(
        tester
            .widget<CheckboxListTile>(find.ancestor(
                of: find.text('wlan2'),
                matching: find.byType(CheckboxListTile)))
            .value,
        true);
    expect(writes, isEmpty);
  });

  testWidgets(
      'failed update retains previous selection and stop disables switch',
      (tester) async {
    enabled = true;
    selected = ['wlan2'];
    await open(tester);
    fail = true;
    await tester.tap(find.text('rndis0'));
    await tester.pumpAndSettle();
    expect(selected, ['wlan2']);
    expect(find.textContaining('更新失败'), findsOneWidget);
    status.value = ProxyStatus.stopped;
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('stopped proxy cannot enable sharing', (tester) async {
    status.value = ProxyStatus.stopped;
    await open(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(find.text('请先开启代理'), findsNothing);
  });
}
