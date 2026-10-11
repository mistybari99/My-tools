# AUDIT (Command 0, Step 3) of the existing app

Scope: repo `My-tools`, branch `ccr-78d03e25-k7ksyo` (not `functions-v1`; nothing was committed). Read-only audit of `web/*.js`, `supabase/*.sql` (schema.sql, phase2..phase10, ALL_NEW*.sql), `docs/*`. Written against the spec "Build commands: functions only" (Command 0 Step 3, parts A-I).
No key, password or PIN is printed. The Supabase publishable key in `web/config.js` is public by design; the secret key is "not present" in the repo.

Big picture: the app is much further along than the spec assumes. The spec's open question 1 says "only 14-1 is built; 14-2, 08-1, 01-1, 01-2, 0-1 show as Soon". In this repo 41 of the 42 forms are already spec-driven screens (all except 0-1, which is the Location settings screen), and phases 5-10 add POS, rules and grants, reports, stock and purchase on top. Whether phases 5-10 SQL has been run on the live database is not visible from the repo (ROADMAP.md says "to be run once by owner"); see part I.

Source file map used below: `web/app.js` (login, shell, staff, backup, logs), `web/entry.js` (form engine, location settings), `web/forms*.js` (form specs), `web/nav.js` (Home v2 and drawer), `web/rules.js` (Rules and options hub), `web/lists.js` (Edit lists), `web/items2.js` (Items v2).

---

## A. Stack

| Item | Finding | Evidence |
|---|---|---|
| Language / framework | Plain JavaScript, no framework, no bundler. Each file is an IIFE that attaches to `window.BOS_APP`, `window.BOS`, `window.BOS_PAGES`. Hash router (`#/home`, `#/form/14-1`, `#/entry/<id>`). Text in 3 modes (bn, mix = Bng-Eng, en). | `web/index.html` (27 script tags), `web/app.js:158-175` |
| Build tool | None. `web/` is served as static files. `tools/glossary.py` only helps with wording. | repo tree |
| Hosting | GitHub Pages (static). DECISIONS.md says `web/` goes to a separate PUBLIC repo; this private repo keeps SQL, data and docs. Prices and costs never go in the public repo. | `docs/DECISIONS.md:6,35`, `docs/SETUP.md` |
| Backend / data store | Supabase (free plan, Singapore). Postgres with RLS, `security definer` RPC functions, Supabase Auth, Storage bucket `photos` (receipts, item images). | `supabase/schema.sql`, `web/entry.js:113` (`sb.storage.from('photos')`) |
| Login | Staff ID + PIN. Staff ID becomes a fake e-mail `<id>@staff.islamia-bos.app`; the Supabase Auth password is `<PIN>-bos` (4-6 digits, so it meets the 6-character minimum). `signInWithPassword` is called from the browser. | `web/app.js:92-94,120-127`, `web/config.js` |
| Where the PIN is checked | Inside Supabase Auth (GoTrue), which keeps a bcrypt hash. Our tables never hold the PIN. First registered user becomes owner; everyone else is `pending` until the owner approves (`handle_new_user` trigger). | `schema.sql:164-185` |
| Wrong-PIN lock | `login_precheck(staff)` (read) and `login_failed(staff)` (write) are RPCs the CLIENT calls around the Auth call. Count in `login_failures`; after `settings.max_fails` (default 5) the account stays locked until the owner presses unlock (`unlock_staff`). There is no 10-minute auto-unlock and no log line per failed attempt. `login_failed` is callable by `anon`, so anyone can lock any staff ID; and an attacker who calls Auth directly never triggers the counter. SETUP.md and MODULE_MAP.md both say this is "not a hard server-side block". | `schema.sql:320-347,420-445`, `docs/SETUP.md:21-22`, `docs/MODULE_MAP.md` (Still open) |
| PIN change / reset | No screen found for changing or resetting a PIN (only `unlock_staff`). | grep `updateUser` returns nothing |
| Where permissions are enforced | Server first: RLS on every table (`is_active()`, `is_owner()`, `can_do(form, 'view/enter/approve')`, `can_loc(location)`), writes through `security definer` RPCs (`save_entry`, `submit_entry`, `decide_entry`, `submit_item_change`, `decide_release`, `record_sale2`, ...). Anonymous and authenticated roles start with `revoke all` and get only listed grants. The client also hides tiles (`OWNER_ONLY` set, `S.ctx.perms`), but a hidden route is backed by RLS. Weak spot: the CONTENT of an entry is client-computed (flags, totals, limit checks, required fields). `save_entry` stores whatever `p_data` and `p_flags` the browser sends, and `submit_entry` blocks only on red flags the browser itself sent. | `schema.sql:407-486`, `phase2.sql:105-163`, `web/app.js:158`, `web/entry.js:343-380` |
| Offline | No service worker, no app-shell cache. Only the POS has an offline queue: a sale that cannot be sent is kept in `localStorage` (`bos_pos_queue_<uid>`) and re-sent with an idempotency key `p_client`; refused ones are kept visible. Forms: an unsaved NEW entry is kept as a local draft (`bos_tmp_<form>_<loc>`) and restored; there is no automatic retry and no "Not sent yet" state for form saves. Reports say "you are offline". | `web/pos.js:3,66-81,255-340`, `web/entry.js:332,375` |

---

## B. Data (exact tables and fields)

### B1. Staff, roles, permissions
| Thing | Table.fields | How it is stored |
|---|---|---|
| Staff | `profiles(id uuid = auth.users.id, staff_id text unique, full_name, status pending/active/disabled, lang bn/mix/en, created_at)`. `user_roles(user_id, role_code)`. `user_locations(user_id, location_id)`. | Retire = `status='disabled'` (no delete grant on profiles). `guard_last_owner` triggers keep at least one active owner. Roles can be removed from a person (`user_roles` has a delete grant, logged by `audit_user_roles`). |
| Roles | `roles(code pk, name_bn, name_mix, name_en, sort, allow_self_approve, active)`. 11 seeded: owner, management, cash_controller, showroom_manager, salesperson, storekeeper, factory_incharge, purchasing, party_coordinator, carrier, hr. | `schema.sql:17,545-557` |
| Role x form permissions | `role_form_perms(role_code, form_code, can_view, can_enter, can_approve)`; `forms(code pk, area, name_bn/mix/en, version, sort, count_first, red_block, enabled)`. Owner sees everything (`my_context` builds perms). Edited in the Role x form screen (`#/matrix`). Keys exist only for view/enter/approve: no request_change, print, list.add, location.* keys. | `schema.sql:45-64,375-405` |
| Other grants | `rules(key, module, kind, value, default_value, unit, choices, min/max...)` (owner-editable switches and numbers); `grant_defs(grant_code...)`, `rule_grants(grant_code, role_code, allowed)` (who may do a controlled action, e.g. `discount_over_limit`, `price_override`, `sale_void`, `supplier_manage`), `user_grants(user_id, grant_code, location_id, valid_until)` (per person), `emergency_requests(...)` (staff blocked by a rule asks, owner approves once or for a short window). | `phase7.sql:12-30,89-165`, `phase8.sql:49-62` |

