# Islamia Misty Ghar BOS: Screen map, demo-day stories, stock ledger, balance sheet, feedback (English)

Status: documentation only. Nothing in the main project code was changed. No write was run against the live Supabase project `rpqrcmesbhwtyrikabhy`; only SELECT queries were used.

Dated 2026-10-16. Fictitious people and fictitious demo numbers. Run any of this only on a test project.

## 0. How to read the tags

| Tag | Meaning |
|---|---|
| `[code]` | Confirmed by reading the web or supabase SQL code in this repo (latest definition file noted). |
| `[live]` | Confirmed by a read-only SELECT on the live database on 2026-10-16. |
| `[unverified]` | Not confirmed by code or live data. Must be checked before the demo is trusted. |
| `[demo]` | A made-up number used only to make the demo add up. |

Skill note: the skill named `/Token-Optimization` was not in this session's skill list, so it was not applied. See section 9 for skill suggestions.

---

## 1. Corrections to the earlier demo docs

Found while checking code for this document. These must be fixed in `DEMO_FULL_WORKFLOW_AND_LEDGER.md` and `REAL_LIFE_DAILY_WORKFLOW_GUIDE.md`.

| # | Earlier doc says | Code/live says | Fix |
|---|---|---|---|
| C1 | Jamal (storekeeper) enters the opening stock | `stock_opening` has no `rule_grants` row `[live]`. Only the owner passes the check (owner bypass in `has_grant`) `[code: phase8]`. | Karim enters opening stock, or Karim grants `stock_opening` first. |
| C2 | `branch2` has an opening of 5 kg sweet A, and it also receives 5 kg from `main` at 10:15 | Both together double-count. | Branch2 opening = 0. The 5 kg from `main` is the only source. Added step S6a (main sends 5 kg at 10:10). |
| C3 | Balance sheet line "goods in transit: 1 kg sweet A" | After receipt the transfer status is `received`. The 1 kg is not in transit; it is **missing** `[code: phase10 stock_receive_transfer]`. | Listed as an unexplained loss (section 7, G3). |
| C4 | Main sweet A "out" includes "branch2 (?)" | Main sends 5 kg to branch2. | Corrected in section 5. |
| C5 | Balance sheet cash for branch2 = 1,000, al_cakes = 300, 2 kg sold at branch2 | 2 kg at the demo price of ৳800/kg is ৳1,600. | Recalculated in section 6 with the stated demo price. |
| C6 | Form list has 46 codes incl. 10-x, 20-x | Code also has `0-1` (location settings), `18-1` (marketing expense register). Not in the demo docs. | Added in section 3.3. |

---

## 2. Places and people (from `docs/DEMO_STAFF_ROSTER.md`, live roles)

| Place code | Use | Demo person (role) |
|---|---|---|
| `main` | Main showroom, main sweet factory, **cash hub** (`hub_functions = true`, live) | Rahim (showroom_manager), Selim (factory_incharge), Nasrin (salesperson), Ruma (party_coordinator), Fatema (cash_controller) |
| `branch2` | Second showroom | Shirin (showroom_manager), Tania (salesperson) |
| `mishti_bari` | MISTY BARI showroom | Ayesha (showroom_manager) |
| `al_cakes` | AL-CAKIZ showroom | Lipi (showroom_manager) |
| `cake_factory` | Cake factory | Mitu (factory_incharge) |
| `godown` | Central store | Jamal (storekeeper) |
| `mishti_factory` | **Paused** (live `paused`). Not in this demo. | — |
| head office (no place row) | Purchasing, HR, recipe approval | Hasan (purchasing), Anwar (hr), Nazia (recipe_approver) |
| all | Owner, management | Karim (owner), Salma (management) |
| between places | Carrier, no approval | Sohel (carrier) |

Live check `[live]`: 7 location rows; 13 roles; one real profile (owner + management on one account). No other staff accounts exist, so every demo person is a role on paper until accounts are created.

---

## 3. Real screens and options (from `web/`)

### 3.1 Navigation

Routes are hash paths (`#/<route>`). The drawer has 13 groups (`web/ia.js`). Visibility uses the predicates in `ia.js` (owner, `P(code,'view'|'enter'|'approve')`, grant flags). The server still checks every call.

