import 'models.dart';
import 'proxy_platform_service.dart';
import 'windows_proxy_platform_service.dart';

class NativeProxyService implements ProxyPlatformService {
  NativeProxyService._() : _delegate = WindowsProxyPlatformService();

  static final NativeProxyService instance = NativeProxyService._();
  final ProxyPlatformService _delegate;

  @override
  Future<bool> isRunning() => _delegate.isRunning();
  @override
  Future<void> start() => _delegate.start();
  @override
  Future<void> stop() => _delegate.stop();
  @override
  Future<void> restart() => _delegate.restart();
  @override
  Future<void> syncSystemProxy() => _delegate.syncSystemProxy();
  @override
  Future<NetworkMode> getNetworkMode() => _delegate.getNetworkMode();
  @override
  Future<void> setNetworkMode(NetworkMode mode) =>
      _delegate.setNetworkMode(mode);
  @override
  Future<CoreType> getCoreType() => _delegate.getCoreType();
  @override
  Future<void> setCoreType(CoreType core) => _delegate.setCoreType(core);
  @override
  Future<ConfigInfo> getConfigInfo() => _delegate.getConfigInfo();
  @override
  Future<List<ConfigProfile>> getConfigs() => _delegate.getConfigs();
  @override
  Future<List<ConfigProfile>> importConfigs() => _delegate.importConfigs();
  @override
  Future<ConfigInfo> selectConfig(String id) => _delegate.selectConfig(id);
  @override
  Future<String> getConfigContent(String id) => _delegate.getConfigContent(id);
  @override
  Future<List<ConfigProfile>> saveConfigContent({
    required String id,
    required String content,
  }) => _delegate.saveConfigContent(id: id, content: content);
  @override
  Future<List<ConfigProfile>> renameConfig({
    required String id,
    required String name,
  }) => _delegate.renameConfig(id: id, name: name);
  @override
  Future<List<ConfigProfile>> deleteConfig(String id) =>
      _delegate.deleteConfig(id);
  @override
  Future<List<DebugLogFile>> getDebugLogs() => _delegate.getDebugLogs();
  @override
  Future<String> getDebugLogContent(String id) =>
      _delegate.getDebugLogContent(id);
  @override
  Future<bool> getUsageNoticeAccepted() => _delegate.getUsageNoticeAccepted();
  @override
  Future<void> acceptUsageNotice() => _delegate.acceptUsageNotice();
  @override
  Future<List<ConfigProfile>> addSubscription({
    required String name,
    required String url,
  }) => _delegate.addSubscription(name: name, url: url);
  @override
  Future<List<ConfigProfile>> updateSubscription({
    required String id,
    required String name,
    required String url,
  }) => _delegate.updateSubscription(id: id, name: name, url: url);
  @override
  Future<List<ConfigProfile>> refreshSubscription(String id) =>
      _delegate.refreshSubscription(id);
  @override
  Future<SubscriptionUrlTestResult> testSubscriptionUrl(String id) =>
      _delegate.testSubscriptionUrl(id);
  @override
  Future<bool> getDebugLoggingEnabled() => _delegate.getDebugLoggingEnabled();
  @override
  Future<void> setDebugLoggingEnabled(bool enabled) =>
      _delegate.setDebugLoggingEnabled(enabled);
  @override
  Future<void> clearDebugLogs() => _delegate.clearDebugLogs();
  @override
  Future<bool> getServiceAutoStartEnabled() =>
      _delegate.getServiceAutoStartEnabled();
  @override
  Future<void> setServiceAutoStartEnabled(bool enabled) =>
      _delegate.setServiceAutoStartEnabled(enabled);
  @override
  Future<bool> getIpv6Enabled() => _delegate.getIpv6Enabled();
  @override
  Future<void> setIpv6Enabled(bool enabled) =>
      _delegate.setIpv6Enabled(enabled);
  @override
  Future<bool> getBypassLanEnabled() => _delegate.getBypassLanEnabled();
  @override
  Future<void> setBypassLanEnabled(bool enabled) =>
      _delegate.setBypassLanEnabled(enabled);
  @override
  Future<CoreUpdateInfo> checkCoreUpdate(CoreType core) =>
      _delegate.checkCoreUpdate(core);
  @override
  Future<void> updateCore(CoreType core) => _delegate.updateCore(core);
}
