/// Scalp engine: in-and-out trades lasting minutes, long only.
///
/// Uses 5-minute and 15-minute candles plus the live order book.
/// Score categories (max 100):
///   15m trend 20 · 5m trend & VWAP 20 · Momentum 20 ·
///   Volume burst 15 · Order book 15 · Spread / cost 10
/// minus penalties for dead or wild volatility, chasing, targets that
/// fees would eat, and a falling BTC.
library;

import 'dart:math' as math;

import 'indicators.dart';
import 'models.dart';

/// Binance spot taker fee (0.1%) paid on both the buy and the sell.
const scalpFeePct = 0.2;

MarketRegime analyzeScalpRegime(List<Candle> btc15m) {
  final closes = btc15m.map((c) => c.close).toList();
  final price = closes.isEmpty ? 0.0 : closes.last;
  final ret4h = pctChange(closes, 16);
  final e9 = lastOf(ema(closes, 9));
  final e21 = lastOf(ema(closes, 21));
  if (e9 == null || e21 == null) {
    return MarketRegime(Regime.mixed, 'Not enough BTC data.', price, ret4h, '4h');
  }
  if (price > e21 && e9 > e21) {
    return MarketRegime(Regime.bullish,
        'BTC is rising on the 15-minute chart — tailwind for quick longs.', price, ret4h, '4h');
  }
  if (price < e21 && e9 < e21) {
    return MarketRegime(Regime.bearish,
        'BTC is falling on the 15-minute chart — most long scalps fail now. Wait or size very small.',
        price, ret4h, '4h');
  }
  return MarketRegime(Regime.mixed,
      'BTC is choppy short-term — take only the cleanest setups.', price, ret4h, '4h');
}

