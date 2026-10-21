# A2 - Sales-to-stock reconciliation: audit + gap analysis

Stage 1-2 of Audit > Gap > Priority > Implementation > Verification. Branch `audit/a2`. No SQL or web code was changed.
Only this file and `tests/sql/audit2/a2/` were added.

## 0. Method and assumptions

- Final database built from nothing with `tests/sql/final_build.sh a2db` (canonical order `tests/sql/paste_order.env`, phases 72..111), Postgres 16, socket /tmp port 5544.
- Function bodies were read from `pg_get_functiondef` of that build (the final bodies, not the per-phase files). `fn:N` below = line N of that definition.
- Scenarios: `tests/sql/audit2/a2/run_a2.sh a2t` (re-creates the scratch DB `a2t` from template `a2db`, prepends `tests/sql/e2e/00_common.sql`, runs `a2_00 .. a2_40`).
  Last run: **131 PASS / 23 FAIL** (a FAIL is a finding, or a "feature absent" probe). Every expectation was hand-computed before running.
- Default settings ("def" mode): no setup-advisor recommendations applied, accounting OFF. The e2e "rec" mode was not re-run (assumption: advisor rows only flip optional rules; the findings are about code paths).
- Roles used: owner, salesperson (location 1 only), salesperson 2 (location 2 only), maker, approver. Locations are the seeded ids 1, 2, 3.
- Assumption: costs in the tests are per BASE unit. Concurrency (two phones at once) was NOT run here; code read only (`stock_post` locks the balance row `FOR UPDATE`, `fn:20-21`).
- Form paths (04-1/04-2/04-3/03-1/05-1 via `entry_post_ledger`, `forms_post_to_ledger`) and online orders (`online_order_deliver`) were read, not executed (marked CODE-READ).
- Verdict words: PASS = behaves as the owner would expect; FAIL = wrong or silent mismatch; NOT SUPPORTED = no such feature.

## 1. How a sale reaches stock (the real path)

1. `record_sale2` (final body, phase 94/87 lineage) prices from `items.sell_price` (`fn:47 pr := it.sell_price`) and stores each line as `{item_id, qty, price, unit = items.unit}` (`fn:62`).
   It does NOT accept a unit per line: qty is always in the item's own selling unit. The POS app converts "3 pc" into kg on the phone (`web/pos.js:83-99`, conversions cached in localStorage `bos_pos_conv`, `pos.js:111`) and only the converted qty reaches the server.
2. Trigger `sales_stock_out` (AFTER INSERT on `sales`) calls `_sale_stock_out` (phase 89 merge of 82/83/94): per tracked item, in item-id order, `bq = _base_qty(item, qty, line unit)` (`fn:26`), then `stock_post(item, sale location, -bq, 'sale_out', ..., neg)` (`fn:51`).
3. `stock_post` (single writer): locks `stock_balance` row, applies the negative-stock policy, consumes `stock_batches` in order (expired last, then `expires_at` nulls last, `made_at`, `id`; `fn:63`), writes one `stock_ledger` row per batch touched, the AFTER INSERT trigger `stock_ledger_balance` keeps `stock_balance` (qty, weighted avg cost) in step.
4. Void: trigger `_sale_stock_void` re-posts each un-reversed `sale_out` row as `sale_void_in` with the SAME batch id (`_sale_stock_void fn:11`). Return: `sale_return` walks the sale's own `sale_out` rows in id order and restores to the batch of each row (`sale_return fn:84-90`).
5. Packaging (`_sale_packaging_out`) is OFF by default (`packaging_consume_on` = off, `fn:10`). Combo/kit explosion does not exist (section 3.a).

## 2. Scenario results (a)-(l)

