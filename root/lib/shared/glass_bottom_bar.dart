import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_appearance.dart';
import 'glass_style.dart';
import 'pulse_icons.dart';

class PulseBottomBar extends StatefulWidget {
  const PulseBottomBar(
      {super.key, required this.index, required this.onSelected});
  final int index;
  final ValueChanged<int> onSelected;
  static const icons = [
    Icons.home_outlined,
    Icons.hub_outlined,
    Icons.inventory_2_outlined,
    Icons.settings_outlined
  ];
  static const labels = ['首页', '代理', '配置', '设置'];
  @override
  State<PulseBottomBar> createState() => _PulseBottomBarState();
}

class _PulseBottomBarState extends State<PulseBottomBar> {
  final _nodes = List.generate(4, (_) => FocusNode());
  double? _dragPosition;
  bool _pointerCancelled = false;

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _move(double x, double cellWidth) {
    setState(() => _dragPosition = (x / cellWidth - .5).clamp(0.0, 3.0));
  }

  void _commit() {
    final next = _pointerCancelled ? null : _dragPosition?.round();
    setState(() => _dragPosition = null);
    if (next != null && next != widget.index) widget.onSelected(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final floating =
        AppearanceScope.maybeOf(context)?.floatingBottomBar ?? false;
    final height = math.max(floating ? 54.0 : 44.0,
        26 + MediaQuery.textScalerOf(context).scale(11) * 1.45);
    final duration =
        _dragPosition != null || MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220);
    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.only(top: floating ? 8 : 0, bottom: floating ? 16 : 0),
        child: LayoutBuilder(builder: (context, constraints) {
          final width = floating
              ? math.min(440.0, constraints.maxWidth - 32)
              : constraints.maxWidth;
          Widget bar = Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 6, vertical: floating ? 6 : 10),
            child: LayoutBuilder(builder: (context, inner) {
              final cellWidth = inner.maxWidth / 4;
              final position = _dragPosition ?? widget.index.toDouble();
              final selected = position.round();
              return Listener(
                  onPointerDown: (_) => _pointerCancelled = false,
                  onPointerCancel: (_) {
                    _pointerCancelled = true;
                    setState(() => _dragPosition = null);
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (d) =>
                        _move(d.localPosition.dx, cellWidth),
                    onHorizontalDragUpdate: (d) =>
                        _move(d.localPosition.dx, cellWidth),
                    onHorizontalDragEnd: (_) => _commit(),
                    onHorizontalDragCancel: () =>
                        setState(() => _dragPosition = null),
                    child: SizedBox(
                        height: height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedPositioned(
                              key: const ValueKey('bottom-glass-indicator'),
                              duration: duration,
                              curve: Curves.easeOutCubic,
                              left: position * cellWidth,
                              width: cellWidth,
                              top: 0,
                              bottom: 0,
                              child: IgnorePointer(
                                  child: TweenAnimationBuilder<double>(
                                      key: const ValueKey('bottom-glass-scale'),
                                      tween: Tween(
                                          begin: 0,
                                          end: _dragPosition != null ? 1 : 0),
                                      duration: MediaQuery.disableAnimationsOf(context)
                                          ? Duration.zero
                                          : const Duration(milliseconds: 160),
                                      curve: Curves.easeOutCubic,
                                      builder: (_, progress, child) => Transform.translate(
                                          offset: Offset(
                                              0,
                                              -math.max(0, height * .6 / 2 - (floating ? 6 : 10)) *
                                                  progress),
                                          child: Transform.scale(
                                              alignment: Alignment(
                                                  position / 1.5 - 1, 0),
                                              scaleX: 1 + .22 * progress,
                                              scaleY: 1 + .6 * progress,
                                              child: child)),
                                      child: GlassSurface(
                                          lifted: _dragPosition != null,
                                          selected: true,
                                          radius: floating ? height / 2 : 15,
                                          borderRadius: floating && _dragPosition != null
                                              ? BorderRadius.all(Radius.elliptical(cellWidth / 2, height / 2))
                                              : null,
                                          child: const SizedBox.expand()))),
                            ),
                            Row(children: [
                              for (var i = 0; i < 4; i++)
                                Expanded(
                                    child: Focus(
                                  onKeyEvent: (_, event) {
                                    if (event is! KeyDownEvent) {
                                      return KeyEventResult.ignored;
                                    }
                                    final key = event.logicalKey;
                                    final next = key ==
                                            LogicalKeyboardKey.arrowRight
                                        ? (i + 1) % 4
                                        : key == LogicalKeyboardKey.arrowLeft
                                            ? (i + 3) % 4
                                            : key == LogicalKeyboardKey.home
                                                ? 0
                                                : key == LogicalKeyboardKey.end
                                                    ? 3
                                                    : null;
                                    if (next == null) {
                                      return KeyEventResult.ignored;
                                    }
                                    widget.onSelected(next);
                                    _nodes[next].requestFocus();
                                    return KeyEventResult.handled;
                                  },
                                  child: Semantics(
                                    selected: selected == i,
                                    button: true,
                                    child: InkWell(
                                      key: ValueKey('bottom-destination-$i'),
                                      focusNode: _nodes[i],
                                      borderRadius: BorderRadius.circular(
                                          floating ? height / 2 : 15),
                                      onTap: () {
                                        _nodes[i].requestFocus();
                                        widget.onSelected(i);
                                      },
                                      child: SizedBox(
                                          height: height,
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              PulseIcon(PulseBottomBar.icons[i],
                                                  size: 18,
                                                  color: selected == i
                                                      ? colors.primary
                                                      : colors
                                                          .onSurfaceVariant),
                                              const SizedBox(height: 2),
                                              Text(PulseBottomBar.labels[i],
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      height: 1.45,
                                                      color: selected == i
                                                          ? colors.primary
                                                          : colors
                                                              .onSurfaceVariant,
                                                      fontWeight: selected == i
                                                          ? FontWeight.w600
                                                          : FontWeight.w400)),
                                            ],
                                          )),
                                    ),
                                  ),
                                )),
                            ]),
                          ],
                        )),
                  ));
            }),
          );
          bar = floating
              ? Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                      child: GlassSurface(
                          key: const ValueKey('floating-bottom-surface'),
                          blur: true,
                          radius: (height + 12) / 2,
                          child: const SizedBox.shrink())),
                  Material(type: MaterialType.transparency, child: bar),
                ])
              : Material(
                  key: const ValueKey('docked-bottom-surface'),
                  color: colors.surfaceContainerLow,
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          border: Border(
                              top: BorderSide(color: colors.outlineVariant))),
                      child: bar));
          return Align(
              heightFactor: 1, child: SizedBox(width: width, child: bar));
        }),
      ),
    );
  }
}
