import 'package:flutter/material.dart';

Future<bool> showAddNodeDialog({
  required BuildContext context,
  required List<String> nodes,
  required Future<List<String>> Function(String name) onDelete,
  required Future<void> Function(String link) onSave,
}) async {
  final controller = TextEditingController();
  var saving = false;
  var changed = false;
  var manualNodes = List<String>.from(nodes);
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
                      Text('手动添加的节点（${manualNodes.length}）'),
                      const SizedBox(height: 8),
                      if (manualNodes.isEmpty)
                        const Text('暂无手动节点')
                      else
                        SizedBox(
                          width: double.maxFinite,
                          height: MediaQuery.sizeOf(context).height * 0.22,
                          child: ListView.builder(
                            itemCount: manualNodes.length,
                            itemBuilder: (context, index) => ListTile(
                              dense: true,
                              title: Text(manualNodes[index]),
                              trailing: IconButton(
                                tooltip: '删除手动节点',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: saving
                                    ? null
                                    : () async {
                                        setDialogState(() {
                                          saving = true;
                                          error = null;
                                        });
                                        try {
                                          final remaining = await onDelete(
                                              manualNodes[index]);
                                          if (context.mounted) {
                                            setDialogState(() {
                                              manualNodes = remaining;
                                              changed = true;
                                              saving = false;
                                            });
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
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        enabled: !saving,
                        minLines: 1,
                        maxLines: 6,
                        decoration: InputDecoration(
                          labelText: '节点链接',
                          errorText: error,
                          errorMaxLines: 8,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(context).pop(changed),
                    child: Text(changed ? '关闭' : '取消'),
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
        changed;
  } finally {
    // Let the dialog finish its closing animation before disposing its field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }
}
