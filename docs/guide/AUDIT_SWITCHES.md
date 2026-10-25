# Audit switches 112 to 118 - plain-English guide

This page lists every new rule (switch) added by phases 112 to 118. It is written for the owner.

**Read this first:**
- Every switch starts OFF. OFF means the app works exactly as before.
- Turn on one switch at a time. Wait one day, check the report named in the order table, then go on.
- Do not turn on two switches on the same day.
- Turn a switch on or off in the switchboard (`#/switchboard`).
- Some switches are not on/off. They are text settings (the last two rows). Leave them at their default unless you need to change them.
- The setup advisor (`#/setupadvisor`) may show a recommended value for some of these. A recommendation is not applied until you press Apply. Follow the order in this page, not the advisor's order.

**Risk levels:**
- **Low**: changes a report or shows a warning. No entry is posted and no stock moves.
- **Medium**: changes a number that feeds costs, stock or reports, or writes entries that can be reversed.
- **High**: can block daily work, or writes ledger entries that are hard to undo.

**Gap ids** point to the audit documents in `docs/audit2/`: A1 manufacturing cost, A2 sales and stock, A3 real profit, A4 cash and reconciliation, A5 factory and branch. The gap ids are the ones named in each phase's header.

---

## 1. The switches

### Phase 112 - one true profit figure

| Rule name | Default | What it changes, in simple words | Risk | Gap closed | How to turn off |
|---|---|---|---|---|---|
| `profit_truth_mode` | off | The shop P&L and the dashboard "Net profit" tile show one profit figure. It takes off wastage, card fees, salary (paper sheet or payroll app, not both), fixed cost and shared bills. Sales with unknown cost are shown apart and the figure is marked provisional. Books are not changed. | Medium | A3 G1, G2, G3, G4, G5, G6, G7 | Set to off |
| `cost_share_prorate_mode` | off | A monthly shared bill is counted by the days in the report range. A one-day report shows 1/30 of a 30-day month's bill, not the whole bill. Full-month reports do not change. | Low | A3 G8 | Set to off |
| `items_net_of_returns` | off | Top items and category reports subtract returned money, quantity and cost. Works only while `reports_net_of_returns` is on. | Low | A3 G9 | Set to off |

### Phase 113 - books and cash truth

| Rule name | Default | What it changes, in simple words | Risk | Gap closed | How to turn off |
|---|---|---|---|---|---|
| `drawer_short_post` | off | A cash count (form 14-1) that is short or over is posted as "Cash short / over" (account 5800) and shows in the day book. A form that stops being final is reversed. | Medium | A4 G01 | Set to off |
| `dues_net_advance` | off | The dues list and the collection screen leave out advance money already used on a bill. A bill paid from advance cannot be collected a second time. | Medium | A4 G03 | Set to off |
| `period_lock_owner_mode` | off | The owner can still change a closed period, but a yellow warning `closed_period_owner` is written (once per date and day). Other users are still refused. Value to turn on: `warn`. | Low | A4 G04 | Set to off |
| `period_lock_late_warn` | off | When the scheduler skips documents because their date is in a closed period, a yellow warning `late_docs_locked` is written. The documents stay unbooked, as before. | Low | A4 G04 | Set to off |
| `daybook_align_mode` | off | The day book shows a 10-2 voucher paid by bank or mobile with that mode (today it always shows cash). The card fee of a card settlement shows on the bank side. | Low | A4 G05 | Set to off |
| `bank_stmt_post_on` | off | In bank reconciliation, an unmatched statement line can be posted in one step as "fee" or "interest", and matched. Needs `bank_recon_on` to be on. | Medium | A4 G08 | Set to off |

### Phase 114 - stock safety, part 1

| Rule name | Default | What it changes, in simple words | Risk | Gap closed | How to turn off |
|---|---|---|---|---|---|
| `late_sale_follows_block` | off (false) | A sale that arrives online with an old sale time is no longer treated as a late offline sync. The "block when stock is negative" rule applies to it. A real offline-queue replay is not affected. | Medium | A2 G3 | Set to false |
| `transfer_needs_stock` | off (false) | A transfer cannot send more than the sender holds. The owner's override (sell_below_zero permission or emergency approval) still works. Also stops negative stock on send. | Medium | A2 G6; also A5 GAP-8 | Set to false |
| `return_uses_sale_rows` | off (false) | A sale return puts stock back using the rows the sale took out, not today's unit factor. A factor changed after the sale no longer moves the book. | Medium | A2 G5 | Set to false |
| `item_unit_change_needs_zero` | off (false) | The base unit of an item cannot be changed while stock is on hand. | Low | A2 G5 | Set to false |
| `item_lifecycle_needs_zero` | off (false) | An item cannot be set to "not tracked" or inactive while stock is on hand. | Low | A2 G9 | Set to false |
| `batch_for_adjustments` | off (false) | A stock count gain and opening stock get an adjustment batch (no expiry), so expiry and FEFO lists see the stock. | Medium | A2 G8 | Set to false |
| `batch_refill_cap` | off (false) | A new batch that refills a negative balance keeps only the part really on hand. Example: balance -2, batch 10, kept batch 8. | Medium | A2 G8 | Set to false |

