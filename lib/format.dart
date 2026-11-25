import 'package:flutter/material.dart';

import 'models.dart';

String fmtPrice(double p) {
  if (p >= 1000) return p.toStringAsFixed(2);
  if (p >= 1) return p.toStringAsFixed(4);
  if (p == 0) return '0';
  return p.toStringAsPrecision(4);
}

String fmtCompact(double v) {
  if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}

String fmtPct(double v, {int digits = 2}) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(digits)}%';

const upColor = Color(0xFF26A69A);
const downColor = Color(0xFFEF5350);

Color changeColor(double v) => v >= 0 ? upColor : downColor;

Color ratingColor(Rating r) => switch (r) {
      Rating.strongBuy => const Color(0xFF00C853),
      Rating.buy => const Color(0xFF66BB6A),
      Rating.neutral => const Color(0xFFFFB300),
      Rating.avoid => const Color(0xFFEF5350),
    };

Color scoreColor(int s) {
  if (s >= 72) return ratingColor(Rating.strongBuy);
  if (s >= 58) return ratingColor(Rating.buy);
  if (s >= 42) return ratingColor(Rating.neutral);
  return ratingColor(Rating.avoid);
}

Color impactColor(Impact i) => switch (i) {
      Impact.positive => upColor,
      Impact.negative => downColor,
      Impact.neutral => const Color(0xFF9E9E9E),
    };

IconData impactIcon(Impact i) => switch (i) {
      Impact.positive => Icons.trending_up,
      Impact.negative => Icons.trending_down,
      Impact.neutral => Icons.remove,
    };

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  return '${d.inHours} h ago';
}
