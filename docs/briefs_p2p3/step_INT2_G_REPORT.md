# Step INT2 / G - phase89 (final function bodies) + full regression + audit re-run

Branch `fix/phase-INT2` (from `integration/p72-p79`, which holds 72-79, 80-88, 90, 91, 86). New files only: `supabase/phase89.sql`, `supabase/phase89_test.sql`, `supabase/phase72b_test.sql`, `phase73b_test.sql`, `phase76b_test.sql`, `docs/PASTE_ORDER.md`, `tests/sql/final_build.sh`, `tests/sql/final_sweep.sql`, this report. No old phase file and no old test file was edited. Nothing touched a live database; every number below comes from scratch Postgres 16 databases (socket /tmp, port 5544, names `i2_*`, dropped afterwards).

## 1. What phase89 fixes (task 1 and 2)

Method: one scratch DB built phase8..71, then phases 72..79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 90, 91 one by one; after every phase the md5 of `pg_get_functiondef` of all 1135 public functions was stored. 20 functions are changed by 2 or more phases (list below). Their `bosNN` tags were compared phase by phase.

Tags LOST in numeric paste order (real defects, all fixed by phase89):

| function | what was lost | lost by | effect before phase89 |
|---|---|---|---|
| `_sale_stock_out()` | phase82 `unit_conv_required` (refuse / red late line), plus the original Bangla wording of the unit message was re-worded to "stock" | phase83 | **this is the cause of the 4 fails of phase82_test (53/4)**: refuse mode never refuses, `off` mode still raises the yellow line |
| `_acct_docs(date)` | phase80 free-cost-item rule (item marked "cost really zero" counted as known) | phase85 | free-cost items again flagged `cogs_missing` in the journal; phase80_test failed 6 checks (80/6) |
| `_cogs_lines72(date,date,integer[])` | phase80 free-cost-item rule in the report cost query | phase88 | free-cost items again counted as "unknown cost revenue" in reports |

Also found: phase87_test T0 failed (52/1) in plain numeric order because of the same losses; with phase89 it is 53/0.
The other 17 multi-phase functions keep every tag in numeric order (`_acct_docs` 72/74 and `_r3q_l1_pnl` / `_r3q_l3_shop_pnl` / `production_post` were already merged by phase79; `_post_purchase_p13`, `stock_post` 82+87; `acct_post_pending`, `acct_status`, `inventory_vs_gl` 72+85; `recipe_approve`, `cost_rule_approve` 73/75+87; `pool_set` 74+75; `recipe_cost` 73+74; `online_order_get`, `online_orders_list` 76+77; `inbox_board`, `sales_channel_save` 76+86).

phase89.sql (176 KB, create-or-replace only; no table, rule, data or privilege touched):
* guard at the top: one marker object per phase (72..78, 80..88, 90, 91; 79 via the bos72 tag in the 7-argument `production_post`); raises `phase89 needs phases 72..88, 90, 91 pasted first (see docs/PASTE_ORDER.md); missing: <numbers>`.
* 3 merged bodies: `_sale_stock_out` = 3-way merge (base 79, 82, 83) with the original Bangla message restored; `_acct_docs` = 3-way merge (base 79, 80, 85), no conflict; `_cogs_lines72` = phase88 body + the phase80 lines (cst CTE and the lc/lq/uq filters). Lines changed carry `bos89`.
* 28 functions re-asserted byte-identical to the final numeric-order text (the 17 above plus `dup_suspects`, `urgent_alerts`, `acct_journal_post` (8-arg), `sale_return`, `online_order_save`, `stock_reconcile`, `_void_purchase_p13`, `stock_receive_transfer`, `partner_calculate`, `partner_settlement_save`, `stock_count_adjust`) so that a different paste order cannot leave an older body. A DO block drops the 7-argument `acct_journal_post` only if the 8-argument one exists.
* Checked on the final DB: applying phase89 changes exactly 3 function hashes (the three merged ones); a second paste changes none; ACL / SECURITY DEFINER / volatility / search_path of all 1135 functions identical with and without phase89; a build from the committed `tests/sql/final_build.sh` has the same overall function md5 as my build.
* `supabase/phase89_test.sql`: **64 pass / 0 fail** on the final build (50 function/tag pairs, original Bangla wording kept, hand-computed scenarios: unconverted unit refused under `refuse` while an offline replay below stock is accepted with a yellow line and stock 10-15 = -5; Water marked free: sale not flagged `cogs_missing`, card settlement document 600 = 588 + 12 present, `_cogs_lines72` unk_rev 0 / led_rev 50 under default, `item_costs` and `ledger_avg` switch, posting without error, all entries balanced, second paste = identical hashes). On the build WITHOUT phase89 it gives 55 pass / 9 fail, so it detects the defects.
* `docs/PASTE_ORDER.md`: the single canonical order (phase89 LAST), per-file needs, rules for phase 92/93 (re-check with phase89_test).

