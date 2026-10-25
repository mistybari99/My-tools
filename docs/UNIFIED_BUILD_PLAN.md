# Unified build plan

Status: plan only. No code, SQL or database was changed to write this. Live Supabase was never touched.
Base: the current working branch (read-only audit line), latest SQL file `supabase/phase87.sql` (money accounts).
Tags: `[verified]` = read in code or in a repo document. `[unverified]` = could not be confirmed (no live database, no phone, no test run, or an owner fact). All effort numbers are working days for one developer, including SQL test and web test, and are `[unverified]` estimates.
No fictional or demo document was used. Every default below is the default in code or a proposal that the owner must confirm. No number is invented: a limit that only the owner can state is shown as "blank = off".

## 0. Sources and how to read this plan

| Source | What it is | Where |
|---|---|---|
| Audit A (accounting, 33 findings) | IDs A-01 to A-33 | working paper, outside the repo |
| Audit B (operations, 37 findings) | IDs B-01 to B-37 | working paper, outside the repo |
| Audit C (usability and IA, 46 findings, 101-route map) | IDs C-01 to C-46, quick wins Q1-Q17, bigger changes B1-B12 (here written "C-B1" to avoid a clash with auditor B) | working paper, outside the repo |
| Audit D (compact screen design, 25 screens) | patterns P1-P16, safety rules S1-S9 | working paper, outside the repo |
| Debate responses A and B | severity changes, merged top-25 lists | working papers, outside the repo |
| `docs/FORM_LEDGER_LINKAGE_AUDIT.md` | gaps G16-G33 | in the repo |
| `docs/BUILD_PLAN_GAPS.md`, `docs/BUILD-LOG.md`, `docs/integration/*.md` | gaps G1-G15, what phases 80-87 built | in the repo |

The working papers are not in the repo. Their IDs are kept here as a trace. Every item below is written so it can be built without opening them.

Id clash [verified]: `docs/BUILD_PLAN_GAPS.md` uses the id G16 for "Money accounts" (phase87). `docs/FORM_LEDGER_LINKAGE_AUDIT.md` uses G16 for "reports blind to app payroll". In this plan `G16` always means the audit gap. Phase87 is written `M87`. The integrator should rename one of them in the docs.

Owner's standing rules, applied to every item:
1. Every control is a SETTING with a safe default. A blank number means off or "data needed", never an invented value.
2. An exception is always possible. It needs a written reason, one `audit_log` line (who, when, from, to, reason) and a row in the Exceptions list.
3. Nothing the owner needs is missing. Parked work stays in the plan with its own gate.
4. The approver of the owner's own entries is never hard-coded. It is any role or any named user, changeable at any time. Phase87 already builds this (`owner_approval_mode_set2`, `entry_approver_set`) [verified]. No item below may fix an approver.

## 1. One-page summary

### 1.1 What the audits found

| Audit | Findings | Severity split | Effort they quote |
|---|---|---|---|
| A accounting | 33 | 3 critical, 20 major, 10 minor | about 135 days for the agreed top 25 |
| B operations | 37 | 6 critical, 19 major, 12 minor | 135-150 days before trimming |
| C usability | 46 | 11 high, 30 medium, 5 low; 17 quick wins (under 1 day each); 12 bigger changes (1 to 10 days each) | no total stated |
| D compact design | 25 screens measured (longest: daily showroom sheet 14-1 at 12.5 phone screens), 16 patterns | n/a | 33.1 days (+2.5 optional) |
| Form-to-ledger audit | 79 rows: 20 linked, 41 partial, 12 register only, 6 paper only; 18 new gaps G16-G33 | n/a | about 49 days |
| Debate | A dropped or downgraded 7 of its own; B downgraded 8, dropped 4, merged 2 | critical list shrank to 4 or 5 | merged lists of 25 each, about 125-135 days each |

After removing duplicates this plan has 54 items: 4 critical, 3 "major+" (top of major, built early), 41 major (four of them gated by an owner or adviser answer), 6 minor. Total work is about 350 days plus about 35 days of integration reserve [unverified].

### 1.2 Already fixed by phases 80-87 [verified from BUILD_PLAN_GAPS and BUILD-LOG]

All new behaviour in these phases is OFF or safe by default. Live state of every switch is `[unverified]`.

| Phase | What it fixed | Still open from it |
|---|---|---|
| 80 | G3 opening balance in one balanced journal entry (stock, cash, wallets, customer dues, supplier dues, capital); G7; G15 owner approval modes | The operational sub-ledgers do not read the opening (A-02, U-01). Web is a JSON box. |
| 81 | G4 cash short/over cases (posting OFF); G5 customer advance tests; G6 transit short claim, recover, write-off | Showroom half of handover (G19); transfers still post nothing |
| 82 | G1 payroll accrual (OFF); G8 partner settlement posting (OFF); G12 daily profit without salary; Monthly Close screen | Close checks payroll only and locks nothing (A-04, U-14) |
| 83 | G9 wallets with fees and blind 10-3 reconcile; G10 recipe material gate (OFF) | Wallet opening is register only (m10) |
| 84 | G11 read-only Balance Check; G13 test reset (test projects only) | Banner on Accounts not done |
| 85 | Integration hooks into `_acct_docs`, `_p27_pl`, `_daybook_lines` | Re-pasting an older phase removes hooks |
| 86 | Fixes M1-M4, m5, m8 after the independent check; wallet split behind a switch | m6 (named approver narrows only entries and entry change requests), m9, m10 |
| 87 | Money accounts: registry of cash drawers, wallets, bank accounts; payment source chosen per payment on 14 event types; transfers with fee; charges and interest; statements; negative-balance policy; one-off owner exceptions; approver by role, named user or per entry | See table 1.3 |

### 1.3 What phase87 already answers, and what is left

| Audit item | Answered by phase87 | Left over | Goes to |
|---|---|---|---|
| A-06 negative cash | Per-account `neg_policy` warn, block or allow; one-off exception | Who may record owner draw or top-up; bank slip; amount limit | U-07 |
| A-14 card receivable | A card payment can be tied to a bank money account; transfer with fee moves money between accounts | Account 1140 is not a money account; sale receipts were not given a picker; no settlement event | U-10, U-20 |
| A-15 bank receipts | Not answered (sale receipts and collections unchanged) | `sale_payments.mode` still cash, mobile or card | U-10 |
| A-16 many bank accounts | Registry, picker on 14 payment events, statements, charges and interest, real-balance check | Cheque and post-dated cheque register (explicitly not built); formal reconciliation statement; picker on customer receipts | U-10, U-52 |
| A-12 bank charges | `money_charge_add` now uses 5810 | Rent, utilities, marketing, other income | U-09 |
| A-17 cash flow | `acct_cash_flow` counts money accounts as cash, bank and mobile | Legacy wallet accounts 1131-1134 `[unverified]`; no operating, investing, financing split | U-09, U-52 |
| A-03 owner bypass | One-off exception grant for a non-owner in a closed period | `lock_check` still returns at once for the owner [verified, `phase6.sql`]; posting still depends on the caller | U-02 |
| B-06 courier cash on delivery | Not answered | No courier or platform receivable | U-20 |
| Owner approver rule | Done (role, named users, per entry) | m6 | U-24 |

### 1.4 What remains

| Area | Remaining |
|---|---|
| Money and control (Wave 1) | Opening dues cannot be collected; period lock is optional and the owner bypass is silent; leavers keep login; spoiled returns restock; two different profits; owner-money entries and supplier payments are weakly controlled; rent and utilities have no accounts; journal fills only when someone opens Accounts; cost column in a seed file |
| Daily operations (Wave 2) | No business-day state; month close checks payroll only; stock movements and transfers do not reach the books; no daily count; POS cannot start offline; custom cake orders; courier cash; price lists; alerts depend on one cron; food-safety and compliance registers; exit clearance; 14-1 not compared with POS; paper registers not posted |
| Usability (Wave 3) | Home is 4.5 screens; 11 roles but 7 personas; settings spread over 10+ screens; 46 browser prompts; 13 categories; 14-1 is 12.5 screens; presets and a first-run checklist do not exist |
| Tax, entities, advanced (Wave 4) | VAT, withholding tax, payroll liabilities, legal entities, cheque register, valuation and reporting extras. Gated by an adviser letter and owner answers (section 5) |

## 2. Unified ranked backlog (54 items)

Ranking rule: severity after the debate, then cost of delay, then dependencies, then effort. Within a wave the order is the build order.

Legend.
- Sev: critical, major+ (top of major, built first), major, minor.
- Risk: L low, M medium, H high (hot path or changes numbers owners already read).
- Owner decision: OD-n points to section 5. N = none.
- Tests: the item-specific negative or behaviour tests. Every item also needs the generic tests of section 6 (balance, default safe, paste twice, phase order, web, demo-leak).
- Phase numbers are proposals. Waves 1 to 4 use ranges 88-99, 100-169, 170-179 and 180-249. Zero-padding is not needed, the fresh-database script takes an explicit `ORDER` list [verified, `tests/sql/build_fresh_db.sh`]; any glob that sorts file names must be checked first [unverified].
- Helper function prefixes: each package uses its own prefix (`_u01_`, `_u02_` ...) so two packages never define the same name.
- Settings named below are proposals. The default is shown in brackets.

### 2.1 Wave 1: money and control holes that cost money now (12 items, 42 days)

