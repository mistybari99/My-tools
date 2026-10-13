# Module G: Business assistant - first-step audit (read-only MVP)

Date: 2026-10-13. Method: read the brief, the phase files that define reads (phase4, 5, 9, 10, 12, 13, 16, 21-28), built a fresh test DB
(`a47base` = schema..phase28) and listed the live report catalogue from it, read web/app.js, entry.js, ia.js, nav.js, reports*.js.
Optional modules being built at the same time by other agents (phase40-46) were read from their briefs / current files only.

## 1. Stack facts that decide the design
* Static web app (GitHub Pages), plain JS, no build. Supabase Postgres + RLS + RPC is the only server. The owner is phone-only and pastes SQL.
* No app server -> an LLM API key can never live in the browser. Any paid model needs a Supabase Edge Function that the owner deploys (not done).
* The browser already runs every read under the user's own JWT; every report function re-checks `is_active`, grants, `can_loc`, cost and salary rights.
  So an assistant that only calls these existing functions inherits the whole access model for free.
* App context: `my_context` (is_owner, roles, locations, perms per form), `has_grant(code, loc)`, `B.ENV` (locs, items, staff, rules, grant_defs, lists),
  `B.rule(key)`, `B.L / B.lab` (bn / en / mix), `A.shell / openSheet / esc / fail`. Routes come from `web/ia.js` (`BOS.IA`).

## 2. What data / RPCs exist and which are safe read-only tools
All below are `stable` or read-only `security definer` functions with their own access checks (verified in the SQL). None takes SQL or a table name.

| Server function | What it returns | Access (server) | Assistant tool |
|---|---|---|---|
| `report_run(key, filters, group, sort, page, compare)` (phase9, engine 1) | columns / rows / totals / **compare delta per measure** / notes / meta.from-to | `rpt_access(group)` (owner, `report_<group>`, `view_reports`); cost columns only with `rpt_cost_ok`; mobile masked | sales_summary, sales_by_location, sales_trend, top_items, category_sales, discounts, voids, payment_modes, collections, best_customers, hour_weekday, receivable_aging, credit_limit_use |
| `report_run2(key, ...)` (phase21 + phase24 wrapper -> report_run3 for report_defs3) | same shape, no compare | `_r2_ok` / `_r3_ok` (group grant, cost, owner_only) | expenses_by_head, expense_trend (E2), cash_short_over, cash_flow (W1), stock_low, stock_balance, expiry_soon, wastage, transfers_gap, supplier_ageing (cost), purchases_by_supplier (cost), attendance_summary, exceptions_summary, count_variance (K2), paper_numbers (G2), compliance (X4), margin (L2, cost), pnl (L1, owner), shop_pnl (L3, owner), payroll (T3, owner), lapsed_customers (D5) |
| `report_presets()` | today / yesterday / last_7 / last_30 / this & last month / week / fy (rules week_start, fiscal year with documented fallbacks) | is_active | period resolution is left to the server whenever a preset fits |
| `biz_daily / biz_items / biz_staff / biz_outlook` (phase4, 6, 23) | day x location revenue, ABC items, staff indicator outliers vs median, 7-day outlook | `biz_ok` (owner, POS approve, view_reports); cogs only with `biz_cost_ok` | staff_outliers (biz_staff), outlook (biz_outlook) |
| `day_book(loc, from, to)` (phase23) | in/out per mode, net open/close, **opening/closing balances only when the 3 opening balances are set and the caller sees all places** | `view_daybook` per place, `daybook_enabled`, salary lines hidden without `salary_view` | cash_position |
| `customer_dues()` (phase12) | receivable per customer, limit, oldest | POS view/enter | receivables |
| `supplier_dues(loc)` (phase10) | payable per supplier, overdue | `_pur_ok` | payables |
| `stock_levels(loc, filters)` (phase10) | qty, min, below_min, value (value only where `_cost_ok`) | is_active + can_loc | stock_value |
| `needs_you_oldest(limit)` (phase28) | oldest waiting approvals / releases / emergencies / item changes / pending staff / wastage / parallel months, with route | each row filtered by the caller's own rights | needs_you |
| `number_audit_summary()` (phase5) | paper-number gaps per form x place | its own rules | number_gaps |
| `rules`, `grant_defs`, `locations` tables (select) | settings, grant labels, places | RLS select for authenticated | rule_info, locations |
| Optional (other agents, guarded by a catalogue check, never an error): `balance_sheet`, `income_statement`, `trial_balance` (phase40 accounting), `partner_overview` (phase44, owner), `tier_usage_report` (phase43), `backup_status` (phase46) | - | their own checks | acc_balance_sheet, acc_income_statement, acc_trial_balance, partners, tiers, backup |

Write functions (sale, purchase, approve, rules set ...) exist but are **not** tools: the MVP has no write action at all.

## 3. Questions the MVP can answer (verified numbers come only from the functions above)
* Sales today / period / per branch / trend / compare vs previous period (engine-1 compare gives current, previous, abs and pct per measure).
* Top / bottom items and categories by sales; margin by item (cost right only); P&L by month and shop (owner only).
* Biggest expenses (by head), expense change vs previous period (E2), discounts, voids, cash short/over, wastage, count variance, expiry, low stock, transfers not received.
* Receivables, payables (overdue), stock value (cost right), cash/bank/mobile position (only when the day-book opening balances are set).
* Needs-you list, paper-number gaps, exceptions, form compliance, staff indicator outliers.
* Setup: screens, settings, grants, forms, docs, playbooks (KB), and live configuration findings (`assistant_health`, new in phase47).

