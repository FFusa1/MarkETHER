import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:market_ai/analyzer.dart';
import 'package:market_ai/indicators.dart';
import 'package:market_ai/models.dart';

/// Synthetic candles: compounding drift per bar plus a small wobble.
List<Candle> series(int n, double drift, {double start = 100, int hours = 24}) {
  final out = <Candle>[];
  var price = start;
  final t0 = DateTime(2025, 1, 1);
  for (var i = 0; i < n; i++) {
    final open = price;
    price = price * (1 + drift) * (1 + 0.004 * math.sin(i / 3));
    final close = price;
    out.add(Candle(
      openTime: t0.add(Duration(hours: hours * i)),
      open: open,
      high: math.max(open, close) * 1.01,
      low: math.min(open, close) * 0.99,
      close: close,
      volume: 1000 + i * (drift > 0 ? 10 : -2).toDouble(),
      quoteVolume: (1000 + i * 5) * close,
    ));
  }
  return out;
}

Ticker ticker(String symbol, double price) => Ticker(
      symbol: symbol,
      lastPrice: price,
      changePercent: 1,
      quoteVolume: 1e8,
      high: price,
      low: price,
      trades: 1000,
    );

void main() {
  group('indicators', () {
    test('EMA of a constant series is that constant', () {
      final e = ema(List.filled(50, 7.0), 20);
      expect(e.first, isNull);
      expect(e.last, closeTo(7, 1e-9));
    });

    test('RSI of a strictly rising series is 100', () {
      final r = rsi(List.generate(40, (i) => 10.0 + i));
      expect(r.last, 100);
    });

    test('RSI stays within 0..100', () {
      final closes = series(200, 0.001).map((c) => c.close).toList();
      for (final v in rsi(closes).whereType<double>()) {
        expect(v, inInclusiveRange(0, 100));
      }
    });

    test('ATR and ADX produce values with enough data', () {
      final c = series(120, 0.01);
      expect(lastOf(atr(c)), greaterThan(0));
      final a = adx(c);
      expect(a, isNotNull);
      expect(a!.plusDi, greaterThan(a.minusDi));
    });

    test('pctChange', () {
      expect(pctChange([100, 110], 1), closeTo(10, 1e-9));
    });
  });

  group('analyzer', () {
    final btc = series(250, 0.002, start: 60000);
    final regime = analyzeRegime(btc);

    test('BTC uptrend is detected as bullish', () {
      expect(regime.regime, Regime.bullish);
    });

    test('uptrending coin outscores a downtrending coin', () {
      final upD = series(250, 0.01);
      final upH = series(200, 0.002, hours: 4);
      final dnD = series(250, -0.008);
      final dnH = series(200, -0.002, hours: 4);
      final up = analyzeCoin(
          ticker: ticker('UPUSDT', upD.last.close),
          daily: upD, h4: upH, btcDaily: btc, regime: regime)!;
      final dn = analyzeCoin(
          ticker: ticker('DNUSDT', dnD.last.close),
          daily: dnD, h4: dnH, btcDaily: btc, regime: regime)!;
      expect(up.score, greaterThan(dn.score));
      expect(dn.rating, Rating.avoid);
      expect(up.score, inInclusiveRange(0, 100));
      expect(up.stop, lessThan(up.entry));
      expect(up.target, greaterThan(up.entry));
    });

    test('stablecoins pinned near \$1 are skipped', () {
      final peg = List.generate(250, (i) {
        final p = 1 + 0.002 * math.sin(i.toDouble());
        return Candle(
          openTime: DateTime(2025, 1, 1).add(Duration(days: i)),
          open: p,
          high: p * 1.001,
          low: p * 0.999,
          close: p,
          volume: 1e6,
          quoteVolume: 1e6,
        );
      });
      expect(isPegged(peg), isTrue);
      expect(
          analyzeCoin(
              ticker: ticker('USTABLEUSDT', peg.last.close),
              daily: peg, h4: peg, btcDaily: btc, regime: regime),
          isNull);
      expect(isPegged(series(250, 0.01)), isFalse);
    });

    test('a 24h spike is penalised and never rated Strong Buy', () {
      final d = series(250, 0.01);
      final h = series(200, 0.002, hours: 4);
      final calm = analyzeCoin(
          ticker: ticker('AUSDT', d.last.close),
          daily: d, h4: h, btcDaily: btc, regime: regime)!;
      final spiked = analyzeCoin(
          ticker: Ticker(
              symbol: 'AUSDT',
              lastPrice: d.last.close,
              changePercent: 30,
              quoteVolume: 1e8,
              high: d.last.close,
              low: d.last.close,
              trades: 1000),
          daily: d, h4: h, btcDaily: btc, regime: regime)!;
      expect(spiked.score, lessThan(calm.score));
      expect(spiked.rating, isNot(Rating.strongBuy));
      expect(spiked.signals.any((s) => s.category == 'Chase risk'), isTrue);
    });

    test('too little history returns null', () {
      final short = series(30, 0.01);
      expect(
          analyzeCoin(
              ticker: ticker('NEWUSDT', short.last.close),
              daily: short, h4: short, btcDaily: btc, regime: regime),
          isNull);
    });
  });
}
