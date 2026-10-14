# Step R (phase88) - ONE cost source for every report (a1-F6, a2-F5, a3-F1; QA_COVERAGE item 5)

Files: supabase/phase88.sql, supabase/phase88_test.sql, this report. No web file changed (the rule shows in the existing owner rules screen from the `rules` table).
Branch fix/phase-R from integration/p72-p79. Paste after 84. Guard raises "phase88 needs phases 72..79, 82, 83 and 84 pasted first". Additive, paste-twice safe (one rule, helpers, create or replace only, no data change).

## What it does
* Owner switch `report_cost_source`: `ledger_then_item_costs` (DEFAULT) | `ledger_avg` | `item_costs`.
  - ledger_then_item_costs: cost of the units sold from the stock ledger (what the journal books); typed item_costs only for quantity with no ledger cost (shown as an estimate, `fallback_cogs`).
  - ledger_avg: ledger only; no ledger cost = UNKNOWN. item_costs: typed cost only (old biz_items / report-builder behaviour).
  - The journal (GL) always uses the ledger and is NOT switched; `profit_source_check` shows report vs journal.
* `_cogs_lines72` re-created with the switch, so biz_daily, _p27_pl, l1/l2/l3, brand_pnl, partner base, profit_source_check, acct_income_statement follow it (unchanged numbers on the default).
* Moved onto the same source: `biz_items` (via _cogs_lines72), report builder cost measures (`rpt_agg_sql` now joins `_line_cost88(sale, item)`; cogs/gp/gp_pct/costed_net/uncosted_pct in item_sales etc.), `items_with_cost` (effective current cost: stock-balance average, typed as fallback).
* Unknown is not 0: biz_items cogs = NULL when part of an item's sales has no cost; builder cogs stays blank; items_with_cost has no row for an item without cost.
* New (cost-grant holders only, closed to anon): `item_cost_status88()` (item, cost, source, cost_missing), `biz_items_cost88(from,to,loc)` (cogs, fallback_cogs, unknown_cost_rev, cost_missing). Internals `_rcs88`, `_item_cost_eff88`, `_line_cost88` revoked from the browser.
* Re-created from the LATEST definitions, only bos88 lines changed, older tags kept (bos14 in biz_items / rpt_agg_sql comments; biz_daily, _p27_pl, _acct_docs, production_post not touched, bos72/74/79/82/83/84 intact - checked by T0).
* Cost secrecy, RLS, grants unchanged (biz_cost_ok / view_cost gating kept; ACLs of re-created functions preserved).

## DEVIATION to read
"Default = today's behaviour" cannot hold for every screen: before this step biz_daily used ledger-first while biz_items / builder / items_with_cost used typed cost only. Default = ledger_then_item_costs (the journal-consistent behaviour of the main P&L). So on the default, biz_items, the report builder and items_with_cost CHANGE wherever a ledger cost differs from a typed cost (that is the bug). To get the old numbers on those screens set `item_costs` (this also switches biz_daily to typed cost).

# যাচাই হয়েছে
* Fresh build 8..84 + 88 clean; phase88 applied twice, no error. phase88_test: 47 pass / 0 fail (hand-computed: Cake ledger 70 vs typed 60, Mango ledger only, Typed typed only, Nothing no cost; sale 510; journal COGS 260). Same item cost equal in report builder, biz_items, biz_daily and journal COGS (Cake 140 on all, ledger_avg total 260 = journal 260); item_costs mode 150, journal still 260; ledger_avg unknown revenue 70 and cogs blank/NULL not 0; switch null = default = identical numbers; secrecy: plain staff gets no cost list, no builder cogs, biz_items_cost88 refused, internals "permission denied"; cost-grant holder sees them.
* Regression: every older suite on its own fresh build, once without and once with phase88: fail lines IDENTICAL in all 52 suites (diff empty). Known baseline fails unchanged: phase8 T1, phase10 T12, phase15 T0, phase19 T0, phase21 T1, phase22 (8, phase84 fixtures), phase23 T0, phase47 T1 x2, phase72 T0 (70/1). phase73..79: 98, 96, 76, 108, 26, 101, 77 all 0 fail; phase83 76/0; phase84 64/0.
* phase82 on the full build: 53 pass / 4 fail, same 4 on the build without phase88 (it was written on 73-78 only; not caused by this step, not investigated).

# পড়ে বোঝা
* `_line_cost88` uses the ledger total of the sale+item divided by the units on the sale lines, so qty x cost = the journal figure even when the sale unit differs from the base unit. Per-row function call in the report builder: fine for the 366-day limit sizes tested here; not load-tested.
* In the builder a line whose ledger rows are only partly costed uses the typed cost for the whole line (ledger_then) or is unknown (ledger_avg); `_cogs_lines72` splits by quantity instead, so these two can differ slightly in that partial case only.
* The builder `line` source has no returns, biz_items has no returns (as before); biz_daily nets returns (rule). So equality across screens is for sales without returns.
* items_with_cost feeds web/items2.js (cost column). It now shows the effective cost, so a screen that edits the typed cost will show the ledger average beside it; no web text was changed.

# যাচাই হয়নি
* Nothing applied to the live DB; real state unknown. No web screen shows `cost_missing` / `item_cost_status88` / `biz_items_cost88` yet (no UI built, to avoid touching files edited by other agents).
* Performance on a large real ledger; concurrent use; real phone.
* Journal-side gaps (a3-F3 NULL cost never back-filled) are not changed here.
