# Real-life daily workflow guide (English), location-based

Islamia Misty Ghar · BOS app · who enters what, from which location, and one full demo day

- Source: the code on branch `ccr-46b26d91-81vl9s` (`web/`, `supabase/ALL_NEW*.sql`, seed `locations` rows). A read-only audit of the live database (project Islamiya-Bos) was added on 2026-10-16 — see `docs/SUPABASE_READONLY_AUDIT.md`. Nothing was changed in it.
- All names of people are **fictitious demo names**. No staff accounts exist, and the owner has not granted any permission. Everything below is the **intended setup**, not the current state.
- Quantities and money amounts are illustrative.

---

## 0. How to read this

**Status tags**

- `[Live-code]` the screen and its logic exist in code.
- `[Needs switch]` the stock or ledger effect happens only when an owner switch is ON.
- `[Not built]` no code found.
- `[Unverified]` not confirmed from code or a live database.

**Two rules that apply everywhere**

1. **Enter, then Approve.** A maker enters and submits. A different person approves. The owner may approve own work only while `owner_self_approve` is ON (ON in code by default).
2. **A location is a place, and a person sees only the places they are granted.** The owner and management see all places. Everyone else sees only the place(s) assigned to them.

---

## 1. Location map

Codes are the real `locations.code` values in the seed files. The left column shows the short names you used; the mapping is my reading and must be confirmed by the owner.

| Your short code | App code | Place (English name in seed) | Status | What happens here |
|---|---|---|---|---|
| `IMG-M` (assumed) | `main` | ISLAMIYA MISTY GHAR — Main Showroom & Main (Sweet) Factory | Active | Main showroom and the main sweet factory. Retail sales, production, party orders. |
| `IMG-2` (assumed) | `branch2` | ISLAMIYA MISTY GHAR — 2nd Branch | Active | Second showroom. Retail sales. |
| `IMG-3` | not found | not in seed | **Unknown** | No code matches. Owner to confirm. |
| `AL-C` (assumed) | `al_cakes` | AL-CAKIZ (below the residence) | Active | AL-CAKIZ showroom. |
| `CF` (assumed) | `cake_factory` | Cake Factory (below the residence) | Active | Cake production (assumed). |
| `GD` (assumed) | `godown` | Godown (lane beside ISLAMIYA MISTY GHAR) | Active | Central store for raw material, packaging and goods in stock. |
| `SF` (assumed) | `mishti_factory` | Mujgunni Sweet Factory | **Closed** (machines stored, `paused`) | Not in use now. Only resume when the owner decides. |
| — | `mishti_bari` | MISTY BARI | Active | Showroom for the MISTY BARI brand. |
| — | `main` (hub) | Cash hub | **Verified live** | In the live database `main` has `hub_functions = true`; no other place does. The hub is the Main Showroom, not a separate place. Cash controller is granted `main`. |

**Owner to confirm before this guide is final:** the meaning of `IMG-3`, `CF`, `SF` and `GD`; where the hub is; whether `SF` will resume.

Brand names used on forms (code `brand` lists): ISLAMIYA MISTY GHAR, MISTY BARI, AL-CAKIZ, Other.

---

## 2. Roles by location (intended setup, not granted)

Roles are **per location**. A person can hold one role at one place, or a role at several places if the owner grants it. Names are demo only.

| Role | Main location | Other places | What the role does |
|---|---|---|---|
| **Owner** | all | all | Sets rules and limits, approves exceptions, decides releases. |
| **Management** | all | all | Approves most entries, views reports and all locations. |
| **Showroom manager** | `main` (Rahim) | `branch2`, `mishti_bari`, `al_cakes` (one per showroom) | Runs one showroom: day sheet, handover, shift handover, expenses, transfers in. |
| **Recipe approver / Intake bot** | head office / system | — | Live roles `recipe_approver` (approves recipes) and `intake_bot` (online-order intake only). Not part of the demo day. |
| **Salesperson / cashier** | one showroom | — | POS sales, dues collection, customer orders. |
| **Storekeeper** | `godown` (Jamal) | — | Receives goods, issues material, transfers out, counts stock. |
| **Factory in-charge** | `main` (Selim, main sweet factory) | `cake_factory` if granted | Production, daily factory sheet, yield tests, recipe cards. |
| **Purchasing** | head office (no place row; uses purchase grants) | all receiving places | Requisitions, quotes, orders, bills, supplier ledger. |
| **Cash controller** | hub (Fatema) | all showrooms (view and handover) | Handover counts, digital payment register, cash position, expenses review. |
| **Party coordinator** | `main` (Ruma) | — | Party and wholesale invoices, customer orders, party ledger. |
| **HR** | head office (Anwar) | all places (view, not stock) | Attendance, salary sheet, advances, leave. |
| **Carrier** | moves cash and goods between places (Sohel) | — | Carries cash and challans; does not approve. |

