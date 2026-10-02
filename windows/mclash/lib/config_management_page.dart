// Keep these APIs compatible with the Flutter 3.32 CI toolchain.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'config_management.dart';
import 'proxy_chain.dart';
import 'subscription_filter.dart';
import 'subscription_filter_dialog.dart';

enum ConfigManagementMode { rules, groups, filters }

class ConfigManagementPage extends StatefulWidget {
  const ConfigManagementPage(
      {super.key,
      required this.content,
      required this.mode,
      required this.onSave});
  final String content;
  final ConfigManagementMode mode;
  final Future<void> Function(String) onSave;
  @override
  State<ConfigManagementPage> createState() => _ConfigManagementPageState();
}

class _ConfigManagementPageState extends State<ConfigManagementPage> {
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

  Future<void> _change(String Function() change) async {
    try {
      await _save(change());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _rule([int? index]) async {
    final rules = configRules(_content);
    final result = await _ruleDialog(
        context, index == null ? null : rules[index], configPolicies(_content));
    if (result == null || !mounted) return;
    if (index == null) {
      final matchIndex =
          rules.indexWhere((rule) => rule.split(',').first.trim() == 'MATCH');
      rules.insert(
          matchIndex < 0 || result.startsWith('MATCH,')
              ? rules.length
              : matchIndex,
          result);
    } else {
      rules[index] = result;
    }
    await _change(() => updateConfigRules(_content, rules));
  }

  Future<void> _group([Map<String, dynamic>? group]) async {
    final result = await _groupDialog(context, _content, group);
    if (result == null || !mounted) return;
    await _change(() => updateConfigGroup(_content, result,
        oldName: group?['name'] as String?));
  }

  Future<void> _deleteGroup(String name) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('删除 $name？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除'))
              ],
            ));
    if (confirmed == true && mounted) {
      await _change(() => deleteConfigGroup(_content, name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final rules = configRules(_content);
    final groups = configGroups(_content);
    final managed = readProxyChainGroups(_content);
    final filters = readSubscriptionFilters(_content);
    return PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(
              title: Text(switch (mode) {
                ConfigManagementMode.rules => '规则管理',
                ConfigManagementMode.groups => '代理组管理',
                ConfigManagementMode.filters => '正则设置',
              }),
              actions: [
                if (mode != ConfigManagementMode.filters)
                  IconButton(
                      tooltip:
                          mode == ConfigManagementMode.rules ? '新增规则' : '新增代理组',
                      onPressed: _saving
                          ? null
                          : () => mode == ConfigManagementMode.rules
                              ? _rule()
                              : _group(),
                      icon: const Icon(Icons.add))
              ]),
          body: Column(children: [
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
                child: Text(switch (mode) {
                  ConfigManagementMode.rules => '规则从上到下匹配，拖动右侧手柄调整顺序。每次修改自动保存。',
                  ConfigManagementMode.groups => '这里只显示当前成员，请通过正则设置调整。',
                  ConfigManagementMode.filters =>
                    '选择任意代理组设置正则。留空匹配全部节点；更新订阅时自动重新匹配。',
                })),
            Expanded(
                child: AbsorbPointer(
                    absorbing: _saving,
                    child: mode == ConfigManagementMode.rules
                        ? ReorderableListView.builder(
                            itemCount: rules.length,
                            buildDefaultDragHandles: false,
                            onReorder: (oldIndex, newIndex) {
                              if (newIndex > oldIndex) newIndex--;
                              final reordered = [...rules];
                              reordered.insert(
                                  newIndex, reordered.removeAt(oldIndex));
                              _change(
                                  () => updateConfigRules(_content, reordered));
                            },
                            itemBuilder: (context, index) => ListTile(
                                key: ValueKey('$index:${rules[index]}'),
                                title: Text(rules[index]),
                                leading: Text('${index + 1}'),
                                onTap: () => _rule(index),
                                trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                          tooltip: '删除规则',
                                          icon:
                                              const Icon(Icons.delete_outline),
                                          onPressed: () => _change(() =>
                                              updateConfigRules(
                                                  _content,
                                                  [...rules]
                                                    ..removeAt(index)))),
                                      ReorderableDragStartListener(
                                          index: index,
                                          child: const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: Icon(Icons.drag_handle))),
                                    ])))
                        : ListView.builder(
                            itemCount: groups.length,
                            itemBuilder: (context, index) {
                              final group = groups[index];
                              final name = group['name'] as String;
                              final locked = managed.containsKey(name);
                              return ListTile(
                                  title: Text(name),
                                  subtitle: Text(locked
                                      ? '由链式节点管理'
                                      : mode == ConfigManagementMode.filters
                                          ? filters.containsKey(name)
                                              ? (filters[name]!.isEmpty
                                                  ? '匹配全部节点'
                                                  : filters[name]!)
                                              : '当前成员，尚未设置正则'
                                          : '${group['type']} · ${(group['proxies'] as List? ?? []).length} 个成员'),
                                  enabled: !locked,
                                  onTap: () async {
                                    if (mode == ConfigManagementMode.groups) {
                                      await _group(group);
                                      return;
                                    }
                                    await showSubscriptionFilterDialog(
                                        context: context,
                                        groupName: name,
                                        initialFilter: filters[name] ?? '',
                                        onSave: (filter) => _save(
                                            editSubscriptionFilter(
                                                _content, name, filter)));
                                  },
                                  trailing: mode ==
                                              ConfigManagementMode.groups &&
                                          !locked &&
                                          !isProtectedConfigGroup(name)
                                      ? IconButton(
                                          tooltip: '删除代理组',
                                          icon:
                                              const Icon(Icons.delete_outline),
                                          onPressed: () => _deleteGroup(name))
                                      : mode == ConfigManagementMode.groups &&
                                              isProtectedConfigGroup(name)
                                          ? const Tooltip(
                                              message: '固定代理组，不可删除或改名',
                                              child: Icon(Icons.lock_outline))
                                          : const Icon(Icons.chevron_right));
                            }))),
          ]),
        ));
  }
}

