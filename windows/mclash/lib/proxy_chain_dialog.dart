import 'proxy_edit_access.dart';
import 'package:flutter/material.dart';

Future<List<String>?> _selectNodes(BuildContext context, String title,
    List<String> nodes, List<String> initial, String clearLabel) async {
  final selected = initial.toSet();
  var query = '';
  return showDialog<List<String>>(
    context: context,
    builder: (_) => ProxyEditAccess.inherit(
        context,
        (context) => StatefulBuilder(builder: (context, setState) {
              final visible = nodes
                  .where((name) =>
                      name.toLowerCase().contains(query.toLowerCase()))
                  .toList();
              final media = MediaQuery.of(context);
              return AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontSize: 18)),
                scrollable: true,
                content: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        style: Theme.of(context).textTheme.bodyMedium,
                        onChanged: (value) =>
                            setState(() => query = value.trim()),
                        decoration: InputDecoration(
                          hintText: '搜索节点',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      Row(children: [
                        TextButton(
                          onPressed: !ProxyEditAccess.allowed(context)
                              ? null
                              : () => setState(() => selected.addAll(visible)),
                          child: const Text('全选'),
                        ),
                        TextButton(
                          onPressed: !ProxyEditAccess.allowed(context)
                              ? null
                              : () => Navigator.of(context).pop(<String>[]),
                          child: Text(clearLabel),
                        ),
                      ]),
                      SizedBox(
                        height: ((media.size.height - media.viewInsets.bottom) *
                                0.35)
                            .clamp(100.0, 280.0),
                        child: visible.isEmpty
                            ? const Center(child: Text('暂无匹配节点'))
                            : ListView.builder(
                                itemCount: visible.length,
                                itemBuilder: (context, index) =>
                                    CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: _NodeName(visible[index]),
                                  value: selected.contains(visible[index]),
                                  onChanged: !ProxyEditAccess.allowed(context)
                                      ? null
                                      : (checked) => setState(() {
                                            if (checked == true) {
                                              selected.add(visible[index]);
                                            } else {
                                              selected.remove(visible[index]);
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
                      onPressed: !ProxyEditAccess.allowed(context)
                          ? null
                          : () => Navigator.of(context).pop(selected.toList()),
                      child: const Text('确定')),
                ],
              );
            })),
  );
}

class _NodeName extends StatelessWidget {
  const _NodeName(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(name,
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
}

class _NodeSection extends StatelessWidget {
  const _NodeSection({
    required this.title,
    required this.count,
    required this.tooltip,
    required this.onSelect,
    required this.child,
  });
  final String title;
  final int count;
  final String tooltip;
  final VoidCallback? onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text('$title（$count）',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton(
                  onPressed: onSelect,
                  child: Tooltip(message: tooltip, child: const Text('选择')),
                ),
              ]),
              child,
            ],
          ),
        ),
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
        barrierDismissible: true,
        builder: (_) => ProxyEditAccess.inherit(
            context,
            (context) => StatefulBuilder(
                  builder: (context, setDialogState) => PopScope(
                    canPop: !saving,
                    child: AlertDialog(
                      title: Text(prepend ? '链式节点' : '添加后置代理',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontSize: 18)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      content: SizedBox(
                        width: 480,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (chainLabel != null) ...[
                                Text(chainLabel,
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                                const SizedBox(height: 12),
                              ],
                              _NodeSection(
                                title: prepend ? '前置节点' : '后置节点',
                                count: other.length,
                                tooltip: prepend ? '选择前置节点' : '选择后置节点',
                                onSelect: !ProxyEditAccess.allowed(context) ||
                                        saving
                                    ? null
                                    : () async {
                                        final values = await _selectNodes(
                                            context,
                                            prepend ? '选择前置节点' : '选择后置节点',
                                            nodes
                                                .where((name) =>
                                                    !current.contains(name))
                                                .toList(),
                                            other,
                                            prepend ? '清空选择' : '清除后置代理');
                                        if (values != null && context.mounted) {
                                          setDialogState(() {
                                            other = values;
                                            current.removeWhere(other.contains);
                                            error = null;
                                          });
                                        }
                                      },
                                child: SizedBox(
                                  width: double.maxFinite,
                                  height: (other.length * 48.0).clamp(0.0,
                                      MediaQuery.sizeOf(context).height * 0.4),
                                  child: ReorderableListView(
                                    primary: false,
                                    buildDefaultDragHandles: false,
                                    onReorderItem: (oldIndex, newIndex) {
                                      if (saving ||
                                          !ProxyEditAccess.allowed(context)) {
                                        return;
                                      }
                                      setDialogState(() {
                                        final name = other.removeAt(oldIndex);
                                        other.insert(newIndex, name);
                                      });
                                    },
                                    children: [
                                      for (var index = 0;
                                          index < other.length;
                                          index++)
                                        ListTile(
                                          key: ValueKey(other[index]),
                                          contentPadding: EdgeInsets.zero,
                                          minTileHeight: 48,
                                          leading: SizedBox(
                                              width: 20,
                                              child: Text('${index + 1}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall)),
                                          minLeadingWidth: 20,
                                          horizontalTitleGap: 8,
                                          title: _NodeName(other[index]),
                                          trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip:
                                                      '移除前置节点 ${other[index]}',
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error,
                                                  onPressed: !ProxyEditAccess
                                                              .allowed(
                                                                  context) ||
                                                          saving
                                                      ? null
                                                      : () =>
                                                          setDialogState(() {
                                                            other.removeAt(
                                                                index);
                                                            error = null;
                                                          }),
                                                  icon: const Icon(Icons.close,
                                                      size: 20),
                                                ),
                                                ReorderableDragStartListener(
                                                  index: index,
                                                  enabled:
                                                      ProxyEditAccess.allowed(
                                                              context) &&
                                                          !saving,
                                                  child: const Padding(
                                                    padding: EdgeInsets.all(8),
                                                    child: Icon(
                                                        Icons.drag_handle,
                                                        size: 20),
                                                  ),
                                                ),
                                              ]),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _NodeSection(
                                title: '作用节点',
                                count: current.length,
                                tooltip: '选择作用节点',
                                onSelect: !ProxyEditAccess.allowed(context) ||
                                        saving
                                    ? null
                                    : () async {
                                        final eligible = nodes
                                            .where((name) =>
                                                !other.contains(name) &&
                                                !excludedTargets.contains(name))
                                            .toList();
                                        final values = await _selectNodes(
                                            context,
                                            '选择作用节点',
                                            eligible,
                                            current,
                                            '清空选择');
                                        if (values != null && context.mounted) {
                                          setDialogState(() {
                                            current = values;
                                            error = null;
                                          });
                                        }
                                      },
                                child: SizedBox(
                                  height: (current.length * 48.0).clamp(0.0,
                                      MediaQuery.sizeOf(context).height * 0.3),
                                  child: ListView.builder(
                                    primary: false,
                                    itemCount: current.length,
                                    itemBuilder: (context, index) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      minTileHeight: 48,
                                      title: _NodeName(current[index]),
                                      trailing: IconButton(
                                        tooltip: '移除作用节点 ${current[index]}',
                                        color:
                                            Theme.of(context).colorScheme.error,
                                        onPressed: saving
                                            ? null
                                            : () => setDialogState(() {
                                                  current.removeAt(index);
                                                  error = null;
                                                }),
                                        icon: const Icon(Icons.close, size: 20),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (error != null) ...[
                                const SizedBox(height: 12),
                                Text(error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                              ],
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('取消')),
                        FilledButton(
                          onPressed: !ProxyEditAccess.allowed(context) ||
                                  saving ||
                                  (other.isEmpty && initialNodes.isEmpty) ||
                                  (other.isNotEmpty && current.isEmpty) ||
                                  other.length == nodes.length
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
                )),
      ) ??
      false;
}
