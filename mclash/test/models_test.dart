import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/models.dart';

void main() {
  group('VpnTunnelSettings', () {
    test('supports IPv6 without a separate IPv6 DNS setting', () {
      final settings = VpnTunnelSettings.fromMap({
        'ipv6Enabled': true,
      });

      expect(settings.ipv6Enabled, isTrue);
      expect(settings.ipv4DnsServers, ['1.1.1.1']);
    });
  });
}
