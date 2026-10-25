# RSI Pull Up acceptance and regression plan

## Result ledger

- Main EA: MetaEditor compilation performed; final results in `compile.log`.
- Test EA: MetaEditor compilation performed; final results in `tests/compile.log`.
- Runtime self-tests, historical Strategy Tester passes and demo/live scenarios: **NOT RUN**.
- Every expected result below remains **UNVERIFIED** until a run's report/Journal is attached. No performance or profitability claim is made.

Record for each run: MT5/build, MQ5 revision/hash, broker/server, account mode/currency/leverage, symbol specifications (point, digits, tick size, contract/profit mode, volume min/max/step/limit, stop/freeze levels, filling/execution flags), chart timeframe, inputs, date interval, modeling mode, data source, actual ticks used, observed results and log/report paths.

Use the defaults (XAUUSD M1; M5/M15/H1; RSI14 Close; levels 30; lots .01/.02/.03; TP4/SL2; 24h Fibonacci). Use Every tick based on real ticks with warmup history for each RSI timeframe. Follow README installation/testing instructions. For exact input sequences, use a controlled MT5 custom symbol and synthetic tick fixture or a demo broker/test environment that can reproduce the condition. Do not inject fake RSI into the production EA or disable its protection. The test-only EA independently exercises production helper functions without sending orders.

## Entry acceptance tests (original requirements 1-15)

Values below use [RSI0, RSI1, RSI2, RSI3]. Arrange an ARMED state, no blocking position/order and valid broker conditions unless specified.

| ID | Setup/action | Expected result |
| --- | --- | --- |
| 1 | [29,29,31,31] | One protected BUY requesting Vol. |
| 2 | [29,29,29,31] | One protected BUY requesting Vol2. |
| 3 | [29,29,29,29] | One protected BUY requesting Vol3. |
| 4 | [29,31,29,29] | No order; signal remains armed. |
| 5 | [31,29,29,29] | No order. |
| 6 | [29,29,31,29] | Vol; Conf3 cannot override false Conf2. |
| 7 | Put each RSI exactly at 30 in turn | RSI0/1 equality prevents entry; RSI2 equality selects Vol; RSI3 equality with Conf2 true selects Vol2. Main equality preserves either existing signal state. |
| 8 | No prior state in isolated demo scope; attach during valid oversold signal | First ready tick may enter immediately; no upward crossing required. |
| 9 | Hold RSI0<30, begin RSI1>30, then drop RSI1<30 intrabar | Entry on confirming tick, without waiting for bar close. |
| 10 | Execute a trade; hold RSI0 below 30 through exit and many ticks | No repeat entry. |
| 11 | After consumption move RSI0 to 30, then >30 | Equality leaves CONSUMED; strict rise sets ARMED. |
| 12 | After rearm, return RSI0/1 below thresholds with position absent | One new entry; selected size follows current confirmations. |
| 13 | Existing owned hedging position; or any netting position | No extra entry, close, volume change or stop modification. |
| 14 | Valid signal while a position blocks it; close that position while RSI0 remains below 30 | Signal consumed; no deferred entry until a strict-rise rearm and new valid signal. |
| 15 | Arrange a broker rejection while signal persists | No per-tick burst; at most one entry attempt in a chart bar; retry may occur next bar only if still armed/valid. |

The source-level self-test enumerates all 16 four-condition truth-table combinations, plus equality and rearm boundaries. Run `tests/RSI_Pull_Up_SelfTest` in Strategy Tester with defaults. Inspect individual PASS/FAIL lines and final result; a compilation alone is not a pass.

## Money management acceptance tests (16-21)

