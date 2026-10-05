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

class MclashApp extends StatefulWidget {
  const MclashApp({super.key});

  @override
  State<MclashApp> createState() => _MclashAppState();
}

class _MclashAppState extends State<MclashApp> {
  final _appearance = AppearanceController();
  @override
  void initState() {
    super.initState();
    _appearance.load();
  }

  @override
  void dispose() {
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _appearance,
        builder: (context, _) => AppearanceScope(
            controller: _appearance,
            child: MaterialApp(
              title: 'Mclash Root',
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              debugShowCheckedModeBanner: false,
              themeMode: ThemeMode.system,
              theme: buildPulseTheme(Brightness.light,
                  seedColor: _appearance.color),
              darkTheme: buildPulseTheme(Brightness.dark,
                  seedColor: _appearance.color),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: AppearanceTextScaler(
                        MediaQuery.textScalerOf(context),
                        _appearance.fontScale)),
                child: WindowSafeArea(child: child!),
              ),
              home: const HomePage(),
            )),
      );
}
