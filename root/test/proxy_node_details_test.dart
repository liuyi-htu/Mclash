import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/proxy_node_details.dart';

void main() {
  test('resolves nested selections and orders multiple dialers before exit',
      () {
    final details = ProxyNodeDetails('选择组', {
      '选择组': {'now': '出口组'},
      '出口组': {'now': '出口'},
      '出口': {'type': 'VMess', 'dialer-proxy': '前置组'},
      '前置组': {'now': '前置二'},
      '前置二': {'dialer-proxy': '前置一'},
      '前置一': {'type': 'Socks5'},
    });
    expect(details.name, '出口');
    expect(details.selectionPath, ['选择组', '出口组', '出口']);
    expect(details.chain, ['前置一', '前置二', '出口']);
    expect(details.incomplete, isFalse);
  });

  test('direct nodes and unavailable details remain readable', () {
    final details = ProxyNodeDetails('DIRECT', {});
    expect(details.name, 'DIRECT');
    expect(details.chain, ['DIRECT']);
    expect(details.info, isEmpty);
  });

  test('cycles in selection or dialers cannot hang the panel', () {
    expect(
        ProxyNodeDetails('A', {
          'A': {'now': 'B'},
          'B': {'now': 'A'},
        }).incomplete,
        isTrue);
    final details = ProxyNodeDetails('A', {
      'A': {'dialer-proxy': 'B'},
      'B': {'dialer-proxy': 'A'},
    });
    expect(details.incomplete, isTrue);
    expect(details.chain, ['B', 'A']);
  });

  test('runtime YAML supplies chain data and tolerates unavailable config', () {
    final nodes = runtimeProxyDetails('''
proxies:
  - {name: 出口, type: vmess, server: exit.example, port: 443, dialer-proxy: 入口}
  - {name: 入口, type: http}
''');
    expect(ProxyNodeDetails('出口', nodes).chain, ['入口', '出口']);
    expect(nodes['出口']!['server'], 'exit.example');
    expect(runtimeProxyDetails(''), isEmpty);
    expect(runtimeProxyDetails('proxies: ['), isEmpty);
  });
}
