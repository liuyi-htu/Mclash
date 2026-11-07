import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core_connection_settings.dart';

void main() {
  test('wildcard listeners connect through loopback and preserve IPv6', () {
    final ipv4 =
        CoreConnectionSettings(controller: '0.0.0.0:9191', mixedPort: 7891);
    ipv4.validate();
    expect(ipv4.endpoint.host, '127.0.0.1');
    expect(ipv4.endpoint.port, 9191);
    final ipv6 =
        CoreConnectionSettings(controller: '[::]:9191', mixedPort: 7891);
    ipv6.validate();
    expect(ipv6.endpoint.toString(), 'http://[::1]:9191');
  });
  test('rejects invalid ports, duplicate ports, URLs and header injection', () {
    for (final address in [
      '127.0.0.1',
      'http://127.0.0.1:9090',
      '127.0.0.1:0',
      '127.0.0.1:65536',
      'example.org:9090',
      '127.0.0.1:9090/path'
    ]) {
      expect(
          () => CoreConnectionSettings(controller: address, mixedPort: 7890)
              .validate(),
          throwsFormatException,
          reason: address);
    }
    expect(() => const CoreConnectionSettings(mixedPort: 9090).validate(),
        throwsFormatException);
    expect(() => const CoreConnectionSettings(mixedPort: 0).validate(),
        throwsFormatException);
    expect(
        () => const CoreConnectionSettings(secret: 'a\nb', mixedPort: 7890)
            .validate(),
        throwsFormatException);
  });
}
