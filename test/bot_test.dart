import 'package:flutter_test/flutter_test.dart';
import 'package:market_ai/bot/paper_bot.dart';
import 'package:market_ai/models.dart';

final t0 = DateTime(2025, 6, 1, 12);

Position pos({double entry = 100, double stop = 99, double target = 102, DateTime? checked}) =>
    Position(
      symbol: 'AUSDT',
      base: 'A',
      entryTime: t0,
      entryPrice: entry,
      qty: 0.1,
      stop: stop,
      target: target,
      score: 75,
      features: const {'Momentum': 100, 'Order book': 30, 'Penalties': 0},
      lastChecked: checked ?? t0,
    );

Candle m1(int minute, {required double high, required double low, double? open}) => Candle(
      openTime: t0.add(Duration(minutes: minute)),
      open: open ?? (high + low) / 2,
      high: high,
      low: low,
      close: (high + low) / 2,
      volume: 1,
      quoteVolume: 100,
    );

Trade trade(double exit,
        {Map<String, int> f = const {'Momentum': 100}, int minute = 0, int score = 70}) =>
    Trade(
      symbol: 'AUSDT',
      base: 'A',
      entryTime: t0.add(Duration(minutes: minute)),
      exitTime: t0.add(Duration(minutes: minute + 10)),
      entryPrice: 100,
      exitPrice: exit,
      qty: 0.1,
      reason: 'test',
      score: score,
      features: f,
    );

void main() {
  const hour = Duration(minutes: 60);

  group('exitOnPrice', () {
    test('stop fills at the bid, target at the target, otherwise hold', () {
      final p = pos();
      expect(exitOnPrice(p, 98.5, t0, hour)!.reason, 'Stop');
      expect(exitOnPrice(p, 98.5, t0, hour)!.price, 98.5);
      expect(exitOnPrice(p, 102.4, t0, hour)!.price, 102);
      expect(exitOnPrice(p, 100.5, t0, hour), isNull);
    });

    test('time limit closes at the bid', () {
      final e = exitOnPrice(pos(), 100.3, t0.add(const Duration(minutes: 61)), hour)!;
      expect(e.reason, 'Time limit');
      expect(e.price, 100.3);
    });
  });

  group('replayExit (app was closed)', () {
    test('finds the target hit while closed', () {
      final e = replayExit(pos(), [m1(1, high: 100.5, low: 99.5), m1(2, high: 102.1, low: 100)],
          t0.add(hour))!;
      expect(e.reason, 'Target (app closed)');
      expect(e.price, 102);
    });

    test('a candle touching stop and target counts as a stop', () {
      final e = replayExit(pos(), [m1(1, high: 103, low: 98)], t0.add(hour))!;
      expect(e.reason, 'Stop (app closed)');
      expect(e.price, 99);
    });

    test('time limit reached while closed', () {
      final e = replayExit(pos(), [m1(30, high: 100.5, low: 99.5), m1(60, high: 100.6, low: 99.6, open: 100.2)],
          t0.add(hour))!;
      expect(e.reason, 'Time limit (app closed)');
      expect(e.price, 100.2);
    });

    test('nothing happened yet: keep holding', () {
      expect(replayExit(pos(), [m1(5, high: 100.5, low: 99.5)], t0.add(hour)), isNull);
    });

    test('ignores candles from before the last live check', () {
      final p = pos(checked: t0.add(const Duration(minutes: 10)));
      expect(replayExit(p, [m1(2, high: 103, low: 98), m1(11, high: 100.5, low: 99.5)], t0.add(hour)),
          isNull);
    });
  });

  group('results', () {
    test('fees are charged on both sides', () {
      final t = trade(100); // flat price
      expect(t.netPct, closeTo(-0.2, 1e-9));
      expect(t.win, isFalse);
    });

    test('stats: win rate, streak, profit factor', () {
      // newest first: win, loss, loss, loss, win
      final s = BotStats.of([trade(101), trade(99), trade(99), trade(99), trade(102)]);
      expect(s.trades, 5);
      expect(s.wins, 2);
      expect(s.winRate, closeTo(40, 1e-9));
      expect(s.worstLosingStreak, 3);
      expect(s.profitFactor, greaterThan(0));
    });

    test('insights find the signal that separates winners from losers', () {
      final trades = [
        for (var i = 0; i < 6; i++) trade(101.5, f: const {'Momentum': 100, 'Volume': 20}),
        for (var i = 0; i < 6; i++) trade(98.5, f: const {'Momentum': 20, 'Volume': 20}),
        for (var i = 0; i < 6; i++) trade(101.5, f: const {'Momentum': 100, 'Volume': 90}),
        for (var i = 0; i < 6; i++) trade(98.5, f: const {'Momentum': 20, 'Volume': 90}),
      ];
      final ins = insightsOf(trades);
      final momentum = ins.firstWhere((i) => i.category == 'Momentum');
      final volume = ins.firstWhere((i) => i.category == 'Volume');
      expect(momentum.enoughData, isTrue);
      expect(momentum.edge, greaterThan(2));
      expect(volume.edge.abs(), lessThan(0.01));
      expect(ins.first.category, 'Momentum');
    });
  });

  group('entry level', () {
    test('LONG NOW always enters; LONG only when "LONG and above" is set', () {
      expect(shouldEnter(Rating.strongBuy, false), isTrue);
      expect(shouldEnter(Rating.strongBuy, true), isTrue);
      expect(shouldEnter(Rating.buy, false), isFalse);
      expect(shouldEnter(Rating.buy, true), isTrue);
      expect(shouldEnter(Rating.neutral, true), isFalse);
      expect(shouldEnter(Rating.avoid, true), isFalse);
    });

    test('results split into LONG NOW (70+) and LONG (below 70)', () {
      final tiers = statsByTier([
        trade(102, score: 75),
        trade(99, score: 70),
        trade(101, score: 69),
        trade(98, score: 60),
        trade(97, score: 58),
      ]);
      expect(tiers.longNow.trades, 2);
      expect(tiers.longNow.wins, 1);
      expect(tiers.long.trades, 3);
      expect(tiers.long.wins, 1);
      expect(tiers.long.netUsd, lessThan(0));
    });

    test('"Enter on" setting survives save/load and defaults to LONG and above', () {
      expect(BotSettings.fromJson(const {}).enterOnLong, isTrue);
      expect(BotSettings.fromJson(BotSettings(enterOnLong: false).toJson()).enterOnLong, isFalse);
    });
  });

  test('positions and trades survive save/load as JSON', () {
    final p = Position.fromJson(pos().toJson());
    expect(p.stop, 99);
    expect(p.features['Momentum'], 100);
    final t = Trade.fromJson(trade(101).toJson());
    expect(t.netPct, closeTo(0.8, 1e-9));
    final s = BotSettings.fromJson(BotSettings(tradeSize: 7).toJson());
    expect(s.tradeSize, 7);
    expect(s.autoStart, isFalse);
  });
}
