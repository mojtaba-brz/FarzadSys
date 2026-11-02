# KTR v1.0 acceptance and Strategy Tester plan

## Actual verification ledger

| Check | Status | Evidence / boundary |
| --- | --- | --- |
| Portable production core + recovery assertions | **TESTED: 112 passed, 0 failed** | `python3 tests/ktr/run_portable.py`; [recorded output](tests/ktr/results/portable.txt) |
| C++ compatibility build | **TESTED** | g++ C++17, `-Wall -Wextra -Werror`; adapts MQL array/string plumbing only, retains production pure function bodies |
| Existing RSI source/docs/Fibonacci preservation | **TESTED** | Byte comparison against commit `2e69947155a343f0b3a5f207b56873ca0f18fda9` |
| Persistence API/brace/source whitespace checks | **TESTED** | Portable runner and `git diff --check` |
| Actual MetaEditor compilation | **NOT TESTED** | Compiler absent; no EX5, native build log or claimed compile result |
| Native core script and buffer-alignment script | **NOT TESTED** | Scripts supplied; must compile and run in MT5 |
| Broker transactions, terminal restart, liquidation, visual monitor | **NOT TESTED** | Controlled hedging demo account required |
| Strategy Tester / real ticks / profitability | **NOT TESTED** | No tester or performance run was executed |

The repository baseline documents RSI self-tests but does not actually track a `tests/` directory on its current master commit. New KTR tests are explicitly tracked despite the existing broad `tests/` ignore rule. No historical RSI test result is reused as evidence for KTR.

## Repeatable local and native checks

1. Run `python3 tests/ktr/run_portable.py` from a git checkout with Python 3 and g++. This executes the production core/recovery bodies through a minimal compatibility adapter. It cannot verify MQL5 SDK calls, event scheduling or actual fills.
2. In MetaEditor compile `Kumo_Trend_Rider.mq5`, `tests/ktr/KTR_Core_Script.mq5`, and `tests/ktr/KTR_Alignment_Script.mq5`. Capture **actual** complete compiler logs, including warnings. Resolve errors and repeat portable checks after any calculation change.
3. Run the native core script. Its expected total is 112 assertions, but mark it passed only after its actual journal is saved.
4. Run the alignment script on symbols/timeframes with synchronized history. It creates no trades and checks shifted SSA/SSB plus Tenkan/Kijun against independent OHLC on eight completed bars. Failed/unready data is not a pass. Repeat for standard FX, metals and a symbol whose tick size differs from point.
5. Use a custom-symbol fixture and visual stepping to change the forming candle wildly while completed history stays fixed. Closed decisions must not change. Then complete the candle and verify exactly one new decision. Inspect native Ichimoku displacement; portable cosine tests do not establish buffer alignment.

Record MT5/MetaEditor build, commit hash, broker/server, hedging mode, account currency/leverage, deposit, symbols, contract/profit calculation mode, point/tick size, volume min/max/step/limit, stop/freeze levels, fill/execution permissions, spread, commissions, swap, server date/DST, all inputs, history interval and modeling mode with every native run. Save reports/journals under `tests/ktr/results/` without credentials/account identifiers.

## Fixture and failure procedures

Use controlled custom-symbol OHLC/ticks to reproduce cloud reversals and shape plateaus; warm up 52 bars plus shape/ATR windows before assertions. Supply at least 26 extra bars for displayed-cloud and Chikou filters. Confirm signals against independently calculated values, not just chart color.

