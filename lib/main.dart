import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'watchlist.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final watchlist = Watchlist()..load();
  runApp(MarketAiApp(watchlist: watchlist));
}

class MarketAiApp extends StatelessWidget {
  final Watchlist watchlist;
  const MarketAiApp({super.key, required this.watchlist});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MarkETHER',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF26A69A),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E1116),
        cardTheme: const CardThemeData(
          color: Color(0xFF171B22),
          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        ),
      ),
      home: HomeScreen(watchlist: watchlist),
    );
  }
}
