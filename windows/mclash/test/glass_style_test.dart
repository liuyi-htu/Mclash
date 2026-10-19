import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/app_appearance.dart';
import 'package:mclash/glass_style.dart';

void main() {
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
