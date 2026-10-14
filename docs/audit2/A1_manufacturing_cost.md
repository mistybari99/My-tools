# A1 - Actual manufacturing cost: audit + gap analysis (stage 1-2)

Branch `audit/a1`. Scope: is product cost computed correctly from recipe, raw-material use, wastage, labour and overhead?
No SQL or web code was changed. Only this file and `tests/sql/audit2/a1/` were added.

## 1. Method

- Final DB built from nothing with `tests/sql/final_build.sh a1db` (canonical order, `docs/PASTE_ORDER.md`, phase 72..111). Scratch Postgres 16, socket `/tmp`, port 5544.
- Function text below is the FINAL body (`pg_get_functiondef` of the built DB). `fn:NN` = line inside that dumped body. Phase numbers say where the logic came from.
- Scenarios: `tests/sql/audit2/a1/run.sh` (clones `a1db` to `a1s`, runs `s0..s6` in one psql session; reuses `tests/sql/e2e/00_common.sql`). Expected numbers are written as `HAND:` comments in each file BEFORE the run. Output of the last run: `tests/sql/audit2/a1/expected_run_output.txt` (85 asserts PASS, 11 FAIL; every FAIL is explained in section 3 - they are probes that confirm a gap, not test bugs).
- Two of my own hand numbers were wrong at first (a test-order artefact: GL not yet posted in S0; the cake average after the extra back-dated run in F0/F1). I corrected the expectation and noted why in the file. No product number was changed to fit.
- Money is in the shop currency (no symbol). No real names are used.

## 2. How the system builds product cost (read from code)

| Layer | What the code does | Where |
|---|---|---|
| 1 Raw material | Ingredients leave stock at the weighted average of the place (`stock_balance.avg_cost`). Need = recipe qty x batches x (1 + waste%/100), rounded 4 dp. Waste blank = 0 plus a yellow flag. | `_recipe_need:16`, `production_post:158-165` |
| 1b Today view | Last `purchase_in` unit cost of the item. Display only ("never booked"). | `_today_cost`, `recipe_cost:54,79-81` |
| 2 Conversion | Per location mode `off / recipe / pool` (`location_cost_cfg`). `recipe`: component rows per recipe (per_batch, per_unit on ACTUAL output, per_labour_hour = rate x hours_per_batch x batches). `pool`: monthly pool of the run month / NORMAL monthly output x actual output kg. | `_conv_cost:11-34` |
| 2b Packaging | (i) packaging as a recipe line (cost like any ingredient); (ii) `product_packaging` row with `applies_to=production` and global rule `packaging_consume_on=production`: qty_per_unit x PLANNED yield. `sale` mode = cost of sale, not of product. | `_recipe_need:23-26` |
| Booking | Ledger: finished good in at (material + conversion) / ACTUAL output (`production_post:174`). Journal: Dr 1310 material+conversion, Cr 1320/1330 material, Cr 5950 overhead absorbed. | `production_post:174-181`, `_acct_docs` production block |
| 3 Showroom/admin | Cost bill shares have dest `factory/showroom/admin`; only `factory` is pushed into pools, the rest is read by `branch_overhead`. | `_cs_push_pools:13`, `branch_overhead` |
| Month end | `overhead_trueup` = actual pool - absorbed (report only). | `overhead_trueup:11-23` |

## 3. Checks

Legend: PASS / FAIL / NS (not supported). Numbers = hand value vs system value, from `expected_run_output.txt`.

### (a) Recipe, waste %, yield loss (S1)

