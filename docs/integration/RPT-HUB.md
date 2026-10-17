# Integration note RPT-HUB: Business Memory (Reports hub, "what happened", Ask / Find, Spend finder)

Branch `rpt-hub`, base 47ba1e5. SQL phases **470-476** (all READ ONLY over business tables, paste-twice safe, no setting, no OFF switch, no route removed). Reports stay open to the roles that already hold the report rights; each answer is cut down to those rights on the server.

## 1. Files
| File | What |
|---|---|
| `supabase/phase470.sql` (+ `_test`, 24 checks) | table `rpthub_user_items` (favourites, recent, saved views, pins; RLS own rows only), ~27 date indexes, helpers `_rh_area_ok` / `_rh_locs` / `_rh_staff` / `_rh_ts`, `rpt_hub_perms()` |
| `supabase/phase471.sql` | `_rh_events` (one chronological event set: sales, voids, returns, collections, quick expenses, 10-2 vouchers, supplier payments/refunds, purchases, production, transfers, wastage, count adjustments, cash moves/short, other income, paper sheets 10-1/14-1/04-3/05-1, transit short, approvals, exceptions, period/lock, staff status/exit, advances, salary, price change, stock ledger), `rpt_hub_day` (events, day totals, reconciliation with `biz_daily`) |
| `supabase/phase472.sql` | `rpt_hub_find_entity`, `rpt_hub_entity` (item, customer, supplier, staff, employee, outlet, batch; running balance = `customer_ledger` / `supplier_ledger` / `stock_balance`, tested) |
| `supabase/phase473.sql` | `rpt_hub_metrics`, `rpt_hub_compare` (two periods, change, percent, movers by outlet), `rpt_hub_drill` (the transactions behind a figure; their sum equals the figure) |
| `supabase/phase474.sql` | `rpt_hub_trail` (who created / posted / voided, stock and journal reversals, exceptions, corrections, change requests, audit_log for the owner; anything missing is listed in `not_recorded`) |
| `supabase/phase475.sql` | `rpt_hub_my`, `rpt_hub_item_save`, `rpt_hub_item_remove`, `rpt_hub_touch`, `rpt_hub_log_export` |
| `supabase/phase476.sql` | `rpt_hub_spend_options`, `rpt_hub_spend` (spend explorer) |
| `supabase/phase470_test.sql`, `phase471_test.sql` (50 checks, incl. 6500 extra rows), `phase476_test.sql` (36 checks), `tests/sql/rpthub_tt.sql`, `tests/sql/rpthub_fixture.sql` | each test pastes the phases itself (`\i supabase/...`, run from the repo root) on a copy of a database through phase 99 |
| `web/reporthub.js`, `reporthub_parse.js`, `reporthub_ask.js`, `reporthub_time.js` | hub home + catalogue, question parser (pure, no AI), Ask + Spend finder, Day replay / Timeline / Compare / Drill / Trail |
| `web/data/report_registry.json` + `tools/build_report_registry.py` | static catalogue of the 193 master reports (+ parser word lists) |
| `tests/web/reporthub_test.js` (101 checks, 360 px, 3 language modes), `reporthub_parse_test.js` (68 checks) | |

## 2. Hook sites in shared files (done in this branch, minimal)
* `web/ia.js`: ONE line, `rec('reports/hub', 'reports', ...)` placed before `rec('biz', ...)`; `also: ['reports']`, `ok: any` (the server decides).
* `web/index.html`: after `reports2.js` add `<script src="reporthub_parse.js"></script><script src="reporthub.js"></script><script src="reporthub_ask.js"></script><script src="reporthub_time.js"></script>`.
* `web/reports.js` is NOT edited: `reporthub.js` wraps `BOS_PAGES.reports` (so `#/reports/hub/...` is served by the hub and `#/reports` shows one "Business Memory" card on top, also when the report engine is missing) and pushes one `B.reportLinks` entry.
* Integrator to do: `tests/sql/ORDER.txt` add `phase470 ... phase476` after `phase99` (they work after phase 99 and also without it; they need phases 8-21 only plus phase 72/88 tables the day replay reads); `web/sw.js` precache the 5 new files; `docs/BUILD-LOG.md`. `tests/web` runner list: add the two tests.
* Optional Home pin card: `rpt_hub_my()->pin` holds the pinned saved views; `B.rhub` exposes nothing for Home yet. The menu entry itself can already be pinned with the existing favourites.

