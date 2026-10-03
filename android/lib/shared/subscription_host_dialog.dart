import 'package:flutter/material.dart';

Future<bool> showSubscriptionHostDialog({
  required BuildContext context,
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
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => PopScope(
              canPop: !saving,
              child: AlertDialog(
                title: const Text('修改 Host'),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: controller,
                          enabled: !saving,
                          minLines: 1,
                          maxLines: 1,
                          decoration: InputDecoration(
                            labelText: 'VMess HTTP / WS Host',
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            errorText: error,
                            errorMaxLines: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(96, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: saving
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
              ),
            ),
          ),
        ) ??
        false;
  } finally {
    // Let the dialog finish its closing animation before disposing its field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }
}
