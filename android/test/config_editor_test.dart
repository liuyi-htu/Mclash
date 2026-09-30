import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core/models.dart';
import 'package:mclash/pages/config_editor_page.dart';

void main() {
  const channel = MethodChannel('mclash/native');
  const profile = ConfigProfile(
      id: 'test',
      name: 'Test',
      type: 'local',
      active: true,
      exists: true,
      updatedAt: 0);
  testWidgets('long lines scroll horizontally and invalid YAML is not saved',
      (tester) async {
    var saves = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getConfigContent') {
        return 'rules: []\n# ${'long' * 150}\n';
      }
      if (call.method == 'saveConfigContent') saves++;
      return null;
    });
    await tester.pumpWidget(const MaterialApp(
        home: ConfigEditorPage(profile: profile, proxyRunning: false)));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(tester.getSize(field).width, greaterThan(800));
    expect(find.textContaining('共 3 行'), findsOneWidget);
    await tester.enterText(field, 'rules: [');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('详情'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
