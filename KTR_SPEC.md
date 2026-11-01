# Codex Task — Develop Kumo Trend Rider (KTR) v1.0

## 0. Objective and repository

Develop a new MetaTrader 5 Expert Advisor in MQL5 named **Kumo Trend Rider (KTR)**.

Repository: `https://github.com/mojtaba-brz/FarzadSys`

Create the new EA in the **same directory as the existing RSI Pull Up EA**.

Suggested new main file:

`Kumo_Trend_Rider.mq5`

Before implementation, inspect the existing repository structure, coding conventions, README, and testing infrastructure.

**Important:**

- Create KTR as an independent EA, not an extension of RSI Pull Up.
- Do not change `RSI_Pull_Up.mq5` or its established behavior.
- Shared utility files are acceptable only if they do not introduce regressions into the existing project.
- Prefer modular, readable MQL5 code using `.mqh` components when justified.
- Implement the complete agreed specification, not a reduced prototype.
- Use broker and market information for state reconstruction. Do not introduce custom persistence files, Terminal Global Variables, or databases.
- Do not introduce trading rules that depend on incomplete candles.
- Do not claim MetaEditor compilation, terminal execution, or Strategy Tester results unless actually performed.

Create separate KTR documentation and tests.

---

# 1. Trading strategy overview

KTR is an Ichimoku-based trading strategy supporting:

1. Trend-start entries based on forward-projected Kumo changes.
2. First entries based on similarity between Tenkan/Kijun and Senkou Span A peaks or valleys.
3. Additional entries based on five independently enabled signal methods.
4. Independently selectable confirmation filters for first entries and additional entries.
5. Three selectable stop-loss methods.
6. Three selectable risk models for additional positions.
7. Independent BUY and SELL episodes, including simultaneous opposing exposure.
8. Account-wide daily risk monitoring and emergency liquidation.
9. A minimal prop-firm monitoring table.
10. Restart recovery from broker information and market history.

Trading must be supported on **MT5 hedging accounts only**.

The chart symbol and chart timeframe determine the main strategy instrument and timeframe.

Default Ichimoku settings:

- Tenkan: 9
- Kijun: 26
- Senkou Span B: 52
- Displacement: 26 bars

Use these standard settings by default.

Expose the relevant indicator parameters only if this can be done without introducing alignment errors. The standard configuration must be the principal implementation and test reference.

The strategy must support:

```text
TRADE_BUY_ONLY
TRADE_SELL_ONLY
TRADE_BOTH
```

Default: `TRADE_BOTH`.

---

# 2. Projected Kumo trend detector

## 2.1 Trend definition

The trend must be determined exclusively from the **forward-projected Ichimoku cloud calculated using recent completed candles**.

For calculation candle `t`:

```text
Tenkan[t] = midpoint(highest high, lowest low, 9)
Kijun[t]  = midpoint(highest high, lowest low, 26)

SSA[t] = (Tenkan[t] + Kijun[t]) / 2
SSB[t] = midpoint(highest high, lowest low, 52)
```

These are the calculation values displayed 26 candles forward.

Trend:

```text
SSA > SSB => UPWARD
SSA < SSB => DOWNWARD
SSA = SSB => NEUTRAL
```

Do not use price relative to the cloud to identify the trend.

Do not use the cloud currently displayed beneath the price candle as the primary trend reference.

Only completed calculation candles are allowed.

## 2.2 MQL5 indicator alignment

Use `iIchimoku()` and its indicator buffers:

```text
0: Tenkan
1: Kijun
2: Senkou Span A
3: Senkou Span B
4: Chikou
```

Senkou buffers have forward plot displacement.

For a displacement of 26, the most recently completed *calculation* candle corresponds to an offset equivalent to `CopyBuffer(..., -25, ...)`, whereas the forming calculation candle corresponds to the subsequent forward position.

Do not blindly hardcode indexing based on visual chart positions.

Build a verified buffer-access abstraction and compare its outputs against independently calculated Ichimoku values from OHLC history.

Reference documentation:

- https://www.mql5.com/en/docs/indicators/iichimoku
- https://www.mql5.com/en/docs/series/copybuffer
- https://www.mql5.com/en/book/applications/indicators_use/indicators_copybuffer

## 2.3 Trend changes

A trend change occurs when the last completed cloud calculation establishes the opposite direction.

An equality between SSA and SSB is neutral:

- No new trend-start event is generated during equality.
- Do not automatically close positions solely because equality appears.
- Preserve the last confirmed non-neutral direction for detecting the next genuine reversal.
- Suppress new entries during neutral readings unless a separately documented policy explicitly permits them. Default is suppression.

When a confirmed UPWARD-to-DOWNWARD or DOWNWARD-to-UPWARD reversal occurs:

1. Initiate closing **all KTR positions on the managed symbol**, irrespective of their BUY/SELL direction.
2. Reconcile all outstanding closing transactions.
3. End both existing trading episodes.
4. Evaluate a new trend-start entry for the new direction only when the previous positions have been confirmed closed.
5. Apply the selected first-entry configuration and account risk checks.

A reversal detected after an EA restart must still result in closing positions opened before that reversal.

Do not replay arbitrary historical entries after a restart.

On first attachment, an existing trend is not by itself a new trend-start signal.

---

# 3. Trading episodes

## 3.1 Episode architecture

