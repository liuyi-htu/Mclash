import 'package:flutter/material.dart';

/// Shared type sizes for modal titles, controls, body text and hints.
/// System text scaling and platform font families remain inherited.
class DialogTypography extends StatelessWidget {
  const DialogTypography({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    TextStyle? body(TextStyle? style) =>
        style?.copyWith(fontSize: 14, height: 1.45, letterSpacing: 0);
    final title = theme.textTheme.titleMedium?.copyWith(
        fontSize: 18,
        height: 1.45,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        color: colors.onSurface);
    final hint = theme.textTheme.bodySmall
        ?.copyWith(fontSize: 12, height: 1.45, letterSpacing: 0);
    final control = body(theme.textTheme.labelLarge);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          titleLarge: title,
          titleMedium: body(theme.textTheme.titleMedium),
          titleSmall: body(theme.textTheme.titleSmall),
          bodyLarge: body(theme.textTheme.bodyLarge),
          bodyMedium: body(theme.textTheme.bodyMedium),
          bodySmall: hint,
          labelLarge: control,
          labelMedium: body(theme.textTheme.labelMedium),
          labelSmall: hint,
        ),
        dialogTheme: theme.dialogTheme.copyWith(
          titleTextStyle: title,
          contentTextStyle: body(theme.textTheme.bodyMedium),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          titleTextStyle: body(theme.textTheme.bodyMedium),
          subtitleTextStyle: hint,
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          labelStyle: body(theme.textTheme.bodyMedium),
          floatingLabelStyle: body(theme.textTheme.bodyMedium),
          hintStyle: body(theme.textTheme.bodyMedium),
          helperStyle: hint,
          errorStyle: hint?.copyWith(color: colors.error),
        ),
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle())
              .copyWith(textStyle: WidgetStatePropertyAll(control)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: (theme.filledButtonTheme.style ?? const ButtonStyle())
              .copyWith(textStyle: WidgetStatePropertyAll(control)),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(textStyle: WidgetStatePropertyAll(control)),
        ),
      ),
      child: child,
    );
  }
}
