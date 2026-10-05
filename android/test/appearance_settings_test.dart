import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/app_appearance.dart';

class _RecordingController extends AppearanceController {
  Color? savedColor;
  double? savedScale;
  @override
  Future<void> save() async {
    savedColor = color;
    savedScale = fontScale;
  }
}

void main() {
  test('color and global text size survive reopening and consecutive saves',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('mclash-appearance-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/appearance.json');
    final controller = AppearanceController(fileProvider: () async => file);
    addTearDown(controller.dispose);
    controller.preview(color: const Color(0xFF26745A), fontScale: 1.15);
    final first = controller.save();
    controller.preview(fontScale: 1.3);
    final second = controller.save();
    await Future.wait([first, second]);
    final reopened = AppearanceController(fileProvider: () async => file);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.color, const Color(0xFF26745A));
    expect(reopened.fontScale, 1.3);
    expect(
        AppearanceTextScaler(const TextScaler.linear(1.8), reopened.fontScale)
            .scale(14),
        closeTo(14 * 1.8 * 1.3, .001));
  });

  test('damaged preferences retain defaults and a failed save can retry',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('mclash-appearance-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/appearance.json');
    await file.writeAsString('{broken');
    var fail = true;
    final controller =
        AppearanceController(fileProvider: () async => fail ? null : file);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.fontScale, 1);
    await expectLater(controller.save(), throwsA(isA<FileSystemException>()));
    fail = false;
    await controller.load();
    expect(controller.color, AppearanceController.defaultColor);
    controller.preview(fontScale: .85);
    await controller.save();
    expect(jsonDecode(await file.readAsString())['fontScale'], .85);
  });

  testWidgets('theme opens, changes color and saves font slider adjustments',
      (tester) async {
    final controller = _RecordingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(AppearanceScope(
        controller: controller,
        child: MaterialApp(
            theme: buildPulseTheme(Brightness.light),
            home: const Scaffold(body: AppearanceTile()))));
    expect(find.text('Pulse'), findsNothing);
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-color-2')));
    await tester.pumpAndSettle();
    expect(controller.color, const Color(0xFF26745A));
    final slider = find.byKey(const ValueKey('global-font-slider'));
    await tester.drag(slider, const Offset(70, 0));
    await tester.pumpAndSettle();
    expect(controller.fontScale, greaterThan(1));
    expect(controller.savedColor, controller.color);
    expect(controller.savedScale, controller.fontScale);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
