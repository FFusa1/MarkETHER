import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's starred symbols on the device.
class Watchlist extends ChangeNotifier {
  static const _key = 'watchlist';
  final Set<String> _symbols = {};

  Set<String> get symbols => Set.unmodifiable(_symbols);
  bool contains(String symbol) => _symbols.contains(symbol);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _symbols
      ..clear()
      ..addAll(prefs.getStringList(_key) ?? const []);
    notifyListeners();
  }

  Future<void> toggle(String symbol) async {
    if (!_symbols.remove(symbol)) _symbols.add(symbol);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _symbols.toList());
  }
}
