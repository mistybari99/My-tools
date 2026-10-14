# A3 - REAL PROFIT per product and per branch (audit + gap analysis, stages 1-2)

Branch `audit/a3`. Scope: final database (docs/PASTE_ORDER.md, phases 72..111, built by `tests/sql/final_build.sh`), plus `web/dashx_metrics.js`. No SQL/web code was changed.
Evidence: `tests/sql/audit2/a3/a3_scenario.sql` (runner `run.sh`, raw output `a3_output.txt`). Scratch Postgres 16, port 5544. Every expected figure below was hand-computed BEFORE the system was asked.
Code references are `function (file:line)` of the LAST definition in paste order. Items marked "code-read" were not executed.

## 0. Verdict in five lines

1. The system shows GOOD gross profit (revenue - cost of goods) per product, per category, per branch, with honest "cost unknown" handling in most places.
2. It does NOT show true net profit anywhere. Four different "profit" numbers exist (dashboard books, branch P&L, report builder, partner base) and they disagree on the same data.
3. In the scenario below the owner would read +842.80 ("Net profit (books)" tile), +190.00 (sum of branch P&L), -830.00 (branch P&L with cost shares switched on) while the hand-computed true result is -877.20 (unknown-cost item counted at 0 cost) / -1077.20 (unknown item excluded).
4. Missing from every branch/product profit: wastage and expiry loss, card fees, unallocated shared costs. Shared-cost shares are report-only rows, default OFF, not pro-rated by period.
5. Product-level net profit (after any overhead) and contribution margin do not exist.

## 1. Scenario (hand-computed before running)

Places: S1 = location 2 (showroom), S2 = location 3 (showroom), F = location 6 (factory), Main = location 1 (cost_attrib_main). One day (today), accounting ON, autopost ON.

| Item | Setup |
|------|-------|
| A (sweet_kg) | made in F: 2 batches x 10 kg, flour 6 kg x 40 + sugar 3 kg x 20 = 300 raw per batch, labour component 100 per batch (loc_cost_cfg_set(6,'recipe')) -> unit cost (300+100)/10 = **40**. 10 kg transferred to S1, 10 kg to S2 (cost 40 kept). Sell price 100 |
| B (resale) | S1 opening 10 @ 50, sell 90 |
| C (resale) | S1 opening 5, NO cost known, sell 100 |

| Event | Place | Amount |
|-------|-------|--------|
| Sale 1: A 5 kg, discount 50 | S1 | 500 - 50 = 450 cash (avg 90/kg) |
| Sale 2: B 4 pc by card | S1 | 360 |
| Sale 3: C 2 pc (cost unknown) | S1 | 200 |
| Sale 4: A 8 kg, discount 160 (20 %) | S2 | 640 cash (avg 80/kg) |
| Return of 1 kg A from sale 1 | S1 | refund 90 (discount share kept), COGS back 40 |
| Wastage 1 kg A | S2 | 40 at cost |
| Card settlement 360, fee 7.20 | S1 | fee 7.20 |
| Salary (form 02-2) | S1 300, F 200 | |
| Quick expenses: rent S1 150, delivery (transport) S2 40 | | |
| Electricity bill 600, shared S1:S2, rule headcount 2:1 | | S1 400, S2 200 |
| Internet bill 300, shared, rule fixed 70:30 | | S1 210, S2 90 |
| Accounts-software bill 120, admin share of S1, attribution "main centre" | | Main 120 |

Hand-computed expectations (costed items only; C shown separately):

| | S1 | S2 | F | Main | Company |
|---|---|---|---|---|---|
| Net sales (after discount and return) | 920 (incl. C 200) | 640 | 0 | 0 | 1,560 |
| Costed revenue | 720 | 640 | | | 1,360 |
| COGS | 360 | 320 | 0 | | 680 |
| **Gross profit (costed)** | **360** | **320** | 0 | | **680** (50.0 %) |
| Wastage + card fee + delivery | -7.20 | -80 | | | -87.20 |
| **Contribution margin** | **352.80** | **240** | 0 | | **592.80** |
| Salary | -300 | 0 | -200 | | -500 |
| Rent | -150 | | | | -150 |
| Shared bills (electricity, internet, admin) | -610 | -290 | | -120 | -1,020 |
| **Net profit (C excluded)** | **-707.20** | **-50** | **-200** | **-120** | **-1,077.20** |
| Net profit (C taken at cost 0) | -507.20 | | | | -877.20 |