| ID | Title (source IDs) | Sev | Why a real business needs it | What to build (phase, tables and functions, screen) | Depends | Days | Risk | Owner decision | Tests |
|---|---|---|---|---|---|---|---|---|---|
| U-01 | Opening dues and payables linked to the sub-ledgers (A-02; debate A Q2, B Q2; G3 other half) | critical | A customer who owed money before go-live cannot be collected: `collect_payment` raises `overpaid`; the POS credit limit ignores the old due; supplier opening is typed twice | phase88: `customers.opening_balance` and `opening_date` read by `_cust_bal` and by the credit check; `opening_balance_post` also sets supplier and customer openings in the same transaction; freeze both after the opening batch (later change = approved adjustment journal with reason); `party_gl_gate()` per party (sub-ledger equals GL, uses `acct_reconcile`); screen `#/openparties` (list, paste import, difference column) | G3 (done) | 4 | M: patches a phase80 function | OD-16 (source list of old dues, data) | Customer with opening 500: collect 500 ok, 600 `overpaid`; credit limit counts opening; second opening post refused; edit after freeze refused, allowed with reason and audit line; gate shows a differing party; supplier `overpaid` guard uses the same figure |
| U-02 | Period integrity: pure-date lock, owner override with reason, back-date window, no silent re-dating (A-03, A-31, B-04d, B-36; C-21 date wording) | critical | A lock that is blank by default and bypassed silently is not a close. A sale older than 72 h is silently re-dated to today. A cash move can be dated back to year 2000 | phase89: `lock_check` becomes a pure date test; `_acct_locked` no longer depends on who opens the page (a document is in or out of a closed month the same way for every user); owner is no longer silent: setting `owner_closed_period_mode` (reason [default], log, off) with `period_override_start(reason, from, to, minutes)` reusing phase87 `money_exception_grants` and `money_exceptions`; `backdate_max_days_<doc type>` for purchase bill date, cash move, expense, production `made_at` (blank = off; over the limit needs approver or reason); `auto_lock_day` (blank = off); `late_sale_policy` (park [default] or redate): a sale older than `pos_offline_hours` becomes exception `late_sale_held`; block moving `accounting_start_date` after an opening batch; backlog preview and reason when `accounting_on` is switched ON after OFF; lock date cannot move backward after a year close without a reopen reason; screen `#/periodlock` (state, override log, rules) | none | 5 | H: `lock_check` and `record_sale2` are hot paths | OD-5, OD-7 | Owner edit in a locked month without reason refused (mode reason); with reason allowed and one audit line and one red exception; non-owner refused; same document posts or skips identically for owner and accountant; sale 80 h old parked not re-dated; backdate over limit refused or needs reason; lock date backward after year close refused; mode off = old behaviour |
| U-03 | Staff exit revokes login, grants and device tokens (B-02) | critical | A dismissed cashier keeps POS, refund, stock write-off and cash-move access until someone remembers a second screen | phase90: `employee_status_set` (hooked) sets linked `profiles.status` to disabled, ends `user_grants`, deactivates the `attendance_devices` token, writes one audit row; red exception `exit_access_open` when a linked profile is still active after N hours (setting, blank = off); re-hire reverses the disable (grants are not restored automatically); setting `exit_revoke_mode` (auto [default], alert only, off) and `exit_revoke_statuses`; the owner may keep access for one person with a reason (audit line) | none | 1.5 | L | OD-11 | Resign: profile disabled, grants ended, device inactive; re-hire re-enables login only; keep-access without reason refused; alert mode disables nothing but raises the exception; non-owner HR cannot keep access |
| U-04 | Sale return control: restock choice, window, receipt, automatic write-off (B-03; A-18f in part) | major+ | A returned sweet or cake goes straight back to sellable stock on its batch and FEFO sells it again; a receipt of any age is accepted. Food-safety exposure and hidden wastage. The timing effect on profit is temporary, so major, but it is cheap and has no dependency | phase91: `sale_return(... p_restock_lines jsonb)`; `return_no_restock_classes` (default: perishable item classes, owner confirms the list); non-restock quantity goes to `stock_wastage` with reason `customer_return` (journal 5100 through the existing wastage source); `return_window_hours` per item class (blank = off); `return_needs_receipt` (off); override with grant `return_restock` or a reason and audit line; `web/returnrules.js` (settings and report "returns by reason: restocked or written off"); the picker is wired into `salereturn.js` by the integrator | none | 3 | M | OD-6 | Perishable return not restocked, wastage row and journal 5100 balanced; non-perishable restocks; expired batch cannot be restocked; window exceeded needs grant or reason; window blank = old behaviour; restock without grant refused |
| U-05 | One profit number (A-01; FORM_LEDGER D4; debate decision 3.1) | critical | Branch ranking, the owner board and partner payout use a P&L that leaves out wastage, count shrinkage, transit loss, cash short and bill-paid operating cost, and counts factory overhead twice when conversion costing is ON | phase92: add rows to the management P&L by text patch of `_p27_pl`: wastage, `count_adjust`, transit loss (phase81 cases), cash short (phase81), supplier-bill opex, minus absorbed overhead; one function feeds L1, L3, L5, the owner board, `partner_calculate` and `c_partner_month_split`; every settlement stores its basis; setting `profit_source` (management [default] or ledger); report `profit_recon(month)` "management versus ledger, difference by cause"; screen `#/profitcheck` | U-06 (same package), phase87 patch order; U-11 before choosing ledger | 5 | H: changes figures owners already read; partner disputes | OD-8 | Fixture with wastage 100, count loss 50, cash short 20: branch profit falls by 170; absorbed overhead not counted twice; partner preview equals settlement; snapshot diff lists only the new rows; recon difference fully explained by named causes |
| U-06 | Report parity and dated brand map (G16, G21, G12 rest, A-21 lean) | major | Salary and expense totals differ between day book, P&L, expense report and journal; changing the brand map rewrites history | phase93: patch `_p27_pl` salary rows to read app payroll runs (not a shadow of a 02-2 sheet) as primary with the form as fallback; `expense_by_head` and E3 add quick expenses and drop shadows; setting `expense_count_on` (approved [default] or submitted) used by day book, P&L and journal; `report_brand_map` gets `valid_from` and `valid_to`; brand P&L reads the map as of each date | U-05 | 5.5 | M | OD-8 | Salary counted once with form and run both present; day book, P&L and expense report show one total for a fixture day; changing the brand map leaves old months unchanged |
| U-07 | Cash and payment controls, lean (A-06, A-07, A-08 lite; debate Q3, Q9) | major+ | Theft can be booked as "owner drawing"; duplicate supplier payments; two "employees" paid to one account | phase94: `owner_money_entry_mode` (owner only [default], approval, open) for `owner_draw`, `owner_topup`, partner capital by a non-owner; approval by the approver chosen under phase87 (any role or user); `bank_slip_required` (on) for `bank_deposit` and `bank_withdraw`, yellow exception for large or back-dated (limit blank = off); negative cash stays with phase87 `neg_policy`; `pay_supplier`: exception `duplicate_payment`, rule `supplier_pay_over` (blank = off) sends the payment to the approver; supplier opening frozen after go-live (with U-01); duplicate-vendor warning (name, mobile, TIN); unique employee pay account (warn or block) with a red exception on change; `purchase_separate_poster` ON for non-owner; add 6-8 pairs to `grant_separation_pairs` (cash move with day-close approve, supplier pay with purchase enter, payroll with employee manage, accounts manage with purchase) and show them on `#/delegation`; screen `web/moneycontrols.js` | U-01; phase87 | 5.5 | M | OD-9, OD-10 | Branch user owner draw is pending and not posted; approver of any role or user approves; maker equals approver refused; duplicate payment flagged; payment over threshold waits; duplicate pay account refused in block mode; mode open allowed with audit line |
| U-08 | Journal, chart and mapping controls, lean (A-05; debate J-24) | major | Manual journals move profit between periods or hide a shortage; a branch accountant can post company-wide; a mapping can point to the wrong account type | phase95: `can_loc` check on every line in `acct_journal_post` and `_acct_resolve`; type guard in `acct_mapping_set`; attachment required above `journal_attach_over` (blank = off); non-owner journals touching cash, bank, receivable, payable or inventory control accounts create a release request (`journal_control_acct_mode`: request [default], allow, block); each override has reason and audit line | none | 2 | L | N | Branch-scoped accountant posting to another branch refused; sales key mapped to an expense account refused; control-account journal waits; owner override with reason works |
| U-09 | Chart and mapping completeness, expense heads, other income (A-12; A-17 bug; accounts needed by B-06 and B-25) | major | Rent, electricity and marketing disappear into "other expenses"; scrap, old oil, rent received and supplier discounts have no event; no account for courier cash or staff deposits | phase96: seed accounts and mapping keys: `exp_rent`, `exp_utilities`, `exp_marketing`, `other_income`, courier receivable 1250, staff deposit liability, purchase discount, rounding, bad debt, asset disposal gain or loss, VAT and withholding payable placeholders (inactive); widen the `expense_heads` list (owner confirms the list); entry `#/otherincome` (head, mode, money account picker, photo; Dr cash or bank or wallet, Cr 4900); check that `acct_cash_flow` includes legacy wallets 1131-1134 and money accounts `[unverified]`; mapping coverage line in Balance Check | none | 3.5 | L | OD-16 | Rent head posts to its own account; other income balanced; unmapped key shows in coverage check; cash flow closing cash equals sum of cash, bank and wallet accounts |
| U-10 | Customer receipt channels: bank and cheque reference (A-15; A-16 picker; debate Q5) | major | Hotels, offices and party customers pay by bank transfer or cheque. Staff must book them as card or mobile, which misstates bank and wallets | phase97: `sale_payments.mode` accepts bank (cheque = bank with `cheque_no` reference); money account picker (`BOS.moneySrc`) on collections and POS split payments through a new event type in `money_event_settings`; `_acct_paykey` and the day book map to the chosen money account; reference mandatory by setting | phase87 | 2 | M: POS file is shared | OD-2 | Bank collection posts Dr bank account, Cr receivable; reference mandatory when set; old rows unchanged; wallet reconcile unaffected |
| U-11 | Journal freshness and switch-coupling warning (G30, A-29, G33) | major | The books fill only when an authorised user opens Accounts. Turning on `forms_post_to_ledger` locks four stock screens with no warning | phase98: `acct_post_scheduled` with a watermark per source type and a cap per run, called by the existing notify workflow or by pg_cron if the plan allows `[unverified]`; strip "last posted at" on Home and Accounts; read function `acct_readiness()` planned as G2 (start date set, switch on, opening exists, mappings complete, unposted count, posting errors); `switch_coupling_warning(key)` text and confirm on `#/ledgerlinks` and `#/paths` (`web/freshness.js`) | G2 | 2.5 | M | OD-14 | New sale appears in the journal with nobody opening Accounts; poster is idempotent; warning shown before the switch is saved; switch off = old behaviour |
| U-12 | Data protection: cost column in seed file, backup encryption, retention, restore drill (A-27; debate Q8) | major (minor if the repo copy is private) | `data/items_seed.csv` carries a cost price for 57 items although the rule says costs never sit in the public copy `[verified in the file by both auditors; repo visibility unverified]`. The nightly dump holds NID and bank numbers in plain text | No SQL. Remove `cost_price` from the seed file and from history with `tools/make_clean_branch.sh` and `docs/HISTORY_CLEANUP_RUNBOOK.md`; client-side encryption of the dump with an owner-held passphrase in `tools/backup_dump.py` (setting, OFF until the owner holds the key); owner states the retention period in a document; quarterly restore drill on a scratch project with the result logged; note that Auth users are not in the dump | none | 2.5 | M: history rewrite | OD-15 | Seed file has no cost column; `check_no_demo_leak.py` OK; encrypted dump restores with the key and fails without; `tools/test_restore_drill.py` passes |

### 2.2 Wave 2: daily operations (21 items, 137 days)