Maintain two independent directional engines:

```text
BUY_ENGINE
SELL_ENGINE
```

There can be:

- At most one BUY episode.
- At most one SELL episode.
- Both episodes active simultaneously.
- Multiple independently stopped positions inside each episode.

A trading episode starts only when its first-entry order receives an actual opening fill.

An episode is **not necessarily associated with a newly started cloud trend**.

Shape-similarity signals can initiate an episode during an already established trend, including a direction opposite to the projected-cloud color.

Example:

```text
Cloud: GREEN

BUY episode: ACTIVE
SELL episode: ACTIVE

Both are permitted.
```

A new episode of the same direction cannot overlap an existing one.

## 3.2 Episode states

Implement:

```text
IDLE
ACTIVE
SUSPENDED
CLOSING
```

`IDLE`:

- No open episode positions.
- A fresh first-entry signal may initiate a new episode.

`ACTIVE`:

- The original first position still exists with positive open volume.
- Additional entries may be opened.

`SUSPENDED`:

- The original first position has fully closed.
- One or more additional positions remain open.
- No new first or additional trades are permitted for that direction.

`CLOSING`:

- A cloud reversal or emergency liquidation has requested closure.
- All further entries are prohibited until reconciliation completes.

When the final position of an ACTIVE or SUSPENDED episode closes, transition to IDLE.

A later first-entry event can then start a new episode.

## 3.3 Original first-position closure

**Regardless of the reason for closure**, when the first position becomes fully closed:

- If additional positions remain, transition to SUSPENDED.
- If no positions remain, transition to IDLE.

Partial closure must not suspend the episode while the original first position still has positive volume.

Do not liquidate remaining additional positions merely because the first position closes.

Signals arriving while an episode is ACTIVE or SUSPENDED cannot create another first entry in that direction.

Do not queue ignored or rejected signals.

## 3.4 Episode ownership

Every opened position must be associated with:

- Direction.
- Episode identifier.
- Entry role: FIRST or ADDITION.
- Entry method.
- Originating signal event.
- Broker position identifier.
- Actual opening execution.

Persist compact recoverable metadata in trade/order comments wherever broker constraints permit.

Also use broker order, deal, and position identifiers. Never rely on comments alone.

---

# 4. First-entry signal configuration

Provide:

```text
FIRST_TREND_START
FIRST_SHAPE_SIMILARITY
FIRST_EITHER
```

Default: `FIRST_EITHER`.

## 4.1 Trend-start entry

Generate a BUY event when the forward-projected cloud changes to green.

Generate a SELL event when the forward-projected cloud changes to red.

The event is confirmed only after the corresponding calculation candle closes.

The new entry is submitted at the first available permitted trading opportunity after confirmation.

If the cloud change has triggered closing existing positions, first complete the required position closures.

An entry event generated on that reversal may remain eligible for that immediate post-closure decision, but must expire if the closing process extends beyond the next main-timeframe signal bar. Do not permit unlimited stale-event replay.

## 4.2 Shape-similarity entry

Compare:

- Tenkan and SSA.
- Kijun and SSA.

Use underlying calculation histories rather than visually displaced SSA coordinates.

Allow configurable lag alignment.

Support four independent pattern switches:

```text
Enable_Tenkan_SSA_Valley = true
Enable_Tenkan_SSA_Peak   = true
Enable_Kijun_SSA_Valley  = true
Enable_Kijun_SSA_Peak    = true
```

Direction mapping:

```text
Matching valley => BUY
Matching peak   => SELL
```

The projected-cloud direction does **not** restrict these first entries.

## 4.3 Shape-similarity detection

Develop a deterministic, testable algorithm based on:

1. Matching local peaks or valleys.
2. Similarity of the local line shapes.
3. Maximum allowed time displacement.
4. Minimum meaningful line movement.
5. Completed-candle confirmation only.

Proposed configurable defaults:

```text
Shape_Window_Bars          = 7
Shape_Max_Lag_Bars         = 2
Shape_Min_Similarity       = 0.90
Shape_Pivot_Left_Bars      = 2
Shape_Pivot_Right_Bars     = 2
Shape_Min_Amplitude_ATR    = 0.05
Shape_Plateau_Tolerance    = configurable
```

Use a normalized first-difference comparison as the initial shape metric:

```text
DX = consecutive changes in line X
DY = consecutive changes in line Y

Similarity = dot(DX, DY) / (norm(DX) * norm(DY))
```

Align comparison windows using the candidate pivot lag.

A qualifying match must have:

```text
Same confirmed extremum type
AND absolute pivot-time lag <= Shape_Max_Lag_Bars
AND Similarity >= Shape_Min_Similarity
AND sufficient non-flat movement
```

Reject degenerate vectors with near-zero norms.

Use ATR-normalized amplitude and/or tolerance where appropriate.

### Plateau-aware peaks and valleys

Tenkan, Kijun, and SSA may remain flat across several candles.

Treat an approximately flat cluster as a single feature:

- Downward movement → plateau → upward movement = valley.
- Upward movement → plateau → downward movement = peak.

Each plateau must produce at most one extremum event.

Do not generate repeated signals for the same plateau.

A signal becomes eligible only after **both matching extrema have been causally confirmed**.

The signal timestamp is the later confirmation timestamp, not the earlier pivot timestamp.

Avoid look-ahead bias.

