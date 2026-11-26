import 'dart:async';

import 'package:flutter/material.dart';

import '../binance_api.dart';
import '../format.dart';
import '../models.dart';
import '../watchlist.dart';
import 'detail_screen.dart';

enum _Filter { all, buys, watchlist }

class HomeScreen extends StatefulWidget {
  final Watchlist watchlist;
  const HomeScreen({super.key, required this.watchlist});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _scalpRefresh = Duration(seconds: 60);

  final _scanner = MarketScanner();
  final Map<TradeMode, ScanResult> _results = {};
  TradeMode _mode = TradeMode.swing;
  String? _error;
  bool _loading = false;
  int _done = 0;
  int _total = 0;
  int _topN = 50;
  _Filter _filter = _Filter.all;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.watchlist.addListener(_onWatchlist);
    _scan();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.watchlist.removeListener(_onWatchlist);
    super.dispose();
  }

  void _onWatchlist() {
    if (mounted) setState(() {});
  }

  void _setMode(TradeMode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _error = null;
    });
    _timer?.cancel();
    _timer = null;
    if (m == TradeMode.scalp) {
      // Scalp signals go stale within minutes: refresh automatically.
      _timer = Timer.periodic(_scalpRefresh, (_) {
        if (_mode == TradeMode.scalp && !_loading) _scan();
      });
    }
    final existing = _results[m];
    if (existing == null || DateTime.now().difference(existing.time) > _staleAfter(m)) _scan();
  }

  Duration _staleAfter(TradeMode m) =>
      m == TradeMode.scalp ? _scalpRefresh : const Duration(minutes: 15);

  Future<void> _scan() async {
    if (_loading) return;
    final mode = _mode;
    setState(() {
      _loading = true;
      _error = null;
      _done = 0;
      _total = 0;
    });
    try {
      final r = await _scanner.scan(
        mode: mode,
        topN: _topN,
        onProgress: (d, t) {
          if (mounted) {
            setState(() {
              _done = d;
              _total = t;
            });
          }
        },
      );
      if (mounted) setState(() => _results[mode] = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // If the user switched modes during the scan, load the new mode too.
    if (mounted && _mode != mode && _results[_mode] == null) _scan();
  }

  List<CoinAnalysis> _visible(ScanResult r) => switch (_filter) {
        _Filter.all => r.coins,
        _Filter.buys => r.coins
            .where((c) => c.rating == Rating.strongBuy || c.rating == Rating.buy)
            .toList(),
        _Filter.watchlist => r.coins.where((c) => widget.watchlist.contains(c.symbol)).toList(),
      };

  @override
  Widget build(BuildContext context) {
    final r = _results[_mode];
    final visible = r == null ? const <CoinAnalysis>[] : _visible(r);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MarkETHER', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Coins to scan',
            icon: const Icon(Icons.tune),
            initialValue: _topN,
            onSelected: (v) {
              setState(() => _topN = v);
              _scan();
            },
            itemBuilder: (_) => [30, 50, 80, 120]
                .map((n) => PopupMenuItem(value: n, child: Text('Scan top $n coins')))
                .toList(),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _scan,
          ),
        ],
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: _total == 0 ? null : _done / _total,
                ),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _scan,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SegmentedButton<TradeMode>(
                segments: const [
                  ButtonSegment(
                    value: TradeMode.swing,
                    icon: Icon(Icons.calendar_month, size: 18),
                    label: Text('Swing · days'),
                  ),
                  ButtonSegment(
                    value: TradeMode.scalp,
                    icon: Icon(Icons.bolt, size: 18),
                    label: Text('Scalp · minutes'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => _setMode(s.first),
              ),
            ),
            if (r != null)
              _RegimeCard(
                result: r,
                autoRefresh: _mode == TradeMode.scalp ? _scalpRefresh : null,
              ),
            if (_loading && r == null)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_total == 0
                      ? 'Loading Binance market…'
                      : 'Analysing coins $_done / $_total'),
                ]),
              ),
            if (_error != null) _ErrorCard(message: _error!, onRetry: _scan),
            if (r != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Wrap(spacing: 8, children: [
                  _chip('All (${r.coins.length})', _Filter.all),
                  _chip(_mode == TradeMode.scalp ? 'Long signals' : 'Buy signals', _Filter.buys),
                  _chip('Watchlist (${widget.watchlist.symbols.length})', _Filter.watchlist),
                ]),
              ),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child: Text('Nothing here right now.', style: TextStyle(color: Colors.white54))),
                ),
              ...visible.asMap().entries.map((e) => _CoinTile(
                    rank: e.key + 1,
                    coin: e.value,
                    starred: widget.watchlist.contains(e.value.symbol),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DetailScreen(coin: e.value, watchlist: widget.watchlist),
                    )),
                  )),
              _Disclaimer(mode: _mode),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, _Filter f) => ChoiceChip(
        label: Text(label),
        selected: _filter == f,
        onSelected: (_) => setState(() => _filter = f),
      );
}