Product expectations: A = rev 360 / cogs 160 / GP 200 at S1 (net of return), 640 / 320 / 320 at S2; B = 360 / 200 / 160; C = revenue 200, profit UNKNOWN.

## 2. What the system actually shows (all from `a3_output.txt`)

| Figure | Source (file:line) | S1 | S2 | F | Company |
|---|---|---|---|---|---|
| Revenue / discount / costed rev / cogs | `biz_daily` (phase72:110) | 920 / 50 / 720 / 360 | 640 / 160 / 640 / 320 | - | 1,560 / 210 / 1,360 / 680 |
| Brand GP | `brand_pnl` (phase20:457) | 360 | 320 | | 680 |
| Shop P&L profit (switch OFF) | `_r3q_l3_shop_pnl` (phase89:499) over `_p27_pl` (phase72:168) | **110.00** | **280.00** | **-200** | **190.00** |
| Shop P&L + cost-share rows (switch ON) | same, `_c78_rows` (phase78:175) | 110 - 610 = **-500** | 280 - 290 = **-10** | -200 | Main -120; total **-830.00** |
| "Net profit (books)" tile and income statement | `acct_income_statement` (phase72:583), `net_profit` tile (dashx_metrics.js:141) | 402.80 | 240.00 | **+200.00** | **842.80** (flag `provisional:true`, tile ignores it) |
| Report builder item_sales GP | `rpt_agg_sql` (phase110:191) | A 250 (cogs 200) | A 320 | | by location: S1 net 1,010 / gp 410 |
| Margin report item level | `_r3q_l2_margin` (phase72:263) | A 200, B 160, C blank | A 320 | | 1,560 / 680 |
| `biz_items` revenue / cogs | phase88:186 | A 450/200, B 360/200, C 200/NULL | A 640/320 | | 1,650 / 720 |
| Dashboard gross profit / margin tiles | dashx_metrics.js:134-140 | | | | 680 / 50.00 % |

