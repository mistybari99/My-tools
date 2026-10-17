# Reports audit 1 (sections 1-4)

AUDIT DONE, BUT docs/REPORTS_AUDIT_1.md WAS NOT WRITTEN, AND NOTHING WAS COMMITTED. My Write call for that file was refused by the harness ("Subagents should return findings as text, not write report files"). I did not work around the refusal. The worktree is clean (only the audit scratch work exists, outside the repo). The full audit is below so you can save it as docs/REPORTS_AUDIT_1.md and commit. I did not run check_no_demo_leak.py (no file written); the text uses only neutral test_* wording.

HOW IT WAS CHECKED
- Read: web/ia.js, reports.js, reports2.js, ownerboard.js, dash.js, biz.js, costing.js, recipes.js, stockx.js, forms_factory.js, plus the SQL of all three report engines and the latest definitions (phase72/79/86/92/93).
- Ran: a local throwaway Postgres 16 (port 5620, data dir /var/lib/postgresql/audit5620, outside the repo), built from tests/sql/ORDER.txt (phase8 to phase99). It is now stopped. The dry run used neutral test_* data across the whole chain: opening stock, purchase, two production runs (the second with a typed short yield), factory-to-showroom transfer received 1 kg short, 5 sales (retail, discounted, quick, wholesale with price override and credit, one voided), one cash refund return, one wastage. Then I called every relevant report. The scripts are in the session scratchpad, not the repo.
- Live DB state (from docs/SUPABASE_READONLY_AUDIT.md): stock_ledger 0 rows, production_runs 0, purchase_bills 0, 10 test sales. Today every cost, production and stock report would have no source data.

STATUS COUNTS (55): IMPLEMENTED 27 (14 of them with a known defect flag D1/D2/D3), INCOMPLETE 18, UNAVAILABLE 9, UNVERIFIED 1.

REPORT ENGINES
- Engine 1: report_run, phase9.sql:517-574 (sales, POS, cash, customers).
- Engine 2: report_run2, phase21.sql:80-90 (wastage, stock, expense).
- Engine 3: table report_defs3 (phase24-27: l1_pnl, l2_margin, l3_shop_pnl, f1_production, f2_yield, f3_raw_vs_recipe, k3_store_ledger, q3_complaints, s10_orders, x5_staff_trend).
- One viewer (reports.js:149-475) gives CSV and Print/PDF, tap-row drill-down on engine-1 grouped reports only, compare against the previous period, last week or last year, and a phone layout with a sticky first column.
- These pages have no CSV: biz, brandpnl, discounts, owner, home. Engine-3 raw reports have no drill-down.

DEFECTS FOUND (flags used in the matrix)
- D1: engine-1 sales reports ignore returns (rpt_bill/rpt_daily/sales_fact, phase9.sql:135-212). On the dry-run day, Sales summary, pos_day_close and item_sales show net 4,220 (item qty 9). The dashboard sales_summary() (phase23.sql:220), biz_daily (phase72.sql:110), l1_pnl and l2_margin show 3,820 (qty 8). The rule reports_net_of_returns (default true) is honoured by the later functions but not by engine 1.
- D1b: pos_day_close expected_cash (phase9.sql:748-749 = cash_in + cash_collections) ignores cash refunds. A 400 cash refund was paid out, yet expected_cash stayed 2,200 (should be 1,800). Money-critical.
- D2: two cost bases for gross profit. Engine 1 uses item_costs (typed price list, phase9.sql:495-500). l2_margin and biz_daily use the stock-ledger cost (_cogs_lines72, phase72.sql:55). For the same item, item_sales shows GP "-" and uncosted 100%, while l2_margin shows margin 2,550.82 (83.71%). biz_items cogs also uses item_costs only. The "-" is honest, not invented.
- D3: net profit omits losses by default. profit_one_number_on defaults to false (phase92.sql:51). l1_pnl profit was 3,323.55 with a 62.06 wastage in the period; switched on (local only) it became 3,261.49. Missing salary, expenses and fixed cost are flagged in the "gaps" column. Wastage, count shrink, transit loss and cash short are silently left out until the owner turns the switch on.
- D4: f3_raw_vs_recipe (phase26.sql:319) "actual" is the recipe itself, because production_post issues exactly the recipe need. Both runs showed expected 40.0 milk, actual 40.0, variance 0.00%, even though run 2 made 17 instead of 20. A variance that is not measured is misleading.
- D5: the app never captures actual yield. production_post has p_actual_yield (phase79.sql:392) but web/recipes.js:286 never sends it. So yield_actual and yield_var_pct are always null, and the costing Runs tab shows "Act" equal to "Std". A direct call gave -15%.
- D6: with the default location mode "off", _conv_cost (phase74.sql:185) returns conversion cost 0 as "complete". The Runs tab shows "conv ৳0" with no "not costed" notice.
- D7: f1_production shows dispatch quantity as the quantity sent, not received (sent 20, received 19), and run quantity is the standard yield unless an actual is typed.
- Positive: cost columns return null ("-") when cost is unknown, uncosted % and the gaps column are shown, and cost columns are hidden without the cost right (rpt_cost_ok, phase9.sql:309). Sales have only done/void, so no draft leaks into any figure. The voided receipt is listed in the register with status void, and excluded from every sum and from payment_modes.

