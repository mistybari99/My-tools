# Step Perf - report (phase110)

Branch `fix/phase-Perf` (from integration/p72-p79 fb73a6a = phases 72-104, 106-108). New files: `supabase/phase110.sql`, `supabase/phase110_test.sql`, `tests/sql/perf/*` (seed, bench, budget, equality, README). Edited: `docs/PASTE_ORDER.md` (section J). Nothing ran against a live database. Test data only.

## What phase110 does (additive, paste-twice safe, no BEGIN, no CONCURRENTLY)

1. **8 indexes first** (header: run at a quiet time, each build blocks writes to its table for a moment). The 7 tested ones plus one added after measuring: `stock_ledger (reason, made_at)`. Reason: with index 2 `(item_id, location_id, reason, made_at)` in place the planner used it for the autopost stock-move scan (`reason in (...) and made_at >= ...`) as a FULL index scan on every tick (2x slower and growing with the ledger); the extra index keeps that scan at the size of the window.
2. **Six function patches**, re-created from the LATEST bodies of this branch (all bosNN tags kept; new tag bos110 on the four it alone owns, the plain marker `perf110` on `inbox_list` and `_acct_stock_moves85` so phase103's body guard still accepts them). A check block before the patches stops the paste if one of the six carries a tag phase110 does not know (a later phase changed it).
   - `_cogs_lines72`, `_item_cost_eff88`: the one-row `_rcs88()` CTE is `AS MATERIALIZED` (it was inlined: the rule was read once per row, 143k calls for 30 days).
   - `_rcs88`: one rules lookup instead of two rule_txt() chains (same answer for every value, null, empty, missing row).
   - `rpt_agg_sql` (P5, set-based): the cost of every (sale, item) pair of the report is computed once (ledger cost of the sale's own rows when all carry a cost, else the list cost, else null; all three `report_cost_source` modes) and joined, instead of `_line_cost88()` per fact row. `_line_cost88` is unchanged. The review's "P5 = 4x" is now ~9x.
   - `inbox_list`: contact check once per place (the review's patch re-derived on the bos103 body: mask first, cut after).
   - `_acct_stock_moves85`: production / sale / untyped `issue_out` rows (reverses_id null) are dropped in the scan itself; they can never get a class. (The review's version filtered after the join; the planner could not push it down.)
3. phase105 (Sec2) and phase109 (Conc) are not on origin (only drafts in other worktrees); neither re-creates one of the six functions, so phase110 is independent of them. Section J of PASTE_ORDER lists 104-110 (105 and 109 reserved / pending).

## Results (backend CPU ms, medians of 5; seed = review seed, 60k sale lines / 184k ledger rows / 365 days)

"pre-72" = the same seed on a build up to phase71. "before" = this branch without phase110 (single run for the old slow cases). Box shared, +-20 % on small numbers.

| case | pre-72 | before 110 | after 110 | before/after | after/pre-72 |
|---|---:|---:|---:|---:|---:|
| biz_daily 30 d | 49 | 16,965 | **206** | 82x | 4.2x |
| biz_daily 365 d | 376 | 149,473 | **1,871** | 80x | 5.0x |
| _p27_pl 365 d | 370 | 143,559 | **1,844** | 78x | 5.0x |
| biz_items 30 d / 365 d | 85 / 766 | 15,625 / 151,180 | **280 / 2,829** | 56x / 53x | 3.3x / 3.7x |
| items_with_cost() | 2.3 | 185 | 6.8 | 27x | 3.0x |
| report_run item_sales 365 d (cost) | 236 | 19,564 | **2,140** | 9.1x | 9.1x |
| report_run sales_summary 365 d | 234 | 19,209 | **1,996** | 9.6x | 8.5x |
| report_run category_sales 365 d | 257 | 17,842 | **2,229** | 8.0x | 8.7x |
| _cogs_lines72 365 d | - | 153,116 | 1,994 | 77x | - |
| inventory_vs_gl(today) | - | 22,032 | **575** | 38x | - |
| unmatched_forms 30 d / 365 d | - | 2,288 / 24,780 | **26 / 183** | 89x / 135x | - |
| inbox_list(50) | - | 191 | 31.5 | 6x | - |
| _acct_docs (500 pending) | 300 | 1,242 | 490 | 2.5x | 1.6x |
| acct_post_pending idle | 282 | 1,159 | 386 | 3.0x | 1.4x |
| acct_autopost_tick idle | - | 1,108 | 424 | 2.6x | - |
| acct_autopost_tick, 500 pending | - | 2,227 | 1,048 | 2.1x | - |
| record_sale2 3 lines (4 variants) | 31-38 | 34-46 | 34-48 | ~1.0x | 1.1-1.3x |
| stock_post (4) / production_post (2) | 7-12 / 40 | 7-14 / 36 | 8-15 / 35 | ~1.0x | ~1.0x |

Budget (`tests/sql/perf/budget.py`, exit 0): biz_daily 30 d 0.21 s (<= 1 s); every year report 1.8-2.8 s (<= 5 s); sale <= 60 ms (47.7 ms worst); inventory_vs_gl 0.58 s; unmatched_forms 365 d 0.18 s. POS and stock paths unchanged. Still slower than pre-72: reports 3-5x (report_run with cost 8-9x: the per-pair cost lookup stays), `_acct_docs` 1.4-1.6x (every document since the accounting start is still re-checked every tick; suggest posting only recent documents).

Index effect (`tests/sql/perf/index_effect.py`, the target statement with / without the index): refid 209 ms / 2,978 ms; item_loc_reason 191 ms / 25,180 ms; purchase_bills id::text 532 ms / 21,143 ms (production_runs id::text 560 / 1,429); lastcost 4 / 39.5 ms; audit_log history 0.9 ms / 25,100 ms and view report 3.3 / 112 ms at 2 M audit rows; reason_made 59 / 88 ms (plus: it stops the full-index scan of index 2).

## Proof that results are identical

- `tests/sql/perf/equality.sh` (133 md5 lines: biz_daily, biz_items, _p27_pl, _cogs_lines72, items_with_cost, _item_cost_eff88, report_run x6 reports (rows / totals / columns), inventory_vs_gl, unmatched_forms, _acct_docs, _acct_stock_moves85, acct_post_pending dry, inbox_list, journal and trial balance after a real post, all three cost modes, 30 d and 365 d): **identical before / after on the seeded DB and on the e2e DBs (rec and def)**. Trial balance difference 0.00 (seed and e2e).
- `supabase/phase110_test.sql`: **45 pass / 0 fail** on a fresh build (each patched function vs its old body on fixtures in all three cost modes, the old per-row `rpt_agg_sql` join vs the new one for 12 sale/item pairs and 4 groupings x 3 modes, paste three times, unknown-tag stop).
- `tests/sql/e2e/run.sh` rec and def on a build WITH phase110: 0 FAIL (207 / 206 PASS); also 0 FAIL on the build without it.
- `tests/sql/run_all_sql.sh` (builds the PASTE_ORDER chain + phase104..110): TOTAL fail 35 = baseline 35, no new fail (7172 pass). With phase110 in the chain three old assertions are false by design (phase89e P2 / P2a, phase103 T9: a re-paste of 89 / 103 puts the older, slower text back); recorded in `tests/sql/baseline_fails.txt` (phase89e 2, phase103 1) with replacements `phase89f_test.sql` / `phase103b_test.sql` (0 fail), like phase46 / phase46b.
- Final re-check of the budget after the last edit (comments only): biz_daily 30 d 190 ms, year reports 1.7-2.5 s, sale 35-51 ms, autopost tick idle 287 ms.

## Honest limits

- phase110 re-creates 6 functions: until a later phase merges it, a re-paste of phase89 / 98 / 99 / 103 undoes them (rule in PASTE_ORDER J). `inbox_list` and `_acct_stock_moves85` are owned by phase103's text too.
- The pre-110 numbers of the 100+ s cases are single runs. The seed has no `count_adjust` / transfer rows, so the stock-move branch is covered by fixtures (phase110_test) and the e2e DB (2 rows), not by the big seed.
- Index builds: measured 0.03-1.5 s each on 184k ledger rows, 5 s for 2 M audit rows; expect 1-2 s per million ledger rows.
