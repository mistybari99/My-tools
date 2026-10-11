# BUILD-LOG

One entry per task: what changed, what could NOT be confirmed, manual checks and results. Append, never overwrite others' entries.

## Carry-over checklist (HANDOVER §8)

- [ ] 1. Items.details + apply_item_patch + Details field on item form
- [ ] 2. Cost visible on items list for view_cost grant only (RPC gated by has_grant)
- [ ] 3. Real low-stock status on items list/filter (stock_levels RPC, min_stock flag)
- [ ] 4. Stock: category label list in stock_levels; purchase/sale unit list per item; item-name search in stock list
- [ ] 5. Barcode scan on purchase-bill item field and stock actions
- [ ] 6. Home Accounting "Day book" tile
- [ ] 7. Per-line stock-effect preview in purchase bill editor
- [ ] 8. Photos for stock/purchase: dedicated STOCK / PURCHASE prefixes or grant-based photo_ok
- [ ] 9. Emergency-rule keys for stock_count_adjust, stock_transfer, stock_issue, stock_production
- [ ] 10. Wastage: manager approval above an owner-set limit (maker-checker)
- [ ] 11. Supplier refund (cash back) alongside return credits; sale_return flow
- [ ] 12. Expired batches: optional setting to block selling expired stock
- [ ] 13. Salary view / export_data grants: salary report page, server-side export grant
- [ ] 14. stock_ledger.ref_id column grant leak: revoke column or null via view
- [ ] 15. Forms <-> stock/purchase links (04-1, 04-2, 04-3, 03-1, 05-1 post to ledger when approved, switchable, default off; 04-4 / 06-5 as views; 06-5 supplier_pick)
- [ ] 16. Discount approver stored on sales; brand-level P&L; remaining reports of the 65-report catalogue
- [ ] 17. Nav leftovers: Year tab follows fiscal_year_start; drawer search; location switcher in drawer footer; staff home "today's sheets"; owner default favourites per role UI
- [ ] 18. Run tests/web/smoke.js; real-device checks list for the owner (thermal printer 58/80, camera barcode, offline sale sync, Chrome auto-translate off)
- [x] 19. Security backlog: BACKUP_TABLES completeness, server-side PIN lockout + failed-login log, audit_log append-only, immutable codes, option deletes revoked (W1)
- [ ] 20. VAT/Mushak 6.3 receipt line stays OFF until the owner's adviser gives the rate; no number invented

(Item 19 is ticked by W1 below; it is done for the parts listed in the W1 entry.)

## Decisions log

- (empty; add one line per decision: date, task, decision, setting that switches it)

## Task entries

