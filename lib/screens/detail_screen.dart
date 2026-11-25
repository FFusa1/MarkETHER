import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../watchlist.dart';
import '../widgets/price_chart.dart';
import 'home_screen.dart';

class DetailScreen extends StatefulWidget {
  final CoinAnalysis coin;
  final MarketRegime regime;
  final Watchlist watchlist;
  const DetailScreen(
      {super.key, required this.coin, required this.regime, required this.watchlist});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _daily = true;

  @override
  Widget build(BuildContext context) {
    final c = widget.coin;
    final t = c.ticker;
    final starred = widget.watchlist.contains(c.symbol);
    final riskPct = (c.entry - c.stop) / c.entry * 100;
    final rewardPct = (c.target - c.entry) / c.entry * 100;

    return Scaffold(
      appBar: AppBar(
        title: Text('${c.base} / USDT'),
        actions: [
          IconButton(
            tooltip: starred ? 'Remove from watchlist' : 'Add to watchlist',
            icon: Icon(starred ? Icons.star : Icons.star_border,
                color: starred ? const Color(0xFFFFB300) : null),
            onPressed: () async {
              await widget.watchlist.toggle(c.symbol);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Header: price + score
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(fmtPrice(t.lastPrice),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    Text('${fmtPct(t.changePercent)} 24h',
                        style: TextStyle(color: changeColor(t.changePercent))),
                    const SizedBox(height: 4),
                    Text(
                      '24h range ${fmtPrice(t.low)} – ${fmtPrice(t.high)}\n'
                      'Volume \$${fmtCompact(t.quoteVolume)} · 30d ${fmtPct(c.return30d, digits: 1)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ]),
                ),
                Column(children: [
                  ScoreBadge(score: c.score, size: 72),
                  const SizedBox(height: 6),
                  RatingChip(rating: c.rating),
                ]),
              ]),
            ),
          ),

          // Chart
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('Chart', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  ChoiceChip(
                    label: const Text('1D'),
                    selected: _daily,
                    onSelected: (_) => setState(() => _daily = true),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('4H'),
                    selected: !_daily,
                    onSelected: (_) => setState(() => _daily = false),
                  ),
                ]),
                const SizedBox(height: 10),
                PriceChart(
                  candles: _daily ? c.daily : c.h4,
                  stop: c.stop,
                  target: c.target,
                ),
              ]),
            ),
          ),

          // Trade plan
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Suggested trade plan', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _levelRow('Entry (current price)', c.entry, null, Colors.white),
                _levelRow('Stop-loss', c.stop, -riskPct, downColor),
                _levelRow('Target', c.target, rewardPct, upColor),
                const Divider(height: 20),
                Text('Risk / reward: 1 : ${c.riskReward.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: c.riskReward >= 1.5 ? upColor : const Color(0xFFFFB300),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text(
                  'Stop is placed under the recent swing low (max 2.5× daily ATR). '
                  'Target is the 60-day high, or 3× ATR if price is already near it.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ]),
            ),
          ),

          // Key indicators
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Key indicators', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _stat('RSI (1D)', c.rsiDaily?.toStringAsFixed(0)),
                  _stat('ADX (1D)', c.adxDaily?.toStringAsFixed(0)),
                  _stat('ATR % (1D)', c.atrPercent == null ? null : '${c.atrPercent!.toStringAsFixed(1)}%'),
                  _stat('vs BTC 30d',
                      c.relStrength30d == null ? '—' : fmtPct(c.relStrength30d!, digits: 1)),
                  _stat('Volume (4H)',
                      c.volumeRatio == null ? null : '${c.volumeRatio!.toStringAsFixed(1)}x'),
                  _stat('MACD hist (4H)',
                      c.macdHist4h == null ? null : (c.macdHist4h! >= 0 ? 'Positive' : 'Negative')),
                ]),
              ]),
            ),
          ),

          // Signals
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Score breakdown (${c.score}/100)',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...c.signals.map(_signalRow),
              ]),
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'This is an automated technical analysis, not financial advice. '
              'Always do your own research and never risk more than you can afford to lose.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelRow(String label, double price, double? pct, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
          Text(fmtPrice(price), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          if (pct != null)
            SizedBox(
              width: 70,
              child: Text(fmtPct(pct, digits: 1),
                  textAlign: TextAlign.right, style: TextStyle(color: color, fontSize: 12)),
            ),
        ]),
      );

  Widget _stat(String label, String? value) => Container(
        width: 100,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _signalRow(Signal s) {
    final color = impactColor(s.impact);
    final pts = s.maxPoints == 0 ? '${s.points}' : '${s.points}/${s.maxPoints}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(impactIcon(s.impact), size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: '${s.category}  ',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            TextSpan(text: s.text, style: const TextStyle(fontSize: 13)),
          ])),
        ),
        Text(pts, style: TextStyle(color: color, fontSize: 12)),
      ]),
    );
  }
}
