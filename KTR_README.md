# Kumo Trend Rider v1.0

**IMPLEMENTED — source implementation.** **TESTED — 84 portable assertions on production calculation/recovery bodies, plus source preservation checks.** **NOT TESTED — MetaEditor compilation, native scripts, broker execution, Strategy Tester, visual rendering or profitability.** See [test evidence](tests/ktr/results/portable.txt) and [acceptance plan](KTR_TEST_PLAN.md). This is an independent EA; existing RSI Pull Up sources and documentation are unchanged.

## Installation and scope

Copy `Kumo_Trend_Rider.mq5` and the entire `Include/KTR/` directory into the same Experts project folder as RSI Pull Up. Compile the new main file in MetaEditor. Do not attach to a live account before performing the native and broker tests below. No EX5 binary is supplied because no MT5 compiler is installed in the implementation environment.

Use **one KTR instance on one dedicated MT5 hedging account**. Chart symbol and timeframe select the strategy market. Netting/exchange account modes are rejected. Ordinary reversals close only positions with the configured magic on the chart symbol; the emergency policy closes **every account position and cancels every account pending order**, including manual/other-EA exposure. Removal/reinitialization itself does not close trades. No terminal globals, custom persistence files, databases or external dependencies are used by KTR.

The approved task is retained in [KTR_SPEC.md](KTR_SPEC.md). Configuration choices not assigned a default there are listed as assumptions below.

## Architecture

| File | Responsibility |
| --- | --- |
| `Kumo_Trend_Rider.mq5` | Account/input validation, closed-bar scheduling, startup, reversal closure barrier, event handlers |
| `Include/KTR/Core.mqh` | Pure cosine/plateau/trigger, risk, state and incremental causal swing calculations |
| `Include/KTR/Inputs.mqh` | Grouped inputs; first and additional confirmations have separate switches |
| `Include/KTR/Market.mqh` | Ichimoku handles/alignment, first signals, five additional methods, seven filters, causal levels, shape deduplication |
| `Include/KTR/Recovery.mqh` | Compact metadata and deterministic broker-snapshot episode reconstruction |
| `Include/KTR/Broker.mqh` | Order/deal/position associations, request reconciliation/cancellation, ticket-specific closures |
| `Include/KTR/Account.mqh` | Broker-server day baseline, all-account exposure, emergency latch, bounded historical samples, four-metric panel |
| `Include/KTR/Execution.mqh` | Three SL methods, three risk models, conservative sizing, joint preflight and market submission |

OnTick checks account protection, reconciles broker snapshots and processes newly closed bars. Lower-timeframe events follow their own closes, using the most recently completed main-timeframe filters and chart-timeframe stops. OnTimer independently checks emergency risk, retries unresolved closures, draws the monitor and performs bounded historical work. Trade callbacks mark history dirty and immediately check current equity; state does not depend on callback order. Timer and indicator handles are released on removal, and only chart objects with this instance's KTR prefix are deleted.

## Cloud timing and first entries

The principal configuration is fixed at **9/26/52 with 26-bar displacement**, avoiding mismatched parameter/plot shifts. For calculation shift `s >= 1`, Senkou access starts at `s - 26`; the latest closed calculation is `CopyBuffer(..., -25, ...)`. Tenkan, Kijun, SSA and SSB on the last eight closed calculation bars are compared to an independent OHLC midpoint calculation on every load. Missing, partial or inconsistent buffers block entries. The forming calculation candle is never copied into signal history.

Projected SSA > SSB means upward, SSA < SSB downward. Neutral preserves the most recent non-neutral direction but suppresses all entries. Price/cloud confirmation uses SSA/SSB **26 calculation bars earlier**, representing the cloud actually displayed at the completed candle. It never changes trend identification.

First entry can be Trend Start, Shape Similarity or Either. First attachment only seeds history and waits for new events. An opposite non-neutral projected cloud closes both existing directional episodes; no position is closed just because the cloud becomes equal. An immediate post-closure trend-start candidate is retained only while the main signal bar remains current. Offline reversals are checked against the original first execution, including intervening reversals that subsequently reversed back. Insufficient reversal history blocks additions to the affected episode.

