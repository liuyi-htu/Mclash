import 'package:mclash/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/subscription_links.dart';

void main() {
  test('airport names follow URLs and legacy single links use the profile name',
      () {
    const profile = {
      'id': 'airport',
      'name': '原机场',
      'type': 'subscription',
      'url': 'https://example.org/a',
      'subscriptionUserInfo': 'total=1000'
    };
    final legacy = ConfigProfile.fromMap(profile);
    expect(legacy.subscriptionNameFor('https://example.org/a', 0), '原机场');
    expect(legacy.subscriptionInfoFor('https://example.org/a'), 'total=1000');
    final named = ConfigProfile.fromMap({
      ...profile,
      'url': 'https://example.org/b\nhttps://example.org/a',
      'subscriptionNames': {
        'https://example.org/a': '第一机场',
        'https://example.org/b': '第二机场'
      },
      'subscriptionInfos': {
        'https://example.org/a': 'total=2000',
        'https://example.org/b': 'total=3000'
      }
    });
    expect(named.subscriptionNameFor('https://example.org/b', 0), '第二机场');
    expect(named.subscriptionNameFor('https://example.org/a', 1), '第一机场');
    expect(named.subscriptionInfoFor('https://example.org/a'), 'total=2000');
    expect(named.subscriptionInfoFor('https://example.org/b'), 'total=3000');
  });

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
