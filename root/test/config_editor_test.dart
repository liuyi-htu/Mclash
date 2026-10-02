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
  testWidgets('subscription config stays read-only even when proxy is stopped',
      (tester) async {
    const subscription = ConfigProfile(
        id: 'airport',
        name: 'Airport',
        type: 'subscription',
        active: true,
        exists: true,
        updatedAt: 0);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getProxyStatus') return 'stopped';
      if (call.method == 'isRunning') return false;
      if (call.method == 'getConfigContent') return 'rules: []\n';
      throw StateError('Unexpected write or runtime read: ${call.method}');
    });
    await tester.pumpWidget(const MaterialApp(
        home: ConfigEditorPage(profile: subscription, proxyRunning: false)));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(find.text('订阅配置（只读）'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('running editor shows runtime read-only and unlocks when stopped',
      (tester) async {
    var running = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getProxyStatus') return running ? 'running' : 'stopped';
      if (call.method == 'isRunning') return running;
      if (call.method == 'getRuntimeConfigContent') return 'mixed-port: 7890\n';
      if (call.method == 'getConfigContent') return 'rules: []\n';
      throw StateError('Unexpected mutation: ${call.method}');
    });
    await tester.pumpWidget(const MaterialApp(
        home: ConfigEditorPage(profile: profile, proxyRunning: true)));
    await tester.pumpAndSettle();
    var field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isTrue);
    expect(field.controller!.text, 'mixed-port: 7890\n');
    expect(find.text('当前运行配置（只读）'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
    running = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isFalse);
    expect(field.controller!.text, 'rules: []\n');
    expect(find.text('保存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
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
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final controller = tester.widget<TextField>(field).controller!;
    final start = controller.text.indexOf('#');
    final end = controller.text.lastIndexOf('\n');
    expect(
      editable.getLocalRectForCaret(TextPosition(offset: start)).top,
      editable.getLocalRectForCaret(TextPosition(offset: end)).top,
      reason: 'Long lines must occupy one visual row, matching the gutter',
    );
    final horizontal = find.byWidgetPredicate((widget) =>
        widget is SingleChildScrollView &&
        widget.scrollDirection == Axis.horizontal);
    final scrollable = tester.state<ScrollableState>(find.descendant(
      of: horizontal,
      matching: find.byWidgetPredicate((widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.right),
    ));
    expect(scrollable.position.maxScrollExtent, greaterThan(300));
    scrollable.position.jumpTo(300);
    await tester.pump();
    expect(tester.getTopLeft(field).dx, lessThan(0));
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
