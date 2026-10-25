# Form to ledger to report linkage audit

Status: read-only code audit. No code, SQL or database was changed or written to. Live switch values were **not** read; every default below is the default in the code.
Tags: `[verified]` = read in code, file and function cited. `[not found]` = searched, absent. `[unverified]` = could not confirm without the live database or a test run.
No demo file was used as evidence (`docs/demo/` is fictional). Gap ids G1 to G15 are defined in `docs/BUILD_PLAN_GAPS.md`; new ids start at G16.
`supabase/phase80.sql` is being written by another builder on this branch right now (opening balance, owner approval modes). It is **not** audited here. Anything it adds is out of scope, except where it touches G3 or G15.

## 0. The question and the short answer

Question: does every form entry (all 42 paper-form codes, plus ITEMS, ITEM_COST and POS) and every dedicated screen connect to the ledgers and the reports?

Short answer: **No.** Only the dedicated screens (POS, purchase, dues, returns, cash moves, quick expense, production run, wastage, app payroll payments, partner capital) reach the stock ledger and the journal. Of the 42 paper forms, only 10-2 (expense voucher) reaches the journal. Five stock forms (04-1, 04-2, 04-3, 03-1, 05-1) can reach the stock ledger, but only when a master switch is ON (default OFF) and never reach the journal. The rest are saved as records (`entries`) and some are read by reports. Most money fields on paper forms are typed by hand and are never compared with what the system already knows.

### 0.1 How the data flows (verified)

| Layer | What it is | Written by | Read by |
|---|---|---|---|
| `entries` (form records, `data` json) | Every paper form, saved by `save_entry`, `submit_entry`, `decide_entry` (`web/entry.js`) | The form screens | Day book, some reports, exceptions, compliance. **Not** the stock ledger or journal, except the cases below |
| `stock_ledger`, `stock_balance`, `stock_batches` | Append-only stock truth | `stock_post` called by sale trigger, purchase, stock screens, production, and (switch ON) `entry_post_ledger` | Stock screens, K3 report, COGS in P&L |
| Operational tables (`sales`, `sale_payments`, `sale_returns`, `purchase_bills`, `supplier_payments`, `cash_moves`, `quick_expenses`, `payroll_*`, `employee_advances`, `partner_capital`, `production_runs`, `stock_wastage`) | Dedicated screens | RPCs from `web/*.js` | Day book, reports, and the journal scanner |
| `journal_entries`, `journal_lines` | Double-entry books | **Only** the scanner `_acct_docs` called by `acct_post_pending` (and manual `acct_journal_post`, `acct_opening`, year close, depreciation) | `web/accounts.js` (trial balance, balance sheet, income statement, cash flow, ledgers), `daybook_vs_journal`, `inventory_vs_gl` |

Key facts:

1. The journal is **derived**. `_acct_docs` (latest body `supabase/phase79.sql`) has exactly these sources: `sale`, `sale_return`, `collection`, `purchase`, `supplier_payment`, `supplier_refund`, `expense_voucher` (form 10-2), `quick_expense`, `cash_move`, `wastage`, `production`, `payroll_payment`, `staff_advance`, `partner_capital`. Nothing else posts. [verified]
2. Journal posting is off by default: rule `accounting_on` default false, `accounting_start_date` default empty (`supabase/phase40.sql`, rules insert). [verified]
3. Journal posting is **not** triggered by the database. `acct_post_pending` is called only from `web/accounts.js` (`autopost()` when an authorised user opens `#/accounts`, and the "Post now" button). No `pg_cron`, trigger or edge job was found in `supabase/` or `web/`. [verified, `[not found]` for any scheduler]
4. The five forms that can post to the stock ledger are fixed in `public._elp_enabled`: 04-1, 04-2, 04-3, 03-1, 05-1 (`supabase/phase20.sql`). Trigger `entries_post_ledger` (AFTER UPDATE on `entries`, when status becomes `approved`) calls `entry_post_ledger` (latest body `supabase/phase51.sql`). [verified]
5. Stock-form posting needs master rule `forms_post_to_ledger` (default **false**, `supabase/phase20.sql`) **and** a per-form row in `forms_ledger_cfg` (default `is_on = true`).
6. Even with the master ON, a stock form posts only if its path domain is `primary = b` (`supabase/phase48.sql path_cfg`, `supabase/phase51.sql _elp_post_line`). Domains `stock_issue`, `stock_transfer`, `stock_count`, `production` have default primary `a` (the screen), but `legacy_rule = 'forms_post_to_ledger'`: while that rule is ON the default primary becomes `b`. So turning the master ON also **locks the screens** for those four actions (`_stock_ledger_path_guard51` raises `path_locked`). See G33.
7. Journal entries from stock forms: **none**. `entry_ledger_posts` rows carry `ref_type 'entry'`; `_acct_docs` reads stock rows only for `sale`, `sale_pack`, `sale_return`, `wastage` and `production` refs. [verified]

### 0.2 Status labels used in the matrix

| Label | Meaning (judged on the code path, with the intended switches ON) |
|---|---|
| LINKED | Every money, quantity or status group is read or posted by a ledger, the journal or a report of record with no re-typing. Or the fact is carried by a dedicated screen that is linked end to end. |
| PARTIAL | At least one group is linked and at least one money/quantity group is not. Or the link exists only behind a default-OFF switch or a manual owner action. Or it reaches reports but no ledger. |
| REGISTER ONLY | Saved and listed. Money or quantity groups reach no ledger and no report except lists, exceptions or compliance counts. |
| PAPER ONLY BY DESIGN | No money, quantity or status that needs a ledger (policy, checklist, specification, HR document). |

Default state of the switches is shown in its own column. Where the intended switch is OFF by default, the status is still judged with it ON, and the default is flagged.

## 1. Matrix

Columns: Sales | Inv(entory) | Prod(uction) | Cash | Journal | Report(s) | Switch and default | Status | Evidence. "-" means the form has no such group. "no" means the group exists on the form and nothing reads it.

Abbreviations. `DB` = `_daybook_lines` family (`supabase/phase50.sql`, `phase13.sql _daybook_lines12`, `phase42.sql _daybook_lines23`). `PL` = `_p27_pl` (`supabase/phase72.sql`). `ELP` = `entry_post_ledger` / `_elp_post_line` (`supabase/phase51.sql`). `PS` = switch `forms_post_to_ledger` default OFF. `AO` = rule `accounting_on` default OFF.

### 1.1 Paper forms and the item pseudo-forms

