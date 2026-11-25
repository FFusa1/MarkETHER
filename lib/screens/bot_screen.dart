import 'package:flutter/material.dart';

import '../bot/paper_bot.dart';
import '../format.dart';

class BotScreen extends StatelessWidget {
  final PaperBot bot;
  const BotScreen({super.key, required this.bot});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MarkETHER Bot', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListenableBuilder(
        listenable: bot,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _StatusCard(bot: bot),
            _SummaryRow(bot: bot),
            _OpenPositions(bot: bot),
            _StatsCard(bot: bot),
            _LearningCard(bot: bot),
            _SettingsCard(bot: bot),
            _Journal(bot: bot),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset paper account'),
                onPressed: () => _confirmReset(context),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Paper mode uses fake money on real Binance prices: it buys at the ask, sells at the '
                'bid or the target, and pays 0.1% fees on each side. Results are a simulation and '
                'not financial advice.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset paper account?'),
        content: const Text(
            'This deletes all paper trades, open positions and learning data. It cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) await bot.resetPaper();
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;
  const _Section({required this.title, this.trailing, required this.children});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );
}

class _StatusCard extends StatelessWidget {
  final PaperBot bot;
  const _StatusCard({required this.bot});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (bot.state) {
      BotState.running => (upColor, bot.busy ? 'SCANNING…' : 'RUNNING'),
      BotState.pausedDailyLimit => (const Color(0xFFFFB300), 'PAUSED · DAILY LOSS LIMIT'),
      BotState.stopped => (Colors.white54, 'STOPPED'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const Spacer(),
            if (bot.running)
              FilledButton.tonalIcon(
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
                onPressed: bot.stop,
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
                onPressed: bot.start,
              ),
          ]),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.science, size: 18), label: Text('Paper')),
              ButtonSegment(
                  value: true,
                  icon: Icon(Icons.lock, size: 18),
                  label: Text('Live'),
                  enabled: false),
            ],
            selected: const {false},
            onSelectionChanged: (_) {},
          ),
          const SizedBox(height: 6),
          const Text(
            'Live trading unlocks after the paper phase (300+ trades with profit after fees).',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Text(
            bot.running
                ? 'Scans the top ${bot.settings.topN} coins every minute and buys LONG NOW signals. '
                    'Checks open trades every 15 seconds. On Android it keeps running in the '
                    'background (you will see a notification) until you press Stop or swipe the app '
                    'away. In a browser it runs while this tab is open.'
                : 'Press Start to begin a paper session.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (bot.lastEvent != null) ...[
            const SizedBox(height: 8),
            Text(bot.lastEvent!, style: const TextStyle(fontSize: 13)),
          ],
          if (bot.lastScan != null)
            Text('Last scan ${timeAgo(bot.lastScan!)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          if (bot.lastError != null) ...[
            const SizedBox(height: 6),
            Text(bot.lastError!, style: const TextStyle(color: downColor, fontSize: 12)),
          ],
        ]),
      ),
    );
  }
}

String _usd(double v) => '${v >= 0 ? '+' : '−'}\$${v.abs().toStringAsFixed(2)}';

class _SummaryRow extends StatelessWidget {
  final PaperBot bot;
  const _SummaryRow({required this.bot});

  @override
  Widget build(BuildContext context) {
    final s = bot.stats;
    Widget tile(String label, String value, [Color? color]) => Expanded(
          child: Card(
            margin: const EdgeInsets.all(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(children: [
                Text(value,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        tile('Today', _usd(bot.todayPnl), changeColor(bot.todayPnl)),
        tile('Total', _usd(s.netUsd), changeColor(s.netUsd)),
        tile('Win rate', s.trades == 0 ? '—' : '${s.winRate.toStringAsFixed(0)}%'),
        tile('Trades', '${s.trades}'),
      ]),
    );
  }
}

class _OpenPositions extends StatelessWidget {
  final PaperBot bot;
  const _OpenPositions({required this.bot});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Open trades (${bot.open.length}/${bot.settings.maxOpen})',
      trailing: bot.open.isEmpty
          ? null
          : TextButton(onPressed: bot.closeAll, child: const Text('Close all')),
      children: [
        if (bot.open.isEmpty)
          const Text('No open trades. The bot buys when a coin reaches LONG NOW.',
              style: TextStyle(color: Colors.white54)),
        for (final p in bot.open)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p.base}  ·  score ${p.score}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    'In ${fmtPrice(p.entryPrice)} · stop ${fmtPrice(p.stop)} · target ${fmtPrice(p.target)}\n'
                    '\$${p.size.toStringAsFixed(2)} · ${DateTime.now().difference(p.entryTime).inMinutes} min',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmtPrice(p.lastBid ?? p.entryPrice)),
                Text(fmtPct(p.netPctAt(p.lastBid ?? p.entryPrice)),
                    style: TextStyle(
                        color: changeColor(p.netPctAt(p.lastBid ?? p.entryPrice)), fontSize: 12)),
              ]),
              IconButton(
                tooltip: 'Close this trade now',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => bot.closePosition(p),
              ),
            ]),
          ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  final PaperBot bot;
  const _StatsCard({required this.bot});

  @override
  Widget build(BuildContext context) {
    final s = bot.stats;
    Widget row(String k, String v, [Color? c]) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(color: Colors.white70))),
            Text(v, style: TextStyle(fontWeight: FontWeight.w600, color: c)),
          ]),
        );
    final goal = (s.trades / 300).clamp(0.0, 1.0);
    return _Section(title: 'Paper results', children: [
      row('Trades', '${s.trades}  (${s.wins} wins · ${s.trades - s.wins} losses)'),
      row('Net profit after fees', _usd(s.netUsd), changeColor(s.netUsd)),
      row('Average win', s.wins == 0 ? '—' : fmtPct(s.avgWinPct), upColor),
      row('Average loss', s.trades - s.wins == 0 ? '—' : fmtPct(s.avgLossPct), downColor),
      row('Profit factor',
          s.trades == 0 ? '—' : (s.profitFactor.isInfinite ? '∞' : s.profitFactor.toStringAsFixed(2))),
      row('Worst losing streak', '${s.worstLosingStreak}'),
      const SizedBox(height: 10),
      Text('Progress to the go-live check: ${s.trades} / 300 trades',
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 4),
      LinearProgressIndicator(value: goal, minHeight: 6, borderRadius: BorderRadius.circular(3)),
    ]);
  }
}

