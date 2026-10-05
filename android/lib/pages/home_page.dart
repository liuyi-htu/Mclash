import '../shared/app_appearance.dart';
import '../shared/pulse_dashboard.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';
import '../shared/top_notice.dart';
import 'app_selector_page.dart';
import 'config_page.dart';
import 'device_registration_page.dart';
import 'proxy_panel_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _service = NativeProxyService.instance;

  final _proxyStatus = ValueNotifier<ProxyStatus>(ProxyStatus.starting);
  ProxyStatus get _status => _proxyStatus.value;
  set _status(ProxyStatus value) => _proxyStatus.value = value;
  bool _refreshInProgress = false;
  ConfigInfo _config = const ConfigInfo(exists: false);
  bool _debugLoggingEnabled = false;
  bool _developerModeEnabled = false;
  int _aboutTitleTapCount = 0;
  DateTime? _lastAboutTitleTap;
  Timer? _trafficTimer;
  bool _statusChecking = false;
  int? _lastRxBytes;
  int? _lastTxBytes;
  DateTime? _lastTrafficSample;
  double _downloadBytesPerSecond = 0;
  double _uploadBytesPerSecond = 0;
  String _proxyMode = 'rule';
  bool _changingProxyMode = false;
  bool _toggling = false;
  int _transitionGeneration = 0;
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
    _proxyStatus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
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

  Future<void> _pollStatus() async {
    if (_statusChecking || _toggling || !mounted) return;
    _statusChecking = true;
    final generation = _transitionGeneration;
    try {
      final status =
          await _service.getProxyStatus().timeout(const Duration(seconds: 5));
      if (!mounted || _toggling || generation != _transitionGeneration) return;
      final previous = _status;
      setState(() => _status = status);
      if (status == ProxyStatus.running && previous != status) {
        unawaited(_loadProxyMode());
      }
    } catch (_) {
      // Retry on the next foreground sample. Native write guards remain authoritative.
    } finally {
      _statusChecking = false;
    }
  }

  Future<void> _updateTrafficSpeed() async {
    try {
      unawaited(_pollStatus());
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
    if (!mounted || _refreshInProgress) return;
    _refreshInProgress = true;
    final generation = _transitionGeneration;
    try {
      final config = await _service.getConfigInfo();
      final status = await _service.getProxyStatus();
      final debugLoggingEnabled = await _service.getDebugLoggingEnabled();
      if (!mounted) return;
      setState(() {
        _config = config;
        if (!_toggling && generation == _transitionGeneration) {
          _status = status;
        }
        _debugLoggingEnabled = debugLoggingEnabled;
      });
      if (status == ProxyStatus.running) await _loadProxyMode();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      _refreshInProgress = false;
    }
  }

  Future<void> _openAppSelector() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AppSelectorPage()));
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

      final save = await showDialog<bool>(
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
                          hintText: '114.114.114.114',
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
                    onPressed: () {
                      ipv4DnsController.text = '114.114.114.114';
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
      ),
    );
  }

  Future<void> _openSourceRepository(BuildContext dialogContext) async {
    final opened = await launchUrl(
      Uri.parse('https://github.com/liuyi-htu/Mclash'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted && dialogContext.mounted) {
      showTopSnackBar(context, const SnackBar(content: Text('无法打开源码链接')));
    }
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

    _toggling = true;
    _transitionGeneration++;
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
      await _loadProxyMode();
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = ProxyStatus.stopped);
      _showError(error);
    } finally {
      _toggling = false;
      _transitionGeneration++;
    }
  }

  Future<void> _showDebugLogSettings() async {
    var enabled = _debugLoggingEnabled;

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<ProxyStatus>(
        valueListenable: _proxyStatus,
        builder: (_, status, child) => StatefulBuilder(
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
                    onChanged: _status != ProxyStatus.stopped
                        ? null
                        : (value) async {
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
                    onTap: () => Navigator.of(dialogContext).pop('Mclash.log'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.memory_rounded),
                    title: const Text('mihomo.log'),
                    subtitle: const Text('mihomo 内核运行日志'),
                    onTap: () => Navigator.of(dialogContext).pop('mihomo.log'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.swap_vert_circle_outlined),
                    title: const Text('hev.log'),
                    subtitle: const Text('IPv4/IPv6 TUN 转发日志'),
                    onTap: () => Navigator.of(dialogContext).pop('hev.log'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: _status != ProxyStatus.stopped
                    ? null
                    : () => Navigator.of(dialogContext).pop('clear'),
                icon: const Icon(Icons.delete_outline),
                label: const Text('清除'),
              ),
            ],
          ),
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
    final confirmed = await showDialog<bool>(
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

    if (!confirmed || await _service.getProxyStatus() != ProxyStatus.stopped) {
      return;
    }

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
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  void _showError(Object error) {
    showErrorNotice(context, error);
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
          : pulseAppBar(context,
              badge: 'VPN',
              title: tab == 1
                  ? '配置与订阅'
                  : tab == 2
                      ? '设置'
                      : 'Mclash'),
      body: PulseNavigation(
        index: navIndex,
        onSelected: (index) => handleDestination(const [0, 3, 1, 2][index]),
        child: IndexedStack(
          index: tab,
          children: [
            PulseDashboard(
              running: running,
              busy: busy,
              status: _statusText,
              detail: 'VPN · ${_config.fileName ?? '未选择配置'}',
              download: _formatSpeed(_downloadBytesPerSecond),
              downloadTotal: _formatSpeed((_lastRxBytes ?? 0).toDouble())
                  .replaceAll('/s', ''),
              uploadTotal: _formatSpeed((_lastTxBytes ?? 0).toDouble())
                  .replaceAll('/s', ''),
              upload: _formatSpeed(_uploadBytesPerSecond),
              mode: _proxyMode,
              changingMode: _changingProxyMode,
              onToggle: _toggle,
              onMode: _setProxyMode,
              onRefresh: _refresh,
            ),
            ConfigPage(proxyRunning: _status != ProxyStatus.stopped),
            _SettingsPage(
              developerModeEnabled: _developerModeEnabled,
              onVpnSettings: _showVpnTunnelSettings,
              onAppSelector: _openAppSelector,
              onDebugLogs: _showDebugLogSettings,
              onDeveloperSettings: _showDeveloperSettings,
              onAbout: _showAbout,
            ),
            tab == 3
                ? ProxyPanelPage(proxyRunning: running, proxyMode: _proxyMode)
                : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width >= 720
          ? null
          : PulseBottomBar(
              index: navIndex,
              onSelected: (index) =>
                  handleDestination(const [0, 3, 1, 2][index]),
            ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.developerModeEnabled,
    required this.onVpnSettings,
    required this.onAppSelector,
    required this.onDebugLogs,
    required this.onDeveloperSettings,
    required this.onAbout,
  });

  final bool developerModeEnabled;
  final Future<void> Function() onVpnSettings;
  final Future<void> Function() onAppSelector;
  final Future<void> Function() onDebugLogs;
  final Future<void> Function() onDeveloperSettings;
  final Future<void> Function() onAbout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 380 ? 12 : 16,
          0,
          MediaQuery.sizeOf(context).width < 380 ? 12 : 16,
          18),
      children: [
        const PulseSectionLabel('代理接管'),
        PulseSettingsGroup(children: [
          SettingsCard(
              icon: Icons.tune_rounded, title: 'VPN 参数', onTap: onVpnSettings),
          SettingsCard(
              icon: Icons.apps_rounded, title: '分应用代理', onTap: onAppSelector),
        ]),
        const PulseSectionLabel('工具'),
        PulseSettingsGroup(children: [
          SettingsCard(
              icon: Icons.article_outlined, title: '调试日志', onTap: onDebugLogs),
          if (developerModeEnabled)
            SettingsCard(
                icon: Icons.developer_mode_rounded,
                title: '开发者模式',
                onTap: onDeveloperSettings),
        ]),
        const PulseSectionLabel('外观与应用'),
        PulseSettingsGroup(children: [
          const AppearanceTile(),
          SettingsCard(
              icon: Icons.info_outline_rounded,
              title: '关于 Mclash',
              onTap: onAbout),
        ]),
      ],
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
