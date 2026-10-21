# IA CONCEPT — task-based structure and behaviour for ISLAMIYA MISTY GHAR

Scope: STRUCTURE and BEHAVIOUR only. No colours, fonts, or business-rule changes. Complements web/ia.js (screen registry, 13 categories) and docs/IA_AUDIT.md (route inventory); this file does not repeat that inventory. Routes below are hash routes as used in web/nav.js ROUTES (`#/pos`, `#/form/14-1`...). Form codes come from MODULE_MAP (verify any code marked `?` against the forms table before building).

## 0. Executive summary (10 lines)
1. Thesis: the app should open on "what needs me now", not on a menu. Home = Now strip + 4-6 quick actions + Pinned + Recent, per person.
2. The owner/staff already have the screens (POS, 41 forms, stock, purchase, reports, control). The problem is reaching them in few taps. IA work is routing, not rebuilding.
3. Each role gets 4 bottom-nav slots tuned to its day (owner: Home, Needs-you, Sell/Reports, Me; cashier: Sell, Dues, Day, Me). Drawer keeps all 13 categories, reordered per role. Nothing removed.
4. One global "do" search (command palette) with verbs (sell, count stock, pay supplier, close day) and the existing menu/item/customer search merged.
5. Guided flows (Open shop, Close day, Factory day, Month-end) are checklist screens that only link to existing forms and tick from server state; zero new business logic.
6. Owner Control Center becomes: Needs-you inbox (oldest first) / Exceptions triage / Delegation board / Switchboard (every ON/OFF in one searchable page).
7. Consistency: one glossary (~40 terms), one status vocabulary, fixed record-page and list-page anatomy, fixed primary-vs-three-dot rule, standard error recovery.
8. Productivity ideas ranked; SAFE (structure-only) ones ship first; anything touching money/stock/approval rules is flagged "owner approval".
9. Roadmap: 3 shippable increments (A: Home+Now+nav slots+search verbs; B: guided flows+Needs-you+Switchboard; C: consistency kit+productivity). Each has acceptance tests.
10. Server stays the permission authority: every shortcut, badge and tile is a convenience; hidden/locked UI never grants anything; counts come from existing RPCs (control_counts, stock_levels).

---
## 1. Personas, jobs-to-be-done, ideal taps
Tap count = taps from app open (already logged in) to the first useful input. "Home" = the new task home (section 2). Routes are existing ones.

### 1.1 Owner (phone, often remote)
| # | Job | Screen / route | Ideal taps |
|---|---|---|---|
| 1 | Morning check: sales, cash, dues, problems | `#/home` Now strip + period tabs | 0 |
| 2 | Decide pending items (emergency, release, staff, item change, exceptions) | `#/control` Needs-you -> `#/emergency` `#/releases` `#/staff` `#/itemreq` `#/exceptions` | 1-2 (approve row inline = 2) |
| 3 | Closing review of each showroom (cash short/over, deposit) | `#/exceptions`, `#/daybook`, report hub | 2 |
| 4 | Today across all shops | `#/biz` / dash on Home | 0-1 |
| 5 | Give / take back a permission | `#/rulehub` Who may do what (-> Delegation board) | 2 |
| 6 | Change a rule / limit / ON-OFF | `#/rules` (-> Switchboard) | 2 (search) |
| 7 | Set item price / approve new item | `#/items`, `#/bulkitems`, `#/itemreq` | 2-3 |
| 8 | Supplier dues and pay | `#/payables` | 2 |

### 1.2 Showroom manager
| # | Job | Screen | Taps |
|---|---|---|---|
| 1 | Open shop checklist (cash float, fridge/stock look) | Guided flow "Open shop" -> `#/form/14-1` | 1 |
| 2 | Approve staff entries/discounts/voids | `#/pending`, `#/exceptions` | 1-2 |
| 3 | Cash count and day close (06-1 -> 03-1 -> deposit) | Guided flow "Close day" | 1 + steps |
| 4 | Receive goods / transfer in | `#/form/04-1`, `#/form/03-1` | 2 |
| 5 | Stock count (blind) | `#/form/04-3` or `#/stock` | 2 |
| 6 | Expenses / imprest | `#/form/10-2`, `#/form/18-1` | 2 |
| 7 | Dues collection follow-up | `#/dues` | 1 |
| 8 | Sale return / wastage | `#/salereturn`, `#/stock` (wastage) | 2 |

### 1.3 Cashier / counter staff
| # | Job | Screen | Taps |
|---|---|---|---|
| 1 | Sell | `#/pos` | 1 (bottom nav, or 0 if POS is the staff home) |
| 2 | Scan item | `#/pos` scan (barcode.js) | 1 inside POS |
| 3 | Collect baki | `#/dues` -> customer -> Collect | 3 |
| 4 | Sale return | `#/salereturn` | 2 |
| 5 | Ask for a blocked action (emergency request) | inline from the block message | 1 |
| 6 | Count drawer at shift end | `#/form/14-1` | 2 |
| 7 | Send offline sales | `#/outbox` (badge shows only if non-empty) | 1 |
| 8 | Look up price | search verb "price" -> `#/items` | 2 |

