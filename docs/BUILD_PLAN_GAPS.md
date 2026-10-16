# Build plan: close gaps G1 to G14

Status: plan only. No code, SQL or database was changed to write this. Gap list: `docs/SYSTEM_UPDATE_PLAN.md`. Demo material lives in `docs/demo/` and is **not** a source of truth.
Tags: `[verified]` = read in code, file and function cited. `[not found]` = searched, absent. `[unverified]` = could not confirm (no live access, no phone, no test run).
All numbers in the demo are invented. Real numbers come only from the owner or the live database.

## 0. Key finding before any build

The gap list was written from a demo and is **partly out of date**. The code already has more than the demo assumed.

| Gap | Demo claim | What the code does [verified] | Real remaining work |
|---|---|---|---|
| G1 | Payroll and advances not in journal | `supabase/phase52.sql` adds `_acct_docs` sources `payroll_payment` and `staff_advance`; latest body in `supabase/phase79.sql` (lines about 194-215) | Cash basis only. No accrual (Cr 2200). No month-close. |
| G5 | No customer-advance journal | `phase40.sql`/`phase79.sql` `_acct_docs` cash_move kinds `cust_advance`, `cust_advance_refund`, `cust_advance_used` use mapping `cust_advance` (2300) | Tests and a report only. |
| G3 | No opening screen | `phase40.sql` `acct_opening(p_lines, p_plug, ...)`; `web/accounts.js` tab `t_opening` calls it (line about 582) | Raw account lines only. No stock, per-place cash, wallet, party structure. |
| G7 | No capital journal | `phase52.sql` source `partner_capital` (contribution Dr cash / Cr 3100 etc.) | Opening capital via G3 only. |
| G10 | Milk, chhana, packing not stock | `data/item_dictionary.csv` has Raw Material rows (e.g. Liquid Milk); `phase19.sql` `recipe_lines`, `product_packaging`; `production_post` consumes both | Make ingredients required; check costs exist. |
| G2 | Journal empty | Journal is a derived layer. Rules `accounting_on` (default OFF) and `accounting_start_date` (empty) in `phase40.sql` | Operations step, not code. Live state [unverified]; the read-only audit did not count `journal_entries`. |

Real code gaps: G4, G6, G8 (settlement), G9, G11 (one screen), G12 (verify), G13. Treat G1, G2, G3, G5, G7, G10 as "finish and test", not "build from zero".

## 1. Conventions learned from the repo

- Next SQL number: **phase80** (latest file is `supabase/phase79.sql`; one-paste bundles are `ALL_NEW11a/b/c.sql`). Before using 80+, check no other branch took the number: the header of `phase78.sql` says "phase72 is another branch" [unverified for 80+].
- Every phase file: header comment, "Additive; paste-twice safe", own tag `bosNN` on changed lines, `create table if not exists`, `create or replace function`, `insert ... on conflict do nothing`, `revoke all ... from public, anon, authenticated` then explicit `grant execute`, RLS on every new table, `log_change` audit trigger, `client_id` idempotency, new switches in `rules` default OFF.
- Journal sources are posted only through `_acct_docs` (unique `(source_type, source_id)`, `je_source_uq`). Reversal via `_acct_need`. **Hazard:** `_acct_docs` was re-created in phases 40, 50, 52, 72, 74, 79. A new phase must copy the latest body (phase79) and then add its block, or later pastes of old phases overwrite it [verified, see `phase79.sql` header]. Plan: put all new sources in **one** re-creation of `_acct_docs` per release, or add a separate scanner function that `_acct_docs` calls.
- Tests: `supabase/phaseNN_test.sql` using `tt.chk`, `tt.err`, `tt.as`, `tt.unbalanced_entries()`, `tt.jl(type, sid, code, side)` (see `phase79_test.sql`). Fresh DB: `ORDER="phase8 ... phase79 phase80" bash tests/sql/build_fresh_db.sh <db>` [not run here]. Web tests: `tests/web/<name>_test.js` with `tests/web/stub.js`.
- New screen: one `rec('<route>', '<group>', [bn, en, mix], {...})` line in `web/ia.js`, `window.BOS_PAGES.<route>`, script tag in `web/index.html`, i18n keys in 3 modes, permission via `c.own`, `c.GF.<grant>`, `c.P(...)` (rules in `docs/IA_RULES.md`, skill `bos-organise`). Never rename a route. Run `node tests/web/ia_test.js` plus nav, nav2, control, favsync, settings2.
- Rule from `docs/BUILD-RULES.md`: nothing deleted, append-only logs, no invented numbers, a blank setting blocks the form. After each task write `docs/BUILD-LOG.md`.
- `setup-sql.html` (public repo builder) is not rebuilt for phases 48+ [HANDOVER_5]. Each release needs the owner one-paste bundle `ALL_NEW12*.sql` and a rebuild of that page [unverified how it is built; builder script [not found] in this repo].
- Existing accounts [verified `phase40.sql`]: 1110 cash, 1120 bank, 1130 mobile wallets (single), 1220 staff advances, 1230 clearing, 1310/1320/1330 inventory, 2200 accrued salaries, 2300 customer advances, 3100 owner capital, 3200 partner capital, 3900 retained earnings, 5100 wastage, 5200 salaries, 5800 cash short/over. Mapping keys exist for most (`acct_mappings`); **no mapping key for 2200 [not found]**.

