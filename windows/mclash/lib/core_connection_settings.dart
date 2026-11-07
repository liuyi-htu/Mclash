import 'dart:io';

class CoreConnectionSettings {
  const CoreConnectionSettings(
      {this.controller = '127.0.0.1:9090',
      this.secret = '',
      required this.mixedPort});
  final String controller;
  final String secret;
  final int mixedPort;

  factory CoreConnectionSettings.fromMap(Map<dynamic, dynamic> map,
          {int defaultPort = 7890}) =>
      CoreConnectionSettings(
        controller: map['controller'] as String? ?? '127.0.0.1:9090',
        secret: map['secret'] as String? ?? '',
        mixedPort: (map['mixedPort'] as num?)?.toInt() ?? defaultPort,
      );
  Map<String, Object> toMap() =>
      {'controller': controller, 'secret': secret, 'mixedPort': mixedPort};
  Uri get endpoint {
    final uri = Uri.parse('http://$controller');
    final host = switch (uri.host) {
      '0.0.0.0' || '*' => '127.0.0.1',
      '::' || '[::]' => '::1',
      _ => uri.host
    };
    return uri.replace(host: host);
  }

  void validate() {
    final uri = Uri.tryParse('http://$controller');
    if (uri == null ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.path.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.userInfo.isNotEmpty ||
        InternetAddress.tryParse(
                uri.host.replaceAll('[', '').replaceAll(']', '')) ==
            null) {
      throw const FormatException('请输入有效的控制接口 IP:端口，IPv6 使用 [地址]:端口');
    }
    if (mixedPort < 1 || mixedPort > 65535) {
      throw const FormatException('代理端口范围为 1–65535');
    }
    if (mixedPort == uri.port) throw const FormatException('代理端口不能与控制接口端口相同');
    if (secret.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('密钥不能包含换行');
    }
  }
}
