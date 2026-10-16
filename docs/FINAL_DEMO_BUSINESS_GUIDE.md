# Islamia Misty Ghar BOS: Final Demo Business Guide

Status: DEMO ONLY. Read this before any test run.

- All names, mobile numbers, supplier names and money are invented.
- Run it only in a test project. Do not write to the live project.
- Permissions are assumed to be granted for the demo. No real staff account exists yet.
- The owner will translate this file to Bengali later. Software terms stay in English on purpose (screen names, option labels, field names, form codes). Narration is plain English so it can be translated line by line.

Tags used in this file:

- **[verified]**: checked in the code (SQL function, rule switch, or UI label) during this review.
- **[unverified]**: the design says so, but this review did not confirm it in code.
- **[assumption]**: a business expectation the demo tests. The software may or may not do it.
- **[gap]**: the software cannot produce this yet.

Sources read for this guide: `docs/SUPABASE_READONLY_AUDIT.md`, `docs/DEMO_STAFF_ROSTER.md`, `docs/REAL_LIFE_DAILY_WORKFLOW_GUIDE.md`, `docs/REAL_LIFE_STORY_GUIDE.md`, `docs/DEMO_FULL_WORKFLOW_AND_LEDGER.md`, `web/ia.js` (screen registry), and the `web/` screen and form files named below.

---

## 0. Starting state (read once)

| Item | Live project today | Demo starting state |
|---|---|---|
| Real data | Setup tables only (items, options, rules, forms, role grants, audit log) | Demo day 0 entries are made in the test project |
| `stock_ledger` | 0 rows [verified in audit] | Opening balances posted on day 0 (table below) |
| `journal` | Empty [verified in audit] | Stays empty for the demo; see section 7.5 [gap] |
| Accounts | 1 real account (owner + management) [verified in audit] | 17 demo accounts from `DEMO_STAFF_ROSTER.md` in the test project only |
| Switches | `forms_post_to_ledger` OFF, `blind_count_on` OFF, `owner_self_approve` ON, `stock_negative_mode` warn, `period_closed_until` empty [verified in audit] | Same |

Day 0 setup, done by Karim (owner) the night before:

| Step | Screen (route) | Entry |
|---|---|---|
| Owner money in (main drawer float) | Cash & bank moves (`#/cashmoves`), kind "Owner put money in" | Main, cash, 20,000 |
| Opening stock | Stock (`#/stock`), action "Opening balance" | godown: Sugar 60 kg at 105; Flour 50 kg at 60; Mishti A 30 kg at 60 |
| Opening customer due | Dues (`#/dues`) or Customers (`#/customers`) [unverified: which screen takes an opening due] | Customer A, 600 |
| Check switches | Switchboard (`#/switchboard`) | Confirm the five switch values above |

---

## 1. Places and fictitious staff

| Place code | Name in the story | Who runs it (demo) | What happens there |
|---|---|---|---|
| `main` | Main showroom + main sweet factory + cash hub | Rahim (showroom_manager), Nasrin (salesperson), Selim (factory_incharge), Fatema (cash_controller, hub), Ruma (party_coordinator) | Sales, Mishti A production, cash hub count |
| `branch2` | Second showroom | Shirin (showroom_manager), Tania (salesperson) | Sales, returns |
| `mishti_bari` | MISTY BARI | Ayesha (showroom_manager) | Sales, receives godown transfers |
| `al_cakes` | AL-CAKIZ | Lipi (showroom_manager) | Cake B sales |
| `cake_factory` | Cake factory | Mitu (factory_incharge) | Cake B production |
| `godown` | Central store | Jamal (storekeeper) | Receipts, transfers out, counts (counted by Hasan) |
| Head office | Purchasing, HR, recipe approval | Hasan (purchasing), Anwar (hr), Nazia (recipe_approver) | Purchase bills, attendance, recipe approval |
| Owner and management | All places | Karim (owner), Salma (management) | Approvals, exceptions, final decisions |
| Carrier (no place) | Moves cash and slips between places | Sohel (carrier) | No approval rights |
| `mishti_factory` | Not in this demo | Paused, excluded | Opening it is a decision for the owner |

Separation rules to test (from the roster):

- Counter is not the storekeeper: Hasan counts, Jamal does not.
- Witness is not the counter: Anwar watches the count.
- Maker is not the approver: Selim cannot approve his own recipe. Nazia approves.
- Owner self-approve is ON, so Karim may approve his own items. See negative case N10.

---

## 2. Screen and option catalogue

