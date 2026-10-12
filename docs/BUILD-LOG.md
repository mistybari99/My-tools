# BUILD-LOG

One entry per task: what changed, what could NOT be confirmed, manual checks and results. Append, never overwrite others' entries.

## Carry-over checklist (HANDOVER §8)

- [x] 1. Items.details + apply_item_patch + Details field on item form
- [x] 2. Cost visible on items list for view_cost grant only (RPC gated by has_grant)
- [x] 3. Real low-stock status on items list/filter (stock_levels RPC, min_stock flag)
- [x] 4. Stock: category label list in stock_levels; purchase/sale unit list per item; item-name search in stock list
- [x] 5. Barcode scan on purchase-bill item field and stock actions
- [ ] 6. Home Accounting "Day book" tile
- [x] 7. Per-line stock-effect preview in purchase bill editor
- [x] 8. Photos for stock/purchase: dedicated STOCK / PURCHASE prefixes or grant-based photo_ok
- [x] 9. Emergency-rule keys for stock_count_adjust, stock_transfer, stock_issue, stock_production
- [x] 10. Wastage: manager approval above an owner-set limit (maker-checker)
- [x] 11. Supplier refund (cash back) alongside return credits; sale_return flow
- [x] 12. Expired batches: optional setting to block selling expired stock
- [ ] 13. Salary view / export_data grants: salary report page, server-side export grant
- [x] 14. stock_ledger.ref_id column grant leak: revoke column or null via view
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

