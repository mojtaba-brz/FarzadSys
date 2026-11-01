# RSI Pull Up acceptance and regression plan

## Result ledger

- Main EA: MetaEditor compilation performed; final results in `compile.log`.
- Test EA: MetaEditor compilation performed; final results in `tests/compile.log`.
- Offline native MQL5 regression tests: see final counts and journals in `tests/results/`. Existing RSI pure checks, Fibonacci core, CSV, snapshots and native coordinate readbacks were executed.
- Authenticated broker monetary tests and five generated-tick trading comparisons: **RUN**, see tests/results/VERIFICATION.md.
- Real-tick run stalled and was stopped. Actual netting broker, visual renderer, live-network/crash timing and out-of-sample performance: **NOT VERIFIED**.
- Only assertions evidenced in the offline journals are passed; trading/visual/analytics scenarios remain **UNVERIFIED** until a run's report/Journal is attached. No performance or profitability claim is made.

Record for each run: MT5/build, MQ5 revision/hash, broker/server, account mode/currency/leverage, symbol specifications (point, digits, tick size, contract/profit mode, volume min/max/step/limit, stop/freeze levels, filling/execution flags), chart timeframe, inputs, date interval, modeling mode, data source, actual ticks used, observed results and log/report paths.

Use the defaults (XAUUSD M1; M5/M15/H1; RSI14 Close; levels 30; lots .01/.02/.03; TP4/SL2; Observe Only, M15 pivots3/3, minimum1.5 ATR14, history500, expiry96). Use Every tick based on real ticks with warmup history for each RSI timeframe. Follow README installation/testing instructions. For exact input sequences, use a controlled MT5 custom symbol and synthetic tick fixture or a demo broker/test environment that can reproduce the condition. Do not inject fake RSI into the production EA or disable its protection. The test-only EA independently exercises production helper functions without sending orders.

## Entry acceptance tests (original requirements 1-15)

Values below use [RSI0, RSI1, RSI2, RSI3]. Arrange an ARMED state, no blocking position/order and valid broker conditions unless specified. Run original RSI acceptance cases with FIB_DISABLED and FIB_OBSERVE_ONLY; filtered versions additionally require their selected zone.

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
| 25 | Use confirmed synthetic pivot sequences on Fibo_Timeframe | Frozen Mode A L/H and Mode B A/B/C anchors, exact formulas and activation times match v2 cases below. Rolling 24h/M1 anchors are removed. |
| 26 | Run many ticks/minutes; inspect chart object list and manually placed Fibonacci | One object per available model updated in place; no duplicates; unrelated user drawings untouched. |
| 27 | Chart>=RSI1; RSI1>=RSI2; RSI2>=RSI3; then restore valid order | Clear on-chart warning even with monitor hidden; no new entries. Existing broker stops stay active; correcting configuration/reinit enables entries. |
| 28 | Consume signal, close position, restart EA and terminal while RSI0 stays oversold | Persisted CONSUMED state survives; no first-attachment repeat. Repeat with armed state, last rejected attempt bar and in-flight request. |
| 29 | Netting: existing manual/other-magic BUY or SELL; hedging: manual position and an owned position | Netting positions are never merged/modified by this EA; hedging ownership uses symbol+magic, allowing other-magic positions while still limiting this EA to one. |
| 30 | Missing/unsynchronized history, failed CopyBuffer, invalid handle, unavailable tick/OrderCalcProfit | No entry from stale/partial readings; diagnostic indicates unready history/calculation. Missing Fibonacci-only data does not disable Disabled/Observe trading; filtered entries wait safely. |

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
| R13 | Terminal Algo Trading off, EA permission off, or account expert trading off | No submission; visible reason. Existing positions/SL/TP are unchanged. |
| R14 | Simultaneous high/low pivot, strict tie, flat range, insufficient ATR/history | No invented pivot ordering or setup; block only filtered entries, retaining RSI-only behavior. |
| R15 | Tied neighboring pivots, old candidate ages outside history, weekend gaps | Ties reject pivots; candidate history pruning never edits frozen setups; expiry counts actual completed candles. |
| R16 | Resize chart, change offsets/position/font, hide monitor/fibo | Stable positioning within available pixels, no object recreation per tick. Invalid-TF warning stays visible. Reinit/detach removes only this instance's objects. |
| R17 | Run >one chart bar with persistent validation error; inspect logs | Entry attempts no faster than chart bars; status messages on changes, duplicate Log messages throttled. |
| R18 | Large order tickets above double's exact integer range | Persisted high/low halves reconstruct exact ticket; history reconciliation uses ulong. |
| R19 | Gaps, spread spikes, changed account conversion rates | Invalid protections skip; actual gross/net P/L may differ from initial estimates; no claimed exact money guarantee. |
| R20 | Inputs outside numeric ranges or non-finite, zero/negative money/lots, invalid swing settings/font | Initialization rejects numeric-invalid settings. Broker-specific unsupported positive volume rejects at attempt. |
| R22 | Set confirmation levels to 25/35/45; run the self-test and controlled entry cases around each level | Each RSI uses only its own threshold in entry/sizing, strict equality, journal confirmations and green row background. Main uses Entry independently. |
| R23 | Attach with default monitor settings; resize chart and adjust width/font | Default v2 panel is LEFT_MIDDLE, 300 by 336 pixels with font 9 and seven added Fibonacci rows, shorter TF labels and per-row thresholds. Status truncates with full tooltip; configured width/font and green backgrounds remain functional. |
| R21 | Full backtest with visual mode off and on | Same strategy decisions from same ticks/settings; graphics do not gate orders. No future data read. |

