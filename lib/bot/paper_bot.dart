/// Session-based paper-trading bot.
///
/// Starts when the app opens (if auto-start is on) and stops taking new trades
/// when the app closes. Trades still open while the app was closed are settled
/// on the next start by replaying the 1-minute candles that were missed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../binance_api.dart';
import '../models.dart';

/// Binance spot fee per side (0.1%), paid on entry and on exit.
const feePerSidePct = 0.1;

class BotSettings {
  double tradeSize;
  int maxOpen;
  double dailyLossLimit;
  int timeLimitMin;
  int cooldownMin;
  int topN;
  bool autoStart;

  /// true = also enter on LONG (score 56–69), not only LONG NOW (70+).
  bool enterOnLong;

  /// Also buy when a bullish chart pattern shows up and the score is 50+,
  /// so the bot can learn whether the pattern works on its own.
  bool patternTrades;

  /// Skip coins showing a pattern that lost money over 20+ trades.
  bool skipLosingPatterns;

  BotSettings({
    this.enterOnLong = true,
    this.patternTrades = true,
    this.skipLosingPatterns = true,
    this.tradeSize = 10,
    this.maxOpen = 3,
    this.dailyLossLimit = 5,
    this.timeLimitMin = 60,
    this.cooldownMin = 15,
    this.topN = 50,
    this.autoStart = false,
  });

  Map<String, dynamic> toJson() => {
        'tradeSize': tradeSize,
        'maxOpen': maxOpen,
        'dailyLossLimit': dailyLossLimit,
        'timeLimitMin': timeLimitMin,
        'cooldownMin': cooldownMin,
        'topN': topN,
        'autoStart': autoStart,
        'enterOnLong': enterOnLong,
        'patternTrades': patternTrades,
        'skipLosingPatterns': skipLosingPatterns,
      };

  factory BotSettings.fromJson(Map<String, dynamic> j) => BotSettings(
        tradeSize: (j['tradeSize'] as num?)?.toDouble() ?? 10,
        maxOpen: (j['maxOpen'] as num?)?.toInt() ?? 3,
        dailyLossLimit: (j['dailyLossLimit'] as num?)?.toDouble() ?? 5,
        timeLimitMin: (j['timeLimitMin'] as num?)?.toInt() ?? 60,
        cooldownMin: (j['cooldownMin'] as num?)?.toInt() ?? 15,
        topN: (j['topN'] as num?)?.toInt() ?? 50,
        autoStart: j['autoStart'] as bool? ?? false,
        enterOnLong: j['enterOnLong'] as bool? ?? true,
        patternTrades: j['patternTrades'] as bool? ?? true,
        skipLosingPatterns: j['skipLosingPatterns'] as bool? ?? true,
      );
}

class Position {
  final String symbol;
  final String base;
  final DateTime entryTime;
  final double entryPrice;
  final double qty;
  final double stop;
  final double target;
  final int score;

  /// Strength 0–100 of each score category at entry (for learning).
  final Map<String, int> features;

  /// Patterns seen at entry, e.g. "Cup and handle (15m)".
  final List<String> patterns;

  /// Why it was bought: 'LONG NOW', 'LONG' or 'Pattern'.
  final String entry;
  DateTime lastChecked;
  double? lastBid;

  Position({
    required this.symbol,
    required this.base,
    required this.entryTime,
    required this.entryPrice,
    required this.qty,
    required this.stop,
    required this.target,
    required this.score,
    required this.features,
    this.patterns = const [],
    this.entry = '',
    required this.lastChecked,
    this.lastBid,
  });

  double get size => entryPrice * qty;

