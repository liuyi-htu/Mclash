import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

Map<String, Map<String, dynamic>> configRuleProviders(String content) {
  final config = loadYaml(content);
  final providers = config is Map ? config['rule-providers'] : null;
  if (providers == null) return {};
  if (providers is! Map) throw const FormatException('规则集配置必须是映射');
  dynamic plain(dynamic value) {
    if (value is Map) {
      return {
        for (final entry in value.entries) '${entry.key}': plain(entry.value)
      };
    }
    if (value is List) return value.map(plain).toList();
    return value;
  }

  final result = <String, Map<String, dynamic>>{};
  for (final entry in providers.entries) {
    if (entry.key is! String || entry.value is! Map) {
      throw const FormatException('规则集名称或内容无效');
    }
    result[entry.key as String] =
        Map<String, dynamic>.from(plain(entry.value) as Map);
  }
  return result;
}

RegExp _reference(String name) =>
    RegExp('(^|[,(])\\s*RULE-SET\\s*,\\s*${RegExp.escape(name)}\\s*(?=[,)])');

Iterable<String> _rules(dynamic config) sync* {
  for (final rule in config['rules'] as List? ?? []) {
    if (rule is String) yield rule;
  }
  for (final rules in (config['sub-rules'] as Map? ?? {}).values) {
    for (final rule in rules as List? ?? []) {
      if (rule is String) yield rule;
    }
  }
}

String updateConfigRuleProvider(
    String content, String name, Map<String, dynamic> provider,
    {String? oldName}) {
  name = name.trim();
  if (name.isEmpty || RegExp(r'[,()\r\n]').hasMatch(name)) {
    throw const FormatException('名称不能为空，且不能包含逗号、括号或换行');
  }
  final providers = configRuleProviders(content);
  if (oldName != null && !providers.containsKey(oldName)) {
    throw const FormatException('原规则集不存在');
  }
  if (name != oldName && providers.containsKey(name)) {
    throw const FormatException('规则集名称已存在');
  }
  final type = provider['type'];
  final behavior = provider['behavior'];
  final format = provider['format'] ?? 'yaml';
  if (!['http', 'file', 'inline'].contains(type) ||
      !['domain', 'ipcidr', 'classical'].contains(behavior) ||
      !['yaml', 'text', 'mrs'].contains(format)) {
    throw const FormatException('请选择有效的来源、行为和格式');
  }
  if (format == 'mrs' && (behavior == 'classical' || type == 'inline')) {
    throw const FormatException('MRS 仅支持远程或文件来源的 domain / ipcidr 规则集');
  }
  if (type == 'http') {
    final url = Uri.tryParse('${provider['url'] ?? ''}');
    if (url == null ||
        !['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty) {
      throw const FormatException('请输入有效的 HTTP / HTTPS 下载链接');
    }
    final interval = provider['interval'];
    if (interval != null && (interval is! int || interval < 0)) {
      throw const FormatException('更新间隔必须是非负整数');
    }
  }
  final path = '${provider['path'] ?? ''}'.trim();
  if (type == 'file' && path.isEmpty) throw const FormatException('请输入本地文件路径');
  if (path.isNotEmpty &&
      providers.entries.any(
          (entry) => entry.key != oldName && entry.value['path'] == path)) {
    throw const FormatException('规则集文件路径已被使用');
  }
  if (type == 'inline') {
    final payload = provider['payload'];
    if (payload is! List ||
        payload.isEmpty ||
        payload.any((value) => value is! String || value.trim().isEmpty)) {
      throw const FormatException('请填写内嵌规则，每行一条');
    }
  }
  final next = <String, dynamic>{};
  for (final entry in providers.entries) {
    next[entry.key == oldName ? name : entry.key] =
        entry.key == oldName ? provider : entry.value;
  }
  if (oldName == null) next[name] = provider;
  final editor = YamlEditor(content)..update(['rule-providers'], next);
  if (oldName != null && oldName != name) {
    final config = loadYaml(content) as Map;
    String rename(String rule) => rule.replaceAllMapped(
        _reference(oldName), (match) => '${match[1]}RULE-SET,$name');
    if (config['rules'] is List) {
      editor.update(['rules'],
          [for (final rule in config['rules']) rename(rule as String)]);
    }
    final subRules = config['sub-rules'];
    if (subRules is Map) {
      for (final entry in subRules.entries) {
        editor.update(['sub-rules', entry.key],
            [for (final rule in entry.value as List) rename(rule as String)]);
      }
    }
  }
  return editor.toString();
}

String deleteConfigRuleProvider(String content, String name) {
  final config = loadYaml(content) as Map;
  if (_rules(config).any((rule) => _reference(name).hasMatch(rule))) {
    throw const FormatException('该规则集仍被规则引用，请先修改或删除对应的 RULE-SET 规则');
  }
  final providers = configRuleProviders(content)..remove(name);
  return (YamlEditor(content)..update(['rule-providers'], providers))
      .toString();
}
