# Islamia BOS — module map (what exists, what is editable, what is controlled)

Everything below is already in the app unless marked ☐ (planned). Nothing from the owner's list was removed; things were grouped.
Where a number is a limit, it is **never fixed in code**: it is a location setting, a rule, a list value or a role grant that the owner edits.

Legend — **Rule** = switch/number/choice in *Rules & options → Rules* · **Grant** = which role may (*Who may do what*) ·
**List** = editable dropdown (*Edit lists*) · **Limit** = per-location number (*Location limits*) · **Form rule** = per form (*Form rules*).

## 1 · Sales (POS)  — modelled on Odoo POS / Loyverse / Square
| Function | Options |
|---|---|
| Item-wise sale with kg / piece / pound, quick keys (frequent items), search, categories | prices from the item list (price history kept) |
| Quick sale for rush (one tap cash) · item not in the list (flagged) · new item request | Rule `pos_unlisted` allow / flag / block |
| Retail / wholesale sale type | wholesale needs a customer (Rule `pos_customer_on_wholesale`) |
| Split and **partial payment** (cash / bKash·Nagad / card), the rest stays due | wallets are a **List** |
| Discount with a limit | **Limit** `discount_limit`; above it (or no limit written) needs **Grant** `discount_over_limit` (Rule `pos_discount_manager`) |
| Price change | **Grant** `price_override` (Rule `pos_override_manager`) |
| Void with a reason · reverse a wrong collection | **Grant** `sale_void`, `collection_void` |
| Offline sales queue (per user, sent when online, refused ones kept visible) | Rule `pos_offline_hours` |
| Receipt number per location, receipt share | — |

## 2 · Customers, dues (baki), collections  — Zoho / ERPNext / Vyapar practice
Customer by mobile (01XXXXXXXXX) · name · retail/wholesale · **credit limit per customer** (Rule `pos_credit_mode` block / warn / off; **Grant** `credit_over_limit`) ·
dues list with age · customer ledger · collect full or part, by cash / mobile / card · mobile required on due sales (Rule `pos_customer_on_due`),
on any discount (Rule `pos_customer_on_discount`). Mobile-money reference kept for reconciliation (form 07-1).

## 3 · Cash, drawer, handover  (forms 06-1, 03-1, 07-1, 04-1, 30-1, 14-1)
Blind count first (Form rule `count_first`) · short/over against **Limit** `cash_tol` · red control blocks submit; staff asks, owner decides (release requests) ·
cash handover with hub count · digital payment reconciliation · cash position and purchase budget (hub **Limits** `hub_cash_max`, `hub_min_cash`).

## 4 · Expenses & imprest  (11-1, 17-1)
Expense heads and marketing heads are **Lists** (marketing head has a monthly limit in its list row) · **Limit** `expense_max`, `imprest` · receipt photo ·
over-limit needs an approver · imprest equation (cash + receipts = fixed amount).

## 5 · Purchasing & suppliers  (28-1 … 38-1)
Requisition → quotation comparison (**Limit** `quote_over`) → purchase order → goods received (13-1) → bill check (3-way match) → supplier ledger.

## 6 · Stock, godown, transfers  (39-1, 13-1 … 37-1)
Transfer challan with receiver check · goods received with photo · material issue · stock count with blind count and tolerance (**Limits** `count_tol_pct/max`) · store ledger.
☐ later: minimum-stock / reorder suggestions from sales speed (needs a live stock balance) · wastage write-off reasons as a **List**.

## 7 · Factory & production  (12-1 … 22-1)
Daily sheet (fridge limits per fridge, scale check) · product spec card · recipe card · yield test · new product decision. All numbers are the owner's entries.

## 8 · People & HR  (19-1 … 34-1, 33-1)
Attendance, salary sheet, advances, appointment letter, leave, exit clearance, duty & backup card, skill checklist, shift handover.

## 9 · Assets & maintenance  (16-1) · Owner reports  (40-1, 20-1) · Orders & sales papers  (05-1 … 23-1)
Maintenance request with photos · weekly review · monthly P&L and KPIs · customer order · discount slip · returns & complaints · party invoice and ledger · online & delivery ledger.

## 10 · Controls (the thread through everything)
Red / yellow flags → exceptions list · release requests · **emergency requests** (staff blocked by a rule asks at once; owner approves once or for a short window; later sets the
standing **Grant**) · **books closed until** (Rule `period_closed_until`) · printed paper number with gap audit (Rule `entry_paper_no_required`) ·
draft changes need a note (correction log) · every change in the audit log · staff PIN lock.

## 11 · Owner dashboard & analysis
Problems first · today's numbers · 7-day sales · gross margin / break-even / purchase outlook / ABC items / staff indicators / limit suggestions (nothing applied automatically).

## 12 · Settings structure (where the owner finds things)
*Rules & options* hub: **Rules** (all switches/numbers/choices) · **Who may do what** (role grants) · **More** (lists, location limits, form rules, role × form matrix, staff, general settings, number audit, business analysis, change log, backup).
Home keeps only daily work and things that need a decision (emergency requests, release requests, staff approval, exceptions).

## Still open (needs the owner)
☐ VAT / Mushak 6.3 receipt requirement for a sweet shop (confirm with a VAT adviser) · ☐ English spelling of "মিষ্টি বাড়ি" (set as MISTY BARI) ·
☐ server-side recomputation of key form equations · ☐ hard server-side PIN lock (needs a Supabase Auth hook).