### B2. Items, prices, costs, change requests
| Thing | Table.fields | How it is stored |
|---|---|---|
| Items | `items(id uuid, code unique default 'I-001'.., name_bn, name_en, name_mix, category text, category_bn text, unit text, sell_price, is_active, created_at, updated_at, updated_by)` plus phase8: `sub_category, base_unit, sell_units text[], wholesale_price, tracked, min_stock, barcode, source made/bought, vat_applicable, images text[]`. | No delete grant; retire = `is_active=false`. Code is immutable (trigger `items_before`, `schema.sql:230-239`). Written only through `submit_item_change` / `decide_item_change`. |
| HOW CATEGORY AND UNIT ARE STORED TODAY | TWO SEPARATE FIELDS: `items.category` (text key) and `items.unit` (text key: `kg`, `pc`, `lb`). But the legacy category KEYS still carry the unit inside them: `sweet_kg` (মিষ্টি (কেজি)), `sweet_pc`, `cake_lb`, `cake_pc`, `doi`. The seed has 57 items (16 sweet_kg, 18 sweet_pc, 10 cake_lb, 4 cake_pc, 9 doi). `category_bn` stores the label next to the key. Items v2 added `item_categories` and `item_subcategories` option lists (owner can add a category from the item screen) and a `units` option list (kg, piece, box, pack, pound, gram) with an alias map because items keep the old codes `pc`/`lb`. The old combined-choice screen is only the fallback `app.js:266-267`; `items2.js` takes over `#/items` (`app.js:167-169`). | `schema.sql:66-78,566-640`, `phase8.sql:13-24,207-216`, `web/items2.js:46-47,77-98,215-221,259-292` |
| Prices | `items.sell_price`, `wholesale_price`; history `item_price_history(item_id, sell_price, cost_price, changed_at, changed_by)` written by triggers. | `schema.sql:98,246-274` |
| Costs | `item_costs(item_id pk, cost_price)`, readable only with `can_do('ITEM_COST','view')` (RLS). | `schema.sql:80,473-476` |
| Item change requests | `item_changes(id, item_id null=new, patch jsonb, note, status pending/approved/rejected, requested_by/_staff/_at, decided_by/_staff/_at, decision_note)`. Owner's own change applies at once; others wait; the requester cannot approve own unless owner or role `allow_self_approve`. | `schema.sql:88-96,330-376` |
| Units | `unit_conversions`, `shelf_life_rules` (phase8), `option_lists` list `units`. | `phase8.sql:262,329` |

### B3. Release requests, exceptions, limits
| Thing | Table.fields |
|---|---|
| Red-control release requests | `release_requests(id, entry_id, flag_code, flag_amount, reason, status pending/approved/rejected, requested_by/_staff/_at, decided_by/_staff/_at, decision_note)`; one pending per entry+flag; a release covers only the amount asked. `request_release` (maker, draft only), `decide_release` (owner only). `phase2.sql:51-59,172-198` |
| Exceptions | `exceptions(id, entry_id, form_code, location_id, entry_date, flag_code, level red/yellow, amount, text jsonb, status open/resolved, resolved_by/_staff/_at/_note)` (phase 3+ adds `sale_id`). Created from flags at submit and decide; `resolve_exception` needs a note. `phase2.sql:39-49,200-209` |
| Emergency requests | `emergency_requests` (phase7). |
| Limits per location ("Location settings") | `location_settings(location_id, key, value jsonb null = "data needed", updated_at, updated_by)`, PK (location_id, key). Keys defined in `B.SETTING_DEFS` (38 keys, groups A cash and limits, B time and place, C products and storage, F purchase and count): `drawer_float, imprest, expense_max, cash_tol, goods_money_tol_pct/_max, big_sale, avg_daily_sales, discount_limit, refund_limit, hub_cash_max, hub_min_cash, order_hold_days, unclaimed_days, open_time, close_time, busy_day_def, handover_point, crates, trays, fridge1..3_name/_min/_max, shelf_sweet/cake/doi/bakery, daytag_0..6, waste_classes, count_tol_pct/_max, quote_over` + phase8/9 extras. Owner-only write (RLS `locset_owner_write`); NOT versioned (an upsert overwrites; the old value survives only in `audit_log`). Marketing monthly limit by head lives elsewhere: `option_lists.extra.limit_month` (`web/lists.js:13`). |

### B4. Form entries (14-1 and the other 40)
All form entries, 14-1 included, go into ONE table: `entries(id uuid, form_code fk forms, location_id fk, serial int, entry_date, status draft/submitted/approved/rejected, data jsonb, flags jsonb [{code, level, amount, text}], check_data jsonb (the checker's section), created_by/_staff/_at, updated_at, submitted_at, checked_by/_staff/_at, check_note)`, unique (form_code, location_id, serial). Serial numbers come from `serials(form_code, location_id, last)`. The paper's own printed number is `data.paper_no`, with a unique index per form+location (`entries_paper_no_uq`, phase5) and a gap audit `number_audit()`. No direct insert, update or delete grant on `entries` (only `select`); every write is an RPC. Draft edits that overwrite a non-empty value need a note and are copied to `corrections(before, after)`. POS sales do NOT use `entries` (trigger `entries_no_pos`); they use `sales`, `sale_payments`, `customers` (phase3/6). Stock and purchase (phase10) use their own typed tables (`stock_batches, stock_ledger, stock_balance, stock_wastage, stock_transfers, purchase_bills, purchase_lines, supplier_payments`), not linked to the 04-x/06-x form entries.

