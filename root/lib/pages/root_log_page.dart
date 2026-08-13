import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';
import '../shared/top_notice.dart';

class RootLogPage extends StatefulWidget {
  const RootLogPage({super.key});

  @override
  State<RootLogPage> createState() => _RootLogPageState();
}

class _RootLogPageState extends State<RootLogPage> {
  final _service = NativeProxyService.instance;
  static const _logs = ['mihomo.log', 'module.log', 'update.log'];
  String _selected = _logs.first;
  String _content = '';
  bool _loading = true;
  RootSettings? _settings;
  bool _changingLogging = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _refresh();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _service.getRootSettings();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      // Log reading below presents the actionable Root error.
    }
  }

  Future<void> _setLogging(bool enabled) async {
    final settings = _settings;
    if (settings == null || _changingLogging) return;
    setState(() => _changingLogging = true);
    try {
      final running = await _service.isRootRunning();
      final saved = await _service.saveRootSettings(
        settings.copyWith(loggingEnabled: enabled),
      );
      if (running) {
        await _service.stopRoot();
        await _service.startRoot();
      }
      if (!mounted) return;
      setState(() => _settings = saved);
      showTopSnackBar(
        context,
        SnackBar(content: Text(running ? 'Root 日志设置已应用并重启代理' : 'Root 日志设置已保存')),
      );
    } catch (error) {
      if (!mounted) return;
      showTopSnackBar(context, SnackBar(content: Text('修改 Root 日志失败：$error')));
    } finally {
      if (mounted) setState(() => _changingLogging = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final content = await _service.readRootLog(_selected);
      if (!mounted) return;
      setState(() {
        _content = content;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _content = '读取失败：$error';
        _loading = false;
      });
    }
  }

  Future<void> _clear() async {
    try {
      await _service.clearRootLog(_selected);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showTopSnackBar(context, SnackBar(content: Text('清空失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Root 日志'),
          actions: [
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              onPressed: _content.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: _content));
                      if (!context.mounted) return;
                      showTopSnackBar(
                        context,
                        const SnackBar(content: Text('日志已复制')),
                      );
                    },
              icon: const Icon(Icons.copy_rounded),
            ),
            IconButton(
                onPressed: _clear, icon: const Icon(Icons.delete_outline)),
          ],
        ),
        body: Column(
          children: [
            if (_settings != null)
              SwitchListTile(
                title: const Text('Root 日志'),
                subtitle: const Text('记录 mihomo 详细运行日志'),
                value: _settings!.loggingEnabled,
                onChanged: _changingLogging ? null : _setLogging,
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: _logs
                    .map(
                        (name) => ButtonSegment(value: name, label: Text(name)))
                    .toList(growable: false),
                selected: {_selected},
                onSelectionChanged: (selection) {
                  setState(() => _selected = selection.first);
                  _refresh();
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _content,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      );
}
