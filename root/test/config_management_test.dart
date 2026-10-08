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
  test('DIRECT preference survives matching, rename and delete', () {
    final enabled = updateConfigGroup(source, {'name': '自选', 'type': 'select'},
        oldName: '自选', filter: '^JP', includeDirect: true);
    expect(configGroups(enabled)[1]['proxies'], ['DIRECT', 'JP']);
    final disabled = updateConfigGroup(
        enabled, {'name': '更名', 'type': 'select'},
        oldName: '自选', filter: '^北', includeDirect: false);
    expect(configGroups(disabled)[1]['proxies'], ['北京']);
    expect(readGroupDirectOptions(disabled), {'更名': false});
    final refreshed = addNodeLink(disabled, 'http://example.org:80#北京2');
    expect(configGroups(refreshed)[1]['proxies'], ['北京2', '北京']);
    expect(() => editSubscriptionFilter(disabled, '更名', r'^missing$'),
        throwsFormatException);
    final deleted =
        deleteConfigGroup(updateConfigRules(disabled, ['MATCH,DIRECT']), '更名');
    expect(readGroupDirectOptions(deleted), isEmpty);
  });

  test('group reordering preserves settings, metadata and references', () {
    final content = '# Mclash 链路代理组: {"链路":["JP"]}\n'
        '# Mclash 代理组正则: {"自选":"^JP"}\n'
        '${source.replaceFirst('rules:', '  - {name: 链路, type: select, proxies: [JP], hidden: true}\nrules:')}'
        'sub-rules: {child: ["MATCH,自选"]}\n';
    final before = loadYaml(content);
    final reordered = reorderConfigGroups(content, ['链路', '自选', '🚀 国内']);
    expect(configGroups(reordered), [
      configGroups(content)[2],
      configGroups(content)[1],
      configGroups(content)[0]
    ]);
    final after = loadYaml(reordered);
    for (final key in ['proxies', 'rules', 'sub-rules']) {
      expect(after[key], before[key]);
    }
    expect(reordered, contains('# Mclash 链路代理组: {"链路":["JP"]}'));
    expect(
        readSubscriptionFilters(reordered), readSubscriptionFilters(content));
    expect(
        configGroups(editSubscriptionFilter(reordered, '自选', '^北'))
            .map((group) => group['name']),
        ['链路', '自选', '🚀 国内']);
    expect(configGroups(reorderConfigGroups(reordered, ['🚀 国内', '自选', '链路'])),
        configGroups(content));
  });

  test('group reordering rejects missing, repeated and unknown names', () {
    for (final names in [
      ['自选'],
      ['自选', '自选'],
      ['自选', '不存在']
    ]) {
      expect(() => reorderConfigGroups(source, names), throwsFormatException);
    }
  });

  test(
      'runtime metadata follows menu order and groups numbered chains by direction',
      () {
    const settings =
        '# Mclash 链路设置: {"1":{"back":["A"]},"2":{"front":["B"]},"3":{"back":["C"]}}';
    const headers = [
      '# Mclash 代理组正则: {"测速":"^JP"}',
      '# Mclash 节点链路 3: {"C":"JP"}',
      '# Mclash 节点链路 1: {"A":"JP"}',
      '# Mclash 链路代理组: {"Chain":["JP"]}',
      '# Mclash HTTP/WS Host: "gw.alicdn.com"',
      '# Mclash 节点链路 2: {"JP":"B"}',
      '# Mclash 手动节点: ["A"]',
    ];
    final nodeHeaders = [
      headers[6],
      headers[4],
      '# Mclash 链式节点 2: {"JP":"B"}',
      '# Mclash 后置链路 1: {"A":"JP"}',
      '# Mclash 后置链路 3: {"C":"JP"}'
    ];
    final groupHeaders = [headers[3], headers[0]];
    for (final groupsFirst in [false, true]) {
      final sections = groupsFirst
          ? 'proxy-groups: []\nproxies: []\nrules: []\n'
          : 'proxies: []\nproxy-groups: []\nrules: []\n';
      final runtime =
          '${headers.join('\n')}\n${sections}description: |\n  # Mclash HTTP/WS Host: literal text\n';
      final profile = '$settings\n$runtime';
      final result = orderRuntimeMetadata(runtime, profileContent: profile);
      expect(
          result.split('\n').where((line) => line.startsWith('# Mclash ')),
          groupsFirst
              ? [...groupHeaders, ...nodeHeaders]
              : [...nodeHeaders, ...groupHeaders]);
      expect(loadYaml(result), loadYaml(runtime));
      expect(orderRuntimeMetadata(result, profileContent: profile), result);
      expect(orderRuntimeMetadata(result), result);
    }
  });

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
  test('regional groups stay locked and allow regex and type edits', () {
    final content = source
        .replaceAll('name: 自选', 'name: 🌍 国外')
        .replaceAll('example.org,自选', 'example.org,🌍 国外');
    for (final name in ['🚀 国内', '🌍 国外']) {
      expect(
          () => deleteConfigGroup(content, name),
          throwsA(isA<FormatException>()
              .having((error) => error.message, 'message', contains('不可删除'))));
      expect(
          () => updateConfigGroup(
              content,
              {
                'name': '更名',
                'type': 'select',
                'proxies': ['JP']
              },
              oldName: name),
          throwsFormatException);
      final filtered = editSubscriptionFilter(content, name, '^JP');
      final edited = updateConfigGroup(
          filtered,
          {
            'name': name,
            'type': 'url-test',
            'proxies': configGroups(filtered)
                .firstWhere((group) => group['name'] == name)['proxies']
          },
          oldName: name);
      expect(readSubscriptionFilters(edited)[name], '^JP');
      expect(
          configGroups(edited)
              .firstWhere((group) => group['name'] == name)['type'],
          'url-test');
    }
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
    final cyclic = source
        .replaceAll('proxies: [JP]', 'proxies: [另一组]')
        .replaceAll(
            'rules:', '  - {name: 另一组, type: select, proxies: [自选]}\nrules:');
    expect(
        () => updateConfigGroup(
            cyclic,
            {
              'name': '自选',
              'type': 'select',
              'proxies': ['另一组']
            },
            oldName: '自选'),
        throwsFormatException);
  });
  test('group rename and regex edit save together', () {
    final edited = updateConfigGroup(
        source,
        {
          'name': '更名',
          'type': 'select',
          'proxies': ['JP']
        },
        oldName: '自选',
        filter: '^北');
    expect(readSubscriptionFilters(edited)['更名'], '^北');
    expect(readSubscriptionFilters(edited).containsKey('自选'), isFalse);
    expect(configGroups(edited)[1]['proxies'], ['北京']);
    expect(configRules(edited).first, contains('更名'));
  });

  test('members can only change through regex and group edits preserve filters',
      () {
    final filtered = editSubscriptionFilter(source, '自选', '^北');
    expect(loadYaml(filtered)['proxy-groups'][1]['proxies'], ['北京']);
    expect(
        () => updateConfigGroup(
            filtered,
            {
              'name': '自选',
              'type': 'select',
              'proxies': ['JP']
            },
            oldName: '自选'),
        throwsFormatException);
    final edited = updateConfigGroup(
        filtered,
        {
          'name': '更名',
          'type': 'select',
          'proxies': ['北京']
        },
        oldName: '自选');
    expect(readSubscriptionFilters(edited)['更名'], '^北');
    expect(edited, startsWith('# Mclash 代理组正则: '));
    expect(edited, isNot(contains('# Mclash 国内正则: ')));
    expect(edited, isNot(contains('# Mclash 代理组「自选」正则: ')));
    final deleted = deleteConfigGroup(
        edited.replaceAll('example.org,更名', 'example.org,DIRECT'), '更名');
    expect(deleted, isNot(contains('# Mclash 代理组「更名」正则: ')));
    expect(loadYaml(edited)['proxy-groups'][1]['proxies'], ['北京']);
    final created = updateConfigGroup(source, {'name': '新建', 'type': 'select'});
    expect(configGroups(created).last['proxies'], ['北京', 'JP']);
    expect(readSubscriptionFilters(created)['新建'], '');
    expect(created, contains('"新建":""'));
    expect(created.indexOf('# Mclash 代理组正则: '),
        lessThan(created.indexOf('proxies:')));
    expect(
        () => editSubscriptionFilter(source, '自选', '['), throwsFormatException);
  });

  test(
      'adding a node reapplies arbitrary filters without expanding manual groups',
      () {
    final manual =
        writeSubscriptionFilters(source.replaceAll('[DIRECT, 北京]', '[JP]'), {});
    final filtered = editSubscriptionFilter(manual, '自选', '');
    final result = addNodeLink(filtered, 'http://example.org:80#New');
    expect(loadYaml(result)['proxy-groups'][0]['proxies'], ['JP']);
    expect(loadYaml(result)['proxy-groups'][1]['proxies'], ['New', '北京', 'JP']);
  });
}