| Group | Route (hash) | Screen (English purpose) | Who sees it (predicate in `ia.js`) |
|---|---|---|---|
| Dashboard | `home` | Home tiles | everyone |
| Items | `items`, `items/new`, `bulkitems`, `itemimport`, `itemmap`, `itemtypes`, `settings2/units`, `lists` | Item master, new item, bulk price edit, CSV import, map old items, item types, unit conversions, option lists | `ITEMS` view/enter; import and unit conversion = owner only |
| Inventory | `stock`, `stockx`, `assets` | Stock hub (levels, expiring, transit, wastage approvals, stock ledger); stock report; asset ledger | location-scoped |
| Purchasing | `purchase`, `purchase/new`, `purchase/return`, `payables`, `settings2/suppliers` | Purchase bills list, new bill, supplier return, supplier payables | `purchase_entry` grant |
| Factory | `recipes`, `recipebook`, `costing`, `costsources`, `costattrib` | Recipes and production; recipe book; overhead costing | `stock_production` grant for production |
| Sales | `pos`, `salereturn`, `onlineorders`, `inbox`, `flow` | POS sell; sale return; online orders; inbox; daily flow | POS grant |
| Customers | `dues`, `customers`, `tiers`, `invoice` | Collect dues; customer list and tiers; invoice and print | POS grant / customer grants |
| Accounting | `daybook`, `quickexp`, `cashmoves`, `ledgerlinks`, `accounts`, `finance2`, `employees`, `deeds` | Day book; quick expense; cash and bank moves; post links; ledger; finance 2 | cash grants |
| Approvals | `exceptions`, `pending`, `releases`, `emergency`, `changes`, `itemreq`, `numaudit`, `outbox`, `eqcheck`, `notifications` | Exceptions list; approvals waiting; release requests; emergency requests; change requests; item requests; number audit; offline outbox; server equality check | approver |
| Reports | `reports`, `report`, `biz`, `brandpnl`, `discounts`, `biexport`, `assistant` | Reports; business view; brand P&L; discount report; BI export; assistant | owner / management |
| People | `staff`, `matrix`, `salary`, `attendance`, `attend2`, `leave`, `payroll`, `benefitsx` | Staff; permission matrix; salary report; attendance; punch 2; leave; payroll; benefits report | HR / owner |
| Locations | `locations`, `locset`, `locsheet`, `rollout` | Locations; location settings; location sheet; rollout | owner |
| Settings | `control`, `rulehub`, `owner`, `switchboard`, `paths`, `rules`, `settings`, `settings2`, `logs`, `backup`, `twofa`, `integrations`, `restoredrill`, `printbooks`, `delegation`, `partners`, `saleforms`, `parallel` | Control centre; rule hub; owner board; switchboard (all switches); path switch; rules; settings; logs; backup; 2FA; integrations; restore drill; print; delegation; partners; sale forms | owner |

Total registered routes: 90 `[code: web/ia.js]`.

### 3.2 Stock screen (`#/stock`) `[code: web/stock2.js]`

Tabs: **levels**, **expiring**, **transit**, **wa** (wastage approvals; shown only to approvers or to the requester).

Button **Stock actions** opens a sheet. Options and what each writes:

| Option (label) | Sheet kind | RPC | Who (grant, from live `rule_grants`) | Writes |
|---|---|---|---|---|
| Opening balance | `open` | `stock_opening` | owner only `[live]` | One `opening` ledger row per item per place. Second try = `opening_exists`. |
| Issue to production | `issue` | `stock_issue` | `storekeeper`, `factory_incharge` `[live]` | `issue_out` (stock OUT) |
| Production in | `prod` | `stock_production_in` | `factory_incharge` `[live]` | `production_in` (stock IN) + batch with expiry. Manual entry blocked if rule `production_requires_recipe` is on. |
| Transfer out | `xfer` | `stock_transfer` | `storekeeper`, `showroom_manager`, `factory_incharge` `[live]` | `transfer_out` at sender now; status `sent` (in transit) |
| Receive | (from transit tab) | `stock_receive_transfer` | same grant, receiver side | `transfer_in` at receiver for the received qty; status `received`. Short receipt raises yellow `transit_short`. |
| Cancel transfer | (transit tab) | `stock_cancel_transfer` | sender or grant holder, only while `sent` | reversing row |
| Counted quantity (count) | `count` | `stock_count_adjust` | **management only** `[live]` | `count_adjust` = counted minus book. Empty note is refused (`note_required`). Variance flag only if `count_tolerance_pct` is set. |
| Wastage | `waste` | `stock_wastage` (request) → `wastage_decide` | `storekeeper`, `showroom_manager`, `factory_incharge`, `management` `[live]` | Request row first (`wastage_requests`, pending). Posts `wastage` only when an approver decides. Reason must be from `wastage_reasons`. Photo required above `wastage_photo_above` if set. |

Read-only: **Stock ledger** (`stock_ledger_rows`), **expiring** list.

Note on the wastage path: the `phase12` definition is the current one. The `phase10` body is superseded, so it is not used here `[code]`.

### 3.3 Paper-form registry (`web/forms*.js`) `[code]`

46 form codes. Form = a structured paper record. Its stock/cash effect is listed in section 3.4.

