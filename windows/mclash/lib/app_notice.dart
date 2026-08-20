import 'dart:async';

import 'package:flutter/material.dart';

class AppNotice {
  AppNotice._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(BuildContext context, String message, {bool error = false}) {
    dismiss();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final colors = Theme.of(overlayContext).colorScheme;
        final background = error
            ? colors.errorContainer
            : colors.inverseSurface;
        final foreground = error
            ? colors.onErrorContainer
            : colors.onInverseSurface;
        return Positioned(
          top: 12,
          left: 20,
          right: 20,
          child: SafeArea(
            bottom: false,
            child: Center(
              child: Material(
                color: background,
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          error
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          color: foreground,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            message,
                            style: TextStyle(color: foreground),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: '关闭',
                          visualDensity: VisualDensity.compact,
                          onPressed: dismiss,
                          icon: Icon(Icons.close_rounded, color: foreground),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(Duration(seconds: error ? 6 : 3), dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}
