import 'dart:convert';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

const _chainPrefix = '# Mclash 节点链路: ';
const _globalPrefix = '# Mclash 全局链路: ';
const _groupPrefix = '# Mclash 链路代理组: ';

List<String> savedProxyNodeNames(String content) {
  final nodes = (loadYaml(content) as YamlMap)['proxies'] as List? ?? [];
  return nodes.map((node) => node['name'] as String).toList();
}

Map<String, String> readProxyChains(String content) {
  for (final line in content.split('\n')) {
    if (line.startsWith(_chainPrefix)) {
      return Map<String, String>.from(
          jsonDecode(line.substring(_chainPrefix.length)) as Map);
    }
  }
  return {};
}

Map<String, List<String>> readProxyChainGroups(String content) {
  for (final line in content.split('\n')) {
    if (line.startsWith(_groupPrefix)) {
      final data = jsonDecode(line.substring(_groupPrefix.length)) as Map;
      return {
        for (final entry in data.entries)
          entry.key as String: List<String>.from(entry.value as List)
      };
    }
  }
  return {};
}

Map<String, List<String>> readGlobalProxyChains(String content) {
  for (final line in content.split('\n')) {
    if (line.startsWith(_globalPrefix)) {
      final data = jsonDecode(line.substring(_globalPrefix.length)) as Map;
      return {
        for (final entry in data.entries)
          entry.key as String: List<String>.from(entry.value as List)
      };
    }
  }
  return {};
}

List<String> readProxyChainTargets(String content, {required bool prepend}) {
  final roles = readGlobalProxyChains(content);
  final saved = roles[prepend ? 'frontTargets' : 'backTargets'];
  final eligible = savedProxyNodeNames(content).where((name) =>
      !(roles['front'] ?? []).contains(name) &&
      !(roles['back'] ?? []).contains(name));
  if (saved != null) return saved.where(eligible.contains).toList();
  // Older profiles applied the chain to every node available at that time.
  return (roles[prepend ? 'front' : 'back'] ?? []).isEmpty
      ? [] : eligible.toList();
}

String setGlobalProxyChain(String content, List<String> selected,
    {required bool prepend, required List<String> targets}) {
  if (!selected.every(savedProxyNodeNames(content).contains)) {
    throw const FormatException('请重新选择已保存的代理节点');
  }
  final roles = readGlobalProxyChains(content);
  final key = prepend ? 'front' : 'back';
  final opposite = roles[prepend ? 'back' : 'front'] ?? [];
  if (selected.any(opposite.contains)) {
    throw const FormatException('前置和后置不能选择同一个节点');
  }
  if (selected.isNotEmpty && targets.isEmpty) {
    throw const FormatException('请至少选择一个作用节点');
  }
  if (!targets.every(savedProxyNodeNames(content).contains) ||
      targets.any((name) => selected.contains(name) || opposite.contains(name))) {
    throw const FormatException('作用节点不能包含前置或后置节点');
  }
  final oppositeKey = prepend ? 'back' : 'front';
  roles['${oppositeKey}Targets'] = readProxyChainTargets(content, prepend: !prepend)
      .where((name) => !selected.contains(name)).toList();
  roles[key] = selected;
  roles['${key}Targets'] = selected.isEmpty ? [] : targets.toSet().toList();
  return _applyGlobalProxyChains(content, content, roles);
}

String _applyGlobalProxyChains(
    String content, String previous, Map<String, List<String>> roles) {
  final names = savedProxyNodeNames(content);
  final front = (roles['front'] ?? <String>[]).where(names.contains).toList();
  final back = (roles['back'] ?? <String>[]).where(names.contains).toList();
  final normal = names
      .where((name) => !front.contains(name) && !back.contains(name))
      .toList();
  if (normal.isEmpty) {
    throw const FormatException('请保留至少一个节点作为作用对象');
  }
  final oldChains = readProxyChains(previous);
  final oldGroups = readProxyChainGroups(previous);
  final config = loadYaml(content) as YamlMap;
  final editor = YamlEditor(content);
  final nodes = config['proxies'] as List;
  for (var i = 0; i < nodes.length; i++) {
    if (oldChains.containsKey(nodes[i]['name']) &&
        nodes[i].containsKey('dialer-proxy')) {
      editor.remove(['proxies', i, 'dialer-proxy']);
    }
  }
  if (config.containsKey('proxy-groups')) {
    editor.update([
      'proxy-groups'
    ], [
      for (final group in config['proxy-groups'] as List)
        if (!oldGroups.containsKey(group['name'])) group
    ]);
  }
  var result = editor
      .toString()
      .split('\n')
      .where((line) =>
          !line.startsWith(_chainPrefix) &&
          !line.startsWith(_groupPrefix) &&
          !line.startsWith(_globalPrefix))
      .join('\n');
  if (front.isNotEmpty) {
    for (var index = 1; index < front.length; index++) {
      result =
          setProxyChain(result, front[index], front[index - 1], prepend: true);
    }
    final targets = (roles['frontTargets'] ?? normal).where(normal.contains).toList();
    if (targets.isNotEmpty) {
      result = setProxyChains(result, targets, [front.last], prepend: true);
    }
  }
  if (back.isNotEmpty) {
    final targets = (roles['backTargets'] ?? normal).where(normal.contains).toList();
    if (targets.isNotEmpty) {
      result = setProxyChains(result, targets, back, prepend: false);
    }
  }
  return '$_globalPrefix${jsonEncode(roles)}\n$result';
}

