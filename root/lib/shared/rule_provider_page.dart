import 'package:flutter/material.dart';
import 'add_action_button.dart';
import 'management_style.dart';
import 'rule_provider_management.dart';

class RuleProviderPage extends StatefulWidget {
  const RuleProviderPage(
      {super.key, required this.content, required this.onSave});
  final String content;
  final Future<void> Function(String) onSave;
  @override
  State<RuleProviderPage> createState() => _RuleProviderPageState();
}

class _RuleProviderPageState extends State<RuleProviderPage> {
  late String _content = widget.content;
  bool _saving = false;
  String? _error;

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

  Future<void> _edit([String? name]) async {
    await _providerDialog(
        context,
        name,
        configRuleProviders(_content)[name],
        (nextName, provider) => _save(updateConfigRuleProvider(
            _content, nextName, provider,
            oldName: name)));
  }

  Future<void> _delete(String name) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('删除规则集 $name？',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontSize: 18)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                DestructiveActionButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    try {
      await _save(deleteConfigRuleProvider(_content, name));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers = configRuleProviders(_content);
    return PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(title: const Text('规则集管理')),
          floatingActionButtonLocation: managementAddButtonLocation(context),
          floatingActionButton: AddActionButton(
              tooltip: '新增规则集', onPressed: _saving ? null : () => _edit()),
          body: ManagementBody(
              child: Column(children: [
            if (_saving) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('在规则管理中使用 RULE-SET 引用规则集。每次修改自动保存。',
                    style: Theme.of(context).textTheme.bodySmall)),
            Expanded(
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 168),
                    children: [
                  if (providers.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('暂无规则集，点击右下角加号添加。')),
                  for (final entry in providers.entries)
                    ManagementCard(
                        compact: true,
                        child: ListTile(
                          minTileHeight: 64,
                          title: Text(entry.key),
                          subtitle: Text(
                              '${entry.value['type']} · ${entry.value['behavior']} · ${entry.value['format'] ?? 'yaml'}'),
                          enabled: !_saving,
                          onTap: _saving ? null : () => _edit(entry.key),
                          trailing: ManagementDeleteButton(
                              tooltip: '删除规则集 ${entry.key}',
                              onPressed:
                                  _saving ? null : () => _delete(entry.key)),
                        )),
                ])),
          ])),
        ));
  }
}

Future<void> _providerDialog(
    BuildContext context,
    String? initialName,
    Map<String, dynamic>? initial,
    Future<void> Function(String, Map<String, dynamic>) onSave) async {
  final name = TextEditingController(text: initialName ?? '');
  final url = TextEditingController(text: initial?['url'] as String? ?? '');
  final path = TextEditingController(text: initial?['path'] as String? ?? '');
  final interval =
      TextEditingController(text: '${initial?['interval'] ?? 86400}');
  final proxy = TextEditingController(text: initial?['proxy'] as String? ?? '');
  const type = 'http';
  var behavior = initial?['behavior'] as String? ?? 'domain';
  var format = initial?['format'] as String? ?? 'yaml';
  bool saving = false;
  String? error;
  try {
    await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
              builder: (context, update) {
                final editable = !saving;
                Widget field(TextEditingController controller, String label,
                        {String? hint,
                        bool multiline = false,
                        bool number = false}) =>
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                            controller: controller,
                            enabled: editable,
                            style: Theme.of(context).textTheme.bodyMedium,
                            minLines: multiline ? 3 : 1,
                            maxLines: multiline ? 8 : 1,
                            keyboardType: number
                                ? TextInputType.number
                                : multiline
                                    ? TextInputType.multiline
                                    : TextInputType.text,
                            decoration:
                                managementFieldDecoration(context, label)
                                    .copyWith(hintText: hint)));
                Widget choice(String label, String value, List<String> options,
                        void Function(String) changed) =>
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                            // Keep compatibility with Flutter 3.32 CI.
                            // ignore: deprecated_member_use
                            value: value,
                            isExpanded: true,
                            style: Theme.of(context).textTheme.bodyMedium,
                            decoration:
                                managementFieldDecoration(context, label),
                            items: [
                              for (final item in {...options, value})
                                DropdownMenuItem(value: item, child: Text(item))
                            ],
                            onChanged: editable
                                ? (value) => update(() => changed(value!))
                                : null));
                return PopScope(
                    canPop: !saving,
                    child: AlertDialog(
                      title: Text(initialName == null ? '新增规则集' : '编辑规则集',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontSize: 18)),
                      content: SizedBox(
                          width: 420,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                field(name, '名称'),
                                if (initial != null &&
                                    initial['type'] != 'http')
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Text(
                                          '此规则集原为本地来源，请填写下载链接后保存为远程规则集。',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall)),
                                choice(
                                    '规则行为',
                                    behavior,
                                    ['domain', 'ipcidr', 'classical'],
                                    (value) => behavior = value),
                                choice('文件格式', format, ['yaml', 'text', 'mrs'],
                                    (value) => format = value),
                                if (type == 'http') ...[
                                  field(url, '下载链接',
                                      hint: 'https://example.org/rules.yaml'),
                                  field(interval, '更新间隔（秒）', number: true),
                                  field(proxy, '下载策略（可选）',
                                      hint: 'DIRECT 或代理组名称'),
                                ],
                                if (type != 'inline')
                                  field(path, '缓存路径（可选）',
                                      hint: './rules/example.yaml'),
                                if (error != null)
                                  Text(error!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error)),
                              ]))),
                      actions: [
                        TextButton(
                            onPressed:
                                saving ? null : () => Navigator.pop(context),
                            child: const Text('取消')),
                        FilledButton(
                            onPressed: !editable
                                ? null
                                : () async {
                                    final provider = <String, dynamic>{
                                      ...?initial,
                                      'type': type,
                                      'behavior': behavior,
                                      'format': format
                                    };
                                    for (final key in [
                                      'url',
                                      'interval',
                                      'path',
                                      'proxy',
                                      'payload'
                                    ]) {
                                      provider.remove(key);
                                    }
                                    if (type == 'http') {
                                      final seconds =
                                          int.tryParse(interval.text.trim());
                                      if (seconds == null || seconds <= 0) {
                                        update(() => error = '更新间隔必须是正整数');
                                        return;
                                      }
                                      provider['url'] = url.text.trim();
                                      provider['interval'] = seconds;
                                      if (proxy.text.trim().isNotEmpty) {
                                        provider['proxy'] = proxy.text.trim();
                                      }
                                    }
                                    if (type != 'inline' &&
                                        path.text.trim().isNotEmpty) {
                                      provider['path'] = path.text.trim();
                                    }
                                    update(() {
                                      saving = true;
                                      error = null;
                                    });
                                    try {
                                      await onSave(name.text.trim(), provider);
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    } catch (failure) {
                                      if (context.mounted) {
                                        update(() {
                                          saving = false;
                                          error = failure.toString();
                                        });
                                      }
                                    }
                                  },
                            child: Text(saving ? '保存中…' : '保存')),
                      ],
                    ));
              },
            ));
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final controller in [name, url, path, interval, proxy]) {
      controller.dispose();
    }
  }
}
