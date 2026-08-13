import 'dart:io';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';
import '../shared/top_notice.dart';

class RootSettingsDialog extends StatefulWidget {
  const RootSettingsDialog({super.key, required this.proxyRunning});

  final bool proxyRunning;

  @override
  State<RootSettingsDialog> createState() => _RootSettingsDialogState();
}

class _RootSettingsDialogState extends State<RootSettingsDialog> {
  final _service = NativeProxyService.instance;
  final _cidrs = TextEditingController();
  RootSettings? _settings;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cidrs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _service.getRootSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _cidrs.text = settings.bypassCidrs;
      });
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context);
      showTopSnackBar(context, SnackBar(content: Text('读取 Root 参数失败：$error')));
    }
  }

  String? _validateCidrs(String text) {
    for (final value in text.split(RegExp(r'[\n,，;；\s]+'))) {
      if (value.isEmpty) continue;
      final parts = value.split('/');
      if (parts.length != 2) return '网段缺少掩码：$value';
      final address = InternetAddress.tryParse(parts.first);
      final prefix = int.tryParse(parts.last);
      if (address == null || prefix == null) return '无效网段：$value';
      final max = address.type == InternetAddressType.IPv4 ? 32 : 128;
      if (prefix < 0 || prefix > max) {
        return '${address.type == InternetAddressType.IPv4 ? 'IPv4' : 'IPv6'} 掩码超出范围：$value';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final settings = _settings;
    if (settings == null) return;
    final validation = _validateCidrs(_cidrs.text);
    if (validation != null) {
      showTopSnackBar(context, SnackBar(content: Text(validation)));
      return;
    }
    var restart = false;
    if (widget.proxyRunning) {
      restart = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('应用 Root 参数'),
              content: const Text('代理正在运行，是否立即重启并应用新参数？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('仅保存'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('保存并重启'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await _service.saveRootSettings(
        settings.copyWith(bypassCidrs: _cidrs.text),
      );
      if (restart) {
        await _service.stopRoot();
        await _service.startRoot();
      }
      if (!mounted) return;
      Navigator.pop(context, restart);
    } catch (error) {
      if (!mounted) return;
      showTopSnackBar(context, SnackBar(content: Text('保存失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return AlertDialog(
      title: const Text('Root 参数'),
      content: SizedBox(
        width: 460,
        child: settings == null
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('开机自启'),
                      subtitle: const Text('由 Root 模块在系统启动完成后运行'),
                      value: settings.autoStart,
                      onChanged: (value) => setState(
                        () => _settings = settings.copyWith(autoStart: value),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('IPv6'),
                      subtitle: settings.proxyMode == RootProxyMode.tproxy
                          ? const Text('TProxy 模式暂不支持 IPv6')
                          : null,
                      value: settings.ipv6Enabled,
                      onChanged: settings.proxyMode == RootProxyMode.tproxy
                          ? null
                          : (value) => setState(
                                () => _settings =
                                    settings.copyWith(ipv6Enabled: value),
                              ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('绕过局域网'),
                      value: settings.bypassLan,
                      onChanged: (value) => setState(
                        () => _settings = settings.copyWith(bypassLan: value),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cidrs,
                      minLines: 5,
                      maxLines: 8,
                      decoration: InputDecoration(
                        labelText: '绕过网段',
                        helperText: settings.ipv6Enabled
                            ? '每行一个 IPv4/IPv6 CIDR'
                            : 'IPv6 条目会保留，启用 IPv6 后生效',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving || settings == null ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
