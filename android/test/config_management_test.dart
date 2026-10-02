import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/config_management.dart';
import 'package:mclash/shared/subscription_filter.dart';
import 'package:mclash/shared/node_link.dart';
import 'package:yaml/yaml.dart';

const source = '''
# Mclash 国内正则: "北京"
proxies: [{name: 北京, type: http}, {name: JP, type: http}]
proxy-groups:
  - {name: 🚀 国内, type: select, proxies: [DIRECT, 北京]}
  - {name: 自选, type: select, proxies: [JP]}
rules: ['DOMAIN-SUFFIX,example.org,自选', 'MATCH,DIRECT']
''';

void main() {
  test('rules retain order and support complex rule policies', () {
    final rules = [
      'AND,((NETWORK,TCP),(DST-PORT,443)),自选',
      'IP-CIDR,1.1.1.0/24,REJECT,no-resolve',
      'MATCH,DIRECT'
    ];
    expect(configRules(updateConfigRules(source, rules)), rules);
    expect(
        () => updateConfigRules(source, ['MATCH,不存在']), throwsFormatException);
  });
  test('src options and sub-rule references survive group renaming', () {
    const rule = 'IP-CIDR,192.168.0.0/16,自选,no-resolve,src';
    final content = "${updateConfigRules(source, [
          rule,
          'MATCH,DIRECT'
        ])}sub-rules: {child: ['MATCH,自选']}\n";
    expect(rulePolicy(rule), '自选');
    final updated = updateConfigGroup(
        content,
        {
          'name': '新组',
          'type': 'select',
          'proxies': ['JP']
        },
        oldName: '自选');
    expect(
        configRules(updated).first, 'IP-CIDR,192.168.0.0/16,新组,no-resolve,src');
    expect(loadYaml(updated)['sub-rules']['child'], ['MATCH,新组']);
    expect(
        () => deleteConfigGroup(
            updateConfigRules(content, ['MATCH,DIRECT']), '自选'),
        throwsFormatException);
  });
  test('rename group rewrites rule, group and node references', () {
    final withReferences = source
        .replaceAll(
            'name: 北京, type: http', 'name: 北京, type: http, dialer-proxy: 自选')
        .replaceAll('proxies: [DIRECT, 北京]', 'proxies: [DIRECT, 自选]');
    final updated = updateConfigGroup(
        withReferences,
        {
          'name': '新组',
          'type': 'select',
          'proxies': ['JP']
        },
        oldName: '自选');
    final config = loadYaml(updated);
    expect(config['proxy-groups'][0]['proxies'], ['DIRECT', '新组']);
    expect(config['proxies'][0]['dialer-proxy'], '新组');
    expect(config['rules'][0], 'DOMAIN-SUFFIX,example.org,新组');
  });
  test('group deletion rejects references and succeeds after removing them',
      () {
    expect(() => deleteConfigGroup(source, '自选'), throwsFormatException);
    final updated =
        deleteConfigGroup(updateConfigRules(source, ['MATCH,DIRECT']), '自选');
    expect(configGroups(updated).map((group) => group['name']), ['🚀 国内']);
  });
  test('duplicate names and indirect cycles cannot be saved', () {
    expect(
        () => updateConfigGroup(source, {
              'name': 'JP',
              'type': 'select',
              'proxies': ['DIRECT']
            }),
        throwsFormatException);
    final updated = updateConfigGroup(source, {
      'name': '另一组',
      'type': 'select',
      'proxies': ['自选']
    });
    expect(
        () => updateConfigGroup(
            updated,
            {
              'name': '自选',
              'type': 'select',
              'proxies': ['另一组']
            },
            oldName: '自选'),
        throwsFormatException);
  });
  test('any group can use regex and manual selection cancels it', () {
    final filtered = editSubscriptionFilter(source, '自选', '^北');
    expect(loadYaml(filtered)['proxy-groups'][1]['proxies'], ['北京']);
    expect(readSubscriptionFilters(filtered)['自选'], '^北');
    final manual = updateConfigGroup(
        filtered,
        {
          'name': '🚀 国内',
          'type': 'select',
          'proxies': ['JP']
        },
        oldName: '🚀 国内');
    expect(readSubscriptionFilters(manual).containsKey('🚀 国内'), false);
    final reapplied =
        applySubscriptionFilters(manual, readSubscriptionFilters(manual));
    expect(loadYaml(reapplied)['proxy-groups'][0]['proxies'], ['JP']);
    expect(
        () => editSubscriptionFilter(source, '自选', '['), throwsFormatException);
  });
  test(
      'adding a node reapplies arbitrary filters without expanding manual groups',
      () {
    final manual = updateConfigGroup(
        source,
        {
          'name': '🚀 国内',
          'type': 'select',
          'proxies': ['JP']
        },
        oldName: '🚀 国内');
    final filtered = editSubscriptionFilter(manual, '自选', '');
    final result = addNodeLink(filtered, 'http://example.org:80#New');
    expect(loadYaml(result)['proxy-groups'][0]['proxies'], ['JP']);
    expect(loadYaml(result)['proxy-groups'][1]['proxies'], ['北京', 'JP', 'New']);
  });
}
