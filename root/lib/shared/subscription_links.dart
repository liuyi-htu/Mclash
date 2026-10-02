/// Stored as one URL per line to keep existing single-link profiles compatible.
List<String> subscriptionLinks(String value) {
  final links = value
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toSet()
      .toList();
  if (links.isEmpty) throw const FormatException('请输入订阅链接');
  for (var i = 0; i < links.length; i++) {
    final uri = Uri.tryParse(links[i]);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw FormatException('第 ${i + 1} 个订阅链接无效，请输入 HTTP 或 HTTPS 链接');
    }
  }
  return links;
}

String normalizeSubscriptionLinks(String value) =>
    subscriptionLinks(value).join('\n');
