import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Keeps the bundled routing policy and embeds only downloaded proxy nodes.
String buildSubscriptionConfig(String template, String subscription,
    {String? previousConfig}) {
  final source = loadYaml(subscription);
  final nodes = source is YamlMap ? source['proxies'] : null;
  if (nodes is! YamlList || nodes.isEmpty) {
    throw const FormatException(
      '订阅没有可内置的 proxies 节点，请使用包含节点的 Mihomo 订阅',
    );
  }
  final names = <String>[];
  for (final node in nodes) {
    if (node is! YamlMap ||
        node['name'] is! String ||
        (node['name'] as String).trim().isEmpty ||
        node['type'] is! String) {
      throw const FormatException('订阅节点缺少名称或类型');
    }
    names.add(node['name'] as String);
  }
  if (names.toSet().length != names.length) {
    throw const FormatException('订阅节点名称重复');
  }
  final config = loadYaml(template) as YamlMap;
  final groups = config['proxy-groups'] as YamlList;
  final reserved = <String>{
    'DIRECT',
    'REJECT',
    'REJECT-DROP',
    'PASS',
    'COMPATIBLE',
    'GLOBAL',
    for (final group in groups) group['name'] as String,
  };
  if (names.any(reserved.contains)) {
    throw const FormatException('订阅节点名称与默认策略冲突');
  }
  final editor = YamlEditor(template);
  if (config.containsKey('proxy-providers')) editor.remove(['proxy-providers']);
  editor.update(['proxies'], nodes);
  final previous = previousConfig == null ? null : loadYaml(previousConfig);
  final previousGroups = previous is YamlMap ? previous['proxy-groups'] : null;
  final filters = <String, String>{
    if (previousGroups is YamlList)
      for (final group in previousGroups)
        if (group is YamlMap &&
            group['name'] is String &&
            group['filter'] is String)
          group['name'] as String: group['filter'] as String,
  };
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i] as YamlMap;
    if (group.containsKey('use')) editor.remove(['proxy-groups', i, 'use']);
    final filter = filters[group['name']] ?? group['filter'];
    if (filter != null) editor.update(['proxy-groups', i, 'filter'], filter);
    editor.update(['proxy-groups', i, 'include-all-proxies'], true);
    editor.update(['proxy-groups', i, 'empty-fallback'], 'DIRECT');
    editor.update(['proxy-groups', i, 'proxies'],
        (group['proxies'] as YamlList?)?.toList() ?? <String>[]);
  }
  return editor.toString();
}
