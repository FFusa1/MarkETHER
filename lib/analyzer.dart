/// Rules-based scoring engine (swing horizon: 4h + 1d candles).
///
/// Score is the sum of six categories (max 100):
///   Trend 30 · Momentum 20 · Relative strength vs BTC 15 ·
///   Volume 15 · Structure 12 · Risk 8
/// then adjusted for the overall market regime (BTC trend).
library;

import 'dart:math' as math;

import 'indicators.dart';
import 'models.dart';

MarketRegime analyzeRegime(List<Candle> btcDaily) {
  final closes = btcDaily.map((c) => c.close).toList();
  final price = closes.isEmpty ? 0.0 : closes.last;
  final e20 = lastOf(ema(closes, 20));
  final e50 = lastOf(ema(closes, 50));
  final e200 = lastOf(ema(closes, 200));
  final ret30 = pctChange(closes, 30);

  if (e20 == null || e50 == null) {
    return MarketRegime(
        Regime.mixed, 'Not enough BTC history to judge the market.', price, ret30, '30d');
  }
  int bull = 0;
  if (price > e50) bull++;
  if (e20 > e50) bull++;
  if (e200 == null || price > e200) bull++;

  if (bull == 3) {
    return MarketRegime(Regime.bullish,
        'BTC is above its 50 & 200-day averages — market tailwind for altcoins.', price, ret30, '30d');
  }
  if (bull == 0 || (price < e50 && e20 < e50)) {
    return MarketRegime(Regime.bearish,
        'BTC is in a downtrend — most coins fall with it. Be selective and size small.', price, ret30, '30d');
  }
  return MarketRegime(Regime.mixed,
      'BTC trend is mixed — favour only the strongest setups.', price, ret30, '30d');
}

/// True for stablecoins and other pegged assets: price has stayed within ±3%
/// of $1 and moved less than 2% top-to-bottom over the last 30 days.
bool isPegged(List<Candle> daily) {
  if (daily.isEmpty) return false;
  final recent = daily.sublist(math.max(0, daily.length - 30));
  final hi = recent.map((c) => c.high).reduce(math.max);
  final lo = recent.map((c) => c.low).reduce(math.min);
  final last = recent.last.close;
  return last > 0.97 && last < 1.03 && lo > 0 && hi / lo < 1.02;
}

