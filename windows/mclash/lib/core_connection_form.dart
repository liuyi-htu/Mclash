import 'package:flutter/material.dart';
import 'core_connection_settings.dart';

class CoreConnectionForm extends StatefulWidget {
  const CoreConnectionForm(
      {super.key, required this.initial, required this.onSave});
  final CoreConnectionSettings initial;
  final Future<void> Function(CoreConnectionSettings) onSave;
  @override
  State<CoreConnectionForm> createState() => _CoreConnectionFormState();
}

class _CoreConnectionFormState extends State<CoreConnectionForm> {
  late final _controller =
      TextEditingController(text: widget.initial.controller);
  late final _secret = TextEditingController(text: widget.initial.secret);
  late final _port = TextEditingController(text: '${widget.initial.mixedPort}');
  bool _saving = false;
  bool _showSecret = false;
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    _secret.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settings = CoreConnectionSettings(
          controller: _controller.text.trim(),
          secret: _secret.text,
          mixedPort: int.tryParse(_port.text.trim()) ?? 0);
      settings.validate();
      await widget.onSave(settings);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Text('内核连接设置', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  TextField(
                      controller: _controller,
                      enabled: !_saving,
                      autocorrect: false,
                      decoration: const InputDecoration(
                          labelText: 'external-controller',
                          hintText: '127.0.0.1:9090')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _secret,
                      enabled: !_saving,
                      obscureText: !_showSecret,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                          labelText: 'secret',
                          suffixIcon: IconButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(
                                      () => _showSecret = !_showSecret),
                              icon: Icon(_showSecret
                                  ? Icons.visibility_off
                                  : Icons.visibility)))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _port,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'mixed-port')),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? '正在保存…' : '保存')),
                ]))),
      );
}
