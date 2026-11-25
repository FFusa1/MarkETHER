import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:market_ai/indicators.dart';
import 'package:market_ai/models.dart';
import 'package:market_ai/scalp_analyzer.dart';

/// Synthetic intraday candles with compounding drift and a small wobble.
List<Candle> bars(int n, double drift, {double start = 10, int minutes = 5, double volBoost = 1}) {
  final out = <Candle>[];
  var price = start;
  for (var i = 0; i < n; i++) {
    final open = price;
    price = price * (1 + drift) * (1 + 0.001 * math.sin(i / 2));
    final close = price;
    final boost = i >= n - 3 ? volBoost : 1.0;
    out.add(Candle(
      openTime: DateTime(2025, 1, 1).add(Duration(minutes: minutes * i)),
      open: open,
      high: math.max(open, close) * 1.002,
      low: math.min(open, close) * 0.998,
      close: close,
      volume: 1000 * boost,
      quoteVolume: 1000 * close * boost,
    ));
  }
  return out;
}

/// Order book around [price]; [bidWeight] > 1 puts more size on the bid side.
OrderBook book(double price, {double bidWeight = 1, double spreadPct = 0.01}) {
  final half = price * spreadPct / 200;
  final bid = price - half;
  final ask = price + half;
  return OrderBook(
    List.generate(20, (i) => [bid * (1 - i * 0.0002), 100 * bidWeight]),
    List.generate(20, (i) => [ask * (1 + i * 0.0002), 100.0]),
  );
}

Ticker tick(String s, double p) => Ticker(
    symbol: s, lastPrice: p, changePercent: 2, quoteVolume: 5e7, high: p, low: p, trades: 9999);

void main() {
  test('OrderBook spread and imbalance', () {
    final b = book(100, bidWeight: 3, spreadPct: 0.02);
    expect(b.spreadPct, closeTo(0.02, 1e-6));
    expect(b.imbalance(), greaterThan(0.7));
    expect(book(100).imbalance(), closeTo(0.5, 0.01));
  });

  test('vwap of flat-volume constant price equals the price', () {
    final c = bars(50, 0, start: 5);
    final v = lastOf(vwap(c, 20))!;
    expect(v, closeTo(c.last.close, c.last.close * 0.01));
  });

  test('ticker near \$1 with no movement looks pegged', () {
    expect(
        const Ticker(
                symbol: 'XUSDT', lastPrice: 1.0, changePercent: 0, quoteVolume: 1e8,
                high: 1.001, low: 0.999, trades: 1)
            .looksPegged,
        isTrue);
    expect(tick('AUSDT', 1.0).looksPegged, isTrue); // high == low
    expect(
        const Ticker(
                symbol: 'BUSDT', lastPrice: 1.0, changePercent: 5, quoteVolume: 1e8,
                high: 1.05, low: 0.95, trades: 1)
            .looksPegged,
        isFalse);
  });

  group('scalp analyzer', () {
    final btc = bars(100, 0.0005, start: 60000, minutes: 15);
    final regime = analyzeScalpRegime(btc);

    test('rising BTC on 15m is bullish', () {
      expect(regime.regime, Regime.bullish);
      expect(regime.returnLabel, '4h');
    });

    test('pumping coin with bids stacked beats dumping coin with asks stacked', () {
      final up5 = bars(200, 0.0015, volBoost: 3);
      final up15 = bars(100, 0.003, minutes: 15);
      final dn5 = bars(200, -0.0015, volBoost: 3);
      final dn15 = bars(100, -0.003, minutes: 15);
      final up = analyzeScalp(
          ticker: tick('UPUSDT', up5.last.close),
          m5: up5, m15: up15, book: book(up5.last.close, bidWeight: 3), regime: regime)!;
      final dn = analyzeScalp(
          ticker: tick('DNUSDT', dn5.last.close),
          m5: dn5, m15: dn15, book: book(dn5.last.close, bidWeight: 0.3), regime: regime)!;

      expect(up.mode, TradeMode.scalp);
      expect(up.score, greaterThan(dn.score));
      expect(dn.rating, Rating.avoid);
      expect(up.stop, lessThan(up.entry));
      expect(up.target, greaterThan(up.entry));
      expect(up.netRewardPct, closeTo(up.rewardPct - scalpFeePct, 1e-9));
      expect(up.charts.keys, containsAll(['5m', '15m']));
    });

    test('a very wide spread is penalised', () {
      final c5 = bars(200, 0.001);
      final c15 = bars(100, 0.002, minutes: 15);
      final tight = analyzeScalp(
          ticker: tick('AUSDT', c5.last.close),
          m5: c5, m15: c15, book: book(c5.last.close, spreadPct: 0.01), regime: regime)!;
      final wide = analyzeScalp(
          ticker: tick('AUSDT', c5.last.close),
          m5: c5, m15: c15, book: book(c5.last.close, spreadPct: 0.5), regime: regime)!;
      expect(wide.score, lessThan(tight.score));
      expect(wide.signals.any((s) => s.text.contains('eats the edge')), isTrue);
    });

    test('too little data returns null', () {
      final short = bars(20, 0.001);
      expect(
          analyzeScalp(
              ticker: tick('AUSDT', short.last.close),
              m5: short, m15: short, book: book(short.last.close), regime: regime),
          isNull);
    });
  });
}
