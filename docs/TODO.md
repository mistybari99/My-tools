# TODO — exact build tasks (no re-audit of the whole app; test with DRY data only)
Rule: real data comes after the software is complete. Every task = write → dry test (fake rows in local DB, rolled back) → one audit of ONLY that diff → push. Each new screen registered in web/ia.js. Every feature has an ON/OFF setting.

## A. Correctness first (wrong numbers if left)
- [ ] A1 GRN(04-1) vs purchase page both post purchase_in → one source of truth + cross-check + switch.
- [ ] A2 Sales/due reports not net of sale returns / refund cash → subtract.
- [ ] A3 Hard-coded locations in forms_cash/forms_sales/forms_staff → read `locations`, hide paused/closed.
- [ ] A4 Day-book gaps: bank deposit (10-3), customer advance, owner top-up, hub-receipt side of 10-1.
- [ ] A5 Production run void/undo (reverses ledger); packaging line on receipt.

## B. Rules / safety
- [ ] B1 owner_self_approve for wastage, supplier refund, sale return, settings approvals.
- [ ] B2 Blind count for 04-3 and 04-1; expected qty sealed server-side (browser must not compute it).
- [ ] B3 PIN signature on the other two-person forms (per-form table pin_sig_cfg).
- [ ] B4 Owner Switchboard page: ONE searchable page for every ON/OFF (ia_home_v2, ui_collapsed_controls, blind_count_cfg, pin_sig_cfg, all existing).

## C. Missing screens / reports
- [ ] C1 34 reports left: S10,P2,P4-P6,K2,K3,F1-F4,E2-E4,W1,W2,D5,T3,T4,L1-L5,X2-X5,G2,M1,M2,Q1-Q3 (build in batches of ~8, one shared report template).
- [ ] C2 Recipe/production reports.
- [ ] C3 Parallel-mode comparison (paper vs app pairs) + month-end pass/fail.
- [ ] C4 Item list type/class count badges.
- [ ] C5 Needs-you oldest-first rows; printbooks tile live; release_decide page.

## D. Usability
- [ ] D1 ~50 plain selects → B.listctl.enhance (purchase unit/return reasons, sale-return reasons, stock unit, wallets, asset condition, itemmaster type/class, unit conversion).
- [ ] D2 Guided steppers: open shop, close day (14-1→10-1→deposit), factory day, month-end.
- [ ] D3 Delegation board; templates/smart defaults.
- [ ] D4 Service worker (offline first-load).
- [ ] D5 Fix stale tests: pos_test.js (#cart_given), engine_test.js assertions, re-run tests/sql/p9.

## E. NOT code — after software is complete (real data / owner)
- [ ] E1 Prices/units/min-stock via #/bulkitems; 57 legacy items in #/itemmap; Bangla category names.
- [ ] E2 Per-form paper check docs/forms/* (needs paper kit).
- [ ] E3 Auth hook, confirm phase 22, switches ON, permissions, mishti_factory, phone checklist (docs/DEVICE_CHECKLIST.md).
- [ ] E4 VAT/Mushak stays OFF until adviser gives the rate.

## Order: A1→A2→A3→A4→A5 → B1→B2→B3→B4 → C → D. Stop and report after each letter group.