## 2. Gap by gap

Effort is in working days for one developer including SQL test and web test. Estimates are [unverified] guesses.

### G1 Payroll and advances to journal  (effort 3)
- **Current:** `payroll_runs`, `payroll_lines`, `payroll_payments`, `employee_advances` in `phase42.sql`. Journal on payment only (phase52/79): Dr 5200 (paid plus advance recovery), Cr cash/bank/wallet, Cr 1220 for recovery. Advance given: Dr 1220, Cr cash/bank/wallet. Run that is a locked shadow of form 02-2 posts nothing. Accrual: **[not found]**. Monthly close screen: **[not found]** (`year_closes` in phase53 is year-end only).
- **Deliverables:** `supabase/phase81.sql`.
  - Rule `payroll_accrual_on` (default OFF). When ON, run approval posts new source `payroll_accrual`: Dr 5200 Salary expense; Cr 2200 Accrued salaries (net pay); Cr 1220 Staff advances (recovery). Payment then posts Dr 2200, Cr cash/bank/wallet. Effective from the month the owner chooses; earlier months keep today's cash-basis posting.
  - New mapping `salary_accrued` -> 2200.
  - Wallet or bank source account follows the payment mode already in `payroll_payments.mode`. Owner decision Q1.
  - Web: add "accrued salary" line to `web/payroll.js` run detail; no new route.
- **Tests:** `phase81_test.sql`: run of 3 staff, hand-computed net; Dr = Cr; payment clears 2200 to 0; advance recovery reduces 1220; void run reverses; shadow 02-2 run posts nothing; pasted twice; switch OFF = phase79 behaviour unchanged. Web: extend `tests/web/payroll_test.js`.
- **Risk / rollback:** double count if both modes post. Guard with `_acct_need` and the switch. Rollback: switch OFF; entries already posted are reversed by `_acct_reverse`, never deleted.
- **Depends on:** G2 (accounting on), G3 (opening 2200 if any).

### G2 Journal filled  (effort 1)
- **Current:** journal fills only when `accounting_on` is true and `accounting_start_date` is set; `acct_post_pending` posts sources dated on or after start [verified `phase40.sql`, `phase79.sql`]. Live values [unverified].
- **Deliverables:** no new table. Add read-only `acct_readiness()` in `phase80.sql`: returns start date set, switch on, opening exists, mappings complete, count of unposted sources, `acct_post_errors72`. Show it at the top of `#/accounts` (extend `web/accounts.js`).
- **Tests:** `phase80_test.sql` readiness before and after setting start date. **Risk:** low (read only). **Depends on:** none. Owner must set the start date (Q6).

