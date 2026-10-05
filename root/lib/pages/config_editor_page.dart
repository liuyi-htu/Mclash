import '../shared/dialog_typography.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';
import '../shared/top_notice.dart';
import '../shared/config_text_editor.dart';

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
  bool _showLineNumbers = false;
  bool _searchVisible = false;
  int _searchIndex = -1;
  final _searchController = TextEditingController();
  bool _readOnly = false;
  bool _runtimeContent = false;
  bool _observedRunning = false;
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
    _load();
    _stateTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _checkRunningState());
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    _controller.dispose();
    _searchController.dispose();
    _jumpController.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  Future<void> _checkRunningState() async {
    if (widget.runtimeView || _loading || _saving || _checkingState) return;
    _checkingState = true;
    try {
      final running = await _service.getProxyStatus() != ProxyStatus.stopped;
      if (mounted && running != _observedRunning) {
        await _applyRunningState(running);
      }
    } catch (_) {
      // Keep the current view; native save guards still reject unsafe writes.
    } finally {
      _checkingState = false;
    }
  }

  Future<void> _applyRunningState(bool running) async {
    if (_dirty) {
      // Keep the draft in place; only lock editing until the proxy stops.
      setState(() {
        _observedRunning = running;
        _readOnly = running || widget.profile.isSubscription;
      });
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    try {
      final running = await _service.getProxyStatus() != ProxyStatus.stopped;
      if (!mounted) return;
      if (_dirty) {
        await _applyRunningState(running);
        return;
      }
      setState(() {
        _observedRunning = running;
        _runtimeContent = widget.runtimeView || running;
        _readOnly = _runtimeContent || widget.profile.isSubscription;
      });
      final content = widget.runtimeView || running
          ? await _service.getRuntimeConfigContent()
          : await _service.getConfigContent(widget.profile.id);
      if (!mounted) return;
      if (_dirty) {
        setState(() {
          _runtimeContent = false;
          _readOnly = _observedRunning || widget.profile.isSubscription;
        });
        return;
      }
      _controller.removeListener(_handleTextChanged);
      _readOnly = _runtimeContent || widget.profile.isSubscription;
      _dirty = false;
      _lastText = content;
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
      builder: (context) => DialogTypography(
          child: AlertDialog(
        title: Text('跳转到行（1–$_lineCount）'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: TextField(
            controller: input,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: '行号',
                filled: true,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, int.tryParse(input.text)),
              child: const Text('跳转'))
        ],
      )),
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

  List<RegExpMatch> get _matches => _searchController.text.isEmpty
      ? []
      : RegExp(RegExp.escape(_searchController.text), caseSensitive: false)
          .allMatches(_controller.text)
          .toList();

  void _findMatch({bool reset = false, bool previous = false}) {
    final matches = _matches;
    setState(() => _searchIndex = matches.isEmpty
        ? -1
        : reset
            ? 0
            : (_searchIndex + (previous ? -1 : 1)) % matches.length);
    if (_searchIndex < 0) return;
    final match = matches[_searchIndex];
    _controller.selection =
        TextSelection(baseOffset: match.start, extentOffset: match.end);
    if (_editorScrollController.hasClients) {
      final line = _countLines(_controller.text.substring(0, match.start));
      final height = MediaQuery.textScalerOf(context).scale(13) * 1.35;
      _editorScrollController.jumpTo(((line - 1) * height)
          .clamp(0.0, _editorScrollController.position.maxScrollExtent));
    }
  }

  Widget _searchBar() => Row(children: [
        Expanded(
            child: TextField(
          controller: _searchController,
          onChanged: (_) => _findMatch(reset: true),
          onSubmitted: (_) => _findMatch(),
          decoration: InputDecoration(
              hintText: '搜索配置',
              filled: true,
              isDense: true,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none)),
        )),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
                '${_searchIndex < 0 ? 0 : _searchIndex + 1}/${_matches.length}',
                style: Theme.of(context).textTheme.bodySmall)),
        IconButton(
            tooltip: '上一个匹配',
            visualDensity: VisualDensity.compact,
            onPressed:
                _matches.isEmpty ? null : () => _findMatch(previous: true),
            icon: const Icon(Icons.keyboard_arrow_up, size: 20)),
        IconButton(
            tooltip: '下一个匹配',
            visualDensity: VisualDensity.compact,
            onPressed: _matches.isEmpty ? null : () => _findMatch(),
            icon: const Icon(Icons.keyboard_arrow_down, size: 20)),
        IconButton(
            tooltip: '关闭搜索',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _searchVisible = false),
            icon: const Icon(Icons.close, size: 20)),
      ]);

  Future<void> _save() async {
    if (_saving || _readOnly) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (await _service.getProxyStatus() != ProxyStatus.stopped) {
        await _applyRunningState(true);
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
          builder: (context) => DialogTypography(
              child: AlertDialog(
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
          )),
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
          title: Row(children: [
            Expanded(
                child: Text(
                    _runtimeContent
                        ? '当前运行配置'
                        : _readOnly
                            ? (_dirty ? '草稿已保留（停止代理后可编辑）' : '订阅配置（只读）')
                            : '修改配置',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            if (_runtimeContent)
              const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Tooltip(
                      message: '只读',
                      child: Icon(Icons.lock_outline, size: 18))),
          ]),
          actions: [
            IconButton(
              tooltip: _showLineNumbers ? '隐藏行号' : '显示行号',
              icon: Icon(Icons.numbers,
                  color: _showLineNumbers
                      ? Theme.of(context).colorScheme.primary
                      : null),
              onPressed: _loading
                  ? null
                  : () => setState(() => _showLineNumbers = !_showLineNumbers),
            ),
            IconButton(
                onPressed: _loading ? null : _jumpToLine,
                tooltip: '跳转到行',
                icon: const Icon(Icons.format_list_numbered)),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              enabled: !_loading,
              onSelected: (value) async {
                if (value == 'search') {
                  setState(() => _searchVisible = true);
                } else {
                  await Clipboard.setData(
                      ClipboardData(text: _controller.text));
                  if (!context.mounted) return;
                  showTopSnackBar(
                      context, const SnackBar(content: Text('配置已复制')));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'search', child: Text('搜索配置')),
                PopupMenuItem(value: 'copy', child: Text('复制全文')),
              ],
            ),
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
                  padding: EdgeInsets.fromLTRB(
                      MediaQuery.sizeOf(context).width < 600 ? 8 : 16,
                      8,
                      MediaQuery.sizeOf(context).width < 600 ? 8 : 16,
                      12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_searchVisible) ...[
                        _searchBar(),
                        const SizedBox(height: 8)
                      ],
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
                        child: ConfigTextEditor(
                          controller: _controller,
                          readOnly: _readOnly,
                          scrollController: _editorScrollController,
                          showLineNumbers: _showLineNumbers,
                        ),
                      ),
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                              '第 $_currentLine 行，第 $_currentColumn 列 · 共 $_lineCount 行',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant))),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
