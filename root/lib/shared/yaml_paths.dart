import 'dart:collection';
import 'package:yaml/yaml.dart';

/// Remove optional slash escapes only from double-quoted path values.
/// Editing source spans preserves comments and meaningful backslashes.
String normalizeYamlPaths(String content) {
  final edits = <int, (int, String)>{};
  final visited = HashSet<YamlNode>.identity();
  final cleaned = HashSet<YamlNode>.identity();
  void clean(YamlNode node) {
    if (!cleaned.add(node)) return;
    if (node is YamlList) {
      for (final item in node.nodes) {
        clean(item);
      }
    } else if (node is YamlScalar && node.style == ScalarStyle.DOUBLE_QUOTED) {
      final text = node.span.text;
      final result = StringBuffer();
      for (var i = 0; i < text.length; i++) {
        if (text[i] == r'\' && i + 1 < text.length) {
          final next = text[++i];
          if (next != '/') result.write(r'\');
          result.write(next);
        } else {
          result.write(text[i]);
        }
      }
      if (result.toString() != text) {
        edits[node.span.start.offset] =
            (node.span.end.offset, result.toString());
      }
    }
  }

  void visit(YamlNode node) {
    if (!visited.add(node)) return;
    if (node is YamlMap) {
      for (final entry in node.nodes.entries) {
        if ((entry.key as YamlNode).value == 'path') clean(entry.value);
        visit(entry.value);
      }
    } else if (node is YamlList) {
      for (final item in node.nodes) {
        visit(item);
      }
    }
  }

  try {
    for (final document in loadYamlDocuments(content)) {
      visit(document.contents);
    }
  } on YamlException {
    // Keep invalid drafts unchanged; the existing save validation handles them.
    return content;
  }
  var result = content;
  for (final start in edits.keys.toList()..sort((a, b) => b.compareTo(a))) {
    final edit = edits[start]!;
    result = result.replaceRange(start, edit.$1, edit.$2);
  }
  return result;
}
