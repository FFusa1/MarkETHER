import 'package:flutter/material.dart';

import 'bot/background.dart';
import 'bot/paper_bot.dart';
import 'screens/bot_screen.dart';
import 'screens/home_screen.dart';
import 'watchlist.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundKeeper.initPort();
  final watchlist = Watchlist()..load();
  final bot = PaperBot()
    ..onSessionStart = BackgroundKeeper.start
    ..onStatusText = BackgroundKeeper.update
    ..onSessionStop = BackgroundKeeper.stop;
  bot.load().then((_) {
    if (bot.settings.autoStart) bot.start();
  });
  runApp(MarketAiApp(watchlist: watchlist, bot: bot));
}

class MarketAiApp extends StatelessWidget {
  final Watchlist watchlist;
  final PaperBot bot;
  const MarketAiApp({super.key, required this.watchlist, required this.bot});

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
      home: AppShell(watchlist: watchlist, bot: bot),
    );
  }
}

/// Bottom navigation between the market scanner and the trading bot.
class AppShell extends StatefulWidget {
  final Watchlist watchlist;
  final PaperBot bot;
  const AppShell({super.key, required this.watchlist, required this.bot});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back to the app: settle anything that happened while it was
    // paused and scan straight away.
    _lifecycle = AppLifecycleListener(onResume: widget.bot.resumed);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(watchlist: widget.watchlist),
          BotScreen(bot: widget.bot),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: widget.bot,
        builder: (context, _) => NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.radar), label: 'Scanner'),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: widget.bot.running,
                backgroundColor: const Color(0xFF26A69A),
                smallSize: 8,
                child: const Icon(Icons.smart_toy_outlined),
              ),
              label: widget.bot.running ? 'Bot · running' : 'Bot',
            ),
          ],
        ),
      ),
    );
  }
}
