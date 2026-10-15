# INTEGRATION REPORT 8 - Reports (131), master data per business (132), behaviour per business (133) merged

Branch `local-int2` (worktree /home/user/work-int2), cut from `local-rpt` (which holds `local-int` = phases 122-129, and phase 131). NOTHING is pushed, NOTHING is pasted on the live database, no public repo touched. The owner must say "push".

## 1. Branch map

| Step | What it brought | Phase |
|---|---|---|
| local-rpt (base, contains local-int) | Organization layer, walls C1, import-export, variants, dealer, web B2, reports Stage 1 | 122-129, 131 |
| local-c2 (5b39aa7), merged without conflict | master data per business: 54-row registry, `org_unit_id` on 34 master tables, restrictive read policies, write guard, shares, per-business uniqueness (relax / restore), 93 functions patched | 132 |
| local-c3 (d32b385), merged with conflicts | behaviour, permissions, reports per business: rule overrides, per-business grants / role forms, write-border triggers on 95 tables, 41 patched + 4 re-created functions, per-business digest, storage and bot rules, differential probe | 133 |

Conflicts (all resolved keeping both sides): docs (HANDOVER_7, REMAINING, TODO, PASTE_ORDER), `tests/sql/paste_order.env`, and the repair tails of the old replacement suites (89h, 94b, 98d, 98e, 103b, 103d, 110b, 112, 113b, 115b, 119). C3's placeholder row 59 of PASTE_ORDER was dropped (C2's real row 59 wins; row 60 and notes N11 / N12 kept). After the merge three more suites (87, 100, 111) got `phase133` after `phase132` (C2 had given them only 132).

