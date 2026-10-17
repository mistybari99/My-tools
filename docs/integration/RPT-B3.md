# Integration note RPT-B3: traceability and recall, quality extras, purchasing reports

SQL numbers **phase430 to phase436**, pasted in that order after phase99 (needs phases 8 to 99 only; nothing of R1-R4, phases 420-429, is needed or touched). Every file is paste-twice safe, no earlier phase file is edited, **no shared function changes behaviour**. Requirements: `docs/REPORTS_AUDIT_2.md` (items #65, #74, #78, #81, #83, #85, #89, #92, #100-#104).

New files: `supabase/phase430.sql` ... `phase436.sql` and `phase430_test.sql` ... `phase436_test.sql`, `tests/sql/rb3_hooks430.sql`, `web/trace.js`, `web/stockout.js`, `web/purchrep.js`, `tests/web/rptb3_test.js`, `docs/integration/RPT-B3_info.json`, this note. Edited in place (additive): `web/stockx.js`, `web/stock2.js`, `web/purchase.js`, `web/recipes.js`, `web/ia.js` (5 records), `web/index.html` (3 script tags), `tests/sql/ORDER.txt` (one line).

## 1. What each phase does
| Phase | Item | Content |
|---|---|---|
| 430 | #83 | `receipt_lots` (supplier lot + expiry typed on a purchase line, optional), `receipt_lots_stage / _get / _apply / receipt_lot_check`, `stock_unbatched`, settings `receipt_lot_required` and `receipt_expiry_required` (both OFF), helpers `_rb3_patch`, `_rb3_lot_gate`, `_rb3_lot_apply` |
| 431 | #83 #85 | `trace_batch` (raw lot -> production -> finished batch -> transfers -> outlets / named customers, and back), `trace_batch_find`, `recall_cases`, `recall_batches`, `recall_open / add_batch / batch_mark / close / list`, `recall_affected` (affected-stock report incl. unbatched quantity and receipts without a lot), grant `recall_manage` |
| 432 | #89 #65 | `qc_records` + item, qty, supplier (11-argument `qc_record`; the 7-argument one is now a wrapper), `qc_list` with item / supplier filters, `stock_transfers` + damaged qty and reason, 5-argument `stock_receive_transfer` (calls the untouched 3-argument one), `transfer_damage_report`, list `transfer_damage_reasons` |
| 433 | #74 #81 #78 | `stockout_log` + `stockout_add / void / list / summary` (grant `stockout_log`), `shelf_life_missing` (notice only; the maintenance screen Settings > Shelf life already exists), `yield_report` |
| 434 | #92 #101 #104 | price trend gets a `value` column (same engine report `p2_rate_trend`, cost rule unchanged), `supplier_item_prices` + `supplier_price_set / retire / list`, `item_suppliers` + `item_supplier_set / retire / list`, grant `supplier_terms_manage` |
| 435 | #100-#104 | `supplier_returns_report`, `purch_price_variance`, `supplier_rejection_rate`, `supplier_dependency`, `supplier_delivery_perf` |
| 436 | all | `rb3_log_export`: audit line for every CSV of the new reports (same rule as `log_page_export`: owner or `export_data`) |

## 2. Settings (all OFF or blank by default; nothing starts by itself)
| Key | Default | Meaning |
|---|---|---|
| `receipt_lot_required` | OFF | a bill with tracked stock lines cannot be posted without a supplier lot number on each (server refusal needs hook H430-1; the screen asks either way) |
| `receipt_expiry_required` | OFF | the lot also needs an expiry date |

Nothing else is a setting because nothing else changes stock or money: every addition is a record, a report or a notice. No limit, threshold or price is invented; an unset value is shown as "data not captured: <field>".

## 3. Hook (the only shared-function change; optional)
`post_purchase(uuid, jsonb)` (the phase14 wrapper). Exact text: `tests/sql/rb3_hooks430.sql` (marker `bos430`, applied with `_rb3_patch`; a missing site stops everything; twice = no-op). It (a) calls `_rb3_lot_gate` before posting and (b) calls `_rb3_lot_apply` after a successful posting. **Without it** the purchase screen calls `receipt_lots_apply` itself right after posting, so lots still become stock batches; only the server-side "lot required" refusal needs the hook. Re-pasting phase10 / phase14 removes the patch: paste the hook file again. phase430_test T5 proves the hook on a scratch copy inside a rolled-back transaction.

## 4. Hook sites in the web
`web/ia.js`: `trace`, `recall`, `stockout` (group stock, also reports), `purchrep` and `report/p2_rate_trend` (group purch, also reports). `web/index.html`: `trace.js`, `stockout.js`, `purchrep.js` after `twofa.js`. `tests/sql/ORDER.txt`: one line (will conflict textually with the R1-R4 builder's line; keep both). `web/purchase.js`: lot / expiry fields on a stock line, `receipt_lots_stage` on save, `receipt_lots_apply` after post, a lots block on the bill. `web/stock2.js`: damaged quantity and reason on the transfer receive sheet. `web/stockx.js`: quality filters and columns, tabs "Damaged on receipt" and "Yield", the shelf-life notice. `web/recipes.js`: optional actual yield in the production sheet (blank = today's 6-argument call) and the shelf-life notice.

## 5. Owner rules kept
Reports stay open to the roles with `report_stock / report_purchase / report_quality` (and the owner); money columns only with the cost right (the server sends null and says `cost_hidden`); agreed prices are costs and the table is not readable by browsers. New capture is a digital entry screen only; the paper form code is "to be given by owner" (said on each screen). Equivalents were extended, not duplicated (QC list, transfer receive, price trend, shelf-life screen, production screen). A recall case records what was done; holding / returning / writing off is done with the existing screens. CSV follows the existing export right (owner or `export_data`) and is audit-logged before the file is built.

## 6. Not confirmed
Live Supabase, a real phone, the CSV in a real spreadsheet, the hook on the live function text (proved on the text of a database built from phases 8-99), pg_cron. R1-R4 (phases 420-429) were not present, so interaction with them is untested (`p2_rate_trend` is touched by phase434 only; the QC wrapper and the `qc_list` re-creation assume the phase60 text).