### Duplicate similarity signals

If Tenkan–SSA and Kijun–SSA detect essentially the same SSA extremum, merge their events into one first-entry candidate per direction.

Retain the detected component names for diagnostics.

One market structure must not generate duplicate first-entry orders merely because both line pairs matched.

---

# 5. Additional-entry signals

Additional entries are available only in an ACTIVE episode.

Provide an independent On/Off switch for every method.

```text
Enable_LowerTF_Entry
Enable_Kijun_Pullback
Enable_Tenkan_Kijun_Cross
Enable_Flat_SSB_Bounce
Enable_Kijun_Rejection
```

Multiple enabled trigger methods use logical OR.

If several methods qualify simultaneously for the same direction and signal bar, open at most one additional position.

Each successful addition has its own broker-side stop loss.

## 5.1 Lower-timeframe entry

Provide an independently selectable lower timeframe.

It must be strictly below the current chart timeframe.

Apply the selected first-entry signal method on the lower timeframe:

```text
FIRST_TREND_START
FIRST_SHAPE_SIMILARITY
FIRST_EITHER
```

If shape similarity is used, perform the corresponding calculation using that timeframe's closed candles.

The lower timeframe determines its own signal timing, while the episode remains associated with the main chart symbol and direction.

Evaluate lower-timeframe signals when their own candles close.

Do not wait for a main-timeframe candle to close unnecessarily.

Use the most recently completed main-timeframe information for main-timeframe confirmation filters.

If no valid lower timeframe exists, disable that entry method with an explanatory warning rather than failing unrelated strategy components.

## 5.2 Kijun pullback

BUY:

- A completed candle touches or crosses Kijun, using a configurable tolerance.
- That candle closes back above Kijun.

SELL:

- Equivalent bearish condition.
- Candle closes back below Kijun.

A touch may be defined using the candle's high/low range, but all measurements must come from a completed candle.

## 5.3 Tenkan–Kijun crossover

BUY:

```text
Previous completed candle: Tenkan <= Kijun
Latest completed candle:   Tenkan > Kijun
```

SELL:

```text
Previous completed candle: Tenkan >= Kijun
Latest completed candle:   Tenkan < Kijun
```

Use no incomplete indicator values.

## 5.4 Flat Senkou Span B bounce

Identify meaningful horizontal SSB support/resistance levels from historical completed indicator calculations.

Starting defaults:

```text
Flat_SSB_Min_Bars          = 5
Flat_SSB_Max_Variation_ATR = 0.05
Flat_SSB_Touch_ATR         = 0.15
Flat_SSB_Max_Age_Bars      = 100
```

A flat region becomes a valid level only after its qualifying duration has completed.

For BUY:

- Price tests a previously identified flat SSB support level.
- The signal candle closes back above the level.

For SELL:

- Price tests a previously identified flat SSB resistance level.
- The signal candle closes back below the level.

Use only levels that were known at the decision time.

Do not infer a support/resistance level using future data.

Level aging, deduplication, and invalidation must be deterministic.

## 5.5 Kijun rejection

Use a stronger reaction than the basic Kijun pullback.

BUY:

- Kijun touched within tolerance.
- Bullish directional candle body.
- Significant lower rejection wick.
- Candle closes on the bullish side of Kijun.

SELL:

- Symmetric bearish conditions.
- Significant upper rejection wick.

Starting input:

```text
Kijun_Rejection_Min_WickBody = 1.5
```

Handle zero or near-zero body sizes safely.

The Kijun pullback and Kijun rejection methods must remain separate.

If both trigger on the same bar, open only one additional position.

## 5.6 Additional-entry cooldown

Provide a configurable cooldown:

```text
Additional_Entry_Cooldown_Main_Bars = 1
```

Use it to prevent repeated additions in a short interval.

The cooldown must be based on completed main-timeframe bars, not arbitrary elapsed wall-clock time.

For simultaneous events, use a reproducible deduplication and priority procedure.

A new episode must not receive an additional trade from the same first-entry event that created it.

---

# 6. Independent confirmation filters

**First entries and additional entries must have separate sets of On/Off confirmation inputs.**

Implement the following independently for both categories:

| Confirmation | First entry input | Additional entry input |
|---|---|---|
| Price relative to Kumo | On/Off | On/Off |
| Tenkan–Kijun alignment | On/Off | On/Off |
| Flat SSB support/resistance | On/Off | On/Off |
| Swing support/resistance | On/Off | On/Off |
| Cloud thickness | On/Off | On/Off |
| Higher-timeframe Kumo agreement | On/Off | On/Off |
| Chikou clearance | On/Off | On/Off |

All confirmation filters should default to OFF.

The first benchmark must therefore reproduce the raw trigger logic without optional confirmations.

Rules:

```text
Entry triggers: OR
Enabled confirmation filters: AND
All confirmation filters OFF: no confirmation restrictions
```

A confirmation is never an independent entry trigger.

## 6.1 Price relative to Kumo

This is an optional entry confirmation only.

Do not let it affect the primary projected-cloud trend definition.

For this confirmation, use the cloud displayed at the latest completed candle's actual time, not the future-projected cloud values.

BUY:

```text
Closed price above current displayed cloud
```

SELL:

```text
Closed price below current displayed cloud
```

## 6.2 Tenkan–Kijun alignment