| Code | Title (English) | File |
|---|---|---|
| 0-1 | Location settings sheet | forms_sales/forms_stock (see §7 G9) |
| 01-1 / 01-2 | Weekly review / monthly P&L and KPI | forms_sales.js |
| 02-1 … 02-8 | Attendance, salary, advance, appointment, leave, exit, duty card, skill checklist | forms_staff.js |
| 03-1 | Transfer challan (IBT) | forms.js |
| 04-1 | Goods received note (GRN) | forms_stock.js |
| 04-2 | Material issue slip | forms_stock.js |
| 04-3 | Stock count sheet | forms.js |
| 04-4 | Store ledger (read) | forms_stock.js |
| 05-1 … 05-5 | Factory daily sheet, product spec, recipe card, yield test, new product decision | forms_factory.js |
| 06-1 … 06-5 | Purchase requisition, quotation comparison, purchase order, bill check and payment request, supplier ledger | forms_stock.js |
| 08-1 | Maintenance request and record | forms_sales.js |
| 10-1 | Cash handover slip (showroom sends, hub receives) | forms.js |
| 10-2 | Expense voucher | forms.js |
| 10-3 | Digital payment reconciliation register | forms_cash.js |
| 10-4 | Cash position and purchase budget | forms_cash.js |
| 10-5 | Receivable and advance reconciliation | forms_cash.js |
| 11-1 | Shift handover register | forms_staff.js |
| 14-1 | Daily showroom sheet | forms.js |
| 14-2 | Jalebi counter daily record | forms_cash.js |
| 18-1 | Marketing expense register | forms_cash.js (not in earlier docs, §1 C6) |
| 20-1 | Customer order form | forms_sales.js |
| 20-2 | Discount approval slip | forms_sales.js |
| 20-3 | Return and complaint register | forms_sales.js |
| 20-4 | Party and wholesale invoice | forms_sales.js |
| 20-5 | Party and wholesale ledger | forms_cash.js |
| 20-6 | Online and delivery ledger | forms_cash.js |

Form submit / approve path `[code: entry.js → RPC submit_entry, decide_entry, save_entry]`.

Count sections (14-1 drawer, 10-1 hub) use `entry_counts` and `count_save`. The count is refused if the person is not the creator and does not hold the approve grant, unless the owner (`_count_can18`) `[code: phase18]`.

### 3.4 Cash, POS and other screens

**POS (`#/pos`)** `[code: web/pos.js]`
- Payment modes: `cash` (নগদ), `mobile`, `card`, `due` (বাকি). Due needs a customer; the code returns `customer_required` when the mobile is missing.
- Discount above the limit → `discount_needs_approval` (grant `discount_over_limit`). Price change → yellow flag `price_changed` (`price_override`).
- Offline: if there is no network, the sale is kept and sent later ("waiting to send").
- Void needs a written reason (`void_sale`).
- Sale return `#/salereturn`: RPC `sale_return` `[code: exists; batch/price rule unverified]`.

**Dues (`#/dues`)**: RPCs `customer_dues`, `customer_ledger`, `collect_payment`, `void_collection`. Oldest due paid first `[code: dues.js; oldest-first rule unverified]`.

**Cash moves (`#/cashmoves`)** `[code: web/cashmoves.js]`. 8 kinds:

| Kind | Money moves? | Notes |
|---|---|---|
| bank_deposit (cash → bank) | yes | |
| bank_withdraw (bank → cash) | yes | |
| owner_topup | yes | owner money into business |
| owner_draw | yes | owner takes money |
| cust_advance | yes | customer advance received |
| cust_advance_refund | yes | |
| cust_advance_used | no | advance used against a sale |
| hub_receipt | yes | hub received cash |

RPCs: `cash_move_add` (has dry-run), `cash_move_void` (needs reason, nothing deleted), `customer_advances`.

**Quick expense (`#/quickexp`) and day book (`#/daybook`)** `[code: daybook.js; quickexp route in ia.js]`. RPCs `day_book`, `set_daybook_start`, `set_daybook_opening`. Quick expenses become a 10-2 draft at day end `[code: phase72/74/79 reference; exact draft logic unverified]`.

**Purchase bill (`#/purchase/new`)** `[code: purchase.js]`. Fields: supplier, bill date, bill number (in bill), item, qty, rate, discount ৳, bill photo. Buttons: Save draft (খসড়া সংরক্ষণ), Post bill. RPCs `save_purchase`, `post_purchase`; payment `pay_supplier`.

**Exceptions / approvals**: `#/exceptions` (flags yellow/red), `#/pending` (waiting), `#/releases` (release requests, decided by `release_decide` or owner), `#/emergency` (one-time approval, `em_enabled`).

**Switchboard (`#/switchboard`)** lists every switch. Owner only.

### 3.5 Switches and rules used in this demo (live `[live]` unless noted)

| Switch / rule | Live value | Effect |
|---|---|---|
| `forms_post_to_ledger` | OFF | Paper forms do not post stock. The stock screen is the posting. |
| `blind_count_on` | OFF | Count is not hidden from the counter. |
| `owner_self_approve` | ON | Owner may approve own entries. |
| `stock_negative_mode` | `warn` | Sale with no stock is allowed with a warning; never blocked `[code: ALL_NEW3]`. |
| `period_closed_until` | blank | **No date lock.** Back-dated changes are allowed `[code comment: ALL_NEW10]`. |
| `count_tolerance_pct` | not checked | Empty = no variance flag `[code: ALL_NEW3, `if tol is not null`]`. |
| `pin_signature_on` | OFF (default) | Witness chosen from a list; no PIN signature `[code: phase18]`. |
| `em_enabled` | ON | Emergency approvals are possible. |
| `tools_stock_on` | OFF | `[live]` as stated in the audit. |