  /// Profit in % if sold at [price] now, after both fees.
  double netPctAt(double price) => (price / entryPrice - 1) * 100 - 2 * feePerSidePct;

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'base': base,
        'entryTime': entryTime.millisecondsSinceEpoch,
        'entryPrice': entryPrice,
        'qty': qty,
        'stop': stop,
        'target': target,
        'score': score,
        'features': features,
        'patterns': patterns,
        'entry': entry,
        'lastChecked': lastChecked.millisecondsSinceEpoch,
        'lastBid': lastBid,
      };

  factory Position.fromJson(Map<String, dynamic> j) => Position(
        symbol: j['symbol'] as String,
        base: j['base'] as String,
        entryTime: DateTime.fromMillisecondsSinceEpoch((j['entryTime'] as num).toInt()),
        entryPrice: (j['entryPrice'] as num).toDouble(),
        qty: (j['qty'] as num).toDouble(),
        stop: (j['stop'] as num).toDouble(),
        target: (j['target'] as num).toDouble(),
        score: (j['score'] as num).toInt(),
        features: (j['features'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt())),
        patterns: _strings(j['patterns']),
        entry: j['entry'] as String? ?? '',
        lastChecked: DateTime.fromMillisecondsSinceEpoch((j['lastChecked'] as num).toInt()),
        lastBid: (j['lastBid'] as num?)?.toDouble(),
      );
}

class Trade {
  final String symbol;
  final String base;
  final DateTime entryTime;
  final DateTime exitTime;
  final double entryPrice;
  final double exitPrice;
  final double qty;
  final String reason;
  final int score;
  final Map<String, int> features;
  final List<String> patterns;

  /// Why it was bought: 'LONG NOW', 'LONG' or 'Pattern' ('' = older trade).
  final String entry;

  const Trade({
    required this.symbol,
    required this.base,
    required this.entryTime,
    required this.exitTime,
    required this.entryPrice,
    required this.exitPrice,
    required this.qty,
    required this.reason,
    required this.score,
    required this.features,
    this.patterns = const [],
    this.entry = '',
  });

  double get netPct => (exitPrice / entryPrice - 1) * 100 - 2 * feePerSidePct;
  double get netUsd => entryPrice * qty * netPct / 100;
  bool get win => netUsd > 0;
  Duration get duration => exitTime.difference(entryTime);

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'base': base,
        'entryTime': entryTime.millisecondsSinceEpoch,
        'exitTime': exitTime.millisecondsSinceEpoch,
        'entryPrice': entryPrice,
        'exitPrice': exitPrice,
        'qty': qty,
        'reason': reason,
        'score': score,
        'features': features,
        'patterns': patterns,
        'entry': entry,
      };

  factory Trade.fromJson(Map<String, dynamic> j) => Trade(
        symbol: j['symbol'] as String,
        base: j['base'] as String,
        entryTime: DateTime.fromMillisecondsSinceEpoch((j['entryTime'] as num).toInt()),
        exitTime: DateTime.fromMillisecondsSinceEpoch((j['exitTime'] as num).toInt()),
        entryPrice: (j['entryPrice'] as num).toDouble(),
        exitPrice: (j['exitPrice'] as num).toDouble(),
        qty: (j['qty'] as num).toDouble(),
        reason: j['reason'] as String,
        score: (j['score'] as num).toInt(),
        features: (j['features'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt())),
        patterns: _strings(j['patterns']),
        entry: j['entry'] as String? ?? '',
      );

  /// Entry level, also for trades saved before it was recorded.
  String get tier => entry.isNotEmpty
      ? entry
      : (score >= longNowMinScore ? 'LONG NOW' : (score >= longMinScore ? 'LONG' : 'Pattern'));
}

List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];

// ---------------------------------------------------------------------------
// Pure trading rules (unit-tested)
// ---------------------------------------------------------------------------

/// Category strengths 0–100 from a scalp analysis, plus total penalties.
Map<String, int> featuresOf(CoinAnalysis c) {
  final pts = <String, int>{};
  final max = <String, int>{};
  var penalties = 0;
  for (final s in c.signals) {
    if (s.maxPoints > 0) {
      pts[s.category] = (pts[s.category] ?? 0) + s.points;
      max[s.category] = (max[s.category] ?? 0) + s.maxPoints;
    } else if (s.points < 0) {
      penalties -= s.points;
    }
  }
  return {
    for (final k in pts.keys) k: max[k]! == 0 ? 0 : (pts[k]! * 100 / max[k]!).round(),
    'Penalties': penalties,
  };
}