- Construct smooth mirrored/shifted Tenkan/SSA and Kijun/SSA patterns with plateaus, lag at/beyond the boundary, short right-hand histories and near-flat movement. Observe event pivot timestamps **and** later confirmation/decision timestamps. Both pairs matching one SSA structure must log one merged FIRST candidate. Reject that candidate via risk; the later pair must not queue another attempt. Repeat across reattachment.
- Drive both directions with shape signals during one established cloud. First-position partial close must remain ACTIVE; full manual close and SL must suspend if additions remain. Close the final addition, restart, and require a new event. Verify original position identifiers against actual broker history, including closed FIRST records.
- Inject each additional method independently. For simultaneous methods, inspect the method bit mask and actual deal count. Test main and lower candles closing together and asynchronously; no duplicated addition on one decision, and cooldown uses main bars. Deliberately make lower history unavailable; main methods must remain usable.
- Run every first/additional filter separately and in combinations. Changing an additional-only filter must not alter raw first triggers and vice versa. Test all OFF. Confirm historical levels qualified **before** the test candle; break and age them and verify invalidation.
- Exercise native chart fractals at shifts 2/3 to demonstrate that a forming right candle is never used. For ZigZag, replay all chronological prefixes; confirmation cannot move into the past or mutate when later highs/lows arrive. Test gaps longer than stop history: missing causal continuity must reject rather than invent a stop.
- Test volume below broker minimum, nondecimal step, wide spread, stop/freeze minimum, disabled SL flag, long/short-only mode, directional volume limit, insufficient margin, FOK/IOC and RETURN-only entries. Independently call OrderCalcProfit at the **actual** requested stop and reserve price and compare with budget.
- Account risk: include unrelated symbols, manual positions, opposite exposure, missing SL, unknown quote/conversion and pending orders. Verify individual market-to-stop losses rather than offsetting BUY and SELL. Existing equity loss must be included once. Reject a proposed oversized order without closing existing exposure.
- For simultaneous first entries, test combined acceptance, budget/margin failure, one-direction filter/stop failure, rejection of the second request, delayed first visibility and partial fill. Joint preflight must reject both if they cannot qualify; do not assert atomic actual execution.
- Use a dedicated **demo** account to cross actual daily equity threshold between chart ticks. Timer/trade callbacks must initiate all-account closes/cancellations and lock entries. Test rejected/partial closes, an outstanding closing order, disabled trade permission, disconnect/reconnect and unresolved liquidation across midnight. Repeated cancellations must be throttled. Do not use a production account to test emergency liquidation.
- Reattach after an evidenced daily liquidation while equity has recovered; broker emergency comments should restore lock. Strip both order/deal comments and hide ticks/history to document the unavoidable reconstruction limit. Historical **estimated** minima alone must not close positions or create an exact-history claim.
- Reconstruct midnight balance with realized profit/loss, commissions, carry positions, deposits/withdrawals and account credit. Credit affects equity/cash adjustment, not account balance. Compare current equity P&L with independent account statements. Reconstruct with missing ticks, shortened broker history and initial-deposit override; inspect Estimated/Unavailable labels. Resize charts and test all four monitor corners, colors and monitor OFF. Graphics must not gate trading.

## Traceability to all 72 supplied acceptance cases

“Portable” below refers only to deterministic production calculations or snapshot fixtures. Every broker/native portion remains **NOT TESTED** until an actual MT5 journal/report establishes it. The complete original requirements remain in [KTR_SPEC.md](KTR_SPEC.md).

