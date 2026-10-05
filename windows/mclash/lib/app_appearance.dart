import 'dart:io';
import 'package:flutter/material.dart';

/// The explicit light/dark tokens from the compact-console reference.
ThemeData buildPulseTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final accent = dark ? const Color(0xFFA8C9F3) : const Color(0xFF315F95);
  final tint = dark ? const Color(0xFF283A52) : const Color(0xFFDFEBFB);
  final background = dark ? const Color(0xFF161A20) : const Color(0xFFF3F6FA);
  final colors =
      (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    primary: accent,
    onPrimary: dark ? const Color(0xFF161A20) : Colors.white,
    primaryContainer: tint,
    onPrimaryContainer: accent,
    secondary: accent,
    secondaryContainer: tint,
    onSecondaryContainer: accent,
    surface: background,
    surfaceContainerLow: dark ? const Color(0xFF242329) : Colors.white,
    surfaceContainer: dark ? const Color(0xFF242329) : Colors.white,
    surfaceContainerHighest: tint,
    onSurface: dark ? const Color(0xFFEFEDF4) : const Color(0xFF26232E),
    onSurfaceVariant: dark ? const Color(0xFFBBB5C4) : const Color(0xFF67616F),
    outlineVariant: dark ? const Color(0xFF3C3742) : const Color(0xFFE8E3EC),
    outline: dark ? const Color(0xFFBBB5C4) : const Color(0xFF67616F),
  );
  final base = ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: Platform.isWindows ? 'Segoe UI' : 'Roboto',
      fontFamilyFallback:
          Platform.isWindows ? const ['Microsoft YaHei UI'] : null);
  return base.copyWith(
    scaffoldBackgroundColor: colors.surface,
    textTheme: base.textTheme.copyWith(
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          letterSpacing: 0,
          height: 1.45,
          color: colors.onSurface),
      bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          letterSpacing: 0,
          height: 1.45,
          color: colors.onSurfaceVariant),
      titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 15,
          letterSpacing: 0,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: colors.onSurface),
    ),
    appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
            fontFamily: Platform.isWindows ? 'Segoe UI' : 'Roboto',
            color: colors.onSurface,
            fontSize: 23,
            height: 1.45,
            fontWeight: FontWeight.w600,
            letterSpacing: -.5)),
    cardTheme: CardThemeData(
        color: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    dividerTheme:
        DividerThemeData(color: colors.outlineVariant, thickness: 1, space: 1),
    iconTheme: IconThemeData(size: 20, color: colors.onSurfaceVariant),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none)),
    navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.primaryContainer,
        selectedLabelTextStyle: TextStyle(
            color: colors.primary, fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle:
            TextStyle(color: colors.onSurfaceVariant, fontSize: 11)),
  );
}

class AppearanceTile extends StatelessWidget {
  const AppearanceTile({super.key});
  @override
  Widget build(BuildContext context) => const SettingsCard(
      icon: Icons.palette_outlined,
      title: '主题',
      subtitle: 'Pulse',
      readOnly: true);
}

class SettingsCard extends StatelessWidget {
  const SettingsCard(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.onTap,
      this.readOnly = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool readOnly;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final grouped =
        context.dependOnInheritedWidgetOfExactType<_PulseSettingsScope>() !=
            null;
    final row = InkWell(
      borderRadius: BorderRadius.circular(grouped ? 8 : 20),
      onTap: onTap,
      child: Opacity(
        opacity: onTap != null || readOnly ? 1 : .4,
        child: Padding(
          padding: grouped
              ? const EdgeInsets.symmetric(vertical: 11)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 22),
            child: Row(children: [
              Expanded(child: Text(title)),
              if (subtitle != null) ...[
                const SizedBox(width: 10),
                Flexible(
                    child: Text(subtitle!,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: colors.onSurfaceVariant))),
              ],
            ]),
          ),
        ),
      ),
    );
    return grouped ? row : Card(child: row);
  }
}

class PulseSectionLabel extends StatelessWidget {
  const PulseSectionLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(3, 14, 3, 7),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall));
}

class PulseSettingsGroup extends StatelessWidget {
  const PulseSettingsGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: _PulseSettingsScope(
            child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ])),
      ));
}

class _PulseSettingsScope extends InheritedWidget {
  const _PulseSettingsScope({required super.child});
  @override
  bool updateShouldNotify(_PulseSettingsScope oldWidget) => false;
}
