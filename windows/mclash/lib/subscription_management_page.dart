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
  });

  final ConfigProfile profile;
  final bool proxyRunning;
  final Future<ConfigProfile?> Function(ConfigProfile profile, String? link)
      onEdit;
  final Future<ConfigProfile?> Function(
      ConfigProfile profile, List<String> order) onReorder;

  @override
  State<SubscriptionManagementPage> createState() =>
      _SubscriptionManagementPageState();
}

class _SubscriptionManagementPageState
    extends State<SubscriptionManagementPage> {
  late ConfigProfile _profile = widget.profile;
  bool _working = false;
  String? _error;

  Future<void> _change(Future<ConfigProfile?> Function() action) async {
    setState(() {
      _working = true;
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
      if (mounted) setState(() => _working = false);
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
        floatingActionButton: AddActionButton(
          tooltip: '添加机场',
          onPressed: editable
              ? () => _change(() => widget.onEdit(_profile, null))
              : null,
        ),
        body: Column(
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
                padding: const EdgeInsets.only(bottom: 88),
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
                    ListTile(
                      key: ValueKey(links[i]),
                      isThreeLine: true,
                      leading: ReorderableDragStartListener(
                        index: i,
                        enabled: editable,
                        child: const Icon(Icons.drag_handle),
                      ),
                      title: Text(
                          '${i + 1} · ${_profile.subscriptionNameFor(links[i], i)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(subscriptionUsageSummary(
                          _profile.subscriptionInfoFor(links[i]))),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _working
                          ? null
                          : () =>
                              _change(() => widget.onEdit(_profile, links[i])),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
