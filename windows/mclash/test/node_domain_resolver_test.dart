import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/node_domain_resolver.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
      'deduplicates DNS, prefers IPv4, preserves explicit and implicit identities',
      () async {
    const source = '''proxies:
- {name: A, type: vmess, server: node.example, tls: true, network: ws}
- {name: B, type: trojan, server: node.example, sni: custom.example, network: ws, ws-opts: {headers: {Host: custom.example}}}
- {name: IP, type: http, server: 192.0.2.3}
- {name: Failed, type: http, server: fail.example}
''';
    final calls = <String>[];
    final result = await resolveNodeDomains(source, lookup: (host) async {
      calls.add(host);
      if (host == 'fail.example') throw const SocketException('offline');
      return [InternetAddress('2001:db8::1'), InternetAddress('192.0.2.1')];
    });
    final nodes = loadYaml(result)['proxies'] as List;
    expect(nodes[0]['server'], '192.0.2.1');
    expect(nodes[0]['servername'], 'node.example');
    expect(nodes[0]['ws-opts']['headers']['Host'], 'node.example');
    expect(nodes[1]['sni'], 'custom.example');
    expect(nodes[1]['ws-opts']['headers']['Host'], 'custom.example');
    expect(nodes[2]['server'], '192.0.2.3');
    expect(nodes[3]['server'], 'fail.example');
    expect(calls.where((host) => host == 'node.example'), hasLength(1));
    expect(calls, isNot(contains('192.0.2.3')));
  });
  test('failed DNS retains original and IPv6 only DNS preserves SNI', () async {
    const source =
        'proxies: [{name: A, type: http, server: node.example, tls: true}]';
    expect(
        await resolveNodeDomains(source,
            lookup: (_) async => throw const SocketException('offline')),
        source);
    final result = await resolveNodeDomains(source,
        lookup: (_) async => [InternetAddress('2001:db8::1')]);
    final node = loadYaml(result)['proxies'][0];
    expect(node['server'], '2001:db8::1');
    expect(node['sni'], 'node.example');
  });
}
