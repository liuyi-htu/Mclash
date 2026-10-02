import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/subscription_config.dart';
import 'package:mclash/subscription_filter.dart';
import 'package:mclash/subscription_host.dart';
import 'subscription_host_test.dart' show hostSource;
import 'package:yaml/yaml.dart';

void main() {
  final template = File('../../assets/default-config.yaml').readAsStringSync();
  const subscription = '''
proxies:
  - {name: 上海专线, type: ss, server: sh.example, port: 443, cipher: aes-128-gcm, password: "secret:#"}
  - {name: hk Premium, type: vmess, server: hk.example, port: 443, uuid: test, ws-opts: {headers: {Host: example.org}}}
  - {name: 美国, type: ss, server: us.example, port: 443, cipher: aes-128-gcm, password: secret}
rules: [MATCH,REJECT]
dns: {enable: false}
''';
  test(
      'refresh retains custom rules, manual groups, arbitrary filters and options',
      () {
    const previous = """
# Mclash 代理组正则: {"测速":"^JP"}
proxies: [{name: Old, type: http}, {name: Keep, type: http}]
proxy-groups:
  - {name: 手选, type: select, proxies: [Old, Keep]}
  - {name: 空组, type: select, proxies: [Old]}
  - {name: 测速, type: url-test, proxies: [Old], url: 'https://example.org', interval: 60, tolerance: 30}
  - {name: 总组, type: select, proxies: [手选, 测速]}
rules: ['DOMAIN-SUFFIX,example.org,总组', 'MATCH,DIRECT']
""";
    final text = buildSubscriptionConfig(template,
        'proxies: [{name: Keep, type: http}, {name: JP New, type: http}, {name: US New, type: http}]',
        previousConfig: previous);
    final config = loadYaml(text);
    expect(config['rules'], loadYaml(previous)['rules']);
    final groups = config['proxy-groups'];
    expect(groups.map((group) => group['name']).toList(),
        ['手选', '空组', '测速', '总组']);
    expect(groups[0]['proxies'], ['Keep']);
    expect(groups[1]['proxies'], ['DIRECT']);
    expect(groups[2]['proxies'], ['JP New']);
    expect(groups[2]['interval'], 60);
    expect(groups[2]['tolerance'], 30);
    expect(groups[3]['proxies'], ['手选', '测速']);
    expect(readSubscriptionFilters(text), {'测速': '^JP'});
  });
  test('manual regional groups do not resume regex matching on refresh', () {
    const previous =
        '# Mclash 代理组正则: {}\nproxies: [{name: Keep, type: http}]\nproxy-groups: [{name: 🚀 国内, type: select, proxies: [Keep]}]\nrules: ["MATCH,🚀 国内"]';
    final config = loadYaml(buildSubscriptionConfig(template,
        'proxies: [{name: Keep, type: http}, {name: New, type: http}]',
        previousConfig: previous));
    expect(config['proxy-groups'][0]['proxies'], ['Keep']);
  });
  test('refresh rejects a missing node still referenced by a rule', () {
    const previous =
        "# Mclash 代理组正则: {}\nproxies: [{name: Old, type: http}]\nproxy-groups: [{name: Custom, type: select, proxies: [Old]}]\nrules: ['IP-CIDR,1.1.1.0/24,Old,no-resolve,src']";
    expect(
        () => buildSubscriptionConfig(
            template, 'proxies: [{name: New, type: http}]',
            previousConfig: previous),
        throwsA(isA<FormatException>()
            .having((error) => error.message, 'message', contains('仍被规则引用'))));
  });
  test('refresh preserves all manual fields despite Host and chain overrides',
      () {
    const previous =
        '# Mclash 手动节点: ["Manual"]\n# Mclash HTTP/WS Host: "preset.example"\n# Mclash 节点链路: {"Manual":"KR New"}\nproxies: [{name: Manual, type: vmess, server: manual.example, port: 443, uuid: test, network: ws, dialer-proxy: KR, ws-opts: {headers: {Host: custom.example}}, udp: true}, {name: KR, type: http, server: old.example, port: 80}]\nproxy-groups: [{name: 🚀 国内, type: select, proxies: [DIRECT]}, {name: 🌍 国外, type: select, proxies: [KR]}]';
    const incoming =
        'proxies: [{name: Manual, type: http, server: overwritten.example, port: 80}, {name: KR, type: http, server: updated.example, port: 80}, {name: KR New, type: http, server: new.example, port: 80}]';
    final config = loadYaml(
        buildSubscriptionConfig(template, incoming, previousConfig: previous));
    final manual =
        config['proxies'].firstWhere((node) => node['name'] == 'Manual');
    expect(manual, loadYaml(previous)['proxies'][0]);
    expect(
        config['proxies'].firstWhere((node) => node['name'] == 'KR')['server'],
        'updated.example');
  });
  test('embeds full nodes and keeps default routing and regional groups', () {
    final original = loadYaml(template);
    final result = buildSubscriptionConfig(template, subscription);
    final config = loadYaml(result);
    expect(config['proxy-providers'], isNull);
    expect(config['proxies'], loadYaml(subscription)['proxies']);
    expect(config['rules'], original['rules']);
    expect(config['dns'], original['dns']);
    expect(config['proxy-groups'][0]['proxies'],
        ['DIRECT', '上海专线', 'hk Premium', '美国']);
    expect(config['proxy-groups'][1]['proxies'], ['上海专线', 'hk Premium', '美国']);
    expect(readSubscriptionFilter(result, domesticGroup), isEmpty);
    expect(readSubscriptionFilter(result, foreignGroup), isEmpty);
    for (final group in config['proxy-groups']) {
      expect(group['use'], isNull);
      expect(group['include-all-proxies'], isNull);
      expect(group['filter'], isNull);
    }
    expect(result, isNot(contains('token=')));
  });
  test('unmatched regions retain usable DIRECT fallback', () {
    final config = loadYaml(editSubscriptionFilter(
        buildSubscriptionConfig(
            template, 'proxies: [{name: 美国, type: ss, server: us.example}]'),
        foreignGroup,
        'KR'));
    expect(config['proxy-groups'][1]['proxies'], ['DIRECT']);
  });
  test('refresh retains customized and blank filters from the subscription',
      () {
    final previous = editSubscriptionFilter(
        editSubscriptionFilter(buildSubscriptionConfig(template, subscription),
            domesticGroup, '广州'),
        foreignGroup,
        '');
    final config = loadYaml(buildSubscriptionConfig(template, subscription,
        previousConfig: previous));
    expect(
        readSubscriptionFilter(
            buildSubscriptionConfig(template, subscription,
                previousConfig: previous),
            domesticGroup),
        '广州');
    expect(config['proxy-groups'][1]['proxies'].length, 3);
    expect(config['proxy-groups'][0]['filter'], isNull);
  });
  test('refresh retains Host override and applies it only to VMess HTTP/WS',
      () {
    final previous = editSubscriptionHost(
        buildSubscriptionConfig(template, hostSource), 'new.example');
    final refreshed =
        buildSubscriptionConfig(template, hostSource, previousConfig: previous);
    final nodes = loadYaml(refreshed)['proxies'];
    expect(nodes[0]['http-opts']['headers']['Host'], ['new.example']);
    expect(nodes[1]['ws-opts']['headers']['Host'], 'new.example');
    expect(nodes[2]['ws-opts']['headers']['Host'], 'new.example');
    expect(nodes[3], loadYaml(hostSource)['proxies'][3]);
    expect(nodes[4], loadYaml(hostSource)['proxies'][4]);
    expect(readSubscriptionHost(refreshed), 'new.example');
  });
  test('rejects empty, provider-only, malformed and conflicting nodes', () {
    for (final source in [
      'proxies: []',
      'proxy-providers: {airport: {type: http}}',
      'proxies: [bad]',
      'proxies: [{name: DIRECT, type: ss}]',
      'proxies: [{name: duplicate, type: ss}, {name: duplicate, type: ss}]',
      'proxies: [',
    ]) {
      expect(() => buildSubscriptionConfig(template, source),
          throwsA(isA<Exception>()));
    }
  });
}
