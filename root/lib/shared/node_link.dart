import 'proxy_chain.dart';
import 'dart:convert';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'subscription_filter.dart';
import 'subscription_host.dart';

const manualNodePrefix = '# Mclash 手动节点: ';

List<String> readManualNodeNames(String content) {
  for (final line in content.split('\n')) {
    if (line.startsWith(manualNodePrefix)) {
      return List<String>.from(
          jsonDecode(line.substring(manualNodePrefix.length)) as List);
    }
  }
  return [];
}

/// Manual nodes take precedence over downloaded nodes with the same name.
List<dynamic> mergeManualNodes(List<dynamic> downloaded, String? previous) {
  if (previous == null) return downloaded;
  final names = readManualNodeNames(previous).toSet();
  final oldNodes = (loadYaml(previous) as YamlMap)['proxies'] as List? ?? [];
  final manual =
      oldNodes.where((node) => names.contains(node['name'])).toList();
  final retained = manual.map((node) => node['name']).toSet();
  return [
    ...manual,
    ...downloaded.where((node) => !retained.contains(node['name']))
  ];
}

String writeManualNodeNames(String content, List<String> names) {
  final body = content
      .split('\n')
      .where((line) => !line.startsWith(manualNodePrefix))
      .join('\n');
  return names.isEmpty ? body : '$manualNodePrefix${jsonEncode(names)}\n$body';
}

Map<String, dynamic> parseVmessLink(String link) {
  final value = link.trim().replaceAll(RegExp(r'\s'), '');
  if (!value.startsWith('vmess://') || value.length > 1024 * 1024) {
    throw const FormatException('请输入一个 vmess:// 节点链接');
  }
  Map<String, dynamic> data;
  try {
    final encoded = value.substring(8).split('#').first;
    data = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(base64.decode(base64.normalize(encoded))))
            as Map);
  } catch (_) {
    throw const FormatException('VMess 链接的 Base64 或 JSON 格式无效');
  }
  String text(String key, [String fallback = '']) =>
      data[key]?.toString().trim() ?? fallback;
  int number(String key, {int? fallback}) {
    final raw = text(key);
    final result = raw.isEmpty ? fallback : int.tryParse(raw);
    if (result == null) throw FormatException('VMess $key 必须是整数');
    return result;
  }

  final server = text('add');
  final id = text('id');
  final port = number('port');
  final alterId = number('aid', fallback: 0);
  if (server.isEmpty || id.isEmpty || port < 1 || port > 65535 || alterId < 0) {
    throw const FormatException('VMess 地址、用户 ID、端口或 alterId 无效');
  }
  var network = text('net', 'tcp');
  if (network.isEmpty) network = 'tcp';
  final type = text('type', 'none');
  if (network == 'tcp' && type == 'http') network = 'http';
  if (!['tcp', 'http', 'ws', 'h2', 'grpc'].contains(network)) {
    throw FormatException('暂不支持 VMess 传输类型：$network');
  }
  if (network == 'tcp' && type.isNotEmpty && type != 'none') {
    throw FormatException('暂不支持 TCP 伪装类型：$type');
  }
  final tls = text('tls');
  if (tls.isNotEmpty && tls != 'none' && tls != 'tls') {
    throw FormatException('暂不支持 VMess TLS 类型：$tls');
  }
  final node = <String, dynamic>{
    'name': text('ps').isEmpty ? 'VMess $server:$port' : text('ps'),
    'type': 'vmess',
    'server': server,
    'port': port,
    'uuid': id,
    'alterId': alterId,
    'cipher': text('scy').isEmpty ? 'auto' : text('scy'),
    'udp': true,
    'network': network,
    'tls': tls == 'tls',
    if (text('sni').isNotEmpty) 'servername': text('sni'),
    if (text('fp').isNotEmpty) 'client-fingerprint': text('fp'),
    if (text('alpn').isNotEmpty)
      'alpn': text('alpn')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
  };
  final host = text('host');
  final path = text('path').isEmpty ? '/' : text('path');
  final hosts =
      host.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  switch (network) {
    case 'http':
      node['http-opts'] = {
        'method': 'GET',
        'path': path.split(',').map((s) => s.trim()).toList(),
        if (hosts.isNotEmpty) 'headers': {'Host': hosts},
      };
    case 'ws':
      node['ws-opts'] = {
        'path': path,
        if (host.isNotEmpty) 'headers': {'Host': host}
      };
    case 'h2':
      node['h2-opts'] = {'path': path, if (hosts.isNotEmpty) 'host': hosts};
    case 'grpc':
      node['grpc-opts'] = {'grpc-service-name': text('path')};
  }
  return node;
}

