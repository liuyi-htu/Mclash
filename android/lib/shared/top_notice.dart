import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

OverlayEntry? _currentNotice;
Timer? _currentNoticeTimer;

void showTopSnackBar(BuildContext context, SnackBar snackBar) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final theme = Theme.of(context);
  final snackBarTheme = theme.snackBarTheme;

  _currentNoticeTimer?.cancel();
  _currentNotice?.remove();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => Positioned(
      top: MediaQuery.paddingOf(overlayContext).top + kToolbarHeight + 8,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          bottom: false,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: snackBar.backgroundColor ??
                  snackBarTheme.backgroundColor ??
                  theme.colorScheme.inverseSurface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: _SwipeDismissibleNotice(
              onDismiss: () => _removeNotice(entry),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: DefaultTextStyle.merge(
                  style: snackBarTheme.contentTextStyle ??
                      TextStyle(color: theme.colorScheme.onInverseSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  child: Row(
                    children: [
                      Expanded(child: snackBar.content),
                      if (snackBar.action != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            snackBar.action!.onPressed();
                            _removeNotice(entry);
                          },
                          child: Text(snackBar.action!.label),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  _currentNotice = entry;
  overlay.insert(entry);
  _currentNoticeTimer = Timer(snackBar.duration, () => _removeNotice(entry));
}

void showErrorNotice(BuildContext context, Object error) {
  final details = errorNoticeDetails(error);
  final summary = errorNoticeSummary(details);
  showTopSnackBar(
    context,
    SnackBar(
      content: Text(summary),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: '详情',
        onPressed: () {
          if (!context.mounted) return;
          showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('错误详情'),
              content: SingleChildScrollView(child: SelectableText(details)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

String errorNoticeDetails(Object error) {
  final message = error is PlatformException
      ? (error.message?.trim().isNotEmpty == true ? error.message! : error.code)
      : error.toString();
  return message.trim().replaceFirst(
        RegExp(r'^(?:Exception|StateError|FormatException):\s*'),
        '',
      );
}

String errorNoticeSummary(String details) {
  final normalized = details.trim();
  if (normalized.isEmpty) return '未知错误';

  var summary = normalized
      .split(RegExp(r'[\r\n]+'))
      .firstWhere((line) => line.trim().isNotEmpty)
      .trim();
  summary = summary.split('；最近日志：').first.trim();
  summary = summary.split('。最近日志：').first.trim();
  const maxCharacters = 120;
  if (summary.length > maxCharacters) {
    summary = '${summary.substring(0, maxCharacters - 1)}…';
  }
  return summary.isEmpty ? '未知错误' : summary;
}

void _removeNotice(OverlayEntry entry) {
  if (entry.mounted) entry.remove();
  if (identical(_currentNotice, entry)) {
    _currentNoticeTimer?.cancel();
    _currentNotice = null;
    _currentNoticeTimer = null;
  }
}

class _SwipeDismissibleNotice extends StatefulWidget {
  const _SwipeDismissibleNotice({
    required this.child,
    required this.onDismiss,
  });

  final Widget child;
  final VoidCallback onDismiss;

  @override
  State<_SwipeDismissibleNotice> createState() =>
      _SwipeDismissibleNoticeState();
}

class _SwipeDismissibleNoticeState extends State<_SwipeDismissibleNotice> {
  static const _dismissDistance = 48.0;
  static const _dismissVelocity = 700.0;

  Offset _dragOffset = Offset.zero;

  void _reset() {
    if (!mounted) return;
    setState(() => _dragOffset = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        setState(() => _dragOffset += details.delta);
      },
      onPanEnd: (details) {
        final velocity = details.velocity.pixelsPerSecond;
        if (_dragOffset.distance >= _dismissDistance ||
            velocity.distance >= _dismissVelocity) {
          widget.onDismiss();
        } else {
          _reset();
        }
      },
      onPanCancel: _reset,
      child: Transform.translate(offset: _dragOffset, child: widget.child),
    );
  }
}
