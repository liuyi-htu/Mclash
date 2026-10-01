import 'package:flutter/material.dart';

Future<bool> showProxyChainDialog({
  required BuildContext context,
  required List<String> nodes,
  required bool prepend,
  required Future<void> Function(String current, String other) onSave,
}) async {
  String? current;
  String? other;
  String? error;
  var saving = false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: Text(prepend ? '添加前置代理' : '添加后置代理'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('current-$current'),
                      initialValue: current,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '当前节点'),
                      items: [
                        for (final name in nodes)
                          DropdownMenuItem(
                              value: name,
                              child:
                                  Text(name, overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setDialogState(() {
                                current = value;
                                if (other == current) other = null;
                                error = null;
                              }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('other-$current-$other'),
                      initialValue: other,
                      isExpanded: true,
                      decoration:
                          InputDecoration(labelText: prepend ? '前置节点' : '后置节点'),
                      items: [
                        for (final name
                            in nodes.where((name) => name != current))
                          DropdownMenuItem(
                              value: name,
                              child:
                                  Text(name, overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setDialogState(() {
                                other = value;
                                error = null;
                              }),
                    ),
                    const SizedBox(height: 16),
                    if (current != null && other != null)
                      Text(
                          '本机 → ${prepend ? other : current} → ${prepend ? current : other} → 目标\n使用时选择出口节点：${prepend ? current : other}'),
                    const SizedBox(height: 12),
                    const Text('保存后直接修改配置并同步当前启用配置，会替换出口节点已有的前置设置。'),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed:
                        saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('取消')),
                FilledButton(
                  onPressed: saving || current == null || other == null
                      ? null
                      : () async {
                          setDialogState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await onSave(current!, other!);
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
}
