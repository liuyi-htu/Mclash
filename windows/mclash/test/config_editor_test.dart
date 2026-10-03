import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/config_editor_page.dart';
import 'package:mclash/models.dart';
import 'package:mclash/proxy_platform_service.dart';

class _EditorService implements ProxyPlatformService {
  @override
  Future<bool> isRunning() async => false;

  @override
  Future<String> getConfigContent(String id) async => 'rules: []\n';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RuntimeEditorService extends _EditorService {
  _RuntimeEditorService(this.content);
  final String content;
  @override
  Future<bool> isRunning() async => true;
  @override
  Future<String> getRuntimeConfigContent() async => content;
}

void main() {
  const profile = ConfigProfile(
      id: 'test',
      name: 'Test',
      type: 'local',
      active: true,
      exists: true,
      updatedAt: 0);

  testWidgets('runtime viewer hides line numbers, jumps, searches and copies',
      (tester) async {
    tester.view.physicalSize = const Size(320, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final content =
        'mode: rule\n# ${'long ' * 100}needle\nrules:\n  - MATCH,DIRECT\n';
    var copied = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = call.arguments['text'] as String;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
        home: ConfigEditorPage(
            profile: profile,
            runtimeView: true,
            service: _RuntimeEditorService(content))));
    await tester.pumpAndSettle();
    final editor = find
        .byWidgetPredicate((widget) => widget is TextField && widget.readOnly);
    final controller = tester.widget<TextField>(editor).controller!;
    final numbers = find.byKey(const ValueKey('config-line-numbers'));
    expect(numbers, findsNothing);
    expect(find.text('保存'), findsNothing);
    expect(tester.getCenter(find.byTooltip('显示行号')).dx,
        lessThan(tester.getCenter(find.byTooltip('跳转到行')).dx));
    await tester.tap(find.byTooltip('显示行号'));
    await tester.pumpAndSettle();
    expect(numbers, findsOneWidget);
    await tester.tap(find.byTooltip('隐藏行号'));
    await tester.pumpAndSettle();
    expect(numbers, findsNothing);
    await tester.tap(find.byTooltip('跳转到行'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '行号'), '3');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(controller.selection.start, content.indexOf('rules:'));
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索配置'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索配置'), 'NEEDLE');
    await tester.pumpAndSettle();
    expect(controller.selection.textInside(controller.text), 'needle');
    expect(find.text('1/1'), findsOneWidget);
    final horizontal = tester.state<ScrollableState>(find.ancestor(
        of: editor,
        matching: find.byWidgetPredicate((widget) =>
            widget is Scrollable &&
            widget.axisDirection == AxisDirection.right)));
    expect(horizontal.position.pixels, greaterThan(0));
    await tester.enterText(find.widgetWithText(TextField, '搜索配置'), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('0/0'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制全文'));
    await tester.pumpAndSettle();
    expect(copied, content);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('subscription editor stays read-only with the proxy stopped',
      (tester) async {
    const subscription = ConfigProfile(
        id: 'airport',
        name: 'Airport',
        type: 'subscription',
        active: true,
        exists: true,
        updatedAt: 0);
    await tester.pumpWidget(MaterialApp(
        home: ConfigEditorPage(
            profile: subscription, service: _EditorService())));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(find.byTooltip('保存'), findsNothing);
    expect(find.text('订阅配置（只读）'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('long lines stay on one row at text scale $scale',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ConfigEditorPage(profile: profile, service: _EditorService()),
      ));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);

      // Repeated edits must update the width even after the editor becomes dirty.
      for (final length in [150, 300]) {
        final text = 'rules: []\n# ${'long' * length}\n';
        await tester.enterText(field, text);
        await tester.pumpAndSettle();
        expect(tester.getSize(field).width, greaterThan(800));
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        expect(
          editable
              .getLocalRectForCaret(TextPosition(offset: text.indexOf('#')))
              .top,
          editable
              .getLocalRectForCaret(
                  TextPosition(offset: text.lastIndexOf('\n')))
              .top,
        );
      }
      final horizontal = find.byWidgetPredicate((widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal);
      final scrollable = tester.state<ScrollableState>(find.descendant(
        of: horizontal,
        matching: find.byWidgetPredicate((widget) =>
            widget is Scrollable &&
            widget.axisDirection == AxisDirection.right),
      ));
      expect(scrollable.position.maxScrollExtent, greaterThan(300));
      scrollable.position.jumpTo(300);
      await tester.pump();
      expect(tester.getTopLeft(field).dx, lessThan(0));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
