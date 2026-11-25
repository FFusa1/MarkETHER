import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../watchlist.dart';
import '../widgets/price_chart.dart';
import 'home_screen.dart';

class DetailScreen extends StatefulWidget {
  final CoinAnalysis coin;
  final Watchlist watchlist;
  const DetailScreen({super.key, required this.coin, required this.watchlist});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late String _chart = widget.coin.charts.keys.first;

  @override
  Widget build(BuildContext context) {
    final c = widget.coin;
    final t = c.ticker;
    final scalp = c.mode == TradeMode.scalp;
    final starred = widget.watchlist.contains(c.symbol);

    return Scaffold(
      appBar: AppBar(
        title: Text('${c.base} / USDT · ${c.mode.title}'),
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
                      'Volume \$${fmtCompact(t.quoteVolume)} · horizon: ${c.mode.horizon}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ]),
                ),
                Column(children: [
                  ScoreBadge(score: c.score, size: 72),
                  const SizedBox(height: 6),
                  RatingChip(rating: c.rating, mode: c.mode),
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
                  for (final k in c.charts.keys) ...[
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(k),
                      selected: _chart == k,
                      onSelected: (_) => setState(() => _chart = k),
                    ),
                  ],
                ]),
                const SizedBox(height: 10),
                PriceChart(
                  candles: c.charts[_chart] ?? const [],
                  fast: scalp ? 9 : 20,
                  slow: scalp ? 21 : 50,
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
                Text(scalp ? 'Scalp plan (long)' : 'Suggested trade plan',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _levelRow(scalp ? 'Entry (best ask now)' : 'Entry (current price)', c.entry, null,
                    Colors.white),
                _levelRow('Stop-loss', c.stop, -c.riskPct, downColor),
                _levelRow('Target', c.target, c.rewardPct, upColor),
                const Divider(height: 20),
                if (scalp) ...[
                  Text(
                    'After fees (0.1% buy + 0.1% sell): '
                    'win ${fmtPct(c.netRewardPct)} · loss ${fmtPct(-c.netRiskPct)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  scalp
                      ? 'Net risk / reward: 1 : ${c.netRiskReward.toStringAsFixed(2)}'
                      : 'Risk / reward: 1 : ${c.riskReward.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: (scalp ? c.netRiskReward >= 1.2 : c.riskReward >= 1.5)
                          ? upColor
                          : const Color(0xFFFFB300),
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  scalp
                      ? 'Stop = 1.2× the 5-minute ATR (min 0.25%), target = 2× the stop distance. '
                          'Exit at target or stop — do not hold a failed scalp hoping it comes back.'
                      : 'Stop is placed under the recent swing low (max 2.5× daily ATR). '
                          'Target is the 60-day high, or 3× ATR if price is already near it.',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
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
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: c.stats.map((s) => _stat(s.label, s.value)).toList(),
                ),
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
              child: Text(fmtPct(pct, digits: 2),
                  textAlign: TextAlign.right, style: TextStyle(color: color, fontSize: 12)),
            ),
        ]),
      );

  Widget _stat(String label, String value) => Container(
        width: 100,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
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
