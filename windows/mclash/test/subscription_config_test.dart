import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/subscription_config.dart';
import 'package:mclash/subscription_filter.dart';
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
  test('embeds full nodes and keeps default routing and regional groups', () {
    final original = loadYaml(template);
    final result = buildSubscriptionConfig(template, subscription);
    final config = loadYaml(result);
    expect(config['proxy-providers'], isNull);
    expect(config['proxies'], loadYaml(subscription)['proxies']);
    expect(config['rules'], original['rules']);
    expect(config['dns'], original['dns']);
    expect(config['proxy-groups'][0]['proxies'], ['DIRECT', '上海专线']);
    expect(config['proxy-groups'][1]['proxies'], ['DIRECT']);
    for (final group in config['proxy-groups']) {
      expect(group['use'], isNull);
      expect(group['include-all-proxies'], isNull);
      expect(group['filter'], isNull);
    }
    expect(result, isNot(contains('token=')));
  });
  test('unmatched regions retain usable DIRECT fallback', () {
    final config = loadYaml(buildSubscriptionConfig(
        template, 'proxies: [{name: 美国, type: ss, server: us.example}]'));
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
