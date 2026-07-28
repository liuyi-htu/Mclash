import 'package:flutter/services.dart';

import 'models.dart';

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
    final result =
        await _channel.invokeListMethod<Object?>(
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
    final result =
        await _channel.invokeListMethod<Object?>(
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
    final result =
        await _channel.invokeListMethod<Object?>(
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
    final result =
        await _channel.invokeListMethod<Object?>(
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
    final result =
        await _channel.invokeListMethod<Object?>(
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
    final result =
        await _channel.invokeListMethod<Object?>(
          'deleteConfig',
          <String, Object>{'id': id},
        ) ??
        const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(ConfigProfile.fromMap)
        .toList(growable: false);
  }

  Future<VpnTunnelSettings> getVpnTunnelSettings() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getVpnTunnelSettings',
    );
    return VpnTunnelSettings.fromMap(result ?? const <Object?, Object?>{});
  }

  Future<VpnTunnelSettings> saveVpnTunnelSettings({
    required int mtu,
    required int tcpBufferSize,
    required List<String> ipv4DnsServers,
    required bool bypassLan,
  }) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'saveVpnTunnelSettings',
      <String, Object>{
        'mtu': mtu,
        'tcpBufferSize': tcpBufferSize,
        'ipv4DnsServers': ipv4DnsServers,
        'bypassLan': bypassLan,
      },
    );
    return VpnTunnelSettings.fromMap(result ?? const <Object?, Object?>{});
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
    return value == 'excludeSelected'
        ? AppProxyMode.excludeSelected
        : AppProxyMode.onlySelected;
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

  Future<bool> prepareVpn() async {
    return await _channel.invokeMethod<bool>('prepareVpn') ?? false;
  }

  Future<void> start() => _channel.invokeMethod<void>('start');

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  Future<bool> isRunning() async {
    return await _channel.invokeMethod<bool>('isRunning') ?? false;
  }

  Future<String> getStartupLog() async {
    return await _channel.invokeMethod<String>('getStartupLog') ?? '没有调试日志';
  }

  Future<String> getDebugLog(String name) async {
    return await _channel.invokeMethod<String>('getDebugLog', <String, Object>{
          'name': name,
        }) ??
        '没有调试日志';
  }

  Future<bool> getDebugLoggingEnabled() async {
    return await _channel.invokeMethod<bool>('getDebugLoggingEnabled') ?? false;
  }

  Future<String> getDelayResults() async {
    return await _channel.invokeMethod<String>('getDelayResults') ?? '{}';
  }

  Future<void> setDelayResults(String json) {
    return _channel.invokeMethod<void>('setDelayResults', <String, Object>{
      'json': json,
    });
  }

  Future<void> setDebugLoggingEnabled(bool enabled) {
    return _channel.invokeMethod<void>(
      'setDebugLoggingEnabled',
      <String, Object>{'enabled': enabled},
    );
  }

  Future<void> clearDebugLogs() =>
      _channel.invokeMethod<void>('clearDebugLogs');
}