| Code | Sales | Inv | Prod | Cash | Journal | Report(s) | Switch and default | Status | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| ITEMS | price list used by POS | item must be tracked for stock | recipes use items | - | - | all item/stock reports | item change needs approval (`itemreq`) | LINKED | `web/items2.js submit_item_change`, `web/itemmaster.js item_apply` |
| ITEM_COST | COGS fallback | stock value | recipe cost | - | via `cogs` only when ledger cost is absent | L1, L2, L3 (`_cogs_lines72` fallback) | cost right (`_cost_ok`) | LINKED | `supabase/phase72.sql _cogs_lines72` |
| POS | sale, dues, discount, receipt | `sale_out` by trigger | - | `sale_payments` by mode | source `sale` (Dr pay_*, receivable, sales_discount; Cr sales; Dr cogs / Cr inv_*) | day book, `biz_*`, report engine 1/2/3, owner board | AO OFF, start date empty | LINKED | `web/pos.js record_sale2`; `supabase/phase10.sql _sale_stock_out`; `phase79.sql _acct_docs[sale]` |
| 0-1 | - | - | - | `drawer_float`, `imprest`, `cash_tol`, limits | - | forms read limits through `get_limit`; PL reads `fixed_cost_month` | owner or head management approves sheet | LINKED (config) | `web/locations.js sheet_approve`; `supabase/phase72.sql _p27_pl` |
| 01-1 | typed sales, discount, online | typed wastage, jalebi/chhana gaps | - | typed `cash_so`, receivable, supplier_due | no | none [not found] | rollout mode only | REGISTER ONLY | `web/forms_sales.js` form 01-1; no SQL reader |
| 01-2 | typed sales, purchases, discount | typed open/close stock | - | typed salary, bank charges, cash short | no | L4 `l4_owner_sheet` compares it with the computed P&L | cost right, owner only | PARTIAL | `supabase/phase27.sql _r3q_l4_owner_sheet` |
| 02-1 | - | - | - | typed temp `wage` | no | `salary_report`, attendance_summary; feeds `attendance_days` | path `attendance`, default primary = punches; the form becomes a locked shadow | PARTIAL | `supabase/phase54.sql attendance_form_link_run`; `phase13.sql salary_report` |
| 02-2 | - | - | - | receipts `net` in DB (non-shadow) | **no** source for the form | PL salary (`sa` CTE), `salary_report`, T3, T4 | path `payroll`, default primary = app payroll; form = locked shadow | PARTIAL | `supabase/phase50.sql _payroll_entry_link50`; `phase72.sql _p27_pl[sa]`; `phase52.sql` header "salary_form day-book-only" |
| 02-3 | - | - | - | adv lines in DB | **no** source for the form | `salary_report`, T3 | none; `employee_advances` mode `none` means "already on 02-3" | PARTIAL | `supabase/phase50.sql _daybook_lines`; `phase42.sql _daybook_lines23` comment |
| 02-4 | - | - | - | - | - | - | - | PAPER ONLY BY DESIGN | `web/forms_staff.js` 02-4 (terms and duties) |
| 02-5 | - | - | - | - | - | none [not found]; the app has its own `leave_request_save` | - | REGISTER ONLY | `web/attendance.js leave_request_save`; no SQL reader of 02-5 |
| 02-6 | - | - | - | typed `final_due`, `abs_adv`, `notice_ded` | no | none [not found]; app has `payroll_settlement_preview` | - | REGISTER ONLY | `web/payroll.js payroll_settlement_preview` |
| 02-7 | - | - | - | - | - | - | - | PAPER ONLY BY DESIGN | `web/forms_staff.js` 02-7 |
| 02-8 | - | - | - | - | - | - | - | PAPER ONLY BY DESIGN | `web/forms_staff.js` 02-8 |
| 03-1 | - | `transfer_out` / `transfer_in` via ELP | - | `cash_amount` typed, no | none (transfer is company-neutral; short is G6) | K2, K3, `transfers_gap` | PS OFF; path `stock_transfer` default a (screen) | PARTIAL | `supabase/phase51.sql _elp_post_line[transfer]`; `phase48.sql path_domains` |
| 04-1 | - | `purchase_in` via ELP **skipped** by default (`covered_by_purchase_page`) | - | `cash_amount` typed, no | none (the purchase bill posts) | P2, P4, P5, P6, batch/expiry (`grn_batch_add`) | PS OFF; rule `grn_receipt_source` default `purchase` | PARTIAL | `supabase/phase51.sql _elp_post_line`; `phase23.sql` rule; `phase60.sql grn_batch_add` |
| 04-2 | - | `issue_out` via ELP | - | - | none | K3 | PS OFF; path `stock_issue` default a | PARTIAL | `supabase/phase51.sql _elp_post_line[out]` |
| 04-3 | - | `count_adjust` via ELP (delta against book on sheet) | - | - | none | K2 variance | PS OFF; path `stock_count` default a; blind count | PARTIAL | `supabase/phase51.sql _elp_post_line[count]`; `phase26.sql _r3q_k2_count_variance` |
| 04-4 | - | read view of `stock_ledger_rows` only when master ON | - | - | - | the view itself | PS OFF = typed paper ledger | PARTIAL | `web/forms_stock.js viewStoreLedger`, `LS.master` |
| 05-1 | - | `production_in` + batch via ELP (output lines only) | **no ingredients, no cost** on the sheet | - | none | F1, F2, F4, Q1, Q2 | PS OFF; path `production` default a (recipe run) | PARTIAL | `supabase/phase20.sql _elp_lines[05-1]`; `phase26.sql _r3q_f1_production` |
| 05-2 | - | - | spec only | - | - | - | - | PAPER ONLY BY DESIGN | `web/forms_factory.js` 05-2 |
| 05-3 | - | - | typed ingredient qty and steps | - | - | none [not found]; real recipe is `recipe_lines` | - | REGISTER ONLY | `web/recipes.js recipe_save` |
| 05-4 | - | - | yield inputs/outputs | - | - | F2; suggestion only | - | PARTIAL | `supabase/phase74.sql recipe_yield_suggestion`; `phase26.sql _r3q_f2_yield` |
| 05-5 | est price, sold qty | - | trial | - | - | none | - | PAPER ONLY BY DESIGN | `web/forms_factory.js` 05-5 (decision sheet) |
| 06-1 | - | typed need and stock | - | typed `adv_given`, rates | no | none [not found]; `reorder_report` is separate | - | REGISTER ONLY | `supabase/phase60.sql reorder_report` |
| 06-2 | - | - | - | typed quote rates | no | none [not found] | - | REGISTER ONLY | `web/forms_stock.js` 06-2 |
| 06-3 | - | - | - | PO totals | no; there is no PO table [not found] | P5 open POs (`_p26_po`) | - | PARTIAL | `supabase/phase26.sql _p26_po` |
| 06-4 | - | short/return qty typed | - | `pay_amount` typed; creates no payment | no | P4, P5 (`bil` CTE) | - | PARTIAL | `supabase/phase26.sql _p26_po` |
| 06-5 | - | - | - | typed bill/debit/pay lines | read view of `supplier_ledger` only when master ON | the view | PS OFF = typed paper ledger | PARTIAL | `web/forms_stock.js viewSupplierLedger` |
| 08-1 | - | - | breakdown record | `est_cost`, `actual_cost` typed | no | F4; optional `assets.maintenance_ref` | - | PARTIAL | `supabase/phase14.sql asset_add`; `phase26.sql _r3q_f4_breakdowns` |
| 10-1 | - | - | - | handover = count - float, DB line `internal` | **no** source (hub half also missing) | DB (internal), W2 handover vs hub, dup_suspects D8 | blind count; no switch | PARTIAL | `supabase/phase50.sql _daybook_lines[10-1]`; `phase25.sql _r3q_w2_handover_vs_hub`; `phase52.sql` header "NOT done" |
| 10-2 | - | - | - | DB out/cash; imprest fields typed | source `expense_voucher`: Dr `exp_<head>`, Cr `pay_cash` (approved only) | DB, PL (`ex`), E2, E3, `expense_by_head` | path `expense` default a; AO OFF; shadow of quick expense excluded | LINKED | `supabase/phase79.sql _acct_docs[expense_voucher]`; `phase72.sql _p27_pl[ex]` |
| 10-3 | - | - | - | typed digital differences | no | none [not found]; `payment_recon` (phase62) is provider-based and separate | - | REGISTER ONLY | `supabase/phase62.sql payment_recon` |
| 10-4 | - | - | - | typed hub cash, bank, mobile, recv, pay | no | P6 reads the budget part | - | PARTIAL | `supabase/phase26.sql _r3q_p6_purchase_budget` |
| 10-5 | typed receivable aging | - | - | typed advances | no | none [not found]; system has `customer_dues` and `customer_advances` | - | REGISTER ONLY | `web/dues.js customer_dues` |
| 11-1 | - | typed pending/short qty | - | typed `cash`, `shop_cash` | no | none [not found] | - | REGISTER ONLY | `web/forms_staff.js` 11-1 |
| 14-1 | typed totals by category, online, party, dues, refund, credit, discount | typed closing stock, waste, own use, samples | - | typed digital split, hub deposit, cash count | no | `cash_short_over` report (flags), E3, Q1, Q2, X4 compliance, digest, notify | blind cash count; AO n/a; **no** server compare with POS | PARTIAL | `web/forms.js` 14-1 `calc`; `supabase/phase21.sql report_run2[cash_short_over]`; `phase18.sql _count_inputs18` |
| 14-2 | typed `jalebi_sales` | typed flour/sugar/oil, unsold | typed batch use | `old_oil_amt` typed | no | none [not found] | - | REGISTER ONLY | `web/forms_cash.js` 14-2 |
| 18-1 | - | - | - | `amt` by source (imprest/bank/card/mobile/owner) | no | E4 limit, M2 vs sales | - | PARTIAL | `supabase/phase25.sql _r3q_e4_marketing_limit`; `phase26.sql _r3q_m2_marketing_vs_sales` |
| 20-1 | typed order, `advance`, `due_paid` | - | - | advance typed, no | no | S10 orders; owner may link to a sale | `sale_forms_link_on` OFF | PARTIAL | `supabase/phase25.sql _r3q_s10_orders`; `phase61.sql sale_form_link` |
| 20-2 | discount typed | - | - | - | no | none [not found] except the link tool; `discounts_report` reads `sales` | `sale_forms_link_on` OFF | PARTIAL | `supabase/phase61.sql unlinked_sale_forms`; `phase20.sql discounts_report` |
| 20-3 | `refund_amt`, return qty | typed qty, no restock | - | refund typed | no | Q3 complaints | - | PARTIAL | `supabase/phase26.sql _r3q_q3_complaints`; real return is `sale_return` |
| 20-4 | party invoice typed | - | - | `cash_today`, `prev_dues` typed | no | none [not found]; owner may link to a sale | `sale_forms_link_on` OFF | PARTIAL | `supabase/phase61.sql sale_form_link` |
| 20-5 | typed ledger | - | - | typed `coll` | no | none [not found]; system has `customer_ledger` | - | REGISTER ONLY | `web/dues.js customer_ledger` |
| 20-6 | typed online/delivery lines | - | - | `amt`, `dcharge` typed | no | S10 orders | `online_orders_on` OFF | PARTIAL | `supabase/phase25.sql _r3q_s10_orders` |