### B5. Change log, backup
| Thing | Finding |
|---|---|
| Change log | `audit_log(id, at, user_id, staff_id, action, table_name, record_id, detail jsonb {old,new})`, written ONLY by trigger `log_change(keycols)` (security definer) on items, item_costs, item_changes, roles, forms, locations, settings, profiles, user_roles, user_locations, role_form_perms, location_settings, release_requests, exceptions, sales, rules, rule_grants, user_grants, option_lists, suppliers, etc. Plus `log_entry_status` (every entry status move). Authenticated users hold only `select`, and only the owner passes the RLS read policy. There is no UPDATE/DELETE grant and no update policy, but also no immutability trigger (the stock ledger has one, `phase10.sql:352-356`; audit_log does not). Viewer: `#/logs` shows the last 100, filter by 9 tables only. `schema.sql:114,135-210,483` |
| Correction log | `corrections(at, user_id, staff_id, form_code, entry_id, note not blank, before, after)`: insert-only for users, readable by the owner and the author. |
| Backup | Home -> Rules and options -> Backup: downloads one JSON (`bk_all`) and an items CSV. `BACKUP_TABLES` = profiles, roles, user_roles, locations, user_locations, forms, role_form_perms, items, item_price_history, settings, audit_log, corrections. THE BACKUP DOES NOT INCLUDE `entries`, `exceptions`, `release_requests`, `location_settings`, `item_costs`, `item_changes`, `option_lists`, `rules`, `sales`, `customers`, `suppliers`, stock or purchase tables. Free plan has no automatic backup (DECISIONS.md). `web/app.js:448-472` |

---

## C. Locations

Table: `locations(id serial pk, code text not null unique, name_bn, name_mix, name_en, sort, is_active)` (`schema.sql:31-37`). RLS: everybody active reads; owner inserts/updates (`for all` policy, but no delete grant). There is NO screen to add or edit locations (only SQL). `is_active` exists but nothing in the web filters on it (`entry.js:96` loads all rows). No `kind`, `model`, `status`, `hub`, `supplied_by` columns. The code is `unique` but NOT immutable (no trigger; the owner can UPDATE it through the API).

Seven places, codes exactly as seeded (`schema.sql:543-550`) and renamed by code in `phase5.sql:7-13`:

| sort (phase5) | code in DB | name_en after phase5 | name_bn after phase5 |
|---|---|---|---|
| 1 | `main` | ISLAMIYA MISTY GHAR — Main Showroom & Main (Sweet) Factory | ইসলামিয়া মিষ্টি ঘর — মেইন শোরুম ও মেইন (মিষ্টি) কারখানা |
| 2 | `branch2` | ISLAMIYA MISTY GHAR — 2nd Branch | ইসলামিয়া মিষ্টি ঘর — ২য় শাখা |
| 3 | `mishti_bari` | MISTY BARI | মিষ্টি বাড়ি |
| 4 | `al_cakes` | AL-CAKIZ (below the residence) | AL-CAKIZ (বাসার নিচে) |
| 5 | `cake_factory` | Cake Factory (below the residence) | কেক কারখানা (বাসার নিচে) |
| 6 | `mishti_factory` | Mujgunni Sweet Factory (closed, machines stored) | মুজগুন্নি মিষ্টি কারখানা (বন্ধ, যন্ত্র রাখা) |
| 7 | `godown` | Godown (lane beside ISLAMIYA MISTY GHAR) | গোডাউন (ইসলামিয়ার পাশের গলি) |

Points that matter for Commands 1 and 5:
- The codes are lower-case slugs, not numbers. They exist for all seven, so nothing needs inventing; but the spec's "Sweet factory" is NOT a separate row today: phase5 folds the main sweet factory into `main`'s name and re-uses code `mishti_factory` for the stopped Mujgunni factory. schema.sql originally named `mishti_factory` "Sweet Factory" (sort 5). The mapping spec-place to DB-code needs the owner (part I, question 2).
- Hub: no flag. The hub is implied by who fills the "checker" section of 10-1/14-1 and by settings keys `hub_cash_max`, `hub_min_cash`.

Where locations are chosen or hard-coded:
| Where | What |
|---|---|
| `web/entry.js:179` (field type `loc`) | select over all rows of `locations` + a fixed `other` option |
| `web/entry.js:453-457` `myLocs()` | owner and role `management` see all; others only `user_locations` |
| `web/entry.js:521` Location settings, `web/pos.js:112`, `biz.js:64`, `dues.js:63`, `stock2.js:157,203,285`, `purchase.js:117,287,319`, `invoice.js:226,254`, `settings2.js:339` | location pickers reading the table (good) |
| `web/forms_cash.js:33` `SHOWROOMS` (10-3) | HARD-CODED s1 Main, s2 2nd Branch, s3 MISTY BARI, s4 AL-CAKIZ, other |
| `web/forms_sales.js:297` `SHOWROOMS` (01-1) | HARD-CODED list of names |
| `web/forms_cash.js:297` brand options `imh, mb, ak, other, all` (18-1) and `web/forms_factory.js:256` `BRANDS` islamia, bari, alcakes, other (05-5) | HARD-CODED brands |
| `web/forms_staff.js:316-327` `SLOT_A..SLOT_I` (02-7) | HARD-CODED duty-slot names that contain place names (Main, 2nd Branch, MISTY BARI, Godown, Sweet factory...) |
| `web/forms.js:98,232`, `forms_cash.js:211` | transfer types, goods source (`factory/godown/branch`, `godown/factory`) as fixed arrays |
| `supabase/phase9.sql:52-56` | `report_brand_map` seeded by CODE: main and branch2 = islamiya, mishti_bari = misty_bari, al_cakes = al_cakiz; factories and godown deliberately unmapped |

---

## D. Lists (fixed arrays, native selects, radio-like choices)

Mechanism: field builders `SEL` (native `<select>`, `entry.js:177`) and `CH` (button group, one choice) take either a literal array or `B.opts('<list_code>', fallback)`, which reads `option_lists` rows that are active. The stored value is the value code (e.g. `staff_meal`), never the label; a retired code still shows on old records (`entry.js:162`).

### D1. Already driven by `option_lists` (owner edits in `#/lists`, `web/lists.js:10-17`, which only exposes 6 lists)
| list_code | Used by | Seed values (value_code) |
|---|---|---|
| `expense_heads` | 10-2 line `head` (`forms.js:30`) | staff_meal, transport, hospitality, repair, labour, sourcing, other |
| `marketing_heads` | 18-1 line `head` (`forms_cash.js:304`); `extra.limit_month` | 1..10 (ten heads of the paper; 10 = Other) |
| `wallets` | POS partial payment (`pay.js:27,60`) | bkash, nagad, rocket, upay |
| `units` | Items v2, stock, purchase (`settings2.js:192`, `stock2.js:156`, `purchase.js:146`) | kg, piece, box, pack, pound, gram |
| `item_categories`, `item_subcategories` | Items v2 (`items2.js:81-93,215-217`) | no seed; legacy keys fall back to `CATLEG` |
| `supplier_types`, `customer_types` | settings2 supplier form (`settings2.js:296`), `customers.type_code` | milk, sugar, packaging, fuel, gas, services, other / retail, wholesale, party, corporate, online, staff |
| `wastage_reasons`, `return_reasons` | stock actions (`stock2.js:328,400`), purchase return (`purchase.js:157`); also checked in SQL (`phase10.sql:552,999`) | expired, spoiled, burnt, broken, sample, staff_meal, unknown / damaged, wrong_item, quality, excess, other |
Not editable in the app: `supplier_types, customer_types, wastage_reasons, return_reasons` (no tab in `lists.js`). `option_lists` has owner `for all` RLS and a DELETE grant (`phase6.sql:423`); the screen never deletes.

