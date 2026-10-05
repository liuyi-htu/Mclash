import 'dialog_typography.dart';
import 'management_style.dart';
import 'models.dart';
import 'proxy_edit_access.dart';
import 'package:flutter/material.dart';

Future<bool> showSubscriptionHostDialog({
  required BuildContext context,
  ValueNotifier<ProxyStatus>? proxyStatus,
  required String initialHost,
  required Future<void> Function(String host) onSave,
}) async {
  final controller = TextEditingController(text: initialHost);
  var saving = false;
  String? error;
  try {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (_) => ProxyEditAccess.wrap(
              proxyStatus,
              (context) => StatefulBuilder(
                    builder: (context, setDialogState) => PopScope(
                      canPop: !saving,
                      child: DialogTypography(
                          child: AlertDialog(
                        title: Text('修改 Host',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontSize: 18)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        actionsPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        content: SizedBox(
                          width: 480,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  controller: controller,
                                  enabled: ProxyEditAccess.allowed(context) &&
                                      !saving,
                                  minLines: 1,
                                  maxLines: 1,
                                  decoration: managementFieldDecoration(
                                          context, 'VMess HTTP / WS Host')
                                      .copyWith(
                                    fillColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.45),
                                    errorStyle: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error),
                                    errorText: error,
                                    errorMaxLines: 8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        actions: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(96, 48),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed:
                                !ProxyEditAccess.allowed(context) || saving
                                    ? null
                                    : () async {
                                        setDialogState(() {
                                          saving = true;
                                          error = null;
                                        });
                                        try {
                                          await onSave(controller.text.trim());
                                          if (context.mounted) {
                                            Navigator.of(context).pop(true);
                                          }
                                        } catch (failure) {
                                          if (context.mounted) {
                                            setDialogState(() {
                                              saving = false;
                                              error = failure.toString();
                                            });
                                          }
                                        }
                                      },
                            child: Text(saving ? '保存中…' : '保存'),
                          ),
                        ],
                      )),
                    ),
                  )),
        ) ??
        false;
  } finally {
    // Let the dialog finish its closing animation before disposing its field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }
}
