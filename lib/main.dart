import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const CoupApp());
}

class CoupApp extends StatelessWidget {
  const CoupApp({super.key});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4A84B);
    return MaterialApp(
      title: 'Coup LAN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
          primary: gold,
          surface: const Color(0xFF16141A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0E12),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0E12),
          centerTitle: true,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