BUY requires Tenkan above Kijun.

SELL requires Tenkan below Kijun.

## 6.3 Flat SSB support/resistance

Confirm that the proposed trade direction is supported by a previously confirmed flat SSB level with a meaningful price interaction.

Keep this confirmation distinct from the flat SSB bounce entry trigger.

## 6.4 Swing support/resistance

Construct support/resistance levels from confirmed historical price swings.

Starting defaults:

```text
SR_Min_Touches          = 2
SR_Min_Touch_Separation = 3 candles
SR_Tolerance_ATR        = configurable
SR_Lookback_Bars        = configurable
```

BUY confirmation requires valid support interaction.

SELL confirmation requires valid resistance interaction.

Avoid future-dependent clustering or retrospective labeling.

## 6.5 Cloud thickness

Use projected-cloud thickness:

```text
Thickness = abs(SSA - SSB)
```

Normalize by ATR where applicable.

Provide a minimum thickness threshold.

For example:

```text
Cloud_Min_Thickness_ATR = configurable
```

An enabled filter rejects entries when thickness is below the threshold.

## 6.6 Higher-timeframe Kumo agreement

Provide a selectable higher timeframe, strictly above the chart timeframe.

Evaluate its projected-cloud direction from its last completed calculation candle.

BUY requires upward higher-timeframe cloud direction.

SELL requires downward higher-timeframe cloud direction.

## 6.7 Chikou clearance

Implement a causal Chikou clearance test.

Compare the most recently completed close against price structure 26 bars earlier—the region where that close would be displayed as Chikou.

BUY requires bullish clearance above the relevant historical structure.

SELL requires bearish clearance below the relevant historical structure.

Provide a configurable clearance margin.

Do not introduce future-bar references by visually aligning Chikou.

---

# 7. Stop-loss methods

Provide:

```text
SL_FRACTAL
SL_ZIGZAG
SL_FIXED_DISTANCE
```

Every trade must have an actual broker-side SL.

Do not substitute a different method silently if the selected method cannot produce a valid level.

## 7.1 Fractal method

Use standard fractals on the current chart timeframe.

BUY:

- Find the most recent eligible confirmed lower fractal.
- Fractal must be at least `Fractal_Min_Distance_ATR * ATR` below proposed entry.
- Place SL an additional configurable buffer below the fractal.

SELL:

- Find the most recent eligible confirmed upper fractal.
- Require the same ATR-normalized minimum distance.
- Place SL a buffer above the fractal.

Inputs:

```text
Fractal_Min_Distance_ATR = configurable
Fractal_SL_Buffer_Ticks   = configurable
ATR_Period                = 14
ATR_Timeframe             = selectable
```

Only confirmed fractals may be used.

## 7.2 ZigZag method

Use ZigZag-style major peak and valley identification on the chart timeframe.

Inputs:

```text
ZigZag_Depth     = 12
ZigZag_Deviation = 5
ZigZag_Backstep  = 3
ZigZag_SL_Buffer_Ticks = configurable
```

Implement or wrap a **causal ZigZag swing-confirmation mechanism**.

Critical requirements:

- The currently developing ZigZag leg can change.
- A provisional high or low is not a confirmed swing.
- Record both pivot time and confirmation time.
- Once a swing becomes eligible for trade decisions, do not retroactively modify its historical confirmation status.
- Historical tests must replay the swing detector chronologically.

The implementation must preserve the intended Depth/Deviation/Backstep semantics and document any deliberate difference from the final visual output of the standard ZigZag indicator.

BUY uses the most recent eligible confirmed major valley below entry.

SELL uses the most recent eligible confirmed major peak above entry.

Apply the SL buffer beyond the swing.

## 7.3 Fixed-distance method

Provide configurable fixed stop distance in ticks.

The exact distance must be converted using the symbol's trading specifications.

Do not assume that a pip has the same meaning across FX, metals, indices, and other instruments.

## 7.4 Stop validation

Before every entry:

- Verify that SL is on the protective side of the proposed opening price.
- Respect `SYMBOL_TRADE_TICK_SIZE`.
- Respect broker stop-distance and freeze-level restrictions.
- Check spread and permissible SL adjustment.
- Validate volume and margin.
- Reject trades whose valid SL cannot be placed.

Do not increase actual risk beyond the requested risk budget merely to satisfy broker restrictions.

No take-profit target is required in v1.0.

Normal exits are broker SL, an externally initiated full close, or global projected-cloud reversal.

---

# 8. Position sizing

## 8.1 First entry

Default risk:

```text
First_Entry_Risk_Percent = 2.0
```

Risk is calculated from current account equity.

```text
RiskMoney = CurrentEquity * 0.02
```

The real order volume is calculated from proposed entry and SL prices.

Use `OrderCalcProfit()` and the account currency rather than assuming a fixed pip value.

Round volume down to the broker's permitted volume step.

Never round up to the broker minimum if this exceeds the risk budget.

If the computed volume is below minimum, skip the trade.

## 8.2 Additional-entry risk options

Provide:

```text
ADD_RISK_SAME
ADD_RISK_FIXED_REDUCTION
ADD_RISK_TREND_END_PROBABILITY
```

### A. Same risk

Each addition uses the configured first-entry risk percentage of current equity before the shared daily cap.

### B. Fixed reduction

Reduce additional-entry risk geometrically.