| # | Check | Result | Evidence |
|---|---|---|---|
| a1 | recipe_cost: flour 6 kg +10% waste, sugar 3, butter 2 +5%, box 2 pc, labour 2 h x 50, gas 2/kg | PASS | material 1500 = 264+180+1050+6; conversion 120; unit 162.000 (hand = system) `recipe_cost:46-81` |
| a2 | Production of 2 batches deducts waste-inflated quantities | PASS | flour 100-13.2=86.8, sugar 44, butter 15.8, box 196 `_recipe_need:16` |
| a3 | Actual yield 18.5 kg (theoretical 20): cost per kg on ACTUAL output | PASS | material 3000, conversion 237 (200 labour + 2x18.5 gas), unit 174.973 = 3237/18.5 `production_post:126,174` |
| a4 | Journal equals the run | PASS | Dr 1310 3237; Cr 1320 2988; Cr 1330 12; Cr 5950 237; no unbalanced entry `_acct_docs` production block |
| a5 | Over-yield (10.8 vs 10) lowers unit cost | PASS | 1621.6/10.8 = 150.148 |
| a6 | Yield variance stored as % | PASS | `yield_var_pct` -7.50, `yield_std` 20, `yield_actual` 18.5 `production_post:177-181` |
| a7 | Yield variance alert | PASS (opt-in) | exists (`production_post:195-199`) but rule `yield_variance_warn_pct` is NULL by default, so silent unless the owner sets it |
| a8 | Cost of the yield loss in money; standard-vs-actual cost | NS | `production_run_costs` has `yield_var_pct` only. Hand: 1.5 kg missing = 242.78 of extra cost, never shown. `std_cost` is NOT a standard: it is (actual material + actual conversion)/theoretical output (161.85), so it mixes actual spend with theoretical output |

### (b) Conversion cost: labour, gas, electricity, rent (S2)

| # | Check | Result | Evidence |
|---|---|---|---|
| b1 | Labour per hour / per batch / per unit in recipe mode | PASS | a1, a3 |
| b2 | Pool rate = pool / normal output; gas smoothing over months | PASS | labour 30, gas (6000+9000)/2/1000 = 7.5, electricity 4, rent 5 = 46.5/kg; run of 10 kg = 465; unit 196.5 `_pool_rate:11-23` |
| b3 | Allocation driver | NS (kg only) | Cake and a simpler sweet both get 46.5/kg (sweet unit 96.5) although labour needs differ. No driver by batches, labour hours or machine hours. `recipe_labour_suggest` is "suggestion_only" `_conv_cost:30` |
| b4 | Product measured in pieces in pool mode | FAIL | conversion = 0, unit 4.0 = material only; only a yellow flag `conversion_incomplete` (`_conv_cost:25`). Understates cost of every piece/litre product |
| b5 | Run dated before the month's pool is typed | FAIL | back-dated run: unit 150.0 = material only, `conversion_complete=false`, `conversion_detail=[]`; later typing of pools does not re-price it (B6/B7). Normal reality: bills arrive after production |
| b6 | Month-end true-up numbers | PASS | actual 45000 (labour 30000, gas 6000, elec 4000, rent 5000) - absorbed 1288.60 = unabsorbed 43711.40 (hand = system; recipe-mode and pool-mode runs are summed together) `overhead_trueup` |
| b7 | Unabsorbed/over-absorbed overhead is booked | NS | No journal at month end; 5950 stays at -1288.60. Under-absorption never reaches product cost or a P&L adjustment by itself (it is only a report) |
| b8 | Pool actual is tied to the real expense in the GL | FAIL | `pool_set` and `cost_bill_add` post nothing (expense accounts debit 0 apart from COGS). Cr 5950 can therefore exist with no matching Dr expense: profit is overstated unless the owner also enters the same cost as an expense/payroll. Double-keying risk is warned only for `allocated` bills (`pool_set:20-24`) |
| b9 | Layer 3 (showroom/admin) excluded from product cost | PASS | shared bill 10000: factory share 5000 -> pool of place 1; showroom 3000 -> `branch_overhead` only; place 6 factory 2000 |
| b10 | Labour tied to real attendance/payroll for the run | NS | `production_runs` has no hours/staff/payroll link (V5). Labour = typed rate or typed pool |

### (c) Multi-stage, by-products, packaging stage (S3)

