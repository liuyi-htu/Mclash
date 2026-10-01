String subscriptionUsageSummary(String? header) {
  final values = <String, int>{};
  for (final part in (header ?? '').split(';')) {
    final separator = part.indexOf('=');
    if (separator < 0) continue;
    final key = part.substring(0, separator).trim().toLowerCase();
    final value = int.tryParse(part.substring(separator + 1).trim());
    if (value != null && value >= 0) values[key] = value;
  }
  String remaining = '未提供';
  final total = values['total'];
  final upload = values['upload'];
  final download = values['download'];
  if (total == 0) {
    remaining = '不限量';
  } else if (total != null && upload != null && download != null) {
    var bytes = ((total - upload).clamp(0, total) - download)
        .clamp(0, total)
        .toDouble();
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var unit = 0;
    while (bytes >= 1024 && unit < units.length - 1) {
      bytes /= 1024;
      unit++;
    }
    remaining = '${bytes.toStringAsFixed(unit == 0 ? 0 : 2)} ${units[unit]}';
  }
  String expiration = '不限时';
  final expire = values['expire'];
  if (expire == 0) {
    expiration = '不限时';
  } else if (expire != null && expire <= 8640000000000) {
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(expire * 1000);
      String pad(int n) => n.toString().padLeft(2, '0');
      expiration =
          '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
    } on ArgumentError {
      expiration = '不限时';
    }
  }
  return '剩余流量：$remaining\n到期时间：$expiration';
}