## Coverage limits

A broker/demo environment or a purpose-built execution simulator is required for delayed transactions, partial fills, freeze restrictions, network interruption and restart timing. Real-tick historical testing alone cannot prove these. The offline self-tests run no order execution and cannot establish live safety. Record skipped/unreproducible scenarios explicitly. Do not mark any test passed from source inspection or compilation.


## v2 Fibonacci acceptance matrix

`FiboTestCases.mqh` contains controlled OHLC fixtures (bar high=sample+0.1, low=sample-0.1, timestamps 900 seconds apart). Bullish samples: `[110,108,106,100,105,110,115,120,118,116,112,115,120,125,130,126,122,119,118]`. Pivots L0 index3, H0 index7, L index10, H index14 activate A only at bar18's opening. Bearish samples: `[140,145,148,150,146,140,135,125,128,130,135,140,138,135,132,125]`. A index3, B index7, C index11 activate B only at bar15. ATR10 and minimum1.5 are used only for these fixed unit fixtures, never substituted into production indicator reads.

| v2 ID | Procedure | Expected result / coverage |
| --- | --- | --- |
| 1 | Strict candidate with three lower left/right highs | HIGH only with all six neighbors; native core test. |
| 2 | Supply only two completed right bars, then third | No early pivot; eligible after third completes; native core test. |
| 3 | Tie any neighboring high/low | That pivot rejected; outside high+low candle also rejected. Native tests. |
| 4 | Feed alternating timestamped candidates, then an older timestamp | Chronological order retained; older rejected. Native test. |
| 5 | Feed consecutive weaker then stronger highs/lows | More extreme pending candidate wins; existing setup copies unchanged. Native test. |
| 6 | Swing range at/below 1.5 ATR; zero/invalid ATR | Equality qualifies, smaller/invalid does not. Native tests; broker ATR alignment manual. |
| 7 | Alter bars beyond supplied completed index | Prior pivot unchanged; native test. Visually step tester to verify no future activation. |
| 8 | Replace candidate after setup activation | Frozen L/H/A/B/C and ATR remain unchanged until explicit new setup replacement. Native test. |
| 9 | Newer qualifying setup; invalidate; age through expiry | New ID replaces; terminal states block zone match. Native tests. End-to-end incremental/catchup logs manual. |
| 10 | Query zone before setup activation timestamp | False; native tests for both models. Reconstructed startup emits summary only. |
| 11 | HH/HL fixture, then remove HH or HL/reference pivot | Only complete bullish structure qualifies; native tests. |
| 12 | Confirm bullish fixture | Correct L->H coordinates; native math/property tests, actual renderer manual. |
| 13 | L100,H140 | F50=120,F61.8=115.28,F78.6=108.56; native test. |
| 14 | Prices on/inside/outside each A zone boundary | Inclusive lower/upper; outside false; native tests. |
| 15 | Price at L, then strictly below | Equality valid; strict break invalidates permanently; native tests. |
| 16 | Confirm bearish fixture | A high -> B low -> C high chronological; no activation before C confirmation; native tests. |
| 17 | C=A or C<=B | No bearish exhaustion setup; native tests. |
| 18 | A150,B100,C130 | E127.2=66.4,E161.8=49.1; native tests. |
| 19 | ATR10, within +/-1 of each projection; between projections | Boundary included; gap excluded; native tests. |
| 20 | At/above C; at/below E161.8-tolerance | Equal boundaries remain valid; strict breach invalidates; native tests. |
| 21 | Run Disabled on baseline dates | Same original RSI decisions, sizing, stops and safety. Generated-tick comparison passed; real-tick/out-of-sample comparison pending. |
| 22 | Repeat same ticks/inputs with Observe Only | Exact deal parity with Disabled. Include cases with missing Fibonacci history and file failures. Generated-tick comparison passed; real-tick/out-of-sample comparison pending. |
| 23 | Pullback Only with A false/true, RSI true | No entry until A zone; core mode truth table passed, trading integration manual. |
| 24 | Countertrend Only with B false/true, RSI true | No entry until B zone; core table passed, trading integration manual. |
| 25 | Both: neither/A/B/both confirmed | None/one/one/one potential entry; no double submission. Core table passed; order count manual. |
| 26 | Missing/unsynchronized history, ATR or quote | False actual matches; bypass in Disabled/Observe, block filtered modes only. Table passed; platform fault integration manual. |
| 27 | RSI valid, stay outside zones, later touch zone | Remain ARMED, then allow eligible entry; no upward crossing requirement. Generated-tick trade/CSV integration passed; live edge cases remain manual. |
| 28 | Combined signal blocked by position; then position exits | Consume eligible blocked signal; no queued trade. Missing Fib while blocked must leave ARMED. Generated-tick trade/CSV integration passed; live edge cases remain manual. |
| 29 | Reject an order, delay acceptance, partial fill, existing foreign netting position | Original bounded retry/unresolved-request/ownership/monetary protections unchanged. Money/invalid-volume/margin tests passed; delayed/partial/netting-broker execution pending. |
| 30 | Restart active/invalidated/expired setup, reconnect during same forming bar, corrupt snapshot | Anchors/ATR/tombstone persist, current bar extrema cover missed excursion, bad snapshot blocks filtered entries. Native round-trip/truncation tests passed; actual disconnect/restart/manual reconciliation pending. |
| 31 | Native object readback and visual overlay with independent price lines | Readback formulas/coefficients passed; renderer labels at H/L and E127/E161 plus shading must be inspected visually. |
| 32 | Many ticks, bar changes, replacements, show/hide and manual user drawings | Fixed EA object names, move/reuse only on state/revision changes, no manual object edits. Manual visual test. |
| 33 | Toggle RSI conditions with custom threshold/color inputs | Green background/static font preserved. Test all monitor positions/resizes. Manual visual test. |
| 34 | CSV with commas/quotes, unexecuted signal, rejection, partial deal and final exit | Native field-count/escaping/event tests passed. Broker event/order/position linkage and net reconciliation manual; empty net for unexecuted signals. |
| 35 | Replay known bars; inspect activation-time logs and identical runs | No historical zone/entry rows emitted by bootstrap, no signal before right-bar confirmation. Synthetic timing passed; full tester log analysis pending. |

