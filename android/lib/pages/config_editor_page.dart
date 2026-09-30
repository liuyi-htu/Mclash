import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';
import '../shared/top_notice.dart';

class ConfigEditorPage extends StatefulWidget {
  const ConfigEditorPage({
    required this.profile,
    this.runtimeView = false,
    required this.proxyRunning,
    super.key,
  });

  final ConfigProfile profile;
  final bool runtimeView;
  final bool proxyRunning;

  @override
  State<ConfigEditorPage> createState() => _ConfigEditorPageState();
}

class _ConfigEditorPageState extends State<ConfigEditorPage> {
  final _service = NativeProxyService.instance;
  final _controller = TextEditingController();
  final _jumpController = TextEditingController();
  final _editorScrollController = ScrollController();
  final _lineNumberScrollController = ScrollController();
  bool _readOnly = false;
  Timer? _stateTimer;
  bool _checkingState = false;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  int _lineCount = 1;
  int _currentLine = 1;
  int _currentColumn = 1;
  String _lastText = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _editorScrollController.addListener(_syncLineNumberScroll);
    _load();
    _stateTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _checkRunningState());
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    _controller.dispose();
    _jumpController.dispose();
    _editorScrollController.dispose();
    _lineNumberScrollController.dispose();
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
      _lastText = content;
      _controller.removeListener(_handleTextChanged);
      _readOnly = widget.runtimeView || running;
      _dirty = false;
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
    final text = _controller.text;
    final offset = _controller.selection.extentOffset.clamp(0, text.length);
    setState(() {
      if (text != _lastText) _dirty = true;
      _lastText = text;
      _lineCount = _countLines(text);
      _currentLine = _countLines(text.substring(0, offset));
      _currentColumn = offset - text.substring(0, offset).lastIndexOf('\n');
    });
  }

  Future<void> _jumpToLine() async {
    final input = _jumpController..clear();
    final line = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('跳转到行（1–$_lineCount）'),
        content: TextField(
            controller: input,
            autofocus: true,
            keyboardType: TextInputType.number),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, int.tryParse(input.text)),
              child: const Text('跳转'))
        ],
      ),
    );
    if (line == null || !mounted) return;
    _selectLine(line.clamp(1, _lineCount));
  }

  void _selectLine(int line) {
    var offset = 0;
    for (var i = 1; i < line; i++) {
      offset = _controller.text.indexOf('\n', offset) + 1;
    }
    final end = _controller.text.indexOf('\n', offset);
    _controller.selection = TextSelection(
        baseOffset: offset,
        extentOffset: end < 0 ? _controller.text.length : end);
    if (_editorScrollController.hasClients) {
      final height = MediaQuery.textScalerOf(context).scale(13) * 1.35;
      _editorScrollController.jumpTo(((line - 1) * height)
          .clamp(0.0, _editorScrollController.position.maxScrollExtent));
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

      try {
        if (loadYaml(_controller.text) is! YamlMap) {
          throw const FormatException('配置必须是 YAML 对象');
        }
      } on YamlException catch (error) {
        final line = error.span?.start.line;
        if (line != null) _selectLine(line + 1);
        rethrow;
      }
      await _service.saveConfigContent(
          id: widget.profile.id, content: _controller.text);
      if (!mounted) return;
      setState(() => _dirty = false);
      showTopSnackBar(context, const SnackBar(content: Text('配置已保存，下次启动时应用')));
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
          title: Text(_readOnly ? '运行配置（只读）' : '修改配置'),
          actions: [
            IconButton(
                onPressed: _loading ? null : _jumpToLine,
                tooltip: '跳转到行',
                icon: const Icon(Icons.format_list_numbered)),
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
                              width: 28 +
                                  _lineCount.toString().length *
                                      MediaQuery.textScalerOf(context).scale(9),
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
                                child: Text.rich(
                                  TextSpan(
                                      children: List.generate(
                                          _lineCount,
                                          (index) => TextSpan(
                                                text:
                                                    '${index + 1}${index + 1 == _lineCount ? '' : '\n'}',
                                                style: TextStyle(
                                                    backgroundColor: index +
                                                                1 ==
                                                            _currentLine
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .primaryContainer
                                                        : null),
                                              ))),
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
                              child: LayoutBuilder(
                                  builder: (context, constraints) {
                                final editorStyle = Theme.of(context)
                                    .textTheme
                                    .bodyLarge!
                                    .copyWith(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      height: 1.35,
                                    );
                                final painter = TextPainter(
                                  text: TextSpan(
                                      text: _controller.text,
                                      style: editorStyle),
                                  textDirection: TextDirection.ltr,
                                  textScaler: MediaQuery.textScalerOf(context),
                                )..layout();
                                final width = (painter.width + 48).clamp(
                                    constraints.maxWidth, double.infinity);
                                painter.dispose();
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: width,
                                    height: constraints.maxHeight,
                                    child: TextField(
                                      textDirection: TextDirection.ltr,
                                      controller: _controller,
                                      readOnly: _readOnly,
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
                                      style: editorStyle,
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
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                      Text(
                          '第 $_currentLine 行，第 $_currentColumn 列 · 共 $_lineCount 行'),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
