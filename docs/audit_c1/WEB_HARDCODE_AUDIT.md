# WEB hardcode audit (C1) - sweets assumptions that block multi-business use

Status: READ-ONLY audit, no code changed. Base: branch `ccr-9c1f9be7-3s9qnz` (HEAD 8583954). Blueprint context: `docs/GROUP_ERP_STAGE_A.md` (branch `ccr-46b26d91-81vl9s`), `docs/HANDOVER_6.md`.
Scope: `web/*.js`, `web/index.html`, `web/manifest.json`, `web/ia.js`, `tools/*.py|js|sh`. SQL is out of scope (another agent builds B1 `org_units`).
Method: grep + reading of the lines quoted. No browser run, no live DB. Items marked [unverified] need a runtime or DB check.
Risk: S = small, local string/list swap. M = touches shared loader or several screens. L = changes data scoping/security or many files.
Tests named below are proposals (node unit test on the pure helper, or a Playwright/jsdom smoke on the screen); none exist for these yet [unverified].

Target vocabulary used below: `org_units` (business tree, from B1), `locations.org_unit_id`, `report_brand_map` (extended with `org_unit_id`), `brand_profile` (new: name_bn/en, logo, address, phone, tax id, footer per business - the shop block in `tpl_registry.js:111-233` already reads such a block from settings), `option_lists` (existing, extend with `org_unit_id`), `B.biz` (new client object: current business id + its location ids).

## 0. Counts