## 2. Old-test problems (task 3), without editing old test files

| old test | problem | copy | result |
|---|---|---|---|
| phase76 T1 | uses 'telegram' as the invalid kind; phase86 made it valid | `phase76b_test.sql` ('signal') | 108 pass / 0 fail (old: 107/1) |
| phase73 T4 x2 | assert the owner is refused on his own change; phase87 (owner decision) lets the owner approve, with audit row + suggestion | `phase73b_test.sql` | 98 / 0 (old: 96/2) |
| phase72 T0 | looks for bos72 in the 6-argument `production_post` (a wrapper since phase74) | `phase72b_test.sql` (7-arg core) | 71 / 0 (old: 70/1) |
| phase22 M2 x8 | fixtures delete/edit rows that phase84 now protects | already `phase22b_test.sql` from step X | 82 / 0 (old: 71/8) |
| phase21 T1 | catalogue lists 12 | `phase21b` (step X) still fails the same T1: `report_catalog2()` has 46 entries since phase24+ (baseline, identical on the <=71 build) | accepted |

## 3. Full SQL regression (task 4)

Every `supabase/*_test.sql`, each on its OWN fresh clone of a template DB, as pass/fail (NOTICE PASS / FAIL counts). Columns: A = build phase8..71 only (no 72+); B = 72..91 without 89; C = final (72..91 + 89). Sweep columns (negative stock, stock cache vs ledger, unbalanced entries, trial balance = journal lines, profit_source_check) were run on every clone after its suite.

