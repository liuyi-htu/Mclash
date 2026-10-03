import 'package:flutter/material.dart';

import 'models.dart';

/// Carries the live service state into configuration routes and dialogs.
class ProxyEditAccess extends InheritedNotifier<ValueNotifier<ProxyStatus>> {
  const ProxyEditAccess(
      {super.key, required super.notifier, required super.child});

  static bool allowed(BuildContext context) {
    final access =
        context.dependOnInheritedWidgetOfExactType<ProxyEditAccess>();
    return access == null || access.notifier?.value == ProxyStatus.stopped;
  }

  static Widget wrap(ValueNotifier<ProxyStatus>? status,
      Widget Function(BuildContext) builder) {
    if (status == null) return Builder(builder: builder);
    return ProxyEditAccess(
      notifier: status,
      child: Builder(builder: (context) {
        // Rebuild the entire route/dialog when service state changes.
        allowed(context);
        return builder(context);
      }),
    );
  }

  static Widget inherit(
          BuildContext context, Widget Function(BuildContext) builder) =>
      wrap(
        context.getInheritedWidgetOfExactType<ProxyEditAccess>()?.notifier,
        builder,
      );
}