Map<String, dynamic> parseNodeLink(String link) {
  final value = link.trim();
  if (value.startsWith('vmess://')) return parseVmessLink(value);
  try {
    final uri = Uri.parse(value);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery) {
      throw const FormatException();
    }
    final port = uri.hasPort
        ? uri.port
        : uri.scheme == 'https'
            ? 443
            : 80;
    if (port < 1 || port > 65535) throw const FormatException();
    final userInfo = uri.userInfo;
    final separator = userInfo.indexOf(':');
    return {
      'name': uri.fragment.isEmpty
          ? '${uri.scheme.toUpperCase()} ${uri.host}:$port'
          : Uri.decodeComponent(uri.fragment),
      'type': 'http',
      'server': uri.host,
      'port': port,
      if (uri.scheme == 'https') 'tls': true,
      if (userInfo.isNotEmpty)
        'username': Uri.decodeComponent(
            separator < 0 ? userInfo : userInfo.substring(0, separator)),
      if (separator >= 0)
        'password': Uri.decodeComponent(userInfo.substring(separator + 1)),
    };
  } catch (_) {
    throw const FormatException(
        '请输入 vmess:// 或 HTTP 代理链接，例如 http://10.0.0.200:80/');
  }
}

String addNodeLink(String content, String link) {
  final node = parseNodeLink(link);
  final hostOverride = readSubscriptionHost(content);
  if (hostOverride.isNotEmpty && ['http', 'ws'].contains(node['network'])) {
    final host = hostOverride.trim();
    if (RegExp(r'[\s/\\?#]').hasMatch(host)) {
      throw const FormatException('Host 不要包含 URL、路径或空白字符');
    }
    final key = node['network'] == 'http' ? 'http-opts' : 'ws-opts';
    final options = node[key] as Map<String, dynamic>;
    if (host.isEmpty) {
      options.remove('headers');
    } else {
      options['headers'] = {
        'Host': node['network'] == 'http'
            ? host
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList()
            : host
      };
    }
  }
  final config = loadYaml(content) as YamlMap;
  final nodes = config['proxies'] as List? ?? [];
  final groups = config['proxy-groups'] as List? ?? [];
  final usedNames = <String>{
    'DIRECT',
    'REJECT',
    'REJECT-DROP',
    'PASS',
    'COMPATIBLE',
    'GLOBAL',
    for (final item in nodes) item['name'] as String,
    for (final group in groups) group['name'] as String,
  };
  final originalName = node['name'] as String;
  var name = originalName;
  var suffix = 2;
  while (usedNames.contains(name)) {
    name = '$originalName ($suffix)';
    suffix++;
  }
  node['name'] = name;
  final editor = YamlEditor(content)..update(['proxies'], [node, ...nodes]);
  var result = editor.toString();
  final filters = readSubscriptionFilters(content);
  if (filters.isNotEmpty) {
    result = applySubscriptionFilters(result, filters);
  } else if (!content
      .split('\n')
      .any((line) => line.startsWith(groupFilterPrefix))) {
    // Preserve the existing local-config behavior; subscription manual groups
    // keep their explicitly selected members.
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (group['type'] == 'select' &&
          group['proxies'] is List &&
          !readProxyChainGroups(content).containsKey(group['name'])) {
        editor.update(
            ['proxy-groups', i, 'proxies'], [name, ...group['proxies']]);
      }
    }
    result = editor.toString();
  }

  return applySavedProxyChains(
      writeManualNodeNames(result, [name, ...readManualNodeNames(content)]),
      content);
}

List<String> savedManualNodeNames(String content) {
  final saved = savedProxyNodeNames(content).toSet();
  return readManualNodeNames(content).where(saved.contains).toList();
}

String restoreManualNodes(String content, String? previous) {
  if (previous == null) return content;
  final names = readManualNodeNames(previous).toSet();
  if (names.isEmpty) return content;
  final old = (loadYaml(previous) as YamlMap)['proxies'] as List? ?? [];
  final manual = {
    for (final node in old)
      if (names.contains(node['name'])) node['name']: node
  };
  final nodes = (loadYaml(content) as YamlMap)['proxies'] as List? ?? [];
  final result = (YamlEditor(content)
        ..update(['proxies'],
            [for (final node in nodes) manual[node['name']] ?? node]))
      .toString();
  validateProxyChains(result);
  return result;
}

String deleteManualNode(String content, String name) {
  if (!savedManualNodeNames(content).contains(name)) {
    throw const FormatException('只能删除手动添加的节点');
  }
  final config = loadYaml(content) as YamlMap;
  final nodes = [
    for (final node in config['proxies'] as List)
      if (node['name'] != name) Map<dynamic, dynamic>.from(node as Map)
  ];
  for (final node in nodes) {
    if (node['dialer-proxy'] == name) node.remove('dialer-proxy');
  }
  final editor = YamlEditor(content)..update(['proxies'], nodes);
  final groups = config['proxy-groups'] as List? ?? [];
  for (var i = 0; i < groups.length; i++) {
    final members = groups[i]['proxies'];
    if (members is List && members.contains(name)) {
      final retained = members.where((node) => node != name).toList();
      editor.update(['proxy-groups', i, 'proxies'],
          retained.isEmpty ? ['DIRECT'] : retained);
    }
  }
  final result = removeProxyChainNode(
      writeManualNodeNames(editor.toString(),
          readManualNodeNames(content).where((node) => node != name).toList()),
      name);
  validateProxyChains(result);
  return result;
}
