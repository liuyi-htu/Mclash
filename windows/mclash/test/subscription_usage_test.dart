import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/subscription_usage.dart';

void main() {
  test('usage subtracts upload and download and accepts spacing and case', () {
    expect(
        subscriptionUsageSummary(
            'Upload=1073741824;download=2147483648; TOTAL=5368709120;expire=0'),
        '剩余流量：2.00 GB\n到期时间：不限时');
    expect(subscriptionUsageSummary('upload=10;download=100;total=20'),
        '剩余流量：0 B\n到期时间：不限时');
  });
  test('missing and invalid usage is unknown, zero total is unlimited', () {
    expect(subscriptionUsageSummary(null), '剩余流量：未提供\n到期时间：不限时');
    expect(
        subscriptionUsageSummary(
            'upload=-1;download=oops;total=20;expire=9223372036854775807'),
        '剩余流量：未提供\n到期时间：不限时');
    expect(subscriptionUsageSummary('total=0;expire=0'), '剩余流量：不限量\n到期时间：不限时');
  });
  test('expiry uses local calendar time from Unix seconds', () {
    const seconds = 2000000000;
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String pad(int n) => n.toString().padLeft(2, '0');
    expect(subscriptionUsageSummary('expire=$seconds'),
        '剩余流量：未提供\n到期时间：${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}');
  });
}
