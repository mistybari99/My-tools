# A4 - Cash and accounting reconciliation (audit + gap analysis, stages 1-2)

Branch `audit/a4`. Scope: do sales, cash, bank, mobile wallet / card, payment settlement and the ledger agree? Final DB = canonical order `docs/PASTE_ORDER.md` (phases 72..111), built with `tests/sql/final_build.sh a4db` on scratch Postgres 16 (port 5544). No SQL or web code was changed. Scripts: `tests/sql/audit2/a4/` (`run_a4.sh`, `a4_01..05*.sql`, output `last_run.txt`). Rerun: `bash tests/sql/audit2/a4/run_a4.sh a4db`.
Result of the executable scenarios: **105 assertions, 94 PASS, 11 FAIL** (the 11 are the findings listed below; 2 of them are "NOT SUPPORTED" probes written as failing assertions).

Check matrix tally (section 2): 57 checks = 25 PASS, 15 FAIL, 11 NS (not supported), 6 NOTE. Gap list: 20 gaps (4 High, 10 Medium, 6 Low, see section 5).

Assumptions (marked A): A1 one location (id 1), BDT, `Asia/Dhaka` is the business day. A2 Names are fixtures. A3 `accounting_on = true`, accounting start = today-5; every other rule at its shipped default (so `manual_journal_guard`, `card_settle_over_mode`, `period_closed_until`, scheduler are OFF). A4 Posting is done by calling `acct_post_pending` (the autopost scheduler is off by default; with it on the same function runs). A5 "Day D" = yesterday (sales are back-dated with `p_sold_at`), "today" = card settlement day.

## 1. Scenario and hand-computed expectations (written before running)

Item X sells 100, average cost 60, 100 units in stock. Opening journal: cash 20000, bank 50000, inventory 6000 = capital 76000.

| Day D event | Effect expected |
|---|---|
| Cash sale 3 x 100 | cash +300, sales 300, COGS 180 |
| Card sale 2 x 100 | card receivable +200 (no fee yet) |
| Mobile (bKash) sale 1 x 100 | mobile +100 |
| Bank-transfer sale (POS mode `bank`) | expected refused |
| Due sale 4 x 100, discount 20, cash 80, customer One | total 380, receivable +300, discount 20 |
| Sale at 00:30 Dhaka (= 18:30 UTC of D-1), cash 100 | must belong to D |
| Advance 500 cash (customer Two), due sale 200, advance used 200 | cash +500, advance liab 500 -> 300, receivable +200 -200 |
| Return of 1 unit of the cash sale, refunded in cash 100 | returns 100, cash -100, stock +1, COGS -60 |
| Voucher 10-2 transport 150 pay_mode bank; voucher repair 70 (no pay_mode); quick expense 50 cash | bank -150, cash -120 |
| Purchase 10 x 60 (payable 600); supplier payment 300 by bank | payable 300 |
| Cash deposit to bank 400 | cash -400, bank +400 |
| Drawer form 14-1: float 1000, typed day figures, counted 1770 | expected 1780, shortage 10 |
| Next day: card settlement gross 200, fee 4 | bank +196, bank charges 4, card receivable 0 |

Hand totals vs system (all after posting; `E1` in `a4_02_checks.sql`):

| Item | Expected | System | Result |
|---|---|---|---|
| Cash 1110 | 20000+300+100+80+500-100-70-50-400 = 20360 | 20360 | PASS |
| Bank 1120 | 50000+400-150-300+196 = 50146 | 50146 | PASS |
| Mobile 1130 / Card receivable 1140 | 100 / 0 | 100 / 0 | PASS |
| Customer receivable 1210 | 300+200-200 = 300 | 300 | PASS |
| Customer advances 2300 | 500-200 = 300 cr | 300 cr | PASS |
| Supplier payable 2100 | 600-300 = 300 cr | 300 cr | PASS |
| Sales 4100 / discount 4120 / returns 4110 | 1300 / 20 / 100 | same | PASS |
| COGS 5000 | 12 net units x 60 = 720 | 720 | PASS |
| Transport 5700 / repair 5600 / bank charges 5810 | 200 / 70 / 4 | same | PASS |
| Inventory 1310-1330 | 6000+600-780+60 = 5880 | 5880 | PASS |
| Profit | 1300-20-100-720-200-70-4 = 186 | 186 | PASS |
| Trial balance Dr-Cr | 0 | 0 (acct_trial_balance diff 0.00, balance_sheet difference 0.00) | PASS |
| Cash short/over 5800 | physical shortage 10 should reach books | 0 | FAIL (see C18) |

