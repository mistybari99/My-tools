# Integration note RPT-C2: order and delivery (R4), customer (R5) and staff (R6) reports

Source: `docs/REPORTS_AUDIT_3.md` (reports #138-#163 of the master list, packages R4, R5, R6). SQL numbers **445 to 457**, pasted after phase 99, in numeric order, each paste-twice safe. No old phase file and no old function was edited. Every new behaviour is a setting that defaults to OFF or blank; reading never writes. Local throwaway Postgres only (port 5700); the live project was not touched; nothing was pushed.

## 1. What each phase does

| Phase | Reports | Content |
|---|---|---|
| 445 | capture | `order_cake_specs` (weight, flavour, message, design, photo reference), `order_promises` (promised time slot), `c2_order_spec_save`, `c2_order_promise_set`, `c2_orders_features()`. Rules `order_promise_required` (OFF), `order_late_grace_minutes` (blank). |
| 446 | #162 capture | `order_delivery_costs` (actual cost per order, list `order_delivery_cost_kinds`), `c2_order_cost_add / _void`. Information only: nothing posts to the books. |
| 447 | #156 capture | `order_advance_posts`, `c2_order_advance_post / _void / _apply`, `c2_order_deliver`. Rules `order_advance_post_on` (OFF), `order_advance_post_from` (blank). Uses only the existing `cash_move_add` (`cust_advance`, `cust_advance_used`). |
| 448 | #157 capture | `order_refunds`, `c2_order_cancel`, `c2_order_refund_pay / _void`, `c2_order_refunds_list`. Rule `order_refund_record_on` (OFF). A refund is a real money record through `cash_move_add` (`cust_advance_refund`). |
| 449 | #153 #155 #156 | `_c2_orders_base` (one normalised row list: app order, paper 05-1, paper 23-1, never merged), `c2_order_register`, `c2_cake_register`, `c2_order_balances`, `c2_order_detail`. |
| 450 | #159 #158 #163 | `c2_orders_delayed`, `c2_orders_ontime`, `c2_order_fulfilment`. |
| 451 | #157 #162 | `c2_order_cancellations`, `c2_delivery_cost_report`. |
| 452 | #160 #161 | `production_run_orders` (order on a production run), `c2_production_link_order / _void`, `c2_orders_for_production`, `c2_order_production_cost`, `c2_order_profit`. |
| 453 | #138 + notice | `customers.credit_days`, rules `credit_default_days`, `credit_risk_watch_days`, `credit_risk_high_days` (all blank), `c2_customer_credit_days_set`, `c2_credit_risk`, `c2_credit_terms_list`, `c2_dues_not_linked_notice`. |
| 454 | #139 #140 #141 | `c2_customer_ltv` (all time, no 365-day cap), `c2_customer_returns`, `c2_customer_special_orders`, `c2_customer_card`. |
| 455 | #142 #147 + notice | `c2_att_period_summary`, `c2_att_person_days`, `c2_salary_basis`. |
| 456 | #150 #148 | `c2_cashier_variance`, `c2_sales_per_labour_hour`. |
| 457 | #149 capture | `production_crew`, `c2_production_crew_set / _get`, `c2_crew_pick`, `c2_output_per_labour_hour`. |

Table and function names: browser functions are `c2_*`; helpers `_c2_*` are closed to browsers (`c2_can_read_orders`, `c2_can_read_customers`, `c2_can_read_staff`, `c2_order_visible` stay open because the row policies call them). The CRM tables (phases 300-340) are not touched.

## 2. Rules the build follows

* **Reports are open.** Access is the existing report right (owner, `report_orders` / `report_customers` / `report_staff` / `report_cash` / `report_pos`, `view_reports`) or the right that already shows the data (POS view, `_att_view`). A module that is not switched on does not hide the report: the answer carries the note `module_off` ("Module not switched on") and still returns what exists (paper rows, earlier orders).
* **Never 0 when data is missing.** A figure that cannot be known is `null` and the screen shows a dash with the title "not captured": delivery cost not written, balance of a handed-over paper sheet with no due payment written, on-time percentage with nothing judged, sales per hour with no hours, profit with a missing cost, overdue for a customer with no terms. Counts of the unknowns are shown beside the figures.
* **Nothing invented.** Late grace, credit days, risk days are blank settings; with them blank the report says "rule not set" and shows ages and amounts. Costs split by quantity only when the quantity is written.
* **No silent change of a figure.** The old `online_orders_list` balance, `customer_dues`, the hub reports and every posted figure are unchanged (proved: old suites phase 9, 12, 23, 25, 40, 42, 61, 87, 99 give identical result lines with and without 445-457). The Online orders card shows the old balance and, for delivered or cancelled orders, a second line with the true figure.
* **Money-affecting behaviour is behind settings, default OFF = today:** advance posting (447), refund record (448), promise gate (445). A cancelled-order refund, a posted advance and its application use only `cash_move_add` (so the existing cash right, period lock, backdate and money-source rules apply).
* **New data capture is a digital entry inside the software.** Paper form code for a printed cake sheet, crew sheet or cashier box: **to be given by owner** (none invented). The Cashier box on 06-1 is a new field of the existing form, not a new form.

## 3. Hook sites (what the integrator must merge or paste)

SQL hooks: **none**. No old SQL function is patched. The web calls the new `c2_*` functions when `c2_orders_features()` says the server has them and falls back to the old calls otherwise (`online_order_cancel`, `online_order_deliver`). Three triggers were added to `online_orders` (promise gate, advance guard, refund-due row), each inert while its setting is OFF. One column was added to `customers` (`credit_days`).

Web hook sites:

| File | Change |
|---|---|
| `web/c2rpt.js` (new) | shared helper `BOS.c2ui`: filters, tables, notes, CSV, drill-down, page factory, hub link helper. |
| `web/orderreports.js` (new) | route `orderreports` (10 tabs) and `BOS.c2orders` (capture helper used by salesx.js). |
| `web/custinsight.js` (new) | route `custinsight` (credit, lifetime value, returns and complaints, special orders, customer card with credit days). |
| `web/staffreports.js` (new) | route `staffreports` (attendance, variance, sales per hour, output per hour, cashier variance, salary basis) and `BOS.c2prod` (crew and order fields of the production sheet). |
| `web/salesx.js` | additive guarded lines: `B.c2orders` init/attach on load, cake and slot fields in the order form, refund-mode box and `c2_order_cancel` on cancel, delivery cost box and `c2_order_deliver` on deliver, a Details button, a second balance line for closed orders. |
| `web/forms_cash.js` | one block at the end: Cashier box added to the head of form 06-1. |
| `web/recipes.js` | production sheet: `#pr_c2` placeholder filled by `B.c2prod`, crew and order saved after `production_post` returns a `run_id`. |
| `web/ia.js` | three `rec(...)` lines (before `biexport`): `orderreports` (group `sale`, also `factory`), `custinsight` (group `cust`), `staffreports` (group `people`, also `acc`). No Home tile, no bottom-bar slot, no route removed. |
| `web/index.html` | four script tags after `salesx.js`. |
| `tests/web/s10_common.js` | `ROOT` now points at this checkout's `web/` (it was a fixed path to the main checkout, so tests run in a worktree tested the wrong files). |
| `tests/sql/ORDER.txt` | one comment line and one line `phase445 ... phase457` after phase99. |

Reports hub: each screen pushes one `B.reportLinks` entry (`c2_orders`, `c2_cust`, `c2_staff`). The R1 package's own hub/notes work (`reportnotes.js`) is not touched; the salary-basis notice here is a read function and a tab, not a banner on the hub T3/T4 reports.

## 4. Settings added (all through `rules`; the owner changes them in Settings)

`order_promise_required` OFF, `order_late_grace_minutes` blank, `order_advance_post_on` OFF, `order_advance_post_from` blank, `order_refund_record_on` OFF, `credit_default_days` blank, `credit_risk_watch_days` blank, `credit_risk_high_days` blank. Plain-English (i) texts for each setting, capture box and report: `docs/integration/RPT-C2_info.json`.

## 5. Tests

* SQL, local Postgres 16, one suite per phase (`bash tests/sql/c2_run.sh phase445 ... phase457`; builds phases 8-99 once, pastes the C2 phases, pastes them all a second time on a copy, runs the suite): 35 + 25 + 24 + 24 + 37 + 23 + 20 + 30 + 25 + 27 + 21 + 13 + 20 = **324 checks, 0 failed**. Fixtures: `tests/sql/c2_fixture.sql`, `c2_orders_fixture.sql`, `c2_cust_fixture.sql`, `c2_staff_fixture.sql` (neutral `test_*` data only).
* Web, headless Chromium at 360 px: `tests/web/c2_test.js` (mocked RPCs) plus the regression set `bash tests/web/c2_regress.sh` (ia, nav, nav2, control, favsync, settings2, salesx, recipes, allforms, forms_links, customers, wave1 wiring and comment guard, reports).

## 6. Known limits and decisions left to the owner

* With advance posting ON, the sale made at delivery shows the advance part as due until it is applied, and the customer dues lists (which count sales and sale payments only, as for every `cust_advance_used` today) keep showing it; the order register, balances report and credit report show the applied advance beside the due. A customer credit limit smaller than the advance can stop the delivery sale; void the posted advance and deliver the old way in that case.
* Posting, voiding or applying an advance and paying a refund need the existing `cash_move` right. A salesperson without it can still cancel: the refund waits as "due" in the refund list.
* A `income` advance fate on an order whose advance is posted is refused (the accountant moves 2300 to income by hand).
* Complaints (32-1) link to customers only through the optional phone box; unlinked sheets are counted, not guessed. Making the phone required is an owner decision.
* Paper 05-1 rows are judged late by the date and time written on the sheet; the sheet has no delivery timestamp, so paper never enters the on-time percentage.
* Order profit nets nothing for returns: an order whose sale has a return is "not judged".
* Not tested: a real phone, live data volume, the real photo upload path (`B.s2.uploadPhoto` is called when present), period-lock interplay beyond what `cash_move_add` already enforces, the (i) sheet rendering (the JSON is delivered; the screens show the same text as the tab introduction).
