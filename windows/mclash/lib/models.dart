enum ProxyStatus { stopped, starting, running, stopping }

enum NetworkMode { proxy, tun }

enum CoreType { mihomo, singBox }

class DebugLogFile {
  const DebugLogFile({
    required this.id,
    required this.displayName,
    required this.description,
  });

  final String id;
  final String displayName;
  final String description;
}

class CoreUpdateInfo {
  const CoreUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
  });

  factory CoreUpdateInfo.fromMap(Map<String, dynamic> map) => CoreUpdateInfo(
        currentVersion: map['currentVersion']?.toString() ?? 'unknown',
        latestVersion: map['latestVersion']?.toString() ?? 'unknown',
        updateAvailable: map['updateAvailable'] == true,
      );

  final String currentVersion;
  final String latestVersion;
  final bool updateAvailable;
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
