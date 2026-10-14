# Step Cat (phase100) - Category and Sub-category wherever an item is involved

Branch `fix/phase-Cat` (from `integration/p72-p79`, `fix/phase-INT3` merged: phase98 exists, nothing to re-base). Owner rule (phone only): wherever an item / product is involved there must be a Category and a Sub-category, selectable (never typed free), filterable, shown.
`items.category` / `items.sub_category` (phase8) stay the text columns every old screen reads; nothing existing is rewritten. Only new files plus small `bos100`-tagged edits of 6 screens.

Files: `supabase/phase100.sql`, `supabase/phase100_test.sql`, `web/catpick.js`, `tests/web/catpick_test.js`, `tests/web/catpick_pw_test.js`, this report. Edited (tagged `bos100`, 1-14 added lines each): `web/pos.js`, `web/stock2.js`, `web/bulkitems.js`, `web/scan.js`, `web/itemmaster.js`, `web/recipes.js`; appended at the END: 2 recs in `web/ia.js`, 1 script tag in `web/index.html`.

## STEP 1 - Audit (what existed BEFORE this step)

Legend: **a** editable, **b** selectable as filter, **c** displayed, **d** in reports / grouping / export.  Cat = Category, Sub = Sub-category.  Y = yes, - = no, n/a = the screen has no item list of its own.

| # | Screen / flow (file) | a edit | b filter | c shown | d report / group / export | what bos100 adds |
|---|---|---|---|---|---|---|
| 1 | POS item grid (`pos.js`) | n/a (New item opens the item editor) | Cat chips Y, Sub - | Cat only as a chip, not on the item card | via the report builder (Cat only) | Sub chips under the chosen Cat + Sub filter; Cat chip names follow the master (pos.js, 5 tagged lines) |
| 2 | Purchase new bill / return, line item (`purchase.js`) | n/a | - | - | - | Cat + Sub bar above the lines (filters the item list, option hint shows Cat . Sub) - no purchase.js edit |
| 3 | Purchase "+ New item" quick sheet (`itemmaster.js` ni_*) | Cat Y (dictionary select), Sub - | - | - | - | Sub select that follows the Cat, sent as `sub_category` (2 tagged lines) |
| 4 | Stock hub levels (`stock2.js`) | n/a | Cat Y, Sub - | Cat Y (row line), Sub - | `stock_levels` filter Cat only | Sub select in the filter sheet + client side Sub filter (3 tagged lines) |
| 5 | Stock issue / transfer / count / wastage / opening / production item picker (`stock2.js` itemFld) | n/a | - | - | - | Cat + Sub bar over the item field (no stock2 edit for this part) |
| 6 | Expiring / in transit / approvals tabs (`stock2.js`) | n/a | - | - | - | not done (they list batches / transfers, not an item catalogue) |
| 7 | Recipes list + editor + ingredient and finished-item pickers (`recipes.js`) | n/a | - | - | - | list: Cat + Sub filter row and Cat shown on each row (3 tagged lines); pickers get the bar |
| 8 | Production sheet (`recipes.js` prodButton, `stock2.js` a_prod) | n/a | - | - | - | picker bar (same as 5) |
| 9 | Artisan recipe book (`recipebook.js`) | n/a | - | - | - | not done (artisan -> recipe list; recipes screen covers the catalogue) |
| 10 | GRN / goods received list (`stockx.js`) | n/a | - | - | - | not done (lines come from a bill, not a picker) |
| 11 | Landed cost (`landed.js`) | n/a | - | - | - | not done (works on posted bill lines) |
| 12 | Scan match / scan create (`scan.js`) | Cat typed as free text (invalid values are refused by item_new), Sub - | - | - | - | Cat is a select of the master (1 tagged line); Sub NOT added (server function `scan_*` would need re-creating: see Not done) |
| 13 | Barcode (`barcode.js`) | n/a | - | - | - | n/a: it only returns the code |
| 14 | Bulk item editor (`bulkitems.js`) | Cat only through CSV import (not in the grid) | Cat Y, Sub - | - | CSV export has Cat, no Sub | Sub filter, Cat . Sub under the code, "Set Category of selected" (bulk RPC) (7 tagged lines) |
| 15 | Product list + editor (`items2.js`) | Y, both are selects of the editable lists | Y, both | Y, both (row line) | - (no export on this screen) | Sub list follows the chosen Cat + hint when the rule is warn / required (hook, no items2 edit) |
| 16 | Item master / dictionary import (`itemmaster.js`) | Y (new by category, import) | Y (by category chooser) | Y | import preview counts by Cat | master table fed by the import (option_lists trigger) |
| 17 | Editable lists (`lists.js`: item_categories, item_subcategories) | Y (owner, list rules) | n/a | n/a | n/a | the master keeps these two lists in step (best effort) |
| 18 | Online orders (`salesx.js`) item select | n/a | - | - | - | Cat + Sub bar over the lines |
| 19 | Paper forms (`entry.js` ITEM fields, forms_*) | n/a | - | - | - | Cat + Sub bar (datalist `dl_items`) |
| 20 | Customers / price lists (`customers.js`, forms price list) | n/a | n/a | n/a | n/a | n/a (no item catalogue; price list rows are paper-form ITEM fields = row 19) |
| 21 | Report builder (`reports.js`, `filters.js`, SQL `rpt_agg_sql`) | n/a | Cat Y (filter `categories`) | Cat Y (group column) | group by Cat Y, CSV export Y, Sub - | not changed (engine function not re-created) - see 22 |
| 22 | Business items / ABC (`biz.js`, SQL `biz_items`) | n/a | - | - | no Cat, no Sub | new page `#/catreport` + SQL `biz_items_by_category` (read-only wrapper, cost only for cost-right holders), CSV |
| 23 | Stock valuation (SQL `stock_valuation`) | n/a | - | - | no Cat | SQL `stock_valuation_by_category` + same page |
| 24 | Cost board / costing (`costboard.js`, `costing.js`) | n/a | - | - | - | not done (small exception lists) |
| 25 | Labels / price tags / templates (`tpl_labels.js`, `tpl_docs.js`, `tplpicker.js`) | n/a | - | - | - | not done: stickers print name, barcode, price only (see Not done) |
| 26 | Old items page in `app.js` | Cat select, Sub - | Cat chips | Cat | Cat in CSV backup | not changed (superseded by items2) |
| 27 | Settings: shelf-life rule scope (`settings2.js`) | rule scope select of Cat | n/a | Cat | n/a | not an item screen |
| - | `forms_factory.js` field `cat` | - | - | - | - | NOT the item Category: a paper-form choice (sweet / cake / bakery / other) |