For addition number `n`, where the original first entry has index 1:

```text
RiskPercent(n) = BaseRiskPercent * (1 - ReductionFraction)^(n - 1)
```

Provide a configurable percentage reduction input.

Suggested starting value:

```text
Additional_Risk_Reduction_Percent = 20
```

### C. Trend-end probability

Estimate the probability that the current projected-cloud trend ends within the next `H` completed main-timeframe candles.

Define trend duration `T` from confirmed projected-cloud transitions.

Current trend age: `a`.

Estimate:

```text
P_end(a,H) =
  count(completed past trends where a < T <= a+H)
  /
  count(completed past trends where T > a)
```

Use only trends that had fully completed before the historical trade decision.

Proposed defaults:

```text
Trend_End_Horizon_Bars = 10
Trend_End_Min_Samples  = 50
Trend_End_History_Bars = configurable
```

Additional risk:

```text
RiskPercent = BaseRiskPercent * (1 - P_end)
```

Bound the probability to [0,1].

Bound the resulting risk to [0, BaseRiskPercent].

When there are insufficient eligible observations, fall back to the fixed-reduction method and report this in diagnostics.

Trend age is based on the global projected-cloud trend, regardless of BUY or SELL episode direction, because a cloud reversal closes both directions.

Avoid assumptions that trend-ending probability must increase with trend age.

Implement a deterministic, no-look-ahead historical estimator. No machine-learning dependency is required.

---

# 9. Account-wide maximum daily risk

Default:

```text
Max_Daily_Risk_Percent = 5.0
```

At the start of every broker-server calendar day, define:

```text
B_day = account balance at the daily reset
```

For the current account equity `E` and estimated additional remaining stop losses:

```text
L_open = estimated additional losses if currently open positions
         move from their present market values to their stop prices

L_new = proposed new trade's estimated loss from entry to SL
```

Then:

```text
ProjectedWorstEquity = E - L_open - L_new

ProjectedDailyRiskPercent =
    max(0, B_day - ProjectedWorstEquity) / B_day * 100
```

A trade is allowed only if its projected daily risk is at or below 5%, in addition to all other checks.

Account-wide risk must include all current positions.

For opposite BUY/SELL positions, use a conservative individual-stop exposure estimate. Do not presume perfect offsetting.

Include reasonable commissions and account-currency conversions where the broker exposes the required information.

When existing exposure has an unknown or missing SL, do not underestimate the account's risk. Block additional orders until the exposure can be assessed safely.

## 9.1 Two simultaneous first-entry signals

If a BUY and SELL first-entry signal occur at the same decision time:

1. Calculate both proposed orders and their stops.
2. Assess their combined risk and margin requirements.
3. If both qualify jointly, attempt both.
4. If both cannot jointly qualify, **reject both**.
5. Do not prioritize either direction.
6. Do not queue rejected signals.

MT5 cannot guarantee atomic submission of separate market orders.

Handle partial execution honestly: reconcile actual fills, retain accurate risk accounting, prevent duplicates, and log if only one of the attempted orders executed. Do not falsely report an all-or-none transaction.

## 9.2 Hard daily loss limit

Independently monitor:

```text
CurrentEquity <= B_day * (1 - Max_Daily_Risk_Percent/100)
```

When the threshold is reached:

1. Initiate closing all account positions, since this is a dedicated EA account.
2. Continue safe closing/reconciliation attempts if any position remains.
3. Disable all new trading.
4. Maintain the lock until the next broker-server midnight.
5. On the next day, reconstruct the new daily opening balance and reevaluate eligibility.

This hard equity protection is an explicit exception to closed-candle signal rules.

It must be checked on live market/account updates and also on a timer so that monitoring is not dependent solely on ticks from the chart symbol.

A proposed order exceeding risk capacity must be rejected without liquidating existing positions. Liquidation occurs when the **actual equity threshold** is reached or breached.

Do not assume broker execution guarantees a strict maximum 5% loss.

---

# 10. Normal exits and position ownership

Cloud-change exits use completed main-timeframe calculations only.

When projected-cloud color reverses, terminate both directional episodes by closing all KTR positions on the managed symbol.

Emergency account-level risk liquidation closes all account positions.

Do not accidentally close unrelated positions merely because they share a symbol when performing ordinary strategy exits.

Use a dedicated Magic Number and broker position identifiers.

Support partial fills, partial closes, asynchronous trade transactions, execution failures, and disconnections.

`OnTradeTransaction()` must trigger reconciliation, but should not assume that trade transaction callbacks arrive in a guaranteed sequence.

Use actual broker state as the source of truth.

---

# 11. Restart and state reconstruction

The EA must continue correctly after:

- MT5 restart.
- EA removal and reattachment.
- Chart refresh or timeframe change.
- Temporary terminal disconnection.
- Temporary missing indicator history.

**No custom persistence files, Terminal Global Variables, SQLite, or external databases.**

Use:

1. Current positions.
2. Account/order/deal history.
3. Position identifiers.
4. Compact trade comments.
5. Historical OHLC/indicator calculations.
6. Broker-server timestamps.

Order comments should identify episode and entry role using compact strings, within broker limits.

Suggested logical metadata:

```text
KTR | version | episode-id | FIRST/ADD | method
```

Implement safe truncation and recoverability.

The broker may change order comments, so use stable order and position identifiers and deal history wherever possible.

