import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';
import '../shared/top_notice.dart';
import 'app_selector_page.dart';
import 'config_page.dart';
import 'device_registration_page.dart';
import 'proxy_panel_page.dart';
import 'root_core_update_page.dart';
import 'root_log_page.dart';
import 'root_settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _service = NativeProxyService.instance;

  ProxyStatus _status = ProxyStatus.stopped;
  ConfigInfo _config = const ConfigInfo(exists: false);
  bool _developerModeEnabled = false;
  RootStatus? _rootStatus;
  int _aboutTitleTapCount = 0;
  DateTime? _lastAboutTitleTap;
  Timer? _trafficTimer;
  int? _lastRxBytes;
  int? _lastTxBytes;
  DateTime? _lastTrafficSample;
  double _downloadBytesPerSecond = 0;
  double _uploadBytesPerSecond = 0;
  String _proxyMode = 'rule';
  bool _changingProxyMode = false;
  int _selectedHomeTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _showUsageNoticeIfNeeded();
      await _loadDeveloperMode();
      await _refresh();
      _startTrafficUpdates();
    });
  }

  @override
  void dispose() {
    _trafficTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTrafficUpdates();
    } else {
      _trafficTimer?.cancel();
      _trafficTimer = null;
    }
  }

  void _startTrafficUpdates() {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState != null && lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (_trafficTimer?.isActive ?? false) return;
    _lastRxBytes = null;
    _lastTxBytes = null;
    _lastTrafficSample = null;
    unawaited(_updateTrafficSpeed());
    _trafficTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTrafficSpeed(),
    );
  }

  Future<void> _updateTrafficSpeed() async {
    try {
      final stats = await _service.getTrafficStats();
      final now = DateTime.now();
      final rx = stats['rxBytes'] ?? 0;
      final tx = stats['txBytes'] ?? 0;
      final previousTime = _lastTrafficSample;
      final seconds = previousTime == null
          ? 0.0
          : now.difference(previousTime).inMilliseconds / 1000;
      final download = seconds > 0 && _lastRxBytes != null
          ? ((rx - _lastRxBytes!) / seconds).clamp(0, double.infinity)
          : 0.0;
      final upload = seconds > 0 && _lastTxBytes != null
          ? ((tx - _lastTxBytes!) / seconds).clamp(0, double.infinity)
          : 0.0;
      _lastRxBytes = rx;
      _lastTxBytes = tx;
      _lastTrafficSample = now;
      if (!mounted) return;
      setState(() {
        _downloadBytesPerSecond =
            _status == ProxyStatus.running ? download.toDouble() : 0;
        _uploadBytesPerSecond =
            _status == ProxyStatus.running ? upload.toDouble() : 0;
      });
    } catch (_) {
      // Keep the last displayed values if traffic statistics are unavailable.
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
      RootStatus? rootStatus;
      try {
        rootStatus = await _service.getRootStatus();
      } catch (_) {
        rootStatus = null;
      }
      if (!mounted) return;
      setState(() {
        _config = config;
        _status = running ? ProxyStatus.running : ProxyStatus.stopped;
        _rootStatus = rootStatus;
      });
      if (running) await _loadProxyMode();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
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

  Future<Map<String, dynamic>> _proxyControllerRequest(
    String method, {
    Map<String, Object>? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
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

  Future<void> _setupRoot() async {
    try {
      final status = await _service.getRootStatus();
      if (!status.hasRootPermission) {
        throw Exception('未获得 Root 权限；请在 Root 管理器中授权 Mclash');
      }
      if (status.state == RootState.disabled) {
        if (!mounted) return;
        final install = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('安装 Root 模块'),
                content: const Text('需要安装 APK 内置模块。安装完成后必须重启设备。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('安装'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!install) return;
        final installed = await _service.installRootModule();
        if (!mounted) return;
        showTopSnackBar(context, SnackBar(content: Text(installed.message)));
        return;
      }
      if (status.state != RootState.ready) throw Exception(status.message);
      await _service.switchToRootMode();
      if (!mounted) return;
      showTopSnackBar(context, const SnackBar(content: Text('Root 模式已就绪')));
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _showRuntimeSettings() async {
    final restarted = await showDialog<bool>(
      context: context,
      builder: (_) => RootSettingsDialog(
        proxyRunning: _status == ProxyStatus.running,
      ),
    );
    if (!mounted || restarted == null) return;
    showTopSnackBar(
      context,
      SnackBar(content: Text(restarted ? 'Root 参数已保存并重启代理' : 'Root 参数已保存')),
    );
    await _refresh();
  }

  Future<void> _showRootProxyMode() async {
    try {
      final settings = await _service.getRootSettings();
      if (!mounted) return;
      var selected = settings.proxyMode;
      final save = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setDialogState) => AlertDialog(
                title: const Text('运行模式'),
                content: RadioGroup<RootProxyMode>(
                  groupValue: selected,
                  onChanged: (value) {
                    if (value != null) setDialogState(() => selected = value);
                  },
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<RootProxyMode>(
                        value: RootProxyMode.tun,
                        title: Text('TUN'),
                        subtitle: Text('默认，支持 IPv4 与 IPv6'),
                      ),
                      RadioListTile<RootProxyMode>(
                        value: RootProxyMode.tproxy,
                        title: Text('TProxy'),
                        subtitle: Text('TCP/UDP，暂不支持 IPv6'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ) ??
          false;
      if (!save || selected == settings.proxyMode) return;
      var restart = false;
      if (_status == ProxyStatus.running) {
        if (!mounted) return;
        restart = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('重启代理'),
                content: const Text('代理正在运行，需要重启后才能应用新的运行模式。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('仅保存'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('保存并重启'),
                  ),
                ],
              ),
            ) ??
            false;
      }
      await _service.saveRootSettings(
        settings.copyWith(
          proxyMode: selected,
          ipv6Enabled:
              selected == RootProxyMode.tproxy ? false : settings.ipv6Enabled,
        ),
      );
      if (restart) {
        await _service.stopRoot();
        await _service.startRoot();
      }
      if (!mounted) return;
      showTopSnackBar(
        context,
        SnackBar(content: Text(restart ? '运行模式已应用并重启代理' : '运行模式已保存')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _openRootCoreUpdate() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const RootCoreUpdatePage()),
    );
  }

  Future<void> _openRootLog() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const RootLogPage()),
    );
    await _refresh();
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
      onTap: () async {
        Navigator.of(context).pop();
        await onTap();
      },
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
          if (_developerModeEnabled)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                unawaited(_showDeveloperSettings());
              },
              icon: const Icon(Icons.developer_mode_outlined),
              label: const Text('开发者模式'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
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
      await _service.start();
      if (!mounted) return;
      setState(() => _status = ProxyStatus.running);
      await _loadProxyMode();
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = ProxyStatus.stopped);
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
          ConfigPage(proxyRunning: _status != ProxyStatus.stopped),
          _SettingsPage(
            rootActivated: _rootStatus?.state == RootState.ready,
            onRootSetup: _setupRoot,
            onRuntimeSettings: _showRuntimeSettings,
            onRootProxyMode: _showRootProxyMode,
            onRootCoreUpdate: _openRootCoreUpdate,
            onRootLog: _openRootLog,
            onAppSelector: _openAppSelector,
            onAbout: _showAbout,
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

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.rootActivated,
    required this.onRootSetup,
    required this.onRuntimeSettings,
    required this.onRootProxyMode,
    required this.onRootCoreUpdate,
    required this.onRootLog,
    required this.onAppSelector,
    required this.onAbout,
  });

  final bool rootActivated;
  final Future<void> Function() onRootSetup;
  final Future<void> Function() onRuntimeSettings;
  final Future<void> Function() onRootProxyMode;
  final Future<void> Function() onRootCoreUpdate;
  final Future<void> Function() onRootLog;
  final Future<void> Function() onAppSelector;
  final Future<void> Function() onAbout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _SettingsActionTile(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Root 环境',
                trailing: _ActivationBadge(active: rootActivated),
                onTap: onRootSetup,
              ),
              const Divider(height: 1, indent: 64),
              _SettingsActionTile(
                icon: Icons.tune_rounded,
                title: 'Root 参数',
                onTap: onRuntimeSettings,
              ),
              const Divider(height: 1, indent: 64),
              _SettingsActionTile(
                icon: Icons.route_rounded,
                title: '运行模式',
                onTap: onRootProxyMode,
              ),
              const Divider(height: 1, indent: 64),
              _SettingsActionTile(
                icon: Icons.system_update_alt_rounded,
                title: '更新内核',
                onTap: onRootCoreUpdate,
              ),
              const Divider(height: 1, indent: 64),
              _SettingsActionTile(
                icon: Icons.article_outlined,
                title: 'Root 日志',
                onTap: onRootLog,
              ),
              const Divider(height: 1, indent: 64),
              _SettingsActionTile(
                icon: Icons.apps_rounded,
                title: '分应用代理',
                onTap: onAppSelector,
              ),
              const Divider(height: 1, indent: 64),
              _SettingsActionTile(
                icon: Icons.info_outline_rounded,
                title: '关于',
                onTap: onAbout,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Row(
          children: [
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
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _ActivationBadge extends StatelessWidget {
  const _ActivationBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color:
            active ? colors.primaryContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? '已激活' : '未激活',
        style: TextStyle(
          color: active ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
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