| ID | Required case | Current evidence / remaining validation |
| --- | --- | --- |
| 1 | Projected SSA matches independently calculated values. | NOT TESTED: native/broker/visual procedure above required. |
| 2 | Projected SSB matches independently calculated values. | NOT TESTED: native/broker/visual procedure above required. |
| 3 | `CopyBuffer()` displacement is verified. | NOT TESTED: native/broker/visual procedure above required. |
| 4 | The current forming candle never influences trading signals. | NOT TESTED: native/broker/visual procedure above required. |
| 5 | Green/red cloud transitions are detected at the correct completed candle. | Portable trend transitions pass; native calculation timing NOT TESTED. |
| 6 | Equality does not create spurious trend transitions. | Portable neutral bridge/state passes; native signals NOT TESTED. |
| 7 | Changing chart timeframe resets signal scheduling safely. | NOT TESTED: native/broker/visual procedure above required. |
| 8 | Matching confirmed valleys generate one BUY signal. | Portable matched valleys pass; actual BUY decision/fill NOT TESTED. |
| 9 | Matching confirmed peaks generate one SELL signal. | Portable matched peaks pass; actual SELL decision/fill NOT TESTED. |
| 10 | Correctly aligned patterns pass the similarity threshold. | Portable scale normalization/allowed lag passes. |
| 11 | Excessive lag rejects the pattern. | Portable excessive-lag rejection passes. |
| 12 | Low similarity rejects the pattern. | Portable same-extremum low-cosine rejection passes. |
| 13 | Flat or degenerate sequences cannot produce false scores. | Portable degenerate-vector rejection passes. |
| 14 | Plateaus produce one extremum, not repeated extrema. | Portable one-feature plateau passes; runtime deduplication NOT TESTED. |
| 15 | Confirmation timestamps are correctly delayed. | Portable right-bar timestamps pass; terminal scheduling NOT TESTED. |
| 16 | No historical look-ahead or future-bar references. | Portable shape and ZigZag prefix invariance passes; native history indexing NOT TESTED. |
| 17 | Duplicate matches on the same SSA extremum merge. | NOT TESTED: native/broker/visual procedure above required. |
| 18 | Opposite-direction first entries are possible regardless of cloud color. | NOT TESTED: native/broker/visual procedure above required. |
| 19 | One BUY and one SELL episode can coexist. | Portable independent BUY/SELL snapshot recovery passes; actual hedging execution NOT TESTED. |
| 20 | Two BUY episodes cannot coexist. | Portable overlapping BUY identity rejection passes. |
| 21 | Two SELL episodes cannot coexist. | Portable overlapping SELL identity rejection passes. |
| 22 | First position closure with remaining additions causes SUSPENDED. | Portable closed-first/live-addition snapshot becomes SUSPENDED. |
| 23 | Partial first-position closure does not cause SUSPENDED. | Portable positive partial FIRST remains ACTIVE. |
| 24 | Suspended episodes reject all entry signals. | Portable SUSPENDED classification passes; execution gate NOT TESTED. |
| 25 | After the final episode position closes, state becomes IDLE. | Portable empty episode transitions IDLE. |
| 26 | Starting another episode requires a genuinely fresh first-entry signal. | NOT TESTED: native/broker/visual procedure above required. |
| 27 | A cloud reversal closes both directions. | NOT TESTED: native/broker/visual procedure above required. |
| 28 | Existing broker positions reconstruct correct episode states after restart. | Portable broker-snapshot helper passes; real broker/deal reconstruction after restart NOT TESTED. |
| 29 | Each of the five methods independently triggers the intended direction. | NOT TESTED: native/broker/visual procedure above required. |
| 30 | Multiple methods on the same event cannot create duplicates. | NOT TESTED: native/broker/visual procedure above required. |
| 31 | Lower-timeframe signals use completed candles. | NOT TESTED: native/broker/visual procedure above required. |
| 32 | Kijun pullback and Kijun rejection are distinguishable. | Portable pullback/rejection distinction passes. |
| 33 | Flat SSB levels are identified before they are used. | NOT TESTED: native/broker/visual procedure above required. |
| 34 | Cooldown works across multi-timeframe signals. | NOT TESTED: native/broker/visual procedure above required. |
| 35 | Additional entries are rejected when the episode is not ACTIVE. | NOT TESTED: native/broker/visual procedure above required. |
| 36 | First-entry and additional-entry filters are independent. | NOT TESTED: native/broker/visual procedure above required. |
| 37 | Enabled confirmations use logical AND. | NOT TESTED: native/broker/visual procedure above required. |
| 38 | Enabled entry methods use logical OR. | NOT TESTED: native/broker/visual procedure above required. |
| 39 | All confirmations OFF leaves raw signals unchanged. | NOT TESTED: native/broker/visual procedure above required. |
| 40 | Higher-timeframe and Chikou checks use historical information causally. | NOT TESTED: native/broker/visual procedure above required. |
| 41 | Price-relative-to-Kumo confirmation does not change trend identification. | NOT TESTED: native/broker/visual procedure above required. |
| 42 | Confirmed fractal distance rule works for BUY and SELL. | NOT TESTED: native/broker/visual procedure above required. |
| 43 | Fractal SL buffer is applied outside the fractal. | NOT TESTED: native/broker/visual procedure above required. |
| 44 | ZigZag developing swings are never treated as confirmed pivots. | Portable incremental ZigZag prefix tests pass; native stop use NOT TESTED. |
| 45 | ZigZag confirmed-pivot timing is causal. | Portable immutable confirmation timing passes; native replay NOT TESTED. |
| 46 | Fixed-distance SL respects tick size. | Portable tick rounding passes; broker method integration NOT TESTED. |
| 47 | Broker stop restrictions are handled safely. | NOT TESTED: native/broker/visual procedure above required. |
| 48 | `OrderCalcProfit()`-based lot sizing respects requested account-currency risk. | Portable risk-to-volume arithmetic passes; actual OrderCalcProfit currency conversion NOT TESTED. |
| 49 | Rounding never increases risk. | Portable volume floors pass. |
| 50 | Invalid stop or insufficient minimum volume prevents entry. | Portable below-minimum skip passes; native stop/volume/margin preflight NOT TESTED. |
| 51 | Initial risk defaults to 2%. | NOT TESTED: native/broker/visual procedure above required. |
| 52 | Additional-entry risk models work independently. | Portable geometric reduction and empirical probability pass; broker sizing modes NOT TESTED. |
| 53 | Statistical trend-end estimation excludes future data. | Portable conditional-duration sample arithmetic passes; native market replay NOT TESTED. |
| 54 | Insufficient historical observations trigger documented fallback. | NOT TESTED: native/broker/visual procedure above required. |
| 55 | Projected daily risk includes existing positions and proposed positions. | Portable projected-equity boundary cases pass; actual all-account exposure NOT TESTED. |
| 56 | Opposite BUY/SELL exposure is evaluated conservatively. | NOT TESTED: native/broker/visual procedure above required. |
| 57 | Simultaneous first-entry signals are both rejected if combined risk is insufficient. | Portable budget boundaries pass; joint submission/partial execution NOT TESTED. |
| 58 | Hard 5% daily equity loss initiates liquidation immediately. | NOT TESTED: native/broker/visual procedure above required. |
| 59 | No new positions are opened while liquidation remains unresolved. | NOT TESTED: native/broker/visual procedure above required. |
| 60 | Trading remains locked until the next daily reset. | NOT TESTED: native/broker/visual procedure above required. |
| 61 | Daily reset uses broker-server calendar boundaries. | NOT TESTED: native/broker/visual procedure above required. |
| 62 | Restart with no positions does not replay old entries. | NOT TESTED: native/broker/visual procedure above required. |
| 63 | Restart with an ACTIVE episode restores ownership and position roles. | Portable original FIRST and addition snapshot recovery passes; actual restart NOT TESTED. |
| 64 | Restart with a SUSPENDED episode does not reactivate it. | Portable SUSPENDED snapshot remains suspended; actual restart NOT TESTED. |
| 65 | Broker SL or manual closure of the first position is reconstructed correctly. | Portable absent/partial FIRST cases pass; real broker SL/manual deal history NOT TESTED. |
| 66 | Incomplete episode ownership does not create duplicate orders. | Portable missing metadata/first history blocks; unknown network request integration NOT TESTED. |
| 67 | Daily opening balance is reconstructed where broker history permits. | NOT TESTED: native/broker/visual procedure above required. |
| 68 | Current equity P&L uses the specified daily and initial baselines. | NOT TESTED: native/broker/visual procedure above required. |
| 69 | Historical minimum equity calculations report their completeness accurately. | NOT TESTED: native/broker/visual procedure above required. |
| 70 | Missing tick history cannot silently produce falsely exact drawdown. | NOT TESTED: native/broker/visual procedure above required. |
| 71 | Monitoring remains display-only. | NOT TESTED: native/broker/visual procedure above required. |
| 72 | Existing RSI Pull Up behavior and tests remain unchanged. | All six existing EA/docs/Fibonacci files byte-identical to baseline; existing native test files are absent from tracked master. |