/// Which scalp ratings the bot buys.
bool shouldEnter(Rating r, bool enterOnLong) =>
    r == Rating.strongBuy || (enterOnLong && r == Rating.buy);

/// Score of 70+ is LONG NOW; 56–69 is LONG (scores and labels always agree).
const longNowMinScore = 70;

/// LONG starts at 56.
const longMinScore = 56;

/// Pattern-only buys need at least this score (WAIT, not AVOID).
const patternMinScore = 50;

/// Results split by entry signal, to decide which level to use live.
({BotStats longNow, BotStats long, BotStats pattern}) statsByTier(List<Trade> trades) => (
      longNow: BotStats.of(trades.where((t) => t.tier == 'LONG NOW').toList()),
      long: BotStats.of(trades.where((t) => t.tier == 'LONG').toList()),
      pattern: BotStats.of(trades.where((t) => t.tier == 'Pattern').toList()),
    );

/// A pattern needs this many trades before its result counts.
const patternMinTrades = 20;

/// Results for each pattern seen at entry, best average first.
List<({String name, BotStats stats})> patternStatsOf(List<Trade> trades) {
  final names = <String>{for (final t in trades) ...t.patterns};
  final out = [
    for (final n in names)
      (name: n, stats: BotStats.of(trades.where((t) => t.patterns.contains(n)).toList())),
  ];
  out.sort((a, b) => b.stats.avgPct.compareTo(a.stats.avgPct));
  return out;
}

/// Patterns that lost money after fees over at least [patternMinTrades] trades.
Set<String> losingPatterns(List<Trade> trades) => {
      for (final p in patternStatsOf(trades))
        if (p.stats.trades >= patternMinTrades && p.stats.netUsd < 0) p.name,
    };

/// Why the bot buys a coin ('LONG NOW', 'LONG', 'Pattern'), or null to skip.
String? entryReason({
  required Rating rating,
  required int score,
  required double netRiskReward,
  required List<ChartPattern> patterns,
  required BotSettings settings,
  Set<String> losing = const {},
}) {
  if (settings.skipLosingPatterns && patterns.any((p) => losing.contains(p.name))) return null;
  if (shouldEnter(rating, settings.enterOnLong)) {
    return rating == Rating.strongBuy ? 'LONG NOW' : 'LONG';
  }
  if (settings.patternTrades &&
      score >= patternMinScore &&
      netRiskReward >= 1 &&
      patterns.any((p) => p.bullish && !p.candle) &&
      !patterns.any((p) => !p.bullish)) {
    return 'Pattern';
  }
  return null;
}

/// Exit decision for a live price check, or null to keep holding.
/// Stops fill at the current bid (market sell); targets fill at the target
/// (resting limit sell).
({double price, String reason})? exitOnPrice(
    Position p, double bid, DateTime now, Duration timeLimit) {
  if (bid <= p.stop) return (price: bid, reason: 'Stop');
  if (bid >= p.target) return (price: p.target, reason: 'Target');
  if (now.difference(p.entryTime) >= timeLimit) return (price: bid, reason: 'Time limit');
  return null;
}

/// Replays 1-minute candles missed while the app was closed. If a candle
/// touches both stop and target we assume the stop came first (conservative).
({double price, DateTime time, String reason})? replayExit(
    Position p, List<Candle> m1, DateTime deadline) {
  for (final k in m1) {
    if (k.openTime.isBefore(p.lastChecked.subtract(const Duration(minutes: 1)))) continue;
    if (k.low <= p.stop) return (price: p.stop, time: k.openTime, reason: 'Stop (app closed)');
    if (k.high >= p.target) return (price: p.target, time: k.openTime, reason: 'Target (app closed)');
    if (!k.openTime.isBefore(deadline)) {
      return (price: k.open, time: k.openTime, reason: 'Time limit (app closed)');
    }
  }
  return null;
}

class BotStats {
  final int trades;
  final int wins;
  final double netUsd;
  final double avgWinPct;
  final double avgLossPct;
  final double profitFactor;
  final int worstLosingStreak;

