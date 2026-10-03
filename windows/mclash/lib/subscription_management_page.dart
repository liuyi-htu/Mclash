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
  });

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
        Navigator.of(context).pop();
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
  Widget build(BuildContext context) {
    final links = subscriptionLinks(_profile.url ?? '');
    final editable = !_working && !widget.proxyRunning;
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        appBar: AppBar(title: const Text('订阅管理')),
        floatingActionButtonLocation: managementAddButtonLocation(context),
        floatingActionButton: AddActionButton(
          tooltip: '添加机场',
          onPressed: editable
              ? () => _change(() => widget.onEdit(_profile, null))
              : null,
        ),
        body: ManagementBody(
            child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: ReorderableListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 168),
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
                    ManagementCard(
                      key: ValueKey(links[i]),
                      child: InkWell(
                        onTap: _working
                            ? null
                            : () => _change(
                                () => widget.onEdit(_profile, links[i])),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 4, 8, 12),
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
                                          '${i + 1} · ${_profile.subscriptionNameFor(links[i], i)}',
                                          maxLines: 1,
                                          softWrap: false,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: IconButton(
                                    tooltip: '更新机场',
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    icon: _updatingLink == links[i]
                                        ? TickerMode(
                                            enabled: ModalRoute.of(context)
                                                    ?.isCurrent ??
                                                true,
                                            child: const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2)),
                                          )
                                        : const Icon(Icons.refresh_rounded,
                                            size: 22),
                                    onPressed:
                                        editable && widget.onUpdate != null
                                            ? () => _change(
                                                () => widget.onUpdate!(
                                                    _profile, links[i]),
                                                updatingLink: links[i])
                                            : null,
                                  ),
                                ),
                                ManagementDeleteButton(
                                  tooltip: '删除机场',
                                  onPressed: editable && widget.onDelete != null
                                      ? () => _change(() =>
                                          widget.onDelete!(_profile, links[i]))
                                      : null,
                                ),
                              ]),
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ReorderableDragStartListener(
                                      index: i,
                                      enabled: editable,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            0, 6, 12, 6),
                                        child: Icon(Icons.drag_handle,
                                            size: 22,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                          subscriptionUsageSummary(_profile
                                              .subscriptionInfoFor(links[i])),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  height: 1.5)),
                                    ),
                                  ]),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        )),
      ),
    );
  }
}
