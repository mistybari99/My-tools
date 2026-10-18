# PASTE ORDER: what to paste into Supabase, in what order, and what to switch on

This is the owner's step list for the merged build (all packages built so far). It was written by the master integrator and checked on a local throwaway Postgres only; nothing was pasted into the live Supabase project by any agent (CLAUDE.md, Database safety).

**Everything new starts OFF or blank.** After you paste, the app behaves exactly as it did before, apart from added columns, added notices and new screens that stay empty until you use them (proved: `tests/sql/integ_before_after.sh`, section 7).

## 0. Before you start

1. Take a backup (Home > Backup, or the nightly backup file). Pasting is safe to repeat, but a backup is cheap.
2. Open the Supabase project > SQL Editor. Paste ONE file at a time: open the file in GitHub (branch `claude/supabase-readonly-audit-xo3qkp`, folder `supabase/`), copy all, paste, Run. Wait for "Success" before the next one.
3. **Paste only the files named in section 2, in that order.** The same order is in `tests/sql/ORDER.txt` (one name per word).
4. **Do NOT paste** (test projects only, they wipe data or exist only for tests):
   - `supabase/phase84_test_project_only.sql`
   - `supabase/phase84b_test_project_only_wave1.sql` (and any file whose name starts with `phase84b_`)
   - any `*_test.sql` file, `phase14_import*`, `phase30_controls*`, `ALL_NEW*` (only for a brand-new empty project, see SETUP.md)
5. A file that stops with a red error: stop there, copy the message, do not paste the next file. Every file is safe to paste again after the cause is fixed.
6. **Restore test and idle projects.** Once, before you rely on the backup, restore the latest backup into a spare (test) project and open the app on it; a backup that was never restored is not proved. Two things stop quietly when nobody uses them: a Supabase free-tier project is paused automatically after 7 days without activity (open the app or the dashboard at least once a week, or use a paid plan), and a GitHub Actions scheduled workflow (nightly backup, notifications) is disabled by GitHub after 60 days without any repository activity (push a small commit or re-enable it under Actions). Check both after a long holiday.

## 1. What is already in your live project

Phases 8 to 87 (the base). If you pasted Wave 1 (88 to 99) already, skip those rows. Your project's history decides where you start; pasting a phase that is already in causes no error and no data change, but an OLD phase (3 to 98) also puts back the older text of functions that later phases patched. Read section 5 before you paste any file that is already in; for phases 88 and later (and 120 on) a second paste changes nothing (proved, function text identical).

## 2. The paste list (numeric order = `tests/sql/ORDER.txt`)

