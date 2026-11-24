import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core/models.dart';

void main() {
  test('new and missing settings default to TUN with mips', () {
    const defaults = RootProxySettings(bypassLan: true);
    expect(defaults.proxyMode, 'tun');
    expect(defaults.tunStack, 'mips');
    final restored = RootProxySettings.fromMap({});
    expect(restored.proxyMode, 'tun');
    expect(restored.tunStack, 'mips');
  });
  test('explicit existing selections are retained', () {
    final saved =
        RootProxySettings.fromMap({'proxyMode': 'tproxy', 'tunStack': 'mixed'});
    expect(saved.proxyMode, 'tproxy');
    expect(saved.tunStack, 'mixed');
  });
}
