import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/native_proxy_service.dart';
import '../shared/top_notice.dart';

class DeviceRegistrationPage extends StatefulWidget {
  const DeviceRegistrationPage({super.key});

  @override
  State<DeviceRegistrationPage> createState() => _DeviceRegistrationPageState();
}

class _DeviceRegistrationPageState extends State<DeviceRegistrationPage> {
  final _service = NativeProxyService.instance;
  Map<String, dynamic>? _info;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await _service.getDeviceRegistration();
      if (mounted) setState(() => _info = info);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final path = await _service.exportDeviceRegistration();
      if (!mounted) return;
      showTopSnackBar(
        context,
        SnackBar(content: Text(path == null ? '已保存' : '已保存：$path')),
      );
    } on PlatformException catch (error) {
      if (!mounted || error.code == 'cancelled') return;
      _showMessage('保存失败：${error.message ?? error.code}');
    } catch (error) {
      if (mounted) _showMessage('保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final json = _info?['json']?.toString();
    if (json == null || json.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) _showMessage('登记 JSON 已复制');
  }

  void _showMessage(String message) {
    showTopSnackBar(context, SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(
          title: Text('设备登记',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontSize: 18))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('读取失败：$_error'),
              ),
            ),
          if (info != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '设备身份已就绪',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text('安装 ID', style: Theme.of(context).textTheme.bodySmall),
                    SelectableText(info['installationId']?.toString() ?? '',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontSize: 13)),
                    const SizedBox(height: 12),
                    Text('公钥 SHA-256 指纹',
                        style: Theme.of(context).textTheme.bodySmall),
                    SelectableText(info['fingerprint']?.toString() ?? '',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  textStyle: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 14)),
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.save_alt_rounded, size: 18),
              label: const Text('导出设备登记 JSON'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  textStyle: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 14)),
              onPressed: _busy ? null : _copy,
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('复制登记 JSON'),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              title: Text('查看完整登记信息',
                  style: Theme.of(context).textTheme.bodyMedium),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(info),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