### Additional v2 recovery and observation tests

- Restart with an in-flight BUY and new model settings: existing broker-side stops/recovery remain authoritative, no new order bypass.
- A live wick invalidates a setup then price recovers in the same candle: retain invalidation through restart; do not reactivate from a newer current price. Test with both Bid-priced and Last-priced symbol histories.
- Advance beyond available recovery history: expire cached setups, prune candidates and rebuild safely. No retroactive trade submissions.
- Hide both drawings and disable the code-only debug CSV constant in every mode: confirmation calculations and trade decisions unchanged. Change appearance without changing anchors.
- Debug CSV filenames are automatically distinct across account/symbol/magic scopes and modes. No export/filename inputs appear; lock/open failures do not change trading decisions.
- Close an EA position manually; delay position-deletion transaction; partial-close then full-close: deal results are distinct, POSITION_CLOSED appears only after absence, net includes history costs. Restart during closure, deduplicate by position/deal ID.
- Use PERIOD_CURRENT as Fibo_Timeframe then change chart timeframe: configuration resolves the actual timeframe and starts an appropriate model state.
- Run all five modes on identical development, validation and untouched out-of-sample segments. Check Disabled/Observe parity and collect independently simulated reports. Report count, net expectancy, profit factor, equity drawdown, win rate, holding time, confirmation frequency and denominators. No improvement claim without that evidence.

