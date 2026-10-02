import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/subscription_links.dart';

void main() {
  test('links normalize CRLF, blanks and repeated URLs in source order', () {
    expect(
        normalizeSubscriptionLinks(
            ' https://example.org/a\r\n\r\nhttps://example.org/b\nhttps://example.org/a '),
        'https://example.org/a\nhttps://example.org/b');
    expect(
        subscriptionLinks('https://example.org/a'), ['https://example.org/a']);
  });
  test('every link must be valid HTTP or HTTPS', () {
    for (final value in [
      '',
      'file:///tmp/test',
      'https://',
      'https://example.org/a\ninvalid'
    ]) {
      expect(() => subscriptionLinks(value), throwsFormatException);
    }
  });
}
