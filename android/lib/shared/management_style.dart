import 'package:flutter/material.dart';

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
  const ManagementCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).cardTheme.color ?? colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ListTileTheme(
        data: ListTileThemeData(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
          subtitleTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
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
      minTileHeight: 60,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: enabled ? 0.09 : 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon,
            size: 21,
            color: enabled ? color : colors.onSurface.withValues(alpha: 0.38)),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: enabled && destructive ? colors.error : null)),
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
