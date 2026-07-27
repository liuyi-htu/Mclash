import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/main.dart';

void main() {
  testWidgets('shows minimal home screen', (tester) async {
    await tester.pumpWidget(const MclashApp());
    expect(find.text('Mclash'), findsOneWidget);
    expect(find.text('启动代理'), findsOneWidget);
    expect(find.text('当前配置'), findsOneWidget);
    expect(find.text('代理面板'), findsOneWidget);
  });

  testWidgets('home menu stays compact', (tester) async {
    await tester.pumpWidget(const MclashApp());

    await tester.tap(find.byTooltip('更多功能'));
    await tester.pumpAndSettle();

    final configItem = find.ancestor(
      of: find.text('配置文件'),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
    );
    expect(configItem, findsOneWidget);
    expect(tester.getSize(configItem).width, lessThan(250));
  });
}
