import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';

class CoreUpdateDialog extends StatefulWidget {
  const CoreUpdateDialog({super.key, required this.proxyStatus});

  final ValueListenable<ProxyStatus> proxyStatus;

  @override
  State<CoreUpdateDialog> createState() => _CoreUpdateDialogState();
}

class _CoreUpdateDialogState extends State<CoreUpdateDialog> {
  final _service = NativeProxyService.instance;
  Map<String, dynamic>? _info;
  bool _busy = false;
  bool _updating = false;
  String? _message;

  bool get _proxyEnabled => widget.proxyStatus.value == ProxyStatus.running;

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
      final status = await _service.getProxyStatus();
      if (status != ProxyStatus.running) {
        throw StateError('请先开启代理再更新内核');
      }
      final info = await _service.updateCore();
      if (!mounted) return;
      setState(() {
        _info = {
          'currentVersion': info['version'],
          'latestVersion': info['version']
        };
        _message = info['updated'] == true ? 'mihomo 内核更新完成' : '当前已是最新稳定版';
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
  Widget build(BuildContext context) => ValueListenableBuilder<ProxyStatus>(
        valueListenable: widget.proxyStatus,
        builder: (context, status, _) => PopScope(
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
                                      onPressed: _busy || !_proxyEnabled
                                          ? null
                                          : _check,
                                      style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8)),
                                      child: const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text('检测版本',
                                              maxLines: 1, softWrap: false)))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: FilledButton(
                                      onPressed: _busy || !_proxyEnabled
                                          ? null
                                          : _update,
                                      style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8)),
                                      child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                              _updating ? '正在更新…' : '更新内核',
                                              maxLines: 1,
                                              softWrap: false)))),
                            ]),
                            if (_message != null) ...[
                              const SizedBox(height: 14),
                              Text(_message!),
                            ],
                          ],
                        ),
                      ),
                    ),
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
        ),
      );
}