Conclusion: the ledger itself is arithmetically correct for every document type that is journalled. The weaknesses are in the controls around it (what is NOT journalled, what the reconciliation views cannot see, defaults that are off).

## 2. Check matrix

Legend: PASS / FAIL / NS (not supported). Evidence cites `file:line` of the canonical source (latest definition in the paste order) and test step ids.

### 2.1 Sales, payments, ledger

| # | Check | Result | Evidence |
|---|---|---|---|
| C01 | Sales total by payment mode == sum of `sale_payments` == GL | PASS | P1: cash 480, card 200, mobile 100; P2: sum(total) 1280 = sale payments 780 + dues 500; P3: GL(4100-4120)=1280. `_acct_docs` sale block `phase98.sql:75-92` |
| C02 | Revenue split: gross sales 4100 credit, discount 4120 debit, returns 4110 | PASS | E1 numbers above; `phase98.sql:75-110`. Net revenue = 1180 |
| C03 | Tax: GL revenue + tax + receivable movement | NS | No output-VAT account exists (only `vat_input` 1240). `vat_report` (`phase53.sql:556`) is a memo calculation; sales are credited gross |
| C04 | POS payment modes: cash, mobile, card only | PASS (limit) | `phase87.sql:316` `bad_mode`; check constraint `sale_payments_mode_check`. "Bank transfer sale" is NS: S3b refused with `bad_mode`; shops must book it as `mobile` |
| C05 | Card sale: receivable at sale, fee only at settlement | PASS | card sale -> Dr `pay_card` 200; `card_settle` + `_acct_docs` `phase98.sql:311-322`: Dr bank 196, Dr 5810 4, Cr pay_card 200; 1140 = 0 |
| C06 | Return refunded in cash | PASS | `sale_return` `phase12.sql:574`; entry Dr 4110 100 / Cr cash 100 / Dr inventory 60 / Cr COGS 60 |
| C07 | Partial returns add up to the sale (rounding) | PASS | Q1/Q2: 3 x 100, discount 3.337% = 10.01, total 289.99; returns 96.66 + 193.33 = 289.99; net GL revenue 0 |
| C08 | Rounding of COGS at 3-decimal cost | FAIL (minor) | RD1: 50 sales of 0.7 x cost 41.3333: GL inventory 46006.80 vs stock ledger 46006.63 = 0.17 (0.0033 per sale, always the same direction). `inventory_vs_gl` reports it as `unexplained 0.17` |
| C09 | Voids: due sale | PASS | V2b: cash -80, receivable of customer One 0, stock +4, customer disappears from `customer_dues` |
| C10 | Void blocked when a return exists | PASS | V2 `sale_has_returns` (`_sale_void_guard`, `phase12.sql:518`) |
| C11 | Void of an already settled card sale | FAIL | V3: card receivable becomes -200; the payout stays in bank; nothing links the void to the settlement (`void_sale` `phase6.sql:333`, no check against `card_settlements85`) |
| C12 | Void/reversal is dated on the day the void is made, not the sale day | FAIL (design, reporting) | V5: GL 4100 credit dated D still 1300 after two voids; `biz_daily(D)` shows 700. `acct_post_pending` `phase40.sql:660` `rdate = greatest(void_date, orig date)`. A day/month P&L from the GL differs from sales reports across a month end or a closed period |
| C13 | Double-posting protection | PASS | G0: second `acct_post_pending` posts 0; J1: duplicate insert -> `je_source_uq` (unique (source_type, source_id) where reverses_id is null); `je_reverses_uq`; J2 update/delete of journal lines -> `append_only` |
| C14 | Shadow engine: one record counted once | PASS | quick expense posted once (`by_type.quick_expense=1`, E1 transport 200 = 150 + 50). The quick-expense + form 10-2 pair is covered by `tests/sql/e2e/07_reports.sql` H2 (not re-run here, A6) |
| C15 | Unbalanced entries | PASS | `_acct_write` `unbalanced` guard; `tt.unbalanced()` = 0 after all 105 steps |

### 2.2 Cash, day book, drawer

