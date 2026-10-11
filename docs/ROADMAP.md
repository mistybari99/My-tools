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
- [ ] P4 Remaining forms in batches (see list below), each audited
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