Menu path = group name in the drawer, then screen name. Route = the hash in the address bar, taken from the registry in `web/ia.js` (each record's `route`). The "Who can use it" column uses the registry check: `owner` = owner only; `locOk` = only places the user is given; `pos` = till users; `approver` = people with an approval grant; `P(code, view|enter|approve)` = a form permission grant; `GF.*` = a named grant.

### 2.1 Dashboard

| Screen | Menu path | Route | Who can use it | What it does | Writes |
|---|---|---|---|---|---|
| Home | Dashboard > Home | `#/home` | Everyone | Tiles for the day | Nothing |
| Control Center | Settings > Control Center | `#/control` | `ctlOk` [unverified: exact grant] | One place for attention counts | Nothing |
| Guided routines | Sales & POS > Guided routines (`flow`) | `#/flow` | Not checked | Step-by-step day tasks | Nothing [unverified] |

### 2.2 Items and master data

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| Items | Item & Master Data > Items | `#/items` | `P(ITEMS, view)` | Item list and prices | Item master |
| Add product | Item & Master Data > Add product | `#/items/new` | `P(ITEMS, enter)` | New item (fields: name, code, unit, price, tracked or not) | Item master |
| Lists | Item & Master Data > Lists | `#/lists` | Owner or `list_manage` | Dropdown options and categories | Lists |
| Unit conversions | Item & Master Data > Unit conversions | `#/settings2/units` | Owner | Converts units (for example piece to kg) | Unit table |
| Item types & defaults | Item & Master Data > Item types & defaults | `#/itemtypes` | Owner | Raw material, finished goods, asset, consumable | Item types |
| Bulk item editor | Item & Master Data > Bulk item editor | `#/bulkitems` | `item_bulk` or `item_create` | Change many items at once | Item master |

### 2.3 Inventory and stock

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| Stock | Inventory & Stock > Stock | `#/stock` | `locOk` | Stock list by place. Action menu "Stock actions" holds the options below. | Stock ledger |
| Stock action: Opening balance | Stock > Stock actions | `#/stock` | `locOk` | Sets starting quantity for an item at a place | Stock ledger (Opening) |
| Stock action: Transfer out | Stock > Stock actions | `#/stock` | `locOk` | Sends stock to another place. Shows "In transit" until received. Fields: item, quantity, unit, "Send to", note. | Stock ledger (Transfer out) |
| Receive (in transit) | Stock > In transit > Receive | `#/stock` | Receiving place | Enter quantity received (base unit). Shows "Short" when less than sent. | Stock ledger (Transfer in) |
| Take back | Stock > In transit > Take back | `#/stock` | Sending place | Cancels a transfer that has not been received and returns the stock | Stock ledger (Reversal) |
| Stock action: Issue to production | Stock > Stock actions | `#/stock` | `locOk` | Issues raw material to a production area. Fields: item, quantity, "Send to". | Stock ledger (Issued) |
| Stock action: Production in | Stock > Stock actions | `#/stock` | `locOk` | Adds finished goods made outside the recipe screen. Fields: "Made at" date. | Stock ledger (Production) |
| Stock action: Write off wastage | Stock > Stock actions | `#/stock` | `locOk` | Removes spoiled stock. Reason and note required. Large amounts need approval ("Large wastage write-off — approval"). | Stock ledger (Wastage) |
| Stock action: Adjust to a count | Stock > Stock actions | `#/stock` | `locOk` | Sets stock to the counted quantity. Difference posted as Count. Note required. | Stock ledger (Count) |
| Stock ledger | Inventory & Stock > Stock ledger | `#/stock` (ledger view) | `locOk` | Every movement with a reference. "Reconcile" checks the ledger against the cache. | Nothing (read) |
| Expiring soon | Inventory & Stock > Stock (filter) | `#/stock` | `locOk` | Batches near expiry (only items with a shelf-life rule) | Nothing |
| Stock reports & quality | Inventory & Stock > Stock report & quality | `#/stockx` | `locOk` | Stock value, below-minimum items, quality view | Nothing |
| Asset register | Inventory & Stock > Asset register | `#/assets` | `locOk` | Equipment and machines. Not counted as stock. | Asset register |

Stock movement types (from the ledger screen labels): Opening, Purchase, Purchase return, Sale, Sale voided, Sale return, Issued, Production, Transfer out, Transfer in, Wastage, Count, Reversal.

### 2.4 Purchasing and suppliers

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| Purchase bills | Purchasing & Suppliers > Purchase bills | `#/purchase` | `locOk` | List of bills | Nothing (read) |
| New purchase bill | Purchasing & Suppliers > New purchase bill | `#/purchase/new` | `locOk` | Supplier, bill number, items, quantity, unit cost, payment type. Save, then post. | Stock (Purchase), supplier payable |
| Purchase return | Purchasing & Suppliers > Purchase return | `#/purchase/return` | `locOk` | Returns goods to a supplier | Stock (Purchase return), payable |
| Supplier payables | Purchasing & Suppliers > Supplier payables | `#/payables` | `locOk` | Amount owed to each supplier | Nothing (read) [unverified: payment entry] |
| Suppliers (settings) | Settings > Suppliers | `#/settings2/suppliers` | Owner | Supplier master | Supplier master |

### 2.5 Factory and production

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| Recipes & production | Factory & Production > Recipes & production | `#/recipes` | `locOk` | Pick recipe, batches, planned output, actual output, notes. Yield difference shown. | Stock: raw material out, finished goods in |
| Artisan recipe book | Factory & Production > Artisan recipe book | `#/recipebook` | Not checked | Recipe reference | [unverified] |
| Costing & overhead | Factory & Production > Costing & overhead | `#/costing` | Not checked | Overhead per production | [unverified] |
| Cost sources & allocation | Factory & Production > Cost sources & allocation | `#/costsources` | Not checked | How costs are shared | [unverified] |
| Which showroom a cost belongs to | Factory & Production > Which showroom a cost belongs to | `#/costattrib` | Not checked | Assigns cost to a place | [unverified] |

### 2.6 Sales and POS

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| POS (till) | Sales & POS > POS | `#/pos` | `pos` (till users) | Sell, Quick sale, cart, Pay. Options: Retail / Wholesale, Customer (add or existing), Discount (৳), Mobile / due / split, Print receipt, Share receipt, Change price (goes to exceptions), Void (reason required). | Stock (Sale), cash or mobile, customer due |
| Sale returns | Sales & POS > Sale returns | `#/salereturn` | `pos` | Pick the day's receipt, "Take goods back", return quantity, return reason, how handed back (Cash, Mobile, Card, Wallet: bKash / Nagad / Rocket). Amount can come off the customer's due. | Stock (Sale return), due or cash |
| Online orders | Sales & POS > Online orders | `#/onlineorders` | `pos` | Orders from the intake channel | Order records [unverified: stock reservation] |
| Message inbox | Sales & POS > Message inbox | `#/inbox` | Not checked | Customer and staff messages | Messages [unverified] |

Till rules, verified in code:

- A customer (mobile and name) is required when any amount is left due, and for every wholesale sale [verified: `customer_required`].
- A discount above the place's limit needs approval [verified: `discount_needs_approval`, rule `discount_over_limit`].
- Stock below zero: with `stock_negative_mode` = warn the sale goes through with a warning [verified: rule read; exact warning text unverified].

### 2.7 Customers, orders and invoices

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| Customers & tiers | Customers, Orders & Invoices > Customer list & tier | `#/customers` | Not checked | Customer list and tier | Customer master |
| Customer tiers & benefits | Customers, Orders & Invoices > Customer tier & benefits | `#/tiers` | Not checked | Tier rules | Tier rules |
| Dues | Customers, Orders & Invoices > Dues | `#/dues` | `pos` | Customers who owe. "Collect due" takes cash or mobile. A collection can be reversed by owner or POS approver with a reason [verified: reversal function]. | Customer due, cash or mobile |
| Invoice & print | Customers, Orders & Invoices > Invoice & print | `#/invoice` | Owner | Invoice print | Nothing [unverified] |

### 2.8 Accounting and finance

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| Day book | Accounting & Finance > Day book | `#/daybook` | Owner or `view_daybook` | Money in, money out, opening and closing per day, by Cash, Bank, Mobile. Export CSV. Print or PDF. Day book can be switched on or off by the owner. | Nothing (read) |
| Quick expense | Accounting & Finance > Quick expense | `#/quickexp` | Owner or `10-2` enter grant | One-line cash or mobile expense. Cannot be edited or deleted after saving; void it instead [verified]. | Day book (expense) |
| Cash & bank moves | Accounting & Finance > Cash & bank moves | `#/cashmoves` | Owner or `cash_move` | Kinds: Bank deposit (cash to bank), Bank withdrawal, Owner put money in, Owner took money out, Customer advance received, Customer advance refunded, Advance used against a sale (no money moves), Hub received cash. Fields: place, kind, through (Cash / Bank / Mobile), amount, date, customer mobile, slip or reference, note. Void needs a reason. | Cash, bank or mobile balance; advance |
| Accounts & ledger | Accounting & Finance > Accounts & ledger | `#/accounts` | Not checked | Chart of accounts and ledger | Read [gap: journal empty] |
| Ledger links | Accounting & Finance > Ledger links | `#/ledgerlinks` | Not checked | Links from records to ledger lines | Read [unverified] |
| Employees | Accounting & Finance > Employees | `#/employees` | `employee_view` or `employee_manage` | Staff master | Employee master |
| Deeds & agreements | Accounting & Finance > Deeds & agreements | `#/deeds` | Not checked | Contracts. An active deed cannot be edited; make an amendment [verified]. | Deed records |
| Finance 2 (bank, year end, VAT, assets, budget) | Accounting & Finance > Finance 2 | `#/finance2` | Not checked | Bank, year end, VAT, asset and budget views | [unverified] |

### 2.9 Approvals and exceptions

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| Exceptions | Approvals & Exceptions > Exceptions | `#/exceptions` | Approver | Yellow and red flags (shortages, price changes, discounts, count differences). Each needs a decision and a note. | Flag review |
| Awaiting approval | Approvals & Exceptions > Awaiting approval | `#/pending` | Approver | Forms and items waiting for a decision (approve or reject, reason needed for reject) | Approval decision |
| Item requests | Approvals & Exceptions > Item requests | `#/itemreq` | Approver | Requests for new items | Item master on approve |
| Releases | Approvals & Exceptions > Releases | `#/releases` | Approver | Releases of blocked items [unverified] | [unverified] |
| Emergency | Approvals & Exceptions > Emergency | `#/emergency` | Owner | One-time or short-window approval for a blocked person. Used once or for a short window, then the owner decides whether the role gets the grant for good. | Grant (temporary) [verified] |
| Change requests | Approvals & Exceptions > Change requests | `#/changes` | Approver | Requests to change a closed record | [unverified] |
| Number audit | Approvals & Exceptions > Number audit | `#/numaudit` | Approver | Checks number sequences | Read [unverified] |
| Server re-check | Approvals & Exceptions > Server re-check of totals | `#/eqcheck` | Approver | Re-checks totals on the server | Read |
| Not sent yet | Approvals & Exceptions > Not sent yet | `#/outbox` | Any signed-in user | Offline saves waiting to reach the server | Sends when online [verified label] |
| Notifications | Approvals & Exceptions > Notifications | `#/notifications` | Any signed-in user | Alerts | Nothing |

### 2.10 Reports and analytics

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| Reports | Reports & Analytics > Reports | `#/reports` | Not checked | Report list | Nothing |
| Brand profit & loss | Reports & Analytics > Brand profit & loss | `#/brandpnl` | Not checked | Profit by brand | Nothing |
| Discounts report | Reports & Analytics > Discounts report | `#/discounts` | Not checked | Discounts given | Nothing |
| Ask (assistant) | Reports & Analytics > Ask | `#/assistant` | Not checked | Questions about the data | Nothing [unverified] |
| BI export | Reports & Analytics > BI export | `#/biexport` | Not checked | Data export | Export log |

### 2.11 Staff, roles and permissions

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| Staff | Staff, Roles & Permissions > Staff | `#/staff` | Not checked | Staff list and roles | Staff master |
| Permission matrix | Staff, Roles & Permissions > Matrix | `#/matrix` | Not checked | Who can view, enter or approve each form | Grants |
| Attendance | Staff, Roles & Permissions > Attendance | `#/attendance` | `attendance_manage` or `employee_view` | Attendance register | Attendance |
| Attendance 2 (punch, mark, counted once) | Staff, Roles & Permissions > Attendance 2 | `#/attend2` | Not checked | Punch, mark, one count per person per day | Punch |
| Leave | Staff, Roles & Permissions > Leave | `#/leave` | Not checked | Leave requests | Leave |
| Payroll | Staff, Roles & Permissions > Payroll | `#/payroll` | `payroll_manage` or `salary_view` | Salary sheet | Payroll sheet only; no journal [verified, see section 7.5] |
| Salary report | Staff, Roles & Permissions > Salary report | `#/salary` | Not checked | Salary view | Nothing |
| Employee benefits (report) | Staff, Roles & Permissions > Employee benefits | `#/benefitsx` | Not checked | Benefit view | Nothing |

### 2.12 Locations

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| Locations | Locations > Locations | `#/locations` | Owner [unverified] | Place list | Place master |
| Location settings | Locations > Location settings | `#/locset` | Owner [unverified] | Settings per place | Location settings |
| Location settings sheet | Locations > Location settings sheet | `#/locsheet` | Owner [unverified] | Paper form 0-1 equivalent | Settings version |
| Paper / Parallel / App | Locations > Paper / Parallel / App | `#/rollout` | Owner | Which mode each place is in | Mode setting |

### 2.13 Administration and settings

| Screen | Menu path | Route | Who | What it does | Writes |
|---|---|---|---|---|---|
| Owner mode board | Settings > Owner mode board | `#/owner` | Owner | Owner summary | Nothing |
| Path switches & shadow copies | Settings > Path switches | `#/paths` | Owner | Which path is main and which is off | Path switch |
| Switchboard | Settings > Switchboard | `#/switchboard` | Owner | All on or off switches (see section 4) | Rule values |
| Rules | Settings > Rules | `#/rules` | Owner | Rules and grants | Rule values |
| Rule hub | Settings > Rule hub | `#/rulehub` | Owner | Rule guide | Nothing |
| Settings (all options) | Settings > Settings | `#/settings2` | Owner | Every option | Setting values |
| Delegation board | Settings > Delegation board | `#/delegation` | Owner | Who handles which task | Delegation |
| Printing & books | Settings > Printing & books | `#/printbooks` | Not checked | Print paper forms | Nothing |
| Integrations & export | Settings > Integrations & export | `#/integrations` | Not checked | Connections and export | Export log |
| Logs | Settings > Logs | `#/logs` | Not checked | Audit trail view | Nothing |
| Backup and restore drill | Settings > Backup, Restore drill | `#/backup`, `#/restoredrill` | Owner | Backup and test restore | Nothing to business data |
| Two-factor sign-in | Settings > Two-factor sign-in | `#/twofa` | Any signed-in user | 2FA setup | Account setting |
| Form 20-1/2/4 to sales | Settings > Form 20-1/2/4 to sales | `#/saleforms` | Not checked | Links party and order forms to sales | Form-to-sale links (trail; void instead of delete) [verified] |
| Parallel month | Settings > Parallel month | `#/parallel` | Owner | Compare paper and app for one month, pass or fail | Nothing |

---

## 3. Forms (paper codes) and their software screens

Each row says who fills in the paper form, where, who approves it, and what happens after approval. "Dedicated option" = a screen that does the same job without the paper form. "Form" = the paper form, filled in the form screen. Use one path, not both, or the same sale or receipt is counted twice.

Form codes are taken from `web/forms*.js`. Where the mapping to a screen was not confirmed, the row says so.

| Code | Paper form | Who enters | Where | Who approves | What happens after approval | Dedicated option (screen) | Form |
|---|---|---|---|---|---|---|---|
| 01-1 | Weekly review | Karim | Any | none | Record only | Reports | Form |
| 01-2 | Monthly P&L | Karim | Any | none | Record only | Reports | Form |
| 02-1 | Attendance register | Anwar | Head office | none | Record | Attendance 2 (`#/attend2`) | Form |
| 02-2 | Salary sheet | Anwar | Head office | Karim or Salma | Locks when month starts [unverified] | Payroll (`#/payroll`) | Form |
| 02-3 | Advance register | Anwar | Head office | none | Record. Does not go to the journal [verified gap] | None | Form |
| 02-4, 02-6, 02-7, 02-8 | Appointment, release, duty, skill | Anwar | Head office | none | Record | Employees (`#/employees`) | Form |
| 02-5 | Leave application | Rahim (for staff) | Showroom | Anwar | Record | Leave (`#/leave`) | Form |
| 03-1 | Transfer note | Jamal | godown | Receiving place | Stock moves when received | Stock > Transfer out (`#/stock`) | Both (use one) |
| 04-1 | Goods receipt note (GRN) | Jamal | godown | Salma | If purchase bill is in use, the form adds no stock. If `forms_post_to_ledger` is ON, the form may add stock too: double count risk [verified text] | New purchase bill (`#/purchase/new`) | Both (use one) |
| 04-2 | Issue slip | Jamal | godown | Selim signs | Stock moves when posted | Stock > Issue to production | Both (use one) |
| 04-3 | Count sheet | Hasan (counter) | godown or showroom | Anwar (witness) | Adjust through count | Stock > Adjust to a count | Both (use one) |
| 04-4 | Stock ledger view | Jamal, Fatema, Salma (view) | Any | none | Read only | Stock ledger (`#/stock`) | Form (read) |
| 05-1 | Daily factory sheet | Selim or Mitu | main, cake_factory | Salma | Paper; stock moves come from the recipe run | Recipes & production (`#/recipes`) | Both (use one) |
| 05-2, 05-3, 05-4 | Product spec, recipe card, yield test | Selim | main | Salma | Record. Live recipe is the recipe screen | Recipes & production | Form |
| 05-5 | New product decision | Selim | main | Karim or Salma | Record | Item types (`#/itemtypes`) | Form |
| 06-1 | Purchase request | Hasan | Head office | Salma | Nothing moves | None confirmed [unverified] | Form |
| 06-2 | Quote comparison | Hasan | Head office | none | Nothing moves | None confirmed [unverified] | Form |
| 06-3 | Purchase order | Hasan | Head office | Salma | Nothing moves | None confirmed [unverified] | Form |
| 06-4 | Bill matching and payment request | Hasan | Head office | Salma | Request only; payment goes through supplier payments | Supplier payables (`#/payables`) | Form |
| 06-5 | Supplier ledger | Hasan (view) | Head office | none | Read only | Supplier payables | Form (read) |
| 08-1 | Repair request | Rahim | Showroom | Salma | Record | None confirmed [unverified] | Form |
| 10-1 | Cash handover slip | Rahim (sends), Fatema (receives) | Showroom or hub | Salma or Karim (if difference) | Cash movement created [unverified] | Cash & bank moves > Hub received cash (`#/cashmoves`) | Both (use one) |
| 10-2 | Expense voucher | Rahim or Fatema | Showroom or hub | Salma | Goes to the day book once | Quick expense (`#/quickexp`) | Both (use one) |
| 10-3 | Digital payment register | Fatema | hub | none | Flags any mismatch with the phone totals | Day book (`#/daybook`) | Form |
| 10-4 | Cash position and purchase budget | Fatema | hub | Salma | Record [unverified: budget effect] | Day book | Form |
| 10-5 | Dues and advances check | Fatema | hub | none | Ledger match [unverified] | Dues (`#/dues`) | Form |
| 11-1 | Shift handover | Rahim or Lipi | Showroom | none | Record | None confirmed [unverified] | Form |
| 14-1 | Daily showroom sheet | Showroom manager | each showroom | Salma | No stock; drawer must match | Day book + Exceptions | Form |
| 14-2 | Jilapi counter sheet | Nasrin | main | Rahim | Record | Sales & POS [unverified] | Form |
| 18-1 | Cash form | Fatema | hub | none | Record [unverified] | Cash & bank moves | Form |
| 20-1 | Customer order | Nasrin or Ruma | Showroom or main | none | Record; delivery adds to sales | Online orders (`#/onlineorders`) for online; party order screen not confirmed | Form |
| 20-2 | Discount approval slip | Rahim or Shirin | Showroom | Salma | Shows in POS discount report | Discounts report (`#/discounts`) | Form |
| 20-3 | Returns and complaints register | Shirin or Tania | Showroom | none | Return number goes on sheet 14-1 | Sale returns (`#/salereturn`) | Both (use one) |
| 20-4 | Party and wholesale invoice | Ruma | main | Salma (advice) | Record; cash on 14-1 [unverified] | POS, wholesale | Form |
| 20-5 | Party ledger | Ruma | main | none | Read | Dues (`#/dues`) | Form (read) |
| 20-6 | Online and delivery ledger | Ruma, Sohel, intake channel | main | none | Adds to sales; stock from sale [unverified] | Online orders | Form (read) |

Notes on the forms table:

- The "Both (use one)" rows are the main risk for double counting. The switch `forms_post_to_ledger` controls whether saving a form also posts to the ledger [verified: switch read in form code].
- With `forms_post_to_ledger` OFF (the demo setting), the paper form is a record only and the dedicated option does the posting.
- Forms 04-4 and 06-5 are read-only views of the ledger. Form 05-1 is paper only.

---

## 4. Switches used in the demo

| Switch | Value | Effect | Status |
|---|---|---|---|
| `forms_post_to_ledger` | OFF | Saving a form does not post to the stock or money ledger. Dedicated screens post. | [verified switch; per-form effect unverified] |
| `blind_count_on` | OFF | Counters see the expected quantity. Turn ON only when a count form is enabled, or the switch shows a problem. | [verified: consistency check; what the counter sees is unverified] |
| `owner_self_approve` | ON | The owner can approve items they made. Makers cannot approve others' items for attendance overrides. | [verified in attendance code; other screens unverified] |
| `stock_negative_mode` | warn | Sales below zero stock go through with a warning | [verified: mode read; warning text unverified] |
| `discount_over_limit` | rule on | Discounts above the limit need approval | [verified] |
| `period_closed_until` | empty | When set to a date, entries on or before that date are refused | [verified] |
| `block_expired_sale` | unknown | With `stock_negative_mode` = allow, this blocks expired sales | [unverified: value in demo] |

---

## 5. A full day story: shutter open to shutter close

Time is shown as hh:mm. All places use the same test project. Each step gives: the place, the person, the screen and clicks, and the expected result.

Click paths use the labels read from the code. Exact button positions are [unverified] until someone runs the test.

### 5.0 Night before (Karim, owner, 21:00, Day 0)

| Step | Place | Who | Screen and clicks | Expected result |
|---|---|---|---|---|
| Set switches | all | Karim | Settings > Switchboard. Check the five values in section 0. | Values match section 0 |
| Owner money in | main | Karim | Accounting & Finance > Cash & bank moves. Kind: Owner put money in. Place: main. Through: Cash. Amount 20,000. Save. | Main cash 20,000. Owner capital 20,000 [gap: no journal] |
| Opening stock | godown | Karim | Inventory & Stock > Stock > Stock actions > Opening balance. Sugar 60 kg at 105. Flour 50 kg at 60. Mishti A 30 kg at 60. Save each. | Stock at godown: Sugar 60, Flour 50, Mishti A 30. Stock value 11,100 |
| Opening due | main | Karim | Customers, Orders & Invoices > Customers. Customer A, mobile 01700-000001 (demo), due 600. [unverified screen] | Customer A owes 600 |

### 5.1 07:00 godown: check transit

| Who | Place | Screen and clicks | Expected result |
|---|---|---|---|
| Jamal | godown | Inventory & Stock > Stock > In transit tab | Empty list. Nothing on the road. |

### 5.2 07:30 godown: sugar delivery

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Count the delivery against the bill (04-1 sheet, paper) | Jamal | Paper form 04-1. Count 40 kg. Note: "OK". | Paper only. Nothing posts (switch OFF). |
| Post the bill | Hasan (purchasing) | Purchasing & Suppliers > New purchase bill. Supplier "Supplier S1 (demo sugar trader)". Bill DEMO-B-001. Sugar 40 kg at 110 = 4,400, on credit. Save, then post. | Stock godown Sugar 60 + 40 = 100. Supplier S1 owes 4,400. Ledger line Purchase, 40 kg. |

Stock value after this step: Sugar 100 kg, value 10,700 (average 107.00).

### 5.3 08:30 godown to main: sugar transfer

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Send 20 kg sugar | Jamal | Inventory & Stock > Stock > Stock actions > Transfer out. Item Sugar. Quantity 20. Send to main. Note "for Mishti A run". Paper 03-1 signed by Jamal. | Godown Sugar 80 (in transit 20). Ledger line Transfer out. |
| Receive 20 kg | Selim (main) | Stock > In transit > Receive. Quantity received 20. Save. | Main Sugar 20. Ledger line Transfer in. In transit 0. |

### 5.4 08:45 godown to cake factory: flour transfer

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Send 15 kg flour | Jamal | Stock > Stock actions > Transfer out. Flour 15 kg. Send to cake_factory. | Godown Flour 35 (in transit 15). |
| Receive 15 kg | Mitu (cake_factory) | Stock > In transit > Receive 15. | Cake factory Flour 15. |

### 5.5 09:00 main: Mishti A production (batch 1 and 2)

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Run recipe | Selim | Factory & Production > Recipes & production. Recipe "Mishti A". Batches 2. Planned output 10.0 kg. Actual output 9.6 kg. Yield difference shown: -4%. Note "Dough thicker, 0.4 kg lost in tray". Save. | Sugar at main 20 minus 6 = 14. Mishti A at main +9.6 kg at 66.875 per kg (cost 642.00). Yield flag [unverified threshold: tolerance rule]. |
| Paper sheet | Selim | 05-1 daily factory sheet filled, signed by Selim. Sent to Salma. | Paper. Salma approves later (step 5.17). |

### 5.6 09:40 cake factory: Cake B run

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Run recipe | Mitu | Recipes & production. Recipe "Cake B". Batches 1. Planned output 6.0 kg. Actual 6.0 kg. Note none. | Flour at cake factory 15 minus 9 = 6. Cake B +6 kg at 90 per kg (cost 540). No yield flag. |

### 5.7 10:00 main to branch2: Mishti A transfer

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Send 5 kg | Rahim | Stock > Stock actions > Transfer out. Mishti A 5 kg. Send to branch2. | Main Mishti A 9.6 minus 5 = 4.6 (in transit 5). |
| Receive 5 kg | Shirin (branch2), 10:15 | Stock > In transit > Receive 5. | Branch2 Mishti A +5 at 66.875 (cost 334.38). Main Mishti A stays 4.6 until later sales. |

### 5.8 10:00 godown to mishti_bari: first Mishti A transfer

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Send 10 kg | Jamal | Transfer out. Mishti A 10. Send to mishti_bari. | Godown Mishti A 30 minus 10 = 20 (in transit 10). |

### 5.9 10:30 main: opening sheet and drawer count

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Opening count | Rahim | Paper 14-1 opening section: count drawer 20,000. Compare to system (Day book: opening 20,000). | Match. No flag. |

### 5.10 11:00 main: POS sale, cash and bKash split

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Sell 1.5 kg Mishti A | Nasrin | Sales & POS > POS. Tap Mishti A. Quantity 1.5. Add to cart. Pay: split. Cash 500. bKash 400 with bKash reference (demo). Total 900. Complete sale. Print receipt. | Main Mishti A 4.6 minus 1.5 = 3.1. Cash +500 at main. Mobile (bKash) +400. Receipt printed. |

### 5.11 11:20 branch2: POS sale, cash

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Sell 2 kg Mishti A | Tania | POS. Mishti A 2 kg. Pay: Cash. Total 1,200 (600 per kg). Complete sale. | Branch2 Mishti A 5 minus 2 = 3. Cash at branch2 +1,200. |

### 5.12 11:30 main: POS sale on credit (due)

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Sell 2 kg Mishti A on credit | Nasrin | POS. Mishti A 2 kg. Customer: Add customer. New customer name "Customer B (demo)", mobile 01700-000002. Pay: Due. Total 1,200. Complete sale. | Main Mishti A 3.1 minus 2 = 1.1. Customer B owes 1,200. Without the mobile and name the till refuses (negative case N3). |

Main Mishti A closing check: 9.6 + 0 - 5 (transfer) - 1.5 (cash) - 2 (credit) = 1.1. ✓

### 5.13 12:00 main: party order (Ruma), advance by bKash

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Record order 20-1 | Ruma | Paper 20-1 order: Mishti A 5 kg, delivery next day, advance 1,000. Order screen: [unverified; party order screen not confirmed]. | Order recorded. No stock out yet. |
| Take advance | Ruma | Accounting & Finance > Cash & bank moves. Kind: Customer advance received. Place main. Through: Mobile (bKash). Amount 1,000. Customer mobile 01700-000003 (demo). Save. | Main bKash +1,000. Customer advance owed 1,000. Ledger line for advance [gap: no journal]. |

### 5.14 12:30 cake factory to al_cakes: Cake B transfer

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Send 3 kg Cake B | Mitu | Transfer out. Cake B 3. Send to al_cakes. | Cake factory Cake B 6 minus 3 = 3 (in transit 3). |
| Receive 3 kg | Lipi (al_cakes), 13:00 | In transit > Receive 3. | Al_cakes Cake B +3 at 90 per kg (cost 270). |

### 5.15 12:45 online order (no stock, no cash yet)

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Record online order | Ruma | Sales & POS > Online orders. Order: Mishti A 1 kg, COD. Mobile 01700-000004 (demo). | Order recorded. Stock not reduced [unverified]. Cash nil. |

### 5.16 13:00 al_cakes: POS sale, cash

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Sell 0.3 kg Cake B | Lipi | POS. Cake B 0.3 kg. Pay: Cash. Total 300 (1,000 per kg). Complete. | Al_cakes Cake B 3 minus 0.3 = 2.7. Cash at al_cakes +300. |

### 5.17 13:15 main: old due collected

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Collect 600 | Nasrin | Sales & POS > Dues. Search "Customer A". Collect due. Amount 600. Through: Cash. Save. | Customer A due 0. Main cash +600. |

### 5.18 13:45 godown to mishti_bari: second Mishti A transfer

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Send 10 kg | Jamal | Transfer out. Mishti A 10. Send to mishti_bari. Paper 03-1. | Godown Mishti A 20 minus 10 = 10 (in transit 10). |

### 5.19 14:00 mishti_bari: first receipt, POS sale

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Receive 10 kg | Ayesha | In transit > Receive 10. | Mishti bari Mishti A +10 at 60 per kg (cost 600). |
| Sell 3 kg | Ayesha | POS. Mishti A 3. Pay: Cash. Total 1,800. Complete. | Mishti bari Mishti A 10 minus 3 = 7. Cash at mishti_bari +1,800. |

### 5.20 15:00 mishti_bari: second receipt, short 1 kg

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Receive 9 of 10 kg | Ayesha | In transit > Receive. Quantity received 9. System shows "Short" and "the owner will be told". | Mishti bari Mishti A 7 plus 9 = 16 (cost +540). Short 1 kg stays in transit as an open exception. Owner sees it in Exceptions. |

### 5.21 15:30 branch2: sales return (customer brings back 0.5 kg)

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Find receipt | Shirin | Sales & POS > Sale returns. Pick today's receipt from Tania's 11:20 sale. | Receipt shows Mishti A 2 kg sold. |
| Take goods back | Shirin | Take goods back. Quantity 0.5. Reason "Customer changed mind". How handed back: Cash. Amount 300. Confirm return. | Branch2 Mishti A 3 plus 0.5 = 3.5 (cost back at 66.875 per kg, original batch rule [unverified]). Cash at branch2 minus 300. Net cash at branch2 = 1,200 minus 300 = 900. |

### 5.22 15:45 main: expense, tea and small repair

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Record expense | Rahim | Accounting & Finance > Quick expense. Amount 350. Cash. Note "tea and small repair, receipt attached". Save. | Day book Money out 350 (cash). Expense cannot be edited later; void with reason only [verified]. |
| Paper voucher | Rahim | 10-2 voucher filled, receipt stapled. Sent to Salma for approval. | Paper. Must not be entered again in the software (negative case N11). |

### 5.23 16:00 hub: cash handover (10-1)

Main drawer: float 20,000 + cash sales 500 + old due 600 - expense 350 = 20,750 expected. Float stays 20,000. Surplus 750 goes to the hub.

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Count drawer | Rahim | Day book, cash line for today. Count: 20,750. | Count matches system. |
| Pack and send 750 | Rahim, then Sohel (carrier) | Paper 10-1: amount 750. Signed by Rahim. Sohel takes envelope. | Cash in custody of carrier [gap: no clear custody record]. |
| Receive at hub, count | Fatema | Accounting & Finance > Cash & bank moves. Kind: Hub received cash. Place main. Amount: counted 550. Note "counted at hub". Save. Count does not match 750 expected: system shows difference 200 (red) and asks for a reason [assumption: reason required]. | Hub cash +550. Difference 200 open. Exceptions list: red flag. Rule: a red flag must be solved before the day can close (negative case N4). |

Reason written by Fatema: "carrier short, 200 unexplained, reported to owner". Karim decides at 20:00 (step 5.27).

### 5.24 16:20 hub: digital register check (10-3)

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Check bKash total | Fatema | Paper 10-3. Phone bKash total for main: 400 (sale) + 1,000 (advance) = 1,400. Day book, Mobile line for main: 1,400. | Match. No flag. |

### 5.25 16:30 hub: cash position and dues check

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Cash position (10-4) | Fatema | Paper 10-4. Hub cash 550 counted. Expected cash position: 550 plus any float (0). | Record. The 200 difference is still open. |
| Dues check (10-5) | Fatema | Sales & POS > Dues. Customer A 0. Customer B 1,200. | Ledger matches paper. |

### 5.26 17:00 al_cakes and branch2: shift and day sheet

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Shift handover (11-1) | Lipi | Paper 11-1. Cash held 300. Cake B 2.7 kg. | Record. Cash stays at al_cakes until next carrier run. |
| Showroom sheet (14-1) | Shirin | Paper 14-1: cash 900, Mishti A 3.5 kg, sales 900 net, return 0.5 kg recorded (return number on 20-3). | Matches system. No flag. |

### 5.27 17:30 mishti_bari: day cash and sheet

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Showroom sheet (14-1) | Ayesha | Paper 14-1: cash 1,800. Mishti A 16 kg. Short 1 kg reported. | Matches. The short is already an exception. Cash stays at mishti_bari until next carrier run. |

### 5.28 18:00 management approvals (Salma)

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Approve main 14-1 | Salma | Approvals & Exceptions > Awaiting approval. Pick main sheet 14-1 (Rahim). Approve. | Sheet approved. |
| Approve 10-2 expense (350) | Salma | Awaiting approval. Pick 10-2 voucher. Approve. | Approved. Expense already in day book once (no second posting). |
| Approve Selim 05-1 | Salma | Awaiting approval. Pick 05-1. Approve. | Approved. |

### 5.29 18:20 branch2: sheet approval

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Approve branch2 14-1 | Salma | Awaiting approval. Pick Shirin's sheet 14-1. Approve. | Approved. |

### 5.30 18:30 godown: stock count (04-3)

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Count five lines (counter) | Hasan | Inventory & Stock > Stock > Stock actions > Adjust to a count. Lines: Sugar 79.5 (system 80.0). Flour 35.0 (system 35.0). Mishti A 10.0 (system 10.0). Cake B 0 (system 0). Packing box 0 (system 0, not tracked). | Sugar difference -0.5. Other lines match. |
| Witness | Anwar | Paper 04-3 signed as witness. Not the counter. | Witness signed. |
| Reason and post | Hasan | Note "bag opened and spilled, 0.5 kg" on sugar. Post count. | Sugar stock 79.5. Count line -0.5 kg at 107 = -53.50. Exception: count difference (yellow). Karim closes it at 20:00. |

Jamal does not count. Jamal's role in the count is the storekeeper handing over the paper trail [assumption: enforced separation not verified].

### 5.31 19:00 head office: purchase request and quotes

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Purchase request (06-1) | Hasan | Paper 06-1: flour 35 kg for next week. Sent to Salma. | Paper. Nothing moves. |
| Quote comparison (06-2) | Hasan | Paper 06-2: two quotes for flour. | Paper. Nothing moves. |

### 5.32 19:20 main: recipe change, approval by recipe approver

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| New recipe version | Selim | Factory & Production > Recipes & production. Recipe "Mishti A". New version. Note "less sugar, test 1". Submit. | New version waits for approval [unverified where]. |
| Approve | Nazia | Approvals & Exceptions > Awaiting approval. Pick Mishti A version. Approve. | New version active from approval. Selim cannot approve (negative case N8). |

### 5.33 19:30 head office: attendance

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Attendance | Anwar | Staff, Roles & Permissions > Attendance 2. Mark each staff once. | One record per person per day. Second mark refused [verified: punch cannot be changed, only voided or mapped]. |

### 5.34 20:00 owner: exceptions

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Review exceptions | Karim | Approvals & Exceptions > Exceptions. List: (1) sugar count -0.5 kg; (2) mishti_bari 1 kg transit short; (3) hub cash 200 short; (4) price or discount items (none today). | Each item shows a note field. |
| Decide 1: sugar count | Karim | Accept as shop loss. Note "spillage, witnessed". | Count difference stays booked as loss (53.50). Closed. |
| Decide 2: transit short | Karim | Keep open for carrier check tomorrow. Note "Sohel to check with Ayesha". | Stays open. Stock value includes 60 in transit. Flag stays yellow. [gap: no clear write-off action] |
| Decide 3: hub cash short | Karim | Keep open. Note "Sohel to explain; 200 held as open item". | Stays open. Not in any balance as cash. [gap: no posting for cash difference] |

### 5.35 20:20 each place: day close

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Close day sheet | Rahim, Shirin, Ayesha, Lipi, Mitu, Jamal | Each place closes its day sheet. Button label: [unverified; per-place close not confirmed] | Day sheet closed. No red flags open for that place except the carrier item (hub). |
| Lock period | Karim | Settings > Switchboard or Rules. Set `period_closed_until` = today. [verified rule key] | Entries dated today or earlier are refused (negative case N9). |

### 5.36 20:40 owner: day book read

| Step | Who | Screen and clicks | Expected result |
|---|---|---|---|
| Read day book | Karim | Accounting & Finance > Day book. Period: today. All locations. | Money in and out by Cash, Bank, Mobile. Shows the day totals in section 7.4. Journal cross-check: not possible, journal is empty [gap]. |

---

## 6. Negative cases: what goes wrong and what the software does

Each case: what the business does wrong, who, what the software does, and the tag.

| # | What goes wrong | Who | What the software does | Tag |
|---|---|---|---|---|
| N1 | Storekeeper counts his own stock | Jamal | Expected: separation rule refuses (counter must not be storekeeper) | [assumption] Not verified in this review |
| N2 | Witness is also the counter | Anwar | Expected: refused | [assumption] |
| N3 | Credit sale with no customer mobile or name | Nasrin | Refused: customer required | [verified] `customer_required` |
| N4 | Hub difference 200 with no reason | Fatema | Red flag. Entry needs a reason. Day cannot close until solved | [verified] red flag rule; reason field [assumption] |
| N5 | Transfer sent 5, received 4 | Shirin | Shortage shown ("Short — the owner will be told"). Not written off by itself | [verified] label; colour [unverified] |
| N6 | Sale when stock is zero | Nasrin | Warning, sale goes through (`stock_negative_mode` = warn) | [verified] mode; warning text [unverified] |
| N7 | Discount above limit | Tania | Refused until approval | [verified] `discount_needs_approval` |
| N8 | Maker approves own recipe | Selim | Refused. Nazia must approve | [assumption] Maker-approver rule verified for attendance only |
| N9 | Entry on a closed day | Rahim | Refused when `period_closed_until` is set | [verified] `period_closed`. Note: switch empty during this review |
| N10 | Owner approves own item | Karim | Allowed while `owner_self_approve` is ON. No second person. | [verified] owner exempt |
| N11 | Same expense entered on paper voucher and in quick expense | Rahim | Expected: duplicate warning. No code found for it | [assumption] |
| N12 | Carrier tries to approve a handover | Sohel | Refused (no approval grant) | [assumption] Role grants not checked |
| N13 | Edit a quick expense after saving | Rahim | Refused. Must void with reason | [verified] append-only |
| N14 | Edit or delete a posted record (cash move, form) | Any | Refused; void with reason | [verified] append-only text |
| N15 | Open `mishti_factory` | Selim | Paused place; owner decides | [unverified] |
| N16 | Form 04-1 and purchase bill both add the same sugar | Jamal and Hasan | With `forms_post_to_ledger` ON, stock may be added twice. OFF in demo | [verified] warning text in code |
| N17 | Advance paid to staff, not in ledger | Anwar | Not flagged. Shows in day book only. No journal | [verified] "not connected" |
| N18 | Sale after receiving transfer that was later cancelled | Shirin | Refused: "It is no longer in transit" | [verified] label |
| N19 | Receive more than sent | Ayesha | Refused: "Cannot receive more than was sent" | [verified] label |
| N20 | Large wastage with no approval | Hasan | Routed to approval | [verified] label and `wastage_decide`; threshold [unverified] |
| N21 | Count loss within tolerance | Hasan | Accepted without flag | [unverified] tolerance value |
| N22 | Recipe yield 4% below plan with no note | Selim | Refused or flagged | [assumption] Note field shown; refusal [unverified] |
| N23 | Lost paper sheet (never entered) | Shirin | No flag. Software only knows what is typed | [assumption] |
| N24 | Offline sale on a dead phone, rejected later | Tania | Stays in "Not sent yet" and shows "Could not be recorded (refused)" if rules refuse it | [verified] labels |
| N25 | Online order with COD, delivered, no stock out | Ruma | Stock out tied to sale [unverified] | [unverified] |
| N26 | Cash float changed mid-day with no record | Rahim | No cash kind exists for float change. Only owner money in or out | [gap] |
| N27 | Mobile payment slip typed wrong | Nasrin | Mobile reference is free text. No check against the phone | [assumption] |
| N28 | Hub count typed as 25,000 instead of 24,800 | Fatema | Accepted. The difference is only visible against the expected figure | [assumption] |

Negative cases the software leaves unflagged (most important for the owner):

- N10 self-approval (owner_self_approve ON).
- N11 duplicate expense across paper and screen.
- N17 advance not in the ledger.
- N21 tolerance count loss.
- N23 lost paper sheet.
- N26 float change with no kind.

---

## 7. Ledger and balance sheet for the day

**Demo money.** All taka amounts are invented. They tie out inside this guide, but the software does not yet produce the balance sheet from the ledger (see section 8, G2).

### 7.1 Stock ledger for the day (quantity)

Columns: place, item, opening, in, out, closing, reason for each movement. Quantities in kg (or unit as listed).

| Place | Item | Opening | In | Out | Closing | Reason for each movement |
|---|---|---|---|---|---|---|
| godown | Sugar | 60 | +40 purchase bill DEMO-B-001 (07:30) | -20 transfer to main (08:30); -0.5 count adjustment (18:30) | 79.5 | Purchase; transfer; count loss |
| godown | Flour | 50 | 0 | -15 transfer to cake_factory (08:45) | 35 | Transfer |
| godown | Mishti A | 30 | 0 | -10 transfer to mishti_bari (10:00); -10 transfer to mishti_bari (13:45) | 10 | Transfer |
| godown | Cake B | 0 | 0 | 0 | 0 | None |
| main | Sugar | 0 | +20 transfer in (08:40) | -6 used in Mishti A run (09:00) | 14 | Transfer in; production |
| main | Mishti A | 0 | +9.6 production (09:00) | -5 transfer to branch2 (10:00); -1.5 POS cash (11:00); -2 POS credit (11:30) | 1.1 | Production; transfer; sales |
| branch2 | Mishti A | 0 | +5 transfer in (10:15); +0.5 sale return (15:30) | -2 POS cash (11:20) | 3.5 | Transfer in; return; sale |
| mishti_bari | Mishti A | 0 | +10 transfer in (14:00); +9 transfer in (15:00) | -3 POS cash (14:30) | 16 | Transfer in; sale |
| transit (in transit) | Mishti A | 0 | +20 sent (godown, 10:00 and 13:45) | -19 received (mishti_bari) | 1 | Open short, owner decision pending |
| cake_factory | Flour | 0 | +15 transfer in (08:50) | -9 used in Cake B run (09:40) | 6 | Transfer in; production |
| cake_factory | Cake B | 0 | +6 production (09:40) | -3 transfer to al_cakes (12:30) | 3 | Production; transfer |
| al_cakes | Cake B | 0 | +3 transfer in (13:00) | -0.3 POS cash (13:00) | 2.7 | Transfer in; sale |

Check on Mishti A (all places): opening 30 + production 9.6 - sales 8.5 (main 1.5 and 2, branch2 2, mishti_bari 3) + return 0.5 = 31.6. Closing lines: godown 10, main 1.1, branch2 3.5, mishti_bari 16, in transit 1 = 31.6. Balanced.

### 7.2 Stock value at close (demo ৳, average cost)

| Place | Item | Quantity | Unit cost ৳ | Value ৳ |
|---|---|---|---|---|
| godown | Sugar | 79.5 | 107.00 | 8,506.50 |
| godown | Flour | 35 | 60.00 | 2,100.00 |
| godown | Mishti A | 10 | 60.00 | 600.00 |
| main | Sugar | 14 | 107.00 | 1,498.00 |
| main | Mishti A | 1.1 | 66.875 | 73.56 |
| branch2 | Mishti A | 3.5 | 66.875 | 234.06 |
| mishti_bari | Mishti A | 16 | 60.00 | 960.00 |
| cake_factory | Flour | 6 | 60.00 | 360.00 |
| cake_factory | Cake B | 3 | 90.00 | 270.00 |
| al_cakes | Cake B | 2.7 | 90.00 | 243.00 |
| In transit | Mishti A | 1 | 60.00 | 60.00 |
| **Total** | | | | **14,905.13** |

Rows are rounded to paisa for display. The total is taken from unrounded values (14,905.125), so the visible rows add to 14,905.12.

Cost roll-forward check: opening 11,100 + purchase 4,400 - count loss 53.50 - cost of goods sold 541.375 = 14,905.125. Cost of goods sold = Mishti A 334.375 (main 234.06 + branch2 net 100.31) + Mishti bari 180 + Cake B 27.

Production costs are carried by the consumed inputs (sugar 642 into Mishti A, flour 540 into Cake B). No labour or overhead is added in this demo [gap: no overhead in the demo].

### 7.3 Cash and mobile at close (demo ৳)

| Place | Item | Opening | In | Out | Close | Note |
|---|---|---|---|---|---|---|
| main | Drawer cash | 20,000 | +500 POS, +600 old due | -350 expense; -750 sent to hub | 20,000 | Float kept |
| carrier (Sohel) | Cash in custody | 0 | +750 from main | -550 to hub; -200 unexplained | 0 | Short 200, open |
| hub | Cash | 0 | +550 counted | 0 | 550 | Counted at hub |
| branch2 | Cash | 0 | +1,200 POS | -300 return refund | 900 | Held for carrier run |
| al_cakes | Cash | 0 | +300 POS | 0 | 300 | Held for carrier run |
| mishti_bari | Cash | 0 | +1,800 POS | 0 | 1,800 | Held for carrier run |
| main | bKash (mobile) | 0 | +400 POS, +1,000 advance | 0 | 1,400 | Matches 10-3 phone check |

### 7.4 Day totals (demo ৳)

| Line | Amount | Note |
|---|---|---|
| POS sales (cash and mobile) | 3,900 | main 900 (500 cash + 400 bKash); branch2 1,200; mishti_bari 1,800; al_cakes 300 |
| Credit sales (due) | 1,200 | Customer B |
| Gross sales | 5,400 | |
| Sale returns | -300 | Branch2 refund |
| Net sales | 5,100 | |
| Cost of goods sold | -541.38 | Exact 541.375; shown rounded |
| Count loss (sugar) | -53.50 | Booked |
| Expense (tea and small repair) | -350 | Booked once |
| **Day profit before open items** | **4,155.13** | 5,100 - 541.375 - 53.50 - 350 (unrounded) |
| Open: transit short (Mishti A 1 kg) | 60 | Still inside stock; not expensed |
| Open: hub cash short | 200 | Not in cash; not expensed |
| Collections (old due) | 600 | Not revenue (receivable) |
| Customer advance taken (Ruma) | 1,000 | Liability, not revenue |

### 7.5 Balance sheet at end of day (demo ৳)

| Assets | ৳ | Liabilities and equity | ৳ |
|---|---|---|---|
| Drawer cash (main) | 20,000 | Supplier payable (S1, bill DEMO-B-001) | 4,400 |
| Hub cash | 550 | Customer advance (Ruma) | 1,000 |
| Cash at branch2, al_cakes, mishti_bari | 3,000 | **Total liabilities** | **5,400** |
| bKash (mobile) balance, main | 1,400 | Owner capital at start of day (Day 0 float 20,000, opening stock 11,100, opening due 600) | 31,700 |
| Customer dues (Customer B) | 1,200 | Day profit before open items | 4,155.13 |
| Stock (includes 60 in transit) | 14,905.13 | Open: hub cash short | -200 |
| | | **Total equity** | **35,655.13** |
| **Total assets** | **41,055.13** | **Total liabilities and equity** | **41,055.13** |

Balance check: 41,055.13 = 5,400 + 35,655.13. ✓

Items the software cannot yet produce:

| Line | Code status |
|---|---|
| Owner capital and opening balances | [gap] No journal. Opening entries are in stock and cash lines only. |
| Cash handover (10-1) as a cash movement | [unverified] |
| Hub cash short 200 as an open item | [gap] No posting path for cash differences |
| Transit short 60 | [gap] No clear write-off action |
| Customer advance (1,000) as liability | [gap] Advance is in the day book but has no journal source |
| Supplier payable (4,400) | [unverified] Purchase bill posting to a payable line |
| bKash balance as an account | [gap] Mobile wallets not shown as accounts |
| Cost of goods sold | [unverified] Stock value from average cost (`costing_method` avg, verified in SQL comment) |
| Payroll and salary advance | [gap] No journal (verified in code comment: "advance / salary postings are not connected") |
| Partner capital | [gap] Not in this day |
| Overhead and labour in production | [gap] Not in this demo |

---

## 8. Feedback: gaps and system updates

### 8.1 Gaps found

| # | Gap | Where | Priority |
|---|---|---|---|
| G1 | Payroll and salary advance do not post to the journal | Payroll (`#/payroll`), Advance register (02-3). Verified in code comment. | P1 |
| G2 | Journal and stock ledger are empty in the live project, so no balance sheet can be produced | Audit section 1 | P1 |
| G3 | No opening-balance screen for stock, cash, dues and payables in one place | Stock > Opening balance (per item only); cash via Owner put money in | P1 |
| G4 | Hub cash short has no posting path and no clear owner decision | Cash & bank moves > Hub received cash | P1 |
| G5 | Owner self-approve is ON by default, so the owner can approve own work with no second person | Switchboard (`owner_self_approve`) | P1 |
| G6 | Double-entry risk: form 04-1 and the purchase bill, form 10-2 and quick expense, form 03-1 and transfer. Only one switch controls part of this | Forms table section 3 | P1 |
| G7 | Duplicate expense warning not found in code | Quick expense (`#/quickexp`) | P2 |
| G8 | Transit short has no explicit write-off or claim action | Stock > In transit | P2 |
| G9 | Customer advance has no journal source | Cash & bank moves kind "Customer advance received" | P2 |
| G10 | Mobile wallets (bKash, Nagad, Rocket) are not accounts; balance per wallet not shown | Day book, cash moves | P2 |
| G11 | Recipes do not track milk, chhana or packing as stock; cost is sugar and flour only | Recipes & production | P2 |
| G12 | Recipe yield tolerance value not visible in the screen | Recipes & production | P3 |
| G13 | Count tolerance value not visible; counter may see expected quantity if blind count is OFF | Stock > Adjust to a count; switch `blind_count_on` | P2 |
| G14 | No per-place day close button found | Day sheets (14-1) | P2 |
| G15 | Online order stock reservation and stock-out at delivery not confirmed | Online orders (`#/onlineorders`) | P2 |
| G16 | Party order (20-1) screen not confirmed in the registry | Form 20-1 | P3 |
| G17 | Security advisor: 12 anon-callable SECURITY DEFINER functions, 80 functions with mutable search_path, leaked-password protection OFF | Supabase audit section 2 | P1 before real use |
| G18 | Hub is the same place as main; a separate hub place is not modelled | Places | P3 (owner decision) |
| G19 | Stock or owner decisions on short and difference are not in one place for the owner to close | Exceptions (`#/exceptions`) | P2 |
| G20 | Opening customer due has no confirmed screen | Dues or Customers | P2 |

### 8.2 System update suggestions (priority order)

1. **Journal posting for payroll, advances and partner capital (G1).** Post salary and advance to the journal when the sheet is approved. This is the biggest hole in the books.
2. **One opening-balance page (G3).** One form for the whole group: stock per place, cash per place, customer dues, supplier payables, owner capital. It is the first thing every new place needs.
3. **Cash difference and handover posting (G4, G9).** When a handover is counted with a difference, post the cash move, the difference line and an owner decision. Show the carrier custody as its own line.
4. **Turn off owner self-approve by default (G5).** Keep the switch, but default it to OFF and log each self-approval in the exceptions list.
5. **Single path per job (G6).** Hide one of each pair (purchase bill or form 04-1, expense voucher or quick expense, transfer note or transfer screen) when the other is ON. Warn when both are used for the same item and date.
6. **Duplicate check on expenses and receipts (G7).** Same amount, same place, same day: warn before save.
7. **Transit short close action (G8).** Owner can accept, write off or claim, with a note. The item then leaves the in-transit list.
8. **Track production inputs (G11).** Add milk, chhana and packing as stock items so cost per kg is right.
9. **Show the tolerance values on the screen (G12, G13).** The counter and the owner should see the limit before they type.
10. **Day close per place (G14).** One button on the day sheet that checks open flags for that place and locks the day.
11. **Stock reservation for orders (G15).** Decide when an order holds stock, and when stock leaves.
12. **Security fixes from the audit (G17).** Enable leaked-password protection, review the 12 anon-callable functions, set search_path on the 80 functions. Owner approval needed first (audit section 4).

### 8.3 Before the demo runs

- Run in the test project only.
- Post the Day 0 entries first (section 0), then check the balance sheet can be tied to them.
- Do not turn `forms_post_to_ledger` ON for the demo unless the double-count test (N16) is the point of the test.
- Confirm each [unverified] button label by clicking it once. Update this file after the click test.
- Translate the file to Bengali only after the English file is final.
