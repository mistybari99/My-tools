# Integration notes: Package W1-D (U-05 one profit number, U-06 report parity and dated brand map)

Branch files: `supabase/phase92.sql`, `supabase/phase93.sql`, `supabase/phase92_test.sql`, `supabase/phase93_test.sql`, `web/profitcheck.js`, `tests/web/profitcheck_test.js`,
`tests/sql/w1d_fixture.sql`, `tests/sql/w1d_snap_setup.sql`, `tests/sql/w1d_snap.sql`, `tests/sql/w1d_before_after.sh`, this file.
No existing file was edited. Paste order: after phase87 and after every other Wave 1 phase (88 to 91, 94 to 98): 92, then 93. Both are paste-twice safe (tested). All new functions use the prefix `_w1d_`.

## 1. What is patched (exact-text patch of the live definition, helper `_w1d_patch(fn, marker, pairs)`; a missing site STOPS the paste; the marker makes the second paste a no-op)

| Function | Marker | Phase | Change |
|---|---|---|---|
| `_p27_pl(date,date,int[])` | bos92 | 92 | one more `union all` in the expenses: `select x.m, x.loc, x.amt from public._w1d_pl_extra(d1, d2, locs) x` (zero rows while `profit_one_number_on` is off) |
| `_p27_pl` | bos93 | 93 | 10-2 status test becomes `public._w1d_exp_status_ok(e.status, 'pl')`; salary: the 02-2 sheet is the fallback only where no counted run exists (setting `report_salary_source`), runs are read when accrual is on OR the source is `app_first` |
| `partner_calculate(bigint,date,date,jsonb)` | bos92 | 92 | variable `lj`; ledger source (only master ON + `profit_source = ledger`); returns `profit_basis` (stored in `partner_settlements.calc`) |
| `c_partner_month_split(date)` | bos92 | 92 | the preview base uses the same management profit as the settlement while the master is ON and the source is management; basis text |
| `report_run2_core(...)` | bos93 | 93 | `expense_by_head`: status rule, shadow vouchers out and quick expenses in while `report_expense_parity_on` |
| `_r3q_e3_weak_control`, `_r3q_e2_expense_trend` | bos93 | 93 | status rule; E3 also drops shadows and gets a `quick` row while parity is on |
| `brand_pnl(date,date,text)` | bos93 | 93 | `left join lateral public._w1d_brand_at(d.location_id, d.sale_date) b on true` (off = today's map) |

`_p27_pl`, `partner_calculate` and `c_partner_month_split` are on the integrator list (plan 4.2) but U-05 names them and the package brief allows them: W1-D is the only Wave 1 package that touches them.
New table triggers: `report_brand_map_w1d` on `report_brand_map` (records every change of the map in `report_brand_map_hist`).

## 2. Hooks the integrator must run (one call, in the re-patch phase 99, after every older phase that re-creates these functions)

```sql
\i supabase/phase92.sql    -- re-patches _p27_pl, partner_calculate, c_partner_month_split (idempotent)
\i supabase/phase93.sql    -- re-patches _p27_pl, report_run2_core, E2, E3, brand_pnl (idempotent)
select public._w1d_hooks_apply();   -- day book and journal use the same voucher rule (exact text, marker bos93, stops if a site is missing, second call patches nothing)
```
`_w1d_hooks_apply()` patches two shared functions:

| Function | Old text | New text |
|---|---|---|
| `_daybook_lines(int[],int[],date,date)` | `e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)` | `e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'daybook') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)` |
| `_acct_docs(date)` (two sites, both replaced) | `e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */` | `e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'journal') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */` |

At the default `expense_count_on = as_today` the function answers exactly what those two sites did before (day book: submitted + approved, journal: approved only), proved by `w1d_before_after.sh` (hooks applied, 21 snapshots identical).
Without the hook, `expense_count_on = approved | submitted` changes only the P&L, E2, E3 and the expense report; the day book and the journal keep their own rule and `report_parity` shows the difference.
Re-paste hazard: re-pasting phase 13, 23, 27, 44, 50, 52, 72, 79, 82, 85, 86 or 87 removes the markers: paste 92 and 93 again and call the hook again. If another phase rewrites the two 10-2 lines the hook stops with `bos93 patch site not found` (it never half-patches).

## 3. Web registration (web/ia.js and web/index.html are the integrator's)

index.html, next to `wallets.js`: `<script src="profitcheck.js"></script>`

ia.js (group `reports`, one line):
```js
rec('profitcheck', 'reports', ['Profit check', 'Profit check', 'Profit check'], { icon: 'chart', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true,
  kw: ['profit', 'one profit number', 'loss', 'wastage', 'shortage', 'partner profit', 'reconcile', 'journal profit', 'brand', 'parity', 'expense report', 'salary'],
  verbs: ['compare profit', 'leave a loss out of profit', 'change brand'], aliases: ['profit check'] }),
```
(English labels only, owner rule.) If the icon `chart` does not exist use `money`. The server decides every right (`_w1d_view`, `_w1d_mgr`, owner only for settings and `brand_map_set`).

## 4. Settings added (rules, module reports, labels English only, every change written to audit_log by the existing rules trigger)

| Key | Default | Label | What it does |
|---|---|---|---|
| `profit_one_number_on` | OFF | One profit number: count losses in the profit | master: adds the rows below to the management profit; the partner preview then equals the settlement |
| `profit_losses_from` | blank | Count these extra profit rows from this date | blank = every date; not a date = ignored |
| `profit_loss_wastage`, `profit_loss_count`, `profit_loss_transit`, `profit_loss_cashshort`, `profit_loss_billopex`, `profit_overhead_once` | ON each (act only while the master is ON) | Profit counts wasted stock / stock count shortages / goods lost in transit / cash short and over / running costs paid by supplier bill / factory overhead once | one switch per row |
| `profit_source` | management | Partner shares take the profit from | management or ledger (journal); acts only while the master is ON |
| `report_salary_source` | legacy | Salary in the profit comes from | legacy (today) or app_first |
| `report_expense_parity_on` | OFF | Expense report counts quick expenses and skips shadow vouchers | expense report and E3 count what the P&L counts |
| `expense_count_on` | as_today | Expense vouchers count when they are | as_today / approved / submitted, one rule in P&L, reports, day book and journal (needs the hook for the last two) |
| `brand_map_dated_on` | OFF | Brand reports use the brand each place had on each day | off = today's map for every day |

Exceptions (rule 3): `profit_exclude(cause, source_id, reason)` leaves ONE loss out of the management profit (reason of 5+ letters, audit_log through the table trigger, one yellow line in the Exceptions list `profit_row_excluded`), `profit_exclusion_revoke(id, reason)` counts it again (yellow line `profit_row_exclusion_revoked`). `brand_map_set(place, code, bn, en, from, reason)`: a date in the past needs a reason and writes the yellow line `brand_map_backdated`; a future date is refused. Nothing is deleted anywhere (delete triggers on both new tables).
Owner approver is not touched (no approver in this package).

## 5. Tables and functions added

Tables: `profit_row_exclusions`, `report_brand_map_hist` (RLS on, browsers read only; written by the functions and the trigger).
Internal functions (closed to browsers): `_w1d_patch`, `_w1d_pl_rows`, `_w1d_pl_rows_on`, `_w1d_pl_extra`, `_w1d_cause_on`, `_w1d_losses_from`, `_w1d_mgmt_profit`, `_w1d_ledger_profit`, `_w1d_profit_override`, `_w1d_profit_basis`, `_w1d_split_base`, `_w1d_split_basis`, `_w1d_salary_app_first`, `_w1d_parity_on`, `_w1d_brand_open`, `_w1d_brand_trg`, `_w1d_brand_at`, `_w1d_hooks_apply`.
API: `profit_recon(from, to, place)`, `profit_exclude`, `profit_exclusion_revoke`, `profit_exclusions_list`, `report_parity(from, to, place)`, `brand_map_set`, `brand_map_hist_list`. `_w1d_view`, `_w1d_mgr`, `_w1d_exp_status_ok` are executable by signed-in users (policies and the day book call them).
No journal source is added and no journal entry is written by this package.

## 6. How each loss is counted (decision for the owner to confirm)

wastage = stock-ledger cost of `wastage` rows (cost 0 or empty = unknown, not guessed); count shortage = negative `count_adjust` rows at ledger cost (a surplus has no cost on its row and is not valued); transit loss = written-off events only (a claim to the carrier is a receivable); cash short = approved cases, short positive and over negative, a short booked as a staff receivable is 0; running cost by bill = the consumable and unclassified part of posted purchase bills (a purchase return is negative; stock and fixed-asset lines are not a cost); absorbed overhead = conversion cost of finished runs, subtracted from the expenses (it is already in the cost of goods).

## 7. Tests (local Postgres 16, port 5564, database built through phase87 then 92 and 93)

- `phase92_test.sql`: 75 pass, 0 fail. `phase93_test.sql`: 55 pass, 0 fail (each run on a fresh database; the data is `tests/sql/w1d_fixture.sql`, hand-computed numbers in its header).
- `tests/sql/w1d_before_after.sh`: with every setting at its default 21 snapshots (P&L, L1, L3, L4, L5, T4, E2, E3, expense report, partner calculation and preview, brand P&L, income statement, balance sheet, trial balance, cash flow, day book, day book versus journal, journal lines, posting dry run) are identical before and after phases 92 and 93 and the hook; a second wave of records gives the same reports with and without the phases; each setting changes only the figures it should and switching it off restores them.
- Older suites run on a database through 87 and on the same database with 92, 93 and the hook: the failing set is identical (list in the final report of the package).
- `tests/web/profitcheck_test.js`: 0 assert failures, no console errors (mocked RPCs; the script is injected because `index.html` is the integrator's).

## 8. Not done, not confirmed

- UNTESTED: the real integrator re-patch phase (the hook was tested by calling `_w1d_hooks_apply()` on a database through 87, not inside a phase 99); the screen on a real phone and against the real server; `#/profitcheck` in `ia_test`, nav, nav2, control, favsync and settings2 (the `rec` line is not added by this package); behaviour with a salary run that has advance recovery in `report_parity` beyond the unit fixture (no recovery).
- Not done: `salary_report` and `_r3q_t3_payroll` still read 02-2 sheets only; the brand filter of the report filters (`_r2_locs`) uses today's map; the ledger source feeds partner shares only (branch reports L1/L3 stay management); L1/L3 do not show the extra rows as separate lines (they are inside `expenses`; `profit_recon` and the screen show them by cause); count surplus is not valued; `profit_recon` needs the journal for the ledger side.
- OD-8 (owner decision): when to switch `profit_one_number_on` ON, from which date (`profit_losses_from`), and when to choose `profit_source = ledger` (plan: after phase 98 posts daily and two clean months agree).

## 9. BUILD-LOG entry for the integrator to paste (rule 16)

"phases 92, 93 (package W1-D): U-05 one profit number (settings, extra rows in _p27_pl, partner preview = settlement, basis stored on every settlement, profit_recon, exception path) and U-06 report parity (expense report and E3 parity, one voucher rule, salary source app_first, report_parity) and dated brand map (history table, brand_map_set, brand_pnl as of each day). All OFF by default; before/after snapshot identical. Patched by text with markers bos92 and bos93: _p27_pl, partner_calculate, c_partner_month_split, report_run2_core, _r3q_e3_weak_control, _r3q_e2_expense_trend, brand_pnl; hook _w1d_hooks_apply() patches _daybook_lines and _acct_docs. Not confirmed: real phase99 re-patch, phone, ia registration, salary_report/T3 parity."
