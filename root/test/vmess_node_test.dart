import 'package:mclash/shared/proxy_chain.dart';
import 'package:mclash/shared/subscription_filter.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:mclash/shared/node_link.dart';
import 'package:mclash/shared/subscription_host.dart';

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
  final template = File('../assets/default-config.yaml').readAsStringSync();
  test('explicit Host, filter and chain settings still apply to manual nodes',
      () {
    final manual = addNodeLink(template, linkFor({}));
    final edited = editSubscriptionHost(manual, 'explicit.example');
    expect(loadYaml(edited)['proxies'][0]['http-opts']['headers']['Host'],
        ['explicit.example']);
    final filtered =
        editSubscriptionFilter(edited, domesticGroup, '__no_match__');
    expect(loadYaml(filtered)['proxy-groups'][0]['proxies'], ['DIRECT']);
    final withFront = addNodeLink(filtered, 'http://10.0.0.200/#front');
    final chained = setGlobalProxyChain(withFront, ['front'],
        prepend: true, targets: ['上海手动']);
    expect(loadYaml(chained)['proxies'][1]['dialer-proxy'], 'front');
    expect(savedManualNodeNames(chained), ['front', '上海手动']);
  });
  test('deleting manual nodes removes references and rejects airport nodes',
      () {
    const content =
        '# Mclash 手动节点: ["Manual"]\n# Mclash 节点链路: {"Airport":"Manual"}\n# Mclash 链路代理组: {"Chain":["Manual"]}\n# Mclash 全局链路: {"front":["Manual"]}\nproxies: [{name: Airport, type: http, server: airport.example, port: 80, dialer-proxy: Manual}, {name: Manual, type: http, server: manual.example, port: 80}]\nproxy-groups: [{name: Region, type: select, proxies: [Manual]}, {name: Chain, type: select, proxies: [Manual]}]';
    expect(savedManualNodeNames(content), ['Manual']);
    expect(() => deleteManualNode(content, 'Airport'), throwsFormatException);
    final result = deleteManualNode(content, 'Manual');
    final config = loadYaml(result);
    expect(savedManualNodeNames(result), isEmpty);
    expect(config['proxies'].length, 1);
    expect(config['proxies'][0]['name'], 'Airport');
    expect(config['proxies'][0]['dialer-proxy'], isNull);
    expect(config['proxy-groups'][0]['proxies'], ['DIRECT']);
    expect(config['proxy-groups'][1]['proxies'], ['DIRECT']);
  });
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
    expect(config['proxies'][1]['http-opts']['headers']['Host'],
        ['preset.example']);
    expect(
        config['proxies'][0]['ws-opts']['headers']['Host'], 'preset.example');
    expect(config['proxies'][0]['servername'], 'tls.example');
    expect(config['proxies'][0]['name'], '上海手动 (2)');
    expect(
        config['proxy-groups'][0]['proxies'], ['DIRECT', '上海手动 (2)', '上海手动']);
    expect(config['proxy-groups'][0]['filter'], isNull);
    expect(config['rules'], loadYaml(template)['rules']);
    expect(readManualNodeNames(result), ['上海手动 (2)', '上海手动']);
    expect(loadYaml(first)['proxies'][0]['http-opts']['headers']['Host'],
        ['link.example']);
    final tcp = loadYaml(addNodeLink(
        configured, linkFor({'net': 'tcp', 'type': 'none'})))['proxies'][0];
    expect(tcp['http-opts'], isNull);
    expect(tcp['ws-opts'], isNull);
  });
  test('local config retains policy and adds node to manual select groups', () {
    const local =
        'proxies: []\nproxy-groups: [{name: custom, type: select, proxies: [DIRECT]}]\nrules: [MATCH,custom]\n';
    final result = loadYaml(addNodeLink(local, linkFor({'ps': 'DIRECT'})));
    expect(result['proxy-groups'][0]['proxies'], ['DIRECT (2)', 'DIRECT']);
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
            [0];
    expect(added['type'], 'http');
    expect(added['server'], '10.0.0.200');
    expect(added['http-opts'], isNull);
    final config = loadYaml(addNodeLink(template, 'http://10.0.0.200/#wap'));
    expect(config['proxy-groups'][0]['proxies'], ['DIRECT', 'wap']);
    expect(config['proxy-groups'][1]['proxies'], ['wap']);
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