At restart:

1. Validate account type and inputs.
2. Load sufficient chart history.
3. Reconstruct the current projected-cloud state.
4. Reconstruct active BUY and SELL episodes from positions and deals.
5. Identify each episode's original first position.
6. Determine whether the first position still has positive remaining volume.
7. Restore ACTIVE or SUSPENDED status accordingly.
8. Detect any cloud reversals occurring while the EA was offline.
9. Perform mandatory closure if needed.
10. Reconstruct trade event IDs to avoid duplicate entries.
11. Resume only newly confirmed eligible signals.

If episode ownership cannot be reconstructed safely, block new entries for the affected direction rather than inventing an IDLE state.

Continue account-risk monitoring independently.

Do not replay old first-entry signals merely because they occurred during downtime.

---

# 12. Prop-firm monitoring panel

Create a minimal, readable table on the chart.

**The panel is strictly for account-performance monitoring. Do not add strategy signals, RSI values, Ichimoku values, or entry indicators to this table.**

Display these four metrics:

```text
Today's P&L
Maximum Daily Drawdown
Total P&L
Maximum Overall Drawdown
```

Show monetary values and percentages where meaningful.

## 12.1 Today's P&L

```text
Today's P&L = Current Equity - Balance at start of day
```

Daily percent:

```text
Today's P&L % = Today's P&L / OpeningDailyBalance * 100
```

## 12.2 Maximum daily drawdown

```text
DailyDD = max(0, OpeningDailyBalance - MinimumDailyEquity)
```

```text
DailyDDPercent = DailyDD / OpeningDailyBalance * 100
```

Equity minima are measured relative to the day's opening balance, not the highest equity reached that day.

## 12.3 Total P&L

```text
TotalP&L = CurrentEquity - InitialDepositedBalance
```

Account cash-flow adjustments must be handled explicitly if later deposits or withdrawals exist. Do not count external cash flows as trading profit.

Prefer reconstructing the initial deposit from broker history. When incomplete broker history prevents this, display an unavailable/estimated status rather than fabricating a baseline. An optional user-entered initial-deposit override may be provided and clearly labeled.

## 12.4 Maximum overall drawdown

```text
OverallDD = max(0, InitialDepositedBalance - MinimumHistoricalEquity)
```

```text
OverallDDPercent =
    OverallDD / InitialDepositedBalance * 100
```

This is an **initial-balance-relative historical drawdown**, not conventional peak-to-trough drawdown.

## 12.5 Daily reset

Use broker-server date and midnight.

Account for server timezone and daylight-saving transitions without assuming a fixed UTC offset.

On the first available event after midnight, reconstruct the balance at the calendar day's start.

Do not use the current balance in place of an unknown historical opening balance.

## 12.6 Historical equity reconstruction

Do not use locally persisted historical equity snapshots.

Reconstruct historical extrema on a best-effort basis using:

- Broker deal history.
- Position opening and closing events.
- Historical tick data using `CopyTicksRange()`.
- Symbol-level bid/ask information.
- Available broker commission, swap, and conversion information.

Reconstruct exposure chronologically, including positions carried across midnight.

Tick data does not directly contain historical account equity, so full exact reconstruction may be impossible.

Implement completeness checks.

If the historical minimum is uncertain:

- Display the reconstructed value as **Estimated**.
- Show a small completeness warning associated with the panel.
- Do not present estimates as exact.
- Continue trading based on current account equity and available history, as selected.

Use chunked, bounded historical processing to avoid freezing MT5 or allocating unlimited memory.

During the current live session, track observed equity minima in memory and combine them with any reconstructed history.

After restart, recompute from accessible broker/market history.

No claim of exact reconstruction is permitted if missing historical ticks or account conversion data could change the result.

---

# 13. Runtime architecture and performance

Organize the EA into clear modules or components:

```text
KTR Main EA
├── Ichimoku / Projected Trend
├── Shape Similarity
├── First Entry Signals
├── Additional Entry Signals
├── Confirmation Filters
├── Fractal / ZigZag / Fixed SL
├── Position Sizing
├── Trend-End Probability
├── Episode State Manager
├── Trade Execution / Reconciliation
├── Daily Risk Manager
├── Historical Equity Reconstruction
└── Prop-Firm Monitor
```

Use a simpler structure if justified, but maintain these logical separations.

Recommended execution architecture:

**OnInit**
- Validate inputs and hedging mode.
- Initialize indicator handles.
- Recover episodes and broker state.
- Initialize account-risk tracking.
- Reconstruct available historical monitoring metrics.
- Register timer.

**OnTick**
- Check emergency risk limit.
- Reconcile positions and pending requests.
- Process newly closed candles.
- Evaluate eligible signals.
- Execute orders only after risk validation.

**OnTimer**
- Update account monitoring.
- Check hard equity loss.
- Reconcile outstanding closures.
- Refresh panel.
- Process bounded historical reconstruction work.

**OnTradeTransaction**
- Mark broker state as requiring reconciliation.
- Associate deals with positions and episode metadata.
- Detect full/partial closes accurately.
- Avoid duplicate transaction handling.

**OnDeinit**
- Release indicator handles and timer.
- Remove only KTR-owned chart objects.
- Do not automatically close positions unless a separate explicit strategy rule requires it.

Make indicator and historical calculations incremental wherever possible.

