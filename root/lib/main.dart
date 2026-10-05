import 'shared/pulse_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'shared/app_appearance.dart';
import 'pages/home_page.dart';
import 'shared/window_safe_area.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerPulseIconLicenses();
  runApp(const MclashApp());
}

class MclashApp extends StatelessWidget {
  const MclashApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mclash Root',
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: buildPulseTheme(Brightness.light),
        darkTheme: buildPulseTheme(Brightness.dark),
        builder: (context, child) => WindowSafeArea(child: child!),
        home: const HomePage(),
      );
}