---

## 4. Grants: who can use what (live `rule_grants`, 13 rows checked)

| Grant | Live holders (besides owner, who passes everything) | Comment |
|---|---|---|
| `stock_opening` | none | Owner only (gap G1). |
| `stock_count_adjust` | management | Storekeeper and purchasing cannot post a count (gap G2). |
| `stock_issue` | storekeeper, factory_incharge | |
| `stock_transfer` | storekeeper, showroom_manager, factory_incharge | |
| `stock_production` | factory_incharge | |
| `wastage_write_off` | storekeeper, showroom_manager, factory_incharge, management | Request, then decision. |
| `purchase_entry` | purchasing, storekeeper | Storekeeper can enter bills too (separation question, G6). |
| `wastage_decide` | not in the 13-row check | Not checked. `[unverified]` |

Owner has all grants (`has_grant` returns true for owner) `[code: phase8]`.

Live self-approve check: no role currently has `allow_self_approve` `[live]`. The seed file sets it on `showroom_manager` `[code: phase seed]`. See G5.

---

## 5. Stories, per location, from opening to closing

Format: screen used → clicks → expected result → negative case. Route hashes are from `ia.js`. Click labels are the English text from the code's `L()` calls; where the button text was not confirmed it is marked `[unverified]`.

### S0. Pre-day setup (owner Karim, before 07:00, test project only)
- Screen: `#/switchboard`, `#/stock` → Stock actions → Opening balance.
- Clicks: 1. open `#/switchboard`, check `forms_post_to_ledger` OFF, `blind_count_on` OFF, `owner_self_approve` ON. 2. open `#/stock`, Stock actions → Opening balance: godown, sugar 60 kg, flour 50 kg, sweet A 30 kg; note required; save.
- Expected: one opening row per item per place. Balance shows 60 / 50 / 30.
- Negative: second opening for the same item and place → `opening_exists`. Jamal (storekeeper) tries it → `not allowed` (no `stock_opening` grant) `[code+live]`.

### S1. godown: goods in (07:30)
- Screen: `#/purchase/new` (Hasan, purchasing, bill entered the day before) then `#/stock` for the GRN.
- Clicks: Hasan: Purchase bill → supplier, bill number, item sugar, qty 40 kg, rate `[demo]`, Post bill. Jamal: form 04-1 GRN, counted 40, quality "accept".
- Expected: stock IN 40 kg sugar at godown `purchase_in` (because bill is posted). The GRN does not add stock again (`covered_by_purchase_page`, only when the switch is ON).
- Negative: Jamal posts the bill himself → he has `purchase_entry` grant (storekeeper) so it is allowed; separation between buyer and receiver is not enforced (G6). Test: post without supplier → refused.

### S2. godown → main: sugar issue (08:30)
- Screen: `#/stock` → Stock actions → Issue to production. Paper 04-2 issue slip is kept.
- Clicks: godown, sugar, qty 20 kg, note "issue to main"; submit. Selim signs the paper slip.
- Expected: `issue_out` godown −20 kg. Main sugar +20 kg is not created by this step; the issue has no receiving row. **Gap G7**: the receiving place is not stored on the issue, so main's sugar balance does not rise. The ledger shows the 20 kg leaving godown only.
- Negative: issue more than in stock → warn (`stock_negative_mode` = warn) `[code]`; issue with a unit not defined → `unit_unknown`.

### S3. godown → cake_factory: flour issue (08:45)
- Screen: `#/stock` → Issue to production (same as S2).
- Clicks: flour 15 kg; Mitu confirms on paper.
- Expected: godown −15 kg flour. Same gap G7 at cake_factory.
- Negative: issue flour to `cake_factory` by a salesperson → `not allowed` (no `stock_issue` grant).

### S4. main: sweet A production (09:00)
- Screen: `#/recipes` (Recipes and production) → Production in.
- Clicks: choose recipe "sweet A", 2 batches, actual yield 9.6 kg, made date today, Save.
- Expected: finished goods IN 9.6 kg with expiry from shelf-life rule; ingredients OUT per recipe `[unverified: recipe consumption not checked in code this round]`. Yield variance 4 % (10 vs 9.6) flagged.
- Negative: production without a recipe when `production_requires_recipe` is on → `recipe_required`. Yield note short → `note_required` if rule on.
- Then 05-1 Factory daily sheet (Selim) → submit → Salma approves (`#/pending`).

### S5. cake_factory: cake B production (09:40)
- Screen: `#/recipes` (Mitu).
- Clicks: "cake B", 1 batch, actual 6 kg.
- Expected: cake B IN 6 kg at cake_factory.
- Negative: Mitu tries to produce at `main` → `not allowed`.

