/// Classic chart patterns (cup and handle, double bottom, flags, ...) and
/// candle patterns (hammer, engulfing, ...), detected on recent candles.
///
/// Detection only says "this shape is here now". Whether a pattern actually
/// makes money is learned by the bot from its own trades.
library;

import 'dart:math' as math;

import 'models.dart';

class ChartPattern {
  final String name;
  final bool bullish;

  /// true = single/few-candle pattern, false = multi-candle chart pattern.
  final bool candle;
  final String note;

  const ChartPattern(this.name, {required this.bullish, required this.candle, required this.note});
}

/// Chart patterns on [chart] (e.g. 15m) and candle patterns on [candles]
/// (e.g. 5m). Labels are added to the names, e.g. "Cup and handle (15m)".
List<ChartPattern> detectPatterns({
  required List<Candle> chart,
  required String chartLabel,
  required List<Candle> candles,
  required String candleLabel,
}) {
  final out = <ChartPattern>[];
  ChartPattern? tag(ChartPattern? p, String label) => p == null
      ? null
      : ChartPattern('${p.name} ($label)', bullish: p.bullish, candle: p.candle, note: p.note);
  for (final f in [
    cupAndHandle,
    inverseHeadAndShoulders,
    doubleBottom,
    bullFlag,
    ascendingTriangle,
    rangeBreakout,
    doubleTop,
    rangeBreakdown,
  ]) {
    final p = tag(f(chart), chartLabel);
    if (p != null) out.add(p);
  }
  for (final f in [hammer, bullishEngulfing, threeWhiteSoldiers, shootingStar, bearishEngulfing]) {
    final p = tag(f(candles), candleLabel);
    if (p != null) out.add(p);
  }
  return out;
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

String _p(double v) => '${v.toStringAsFixed(1)}%';

/// Average candle range in % of price over the last [n] candles: scales the
/// size rules so the same detector works on 5m, 15m or 4h charts.
double _avgRangePct(List<Candle> c, [int n = 30]) {
  final s = c.sublist(math.max(0, c.length - n));
  if (s.isEmpty) return 0;
  return s.fold<double>(0, (a, k) => a + (k.close > 0 ? (k.high - k.low) / k.close * 100 : 0)) /
      s.length;
}

int _argMaxHigh(List<Candle> c, int from, int to) {
  var best = from;
  for (var i = from; i < to; i++) {
    if (c[i].high > c[best].high) best = i;
  }
  return best;
}

int _argMinLow(List<Candle> c, int from, int to) {
  var best = from;
  for (var i = from; i < to; i++) {
    if (c[i].low < c[best].low) best = i;
  }
  return best;
}

double _maxHigh(List<Candle> c, int from, int to) =>
    c.sublist(from, to).fold<double>(double.negativeInfinity, (a, k) => math.max(a, k.high));

double _minLow(List<Candle> c, int from, int to) =>
    c.sublist(from, to).fold<double>(double.infinity, (a, k) => math.min(a, k.low));

List<int> _pivotLows(List<Candle> c, int from, [int w = 2]) => [
      for (var i = math.max(from, w); i < c.length - w; i++)
        if (List.generate(2 * w + 1, (j) => i - w + j)
            .every((j) => j == i || c[j].low >= c[i].low))
          i
    ];

List<int> _pivotHighs(List<Candle> c, int from, [int w = 2]) => [
      for (var i = math.max(from, w); i < c.length - w; i++)
        if (List.generate(2 * w + 1, (j) => i - w + j)
            .every((j) => j == i || c[j].high <= c[i].high))
          i
    ];

// ---------------------------------------------------------------------------
// bullish chart patterns
// ---------------------------------------------------------------------------

/// Rounded dip between two similar highs (the cup), a small shallow pullback
/// (the handle), and price back near or above the rim.
ChartPattern? cupAndHandle(List<Candle> c) {
  final n = c.length;
  if (n < 30) return null;
  final start = math.max(0, n - 80);
  final r = _argMaxHigh(c, n - 18, n - 2); // right rim; handle = r+1 .. n-1
  if (r - start < 16) return null;
  final l = _argMaxHigh(c, start, r - 10); // left rim
  final b = _argMinLow(c, l + 1, r); // cup bottom
  final hl = c[l].high, hr = c[r].high, low = c[b].low;
  final rim = math.min(hl, hr);
  final depthAbs = rim - low;
  if (depthAbs <= 0) return null;
  final depth = depthAbs / rim * 100;
  final unit = _avgRangePct(c);
  if (depth < math.max(1.0, 3 * unit) || depth > 25 * unit) return null;
  if ((hl - hr).abs() > 0.25 * depthAbs) return null; // rims at a similar level
  if (_maxHigh(c, l + 1, r) > math.max(hl, hr)) return null; // nothing pokes above the rims
  if (b - l < 4 || r - b < 4) return null;
  final pos = (b - l) / (r - l);
  if (pos < 0.2 || pos > 0.8) return null; // bottom roughly in the middle
  // Rounded "U", not a sharp "V": several candles spend time near the bottom.
  final nearBottom = [for (var i = l + 1; i < r; i++) c[i]]
      .where((k) => k.low <= low + 0.25 * depthAbs)
      .length;
  if (nearBottom < math.max(3, (r - l) ~/ 6)) return null;
  final handleLow = _minLow(c, r + 1, n);
  final drop = (hr - handleLow) / (hr - low);
  if (drop < 0.05 || drop > 0.5) return null; // handle: shallow pullback in the top half
  final close = c.last.close;
  if (close < hr - 0.4 * (hr - handleLow) || close > hr * 1.02) return null;
  return ChartPattern('Cup and handle',
      bullish: true,
      candle: false,
      note: 'Cup ${_p(depth)} deep, price ${close > hr ? 'breaking out above' : 'just under'} the rim');
}

/// Two lows at about the same level with a peak between; price back up near
/// that peak (the neckline).
ChartPattern? doubleBottom(List<Candle> c) {
  final n = c.length;
  if (n < 25) return null;
  final piv = _pivotLows(c, math.max(0, n - 60));
  final unit = _avgRangePct(c);
  for (final p2 in piv.reversed) {
    if (n - 1 - p2 > 15) break;
    for (final p1 in piv.reversed.where((i) => i <= p2 - 6)) {
      final a = c[p1].low, b = c[p2].low, low = math.min(a, b);
      final neck = _maxHigh(c, p1, p2 + 1);
      final h = neck - low;
      if (h <= 0 || h / neck * 100 < math.max(1.0, 3 * unit)) continue;
      if ((a - b).abs() > 0.2 * h) continue;
      if (_minLow(c, p1, n) < low - 0.05 * h) continue; // no lower low since
      if (p1 < 5 || _maxHigh(c, math.max(0, p1 - 15), p1) < neck) continue; // came from above
      final close = c.last.close;
      if (close < neck - 0.3 * h || close > neck + 0.5 * h) continue;
      return ChartPattern('Double bottom',
          bullish: true,
          candle: false,
          note: 'Two lows ${p2 - p1} candles apart, price ${close > neck ? 'above' : 'near'} the neckline');
    }
  }
  return null;
}

/// Three lows, the middle one deepest (head), shoulders similar; price back
/// near the neckline.
ChartPattern? inverseHeadAndShoulders(List<Candle> c) {
  final n = c.length;
  if (n < 30) return null;
  final piv = _pivotLows(c, math.max(0, n - 80));
  final unit = _avgRangePct(c);
  for (var k = piv.length - 1; k >= 2; k--) {
    final s2 = piv[k], hd = piv[k - 1], s1 = piv[k - 2];
    if (n - 1 - s2 > 15) break;
    if (hd - s1 < 3 || s2 - hd < 3) continue;
    final ls = c[s1].low, head = c[hd].low, rs = c[s2].low;
    final neck = math.max(_maxHigh(c, s1, hd), _maxHigh(c, hd, s2 + 1));
    final depth = neck - head;
    if (depth <= 0 || depth / neck * 100 < math.max(1.0, 3 * unit)) continue;
    final shoulder = math.max(ls, rs);
    if (shoulder - head < 0.25 * depth) continue; // head clearly lower
    if ((ls - rs).abs() > 0.3 * (neck - head)) continue; // shoulders alike
    if (_minLow(c, s2, n) < rs - 0.1 * depth) continue;
    final close = c.last.close;
    if (close < neck - 0.3 * depth || close > neck + 0.5 * depth) continue;
    return ChartPattern('Inverse head and shoulders',
        bullish: true,
        candle: false,
        note: 'Head ${_p(depth / neck * 100)} below the neckline, price '
            '${close > neck ? 'above' : 'near'} it');
  }
  return null;
}

/// Sharp rise (the pole), then a tight sideways/down drift that gives back
/// at most half of it (the flag); price near the top of the flag.
ChartPattern? bullFlag(List<Candle> c) {
  final n = c.length;
  if (n < 25) return null;
  final unit = _avgRangePct(c);
  final top = _argMaxHigh(c, n - 14, n - 3); // pole top; flag = top+1 .. n-1
  final s = _argMinLow(c, math.max(0, top - 8), top); // pole start
  if (top - s < 2) return null;
  final poleAbs = c[top].high - c[s].low;
  final pole = poleAbs / c[s].low * 100;
  if (pole < math.max(1.5, 4 * unit)) return null;
  final flagLow = _minLow(c, top + 1, n);
  final retrace = (c[top].high - flagLow) / poleAbs;
  if (retrace < 0.1 || retrace > 0.5) return null;
  final flagHigh = _maxHigh(c, top + 1, n - 1);
  if (flagHigh > c[top].high) return null;
  final close = c.last.close;
  if (close < flagLow + 0.6 * (c[top].high - flagLow)) return null;
  return ChartPattern('Bull flag',
      bullish: true,
      candle: false,
      note: 'Pole +${_p(pole)}, flag gave back ${(retrace * 100).toStringAsFixed(0)}%');
}

/// Flat resistance tested at least twice while the lows keep rising.
ChartPattern? ascendingTriangle(List<Candle> c) {
  final n = c.length;
  if (n < 25) return null;
  final from = math.max(0, n - 40);
  final highs = _pivotHighs(c, from);
  if (highs.length < 2) return null;
  final top = highs.map((i) => c[i].high).reduce(math.max);
  final touches = highs.where((i) => c[i].high >= top * 0.995).toList();
  if (touches.length < 2 || touches.last - touches.first < 6) return null;
  if (_maxHigh(c, touches.first, n - 1) > top * 1.002) return null;
  final lows = _pivotLows(c, touches.first);
  if (lows.length < 2) return null;
  for (var i = 1; i < lows.length; i++) {
    if (c[lows[i]].low <= c[lows[i - 1]].low * 1.001) return null;
  }
  final height = (top - c[lows.first].low) / top * 100;
  if (height < math.max(0.8, 2 * _avgRangePct(c))) return null;
  final close = c.last.close;
  if (close < top * 0.994 || close > top * 1.015) return null;
  return ChartPattern('Ascending triangle',
      bullish: true,
      candle: false,
      note: '${touches.length} tests of the top, ${lows.length} rising lows');
}

/// Price above the highest high of the previous 24 candles on rising volume.
ChartPattern? rangeBreakout(List<Candle> c) {
  final n = c.length;
  if (n < 30) return null;
  final prevHigh = _maxHigh(c, n - 25, n - 1);
  if (c.last.close <= prevHigh) return null;
  if (_volRatio(c) < 1.5) return null;
  return ChartPattern('Range breakout',
      bullish: true, candle: false, note: 'New 24-candle high on ${_volRatio(c).toStringAsFixed(1)}x volume');
}

double _volRatio(List<Candle> c) {
  final n = c.length;
  final recent = c.sublist(n - 2).fold<double>(0, (a, k) => a + k.quoteVolume) / 2;
  final prior = c.sublist(n - 22, n - 2).fold<double>(0, (a, k) => a + k.quoteVolume) / 20;
  return prior > 0 ? recent / prior : 1;
}

// ---------------------------------------------------------------------------
// bearish chart patterns (warnings)
// ---------------------------------------------------------------------------

/// Two highs at about the same level with a dip between; price back down
/// near that dip.
ChartPattern? doubleTop(List<Candle> c) {
  final n = c.length;
  if (n < 25) return null;
  final piv = _pivotHighs(c, math.max(0, n - 60));
  final unit = _avgRangePct(c);
  for (final p2 in piv.reversed) {
    if (n - 1 - p2 > 15) break;
    for (final p1 in piv.reversed.where((i) => i <= p2 - 6)) {
      final a = c[p1].high, b = c[p2].high, high = math.max(a, b);
      final neck = _minLow(c, p1, p2 + 1);
      final h = high - neck;
      if (h <= 0 || h / high * 100 < math.max(1.0, 3 * unit)) continue;
      if ((a - b).abs() > 0.2 * h) continue;
      if (_maxHigh(c, p1, n) > high + 0.05 * h) continue;
      if (p1 < 5 || _minLow(c, math.max(0, p1 - 15), p1) > neck) continue; // came from below
      final close = c.last.close;
      if (close > neck + 0.3 * h || close < neck - 0.5 * h) continue;
      return ChartPattern('Double top',
          bullish: false,
          candle: false,
          note: 'Two highs ${p2 - p1} candles apart, price ${close < neck ? 'below' : 'near'} the neckline');
    }
  }
  return null;
}

/// Price below the lowest low of the previous 24 candles.
ChartPattern? rangeBreakdown(List<Candle> c) {
  final n = c.length;
  if (n < 30) return null;
  if (c.last.close >= _minLow(c, n - 25, n - 1)) return null;
  return const ChartPattern('Range breakdown',
      bullish: false, candle: false, note: 'New 24-candle low');
}

// ---------------------------------------------------------------------------
// candle patterns (on the last closed candle; the very last one is still forming)
// ---------------------------------------------------------------------------

double _body(Candle k) => (k.close - k.open).abs();
double _range(Candle k) => k.high - k.low;
double _upper(Candle k) => k.high - math.max(k.open, k.close);
double _lower(Candle k) => math.min(k.open, k.close) - k.low;
bool _green(Candle k) => k.close > k.open;
bool _red(Candle k) => k.close < k.open;

double _avgRange(List<Candle> c, int end, [int n = 20]) {
  final s = c.sublist(math.max(0, end - n), end);
  return s.isEmpty ? 0 : s.fold<double>(0, (a, k) => a + _range(k)) / s.length;
}

bool _fellBefore(List<Candle> c, int k) => k >= 6 && c[k - 1].close < c[k - 6].close;
bool _roseBefore(List<Candle> c, int k) => k >= 6 && c[k - 1].close > c[k - 6].close;

/// Long lower wick after a drop: sellers pushed down, buyers pushed back.
ChartPattern? hammer(List<Candle> c) {
  if (c.length < 25) return null;
  final k = c.length - 2;
  final x = c[k];
  if (_range(x) <= 0 || _range(x) < 0.8 * _avgRange(c, k)) return null;
  if (_lower(x) < 2 * _body(x) || _upper(x) > math.max(_body(x), 0.15 * _range(x))) return null;
  if (!_fellBefore(c, k)) return null;
  return const ChartPattern('Hammer',
      bullish: true, candle: true, note: 'Long lower wick after a drop');
}

ChartPattern? bullishEngulfing(List<Candle> c) {
  if (c.length < 25) return null;
  final k = c.length - 2;
  final x = c[k], prev = c[k - 1];
  if (!_red(prev) || !_green(x)) return null;
  if (x.open > prev.close || x.close < prev.open || _body(x) < 1.1 * _body(prev)) return null;
  if (_body(x) < 0.5 * _avgRange(c, k)) return null;
  if (!_fellBefore(c, k)) return null;
  return const ChartPattern('Bullish engulfing',
      bullish: true, candle: true, note: 'Green candle swallowed the previous red one');
}

ChartPattern? threeWhiteSoldiers(List<Candle> c) {
  if (c.length < 25) return null;
  final k = c.length - 2;
  final three = [c[k - 2], c[k - 1], c[k]];
  for (var i = 0; i < 3; i++) {
    final x = three[i];
    if (!_green(x) || _range(x) <= 0 || _body(x) < 0.5 * _range(x)) return null;
    if (i > 0 && (x.close <= three[i - 1].close || x.open < three[i - 1].open)) return null;
  }
  if (three.fold<double>(0, (a, x) => a + _body(x)) < 1.5 * _avgRange(c, k - 2)) return null;
  return const ChartPattern('Three white soldiers',
      bullish: true, candle: true, note: 'Three strong green candles in a row');
}

/// Long upper wick after a rise: buyers pushed up, sellers pushed back.
ChartPattern? shootingStar(List<Candle> c) {
  if (c.length < 25) return null;
  final k = c.length - 2;
  final x = c[k];
  if (_range(x) <= 0 || _range(x) < 0.8 * _avgRange(c, k)) return null;
  if (_upper(x) < 2 * _body(x) || _lower(x) > math.max(_body(x), 0.15 * _range(x))) return null;
  if (!_roseBefore(c, k)) return null;
  return const ChartPattern('Shooting star',
      bullish: false, candle: true, note: 'Long upper wick after a rise');
}

ChartPattern? bearishEngulfing(List<Candle> c) {
  if (c.length < 25) return null;
  final k = c.length - 2;
  final x = c[k], prev = c[k - 1];
  if (!_green(prev) || !_red(x)) return null;
  if (x.open < prev.close || x.close > prev.open || _body(x) < 1.1 * _body(prev)) return null;
  if (_body(x) < 0.5 * _avgRange(c, k)) return null;
  if (!_roseBefore(c, k)) return null;
  return const ChartPattern('Bearish engulfing',
      bullish: false, candle: true, note: 'Red candle swallowed the previous green one');
}
