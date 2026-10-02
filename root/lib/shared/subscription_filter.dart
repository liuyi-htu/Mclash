import 'dart:convert';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

const domesticGroup = '🚀 国内';
const foreignGroup = '🌍 国外';
const defaultSubscriptionFilters = {domesticGroup: '', foreignGroup: ''};
const groupFilterPrefix = '# Mclash 代理组正则: ';
const customGroupFilterPrefix = '# Mclash 代理组「';
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

Map<String, String> readSubscriptionFilters(String content) {
  final config = loadYaml(content) as YamlMap;
  final groups = (config['proxy-groups'] as List? ?? []);
  final names = groups.map((group) => group['name']).toSet();
  final generic =
      content.split('\n').where((line) => line.startsWith(groupFilterPrefix));
  if (generic.isNotEmpty) {
    final result = Map<String, String>.from(
        jsonDecode(generic.first.substring(groupFilterPrefix.length)) as Map)
      ..removeWhere((name, _) => !names.contains(name));
    for (final entry in _prefixes.entries) {
      final lines =
          content.split('\n').where((line) => line.startsWith(entry.value));
      if (result.containsKey(entry.key) && lines.isNotEmpty) {
        result[entry.key] =
            jsonDecode(lines.first.substring(entry.value.length)) as String;
      }
    }
    return result;
  }
  final result = <String, String>{};
  for (final group in groups) {
    final name = group['name'] as String;
    final prefix = _prefixes[name];
    final comments = content
        .split('\n')
        .where((line) => prefix != null && line.startsWith(prefix));
    if (comments.isNotEmpty) {
      result[name] =
          jsonDecode(comments.first.substring(prefix!.length)) as String;
    } else if (group['filter'] is String ||
        defaultSubscriptionFilters.containsKey(name)) {
      result[name] = group['filter'] as String? ?? '';
    }
  }
  return result;
}

String readSubscriptionFilter(String content, String groupName) {
  _groupIndex(loadYaml(content) as YamlMap, groupName);
  return readSubscriptionFilters(content)[groupName] ?? '';
}

String writeSubscriptionFilters(String content, Map<String, String> filters) {
  final body = content
      .split('\n')
      .where((line) =>
          !line.startsWith(groupFilterPrefix) &&
          !line.startsWith(customGroupFilterPrefix) &&
          !_prefixes.values.any(line.startsWith) &&
          line != '# Mclash 默认机场订阅')
      .join('\n');
  return '$groupFilterPrefix${jsonEncode(filters)}\n$body';
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
  for (final groupName in filters.keys) {
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
  return writeSubscriptionFilters(editor.toString(), filters);
}

String editSubscriptionFilter(String content, String groupName, String filter) {
  return applySubscriptionFilters(content, {
    ...readSubscriptionFilters(content),
    groupName: filter.trim(),
  });
}
