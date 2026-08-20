import 'models.dart';

abstract interface class ProxyPlatformService {
  Future<bool> isRunning();
  Future<void> start();
  Future<void> stop();
  Future<void> restart();
  Future<void> syncSystemProxy();
  Future<NetworkMode> getNetworkMode();
  Future<void> setNetworkMode(NetworkMode mode);
  Future<CoreType> getCoreType();
  Future<void> setCoreType(CoreType core);
  Future<ConfigInfo> getConfigInfo();
  Future<List<ConfigProfile>> getConfigs();
  Future<List<ConfigProfile>> importConfigs();
  Future<ConfigInfo> selectConfig(String id);
  Future<String> getConfigContent(String id);
  Future<List<ConfigProfile>> saveConfigContent({
    required String id,
    required String content,
  });
  Future<List<ConfigProfile>> renameConfig({
    required String id,
    required String name,
  });
  Future<List<ConfigProfile>> deleteConfig(String id);
  Future<List<DebugLogFile>> getDebugLogs();
  Future<String> getDebugLogContent(String id);
  Future<bool> getUsageNoticeAccepted();
  Future<void> acceptUsageNotice();
  Future<List<ConfigProfile>> addSubscription({
    required String name,
    required String url,
  });
  Future<List<ConfigProfile>> updateSubscription({
    required String id,
    required String name,
    required String url,
  });
  Future<List<ConfigProfile>> refreshSubscription(String id);
  Future<SubscriptionUrlTestResult> testSubscriptionUrl(String id);
  Future<bool> getDebugLoggingEnabled();
  Future<void> setDebugLoggingEnabled(bool enabled);
  Future<void> clearDebugLogs();
  Future<bool> getServiceAutoStartEnabled();
  Future<void> setServiceAutoStartEnabled(bool enabled);
  Future<bool> getIpv6Enabled();
  Future<void> setIpv6Enabled(bool enabled);
  Future<bool> getBypassLanEnabled();
  Future<void> setBypassLanEnabled(bool enabled);
  Future<CoreUpdateInfo> checkCoreUpdate(CoreType core);
  Future<void> updateCore(CoreType core);
}