### W1 Hardening (supabase/phase11.sql, supabase/phase11_test.sql)
Changed
- docs/BUILD-RULES.md saved verbatim (16 rules); this log created.
- phase11.sql (additive, run twice OK): audit_log append-only (row trigger update/delete + statement trigger truncate, ENABLE ALWAYS so it also holds under session_replication_role=replica; UPDATE/DELETE/TRUNCATE revoked from clients). No function in the schema updates/deletes audit_log (grep of all function bodies: none).
- Immutable codes (error 'code is immutable'): locations.code, forms.code, roles.code, option_lists.list_code + value_code, items.code. Same-value updates and filling a previously empty code are allowed. (items.code also has the older trigger 'item code cannot be changed'.) No item_categories / units tables exist; category and unit are option_lists rows (covered).
- No hard deletes: BEFORE DELETE trigger ('nothing is deleted – retire instead') on option_lists, locations, forms, items, profiles, entries, sales, customers, suppliers; exceptions: only status='open' rows may be deleted (submit_entry/decide_entry re-evaluate open flags by delete+insert; decided exceptions are protected). DELETE revoked from anon/authenticated on option_lists, unit_conversions, shelf_life_rules, invoice_templates, print_profiles, report_brand_map.
- Kept DELETE (UI needs it, all audited by triggers): role_form_perms, user_roles, user_locations (app.js tick toggles), rule_grants, user_grants (via definer RPC), report_views, user_favourites, role_favourites (personal convenience).
- Web UI retire instead of delete: invoice.js iv_del / iv_prof_del and settings2.js s2_sh_del now set active=false (small edits in files outside W1's list, needed so the revoke does not break buttons).
- Server-side lockout: new login_attempts (owner read only, no client write) and login_throttle (no client access); login_failures gets locked_until + window_start. login_failed logs each attempt, locks at max_fails failures within lock_minutes (new setting, default 10) for lock_minutes; auto-release when lockout_auto_release (new setting, default true) else only owner unlock; per-staff cap 50 log rows/min, unknown ids share one global cap of 200/min; unknown ids return the same shape and write no lock row. login_precheck keeps `locked` and adds `seconds_left` (null = until owner unlocks) and `attempts_left`. login_success clears and logs ok. unlock_staff now also writes an audit_log line. Signatures unchanged. The settings screen already lists every settings row, so lock_minutes / lockout_auto_release appear next to max_fails with no UI change.
- app.js backup: BACKUP_TABLES now 44 tables (all business tables the owner can read incl. item_costs, sales incl. lines, stock/purchase tables, masters, login logs; never PIN/secret data - PINs are only in Supabase Auth). A failing table is recorded in `errors` and skipped; pagination kept; JSON has `row_counts`.
Not confirmed (mock only)
- Real Supabase run (only local Postgres 16 with auth mock). Rate-limit numbers 50/min and 200/min are anti-spam constants, not settings. Client does not yet show seconds_left (still shows the old locked message).
- set_unit_conversion (definer) still hard-deletes unit_conversions rows when told to; left as is (not client-direct).
Checks
- phase11_test.sql on fresh db: 62 pass / 0 fail. phase10_test.sql fresh with phase11: 307/0. phase8_test.sql: only the known 'T1 staff direct update rules'. phase11 run twice: no errors. Web tests: see task report.

#### W1 fixes after audit
- login_precheck now returns only {locked, seconds_left} (same shape for known/unknown ids; attempts_left removed). Spam caps lowered: 20 log rows/min per known id, 60/min global for unknown ids (constants). _login_setting_num cast is inside the jsonb_typeof guard.
- set_unit_conversion now retires (active=false) instead of deleting; readers already filter active.
- Owner accounts always auto-release their lock after lock_minutes, even if lockout_auto_release is off.
- BACKUP_TABLES + wastage_requests, supplier_refunds, sale_returns (phase12; phase13 creates no tables).
- phase8_test.sql: the stale `delete from invoice_templates` now expects 'permission denied'.
- User removal = retire the profile (profiles.status), never delete; deleting an auth user from the Supabase dashboard is blocked on purpose (profiles delete trigger).
- login_attempts grows without limit (nothing is deleted by design); at the 20 rows/min cap this is small, review yearly.

#### Known limits (W1)
1. The lockout guards the app's login screen only: the Supabase Auth endpoint can still be called directly with guessed PINs, and anyone can lock a known staff id by failing on purpose (an owner's lock self-releases after lock_minutes).
2. Real fix = Auth hook. phase11.sql contains public.hook_password_verification_attempt(event jsonb) (returns {decision: continue|reject}, uses login_failures; granted to supabase_auth_admin when that role exists). It is NOT enabled; the owner enables it in Supabase Dashboard > Authentication > Hooks > Password verification attempt. Not tested against a real Supabase Auth (only the function logic is tested locally).