## 3. Behaviour you should know
* **Reconciliation**: day net sales, number of sales, discount, void count and void value are compared with `biz_daily` (the dashboard summary). Status `match`, `mismatch` (the page shows both numbers) or `not_available` (no right to open the summary; never guessed). The older engine-1 `pos_day_close` still ignores returns (audit defect D1); the hub follows `reports_net_of_returns` like `biz_daily`.
* **Masking**: each kind needs its report right (`report_sales/pos/cash/customers/stock/purchase/expense/control`, `salary_view`/`payroll_manage`, employee/staff rights, `accounts_view`, `view_cost`). A kind the person may not see is named in `masked`, never counted. Cost, value and wastage amounts are null without the cost right. `audit_log` is shown to the owner only (its RLS). Saved form data of blind-count sheets is never returned.
* **Spend finder**: heads match by exact code; words are searched in the head CODE and in the memo / payee / bill text; every row says `head`, `memo` or `both`. A broad head such as "utilities" is NOT counted by itself, only when a word (electricity, বিদ্যুৎ ...) is in the memo. A person filter lists rows whose record stores the person (`direct`: advances, salary, purchases, supplier payments, refunds) and rows where the person's name is in the memo (`text`, flagged "not a verified link"); other expenses are counted apart as "not linked to a person" with the missing field (`quick_expenses.person_id`, `10-2 line person_id`). Staff pay rows (advance, salary, heads `staff_meal` and `labour`, any staff-linked row) need the payroll right. Default sources count a cost once (no supplier payments, no refunds, no journal); a utility bill that repeats a saved voucher is kept out of the total and listed under overlap.
* **Question box**: deterministic word lists in the registry (`parser` section). Always shows four chips (person, what, place, period); a missing period, an ambiguity (e.g. "ভাড়া" = rent or fare, "factory" = two places) or an unresolved name stops the run and shows the builder pre-filled plus the best matching reports. "Last N months" is rolling (today back N months), "last month/year" is the calendar one; the chip prints the exact dates. The fiscal year works only when `fiscal_year_start_month` is set.

## 4. Registry and audit 3
Reports 1-104 come from audits 1 and 2 (status counts 42 implemented, 46 incomplete, 15 unavailable, 1 unverified). Names are the audits' wording; the owner's master-list wording was not available to the builder. Reports 105-193 (sections 8-14) are `unaudited` placeholders. When audit 3 lands: put its table(s) (columns `no | name_en | name_bn | section | question_en | question_bn | status | route | source | grant | area | kw | note`) in `tools/report_registry_merge/*.md|csv` or pass `--merge file`, optionally `--master docs/inputs/report_master_list.csv` for the owner's exact names, then `python3 tools/build_report_registry.py` and `--check`.

## 5. Not tested / limits
* No real phone or live data; web tests mock the RPCs; SQL tests use `test_*` data on a local throwaway Postgres.
* Performance: 4 000 quick expenses + 2 500 collections added; day, year spend, year customer timeline and compare run in well under 6 s together. Larger ranges rely on the indexes of phase470.
* Bengali phrasing coverage is rule based (68 parser checks); unusual spellings fall back to the builder.
* The Home pin card and `sw.js` caching are integrator work. `rpt_hub_trail` for `entries` shows meta only, no form data.
* Known source gaps shown honestly: expenses carry no staff id; sales rows have no `created_at` (sold_at is used); utility bills have no person.
