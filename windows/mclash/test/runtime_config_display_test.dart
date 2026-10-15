import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:mclash/runtime_config_display.dart';

const source = """
# Mclash 手动节点: ["节点一"]
mode: rule
proxies:
  - name: 节点一
    type: vmess
    port: 443
    udp: true
    password: "true:#,[]"
    ws-opts:
      path: /socket
      headers:
        Host: example.org
    alpn: [h2, http/1.1]
  - name: 节点二
    type: http
    server: example.net
    port: 80
    certificate: |-
      first line
      second line
proxy-groups:
  - name: Group
    type: select
    proxies: [节点一, 节点二]
# rules stay in their original place
rules: [MATCH,Group]
""";

void main() {
  test('each proxy occupies one line, preserving options and other sections',
      () {
    final formatted = formatRuntimeConfigForDisplay(source);
    expect(loadYaml(formatted), loadYaml(source));
    final lines = formatted
        .split('\n')
        .where((line) => line.trimLeft().startsWith('- {'));
    expect(lines, hasLength(2));
    expect(lines.first, contains('ws-opts'));
    expect(lines.last, contains(r'first line\nsecond line'));
    expect(formatted.substring(formatted.indexOf('proxy-groups:')),
        source.substring(source.indexOf('proxy-groups:')));
    expect(formatted, startsWith('# Mclash 手动节点: ["节点一"]\n'));
    expect(formatRuntimeConfigForDisplay(formatted), formatted);
  });
  test('flow lists are split into one line per proxy', () {
    const text =
        'proxies: [{name: A, type: http}, {name: B, type: http}]\nrules: []\n';
    final formatted = formatRuntimeConfigForDisplay(text);
    expect(loadYaml(formatted), loadYaml(text));
    expect(
        formatted
            .split('\n')
            .where((line) => line.trimLeft().startsWith('- {')),
        hasLength(2));
  });
  test('aliases remain valid when expanding compact proxies', () {
    const text =
        '# runtime\noptions: &options {Host: example.org}\nproxies: &nodes [{name: A, type: http, headers: *options}]\ncopy: *nodes\n';
    final formatted = formatRuntimeConfigForDisplay(text);
    expect(loadYaml(formatted), loadYaml(text));
    expect(formatted, startsWith('# runtime\n'));
    expect(
        formatted
            .split('\n')
            .where((line) => line.trimLeft().startsWith('- {')),
        hasLength(1));
  });
  test('empty, missing or malformed configurations stay readable', () {
    for (final text in [
      'proxies: []\n',
      'rules: []\n',
      'proxies: [broken',
      ''
    ]) {
      expect(formatRuntimeConfigForDisplay(text), text);
    }
  });
}
