# Real-life daily workflow guide (English)

Islamia Misty Ghar · BOS app · forms, roles (demo), and one full demo day

- Written from the code on branch `ccr-46b26d91-81vl9s`. The database was not run or tested live.
- All staff names are fictitious demo names. No staff accounts exist yet and no permissions have been granted by the owner.
- Demo quantities and money amounts are illustrative only.

---

## 0. How to read this

**Status tags**

- `[Live-code]` the screen and its logic exist in the code.
- `[Needs switch ON]` the stock or ledger effect happens only when an owner switch is on.
- `[Not built]` no code found.
- `[Unverified]` not confirmed from the code or a live database.

**Defaults** are the values the SQL seed files set. The owner may have changed them in the live database, so check *Rules* before relying on them.

---

## 1. Design in one page

**Entry, then Approve**
- Save draft, then **Submit**, then **Approve**.
- Red controls block **Submit** (not Approve) until a release is approved.
- Approve must be done by another person. The owner is exempt while `owner_self_approve` is ON, and it is ON by default.
- Rejecting needs a note.

**Stock ledger**
- Every stock change is a row in `stock_ledger`. Sales, purchase bills, production, issue, count adjust, wastage and transfers all post through stock functions.
- Negative stock is a warning by default (`stock_negative_mode = warn`).

**Transfers in transit**
- Sender: stock goes OUT at once when the transfer is sent.
- Receiver: stock comes IN only when they receive it, typing the quantity received.
- A short receipt creates a yellow `transit_short` exception. The missing quantity is not written off automatically.
- The sender can cancel while the transfer is still in transit.

**Screen or paper form (no double posting)**
- For issue, transfer, count and factory production, the owner picks one primary path per domain.
- Default primary is **`a` = the screen** (Stock or Recipes & production). An approved paper form is then only a reference. Its lines are kept as `skipped: covered_by_screen`.
- Primary `b` (the paper form posts) needs `forms_post_to_ledger` ON as well.

**Switches and defaults (from seed)**

