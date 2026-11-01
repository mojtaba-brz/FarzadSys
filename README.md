# RSI Pull Up v2.02 for MetaTrader 5

A BUY-only Expert Advisor for comparing the original current-candle RSI strategy with two optional confirmed-swing Fibonacci zone filters. It uses the chart symbol and timeframe, four RSI(14, PRICE_CLOSE) readings at shift 0, persisted signal state, and broker-side SL/TP estimated in the deposit currency. No external runtime dependencies.

## Files and installation

- `RSI_Pull_Up.mq5`: production EA; modular functions in one file.
- `tests/RSI_Pull_Up_SelfTest.mq5`: test-only EA that calls production calculation functions. It never invokes the production trading event handlers.
- `Include/FiboCore.mqh`: pure confirmed-pivot, swing, setup lifecycle and zone logic.
- `Include/FiboRuntime.mqh`: cached bar processing, ATR, snapshots, CSV and trade-outcome linkage.
- `Include/FiboChart.mqh`: native Fibonacci, expansion, anchor labels and shaded zones.
- `tests/Fibo_SelfTest.mq5`: deterministic test EA; `tests/Fibo_Core_Script.mq5` runs the same core cases without a broker account.
- `tests/RSI_Regression_Script.mq5`: offline existing RSI regressions, Fibonacci tests, native snapshots, CSV and coordinate readback tests.
- `TEST_PLAN.md`: acceptance procedure and expected outcomes.
- `compile.log` and `tests/compile.log`: local MetaEditor build evidence.

In MT5, choose **File > Open Data Folder**. Copy this project (preserving `Include/` and `tests/`, excluding `tests/mt5_portable/`) to `MQL5/Experts/RSIPullUp/`. Open the main MQ5 in MetaEditor and press F7. Refresh Navigator, then attach `RSIPullUp/RSI_Pull_Up` to the desired chart. The supplied sources also compile directly from this Shared Projects directory; copying under Experts makes the EA easy to select in Navigator and Strategy Tester.

Start with XAUUSD M1, confirmations M5/M15/H1. Other instruments and deposit currencies are supported subject to their broker's contract, order, volume and stop rules. No live orders were placed during development.

## Inputs

| Group | Inputs and defaults |
| --- | --- |
| Position Sizing | Vol 0.01, Vol2 0.02, Vol3 0.03 lots |
| RSI | Entry 30; RSI1/RSI2/RSI3 Confirmation levels each 30; RSI1 M5, RSI2 M15, RSI3 H1 |
| Trade Management | Take Profit 4, Stop Loss 2 deposit-currency units per position; Magic 300130; slippage fixed internally at 10 points; trading permission follows MT5/account settings |
| Fibonacci | Observe Only; M15; strict pivots 3 left / 3 right; ATR14; minimum swing 1.5 ATR; 500 history bars; expiry 96 completed candles |
| Fibonacci appearance/export | Both drawings visible; DodgerBlue pullback / Orange expansion; shaded zones on; development-only debug CSV enabled internally |
| Monitor | Show true, LEFT_MIDDLE, offsets 20/0 pixels, font 9, width 300 pixels, white text, black normal background, green confirmation background |

The actual chart timeframe must be strictly shorter than RSI1, which must be strictly shorter than RSI2, which must be strictly shorter than RSI3. Durations are compared with `PeriodSeconds`, not enum values. Invalid ordering leaves the EA loaded, warns on the chart even if the monitor is hidden, and disables entries. Existing broker-side stops are untouched. Correct the settings or change the chart timeframe to reinitialize.

Monitor defaults to LEFT_MIDDLE and also supports RIGHT_MIDDLE, RIGHT_TOP and LEFT_TOP. Status text is shortened to fit; hover over it for the full message. Offsets are relative to the selected edge/vertical location. The panel repositions on chart resize; the compact default is 300 pixels wide with 21-pixel rows. The v2 panel has 16 rows (336 pixels tall) including seven Fibonacci status rows. `Monitor_Width` and font size remain adjustable; extremely small charts may clip the table. Each RSI row shows its own threshold.

## Entry and state rules

Every tick reads all four live RSI buffers. With RSI0 < Entry and RSI1 < RSI1 Confirmation:

| RSI2 < RSI2 Confirmation | RSI3 < RSI3 Confirmation | Requested lots |
| --- | --- | --- |
| false | either | Vol |
| true | false | Vol2 |
| true | true | Vol3 |