**Gaps:** a showroom manager at each showroom, and a dedicated storekeeper at each showroom, are not yet seeded. The owner must decide who holds which role at which place before any entry is made.

---

## 3. Each form: where, who, how, what after Approve

Read each row as: **Enter at** (location) · **Entered by** (role) · **Approved by** (role) · **After Approve**.

### 3.1 Showroom day

| Form | Enter at | Entered by | Approved by | How (short) | After Approve |
|---|---|---|---|---|---|
| **14-1 Daily Showroom Sheet** `[Live-code]` | each showroom | Showroom manager | Management | Opening float, receipts, sales by category, cash count by note, closing stock, checklist. Count cash first. | No stock or ledger posting. Drawer expected vs counted shown. Short/over beyond `cash_tol` is red. Needs `drawer_float`, `imprest`, `cash_tol`. |
| **14-2 Jalebi Counter Record** `[Live-code]` | `main` (counter) | Salesperson | Showroom manager | Counter production, sales, waste. | Record only. |
| **11-1 Shift Handover Register** `[Live-code]` | each showroom | Showroom manager | — | Shift-to-shift handover with serial no. (used in 14-1). | Record only. |
| **20-2 Discount Approval Slip** `[Live-code]` | showroom | Showroom manager | Management or owner | Written approval for discount above limit. | Record. POS uses it for discount reports. |
| **20-3 Return and Complaint Register** `[Live-code]` | showroom | Showroom manager or salesperson | — | Book of returns and complaints. | Record. Refund figure typed into 14-1 with the register no. |
| **08-1 Maintenance Request** `[Live-code]` | showroom | Showroom manager | Management | Repair request with photos, then the record. | Record. No asset posting. |
| **02-5 Leave Application** `[Live-code]` | showroom | Showroom manager (for staff) | HR | Leave request. | Record. |

### 3.2 Point of sale (POS) and customers

| Form / screen | Enter at | Entered by | Approved by | How (short) | After save / Approve |
|---|---|---|---|---|---|
| **POS sale (Sell)** `[Live-code]` | each showroom | Salesperson or cashier | — (grants for over-limit) | Items by kg, piece or pound. Split payment: cash, bKash, Nagad, card, or due. Mobile needed for due and wholesale. | Tracked items leave that showroom's stock at once (`sale_out`). Due adds to customer balance. Discount above limit needs `discount_over_limit`; price change needs `price_override`. |
| **Sale return** `[Live-code]` | showroom | Salesperson with POS return grant `[Unverified]` | Showroom manager if grant requires | Sale, items, quantities, reason, refund mode. | Stock back into original batch at original cost. Value reduces the customer's due first; the rest is refunded. |
| **Dues collection** `[Live-code]` | showroom | Salesperson | — | Customer mobile, amount, mode. Oldest due paid first. | Customer balance goes down. Shows in 14-1 as "earlier dues collected". |
| **20-1 Customer Order** `[Live-code]` | showroom or `main` | Salesperson or party coordinator | — | Customer, items, date, advance. | Record. Links to the sale when delivered (`sale_form_link`). |
| **20-4 Party and Wholesale Invoice** `[Live-code]` | `main` | Party coordinator | Management (suggested) | Party order invoice. | Record. Party cash typed into 14-1 `[Unverified]` on automatic link. |
| **20-5 Party Ledger** `[Live-code]` | `main` | Party coordinator | — | Who owes what. | Read or record. |
| **20-6 Online and Delivery Ledger** `[Live-code]` | `main` or showroom | Carrier or party coordinator | — | Order, link to sale, deliver, cancel. | Link to sale. Stock effect comes from the sale `[Unverified]`. |

### 3.3 Cash, bank and hub

