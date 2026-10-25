# Variants, per-business items, price lists (phase125) and large-catalogue search (phase126) - registration for the lead

Owner decisions this serves: GROUP_ERP_STAGE_A.md sections 13 (fashion / cloth: variants size x colour x fabric, retail + wholesale + online + tailoring, configurable per product group) and 14 (dealership: thousands of items per branch). Sweets is business #1 and behaves identically (proof below).

## (a) web/ia.js - add this line (group `stock`; visible to the owner or anyone holding variants_manage)
```js
  rec('variants', 'stock', ['ভ্যারিয়েন্ট (সাইজ / রং)', 'Variants (size / colour)', 'Variants (size / colour)'], { icon: 'items', ok: (c) => c.own || c.GF.variants_manage === true, kw: ['variant', 'size', 'colour', 'color', 'fabric', 'style', 'matrix', 'sku', 'barcode', 'price list', 'wholesale', 'cloth', 'fashion'] }),
```
(Icon `items` exists in ia.js. No OWNER_ONLY entry: a holder of the grant may open it; the page and every server function check scope again. Hide it for the sweets-only owner if wanted: `my_businesses125()` returns only businesses the caller works in.)

## (b) web/index.html - script tag, after org122.js / cashmoves.js (needs only web/app.js globals BOS_APP, BOS.L / lab)
```html
<script src="variants125.js"></script>
```

## (c) SQL added (after phase122; canonical order ...122, 123, 124, 125, 126; idempotent, paste twice = no change)
* phase125 (marker var125): `items.org_unit_id` (+ style_id, variant_key, variant_opts); tables option_sets, option_values, item_styles, style_axes, price_lists, price_list_items; functions option_set_save, option_values_save, style_save, variants_generate, variants_overview, variant_matrix, my_businesses125, price_list_save, price_list_items_set, price_for125; rule `variants_on` (switch, default OFF); grant `variants_manage`.
* phase126 (marker var126): `items.brand`, indexes (btree prefix + pg_trgm GIN when available), `items_search`, `items_search_info126`.
* Nothing existing is changed except: the `items_read` policy (see below), one nullable column fill (`items.org_unit_id` = the sweets business), a BEFORE INSERT/UPDATE trigger `items_org125` on items (fills a new item's business: the caller's only business, otherwise the sweets business; an item never moves business later).
* `items_read`: replaced ONLY while it is still the original "any active user" policy (or ours). With `variants_on` OFF it behaves exactly as before. With it ON an item is visible only inside the caller's business (owner: all). If Stage C1 (phase123) has already tightened `items_read`, phase125 leaves it alone and says so with a NOTICE; C1's policy then decides (the C1 owner should make sure items without org_unit_id or of another business are hidden the same way).
* Scope used here (deliberately NOT the `management` bypass of can_loc): owner = every business; others = the businesses of the locations they are assigned to in user_locations. Writes need the owner, or the grant `variants_manage` AND the business being one of theirs. If C1's `can_scope` lands, the three helper functions `_my_biz125`, `_biz_vis125`, `_biz_mgr125` are the only places to repoint.

## (d) How the owner starts a cloth business (nothing is hardcoded)
#/organization -> legal entity -> business (template `fashion_apparel`) -> branch + location mapped to it -> people + grant `variants_manage` -> turn `variants_on` ON -> #/variants: Option lists (e.g. Size S M L XL / 28 30 32 / kids age bands, Colour, Fabric; any list per product group) -> Styles (pick up to 4 lists in order, first = rows, second = columns) -> open the style -> Check first -> Create. Each combination becomes an ordinary item (code = style + option codes, own EAN-13 barcode, tracked), so purchase, stock, transfer, POS and reports use it unchanged; stock per variant per location is the existing stock_ledger / stock_balance. Add a new colour later and press Create again: only the new combinations are made (idempotent). Price lists (retail / wholesale / online, date validity, quantity tiers) override nothing: `items.sell_price` / `wholesale_price` are never touched; `price_for125(item, channel, date, qty)` is the one read that returns "list price if a valid row exists, else the item's own price" and no existing sales flow calls it yet (wiring it into POS / invoices is the next slice).

