# Step C (phase74) - costing and overhead (conversion cost goes into product cost)
Branch `fix/phase-C` (from `fix/phase-C0`). Files: `supabase/phase74.sql`, `supabase/phase74_test.sql`, `web/costing.js`, `tests/web/costing_test.js`, this report.
Paste order: ... phase71, phase73, **phase74** (paste-twice safe, checked). No old phase file edited.

## !! LEAD: re-merge with phase72 (Part 1 step B) - I could not see it
phase74 re-creates, from the LATEST definitions in this worktree (phase19 + my phase73), these functions - tagged `bos74` / `bos73`:
- `production_post`: now a **7-argument core** `(p_loc, p_recipe, p_batches, p_client, p_made_at, p_note, p_actual_yield)` WITHOUT defaults, plus the old **6-argument signature as a thin SQL wrapper** (`phase74.sql:468`). Callers and older tests that use 6 arguments keep working and are never ambiguous. If phase72 changed `production_post` (e.g. the `production_requires_cost` switch): its checks must be moved INTO the 7-arg core (`phase74.sql:373-466`); a re-created 6-arg body from phase72 is overwritten by my wrapper when phase74 is pasted after it.
- `recipe_cost` (`phase74.sql:323`): same maths for the material part but now built on `_recipe_need`; if phase72 changed COGS-source or the cost basis here, re-apply it.
- `stock_production_in` (`phase74.sql:530`, C8), `_acct_docs` (`phase74.sql:594`, the production block only, marked `bos74`).
- phase72's `_p27_pl` is NOT touched by phase74 (no overlap). `_recipe_read` was re-created in phase73.
Order matters: paste phase72 first, then phase73, then phase74, then re-apply any phase72 line that lives in the four functions above.

