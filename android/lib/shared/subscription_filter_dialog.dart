import 'package:flutter/material.dart';
import 'subscription_filter.dart';

Future<bool> showSubscriptionFilterDialog({
  required BuildContext context,
  required String groupName,
  required String initialFilter,
  required Future<void> Function(String filter) onSave,
}) async {
  final controller = TextEditingController(text: initialFilter);
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
                title: Text(groupName == domesticGroup
                    ? '国内正则表达式'
                    : groupName == foreignGroup
                        ? '国外正则表达式'
                        : '$groupName 正则表达式'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: controller,
                        enabled: !saving,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: '节点名称匹配规则',
                          errorText: error,
                          errorMaxLines: 8,
                        ),
                      ),
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
