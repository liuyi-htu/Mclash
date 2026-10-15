import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';
import '../shared/dialog_typography.dart';

class NetworkSharingDialog extends StatefulWidget {
  const NetworkSharingDialog({super.key, required this.proxyStatus});

  final ValueListenable<ProxyStatus> proxyStatus;

  @override
  State<NetworkSharingDialog> createState() => _NetworkSharingDialogState();
}

class _NetworkSharingDialogState extends State<NetworkSharingDialog> {
  final _service = NativeProxyService.instance;
  NetworkSharingSettings _settings = const NetworkSharingSettings();
  bool _busy = false;
  String? _error;
  int _statusGeneration = 0;

  bool get _running => widget.proxyStatus.value == ProxyStatus.running;

  @override
  void initState() {
    super.initState();
    widget.proxyStatus.addListener(_statusChanged);
    _load();
  }

  @override
  void dispose() {
    widget.proxyStatus.removeListener(_statusChanged);
    super.dispose();
  }

  void _statusChanged() {
    setState(() {
      _statusGeneration++;
      _settings = const NetworkSharingSettings();
      _error = null;
    });
    if (!_busy) _load();
  }

  Future<void> _perform(
      Future<NetworkSharingSettings> Function() action) async {
    final generation = _statusGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await action();
      if (mounted && generation == _statusGeneration) {
        setState(() =>
            _settings = _running ? settings : const NetworkSharingSettings());
      }
    } catch (error) {
      if (mounted && generation == _statusGeneration) {
        setState(() => _error = error is PlatformException
            ? error.message ?? '网络共享设置失败'
            : error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (generation != _statusGeneration && _running) _load();
      }
    }
  }

  Future<void> _load() => _perform(_service.getNetworkSharing);

  Future<void> _save(bool enabled, List<String> interfaces) => _perform(
        () => _service.setNetworkSharing(
            enabled: enabled, interfaces: interfaces),
      );

  @override
  Widget build(BuildContext context) {
    final interfaces = {
      ..._settings.availableInterfaces,
      ..._settings.interfaces,
    }.toList()
      ..sort();
    return PopScope(
      canPop: !_busy,
      child: DialogTypography(
        child: AlertDialog(
          title: const Text('网络共享'),
          scrollable: true,
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('共享代理网络'),
                  value: _running && _settings.enabled,
                  onChanged: !_running || _busy
                      ? null
                      : (enabled) => _save(enabled, _settings.interfaces),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_running && _settings.enabled) ...[
                  Row(children: [
                    const Expanded(child: Text('可共享接口')),
                    IconButton(
                      onPressed: _busy ? null : _load,
                      icon: const Icon(Icons.refresh_rounded,
                          semanticLabel: '刷新接口'),
                    ),
                  ]),
                  for (final interface in interfaces)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(interface),
                      value: _settings.interfaces.contains(interface),
                      onChanged: _busy
                          ? null
                          : (selected) {
                              final selection = _settings.interfaces.toSet();
                              if (selected == true) {
                                selection.add(interface);
                              } else {
                                selection.remove(interface);
                              }
                              _save(true, selection.toList());
                            },
                    ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