Do not rescan the entire chart on every market tick.

Avoid repeated large `CopyTicksRange()` requests.

Use one KTR strategy instance per dedicated account for v1.0. Document that simultaneous installations on multiple charts would require an additional account-wide coordination mechanism that is outside this specification.

---

# 14. Input organization

Provide clearly grouped MT5 input parameters.

Suggested groups:

### General

```text
Trade_Direction
Magic_Number
Enable_Trading
Max_Slippage_Points
```

### Ichimoku / Trend

```text
Tenkan_Period = 9
Kijun_Period = 26
SenkouB_Period = 52
```

### First Entry

```text
First_Entry_Method = FIRST_EITHER

Enable_Tenkan_SSA_Valley = true
Enable_Tenkan_SSA_Peak = true
Enable_Kijun_SSA_Valley = true
Enable_Kijun_SSA_Peak = true

Shape_Window_Bars = 7
Shape_Max_Lag_Bars = 2
Shape_Min_Similarity = 0.90
Shape_Pivot_Left_Bars = 2
Shape_Pivot_Right_Bars = 2
Shape_Min_Amplitude_ATR = 0.05
Shape_Plateau_Tolerance
```

### Additional Entry

```text
Enable_LowerTF_Entry
Lower_Entry_Timeframe

Enable_Kijun_Pullback
Enable_Tenkan_Kijun_Cross
Enable_Flat_SSB_Bounce
Enable_Kijun_Rejection

Additional_Entry_Cooldown_Main_Bars = 1
Kijun_Rejection_Min_WickBody = 1.5
```

### First-Entry Confirmations

Separate boolean input for each of the seven confirmation filters.

### Additional-Entry Confirmations

Another, completely independent set of seven boolean inputs.

### Support and Resistance

```text
Flat_SSB_Min_Bars = 5
Flat_SSB_Max_Variation_ATR = 0.05
Flat_SSB_Touch_ATR = 0.15
Flat_SSB_Max_Age_Bars = 100

SR_Min_Touches = 2
SR_Min_Touch_Separation = 3
SR_Lookback_Bars
SR_Tolerance_ATR
```

### Stop Loss

```text
SL_Method

Fractal_Min_Distance_ATR
Fractal_SL_Buffer_Ticks

ZigZag_Depth = 12
ZigZag_Deviation = 5
ZigZag_Backstep = 3
ZigZag_SL_Buffer_Ticks

Fixed_SL_Distance_Ticks

ATR_Period = 14
ATR_Timeframe
```

### Risk

```text
First_Entry_Risk_Percent = 2.0
Max_Daily_Risk_Percent = 5.0

Additional_Risk_Method
Additional_Risk_Reduction_Percent = 20

Trend_End_Horizon_Bars = 10
Trend_End_Min_Samples = 50
Trend_End_History_Bars
```

### Monitoring

```text
Show_Prop_Monitor = true
Monitor_Corner
Monitor_X
Monitor_Y
Monitor_Font_Size
Monitor_Color_Settings
Initial_Deposit_Override
```

Include additional settings only when necessary for clearly defined behavior.

All numeric inputs must be validated, including timeframe ordering and percentage ranges.

---

# 15. Testing and acceptance criteria

Create automated testable functions and a separate KTR test plan.

Preserve all existing RSI Pull Up tests.

At minimum cover the following scenarios.

## A. Ichimoku calculations

1. Projected SSA matches independently calculated values.
2. Projected SSB matches independently calculated values.
3. `CopyBuffer()` displacement is verified.
4. The current forming candle never influences trading signals.
5. Green/red cloud transitions are detected at the correct completed candle.
6. Equality does not create spurious trend transitions.
7. Changing chart timeframe resets signal scheduling safely.

## B. Shape similarity

8. Matching confirmed valleys generate one BUY signal.
9. Matching confirmed peaks generate one SELL signal.
10. Correctly aligned patterns pass the similarity threshold.
11. Excessive lag rejects the pattern.
12. Low similarity rejects the pattern.
13. Flat or degenerate sequences cannot produce false scores.
14. Plateaus produce one extremum, not repeated extrema.
15. Confirmation timestamps are correctly delayed.
16. No historical look-ahead or future-bar references.
17. Duplicate matches on the same SSA extremum merge.
18. Opposite-direction first entries are possible regardless of cloud color.

## C. Trading episodes

19. One BUY and one SELL episode can coexist.
20. Two BUY episodes cannot coexist.
21. Two SELL episodes cannot coexist.
22. First position closure with remaining additions causes SUSPENDED.
23. Partial first-position closure does not cause SUSPENDED.
24. Suspended episodes reject all entry signals.
25. After the final episode position closes, state becomes IDLE.
26. Starting another episode requires a genuinely fresh first-entry signal.
27. A cloud reversal closes both directions.
28. Existing broker positions reconstruct correct episode states after restart.

## D. Additional entries

29. Each of the five methods independently triggers the intended direction.
30. Multiple methods on the same event cannot create duplicates.
31. Lower-timeframe signals use completed candles.
32. Kijun pullback and Kijun rejection are distinguishable.
33. Flat SSB levels are identified before they are used.
34. Cooldown works across multi-timeframe signals.
35. Additional entries are rejected when the episode is not ACTIVE.

## E. Confirmation filters