Summary of the gaps found: the master did not exist (two flat editable lists + free text); Sub-category was missing from every filter, picker, report and from the POS; Category was typed free in the scan screen; no report grouped by Sub-category; no rule to require a Category; no screen to merge / rename / reorder / move.

## STEP 2 - What was built

### SQL `supabase/phase100.sql` (additive, paste-twice safe, guard needs 72..97)
* **No existing function is re-created** (phase100_test T0 compares `md5(pg_get_functiondef)` of every public function before / after: 0 changed), so nothing has to be re-based on phase98 (INT3, merged) or phase99 (Opt: no commit exists yet on any branch I can read; because phase100 touches no function, a later phase99 cannot be damaged by it and phase100 cannot be damaged by phase99, in either paste order).
* Table `item_categories` (id, parent_id null = Category, `code` = the text kept in items.category / sub_category, name_bn, name_en, name_mix, sort, active, merged_into, client_id, audit columns). Unique code per parent, unique active name per parent, unique client id. RLS: read for active staff, nobody writes it directly. Audit: `log_change` on every row change. No hard delete.
* Seeded from DISTINCT existing items.category / sub_category plus the editable list `item_categories`; names = list label, else `items.category_bn`, else the stored code (a Bangla-empty dictionary label falls back to the English label). Nothing invented. Seed of this shop's data: 5 Categories, 57 items linked.
* `items.category_id` / `sub_category_id` kept in sync by a BEFORE trigger (also registers a value an old screen typed). The trigger can never block an item save.
* Rule `category_required_on_item` off (default) | warn | required, recommendation row `warn`. `required` is checked at the END of the transaction on the FINAL row (a deferred constraint trigger): the item editor inserts the item and sets the Sub-category in a second statement. A NEW item without a Category is refused; a Category that has Sub-categories needs one; old items stay editable; clearing a Category is refused.
* RPCs (all SECURITY DEFINER, anon has no execute): `category_list`, `category_save` (add / sort / switch off; client id = idempotent), `category_rename` (owner), `category_merge` (owner, audited, idempotent), `category_move`, `category_reorder`, `item_set_category`, `item_set_category_bulk`, `category_sync100`, `category_rule_state`, `items_missing_category`.
* Reports: `biz_items_by_category(from, to, loc, level)` and `stock_valuation_by_category(loc, level)` wrap the existing functions, so permission checks and cost secrecy are exactly those of the ungrouped report; grouped totals equal the ungrouped total (tested).
* Manage = owner or grant `item_create` / `item_bulk`; rename + merge = owner only.

### Web `web/catpick.js` (loaded last)
`B.catpick` (tree with a read-only fallback built from the items when phase100 is missing, two-level chip / select picker `mount`, `field` / `read` pair of selects, `subSelect`, `filterRow`, `subChips`, `bulkSheet`, remembered last choice per picker with try/catch localStorage), `B.catfilter(items, sel)`, guarded enhancers (one MutationObserver) for the item pickers of other screens, pages `#/categories` (add, rename, merge, reorder, switch off, move items, move a Sub-category, rule select, missing list with bulk set) and `#/catreport` (sales / stock value, Category or Category + Sub, CSV). Handlers all `cat_`. Language: English mode all English; Bangla keeps Category / Sub-category / Item in English; mix.

## Tests (numbers are from this branch, scratch Postgres 16 clones, port 5544)

TESTNUMBERS

## যাচাই হয়েছে
VERIFIED

## পড়ে বোঝা
READ

## যাচাই হয়নি
NOTVERIFIED

## Paste order
`... phase97, phase98, phase100` (phase100 re-creates nothing, so its place after 98 is only for tidiness; `tests/sql/final_build.sh <db> "<canonical order> phase100"` builds it; I did not edit `final_build.sh` or `docs/PASTE_ORDER.md` to avoid a merge conflict with the Opt / INT3 branches).