Shape similarity pairs Tenkan/SSA and Kijun/SSA independently. Valleys buy and peaks sell regardless of projected color. Approximate plateaus are single extrema, with their last bar as the canonical pivot. Left and right neighborhoods must be beyond the plateau tolerance. Confirmation occurs only when all right bars of **both** extrema have closed. Windows end at each extremum's own confirmation and are aligned using pivot lag; normalized first differences supply cosine similarity, and both line ranges must exceed the configured ATR amplitude. Zero-norm windows are rejected.

Plateau membership uses a **fixed fraction of trading tick size**, rather than a changing ATR, so ATR changes cannot retrospectively relabel flat clusters. Amplitude uses the closed ATR of the signal timeframe. This is a deliberate concrete interpretation of the specification's configurable plateau tolerance. The event is the SSA extremum timestamp; eligibility time is the later confirmation. Tenkan/Kijun matches merge their method bits before the SSA structure is consumed, even if risk/confirmations/state reject it. Startup seeds already matched structures to avoid retrying an old plateau when its second line pair confirms later.

## Additional methods and filters

All additional methods default OFF for a first-entry-only benchmark. Their triggers are OR-ed; a merged bit mask retains the components. Main-timeframe methods take precedence over a coincident lower-timeframe event for each direction. One position per direction/decision is considered, and the completed-main-bar cooldown spans all methods. A new episode cannot receive an addition on its creating main bar, even when cooldown is zero. Rejected/ignored events are consumed; there is no queue.

| Method | Closed-candle implementation |
| --- | --- |
| Lower timeframe | Selected first-entry method with its own cloud/shape history; must be strictly below chart TF, otherwise only this method is disabled with a warning |
| Kijun pullback | Candle range touches Kijun within ATR tolerance and closes strictly on the proposed side |
| Tenkan/Kijun cross | Previous T <= K and latest T > K for BUY, symmetric SELL |
| Flat SSB bounce | Historical flat calculation region has already qualified; level is tested and price closes on its supported side |
| Kijun rejection | Pullback plus directional nonzero body and directional rejection wick/body ratio |

Flat regions are maximal tolerance-bounded runs. A level is fixed from the first qualifying bars and classified by price at qualification. Its age is measured from qualification; a decisive close through the unsupported side invalidates it. Runs are not emitted as overlapping repeated levels. Flat confirmation additionally requires the previous candle to approach from the supported side, keeping it distinct from the bounce trigger.

Swing SR uses strict two-left/two-right price pivots confirmed **before** the signal candle. Fixed-anchor price clusters require separated confirmed touches. A decisive close through the anchor tolerance invalidates that cluster. It is never clustered using future pivots.

Each category has its own seven independent filters, all default OFF, combined with AND:

1. Closed price strictly outside the cloud displayed at its actual time.
2. Tenkan/Kijun directional alignment.
3. Previously qualified flat-SSB interaction and supported approach.
4. Confirmed multi-touch swing SR interaction.
5. Projected thickness divided by closed main ATR meets minimum.
6. Most recently completed projected cloud on a strictly higher timeframe agrees.
7. Closed price clears the high (BUY) or low (SELL) 26 bars earlier, plus ATR margin.

## Episodes, ownership and restart

BUY and SELL each have at most one episode. An actual opening deal starts an episode, never a submitted request. Its original broker position identifier controls ACTIVE versus SUSPENDED; positive partial volume remains ACTIVE. When that identifier disappears while additions remain, state is SUSPENDED irrespective of SL/manual/external closure reason. Remaining additions keep their own stops. Final closure yields IDLE, requiring a fresh signal. CLOSING excludes all entries until positions and outstanding orders reconcile.

Comments use `K1|episode|F/A|method-mask|event|timeframe-seconds`, with base-36 numeric fields, normally under 31 characters. Overlength/invalid metadata is rejected rather than silently truncated. Direction comes from opening execution. Records connect opening deals to stable `DEAL_POSITION_ID`, originating order ticket, first/last execution time and volume-weighted actual execution price. Deal comments are preferred, with original order comments as fallback. Partial fills for the same position aggregate into one record. Entry counts include previously closed additions, preserving geometric risk reduction on restart.