Counts for 1.1 (45 rows): LINKED 5, PARTIAL 24, REGISTER ONLY 11, PAPER ONLY BY DESIGN 5.

### 1.2 Dedicated screens (routes in `web/ia.js`)

| Screen (route) | Sales | Inv | Prod | Cash | Journal | Report(s) | Switch and default | Status | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| `items`, `items/new`, `lists`, `settings2/units`, `itemimport`, `itemmap`, `bulkitems`, `itemtypes` | price | tracked flag, unit factors | recipe items | - | `item_type` drives inventory account split | all item reports | approval of changes | LINKED | `web/itemmaster.js`, `bulkitems.js`; `phase72.sql _acct_inv_split72` |
| `stock` opening (`stock_opening`) | - | `opening` row, unique per item+place | - | - | **none** (phase80 in progress, not audited) | `inventory_vs_gl` shows the gap | cost right | PARTIAL | `supabase/phase10.sql stock_opening` |
| `stock` manual issue (`stock_issue`) | - | `issue_out`, ref `issue` | no run, no cost line | - | **none** | K3 | path `stock_issue` | PARTIAL | `supabase/phase10.sql stock_issue` |
| `stock` transfer and transit (`stock_transfer`, `stock_receive_transfer`) | - | out and in, short raises `transit_short` | - | - | none (neutral) ; short is G6 | transfers_gap | path `stock_transfer` | PARTIAL | `supabase/phase10.sql stock_receive_transfer` |
| `stock` count adjust (`stock_count_adjust`) | - | `count_adjust` | - | - | **none** (loss never reaches P&L) | K2, exceptions `stock_count_variance` | tolerance rule `count_tolerance_pct` | PARTIAL | `supabase/phase10.sql stock_count_adjust` |
| `stock` wastage and expire (`stock_wastage`, `stock_expire_batch`) | - | `wastage` | - | - | source `wastage`: Dr `wastage` / Cr `inv_*` | wastage_by_reason | approval limit rule `wastage_approval_limit` | LINKED | `supabase/phase12.sql`/`phase74.sql stock_wastage`; `phase79.sql _acct_docs[wastage]` |
| `stock` production without recipe (`stock_production_in`) | - | `production_in` + batch | no ingredients | - | **none** (no `production_runs` row) | K3 | `production_requires_recipe` | PARTIAL | `supabase/phase74.sql stock_production_in` |
| `stockx` (reorder, near expiry, QC, FEFO, GRN batch) | - | batches, QC status | QC of runs | - | - | read only | `quality_block_on` OFF | PARTIAL | `supabase/phase60.sql qc_record` |
| `assets` (asset register) | - | - | - | no cost field | none | F4 | - | REGISTER ONLY | `supabase/phase14.sql` table `assets` (no cost, no link to `fa_assets`) |
| `purchase`, `purchase/new`, `purchase/return` | - | `purchase_in` / `purchase_return`, batch aware | - | via payment | source `purchase`: Dr `purch_*`, Cr `payable` | P2, P4, P6, payables | AO OFF | LINKED | `web/purchase.js post_purchase`; `phase79.sql _acct_docs[purchase]` |
| `payables`, supplier payments and refunds | - | - | - | `supplier_payments` | sources `supplier_payment`, `supplier_refund` | DB, payables_summary | AO OFF | LINKED | `web/purchase.js pay_supplier`; `phase79.sql` |
| `recipes` (recipe run) | - | ingredients `issue_out`, finished `production_in` | cost, yield, conversion | - | source `production` (Dr `inv_finished`, Cr `inv_*`, Cr `overhead_absorbed`) | F1-F3, production_run_costs | `recipe_approval` OFF; `production_requires_cost` = warn | LINKED | `supabase/phase79.sql production_post`, `_acct_docs[production]` |
| `recipebook` | - | - | approval gate | - | - | - | gate OFF | PARTIAL | `supabase/phase74.sql _recipe_gate73` |
| `costing` (conversion cost, pools) | - | - | conversion cost into run | - | only through `production` Cr `overhead_absorbed`; true-up variance not posted | production_run_costs, `overhead_trueup` (read-only) | conversion mode OFF | PARTIAL | `supabase/phase74.sql overhead_trueup` (stable, no insert) |
| `costsources`, `costattrib` (cost bills, shares) | - | - | factory shares into pools | **no payment, no payable** | **none** (`cost_bill_creates_payment` not built) | branch P&L rows only if `cost_attrib_in_pl` | `cost_attrib_in_pl` OFF | PARTIAL | `supabase/phase78.sql` header "NOT built"; `phase75.sql cost_bill_add` |
| `pos` | yes | yes | - | yes | yes | yes | AO OFF | LINKED | see POS row |
| `salereturn` | `sale_returns` | `sale_return` restock | - | refund by mode | source `sale_return` | DB (`_daybook_lines12`), PL nets returns (`reports_net_of_returns` ON) | AO OFF | LINKED | `supabase/phase12.sql sale_return`; `phase79.sql` |
| `dues` | collection | - | - | `sale_payments` kind collection | source `collection` | customer_dues, DB | AO OFF | LINKED | `web/dues.js collect_payment` |
| `customers`, `tiers` (points, gifts) | redeem returns a taka value, **not** tied to a sale | - | - | - | none (no points liability) | tier_usage_report | `loyalty_points_on` | PARTIAL | `supabase/phase43.sql customer_points_redeem` |
| `onlineorders` | `record_sale2` at delivery | via sale trigger | - | `advance` is a column until delivery; cancel fate creates no cash row | via the sale only | S10 | `online_orders_on` OFF | PARTIAL | `supabase/phase61.sql online_order_deliver`, `online_order_cancel` |
| `saleforms` | links 20-1/2/4 to a sale | - | - | - | - | `unlinked_sale_forms` | `sale_forms_link_on` OFF | PARTIAL | `supabase/phase61.sql sale_form_link` |
| `daybook` | reads sales | - | - | reads all cash/bank/mobile rows | compared by `daybook_vs_journal` | the day book | opening typed by hand (`set_daybook_opening`) | LINKED | `supabase/phase50.sql _daybook_lines`; `phase49.sql daybook_vs_journal` |
| `cashmoves` | `cust_advance*` | - | - | bank deposit/withdraw, owner top-up/draw, hub receipt | source `cash_move` | DB | AO OFF | LINKED | `web/cashmoves.js cash_move_add`; `phase79.sql _acct_docs[cash_move]` |
| `quickexp` | - | - | - | `quick_expenses` | source `quick_expense` | DB, PL, E2 (not `expense_by_head`) | path `expense` | LINKED | `supabase/phase50.sql quick_expense_add` |
| `accounts` | - | `inventory_vs_gl` | - | cash accounts | the books themselves; posting only when the page is opened | trial balance, balance sheet, income statement, cash flow | AO OFF, start date empty | LINKED | `web/accounts.js autopost` |
| `finance2` | VAT report | - | - | bank recon (statement pasted by hand) | year close, depreciation post | vat_report, budget_vs_actual | `bank_recon_on`, `year_close_on`, `fixed_assets_on`, `budgets_on`, `vat_on` all OFF | PARTIAL | `supabase/phase53.sql` |
| `payroll` | - | - | - | `payroll_payments`, `employee_advances` | sources `payroll_payment`, `staff_advance` (cash basis) | DB, **not** PL / `salary_report` / T3 | AO OFF; path `payroll` default app | PARTIAL | `supabase/phase79.sql _acct_docs[payroll_payment]`; `phase72.sql _p27_pl[sa]` |
| `attendance`, `attend2`, `leave` | - | - | - | feeds payroll calc | - | attendance_summary | `app_punch_on` OFF | LINKED | `supabase/phase42.sql` (payroll reads `attendance_days`) |
| `employees` | - | - | - | pay terms feed payroll | - | - | - | LINKED | `web/employees.js employee_pay_set` |
| `salary` (salary report) | - | - | - | forms 02-1/02-2/02-3 only | - | itself | `salary_view` grant | PARTIAL | `supabase/phase13.sql salary_report` |
| `partners` | - | - | - | `partner_capital` | capital kinds post; **settlement approve/pay post nothing** (G8) | `partner_party_statement` | AO OFF | PARTIAL | `supabase/phase52.sql` source `partner_capital`; no settlement source in `_acct_docs` |
| `reports`, `biz`, `brandpnl`, `discounts`, `report` | reads | reads | reads | reads | - | computed on open from live tables | cost right for cost columns | LINKED | `supabase/phase24.sql report_run3`; `phase9.sql report_run` |
| `parallel`, `comparison_*` | paper vs app figure per day | - | - | - | - | month-end pass or fail | `parallel_compare_on` ON | PARTIAL (manual compare, typed by two people) | `supabase/phase28.sql comparison_days` |
| `printbooks` | - | - | - | - | - | gap/overlap of paper serials | - | PAPER ONLY BY DESIGN | `supabase/phase28.sql paper_books_check` |
| `ledgerlinks`, `paths`, `switchboard`, `rulehub`, `rollout` | - | - | - | - | - | show switches and retry list | the switches themselves | control screens (see 1.3) | `web/forms_stock.js` (ledgerlinks), `supabase/phase48.sql path_switches` |

