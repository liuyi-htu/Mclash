import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Corrects only top insets already handled by the Android small-window frame.
class WindowSafeArea extends StatefulWidget {
  const WindowSafeArea({required this.child, super.key});
  final Widget child;

  @override
  State<WindowSafeArea> createState() => _WindowSafeAreaState();
}

class _WindowSafeAreaState extends State<WindowSafeArea>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('mclash/window');
  double? _topInset;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'windowChanged') _refreshAfterLayout();
    });
    _refreshAfterLayout();
  }

  void _refreshAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final generation = ++_generation;
    double? inset;
    try {
      final value = await _channel.invokeMethod<num>('getTopInset');
      inset = value?.toDouble();
      if (inset != null && (!inset.isFinite || inset < 0)) inset = null;
    } on PlatformException {
      inset = null;
    } on MissingPluginException {
      inset = null;
    }
    if (mounted && generation == _generation && inset != _topInset) {
      setState(() => _topInset = inset);
    }
  }

  @override
  void didChangeMetrics() => _refreshAfterLayout();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAfterLayout();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final inset = _topInset;
    if (inset == null) return widget.child;
    return MediaQuery(
      data: data.copyWith(
        padding: data.padding.copyWith(top: data.padding.top.clamp(0.0, inset)),
        viewPadding: data.viewPadding.copyWith(
          top: data.viewPadding.top.clamp(0.0, inset),
        ),
      ),
      child: widget.child,
    );
  }
}