## 3. Check results

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| C1 | Revenue per branch is net of discount and shows the discount separately | **PASS** | `biz_daily` S1 920/disc 50, S2 640/disc 160. `biz_items` scales each line by total/subtotal (phase88:204). Discount tile = sum(sales.discount) (dashx_metrics.js:124) |
| C2 | A return reduces revenue AND cost, with its discount share | **PASS** in biz_daily, `_p27_pl`, `_r3q_l2_margin`, brand_pnl, GL (refund 90 not 100; COGS back 40 -> S1 cogs 360). **FAIL** in `biz_items` and the report builder | `biz_items` A revenue 1,090/cogs 520 (no return) vs margin report 1,000/480. Builder S1 A net 450, gp 250 vs margin 200. Builder by location S1 net 1,010 vs biz_daily 920. Cause: `biz_items` uses `h.src='sale'` only (phase88:209); `sales_fact` has no return rows |
| C3 | Raw material + conversion cost is in product cost | **PASS** when `loc_cost_cfg_set(6,'recipe')` and a labour component exist: unit cost 40.0000 (P0). **Silent when not configured** | `_conv_cost` returns amount 0, `complete:true` when mode is `off` (phase74:185); `location_cost_cfg.mode` defaults to 'off'. No visible flag on the profit screens |
| C4 | Factory shared bills (electricity etc.) reach product cost | **NOT RUN** (code-read) | `_cs_push_pools` writes `factory_cost_pools` rows for dest `factory` (phase75:366); `_pool_rate` feeds pool-mode recipes only. Factory shares cannot be reassigned (`factory_share_not_reassignable`, phase78:275) |
| C5 | Factory payroll flows into product cost | **FAIL** (design gap) | Labour in product cost is the typed recipe component (200). Factory salary 200 is ALSO a branch loss in `_p27_pl` (F profit -200) -> counted twice in the company sum (COGS includes the 200 and F shows -200) |
| C6 | Branch operating costs: rent, delivery, utilities, salary | **PARTIAL** | Rent 150 (S1) and delivery 40 (S2) in `_p27_pl.o_exp` (quick_expenses + 10-2 lines, phase72:168). Salary only from form 02-2 sheet. Utilities/shared bills only as separate rows when `cost_attrib_in_pl` is ON (default OFF: `l3_off` = 0 rows) |
| C7 | Wastage / expiry loss in branch or product profit | **FAIL** | GL S2 shows 5100 wastage 40 (`_acct_docs`, phase103:325). `_p27_pl` has no wastage term: S2 profit 280 instead of 240 before shares. Not in `biz_items`, builder, partner base |
| C8 | Card / payment fees in branch or product profit | **FAIL** | Fee 7.20 only in GL account 5810 at the settlement location/date (`card_settle`, phase109:686). Not in `_p27_pl`, shop P&L, partner base. No per-sale or per-product fee. Mobile-wallet fees have no table at all |
| C9 | Salary by branch (booked to S1) | **PASS** for form 02-2 (S1 300, F 200 in `_p27_pl`). **FAIL** consistency with the books | GL S1 expense lines: 5000, 5810, 5900 only - no 5200 salary. GL posts salary only from payroll-app payments on pay_date (`_acct_docs` payroll_payment, phase103:360). `_p27_pl` reads only 02-2 sheets (phase72:168 CTE `sa`) and ignores payroll_payments (code-read; shadow rule hides the sheet when the app is the record) |
| C10 | Unknown cost shown as unknown, never 100 % margin | **MIXED** | PASS: `biz_items` C cogs NULL; builder C gp NULL, uncosted 100 %; margin report C blank; `by_category` cake_pc `cogs_unknown_items`=1; dashboard gross-profit tile uses costed part only; partner base returns `net_profit_before_fees:null` + warning `uncosted_sales`. **FAIL**: shop P&L `profit` = net - cogs - ... counts C's 200 at 0 cost (S1 110.00, `profit_pct` 11.96); only the text `gaps: cogs(uncosted)` and `uncosted_pct` 21.74 warn. GL "Net profit (books)" 842.80 includes C at 100 % and the tile drops `provisional` |
| C11 | Sum of branch profits == company P&L | **FAIL** | Sum of shop P&L 190.00 (switch off), -830.00 (on); `_p27_pl` sum 190.00; GL company 842.80 (GL internally consistent: sum by loc = company). Hand-computed -877.20 / -1,077.20 |
| C12 | Sum of product profit == branch profit before overheads | **FAIL** | `biz_items` sums 1,650 / 720 vs `biz_daily` 1,560 / 680 (return not netted). The margin report sums 1,560 / 680 and `profit_source_check` agrees with the journal (cogs 680 = 680, difference 0), so only `biz_items` / builder break the sum |
| C13 | Re-assigning a cost is audited and moves profit correctly | **PASS** (report), with limits | Admin share 120: main_centre (loc 1) -> location 3: `_c78_dest` before `main_centre,1`, after `location,3`; shop P&L rows moved (S2 shares 200+90+120). `cost_share_reassign` is insert-only (trigger `csr78_nodml`), reason >= 3 chars mandatory, `audit_log` +5 rows for 3 attribution inserts + main centre + reassign. GL unchanged (S1 402.80, S2 240.00): shares are report-only. Closed period: owner may override, exception `cost_share_locked_reassign` raised (phase78:275, code-read) |
| C14 | Past months cannot be silently restated by settings | **PARTIAL** | `cost_attrib_set` for a past month: refused `effective_in_past` (test H1 PASS). But `cost_share_reassign` applies to any month and reports read the LATEST reassign, so a past month's P&L changes later with no snapshot |
| C15 | Period cut-off for shared costs | **FAIL** | A one-day report on a day with NO activity (yesterday) still shows all 1,020 of shares (`yday_l3`); one-day total 1,020 = whole-month total 1,020 (`_c78_rows` selects month rows with `mth between _m1(from) and to`, phase78:175). Sales, returns (Dhaka date), quick expenses (`exp_today_only` 150 vs two days 175) and `fixed_cost_month` (pro-rated by days) cut off correctly |
| C16 | Allocation by SALES SHARE | **NOT SUPPORTED** | `cost_rule_save` methods: sub_meter, fixed_percent, floor_area, headcount, output_kg, whole_to_one, other_manual (phase75:247). `'sales_share'` -> `bad_value` (test B2 PASS) |
| C17 | Allocation by headcount / fixed % | **PASS** (arithmetic) | Electricity 600 -> S1 400 / S2 200; internet 300 -> 210 / 90; shares always sum to the bill (last share takes the rounding, `_cs_alloc` phase75:290). Headcount values are typed numbers, not read from employees |
| C18 | Unallocated shared costs are visible in profit | **FAIL** | No attribution setting = `unallocated`, "not charged anywhere": `branch_cost_view` showed 1,020 unallocated; `_r3q_l3_shop_pnl` excludes `dkind='unallocated'` rows even with the switch on |
| C19 | Contribution margin per branch / product | **NOT SUPPORTED** | No function or measure; fee, wastage, delivery are not tagged variable/fixed |
| C20 | Net profit per product / category (after overhead) | **NOT SUPPORTED** | Only gross margin: `biz_items`, `biz_items_by_category` (phase100:468), `_r3q_l2_margin`, builder `gp`. Category cogs sums only costed items (cake_pc revenue 560, cogs 200, one unknown item flagged) |
| C21 | Product x branch profit (same product, different discounts) | **PASS** via `_r3q_l2_margin` per location filter or builder `locations` filter; no single matrix | A at S1 90/kg avg after discount, GP 200; at S2 80/kg, GP 320 (cost 40). The two views disagree on S1 A (200 vs 250, see C2) |
| C22 | Dashboard "profit" tiles are what they say | **PARTIAL** | `gross_profit`, `cogs`, `gross_margin` = costed part of `biz_daily` (680, 50.00 %): correct and labelled "(costed part)". `net_profit` tile = `acct_income_statement.net_profit` (842.80): misses sheet salary 500 and cost shares 1,020, includes +200 absorbed-overhead credit, drops `provisional` (dashx_metrics.js:141-142) |
| C23 | Partner profit base == branch P&L | **PARTIAL**: same base as the shop P&L (PASS), not true profit (FAIL) | `partner_calculate` (phase89:1102) uses `_p27_pl` sums: gp - expenses - salary - fixed. Warned and refused for S1 (C uncosted). When costed it omits wastage, card fee and cost shares |
| C24 | Report cost source is one switch | **PASS** | `_rcs88()` ledger_avg / item_costs / ledger_then_item_costs used by `_cogs_lines72` (phase110:94), `_item_cost_eff88`, builder `rpt_agg_sql`; ledger cost 40 used everywhere in the run; `profit_source_check` agrees with the journal |
| C25 | Delivery as revenue/cost | **NOT SUPPORTED** | `online_orders.delivery_charge` feeds only `online_order_save/deliver/list` and `_r3q_s10_orders`; not in sales total, GL or P&L. Delivery cost exists only as a free quick expense (head transport), by place, not by order or product |

