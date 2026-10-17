# Reports audit 2 (sections 5-7, reports 56-104)

SETUP: local throwaway Postgres 16 on port 5630, built from tests/sql/ORDER.txt with no errors, now stopped and deleted. I ran a dry run with neutral test_* data kept outside the repo: opening stock, 4 purchase bills (one draft, one voided, one purchase return), a batch with expiry, recipe, production run, sales (one voided), a refund, 2 transfers (one short, one in transit), wastage, a count, a sale beyond stock, and paper-form entries (PO, GRN, bill check, count sheet, hygiene and fridge sheet, complaint). I called every report named below as owner. Not checked: a real browser or phone, the CSV/PDF files, or live data. The live stock_ledger has 0 rows.

COUNTS (49 reports): IMPLEMENTED 15 | INCOMPLETE 28 | UNAVAILABLE 6 | UNVERIFIED 0 (data level; screens not opened in a browser).
- Section 5, #56-75: 3 implemented, 15 incomplete, 2 unavailable (68, 74).
- Section 6, #76-89: 4 implemented (76, 86, 87, 88), 7 incomplete, 3 unavailable (81, 83, 85).
- Section 7, #90-104: 8 implemented, 6 incomplete, 1 unavailable (104).
- Status meaning: INCOMPLETE = partial or misleading, or no report yet but existing records fully support it (build only). UNAVAILABLE = new data capture needed.

STOCK IDENTITY (opening + in - out = closing), tested by SQL
- Ledger sum equals the balance on every item and place (difference 0). `stock_reconcile` found 0 mismatches.
- Draft and voided purchases entered no figure. A voided sale nets to zero. A refund adds `sale_return` stock.
- Transfers are not double counted in a balance. In a movement summary over all places, out 4.0 versus in 2.5 shows a 1.0 in-transit gap and a 0.5 short gap. A "total outward" that includes transfer_out overstates consumption. A short receipt creates a `shortage_transit` record (value, claim, write-off) automatically.
- Refund risk: a "damaged" refund went back into sellable stock, because `w1c_return_class_rules` is empty. A later `customer_return` write-off would count the same item twice.