| # | Check | Result | Evidence |
|---|---|---|---|
| c1 | Semi-finished (chhana) as ingredient of another recipe (sweet) | NS | chhana itself costs correctly (1600/3 = 533.333) but `recipe_save` refuses it: `bad_ingredient_type` (`_recipe_lines_ok:16` allows only raw_material, packaging, resale; `recipe_save:30` allows only finished_good as product). One item cannot be both |
| c2 | Workaround: typed-cost production-in of the semi-finished | FAIL | works, but `stock_production_in` consumes no milk: milk stays 180 ltr while Dr 1310 / Cr 5950 1599.99 books "overhead absorbed" (switch `acct_manual_prod_in103`). Inventory and profit are both overstated by the untouched inputs |
| c3 | By-products / co-products | NS | one `item_id` per `production_runs`, no output-lines table (S3 C3). No joint-cost split |
| c4 | Packaging added at packing stage inside product cost | PASS | pouch 1/kg, rule `production`: pouches 30 used, cost (1200+30)/27 = 45.556 |
| c5 | ... on actual output | FAIL (minor) | packaging uses PLANNED yield (30) although 27 kg came out: 3 pouches charged to 27 kg (`_recipe_need:23` uses `yb`) |
| c6 | Packaging basis for showroom pack/sale | PASS by design | `packaging_consume_on` is ONE global switch: a product is either packed at production (in product cost) or at sale (cost of sale); not both |

### (d) Price change, landed cost, returns (S4)

| # | Check | Result | Evidence |
|---|---|---|---|
| d1 | Weighted average after purchase | PASS | 70 kg@40 + 50 kg@52 = 45.000 |
| d2 | Next run uses the new average | PASS | 10 kg oil x 45 + 10 pouches = 460, unit 46.0 |
| d3 | "Today purchase price" view and gap | PASS | today unit 53.0, book 46.0, gap 15.22 % (hand = system) |
| d4 | Today price includes freight | FAIL (minor) | `_today_cost` reads invoice cost 52; landed price is 52 + 600/50 = 64. The gap % ignores freight |
| d5 | Landed freight into average | PASS | 110 kg: (4950+600)/110 = 50.4545 (`landed_post`: stock_added 600) |
| d6 | Runs made before the freight arrived are re-priced | NS | earlier run stays 46.0; FG already made keeps the old cost. Normal for average cost, but no report shows "freight that arrived after use" apart from landed_post |
| d7 | Raw-material return to supplier | PASS | out at current average (qty 105, avg unchanged 50.4545), supplier credit 260 vs 252.27 -> variance 7.73 (`_post_purchase_p13:79-81`) |
| d8 | Next run after freight and return | PASS | 10 x 50.4545 + 10 = 514.545 -> 51.4545 |

### (e) Partner-supplied material

| # | Check | Result | Evidence |
|---|---|---|---|
| e1 | Production with material owned by a partner/customer (job work, consignment) | NS | no owner/consignment column on `stock_balance`, `stock_ledger`, `production_runs`, `recipe_lines` (E1). `partner_*` tables are profit-share agreements (`partner_calculate`); `partner_capital.mode='in_kind'` exists but the journal skips it (`_acct_docs` partner_capital block: `mode <> 'in_kind'`), it creates no stock and no cost layer |

### (f) Reports == journal == stock ledger (S5)

| # | Check | Result | Evidence |
|---|---|---|---|
| f1 | Sale COGS: report = journal = ledger | PASS | 5 kg cake at average 168.8357 = 844.18 in `biz_daily`, journal 5000 and `stock_ledger`; `profit_source_check` agree = true |
| f2 | Every costed run: run cost = ledger production_in value = journal Dr 1310 | PASS | summed absolute difference 0.00 (all costed runs) |
| f3 | `inventory_vs_gl` | PASS | unexplained 0.00; the only difference is explained (`purchase_return_variance` -7.73) |
| f4 | Second cost source `item_costs` | PASS (design) | default `report_cost_source = ledger_then_item_costs`; forcing `item_costs` gives COGS 600 vs journal 844.18 and `profit_source_check` says "not agree" (honest, but a switch that can split reports from books) |
| f5 | Ingredient with unknown cost | FAIL | run books partial cost: Dr 1310 300 (sugar only), `cogs_missing`, FG avg NULL. Owner then supplies RM cost 20 via `cost_wait_supply96`: it goes to overlay `ledger_cost_supply96`, `stock_balance.avg_cost` stays NULL, the production run is NOT on the cost-waiting list (only the opening row is), the old run stays uncosted, and a NEW run is again booked at 300. Hand value for the new run: 5x20+5x60 = 400 |
| f6 | Free-cost flag (phase80) | PASS | item flagged free: run unit cost 30.0, `cost_complete=true`; unflagged stays unknown |
| f7 | Recipe versions and approval gate | PASS | copy = version 2; with `recipe_approval_required=on` unapproved version refused (`recipe_not_approved`); approved recipe cannot be edited (`recipe_approved`); owner self-approval allowed and logged (`recipe_approve` bos87) |
| f8 | Cost history of the recipe standard per version | NS | no stored standard on `recipes`/`recipe_lines` (V4); `recipe_cost` always recomputes with today's average, so an old version cannot be compared to what it cost then |

