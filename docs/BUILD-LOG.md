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