Each confirmation RSI has its own input (`RSI1_Confirmation_Level`, `RSI2_Confirmation_Level`, `RSI3_Confirmation_Level`), used consistently in sizing, journal confirmations and row highlighting. All default to 30, preserving the original default strategy. The main RSI retains its separate `RSI_Entry_Level`. Existing saved settings using the former shared confirmation input must be updated to the three new inputs.

There is no RSI crossing or closed-bar filter. The default Observe Only mode does not apply a Fibonacci trading filter. All comparisons are strict. Equality neither enters nor rearms. A genuine first attachment is ARMED, permitting an immediate entry. An executed or partially filled entry consumes the signal. Only RSI0 strictly above Entry rearms, including while a position remains open.

An actionable signal (including the selected Fibonacci filter when required) blocked by an existing position is consumed; closing that position does not release a queued signal. Hedging accounts block positions belonging to this symbol/magic. Netting accounts block **any** position on the symbol. A second EA instance with the same account/server/symbol/magic scope is rejected, avoiding concurrent submissions from this EA on two charts. Use a single instance per scope; other terminals and external traders cannot participate in this terminal-local guard.

Failed validations/rejections leave the signal armed but are retried at most once per chart bar. The attempt bar is persisted. An accepted or uncertain request remains in flight until broker positions, orders or history resolve it. Partial fills consume the signal and any remaining RETURN order is canceled, with cancellation retries throttled to five seconds if necessary. Broker cancellation or freeze restrictions can delay cancellation; the EA stays locked against additional entry requests. FOK is preferred, then IOC, then RETURN only on execution modes that permit it.

## Restart recovery

Live signal state, last-attempt bar, request intent, request time and exact order ticket halves are kept in terminal Global Variables. Keys are hashed from account server/login, symbol and magic; the exact prefix is printed as `Persistence scope: RPU....live`. Chart timeframe is intentionally not part of the key. Deinitialization removes only this chart instance's graphical objects and releases indicator handles; it retains signal state.

Request intent is flushed **before** `OrderSend`. Startup restores the record and reconciles actual EA positions, active orders and history. An owned open position proves a previous entry. First attachment is used only when no live state exists. Tester passes deliberately start independently using a separate `.test` namespace.

If a crash or connection failure leaves an unknown request with no ticket or broker evidence, the EA deliberately remains locked rather than blindly resending. After independently verifying the broker's positions/orders/history and confirming that no request remains outstanding, detach the EA and use MT5 **F3** to remove the `.pending`, `.since`, `.orderHi` and `.orderLo` variables for its printed prefix. Keep `.state` and `.bar` to preserve the signal/retry history. Reattach to reconcile again. Deleting all state applies first-attachment behavior and can allow immediate entry.

Terminal Global Variables expire after four weeks without access. The running EA refreshes access; preservation beyond a terminal shutdown of four weeks is subject to that platform limit. Reinstallation, deletion of globals, a different terminal/account/server/symbol/magic also creates a new scope. The instance guard is terminal-local, not a distributed lock across multiple terminals. Concurrent manual/other-EA trading on a netting symbol should be avoided because the broker can merge positions after this EA's preflight check.

## Monetary protection and broker constraints

`OrderCalcProfit(ORDER_TYPE_BUY, symbol, lots, Ask, closing_price, ...)` calculates gross account-currency profit. The EA brackets and bisects the TP/SL roots, compares adjacent price ticks, and chooses the closest tick to each requested monetary target. BUY exits use Bid, so initial stop-distance validation is relative to current Bid. The monetary root is based on estimated Ask entry. Tick size is used for price increments; point size is used for broker stop distances and deviation.

The requested lot size must meet min/max/step and total directional volume-limit rules; it is never resized. Trade/order modes, filling policy, margin and `OrderCheck` are validated. If the closest rounded target prices fail stop-distance requirements, the trade is skipped. Targets are never moved to satisfy broker minimum distances. Initial protection is included in the market request; there is no fallback to an unprotected entry. Freeze levels concern later operations: this EA makes no stop/position modifications, and the server enforces cancellation constraints on any remainder.

