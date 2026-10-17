# Integration notes: Package RPT-C1 (reports honesty, expense register, statements)

Source: `docs/REPORTS_AUDIT_3.md` findings F1 to F5, F9, F10, F12, F14 and reports #114, #115, #121, #124, #126. Phases 440 to 444 only; all new files, paste-twice safe (tested), nothing in an older phase file edited.
Paste order: after phase 99 (and after every other package that patches the same functions, see the hazard list). Order: 440, 441, 442, 443, 444. Not added to `tests/sql/ORDER.txt` (that file is the Wave 1 order up to phase 99; the integrator appends 440 to 444 when the packages are merged).
Owner rules kept: reports stay open (no capture switch is needed to read); "data not captured" instead of 0; nothing invented (every cut-off is a setting, every class is blank until the owner sets it); an existing figure changes only behind a setting whose default is today, plus added columns / notices / basis lines.

## 1. Files

| File | What |
|---|---|
| `supabase/phase440.sql` (+ `_test`) | helper `_c1_patch`, null-safe engine 3 totals, L1/L3 `profit_complete` + setting, notices (`report_notes`) |
| `supabase/phase441.sql` (+ `_test`) | attendance from both sources, compliance start date + closed days, RFM / lapsed cut-offs as settings, cash short by case status |
| `supabase/phase442.sql` (+ `_test`) | `expense_register()` |
| `supabase/phase443.sql` (+ `_test`) | `coa_report_class`, `coa_class_list/set/apply_suggested`, `stmt_pl_matrix`, `stmt_pl_drill` |
| `supabase/phase444.sql` (+ `_test`) | `stmt_cash_flow`, `stmt_cf_drill`, `stmt_working_capital`, `c1_export_log`, setting `report_cf_opening_through` |
| `web/reportnotes.js` | `B.reportnotes` (notices) and `B.c1` (CSV helpers, export gate) |
| `web/expenseregister.js`, `web/statements.js` | the two screens (`#/expenseregister`, `#/statements`) |
| `tests/sql/c1_fixture.sql`, `c1_before_after.sh`; `tests/web/c1_test.js` | fixture (hand-computed numbers in its header), default-settings proof, headless 360px test |
| `docs/integration/RPT-C1_info.json` | the (i) info entries |

## 2. Patched functions (exact-text patch of the live definition by `_c1_patch`; a missing or doubled site STOPS the paste; the marker makes the second paste a no-op)

| Function | Marker | Change |
|---|---|---|
| `report_run3(text,jsonb,text,text,integer)` | bos440 | a total over a column in which no row has a value is null (not captured), not 0 |
| `_r3q_l1_pnl`, `_r3q_l3_shop_pnl` | bos440 | new key `profit_complete`; profit null when a part is missing only while `report_profit_blank_on` is ON (default OFF = today) |
| `_r3q_m1_rfm`, `_r3q_d5_lapsed` | bos441 | the built-in 3 / 30 / 60 / 180 become settings; blank = the built-in number |
| `report_run2_core(...)` | bos441a, bos441b | `attendance_summary` reads `attendance_days` plus paper 02-1 in separate rows (column `source`); `cash_short_over` can follow the shortage case status (setting, default OFF) |
| `_r3q_x4_compliance(date,date,integer[],jsonb)` | (replaced as a whole) | rollout start date + closed days; the paste STOPS if the live function is neither the original nor already this version |

Re-paste hazard: re-pasting phase 21, 24, 25, 26, 27, 72, 76 to 79 (or W1-D 92 / 93) removes the markers: paste 440 and 441 again. `report_run2_core` is also patched by W1-D (bos93) and may be by other packages; 441 patches its own sites only and stops if one is missing.
Not touched: engine-1 sales functions (another package adds returns columns there). The returns line for the hub sales reports is a notice (`report_notes` topic `returns_line`), so it does not depend on those functions.

## 3. Hook sites in shared files (small, all in existing files; everything degrades silently on a database without the phases)