Fixes made at the root during the merge:
* `phase89h_test` P2a existed twice (C2 expected 17 re-created functions, C3 expected 16). The real number on the merged chain is 18 (the 15 of the older phases + `recipe_approve` and `stock_post` from phase132 + `acct_status` from phase133). One line now, with the 18-function list. (No phase file was touched.)
* `tools/scope_classify133.py` had no class for six phase132 functions (`master_share_create / revoke / list`, `master_scope_report132`, `org_masters_relax_unique / restore_unique`); added one OWNER rule with the reason. `tests/sql/scope_allowlist.txt` and `docs/audit_c1/C3_COVERAGE.md` were regenerated on a merged build with the C3 seed users (267 reviewed functions; C2's patches made some entries scope-aware).
* Tag markers: C3 re-creates `rule_val`, `can_grant`, `can_do`, `has_grant` and patches 41 more; C2 patches 93. No function was patched by both with a collision: `tag_loss_check` = NET LOST TAGS 0, and the three `c*_before_after` proofs show the bodies are what each phase promises (section 3). No re-assert was needed.

## 2. Final canonical order

`... 118, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, (130 = test only), 131, 132, 133`. Rows 50 to 60 of `docs/PASTE_ORDER.md` = `tests/sql/paste_order.env` (phase130 is a test file and is not in either list, as phase119). `python3 tools/check_paste_order.py` = OK. `bash tests/sql/tag_loss_check.sh` = NET LOST TAGS 0.

Re-paste tails: every replacement suite that repairs after an older phase now ends with `129, 131, 132, 133` in that order (checked by script over all `supabase/*_test.sql`). Rule for the owner: after re-pasting any older phase, paste 112..118, 120, 121, then 122..129, 131, 132, 133 again.

## 3. Test results (fresh `final_build.sh` database, phases 72..133)

| Check | Result | Baseline |
|---|---|---|
| `run_all_sql.sh` (125 suites) | 9966 pass / 50 fail after the phase89h fix (first run 9965 / 52: only phase89h P2a, see above) | 50 = exactly `baseline_fails.txt` (phase16 7, phase18 1, phase21 17, phase21b 17, phase118 V10 1 ...), every suite `= baseline`; the file was NOT edited |
| New suites | phase122 111/0, 123 171/0, 124 118/0, 125 139/0, 126 53/0, 127 109/0, 128 88/0, 129 91/0, 131 197/0, 132 176/0, 133 269/0 | - |
| `phase130_integration_test` extended (T4 new) | 57 pass / 0 fail (was 28) | - |
| e2e | def 206/0, rec 205/0 | same as before |
| Before / after, switch OFF = identical, each on a final build that lacks only its own phases | b1 OK (11 fingerprints), c1 OK (OFF identical, ON owner identical), var125 OK (13), dl127 OK (14), c2 ALL OK (reads, writes, 1389 other functions byte-identical, 93 patched, owner ON identical), c3 OK (OFF identical, changed bodies = the 45 marked bodies, owner ON identical), reports131 OK (new `tests/sql/rpt131_before_after.sh`: every function body except `rpt131_*`, every rule except `rpt131_on`, policies, grants, table count identical) | - |
| Web (Playwright, mocked RPCs) | org122, b2, impexp124, variants125, dealer127, reports131: no errors, 0 assert failures; order 37/0; order_lazy 37/0; lazy 32/0; ia: no errors, 0 assert failures; lang_all: 2861 violations = baseline 2861, NEW 0 | - |

The extended integration test (T4, switch ON, businesses Sweets / Hardware / Import-Export, scoped users): reports131 (`rpt131_sales`, `rpt131_item_profit`) show a manager only his own place and refuse a foreign place; masters (customers, suppliers, items) are filtered by direct select for each manager and the owner sees all with the same counts as OFF; per-business rule override is read by the HW manager only, a sweets manager cannot set one; per-business digest only for the own business; owner totals (sales rows, trial balance, report totals, customer / supplier counts) equal ON and OFF; OFF again: a management user sees both places again.

## 4. Setup page

`/home/user/work-c4-out/setup-run-21-23.html` (about 252 KB): ONE page, three parts (131, 132, 133), each with Copy Part N, its own read-only Check and a Check all; no chain lock, no localStorage; same style and behaviour as the published `setup-run-17-20.html`. Generated by `tools/gen_setup_run_21_23.py` from the three single pages: SQL strings are extracted programmatically and are byte-identical to `setup-run-21/22/23.html` (and each ends with the repo file `supabase/phase131/132/133.sql`).

Earlier flaw fixed: a Check could fail with an error (or be partly true) before its part was pasted. The checks of parts 2 and 3 now use `case when to_regprocedure(...) is null`, `to_regclass(...)` for privilege tests and require the part's own object before any "was not touched / not executable" check counts. Scratch DB built to phase 129: Check all BEFORE = 0/16, 0/30, 0/33 (crosses, no error); pasted parts 1, 2, 3 in order, each Check = 16/16, 30/30, 33/33, Check all = N/N; re-pasted all three twice: no error, still N/N. `node --check` on the page script OK; headless click test at 360 px: every Copy / Check button puts the right text on the clipboard, no JS error, no horizontal overflow. The three single pages (21, 22, 23) are unchanged and not to be used. NOT published.

## 5. What the strict separation now covers (switch `org_scope_on` ON, default OFF)

* Places, sales, dues, assets, costs, staff (phase123), plus every table with a place column through a write-border trigger (phase133, 95 tables): a non-owner cannot write a row of a foreign place by any function.
* Masters (phase132): customers, items, suppliers, recipes, artisans, categories, employees, price lists, option lists and children: 34 tables with `org_unit_id`, restrictive read policy, write guard, stock guard (an item of one business cannot be booked at a place of another), sharing only by explicit owner share, per-business unique customer mobile and item code / barcode after `org_masters_relax_unique`.
* Rules, roles, grants (phase133): value per business (`rule_overrides`), grant matrix and form rights per business, `management` per business; 826 exposed definer functions classified, 520 scope-aware by construction, 306 reviewed one by one, 0 without a reason; checker `scope_gaps133()` plus reviewed list make a new unscoped function fail the test.
* Reports (phase131 / 133): `rpt131_*`, `report_run`, `receivable_aging`, `my_context`, per-business `daily_digest_biz133`; photos path / policies; one bot per business is the recommended design (a bot of A cannot write into the channel of B).
* Import-export, variants, dealer (124-129): isolated, proved in the integration test.

## 6. What is NOT separated (honest list)

1. Chart of accounts `coa_accounts` and `acct_mappings`: one chart for the whole database. While the switch is ON these, the opening journal, bank statements / matching, scheduler, main cost place and the setup advisors are OWNER-ONLY. The posting engine runs on one ledger (no per-legal-entity books).
2. Loyalty ladder (tiers, gift rules): one ladder for the group.
3. Vocabulary primary keys: the same `value_code` cannot exist in two businesses; `employees.nid_no` is global.
4. Intake bots / web orders (no login): new customers land in the default (sweets) business until a bot identity per business exists; SMS outbox has no business column; storage is ONE bucket (isolation by policy and path).
5. Web screens: nothing in `web/` calls `rules_effective133()` or the override setters; screens that show rule values still show the GROUP value; there is no per-business rule or role-matrix UI and no Switchboard business selector. A second business sees EMPTY pick lists until the owner creates or shares them.
6. A cashier typing a mobile that already belongs to another business gets the plain unique error until the owner has run the relax.
7. Report functions that join items by code are only listed as warnings by `org_masters_preflight()`.
8. Intercompany (cross-business stock transfer is refused), master owner dashboard (Stage F), dealer POS, GL posting for schemes / import-export, fashion slices: not built.

## 7. Exact switch-on procedure for `org_scope_on`

Nothing below has been done on a live database. One step per day; check after each; OFF goes back instantly (except while unique keys are relaxed, see step 8).

0. Prerequisites: Runs 17-20 and 21-23 pasted, all Checks green (`Check all` of each page). Take a backup.
1. #/organization: check the sweets tree; add legal entity, then the new business, then its branches.
2. Map locations: every place must have `locations.org_unit_id` (new places are not mapped automatically).
3. Users: give each manager a scope (`org_scope_grant(user, business, 'management', note, client_uuid)`; the user must also hold the role `management`), assign staff places (`user_locations`), give grants with the right place.
4. Preflight, as owner: `select org_scope_preflight();` (unmapped places, managers without scope, NULL-place config rows, personal grants without a place) and `select org_masters_preflight();` (masters without business, duplicates blocking the per-business unique, warnings). Also `select * from scope_gaps133();` must list only the reviewed functions. Fix everything listed.
5. Optional per-business values: `rule_override_set133(business, key, value, note, client_uuid)`; `rule_grant_override_set133`, `role_form_override_set133`; check with `rules_effective133(business)` and `role_matrix_list133(business)`. Money-book rules stay group-wide.
6. Turn `org_scope_on` ON in #/switchboard. Test with a manager of EACH business (own places only, no foreign customer / supplier / item, reports only own) and with the owner (same numbers as before).
7. Then per business, one per day: `impexp_on`, `variants_on`, `dealer_cheque_on`, `dealer_scheme_on`, `dealer_tint_on`, `rpt131_on`.
8. Only if two businesses need the same item code or customer mobile: `select org_masters_relax_unique(true);` (dry run), read it, then `(false, true)`. Restore with `org_masters_restore_unique(...)`; the switch cannot go OFF while keys are relaxed.
9. Rollback: set `org_scope_on` OFF in #/switchboard (instant, no data change; per-business rows and overrides stay but are ignored). If keys were relaxed, restore them first (needs no duplicates).

## 8. Risks and unverified items

* Nothing ran on the owner's live Supabase or on a phone; all numbers are synthetic scratch databases. Pages 21-23 are verified on a scratch DB (before 0/N, after N/N, re-paste x2), not clicked in the live SQL editor.
* Storage policies proved on the mock bucket only; on the real `storage.objects` the SQL editor must be allowed to create policies.
* The Supabase default-grant assumption (a function without an explicit revoke stays executable by `authenticated`) is an audit assumption.
* Timings are from the scratch box (`can_do` about 15-20 percent slower, `rule_val` faster).
* Phase 132 and 133 patch live function bodies by text; if an older phase is re-pasted, the patched bodies are put back (re-paste rule, section 2) and phase 133 stops with "the anchor ... is not in <function> exactly once" if a newer body no longer matches: merge by hand.
* The differential probe of C3 has 11 reviewed known differences (`tests/sql/scope_probe_known.txt`).
* Run 21-23 page is 252 KB (more than the usual 200 KB) because the owner asked for one page; each part is 64-88 KB.

## 9. Remaining work

1. C2b: per-legal-entity chart of accounts, mappings, bank statements, opening journal and posting engine (needs a rewrite of the posting functions); per-business loyalty ladder; vocabulary PKs per business; per-business SMS outbox and main cost place; bot identity per business and storage layout.
2. Web (B2 owner): rule-override editor + Switchboard business selector (`rule_overrides_list133`, `rules_effective133`, `rule_override_set133`), role matrix per business (`role_matrix_list133`), master share screen, working-business switcher (`master_context_set132`), screens that show GROUP rule values.
3. Dealer POS (scheme / tint / cheque at the counter); GL posting for schemes and import-export.
4. Fashion slices (retail, wholesale, online, tailoring), template seed `fashion_apparel`.
5. Stage E intercompany (default OFF); Stage F master dashboard with `data_status`.
6. Owner phone UAT of #/reports131, #/organization and the new screens at 360 px; Bangla wording of the new error codes of 132 / 133.
7. Publish: setup-run-21-23.html after Runs 17-20; the owner pastes Part 1, 2, 3 with their Checks.

## 10. Owner checklist (short MCQ; nothing is switched on until the owner says so)

1. May we paste Run 21-23 (it changes nothing you see; every feature stays OFF)?  A) Today, after Run 17-20 Checks are green. B) Ask again next week.
2. Walls between businesses ON?  A) Not yet, first my second business. B) Yes, after the preflight lists are empty. C) No, one business only.
3. Will two businesses need the SAME item code or customer mobile?  A) No (recommended). B) Yes (relax step 8).
4. A new business starts with EMPTY lists (items, categories, expense heads). A) I create them. B) Share the sweets lists read-only. C) Decide later.
5. Who may change a rule for one business?  A) Only me (built). B) The manager of that business (needs a screen).
6. Bots (Telegram / WhatsApp / SMS)?  A) One bot per business (recommended). B) One group bot.
7. Business accountants: OK that chart of accounts, bank reconciliation and opening journal are owner-only while the walls are ON (until C2b)?  A) Yes. B) No, build per-business books first.
8. Push to the public site now?  A) No, wait. B) Yes, after I check the screens on my phone.