Once opened, the original broker-side stops manage exits. No RSI exit, trailing stop, break-even, volume modification, SELL or add-on entry exists. Estimated targets are **not exact or guaranteed**: fill price, slippage, gaps, commissions, swap and currency conversion can change actual results. Journal ATTEMPT/RESULT/EXECUTED records include RSI values, confirmations, volume, prices, estimated money, account currency, magic, return codes and actual fills when available.

## Fibonacci v2: operating modes and inputs

| `Fibo_Mode` | Entry behavior |
| --- | --- |
| FIB_DISABLED (0) | Original RSI decisions; Fibonacci filter not applied |
| FIB_OBSERVE_ONLY (1, default) | Same RSI decisions as Disabled; record both actual zone matches |
| FIB_PULLBACK_ONLY (2) | RSI signal AND bullish-pullback zone |
| FIB_COUNTERTREND_ONLY (3) | RSI signal AND bearish-exhaustion projection zone |
| FIB_BOTH (4) | RSI signal AND (pullback OR countertrend); one order maximum |

Disabled and Observe Only force the **filter pass** flag true, but actual `PullbackConfirmed` and `CountertrendConfirmed` remain separate measured zone flags. The monitor shows NOT APPLIED rather than implying a zone match. In filtered modes a false/missing confirmation leaves RSI ARMED; a later zone match can enter while the RSI conditions remain valid. Only an actionable combined signal blocked by a position is consumed. Execution, retries, unresolved-request safety and rearming retain their original rules.

Inputs: `Fibo_Timeframe=M15`, `Pivot_Left_Bars=3`, `Pivot_Right_Bars=3`, `Min_Swing_ATR=1.5`, `ATR_Period=14`, `Swing_History_Bars=500`, `Setup_Expiry_Bars=96`. **`Fibonacci_Lookback_Hours` is removed**: elapsed-window extrema no longer determine any anchors. The old Show_Fibonacci/Fibonacci_Color settings are replaced by independent `Show_Pullback_Fibonacci`, `Show_Countertrend_Fibonacci`, `Pullback_Fibonacci_Color` and `Countertrend_Fibonacci_Color`. Both show flags default true, colors DodgerBlue/Orange. `Show_Fibonacci_Zones=true` enables muted solid `Pullback_Zone_Color` and `Countertrend_Zone_Color`. Native rectangles do not offer portable alpha blending, so no unsupported opacity promise/input is provided. Drawing visibility never gates calculations or entries.

### Confirmed swing engine and setup lifecycle

Only closed Fibonacci-timeframe bars confirm pivots. A candidate must strictly exceed every neighboring high (or be strictly below every neighboring low); ties reject that pivot. A simultaneous high/low pivot is rejected because OHLC cannot establish order. With three right candles, confirmation occurs at the actual opening timestamp of the bar following the third completed right candle. No right-side forming/future candle is read. Timestamps are stable pivot identifiers.

Chronological pivots alternate; old pending candidates are pruned to the configured history window without editing existing setup copies. A same-type candidate replaces the last candidate only when more extreme; equal/weaker candidates are ignored. Setup anchors are copies, never mutable references to the candidate list. A newer fully confirmed qualifying sequence may replace a setup, with a different ID and logged replacement. Closed-bar ATR at activation is snapshotted along with its bar timestamp. Swing range must be positive and at least `Min_Swing_ATR * ATR`.

The default bootstrap requests 523 bars (500 processed history bars plus pivot/ATR warmup and the forming bar). Insufficient or unsynchronized history/ATR blocks only filtered entries. After initialization, full data is retrieved only when a Fibonacci bar changes and only newly completed bars are processed; ticks use cached setups and the forming bar's extrema. Historical reconstruction produces no retroactive entries or historical confirmation rows. Existing setups are aged/invalidated with a completed bar **before** any setup confirmed by that bar is activated.

Mode A needs four alternating confirmed pivots: previous Low, previous High, L, H, with L higher than the previous low and H higher than the previous high. This avoids asserting bullish structure without reference pivots. It creates a bullish impulse L -> H. `F(r) = H - r*(H-L)`; zone `[F(0.786), F(0.50)]` is inclusive. A strict price break below L invalidates the setup; equality does not. The object displays 0% at H and 100% at L, plus 23.6/38.2/50/61.8/78.6%.

