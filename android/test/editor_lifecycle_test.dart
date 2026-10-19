import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core/models.dart';
import 'package:mclash/pages/config_editor_page.dart';
import 'package:mclash/shared/page_visibility.dart';

void main() {
  testWidgets('editor pauses state requests when background or covered',
      (tester) async {
    var reads = 0;
    const channel = MethodChannel('mclash/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getProxyStatus') {
        reads++;
        return 'stopped';
      }
      if (call.method == 'getConfigContent') return 'rules: []\n';
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [vpnRouteObserver],
      home: const ConfigEditorPage(
        profile: ConfigProfile(
            id: 'test',
            name: 'Test',
            type: 'local',
            active: true,
            exists: true,
            updatedAt: 0),
        proxyRunning: false,
      ),
    ));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = reads;
    await tester.pump(const Duration(seconds: 10));
    expect(reads, paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, greaterThan(paused));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator
        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold())));
    await tester.pumpAndSettle();
    final covered = reads;
    await tester.pump(const Duration(seconds: 10));
    expect(reads, covered);
    navigator.pop();
    await tester.pumpAndSettle();
    final popped = reads;
    await tester.pump(const Duration(seconds: 1));
    expect(reads - popped, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
