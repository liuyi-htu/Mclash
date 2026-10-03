import 'management_style.dart';
import 'add_action_button.dart';
import 'package:flutter/material.dart';
import 'proxy_chain.dart';
import 'proxy_chain_dialog.dart';

class ProxyChainPage extends StatefulWidget {
  const ProxyChainPage({
    super.key,
    required this.content,
    required this.onSave,
  });

  final String content;
  final Future<void> Function(String content) onSave;

  @override
  State<ProxyChainPage> createState() => _ProxyChainPageState();
}

class _ProxyChainPageState extends State<ProxyChainPage> {
  late String _content = widget.content;
  bool _saving = false;
  String? _error;

  Future<void> _edit([String? id]) async {
    final nodes = savedProxyNodeNames(_content);
    final sets = readProxyChainSets(_content);
    final chainId = id ?? nextProxyChainSetId(_content);
    final initial = sets[chainId] ?? const <String, List<String>>{};
    await showProxyChainDialog(
      context: context,
      nodes: nodes,
      prepend: true,
      chainLabel: '链式节点 $chainId',
      initialNodes: initial['front'] ?? const [],
      initialTargets: initial['frontTargets'] ?? const [],
      excludedTargets: [
        for (final entry in sets.entries)
          if (entry.key != chainId) ...[
            ...entry.value['front'] ?? <String>[],
            ...entry.value['back'] ?? <String>[]
          ]
      ],
      onSave: (current, other) => _save(setProxyChainSet(
          _content, chainId, other,
          prepend: true, targets: current)),
    );
  }

  Future<void> _save(String next) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(next);
      if (mounted) setState(() => _content = next);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除链式节点 $id？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          DestructiveActionButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _save(setProxyChainSet(_content, id, const [],
          prepend: true, targets: const []));
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = readProxyChainSets(_content)
        .entries
        .where((entry) => (entry.value['front'] ?? []).isNotEmpty);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('链式节点')),
        floatingActionButtonLocation: managementAddButtonLocation(context),
        floatingActionButton: AddActionButton(
          tooltip: '新增链式节点',
          onPressed: _saving ? null : () => _edit(),
        ),
        body: ManagementBody(
            child: Column(
          children: [
            if (_saving) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 168),
                children: [
                  for (final entry in existing)
                    ManagementCard(
                        child: ListTile(
                      title: Text('链式节点 ${entry.key}'),
                      subtitle: Text(
                          '${entry.value['front']!.join(' → ')}\n作用节点：${(entry.value['frontTargets'] ?? []).join('、')}'),
                      isThreeLine: true,
                      trailing: ManagementDeleteButton(
                        tooltip: '删除链式节点',
                        onPressed: _saving ? null : () => _delete(entry.key),
                      ),
                      enabled: !_saving,
                      onTap: () => _edit(entry.key),
                    )),
                  if (existing.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('暂无链式节点，点击右下角加号添加。'),
                    ),
                ],
              ),
            ),
          ],
        )),
      ),
    );
  }
}