  const BotStats(this.trades, this.wins, this.netUsd, this.avgWinPct, this.avgLossPct,
      this.profitFactor, this.worstLosingStreak);

  double get winRate => trades == 0 ? 0 : wins / trades * 100;

  /// Average result per trade in %, after fees.
  double get avgPct =>
      trades == 0 ? 0 : (avgWinPct * wins + avgLossPct * (trades - wins)) / trades;

  factory BotStats.of(List<Trade> trades) {
    if (trades.isEmpty) return const BotStats(0, 0, 0, 0, 0, 0, 0);
    final wins = trades.where((t) => t.win).toList();
    final losses = trades.where((t) => !t.win).toList();
    final grossWin = wins.fold<double>(0, (a, t) => a + t.netUsd);
    final grossLoss = losses.fold<double>(0, (a, t) => a - t.netUsd);
    var streak = 0, worst = 0;
    // trades are stored newest first; walk oldest first
    for (final t in trades.reversed) {
      if (t.win) {
        streak = 0;
      } else {
        streak++;
        worst = math.max(worst, streak);
      }
    }
    double avg(List<Trade> l) =>
        l.isEmpty ? 0 : l.fold<double>(0, (a, t) => a + t.netPct) / l.length;
    return BotStats(
      trades.length,
      wins.length,
      grossWin - grossLoss,
      avg(wins),
      avg(losses),
      grossLoss == 0 ? (grossWin > 0 ? double.infinity : 0) : grossWin / grossLoss,
      worst,
    );
  }
}

/// How one score category relates to results: trades where it was strong
/// (≥60% of its points) versus weak.
class Insight {
  final String category;
  final int strongN;
  final double strongWinRate;
  final double strongAvgPct;
  final int weakN;
  final double weakWinRate;
  final double weakAvgPct;

  const Insight(this.category, this.strongN, this.strongWinRate, this.strongAvgPct, this.weakN,
      this.weakWinRate, this.weakAvgPct);

  static const minPerGroup = 5;
  bool get enoughData => strongN >= minPerGroup && weakN >= minPerGroup;

  /// Positive = the category helps pick winners.
  double get edge => strongAvgPct - weakAvgPct;
}

List<Insight> insightsOf(List<Trade> trades) {
  final cats = <String>{};
  for (final t in trades) {
    cats.addAll(t.features.keys.where((k) => k != 'Penalties'));
  }
  final out = <Insight>[];
  for (final cat in cats) {
    final strong = trades.where((t) => (t.features[cat] ?? 0) >= 60).toList();
    final weak = trades.where((t) => t.features.containsKey(cat) && t.features[cat]! < 60).toList();
    double wr(List<Trade> l) => l.isEmpty ? 0 : l.where((t) => t.win).length / l.length * 100;
    double avg(List<Trade> l) =>
        l.isEmpty ? 0 : l.fold<double>(0, (a, t) => a + t.netPct) / l.length;
    out.add(Insight(cat, strong.length, wr(strong), avg(strong), weak.length, wr(weak), avg(weak)));
  }
  out.sort((a, b) => b.edge.compareTo(a.edge));
  return out;
}

// ---------------------------------------------------------------------------
// The bot
// ---------------------------------------------------------------------------

enum BotState { stopped, running, pausedDailyLimit }

class PaperBot extends ChangeNotifier {
  static const _prefsKey = 'paperBot.v1';
  static const scanEvery = Duration(seconds: 60);
  static const watchEvery = Duration(seconds: 15);

  final BinanceApi api;
  final MarketScanner scanner;

  PaperBot._(this.api) : scanner = MarketScanner(api);
  factory PaperBot([BinanceApi? api]) => PaperBot._(api ?? BinanceApi());

  BotSettings settings = BotSettings();
  final List<Position> open = [];
  final List<Trade> trades = [];
  final Map<String, DateTime> _cooldown = {};

  /// Hooks for the background service (set by the app; null in tests).
  Future<void> Function(String text)? onSessionStart;
  Future<void> Function(String text)? onStatusText;
  Future<void> Function()? onSessionStop;