### S6a. main → branch2: sweet A transfer (10:10) — added step, see C2
- Screen: `#/stock` → Stock actions → Transfer out (Rahim).
- Clicks: from main, to branch2, sweet A, qty 5 kg, note "showroom restock"; submit.
- Expected: main −5 kg now; status `sent`, shows in the transit tab.
- Negative: transfer to the same place → `bad_location`; qty 0 → `bad_qty`.

### S6. branch2 receives (10:15)
- Screen: `#/stock` → transit tab → Receive (Shirin).
- Clicks: open the transfer, received qty 5, Receive.
- Expected: branch2 sweet A IN 5 kg; status `received`.
- Negative: receive a transfer that is not `sent` → `not_in_transit`. Receive more than sent → `over_received`. Tania (salesperson) tries → `not allowed`.

### S7. main: POS cash + bKash sale (11:00)
- Screen: `#/pos` (Nasrin). Price per kg for sweet A `[demo ৳800]`.
- Clicks: Sell → item sweet A, qty 1.5 kg → Add to cart → Pay → cash ৳900, mobile ৳300 → Complete sale.
- Expected: stock OUT main 1.5 kg; cash ৳900, mobile ৳300 recorded.
- Negative: stock 0 at main → sale allowed with warning (`stock_negative_mode` = warn). Discount above limit without grant → `discount_needs_approval`.

### S8. branch2: POS cash sale (11:20)
- Screen: `#/pos` (Tania).
- Clicks: sweet A 2 kg, cash ৳1,600 `[demo]`, Complete sale.
- Expected: branch2 stock OUT 2 kg; cash ৳1,600 at branch2 (not yet handed to hub; see G8).
- Negative: Tania tries to void the sale without reason → refused; void with reason → yellow `sale_void` line.

### S9. main: POS due sale (11:30)
- Screen: `#/pos` (Nasrin).
- Clicks: sweet A 2 kg; Pay → due (বাকি); customer mobile entered; Complete sale.
- Expected: stock OUT main 2 kg; customer due +৳1,600 `[demo]`.
- Negative: due without mobile → `customer_required`. Unknown mobile → "customer not found" path `[unverified text]`.

### S10. main: customer order with advance (12:00)
- Screen: `#/customers` order form 20-1 (Ruma); or `#/onlineorders`.
- Clicks: customer, 5 kg sweet A, advance ৳1,000, delivery Friday; Save.
- Expected: record only. No stock. Advance is a liability until used (cust_advance in `#/cashmoves`).
- Negative: order without advance → allowed if rule; `[unverified]`.

### S11. cake_factory → al_cakes: cake B transfer (12:30)
- Screen: `#/stock` → Transfer out (Mitu), Receive (Lipi).
- Clicks: Mitu: cake_factory → al_cakes, cake B, 3 kg. Lipi: Receive 3.
- Expected: cake_factory −3 kg, al_cakes +3 kg.
- Negative: Lipi tries to receive without the transfer (or wrong place) → refused.

### S12. main: online order intake (12:45)
- Screen: `#/onlineorders` (intake_bot / Ruma).
- Expected: record in 20-6 only. Stock effect comes from the sale when delivered `[unverified]`.
- Negative: online order with no customer → refused `[unverified]`.

### S13. al_cakes: cake B cash sale (13:00)
- Screen: `#/pos` (Lipi).
- Clicks: cake B 1 kg (pound/kg unit as set), cash ৳300 `[demo]`.
- Expected: al_cakes −1 kg; cash ৳300 at al_cakes (not handed over; G8).
- Negative: Lipi gives 300 back as discount beyond limit → `discount_needs_approval`.

### S14. main: dues collection (13:15)
- Screen: `#/dues` (Nasrin).
- Clicks: enter customer mobile, amount ৳600, mode cash, Collect.
- Expected: customer balance down ৳600; cash in ৳600.
- Negative: collect more than due → refused `[unverified]`; void collection without reason → refused.

### S15. godown → mishti_bari: second transfer (13:45)
- Screen: `#/stock` (Jamal).
- Clicks: transfer out sweet A 10 kg to mishti_bari.
- Expected: godown −10 kg; `sent`.
- Negative: transfer more than stock → warn only (stock_negative_mode).

### S16. mishti_bari: receive both transfers (14:00, 15:00)
- Screen: `#/stock` transit tab (Ayesha).
- Clicks 14:00: Receive first transfer, qty 10. 15:00: Receive second transfer, qty 9 (sent 10).
- Expected: mishti_bari IN 10 kg then IN 9 kg; yellow exception `transit_short` (1 kg). **G3**: the 1 kg is not in any ledger balance after receive.
- Negative: receive over the sent qty → `over_received`. Cancel by Ayesha after receive → refused (not `sent`).

### S17. branch2: sales return (15:30)
- Screen: `#/salereturn` (Shirin) and `#/forms` 20-3 register.
- Clicks: find sale, return 1 unit, reason, refund mode cash; Save.
- Expected: stock back to original batch at original cost `[unverified: batch rule]`; refund recorded.
- Negative: return without sale → refused. Refund above sale → refused `[unverified]`.

