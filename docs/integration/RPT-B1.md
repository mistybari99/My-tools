# Integration note RPT-B1 (reports: returns, "not captured", cost basis, reports map, three added reports)

Branch `rpt-b1` (base 47ba1e5). Audit: `docs/REPORTS_AUDIT_1.md`. Test data only (`test_*`). Nothing was pasted into any live database; tests ran on a local throwaway Postgres 16.

## Files
- SQL (new phase files only, paste after phase 99 in this order, each paste-twice safe): `supabase/phase400.sql` (R1), `phase401.sql` (R2), `phase402.sql` (R7), `phase403.sql` (three added reports) and the tests `phase400_test.sql` .. `phase403_test.sql` (fixtures `tests/sql/rptb1_fixture.sql`, `rptb1_fixture2.sql`, `rptb1_fixture3.sql`).
- Hooks: `docs/integration/RPT-B1_hooks.sql` (13 exact-text patches, helper `_rptb1_patch` shipped by phase400, markers bos400 / bos401 / bos402). A section whose phase is not pasted is skipped. Paste-twice safe.
- Web: `web/reportsmap.js` (new, script tag added after `reports2.js` in `web/index.html`), edits in `web/reports.js`, `web/costing.js`, `web/biz.js`, `web/ia.js`.
- Info (i) texts: `docs/integration/RPT-B1_info.json` (20 entries).
- Add `phase400 .. phase403` to `tests/sql/ORDER.txt` after phase99 when you integrate (not done here: the order file belongs to the integrator). Suites 400 to 403 expect a DB built through phase 99 plus the phases up to their own number.

## What each phase does
| Phase | Item | Adds | Defaults |
|---|---|---|---|
| 400 | R1 | views `rpt_ret_b/_l/_p`; new columns `returns_amt`, `net_after_returns` (sales_summary, sales_trend, sales_combined), plus `returns_qty`, `qty_after_returns` (item_sales, category_sales), `refund_paid`, `net_after_refunds` (payment_modes), `refund_cash/_mobile/_card`, `expected_cash_after_refunds` (pos_day_close) | Old columns unchanged. Rule `reports_net_of_returns` honoured (off = "after returns" equals the old column + a note). A day with a return and no sale appears as a return-only row. |
| 401 | R2 | `f3` actual empty unless a movement was posted after the automatic issue (status column `actual_status`, note "Not captured"), conversion cost empty + `conversion_status` when the place method is off, `actual_cost` empty when no actual yield, `unit_cost_basis`; `gaps` column of l1/l3 names wastage / count shrink / transit loss / cash short left out of the profit; Runs-tab CSV | Profit figures unchanged; only text and empty cells. `profit_one_number_on` stays a setting (off). |
| 402 | R7 | setting `reports_cost_basis` (`price_list` default, `ledger_first`), view `rpt_line_cost`, biz item cost helper, `biz_cost_status` RPC, unknown-cost / estimate / hint notes | Default `price_list` = today's figures (proved: the cost-join SQL text is identical). |
| 403 | extras | reports `y1_daily_sellout`, `y2_festival_compare`, `y3_customer_items`; `report_drill(key, ref)`; setting `report_top_customers_n` (blank = 10) | Read-only. Open to the group grants report_stock / report_sales / report_customers. |

## Hook sites (for the integrator)
`rpt_meas`, `rpt_def`, `rpt_agg_build`, `rpt_raw` (pos_day_close), `report_run` (two statements: R1 notes, R7 notes), `_r3q_f3_raw_vs_recipe`, `_r3q_l1_pnl`, `_r3q_l3_shop_pnl`, `report_run3` (notes call), `production_run_costs`, `rpt_agg_sql` (cost join), `biz_items` (cost rows). Re-pasting phase 9, 24, 26, 27 (or the later phases that re-create l1/l3: 72, 78, 79), 74/79 (production_run_costs) or 4/14 (biz_items) removes the matching hook: run the hooks file again (add it to the wave re-patch phase). `select _rptb1_hooked(), _rptb1_hooked401(), _rptb1_hooked402();` shows which sites are in.
Placeholders: the new measures in `rpt_meas` are `null::numeric`; `_rptb1_agg_wrap` fills them. If the `rpt_meas`/`rpt_def` hooks are installed without the `rpt_agg_build` hook the columns show empty, never a wrong number. Install the file as one piece.

## Report placement (web/ia.js)
`reports/map` added (group reports). Per the audit placement: `brandpnl` -> dash, `owner` -> dash, `profitcheck` -> acc, `discounts` -> sale; each keeps its old group in `also` so the category page still lists it. `biz` gets `also: acc`. No route removed or renamed. `tests/web/wave1_wiring_test.js` now expects `profitcheck` in `acc`.

## Why these three added reports (matched by purpose, nothing equivalent exists)
- `k3_store_ledger` / `stock_balance`: period totals per movement kind and the balance now; no day, no closing, no sell-through. -> y1.
- report hub compare (`prev/week/year`): whole-period totals only, no per-item "no previous data" state, no custom previous dates. -> y2.
- `best_customers`: customers and totals, not what they buy. -> y3 (sales have `customer_id`, so it was cheap).

## Open points / decisions for the owner
1. `reports_cost_basis` default `price_list`; the owner switches to `ledger_first` when ready (the margin report already uses the ledger first).
2. f3 "measured" means a stock movement posted for the run after its automatic issue. The production-capture package (R3) should post the real issue that way (same item, `ref_type 'production'`, `ref_id` = run id).
3. Sections 5 to 14 of the reports map are placeholders ("not audited yet"); fill them with `BOS.reportsMap.extend([...])` or `window.BOS_REPORT_MAP_EXT` (schema in the file header).
4. Not built (needs data capture, see the audit): R3 production capture, R4 production reports, R5 targets, R6 sales analytics adds, R8, R9.
5. Rows of reports grouped by a dimension now include return-only groups (old columns 0). Totals tie exactly to the dashboard.
