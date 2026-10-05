import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// The explicit light/dark tokens from the compact-console reference.
ThemeData buildPulseTheme(Brightness brightness, {Color? seedColor}) {
  final dark = brightness == Brightness.dark;
  final custom = seedColor != null && seedColor != const Color(0xFF315F95);
  final accent = custom
      ? (dark ? Color.lerp(seedColor, Colors.white, .45)! : seedColor)
      : (dark ? const Color(0xFFA8C9F3) : const Color(0xFF315F95));
  final tint = custom
      ? Color.lerp(accent, dark ? const Color(0xFF161A20) : Colors.white, .85)!
      : (dark ? const Color(0xFF283A52) : const Color(0xFFDFEBFB));
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

Color pulsePanelCardColor(BuildContext context, {bool selected = false}) {
  final colors = Theme.of(context).colorScheme;
  if (selected) return colors.primaryContainer;
  return Theme.of(context).brightness == Brightness.dark
      ? colors.surfaceContainerLow
      : Color.lerp(colors.surfaceContainerLow, colors.primaryContainer, .65)!;
}

ShapeBorder pulsePanelCardShape(BuildContext context, {bool selected = false}) {
  final colors = Theme.of(context).colorScheme;
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(20),
    side: Theme.of(context).brightness == Brightness.dark
        ? BorderSide.none
        : BorderSide(
            color: colors.primary.withValues(alpha: selected ? .55 : .18)),
  );
}

class AppearanceController extends ChangeNotifier {
  AppearanceController({Future<File?> Function()? fileProvider})
      : _fileProvider = fileProvider ?? _defaultFile;
  final Future<File?> Function() _fileProvider;
  static const defaultColor = Color(0xFF315F95);
  Color color = defaultColor;
  static const fontSizeBaseline = 1.1;
  double fontScale = 1;
  double get effectiveFontScale => fontScale * fontSizeBaseline;
  ThemeMode themeMode = ThemeMode.system;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _writes = Future.value();

  static Future<File?> _defaultFile() async {
    if (Platform.isWindows) {
      final directory = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'];
      if (directory == null) return null;
      return File(
          '$directory${Platform.pathSeparator}Mclash${Platform.pathSeparator}appearance.json');
    }
    final directory = await const MethodChannel('mclash/native')
        .invokeMethod<String>('getAppDataDirectory');
    return directory == null ? null : File('$directory/appearance.json');
  }

  Future<void> load() async {
    try {
      final file = await _fileProvider();
      if (file == null || !await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map;
      final savedColor = data['color'];
      final savedScale = data['fontScale'];
      final savedMode = data['themeMode'];
      themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == savedMode,
        orElse: () => ThemeMode.system,
      );
      if (savedColor is int &&
          savedColor >= 0xFF000000 &&
          savedColor <= 0xFFFFFFFF) {
        color = Color(savedColor);
      }
      if (savedScale is num && savedScale.isFinite) {
        // Keep the previous visual size when adopting the larger 100% baseline.
        final relativeScale = data['fontScaleVersion'] == 2
            ? savedScale.toDouble()
            : savedScale.toDouble() / fontSizeBaseline;
        fontScale = relativeScale.clamp(.7, 1.3);
      }
      if (!_disposed) notifyListeners();
    } catch (_) {
      // Missing or damaged preferences leave the default appearance usable.
    }
  }

  void preview({Color? color, double? fontScale, ThemeMode? themeMode}) {
    if (themeMode != null) this.themeMode = themeMode;
    if (color != null) this.color = color;
    if (fontScale != null) this.fontScale = fontScale.clamp(.7, 1.3);
    notifyListeners();
  }

  Future<void> save() {
    final data = jsonEncode({
      'color': color.toARGB32(),
      'fontScale': fontScale,
      'fontScaleVersion': 2,
      'themeMode': themeMode.name
    });
    final next = _writes.then((_) async {
      final file = await _fileProvider();
      if (file == null) throw const FileSystemException('无法保存外观设置');
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(data, flush: true);
      await temporary.rename(file.path);
    });
    _writes = next.catchError((Object _) {});
    return next;
  }
}

class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope(
      {super.key,
      required AppearanceController controller,
      required super.child})
      : super(notifier: controller);
  static AppearanceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
}

class AppearanceTextScaler extends TextScaler {
  const AppearanceTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is AppearanceTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}

class AppearanceTile extends StatelessWidget {
  const AppearanceTile({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppearanceScope.maybeOf(context);
    return SettingsCard(
      icon: Icons.palette_outlined,
      title: '主题',
      onTap: controller == null
          ? null
          : () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => AppearanceScope(
                  controller: controller,
                  child: const _AppearanceSheet(),
                ),
              ),
    );
  }
}

class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet();
  static const colors = [
    AppearanceController.defaultColor,
    Color(0xFF7356A6),
    Color(0xFF26745A),
    Color(0xFFA75B29),
    Color(0xFFAD476B),
    Color(0xFF357C85),
    Color(0xFF675F71)
  ];
  @override
  Widget build(BuildContext context) {
    final controller = AppearanceScope.maybeOf(context)!;
    final hue = HSVColor.fromColor(controller.color).hue;
    Future<void> save() async {
      try {
        await controller.save();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('主题设置保存失败，请重试')));
        }
      }
    }

    return SafeArea(
        child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('主题', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Text('显示模式', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final entry in const {
            ThemeMode.system: '跟随系统',
            ThemeMode.dark: '深色模式',
            ThemeMode.light: '浅色模式',
          }.entries)
            ChoiceChip(
              key: ValueKey('theme-mode-${entry.key.name}'),
              label: Text(entry.value),
              showCheckmark: false,
              selected: controller.themeMode == entry.key,
              onSelected: (_) {
                controller.preview(themeMode: entry.key);
                save();
              },
            ),
        ]),
        const SizedBox(height: 16),
        Text('主题颜色', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (var i = 0; i < colors.length; i++)
            Semantics(
                label: '主题颜色 ${i + 1}',
                button: true,
                selected: controller.color == colors[i],
                child: InkWell(
                  key: ValueKey('theme-color-$i'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    controller.preview(color: colors[i]);
                    save();
                  },
                  child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                          child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                  color: colors[i], shape: BoxShape.circle),
                              child: controller.color == colors[i]
                                  ? const Icon(Icons.check,
                                      color: Colors.white, size: 18)
                                  : null))),
                )),
        ]),
        Slider(
            key: const ValueKey('theme-hue-slider'),
            min: 0,
            max: 360,
            value: hue,
            label: '色相 ${hue.round()}',
            onChanged: (value) => controller.preview(
                color: HSVColor.fromAHSV(1, value, .65, .6).toColor()),
            onChangeEnd: (_) => save()),
        const SizedBox(height: 8),
        Text('全局字号', style: Theme.of(context).textTheme.bodyMedium),
        Center(
            child: Text('${(controller.fontScale * 100).round()}%',
                key: const ValueKey('global-font-percentage'),
                style: Theme.of(context).textTheme.bodySmall)),
        Slider(
            key: const ValueKey('global-font-slider'),
            min: .7,
            max: 1.3,
            divisions: 12,
            value: controller.fontScale,
            label: '${(controller.fontScale * 100).round()}%',
            onChanged: (value) => controller.preview(fontScale: value),
            onChangeEnd: (_) => save()),
        Text('左右拖动，调整所有页面和按钮的字号', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        TextButton(
            onPressed: () {
              controller.preview(
                  color: AppearanceController.defaultColor,
                  fontScale: 1,
                  themeMode: ThemeMode.system);
              save();
            },
            child: const Text('恢复默认')),
      ]),
    ));
  }
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