| ID | Title (source IDs) | Sev | Why a real business needs it | What to build (phase, tables and functions, screen) | Depends | Days | Risk | Owner decision | Tests |
|---|---|---|---|---|---|---|---|---|---|
| U-13 | Business-day state and closed-day gate (B-01; A-03c; debate Q1) | major+ | A sale, void, return, collection or cash move is accepted after the 14-1 sheet is counted and the cash is at the hub; a void after the count hides a shortage | phase100: `business_days(location_id, day, status open or closed or reopened, opened_by, closed_by, reopen_reason)`; `_day_gate(loc, date)` called from `record_sale2`, `void_sale`, `sale_return`, `collect_payment`, `cash_move_add` by hook; `day_gate_mode` (off, warn [default], block with release request); grant `closed_day_edit`; release through the existing `request_release`; optional `cashier_sessions` (till, opening and closing count) to prefill 14-1; screen `#/daystate` and Open day and Close day buttons on POS Home (by hook) | U-02 | 6 | H | OD-4 | Void after close refused or needs release in block mode; warn mode only flags; reopen needs reason and audit; late offline sale handled by U-02 policy; mode off = old behaviour |
| U-14 | Severity-based month-close checklist (A-04; debate Q10) | major | The checklist tests payroll only, so "closed" gives false comfort | phase101: `close_checks` (code, severity blocker or warning, query) seeded with: unposted sources, `acct_post_errors72`, unmatched bank statement lines, stock count approved, `inventory_vs_gl`, `acct_reconcile` party differences, pending 10-2 and wastage requests, `cogs_missing`, day-close of every trading day per place (U-13), transfers received or claimed, payroll posted; a warning can be accepted with a note; `month_close_sets_lock` (ask [default], always, never): the lock is set only on the owner's confirm; reopen stays owner only with reason; `web/monthclose.js` is owned by this package | U-02, U-13 | 3 | M | OD-5 | One place without a 14-1 is a blocker; warning accepted with note writes audit line; confirm sets `period_closed_until`; never auto-set; reopen needs reason |
| U-15 | Stock-movement journals: count, issue, manual production (G18) | major | Shrinkage and manual issues change stock but never reach the books; `inventory_vs_gl` always has an unexplained part | phase103: new sources `stock_count`, `stock_issue`, `stock_manual_production`, keyed on `stock_ledger.id`, including rows made by forms (`ref_type entry`); loss, gain and consumption accounts named by the owner; delivered as `_s_docs` and hooked into `_acct_docs` | U-09, G2 | 4 | M: hook into `_acct_docs` | OD-16 | Count loss posts Dr loss, Cr inventory; gain reverse; void reverses; `inventory_vs_gl` unexplained part falls to rounding; paste twice posts nothing new |
| U-16 | Transfer documents and transfer journal (B-14, A-19; debate Q6) | major | The factory sends 30-60 lines to each showroom every morning, one item per call today. Unreceived goods let a showroom sell what the system says it lacks. Branch inventory in the GL is wrong | phases 107-110: `transfer_docs` and lines (challan no, carrier, vehicle, seal, temperature, sent_at); `stock_transfer_doc(p_lines)`; receive by line with reason (short, damaged, spoiled, over); alert `transfer_unreceived` after `transfer_receive_hours` (blank = off); refuse dispatch with less than `min_shelf_hours_dispatch` unless a reason; journal: one daily summary entry per from-to pair at ledger cost plus an in-transit asset line (source `stock_transfer_day`); `transfer_markup_pct` for partner sites only (blank = none); printable challan `web/transferdocs.js` | G6 (done), U-15 | 8.5 | M | OD-17 | Send 40 lines, receive 39 with reason; in-transit line clears; over-receipt needs reason; summary entry balanced; stock identity per place unchanged |
| U-17 | Daily per-item blind count (B-15) | major | A monthly count is too late for sweets: wastage and giveaway are separable only by a nightly count of the 20-40 fast items | phase105: `daily_count_items` per showroom (owner picks items); end-of-day blind count inside the close flow reusing `stock_count_adjust` and the phase18 seal; variance exception above `count_tolerance_pct`; `web/dailycount.js` | U-13, U-15 | 4 | L | N | Count saved before expected figure shown; variance creates exception; adjustment reaches the journal; closed day blocks late count |
| U-18 | Offline POS resilience (B-04 a-c; C-40) | major | Load-shedding and weak data are routine. After a phone restart with no internet the POS cannot start; an offline sale prints no receipt; the owner cannot see sales waiting on a phone | phase111: `pos_outbox_report(device, count, oldest)`; IndexedDB cache of sellable items, prices and tier rules written on every successful load; boot POS from the cache when `my_context` fails (queue-only writes); provisional receipt `OFF-<device>-<n>` mapped to the server receipt on sync; owner digest line "n sales waiting at <place> since <time>"; header chip Online, Offline or N not sent with Send now; `pos_offline_max_queue` (blank = off); `web/posoffline.js` | U-02 (late sale parked) | 6.5 | H: cache can hold old prices | OD-7 | Browser test: cold start offline sells from cache; provisional receipt maps on sync; price changed meanwhile is flagged; heartbeat visible to owner; cache cleared on logout |
| U-19 | Custom cake, gift and party orders end to end, advance cash on the day (B-05, G22) | major | The highest-margin, highest-complaint line. The digital order has no message, design, slot, factory view or capacity; the advance reaches cash only at delivery | phases 114-117: `custom_order_lines` (weight, flavour, message, design note, photo); `online_orders.ready_by`, `fulfil_location_id`, `slot_code`; `order_capacity(location, day, max_orders or max_lb)` owner list; statuses `in_production`, `ready`; edit after confirm writes `changed_after_confirm` and an exception; factory orders-due board with print slip; advance saved as a `cust_advance` cash move, used at delivery without a second sale payment, cancel fates refund and income post; 20-1 shown read-only in app mode; `web/cakeorders.js` | G5 (done) | 9 | M | OD-19 | Advance appears in cash on the day taken; delivery does not double count it; cancel with refund and with forfeit post balanced; edit after confirm raises exception; capacity full warns |
| U-20 | Courier, platform and card receipts with settlement (B-06, B-30, A-32, A-14) | major | Cash held by a courier shows as a customer due; no rider statuses or fees; card receivable 1140 is never cleared | phases 122-126: `carriers` (own, courier, food app; commission %; settle days); payment mode `courier_cod` or `platform` with `carrier_id` posting to account 1250; statuses `out_for_delivery`, `failed`, `returned` with fate selector (failed perishable goes to wastage 5100); `delivery_zones(fee, eta_min)`; settlement screen (expected, received, commission expense) replacing the typed 10-3 online table; card: cash-move kind `card_settlement` (gross, fee, net) clearing 1140 into a bank money account, built only for modes that show real volume; `web/carriers.js` | U-19 schema phase, U-09, phase87 | 11 | M | OD-2, OD-19 | COD sale is not a customer due; settlement clears 1250 and books commission; failed delivery fate posts; card settlement gross equals fee plus net; party type courier accepted by the journal constraint |
| U-21 | Production plan from orders, indent and history (B-16) | major (operations, behind control items) | The 14-1 demand table is read by nothing; reorder is a flat average | phases 118-121: `production_plan(day, item, location, qty_orders, qty_demand, qty_suggested, qty_planned)`; sources: confirmed orders, a `showroom_indent` entry replacing the paper demand table, 4-week same-weekday average from `sale_out`, owner event multipliers (blank = none); shortcut plan to `production_post` with ingredient check; `web/prodplan.js` | U-19 | 7 | L | OD-19 (event list) | Confirmed order adds to the plan; suggestion equals hand-computed average; ingredient shortage shown before posting |
| U-22 | Receivable controls: terms, overdue block, dunning, write-off, ageing (A-22, B-08, A-33) | major | Party and wholesale trade pays on 7, 15 or 30 days; bad debt is the biggest cash risk; buckets are blank by default | phases 127-129: `customers.credit_days`, `sales.due_date`; `pos_credit_overdue_block_days` (blank = off) asks for a grant or release; weekly `due_reminders()` for opted-in customers; `due_write_off(customer, amount, reason)` with approver by setting (Dr bad debt or allowance, Cr 1210); allowance by ageing band (blank = off); buckets 7/30/60/90 shown as a suggestion, not applied; balance sheet shows negative payable as supplier advance and negative receivable as customer credit; customer statement print; `web/receivables.js` | U-01 | 6 | M | OD-16 | Overdue block refuses or asks release; write-off balanced and needs reason; reminder job idempotent; statement equals ledger |
| U-23 | Price lists: wholesale, location, dated, customer rate; quote with rate lock (B-07, B-09) | major | `wholesale_price` is stored but never used; staff override prices by hand; festival prices change on a date | phases 130-132: `item_prices(item, kind retail or wholesale or online, location, brand, customer, valid_from, valid_to, price)`; `record_sale2` resolves price by sale type, location, customer and today (hook); POS shows the resolved price; scheduled change replaces the immediate edit; `quotes` lite (validity, rate lock, convert to sale, invoice from the sale); `web/pricelists.js` | none | 5 | M: POS hot path | OD-15 | Wholesale sale uses wholesale price; dated price switches at midnight; customer rate wins; override still possible with existing yellow flag; old sales unchanged |
| U-24 | Alert pipeline and approval routing (B-27, B-28, A-08 rest, B-34; m6) | major | The owner relies on a phone message but alerts depend on one cron, warn-level alerts are never e-mailed, and one showroom manager sends all approvals to the owner | phases 133-135: `notify_runs(kind, at)`; red `notify_silent` when no run for N hours (setting); per-kind "e-mail this too"; digest sections: gross profit, orders due, production versus sold, unreceived transfers, hub cash, absent staff, quick-sale share; after-close recap slot (time setting); approval routing table (primary, backup, escalate after N minutes) for POS-blocking approvals with live status to the requester; routing never fixes the owner's own-entry approver; widen the named-approver mode beyond entries (m6); `web/notifyhealth.js`, `web/approvalroute.js` | U-13, U-16 for digest sections | 7 | L | OD-20 | Stopped cron raises `notify_silent`; selected warn kind is e-mailed; escalation moves a request after N minutes; maker never approves own request |
| U-25 | Complaint ticket, batch trace, hold batch (B-17) | major | A food complaint needs "which batch, which showrooms sold it, who still holds it" within hours | phases 136-137: `complaints(customer, sale, item, batch, kind, severity, status, owner, compensation, closed_at)`; `batch_trace(batch_id)` (production run, transfers, showrooms, receipts, remaining stock); hold batch reusing `qc_record status hold` and `quality_block_on`; `web/complaints.js` | none | 5 | L | N | Trace lists every sale of the batch; hold blocks sale when the block switch is on; ticket cannot be closed without outcome |
| U-26 | Compliance register (A-23, B-19) | major | Trade licence, food and fire certificates, extinguisher refills, staff health certificates and VAT or withholding due dates expire; a missed renewal can close a showroom | phases 138-139: `compliance_items(owner type, kind, number, issued, expires, file, reminder days, cost)`; `employee_documents.expires_on`; `notify_scan` block "expiring in N days"; Control Center tile; `web/compliance.js` | none | 3 | L | N | Reminder fires at the set day; expired item shows red; document photo kept |
| U-27 | Cold chain log and asset service history (B-18, B-20; G27 asset link) | major | A chiller failing overnight is the costliest event; a freezer or oven failing before a festival; `assets`, `fa_assets` and the purchase line can carry three costs | phases 140-142: `equipment_temp_log`, `assets.target_min` and `target_max`; excursion makes a red exception and holds batches stored in that asset; `asset_service(kind, date, vendor, cost, downtime, next_due)`; next-service alerts; link `assets` to `fa_assets` and the purchase line (one cost); `web/coldchain.js` | U-25 hold mechanism, U-09 | 6 | M | N | Out-of-range reading holds linked batches; service due alert; lifetime repair cost visible only with the cost right; one cost per asset |
| U-28 | Receiving quality and valuation lite (A-18 lite, B-22) | major | Rejects and short weight are not captured at the gate; the purchase-return variance is never posted; no stock value for a past date | phases 143-145: `purchase_lines.accepted_qty`, `rejected_qty`, `reject_reason`; automatic debit note (`kind return`) for rejects; milk and chhana receiving checks stored as `qc_records source_type grn`; post `purchase_bills.variance` to a variance account; `stock_valuation_asof(date, loc)`; list of items without cost; `web/receiving.js` | U-09 | 5 | M | N | Reject creates a balanced debit note; variance posts once; as-of valuation equals ledger replay; items without cost listed |
| U-29 | Staff exit clearance, security deposit, payroll deductions in the books (B-25, A-11 lite; debate Q7) | major | The deposit is recorded but is neither a liability nor refunded; pay-structure deductions vanish from the ledger; the owner pays final salary first and chases the rest | phases 146-147: `exit_cases` checklist (assets, keys, cash short, advances, deposit); final payment blocked until required items are ticked or an approver overrides with reason; `staff_deposit` liability (party tag staff) with its cash-receipt event; accrual lines credit deductions by kind (gross expense = net plus deductions plus advance recovery); deduction payable accounts; encashment and notice rules as owner rates (blank = off); `web/exitclear.js` | U-03, U-09 | 5 | M | OD-12 | Deposit received and refunded balanced; settlement nets deposit and open shortage; deductions credit payable; blocked final pay released with reason |
| U-30 | Sheet-versus-system compare and handover (G20, G28, G19; G4 link) | major | Every figure on 14-1 is typed and never compared with POS; the showroom half of a cash handover reaches no ledger | phases 148-152: `sheet_vs_system(entry)` for 14-1 and 10-1, then 10-4, 10-5, 06-5, 20-5, 04-4, 01-1; exception `sheet_system_gap` using `cash_tol` and `goods_money_tol_pct`; 14-1 stock table (waste, own use, sample) compared with wastage and issues of the day; source `cash_handover` from approved 10-1 (Dr `hub_clearing`, Cr `pay_cash`), skipped for a shadow, reversed on re-open; `web/sheetcheck.js` | U-13, U-11, U-15 | 11 | M | OD-17 | Wrong total on 14-1 raises exception with no human compare; handover entry balanced; 1230 returns to zero after hub receipts |
| U-31 | Paper-to-books posting: registers, marketing, cost bills (G24, G25, G26, G29) | major | Paper links are not read by any report; marketing spend and cost bills reach no books | phases 153-157: `purchase_bills.po_ref`, `supplier_payments.entry_ref`; 20-2 and 20-3 serials on sales and returns; source `marketing_expense` (Dr `exp_marketing`, Cr by source, refuse a 10-2 duplicate); cost bill posts Dr `exp_<type>`, Cr payable or pay account behind `cost_bill_creates_payment` (OFF); month-end overhead true-up on `overhead_absorbed`; `web/paperposts.js` | U-09, U-11 | 11 | M | OD-16 | Bank-paid ad invoice reaches journal and L1; cost bill once in expense and once in conversion cost via absorbed account; duplicate 10-2 refused |
| U-32 | Minor linkage gaps, each needs an owner yes (G23 with B-12, G17, G31, G32) | minor | Loyalty points are not tied to a sale and never reverse on a return; form-path payroll has no journal; HR paper money is typed twice; recipe card and live recipe can differ | phases 158-162: redeem points inside `record_sale2` as a referenced discount, reverse points on return, expiry job; sources `payroll_form` and `staff_advance_form` only when the form path is primary; 02-1 temp wage as quick expense; 02-6 from `payroll_settlement_preview`; show live recipe or shelf life next to cards 05-2 and 05-3; `web/linkage.js` | U-06 | 11 | L | OD-16 | Points and discount move together; return reverses proportional points; form payroll posts once; card cannot silently differ |
| U-33 | Recurring bill entry for rent and electricity (A-13 lean; debate Q5 order) | major | Rent and utilities are recognised when paid, so monthly branch profit swings with payment dates | phase163: `bill_commitments(payee, head, amount, period, due date)` posting Dr expense, Cr payable; the later payment clears the payable; no prepaid amortisation yet (U-49); `web/recurring.js` | U-09, U-15 | 3 | L | N | Bill posts in its period; payment clears payable; edit after posting needs reason |

