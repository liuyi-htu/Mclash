import 'proxy_edit_access.dart';
import 'management_style.dart';
import 'add_action_button.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'subscription_links.dart';
import 'subscription_usage.dart';

class SubscriptionManagementPage extends StatefulWidget {
  const SubscriptionManagementPage({
    super.key,
    required this.profile,
    required this.proxyRunning,
    required this.onEdit,
    required this.onReorder,
    this.onUpdate,
    this.onDelete,
    this.embedded = false,
  });

  final bool embedded;
  final ConfigProfile profile;
  final bool proxyRunning;
  final Future<ConfigProfile?> Function(ConfigProfile profile, String? link)
      onEdit;
  final Future<ConfigProfile?> Function(
      ConfigProfile profile, List<String> order) onReorder;

  final Future<ConfigProfile?> Function(ConfigProfile profile, String link)?
      onUpdate;
  final Future<ConfigProfile?> Function(ConfigProfile profile, String link)?
      onDelete;

  @override
  State<SubscriptionManagementPage> createState() =>
      _SubscriptionManagementPageState();
}

class _SubscriptionManagementPageState
    extends State<SubscriptionManagementPage> {
  late ConfigProfile _profile = widget.profile;
  bool _working = false;
  String? _error;
  String? _updatingLink;

  Future<void> _change(Future<ConfigProfile?> Function() action,
      {String? updatingLink}) async {
    if (!ProxyEditAccess.allowed(context) || widget.proxyRunning) return;
    setState(() {
      _working = true;
      _updatingLink = updatingLink;
      _error = null;
    });
    try {
      final profile = await action();
      if (!mounted) return;
      if (profile == null) {
        setState(() => _working = false);
        if (!widget.embedded) Navigator.of(context).pop();
        return;
      }
      setState(() => _profile = profile);
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _updatingLink = null;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant SubscriptionManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) _profile = widget.profile;
  }

  @override
  Widget build(BuildContext context) {
    final links = subscriptionLinks(_profile.url ?? '');
    final editable =
        ProxyEditAccess.allowed(context) && !_working && !widget.proxyRunning;
    final colors = Theme.of(context).colorScheme;
    final cards = ReorderableListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      padding: widget.embedded
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 12, 16, 168),
      buildDefaultDragHandles: false,
      // Keep compatibility with the Flutter 3.32 CI toolchain.
      // ignore: deprecated_member_use
      onReorder: (oldIndex, newIndex) {
        if (!editable) return;
        if (newIndex > oldIndex) newIndex--;
        if (newIndex == oldIndex) return;
        final reordered = [...links];
        reordered.insert(newIndex, reordered.removeAt(oldIndex));
        _change(() => widget.onReorder(_profile, reordered));
      },
      children: [
        for (var i = 0; i < links.length; i++)
          Padding(
            key: ValueKey(links[i]),
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
                child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: editable
                  ? () => _change(() => widget.onEdit(_profile, links[i]))
                  : null,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                  _profile.subscriptionNameFor(links[i], i),
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                      fontSize:
                                          MediaQuery.sizeOf(context).width < 380
                                              ? 13
                                              : 14,
                                      fontWeight: FontWeight.w600))),
                        )),
                        SizedBox(
                            width: 36,
                            height: 44,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              tooltip: '更新机场',
                              color: colors.onSurfaceVariant,
                              icon: _updatingLink == links[i]
                                  ? TickerMode(
                                      enabled:
                                          ModalRoute.of(context)?.isCurrent ??
                                              true,
                                      child: const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2)))
                                  : const Icon(Icons.refresh_rounded, size: 20),
                              onPressed: editable && widget.onUpdate != null
                                  ? () => _change(
                                      () =>
                                          widget.onUpdate!(_profile, links[i]),
                                      updatingLink: links[i])
                                  : null,
                            )),
                        SizedBox(
                            width: 36,
                            height: 44,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              tooltip: '删除机场',
                              color: colors.onSurfaceVariant,
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: editable && widget.onDelete != null
                                  ? () => _change(() =>
                                      widget.onDelete!(_profile, links[i]))
                                  : null,
                            )),
                        ReorderableDragStartListener(
                            index: i,
                            enabled: editable,
                            child: SizedBox(
                                width: 36,
                                height: 44,
                                child: Icon(Icons.drag_handle,
                                    size: 20,
                                    color: colors.onSurfaceVariant.withValues(
                                        alpha: editable ? 1 : .4)))),
                      ]),
                      const SizedBox(height: 4),
                      ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                  subscriptionUsageSummary(_profile
                                          .subscriptionInfoFor(links[i]))
                                      .replaceAll('\n', ' · '),
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                      fontSize: 11,
                                      height: 1.45,
                                      color: colors.onSurfaceVariant)))),
                      const SizedBox(height: 8),
                      if (subscriptionRemainingFraction(
                              _profile.subscriptionInfoFor(links[i]))
                          case final fraction?)
                        ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 5,
                                color: colors.primary,
                                backgroundColor: colors.outlineVariant)),
                    ]),
              ),
            )),
          ),
      ],
    );
    final error = _error == null
        ? null
        : Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: TextStyle(color: colors.error)));
    if (widget.embedded) {
      return Column(children: [if (error != null) error, cards]);
    }
    return PopScope(
        canPop: !_working,
        child: Scaffold(
          appBar: AppBar(title: const Text('订阅管理')),
          floatingActionButtonLocation: managementAddButtonLocation(context),
          floatingActionButton: AddActionButton(
              tooltip: '添加机场',
              onPressed: editable
                  ? () => _change(() => widget.onEdit(_profile, null))
                  : null),
          body: ManagementBody(
              child: Column(children: [
            if (error != null) error,
            Expanded(child: cards)
          ])),
        ));
  }
}