### G3 Opening Balance screen  (effort 5)
- **Current:** `acct_opening` posts one `opening` entry from raw lines, only balance-sheet accounts, dry-run supported, blocks if opening exists or postings precede it [verified]. Stock opening is separate: `stock_open`-style call at `phase10.sql` line about 526 writes `stock_ledger` reason `opening` (unique per item+place) and **no journal** [verified]. Result: inventory GL differs from stock until typed by hand (`inventory_vs_gl`, `phase72.sql`).
- **Deliverables:** `phase80.sql`:
  - `opening_balance_preview(p_json)` and `opening_balance_post(p_json, p_client)` (owner / `accounts_manage`). Input: stock lines (place, item, qty, unit cost), cash per place, wallets (see G9), customer dues, supplier dues, capital. Builds **one** balanced `opening` journal entry: Dr 1310/1320/1330 by item type, Dr 1110/1120/1130, Dr 1210, Cr 2100, Cr 3100/3200, balancing figure only to 3900 if the owner confirms. Posts stock openings through the existing opening function in the same transaction. Refuses if Dr <> Cr.
  - Table `opening_batches` (append-only trail, payload hash, who, when).
  - Web: new route `openbal`, group `acc`, label ['শুরুর ব্যালেন্স', 'Opening balance', 'Opening balance'], kw bn+en (opening, start, শুরু, জের), `ok: c.own || c.GF.accounts_manage`, file `web/openbal.js`, one `rec()` line in `web/ia.js`, script tag in `web/index.html`. `drawer:false` is not used; screen is a normal Accounts item. Old Opening tab in `accounts.js` stays.
- **Tests:** `phase80_test.sql` (dry-run writes nothing; unbalanced refused; second post refused; stock and GL equal after post; Dr = Cr; non-owner refused). Web: `tests/web/openbal_test.js`.
- **Risk / rollback:** one-time and irreversible in effect; reversal entry via `acct_journal_reverse` (supports `opening`). Stock opening rows cannot be edited (ledger append-only), so preview must be mandatory. **Depends on:** G2, G9 (wallet split), Q5 for item costs.

### G4 Hub cash short  (effort 3)
- **Current:** short/over from counts creates exception flag `cash_short_over` with `amount` in `exceptions` (read in `phase46.sql` around lines 363-369, 506). Account 5800 "Cash short / over" exists; **no mapping key and no journal source [not found]**. Hub receipt `cash_moves.kind='hub_receipt'` posts Dr 1110 / Cr 1230 [verified].
- **Deliverables:** `phase82.sql`: table `cash_short_cases` (exception id, place, date, amount signed, reason, status open/approved/rejected, approved_by, note required). Mapping `cash_short` -> 5800. Function `cash_short_decide(id, approve, note)` owner only. New source `cash_short` posts only on approve: short Dr 5800, Cr 1110; over Dr 1110, Cr 5800. Posting date = count date. Rule `cash_short_post_on` default OFF. Web: add a card to `web/ownerboard.js` or the exceptions list; no new route if possible [unverified which screen lists exceptions best].
- **Tests:** short 200 and over 50 (test numbers), unapproved posts nothing, reject posts nothing, void reverses, Dr = Cr, cash account equals counted cash after post. **Risk:** double count with a manual journal (D9 in ERP audit); add a duplicate warning. **Depends on:** G2. Owner Q2.

### G5 Customer advance  (effort 1)
- **Current:** posts as above [verified]. `acct_party_ledger` and `acct_reconcile` read mapping `cust_advance` (`phase40.sql` ~968). Using an advance in the POS as a payment mode: [unverified].
- **Deliverables:** no schema. `phase82_test.sql` block: deposit 1,000 (test): Dr cash, Cr 2300; used against a sale: Dr 2300, Cr 1210; refund: Dr 2300, Cr cash; balance sheet shows 2300 as liability. Add to `acct_reconcile` note if mismatch. Document in `docs/MODULE_MAP.md` only if wanted.
- **Risk:** low. **Depends on:** G2.