### 2.3 Wave 3: usability (12 items, 88 days, +2.5 optional)

All Wave 3 items keep every route URL, every form and every option. Nothing is removed (BUILD-RULES 1).

| ID | Title (source IDs) | Sev | Why a real business needs it | What to build (phase, files, screen) | Depends | Days | Risk | Owner decision | Tests |
|---|---|---|---|---|---|---|---|---|---|
| U-34 | Role "My day" Home, personas and routines on Home (C-01, C-02, C-03, C-07, C-08, C-13, C-15; Q1, Q2, Q17; D 4.23) | major | Home is 4.5 phone screens and shows the same screen five ways; 11 roles but 7 personas (purchasing, HR and cash controller get the wrong shortcuts); the best "what next" feature (Guided routines) is hidden four taps deep | No SQL. `web/home2.js`; `persona()` by role code first, then grants, with lists for purchasing, hr, party, carrier, cash controller; Home = 5 blocks (primary job, do next, my shortcuts, numbers, help); bottom bar Home, Search, primary-job orb, Do next, Menu; favourites menu reduced to Pin, Open plus an Edit mode; salesperson sees "My sales today" (setting `home_totals_for_sales`, off); behind rule `ia_home_v3` (OFF) | none | 4.5 | M: `nav.js` is shared | OD-13 | `ia_test`, nav, nav2, control, favsync; every persona sees a primary job; tap table of Audit C (average 2.56 down to 1.42) re-measured on 10 jobs |
| U-35 | Setup area: six tabs, typed controls, retire the raw settings screen (C-16 to C-21; C-B1) | major | Switches live in 10+ screens; the legacy screen shows raw keys and typed dates | No SQL. `web/setup.js` with tabs Start here, Places, Access, Rules, Master data, Printing and connections, Safety; every key gets a typed control (switch, number with unit, date picker, choice); alerts (25 `notify_*`) and emergency (23 `em_*`) become one card each with Off, Normal, Strict; keys under Details; only the changed card redraws; `period_closed_until` uses a date picker with "Entries on or before this date will be locked. Owner can still reopen with a reason." | none | 5 | M | N | Every old key reachable; no raw JSON box; settings2, rules and switchboard tests pass |
| U-36 | Presets and the Setup checklist routine (C-10; B-29; C-B2, C-B3) | major | A new owner sees an empty Home with no "start here"; 150 rules to learn | phase170: `apply_preset(name)` calling `set_rule` per value (validated, audit-logged), preview diff, Undo for 10 seconds; presets Small shop, Multi-outlet, Factory (values are proposals in Audit C table 4.1, owner confirms); `#/flow/setup` 13 steps (done by data, to do, skip with note); operations readiness screen (percent of tracked items with shelf life, minimum stock, recipe, unit conversion, cost) | U-35 | 7 | M | OD-14 | Preset changes only listed rules; each change in `audit_log`; preview equals result; undo restores; preset off = old values |
| U-37 | One confirm sheet, error dictionary, undo, plain wording (C-29, C-30, C-31, C-32, C-35; D P14) | major | 46 browser prompts in 27 files can be suppressed in an installed app and the action silently does nothing; errors vanish after 2.6 s as database text; staff see "SQL must be run" | `BOS.ui.confirm({title, impact, reasonRequired, typeToConfirm})` (type to confirm only for close month, activate agreement, restore); error dictionary `code to three languages and what to do`, toast 6 s, Copy details for owner; Undo toast only for reversible non-financial writes (never Submit, Approve, void, payments, close day or month); replace "SQL", "phase15", "Data needed" wording; mechanical sweep of 27 files is run by the integrator last | none | 4.5 | M: touches 27 files | N | Grep test: no `window.prompt` or `window.confirm` remains; money grants show an impact sentence; undo restores the previous value; error code shown in all three languages |
| U-38 | IA regroup into 9 areas, route map guard, search v2, glossary (C-04, C-05, C-06, C-09, C-26, C-27, C-28; route map; C-B10) | major | 13 categories and 88 drawer rows; search is hidden; one Bangla word has 14 English words; the glossary guard fails today (6 inconsistent terms) | First commit of this package: `docs/IA_ROUTE_MAP.md` with the map of section 2.5 below. Then `web/ia.js` group fields only (integrator), `#/group/<old id>` redirects, rename "Attendance 2", "Finance 2", header search icon with deep links (customer sheet, item page), search by receipt number, entry serial, paper number, customer phone; `tools/glossary.py` extended to about 60 terms and run in CI | none | 6 | M | OD-18 | Snapshot of the 101 route ids: each resolves in `BOS.ia.resolve()` and is visible to at least one role; `python3 tools/glossary.py` prints 0 inconsistent; search finds a receipt |
| U-39 | One Approvals inbox and one Access page (C-11, C-12, C-14; C-B6, C-B7) | major | Approvals are spread over nine screens and four overlapping inboxes; three views of permissions with no guidance; staff approval is 11 independent buttons | No SQL. `web/approvals.js` (filter chips, inline Approve and Reject; the nine screens stay as links); `web/access.js` (By person, By role, By form; impact sentence and confirm for money grants such as `salary_view`, `view_cost`, `export_data`); staff approve sheet: role preset text, copy from another person, location in the same sheet | none | 6 | M | N | Inline approve calls the same RPC; grants enforced on server; decider never the maker |
| U-40 | Job cards for form-versus-screen pairs and merged near-identical screens (C-22 to C-25; C-B8) | major | 20 jobs have both a paper form and a screen, so the user must know which to use | No SQL. `web/jobcards.js`: one card per job, default path from the existing rule (`grn_receipt_source`, path switches), other path as a secondary link; tabs merge customers, dues and tiers; attendance family; pay family; three cost screens; "Path switches and shadow copies" renamed "Two-way jobs" under Advanced | none | 5 | M | OD-13 | Each of the 20 jobs opens its default path; both paths still reachable; owner default stored once |
| U-41 | Compact foundation (D phases 0-1: P1, helpers for P2 to P6, S1 fix) | major | The app is one 640 px column; stacked bars waste 18 percent of the phone; a hard check reads the page (DOM) and silently stops working if its notice sits in a closed section | `web/compact.js`, `web/compact.css` (`B.ui.more, tabs, steps, bar, row, help, jump, find, undo`); phase171 rule `ui_compact` (OFF) plus per-phone `bos_compact`; chrome diet; baseline harness `tests/web/compact_measure.js` and `compact_baseline.json`; S1: `blockOn()` reads `E.calc.needs` instead of the DOM (`entry.js`, `locations.js`, integrator) | none | 7.5 | M | OD-18 | Module unit page; S1 regression: missing limit refuses submit with compact ON and OFF; storage blocked renders; with switch off the old markup is byte-identical |
| U-42 | Form engine compaction (D phase 2; C-36, C-37) | major | 41 paper-form specs share one renderer; 14-1 is 12.5 screens | `web/entry.js` has one owner in this package: sections to tabs, steps or accordion with required, red and yellow badges; "Missing fields" sheet jumps to the field and opens its section; remembered open state; "entered later from paper" group closed but forced open in paper mode; two short fields per row; notes to one-line banner plus help; table row cards to compact rows with Enter flow; sticky summary bar; per-form metadata for 14-1, 01-1, 01-2, 14-2, 03-1, 02-6, 02-7, 02-8, 02-2, 10-2, 04-3; "Open today's 14-1" direct; no tick-all for checklists | U-41 | 7.5 | H: all forms | OD-18 | Audit D tests T1-T14: field parity (set of `data-p` paths equal with compact off), jump to missing, red flag cannot hide, blind-count masks stay masked, both modes pass the existing suites |
| U-43 | Screen compaction: settings family, transactions, home, assistant, analysis (D phases 3-5; P11, P12, P16) | minor-major | Switchboard is about 18 screens; locset 5.5; purchase bill with 20 lines 9; product edit and employee wizard stack two bars | Three disjoint parts after U-41: (a) switchboard, matrix, form rules, location settings, access, tiers (6 d); (b) purchase bill, POS cart foot, product edit, employee wizard, partners, invoice (6.4 d); (c) assistant, analysis, home, next-10 list (3.7 d); plus the shared test matrix (2 d) | U-41 | 18.1 | M | OD-18 | Height budget per route; field parity; one bottom bar; Confirm visible in POS sheet with 8 lines |
| U-44 | Phone ergonomics, in-screen help and missing options (C-33, C-34, C-38 to C-46; Audit C section 5; C-B11) | major | Mini buttons are 36 px; no help inside screens; no hold-a-sale, repeat sale, receipt search, call or remind button, PIN reset | `.mini` to 44 px and bigger-text switch in Me; shared empty-state block with a next step; "?" help (3 lines, example, Ask) on every screen with one-time role tips; per-person start screen; dues: Call and Remind and "Over limit" text; return: search by receipt, customer or amount and "Return last sale"; low-stock row to requisition; POS hold sale and repeat last sale; PIN reset with reason; barcode in count form; duplicate item; printable cheat sheet | none | 8 | L | N | Touch target audit at 360x780; every listed option present and permission-checked on the server |
| U-45 | Keyed i18n migration of the inline strings (C-B12) | minor (optional) | 7,983 inline `L(bn,en,mix)` strings block a later full Bangla translation | Move strings to keyed dictionaries in batches after the glossary is clean; no behaviour change | U-38 | 9 | L | N | Key coverage test: no missing key in any of the three modes |