CoinAnalysis? analyzeScalp({
  required Ticker ticker,
  required List<Candle> m5,
  required List<Candle> m15,
  required OrderBook book,
  required MarketRegime regime,
}) {
  if (m5.length < 60 || m15.length < 30 || book.bestAsk <= 0 || book.bestBid <= 0) return null;

  final symbol = ticker.symbol;
  final base = symbol.endsWith('USDT') ? symbol.substring(0, symbol.length - 4) : symbol;
  final signals = <Signal>[];
  void add(String cat, String text, int pts, int max, [Impact? impact]) {
    final imp = impact ??
        (pts >= max * 0.6 ? Impact.positive : (pts <= max * 0.2 ? Impact.negative : Impact.neutral));
    signals.add(Signal(cat, text, imp, pts, max));
  }

  String pct(double v, [int d = 2]) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(d)}%';

  final c5 = m5.map((c) => c.close).toList();
  final c15 = m15.map((c) => c.close).toList();
  final price = c5.last;

  // ---------------- 15m trend (20) ----------------
  final e9_15 = lastOf(ema(c15, 9))!;
  final e21_15 = lastOf(ema(c15, 21))!;
  if (price > e21_15) {
    add('15m trend', 'Price above 15m EMA21', 10, 10);
  } else {
    add('15m trend', 'Price below 15m EMA21', 0, 10);
  }
  if (e9_15 > e21_15) {
    add('15m trend', '15m EMA9 above EMA21 (short-term uptrend)', 10, 10);
  } else {
    add('15m trend', '15m EMA9 below EMA21 (short-term downtrend)', 0, 10);
  }

  // ---------------- 5m trend & VWAP (20) ----------------
  final vw = lastOf(vwap(m5, 96)); // 8 hours of 5m candles
  final vwDist = vw == null || vw == 0 ? 0.0 : (price / vw - 1) * 100;
  if (vw != null) {
    if (price > vw) {
      add('5m trend', 'Above 8h VWAP (${pct(vwDist)}) — buyers in control', 8, 8);
    } else {
      add('5m trend', 'Below 8h VWAP (${pct(vwDist)}) — sellers in control', 0, 8);
    }
  }
  final e9_5 = lastOf(ema(c5, 9))!;
  final e21_5 = lastOf(ema(c5, 21))!;
  if (e9_5 > e21_5) {
    add('5m trend', '5m EMA9 above EMA21', 7, 7);
  } else {
    add('5m trend', '5m EMA9 below EMA21', 0, 7);
  }
  if (price > e9_5) {
    add('5m trend', 'Holding above 5m EMA9', 5, 5);
  } else {
    add('5m trend', 'Lost the 5m EMA9', 0, 5);
  }

  // ---------------- Momentum (20) ----------------
  final r7 = lastOf(rsi(c5, 7));
  if (r7 != null) {
    final r = r7.toStringAsFixed(0);
    if (r7 > 80) {
      add('Momentum', '5m RSI(7) $r — overbought, likely to snap back', 0, 10);
    } else if (r7 >= 70) {
      add('Momentum', '5m RSI(7) $r — hot, late entry', 5, 10, Impact.neutral);
    } else if (r7 >= 50) {
      add('Momentum', '5m RSI(7) $r — bullish momentum', 10, 10);
    } else if (r7 >= 30) {
      add('Momentum', '5m RSI(7) $r — weak momentum', 0, 10);
    } else {
      add('Momentum', '5m RSI(7) $r — oversold, bounce possible but against the move', 3, 10,
          Impact.neutral);
    }
  }
  final m = macd(c5);
  final hist = lastOf(m.hist);
  final histPrev = valueAgo(m.hist, 1);
  if (hist != null) {
    if (hist > 0) {
      add('Momentum', '5m MACD histogram positive', 5, 5);
    } else {
      add('Momentum', '5m MACD histogram negative', 0, 5);
    }
    if (histPrev != null) {
      if (hist > histPrev) {
        add('Momentum', '5m momentum accelerating', 5, 5);
      } else {
        add('Momentum', '5m momentum fading', 0, 5);
      }
    }
  }

  // ---------------- Volume burst (15) ----------------
  final recent = m5.sublist(m5.length - 3);
  final prior = m5.sublist(m5.length - 23, m5.length - 3);
  final recentAvg = recent.fold<double>(0, (a, c) => a + c.quoteVolume) / recent.length;
  final priorAvg = prior.fold<double>(0, (a, c) => a + c.quoteVolume) / prior.length;
  final volRatio = priorAvg > 0 ? recentAvg / priorAvg : 1.0;
  final priceUp = c5.last > c5[c5.length - 4];
  final vr = '${volRatio.toStringAsFixed(1)}x';
  if (volRatio >= 2 && priceUp) {
    add('Volume', 'Volume burst ($vr) on rising price', 15, 15);
  } else if (volRatio >= 2) {
    add('Volume', 'Selling burst ($vr) — price dropping on heavy volume', 0, 15);
  } else if (volRatio >= 1.3 && priceUp) {
    add('Volume', 'Rising volume ($vr) with price', 10, 15);
  } else {
    add('Volume', 'No volume burst ($vr)', 4, 15, Impact.neutral);
  }

  // ---------------- Order book (15) ----------------
  final imb = book.imbalance(0.5);
  final bidShare = '${(imb * 100).toStringAsFixed(0)}% bids';
  if (imb >= 0.62) {
    add('Order book', 'Buyers stacked near price ($bidShare within 0.5%)', 15, 15);
  } else if (imb >= 0.53) {
    add('Order book', 'More buyers than sellers near price ($bidShare)', 10, 15);
  } else if (imb >= 0.45) {
    add('Order book', 'Balanced order book ($bidShare)', 5, 15, Impact.neutral);
  } else {
    add('Order book', 'Sellers stacked near price ($bidShare)', 0, 15);
  }

  // ---------------- Spread / cost (10) ----------------
  final spread = book.spreadPct;
  final sp = '${spread.toStringAsFixed(3)}%';
  if (spread <= 0.02) {
    add('Cost', 'Tight spread ($sp)', 10, 10);
  } else if (spread <= 0.05) {
    add('Cost', 'Acceptable spread ($sp)', 7, 10);
  } else if (spread <= 0.1) {
    add('Cost', 'Wide-ish spread ($sp)', 3, 10, Impact.neutral);
  } else {
    add('Cost', 'Wide spread ($sp) — costly to scalp', 0, 10);
  }

  // ---------------- Trade levels ----------------
  final atr5 = lastOf(atr(m5)) ?? price * 0.004;
  final atrPct = atr5 / price * 100;
  final entry = book.bestAsk; // a market buy fills at the ask
  final stopDist = math.max(1.2 * atr5, entry * 0.0025);
  final stop = entry - stopDist;
  final target = entry + 2 * stopDist;
  final netTarget = (target - entry) / entry * 100 - scalpFeePct;

  // ---------------- Penalties ----------------
  var score = signals.fold<int>(0, (a, s) => a + s.points);
  void penalty(String cat, String text, int pts, [Impact impact = Impact.negative]) {
    score -= pts;
    signals.add(Signal(cat, text, impact, -pts, 0));
  }

  final ap = '${atrPct.toStringAsFixed(2)}%';
  if (atrPct < 0.15) {
    penalty('Volatility', 'Too quiet (5m ATR $ap) — moves too small to beat fees', 10);
  } else if (atrPct > 2) {
    penalty('Volatility', 'Whipsaw risk (5m ATR $ap)', 8);
  }

  final chg1h = pctChange(c5, 12);
  if (chg1h >= 8) {
    penalty('Chase risk', 'Already ${pct(chg1h, 1)} in the last hour — chasing', 10);
  } else if (chg1h >= 4) {
    penalty('Chase risk', 'Up ${pct(chg1h, 1)} in the last hour', 4, Impact.neutral);
  }

  if (netTarget < 0.3) {
    penalty('Fees', 'Target only ${pct(netTarget)} after fees', 10);
  }
  if (spread > 0.15) {
    penalty('Fees', 'Spread $sp eats the edge', 10);
  }

  if (base != 'BTC') {
    if (regime.regime == Regime.bearish) {
      penalty('Market', 'BTC falling on 15m', 8);
    } else if (regime.regime == Regime.mixed) {
      penalty('Market', 'BTC choppy on 15m', 3, Impact.neutral);
    }
  }
  score = math.min(100, math.max(0, score));

  var rating = score >= 70
      ? Rating.strongBuy
      : score >= 56
          ? Rating.buy
          : score >= 42
              ? Rating.neutral
              : Rating.avoid;
  final netRR = netTarget / (stopDist / entry * 100 + scalpFeePct);
  if (rating == Rating.strongBuy && ((r7 != null && r7 > 80) || chg1h >= 8 || spread > 0.1)) {
    rating = Rating.buy;
  }
  if ((rating == Rating.buy || rating == Rating.strongBuy) && netRR < 1) {
    rating = Rating.neutral;
  }

  return CoinAnalysis(
    mode: TradeMode.scalp,
    symbol: symbol,
    base: base,
    ticker: ticker,
    score: score,
    rating: rating,
    signals: signals,
    charts: {'5m': m5, '15m': m15},
    stats: [
      Stat('RSI(7) 5m', r7 == null ? '—' : r7.toStringAsFixed(0)),
      Stat('vs VWAP', vw == null ? '—' : pct(vwDist)),
      Stat('Spread', sp),
      Stat('Book bids', '${(imb * 100).toStringAsFixed(0)}%'),
      Stat('ATR 5m', ap),
      Stat('Volume 5m', vr),
      Stat('1h change', pct(chg1h, 1)),
    ],
    entry: entry,
    stop: stop,
    target: target,
    feePct: scalpFeePct,
  );
}
