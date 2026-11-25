/// Core data types shared by the API layer, analyzers and UI.
library;

enum TradeMode { swing, scalp }

extension TradeModeInfo on TradeMode {
  String get title => this == TradeMode.swing ? 'Swing' : 'Scalp';
  String get horizon => this == TradeMode.swing ? 'days – weeks' : 'minutes';
}

class Candle {
  final DateTime openTime;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final double quoteVolume;

  const Candle({
    required this.openTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.quoteVolume,
  });

  /// Binance kline array: [openTime, open, high, low, close, volume,
  /// closeTime, quoteAssetVolume, trades, ...]
  factory Candle.fromJson(List<dynamic> k) => Candle(
        openTime: DateTime.fromMillisecondsSinceEpoch((k[0] as num).toInt()),
        open: double.parse(k[1] as String),
        high: double.parse(k[2] as String),
        low: double.parse(k[3] as String),
        close: double.parse(k[4] as String),
        volume: double.parse(k[5] as String),
        quoteVolume: double.parse(k[7] as String),
      );
}

class Ticker {
  final String symbol;
  final double lastPrice;
  final double changePercent;
  final double quoteVolume;
  final double high;
  final double low;
  final int trades;

  const Ticker({
    required this.symbol,
    required this.lastPrice,
    required this.changePercent,
    required this.quoteVolume,
    required this.high,
    required this.low,
    required this.trades,
  });

  factory Ticker.fromJson(Map<String, dynamic> j) => Ticker(
        symbol: j['symbol'] as String,
        lastPrice: double.tryParse('${j['lastPrice']}') ?? 0,
        changePercent: double.tryParse('${j['priceChangePercent']}') ?? 0,
        quoteVolume: double.tryParse('${j['quoteVolume']}') ?? 0,
        high: double.tryParse('${j['highPrice']}') ?? 0,
        low: double.tryParse('${j['lowPrice']}') ?? 0,
        trades: (j['count'] as num?)?.toInt() ?? 0,
      );

  /// Stablecoin-like: priced near $1 and barely moved in 24h.
  bool get looksPegged =>
      lastPrice > 0.97 && lastPrice < 1.03 && low > 0 && high / low < 1.01;
}

/// Top of the order book. Each level is [price, quantity].
class OrderBook {
  final List<List<double>> bids;
  final List<List<double>> asks;

  const OrderBook(this.bids, this.asks);

  factory OrderBook.fromJson(Map<String, dynamic> j) {
    List<List<double>> parse(dynamic side) => (side as List<dynamic>)
        .map((l) => [
              double.parse((l as List<dynamic>)[0] as String),
              double.parse(l[1] as String),
            ])
        .toList();
    return OrderBook(parse(j['bids']), parse(j['asks']));
  }

  double get bestBid => bids.isEmpty ? 0 : bids.first[0];
  double get bestAsk => asks.isEmpty ? 0 : asks.first[0];
  double get mid => (bestBid + bestAsk) / 2;
  double get spreadPct => mid > 0 ? (bestAsk - bestBid) / mid * 100 : 0;

  /// Share (0..1) of the dollar value resting within [pct]% of the mid price
  /// that sits on the buy side. Above 0.5 = more buyers waiting than sellers.
  double imbalance([double pct = 0.5]) {
    final m = mid;
    if (m <= 0) return 0.5;
    final lo = m * (1 - pct / 100);
    final hi = m * (1 + pct / 100);
    double bid = 0, ask = 0;
    for (final l in bids) {
      if (l[0] >= lo) bid += l[0] * l[1];
    }
    for (final l in asks) {
      if (l[0] <= hi) ask += l[0] * l[1];
    }
    final total = bid + ask;
    return total == 0 ? 0.5 : bid / total;
  }
}

enum Impact { positive, negative, neutral }

class Signal {
  final String category;
  final String text;
  final Impact impact;
  final int points;
  final int maxPoints;

  const Signal(this.category, this.text, this.impact, this.points, this.maxPoints);
}

enum Rating { strongBuy, buy, neutral, avoid }

extension RatingLabel on Rating {
  String get label => labelFor(TradeMode.swing);

  String labelFor(TradeMode mode) => switch ((this, mode)) {
        (Rating.strongBuy, TradeMode.swing) => 'STRONG BUY',
        (Rating.buy, TradeMode.swing) => 'BUY',
        (Rating.strongBuy, TradeMode.scalp) => 'LONG NOW',
        (Rating.buy, TradeMode.scalp) => 'LONG',
        (Rating.neutral, TradeMode.swing) => 'NEUTRAL',
        (Rating.neutral, TradeMode.scalp) => 'WAIT',
        (Rating.avoid, _) => 'AVOID',
      };
}

enum Regime { bullish, mixed, bearish }

class MarketRegime {
  final Regime regime;
  final String summary;
  final double btcPrice;
  final double btcReturn;

  /// Period of [btcReturn], e.g. '30d' or '4h'.
  final String returnLabel;

  const MarketRegime(this.regime, this.summary, this.btcPrice, this.btcReturn, this.returnLabel);
}

/// One labelled indicator reading for the detail screen.
class Stat {
  final String label;
  final String value;
  const Stat(this.label, this.value);
}

class CoinAnalysis {
  final TradeMode mode;
  final String symbol;
  final String base;
  final Ticker ticker;
  final int score;
  final Rating rating;
  final List<Signal> signals;

  /// Chart series by timeframe label, e.g. {'1D': ..., '4H': ...}.
  final Map<String, List<Candle>> charts;
  final List<Stat> stats;

  // Suggested trade levels.
  final double entry;
  final double stop;
  final double target;

  /// Round-trip trading fees in percent (buy + sell).
  final double feePct;

  const CoinAnalysis({
    required this.mode,
    required this.symbol,
    required this.base,
    required this.ticker,
    required this.score,
    required this.rating,
    required this.signals,
    required this.charts,
    required this.stats,
    required this.entry,
    required this.stop,
    required this.target,
    this.feePct = 0.2,
  });

  double get riskPct => entry > 0 ? (entry - stop) / entry * 100 : 0;
  double get rewardPct => entry > 0 ? (target - entry) / entry * 100 : 0;

  double get riskReward => riskPct <= 0 ? 0 : rewardPct / riskPct;

  /// Profit at target / loss at stop once fees are paid.
  double get netRewardPct => rewardPct - feePct;
  double get netRiskPct => riskPct + feePct;
  double get netRiskReward => netRiskPct <= 0 ? 0 : netRewardPct / netRiskPct;

  Iterable<Signal> get positives => signals.where((s) => s.impact == Impact.positive);
  Iterable<Signal> get negatives => signals.where((s) => s.impact == Impact.negative);
}

class ScanResult {
  final TradeMode mode;
  final List<CoinAnalysis> coins;
  final MarketRegime regime;
  final DateTime time;
  final int failed;

  const ScanResult(this.mode, this.coins, this.regime, this.time, this.failed);
}
