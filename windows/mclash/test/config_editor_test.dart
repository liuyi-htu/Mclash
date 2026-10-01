import 'package:flutter/material.dart';
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

void main() {
  const profile = ConfigProfile(
      id: 'test',
      name: 'Test',
      type: 'local',
      active: true,
      exists: true,
      updatedAt: 0);

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
