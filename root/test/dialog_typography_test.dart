import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/dialog_typography.dart';
import 'package:mclash/shared/app_appearance.dart';
import 'package:mclash/shared/management_style.dart';

void main() {
  testWidgets('dialog type sizes are uniform across themes and font scales',
      (tester) async {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.8]) {
        await tester.pumpWidget(MaterialApp(
          theme: buildPulseTheme(brightness),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: DialogTypography(
              child: AlertDialog(
                title: const Text('统一标题'),
                scrollable: true,
                content: SizedBox(
                  width: 400,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('正文'),
                    const ListTile(title: Text('设置项目'), subtitle: Text('提示')),
                    const TextField(
                        decoration: InputDecoration(labelText: '输入')),
                    ManagementMenuTile(
                      icon: Icons.edit,
                      title: '修改配置名称',
                      onTap: () {},
                    ),
                    DropdownButton<String>(
                      value: 'mixed',
                      items: const [
                        DropdownMenuItem(value: 'mixed', child: Text('mixed')),
                        DropdownMenuItem(
                            value: 'system', child: Text('system')),
                      ],
                      onChanged: (_) {},
                    ),
                  ]),
                ),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('取消')),
                  FilledButton(onPressed: () {}, child: const Text('保存')),
                ],
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        for (final entry in [
          ('统一标题', 18.0),
          ('正文', 14.0),
          ('设置项目', 14.0),
          ('提示', 12.0),
          ('取消', 14.0),
          ('保存', 14.0),
          ('修改配置名称', 14.0),
        ]) {
          final paragraph =
              tester.renderObject<RenderParagraph>(find.text(entry.$1));
          expect(paragraph.text.style!.fontSize, entry.$2);
          expect(paragraph.textScaler.scale(entry.$2), entry.$2 * scale);
          expect(paragraph.text.style!.fontWeight,
              entry.$1 == '统一标题' ? FontWeight.w600 : FontWeight.w400);
        }
        expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .style
                .fontSize,
            14);
        expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .style
                .fontWeight,
            FontWeight.w400);
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        final option =
            tester.renderObject<RenderParagraph>(find.text('system').last);
        expect(option.text.style!.fontWeight, FontWeight.w400);
        await tester.tap(find.text('system').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });
}
