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
      onSave: (current, other) async {
        final next = setProxyChainSet(_content, chainId, other,
            prepend: true, targets: current);
        setState(() => _saving = true);
        try {
          await widget.onSave(next);
          if (mounted) setState(() => _content = next);
        } finally {
          if (mounted) setState(() => _saving = false);
        }
      },
    );
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
        floatingActionButton: AddActionButton(
          tooltip: '新增链式节点',
          onPressed: _saving ? null : () => _edit(),
        ),
        body: Column(
          children: [
            if (_saving) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final entry in existing)
                    ListTile(
                      title: Text('链式节点 ${entry.key}'),
                      subtitle: Text(
                          '${entry.value['front']!.join(' → ')}\n作用节点：${(entry.value['frontTargets'] ?? []).join('、')}'),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_saving,
                      onTap: () => _edit(entry.key),
                    ),
                  if (existing.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('暂无链式节点，点击右下角加号添加。'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
