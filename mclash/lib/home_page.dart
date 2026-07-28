import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_selector_page.dart';
import 'config_page.dart';
import 'device_registration_page.dart';
import 'models.dart';
import 'native_proxy_service.dart';
import 'proxy_panel_page.dart';
import 'top_notice.dart';

enum _HomeMenuAction { config, generalSettings }

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
  bool _developerModeEnabled = false;
  int _aboutTitleTapCount = 0;
  DateTime? _lastAboutTitleTap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _showUsageNoticeIfNeeded();
      await _loadDeveloperMode();
      await _refresh();
    });
  }

  Future<void> _loadDeveloperMode() async {
    try {
      final enabled = await _service.getDeveloperModeEnabled();
      if (mounted) setState(() => _developerModeEnabled = enabled);
    } catch (_) {
      // Developer options remain hidden if the native preference is unavailable.
    }
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
                            showTopSnackBar(
                              dialogContext,
                              SnackBar(content: Text('保存声明状态失败：$error')),
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
        await SystemNavigator.pop();
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
      if (!mounted) return;
      setState(() {
        _config = config;
        _status = running ? ProxyStatus.running : ProxyStatus.stopped;
        _debugLoggingEnabled = debugLoggingEnabled;
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

  Future<void> _openAppSelector() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AppSelectorPage()));
  }

  Future<void> _openProxyPanel() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ProxyPanelPage(proxyRunning: _status == ProxyStatus.running),
      ),
    );
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

  Future<void> _showGeneralSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
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
            _settingsTile(
              context: sheetContext,
              icon: Icons.tune_rounded,
              title: 'VPN 参数',
              onTap: _showVpnTunnelSettings,
            ),
            _settingsTile(
              context: sheetContext,
              icon: Icons.apps_rounded,
              title: '分应用代理',
              onTap: _openAppSelector,
            ),
            _settingsTile(
              context: sheetContext,
              icon: Icons.article_outlined,
              title: '调试日志',
              onTap: _showDebugLogSettings,
            ),
            if (_developerModeEnabled)
              _settingsTile(
                context: sheetContext,
                icon: Icons.developer_mode_rounded,
                title: '开发者模式',
                onTap: _showDeveloperSettings,
              ),
            _settingsTile(
              context: sheetContext,
              icon: Icons.info_outline_rounded,
              title: '关于',
              onTap: _showAbout,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeveloperSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '开发者模式',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              _settingsTile(
                context: sheetContext,
                icon: Icons.badge_outlined,
                title: '设备登记',
                subtitle: '生成并导出本设备登记文件',
                onTap: _openDeviceRegistration,
              ),
              const Divider(height: 24),
              OutlinedButton.icon(
                onPressed: () async {
                  await _service.disableDeveloperMode();
                  if (!mounted) return;
                  setState(() => _developerModeEnabled = false);
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                  showTopSnackBar(
                    context,
                    const SnackBar(content: Text('开发者模式已关闭')),
                  );
                },
                icon: const Icon(Icons.developer_mode_outlined),
                label: const Text('关闭开发者模式'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDeviceRegistration() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const DeviceRegistrationPage()),
    );
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

  Future<void> _showVpnTunnelSettings() async {
    try {
      final current = await _service.getVpnTunnelSettings();
      if (!mounted) return;

      final ipv4DnsController = TextEditingController(
        text: current.ipv4DnsServers.join(', '),
      );
      final mtuController = TextEditingController(text: '${current.mtu}');
      final bufferController = TextEditingController(
        text: '${current.tcpBufferSize}',
      );
      var ipv6Enabled = current.ipv6Enabled;
      var bypassLan = current.bypassLan;
      String? validationMessage;

      List<String> parseDnsServers(TextEditingController controller) =>
          controller.text
              .split(RegExp(r'[,，;；\s]+'))
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(growable: false);

      final save =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setDialogState) => AlertDialog(
                title: const Text('VPN 参数'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用 IPv6'),
                        value: ipv6Enabled,
                        onChanged: (value) =>
                            setDialogState(() => ipv6Enabled = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('绕过局域网'),
                        value: bypassLan,
                        onChanged: (value) =>
                            setDialogState(() => bypassLan = value),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ipv4DnsController,
                        decoration: const InputDecoration(
                          labelText: 'IPv4 DNS',
                          hintText: '1.1.1.1',
                        ),
                        keyboardType: TextInputType.text,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: mtuController,
                        decoration: const InputDecoration(
                          labelText: 'VPN MTU',
                          hintText: '1500',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: bufferController,
                        decoration: const InputDecoration(
                          labelText: 'TCP 缓冲大小',
                          hintText: '262144',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            validationMessage!,
                            style: TextStyle(
                              color: Theme.of(dialogContext).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () {
                      ipv4DnsController.text = '1.1.1.1';
                      mtuController.text = '1500';
                      bufferController.text = '262144';
                      setDialogState(() {
                        ipv6Enabled = false;
                        bypassLan = true;
                        validationMessage = null;
                      });
                    },
                    child: const Text('恢复默认'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final mtu = int.tryParse(mtuController.text.trim());
                      final tcpBuffer = int.tryParse(
                        bufferController.text.trim(),
                      );
                      final ipv4DnsServers = parseDnsServers(ipv4DnsController);
                      if (ipv4DnsServers.isEmpty ||
                          ipv4DnsServers.any(
                            (address) =>
                                InternetAddress.tryParse(address)?.type !=
                                InternetAddressType.IPv4,
                          )) {
                        setDialogState(
                          () => validationMessage = '请填写有效的 IPv4 DNS 地址',
                        );
                        return;
                      }
                      if (mtu == null || mtu < 576 || mtu > 9000) {
                        setDialogState(
                          () => validationMessage = 'MTU 必须在 576 到 9000 之间',
                        );
                        return;
                      }
                      if (tcpBuffer == null ||
                          tcpBuffer < 4096 ||
                          tcpBuffer > 1048576) {
                        setDialogState(
                          () =>
                              validationMessage = 'TCP 缓冲必须在 4096 到 1048576 之间',
                        );
                        return;
                      }
                      Navigator.of(dialogContext).pop(true);
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ) ??
          false;

      final mtu = int.tryParse(mtuController.text.trim());
      final tcpBuffer = int.tryParse(bufferController.text.trim());
      final ipv4DnsServers = parseDnsServers(ipv4DnsController);
      ipv4DnsController.dispose();
      mtuController.dispose();
      bufferController.dispose();

      if (!save || mtu == null || tcpBuffer == null || ipv4DnsServers.isEmpty) {
        return;
      }
      await _service.saveVpnTunnelSettings(
        mtu: mtu,
        tcpBufferSize: tcpBuffer,
        ipv4DnsServers: ipv4DnsServers,
        ipv6Enabled: ipv6Enabled,
        bypassLan: bypassLan,
      );
      if (!mounted) return;
      showTopSnackBar(
        context,
        SnackBar(content: const Text('VPN 参数已保存，下次启动代理生效')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _handleAboutTitleTap(dialogContext),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Mclash',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
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
              'https://github.com/liuyi-htu/Mclash',
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

  Future<void> _handleAboutTitleTap(BuildContext dialogContext) async {
    if (_developerModeEnabled) return;
    final now = DateTime.now();
    if (_lastAboutTitleTap == null ||
        now.difference(_lastAboutTitleTap!) > const Duration(seconds: 2)) {
      _aboutTitleTapCount = 0;
    }
    _lastAboutTitleTap = now;
    _aboutTitleTapCount += 1;
    if (_aboutTitleTapCount < 5) return;

    _aboutTitleTapCount = 0;
    await _service.enableDeveloperMode();
    if (!mounted) return;
    setState(() => _developerModeEnabled = true);
    if (dialogContext.mounted) {
      showTopSnackBar(context, const SnackBar(content: Text('开发者模式已启用')));
    }
  }

  Future<void> _toggle() async {
    if (_status == ProxyStatus.starting || _status == ProxyStatus.stopping) {
      return;
    }

    try {
      if (_status == ProxyStatus.running) {
        setState(() => _status = ProxyStatus.stopping);
        await _service.stop();
        if (!mounted) return;
        setState(() => _status = ProxyStatus.stopped);
        return;
      }

      if (!_config.exists) {
        _showError('请先上传 mihomo YAML 配置');
        return;
      }

      setState(() => _status = ProxyStatus.starting);
      final granted = await _service.prepareVpn();
      if (!granted) {
        if (!mounted) return;
        setState(() => _status = ProxyStatus.stopped);
        return;
      }
      await _service.start();
      if (!mounted) return;
      setState(() => _status = ProxyStatus.running);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = ProxyStatus.stopped);
      _showError(error);
    }
  }

  Future<void> _showDebugLogSettings() async {
    var enabled = _debugLoggingEnabled;

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
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_applications_outlined),
                  title: const Text('Mclash.log'),
                  subtitle: const Text('服务启动、停止和控制日志'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(dialogContext).pop('Mclash.log'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.memory_rounded),
                  title: const Text('mihomo.log'),
                  subtitle: const Text('mihomo 内核运行日志'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(dialogContext).pop('mihomo.log'),
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
    } else if (action != null) {
      await _showDebugLog(action);
    }
  }

  Future<void> _confirmClearDebugLogs() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('清除调试日志'),
            content: const Text(
              '将清空 App 启动日志、mihomo 日志和最近一次启动错误。'
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
      showTopSnackBar(context, const SnackBar(content: Text('调试日志已清除')));
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _showDebugLog(String name) async {
    try {
      final log = await _service.getDebugLog(name);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(name),
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
                showTopSnackBar(
                  dialogContext,
                  const SnackBar(content: Text('日志已复制')),
                );
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
    showTopSnackBar(context, SnackBar(content: Text(error.toString())));
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
  }) {
    final colors = Theme.of(context).colorScheme;
    return PopupMenuItem<_HomeMenuAction>(
      value: value,
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                    style: const TextStyle(
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
                      onPressed: _openProxyPanel,
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