void _validateChains(Map<String, List<String>> graph) {
  final active = <String>{};
  final complete = <String>{};
  void visit(String name) {
    if (active.contains(name)) throw const FormatException('代理链路形成循环，请选择其他节点');
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

String _writeMetadata(String content, Map<String, String> chains,
    Map<String, List<String>> groups) {
  final body = content
      .split('\n')
      .where((line) =>
          !line.startsWith(_chainPrefix) && !line.startsWith(_groupPrefix))
      .join('\n');
  return '${chains.isEmpty ? '' : '$_chainPrefix${jsonEncode(chains)}\n'}${groups.isEmpty ? '' : '$_groupPrefix${jsonEncode(groups)}\n'}$body';
}

String applySavedProxyChains(String content, String previous) {
  final global = readGlobalProxyChains(previous);
  if (global.isNotEmpty) {
    return _applyGlobalProxyChains(content, previous, global);
  }
  final overrides = readProxyChains(previous);
  final managed = readProxyChainGroups(previous);
  final config = loadYaml(content) as YamlMap;
  final nodes = config['proxies'] as List? ?? [];
  final names = nodes.map((node) => node['name'] as String).toSet();
  final groups = <dynamic>[
    for (final group in config['proxy-groups'] as List? ?? [])
      if (!managed.containsKey(group['name'])) group,
    for (final entry in managed.entries)
      {
        'name': entry.key,
        'type': 'select',
        'proxies': entry.value.where(names.contains).isEmpty
            ? ['DIRECT']
            : entry.value.where(names.contains).toList()
      },
  ];
  final groupNames = groups.map((group) => group['name']).toSet();
  final graph = <String, List<String>>{
    for (final node in nodes)
      if (node['dialer-proxy'] is String)
        node['name'] as String: [node['dialer-proxy'] as String],
    for (final group in groups)
      group['name'] as String:
          List<String>.from(group['proxies'] as List? ?? []),
  };
  final editor = YamlEditor(content);
  if (managed.isNotEmpty) editor.update(['proxy-groups'], groups);
  for (var i = 0; i < nodes.length; i++) {
    final target = nodes[i]['name'] as String;
    final upstream = overrides[target];
    if (upstream != null &&
        (names.contains(upstream) || groupNames.contains(upstream))) {
      graph[target] = [upstream];
      editor.update(['proxies', i, 'dialer-proxy'], upstream);
    }
  }
  _validateChains(graph);
  return _writeMetadata(editor.toString(), overrides, managed);
}

String setProxyChains(String content, List<String> current, List<String> other,
    {required bool prepend}) {
  final names = savedProxyNodeNames(content);
  final currentNames = current.toSet();
  final otherNames = other.toSet();
  if (currentNames.isEmpty || otherNames.isEmpty) {
    throw const FormatException('请在两侧分别选择至少一个节点');
  }
  if (currentNames.intersection(otherNames).isNotEmpty) {
    throw const FormatException('入口和出口不能选择同一个节点');
  }
  if (![...currentNames, ...otherNames].every(names.contains)) {
    throw const FormatException('所选节点已不存在，请重新选择');
  }
  final targets = prepend ? currentNames : otherNames;
  final upstreams = (prepend ? otherNames : currentNames).toList();
  final chains = readProxyChains(content);
  final managed = readProxyChainGroups(content);
  var upstream = upstreams.first;
  if (upstreams.length > 1) {
    final config = loadYaml(content) as YamlMap;
    final used = {
      ...names,
      for (final group in config['proxy-groups'] as List? ?? [])
        group['name'] as String
    };
    final base = prepend ? '🔗 前置代理' : '🔗 后置入口';
    upstream = base;
    var index = 2;
    while (used.contains(upstream)) {
      upstream = '$base ($index)';
      index++;
    }
    managed[upstream] = upstreams;
  }
  for (final target in targets) {
    chains[target] = upstream;
  }
  return applySavedProxyChains(content, _writeMetadata('', chains, managed));
}

String setProxyChain(String content, String current, String other,
        {required bool prepend}) =>
    setProxyChains(content, [current], [other], prepend: prepend);

void validateProxyChains(String content) {
  final config = loadYaml(content) as YamlMap;
  _validateChains({
    for (final node in config['proxies'] as List? ?? [])
      if (node['dialer-proxy'] is String)
        node['name'] as String: [node['dialer-proxy'] as String],
    for (final group in config['proxy-groups'] as List? ?? [])
      group['name'] as String:
          List<String>.from(group['proxies'] as List? ?? []),
  });
}

String removeProxyChainNode(String content, String name) {
  final overrides = readProxyChains(content)
    ..removeWhere((target, upstream) => target == name || upstream == name);
  final managed = readProxyChainGroups(content);
  for (final members in managed.values) {
    members.removeWhere((member) => member == name);
  }
  final roles = readGlobalProxyChains(content);
  for (final members in roles.values) {
    members.removeWhere((member) => member == name);
  }
  roles.removeWhere((key, members) => !key.endsWith('Targets') && members.isEmpty);
  final names = savedProxyNodeNames(content);
  if (!names
      .any((node) => !(roles['front'] ?? []).contains(node) && !(roles['back'] ?? []).contains(node))) {
    roles.clear();
  }
  final body = content
      .split('\n')
      .where((line) => !line.startsWith(_globalPrefix))
      .join('\n');
  final result = _writeMetadata(body, overrides, managed);
  return roles.isEmpty ? result : '$_globalPrefix${jsonEncode(roles)}\n$result';
}
