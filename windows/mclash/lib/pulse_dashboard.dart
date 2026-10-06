import 'package:flutter/material.dart';
import 'pulse_icons.dart';

PreferredSizeWidget pulseAppBar(BuildContext context,
    {String badge = '',
    String title = 'Mclash',
    List<Widget> actions = const [],
    PreferredSizeWidget? bottom}) {
  final colors = Theme.of(context).colorScheme;
  final titleHeight = MediaQuery.textScalerOf(context).scale(23) * 1.45;
  // The first rail icon is centered 24px below the safe-area top.
  final topPadding = (24 - titleHeight / 2).clamp(0.0, 24.0);
  return PreferredSize(
    preferredSize: Size.fromHeight(
        topPadding + titleHeight + 14 + (bottom?.preferredSize.height ?? 0)),
    child: SafeArea(
        bottom: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: EdgeInsets.fromLTRB(18, topPadding, 18, 14),
              child: SizedBox(
                  height: titleHeight,
                  child: Row(children: [
                    Expanded(
                        child: Row(children: [
                      Flexible(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.fontFamily,
                                  fontSize: 23,
                                  height: 1.45,
                                  fontWeight: FontWeight.lerp(
                                      FontWeight.w600, FontWeight.w700, .5),
                                  letterSpacing: -.5,
                                  color: colors.onSurface))),
                      if (title == 'Mclash' && badge.isNotEmpty) ...[
                        const SizedBox(width: 9),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(badge,
                                style: TextStyle(
                                    fontFamily: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.fontFamily,
                                    fontSize: 11,
                                    height: 1.45,
                                    color: colors.primary))),
                      ],
                    ])),
                    if (actions.isNotEmpty)
                      Theme(
                          data: Theme.of(context).copyWith(
                              iconButtonTheme: IconButtonThemeData(
                                  style: IconButton.styleFrom(
                                      minimumSize: const Size(40, 32),
                                      padding: EdgeInsets.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap))),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions)),
                  ]))),
          if (bottom != null) bottom,
        ])),
  );
}

class PulseDashboard extends StatelessWidget {
  const PulseDashboard(
      {super.key,
      required this.running,
      required this.busy,
      required this.status,
      this.detail,
      this.downloadTotal,
      this.uploadTotal,
      required this.download,
      required this.upload,
      required this.mode,
      required this.changingMode,
      required this.onToggle,
      required this.onMode,
      required this.onRefresh});
  final bool running, busy, changingMode;
  final String status, download, upload;
  final String? mode, detail, downloadTotal, uploadTotal;
  final VoidCallback? onToggle;
  final ValueChanged<String> onMode;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 380 ? 12 : 16,
                0,
                MediaQuery.sizeOf(context).width < 380 ? 12 : 16,
                18),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            status == '运行中'
                                ? '服务运行中'
                                : status == '未启动'
                                    ? '服务已停止'
                                    : status,
                            style: TextStyle(
                                fontSize: 19,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                                color: colors.primary)),
                        Text(detail ?? 'Mihomo',
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ])),
                  const SizedBox(width: 10),
                  Semantics(
                    toggled: running,
                    child: Material(
                        key: const ValueKey('service-toggle'),
                        color: running && !busy
                            ? colors.primary
                            : colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        child: IconButton(
                            onPressed: busy ? null : onToggle,
                            tooltip: busy
                                ? '处理中'
                                : running
                                    ? '停止服务'
                                    : '启动服务',
                            constraints: const BoxConstraints.tightFor(
                                width: 48, height: 48),
                            padding: EdgeInsets.zero,
                            icon: busy
                                ? SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: colors.primary))
                                : PulseIcon(Icons.power_settings_new,
                                    color: running
                                        ? colors.onPrimary
                                        : colors.onSurfaceVariant))),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text('运行模式',
                      style: Theme.of(context).textTheme.bodySmall)),
              const SizedBox(height: 8),
              PulseModeControl(
                  mode: mode,
                  onChanged: running && !busy && !changingMode ? onMode : null),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: _SpeedCard(
                        label: '下载速度',
                        value: download,
                        total: downloadTotal == null
                            ? null
                            : '↓ 本次 $downloadTotal')),
                const SizedBox(width: 10),
                Expanded(
                    child: _SpeedCard(
                        label: '上传速度',
                        value: upload,
                        total:
                            uploadTotal == null ? null : '↑ 本次 $uploadTotal')),
              ]),
              const SizedBox(height: 12),
            ]));
  }
}