| # | Check | Result | Evidence |
|---|---|---|---|
| C16 | Day-end cash per cashier vs journal cash account | NS | The journal has no cashier: `journal_entries.created_staff` = person who ran the posting (owner / NULL for the scheduler). Sums per cashier exist only in `sale_payments.created_staff` (PC1-PC3). Drawer form 14-1 expected cash is built from figures TYPED on the form (`_count_inputs18`, `phase18.sql:204`), not read from `sale_payments`/GL |
| C17 | Drawer count: expected vs counted | PASS | `count_save` `phase18.sql:251`: counted 1770, expected 1780, diff -10, blind count, one result only (W1) |
| C18 | Drawer shortage / overage reaches the ledger | FAIL | COA has 5800 "Cash short / over" but no mapping key and no `_acct_docs` block; the flag is only an exception `cash_short_over` (`phase18.sql:349`). GL cash 20360 vs physical 20350; 5800 = 0. No journal for `entry_counts.diff` |
| C19 | Drawer opening float = previous close | FAIL (control) | `open_counted` is typed (`phase18.sql:196`); no link to the previous day's closing count or to the GL cash account |
| C20 | Cash drawer events (phase95) | NS | `drawer_events` log only auto/no-sale/test/failed opens (`drawer_report`, `phase95.sql:140`); they carry no money, no reconciliation |
| C21 | Day book (`day_book`) vs journal | FAIL | D1: `daybook_vs_journal` shows 3 differing kinds. D2: day-book bank net 300 vs GL 146; cash 210 vs GL 360. Causes in C22, C23 |
| C22 | 10-2 voucher payment mode in the day book | FAIL | `_daybook_lines` hard-codes `'cash'` for 10-2 (`phase50.sql:277`) while the ledger uses `pay_mode` (`phase98.sql:147-170`, bos85). Voucher paid by bank 150 shows as cash out; mobile voucher 40 also (EX2) |
| C23 | Card fee in the day book | FAIL | Day book treats card as bank on the sale day (`_daybook_lines`, note `card_as_bank`) and has no row for `card_settlement`; ledger bank gets 196. Difference = fee 4 (D1 row `card_settlement` diff 4.00) |
| C24 | Voucher timing | NOTE | Day book counts a 10-2 voucher at submit, ledger at approve (`daybook_vs_journal` note, `phase13.sql:135`). Disclosed, not an error |
| C25 | Day-book opening vs ledger opening | FAIL (control) | `set_daybook_opening` (rules `daybook_open_cash/bank/mobile`) and `acct_opening` are two separate hand-typed openings (`daybook_start` vs `accounting start` also separate). Nothing compares them |
| C26 | Cash deposit to bank (`cash_move bank_deposit`) | PASS | Dr bank 400 / Cr cash 400 (`phase98.sql:181-190`); statement line matched. Day book note `bank_deposit_not_dated`: deposit has no bank account choice and no bank slip date |
| C27 | Owner money (`owner_topup`, `owner_draw`, partner capital) | PASS | journalled (`phase98.sql:181-190`, `258-285`); shown by kind in `daybook_vs_journal` |
| C28 | Advance received / used | PASS (see C31) | Dr cash / Cr 2300; used: Dr 2300 / Cr 1210 (`phase98.sql:189`). `customer_advances()` total 300 = GL 2300 |
| C29 | Paper-form salary / advance lines | NOTE | In the day book only (`salary_form`, `advance_form`); journal posts payroll payments instead |

### 2.3 Bank, card, mobile wallet