### 1.4 Store keeper / godown
| # | Job | Screen | Taps |
|---|---|---|---|
| 1 | Goods received (GRN) | `#/form/04-1` or `#/purchase/new` | 2 |
| 2 | Issue material to factory/shop | `#/form/04-2` | 2 |
| 3 | Transfer out (challan) | `#/form/03-1` | 2 |
| 4 | Stock count | `#/form/04-3` | 2 |
| 5 | Low stock / expiring look | `#/stock` (low, expiry chips) | 1 |
| 6 | Wastage entry | `#/stock` -> wastage | 3 |
| 7 | Receive transfer (confirm) | Now strip row "transfer in transit" | 2 |
| 8 | Purchase bill entry / return | `#/purchase/new`, `#/purchase/return` | 2 |

### 1.5 Factory head / operator
| # | Job | Screen | Taps |
|---|---|---|---|
| 1 | Daily factory sheet (fridge, scale) | `#/form/05-1` via Factory-day flow | 1 |
| 2 | Production run (consume raw, make goods) | `#/recipes` | 2 |
| 3 | Request material | `#/form/06-1` | 2 |
| 4 | Receive issued material | `#/form/04-1` / `#/stock` | 2 |
| 5 | Yield test / recipe card | `#/form/05-4?`, `#/form/05-3?` | 2 |
| 6 | Dispatch to showrooms (transfer) | `#/form/03-1` | 2 |
| 7 | Maintenance request (machine) | `#/form/08-1` | 2 |
| 8 | Shift handover | `#/form/11-1` | 2 |

### 1.6 Accountant
| # | Job | Screen | Taps |
|---|---|---|---|
| 1 | Day book | `#/daybook` | 1 |
| 2 | Supplier payables, pay | `#/payables` | 2 |
| 3 | Purchase bills check (3-way match) | `#/purchase` | 2 |
| 4 | Digital reconcile (bKash/card) | `#/form/10-3` | 2 |
| 5 | Salary sheet (if granted) | `#/salary` | 1-2 |
| 6 | Expense review | report hub -> expense by head | 3 |
| 7 | P&L / reports / CSV | `#/reports`, `#/biz` | 2-3 |
| 8 | Month-end checks (books-closed date) | Month-end flow | 1 |

### 1.7 Hub person
| # | Job | Screen | Taps |
|---|---|---|---|
| 1 | Receive showroom cash (hub count) | `#/form/10-1` hub side | 2 |
| 2 | Cash position vs purchase budget | `#/daybook` / cash report | 1-2 |
| 3 | Supplier payment | `#/payables` | 2 |
| 4 | Purchase order / quotation | `#/form/06-2?` `27-1?` | 2 |
| 5 | Transfers overview (in transit) | `#/stock` | 1 |
| 6 | Collect from wholesale dues | `#/dues` | 2 |
| 7 | Staff attendance entry | `#/form/02-1` | 2 |
| 8 | Reports to owner | `#/reports` | 2 |

Honest note: persona = role + grants, not a fixed role. The server gives `S.ctx.roles`, `perms`, grants (`GF`). The persona home is chosen by a rule table (section 2.6), and the owner can override per person.

---
## 2. Task-based Home (one layout, content decided by role + grants)
Home page job (one sentence): "Show me what needs me now and let me start my most common job in one tap."

### 2.1 Anatomy (top to bottom, same order for everyone)
1. **Now / Today strip** (max 5 rows + "see all"): rows that need an action by THIS person. Row = edge marker + one line + count/age + chevron. Oldest first.
2. **My quick actions**: 4-6 large buttons from a per-role default list (editable by the person, owner can set role defaults).
3. **Pinned**: star-pinned screens (existing favourites, `nav_pin`).
4. **Recent**: last 5 distinct screens/records opened (local, per user, try/catch storage).
5. **Numbers** (owner/manager only): the existing Business/Accounting numbers, collapsed below the strip. Numbers never push the Now strip down.

### 2.2 Now-strip content by role (all from existing data; no new rules)
| Source row | Owner | Manager | Cashier | Store | Factory | Accountant | Hub |
|---|---|---|---|---|---|---|---|
| Emergency / release requests (`control_counts`) | yes | no | no | no | no | no | no |
| Staff approval, item change requests | yes | no | no | no | no | no | no |
| Entries awaiting MY approval (`#/pending`) | yes | own shop | no | no | factory sheets | bills | yes |
| Red/yellow exceptions (`#/exceptions`) | yes | own shop | no | no | no | no | yes |
| Drafts of mine / sheets to fill today (06-1, 12-1, 04-3...) | no | yes | yes (06-1) | yes | yes (12-1) | no | no |
| Rejected - needs my fix | no | yes | yes | yes | yes | yes | yes |
| Not-sent offline queue (`#/outbox`) | yes | yes | yes | yes | yes | no | no |
| Transfers in transit to my place | no | yes | no | yes | yes | no | yes |
| Low stock (min_stock flag via `stock_levels`) | digest | yes | no | yes | yes | no | no |
| Expiring batches (shelf-life) | digest | yes | no | yes | yes | no | no |
| Dues overdue (age bands 8/30 from settings) | digest | yes | yes (collect) | no | no | yes | yes |
| Supplier payables due | digest | no | no | no | no | yes | yes |
| Books-closed / month-end reminder | yes | no | no | no | no | yes | no |
"digest" = one line with a count ("12 low-stock items") instead of rows, for the owner, to keep the strip about decisions.

