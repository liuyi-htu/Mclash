import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:mclash/shared/subscription_host.dart';

const hostSource = """
proxies:
  - {name: KR-http, type: vmess, network: http, server: origin.example, servername: tls.example, http-opts: {path: [/abc], headers: {host: [old.example], X-Test: [keep]}}}
  - {name: KR-ws, type: vmess, network: ws, ws-opts: {path: /ws, headers: {Host: old.example, X-Test: keep}}}
  - {name: KR-new, type: vmess, network: ws}
  - {name: KR-vless, type: vless, network: ws, ws-opts: {headers: {Host: original.example}}}
  - {name: KR-h2, type: vmess, network: h2, h2-opts: {host: [original.example]}}
  - {name: KR-tcp, type: vmess, network: tcp}
proxy-groups:
  - {name: 🚀 国内, type: select, proxies: [DIRECT]}
  - {name: 🌍 国外, type: select, proxies: [KR-http, KR-ws]}
rules: [MATCH,DIRECT]
""";

void main() {
  test('Host edit changes only VMess HTTP and WS while retaining other fields',
      () {
    final edited = editSubscriptionHost(hostSource, 'new.example:8080');
    final original = loadYaml(hostSource);
    final config = loadYaml(edited);
    final nodes = config['proxies'];
    expect(nodes[0]['http-opts']['headers']['Host'], ['new.example:8080']);
    expect(nodes[0]['http-opts']['headers']['host'], isNull);
    expect(nodes[0]['http-opts']['headers']['X-Test'], ['keep']);
    expect(nodes[0]['http-opts']['path'], ['/abc']);
    expect(nodes[0]['server'], 'origin.example');
    expect(nodes[0]['servername'], 'tls.example');
    expect(nodes[1]['ws-opts']['headers']['Host'], 'new.example:8080');
    expect(nodes[1]['ws-opts']['path'], '/ws');
    expect(nodes[1]['ws-opts']['headers']['X-Test'], 'keep');
    expect(nodes[2]['ws-opts']['headers']['Host'], 'new.example:8080');
    for (var i = 3; i < nodes.length; i++) {
      expect(nodes[i], original['proxies'][i]);
    }
    expect(config['proxy-groups'], original['proxy-groups']);
    expect(config['rules'], original['rules']);
    expect(readSubscriptionHost(edited), 'new.example:8080');
    expect(readSubscriptionHost(editSubscriptionHost(edited, 'second.example')),
        'second.example');
  });
  test('rejects empty hosts, URLs and header injection', () {
    for (final host in [
      '',
      'http://example.com',
      'example.com/path',
      'example.com\r\nX-Test: bad'
    ]) {
      expect(
          () => editSubscriptionHost(hostSource, host), throwsFormatException);
    }
  });
}
