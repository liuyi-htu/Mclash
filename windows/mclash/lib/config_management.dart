import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'subscription_filter.dart';
import 'proxy_chain.dart';

const builtinPolicies = [
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'PASS',
  'COMPATIBLE'
];

const _configActionSections = {
  'addNode': 'proxies',
  'host': 'proxies',
  'prependProxy': 'proxies',
  'appendProxy': 'proxies',
  'groups': 'proxy-groups',
  'filters': 'proxy-groups',
  'rules': 'rules',
};

/// Follow the YAML section order; missing sections use the default order.
List<String> configActionOrder(String content) {
  final config = loadYaml(content);
  final sections = <String>{
    if (config is YamlMap)
      for (final key in config.keys)
        if (_configActionSections.containsValue(key)) key as String,
    ..._configActionSections.values,
  };
  return [
    for (final section in sections)
      for (final entry in _configActionSections.entries)
        if (entry.value == section) entry.key,
  ];
}

List<String> configPolicies(String content) {
  final config = loadYaml(content) as YamlMap;
  return [
    ...builtinPolicies,
    for (final group in config['proxy-groups'] as List? ?? [])
      group['name'] as String,
    for (final node in config['proxies'] as List? ?? []) node['name'] as String
  ];
}

List<String> configRules(String content) =>
    List<String>.from((loadYaml(content) as YamlMap)['rules'] as List? ?? []);

dynamic _plain(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: _plain(entry.value)
    };
  }
  if (value is List) return [for (final item in value) _plain(item)];
  return value;
}

List<Map<String, dynamic>> configGroups(String content) => [
      for (final group
          in (loadYaml(content) as YamlMap)['proxy-groups'] as List? ?? [])
        _plain(group) as Map<String, dynamic>
    ];

int rulePolicyIndex(List<String> parts) {
  var index = parts.length - 1;
  while (index > 0 && ['no-resolve', 'src'].contains(parts[index].trim())) {
    index--;
  }
  return index;
}

String? rulePolicy(String rule) {
  final parts = rule.split(',');
  if (parts.first.trim() == 'SUB-RULE' || parts.length < 2) return null;
  return parts[rulePolicyIndex(parts)].trim();
}

String replaceRulePolicy(String rule, String oldName, String newName) {
  final parts = rule.split(',');
  if (parts.first.trim() == 'SUB-RULE') return rule;
  final index = rulePolicyIndex(parts);
  if (index > 0 && parts[index].trim() == oldName) parts[index] = newName;
  return parts.join(',');
}

String updateConfigRules(String content, List<String> rules) {
  for (final rule in rules) {
    final parts = rule.split(',');
    if (parts.length < 2 || parts.any((part) => part.trim().isEmpty)) {
      throw const FormatException('规则格式无效');
    }
    // SUB-RULE targets a sub-rule section rather than a proxy policy.
    if (parts.first != 'SUB-RULE' &&
        !configPolicies(content)
            .contains(parts[rulePolicyIndex(parts)].trim())) {
      throw const FormatException('规则目标不存在，请选择有效的节点或代理组');
    }
  }
  final editor = YamlEditor(content)..update(['rules'], rules);
  return editor.toString();
}

void _validateGraph(String content) {
  final config = loadYaml(content) as YamlMap;
  final graph = <String, List<String>>{
    for (final group in configGroups(content))
      group['name'] as String:
          List<String>.from(group['proxies'] as List? ?? []),
    for (final node in config['proxies'] as List? ?? [])
      if (node['dialer-proxy'] is String)
        node['name'] as String: [node['dialer-proxy'] as String],
  };
  final active = <String>{}, complete = <String>{};
  void visit(String name) {
    if (active.contains(name)) throw const FormatException('代理组或链路形成循环');
    if (!complete.add(name)) return;
    active.add(name);
    for (final child in graph[name] ?? <String>[]) {
      visit(child);
    }
    active.remove(name);
  }

  for (final name in graph.keys) {
    visit(name);
  }
}

String updateConfigGroup(String content, Map<String, dynamic> group,
    {String? oldName}) {
  final name = (group['name'] as String).trim();
  if (name.isEmpty || name.contains(',') || name.contains('\n')) {
    throw const FormatException('代理组名称不能为空，也不能包含逗号或换行');
  }
  if (readProxyChainGroups(content).containsKey(oldName)) {
    throw const FormatException('链路代理组由前置/后置代理管理');
  }
  final policies = configPolicies(content).where((value) => value != oldName);
  if (policies.contains(name) || name == 'GLOBAL') {
    throw const FormatException('名称与已有节点或代理组冲突');
  }
  final members = List<String>.from(group['proxies'] as List? ?? []);
  if (members.isEmpty) throw const FormatException('请选择至少一个成员');
  if (members.contains(name) ||
      members.contains(oldName) ||
      members.any((member) => !configPolicies(content).contains(member))) {
    throw const FormatException('代理组成员无效');
  }
  final groups = configGroups(content);
  final index = groups.indexWhere((item) => item['name'] == oldName);
  final updated = {...group, 'name': name};
  if (index < 0) {
    groups.add(updated);
  } else {
    groups[index] = updated;
  }
  final editor = YamlEditor(content);
  if (oldName != null && oldName != name) {
    for (final item in groups) {
      if (item['proxies'] is List) {
        item['proxies'] = [
          for (final member in item['proxies'])
            member == oldName ? name : member
        ];
      }
    }
    editor.update([
      'rules'
    ], [
      for (final rule in configRules(content))
        replaceRulePolicy(rule, oldName, name)
    ]);
    final subRules = (loadYaml(content) as YamlMap)['sub-rules'] as Map? ?? {};
    for (final entry in subRules.entries) {
      editor.update([
        'sub-rules',
        entry.key
      ], [
        for (final rule in entry.value as List)
          replaceRulePolicy(rule as String, oldName, name)
      ]);
    }
    final nodes = (loadYaml(content) as YamlMap)['proxies'] as List? ?? [];
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i]['dialer-proxy'] == oldName) {
        editor.update(['proxies', i, 'dialer-proxy'], name);
      }
    }
  }
  editor.update(['proxy-groups'], groups);
  // Choosing members switches this group from regex matching to manual selection.
  final filters = readSubscriptionFilters(content)
    ..remove(oldName)
    ..remove(name);
  final result = writeSubscriptionFilters(editor.toString(), filters);
  _validateGraph(result);
  return result;
}

String deleteConfigGroup(String content, String name) {
  if (readProxyChainGroups(content).containsKey(name)) {
    throw const FormatException('链路代理组由前置/后置代理管理');
  }
  final config = loadYaml(content) as YamlMap;
  final groups = configGroups(content);
  final subRules = config['sub-rules'] as Map? ?? {};
  final referenced = groups.any((group) =>
          group['name'] != name &&
          (group['proxies'] as List? ?? []).contains(name)) ||
      (config['proxies'] as List? ?? [])
          .any((node) => node['dialer-proxy'] == name) ||
      [
        ...configRules(content),
        for (final rules in subRules.values) ...List<String>.from(rules as List)
      ].any((rule) => replaceRulePolicy(rule, name, '__deleted__') != rule);
  if (referenced) throw const FormatException('此组仍被规则、其他代理组或链路引用，请先修改引用');
  final editor = YamlEditor(content)
    ..update(['proxy-groups'],
        groups.where((group) => group['name'] != name).toList());
  return writeSubscriptionFilters(
      editor.toString(), readSubscriptionFilters(content)..remove(name));
}