## (e) PLAN to relax the global items.code unique later (NOT done in phase125; the old constraint is untouched)
Today `items.code` is globally unique (`items_code_key`), plus `items_barcode_uq` (barcode, global). phase125 adds `items_org_code_uq125 (org_unit_id, code)`; with one business it can never fire, with several businesses it is the constraint that must remain. A second business therefore cannot yet reuse a sweets code (the generator refuses with `code_taken` and names the clash; use a business prefix in style codes meanwhile). To relax, in this order, in a separate phase, only when a second business really needs the same codes:
1. Inventory every function that finds an item by code or barcode (grep `from public.items where code`, `i.code =`, `barcode =` in scan_*, bulk import items_bulk_apply, POS barcode lookup, labels, recipes import: about 13 direct sites and 47 files mention `where code =`). Each must take the business from its caller (location -> org_unit -> business, `org_unit_scope`) or from the document it belongs to.
2. Make `items.org_unit_id` NOT NULL (every row is filled; the trigger fills new rows).
3. `alter table items drop constraint items_code_key;` (keep `items_code_immutable`, `items_org_code_uq125`, `items_code_prefix_idx`); change `items_barcode_uq` to `(org_unit_id, barcode)`; give `item_code_seq` a per-business prefix (default code `I-001` style is sweets only).
4. In `variants_generate` change the `code_taken` pre-check to "same business".
5. Tests: the same code in two businesses is allowed, twice in one business is refused, every sweets lookup returns the same rows, run_all_sql at baseline. Rollback = re-add the unique constraint (only valid while no duplicate exists).

## (f) Measurements (synthetic 20,000 hardware items + 57 sweets items, scratch DB, tests/sql/var126_perf.sh; shared box with other agents running, so absolute numbers are noisy, best of 3, as the hardware staff user = scope applied)
| call | time |
|---|---|
| items_search 'emulsion' (name substring, 1,833 matches, page 50 + counts) | 93 ms |
| items_search 'putty 4L' | 60 ms |
| items_search Bangla substring | 75 ms |
| items_search rare term 'item 19999' | 87 ms |
| items_search code prefix / barcode exact | 64 / 69 ms |
| items_search category + brand filter, page 3 | 17 ms |
| items_search no query, first page with counts / counts off | 56 / 37 ms |
| items_search deep page (offset 20000) | 73 ms |
| items_search short query 'em' (prefix only) | 51 ms |
| for comparison: `select count(*) from items` (existing policy, 20k rows) | 142-158 ms (switch ON and OFF equal: the new policy adds no measurable cost) |
| for comparison: `select ... from items order by code limit 50` | 6 ms |
| insert of 2,000 items without / with the phase126 indexes | 724 / 774 ms (about +7%) |
| table + indexes size 20k items | 8.2 MB -> 12 MB |
Notes: the planner prefers a sequential scan for a common word (9% of rows); the trigram index is used for selective words. With pg_trgm absent the fallback is btree prefix indexes (names then match from the START only); `items_search_info126()` reports the mode. pg_trgm is installed into schema `extensions` (not `public`) so its ~30 helper functions do not enter the API schema. The old screens still load all items in the browser; moving them to `items_search` (paging) is the next slice and is what the 20k catalogue needs (web item lists are NOT changed by phase126).

## (g) Tests
* supabase/phase125_test.sql 139/0 (switch OFF refusals, backfill, old constraint kept, option sets/values, styles, generator: dry run, 10 -> 15 variants, idempotent, pick subset, retired values, 3 axes, kids age bands, too_many, code clash, barcode check digit, stock per variant through stock_ledger, two businesses isolated by direct select / RPC swap / id guess, price lists by channel, date validity, quantity tier, item price not overwritten, audit, no hard delete, second paste no change, sweets numbers unchanged).
* supabase/phase126_test.sql 53/0 (scope, search by code / barcode / name / Bangla / short query, literal % and _, filters, paging, counts, limits, no cost field, second paste).
* tests/sql/var125_before_after.sh: seeded A3/A5 data, 13 fingerprints (trial balance, profit_truth112, net_profit_report, stock_recon_statement, factory_branch_statement, sales / stock / journal totals, can_loc body, every older function body, rules, item list, stock balance) identical before/after pasting phase125 + phase126.
* tests/web/variants125_test.js (mocked RPCs with the real shapes): list, matrix with a missing cell, dry run then generate with a picked subset, saves, friendly errors, switch-off banner, view-only, no business, business picker, Bangla, escaping, 360px no horizontal overflow, no JS errors.
* phase122_test.sql T2/T9: the exemption list of "functions / policies that may mention the org objects" now also names the phase125/126 objects (the only edit to an existing test).

## (h) Not built / pending
Wiring `price_for125` into POS / invoices / online orders; purchase and POS size-colour grid entry; variant-aware labels and bulk import (CSV of styles + options); item list screens on `items_search` (paging) and a business switcher on them; exchange / return rules; season / collection; tailoring and cut-make-trim costing; per-business item codes (section e); a UI to retire a variant item (use the existing item screens: it is an ordinary item); price list rows by CSV; an automatic fallback test of the btree-prefix mode (only its DDL was run).