Counts for 1.2 (34 rows with a status): LINKED 15, PARTIAL 17, REGISTER ONLY 1, PAPER ONLY BY DESIGN 1, plus 1 row of control screens that carry no money fact (not counted).

Grand total for 1.1 + 1.2 (79 counted rows): **LINKED 20, PARTIAL 41, REGISTER ONLY 12, PAPER ONLY BY DESIGN 6.**

### 1.3 Routes that carry no money, quantity or status fact (not counted)

`home`, `exceptions`, `pending`, `itemreq`, `releases`, `emergency`, `changes`, `numaudit`, `outbox`, `staff`, `matrix`, `locations`, `locset`, `locsheet`, `control`, `owner`, `delegation`, `flow`, `deeds`, `notifications`, `assistant`, `rules`, `settings`, `settings2`, `logs`, `backup`, `integrations`, `restoredrill`, `twofa`, `inbox`, `benefitsx`, `biexport`, `invoice`, `eqcheck`. These read, approve, configure or print. They write no ledger line. `[verified]` by their RPC list (`grep` of `rpc(` in each file).

### 1.4 Report and dashboard sources (what reads what)

| Report or dashboard | Reads | Journal? |
|---|---|---|
| Day book (`day_book`) | `sale_payments`, `supplier_payments`, form 10-2 (submitted or approved, non-shadow), form 10-1 (internal), form 02-3 and 02-2 receipts, `sale_returns`, `supplier_refunds`, `cash_moves`, `payroll_payments`, `employee_advances`, `quick_expenses` | No. Compared with the journal by `daybook_vs_journal` |
| Accounts screens (`acct_*`) | `journal_entries`, `journal_lines` | Yes |
| Report engine 1 (phase9: sales summary, trend, items, categories, receipts, hour/weekday, retail/wholesale, discounts) | `sales`, `sale_payments` | No |
| Report engine 2 (phase21: item_slow, stock_low, stock_balance, wastage, expiry_soon, transfers_gap, supplier_ageing, purchases_by_supplier, expense_by_head, cash_short_over, attendance_summary, exceptions_summary) | stock tables, purchases, form 10-2 (no quick expenses, no shadow filter), form 14-1 flags, attendance | No |
| Report engine 3 (phases 24 to 28, 70+: S10, D5, M1, X2-X5, G2, K2, K3, E2-E4, W1, W2, P2, P4-P6, F1-F4, M2, Q1-Q3, L1-L5, T3, T4) | `sales`, `entries` (named forms), `stock_ledger`, `purchase_bills`, `cash_moves` (W1) | No |
| P&L L1 / L3 / L5 (`_p27_pl`) | `sales`, `sale_returns`, `stock_ledger` cost, form 10-2 + `quick_expenses`, **form 02-2 only** for salary, `location_settings.fixed_cost_month` | No |
| Owner board, dash, home (`ownerboard.js`, `dash.js`, `nav.js`) | counts of `entries` by status and form, `sales_summary`, `customer_dues`, `payables_summary`, `stock_levels` | No |

