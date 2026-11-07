import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Resolve a working copy; callers keep the original subscription in the cache.
Future<String> resolveNodeDomains(String content,
    {Future<List<InternetAddress>> Function(String)? lookup}) async {
  final root = loadYaml(content);
  if (root is! Map || root['proxies'] is! List) return content;
  final nodes = root['proxies'] as List;
  final domains = nodes
      .whereType<Map>()
      .map((n) => n['server'])
      .whereType<String>()
      .where((host) => InternetAddress.tryParse(host) == null)
      .toSet()
      .toList();
  if (domains.isEmpty) return content;
  final resolved = <String, String>{};
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  var next = 0;
  Future<void> worker() async {
    while (next < domains.length) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return;
      final host = domains[next++];
      try {
        final addresses = await (lookup ?? InternetAddress.lookup)(host)
            .timeout(remaining < const Duration(seconds: 5)
                ? remaining
                : const Duration(seconds: 5));
        if (addresses.isEmpty) continue;
        final address = addresses.firstWhere(
            (ip) => ip.type == InternetAddressType.IPv4,
            orElse: () => addresses.first);
        resolved[host] = address.address;
      } catch (_) {
        // Keep domains when offline, unresolvable, or timed out.
      }
    }
  }

  await Future.wait(List.generate(4, (_) => worker()));
  if (resolved.isEmpty) return content;
  final editor = YamlEditor(content);
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is! Map) continue;
    final host = node['server'];
    final address = resolved[host];
    if (address == null) continue;
    final type = node['type']?.toString().toLowerCase();
    if (node['tls'] == true ||
        ['trojan', 'hysteria', 'hysteria2', 'tuic', 'anytls'].contains(type)) {
      final key = ['vmess', 'vless'].contains(type) ? 'servername' : 'sni';
      if (node[key] == null || node[key] == '') {
        editor.update(['proxies', i, key], host);
      }
    }
    if (node['network'] == 'ws') {
      final rawOpts = node['ws-opts'];
      final opts = rawOpts is Map
          ? Map<String, dynamic>.from(rawOpts)
          : <String, dynamic>{};
      final rawHeaders = opts['headers'];
      final headers = rawHeaders is Map
          ? Map<String, dynamic>.from(rawHeaders)
          : <String, dynamic>{};
      if (!headers.keys.any((key) => key.toLowerCase() == 'host')) {
        headers['Host'] = host;
      }
      opts['headers'] = headers;
      editor.update(['proxies', i, 'ws-opts'], opts);
    }
    editor.update(['proxies', i, 'server'], address);
  }
  return editor.toString();
}