Current live position identifiers determine what remains open. Opening history identifies the original first position even after it has closed. Multiple same-direction episode identities, missing original history or malformed ownership metadata block that direction. Broker comments alone are insufficient: position/order/deal identifiers are always linked. If the broker strips **both** deal and order metadata and no safe association can be established, the EA blocks rather than guessing.

History/position snapshots, not callback ordering, reconcile execution. Entry filling is FOK when available, then IOC; symbols requiring RETURN-only new entries are skipped. Remaining live KTR orders are canceled on reconciliation, including after restart, and block entries until broker resolution. An uncertain request without terminal broker evidence remains blocked in memory; there is no timeout-based resubmission. A second entry request is never sent merely because a local timeout elapsed. Single-instance operation is a documented account requirement, not a distributed lock.

## Stops, sizing and risk

Every submitted entry includes broker SL and no TP. The chosen stop method never silently falls back:

- **Fractal:** native chart-timeframe lower/upper buffer, only shift 3 or older (two fully completed right bars). Scan newest eligible pivot at least the configured independent closed-ATR distance from entry, then add tick buffer.
- **ZigZag:** chart-timeframe rolling Depth high/low candidate; Backstep completed bars of candidate stability and Deviation broker points of reversal confirm it. Candidate extremes can move; confirmed pivot/confirmation timestamps are frozen. Live processing advances incrementally with a Depth-sized ring. Restart replays chronologically. A historical pivot is never used before confirmation. The latest eligible confirmed swing on the protective side is used, within stop history bounds.
- **Fixed:** ticks times `SYMBOL_TRADE_TICK_SIZE`, never an assumed pip value.

The ZigZag mechanism deliberately differs from the final repainting visual standard: Backstep is a causal stability delay, and an initial candle sequence simultaneously qualifying a high and low does not invent an ordering. This preserves Depth/Deviation/Backstep roles while providing immutable tradable confirmations. It is **not** advertised as a pixel-for-pixel clone of the final standard ZigZag plot.

Stops round outward to trading ticks; volume is then sized to that actual stop. Stop/freeze distance is checked against the executable bid/ask, so spread is included. Market/SL permissions, directional symbol permissions, fill mode, aggregate directional volume limit, margin and `OrderCheck` are checked. Failure skips the event. The loss per lot comes from `OrderCalcProfit` in account currency with adverse permitted deviation reserved. Commission reserve is the maximum of user input and observed historical per-lot round-trip charges. Volume floors to step and never rounds up to broker minimum.

First risk is 2% of current equity. Addition risk selects base risk, geometric reduction (20% default; first addition 1.6%) or empirical trend-end probability. Completed historical trend durations exclude the left-censored initial trend and the unfinished current trend. Neutral bars count toward duration. Age is zero on the reversal calculation bar. Only durations `T > age` enter the denominator; `age < T <= age + H` enter the numerator. Fewer than the minimum eligible samples, or unknown age, uses logged fixed-reduction fallback. BUY and SELL use the same global projected trend age.

Account exposure sums each open position's remaining **current executable market-to-SL** loss separately across all symbols, plus costs. Opposing trades are not netted. Missing/crossed/unknown SLs, unavailable conversions, or any unassessed account pending order block new entries. Proposed worst equity must remain at or above `B_day * (1 - Max_Daily_Risk_Percent/100)`. Equity deficit already includes realized and floating P&L; it is not double-counted as entry-to-stop risk for existing positions.

Simultaneous eligible BUY and SELL first entries are jointly prepared, filtered, sized and checked for combined risk/margin. If either cannot qualify jointly, both are rejected. After the first sequential submission, current exposure is checked again and unresolved first-order risk remains reserved. **KNOWN LIMITATION:** MT5 cannot provide an atomic pair of separate market orders. One may execute while the other fails; this is logged and reconciled honestly.

## Daily protection and monitoring

The day is the broker-server calendar day, derived via `TimeToStruct`/`StructToTime`, with no hardcoded UTC offset. Opening balance is reverse-reconstructed as current balance minus all available deal money changes since midnight. Missing/truncated history is explicitly an **Estimated available-ledger baseline**; it is not presented as a known midnight balance. Available-history trading continues as requested, but an invalid/nonpositive baseline blocks new orders.

