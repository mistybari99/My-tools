# ERP Audit & Roadmap (audit only — nothing implemented)

Date: 2026-10-13. Basis: repo `ccr-2f54f832-rkdi5z` (HANDOVER_3 state), public copy `islamia-bos-app`.
Method: read-only code/SQL/doc reading by 3 agents. **No SQL, tests or app were run in this audit.** Items marked UNVERIFIED were not confirmed in code.
Truth sources: `web/ia.js` (routes), `supabase/phase*.sql`. `docs/MODULE_MAP.md` is stale (no phases 40–47).

## 0. Missing documents (blocking some checks)
1. **Original paper Form Kit + Business Guide text** — NOT in repo (only `docs/inputs/Build-commands-functions-only.md`, a summary). Without it, field-by-field match of the 41 forms to paper is impossible (REMAINING #13 / TODO E2 already open).
2. Form **0-1** (Location settings): built as `locset`/`locsheet` screens, not as a form — confirm if that counts.
3. Accountant/VAT adviser rate for Mushak 6.3 (VAT stays OFF).
4. Real-DB facts: which tables exist on live Supabase, backup.yml ever ran?, accounting start date + opening balances.

## 1. Inventory (evidence)
- 70 route records in `ia.js` (13 groups). ~146 tables created in schema+phases (~179 incl. re-creates), ~888 function definitions. Phases 40–47 add ~50 tables, each with `phaseNN_test.sql`.
- Tests: `tests/sql` (test*.sql, p9/), `supabase/phase{8,10–28,40–47}_test.sql`, ~50 `tests/web/*_test.js`, `tests/py`. No CI runs them (only backup/notify workflows).
- No dedicated test: dash, cashmoves, dues, filters, flow, pager, reports2, pay, printbooks, delegation, switchboard; phases 2–7, 9, 30 have no `_test.sql` (partly covered by tests/sql — UNVERIFIED).
- Forms: 41 of 42 as JS specs (`entries.data` jsonb): 01-1,01-2; 02-1..02-8; 03-1; 04-1..04-4; 05-1..05-5; 06-1..06-5; 08-1; 10-1..10-5; 11-1; 14-1,14-2; 18-1; 20-1..20-6.
- Modules: Accounts(40) Employees(41) Attendance/Payroll(42) Customer tiers(43) Partners(44) Owner board(45) Notifications/Backup(46) Assistant(47) + POS, stock, purchase, recipes, reports, controls, locations.

## 2. Manual form ↔ shortcut tab ↔ automated workflow
| Area | Original form | Shortcut / typed screen | Automation | Link today |
|---|---|---|---|---|
| Sale | 20-1,20-2,20-4 (paper mirror in `entries`) | POS `record_sale2` → `sales` | loyalty, accounts auto-post | **None** (20-x never posts to sales) |
| Collection/dues | 20-5/20-6 | `collect_payment`, `cash_moves` advances | acct auto-post | OK |
| Expense | 10-2 | none (form is only entry) | accounts reads approved 10-2 | day book counts submitted+approved, books approved only |
| Cash/drawer | 10-1,14-1,10-3,10-4 | `cash_moves` (deposit, hub_receipt, owner top-up) | day book | 10-1 not tied to `hub_receipt` |
| Purchase | 06-1..06-5, 04-1 GRN | `purchase.js` → `purchase_bills`+`stock_ledger` | 3-way match | GRN guard `grn_receipt_source` (only guard in system) |
| Stock | 03-1,04-2,04-3 | `stock2.js` (issue/transfer/count/wastage) | `entry_post_ledger` (switch, default OFF) | **no guard** between form and screen |
| Production | 05-1..05-5 | `recipes.js` `production_post` | 05-1 output → ledger (switch) | **no guard** |
| Payroll | 02-1..02-3 | `payroll42` (`payroll_*`, `employee_advances`) | day-book salary line | **both unioned, no exclusion** |
| Partners | — (new) | `partner_capital` vs `cash_moves` owner_topup/draw | — | **unlinked** |
Rule going forward: keep every paper form; app = faster capture of the *same* record, never a second record.

## 3. Duplicate / conflict register
| # | Case | Risk | Why (evidence) | Safe resolution (needs approval) |
|---|---|---|---|---|
| D1 | Payroll: 02-2 form receipt + `payroll_payments` | **HIGH** | day book unions both (phase13.sql:162, phase42.sql:1543) | per-month mode switch (paper vs app); exclusion rule; reconcile report |
| D2 | Stock: form 04-2/03-1/04-3 posted by `entry_post_ledger` + same action in stock2 | **HIGH** (when `forms_post_to_ledger` ON) | no covered_by guard (phase20.sql:84, phase23.sql:46 GRN only) | one source per action per location; warn when both exist |
| D3 | Production: 05-1 output + recipe run | **HIGH** (switch ON) | phase20.sql:126; ingredient consume for 05-1 UNVERIFIED | recipe run = source; 05-1 becomes reference link |
| D4 | Owner top-up/draw: `cash_moves` vs `partner_capital` | Med-High | books see only cash_moves (phase40.sql:428); no link | partner_capital authoritative for equity; cash_move references it |
| D5 | Sale keyed in 20-4 and POS | Med | 20-x posts nowhere | 20-x = print/paper copy that links to a `sales` row |
| D6 | GRN as source while purchase page also posts | Med | warn only (phase47.sql:307) | make settings mutually exclusive |
| D7 | Expense status mismatch day book vs accounts | Med | submitted vs approved | align to approved (or show both labeled) |
| D8 | 10-1 handover vs hub `hub_receipt` | Med | warn `hub_receipt_not_recorded` only | link by reference id |
| D9 | Manual journal duplicating an auto-posted source | Low-Med | no duplicate check on manual journals (UNVERIFIED) | warn on same date+amount+party |
| D10 | Accounts have no source for payroll, advances, partners, 20-x, 10-1/10-3/14-1 | **Gap** | phase40 header "not connected" | typed manual journals meanwhile → add auto-post sources |
| D11 | Forms have no retry/outbox (POS only) | Med | entry.js draft only | forms outbox with client ids |
Idempotency that **is** sound: `sales.client_id`, `purchase_bills.client_id`, `stock_ledger (client_id,reason)`, `production_runs.client_id`, `payroll_runs` one/month/location, `partner_capital.client_id`, `je_source_uq(source_type,source_id)`, attendance punch unique index.
Existing reconcile: `stock_reconcile`, `acct_reconcile` (customer/supplier vs journal), `ledger_post_problems`, phase28 parallel comparison, phase47 health flags.
**Missing reconcile:** day book↔journal, payroll_payments↔02-2, form-posted↔stock2, partner_capital↔cash_moves.
No existing records were touched; suspected duplicates must be found by *read-only* reports first, then reviewed one by one.

## 4. ERP capability comparison
Legend: V verified (UI+SQL+test) · P partial · M missing.
| Area | V | P | M / unnecessary |
|---|---|---|---|
| Finance | CoA, journals, TB, P&L, BS, cash flow, party ledger | bank reconciliation (acct_reconcile is integrity check, no bank-statement match), period close (lock only, no year-end roll), VAT (setting only) | bank statement import, multi-currency (unnecessary), fixed-asset depreciation, budgets |
| Purchase/stock | bills, returns, payables, 3-way match, ledger, transfers, counts, wastage | — | reorder suggestions, wastage-reason list, batch/expiry on GRN |
| Manufacturing | recipes/BOM, production, packaging | quality (yield test form only) | production void/undo is done (A5); QC module = optional |
| Sales | POS, returns, customers, tiers, loyalty, dues | orders/invoicing (print template + paper forms) | online order channel (future) |
| HR | employees, docs, deeds, attendance, leave, payroll | benefits (basic) | payroll→accounts posting |
| Partners | agreements, capital, settlements | link to accounts | — |
| Multi-branch/reports | locations, 19 reports + 34 more, owner board | day-book↔books reconcile | BI export |
| Approvals/automation | exceptions, releases, emergency, change requests, notifications | scheduled jobs only (notify_scan, digest) | general workflow engine (unnecessary now) |
| Security | RLS everywhere (loop-checked), audit_log append-only, grants | PIN lock (see §7), backup | restore drill, 2FA |
| AI/integrations | assistant (local) | llm_proxy not deployed; PWA/offline (not device-tested) | SMS/WhatsApp/payment-gateway/accounting export |

## 5. Source-of-truth proposal
| Transaction | Authoritative | Others become |
|---|---|---|
| Sale | `sales`+`sale_payments` | 20-x = linked print/paper copy |
| Purchase | `purchase_bills` | 06-x, 04-1 = reference/receipt check |
| Stock movement | `stock_ledger` | 03-1/04-x = document that *creates* the ledger line via same service |
| Production | `production_runs` | 05-1 = sheet linked to run |
| Expense/cash | `entries` 10-2 (approved) → journal | day book uses approved only |
| Payroll | `payroll_runs/payments` (app mode) OR 02-2 (paper mode) — per month switch | the other mode read-only |
| Equity | `partner_capital` | cash_move linked |
| Accounting | journal auto-posted from the above | manual journal only for true adjustments |
Services: one shared posting function per transaction type; unique `(source_type, source_id)` on every post; "covered_by" guard table; weekly reconcile report with actionable warnings.

## 6. Attendance / biometric / geofence (as built)
- Real: ZKTeco bridge (pyzk, tested vs fake server only) + USB/CSV import (ZKTeco, Hikvision, Suprema); optional staff app punch (`app_punch_on`, OFF). Shifts, grace, night, overtime (approval+cap), leave, payroll lock, duplicate guards (unique index, `att_double_punch_min`, append-only).
- **Not built:** geofence, GPS, face, selfie, WebAuthn, device binding. App punch is spoofable (any logged-in session, anywhere).
- Platform truth: WebAuthn proves the *phone owner*, not the employee; no template matching. In-browser face recognition: weak liveness, heavy on low-end Android, privacy risk — **not recommended** for payroll. Browser GPS 20–100 m, spoofable (mock apps), soft control only. iOS PWA: no background geo/sync, push only iOS 16.4+ installed. External fingerprint device = strongest path (but buddy-punch and device clock must be Dhaka time).
- Recommendation: fingerprint device = primary; app punch = fallback with per-branch geofence as a *flag* (not block), selfie photo as evidence, manager approval for out-of-zone; offline punch queue; no face-recognition.

## 7. Security / integrity / ops risks
1. **PIN login is weakest point (HIGH):** password = `${pin}-bos`, 4–6 digits, predictable staff email; lockout counted only because the *browser* calls `login_failed` (app.js:128). Direct calls to Supabase Auth bypass it; anon can also lock a known staff id. Fix: Auth hook `hook_password_verification_attempt` (owner action, already on list) + longer PIN/pepper.
2. Backup: workflow never proven on real Supabase; restore tested at 91 tables (now 146); auth users not in dump; `attendance_devices` and other `token_hash` tables silently excluded.
3. Accounting is a derived layer: unposted sources (payroll, advances, partners, 20-x, 10-x) mean books incomplete until D10 closed.
4. Server-side recomputation of form equations not enforced (forms are jsonb).
5. Public repo exposes full SQL logic in `setup-sql.html` (no secrets/costs found). Delete page when done.
6. No CI; many modules/phases without dedicated tests; nothing verified on real phone/printer/fingerprint device.
7. Single-owner dependency (SQL paste, approvals, secrets). Manual phase order; `_daybook_lines23` re-create hazard.
8. Free tier limits (UNVERIFIED in repo): DB size, inactivity pause, Actions minutes.

## 8. Target architecture / module hierarchy
Core: Auth+Roles+Grants+Rules → Master data (items, locations, parties) → **Transaction services** (sale, purchase, stock move, production, cash move, payroll, equity) each with idempotent client id + posting hook → **Ledgers** (stock_ledger, journal) → Documents layer (the 41 paper-form specs bind to a transaction, never duplicate it) → Controls (exceptions, approvals, period lock) → Reports/Owner board → Notifications/Backup/Assistant.

## 9. Roadmap (dependency-aware; effort in agent-sessions S ≈ 1 working session)
**Phase A — Foundations (mandatory)**
- A1 Read-only duplicate-detection reports D1–D4,D8 (no data change) — 1 S. Accept: reports list suspect rows, zero writes.
- A2 Source-of-truth switches + `covered_by` guards (payroll mode/month, stock form-vs-screen, 05-1 vs recipe, GRN exclusivity) — 2 S. Accept: enabling both paths is refused/warned; SQL+web tests.
- A3 Accounting auto-post sources: payroll, advances, partner_capital, 10-1/10-3 — 2 S. Accept: journal ties to day book; `je_source_uq` holds.
- A4 Day-book↔journal reconcile report + weekly exception — 1 S.
- A5 PIN hardening (Auth hook doc + stronger PIN scheme + server-checked lock) — 1 S + owner step.
- A6 Real-DB verification pass (owner pastes check SQL; backup run + restore drill; counts of tables/RLS) — 1 S + owner.
**Phase B — Business fit**
- B1 Paper Form Kit import (needs documents) → per-form check docs/forms/* — 2 S.
- B2 20-x ↔ `sales` link; 10-2 status alignment; forms retry outbox — 2 S.
- B3 Server-side recompute of key form equations — 2 S.
- B4 Bank reconciliation (manual statement paste), period/year-end close — 2 S.
**Phase C — Attendance upgrade (useful)**
- C1 Per-branch geofence flag + selfie evidence + approval for out-of-zone; offline queue — 2 S. Acceptance: flags only, no hard block; spoof limits shown to owner.
- C2 Device bridge field test with real hardware — owner + 1 S.
**Phase D — Future/optional:** reorder suggestions, wastage-reason list, QC module, online orders, SMS/WhatsApp, BI export, llm_proxy deploy, CI.
**Unnecessary now:** in-browser face recognition, multi-currency, general workflow engine, manufacturing MRP planning.

## 10. Decisions needed from owner
1. Upload/paste the **paper Form Kit + Business Guide** (or confirm the Build-commands file is the full spec).
2. Payroll: from which month is the app payroll the only record (02-2 becomes read-only)? Or stay paper?
3. Stock/production: should approved 04-2/03-1/04-3/05-1 forms post to the ledger (then stock2 screen is read-only for that action), or stay screen-first (forms are paper copy)?
4. Expense 10-2: count at *submitted* or *approved* in the day book?
5. Owner top-up/draw: record once in `partner_capital` (recommended)?
6. Accounting start date + opening balances; is a bank-statement match needed?
7. Attendance: fingerprint device primary? Geofence radius per branch; allow app punch at all?
8. OK to enable the Supabase Auth hook and change PIN scheme (staff re-set PINs)?
9. Has `backup.yml` ever run? Approve a restore drill on a spare project.
10. Confirm form 0-1 = location settings screen.

STOP: no implementation until owner approves this roadmap.
