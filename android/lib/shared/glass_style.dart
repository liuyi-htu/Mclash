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
      this.radius = 20,
      this.borderRadius,
      this.dragProgress});
  final Widget child;
  final bool selected, proxy, blur, lifted;
  final double radius;
  final BorderRadius? borderRadius;
  // Supplied by the navigation animation so fill, shape and shadow share a clock.
  final double? dragProgress;

  @override
  Widget build(BuildContext context) {
    final rounding = borderRadius ?? BorderRadius.circular(radius);
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final drag = dragProgress?.clamp(0.0, 1.0);
    final baseFill =
        selected ? pulseGlassFill(context) : colors.surfaceContainerLow;
    final fill = drag == null
        ? baseFill
        : baseFill.withValues(alpha: baseFill.a * (1 - .65 * drag));
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
          borderRadius: rounding,
          border: Border.all(
              width: proxy ? 1.5 : 1,
              color: selected && proxy
                  ? colors.primary.withValues(alpha: .65)
                  : selected
                      ? const Color(0xFFA0A0A0).withValues(
                          alpha: drag == null ? .16 : .16 - .10 * drag)
                      : colors.outlineVariant),
        ),
        child: child,
      ),
    );
    if (blur) {
      material = BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: material);
    }
    if (drag != null) {
      material = CustomPaint(
        key: const ValueKey('glass-lens-lighting'),
        foregroundPainter: _GlassLensLighting(rounding, drag, dark),
        child: material,
      );
    }
    return AnimatedContainer(
      duration: drag != null || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: rounding,
        boxShadow: [
          BoxShadow(
            color: (dark ? Colors.black : const Color(0xFF828282)).withValues(
                alpha: drag == null
                    ? (dark ? .3 : .2)
                    : ui.lerpDouble(dark ? .3 : .2, dark ? .14 : .06, drag)!),
            blurRadius: drag == null
                ? (lifted ? 24 : (selected ? 10 : 14))
                : ui.lerpDouble(10, 14, drag)!,
            spreadRadius: drag == null ? (lifted ? 4 : 0) : 0,
            offset: Offset(0, drag == null ? 3 : ui.lerpDouble(3, 0, drag)!),
          )
        ],
      ),
      child: ClipRRect(borderRadius: rounding, child: material),
    );
  }
}

/// Lighting stays inside the lens contour; the outer shadow only lifts it slightly.
class _GlassLensLighting extends CustomPainter {
  const _GlassLensLighting(this.rounding, this.progress, this.dark);
  final BorderRadius rounding;
  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0 || size.isEmpty) return;
    final rect = Offset.zero & size;
    final contour = Path()..addRRect(rounding.toRRect(rect.deflate(.7)));
    canvas.save();
    canvas.clipPath(contour);
    // A broad grey band hugs the upper shoulders and fades towards the centre.
    canvas.drawPath(
        contour,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              // Neutral greys sampled from the reference video's upper rim.
              const Color(0xFFDDDDDD)
                  .withValues(alpha: (dark ? .20 : 1) * progress),
              const Color(0xFFE7E7E7)
                  .withValues(alpha: (dark ? .08 : .75) * progress),
              const Color(0xFFF2F2F2)
                  .withValues(alpha: (dark ? .02 : .3) * progress),
              Colors.transparent,
            ],
            stops: const [0, .18, .35, .65],
          ).createShader(rect));
    // The lower rim catches white light without filling the transparent centre.
    canvas.drawPath(
        contour,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: .08 * progress),
              Colors.white.withValues(alpha: (dark ? .18 : .45) * progress),
              Colors.white.withValues(alpha: (dark ? .4 : .95) * progress),
            ],
            stops: const [0, .5, 1],
          ).createShader(rect));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassLensLighting oldDelegate) =>
      rounding != oldDelegate.rounding ||
      progress != oldDelegate.progress ||
      dark != oldDelegate.dark;
}