### Totals (41 rows)
- PASS 25 (a1-a7, b1, b2, b6, b9, c4, c6, d1, d2, d3, d5, d7, d8, f1, f2, f3, f4, f6, f7; a7 is opt-in, c6 and f4 are by design)
- FAIL 7 (b4, b5, b8, c2, c5, d4, f5)
- NOT SUPPORTED 9 (a8, b3, b7, b10, c1, c3, d6, e1, f8)

## 4. Gap analysis

Severity: H = money/profit wrong or decision wrong today; M = wrong in common cases; L = cosmetic or rare.
Effort: S < 1 day, M = days, L = weeks.

| G | Gap | Impact on the real business | Sev | Evidence | Fix outline | Eff | Depends |
|---|---|---|---|---|---|---|---|
| G1 | Semi-finished goods cannot be an ingredient (chhana -> sweet, dough -> biscuit) | Multi-stage products are costed by hand or not at all; the typed-cost workaround overstates inventory and profit (c2). Decision: sweet price set on a guessed chhana cost | H | c1, c2 | Allow finished_good (flag `semi_finished`) in `_recipe_lines_ok`; `_recipe_need` already reads `stock_balance`, so avg cost of the semi flows; block cycles; show stage cost split in `recipe_cost` | M | none; re-test `recipe_copy`, `production_can_make` |
| G2 | Pool/cost bills are memos, not postings; Cr 5950 has no guaranteed Dr expense | If the owner types a pool but not the expense (or vice versa) profit is wrong by the pool amount; no check that pool = GL expense | H | b8, L2 | Link pool rows to expense/payroll journal sums (reconcile report `pool_vs_gl`), warn when 5950 credit exceeds expenses of the month; or let `cost_bill_add` post Dr expense | M | phase75 cost sources, accounting module |
| G3 | Unabsorbed/over-absorbed overhead not booked and not repriced; month-end true-up is a report | Product cost is wrong in a low-output month (fixed cost per kg too low or too high); stock carries the estimate forever; P&L view of overhead is split between 5950 and expenses | H | b6, b7, b5 | Month-close step: post variance (Dr/Cr 5950 vs expense or cost-of-sales); option to reprice runs of the month with actual pool / actual output (needs the run to stay open until close) | L | G2, period lock |
| G4 | Runs made before the month's pool exists book conversion 0 | Early-month production is cheaper in books than reality; sold at a thin margin without knowing | H | b5, B7 | Use last complete month's rate as provisional (flag), then month-close true-up (G3); at least list runs with `conversion_complete=false` as a work queue | M | G3 |
| G5 | Overhead driver is output kg only; no batches, labour hours or machine hours; one global `normal_monthly_output` per place | Labour-heavy sweets are under-costed and simple items over-costed; wrong margin ranking of products | M | b3 | Add driver choice per cost type (kg / batches / labour hours) using `recipe_cost_components.hours_per_batch`; normal output per month and per product group | M | none |
| G6 | Pool mode ignores non-kg products (pc, ltr) | Piece-sold items (samosa, snack boxes) carry material only | M | b4 | Use base unit weight conversion or per-batch driver (G5) instead of the `pool_unit_not_kg` stop | S | G5 |
| G7 | Unknown-cost ingredient: supplied cost does not reach the item average or the old/new runs; production not on the cost-wait list | Finished good stays with NULL cost; sales of it have no COGS; GL carries a partial cost silently (`cogs_missing`) | H | f5 | Make `cost_wait_supply96` also write `stock_balance.avg_cost` (or re-cost dependants through the overlay); list `production` rows in `_cw_docs96`; default `production_requires_cost=refuse` once data is clean | M | phase96/103 overlay |
| G8 | No standard-vs-actual cost report: no price/usage/yield/conversion variance, no money value of yield loss; `std_cost` is mislabelled | Owner cannot see "why did the cake cost go up": price, waste, yield or overhead | H | a8, V4, f8 | Store standard (recipe_cost at approval/version) per version; report per run: price var, usage var, yield var (money), conversion var; rename `std_cost` | M | G3 for conversion variance |
| G9 | No by-product/co-product output | Joint products (whey, cream, skim milk, trimmings) get zero cost or are lost from stock | M | c3 | `production_outputs` table with cost-share method (market value / weight); first support "by-product credit" | L | G1 |
| G10 | Packaging consumed on planned yield | Packaging cost per kg off by planned/actual ratio; stock of packaging drifts | L | c5 | Use actual output when `p_actual_yield` is given (or ask packed qty) | S | none |
| G11 | `packaging_consume_on` is global, not per product | Cannot pack cakes at production and sweets at sale | M | c6 | Move the choice to `product_packaging.applies_to` only | S | none |
| G12 | Labour not tied to production (no hours, workers, payroll) | Labour is a typed rate; real overtime/idle time never appears in cost | M | b10, V5 | Optional worker-hours entry on a run; labour pool from payroll by hours | L | payroll module |
| G13 | Today-price view excludes freight; gap % ignores landed cost | "Today cost" understates replacement cost by freight share (12 per kg in the test) | L | d4 | `_today_cost` = invoice cost + landed share of the last posted landed doc | S | phase97 |
| G14 | Partner/customer-supplied material (job work, consignment) not modelled | Cannot cost contract manufacturing or a partner who brings milk; in-kind capital skipped by the journal | M | e1 | `stock_owner` on ledger rows, zero-cost or memo valuation, fee-only product cost; reuse `partner_*` | L | G1, accounting design |
| G15 | Yield-variance alert and waste-required rules are OFF by default | Yield loss goes silent; blank waste counts as 0 | L | a7, A6 | Recommend defaults through setup advisor (`setup_recommendations`) | S | none |
| G16 | `report_cost_source=item_costs` can split reports from books | If someone sets it, margin reports differ from the journal (profit_source_check shows it) | L | f4 | Keep, but show a banner on margin reports when the mode is not ledger | S | none |

