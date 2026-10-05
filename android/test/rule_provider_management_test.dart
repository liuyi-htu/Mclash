import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/rule_provider_management.dart';
import 'package:mclash/shared/config_management.dart';
import 'package:yaml/yaml.dart';

const source = '''
# keep this comment
proxies: []
proxy-groups: []
rule-providers:
  old:
    type: http
    url: https://example.org/rules.yaml
    behavior: domain
    header: {User-Agent: [custom]}
rules: ['RULE-SET,old,DIRECT', 'DOMAIN,old,DIRECT', 'AND,((RULE-SET,old),(NETWORK,TCP)),DIRECT']
sub-rules: {child: ['RULE-SET,old,REJECT']}
''';
void main() {
  test('provider rename updates direct, nested and sub-rule references', () {
    final provider = configRuleProviders(source)['old']!;
    final next =
        updateConfigRuleProvider(source, 'new', provider, oldName: 'old');
    final config = loadYaml(next) as Map;
    expect(configRuleProviders(next).keys, ['new']);
    expect(configRuleProviders(next)['new']!['header'], provider['header']);
    expect(config['rules'], [
      'RULE-SET,new,DIRECT',
      'DOMAIN,old,DIRECT',
      'AND,((RULE-SET,new),(NETWORK,TCP)),DIRECT'
    ]);
    expect(config['sub-rules']['child'], ['RULE-SET,new,REJECT']);
    expect(next, contains('# keep this comment'));
    expect(() => deleteConfigRuleProvider(next, 'new'), throwsFormatException);
  });
  test(
      'add and delete preserve other configuration and reject invalid providers',
      () {
    const empty = 'rules: [MATCH,DIRECT]\n';
    const provider = {
      'type': 'inline',
      'behavior': 'classical',
      'payload': ['DOMAIN,example.org']
    };
    final next = updateConfigRuleProvider(empty, 'local', provider);
    expect(configRuleProviders(next)['local']!['payload'], provider['payload']);
    expect(
        configRuleProviders(deleteConfigRuleProvider(next, 'local')), isEmpty);
    for (final invalid in [
      {...provider, 'payload': <String>[]},
      {...provider, 'format': 'mrs'},
      {'type': 'http', 'behavior': 'domain', 'url': 'invalid'},
      {'type': 'file', 'behavior': 'domain'},
    ]) {
      expect(() => updateConfigRuleProvider(empty, 'bad', invalid),
          throwsFormatException);
    }
    expect(() => updateConfigRuleProvider(next, 'local', provider),
        throwsFormatException);
    expect(loadYaml(next)['rules'], loadYaml(empty)['rules']);
  });
  test(
      'ruleset entry always immediately precedes rules regardless of YAML order',
      () {
    for (final content in [
      '',
      source,
      'rules: []\nrule-providers: {}\nproxies: []\n'
    ]) {
      final actions = configActionOrder(content);
      expect(actions.indexOf('ruleProviders') + 1, actions.indexOf('rules'));
    }
  });
}
