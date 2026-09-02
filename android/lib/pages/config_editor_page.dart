import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';
import '../shared/top_notice.dart';

class ConfigEditorPage extends StatefulWidget {
  const ConfigEditorPage({
    required this.profile,
    required this.proxyRunning,
    super.key,
  });

  final ConfigProfile profile;
  final bool proxyRunning;

  @override
  State<ConfigEditorPage> createState() => _ConfigEditorPageState();
}

class _ConfigEditorPageState extends State<ConfigEditorPage> {
  final _service = NativeProxyService.instance;
  final _controller = TextEditingController();
  final _editorScrollController = ScrollController();
  final _lineNumberScrollController = ScrollController();
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  int _lineCount = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _editorScrollController.addListener(_syncLineNumberScroll);
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorScrollController.dispose();
    _lineNumberScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final content = await _service.getConfigContent(widget.profile.id);
      if (!mounted) return;
      _controller.text = content;
      _lineCount = _countLines(content);
      _controller.addListener(_handleTextChanged);
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _handleTextChanged() {
    if (!mounted) return;
    final nextLineCount = _countLines(_controller.text);
    if (!_dirty || nextLineCount != _lineCount) {
      setState(() {
        _dirty = true;
        _lineCount = nextLineCount;
      });
    }
  }

  int _countLines(String text) => '\n'.allMatches(text).length + 1;

  void _syncLineNumberScroll() {
    if (!_lineNumberScrollController.hasClients) return;
    final target = _editorScrollController.offset.clamp(
      0.0,
      _lineNumberScrollController.position.maxScrollExtent,
    );
    _lineNumberScrollController.jumpTo(target);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.saveConfigContent(
        id: widget.profile.id,
        content: _controller.text,
      );
      if (!mounted) return;
      setState(() => _dirty = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('配置已保存'),
          content: Text(
            widget.proxyRunning ? '确认后将重启代理并应用新配置。' : '代理当前未运行，新配置将在下次启动时应用。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(widget.proxyRunning ? '确认并重启' : '确定'),
            ),
          ],
        ),
      );
      if (widget.proxyRunning) await _service.restart();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = errorNoticeSummary(errorNoticeDetails(error)));
      showErrorNotice(context, error);
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
          title: const Text('修改配置'),
          actions: [
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
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (_error != null) const SizedBox(height: 10),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 52,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(12),
                                ),
                              ),
                              child: SingleChildScrollView(
                                controller: _lineNumberScrollController,
                                physics: const NeverScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(8, 12, 8, 12),
                                child: Text(
                                  List.generate(
                                    _lineCount,
                                    (index) => '${index + 1}',
                                  ).join('\n'),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                            const VerticalDivider(width: 1, thickness: 1),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                scrollController: _editorScrollController,
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
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.horizontal(
                                      right: Radius.circular(12),
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.all(12),
                                ),
                              ),
                            ),
                          ],
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