### D2. Fixed option arrays inside form specs (NOT list-driven)
| File:line | Field | Values |
|---|---|---|
| forms.js:98 `TTYPES` (03-1 `ttype`) | transfer type | f2s, s2f, cust, s2s, g2l, p2l, other |
| forms.js:100/113 `GRADES` | grade | g1, g2 |
| forms.js:104 | shift | m, a, n |
| forms.js:124 | liability | factory, transport, ok |
| forms.js:127 | return reason (03-1) | g2, unsold, broken, expired (+) |
| forms.js:137 | payment | adv, cash, credit |
| forms.js:160 | count kind (04-3) | regular, surprise |
| forms.js:195 `CATS` (14-1 sales categories) | 8 columns | sweet, cake, jalebi, doi, bakery, ice, drink, other (paper has 9 incl. one unnamed slot) |
| forms.js:210-211 | day type, shift (14-1) | normal, busy / full, s1, s2 |
| forms.js:224 | expired shown | no, yes |
| forms.js:232 | goods source (14-1 B) | factory, godown, branch, supplier, outside |
| forms.js:286 | incident type | urgent, routine |
| forms_stock.js:24-33 | `PAYS` cash, credit, bank, mobile, owner, other; `SHIFTS`; paper po/pr/direct | |
| forms_stock.js:29 `QUALITY` (04-1) | accept, reduced, hold, return | |
| forms_stock.js:95 `PURPOSE` (04-2) | prod, staff, sample, trial | |
| forms_stock.js:139 `OTHER_PAPERS` (04-4) | return, count_adj, other | |
| forms_stock.js:189,199,216,262,331,344,352,387,398 | urgency; cmp within/outside; decision; single; `BILLPAYS` cash, bank, cheque, mobile, owner, other; mismatch qty/rate/both; debit reason short/return/quality; supplier kind; verify how | |
| forms_cash.js:33 `SHOWROOMS` (10-3) | s1, s2, s3, s4, other | HARD-CODED places |
| forms_cash.js:146 `ADV_STATUS` | pending, given, refunded | |
| forms_cash.js:197-211 (14-2) | unit kg/l; scale ok/bad; old oil sold/destroyed; source godown/factory | |
| forms_cash.js:289-297 | 18-1 `MKT_SRC` imprest, bank, card, mobile, owner (no sales drawer: matches spec); brand imh, mb, ak, other, all; `MONTHS` | |
| forms_cash.js:349,393-395 | rate basis list/special; money path merchant/cod/foodapp; delivery shop/own/courier/foodapp; outcome | |
| forms_factory.js:113-183 | `HD` hour/day; cat sweet/cake/bakery/other; storage fridge/chiller/normal/other; `FAMILIES` chana, fried, doi, khoa, cake, other; `RUNITS` kg, l, pc, lb, g; base unit; shift | |
| forms_factory.js:256-291 | `BRANDS` islamia, bari, alcakes, other; decision keep/change/drop | |
| forms_sales.js:23-26 | `CHANNELS` counter, phone, message, party, other; `ONLINE` fb, ig, tt, wa, foodapp, other; `DELIV` pickup, own, courier, foodapp, other; `PAYMODES` cash, bkash, nagad, card, other | |
| forms_sales.js:32-111,138,163-221,252-274,297-385 | order type; delivery mode; adv fate; goods fate; discount reason (old, bulk, cond, offer, other); `COMPLAINTS` taste, smell, broken, short, wrong, late, staff; invoice doc quote/invoice; pay cash/credit/part; cash mode cash/bkash/bank/other; maintenance `PROBLEMS` p_stop, p_cool, p_noise, p_leak, p_power, p_other; cost type; pay imprest/hub/bank/mobile/owner/other; KPI scope/dir | |
| forms_staff.js:16-18 | `MONTHS` 1-12; `PAYM` bank, mobile, cash, owner, other | |
| forms_staff.js:190-279 | lodging/keys; leave type swap, annual, unpaid, sick, emergency; decision yes/no/part; exit how resign/terminate/contract/other | |
| forms_staff.js:316-336 | `SLOT_A..I` duty slot names, skill full/part | |
| forms_staff.js:508-513 | display match/short; place shop/factory (11-1) | |
| `B.YN` entry.js:51 | yes / no, used in dozens of fields | |
| `entry.js:177-179` | `staff` select = all active profiles; `loc` select = all locations + fixed `other` | |

### D3. Fixed arrays / selects outside forms
| File:line | Field | Values |
|---|---|---|
| app.js:29, 266-267 | legacy item `UNIT` (kg, pc, lb); legacy category select (derived from existing items) | |
| items2.js:46-47 | `LEG` units kg, pc, lb + `ALIAS` pc->piece, lb->pound | |
| pay.js:14 | POS `MODES` | cash, mobile, card |
| invoice.js:17,227 | `KINDS` thermal80, thermal58, common, a4, label; printer type thermal, a4, label, other | |
| rules.js:64 | rule `choice` selects, choices from `rules.choices` (block / warn / off ...) | |
| settings2.js:145,175,258-260 | fiscal month; costing method (avg only); shelf-life scope all/cat/item | |
| reports.js:197-199, stock2.js, purchase.js:116 | group/sort dimensions, purchase status draft/posted/void | |
| SQL | `check (status in (...))` constraints on entries, item_changes, release_requests, exceptions, profiles.status, sales (pay_mode, sale_type) | |

---

## E. Forms (42 codes of the spec)

How "Built / Soon / Absent" is decided by the app: `live = B.forms[code]` exists in JS (`app.js:215`, `nav.js:101-103`); `0-1` is live for the owner only (it opens `#/locset`). Chips shown on Home and in the drawer: `Soon` (no spec), `Can enter` or `Can view`, `Can approve`, from `role_form_perms` (owner has all). Entry chips: status draft / submitted / approved / rejected, red (dot) and yellow (triangle) flag counts. There is no Paper / Parallel / App chip anywhere. Storage for every Built form: `entries` (`form_code`, `data jsonb`, `check_data jsonb`, `flags jsonb`), serial from `serials`, paper number in `data.paper_no`. Exceptions: noted per row. Rows exist in `forms` for all 42 codes (`schema.sql:520-562`).