### G6 Transit short  (effort 4)
- **Current:** `stock_receive_transfer` (`phase10.sql` ~699) posts `transfer_in` for the received qty only and raises exception `transit_short` (yellow). The short qty stays out of both places; there is no claim, write-off or status [verified]. Transfers post no journal [no stock_transfer source in `_acct_docs`], so GL inventory stays higher than stock until decided. Ledger reason list is a check constraint (`phase10.sql` line 94) [later phases may extend it, verify at build].
- **Deliverables:** `phase82.sql`: table `transit_shortages` (transfer id unique, item, qty_short, unit_cost from the `transfer_out` row, status open/claimed/recovered/written_off, decided_by, note). Trigger or call in receive creates the row. New account 1240 "Receivable from carrier" (check code free) and mapping `carrier_claim`. Functions `transit_short_claim`, `_recover`, `_writeoff` (owner only, note required). Journal: claim Dr 1240, Cr inventory (by item type); recover Dr cash, Cr 1240; write-off Dr 5100, Cr inventory (or Dr 5100, Cr 1240 after a claim). Web: new tab inside `web/stock2.js` Transit view (no route), or route `transitshort` if too large.
- **Tests:** send 10, receive 9: row open with qty 1; claim then recover; write-off; Dr = Cr; stock identity per place unchanged; cannot decide twice; non-owner refused.
- **Risk:** value uses cost at send; unknown cost = 0, show "cost missing", do not post. **Depends on:** G2; Q3 who bears the loss.

### G7 Owner capital and opening  (effort 1, mostly in G3)
- **Current:** capital contributions post (phase52) [verified]. Opening capital via `acct_opening`.
- **Deliverables:** capital lines in the G3 payload (Cr 3100 or 3200). Test that a later top-up posts once (`owner_money_link`, phase51/52 count-once). **Depends on:** G3.

### G8 Partner capital and profit share  (effort 5)
- **Current:** `partner_parties`, `partner_agreements`, `partner_capital`, `partner_settlements`, `partner_settlement_lines`, `partner_settlement_payments` (`phase44.sql`); `partner_calculate`, `partner_settlement_save/approve/pay`, `partner_party_statement`; web `web/partners.js`, route `partners`, owner only [verified]. Capital posts to the journal. **Settlement approval and payment post nothing [not found in `_acct_docs`]**.
- **Deliverables:** `phase83.sql`: sources `partner_settlement` (on approve: Dr 3900 or current-year profit appropriation, Cr new liability 2600 "Partner profit payable") and `partner_settlement_pay` (Dr 2600, Cr cash/bank/wallet). Mapping `partner_payable`. Per-partner share report in `partners.js` statement. Share percentages come only from agreements (no invented numbers).
- **Tests:** two partners 60/40 test split, Dr = Cr, paid in two parts, void reverses, share sum equals profit. **Risk:** legal terms (Q4). **Depends on:** G2, G11 (profit figure), G1 (salary in profit).

### G9 Wallets bKash / Nagad / Rocket  (effort 4)
- **Current:** one account 1130; `sale_payments` and `supplier_payments` have free-text `wallet` (up to 30 chars) [verified `phase6.sql`, `phase10.sql`]; option list `wallets` in `web/lists.js`; forms have bKash/Nagad fields (`web/forms.js`, `forms_cash.js`). Journal pays `pay_mobile` -> 1130 for all wallets. Per-wallet account or phone reconcile: **[not found]**.
- **Deliverables:** `phase84.sql`: table `wallet_accounts` (code, name_bn/en, coa_account_id, fee mapping, active); child accounts 1131 bKash, 1132 Nagad, 1133 Rocket under 1130; resolve `wallet` text to an account in `_acct_paykey` path (fallback 1130 when unknown, so nothing is lost). Fee: Dr new expense 5815 "Wallet fees", Cr wallet (Q1/fee policy). Digital reconcile (form 10-3): `wallet_reconcile(date, loc)` compares phone total typed by staff with journal balance. Web: extend `web/cashmoves.js` or `web/finance2.js` bank tab; route only if needed.
- **Tests:** three wallet sales (test numbers) land on three accounts; unknown wallet lands on 1130; fee Dr = Cr; reconcile shows difference. **Risk:** history before the change stays on 1130 (move by journal if the owner wants). **Depends on:** G3 (opening per wallet).

### G10 Milk, chhana, packing as stock  (effort 2)
- **Current:** items from the dictionary import (Raw Material 149, Packaging 94 rows per `docs/DRYRUN_item_master.md`); live item count 1,369 [audit]. `recipe_lines` ingredients; `recipe_waste_required` default OFF; `product_packaging`; `production_post` consumes ingredients and packaging in one transaction; conversion cost in `recipe_cost_components` (`phase74.sql`) [verified]. Ingredient-required rule: **[not found]**.
- **Deliverables:** `phase85.sql`: rule `recipe_ingredients_required` (default OFF): recipe activation refused with no ingredient lines; report `recipe_cost_gaps()` listing ingredients with no cost. Data work (no SQL): owner opening stock and prices through G3 and purchase bills (Q5).
- **Tests:** activate empty recipe refused when ON; cost gap report lists a zero-cost ingredient; production cost equals sum of ingredients + packaging + conversion. **Depends on:** G3.