### 2.3 Badge rules
- A badge/dot appears ONLY if the current user can act on the item now (grant check client side for display; server enforces on action).
- Count = actionable items, not "total in table". Informational numbers (sales total) are never badges.
- Ordering inside any queue: oldest first; items older than the SLA setting get a warn marker (SLA is a settings value; empty = no marker, "Data needed").
- Dot, not number, on drawer groups and bottom-nav slots (calm). Number only on the Now-strip row and inside the screen.
- A badge clears when the underlying row is decided, never by "mark all read".
- No badge for things the user already viewed but not decided: keep it until decided (honest), but do not re-push it.
- Max one badge per bottom-nav slot.

### 2.4 Empty-state wording (Bng-Eng, calm, tells the next step)
- Now strip empty: "সব ঠিক আছে — এখন কিছু করার নেই" / "All clear. Nothing needs you now."
- Cashier no dues: "আজ কোনো বাকি নেই".
- Pinned empty: "প্রিয় স্ক্রিনে ⭐ চাপুন, এখানে দেখাবে".
- Recent empty: "এখনও কিছু খোলা হয়নি".
- Locked module (when rule `ui_noperm_mode` = lock): "অনুমতি নেই — মালিকের কাছে চান" with a single "অনুরোধ করুন" action (existing emergency-request path). Hide mode: nothing shown.
- Never use "Error" as an empty state; never blank.

### 2.5 Quick actions defaults (editable; owner sets role default, person overrides)
- Owner: Needs-you, Sales today, Dues, Items/prices, Reports, Control Center.
- Manager: Sell (POS), Cash count 06-1, Receive goods 13-1, Stock count 36-1, Expense 11-1, Close day.
- Cashier: Sell, Collect baki, Sale return, Cash count 06-1, Not-sent (if any).
- Store: Receive goods, Issue 18-1, Transfer 39-1, Stock count, Wastage, Low stock.
- Factory: Daily sheet 12-1, Production, Request material 28-1, Transfer 39-1, Handover 11-1.
- Accountant: Day book, Payables, Purchase bills, Digital reconcile 07-1, Reports, Salary (if granted).
- Hub: Hub cash 03-1, Payables, Day book, Transfers, Dues.
A button shows only if `ok()` for that route (same function nav.js uses). If fewer than 4 qualify, fill from Recent.

### 2.6 Choosing the home variant
Rule table (first match): owner -> Owner home; role management -> Manager; has `POS.enter` and no approve -> Cashier; grant/area store -> Store; area factory -> Factory; salary_view/view_daybook -> Accountant; location kind hub -> Hub. Fallback: Cashier-like "My forms" list. The owner can pin a person to a variant (setting on staff record). Multi-role: merge Now rows, keep one quick-action list (union capped at 6).

---
## 3. Navigation model

### 3.1 Bottom nav: always 4 slots, ordered by thumb frequency (the current Home / Menu / POS / Me remains the fallback)
| Persona | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Owner | Home | Needs-you (Control Center inbox, dot) | Reports | Me |
| Manager | Home | Sell | Day (guided flows) | Menu |
| Cashier | Sell | Dues | Day (06-1 / close) | Me |
| Store | Home | Stock | Receive/Issue (hub of 04-x, 39-1) | Menu |
| Factory | Home | Today's sheets | Production | Menu |
| Accountant | Home | Day book | Payables | Menu |
| Hub | Home | Cash | Payables | Menu |
Rules: the drawer button is always reachable in the header, so "Menu" need not take a slot for roles that have a task slot. Slot choices are a setting (owner role default, person override). Bottom nav stays hidden on `#/pos` and entry forms (as now). A slot the user may not open is replaced, not greyed.

### 3.2 Drawer: all 13 categories, order by persona
Categories (names to match ia.js; use its exact ids when it lands): Dashboard & Overview, Items & Master Data, Inventory & Stock, Purchasing & Suppliers, Factory & Production, Sales & POS, Customers & Dues, Accounting & Finance, Approvals & Exceptions, Reports & Analytics, People & Permissions, Locations, Administration & Settings.
| Persona | Order (top -> bottom; rest follow default order) |
|---|---|
| Owner | Approvals, Dashboard, Reports, Sales, Accounting, Items, Customers, Purchasing, Inventory, Factory, People, Locations, Admin |
| Manager | Sales, Approvals, Inventory, Customers, Accounting, Purchasing, Reports... |
| Cashier | Sales, Customers, Accounting (cash only), Dashboard |
| Store | Inventory, Purchasing, Factory, Items |
| Factory | Factory, Inventory, Purchasing (requests) |
| Accountant | Accounting, Purchasing & Suppliers, Reports, Customers |
| Hub | Accounting, Purchasing, Inventory, Customers, Reports |
Behaviour: groups are collapsible and remember state per user; a group with an actionable item shows a dot; pinned and recent are NOT repeated in the drawer (they live on Home) except a short "Pinned" group at top of the drawer for desktop. Every existing route stays in exactly one primary group (aliases allowed as "also under" in search only).

