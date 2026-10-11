# Islamia BOS — Roadmap & checkpoints

Rule: after every phase (or at most every ~60–90 min of work) update the **Checkpoint log** at the bottom:
what is done, what is next, what is untested. Read this file first when resuming. Every phase is audited by a
separate review agent before it is called done.

Workflow per phase: code → local test (Postgres mock + Playwright stub) → audit agent → fix → commit/push
(private repo `My-tools` branch `ccr-78d03e25-k7ksyo`; public `islamia-bos-app` main gets only `web/`) → tell user.

## Phases
- [x] P1 Core: auth (Staff ID+PIN), roles, matrix, items & prices, approvals, audit log, backup
- [x] P2 Form engine + 5 forms (14-1, 10-1, 10-2, 03-1, 04-3), exceptions, release requests, location settings
- [x] Hosting: GitHub Pages live, owner registered (real Supabase verified: signup, login, home)
- [x] P3a POS / running sales page (`phase3.sql`: `sales`, `record_sale`, `void_sale`) — items, quick sale, rush mode
- [x] P3b Owner dashboard (problems first + short numbers; uses POS sales, entries, exceptions)
- [x] P3c Photos (engine + 10-2; 04-1/08-1 when built) (Storage bucket `photos`) on 10-2, 04-1, 08-1 — SQL goes in the same `phase3.sql`
- [x] P4 Remaining forms (all 41 form specs live; audited by 3 independent agents, findings fixed) in batches (see list below), each audited
- [ ] P5 Hardening: server-side recompute of key equations, offline queue, hard PIN lock

## Remaining forms (37) — batch order
1. Stock/purchase: 04-1 GRN, 04-2 Material issue, 04-4 Store ledger, 06-1 PR, 06-2 CS, 06-3 PO, 06-4 Bill check, 06-5 Supplier ledger
2. Cash/accounts: 10-3 Digital recon, 10-4 Cash position, 10-5 Receivable/advance, 18-1 Marketing expense, 20-6 Online/delivery ledger
3. Showroom/sales: 14-2 Jalebi counter, 20-1 Order form, 20-2 Discount slip, 20-3 Return/complaint, 20-4 Party invoice, 20-5?
4. Factory: 05-1…05-5
5. People: 11-1, 02-1…02-8
6. Assets/owner: 08-1, 01-1, 01-2, 0-1 (location settings sheet is already the Location settings page)

## Decisions this phase
- POS lines store a **price snapshot**; later price changes never alter old sales.
- A sale is never edited; mistakes are fixed by **void with a note** (owner or POS approver). Voids go to exceptions.
- Discount and price override are recorded per sale; the dashboard shows them. No invented limits.
- Quick sale = amount + payment mode (+ optional category), for rush hours.
- Pending sales queue in localStorage when the network drops and are re-sent (rush safety).

## Checkpoint log
- 2026-10-11 · P1, P2 done and live. Owner `imgowner01` registered on real Supabase. Next: P3a POS.
- 2026-10-11 (later) · P3a/b/c coded + locally tested (DB test4.sql all pass; UI pos_test.js, photo_test.js pass). `supabase/phase3.sql`
  NOT yet run on real Supabase, so the public site (islamia-bos-app) is NOT updated with POS/dashboard/photos yet.
  Next: audit agent on phase3, fix findings, then ask user to run phase3.sql once and push web/ to the public repo. Then P4 forms.
- 2026-10-11 (audit round) · Audit agent found 14 issues in phase 3; fixed: offline queue (per-user, no lost/dropped sales, failed list),
  offline sale keeps its own time, price-drift flag, storage policies scoped by form+location+size+jpeg, exception location scope,
  dashboard uses `sales_summary` RPC (no 1000-row cap), digits normalised, POS can't be saved as a generic entry, input validation.
  Left as owner decision: any POS-enter user may override a price (it creates a yellow exception) — tell owner.
  Running now: 5 form-building agents (files web/forms_stock|cash|sales|factory|staff.js). Next: audit each, add script tags to index.html, run phase3.sql with user, push web/ to public repo.
- 2026-10-11 (forms) · All 41 forms live in web/ (forms_stock/cash/sales/factory/staff.js, index.html wired). 3 audit rounds done and fixed;
  engine bug fixed (sparse table rows). allforms_test.js: every form opens in bn/mix/en with no JS errors.
  Pending: user runs supabase/phase3.sql once; open owner decisions are listed in the chat summary (leave includes paid leave?, 18-1 limit monthly or per expense?, 20-1 discount limit reuse, flag colours chosen by authors).
  Next: P5 hardening (server-side recompute of key equations, hard PIN lock), real-device test by owner.
