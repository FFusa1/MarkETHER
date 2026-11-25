/// Technical indicators. Every series function returns a list the same length
/// as its input, with `null` where there is not yet enough data.
library;

import 'dart:math' as math;

import 'models.dart';

double? lastOf(List<double?> v) => v.isEmpty ? null : v.last;

double? valueAgo(List<double?> v, int barsAgo) {
  final i = v.length - 1 - barsAgo;
  return i >= 0 ? v[i] : null;
}

List<double?> sma(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  double sum = 0;
  for (var i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= period) sum -= values[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

List<double?> ema(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (values.length < period) return out;
  double sum = 0;
  for (var i = 0; i < period; i++) {
    sum += values[i];
  }
  double prev = sum / period;
  out[period - 1] = prev;
  final k = 2 / (period + 1);
  for (var i = period; i < values.length; i++) {
    prev = values[i] * k + prev * (1 - k);
    out[i] = prev;
  }
  return out;
}

/// EMA over a series that starts with nulls.
List<double?> _emaNullable(List<double?> values, int period) {
  final out = List<double?>.filled(values.length, null);
  final start = values.indexWhere((v) => v != null);
  if (start < 0) return out;
  final compact = values.sublist(start).map((v) => v ?? 0).toList();
  final e = ema(compact, period);
  for (var i = 0; i < e.length; i++) {
    out[start + i] = e[i];
  }
  return out;
}

List<double?> rsi(List<double> closes, [int period = 14]) {
  final out = List<double?>.filled(closes.length, null);
  if (closes.length <= period) return out;
  double gain = 0, loss = 0;
  for (var i = 1; i <= period; i++) {
    final d = closes[i] - closes[i - 1];
    if (d >= 0) {
      gain += d;
    } else {
      loss -= d;
    }
  }
  gain /= period;
  loss /= period;
  out[period] = _rsiValue(gain, loss);
  for (var i = period + 1; i < closes.length; i++) {
    final d = closes[i] - closes[i - 1];
    final g = d > 0 ? d : 0.0;
    final l = d < 0 ? -d : 0.0;
    gain = (gain * (period - 1) + g) / period;
    loss = (loss * (period - 1) + l) / period;
    out[i] = _rsiValue(gain, loss);
  }
  return out;
}

double _rsiValue(double gain, double loss) {
  if (loss == 0) return gain == 0 ? 50 : 100;
  return 100 - 100 / (1 + gain / loss);
}

typedef Macd = ({List<double?> line, List<double?> signal, List<double?> hist});

Macd macd(List<double> closes, {int fast = 12, int slow = 26, int signal = 9}) {
  final f = ema(closes, fast);
  final s = ema(closes, slow);
  final line = List<double?>.generate(
      closes.length, (i) => (f[i] != null && s[i] != null) ? f[i]! - s[i]! : null);
  final sig = _emaNullable(line, signal);
  final hist = List<double?>.generate(
      closes.length, (i) => (line[i] != null && sig[i] != null) ? line[i]! - sig[i]! : null);
  return (line: line, signal: sig, hist: hist);
}

List<double> trueRange(List<Candle> c) {
  final tr = List<double>.filled(c.length, 0);
  for (var i = 0; i < c.length; i++) {
    if (i == 0) {
      tr[i] = c[i].high - c[i].low;
    } else {
      final pc = c[i - 1].close;
      tr[i] = math.max(c[i].high - c[i].low,
          math.max((c[i].high - pc).abs(), (c[i].low - pc).abs()));
    }
  }
  return tr;
}

List<double?> atr(List<Candle> c, [int period = 14]) {
  final out = List<double?>.filled(c.length, null);
  if (c.length <= period) return out;
  final tr = trueRange(c);
  double a = 0;
  for (var i = 1; i <= period; i++) {
    a += tr[i];
  }
  a /= period;
  out[period] = a;
  for (var i = period + 1; i < c.length; i++) {
    a = (a * (period - 1) + tr[i]) / period;
    out[i] = a;
  }
  return out;
}

typedef AdxResult = ({double adx, double plusDi, double minusDi});

/// Wilder's ADX with +DI / -DI, latest values only.
AdxResult? adx(List<Candle> c, [int p = 14]) {
  final n = c.length;
  if (n < 2 * p + 1) return null;
  final tr = trueRange(c);
  final pdm = List<double>.filled(n, 0);
  final mdm = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    final up = c[i].high - c[i - 1].high;
    final down = c[i - 1].low - c[i].low;
    pdm[i] = (up > down && up > 0) ? up : 0;
    mdm[i] = (down > up && down > 0) ? down : 0;
  }
  double sTr = 0, sP = 0, sM = 0;
  for (var i = 1; i <= p; i++) {
    sTr += tr[i];
    sP += pdm[i];
    sM += mdm[i];
  }
  final dx = <double>[];
  double pdi = 0, mdi = 0;
  for (var i = p; i < n; i++) {
    if (i > p) {
      sTr = sTr - sTr / p + tr[i];
      sP = sP - sP / p + pdm[i];
      sM = sM - sM / p + mdm[i];
    }
    if (sTr == 0) {
      dx.add(0);
      continue;
    }
    pdi = 100 * sP / sTr;
    mdi = 100 * sM / sTr;
    final sum = pdi + mdi;
    dx.add(sum == 0 ? 0 : 100 * (pdi - mdi).abs() / sum);
  }
  if (dx.length < p) return null;
  double a = 0;
  for (var i = 0; i < p; i++) {
    a += dx[i];
  }
  a /= p;
  for (var i = p; i < dx.length; i++) {
    a = (a * (p - 1) + dx[i]) / p;
  }
  return (adx: a, plusDi: pdi, minusDi: mdi);
}

List<double> obv(List<Candle> c) {
  final out = List<double>.filled(c.length, 0);
  for (var i = 1; i < c.length; i++) {
    final d = c[i].close - c[i - 1].close;
    out[i] = out[i - 1] + (d > 0 ? c[i].volume : (d < 0 ? -c[i].volume : 0));
  }
  return out;
}

/// Rolling volume-weighted average price over the last [period] candles,
/// using the typical price (high + low + close) / 3.
List<double?> vwap(List<Candle> c, int period) {
  final out = List<double?>.filled(c.length, null);
  double pv = 0, vol = 0;
  for (var i = 0; i < c.length; i++) {
    final tp = (c[i].high + c[i].low + c[i].close) / 3;
    pv += tp * c[i].volume;
    vol += c[i].volume;
    if (i >= period) {
      final o = c[i - period];
      pv -= (o.high + o.low + o.close) / 3 * o.volume;
      vol -= o.volume;
    }
    if (i >= period - 1) out[i] = vol > 0 ? pv / vol : c[i].close;
  }
  return out;
}

/// Percent change of the last value versus `bars` bars earlier.
double pctChange(List<double> v, int bars) {
  if (v.length <= bars) return v.isEmpty ? 0 : (v.last / v.first - 1) * 100;
  final prev = v[v.length - 1 - bars];
  if (prev == 0) return 0;
  return (v.last / prev - 1) * 100;
}
