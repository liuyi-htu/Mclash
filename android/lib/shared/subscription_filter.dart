import 'dart:convert';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

const domesticGroup = '🚀 国内';
const foreignGroup = '🌍 国外';
const defaultSubscriptionFilters = {domesticGroup: '上海', foreignGroup: 'KR'};
const _prefixes = {
  domesticGroup: '# Mclash 国内正则: ',
  foreignGroup: '# Mclash 国外正则: '
};

int _groupIndex(YamlMap config, String name) {
  final groups = config['proxy-groups'];
  if (groups is YamlList) {
    final index =
        groups.indexWhere((group) => group is YamlMap && group['name'] == name);
    if (index >= 0) return index;
  }
  throw FormatException('配置文件中找不到 $name 代理组');
}

String readSubscriptionFilter(String content, String groupName) {
  final prefix = _prefixes[groupName]!;
  for (final line in content.split('\n')) {
    if (line.startsWith(prefix)) {
      return jsonDecode(line.substring(prefix.length)) as String;
    }
  }
  final config = loadYaml(content) as YamlMap;
  final index = _groupIndex(config, groupName);
  return config['proxy-groups'][index]['filter'] as String? ??
      defaultSubscriptionFilters[groupName]!;
}

RegExp _compile(String filter) {
  var insensitive = false;
  if (filter.startsWith('(?i)')) {
    insensitive = true;
    filter = filter.substring(4);
  }
  return RegExp(filter, caseSensitive: !insensitive);
}

/// Expressions are kept in comments; Mihomo receives explicit proxy lists.
String applySubscriptionFilters(String content, Map<String, String> filters) {
  final config = loadYaml(content) as YamlMap;
  final nodes = config['proxies'];
  if (nodes is! YamlList || nodes.isEmpty) {
    throw const FormatException('配置没有内置节点，请先更新机场订阅');
  }
  final names = nodes.map((node) => node['name'] as String).toList();
  final editor = YamlEditor(content);
  for (final groupName in defaultSubscriptionFilters.keys) {
    final index = _groupIndex(config, groupName);
    final group = config['proxy-groups'][index] as YamlMap;
    final filter = filters[groupName]!;
    final pattern = _compile(filter);
    final selected = <String>[
      if (groupName == domesticGroup) 'DIRECT',
      ...names.where(pattern.hasMatch),
    ];
    for (final key in [
      'filter',
      'use',
      'include-all-proxies',
      'include-all',
      'include-all-providers',
      'empty-fallback'
    ]) {
      if (group.containsKey(key)) editor.remove(['proxy-groups', index, key]);
    }
    editor.update(['proxy-groups', index, 'proxies'],
        selected.isEmpty ? ['DIRECT'] : selected);
  }
  final body = editor
      .toString()
      .split('\n')
      .where((line) =>
          !_prefixes.values.any(line.startsWith) && line != '# Mclash 默认机场订阅')
      .join('\n');
  return '${[
    for (final group in defaultSubscriptionFilters.keys)
      '${_prefixes[group]}${jsonEncode(filters[group])}'
  ].join('\n')}\n$body';
}

String editSubscriptionFilter(String content, String groupName, String filter) {
  return applySubscriptionFilters(content, {
    for (final group in defaultSubscriptionFilters.keys)
      group: group == groupName
          ? filter.trim()
          : readSubscriptionFilter(content, group),
  });
}
