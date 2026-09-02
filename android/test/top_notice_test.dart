import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/top_notice.dart';

void main() {
  testWidgets('top notice can be dismissed in every direction', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const Scaffold();
          },
        ),
      ),
    );

    for (final offset in const [
      Offset(-80, 0),
      Offset(80, 0),
      Offset(0, -80),
      Offset(0, 80),
    ]) {
      showTopSnackBar(
        context,
        const SnackBar(content: Text('关键信息')),
      );
      await tester.pump();
      expect(find.text('关键信息'), findsOneWidget);

      await tester.drag(find.text('关键信息'), offset);
      await tester.pump();
      expect(find.text('关键信息'), findsNothing);
    }
  });

  testWidgets('top notice limits text to two lines', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const Scaffold();
          },
        ),
      ),
    );

    showTopSnackBar(
      context,
      const SnackBar(content: Text('第一行\n第二行\n第三行')),
    );
    await tester.pump();

    final text = tester.widget<Text>(find.text('第一行\n第二行\n第三行'));
    expect(text.maxLines, isNull);
    final inherited = tester.widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('第一行\n第二行\n第三行'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    expect(inherited.maxLines, 2);
    expect(inherited.overflow, TextOverflow.ellipsis);
    await tester.drag(find.text('第一行\n第二行\n第三行'), const Offset(80, 0));
    await tester.pump();
  });

  testWidgets('error notice shows key message and opens details',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const Scaffold();
          },
        ),
      ),
    );

    showErrorNotice(
      context,
      PlatformException(
        code: 'start_failed',
        message: '配置第 12 行格式错误；最近日志：完整的内核错误内容',
      ),
    );
    await tester.pump();

    expect(find.text('配置第 12 行格式错误'), findsOneWidget);
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(find.text('错误详情'), findsOneWidget);
    expect(find.text('配置第 12 行格式错误；最近日志：完整的内核错误内容'), findsOneWidget);
  });
}