class _RegimeCard extends StatelessWidget {
  final ScanResult result;
  final Duration? autoRefresh;
  const _RegimeCard({required this.result, this.autoRefresh});

  @override
  Widget build(BuildContext context) {
    final regime = result.regime;
    final (color, label) = switch (regime.regime) {
      Regime.bullish => (upColor, 'BULLISH'),
      Regime.mixed => (const Color(0xFFFFB300), 'MIXED'),
      Regime.bearish => (downColor, 'BEARISH'),
    };
    final title = result.mode == TradeMode.scalp ? 'BTC short-term' : 'Market regime';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title, style: const TextStyle(color: Colors.white60)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const Spacer(),
            Text(
              autoRefresh == null
                  ? timeAgo(result.time)
                  : '${timeAgo(result.time)} · auto ${autoRefresh!.inSeconds}s',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ]),
          const SizedBox(height: 8),
          Text(regime.summary),
          const SizedBox(height: 6),
          Text(
            'BTC \$${fmtPrice(regime.btcPrice)} · ${regime.returnLabel} ${fmtPct(regime.btcReturn, digits: 1)} · ${result.coins.length} coins analysed',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ]),
      ),
    );
  }
}

class _CoinTile extends StatelessWidget {
  final int rank;
  final CoinAnalysis coin;
  final bool starred;
  final VoidCallback onTap;
  const _CoinTile(
      {required this.rank, required this.coin, required this.starred, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = coin.ticker;
    final reasons = coin.positives.take(2).map((s) => s.text).join(' · ');
    final scalp = coin.mode == TradeMode.scalp;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ScoreBadge(score: coin.score),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('$rank. ', style: const TextStyle(color: Colors.white38)),
                  Flexible(
                    child: Text(coin.base,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  if (starred)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.star, size: 14, color: Color(0xFFFFB300)),
                    ),
                  const SizedBox(width: 8),
                  RatingChip(rating: coin.rating, mode: coin.mode),
                ]),
                const SizedBox(height: 4),
                Text(
                  scalp
                      ? 'Target ${fmtPct(coin.netRewardPct)} · Stop ${fmtPct(-coin.netRiskPct)} after fees'
                      : (reasons.isEmpty ? 'No strong positive signals' : reasons),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                if (coin.patterns.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      coin.patterns.map((p) => '${p.bullish ? '▲' : '▼'} ${p.name}').join('  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: coin.patterns.any((p) => p.bullish)
                              ? const Color(0xFF80CBC4)
                              : downColor),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtPrice(t.lastPrice), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(fmtPct(t.changePercent),
                  style: TextStyle(color: changeColor(t.changePercent), fontSize: 12)),
              Text('Vol ${fmtCompact(t.quoteVolume)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class ScoreBadge extends StatelessWidget {
  final int score;
  final double size;
  const ScoreBadge({super.key, required this.score, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final color = scoreColor(score);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 4,
            color: color,
            backgroundColor: Colors.white10,
          ),
        ),
        Text('$score',
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: size * 0.33)),
      ]),
    );
  }
}

class RatingChip extends StatelessWidget {
  final Rating rating;
  final TradeMode mode;
  const RatingChip({super.key, required this.rating, this.mode = TradeMode.swing});

  @override
  Widget build(BuildContext context) {
    final c = ratingColor(rating);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(rating.labelFor(mode),
          style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Icon(Icons.cloud_off, color: downColor, size: 36),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}

class _Disclaimer extends StatelessWidget {
  final TradeMode mode;
  const _Disclaimer({required this.mode});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(
          mode == TradeMode.scalp
              ? 'Scalp signals are a snapshot — prices move in seconds. Check the live Binance chart '
                  'before entering, always set the stop-loss, and remember fees (~0.1% per side) are '
                  'already included in the targets shown. Not financial advice.'
              : 'Scores are generated automatically from technical indicators on Binance public data. '
                  'They are not financial advice and do not guarantee future prices. Crypto is highly '
                  'volatile — only risk money you can afford to lose and always use a stop-loss.',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      );
}