### Phase 115 - factory to branch transfers

| Rule name | Default | What it changes, in simple words | Risk | Gap closed | How to turn off |
|---|---|---|---|---|---|
| `transfer_late_receive` | off (false) | A short receipt can be completed later. The missing part comes in on a second delivery, at the sent cost, in the same batch. Not possible if the shortage was already written off or booked. | Medium | A5 GAP-2 | Set to false |
| `transfer_return_marker` | off (false) | Goods sent back to the factory are a marked return: they have a reason (damaged, expired, excess, wrong item, other) and a link to the original transfer. | Low | A5 GAP-3 | Set to false |
| `transfer_notify_receiver` | off (false) | When goods are sent, the managers of the receiving place get one notification per transfer. | Low | A5 GAP-6 | Set to false |
| `transit_loss_gl_fix` | off (false) | Transit loss no longer leaves a phantom stock line in the books, and the transit-loss entry is no longer stuck on "cost missing". Wrong entries already posted are not rewritten. | High | A5 GAP-4 | Set to false. Old posted entries stay. |

### Phase 116 - manufacturing cost engine

| Rule name | Default | What it changes, in simple words | Risk | Gap closed | How to turn off |
|---|---|---|---|---|---|
| `semi_finished_ingredient116` | off (false) | A finished item (for example chhana or dough) can be an ingredient of another recipe. A recipe that loops back on itself is refused (`recipe_cycle`). | High | A1 G1 | Set to false |
| `packaging_on_actual_yield116` | off (false) | Packaging is used and costed for the quantity really made, not the planned yield. | Medium | A1 G10 | Set to false |
| `std_snapshot_auto116` | off (false) | The first run of a recipe at a place stores a standard cost (recipe quantities times that day's prices). It stores only; it does not change the cost you see. | Low | A1 G8 | Set to false |
| `std_cost_true116` | off (false) | A production run's standard cost per unit is the stored standard. The old number is kept in `cost_full_yield116`. | Medium | A1 G8 | Set to false |
| `pool_drivers116` | off (false) | Overhead can be shared out by output kg, output units, batches or labour hours, per place and per cost type. | Medium | A1 G5, G6 | Set to false |
| `conv_provisional116` | off (false) | A run made in a month that has no overhead pool yet uses the last month (up to 6 months back) that has one. The run is marked PROVISIONAL. | Medium | A1 G4 | Set to false |
| `cost_supply_to_avg116` | off (false) | A cost supplied through the cost-waiting list also moves the stock average cost, and the run is re-costed. | High | A1 G7 | Set to false |

### Phase 117 - factory overhead reaches the books

| Rule name | Default | What it changes, in simple words | Risk | Gap closed | How to turn off |
|---|---|---|---|---|---|
| `pool_gl_post117` | off (false) | Each overhead pool row is posted to the books as an expense (Dr expense, Cr 2400 accrued expenses), dated the last day of the month. A retired pool row is reversed. **Turn on only if the same factory costs are NOT also entered as expenses, payroll or bills. Otherwise they are counted twice.** | High | A1 G2 (report side: G3) | Set to false. A posted row is reversed only when it is retired. |
| `factory_labour_absorbed117` | off (false) | The branch P&L leaves out the factory salary that is already absorbed into product cost, so it is not counted twice. Example: salary 200, absorbed 200, shows 0. | Medium | A3 gap 5 (the B3 report also calls it G10) | Set to false |

### Phase 118 - reports and two text settings

Phase 118 also adds three read-only reports (stock reconciliation, factory-branch statement, net profit report). They have no switch. They are controlled by view rights, not by a rule.

| Rule name | Default | What it changes, in simple words | Risk | Gap closed | How to turn off |
|---|---|---|---|---|---|
| `profit_variable_heads` | `"transport"` (text, not on/off) | Which expense heads count as variable selling cost inside the contribution margin. | Low | A3 G13, C19, C20 (report) | Set back to `"transport"` |
| `branch_stmt_ageing_hours` | `"24,72"` (text, not on/off) | The age bands, in hours, for goods in transit on the factory-branch statement: 0 to 24 hours, 1 to 3 days, over 3 days. | Low | A5 GAP-1 | Set back to `"24,72"` |

---

## 2. Recommended order to turn on

Turn on one row. Use the value in "Turn on as". Then watch the report for one full day before the next row. If anything looks wrong, turn that row back off, and send a screenshot.

**Stage 1 - warnings and reports only (low risk)**

| Step | Rule name | Turn on as | Watch this report for a day |
|---|---|---|---|
| 1 | `period_lock_late_warn` | on | Yellow warnings list: look for `late_docs_locked`. Scheduler status in `#/books85`. |
| 2 | `period_lock_owner_mode` | warn | Yellow warnings list: look for `closed_period_owner`. |
| 3 | `daybook_align_mode` | on | Day book against the journal (the `daybook_vs_journal` check). |
| 4 | `cost_share_prorate_mode` | on | Shop P&L for a one-day range and for a full month. |
| 5 | `items_net_of_returns` | on (also needs `reports_net_of_returns` on) | Top items and category reports on a day with returns. |
| 6 | `std_snapshot_auto116` | on | Production run costs: they should look the same as before. |
| 7 | `transfer_notify_receiver` | on | Receiving managers get one notice per transfer. |
| 8 | `transfer_return_marker` | on | Factory-branch statement: returns show their reason. |
| 9 | `item_unit_change_needs_zero` | on | Stock reconciliation statement: no item changed while stock is on hand. |
| 10 | `item_lifecycle_needs_zero` | on | Stock reconciliation statement: same check as step 9. |

**Stage 2 - report numbers change (medium risk)**

| Step | Rule name | Turn on as | Watch this report for a day |
|---|---|---|---|
| 11 | `profit_truth_mode` | on | Shop P&L and the dashboard "Net profit" tile. Both must show the same figure. Compare with yesterday. |
| 12 | `factory_labour_absorbed117` | on | Branch P&L: the factory salary line is lower by the absorbed labour. |
| 13 | `packaging_on_actual_yield116` | on | Packaging stock after a production that made less than planned. |
| 14 | `std_cost_true116` | on | Production run costs. The old number is still kept in `cost_full_yield116`. |
| 15 | `pool_drivers116` | on | Overhead per unit in production runs, per place. |
| 16 | `conv_provisional116` | on | Runs marked PROVISIONAL. Count them each day. |

**Stage 3 - stock flow (medium risk)**

| Step | Rule name | Turn on as | Watch this report for a day |
|---|---|---|---|
| 17 | `batch_for_adjustments` | on | Stock reconciliation statement and expiry lists. |
| 18 | `batch_refill_cap` | on | Stock reconciliation statement (batch totals match balances). |
| 19 | `return_uses_sale_rows` | on | Stock reconciliation statement after returns. |
| 20 | `late_sale_follows_block` | on | Stock reconciliation statement: sales that did not leave stock. Also refused sales. |
| 21 | `transfer_late_receive` | on | Factory-branch statement: short and in-transit quantities. |
| 22 | `transfer_needs_stock` | on | Factory-branch statement, and any transfers refused. |

**Stage 4 - money posted to the books or cost flow (medium to high risk)**

| Step | Rule name | Turn on as | Watch this report for a day |
|---|---|---|---|
| 23 | `dues_net_advance` | on | Customer dues list against bills paid from advance. |
| 24 | `drawer_short_post` | on | Day book "Cash short / over" row after each cash count. |
| 25 | `bank_stmt_post_on` | on (needs `bank_recon_on` on) | Bank reconciliation, and the trial balance in `#/accounts`. |
| 26 | `transit_loss_gl_fix` | on | Trial balance in `#/accounts` (balanced). |
| 27 | `cost_supply_to_avg116` | on | Cost-waiting list (`#/books96`) and the stock average cost. |
| 28 | `semi_finished_ingredient116` | on | Stock of semi-finished items and production runs. |
| 29 | `pool_gl_post117` | on | Trial balance in `#/accounts`, and the `pool_vs_gl117` check. **Last step. Only after you confirmed there is no double count.** |

**Optional (text settings, not on/off):** `profit_variable_heads` and `branch_stmt_ageing_hours`. Change them only if the owner wants different expense heads or age bands.

---

## 3. How to turn off

- Turning a switch off stops its new effects. Entries already written stay, unless the row above says otherwise.
- `drawer_short_post`: a form that stops being final is reversed.
- `pool_gl_post117`: a posted pool row is reversed only when that row is retired.
- `transit_loss_gl_fix`: wrong entries already posted are not rewritten, so turning it off does not fix them. Check the trial balance in `#/accounts` after turning it off.
- `std_cost_true116`: the old standard cost is still in `cost_full_yield116`.
- If you turned several switches on, turn them off in the reverse order of the table above.
- After any change, check `#/accounts` (trial balance balanced) and `#/setupadvisor` (no `not_installed` rows).

## 4. Notes for the owner

- Test on a test item and a test name (for example `01XXXXXXXXX`) before you use real bills.
- Phase 112 and phase 113 add advisor rows with recommended values. Those values are advice only. Press Apply only when you have read the row in this page.
- Gap ids are as named in each phase's header. A3 "gap 5" is written as G10 in the B3 report. Check `docs/audit2/A3_real_profit.md` before you rely on either label.

## 5. Sources

- Phase 112: branch `origin/impl/b1`, `supabase/phase112.sql`
- Phase 113: branch `origin/impl/b1`, `supabase/phase113.sql`
- Phase 114: branch `origin/impl/b2`, `supabase/phase114.sql`
- Phase 115: branch `origin/impl/b2`, `supabase/phase115.sql`
- Phase 116: branch `origin/impl/b3`, `supabase/phase116.sql`
- Phase 117: branch `origin/impl/b3`, `supabase/phase117.sql`
- Phase 118: branch `origin/impl/b4`, `supabase/phase118.sql`
- Batch 3 summary: `docs/audit2/B3_REPORT.md` on `origin/impl/b3`
