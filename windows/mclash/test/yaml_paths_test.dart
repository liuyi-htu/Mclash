import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:mclash/yaml_paths.dart';

void main() {
  test('cleans HTTP path arrays and scalar paths without changing YAML values',
      () {
    const source = r'''# keep comment
proxies:
  - {name: A, type: vmess, http-opts: {path: ["\/", "\/abc"]}}
  - {name: B, type: vmess, ws-opts: {path: "\/ws?ed=2048"}}
''';
    final normalized = normalizeYamlPaths(source);
    expect(normalized, isNot(contains(r'\/')));
    expect(normalized, contains('path: ["/", "/abc"]'));
    expect(normalized, startsWith('# keep comment'));
    expect(loadYaml(normalized), loadYaml(source));
    expect(normalizeYamlPaths(normalized), normalized);
  });
  test('retains real backslashes, single quotes and unrelated fields', () {
    const source = r'''path: ["\\\/abc", '\/literal']
password: "\/keep"
# path: "\/comment"
''';
    final normalized = normalizeYamlPaths(source);
    expect(loadYaml(normalized), loadYaml(source));
    expect(normalized, contains(r"'\/literal'"));
    expect(normalized, contains(r'password: "\/keep"'));
  });
}
