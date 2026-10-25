# RSI Pull Up for MetaTrader 5

A BUY-only Expert Advisor for testing the specified current-candle RSI idea. It uses the chart symbol and timeframe, four RSI(14, PRICE_CLOSE) readings at shift 0, persisted signal state, and broker-side SL/TP estimated in the deposit currency. No external runtime dependencies.

## Files and installation

- `RSI_Pull_Up.mq5`: production EA; modular functions in one file.
- `tests/RSI_Pull_Up_SelfTest.mq5`: test-only EA that calls production calculation functions. It never invokes the production trading event handlers.
- `TEST_PLAN.md`: acceptance procedure and expected outcomes.
- `compile.log` and `tests/compile.log`: local MetaEditor build evidence.

In MT5, choose **File > Open Data Folder**. Copy this project (preserving `tests/`) to `MQL5/Experts/RSIPullUp/`. Open the main MQ5 in MetaEditor and press F7. Refresh Navigator, then attach `RSIPullUp/RSI_Pull_Up` to the desired chart. The supplied sources also compile directly from this Shared Projects directory; copying under Experts makes the EA easy to select in Navigator and Strategy Tester.

Start with XAUUSD M1, confirmations M5/M15/H1. Other instruments and deposit currencies are supported subject to their broker's contract, order, volume and stop rules. No live orders were placed during development.

## Inputs

| Group | Inputs and defaults |
| --- | --- |
| Position Sizing | Vol 0.01, Vol2 0.02, Vol3 0.03 lots |
| RSI | Entry 30; RSI1/RSI2/RSI3 Confirmation levels each 30; RSI1 M5, RSI2 M15, RSI3 H1 |
| Trade Management | Take Profit 4, Stop Loss 2 deposit-currency units per position; Magic 300130; Slippage 20 points; Enable Trading true |
| Fibonacci | Show true, elapsed lookback 24 hours, DodgerBlue |
| Monitor | Show true, RIGHT_MIDDLE, offsets 20/0 pixels, font 9, width 300 pixels, white text, black normal background, green confirmation background |

The actual chart timeframe must be strictly shorter than RSI1, which must be strictly shorter than RSI2, which must be strictly shorter than RSI3. Durations are compared with `PeriodSeconds`, not enum values. Invalid ordering leaves the EA loaded, warns on the chart even if the monitor is hidden, and disables entries. Existing broker-side stops are untouched. Correct the settings or change the chart timeframe to reinitialize.

Monitor placement also supports LEFT_MIDDLE, RIGHT_TOP and LEFT_TOP. Status text is shortened to fit; hover over it for the full message. Offsets are relative to the selected edge/vertical location. The panel repositions on chart resize; the compact default is 300 pixels wide with 21-pixel rows (189 pixels tall). `Monitor_Width` and font size remain adjustable; extremely small charts may clip the table. Each RSI row shows its own threshold.

## Entry and state rules

Every tick reads all four live RSI buffers. With RSI0 < Entry and RSI1 < RSI1 Confirmation:

| RSI2 < RSI2 Confirmation | RSI3 < RSI3 Confirmation | Requested lots |
| --- | --- | --- |
| false | either | Vol |
| true | false | Vol2 |
| true | true | Vol3 |

Each confirmation RSI has its own input (`RSI1_Confirmation_Level`, `RSI2_Confirmation_Level`, `RSI3_Confirmation_Level`), used consistently in sizing, journal confirmations and row highlighting. All default to 30, preserving the original default strategy. The main RSI retains its separate `RSI_Entry_Level`. Existing saved settings using the former shared confirmation input must be updated to the three new inputs.

There is no crossing, closed-bar or Fibonacci filter. All comparisons are strict. Equality neither enters nor rearms. A genuine first attachment is ARMED, permitting an immediate entry. An executed or partially filled entry consumes the signal. Only RSI0 strictly above Entry rearms, including while a position remains open.

