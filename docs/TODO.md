# TODO — exact build tasks (no re-audit of the whole app; test with DRY data only)
Rule: real data comes after the software is complete. Every task = write → dry test (fake rows in local DB, rolled back) → one audit of ONLY that diff → push. Each new screen registered in web/ia.js. Every feature has an ON/OFF setting.

## A. Correctness first (wrong numbers if left)
- [x] A1 GRN(13-1) vs purchase page both post purchase_in → one source of truth + cross-check + switch.
- [x] A2 Sales/due reports not net of sale returns / refund cash → subtract.
- [x] A3 Hard-coded locations in forms_cash/forms_sales/forms_staff → read `locations`, hide paused/closed.
- [x] A4 Day-book gaps: bank deposit (07-1), customer advance, owner top-up, hub-receipt side of 03-1.
- [x] A5 Production run void/undo (reverses ledger); packaging line on receipt.

## B. Rules / safety
- [x] B1 owner_self_approve for wastage, supplier refund, sale return, settings approvals.
- [x] B2 Blind count for 36-1 and 13-1; expected qty sealed server-side (browser must not compute it).
- [x] B3 PIN signature on the other two-person forms (per-form table pin_sig_cfg).
- [x] B4 Owner Switchboard page: ONE searchable page for every ON/OFF (ia_home_v2, ui_collapsed_controls, blind_count_cfg, pin_sig_cfg, all existing).

## C. Missing screens / reports
- [x] C1 34 reports left: S10,P2,P4-P6,K2,K3,F1-F4,E2-E4,W1,W2,D5,T3,T4,L1-L5,X2-X5,G2,M1,M2,Q1-Q3 (build in batches of ~8, one shared report template).
- [x] C2 Recipe/production reports.
- [x] C3 Parallel-mode comparison (paper vs app pairs) + month-end pass/fail.
- [x] C4 Item list type/class count badges.
- [x] C5 Needs-you oldest-first rows; printbooks tile live; release_decide page.

