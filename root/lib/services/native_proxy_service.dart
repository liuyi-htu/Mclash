import 'package:flutter/services.dart';

import '../core/models.dart';

class NativeProxyService {
  NativeProxyService._();

  static final NativeProxyService instance = NativeProxyService._();
  static const MethodChannel _channel = MethodChannel('mclash/native');

  Future<bool> getUsageNoticeAccepted() async {
    return await _channel.invokeMethod<bool>('getUsageNoticeAccepted') ?? false;
  }

  Future<void> acceptUsageNotice() {
    return _channel.invokeMethod<void>('acceptUsageNotice');
  }

  Future<bool> getDeveloperModeEnabled() async {
    return await _channel.invokeMethod<bool>('getDeveloperModeEnabled') ??
        false;
  }

  Future<void> enableDeveloperMode() {
    return _channel.invokeMethod<void>('enableDeveloperMode');
  }

  Future<void> disableDeveloperMode() {
    return _channel.invokeMethod<void>('disableDeveloperMode');
  }

  Future<void> switchToRootMode() =>
      _channel.invokeMethod<void>('switchToRootMode');

  Future<bool> hasRootPermission() async =>
      await _channel.invokeMethod<bool>('hasRootPermission') ?? false;

  Future<RootStatus> getRootStatus() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getRootStatus',
    );
    return RootStatus.fromMap(result ?? const <Object?, Object?>{});
  }

  Future<RootStatus> installRootModule() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'installRootModule',
    );
    return RootStatus.fromMap(result ?? const <Object?, Object?>{});
  }

  Future<String> getRootModuleVersion() async =>
      await _channel.invokeMethod<String>('getRootModuleVersion') ?? '';

  Future<RootSettings> getRootSettings() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getRootSettings',
    );
    return RootSettings.fromMap(result ?? const <Object?, Object?>{});
  }

  Future<RootSettings> saveRootSettings(RootSettings settings) async {
    final result = await _channel
        .invokeMapMethod<Object?, Object?>('saveRootSettings', <String, Object>{
      'autoStart': settings.autoStart,
      'loggingEnabled': settings.loggingEnabled,
      'ipv6Enabled': settings.ipv6Enabled,
      'bypassLan': settings.bypassLan,
      'bypassCidrs': settings.bypassCidrs,
      'proxyMode': settings.proxyMode.name,
    });
    return RootSettings.fromMap(result ?? const <Object?, Object?>{});
  }

  Future<void> syncRootRuntime() =>
      _channel.invokeMethod<void>('syncRootRuntime');

  Future<void> startRoot() => _channel.invokeMethod<void>('startRoot');

  Future<void> stopRoot() => _channel.invokeMethod<void>('stopRoot');

  Future<bool> isRootRunning() async =>
      await _channel.invokeMethod<bool>('isRootRunning') ?? false;

  Future<String> readRootLog(String name) async =>
      await _channel.invokeMethod<String>('readRootLog', <String, Object>{
        'name': name,
      }) ??
      '$name 为空';

  Future<void> clearRootLog(String name) => _channel.invokeMethod<void>(
        'clearRootLog',
        <String, Object>{'name': name},
      );

  Future<RootCoreVersion> checkRootCoreVersion(String manifestUrl) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'checkRootCoreVersion',
      <String, Object>{'manifestUrl': manifestUrl},
    );
    return RootCoreVersion.fromMap(result ?? const <Object?, Object?>{});
  }

  Future<Map<String, dynamic>> updateRootCore(RootCoreVersion version) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'updateRootCore',
      version.toArguments(),
    );
    return Map<String, dynamic>.from(result ?? const <String, dynamic>{});
  }

  Future<Map<String, dynamic>> getRootCoreUpdateStatus() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getRootCoreUpdateStatus',
    );
    return Map<String, dynamic>.from(result ?? const <String, dynamic>{});
  }

  Future<void> cancelRootCoreUpdate() =>
      _channel.invokeMethod<void>('cancelRootCoreUpdate');

  Future<Map<String, dynamic>> getDeviceRegistration() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getDeviceRegistration',
    );
    return Map<String, dynamic>.from(result ?? const <String, dynamic>{});
  }

  Future<String?> exportDeviceRegistration() {
    return _channel.invokeMethod<String>('exportDeviceRegistration');
  }

  Future<ConfigInfo> getConfigInfo() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getConfigInfo',
    );
    return ConfigInfo.fromMap(result ?? const <Object?, Object?>{});
  }

  Future<List<ConfigProfile>> getConfigs() async {
    final result =
        await _channel.invokeListMethod<Object?>('getConfigs') ?? const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(ConfigProfile.fromMap)
        .toList(growable: false);
  }

  Future<List<String>> getProxyGroupOrder() async {
    final result =
        await _channel.invokeListMethod<String>('getProxyGroupOrder') ??
            const [];
    return result;
  }

  Future<List<ConfigProfile>> importConfigs() async {
    final result =
        await _channel.invokeListMethod<Object?>('importConfigs') ?? const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(ConfigProfile.fromMap)
        .toList(growable: false);
  }

  Future<List<ConfigProfile>> addSubscription({
    required String name,
    required String url,
  }) async {
    final result = await _channel.invokeListMethod<Object?>(
          'addSubscription',
          <String, Object>{'name': name, 'url': url},
        ) ??
        const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(ConfigProfile.fromMap)
        .toList(growable: false);
  }

  Future<List<ConfigProfile>> updateSubscription({
    required String id,
    required String name,
    required String url,
  }) async {
    final result = await _channel.invokeListMethod<Object?>(
          'updateSubscription',
          <String, Object>{'id': id, 'name': name, 'url': url},
        ) ??
        const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(ConfigProfile.fromMap)
        .toList(growable: false);
  }

  Future<List<ConfigProfile>> refreshSubscription(String id) async {
    final result = await _channel.invokeListMethod<Object?>(
          'refreshSubscription',
          <String, Object>{'id': id},
        ) ??
        const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(ConfigProfile.fromMap)
        .toList(growable: false);
  }

  Future<String> getConfigContent(String id) async {
    return await _channel.invokeMethod<String>(
          'getConfigContent',
          <String, Object>{'id': id},
        ) ??
        '';
  }

  Future<List<ConfigProfile>> saveConfigContent({
    required String id,
    required String content,
  }) async {
    final result = await _channel.invokeListMethod<Object?>(
          'saveConfigContent',
          <String, Object>{'id': id, 'content': content},
        ) ??
        const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(ConfigProfile.fromMap)
        .toList(growable: false);
  }

  Future<SubscriptionUrlTestResult> testSubscriptionUrl(String id) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'testSubscriptionUrl',
      <String, Object>{'id': id},
    );
    return SubscriptionUrlTestResult.fromMap(
      result ?? const <Object?, Object?>{},
    );
  }

  Future<ConfigInfo> selectConfig(String id) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'selectConfig',
      <String, Object>{'id': id},
    );
    return ConfigInfo.fromMap(result ?? const <Object?, Object?>{});
  }

  Future<List<ConfigProfile>> renameConfig({
    required String id,
    required String name,
  }) async {
    final result = await _channel.invokeListMethod<Object?>(
          'renameConfig',
          <String, Object>{'id': id, 'name': name},
        ) ??
        const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(ConfigProfile.fromMap)
        .toList(growable: false);
  }

  Future<List<ConfigProfile>> deleteConfig(String id) async {
    final result = await _channel.invokeListMethod<Object?>(
          'deleteConfig',
          <String, Object>{'id': id},
        ) ??
        const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(ConfigProfile.fromMap)
        .toList(growable: false);
  }

  Future<List<InstalledApp>> getInstalledApps() async {
    final result =
        await _channel.invokeListMethod<Object?>('getInstalledApps') ??
            const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(InstalledApp.fromMap)
        .toList(growable: false);
  }

  Future<AppProxyMode> getMode() async {
    final value = await _channel.invokeMethod<String>('getMode');
    return value == 'include' || value == 'onlySelected'
        ? AppProxyMode.include
        : AppProxyMode.exclude;
  }

  Future<Set<String>> getSelectedPackages() async {
    final result = await _channel.invokeListMethod<String>(
      'getSelectedPackages',
    );
    return (result ?? const <String>[]).toSet();
  }

  Future<void> saveAppFilter({
    required AppProxyMode mode,
    required Set<String> packageNames,
  }) {
    return _channel.invokeMethod<void>('saveAppFilter', <String, Object>{
      'mode': mode.name,
      'packageNames': packageNames.toList(growable: false),
    });
  }

  Future<void> start() => _channel.invokeMethod<void>('start');

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  Future<bool> isRunning() async {
    return await _channel.invokeMethod<bool>('isRunning') ?? false;
  }

  Future<Map<String, int>> getTrafficStats() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getTrafficStats',
    );
    return <String, int>{
      'rxBytes': (result?['rxBytes'] as num?)?.toInt() ?? 0,
      'txBytes': (result?['txBytes'] as num?)?.toInt() ?? 0,
    };
  }

  Future<String> getDelayResults() async {
    return await _channel.invokeMethod<String>('getDelayResults') ?? '{}';
  }

  Future<void> setDelayResults(String json) {
    return _channel.invokeMethod<void>('setDelayResults', <String, Object>{
      'json': json,
    });
  }
}
