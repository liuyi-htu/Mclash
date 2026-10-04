import 'package:flutter/material.dart';
import 'package:mclash/proxy_platform_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/models.dart';
import 'package:mclash/config_editor_page.dart';

void main() {
  testWidgets('draft survives external start and stop without being reloaded',
      (tester) async {
    var running = false;
    var runtimeReads = 0;
    final service = DraftService(() => running, () => runtimeReads++);
    const profile = ConfigProfile(
        id: 'test',
        name: 'Test',
        type: 'local',
        active: true,
        exists: true,
        updatedAt: 0);
    await tester.pumpWidget(MaterialApp(
        home: ConfigEditorPage(profile: profile, service: service)));
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

class DraftService implements ProxyPlatformService {
  DraftService(this.running, this.onRuntimeRead);
  final bool Function() running;
  final void Function() onRuntimeRead;
  @override
  Future<bool> isRunning() async => running();
  @override
  Future<String> getConfigContent(String id) async => 'rules: []\n';
  @override
  Future<String> getRuntimeConfigContent() async {
    onRuntimeRead();
    return 'mode: rule\nrules: []\n';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
