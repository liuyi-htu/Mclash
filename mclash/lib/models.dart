enum ProxyStatus { stopped, starting, running, stopping }

enum AppProxyMode { onlySelected, excludeSelected }

class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    required this.isSystemApp,
  });

  factory InstalledApp.fromMap(Map<Object?, Object?> map) {
    return InstalledApp(
      packageName: map['packageName']! as String,
      label: map['label']! as String,
      isSystemApp: map['isSystemApp'] as bool? ?? false,
    );
  }

  final String packageName;
  final String label;
  final bool isSystemApp;
}

class ConfigInfo {
  const ConfigInfo({required this.exists, this.fileName});

  factory ConfigInfo.fromMap(Map<Object?, Object?> map) {
    return ConfigInfo(
      exists: map['exists'] as bool? ?? false,
      fileName: map['fileName'] as String?,
    );
  }

  final bool exists;
  final String? fileName;
}

class ConfigProfile {
  const ConfigProfile({
    required this.id,
    required this.name,
    required this.type,
    required this.active,
    required this.exists,
    required this.updatedAt,
    this.url,
  });

  factory ConfigProfile.fromMap(Map<Object?, Object?> map) {
    return ConfigProfile(
      id: map['id']! as String,
      name: map['name']! as String,
      type: map['type']! as String,
      url: map['url'] as String?,
      active: map['active'] as bool? ?? false,
      exists: map['exists'] as bool? ?? false,
      updatedAt: map['updatedAt'] as int? ?? 0,
    );
  }

  final String id;
  final String name;
  final String type;
  final String? url;
  final bool active;
  final bool exists;
  final int updatedAt;

  bool get isSubscription => type == 'subscription';
}

class SubscriptionUrlTestResult {
  const SubscriptionUrlTestResult({
    required this.success,
    required this.message,
    this.responseTimeMs,
    this.statusCode,
    this.contentLength,
    this.contentType,
  });

  factory SubscriptionUrlTestResult.fromMap(Map<Object?, Object?> map) {
    return SubscriptionUrlTestResult(
      success: map['success'] as bool? ?? false,
      responseTimeMs: map['responseTimeMs'] as int?,
      statusCode: map['statusCode'] as int?,
      contentLength: map['contentLength'] as int?,
      contentType: map['contentType'] as String?,
      message: map['message'] as String? ?? '检测失败',
    );
  }

  final bool success;
  final int? responseTimeMs;
  final int? statusCode;
  final int? contentLength;
  final String? contentType;
  final String message;
}

class VpnTunnelSettings {
  const VpnTunnelSettings({
    required this.mtu,
    required this.tcpBufferSize,
    required this.ipv4DnsServers,
    required this.ipv6Enabled,
    required this.bypassLan,
  });

  factory VpnTunnelSettings.fromMap(Map<Object?, Object?> map) {
    return VpnTunnelSettings(
      mtu: map['mtu'] as int? ?? 1500,
      tcpBufferSize: map['tcpBufferSize'] as int? ?? 262144,
      ipv4DnsServers:
          (map['ipv4DnsServers'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const ['1.1.1.1'],
      ipv6Enabled: map['ipv6Enabled'] as bool? ?? false,
      bypassLan: map['bypassLan'] as bool? ?? true,
    );
  }

  final int mtu;
  final int tcpBufferSize;
  final List<String> ipv4DnsServers;
  final bool ipv6Enabled;
  final bool bypassLan;
}
