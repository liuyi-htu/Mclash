import 'management_style.dart';
import 'add_action_button.dart';
import 'package:flutter/material.dart';

class AddNodePage extends StatefulWidget {
  const AddNodePage({
    super.key,
    required this.nodes,
    required this.onDelete,
    required this.onSave,
  });

  final List<String> nodes;
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
      builder: (context) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !_saving,
          child: AlertDialog(
            title: const Text('添加节点'),
            content: TextField(
              controller: _controller,
              enabled: !_saving,
              minLines: 1,
              maxLines: 6,
              decoration: InputDecoration(
                  labelText: '节点链接', errorText: error, errorMaxLines: 8),
            ),
            actions: [
              TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          update(() => error = null);
                          try {
                            final nodes =
                                await widget.onSave(_controller.text.trim());
                            if (!mounted) return;
                            setState(() {
                              _nodes = nodes;
                              _saving = false;
                            });
                            if (context.mounted) Navigator.of(context).pop();
                          } catch (failure) {
                            if (mounted) setState(() => _saving = false);
                            if (context.mounted) {
                              update(() => error = failure.toString());
                            }
                          }
                        },
                  child: Text(_saving ? '保存中…' : '保存')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(title: Text('添加节点（${_nodes.length}）')),
          floatingActionButtonLocation: managementAddButtonLocation(context),
          floatingActionButton: AddActionButton(
              tooltip: '添加节点', onPressed: _saving ? null : _add),
          body: ManagementBody(
              child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              if (_saving) const LinearProgressIndicator(),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_nodes.isEmpty) const Text('暂无手动节点'),
              for (final name in _nodes)
                ManagementCard(
                    child: ListTile(
                  title: Text(name),
                  trailing: ManagementDeleteButton(
                    tooltip: '删除手动节点',
                    onPressed: _saving
                        ? null
                        : () => _change(() => widget.onDelete(name)),
                  ),
                )),
            ],
          )),
        ),
      );
}
