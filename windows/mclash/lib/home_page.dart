import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_notice.dart';
import 'config_page.dart';
import 'models.dart';
import 'native_proxy_service.dart';

enum _HomeMenuAction { config, generalSettings }

enum _RunModeChoice { mihomoTun, mihomoProxy, singBoxTun, singBoxProxy }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _service = NativeProxyService.instance;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _showUsageNoticeIfNeeded();
      await _refresh();
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
        if (mounted) setState(() => _status = next);
      }
    } catch (_) {
      // Transient SCM/controller failures are reported by explicit actions.
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
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
                        body:
                            '本项目完全透明开源，构建脚本和完整项目源码均随发布包提供，'
                            '可供审查、学习、修改和自行编译。',
                      ),
                      const _UsageNoticeItem(
                        icon: Icons.verified_user_outlined,
                        title: '仅限合法用途',
                        body:
                            '仅可用于学习研究、软件开发、网络调试、个人隐私保护，'
                            '以及已经获得明确授权的网络和设备。',
                      ),
                      const _UsageNoticeItem(
                        icon: Icons.block_outlined,
                        title: '禁止违法滥用',
                        body:
                            '禁止用于未经授权的入侵、攻击、扫描、诈骗、窃取数据、'
                            '侵犯隐私、传播违法内容或其他违法活动。',
                        warning: true,
                      ),
                      const _UsageNoticeItem(
                        icon: Icons.info_outline,
                        title: '责任说明',
                        body:
                            '本项目不提供节点、订阅或内容服务。使用者应遵守法律法规，'
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
      final serviceAutoStartEnabled = await _service
          .getServiceAutoStartEnabled();
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
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _openConfigPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ConfigPage(proxyRunning: _status != ProxyStatus.stopped),
      ),
    );
    await _refresh();
  }

  Future<void> _openProxyBoard() async {
    const url = 'https://board.zash.run.place/#/proxies';
    try {
      await Process.start('explorer.exe', const [
        url,
      ], mode: ProcessStartMode.detached);
    } catch (error) {
      if (mounted) _showError('打开代理面板失败：$error');
    }
  }

  Future<void> _handleMenuAction(_HomeMenuAction action) async {
    switch (action) {
      case _HomeMenuAction.config:
        await _openConfigPage();
        return;
      case _HomeMenuAction.generalSettings:
        await _showGeneralSettings();
        return;
    }
  }

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
        '已切换到 ${core == CoreType.mihomo ? 'mihomo' : 'sing-box'} + '
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
              _settingsTile(
                context: sheetContext,
                icon: Icons.swap_horiz_rounded,
                title: '运行模式',
                subtitle:
                    '${_coreType == CoreType.mihomo ? 'mihomo' : 'sing-box'} + '
                    '${_networkMode == NetworkMode.proxy ? '系统代理' : 'TUN'}',
                onTap: _showRunModeDialog,
              ),
              _settingsTile(
                context: sheetContext,
                icon: Icons.article_outlined,
                title: '调试日志',
                subtitle: _debugLoggingEnabled ? '已启用' : '已关闭',
                onTap: _showDebugLogSettings,
              ),
              _settingsTile(
                context: sheetContext,
                icon: Icons.system_update_alt_rounded,
                title: '更新内核',
                onTap: _showCoreUpdate,
              ),
              _settingsTile(
                context: sheetContext,
                icon: Icons.info_outline_rounded,
                title: '关于',
                subtitle: 'Mclash 开源信息',
                onTap: _showAbout,
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
      (CoreType.singBox, NetworkMode.tun) => _RunModeChoice.singBoxTun,
      (CoreType.singBox, NetworkMode.proxy) => _RunModeChoice.singBoxProxy,
    };
    final selected = await showDialog<_RunModeChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('选择运行模式'),
        content: RadioGroup<_RunModeChoice>(
          groupValue: current,
          onChanged: (value) => Navigator.of(dialogContext).pop(value),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<_RunModeChoice>(
                value: _RunModeChoice.mihomoTun,
                title: Text('mihomo + TUN'),
              ),
              RadioListTile<_RunModeChoice>(
                value: _RunModeChoice.mihomoProxy,
                title: Text('mihomo + 系统代理'),
              ),
              RadioListTile<_RunModeChoice>(
                value: _RunModeChoice.singBoxTun,
                title: Text('sing-box + TUN'),
              ),
              RadioListTile<_RunModeChoice>(
                value: _RunModeChoice.singBoxProxy,
                title: Text('sing-box + 系统代理'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final core = switch (selected) {
      _RunModeChoice.mihomoTun || _RunModeChoice.mihomoProxy => CoreType.mihomo,
      _RunModeChoice.singBoxTun ||
      _RunModeChoice.singBoxProxy => CoreType.singBox,
    };
    final mode = switch (selected) {
      _RunModeChoice.mihomoTun || _RunModeChoice.singBoxTun => NetworkMode.tun,
      _RunModeChoice.mihomoProxy ||
      _RunModeChoice.singBoxProxy => NetworkMode.proxy,
    };
    await _switchRunMode(core, mode);
  }

  Widget _settingsTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    required Future<void> Function() onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colors.onPrimaryContainer),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () async {
        Navigator.of(context).pop();
        await onTap();
      },
    );
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
              const SizedBox(height: 12),
              _coreUpdateCard(sheetContext, CoreType.singBox, 'sing-box'),
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
                        onPressed:
                            busy ||
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
            const SelectableText(
              'https://github.com/liuyi-htu/Mclash-for-windows',
              style: TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Telegram group',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const SelectableText('https://telegram.me/+QqTdo3bY8eAyZmFl'),
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
                          : log.id == 'mihomo.log' || log.id == 'sing-box.log'
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
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('清除调试日志'),
            content: const Text(
              '将清空服务日志、mihomo 日志、sing-box 日志和内核更新日志。'
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

  String get _buttonText => switch (_status) {
    ProxyStatus.stopped => '启动代理',
    ProxyStatus.starting => '正在启动',
    ProxyStatus.running => '停止代理',
    ProxyStatus.stopping => '正在停止',
  };

  PopupMenuItem<_HomeMenuAction> _menuItem({
    required _HomeMenuAction value,
    required IconData icon,
    required String title,
    bool enabled = true,
  }) {
    final colors = Theme.of(context).colorScheme;
    return PopupMenuItem<_HomeMenuAction>(
      value: value,
      enabled: enabled,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy =
        _status == ProxyStatus.starting || _status == ProxyStatus.stopping;
    final colors = Theme.of(context).colorScheme;
    final running = _status == ProxyStatus.running;

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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: PopupMenuButton<_HomeMenuAction>(
              tooltip: '更多功能',
              onSelected: _handleMenuAction,
              offset: const Offset(0, 10),
              constraints: const BoxConstraints(minWidth: 150, maxWidth: 180),
              icon: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: colors.onPrimaryContainer,
                ),
              ),
              itemBuilder: (context) => [
                _menuItem(
                  value: _HomeMenuAction.config,
                  icon: Icons.description_outlined,
                  title: '配置文件',
                ),
                _menuItem(
                  value: _HomeMenuAction.generalSettings,
                  icon: Icons.settings_outlined,
                  title: '常规设置',
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: running
                      ? const [Color(0xFF356AE6), Color(0xFF5B8CFF)]
                      : const [Color(0xFF202B45), Color(0xFF42506D)],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color:
                        (running
                                ? const Color(0xFF356AE6)
                                : const Color(0xFF202B45))
                            .withValues(alpha: 0.20),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Icon(
                      running ? Icons.shield_rounded : Icons.shield_outlined,
                      size: 46,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          '当前配置',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _config.exists
                                ? (_config.fileName ?? '未命名配置')
                                : '未选择',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: busy ? null : _toggle,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: running
                            ? colors.error
                            : const Color(0xFF2859C5),
                        disabledBackgroundColor: Colors.white.withValues(
                          alpha: 0.72,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              running
                                  ? Icons.stop_circle_outlined
                                  : Icons.play_circle_outline_rounded,
                            ),
                      label: Text(_buttonText),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _openProxyBoard,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.38),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('代理面板'),
                    ),
                  ),
                ],
              ),
            ),
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
