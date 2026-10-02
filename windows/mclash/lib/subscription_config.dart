import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'subscription_filter.dart';
import 'config_management.dart' show rulePolicy;
import 'subscription_host.dart';
import 'node_link.dart';
import 'proxy_chain.dart';

Object? _plainSubscriptionValue(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key: _plainSubscriptionValue(entry.value)
    };
  }
  if (value is List) return value.map(_plainSubscriptionValue).toList();
  return value;
}

/// Resolves names in source order and retains dialer references within a source.
String mergeSubscriptionSources(List<String> sources) {
  if (sources.isEmpty) throw const FormatException('请输入订阅链接');
  if (sources.length == 1) return sources.single;
  final batches = <List<Map<String, dynamic>>>[];
  for (var i = 0; i < sources.length; i++) {
    final source = loadYaml(sources[i]);
    final proxies = source is Map ? source['proxies'] : null;
    if (proxies is! List || proxies.isEmpty) {
      throw FormatException('第 ${i + 1} 个订阅没有可内置的 proxies 节点');
    }
    final batch = <Map<String, dynamic>>[];
    for (final node in proxies) {
      if (node is! Map ||
          node['name'] is! String ||
          (node['name'] as String).trim().isEmpty ||
          node['type'] is! String) {
        throw FormatException('第 ${i + 1} 个订阅节点缺少名称或类型');
      }
      batch
          .add(Map<String, dynamic>.from(_plainSubscriptionValue(node) as Map));
    }
    if (batch.map((node) => node['name']).toSet().length != batch.length) {
      throw FormatException('第 ${i + 1} 个订阅节点名称重复');
    }
    batches.add(batch);
  }
  final merged = <Map<String, dynamic>>[];
  for (var i = 0; i < batches.length; i++) {
    final renamed = {
      for (final node in batches[i])
        node['name'] as String: '${i + 1}-${node['name']}'
    };
    for (final node in batches[i]) {
      node['name'] = renamed[node['name']];
      final upstream = node['dialer-proxy'];
      if (renamed.containsKey(upstream)) {
        node['dialer-proxy'] = renamed[upstream];
      }
    }
    merged.addAll(batches[i]);
  }
  return (YamlEditor('')..update([], {'proxies': merged})).toString();
}

/// Refreshes nodes while retaining user routing and proxy groups.
String buildSubscriptionConfig(String template, String subscription,
    {String? previousConfig}) {
  final source = loadYaml(subscription);
  final downloaded = source is YamlMap ? source['proxies'] : null;
  if (downloaded is! YamlList || downloaded.isEmpty) {
    throw const FormatException(
      '订阅没有可内置的 proxies 节点，请使用包含节点的 Mihomo 订阅',
    );
  }
  final nodes = mergeManualNodes(downloaded, previousConfig);
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
  if (previousConfig != null) {
    final previous = loadYaml(previousConfig) as YamlMap;
    final missing = {
      for (final node in previous['proxies'] as List? ?? [])
        node['name'] as String
    }..removeAll(names);
    final subRules = previous['sub-rules'] as Map? ?? {};
    for (final rule in [
      ...List<String>.from(previous['rules'] as List? ?? []),
      for (final rules in subRules.values) ...List<String>.from(rules as List)
    ]) {
      final target = rulePolicy(rule);
      if (missing.contains(target)) {
        throw FormatException('节点 $target 已从订阅移除，但仍被规则引用，请先修改规则；原配置已保留');
      }
    }
  }
  final configContent = previousConfig ?? template;
  final config = loadYaml(configContent) as YamlMap;
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
  final editor = YamlEditor(configContent);
  if (config.containsKey('proxy-providers')) editor.remove(['proxy-providers']);
  editor.update(['proxies'], nodes);
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i] as YamlMap;
    if (group.containsKey('use')) editor.remove(['proxy-groups', i, 'use']);
    final selected = (group['proxies'] as List? ?? [])
        .where((name) => names.contains(name) || reserved.contains(name))
        .toList();
    editor.update(['proxy-groups', i, 'proxies'],
        selected.isEmpty ? ['DIRECT'] : selected);
  }
  final filtered = applySubscriptionFilters(
      editor.toString(), readSubscriptionFilters(configContent));
  final host = readSubscriptionHost(previousConfig ?? template);
  final result = host.isEmpty ? filtered : editSubscriptionHost(filtered, host);
  return restoreManualNodes(
      applySavedProxyChains(
          writeManualNodeNames(
              result, readManualNodeNames(previousConfig ?? '')),
          previousConfig ?? ''),
      previousConfig);
}