- 2026-10-11 (business logic) · supabase/phase4.sql: read-only analytics functions (biz_daily, biz_items ABC, biz_staff vs peer median,
  biz_outlook purchase estimate from same-weekday sales x actual cost ratio, biz_suggest limit suggestions from history). Tested on synthetic data
  (totals cross-checked). web/biz.js page '#/biz' (Business analysis): margin, break-even (needs setting fixed_cost_month), outlook, ABC, staff indicators
  (flag only if owner sets anomaly_ratio), limit suggestions with an explicit Apply button. Nothing is auto-applied. Run order for user: phase3.sql then phase4.sql.
  Next: audit phase4 + biz.js, P5 hardening (server recompute, PIN lock).
- 2026-10-11 (live) · User ran phase3.sql + phase4.sql on real Supabase (combined, Success). Public site has all features; temp setup page removed.
  Next: owner tries POS/forms on phone and sends screenshots; fix issues. P5 hardening still open (server-side recompute, hard PIN lock).
- 2026-10-11 (POS v2, research) · Research (Odoo/ERPNext/Zoho/Loyverse/Square/Lightspeed/QuickBooks/Xero + Bangladesh products; sources partly secondary).
  Built: phase6.sql (customers by mobile, split/partial payment, baki ledger + collections, wholesale rule, option_lists table, discount/price-override need a manager,
  credit limit per customer) + web/pay.js, pos.js v2, dues.js. Bng-Eng suffix bug fixed (Count-এর). Not yet run on real DB: phase5.sql, phase6.sql (user will run later).
  Rules decided from research: hide expected cash from cashier (already blind count), manager approval for discount above limit / price override, credit limit with manager override,
  void keeps reason, sequential receipt numbers. Still TODO: editable lists UI (#/lists) + forms reading lists, marketing-head limits & fridges as compact tables, books-closed date lock,
  stock write-off reasons, receipt VAT/Mushak question for owner.
- 2026-10-11 (lists, lock) · web/lists.js (#/lists: expense heads, marketing heads + monthly limit, wallets), location settings show fridges and day tags as one compact table each,
  books-closed date (settings key books_closed_until; only the owner can change anything dated on/before it) in phase6.sql. Full chain schema->phase6 builds and tests pass on a fresh DB.
  Audit of phase6/POS v2 launched. User still has to run phase5.sql + phase6.sql (the app falls back safely until then: full-cash single-mode sales still work, dues page needs SQL).
- 2026-10-11 (audit 5) · 23 findings on phase5/6 + POS v2; fixed: customer balance is business-wide (credit limit cannot be dodged at another shop), collection idempotency/lock,
  reversible collections (void_collection), correct FIFO oldest-due, rounding to 2 dp, discount without a written limit needs a manager, safe books-closed date (+validation),
  number-audit digit cap, mobile normaliser, offline-queue poison handling, quick-sale standalone, change maths, collection location picker, credit-limit validation, list reorder in one write.
  Known/accepted: voiding a sale after its dues were collected leaves the customer in credit (shown as negative balance); custom/quick lines have no price control beyond the yellow exception.
- 2026-10-11 (rules & emergency) · phase7.sql: rules table (switches/numbers/choices), rule_grants + grant_defs (who may do what), emergency_requests with
  request/decide/cancel/use, can_do/can_loc honour short emergency windows, entry paper-no rule. record_sale2/lock_check/void_* now read rules+grants.
  web/rules.js (#/rulehub tabs Rules / Who may do what / More; #/emergency owner queue; staff 'ask for emergency approval' sheet). Home regrouped, MODULE_MAP.md written.
  supabase/ALL_NEW.sql = phase5+6+7 in one paste (builds on a fresh chain; tests test10/11 pass). User declined to run SQL: only they can (no DB access from here).

## Checkpoint — audit fixes for rules / emergency system
- Emergency approvals now bound to amount, date and location; form_access cannot target ITEM_COST or unknown forms.
- Window use leaves an `emergency_window_used` exception; unattributed due leaves `unattributed_due`.
- Rule number bounds enforced; internal helpers revoked from public roles; one approval covers one sale.
- Regression tests (forms, POS, rules, lists, biz) all pass. `supabase/ALL_NEW.sql` regenerated (phase5+6+7) — still to be run once by the owner.

## Checkpoint — Plan v2 build (UI v2, phase8 masters/settings, phase9 report engine, reports/settings/invoice UI)
- All JS regression tests + new tests pass; phase8 106/106, phase9 125/125 SQL tests; independent audit done, fixes applied.
- supabase/ALL_NEW2.sql = phase8 + phase9 — to be run once by owner (off-hours; brief lock on sales).

## Checkpoint — items v2, barcode, supplier picker, stock ledger + purchases (phase10)
- Web: items2, barcode, supplier picker in forms, stock2, purchase/payables; 14 test suites green.
- phase10.sql: audit found 13 issues, all fixed; phase10_test 307/307. ALL_NEW3.sql = phase10 (phase8/9 already live).