`[verified]` from the function bodies cited in section 1.1.

## 2. Every REGISTER ONLY and PARTIAL item: what is disconnected, what a connection must do

Journal accounts use the mapping keys of `_acct_docs` (`pay_cash`, `pay_bank`, `pay_card`, `pay_mobile`, `receivable`, `payable`, `salary_exp`, `staff_advance`, `hub_clearing`, `cust_advance`, `inv_raw`, `inv_pack`, `inv_finished`, `wastage`, `overhead_absorbed`, `owner_capital`, `owner_drawings`, `exp_<head>`). A new key must be added in `acct_mappings` before use. Cash short/over account 5800 exists but has no mapping key [verified, `docs/BUILD_PLAN_GAPS.md` section 1].

### 2.1 Forms

| Item | Disconnected | A connection must do | Gap |
|---|---|---|---|
| 01-1 | Every money figure is typed by hand | Prefill from system (sales, discount, wastage, receivable, supplier dues); show difference | G20 |
| 01-2 | Typed P&L; only L4 compares it | Keep L4. Add prefill from L1; no ledger line | G20 |
| 02-1 | Temp `wage` typed, not in day book or journal | Temps paid in cash: record as `quick_expense` head labour (Dr `exp_labour`, Cr `pay_cash`) or refuse | G31 |
| 02-2 | No journal source. PL reads this form but not app payroll | If form is primary: source `payroll_form` Dr `salary_exp` (net + advance deduction), Cr `pay_*` by receipt method, Cr `staff_advance` for deduction; skip when shadow. PL must read app payroll too | G17, G16 |
| 02-3 | No journal source; may double with `employee_advances` | Source `staff_advance_form` Dr `staff_advance`, Cr `pay_*`; refuse a second record for the same person, date, amount | G17 |
| 02-5 | App leave module and the form are two records | Link by form serial in `leave_request_save` or lock one path | G31 |
| 02-6 | Final settlement money typed; app has `payroll_settlement_preview` | Fill from preview; post through payroll payment, not by form | G31 |
| 03-1 | Off by default; `cash_amount` typed; transit short has no claim | Keep stock posting. `cash_amount` must become a supplier or cash record. Short: G6 | G24, G6, G33 |
| 04-1 | Skipped by default; `cash_amount` not read | Keep the skip rule (it prevents double count). Link cash paid to `supplier_payments.ref_entry` | G24 |
| 04-2 | Off by default; no journal for `issue_out` of ref `entry` | Journal source on `stock_ledger` id: Dr consumption or WIP (owner account), Cr `inv_raw` or `inv_pack` at ledger cost | G18 |
| 04-3 | Off by default; `count_adjust` has no journal | Loss: Dr stock count loss, Cr `inv_*`. Gain: Dr `inv_*`, Cr stock count gain. Report must read it (L1, `inventory_vs_gl`) | G18 |
| 04-4 | Typed paper ledger while master OFF | Make the read view the default view with an "enter on paper" link, or prefill balance from `stock_balance` | G20 |
| 05-1 | Finished goods only; no ingredients, no cost; off by default | Keep as reference when a recipe run exists. If sheet is primary, require ingredient lines or a linked recipe run; cost = recipe cost | G33, G10 |
| 05-3 | Typed recipe differs from `recipe_lines` | Show the live recipe next to the card, or draft a recipe from the card for approval | G32 |
| 05-4 | Yield only suggests; no variance posting | Keep (decision data). Show F2 yield variance in the run screen | none |
| 06-1, 06-2 | Quantities and rates typed; no link to reorder or purchase | Prefill 06-1 from `reorder_report`; save the chosen quote rate into the purchase bill | G24 |
| 06-3 | PO exists only as a form; P5 matches paper only | Add `purchase_bills.po_ref`; P5 counts bills from the purchase screen | G24 |
| 06-4 | Payment request creates no payment; bill amount not compared with the posted bill | Approved 06-4 creates a pending payment line in `purchase.js`; payment stores `entry_ref` | G24 |
| 06-5 | Typed while master OFF; master dues typed | Show `payables_summary` next to `master`; flag a difference | G20 |
| 08-1 | `est_cost`, `actual_cost` typed; not posted | Repair paid in cash: through a quick expense linked to the 08-1 serial (Dr `exp_repair`, Cr `pay_*`). Asset link exists | G27 |
| 10-1 | No journal source. Hub half is a separate manual `cash_move` | Showroom half: Dr `hub_clearing` (1230), Cr `pay_cash` at the showroom on approval, amount = counted minus float. Hub receipt then clears 1230. Difference to 5800 (G4) | G19, G4 |
| 10-3 | Digital differences typed | Compare `sale_payments` (mobile, card) by wallet with the typed phone totals; flag difference (G9 `wallet_reconcile`) | G9, G20 |
| 10-4 | Hub cash, bank, mobile typed | Prefill from journal balances of `pay_cash`, `pay_bank`, `pay_mobile`; flag difference | G20 |
| 10-5 | Receivable and advance aging typed | Prefill from `customer_dues` and `customer_advances`; flag difference | G20 |
| 11-1 | Cash and pending qty typed, unread | Optional: compare `cash` with the 10-1 slip of the same shift. Else keep as register | G20 |
| 14-1 | All sales, digital, dues, refund, credit totals typed; only arithmetic check | Server function `sheet_vs_system(entry)`: compute total sales, by mode, returns, collections, credit from `sales`, `sale_payments`, `sale_returns`, `cash_moves` for the place and day; raise exception `sheet_system_gap` using existing limits `cash_tol`, `goods_money_tol_pct` | G20 |
| 14-1 stock table | `waste_qty`, `own_use`, `sample` typed, never posted | Compare with `stock_wastage` and manual issues of the day; flag difference (do not post twice) | G28 |
| 14-2 | Flour, sugar, oil, sales typed | Compare `jalebi_sales` with POS sales of the jalebi item; keep inputs as register | G20 |
| 18-1 | Spend by bank, card, mobile, owner is in no ledger or P&L; imprest spend could be typed twice | Source `marketing_expense`: Dr `exp_marketing`, Cr `pay_bank` / `pay_card` / `pay_mobile` / `owner_capital` by source. Imprest source: refuse if a 10-2 line with the same receipt exists | G26 |
| 20-1 | Advance and `due_paid` typed; only S10 reads it | Advance must exist as a `cust_advance` cash move (Dr `pay_*`, Cr `cust_advance`); link by order number | G22 |
| 20-2 | Discount slip not tied to the sale discount | Store slip serial on the sale; `discounts_report` shows the slip | G25 |
| 20-3 | Return register separate from `sale_return` | Require register serial in the return sheet; Q3 reads `sale_returns.reason` too | G25 |
| 20-4 | Party invoice typed apart from the sale | Link to a wholesale sale (sale type wholesale); or generate the invoice from the sale | G25 |
| 20-5 | Party ledger typed | Prefill from `customer_ledger`; flag difference | G20 |
| 20-6 | Online ledger typed; S10 reads it only | Compare with `online_orders` delivered that day | G22 |

