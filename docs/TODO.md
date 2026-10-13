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