Mode B needs A High -> B Low -> C High with `A > C > B`. The bearish impulse A-B meets the ATR magnitude requirement. Only after C confirms, `E(r) = C - r*(A-B)` is frozen for r=1.272 and 1.618. Confirmation requires distance <= `0.10 * activation ATR` from **either individual level**; the gap between them is not a support zone. Strictly above C or strictly below `E(1.618)-tolerance` invalidates the setup. The optional 100% reference is displayed too. A zone match is a research condition, not proof that price will reverse.

Both models expire after 96 completed Fibonacci candles by default. Activation begins at age zero; the first completed candle after activation increments age to one. Active, expired and invalidated setups are distinguished in the monitor and on-chart labels. Obsolete or unavailable-data drawings turn gray/dotted and lose shading, so they cannot appear active. Frozen anchors, exact price labels and two independent objects use the EA's existing scope/chart prefix. Only EA-owned objects are removed.

### Price basis, restart state and display mapping

Fibonacci uses BID on Bid-priced charts and LAST on Last-priced charts (`SYMBOL_CHART_MODE`), with no fallback to a different basis. Missing/invalid quotes disable actual confirmations. The chosen basis is logged; BUY execution continues to use Ask in the original trade engine. Current forming-bar extrema also invalidate cached setups, covering excursions during a disconnect/restart.

A native binary snapshot `<printed persistence scope>.fibo.bin` in MQL5/Files stores the candidate pivots, both setup states/anchors, ATR snapshots, ages and last processed closed bar. Restart loads it and processes only missing bars. Invalidated/expired states do not reset to active. Configuration changes explicitly start a fresh model configuration; the effective timeframe is included even when PERIOD_CURRENT is selected. If the gap exceeds available history, cached active setups expire before available history is reconstructed. Snapshots now use a content checksum and staged/flushed replacement; interrupted staging (.tmp) fails closed rather than loading potentially stale state. Legacy v2.00 snapshots are migrated while preserving anchors and invalidations. A damaged, truncated, checksum-invalid or unwritable snapshot fails closed for filtered entries; RSI-only modes still trade. After verifying state, detach and resolve the damaged snapshot and any uncommitted .tmp file before intentionally reconstructing afresh. This is separate from existing RSI/order Global Variables. Tester passes start independent model state and do not use live snapshots.

MT5 retracement coordinates L,H use `price2 + r*(price1-price2)`; expansion A,B,C uses `price3 + r*(price2-price1)`. Thus positive standard coefficients implement the desired formulas directly in v2; the old reversed retracement labels are removed. Coordinate/level coefficients are read back and checked against the formulas, with native-object tests. Visual verification of the renderer and all styles remains in the manual checklist. Monitor RSI rows retain their green backgrounds and unchanged configured font color.

## Event observations and CSV

Fibonacci CSV export is **debugging only** and has no enable/filename inputs. The code-only `DEBUG_FIBO_CSV=true` constant in `Include/FiboRuntime.mqh` keeps it enabled during development. Filenames are generated as `RSI_Pull_Up_Fibo_Debug_<account/symbol/magic scope>.<mode>.csv`, preventing collisions between scopes/modes without additional inputs. The Journal reports the exact name. Files append, quote/escape fields and flush on events. A TODO marks this export for removal when the EA is finalized; the separate binary recovery snapshots are safety state and are not debug files.

Live output is in **File > Open Data Folder > MQL5/Files**. In Strategy Tester it is in the executing agent's **MQL5/Files**, typically `<tester data root>/Agent-127.0.0.1-<port>/MQL5/Files`, not the live terminal's Files directory; no FILE_COMMON flag is used. Remote/cloud agents have their own sandbox, so use a local agent for collecting CSVs. Files from repeated passes append; `run_id` differentiates starts and `signal_cycle` persists across live restarts. Cycle 0 denotes an unknown pre-observation trade cycle; it is never invented from the current signal. Request-cycle, order, deal and position identifiers link asynchronous execution/closure rows to decisions, including across restarted runs. Use account/scope plus position ID when joining positions, not the current RSI state on an exit row.

CSV fields are:

- Run ID, server event time, symbol, chart/Fibonacci timeframes, event, signal/request cycle and RSI-ready flag.
- RSI0..3, threshold0..3, current selected entry lots, signal state, evaluation price and BID/LAST source.
- Mode A ID/state, L/H prices, pivot/confirmation times, lower/upper zone, actual confirmation, activation ATR/time and signed ATR distances to 50/61.8/78.6%.
- Mode B ID/state, A/B/C prices, pivot/confirmation times, 127.2/161.8 projections, tolerance, actual confirmation and matched-zone code (1272/1618/0), activation ATR/time and signed ATR distances to both projections.
- Active mode, data readiness, filter pass, order-attempt flag, order/deal/position IDs, actual fill, server retcode, realized net where available, currency and notes.