Optional: master-detail layout on laptops (D P8, 2.5 days) if the owner uses a laptop enough (OD-18).

### 2.4 Wave 4: tax, legal entities, advanced (9 items, 83 days)

Wave 4 starts only when the gate in the last column is met. Schema preparation is cheap and starts the day the gate opens.

| ID | Title (source IDs) | Sev | Why a real business needs it | What to build (phase, tables and functions, screen) | Depends / gate | Days | Risk | Owner decision | Tests |
|---|---|---|---|---|---|---|---|---|---|
| U-46 | VAT data model and Mushak outputs (A-09; TODO E4) | major (gated) | `vat_report` recomputes tax from today's item flag, so a later flag change rewrites past months; no VAT accounts; no tax-invoice fields or return worksheet | phases 180-189: `vat_rates(class, rate, regime, valid_from)`; store `vat_amount` and `vat_rate` on sale lines, returns and purchase lines at posting; VAT payable and input VAT accounts and mapping keys; split `_acct_docs` sale, return, purchase blocks; settlement journal; tax-invoice print; monthly return worksheet; BIN per unit; switches stay OFF until the adviser says | Adviser letter (OD-3); U-09 | 10 | H | OD-3 | Stored VAT does not change when an item flag changes later; sale, return and settlement balanced; rate regime per class |
| U-47 | Withholding tax and VAT at source (A-10) | minor now, major once applicable | The business may be the collecting agent for the government on supplier, rent and service payments | phases 190-194: `withholding_rules(payee type, category, tax kind, rate, threshold, valid_from)` entered by owner or adviser (no defaults); split on `pay_supplier`, 10-2 and rent bills; payable accounts; challan register with due-date reminders into U-26 | OD-3; U-46; U-26 | 6 | M | OD-3 | Split payment balanced; challan register ties to payable; rules blank = nothing deducted |
| U-48 | Payroll employer-side liabilities (A-11 rest) | major (gated) | Provident fund, gratuity, leave encashment, festival-bonus provision and wage-fund items are not in the books | phases 195-198: provision accounts; monthly provision entries driven by joining date and pay structure; final settlement function that posts; statutory wage register shape | Adviser letter (OD-3, OD-12); U-29 | 4 | M | OD-3, OD-12 | Provision balanced; final settlement clears provisions; rates blank = off |
| U-49 | Full accrual and prepayment engine (A-13 rest) | major | Yearly fees and insurance are not spread; no prepayment on the balance sheet | phase199: amortisation job for prepaid items (1400) and accrued items (2400) in `acct_post_pending`; reuse `costsources` input so a bill is typed once | U-33, U-31 | 3 | L | N | Yearly bill spreads over 12 months; payment clears; reversal on void |
| U-50 | Legal entities, consolidation, inter-company (A-20) | conditional major | If the factory, hub and showrooms or partner-held shops have separate licences or BINs, one book cannot support filing or consolidation | phases 200-209: `legal_entities(name, BIN, TIN, licence)`; `locations.entity_id`; `journal_entries.entity_id` derived from the location; entity filter in every `acct_*` report; inter-company accounts and elimination report | OD-1 must be yes; U-46 | 12 | H: touches every report | OD-1 | Trial balance per entity equals consolidated after elimination; entity filter in all statements |
| U-51 | Brand and cost-centre dimension in the journal (A-21 rest) | minor | Brand P&L is gross margin only; shared hub or factory cost is not allocated to brands | phases 210-213: `brand_code` resolved from the dated brand map (U-06) into `journal_lines`; allocation rules for cost pools by sales share or fixed percent; brand statement from the journal | U-06, U-05 | 4 | M | N | Brand statements add up to the company statement; allocation balanced |
| U-52 | Bank pack: cheque register, reconciliation statement, cash-flow statement, comparatives (A-16 rest, A-17, A-30) | major | A bank or auditor asks for the standard reconciliation statement, a statement of cash flows and comparatives | phases 214-219: cheque and post-dated cheque register with states (issued, presented, bounced, cancelled) and post-dated liability; statement-line "post as" journal for charges and interest (still approved by U-08); reconciliation statement (books plus deposits in transit minus cheques outstanding equals bank); cash set = all active descendants of 1100 except 1140 with operating, investing, financing split and indirect reconciliation; comparative parameter on `acct_*`; schedules and a PDF pack | U-08, U-10, phase87 | 12 | M | N | Reconciliation statement ties to statement balance; indirect cash flow ends at the cash set; comparatives equal prior-period reports |
| U-53 | Valuation advanced, assets, partner statement, budgets (A-18 rest, A-24, A-25, A-28; B-23, B-24) | minor | Landed cost, write-down of near-expiry stock, marked-down sale, co-products, asset disposal, partner transparency, forecasts | phases 220-229: landed-cost allocation on bills; NRV provision by remaining shelf life (percent from owner); batch grade and `markdown_pct` by hours to expiry; co-product outputs and artisan, shift, equipment on production runs; asset disposal journal and method choice; partner contributions to 3200 and a read-only partner statement; revenue budget, forecast, variance notes | U-28, U-15 | 16 | M | N | Landed cost raises unit cost; provision balanced and reversible; disposal clears cost and depreciation; partner sees only own statement |
| U-54 | Operations extras (B-10, B-11, B-13, B-21 light, B-26, B-31, B-32) | minor | Quick-sale and quantity guards, exchange flow, supplier-wise shopping list, staff incentive, low-literacy counter options, free-issue budget | phases 230-239: `pos_quick_max_amount` and share per cashier; `typical_max_qty` confirm; `sale_exchange`; shopping list from `reorder_report` and last supplier; `incentive_rules` and staff credit to `other_deductions`; picture tiles and Bangla digits option; `free_issue_daily_value` per outlet | U-23, U-29 | 16 | L | N | Each guard is a setting with a blank default; incentive posts to payroll once |

Parked or dropped by the debate (not built, kept here so nothing is lost):

| ID | Reason |
|---|---|
| A-26 hash chain on audit tables | Append-only triggers and the nightly copy are adequate until an outside auditor asks |
| B-33 disciplinary and training record, B-35 supplier scorecard, B-37 lost-demand tap, B-36 made-at back-date | Low value (B-36 is covered by the back-date rule in U-02) |
| A-08 `doa_rules` table | Replaced by settings thresholds with a chosen approver (U-07, U-24) and the existing SoD pair table |
| A-07 vendor change-request workflow, payee bank data | Lean controls in U-07 are enough for a small supplier list |
| Cheque and post-dated cheque register | Phase87 chose not to build it; moved to U-52 |
| m9 (fee treatment toggle), m10 (wallet opening) | Left open by phase86; revisit with U-09 |
| G1 to G15 | Done in SQL by phases 80-87 (see 1.2); web gaps are inside U-01, U-14, U-36 |

### 2.5 Information architecture: the 101-route map (for U-38)

Principles: group by job; nothing removed; every route keeps its `#/route`; at most 9 areas and 7 rows on a first screen; old `#/group/<id>` pages redirect. The full table with reasons is Audit C section 2.8 (working paper). The first commit of U-38 copies it to `docs/IA_ROUTE_MAP.md`. The condensed map follows. `moneyaccounts` (phase87) was added after the audit and belongs to Money.

| New area | Routes | Count |
|---|---|---|
| Home (My day) | `home`, `flow`, `owner` | 3 |
| Sell | `pos`, `salereturn`, `dues`, `onlineorders`, `inbox`, `customers`, `tiers` | 7 |
| Stock and Items | `items`, `items/new`, `bulkitems`, `stock`, `assets`, `stockx` | 6 |
| Buy | `purchase`, `purchase/new`, `purchase/return`, `payables`, `settings2/suppliers` | 5 |
| Factory | `recipes`, `recipebook`, `costing`, `costsources`, `costattrib` | 5 |
| Money | `daybook`, `finance2`, `quickexp`, `cashmoves`, `shortages`, `wallets`, `ledgerlinks`, `accounts`, `monthclose`, `partners` (+ `moneyaccounts`) | 10 |
| People | `attend2`, `benefitsx`, `staff`, `salary`, `employees`, `employees/new`, `deeds`, `attendance`, `leave`, `payroll` | 10 |
| Checks | `eqcheck`, `exceptions`, `pending`, `itemreq`, `releases`, `emergency`, `changes`, `numaudit`, `outbox`, `balancecheck`, `notifications` | 11 |
| Reports | `reports`, `biz`, `brandpnl`, `discounts`, `biexport`, `assistant` | 6 |
| Setup | `lists`, `settings2/units`, `itemimport`, `itemmap`, `itemtypes`, `invoice`, `saleforms`, `integrations`, `restoredrill`, `paths`, `locations`, `locset`, `locsheet`, `rollout`, `control`, `rulehub`, `switchboard`, `parallel`, `printbooks`, `matrix`, `delegation`, `rules`, `settings`, `settings2`, `logs`, `backup`, `settings2/fiscal`, `settings2/vat`, `settings2/barcode`, `settings2/noperm`, `settings2/stock`, `settings2/disc`, `settings2/shelf`, `settings2/access`, `settings2/fav` | 35 |
| Me | `twofa` | 1 |
| Hidden aliases | `products` (to Items), `report` (to Reports) | 2 |
| Total | | 101 |

