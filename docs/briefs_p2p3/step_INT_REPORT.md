# Step INT - integration branch integration/p72-p79 (phase 72..79)

Branch = fix/phase-C2b (73, 74, 75, 78) + merge fix/phase-B (72) + merge fix/phase-E9 (76, 77, includes H). Both merges were conflict-free at file level (no two branches touch the same file except web/ia.js and web/index.html, which only this branch edits). The real conflict was inside SQL (later phases silently overwrite earlier function bodies) and is solved by supabase/phase79.sql.

## Paste order for the owner (each file once; phase79 LAST; all are paste-twice safe)

| # | file | size |
|---|------|------|
| 1 | supabase/phase72.sql | 77.1 KB |
| 2 | supabase/phase73.sql | 51.8 KB |
| 3 | supabase/phase74.sql | 75.6 KB |
| 4 | supabase/phase75.sql | 54.2 KB |
| 5 | supabase/phase76.sql | 66.4 KB |
| 6 | supabase/phase77.sql | 20.3 KB |
| 7 | supabase/phase78.sql | 36.5 KB |
| 8 | supabase/phase79.sql | 45.2 KB |

phase79 starts with a guard that raises "phase79 needs phases 72..78 pasted first" if any of them is missing. Nothing in phase79 touches tables, data or rules; only `create or replace function`.

## Functions overwritten by a later phase (found by diffing pg_get_functiondef after every phase on a DB built 71 -> 78)

| function | phases that re-create it | tags BEFORE phase79 (order 72..78) | tags AFTER phase79 |
|---|---|---|---|
| _acct_docs(date) | 72, 74 | bos50, bos52, bos74 (bos72 LOST) | bos50, bos52, bos72, bos74 |
| production_post 7-arg core | 74 (new; 72 and 73 only changed the 6-arg) | bos73, bos74 (bos72 LOST: production_requires_cost, cost 0 = unknown) | bos72, bos73, bos74 |
| production_post 6-arg | 72, 73, 74 | thin wrapper | thin wrapper (re-asserted) |
| _r3q_l1_pnl | 72, 78 | bos78 (bos72 LOST: cogs_fallback, unknown_cost_rev) | bos72, bos78 |
| _r3q_l3_shop_pnl | 72, 78 | bos78 (bos72 LOST) | bos72, bos78 |
| recipe_cost | 73, 74 | bos73, bos74 | same (phase72 never touched it); re-asserted |
| pool_set | 74, 75 | bos75 (contains 74) | same; re-asserted |
| online_order_get, online_orders_list | 76, 77 | bos76, bos77 | same (077 already contains 076) |

Single-phase functions (survive in any order, tags checked by phase79_test T0): _p27_pl (bos50,bos72), _r3q_l2_margin (bos72), biz_daily (bos72), acct_status / acct_overview / acct_income_statement / acct_post_pending (bos72), recipe_save, recipe_copy, _recipe_read (bos73), stock_production_in (bos74; no phase72 content exists for it), online_order_deliver / online_order_status (bos77). brand_pnl and the partner profit base call biz_daily / _p27_pl, so they get bos72 numbers through them.

How phase79 was built: _acct_docs = git 3-way merge (base = phase52 definition, 72 side, 74 side); only one hunk conflicted (the production block) and was resolved by keeping both: 72's `_acct_inv_split72` split lines AND 74's `inv_finished + conversion` and `overhead_absorbed` credit. production_post core = phase74 text + the bos72 refuse block + `coalesce(av,0) <= 0`. l1/l3 = phase72 body + phase78 `union all` rows.

# যাচাই হয়েছে

* Build order phase8 ... phase71, 72, 73, 74, 75, 76, 77, 78, 79 builds clean. Applying phase79 a second time: all function hashes identical (paste-twice safe). Apply of phase79 changes exactly 4 function bodies vs the 72..78 build (_acct_docs, production_post 7-arg, l1, l3); recipe_cost / pool_set / wrapper come out byte-identical (re-assert only).
* Diff of pg_get_functiondef (a) final vs (b) expectation: final vs "72..78 without 79" differs only by the bos72 lines (production_post: 1 var, 9-line refuse block, 1 changed line; l1: 2 keys + 1 join; l3: sx cte + keys; _acct_docs: 18 lines of rounding/cost-0). Final _acct_docs vs "phase72 only" differs by only the 3 bos74 lines. This was done with a scripted diff on scratch DBs (79_before, 79_final, 79_p72, 79_no72).
* SQL suites, each on its OWN fresh final build (72..79):
  8: 107 (1 fail), 10: 307 (1), 11: 68, 12: 97, 13: 76, 14: 153, 15: 114 (1), 16: ok, 17: 147, 18: 108, 19: 94 (1), 20: 63, 21: 75 (1), 22: ok, 23: 91 (1), 24: 22, 25: 91, 26: 117, 27: 55, 28: 41, 40: 119, 41: 171, 42: 160, 43: 144, 44: 181, 45: 46, 46: 117, 47: 72 (2 fail), 48: 54, 49: 16, 50: 45, 51: 23, 52: 33, 53: 112, 54: 84, 60: 62, 61: 114, 62: 74, 70: 28, 71: 26,
  **72: 70 pass / 1 fail (branch reported 71/0), 73: 98/0, 74: 96/0, 75: 76/0, 76: 108/0, 77: 26/0, 78: 101/0, 79: 77/0** - phases 73-78 equal their own branch numbers.