A qualifying signal blocked by an existing position is consumed; closing that position does not release a queued signal. Hedging accounts block positions belonging to this symbol/magic. Netting accounts block **any** position on the symbol. A second EA instance with the same account/server/symbol/magic scope is rejected, avoiding concurrent submissions from this EA on two charts. Use a single instance per scope; other terminals and external traders cannot participate in this terminal-local guard.

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

## Fibonacci and monitor

Fibonacci scans available M1 bars by server timestamp in the rolling elapsed-hour window, including the forming M1 bar. At an exact window boundary, M1 data cannot identify the intra-minute time of an extreme. The implementation uses bar-open timestamps inside `[now - hours*3600, now]`, omitting the straddling boundary minute rather than including potentially out-of-window prices. This gives minute-resolution window membership, not reconstructed tick extrema. Weekend gaps do not extend the window to collect a fixed candle count.

Earliest occurrences win tied highs/lows. The earlier extreme is the first coordinate and displayed 0%, the later is displayed 100%. MT5's internal Fibonacci level coefficients are reversed to label that chronological direction correctly. Both extrema on the same M1 bar are ambiguous, so the EA removes its own Fibonacci until ordering is knowable. Missing M1 history affects display only. Full-window scans occur once per server second or on changes to current M1 extremes; object anchors change only when necessary. Standard labels are 0, 23.6, 38.2, 50, 61.8, 78.6, 100%.

Rows show the actual selected timeframes. RSI below its respective threshold uses the configurable green **background** with the same static text color. Signal, selected volume, position and trading/validation status are also displayed. Object names include scope and chart ID; user drawings are left alone.

Platform references: [OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit), [Fibonacci objects](https://www.mql5.com/en/docs/constants/objectconstants/enum_object/obj_fibo).

## Reproducible Strategy Tester procedure

1. Install/compile under Experts as above. Open MT5 Strategy Tester (Ctrl+R), select `RSIPullUp/RSI_Pull_Up`, symbol XAUUSD, timeframe M1.
2. Use the default inputs. Choose **Every tick based on real ticks** where the broker supplies real tick history. Use a date range with M1 and higher-timeframe warmup history; confirm all four RSI readings become available. Keep account currency, leverage, contract specs, spread/data source and deposit recorded with the report.
3. Run a single pass in Visual mode. Add four native RSI(14, Close) indicators on the corresponding charts to compare shift-0 readings; pause/tick through entries. Verify broker SL/TP in the positions and deal history and compare Journal ATTEMPT/EXECUTED records.
4. Execute the checklist in TEST_PLAN.md. Use controlled custom-symbol ticks for exact threshold/equality, failures, gaps and delayed execution cases; historical data alone cannot guarantee those events. Never change production conditions to force a test.
5. Repeat on a forex symbol and another supported contract, then a test environment whose deposit currency differs from USD. Inspect actual broker tick size, volume and stop requirements. A valid skip for an infeasible small monetary target is expected, not a solver failure.
6. Compile/select `RSIPullUp/tests/RSI_Pull_Up_SelfTest`. Run a single pass on XAUUSD M1 with defaults and a short range containing ticks. This test-only EA stops after its first tick and prints `SELFTEST RESULT: passed=... failed=...`. It tests production volume selection, equality/rearming, extrema selection and OrderCalcProfit price-grid properties without submitting orders. It must report zero failures. Repeat with confirmation levels 25/35/45 to test independent thresholds and equality for each RSI. It intentionally refuses live-chart initialization.
7. Save tester report, settings, Journal and build logs with each result. A tester pass does not test live network timing or terminal restart recovery; use a demo account for those cases.

All reads are current/past data; there are no forward bar references. The forming bar can change on every tick by design. Parameter optimization is not part of this delivery.

## Verification status

MetaEditor64 compilation of the main EA and self-test EA was performed locally; consult the compile logs for the final results. Strategy Tester and demo execution scenarios have **not** been run. The test harness is provided and compiled, but its runtime assertions are not reported as passed. The acceptance checklist records expected outcomes, not observed trading performance.