## Executed evidence and reproduction

See `tests/results/RSI_Regression_Result.txt`, `Regression_Journal.log` and core results. The offline regression script invokes production helper functions, no production trading handlers. Runtime tests deliberately corrupt a scratch snapshot to prove fail-closed handling, then remove it. Native coefficient checks do not replace visual renderer inspection. Broker-dependent monetary tests are explicitly skipped offline; the original tester EA still runs them in an authenticated environment.

The initial no-account launch failed (historical evidence in Tester_Launch.log); a later isolated demo configuration ran authenticated tests successfully. See tests/results/VERIFICATION.md for 124 offline checks, 120 self-tests in each of three symbol/currency contexts, 572 report/CSV assertions and five generated-tick reports. No real-tick, live or out-of-sample scenario is inferred from these results.


## v2.01 regression additions

- Alter a full-size snapshot without updating integrity data: reject, preserve fail-closed state, never reactivate the setup. The new test reproduced a failure before the checksum fix and passes afterward.
- Interrupt snapshot staging with an existing committed file: do not load potentially stale state; the committed file itself remains intact. Resolve the uncommitted scratch file and confirm valid recovery.
- Migrate a valid v2.00 snapshot: preserve invalidation/anchors and write the checksummed format.
- Successful order journal rows must show the captured OrderSend error (zero in the completed runs), not an unrelated previous API error.
- Explicit tester-input template prevents prior negative-test lot sizes leaking into subsequent default scenarios. Discard contaminated test runs rather than treating their zero trades as a filter result.
- Native test-only ownership adapter covers hedging own/foreign/manual positions, symbol scope, retail/exchange netting and empty positions; actual broker-netting execution remains separate.
- Cross-currency tester scenarios assert ACCOUNT_CURRENCY explicitly and run OrderCalcProfit nearest-tick checks; XAUUSD_o/USD, XAUUSD_o/EUR and EURUSD_o/USD passed.
- Report/CSV audits reconcile every realized position, verify broker SL/TP and no overlapping BUY entries, exact Disabled/Observe trade identity, appropriate filters/lot choices, completed anchor timestamps, and at most one failed attempt per M1 bar.


## Simplified inputs regression

- Confirm slippage/trading-enable/CSV-export/CSV-filename controls are absent from EA inputs. Market requests use fixed deviation 10 points.
- A fresh attachment defaults to LEFT_MIDDLE; other placement options and offsets still work.
- MT5/account trading permissions still reject disallowed submissions.
- CSV diagnostics continue through code-only settings and automatically scoped filenames during development; remove debug export at finalization while preserving recovery snapshots.