| # | Scenario | Verdict | Evidence (function:line + numbers) |
|---|---|---|---|
| a1 | Sell 0.75 kg of an item stocked in kg | PASS | A-KG 10 > 9.25 kg; sale total 150 (0.75 x 200); one `sale_out` row -0.75 with ref = sale id; avg cost stays 100 (test a1). |
| a2 | Sell 3 pc, item unit pc, 1 pc = 0.2 kg, stock in kg | PASS | `_sale_stock_out fn:26`: 5 kg > 4.4 kg; total 150 (test a2). Void restores 0.4 kg for a 2 pc sale (e3). |
| a2b | Same but NO conversion row (default `unit_conv_required` = warn) | FAIL (flagged) | Sale of 3 pc accepted, stock stays 5.0 kg, one yellow `stock_unit_unknown` (`fn:28-40`). With rule = refuse the sale is refused `unit_unknown` (PASS). Owner screen `unit_unknown_items()` (web/guards.js:50) lists the items. Default is the weak setting. |
| a3 | Box of 12 whose stock is loose pcs (item unit box, base pc, 1 box = 12 pc) | PASS | 120 pc > 96 pc after 2 box; total 1200 (test a3). |
| a3b | Combo made of a DIFFERENT loose item (COMBO12 untracked, LOOSE tracked) | FAIL / NOT SUPPORTED | Selling 1 combo leaves LOOSE at 120 (expected 108) and raises no flag. `packaging_set` refuses a non-packaging component (`bad_ingredient_type`), so no kit/bundle mechanism exists. |
| b | Sale at location A must not touch B | PASS | Sale at loc1: loc1 9.25 > 8.25, loc2 stays 4. Seller of loc1 sending loc2 = `not allowed for this location` (`record_sale2 fn:19`). Seller2 at loc2: 4 > 2.5, loc1 unchanged. Owner sale at loc3 with no stock creates a -1 balance only at loc3. |
| c | FIFO/FEFO batches | PASS | 3 batches (5 kg each, created out of order, shelf life 4 d). Sale of 7: oldest-expiry batch 5 > 0, middle 5 > 3, youngest untouched; ledger rows carry batch ids 2,3; sum(batch remaining) 8 = balance 8 (`stock_post fn:63`). |
| c2 | Opening / unbatched stock in FIFO | FAIL (design) | Opening stock has no batch (A-KG balance 9.0, batches 0, test x1): never expires, is sold last (the `rem > 0` tail row, `stock_post fn:82`) although it is the oldest. |
| d | Return restores to the right batch / location | PASS | Return 3 kg: batch 2 (oldest) 0 > 3; return 4 more: all batches 5,5,5; balance 15; loc2 untouched; return > sold refused `return_exceeds_sale` (`sale_return fn:41`); 1 pc of 3 pc sale returns 0.2 kg (4.4 > 4.6). Void of a sale with returns refused `sale_has_returns`. |
| d7 | Return after the unit factor was edited | FAIL | Sale taken at 0.2 kg/pc; factor edited to 0.25; return of 1 pc restores 0.25 not 0.2 (book 4.85, expected 4.8). `sale_return fn:73` re-converts with TODAY's factor instead of using the ledger rows. |
| e | Void restores stock | PASS | Void of a 7 kg sale: batches back to 5,5,5, balance 15; 2nd void `already void`; 0.75 kg void: 8.25 > 9.0. |
| f1 | Production adds FG at the right unit | PASS | 2 batches x 10 kg: cake +20, flour 100 > 88, sugar 100 > 94, FG avg cost (12x40 + 6x50)/20 = 39, other location 0, batch 20 (`production_post fn:38,93`). |
| f2 | Actual yield | PASS | Actual 18.5 booked (20 + 18.5 = 38.5, `fn:43`); `yield_var_pct` -7.5; unit cost 780/18.5 = 42.162162; ingredients still at recipe qty (flour 88 > 76). |
| f3 | Recipe yield in pc | PASS | Yield 40 pc, 1 pc = 0.05 kg, 3 batches = 6 kg stock; selling 20 pc takes 1 kg. |
| f4 | Production void | PASS | Void refused `batch_partly_used` after part of the batch was sold (`production_void fn:18`); void of an unsold run returns flour +12, sugar +6, cake -18.5. |
| g1 | Transfer send / in-transit | PASS | Send 8 of 20: loc1 12, loc2 0, `stock_in_transit` shows 8. |
| g2 | Receive with shortage | PASS with caveat | Receive 6 of 8: loc2 6; transfer status `received`; `stock_in_transit` empties; yellow `transit_short`; shortage 2 kg is in `transit_short_open` only. All-place stock = 18 of 20 (2 kg are in nobody's balance until resolved; `stock_receive_transfer fn:33`). |
| g3 | Resolve shortage | PASS | `transit_short_resolve`: in +2 then `transit_loss` -2 at destination (`_transit_loss83 fn:14-15`); list empties; loc2 stays 6. Rule `transit_short_mode` = loss does it automatically (`fn:37`). |
| g4-g7 | Duplicates, cancel, over-receive, unit | PASS | Second receive = `dup`, loc2 still 6; cancel gives 3 kg back; receive 3 of 2 = `over_received`; 5 pc sent = 1.0 kg stored (`stock_transfer fn:17`). |
| g8 | Transfer above the sender's stock (default warn) | FAIL | Sender held 10, transfer of 20 accepted, sender = -10, receiver can book 20 (`stock_transfer fn:30` posts with neg mode `full`; `stock_post fn:38` only blocks in mode `block`). Stock is created from nothing. |
| g9 | Batches travel | PASS | Send 7 of two 5 kg batches: sender 0,3; receive 5: one destination batch of 5 with the same `expires_at`; sum batches = balance. Shortage is taken from the younger batch (`receive fn:19`). |
| h1-h4 | Count adjustment | PASS | Book 10, count 12: delta +2, avg cost stays 10 (gain without cost does not dilute, `_avg_next`); recount same = delta 0, no row; count entered as 10 pc = 2.0 kg. |
| h5 | Count loss on batch item | PASS | Loss of 2 comes off the earliest-expiry batch: 5,3,5. |
| h6 | Count gain on batch item | FAIL | Gain of 1 creates no batch: batches 13 vs balance 14 (`stock_count_adjust fn:22` passes no batch). |
| h7 | Variance highlighted | FAIL (default) | `count_tolerance_pct` is unset, so a +2 on 10 raises 0 `stock_count_variance` rows (`fn:23`). |
| w | Wastage | PASS | 1 kg from a named batch: 5 > 4; 5 pc = 1.0 kg out. |
| i1-i3 | Offline replay, duplicates | PASS | Offline sale 3 h old keeps `sold_at`, takes stock 5 > 3; replay same client id = `dup`, one row; another user replaying it = `client_id_taken` (`record_sale2 fn:21-23`). |
| i4 | Block mode vs a "late" sale | FAIL (control bypass) | `stock_negative_mode = block`, stock 3, sale 10: with `p_sold_at` = now: refused `insufficient_stock`; with `p_sold_at` = now - 5 min through plain `record_sale2`: ACCEPTED, balance -7. `_sale_stock_out fn:12` makes any sale older than 2 min "soft" and `stock_post fn:38` blocks only `full`. `web/pos.js:308` sends the phone clock as `p_sold_at` on every sale, so a phone 2+ min behind (or any direct RPC caller) defeats the block. Only a yellow `stock_negative` is raised. The switch `offline_soft_stock` is moot (only matters inside the first 2 min). |
| i5 | Sale older than 72 h | FAIL | A 100-hour-old offline sale is re-dated to now (`record_sale2 fn:25`), no flag: sales and stock-out land on today. |
| j1 | `allow` | PASS (by design) | 5 - 8 = -3, no exception. |
| j2 | `warn` | PASS with gap | Accepted, -3, one yellow `stock_negative`; a second, deeper sale the same day (-5) raises no second flag (dedup on text/day, `stock_post fn:54`). |
| j3 | `block` | PASS | Refused `insufficient_stock`; whole sale rolled back (sale count unchanged, balance 5); selling exactly 5 > 0 works. |
| j4 | `block` + grant `sell_below_zero` | PASS with gap | Accepted, -2; the use is logged only if rule `neg_grant_log` is on (default off: 0 rows, `fn:47`). |
| j5/j6 | Invalid mode text; production short | PASS | `set_rule` refuses "blok"; maker producing 40 batches with too little sugar/flour = `insufficient_stock` (`production_post fn:55`). Owner passes this check (`has_grant` true for owner; observed in an earlier probe, not in the table). |
| j7 | Refill of a negative balance | FAIL | Balance -2, production-in 10: balance 8 but batch remaining 10 (batch sum > balance). Expiry/FEFO lists show 2 phantom units. |
| k1-k3 | Rename, category change, code edit | PASS | Rename: balance 10 kept, next sale reduces the same row (stock keyed by item uuid). `item_set_category`: stock_levels category filter follows. Code edit refused (`code_immutable`). |
| k0 | Change `base_unit` kg > pc while 10 on hand | FAIL | Accepted; the number 10 silently changes meaning (`items_unit_conv82` guards only when rule = refuse). |
| k4 | Deactivate an item that holds stock | FAIL | `stock_levels` hides it (0 rows) while `stock_valuation` still counts 8 x 100 = 800. |
| k5 | Set tracked = false, sell, set tracked = true | FAIL | Book stays 8, real 7; no flag. No guard like `item_has_stock` exists for `tracked`. |
| k6 | Item merge | NOT SUPPORTED | No merge/dedupe function (only `category_merge`). Duplicates can only be emptied by count adjustments (loses cost and batches). |
| form | Forms 04-x/05-1 paths | CODE-READ | Qty goes through `_base_qty(item, qty, it.unit)` (`_elp_post_line`); a failed post becomes yellow `ledger_post_failed`; when the stock screen is primary the form line is `skipped covered_by_screen` and listed by `unmatched_forms`. `form_051_mode` default `reference`. Not executed. |
| online | Online orders | CODE-READ | Stock moves only at delivery: `online_order_deliver` calls `record_sale2` (same trigger path, `sold_at` null so block applies). Packing check/reserve is advisory (`_oo_short77`). `online_order_link_sale` links any sale without comparing lines. |
| l1 | opening + production + receipts - sales - wastage - transfers +/- adj = closing, per item / location / period | NOT SUPPORTED | No statement function. `k3_store_ledger` (report) gives per item x reason in/out/net for a period, no opening, no closing, no location column, no variance (columns: item_code, item_name, unit, kind, movements, in_qty, out_qty, net_qty); it excludes reversed pairs (`_r3q_k3_store_ledger fn:12`). Sum of its net over a day equals the balance only when the period starts at zero (A-KG 10.4 = 10.4 in the test). `stock_ledger_rows` is a row list, per location, max 1000 rows. |
| l2 | Ledger vs cached balance | PASS | `stock_reconcile(false)`: 0 rows clean; +1 tamper shows 1 row diff +1; `stock_reconcile(true)` repairs and audit-logs (`fn:24`). |
| l3 | Batch table vs balance | NOT SUPPORTED | `stock_reconcile` ignores batches: F-BATCH batches 13 vs balance 14 gives 0 rows; no batch consistency function exists. |
| l4 | Sales lines vs stock ledger | NOT SUPPORTED | No report compares what was sold with what left stock. A query (test l4) finds the untracked-sale mismatch M-1 (sold 3, ledger 2) at once, but nothing runs it. |
| l5 | Existing variance reports | PASS (partial) | `f3_raw_vs_recipe` (expected vs actual ingredient use per run; flour diff 0 and the voided run excluded), `f2_yield` (sheet vs run qty), `k2_count_variance` (04-3 paper counts), `inventory_vs_gl` (money only: GL vs valuation with reasons and an "unexplained" residual, `inventory_vs_gl fn:8-90`; returns `data_needed` until accounting is started), `unmatched_forms` (paper forms vs screen records, not sales). None is a quantity statement. |

## 3. Detail notes

### 3.a Combo / kit
`product_packaging` is the only "component" table; `packaging_set` requires the component to be `item_type = 'packaging'` and the product `finished_good`/`resale`. A box of 12 is only supported as one item with a unit conversion (a3). A combo of different tracked items has no explosion, and selling an untracked combo is silent (a3b).

### 3.b Where a mismatch can be seen today
- Per sale, yellow: `stock_unit_unknown`, `stock_negative` (once per item/day), `offline_soft_stock`, `sold_expired` (red), `return_no_stock_trace`, `packaging_not_consumed`, `transit_short`.
- Lists: `unit_unknown_items()`, `never_opened_negative_items()`, `transit_short_open()`, `stock_reconcile()`, `ledger_post_problems`.
- NOT visible: sales-vs-ledger gaps, batch-vs-balance drift, untracked/deactivated item drift, opening-to-closing proof per item, the 2 minute "soft" bypass.

### 3.c Reconciliation equation - what exists vs the ask
| Term | Where it lives today |
|---|---|
| Opening | `stock_ledger` reason `opening` (row), no "balance as of date" function (only `inventory_vs_gl` replays value, money only) |
| Production | `production_in` (+ `issue_out` for ingredients), reports f1/f2/f3 |
| Receipts | `purchase_in`, `transfer_in`, `sale_return` (return mixed with receipts in k3 `kind`) |
| Sales | `sale_out`, `sale_void_in` (excluded as a pair by k3) |
| Wastage | `wastage`, `transit_loss`, batch expiry via `stock_expire_batch` |
| Transfers out | `transfer_out`, `reversal` |
| Adjustments | `count_adjust`, `opening` |
| Closing | `stock_balance` (cache, checked by `stock_reconcile`) |
Everything needed is in the immutable ledger (triggers `stock_ledger_no_update`, `_ledger_to_balance`); only the report is missing.

## 4. Gap analysis

Severity: H = money/control can be wrong and the owner cannot see it; M = wrong or hidden under realistic use; L = polish/default. Effort S < 1 day, M 2-4 days, L > 1 week.

| ID | Gap | Business impact | Sev | Evidence | Fix outline | Effort | Depends on |
|---|---|---|---|---|---|---|---|
| G1 | No per-item/per-location/per-period stock movement statement (opening + production + receipts - sales - wastage - transfers +/- adjustments = closing, variance) | Owner cannot prove shrinkage or find which movement explains a stock gap; has to read 1000-row ledger lists | H | l1: k3 has 8 columns, no opening/closing/location/variance; `stock_ledger_rows` limit 1000 | New read-only `stock_movement_statement(from, to, loc, item/category)`: opening = sum(qty_delta) before `from`, buckets by reason group (production, purchase/receipt, transfer in, return, sale, void, wastage, transit loss, transfer out, count/opening adj), closing = sum to `to`, variance = closing - cached balance when `to` = today; cost columns only with cost grant; report-catalog entry + web screen from the item card | M | none (ledger complete) |
| G2 | No sales-vs-stock reconciliation | A sale can leave stock untouched (unit unknown, untracked, no conversion) and only a per-sale yellow line says so; no totals | H | a2b (stock stays 5.0), k5 (book 8, real 7, no flag), l4 | Nightly/on-demand `sale_stock_gap(from,to,loc)`: per item base qty of done sales (voids excluded) vs ledger `sale_out + sale_void_in`; red exception `sale_stock_gap` above a tolerance; list unconvertible lines separately | S-M | G1 shares the ledger buckets |
| G3 | `stock_negative_mode = block` is bypassed by a client-controlled `p_sold_at` older than 2 minutes | Owner's strongest oversell control silently off for any phone with a slow clock or any API caller; stock goes negative with only a yellow flag | H | i4b: stock 3, sale 10 accepted, balance -7; `_sale_stock_out fn:12`; `pos.js:308` | Treat a sale as late only when `bos.offline_replay` is set (record_sale_offline) or the queue replays; in `record_sale2` online path ignore `p_sold_at` older than a small skew (or clamp to now); set `offline_sale_max_age` default (e.g. 72 h) and make `offline_soft_stock` meaningful | S | none |
| G4 | Unit-unknown sale is accepted and stock not reduced by default | Silent oversell of items with a unit/base mismatch until the owner opens the guard screen | M | a2b; `_sale_stock_out fn:28` default warn | Default `unit_conv_required` = refuse for tracked items (items_unit_conv82 already guards item save); keep warn only as an explicit choice; advisor row | S | none |
| G5 | Return after a unit-factor edit restores the wrong quantity; factor and `base_unit` can be changed with stock/sales present | Book stock drifts by (new - old factor) x qty on every later return; base unit change re-reads the number | M | d7 (4.85 vs 4.8); k0; `sale_return fn:73` | Base the restore on the sale's own `sale_out` rows scaled by returned/sold ratio (qty in the line's unit); guard `base_unit`/`unit` change and factor change when `stock_balance.qty <> 0` or sales exist (new version row instead of overwrite) | S-M | none |
| G6 | Transfer above the sender's stock accepted in default mode | Stock appears at the destination from nothing; sender negative | M | g8 (-10); `stock_transfer fn:30` | New neg mode for transfers/wastage/issue: always strict unless `sell_below_zero`-type grant; or `stock_post` p_neg `strict` | S | none |
| G7 | No combo/kit (BOM-on-sale); untracked combo is silent | Combo sales (box of mixed sweets, gift pack) leave component stock overstated | M | a3b (120 vs 108), `packaging_set` rule | `sale_components(product, component, qty)`; `_sale_stock_out`/`_sale_stock_void`/`sale_return` explode lines (reuse `_ret_pack80` pattern); flag when an untracked sellable item with components is absent | M | G2 (gap report catches misses meanwhile) |
| G8 | Batch table not reconciled with balance; gains/refills create no batch; opening has none | FEFO and expiry alerts miss stock (opening/gain) or show phantom stock (refill of a negative balance) | M | h6 13 vs 14; j7 10 vs 8; x1 9 vs 0; l3 | Add batch check to `stock_reconcile` (sum batches vs balance, both signs); on count gain / refill create an "adjustment batch" (no expiry or owner default); on positive refill of a negative balance cap batch qty at qty_in - deficit | M | none |
| G9 | Item lifecycle can break stock silently: untrack with stock, deactivate with stock hidden from `stock_levels`, no merge | Duplicate items cannot be fixed without losing cost/batches; hidden stock still valued | M | k4 (0 rows vs 800); k5; k6 | Block `tracked=false` when balance <> 0 (same pattern as `item_has_stock`); `stock_levels` include inactive items with qty <> 0 (flagged); `item_merge(from, into)` posting paired ledger rows with cost, batches and a link table | M | G1 for proof after merge |
| G10 | Offline sale older than 72 h re-dated to now, unflagged | Sale and stock-out on the wrong day, daily close and period lock wrong | M | i5; `record_sale2 fn:25` | Keep the phone date up to a rule limit; beyond it refuse into a manager review queue or flag red `sale_redated` | S | G3 |
| G11 | Transit shortage drops out of every view after receive until resolved | 2 of 20 kg "disappear" from stock and in-transit (value hidden unless user opens a separate list) | L | g2 (12+6=18) | Show `transit_short` open rows inside `stock_in_transit` and in the statement (G1); advisor suggests `transit_short_mode = loss` with owner alert | S | G1 |
| G12 | Monitoring rules are off by default | Count variance, grant use, repeated negative sales are not highlighted | L | h7; j4; j2 (one flag per item/day) | Advisor defaults: `count_tolerance_pct`, `neg_grant_log` on, daily summary exception with count of negative sales; show owner bypass of production short check as a log line | S | none |
| G13 | Server trusts the phone's unit conversion; typed alt qty not stored | Stale cached conversion (offline) or a typo changes stock with no trace of "3 pc" | L | `pos.js:83-111`, `record_sale2 fn:62` | Send `unit` + qty typed per line; server converts with current rules and stores both (`alt_unit`, `alt_qty`) | S-M | G5 |
| G14 | Online order link does not compare lines | An order can be "delivered" against a different sale | L | `online_order_link_sale` (CODE-READ) | Compare line item/qty, warn or block on mismatch | S | none |
| G15 | Form 05-x/04-3 shadow paths only checked for skipped lines | A failed form post (yellow `ledger_post_failed`) or a sheet/run qty gap is easy to miss | L | CODE-READ `_entries_post_ledger`, `f2_yield qty_gap` | Surface open `ledger_post_failed` counts and sheet-vs-run gap on the owner board | S | none |

## 5. Suggested priority (input for stage 3)
1. G3 (control bypass, one-line semantics) and G6 (transfer creates stock): both small, both money-relevant.
2. G1 + G2 together (the missing reconciliation the owner asked for) - same ledger buckets.
3. G4, G5, G10 (defaults and conversion integrity).
4. G8, G9, G7 (batch and item lifecycle, kit support).
5. G11-G15 (visibility polish).

## 6. How to re-run

```
bash tests/sql/final_build.sh a2db        # once (about 4 min)
bash tests/sql/audit2/a2/run_a2.sh a2t                          # all a2_*.sql in order; prints PASS/FAIL notices, then pass|fail counts
bash tests/sql/audit2/a2/run_a2.sh a2t a2_00_setup.sql a2_10_sales.sql   # a subset (always include 00 first)
```
Files: `a2_00_setup.sql` (users, 17 items, openings), `a2_10_sales.sql` (a,b,c,d,e), `a2_20_prod_xfer_count.sql` (f,g,h,w), `a2_30_offline_negative_items.sql` (i,j,k), `a2_40_reconcile_reports.sql` (l).
Every FAIL line in the output is a finding in section 2; tests for features that are absent assert the feature exists, so they print FAIL by design.