### 2.2 Screens

| Screen | Disconnected | A connection must do | Gap |
|---|---|---|---|
| `stock` opening | No journal line | One opening entry: Dr `inv_*`, Cr 3100/3200 (phase80 is building this; not audited) | G3 |
| `stock` manual issue, count adjust, production without recipe | No journal line; shrinkage never reaches P&L | See 04-2, 04-3 above. Production without recipe: Dr `inv_finished`, Cr the same consumption account, cost from `p_unit_cost` | G18 |
| `stock` transfer | Transit short has no claim | G6 | G6 |
| `stockx` | QC and batch data not used by margin or P&L | Optional: QC reject to wastage. Keep read-only unless owner decides | none |
| `assets` | Register has no cost; `fa_assets` has cost; no link | Add `fa_assets.asset_id` (to `assets`) and the purchase line; one cost | G27 |
| `recipebook`, `costing` | Gates and conversion modes are OFF; true-up difference never posted | Owner enables per G10. True-up: Dr/Cr `overhead_absorbed` against actual overhead expense at month end | G10, G29 |
| `costsources`, `costattrib` | Bills create no expense, payable or payment | On bill save: Dr `exp_<type>` (or overhead pool), Cr `payable` or `pay_*`; avoid double with 10-2 (phase75 yellow flag only) | G29 |
| `customers` (points, gifts) | Redeemed value is a manual discount; no points liability | Redeem inside `record_sale2` as discount with a reference; optional accrual Dr marketing, Cr points liability | G23 |
| `onlineorders` | Advance is a column; cancel fate creates no cash row | On save: `cust_advance` cash move; on delivery: `cust_advance_used` (Dr 2300, Cr `receivable`) and no duplicate sale payment; on cancel refund: `cust_advance_refund`; fate `income`: Dr 2300, Cr other income | G22, G5 |
| `saleforms` | Owner links by hand; switch OFF | See 20-1, 20-2, 20-4 | G25 |
| `finance2` | All switches OFF; bank statement pasted by hand | Owner decision to enable; no code gap except automation of statement import (not in scope) | G11 |
| `payroll` | Journal on payment only; PL, salary report, T3, T4 do not read app payroll | PL, `salary_report`, T3, T4 must read `payroll_lines` / `payroll_payments` (non-shadow). Accrual is G1 | G16, G1 |
| `salary` | Reads forms only | Same as payroll | G16 |
| `partners` | Settlement approve and pay post nothing | G8 | G8 |
| `parallel` | Typed figures, two people | Fill the app figure from the server (`sheet_vs_system`) instead of typing | G20 |

## 3. Cases where the same fact can be counted twice

