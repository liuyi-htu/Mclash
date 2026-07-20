import 'dart:async';

import 'package:flutter/material.dart';

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
              color:
                  snackBar.backgroundColor ??
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: DefaultTextStyle(
                style:
                    snackBarTheme.contentTextStyle ??
                    TextStyle(color: theme.colorScheme.onInverseSurface),
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
  );

  _currentNotice = entry;
  overlay.insert(entry);
  _currentNoticeTimer = Timer(snackBar.duration, () => _removeNotice(entry));
}

void _removeNotice(OverlayEntry entry) {
  if (entry.mounted) entry.remove();
  if (identical(_currentNotice, entry)) {
    _currentNotice = null;
    _currentNoticeTimer = null;
  }
}
