import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'engine/stockfish_service.dart';
import 'game_notifier.dart';
import 'home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider<GameNotifier>(
      create: (_) => GameNotifier(),
      child: const ChessRexxinApp(),
    ),
  );
}

class ChessRexxinApp extends StatefulWidget {
  const ChessRexxinApp({super.key});

  @override
  State<ChessRexxinApp> createState() => _ChessRexxinAppState();
}

class _ChessRexxinAppState extends State<ChessRexxinApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Aplikasi ditutup: hentikan analisis dan matikan engine.
    if (state == AppLifecycleState.detached) {
      unawaited(StockfishService.instance.shutdown());
    }
  }

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