MATRIX (compact; the full 16-column table with file:line was in the unsaved draft)
Notation: Eq? = existing report with the same purpose under another name. Verified: R = ran on the dry-run DB, r = read only. Size and priority shown only where something must be built or fixed (S/M/L; P1 money-critical or daily, P2, P3).

Section 1, Executive
- 1 Executive dashboard: home (dash.js:36-56) + owner board + biz. INCOMPLETE, R+r, M, P1. No outlet/brand comparison, profit, production or target tiles. Eq: owner + biz.
- 2 Daily business summary: report/pos_day_close (phase9.sql:729-753). INCOMPLETE, R, S, P1. D1 and D1b: refund payout column and net after returns missing.
- 3 Monthly business summary: l1_pnl, l4_owner_sheet, monthclose. INCOMPLETE, R, S, P1. D3; expenses come only from 10-2 vouchers.
- 4 Sales, gross and net profit overview: biz, l1_pnl, l3_shop_pnl, profitcheck. INCOMPLETE, R, S, P1. D3; 20% of dry-run sales uncosted (quick lines have no cost, correctly flagged).
- 5 Outlet comparison: l3_shop_pnl (phase79.sql:449), sales_combined. IMPLEMENTED, R. Eq: l3_shop_pnl.
- 6 Brand comparison: brandpnl page (brand_pnl, phase20.sql:457, dated brand map from phase93), sales_combined grouped by brand. IMPLEMENTED, R. Only gap: no CSV on the brandpnl page (S, P3).
- 7 Factory vs retail: none. UNAVAILABLE, r, M, P3. Missing: inter-unit transfer valuation (stock_transfers has no value) and a factory cost-centre result.
- 8 Budget vs actual: finance2 Budgets tab (budget_vs_actual, phase53.sql:806). UNVERIFIED (ran empty only). Needs rules budgets_on (default false) and accounting_on, plus posted journals and budgets entered. S, P2.
- 9 Target vs achievement: none. UNAVAILABLE, P2, M. No targets table, setting or screen anywhere (grep).
- 10 KPI trends and exception alerts: owner widgets with yellow/red limits, exceptions, x4/x5 reports, sales_trend. INCOMPLETE, M, P2. No stored KPI history.

