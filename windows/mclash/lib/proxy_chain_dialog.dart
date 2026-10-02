import 'package:flutter/material.dart';

Future<List<String>?> _selectNodes(BuildContext context, String title,
    List<String> nodes, List<String> initial) async {
  final selected = initial.toSet();
  return showDialog<List<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: () =>
                              setState(() => selected.addAll(nodes)),
                          child: const Text('全选'),
                        ),
                        TextButton(
                          onPressed: () => setState(selected.clear),
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.4,
                      child: ListView.builder(
                        itemCount: nodes.length,
                        itemBuilder: (context, index) => CheckboxListTile(
                          title: Text(nodes[index]),
                          value: selected.contains(nodes[index]),
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              selected.add(nodes[index]);
                            } else {
                              selected.remove(nodes[index]);
                            }
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(selected.toList()),
                    child: const Text('确定')),
              ],
            )),
  );
}

Future<bool> showProxyChainDialog({
  required BuildContext context,
  required List<String> nodes,
  required bool prepend,
  String? chainLabel,
  List<String> initialNodes = const [],
  List<String> initialTargets = const [],
  List<String> excludedTargets = const [],
  required Future<void> Function(List<String> current, List<String> other)
      onSave,
}) async {
  var other = initialNodes.where(nodes.contains).toSet().toList();
  var current = initialTargets
      .where((name) =>
          nodes.contains(name) &&
          !other.contains(name) &&
          !excludedTargets.contains(name))
      .toSet()
      .toList();
  String? error;
  var saving = false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: Text(prepend ? '链式节点' : '添加后置代理'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (chainLabel != null) ...[
                      Text(chainLabel,
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final values = await _selectNodes(
                                  context,
                                  prepend ? '选择前置节点' : '选择后置节点',
                                  nodes
                                      .where((name) => !current.contains(name))
                                      .toList(),
                                  other);
                              if (values != null && context.mounted) {
                                setDialogState(() {
                                  other = values;
                                  current.removeWhere(other.contains);
                                  error = null;
                                });
                              }
                            },
                      child: Text(
                          '${prepend ? '选择前置节点' : '选择后置节点'}（已选 ${other.length} 个）'),
                    ),
                    SizedBox(
                      width: double.maxFinite,
                      height: (other.length * 64.0)
                          .clamp(0.0, MediaQuery.sizeOf(context).height * 0.4),
                      child: ReorderableListView(
                        primary: false,
                        buildDefaultDragHandles: false,
                        onReorderItem: (oldIndex, newIndex) {
                          if (saving) return;
                          setDialogState(() {
                            final name = other.removeAt(oldIndex);
                            other.insert(newIndex, name);
                          });
                        },
                        children: [
                          for (var index = 0; index < other.length; index++)
                            ListTile(
                              key: ValueKey(other[index]),
                              contentPadding: EdgeInsets.zero,
                              minTileHeight: 64,
                              title: Text(other[index]),
                              trailing: ReorderableDragStartListener(
                                index: index,
                                enabled: !saving,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final eligible = nodes
                                  .where((name) =>
                                      !other.contains(name) &&
                                      !excludedTargets.contains(name))
                                  .toList();
                              final values = await _selectNodes(
                                  context, '选择作用节点', eligible, current);
                              if (values != null && context.mounted) {
                                setDialogState(() {
                                  current = values;
                                  error = null;
                                });
                              }
                            },
                      child: Text('选择作用节点（已选 ${current.length} 个）'),
                    ),
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
                  onPressed:
                      saving || other.isEmpty || other.length == nodes.length
                          ? null
                          : () async {
                              setDialogState(() {
                                saving = true;
                                error = null;
                              });
                              try {
                                await onSave(current, other);
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
