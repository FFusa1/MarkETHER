/// Read-only access to Binance public market data. No API key, no trading.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'analyzer.dart';
import 'models.dart';

class BinanceApi {
  /// The second host is Binance's official public market-data mirror,
  /// used automatically if the main API is unreachable.
  static const _hosts = ['https://api.binance.com', 'https://data-api.binance.vision'];
  int _hostIndex = 0;
  final http.Client _client = http.Client();

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    Object? lastError;
    for (var attempt = 0; attempt < _hosts.length; attempt++) {
      final idx = (_hostIndex + attempt) % _hosts.length;
      final uri = Uri.parse('${_hosts[idx]}$path').replace(queryParameters: query);
      try {
        final res = await _client.get(uri).timeout(const Duration(seconds: 20));
        if (res.statusCode == 200) {
          _hostIndex = idx;
          return jsonDecode(res.body);
        }
        lastError = 'HTTP ${res.statusCode}';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Could not reach Binance ($lastError). Check your internet connection.');
  }

  Future<List<Ticker>> tickers24h() async {
    final data = await _get('/api/v3/ticker/24hr') as List<dynamic>;
    return data.map((e) => Ticker.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Candle>> klines(String symbol, String interval, {int limit = 250}) async {
    final data = await _get('/api/v3/klines', {
      'symbol': symbol,
      'interval': interval,
      'limit': '$limit',
    }) as List<dynamic>;
    return data.map((e) => Candle.fromJson(e as List<dynamic>)).toList();
  }
}

/// Stablecoins, fiat, wrapped and pegged assets — not worth "analysing".
const _excludedBases = {
  'USDC', 'FDUSD', 'TUSD', 'BUSD', 'DAI', 'USDP', 'USDE', 'PYUSD', 'USD1', 'XUSD',
  'BFUSD', 'RLUSD', 'USDS', 'EUR', 'EURI', 'AEUR', 'GBP', 'TRY', 'BRL', 'PAXG',
  'XAUT', 'WBTC', 'WBETH', 'BETH', 'BNSOL', 'UST', 'USTC', 'SUSD', 'U', 'USDD',
  'FRAX', 'LUSD', 'GUSD', 'USDT',
};
// Any other stablecoin is caught by isPegged() in the analyzer.

class MarketScanner {
  final BinanceApi api;
  MarketScanner([BinanceApi? api]) : api = api ?? BinanceApi();

  /// Picks the [topN] most-traded USDT pairs, downloads their 1d and 4h
  /// candles and scores each one.
  Future<ScanResult> scan({
    int topN = 50,
    double minQuoteVolume = 5e6,
    void Function(int done, int total)? onProgress,
  }) async {
    final tickers = await api.tickers24h();
    final universe = tickers.where((t) {
      if (!t.symbol.endsWith('USDT')) return false;
      final base = t.symbol.substring(0, t.symbol.length - 4);
      if (base.isEmpty || _excludedBases.contains(base)) return false;
      if (base.endsWith('DOWN') || base.endsWith('BULL') || base.endsWith('BEAR')) return false;
      return t.quoteVolume >= minQuoteVolume && t.trades > 0 && t.lastPrice > 0;
    }).toList()
      ..sort((a, b) => b.quoteVolume.compareTo(a.quoteVolume));

    final selected = universe.take(topN).toList();
    if (!selected.any((t) => t.symbol == 'BTCUSDT')) {
      final btc = tickers.where((t) => t.symbol == 'BTCUSDT');
      if (btc.isNotEmpty) selected.insert(0, btc.first);
    }

    final btcDaily = await api.klines('BTCUSDT', '1d', limit: 250);
    final regime = analyzeRegime(btcDaily);

    final results = <CoinAnalysis>[];
    var done = 0;
    var failed = 0;
    final total = selected.length;
    onProgress?.call(0, total);

    // Small worker pool keeps us well under Binance rate limits.
    var next = 0;
    Future<void> worker() async {
      while (next < selected.length) {
        final t = selected[next++];
        try {
          final daily = t.symbol == 'BTCUSDT'
              ? btcDaily
              : await api.klines(t.symbol, '1d', limit: 250);
          final h4 = await api.klines(t.symbol, '4h', limit: 200);
          final a = analyzeCoin(
              ticker: t, daily: daily, h4: h4, btcDaily: btcDaily, regime: regime);
          if (a != null) results.add(a);
        } catch (_) {
          failed++;
        }
        done++;
        onProgress?.call(done, total);
      }
    }

    await Future.wait(List.generate(6, (_) => worker()));
    results.sort((a, b) => b.score.compareTo(a.score));
    return ScanResult(results, regime, DateTime.now(), failed);
  }
}