Paper forms by area (42 of 42): Sell 14-1, 14-2, 20-1 to 20-6; Stock and Items 03-1, 04-1 to 04-4, 08-1; Buy 06-1 to 06-5; Factory 05-1 to 05-5; Money 10-1 to 10-5, 18-1; People 02-1 to 02-8, 11-1; Reports 01-1, 01-2; Setup 0-1 (opens `#/locset`). Dynamic patterns (`#/form/<code>`, `#/entry/new/<code>`, `#/entry/<id>`, `#/group/<id>`, `#/report/<key>`, `#/flow/<key>` plus new `#/flow/setup`, item, employee and `settings2` sub-pages) keep their URLs.

Standard terms to enforce (full list of about 60 goes into `tools/glossary.py`): Sell, Sales, Sale; Due and Dues (Pending only for approvals); Cancel before saving, Void after saving with reason, Reject by an approver; Off (switch), Close (dismiss), Closed (period), Inactive (item or person); On, Active, Go live; Location (not Place); Item in lists, Product on the customer receipt; Approve and Pending approval; Exception; Employee (HR register) versus Login (app account); Setup, Switch, Limit, Access; Not set yet (not "Data needed").

## 3. Disagreements resolved

### 3.1 P&L source (A-01: auditor A wants the journal, auditor B wants the management P&L fixed)

Resolution. Fix the management P&L now with the missing loss rows (U-05), keep one function for branch ranking, owner board and partner settlement, and add a setting `profit_source` (management [default] or ledger). Publish `profit_recon` so the difference is always visible. Every partner settlement stores the basis it used.

Reasoning. The journal fills only when someone opens Accounts and `accounting_on` is OFF by default, so the daily owner board cannot depend on it, yet leaving out wastage and shrinkage is a real error that must stop now. A setting plus a reconciliation lets the owner switch to the ledger once postings are fresh (U-11) and two clean months agree, and no partner is surprised because the basis is written on the settlement.

### 3.2 Automatic month lock versus owner rules with an override reason (A-03, A-04)

Resolution. No automatic lock by default. `auto_lock_day` exists but is blank (off). The month-close action sets the lock only when the owner confirms (`month_close_sets_lock` = ask). The owner is no longer silent in a closed period: `owner_closed_period_mode` defaults to reason. Any override is allowed with a required reason, one `audit_log` line and a red exception row.

Reasoning. Late paper entry ("entered later"), offline sales up to 72 hours and late supplier bills are real reasons for a few days of delay, so a hard automatic lock would stall daily work and teach people to bypass it. The real faults are the silent owner bypass and posting that depends on who opens the page, and a reason-and-log rule fixes both without ever blocking the owner.

### 3.3 Tax and legal-entity work as a second wave (A-09, A-10, A-20)

Resolution. Keep U-46 to U-50 in Wave 4 behind two gates: a written adviser answer (OD-3) and the owner's yes or no on separate entities (OD-1). Prepare cheaply now: inactive VAT and withholding payable accounts (U-09), due-date reminders (U-26), and the VAT-per-document schema the day the adviser answers.

Reasoning. Rates, thresholds and any entity structure are not in the repo, and building 12 or more days that touch every report before the owner states the facts would force invented numbers, which BUILD-RULES forbids. Nothing is lost: each item keeps its own entry, its gate and its question in section 5, so the owner can unlock them in one sitting.

### 3.4 Other disagreements

