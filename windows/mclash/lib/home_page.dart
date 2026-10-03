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

  ProxyStatus _status = ProxyStatus.stopped;
  ConfigInfo _config = const ConfigInfo(exists: false);
  bool _debugLoggingEnabled = false;
  bool _serviceAutoStartEnabled = false;
  bool _ipv6Enabled = false;
  bool _bypassLanEnabled = true;
  NetworkMode _networkMode = NetworkMode.proxy;
  CoreType _coreType = CoreType.mihomo;
  bool _switchingMode = false;
  bool _operationDialogOpen = false;
  Timer? _statusTimer;
  Timer? _trafficTimer;
  bool _samplingTraffic = false;
  int _selectedHomeTab = 0;
  double _downloadBytesPerSecond = 0;
  double _uploadBytesPerSecond = 0;
  String _proxyMode = 'rule';
  bool _changingProxyMode = false;

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

  Future<void> _pollStatus() async {
    try {
      final running = await _service.isRunning();
      if (!mounted ||
          _status == ProxyStatus.starting ||
          _status == ProxyStatus.stopping) {
        return;
      }
      final next = running ? ProxyStatus.running : ProxyStatus.stopped;
      if (_status != next) {
        if (!running) await _service.syncSystemProxy();
        if (mounted) {
          setState(() => _status = next);
          if (running) unawaited(_loadProxyMode());
        }
      }
    } catch (_) {
      // Transient SCM/controller failures are reported by explicit actions.
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _trafficTimer?.cancel();
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
    try {
      final config = await _service.getConfigInfo();
      final running = await _service.isRunning();
      final debugLoggingEnabled = await _service.getDebugLoggingEnabled();
      final serviceAutoStartEnabled =
          await _service.getServiceAutoStartEnabled();
      final ipv6Enabled = await _service.getIpv6Enabled();
      final bypassLanEnabled = await _service.getBypassLanEnabled();
      final networkMode = await _service.getNetworkMode();
      final coreType = await _service.getCoreType();
      await _service.syncSystemProxy();
      if (!mounted) return;
      setState(() {
        _config = config;
        _status = running ? ProxyStatus.running : ProxyStatus.stopped;
        _debugLoggingEnabled = debugLoggingEnabled;
        _serviceAutoStartEnabled = serviceAutoStartEnabled;
        _ipv6Enabled = ipv6Enabled;
        _bypassLanEnabled = bypassLanEnabled;
        _networkMode = networkMode;
        _coreType = coreType;
      });
      if (running) await _loadProxyMode();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _openProxyPanel() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) =>
          ProxyPanelPage(proxyRunning: _status == ProxyStatus.running),
    ));
    await _refresh();
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
    if (_changingProxyMode || mode == _proxyMode) return;
    final previous = _proxyMode;
    setState(() {
      _changingProxyMode = true;
      _proxyMode = mode;
    });
    try {
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

  Future<void> _showProxyModeDialog() async {
    if (_changingProxyMode || _status != ProxyStatus.running) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;

        Widget modeOption({
          required String value,
          required String title,
          required IconData icon,
        }) {
          final selected = value == _proxyMode;
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Material(
              color: selected
                  ? colors.primary.withValues(alpha: 0.12)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(dialogContext).pop(value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 17,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.11),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: colors.primary, size: 23),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check_circle_rounded, color: colors.primary),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 32,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '选择运行模式',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  modeOption(
                    value: 'rule',
                    title: '规则模式',
                    icon: Icons.route_outlined,
                  ),
                  modeOption(
                    value: 'global',
                    title: '全局模式',
                    icon: Icons.public_rounded,
                  ),
                  modeOption(
                    value: 'direct',
                    title: '直连模式',
                    icon: Icons.link_rounded,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) await _setProxyMode(selected);
  }

  String _normalProxyMode(String mode) => switch (mode) {
        'global' => 'global',
        'direct' => 'direct',
        _ => 'rule',
      };

  String get _proxyModeLabel => switch (_proxyMode) {
        'global' => '全局',
        'direct' => '直连',
        _ => '规则',
      };

  Future<void> _switchRunMode(CoreType core, NetworkMode target) async {
    if (_switchingMode ||
        _status == ProxyStatus.starting ||
        _status == ProxyStatus.stopping) {
      return;
    }
    if (target == _networkMode && core == _coreType) return;
    final wasRunning = _status == ProxyStatus.running;
    setState(() => _switchingMode = true);
    if (wasRunning) {
      _showOperationWaitDialog('正在切换运行模式', 8);
    }
    try {
      await _service.setCoreType(core);
      await _service.setNetworkMode(target);
      if (wasRunning) {
        await _service.restart();
      } else {
        await _service.syncSystemProxy();
      }
      if (!mounted) return;
      setState(() {
        _networkMode = target;
        _coreType = core;
        _status = wasRunning ? ProxyStatus.running : _status;
      });
      AppNotice.show(
        context,
        '已切换到 mihomo + '
        '${target == NetworkMode.tun ? 'TUN' : '系统代理'}',
      );
    } catch (error) {
      if (!mounted) return;
      _showError('切换模式失败：$error');
    } finally {
      if (wasRunning) {
        _closeOperationWaitDialog();
      }
      if (mounted) {
        setState(() => _switchingMode = false);
      }
    }
  }

  Future<void> _showGeneralSettings() async {
    var changingAutoStart = false;
    var changingIpv6 = false;
    var changingBypassLan = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            children: [
              Text(
                '常规设置',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                secondary: const Icon(Icons.power_settings_new_rounded),
                title: const Text(
                  '开机自启',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                value: _serviceAutoStartEnabled,
                onChanged: changingAutoStart
                    ? null
                    : (enabled) async {
                        setSheetState(() => changingAutoStart = true);
                        try {
                          await _service.setServiceAutoStartEnabled(enabled);
                          if (mounted) {
                            setState(() => _serviceAutoStartEnabled = enabled);
                          }
                        } catch (error) {
                          if (mounted) _showError('修改服务开机自启失败：$error');
                        } finally {
                          if (sheetContext.mounted) {
                            setSheetState(() => changingAutoStart = false);
                          }
                        }
                      },
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                secondary: const Icon(Icons.language_rounded),
                title: const Text(
                  '启用 IPv6',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('允许代理内核使用 IPv6 网络'),
                value: _ipv6Enabled,
                onChanged: changingIpv6
                    ? null
                    : (enabled) async {
                        setSheetState(() => changingIpv6 = true);
                        try {
                          await _service.setIpv6Enabled(enabled);
                          if (_status == ProxyStatus.running) {
                            await _service.restart();
                          }
                          if (mounted) {
                            setState(() => _ipv6Enabled = enabled);
                          }
                        } catch (error) {
                          if (mounted) _showError('修改 IPv6 设置失败：$error');
                        } finally {
                          if (sheetContext.mounted) {
                            setSheetState(() => changingIpv6 = false);
                          }
                        }
                      },
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                secondary: const Icon(Icons.lan_outlined),
                title: const Text(
                  '绕过局域网',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('局域网和私有地址不经过代理'),
                value: _bypassLanEnabled,
                onChanged: changingBypassLan
                    ? null
                    : (enabled) async {
                        setSheetState(() => changingBypassLan = true);
                        try {
                          await _service.setBypassLanEnabled(enabled);
                          if (_status == ProxyStatus.running) {
                            await _service.restart();
                          } else {
                            await _service.syncSystemProxy();
                          }
                          if (mounted) {
                            setState(() => _bypassLanEnabled = enabled);
                          }
                        } catch (error) {
                          if (mounted) _showError('修改局域网绕过设置失败：$error');
                        } finally {
                          if (sheetContext.mounted) {
                            setSheetState(() => changingBypassLan = false);
                          }
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRunModeDialog() async {
    final current = switch ((_coreType, _networkMode)) {
      (CoreType.mihomo, NetworkMode.tun) => _RunModeChoice.mihomoTun,
      (CoreType.mihomo, NetworkMode.proxy) => _RunModeChoice.mihomoProxy,
    };
    final selected = await showDialog<_RunModeChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('选择运行模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(current == _RunModeChoice.mihomoTun
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              onTap: () =>
                  Navigator.of(dialogContext).pop(_RunModeChoice.mihomoTun),
              title: const Text('TUN'),
            ),
            ListTile(
              leading: Icon(current == _RunModeChoice.mihomoProxy
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              onTap: () =>
                  Navigator.of(dialogContext).pop(_RunModeChoice.mihomoProxy),
              title: const Text('系统代理'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    const core = CoreType.mihomo;
    final mode = selected == _RunModeChoice.mihomoTun
        ? NetworkMode.tun
        : NetworkMode.proxy;
    await _switchRunMode(core, mode);
  }

  Future<void> _showCoreUpdate() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '更新内核',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              _coreUpdateCard(sheetContext, CoreType.mihomo, 'mihomo'),
              const SizedBox(height: 14),
              const Center(child: Text('更新会先完成下载，再自动停止代理、替换内核并恢复运行。')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coreUpdateCard(BuildContext context, CoreType core, String name) {
    CoreUpdateInfo? info;
    var busy = false;
    var updating = false;
    return StatefulBuilder(
      builder: (context, setCardState) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  info == null
                      ? '尚未检测版本'
                      : '当前 ${info!.currentVersion} / 官方 ${info!.latestVersion}',
                ),
                if (updating) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('正在下载并更新内核，请勿关闭应用…'),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy
                            ? null
                            : () async {
                                setCardState(() => busy = true);
                                try {
                                  info = await _service.checkCoreUpdate(core);
                                } catch (error) {
                                  if (mounted) _showError(error);
                                }
                                if (context.mounted) {
                                  setCardState(() => busy = false);
                                }
                              },
                        child: const Text('检测版本'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ||
                                _status == ProxyStatus.starting ||
                                _status == ProxyStatus.stopping
                            ? null
                            : () async {
                                setCardState(() {
                                  busy = true;
                                  updating = true;
                                });
                                try {
                                  info ??= await _service.checkCoreUpdate(core);
                                  await _service.updateCore(core);
                                  if (mounted) {
                                    AppNotice.show(
                                      this.context,
                                      '$name 内核更新完成',
                                    );
                                  }
                                } catch (error) {
                                  if (mounted) {
                                    await _showCoreUpdateFailure(name, error);
                                  }
                                }
                                if (context.mounted) {
                                  setCardState(() {
                                    busy = false;
                                    updating = false;
                                  });
                                }
                              },
                        child: Text(updating ? '正在更新…' : '更新内核'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
    if (_status == ProxyStatus.starting || _status == ProxyStatus.stopping) {
      return;
    }

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
        setState(() => _status = ProxyStatus.stopped);
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
      setState(() => _status = ProxyStatus.running);
      unawaited(_loadProxyMode());
    } catch (error) {
      _closeOperationWaitDialog();
      if (!mounted) return;
      setState(() => _status = ProxyStatus.stopped);
      _showError(error);
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
      builder: (dialogContext) => StatefulBuilder(
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
                  onChanged: (value) async {
                    try {
                      await _service.setDebugLoggingEnabled(value);
                      if (!mounted) return;
                      setState(() => _debugLoggingEnabled = value);
                      setDialogState(() => enabled = value);
                    } catch (error) {
                      if (!mounted) return;
                      _showError(error);
                    }
                  },
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
              onPressed: () => Navigator.of(dialogContext).pop('clear'),
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
    );

    if (!mounted) return;
    if (action == 'clear') {
      await _confirmClearDebugLogs();
    }
  }

  Future<void> _confirmClearDebugLogs() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
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
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('清除'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await _service.clearDebugLogs();
      if (!mounted) return;
      AppNotice.show(context, '调试日志已清除');
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
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
        ProxyStatus.stopped => '未启动',
        ProxyStatus.starting => '正在启动',
        ProxyStatus.running => '运行中',
        ProxyStatus.stopping => '正在停止',
      };

  @override
  Widget build(BuildContext context) {
    final busy =
        _status == ProxyStatus.starting || _status == ProxyStatus.stopping;
    final colors = Theme.of(context).colorScheme;
    final running = _status == ProxyStatus.running;

    void handleDestination(int index) {
      if (index == _selectedHomeTab) return;
      setState(() => _selectedHomeTab = index);
      if (index == 0) _refresh();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mclash',
          style: TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedHomeTab,
        children: [
          RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 18, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: running
                          ? const [Color(0xFF3167F4), Color(0xFF4938EE)]
                          : const [Color(0xFF51627E), Color(0xFF303B55)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: (running
                                ? const Color(0xFF356AE6)
                                : const Color(0xFF202B45))
                            .withValues(alpha: 0.20),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Icon(
                                  running
                                      ? Icons.verified_user_rounded
                                      : Icons.shield_outlined,
                                  color: Colors.white,
                                  size: 29,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      running ? '已连接' : _statusText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _config.exists
                                          ? (_config.fileName ?? '未命名配置')
                                          : '尚未选择配置',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (busy)
                                const SizedBox.square(
                                  dimension: 26,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              else
                                Switch(
                                  value: running,
                                  onChanged: (_) => _toggle(),
                                  activeThumbColor: const Color(0xFF315FE8),
                                  activeTrackColor: Colors.white,
                                  inactiveThumbColor: Colors.white,
                                  inactiveTrackColor: Colors.white.withValues(
                                    alpha: 0.28,
                                  ),
                                  trackOutlineColor:
                                      const WidgetStatePropertyAll(
                                    Colors.transparent,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 19),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _TrafficSpeed(
                                    icon: Icons.arrow_downward_rounded,
                                    value: _formatSpeed(
                                      _downloadBytesPerSecond,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 26,
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                                Expanded(
                                  child: _TrafficSpeed(
                                    icon: Icons.arrow_upward_rounded,
                                    value: _formatSpeed(_uploadBytesPerSecond),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _HomeActionTile(
                        icon: Icons.hub_outlined,
                        title: '代理面板',
                        onTap: _openProxyPanel,
                      ),
                      const Divider(height: 1, indent: 64),
                      _HomeActionTile(
                        icon: Icons.route_outlined,
                        title: '代理规则',
                        trailing: _changingProxyMode
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                running ? '$_proxyModeLabel模式' : '启动代理后可切换',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                        onTap: running && !_changingProxyMode
                            ? _showProxyModeDialog
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ConfigPage(
              proxyRunning: _status != ProxyStatus.stopped, service: _service),
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  _HomeActionTile(
                      icon: Icons.tune_rounded,
                      title: '常规设置',
                      onTap: _showGeneralSettings),
                  const Divider(height: 1, indent: 64),
                  _HomeActionTile(
                      icon: Icons.swap_horiz_rounded,
                      title: '运行模式',
                      trailing: Text(
                          _networkMode == NetworkMode.proxy ? '系统代理' : 'TUN'),
                      onTap:
                          busy || _switchingMode ? null : _showRunModeDialog),
                  const Divider(height: 1, indent: 64),
                  _HomeActionTile(
                      icon: Icons.article_outlined,
                      title: '调试日志',
                      onTap: _showDebugLogSettings),
                ]),
              ),
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  _HomeActionTile(
                      icon: Icons.system_update_alt_rounded,
                      title: '更新内核',
                      onTap: _showCoreUpdate),
                  const Divider(height: 1, indent: 64),
                  _HomeActionTile(
                      icon: Icons.info_outline_rounded,
                      title: '关于 Mclash',
                      onTap: _showAbout),
                ]),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedHomeTab,
        onDestinationSelected: handleDestination,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
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

class _TrafficSpeed extends StatelessWidget {
  const _TrafficSpeed({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 17, color: Colors.white.withValues(alpha: 0.76)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeActionTile extends StatelessWidget {
  const _HomeActionTile({
    this.icon,
    this.leading,
    required this.title,
    this.trailing,
    this.onTap,
  }) : assert(icon != null || leading != null);

  final IconData? icon;
  final Widget? leading;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 15, 18),
        child: Row(
          children: [
            leading ??
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: colors.primary, size: 25),
                ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
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
