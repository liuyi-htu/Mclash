import 'app_appearance.dart';
import 'pulse_dashboard.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_notice.dart';
import 'config_page.dart';
import 'proxy_panel_page.dart';
import 'models.dart';
import 'native_proxy_service.dart';
import 'proxy_platform_service.dart';

enum _RunModeChoice { mihomoTun, mihomoProxy }

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.service});

  final ProxyPlatformService? service;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ProxyPlatformService _service =
      widget.service ?? NativeProxyService.instance;

  final _statusNotifier = ValueNotifier(ProxyStatus.checking);
  ProxyStatus get _status => _statusNotifier.value;
  set _status(ProxyStatus value) => _statusNotifier.value = value;
  ConfigInfo _config = const ConfigInfo(exists: false);
  bool _debugLoggingEnabled = false;
  bool _serviceAutoStartEnabled = false;
  bool _ipv6Enabled = false;
  bool _bypassLanEnabled = true;
  NetworkMode _networkMode = NetworkMode.proxy;
  CoreType _coreType = CoreType.mihomo;
  bool _operationDialogOpen = false;
  Timer? _statusTimer;
  Timer? _trafficTimer;
  bool _samplingTraffic = false;
  int _selectedHomeTab = 0;
  double _downloadBytesPerSecond = 0;
  double _uploadBytesPerSecond = 0;
  String _proxyMode = 'rule';
  bool _changingProxyMode = false;
  Future<void>? _statusPoll;
  bool _refreshing = false;
  int _operationGeneration = 0;
  String? _statusError;
  final _coreBusy = ValueNotifier(false);
  CoreUpdateInfo? _coreInfo;
  bool _coreUpdating = false;
  String? _coreMessage;
  final _settingsBusy = ValueNotifier(false);
  bool get _canEditSettings => _status == ProxyStatus.stopped && _canOperate;

  bool get _canOperate =>
      !_changingProxyMode &&
      !_settingsBusy.value &&
      !_coreBusy.value &&
      (_status == ProxyStatus.running || _status == ProxyStatus.stopped);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _showUsageNoticeIfNeeded();
      await _refresh();
      if (!mounted) return;
      _trafficTimer = Timer.periodic(
          const Duration(seconds: 1), (_) => _updateTrafficSpeed());
    });
    _statusTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollStatus(),
    );
  }

  Future<void> _pollStatus() {
    if (_statusPoll != null) return _statusPoll!;
    if (_operationDialogOpen) return Future.value();
    final task = _detectStatus();
    _statusPoll = task;
    return task.whenComplete(() {
      if (identical(_statusPoll, task)) _statusPoll = null;
    });
  }

  Future<void> _statusAfterOperation() async {
    if (_statusPoll != null) await _statusPoll;
    if (mounted) await _pollStatus();
  }

  Future<void> _detectStatus() async {
    final generation = _operationGeneration;
    try {
      final next =
          await _service.getProxyStatus().timeout(const Duration(seconds: 12));
      if (!mounted || generation != _operationGeneration) return;
      final previous = _status;
      setState(() {
        _status = next;
        _statusError = null;
      });
      if (next == ProxyStatus.stopped && previous != next) {
        await _service.syncSystemProxy();
      }
      if (next == ProxyStatus.running && previous != next) {
        unawaited(_loadProxyMode());
      }
    } catch (error) {
      if (!mounted || generation != _operationGeneration) return;
      setState(() {
        _status = ProxyStatus.failed;
        _statusError = error.toString();
      });
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _trafficTimer?.cancel();
    _statusNotifier.dispose();
    _coreBusy.dispose();
    _settingsBusy.dispose();
    super.dispose();
  }

  Future<void> _showUsageNoticeIfNeeded() async {
    try {
      final accepted = await _service.getUsageNoticeAccepted();
      if (!mounted || accepted) return;

      var confirmed = false;
      var saving = false;

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => PopScope(
            canPop: false,
            child: AlertDialog(
              icon: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Theme.of(dialogContext).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.policy_outlined,
                  size: 30,
                  color: Theme.of(dialogContext).colorScheme.onPrimaryContainer,
                ),
              ),
              title: const Text('使用声明与合规承诺', textAlign: TextAlign.center),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '使用 Mclash 前，请认真阅读以下声明：',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 14),
                      const _UsageNoticeItem(
                        icon: Icons.code_rounded,
                        title: '完全透明开源',
                        body: '本项目完全透明开源，构建脚本和完整项目源码均随发布包提供，'
                            '可供审查、学习、修改和自行编译。',
                      ),
                      const _UsageNoticeItem(
                        icon: Icons.verified_user_outlined,
                        title: '仅限合法用途',
                        body: '仅可用于学习研究、软件开发、网络调试、个人隐私保护，'
                            '以及已经获得明确授权的网络和设备。',
                      ),
                      const _UsageNoticeItem(
                        icon: Icons.block_outlined,
                        title: '禁止违法滥用',
                        body: '禁止用于未经授权的入侵、攻击、扫描、诈骗、窃取数据、'
                            '侵犯隐私、传播违法内容或其他违法活动。',
                        warning: true,
                      ),
                      const _UsageNoticeItem(
                        icon: Icons.info_outline,
                        title: '责任说明',
                        body: '本项目不提供节点、订阅或内容服务。使用者应遵守法律法规，'
                            '并自行承担配置和使用行为产生的责任。',
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: confirmed,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          '我已阅读、理解并同意遵守以上声明',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onChanged: saving
                            ? null
                            : (value) {
                                setDialogState(
                                  () => confirmed = value ?? false,
                                );
                              },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('不同意并退出'),
                ),
                FilledButton(
                  onPressed: !confirmed || saving
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          try {
                            await _service.acceptUsageNotice();
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop(true);
                          } catch (error) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => saving = false);
                            AppNotice.show(
                              dialogContext,
                              '保存声明状态失败：$error',
                              error: true,
                            );
                          }
                        },
                  child: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('同意并继续'),
                ),
              ],
            ),
          ),
        ),
      );

      if (result != true) {
        exit(0);
      }
    } catch (error) {
      if (!mounted) return;
      _showError('读取使用声明状态失败：$error');
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    await _pollStatus();
    try {
      final config = await _service.getConfigInfo();
      final debugLoggingEnabled = await _service.getDebugLoggingEnabled();
      final serviceAutoStartEnabled =
          await _service.getServiceAutoStartEnabled();
      final ipv6Enabled = await _service.getIpv6Enabled();
      final bypassLanEnabled = await _service.getBypassLanEnabled();
      final networkMode = await _service.getNetworkMode();
      final coreType = await _service.getCoreType();
      if (_status != ProxyStatus.failed) await _service.syncSystemProxy();
      if (!mounted) return;
      setState(() {
        _config = config;
        _debugLoggingEnabled = debugLoggingEnabled;
        _serviceAutoStartEnabled = serviceAutoStartEnabled;
        _ipv6Enabled = ipv6Enabled;
        _bypassLanEnabled = bypassLanEnabled;
        _networkMode = networkMode;
        _coreType = coreType;
      });
      if (_status == ProxyStatus.running) await _loadProxyMode();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _updateTrafficSpeed() async {
    if (_samplingTraffic || !mounted) return;
    if (_status != ProxyStatus.running) {
      if (_downloadBytesPerSecond != 0 || _uploadBytesPerSecond != 0) {
        setState(() {
          _downloadBytesPerSecond = 0;
          _uploadBytesPerSecond = 0;
        });
      }
      return;
    }
    _samplingTraffic = true;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..findProxy = (_) => 'DIRECT';
    try {
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:9090/traffic'));
      final response =
          await request.close().timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return;
      final line = await response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 3));
      final stats = jsonDecode(line) as Map;
      if (!mounted || _status != ProxyStatus.running) return;
      setState(() {
        _downloadBytesPerSecond = (stats['down'] as num? ?? 0).toDouble();
        _uploadBytesPerSecond = (stats['up'] as num? ?? 0).toDouble();
      });
    } catch (_) {
      // The controller may be unavailable while the service is restarting.
    } finally {
      client.close(force: true);
      _samplingTraffic = false;
    }
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    if (bytesPerSecond >= 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${bytesPerSecond.toStringAsFixed(0)} B/s';
  }

  Future<Map<String, dynamic>> _proxyControllerRequest(
    String method, {
    Map<String, Object>? body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:9090/configs'),
      );
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
            const Duration(seconds: 8),
          );
      final text = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Controller ${response.statusCode}: ${text.trim()}');
      }
      if (text.trim().isEmpty) return const <String, dynamic>{};
      final decoded = jsonDecode(text);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
    } finally {
      client.close(force: true);
    }
  }

  String _normalProxyMode(String mode) => switch (mode) {
        'global' => 'global',
        'direct' => 'direct',
        _ => 'rule',
      };

  Future<void> _loadProxyMode() async {
    try {
      final configs = await _proxyControllerRequest('GET');
      final mode = configs['mode']?.toString().toLowerCase();
      if (!mounted || mode == null) return;
      setState(() => _proxyMode = _normalProxyMode(mode));
    } catch (_) {
      // Keep the last known mode while mihomo is still becoming available.
    }
  }

  Future<void> _setProxyMode(String mode) async {
    if (!_canOperate || _status != ProxyStatus.running || mode == _proxyMode) {
      return;
    }
    final previous = _proxyMode;
    setState(() {
      _changingProxyMode = true;
      _proxyMode = mode;
    });
    try {
      final status = await _service.getProxyStatus();
      if (!mounted) return;
      if (status != ProxyStatus.running) {
        setState(() {
          _status = status;
          _proxyMode = previous;
        });
        return;
      }
      await _proxyControllerRequest(
        'PATCH',
        body: <String, Object>{'mode': mode},
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _proxyMode = previous);
      _showError(error);
    } finally {
      if (mounted) setState(() => _changingProxyMode = false);
    }
  }

  Future<bool> _confirmStopped() async {
    late final ProxyStatus status;
    try {
      status =
          await _service.getProxyStatus().timeout(const Duration(seconds: 12));
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = ProxyStatus.failed;
          _statusError = error.toString();
        });
      }
      rethrow;
    }
    if (!mounted) return false;
    setState(() => _status = status);
    if (status == ProxyStatus.stopped) return true;
    _showError('请先停止代理再修改设置');
    return false;
  }

  Future<void> _changeSetting(Future<void> Function() action) async {
    if (!_canEditSettings) return;
    setState(() => _settingsBusy.value = true);
    try {
      if (!await _confirmStopped()) return;
      await action();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _settingsBusy.value = false);
    }
  }

  Future<void> _switchRunMode(CoreType core, NetworkMode target) async {
    if (!_canEditSettings) return;
    if (target == _networkMode && core == _coreType) return;
    await _changeSetting(() async {
      await _service.setCoreType(core);
      await _service.setNetworkMode(target);
      await _service.syncSystemProxy();
      if (!mounted) return;
      setState(() {
        _networkMode = target;
        _coreType = core;
      });
      AppNotice.show(
          context, '已切换到 ${target == NetworkMode.tun ? 'TUN' : '系统代理'}');
    });
  }

  Future<void> _showGeneralSettings() async {
    if (!_canEditSettings) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AnimatedBuilder(
        animation:
            Listenable.merge([_statusNotifier, _coreBusy, _settingsBusy]),
        builder: (_, child) => PopScope(
          canPop: !_settingsBusy.value,
          child: AlertDialog(
            title: const Text('常规设置'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    secondary: const Icon(Icons.power_settings_new_rounded),
                    title: const Text('开机自启',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    value: _serviceAutoStartEnabled,
                    onChanged: !_canEditSettings
                        ? null
                        : (enabled) => _changeSetting(() async {
                              await _service
                                  .setServiceAutoStartEnabled(enabled);
                              if (mounted) {
                                setState(
                                    () => _serviceAutoStartEnabled = enabled);
                              }
                            }),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    secondary: const Icon(Icons.language_rounded),
                    title: const Text('启用 IPv6',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('允许代理内核使用 IPv6 网络'),
                    value: _ipv6Enabled,
                    onChanged: !_canEditSettings
                        ? null
                        : (enabled) => _changeSetting(() async {
                              await _service.setIpv6Enabled(enabled);
                              if (mounted) {
                                setState(() => _ipv6Enabled = enabled);
                              }
                            }),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    secondary: const Icon(Icons.lan_outlined),
                    title: const Text('绕过局域网',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('局域网和私有地址不经过代理'),
                    value: _bypassLanEnabled,
                    onChanged: !_canEditSettings
                        ? null
                        : (enabled) => _changeSetting(() async {
                              await _service.setBypassLanEnabled(enabled);
                              await _service.syncSystemProxy();
                              if (mounted) {
                                setState(() => _bypassLanEnabled = enabled);
                              }
                            }),
                  ),
                ]),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: _settingsBusy.value
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRunModeDialog() async {
    if (!_canEditSettings) return;
    final current = switch ((_coreType, _networkMode)) {
      (CoreType.mihomo, NetworkMode.tun) => _RunModeChoice.mihomoTun,
      (CoreType.mihomo, NetworkMode.proxy) => _RunModeChoice.mihomoProxy,
    };
    final selected = await showDialog<_RunModeChoice>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation:
            Listenable.merge([_statusNotifier, _coreBusy, _settingsBusy]),
        builder: (_, child) => AlertDialog(
          title: const Text('选择运行模式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(current == _RunModeChoice.mihomoTun
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                onTap: !_canEditSettings
                    ? null
                    : () => Navigator.of(dialogContext)
                        .pop(_RunModeChoice.mihomoTun),
                title: const Text('TUN'),
              ),
              ListTile(
                leading: Icon(current == _RunModeChoice.mihomoProxy
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                onTap: !_canEditSettings
                    ? null
                    : () => Navigator.of(dialogContext)
                        .pop(_RunModeChoice.mihomoProxy),
                title: const Text('系统代理'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted || !_canEditSettings) return;
    const core = CoreType.mihomo;
    final mode = selected == _RunModeChoice.mihomoTun
        ? NetworkMode.tun
        : NetworkMode.proxy;
    await _switchRunMode(core, mode);
  }

  Future<void> _showCoreUpdate() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AnimatedBuilder(
        animation: Listenable.merge([_statusNotifier, _coreBusy]),
        builder: (_, child) => PopScope(
          canPop: !_coreBusy.value,
          child: AlertDialog(
            title: const Text('更新内核'),
            content: SizedBox(
                width: 440,
                child: SingleChildScrollView(child: _coreUpdateCard())),
            actions: [
              FilledButton(
                onPressed: _coreBusy.value
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runCoreOperation({required bool update}) async {
    if (!_canOperate || _status != ProxyStatus.running) return;
    setState(() {
      _coreUpdating = update;
      _coreMessage = null;
      _coreBusy.value = true;
    });
    try {
      _coreInfo = await _service.checkCoreUpdate(CoreType.mihomo);
      if (update && _coreInfo!.updateAvailable) {
        if (!mounted || _status != ProxyStatus.running) {
          throw StateError('代理已断开，请重新连接后更新');
        }
        await _service.updateCore(CoreType.mihomo);
        _coreMessage = 'mihomo 内核更新完成';
        // Read the installed version again; the pre-update snapshot is stale.
        try {
          _coreInfo = await _service.checkCoreUpdate(CoreType.mihomo);
        } catch (error) {
          _coreInfo = null;
          _coreMessage = '内核更新完成，但读取版本失败：$error';
        }
        await _pollStatus();
      } else {
        _coreMessage = _coreInfo!.updateAvailable ? '发现新版本' : '当前已是最新稳定版';
      }
    } catch (error) {
      if (mounted) {
        _coreMessage = '${update ? '更新' : '检测'}失败：$error';
        if (update) {
          await _showCoreUpdateFailure('mihomo', error);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _coreUpdating = false;
          _coreBusy.value = false;
        });
      }
    }
  }

  Widget _coreUpdateCard() {
    final enabled = _canOperate && _status == ProxyStatus.running;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('mihomo',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(_coreInfo == null
                    ? '尚未检测版本'
                    : '当前 ${_coreInfo!.currentVersion} / 官方 ${_coreInfo!.latestVersion}'),
                if (_coreBusy.value) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_coreUpdating ? '正在下载并更新内核，请勿关闭应用…' : '正在检测版本…'),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                    onPressed:
                        enabled ? () => _runCoreOperation(update: false) : null,
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('检测版本', maxLines: 1, softWrap: false)),
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: FilledButton(
                    onPressed:
                        enabled ? () => _runCoreOperation(update: true) : null,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_coreUpdating ? '正在更新…' : '更新内核',
                            maxLines: 1, softWrap: false)),
                  )),
                ]),
                if (_coreMessage != null) ...[
                  const SizedBox(height: 14),
                  SelectableText(_coreMessage!)
                ],
              ],
            )));
  }

  Future<void> _showCoreUpdateFailure(String name, Object error) async {
    String updateLog;
    if (!_debugLoggingEnabled) {
      updateLog = '调试日志未开启，本次更新未写入日志。';
    } else {
      try {
        updateLog = await _service.getDebugLogContent('update.log');
      } catch (logError) {
        updateLog = '读取 update.log 失败：$logError';
      }
    }
    if (!mounted) return;

    final lines = updateLog.trimRight().split('\n');
    final recentLog =
        (lines.length > 80 ? lines.sublist(lines.length - 80) : lines).join(
      '\n',
    );
    final logTitle = _debugLoggingEnabled ? '最近的 update.log' : '调试日志';
    final details = '错误：$error\n\n$logTitle：\n$recentLog';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$name 内核更新失败'),
        content: SizedBox(
          width: 640,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: SelectableText(
                details,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: details));
              if (!dialogContext.mounted) return;
              AppNotice.show(dialogContext, '失败日志已复制');
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制日志'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAbout() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    final buildSuffix =
        packageInfo.buildNumber.isEmpty ? '' : '+${packageInfo.buildNumber}';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('关于'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Mclash',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            Text('版本：${packageInfo.version}$buildSuffix'),
            const SizedBox(height: 14),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.code_rounded, size: 20),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '本项目完全透明开源，构建脚本与完整源码均随发布包提供。',
                    style: TextStyle(height: 1.45),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('开源地址', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Semantics(
              link: true,
              child: InkWell(
                onTap: () => _openSourceRepository(dialogContext),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'https://github.com/liuyi-htu/Mclash',
                    style: TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSourceRepository(BuildContext dialogContext) async {
    final opened = await launchUrl(
      Uri.parse('https://github.com/liuyi-htu/Mclash'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted && dialogContext.mounted) {
      AppNotice.show(dialogContext, '无法打开源码链接');
    }
  }

  Future<void> _toggle() async {
    if (!_canOperate) {
      return;
    }

    _operationGeneration++;
    try {
      if (_status == ProxyStatus.running) {
        setState(() => _status = ProxyStatus.stopping);
        _showOperationWaitDialog('正在停止代理', 3);
        try {
          await _service.stop();
        } finally {
          _closeOperationWaitDialog();
        }
        if (!mounted) return;
        await _statusAfterOperation();
        return;
      }

      if (!_config.exists) {
        _showError('请先上传 mihomo YAML 配置');
        return;
      }

      setState(() => _status = ProxyStatus.starting);
      _showOperationWaitDialog('正在启动代理', 5);
      try {
        await _service.start();
      } finally {
        _closeOperationWaitDialog();
      }
      if (!mounted) return;
      await _statusAfterOperation();
    } catch (error) {
      _closeOperationWaitDialog();
      if (!mounted) return;
      _showError(error);
      await _statusAfterOperation();
    }
  }

  void _showOperationWaitDialog(String title, int seconds) {
    _operationDialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text('预计约 $seconds 秒'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ).whenComplete(() => _operationDialogOpen = false),
    );
  }

  void _closeOperationWaitDialog() {
    if (!_operationDialogOpen || !mounted) return;
    _operationDialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _showDebugLogSettings() async {
    var enabled = _debugLoggingEnabled;
    late final List<DebugLogFile> logs;
    try {
      logs = await _service.getDebugLogs();
    } catch (error) {
      if (mounted) _showError(error);
      return;
    }
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation:
            Listenable.merge([_statusNotifier, _coreBusy, _settingsBusy]),
        builder: (_, child) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('调试日志'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用调试日志'),
                    value: enabled,
                    onChanged: !_canEditSettings
                        ? null
                        : (value) => _changeSetting(() async {
                              await _service.setDebugLoggingEnabled(value);
                              if (!mounted) return;
                              setState(() => _debugLoggingEnabled = value);
                              if (dialogContext.mounted) {
                                setDialogState(() => enabled = value);
                              }
                            }),
                  ),
                  const Divider(height: 24),
                  for (final log in logs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        log.id == 'update.log'
                            ? Icons.system_update_alt_rounded
                            : log.id == 'mihomo.log'
                                ? Icons.memory_rounded
                                : Icons.settings_applications_outlined,
                      ),
                      title: Text(log.displayName),
                      subtitle: Text(log.description),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showDebugLog(log),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: !_canEditSettings
                    ? null
                    : () => Navigator.of(dialogContext).pop('clear'),
                icon: const Icon(Icons.delete_outline),
                label: const Text('清除'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'clear') {
      await _confirmClearDebugLogs();
    }
  }

  Future<void> _confirmClearDebugLogs() async {
    if (!_canEditSettings) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AnimatedBuilder(
            animation:
                Listenable.merge([_statusNotifier, _coreBusy, _settingsBusy]),
            builder: (_, child) => AlertDialog(
              title: const Text('清除调试日志'),
              content: const Text(
                '将清空服务日志、mihomo 日志和内核更新日志。'
                '此操作不会删除配置文件。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: !_canEditSettings
                      ? null
                      : () => Navigator.of(dialogContext).pop(true),
                  child: const Text('清除'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!confirmed) return;

    await _changeSetting(() async {
      await _service.clearDebugLogs();
      if (!mounted) return;
      AppNotice.show(context, '调试日志已清除');
    });
  }

  Future<void> _showDebugLog(DebugLogFile file) async {
    try {
      final log = await _service.getDebugLogContent(file.id);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(file.displayName),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
                child: SelectableText(
                  log,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: log));
                if (!dialogContext.mounted) return;
                AppNotice.show(dialogContext, '日志已复制');
              },
              icon: const Icon(Icons.copy),
              label: const Text('复制'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  void _showError(Object error) {
    AppNotice.show(context, error.toString(), error: true);
  }

  String get _statusText => switch (_status) {
        ProxyStatus.checking => '检测中',
        ProxyStatus.recovering => '恢复中',
        ProxyStatus.failed => '检测失败',
        ProxyStatus.stopped => '未启动',
        ProxyStatus.starting => '正在启动',
        ProxyStatus.running => '运行中',
        ProxyStatus.stopping => '正在停止',
      };

  @override
  Widget build(BuildContext context) {
    final busy = _coreBusy.value ||
        (_status != ProxyStatus.running &&
            _status != ProxyStatus.stopped &&
            _status != ProxyStatus.failed);
    final running = _status == ProxyStatus.running;

    final tab = _selectedHomeTab;
    final navIndex = const [0, 2, 3, 1][tab];

    void handleDestination(int index) {
      if (index == _selectedHomeTab) return;
      setState(() => _selectedHomeTab = index);
      if (index == 0) _refresh();
    }

    return Scaffold(
      appBar: tab == 3
          ? null
          : AppBar(
              title: Text(
                'Mclash',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                ),
              ),
            ),
      body: PulseNavigation(
        index: navIndex,
        onSelected: (index) => handleDestination(const [0, 3, 1, 2][index]),
        child: IndexedStack(
          index: tab,
          children: [
            PulseDashboard(
              running: running,
              busy: busy || !_canOperate,
              status: _statusText,
              detail: _statusError == null ? null : '状态检测失败：$_statusError',
              download: _formatSpeed(_downloadBytesPerSecond),
              upload: _formatSpeed(_uploadBytesPerSecond),
              mode: _proxyMode,
              changingMode: _changingProxyMode,
              onToggle: _toggle,
              onMode: _setProxyMode,
              onRefresh: _refresh,
            ),
            ConfigPage(
                proxyRunning: _status != ProxyStatus.stopped,
                service: _service,
                proxyStatus: _statusNotifier),
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                const AppearanceTile(),
                const SizedBox(height: 16),
                ...[
                  SettingsCard(
                      icon: Icons.tune_rounded,
                      title: '常规设置',
                      onTap: _canEditSettings ? _showGeneralSettings : null),
                  const SizedBox(height: 12),
                  SettingsCard(
                      icon: Icons.swap_horiz_rounded,
                      title: '运行模式',
                      onTap: _canEditSettings ? _showRunModeDialog : null,
                      subtitle:
                          _networkMode == NetworkMode.proxy ? '系统代理' : 'TUN'),
                  const SizedBox(height: 12),
                  SettingsCard(
                      icon: Icons.article_outlined,
                      title: '调试日志',
                      onTap: _showDebugLogSettings),
                  const SizedBox(height: 12),
                  SettingsCard(
                      icon: Icons.system_update_alt_rounded,
                      title: '更新内核',
                      onTap: _showCoreUpdate),
                  const SizedBox(height: 12),
                  SettingsCard(
                      icon: Icons.info_outline_rounded,
                      title: '关于 Mclash',
                      onTap: _showAbout),
                  const SizedBox(height: 12),
                ],
              ],
            ),
            tab == 3
                ? ProxyPanelPage(proxyRunning: running, service: _service)
                : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width >= 720
          ? null
          : NavigationBar(
              selectedIndex: navIndex,
              onDestinationSelected: (index) =>
                  handleDestination(const [0, 3, 1, 2][index]),
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: '首页',
                ),
                const NavigationDestination(
                    icon: Icon(Icons.hub_outlined), label: '代理'),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  label: '配置',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: '设置',
                ),
              ],
            ),
    );
  }
}

class _UsageNoticeItem extends StatelessWidget {
  const _UsageNoticeItem({
    required this.icon,
    required this.title,
    required this.body,
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = warning ? colors.error : colors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: warning ? colors.error : colors.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    height: 1.45,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