| # | Check | Result | Evidence |
|---|---|---|---|
| C30 | Bank per statement vs ledger | PASS | B1/B2 `bank_stmt_import`, `bank_recon_suggest`, `bank_recon_match_many` (`phase53.sql:405`): 5 lines imported, 4 matched automatically, `book_total` 146 (excl. opening) = system |
| C31 | Statement line with no book entry (bank fee 12.5) | NS | B3: report lists it as unmatched; no action turns it into an entry (`finance2.js` shows `b_nopost`). The user must go to manual journal |
| C32 | Several bank accounts / wallets | NS | One mapping `pay_bank` -> 1120, one `pay_mobile` -> 1130. `_a53_bank_acct` accepts any child of 1100 for import, but no payment mode or settlement can post to another account |
| C33 | Opening bank balance vs first statement balance | NS | `bank_recon_report` returns `last_statement_balance` but never compares it with the ledger balance at that date (it compares movements only) |
| C34 | Bank recon is optional | NOTE | Rule `bank_recon_on` default off (`bank_stmt_import` raises `switch_off`) |
| C35 | Card settlement entry (gross, fee, net, client id idempotent) | PASS | S: `card_settle` `phase85.sql:808`, `dup` on same client id |
| C36 | Over-settlement | FAIL by default | C1: settlement 5000 with 0 unsettled accepted, 1140 = -5000 (rule `card_settle_over_mode` default `off`, `phase109.sql` card_settle); C2 with `refuse`: `over_settlement` raised for 5000 and for a second 200 |
| C37 | Card settlement vs the card sales it settles (per batch / terminal report / MDR %) | NS | C3: `card_settlements85` stores only gross/fee/date/note; no link to `sale_payments`, no import of the acquirer statement; `unsettled` is a balance only (`card_settlement_list`) |
| C38 | Mobile wallet (bKash/Nagad) settlement and fee | NS | Wallet sale is Dr 1130 gross; no cash-out, no MDR/fee action, no `card_settle`-like screen (`card_settle` allows `bank_mode` bank/mobile only as the receiving side) |
| C39 | Online/wallet gateway reconciliation | PASS | `payment_recon_v` / `payment_recon` (`phase62.sql:406`) compare intents with `sale_payments`: states open, missing_payment, voided_payment, amount_mismatch, matched |

### 2.4 Receivables, payables, advances

| # | Check | Result | Evidence |
|---|---|---|---|
| C40 | Receivable sub-ledger vs GL (`acct_reconcile`) | PASS | R1: 0 customers differing; `phase40.sql:959`; shown on accounts screen (`accounts.js:324`). Needs owner (`_acct_all`) |
| C41 | Payable sub-ledger vs GL | PASS | R1: 0 suppliers differing; `payables_summary` 300 = GL 2100 |
| C42 | `customer_dues` list total vs GL receivable | FAIL | R1: list 500 vs GL 300. `customer_dues` (`phase12.sql:539`) = sales - payments - return credit and ignores `cust_advance_used`; customer Two shows 200 due although the advance covered it. `acct_reconcile` adds the used advance back (`advance_applied`) so it hides this |
| C43 | Collection after advance already applied | FAIL | V1: owner collects 200 cash from customer Two (list says due): GL receivable of Two = -200 and advance liability still 300. The debt is cleared twice. `collect_payment` `phase6.sql:258` does not look at advances |
| C44 | Advance consumption at POS | NS | `record_sale2` has no advance payment mode; consumption is a separate `cash_move_add('cust_advance_used')` (`phase23.sql:260`) |
| C45 | Advances sub-ledger vs GL per customer | NS | Only the total is compared (`customer_advances()` = 300 = GL); `acct_reconcile` has no 2300 part |
| C46 | Bill auto-payment (phase99) counted once | PASS | BP1: `auto_cash` bill 100 -> cash -100, payable net 0; BP2: manual pay on the same bill refused `nothing_due`; BP4 sub-ledger = GL |
| C47 | Payment not tied to a bill | NOTE | `pay_supplier` (`phase10.sql:1181`) accepts amounts beyond the bill; supplier goes to credit balance (shown in `payables_summary.credit_total`) |
| C48 | Supplier payment date | NS | `pay_supplier`/`collect_payment` have no date parameter: `paid_at = now()`. A payment typed after midnight, for the previous day, lands on the next day in day book and GL |
| C49 | Supplier payment void | PASS | V4 reversal restores payable 600; journal balanced |

### 2.5 Ledger controls

