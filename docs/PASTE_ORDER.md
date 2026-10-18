# PASTE ORDER: the Supabase SQL files, in order

This is the owner's list of every phase file in `supabase/` from phase 8 to phase 498, in the order to paste them. One line per file.

**Read first.** Nothing in this list was pasted by an agent. The owner pastes the SQL himself, after review, into the live project (CLAUDE.md, Database safety). Everything new starts OFF or blank: pasting a file adds tables, functions and settings, but no feature turns on until the owner switches it on (see `docs/GO_LIVE.md`).

## How to read the table

- **Pos.** The paste position. Paste in this order, one file at a time, and wait for "Success" before the next.
- **Phase file.** The file in `supabase/`. Files with a `_test` name are never pasted (see the list at the end).
- **Package.** The build package the file belongs to (W1-A, RPT-B4, X1 and so on). `base` is the product as it was before the packages.
- **What it does.** One line. The file's own header says what it needs ("Run AFTER ...") and what it leaves alone; read that header before a paste if you are unsure.

## Numbering of phases 479 to 498: read this

Phases 479 to 498 (the X-packages X1 to XC, the XB package and the RPT, CRM and XC work in that range) were numbered by **several builders working in parallel**. The numbers were picked to avoid clashes, not to show the build or the dependency order. So a higher number does not mean "built later", and two neighbouring numbers may not depend on each other at all.

The positions below follow the numbers, which is the order `tests/sql/ORDER.txt` uses. Each file's header lists what it needs. If a file's header says it needs another phase, paste that phase first, even if its number is higher.

## Renumbered from (paste order kept)

The parallel-builder files were renumbered in paste order so the sequence continues after phase 478. No SQL body changed; only file names, references in text files and the header comments that named their own file. Old name -> new name, with `_test` files following their main file:

| Old number | New number |
|---|---|
| 480 | 479 |
| 481 | 480 |
| 490 | 481 |
| 491 | 482 |
| 500 | 483 |
| 510 | 484 |
| 511 | 485 |
| 520 | 486 |
| 530 | 487 |
| 531 | 488 |
| 532 | 489 |
| 533 | 490 |
| 540 | 491 |
| 541 | 492 |
| 542 | 493 |
| 550 | 494 |
| 551 | 495 |
| 552 | 496 |
| 553 | 497 |
| 554 | 498 |

## Phases 491 to 493 (XB): not yet in `tests/sql/ORDER.txt`

Phases 491, 492 and 493 say "Run AFTER phase 478" in their headers, but they are missing from `tests/sql/ORDER.txt`, so the build scripts never build them. They are listed here at their numeric position (after 490, before 494). Before pasting them in the live project, the owner or a builder should add them to `tests/sql/ORDER.txt` and run the local build once.

## Never paste these

- `supabase/phase84_test_project_only.sql`, `supabase/phase84b_*` and `supabase/phase84c_*`: they are for TEST projects only and some of them wipe data. Never paste them into the live project.
- Any `*_test.sql` file: tests, not schema.
- `ALL_NEW*.sql`: full bundles for a brand-new empty project only (see `docs/SETUP.md`). Do not mix them with this list.
- `phase14_import*` and `phase30_controls*`: data and UI helper files, not schema phases.

Phases 8 to 498 have 184 files in `supabase/`. The numbers between them (for example 29 to 39, 55 to 59, 100 to 119) have no file, so no line here.

## Paste steps (short)

1. Take a backup (Home > Backup) and restore it once into a test project (see `docs/GO_LIVE.md`).
2. Paste the files in the order below, one at a time, into the Supabase SQL editor. Each file is safe to paste twice (the headers say so).
3. If a file stops with a red error, stop, copy the message and do not paste the next file.
4. After the last file (position 184), run: `select * from public._i2_state() where not present;` It must return no rows.

Positions 8 to 99 are the base and Wave 1. If the live project already has some of them, skip what is already in, but read section "Old phase files" in `docs/GO_LIVE.md` before you re-paste any old file (phases 3 to 98 put back older function text).

## The list