### G11 Balance check  (effort 2)
- **Current:** `acct_balance_sheet` returns `unbalanced` and `difference` (`phase40.sql` ~860-864); `inventory_vs_gl` (`phase72.sql`); `daybook_vs_journal` (phase49/52); `eqcheck` route is form-total re-check, not the balance sheet [verified]. A dedicated Balance Check page: **[not found]**.
- **Deliverables:** `phase86.sql`: `balance_check(p_date, p_loc)` returns assets, liabilities, equity, earnings, difference, plus reasons: unposted sources, `acct_post_errors72`, inventory vs GL, unbalanced entries (always 0), orphans. Web: red/green banner at top of `#/accounts` and `#/finance2`; no new route. The demo difference (20,756) is invented; do not use it as a target.
- **Tests:** balanced = 0; forced unbalanced fixture is impossible (journal trigger) so test the difference path with a missing source; negative tests below. **Depends on:** G1, G2, G3.

### G12 Salary not in daily profit  (effort 2)
- **Current:** day book shows salary as an out line (`phase13.sql`, `phase42.sql` ~349, hidden without `salary_view`) [verified]; `_p27_pl` includes salary from the form (phase50/79) [verified by tag list]. Whether daily sheet profit (`biz_daily`) includes salary: [unverified].
- **Deliverables:** rule `salary_in_daily_off` (default OFF) so the daily/day-book profit excludes salary and the monthly close carries it; read `biz_daily` first and decide the smallest change. Monthly Close tab (G1 accrual makes monthly cost). **Depends on:** G1; Q1.

### G13 Demo reset (test project only)  (effort 2)
- **Current:** no reset function [not found]. Ledgers are append-only with truncate triggers (`stock_ledger`, `audit_log`) by design.
- **Deliverables:** do **not** add a reset function to the app database. Safer: `tools/reset_test_project.md` (steps to recreate a scratch Supabase project from `schema.sql` + phases, using `tests/sql/build_fresh_db.sh`). Any script must refuse unless an env flag names a test project URL, and must never read the live `SUPABASE_URL` secret. Owner confirmation required. **Risk:** a reset run against live would destroy records. Hence no SQL reset in `supabase/`.

### G14 Demo files and branch  (effort 0.5, done in this change)
- Demo docs moved to `docs/demo/` with `git mv`; `docs/demo/README.md` added; guard `tools/check_no_demo_leak.py`. Branch clean-up (deleting old branches) needs owner approval; nothing deleted.

## 3. Dependencies

`G2 -> G3 -> (G7, G9, G10) ; G2 -> G1 -> G12 ; G2 -> G4, G5, G6 ; (G1, G3) -> G11 ; (G1, G11) -> G8 ; G13, G14 independent.`

## 4. Recommended order and phases

| Release | SQL | Gaps | Days | Gate |
|---|---|---|---|---|
| R0 | none | Owner answers Q1-Q6; test project ready | 1 | Written yes |
| R1 | phase80 | G2 readiness, G3 opening, G7 | 6 | Test project: opening balanced |
| R2 | phase81 | G1 accrual, G12 | 5 | Payroll Dr = Cr |
| R3 | phase82 | G4, G5 tests, G6 | 8 | Cash and transit negative tests |
| R4 | phase84 | G9 wallets | 4 | Wallet reconcile |
| R5 | phase85 | G10 | 2 | Cost gap report |
| R6 | phase83 | G8 partners | 5 | Profit share ties to profit |
| R7 | phase86 | G11 balance check | 2 | Difference 0 with real postings |
| R8 | none | G13 test reset doc, full demo in test project | 2 | Report |
Total about 35 days [unverified]. Phase numbers follow release order only if filenames are chosen when built; keep numbers unique and increasing.

## 5. Definition of done (per release)