| # | Check | Result | Evidence |
|---|---|---|---|
| C50 | Period lock: non-owner cannot sell/void/post inside a closed period | PASS | L1: `period_closed` from trigger `sales_lock` (`phase6.sql:474`, also on UPDATE with the old sale_date), `cash_move_add`, `card_settle` (`phase85.sql:825`) |
| C51 | Period lock: owner | FAIL (control) | L2: owner can sell into the closed period and owner-run `acct_post_pending` posts it with entry_date = D (`lock_check` returns for `is_owner()`, `phase6.sql:455`; `_acct_locked` calls it, `phase40.sql:161`). Closed months can change silently |
| C52 | Period lock vs scheduler | FAIL (control) | L3: with no signed-in user the late sale stays un-journalled (`locked = 1`, no entry) though it is in sales and payments: books omit cash that was taken; only a counter shows it. Result depends on WHO runs the posting (C51 vs C52) |
| C53 | Return in a closed period | NOTE | `sale_return` checks today, not the sale date (`phase12.sql` `lock_check(now)`) - the return books on today; consistent |
| C54 | Manual journal guard | FAIL by default | M1: with `manual_journal_guard = off` a manual Dr cash 5 / Cr capital 5 posts (`acct_journal_post` `phase40.sql:701`, guard `_manual_guard85` `phase85.sql:198` only when 'on'). `daybook_vs_journal` shows it as kind `manual`, mode cash |
| C55 | Timezone cut-off | PASS | T1: 00:30 Dhaka sale has `sale_date` D, JE date D; its UTC date would be D-1. All cash/accounting functions use `at time zone 'Asia/Dhaka'`; scan of `pg_proc` for `created_at::date`, `current_date`, `now()::date` found one: `vat_report` outret bucket (`phase53.sql` `r.created_at::date`, session time zone dependent) - minor |
| C56 | Inventory vs GL / profit source | PASS | `inventory_vs_gl` agrees (6120 = 6120 at one point), `profit_source_check` `agree: true`, `cogs_missing 0`. Only the rounding drift of C08 |
| C57 | Stale ledger | NOTE | Scheduler off by default (`acct_overview.status.scheduler.on=false`); until `acct_post_pending` runs, `acct_reconcile` shows the difference and `status.pending` counts it (ST1/ST2). Reconciliation is only valid after posting |

## 3. Documents that are NOT journalled (by source type)

Journalled (`_acct_docs`, `phase98.sql`): sale, sale_return, collection, purchase (+return), supplier_payment, supplier_refund, expense_voucher (10-2, approved), quick_expense, cash_move (all 8 kinds), wastage, production, payroll_payment, staff_advance, partner_capital, stock_adjust/opening/issue/prodin/transfer, transit_loss, purchase_variance, card_settlement, landed_cost(+void), manual, opening, year_close, fa_depr (`fa_depr_post`, on request).

NOT journalled (verified in code or by the run):

| Item | Where it lives | Effect |
|---|---|---|
| Drawer shortage / overage | `entry_counts.diff`, exception `cash_short_over` | GL cash > physical; account 5800 unused |
| Drawer events (no-sale, auto-open) | `drawer_events` | log only |
| Card fee, wallet fee on a statement line | `bank_statement_lines` | needs a hand-made manual journal |
| Partner profit-share payments | `partner_settlement_payments` (`partner_settlement_pay`, `phase44.sql:1034`) | no source type in `_acct_docs`, not in day book |
| Paper forms 02-2 salary / 02-3 advance | `entries` | day book only (`salary_form`, `advance_form`) |
| 10-1 cash handover to hub | `entries` | day book only, marked internal; only `hub_receipt` cash move is journalled |
| Sales tax (VAT output) | `vat_report` | memo only |
| Expense accruals (unpaid vouchers) | - | 10-2 is cash-basis; 2200/2400 accrual accounts have no feed |
| Voucher submitted, not approved | `entries` | day book yes, GL no (timing) |
| Late documents in a closed period (scheduler run) | sales etc. | skipped, counted `locked` |
| Sales/payments of sale void settled by card | - | see C11 |
| Tendered amount / change | `sales.tendered` | not needed; payments hold the net |

## 4. Reconciliation screens: what exists and what is missing

| Need | Exists | Where | Missing |
|---|---|---|---|
| Day-end cash close, expected vs counted | blind count on form 14-1 | `count_save`, `entry.js:509`; result in `entry_counts` | not automatic from POS data, not per cashier shift, no GL link, no shortage posting, no float carry-over |
| Day book vs journal | yes | `daybook_vs_journal` (`paths.js`), `day_book` | 3 known mismatches (C22, C23, C25); only a developer-style table |
| Bank reconciliation | yes (off by default) | `finance2.js:199-259`, `bank_recon_*` | post-from-statement, balance check vs statement, multi-account |
| Card settlement reconciliation | partial | `books85.js`, `card_settlement_list` (unsettled balance) | per-batch matching, MDR %, acquirer file, over-settlement ON by default |
| Wallet reconciliation | gateway intents only | `payment_recon` | statement-based wallet reconciliation, wallet fee |
| Receivable / payable sub-ledger vs GL | yes | `acct_reconcile` (`accounts.js:324`) | customer advances per customer, card, bank, mobile, stale GL warning on screen |
| Inventory vs GL, profit vs GL | yes | `inventory_vs_gl`, `profit_source_check` (`costboard.js:56`) | - |
| One "close the day" screen that ties sales by mode = payments = cash/bank/card/wallet movements = GL | no | - | whole report |

