import 'dialog_typography.dart';
import 'proxy_edit_access.dart';
import 'management_style.dart';
import 'add_action_button.dart';
// Keep these APIs compatible with the Flutter 3.32 CI toolchain.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'config_management.dart';
import 'proxy_chain.dart';
import 'subscription_filter.dart';

enum ConfigManagementMode { rules, groups }

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
    if (!ProxyEditAccess.allowed(context)) {
      throw StateError('请先停止代理再修改配置');
    }
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
    await _change(() => result);
  }

  Future<void> _deleteGroup(String name) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => ProxyEditAccess.inherit(
            context,
            (context) => DialogTypography(
                    child: AlertDialog(
                  title: Text('删除 $name？'),
                  actions: [
                    DestructiveActionButton(
                        onPressed: !ProxyEditAccess.allowed(context)
                            ? null
                            : () => Navigator.pop(context, true),
                        child: const Text('删除'))
                  ],
                ))));
    if (confirmed == true && mounted) {
      await _change(() => deleteConfigGroup(_content, name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = ProxyEditAccess.allowed(context);
    final mode = widget.mode;
    final rules = configRules(_content);
    final groups = configGroups(_content);
    final managed = readProxyChainGroups(_content);
    return PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(
              title: Text(switch (mode) {
            ConfigManagementMode.rules => '规则管理',
            ConfigManagementMode.groups => '代理组管理',
          })),
          floatingActionButtonLocation: managementAddButtonLocation(context),
          floatingActionButton: AddActionButton(
              tooltip: mode == ConfigManagementMode.rules ? '新增规则' : '新增代理组',
              onPressed: !editable || _saving
                  ? null
                  : () =>
                      mode == ConfigManagementMode.rules ? _rule() : _group()),
          body: ManagementBody(
              child: Column(children: [
            if (_saving) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            if (mode == ConfigManagementMode.rules)
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('规则从上到下匹配，拖动右侧手柄调整顺序。每次修改自动保存。',
                      style: TextStyle(fontSize: 12))),
            if (mode == ConfigManagementMode.groups)
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('拖动右侧手柄调整代理组顺序。每次修改自动保存。',
                      style: TextStyle(fontSize: 12))),
            Expanded(
                child: AbsorbPointer(
                    absorbing: _saving,
                    child: mode == ConfigManagementMode.rules
                        ? ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 168),
                            itemCount: rules.length,
                            buildDefaultDragHandles: false,
                            onReorder: (oldIndex, newIndex) {
                              if (!editable) return;
                              if (newIndex > oldIndex) newIndex--;
                              final reordered = [...rules];
                              reordered.insert(
                                  newIndex, reordered.removeAt(oldIndex));
                              _change(
                                  () => updateConfigRules(_content, reordered));
                            },
                            itemBuilder: (context, index) => ManagementCard(
                                key: ValueKey('$index:${rules[index]}'),
                                compact: true,
                                child: ListTile(
                                    minTileHeight: 56,
                                    key: ValueKey('$index:${rules[index]}'),
                                    enabled: editable,
                                    title: ScrollConfiguration(
                                      behavior: ScrollConfiguration.of(context)
                                          .copyWith(scrollbars: false),
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Text(rules[index],
                                            maxLines: 1, softWrap: false),
                                      ),
                                    ),
                                    leading: Text('${index + 1}',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontSize: 12)),
                                    onTap: editable ? () => _rule(index) : null,
                                    trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ManagementDeleteButton(
                                              tooltip: '删除规则',
                                              onPressed: !editable
                                                  ? null
                                                  : () => _change(() =>
                                                      updateConfigRules(
                                                          _content,
                                                          [
                                                            ...rules
                                                          ]..removeAt(index)))),
                                          ReorderableDragStartListener(
                                              enabled: editable,
                                              index: index,
                                              child: const Padding(
                                                  padding: EdgeInsets.all(14),
                                                  child: Icon(Icons.drag_handle,
                                                      size: 20))),
                                        ]))))
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 168),
                            itemCount: groups.length,
                            buildDefaultDragHandles: false,
                            onReorder: (oldIndex, newIndex) {
                              if (!editable || _saving) return;
                              if (newIndex > oldIndex) newIndex--;
                              if (newIndex == oldIndex) return;
                              final names = [
                                for (final group in groups)
                                  group['name'] as String
                              ];
                              names.insert(newIndex, names.removeAt(oldIndex));
                              _change(
                                  () => reorderConfigGroups(_content, names));
                            },
                            itemBuilder: (context, index) {
                              final group = groups[index];
                              final name = group['name'] as String;
                              final locked = managed.containsKey(name);
                              return ManagementCard(
                                  key: ValueKey(name),
                                  compact: true,
                                  child: ListTile(
                                      minTileHeight: 64,
                                      title: Text(name),
                                      subtitle: Text(locked
                                          ? '由链式节点管理'
                                          : '${group['type']} · ${(group['proxies'] as List? ?? []).length} 个成员'),
                                      enabled: editable && !locked,
                                      onTap: editable && !locked
                                          ? () => _group(group)
                                          : null,
                                      trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                                width: 48,
                                                height: 48,
                                                child: !locked &&
                                                        !isProtectedConfigGroup(
                                                            name)
                                                    ? ManagementDeleteButton(
                                                        tooltip: '删除代理组',
                                                        onPressed: !editable
                                                            ? null
                                                            : () =>
                                                                _deleteGroup(
                                                                    name))
                                                    : isProtectedConfigGroup(
                                                            name)
                                                        ? const Tooltip(
                                                            message:
                                                                '固定代理组，不可删除或改名',
                                                            child: Center(
                                                                child: Icon(Icons
                                                                    .lock_outline)))
                                                        : const Center(
                                                            child: Icon(Icons
                                                                .chevron_right))),
                                            ReorderableDragStartListener(
                                                enabled: editable && !_saving,
                                                index: index,
                                                child: const Tooltip(
                                                    message: '拖动排序',
                                                    child: Padding(
                                                        padding:
                                                            EdgeInsets.all(14),
                                                        child: Icon(
                                                            Icons.drag_handle,
                                                            size: 20)))),
                                          ])));
                            }))),
          ])),
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
        builder: (_) => ProxyEditAccess.inherit(
            context,
            (context) => StatefulBuilder(
                builder: (context, update) => DialogTypography(
                        child: AlertDialog(
                      title: Text(initial == null ? '新增规则' : '编辑规则',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontSize: 18)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      content: SizedBox(
                          width: 420,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text('编辑完整单条规则',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium),
                                    value: advanced,
                                    onChanged: !ProxyEditAccess.allowed(context)
                                        ? null
                                        : (value) =>
                                            update(() => advanced = value)),
                                const SizedBox(height: 10),
                                if (advanced)
                                  TextField(
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                      enabled: ProxyEditAccess.allowed(context),
                                      controller: raw,
                                      minLines: 2,
                                      maxLines: 6,
                                      decoration: managementFieldDecoration(
                                              context, 'Mihomo 规则')
                                          .copyWith(
                                              helperText:
                                                  '支持 AND、OR、NOT、SUB-RULE 等复杂规则'))
                                else ...[
                                  DropdownButtonFormField<String>(
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                      value: type,
                                      isExpanded: true,
                                      decoration: managementFieldDecoration(
                                          context, '规则类型'),
                                      items: [
                                        for (final item in _ruleTypes)
                                          DropdownMenuItem(
                                              value: item,
                                              child: Text(item,
                                                  overflow:
                                                      TextOverflow.ellipsis))
                                      ],
                                      onChanged:
                                          !ProxyEditAccess.allowed(context)
                                              ? null
                                              : (value) =>
                                                  update(() => type = value!)),
                                  if (type != 'MATCH') ...[
                                    const SizedBox(height: 10),
                                    TextField(
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                        enabled:
                                            ProxyEditAccess.allowed(context),
                                        controller: expression,
                                        decoration: managementFieldDecoration(
                                            context, '匹配内容')),
                                  ],
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                      value: target,
                                      isExpanded: true,
                                      decoration: managementFieldDecoration(
                                          context, '目标策略'),
                                      items: [
                                        for (final policy in policies)
                                          DropdownMenuItem(
                                              value: policy,
                                              child: Text(policy,
                                                  overflow:
                                                      TextOverflow.ellipsis))
                                      ],
                                      onChanged:
                                          !ProxyEditAccess.allowed(context)
                                              ? null
                                              : (value) => target = value!),
                                  if ([
                                    'GEOIP',
                                    'IP-CIDR',
                                    'IP-CIDR6',
                                    'RULE-SET'
                                  ].contains(type))
                                    CheckboxListTile(
                                        title: const Text(
                                            '不触发 DNS 解析（no-resolve）'),
                                        value: noResolve,
                                        onChanged:
                                            !ProxyEditAccess.allowed(context)
                                                ? null
                                                : (value) => update(
                                                    () => noResolve = value!)),
                                ],
                                if (error != null)
                                  Text(error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error)),
                              ]))),
                      actions: [
                        FilledButton(
                            onPressed: !ProxyEditAccess.allowed(context)
                                ? null
                                : () {
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
                                            if (type != 'MATCH')
                                              expression.text.trim(),
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
                    )))));
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expression.dispose();
    raw.dispose();
  }
}