| Category | Items | S | M | L |
|---|---|---|---|---|
| A. Brand lists / brand constants | 9 | 6 | 3 | 0 |
| B. Showroom / location name lists and *_FALLBACK arrays | 7 | 5 | 2 | 0 |
| C. Location codes (main, s1..s4, factory, godown) | 6 | 5 | 1 | 0 |
| D. Location kind assumptions | 8 | 3 | 5 | 0 |
| E. Duty-slot lists | 4 | 2 | 2 | 0 |
| F. Company name in labels, receipts, invoices, print | 12 | 9 | 3 | 0 |
| G. Global cached lists (B.ENV, caches, localStorage) | 9 | 1 | 5 | 3 |
| H. Menus / routes with no business switcher | 6 | 0 | 4 | 2 |
| I. Bangla/English labels naming sweets brands/products | 10 | 8 | 2 | 0 |
| J. Company-wide report/dashboard totals | 9 | 0 | 6 | 3 |
| K. tools/*.py|js | 7 | 4 | 3 | 0 |
| Total | 87 | 43 | 31 | 8 |

(Counts are of rows in the tables below; one row may cover several lines of the same pattern.)

## 1. Where the app loads locations and rules at start (the choke point)

| Step | file:line | What happens | Multi-business effect |
|---|---|---|---|
| Sign-in | `web/app.js:157,187` | `sb.rpc('my_context')` -> `S.ctx` (profile, roles, perms, `locations` id list, `is_owner`) | `ctx.locations` is a flat list with no business grouping. `ctx` is also saved for offline cold start (`app.js:159,190`, `coldstart.js`). |
| After login | `web/app.js:215` | `await B.loadStatic()` | Starts the global cache below. |
| Static cache | `web/entry.js:92-102` | `ENV = {staff, items, locs, byLoc, lists, rules, grantDefs, sup}`. `ENV.locs = select * from locations order by sort` (entry.js:96); `ENV.items` = ALL items (entry.js:95); `ENV.staff = rpc staff_directory` (entry.js:94); `ENV.lists = option_lists` (entry.js:111-114 loadLists); `ENV.rules = rules` (entry.js:105-109 loadRules, `B.rule(key, fallback)` entry.js:110) | One business assumed. Every screen reads `B.ENV.locs` (about 60 call sites, see section G). Rules and option lists are global keys with no org scope. |
| Cold start | `web/coldstart.js:80-108` | Snapshot of `locs, rules, lists, grantDefs, items` per user in localStorage, re-read when online | Snapshot is keyed by user only (`'bos_cs_env_' + u`), not by business. |
| Other direct loaders | `web/app.js:430` (staff screen, reads `locations` raw), `cost116.js:130`, `costing.js:51`, `recon118.js:113`, `s1setup.js:45,50`, `stepw_common.js:67`, `paths.js:39,78`, `inbox.js:216`, `rollout.js:78`, `locations.js:67,224`, `recipebook.js:61` | Each re-selects `locations` without the `B.ENV` cache | Each needs the same business filter; easy to miss one. |
| Location switcher | `web/nav.js:232-262` (`wideLoc`, `locChoices`, `curLoc`, `setCurLoc`, `drawLocBox`) | Drawer select: "all my places" or one location; stored in `bos_curloc_<uid>`; fires `bos:loc` | This is the only existing switcher. It is flat: "all" = every location of every business, and `management`/owner see all. Consumers of `B.curLoc()`: `nav.js` (6), `biz.js`, `dash.js`, `reports.js` only [per grep]. Most other screens ignore it and build their own `LOCS()` list. |

Proposed replacement (one change, many wins): add `B.biz = { id, name, loc_ids }` loaded in `loadStatic()` from a new RPC `my_businesses()` (ctx.businesses). Make `ENV.locs` = locations of the current business only; `ENV.items`, `ENV.lists`, `ENV.rules`, `ENV.staff` fetched with `p_org` and cached per business id (`ENV.byBiz[id]`). Make `curLoc()` return only locations in `B.biz.loc_ids`. Risk L (touches the root cache). Test: unit test that switching business empties and refetches `ENV`; two-business fixture where a user of business A never sees a location id of business B in any `LOCS()` helper (grep-driven test over `B.ENV.locs` call sites).

## 2. Findings

### A. Brand lists / brand constants

| # | file:line | Hardcoded | Replacement | Risk | Test |
|---|---|---|---|---|---|
| A1 | `web/app.js:14` | `window.BOS.BRAND = {hub, bari, cakiz}` three sweets brand names (Islamia Misty Ghar, Misty Bari, AL-CAKIZ) | Read from `brand_profile` / `org_units.name_bn,name_en` via `B.biz`; delete constant | S | unit: `BOS.BRAND` absent, header uses `B.biz.name` |
| A2 | `web/app.js:13`, `web/nav.js:11`, `web/invoice.js:56`, `web/invoiceview.js:22`, `web/purchaseprint.js:22` | Five separate copies of `const BRAND = {bn:'ইসলামিয়া মিষ্টি ঘর', en:'ISLAMIYA MISTY GHAR'}` | One `B.brand()` helper backed by `brand_profile` of the current business (or of the document's `location_id` business) | S | unit: each renderer called with business X prints X's name |
| A3 | `web/forms_factory.js:259` (used `:264`) | `BRANDS = [islamia, bari, alcakes, other]` in factory form 05-5 | `B.opts('brands', ...)` fed from `report_brand_map` of the current business (the fallback list becomes `[other]`) | S | form test: brand select shows only current-business brands |
| A4 | `web/forms_cash.js:300` | Marketing register 18-1 brand CH list `imh, mb, ak, other, all` (different codes from A3: the same brand has two code sets, `islamia/bari/alcakes` vs `imh/mb/ak`) | Same DB list as A3; store `brand_code` from `report_brand_map` | S | same; plus data check that old codes still map [unverified] |
| A5 | `web/filters.js:77` | Report brand filter already DB-driven (`report_brand_map`), but map has no business column; fallback text `nobrand` at `filters.js:27` | Add `org_unit_id` to `report_brand_map`; filter `.eq('org_unit_id', B.biz.id)` | M | filter test with two businesses sharing no brand codes |
| A6 | `web/reports.js:197,208,336,540-600` (`brand_pnl`, `PB` state `:557`) | "By brand" P&L through `report_brand_map` | Same column; brand P&L only inside one business; group-level roll-up becomes a separate owner screen | M | report test: brand P&L total = business total |
| A7 | `web/ia.js:107` | Menu "Brand profit & loss" (`brandpnl`) | Keep, scoped; hide when business has no brands | S | ia visibility test |
| A8 | `web/forms_sales.js:351,377,425` | Form 20-x "Sales by location and brand" (table + flag `sales_by_gap`) | Rows from `report_brand_map` x locations of current business | M | form calc test |
| A9 | `web/assistant.js:189` | Location alias stop-words `islamia, misty, mishti, ghar` used to match spoken branch names | Derive stop-words from `B.biz.name` tokens | S | unit: alias index for a hardware shop |

### B. Showroom / location name lists and *_FALLBACK arrays

| # | file:line | Hardcoded | Replacement | Risk | Test |
|---|---|---|---|---|---|
| B1 | `web/forms_cash.js:34` `SHOWROOMS_FALLBACK` (4 named showrooms s1-s4 with brand names) | Used when `ENV.locs` has no showroom (`:36`) | Fallback = empty list + "no places set up yet" notice; names come only from `locations` | S | unit: empty locs -> empty select, no sweets name |
| B2 | `web/forms_sales.js:298` `SHOWROOMS_FALLBACK` (same 4 names) | same, used `:300` | same | S | same |
| B3 | `web/forms_staff.js:317` `SLOT_A_FALLBACK`, `:318` `SLOT_B_FALLBACK` | Duty-slot names with brand names | same; see E | S | same |
| B4 | `web/forms_cash.js:51` | Default rows `['s1','s2','s3','s4']` when no showroom locs | Default rows = live showrooms of current business, never fixed codes | S | form init test |
| B5 | `web/forms_cash.js:35`, `forms_sales.js:299`, `forms_staff.js:319` | Three copies of "live showroom" filter on `B.ENV.locs` (`kind==='showroom'`, status live/setting_up) | One `B.bizLocs({kind})` helper that also applies the business filter | M | unit on helper |
| B6 | `web/forms_sales.js:305-318` (form 20-1 "A. all showrooms side by side", "B. Factory & hub") | Row labels `Sweets factory`, `Cake factory`, `Other`, `Hub` fixed | Rows from non-showroom locations of the business (factory/godown/hub kinds) | M | form calc test |
| B7 | `web/forms.js:101-102` `TTYPES` | Transfer types `Factory->showroom`, `Showroom->factory`, `Showroom->showroom`, `Godown->location`, `Party return` | `option_lists` code `transfer_types` per business template (hardware: warehouse->counter) | S | opts fallback test |

### C. Location codes

| # | file:line | Hardcoded | Replacement | Risk | Test |
|---|---|---|---|---|---|
| C1 | `web/assistant.js:193` | `if (l.code === 'main')` adds aliases `main, মেইন, প্রধান, main shop, main branch` | Alias list from `locations.aliases` jsonb or `name_*` only | S | unit |
| C2 | `web/assistant.js:194` | Regex on codes like `s1..s4` -> "branch N", "shakha N", "Nnd shop" | Drop numeric inference or make it a per-business setting | S | unit |
| C3 | `web/forms_cash.js:51,214` | Codes `s1..s4`, `godown`, `factory` as stored values (source CH `[['godown'..],['factory'..]]`) | Store `location_id`, label from `locations` | M | form save/load test, old entries still render [unverified] |
| C4 | `web/forms.js:214` | Shift CH values `full, s1, s2` (these are shift codes, not locations: OK) - listed so nobody "fixes" them | none | - | none |
| C5 | `web/a11yfix.js:215,292`, `payroll.js:99`, `restoredrill.js:77` | `'main'`, `'s1'..'s5'` hits are DOM role / step keys, not locations | none (false positives) | - | none |
| C6 | `web/entry.js:541,768,787,801`, `dash.js:115`, `pos.js:457` | Entry serial/receipt prefix = `loc.code` (`<form>-<loc.code>-<serial>`) | Keep, but make `locations.code` unique per org_unit not globally, or prefix with business code [unverified: DB unique constraint] | S | two businesses with a code `s1` produce distinct serials |

(C4 and C5 are not counted in the table in section 0.)

### D. Location kind assumptions

`locations.js:56` `KINDS = ['showroom','factory','godown','hub','online','other']` mirrors the DB CHECK `locations_kind_chk` (closed set, see blueprint section 2.3).

| # | file:line | Assumption | Replacement | Risk | Test |
|---|---|---|---|---|---|
| D1 | `web/locations.js:56,194,209` | Closed kind list; default new kind `'showroom'` | Kinds from `location_kinds` table / org template; default from template | M | locations screen test with a new kind |
| D2 | `web/cost116.js:133`, `web/costing.js:56` | Default costing place = first `kind==='factory'` else first location | Default = first production-capable location of the current business | S | unit |
| D3 | `web/ownerboard.js:88` | Day-close widget: `kind==='showroom'` else all | Use kind flag `has_day_close` on location/template | M | widget test |
| D4 | `web/forms_cash.js:35`, `forms_sales.js:299`, `forms_staff.js:319` | see B5 | helper | M | see B5 |
| D5 | `web/forms_staff.js:517` | Place CH `shop`/`factory` | from kinds | S | form |
| D6 | `web/ia.js:66` ("Which showroom a cost belongs to"), `ia.js:172` ("Factory-to-branch statement"), `ia.js:15` group "Factory & Production" | Factory/showroom topology baked in menu labels and groups | Menu labels from template terms (`t:` keys), group hidden if business has no production kind | M | ia test per template |
| D7 | `web/ia.js:27` `AREA_G` (cash, stock, factory, assets, purchase, sales, showroom, staff, owner) | Fixed area -> group map | Per-template area list | M | ia test |
| D8 | `web/ia.js:200,222,231,235` | Persona picks: `05-1` form -> 'factory', hub persona `['home','hubcash','payables']` | Persona by role template, not by form code | M | persona test |

### E. Duty-slot lists (form 02-7 "Duty & backup card", `web/forms_staff.js`)

| # | file:line | Content | Replacement | Risk | Test |
|---|---|---|---|---|---|
| E1 | `:317-318,320-321` `SLOT_A/B` | Live-showroom based (good) but fallback and `slice(1)` (second showroom onward) assume >=2 showrooms | slots generated per location of business; role pair (manager+backup) from template | S | form |
| E2 | `:322` `SLOT_C` | `Yeast backup 1..3` (bakery) | Slot list from `option_lists('duty_slots_C')` | S | opts |
| E3 | `:323-324` `SLOT_E` | Godown, Sweet-factory store, Cake-factory store keeper+backup | from non-showroom locations of business | M | form |
| E4 | `:325-326` `SLOT_F` | Sweet/Cake factory in-charge, head artisan + backups | from template role list | M | form |

Section headings `:353,362,363,461-464` ("Section A showroom managers", "C godown", "D factory") and checklist rows `:405-457` are also sweets-specific text.

### F. Company name in labels, receipts, invoices, print

| # | file:line | What | Replacement | Risk | Test |
|---|---|---|---|---|---|
| F1 | `web/index.html:9` | `<title>` Islamia Misty Ghar | Neutral title ("Mother ERP") set at runtime from `B.biz` | S | smoke |
| F2 | `web/manifest.json:2` (and short_name/icons [unverified]) | PWA name | One manifest per business entry URL, or neutral name | S | manifest check |
| F3 | `web/i18n.js:3` | `T.app` = brand in bn/mix/en | Resolve at render from `B.brand()` | S | unit |
| F4 | `web/app.js:58` | Page header uses `BRAND.bn/en` | `B.brand()` | S | unit |
| F5 | `web/nav.js:326` | Drawer head name + `mark.svg` logo | `B.brand()` + per-business logo asset | S | smoke |
| F6 | `web/pos.js:457` | POS receipt text hardcodes `ISLAMIYA MISTY GHAR` (second line, even if `A.BRAND_TEXT` set) | Receipt head from `brand_profile` of the sale's location business | S | receipt text unit test |
| F7 | `web/invoice.js:98`, `:74-75` (SAMPLE with Rasgolla/Sandesh and "Islamiya Misty Ghar - Main branch") | Invoice header + preview sample | `brand_profile`; neutral sample | S | render test |
| F8 | `web/invoiceview.js:73,105,117,230` | On-screen invoice, share text, `tplOpts shop:{name: brandText()}` | per-document business | S | render test |
| F9 | `web/purchaseprint.js:22-23` | Purchase print header | same | S | render |
| F10 | `web/tpl_registry.js:111-233`, `tpl_docs.js`, `tpl_samples.js:31` | Document templates already take `shop` block (name, logo, address, phone, taxId, footer) from settings - good seam, but `invoiceview.js:230` only passes `name` | Pass full shop block per business; settings per org_unit | M | template test per business |
| F11 | `web/printbooks.js:22-37` ("Print & books") | Paper-book register keyed by `location_id`+form; form list `select code from forms` is global (`:21` load) | Filter forms to those enabled for the business (see H); register by org_unit | M | unit |
| F12 | `web/attend2.js:214` (`rp:{name:'Islamia BOS'}`), `web/forms_staff.js` printed checklists | WebAuthn relying-party display name; print text | `B.brand()` | S | - |
| F13 | `web/invoice.js:21,26` flags `brand` "Business name" toggle | Fine as flag; value from F2/F7 | - | - | - |

Printed paper forms (the `B.forms['..']` specs: forms.js 5, forms_cash 7, forms_factory 5, forms_sales 7, forms_staff 9, forms_stock 9 = 42 specs) carry sweets wording (sheet names "Daily showroom sheet", jalebi, yeast, chhana). They are one shared catalogue; see H4.

### G. Global cached lists and storage

| # | file:line | What | Replacement | Risk | Test |
|---|---|---|---|---|---|
| G1 | `web/entry.js:96` + ~60 consumers (`B.ENV.locs`): accounts, assistant, assistant_tools, attend2, biz, books85, books96, dash, dashx, dashx_metrics, daybook, delegation, dues, employees, entry, filters, finance2, flow, forms_*, invoice, invoiceview, itemmaster, items2, locations, nav, ownerboard, parallel, payroll, pos, posfail, printbooks, purchase, purchaseprint, recipes, reports, rollout, rules, salary, salesx, scan, settings2, stock2, stockx, tplpicker | One flat location list for the whole company | `ENV.locs` filtered by `B.biz`; helper `B.bizLocs()`; lint rule forbidding raw `B.ENV.locs` outside entry.js | L | grep test: no raw `B.ENV.locs` outside allow-list; two-business smoke |
| G2 | `web/entry.js:95` | `ENV.items` = every item (paged via `BOS_ALL`) | `items` carry `org_unit_id`/scope; load by business; cache key per business | L | item count differs per business |
| G3 | `web/entry.js:94` | `staff_directory` global | scoped RPC | M | - |
| G4 | `web/entry.js:105-114` | `rules`, `option_lists`, `grant_defs` global; `B.rule(key, fallback)` | rules keyed `(org_unit_id,key)`, `B.rule` reads current business | L | rule A != rule B test |
| G5 | `web/coldstart.js:87-108` + `app.js:159,190` | Offline snapshot of `ctx`, `locs`, `rules`, items, per user | key by `uid + biz id`; clear on switch | M | offline switch test |
| G6 | `web/nav.js` `bos_curloc_<uid>`, `pos.js:125,561` `bos_pos_loc`, `bos_pos_conv`, `bos_pos_queue_*`, `bos_pos_failed_*`, `bos_eq_*`, `bos_pins_*`, `bos_ownermode_*`, `bos_dashx_*` | Browser keys not tagged with business; offline sale queue could replay into the wrong business after a switch | Add business id to key prefix; refuse flush if `location_id` not in current business | M | queue test |
| G7 | `web/filters.js:73` `accessLocs`, `OPT` cache `:72` (`brands`, `cats`, `custs`) | Session caches of brands, item categories, customers (limit 1000, `filters.js:80`) | per-business cache + reset on switch | M | - |
| G8 | `web/assistant.js:188` `LOCIDX` cache keyed only by count `ls.length` | Stale on business switch with equal count | key by business id | S | unit |
| G9 | `web/sw.js:4` `VERSION='bos-sw-v1'` single cache, precache of same bundle | Same bundle for every business is fine (bundle has no data) - noted only | none | - | - |

(G9 not counted.)

### H. Menus / routes with no business switcher

Screens that need a business switcher (or need to inherit the global one) once more than one business is in the DB:

| # | Screen / route | file | Why |
|---|---|---|---|
| H1 | Home (tiles, "sheets today", stats "per location", low stock) | `nav.js:204,661,700-712` | Totals over `locChoices()`; "all places" = every business |
| H2 | Owner dashboard `dashx`, owner board `ownerboard` | `dashx.js:274`, `ownerboard.js:65,88` | `locsNow()` returns all locations when `S.ctx.is_owner` or `!mine.length` |
| H3 | Reports hub + report runner + brand P&L + business analysis `biz` | `reports.js:587`, `biz.js:53-58`, `ia.js:105-107` | `report_run` takes filters, no org filter [server side unverified] |
| H4 | Paper form catalogue (all `B.forms[...]`) and role x form matrix, form rollout | `entry.js` forms list, `rollout.js:78`, `app.js:~460 viewMatrix`, `printbooks.js:21` | One shared form catalogue with sweets wording; needs `forms.org_unit_id` / template (bakery set vs hardware set) |
| H5 | Staff + roles + user_locations screen | `app.js:428-455` | Lists all profiles and every location in one toggle list; `management` role sees everything |
| H6 | `management` role bypass in JS (`includes('management')`: attend2, biz, dash, daybook x2, dues x2, entry, filters, flow, forms_stock x2, ia, nav x3, optviews, pos, printbooks, reports, salary x2, salesx, scan, stock2 x2 = about 27 sites) | list in section 0 | "management" = all locations of all businesses; needs `management@org_unit` scope (server `can_loc` is the real gate; JS only mirrors it) |

Also needing a switcher: Accounts / day book / chart (`accounts.js`, `daybook.js`, `books85.js`, `books96.js`, `finance2.js`; single CoA, blueprint 2.5), Items/categories/bulk import (`itemmaster.js`, `bulkitems.js`, `catpick.js`, `items2.js`), Customers/suppliers (`customers.js`, `partners.js`), Costing family (`costing.js`, `costsources.js`, `costattrib.js`, `cost116.js`, `recipes.js`, `recipebook.js`), Settings/rules/option lists (`settings2.js`, `rules.js`, `switchboard.js`), Assistant (`assistant*.js`: answers company-wide questions, `redact` scope unverified), Notifications/inbox (`notifications.js`, `inbox.js:216`).

Proposed switcher: extend the drawer box at `nav.js:249-262` to two levels - Business (from `ctx.businesses`) then Location - and a `bos:biz` event next to `bos:loc`. Group-level roll-ups (all businesses) only for users with a group grant and on dedicated screens, never as the default "all". Risk M for the switcher, L for retrofitting 40+ screens. Test: for each route in `ia.js`, mount with business A then B and assert no id of the other business appears in rendered HTML (jsdom sweep).

### I. Bangla/English labels naming sweets brands or products

| # | file:line | Text | Replacement | Risk | Test |
|---|---|---|---|---|---|
| I1 | `web/app.js:23-29` `CAT` (sweet_kg, sweet_pc, doi, cake_lb, cake_pc), `UNIT` | Item category labels for POS/lists | `categories` table already exists (`filters.js:81` reads distinct `items.category`); drop legacy map, use `category_bn/en` | S | unit |
| I2 | Duplicate copies of the same legacy map: `pos.js:20-21`, `filters.js:45-46`, `items2.js:57-58`, `catpick.js:78`, `bulkitems.js:86` | 6 copies | single DB-driven source | S | unit |
| I3 | `web/forms.js:198` `CATS` (sweet, cake, jalebi, doi, bakery, ice, drink...), `forms.js:278` return rows, `forms.js:70-136` challan and sheet text | Product families in forms | `option_lists('product_families')` | S | opts |
| I4 | `web/forms_factory.js:120,170` `FAMILIES` (chhana, fried, doi, khoa...) | Sweets production families | same | S | opts |
| I5 | `web/recipebook.js:47` `WORK` (mishti, doi, jilapi, cake, bakery) | Artisan work types | same | S | - |
| I6 | `web/entry.js:81` `SD('shelf_sweet'..)`, `shelf_cake` | Setting definitions named sweets/cake | generic `shelf_<category>` rows | S | settings test |
| I7 | `web/settings2.js:59` `sh_all`: "All sweets" | Label | "All items" | S | - |
| I8 | `web/assistant_tools.js:25` synonyms `sweet, sweets, মিষ্টি` for "item" | Concept words | add per-business vocabulary [unverified use] | S | - |
| I9 | `web/forms_cash.js:197,220,214` jalebi/frying/dough/oil/syrup measuring notes (form 15-x), `forms_staff.js` yeast, `forms_factory.js:74` flour | Whole forms are bakery-specific | gate by business template (see H4) | M | rollout test |
| I10 | `web/itemmaster.js:80` `TYPE_FALLBACK` (finished_good, resale, raw_material...) | Item types: manufacturing assumption; DB first, fallback only | keep DB; fallback neutral | S | - |
| I11 | `web/pay.js:23` `WALLET_FALLBACK` (bKash, Nagad, Rocket, Upay) | Bangladesh wallets, not sweets-specific; DB-first via `option_lists` | note only | - | - |

(I11 not counted; I9 spans many forms and is the real M.)

### J. Report screens showing company-wide totals

| # | file:line | Screen | Risk | Fix |
|---|---|---|---|---|
| J1 | `web/nav.js:700-712` | Home stats `HS.mode==='biz'`: sales, discount, due, per-location rows and a "Total" row over `locs` | M | restrict `locs` to `B.biz` |
| J2 | `web/dash.js:64-68,115,126` | Owner/manager dash: `locs` from `B.ENV.locs`, `missingLoc = SETTING_DEFS.length * ENV.locs.length - ...` | M | per business |
| J3 | `web/dashx.js:274`, `dashx_metrics.js:30` | KPI tiles for all `locsNow()` | M | per business + a labelled group view |
| J4 | `web/ownerboard.js:65-88,160` | Widgets, `report_run` called with filters, day-close over all showrooms | M | add `org` filter param |
| J5 | `web/reports.js:587` + `report_run` rpc `:232` | Reports hub: `locs` filter list; `p_filters` has no org [server unverified] | L | server-side org filter mandatory; client sends `org` |
| J6 | `web/biz.js:53-62` | Business analysis page (`all = B.ENV.locs`) | M | per business |
| J7 | `web/accounts.js:167`, `finance2.js:172`, `books85.js:148`, `books96.js:126` | Accounting screens over one ledger (also `acct_transfer_mode` "company_wide" `books85.js:83,99`) | L | `legal_entity_id` filter (blueprint 3.3) |
| J8 | `web/dues.js:36,60`, `salary.js:43`, `payroll.js:81`, `daybook.js:82`, `stock2.js:133`, `stockx.js:165` | Dues, payroll, day book, stock for all permitted locations | M | per business |
| J9 | `web/assistant.js:309,550`, `assistant_tools.js:302,356` | AI assistant answers over all locations | L [unverified redaction] | scope tool calls to current business |

### K. tools/*.py|js

| # | file:line | What | Replacement | Risk | Test |
|---|---|---|---|---|---|
| K1 | `tools/notify_digest.py:135,142` | Mail subject prefix `[Islamia BOS]` | prefix from `notify_config` per business | S | `tools/test_ops.py` |
| K2 | `tools/notify_digest.py:72-73,97,199-222` | Digest RPCs `daily_digest`, `urgent_alerts`, `notify_config` are global; one `MAIL_TO` env (`:245`) for the whole company | loop per `org_unit`, recipients from DB | M | test_ops: two businesses, two mails, no cross-leak |
| K3 | `tools/notify_sms.py:2,55-64` | Outbox claim global, header text "Islamia BOS" | outbox rows carry `org_unit_id`; sender per business | M | test_ops |
| K4 | `tools/backup_dump.py:55,74-118` | Whole-DB dump into one bundle; `backup_log` single | OK for group owner; add per-org export option for selling or handing over a business | M | restore drill per org |
| K5 | `tools/fingerprint_bridge.py:2,248` | "Islamia BOS" in description; device -> `attendance_punch_push` (device-to-location mapping server side [unverified]) | config per device maps to `org_unit` | S | `test_fingerprint_bridge.py` |
| K6 | `tools/kit_match.py:75` | `BOILER` set contains shop name and address (Khulna, Khalishpur) to strip from paper-kit text | config file per business | S | `test_ops.py` [unverified] |
| K7 | `tools/map_seed_items.py:32,43`, `tools/gen_dryrun_doc.py:60` | Seed-item mapping rules for `Misty`, `Doi`, `Cake` categories and cat numbers 13/14/15 | one-off migration scripts; mark as sweets-only, do not reuse | S | none |
| K8 | `tools/build_kb.py:2`, `glossary.py:2-13` | KB generator and language glossary say "Islamia BOS", `Showroom` term | glossary per business template | S | `check_doc_links.py` |
| K9 | `web/data/kb.json`, `item_dictionary.json`, `seed_item_mapping.json` (data, not code) | Assistant knowledge base and item dictionary are sweets content | per-business KB build; assistant loads by business | M [unverified] | assistant KB test |

(K8-K9 are counted inside the 7 only where they require change; K7 is archival.)

## 3. Top blockers (order to fix)

1. G1/G2/G4 - the single global `B.ENV` (`web/entry.js:92-114`): flat locations, all items, global rules/lists. Everything else hangs on it.
2. H5/H6 - `management` and owner scope by JS list `S.ctx.locations` with no business dimension (about 27 `includes('management')` sites); a cross-business leak unless `my_context` returns business-scoped locations and the server `can_loc` is org-aware.
3. J1-J5 - company-wide dashboards and `report_run` with no org filter; the "all places" default of the drawer switcher (`nav.js:236-262`) would merge businesses.
4. H4/I9 - the paper form catalogue (42 specs) is a bakery's: showroom sheet, jalebi, yeast, chhana. It needs per-business form sets.
5. F-group - five copies of the brand constant plus hardcoded receipt line `pos.js:457` and `<title>`/`manifest.json`; invoices from a hardware shop would print the sweets name.

## 4. Suggested fix order (no code in this task)

1. Add `B.biz` + `my_businesses()` and business-scoped `ENV` (G1-G5, section 1). One PR, behind a rule `multi_business_on` default OFF so the sweets business behaves exactly as today with a single implicit business.
2. Replace brand constants with `B.brand()` (A1, A2, F1-F9) - small, safe, testable.
3. Remove fallbacks and sweets defaults (B1-B4, E1) - after step 1, since the helper is needed.
4. Business switcher in drawer + keyed storage (H1, G6).
5. Scope dashboards and reports (J1-J9) with server work from B1.
6. Form catalogue per template (H4, I9) and tools loops (K2, K3).

## 5. Not covered / [unverified]

- SQL side: whether `report_run`, `daily_digest`, `staff_directory`, `my_context` already accept an org argument. Not read.
- Whether `locations.code` is unique globally (C6).
- Old `entries.data` JSON that stores codes `s1..s4`, `imh/mb/ak`, `islamia/bari/alcakes` (A3, A4, C3): rendering of historical entries after the list is removed needs a data check.
- `web/data/*.json` content (K9) was only listed, not read.
- Counts per category in section 0 are row counts of this document, not exact line counts.