Tally of section 3: 25 checks = PASS 5 (C1, C13, C17, C21, C24), FAIL 7 (C5, C7, C8, C11, C12, C15, C18), PARTIAL/MIXED 8 (C2, C3, C6, C9, C10, C14, C22, C23), NOT SUPPORTED 4 (C16, C19, C20, C25), NOT RUN 1 (C4, code-read).

## 4. GAP ANALYSIS

Severity: Critical = owner can make a wrong money decision from a screen that looks final. High = number is wrong in a common case. Medium = wrong in some setups / missing feature. Effort S = under 1 day, M = 2-5 days, L = more.

| ID | Gap | Business impact (wrong decision?) | Sev | Evidence | Fix outline | Eff | Depends on |
|----|-----|-----------------------------------|-----|----------|-------------|-----|-----------|
| G1 | No single true-profit statement. Four "net" numbers: GL tile +842.80, shop P&L +190 / -830, builder, partner base. Truth -877.20 | YES. Owner sees a profit and keeps a loss-making branch, or the reverse; partner payout could be based on a different number than the dashboard | Critical | Section 2; C11, C22; `acct_income_statement` phase72:583 vs `_r3q_l3_shop_pnl` phase89:499 | Define ONE branch/company profit function (revenue - cogs - wastage - fees - opex - shares) used by dashboard, P&L, partner. Return a `completeness` object (missing: salary, shares, unknown cost). Make tile show it | L | G2, G3, G4 |
| G2 | Salary lives in two stores: 02-2 sheet (read by `_p27_pl`, not posted to GL) and payroll-app payments (posted to GL on pay date, not read by `_p27_pl`) | YES. GL net profit is overstated by every sheet salary (500 here); app payroll is missing from branch P&L | Critical | C9; `_p27_pl` CTE `sa` (phase72:168) vs `_acct_docs` payroll_payment (phase103:360) | One salary source per period: P&L reads payroll_lines (accrual by month) when the app is the record, else 02-2; GL posts accrual or P&L labels cash basis | M | G1 |
| G3 | Wastage, expiry loss, stock-count loss not in branch P&L, product margin, partner base (GL only) | YES. A branch with high spoilage looks 40 better per day; expiry-prone product looks more profitable than it is | High | C7: S2 280 vs 240 | Add `o_wastage` to `_p27_pl` from stock_wastage x ledger cost (same query as `_acct_docs` wastage) and a per-item wastage column to `_r3q_l2_margin` | M | none |
| G4 | Card fees (and wallet fees) only in GL at settlement date/place; never in branch/product profit; no fee on the sale | Medium-High. Card-heavy showroom margin overstated by the fee rate (2 % here) | High | C8: 7.20 missing | Add `o_fees` from card_settlements85 (by settle_date, location) to `_p27_pl`; later allow fee % per pay mode to attribute fee per sale/product | M | G1 |
| G5 | Revenue with unknown cost counted at 0 cost in the shop P&L profit and the books tile (`profit` 110 includes C 200) | YES. A branch selling many uncosted items looks very profitable; only a text note warns | High | C10: S1 profit 110.00 / 11.96 %, GL 842.80 `provisional:true` ignored by tile | Return `profit` null (or `profit_costed_only` + `profit_unknown_rev`) when uncosted_pct > threshold; show a red badge on the tile from `provisional` | S | none |
| G6 | `cost_attrib_in_pl` default OFF; shares are separate rows, not in the branch `profit` field or the totals; GL never holds them | YES. By default shared electricity/internet/rent never touch any branch profit | High | C6, `l3_off` 0 rows; rows have `profit = -amt` as extra rows | Make shares part of the branch row (`overheads_attributed`) and of the company total; advisor row to switch on | M | G1 |
| G7 | Unallocated shared costs vanish from every P&L (no rule -> unallocated -> "not charged anywhere") | YES. 1,020 of cost invisible until someone opens branch_cost_view | High | C18 | Put an "Unallocated" row in the P&L and block month close while unallocated > 0 (rule, default warn) | S | none |
| G8 | Shared-cost shares not pro-rated: any date range inside a month shows the whole month's bill; a quiet day shows 1,020 | YES for daily/weekly views: weekly profit double-counts the month bill if reports are added up | High | C15: 1-day = month = 1,020 | Pro-rate monthly bills by days of the range (like `fixed_cost_month` already does) or label rows "month total" and exclude from sub-month ranges | S | none |
| G9 | Returns not netted in `biz_items`, `biz_items_by_category`, builder `item_sales` | YES. Top-product ranking and product margin ignore returns (A 1,090 vs 1,000; gp 250 vs 200); returned-heavy products look best | High | C2, C12 | Make `biz_items` read `_cogs_lines72` rows with sign (as `_r3q_l2_margin` does); add return rows to `sales_fact` or subtract in builder | M | none |
| G10 | Factory conversion cost default `off`, silent (`complete:true`, amount 0); labour is a typed recipe component, not linked to factory payroll; factory salary also hits the factory branch | YES. Product cost can exclude labour and overhead entirely, or count labour twice (200 in COGS and F -200) | High | C3, C5; `_conv_cost` phase74:185 | Setup advisor makes mode mandatory when production exists; pool labour pulled from payroll; mark factory salary as "absorbed" so the branch row does not double count | M | G2 |
| G11 | No sales-share allocation; headcount is typed, not read from employees; no month-by-month automatic re-split | Medium. Owner must hand-type percentages that go stale when sales mix changes | Medium | C16, C17; `cost_rule_save` phase75:247 | New method `sales_share` (previous month net sales per place) and `headcount` from employee_locations | M | G6 |
| G12 | Reassign applies to any past month and reports show the latest assignment: closed months change later (audited, no snapshot) | Medium. Last quarter's branch result can change after it was reviewed | Medium | C14; reassign on closed month = owner override + yellow flag | Freeze P&L snapshot at month close, or show "restated on <date>" on the row | M | none |
| G13 | No contribution margin; fixed/variable not classified; no product net profit after overhead | Medium. Cannot decide to close a branch or drop a product on contribution | Medium | C19, C20 | Tag cost types variable/fixed in `cost_source_types` and expense heads; add contribution column | L | G3, G4, G6 |
| G14 | Expense heads: `rent`, `utilities` have no account mapping; `rent` quick expense lands in 5900 "Other expenses" (accounts 5300/5400 exist, mapping missing) | Low-Medium. Rent by branch cannot be read from the books | Medium | GL S1: 5900 150 for head rent | Add `exp_rent`, `exp_utilities` to acct_mappings and quick-expense heads | S | none |
| G15 | Delivery has no revenue or cost model (`delivery_charge` informational; delivery cost = free quick expense) | Medium. Delivery profitability unknown | Medium | C25 | Add delivery charge to sale total and cost to order | M | none |
| G16 | Bill duplicate guard only checks form 10-2; a quick expense for the same electricity bill is not flagged, double counted when the switch is ON | Medium | Medium | `cost_bill_add` dup guard looks at `entries` form 10-2 only (phase75:417, code-read) | Extend guard to quick_expenses | S | none |
| G17 | Product margin screens share one cost switch, but the labels say "Gross profit" in all of them with different return and fee treatment | Low | Low | C24 | Document in-screen; unify through G1 | S | G1 |

