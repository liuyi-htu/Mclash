import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/settings_sheet.dart';

void main() {
  testWidgets('bottom sheet returns result after removing input controllers',
      (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(
          onPressed: () async {
            final controller = TextEditingController();
            result = await showSettingsSheet<String>(
                context: context,
                builder: (context) => SettingsSheetContent(
                      title: const Text('参数'),
                      content: TextField(controller: controller),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, 'saved'),
                            child: const Text('保存'))
                      ],
                    ));
            controller.dispose();
          },
          child: const Text('打开'));
    })));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.getBottomRight(find.byType(BottomSheet)).dy, 600);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, 'saved');
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy guard blocks barrier back and handle until idle',
      (tester) async {
    final busy = ValueNotifier(true);
    addTearDown(busy.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showSettingsSheet<void>(
                    context: context,
                    builder: (_) => ValueListenableBuilder<bool>(
                          valueListenable: busy,
                          builder: (_, value, child) => PopScope(
                              canPop: !value,
                              child: const SettingsSheetContent(
                                  title: Text('更新'), content: Text('进行中'))),
                        )),
                child: const Text('打开')))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.binding.handlePopRoute();
    await tester.drag(find.bySemanticsLabel('下拉关闭'), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    busy.value = false;
    await tester.pump();
    await tester.drag(find.bySemanticsLabel('下拉关闭'), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keyboard and safe areas keep actions reachable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: 260);
    tester.view.padding = FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!),
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showSettingsSheet<void>(
                    context: context,
                    builder: (sheetContext) => SettingsSheetContent(
                            title: const Text('参数设置'),
                            content: Column(
                                children:
                                    List.generate(30, (i) => Text('设置项目 $i'))),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(sheetContext),
                                  child: const Text('保存'))
                            ])),
                child: const Text('打开')))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final save = find.text('保存');
    await tester.ensureVisible(save);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(380));
    expect(tester.takeException(), isNull);
  });
}
