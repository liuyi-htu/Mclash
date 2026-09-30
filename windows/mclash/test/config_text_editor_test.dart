import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/config_text_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var clipboard = '';
  setUp(() {
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboard = (call.arguments as Map)['text'] as String;
          return null;
        case 'Clipboard.getData':
          return {'text': clipboard};
        case 'Clipboard.hasStrings':
          return {'value': clipboard.isNotEmpty};
        default:
          return null;
      }
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  Widget app(TextEditingController controller, {ScrollController? scroll}) =>
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: ConfigTextEditor(
            controller: controller,
            readOnly: false,
            scrollController: scroll,
          ),
        ),
      );

  testWidgets('transparent line overlay adapts to the number of digits',
      (tester) async {
    final controller =
        TextEditingController(text: List.filled(9, 'mode: rule').join('\n'));
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    final numbers = find.byKey(const ValueKey('config-line-numbers'));
    double width() => tester
        .getSize(find
            .ancestor(of: numbers, matching: find.byType(IgnorePointer))
            .first)
        .width;
    final small = width();
    expect(small, lessThan(40));
    controller.text = List.filled(100, 'mode: rule').join('\n');
    await tester.pump();
    expect(width(), greaterThan(small));
    expect(tester.widget<Text>(numbers).data!.split('\n').length, 100);
    // The overlay has no opaque container or background.
    for (final box in tester.widgetList<ColoredBox>(
        find.ancestor(of: numbers, matching: find.byType(ColoredBox)))) {
      expect(box.color, Colors.transparent);
    }
    controller.text = 'mode: rule';
    await tester.pump();
    expect(width(), small);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
      'line overlay tracks vertical scrolling and stays fixed horizontally',
      (tester) async {
    final controller = TextEditingController(
        text: List.generate(100, (i) => '# $i ${'long' * 100}').join('\n'));
    final vertical = ScrollController();
    await tester.pumpWidget(app(controller, scroll: vertical));
    await tester.pumpAndSettle();
    final numbers = find.byKey(const ValueKey('config-line-numbers'));
    final origin = tester.getTopLeft(numbers);
    vertical.jumpTo(100);
    await tester.pump();
    expect(tester.getTopLeft(numbers).dy, closeTo(origin.dy - 100, 0.01));
    final horizontal = tester.state<ScrollableState>(find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            widget.axisDirection == AxisDirection.right));
    horizontal.position.jumpTo(200);
    await tester.pump();
    expect(tester.getTopLeft(numbers).dx, origin.dx);
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final start = editable.localToGlobal(
        editable.getLocalRectForCaret(const TextPosition(offset: 0)).topLeft);
    expect(start.dy, closeTo(tester.getTopLeft(numbers).dy, 2));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    vertical.dispose();
  });

  testWidgets('Chinese copy and paste menu keeps clipboard actions working',
      (tester) async {
    final controller = TextEditingController(text: 'mode: rule\n');
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await Clipboard.setData(const ClipboardData(text: 'test'));
    await tester.pumpAndSettle();
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('粘贴'), findsOneWidget);
    expect(find.text('剪切'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect((await Clipboard.getData(Clipboard.kTextPlain))!.text, 'mode');
    controller.selection = const TextSelection.collapsed(offset: 10);
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();
    expect(controller.text, 'mode: rulemode\n');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
