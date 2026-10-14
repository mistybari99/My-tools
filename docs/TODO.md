# TODO — exact build tasks (no re-audit of the whole app; test with DRY data only)
Rule: real data comes after the software is complete. Every task = write → dry test (fake rows in local DB, rolled back) → one audit of ONLY that diff → push. Each new screen registered in web/ia.js. Every feature has an ON/OFF setting.

## A. Correctness first (wrong numbers if left)
- [x] A1 GRN(04-1) vs purchase page both post purchase_in → one source of truth + cross-check + switch.
- [x] A2 Sales/due reports not net of sale returns / refund cash → subtract.
- [x] A3 Hard-coded locations in forms_cash/forms_sales/forms_staff → read `locations`, hide paused/closed.
- [x] A4 Day-book gaps: bank deposit (10-3), customer advance, owner top-up, hub-receipt side of 10-1.
- [x] A5 Production run void/undo (reverses ledger); packaging line on receipt.

## B. Rules / safety
- [x] B1 owner_self_approve for wastage, supplier refund, sale return, settings approvals.
- [x] B2 Blind count for 04-3 and 04-1; expected qty sealed server-side (browser must not compute it).
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
- [x] D2 Guided steppers: open shop, close day (14-1→10-1→deposit), factory day, month-end.
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