## 5. What the system cannot do today (summary)

1. Use a semi-finished product as an ingredient (multi-stage costing).
2. Show standard vs actual cost, or price / usage / yield variance in money.
3. Re-price production when the month's labour, gas, electricity or rent is known; post the unabsorbed overhead.
4. Allocate overhead by anything except output kg; cost piece/litre products in pool mode.
5. Tie labour to attendance, hours or payroll of a run (`recipe_labour_suggest` is suggestion only).
6. Keep an overhead pool honest against the GL expense (pool is a memo; no `pool vs expense` check).
7. Costing of by-products and co-products.
8. Material owned by a partner or customer.
9. Restate a finished good after raw-material freight or a late cost arrives (average-cost limitation; landed cost only affects stock on hand).
10. Keep a history of the recipe standard cost per version.

## 6. What works well (keep)

- Weighted-average layer 1 is correct, consistent between recipe_cost, run, ledger and journal (f1-f3, zero difference over all costed runs).
- Waste % and actual yield are in the cost; booking per kg is on actual output.
- Layer 3 (showroom/admin) is kept out of product cost by design and is visible per branch.
- Approved recipes are frozen; versions and approval gate work; free-cost flag and cost-wait list prevent silent zeros in the common cases.
- Landed cost and supplier returns keep the average honest and reconcile in `inventory_vs_gl`.

## 7. Assumptions and limits

- Single place (id 1) for production; place 6 only for the cost-bill split. Day of test: current date of the scratch DB.
- "Normal monthly output" 1000 kg is a test input, not a recommendation.
- Concurrency (`production_post` row locks, phase109) and permissions were not re-tested here.
- Existing e2e files (`tests/sql/e2e/04_production.sql`) already cover refuse-mode `production_requires_cost` and recipe_cost == posted cost at theoretical yield; not repeated.
- Priority and implementation order (stage 3-4) is left to the next stage; suggested first group: G7, G1, G2, G8, G4/G3.