| suite | build <=71 (without 72+) | 72..91 without 89 | 72..91 + 89 (final) |
|---|---|---|---|
| phase8 | 106/1 | 106/1 | 106/1 |
| phase10 | 306/1 | 306/1 | 306/1 |
| phase11 | 68/0 | 68/0 | 68/0 |
| phase12 | 97/0 | 97/0 | 97/0 |
| phase13 | 76/0 | 76/0 | 76/0 |
| phase14 | 153/0 | 153/0 | 153/0 |
| phase15 | 113/1 | 113/1 | 113/1 |
| phase16 | 167/0 | 167/0 | 167/0 |
| phase17 | 147/0 | 147/0 | 147/0 |
| phase18 | 108/0 | 108/0 | 108/0 |
| phase19 | 94/0 | 93/1 | 93/1 |
| phase20 | 63/0 | 63/0 | 63/0 |
| phase21 | 75/1 | 75/1 | 75/1 |
| phase21b | 75/1 | 75/1 | 75/1 |
| phase22 | 82/0 | 71/8 | 71/8 |
| phase22b | 82/0 | 82/0 | 82/0 |
| phase23 | 92/0 | 91/1 | 91/1 |
| phase24 | 22/0 | 22/0 | 22/0 |
| phase25 | 91/0 | 91/0 | 91/0 |
| phase26 | 117/0 | 117/0 | 117/0 |
| phase27 | 55/0 | 55/0 | 55/0 |
| phase28 | 41/0 | 41/0 | 41/0 |
| phase40 | 119/0 | 119/0 | 119/0 |
| phase41 | 171/0 | 171/0 | 171/0 |
| phase42 | 160/0 | 160/0 | 160/0 |
| phase43 | 144/0 | 144/0 | 144/0 |
| phase44 | 181/0 | 181/0 | 181/0 |
| phase45 | 46/0 | 46/0 | 46/0 |
| phase46 | 117/0 | 117/0 | 117/0 |
| phase47 | 70/2 | 70/2 | 70/2 |
| phase48 | 54/0 | 54/0 | 54/0 |
| phase49 | 16/0 | 16/0 | 16/0 |
| phase50 | 45/0 | 45/0 | 45/0 |
| phase51 | 23/0 | 23/0 | 23/0 |
| phase52 | 33/0 | 33/0 | 33/0 |
| phase53 | 112/0 | 112/0 | 112/0 |
| phase54 | 84/0 | 84/0 | 84/0 |
| phase60 | 62/0 | 62/0 | 62/0 |
| phase61 | 114/0 | 114/0 | 114/0 |
| phase62 | 74/0 | 74/0 | 74/0 |
| phase70 | 28/0 | 28/0 | 28/0 |
| phase71 | 26/0 | 26/0 | 26/0 |
| phase72 | n/a (phase absent: 14/43) | 70/1 | 70/1 |
| phase72b | - | 71/0 | 71/0 |
| phase73 | n/a (phase absent: 10/31) | 96/2 | 96/2 |
| phase73b | - | 98/0 | 98/0 |
| phase74 | n/a (phase absent: 15/50) | 96/0 | 96/0 |
| phase75 | n/a (phase absent: 0/12) | 76/0 | 76/0 |
| phase76 | n/a (phase absent: 7/21) | 107/1 | 107/1 |
| phase76b | - | 108/0 | 108/0 |
| phase77 | n/a (phase absent: 2/1) | 26/0 | 26/0 |
| phase78 | n/a (phase absent: 8/32) | 101/0 | 101/0 |
| phase79 | n/a (phase absent: 10/59) | 77/0 | 77/0 |
| phase80 | n/a (phase absent: 12/33) | 80/6 | 86/0 |
| phase81 | n/a (phase absent: 5/13) | 64/0 | 64/0 |
| phase82 | n/a (phase absent: 15/27) | 53/4 | 57/0 |
| phase83 | n/a (phase absent: 11/33) | 76/0 | 76/0 |
| phase84 | n/a (phase absent: 25/38) | 64/0 | 64/0 |
| phase85 | n/a (phase absent: 15/36) | 85/0 | 85/0 |
| phase86 | n/a (phase absent: 4/10) | 65/0 | 65/0 |
| phase87 | n/a (phase absent: 7/25) | 52/1 | 53/0 |
| phase88 | n/a (phase absent: 15/18) | 47/0 | 47/0 |
| phase89 | n/a (needs 72+) | 55/9 | 64/0 |
| phase90 | n/a (phase absent: 9/24) | 119/0 | 119/0 |
| phase91 | n/a (phase absent: 7/41) | 97/0 | 97/0 |
| TOTAL | | | 5699/21 |

Reading the table: "n/a (phase absent: x/y)" = the suite was run on the <=71 build only to show it is meaningless there (the phase it tests is not installed). Numbers are PASS/FAIL notices of the suite.
**Totals on the final build: 5699 pass / 21 fail over 65 suite files** (61 existing + phase72b, 73b, 76b, 89). The same 41 suites <=71 (+21b/22b) give identical results on A and C except: phase19 and phase23 (T0 "no cost columns on recipe tables": phase74 adds cost columns by design) and phase22 (8 fixture fails caused by phase84, replaced by phase22b = 82/0).

Every remaining FAIL on the final build, with cause (none is a product defect):

| suite / assertion | cause | status |
|---|---|---|
| phase8 T1 "staff direct update rules" | the build harness grants ALL on tables to `authenticated` (default privileges); RLS blocks the row but the error text is not "permission denied". Same on A. | test-environment, accepted |
| phase10 T12 "overdue 1500" | date-dependent fixture; same on A (earlier reports: known) | accepted |
| phase15 T0 "list_defs seeded ... default approval" | 3 list_defs rows seeded later with another add_rule; same on A | accepted |
| phase19 T0, phase23 T0 "no cost columns on recipe tables" | pre-phase-74 assertion; phase74 adds cost columns/tables on purpose (pass on A: 94/0, 92/0) | by design |
| phase21 T1 and phase21b T1 "catalogue lists 12" | `report_catalog2()` returns 46 entries since phase24+; same on A | accepted (stale count) |
| phase22 M2 x8 | fixtures vs phase84 protections (stock table delete/edit refused) | replaced by phase22b (82/0) |
| phase47 T1 x2 "role list opens it", "head management allowed + health" | same 2 fails on A (suite prints 70/72) | carried baseline |
| phase72 T0 | 6-arg production_post is a wrapper | replaced by phase72b (71/0) |
| phase73 T4 x2 | owner may now approve (phase87) | replaced by phase73b (98/0) |
| phase76 T1 | 'telegram' valid since phase86 | replaced by phase76b (108/0) |