TOP 10 GAPS (misleading now first)
1. `expiry_soon` hides batches that expire soon unless rule `report_expiry_soon_days` is set (no default). A batch expiring in 2.8 days was invisible there. The stockx tab uses another rule (`expiry_warn_days`), so there are 3 thresholds for one question.
2. Batches with no expiry are silently left out of every expiry report. A production run with no `shelf_life_rules` row gives a batch with null expiry, so "nothing expiring" is false.
3. Supplier overdue shows 0.00 when `credit_days` is empty. This happens in `supplier_ageing`, `supplier_dues` and `payables_summary`. Ageing buckets need rule `report_aging_buckets` (no default).
4. Stock valuation totals drop lines with a null `avg_cost` without any count. `wastage` already shows "entries with no cost"; stock does not.
5. `p4_supplier_score` prints 0 GRNs, 0 POs and 0 rejections when the paper forms were not used, even when purchase bills exist. It never reads `purchase_bills`, returns or `qc_records`.
6. `wastage_by_reason` (stockx tab) adds quantities of different units into one number.
7. A negative balance (-2.7 kg) shows as state "low", and reorder suggests 7.7 kg. The oversold quantity is posted with no batch, which breaks tracing.
8. Missing builds: period reconciliation (#75), negative/integrity list (#72), unsold FG by batch (#80), FG distribution by outlet and batch (#84), ageing (#68), turnover (#73), daily closing vs next-day (#82). The data for most of these already exists.
9. #60-62 have no item-type split (raw, FG, packaging), although `items.item_type` exists. #67 `item_slow` has no stock on hand, value or last movement, and it does not net refunds.
10. `stock_reconcile(p_fix:=true)` (rewrites cached balance and average cost) is reachable from the stock screen (web/stock2.js:554).

DATA-CAPTURE GAPS (forms and tables; form codes are the owner's to give, per BUILD-RULES 1 and 15)
1. Supplier lot/batch and expiry on every raw receipt. Today `grn_batch_add` is a separate, optional step. In the dry run only 22.5 of 167.5 kg flour had a batch. This blocks #68 (raw), #83 and #85.
2. Recall case record (new paper-first form, code from the owner).
3. Stockout or unmet-demand note at the shop (#74).
4. `shelf_life_rules` rows per item or category (#81), and a notice when they are missing.
5. Damaged quantity and reason on the transfer receive sheet (#65).
6. Quality inspection record: rejected qty, item, supplier on `qc_records` (#89, #103).
7. Standard or agreed purchase price per item and supplier (#101).
8. `item_suppliers` table for preferred and alternative suppliers (#104).
9. Fridge min/max per fridge in `location_settings` (already read by `q1_fridge_temp`).
10. Actual yield at production (`production_runs.yield_actual`, optional today) for #78.
11. Wastage reason `unsold`, added as a list value (#79).

MATRIX. S1 = `#/stock`, S2 = `#/stockx`, S3 = `#/report/<key>` raw engine (phase21.sql), S4 = engine 3 (phase24.sql `report_run3`, phase25/26.sql `_r3q_*`), S5 = `#/payables`, S6 = `#/shortages`, S7 = `#/returnrules`, S8 = `#/purchase`.

Common to all rows:
- S3 and S4 have CSV and Print/PDF (web/reports.js:371-420), a sticky first column on mobile (:511), and no drill-down for raw reports (drill is only on engine-1 grouped reports, :310).
- S1, S2, S5, S6 and S8 have no export.
- Only posted records write the ledger. A void writes `reversal`. A refund writes `sale_return`.

| # | Equivalent existing (route · key) and SQL file:line | Status | Verified | Gap type | Missing capture | Size | Prio |
|---|---|---|---|---|---|---|---|
| 56 | S1 levels `stock_levels` phase10.sql:755; S3 `stock_balance` phase21.sql:206 | IMPLEMENTED | ran | - | - | - | - |
| 57 | S3 `stock_balance` value; `stock_valuation` phase10.sql:843 (no screen) | INCOMPLETE | ran | FIX+EXT | none (uncosted count, subtotal per place and place kind) | S | P1 |
| 58 | S3 `stock_low` phase21.sql:206 | IMPLEMENTED | ran | - | caveat: one minimum for all places; a place with no balance row is not listed | - | P3 |
| 59 | S2 reorder `reorder_report` phase60.sql:335 | IMPLEMENTED | ran | - | CSV missing | - | P3 |
| 60-62 | S3 `stock_balance`, no item-type filter | INCOMPLETE | ran | EXT | none | S (one package) | P2 |
| 63 | S3 `k3_store_ledger` phase25.sql:162; S1 `stock_ledger_rows` phase10.sql:794 | INCOMPLETE | ran | EXT | none (opening, closing, running balance, row drill, labels) | M | P2 |
| 64 | S3 `transfers_gap` phase21.sql:280 (exceptions only); `f1_production` dispatch rows | INCOMPLETE | ran | EXT | none (all-transfers mode) | S | P2 |
| 65 | S3 `transfers_gap` + S6 `transit_short_list` phase81.sql:303 | INCOMPLETE | ran | CAP | damaged qty and reason at receipt | S | P2 |
| 66 | S4 `k2_count_variance` phase26.sql:224 (form 04-3); `stock_count_adjust` phase10.sql:589 | INCOMPLETE | ran | EXT | none (cost value; RPC counts missing from it) | S | P2 |
| 67 | S3 `item_slow` phase21.sql:194 | INCOMPLETE | ran | EXT | none (stock on hand, value, last movement; refunds not netted) | M | P2 |
| 68 | none; FG `stock_batches.made_at` only | UNAVAILABLE | read | CAP | receipt lot or date on raw receipts | M | P3 |
| 69 | S3 `expiry_soon` phase21.sql:262; S2 `near_expiry_report` phase60.sql:283; S1 `expiry_list` phase10.sql:824 | INCOMPLETE | ran | FIX | none (one threshold, "no expiry captured" line) | S | P1 |
| 70 | S2 expiry tab, `fefo_hint` phase60.sql:300 | INCOMPLETE | ran | EXT | none (all batches, unbatched qty line) | S | P2 |
| 71 | S3 `k3_store_ledger` summary | INCOMPLETE | ran | NEW | none (row list with who, why, value) | S | P2 |
| 72 | S3 `exceptions_summary` (flag stock_negative); S1 reconcile sheet | INCOMPLETE | ran | NEW | none (negative balance and mismatch list) | S | P1 |
| 73 | partial `reorder_report.days_left` | INCOMPLETE | read | NEW | none (ledger `unit_cost` on sale_out gives cost of sales) | M | P3 |
| 74 | none | UNAVAILABLE | read | CAP | stockout and unmet-demand log (history alone is derivable) | M | P3 |
| 75 | partial `stock_reconcile` phase10.sql:862, `inventory_vs_gl` phase72.sql:781 | INCOMPLETE | ran (identity by SQL) | NEW | none | M | P1 |
| 76 | S3 `wastage` phase21.sql:233 (one dimension at a time) | IMPLEMENTED | ran | - | - | - | P3 |
| 77 | S3 `wastage` value; no % | INCOMPLETE | ran | EXT | none (denominator) | S | P2 |
| 78 | S4 `f2_yield` phase26.sql:281, `f3_raw_vs_recipe` :319; S3 `wastage` by place | INCOMPLETE | ran | NEW+CAP | actual yield at production | M | P2 |
| 79 | S3 `wastage` reasons; S7 `_w1c_return_report` phase91.sql:397 | INCOMPLETE | ran | EXT+CAP | wastage reason `unsold`; owner return class rules | S | P2 |
| 80 | none (`stock_batches`, `production_runs.batch_id`) | INCOMPLETE | read | NEW | none | M | P1 |
| 81 | `shelf_life_for` phase8.sql:358 only | UNAVAILABLE | ran | CAP | `shelf_life_rules` rows | M | P2 |
| 82 | none (ledger replay by date) | INCOMPLETE | read | NEW | none | M | P2 |
| 83 | none (ledger `batch_id`/`ref_id` chain exists) | UNAVAILABLE | ran | CAP+NEW | supplier lot on raw receipt | L | P1 |
| 84 | none (transfer_out and transfer_in share `ref_id`) | INCOMPLETE | ran | NEW | none (oversold sales have no batch) | M | P2 |
| 85 | none | UNAVAILABLE | read | CAP | recall record | L | P1 |
| 86 | S4 `q2_hygiene` phase26.sql:435 (forms 14-1, 05-1) | IMPLEMENTED | ran | - | - | - | - |
| 87 | S4 `q1_fridge_temp` phase26.sql:411 | IMPLEMENTED | ran | - | fridge limits must be set (notice when unset, P3) | - | P3 |
| 88 | S4 `q3_complaints` phase26.sql:458 + S7 | IMPLEMENTED | ran | - | - | - | - |
| 89 | S2 quality tab `qc_list` phase60.sql:189, `qc_record` :137 | INCOMPLETE | ran | EXT+CAP | rejected qty, item, supplier; date and status filters | M | P2 |
| 90 | S3 `purchases_by_supplier` phase21.sql:317 (group none or day) | IMPLEMENTED | ran | - | - | - | P3 |
| 91 | same, group supplier | IMPLEMENTED | ran | - | - | - | - |
| 92 | partial S4 `p2_rate_trend` phase26.sql:110 (qty and rate, no value) | INCOMPLETE | ran | EXT | none | S | P2 |
| 93 | S4 `p2_rate_trend` | IMPLEMENTED | ran | - | - | - | - |
| 94 | S4 `p4_supplier_score` phase26.sql:128 | INCOMPLETE | ran | FIX | none ("not captured" instead of 0; read bills, returns, qc) | S | P1 |
| 95 | S4 `p5_po_match` phase26.sql:168 (POs are paper form 06-3; cancelled POs not listed) | IMPLEMENTED | ran | - | - | - | P3 |
| 96 | S4 `p5_po_match` (GRN and bill legs verified) | IMPLEMENTED | ran | - | optional PO number on `purchase_bills` | - | P3 |
| 97 | S4 `p5_po_match` (status and days_late) | IMPLEMENTED | ran | - | - | - | P3 |
| 98 | S3 `supplier_ageing` phase21.sql:290; S5 `supplier_dues` phase10.sql:1240, `payables_summary` :1289 | INCOMPLETE | ran | FIX | none (credit-days-not-set flag, buckets with no hidden default) | S | P1 |
| 99 | S5 `supplier_ledger` phase12.sql:414 | IMPLEMENTED | ran | - | - | - | P3 |
| 100 | partial S3 `purchases_by_supplier` returns columns | INCOMPLETE | ran | NEW | none (`reason_code`, `ref_bill_id` exist) | S | P2 |
| 101 | partial S4 `p2_rate_trend` | INCOMPLETE | ran | CAP | standard or agreed price | M | P2 |
| 102 | S4 `p4` late POs + `p5` days_late | IMPLEMENTED | ran | - | - | - | P3 |
| 103 | partial S4 `p4` counts | INCOMPLETE | ran | EXT | none (rate %; link `qc_records` to supplier) | S | P2 |
| 104 | none | UNAVAILABLE | read | CAP+NEW | `item_suppliers` (preferred and alternative) | M | P3 |

Filters, tables and calculation per row (compressed):
- Stock rows read `stock_balance`, `stock_ledger`, `items` (`min_stock`, `item_type`, `tracked`), `locations`. Filters are place, category, text, below-min, zero (S1) or locations, brands, categories (S3). Valuation is qty x weighted average cost, shown only with the cost right.
- Wastage rows read `stock_wastage`, `option_lists`, `stock_ledger.unit_cost`. Filters: date, locations, brands. Pending approvals are not counted.
- Purchase rows read `purchase_bills` (posted only), `purchase_lines`, `suppliers`, `supplier_payments`, `supplier_refunds`. Filters: date, locations, brands. Drafts and voids are excluded (verified).
- PO rows read paper-form entries 06-3, 04-1, 06-4 (there is no PO table). The match is by the PO number typed on the GRN and the bill check, so posted `purchase_bills` carry no PO link.

SQL phases 420-439 and web files (new SQL only, safe to paste twice, reports open to the roles that already hold `report_stock`, `report_purchase`, `report_quality`; each phase gets a `_test.sql`, an ORDER.txt line and a BUILD-LOG entry)
- R1 Honesty fixes (phase420, M): #57, 69, 94, 98 and findings 6, 7. Uncosted count and subtotals on stock value. Expiry list with no threshold plus a "no expiry captured" row. "Credit days not set" flag. Scorecard reads bills, returns and qc. Wastage without a cross-unit sum. A "negative" state. Files: web/reports.js (notices), web/stockx.js.
- R2 Stock type and movement (phase421-422, L): #60-62, 63, 64, 66, 71, 77. New web/stockrep.js and an IA record.
- R3 Reconciliation and integrity (phase423, L): #72, 75, 82, 73. `stock_recon_period(from, to, loc)` = opening (ledger replay) + in - out = closing, with in-transit and short lines and a check against the cached balance.
- R4 Batches, ageing, freshness (phase424-425, L): #67, 68 (FG), 70, 80, 84, 69. New web/batchrep.js.
- R5 Traceability and recall (phase426-427, L): #83, 85. Lot on raw receipts, `trace_batch(batch)`, tables `recall_cases` and `recall_batches`. New web/trace.js.
- R6 Quality extras (phase428-429, L): #89, 79, 65, 78, 81, 74. `qc_records` gains `qty`, `item_id`, `supplier_id`. Reason `unsold`. `received_damaged_qty`. `stockout_log`. Files: web/stockx.js, web/stock2.js, web/stockout.js.
- R7 Purchasing (phase430-431, M): #92, 100, 101, 103, 104, 102. New web/purchrep.js.
- R8 Placement and hub (IA only, S): see below.
- New capture must be paper-first: form codes come from the owner, not invented.

SAME PURPOSE ALREADY COVERED (do not rebuild)
- 56 = S1 levels + `stock_balance`; 58 = `stock_low`; 59 = `reorder_report`; 76 = `wastage`; 86 = `q2_hygiene`; 87 = `q1_fridge_temp`; 88 = `q3_complaints` + S7.
- 90 and 91 = `purchases_by_supplier`; 93 = `p2_rate_trend`; 95, 96 and 97 are one report, `p5_po_match`; 99 = `supplier_ledger`; 102 = `p4` + `p5`.
- 65 = `transfers_gap` + S6 (only "damaged" is open). 69 is covered by three screens and needs one threshold, not a fourth.
- Extend in place, no new report: 57, 60-62, 63, 71, 64, 66, 67, 70, 77, 79, 92, 94, 103, 100, 101, 89, 98.

TRULY MISSING (no equivalent anywhere): 68, 72, 73, 74, 75, 78, 80, 81, 82, 83, 84, 85, 104. Only 68 (raw), 74, 81, 83, 85 and 104 (alternatives) need new capture. The rest are queries over existing records.

REPORT PLACEMENT (the section 'Report placement' you asked for; IA has 13 groups and no Quality group)
- Mechanism: one `rec('report/<key>', <group>, label, { also: ['reports'], drawer: false })` per report in web/ia.js. The viewer route already exists. Existing records stay; no route or button is removed.
- `stock` group:
  - Stock levels and value: #56-62.
  - Movements, transfers, counts: #63-66, 71.
  - Batches and ageing: #67, 68, 70, 80, 84.
  - Expiry: #69.
  - Control and reconciliation: #72, 73, 75, 82 (#72 also in `appr`).
  - Stockout: #74.
  - Wastage and freshness: #76-79, 81.
  - Traceability and recall: #83, 85.
  - Food safety and quality (hub tag "quality"): #86-89.
- `purch` group:
  - Purchases and prices: #90-93, 100, 101.
  - Suppliers: #94, 102-104.
  - Purchase orders: #95-97.
  - Payables: #98, 99.
- `factory` group (also `stock`): #78.
- Hub (`#/reports`, web/reports.js): lists all 14 owner sections as cards with status-badge counts and links. Badges come from a static map `BOS.reportStatus` in web/reports2.js, so the hub never runs a report to compute them.
- Sections 1-4 and 8-14 are placeholders ("not audited here").
- Hub badge counts:
  - Section 5: 3 implemented, 15 incomplete, 2 unavailable.
  - Section 6: 4 implemented, 7 incomplete, 3 unavailable.
  - Section 7: 8 implemented, 6 incomplete, 1 unavailable.

OTHER RISKS
- BUILD-RULES 15 says never invent a limit, so the fix for unset thresholds is to show the data with a clear notice, not to add a default value.
- `stock_wastage` has no void, so a wrong entry is corrected only by a count adjustment.
- Raw stock without a batch row cannot be traced or aged. Lot reports must print the unbatched quantity.
- `inventory_vs_gl` returned `data_needed` (accounting start not set) and was not exercised.
