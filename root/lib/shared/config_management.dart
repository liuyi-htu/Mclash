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

bool isProtectedConfigGroup(String? name) =>
    name == domesticGroup || name == foreignGroup;

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
  if (isProtectedConfigGroup(oldName) && name != oldName) {
    throw const FormatException('国内和国外代理组的名称不可修改');
  }
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
  final groups = configGroups(content);
  final index = groups.indexWhere((item) => item['name'] == oldName);
  final members = index >= 0
      ? List<String>.from(groups[index]['proxies'] as List? ?? [])
      : savedProxyNodeNames(content);
  if (members.isEmpty) members.add('DIRECT');
  if (group['proxies'] is List) {
    final requested = List<String>.from(group['proxies'] as List);
    if (requested.length != members.length ||
        requested
            .asMap()
            .entries
            .any((entry) => entry.value != members[entry.key])) {
      throw const FormatException('代理组成员只能通过正则设置修改');
    }
  }
  if (members.contains(name) ||
      members.contains(oldName) ||
      members.any((member) => !configPolicies(content).contains(member))) {
    throw const FormatException('代理组成员无效');
  }
  final updated = {...group, 'name': name, 'proxies': members};
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
  final filters = readSubscriptionFilters(content);
  if (oldName != null && oldName != name && filters.containsKey(oldName)) {
    filters[name] = filters.remove(oldName)!;
  }
  if (index < 0) filters[name] = '';
  final result = writeSubscriptionFilters(editor.toString(), filters);
  _validateGraph(result);
  return result;
}

String deleteConfigGroup(String content, String name) {
  if (isProtectedConfigGroup(name)) {
    throw const FormatException('国内和国外代理组不可删除');
  }
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

/// Match visible profile metadata to the same actions used by the config menu.
String orderRuntimeMetadata(String content, {String? profileContent}) {
  final source = profileContent ?? content;
  final actions = configActionOrder(source);
  final sets = readProxyChainSets(source);
  final lines =
      runtimeProxyChainComments(content, profileContent: source).split('\n');
  String? action(String line) {
    if (line.startsWith('# Mclash 手动节点: ')) return 'addNode';
    if (line.startsWith('# Mclash HTTP/WS Host: ')) return 'host';
    if (line.startsWith(frontChainPrefix)) return 'prependProxy';
    if (line.startsWith(backChainPrefix)) return 'appendProxy';
    if (line.startsWith(numberedChainPrefix)) {
      final id = line.substring(numberedChainPrefix.length).split(':').first;
      return sets[id]?.containsKey('back') == true
          ? 'appendProxy'
          : 'prependProxy';
    }
    if (line.startsWith('# Mclash 节点链路: ')) return 'prependProxy';
    if (line.startsWith('# Mclash 链路代理组: ')) return 'groups';
    if (line.startsWith(groupFilterPrefix)) return 'filters';
    return null;
  }

  final metadata = [
    for (var index = 0; index < lines.length; index++)
      if (lines[index].startsWith('# Mclash '))
        (index, lines[index].trimRight())
  ];
  int rank(String line) {
    final value = action(line);
    return value == null ? actions.length : actions.indexOf(value);
  }

  int chainId(String line) {
    final prefix = proxyChainCommentPrefix(line);
    if (prefix == null) return 0;
    final id = line.substring(prefix.length).split(':').first;
    return int.tryParse(id) ?? 0;
  }

  metadata.sort((a, b) {
    final byAction = rank(a.$2).compareTo(rank(b.$2));
    if (byAction != 0) return byAction;
    final byId = chainId(a.$2).compareTo(chainId(b.$2));
    return byId != 0 ? byId : a.$1.compareTo(b.$1);
  });
  final body = lines.where((line) => !line.startsWith('# Mclash ')).join('\n');
  return '${metadata.map((entry) => '${entry.$2}\n').join()}$body';
}
