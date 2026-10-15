import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:mclash/node_link.dart';
import 'package:mclash/subscription_host.dart';

const uuid = '00000000-0000-4000-8000-000000000001';
String encoded(String text) =>
    base64Url.encode(utf8.encode(text)).replaceAll('=', '');

void main() {
  test('VLESS Reality Vision retains authentication and TLS settings', () {
    final key =
        base64Url.encode(List.generate(32, (i) => i)).replaceAll('=', '');
    final node = parseNodeLink(
        'vless://$uuid@example.org:443?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&sni=cdn.example&fp=chrome&pbk=$key&sid=ab12&spx=%2F&alpn=h2%2Chttp%2F1.1#%E9%A6%99%E6%B8%AF');
    expect(node['name'], '香港');
    expect(node['uuid'], uuid);
    expect(node['tls'], true);
    expect(node['flow'], 'xtls-rprx-vision');
    expect(node['servername'], 'cdn.example');
    expect(node['client-fingerprint'], 'chrome');
    expect(node['reality-opts'], {'public-key': key, 'short-id': 'ab12'});
    expect(node['alpn'], ['h2', 'http/1.1']);
    final padded = parseNodeLink(
        'vless://$uuid@example.org?security=reality&pbk=${Uri.encodeComponent('$key=')}');
    expect(padded['reality-opts']['public-key'], key);
  });

  test('VLESS transports retain host, path and service name', () {
    final ws = parseNodeLink(
        'vless://$uuid@example.org:80?type=ws&host=cdn.example&path=%2Fws%3Fed%3D2048&ed=2048&eh=Sec-WebSocket-Protocol');
    expect(ws['tls'], false);
    expect(ws['ws-opts']['headers'], {'Host': 'cdn.example'});
    expect(ws['ws-opts']['path'], '/ws?ed=2048');
    expect(ws['ws-opts']['max-early-data'], 2048);
    final grpc = parseNodeLink(
        'vless://$uuid@example.org?security=tls&type=grpc&serviceName=my-service&packetEncoding=xudp');
    expect(grpc['grpc-opts'], {'grpc-service-name': 'my-service'});
    expect(grpc['packet-encoding'], 'xudp');
    final http = parseNodeLink(
        'vless://$uuid@example.org?type=tcp&headerType=http&host=a.example,b.example&path=%2Fa,%2Fb');
    expect(http['network'], 'http');
    expect(http['http-opts']['headers']['Host'], ['a.example', 'b.example']);
    expect(http['http-opts']['path'], ['/a', '/b']);
    final h2 = parseNodeLink(
        'vless://$uuid@example.org?security=tls&type=h2&host=cdn.example&path=%2Fh2');
    expect(h2['h2-opts'], {
      'host': ['cdn.example'],
      'path': '/h2'
    });
    final xhttp = parseNodeLink(
        'vless://$uuid@example.org?security=tls&type=xhttp&mode=stream-up&host=cdn.example&path=%2Fxhttp');
    expect(xhttp['xhttp-opts'],
        {'host': 'cdn.example', 'path': '/xhttp', 'mode': 'stream-up'});
  });

  test('Trojan and AnyTLS preserve encoded passwords and secure defaults', () {
    final trojan = parseNodeLink(
        'trojan://p%40ss%3Aword@example.org?type=ws&host=cdn.example&path=%2Fws&peer=tls.example&allowInsecure=0#Trojan');
    expect(trojan['password'], 'p@ss:word');
    expect(trojan['sni'], 'tls.example');
    expect(trojan['skip-cert-verify'], false);
    expect(trojan['ws-opts']['path'], '/ws');
    final any = parseNodeLink(
        'anytls://p%2Bss@example.org?security=tls&type=tcp&sni=tls.example&fp=chrome&insecure=true');
    expect(any['type'], 'anytls');
    expect(any['password'], 'p+ss');
    expect(any['sni'], 'tls.example');
    expect(any['skip-cert-verify'], true);
  });

  test('SS accepts SIP002, legacy Base64 and plaintext SS2022 credentials', () {
    for (final link in [
      'ss://${encoded('aes-128-gcm:p@ss:word')}@example.org:8388#SS',
      'ss://${encoded('aes-128-gcm:p@ss:word@example.org:8388')}#SS',
      'ss://aes-128-gcm:p%40ss%3Aword@example.org:8388/#SS',
    ]) {
      final node = parseNodeLink(link);
      expect(node['type'], 'ss');
      expect(node['server'], 'example.org');
      expect(node['port'], 8388);
      expect(node['cipher'], 'aes-128-gcm');
      expect(node['password'], 'p@ss:word');
      expect(node['name'], 'SS');
    }
    final key = base64.encode(List.filled(16, 1));
    final ss2022 = parseNodeLink(
        'ss://2022-blake3-aes-128-gcm:${Uri.encodeComponent('$key:$key')}@example.org:8388');
    expect(ss2022['password'], '$key:$key');
  });

  test('SS plugin options are converted and not discarded', () {
    final base = 'ss://${encoded('aes-128-gcm:password')}@example.org:8388/';
    final obfs = parseNodeLink(
        '$base?plugin=${Uri.encodeComponent('obfs-local;obfs=http;obfs-host=cdn.example')}');
    expect(obfs['plugin'], 'obfs');
    expect(obfs['plugin-opts'], {'mode': 'http', 'host': 'cdn.example'});
    final ws = parseNodeLink(
        '$base?plugin=${Uri.encodeComponent('v2ray-plugin;tls;host=cdn.example;path=/ws;mux=0')}');
    expect(ws['plugin-opts'], {
      'mode': 'websocket',
      'tls': true,
      'host': 'cdn.example',
      'path': '/ws',
      'mux': false
    });
  });

  test('Hysteria2 aliases retain auth, TLS, obfs and port hopping', () {
    for (final scheme in ['hy2', 'hysteria2']) {
      final node = parseNodeLink(
          '$scheme://user%3Ap%40ss@example.org/?sni=tls.example&insecure=1&obfs=salamander&obfs-password=obfs%2Bpass&mport=443,8000-8010&up=30&down=200#HY');
      expect(node['type'], 'hysteria2');
      expect(node['port'], 443);
      expect(node['password'], 'user:p@ss');
      expect(node['skip-cert-verify'], true);
      expect(node['sni'], 'tls.example');
      expect(node['obfs-password'], 'obfs+pass');
      expect(node['ports'], '443,8000-8010');
      expect(node['up'], '30');
    }
  });

  test('TUIC v5 preserves UUID, password and QUIC options', () {
    final node = parseNodeLink(
        'tuic://$uuid:p%3Aa%40ss@example.org:10443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=tls.example&disable_sni=0&reduce_rtt=1');
    expect(node['uuid'], uuid);
    expect(node['password'], 'p:a@ss');
    expect(node['congestion-controller'], 'bbr');
    expect(node['udp-relay-mode'], 'native');
    expect(node['disable-sni'], false);
    expect(node['reduce-rtt'], true);
    expect(node['alpn'], ['h3']);
  });

  test('SOCKS aliases and HTTPS support encoded credentials and IPv6', () {
    for (final scheme in ['socks', 'socks5']) {
      final node =
          parseNodeLink('$scheme://u%3Aser:p%40ss@[2001:db8::1]:1081#SOCKS');
      expect(node['type'], 'socks5');
      expect(node['username'], 'u:ser');
      expect(node['password'], 'p@ss');
      expect(node['port'], 1081);
      expect(node['server'], '2001:db8::1');
    }
    expect(parseNodeLink('socks5://example.org')['port'], 1080);
    expect(parseNodeLink('https://example.org')['tls'], true);
  });

  test('manual VLESS nodes retain Host, groups, names and deletion behavior',
      () {
    const template =
        'proxies: []\nproxy-groups: [{name: custom, type: select, proxies: [DIRECT]}]\nrules: [MATCH,custom]\n';

    final link =
        'vless://$uuid@example.org?security=tls&type=ws&host=original.example&path=%2Fws#Manual';
    final first =
        editSubscriptionHost(addNodeLink(template, link), 'override.example');
    final added = addNodeLink(first, link);
    final config = loadYaml(added);
    expect(
        config['proxies'][0]['ws-opts']['headers']['Host'], 'original.example');
    expect(
        config['proxies'][1]['ws-opts']['headers']['Host'], 'original.example');
    expect(savedManualNodeNames(added), ['Manual (2)', 'Manual']);
    expect(config['proxy-groups'][0]['proxies'],
        containsAll(['Manual (2)', 'Manual']));
    expect(config['rules'], loadYaml(template)['rules']);
    final deleted = loadYaml(deleteManualNode(added, 'Manual'));
    expect(deleted['proxies'].length, 1);
    expect(deleted['proxy-groups'][0]['proxies'], isNot(contains('Manual')));
  });

  test(
      'malformed and unsupported options fail before saving without leaking credentials',
      () {
    final base = 'vless://$uuid@example.org';
    final cases = [
      '$base:0',
      '$base:65536',
      '$base:bad',
      'vless://not-a-uuid@example.org',
      'vless://$uuid@',
      '$base?security=xtls',
      '$base?security=reality&pbk=bad',
      '$base?security=reality&pbk=${base64Url.encode(List.filled(32, 1))}&sid=abc',
      '$base?flow=xtls-rprx-vision',
      '$base?type=quic',
      '$base?type=grpc&mode=multi',
      '$base?encryption=unsupported',
      '$base?security=tls&insecure=invalid',
      '$base?type=ws&type=tcp',
      '$base?unknown=credential',
      '$base?security=tls&sni=a&peer=b',
      '$base?type=xhttp&mode=invalid',
      '$base?type=xhttp&extra=%7B%7D',
      '$base?security=tls&pbk=must-not-be-ignored',
      'trojan://secret@example.org?security=none',
      'anytls://secret@example.org?security=reality',
      'tuic://secret@example.org',
      'tuic://$uuid:secret@example.org?udp_relay_mode=bad',
      'hy2://secret@example.org?obfs=salamander',
      'hy2://secret@example.org?mport=9000-8000',
      'hy2://secret@example.org?down=invalid',
      'ss://invalid@example.org:8388',
      'ss://unknown:secret@example.org:8388',
      'ss://aes-128-gcm:secret@example.org:8388?plugin=unknown',
      'ss://aes-128-gcm:secret@example.org:8388?plugin=v2ray-plugin%3Bmode%3Dquic',
      'socks5://example.org:0',
      'http://example.org/path',
      'trojan://secret%GG@example.org',
      'trojan://secret@example.org#%FF',
      'trojan://secret@example.org\nvless://other',
    ];
    for (final link in cases) {
      expect(
          () => parseNodeLink(link),
          throwsA(isA<FormatException>().having(
              (e) => e.toString(),
              'safe error',
              allOf(isNot(contains('secret')), isNot(contains('credential'))))),
          reason: 'Invalid case ${cases.indexOf(link)} must not be imported');
    }
  });
}