class PulseModeControl extends StatelessWidget {
  const PulseModeControl({super.key, required this.mode, this.onChanged});
  final String? mode;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(children: [
              for (final item in const [
                ('rule', '规则'),
                ('global', '全局'),
                ('direct', '直连')
              ]) ...[
                if (item.$1 != 'rule') const SizedBox(width: 4),
                Expanded(
                    child: Semantics(
                        selected: mode == item.$1,
                        button: true,
                        enabled: onChanged != null,
                        child: Opacity(
                            opacity: onChanged == null ? .4 : 1,
                            child: Material(
                                color: mode == item.$1
                                    ? colors.primaryContainer
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                child: InkWell(
                                    borderRadius: BorderRadius.circular(11),
                                    onTap: onChanged == null
                                        ? null
                                        : () => onChanged!(item.$1),
                                    child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(minHeight: 44),
                                        child: Center(
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 4),
                                                child: Text(item.$2,
                                                    style: TextStyle(
                                                        fontSize: 13,
                                                        height: 1.45,
                                                        fontWeight: mode == item.$1
                                                            ? FontWeight.w600
                                                            : FontWeight.w400,
                                                        color: mode == item.$1
                                                            ? colors.primary
                                                            : colors.onSurfaceVariant)))))))))),
              ],
            ])));
  }
}

class _SpeedCard extends StatelessWidget {
  const _SpeedCard({required this.label, required this.value, this.total});
  final String label, value;
  final String? total;
  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Speed(label: label, value: value),
          if (total != null)
            Text(total!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ]),
      ));
}

class _Speed extends StatelessWidget {
  const _Speed({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final parts = value.trim().split(RegExp(r'\s+'));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text.rich(
          TextSpan(children: [
            TextSpan(
                text: parts.first,
                style: TextStyle(
                    fontSize: 23,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.6,
                    color: colors.onSurface)),
            if (parts.length > 1)
              TextSpan(
                  text: ' ${parts.skip(1).join(' ')}',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: colors.onSurfaceVariant))
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      const SizedBox(height: 4),
    ]);
  }
}

class PulseBottomBar extends StatelessWidget {
  const PulseBottomBar(
      {super.key, required this.index, required this.onSelected});
  final int index;
  final ValueChanged<int> onSelected;
  static const icons = [
    Icons.home_outlined,
    Icons.hub_outlined,
    Icons.inventory_2_outlined,
    Icons.settings_outlined
  ];
  static const labels = ['首页', '代理', '配置', '设置'];
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
        decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border(top: BorderSide(color: colors.outlineVariant))),
        child: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 7, 6, 9),
                child: Row(children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                        child: Semantics(
                            selected: index == i,
                            button: true,
                            child: InkWell(
                                onTap: () => onSelected(i),
                                child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 5),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                              width: 48,
                                              height: 28,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                  color: index == i
                                                      ? colors.primaryContainer
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          15)),
                                              child: PulseIcon(icons[i],
                                                  color: index == i
                                                      ? colors.primary
                                                      : colors
                                                          .onSurfaceVariant)),
                                          const SizedBox(height: 3),
                                          Text(labels[i],
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  height: 1.45,
                                                  color: index == i
                                                      ? colors.primary
                                                      : colors.onSurfaceVariant,
                                                  fontWeight: index == i
                                                      ? FontWeight.w600
                                                      : FontWeight.w400)),
                                        ])))))
                ]))));
  }
}

/// Keeps page headers and content beside the navigation rail.
class PulseNavigation extends StatelessWidget {
  const PulseNavigation(
      {super.key,
      required this.index,
      required this.onSelected,
      this.appBar,
      required this.child});
  final int index;
  final ValueChanged<int> onSelected;
  final PreferredSizeWidget? appBar;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final page = Scaffold(appBar: appBar, body: child);
        return SafeArea(
          top: false,
          bottom: false,
          child: Row(children: [
            SafeArea(
              left: false,
              right: false,
              child: NavigationRail(
                  selectedIndex: index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: onSelected,
                  destinations: [
                    for (var i = 0; i < PulseBottomBar.labels.length; i++)
                      NavigationRailDestination(
                          icon: PulseIcon(PulseBottomBar.icons[i]),
                          label: Text(PulseBottomBar.labels[i]))
                  ]),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: page)
          ]),
        );
      });
}