| Form | Enter at | Entered by | Approved by | How (short) | After Approve |
|---|---|---|---|---|---|
| **10-1 Cash Handover Slip** `[Live-code]` | showroom (sender) and hub (receiver) | Showroom manager sends; cash controller receives; carrier carries | Management or owner if hub difference | Sender counts by note and leaves float. Hub counts by note. Difference is red (`hub_diff`) and needs a reason. | No stock. Ledger date and line no. written by hand. Automatic cash-move creation `[Unverified]`. |
| **10-2 Expense Voucher** `[Live-code]` | showroom or hub | Showroom manager or cash controller | Management (suggested) | Head, payee, receipt yes/no, amount. Over `expense_max` is yellow. | No stock. Counted once in the day book. Quick expenses get a 10-2 shadow at day end. |
| **10-3 Digital Payment Register** `[Live-code]` | hub | Cash controller | — | bKash, Nagad, card totals vs phone and machine. | Record. Mismatch is a flag. |
| **10-4 Cash Position and Purchase Budget** `[Live-code]` | hub | Cash controller | Management | Cash in hand vs hub limits. | Record `[Unverified]` on exact checks. |
| **10-5 Receivable and Advance Check** `[Live-code]` | hub or showroom | Cash controller | — | Dues and customer advances vs ledger. | Record `[Unverified]` on ledger cross-check. |
| **Cash and bank moves (screen)** `[Live-code]` | location where the cash is | Cash controller or owner | Per grant | Deposit, withdrawal, owner money in/out, advance, hub receipt. | Cash and bank balance, day book. No stock. |
| **Quick expense (day book)** `[Live-code]` | any place with grant | Staff with 10-2 grant, or owner | — | One-line expense: head, amount, mode, receipt. | Day-end creates a 10-2 draft. Counted once. |

### 3.4 Stock, godown and transfers

| Form / screen | Enter at | Entered by | Approved by | How (short) | After Approve / post |
|---|---|---|---|---|---|
| **03-1 Transfer Challan (paper)** `[Live-code]` `[Needs switch]` | sending and receiving place | Storekeeper (`godown`) or showroom manager | Receiver confirms; management | From, to, items, sent qty, receiver's qty. Shortfall is a red flag. | Default (primary `a`): no stock change from the paper. The **Stock screen transfer** is the posting. |
| **Stock: Transfer** `[Live-code]` | sender place | Storekeeper or showroom manager (grant `stock_transfer`) | — | Item, qty, unit, to-place, note. | Stock OUT at sender at once. Goes to "in transit". |
| **Stock: Receive** `[Live-code]` | receiver place | Receiving storekeeper or showroom manager | — | Opens In transit, types received qty. | Stock IN at receiver. Short receipt creates yellow `transit_short`. Not written off automatically. |
| **Stock: Cancel transfer** `[Live-code]` | sender place | Sender | — | Only while in transit. | Reversing row. |
| **04-1 Goods Received Note** `[Live-code]` `[Needs switch]` | `godown` (or showroom receiving) | Storekeeper | Management | Challan no., written vs counted, quality (accept, reduce, hold, return), rate. | No stock change by default. With the switch, purchase lines are skipped (`covered_by_purchase_page`) because the purchase bill posts. |
| **Purchase bill (screen)** `[Live-code]` | place where goods arrive | Purchasing (grant `purchase_entry`) | — | Supplier, bill no., lines. Save, then Post. | Stock IN at that place (`purchase_in`). Supplier payable goes up. |
| **04-2 Material Issue Slip** `[Live-code]` `[Needs switch]` | `godown` to `main` (factory) | Storekeeper | Factory in-charge receives | Items, issued qty, returned qty, purpose. | Default: no stock from the paper. **Stock: Issue** (`stock_issue`) is the posting. |
| **Stock: Issue / Count / Opening / Wastage** `[Live-code]` | place of the stock | Storekeeper; wastage requested by staff | Wastage approver (`wastage_decide`) | Issue to factory. Count adjust with note. Opening once per item per place. | Stock moves. Count variance beyond tolerance is a yellow exception. |
| **04-3 Stock Count Sheet** `[Live-code]` `[Needs switch]` | `godown` or showroom | Counter (not the storekeeper) | Witness (different person) | Counted vs book. Variance beyond `count_tol_pct` / `count_tol_max` is red. Reason on each differing row. | Default: no change from paper. **Stock: Count adjust** is the posting. |
| **04-4 Store Ledger** `[Live-code]` | any place | Storekeeper, cash controller, management (view) | — | Read-only movement book per item. | No posting. The proof screen. |
| **05-1 Factory Daily Sheet** `[Live-code]` `[Needs switch]` | `main` (Sweet Factory) | Factory in-charge | Management (suggested) | Output by item, fridge checks, notes. | Default: no change from paper. **Recipes and production** is the posting. |
| **Recipes and production (screen)** `[Live-code]` | `main` | Factory in-charge (grant `stock_production`, `stock_issue`) | — | Pick recipe, batches, actual yield if different. | Ingredients OUT per recipe. Finished goods IN as a batch with expiry. Yield variance recorded. |
| **05-2 Product Spec** / **05-3 Recipe Card** / **05-4 Yield Test** / **05-5 New Product Decision** `[Live-code]` | `main` | Factory in-charge; management and owner for 05-5 | Management | Specs, paper recipe, yield test, new product decision. | Record only. Live recipe is kept in Recipes (`recipe_save`). |