| Switch / setting | Default | What it does |
|---|---|---|
| `forms_post_to_ledger` | OFF | Approved 04-1, 04-2, 04-3, 03-1, 05-1 may post stock (only when that domain's primary is `b`) |
| `owner_self_approve` | ON | Owner may approve own entries. Can be switched OFF only if another approver exists |
| `blind_count_on` | OFF | Server-side hidden count for 14-1 drawer, 10-1 hub, 04-3 and 04-1 counts |
| `pin_signature_on` | OFF | PIN signature on forms |
| `count_first` (per form) | ON | Counted figure first; expected figure is hidden until counted (screen side) |
| `red_block` (per form) | ON | Red flag blocks Submit until release is approved |
| `enabled` (per form) | ON | Form visible for entry |
| `auto_exceptions` | ON | Flags go to the Exceptions list automatically |
| `rollout_enforce` | ON | Only matters for a form set to paper mode. Default mode is `app` |
| `entry_paper_no_required` | OFF | Paper serial number required on submit |
| `period_closed_until` | empty | No closed-period lock |
| `em_enabled` | ON | Emergency requests allowed |
| `pos_unlisted` | flag | Items not in the list are flagged (not blocked) |
| `pos_credit_mode` | block | Customer over credit limit is blocked (grant `credit_over_limit` overrides) |
| `pos_customer_on_due` | ON | Mobile required on due sales |
| `pos_customer_on_discount` | OFF | Mobile required on discount sales |

**Limits (location settings, no code default)**
- Empty means "data needed", and a difference is then red.
- Examples: `drawer_float`, `imprest`, `cash_tol`, `expense_max`, `count_tol_pct`, `count_tol_max`, `goods_money_tol_pct`, fridge min/max, hub cash limits.

**Grants per role per location**
- Owner: everything.
- Management: all locations.
- Others: only locations assigned to them.
- Form permissions per role: view, enter, approve (`role_form_perms`).
- Action grants (`stock_transfer`, `stock_count_adjust`, `discount_over_limit`, `price_override`, `sale_void`, and so on) per role or per person, optionally with a time limit.
- Emergency requests give a one-use approval or a short window.
- The code seeds *suggested* role defaults. These are suggestions only. The owner has not confirmed them.

**Controls**
- Count first (on by default).
- Red flags block Submit. Yellow flags are warnings.
- Exceptions list, auto-filled.
- Release requests: a maker asks, owner or a delegate with `release_decide` decides.
- Emergency requests.
- Blind count (server side, off by default).
- Period lock (off by default).
- Audit log for changes.

---

## 2. Part A: each form (what, who, where, how, after Approve)

Groups follow the app. Form codes are the numbers in the app.

### 2.1 Showroom

**14-1 Daily Showroom Sheet** `[Live-code]`
- Real life: the shop day sheet. Opening float, goods receipts, sales by category, cash count, closing stock, closing checklist.
- Who and where: showroom manager enters; management approves (suggested). Islamia Main (demo showroom).
- How: sections A to J. Count cash by notes first. Save, Submit (red flags block here), then Approve by another person.
- After Approve: no stock or ledger posting. The expected drawer balance and short/over are shown. Cash short/over beyond `cash_tol` is red. Category total not equal to total sales is red. Setup needed: `drawer_float`, `imprest`, `cash_tol`.

**14-2 Jalebi Counter Daily Record** `[Live-code]`
- Real life: daily record of the jalebi counter (production, sales, waste).
- Who and where: salesperson enters (suggested); cash controller views. Showroom counter.
- How: daily counter record. Field list `[Unverified]` in this pass.
- After Approve: record only. Not in the posting map, so no stock or cash effect.

**ONLINE_INTAKE** `[Not built]`
- Listed as "Soon" in the old manual. No form code or screen found in code.

### 2.2 Cash and accounts

**10-1 Cash Handover Slip** `[Live-code]`
- Real life: cash moves from showroom to hub, counted by both sides.
- Who and where: showroom manager sends; carrier carries; cash controller receives at the hub.
- How: sender counts by notes, leaves float, sees handover amount. Hub counts by notes. Any difference is red (`hub_diff`). Reason needed.
- After Approve: no stock posting. Hub writes the ledger date and line number by hand. Automatic cash-move creation `[Unverified]`.

**10-2 Expense Voucher** `[Live-code]`
- Real life: each expense paid from petty cash (imprest), with receipt.
- Who and where: showroom manager or cash controller enters; management approves (suggested). Showroom.
- How: lines (head, to whom, receipt yes or no, amount). Over `expense_max` is yellow and needs an approver. No receipt needs a reason. Imprest check: cash now + receipts = fixed imprest.
- After Approve: no stock. Counted once in the day book. Quick expenses (below) get a 10-2 shadow at day end.

**10-3 Digital Payment Reconciliation Register** `[Live-code]`
- Real life: match bKash, Nagad and card totals from the day to the phone or machine.
- Who and where: cash controller enters. Hub.
- How: digital totals per wallet against the business phone and machine. Mismatch is a red or yellow flag.
- After Approve: record only. No cash or stock posting `[Unverified]` on exact checks.

**10-4 Cash Position and Purchase Budget** `[Live-code]`
- Real life: cash in hand and what can be spent on purchases.
- Who and where: cash controller enters. Hub.
- How: cash position against hub limits (`hub_cash_max`, `hub_min_cash`) `[Unverified]` on exact checks.
- After Approve: record only.

**10-5 Receivable and Advance Reconciliation** `[Live-code]`
- Real life: outstanding customer dues and advances checked against the ledgers.
- Who and where: cash controller enters. Showroom or hub.
- How: totals for dues and customer advances, checked against the customer ledger.
- After Approve: record only. Cross-check to ledger `[Unverified]`.

### 2.3 Stock and godown

**03-1 Transfer Challan (IBT)** `[Live-code]` (paper). Stock effect `[Needs switch ON]` plus primary `b`.
- Real life: paper challan for goods moved between locations (factory to showroom, showroom to factory, showroom to showroom, customer or party delivery).
- Who and where: storekeeper or showroom manager prepares. Sender and receiver both sign.
- How: from and to location, items (demand, sent, grade, production date). Sender counts and receiver counts. Receiver's quantity below sent is a red shortage flag, so the form cannot be submitted until released.
- After Approve, default (primary `a`): no stock change. Lines are `covered_by_screen`. The Stock screen transfer (next line) is the posting.
- After Approve, primary `b` and switch ON: sender OUT at once. Receiver IN when the received quantity is filled; if blank the transfer stays "sent" (in transit).

**Stock screen: Transfer, Receive, Cancel** `[Live-code]`
- Real life: the actual stock move in the app.
- Who and where: sender's storekeeper or showroom manager (grant `stock_transfer` at the sending location). Receiver needs the same grant at their location.
- How: Stock, then Transfer. Pick item, quantity (any allowed unit), to-location, note. Receiver opens Stock, In transit, Receive, types received quantity.
- After: sender OUT at once. Receiver IN on receive. Short receipt creates yellow `transit_short`. Sender can cancel while in transit (reversing row).

**04-1 Goods Received Note (GRN)** `[Needs switch ON]` for any stock effect.
- Real life: paper receipt of goods from a supplier or factory, counted against the challan.
- Who and where: storekeeper enters; purchasing views. Godown or showroom.
- How: challan number, written vs counted, quality (accept, reduced, hold, return), rate, new rate.
- After Approve: no stock change by default. With the switch ON and `grn_receipt_source = purchase` (default), GRN "in" lines are skipped (`covered_by_purchase_page`) because the purchase bill already posts. Held or returned lines are skipped in every case.

**04-2 Material Issue Slip** `[Live-code]` (screen). Form effect `[Needs switch ON]` plus primary `b`.
- Real life: raw material given to production.
- Who and where: storekeeper enters; factory in-charge receives. Godown to Sweet Factory.
- How: items, issued quantity, returned quantity, "not overnight" flag, purpose.
- After Approve, default: no stock change from the form. Stock screen Issue (`stock_issue`, grant needed) is the posting, and the form lines are `covered_by_screen`.

**04-3 Stock Count Sheet** `[Live-code]`
- Real life: physical count of stock against the ledger.
- Who and where: counter is never the storekeeper. Witness must be a different person. Godown or showroom.
- How: rows of counted vs book. Variance beyond `count_tol_pct` or `count_tol_max` is red. Reason needed on each differing row. Counter = storekeeper is red. Witness = counter is red.
- After Approve, default: no change from the form. Adjust in Stock screen, Count (`stock_count_adjust`, note required). Form lines `covered_by_screen`.

**Stock screen: Issue, Count, Opening, Wastage** `[Live-code]`
- Issue: see 04-2.
- Count adjust: moves stock to the counted figure. Note required. Variance beyond tolerance is a yellow exception.
- Opening stock: once per item and location (grant `stock_opening`).
- Wastage: request goes to a pending list and an approver decides (`wastage_decide`). Reasons are a list.

**04-4 Store Ledger** `[Live-code]`
- Real life: the stock movement book for an item at a location.
- Who and where: view for storekeeper, cash controller and management (suggested).
- How: read-only view of `stock_ledger_rows`.
- After: no posting. This is the proof screen.

### 2.4 Purchasing

**06-1 Purchase Requisition (PR)** `[Live-code]`
- Real life: what the shop needs to buy and why.
- Who and where: purchasing enters; management approves (suggested). Head office.
- How: items, quantities, need-by date, reason.
- After Approve: no stock or cash.

**06-2 Comparative Statement (CS)** `[Live-code]`
- Real life: quotes from suppliers side by side, then pick a supplier.
- Who and where: purchasing. Head office.
- How: quotes per item, choose supplier. Over-limit rule `quote_over` `[Unverified]`.
- After Approve: no stock or cash.

**06-3 Purchase Order (PO)** `[Live-code]`
- Real life: the order sent to the supplier.
- Who and where: purchasing enters; storekeeper can view (suggested).
- How: supplier, items, price from the CS.
- After Approve: no stock or cash. Stock comes in on the purchase bill, not on the PO.

**06-4 Bill Check and Payment Request** `[Live-code]`
- Real life: check the supplier bill against PO and receipt, then request payment.
- Who and where: purchasing enters; management approves (suggested).
- How: bill vs PO vs receipt. Link to purchase bill `[Unverified]`.
- After Approve: a request only. Payment is made with Supplier payables (`pay_supplier`, grant `supplier_pay`).

**06-5 Supplier Ledger** `[Live-code]`
- Real life: what is owed to each supplier.
- Who and where: purchasing and management view.
- How: read-only view of supplier ledger.
- After: no posting.

**Purchase bill (screen, not numbered)** `[Live-code]`
- Real life: the real stock-in for goods bought from suppliers.
- Who and where: purchasing with `purchase_entry` grant (suggested to purchasing and storekeeper). Location where goods arrive.
- How: supplier, bill number, lines (item, quantity, rate). Save, then Post.
- After Post: stock goes IN at that location (`purchase_in`), and the supplier payable goes up. Paying the supplier reduces it (`pay_supplier`).

**Purchase return (screen)** `[Live-code]` (route exists). Exact steps `[Unverified]`.

### 2.5 Factory and production

**05-1 Factory Daily Sheet** `[Needs switch ON]` for any form stock effect.
- Real life: what the factory made today: output by item, fridge temperatures, notes.
- Who and where: factory in-charge enters; management approves (suggested). Sweet Factory.
- How: output lines (item, quantity), fridge checks, notes.
- After Approve, default: no change from the form. The Recipes and production run is the posting, and form lines are `covered_by_screen`. Ingredient use through the form `[Unverified]`.

**Recipes and production (screen, not numbered)** `[Live-code]`
- Real life: make a batch of product from the recipe.
- Who and where: factory in-charge (grant `stock_production`, and `stock_issue` for ingredients). Sweet Factory.
- How: pick recipe, number of batches, actual yield (kg) if different from standard. Save.
- After Post: ingredients go out per recipe lines. Finished goods come IN as a batch with expiry from the shelf-life rule. Yield variance (%) is recorded. A recipe line with no waste % gives a yellow warning.

**05-2 Product Spec Card** `[Live-code]`
- Real life: spec for a product (ingredients, size, shelf life).
- Who and where: factory in-charge enters; management approves.
- After: record only.

**05-3 Recipe Card** `[Live-code]`
- Real life: paper copy of a recipe.
- Who and where: factory in-charge.
- How: recipe lines. Live recipes are kept in Recipes and production (`recipe_save`). Link between paper and live `[Unverified]`.
- After: record only.

**05-4 Yield Test Sheet** `[Live-code]`
- Real life: test of how much finished product a batch gives.
- Who and where: factory in-charge.
- After: record only `[Unverified]` on any link to recipe yield.

**05-5 New Product Decision Sheet** `[Live-code]`
- Real life: decision record for a new product.
- Who and where: management and owner.
- After: record only.

### 2.6 Sales and POS

**POS sale (Sell)** `[Live-code]`
- Real life: every sale at the counter.
- Who and where: salesperson or cashier (POS enter). Showroom POS.
- How: items by kg, piece or pound, or a quick sale for rush. Items not in the list are flagged. Payment split: cash, bKash, Nagad, card, or due. Mobile needed for due and wholesale. Discount above limit needs `discount_over_limit`. Price change needs `price_override`.
- After save: tracked items leave stock at that location at once (`sale_out`). Due creates a customer balance. Wallet and card amounts are recorded.

**Sale return** `[Live-code]`
- Real life: customer brings goods back.
- Who and where: salesperson with the POS grant `[Unverified]` on exact grant name. Showroom.
- How: sale, items and quantities returned, reason, refund mode.
- After: stock goes back into the original batch at the original cost. The value reduces the customer's due first. Any rest is refunded.

**Dues and collection** `[Live-code]`
- Real life: customer pays an old due.
- Who and where: POS enter. Showroom.
- How: customer mobile, amount, cash, mobile wallet or card. Oldest dues are paid first.
- After: customer balance goes down. Cash counts in 14-1 as "earlier dues collected".

**Cash and bank moves** `[Live-code]`
- Real life: bank deposits and withdrawals, owner money in and out, customer advances, hub receipts.
- Who and where: cash controller; owner. Location where the cash is.
- How: kind, amount, mode (cash or bank), customer where needed, note.
- After: cash and bank balances and day book. No stock.

**Quick expense (day book)** `[Live-code]`
- Real life: one-line expense during the day.
- Who and where: staff with 10-2 enter, or owner.
- How: head, amount, mode, receipt yes or no.
- After: day-end, one click creates a 10-2 draft (shadow). Counted once.

**Day book** `[Live-code]`
- Real life: day's cash-type entries in one list.
- Who and where: owner, accountant (`view_daybook`).
- How: read view. Includes cash moves and expenses.
- After: read only. Full set of sources `[Unverified]`.

**20-1 Customer Order Form** `[Live-code]`
- Real life: a customer order taken in advance.
- Who and where: salesperson or party coordinator enters. Showroom.
- How: customer, items, date, advance taken. Link to a POS sale (`sale_form_link`) when delivered.
- After: record. Link to sale is the only effect.

**20-2 Discount Approval Slip** `[Live-code]`
- Real life: written approval for a discount above the limit.
- Who and where: showroom manager enters; management or owner approves.
- After: record. The POS uses the approval for discount reports.

**20-3 Return and Complaint Register** `[Live-code]`
- Real life: book of returns and complaints.
- Who and where: showroom manager, salesperson.
- After: record. Refund figures are typed into 14-1 with the register number.

**20-4 Party and Wholesale Invoice** `[Live-code]`
- Real life: invoice for a party or wholesale order.
- Who and where: party coordinator enters. Islamia Main.
- After: record. Party cash is typed into 14-1 `[Unverified]` on automatic link.

**20-5 Party Ledger** `[Live-code]`
- Real life: what each party owes.
- Who and where: party coordinator, management view.
- After: read or record only.

**20-6 Online and Delivery Ledger** `[Live-code]`
- Real life: online orders and home delivery.
- Who and where: carrier or party coordinator enters (suggested).
- How: order save, link to sale, deliver, cancel.
- After: link to sale. Stock effect comes from the sale `[Unverified]`.

**18-1 Marketing Expense Register** `[Live-code]`
- Real life: marketing spend by head.
- Who and where: management enters.
- After: record. Monthly limit per marketing head `[Unverified]`.

### 2.7 Assets and maintenance

**08-1 Maintenance Request and Record** `[Live-code]`
- Real life: repair request with photos, then the record.
- Who and where: showroom manager enters; management approves (suggested).
- After: record only. No asset posting.

### 2.8 Owner reports

**01-1 Weekly Review Note** `[Live-code]`
- Real life: owner's weekly review.
- Who and where: owner.
- After: record only.

**01-2 Monthly P&L and KPI Sheet** `[Live-code]`
- Real life: monthly profit and KPI.
- Who and where: owner.
- After: record. Numbers come from Reports and Business analysis `[Unverified]`.

### 2.9 Staff and HR

**02-1 Monthly Attendance Register** `[Live-code]`
- Who and where: HR enters. Record of attendance (punch screens are separate).

**02-2 Monthly Salary Sheet** `[Live-code]`
- Who and where: HR enters; owner or management approves.
- After Approve: payroll domain. Once app payroll starts for that month the form is locked, with a shadow copy kept `[Unverified]` on exact lock.

**02-3 Staff Advance Register** `[Live-code]`
- Who and where: HR enters. Record of advances, linked to payroll `[Unverified]`.

**02-4 Appointment Letter Terms** `[Live-code]`
- Who and where: HR. Record of terms and duties.

**02-5 Leave Application** `[Live-code]`
- Who and where: showroom manager enters (suggested); HR approves. Leave screen exists.
- After: record.

**02-6 Exit Clearance** `[Live-code]`
- Who and where: HR. Checklist record.

**02-7 Duty and Backup Card** `[Live-code]`
- Who and where: HR enters. Record of duty and backup person.

**02-8 Skill Checklist** `[Live-code]`
- Who and where: HR. Record.

**11-1 Shift Handover Register** `[Live-code]`
- Real life: handover between shifts (serial numbers are used in 14-1).
- Who and where: showroom manager enters. Showroom.
- After: record only.

### 2.10 Items and settings

**ITEMS (item list and prices)** `[Live-code]`
- Real life: the item list and selling prices.
- Who and where: owner (direct change). Others send a request (`itemreq`) that an approver decides.
- After: prices apply to future sales only.

**ITEM_COST (cost price)** `[Live-code]`
- Real life: cost price. Visible and editable only with the `ITEM_COST` permission.

**0-1 Location Settings Sheet** `[Live-code]`
- Real life: sets limits per location (fridge, cash float, imprest, tolerance).
- Who and where: owner. Screen: Locations, settings sheet.
- After: new version of location settings.

---

## 3. Part B: role playbook (demo names, intended setup)

**Important:** the owner has not yet granted any permissions and has not added any staff accounts. Everything below is the intended setup to configure, not existing accounts. The code's suggested defaults are not confirmed by the owner.

Demo names (fictitious):

### Owner: Demo Owner - Karim
- Responsibilities: final decisions on red releases, emergency requests and item price changes; sets switches, grants and limits; reviews owner board and exceptions.
- Forms: 0-1, 01-1, 01-2, and every approval.
- Location: all.

### Management: Demo Management - Salma
- Responsibilities: approves most entries; checks cash and stock; approves transfers and count sheets.
- Forms: approves 14-1, 03-1, 04-2, 04-3, 05-1, 06-1, 06-4, 10-2, 20-2, 08-1 (suggested).
- Location: all (management rule).

### Showroom manager: Demo Showroom Manager - Rahim (Islamia Main)
- Responsibilities: opens and closes the shop, runs the cash handover, sends transfers, does expenses, handles discount slips.
- Forms: 14-1 (enter), 10-1 (send), 10-2, 03-1 (send), 20-2, 20-3, 11-1, 08-1, 02-5.
- Location: Islamia Main only.
- Cannot: approve own 14-1 (needs management or owner).

### Showroom manager (Misty Bari): Demo Showroom Manager - Ayesha
- Responsibilities: receives transfers, checks shortage, counts with the sender.
- Forms: 03-1 (receive side), Stock, In transit, Receive.
- Location: Mishti Bari only.

### Salesperson and cashier: Demo Salesperson - Nasrin (Islamia Main)
- Responsibilities: POS sales, dues collection, customer orders, sale returns (if granted).
- Forms: POS sale, sale return, dues, 14-2, 20-1 (enter).
- Location: Islamia Main POS.
- Limits: no discount above limit and no price change without the grant.

### Storekeeper: Demo Storekeeper - Jamal (Islamia Main godown)
- Responsibilities: receives goods (04-1), issues to factory (04-2), counts stock (04-3), holds the stock ledger.
- Forms: 04-1, 04-2, 04-3, 04-4, 06-3 (view), stock screen transfer, issue, count, wastage.
- Location: godown.
- Cannot: count own stock (counter must be someone else).

### Factory in-charge: Demo Factory In-charge - Selim (Sweet Factory)
- Responsibilities: runs production, daily factory sheet, product spec, sends finished goods.
- Forms: 05-1 to 05-5, 04-2 (receive), 03-1 (send), production run.
- Location: Sweet Factory.

### Purchasing: Demo Purchasing - Hasan (head office)
- Responsibilities: quotes, PO, purchase bill, bill check.
- Forms: 06-1, 06-2, 06-3, 06-4, 06-5, purchase bill.
- Location: all purchase locations (grant).

### Cash controller: Demo Cash Controller - Fatema (hub)
- Responsibilities: receives handovers, counts cash, reconciles digital payments, cash and bank moves.
- Forms: 10-1 (hub count), 10-3, 10-4, 10-5, 14-2 (view), cash and bank moves.
- Location: hub.

### Party coordinator: Demo Party Coordinator - Ruma (Islamia Main)
- Responsibilities: party and wholesale orders and invoices, party ledger.
- Forms: 20-1, 20-2, 20-4, 20-5.
- Location: Islamia Main.

### HR: Demo HR - Anwar (head office)
- Responsibilities: attendance, salary, advances, leave, exit clearance, duty cards, skill checklist.
- Forms: 02-1 to 02-8, 11-1.
- Location: all.

### Carrier (extra role in code): Demo Carrier - Sohel
- Responsibilities: carries cash bags and goods between locations, records online deliveries.
- Forms: 10-1 (carry), 03-1 (view), 20-6 (enter).

---

## 4. Part C: one complete demo day

**Demo setup (owner would set these; none is set yet)**
- `drawer_float` 2,000; `imprest` 5,000; `cash_tol` 100; `expense_max` 1,000.
- Stock screen is the primary path for transfers and counts (default). `forms_post_to_ledger` stays OFF. The day works without changing any switch.
- Demo item: "ISLAMIYA demo sweet" (kg). Demo recipe: 100 kg standard yield per batch.

Each step: **time, who, where, form or screen, result, verification**.

**07:45 Opening (Islamia Main)**
- Who: Rahim (showroom manager).
- Form: 14-1, section A.
- Result: shutter time recorded, safety check OK, float counted 2,000 (matches), fridges in range, no expired goods on display.
- Verify: 14-1 draft shows float 2,000 and difference 0. Not submitted yet.

**08:00 Transfer 20 kg to Mishti Bari (Islamia Main to Mishti Bari)**
- Who: Jamal (storekeeper) on the Stock screen; Rahim (showroom manager) checks the sender side on the paper challan.
- Screen: Stock, Transfer. Item ISLAMIYA demo sweet, 20 kg, to Mishti Bari.
- Result: Islamia Main goes down by 20 kg at once. Transfer is "sent" and 20 kg is in transit.
- Paper 03-1 is filled by Jamal, signed by Rahim. Salma approves it.
- Result on 03-1: default primary, so no extra stock change. Lines are `covered_by_screen`.
- Verify: Stock, In transit shows 20 kg. Stock ledger row `transfer_out` -20 at Islamia Main. 03-1 shows `covered_by_screen`.

**08:30 to 17:00 POS sales (Islamia Main)**
- Who: Nasrin (salesperson).
- Screen: POS (Sell).
- Result for the day: about 40 bills, total sales 38,000 (sweets 30,000; cake 4,000; jalebi 2,000; curd 1,000; bakery 1,000). Digital 13,000 (bKash 8,000; Nagad 3,000; card 2,000). One due sale of 3,000 (customer mobile given, credit).
- Tracked items leave Islamia Main stock at once on each sale.
- Verify: stock levels at Islamia Main drop with each sale. Sales list shows 38,000 total, 13,000 digital, 3,000 due.

**11:30 Receive at Mishti Bari (19.5 kg, 0.5 kg short)**
- Who: Ayesha (showroom manager, Mishti Bari).
- Screen: Stock, In transit, Receive. Received quantity 19.5 kg.
- Result: Mishti Bari goes up by 19.5 kg. Transfer status "received". Yellow `transit_short` exception: sent 20, received 19.5.
- The 0.5 kg is not in any location now. The app does not write it off automatically.
- Paper 03-1 (receiver check) shows red shortage. It cannot be submitted until released. Ayesha asks for release with note "0.5 kg short in transit, carrier informed".
- Karim (owner) accepts the release. Ayesha submits 03-1. Salma approves.
- Verify: In transit is 0 for this transfer. Exceptions list has `transit_short` 0.5 kg. Releases list shows the request and Karim's decision.

**14:00 Production 1 batch (Sweet Factory)**
- Who: Selim (factory in-charge).
- Screen: Recipes and production. Recipe ISLAMIYA demo sweet, 1 batch, standard yield 100 kg, actual yield 98 kg.
- Result: ingredients go out per recipe (demo: milk solids 60 kg, sugar 25 kg). Finished goods IN 98 kg as a batch, with expiry from the shelf-life rule. Yield variance -2.00%.
- Verify: production run shows standard 100, actual 98, variance -2.00%. Stock ledger: `production_in` +98 kg and ingredient out lines. Yellow warning if a recipe line has no waste % set.

**15:00 Expense (Islamia Main)**
- Who: Rahim.
- Form: 10-2 Expense Voucher. Tea and snacks for staff, 250, with receipt.
- Result: imprest check: cash now 4,750 + receipts 250 = 5,000. Matches. No stock.
- Verify: 10-2 shows imprest match. Day book shows the expense once.

**17:30 Factory daily sheet (Sweet Factory)**
- Who: Selim (enters), Salma (approves).
- Form: 05-1, output line 98 kg.
- Result: default primary, so the form does not post a second 98 kg. Line is `covered_by_screen`.
- Verify: stock shows 98 kg once, from the production run. Ledger posts show `covered_by_screen` only if the switch is ON (here it is OFF, so nothing is posted by the form).

**18:00 to 18:20 Factory to showroom (60 kg)**
- Who: Jamal sends from Sweet Factory; Rahim receives at Islamia Main.
- Screen: Stock, Transfer, then Receive. 60 kg, full receipt.
- Result: Sweet Factory minus 60 kg, then Islamia Main plus 60 kg. In transit back to 0.
- Verify: In transit empty after receive. Two ledger rows (`transfer_out` and `transfer_in`).

**19:30 Dues collection (Islamia Main)**
- Who: Nasrin.
- Screen: Dues and collection. Customer collects 1,000 from an earlier due (cash).
- Result: earlier due 2,000 becomes 1,000. Oldest due first. Cash 1,000.
- Verify: customer ledger shows 1,000 collected. Customer now owes 4,000 in total (1,000 earlier plus today's 3,000 credit sale).

**19:45 Sale return (Islamia Main)**
- Who: Nasrin (with the return grant).
- Screen: Sale return. Customer brings back 1 kg from an earlier sale, value 500.
- Result: stock back into the original batch at the original cost. Value reduces the earlier due (no cash refund). Earlier due 1,000 becomes 500. Total owed 3,500.
- Verify: stock at Islamia Main +1 kg. Customer total owed 3,500 (500 earlier plus 3,000 credit sale).

**21:00 Cash count and handover (Islamia Main to Hub)**
- Who: Rahim (sender), Sohel (carrier), Fatema (hub receiver).
- Form: 14-1 section E cash count by notes first: 24,500. Expected drawer: 2,000 opening + 38,000 sales - 13,000 digital + 1,000 earlier dues - 3,000 credit sales = 25,000. Short 500.
- Result: short 500 is red (more than `cash_tol` 100). Red flag `cash_short_over`. Submit is blocked.
- 10-1 handover: counted 24,500 - leave float 2,000 = 22,500. Fatema counts 22,500 at hub. Matches, no hub difference.
- Verify: 14-1 shows expected 25,000, counted 24,500, short 500. 10-1 shows hub count equal to handover.

**21:30 Close day (Islamia Main)**
- Who: Rahim (maker); Karim (owner decides release); Salma (approves 14-1).
- Form: 14-1 sections F to J (closing stock, demand for tomorrow, 16-step checklist with different people for each step, incidents).
- Witness second count 24,500 matches. No witness flag.
- Result: Submit blocked by `cash_short_over` red. Rahim asks release with note "500 short, no receipt error found, need owner decision". Karim accepts with note "record as unexplained, review with Nasrin tomorrow". Rahim submits. Salma approves.
- Verify: release decision logged. 14-1 status "approved". Exceptions list keeps `cash_short_over` -500 open until resolved.

**22:00 Owner check (Karim)**
- Screens: owner board, Exceptions, Releases, Stock, Day book, audit log.
- Result: two open items for Karim. (1) `transit_short` 0.5 kg for Mishti Bari: accept as loss with note, or write off as wastage with a reason. This is an owner decision, not automatic. (2) `cash_short_over` -500 at Islamia Main: resolve with a note.
- Verify: reports show sales 38,000, digital 13,000 and expense 250 `[Unverified]` on which screen shows each total. Stock ledger shows both transfers and production in and out. Audit log shows who did what and when.

---

## 5. Part D: where to verify, and gaps

### 5.1 Where to verify (screens)

- **Exceptions**: all red and yellow flags (`transit_short`, `cash_short_over`, `count_variance`, `hub_diff`, and others). Owner resolves.
- **Awaiting approval (Pending)**: entries waiting for approve.
- **Releases**: red-control release requests, with decisions.
- **Emergency**: emergency requests and approvals (owner).
- **Stock hub**: levels, In transit, Expiring, item ledger (`stock_ledger_rows`), Reconcile.
- **Store Ledger (04-4)** and **Supplier Ledger (06-5)**: read-only proofs.
- **Customer dues and ledger**: per customer.
- **Day Book**: daily cash-type totals.
- **Reports** and **Business analysis**: sales and profit.
- **Number audit**: paper serial number gaps.
- **Path switches and shadow copies**: which path is primary per domain (screen or form).
- **Ledger links** (owner): form-to-ledger links.
- **Change requests** and **Correction log**: changes to drafts.
- **Audit log** (owner): every change with user and time.
- **Owner board**: problems first.

### 5.2 Gaps and things not configured yet

**Owner decisions and setup (not done)**
1. No permissions granted and no staff accounts. Suggested defaults in code are not confirmed.
2. Location limits empty: `drawer_float`, `imprest`, `cash_tol`, `expense_max`, count tolerances, goods-money tolerance, fridge min and max, hub cash limits. Until set, the app shows "data needed" and differences go red.
3. Item list: 57 seed items. Units and prices need owner check. Unit conversions (kg, piece, pound) need checking per item.
4. Shelf-life rules per item (for expiry on production batches).
5. Switch decisions: `forms_post_to_ledger` (OFF by default; keep OFF if screens are used), `blind_count_on` (OFF), `pin_signature_on` (OFF).
6. Self-approval: `owner_self_approve` is ON by default. If the owner wants strict separation, switch it OFF (needs another approver to exist first).
7. Transfer shortfall write-off rule: not automatic. Owner decides each case.
8. Intercompany accounting between Islamia Main and Mishti Bari if they are separate legal units: not decided.
9. VAT and Mushak receipt requirement: open (confirm with a VAT adviser).

**Not built or not found in code**
10. ONLINE_INTAKE form: not found.
11. Production return or reversal of finished goods back to raw stock: not found.
12. Hard server-side PIN lock (needs Supabase Auth hook): not built.
13. Automatic backup: free plan has manual download only. Restore drill screen exists.

**Not verified**
14. Live database behaviour: all flows above are verified from code, not run against a live database.
15. Several form field lists and cross-links marked `[Unverified]` in Part A.

**Corrections to existing documents (found while writing this guide)**
- `docs/REAL_LIFE_OPERATIONAL_MANUAL.md` says 03-1 moves stock. By default it does not. The Stock screen transfer moves stock. The 03-1 form is a reference (`covered_by_screen`) unless primary is `b` and `forms_post_to_ledger` is ON.
- `docs/REAL_LIFE_OPERATIONAL_MANUAL.md` says GRN posts stock when the switch is on. With the default source `purchase`, GRN "in" lines are skipped because the purchase bill posts them.
- `docs/DECISIONS.md` says self-approval is blocked by default. Code default is ON for the owner (`owner_self_approve = true`).
- Switch defaults: `count_first` and `red_block` default to ON for every form, not OFF. Most switches in the Rules page default to OFF, but these two do not.
- `forms.red_block` comment in SQL says "blocks day close". Code enforces it on Submit (`submit_entry`).
