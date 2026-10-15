import 'dart:collection';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Compact proxy entries for the read-only runtime viewer.
/// The configuration supplied to the core is never changed here.
String formatRuntimeConfigForDisplay(String content) {
  try {
    final document = loadYaml(content);
    if (document is! YamlMap) return content;
    final proxies = document['proxies'];
    if (proxies is! YamlList || proxies.isEmpty) return content;
    final compact = [
      for (final proxy in proxies)
        wrapAsYamlNode(_plain(proxy),
            collectionStyle: CollectionStyle.FLOW,
            scalarStyle: ScalarStyle.DOUBLE_QUOTED),
    ];
    if (!_hasAliases(document)) {
      return (YamlEditor(content)
            ..update([
              'proxies'
            ], wrapAsYamlNode(compact, collectionStyle: CollectionStyle.BLOCK)))
          .toString();
    } else {
      // Expand aliases together so references outside proxies remain valid.
      final expanded = _plain(document) as Map;
      expanded['proxies'] = compact;
      final header = content
          .split('\n')
          .takeWhile((line) => line.trim().isEmpty || line.startsWith('#'))
          .join('\n');
      final editor = YamlEditor('{}')..update([], expanded);
      return '${header.isEmpty ? '' : '$header\n'}$editor\n';
    }
  } on FormatException {
    // A broken configuration must remain readable for troubleshooting.
    return content;
  }
}

Object? _plain(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries) _plain(entry.key): _plain(entry.value)
    };
  }
  if (value is List) return [for (final item in value) _plain(item)];
  return value;
}

// Detect references before editing: replacing an anchored proxy collection can
// otherwise leave dangling aliases outside the collection.
bool _hasAliases(YamlNode root) {
  final seen = HashSet<YamlNode>.identity();
  bool visit(YamlNode node) {
    if (!seen.add(node)) return true;
    if (node is YamlMap) {
      for (final entry in node.nodes.entries) {
        if (visit(entry.key as YamlNode) || visit(entry.value)) return true;
      }
    } else if (node is YamlList) {
      for (final child in node.nodes) {
        if (visit(child)) return true;
      }
    }
    return false;
  }

  return visit(root);
}
