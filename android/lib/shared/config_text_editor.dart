import 'package:flutter/material.dart';

/// A YAML editor with unwrapped lines and a transparent, fixed line overlay.
class ConfigTextEditor extends StatefulWidget {
  const ConfigTextEditor({
    required this.controller,
    required this.readOnly,
    this.scrollController,
    super.key,
  });

  final TextEditingController controller;
  final bool readOnly;
  final ScrollController? scrollController;

  @override
  State<ConfigTextEditor> createState() => _ConfigTextEditorState();
}

class _ConfigTextEditorState extends State<ConfigTextEditor> {
  late final ScrollController _editorScroll =
      widget.scrollController ?? ScrollController();
  final _lineScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _editorScroll.addListener(_syncLines);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _editorScroll.removeListener(_syncLines);
    if (widget.scrollController == null) _editorScroll.dispose();
    _lineScroll.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _syncLines() {
    if (!_lineScroll.hasClients) return;
    _lineScroll.jumpTo(
        _editorScroll.offset.clamp(0.0, _lineScroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.controller.text;
    final lineCount = '\n'.allMatches(text).length + 1;
    final style = theme.textTheme.bodyLarge!.copyWith(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.35,
    );
    final scaler = MediaQuery.textScalerOf(context);
    // Measure with the same theme letter spacing and scaling as the input.
    final linePainter = TextPainter(
      text: TextSpan(text: '$lineCount', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final lineWidth = linePainter.width.ceilToDouble() + 16;
    linePainter.dispose();

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              left: lineWidth,
              child: LayoutBuilder(builder: (context, constraints) {
                final painter = TextPainter(
                  text: TextSpan(text: text, style: style),
                  textDirection: TextDirection.ltr,
                  textScaler: scaler,
                )..layout();
                final width = (painter.width + 48)
                    .clamp(constraints.maxWidth, double.infinity);
                painter.dispose();
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    height: constraints.maxHeight,
                    child: TextField(
                      textDirection: TextDirection.ltr,
                      controller: widget.controller,
                      readOnly: widget.readOnly,
                      scrollController: _editorScroll,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      style: style,
                      decoration: const InputDecoration(
                        hintText: 'YAML 配置内容',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.all(12),
                      ),
                    ),
                  ),
                );
              }),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: lineWidth,
              child: IgnorePointer(
                child: SingleChildScrollView(
                  controller: _lineScroll,
                  physics: const NeverScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Text(
                    List.generate(lineCount, (index) => '${index + 1}')
                        .join('\n'),
                    key: const ValueKey('config-line-numbers'),
                    textAlign: TextAlign.right,
                    style: style.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
