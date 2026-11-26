import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:market_ai/bot/paper_bot.dart';
import 'package:market_ai/models.dart';
import 'package:market_ai/patterns.dart';

/// Candles that walk through [prices]: open = previous close, 0.3 wicks.
List<Candle> walk(List<double> prices) {
  final out = <Candle>[];
  var prev = prices.first;
  for (var i = 0; i < prices.length; i++) {
    final p = prices[i];
    out.add(Candle(
      openTime: DateTime(2025, 1, 1).add(Duration(minutes: 15 * i)),
      open: prev,
      high: math.max(prev, p) + 0.3,
      low: math.min(prev, p) - 0.3,
      close: p,
      volume: 1,
      quoteVolume: 100,
    ));
    prev = p;
  }
  return out;
}

/// [n] steps from [a] (excluded) to [b] (included).
List<double> line(double a, double b, int n) => [for (var i = 1; i <= n; i++) a + (b - a) * i / n];

Candle k(double o, double h, double l, double c) => Candle(
      openTime: DateTime(2025),
      open: o,
      high: h,
      low: l,
      close: c,
      volume: 1,
      quoteVolume: 100,
    );

void main() {
  group('chart patterns', () {
    test('finds a cup and handle', () {
      final p = <double>[
        for (var i = 0; i < 15; i++) 95 + i * 5 / 14, // rise to the left rim
        for (var i = 15; i < 56; i++) 100 - 8 * math.sin(math.pi * (i - 14) / 41), // the cup
        99.2, 98.6, 98.0, 98.2, 98.5, 98.8, 99.0, 99.2, 99.3, 99.5, 99.6, 99.6, // the handle
      ];
      final r = cupAndHandle(walk(p));
      expect(r, isNotNull);
      expect(r!.bullish, isTrue);
      expect(r.candle, isFalse);
    });

    test('a steady rise is not a cup and handle', () {
      expect(cupAndHandle(walk([for (var i = 0; i < 60; i++) 100 + i * 0.2])), isNull);
    });

    test('finds a double bottom', () {
      final p = [105.0, ...line(105, 98, 15), ...line(98, 103, 7), ...line(103, 98.1, 8), ...line(98.1, 102.5, 10)];
      expect(doubleBottom(walk(p)), isNotNull);
    });

    test('finds a bull flag', () {
      final p = [
        for (var i = 0; i < 20; i++) 100 + (i.isOdd ? 0.2 : 0.0),
        ...line(100, 106, 6), // the pole
        105.5, 105, 104.6, 104.3, 104.5, 104.8, 105.2, 105.6, // the flag
      ];
      expect(bullFlag(walk(p)), isNotNull);
    });

    test('labels names with the timeframe', () {
      final p = [105.0, ...line(105, 98, 15), ...line(98, 103, 7), ...line(103, 98.1, 8), ...line(98.1, 102.5, 10)];
      final found = detectPatterns(chart: walk(p), chartLabel: '15m', candles: walk(p), candleLabel: '5m');
      expect(found.map((e) => e.name), contains('Double bottom (15m)'));
    });
  });

  group('candle patterns (on the last closed candle)', () {
    final decline = [for (var i = 0; i < 25; i++) k(110 - i * 0.3, 110.2 - i * 0.3, 109.5 - i * 0.3, 109.7 - i * 0.3)];

    test('bullish engulfing after a drop', () {
      final c = [...decline, k(102.6, 102.7, 101.9, 102.0), k(101.9, 103.3, 101.8, 103.2), k(103.2, 103.4, 103.1, 103.3)];
      final r = bullishEngulfing(c);
      expect(r, isNotNull);
      expect(r!.candle, isTrue);
    });

    test('hammer after a drop', () {
      final c = [...decline, k(102.3, 102.45, 100.5, 102.4), k(102.4, 102.6, 102.3, 102.5)];
      expect(hammer(c), isNotNull);
    });

    test('no hammer when the wick is short', () {
      final c = [...decline, k(102.3, 102.45, 102.0, 102.4), k(102.4, 102.6, 102.3, 102.5)];
      expect(hammer(c), isNull);
    });
  });

  group('learning from patterns', () {
    const cup = ChartPattern('Cup and handle (15m)', bullish: true, candle: false, note: '');
    const hammerP = ChartPattern('Hammer (5m)', bullish: true, candle: true, note: '');
    const top = ChartPattern('Double top (15m)', bullish: false, candle: false, note: '');
    final s = BotSettings();

    String? why(Rating r, int score, List<ChartPattern> p, {Set<String> losing = const {}, BotSettings? set}) =>
        entryReason(
            rating: r, score: score, netRiskReward: 1.5, patterns: p, settings: set ?? s, losing: losing);

    test('signals still decide first', () {
      expect(why(Rating.strongBuy, 75, const []), 'LONG NOW');
      expect(why(Rating.buy, 60, const []), 'LONG');
      expect(why(Rating.neutral, 52, const []), isNull);
    });

    test('a bullish chart pattern can buy a WAIT coin with score 50+', () {
      expect(why(Rating.neutral, 52, const [cup]), 'Pattern');
      expect(why(Rating.neutral, 48, const [cup]), isNull); // score too low
      expect(why(Rating.neutral, 52, const [hammerP]), isNull); // single candle is not enough
      expect(why(Rating.neutral, 52, const [cup, top]), isNull); // mixed signals
      expect(why(Rating.neutral, 52, const [cup], set: BotSettings(patternTrades: false)), isNull);
    });

    test('a pattern that lost over 20+ trades is skipped', () {
      expect(why(Rating.strongBuy, 75, const [cup], losing: {'Cup and handle (15m)'}), isNull);
      expect(
          why(Rating.strongBuy, 75, const [cup],
              losing: {'Cup and handle (15m)'}, set: BotSettings(skipLosingPatterns: false)),
          'LONG NOW');
    });

    Trade t(double exit, List<String> p) => Trade(
          symbol: 'AUSDT',
          base: 'A',
          entryTime: DateTime(2025),
          exitTime: DateTime(2025).add(const Duration(minutes: 10)),
          entryPrice: 100,
          exitPrice: exit,
          qty: 0.1,
          reason: 'test',
          score: 60,
          features: const {},
          patterns: p,
          entry: 'Pattern',
        );

    test('results per pattern, losers only after 20 trades', () {
      final trades = [
        for (var i = 0; i < 20; i++) t(99, ['Bull flag (15m)']),
        for (var i = 0; i < 10; i++) t(98, ['Double bottom (15m)']),
        for (var i = 0; i < 20; i++) t(102, ['Cup and handle (15m)']),
      ];
      final stats = patternStatsOf(trades);
      expect(stats.first.name, 'Cup and handle (15m)');
      expect(stats.first.stats.trades, 20);
      expect(stats.first.stats.avgPct, closeTo(1.8, 1e-9));
      expect(losingPatterns(trades), {'Bull flag (15m)'}); // double bottom: only 10 trades
      expect(statsByTier(trades).pattern.trades, 50);
    });

    test('patterns and entry survive save/load', () {
      final back = Trade.fromJson(t(101, ['Hammer (5m)']).toJson());
      expect(back.patterns, ['Hammer (5m)']);
      expect(back.tier, 'Pattern');
    });
  });
}
