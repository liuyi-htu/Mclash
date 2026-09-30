import 'dart:async';

import 'package:flutter/material.dart';

import 'app_notice.dart';
import 'models.dart';
import 'native_proxy_service.dart';

class ConfigEditorPage extends StatefulWidget {
  const ConfigEditorPage(
      {required this.profile, this.runtimeView = false, super.key});

  final ConfigProfile profile;
  final bool runtimeView;

  @override
  State<ConfigEditorPage> createState() => _ConfigEditorPageState();
}

class _ConfigEditorPageState extends State<ConfigEditorPage> {
  final _service = NativeProxyService.instance;
  final _controller = TextEditingController();
  bool _readOnly = false;
  Timer? _stateTimer;
  bool _checkingState = false;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _stateTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _checkRunningState());
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkRunningState() async {
    if (widget.runtimeView || _loading || _saving || _checkingState) return;
    _checkingState = true;
    try {
      final running = await _service.isRunning();
      if (mounted && running != _readOnly) await _load();
    } catch (_) {
      // Keep the current view; native save guards still reject unsafe writes.
    } finally {
      _checkingState = false;
    }
  }

  Future<void> _load() async {
    try {
      final running = await _service.isRunning();
      if (!mounted) return;
      setState(() => _readOnly = widget.runtimeView || running);
      final content = widget.runtimeView || running
          ? await _service.getRuntimeConfigContent()
          : await _service.getConfigContent(widget.profile.id);
      if (!mounted) return;
      _controller.removeListener(_markDirty);
      _readOnly = widget.runtimeView || running;
      _dirty = false;
      _controller.text = content;
      _controller.addListener(_markDirty);
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _markDirty() {
    if (!_readOnly && !_dirty && mounted) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (_saving || _readOnly) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (await _service.isRunning()) {
        await _load();
        return;
      }

      await _service.saveConfigContent(
        id: widget.profile.id,
        content: _controller.text,
      );
      if (!mounted) return;
      setState(() => _dirty = false);
      AppNotice.show(context, '配置内容已保存');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty || _saving) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('放弃修改？'),
            content: const Text('配置内容尚未保存，确定放弃修改吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续编辑'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('放弃修改'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _confirmDiscard() || !context.mounted) return;
        setState(() => _dirty = false);
        Navigator.of(context).pop(true);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(_readOnly ? '运行配置（只读）' : '修改配置'),
          actions: [
            if (!_readOnly)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: FilledButton.icon(
                  onPressed: _loading || _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _readOnly ? '当前内核实际运行配置' : widget.profile.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (!_readOnly && widget.profile.isSubscription) ...[
                        const SizedBox(height: 6),
                        const Text('这是订阅配置，后续更新订阅时会覆盖手工修改的内容。'),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          readOnly: _readOnly,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textAlignVertical: TextAlignVertical.top,
                          autocorrect: false,
                          enableSuggestions: false,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.35,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'YAML 配置内容',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