| Pos. | Phase file | Package | What it does |
|---|---|---|---|
| 1 | `phase8.sql` | base | Masters, settings, grants, invoice templates, saved views, favourites, discount by amount or percent |
| 2 | `phase9.sql` | base | Report engine core and the first reports that need no new data capture |
| 3 | `phase10.sql` | base | Stock ledger, purchases, supplier ledger, batches and expiry |
| 4 | `phase11.sql` | base | Audit log append-only, immutable codes, no hard deletes, server PIN lockout, failed-login log |
| 5 | `phase12.sql` | base | Items, stock and purchase finishing work (owner's handover list) |
| 6 | `phase13.sql` | base | Day book (cash, bank, mobile in and out by day), salary report 02-1 to 02-3, audited exports |
| 7 | `phase14.sql` | base | Item master |
| 8 | `phase15.sql` | base | List add-rules, Other queue, shared list control |
| 9 | `phase16.sql` | base | Locations (kind, status, hub, setup steps, pause, close) and Control Center counts |
| 10 | `phase17.sql` | base | Rollout per form and place (paper, parallel, app); paper and app together |
| 11 | `phase18.sql` | base | Server-side blind count for forms 14-1 and 10-1; PIN signatures (second signature = another login) |
| 12 | `phase19.sql` | base | Recipes and bill of materials, packaging rule, production that uses raw material |
| 13 | `phase20.sql` | base | Forms-to-stock-ledger links, sales discount approver, brand-level P&L |
| 14 | `phase21.sql` | base | 12 more reports for the Reports hub |
| 15 | `phase22.sql` | base | Bulk item editor and old-item decision tools |
| 16 | `phase23.sql` | base | Wrong-number fixes (group A) |
| 17 | `phase24.sql` | base | Report engine 3: registry of reports, one function per report |
| 18 | `phase25.sql` | base | Report builder on engine 3 (read-only) |
| 19 | `phase26.sql` | base | 13 reports on engine 3 |
| 20 | `phase27.sql` | base | Profit reports on engine 3 (L1 to L5, T3, T4) |
| 21 | `phase28.sql` | base | Parallel-month comparison, print and paper book register |
| 22 | `phase40.sql` | base | Accounting module (Module A) |
| 23 | `phase41.sql` | base | Employees: registration, pay structure, facilities, documents, roles, deeds |
| 24 | `phase42.sql` | base | Attendance, leave, automatic payroll, fingerprint device integration |
| 25 | `phase43.sql` | base | Customer registration and customer tiers |
| 26 | `phase44.sql` | base | Partnership, investment, profit-share and franchise deed engine |
| 27 | `phase45.sql` | base | Owner mode board (customisable must-check list) |
| 28 | `phase46.sql` | base | Automatic backup and notifications (in-app bell, email digest, alerts) |
| 29 | `phase47.sql` | base | Business assistant, read-only MVP |
| 30 | `phase48.sql` | base | "One record + locked shadow copy" engine and owner path switches (P1 slice 1) |
| 31 | `phase49.sql` | base | Read-only reports (P1 slice 2) |
| 32 | `phase50.sql` | base | Payroll and expense records with locked shadow copy (P1 slice 3) |
| 33 | `phase51.sql` | base | Stock issue, transfer, count; production; owner top-up and draw (P1 slice 4) |
| 34 | `phase52.sql` | base | Journal auto-post sources for payroll payments, staff advances, partner capital (P2 gap 6) |
| 35 | `phase53.sql` | base | Accounting gaps 1 to 5 on top of phase 40 (P2) |
| 36 | `phase54.sql` | base | Attendance counted once on two paths; form equation recompute (P2c) |
| 37 | `phase60.sql` | base | Reorder suggestion, wastage reasons, batch and expiry on goods receipt, QC records (P3) |
| 38 | `phase61.sql` | base | Online order channel, forms 20-1 / 20-2 / 20-4 linked to sales, benefits, BI export (P3) |
| 39 | `phase62.sql` | base | SMS and WhatsApp queue, payment-gateway intents, webhook log, reconciliation (P3) |
| 40 | `phase70.sql` | base | Restore drill record (proof that the backup can be restored) |
| 41 | `phase71.sql` | base | Two-factor login (TOTP) for staff, safe core |
| 42 | `phase72.sql` | base | One COGS source for reports, balanced inventory lines, unknown-cost warnings |
| 43 | `phase73.sql` | base | Recipe master: artisans, recipe versions with approval, steps, recipe book |
| 44 | `phase74.sql` | base | Costing and overhead (conversion cost into product cost) |
| 45 | `phase75.sql` | base | Cost sources and allocation (separate or shared bills) |
| 46 | `phase76.sql` | base | Sales channels, message inbox, web order intake, Meta message intake (pull-in only) |
| 47 | `phase77.sql` | base | Existing online-order gap fixes (audit a2-F6) |
| 48 | `phase78.sql` | base | Showroom and admin cost attribution, approval separation hint |
| 49 | `phase79.sql` | base | Integration: merged definitions of functions re-created by phases 72 to 78 |
| 50 | `phase80.sql` | base | One-step opening balance (stock, cash per place, wallets, dues, payables, capital) |
| 51 | `phase81.sql` | base | Shortages: hub count cash short, customer advance check, transit short |
| 52 | `phase82.sql` | base | Salary accrual, Monthly Close, partner profit-share posting |
| 53 | `phase83.sql` | base | Separate wallets (bKash, Nagad, Rocket, others) and production materials |
| 54 | `phase84.sql` | base | Balance check, read-only (safe for the live project) |
| 55 | `phase85.sql` | base | Integration of phases 81, 82, 83 into the shared functions |
| 56 | `phase86.sql` | base | Fixes after the independent check of phases 80 to 85 |
| 57 | `phase87.sql` | base | Money accounts |
| 58 | `phase88.sql` | W1-A | Opening dues and payables linked to customer and supplier sub-ledgers (W1-A) |
| 59 | `phase89.sql` | W1-B | Period lock, back-date window, late offline sales held for the owner (W1-B) |
| 60 | `phase90.sql` | W1-C | Staff exit revokes access (W1-C) |
| 61 | `phase91.sql` | W1-C | Sale return control: window, class rule, expired-batch rule (W1-C) |
| 62 | `phase92.sql` | W1-D | One profit number (W1-D) |
| 63 | `phase93.sql` | W1-D | Report parity and dated brand map (W1-D) |
| 64 | `phase94.sql` | W1-E | Cash and payment controls: supplier payment limit, duplicate guard (W1-E) |
| 65 | `phase95.sql` | W1-E | Journal, chart and mapping controls, journal requests (W1-E) |
| 66 | `phase96.sql` | W1-F | Chart and mapping completeness, expense heads, other income (W1-F) |
| 67 | `phase97.sql` | W1-F | Customer receipt channels: bank, cheque, payment source on collections (W1-F) |
| 68 | `phase98.sql` | W1-G | Journal freshness, switch-coupling warning, data-protection settings (W1-G) |
| 69 | `phase99.sql` | I-1 (Wave 1 integration) | Wave 1 integration: applies the Wave 1 hooks in one call (I-1) |
| 70 | `phase120.sql` | R1 | Pay requests: staff salary and advance, supplier payment, one approver (R1) |
| 71 | `phase130.sql` | R2-A | Announcements from the owner (R2-A) |
| 72 | `phase131.sql` | R2-B | To-do list with repeats (R2-B) |
| 73 | `phase132.sql` | R2-C | Shift templates and weekly roster, record only (R2-C) |
| 74 | `phase140.sql` | W1-FIX | A sale void follows the return rules (W1-FIX) |
| 75 | `phase141.sql` | W1-FIX | Supplier payment limit counted over several days (W1-FIX) |
| 76 | `phase142.sql` | W1-FIX | A staff exit cannot be undone by linking a login (W1-FIX) |
| 77 | `phase143.sql` | W1-FIX | One re-patch call for the hooks of phases 140 to 142 (W1-FIX) |
| 78 | `phase300.sql` | CRM-A | Customer profile plus: schema, settings, grants, helpers (CRM-A) |
| 79 | `phase301.sql` | CRM-A | Customer profile plus: write functions (CRM-A) |
| 80 | `phase302.sql` | CRM-A | Customer 360: read functions, timeline, upcoming dates, masked directory (CRM-A) |
| 81 | `phase303.sql` | CRM-B | Consent per channel with evidence, do-not-contact list (CRM-B) |
| 82 | `phase304.sql` | CRM-B | Privacy by role: phone numbers and lists, export control, log (CRM-B) |
| 83 | `phase305.sql` | CRM-B | Possible duplicate customers, soft "same person" link (CRM-B) |
| 84 | `phase306.sql` | CRM-C | Customer scores and RFM labels with the owner's cut-offs (CRM-C) |
| 85 | `phase307.sql` | CRM-C | Customer lists (segments): rule builder, saved lists (CRM-C) |
| 86 | `phase308.sql` | CRM-C | Customer value: repeat rate, lifetime value, lapsed and at-risk lists (CRM-C) |
| 87 | `phase316.sql` | CRM-F | Loyalty extras part 1: points expiry, burn rules, manual adjustment alert (CRM-F) |
| 88 | `phase317.sql` | CRM-F | Loyalty extras part 2: referral codes and rewards (CRM-F) |
| 89 | `phase318.sql` | CRM-F | Loyalty extras part 3: coupons and vouchers (CRM-F) |
| 90 | `phase319.sql` | CRM-F | Loyalty extras part 4: birthday and festival hooks, points statement (CRM-F) |
| 91 | `phase323.sql` | CRM-G | Enquiry and lead pipeline, tasks: settings, rights, tables, guards (CRM-G, 1 of 5) |
| 92 | `phase324.sql` | CRM-G | Leads: save, notes, assign, stage moves, lost and reopen with reason, quotes (CRM-G, 2 of 5) |
| 93 | `phase325.sql` | CRM-G | Convert a won lead to an order or party form; pipeline board (CRM-G, 3 of 5) |
| 94 | `phase326.sql` | CRM-G | Tasks: add, done, snooze, skip, reassign, my tasks (CRM-G, 4 of 5) |
| 95 | `phase327.sql` | CRM-G | Status for the screens, settings overview, go-live checklist (CRM-G, 5 of 5) |
| 96 | `phase328.sql` | CRM-H | Customer complaints with an SLA clock (CRM-H, 1 of 2) |
| 97 | `phase329.sql` | CRM-H | Ratings, repeat-complaint list, complaints and ratings report (CRM-H, 2 of 2) |
| 98 | `phase400.sql` | RPT-B1 | Returns and refund consistency in sales reports (RPT-B1) |
| 99 | `phase401.sql` | RPT-B1 | "Data not captured" notices (RPT-B1) |
| 100 | `phase402.sql` | RPT-B1 | One cost basis for item sales and business analysis (RPT-B1) |
| 101 | `phase403.sql` | RPT-B1 | Three reports a sweets and bakery business needs (RPT-B1) |
| 102 | `phase404.sql` | RPT-B4 | Production capture: tables and helpers (RPT-B4) |
| 103 | `phase405.sql` | RPT-B4 | Production capture: entry functions (RPT-B4) |
| 104 | `phase406.sql` | RPT-B4 | Plan vs actual, order status, production-to-dispatch reconciliation (RPT-B4) |
| 105 | `phase407.sql` | RPT-B4 | Real consumption vs recipe, standard vs actual cost, price, usage and yield variance (RPT-B4) |
| 106 | `phase408.sql` | RPT-B4 | Run-level yield vs standard, reject and loss, wastage with batch (RPT-B4) |
| 107 | `phase409.sql` | RPT-B4 | Sales targets and daily KPI snapshots: tables, settings, target entry (RPT-B4) |
| 108 | `phase410.sql` | RPT-B4 | Target vs achievement, KPI trends, exception alerts (RPT-B4) |
| 109 | `phase411.sql` | RPT-B4 | Outlet target tile for the owner board (RPT-B4) |
| 110 | `phase412.sql` | RPT-B4 | Rated capacity, production lines and labour hours per run (RPT-B4) |
| 111 | `phase413.sql` | RPT-B4 | Output per labour hour and capacity utilization (RPT-B4) |
| 112 | `phase415.sql` | RPT-B4 | Owner setting for the value of goods moved between units (RPT-B4) |
| 113 | `phase416.sql` | RPT-B4 | Factory vs retail report and audit line for the CSV of new reports (RPT-B4) |
| 114 | `phase420.sql` | RPT-B2 | Honesty fixes in the existing stock and purchase reports (RPT-B2) |
| 115 | `phase421.sql` | RPT-B2 | Stock movement reports on engine 3 (RPT-B2) |
| 116 | `phase422.sql` | RPT-B2 | Stock movement ledger of one item at one place (RPT-B2) |
| 117 | `phase423.sql` | RPT-B2 | Stock reconciliation and integrity, read-only (RPT-B2) |
| 118 | `phase424.sql` | RPT-B2 | Batches and freshness, read-only (RPT-B2) |
| 119 | `phase425.sql` | RPT-B2 | Where each production batch went, read-only (RPT-B2) |
| 120 | `phase430.sql` | RPT-B3 | Supplier lot and expiry captured at raw receipt (RPT-B3) |
| 121 | `phase431.sql` | RPT-B3 | Traceability and recall (RPT-B3) |
| 122 | `phase432.sql` | RPT-B3 | Quality check by item, quantity and supplier; damaged quantity on transfer (RPT-B3) |
| 123 | `phase433.sql` | RPT-B3 | Stockout log, shelf-life-not-set notice, actual yield report (RPT-B3) |
| 124 | `phase434.sql` | RPT-B3 | Price trend with value, agreed price per item and supplier (RPT-B3) |
| 125 | `phase435.sql` | RPT-B3 | Purchasing reports: supplier returns, adjustments, agreed-price variance (RPT-B3) |
| 126 | `phase436.sql` | RPT-B3 | Audit line for the CSV export of the new reports (RPT-B3) |
| 127 | `phase440.sql` | RPT-C1 | Report honesty part 1: null-safe totals, profit completeness (RPT-C1) |
| 128 | `phase441.sql` | RPT-C1 | Report honesty part 2 (RPT-C1) |
| 129 | `phase442.sql` | RPT-C1 | Expense register (RPT-C1) |
| 130 | `phase443.sql` | RPT-C1 | Statements part 1: account classes, P&L by month and outlet (RPT-C1) |
| 131 | `phase444.sql` | RPT-C1 | Statements part 2: cash-flow statement, working capital (RPT-C1) |
| 132 | `phase445.sql` | RPT-C2 | Order capture part 1: cake specification and promised time slot (RPT-C2) |
| 133 | `phase446.sql` | RPT-C2 | Order capture part 2: actual delivery cost of an app order (RPT-C2) |
| 134 | `phase447.sql` | RPT-C2 | Advance on an app order becomes a customer advance (setting OFF) (RPT-C2) |
| 135 | `phase448.sql` | RPT-C2 | Cancelling an app order with a refund makes a money record (RPT-C2) |
| 136 | `phase449.sql` | RPT-C2 | Order registers and advance or outstanding balances, read-only (RPT-C2) |
| 137 | `phase450.sql` | RPT-C2 | Delayed and undelivered orders, on-time delivery, fulfilment rate, read-only (RPT-C2) |
| 138 | `phase451.sql` | RPT-C2 | Order cancellation and refunds, delivery cost and performance, read-only (RPT-C2) |
| 139 | `phase452.sql` | RPT-C2 | Order-wise production and material cost, order profitability (RPT-C2) |
| 140 | `phase453.sql` | RPT-C2 | Customer credit risk and overdue; dues not linked to a customer notice (RPT-C2) |
| 141 | `phase454.sql` | RPT-C2 | Customer lifetime value, complaints and returns per customer, cake history (RPT-C2) |
| 142 | `phase455.sql` | RPT-C2 | Attendance summary, overtime and late variance (RPT-C2) |
| 143 | `phase456.sql` | RPT-C2 | Sales per labour hour; cashier cash variance with shift (RPT-C2) |
| 144 | `phase457.sql` | RPT-C2 | Production crew and hours per run; output per worker (RPT-C2) |
| 145 | `phase458.sql` | RPT-C3 | Campaign master list, campaign or offer code on a sale, audited export (RPT-C3) |
| 146 | `phase459.sql` | RPT-C3 | Marketing reports: spend by campaign, spend vs sales, campaign revenue (RPT-C3) |
| 147 | `phase460.sql` | RPT-C3 | Marketing reports: coupon usage, acquisition cost, repeat purchase (RPT-C3) |
| 148 | `phase461.sql` | RPT-C3 | Post marketing spend of form 18-1 to the journal, setting OFF, no double count (RPT-C3) |
| 149 | `phase462.sql` | RPT-C3 | Audit and control: audit log pager, register of voided and reversed records (RPT-C3) |
| 150 | `phase463.sql` | RPT-C3 | Audit and control: approval delays, stock adjustment approval history (RPT-C3) |
| 151 | `phase464.sql` | RPT-C3 | Audit and control: price-override approver, unusual transactions list (RPT-C3) |
| 152 | `phase465.sql` | RPT-C3 | Planning: festival calendar, sales forecast, item demand forecast (RPT-C3) |
| 153 | `phase466.sql` | RPT-C3 | Planning: production requirement, recipe-based raw material purchase forecast (RPT-C3) |
| 154 | `phase467.sql` | RPT-C3 | Planning: expected cash in and out calendar, supplier payments, expected wastage (RPT-C3) |
| 155 | `phase468.sql` | RPT-C3 | Planning: sales and profit what-if scenarios, seasonal demand (RPT-C3) |
| 156 | `phase470.sql` | RPT-HUB | Business Memory hub: saved items, date indexes, permission helpers (RPT-HUB, read-only) |
| 157 | `phase471.sql` | RPT-HUB | "What happened?" day replay (RPT-HUB) |
| 158 | `phase472.sql` | RPT-HUB | Entity timelines with running balance (RPT-HUB) |
| 159 | `phase473.sql` | RPT-HUB | "What changed" and "why did this number change" (RPT-HUB) |
| 160 | `phase474.sql` | RPT-HUB | Audit trail overlay for one record (RPT-HUB) |
| 161 | `phase475.sql` | RPT-HUB | Favourites, recent reports, saved views, Home pins, export log (RPT-HUB) |
| 162 | `phase476.sql` | RPT-HUB | Spend explorer: how much was spent on what, for whom, where (RPT-HUB) |
| 163 | `phase477.sql` | integrator | Re-patch of every package hook plus integration glue; paste after 476 (integrator) |
| 164 | `phase478.sql` | integrator | Closes the small helper functions to the signed-out role; paste after 477 (integrator) |
| 165 | `phase479.sql` | X1 | X1 foundation part 1: connection registry, job runs, one gate for outside and AI calls, agent identities (X1) |
| 166 | `phase480.sql` | X1 | X1 foundation part 2: approval queue for agent proposals, health view (X1) |
| 167 | `phase481.sql` | X2 | X2 website part 1: settings (OFF), catalogue publishing, public read functions (X2) |
| 168 | `phase482.sql` | X2 | X2 website part 2: checkout, stock holds, tracking, custom cake requests, owner admin (X2) |
| 169 | `phase483.sql` | X3 | X3 social and marketing workspace: content, approval, publishing queue, metrics (X3, OFF) |
| 170 | `phase484.sql` | X4 | X4 AI foundation: provider registry, monthly budgets, redaction, agent catalogue, call log (X4, OFF) |
| 171 | `phase485.sql` | X4 | X4 AI knowledge, suggestions, feedback, evaluation (X4, OFF) |
| 172 | `phase486.sql` | X5 | X5 item recognition foundation: duplicate check, review record, aliases, asset details (X5) |
| 173 | `phase487.sql` | X6 | X6 market intelligence foundation: settings (OFF), rights, tables (X6) |
| 174 | `phase488.sql` | X6 | X6 workspace: topics, sources, findings, competitor prices, opportunities (X6) |
| 175 | `phase489.sql` | X6 | X6 growth intelligence from own data, read-only (X6) |
| 176 | `phase490.sql` | X6 | X6 scheduled research hook (OFF), AI summariser slot, competitor price alerts, weekly digest (X6) |
| 177 | `phase491.sql` | XB | XB part 1: bKash, Nagad, Rocket payment capture and reconciliation (XB) |
| 178 | `phase492.sql` | XB | XB part 2: custom-cake workflow on top of an app order (XB) |
| 179 | `phase493.sql` | XB | XB part 3: riders, delivery status, zones, cash on delivery per rider per day (XB) |
| 180 | `phase494.sql` | XC | XC-1 owner daily summary, recipients, send log, receipt continuity (XC, OFF) |
| 181 | `phase495.sql` | XC | XC-2 daily production suggestion, baker's confirmation, accuracy report (XC, OFF) |
| 182 | `phase496.sql` | XC | XC-3 supplier price board, rise alert (threshold blank), recipe-cost preview (XC, OFF) |
| 183 | `phase497.sql` | XC | XC-4 unsold stock and markdown list, wastage share (XC, OFF, markdown % blank) |
| 184 | `phase498.sql` | XC | XC-5 owner-only staff coaching board, no rankings (XC, OFF) |

Package names: `base` = the product before the packages; W1-A to W1-G, I-1 = Wave 1 (phases 88 to 99); R1 = pay requests; R2-A to R2-C = announcements, to-do, shifts; W1-FIX = Wave 1 fixes (140 to 143); CRM-A to CRM-H = customer work; RPT-B1 to RPT-C3 and RPT-HUB = reports; integrator = the re-patch and the anon lock (477, 478); X1 to X6, XB and XC = the later packages (all OFF by default).

## Old phase files: if you ever paste one again

Old phase files (3 to 98) re-create functions, and that removes the hooks other phases added to them. If you paste any old file again, paste phase 477 afterwards (it puts every hook back and calls `public._i2_apply_all()`), then paste phase 478 again (it closes the helper functions to anon). Then run the check in step 4 above. The full rule is in the old version of this file and in `docs/GO_LIVE.md`.
