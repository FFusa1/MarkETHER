/// Core data types shared by the API layer, analyzer and UI.
library;

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
  String get label => switch (this) {
        Rating.strongBuy => 'STRONG BUY',
        Rating.buy => 'BUY',
        Rating.neutral => 'NEUTRAL',
        Rating.avoid => 'AVOID',
      };
}

enum Regime { bullish, mixed, bearish }

class MarketRegime {
  final Regime regime;
  final String summary;
  final double btcPrice;
  final double btcReturn30d;

  const MarketRegime(this.regime, this.summary, this.btcPrice, this.btcReturn30d);
}

class CoinAnalysis {
  final String symbol;
  final String base;
  final Ticker ticker;
  final int score;
  final Rating rating;
  final List<Signal> signals;
  final List<Candle> daily;
  final List<Candle> h4;

  // Key indicator readings (null when there is not enough history).
  final double? rsiDaily;
  final double? adxDaily;
  final double? atrPercent;
  final double? relStrength30d;
  final double? volumeRatio;
  final double? macdHist4h;
  final double return30d;

  // Suggested trade levels.
  final double entry;
  final double stop;
  final double target;

  const CoinAnalysis({
    required this.symbol,
    required this.base,
    required this.ticker,
    required this.score,
    required this.rating,
    required this.signals,
    required this.daily,
    required this.h4,
    required this.rsiDaily,
    required this.adxDaily,
    required this.atrPercent,
    required this.relStrength30d,
    required this.volumeRatio,
    required this.macdHist4h,
    required this.return30d,
    required this.entry,
    required this.stop,
    required this.target,
  });

  double get riskReward {
    final risk = entry - stop;
    if (risk <= 0) return 0;
    return (target - entry) / risk;
  }

  Iterable<Signal> get positives => signals.where((s) => s.impact == Impact.positive);
  Iterable<Signal> get negatives => signals.where((s) => s.impact == Impact.negative);
}

class ScanResult {
  final List<CoinAnalysis> coins;
  final MarketRegime regime;
  final DateTime time;
  final int failed;

  const ScanResult(this.coins, this.regime, this.time, this.failed);
}
