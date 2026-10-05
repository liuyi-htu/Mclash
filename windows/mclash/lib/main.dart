import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_appearance.dart';
import 'home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MclashApp());
}

class MclashApp extends StatelessWidget {
  const MclashApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mclash',
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: buildPulseTheme(Brightness.light),
        darkTheme: buildPulseTheme(Brightness.dark),
        home: const HomePage(),
      );
}