Actual equity at or below the daily threshold immediately latches the day lock, cancels account pending orders and sends ticket-specific closes for all account positions. Tick, timer and trade-account callbacks check the threshold independently. Unresolved closes retry with a three-second throttle, without reopening positions. The latch remains until the next broker midnight; unfinished liquidation carries across midnight until the account is flat. At restart, `KTR!daily` execution/order history can recover the day lock. **Estimated chart-history minima never themselves trigger liquidation**; monitoring is display-only.

The panel shows exactly today's equity P&L, maximum opening-day-balance-relative drawdown, cash-flow-adjusted total equity P&L, and initial-deposit-relative maximum overall drawdown, plus a small completeness/currency note. Later deposits/withdrawals are subtracted from total P&L, rather than counted as trading performance. The initial deposit is taken from a reconciled broker cash ledger, with optional labeled override; otherwise initial-based metrics are Unavailable.

Historical work replays broker opening/closing deals chronologically, including carried positions, and samples bid/ask using bounded one-second `CopyTicksRange` windows. Current-session actual equity minima are combined with valid historical samples. Today's history is processed before earlier dates. Missing exposure ticks invalidate that sample rather than treating missing P&L as zero. Replay is capped at 128 concurrent positions; excess/incomplete openings invalidate samples. At most 100,000 most recent broker deals are processed; truncated baselines are labeled estimated. Samples/history days/per-timer work are bounded by inputs. Defaults request 30 days, five-minute samples, two samples per timer, at most 10,000 samples. Native tick-history retrieval may wait for broker data; terminal responsiveness remains a native acceptance test.

**All historical extrema remain Estimated**, including while work is incomplete: samples can miss intrainterval extrema, historical conversion rates/contracts/open swap cannot be fully reconstructed from present APIs, older periods may be outside the window, and tick history may be absent. Historical account credit/correction behavior can also prevent exact cash reconciliation. Increasing sampling does not make an exactness claim.

## Known limits and required native validation

- **NOT TESTED:** no MetaEditor, MT5 or Strategy Tester ran here. The C++ adapter checks production pure bodies, not MQL5 language/API compilation, indicators or execution. Native scripts are supplied but unrun.
- No claim of positive returns or a strict 5% loss guarantee. Gaps, spread changes, slippage outside requested deviation, unavailable prices, network outages and broker refusal can exceed the threshold.
- A single EA cannot enforce liquidation while MT5 is stopped/disconnected. Broker stops remain, but emergency closes need a connected running terminal and permissions.
- Without permitted durable local storage, an equity-only daily breach that leaves no broker evidence cannot be recovered exactly after a crash if later equity recovers. Broker emergency comments recover evidenced actions; missing history/comments/ticks remain a documented reconstruction limit, never a fabricated exact latch.
- The monitor's estimated extrema are not trading signals. They cannot establish that an actual historical limit was breached.
- Historical opening ownership can be unrecoverable after broker truncation or removal of all metadata. New entries are blocked; broker stops and current account protection continue.
- Live candle-history correction by a broker can change later replay results. Previously confirmed live ZigZag records do not mutate, and no old entry is replayed on attachment.
- This release does not coordinate multiple KTR charts/terminals or outside traders. Dedicated single-instance use is required. RETURN-only entry execution is intentionally unsupported.
- Stop placement, fill-price risk, partial execution, server rollover, multicurrency commissions and chart layout require the broker-specific tests in the acceptance plan.

## Assumptions and defaults

Unspecified defaults were chosen conservatively: all additional methods OFF, additional risk fixed reduction, SL fractal, ATR chart timeframe, lower TF M5, higher TF H4, fixed stop 200 trading ticks, fractal minimum 0.5 ATR with two-tick buffer, swing tolerance 0.15 ATR and lookback 300. All confirmations OFF reproduces the raw-trigger benchmark. An existing established cloud on first attachment does not cause an entry. Opposite-color shape entries remain possible; only explicitly enabled confirmations restrict them.

## Input reference