| Order | Phase file(s) | Package | What it adds, in one line |
|---|---|---|---|
| 1 | `phase8` ... `phase87` (every number in ORDER.txt) | base | the product as it is today |
| 2 | `phase88` | Wave 1 W1-A | opening balances of customers and suppliers, customer ledger with the opening due (hooks) |
| 3 | `phase89` | Wave 1 W1-B | period lock, back-date window, late offline sales held for the owner (hooks) |
| 4 | `phase90`, `phase91` | Wave 1 W1-C | staff exit lockout; sale returns with a window, a class rule and expired-batch rule (hooks) |
| 5 | `phase92`, `phase93` | Wave 1 W1-D | "one profit number" and report parity (hooks, profit view) |
| 6 | `phase94`, `phase95` | Wave 1 W1-E | supplier payment limit and duplicate guard; journal requests (hooks) |
| 7 | `phase96`, `phase97` | Wave 1 W1-F | day book vs journal, other income; bank/cheque receipts (hooks) |
| 8 | `phase98` | Wave 1 W1-G | "last posted at" strip, scheduled journal posting, encrypted backup, switch acknowledgements |
| 9 | `phase99` | Wave 1 I-1 | applies the 37 Wave 1 hooks in one call and merges the Exceptions kinds |
| 10 | `phase120` | R1 pay requests | staff salary/advance requests and supplier payment requests with one approver; "required" policies (a trigger, no function hook) |
| 11 | `phase130`, `phase131`, `phase132` | R2 | announcements, to-do list with repeats, shift roster (record-only) |
| 12 | `phase140` ... `phase143` | W1-FIX | void follows the return rules; supplier limit over several days; staff-exit fixes (4 hooks); re-patch of those 4 |
| 13 | `phase300`, `phase301`, `phase302` | CRM-A | customer profile plus: extra phones, delivery points, family dates, tags, notes, Customer 360, masked directory |
| 14 | `phase303`, `phase304`, `phase305` | CRM-B | consent register and do-not-contact, privacy by role with reveal log and export control, duplicate customers with a soft link |
| 15 | `phase306`, `phase307`, `phase308` | CRM-C | customer lists (segments), RFM and customer value, privacy helpers, optional scheduled score refresh |
| 16 | `phase316` ... `phase319` | CRM-F | points expiry and burn rules, referral, coupons and vouchers, optional voucher liability, birthday/festival hooks, statement and summary |
| 17 | `phase323` ... `phase327` | CRM-G | party/gift enquiries (leads, quotes, won/lost) and tasks with reminders |
| 18 | `phase328`, `phase329` | CRM-H | complaints with a clock, food-safety flag, ratings and repeat complaints |
| 19 | `phase400` ... `phase403` | RPT-B1 | returns and refunds in the sales reports, "not captured" notices, cost basis setting, three added reports |
| 20 | `phase404` ... `phase413`, `phase415`, `phase416` | RPT-B4 | production plans/orders/real use/loss, targets and KPI, capacity and labour, factory vs retail |
| 21 | `phase420` ... `phase425` | RPT-B2 | stock and freshness reports (ledger, reconciliation, batches, ageing, turnover, integrity) |
| 22 | `phase430` ... `phase436` | RPT-B3 | supplier lot and expiry on receipts, trace and recall, quality extras, stockout log, purchasing reports |
| 23 | `phase440` ... `phase444` | RPT-C1 | report honesty (null-safe totals, profit completeness), expense register, P&L by month/outlet, cash-flow statement, working capital |
| 24 | `phase445` ... `phase457` | RPT-C2 | order and delivery reports and capture (cake spec, promise slot, advance, refund, delivery cost), customer credit, staff and labour reports |
| 25 | `phase458` ... `phase468` | RPT-C3 | campaigns and marketing spend (optional posting of form 18-1), audit reports, forecasts |
| 26 | `phase470` ... `phase476` | RPT-HUB | Business Memory: day replay, timeline of a thing, compare, spend finder, record trail (all read-only) |
| 27 | `phase477` | integrator | **re-patch all** + glue (see section 5) + one Exceptions-kinds merge |
| 28 | `phase478` | integrator | closes the ~13 small helper functions (`_..._present`, `_w1*_`) to the signed-out role (anon); signed-in people, the owner paths, `_i2_state()` and phase 477 keep working. Paste **last**, after 477 |
| 29 | `phase490` | X2 website part 1 | website settings (all OFF or blank, in `rules`), catalogue publishing (`web_item_pub`, approved photos), pickup points, zones, closures; public read functions `web_site_config`, `web_catalog_v2`, `web_quote` (anon) |
| 30 | `phase491` | X2 website part 2 | public checkout `web_checkout_submit` (idempotent, rate limited, server re-priced, optional hard stock holds), tracking and cancel request, custom cake request, owner `web_admin_*` functions, drift and go-live checklist, storage buckets `web-refs` (private) and `web-public` (public, owner-approved photos). Paste **after 478** and then `phase491_test.sql` only on a test copy |
| 29 | `phase510` | X4 (AI) | AI foundation: provider registry (no key column), monthly token and money budgets, redaction rules, agent catalogue (10 agents, all OFF, forbidden actions and grants refused, untrusted-input agents get no proposal action), append-only `ai_calls` log with `actor_type`, owner-only configuration RPCs. Every switch OFF (`ai_on`, `ai_pause_all`) |
| 30 | `phase511` | X4 (AI) | verified knowledge (propose, another owner verifies, publish; only verified is authoritative), suggestions with accept / reject / correct (no self-decision), later outcomes, golden evaluation cases and runs, scorecard and usage (cost only from owner-typed prices). Paste after 510 |
| 29 | `phase520` | X5 | item recognition foundation: duplicate / similar check (`item_similar`, `item_new2` with client id, barcode and exact-name refusal), review record for unclear reads, approved aliases, asset brand / serial / warranty. All recognition switches OFF; blank limits stay blank. Paste once; the app uses it only after the owner switches `item_similar_check_on` ON |

