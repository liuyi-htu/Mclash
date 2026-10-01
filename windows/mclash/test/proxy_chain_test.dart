import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:mclash/proxy_chain.dart';
import 'package:mclash/subscription_config.dart';

const source = '''
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
}
