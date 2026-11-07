import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core/models.dart';
import 'package:mclash/pages/config_editor_page.dart';
import 'package:mclash/pages/app_selector_page.dart';

void main() {
  const channel = MethodChannel('mclash/native');
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  testWidgets(
      'running editor saves draft with next-start notice and never reads runtime',
      (tester) async {
    String? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getProxyStatus':
          return 'running';
        case 'getConfigContent':
          return saved ?? 'rules: []\n';
        case 'saveConfigContent':
          saved = call.arguments['content'] as String;
          return null;
        default:
          throw StateError('Unexpected runtime mutation: ${call.method}');
      }
    });
    const profile = ConfigProfile(
        id: 'a',
        name: 'A',
        type: 'local',
        active: true,
        exists: true,
        updatedAt: 0);
    await tester.pumpWidget(const MaterialApp(
        home: ConfigEditorPage(profile: profile, proxyRunning: true)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'rules: [MATCH,DIRECT]');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, 'rules: [MATCH,DIRECT]');
    expect(find.text('配置已保存，下次启动代理生效'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'running app selection saves without restart and displays next-start notice',
      (tester) async {
    Map? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getInstalledApps':
          return [
            {
              'packageName': 'org.example.browser',
              'label': 'Browser',
              'isSystemApp': false
            }
          ];
        case 'getSelectedPackages':
          return <String>[];
        case 'getMode':
          return 'excludeSelected';
        case 'saveAppFilter':
          saved = call.arguments as Map;
          return null;
        default:
          throw StateError('Unexpected runtime mutation: ${call.method}');
      }
    });
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            const AppSelectorPage(proxyRunning: true))),
                child: const Text('打开')))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browser'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved!['packageNames'], ['org.example.browser']);
    expect(find.text('分应用代理已保存，下次启动代理生效'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
  });
}
