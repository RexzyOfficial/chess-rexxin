import 'package:flutter/material.dart';

import 'home_screen.dart';

void main() {
  runApp(const ChessRexxinApp());
}

class ChessRexxinApp extends StatelessWidget {
  const ChessRexxinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Rexxin',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF161512),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF769656),
          brightness: Brightness.dark,
          surface: const Color(0xFF262421),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161512),
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