## D. Usability
- [x] D1 ~50 plain selects → B.listctl.enhance (purchase unit/return reasons, sale-return reasons, stock unit, wallets, asset condition, itemmaster type/class, unit conversion).
- [x] D2 Guided steppers: open shop, close day (06-1→03-1→deposit), factory day, month-end.
- [x] D3 Delegation board; templates/smart defaults.
- [x] D4 Service worker (offline first-load).
- [x] D5 Fix stale tests: pos_test.js (#cart_given), engine_test.js assertions, re-run tests/sql/p9.

## E. NOT code — after software is complete (real data / owner)
- [ ] E1 Prices/units/min-stock via #/bulkitems; 57 legacy items in #/itemmap; Bangla category names.
- [ ] E2 Per-form paper check docs/forms/* (needs paper kit).
- [ ] E3 Auth hook, confirm phase 22, switches ON, permissions, mishti_factory, phone checklist (docs/DEVICE_CHECKLIST.md).
- [ ] E4 VAT/Mushak stays OFF until adviser gives the rate.

## Order: A1→A2→A3→A4→A5 → B1→B2→B3→B4 → C → D. Stop and report after each letter group.

## Status notes (latest)
* A, B: phase23 (docs/BUILD-LOG). B1 = no code needed (owner is never gated by wastage / refund / sale return; settings approval already honoured owner_self_approve).
* C: phase24 (report engine 3) + phase25/26/27 (34 reports) + phase28 (parallel comparison, print & books, Needs-you oldest). C5 release_decide page = ROUTE_GRANTS.releases.
* D1 partly: purchase / salereturn / stock2 / itemmaster (unit, asset condition) / pay wallets wired. NOT wired: item type + class (own table / free text), new-item category, unit-conversion inputs (datalist), recipes + bulkitems unit cells, customer_types picker.
* D2 flows, D3 delegation board + "start from my last one" (items / suppliers only), D4 service worker (https only), D5 tests fixed (pos_test retired -> pos2_test; engine_test asserts; tests/sql/p9/run_regress.sh = 0 differences).
* Still open: E (owner data + device checks), the blind-count book figure is still readable from stock_balance by a storekeeper, "packaging line on receipt" (unclear), per-form paper check docs/forms/*.


## F. After the audits (phases 112-121) - details in docs/HANDOVER_6.md
- [x] F1 Audit A1-A5 (docs/audit2/*), fix batches 1-4 = phases 112-118, security fixes = phase121, setup-run-15 pasted by the owner (8/8 checks).
- [x] F2a Merge impl/c4 = phase120 (report speed) on local-c4, order ...118,120,121, all suites checked, setup-run-16 built locally (not published).
- [ ] F2b Owner says "push": publish setup-run-16 to the public repo; owner pastes Run 16 and the Check (3/3).
- [ ] F3 Switch roll-out, one at a time (docs/guide/AUDIT_SWITCHES.md) + UAT checks 65-94.
- [ ] F4 Remaining audit gaps by owner priority (list in HANDOVER_6 PENDING P3); extend probes for the 23 gaps with no probe.
- [ ] F5 Update baseline_fails.txt for phase16/18/21/21b once the clock cause is confirmed; real-phone check of web build 1a9e6c6b70; re-enable CSP decision.
- [ ] F6 Multi-business: keep all new work location/business scoped (HANDOVER_6, GROUP_ERP_STAGE_A.md sections 10-11 on branch ccr-46b26d91-81vl9s).
- [x] G1 Group ERP B1: phase122 organization layer + phase122_test (111/0) + setup-run-17 built locally (docs/HANDOVER_7.md). Not pushed.
- [ ] G2 Owner says "push": publish setup-run-16 then setup-run-17; owner pastes Run 16, Run 17 and the Checks.
- [x] G4 Group ERP C1 first slice: phase123 + phase123_test (171/0) + c1_before_after.sh + setup-run-18 built locally (docs/HANDOVER_7.md, branch local-c1). Not pushed. Switch org_scope_on stays OFF.
- [ ] G5 Owner says "push": publish setup-run-16, 17, 18 in that order; owner pastes Run 16, 17, 18 and the Checks. Before switching org_scope_on ON read `select org_scope_preflight();` (HANDOVER_7 checklist).
- [ ] G6 C1 rest: the ~170 unscoped reader RPCs, per-business rules/roles/grants, storage + bot identity, audit tests 9, 10, 11, 13; needs C2 for masters.
- [ ] G3 B2 organization UI + DB-driven brands/locations; C2 master-data scope + per-entity chart of accounts; D templates; E intercompany (default OFF); F owner-only group dashboard.
- [ ] G3 B2 organization UI + DB-driven brands/locations; C1 scope-based access + RLS tightening + isolation tests behind org_scope_on; C2 master-data scope + per-entity chart of accounts; D templates; E intercompany (default OFF); F owner-only group dashboard.
- [x] G4 Import-Export basic module: phase124 + phase124_test (118/0) + web/impexp124.js + tests/web/impexp124_test.js (local-ie, not pushed).
- [ ] G5 Lead: apply docs/regs/impexp124.md (ia.js rec line, index.html script tag), merge phase123/124 rows in PASTE_ORDER, then owner creates the import_export business (#/organization), grants, turns impexp_on ON.
- [ ] G6 Import-Export later: GL posting (per-entity books), LC, customs, stock link, bank payments, owner review of Bangla labels.
- [x] G7 Variants: phase125 + phase126 + tests (139/0, 53/0, before/after identical, web mocked test) + 20k timings (local-var, not pushed).
- [ ] G8 Lead: apply docs/regs/variants125.md (ia.js rec line, index.html script tag); merge PASTE_ORDER rows (...122, 123, 124, 125, 126).
- [ ] G9 Variants next slice: price_for125 into POS / invoices / online, grid entry in purchase and POS, item lists on items_search, per-business item codes (relax plan in the regs file), bulk import of styles.
- [x] H1 Dealer business: phase127 cheque / PDC, phase128 principal schemes, phase129 tinting + tests + 3 screens (local-dl, not pushed). See docs/HANDOVER_7.md.
- [ ] H2 Lead: apply docs/regs/dealer127.md (ia.js lines + index.html script tags); add the three routes to the lazy list if the build uses it.
- [ ] H3 Owner decisions: when to turn on dealer_cheque_on / dealer_scheme_on / dealer_tint_on (one business at a time, after paste); accountant: how scheme accruals and principal receipts are booked.
- [ ] H4 Later: per-business customer / supplier master data (C2), dealer POS screens, scheme sale-return netting, cheque bounce charge billing to the customer.

- [x] G3a B2 (local-b2): organization UI, business context + switcher, DB-driven brands, business name in receipts/title (HANDOVER_7 STAGE B2). Not pushed.
- [ ] G3b B2 leftovers (raw locations readers, offline queue keys, SQL list in HANDOVER_7)
- [ ] G3 C1 scope-based access + RLS tightening + isolation tests behind org_scope_on; C2 master-data scope + per-entity chart of accounts; D templates; E intercompany (default OFF); F owner-only group dashboard.

## G. After integration (local-int) - details in docs/INTEGRATION_REPORT_7.md
- [ ] Owner "push": publish setup-run-16..20 in order; paste each Run and its Check.
- [ ] Switch-on order: org setup -> map locations -> businesses / users scopes -> org_scope_preflight -> org_scope_on -> module switches one per day.
- [ ] C2 global masters, per-business rules, remaining unscoped RPCs, dealer POS, GL posting (schemes, import-export), fashion slices, Stage E (OFF), Stage F dashboard, fashion_apparel template seed.

## I. Reports (local-rpt) - docs/audit_rpt/PLAN.md
- [x] I1 Audit of the 193 reporting requirements (REPORT_MATRIX.md, PLAN.md, tools/rpt_matrix_gen.py).
- [x] I2 Stage 1 built locally: phase131 (197/0), web/reports131.js, setup-run-21.html. Not pushed, not pasted.
- [ ] I3 Owner "push": publish setup-run-21 after Run 20; paste Run 21 + Check; give report grants, `view_stock_recon`, `accounts_view`; set `report_aging_buckets`; turn `rpt131_on` ON.
- [ ] I4 Stage 2 (missing reports on existing data): below-cost list, price history, purchase registers (payments, returns, PPV), loyalty, employee advances / OT / roster, order cancellations / channel, shelf-life / batch ageing, returns by reason.
- [ ] I5 Stage 3 repairs: daily_digest scope + ledger cost, receivable_aging return credit, item_sales net of returns, A4-G02 automatic day close, A4-G06 card settlement, A2-G10 re-dated sales flag.
- [ ] I6 Stage 4 new data capture (owner MCQ first): targets, cake orders + delivery, production plan / date, leftover count, hours worked, campaigns.
- [ ] I7 Stage 5 number tests for the jsonb-form reports (production, temperature, hygiene, purchase scorecard, expense heads, orders).
- [ ] I8 Owner phone UAT of #/reports131 at 360 px; Bangla wording review.
- [x] G9 Group ERP C2: phase132 (master data per business, switch OFF) + phase132_test + c2_before_after.sh + setup-run-22 built locally (docs/HANDOVER_7.md STAGE C2, docs/audit_c1/C2_COVERAGE.md, branch local-c2). Not pushed.
- [ ] G10 Owner says "push": paste Run 22 (after Run 21) and its Check. Before switching org_scope_on ON read `select org_scope_preflight();` and `select org_masters_preflight();`; decide whether the same item code / customer mobile must exist in two businesses (then `select org_masters_relax_unique(true);`, dry run first).
- [ ] G11 C2b: chart of accounts + mapping per legal entity (needs legal-entity books and a rewrite of the posting functions); per-business loyalty ladder; vocabulary primary keys per business; intake bots / web orders per business; business switcher on the master lists (web).


## J. Group ERP Stage C3 (local-c3) - docs/HANDOVER_7.md (STAGE C3), docs/audit_c1/C3_COVERAGE.md
- [x] J1 phase133 + phase133_test + differential probe + c3_before_after.sh + reviewed list `tests/sql/scope_allowlist.txt` (local, not pushed, not pasted).
- [x] J2 setup-run-23.html built locally (no chain lock, read-only CHECK 33 checks).
- [ ] J3 Lead: merge with C2 (phase132): paste-order rows, re-paste tails 131/132/133, regenerate the reviewed list (`python3 tools/scope_classify133.py <db>`), re-run phase133_test, phase132_test, c3_before_after.sh, c2_before_after.sh.
- [ ] J4 Owner "push": publish setup-run-22 and setup-run-23 after Run 21; paste each Run and its Check. Nothing changes until `org_scope_on` is turned ON (follow the switch-on order in INTEGRATION_REPORT_7 section 6, add: set per-business rule values with `rule_override_set133`, per-business role grants with `rule_grant_override_set133`, only after `org_scope_preflight()` is empty).
- [ ] J5 Web (B2 owner): rule-override editor + Switchboard business selector (`rule_overrides_list133`, `rules_effective133`, `rule_override_set133`), role matrix per business (`role_matrix_list133`), per-business digest tile (`daily_digest_biz133`), Bangla wording for new codes.
- [ ] J6 C2b: per-entity chart of accounts / bank statements / opening journal (they are owner-only while the switch is ON), per-business SMS outbox, per-business main cost place.
- [ ] J7 Decide with the owner: one bot per business (recommended) or one group bot that is a member of every business.

## K. Integration 8 (local-int2) - docs/INTEGRATION_REPORT_8.md
- [x] K1 merged local-c2 + local-c3 on top of local-rpt; order `...129, 131, 132, 133`; tails, allowlist, tests, before/after, one setup page `setup-run-21-23.html` (checks safe before paste).
- [ ] K2 Owner says "push": publish setup-run-21-23.html after Run 17-20; paste Part 1, 2, 3 with their Checks. Then (when ready) follow the switch-on procedure in INTEGRATION_REPORT_8 section 7.
- [ ] K3 Web: per-business rule editor, role matrix, master shares, working-business switcher (J5 above).
- [ ] K4 C2b: per-entity books, loyalty ladder, vocabulary keys, bots / SMS / storage per business.
- [ ] K5 Owner MCQ list: INTEGRATION_REPORT_8 section 10.
---
## L. Stage D (local-prof) - docs/INTEGRATION_REPORT_9.md
- [x] L1 phase134 + web profile screen + leak sweep; order `... 133, 134`; tails; allowlist regenerated; `setup-run-24.html` (check safe before paste).
- [ ] L2 Owner says "push": publish setup-run-24.html after Run 21-23; paste once; Check. Owner opens #/profile for each business and fills logo / address / receipt text.
- [ ] L3 Owner phone UAT: log in as a one-business user and confirm nothing about the group / other businesses shows (drawer, #/organization, receipts).
- [ ] L4 Decide: should audit_log / the exceptions screens ever show a business manager the history of his own business profile (today: owner only)?
---
## M. Stage D2 (local-loc) - docs/INTEGRATION_REPORT_10.md
- [x] M1 phase135 + `web/places135.js` (Add place / Places / Move place / guided New business) + tests + `setup-run-25.html` (check safe before paste).
- [ ] M2 Owner says "push": publish setup-run-25.html after Run 24; paste once; Check. Then create the second business from `#/organization` (steps in INTEGRATION_REPORT_10 section 1).
- [ ] M3 There is still NO screen for `org_scope_grant` (a person's scope over a business) and none for `org_scope_preflight`; people get a business through their places in Staff. Build a small scope screen before switching `org_scope_on` ON for real users.
- [ ] M4 The old Places screen (`#/locations`, Add) still creates UNMAPPED places (it is the unchanged phase16 path). Decide: hide its Add button once a second business exists, or add a business picker to it.
- [ ] M5 Dealer template switches (cheque, schemes, tinting, import-export) are enabled by hand in the Switchboard; a one-click "enable template switches" is not built.