## 4. Gaps - what cannot be answered yet and why
* **Balance sheet / true financial position**: no accounting ledger before phase40 (being built). Until then "financial position" is a composed
  statement: cash/bank/mobile (day book, needs opening balances), receivables, payables, stock value (cost right), month P&L (owner). Each line is
  marked verified / partial / data needed. Fixed assets, loans, owner equity are not in the database -> always "data needed".
* **Profit** for non-owners: L1/L3 are owner-only; L2 margin needs the cost right. Others get "not available with your access".
* **Cash position** when `daybook_open_*` rules are blank or the user cannot see every place: day book returns no balances -> "data needed".
* **Expenses compare**: engine-2 reports have no compare flag -> the assistant runs the same report for both periods and subtracts (only the two server
  totals are used; the difference is arithmetic on them, labelled as such).
* **"Why" explanations**: only what the numbers show (top movers by place / item / head). Weather, competition, festivals are not in the data.
* **Price overrides / late entries per person**: in `discounts` (override_lines) and X4 compliance (late_submits) only; no separate detector.
* **Salaries**: only through `t3_payroll` (owner); attendance summary via report_staff. No other salary figure is shown.
* **Forecasting**: only `biz_outlook` (server's simple average); no own model.
* Customer tiers, partners, payroll runs, backups: only when those phases are installed (catalogue check).

## 5. Risks and how the design handles them
| Risk | Mitigation |
|---|---|
| A guessed number | Composer prints only values read from tool results (+ labelled arithmetic on them: difference, %, share). Missing -> "data needed". Tests compare every printed figure with the mock data. |
| Data leak across roles / places | Tools call the existing RPCs with the user's JWT; the registry also hides tools the user lacks (`assistant_me()` capability map), and a server refusal is shown as "not available with your access" with no data. |
| Prompt injection via data (customer names, notes) | Tool results are never fed back into the router; they are escaped with `esc()` and rendered as text. The router reads only what the user typed. |
| Arbitrary SQL / table access | No tool accepts SQL, a table name, a function name or a sort expression from the user; report keys are a fixed whitelist in the registry and on the server. |
| Write actions by mistake | MVP has no write tool. "delete / approve all / change price" are refused with a link to the screen. Rule `assistant_actions_on` is reserved (OFF). |
| Secrets in logs | `assistant_usage` stores intent, tool keys, ms, tokens, ok - no question text, no results. The composer redacts things that look like PINs / passwords / tokens. |
| Paid API spend | Default provider `local` (free, in the browser). `llm_proxy` is a disabled adapter + undeployed edge function source; budget rule; owner approval needed. |
| Phone performance | Router + composer are synchronous JS (< 5 ms typical); 60 s cache per (tool, params); KB loaded once, lazily. |
| Stale knowledge | `tools/build_kb.py` regenerates kb.json from the real sources; it fails if a playbook names a route / rule / grant that no longer exists. Content hash shown as "knowledge version". |
| Other agents editing shared files | Only new files; the registration lines are in docs/regs/assistant.md for the lead. |

## 6. Configuration conflicts that can be justified from the code (used by `assistant_health`)
* `grn_receipt_source = 'grn'`: phase23 only skips the GRN (04-1) in-lines when the source is `purchase`; the purchase page posts `purchase_in` in
  every case (no skip). So with `forms_post_to_ledger` ON the same goods can enter stock twice (purchase page + GRN; `receipt_duplicates()` exists to
  cross-check) (warn), and with `forms_post_to_ledger` OFF the choice has no effect because GRN never posts (phase20 `_ledger_on`) (info).
  The default (`purchase`) is consistent in both cases.
* `vat_on` ON with `vat_rate` blank -> VAT cannot be computed (phase8). (bad)
* `production_requires_recipe` ON with no active recipe -> every production is refused (phase19). (bad)
* `recipe_waste_required` ON with active recipe lines whose waste % is blank -> those productions are refused (phase19). (warn)
* `daybook_enabled` ON with `daybook_start` blank -> running balances are unknown (phase13/23); opening balances blank -> no closing balances. (warn)
* `period_closed_until` blank or older than 45 days -> old dates stay editable (phase-wide lock_check). (warn / info)
* `blind_count_on` ON with no form switched on in blind_count_cfg; `pin_signature_on` ON with no form in pin_sig_cfg -> the switch does nothing (phase18). (info)
* `stock_negative_mode = 'allow'` together with `block_expired_sale` OFF -> selling beyond stock is not even warned and an expired sale only leaves an
  exception line (phase10/12 stock_post). Labelled "weak control", not an error. (info)
* Form x place in `parallel` with no active comparison pair (phase28 needs one to record a day). (warn)
* Form x place in `app` with no app entry in the last 14 days (rollout switched but not used). (info)
Data checks: active sellable items without price / unit, tracked items without base unit, places without an approved settings sheet or with blank key limits
(drawer_float, cash_tol, discount_limit, expense_max for showrooms), pending staff, active staff with no role or no place, no one but the owner holding approval
(`release_decide`, `wastage_approve`) or report grants, active recipes without yield, suppliers without credit days, customers over their credit limit,
stale backup (if backup_runs exists), accounting on without a start date (if installed).