Future<String?> _groupDialog(
    BuildContext context, String content, Map<String, dynamic>? initial) async {
  final initialFilter =
      readSubscriptionFilters(content)[initial?['name']] ?? '';
  final filter = TextEditingController(text: initialFilter);
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
  var includeDirect = readGroupDirectOptions(content)[initial?['name']] ?? true;
  String? error;
  try {
    return await showDialog<String>(
        context: context,
        builder: (_) => ProxyEditAccess.inherit(
            context,
            (context) => StatefulBuilder(
                builder: (context, update) => DialogTypography(
                        child: AlertDialog(
                      title: Text(initial == null ? '新增代理组' : '编辑代理组',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontSize: 18)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      content: SizedBox(
                          width: 420,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                TextField(
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                    controller: name,
                                    enabled: ProxyEditAccess.allowed(context) &&
                                        !isProtectedConfigGroup(
                                            initial?['name'] as String?),
                                    decoration: managementFieldDecoration(
                                        context, '名称')),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                    value: type,
                                    decoration: managementFieldDecoration(
                                        context, '类型'),
                                    items: [
                                      for (final item in types)
                                        DropdownMenuItem(
                                            value: item,
                                            child: Text(item,
                                                overflow:
                                                    TextOverflow.ellipsis))
                                    ],
                                    onChanged: !ProxyEditAccess.allowed(context)
                                        ? null
                                        : (value) =>
                                            update(() => type = value!)),
                                if (type != 'select') ...[
                                  const SizedBox(height: 10),
                                  TextField(
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                      enabled: ProxyEditAccess.allowed(context),
                                      controller: url,
                                      decoration: managementFieldDecoration(
                                          context, '测速地址')),
                                  const SizedBox(height: 10),
                                  TextField(
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                      enabled: ProxyEditAccess.allowed(context),
                                      controller: interval,
                                      keyboardType: TextInputType.number,
                                      decoration: managementFieldDecoration(
                                          context, '检测间隔（秒）')),
                                ],
                                const SizedBox(height: 10),
                                DropdownButtonFormField<bool>(
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  value: includeDirect,
                                  decoration: managementFieldDecoration(
                                      context, 'DIRECT'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: true, child: Text('DIRECT')),
                                    DropdownMenuItem(
                                        value: false, child: Text('off')),
                                  ],
                                  onChanged: (value) =>
                                      update(() => includeDirect = value!),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                    enabled: ProxyEditAccess.allowed(context),
                                    controller: filter,
                                    minLines: 1,
                                    maxLines: 4,
                                    decoration: managementFieldDecoration(
                                        context, '正则表达式')),
                                const SizedBox(height: 10),
                                if (error != null)
                                  Text(error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error)),
                                Container(
                                  constraints: BoxConstraints(
                                    maxHeight:
                                        (MediaQuery.sizeOf(context).height *
                                                0.32)
                                            .clamp(96.0, 240.0),
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: ListView.builder(
                                    primary: false,
                                    shrinkWrap: true,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    itemCount: selected.length,
                                    itemBuilder: (context, index) => ListTile(
                                      minTileHeight: 48,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14),
                                      title: ScrollConfiguration(
                                        behavior:
                                            ScrollConfiguration.of(context)
                                                .copyWith(scrollbars: false),
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Text(selected[index],
                                              maxLines: 1,
                                              softWrap: false,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ]))),
                      actions: [
                        FilledButton(
                            onPressed: !ProxyEditAccess.allowed(context)
                                ? null
                                : () {
                                    final seconds = int.tryParse(interval.text);
                                    if (name.text.trim().isEmpty) {
                                      update(() => error = '请填写名称');
                                      return;
                                    }
                                    if (type != 'select' &&
                                        (seconds == null ||
                                            seconds <= 0 ||
                                            !(['http', 'https'].contains(
                                                    Uri.tryParse(
                                                            url.text.trim())
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
                                    if (type != 'load-balance') {
                                      group.remove('strategy');
                                    }
                                    try {
                                      final next = updateConfigGroup(
                                          content, group,
                                          includeDirect: includeDirect,
                                          oldName: initial?['name'] as String?,
                                          filter: initial == null ||
                                                  filter.text.trim() !=
                                                      initialFilter
                                              ? filter.text.trim()
                                              : null);
                                      Navigator.pop(context, next);
                                    } catch (failure) {
                                      update(() => error = failure.toString());
                                    }
                                  },
                            child: const Text('保存'))
                      ],
                    )))));
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    filter.dispose();
    name.dispose();
    url.dispose();
    interval.dispose();
  }
}