| ID | Setup/action | Expected result |
| --- | --- | --- |
| 16 | Exercise every Conf1/2/3 combination with main true, then false | Exact requested size or no trade; no resizing/rounding of lots. |
| 17 | USD XAUUSD account, each supported requested volume | Use Ask in OrderCalcProfit; nearest tick TP estimates +4 and SL -2 before costs. Broker distance failure skips, never widens targets. Actual fill/exit may differ. |
| 18 | Non-USD test account, same numeric money inputs | Targets/logs are in ACCOUNT_CURRENCY, not fixed USD or manually converted lots. |
| 19 | Forex pair, index/CFD and a tick-size != point-size instrument | Tick-aligned prices and correct OrderCalcProfit account-currency estimates; appropriate skip if contract constraints make the requested targets infeasible. |
| 20 | Below-min/above-max/off-step lots, exhausted directional volume limit, large stop minimum, insufficient margin | No new position. Journal explains failure. Requested lots and monetary targets are not adjusted. Attempt rate is bounded. |
| 21 | Execute then remove EA/disconnect terminal | Original broker-side TP/SL remain attached; exits require no EA ticks. Do not disconnect any production trading environment for this test. |

For numerical verification, independently call OrderCalcProfit using the logged requested Ask, volume and TP/SL. Evaluate the adjacent ticks as well: the selected tick should minimize absolute target error before broker-distance validation. Check with actual execution price separately to show the impact of slippage. Verify charges and swap are not incorrectly promised as included in targets.

## Chart and reliability acceptance tests (22-30)

| ID | Setup/action | Expected result |
| --- | --- | --- |
| 22 | Compare each native RSI14 Close current-bar value while stepping real ticks | Monitor/entry readings track shift 0 and can change intrabar. No candle-close delay or future-bar access. |
| 23 | Change confirmation timeframes to another strictly increasing sequence | Actual chart/selected TF labels update; indicator handles are rebuilt on reinit. |
| 24 | Cross each threshold, test equality, customize colors | Below threshold gives configurable green background. Equality restores normal background. Static configured text color stays unchanged. |
| 25 | Use known M1 extrema over elapsed window; test low-first and high-first | Chronological first coordinate displays 0%, later 100%. Weekend gaps do not become a fixed candle count. New forming-bar extremes appear. M1 window membership uses bar-open timestamps; boundary-straddling minute is excluded. |
| 26 | Run many ticks/minutes; inspect chart object list and manually placed Fibonacci | One EA Fibonacci object updated in place; no duplicates; unrelated user drawings untouched. |
| 27 | Chart>=RSI1; RSI1>=RSI2; RSI2>=RSI3; then restore valid order | Clear on-chart warning even with monitor hidden; no new entries. Existing broker stops stay active; correcting configuration/reinit enables entries. |
| 28 | Consume signal, close position, restart EA and terminal while RSI0 stays oversold | Persisted CONSUMED state survives; no first-attachment repeat. Repeat with armed state, last rejected attempt bar and in-flight request. |
| 29 | Netting: existing manual/other-magic BUY or SELL; hedging: manual position and an owned position | Netting positions are never merged/modified by this EA; hedging ownership uses symbol+magic, allowing other-magic positions while still limiting this EA to one. |
| 30 | Missing/unsynchronized history, failed CopyBuffer, invalid handle, unavailable tick/OrderCalcProfit | No entry from stale/partial readings; diagnostic indicates unready history/calculation. Missing Fibonacci-only data does not disable otherwise-ready RSI trading. |

## Additional failure and boundary cases

