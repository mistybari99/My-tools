# B3 - Batch 3 "manufacturing cost" (phase116 + phase117)

Branch `impl/b3`. Source: `docs/audit2/A1_manufacturing_cost.md` (G1-G10) and `docs/audit2/A3_real_profit.md` (gap 5 / G10). Files: `supabase/phase116.sql`, `supabase/phase117.sql`, tests `supabase/phase116_test.sql`, `supabase/phase117_test.sql`, `supabase/phase89h_test.sql`. Registered in `docs/PASTE_ORDER.md` (rows 41-42, section N) and `tests/sql/paste_order.env` (appended after phase111). Backend only: no web file was changed (printed forms untouched).

Rules kept: only new additive files, paste twice = identical function bodies (checked with `tests/sql/fn_snapshot.sh`), every behaviour change behind a rules switch (default = today), setup advisor row for each switch (`setup_rec_defs81`, advisory, no value forced), cost tables closed to the browser (no SELECT grant, read through cost-right functions only), tags `bos116` / `bos117` on every re-created function with all older tags kept (`tests/sql/tag_loss_check.sh`: 0 lost).

## Switches (all default OFF)

| key | what it changes |
|---|---|
| `semi_finished_ingredient116` | a finished good (chhana, dough) may be an ingredient; production takes it out of stock at its average; cycles refused (`recipe_cycle`) |
| `packaging_on_actual_yield116` | packaging quantity and cost follow the quantity really made |
| `std_snapshot_auto116` | first run of a recipe at a place stores the standard (recipe qty x that day's average prices) in `recipe_std116` |
| `std_cost_true116` | `production_runs.std_cost` = stored standard per unit (old number always kept in `cost_full_yield116`) |
| `pool_drivers116` | pool overhead can be spread by output kg / output units / batches / labour hours, per place and per cost type |
| `conv_provisional116` | a run whose month has no pool at all uses the last month (up to 6 back) that has one, flagged PROVISIONAL |
| `cost_supply_to_avg116` | a cost supplied through the cost-waiting list also reaches `stock_balance.avg_cost` and re-costs the run |
| `pool_gl_post117` | each pool row is posted Dr expense / Cr 2400 accrued; retired rows are reversed |
| `factory_labour_absorbed117` | branch P&L takes the labour already absorbed into product cost out of the factory salary |

## Gaps fixed

| gap | fix | proof (hand numbers) |
|---|---|---|
| G1 semi-finished as ingredient | switch + cycle guard + `recipe_stage_cost116` | chhana 1600/3 = 533.333; sweet 2 kg chhana + 1 kg sugar = 1126.67 -> 375.556/kg; inventory vs GL diff 0 |
| G7 unknown-cost ingredient | `cost_wait_supply96` hook moves the average (ledger pair, reconcile-safe); `production_recost116` re-costs a run whose partial entry is already posted (reverse + re-post); `production_cost_queue116` lists such runs | old run 5x20 + 5x60 = 400 (unit 40), new run 400, partial entry 300 reversed |
| G2 / b8 pool vs books | `pool_gl_post117`, `pool_vs_gl117` | absorbed 270, expense in books 0 -> flagged; with the switch expense 5600 = 3500 + 2000 + 100, depreciation not posted, cost bill 600 posted and reversed on void |
| G3 unabsorbed overhead | with the pool in the books the unabsorbed part is an expense of the month; `overhead_trueup117` shows what reached the P&L | 5600 - 270 = 5330 |
| G4 early-month run | `conv_provisional116` + `production_cost_queue116` + `production_reprice116` (dry by default; stock average via `cost_adjust` ledger pair, one adjustment entry) | provisional 2 x 30 = 60, real pool 2 x 40 = 80, delta 20 to 1310 and 5950 |
| G5 / G6 drivers, piece products | `pool_drivers116`, `loc_cost_driver_set116`, `cost_type_driver_set116` | batches: 2 x 50 = 100 (unit 11); labour hours 15 + batches 40 = 55 (unit 8.75) |
| G8 standard vs actual | `recipe_std116`, `recipe_std_set116`, `production_variance116`, `production_run_costs` new keys; mislabelled `std_cost` fixed behind a switch | yield loss 3237 x 1.5/20 = 242.78; variance 240 = price 0 + usage 225 + conversion 15; flour price move 30.41 |
| G10 packaging | `packaging_on_actual_yield116` | pouches 30 -> 27, unit 45.5556 -> 45.4444 |
| A3 gap 5 | `factory_labour_absorbed117` in `_p27_pl` | salary 200 - absorbed 200 = 0; salary 300 -> 100 |

## Not done, and why

- Booking OVER-absorbed overhead back out of stock (true-up at month close): needs a re-rate on actual monthly output and an inventory write-down by lot; wrong sold/unsold split would misstate stock. The report side is done (`overhead_trueup117`); the under-absorbed side is handled by posting the pool.
- By-products / co-products (G9): needs an outputs table and a joint-cost split; not small.
- G11 (packaging switch per product), G12 (labour from attendance/payroll), G13 (freight in today price), G14 (partner material), G15, G16: out of the asked scope or large.
- Machine-hours driver: no machine-hour data exists anywhere; only kg / units / batches / labour hours (hours exist on the recipe).
- UI: no screen was changed (the new functions are callable; screens can follow).

## Known interplay (for the integrator)

- `phase109` guard: a re-paste of phase109 after phase116 REFUSES (production_post carries `bos116`). Nothing is destroyed; fix = teach phase109 to skip `production_post` when `bos116` is present (as INT4 did for `_bp_pay99`). Old phases were not edited in this batch. Baseline: `phase89g` 2 and `phase103c` 1 are false by design now; `phase89h_test` is the replacement (chain ends with 116, 117).
- Re-created here: `_recipe_lines_ok`, `_recipe_need` (now a thin wrapper of `_recipe_need116`), `production_post` (7 args), `_conv_cost`, `cost_wait_supply96`, `production_run_costs`, `production_void`, `pool_set`, `_cs_push_pools`, `_p27_pl`. Both files stop with a message if one of them carries a bosNN tag they do not know.
- A re-priced run cannot be voided (`run_repriced`); a past-date `inventory_vs_gl` replay stays consistent because the re-price moves the ledger and the books together.
- The setup advisor rows carry no recommended value for the switches that change books (the e2e `rec` mode applies every recommended value).
