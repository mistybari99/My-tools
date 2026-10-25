# REPORTS PLAN - staged, prioritized (sweets business; written with REPORT_MATRIX.md)

Rules that hold for every stage: additive SQL only (new phase after the last one), new features OFF behind a rule, every report works on the caller's places (`can_loc`, business-safe when `org_scope_on` is ON), no company-wide figure for non-owners, cost only for `rpt_cost_ok()`, salary only for `salary_view`/owner, unknown = "data needed" (never zero), financial reports tie to the journal and separate draft / posted / void / refunded / reversed, a number test with hand-computed values for every new report, one full `run_all_sql` against `baseline_fails.txt` at the end of a stage.

Counts today (from the matrix, 193 items): see the Counts table in REPORT_MATRIX.md. In short: most of the sales, stock, cash, ageing and accounting reports exist; the weak areas are (a) reports built on typed paper-form jsonb (production, temperature, hygiene, purchase scorecards, expense), which have no number tests, (b) whole groups that need data nobody captures yet (cake orders, delivery, targets, production plan, campaigns), (c) known repair gaps from audits A1-A5.

## Stage 1 - DONE in this change (phase131, no new data capture)
Seven reports + catalogue + export log, rule `rpt131_on` default OFF, screen `#/reports131`, 197 SQL asserts, mocked-RPC web test.
Sales net of voids/returns on nine groupings (incl. hour, weekday, payment method); sales/return document register with posted / unposted / void / reversed / void-not-reversed / refunded and the tie-out to the journal; item / category / outlet profit with real ledger costs and an uncosted share; stock reconciliation (paged adapter); wastage by reason/item/outlet/day/status/document with pending/rejected/cancelled/reversed; cash book and day-close per outlet-day (register vs books vs the daily sheet); receivable and payable ageing with the books tie-out and advances.

## Stage 2 - missing reports whose data already exists (no new capture) - next
Order by value:
1. Below-cost / negative-margin list and discount-impact-on-margin (filters on rpt131_item_profit and discounts). Small.
2. Price change history (`item_price_history`) with who/when/old/new; items whose price changed in the period and sales before/after.
3. Purchase side registers: supplier payments register, purchase returns and refunds, purchase price variance (account 5140), landed-cost summary per bill. One phase, same pattern as Stage 1 (status, ledger tie to account 2100).
4. Customer loyalty: points ledger, gift rules/redeemed gifts, tier effect.
5. Staff: employee advances and recoveries, overtime cost, shift roster vs attendance (salary secrecy: `salary_view`).
6. Orders: online order cancellations/reasons, fulfilment time, orders by channel, duplicate-order flags (from `online_order_events`, `sales_channels`, `order_dup_flags`).
7. Food safety from data that exists: shelf-life rule compliance, batch ageing (days on hand), wastage % of sales/production, QC records report, negative-stock exceptions, period-lock/closed-period log.
8. Returns by reason (sale_returns.reason_code) and sales return rate per staff.
Dependencies: none new; each is a read function + a tab in `#/reports131`. Switch: reuse `rpt131_on`.

## Stage 3 - repairs of reports that exist but mislead (documented gaps)
1. `daily_digest` is not place-scoped and values wastage at the current average cost: scope it by `can_loc` for non-owners and use the ledger cost (the executive dashboard depends on it).
2. `receivable_aging` (engine 1) ignores the credit given on returns, so it can disagree with `customer_dues`; make it call the same FIFO as `rpt131_ageing`, then retire the duplicate.
3. Older `item_sales` / `category_sales` are net of returns only through `reports_net_of_returns`; point them at `_cogs_lines72` or mark them "gross" in the title.
4. A4-G07: a void/reversal is booked on the void date; report a "voided after posting" list by sale date and void date (the tie-out already shows the timing gap).
5. A4-G02: automatic day-end cash close (expected cash computed by the system, counted cash entered once, difference posted to 5800); today the counted cash is a typed paper form.
6. A4-G06 card settlements matched to card sales; over-settlement refused.
7. A2-G10: sales older than 72 h are re-dated to now without a flag; flag them and list them.
8. A2-G11 transit shortage visible after receive; A3-G14 expense heads mapped to accounts; A3-G1 turn `profit_truth_mode` on after the accountant review.
Each repair is a re-created function (tagged bosNN, tag-loss check) with before/after fingerprints and an entry in the re-paste tail.

## Stage 4 - needs new data capture (owner decisions first, each a short MCQ)
1. Targets: sales / margin / wastage % per outlet and month (new table, rule) - executive dashboard 1.10, planning 14.x.
2. Cake orders and delivery: order, advance, balance due, flavour/message, due date/time, delivery address/charge/rider, status - groups 11 and pre-order production planning.
3. Production plan and production date on finished goods; end-of-day leftover count - freshness (6.10, 6.11), plan vs actual (4.09).
4. Hours worked linked to sales (sales per labour hour), labour per product (A1-G12).
5. Campaigns/promotions with a code or period, so promotion performance can be measured (12.04); channel and social spend by campaign.
6. Seasonal/festival calendar (owner-entered) for uplift comparison.
7. By-product / co-product output (A1-G9); semi-finished goods as ingredients (A1-G1 switch exists).

## Stage 5 - verify the reports that read typed paper forms (jsonb)
Production, yield, raw vs recipe, breakdowns, fridge temperature, hygiene, complaints, purchase scorecard/rate trend/PO match/budget, cash flow, handover, expense heads, orders (20-1/20-6), marketing limit. They exist and have a menu entry, but no number test was found. Plan: one test file per group with seeded forms and hand numbers; where a form field is renamed the test fails; then decide per report whether to move it onto structured tables.

## Stage 6 - owner acceptance
Real phone at 360 px, real Supabase (nothing here ran there), Bangla wording review by the owner, switch-on order (accounting_on -> daybook -> `rpt131_on`) one per day with a check after each, export test with the printer/PDF path.

## Switch-on order for Stage 1 (owner)
1. Paste Run 21 (phase131) and the read-only CHECK. 2. Set `report_aging_buckets` (e.g. 30,60,90) if ageing buckets are wanted. 3. Give report grants (`report_sales`, `report_stock`, `report_cash`, `report_customers`, `report_purchase`, `report_profit`, or `view_reports`) and `view_stock_recon`, `accounts_view` where the books side should show. 4. Turn `rpt131_on` ON in #/switchboard; open #/reports131. OFF returns every report to "off" instantly.
