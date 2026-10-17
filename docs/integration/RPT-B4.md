# Integration note RPT-B4: production capture and reports, targets and KPI, capacity and labour, factory vs retail

Branch `rpt-b4` (base 47ba1e5). Requirements: `docs/REPORTS_AUDIT_1.md` (packages R3, R4, R5, R8, R9; items #7, #9, #10, #24, #33, #40, #43, #44, #45, #48, #49, #50, #51, #52, #53, #55). Test data only (`test_*`). Nothing was pasted into any live database; tests ran on a local throwaway Postgres 16.

SQL numbers **phase404 to phase416** (414 is not used; 417-419 are reserved and empty). Paste in this order after phase 99. Each file is paste-twice safe, no earlier phase file is edited, **no shared function is re-created or hooked**, `production_post` is not touched. Needs phases 8 to 99 only: nothing of R1/R2/R7 (phases 400-403) or of the traceability package (phases 430-436) is needed or touched.

New files: `supabase/phase404.sql` .. `phase416.sql` and `phase404_test.sql` .. `phase416_test.sql` (no test for 414), `tests/sql/rb4_fixture.sql` and `rb4_fixture2.sql`, `web/rb4common.js`, `web/prodplan.js`, `web/prodreports.js`, `web/targets.js`, `web/capacity.js`, `tests/web/rptb4_test.js`, `docs/integration/RPT-B4_info.json`, this note. Edited (additive): `web/ia.js` (4 records), `web/index.html` (one line of 5 script tags after `twofa.js`), `web/ownerboard.js` (one widget, `target_vs`), `docs/BUILD-LOG.md`.

## 1. What each phase does
| Phase | Package | Content |
|---|---|---|
| 404 | R3a | tables `production_plans`, `production_orders` (numbered by the system, not a paper form code), `production_run_links`, `production_issue_actual`, `production_loss`; helpers `_rb4_prod_view`, `_rb4_prod_entry`, `_rb4_day`, `_rb4_today`, `_rb4_range`; RLS and audit triggers |
| 405 | R3b | entry functions `prod_plan_add / cancel`, `prod_order_add / close / cancel`, `prod_run_link`, `prod_actual_issue_set`, `prod_loss_add / void`, read side `prod_run_detail` (blind: the booked quantity of a line is returned only after the real quantity is saved), `prod_runs_recent` |
| 406 | R4a | `rb4_plan_vs_actual` (#40), `rb4_order_status` (#52), `rb4_dispatch_recon` (#53) |
| 407 | R4b | `rb4_consumption_vs_recipe` (#44), `rb4_cost_variance` (#33 #43 #55: price / usage / yield split, adds up exactly) |
| 408 | R4c | `rb4_run_yield` (#45), `rb4_losses` (#49), `rb4_wastage_dim` (#50 batch and run dimension) |
| 409 | R5a | tables `sales_targets`, `kpi_snapshots`; grant `sales_target_manage` (nobody but the owner by default); settings `kpi_alert_sales_drop_pct`, `kpi_alert_discount_pct`, `kpi_alert_void_n` (all blank); `sales_target_set / retire / list` |
| 410 | R5b | `rb4_target_report` (#9 #24), `kpi_snapshot_take`, `rb4_kpi_trend` (#10 trends and alerts) |
| 411 | R5c | `rb4_target_tile` for the owner board |
| 412 | R8a | tables `production_lines`, `capacity_ratings`, `production_labour`, column `production_run_links.line_id`; grant `capacity_manage`; `production_line_set / list`, `capacity_rating_set / retire / list`, `prod_labour_add / void / list`, `prod_run_line` |
| 413 | R8b | `rb4_labour_productivity` (#48), `rb4_capacity_utilization` (#51) |
| 415 | R9a | settings `transfer_valuation_basis` (none / cost / price_pct, default none) and `transfer_price_pct` (blank), helper `_rb4_transfer_value` |
| 416 | R9b | `rb4_factory_vs_retail` (#7), `rb4_log_export` (audit line before the CSV of every new report) |

## 2. Settings, grants and defaults (everything new is OFF, blank or safe)
| Key | Default | Meaning |
|---|---|---|
| `kpi_alert_sales_drop_pct` / `kpi_alert_discount_pct` / `kpi_alert_void_n` | blank | no alert of that kind; the KPI screen says "limit not set" |
| `transfer_valuation_basis` | `none` | the factory-vs-retail report says "not valued" (today: no value exists at all) |
| `transfer_price_pct` | blank | with `price_pct` and a blank number the report says "percentage not set"; no value is guessed |
| grant `sales_target_manage` | nobody but the owner | who may set targets |
| grant `capacity_manage` | nobody but the owner | who may set lines and rated capacity |
Entry of plans, orders, real use, loss and labour reuses the existing grant `stock_production` (orders may also be raised by the requesting outlet's `stock_transfer` staff). Reading reuses the existing report / recipe rights (`report_stock`, `_recipe_read`, `report_sales`, `report_pos`, `view_reports`); money columns need the cost right (`_cost_ok`). No role was given a new grant.

## 3. Hook sites
- **No SQL hook.** No shared function changes behaviour. Without any other package nothing breaks and nothing else changes.
- `tests/sql/ORDER.txt`: **not edited** (the file is also read by the restore-drill tooling). Add `phase404 phase405 phase406 phase407 phase408 phase409 phase410 phase411 phase412 phase413 phase415 phase416` after the last phase of the owner paste order (after 400-403 and 430-436 if those are pasted; the order among them does not matter, this package needs only phases 8-99).
- `web/ia.js`: `prodplan`, `prodreports`, `capacity` (group factory; `prodreports` also stock and reports, `capacity` also reports) and `targets` (group dash, also sale and reports). Placement follows the audit: #40-#43 #45-#49 #51 #52 #55 factory, #44 #50 #53 stock, #7 #9 #10 dashboard. No route was removed or renamed.
- `web/index.html`: `rb4common.js` must load before the four screens; it is the last block of script tags.
- `web/ownerboard.js`: widget kind `target_vs` (group sales). It is not on any board until the owner adds it. A server without phase 411 hides it (the board's existing "source not installed" rule).
- Optional, not done because `web/recipes.js` belongs to another package: after a production run is posted the production screen could show a link to `#/prodplan/run/<run_id>` ("record real use, loss and labour"). One line: `location.hash = '#/prodplan/run/' + res.run_id`.
- Optional scheduler: run `select public.kpi_snapshot_take();` once a day after `notify_scan` with the same scheduler account (it is accepted for that account); the screen also has a "Take snapshots" button for the owner and the sales-report holders. [unverified: pg_cron on the owner's plan]

## 4. Interaction with the other report packages (read-only look; nothing was merged)
- **Actual yield (R6 of the traceability brief):** that package makes the production screen send `p_actual_yield`. This package reads `production_runs.yield_actual / yield_std / yield_base` only; it never sends or changes a yield. Its own `yield_report` (#78) and this package's `rb4_run_yield` (#45) show the same quantity: keep one screen in the end (`prodreports` tab Yield already has the owner limit note, the not-captured states and the drill-down).
- **R2 (phase401) "measured" definition:** its `f3_raw_vs_recipe` calls an issue "measured" only when a stock movement was posted after the automatic issue. The real use captured here is a **record, not a stock movement** (see section 6), so `f3` will keep saying "not captured" for runs that only have a record. The reports of this package (`rb4_consumption_vs_recipe`, `rb4_cost_variance`) read the record. If the owner wants one source, `f3` can be pointed at `production_issue_actual` in a later hook.
- No table, function or setting name collides with phases 400-403 or 430-436 (prefixes `prod_`, `production_`, `rb4_`, `capacity_`, `sales_target_`, `kpi_`; the other packages use `rb3_`, `rptb1_`, `trace_`, `recall_`, `stockout_`).

## 5. Owner rules kept
Reports are open to the existing report grants (no new OFF switch). Matched by purpose and extended: the wastage list (`wastage_reasons`) is reused for reject / rework reasons; the item price list (`item_costs`) is the standard price; `production_runs` fields are reused for yield; `stock_wastage.batch_id` gives the wastage batch dimension; `biz_daily`'s cost source (`_cogs_lines72`) gives gross profit. A missing figure is "data not captured: <field>" naming the field, never 0 and never an estimate (every report has a note and a status for it). No limit, target, price or percentage is invented: alert limits, the transfer percentage and every target are blank until the owner enters them. Money-affecting behaviour: none changes a booked figure; the valuation setting changes only one report and defaults to today's behaviour. New capture is digital entry screens only; the paper form code is "to be given by owner" (said on every entry screen). Every capture table has an audit trigger; voids and retirements need a reason and nothing is deleted. Counts are blind: the recipe quantity of an ingredient line is not sent to the screen until the real quantity of that line is saved. Every CSV writes an audit line first (`rb4_log_export`, same rule as `log_page_export`); a refusal means no file.

## 6. Decisions the owner has to take (nothing was decided for him)
1. **Real use is a record only.** It does not post a stock correction. Posting the difference (extra use out of stock, less use back in) would change stock and journals and needs a setting and the accounting rules; it was not built. Until then an extra use is corrected through the stock count.
2. `transfer_valuation_basis`: stays `none` until he picks `cost` or `price_pct` (and, for the second, types the percentage).
3. The three KPI alert limits (blank).
4. Who holds `sales_target_manage` and `capacity_manage` (only he does now).
5. Rated capacity is "batches a day and working days a week" per place or line; if he prefers another unit (kilos, hours) it needs a different rating table.
6. The standard price for the price variance is the existing price list (`item_costs`). An ingredient without a list price has no price variance and no usage variance valued at the standard.
7. Paper form codes of the new entry screens (plan, order, real use, loss, labour, targets, lines, rating).

## 7. Not confirmed
Live Supabase, a real phone, the CSV in a real spreadsheet, pg_cron for the snapshot, the owner-board tile on a live board, the interaction with phases 400-403 and 430-436 (not present in this branch; section 4 is from reading them). The reason picker offers only the active options of the existing list `wastage_reasons`; a reason that is not in the list is added in Lists first (the screen links to it): there is no free-text reason. `rb4_dispatch_recon` shows the balance of today for "on hand", not at period end. The factory-vs-retail report does not net the shop profit with a transfer value by design.