## 5. Gap analysis

Severity: H = money or control can be wrong without anyone seeing it; M = wrong report or manual rework; L = small or cosmetic. Effort: S <= 1 day, M = 2-5 days, L > 1 week.

| ID | Gap | Business impact | Sev | Evidence | Fix outline | Eff | Depends on |
|---|---|---|---|---|---|---|---|
| G01 | Drawer shortage/overage never reaches the books (5800 unused) | Cash in GL higher than real cash every time a till is short; owner sees the red flag but P&L and cash balance stay wrong | H | C18, W1, `phase18.sql:349` | On submit of the 14-1 count (or via a "post variance" action) create doc `cash_variance` Dr 5800 / Cr pay_cash (reverse for overage); add mapping `cash_short` | M | G02 |
| G02 | No automatic day-end cash close: expected cash is typed, not read from POS/GL, not per cashier | A cashier can type the expected figures; no proof that the till total = payments - refunds - deposits - expenses | H | C16, C19, `_count_inputs18` | New RPC `cash_close_expected(loc, date, cashier)` from `sale_payments`(cash) + collections + refunds + cash_moves + cash expenses + previous close; show next to the blind count; store float carry-over | L | - |
| G03 | `customer_dues` ignores advances used; collection after advance clears debt twice | Customers can be asked to pay a debt already covered; GL receivable goes negative and advance stays | H | C42, C43, V0/V1 | Make `_cust_bal` / `customer_dues` subtract `cust_advance_used`; block `collect_payment` above the due; prefer one function `apply_advance` | M | - |
| G04 | Period lock bypassed by owner, and scheduler skips locked docs silently | Closed months change without trace, or cash taken is missing from GL while sales exist | H | C51, C52, L2/L3 | Owner needs an explicit reason + exception for closed-period posting; scheduler: list locked documents in a "late documents" screen and offer post-to-next-open-period (or reopen) | M | - |
| G05 | Day book and journal disagree (10-2 mode hard-coded cash, card fee, separate opening) | Two "cash books" with different numbers on the same screen family; owner loses trust | M | C21-C25, D1/D2 | In `_daybook_lines` read `pay_mode` of 10-2; add `card_settlement` row (bank in, fee out); single opening source (use GL opening) | S | - |
| G06 | Card settlement not matched to card sales; over-settlement accepted by default; void of settled card sale leaves negative card receivable | Card money can be settled twice or for sales that never happened; fees unchecked | M | C11, C36, C37 | Default `card_settle_over_mode = warn/refuse` (setup advisor), batch/terminal id on card payment, settlement lists chosen sales or day range, fee % warning; `void_sale` refuses/warns when card payment is in a settlement | M | - |
| G07 | Void/reversal booked on the void date | Day and month P&L from GL differs from sales report; a void of last month's sale hits this month | M | C12, V5, `phase40.sql:660` | Option to reverse on the original date while the period is open (else on first open day), and show the choice in the void dialog; align `biz_daily` | M | G04 |
| G08 | No bank charge / interest posting from a statement line; no statement balance check; one bank and one wallet account only | Bank fees and interest stay outside the books until a manual journal; multi-bank owners cannot reconcile each bank | M | C31-C33, B3 | "Create entry from line" action (Dr 5810/4900, Cr bank) with dry run; compare statement closing balance with ledger at the date; allow `pay_bank` per bank account (mapping by account) and a bank choice on deposit/withdraw/supplier payment | M | - |
| G09 | Manual journal guard default off | Anyone with accounts rights can move cash/bank/receivable with a memo and no reason | M | C54, M1 | Default `manual_journal_guard = on` for new installs (advisor recommends), keep daybook diff alert | S | - |
| G10 | Partner profit-share payments not in GL / day book | Cash leaves the business with no entry | M | section 3, `phase44.sql:1034` | Add source `partner_settlement_payment` to `_acct_docs` (Dr partner payable/drawings, Cr pay_*) and `_daybook_lines23` | S | decision on target account |
| G11 | No tax in the ledger (VAT report is memo only), prices assumed VAT-inclusive | Revenue overstated by VAT where VAT applies; return of VAT not in GL | M | C03 | If `vat_on`: split sales line into 4100 net + new `vat_output` liability at posting; post VAT settlement | L | policy decision |
| G12 | Mobile wallet fee / cash-out and bank transfer at POS | bKash/Nagad merchant fee and bank-transfer sales have no proper flow (booked as mobile) | M | C04, C38 | Add POS mode `bank`; wallet settlement doc like card settlement (gross, fee, to bank) | M | G08 |
| G13 | Advance not usable at POS; advances not reconciled per customer | Cashier needs two steps, mistakes create G03 | M | C44, C45 | Add advance as payment source in `record_sale2` (creates the cust_advance_used move atomically); add 2300 per customer to `acct_reconcile` | M | G03 |
| G14 | Journal has no cashier / shift dimension | Cannot prove per-cashier cash from the ledger | L | C16, PC1 | Put `source_staff`/`shift` on journal lines or entries from the source document at posting time | M | G02 |
| G15 | Payments cannot be back-dated (supplier payment, collection) | After-midnight entry lands on the next day, day book disagrees with paper | L | C48 | Optional `p_date` with `lock_check` and reason | S | - |
| G16 | Rounding drift in COGS at 3+ decimal cost | 0.17 per 50 sales, shows as unexplained in `inventory_vs_gl` | L | C08, RD1 | Post COGS from the exact ledger value (round once per day) or post a daily rounding entry to 5140 | S | - |
| G17 | GL may be stale (scheduler off) while reconciliation views read only posted entries | Owner reads a "difference" that is only pending documents | L | C57, ST1 | Show `pending` count inside `acct_reconcile` and the accounts screen header; recommend scheduler on | S | - |
| G18 | `vat_report` bucket uses `created_at::date` (session zone) | Month edge returns attributed to wrong month if session is UTC | L | C55 | Use `(created_at at time zone 'Asia/Dhaka')::date` | S | - |
| G19 | No single "close the day" reconciliation screen | Owner has seven separate tools; nothing says "today ties out" | M | section 4 | One RPC `day_close_report(loc, date)`: sales by mode, payments, refunds, expenses by mode, deposits, card/wallet/bank movements, counted cash, GL movement, differences, open items | L | G01, G02, G05 |
| G20 | Expenses are cash-basis only (no unpaid voucher / accrual) | Payables for expenses (rent, utilities) invisible | L | section 3 | Pay later flag on 10-2 posting to 2400 then payment doc | M | policy decision |

