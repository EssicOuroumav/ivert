import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const IvertApp());
}

class IvertApp extends StatelessWidget {
  const IvertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IVERT',
      debugShowCheckedModeBanner: false,
      theme: ivertTheme(),
      home: const SplashScreen(),
    );
  }
}