* Every FAIL and why:
  - phase8 T1 "staff direct update rules", phase10 T12 "overdue", phase15 T0 "list_defs seeded", phase21 T1 "catalogue lists 12": known baseline fails, unchanged, expected.
  - phase19 T0 and phase23 T0 "no cost columns on recipe tables": expected, phase74 deliberately adds cost columns/tables (pre-phase-74 assertion).
  - phase47 T1 x2 ("role list opens it", "head management allowed + health"): expected baseline (the suite prints "70/72").
  - phase72 T0 "re-created functions kept their signatures; bos72 lines present": expected. It looks for bos72 in the 6-argument production_post; since phase74 that function is a thin wrapper and the bos72 refuse logic lives in the 7-argument core (verified present and exercised by phase79_test A1). Test left as the branch wrote it.
  - "FAILED: 0" lines in 11/12/14 are the suites' own zero counters, not failures.
* phase79_test.sql (77 checks, hand-computed): tag survival (32 function/tag pairs); production with unknown ingredient cost under production_requires_cost = refuse (cost_missing, nothing written); approval gate on (recipe_not_approved, then separate approver); overhead conversion (labour 100/batch) with material 210.024 -> unit cost 31.0024, journal Dr finished 310.02 = Cr raw 200.01 + Cr packaging 10.01 (rounding remainder on largest) + Cr overhead absorbed 100; warn mode run with unknown cost journalled only for the known part, flag cogs_missing; two-type sale COGS 68.86 = 59.15 + 9.71; report COGS 192.87 = journal 192.87 (profit_source_check difference 0); unknown-cost revenue 400 -> provisional; attribution row (internet 1200) in l1 and l3 together with the bos72 keys; switch back off = identical report. The same test run on the plain 72..78 build FAILS 20 checks, so it does detect the lost changes.
* Web: no duplicate data-act names between accounts/recipebook/costing/costsources/costattrib/inbox/salesx and any other web/*.js. ia.js got 5 rec lines (recipebook, costing, costsources, costattrib after recipes; inbox after onlineorders), index.html got 5 script tags (recipebook, costing, costsources, costattrib after recipes.js; inbox after salesx.js), copied verbatim from the step reports. Node tests one at a time: accounts 39/0, recipebook 49/0, costing 39/0, costsources 34/0, costattrib 59/0, inbox 29/0, salesx 0 failures, ia 0, nav2 0, nav 0. tests/web/lang_en_test.js (new): no Bangla characters in English titles / B.L English strings of the integrated web files (68 checked, 0 found).
* The four cost tests injected their own script tag; now that index.html has the tag they would load it twice, so each test only injects when the tag is absent (test-only change).

# পড়ে বোঝা

* phase72 changed `recipe_cost` in the brief text only; in the file it did not (checked by hash), so there is nothing to merge there.
* With conversion mode on, recipe_cost still treats a blank ingredient cost as unknown but a cost of 0 as known (phase72 changed only production_post/report rules to "0 = unknown"). Not changed here (invent nothing); the owner may want recipe_cost to follow.
* The income statement shows `overhead_absorbed` as a contra-expense (-100 in the test) until the real overhead expense is booked; this is phase74 behaviour.
* A production run with a partly known cost (flour known, sugar unknown) is still journalled for the known part and flagged cogs_missing (phase72 behaviour); only a run with no known cost waits.
* sw.js has no precache list, so inbox.js needs no entry there.
* Owner decisions untouched: no rule default was changed (production_requires_cost warn, recipe_approval_required off, cost_attrib_in_pl off, conversion mode off). Existing Bangla/English wording of any file was not edited.

# যাচাই হয়নি

* Nothing was applied to the live database; the real DB state (which phases the owner already pasted, in what order) is unknown, so phase79's effect on it is tested only on fresh scratch builds.
* The Playwright pages were run, but not on a real phone and not against a real Supabase.
* phase8..28 old suites were run only as listed; tests/sql/test*.sql legacy scripts were not run.
* Concurrent two-user behaviour of the merged production_post (locking order) is unchanged from phase74 but not re-tested concurrently.
* Web screens for phase72 figures (unknown-cost revenue on biz.js / reports.js) remain not built (phaseB report item 2).