## 6. Suggested priority (input to stage 3)

1. Fast, no migration risk: G09, G05, G18, G16, G17 (defaults and view fixes). Also turn on `card_settle_over_mode` (G06 part) and `bank_recon_on` in the setup advisor.
2. Control holes: G03, G04, G01 (with G02 design) - these can make cash or receivables wrong without a visible signal.
3. Reporting integrity: G07, G06, G08, G10.
4. Feature work: G02/G19 (day-close screen), G11, G12, G13, G14, G20.

## 7. How the evidence was produced

- `a4_01_day.sql`: users, items, openings, one business day, posting. `a4_02_checks.sql`: hand-computed expectations E1, sub-ledgers R1, payments P1-P3, time zone T1, day book D1/D2, drawer W1, reports. `a4_03_mutations.sql`: bank statement B*, card C*, collections V*, voids, double posting J*, manual journal M1, period lock L*, rounding Q*. `a4_04_rounding_pending.sql`: RD*, ST*, PC*. `a4_05_billpay.sql`: BP*, EX*, summary.
- Expectations were computed by hand before the first run (comments at the top of `a4_02_checks.sql`). In the first run several of my own expectations were wrong (for example: `record_sale2` is already guarded by `sales_lock`; `void_sale` refuses a sale with returns; my first check of customer receivable mixed in the 2300 lines) and were corrected from the code, not from the output.
- A6 Not re-run in this audit: `tests/sql/e2e/07_reports.sql` (quick expense + form 10-2 counted once) and phase95 drawer UI; their result is taken from the repository tests. Void in a closed period for a non-owner is shown by code (`sales_lock` fires on UPDATE with `old.sale_date`), because the fixture user has no `sale_void` grant.
- All numbers are in BDT, no real names are used (fixtures: Owner, Seller, Buyer, Cust One, Cust Two, Sup A4).