## Strategy Tester controlled comparison

Use a hedging tester configuration and identical symbol history, account currency, leverage, starting balance, spreads/costs, modeled execution, session and tick source for each comparison. Prefer **Every tick based on real ticks**, especially for intrabar emergency liquidation. Use a sufficiently long warmup and record missing history/indicator readiness. Generated ticks or OHLC-only runs cannot establish intrabar emergency behavior.

Run one-factor comparisons, retaining an unmodified baseline preset:

| Component | Required runs |
| --- | --- |
| First entry | Trend Start / Shape Similarity / Either |
| Shape patterns | Tenkan valleys, Tenkan peaks, Kijun valleys, Kijun peaks, combined |
| Additions | All OFF, each of five individually ON, all ON |
| Confirmations | Both categories all OFF; each first-only filter; each additional-only filter; selected combinations |
| Stops | Fractal / causal ZigZag / fixed ticks |
| Addition risk | Same / fixed reduction / trend-end probability; include minimum-sample fallback |

Use chronological in-sample and untouched out-of-sample intervals; never select defaults solely by one optimized historical interval. Save presets and exact revision with each report. Separate BUY/SELL, FIRST/ADDITION and countertrend-shape groups using opening order/deal metadata and stable position identifiers; do not infer FIRST from whether another position is currently open. Link closed profit, commission, fee and swap back to the opening position identifier. Partial exits belong to that same position and episode.