| Code | Status | Spec file:line | Storage / notes |
|---|---|---|---|
| 0-1 | Built as a screen, not as an entry form | `web/entry.js:518-545` (viewLocSet), route `#/locset` | `location_settings` (owner-only, unversioned); row in `forms` area `settings`; no `B.forms['0-1']` |
| 01-1 | Built | forms_sales.js:298 | entries; area owner; hard-coded SHOWROOMS |
| 01-2 | Built | forms_sales.js:355 | entries |
| 02-1 | Built | forms_staff.js:25 | entries |
| 02-2 | Built | forms_staff.js:81 | entries |
| 02-3 | Built | forms_staff.js:133 | entries |
| 02-4 | Built | forms_staff.js:171 | entries |
| 02-5 | Built | forms_staff.js:220 | entries |
| 02-6 | Built | forms_staff.js:267 | entries |
| 02-7 | Built | forms_staff.js:337 | entries; slot names hard-coded (SLOT_A..I) |
| 02-8 | Built | forms_staff.js:467 | entries |
| 03-1 | Built | forms.js:101 | entries (the typed `stock_transfers` table of phase10 is separate) |
| 04-1 | Built | forms_stock.js:30 | entries (separate typed `purchase_bills` flow exists) |
| 04-2 | Built | forms_stock.js:96 | entries |
| 04-3 | Built | forms.js:156 | entries (count_first, tolerances `count_tol_pct/max`) |
| 04-4 | Built | forms_stock.js:140 | entries; one page per item, typed (not a view) |
| 05-1 | Built | forms_factory.js:36 | entries |
| 05-2 | Built | forms_factory.js:114 | entries |
| 05-3 | Built | forms_factory.js:171 | entries |
| 05-4 | Built | forms_factory.js:210 | entries |
| 05-5 | Built | forms_factory.js:259 | entries |
| 06-1 | Built | forms_stock.js:186 | entries |
| 06-2 | Built | forms_stock.js:246 | entries (quotation limit `quote_over`) |
| 06-3 | Built | forms_stock.js:288 | entries; no `getPurchaseBudget` check |
| 06-4 | Built | forms_stock.js:332 | entries |
| 06-5 | Built | forms_stock.js:384 | entries; one page per supplier; supplier picker `SUP` (free text still allowed) |
| 08-1 | Built | forms_sales.js:253 | entries with photos in Storage |
| 10-1 | Built | forms.js:65 | entries; hub section is the `who:'checker'` part (`check_data`) |
| 10-2 | Built | forms.js:25 | entries; heads from `option_lists.expense_heads`; imprest equation in the form |
| 10-3 | Built | forms_cash.js:45 | entries |
| 10-4 | Built | forms_cash.js:95 | entries; budget computed client-side |
| 10-5 | Built | forms_cash.js:147 | entries |
| 11-1 | Built | forms_staff.js:498 | entries |
| 14-1 | Built (Entry + Approve; collapsed sections, 16-step checklist `CLOSE_STEPS`) | forms.js:208 | entries; expected drawer balance, short/over, hub deposit computed in the browser |
| 14-2 | Built | forms_cash.js:187 | entries |
| 18-1 | Built | forms_cash.js:294 | entries; heads from `option_lists.marketing_heads` |
| 20-1 | Built | forms_sales.js:29 | entries |
| 20-2 | Built | forms_sales.js:101 | entries |
| 20-3 | Built | forms_sales.js:139 | entries |
| 20-4 | Built | forms_sales.js:197 | entries |
| 20-5 | Built | forms_cash.js:346 | entries |
| 20-6 | Built | forms_cash.js:386 | entries |

Totals: 41 Built as spec-driven entry forms, 1 Built as a settings screen (0-1), 0 Soon, 0 Absent. Not verified from the repo: whether each form's `role_form_perms` rows are seeded for the real roles, and whether the live database has phases 5-10 (the spec's premise "only 14-1 built" may reflect what the owner has switched on, not the code). No quick-action / "event" linking between forms exists: cross-form numbers (sheet_no, handover slip no., challan no.) are typed text.

---

## F. Owner tiles on Home

Home v2 (`web/nav.js:429-460`, `drawMods` order list at line 456; legacy fallback `web/app.js:197-204`). For the owner, the module grid, in order:

| Tile (en label) | Route | Screen opened |
|---|---|---|
| Sales (POS) | `#/pos` | `web/pos.js` |
| Dues and customers | `#/dues` | `web/dues.js` |
| Reports | `#/reports` | `web/reports.js` (report engine, phase9) |
| Business analysis | `#/biz` | `web/biz.js` |
| Items and prices | `#/items` | `web/items2.js` (falls back to `app.js` viewItems) |
| Item change requests | `#/itemreq` | `app.js` viewItemReq (badge = pending count) |
| Exceptions | `#/exceptions` | `entry.js` viewExceptions (badge = open) |
| Number gap audit | `#/numaudit` | `number_audit()` screen |
| Emergency requests | `#/emergency` | `rules.js` viewEmergency (badge) |
| Red-control release requests | `#/releases` | `entry.js` viewReleases (badge) |
| Staff and approval | `#/staff` | `app.js` viewStaff (badge = pending staff; roles, locations, unlock) |
| Rules and options | `#/rulehub` | `rules.js` hub with tabs Rules / Who may do what / More |

"More" tab (`rules.js:79-82`) is the closest thing to a Control Center: Edit lists `#/lists`, Location limits `#/locset` (form 0-1), Form rules `#/rules` (count_first, red_block, enabled per form), Role x form permissions `#/matrix`, Staff, General settings `#/settings`, Number audit, Business analysis, Change log `#/logs`, Backup `#/backup`. Other owner routes in the drawer: Settings v2 `#/settings2` (units and conversions, shelf-life, suppliers, access, favourites, fiscal year), Invoice and print `#/invoice`, Stock `#/stock`, Purchase `#/purchase`, Payables `#/payables`.
The Home also has two mode tab sets (Business: POS, Items, Item requests, 14-1, 03-1, 04-1, Reports, Stock; Accounts: 10-1, 10-2, 10-4, Dues, P&L, Reports, Payables, and "Daybook" marked Soon), favourites (starred tiles, per user, synced to `user_favourites`) and a forms list with the chips from part E.

---

## G. Rule check of BUILD-RULES (16)