### 3.5 Purchasing (head office, buys for all places)

| Form | Enter at | Entered by | Approved by | How (short) | After Approve |
|---|---|---|---|---|---|
| **06-1 Purchase Requisition** `[Live-code]` | head office | Purchasing | Management (suggested) | Items, qty, need-by date, reason. | No stock or cash. |
| **06-2 Comparative Statement** `[Live-code]` | head office | Purchasing | — | Quotes side by side, choose supplier. | No stock or cash. Over-limit rule `[Unverified]`. |
| **06-3 Purchase Order** `[Live-code]` | head office | Purchasing | Management (suggested) | Supplier, items, price from CS. | No stock or cash. Stock comes on the purchase bill. |
| **06-4 Bill Check and Payment Request** `[Live-code]` | head office | Purchasing | Management (suggested) | Bill vs PO vs receipt. | A request only. Payment through supplier payables (`pay_supplier`). |
| **06-5 Supplier Ledger** `[Live-code]` | head office | — (view) | — | Owed to each supplier. | Read only. |

### 3.6 Staff and HR (head office)

| Form | Enter at | Entered by | Approved by | How (short) | After Approve |
|---|---|---|---|---|---|
| **02-1 Attendance Register** `[Live-code]` | head office | HR | — | Monthly attendance. Punch screens are separate. | Record. |
| **02-2 Salary Sheet** `[Live-code]` | head office | HR | Owner or management | Salary per person, deductions, advances. | Locked once payroll starts for the month `[Unverified]`. |
| **02-3 Advance Register** `[Live-code]` | head office | HR | — | Advances, linked to payroll `[Unverified]`. | Record. |
| **02-4 Appointment Terms / 02-6 Exit Clearance / 02-7 Duty and Backup / 02-8 Skill Checklist** `[Live-code]` | head office | HR | — | Records. | Record. |

### 3.7 Owner, settings and items

| Form / screen | Enter at | Entered by | Approved by | How (short) | After |
|---|---|---|---|---|---|
| **01-1 Weekly Review / 01-2 Monthly P&L and KPI** `[Live-code]` | head office or any | Owner | — | Owner notes. P&L numbers from Reports `[Unverified]`. | Record. |
| **0-1 Location Settings Sheet** `[Live-code]` | per place | Owner | — | Limits per place: float, imprest, tolerances, fridge range. | New settings version. |
| **Items and prices** `[Live-code]` | head office | Owner direct; others send a request (`itemreq`) | Owner or delegate | Item list and selling price. | Prices apply to future sales only. |
| **Cost price (ITEM_COST)** `[Live-code]` | — | Only with `ITEM_COST` grant | — | Visible and editable only with the grant. | — |
| **Exceptions list** `[Live-code]` | any place with grant | Automatic | Owner or releaser | Yellow and red flags from every form. | Release or resolve. |

---

## 4. Controls in one list

- **Count first:** counted figure entered before expected figure is shown (on by default, `count_first`).
- **Red blocks Submit** until a release is approved (`red_block`). Yellow is a warning.
- **Release request:** maker asks, owner or a person with `release_decide` decides.
- **Emergency request:** one-use approval or a short window (`em_enabled`).
- **Transfers:** stock leaves the sender at once; the receiver posts the arrival. Short receipts are flagged, not hidden.
- **Blind count:** server-side hidden count is OFF by default (`blind_count_on`). Turn on only after the owner decides.
- **Period lock:** `period_closed_until` is empty by default, so no closed period yet.

---

## 5. One complete demo day (full roster, all 7 places)

Assumption: every grant below is already given to the named demo person (permissions treated as granted). Run this only in a **test project or test accounts**, never on the live database. Names come from `docs/DEMO_STAFF_ROSTER.md`.