Report: executed trade and episode counts; win rate; net P&L; average trade profit/loss; profit factor; maximum equity drawdown (conventional tester metric **separately** from the initial/day-baseline panel metrics); maximum daily loss; expectancy; exposure duration; FIRST versus ADDITION contribution; BUY versus SELL; countertrend shape performance. Include failed orders, skipped events, fallback counts and history completeness. Never describe a missing or stalled real-tick run as successful. No performance result is currently available.

## Capacity-log regression follow-up

Run `python3 -u tests/ktr/run_submission.py`. The existing 112 pure checks pass, followed by **21 passed / 0 failed** submission-control cases with explicitly stubbed broker/indicator dependencies. Cases cover no signal, failed confirmation/preparation, occupied first-entry direction, zero opening balance, actual daily-risk failure with independently expected diagnostic amounts, margin failure, unassessable existing exposure, combined pair rejection, and accepted single/pair paths. The function body is extracted from production `Execution.mqh`, not reimplemented in the harness.

Native follow-up remains NOT TESTED: reproduce the reported 2026-10-01 01:01 tester decision with the same preset/account configuration; confirm no capacity warning for absent candidates. For a genuine candidate, save the specific detailed baseline/risk/margin line. Test initial funding on the first tester day separately from a positive opening balance on subsequent server days. Do not change the 5% cap to suppress the message.

## Addition and reversal regression follow-up

The pure suite covers lifetime filled-addition caps, fresh-method latches, full-main-candle cooldown excluding a partial fill candle, and trading-session intervals/overnight carry. The stubbed harness now extracts both production `KTRSubmitCandidates` and `KTRFinishReversal`: explicit broker/time/session stubs verify closure barriers, within-bar deferral, session reopening, no duplicate submission, stale expiry, direction skips and retained risk/broker rejection consumption. **112 pure assertions + 21 stubbed cases pass.** This is not native MT5 broker evidence.

Native tests still required: compare the original preset with cap 3/fresh ON; stopped-out additions must still count toward the cap after restart. On M5 with cooldown 1, an addition at 09:29 must not add at 09:30; after a full 09:30-09:35 candle a fresh event may qualify. Verify repeated touches cannot add each candle, independently fresh methods still work, and lower-TF events respect the shared cap/cooldown. Test scheduled closure/reopen inside the eligible signal bar, expiry into the next bar, delayed closing transactions, absent session metadata, holidays, first-day zero baseline, permission and minimum-volume diagnostics. Compare logged forward-cloud values with the correct native indicator location. Revised native build/rerun here: NOT TESTED.

Tester capital regression: pure cases check initial 1000 funding reconstructs first-day B_day 1000, later same-day cash movements do not change that 1000 baseline, normal later-day loss reconstructs opening balance by the original rule, and missing verified initial funding cannot invent a positive balance. Native first-day acceptance must confirm the initial-funding record and baseline log; tester-only branching/history qualification remains unverified in MT5 here.