36. First-entry and additional-entry filters are independent.
37. Enabled confirmations use logical AND.
38. Enabled entry methods use logical OR.
39. All confirmations OFF leaves raw signals unchanged.
40. Higher-timeframe and Chikou checks use historical information causally.
41. Price-relative-to-Kumo confirmation does not change trend identification.

## F. Stop losses and volume

42. Confirmed fractal distance rule works for BUY and SELL.
43. Fractal SL buffer is applied outside the fractal.
44. ZigZag developing swings are never treated as confirmed pivots.
45. ZigZag confirmed-pivot timing is causal.
46. Fixed-distance SL respects tick size.
47. Broker stop restrictions are handled safely.
48. `OrderCalcProfit()`-based lot sizing respects requested account-currency risk.
49. Rounding never increases risk.
50. Invalid stop or insufficient minimum volume prevents entry.

## G. Risk management

51. Initial risk defaults to 2%.
52. Additional-entry risk models work independently.
53. Statistical trend-end estimation excludes future data.
54. Insufficient historical observations trigger documented fallback.
55. Projected daily risk includes existing positions and proposed positions.
56. Opposite BUY/SELL exposure is evaluated conservatively.
57. Simultaneous first-entry signals are both rejected if combined risk is insufficient.
58. Hard 5% daily equity loss initiates liquidation immediately.
59. No new positions are opened while liquidation remains unresolved.
60. Trading remains locked until the next daily reset.
61. Daily reset uses broker-server calendar boundaries.

## H. Restart and monitoring

62. Restart with no positions does not replay old entries.
63. Restart with an ACTIVE episode restores ownership and position roles.
64. Restart with a SUSPENDED episode does not reactivate it.
65. Broker SL or manual closure of the first position is reconstructed correctly.
66. Incomplete episode ownership does not create duplicate orders.
67. Daily opening balance is reconstructed where broker history permits.
68. Current equity P&L uses the specified daily and initial baselines.
69. Historical minimum equity calculations report their completeness accurately.
70. Missing tick history cannot silently produce falsely exact drawdown.
71. Monitoring remains display-only.
72. Existing RSI Pull Up behavior and tests remain unchanged.

---

# 16. Strategy Tester evaluation

Provide a practical MT5 Strategy Tester procedure.

Use identical market history, account settings, spreads, and execution assumptions across comparisons.

Prefer real-tick testing when available, particularly for emergency equity liquidation and order execution.

Run controlled comparisons for:

### First-entry methods

- Trend Start only.
- Shape Similarity only.
- Either.

### Shape patterns

- Tenkan–SSA valleys/peaks.
- Kijun–SSA valleys/peaks.
- Both together.

### Additional entries

- First entry only.
- Each additional-entry method individually.
- All enabled methods.

### Confirmation filters

- All disabled.
- Each filter individually.
- Selected combinations.

### Stop-loss methods

- Fractal.
- ZigZag.
- Fixed distance.

### Risk models

- Same risk.
- Fixed reduction.
- Trend-end probability.

Measure at least:

- Number of trades.
- Number of episodes.
- Win rate.
- Net profit.
- Average profit/loss per trade.
- Profit factor.
- Maximum equity drawdown.
- Maximum daily loss.
- Trade expectancy.
- Exposure duration.
- First-entry versus additional-entry contribution.
- BUY versus SELL performance.
- Results from countertrend shape-similarity entries.

Use chronological in-sample and out-of-sample separation.

Do not select default parameters solely by optimizing one historical sample.

Preserve deterministic signal behavior so differences between tests can be attributed to the changed strategy component.

---

# 17. Deliverables

Create:

1. `Kumo_Trend_Rider.mq5`
2. Appropriate supporting `.mqh` modules, if justified.
3. `KTR_README.md` — full strategy description, inputs, episode lifecycle, chart and risk semantics.
4. `KTR_TEST_PLAN.md` — functional and Strategy Tester cases.
5. Separate KTR self-tests or test utilities, where feasible.

Existing RSI Pull Up files must remain intact.

Document any important MT5-specific limitations, especially:

- Non-atomic simultaneous order placement.
- Hedging-account requirement.
- Broker order-comment restrictions.
- ZigZag repainting and causal confirmation.
- Indicator buffer displacement.
- Historical account-equity reconstruction uncertainty.
- Inability to guarantee the 5% loss threshold under gaps and slippage.
- Runtime limitations of a single EA managing an account-wide emergency policy.

## Completion report

When implementation is complete, report:

1. Files created or modified.
2. Overview of the architecture.
3. How every signal method was implemented.
4. How position and episode ownership is recovered.
5. How the 5% emergency risk limit operates.
6. What assumptions, if any, were required.
7. Results of automated tests actually executed.
8. Actual MetaEditor compilation result, if available.
9. Strategy Tester results, if actually executed.
10. Outstanding limitations or known issues.

Clearly distinguish:

```text
IMPLEMENTED
TESTED
NOT TESTED
KNOWN LIMITATION
```

Do not claim successful compilation merely because the source code was written.

Do not claim live or backtest profitability.

**Primary priorities:** correct projected-cloud timing, no look-ahead bias, rigorous episode-state recovery, independent BUY/SELL management, safe broker-side stop losses, and accurate account-level risk enforcement.

Implement the full KTR v1.0 specification while preserving the existing RSI Pull Up EA.