| ID | Setup/action | Expected result |
| --- | --- | --- |
| R1 | Same scope attached to two charts | Second instance fails initialization clearly; first keeps ownership and state. Releasing first allows attachment. A stale lock after chart closure is reclaimable. |
| R2 | Timeout/connection loss after request acceptance, delayed fill | Persistent pending intent blocks duplicate submissions through subsequent bars and restart; broker evidence resolves it. Never unlock solely because a timeout elapsed. |
| R3 | Crash immediately before/after OrderSend in a controlled demo test | Restart sees intent; no ticket/evidence means lock remains. Follow documented broker verification/recovery procedure before clearing pending fields. |
| R4 | Partial fill followed by remaining live order; restart with partial remainder | Filled quantity consumes signal; unfilled RETURN remainder is canceled; failed cancellation remains pending and retries are throttled. No second market entry. IOC canceled remainder cannot cause an add-on request. |
| R5 | Accepted order later canceled/rejected with zero execution | Pending cleared only when broker terminal order state establishes outcome; signal remains armed; same-bar repeat prohibited. |
| R6 | Fill and TP/SL exit happen before EA processes its next tick | Deal/order history still proves entry; signal is consumed even with no current position. |
| R7 | Rearm while owned position open; return to oversold before exit | New signal is consumed by position block, requiring another strict-rise rearm. If exit happens before new oversold signal, entry may occur on that later signal. |
| R8 | Change chart timeframe or input, restart within rejected-attempt bar | Signal state and last bar persist under the same account/symbol/magic key; no reset to immediate first attachment. Changed timeframes revalidate. |
| R9 | Two live accounts/servers/symbols/magics; tester pass after live operation | Distinct persistence scopes; tester namespace does not alter live state. Each tester pass begins independently. |
| R10 | Attach with an existing owned position but no saved state | Startup marks consumed; no duplicate. Broker SL/TP are untouched. |
| R11 | TP or SL rounds to entry or closest price violates minimum stops | Skip with explanation, no unprotected order or widening to broker minimum. |
| R12 | Disabled symbol, short-only/close-only, disabled market/SL/TP flags, unsupported fill mode, market closed | Validation/server check rejects safely; journal records why; no new unprotected position. |
| R13 | Terminal Algo Trading off, EA permission off, account expert trading off, or Enable Trading false | No submission; visible reason. Existing positions/SL/TP are unchanged. |
| R14 | Both M1 extrema occur on one bar; flat range; no history | Omit only own Fibonacci; no invented intra-minute ordering. Trading remains independent. |
| R15 | Tied extrema, an extreme ages outside window, window crosses weekend | Earliest in-window tie wins; expired extrema replaced; no extension to collect extra bars. |
| R16 | Resize chart, change offsets/position/font, hide monitor/fibo | Stable positioning within available pixels, no object recreation per tick. Invalid-TF warning stays visible. Reinit/detach removes only this instance's objects. |
| R17 | Run >one chart bar with persistent validation error; inspect logs | Entry attempts no faster than chart bars; status messages on changes, duplicate Log messages throttled. |
| R18 | Large order tickets above double's exact integer range | Persisted high/low halves reconstruct exact ticket; history reconciliation uses ulong. |
| R19 | Gaps, spread spikes, changed account conversion rates | Invalid protections skip; actual gross/net P/L may differ from initial estimates; no claimed exact money guarantee. |
| R20 | Inputs outside numeric ranges or non-finite, zero/negative money/lots, invalid lookback/font | Initialization rejects numeric-invalid settings. Broker-specific unsupported positive volume rejects at attempt. |
| R22 | Set confirmation levels to 25/35/45; run the self-test and controlled entry cases around each level | Each RSI uses only its own threshold in entry/sizing, strict equality, journal confirmations and green row background. Main uses Entry independently. |
| R23 | Attach with default monitor settings; resize chart and adjust width/font | Default panel is 300 by 189 pixels with font 9, shorter TF labels and per-row thresholds. Status truncates with full tooltip; configured width/font and green backgrounds remain functional. |
| R21 | Full backtest with visual mode off and on | Same strategy decisions from same ticks/settings; graphics do not gate orders. No future data read. |

## Coverage limits

A broker/demo environment or a purpose-built execution simulator is required for delayed transactions, partial fills, freeze restrictions, network interruption and restart timing. Real-tick historical testing alone cannot prove these. The self-test runs no order execution and cannot establish live safety. Record skipped/unreproducible scenarios explicitly. Do not mark any test passed from source inspection or compilation.