CoinAnalysis? analyzeCoin({
  required Ticker ticker,
  required List<Candle> daily,
  required List<Candle> h4,
  required List<Candle> btcDaily,
  required MarketRegime regime,
}) {
  if (daily.length < 60 || h4.length < 60) return null;

  final symbol = ticker.symbol;
  final base = symbol.endsWith('USDT') ? symbol.substring(0, symbol.length - 4) : symbol;
  final signals = <Signal>[];
  void add(String cat, String text, int pts, int max, [Impact? impact]) {
    final imp = impact ??
        (pts >= max * 0.6 ? Impact.positive : (pts <= max * 0.2 ? Impact.negative : Impact.neutral));
    signals.add(Signal(cat, text, imp, pts, max));
  }

  final dc = daily.map((c) => c.close).toList();
  final hc = h4.map((c) => c.close).toList();
  final close = dc.last;

  if (isPegged(daily)) return null;

  // ---------------- Trend (30) ----------------
  final e20d = lastOf(ema(dc, 20))!;
  final e50d = lastOf(ema(dc, 50))!;
  final e200d = lastOf(ema(dc, 200));
  final e20h = lastOf(ema(hc, 20))!;
  final e50h = lastOf(ema(hc, 50))!;

  if (close > e50d) {
    add('Trend', 'Price above the 50-day average', 8, 8);
  } else {
    add('Trend', 'Price below the 50-day average', 0, 8);
  }
  if (e20d > e50d) {
    add('Trend', '20-day average above 50-day (uptrend structure)', 7, 7);
  } else {
    add('Trend', '20-day average below 50-day (downtrend structure)', 0, 7);
  }
  if (e200d == null) {
    add('Trend', 'Less than 200 days of history — long-term trend unknown', 3, 7, Impact.neutral);
  } else if (close > e200d) {
    add('Trend', 'Above the 200-day average (long-term bull trend)', 7, 7);
  } else {
    add('Trend', 'Below the 200-day average (long-term bear trend)', 0, 7);
  }
  final h4Up = (hc.last > e50h ? 4 : 0) + (e20h > e50h ? 4 : 0);
  add(
      'Trend',
      h4Up == 8
          ? '4h chart trending up'
          : (h4Up == 0 ? '4h chart trending down' : '4h chart mixed'),
      h4Up,
      8);

  // ---------------- Momentum (20) ----------------
  final rsiD = lastOf(rsi(dc));
  if (rsiD != null) {
    final r = rsiD.toStringAsFixed(0);
    if (rsiD > 78) {
      add('Momentum', 'Daily RSI $r — overbought, high pullback risk', 0, 8);
    } else if (rsiD >= 68) {
      add('Momentum', 'Daily RSI $r — strong but getting stretched', 4, 8, Impact.neutral);
    } else if (rsiD >= 50) {
      add('Momentum', 'Daily RSI $r — healthy bullish momentum', 8, 8);
    } else if (rsiD >= 40) {
      add('Momentum', 'Daily RSI $r — neutral momentum', 3, 8, Impact.neutral);
    } else if (rsiD >= 30) {
      add('Momentum', 'Daily RSI $r — bearish momentum', 0, 8);
    } else {
      add('Momentum', 'Daily RSI $r — oversold (bounce possible, trend weak)', 2, 8, Impact.neutral);
    }
  }
  final m4 = macd(hc);
  final hist = lastOf(m4.hist);
  final histPrev = valueAgo(m4.hist, 1);
  if (hist != null) {
    if (hist > 0) {
      add('Momentum', '4h MACD histogram positive', 5, 5);
    } else {
      add('Momentum', '4h MACD histogram negative', 0, 5);
    }
    if (histPrev != null) {
      if (hist > histPrev) {
        add('Momentum', '4h momentum accelerating', 3, 3);
      } else {
        add('Momentum', '4h momentum fading', 0, 3);
      }
    }
  }
  final mD = macd(dc);
  final mdLine = lastOf(mD.line);
  final mdSig = lastOf(mD.signal);
  if (mdLine != null && mdSig != null) {
    if (mdLine > mdSig) {
      add('Momentum', 'Daily MACD above its signal line', 4, 4);
    } else {
      add('Momentum', 'Daily MACD below its signal line', 0, 4);
    }
  }

  // ---------------- Relative strength vs BTC (15) ----------------
  final ret30 = pctChange(dc, 30);
  final btcCloses = btcDaily.map((c) => c.close).toList();
  final btcRet30 = pctChange(btcCloses, 30);
  double? rel;
  if (base == 'BTC') {
    add('Rel. strength', 'Benchmark (BTC itself)', 7, 15, Impact.neutral);
  } else {
    rel = ret30 - btcRet30;
    final rs = '${rel >= 0 ? '+' : ''}${rel.toStringAsFixed(1)}%';
    final pts = rel >= 20
        ? 15
        : rel >= 10
            ? 12
            : rel >= 3
                ? 9
                : rel >= -3
                    ? 6
                    : rel >= -10
                        ? 3
                        : 0;
    add('Rel. strength', '30-day performance vs BTC: $rs', pts, 15);
  }

  // ---------------- Volume (15) ----------------
  double? volRatio;
  if (h4.length >= 25) {
    final recent = h4.sublist(h4.length - 3);
    final prior = h4.sublist(h4.length - 23, h4.length - 3);
    final recentAvg = recent.fold<double>(0, (a, c) => a + c.quoteVolume) / recent.length;
    final priorAvg = prior.fold<double>(0, (a, c) => a + c.quoteVolume) / prior.length;
    volRatio = priorAvg > 0 ? recentAvg / priorAvg : null;
    final priceUp = hc.last > hc[hc.length - 4];
    if (volRatio != null) {
      final vr = '${volRatio.toStringAsFixed(1)}x';
      if (volRatio >= 1.8 && priceUp) {
        add('Volume', 'Volume surge ($vr) on rising price — buyers stepping in', 8, 8);
      } else if (volRatio >= 1.8) {
        add('Volume', 'Heavy volume ($vr) on falling price — selling pressure', 0, 8);
      } else if (volRatio >= 1.2) {
        add('Volume', 'Above-average volume ($vr)', priceUp ? 5 : 2, 8, Impact.neutral);
      } else {
        add('Volume', 'Normal / low volume ($vr)', 2, 8, Impact.neutral);
      }
    }
  }
  final ob = obv(daily);
  if (ob.length > 21) {
    if (ob.last > ob[ob.length - 21]) {
      add('Volume', 'On-balance volume rising over 20 days (accumulation)', 7, 7);
    } else {
      add('Volume', 'On-balance volume falling over 20 days (distribution)', 0, 7);
    }
  }

  // ---------------- Structure (12) ----------------
  final adxR = adx(daily);
  if (adxR != null) {
    final a = adxR.adx.toStringAsFixed(0);
    if (adxR.adx >= 25 && adxR.plusDi > adxR.minusDi) {
      add('Structure', 'Strong uptrend (ADX $a)', 6, 6);
    } else if (adxR.adx >= 25) {
      add('Structure', 'Strong downtrend (ADX $a)', 0, 6);
    } else if (adxR.adx < 20) {
      add('Structure', 'No clear trend / ranging (ADX $a)', 2, 6, Impact.neutral);
    } else {
      add('Structure', 'Trend developing (ADX $a)', 3, 6, Impact.neutral);
    }
  }
  final last20 = daily.sublist(daily.length - 20);
  final high20 = last20.map((c) => c.high).reduce(math.max);
  final distHigh = (high20 - close) / close * 100;
  if (close >= high20 * 0.98) {
    add('Structure', 'At / near 20-day high — breakout zone', 6, 6);
  } else if (distHigh <= 10) {
    add('Structure', '${distHigh.toStringAsFixed(1)}% below 20-day high', 3, 6, Impact.neutral);
  } else {
    add('Structure', '${distHigh.toStringAsFixed(1)}% below 20-day high — weak structure', 0, 6);
  }

  // ---------------- Risk (8) ----------------
  final atrD = lastOf(atr(daily));
  double? atrPct;
  if (atrD != null && close > 0) {
    atrPct = atrD / close * 100;
    final ap = '${atrPct.toStringAsFixed(1)}%';
    if (atrPct > 10) {
      add('Risk', 'Extreme volatility (daily ATR $ap)', 0, 8);
    } else if (atrPct > 6) {
      add('Risk', 'High volatility (daily ATR $ap)', 4, 8, Impact.neutral);
    } else if (atrPct >= 2) {
      add('Risk', 'Healthy volatility (daily ATR $ap)', 8, 8);
    } else {
      add('Risk', 'Low volatility (daily ATR $ap)', 5, 8, Impact.neutral);
    }
  }

  // ---------------- Trade levels ----------------
  final a = atrD ?? close * 0.04;
  final swingLow = daily.sublist(daily.length - 10).map((c) => c.low).reduce(math.min);
  // Stop: below recent swing low, but no wider than 2.5 ATR and no tighter than 1 ATR.
  var stop = math.max(swingLow * 0.99, close - 2.5 * a);
  if (close - stop < a) stop = close - a;
  stop = math.max(stop, 0.0);
  final high60 = daily.sublist(math.max(0, daily.length - 60)).map((c) => c.high).reduce(math.max);
  final target = high60 > close + 1.5 * a ? high60 : close + 3 * a;
  final stopPct = (close - stop) / close * 100;
  final rr = close - stop > 0 ? (target - close) / (close - stop) : 0.0;

  // ---------------- Penalties ----------------
  var score = signals.fold<int>(0, (a, s) => a + s.points);
  void penalty(String cat, String text, int pts, [Impact impact = Impact.negative]) {
    score -= pts;
    signals.add(Signal(cat, text, impact, -pts, 0));
  }

  // Chasing a spike: buying right after a huge daily candle usually means
  // buying the top of the move.
  final change24h = ticker.changePercent;
  final chg = '+${change24h.toStringAsFixed(1)}% in 24h';
  if (change24h >= 25) {
    penalty('Chase risk', 'Parabolic spike ($chg) — wait for a pullback', 14);
  } else if (change24h >= 15) {
    penalty('Chase risk', 'Big spike ($chg) — high pullback risk', 8);
  } else if (change24h >= 10) {
    penalty('Chase risk', 'Sharp move ($chg)', 3, Impact.neutral);
  }

  final sp = '${stopPct.toStringAsFixed(1)}% away';
  if (stopPct > 15) {
    penalty('Trade risk', 'Stop-loss $sp — too wide for a safe position', 8);
  } else if (stopPct > 10) {
    penalty('Trade risk', 'Stop-loss $sp — use a small position', 3, Impact.neutral);
  }

  final rrText = 'Risk/reward 1:${rr.toStringAsFixed(2)}';
  if (rr < 1) {
    penalty('Trade risk', '$rrText — reward smaller than risk', 10);
  } else if (rr < 1.5) {
    penalty('Trade risk', '$rrText — below the 1:1.5 minimum', 5);
  }

  // ---------------- Market regime ----------------
  if (base != 'BTC') {
    if (regime.regime == Regime.bearish) {
      penalty('Market', 'BTC downtrend — market-risk penalty', 10);
    } else if (regime.regime == Regime.mixed) {
      penalty('Market', 'Mixed BTC trend — market-risk penalty', 4, Impact.neutral);
    }
  }
  score = math.min(100, math.max(0, score));

  var rating = score >= 72
      ? Rating.strongBuy
      : score >= 58
          ? Rating.buy
          : score >= 42
              ? Rating.neutral
              : Rating.avoid;
  // Hard caps: a Strong Buy must not be overbought, chased, or a poor trade.
  if (rating == Rating.strongBuy &&
      ((rsiD != null && rsiD > 80) || change24h >= 15 || rr < 1.5 || stopPct > 15)) {
    rating = Rating.buy;
  }
  // A trade where the reward is smaller than the risk is never a buy.
  if ((rating == Rating.buy || rating == Rating.strongBuy) && rr < 1) {
    rating = Rating.neutral;
  }

  String f0(double? v) => v == null ? '—' : v.toStringAsFixed(0);
  return CoinAnalysis(
    mode: TradeMode.swing,
    symbol: symbol,
    base: base,
    ticker: ticker,
    score: score,
    rating: rating,
    signals: signals,
    charts: {'1D': daily, '4H': h4},
    stats: [
      Stat('RSI (1D)', f0(rsiD)),
      Stat('ADX (1D)', f0(adxR?.adx)),
      Stat('ATR % (1D)', atrPct == null ? '—' : '${atrPct.toStringAsFixed(1)}%'),
      Stat('30d return', '${ret30 >= 0 ? '+' : ''}${ret30.toStringAsFixed(1)}%'),
      Stat('vs BTC 30d', rel == null ? '—' : '${rel >= 0 ? '+' : ''}${rel.toStringAsFixed(1)}%'),
      Stat('Volume (4H)', volRatio == null ? '—' : '${volRatio.toStringAsFixed(1)}x'),
      Stat('MACD (4H)', hist == null ? '—' : (hist >= 0 ? 'Positive' : 'Negative')),
    ],
    entry: close,
    stop: stop,
    target: target,
  );
}
