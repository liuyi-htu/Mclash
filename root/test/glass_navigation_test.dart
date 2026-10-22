import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/app_appearance.dart';
import 'package:mclash/shared/glass_bottom_bar.dart';
import 'package:mclash/shared/glass_style.dart';

class _SheetController extends AppearanceController {
  bool fail = true;
  bool? savedFloating;
  @override
  Future<void> save() async {
    if (fail) throw const FileSystemException('test save failure');
    savedFloating = floatingBottomBar;
  }
}

void main() {
  test('floating preference migrates, persists and rolls back failed saves',
      () async {
    final dir = await Directory.systemTemp.createTemp('mclash-glass-settings-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/appearance.json');
    await file
        .writeAsString(jsonEncode({'color': 0xFF26745A, 'fontScale': 1.1}));
    var fail = false;
    final controller =
        AppearanceController(fileProvider: () async => fail ? null : file);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.floatingBottomBar, isFalse);
    expect(controller.color, const Color(0xFF26745A));
    await controller.setFloatingBottomBar(true);
    final reopened = AppearanceController(fileProvider: () async => file);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.floatingBottomBar, isTrue);
    fail = true;
    await expectLater(controller.setFloatingBottomBar(false),
        throwsA(isA<FileSystemException>()));
    expect(controller.floatingBottomBar, isTrue);
    expect(controller.savingFloatingBottomBar, isFalse);
    fail = false;
    await controller.setFloatingBottomBar(false);
    expect(jsonDecode(await file.readAsString())['floatingBottomBar'], isFalse);
  });

  testWidgets('bottom bar clicks, drags on release, cancels and uses keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var index = 0;
    final changes = <int>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildPulseTheme(Brightness.light),
      home: StatefulBuilder(
          builder: (context, update) => Scaffold(
                bottomNavigationBar: PulseBottomBar(
                    index: index,
                    onSelected: (next) {
                      changes.add(next);
                      update(() => index = next);
                    }),
              )),
    ));
    Finder destination(int i) => find.byKey(ValueKey('bottom-destination-$i'));
    final first = tester.getCenter(destination(0));
    final last = tester.getCenter(destination(3));
    final gesture = await tester.startGesture(first);
    await gesture.moveTo(first + const Offset(25, 0));
    await gesture.moveTo(last);
    await tester.pump();
    expect(changes, isEmpty);
    final indicator = find.descendant(
        of: find.byKey(const ValueKey('bottom-glass-indicator')),
        matching: find.byType(GlassSurface));
    expect(tester.widget<GlassSurface>(indicator).lifted, isTrue);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(index, 0);
    expect(tester.widget<GlassSurface>(indicator).lifted, isFalse);
    final drag = await tester.startGesture(first);
    await drag.moveTo(first + const Offset(25, 0));
    await drag.moveTo(last);
    await drag.up();
    await tester.pumpAndSettle();
    expect(index, 3);
    expect(tester.widget<GlassSurface>(indicator).lifted, isFalse);
    expect(changes, [3]);
    await tester.tap(destination(1));
    await tester.pumpAndSettle();
    expect(index, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(index, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(index, 0);
  });

  testWidgets(
      'drag enlarges floating selection into an unclipped oval and restores it',
      (tester) async {
    final controller = AppearanceController();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final floating in [false, true]) {
      controller.preview(floatingBottomBar: floating);
      await tester.pumpWidget(AppearanceScope(
        controller: controller,
        child: MaterialApp(
            home: Scaffold(
                bottomNavigationBar:
                    PulseBottomBar(index: 1, onSelected: (_) {}))),
      ));
      await tester.pumpAndSettle();
      final surface = find.descendant(
          of: find.byKey(const ValueKey('bottom-glass-indicator')),
          matching: find.byType(GlassSurface));
      Rect glassBounds() {
        final box = tester.renderObject<RenderBox>(surface);
        return Rect.fromPoints(box.localToGlobal(Offset.zero),
            box.localToGlobal(box.size.bottomRight(Offset.zero)));
      }

      final normal = glassBounds();
      final frame = tester.getRect(find.byKey(ValueKey(
          floating ? 'floating-bottom-surface' : 'docked-bottom-surface')));
      if (!floating) {
        expect(frame.left, 0);
        expect(frame.right, 390);
        expect(frame.height, 64);
        final material = tester.widget<Material>(
            find.byKey(const ValueKey('docked-bottom-surface')));
        expect(material.shape, isNull);
        expect(material.clipBehavior, Clip.none);
      }
      for (final cancel in [true, false]) {
        final origin = tester
            .getCenter(find.byKey(const ValueKey('bottom-destination-1')));
        final gesture = await tester.startGesture(origin);
        await gesture.moveBy(const Offset(25, 0));
        await gesture.moveBy(const Offset(10, 0));
        await tester.pumpAndSettle();
        expect(glassBounds().width, closeTo(normal.width * 1.22, .01));
        expect(glassBounds().height, closeTo(normal.height * 1.6, .01));
        // Keep the lower edge visible while allowing glass and shadow to
        // extend above the docked frame without an ancestor clipping them.
        expect(glassBounds().top, lessThan(frame.top));
        if (floating) {
          final rounding = tester.widget<GlassSurface>(surface).borderRadius!;
          expect(rounding.topLeft.x, closeTo(normal.width / 2, .01));
          expect(rounding.topLeft.y, closeTo(normal.height / 2, .01));
        }
        expect(glassBounds().bottom, lessThanOrEqualTo(frame.bottom));
        expect(find.ancestor(of: surface, matching: find.byType(ClipRRect)),
            findsNothing);

        expect(
            tester.getRect(find.byKey(ValueKey(floating
                ? 'floating-bottom-surface'
                : 'docked-bottom-surface'))),
            frame);
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        expect(glassBounds().size, normal.size);
        expect(tester.widget<GlassSurface>(surface).borderRadius, isNull);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('floating and docked navigation fit safe area and large text',
      (tester) async {
    final controller = AppearanceController();
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final width in [320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 850);
      for (final floating in [true, false]) {
        controller.preview(floatingBottomBar: floating);
        await tester.pumpWidget(AppearanceScope(
          controller: controller,
          child: MaterialApp(
              theme: buildPulseTheme(Brightness.dark),
              home: MediaQuery(
                data: MediaQueryData(
                    size: Size(width, 850),
                    padding: const EdgeInsets.only(bottom: 34),
                    textScaler: const TextScaler.linear(1.8)),
                child: Scaffold(
                    bottomNavigationBar:
                        PulseBottomBar(index: 1, onSelected: (_) {})),
              )),
        ));
        await tester.pumpAndSettle();
        expect(
            find.byKey(ValueKey(floating
                ? 'floating-bottom-surface'
                : 'docked-bottom-surface')),
            findsOneWidget);
        expect(
            tester
                .getBottomRight(
                    find.byKey(const ValueKey('bottom-destination-3')))
                .dy,
            lessThanOrEqualTo(816));
        if (floating) {
          final frameFinder =
              find.byKey(const ValueKey('floating-bottom-surface'));
          final frame = tester.getRect(frameFinder);
          final outer = tester.widget<GlassSurface>(frameFinder);
          final selectionFinder = find.descendant(
              of: find.byKey(const ValueKey('bottom-glass-indicator')),
              matching: find.byType(GlassSurface));
          final selection = tester.widget<GlassSurface>(selectionFinder);
          final bounds = tester.getRect(selectionFinder);
          expect(frame.width, width - 32);
          expect(outer.radius, closeTo(frame.height / 2, .001));
          expect(selection.radius, closeTo(bounds.height / 2, .001));
          expect(bounds.top - frame.top, closeTo(6, .001));
          expect(frame.bottom - bounds.bottom, closeTo(6, .001));
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('theme toggle persists, restores default and retries failed save',
      (tester) async {
    final controller = _SheetController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(ListenableBuilder(
        listenable: controller,
        builder: (_, child) => AppearanceScope(
            controller: controller,
            child: MaterialApp(
                theme: buildPulseTheme(Brightness.light),
                home: const Scaffold(body: AppearanceTile())))));
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('floating-bottom-bar'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(controller.floatingBottomBar, isFalse);
    expect(find.text('主题设置保存失败，请重试'), findsOneWidget);
    controller.fail = false;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(controller.floatingBottomBar, isTrue);
    final reset = find.text('恢复默认');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(controller.floatingBottomBar, isFalse);
    expect(controller.savedFloating, isFalse);
  });

  testWidgets('glass surfaces preserve theme colors and bound backdrop blur',
      (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(
          theme:
              buildPulseTheme(brightness, seedColor: const Color(0xFF26745A)),
          home: Scaffold(
              body: Column(children: [
            for (var i = 0; i < 5; i++)
              const GlassSurface(
                  proxy: true, selected: true, child: Text('node')),
            const GlassSurface(blur: true, child: Text('navigation')),
          ]))));
      expect(find.byType(BackdropFilter), findsOneWidget);
      final ink = tester.widget<Ink>(find.descendant(
          of: find.byType(GlassSurface).first, matching: find.byType(Ink)));
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.gradient, isA<RadialGradient>());
      final fill = decoration.color!;
      expect(fill.r, fill.g);
      expect(fill.g, fill.b);
      expect(fill.a, lessThan(.2));
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
      'all existing theme colors preserve neutral surfaces in light and dark',
      (tester) async {
    for (final brightness in Brightness.values) {
      for (final seed in const [
        0xFF315F95,
        0xFF7356A6,
        0xFF26745A,
        0xFFA75B29,
        0xFFAD476B,
        0xFF357C85,
        0xFF675F71
      ]) {
        final theme = buildPulseTheme(brightness, seedColor: Color(seed));
        await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: const Scaffold(
                body: GlassSurface(proxy: true, child: Text('node')))));
        await tester.pumpAndSettle();
        final ink = tester.widget<Ink>(find.descendant(
            of: find.byType(GlassSurface), matching: find.byType(Ink)));
        final decoration = ink.decoration! as BoxDecoration;
        expect(
            decoration.color,
            brightness == Brightness.light
                ? Colors.white
                : const Color(0xFF242329));
        expect((decoration.gradient! as RadialGradient).colors.first,
            theme.colorScheme.primary.withValues(alpha: .09));
        expect(
            theme.colorScheme.primary,
            brightness == Brightness.light
                ? Color(seed)
                : seed == 0xFF315F95
                    ? const Color(0xFFA8C9F3)
                    : Color.lerp(Color(seed), Colors.white, .45));
        expect(
            theme.scaffoldBackgroundColor,
            brightness == Brightness.light
                ? Colors.white
                : const Color(0xFF161A20));
      }
    }
  });
}