| # | Pair | What prevents it | Where it fails or is weak |
|---|---|---|---|
| D1 | Purchase screen and GRN 04-1 both add stock | Rule `grn_receipt_source` default `purchase`: GRN `in` lines are logged as `skipped / covered_by_purchase_page` (`phase51.sql _elp_post_line`). P2 rate trend counts a GRN only if no posted bill of the same item, place and supplier is within 3 days (`phase26.sql _p26_rates`) | If owner sets the rule to `grn` and keeps using the purchase page, only an advice `_ah('grn_double_count')` fires (`phase47.sql`). Nothing blocks it. The 3-day, supplier-name match is a heuristic |
| D2 | Stock screen and forms 04-2, 03-1, 04-3, 05-1 | Path switch: `_stock_ledger_path_guard51` refuses the screen when form is primary; `_elp_post_line` skips the form lines when screen is primary (`covered_by_screen`) | Turning on `forms_post_to_ledger` flips four domains to primary `b` through `legacy_rule` and locks the screens without a warning (G33) |
| D3 | Recipe run, 05-1 output, manual `stock_production_in` | Same guard (domain `production`) | Manual `stock_production_in` has no `production_runs` row, so it is outside the journal scanner and outside F1 run-vs-sheet match |
| D4 | App payroll and form 02-2 | Shadow engine: `_payroll_entry_link50` / `_payroll_run_link50` lock one side; DB and journal skip the shadow | `PL` salary and `salary_report` read form 02-2 with **no shadow filter**; they ignore app payroll. Result: P&L and journal can disagree, not double (G16) |
| D5 | Quick expense and form 10-2 | `quick_expense_close_day` builds one draft 10-2 as a locked shadow; `is_shadow` is excluded in DB, PL, journal (`phase50.sql`) | `expense_by_head` (report engine 2) has no shadow filter and no quick expenses (G21). Also DB and PL count 10-2 when *submitted*, the journal only when *approved* (timing, G21) |
| D6 | Partner capital and cash move `owner_topup` / `owner_draw` | `owner_money_link` joins them; shadow does not post (`phase51.sql`, `phase52.sql _shadowed52`) | Until the owner links them, both post. `dup_suspects` D4 lists suspects only |
| D7 | Staff advance: `employee_advances` and form 02-3 | `mode = 'none'` on the app record means "already on 02-3" (`phase42.sql _daybook_lines23` comment) | Pure discipline. If the user picks cash, both show in the day book. `dup_suspects` has no advance check [not found] |
| D8 | Attendance punches and form 02-1 | Shadow of a month the punch data holds (`phase54.sql attendance_count_once`) | Temp `wage` on 02-1 has no counterpart [not found] |
| D9 | Sale and forms 20-1 / 20-2 / 20-4 | Owner links form to sale; linked form is a locked shadow (`phase61.sql sale_form_link`) | The forms never post, so there is no double count. The risk is under-recording (advance, due paid) |
| D10 | Online order advance and a manual customer advance | `online_order_deliver` adds the order advance as a sale payment | If staff also records a `cust_advance` cash move at order time, the delivery payment counts the same money again. No guard [not found] (G22) |
| D11 | 10-1 handover slip and hub receipt cash move | Both are `internal` in the day book, so totals exclude them (`_daybook_lines`, `_daybook_lines23`); `dup_suspects` D8 lists pairs | In the journal only the hub half posts (Dr cash, Cr 1230). Cash is counted at the sale and again at the hub; 1230 carries a credit with no clearing entry (G19) |
| D12 | Cost bill (`costsources`) and a 10-2 voucher for the same bill | Yellow duplicate flag when place, month, head and amount match (`phase75.sql` header) | Flag only. Not blocked |
| D13 | Marketing 18-1 (source imprest) and 10-2 | None [not found] | 18-1 is not posted anywhere, so no double count today; after G26 it must refuse a match |
| D14 | Fixed asset: `assets` row, `fa_assets` row, purchase bill line | None [not found]. The three tables are unlinked | Cost can be typed three times (G27) |
| D15 | Wastage: `stock_wastage` and 14-1 `waste_qty` | Sheet is never posted | No double count; the sheet figure can silently differ (G28) |
| D16 | Return: `sale_return` screen, 14-1 `refund`, 20-3 `refund_amt` | Only the screen posts | Three typed copies can differ (G25) |
| D17 | Day book and journal | Both are derived from the same tables; `daybook_vs_journal` compares them | Needs accounting start date |
| D18 | Same business document posted twice to the journal | Unique `(source_type, source_id)` index `je_source_uq`; `_acct_need` reverses a voided source | A re-numbered 10-2 uses `id:rev_no` and is reversed then re-posted (`phase79.sql`) |

## 4. Prioritised build list (hand this to a builder)

Ground rules for the builder (from `docs/BUILD_PLAN_GAPS.md` section 1, still valid): next SQL number comes after the last file on the branch; `_acct_docs` is re-created by phases 40, 50, 52, 72, 74, 79, so one release must re-create it **once** from the phase79 body and add every new source in that single re-creation; every new switch defaults OFF; tests use `tt.chk`, `tt.err`, `tt.unbalanced_entries()`; no demo data.

Effort is in working days for one developer including SQL and web tests. All estimates are `[unverified]`.

### 4.1 Existing gaps this audit depends on (do not rebuild; ids from `docs/BUILD_PLAN_GAPS.md`)

| Order | Id | Why it matters here |
|---|---|---|
| 1 | G2 | Without `accounting_on` and a start date, every journal link below is dormant |
| 2 | G3 | Opening stock, cash and dues; being built (phase80, not audited) |
| 3 | G5 | Customer advance tests; needed by G22 |
| 4 | G4 | Cash short/over; pairs with G19 |
| 5 | G1 | Payroll accrual; pairs with G16 and G17 |
| 6 | G6, G8, G9, G10, G11, G12 | Unchanged |

### 4.2 New gaps

| Order | Id | Title | Effort (days) | Depends on | Owner decision? | Done when |
|---|---|---|---|---|---|---|
| 1 | G30 | Journal freshness. `acct_post_pending` runs only when an authorised user opens `#/accounts`. Add a server-side run (scheduled job, or a post when a source row is committed) plus a "last posted at" strip on Home | 2 | G2 | Yes: is a scheduler allowed on the hosting plan `[unverified]` | New sale appears in the journal with nobody opening Accounts |
| 2 | G16 | Reports blind to app payroll. `_p27_pl` `sa`, `salary_report`, `_r3q_t3_payroll`, `_r3q_t4_staff_cost_ratio`, `_r3q_l4_owner_sheet` read form 02-2/02-3 only. Add `payroll_lines` / `payroll_payments` (non-shadow) as the primary source, form as fallback when no run exists for that place and month | 3 | none | Yes: which month does a salary belong to (approved run month or paid date)? Same as Q1 in G1 | L1 salary equals the run; no double with an existing 02-2 shadow |
| 3 | G21 | Expense parity. `expense_by_head` (phase21) and E3 add `quick_expenses` and drop shadows; one rule for DB, PL and journal on "submitted vs approved" | 1.5 | none | Yes: count 10-2 when submitted or only when approved | Same total in day book, P&L and expense report for one day |
| 4 | G20 | Sheet-versus-system compare. New read function `sheet_vs_system(entry_id)`: for 14-1 and 10-1 compute system totals (sales, by mode, returns, collections, credit, hub sent) and write a red or yellow exception `sheet_system_gap` using existing tolerances (`cash_tol`, `goods_money_tol_pct`). Then add the same for 10-4, 10-5, 06-5, 20-5, 04-4, 01-1 (prefill and difference) | 6 | none | No (tolerances already exist as location settings). Prefill vs compare-only is a UI choice | A sheet with a wrong total raises a flag with no human compare |
| 5 | G19 | Handover showroom half. New `_acct_docs` source `cash_handover` from approved 10-1: Dr `hub_clearing`, Cr `pay_cash` (showroom location) for counted minus float; skip when the entry is a shadow; reverse on re-open | 3 | G2, G30 | Yes: amount = showroom count or hub-confirmed count (the other becomes the G4 difference) | 1230 returns to zero after hub receipts |
| 6 | G18 | Stock movements without a journal line. New sources: `stock_count` (Dr loss account, Cr `inv_*`; gain the reverse), `stock_issue` (Dr consumption or WIP, Cr `inv_raw`/`inv_pack`), `stock_manual_production` (Dr `inv_finished`, Cr consumption). Key on `stock_ledger.id`; include rows posted by forms (`ref_type 'entry'`) | 4 | G2, G3 | Yes: names of the loss, gain and consumption accounts | `inventory_vs_gl` unexplained difference falls to rounding |
| 7 | G17 | Form-path payroll and advance journal. Source `payroll_form` and `staff_advance_form` from approved 02-2 / 02-3 only when the form is the primary (path `payroll` set to `b`); otherwise refuse in the form screen when `accounting_on` | 2 | G2, G16 | Yes: allow form path at all once accounting is on? | Salary paid via the form reaches `salary_exp` |
| 8 | G22 | Online order advance. Create `cust_advance` cash move on save; on delivery use `cust_advance_used`, not a second sale payment; cancel fates `refund` and `income` post | 3 | G5 | Yes: account for forfeited advance (`income`) | Advance shows in cash on the day it is taken |
| 9 | G24 | Purchase paper link. `purchase_bills.po_ref`, `supplier_payments.entry_ref`; P5 counts screen bills; approved 06-4 creates a pending payment line; 04-1 / 03-1 `cash_amount` creates or links a cash payment | 3 | none | No | P5 shows the same bill whether typed on paper or the screen |
| 10 | G25 | Sales paper registers. Store 20-2 serial on `sales`, 20-3 serial on `sale_returns`; Q3 reads `sale_returns.reason`; 20-4 invoice generated from a wholesale sale | 2 | none | No | Return reason report matches the returns table |
| 11 | G26 | Marketing spend. Source `marketing_expense` (Dr `exp_marketing`, Cr by source); guard against a 10-2 of the same receipt; P&L row | 3 | G2 | Yes: P&L head and treatment of owner-paid spend | Bank-paid ad invoice reaches journal and L1 |
| 12 | G28 | 14-1 stock table (`waste_qty`, `own_use`, `sample`) compared with `stock_wastage` and manual issues of the day | 2 | G20 | No | Difference flagged, nothing posted twice |
| 13 | G27 | Asset registers. Link `assets` to `fa_assets` and the purchase line; one cost | 2 | G2 | Yes: capitalisation limit | One cost per asset |
| 14 | G29 | Cost bills to books and overhead true-up variance. Bill save: Dr `exp_<type>`, Cr `payable` / `pay_*`; month-end true-up entry on `overhead_absorbed` | 4 | G10, G2 | Yes: switch `cost_bill_creates_payment` (see `phase78.sql` header) | Electricity bill appears once in expense and once in conversion cost via absorbed account |
| 15 | G23 | Loyalty points and gifts tied to a sale discount; optional liability | 3 | none | Yes: accrue a liability or not | Redeemed points reduce the sale and the point balance together |
| 16 | G31 | HR paper money: 02-1 temp wage, 02-5 leave link, 02-6 final settlement from `payroll_settlement_preview` | 2 | G16 | Yes: keep paper by design? | No money typed twice |
| 17 | G32 | Cards 05-2 / 05-3 versus `shelf_life_rules` and `recipe_lines` (show live value, or draft from card) | 3 | none | Yes: keep as paper by design? | Card and recipe cannot silently differ |
| 18 | G33 | Warn on switch coupling: the page `#/ledgerlinks` and `#/paths` must state that `forms_post_to_ledger` ON makes the form primary and locks the stock screens; require owner confirmation | 0.5 | none | No | Warning visible before the switch is saved |

