import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'dialog_typography.dart';

class SubscriptionChanges {
  const SubscriptionChanges(
      {required this.added, required this.changed, required this.deleted});

  final List<String> added;
  final List<String> changed;
  final List<String> deleted;

  factory SubscriptionChanges.compare(String before, String after) {
    Map<String, Map> nodes(String content) => {
          for (final node
              in (loadYaml(content) as Map)['proxies'] as List? ?? [])
            if (node is Map && node['name'] is String)
              node['name'] as String: node,
        };
    final oldNodes = nodes(before);
    final newNodes = nodes(after);
    return SubscriptionChanges(
      added:
          newNodes.keys.where((name) => !oldNodes.containsKey(name)).toList(),
      changed: newNodes.keys
          .where((name) =>
              oldNodes.containsKey(name) &&
              !_sameValue(oldNodes[name], newNodes[name]))
          .toList(),
      deleted:
          oldNodes.keys.where((name) => !newNodes.containsKey(name)).toList(),
    );
  }
}

bool _sameValue(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every((key) =>
            right.containsKey(key) && _sameValue(left[key], right[key]));
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        List.generate(left.length, (index) => index)
            .every((index) => _sameValue(left[index], right[index]));
  }
  return left == right;
}

Future<void> showSubscriptionChanges(BuildContext context,
    {required String message, required SubscriptionChanges changes}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogTypography(
        child: AlertDialog(
      title: Text(message),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in [
              ('新增', changes.added),
              ('变动', changes.changed),
              ('删除', changes.deleted),
            ]) ...[
              Text('${section.$1}（${section.$2.length}）',
                  style: Theme.of(dialogContext).textTheme.titleSmall),
              const SizedBox(height: 6),
              if (section.$2.isEmpty)
                const Text('无')
              else
                for (final name in section.$2)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(name)),
              const SizedBox(height: 16),
            ],
          ],
        )),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('确定'))
      ],
    )),
  );
}
