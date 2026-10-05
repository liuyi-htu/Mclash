import 'package:flutter/material.dart';

class CoreUpdatePanel extends StatelessWidget {
  const CoreUpdatePanel(
      {super.key,
      this.currentVersion,
      this.latestVersion,
      required this.busy,
      required this.updating,
      required this.proxyEnabled,
      this.message,
      required this.onCheck,
      required this.onUpdate});
  final String? currentVersion;
  final String? latestVersion;
  final bool busy;
  final bool updating;
  final bool proxyEnabled;
  final String? message;
  final VoidCallback? onCheck;
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget version(String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 76, child: Text(label, style: theme.textTheme.bodySmall)),
          Expanded(
              child: Text(value ?? '尚未检测',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13))),
        ]));
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('mihomo',
                      style:
                          theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                  const SizedBox(height: 10),
                  version('当前版本', currentVersion),
                  version('最新版本', latestVersion),
                ]),
          ),
          if (busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 8),
            Text(updating ? '正在下载并更新内核，请勿关闭应用…' : '正在检测版本…',
                style: theme.textTheme.bodySmall),
          ],
          if (!proxyEnabled && !busy) ...[
            const SizedBox(height: 10),
            Text('开启代理后可检测和更新内核。', style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final check = OutlinedButton(
                onPressed: busy || !proxyEnabled ? null : onCheck,
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle:
                        theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('检测版本', maxLines: 1, softWrap: false));
            final update = FilledButton(
                onPressed: busy || !proxyEnabled ? null : onUpdate,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle:
                        theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: Text(updating ? '正在更新…' : '更新内核',
                    maxLines: 1, softWrap: false));
            final requiredWidth =
                (MediaQuery.textScalerOf(context).scale(14) * 12 + 72)
                    .clamp(280.0, double.infinity);
            return constraints.maxWidth < requiredWidth
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [check, const SizedBox(height: 8), update])
                : Row(children: [
                    Expanded(child: check),
                    const SizedBox(width: 10),
                    Expanded(child: update)
                  ]);
          }),
          if (message != null) ...[
            const SizedBox(height: 12),
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10)),
                child: SelectableText(message!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurface))),
          ],
        ]);
  }
}

class CoreUpdateSheetContent extends StatelessWidget {
  const CoreUpdateSheetContent(
      {super.key, required this.panel, this.onClose, this.busy = false});
  final Widget panel;
  final VoidCallback? onClose;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: 440,
              maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: Container(
                            width: 32,
                            height: 4,
                            decoration: BoxDecoration(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    Text('更新内核',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontSize: 18)),
                    const SizedBox(height: 12),
                    panel,
                    if (onClose != null) ...[
                      const SizedBox(height: 12),
                      Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                              onPressed: busy ? null : onClose,
                              child: const Text('关闭'))),
                    ],
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}