| # | Rule | Verdict | Evidence |
|---|---|---|---|
| 1 | Paper first, never remove | Met (by practice) | All 42 codes seeded (`schema.sql:520-562`); `MODULE_MAP.md` opening line "Nothing from the owner's list was removed"; DECISIONS.md "No invented numbers". No mechanism blocks removal, though. |
| 2 | Paper form codes, never renumbered; retired = closed | Partly | `forms.code` is PK referenced by FKs (a rename with entries present fails) but there is no immutability trigger and the owner holds `insert, update` on `forms` (`schema.sql:423`). Retired state is `forms.enabled=false` (`save_entry` raises "form is switched off"), not a status `closed`. `items.code` is immutable by trigger. `locations.code` is unique but editable. |
| 3 | Nothing is deleted | Partly | No delete grant on profiles, locations, items, entries, sales, exceptions, audit_log, forms. BUT: delete grants and UI/RPC deletes exist on `role_form_perms, user_roles, user_locations` (`schema.sql:422`, `app.js:503-506`), `option_lists` (grant `phase6.sql:423`; UI only deactivates, `lists.js:3`), `unit_conversions` (`phase8.sql:281,319`), `shelf_life_rules` (`settings2.js:394`), `invoice_templates`/`print_profiles` (`invoice.js:370,376`), `report_views` (`reports.js:457`), favourites (`nav.js:490`), `report_brand_map` (`phase9.sql:41`), `rule_grants/user_grants` (`phase7.sql:139`, `phase8.sql:81`), draft `purchase_lines` (`phase10.sql:1045`), and `submit_entry` deletes OPEN system-made exceptions on re-submit (`phase2.sql:156`). Draft table rows can be removed in the form (`delrow` handler in `entry.js`). Staff, items, places and options are retired, not deleted. |
| 4 | Every list has Add new and Other; no free text where a list exists; entry stores the id | Partly | Stores value codes, never labels (`forms.js:30`), and a retired code is still displayed (`entry.js:162`): good. Add new: only the owner, only in Edit lists (`lists.js`) or inline for item categories (`items2.js:267`); form pickers have no Add new. Other: present in many arrays as an `other` value with a write-in field, not on every list (`entry.js:179` loc has it; `TTYPES`, `QUALITY`, `BILLPAYS` partly). Free text where a list exists: supplier name is free text if the picker has no match (`entry.js:100`), 10-2 "paid to", carrier, party name (20-5), staff pickers store `staff_id` text. |
| 5 | Per-list add rule (open / approval / owner), enforced on the server | Not met as a per-list rule | One fixed regime: `option_lists` writes are owner-only by RLS (`phase6.sql:416-417`); item additions use the request path (`submit_item_change`); suppliers use grant `supplier_manage`. No `add_rule`, no pending list-add request, no Other queue. |
| 6 | Location, staff ID and time filled by the system | Partly | `created_by/_staff/_at`, `checked_*`, `submitted_at` come from `auth.uid()` and `now()` in the RPCs (`phase2.sql:105-163`). Location is picked (server checks `can_loc`). The business date `entry_date` is typed with no reason when it is not today; cross-form numbers and "carrier", "keys given to" are typed. |
| 7 | Change log is append-only, one line per change (who, when, what, from, to) | Partly | Log rows exist for most tables and every entry status move (`log_change`, `log_entry_status`); `detail` holds old and new. No UPDATE/DELETE grant and no update policy (`schema.sql:135-138,483`), so the API cannot edit it. No DB trigger forbids it for a privileged user (contrast `phase10.sql:352`), and an entry's `data` edits while draft are logged only as `corrections` when a non-empty value is overwritten. Viewer shows 100 rows, 9 tables. |
| 8 | Requester never approves own request; out-of-limit approvals are logged exceptions, not precedents | Partly | Server blocks maker = approver on entries and item changes (`phase2.sql:~75`, `schema.sql:361-363`) unless the person is the owner or has `roles.allow_self_approve`. Release requests and emergency requests are decided by the owner only, so an owner's own request is self-approved. Release covers only the flagged amount (`release_requests.flag_amount`); emergency window use leaves `emergency_window_used` exception (`phase7.sql:242`). |
| 9 | Blind count enforced; expected shown only after count saved; short/over always written | Not met | `count_first` is a flag on `forms` that only hides CALC fields on screen (`entry.js:148`, `forms.js:16-17,265-266,218`). The expected figure is computed in the browser from the maker's other inputs, so nothing is withheld by the server; in check mode the whole `entries.data` (including the sender's amount) is downloaded (`reloadEntry` in `entry.js` selects the whole row). The computed short/over is not stored (only `E.data` and flags are sent, `entry.js:366`); a zero shows "Matches" on screen; a reason is required only when non-zero. |
| 10 | Two signatures = two different logins, each with its own PIN | Not met | Signatures are staff-name pickers (`ST`, `entry.js:178`: witness `forms.js:268`, second signature `forms.js:288`). "Witness is maker" is a client-side red flag (`forms.js:325,331`). The server enforces only maker != checker on approve (`phase2.sql`), not a second PIN. The hub person is the checker in a second pass, not a second PIN entry. |
| 11 | Locked after approval; change is a request the owner approves, in the log | Partly | `save_entry` refuses any non-draft (`phase2.sql:123`). `reopen_entry` lets the OWNER send an approved entry back to draft with a mandatory note; the old data goes into `corrections`, status moves are in `audit_log`. A non-owner has no way to request a change. `period_closed_until` also locks by date (`phase6.sql:452-483`). No revision n+1 copy. |
| 12 | Offline is a state; Not sent yet; automatic retry; nothing lost | Partly | POS only (`pos.js` queue, idempotent `p_client`, refused sales kept visible). Forms: no queue, no retry, no "Not sent yet" (only a local draft for a not-yet-saved entry). No service worker, so the app shell itself needs a connection. Offline added options: n/a. |
| 13 | name_bn / name_en for every owner-entered name; dictionary keys in 3 modes; no hard-coded labels | Partly | Names store `name_bn, name_en` plus `name_mix` (items, locations, roles, forms, option_lists `label_bn/mix/en`). UI text: `web/i18n.js` dictionary keys with bn, mix, en (used by `t('key')`), but each form and screen carries its labels INLINE as `L(bn, en, mix?)` objects (thousands of them) and the Bng-Eng mode is auto-generated for missing mixes by a word-swap (`entry.js:12-38`). Some English-only hint strings in code (e.g. `forms_staff.js:344`). |
| 14 | Server-side permissions; never store PIN readable; 5 tries then 10-minute lock; log failed attempts | Partly | Server-side: Met for data access (RLS and RPC checks, part A). PIN: bcrypt in Supabase Auth, never in our tables or localStorage. Lock: 5 tries then owner unlock, client-driven, no 10-minute auto-release, no per-attempt log line, anon-callable lock RPC, direct Auth calls bypass it; no PIN change screen. Business rules (limits, required fields) are enforced on the client; the server trusts the flags it is given. |
| 15 | A blank number blocks the form that needs it; never invent a limit | Partly | `location_settings` null = "data needed"; a missing limit makes the tolerance red (`forms.js:19` `tol()` returns 'red' when no limit) and the screen lists the missing keys (`entry.js:240`), but the notice itself does not block Submit and the check is client-side. No numbers are invented (DECISIONS.md "No invented numbers, limits"). Settings are not versioned and there is no "blocks go-live". |
| 16 | After each task write docs/BUILD-LOG.md | Not met | No `docs/BUILD-LOG.md` and no `docs/BUILD-RULES.md`. The nearest habit is the dated checkpoints in `docs/ROADMAP.md` and `docs/DECISIONS.md`. |