### 3.3 Global command search ("do-search")
One field, in the header (replaces separate drawer-search entry point; drawer still has it). Results in 4 ordered sections: **Do** (verbs/actions), **Go** (screens/forms), **Find** (items, customers, suppliers, entries by number), **Settings** (switches). Typing 2+ chars; offline: Do/Go/Settings still work, Find shows "অফলাইন — আইটেম লিস্ট ক্যাশ থেকে".
Verb table (bn / mix / en synonyms all match; Bangla typed in Latin phonetics is NOT promised):
| Verb | Matches | Goes to |
|---|---|---|
| sell / বিক্রি | sell, sale, বিক্রি, pos | `#/pos` |
| collect / বাকি আদায় | baki, due, collect | `#/dues` |
| count cash / ক্যাশ গণনা | cash count, 06-1 | `#/form/14-1` |
| count stock / স্টক গণনা | stock count, 36-1 | `#/form/04-3` |
| new item / নতুন আইটেম | new item, add product | `#/items/new` (or itemreq if no create grant) |
| receive goods / মাল গ্রহণ | grn, receive | `#/form/04-1` |
| new purchase bill | bill, purchase | `#/purchase/new` |
| pay supplier / সাপ্লায়ার পেমেন্ট | pay supplier, payables | `#/payables` |
| expense / খরচ | expense | `#/form/10-2` |
| transfer | challan | `#/form/03-1` |
| wastage | waste, নষ্ট | `#/stock` wastage action |
| return | sale return | `#/salereturn` |
| close day / দিন শেষ | close | Guided flow Close day |
| open shop / দোকান খোলা | open | Guided flow Open shop |
| approve / অনুমোদন | pending, approve | `#/pending` or Needs-you |
| report <name> | any of the 19+ reports | report viewer |
| price <item> | item name | item detail |
| <number> | entry/paper number, mobile 01XXXXXXXXX | entry / customer |
Rules: a result is shown only if `ok()`; if locked-mode is on, the result shows with lock and request action. The last 3 chosen results are suggested when the field is empty (recent). Registry-driven: each ia.js screen gets optional `verbs: []` and `aliases: []` fields (a data addition, no new screens). Search never executes a write; it only navigates.
Trade-off: a palette is a learned habit. Keep the drawer search identical in behaviour so nobody must learn a second one.

### 3.4 Breadcrumbs and back
- Title bar shows the category > screen on wide, only screen title on phone with a small category label under it.
- Hardware/gesture Back: closes sheet/drawer first, then returns to the previous screen in this session (the hash stack), never to a different category's home unexpectedly.
- Back from a form with unsaved input: confirm "ড্রাফটে রাখব?" (Save draft / Discard / Stay). Never silent loss.
- After submitting a form or flow step: return to where the user came from (guided flow, list, or Home), with a one-line confirmation "জমা হয়েছে — #123" and an Undo/Open link where the app already allows it.
- Up arrow in header goes to the parent list of a record page (record -> its list), not Home.

### 3.5 Deep-link rules
- Every screen and every record has a stable hash route: `#/<screen>` or `#/<screen>/<id>`; forms `#/form/<code>` (+ `?id=`).
- A deep link opens only after login; permission is checked on arrival; denied -> "অনুমতি নেই" page with request action, not a blank.
- Needs-you rows and notifications use the same routes (so a shared link and a tap behave identically).
- Parameters for flows: `#/flow/close-day?loc=<code>&date=<d>`; unknown params ignored.
- Never put money values or tokens in the URL. Location is a parameter only as a code.
- Wrong-shop link: if the user lacks `can_loc` for it, say so; do not silently switch location.

---
## 4. Guided flows (lightweight steppers; link only)
Page-job: "walk me through a recurring routine in order, and show what is already done." Implemented as one generic screen `#/flow/<id>` driven by a data list (id, steps[], each step: label, route, `done()` check, optional `skip` with reason). Steps never post data themselves; they open the existing form and, on return, re-read server state to tick. A step the user cannot do is shown as "needs <role>" (assignable, not skipped silently).
Common behaviours: progress "3 of 7"; each step tap-to-open; status per step (todo / done / skipped with reason / blocked); resume from Home (the flow is a Now row "Close day: 2 of 5 left"); flows are editable lists in settings (owner can reorder, add a step linking any route, switch a step ON/OFF); a flow cannot be "completed" by tapping, only by the underlying checks or an explicit skip with a note (audit-logged).

### 4.1 Open shop (manager / cashier)
1. Opening cash float count: `#/form/14-1` (blind count mode if on) - done when today's 06-1 exists for this shop.
2. Staff present: `#/form/02-1` attendance (if shop uses it).
3. Stock/fridge quick look: `#/stock` low + expiry chips (view only, auto-done on view).
4. Check yesterday's problems: `#/exceptions` (own shop) - done when none open.
5. Open POS: `#/pos`.

### 4.2 Close day (06-1 -> 03-1 -> deposit)
1. Count the drawer: `#/form/14-1` (blind; short/over vs `cash_tol`).
2. If red control: ask owner/manager (release request) - blocked until decided.
3. Hand over cash: `#/form/10-1` (hub count).
4. Digital reconcile: `#/form/10-3` (bKash/card vs sales).
5. Bank deposit: record per existing screen (day book "bank deposit" is a known gap in REMAINING P3-9; until then this step is "paper / mark done with note").
6. Expenses and imprest for the day: `#/form/10-2`, `#/form/18-1`.
7. Not-sent offline sales: `#/outbox` must be empty.
8. Done: summary line (sales, cash, short/over, dues) linking to `#/daybook`.

### 4.3 Factory day
1. Daily sheet (fridge limits, scale): `#/form/05-1`.
2. Material received/issued today: `#/form/04-1`, `#/form/04-2`.
3. Production runs: `#/recipes`.
4. Yield test (if scheduled): form 05-x.
5. Wastage: `#/stock`.
6. Dispatch to shops: `#/form/03-1`.
7. Shift handover: `#/form/11-1`.

