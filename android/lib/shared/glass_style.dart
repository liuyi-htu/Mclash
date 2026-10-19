import 'dart:ui' as ui;
import 'package:flutter/material.dart';

Color pulseGlassFill(BuildContext context) =>
    const Color(0xFFBEBEBE).withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .16 : .12);

/// One clipped blur for bounded controls; list cards only paint their material.
class GlassSurface extends StatelessWidget {
  const GlassSurface(
      {super.key,
      required this.child,
      this.selected = false,
      this.proxy = false,
      this.blur = false,
      this.lifted = false,
      this.radius = 20});
  final Widget child;
  final bool selected, proxy, blur, lifted;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill =
        selected ? pulseGlassFill(context) : colors.surfaceContainerLow;
    Widget material = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: fill,
          gradient: proxy
              ? RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.25,
                  colors: [
                    colors.primary.withValues(alpha: .09),
                    Colors.transparent
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
              width: proxy ? 1.5 : 1,
              color: selected && proxy
                  ? colors.primary.withValues(alpha: .65)
                  : selected
                      ? const Color(0xFFA0A0A0).withValues(alpha: .16)
                      : colors.outlineVariant),
        ),
        child: child,
      ),
    );
    if (blur) {
      material = BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: material);
    }
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: (dark ? Colors.black : const Color(0xFF828282))
                .withValues(alpha: dark ? .3 : .2),
            blurRadius: lifted ? 24 : (selected ? 10 : 14),
            spreadRadius: lifted ? 4 : 0,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(radius), child: material),
    );
  }
}