**Pre-day setup (owner Karim, before 07:00)**
- Create the 17 test accounts and assign each role and place from the roster.
- Keep switches as they are today: `forms_post_to_ledger` OFF, `blind_count_on` OFF, `owner_self_approve` ON.
- Enter opening stock per place (`Stock: Opening`), because `stock_ledger` is empty. Example: godown sweet A 30 kg, sugar 60 kg, flour 50 kg; main sweet A 0; cake_factory cake B 0; branch2 sweet A 5 kg.

| Time | Place | Who | Action (screen / form) | Result |
|---|---|---|---|---|
| 07:00 | godown | Jamal | Stock: In transit list | Empty |
| 07:30 | godown | Hasan (purchasing, head office) | Purchase bill: 40 kg sugar, posted at godown (entered the day before) | Stock IN 40 kg sugar at godown |
| 08:00 | godown | Jamal | 04-1 GRN for the sugar: counted 40, quality accept | No extra stock effect (switch OFF) |
| 08:30 | godown → main | Jamal, Selim | 04-2 issue slip 20 kg sugar; then Stock: Issue 20 kg | Stock OUT godown 20 kg; Selim signs |
| 08:45 | godown → cake_factory | Jamal, Mitu | 04-2 issue 15 kg flour; Stock: Issue | Stock OUT godown; Mitu receives |
| 09:00 | main | Selim | Recipes and production: "sweet A", 2 batches, actual yield 9.6 kg | Ingredients OUT; finished goods IN as batch with expiry; 4% yield variance |
| 09:20 | main | Selim | 05-1 Factory Daily Sheet, submit | Waits for Salma; no stock from paper |
| 09:40 | cake_factory | Mitu | Recipes and production: "cake B", 1 batch, yield 6 kg | Stock IN 6 kg cake B at cake_factory |
| 10:00 | godown | Jamal | Stock: Transfer 10 kg sweet A → mishti_bari (in transit) | Stock OUT godown; row in transit |
| 10:15 | branch2 | Shirin | Stock: Transfer 5 kg sweet A from main, receive 5 kg | Stock IN branch2 |
| 10:30 | main | Rahim | 14-1 Daily Showroom Sheet: opening float, count cash by note | Drawer expected shown after count |
| 11:00 | main | Nasrin | POS sale 1.5 kg sweet A; cash 900, rest bKash | Stock OUT main; cash and wallet recorded |
| 11:20 | branch2 | Tania | POS sale 2 kg sweet A, cash | Stock OUT branch2 |
| 11:30 | main | Nasrin | POS sale 2 kg on due; mobile entered | Customer balance up; stock OUT |
| 12:00 | main | Ruma | 20-1 Customer order 5 kg, advance 1000, delivery Friday | Record only; no stock |
| 12:30 | cake_factory → al_cakes | Mitu, Lipi | Stock: Transfer 3 kg cake B; Lipi receives 3 kg | Stock OUT cake_factory; IN al_cakes |
| 12:45 | main | intake_bot (system) | Online order into 20-6, online orders only | Record; Ruma links to a sale later |
| 13:00 | al_cakes | Lipi | POS sale 1 kg cake B, cash; 14-1 opening float | Stock OUT al_cakes; drawer shown |
| 13:15 | main | Nasrin | Dues collection 600 from yesterday's customer | Balance down; shows in 14-1 |
| 13:45 | godown | Jamal | Transfer 10 kg sweet A → mishti_bari (second one) | Stock OUT godown |
| 14:00 | mishti_bari | Ayesha | Receives first 10 kg transfer, types 10 | Stock IN 10 kg |
| 15:00 | mishti_bari | Ayesha | Receives the 13:45 transfer, types 9 (sent 10) | Stock IN 9 kg; yellow transit_short 1 kg |
| 15:30 | branch2 | Shirin | 14-1 day sheet; 20-3 return register for one return | Record; refund typed with register no. |
| 16:00 | main (hub) | Rahim → Sohel → Fatema | 10-1 Cash handover: Rahim counts 25,000, Sohel carries, Fatema counts 24,800 | Diff 200 red; reason needed |
| 16:20 | main (hub) | Fatema | 10-3 Digital payment register: bKash total vs phone | Match or yellow flag |
| 16:30 | main (hub) | Fatema | 10-4 Cash position vs hub limits; 10-5 receivable and advance check | Records; cross-check with ledger |
| 17:00 | main | Rahim | 10-2 Expense 350 (tea and small repair, receipt); quick expense | Counted once in day book |
| 17:30 | al_cakes | Lipi | 11-1 Shift handover register | Record |
| 18:00 | main | Salma | Approves 14-1 (Rahim), 10-2, 05-1 (Selim) | Status approved; no stock |
| 18:20 | branch2 | Shirin, Salma | Approves 14-1 for branch2 and 20-2 discount slip if any | Approved |
| 18:30 | godown | Hasan (counter), Anwar (witness) | 04-3 Stock count, 5 items. Jamal does not count his own stock | Variance beyond tolerance = yellow exception; witness ≠ counter |
| 18:45 | godown | Jamal | Tries to count own stock (test row) | Form refuses; counter must not be storekeeper |
| 19:00 | head office | Hasan | 06-1 Requisition: flour for next week; 06-2 comparative statement, 2 quotes | No stock or cash |
| 19:20 | main | Selim → Nazia | Recipe change "sweet A" v2 sent to recipe approver | Nazia approves; maker ≠ approver |
| 19:30 | head office | Anwar | 02-1 Attendance register for all staff for the day | Record |
| 20:00 | all | Karim | Exceptions list: transit short, hub diff, count variance. Release or resolve each with a note | Each closed with note |
| 20:20 | main, branch2, al_cakes, mishti_bari, cake_factory, godown | each showroom or factory manager (Rahim, Shirin, Lipi, Ayesha, Mitu, Jamal) | Day close: 14-1 approved, no red flags left | Day closed per place |
| 20:40 | all | Karim | Read-only check: day book vs journal (`daybook_vs_journal`) and duplicate suspects (`dup_suspects`) | Reports only; no change |

