# KTR v1.0 implementation report

## IMPLEMENTED

New independent main EA, seven focused modules, full strategy/input documentation, all-72-case acceptance matrix, preserved source specification, portable tests and two nontrading native scripts. Files and architecture are listed in [KTR_README.md](KTR_README.md); existing RSI Pull Up files are unchanged.

Projected Ichimoku comes from completed calculation bars with shifted-buffer/OHLC checks. FIRST uses cloud reversal and/or causal Tenkan/SSA and Kijun/SSA extrema; ADDITION uses independently switched lower-TF first signals, Kijun pullback, TK cross, known flat-SSB bounce and stronger Kijun rejection. Trigger methods OR; seven independent filters AND, separately configured for first/additional entries. Neutral suppresses entry. Opposing shape episodes may coexist.

Opening deals and originating orders connect compact metadata to stable broker position identifiers and actual fill times/weighted prices. Current positive volume controls ACTIVE; absent FIRST plus live additions controls SUSPENDED. Missing/contradictory ownership blocks instead of guessing. Reversals detected from closed history close both managed directions; closure is reconciled before a short-lived trend-start candidate can execute. Pending/uncertain requests block duplicates.

Every entry has its chosen broker SL. Fractal and causal incremental ZigZag use chart history; independent closed ATR is configurable. Fixed stops use trading ticks. OrderCalcProfit plus adverse requested deviation/cost reserve sizes downward to volume step. Risk supports same, geometric and empirical completed-trend survival models. Simultaneous first orders undergo combined risk/margin preflight with honest non-atomic handling.

The daily risk manager reconstructs server-midnight balance from available cash movements, evaluates all-account current-market-to-stop exposure, and blocks unknown exposure. Actual equity breach latches an account-wide cancellation/liquidation policy on ticks, timer and trade callbacks. Unresolved closures retry and trading remains locked to next broker date. Historical chart estimates only inform the four-metric panel, never emergency liquidation.

## TESTED

- **84 passed / 0 failed** portable assertions executing production pure calculation/recovery function bodies via the supplied C++ compatibility adapter.
- Included: neutral/reversal logic, causal shape confirmation, lag/similarity/plateaus, pullback/rejection/crossover, geometric and statistical risk arithmetic, volume/tick boundaries, projected daily budget, immutable incremental ZigZag, metadata and ACTIVE/SUSPENDED/missing-ownership snapshots for both directions.
- Production pure-body compatibility build: g++ C++17, `-Wall -Wextra -Werror`.
- All six existing RSI/docs/Fibonacci source files compare byte-for-byte against baseline commit `2e69947155a343f0b3a5f207b56873ca0f18fda9`.
- No forbidden KTR persistence APIs; source brace/whitespace checks pass.
- Actual output: [tests/ktr/results/portable.txt](tests/ktr/results/portable.txt).

These are not 84 native MT5 integration tests and do not establish compilation, live safety or profitability.

## NOT TESTED

MetaEditor compilation: **not performed; compiler unavailable**. Native MQL5 scripts, indicator buffers in MT5, actual broker transactions, partial fills/closures, disconnect/restart behavior, daily rollover/liquidation, chart rendering, and Strategy Tester: **not performed**. No EX5, terminal/backtest results or profit claim are supplied. Native test procedures and all 72 original acceptance items are mapped honestly in [KTR_TEST_PLAN.md](KTR_TEST_PLAN.md).

## Assumptions

Defaults not prescribed by the task use all additions OFF, fixed-reduction additional risk, fractal stops, chart ATR, M5 lower signals and H4 higher confirmation. Plateau tolerance is a fixed tick fraction to prevent ATR changes from relabeling prior features. Flat SR uses fixed run anchors and directional break invalidation. Swing SR uses confirmed 2/2 pivots. Causal ZigZag uses Backstep stability and does not reproduce the standard final repainting plot exactly. Complete input defaults and behavior are documented in the README.

## KNOWN LIMITATION

MT5 market orders are non-atomic; opposing submissions may execute unequally. Broker history/comment loss can make exact ownership or an earlier daily equity-only breach unrecoverable without the persistence forbidden by the task. Historical equity extrema are always Estimated: tick gaps, bounded samples/history, historic conversions, swap and broker corrections prevent exact reconstruction. Full recovery of a day lock requires current breach or broker emergency execution evidence; no fictitious history is manufactured. Single-instance dedicated-account operation is required; there is no multichart/terminal coordination. RETURN-only entry execution is skipped. A disconnected/stopped terminal cannot enforce emergency closure, and gaps/slippage can exceed 5%. These limitations and native acceptance work remain explicit before live use.