Total new work: about 49 days `[unverified]`. Closing every gap in section 2 also needs the existing G1 to G12.

### 4.3 Dependency chain

`G2 -> G3 -> G18, G26, G27` ; `G2 -> G30 -> G19, G4` ; `G5 -> G22` ; `G16 -> G17, G31` ; `G20 -> G28` ; `G10 -> G29`. G21, G24, G25, G33 are independent.

## 5. Automation: does the report update by itself, or does a human step remain?

"Auto" = no re-typing and no human click after the original screen. "Human" = a person must type, approve, switch on or open a page.

| Fact | Stock | Day book | Operational reports | Journal / accounts reports | Human step left |
|---|---|---|---|---|---|
| Retail sale (POS) | Auto (trigger `_sale_stock_out`) | Auto | Auto | After AO ON + start date, **Human**: opening `#/accounts` or "Post now" (G30) | Switch on; start date |
| Sale return, void | Auto | Auto | Auto (net of returns, rule ON) | Same as sale | as sale |
| Due collection | - | Auto | Auto | Same as sale | as sale |
| Purchase bill | Auto (`post_purchase`) | Auto on payment | Auto | Same as sale | as sale |
| Supplier payment | - | Auto | Auto | Same as sale | as sale |
| Expense voucher 10-2 | - | Auto on submit | Auto on submit (PL); expense report ignores quick entries | After **approval** (human) and posting step | Approver decides |
| Quick expense | - | Auto | PL yes, `expense_by_head` no | Same as sale | as sale |
| Cash move (deposit, owner, hub) | - | Auto | W1 | Same as sale | Typed by hand at the hub for a hub receipt |
| Wastage | Auto (approval above limit) | - | wastage reports | Same as sale | Approver above limit |
| Recipe production | Auto | - | F1-F3 | Same as sale | Recipe must be approved if gate ON |
| GRN / issue / count / transfer / factory sheet | Only if `forms_post_to_ledger` ON and form primary; **default: no** | - | K2, K3, P-reports read the form | None (no journal) | Re-type on the stock screen by default |
| Stock count adjust, manual issue, manual production | Auto | - | K2, K3 | **No journal** (G18) | - |
| App payroll | Attendance feeds calc (auto) | On payment | **PL, salary report, T3, T4 do not read it** (G16) | Journal on payment, then as sale | Run, approve, pay |
| Form 02-2 / 02-3 | - | Auto on submit | PL, salary report read them | **No journal** (G17) | Whole form typed |
| Daily sheet 14-1 | - | - | Flags, compliance | None | **All totals typed**, no compare with POS (G20) |
| Cash handover 10-1 | - | internal | W2 | **No journal** (G19) | Hub receipt typed separately |
| Online order | Auto at delivery | Auto at delivery | S10 | via the sale | Advance and cancel fate are manual (G22) |
| Customer advance | - | Auto | - | Same as sale | Typed on `#/cashmoves` |
| Owner capital / draw | - | Auto | - | Same as sale | Choose partner capital or cash move; link them |
| Marketing spend 18-1 | - | - | E4, M2 | None | Typed; ledger total typed (G26) |
| Opening balances | Manual | Day book opening typed | - | `acct_opening` / phase80 | Whole entry typed |
| Bank statement | - | - | - | Manual paste then match | Human |
| Month end, year end, depreciation, VAT | - | - | - | Manual runs, all switches OFF | Human |
| Report engines 1, 2, 3, P&L | - | - | Computed from live tables on every open (`report_run3`, `report_run2`, `report_run`) | - | None |

## 6. Gaps to confirm with the live database (not done here)

1. Live values of `accounting_on`, `accounting_start_date`, `forms_post_to_ledger`, `grn_receipt_source`, `sale_forms_link_on`, `online_orders_on`. [unverified]
2. Row counts of `journal_entries`, `entry_ledger_posts` (status `skipped`, `failed`), `shadow_links`. [unverified]
3. Whether a scheduler extension is available on the hosting plan. [unverified]
4. Whether daily profit (`biz_daily`) includes salary (also open in G12). [unverified]
5. The account code a purchase bill of an equipment item lands on (`_acct_buy_key`). [unverified]