Totals: Met 1 (rule 1), Partly 11, Not met 4 (rules 5, 9, 10, 16).

Specific hunts requested:
- Delete buttons / queries: listed under rule 3. None touches entries, sales, items, staff, locations, audit_log.
- Editable change log: no client path; no trigger guard either.
- Client-only permission checks: route gating (`OWNER_ONLY`, `app.js:158`) is client, but each is backed by RLS or RPC checks. Genuinely client-only are the BUSINESS rules inside forms (flags, limits, mandatory fields, witness != maker, blind figures).
- PIN storage: `password = PIN + "-bos"` handed to Supabase Auth (`app.js:93`); hash stays in Auth.
- Blind count: see rule 9.
- Two-signature: see rule 10.
- Lock after approval: see rule 11.
- Offline queue coverage: POS sales only.

---

## H. Three riskiest changes and the safest order

Riskiest:
1. **Server-side part-state gate (spec Command 7 and 8h, "every part starts at Paper").** If seeded as the spec says, every one of the 41 working forms would become read-only for staff who use them today. The state table must be seeded to App for the places and forms in real use, and enforced last.
2. **Moving form logic to the server (blind counts, PIN signatures, lock/revisions, getLimit, offline queue) and replacing the form engine with `form_defs/form_fields/form_values`.** Today `save_entry`, `submit_entry`, `decide_entry` are shared by all 41 forms and all flags and totals are computed in the JS specs. A parallel engine would double the code paths; a bug in the shared RPCs hits every form.
3. **Lists (`option_lists` -> `lists/list_options`) with a shared control in about 60 places, plus the Category/Unit migration (Command 3).** `value_code` strings are already stored in entries, in SQL checks (`phase10.sql:552,999`) and in reports (`sales_fact_t`); renaming tables or swapping to ids breaks old data and reports. The Category/Unit split is partly done already (separate columns; legacy keys `sweet_kg` etc. remain), so the dry run must start from the real database, not the 5-choice screen.
(Locations changes are lower risk if additive, but hard-coded showroom lists in forms and `report_brand_map` by code must keep working.)

Safest order:
1. Docs only: BUILD-RULES.md and BUILD-LOG.md; extend `BACKUP_TABLES` (today the backup omits entries, exceptions, location_settings, option_lists, rules, sales...). Take a backup first.
2. Hardening that adds no feature: trigger that blocks UPDATE/DELETE/TRUNCATE on `audit_log`; trigger making `locations.code` and `forms.code` immutable; revoke DELETE on `option_lists`; failed-login log line; server-side lockout in the same RPC path.
3. Locations: add nullable columns (`kind, model, status default 'live' for rows that already have entries, supplied_by, planned_opening, hub_functions, note`, who/when) and a read-only Locations screen; then the edit/add screen.
4. Lists additively on `option_lists`: add `status/retired_*`, a small `list_defs(list_code, add_rule, allow_other)`, `other_entries`; build the shared list control and convert one low-risk form at a time (10-2 head, 18-1 head), fixed arrays remain the fallback.
5. Control Center shell as links to the screens that already exist (the "More" tab), then Needs-you merge.
6. Location settings versioning: new `settings_sheets/values` filled from today's `location_settings`, plus `getLimit(location, key, date)`; old screen reads and writes through it.
7. Item Category/Unit/Sales column: dry run first, owner approves, then migrate.
8. Server-side blind counts and PIN signatures, new RPCs next to the old ones, 14-1 and 10-1 first; then change-request/revision for locked entries; then the offline queue for forms.
9. Rollout state (Paper/Parallel/App), seeded to App where staff already use the form; enforce last.

---

## I. Questions for the owner (max 10)

1. Has the SQL of phases 5-10 (ALL_NEW.sql, ALL_NEW2.sql, ALL_NEW3.sql) been run on the live database, and which forms are used daily at which places? (The spec assumes only 14-1; the code has 41.)
2. Seven places: keep the DB codes `main, branch2, mishti_bari, al_cakes, cake_factory, mishti_factory, godown`? Is the spec's "Sweet factory" the main factory inside `main` (phase5 names `main` "Main Showroom and Main (Sweet) Factory"), and is `mishti_factory` the stopped Mujgunni factory to seed as paused? Which places are live?
3. Which place carries the hub functions (Islamia Main = `main`)?
4. For forms that staff already use, should the starting state be App (not Paper), and does the owner want Paper / Parallel / App for the other forms only?
5. Second signatures: must the second person type their own staff ID and PIN on the same phone (spec rule 10), or is choosing a name plus manager approval enough? Wrong PIN: keep "owner unlocks" (today) or move to "5 tries then 10 minutes"?
6. Which counts must be blind on the server (14-1 drawer, 10-1 hub, 04-3 stock count, 04-1)? May the owner see the expected figure first?
7. Items: how many items and categories are in the live database (the spec says 1,305 items and 25 categories; the repo seed has 57 items and 5 legacy category keys)? Please supply the category sheet and say the standard unit of Doi.
8. Add rules per list: confirm the starting proposal, and say whether the item change-request path and the supplier grant stay as they are.
9. Settings sheet: today's 38 keys use semantic names, the paper uses numbered rows 1-31 with 7a-7f. Map ours to the paper rows, and who fills versus approves (today only the owner can write)? Marketing head limits sit in `option_lists.extra.limit_month`: move to row 22 for hub places only?
10. The owner currently self-approves (items, entries, releases). Under rule 8, should an owner's own request go to a second approver, or is the owner exempt?

---

## Spec vs ours (Commands 1-11)

