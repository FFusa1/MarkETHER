import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format.dart';
import '../indicators.dart';
import '../models.dart';

/// Candlestick chart with EMA 20/50 overlays and optional stop/target lines.
class PriceChart extends StatelessWidget {
  final List<Candle> candles;
  final int visible;
  final double? stop;
  final double? target;

  const PriceChart({
    super.key,
    required this.candles,
    this.visible = 90,
    this.stop,
    this.target,
  });

  @override
  Widget build(BuildContext context) {
    final closes = candles.map((c) => c.close).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 240,
          width: double.infinity,
          child: CustomPaint(
            painter: _ChartPainter(
              candles: candles,
              ema20: ema(closes, 20),
              ema50: ema(closes, 50),
              visible: visible,
              stop: stop,
              target: target,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Wrap(spacing: 14, children: [
          _Legend(color: Color(0xFF42A5F5), label: 'EMA 20'),
          _Legend(color: Color(0xFFFFA726), label: 'EMA 50'),
          _Legend(color: upColor, label: 'Target'),
          _Legend(color: downColor, label: 'Stop'),
        ]),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 3, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ]);
}

class _ChartPainter extends CustomPainter {
  final List<Candle> candles;
  final List<double?> ema20;
  final List<double?> ema50;
  final int visible;
  final double? stop;
  final double? target;

  _ChartPainter({
    required this.candles,
    required this.ema20,
    required this.ema50,
    required this.visible,
    this.stop,
    this.target,
  });

  static const _axisWidth = 62.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final start = math.max(0, candles.length - visible);
    final view = candles.sublist(start);
    final chartW = size.width - _axisWidth;

    var lo = view.map((c) => c.low).reduce(math.min);
    var hi = view.map((c) => c.high).reduce(math.max);
    for (final v in [stop, target]) {
      if (v != null && v > 0) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    final pad = (hi - lo) * 0.05;
    lo -= pad;
    hi += pad;
    if (hi <= lo) hi = lo + 1;

    double y(double p) => size.height - (p - lo) / (hi - lo) * size.height;
    final step = chartW / view.length;
    double x(int i) => i * step + step / 2;

    // Grid + price axis
    final grid = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;
    for (var g = 0; g <= 4; g++) {
      final p = lo + (hi - lo) * g / 4;
      final yy = y(p);
      canvas.drawLine(Offset(0, yy), Offset(chartW, yy), grid);
      _text(canvas, fmtPrice(p), Offset(chartW + 4, yy - 7), Colors.white54);
    }

    // Candles
    final bodyW = math.max(1.0, step * 0.65);
    for (var i = 0; i < view.length; i++) {
      final c = view[i];
      final color = c.close >= c.open ? upColor : downColor;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x(i), y(c.high)), Offset(x(i), y(c.low)), paint);
      final top = y(math.max(c.open, c.close));
      final bottom = y(math.min(c.open, c.close));
      canvas.drawRect(
          Rect.fromLTRB(x(i) - bodyW / 2, top, x(i) + bodyW / 2, math.max(bottom, top + 1)), paint);
    }

    // EMA overlays
    void line(List<double?> series, Color color) {
      final path = Path();
      var started = false;
      for (var i = 0; i < view.length; i++) {
        final v = series[start + i];
        if (v == null) continue;
        if (!started) {
          path.moveTo(x(i), y(v));
          started = true;
        } else {
          path.lineTo(x(i), y(v));
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }

    line(ema20, const Color(0xFF42A5F5));
    line(ema50, const Color(0xFFFFA726));

    // Stop / target
    void level(double? v, Color color) {
      if (v == null || v <= 0) return;
      final yy = y(v);
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1;
      for (double xx = 0; xx < chartW; xx += 8) {
        canvas.drawLine(Offset(xx, yy), Offset(math.min(xx + 4, chartW), yy), paint);
      }
      _text(canvas, fmtPrice(v), Offset(chartW + 4, yy - 7), color);
    }

    level(stop, downColor);
    level(target, upColor);
  }

  void _text(Canvas canvas, String s, Offset o, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _axisWidth - 4);
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.candles != candles || old.visible != visible || old.stop != stop || old.target != target;
}
