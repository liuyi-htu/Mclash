import '../shared/core_update_panel.dart';
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
          child: CoreUpdateSheetContent(
            panel: CoreUpdatePanel(
              currentVersion: _info?['currentVersion']?.toString(),
              latestVersion: _info?['latestVersion']?.toString(),
              busy: _busy,
              updating: _updating,
              proxyEnabled: _proxyEnabled,
              message: _message,
              onCheck: _check,
              onUpdate: _update,
            ),
          ),
        ),
      );
}
