import 'package:yaml/yaml.dart';

/// Runtime YAML supplies connection fields not exposed by older controllers.
Map<String, Map<String, dynamic>> runtimeProxyDetails(String content) {
  try {
    final config = loadYaml(content);
    if (config is! Map) return {};
    return {
      for (final node in config['proxies'] as List? ?? [])
        if (node is Map && node['name'] is String)
          node['name'] as String: Map<String, dynamic>.from(node),
    };
  } catch (_) {
    return {};
  }
}

class ProxyNodeDetails {
  ProxyNodeDetails(String selected, Map<String, Map<String, dynamic>> proxies) {
    final visiting = <String>{};
    String resolve(String name, {bool record = false}) {
      final seen = <String>{};
      while (true) {
        if (!seen.add(name)) {
          incomplete = true;
          return name;
        }
        if (record) selectionPath.add(name);
        final proxy = proxies[name];
        final now = proxy?['now'];
        if (now is! String || now.isEmpty) return name;
        name = now;
      }
    }

    name = resolve(selected, record: true);
    info = proxies[name] ?? {};
    void connect(String target) {
      final node = resolve(target);
      if (!visiting.add(node)) {
        incomplete = true;
        return;
      }
      final upstream = proxies[node]?['dialer-proxy'];
      if (upstream is String && upstream.isNotEmpty) connect(upstream);
      if (!chain.contains(node)) chain.add(node);
      visiting.remove(node);
    }

    if (name.isNotEmpty) connect(name);
  }

  late final String name;
  late final Map<String, dynamic> info;
  final selectionPath = <String>[];
  final chain = <String>[];
  bool incomplete = false;
}
