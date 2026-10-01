import 'package:flutter/material.dart';

Future<bool> showAddNodeDialog({
  required BuildContext context,
  required Future<void> Function(String link) onSave,
}) async {
  final controller = TextEditingController();
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
                title: const Text('添加节点'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: controller,
                        enabled: !saving,
                        minLines: 1,
                        maxLines: 6,
                        decoration: InputDecoration(
                          labelText: '节点链接',
                          helperText: '支持 vmess://、http://、https://，一次添加一个节点',
                          errorText: error,
                          errorMaxLines: 8,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                          '自动使用此配置已设置的 Host，未设置时保留链接中的 Host。节点按现有正则分组，更新订阅后保留。'),
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