1. Every journal entry: sum Dr = sum Cr (`tt.unbalanced_entries() = 0`).
2. Balance sheet: assets = liabilities + equity + current earnings (`acct_balance_sheet.unbalanced = false`).
3. Stock ledger identity per place and item: opening + in - out = closing; `inventory_vs_gl` difference explained.
4. Negative tests: unauthorized role refused; unbalanced refused; second post refused; void reverses; blank setting blocks; paste file twice with no error; switch OFF equals previous behaviour.
5. SQL test passes on a fresh DB built through the new phase; older suites unchanged (known baseline fails: 10 T12, 21, 22; phase47 two asserts [HANDOVER_5]).
6. Web: `ia_test`, nav, nav2, control, favsync, settings2 pass; new screen has 3-language labels.
7. `docs/BUILD-LOG.md` updated with what was not confirmed. Live database written only after the owner's written yes, one phase at a time.

## 6. Never let demo data in

- Files in `docs/demo/` are fiction (invented names such as the roster, invented amounts). They are not seed data and not tests of record.
- Never import, bundle, serve, seed or paste any demo file, name or number into `web/`, `supabase/`, `data/`, `tools/` or any database, live or test.
- Real paths by which `docs/` could reach the app [verified]: `tools/build_kb.py` reads chosen docs files (`BUILD-LOG.md`, `TODO.md`, `HANDOVER_2.md`, `DEVICE_CHECKLIST.md`, `plan_v2/*.md`, `regs/*.md`) into `web/data/kb.json`, which the app ships. Demo files are not on that list. `web/*.js` comments mention `docs/` paths only as text. No workflow, Pages or deploy config for `docs/` was found.
- Guard: `python3 tools/check_no_demo_leak.py` (run before every commit; add to any future CI). Never add a glob over `docs/*.md` or `docs/demo` to `build_kb.py`.
- Test data in SQL tests uses neutral ids and no person names. Demo staff accounts are created only in a test project.
- Live database stays read-only until the owner approves a specific phase in writing.

## 7. Owner decisions still needed (from SYSTEM_UPDATE_PLAN section 4)

| # | Question | Blocks |
|---|---|---|
| Q1 | Salary is paid from cash, bKash or bank? (and wallet fee policy) | G1, G9, G12 |
| Q2 | Cash short is a monthly cost or daily? | G4 |
| Q3 | Who bears carrier short: carrier or shop? | G6 |
| Q4 | When is the partner profit share paid? Contract terms | G8 |
| Q5 | Price of milk and packing: purchase bill or fixed value? | G3, G10 |
| Q6 | Which phase may be applied to the live database, and the accounting start date | all |
| Q7 | Approve deleting or archiving old branches (G14) | G14 |

---

## Owner approval modes (owner request, new item G15)

The owner wants one setting with four modes, switchable at any time to fit the situation:

| Mode | Behaviour |
|---|---|
| Approver | Owner's own entries need approval from a named person (for example Management) |
| Self-approve | Owner approves own entries |
| Logged | Owner's entries are always shown in the log, with who approved and how |
| Off | The control is switched off; the owner decides when to turn it on again |

Status: only the `owner_self_approve` switch is confirmed in code (ON by default). The named-approver choice, the always-log display and an off switch are [unverified] and must be checked in code before building.

Rules for the build: every change of this setting is itself written to the audit log with who changed it and when; the setting is owner-only; the log display works in every mode; a test must prove that "Approver" mode blocks owner self-approval and "Self-approve" mode allows it. Owner decision needed: which person or role is the default approver.


## Build status (R1 + G15, phase80)

| Gap | Status | Tests |
|---|---|---|
| G2 readiness (`acct_readiness`) | not built (opening path only) | none |
| G3 opening balance | done in SQL (`opening_balance_post`, stock + cash + wallet + dues + payables + capital in one balanced entry); web is a JSON box in the Opening tab, so partly | phase80_test 42 pass / 0 fail; accounts_test 0 failures |
| G7 owner and partner capital in opening | done (capital section 3100 / 3200) | in phase80_test |
| G15 owner approval modes | done in SQL (four modes, audit, log); named mode enforced on entries and entry change requests only; no web screen yet, so partly | in phase80_test |
Open: default approver role is blank (owner decision); wallet split waits for G9.