So after counting the b copies in place of the old ones, the remaining distinct failing assertions are 8: phase8 T1, phase10 T12, phase15 T0, phase19 T0, phase21 T1, phase23 T0, phase47 T1 x2 - all identical on the pre-72 build or deliberate.

### Sweeps (run on the clone after each of the 65 suites)
* trial balance balanced, every account row = sum of its journal lines, no unbalanced journal entry: **0 problems in all 65 clones** (16 clones have journal entries; `acct_trial_balance` diff 0.00 in each where it could be computed; phase48 has 1 entry where the sweep's trial-balance call gave no value - the sweep did not show why; its other checks are clean).
* reports == journals: `profit_source_check` over the whole span of entries: difference 0.00 in 10 clones. Five clones show a difference and every one is explained by the check's own labelled notes, not by a mismatch: phase72 and phase72b 199.99 (`fallback_used` 200.00 catalogue-cost fallback + 0.01 rounding; ledger COGS 356.57 vs journal 356.58), phase88 30.00 (`fallback_used`, 30.00 fallback cost), phase80 66.00 (`journal_pending`: 3 documents not yet posted when the suite ended), phase53 `bad_range` (span over 400 days, call refused, not a number). The suites' own hand-computed checks (phase79: report COGS 192.87 = journal 192.87; phase85: report == journal per account) pass.
* negative stock: negative balances exist only in suites that sell without an opening (default `stock_negative_mode` = warn, audit a2-F2) or test the negative / offline-soft / override paths on purpose: 10, 19, 26, 27, 40, 44, 49, 53, 72(+b), 78, 82, 83, 85, 89 (1-4 rows each; for 72 and 78 I checked: only `sale_out` rows of fixture items that were never given an opening stock). Compared with the <=71 build: the counts of all suites <=71 are IDENTICAL (A vs C), so phases 72-91 add no negative stock to any old scenario.
* stock cache (stock_balance) vs sum of ledger: 0 differences except fixtures that write stock_balance directly: phase21 (5), 22 (2), 22b (1), 46 (1); A shows the same (22: 1 vs 2 is the phase84 fixture problem, 22b equals A).

## 4. Web tests (task 4)

IMPORTANT finding about the test setup: most `tests/web/*_test.js` (and the helper `s10_common.js`) hard-code `/home/user/My-tools/web` as the served root, i.e. the MAIN checkout (branch fix/phase-B), NOT the worktree under test. A first run in the worktree therefore tested the wrong code (and `optviews_ui_test` failed because that web has no optviews.js). I did not edit those files; I ran a copy of the committed tree (`git archive HEAD` into a scratch dir, `/home/user/My-tools` replaced by the scratch dir) one test at a time:
**73 `*_test.js` + `smoke.js` = 74 scripts, all exit code 0, 0 assertion failures** (examples: accounts 0 failures, books85 38/0, guards 35/0, inbox 47/0, integrations 15/0, ia 0, optviews 58/0, optviews_ui 0, posfail 23/0, scan 65/0, scan_pw 31/0, lang_en_test **81 English strings checked, 0 with Bangla**). `tests/web/*.png` regenerated by the tests were discarded (no churn committed).
Suggestion for a later step (not done, owner decision): make the web tests read the root from an env var.

## 5. Audit scenarios a1..a4 re-run (task 5)

The scripts in `scratchpad/audit/a1..a4/*.sql` were replayed on clones of the final DB (`i2_a1..a4`). Result with ALL SWITCHES AT DEFAULT, compared by hand on the numbers I checked: (a1) FG cost 66.1 (661/10), 77.087792 after the flour price change, void reversals restore the earlier averages; (a2) a basic sale deducts, a raw material is not sellable, negative stock is accepted in warn mode with the yellow `stock_negative` line, block mode refuses; (a3/a4) RLS / immutability / permission-denied lines come out as audited (I did not diff every line against the report). That is expected: defaults = today's behaviour. Limits: part of the scripts depend on state of the original session (a4 `tt.ctx`: 180 errors from that missing table; a1 t2/t4/t5 call a helper `q.sql` or a function that does not exist), so a4 is only partly replayable; those parts are covered instead by the hand-computed suites named below. With the switch ON I replayed one case end to end: a1-F3 - `production_requires_cost = refuse` and milk without cost: `production_post` raises `cost_missing` (DETAIL milk), nothing posted.

Finding -> status. "fixed" = a switch/feature exists and its phase suite passes on the final build (default OFF unless said, so the owner still has to turn it on = see needs-owner); "accepted" = decided as is; "needs-owner" = not built or a choice only the owner can make.

| finding | status | by (suite on final build) |
|---|---|---|
| a1-F1 recipe cost works | OK, reproduced | - |
| a1-F2 no overhead | fixed, default off; **needs-owner to choose mode per place (off/recipe/pool)** | 74, 75, 78 (96/0, 76/0, 101/0), journal 79 (77/0) |
| a1-F3 NULL cost | fixed as switch (`production_requires_cost` warn->refuse, replayed), free-cost flag; **needs-owner**: back-fill / recost not built, choose refuse | 72, 80 (86/0 with phase89) |
| a1-F4 actual yield | DB done (`p_actual_yield`); no screen sends it -> **needs-owner / UI step** | 74 |
| a1-F5 preview vs run packaging | fixed | 74 |
| a1-F6 two cost sources | fixed: one switch `report_cost_source` (default ledger_then_item_costs) | 88 (47/0) |
| a1-F7 manual/form production cost | fixed (reason required; `form_051_mode` default reference = today) **needs-owner to pick post/refuse** | 74, 83 |
| a1-F8 void/reversal | OK, no change needed | - |
| a1-F9 landed cost | not built, **needs-owner** | - |
| a1-F10 negative ingredient | fixed, default off | 82 (57/0 with phase89) |
| a1-F11 cost drill-down | server side done, no run-detail screen -> accepted for now | 74 |
| a2-F1 unit mismatch | fixed (`unit_conv_required` warn/refuse/off); needs-owner (recommended refuse once `unit_unknown_items()` = 0). This was the lost-by-phase83 rule, now restored | 82 + 89 |
| a2-F2 negative default | fixed as options (`neg_grant_log`, never-opened list); default stays warn: **needs-owner** | 82 |
| a2-F3 offline refused sale | fixed (E8 failed-card board, manager replay override, `offline_soft_stock`; pos.js regex) | 83 (76/0), 89 |
| a2-F4 return margin | fixed | 72 |
| a2-F5 COGS source | fixed (same as a1-F6) | 88 |
| a2-F6 online order gaps | fixed server (pack warn, keep price, void flag) | 77 (26/0) |
| a2-F7 packaging return | fixed as option `packaging_return_mode` (default none) | 80 |
| a2-F8 expired stock | fixed as option `expiry_sale_guard` (default off); per-line override **needs-owner** | 87 (53/0) |
| a2-F9 client_id | other user: fixed (`client_id_taken`); same user + different cart: accepted | 87 |
| a2-F10, F11 | OK by design | - |
| a3-F1 two profit numbers | fixed (`profit_source_check`, one cost switch); report difference 0.00 in sweeps | 72, 88 |
| a3-F2 return costed revenue | fixed | 72 |
| a3-F3 unknown cost silent | fixed server + accounts screen; free-cost flag restored by phase89 | 72, 80, 89 |
| a3-F4 uncosted wastage/production wait | **not built (D3)** -> needs-owner | 85 report |
| a3-F5 rounding / unbalanced | fixed (all entries balanced in every sweep) | 72 |
| a3-F6, a4-F1 GL vs stock ledger | fixed as options `acct_count_adjust`, `acct_issue_out`, transfers, purchase variance (default off); **needs-owner** to switch on + accountant to confirm accounts 5110-5140 | 85 (85/0) |
| a3-F7 opening stock | fixed option `acct_stock_opening` (off) | 85 |
| a3-F8, a4-F8 autopost | fixed in SQL (`acct_autopost_tick`, pending alert); scheduler (pg_cron) **phone-impossible, needs-owner** | 85 |
| a3-F9 locked docs | list + owner force-post done; accountant flow accepted | 85 |
| a3-F10, a4-F7 manual journal | fixed (`manual_journal_guard`, default off) | 85 |
| a3-F11 | OK | - |
| a3-F12 overhead in GL | fixed (overhead_absorbed, default off) | 74, 79 |
| a3-F13 card settlement / expense mode | fixed (`card_settle`, pay_mode) | 85 |
| a4-F2 GRN vs bill | fixed option `purchase_grn_guard` (default off) | 82 |
| a4-F3 void after use | fixed option `purchase_void_guard`, `purchase_void_payments` | 82 |
| a4-F4 form vs screen | fixed options `form_051_mode`, pairing; default = today | 83 (76/0) |
| a4-F5 expense double count | fixed (dup_suspects + link) | 83 |
| a4-F6 transit shortage | fixed options (`transit_short_mode`, GL `acct_transit_loss`) | 83, 85 |
| a4-F9 audit/no-delete on stock tables | fixed | 84 (64/0) |
| a4-F10 shadow pairing | fixed (pairing list) | 83 |
| a4-F11 ledger timing now() vs bill_date | accepted (flag only `purchase_backdate_flag`); changing the stamp would move averages/closed periods: **needs-owner** | 87 |
| a4-F12 entries post failure | accepted (count function; badge for non-approvers not built) | 87 |

Not built / only the owner can decide: a1-F4 (no screen passes the actual yield), a1-F9 (landed cost), a3-F4 (uncosted wastage/production wait), a3-F8 (pg_cron scheduler = server setup), a4-F11 (ledger timing), the same-user client_id reuse (a2-F9) and the per-line expiry override (a2-F8). Every "fixed" row keeps today's behaviour until the owner switches it on.

## যাচাই হয়েছে
* Fresh builds through the canonical order (phase8..71, 72..88, 90, 91, 89) without error; phase89 applied a second time: 0 changes; exactly 3 function bodies change versus the build without phase89; ACL/definer/volatility/search_path of 1135 functions identical.
* 65 SQL suite files, each on its own clone: 5699 pass / 21 fail (all 21 explained above); phase80 80/6 -> 86/0, phase82 53/4 -> 57/0, phase87 52/1 -> 53/0, phase89 64/0 (55/9 without the fix); new b copies 71/0, 98/0, 108/0.
* Sweeps after every suite (trial balance, journal == report with the 5 differences explained, no unbalanced entry, negative stock, stock cache), A vs C comparison; 74 node/Playwright web scripts exit 0 (run on a copy of the committed tree), lang_en_test 81/0.
* Audit scripts a1..a4 replayed with defaults (identical results) and one switch-on replay (a1-F3).
* No real person names, no secrets, no `service_role`; new text only English comments / one English guard message; the original Bangla unit message kept.

## পড়ে বোঝা
* Which numeric slot the owner already pasted on the live DB is unknown; phase89 is safe in any state because its guard checks the other phases and it only re-creates functions.
* The 28 re-asserted functions are equal to the numeric-order text by hash; if a phase 92/93 changes one of them, phase89 must be updated (rule in docs/PASTE_ORDER.md).
* The earlier mock harness (`build_fresh_db.sh`) grants everything to `authenticated`; behaviour of real Supabase grants is covered by the per-phase tests that use `set role authenticated`, not by this harness.
* Unused phase5/6/7 files and `ALL_NEW2..11` are not part of the harness order; I did not change what the owner already pasted.

## যাচাই হয়নি
* Nothing was applied to a live database; real Supabase, a phone, pg_cron, edge functions, Meta/Telegram were not exercised.
* Concurrency (two sessions) was not re-tested.
* The audit scripts of a4 (state-dependent) and parts of a1/a2 were only partly replayable; their findings are judged from the phase suites listed.
* Web tests ran against stub backends in headless Chromium, not on a phone or a real Supabase.
* `phase19b/23b` copies for the two "no cost columns" assertions were NOT made (they are true-by-design failures on any build with phase74).
* Phase 92/93 do not exist here yet; phase89 must be re-checked when they arrive.