Section 2, Sales and POS
- 11 Sales summary: sales_summary. IMPLEMENTED (D1), R, S, P1.
- 12 Trend and period comparison: sales_trend plus compare. IMPLEMENTED (D1), R (compare totals). S, P1.
- 13 Sales by outlet/brand: sales_combined, brandpnl. IMPLEMENTED (D1), R. S, P1.
- 14 Item-wise sales: item_sales. IMPLEMENTED (D1, D2), R. S, P1.
- 15 Category-wise sales: category_sales and the l2_margin category rows. IMPLEMENTED (D1, D2), R.
- 16 Sales by hour and weekday: hour_weekday. IMPLEMENTED (D1), R. Hour taken in Asia/Dhaka and the weekday are correct (hour 3, Saturday).
- 17 Retail vs wholesale: retail_wholesale. IMPLEMENTED (D1), R. S, P2.
- 18 Receipt/invoice register: receipt_register (phase9.sql:721-728). IMPLEMENTED, R. Void rows are listed but excluded from totals.
- 19 Payment method: payment_modes, wallet_recon, collections. IMPLEMENTED (D1), R. Refund payout by mode is missing; goes with the #2 fix. S, P1.
- 20 Discounts and price overrides: report/discounts plus the #/discounts page. INCOMPLETE, R, S, P2. Only the count of override lines; the override value is missing. Sale lines store price and override flag, but not the list price. It is derivable from item_price_history at the sale time.
- 21 Voids, refunds, returns: voids, receipt_register, salereturn, returnrules report (_w1c_return_report, read only), q3_complaints. IMPLEMENTED, R. Eq: voids + q3_complaints.
- 22 Quick/unlisted sales: quick_unlisted. IMPLEMENTED, R.
- 23 Average ticket and items per bill: avg_bill exists; items per bill is missing. INCOMPLETE, S, P2.
- 24 Sales target by outlet: none. UNAVAILABLE. Same build as #9.
- 25 Top/low/declining products: item_sales sort + compare, biz ABC and unsold list, item_slow. IMPLEMENTED, R+r (row-level compare read only). Eq: item_sales + item_slow.
- 26 Sales by salesperson/cashier: staff dimension in the sales reports, x5_staff_trend, biz_staff. IMPLEMENTED (D1), R.
- 27 Sales channel analysis: s10_orders (phase25.sql:20). INCOMPLETE, r, M, P2. It reads paper-form 20-1 entries with free-text channel. POS and online sales are not grouped by sales_channels, and the online_orders.sale_id join is not used.
- 28 Returns and refund reasons: q3_complaints (phase26.sql:458). IMPLEMENTED, R.

Section 3, Product profitability
- 29 GP and margin by item: l2_margin (phase72.sql:263), ledger cost, returns netted. IMPLEMENTED, R (83.71% on the costed part, 20.2% shown uncosted).
- 30 Profitability by category: l2_margin category rows. IMPLEMENTED, R.
- 31 Profitability by outlet: l3_shop_pnl, l1_pnl. IMPLEMENTED (D3), R. S, P1.
- 32 Selling price vs current cost: only per item in itemmaster and per recipe in costing. INCOMPLETE, S, P1. Missing: a list of all sellable items with price, current cost (average or recipe) and margin %, with "cost not captured" when none.
- 33 Standard vs actual cost variance: costing Runs tab (production_run_costs, phase74.sql:474). INCOMPLETE, R, M, P1. D5: actual equals standard. No aggregate.
- 34 Contribution profit by product: l2_margin. IMPLEMENTED, R. Conversion cost is included only when the location mode is not "off"; wastage is not allocated per product.
- 35 Product profitability ranking: l2_margin sorted, biz ABC. IMPLEMENTED, R.
- 36 Price change history and impact: item_price_history is shown per item (last 15 rows, itemmaster.js:188). INCOMPLETE, M, P3. No before/after impact report.
- 37 Discount impact on profit: item_sales (gross, discount, net, GP together) plus discounts. IMPLEMENTED (D2), R.
- 38 Low-margin and loss-making products: l2_margin sorted ascending. INCOMPLETE, S, P2. Needs an owner setting low_margin_pct and a flag column (no invented default).
- 39 Portfolio, high sales vs high profit: biz ABC (sales only). INCOMPLETE, M, P3. Needs a 2-axis class from l2_margin.