Numbers 114 to 132 are reserved in `docs/UNIFIED_BUILD_PLAN.md` 4.4 for Wave 2; R1 (120) and R2 (130 to 132) took numbers inside that range. Nothing else in this build uses 100 to 119 or 121 to 129, so there is no clash; if a later Wave 2 package wants 120 it must be renumbered. RPT-HUB was built as 450 to 456, which clashed with RPT-C2 (445 to 457); it is now **470 to 476** (files, tests, texts all renamed). `phase414` and `phase417` to `phase419` do not exist on purpose (RPT-B4 left them unused).

## 3. After the last paste

1. Run `select * from public._i2_state() where not present;` : it must return **no rows**. (Phase 477 already put every hook in. The rows it would list are hooks that are missing.)
2. Deploy the web files (section 4).
3. Open the app once as the owner. Nothing should look different on Home except the small (i) buttons on screen titles and settings rows, and the new menu entries (Customers: Customer lists, Customer value, Loyalty extras, Coupons, Enquiries, Tasks, Feedback and complaints, Consent and privacy, Duplicate customers; People: Pay requests, Announcements, To-do, Shifts; Reports: Business Memory and Reports map; and the new report screens).

## 4. Deploy the web files

The app is the `web/` folder (static files). As in `docs/HANDOVER_3.md`:

