import 'dart:collection';
import 'dart:convert';
import 'package:yaml/yaml.dart';

const maxNodeInputBytes = 8 * 1024 * 1024;

/// Expand YAML merges before editing: package:yaml resolves aliases but leaves <<.
List<Map<String, dynamic>> parseMihomoNodes(String input) {
  if (input.length > maxNodeInputBytes ||
      utf8.encode(input).length > maxNodeInputBytes) {
    throw const FormatException('节点内容过大（最多 8 MiB）');
  }
  final active = HashSet<Object>.identity();
  var expanded = 0;
  dynamic expand(dynamic value, [int depth = 0]) {
    if (++expanded > 200000 || depth > 100) {
      throw const FormatException('节点内容嵌套过深或展开后过大');
    }
    if (value is! Map && value is! List) return value;
    if (!active.add(value as Object)) {
      throw const FormatException('节点 YAML 包含循环引用');
    }
    try {
      if (value is List) {
        return [for (final item in value) expand(item, depth + 1)];
      }
      final map = value as Map;
      final result = <String, dynamic>{};
      if (map.containsKey('<<')) {
        final merged = expand(map['<<'], depth + 1);
        final sources = merged is List ? merged : [merged];
        for (final source in sources) {
          if (source is! Map<String, dynamic>) {
            throw const FormatException('YAML 合并键 << 必须引用映射或映射列表');
          }
          for (final entry in source.entries) {
            result.putIfAbsent(entry.key, () => entry.value);
          }
        }
      }
      for (final entry in map.entries) {
        if (entry.key == '<<') continue;
        if (entry.key is! String) {
          throw const FormatException('节点 YAML 字段名必须是字符串');
        }
        result[entry.key as String] = expand(entry.value, depth + 1);
      }
      return result;
    } finally {
      active.remove(value);
    }
  }

  final nodes = <Map<String, dynamic>>[];
  try {
    for (final document
        in loadYamlDocuments(input.replaceFirst(RegExp(r'^\uFEFF'), ''))) {
      final root = document.contents.value;
      final dynamic source;
      if (root is Map && root.containsKey('proxies')) {
        source = root['proxies'];
        if (source is! List) {
          throw const FormatException('proxies 必须是节点列表');
        }
      } else {
        source = root;
      }
      final resolved = expand(source);
      if (resolved == null) continue;
      for (final item in resolved is List ? resolved : [resolved]) {
        if (item is! Map<String, dynamic> ||
            item['name'] is! String ||
            (item['name'] as String).trim().isEmpty ||
            item['type'] is! String ||
            (item['type'] as String).trim().isEmpty) {
          throw const FormatException('每个 Mihomo 节点都需要非空的 name 和 type');
        }
        // No protocol whitelist: preserve every protocol-specific field.
        nodes.add(item);
      }
    }
  } on YamlException {
    // YAML diagnostics include source lines, which can contain credentials.
    throw const FormatException('Mihomo YAML 格式无效；使用别名时请同时复制锚点定义');
  }
  if (nodes.isEmpty) throw const FormatException('未找到 Mihomo 节点');
  final names = <String>{};
  for (final node in nodes) {
    if (!names.add(node['name'] as String)) {
      throw const FormatException('导入内容中节点名称重复，请先修改为不同名称');
    }
  }
  return nodes;
}