### 4.4 Month-end (accountant / owner)
1. Every shop's days closed (list of days missing 14-1/10-1).
2. Open exceptions and pending approvals = 0 or acknowledged.
3. Stock count done per location: `#/form/04-3`.
4. Supplier payables check: `#/payables`; purchase bills matched `#/purchase`.
5. Salary sheet: `#/salary`, 02-2/02-3.
6. P&L and reports: `#/biz`, report hub; export CSV.
7. Set "books closed until": rule `period_closed_until` (owner only) - this one is a deliberate separate, owner-confirmed step.
Risk note: steps 1-2 show server-derived status; if a query is missing, show "unknown, check manually" instead of a green tick (never fake done).

---
## 5. Owner Control Center concept (extends `#/control`, same screen, same route)
Page-job: "everything that needs a decision, everything that is set, and who holds power - in one place".
Tabs/sections: **Needs you | Exceptions | Delegation | Switchboard** (top segmented; Control tiles of today stay under "More").

### 5.1 Needs-you inbox
- One merged list across NEEDS (exceptions, releases, emergency, item requests, staff pending, wastage, location setup, settings drafts, change requests). Current screen shows counts only (REMAINING P4-14); the target shows rows.
- Row: edge marker (tone), type icon, 1-line summary ("Staff A - discount 12% - Place 1"), who/where, age, amount if any, chevron.
- Sort: oldest first, overdue (SLA) first. Filters: type chips, location, person. Group toggle: by type / by place.
- Inline: Approve / Reject (primary + a ⋮ with "Ask question", "Defer", "Open full record"). Reject requires a note; approve of money-affecting items opens the record for one glance (no blind bulk-approve of money items).
- Bulk: only for low-risk types (e.g. staff pending, list "Other" queue). Money/stock types: single decisions only.
- Delegation shortcut on each row: "Next time let <role> decide" -> opens the grant page prefilled (does not grant by itself).
- Empty: "কিছু বাকি নেই".

### 5.2 Exceptions triage
Today `#/exceptions` is a list. Target: three buckets - **Red (blocked/needs decision)**, **Yellow (watch)**, **Seen/closed** - each row showing the rule that fired, amount, place, person, and one-tap actions: Accept (with reason), Ask person, Escalate, Create rule suggestion (opens Rules with the limit; never auto-changes). Repeat-offender chip: "3rd time this week" (from existing log counts). Sort oldest first.

### 5.3 Delegation board
Matrix/grouped list: for each grant (from "Who may do what": e.g. `discount_over_limit`, `see_expected`, `item_create`, `rollout_manage`, `change_approve`, `list_manage`, `location_manage`, `settings_approve`, `head_management`, `view_cost`, `salary_view`, `view_daybook`, `release_decide`...) show holders (people/roles), scope (all or location), since when, and status (active/paused). View by grant or by person. Actions on a holder row: Pause (switch OFF without deleting), Resume, Remove, Set expiry (if grants support expiry; else "needs new column - owner approval"). "Recently changed" strip from audit_log. Known gap to show honestly: "release_decide delegates have no page" (REMAINING 14) - the board is where that page link belongs.
Rule: the board changes the same server tables the grants screen does; no parallel store.

### 5.4 Switchboard (all ON/OFF in one searchable page)
- Source: existing Rules (`rule('key')` ~43 keys), Form rules, rollout (Paper/Parallel/App), tools_stock_on, blind_count_on, pin_signature_on, forms_post_to_ledger, packaging_consume_on, owner_self_approve, ui_noperm_mode, ui_calm, vat_on... Also per-form switches. A registry (`key, module, label bn/mix/en, type (switch/number/choice), default, scope, help, risk`) built from the rule definitions already in the DB (`defs`) plus a static list for the ones outside (settings2).
- Layout: search field on top; chips = modules (the 13 categories); "Recently changed" (last 10 with who/when); "Different from default" filter (shows what the owner has altered); each row: label, current value, default hint, ⋮ (Reset to default, History, Who may change, Copy link).
- Safe defaults: every key has a default declared in the registry; "Reset" restores it; "Reset module to safe defaults" requires a confirm sheet listing what will change (diff) and a note; never one-tap global reset.
- Risk tag per switch: normal / money / stock / security. Money/security changes show a one-line effect statement before saving ("Discount without manager will be allowed"). Number inputs refuse non-finite values (existing guard); empty number = "Data needed" (project rule).
- No new rules: this page only edits keys that already exist. Changes are audit-logged by the existing mechanism.
- Trade-off: one big page can overwhelm; hence module chips, search, and the "different from default" lens as the default landing filter for the owner.

---
## 6. Consistency system