## 5. Assumptions

- Owner role used for all calls; role-limited (non-cost) users get NULL cost columns by design and were not tested here.
- `reports_net_of_returns` left at default (ON), `cost_attrib_in_pl` default OFF then ON as stated, `report_cost_source` default.
- Payroll-app path (payroll_payments) is code-read only; the sheet path was run.
- Factory shared-bill -> pool path (C4) is code-read.
- Sale, return, wastage and expenses all on one date; month totals for bills.
- The seeded real locations 1..7 of the build were used; no real person names appear.
- True net profit definition used for expectation: gross profit(costed) - wastage - card fee - delivery - rent - salary - attributed shared bills; unknown-cost revenue excluded (and also shown at cost 0).

## 6. Counts

25 checks: PASS 5, FAIL 7, PARTIAL 8, NOT SUPPORTED 4, NOT RUN 1. 17 gaps: 2 Critical (G1, G2), 8 High (G3-G10), 6 Medium (G11-G16), 1 Low (G17). Scenario script itself: 11 hard assertions, all PASS (unit cost 40, discount-share return 90, shares 400/210, sales_share refused, past-month attribution refused).

## 7. How to re-run

```
bash tests/sql/final_build.sh a3db            # once
createdb -T a3db a3run                         # per run (the scenario writes data)
bash tests/sql/audit2/a3/run.sh a3run          # prints PASS/FAIL lines and every figure above
```
