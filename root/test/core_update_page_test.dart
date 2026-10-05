import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/pages/core_update_page.dart';
import 'package:mclash/core/models.dart';

void main() {
  const channel = MethodChannel('mclash/native');
  var status = 'running';
  var updates = 0;
  var checks = 0;
  late ValueNotifier<ProxyStatus> sharedStatus;
  var fail = false;
  Completer<Map<String, Object>>? pending;

  setUp(() {
    status = 'running';
    updates = 0;
    checks = 0;
    fail = false;
    pending = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkCoreUpdate':
          checks++;
          return {'currentVersion': 'v1.19.31', 'latestVersion': 'v1.19.32'};
        case 'getProxyStatus':
          return status;
        case 'updateCore':
          updates++;
          if (fail) {
            throw PlatformException(code: 'native_error', message: '校验失败');
          }
          return pending?.future ??
              {'version': 'v1.19.32', 'installed': true, 'updated': true};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> open(WidgetTester tester, {bool check = true}) async {
    sharedStatus = ValueNotifier<ProxyStatus>(
        status == 'running' ? ProxyStatus.running : ProxyStatus.stopped);
    addTearDown(sharedStatus.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
        MaterialApp(home: CoreUpdateDialog(proxyStatus: sharedStatus)));
    await tester.pumpAndSettle();
    if (!check) return;
    await tester.tap(find.text('检测版本'));
    await tester.pumpAndSettle();
    expect(find.text('v1.19.31'), findsOneWidget);
    expect(find.text('v1.19.32'), findsOneWidget);
  }

  testWidgets('outside tap closes idle dialog and waits for an active update',
      (tester) async {
    sharedStatus = ValueNotifier(ProxyStatus.running);
    addTearDown(sharedStatus.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CoreUpdateDialog(proxyStatus: sharedStatus),
                ),
                child: const Text('打开'),
              )),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    pending = Completer<Map<String, Object>>();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    pending!.complete({'version': 'v1.19.32', 'updated': true});
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('core update stays centered in landscape and scrolls to actions',
      (tester) async {
    tester.view.physicalSize = const Size(900, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, check: false);
    expect(tester.getCenter(find.byType(AlertDialog)), const Offset(450, 160));
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(updates, 1);
    expect(find.text('mihomo 内核更新完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates version and prevents duplicate updates while busy',
      (tester) async {
    pending = Completer<Map<String, Object>>();
    await open(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(updates, 1);
    pending!
        .complete({'version': 'v1.19.32', 'installed': true, 'updated': true});
    await tester.pumpAndSettle();
    expect(find.text('v1.19.32'), findsNWidgets(2));
    expect(find.text('mihomo 内核更新完成'), findsOneWidget);
  });

  testWidgets(
      'stopped proxy disables both buttons and enables them after start',
      (tester) async {
    status = 'stopped';
    await open(tester, check: false);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(updates, 0);
    expect(checks, 0);
    status = 'running';
    sharedStatus.value = ProxyStatus.running;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull);
  });

  testWidgets('button labels stay on one line on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, check: false);
    for (final label in ['检测版本', '更新内核']) {
      final button = find.descendant(
          of: label == '检测版本'
              ? find.byType(OutlinedButton)
              : find.byType(FilledButton),
          matching: find.text(label));
      expect(tester.widget<Text>(button).maxLines, 1);
      expect(tester.widget<Text>(button).softWrap, false);
    }
    expect(find.textContaining('请先停止代理。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('running proxy can download before native replacement',
      (tester) async {
    status = 'running';
    await open(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(updates, 1);
    expect(find.text('mihomo 内核更新完成'), findsOneWidget);
  });

  testWidgets('failed update retains version and allows retry', (tester) async {
    fail = true;
    await open(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('v1.19.31'), findsOneWidget);
    expect(find.text('v1.19.32'), findsOneWidget);
    expect(find.textContaining('校验失败'), findsOneWidget);
    fail = false;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('v1.19.32'), findsNWidgets(2));
  });
}
