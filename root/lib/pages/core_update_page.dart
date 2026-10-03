import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';

class CoreUpdateDialog extends StatefulWidget {
  const CoreUpdateDialog({super.key});

  @override
  State<CoreUpdateDialog> createState() => _CoreUpdateDialogState();
}

class _CoreUpdateDialogState extends State<CoreUpdateDialog> {
  final _service = NativeProxyService.instance;
  Map<String, dynamic>? _info;
  bool _busy = false;
  bool _updating = false;
  String? _message;

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final info = await _service.checkCoreUpdate();
      if (mounted) {
        setState(() {
          _info = info;
          _message = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = '检测失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _updating = true;
      _message = null;
    });
    try {
      if (await _service.getProxyStatus() != ProxyStatus.stopped) {
        throw StateError('请先停止代理再更新内核');
      }
      final info = await _service.updateCore();
      if (!mounted) return;
      setState(() {
        _info = {
          'currentVersion': info['version'],
          'latestVersion': info['version']
        };
        _message =
            info['updated'] == true ? 'mihomo 内核更新完成，下次启动代理时生效' : '当前已是最新稳定版';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'mihomo 内核更新失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _updating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('更新内核'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('mihomo',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(_info == null
                              ? '尚未检测版本'
                              : '当前 ${_info!['currentVersion']} / 官方 ${_info!['latestVersion']}'),
                          if (_updating) ...[
                            const SizedBox(height: 14),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 8),
                            const Text('正在下载并更新内核，请勿关闭应用…'),
                          ],
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(
                                child: OutlinedButton(
                                    onPressed: _busy ? null : _check,
                                    child: const Text('检测版本'))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: FilledButton(
                                    onPressed: _busy ? null : _update,
                                    child: Text(_updating ? '正在更新…' : '更新内核'))),
                          ]),
                          if (_message != null) ...[
                            const SizedBox(height: 14),
                            Text(_message!),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('请先停止代理。更新会下载官方稳定版，校验后切换内核；失败时保留原内核。'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('关闭'))
          ],
        ),
      );
}