**Roster coverage check:** all 17 names appear in this table (Karim, Salma, Rahim, Ayesha, Shirin, Lipi, Nasrin, Tania, Jamal, Selim, Mitu, Hasan, Fatema, Ruma, Anwar, Sohel, Nazia). All active places appear: main, branch2, mishti_bari, al_cakes, cake_factory, godown. `mishti_factory` is paused and does not appear.

**Note on the demo:** items marked `[Unverified]` in section 3 were not confirmed in code. Run the demo in a test project first (see section 6).

---

## 6. Where to verify, and what is still open

**Verify on the phone (after the owner grants access)**
1. Log in as each demo role at its place and check that the screen list matches section 2.
2. Try a transfer from `godown` to `mishti_bari` and a receipt with a short quantity.
3. Try a count where the counter is the storekeeper. The form must refuse.

**Open items (owner decides)**
- Meaning of `IMG-3`, `CF`, `SF` and `GD` (section 1 is my mapping).
- ~~Where the cash hub is~~ — answered by the live DB: hub = `main` (`hub_functions=true`). Owner may still add a separate hub place later.
- Whether `SF` (`mishti_factory`) resumes.
- Whether a separate sales place is needed for the factory-to-showroom step in the demo (10:00 row).
- Who holds each role at each place (no staff accounts are seeded).
- Whether `blind_count_on`, `forms_post_to_ledger` and `stock_*` switches are turned on, and in what order.

**Not built**
- ONLINE_INTAKE form `[Not built]`. Listed in the old manual, no code found.
- Some reports listed as remaining in `docs/REMAINING.md`.

---

## 7. Live-database facts added on 2026-10-16 (read-only audit)

| Fact | Live value |
|---|---|
| Places | 7 rows: `main` (hub), `branch2`, `mishti_bari`, `al_cakes`, `mishti_factory` (**paused**), `cake_factory`, `godown`; all in org unit 3 |
| Roles in DB | 13: owner, management, cash_controller, showroom_manager, salesperson, storekeeper, factory_incharge, purchasing, party_coordinator, carrier, hr, recipe_approver, intake_bot |
| Staff | 1 profile; owner + management on one account. **No other staff account exists.** |
| Stock ledger | **0 rows** — nothing posted yet. Opening stock must be entered before the demo day shows real movement |
| Sales | 10 test sales, 1 customer |
| Switches | `forms_post_to_ledger` OFF, `blind_count_on` OFF, `owner_self_approve` ON, `period_closed_until` empty, `stock_negative_mode` = warn, `em_enabled` ON, `tools_stock_on` OFF |
| Items | 1,369 items, 57 cost rows |

**Consequence for the demo:** run section 5 in order only after (a) the staff in `docs/DEMO_STAFF_ROSTER.md` are created in a *test* project or as test accounts, (b) opening stock is entered for the godown, (c) the owner decides on the three switches above.

---

## 8. Permission assumption

Every role-to-place grant in section 5 is treated as granted to the named fictitious person. No live grant has been made. Before any real use, the owner must create the accounts and grants, and run the pre-day setup in a test project.