const _ruleTypes = [
  'DOMAIN',
  'DOMAIN-SUFFIX',
  'DOMAIN-KEYWORD',
  'DOMAIN-REGEX',
  'GEOSITE',
  'GEOIP',
  'IP-CIDR',
  'IP-CIDR6',
  'SRC-IP-CIDR',
  'DST-PORT',
  'SRC-PORT',
  'PROCESS-NAME',
  'PROCESS-PATH',
  'RULE-SET',
  'NETWORK',
  'MATCH'
];

Future<String?> _ruleDialog(
    BuildContext context, String? initial, List<String> policies) async {
  final parts = initial?.split(',') ?? [];
  var type = parts.isEmpty ? 'DOMAIN-SUFFIX' : parts.first;
  var advanced = !_ruleTypes.contains(type) || parts.contains('src');
  if (advanced) type = 'DOMAIN-SUFFIX';
  var noResolve = parts.isNotEmpty && parts.last == 'no-resolve';
  final policyIndex = parts.isEmpty ? -1 : rulePolicyIndex(parts);
  var target = policyIndex > 0 && policies.contains(parts[policyIndex])
      ? parts[policyIndex]
      : 'DIRECT';
  final expression = TextEditingController(
      text: parts.length > 2 && !advanced ? parts[1] : '');
  final raw = TextEditingController(text: initial ?? '');
  String? error;
  try {
    return await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text(initial == null ? '新增规则' : '编辑规则'),
                  content: SizedBox(
                      width: 480,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('编辑完整单条规则'),
                            value: advanced,
                            onChanged: (value) =>
                                update(() => advanced = value)),
                        if (advanced)
                          TextField(
                              controller: raw,
                              minLines: 2,
                              maxLines: 6,
                              decoration: const InputDecoration(
                                  labelText: 'Mihomo 规则',
                                  helperText: '支持 AND、OR、NOT、SUB-RULE 等复杂规则'))
                        else ...[
                          DropdownButtonFormField<String>(
                              value: type,
                              decoration:
                                  const InputDecoration(labelText: '规则类型'),
                              items: [
                                for (final item in _ruleTypes)
                                  DropdownMenuItem(
                                      value: item, child: Text(item))
                              ],
                              onChanged: (value) =>
                                  update(() => type = value!)),
                          if (type != 'MATCH')
                            TextField(
                                controller: expression,
                                decoration:
                                    const InputDecoration(labelText: '匹配内容')),
                          DropdownButtonFormField<String>(
                              value: target,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(labelText: '目标策略'),
                              items: [
                                for (final policy in policies)
                                  DropdownMenuItem(
                                      value: policy,
                                      child: Text(policy,
                                          overflow: TextOverflow.ellipsis))
                              ],
                              onChanged: (value) => target = value!),
                          if (['GEOIP', 'IP-CIDR', 'IP-CIDR6', 'RULE-SET']
                              .contains(type))
                            CheckboxListTile(
                                title: const Text('不触发 DNS 解析（no-resolve）'),
                                value: noResolve,
                                onChanged: (value) =>
                                    update(() => noResolve = value!)),
                        ],
                        if (error != null)
                          Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () {
                          if (!advanced &&
                              type != 'MATCH' &&
                              expression.text.trim().isEmpty) {
                            update(() => error = '请填写匹配内容');
                            return;
                          }
                          final rule = advanced
                              ? raw.text.trim()
                              : [
                                  type,
                                  if (type != 'MATCH') expression.text.trim(),
                                  target,
                                  if (noResolve &&
                                      [
                                        'GEOIP',
                                        'IP-CIDR',
                                        'IP-CIDR6',
                                        'RULE-SET'
                                      ].contains(type))
                                    'no-resolve'
                                ].join(',');
                          if (rule.isEmpty) {
                            update(() => error = '请填写规则');
                            return;
                          }
                          Navigator.pop(context, rule);
                        },
                        child: const Text('保存'))
                  ],
                )));
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expression.dispose();
    raw.dispose();
  }
}