class _LearningCard extends StatelessWidget {
  final PaperBot bot;
  const _LearningCard({required this.bot});

  @override
  Widget build(BuildContext context) {
    final list = bot.insights;
    final ready = list.where((i) => i.enoughData).toList();
    return _Section(title: 'What it is learning', children: [
      const Text(
        'For each signal, compares trades where it was strong with trades where it was weak. '
        'A positive edge means that signal helps pick winners.',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
      const SizedBox(height: 8),
      if (ready.isEmpty)
        Text(
          'Not enough trades yet. Each signal needs at least ${Insight.minPerGroup} strong and '
          '${Insight.minPerGroup} weak trades (${bot.trades.length} trades so far).',
          style: const TextStyle(color: Colors.white70),
        ),
      for (final i in ready)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(i.edge > 0.05 ? Icons.trending_up : (i.edge < -0.05 ? Icons.trending_down : Icons.remove),
                size: 16,
                color: i.edge > 0.05 ? upColor : (i.edge < -0.05 ? downColor : Colors.white38)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${i.category}: strong ${i.strongWinRate.toStringAsFixed(0)}% wins (${i.strongN}) · '
                'weak ${i.weakWinRate.toStringAsFixed(0)}% (${i.weakN})',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Text('edge ${fmtPct(i.edge)}',
                style: TextStyle(fontSize: 12, color: changeColor(i.edge))),
          ]),
        ),
    ]);
  }
}

class _SettingsCard extends StatelessWidget {
  final PaperBot bot;
  const _SettingsCard({required this.bot});

  @override
  Widget build(BuildContext context) {
    final s = bot.settings;
    Widget pick<T>(String label, T value, List<T> options, String Function(T) show,
            void Function(T) set) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
            DropdownButton<T>(
              value: value,
              underline: const SizedBox.shrink(),
              items: options
                  .map((o) => DropdownMenuItem<T>(value: o, child: Text(show(o))))
                  .toList(),
              onChanged: (v) {
                if (v != null) bot.updateSettings((_) => set(v));
              },
            ),
          ]),
        );
    final sizes = {5.0, 7.0, 10.0, 20.0, 50.0, s.tradeSize}.toList()..sort();
    final limits = {2.0, 3.0, 5.0, 10.0, 20.0, s.dailyLossLimit}.toList()..sort();
    return _Section(title: 'Settings', children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Start automatically when I open the app'),
        value: s.autoStart,
        onChanged: (v) => bot.updateSettings((x) => x.autoStart = v),
      ),
      pick<double>('Trade size', s.tradeSize, sizes, (v) => '\$${v.toStringAsFixed(0)}',
          (v) => s.tradeSize = v),
      pick<int>('Max open trades', s.maxOpen, [1, 2, 3, 5], (v) => '$v', (v) => s.maxOpen = v),
      pick<double>('Daily loss limit', s.dailyLossLimit, limits, (v) => '\$${v.toStringAsFixed(0)}',
          (v) => s.dailyLossLimit = v),
      pick<int>('Close trade after', s.timeLimitMin, [30, 60, 120], (v) => '$v min',
          (v) => s.timeLimitMin = v),
      pick<int>('Coins to scan', s.topN, [30, 50, 80, 120], (v) => 'top $v', (v) => s.topN = v),
    ]);
  }
}

class _Journal extends StatelessWidget {
  final PaperBot bot;
  const _Journal({required this.bot});

  @override
  Widget build(BuildContext context) {
    final recent = bot.trades.take(50).toList();
    return _Section(title: 'Trade journal', children: [
      if (recent.isEmpty)
        const Text('Closed trades appear here.', style: TextStyle(color: Colors.white54)),
      for (final t in recent)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Icon(t.win ? Icons.check_circle : Icons.cancel,
                size: 16, color: t.win ? upColor : downColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t.base} · ${t.reason}', style: const TextStyle(fontSize: 13)),
                Text(
                  '${_hm(t.entryTime)} → ${_hm(t.exitTime)} · ${t.duration.inMinutes} min · score ${t.score}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_usd(t.netUsd), style: TextStyle(color: changeColor(t.netUsd), fontSize: 13)),
              Text(fmtPct(t.netPct),
                  style: TextStyle(color: changeColor(t.netPct), fontSize: 11)),
            ]),
          ]),
        ),
      if (bot.trades.length > recent.length)
        Text('Showing the latest 50 of ${bot.trades.length} trades.',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
    ]);
  }
}

String _hm(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}