### 6.1 Glossary (label bn / mix (Bangla with simple English) / en). One term = one meaning everywhere.
| Concept | bn | mix | en |
|---|---|---|---|
| Home | হোম | হোম | Home |
| Menu | মেনু | Menu | Menu |
| Sell | বিক্রি | বিক্রি | Sell |
| Sale (record) | বিক্রয় | Sale | Sale |
| Due / baki | বাকি | বাকি | Due |
| Collect (due) | আদায় | Collect | Collect |
| Customer | কাস্টমার | Customer | Customer |
| Supplier | সরবরাহকারী | Supplier | Supplier |
| Purchase bill | ক্রয় বিল | Purchase Bill | Purchase bill |
| Pay supplier | সরবরাহকারীকে পরিশোধ | Supplier-কে Pay | Pay supplier |
| Item | আইটেম | Item | Item |
| Item code | আইটেম কোড | Item code | Item code |
| Price | দাম | Price | Price |
| Stock | স্টক | Stock | Stock |
| Count (stock) | গণনা | Count | Count |
| Cash count | ক্যাশ গণনা | Cash count | Cash count |
| Short / over | কম / বেশি | Short / Over | Short / Over |
| Transfer | স্থানান্তর | Transfer | Transfer |
| Goods received | মাল গ্রহণ | GRN / মাল গ্রহণ | Goods received |
| Issue (material) | সরবরাহ দেওয়া | Issue | Issue |
| Wastage | নষ্ট / অপচয় | Wastage | Wastage |
| Expense | খরচ | খরচ | Expense |
| Imprest | ইমপ্রেস্ট | Imprest | Imprest |
| Handover | হস্তান্তর | Handover | Handover |
| Day close | দিন শেষ | Day close | Close day |
| Draft | খসড়া | Draft | Draft |
| Pending | অপেক্ষায় | Pending | Pending approval |
| Approved | অনুমোদিত | Approved | Approved |
| Rejected | বাতিল | Rejected | Rejected |
| Locked | লক | Locked | Locked |
| Approval | অনুমোদন | Approval | Approval |
| Exception | ব্যতিক্রম | Exception | Exception |
| Release request | ছাড়ের অনুরোধ | Release request | Release request |
| Emergency request | জরুরি অনুরোধ | Emergency request | Emergency request |
| Grant (permission) | অনুমতি | Permission | Permission |
| Location | লোকেশন | Location | Location |
| Showroom | শোরুম | Showroom | Showroom |
| Factory | কারখানা | Factory | Factory |
| Godown | গোডাউন | Godown | Godown |
| Paper number | কাগজের নম্বর | Paper no. | Paper no. |
| Entered later | পরে এন্ট্রি | Entered later | Entered later |
| Rule / switch | নিয়ম | Rule | Rule |
Rules: brand "ISLAMIYA MISTY GHAR / ইসলামিয়া মিষ্টি ঘর" never translated or abbreviated. "Pending" in UI always means "waiting for someone's decision". "Approve" never used for "save". Same word for the same thing in nav label, page title, button and Now-strip. The glossary lives in i18n.js keys; new strings must reuse a glossary key first. Do not change existing wording in bulk (risk: owner has learned it); only fix real conflicts.

### 6.2 Status vocabulary (chip = word + marker; colour is decided later by the theme)
| Status | Meaning | Who moves it | Editable? |
|---|---|---|---|
| Draft | saved, not submitted | maker | yes |
| Pending | submitted, waiting for approver | system | no (maker may withdraw if rule allows) |
| Approved | accepted | approver | via change request |
| Rejected | sent back with reason | approver | maker fixes and resubmits (new revision) |
| Locked | period closed or form locked | owner/rule | via change request only |
| Paper | exists on paper, no app record | rollout mode | n/a |
| Entered later | app record of a paper original, with paper serial and original time | maker | as Pending |
| Void/Cancelled | reversed with a reason, kept visible | granted person | no |
| Inactive/Hidden | item/location switched off, never deleted | owner/granted | yes |
Rules: statuses are mutually exclusive on one record except "Entered later" which is a flag next to the main status. Chip text is always shown (never colour alone).

### 6.3 Action hierarchy
- One primary action per screen, in a sticky bottom bar (Save/Submit/Pay/Collect/Approve).
- Secondary visible: at most 2 (e.g. Save draft, Print).
- Everything else in ⋮: edit details, history, duplicate, print, share, void/cancel, lock/unlock, inactivate, copy link, "ask owner".
- Rules for ⋮: never hide the main workflow; destructive ones go last, need a confirm sheet and a reason; items the user lacks the grant for are shown disabled with the reason ("অনুমতি নেই"), not hidden, unless `ui_noperm_mode` = hide.
- Row ⋮ and record-page ⋮ contain the same verbs in the same order (consistency).
- Swipe is not required for anything (accessibility, low-end phones).

### 6.4 Record page anatomy
1. Header: back (to list), title (type + number), ⋮.
2. Status chip + flags (Entered later, Paper no., Locked).
3. Key facts block (3-6 label/value pairs: place, date, person, amount, key result). Money right-aligned tabular.
4. Body: the form fields or detail, grouped with section headings; read-only if status not Draft/Rejected.
5. Photos/attachments.
6. Timeline/History: created, submitted, approved/rejected (who, when, note), revisions, change requests (from audit_log), most recent first, collapsed beyond 3.
7. Sticky action bar (primary + max 2 secondary).

### 6.5 List page anatomy
Header (title, count) -> search (name/number/barcode) -> filter chips (applied, removable, "Filters" opens a sheet) -> sort control -> optional bulk-select mode (via ⋮ "Select", never always on) -> rows (edge marker, title, 2 facts, status chip, ⋮) -> pager ("50 per page + আরও") -> sticky primary "New" if the user may create.
States: **Loading** skeleton rows (no spinner-only); **Empty (no data)** one line + the create action; **Empty (filtered)** "কোনো ফল নেই — ফিল্টার সাফ করুন" + clear button; **Error** message + Retry; **Offline** info bar "অফলাইন, পুরনো তথ্য (সময়)" and write actions queued or disabled with the reason; **No permission** per 2.4.

