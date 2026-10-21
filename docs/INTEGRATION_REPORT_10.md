# INTEGRATION REPORT 10 - Create the second business (and its places) from the app (phase 135)

Branch `local-loc` (worktree /home/user/work-loc), cut from `local-prof` tip 7d0e5ba (phases up to 134 + web). NOTHING is pushed, NOTHING is pasted on the live database, the public repo is untouched. The owner must say "push".

## 1. For the owner: how to create the second business, step by step (after Run 25 is pasted)

1. Open **Organization** (`#/organization`). Press **+ New business** (only you see it).
2. Step 1: write the business name (Bangla and English), a short code (capital letters / digits, for example `DLR`), choose the business type. A type marked **Not built yet** (dealership and others) has no screens of its own yet: tick the box to say you understand. Legal entity: keep "New legal entity (own books)" unless the business belongs to a company you already made.
3. Step 2: add the places (shops, branches, warehouses). A dealership starts with two rows; add or remove rows (1 to 10). Keep the tick "make one branch unit for each place" if you want a branch in the tree for each.
4. Press **Create now**. If something fails (for example a name is already used) the failed lines are shown in plain words; fix and press **Try again**: nothing is created twice.
5. Step 3 shows what was made and a checklist: set each place **live** (Locations screen), give each person a place (Staff), fill the business **profile** (name, address, receipt text), then turn on the separate data scope (Switchboard, `org_scope_on`) and review the template switches.
6. Later, on the business card: **+ Add place**, **Places** (list). In the list you (owner only) can **Move to another business**: press Check first; the screen shows stock, transactions, people and open documents. People assigned, open documents or a supply link across the border block the move; old transactions need your tick (their history moves too).

Be honest about two things: (a) there is still no screen to give a person a scope over a business, and none for the `org_scope_on` preflight (a person gets a business through the places given in Staff); (b) until `org_scope_on` is ON, the place names of both businesses can still appear in each other's lists (the walls are the switch). The new places appear in the pick-lists of THEIR business only when the app shows that business (the switcher), as bizctx already did for mapped places.

## 2. What was built

* `supabase/phase135.sql` (marker `loc135`, canonical row 62, paste twice safe, guard inside):
  * `business_place_create135(p_business, p_kind, p_code, p_name_bn, p_name_en, p_org_branch, p_client)`: owner, or the `org_manage` holder INSIDE that business (`_biz_mgr134`; a foreign or missing business answers `not allowed` alike). Calls the existing `location_save` (same defaults: model A, 17 setup steps, settings sheet version 1), the place is born mapped to the business (or a branch / site inside it; a foreign branch = `bad_branch`) and starts `setting_up`, the status the pick-lists show. Kinds: the six of the CHECK; aliases branch / dealer_branch / sales_point = showroom, warehouse / store = godown. Stored code = business code (lower case) + `_` + your code (global unique, immutable; existing codes untouched; clear errors `bad_code`, `code_too_long`, `code_in_use`). Name must be unique inside the business, the same name in another business is allowed and never revealed. Idempotent by client key.
  * `business_place_move135(...)`: owner only, `p_dry` default true (impact: stock, transactions per table, open documents, people, supply link, blockers), always refuses people / open documents / cross-border supply link, refuses transactions unless `p_force`, reason needed, append-only history in `business_place_ops135`.
  * `business_places_list135`, `business_profile_ensure135` (phase134 already seeds a profile by trigger when a business unit is created; the helper only repairs one that has none).
  * `location_save` (phase16) is text-patched once: a transaction-bound token (set only inside `business_place_create135` after its own permission test, tied to the transaction id) skips the "may add a place" test; the name test then compares inside the business; the insert carries `org_unit_id`. Found by test: with `org_scope_on` ON the phase133 border trigger refuses the settings-sheet insert of an UNMAPPED new place for a non-owner, so the place must be born mapped.
* Web: `web/places135.js` (+ hooks in `web/org122.js`, script tag in `web/index.html`, keywords on the existing `organization` record in `web/ia.js`; no new route). Bilingual, friendly error texts, 360 px tested.
* Setup page `/home/user/work-c4-out/setup-run-25.html` (`tools/gen_setup_run_25.py`): SQL byte-identical to `supabase/phase135.sql`; one read-only Check of 15 lines, safe BEFORE the paste (2/15, no error), 15/15 after; no chain lock, no localStorage; copy buttons tested headless at 360 px.

## 3. Verification

* `supabase/phase135_test.sql`: 130 pass / 0 fail on a fresh `final_build.sh` database (two businesses created exactly as the app does; mapping, kinds, codes, defaults equal to the Places screen path, idempotency, validation codes, who may / may not (owner, A manager, D manager, plain users, cross attempts), RLS visibility with the switch ON, move dry-run / blockers / force / history, profile helper, paste twice, privileges, token cannot be forged, sweets fingerprint identical).
* `tests/sql/loc135_before_after.sh` (switch OFF, same seeded data): OK - identical rules, grants, tree, locations, counts, digest, dues, trial balance, policies and the OLD add-a-place path (same row, 17 steps, sheets, error texts); only `location_save` changed, 8 functions are new, none dropped.
* Full `run_all_sql.sh` (TIMEOUT=2400): first run 10226 pass / 54 fail = baseline 50 + 4 caused by phase135 in three suites that assert "no other function mentions these tables" / "every table with a place column has the border trigger" (phase127 T10, phase129 T7, phase133 T5 and T14). Fixed (the impact helper writes the two dealer table names in two pieces; the ops table is listed as a system record in the phase133 test), then re-run: phase127 109/0, phase129 91/0, phase133 269/0, phase135 130/0. The whole suite was NOT run a second time, so 50 = baseline is derived (all other suites were equal to their baseline in the first run). No baseline file was edited.
* `tag_loss_check.sh`: NET LOST TAGS 0. `check_paste_order.py`: OK (row 62). Scope allowlist regenerated: 264 reviewed functions (+ `business_place_move135`, OWNER).
* Web (Playwright, mocked RPCs): `places135_test.js` ALL OK (add place, errors, client key reuse, pick-lists per business, list + move with force / blockers, the 3-step New business incl. retry without duplicates, manager has no New business / Move, 360 px, no JS errors); org122, ia, nav2, b2, profile134, control, favsync, settings2, nav_b, order 37/0, order_lazy 37/0, lazy 32/0, sec2_csp 23/0 all clean; lang_all 2861 = baseline 2861, NEW 0.

## 4. Not verified / honest list

1. Nothing ran on the owner's live Supabase or on a phone.
2. The old Places screen (`#/locations` Add) still creates UNMAPPED places; with a second business they belong implicitly to the first business in the pick-lists (bizctx rule). Use Organization to add places once a second business exists.
3. A user who can neither be an owner nor hold `org_manage` cannot create places (by design); the manager of a business must be assigned a place of that business first (phase134 rule: his business is the one his places belong to), so the owner makes the first place.
4. A forced move carries the place history to the new business; items of the old business at that place are not re-assigned (the stock guard of phase132 may then refuse new movements of those items while `org_scope_on` is ON).
5. Template switches (cheque, schemes, tinting, import-export) are not enabled automatically; the checklist only names the step.
