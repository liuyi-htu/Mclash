import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core/models.dart';
import 'package:mclash/pages/config_editor_page.dart';

void main() {
  testWidgets('draft survives external start and stop without being reloaded',
      (tester) async {
    var running = false;
    var runtimeReads = 0;
    const channel = MethodChannel('mclash/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getProxyStatus':
          return running ? 'running' : 'stopped';
        case 'isRunning':
          return running;
        case 'getConfigContent':
          return 'rules: []\n';
        case 'getRuntimeConfigContent':
          runtimeReads++;
          return 'mode: rule\nrules: []\n';
        default:
          throw StateError('Unexpected: ${call.method}');
      }
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    const profile = ConfigProfile(
        id: 'test',
        name: 'Test',
        type: 'local',
        active: true,
        exists: true,
        updatedAt: 0);
    await tester.pumpWidget(const MaterialApp(
        home: ConfigEditorPage(profile: profile, proxyRunning: false)));
    await tester.pumpAndSettle();
    final field =
        find.byWidgetPredicate((w) => w is TextField && w.maxLines == null);
    const draft = 'rules:\n  - DOMAIN,unsaved.example,DIRECT\n';
    await tester.enterText(field, draft);
    await tester.pump();
    running = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, draft);
    expect(tester.widget<TextField>(field).readOnly, true);
    running = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, draft);
    expect(tester.widget<TextField>(field).readOnly, false);
    expect(runtimeReads, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
