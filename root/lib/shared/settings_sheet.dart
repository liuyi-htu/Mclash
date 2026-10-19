import 'package:flutter/material.dart';

/// Matches the theme sheet's bottom-up route while respecting busy PopScopes.
/// Awaiting removal also keeps text controllers alive during the exit animation.
Future<T?> showSettingsSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final theme = Theme.of(context);
  final route = ModalBottomSheetRoute<T>(
    builder: (sheetContext) => _SettingsSheetFrame(
      dismissible: barrierDismissible,
      child: builder(sheetContext),
    ),
    capturedThemes:
        InheritedTheme.capture(from: context, to: navigator.context),
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: barrierDismissible,
    // The native drag handler calls pop directly and bypasses busy PopScopes.
    // Our handle uses maybePop, just like tapping outside or pressing Back.
    enableDrag: false,
    showDragHandle: false,
    backgroundColor: theme.colorScheme.surfaceContainerLow,
    constraints: const BoxConstraints(maxWidth: 640),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    settings: const RouteSettings(name: 'settings-sheet'),
  );
  final result = await navigator.push(route);
  await route.completed;
  return result;
}

class _SettingsSheetFrame extends StatefulWidget {
  const _SettingsSheetFrame({required this.child, required this.dismissible});
  final Widget child;
  final bool dismissible;
  @override
  State<_SettingsSheetFrame> createState() => _SettingsSheetFrameState();
}

class _SettingsSheetFrameState extends State<_SettingsSheetFrame> {
  double _drag = 0;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          final available =
              (constraints.maxHeight - keyboard).clamp(0.0, double.infinity);
          final handle = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: widget.dismissible ? (_) => _drag = 0 : null,
            onVerticalDragUpdate:
                widget.dismissible ? (d) => _drag += d.delta.dy : null,
            onVerticalDragEnd: widget.dismissible
                ? (d) {
                    if (_drag > 48 || (d.primaryVelocity ?? 0) > 500) {
                      Navigator.of(context).maybePop();
                    }
                  }
                : null,
            child: Semantics(
              label: '下拉关闭',
              button: widget.dismissible,
              onTap: widget.dismissible
                  ? () => Navigator.of(context).maybePop()
                  : null,
              child: SizedBox(
                  height: 32,
                  child: Center(
                      child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: .4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ))),
            ),
          );
          final contents = available < 128
              ? SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [handle, widget.child]))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [handle, Flexible(child: widget.child)]);
          return AnimatedPadding(
            padding: EdgeInsets.only(bottom: keyboard),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: available),
                child: SafeArea(top: false, child: contents)),
          );
        },
      );
}

/// Shared title, scrollable body and actions for settings sheets.
class SettingsSheetContent extends StatelessWidget {
  const SettingsSheetContent(
      {super.key, this.title, this.content, this.actions});
  final Widget? title, content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final heading = title == null
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.titleLarge,
                  child:
                      Semantics(namesRoute: true, header: true, child: title!),
                ),
              );
        final body = Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: content ?? const SizedBox.shrink());
        final buttons = actions == null || actions!.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions!),
              );
        if (!constraints.hasBoundedHeight || constraints.maxHeight < 180) {
          return SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                if (heading != null) heading,
                body,
                if (buttons != null) buttons
              ]));
        }
        return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (heading != null) heading,
              Flexible(child: SingleChildScrollView(child: body)),
              if (buttons != null) buttons
            ]);
      });
}