Section 4, Production
- 40 Plan vs actual: none. 05-1 has only an "unplanned production yes/no". UNAVAILABLE, M, P1. Needs a production_plans table and entry screen.
- 41 Batch register: f1_production (phase26.sql:249), the recipes last-15 list, costing Runs. IMPLEMENTED (D7), R. It deliberately has no totals, which avoids double counting run + sheet + dispatch.
- 42 Recipe/BOM costing: costing, recipebook. IMPLEMENTED, R (unit 58.33, today 61.00, gap 4.57%).
- 43 Standard vs actual manufacturing cost: costing Runs tab. INCOMPLETE, R, M, P1. D5 and D6. Same data as #33.
- 44 Raw material use vs recipe: f3_raw_vs_recipe. UNAVAILABLE with D4 (the report falsely shows 0.00%), R, M, P1. Missing: actual issue per batch (04-2 issue slip lines linked to the run, or an actual-use field at production post). The report must say "not captured".
- 45 Yield vs standard: f2_yield (phase26.sql:281, from 05-4 yield tests). INCOMPLETE, R (no 05-4 data, std blank), S, P1. D5: run-level actual yield field missing.
- 46 Batch-wise production cost: costing Runs tab and d_production_cost_breakdown. IMPLEMENTED, R (1,750.00 / 30 kg = 58.33). CSV on the Runs tab would help (S, P2).
- 47 Labour and overhead cost: costing components, pools, true-up. INCOMPLETE, r, M, P2. D6; factory payroll is not linked to the labour pool.
- 48 Output per labour hour: none. UNAVAILABLE, M, P3. Attendance exists at day level only; needs labour hours per run.
- 49 Rejection, rework, production loss: f2_yield (second %, waste %) plus wastage reasons. INCOMPLETE, R, M, P2. Rework and reject quantity per run are not captured.
- 50 Wastage by reason/product/batch: report/wastage (value) and the stockx Wastage tab (quantity only). IMPLEMENTED, R (62.06 on 1 kg expired). Batch and production-run dimension is missing (S, P2).
- 51 Capacity utilization: none. UNAVAILABLE, M, P3. location_cost_cfg.normal_monthly_output is blank and used for overhead only.
- 52 Production order status and pending orders: none (customer orders exist in salesx and 20-1 only). UNAVAILABLE, M, P2.
- 53 Production-to-dispatch reconciliation: f1_production rows side by side, no balance. INCOMPLETE, R, M, P1. Needs made - sent - received - in transit - short - on hand, per item and day. Data exists in production_runs and stock_transfers.
- 54 FG produced vs sold vs remaining: k3_store_ledger (phase25.sql:162) plus the stock_balance report. IMPLEMENTED, R (47 in, 9 out, 19 in / 20 out transfer, 1 waste, 1 return). Optional closing-balance column.
- 55 Manufacturing cost variance analysis: none. UNAVAILABLE, M, P2. A price/usage/yield split needs actual consumption and actual yield (D4, D5).

TRULY MISSING VS ALREADY COVERED (match by purpose)
- Same purpose already covered, fix only, no new build: #5, #6, #11-17, #19, #26 (engine 1: add returns), #18, #21, #22, #25, #28, #29, #30, #31, #34, #35, #37, #41, #42, #46, #50, #54. Name differences: #2 = pos_day_close; #25 = item_sales + item_slow; #21/#28 = voids + q3_complaints; #34/#35 = l2_margin; #54 = k3_store_ledger + stock_balance; #46 = costing Runs tab.
- Needs a fix or small addition on an existing report: #1, #2, #3, #4, #8 (test with data), #10, #20, #23, #27, #32, #33, #36, #38, #39, #43, #45, #47, #49, #53.
- Truly missing (data capture + SQL + screen + export): #7, #9 and #24 (one build), #40, #44, #48, #51, #52, #55.

REPORT PLACEMENT (target IA; no route removed or renamed)
Each report sits under its business group in web/ia.js (13 groups, docs/IA_RULES.md). Existing routes keep working. Reports stay open to the roles that already hold the group grant (report_sales, report_pos, report_cash, view_cost); no new OFF switch.
- #1, #10: Dashboard (dash), executive board (home, owner).
- #5-#7, #9: Dashboard (dash), performance comparison.
- #2, #3, #4, #8: Accounting and Finance (acc), management P&L (l1_pnl, monthclose, finance2 budgets). The day close belongs under Sales.
- #11-#20, #22-#27: Sales and POS (sale), sales reports.
- #21, #28: Sales and POS (sale), voids and returns.
- #29-#35, #37-#39: Reports (reports), product profitability (shown locked without the cost right).
- #36: Items and Master Data (item), price history.
- #40-#43, #45-#49, #51, #52, #55: Factory and Production (factory), batch register, recipe costing, efficiency.
- #44, #50, #53, #54: Inventory and Stock (stock), consumption, wastage, dispatch reconciliation, FG balance.
- #41 and #46: also linked from Factory (batch register and cost).
- One Reports hub: keep the `reports` route and add a section page `reports/map` that lists the 14 sections of the master list. Each section gets a status badge (implemented / incomplete / unavailable / unverified) and one link per report to its existing route. Sections 1-4 come from this audit; 5-14 follow from the other audits. Badge data is a static registry (web/reportsmap.js), not live data. Register it with one rec('reports/map','reports',...) line in web/ia.js. Keep the routes reports, report, biz, brandpnl, discounts, owner, costing as they are.