| Cmd | Spec asks | Already exists (where) | Genuinely missing | Conflicts / notes |
|---|---|---|---|---|
| 1 Data foundations | locations with kind, model, status, hub; lists, list_options, other_entries; addOption/similar/approval functions; append-only change log; new permission keys; starting lists | `locations` with the 7 codes (`schema.sql:31,543`); `option_lists(list_code, value_code, label_bn/mix/en, sort, active, extra)` (`phase6.sql:412`); `audit_log` + `log_change` triggers; per-role view/enter/approve (`role_form_perms`), rules and grants (`rule_grants`, `user_grants`); owner-only RPC pattern | location columns and status decisions; list header with add_rule; retired_by/at/reason; other_entries; pending list-add requests; addOption normalising and similar-name logic; list.add:<key> and location.* keys; immutability triggers on audit_log, location code | Spec tables `lists`/`list_options` vs our `option_lists` (extend, do not create a second); spec stores option id, ours stores `value_code` text (already label-proof); spec names `name_bn/name_en`, ours `label_bn/label_mix/label_en` (three modes, rule 13); spec log columns vs `audit_log(detail jsonb)`; codes are slugs not numbers |
| 2 List control | one shared control: search, Add new, Other, request, offline queue | `B.opts` + `SEL` (`entry.js:177`), retired value still shown (`entry.js:162`), owner inline add of categories (`items2.js:267`), supplier quick add (`entry.js` sup_new), `loc` select with Other (`entry.js:179`), many `other` + write-in fields | the control itself; search at 8+ options; approval request; Other storage and queue; keyboard/accessibility; offline queue for adds; "+ Add" in Items/Suppliers/Parties/Staff headers | about 60 native selects to replace (part D); `CH` button groups and fixed arrays must be imported as options first |
| 3 Category / Unit / Sales column | split combined category; migrate five choices | Category and Unit already two fields (`items.category`, `items.unit`); Items v2 with `item_categories`, `item_subcategories`, `units` lists (`items2.js`); item changes via request path | `sales_column` list and `category_sales_column`; `category_id/unit_id/legacy_category`; dry run + migration with per-item log lines; 14-1 columns derived from items; 9th unnamed column (ours has 8) | Spec premise (five combined choices on New item) is only true for the legacy `app.js:266` screen and the legacy KEYS (`sweet_kg, sweet_pc, cake_lb, cake_pc, doi`); unit codes differ (`pc/lb` on items vs `piece/pound` in list); live counts (1,305 items, 25 categories) are not in the repo |
| 4 Control Center | `/control` shell, 12 tiles, access tiers, Needs you, Lists & options, Print & books | Owner tiles and the "More" tab (`rules.js:79`); route guard `OWNER_ONLY` (`app.js:158`); badge counts for items, exceptions, releases, emergency, staff; `serials`, `entries_paper_no_uq`, `number_audit()` (phase5) | head-management access tier; merged Needs-you list; Lists & options screen incl. Other queue and sales-column mapping; print notes; book/serial register; rollout board | Route gating is client + RLS rather than a server route check; Home already has an owner dashboard; tile names differ |
| 5 Locations | edit/add place, 17 setup steps, statuses, close checklist | Table and 7 rows only; `user_locations`; duty form 02-7 | all screens, status model, setup steps, pause/close, print notes, add-a-column everywhere | hard-coded showroom/brand/slot lists (part C); `is_active` unused; no place-driven rollout board; B and C models not decided |
| 6 Settings sheet 0-1 | 37 numbered rows, versions, approval, `getLimit(location,row,date)`, blank blocks | `location_settings` (38 keys, group A/B/C/F, null = data needed, `#/locset`); audit trigger; marketing limit in `option_lists.extra` | versioning and effective dates; approval workflow and photo; source and not_needed flags; applies-to per place kind; rows for factory/jalebi/online (rows 17-27); server-side limit check | Spec says old limits screen becomes row 22, ours is a generic per-location key table; paper numbering (7a-7f) vs semantic keys; writes are owner-only, spec wants head management to fill |
| 7 Register + Paper/Parallel/App | forms_register, parts, rollout_state, comparisons, board | `forms` table with all 42 codes + version + enabled + sort; "Soon" chip logic; Form rules screen | parts, printed papers, rollout_state, comparison pairs/days, month-end pass/fail, board, chips Paper/Parallel/App | Default Paper would lock live forms (part H risk 1); we have `enabled` not `closed`; `forms.version` is the kit version |
| 8 Form engine | `form_defs/form_fields/form_entries/form_values`, 5 field kinds, server rules | JS specs `B.forms[code]` with builders `T, TA, N, M, TM, D, CK, ST, ITEM, LOC, DEN, PHOTO, SUP, CH, SEL, CALC, NOTE, TABLE` + shared engine (`entry.js`); `entries(data jsonb, check_data jsonb, flags jsonb)`, `serials`, `corrections`, exceptions, release requests, photos in Storage, per-place read RLS (`can_loc`) | server-withheld expected figure; PIN signatures; EVENT links; stored AUTO results with formula version; `client_id` idempotent offline save; change requests and revisions; entered_later; serial books with software numbers; print with "Copy"; part-state check; getLimit | Different architecture: forms are code (spec-driven JS), data is jsonb in `entries`. Spec kinds map as AUTO ~ CALC, TICK ~ CK, COUNT ~ DEN + `count_first`; EVENT and PIN absent. Do not rebuild 41 forms: add server validators and a `count_blind` RPC to the existing engine |
| 9 Cash, bank, mobile | 10-1, 10-2, 10-3, 10-4, 18-1 on the engine | all five already Built (`forms.js:65,25`; `forms_cash.js:45,95,294`); imprest equation; hub section; marketing heads list; source list without sales drawer | server-blind hub count; distinct-login signatures; counterfoil auto-fill; `getPurchaseBudget` function; replenishment rule; approved-before-spend check on 18-1; serial book with blank first paper number (ours: free-typed `paper_no` + gap audit) | Spec says "add as data"; ours exist as code. Check paper-vs-app differences list for BUILD-LOG instead |
| 10 14-1 and 20-2 | build beside the live 14-1; quick actions; event fields | 14-1 (`forms.js:208`) and 20-2 (`forms_sales.js:101`) Built; sections incl. 16-step checklist, witness second count, hub receipt | nine quick actions and `quick_actions` table; E-fields that read 03-1, 10-1, 10-2, 20-x entries (today typed numbers); `source_pending`; server-blind expected balance; "previous layout" | There is no old and new 14-1: one layout exists. Cross-form numbers are typed text today |
| 11 Template for 34 forms | one form per paste, docs/forms/<code>.md, switch source_pending | 34 of the 34 remaining codes are already Built (part E) | `docs/forms/<code>.md` per form; server check per paper rule S1..Sn; reverse switch of typed fields to events; Turn 7 costing (none; ours has `costing_method` rule and cost reports) | The template assumes the form is absent; here the work is verification against the paper, not creation |