Events cover reconstruction summaries, setup creation/replacement/invalidation/expiry, zone transitions, RSI qualification/rearming, position blocks, validation failures, submitted-request results and actual deal entry/exit/whole-position closure. No duplicate observation is written merely because another tick arrived. `REQUEST_RESULT.order_attempted=1` means OrderSend was called; a validation-failed row has zero. An observed signal is not a filled trade. Empty realized_net means no realized result is asserted, not zero P/L.

`DEAL_EXIT` contains that deal's profit+swap+commission+fee. `POSITION_CLOSED` is deferred until the position is absent and sums its broker history including entry/exit costs. Manual exits of an owned position are linked by position history. Live deal/closure markers and a checkpoint recover observed outcomes across restart; first installation starts collecting from attachment time. Deduplicate by scope+deal/position identifiers if a process fails between a CSV flush and writing its checkpoint. Broker costs posted separately without a position ID, broker history unavailable later, or external netting merges require independent reconciliation with the account statement. No net result is invented for an unexecuted signal.

Platform references: [OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit), [Fibonacci](https://www.mql5.com/en/docs/constants/objectconstants/enum_object/obj_fibo), [Expansion](https://www.mql5.com/en/docs/constants/objectconstants/enum_object/obj_expansion).

## Reproducible Strategy Tester procedure

1. Install/compile under Experts as above. Open MT5 Strategy Tester (Ctrl+R), select `RSIPullUp/RSI_Pull_Up`, symbol XAUUSD, timeframe M1.
2. Use the default inputs. Choose **Every tick based on real ticks** where the broker supplies real tick history. Use a date range with M1 and higher-timeframe warmup history; confirm all four RSI readings become available. Keep account currency, leverage, contract specs, spread/data source and deposit recorded with the report.
3. Run a single pass in Visual mode. Add four native RSI(14, Close) indicators on the corresponding charts to compare shift-0 readings; pause/tick through entries. Verify broker SL/TP in the positions and deal history and compare Journal ATTEMPT/EXECUTED records.
4. Execute the checklist in TEST_PLAN.md. Use controlled custom-symbol ticks for exact threshold/equality, failures, gaps and delayed execution cases; historical data alone cannot guarantee those events. Never change production conditions to force a test.
5. Repeat on a forex symbol and another supported contract, then a test environment whose deposit currency differs from USD. Inspect actual broker tick size, volume and stop requirements. A valid skip for an infeasible small monetary target is expected, not a solver failure.
6. Compile/select `RSIPullUp/tests/RSI_Pull_Up_SelfTest`. Run a single pass on XAUUSD M1 with defaults and a short range containing ticks. This test-only EA stops after its first tick and prints `SELFTEST RESULT: passed=... failed=...`. It tests production volume selection, equality/rearming, legacy extrema regression, Fibonacci core cases and OrderCalcProfit price-grid properties without submitting orders. It must report zero failures. Repeat with confirmation levels 25/35/45 to test independent thresholds and equality for each RSI. It intentionally refuses live-chart initialization.
7. Save tester report, settings, Journal and build logs with each result. A tester pass does not test live network timing or terminal restart recovery; use a demo account for those cases.

All reads are current/past data; there are no forward bar references. The forming bar can change on every tick by design. Parameter optimization is not part of this delivery.

## Five-mode comparison procedure

Run all five configurations independently with the same symbol, dates, real-tick model where available, deposit currency, commission/execution settings, RSI thresholds, volumes, TP/SL and all swing parameters. Only Fibo_Mode and report filenames change; debug CSV names are generated automatically per scope and mode. Do not reconstruct filtered performance merely by deleting trades from the Disabled report: skipping entries changes position availability and subsequent opportunities. First compare Disabled vs Observe Only deal histories (time, direction, requested/fill volume and SL/TP) for exact decision parity. Test five modes again with drawings hidden and the code-only debug export disabled to check independence.

Freeze parameters before evaluation. Split history chronologically, for example: development 2024, validation January-June 2025, held-out July-December 2025; provide the same adequate pre-period warmup in every pass. Do not tune on the held-out segment. If those dates lack broker data, choose and record another chronological split before looking at outcomes. No parameter optimization was performed here.

Record by mode and segment: closed-position count, net profit, net expectancy (`sum net / closed positions`), profit factor (positive position net / absolute negative position net), MT5 maximum equity drawdown, win rate (positive-net positions / closed positions), average first-entry-to-final-exit duration, and actual A/B/either confirmation frequency at eligible RSI decision events. Group partial fills/closes by position ID. Keep rejected/unexecuted signals separate. Report an undefined profit factor when no losing positions exist. Use MT5 reports/history for equity drawdown and deal timing; CSV observations alone are not an equity curve. Also report distinct eligible signal cycles, later zone transitions while ARMED, and attempt/fill counts, so confirmation frequency denominators are explicit. Skipped entries change the denominator in filtered modes; measure each mode separately.

## Verification status and test reproduction

The v2.01 native offline suite passed **124 checks with zero failures**. Authenticated demo Strategy Tester self-tests passed **120 checks each** on XAUUSD_o/USD, XAUUSD_o/EUR and EURUSD_o/USD, including monetary calculations and explicit currency assertions. A separate report/CSV audit passed **572 checks**, including exact Disabled/Observe trade parity, protected BUY-only entries, position limits, sizing/filter conditions and realized-net reconciliation. Native ownership tests use a test-only adapter; they do not place trades or claim actual netting-broker validation.

Five independent M1 XAUUSD_o runs over September 1-8, 2026 used **1,507,083 generated ticks each** with unchanged trading/swing defaults. Disabled/Observe: 58 trades each, identical order/deal tables and net -57.59 USD. Pullback: 2 trades, +1.89 USD; Countertrend: 4, -2.24 USD; Both: 6, -0.35 USD. Insufficient-margin/unsupported-volume tests opened zero positions. With unavailable monthly Fibonacci history, Disabled/Observe traded identically (28 each), while Both opened none. These are generated-tick integration results, not a profitability or real-tick validation claim. The real-tick attempt stalled and was stopped. Detailed metrics, evidence and remaining limitations are in `tests/results/VERIFICATION.md`.

Fault injection reproduced a full-size snapshot corruption bug before the fix (one failing assertion); checksummed/staged snapshots now reject it. Successful-order logging now captures the actual OrderSend error instead of a stale terminal error. Bar/ATR copying also rechecks the timeframe after the copy to guard against a concurrent candle rollover. No RSI, sizing or money-management parameter was optimized or changed.

To reproduce offline: compile/run `tests/RSI_Regression_Script.mq5`, preserving Include and tests under MQL5/Scripts/RSIPullUp (or the Shared Projects compiler output path). It makes no trade requests and writes RSI_Regression_Result.txt to MQL5/Files. Deliberately damaged/uncommitted scratch-snapshot diagnostics are expected test output; scratch files/objects are removed. `Fibo_Core_Script` runs the core-only 70 cases. In an authenticated local Strategy Tester, run `RSI_Pull_Up_SelfTest` on XAUUSD_o with USD, then EUR, and EURUSD_o/USD; set Test_Expected_Currency accordingly. Repeat separate RSI thresholds 25/35/45 when testing custom input configurations.

For comparisons, explicitly populate **all** strategy inputs in every tester config: MT5 carries omitted values over from previous tests. `tests/DEFAULT_TESTER_INPUTS.ini` supplies the production trading defaults with graphics hidden equally for fast automated comparisons; merge that section before applying scenario overrides. Use unique report names and the automatically named debug CSVs with local agents, preserve each agent CSV **before the next test** (MT5 can clean the agent Files sandbox), and retain the MT5 report. The native test sources/fixtures and result logs are provided; no Python or external runtime is required by the EA.

Configuration simplification: `Max_Slippage_Points` and `Enable_Trading` are removed from inputs. Requests always use deviation 10 points. MT5 Algo Trading, EA permissions and broker/account restrictions remain authoritative. Old preset entries for the removed controls should be discarded. The table now defaults to left-middle; saved presets may still specify their previous position.

Archived v2.01 backtests used the earlier configurable 20-point deviation. The v2.02 input cleanup fixes it at 10 points; those historical performance numbers are not a new backtest of the updated setting.
