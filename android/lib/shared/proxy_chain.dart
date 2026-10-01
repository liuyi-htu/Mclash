import 'dart:convert';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

const _chainPrefix = '# Mclash 节点链路: ';

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

void _validateChains(Map<String, String> edges) {
  for (final start in edges.keys) {
    final visited = <String>{};
    String? next = start;
    while (next != null) {
      if (!visited.add(next)) throw const FormatException('代理链路形成循环，请选择其他节点');
      next = edges[next];
    }
  }
}

String applySavedProxyChains(String content, String previous) {
  final overrides = readProxyChains(previous);
  final nodes = (loadYaml(content) as YamlMap)['proxies'] as List? ?? [];
  final names = nodes.map((node) => node['name'] as String).toSet();
  final edges = <String, String>{
    for (final node in nodes)
      if (node['dialer-proxy'] is String)
        node['name'] as String: node['dialer-proxy'] as String,
  };
  final editor = YamlEditor(content);
  for (var i = 0; i < nodes.length; i++) {
    final target = nodes[i]['name'] as String;
    final upstream = overrides[target];
    if (upstream != null && names.contains(upstream)) {
      edges[target] = upstream;
      editor.update(['proxies', i, 'dialer-proxy'], upstream);
    }
  }
  _validateChains(edges);
  final body = editor
      .toString()
      .split('\n')
      .where((line) => !line.startsWith(_chainPrefix))
      .join('\n');
  return overrides.isEmpty
      ? body
      : '$_chainPrefix${jsonEncode(overrides)}\n$body';
}

/// `dialer-proxy` identifies the first hop used to reach the exit node.
String setProxyChain(String content, String current, String other,
    {required bool prepend}) {
  final names = savedProxyNodeNames(content);
  if (current == other) throw const FormatException('不能选择同一个节点作为前置或后置代理');
  if (!names.contains(current) || !names.contains(other)) {
    throw const FormatException('所选节点已不存在，请重新选择');
  }
  final target = prepend ? current : other;
  final upstream = prepend ? other : current;
  final overrides = readProxyChains(content)..[target] = upstream;
  final body = content
      .split('\n')
      .where((line) => !line.startsWith(_chainPrefix))
      .join('\n');
  return applySavedProxyChains(body, '$_chainPrefix${jsonEncode(overrides)}\n');
}
