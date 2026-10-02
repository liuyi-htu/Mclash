import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:mclash/proxy_chain.dart';
import 'package:mclash/subscription_config.dart';

const source = '''
# Mclash 国内正则: "上海"
# Mclash 国外正则: "KR"
proxies:
  - {name: 上海, type: vmess, server: first.example, uuid: 00000000-0000-4000-8000-000000000001}
  - {name: KR, type: http, server: second.example, port: 80}
  - {name: wap, type: http, server: 10.0.0.200, port: 80}
proxy-groups:
  - {name: 🚀 国内, type: select, proxies: [DIRECT, 上海]}
  - {name: 🌍 国外, type: select, proxies: [KR]}
rules: [MATCH,DIRECT]
''';

void main() {
  test('legacy front comments display the chain node name', () {
    const source = '# Mclash 前置链路 1: {"JP":"入口"}\nproxies: []\n';
    final runtime = runtimeProxyChainComments(source);
    expect(runtime, contains('# Mclash 链式节点 1: {"JP":"入口"}'));
    expect(runtime, isNot(contains('前置链路')));
    expect(runtimeProxyChainComments(runtime), runtime);
  });

  test(
      'legacy front and back metadata uses directional labels without changing YAML',
      () {
    final front =
        setGlobalProxyChain(source, ['wap'], prepend: true, targets: ['上海']);
    final both =
        setGlobalProxyChain(front, ['KR'], prepend: false, targets: ['上海']);
    final runtime = runtimeProxyChainComments(both);
    expect(runtime, contains('# Mclash 链式节点 1: {"上海":"wap"}'));
    expect(runtime, contains('# Mclash 后置链路 2: {"KR":"上海"}'));
    expect(runtime, isNot(contains('# Mclash 节点链路')));
    expect(loadYaml(runtime), loadYaml(both));
    expect(runtimeProxyChainComments(runtime), runtime);
  });

  test(
      'multiple front and back sets remain independent across refresh and clearing',
      () {
    final expanded = source.replaceFirst('proxy-groups:',
        '  - {name: US, type: http}\n  - {name: front2, type: http}\n  - {name: back1, type: http}\nproxy-groups:');
    final first = setProxyChainSet(expanded, '1', ['wap'],
        prepend: true, targets: ['上海']);
    final second = setProxyChainSet(first, '2', ['front2'],
        prepend: true, targets: ['KR']);
    final third = setProxyChainSet(second, '3', ['back1'],
        prepend: false, targets: ['US']);
    expect(readProxyChainSets(third).keys, ['1', '2', '3']);
    expect(
        readProxyChains(third), {'上海': 'wap', 'KR': 'front2', 'back1': 'US'});
    expect(third, contains('# Mclash 链式节点 1: {"上海":"wap"}'));
    expect(third, contains('# Mclash 链式节点 2: {"KR":"front2"}'));
    expect(third, contains('# Mclash 后置链路 3: {"back1":"US"}'));
    final refreshed = applySavedProxyChains(expanded, third);
    expect(readProxyChains(refreshed), readProxyChains(third));
    final cleared =
        setProxyChainSet(refreshed, '2', [], prepend: true, targets: []);
    expect(readProxyChainSets(cleared).keys, ['1', '3']);
    expect(readProxyChains(cleared), {'上海': 'wap', 'back1': 'US'});
    expect(loadYaml(cleared)['proxies'][1]['dialer-proxy'], isNull);
  });

  test(
      'multi-set migration retains selected targets and rejects conflicting routes',
      () {
    final legacy =
        setGlobalProxyChain(source, ['wap'], prepend: true, targets: ['上海']);
    final converted =
        setProxyChainSet(legacy, '2', ['wap'], prepend: true, targets: ['KR']);
    expect(readProxyChains(converted), {'上海': 'wap', 'KR': 'wap'});
    expect(converted, isNot(contains('# Mclash 全局链路: ')));
    expect(
        () => setProxyChainSet(converted, '3', ['wap'],
            prepend: false, targets: ['上海']),
        throwsFormatException);
    final expanded = source.replaceFirst(
        'proxy-groups:', '  - {name: second, type: http}\nproxy-groups:');
    final first = setProxyChainSet(expanded, '1', ['wap'],
        prepend: true, targets: ['上海']);
    expect(
        () => setProxyChainSet(first, '2', ['second'],
            prepend: true, targets: ['上海']),
        throwsFormatException);
  });

  test('multiple back sets have separate entry groups and prune deleted nodes',
      () {
    final expanded = source.replaceFirst('proxy-groups:',
        '  - {name: US, type: http}\n  - {name: back2, type: http}\nproxy-groups:');
    final first = setProxyChainSet(expanded, '1', ['wap'],
        prepend: false, targets: ['上海', 'KR']);
    final second = setProxyChainSet(first, '2', ['back2'],
        prepend: false, targets: ['US']);
    expect(readProxyChains(second)['wap'], '🔗 后置入口 (链路 1)');
    expect(readProxyChainGroups(second), {
      '🔗 后置入口 (链路 1)': ['上海', 'KR']
    });
    final deleted = removeProxyChainNode(second, 'US');
    expect(readProxyChainSets(deleted)['2']!['backTargets'], isEmpty);
    expect(readProxyChains(deleted).containsKey('back2'), isFalse);
    expect(readProxyChains(deleted)['wap'], '🔗 后置入口 (链路 1)');
  });

  for (final prepend in [true, false]) {
    test(
        'selected targets stay limited after refresh, edits and deletion ($prepend)',
        () {
      final saved = setGlobalProxyChain(source, ['wap'],
          prepend: prepend, targets: ['上海']);
      expect(readProxyChainTargets(saved, prepend: prepend), ['上海']);
      final refreshed = source.replaceFirst(
          '  - {name: wap', '  - {name: New, type: http}\n  - {name: wap');
      final restored = loadYaml(applySavedProxyChains(refreshed, saved));
      expect(restored['proxies'][1]['dialer-proxy'], isNull);
      expect(restored['proxies'][2]['dialer-proxy'], isNull);
      if (prepend) {
        expect(restored['proxies'][0]['dialer-proxy'], 'wap');
      } else {
        expect(restored['proxies'][3]['dialer-proxy'], '上海');
      }
      final edited = setGlobalProxyChain(saved, ['wap'],
          prepend: prepend, targets: ['KR']);
      expect(readProxyChainTargets(edited, prepend: prepend), ['KR']);
      if (prepend) {
        expect(loadYaml(edited)['proxies'][0]['dialer-proxy'], isNull);
      }
      final deleted = removeProxyChainNode(saved, '上海');
      expect(readProxyChainTargets(deleted, prepend: prepend), isEmpty);
      expect(
          readGlobalProxyChains(
              deleted)[prepend ? 'frontTargets' : 'backTargets'],
          isEmpty);
      final cleared = loadYaml(applySavedProxyChains(refreshed, deleted));
      expect(cleared['proxies'].every((node) => node['dialer-proxy'] == null),
          isTrue);
      expect(
          () => setGlobalProxyChain(source, ['wap'],
              prepend: prepend, targets: []),
          throwsFormatException);
    });
  }

  test('global front proxies follow saved order serially across refresh', () {
    final chained = setGlobalProxyChain(source, ['wap', 'KR'],
        prepend: true, targets: ['上海']);
    final yaml = loadYaml(chained);
    expect(yaml['proxies'][0]['dialer-proxy'], 'KR');
    expect(yaml['proxies'][1]['dialer-proxy'], 'wap');
    expect(yaml['proxies'][2]['dialer-proxy'], isNull);
    expect(readProxyChainGroups(chained), isEmpty);
    final refreshed = loadYaml(applySavedProxyChains(source, chained));
    expect(refreshed['proxies'][0]['dialer-proxy'], 'KR');
    expect(refreshed['proxies'][1]['dialer-proxy'], 'wap');
    final reordered = setGlobalProxyChain(chained, ['KR', 'wap'],
        prepend: true, targets: ['上海']);
    final changed = loadYaml(reordered);
    expect(changed['proxies'][0]['dialer-proxy'], 'wap');
    expect(changed['proxies'][2]['dialer-proxy'], 'KR');
    expect(changed['proxies'][1]['dialer-proxy'], isNull);
    expect(readGlobalProxyChains(reordered)['front'], ['KR', 'wap']);
  });

  test(
      'front and back apply only to explicitly selected targets across refresh',
      () {
    final front = setGlobalProxyChain(source, ['wap'],
        prepend: true, targets: ['上海', 'KR']);
    expect(loadYaml(front)['proxies'][0]['dialer-proxy'], 'wap');
    expect(loadYaml(front)['proxies'][1]['dialer-proxy'], 'wap');
    final both =
        setGlobalProxyChain(front, ['KR'], prepend: false, targets: ['上海']);
    final yaml = loadYaml(both);
    expect(yaml['proxies'][0]['dialer-proxy'], 'wap');
    expect(yaml['proxies'][1]['dialer-proxy'], '上海');
    expect(yaml['proxies'][2]['dialer-proxy'], isNull);
    final refreshed = source.replaceFirst('  - {name: wap',
        '  - {name: New, type: http, server: new.example, port: 80}\n  - {name: wap');
    final restored = loadYaml(applySavedProxyChains(refreshed, both));
    expect(restored['proxies'][2]['dialer-proxy'], isNull);
    expect(restored['proxies'][1]['dialer-proxy'], '上海');
    expect(
        () =>
            setGlobalProxyChain(both, ['wap'], prepend: false, targets: ['上海']),
        throwsFormatException);
  });

  test(
      'prepend sets dialer on current exit, append sets it on the selected post proxy',
      () {
    final before = loadYaml(source);
    final pre = loadYaml(setProxyChain(source, '上海', 'wap', prepend: true));
    expect(pre['proxies'][0]['dialer-proxy'], 'wap');
    expect(pre['proxies'][2]['dialer-proxy'], isNull);
    final post = loadYaml(setProxyChain(source, '上海', 'KR', prepend: false));
    expect(post['proxies'][0]['dialer-proxy'], isNull);
    expect(post['proxies'][1]['dialer-proxy'], '上海');
    expect(post['proxy-groups'], before['proxy-groups']);
    expect(post['rules'], before['rules']);
  });
  test('combines front and back proxies without changing other node fields',
      () {
    final pre = setProxyChain(source, '上海', 'wap', prepend: true);
    final both = setProxyChain(pre, '上海', 'KR', prepend: false);
    expect(loadYaml(both)['proxies'][0]['dialer-proxy'], 'wap');
    expect(loadYaml(both)['proxies'][1]['dialer-proxy'], '上海');
    expect(readProxyChains(both), {'上海': 'wap', 'KR': '上海'});
    expect(loadYaml(both)['proxies'][0]['server'], 'first.example');
    expect(() => setProxyChain(both, 'wap', 'KR', prepend: true),
        throwsFormatException);
    expect(() => setProxyChain(source, '上海', '上海', prepend: true),
        throwsFormatException);
    expect(() => setProxyChain(source, '上海', 'missing', prepend: false),
        throwsFormatException);
  });
  test('restores saved chains on refreshed nodes and skips missing upstreams',
      () {
    final previous = setProxyChain(source, '上海', 'wap', prepend: true);
    expect(
        loadYaml(applySavedProxyChains(source, previous))['proxies'][0]
            ['dialer-proxy'],
        'wap');
    final missing =
        applySavedProxyChains('proxies: [{name: 上海, type: vmess}]', previous);
    expect(loadYaml(missing)['proxies'][0]['dialer-proxy'], isNull);
    expect(readProxyChains(missing), {'上海': 'wap'});
  });
  test('subscription refresh keeps saved chains and existing regional groups',
      () {
    final previous = setProxyChain(source, '上海', 'wap', prepend: true);
    final refreshed = loadYaml(
        buildSubscriptionConfig(source, source, previousConfig: previous));
    expect(refreshed['proxies'][0]['dialer-proxy'], 'wap');
    expect(refreshed['proxy-groups'][0]['proxies'], ['DIRECT', '上海']);
    expect(refreshed['proxy-groups'][1]['proxies'], ['KR']);
  });
  test(
      'batch chains use a select group for multiple upstreams and preserve routing',
      () {
    const multiple =
        "proxies: [{name: A, type: http}, {name: B, type: http}, {name: C, type: http}, {name: D, type: http}]\nproxy-groups: [{name: Existing, type: select, proxies: [A, B]}]\nrules: ['MATCH,Existing']\n";
    final front =
        setProxyChains(multiple, ['A', 'B'], ['C', 'D'], prepend: true);
    final pre = loadYaml(front);
    final group = pre['proxies'][0]['dialer-proxy'];
    expect(pre['proxies'][1]['dialer-proxy'], group);
    expect(pre['proxy-groups'][1]['proxies'], ['C', 'D']);
    expect(pre['proxy-groups'][0], loadYaml(multiple)['proxy-groups'][0]);
    expect(readProxyChainGroups(front)[group], ['C', 'D']);
    final restored = loadYaml(applySavedProxyChains(multiple, front));
    expect(restored['proxies'][0]['dialer-proxy'], group);
    expect(restored['proxy-groups'][1]['proxies'], ['C', 'D']);
    final post = loadYaml(
        setProxyChains(multiple, ['A', 'B'], ['C', 'D'], prepend: false));
    expect(
        post['proxies'][2]['dialer-proxy'], post['proxies'][3]['dialer-proxy']);
    expect(post['proxy-groups'][1]['proxies'], ['A', 'B']);
    expect(() => setProxyChains(front, ['C'], ['A'], prepend: true),
        throwsFormatException);
    expect(
        () => setProxyChains(multiple, ['A', 'B'], ['B', 'C'], prepend: true),
        throwsFormatException);
    expect(() => setProxyChains(multiple, [], ['B'], prepend: true),
        throwsFormatException);
  });
}