`web/reports.js` (4 places, all marked `RPT-C1`):
1. `run()`: after `V.res = res;` a call `loadNotes(tok)` (new function above "result drawing"): asks `B.reportnotes.load(key, filters, columns)` and redraws when the notices arrive. `V.cn` is reset with the rows.
2. `drawRes()`: `${cnH}` (the notices) right after the server notes.
3. `drawRes()` totals row: a measure total that is `null` shows "Not captured" (was an empty cell).
4. `buildCSV()`: a `null` total is written as `not captured`; the notices (with their basis lines) are appended after the meta lines.
`web/costing.js`: a `#cs_gaps` block under the recipe list (`loadGaps`, `gapCsv`): the screen for `d_recipe_cost_gaps`.
`web/ownerboard.js` (balance_check): `rpc('balance_sheet')` (never existed) became `rpc('acct_balance_sheet', {p_as_of: env.td})`; `data_needed` shows the empty state.
`web/index.html`: after `profitcheck.js`: `reportnotes.js`, `expenseregister.js`, `statements.js` (they need `B.s2` from `stock2.js`, so they must come after it).
`web/ia.js`: two records in group `reports` (also listed under `acc`): `expenseregister` and `statements`. No route was removed or renamed. The menu entry is shown to the owner and to accounts view / manage; a person with only the expense or profit report right reaches the screen from the notice links of the hub reports, and the server decides every call either way.

## 4. Server surface

Browser-callable (all `security definer`, signed-in users only, rights checked inside): `report_notes`, `expense_register`, `coa_class_list`, `coa_class_set`, `coa_class_apply_suggested`, `stmt_pl_matrix`, `stmt_pl_drill`, `stmt_cash_flow`, `stmt_cf_drill`, `stmt_working_capital`, `c1_export_log`. Everything with an underscore is closed to browsers (tests prove it).
Rights: report notes = the right of the report itself; expense register = owner, expense report right or accounts view; statements = owner, accounts view / manage or the profit report right; class changes = owner or an accounts manager (`_w1d_mgr`); CSV = the owner or `export_data` plus the right to read that screen (`c1_export_log` writes the audit line and refuses otherwise). Places: the ones the person may see (an unassigned journal line is visible only to people who see all places, as in the books).
New table: `coa_report_class` (RLS on, select for the statement readers, no hard delete, every change in `audit_log`). A class is cleared by blanking it, never deleted.

## 5. Settings added (all blank or OFF = today's behaviour; each has a label and a hint in three modes)

`report_profit_blank_on`, `report_compliance_from`, `report_compliance_closed_days`, `report_rfm_min_orders`, `report_rfm_recent_days`, `report_rfm_atrisk_days`, `report_lapsed_days`, `report_cash_short_by_case_on`, `report_cf_opening_through`. The (i) texts are in `RPT-C1_info.json`.

## 6. Proof

- `tests/sql/c1_before_after.sh`: 33 existing snapshots (profit, break-even, expenses, partner, brand P&L, income statement, balance sheet, trial balance, day book, ...) identical before and after phases 440 to 444 with every setting at its default; the only differences are the new key `profit_complete` on L1 / L3 (checked to be the only difference); pasting twice changes nothing; the pastes write no journal entry.
- SQL tests `phase440_test.sql` to `phase444_test.sql`, web test `tests/web/c1_test.js` (360 px, three language modes, CSV, drill-down, refusals, old-database behaviour).
- Cash-flow statement: opening + flows + opening journals in the period = closing, and the closing equals `acct_cash_flow` of the Cash flow tab. P&L matrix grand total equals `acct_income_statement` net profit. Expense register totals equal `expense_by_head`, `_p27_pl` and the existing `report_parity`.

## 7. Not done / decisions left to the owner

- Loans and VAT are not part of the statements (owner instruction). Working capital by class stays "not captured" until accounts are classed.
- Marketing (18-1) is listed as "not in the books" in the expense register; posting it to the journal is a separate owner decision (audit F8).
- The reads that are still gated by a capture switch (`day_book` for non-owners, `vat_report`, bank import, online orders; audit F11) are not changed here; the new screens do not depend on any.
- Screen labels of the new screens are English only, following the Profit check precedent (English labels only on report screens; confirm with the owner); the notices from the server come in Bangla and English.