### S18. main hub: cash handover, hub count (16:00)
- Screen: form 10-1 (`#/entries` / forms) for the cash slip; hub count in same form.
- Clicks: Rahim: count notes ৳25,000, sign sender side. Sohel carries. Fatema: count ৳24,800, sign receiver side.
- Expected: difference ৳200 red; reason required. Cash move to hub is **not** created automatically `[unverified: no code link found, G8]`.
- Negative: Fatema submits without reason → blocked (red flag must be resolved). Rahim approves own handover → `maker_cannot_approve` unless owner self-approve (owner only).

### S19. main hub: digital and cash position (16:20–16:30)
- Screen: forms 10-3, 10-4, 10-5 (Fatema).
- Clicks: 10-3 enter bKash total from phone; 10-4 cash position; 10-5 receivables check.
- Expected: 10-3 matches demo ৳300 (main bKash); mismatch → yellow flag.
- Negative: mismatch with no note → refused until note.

### S20. main: expense (17:00)
- Screen: `#/quickexp` (Rahim) or form 10-2.
- Clicks: head "tea and small repair", payee, receipt yes, amount ৳350, Save.
- Expected: one expense in day book; not counted twice. Day end creates a 10-2 draft to check once (duplicate detection is after-the-fact, G10).
- Negative: enter the same expense in both 10-2 and quick expense → duplicate suspect in report, not blocked (G10). Over expense limit → yellow `over_limit`.

### S21. al_cakes: shift handover (17:30)
- Screen: form 11-1 (Lipi). Record only.
- Negative: missing shift name → refused `[unverified]`.

