import 'package:flutter/material.dart';

class PulseDashboard extends StatelessWidget {
  const PulseDashboard(
      {super.key,
      required this.running,
      required this.busy,
      required this.status,
      this.detail,
      required this.download,
      required this.upload,
      required this.mode,
      required this.changingMode,
      required this.onToggle,
      required this.onMode,
      required this.onRefresh});
  final bool running, busy, changingMode;
  final String status, download, upload;
  final String? mode;
  final String? detail;
  final VoidCallback onToggle;
  final ValueChanged<String> onMode;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Icon(Icons.circle,
                        size: 10,
                        color: running ? colors.primary : colors.outline),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(status,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(detail ?? 'Mihomo',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                        ])),
                    IconButton.filledTonal(
                        onPressed: busy ? null : onToggle,
                        tooltip: running ? '停止服务' : '启动服务',
                        icon: const Icon(Icons.power_settings_new)),
                  ]))),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
                child: _Speed(
                    label: '下载', value: download, icon: Icons.south_rounded)),
            Expanded(
                child: _Speed(
                    label: '上传', value: upload, icon: Icons.north_rounded)),
          ]),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: 'rule', label: Text('规则')),
              ButtonSegment(value: 'global', label: Text('全局')),
              ButtonSegment(value: 'direct', label: Text('直连'))
            ],
            selected: mode == null ? <String>{} : {mode!},
            onSelectionChanged: running && !busy && !changingMode
                ? (value) {
                    if (value.isNotEmpty) onMode(value.first);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _Speed extends StatelessWidget {
  const _Speed({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label)
        ]),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ]);
}

class PulseNavigation extends StatelessWidget {
  const PulseNavigation(
      {super.key,
      required this.index,
      required this.onSelected,
      required this.child});
  final int index;
  final ValueChanged<int> onSelected;
  final Widget child;
  static const icons = [
    Icons.home_outlined,
    Icons.hub_outlined,
    Icons.inventory_2_outlined,
    Icons.settings_outlined
  ];
  static const labels = ['首页', '代理', '配置', '设置'];
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 720) return child;
        return Row(children: [
          NavigationRail(
              selectedIndex: index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: onSelected,
              destinations: [
                for (var i = 0; i < labels.length; i++)
                  NavigationRailDestination(
                      icon: Icon(icons[i]), label: Text(labels[i]))
              ]),
          const VerticalDivider(width: 1),
          Expanded(child: child)
        ]);
      });
}