### W0 items 6 + 13 (+16 partly): Day book and Salary report (supabase/phase13.sql, supabase/phase13_test.sql, web/daybook.js, web/salary.js)
Changed
- phase13.sql (additive, run twice OK, no new tables): grant `view_daybook` (grant_defs, window, emergency rule em_view_daybook off by default); rules `daybook_enabled` (switch, default ON) and `daybook_start` (text date, empty); set_daybook_start(date) owner-only RPC (validates; set_rule only checks "is a string").
- RPC `day_book(p_loc, p_from, p_to)` (SECURITY DEFINER, authenticated only): needs can_loc + has_grant('view_daybook', loc) per location (owner always); null location = every location the caller may see. Range max 366 days ('bad_range'). daybook_enabled off = owner only ('daybook_off'). Returns per day: open / in / out / close split cash / bank / mobile (+ total) and the lines (type, mode, amount, ref, text, who, time, source). Sources (real rows only, voided/draft/rejected excluded): POS sale_payments (sale + due collection; card counted as bank), supplier_payments (with or without bill), 10-2 expense vouchers (sum of line amounts, cash), 10-1 cash handover slips (notes count - float, cash, marked internal; counted as out in a single-location view, left out of all sums in the all-locations view because the hub side has no location on record), 02-3 advances (cash/bank/mobile only) and 02-2 salary receipt lines (cash/bank/mobile only; skips "owner's personal" and "other"). The two salary kinds need `salary_view` for that location, otherwise they are dropped and `salary_hidden` is true.
- Opening/closing = running total of counted lines from `daybook_start`; start empty (or the day is before it) = null = UI shows "Data needed". Nothing before the start date is assumed.
- RPC `salary_report(p_loc, p_month)`: owner or has_grant('salary_view', loc) + can_loc. Per person line of form 02-2 (month/year written on the form, else entry date; submitted/approved only): salary, work days, absent, leave, due, overtime, other, gross = due+overtime+other, adv_ded, other_ded, net = gross - both deductions (the form's own formulas), remark, paid/signed from the receipt list (matched by name inside the same sheet). Extra blocks: advances per 02-3 page (given / deducted this month, outstanding = sum of the form's balance column) and attendance per 02-1 (present, absent, late, leave, OT hours). No sheet for the month = data_needed.
- RPC `log_page_export(key, kind, filters, rows)` ('daybook' | 'salary'): owner or export_data (rpt_grant), plus view_daybook / salary_view, writes an audit_log row. The pages call it BEFORE building CSV/print and only build the file when it succeeds (server-side gate; the report data itself is gated by the first RPC).
- web/daybook.js: #/daybook (day list with edge markers, day sheet with type chips, per-line and per-day and page ⋮ menus: open source record, copy ref, CSV, print (reuses the #rp_print print CSS of reports.js), settings sheet for the owner (on/off switch, start date)). Filters: location, from/to (+ today / 7 days / month), mode cash / bank / mobile (client-side view of the server's per-mode figures). Accepts Bangla digits in the start date.
- web/salary.js: #/salary (month switch, per person rows, row sheet with every form field, advances + attendance blocks, ⋮ menu: CSV / print). No-permission follows ui_noperm_mode (lock card / hidden menu items).
- nav.js (additive): Accounting tile "Day book" is a live link (was 'coming soon'), routes daybook + salary in the route table/drawer (shown by owner or grant holders; grant flags loaded once with has_grant per location), label key `salary`. reports.js (additive): hub shows an "Other pages" section from `B.reportLinks` (day book, salary report) instead of forcing them into report_run. settings2.js (additive): `view_daybook` in the access manager's grant list. index.html: two script tags.
Decisions / deviations
- Not made report_run reports: the engine's catalogue lives in applied SQL (phase9 rpt_def); standalone pages linked from the hub instead.
- `daybook_enabled` off = nobody except the owner (grants alone do not bypass it).
- Day book cash = POS cash + imprest spending together (there is no separate drawer/imprest book); bank deposits (10-3 weekly figures), customer order advances and owner top-ups have no per-day data and are NOT included (stated in the page's "How this is counted").
- Salary names are free text, so receipt/paid is matched by name only inside the same sheet; advances and attendance are shown as separate blocks (never merged by guess).
Not confirmed (mock only)
- Real Supabase; PostgREST read-only transaction behaviour for these (day_book is VOLATILE plpgsql, no temp tables, so fine); real phone print/CSV download.
Checks
- phase13_test.sql on fresh db (also with phase11 applied): 56 pass / 0 fail, run twice OK. phase10_test.sql fresh with phase13: 0 fail; phase8_test: only the known 'T1 staff direct update rules'.
- tests/web/daybook_test.js and salary_test.js: errors none / 0 failures. Whole web list re-run: all pass except stock2 'photo stored as <form>/<loc>' which fails because another agent changed photo prefixes (STOCK/...); not related to this task. allforms/items2/purchase hit EADDRINUSE while other agents ran tests, passed on rerun.
- Manual SQL checks: location isolation (loc 3 data never visible to a loc-1 user), location-limited grants, role grant add/remove, anon refused, absurd/null dates refused.
