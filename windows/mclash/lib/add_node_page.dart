import 'dialog_typography.dart';
import 'proxy_edit_access.dart';
import 'management_style.dart';
import 'add_action_button.dart';
import 'package:flutter/material.dart';

class AddNodePage extends StatefulWidget {
  const AddNodePage({
    super.key,
    required this.nodes,
    required this.onDelete,
    required this.onSave,
    this.onReorder,
  });

  final List<String> nodes;
  final Future<List<String>> Function(List<String> order)? onReorder;
  final Future<List<String>> Function(String name) onDelete;
  final Future<List<String>> Function(String link) onSave;

  @override
  State<AddNodePage> createState() => _AddNodePageState();
}

class _AddNodePageState extends State<AddNodePage> {
  final _controller = TextEditingController();
  late List<String> _nodes = List<String>.from(widget.nodes);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _change(Future<List<String>> Function() action) async {
    if (!ProxyEditAccess.allowed(context)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final nodes = await action();
      if (!mounted) return;
      setState(() => _nodes = nodes);
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add() async {
    _controller.clear();
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ProxyEditAccess.inherit(
          context,
          (context) => StatefulBuilder(
                builder: (context, update) => PopScope(
                  canPop: !_saving,
                  child: DialogTypography(
                      child: AlertDialog(
                    alignment: Alignment.center,
                    insetPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 24),
                    title: const Text('添加节点'),
                    titleTextStyle: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                            fontSize: 18,
                            height: 1.45,
                            fontWeight: FontWeight.w600),
                    contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    scrollable: true,
                    content: SizedBox(
                      width: 400,
                      child: TextField(
                        controller: _controller,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontSize: 14, height: 1.45),
                        enabled: ProxyEditAccess.allowed(context) && !_saving,
                        minLines: 1,
                        maxLines: 6,
                        decoration: managementFieldDecoration(context, '节点链接')
                            .copyWith(
                                errorText: error,
                                errorMaxLines: 8,
                                errorStyle: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        fontSize: 12,
                                        height: 1.45,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                      ),
                    ),
                    actions: [
                      FilledButton(
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(64, 44),
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontSize: 14, height: 1.45)),
                          onPressed: !ProxyEditAccess.allowed(context) ||
                                  _saving
                              ? null
                              : () async {
                                  setState(() => _saving = true);
                                  update(() => error = null);
                                  try {
                                    final nodes = await widget
                                        .onSave(_controller.text.trim());
                                    if (!mounted) return;
                                    setState(() {
                                      _nodes = nodes;
                                      _saving = false;
                                    });
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  } catch (failure) {
                                    if (mounted) {
                                      setState(() => _saving = false);
                                    }
                                    if (context.mounted) {
                                      update(() => error = failure.toString());
                                    }
                                  }
                                },
                          child: Text(_saving ? '保存中…' : '保存')),
                    ],
                  )),
                ),
              )),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(title: Text('添加节点（${_nodes.length}）')),
          floatingActionButtonLocation: managementAddButtonLocation(context),
          floatingActionButton: AddActionButton(
              tooltip: '添加节点',
              onPressed:
                  !ProxyEditAccess.allowed(context) || _saving ? null : _add),
          body: ManagementBody(
            child: Column(children: [
              if (_saving) const LinearProgressIndicator(),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_nodes.isEmpty) const Text('暂无手动节点'),
              Expanded(
                  child: ReorderableListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 168),
                buildDefaultDragHandles: false,
                // Keep compatibility with Flutter 3.32 CI.
                // ignore: deprecated_member_use
                onReorder: (oldIndex, newIndex) {
                  if (_saving ||
                      widget.onReorder == null ||
                      !ProxyEditAccess.allowed(context)) {
                    return;
                  }
                  if (newIndex > oldIndex) newIndex--;
                  if (oldIndex == newIndex) return;
                  final order = [..._nodes];
                  order.insert(newIndex, order.removeAt(oldIndex));
                  _change(() => widget.onReorder!(order));
                },
                children: [
                  for (var i = 0; i < _nodes.length; i++)
                    ManagementCard(
                      key: ValueKey(_nodes[i]),
                      child: ListTile(
                        title: Text(_nodes[i]),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          ManagementDeleteButton(
                            tooltip: '删除手动节点',
                            onPressed: _saving ||
                                    !ProxyEditAccess.allowed(context)
                                ? null
                                : () =>
                                    _change(() => widget.onDelete(_nodes[i])),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            enabled: !_saving &&
                                widget.onReorder != null &&
                                ProxyEditAccess.allowed(context),
                            child: const SizedBox(
                                width: 48,
                                height: 48,
                                child: Icon(Icons.drag_handle)),
                          ),
                        ]),
                      ),
                    ),
                ],
              )),
            ]),
          ),
        ),
      );
}