1. `python3 tools/build_kb.py` (rebuilds `web/data/kb.json`, the assistant's knowledge; already done in this branch).
2. Copy the whole `web/` folder (every file and `web/data/*.json`, except `setup-sql.html`) into the public Pages repository `mistybari99/islamia-bos-app`, commit, `git push origin main`.
3. On each phone: reload the app once (the service worker is network-first; a second reload picks up everything).
4. The scheduled job `.github/workflows/notify.yml` runs `tools/notify_digest.py`: it now also asks for task reminders (CRM-G) and the complaint clock (CRM-H) after the scan. Both answer "skipped" until you switch their settings ON, and a failure there never stops the alerts.

## 5. If you ever paste an OLD phase file again

Old phase files (3 to 98) re-create functions and so remove the hooks other phases put into them. The rule:

1. Paste **every file from that phase up to `phase98`, in order** (a hook patches the exact text a chain of phases left, so one old file alone can break the chain; this is how the Wave 1 hooks have always worked).
2. Then paste `phase99`, and every later file you use, or simply paste `phase477` (it calls `public._i2_apply_all()`). Then paste `phase478` again: a re-pasted old phase makes its helper functions open to anon again, and 478 closes them (safe to paste twice).
3. `select public._i2_apply_all();` puts back every exact-text hook (Wave 1: 37, W1-FIX: 4, RPT-B1: 13, RPT-B3: 1, CRM-B: 2, CRM-C: 1, RPT-C1: 7, glue: 1) and says how many it had to patch. It is safe to run any time; the second call patches nothing.
4. **Functions that a package re-creates as a whole** (not patched) are not restored by step 3. `select * from public._i2_state() where not present;` lists them with the phase to paste again: `phase420` (report_run2, report_catalog2, stock_reconcile, p4), `phase421` (k2), `phase432` (qc), `phase434` (rate trend), `phase441` (compliance). Pasting those files again is safe.
5. Check again: `select * from public._i2_state() where not present;` returns no rows.

Proved by `supabase/phase477_test.sql` (re-pastes phases 8 to 98 on the finished database, then 477: all 66 hooks come back and every function text is the same as before).

## 6. Where to switch things ON (every one is OFF or blank today)

You switch settings in the app: **Settings (the Switchboard / Rules page), group "module"**. Each row has an (i) button that says what it does and what changes. Past figures never change when you switch something on; each switch only affects what is done after it. Several need a date or an account first and refuse to switch on without it (the screen says why).

Recommended order (small to large): announcements, to-do and shifts (R2); pay requests (R1); the report settings (cost basis, net of returns); customer settings (CRM) one at a time; marketing posting and voucher liability LAST, after your accountant has read `docs/integration/RPT-C3.md` section 5 and `docs/integration/CRM-F.md`.

Four settings are ON by default but do nothing until their module is on: `shift_mates_on` (needs `shift_on`), `crm_unmask_reason_required` (needs `crm_pii_guard_on`), `crm_complaint_fs_exception_on` and `crm_complaint_breach_exception_on` (need `crm_complaints_on`).

### Settings added after phase 99 (125 rows, generated from the database)

| Module (group) | Setting key | Kind | Default |
|---|---|---|---|
| books | marketing_post_from | text | blank |
| books | marketing_post_on | switch | OFF |
| books | supplier_pay_over_cumulative_days | number | 0 |
| crm | crm_burn_max_percent | number | blank |
| crm | crm_burn_max_points | number | blank |
| crm | crm_burn_step_points | number | blank |
| crm | crm_complaint_breach_exception_on | switch | ON, inert until its module is on |
| crm | crm_complaint_fs_categories | text | sick |
| crm | crm_complaint_fs_exception_on | switch | ON, inert until its module is on |
| crm | crm_complaint_fs_severity | choice | keep |
| crm | crm_complaint_sla_hours_critical | number | blank |
| crm | crm_complaint_sla_hours_high | number | blank |
| crm | crm_complaint_sla_hours_low | number | blank |
| crm | crm_complaint_sla_hours_medium | number | blank |
| crm | crm_complaints_on | switch | OFF |
| crm | crm_consent_pos_on | switch | OFF |
| crm | crm_dup_check_on | switch | OFF |
| crm | crm_dup_similar_names_on | switch | OFF |
| crm | crm_export_max_rows | number | blank |
| crm | crm_export_on | switch | OFF |
| crm | crm_feedback_low_max | number | blank |
| crm | crm_feedback_on | switch | OFF |
| crm | crm_feedback_window_days | number | blank |
| crm | crm_hooks_on | switch | OFF |
| crm | crm_lead_list_add_mode | choice | owner |
| crm | crm_lead_lost_by | choice | manager |
| crm | crm_lead_on | switch | OFF |
| crm | crm_lead_quote_valid_days | number | blank |
| crm | crm_lead_reopen_mode | choice | reason |
| crm | crm_lead_stale_days | number | blank |
| crm | crm_lead_win_needs_quote | switch | OFF |
| crm | crm_mask_phone | switch | OFF |
| crm | crm_mask_style | choice | first3_last2 |
| crm | crm_metrics_batch | number | 2000 |
| crm | crm_metrics_schedule_hours | number | blank |
| crm | crm_metrics_schedule_on | switch | OFF |
| crm | crm_on | switch | OFF |
| crm | crm_order_task_days | number | blank |
| crm | crm_pii_guard_on | switch | OFF |
| crm | crm_points_adjust_alert_over | number | blank |
| crm | crm_points_expiry_from | text | blank |
| crm | crm_points_expiry_months | number | blank |
| crm | crm_points_expiry_warn_days | number | blank |
| crm | crm_print_needs_export | switch | OFF |
| crm | crm_quiet_from | text | blank |
| crm | crm_quiet_to | text | blank |
| crm | crm_quote_min_lead_days | number | blank |
| crm | crm_referral_min_bill | number | blank |
| crm | crm_referral_on | switch | OFF |
| crm | crm_referral_referred_points | number | blank |
| crm | crm_referral_reward_points | number | blank |
| crm | crm_repeat_days | number | blank |
| crm | crm_repeat_min | number | 2 |
| crm | crm_repeat_scope | choice | customer_item |
| crm | crm_reveal_for_call | switch | OFF |
| crm | crm_rfm_frequency_min | number | blank |
| crm | crm_rfm_recent_days | number | blank |
| crm | crm_rfm_spend_min | number | blank |
| crm | crm_second_phone_on | switch | OFF |
| crm | crm_seg_export_max_rows | number | blank |
| crm | crm_seg_export_on | switch | OFF |
| crm | crm_segment_max_members | number | 5000 |
| crm | crm_segments_on | switch | OFF |
| crm | crm_task_default_due_hours | number | blank |
| crm | crm_task_on | switch | OFF |
| crm | crm_task_reminder_on | switch | OFF |
| crm | crm_task_snooze_max_days | number | blank |
| crm | crm_unmask_reason_required | switch | ON, inert until its module is on |
| crm | crm_voucher_expense_account | text | blank |
| crm | crm_voucher_liability_account | text | blank |
| crm | crm_voucher_liability_from | text | blank |
| crm | crm_voucher_liability_on | switch | OFF |
| crm | crm_voucher_max_amount | number | blank |
| crm | crm_voucher_max_percent | number | blank |
| crm | crm_voucher_on | switch | OFF |
| crm | crm_winback_days | number | blank |
| customers | credit_default_days | number | blank |
| customers | credit_risk_high_days | number | blank |
| customers | credit_risk_watch_days | number | blank |
| people | announce_on | switch | OFF |
| people | pay_request_advance_ceiling | number | blank |
| people | pay_request_approver_mode | choice | owner |
| people | pay_request_approver_role | text | blank |
| people | pay_request_approver_user | text | blank |
| people | pay_request_exception_mode | choice | reason |
| people | pay_request_max_per_month | number | blank |
| people | pay_requests_on | switch | OFF |
| people | pay_requests_required_kinds | choice | both |
| people | pay_requests_required | switch | OFF |
| people | shift_mates_on | switch | ON, inert until its module is on |
| people | shift_on | switch | OFF |
| people | todo_on | switch | OFF |
| people | todo_repeat_on | switch | OFF |
| pos | order_advance_post_from | text | blank |
| pos | order_advance_post_on | switch | OFF |
| pos | order_promise_required | switch | OFF |
| pos | order_refund_record_on | switch | OFF |
| pos | void_follows_return_rules | switch | OFF |
| purchase | party_request_approver_mode | choice | same |
| purchase | party_request_approver_role | text | blank |
| purchase | party_request_approver_user | text | blank |
| purchase | party_requests_on | switch | OFF |
| purchase | party_requests_required | switch | OFF |
| purchase | receipt_expiry_required | switch | OFF |
| purchase | receipt_lot_required | switch | OFF |
| reports | fc_payroll_day | number | blank |
| reports | fc_window_days | number | blank |
| reports | kpi_alert_discount_pct | number | blank |
| reports | kpi_alert_sales_drop_pct | number | blank |
| reports | kpi_alert_void_n | number | blank |
| reports | mkt_repeat_days | number | blank |
| reports | order_late_grace_minutes | number | blank |
| reports | report_cash_short_by_case_on | switch | OFF |
| reports | report_cf_opening_through | text | blank |
| reports | report_compliance_closed_days | text | blank |
| reports | report_compliance_from | text | blank |
| reports | report_lapsed_days | number | blank |
| reports | report_profit_blank_on | switch | OFF |
| reports | report_rfm_atrisk_days | number | blank |
| reports | report_rfm_min_orders | number | blank |
| reports | report_rfm_recent_days | number | blank |
| reports | report_top_customers_n | number | blank |
| reports | reports_cost_basis | choice | price_list |
| reports | transfer_price_pct | number | blank |
| reports | transfer_valuation_basis | choice | none |

## 7. What was proved, and how to repeat it (local throwaway Postgres only)

| Proof | Command | Result on the merged build |
|---|---|---|
| Every phase can be pasted twice | `PORT=5570 bash tests/sql/run_all_sql.sh` (chain in owner order, every phase from 88 on pasted once, then again on a copy) | no error in any second paste |
| Each package's own SQL suites, alone on a database through phase 99 + its own phases | `docs/integration/INTEGRATION.md` section 6 | 4259 pass, 0 fail (89 suites) |
| Old suites 8 to 87 give the same failing lines as before | same runner (base vs final build) | identical, except 3 documented intended changes (RPT-B2: phase21 T5, phase26 K2; phase84 test-project reset, section 8) |
| Default state = today | `PORT=5570 BASE=base87 bash tests/sql/integ_before_after.sh` | 33 existing reports identical before/after (pasted once, twice, and after a second wave of records); only `l1_pnl` / `l3_shop_pnl` gain the key `profit_complete` and words in `gaps`, no figure changes |
| Many settings ON at once | `psql ... -f tests/sql/integ_test.sql` | 39 checks: every journal entry balances, Balance Check green, all report engines run, the packages share data correctly |
| Re-patch | `supabase/phase477_test.sql` | 33 checks |
| Helpers closed to anon | `supabase/phase478_test.sql` | 13 checks |
| Web | `python3 tests/web/run_all.py` | 97 suites, all clean: exit code 0, no FAIL line, no page error (read every log, not only the exit code) |

## 8. What is NOT covered or untested

- **The live Supabase project, a real phone, a real printer, a real spreadsheet.** Nothing here touched them. Every web test mocks the server; every SQL test uses `test_*` data on a throwaway database.
- **PostgREST calls of functions whose names start with an underscore** (`_crmb_*`, `_crmg_*`, `_crmh_*`, `_w1g_*`, `_i2_*`): the web calls several of them; on a real project they work only if the function is exposed to the API. The existing `_w1c_sale_return` uses the same style, so it is expected to work, but it was never run against PostgREST.
- **The test-project reset** (`phase84_test_project_only.sql` + `phase84b_*`) does not know the tables of phases 120 and later. It REFUSES (it names the tables) instead of wiping part of the data. Do not use it on a project that has these phases until a `phase84c` file classifies them; that file was not written (test-project tooling only).
- **`pg_cron`** for scheduled journal posting and score refresh: not verified on your Supabase plan. The GitHub job `notify.yml` calls them every 30 minutes instead.
- **Offline queue**: new capture screens (cake spec, promise slot, order advance, consent tick, coupon at the till) do not queue offline; a sale made offline loses its coupon / consent tick (documented in CRM-B and CRM-F notes).
- **Accountant sign-off** for: voucher liability (CRM-F), marketing spend posting (RPT-C3), order advance and refund records (RPT-C2), transfer valuation (RPT-B4), management profit vs journal profit (RPT-C1). They are OFF; read the notes before switching on.
- **Bangla review**: most new screen texts are English only by the owner's rule for report screens; Bangla/mix labels written by the builders (settings, rules) need the owner's read.
- **Not built, not touched**: CRM D (campaigns), E (scheduler), I; UI Wave 3; tax/VAT and loans (#127, #128); entities. The UI was not restructured; the only UI changes are the integration hooks and the (i) sign.
- **Two privacy switches** exist (CRM-A `crm_mask_phone`, CRM-B `crm_pii_guard_on`). Phase 477 makes either one hide numbers on both families of screens; the full effect (reveal reason, access log, export gate) is only in CRM-B.
- **Direct table reads** (`customers` policy `customers_read`, risk R6 of CRM-B) are not closed: a person with POS view can still read customer rows through the API.
- Demo-like sample text that already existed before this work and was left alone: the staff id hint in `web/i18n.js` ("rahim01") and the invoice preview sample in `web/invoice.js`.

## 9. Decisions for the owner (nothing was decided for you)

1. **Order of switching on** (section 6) and who is the approver for pay requests (owner / role / person) and the limits `pay_request_max_per_month`, `pay_request_advance_ceiling`.
2. **Privacy**: switch on `crm_pii_guard_on` (recommended; also covers Customer 360 through phase 477), then decide `crm_export_on`, `crm_reveal_for_call`, `crm_mask_style`. Hard merge of customers and "forget this customer" are not built.
3. **Report numbers**: `reports_cost_basis` (price list now; ledger first when ready), `profit_one_number_on`, `report_profit_blank_on`, `reports_net_of_returns`.
4. **Accounting-affecting switches** (each needs a date or account first): `marketing_post_on` (+`marketing_post_from`), `order_advance_post_on` (+from), `order_refund_record_on`, `crm_voucher_liability_on` (+from, accounts), `transfer_valuation_basis`.
5. **Blank limits you must type before the feature works**: KPI alert limits, `credit_default_days` and the credit risk days, `crm_voucher_max_percent` / `max_amount`, `mkt_repeat_days`, `fc_window_days`, complaint SLA hours, lead quote validity.
6. **Who holds the new grants** (all start with the owner only unless the note says a role): `sales_target_manage`, `capacity_manage`, `crm_view`, `crm_contact_view`, `crm_merge`, `crm_loyalty_manage`, `crm_voucher_issue`, `crm_lead_manage`, `crm_complaint_manage`, `recall_manage`, `supplier_terms_manage`.
7. **Paper form codes** for the new entry screens (production plan/order/real use/loss/labour, targets, lines, cake sheet, crew sheet, recall, stockout, lots): shown as "to be given by owner" on each screen.
8. **Real use of ingredients is a record, not a stock movement** (RPT-B4). Posting the difference to stock and journal is a separate decision.
9. **Loans and VAT** reports are not built (#127, #128).
10. **CLAUDE.md**: the Database safety line names only `phase84_test_project_only.sql`; consider adding `phase84b_test_project_only_wave1.sql` (W1-FIX suggestion). Not edited by the integrator.
11. Sample names in `web/i18n.js` and `web/invoice.js` (see section 8).

## 10. X1 foundation (phases 480 and 481)

Paste after phase 478, in this order: `supabase/phase480.sql`, then `supabase/phase481.sql`. Both paste twice clean. Nothing existing is changed (no old function patched); every new behaviour is OFF.
Owner switches: `automation_on` (OFF) and `automation_pause_until` (empty) in the Switchboard; every connection on the Connect Center (OFF). Details and the list of names: `docs/integration/X1.md`.
Not in the paste: `supabase/phase480_test.sql`, `supabase/phase481_test.sql` (tests, fresh test databases only).
