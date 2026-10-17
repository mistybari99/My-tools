# Integration note RPT-B2 (stock and freshness reports; phases 420 to 425; branch rpt-b2)

Audit: `docs/REPORTS_AUDIT_2.md` (items #56-104). Built here: R1 honesty fixes, R2 stock type/movement, R3 reconciliation, R4 batches/freshness. R5-R7 (phase 426+) are another package. Info entries for the (i) button: `docs/integration/RPT-B2_info.json`.

## Files
SQL (paste after phase99, in order, each safe twice): `supabase/phase420.sql` .. `phase425.sql` and `phase42x_test.sql`; fixture `tests/sql/p420_fixture.sql` (neutral test_* data: opening, purchase, production, transfer, sale, wastage, refund, count). `tests/sql/ORDER.txt` lists 420-425 after 99.
Web: new `web/stockrep.js` (also defines `BOS.repkit`: table, CSV, drill helper), `web/batchrep.js`; test `tests/web/stockrep_test.js`.
Edited: `web/ia.js` (22 rec lines), `web/index.html` (two script tags before stockx.js), `web/reports.js` ("not captured" cells, row drill `row.drill`, `res.subtotals`), `web/filters.js` (item_types filter), `web/stock2.js` (negative chip, repair needs typed FIX via `stock_reconcile_fix`), `web/stockx.js` (wastage per unit, CSV, expiry days from the rule), `web/purchase.js` ("credit days not set" chip + notice). Tests changed: `stock2_test.js`, `stockx_test.js`, `s10_common.js` (ROOT can be set with env BOS_WEB).

## Hook sites (what a later re-paste can undo; re-run the named phase)
- `report_run2` and `report_catalog2` are re-created by phase420 (decorator hook `_r4d_<key>(filters, answer)`; an engine-3 row replaces an engine-2 entry of the same key). Re-pasting phase 21 or 24 removes it: paste phase420 again.
- `stock_reconcile(boolean)` is re-created by phase420 (audit line when the cache is rewritten). Re-pasting phase 10 removes it: paste phase420 again.
- Engine-3 rows replaced in place: stock_balance, expiry_soon, item_slow, k2_count_variance, p4_supplier_score (same key, same route, same group/access). Re-pasting phases 25/26 resets k2 and p4: paste 421/420 again.
- Decorated engine-2 key: supplier_ageing (overdue empty when credit days unset).
- No hooked function of phase99 is touched; `_i1_apply_hooks()` output is unchanged.
- Web: shared `H` handler names are prefixed `stk_`, `bch_`, `rk_` (an earlier `sr_` prefix collided with salereturn.js).

## Behaviour changes the owner asked for (everything else only adds columns and notices)
Negative balance reads `negative` (was `low`); one expiry threshold (report_expiry_soon_days, else expiry_warn_days) so `expiry_soon` now lists "soon" batches by default (old: only expired when the first rule was empty); supplier overdue empty (was 0.00) without credit days; `wastage_by_reason2` replaces the cross-unit sum on the stock screen. Old suite diffs caused: phase21_test T5 "rule empty: expired only", phase26_test K2 "no money column" (value columns added for cost-right holders).
New wastage reason value `unsold` (option_lists). No new rule, grant or setting.

## Not built / owner's to decide
New capture (supplier lot on receipt, recall record, stockout log, shelf-life rows, damaged qty at receipt) is R5-R6. `transfers_gap` stays exceptions-only; the all-transfers list is `transfers_register`. Reason classes of #79 are fixed (expired; unsold; broken/burnt/spoiled = damaged).
