import 'package:flutter/material.dart';

InputDecoration managementFieldDecoration(BuildContext context, String label) {
  final colors = Theme.of(context).colorScheme;
  OutlineInputBorder outline(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 14),
    isDense: true,
    filled: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: outline(colors.outline),
    enabledBorder: outline(colors.outline),
    focusedBorder: outline(colors.primary, width: 2),
    disabledBorder: outline(colors.outline.withValues(alpha: 0.5)),
    errorBorder: outline(colors.error),
    focusedErrorBorder: outline(colors.error, width: 2),
  );
}

class ManagementBody extends StatelessWidget {
  const ManagementBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: SizedBox(width: double.infinity, child: child),
        ),
      );
}

class ManagementCard extends StatelessWidget {
  const ManagementCard({super.key, required this.child, this.compact = false});
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.only(bottom: compact ? 6 : 8),
      elevation: 0,
      color: Theme.of(context).cardTheme.color ?? colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ListTileTheme(
        data: ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14, vertical: compact ? 0 : 2),
          minLeadingWidth: compact ? 24 : null,
          horizontalTitleGap: compact ? 8 : null,
          titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w600,
              ),
          subtitleTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontSize: compact ? 12 : null,
                height: compact ? 1.35 : 1.5,
              ),
        ),
        child: child,
      ),
    );
  }
}

class ManagementDeleteButton extends StatelessWidget {
  const ManagementDeleteButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          tooltip: tooltip,
          color: Theme.of(context).colorScheme.error,
          icon: const Icon(Icons.delete_outline, size: 22),
          onPressed: onPressed,
        ),
      );
}

class ManagementMenuTile extends StatelessWidget {
  const ManagementMenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.enabled = true,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive ? colors.error : colors.primary;
    return ListTile(
      minTileHeight: 52,
      horizontalTitleGap: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: enabled ? 0.09 : 0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            size: 18,
            color: enabled ? color : colors.onSurface.withValues(alpha: 0.38)),
      ),
      title: Text(title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: !enabled
                  ? colors.onSurface.withValues(alpha: 0.38)
                  : destructive
                      ? colors.error
                      : colors.onSurface)),
      enabled: enabled,
      onTap: onTap,
    );
  }
}

class DestructiveActionButton extends StatelessWidget {
  const DestructiveActionButton({
    super.key,
    required this.onPressed,
    required this.child,
  });
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        onPressed: onPressed,
        child: child,
      );
}