### 6.6 Error-recovery patterns
- Validation: inline under the field, in the field's own language, focus moves to the first error; the typed data is kept.
- Server refusal (rule/limit/grant): plain reason + the allowed next step (Ask for emergency, Ask approver, Fix amount). Never a raw SQL/RPC message; raw detail under "Details".
- Network failure on submit: keep the form, save to the outbox (existing offline queue where the form supports it), show "Not sent yet - will retry" and the Not-sent count; never double-post (idempotent client ids already exist).
- Session/PIN expired: re-auth sheet over the page, return to the same form with data intact.
- Duplicate guard: if the same entry exists (same number/customer/amount in X minutes), show "Looks like #123 - open it?" before saving.
- Undo only where the app already reverses (void, collection reversal, item merge); otherwise use "change request" wording honestly; no fake undo.
- Every failed action offers: Retry, Save draft, Contact/Ask owner (prefilled message with the screen and time).

---
## 7. Productivity ideas, ranked
Columns: Value (H/M/L), Effort (S/M/L), Risk, Class. SAFE = structure/UI only, reversible, no business rule change. OWNER = needs owner approval because it touches business rules, money, stock, approvals or data model.
| # | Idea | Value | Effort | Risk and note | Class |
|---|---|---|---|---|---|
| 1 | Task Home (Now strip, quick actions, Recent) | H | M | Low. Counts must reuse existing RPCs; badge-only-actionable rule needs care to avoid false zero. | SAFE |
| 2 | Per-role bottom nav slots | H | S | Low; fallback to today's nav. | SAFE |
| 3 | Do-search with verbs | H | M | Low; registry fields only. Offline limits noted. | SAFE |
| 4 | Guided flows (open/close/factory/month-end) | H | M | Low if link-only; risk is false "done" ticks, hence "unknown" state. | SAFE |
| 5 | Switchboard page | H | M | Medium: a registry that drifts from DB rule defs. Build it from `defs` at runtime. | SAFE (read/write of existing keys) |
| 6 | Needs-you rows oldest first | H | M | Low; bulk approve must stay restricted. | SAFE (bulk money approve = OWNER) |
| 7 | Barcode-first POS (scan opens cart add; scan = default focus) | H | S-M | Low; camera support varies on low-end phones, keep typed/device scanner. Scanner behaviour exists. | SAFE |
| 8 | Repeat last / re-open last sale items for a customer | M | S | Low. Must show current price, not the old price. Check stock/expiry. | SAFE (prices frozen from old = OWNER) |
| 9 | Templates (copy yesterday's expense/transfer/production as draft) | H | M | Medium: copies become drafts only, never auto-submitted; numbers must be re-confirmed. | SAFE as draft-only |
| 10 | Smart defaults (location, date, last supplier, last unit) | H | S | Low. Default only prefill; never prefill counts (blind-count integrity) or amounts of cash. | SAFE |
| 11 | Offline-first indicator + Not-sent list in header | H | S | Low; truthful states (no service worker yet: first load needs internet, REMAINING 15). | SAFE |
| 12 | Number-pad entry mode (inputmode decimal, big keys) for counts/cash | H | S | Low; keep paste of Bangla digits normalized. | SAFE |
| 13 | Voice entry for item search / notes | M | M | Medium: browser speech support and Bangla accuracy are poor on cheap phones; notes only, not numbers. | SAFE, optional |
| 14 | Keyboard shortcuts on desktop (/ search, n new, g h home, Ctrl+Enter submit) | L-M | S | Low; need a "?" cheat-sheet. | SAFE |
| 15 | Saved filters and report views as home shortcuts | M | S | Low; views already exist. | SAFE |
| 16 | Low-stock reorder suggestions to a purchase draft | H | M | Medium: touches purchasing practice; suggestion list only, never auto-order. | OWNER |
| 17 | Auto-close day when counts match | M | M | High: changes cash control. | OWNER (recommend NO) |
| 18 | Auto-approve small amounts | M | M | High: approval policy. | OWNER |
| 19 | Escalation reminders to owner (push/SMS/WhatsApp) | H | L | Needs paid/external service and consent. | OWNER |
| 20 | Block selling expired stock (setting exists as backlog 12) | M | S | Business rule. | OWNER |
| 21 | Block unpriced items / "Data needed" prompts in-line to fix | M | S | Keep rule, only add a shortcut to the bulk editor. | SAFE |
Honest trade-offs: more shortcuts means more places that must stay in sync; the registry (ia.js) must be the single source for verbs, aliases, quick-action defaults and flows, otherwise this becomes a second drifting menu.

---
## 8. Phased roadmap (small budget, each independently shippable)
Principle: each increment adds a page or a section behind a setting (`ui_home_v3`, `ui_flows_on`, `ui_switchboard_on`), default ON for the owner only first, then everyone. Existing routes untouched, so rollback = flip the setting.

### Increment A - "Find and start fast" (Home + nav + search)
Scope: Home Now strip + quick actions + Recent (reuse tile code in nav.js and `CNT` counts); per-role bottom nav slots; do-search with verb table; empty-state copy; breadcrumb/back rules (3.4).
Acceptance tests:
- A1 Cashier login: Home shows "Sell" as one tap from open; no owner-only row appears; Now strip shows only own drafts/dues.
- A2 Owner with 2 pending emergency requests and 1 exception: Now strip lists 3 rows oldest first; approving one decrements to 2 without reload; staff with no approve grant never sees any of them.
- A3 Search "close day" (and "দিন শেষ") returns the flow; "sell" returns POS; user without `canPos` gets no Sell result (or lock row in lock mode).
- A4 Back from drawer/sheet closes it first; back from a dirty form asks Draft/Discard/Stay.
- A5 Bottom nav always has exactly 4 slots; an unavailable slot is replaced; nothing disappears from the drawer (compare route set before/after: identical).
- A6 Existing suites still pass: nav, pos2, rules, reports, settings2 (tests/web).
- A7 Offline: Do/Go results work, Find shows the offline notice.

### Increment B - "Guided days and the owner's inbox"
Scope: `#/flow/<id>` generic stepper + 4 flows (data-driven); Needs-you rows (oldest first) in Control Center; Exceptions triage buckets; Delegation board (read-only first, then pause/resume).
Acceptance tests:
- B1 Close day flow: step 1 turns done only after a 06-1 for that shop/date exists; opening it and cancelling leaves it todo; a step the user lacks the grant for shows "needs <role>".
- B2 "Unknown" state: with the check query unavailable (phase not installed) the step shows "check manually", never a green tick.
- B3 Skip needs a note and is audit-logged; flow cannot be marked complete by a tap.
- B4 Needs-you: 10 mixed rows sorted by age; approve/reject writes via the same RPC as the source screen; rejecting without note is refused; money types have no bulk approve.
- B5 Delegation board lists holders identical to the grants screen (compare counts); pausing a grant makes the server refuse the action for that user (test with a SQL/web test).
- B6 Server-authority test: forge a client call without the grant and confirm the server refuses even though the tile is hidden/visible.

### Increment C - "One language and one switch page"
Scope: Switchboard (search, module chips, recently changed, different-from-default, reset with diff); glossary pass on new strings only; record-page/list-page anatomy applied to 3 pilot screens (Items, Dues, Purchase bills); smart defaults and number-pad mode; templates as drafts.
Acceptance tests:
- C1 Switchboard shows the same key count as the rules + settings sources (diff test); changing a switch from here equals changing it in Rules (audit log entry identical).
- C2 "Reset to default" shows a diff and requires a note; reset of a module never touches other modules.
- C3 Search "discount" finds the switch and the Rules entry in Bangla and English.
- C4 Pilot screens pass the anatomy checklist (search, chips, sort, empty/filtered-empty/error/offline states present).
- C5 Smart defaults never prefill counts/cash; template copy creates a Draft only, number fields marked "confirm".
- C6 Glossary lint: no new i18n key duplicates a glossary term with different wording.
Out of scope for all three: new business rules, auto-approvals, notifications, new database tables (except possibly a per-user `recent`/`flow_state` convenience table - prefer localStorage with try/catch; flow ticks are derived from server data, not stored).
Budget note: A is the highest value per effort; B second; C can be sliced screen-by-screen.

---
## 9. Design handoff list (where the owner's later theme applies)
Behaviour above is fixed; the theme sets the look. Components/screens to style:
1. Header (hamburger, title, category label, search, pin, ⋮) and the do-search overlay (sections, verb chips, recent).
2. Bottom nav (4 slots, current, dot, locked/replaced slot).
3. Drawer (group headers, dots, active row, footer: language, location, sync).
4. Home: Now strip rows, quick-action buttons (size, icon style), Pinned, Recent, numbers block, period tabs.
5. Marker system: edge bar, dot, chip - a semantic token set (bad / warn / ok / info / none) needed for status chips, queue rows, due ageing. The docs/plan_v2/UI.md "calm edge-marker" direction remains the reference; the theme replaces values only.
6. Buttons: primary, secondary, tertiary, danger, toggle/segmented; sticky action bar.
7. Record page (status chip, key facts, timeline), list page (chips, sort, bulk bar, pager), bottom sheets (filter, approve, confirm, error), dialogs.
8. Guided flow stepper (step states: todo, done, skipped, blocked, unknown, needs-other-person).
9. Control Center: Needs-you row, exception buckets, delegation board table, switchboard row (switch / number / choice), diff sheet.
10. Empty/loading/error/offline/no-permission states, toasts, offline info bar.
11. Money and numbers display (tabular, negative/due), Bangla and Latin digits, 17px base and Bangla line-height needs.
12. Printed outputs (receipt, labels, invoice designer) follow the separate invoice template designer, not this theme.
Not themeable: brand name text and logo (fixed ISLAMIYA MISTY GHAR / ইসলামিয়া মিষ্টি ঘর), status words, glossary labels.

---
## Appendix - open points the owner may decide (defaults chosen, switchable)
- Lock cards vs hide for no-permission: keep existing `ui_noperm_mode` (default lock).
- Bank-deposit step in Close day: until a deposit screen exists, "mark done with note".
- Role home variants: defaults in 2.6; owner overrides per person.
- Form codes with `?` in section 1 must be verified against the live forms table before binding quick actions.
- Dependency: ia.js ids and `verbs/aliases/quick/flow` fields should be agreed with the builder agent before Increment A starts.