Future<Map<String, dynamic>?> _groupDialog(
    BuildContext context, String content, Map<String, dynamic>? initial) async {
  final name = TextEditingController(text: initial?['name'] as String? ?? '');
  final url = TextEditingController(
      text:
          initial?['url'] as String? ?? 'https://www.gstatic.com/generate_204');
  final interval =
      TextEditingController(text: '${initial?['interval'] ?? 300}');
  var type = initial?['type'] as String? ?? 'select';
  final types = {
    'select',
    'url-test',
    'fallback',
    'load-balance',
    if (initial != null) type
  };
  final selected = initial == null
      ? savedProxyNodeNames(content)
      : List<String>.from(initial['proxies'] as List? ?? []);
  if (selected.isEmpty) selected.add('DIRECT');
  String? error;
  try {
    return await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text(initial == null ? '新增代理组' : '编辑代理组'),
                  content: SizedBox(
                      width: 480,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            controller: name,
                            enabled: !isProtectedConfigGroup(
                                initial?['name'] as String?),
                            decoration: const InputDecoration(labelText: '名称')),
                        DropdownButtonFormField<String>(
                            value: type,
                            decoration: const InputDecoration(labelText: '类型'),
                            items: [
                              for (final item in types)
                                DropdownMenuItem(value: item, child: Text(item))
                            ],
                            onChanged: (value) => update(() => type = value!)),
                        if (type != 'select') ...[
                          TextField(
                              controller: url,
                              decoration:
                                  const InputDecoration(labelText: '测速地址')),
                          TextField(
                              controller: interval,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: '检测间隔（秒）')),
                        ],
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text('当前成员（${selected.length}）：通过正则设置修改')),
                        if (initial == null) const Text('新建组默认使用空正则，匹配全部节点。'),
                        if (error != null)
                          Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        SizedBox(
                            height: 240,
                            child: ListView(children: [
                              for (final member in selected)
                                ListTile(dense: true, title: Text(member)),
                            ])),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () {
                          final seconds = int.tryParse(interval.text);
                          if (name.text.trim().isEmpty) {
                            update(() => error = '请填写名称');
                            return;
                          }
                          if (type != 'select' &&
                              (seconds == null ||
                                  seconds <= 0 ||
                                  !(['http', 'https'].contains(
                                          Uri.tryParse(url.text.trim())
                                              ?.scheme) &&
                                      (Uri.tryParse(url.text.trim())
                                              ?.host
                                              .isNotEmpty ??
                                          false)))) {
                            update(() => error = '请填写有效的测速地址和检测间隔');
                            return;
                          }
                          final group = <String, dynamic>{
                            ...?initial,
                            'name': name.text.trim(),
                            'type': type,
                            'proxies': selected
                          };
                          for (final key in [
                            'filter',
                            'use',
                            'include-all',
                            'include-all-proxies',
                            'include-all-providers',
                            'empty-fallback'
                          ]) {
                            group.remove(key);
                          }
                          if (type != 'select') {
                            group['url'] = url.text.trim();
                            group['interval'] = seconds;
                          } else {
                            for (final key in [
                              'url',
                              'interval',
                              'tolerance',
                              'strategy'
                            ]) {
                              group.remove(key);
                            }
                          }
                          if (type != 'load-balance') group.remove('strategy');
                          Navigator.pop(context, group);
                        },
                        child: const Text('保存'))
                  ],
                )));
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    url.dispose();
    interval.dispose();
  }
}