PROPOSED BUILD PACKAGES (SQL phases 400-419, reserve 415-419; new phase files only, paste-twice safe, each with a _test.sql using neutral test_* data; all new strings in three language modes)
- R1 Returns and refund consistency (phase400, S, P1; no web change, no new capture): add returns_amt and net_after_returns to sales_summary/trend/combined/item/category; add refund_cash and expected_cash_after_refunds to pos_day_close. Existing columns stay unchanged.
- R2 "Data not captured" notices (phase401, S, P1; small edits in web/costing.js): f3 actual = null when no separate issue is captured; conversion cost null with a notice when the mode is off; l1/l3 gaps column adds wastage/shrink when the switch is off; Runs tab shows "actual not captured".
- R3 Production capture (phase402-403, L, P1; web/prodplan.js and edits to web/recipes.js): tables production_plans, production_orders, production_actuals (actual yield and actual issue lines per run) and production_loss (reject/rework quantity and reason). The production screen sends p_actual_yield. No new paper form code without the owner's paper form (BUILD-RULES: form codes are the paper's own).
- R4 Production reports (phase404-405, M, P1; web/prodreports.js): aggregate std vs actual and variance split (#33, #43, #55), plan vs actual (#40), real consumption (#44), order status (#52), reconciliation (#53), run-level yield (#45), reject/rework (#49), CSV on the Runs tab. Needs R3 data.
- R5 Targets and KPI (phase406-407, M, P2; web/targets.js): sales_targets (outlet x month x sales, optional GP %) and kpi_snapshots (daily). Reports #9, #24, #10; a target tile on the owner board. Needs monthly target entry by the owner.
- R6 Sales analytics adds (phase408-410, M, P2; engine-3 rows, one switchboard setting): items per bill (#23), override value (#20), channel from the online_orders join (#27), price vs cost list (#32), price-change impact (#36), low-margin flag setting low_margin_pct (#38), portfolio matrix (#39).
- R7 Cost basis alignment (phase411, S, P2): item_sales and biz_items read ledger cost first, item_costs as fallback, with the same unknown-cost notice as l2_margin.
- R8 Capacity and labour (phase412-413, M, P3; web/capacity.js): rated capacity per outlet/line, production_labour (run, people, hours). Reports #48, #51.
- R9 Factory vs retail (phase414, M, P3): an owner setting for inter-unit transfer valuation (default none, report shows "not valued"). Report #7.
- R10 Reports hub and placement (no SQL, S, P1): web/reportsmap.js and one rec() line in web/ia.js, as in the placement section.

TOP 10 GAPS
1. Engine-1 sales reports and the POS day close ignore returns (D1): 4,220 vs 3,820 net.
2. Expected drawer cash ignores cash refunds (D1b): 2,200 vs 1,800.
3. Net profit overstated by default (D3): wastage, shrink, transit loss and cash short are left out until profit_one_number_on is switched on.
4. Two cost bases for GP (D2): item_sales shows "-" where l2_margin shows 83.71%.
5. Raw-vs-recipe variance is falsely 0.00% (D4).
6. Actual yield is never captured by the app, so "actual cost" equals the standard (D5).
7. Conversion cost shows ৳0 with no "not costed" notice when the mode is off (D6).
8. No production plan, order, rework, labour or capacity capture (#40, #48, #49, #51, #52).
9. No targets or KPI history (#9, #24, #10).
10. No production-to-dispatch reconciliation (#53); the dispatch row shows quantity sent, not received.

DATA-CAPTURE GAPS
- Production plan (date, outlet, item, planned batches/quantity) and production orders with status.
- Actual yield and actual material issue per batch (the DB has the yield column; the app never sends it).
- Reject and rework quantity per run with reason.
- Labour hours per run and rated capacity per outlet/line.
- Sales targets per outlet and month; daily KPI snapshots.
- List price at the time of sale (derivable from item_price_history), to value price overrides.
- Sales channel on POS and online sales (the online_orders.sale_id link exists but is unused).
- Transfer valuation basis for factory-vs-retail results.
- Item costs and ledger data in live: stock_ledger and production_runs are empty today, so all cost reports will show "not captured" until opening stock, purchases and production runs are entered.

CLEANUP
- The local Postgres cluster is stopped; its data dir /var/lib/postgresql/audit5620 remains outside the repo and can be deleted.
- The git state of the worktree (branch worktree-agent-a5c4e6854dbda0345, base 47ba1e5) is unchanged. No file was written or committed, and nothing was pushed.
