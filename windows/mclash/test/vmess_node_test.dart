import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:mclash/node_link.dart';
import 'package:mclash/subscription_host.dart';
import 'package:mclash/subscription_config.dart';

String linkFor(Map<String, dynamic> overrides) =>
    'vmess://${base64Encode(utf8.encode(jsonEncode({
          'ps': '上海手动',
          'add': 'example.org',
          'port': '443',
          'id': '00000000-0000-4000-8000-000000000001',
          'aid': '0',
          'net': 'tcp',
          'type': 'http',
          'host': 'link.example',
          'path': '/',
          'scy': 'auto',
          'tls': '',
          ...overrides,
        })))}';

void main() {
  final template = File('../../assets/default-config.yaml').readAsStringSync();
  test('TCP HTTP disguise imports as HTTP with integer port and Host list', () {
    final node = parseVmessLink(linkFor({}));
    expect(node['network'], 'http');
    expect(node['port'], 443);
    expect(node['alterId'], 0);
    expect(node['tls'], false);
    expect(node['http-opts']['headers']['Host'], ['link.example']);
    expect(node['http-opts']['path'], ['/']);
    final unpadded = linkFor({'net': 'ws'})
        .replaceAll('=', '')
        .replaceAll('+', '-')
        .replaceAll('/', '_');
    // Preserve the URI scheme when testing URL-safe Base64.
    final normalized = 'vmess://${unpadded.substring(8)}';
    expect(parseVmessLink(normalized)['network'], 'ws');
  });
  test(
      'add writes the node, honors stored Host and preserves rules and filters',
      () {
    final first = addNodeLink(template, linkFor({}));
    final configured = editSubscriptionHost(first, 'preset.example');
    final result = addNodeLink(
        configured, linkFor({'net': 'ws', 'tls': 'tls', 'sni': 'tls.example'}));
    final config = loadYaml(result);
    expect(config['proxies'].length, 2);
    expect(config['proxies'][0]['http-opts']['headers']['Host'],
        ['preset.example']);
    expect(
        config['proxies'][1]['ws-opts']['headers']['Host'], 'preset.example');
    expect(config['proxies'][1]['servername'], 'tls.example');
    expect(config['proxies'][1]['name'], '上海手动 (2)');
    expect(
        config['proxy-groups'][0]['proxies'], ['DIRECT', '上海手动', '上海手动 (2)']);
    expect(config['proxy-groups'][0]['filter'], isNull);
    expect(config['rules'], loadYaml(template)['rules']);
    expect(readManualNodeNames(result), ['上海手动', '上海手动 (2)']);
    expect(loadYaml(first)['proxies'][0]['http-opts']['headers']['Host'],
        ['link.example']);
    final tcp = loadYaml(addNodeLink(
        configured, linkFor({'net': 'tcp', 'type': 'none'})))['proxies'][1];
    expect(tcp['http-opts'], isNull);
    expect(tcp['ws-opts'], isNull);
  });
  test('local config retains policy and adds node to manual select groups', () {
    const local =
        'proxies: []\nproxy-groups: [{name: custom, type: select, proxies: [DIRECT]}]\nrules: [MATCH,custom]\n';
    final result = loadYaml(addNodeLink(local, linkFor({'ps': 'DIRECT'})));
    expect(result['proxy-groups'][0]['proxies'], ['DIRECT', 'DIRECT (2)']);
    expect(result['rules'], loadYaml(local)['rules']);
  });
  test('invalid links and unsupported transports are rejected', () {
    for (final link in [
      'ss://abc',
      'vmess://!',
      'vmess://e30=',
      linkFor({'port': '0'}),
      linkFor({'id': ''}),
      linkFor({'net': 'quic'})
    ]) {
      expect(() => addNodeLink(template, link), throwsFormatException);
    }
  });
  test('refresh preserves manual nodes and their edited Host', () {
    final previous = editSubscriptionHost(
        addNodeLink(template, linkFor({})), 'preset.example');
    final refreshed = buildSubscriptionConfig(
        template, 'proxies: [{name: KR-new, type: ss}, {name: 上海手动, type: ss}]',
        previousConfig: previous);
    final nodes = loadYaml(refreshed)['proxies'];
    expect(nodes.length, 2);
    expect(nodes[1]['type'], 'vmess');
    expect(nodes[1]['http-opts']['headers']['Host'], ['preset.example']);
    expect(readManualNodeNames(refreshed), ['上海手动']);
  });
  test(
      'HTTP proxy URLs use defaults, credentials and TLS without VMess Host rewriting',
      () {
    final plain = parseNodeLink('http://10.0.0.200/#wap');
    expect(plain['name'], 'wap');
    expect(plain['type'], 'http');
    expect(plain['server'], '10.0.0.200');
    expect(plain['port'], 80);
    expect(plain['tls'], isNull);
    final secure =
        parseNodeLink('https://user:p%40ss@example.org:8443/#Office');
    expect(secure['port'], 8443);
    expect(secure['tls'], true);
    expect(secure['username'], 'user');
    expect(secure['password'], 'p@ss');
    expect(secure['name'], 'Office');
    final configured = editSubscriptionHost(
        addNodeLink(template, linkFor({})), 'preset.example');
    final added =
        loadYaml(addNodeLink(configured, 'http://10.0.0.200/#wap'))['proxies']
            [1];
    expect(added['type'], 'http');
    expect(added['server'], '10.0.0.200');
    expect(added['http-opts'], isNull);
    final config = loadYaml(addNodeLink(template, 'http://10.0.0.200/#wap'));
    expect(config['proxy-groups'][0]['proxies'], ['DIRECT']);
    expect(config['proxy-groups'][1]['proxies'], ['DIRECT']);
    expect(config['proxies'][0]['name'], 'wap');
    for (final url in [
      'http://example.org/path',
      'http://example.org:0/',
      'http:///'
    ]) {
      expect(() => parseNodeLink(url), throwsFormatException);
    }
  });
}
