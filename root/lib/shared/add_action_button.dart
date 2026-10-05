import 'dart:math' as math;
import 'package:flutter/material.dart';

class AddActionIcon extends StatelessWidget {
  const AddActionIcon({super.key, this.enabled = true});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.add_rounded, color: colors.primary, size: 24),
      ),
    );
  }
}

class AddActionButton extends StatelessWidget {
  const AddActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          enabled: onPressed != null,
          label: tooltip,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: AddActionIcon(enabled: onPressed != null),
            ),
          ),
        ),
      );
}

FloatingActionButtonLocation managementAddButtonLocation(
        BuildContext context) =>
    _ConfigAlignedAddButtonLocation(
        NavigationBarTheme.of(context).height ?? 80);

class _ConfigAlignedAddButtonLocation extends FloatingActionButtonLocation {
  const _ConfigAlignedAddButtonLocation(this.navigationBarHeight);
  final double navigationBarHeight;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final offset = FloatingActionButtonLocation.endFloat.getOffset(geometry);
    if (geometry.minInsets.bottom > 0) return offset;
    final alignedTop = geometry.scaffoldSize.height -
        geometry.minViewPadding.bottom -
        navigationBarHeight -
        kFloatingActionButtonMargin -
        geometry.floatingActionButtonSize.height;
    return Offset(offset.dx, math.min(offset.dy, math.max(0, alignedTop)));
  }
}