## What was built (per brief point)
- **Cost layers**: layer 1 raw material (average, unchanged) + "আজকের কেনা দাম" row; layer 2 conversion cost INTO product cost; layer 3 showroom/admin NOT in product cost. Product cost = material + conversion rate x quantity (`production_post`: `ucb = round((material + conversion) / output, 6)`).
- **C1 `recipe_cost_components`** (`phase74.sql:56`): component type (labour / gas / electricity / factory rent / licence / machine repair / depreciation / ☐ অন্য + typed note, and owner-added types via `cost_type_add`), basis per batch / per base unit (kg) / per labour-hour (hours typed by the cost-right holder - the step suggestion of phase73 is shown beside the box but never flows in), amount may be BLANK -> `conversion_complete=false` + the text 'রূপান্তর খরচ অসম্পূর্ণ'. A change retires the old row and inserts a new one (previous values kept) + audit. Only cost-right holders can read (RLS) or write (`recipe_cost_component_set`, client_id idempotent).
- **C2 pools**: `factory_cost_pools` (location, month, type, actual amount, month|year kind, one-off flag, source manual|allocated), `location_cost_cfg` (mode off|recipe|pool + normal monthly output, BLANK until set), rate = pool / NORMAL output (never actual output). Smoothing is a setting on the cost type (`cost_type_smoothing`): none | yearly12 (yearly / 12) | avg_n with N months - seeded exactly as the brief says: repair 12, gas 3, electricity 3, licence yearly. avg_n = N months ending at the run month / months since the first entry (capped at N); months without an entry are reported as gaps, never filled by a guess. Per location the choice is off (default = today) / recipe / pool. A pool-mode run for a non-kg product is flagged incomplete (`pool_unit_not_kg`) instead of giving a wrong per-kg figure.
- **C3 production_post / production_runs**: new columns `material_cost, conversion_cost, unit_cost, std_cost, actual_cost, conversion_mode, conversion_complete, conversion_detail, yield_std, yield_actual, yield_var_pct`; NOT in the browser column grant (phase19 grant list unchanged) -> read only through `production_run_costs` (cost right). `production_post` answers cost keys only to cost-right holders. Void reverses every ledger row at its original cost (the FG row carries material + conversion) - verified.
- **C4** `recipe_cost` now loops `_recipe_need` (the function the run uses, packaging included) and returns separate rows raw / packaging / conversion; verified equal to the posted run's unit cost (with and without packaging).
- **C5** per ingredient the latest un-reversed `purchase_in` cost (`_today_cost`), a separate `today` block (batch/unit cost on that basis, gap %), yellow warning flag when the gap exceeds rule `cost_gap_warn_pct` (BLANK default = no warning). Display only: the booked cost uses the average (tested).
- **C6 GL**: new COA account 5950 (credit-normal expense) + mapping key `overhead_absorbed`; the production journal is Dr 1310 = material + conversion / Cr 1320 + 1330 = material / Cr overhead_absorbed = conversion (balanced; a run with no conversion posts exactly as before; void reverses). `overhead_trueup(loc, month)`: per type actual (pool figure of the month, yearly /12) vs absorbed (done runs' `conversion_detail`), and the single row **'অনাবশোষিত ওভারহেড'** = actual total - absorbed total. Showroom and admin cost are not absorbed (report says so).
- **C7**: optional `p_actual_yield` (default = recipe yield): the actual output is what is booked into stock and `yield_base`; cost = (material + conversion) / actual output; `std_cost` (per standard yield) and `actual_cost` stored with `yield_var_pct`; yellow flag above rule `yield_variance_warn_pct` (blank default). `recipe_yield_suggestion` reads the latest approved 05-4 sheet and returns the waste % as a SUGGESTION (`applied:false`); nothing writes the recipe.
- **C8**: stock_production_in: a typed cost always raises a yellow flag `production_manual_cost`; new switch `production_manual_needs_reason` (default OFF = today) makes a note (3+ chars) compulsory while `production_requires_recipe` is off. **Recommendation: switch `production_requires_recipe` ON** - then the manual path is closed (`recipe_required`, tested) and every product cost comes from a recipe.
- **Web** `web/costing.js` (`#/costing`): recipe cost sheet (rows + today's price + gap + incomplete flag), rate editor (blank allowed, typed hours, suggestion shown), monthly pools (yearly / one-off boxes), method per place (owner only), true-up with the unabsorbed row, run costs.

## C9 - NOT built, owner-decision items
1. **production_recost** (fix a run's cost after the fact): the ledger is immutable. A correct design is an owner-approved correction entry: a new ledger adjustment row valued at the cost difference + a balancing journal, linked to the run (`reverses`-style). Decide: who may request / approve, a limit on how far back, and whether sold quantities are re-costed or only the remaining stock.
2. **Landed cost split at bill level**: freight / loading / duty typed on the purchase bill and spread by value or quantity into the purchase_in unit cost (audit F9). Decide: spread by value or by quantity, which charges count, and whether the item-less bill lines are allowed.

## যাচাই হয়েছে (চালিয়ে)
- `supabase/phase74_test.sql`: **96 pass / 0 fail** on a fresh DB (phase8..71 + 73 + 74). Verified numbers: material 444 -> unit 44.4 (mode off, as before); recipe mode labour 100 per batch, yield 10 -> **unit 54.4 (+10)**, 3 batches = 300 on 30 kg; actual yield 9 of 10 -> 49.333333 (+11.1%) std 44.4, variance -10%; void reverses at 54.4 and returns stock; blank electricity amount -> flag + yellow exception, partial conversion booked; per labour-hour without typed hours = incomplete even when steps suggest 2 h; typed 2 h -> +10; history keeps the first labour row inactive; pool mode: labour 5000 / 1000 = 5 per kg -> +50 on 10 kg; gas 3-month window with the current month missing = (3000+6000+0)/3 with `gap_months=1`; yearly licence 12000/12 = 1 per kg; repair 24000 over 4 months since first entry = 6 per kg; total 15 per kg -> unit 59.4; a 2 kg slow-month run costs the same 59.4 per kg; the true-up shows the difference in the unabsorbed row; journal run 9 Dr 1310 594 = Cr 1320 444 + Cr 5950 150, balanced, void reversed; recipe_cost == run unit cost (54.4 and 67.1 with packaging 100); today's price 70 vs average 60: gap 16.67%, warn at threshold 10, none at 20, booked cost stays 60; cost secrecy (factory in-charge refused on recipe_cost / run costs / components / pools / true-up, direct select of `material_cost` denied, rows invisible); 05-4 suggestion 5% with recipe unchanged; manual path flags and switches.
- `phase73_test.sql` re-run on a DB built through phase74: **98 pass / 0 fail** (recipe_cost / production_post re-creation keeps the C-0 behaviour).
- `tests/web/costing_test.js` (Playwright, 360px): **39 assertions, 0 failures**, no console errors: no cost right = nothing shown, raw/packaging/conversion rows, today's price + warning chip, incomplete flag, suggestion only, blank amount sent as null, typed hours, new type by name, pools (month / year / one-off, bad amount stopped), method per place (owner only, blank normal output stays null), true-up row, run costs (void + incomplete marked), Bangla, no horizontal overflow.
- **Regression** (all 41 suites, fresh DB each; through phase71 vs through phase74): identical except **two intentional assertion failures** `phase19 T0` and `phase23 T0` "no cost columns on recipe tables" - this brief adds cost columns to `production_runs` (C3). Everything else identical (e.g. 19: 94 -> 93 pass + that 1; 23: 92 -> 91 + that 1; 26: 117, 40: 119, 50: 45, 52: 33, 62: 74, 71: 26 unchanged). Pre-existing FAILs unchanged before/after: phase8 T1, phase10 T12, phase15 T0, phase21 T1, phase47 T1 x2.

## পড়ে বোঝা (code read, not run)
- `_acct_docs` rounding: Dr uses `round(sum)`, Cr uses the sum of per-type rounds (pre-existing pattern, audit item 3) - a 1-paisa difference could appear on a run with many item types; not changed.
- The web cost sheet in `web/recipes.js` (phase19) still reads the old `recipe_cost` keys; all old keys are kept (lines, complete, batch_cost, unit_cost, yield_base) so it still renders, but it does not show the new rows.
- `location_cost_cfg` instead of `location_settings`: see decision 4.

## যাচাই হয়নি (not verified)
- Nothing run against the live database or on a real phone. No real recipe has conversion rates; every figure above is test data.
- `normal_monthly_output` and all rates are BLANK: until the owner types them, pool/recipe mode shows 'অসম্পূর্ণ' (mode defaults to off, so today nothing changes).
- Reports other than the true-up (P&L per product, branch P&L) do not read the conversion cost: the audit's "two cost sources" issue (`item_costs` vs ledger) is Part 1 step B / phase72 territory.
- Pool mode assumes the location's products are kg-based; a mixed kg / piece location needs recipe rates for the piece products (flagged, not solved).
- The 05-4 sheet's own "approved average becomes the target yield" statement (form text) is not wired to anything; only the suggestion exists.

## Mismatches with the printed forms (NOT changed, listed)
1. **10-2 expense voucher** (`web/forms.js:27-47`): the same factory costs (repair/utilities, labour) are typed on 10-2 lines and, for the true actual, again in `factory_cost_pools`. Same fact in two places until C-2ক (cost sources) feeds the pools from one bill. 10-2 has only head / paid to / receipt / amount - no bill number column; the bill number would have to go into "paid to".
2. **02-2 payroll** (salary) is the real "labour" actual but nothing links it to the labour pool; the owner types the labour pool by hand.
3. **05-3 card** has time / headcount / machines at card level (`web/forms_factory.js:200-203`); the per-labour-hour basis needs hours per batch typed again on the rate (the paper figure `total_min x headcount` is a candidate but is not read - one more copy of the same fact).
4. **05-4 yield test** (`web/forms_factory.js:241-243`) says the approved average "will be the target yield in the production report"; our suggestion shows its waste % but never changes the recipe or the standard yield.

## Owner decisions needed
1. Per place: which method - off (today), recipe rates, or monthly pool? (default off everywhere)
2. Type the normal monthly output (kg) for each factory before using pool mode.
3. Confirm the smoothing windows (repair 12 months, gas / electricity 3, licence yearly / 12) - they are settings (`cost_type_smoothing`) and were taken from the brief.
4. Where mode and normal output live: I stored them in a new table `location_cost_cfg` (owner-only, audited) because writes to `location_settings` are routed into the settings-sheet approval workflow (phase16) and its screen has a fixed key list. If you prefer them as normal location settings, say so.
5. Switch `production_requires_recipe` ON (recommended), and decide `production_manual_needs_reason`.
6. Thresholds (blank now): `cost_gap_warn_pct`, `yield_variance_warn_pct`.
7. Labour: type hours per batch by hand or accept the step suggestion as the typed figure (it is only a suggestion today).
8. C9 items above.
9. COA account 5950 / mapping `overhead_absorbed` - confirm the account for the accountant.

## Cannot be done on a phone
- Pasting `phase74.sql` and re-merging phase72 into `production_post` / `recipe_cost` (lead, computer).
- Integrating `web/ia.js` / `web/index.html` (below).
- Everything else (rates, pools, methods, true-up) is done in `#/costing` on the phone once integrated.

## For web/ia.js and web/index.html (lead integrates; I did not edit them)
```js
rec('costing', 'factory', ['খরচ ও ওভারহেড', 'Costing & overhead', 'Costing ও overhead'], { icon: 'money', ok: (c) => c.own || c.GF.view_cost === true, kw: ['cost', 'overhead', 'conversion', 'gas', 'electricity', 'labour', 'pool', 'absorbed', 'খরচ', 'ওভারহেড', 'গ্যাস', 'বিদ্যুৎ', 'রূপান্তর'] }),
```
`<script src="costing.js"></script>` after `recipebook.js` in `web/index.html`.
