enum ProxyStatus { stopped, starting, running, stopping }

enum AppProxyMode { include, exclude }

enum RootState { disabled, installing, rebootRequired, ready, broken }

enum RootProxyMode { tun, tproxy }

class RootStatus {
  const RootStatus({
    required this.state,
    required this.message,
    required this.hasRootPermission,
    required this.running,
    required this.moduleVersion,
    required this.coreVersion,
  });

  factory RootStatus.fromMap(Map<Object?, Object?> map) {
    final raw = map['state'] as String? ?? 'DISABLED';
    final state = switch (raw) {
      'INSTALLING' => RootState.installing,
      'REBOOT_REQUIRED' => RootState.rebootRequired,
      'READY' => RootState.ready,
      'BROKEN' => RootState.broken,
      _ => RootState.disabled,
    };
    return RootStatus(
      state: state,
      message: map['message'] as String? ?? '状态未知',
      hasRootPermission: map['hasRootPermission'] as bool? ?? false,
      running: map['running'] as bool? ?? false,
      moduleVersion: map['moduleVersion'] as String? ?? '',
      coreVersion: map['coreVersion'] as String? ?? '',
    );
  }

  final RootState state;
  final String message;
  final bool hasRootPermission;
  final bool running;
  final String moduleVersion;
  final String coreVersion;
}

class RootSettings {
  const RootSettings({
    required this.autoStart,
    required this.loggingEnabled,
    required this.ipv6Enabled,
    required this.bypassLan,
    required this.bypassCidrs,
    required this.proxyMode,
    required this.ipv6TproxySupported,
  });

  factory RootSettings.fromMap(Map<Object?, Object?> map) => RootSettings(
        autoStart: map['autoStart'] as bool? ?? false,
        loggingEnabled: map['loggingEnabled'] as bool? ?? false,
        ipv6Enabled: map['ipv6Enabled'] as bool? ?? false,
        bypassLan: map['bypassLan'] as bool? ?? true,
        bypassCidrs: map['bypassCidrs'] as String? ?? '',
        proxyMode: map['proxyMode'] == 'tproxy'
            ? RootProxyMode.tproxy
            : RootProxyMode.tun,
        ipv6TproxySupported: map['ipv6TproxySupported'] as bool? ?? false,
      );

  final bool autoStart;
  final bool loggingEnabled;
  final bool ipv6Enabled;
  final bool bypassLan;
  final String bypassCidrs;
  final RootProxyMode proxyMode;
  final bool ipv6TproxySupported;

  RootSettings copyWith({
    bool? autoStart,
    bool? loggingEnabled,
    bool? ipv6Enabled,
    bool? bypassLan,
    String? bypassCidrs,
    RootProxyMode? proxyMode,
  }) =>
      RootSettings(
        autoStart: autoStart ?? this.autoStart,
        loggingEnabled: loggingEnabled ?? this.loggingEnabled,
        ipv6Enabled: ipv6Enabled ?? this.ipv6Enabled,
        bypassLan: bypassLan ?? this.bypassLan,
        bypassCidrs: bypassCidrs ?? this.bypassCidrs,
        proxyMode: proxyMode ?? this.proxyMode,
        ipv6TproxySupported: ipv6TproxySupported,
      );
}

class RootCoreVersion {
  const RootCoreVersion({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    required this.abi,
    required this.url,
    required this.sha256,
    required this.size,
    required this.publishedAt,
  });

  factory RootCoreVersion.fromMap(Map<Object?, Object?> map) => RootCoreVersion(
        currentVersion: map['currentVersion'] as String? ?? '',
        latestVersion: map['latestVersion'] as String? ?? '',
        hasUpdate: map['hasUpdate'] as bool? ?? false,
        abi: map['abi'] as String? ?? '',
        url: map['url'] as String? ?? '',
        sha256: map['sha256'] as String? ?? '',
        size: (map['size'] as num?)?.toInt() ?? -1,
        publishedAt: map['publishedAt'] as String? ?? '',
      );

  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String abi;
  final String url;
  final String sha256;
  final int size;
  final String publishedAt;

  Map<String, Object> toArguments() => <String, Object>{
        'url': url,
        'sha256': sha256,
      };
}

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