Defaults below are literal MQL5 input values. ATR units use the closed relevant signal/main ATR except the explicitly independent stop-ATR timeframe. `Shape_Plateau_Tolerance` is in fractions of a trading tick, ZigZag Deviation in broker points, stop buffers/fixed distance in trading ticks, risk in percent and money in account currency.


### General

| Input | Default | Note |
| --- | --- | --- |
| `Trade_Direction` | `TRADE_BOTH` |  |
| `Magic_Number` | `471001` |  |
| `Max_Deviation_Points` | `10` |  |

### First Entry / Ichimoku (standard 9/26/52, displacement 26)

| Input | Default | Note |
| --- | --- | --- |
| `First_Entry_Method` | `FIRST_EITHER` |  |
| `Enable_Tenkan_SSA_Valley` | `true` |  |
| `Enable_Tenkan_SSA_Peak` | `true` |  |
| `Enable_Kijun_SSA_Valley` | `true` |  |
| `Enable_Kijun_SSA_Peak` | `true` |  |
| `Shape_Window_Bars` | `7` |  |
| `Shape_Max_Lag_Bars` | `2` |  |
| `Shape_Min_Similarity` | `0.90` |  |
| `Shape_Pivot_Left_Bars` | `2` |  |
| `Shape_Pivot_Right_Bars` | `2` |  |
| `Shape_Min_Amplitude_ATR` | `0.05` |  |
| `Shape_Plateau_Tolerance` | `0.01` | fraction of one trading tick; fixed across historical replay |

### Additional Entry

| Input | Default | Note |
| --- | --- | --- |
| `Enable_LowerTF_Entry` | `false` |  |
| `Lower_Entry_Timeframe` | `PERIOD_M5` |  |
| `Enable_Kijun_Pullback` | `false` |  |
| `Enable_Tenkan_Kijun_Cross` | `false` |  |
| `Enable_Flat_SSB_Bounce` | `false` |  |
| `Enable_Kijun_Rejection` | `false` |  |
| `Additional_Entry_Cooldown_Main_Bars` | `1` |  |
| `Kijun_Touch_ATR` | `0.15` |  |
| `Kijun_Rejection_Min_WickBody` | `1.5` |  |

### First Entry Confirmations (AND)

| Input | Default | Note |
| --- | --- | --- |
| `First_Confirm_Price_Kumo` | `false` |  |
| `First_Confirm_TK` | `false` |  |
| `First_Confirm_Flat_SSB` | `false` |  |
| `First_Confirm_Swing_SR` | `false` |  |
| `First_Confirm_Thickness` | `false` |  |
| `First_Confirm_HigherTF` | `false` |  |
| `First_Confirm_Chikou` | `false` |  |

### Additional Entry Confirmations (AND)

| Input | Default | Note |
| --- | --- | --- |
| `Additional_Confirm_Price_Kumo` | `false` |  |
| `Additional_Confirm_TK` | `false` |  |
| `Additional_Confirm_Flat_SSB` | `false` |  |
| `Additional_Confirm_Swing_SR` | `false` |  |
| `Additional_Confirm_Thickness` | `false` |  |
| `Additional_Confirm_HigherTF` | `false` |  |
| `Additional_Confirm_Chikou` | `false` |  |

### Support, resistance and confirmation thresholds

| Input | Default | Note |
| --- | --- | --- |
| `Flat_SSB_Min_Bars` | `5` |  |
| `Flat_SSB_Max_Variation_ATR` | `0.05` |  |
| `Flat_SSB_Touch_ATR` | `0.15` |  |
| `Flat_SSB_Max_Age_Bars` | `100` |  |
| `SR_Min_Touches` | `2` |  |
| `SR_Min_Touch_Separation` | `3` |  |
| `SR_Lookback_Bars` | `300` |  |
| `SR_Tolerance_ATR` | `0.15` |  |
| `Cloud_Min_Thickness_ATR` | `0.1` |  |
| `Higher_Confirmation_Timeframe` | `PERIOD_H4` |  |
| `Chikou_Clearance_ATR` | `0.05` |  |

### Stop loss