| Topic | Positions | Resolution |
|---|---|---|
| Severity of B-04, B-05, B-06 | B critical; A major | Features are major (A's rule: only control or books failures are critical). B-03 return restock is major+, built in Wave 1 because it is cheap and a food-safety risk |
| Exit lockout and return rules placement | Could be read as daily-operations features (Wave 2); both auditors rank them in their first nine | Placed in Wave 1 (U-03 1.5 days, U-04 3 days, no dependency). They can start on day 1 in parallel |
| Accrual versus stock identity | A first conceded stock identity first, then asked for movement journals first | Order: U-15 journals, then U-17 daily count and U-16 transfers, then U-33 and U-49 accrual |
| Approval tables (`journal_approvals`, `doa_rules`) versus existing release machinery | A: new tables; B: reuse | Reuse release and emergency machinery with a rule-chosen approver (U-07, U-08, U-24). No new matrix table |
| SoD report | A said none exists | `grant_separation_pairs` and `grant_separation_report()` exist in `phase78.sql` [verified by B]; U-07 adds pairs |
| Supplier controls | A: full workflow (5 days); B: lean (3) | Lean (U-07). Vendor change requests are parked |
| Bank and cheque register | A: build now; B: phase87 covers it | Phase87 covers accounts; cheque register moves to U-52 |
| Card settlement and MDR | A: major; B: unproven need | U-20 builds it only for payment modes that show real volume (OD-2) |
| Entry-date window | A: auto rules; B: owner-set | Owner-set per document type, blank by default (U-02) |
| Day lock versus month lock order | B: day first; A: independent | U-02 first (5 days), then U-13; U-14 needs both |

## 4. Waves, work packages and parallel safety

### 4.1 Rules that make parallel work safe

1. A package owns its phase-number range, its new web file names, its test file names and its integration note `docs/integration/<package>.md`. Nobody else writes those.
2. A package never edits a shared file (list in 4.2). It ships helper functions with its own prefix and writes the exact hook text in its integration note, as builders B to E did for phases 81 to 84 [verified, `docs/integration/*.md`].
3. Shared SQL functions are changed only by the wave integrator, by the exact-text patch helper `_m_patch` that phase87 introduced (reads the live definition, patches by text, carries a `bosNN` marker, stops if a patch site is missing) [verified]. Nobody re-creates `_acct_docs`, `_p27_pl`, `_daybook_lines` or `lock_check` from an old body. Re-pasting an older phase removes patches, so the integrator's last phase of each wave is a re-patch file.
4. A package that needs another package's table reads it only after that package's schema phase is merged (the "Starts when" column).
5. An existing screen file is edited by exactly one package per wave, the one named in the "Owns" column. A file listed in 4.2 is edited by the integrator only when no package of that wave names it; when a package names it, the integrator does not touch it in that wave.
6. Rules and grants are seeded by each package for its own keys only, with `on conflict do nothing`.
7. `docs/BUILD-LOG.md` and `docs/BUILD_PLAN_GAPS.md` are written only by the integrator, from the packages' integration notes.

### 4.2 Integrator-owned files and functions

| Kind | Items |
|---|---|
| Web files | `web/ia.js`, `web/index.html`, `web/entry.js` (except U-42 in Wave 3), `web/nav.js`, `web/app.js`, `web/sw.js`, `web/i18n.js`, `web/styles.css`, `web/theme.css`, `web/pos.js`, `web/dues.js`, `web/salereturn.js`, `web/cashmoves.js`, `web/purchase.js`, `web/payroll.js`, `web/employees.js`, `web/accounts.js`, `web/forms*.js`, `web/locations.js` |
| SQL shared functions | `_acct_docs` and its `_b_docs`, `_c_docs`, `_d_acct_docs` hooks, `_p27_pl`, `_daybook_lines`, `lock_check`, `record_sale2`, `void_sale`, `sale_return`, `collect_payment`, `cash_move_add`, `pay_supplier`, `save_purchase`, `post_purchase`, `employee_status_set`, `stock_transfer`, `stock_receive_transfer`, `notify_scan`, `daily_digest`, `urgent_alerts`, `opening_balance_post`, `partner_calculate`, `c_partner_month_split`, `acct_post_pending`, `acct_cash_flow`, `_acct_paykey`, `online_order_deliver`, `_cust_bal`, `_sup_balance` |
| Docs | `docs/BUILD-LOG.md`, `docs/BUILD_PLAN_GAPS.md`, `docs/IA_*.md`, `docs/UNIFIED_BUILD_PLAN.md` |
| Test lists | the `ORDER` string for fresh builds and the web test runner list |

### 4.3 Wave 1: money and control (items U-01 to U-12)

| Pkg | Items | Phases | New web file | New tests | Existing file owned |
|---|---|---|---|---|---|
| W1-A | U-01 | 88 | `web/openparties.js` | `phase88_test.sql`, `tests/web/openparties_test.js` | none |
| W1-B | U-02 | 89 | `web/periodlock.js` | `phase89_test.sql`, `tests/web/periodlock_test.js` | none |
| W1-C | U-03, U-04 | 90, 91 | `web/returnrules.js` | `phase90_test.sql`, `phase91_test.sql`, `tests/web/returnrules_test.js` | none |
| W1-D | U-05, U-06 | 92, 93 | `web/profitcheck.js` | `phase92_test.sql`, `phase93_test.sql`, `tests/web/profitcheck_test.js` | the only package that patches `_p27_pl` in Wave 1 |
| W1-E | U-07, U-08 | 94, 95 | `web/moneycontrols.js` | `phase94_test.sql`, `phase95_test.sql`, `tests/web/moneycontrols_test.js` | none |
| W1-F | U-09, U-10 | 96, 97 | `web/otherincome.js` | `phase96_test.sql`, `phase97_test.sql`, `tests/web/otherincome_test.js` | none |
| W1-G | U-11, U-12 | 98 | `web/freshness.js` | `phase98_test.sql`, `tests/web/freshness_test.js`, `tools/test_backup_crypto.py` | `tools/backup_dump.py`, `data/items_seed.csv` |
| I-1 | integrator | 99 | none | `phase99_test.sql` (re-patch and hook checks) | all shared files |

Parallel: all seven packages start together. Internal order: U-05 before U-06; U-01 before the freeze part of U-07; U-09 before the account use in other packages (seed only, no code clash).
Effort: 42 days of package work + 4 days integration. Critical path: W1-D (10.5 days) + integration 4 days.
Exit tests: all package tests green; older suites show the same failing set as before (known baseline: phase 8, 10 T12, 14, 15, 19, 21, 23, 42, 47, 72; 82 has 3 by design after 85 [verified in BUILD-LOG]); `phase87_before_after.sh`-style snapshot identical with every new setting at default; fresh database through phase99 builds; paste twice clean; Balance Check green on a fixture; owner can do each override with a reason; `tools/check_no_demo_leak.py` OK.

### 4.4 Wave 2: daily operations (items U-13 to U-33)

| Pkg | Items | Phases | New web files | Existing file owned | Starts when |
|---|---|---|---|---|---|
| W2-A | U-13, U-14 | 100-102 | `web/daystate.js` | `web/monthclose.js` | Wave 1 integrated (needs U-02) |
| W2-B1 | U-15, U-17 | 103-106 | `web/dailycount.js` | none | U-15 first, then U-17 |
| W2-B2 | U-16 | 107-110 | `web/transferdocs.js` | `web/stock2.js` (transit view) | start of wave |
| W2-C | U-18 | 111-113 | `web/posoffline.js` | none (hooks to `pos.js` by integrator) | needs U-02 |
| W2-D | U-19, U-21 | 114-121 | `web/cakeorders.js`, `web/prodplan.js` | `web/salesx.js` (holds the online orders screen; other screens in it `[unverified]`) | start of wave |
| W2-E | U-20 | 122-126 | `web/carriers.js` | none | after W2-D schema phase 114 is merged |
| W2-F | U-22, U-23 | 127-132 | `web/receivables.js`, `web/pricelists.js` | none | U-01 merged |
| W2-G | U-24 | 133-135 | `web/notifyhealth.js`, `web/approvalroute.js` | none | digest sections after U-13, U-16 |
| W2-H1 | U-25, U-26 | 136-139 | `web/complaints.js`, `web/compliance.js` | none | start of wave |
| W2-H2 | U-27 | 140-142 | `web/coldchain.js` | `web/stockx.js` (QC and batch view) | after U-25 hold mechanism |
| W2-I | U-28, U-29 | 143-147 | `web/receiving.js`, `web/exitclear.js` | none | U-03 merged |
| W2-J | U-30 | 148-152 | `web/sheetcheck.js` | none | needs U-13, U-11, U-15 |
| W2-K | U-31 | 153-157 | `web/paperposts.js` | `web/costsources.js` | needs U-09, U-11 |
| W2-L | U-32 | 158-162 | `web/linkage.js` | none | needs U-06 |
| W2-M | U-33 | 163-164 | `web/recurring.js` | none | needs U-09, U-15 |
| I-2 | integrator | 165-169 | none | all shared files | continuous, with checkpoints after W2-A, W2-B and W2-D |

Parallel: up to 15 packages; practical team size decides the calendar. Chains: U-15 then U-17 then U-30; U-19 then U-20 and U-21; U-16 then U-24 digest part; U-13 then U-14.
Effort: 137 days of package work + 14 days integration. Critical path about 20 days (U-19 then U-20) plus integration checkpoints.
Exit tests: per item tests; stock identity per place and item holds; `inventory_vs_gl` unexplained part is rounding on a fixture; a month-close dry run on a fixture blocks on a missing 14-1 and passes when complete; offline cold-start browser test; every override has reason, audit line and exception row; same baseline fail set; snapshot identical at default settings.

### 4.5 Wave 3: usability (items U-34 to U-45)

Wave 3 packages touch mostly new files, so they may start in the first week of Wave 1. Merges into shared files queue behind the single integrator.

| Pkg | Items | Phases | New web files | Existing file owned | Starts when |
|---|---|---|---|---|---|
| W3-A | U-34 | none | `web/home2.js` | none (`nav.js`, `ia.js` by integrator) | start |
| W3-B | U-35, U-36 | 170 | `web/setup.js`, `web/presets.js` | `web/rules.js`, `web/switchboard.js`, `web/settings2.js` | start; U-36 after U-35 |
| W3-C | U-37 | none | `web/ui_confirm.js` | none; the sweep of 27 files is the integrator's last step | start; sweep at end |
| W3-D | U-38 | none | `web/search2.js`, `docs/IA_ROUTE_MAP.md` | `tools/glossary.py` | start |
| W3-E | U-39 | none | `web/approvals.js`, `web/access.js` | `web/delegation.js` | start |
| W3-F | U-40 | none | `web/jobcards.js` | `web/paths.js` | start |
| W3-G | U-41 | 171 | `web/compact.js`, `web/compact.css` | none | start |
| W3-H | U-42 | none | none | `web/entry.js`, `web/forms*.js` (spec metadata) | after U-41 |
| W3-I | U-43 (a) settings family | none | none | `web/switchboard.js`, `web/locations.js`, `web/customers.js` | after U-41 and after W3-B |
| W3-J | U-43 (b) transactions | none | none | `web/purchase.js`, `web/items2.js`, `web/employees.js`, `web/partners.js`, `web/invoice.js` | after U-41; POS foot after W2-C |
| W3-K | U-43 (c) home, assistant, analysis; U-44 | none | `web/help.js` | `web/assistant.js`, `web/biz.js`, `web/dues.js` | after U-41; Home after U-34 |
| W3-L | U-45 (optional) | none | none | all, mechanical | last |
| I-3 | integrator | 179 | none | `web/ia.js`, `web/nav.js`, `web/index.html`, `web/sw.js` | continuous |

Parallel: W3-A to W3-G in parallel. Chains: U-41 then U-42; U-35 then U-36.
Effort: 88 days (+2.5 optional) + 9 days integration. Critical path about 15 days (U-41 then U-42 or U-43) plus merges.
Exit tests: `ia_test` snapshot of the 101 routes and 42 forms; nav, nav2, control, favsync, settings2; Audit D tests T1-T14 (height budget, field parity, jump to missing, S1 regression, remembered state, sticky bar, overflow in three languages, keyboard, blind count, undo, role hiding, both modes, repo gates); `python3 tools/glossary.py` prints 0; stage gates: owner phone only, then one showroom for one week on 14-1, 10-1, 10-2, 04-3, 03-1, then everyone; one real 14-1 completed by the owner on the new layout.

### 4.6 Wave 4: tax, entities, advanced (items U-46 to U-54)

| Pkg | Items | Phases | New web files | Existing file owned | Gate |
|---|---|---|---|---|---|
| W4-A | U-46, U-47 | 180-194 | `web/vat.js`, `web/withholding.js` | `web/finance2.js` (VAT tab) | OD-3 adviser letter |
| W4-B | U-48, U-49 | 195-199 | `web/accruals.js` | none | OD-3, OD-12; U-33 |
| W4-C | U-50 | 200-209 | `web/entities.js` | none | OD-1 = yes |
| W4-D | U-51 | 210-213 | `web/brandledger.js` | none (`web/reports.js` holds the brand P&L screen and is changed by the integrator) | U-06 |
| W4-E | U-52 | 214-219 | `web/bankpack.js` | `web/finance2.js` bank tab only if W4-A does not touch it; otherwise integrator | U-08, U-10 |
| W4-F | U-53 | 220-229 | `web/valuation2.js` | `web/partners.js` | U-28 |
| W4-G | U-54 | 230-239 | `web/opsextras.js` | none | U-23, U-29 |
| I-4 | integrator | 240-249 | none | shared files | continuous |

Parallel: all packages independent after their gates. `web/finance2.js` is touched by W4-A and W4-E: only one of them edits it; the other uses the integrator.
Effort: 83 days + 8 days integration. Critical path: U-52 (12 days) or U-46 (10 days) after the gate.
Exit tests: VAT stored per document does not change when an item flag changes; entity trial balances add up to the consolidation; every rate or threshold is entered by the owner or adviser (blank = nothing deducted); reconciliation statement ties to the bank statement balance.

## 5. Owner decisions needed

Each is a setting or a fact only the owner has. The recommendation is a proposal, not a number.

1. Separate legal entities? (U-50) Options: no (one book with locations), yes (factory, hub, showrooms or partner-held shops have own licence, BIN or company), unsure. Recommendation: answer first; if unsure, list what each trade licence and BIN covers. Default "no" keeps U-50 closed.
2. Payment mix (U-10, U-20): which of cash, mobile wallets, card machine, bank transfer, cheque, courier cash on delivery, food-app payout does each channel use? Recommendation: count payments by mode for 30 days; build bank mode now (cheap), card and courier parts only for modes with real volume.
3. VAT registration, rate and regime per item class, withholding tax and VAT-at-source applicability (U-46 to U-48). Options: registered, below threshold, not registered. Recommendation: written adviser letter; keep switches OFF until then.
4. Business-day lock (U-13). Options: off, warn, block with release request; who may reopen; window for late paper entry. Recommendation: warn for two weeks, then block with release request; the owner can always release with a reason.
5. Period lock (U-02, U-14). Options: manual lock only (recommended), automatic lock on day N, owner mode reason (recommended), log or off; back-date window per document type. Recommendation: manual lock on confirm; owner mode reason; read a 30-day lateness report before choosing any window number.
6. Return rules per product class (U-04): window in hours per class (sweets, cakes, packaged), receipt required yes or no, which classes may be restocked. Recommendation: no restock for perishable classes; numbers from the owner.
7. Offline POS limits (U-02, U-18): how many hours of offline sales to accept (today 72 [verified default]), what happens beyond (park for owner decision, recommended, or re-date), maximum queued sales per device, provisional receipt prefix.
8. Profit basis for partner settlement and month of salary (U-05, U-06). Options: management P&L with loss rows (recommended now) or ledger; salary belongs to the approved run month or the paid date. Recommendation: management now, ledger after two clean months; tell the partners the basis.
9. Owner-money entries (U-07): who may record owner draw or top-up. Options: owner only (recommended), or a named role or user with approval by an approver the owner chooses at any time. Bank slip reference mandatory: yes (recommended).
10. Supplier payment approval (U-07): amount above which a payment needs an approver, who approves, unique employee pay account warn or block. Recommendation: owner states the amount; block duplicate pay accounts.
11. Exit access (U-03): which statuses revoke login (recommended: resigned, terminated, retired; not on leave), hours before the alert, who may keep access with a reason.
12. Staff security deposit and final settlement (U-29, U-48): hold deposits as a liability (recommended), notice, leave encashment and gratuity rules (adviser).
13. Home and jobs (U-34, U-40): do salespeople see shop totals or only "My sales today" (recommended: mine); the default path for each of the 20 two-way jobs (Audit C table 2.5 proposes one for each).
14. Presets and scheduler (U-36, U-11): confirm the preset values (proposals in Audit C table 4.1); can a scheduler run (GitHub cron or database cron `[unverified]`)?
15. Data and prices (U-12, U-23): is the repo copy public (if yes remove the cost column and history now); wholesale, festival and customer-rate policy; backup passphrase holder and retention years.
16. Lists and account names (U-01, U-09, U-15, U-22, U-31, U-32): expense and other-income heads, names of stock loss, gain and consumption accounts, credit days and overdue block days, bad-debt policy, marketing and cost-bill treatment, and the source list of old customer and supplier dues.
17. Transfer and handover basis (U-16, U-30): transfer markup for partner sites (blank = none); handover amount = showroom count or hub-confirmed count (the other becomes the cash-short difference).
18. Screen design (U-38, U-42, U-43): never allow a one-tap "tick all" on checklists (recommended); merge the Home Modules and Categories grids into one "All screens" group (recommended); rename "Advance options" to "More options" (recommended); master-detail on laptops (2.5 days) only if a laptop is used; which of Cancel, Void, Reject keeps which Bangla word.
19. Custom orders and delivery (U-19, U-20, U-21): capacity unit (orders or pounds) per day, treatment of a forfeited advance as income, delivery zones and fees, commission percent of each app, festival event list for the production plan.
20. Alerts (U-24): which warn-level kinds are e-mailed, hours of silence before `notify_silent`, time of the after-close recap.

## 6. Definition of done

### 6.1 For every item

| # | Check | How it is proved |
|---|---|---|
| 1 | Journal balances | `tt.unbalanced_entries() = 0` after the new tests; every new source or patched source has a Dr = Cr test; `acct_balance_sheet.unbalanced` is false; Balance Check shows no new red |
| 2 | Defaults are safe | New settings default to OFF or blank. With every new setting at its default, the before and after snapshot (pattern of `tests/sql/phase87_before_after.sh`) is identical: P&L, balance sheet, trial balance, cash flow, day book, journal lines, posting dry run. A blank number blocks only the form that needs it and never invents a value |
| 3 | Exceptions possible and logged | Each control has an override path that needs a reason, writes one `audit_log` line and one Exceptions row. No path is tied to a person or a role. The owner's own-entry approver stays under `owner_approval_mode_set2` and `entry_approver_set`. The decider is never the maker of the same request |
| 4 | Negative tests | Unauthorised role refused on the server (a hidden button is also a refused request); unbalanced refused; second post refused (client id, `je_source_uq`); void reverses; closed period refused; blank setting blocks; setting OFF equals previous behaviour |
| 5 | Paste twice safe | The phase file is pasted twice with no error; the second paste patches nothing (`bosNN` marker); `to_regprocedure` guard stops the file with a clear message if an earlier phase is missing |
| 6 | Phase-order notes | File number unique and increasing; header lists "needs phaseNN"; the `ORDER` string for fresh builds is updated; the integration note lists each hook, the exact patch text and the re-paste hazard; `_m_patch` marker named |
| 7 | SQL tests | `phaseNN_test.sql` with `tt.chk` and `tt.err`; fresh database built through the new phase; every older suite shows the same failing set as before the phase |
| 8 | Web test | Screen registered only through `web/ia.js`; labels in three modes `L(bn, en, mix)` with glossary words; no horizontal overflow at 360x780 in bn, mix, en; `tests/web/<name>_test.js` has 0 assert failures and no console errors; `ia_test`, nav, nav2, control, favsync, settings2 pass |
| 9 | Demo-leak check | `python3 tools/check_no_demo_leak.py` prints OK before every commit and push; fixtures use neutral `test_*` ids; no person names; nothing under a demo folder or named DEMO or IMAGINED is read or copied |
| 10 | Paste-twice for data tools | Scripts under `tools/` are safe to run twice and never read the live project secret |
| 11 | Records | An integration note in `docs/integration/` and, after merge, an entry in `docs/BUILD-LOG.md` that lists what could not be confirmed and the manual checks run |
| 12 | Live database | Never written by an agent. The owner pastes one phase at a time after a written yes, on a test project first |
| 13 | Nothing deleted | Retire, never delete; append-only logs untouched |

### 6.2 Extra checks by kind of item

| Kind | Extra checks |
|---|---|
| New posting source | Idempotent by `(source_type, source_id)`; reversed when voided; skipped for a shadow record; appears once in day book and once in the journal; `daybook_vs_journal` shows no new gap |
| Patch of a shared function | Patched by exact text with a marker; a test proves the original behaviour when the new setting is off; the re-patch phase at the end of the wave restores it after an older phase is re-pasted |
| Control or approval | Server-side refusal tested with a salesperson login; maker cannot approve own request; override logged; escalation works when the approver is absent |
| Money screen | Amounts are Latin digits; offline save keeps the payment source; paste of a repeat request does not double post |
| UI-only item | Field parity (the set of fields is equal with the feature off); required, red and irreversible actions always visible or badged; storage blocked or corrupt still renders; per-phone switch restores the old layout |
| Data or tool item | Dry run first; output reviewed by the owner before any rewrite of history |

## 7. Roadmap

Effort is the sum of item days. Reserve is the integrator's time for hooks, re-patch phases and fixes after an independent check (about 10 percent). Calendar figures are `[unverified]` estimates and depend on the team size.

| Wave | Items | Work days | Reserve | Total days | Packages | What runs in parallel | Critical path (with enough builders) | Gate to the next wave |
|---|---|---|---|---|---|---|---|---|
| 1 Money and control | 12 (U-01 to U-12) | 42 | 4 | 46 | 7 + integrator | All seven packages together | W1-D 10.5 days + 4 integration = about 15 days | Exit tests of 4.3 green; owner pastes phases 88-99 on a test project and then live, one at a time |
| 2 Daily operations | 21 (U-13 to U-33) | 137 | 14 | 151 | 15 + integrator | Up to 15 packages; chains W2-D then W2-E, U-15 then U-17 then U-30, U-13 then U-14 | about 20 days of package work + integration checkpoints, about 25 working days | Exit tests of 4.4 green; stock identity and month-close dry run pass |
| 3 Usability | 12 (U-34 to U-45) | 88 (+2.5 optional) | 9 | 97 | 12 + integrator | W3-A to W3-G from week 1, alongside Waves 1 and 2; W3-H to W3-K after U-41 | about 15 days (U-41 then U-42) + merges | Stage gates A, B, C of 4.5 passed; one real 14-1 on the new layout |
| 4 Tax, entities, advanced | 9 (U-46 to U-54) | 83 | 8 | 91 | 7 + integrator | All independent once their gate opens | about 12 to 14 days after the gate | Adviser letter and owner answers (OD-1, OD-3) |
| Total | 54 | 350 | 35 | 385 | | | | |

Reading the table.
- One builder working alone needs about 385 working days in total.
- With enough builders the critical paths add up to about 15 + 25 days for Waves 1 and 2, with Wave 3 running in parallel and Wave 4 after the gates. A realistic team of five or six builders would take Wave 1 in about 3 weeks and Wave 2 in about 5 to 6 weeks `[unverified]`.
- Cheapest first moves (11.5 days, no dependency, large risk reduction): U-03 (1.5), U-04 (3), U-08 (2), U-11 (2.5), U-12 (2.5).

## 8. What could not be verified

- Live values of `accounting_on`, `accounting_start_date`, `forms_post_to_ledger`, `period_closed_until`, the wallet and money-account switches, and row counts of the live journal.
- Whether the repo copy that holds `data/items_seed.csv` is public.
- Whether a database scheduler is available on the hosting plan.
- Whether any tool sorts phase file names with a plain glob (phase numbers above 99).
- Real-device behaviour of offline start, sticky bars and Bangla glyph widths.
- Which existing web file holds the tiers screen (assumed `web/customers.js` in 4.5) and what else `web/salesx.js` holds.
- All effort numbers.
- Statutory facts (VAT, withholding, labour law) are areas to confirm with the adviser. No rate or threshold is asserted anywhere in this plan.

## 9. Trace: source ID to backlog item

Every critical and major finding of the audits, the debates and the form-ledger audit maps to the item shown. "Done" = built by phases 80-87 (section 1.2). "Parked" = section 2.4 table.

| Source | Item |
|---|---|
| A-01 | U-05 (and U-06) |
| A-02 | U-01 |
| A-03 | U-02 (day part U-13) |
| A-04 | U-14 |
| A-05 | U-08 |
| A-06 | U-07 (negative cash: phase87) |
| A-07 | U-07 (vendor change workflow parked) |
| A-08 | U-07 (pairs), U-24 (routing); DOA table parked |
| A-09 | U-46 |
| A-10 | U-47 |
| A-11 | U-29 (lite), U-48 (rest) |
| A-12 | U-09 |
| A-13 | U-33 (lean), U-49 (full) |
| A-14 | U-20 (phase87 partly) |
| A-15 | U-10 |
| A-16 | phase87 (accounts, charges), U-10 (receipt picker), U-52 (cheque register, reconciliation statement) |
| A-17 | U-09 (cash set), U-52 (statement) |
| A-18 | U-28 (lite), U-53 (rest) |
| A-19 | U-16 |
| A-20 | U-50 |
| A-21 | U-06 (dated map), U-51 (journal dimension) |
| A-22 | U-22 |
| A-23 | U-26 |
| A-24, A-25, A-28 | U-53 |
| A-26 | Parked |
| A-27 | U-12 |
| A-29 | U-11 |
| A-30 | U-52 |
| A-31 | U-02 |
| A-32 | U-20 |
| A-33 | U-22 |
| B-01 | U-13 |
| B-02 | U-03 |
| B-03 | U-04 |
| B-04 | U-02 (re-dating), U-18 (offline start, receipt, heartbeat) |
| B-05 | U-19 |
| B-06 | U-20 |
| B-07, B-09 | U-23 |
| B-08 | U-22 |
| B-10, B-11, B-13, B-31, B-32 | U-54 |
| B-12 | U-32 |
| B-14 | U-16 |
| B-15 | U-17 |
| B-16 | U-21 |
| B-17 | U-25 |
| B-18, B-20 | U-27 |
| B-19 | U-26 |
| B-21, B-26 | U-54 |
| B-22 | U-28 |
| B-23, B-24 | U-53 |
| B-25 | U-29 |
| B-27, B-28, B-34 | U-24 |
| B-29 | U-36 |
| B-30 | U-20 |
| B-33, B-35, B-36, B-37 | Parked (B-36 covered by U-02) |
| C-01, C-02, C-03, C-07, C-08, C-13, C-15 | U-34 |
| C-04, C-05, C-06, C-09, C-26, C-27, C-28 | U-38 |
| C-10 | U-36 |
| C-11, C-12, C-14 | U-39 |
| C-16 to C-21 | U-35 |
| C-22 to C-25 | U-40 |
| C-29 to C-32, C-35 | U-37 |
| C-33, C-34, C-38 to C-46 | U-44 (C-40 also U-18) |
| C-36, C-37 | U-42 |
| D P1, S1 | U-41 |
| D P2, P3, P4, P5, P6, P7, P9, P10, P13, P15 | U-41 (components), U-42 (forms) |
| D P11, P12, P16 | U-43 |
| D P14 | U-37 |
| D P8 | Optional, OD-18 |
| D S5 | OD-18 (never tick all) |
| G1, G4, G5, G6, G7, G8, G9, G10, G11, G13, G14, G15 | Done (phases 80-87); open leftovers m6 in U-24, m9 and m10 parked |
| G2 | `acct_readiness()` was never built; it is part of U-11 |
| G3 | Done in the journal; operational half U-01 |
| G12 | U-06 |
| G16, G21 | U-06 |
| G17, G23, G31, G32 | U-32 |
| G18 | U-15 |
| G19, G20, G28 | U-30 |
| G22 | U-19 |
| G24, G25, G26, G29 | U-31 |
| G27 | U-27 |
| G30, G33 | U-11 |