  String get statusText {
    final pnl = todayPnl;
    final sign = pnl >= 0 ? '+' : '−';
    return 'Paper · ${open.length} open · today $sign\$${pnl.abs().toStringAsFixed(2)}';
  }

  bool running = false;
  bool busy = false;
  DateTime? lastScan;
  ScanResult? lastResult;
  String? lastError;
  String? lastEvent;
  Timer? _scanTimer;
  Timer? _watchTimer;

  BotState get state {
    if (!running) return BotState.stopped;
    if (todayPnl <= -settings.dailyLossLimit) return BotState.pausedDailyLimit;
    return BotState.running;
  }

  double get todayPnl {
    final now = DateTime.now();
    return trades
        .where((t) =>
            t.exitTime.year == now.year && t.exitTime.month == now.month && t.exitTime.day == now.day)
        .fold<double>(0, (a, t) => a + t.netUsd);
  }

  BotStats get stats => BotStats.of(trades);
  List<Insight> get insights => insightsOf(trades);

  // ---------------- persistence ----------------

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      settings = BotSettings.fromJson(j['settings'] as Map<String, dynamic>? ?? {});
      open
        ..clear()
        ..addAll((j['open'] as List<dynamic>? ?? [])
            .map((e) => Position.fromJson(e as Map<String, dynamic>)));
      trades
        ..clear()
        ..addAll((j['trades'] as List<dynamic>? ?? [])
            .map((e) => Trade.fromJson(e as Map<String, dynamic>)));
    } catch (e) {
      lastError = 'Could not load saved bot data: $e';
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey,
          jsonEncode({
            'settings': settings.toJson(),
            'open': open.map((p) => p.toJson()).toList(),
            'trades': trades.take(3000).map((t) => t.toJson()).toList(),
          }));
    } catch (_) {
      // Storage can be unavailable (private browsing); the bot keeps working.
    }
  }

  Future<void> updateSettings(void Function(BotSettings s) change) async {
    change(settings);
    notifyListeners();
    await _save();
  }

  // ---------------- session control ----------------

  Future<void> start() async {
    if (running) return;
    running = true;
    lastEvent = 'Session started';
    notifyListeners();
    await onSessionStart?.call(statusText);
    await catchUp();
    _scanTimer?.cancel();
    _watchTimer?.cancel();
    _scanTimer = Timer.periodic(scanEvery, (_) => _cycle());
    _watchTimer = Timer.periodic(watchEvery, (_) => _safeWatch());
    await _cycle();
  }

  void stop() {
    running = false;
    _scanTimer?.cancel();
    _watchTimer?.cancel();
    _scanTimer = null;
    _watchTimer = null;
    lastEvent = 'Session stopped — open trades are settled when you start again';
    notifyListeners();
    _save();
    onSessionStop?.call();
  }

  /// Called when the app comes back to the foreground.
  Future<void> resumed() async {
    if (!running) return;
    await catchUp();
    await _cycle();
  }

  Future<void> closePosition(Position p) async {
    try {
      final b = await api.bids([p.symbol]);
      final bid = b[p.symbol] ?? p.lastBid ?? p.entryPrice;
      _close(p, bid, 'Closed by you', DateTime.now());
    } catch (e) {
      lastError = e.toString();
    }
    notifyListeners();
    await _save();
  }

  Future<void> closeAll() async {
    if (open.isEmpty) return;
    try {
      final b = await api.bids(open.map((p) => p.symbol).toList());
      final now = DateTime.now();
      for (final p in [...open]) {
        _close(p, b[p.symbol] ?? p.lastBid ?? p.entryPrice, 'Closed by you', now);
      }
    } catch (e) {
      lastError = e.toString();
    }
    notifyListeners();
    await _save();
  }

  Future<void> resetPaper() async {
    open.clear();
    trades.clear();
    _cooldown.clear();
    lastEvent = 'Paper account reset';
    notifyListeners();
    await _save();
  }

  // ---------------- engine ----------------

  /// Settles open trades using the 1-minute candles missed while closed.
  Future<void> catchUp() async {
    final now = DateTime.now();
    final limit = Duration(minutes: settings.timeLimitMin);
    for (final p in [...open]) {
      if (now.difference(p.lastChecked) < const Duration(minutes: 2)) continue;
      final deadline = p.entryTime.add(limit);
      final end = now.isBefore(deadline) ? now : deadline.add(const Duration(minutes: 1));
      try {
        final m1 = await api.klinesRange(p.symbol, '1m', p.lastChecked, end);
        final exit = replayExit(p, m1, deadline);
        if (exit != null) {
          _close(p, exit.price, exit.reason, exit.time);
        } else {
          p.lastChecked = now;
        }
      } catch (e) {
        lastError = 'Catch-up failed for ${p.base}: $e';
      }
    }
    notifyListeners();
    await _save();
  }

  Future<void> _cycle() async {
    if (busy || !running) return;
    busy = true;
    notifyListeners();
    try {
      await _watch();
      if (state == BotState.running && open.length < settings.maxOpen) {
        final r = await scanner.scan(mode: TradeMode.scalp, topN: settings.topN);
        lastResult = r;
        lastScan = DateTime.now();
        _enter(r);
      }
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    } finally {
      busy = false;
      notifyListeners();
      await _save();
      if (running) await onStatusText?.call(statusText);
    }
  }

  Future<void> _safeWatch() async {
    if (busy || !running || open.isEmpty) return;
    try {
      await _watch();
      notifyListeners();
      await _save();
    } catch (_) {
      // next tick retries
    }
  }

  Future<void> _watch() async {
    if (open.isEmpty) return;
    final b = await api.bids(open.map((p) => p.symbol).toList());
    final now = DateTime.now();
    final limit = Duration(minutes: settings.timeLimitMin);
    for (final p in [...open]) {
      final bid = b[p.symbol];
      if (bid == null) continue;
      p.lastBid = bid;
      p.lastChecked = now;
      final exit = exitOnPrice(p, bid, now, limit);
      if (exit != null) _close(p, exit.price, exit.reason, now);
    }
  }

  void _enter(ScanResult r) {
    final now = DateTime.now();
    final losing = losingPatterns(trades);
    for (final c in r.coins) {
      if (open.length >= settings.maxOpen) break;
      if (state != BotState.running) break;
      final why = entryReason(
        rating: c.rating,
        score: c.score,
        netRiskReward: c.netRiskReward,
        patterns: c.patterns,
        settings: settings,
        losing: losing,
      );
      if (why == null) continue;
      if (open.any((p) => p.symbol == c.symbol)) continue;
      final cd = _cooldown[c.symbol];
      if (cd != null && now.isBefore(cd)) continue;
      if (c.entry <= 0 || c.stop >= c.entry) continue;
      open.add(Position(
        symbol: c.symbol,
        base: c.base,
        entryTime: now,
        entryPrice: c.entry,
        qty: settings.tradeSize / c.entry,
        stop: c.stop,
        target: c.target,
        score: c.score,
        features: featuresOf(c),
        patterns: c.patterns.map((p) => p.name).toList(),
        entry: why,
        lastChecked: now,
        lastBid: c.entry,
      ));
      final pats = c.patterns.isEmpty ? '' : ' · ${c.patterns.map((p) => p.name).join(', ')}';
      lastEvent = 'Bought ${c.base} at ${c.entry} ($why, score ${c.score})$pats';
    }
  }

  void _close(Position p, double price, String reason, DateTime time) {
    open.remove(p);
    final t = Trade(
      symbol: p.symbol,
      base: p.base,
      entryTime: p.entryTime,
      exitTime: time,
      entryPrice: p.entryPrice,
      exitPrice: price,
      qty: p.qty,
      reason: reason,
      score: p.score,
      features: p.features,
      patterns: p.patterns,
      entry: p.entry,
    );
    trades.insert(0, t);
    _cooldown[p.symbol] = time.add(Duration(minutes: settings.cooldownMin));
    final sign = t.netUsd >= 0 ? '+' : '−';
    lastEvent = 'Sold ${p.base}: $reason, $sign\$${t.netUsd.abs().toStringAsFixed(3)}';
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _watchTimer?.cancel();
    super.dispose();
  }
}
