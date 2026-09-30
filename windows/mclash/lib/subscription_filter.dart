import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

const domesticGroup = '🚀 国内';
const foreignGroup = '🌍 国外';
const defaultSubscriptionFilters = {
  domesticGroup: '上海',
  foreignGroup: 'KR',
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
  final config = loadYaml(content) as YamlMap;
  final index = _groupIndex(config, groupName);
  return config['proxy-groups'][index]['filter'] as String? ??
      defaultSubscriptionFilters[groupName] ??
      '';
}

String editSubscriptionFilter(String content, String groupName, String filter) {
  final config = loadYaml(content) as YamlMap;
  final index = _groupIndex(config, groupName);
  final editor = YamlEditor(content);
  editor.update(['proxy-groups', index, 'filter'], filter.trim());
  // Mihomo applies filter to included nodes and providers, not explicit proxies.
  // Enable inclusion so changing the regex also changes the available nodes.
  final nodes = config['proxies'];
  if (nodes is YamlList && nodes.isNotEmpty) {
    editor.update(['proxy-groups', index, 'include-all-proxies'], true);
    editor.update(['proxy-groups', index, 'empty-fallback'], 'DIRECT');
    editor.update(['proxy-groups', index, 'proxies'],
        groupName == domesticGroup ? ['DIRECT'] : <String>[]);
  }
  return editor.toString();
}