| Input | Default | Note |
| --- | --- | --- |
| `SL_Method` | `SL_FRACTAL` |  |
| `Fractal_Min_Distance_ATR` | `0.5` |  |
| `Fractal_SL_Buffer_Ticks` | `2` |  |
| `ZigZag_Depth` | `12` |  |
| `ZigZag_Deviation` | `5` | broker points, as in standard ZigZag |
| `ZigZag_Backstep` | `3` |  |
| `ZigZag_SL_Buffer_Ticks` | `2` |  |
| `Fixed_SL_Distance_Ticks` | `200` |  |
| `ATR_Period` | `14` |  |
| `ATR_Timeframe` | `PERIOD_CURRENT` |  |
| `Stop_History_Bars` | `1000` |  |

### Risk

| Input | Default | Note |
| --- | --- | --- |
| `First_Entry_Risk_Percent` | `2` |  |
| `Max_Daily_Risk_Percent` | `5` |  |
| `Additional_Risk_Method` | `ADD_RISK_FIXED_REDUCTION` |  |
| `Additional_Risk_Reduction_Percent` | `20` |  |
| `Trend_End_Horizon_Bars` | `10` |  |
| `Trend_End_Min_Samples` | `50` |  |
| `Trend_End_History_Bars` | `10000` |  |
| `Commission_Reserve_Per_Lot` | `0` | account currency, round trip; max with observed broker charges |

### Prop monitor / bounded historical reconstruction

| Input | Default | Note |
| --- | --- | --- |
| `Show_Prop_Monitor` | `true` |  |
| `Monitor_Corner` | `CORNER_LEFT_UPPER` |  |
| `Monitor_X` | `15` |  |
| `Monitor_Y` | `20` |  |
| `Monitor_Font_Size` | `10` |  |
| `Monitor_Text_Color` | `clrWhite` |  |
| `Monitor_Background_Color` | `clrBlack` |  |
| `Initial_Deposit_Override` | `0` |  |
| `Equity_History_Days` | `30` |  |
| `Equity_Sample_Seconds` | `300` |  |
| `Equity_Samples_Per_Timer` | `2` |  |
| `Equity_Max_Samples` | `10000` |  |
| `Broker_History_Refresh_Seconds` | `30` |  |

## References

- [Official iIchimoku buffer/displacement example](https://www.mql5.com/en/docs/indicators/iichimoku)
- [Official CopyBuffer ordering and offsets](https://www.mql5.com/en/docs/series/copybuffer)
- [Official OrderCheck example, including successful retcode 0](https://www.mql5.com/en/docs/trading/ordercheck)
- [Official position-based history access](https://www.mql5.com/en/docs/trading/historyselectbyposition)

## Troubleshooting capacity rejection logs

The original combined `Candidate risk/margin exceeds shared capacity` message did not distinguish causes and could also appear when **no** order survived the signal/filter/preparation gates. That misleading path is now removed: no candidate means no capacity assessment or rejection log.

For viable proposed orders, diagnostics distinguish:

- `Entry blocked: nonpositive daily opening balance`: prints reconstructed `B_day`, equity, currency and baseline completeness. The first tester/account funding booked after midnight may reverse-reconstruct that day's opening balance as zero. This is not a margin failure. The EA does not invent a positive midnight balance or relax the daily limit; the next broker day can have a positive reconstructed baseline.
- `Daily-risk rejection`: prints opening balance, current equity, all-account remaining SL exposure, proposed risk (combined for a pair), projected worst equity, required minimum equity, projected daily risk, configured limit and baseline completeness.
- `Margin rejection`: prints required/free margin, proposed BUY/SELL volumes and account currency.
- Unassessable existing account exposure: explicitly identifies the exposure-assessment gate instead of silently skipping.

A legacy message alone cannot establish which limit rejected a real trade. Recompile the updated main file with its updated include files and collect the detailed Journal line. This change preserves risk percentages, volume sizing, daily baselines and joint-order rejection policy.

`python3 -u tests/ktr/run_submission.py` runs the existing 84 pure checks and 11 additional cases against the **actual production submission function** using explicit broker/indicator stubs. This verifies candidate gating, rejection routing, diagnostic amounts and retained joint-risk behavior; it is not MT5 execution evidence. Output: `tests/ktr/results/submission.txt`.
