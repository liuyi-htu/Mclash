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
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => PopScope(
              canPop: !saving,
              child: AlertDialog(
                title: const Text('修改 Host'),
                content: SingleChildScrollView(
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
                          labelText: 'HTTP / WS Host',
                          helperText: '例如：example.com，不包含 http:// 或路径',
                          errorText: error,
                          errorMaxLines: 8,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('仅修改 VMess 中 HTTP 和 WS 传输的 Host，更新订阅后保留。'),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
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