### S22. approvals (18:00, 18:20)
- Screen: `#/pending` (Salma), form 14-1 approve for main (Rahim's day sheet), 10-2, 05-1 (Selim). Branch2: Shirin → Salma approves 14-1, 20-2 slip if any.
- Expected: status approved; no stock change from forms (switch OFF).
- Negative: Rahim approves his own 14-1 → blocked (not owner, no self-approve, live) `[live]`. Salma approves a form she has no approve grant for → not allowed. Approve with a red flag open → blocked until release (`#/releases`).

### S23. godown: stock count (18:30)
- Screen: form 04-3 (Hasan counts, Anwar witnesses, Jamal does not count) and `#/stock` → Stock actions → Counted quantity (Stock count is posted by a manager only, G2).
- Clicks: Hasan enters counted quantities for 5 items. Anwar signs witness. Management posts "Counted quantity" per item where variance exists.
- Expected: `count_adjust` rows only for posted counts. Variance flag only if tolerance set (G4).
- Negative: Jamal counts own stock → form refuses (rule in demo docs; **not enforced in the stock RPC**, G6). Count with blank note → `note_required`. Witness = counter → not enforced in code (G6).

### S24. head office: purchase requisition and quotes (19:00)
- Screen: form 06-1, 06-2 (Hasan). Record only.
- Expected: no stock or cash.
- Negative: approve own requisition → refused by approver rule `[unverified]`.

### S25. main: recipe change approval (19:20)
- Screen: `#/recipes` (Selim) → recipe change; Nazia approves.
- Expected: new recipe version; live recipe changes after approval `[unverified]`.
- Negative: Selim approves own recipe → `maker_cannot_approve` unless owner (owner only self-approve on, G5).

### S26. head office: attendance (19:30)
- Screen: form 02-1 (Anwar). Record only.
- Negative: punch twice in one day → counted once `[unverified]`.

### S27. all places: exceptions and day close (20:00–20:40)
- Screen: `#/exceptions` (Karim): transit short, hub difference, count variance. Each needs a note to resolve.
- Expected: exceptions closed or released with note. Day closed per place (14-1 approved, no red flags).
- Negative: close a red flag without note → refused. Post an entry for a closed day → `period_closed_until` is blank, so **not blocked** (G9).
- 20:40 read-only: `#/daybook`, reports `daybook_vs_journal`, `dup_suspects`. Nothing changes.

---

## 6. Demo stock ledger and balance sheet at day end (demo numbers)

Demo numbers, not from the live database (stock ledger = 0 rows `[live]`). Quantities in kg. Prices `[demo]`: sweet A ৳800/kg, cake B ৳300/kg.

### 6.1 Stock ledger (quantities)

| Place | Item | Opening | In | Out | Closing | Source of entries |
|---|---|---|---|---|---|---|
| godown | sugar | 60 | 40 (S1 purchase) | 20 (S2 issue) | **80** | ledger rows `opening`, `purchase_in`, `issue_out` |
| godown | flour | 50 | 0 | 15 (S3 issue) | **35** | `issue_out` |
| godown | sweet A | 30 | 0 | 20 (S15, 10 + 10 kg transfer out) | **10** | `transfer_out` ×2 |
| main | sugar | 0 | 20 (S2 issue, but no receipt row, G7) | recipe use `[unverified]` | `[unverified]` | `issue_out` at godown only |
| main | sweet A | 0 | 9.6 (S4 production) | 5 (S6a transfer), 1.5 (S7 POS), 2 (S9 due) | **1.1** | `production_in`, `transfer_out`, `sale_out` |
| branch2 | sweet A | 0 | 5 (S6 receive) | 2 (S8 POS) | **3** | `transfer_in`, `sale_out` |
| mishti_bari | sweet A | 0 | 10 (S16) + 9 (S16) = 19 | 0 | **19** | `transfer_in` ×2 |
| cake_factory | flour | 0 | 15 (S3 issue) | recipe use `[unverified]` | `[unverified]` | `issue_in`, consumption not checked |
| cake_factory | cake B | 0 | 6 (S5 production) | 3 (S11 transfer) | **3** | `production_in`, `transfer_out` |
| al_cakes | cake B | 0 | 3 (S11 receive) | 1 (S13 POS) | **2** | `transfer_in`, `sale_out` |

Reconciliation, sweet A across all places: opening 30 + produced 9.6 = 39.6. Sales out 1.5 + 2 + 2 = 5.5. Missing in transit 1 (G3). Closing 39.6 − 5.5 − 1 = **33.1**. Places: 10 + 1.1 + 3 + 19 = 33.1. Matches.

Cake B: produced 6, sold 1, closing 3 + 2 = 5. Matches.

Sugar and flour at main and cake_factory: recipe consumption `[unverified]`, so closings there are unknown.

Stock value: `[unverified]`. Costs are in `ITEM_COST` (57 cost rows live) and were not used here.

### 6.2 Cash and sales (day, demo ৳)

| Item | ৳ | Note |
|---|---|---|
| Sales main (S7 cash 900 + mobile 300) | 1,200 | cash 900, bKash 300 |
| Sales branch2 (S8 cash) | 1,600 | cash |
| Sales main due (S9) | 1,600 | receivable, not cash |
| Sales al_cakes (S13 cash) | 300 | cash |
| **Total sales** | **4,700** | |
| Cash received: dues (S14) | 600 | from opening receivable |
| Customer advance (S10) | 1,000 | liability; mode `[unverified]` |
| Expense (S20) | (350) | assumed paid from hub cash after the 16:00 count |
| Hub count 16:00 (S18), counted by Fatema | 24,800 | drawer 25,000, difference 200 red `[demo]` |

Opening cash float and prior-day cash are not in the story, so the hub count cannot be checked against sales. `[unverified]`.

### 6.3 Balance sheet at day end (demo, ৳)

| Assets | ৳ | Liabilities and equity | ৳ |
|---|---|---|---|
| Cash at hub (after 16:00 count and ৳350 expense) | 24,450 | Customer advance (S10) | 1,000 |
| Cash at branch2, not handed over (S8) | 1,600 | Supplier payable, sugar bill (S1) | `[unverified]` |
| Cash at al_cakes, not handed over (S13) | 300 | Staff advances and salary | `[unverified]` |
| bKash / digital (S7), reconciled at 10-3 | 300 | Owner capital (opening) | `[unverified]` |
| Receivables, customer due (S9) | `[opening]` + 1,000 | Retained result, day (sales 4,700 − expense 350) before cost of goods | 4,350 (before COGS `[unverified]`) |
| Stock, quantities per §6.1 | see 6.1 | | |
| Stock value | `[unverified]` | | |
| Memo: unexplained short 1 kg sweet A (G3) | — | | |
| Memo: hub difference 200 (S18), open | — | | |

Balance: **not balanced.** Opening capital, opening receivable, supplier bill amount, cost of goods and staff ledger are `[unverified]`. Cash at branch2 and al_cakes is not handed to hub in the story (G8), so it is shown as a separate asset.

Statement: these numbers are demo only, prepared by hand from the story. They are not produced by the system because the stock ledger and journal are empty in the live database `[live]`.

---

## 7. Gaps, missing audits and system update suggestions

Priority: H = fix before real use; M = before the demo; L = later.

| # | Gap | Evidence | Pri | Suggested update |
|---|---|---|---|---|
| G1 | Opening stock is owner-only. Earlier demo says storekeeper enters it. | `stock_opening` has no `rule_grants` row `[live]`. | H | Grant `stock_opening` to storekeeper for godown, or make an opening batch form (the older doc suggested it). |
| G2 | Count adjustment is management-only. Storekeeper and purchasing cannot post a count. | `stock_count_adjust` → management `[live]`. | H | Decide: grant to storekeeper (separate from counter), or keep manager. Document it. |
| G3 | A short transfer receipt removes stock with no ledger row. Only a yellow flag remains. | `stock_receive_transfer` inserts only `rq`; the `transfer_out` already took the full qty `[code: phase10]`. | H | Add a `transit_loss` ledger reason on short receipt, with approval before it is final. |
| G4 | Count variance is not flagged unless `count_tolerance_pct` is set. | `if tol is not null` in `stock_count_adjust` `[code: phase10]`. | H | Owner sets a tolerance value. Default should not be empty. |
| G5 | Self-approve: seed sets `allow_self_approve` on `showroom_manager`. Live has none `[live]`. Drift risk. | seed in migrations `[code]`; live query returned no `allow_self_approve` roles. | H | Keep live as is. Add a test that fails if a role gets self-approve. Owner self-approve is ON by design; decide whether to keep it for the demo. |
| G6 | Counter ≠ storekeeper and witness ≠ counter are not enforced in the stock RPC. Count has no counter or witness field. | No such check in `stock_count_adjust`, `_stock_guard`; form-level only `[code]`. | H | Store `counted_by` and `witnessed_by` on each count row; reject if counter = storekeeper or witness = counter. Turn on `pin_signature_on` for witness. |
| G7 | Issue has no receiving place, so the receiving side is not posted. | `stock_issue(p_item, p_loc, …)` has no destination `[code]`. | M | Issue to production should post `production` receive or use a transfer to the factory place. |
| G8 | Branch cash is not handed to hub automatically; 10-1 → cash move link not found. | No `cash_move` insert in the handover path `[code search, unverified]`. | M | Create a cash-in-transit line on handover send; clear on hub receive. |
| G9 | No period lock: `period_closed_until` is blank. Back-dated entries are allowed. | Blank setting `[live]`; comment in `ALL_NEW10`. | M | Owner sets a close date at each day end. |
| G10 | Duplicate expense (10-2 and quick expense) is detected only after the fact. | `dup_suspects` is a report `[code]`. | M | Warn at entry when the same amount, head and day exist. |
| G11 | No stock value in demo; costs not linked to the ledger. | `ITEM_COST` 57 rows `[live]`; balance sheet uses placeholders. | M | Link cost to each stock row and show value on the ledger. |
| G12 | Negative stock is allowed with warn. The sale still happens. | `stock_negative_mode` = warn `[live]`. | M | Show a daily report of negative stock; owner decides `block` for high-value items. |
| G13 | Shape of 18-1 (marketing) and 0-1 (location settings) is not in the demo flow. | forms in code §3.3. | L | Add to demo day or mark out of scope. |
| G14 | Security advisor: 12 anon-callable SECURITY DEFINER functions, 80 functions without `search_path`, leaked-password protection off, 34 RLS policies with `auth.uid()` not wrapped. | Read-only audit `docs/SUPABASE_READONLY_AUDIT.md` (advisor run earlier). | H (before go-live) | Owner approves the fix list in that audit. Not done here. |

Audit trail gaps: no counter, witness or handover-receiver id on stock rows (G6); no reason stored for shortfall (G3); no record of who changed a switch except `audit_log` (≈2,370 rows live) `[live]`.

Doc fixes: C1–C6 in section 1.

Verification not done: the stories were checked by reading code, not by running the app on a test project. `[unverified]` items must be tested first.

---

## 8. Test plan (short)

1. Create 17 test accounts in a test project (roster). Do not use live.
2. Run S0–S27 in order. Record each expected result against the actual screen.
3. Run the negatives: Jamal counts own stock; Selim approves own recipe; Rahim approves own 14-1; due sale without mobile; over-limit discount; receive over sent; period lock with a back date.
4. Check the ledger totals match §6.1 and the cash figures match §6.2.

---

## 9. Skill suggestions

- The skill named `/Token-Optimization` was not in this session's skill list, so it was not used. Check the exact name, or install it, and re-run this doc with it.
- `anthropic-skills:xlsx`: turn §6.1 into a spreadsheet for the owner, with formulas for closing balances.
- `anthropic-skills:docs` or `doc-coauthoring`: for the owner to review and comment on this doc with the translator.
- `bos-organise`: use it if any screen or route is renamed or hidden, because it keeps `web/ia.js` as the one registry.
- A new skill for "demo day runner" could re-run S0–S27 on a test project and compare ledger totals. Only useful after G1–G6 decisions.

---

## 10. Source files read

- `docs/DEMO_FULL_WORKFLOW_AND_LEDGER.md`, `docs/DEMO_STAFF_ROSTER.md`, `docs/SUPABASE_READONLY_AUDIT.md`, `docs/REAL_LIFE_STORY_GUIDE.md`, `docs/REAL_LIFE_DAILY_WORKFLOW_GUIDE.md`
- `web/ia.js` (90 routes), `web/stock2.js`, `web/pos.js`, `web/cashmoves.js`, `web/purchase.js`, `web/daybook.js`, `web/forms.js`, `web/forms_cash.js`, `web/forms_sales.js`, `web/forms_stock.js`, `web/forms_factory.js`, `web/forms_staff.js`, `web/entry.js` (grep-level)
- `supabase/phase10.sql` (stock RPCs, seeds), `phase12.sql` (wastage request), `phase74.sql` (production), `phase17.sql` (decide_entry), `phase18.sql` (count), `ALL_NEW3.sql`, `ALL_NEW10.sql` (switch comments)
- Live (read-only): `roles.allow_self_approve`, `rule_grants` for stock and wastage grants.

Not read in full: `entry.js` (918 lines), `nav.js`, `costing.js`, `recipes.js`, most reports. Items that depend on them are `[unverified]`.
