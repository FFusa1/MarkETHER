# MarkETHER — Binance crypto scanner (Android + web)

Scans the most-traded Binance USDT spot pairs, runs a professional-style
technical analysis on each coin and ranks them with a 0–100 score.
Two modes, switched at the top of the app:

* **Swing (days – weeks)** — daily + 4h candles. Ratings: STRONG BUY · BUY · NEUTRAL · AVOID.
* **Scalp (minutes)** — 5m + 15m candles + live order book, auto-refresh every 60 s.
  Ratings: LONG NOW · LONG · WAIT · AVOID. Targets and stops are shown after
  Binance fees (0.1% buy + 0.1% sell).

## Scalp score (max 100)

| Category | Pts | What it checks |
|---|---|---|
| 15m trend | 20 | Price vs 15m EMA21, EMA9/EMA21 cross |
| 5m trend | 20 | Price vs 8h VWAP, 5m EMA9/21, holding EMA9 |
| Momentum | 20 | 5m RSI(7) zone, 5m MACD histogram & acceleration |
| Volume | 15 | Last 15 min volume vs previous 100 min |
| Order book | 15 | Share of buy-side value within 0.5% of price |
| Cost | 10 | Bid/ask spread |
| Penalties | | Too quiet / too wild (5m ATR), +4–8% in last hour, target < 0.3% after fees, spread > 0.15%, BTC falling on 15m |

Levels: entry = best ask, stop = 1.2× 5m ATR (min 0.25%), target = 2× stop distance.
Logic: `lib/scalp_analyzer.dart`.

## Swing score

* Read-only Binance public market data — no account, no API key, no trading.
* Swing-trading horizon: daily + 4-hour candles.
* Each coin: score breakdown with reasons, candlestick chart with EMA 20/50,
  suggested entry / stop-loss / target and risk-reward, key indicators.
* Market-regime filter: when BTC is in a downtrend, all altcoin scores are penalised.
* Watchlist saved on the phone.

Max 100:

| Category | Pts | What it checks |
|---|---|---|
| Trend | 30 | Price vs 50/200-day EMA, 20/50 EMA cross, 4h trend |
| Momentum | 20 | Daily RSI zone, 4h MACD histogram & acceleration, daily MACD |
| Relative strength | 15 | 30-day return vs BTC |
| Volume | 15 | 4h volume surge vs 20-bar average, 20-day OBV trend |
| Structure | 12 | ADX trend strength & direction, distance from 20-day high |
| Risk | 8 | Daily ATR % (volatility) |
| Chase risk | −14…0 | 24h spike penalty (≥10% −3, ≥15% −8, ≥25% −14) |
| Trade risk | −18…0 | Stop-loss >10% away (−3) / >15% (−8); risk/reward <1.5 (−5) / <1 (−10) |
| Market | −10…0 | BTC regime penalty (bearish −10, mixed −4) |

Thresholds: ≥72 Strong Buy, ≥58 Buy, ≥42 Neutral, otherwise Avoid.
A Strong Buy is capped to Buy if RSI > 80, the coin rose ≥15% in 24h,
risk/reward < 1.5 or the stop is >15% away. Risk/reward < 1 is never a Buy.
Stablecoins and pegged assets (price held within 2% near $1 for 30 days) are skipped.
Logic lives in `lib/analyzer.dart` and `lib/indicators.dart`.

## Building the APK (no tools needed on your PC)

The APK is built by GitHub Actions (`.github/workflows/build-apk.yml`).
Every push to `main` builds a new APK and publishes it under **Releases**.
Open the repository's *Releases* page on your phone, download
`MarketAI-N.apk` and install it (allow "Install unknown apps" for your browser).

## Disclaimer

The scores are automated technical signals, not financial advice.
Crypto is highly volatile — never risk money you cannot afford to lose.