### W0 carry-over items 1-5, 7-12, 14 (supabase/phase12.sql, supabase/phase12_test.sql, web/items2.js, stock2.js, purchase.js, barcode.js, new web/salereturn.js)
Changed
- 1 details: items.details (text, 2000 chars); apply_item_patch is wrapped, not copied (the old function is renamed `_apply_item_patch_base`, the new one calls it, then sets details; marker comment `bos12-details` makes re-runs a no-op and keeps columns another phase added). Item form: "Details" textarea in Advance options; approval screen label added.
- 2 cost for view_cost only: `items_with_cost()` (definer; owner / ITEM_COST view / has_grant('view_cost'); anon no execute). items2.js asks `has_grant('view_cost')` first, then the RPC; the cost field stays read-only and a save never sends cost. item_costs RLS untouched.
- 3 low stock: items list/filter use `stock_levels(null, {below_min:true})` (server flag, nothing computed in JS): edge marker + chip "Low stock now · qty unit", filter switch, chip. No min_stock = never flagged. Missing phase10 = no low-stock UI.
- 4 stock list: category shown by its item_categories label (filter too); per row "Buy: base, converted units · Sell: sell_units" from unit_conversions + items.sell_units (client side, no new numbers); search now covers code, Bangla/English/Bng-Eng name, category label, barcode (Bangla digits ok). Row ⋮ menu (ledger + allowed actions).
- 5 barcode: `B.barcode.scanItem(items)` / `enabled()`; scan button on the purchase bill line item field and on stock actions (opening, wastage, count, issue, production, transfer). Shown only when a scan option (camera/device) is on; unknown code = "No product has this barcode".
- 7 purchase line preview: under each line "+12 kg -> stock 35 kg at <location> · new average cost ৳ x" from stock_levels (that location) + unit conversions + the bill discount share; same formula as the server weighted average. Unknown conversion = "Data needed: unit conversion unknown"; stock>0 with the average hidden from this person = "Data needed (average cost not available)"; empty stock = the line cost; return = minus, average unchanged; untracked = "no stock effect".
- 8 photos: storage prefixes STOCK/<loc>/ and PURCHASE/<loc>/ (photo_ok re-created: STOCK enter = any stock grant, view = anyone at that location; PURCHASE enter = purchase_entry/return/supplier_pay, view = _pur_ok; all other prefixes unchanged). The web tries STOCK / PURCHASE first and falls back to the old form codes (04-1 / 06-4) if the server refuses, so a database without phase12 still works.
- 9 emergency keys: rules em_stock_count_adjust / em_stock_transfer / em_stock_issue / em_stock_production (+ em_sale_return) default OFF; grant_defs.emergency_rule filled for the four stock grants (only where still empty). The RPCs already used _may -> _use_em, so request / approve / use needs no code change.
- 10 wastage maker-checker: rule `wastage_approval_limit` (number in base unit, empty = off), grant `wastage_approve` (role management seeded once), table wastage_requests (RLS, audit), stock_wastage re-created (same behaviour + above-limit => pending request, yellow exception `wastage_pending`, result {pending:true}); `wastage_decide` (different person only, reject needs a note, approve posts the ledger rows now), `wastage_cancel`, `wastage_pending`. The owner is never held back. stock2.js: "Approvals" tab (shown to approvers or to a maker with a waiting request) with ⋮ per row (approve / reject / take back).
- 11a supplier refund: table supplier_refunds (RLS, audit); `supplier_refund` (grant supplier_pay or its emergency, only while balance<0 and never above the credit, idempotent client id), `void_supplier_refund` (purchase_void); `_sup_balance`, `_sup_open`, `supplier_ledger` re-created so a refund raises the balance and re-flows bill allocation; `supplier_credits()` lists suppliers that hold our credit. purchase.js: credit list on #/payables, ⋮ on bill rows / payables rows / credit rows, refund sheet, ledger refund rows with void.
- 11b sale return: table sale_returns, grant `sale_return` (management + showroom_manager seeded once), rule `sale_return_due_first` (default ON; off = refund everything), `sale_return` (per item <= sold - returned, value = qty x average sale price x sale total/subtotal, first off the customer's due, rest refunded cash/mobile/card, tracked items restocked into the batch they left at the cost they left with; return_reasons list; exception `sale_return`), `void_sale_return` (reverses the restock), `sale_returns_for`. customer_balance / customer_dues / customer_ledger re-created to subtract returns; voiding a sale that has a live return is refused (`sale_has_returns`). UI: new web/salereturn.js, route #/salereturn (+ /<sale id>), B.saleReturn.open(saleId).
- 12 `block_expired_sale` (switch, default OFF, module stock => appears in the Rules hub with no JS change). stock_post re-created (copy of phase10 + the check): ON refuses a sale that would need an expired batch (`expired_stock_blocked`, whole sale rolls back); a late-synced offline sale is never refused; OFF keeps the red 'sold_expired'.
- 14 stock_ledger: column privilege on ref_id removed (table SELECT revoked, explicit column list re-granted without ref_id). stock_ledger_rows (definer) unchanged and still gives ref_id to purchase people.
Decisions
- apply_item_patch wrapper instead of a copy (phase11 or later phases may add columns to the original; a copy would drop them).
- wastage limit is a quantity in the item base unit (like wastage_photo_above) because cost is secret.
- Supplier refund reuses the grant supplier_pay (and purchase_void for voiding) instead of a new grant: fewer switches; owner can still delegate per person.
- Sale return value = average sale price per item line x sale discount share (no price is invented); refund cash is only recorded on sale_returns (not in sale_payments) so POS / payment reports are not distorted - the cash-out of a refund is NOT yet in the day book or cash reports (see Not confirmed).
Not confirmed (mock only / open)
- Real Supabase; photo policy on the real storage.objects (only the mock + photo_ok function were tested); the web fallback to the old prefixes relies on upload returning an error.
- Sales reports (rpt_*) and sales.due_amount are NOT net of returns; the day book / cash drawer do not subtract cash refunds yet (sale_returns.refund_amount / refund_mode hold the data for the day book).
- pos.js (not mine) has no ⋮ entry for "Return goods" yet and shows a generic error for `expired_stock_blocked`; the sale-return page is reachable at #/salereturn (no nav tile yet).
- A sale return cannot be voided after its restocked goods were sold again (batch_short).
Checks
- phase12_test.sql: fresh db (phase8 9 10 12) 84 pass / 0 fail; also with phase11 + phase13 in either order; phase12 run twice OK. phase10_test.sql (two T11 lines edited: they read stock_ledger.ref_id as a normal user, which is now correctly refused; they now read it as the table owner) 0 fail with and without phase12; phase11_test / phase13_test 0 fail on a db with phase12; phase8_test only the known T1.
- web: items3_test, stock3_test, purchase3_test, salereturn_test (new) + items2 / barcode (extended) / stock2 / purchase (photo-path expectation changed to STOCK / PURCHASE) - see the final report for the full list result.

#### phase13 audit fixes (D1-D12)
- D1: running totals only cumulate rows dated >= daybook_start (test with the start inside the data range). Response now has net_open/net_close (running net since start) per day and in totals.
- D2: day_book no longer builds a giant jsonb: opening = one aggregate over [start, p_from-1]; lines only for the requested range; the line source function is plain (inlinable) SQL with timestamp-range predicates (index friendly). Timing on a scratch DB with 300,000 payments (2025-01..2026-08, 3 locations): 2-day query 0.18 s all-locations, 0.09 s one location.
- D3: owner-only set_daybook_opening(cash, bank, mobile) (rules daybook_open_*; empty = null). open/close (real balances) are returned only when all three are set AND the view is all-locations (the balances are business-wide); otherwise the page shows "Net since start" (never "Opening/Closing"). Warning chip on negative balances / net / days.
- D4: sale_returns.refund_amount (OUT by refund_mode) and supplier_refunds (IN) are included through _daybook_lines12 (plpgsql, guarded by to_regclass, so phase13 works without phase12). Note added to "How this is counted".
- D5 DECISION: cash handover slips (10-1) are INTERNAL transfers: always their own lines (chip, `internal`) and summed separately in `transfers` (day + totals) in both views; they are counted as cash OUT only in a single-location view (cash really left that showroom) and never in the all-locations in/out/net totals. The form records no hub location, so the hub-side IN cannot be booked ("hub receipt not recorded" note).
- D6: _db_num accepts thousands commas, leading/trailing dot, currency signs/spaces (৳, Tk, BDT), Bangla digits; result has skipped_rows (10-2 lines, 02-3 advances, 02-2 receipts whose amount text is not readable) and the page says "N lines could not be read".
- D7: CSV/print of a single day: totals, opening and closing are those of the selected day(s), with a "Scope" row ("whole period" or the dates); internal rows are marked in print.
- D8: banners for start after the period and for a start inside the period; labels switch between Opening/Closing and Net since start.
- D9: future-dated lines are not shown and `to` is capped at today (`capped` flag); salary_report reports duplicate_sheets (same location + month, >1 sheet) and marks same-name lines `ambiguous` (paid/signed not guessed; nothing is summed per name, every line stays separate).
- D10: range = at most 366 days inclusive (off-by-one fixed), infinite / pre-2000 / post-2100 dates and null give bad_range.
- D12: rule daybook_mask_names (default OFF; owner switch in the day book settings): non-owner holders get text/ref null and names_masked=true.
- D11 left as is (documented earlier): bank deposits (10-3) are not dated per day and not included.
- Tests: phase13_test.sql 76 pass / 0 fail (with phase12 installed; D4 block is skipped by \if when phase12 is absent); web tests extended.
