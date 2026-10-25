# C1 RLS / scope-isolation audit (READ-ONLY sizing for Stage C1)

Branch audited: `origin/ccr-9c1f9be7-3s9qnz` (HEAD `8583954`). Blueprint: `docs/GROUP_ERP_STAGE_A.md` (branch `ccr-46b26d91-81vl9s`), `docs/HANDOVER_6.md`.
Goal of this document: size what has to change so several fully separate businesses can live in ONE Supabase database with strict isolation. Nothing was edited or run against a database.

## 0. Method and honesty notes
- Static analysis only (no live DB). A script (kept outside the repo) parsed `supabase/schema.sql` + all 99 non-test `supabase/phase*.sql` files in phase order, split statements (dollar-quote aware), and applied "latest definition wins" for functions, policies, `alter table`, `grant/revoke`. `ALL_NEW*.sql` are concatenated copies and were excluded. `*_test.sql` excluded.
- Bodies wrapped in `do $pNNN$ ... execute $f$ ... $f$` (phase 85+ style) were expanded and parsed. Policies/RLS/revokes created in `do ... foreach t in array ...` loops were expanded per table (phase28/41/42/44/46/48/61/62/76/83/86/97). DDL written directly inside a DO body (e.g. `dash_layouts`, phase104.sql:41) was added by hand.
- Counts come from the script; they can be off by a few where SQL is written in an unusual shape. Everything not confirmed by reading the SQL is tagged **[unverified]**.
- Supabase assumption **[unverified]**: a table or function with no explicit REVOKE keeps the platform default grant to `authenticated`. For tables, "browser SELECT" below = not explicitly revoked. For functions, "exposed" = not explicitly revoked from `authenticated` (a bare `revoke ... from public, anon` leaves `authenticated` exposed under that assumption).
- Postgres semantics used: several permissive policies on one table are OR-ed, so the widest select policy decides. SECURITY DEFINER functions bypass RLS entirely, so for them the in-function gate is the only protection.

## 1. Headline numbers
| Measure | Count |
|---|---|
| public tables created (latest state, after drops) | **256** (all 256 have RLS enabled; 0 without) |
| Select policy = scoped by `can_loc` (directly, via a scope-aware helper, or via parent-table RLS) | **85** (81 direct/helper + 4 via parent RLS) |
| Readable by ANY active user (policy is `is_active()` only) | **44** |
| Permission-gated but NOT location-scoped (`has_grant(code)` / `can_do(form)` / `_acct_view()` ...; company-wide for every holder) | **46** (41 + 5 that only test `has_grant(code, loc)`, which a role grant satisfies at every location) |
| Owner-only select | 29 |
| Own-row select (`user_id = auth.uid()` etc.) | 19 |
| Closed to the browser (SELECT revoked, or RLS with no select policy; reachable only through SECURITY DEFINER functions) | 33 |
| Tables tagged global master data (items, customers, suppliers, recipes, coa ...) | 50 |
| Tables tagged global configuration (rules, grants, roles, settings ...) | 22 |
| Tables with a `location_id` (or `from_location_id`/`primary_location_id`) column | 96 |
| `business_id` / `org_unit_id` / tenant column anywhere | **0** (grep over all phase SQL, see section 8) |
| Functions defined (latest, all overloads) / SECURITY DEFINER | 1356 / 1145 |
| SECURITY DEFINER functions exposed to `authenticated` (see assumption) | 816 |
| ...of which call `can_loc` directly or transitively (inherit scope) | 387 |
| ...of which do NOT (gate = `is_owner` / `has_grant` / `can_do` / `is_active` / nothing) | 429; 179 of those read tables and do not write |
| Views in public (parsed) | at least 5 (`rpt_daily`, `rpt_pay`, `payment_recon_v`, `stock_ledger_eff96`, `opening_covered103`), none `security_invoker`, all REVOKEd from browser roles (phase9.sql:289, phase62.sql:404, phase96.sql:101, phase103.sql:109) |

Key structural finding: almost all location isolation hangs on ONE function, `can_loc()` (48 policy references and 210 functions call it directly). That makes the core of C1 (swap its internals to org-scope) cheap and high-leverage. The cost is in what does NOT call it: the 44 any-active tables, the 46 permission-only tables, global rules/grants, and the 179 unscoped reader functions.

## 2. Current definitions of the access primitives (latest definition wins)
| Function | Latest definition | What it does today |
|---|---|---|
| `is_active()` | supabase/schema.sql:139 | `profiles.status='active'` for `auth.uid()`. No business notion. |
| `is_owner()` | supabase/schema.sql:144 | active AND has `user_roles.role_code='owner'`. One global owner = every business. Used by 110 policy expressions. |
| `can_loc(p_loc)` | supabase/phase7.sql:277-284 (supersedes phase2.sql:64) | active AND ( `is_owner()` OR **role `management`** OR row in `user_locations` OR approved `loc_access` emergency window for that location ). `p_loc = null` is true only for owner/management. |
| `_all_locs()` | supabase/phase10.sql:250-253 | active AND (`is_owner()` OR **role `management`**). Used by `_pur_ok(null)`, `_cs_src_ok`, `cost_share_reassign` and `location_cost_attribution` policies. |
| `_acct_all()` | supabase/phase40.sql:150 | `can_loc(null)` OR `has_grant('accounts_manage')`: owner/management or any accounts manager sees ALL journals incl. rows with `location_id is null`. |
| `_acct_view()` | supabase/phase40.sql:141 | owner OR `has_grant('accounts_view'/'accounts_manage')` at ANY location (`exists location l ... has_grant(.., l.id)`). Not scoped. |
| `has_grant(code, loc)` | supabase/phase8.sql:93-103 | owner OR ( active AND ( `can_grant(code)` [role-level, **global**] OR personal `user_grants` row with `location_id is null` or `= loc` OR approved emergency window ) ). With `p_loc` null any location-less personal grant or ANY window counts (deliberate, comment at phase8.sql:84-91). |
| `can_grant(code)` | supabase/phase7.sql:125 | role -> `rule_grants` table; global, no location. |
| `can_do(form, action)` | supabase/phase7.sql:262 | role x form matrix (`role_form_perms`), global, no location; location is checked separately by `can_loc`. |
| `user_locations` | table supabase/schema.sql:39 (`user_id`, `location_id`); RLS select = own rows or owner (see `user_locations` policy) | The only place a normal user is bound to places. |
| `biz_ok()` / `biz_cost_ok()` | supabase/phase8.sql:105 / :109 | report / cost visibility: owner OR POS-approve OR `has_grant('view_reports'/'view_cost'/'view_profit')`, no location. |
| `rule_val/rule_on/rule_num/rule_txt` | supabase/phase7.sql:30-45 | reads the single global `rules` row by key; ~695 call-site lines across phase SQL (grep `rule_(on|txt|num|val)\(`). |

## 3. Where the `management` role (and `owner`) bypasses `can_loc`
Current-definition sites (latest wins):
| # | Evidence | Effect |
|---|---|---|
| 1 | supabase/phase7.sql:281 (`can_loc`) | `management` passes `can_loc` for every location id (and null). Every policy/RPC using `can_loc` therefore shows ALL businesses' rows to management. |
| 2 | supabase/phase10.sql:252 (`_all_locs`) | `management` = "all locations" for purchases (`_pur_ok(null)`), cost sources, cost attribution. |
| 3 | supabase/phase40.sql:150 (`_acct_all` -> `can_loc(null)`) | management/owner read the whole journal incl. null-location rows. |
| 4 | supabase/phase46.sql:93 (`_notif_ok`) | management is in the "manager" audience list, company-wide notifications. |
| 5 | supabase/phase47.sql:354 (`assistant_health`) | management excluded from an "unassigned staff" health check (counts as top-level). |
| 6 | supabase/phase8.sql:96 -> `can_grant` (phase7.sql:125) | role-level grants seeded to `management` apply at every location: phase10.sql:51-52, phase12.sql:74-75, phase14.sql:90, phase41.sql:78 (`employee_view`), phase42.sql:72 (`attendance_manage`), phase60.sql:29, phase90.sql:57-58 (`scan_upload/scan_confirm`), phase97.sql:120 (`landed_entry/approve`). |
| 7 | supabase/schema.sql:630-671+ and phase3.sql:10 (`role_form_perms` rows for `management`) | form permissions of management are global (not itself a bypass but combined with #1 = all places). |
| 8 | `is_owner()` schema.sql:144 and every `... or public.is_owner()` clause | one owner role sees everything; correct for a *group* owner, wrong for a per-business owner. 110 uses in policies. |
| 9 | web (UI only, not security): `web/ia.js`, `web/biz.js`, `web/dash.js`, `web/daybook.js`, `web/dues.js`, `web/entry.js`, `web/filters.js`, `web/flow.js`, `web/forms_stock.js`, `web/attend2.js` contain the literal `'management'` | UI gating that must follow the new scope model [unverified what each does]. |

Non-bypass but related: `emergency_requests` windows (`loc_access`, `form_access`) can grant temporary location access (phase7.sql:282-283); `has_grant` windows with `p_loc` null count for any location.

## 4. Table inventory
Policy file:line is the select policy that decides exposure (latest definition). Full per-table matrix: Appendix A.

### 4.1 Scoped by `can_loc` (85 tables) - good, inherit the C1 swap

- `assets` (phase14.sql:752) policy `assets_read` phase14.sql:790 [loc]
- `att_evidence_reg` (phase54.sql:54) policy `att_evidence_reg_read` phase54.sql:97
- `att_mark_log54` (phase54.sql:65) policy `att_mark_log54_read` phase54.sql:99 [loc]
- `attendance_days` (phase42.sql:127) policy `attendance_days_read` phase42.sql:338 [loc]
- `attendance_devices` (phase42.sql:104) policy `attendance_devices_read` phase42.sql:331 [loc]
- `attendance_import_batches` (phase42.sql:110) policy `attendance_import_batches_read` phase42.sql:333 [loc]
- `attendance_punches` (phase42.sql:116) policy `attendance_punches_read` phase42.sql:335 [loc]
- `bill_payments99` (phase99.sql:108) policy `bill_payments99_sel` phase99.sql:140 [loc]
- `budgets` (phase53.sql:120) policy `bud_read` phase53.sql:192 [loc]
- `card_settlements85` (phase85.sql:121) policy `card_settlements85_sel` phase85.sql:132 [loc]
- `cash_moves` (phase23.sql:233) policy `cash_moves_read` phase23.sql:255 [loc]
- `comparison_days` (phase28.sql:34) policy `(dynamic DO)` phase28.sql:58 [loc]
- `cost_bill_inputs` (phase75.sql:110) policy `cs_inp_read` phase75.sql:173 [loc]
- `cost_bill_shares` (phase75.sql:117) policy `cs_shr_read` phase75.sql:174 [loc]
- `cost_share_reassign` (phase78.sql:74) policy `csr78_read` phase78.sql:141
- `cost_source_bills` (phase75.sql:91) policy `cs_bills_read` phase75.sql:172
- `cost_source_locs` (phase75.sql:61) policy `cs_locs_read` phase75.sql:169 [loc]
- `cost_source_rule_shares` (phase75.sql:81) policy `cs_rsh_read` phase75.sql:171 [loc]
- `cost_source_rules` (phase75.sql:68) policy `cs_rules_read` phase75.sql:170
- `cost_sources` (phase75.sql:45) policy `cs_src_read` phase75.sql:168
- `deed_templates` (phase41.sql:207) policy `deed_templates_read` phase41.sql:381
- `employee_advance_recoveries` (phase42.sql:189) policy `employee_advance_recoveries_read` phase42.sql:344
- `employee_advances` (phase42.sql:151) policy `employee_advances_read` phase42.sql:342 [loc]
- `employee_benefit_grants` (phase61.sql:414) policy `employee_benefit_grants_sel` phase61.sql:651
- `employee_benefits` (phase41.sql:192) policy `employee_benefits_read` phase41.sql:373
- `employee_deeds` (phase41.sql:212) policy `employee_deeds_read` phase41.sql:383
- `employee_documents` (phase41.sql:164) policy `employee_documents_read` phase41.sql:366
- `employee_leave_entitlements` (phase41.sql:201) policy `employee_leave_read` phase41.sql:375
- `employee_locations` (phase41.sql:155) policy `employee_locations_read` phase41.sql:362 [loc]
- `employee_pay` (phase41.sql:173) policy `employee_pay_read` phase41.sql:368
- `employee_pay_components` (phase41.sql:183) policy `employee_pay_components_read` phase41.sql:370
- `employee_shift_assignments` (phase42.sql:89) policy `esa_read` phase42.sql:327
- `employee_status_log` (phase41.sql:159) policy `employee_status_log_read` phase41.sql:364
- `employees` (phase41.sql:128) policy `employees_read` phase41.sql:348 [loc]
- `entries` (phase2.sql:21) policy `entries_read` phase2.sql:286 [loc]
- `entry_change_requests` (phase17.sql:449) policy `entry_change_read` phase17.sql:475
- `entry_count_seals` (phase23.sql:497) policy `entry_count_seals_read` phase23.sql:509
- `entry_ledger_posts` (phase20.sql:42) policy `entry_ledger_posts_read` phase20.sql:69 [loc]
- `exceptions` (phase2.sql:39) policy `exceptions_read` phase3.sql:145 [loc]
- `fa_assets` (phase53.sql:92) policy `fa_read` phase53.sql:188 [loc]
- `factory_cost_pools` (phase74.sql:72) policy `fcp_read` phase74.sql:137 [loc]
- `grn_batch_links` (phase60.sql:54) policy `grn_batch_links_read` phase60.sql:104 [loc]
- `inbound_message_events` (phase76.sql:107) policy `inbound_message_events_sel` phase76.sql:754
- `inbound_messages` (phase76.sql:90) policy `inbound_messages_sel` phase76.sql:753 [loc]
- `journal_entries` (phase40.sql:59) policy `je_read` phase40.sql:174 [loc]
- `journal_lines` (phase40.sql:79) policy `jl_read` phase40.sql:176 [loc]
- `leave_requests` (phase42.sql:141) policy `leave_requests_read` phase42.sql:340
- `location_cost_attribution` (phase78.sql:46) policy `lca_read` phase78.sql:139 [loc]
- `location_cost_cfg` (phase74.sql:90) policy `lcc_read` phase74.sql:139 [loc]
- `notifications` (phase46.sql:42) policy `notifications_read` phase46.sql:102 [loc]
- `online_order_events` (phase61.sql:64) policy `online_order_events_sel` phase61.sql:647
- `online_order_flags` (phase77.sql:26) policy `online_order_flags_sel` phase77.sql:213 [loc]
- `online_orders` (phase61.sql:36) policy `online_orders_sel` phase61.sql:646 [loc]
- `order_dup_flags` (phase76.sql:127) policy `order_dup_flags_sel` phase76.sql:756 [loc]
- `parallel_months` (phase28.sql:49) policy `(dynamic DO)` phase28.sql:58 [loc]
- `payroll_bonus_events` (phase42.sql:159) policy `payroll_bonus_events_read` phase42.sql:347 [loc]
- `payroll_lines` (phase42.sql:172) policy `payroll_lines_read` phase42.sql:351 [loc]
- `payroll_payments` (phase42.sql:196) policy `payroll_payments_read` phase42.sql:353 [loc]
- `payroll_runs` (phase42.sql:165) policy `payroll_runs_read` phase42.sql:349 [loc]
- `pos_failed_cards` (phase83.sql:599) policy `pos_failed_cards_sel` phase83.sql:632 [loc]
- `pos_replay_log` (phase83.sql:614) policy `pos_replay_log_sel` phase83.sql:634 [loc]
- `production_runs` (phase19.sql:79) policy `production_runs_read` phase19.sql:155 [loc]
- `purchase_bills` (phase10.sql:151) policy `purchase_bills_read` phase10.sql:1354 [loc]
- `purchase_lines` (phase10.sql:178) policy `purchase_lines_read` phase10.sql:1356
- `qc_records` (phase60.sql:70) policy `qc_records_read` phase60.sql:106 [loc]
- `quick_expenses` (phase50.sql:120) policy `quick_expenses_sel` phase50.sql:149 [loc]
- `sale_form_links` (phase61.sql:283) policy `sale_form_links_sel` phase61.sql:649 [loc]
- `sale_payments` (phase6.sql:43) policy `sale_payments_read` phase6.sql:442 [loc]
- `sale_return_packaging80` (phase80.sql:117) policy `srp80_read` phase80.sql:132 [loc]
- `sale_returns` (phase12.sql:488) policy `sale_returns_read` phase12.sql:512 [loc]
- `sale_tier_use` (phase43.sql:199) policy `stu_read` phase43.sql:225
- `sales` (phase3.sql:16) policy `sales_read` phase3.sql:140 [loc]
- `shadow_links` (phase48.sql:61) policy `shadow_links_sel` phase48.sql:103 [loc]
- `stock_balance` (phase10.sql:111) policy `stock_balance_read` phase10.sql:1348 [loc]
- `stock_batches` (phase10.sql:73) policy `stock_batches_read` phase10.sql:1344 [loc]
- `stock_ledger` (phase10.sql:88) policy `stock_ledger_read` phase10.sql:1346 [loc]
- `stock_transfers` (phase10.sql:134) policy `stock_transfers_read` phase10.sql:1352 [loc]
- `stock_wastage` (phase10.sql:120) policy `stock_wastage_read` phase10.sql:1350 [loc]
- `supplier_payments` (phase10.sql:194) policy `supplier_payments_read` phase10.sql:1359 [loc]
- `supplier_refunds` (phase12.sql:350) policy `supplier_refunds_read` phase12.sql:368 [loc]
- `wastage_requests` (phase12.sql:193) policy `wastage_requests_read` phase12.sql:212 [loc]
- `entry_counts` (phase18.sql:101) policy `entry_counts_read` phase18.sql:136 via entries
- `entry_revisions` (phase17.sql:424) policy `entry_revisions_read` phase17.sql:444 via entries
- `entry_signatures` (phase18.sql:373) policy `entry_signatures_read` phase18.sql:390 via entries
- `fa_depr_posts` (phase53.sql:109) policy `fadp_read` phase53.sql:190 via fa_assets

Caveat for this group: scoping is only as strong as `can_loc`, which today lets owner and management through for every location, and which accepts any `user_locations` row without knowing which business the location belongs to. After B1 (locations -> org_units) a single swap in `can_loc` should make all 85 tables business-safe; this still needs the negative tests in section 9.

### 4.2 Readable by ANY active user - LEAK RISK between businesses (44 tables)
Policy is `public.is_active()` only (supabase evidence per line). Any logged-in staff member of business B can `select *` these through PostgREST.

- `att_site_geo` (phase54.sql:49) policy `att_site_geo_read` phase54.sql:95 [has location_id]
- `benefit_types` (phase61.sql:402) policy `benefit_types_sel` phase61.sql:650 [MASTER]
- `blind_count_cfg` (phase18.sql:34) policy `blind_count_cfg_read` phase18.sql:49 [has location_id]
- `comparison_pairs` (phase28.sql:26) policy `(dynamic DO)` phase28.sql:58
- `cost_charge_types` (phase97.sql:148) policy `cct_read97` phase97.sql:164 [MASTER]
- `cost_component_types` (phase74.sql:33) policy `cost_types_read` phase74.sql:133 [MASTER]
- `customer_tiers` (phase43.sql:20) policy `customer_tiers_read` phase43.sql:73 [MASTER]
- `doc_template_choice` (phase93.sql:17) policy `doc_template_choice_read` phase93.sql:30 [has location_id] [MASTER]
- `form_rollout` (phase17.sql:52) policy `form_rollout_read` phase17.sql:62 [has location_id]
- `forms` (schema.sql:45) policy `forms_read` schema.sql:464 [MASTER]
- `forms_ledger_cfg` (phase20.sql:27) policy `forms_ledger_cfg_read` phase20.sql:37 [CONFIG]
- `gift_rules` (phase43.sql:153) policy `gift_rules_read` phase43.sql:221 [MASTER]
- `grant_defs` (phase7.sql:94) policy `grant_defs_read` phase7.sql:104 [CONFIG]
- `grant_separation_pairs` (phase78.sql:94) policy `gsp_read` phase78.sql:142 [CONFIG]
- `holidays` (phase42.sql:97) policy `holidays_read` phase42.sql:329 [has location_id]
- `invoice_templates` (phase8.sql:389) policy `invtpl_read` phase8.sql:431 [has location_id] [MASTER]
- `item_categories` (phase100.sql:53) policy `item_categories_read100` phase100.sql:76 [MASTER]
- `item_class_map` (phase14.sql:42) policy `item_class_map_read` phase14.sql:646 [MASTER]
- `item_master_links` (phase14.sql:623) policy `item_master_links_read` phase14.sql:642 [MASTER]
- `item_types` (phase14.sql:33) policy `item_types_read` phase14.sql:644 [MASTER]
- `items` (schema.sql:66) policy `items_read` schema.sql:470 [MASTER]
- `leave_types` (phase41.sql:113) policy `leave_types_read` phase41.sql:379 [MASTER]
- `list_defs` (phase15.sql:29) policy `list_defs_read` phase15.sql:43 [MASTER]
- `location_settings` (phase2.sql:7) policy `locset_read` phase2.sql:284 [has location_id]
- `locations` (schema.sql:31) policy `locations_read` schema.sql:458
- `option_lists` (phase6.sql:412) policy `option_lists_read` phase6.sql:421 [MASTER]
- `path_domains` (phase48.sql:17) policy `path_domains_sel` phase48.sql:101 [CONFIG]
- `path_switch` (phase48.sql:47) policy `path_switch_sel` phase48.sql:102 [has location_id]
- `pin_sig_cfg` (phase18.sql:41) policy `pin_sig_cfg_read` phase18.sql:51 [CONFIG]
- `print_profiles` (phase8.sql:410) policy `printprof_read` phase8.sql:433 [has location_id] [MASTER]
- `report_brand_map` (phase9.sql:33) policy `report_brand_map_read` phase9.sql:44 [has location_id] [MASTER]
- `report_defs3` (phase24.sql:8) policy `report_defs3_read` phase24.sql:22 [CONFIG]
- `role_favourites` (phase8.sql:501) policy `rolefav_read` phase8.sql:509 [CONFIG]
- `role_form_perms` (schema.sql:56) policy `perms_read` schema.sql:467 [CONFIG]
- `roles` (schema.sql:17) policy `roles_read` schema.sql:452 [CONFIG]
- `rule_grants` (phase7.sql:89) policy `rule_grants_read` phase7.sql:103 [CONFIG]
- `rules` (phase7.sql:12) policy `rules_read` phase7.sql:27 [CONFIG]
- `sales_channels` (phase76.sql:55) policy `sales_channels_sel` phase76.sql:752 [has location_id]
- `settings` (schema.sql:106) policy `settings_read` schema.sql:478 [CONFIG]
- `settings_keys` (phase16.sql:492) policy `settings_keys_read` phase16.sql:498 [CONFIG]
- `shelf_life_rules` (phase8.sql:329) policy `shelf_read` phase8.sql:350 [MASTER]
- `shifts` (phase42.sql:76) policy `shifts_read` phase42.sql:325 [has location_id]
- `staff_roles` (phase41.sql:94) policy `staff_roles_read` phase41.sql:377 [MASTER]
- `unit_conversions` (phase8.sql:262) policy `unit_conv_read` phase8.sql:278 [MASTER]

Highest concern inside this group (business-identifying or business-specific content):
- `locations` (names, kinds, status, `supplied_by`, `hub_functions`) - lists every site of every business.
- `location_settings`, `att_site_geo` (GPS geofence of each site), `holidays`, `shifts`, `sales_channels`, `path_switch`, `form_rollout`, `blind_count_cfg`, `doc_template_choice`, `invoice_templates`, `print_profiles`, `report_brand_map` - have a `location_id` column but the policy ignores it.
- `items` (1,312 rows per Stage A, sell_price, wholesale_price, barcode), `item_categories`, `item_types`, `option_lists` (supplier/expense/etc. dropdown values), `unit_conversions`, `shelf_life_rules`, `customer_tiers`, `gift_rules`: master/reference data readable by everyone.
- `rules`, `rule_grants`, `grant_defs`, `roles`, `role_form_perms`, `settings`, `forms`: the global switchboard (section 6).

### 4.3 Permission-gated but not location-scoped - company-wide for any grant holder (
46 tables)
These become cross-business the moment one person (or one role such as `management`, `purchasing`, accountant) holds the grant for two businesses, and `has_grant(code)` with no location is satisfied by a role grant everywhere. Tables with a `location_id` column are marked [loc] - the column exists but the policy does not use it.

- `acct_mappings` (phase40.sql:52) policy `acct_map_read` phase40.sql:172 [MASTER]
- `artisans` (phase73.sql:44) policy `artisans_read` phase73.sql:169 [loc] [MASTER]
- `asset_costs` (phase14.sql:769) policy `asset_costs_read` phase14.sql:792 [MASTER]
- `assistant_notes` (phase47.sql:70) policy `assistant_notes_read` phase47.sql:86
- `bank_recon_matches` (phase53.sql:56) policy `brm_read` phase53.sql:182
- `bank_recon_trail` (phase53.sql:70) policy `brt_read` phase53.sql:184
- `bank_statement_lines` (phase53.sql:40) policy `bsl_read` phase53.sql:180
- `budget_log` (phase53.sql:129) policy `budlog_read` phase53.sql:194 [loc]
- `client_errors` (phase107.sql:49) policy `client_errors_read107` phase107.sql:83
- `coa_accounts` (phase40.sql:35) policy `coa_read` phase40.sql:170 [MASTER]
- `cost_attrib_main` (phase78.sql:62) policy `cam_read` phase78.sql:140 [loc]
- `cost_source_types` (phase75.sql:28) policy `cs_types_read` phase75.sql:167 [MASTER]
- `customer_gifts` (phase43.sql:173) policy `cg_read` phase43.sql:223 [MASTER]
- `customer_points_ledger` (phase43.sql:131) policy `cpl_read` phase43.sql:219 [MASTER]
- `customer_tier_history` (phase43.sql:114) policy `cth_read` phase43.sql:217 [MASTER]
- `customers` (phase6.sql:22) policy `customers_read` phase6.sql:440 [MASTER]
- `item_bulk_batches` (phase22.sql:26) policy `item_bulk_batches_read` phase22.sql:39 [MASTER]
- `item_changes` (schema.sql:88) policy `item_changes_read` phase14.sql:390 [MASTER]
- `item_cost_flags` (phase80.sql:40) policy `item_cost_flags_read` phase80.sql:49 [MASTER]
- `item_costs` (schema.sql:80) policy `item_costs_read` schema.sql:473 [MASTER]
- `item_map_actions` (phase22.sql:216) policy `item_map_actions_read` phase22.sql:226 [MASTER]
- `item_mapping_review` (phase14.sql:616) policy `item_mapping_review_read` phase14.sql:640 [MASTER]
- `item_price_history` (schema.sql:98) policy `price_history_read` schema.sql:476 [MASTER]
- `manual_reason_codes85` (phase85.sql:104) policy `manual_reason_codes85_sel` phase85.sql:111 [CONFIG]
- `notify_optin` (phase62.sql:70) policy `(dynamic DO)` phase62.sql:105
- `notify_optin_log` (phase62.sql:80) policy `(dynamic DO)` phase62.sql:105
- `notify_outbox` (phase62.sql:84) policy `(dynamic DO)` phase62.sql:105
- `notify_templates` (phase62.sql:62) policy `(dynamic DO)` phase62.sql:105 [MASTER]
- `payment_intents` (phase62.sql:262) policy `(dynamic DO)` phase62.sql:289 [loc]
- `payment_webhook_log` (phase62.sql:278) policy `(dynamic DO)` phase62.sql:289
- `product_packaging` (phase19.sql:68) policy `product_packaging_read` phase19.sql:153 [MASTER]
- `recipe_cost_components` (phase74.sql:56) policy `rcc_read` phase74.sql:135 [MASTER]
- `recipe_lines` (phase19.sql:54) policy `recipe_lines_read` phase19.sql:151 [MASTER]
- `recipe_steps` (phase73.sql:100) policy `recipe_steps_read` phase73.sql:171 [MASTER]
- `recipe_versions` (phase73.sql:121) policy `recipe_versions_read` phase73.sql:173 [MASTER]
- `recipes` (phase19.sql:40) policy `recipes_read` phase19.sql:149 [MASTER]
- `setup_check_defs81` (phase81.sql:44) policy `setup_check_defs81_sel` phase81.sql:526 [CONFIG]
- `setup_rec_defs81` (phase81.sql:32) policy `setup_rec_defs81_sel` phase81.sql:524 [CONFIG]
- `setup_topic_defs81` (phase81.sql:56) policy `setup_topic_defs81_sel` phase81.sql:528 [CONFIG]
- `suppliers` (phase8.sql:152) policy `suppliers_read` phase8.sql:169 [MASTER]
- `year_closes` (phase53.sql:79) policy `yc_read` phase53.sql:186
- `location_setup_steps` (phase16.sql:121) policy `loc_steps_read` phase16.sql:131 [loc] [weak: has_grant(code, loc) only]
- `paper_books` (phase28.sql:192) policy `(dynamic DO)` phase28.sql:211 [loc] [weak: has_grant(code, loc) only]
- `print_notes` (phase28.sql:203) policy `(dynamic DO)` phase28.sql:211 [loc] [weak: has_grant(code, loc) only]
- `settings_sheets` (phase16.sql:570) policy `settings_sheets_read` phase16.sql:596 [loc] [weak: has_grant(code, loc) only]
- `settings_values` (phase16.sql:587) policy `settings_values_read` phase16.sql:598 [weak: has_grant(code, loc) only]

### 4.4 Owner-only (29), own-row (19), closed to browser (33)
Owner-only tables are safe from other businesses' staff but expose everything to the single global owner (acceptable for a group owner; must become "owner of this business" if a business owner is introduced). Closed tables hold business data reachable only via SECURITY DEFINER functions, so their isolation depends entirely on section 5.

**Owner-only:** `agreement_parties`, `assistant_usage`, `att_self_lock`, `audit_log`, `backup_runs`, `bi_export_log`, `entry_count_peeks`, `inbox_unmask_log99`, `item_import_batches`, `location_block_overrides`, `login_attempts`, `login_failures`, `ops_accounts`, `partner_agreements`, `partner_capital`, `partner_parties`, `partner_rules`, `partner_settlement_lines`, `partner_settlement_payments`, `partner_settlements`, `partner_templates`, `partner_ventures`, `perm_conflict`, `perm_reco_ignore`, `perm_reco_role`, `restore_drills`, `role_option_view`, `setup_apply_batches81`, `setup_apply_lines81`

**Own-row:** `corrections`, `dash_layouts`, `emergency_requests`, `flow_skips`, `list_managers`, `list_other_entries`, `notification_reads`, `option_requests`, `owner_board_items`, `profiles`, `release_requests`, `report_views`, `scan_events`, `scan_jobs`, `user_favourites`, `user_grants`, `user_locations`, `user_option_view`, `user_roles`
Note: `emergency_requests` and `release_requests` also admit `can_grant('emergency_decide')` / `_release_can_see` holders (global role grants); `user_grants` shows own or owner. `profiles` own-or-owner but see `staff_directory()` in section 5.

**Closed (no browser read):** `acct_autopost_runs85`, `acct_post_errors72`, `bill_pay_defaults99`, `bos_salt105`, `client_error_hits107`, `client_error_seen107`, `drawer_events`[loc], `intake_bots`, `intake_failures`, `intake_hits`, `intake_proofs94`, `invoice_shares`[loc], `item_logistics`, `landed_cost_alloc`[loc], `landed_cost_basis`, `landed_cost_docs`, `landed_cost_lines`, `landed_cost_stock`[loc], `landed_costs`[loc], `landed_skips`, `landed_supplier_flags`, `ledger_cost_supply96`, `login_throttle`, `opening_stock_actions96`[loc], `opening_stock_followups103`, `option_view_ops`, `pool_gl_posts117`, `production_reprice116`, `recipe_std116`[loc], `sales_fact_t`[loc], `serials`[loc], `telegram_chat_links`, `telegram_secrets`

### 4.5 Global master data (no owner-unit scope at all)
These are shared across the whole database today; two businesses would share one item list, one customer list (note `customers.mobile` is `unique`, supabase/phase6.sql:23, and `items.code` is `unique` with a global sequence, supabase/schema.sql:68), one supplier list, one chart of accounts (phase40.sql:35, no legal-entity column) and one set of recipes. Stage A already plans an explicit `scope` column (group | legal_entity | business | location) for them (C2); C1 must at least stop cross-business reads.

- `acct_mappings`: class PERM (phase40.sql:52)
- `artisans`: class PERM [loc] (phase73.sql:44)
- `asset_costs`: class PERM (phase14.sql:769)
- `benefit_types`: class ANY (phase61.sql:402)
- `coa_accounts`: class PERM (phase40.sql:35)
- `cost_charge_types`: class ANY (phase97.sql:148)
- `cost_component_types`: class ANY (phase74.sql:33)
- `cost_source_types`: class PERM (phase75.sql:28)
- `customer_gifts`: class PERM (phase43.sql:173)
- `customer_points_ledger`: class PERM (phase43.sql:131)
- `customer_tier_history`: class PERM (phase43.sql:114)
- `customer_tiers`: class ANY (phase43.sql:20)
- `customers`: class PERM (phase6.sql:22)
- `deed_templates`: class SCOPED (phase41.sql:207)
- `doc_template_choice`: class ANY [loc] (phase93.sql:17)
- `employees`: class SCOPED [loc] (phase41.sql:128)
- `forms`: class ANY (schema.sql:45)
- `gift_rules`: class ANY (phase43.sql:153)
- `invoice_templates`: class ANY [loc] (phase8.sql:389)
- `item_bulk_batches`: class PERM (phase22.sql:26)
- `item_categories`: class ANY (phase100.sql:53)
- `item_changes`: class PERM (schema.sql:88)
- `item_class_map`: class ANY (phase14.sql:42)
- `item_cost_flags`: class PERM (phase80.sql:40)
- `item_costs`: class PERM (schema.sql:80)
- `item_import_batches`: class OWNER (phase14.sql:504)
- `item_logistics`: class CLOSED (phase97.sql:280)
- `item_map_actions`: class PERM (phase22.sql:216)
- `item_mapping_review`: class PERM (phase14.sql:616)
- `item_master_links`: class ANY (phase14.sql:623)
- `item_price_history`: class PERM (schema.sql:98)
- `item_types`: class ANY (phase14.sql:33)
- `items`: class ANY (schema.sql:66)
- `leave_types`: class ANY (phase41.sql:113)
- `list_defs`: class ANY (phase15.sql:29)
- `notify_templates`: class PERM (phase62.sql:62)
- `option_lists`: class ANY (phase6.sql:412)
- `partner_templates`: class OWNER (phase44.sql:135)
- `print_profiles`: class ANY [loc] (phase8.sql:410)
- `product_packaging`: class PERM (phase19.sql:68)
- `recipe_cost_components`: class PERM (phase74.sql:56)
- `recipe_lines`: class PERM (phase19.sql:54)
- `recipe_steps`: class PERM (phase73.sql:100)
- `recipe_versions`: class PERM (phase73.sql:121)
- `recipes`: class PERM (phase19.sql:40)
- `report_brand_map`: class ANY [loc] (phase9.sql:33)
- `shelf_life_rules`: class ANY (phase8.sql:329)
- `staff_roles`: class ANY (phase41.sql:94)
- `suppliers`: class PERM (phase8.sql:152)
- `unit_conversions`: class ANY (phase8.sql:262)

Global uniqueness constraints that leak across businesses (existence oracle / collision): `customers.mobile unique` (phase6.sql:23), `items.code unique` (schema.sql:68), `items_barcode_uq` (phase8.sql:217), `profiles.staff_id` / login throttle keyed by `staff_id` (schema.sql:130-136), `client_id` idempotency keys on most write tables [unverified full list].

## 5. SECURITY DEFINER functions that read or return company-wide data without `can_loc`

Method: for each latest SECURITY DEFINER function, exposure = not revoked from `authenticated`; "scope-aware" = calls `can_loc` directly or through a helper that does (fixpoint over the call graph). 429 exposed functions are not scope-aware; Appendix B lists every one that reads a table (179 pure readers). Many are fine (owner-only admin, own-row, config). The following were READ and confirmed to return company-wide business data with a gate that does not involve location:

| Function | Evidence | Gate today | What it returns |
|---|---|---|---|
| `customer_dues()` | supabase/phase105.sql:335 (earlier phase12.sql:539; netted variant `customer_dues_net113` phase113.sql:603) | `can_do('POS', ...)` | every customer's outstanding balance computed from ALL `sales`/`sale_payments`/`sale_returns` of every location (bypasses the `sales` can_loc RLS). |
| `customer_ledger(uuid)` | supabase/phase12.sql:556 | `can_do('POS', ...)` | full sales/collections ledger of a customer across all locations; customers are global so any POS user can pull any customer. |
| `find_customer` | supabase/phase103.sql:1163 | `can_do` | global customer lookup by mobile/name. |
| `fa_register(date)`, `fa_schedule(uuid)` | supabase/phase53.sql:748, :689 | `_acct_view()` only | all fixed assets with cost/accumulated depreciation of every location (table policy is scoped, the RPC is not). |
| `year_close_list()` | supabase/phase53.sql:533 | `_acct_view()` | all year-close records. |
| `items_with_cost()`, `item_cost_status88()`, `item_cost_flags_list` | supabase/phase88.sql:228, :242; phase80.sql:75 | `can_do('ITEM_COST')` / `view_cost` at ANY location (comment phase88.sql: "the list is company wide, so any location grant is enough") | cost price of every item. |
| `drawer_report(date,date)` | supabase/phase95.sql:140 | `is_owner() or has_grant('view_reports')` | drawer open/close events for ALL locations (reads `drawer_events`, a closed table). |
| `staff_directory()` | supabase/phase2.sql:96 | `is_active()` | id / staff_id / full name of every active staff member of every business. |
| `count_unsubmitted_scan()` | supabase/phase18.sql:236 | `is_active()` | INSERTs red `exceptions` for every location's unsubmitted counts, any active user can fire it. |
| `control_counts()` | supabase/phase16.sql:884 | `is_active()` + counts per grant | counts of pending items/requests across locations for grant holders. |
| `partner_*` (overview, calculate, statements) | supabase/phase44.sql:1092 etc., guard `_a44_guard` phase44.sql:145 | `is_owner()` | owner-only, group-wide: partner agreements/capital. Fine for a group owner, must be scoped per business. |
| `notify_scan`, `daily_digest`, `urgent_alerts`, `dup_suspects`, `stock_reconcile`, `backup_stock_*`, `guard_recommendations`, `never_opened_negative_items` | phase46.sql:264/489/458, phase89.sql:825/1929/1971, phase12.sql:725/731, phase82.sql:432/383 | `is_owner()` | owner-only, whole database. |
| `acct_post_pending`, `acct_status`, `acct_set_start`, `acct_opening`, `acct_account_save`, `acct_mapping_set` | phase113.sql:425, phase89.sql:760, phase40.sql:575/750/587/619 | `_acct_view`/owner/none | operate on the single global ledger and chart. |

Functions that DO look safe because they inherit `can_loc`: `report_run` (supabase/phase9.sql:878-900, "rows are limited to can_loc() locations, always"), `profit_truth112` (phase112.sql:250, `locs := array(select l.id ... and public.can_loc(l.id))`), `biz_items` (phase112.sql:287), `biz_daily`, `biz_staff`, `acct_balance_sheet`, `acct_income_statement`, `acct_ledger`, `day_book`, `stock_levels`, `stock_valuation`, `save_entry`, `record_sale*`, `sale_return`, payroll/attendance via `_emp_ok`/`_pr_ok`. These are only as safe as `can_loc` (section 3) and the `locations` rows they iterate.

Remaining blind spots **[unverified]**: (a) the ~16 internal `_r3q_*` report bodies (phase25-27, 50, 72) are revoked from public and called by `report_run`/`report_run2/3` (phase24.sql:61,144) - `report_run` filters locations, `report_run2/run3` were not read line by line; (b) overload resolution of the `grant/revoke` parse (by name, not full signature); (c) `SECURITY INVOKER` functions (about 211) rely on RLS and were not reviewed.

Edge functions: `supabase/functions/scan-extract/index.ts:6` and `telegram-webhook/index.ts:17` state they act as the caller / a bot user with the anon key, service_role not used - so they inherit RLS and function gates. The Telegram bot is a single login (`INTAKE_BOT_EMAIL`): one bot would need one identity per business [unverified].

Storage: bucket `photos` is one private bucket (phase3.sql:184-189); read/insert policies call `photo_ok`, `_scan_photo_ok`, `_emp_photo_ok` (phase90.sql:162-164, phase41.sql:403-405, phase46.sql:546 uses `_is_ops`). `photo_ok`/`_scan_photo_ok`/`_emp_photo_ok` call `can_loc` (direct caller list) so they follow the swap; path layout is global [unverified].

## 6. Global settings tables - what must become per-business
| Table / mechanism | Evidence | Today | Needed for C1 |
|---|---|---|---|
| `rules` (key, value, default_value ...) | supabase/phase7.sql:12; policy `rules_read` = `is_active()`; read by `rule_val` phase7.sql:30 | ONE row per key for the whole DB; ~316 distinct keys seeded (regex count over `insert into rules`, [unverified exact]); groups: stock 57, pos 44, books 35, emergency 28, notify 26, people 21, purchase 20, settings 18, entries 13, reports 11, customers 10 ... | add a scope dimension (group default -> business override); `rule_on/rule_txt/rule_num/rule_val` take the scope from the calling context (location -> org unit) or an explicit argument. Every one of the ~695 call-site lines is affected (mechanical if the functions resolve scope from `current business`). |
| Business-specific rule keys (must NOT be shared) | rule keys in phase files: `accounting_on`, `accounting_start_date`, `period_closed_until` (books), `year_close_on`, `fixed_assets_on`, `vat_on`, `vat_rate`, `vat_prices_include`, `costing_method`, `fiscal_year_start_month/day`, `week_start`, `profit_truth_mode`, `cost_share_prorate_mode`, `items_net_of_returns`, `reports_net_of_returns`, `stock_negative_mode`, discount limits (pos), `purchase_cost_jump_pct`, `landed_*`, `bank_recon_on`, `budgets_on`, `daybook_*`, `acct_*` | one value for all | per business (or per legal entity for books/tax keys) |
| Group-level keys (stay global) | `twofa_*` (security), `ui_*`, `client_errors_*`, `assistant_*`, `scan_*` AI quotas, `notify` plumbing | | group default; allow business override only where noted |
| `grant_defs` | supabase/phase7.sql:94; policy `grant_defs_read` = `is_active()` | catalogue of grant codes (sweets-centric labels) | stays a global catalogue (read-only), fine; but `rule_grants` is the issue below |
| `rule_grants` (role x grant) | phase7.sql:89; select `is_active()`; consumed by `can_grant` (phase7.sql:125) | roles grant privileges everywhere | role-to-grant mapping must become per business (or roles must be created per business) |
| `roles`, `role_form_perms`, `user_roles` | schema.sql:17,56,25 | roles are global sweets roles (showroom manager, storekeeper ...); `user_roles` has no scope | user_roles must carry a scope (org unit); `role_form_perms` per business template |
| `user_locations` | schema.sql:39 | user -> location | replace/extend with user -> org unit (inherit downward); keep for backward compatibility behind flag |
| `user_grants` | phase8.sql:51 (`location_id` nullable) | location-scoped personal grants; NULL = everywhere | NULL must mean "everywhere in this business", not "database" |
| `location_settings` (key,value per location) | supabase/phase2.sql:7; select `is_active()` | per-location, readable by all | add `can_loc` to select policy (S) |
| `settings`, `settings_keys` | schema.sql:106, phase16.sql:492 | global key/value | classify per key |
| `settings_sheets` / `settings_values` | phase16 (`_sheet_viewer_at` phase16.sql:102) | versioned per-location sheets | weak (`has_grant(code, loc)` is role-global) |
| `forms` (enabled, red_block, count_first), `form_rollout`, `pin_sig_cfg`, `forms_ledger_cfg`, `blind_count_cfg`, `report_defs3` | schema.sql:45 etc. | which forms exist / are on | forms catalogue is global; enablement per business (module activation, Stage A section 3.5) |
| `option_lists`, `list_defs`, `list_managers` | phase6.sql:412, phase15.sql:29 | dropdown vocabularies (expense heads, categories, ...) readable by all | per-business vocabularies (scope column) |
| `coa_accounts`, `acct_mappings`, `year_closes`, `budgets`, `bank_*` | phase40.sql:35,52; phase53 | one chart, one mapping set | per legal entity (C2) - C1 only needs to block cross reads |
| `report_brand_map` | phase9.sql:33 | location -> hard-coded sweets brands | per business |

## 7. Prioritized C1 work list (effort S <= 0.5 day, M ~ 1-3 days, L > 3 days; rough, [unverified] until B1 lands)
| P | Item | Effort | Depends |
|---|---|---|---|
| P0 | Define `can_scope(org_unit)` / business resolver and re-implement `can_loc`, `_all_locs`, `_acct_all`, `_notif_ok`, `has_grant(..,loc)` on top of it behind rule flag `org_scope_on` (default OFF = identical behaviour). Drop the `management` global bypass (phase7.sql:281, phase10.sql:252, phase40.sql:150). | M (few functions, high regression risk, needs test suite) | B1 `org_units` + `locations.org_unit_id` |
| P0 | User binding: `user_locations`/`user_roles`/`user_grants` carry org scope; backfill sweets users; NULL-location grant = "whole business" (phase8.sql:93) | M | B1 |
| P0 | Negative-isolation test harness (section 9) incl. generated per-table tests | M | none (can start now) |
| P1 | The 44 `is_active()`-only tables: location-bearing ones (`location_settings`, `att_site_geo`, `holidays`, `shifts`, `sales_channels`, `path_switch`, `form_rollout`, `blind_count_cfg`, `doc_template_choice`, `invoice_templates`, `print_profiles`, `report_brand_map`, `locations`) get `can_loc(location_id)`; `locations` filtered to the caller's business | S-M (13 policies + client impact: `locations` list drives every dropdown in the web app [unverified]) | P0 |
| P1 | Global masters (section 4.5) and their sub tables: add `scope`/`org_unit_id` and a select policy; at minimum `customers`, `suppliers`, `items`, `item_*`, `recipes*`, `artisans`, `coa_accounts`, `acct_mappings`, `option_lists` | L (data model decision shared with C2; unique constraints on `customers.mobile`, `items.code`, barcode must become per-scope) | B1, C2 design |
| P1 | The 179 unscoped reader RPCs (Appendix B), starting with the 10 confirmed in section 5 (`customer_dues`, `customer_ledger`, `find_customer`, `fa_register`, `fa_schedule`, `year_close_list`, `items_with_cost`, `drawer_report`, `staff_directory`, `count_unsubmitted_scan`) | M (confirmed set) + L (full Appendix B triage) | P0 |
| P1 | `rules` per business: scope column + resolver in `rule_val`; classify the ~316 keys (business / group) | L | P0 |
| P1 | `rule_grants`, `role_form_perms`, role catalogue per business | M | P0 |
| P2 | Owner-only RPC families (partners, ops, backups, digest, notify_scan ...): decide group-owner vs business-owner; add scope arg | M | P0 |
| P2 | Closed tables with `location_id` reached only by RPCs (drawer_events, landed_*, opening_stock_*, serials ...): confirm each RPC filters by scope | M | P0 |
| P2 | Storage (`photos` bucket policies) and edge functions identity per business | S-M | P0 |
| P2 | Telegram/intake bot identity per business (`intake_bots`, `telegram_*`) | S | none |
| P3 | Views are revoked (OK); add a CI check that fails when a new table lacks RLS or a new SECURITY DEFINER lacks a scope call | S | none |

## 8. Evidence of absence
- grep -ric "business_id|org_unit|tenant_id|company_id" over non-test `supabase/phase*.sql` + `schema.sql`: re-run on this branch: 0 hits (B1 not merged here).
- No table other than `locations` carries an org dimension; scope is derived from `location_id` (present on 96 of 256 tables).

## 9. Proposed negative isolation tests (SQL, run as two businesses A/B once B1 exists; each must return 0 rows or raise)
For each test create users: `a_staff` (location in A), `a_mgr` (role management in A), `a_owner` (business owner A), `b_staff`, plus group owner.
1. Generated per-table test: for every table in Appendix A with RLS: as `a_staff`/`a_mgr`/`a_owner` run `select count(*)` where row belongs to B -> 0. Fail the build when a new table is missing from the generator list.
2. `management` bypass: `can_loc(<B location>)` is false for `a_mgr`; `_all_locs()` false; `_acct_all()` false; `can_loc(null)` false.
3. Role-global grants: user with role grant `accounts_manage` in A reads 0 journal lines of B; `has_grant('view_cost', <B loc>)` false.
4. Direct select on the 44 former any-active tables: `locations`, `location_settings`, `att_site_geo`, `holidays`, `shifts`, `sales_channels`, `items`, `option_lists`, `report_brand_map`, `rules` return only A's rows.
5. RPC parameter swap: `report_run(..., p_locs=[B loc])`, `profit_truth112(p_loc = B)`, `biz_items`, `acct_ledger`, `stock_levels`, `day_book` with a B location -> empty or `not allowed`.
6. Unscoped RPCs: `customer_dues()`, `customer_ledger(<B customer>)`, `find_customer(<B mobile>)`, `fa_register`, `fa_schedule(<B asset>)`, `items_with_cost`, `drawer_report`, `staff_directory`, `year_close_list` return nothing of B.
7. ID guessing: `select` / `update` by uuid/bigint id of a B row in `sales`, `entries`, `purchase_bills`, `journal_entries`, `employees`, `payroll_runs`, `stock_transfers` (both ends) -> 0 rows; `save_entry/record_sale/save_purchase/sale_return/void_sale` with B `location_id` -> raises.
8. Stock transfers across businesses: `stock_transfers` (policy `can_loc(from) or can_loc(to)`, phase2/10) - a transfer with from=A, to=B must be refused or be explicit intercompany.
9. Cross-business uniqueness: creating customer/item with the same mobile/code/barcode in B succeeds and is invisible to A (after unique constraints become scoped).
10. Rules: `set_rule` in A does not change `rule_on` in B; fiscal year / `period_closed_until` / `accounting_on` independent.
11. Storage: `a_staff` cannot read/insert `photos` objects under B's path.
12. Emergency windows: an approved `loc_access`/`form_access` window for A does not open B (`phase7.sql:282`).
13. Auth side channels: `login_precheck/login_failed` lockout keyed by `staff_id` does not reveal B staff existence [unverified].
14. Group owner positive tests: group owner still sees all businesses; sweets regression checksums unchanged (Stage A section 8).

## 10. Reproduce
Scripts live in the audit session scratchpad (not committed). Rough equivalents:
- tables: `grep -n "create table" supabase/phase*.sql supabase/schema.sql`
- policies: `grep -n "create policy" ...` plus the `foreach t in array` DO loops listed in section 0
- bypasses: `grep -nE "'management'" supabase/phase*.sql supabase/schema.sql`
- tenant columns: `grep -rniE "business_id|org_unit|tenant_id|company_id" supabase/schema.sql supabase/phase*.sql | grep -v _test`


## Appendix A - every public table (latest state)
Columns: table | created at | location col | RLS enabled at | browser SELECT revoked? | class | select policy (name file:line) | tag

| table | created | loc | RLS | sel grant | class | select policy | tag |
|---|---|---|---|---|---|---|---|
| acct_autopost_runs85 | phase85.sql:97 | - | phase85.sql:101 | revoked | CLOSED | (none) |  |
| acct_mappings | phase40.sql:52 | - | phase40.sql:166 | granted | PERM | acct_map_read phase40.sql:172 | MASTER |
| acct_post_errors72 | phase72.sql:29 | - | phase72.sql:33 | revoked | CLOSED | (none) |  |
| agreement_parties | phase44.sql:68 | - | phase44.sql:427(DO) | default [unverified] | OWNER | (dynamic DO) phase44.sql:427 |  |
| artisans | phase73.sql:44 | Y | phase73.sql:165 | granted | PERM | artisans_read phase73.sql:169 | MASTER |
| asset_costs | phase14.sql:769 | - | phase14.sql:788 | granted | PERM | asset_costs_read phase14.sql:792 | MASTER |
| assets | phase14.sql:752 | Y | phase14.sql:787 | granted | SCOPED | assets_read phase14.sql:790 |  |
| assistant_notes | phase47.sql:70 | - | phase47.sql:82 | granted | PERM | assistant_notes_read phase47.sql:86 |  |
| assistant_usage | phase47.sql:140 | - | phase47.sql:154 | granted | OWNER | assistant_usage_read phase47.sql:158 |  |
| att_evidence_reg | phase54.sql:54 | - | phase54.sql:87 | granted | SCOPED | att_evidence_reg_read phase54.sql:97 |  |
| att_mark_log54 | phase54.sql:65 | Y | phase54.sql:88 | granted | SCOPED | att_mark_log54_read phase54.sql:99 |  |
| att_self_lock | phase54.sql:41 | - | phase54.sql:85 | granted | OWNER | att_self_lock_read phase54.sql:93 |  |
| att_site_geo | phase54.sql:49 | Y | phase54.sql:86 | granted | ANY | att_site_geo_read phase54.sql:95 |  |
| attendance_days | phase42.sql:127 | Y | phase42.sql:315(DO) | granted | SCOPED | attendance_days_read phase42.sql:338 |  |
| attendance_devices | phase42.sql:104 | Y | phase42.sql:315(DO) | granted | SCOPED | attendance_devices_read phase42.sql:331 |  |
| attendance_import_batches | phase42.sql:110 | Y | phase42.sql:315(DO) | granted | SCOPED | attendance_import_batches_read phase42.sql:333 |  |
| attendance_punches | phase42.sql:116 | Y | phase42.sql:315(DO) | granted | SCOPED | attendance_punches_read phase42.sql:335 |  |
| audit_log | schema.sql:114 | - | schema.sql:445 | granted | OWNER | audit_owner_read schema.sql:483 |  |
| backup_runs | phase46.sql:33 | - | phase46.sql:64(DO) | default [unverified] | OWNER | backup_runs_read phase46.sql:100 |  |
| bank_recon_matches | phase53.sql:56 | - | phase53.sql:172 | granted | PERM | brm_read phase53.sql:182 |  |
| bank_recon_trail | phase53.sql:70 | - | phase53.sql:173 | granted | PERM | brt_read phase53.sql:184 |  |
| bank_statement_lines | phase53.sql:40 | - | phase53.sql:171 | granted | PERM | bsl_read phase53.sql:180 |  |
| benefit_types | phase61.sql:402 | - | phase61.sql:629(DO) | granted | ANY | benefit_types_sel phase61.sql:650 | MASTER |
| bi_export_log | phase61.sql:525 | Y | phase61.sql:629(DO) | granted | OWNER | bi_export_log_sel phase61.sql:652 |  |
| bill_pay_defaults99 | phase99.sql:90 | - | phase99.sql:102 | revoked | CLOSED | bill_pay_defaults99_sel phase99.sql:105 |  |
| bill_payments99 | phase99.sql:108 | Y | phase99.sql:136 | granted | SCOPED | bill_payments99_sel phase99.sql:140 |  |
| blind_count_cfg | phase18.sql:34 | Y | phase18.sql:46 | granted | ANY | blind_count_cfg_read phase18.sql:49 |  |
| bos_salt105 | phase105.sql:80 | - | phase105.sql:80 | revoked | CLOSED | (none) |  |
| budget_log | phase53.sql:129 | Y | phase53.sql:178 | granted | PERM | budlog_read phase53.sql:194 |  |
| budgets | phase53.sql:120 | Y | phase53.sql:177 | granted | SCOPED | bud_read phase53.sql:192 |  |
| card_settlements85 | phase85.sql:121 | Y | phase85.sql:128 | granted | SCOPED | card_settlements85_sel phase85.sql:132 |  |
| cash_moves | phase23.sql:233 | Y | phase23.sql:253 | granted | SCOPED | cash_moves_read phase23.sql:255 |  |
| client_error_hits107 | phase107.sql:73 | - | phase107.sql:79 | revoked | CLOSED | (none) |  |
| client_error_seen107 | phase107.sql:71 | - | phase107.sql:78 | revoked | CLOSED | (none) |  |
| client_errors | phase107.sql:49 | - | phase107.sql:77 | granted | PERM | client_errors_read107 phase107.sql:83 |  |
| coa_accounts | phase40.sql:35 | - | phase40.sql:165 | granted | PERM | coa_read phase40.sql:170 | MASTER |
| comparison_days | phase28.sql:34 | Y | phase28.sql:58(DO) | default [unverified] | SCOPED | (dynamic DO) phase28.sql:58 |  |
| comparison_pairs | phase28.sql:26 | - | phase28.sql:58(DO) | default [unverified] | ANY | (dynamic DO) phase28.sql:58 |  |
| corrections | schema.sql:122 | - | schema.sql:446 | granted | OWN | corrections_read schema.sql:485 |  |
| cost_attrib_main | phase78.sql:62 | Y | phase78.sql:136 | granted | PERM | cam_read phase78.sql:140 |  |
| cost_bill_inputs | phase75.sql:110 | Y | phase75.sql:165 | granted | SCOPED | cs_inp_read phase75.sql:173 |  |
| cost_bill_shares | phase75.sql:117 | Y | phase75.sql:166 | granted | SCOPED | cs_shr_read phase75.sql:174 |  |
| cost_charge_types | phase97.sql:148 | - | phase97.sql:162 | granted | ANY | cct_read97 phase97.sql:164 | MASTER |
| cost_component_types | phase74.sql:33 | - | phase74.sql:128 | granted | ANY | cost_types_read phase74.sql:133 | MASTER |
| cost_share_reassign | phase78.sql:74 | - | phase78.sql:137 | granted | SCOPED | csr78_read phase78.sql:141 |  |
| cost_source_bills | phase75.sql:91 | - | phase75.sql:164 | granted | SCOPED | cs_bills_read phase75.sql:172 |  |
| cost_source_locs | phase75.sql:61 | Y | phase75.sql:161 | granted | SCOPED | cs_locs_read phase75.sql:169 |  |
| cost_source_rule_shares | phase75.sql:81 | Y | phase75.sql:163 | granted | SCOPED | cs_rsh_read phase75.sql:171 |  |
| cost_source_rules | phase75.sql:68 | - | phase75.sql:162 | granted | SCOPED | cs_rules_read phase75.sql:170 |  |
| cost_source_types | phase75.sql:28 | - | phase75.sql:159 | granted | PERM | cs_types_read phase75.sql:167 | MASTER |
| cost_sources | phase75.sql:45 | - | phase75.sql:160 | granted | SCOPED | cs_src_read phase75.sql:168 |  |
| customer_gifts | phase43.sql:173 | - | phase43.sql:214 | granted | PERM | cg_read phase43.sql:223 | MASTER |
| customer_points_ledger | phase43.sql:131 | - | phase43.sql:212 | granted | PERM | cpl_read phase43.sql:219 | MASTER |
| customer_tier_history | phase43.sql:114 | - | phase43.sql:211 | granted | PERM | cth_read phase43.sql:217 | MASTER |
| customer_tiers | phase43.sql:20 | - | phase43.sql:71 | granted | ANY | customer_tiers_read phase43.sql:73 | MASTER |
| customers | phase6.sql:22 | - | phase6.sql:438 | granted | PERM | customers_read phase6.sql:440 | MASTER |
| dash_layouts | phase104.sql:41 | - | phase104.sql:48 | granted | OWN | dash_layouts_sel phase104.sql:50 |  |
| deed_templates | phase41.sql:207 | - | phase41.sql:337(DO) | granted | SCOPED | deed_templates_read phase41.sql:381 | MASTER |
| doc_template_choice | phase93.sql:17 | Y | phase93.sql:28 | granted | ANY | doc_template_choice_read phase93.sql:30 | MASTER |
| drawer_events | phase95.sql:56 | Y | phase95.sql:72 | revoked | CLOSED | (none) |  |
| emergency_requests | phase7.sql:143 | Y | phase7.sql:159 | granted | OWN | emergency_read phase7.sql:160 |  |
| employee_advance_recoveries | phase42.sql:189 | - | phase42.sql:315(DO) | granted | SCOPED | employee_advance_recoveries_read phase42.sql:344 |  |
| employee_advances | phase42.sql:151 | Y | phase42.sql:315(DO) | granted | SCOPED | employee_advances_read phase42.sql:342 |  |
| employee_benefit_grants | phase61.sql:414 | - | phase61.sql:629(DO) | granted | SCOPED | employee_benefit_grants_sel phase61.sql:651 |  |
| employee_benefits | phase41.sql:192 | - | phase41.sql:337(DO) | granted | SCOPED | employee_benefits_read phase41.sql:373 |  |
| employee_deeds | phase41.sql:212 | - | phase41.sql:337(DO) | granted | SCOPED | employee_deeds_read phase41.sql:383 |  |
| employee_documents | phase41.sql:164 | - | phase41.sql:337(DO) | granted | SCOPED | employee_documents_read phase41.sql:366 |  |
| employee_leave_entitlements | phase41.sql:201 | - | phase41.sql:337(DO) | granted | SCOPED | employee_leave_read phase41.sql:375 |  |
| employee_locations | phase41.sql:155 | Y | phase41.sql:337(DO) | granted | SCOPED | employee_locations_read phase41.sql:362 |  |
| employee_pay | phase41.sql:173 | - | phase41.sql:337(DO) | granted | SCOPED | employee_pay_read phase41.sql:368 |  |
| employee_pay_components | phase41.sql:183 | - | phase41.sql:337(DO) | granted | SCOPED | employee_pay_components_read phase41.sql:370 |  |
| employee_shift_assignments | phase42.sql:89 | - | phase42.sql:315(DO) | granted | SCOPED | esa_read phase42.sql:327 |  |
| employee_status_log | phase41.sql:159 | - | phase41.sql:337(DO) | granted | SCOPED | employee_status_log_read phase41.sql:364 |  |
| employees | phase41.sql:128 | Y | phase41.sql:337(DO) | default [unverified] | SCOPED | employees_read phase41.sql:348 | MASTER |
| entries | phase2.sql:21 | Y | phase2.sql:280 | granted | SCOPED | entries_read phase2.sql:286 |  |
| entry_change_requests | phase17.sql:449 | - | phase17.sql:473 | granted | SCOPED | entry_change_read phase17.sql:475 |  |
| entry_count_peeks | phase18.sql:114 | - | phase18.sql:134 | granted | OWNER | entry_count_peeks_read phase18.sql:139 |  |
| entry_count_seals | phase23.sql:497 | - | phase23.sql:507 | granted | SCOPED | entry_count_seals_read phase23.sql:509 |  |
| entry_counts | phase18.sql:101 | - | phase18.sql:133 | granted | SCOPED_PARENT | entry_counts_read phase18.sql:136 |  |
| entry_ledger_posts | phase20.sql:42 | Y | phase20.sql:64 | granted | SCOPED | entry_ledger_posts_read phase20.sql:69 |  |
| entry_revisions | phase17.sql:424 | - | phase17.sql:442 | granted | SCOPED_PARENT | entry_revisions_read phase17.sql:444 |  |
| entry_signatures | phase18.sql:373 | - | phase18.sql:388 | granted | SCOPED_PARENT | entry_signatures_read phase18.sql:390 |  |
| exceptions | phase2.sql:39 | Y | phase2.sql:281 | granted | SCOPED | exceptions_read phase3.sql:145 |  |
| fa_assets | phase53.sql:92 | Y | phase53.sql:175 | granted | SCOPED | fa_read phase53.sql:188 |  |
| fa_depr_posts | phase53.sql:109 | - | phase53.sql:176 | granted | SCOPED_PARENT | fadp_read phase53.sql:190 |  |
| factory_cost_pools | phase74.sql:72 | Y | phase74.sql:130 | granted | SCOPED | fcp_read phase74.sql:137 |  |
| flow_skips | phase28.sql:345 | Y | phase28.sql:353 | granted | OWN | flow_skips_read phase28.sql:355 |  |
| form_rollout | phase17.sql:52 | Y | phase17.sql:60 | granted | ANY | form_rollout_read phase17.sql:62 |  |
| forms | schema.sql:45 | - | schema.sql:438 | granted | ANY | forms_read schema.sql:464 +1 | MASTER |
| forms_ledger_cfg | phase20.sql:27 | - | phase20.sql:32 | granted | ANY | forms_ledger_cfg_read phase20.sql:37 | CONFIG |
| gift_rules | phase43.sql:153 | - | phase43.sql:213 | granted | ANY | gift_rules_read phase43.sql:221 | MASTER |
| grant_defs | phase7.sql:94 | - | phase7.sql:102 | granted | ANY | grant_defs_read phase7.sql:104 | CONFIG |
| grant_separation_pairs | phase78.sql:94 | - | phase78.sql:138 | granted | ANY | gsp_read phase78.sql:142 | CONFIG |
| grn_batch_links | phase60.sql:54 | Y | phase60.sql:101 | granted | SCOPED | grn_batch_links_read phase60.sql:104 |  |
| holidays | phase42.sql:97 | Y | phase42.sql:315(DO) | granted | ANY | holidays_read phase42.sql:329 |  |
| inbound_message_events | phase76.sql:107 | - | phase76.sql:739(DO) | granted | SCOPED | inbound_message_events_sel phase76.sql:754 |  |
| inbound_messages | phase76.sql:90 | Y | phase76.sql:739(DO) | granted | SCOPED | inbound_messages_sel phase76.sql:753 |  |
| inbox_unmask_log99 | phase99.sql:144 | Y | phase99.sql:160 | granted | OWNER | inbox_unmask_log99_sel phase99.sql:163 |  |
| intake_bots | phase76.sql:70 | - | phase76.sql:739(DO) | default [unverified] | CLOSED | (none) |  |
| intake_failures | phase76.sql:112 | - | phase76.sql:739(DO) | default [unverified] | CLOSED | (none) |  |
| intake_hits | phase76.sql:122 | - | phase76.sql:739(DO) | default [unverified] | CLOSED | (none) |  |
| intake_proofs94 | phase94.sql:104 | - | phase94.sql:109 | revoked | CLOSED | (none) |  |
| invoice_shares | phase92.sql:40 | Y | phase92.sql:50 | revoked | CLOSED | (none) |  |
| invoice_templates | phase8.sql:389 | Y | phase8.sql:425 | granted | ANY | invtpl_read phase8.sql:431 +1 | MASTER |
| item_bulk_batches | phase22.sql:26 | - | phase22.sql:37 | granted | PERM | item_bulk_batches_read phase22.sql:39 | MASTER |
| item_categories | phase100.sql:53 | - | phase100.sql:74 | granted | ANY | item_categories_read100 phase100.sql:76 | MASTER |
| item_changes | schema.sql:88 | - | schema.sql:443 | granted | PERM | item_changes_read phase14.sql:390 | MASTER |
| item_class_map | phase14.sql:42 | - | phase14.sql:632(DO) | granted | ANY | item_class_map_read phase14.sql:646 | MASTER |
| item_cost_flags | phase80.sql:40 | - | phase80.sql:47 | granted | PERM | item_cost_flags_read phase80.sql:49 | MASTER |
| item_costs | schema.sql:80 | - | schema.sql:442 | granted | PERM | item_costs_read schema.sql:473 | MASTER |
| item_import_batches | phase14.sql:504 | - | phase14.sql:511 | granted | OWNER | item_import_batches_read phase14.sql:513 | MASTER |
| item_logistics | phase97.sql:280 | - | phase97.sql:304(DO) | default [unverified] | CLOSED | (none) | MASTER |
| item_map_actions | phase22.sql:216 | - | phase22.sql:224 | granted | PERM | item_map_actions_read phase22.sql:226 | MASTER |
| item_mapping_review | phase14.sql:616 | - | phase14.sql:632(DO) | granted | PERM | item_mapping_review_read phase14.sql:640 | MASTER |
| item_master_links | phase14.sql:623 | - | phase14.sql:632(DO) | granted | ANY | item_master_links_read phase14.sql:642 | MASTER |
| item_price_history | schema.sql:98 | - | schema.sql:441 | granted | PERM | price_history_read schema.sql:476 | MASTER |
| item_types | phase14.sql:33 | - | phase14.sql:632(DO) | granted | ANY | item_types_read phase14.sql:644 | MASTER |
| items | schema.sql:66 | - | schema.sql:440 | granted | ANY | items_read schema.sql:470 | MASTER |
| journal_entries | phase40.sql:59 | Y | phase40.sql:167 | granted | SCOPED | je_read phase40.sql:174 |  |
| journal_lines | phase40.sql:79 | Y | phase40.sql:168 | granted | SCOPED | jl_read phase40.sql:176 |  |
| landed_cost_alloc | phase97.sql:245 | Y | phase97.sql:304(DO) | default [unverified] | CLOSED | (none) |  |
| landed_cost_basis | phase97.sql:236 | - | phase97.sql:304(DO) | default [unverified] | CLOSED | (none) |  |
| landed_cost_docs | phase97.sql:210 | - | phase97.sql:304(DO) | default [unverified] | CLOSED | (none) |  |
| landed_cost_lines | phase97.sql:219 | - | phase97.sql:304(DO) | default [unverified] | CLOSED | (none) |  |
| landed_cost_stock | phase97.sql:262 | Y | phase97.sql:304(DO) | default [unverified] | CLOSED | (none) |  |
| landed_costs | phase97.sql:186 | Y | phase97.sql:304(DO) | default [unverified] | CLOSED | (none) |  |
| landed_skips | phase97.sql:296 | - | phase97.sql:304(DO) | default [unverified] | CLOSED | (none) |  |
| landed_supplier_flags | phase97.sql:288 | - | phase97.sql:304(DO) | default [unverified] | CLOSED | (none) |  |
| leave_requests | phase42.sql:141 | - | phase42.sql:315(DO) | granted | SCOPED | leave_requests_read phase42.sql:340 |  |
| leave_types | phase41.sql:113 | - | phase41.sql:337(DO) | granted | ANY | leave_types_read phase41.sql:379 | MASTER |
| ledger_cost_supply96 | phase96.sql:76 | - | phase96.sql:86 | revoked | CLOSED | (none) |  |
| list_defs | phase15.sql:29 | - | phase15.sql:41 | granted | ANY | list_defs_read phase15.sql:43 | MASTER |
| list_managers | phase15.sql:68 | - | phase15.sql:73 | granted | OWN | list_managers_read phase15.sql:75 |  |
| list_other_entries | phase15.sql:189 | - | phase15.sql:200 | granted | OWN | list_other_read phase15.sql:204 |  |
| location_block_overrides | phase16.sql:423 | Y | phase16.sql:428 | granted | OWNER | loc_block_ov_read phase16.sql:430 |  |
| location_cost_attribution | phase78.sql:46 | Y | phase78.sql:135 | granted | SCOPED | lca_read phase78.sql:139 |  |
| location_cost_cfg | phase74.sql:90 | Y | phase74.sql:131 | granted | SCOPED | lcc_read phase74.sql:139 |  |
| location_settings | phase2.sql:7 | Y | phase2.sql:278 | granted | ANY | locset_read phase2.sql:284 +1 |  |
| location_setup_steps | phase16.sql:121 | Y | phase16.sql:129 | granted | GRANT_LOC_WEAK | loc_steps_read phase16.sql:131 |  |
| locations | schema.sql:31 | - | schema.sql:436 | granted | ANY | locations_read schema.sql:458 +1 |  |
| login_attempts | phase11.sql:94 | - | phase11.sql:102 | granted | OWNER | login_attempts_owner_read phase11.sql:104 |  |
| login_failures | schema.sql:131 | - | schema.sql:447 | granted | OWNER | login_failures_owner_read schema.sql:481 |  |
| login_throttle | phase11.sql:110 | - | phase11.sql:115 | revoked | CLOSED | (none) |  |
| manual_reason_codes85 | phase85.sql:104 | - | phase85.sql:107 | granted | PERM | manual_reason_codes85_sel phase85.sql:111 | CONFIG |
| notification_reads | phase46.sql:58 | - | phase46.sql:64(DO) | default [unverified] | OWN | notification_reads_read phase46.sql:104 |  |
| notifications | phase46.sql:42 | Y | phase46.sql:64(DO) | default [unverified] | SCOPED | notifications_read phase46.sql:102 |  |
| notify_optin | phase62.sql:70 | - | phase62.sql:105(DO) | default [unverified] | PERM | (dynamic DO) phase62.sql:105 |  |
| notify_optin_log | phase62.sql:80 | - | phase62.sql:105(DO) | default [unverified] | PERM | (dynamic DO) phase62.sql:105 |  |
| notify_outbox | phase62.sql:84 | - | phase62.sql:105(DO) | default [unverified] | PERM | (dynamic DO) phase62.sql:105 |  |
| notify_templates | phase62.sql:62 | - | phase62.sql:105(DO) | default [unverified] | PERM | (dynamic DO) phase62.sql:105 | MASTER |
| online_order_events | phase61.sql:64 | - | phase61.sql:629(DO) | granted | SCOPED | online_order_events_sel phase61.sql:647 |  |
| online_order_flags | phase77.sql:26 | Y | phase77.sql:209 | granted | SCOPED | online_order_flags_sel phase77.sql:213 |  |
| online_orders | phase61.sql:36 | Y | phase61.sql:629(DO) | granted | SCOPED | online_orders_sel phase61.sql:646 |  |
| opening_stock_actions96 | phase96.sql:104 | Y | phase96.sql:112 | revoked | CLOSED | (none) |  |
| opening_stock_followups103 | phase103.sql:98 | - | phase103.sql:98 | revoked | CLOSED | (none) |  |
| ops_accounts | phase46.sql:26 | - | phase46.sql:64(DO) | default [unverified] | OWNER | ops_accounts_read phase46.sql:98 |  |
| option_lists | phase6.sql:412 | - | phase6.sql:420 | granted | ANY | option_lists_read phase6.sql:421 +1 | MASTER |
| option_requests | phase15.sql:179 | - | phase15.sql:199 | granted | OWN | option_requests_read phase15.sql:202 |  |
| option_view_ops | phase91.sql:47 | - | phase91.sql:475 | revoked | CLOSED | (none) |  |
| order_dup_flags | phase76.sql:127 | Y | phase76.sql:739(DO) | granted | SCOPED | order_dup_flags_sel phase76.sql:756 |  |
| owner_board_items | phase45.sql:8 | - | phase45.sql:21 | granted | OWN | owner_board_sel phase45.sql:23 |  |
| paper_books | phase28.sql:192 | Y | phase28.sql:211(DO) | default [unverified] | GRANT_LOC_WEAK | (dynamic DO) phase28.sql:211 |  |
| parallel_months | phase28.sql:49 | Y | phase28.sql:58(DO) | default [unverified] | SCOPED | (dynamic DO) phase28.sql:58 |  |
| partner_agreements | phase44.sql:51 | - | phase44.sql:427(DO) | default [unverified] | OWNER | (dynamic DO) phase44.sql:427 |  |
| partner_capital | phase44.sql:89 | - | phase44.sql:427(DO) | default [unverified] | OWNER | (dynamic DO) phase44.sql:427 |  |
| partner_parties | phase44.sql:28 | - | phase44.sql:427(DO) | default [unverified] | OWNER | (dynamic DO) phase44.sql:427 |  |
| partner_rules | phase44.sql:78 | - | phase44.sql:427(DO) | default [unverified] | OWNER | (dynamic DO) phase44.sql:427 |  |
| partner_settlement_lines | phase44.sql:117 | - | phase44.sql:427(DO) | default [unverified] | OWNER | (dynamic DO) phase44.sql:427 |  |
| partner_settlement_payments | phase44.sql:127 | - | phase44.sql:427(DO) | default [unverified] | OWNER | (dynamic DO) phase44.sql:427 |  |
| partner_settlements | phase44.sql:103 | - | phase44.sql:427(DO) | default [unverified] | OWNER | (dynamic DO) phase44.sql:427 |  |
| partner_templates | phase44.sql:135 | - | phase44.sql:427(DO) | default [unverified] | OWNER | (dynamic DO) phase44.sql:427 | MASTER |
| partner_ventures | phase44.sql:38 | Y | phase44.sql:427(DO) | default [unverified] | OWNER | (dynamic DO) phase44.sql:427 |  |
| path_domains | phase48.sql:17 | - | phase48.sql:91(DO) | default [unverified] | ANY | path_domains_sel phase48.sql:101 | CONFIG |
| path_switch | phase48.sql:47 | Y | phase48.sql:91(DO) | default [unverified] | ANY | path_switch_sel phase48.sql:102 |  |
| payment_intents | phase62.sql:262 | Y | phase62.sql:289(DO) | default [unverified] | PERM | (dynamic DO) phase62.sql:289 |  |
| payment_webhook_log | phase62.sql:278 | - | phase62.sql:289(DO) | default [unverified] | PERM | (dynamic DO) phase62.sql:289 |  |
| payroll_bonus_events | phase42.sql:159 | Y | phase42.sql:315(DO) | granted | SCOPED | payroll_bonus_events_read phase42.sql:347 |  |
| payroll_lines | phase42.sql:172 | Y | phase42.sql:315(DO) | granted | SCOPED | payroll_lines_read phase42.sql:351 |  |
| payroll_payments | phase42.sql:196 | Y | phase42.sql:315(DO) | granted | SCOPED | payroll_payments_read phase42.sql:353 |  |
| payroll_runs | phase42.sql:165 | Y | phase42.sql:315(DO) | granted | SCOPED | payroll_runs_read phase42.sql:349 |  |
| perm_conflict | phase91.sql:269 | - | phase91.sql:454 | granted | OWNER | perm_conflict_read phase91.sql:461 | CONFIG |
| perm_reco_ignore | phase91.sql:275 | - | phase91.sql:455 | granted | OWNER | perm_reco_ignore_read phase91.sql:463 | CONFIG |
| perm_reco_role | phase91.sql:263 | - | phase91.sql:453 | granted | OWNER | perm_reco_role_read phase91.sql:459 | CONFIG |
| pin_sig_cfg | phase18.sql:41 | - | phase18.sql:47 | granted | ANY | pin_sig_cfg_read phase18.sql:51 | CONFIG |
| pool_gl_posts117 | phase117.sql:65 | - | phase117.sql:80 | revoked | CLOSED | (none) |  |
| pos_failed_cards | phase83.sql:599 | Y | phase83.sql:624(DO) | default [unverified] | SCOPED | pos_failed_cards_sel phase83.sql:632 |  |
| pos_replay_log | phase83.sql:614 | Y | phase83.sql:624(DO) | default [unverified] | SCOPED | pos_replay_log_sel phase83.sql:634 |  |
| print_notes | phase28.sql:203 | Y | phase28.sql:211(DO) | default [unverified] | GRANT_LOC_WEAK | (dynamic DO) phase28.sql:211 |  |
| print_profiles | phase8.sql:410 | Y | phase8.sql:426 | granted | ANY | printprof_read phase8.sql:433 +1 | MASTER |
| product_packaging | phase19.sql:68 | - | phase19.sql:146 | granted | PERM | product_packaging_read phase19.sql:153 | MASTER |
| production_reprice116 | phase116.sql:109 | - | phase116.sql:132 | revoked | CLOSED | (none) |  |
| production_runs | phase19.sql:79 | Y | phase19.sql:147 | granted | SCOPED | production_runs_read phase19.sql:155 |  |
| profiles | schema.sql:8 | - | schema.sql:433 | granted | OWN | profiles_read schema.sql:449 |  |
| purchase_bills | phase10.sql:151 | Y | phase10.sql:1339 | granted | SCOPED | purchase_bills_read phase10.sql:1354 |  |
| purchase_lines | phase10.sql:178 | - | phase10.sql:1340 | granted | SCOPED | purchase_lines_read phase10.sql:1356 |  |
| qc_records | phase60.sql:70 | Y | phase60.sql:102 | granted | SCOPED | qc_records_read phase60.sql:106 |  |
| quick_expenses | phase50.sql:120 | Y | phase50.sql:145 | granted | SCOPED | quick_expenses_sel phase50.sql:149 |  |
| recipe_cost_components | phase74.sql:56 | - | phase74.sql:129 | granted | PERM | rcc_read phase74.sql:135 | MASTER |
| recipe_lines | phase19.sql:54 | - | phase19.sql:145 | granted | PERM | recipe_lines_read phase19.sql:151 | MASTER |
| recipe_std116 | phase116.sql:90 | Y | phase116.sql:131 | revoked | CLOSED | (none) |  |
| recipe_steps | phase73.sql:100 | - | phase73.sql:166 | granted | PERM | recipe_steps_read phase73.sql:171 | MASTER |
| recipe_versions | phase73.sql:121 | - | phase73.sql:167 | granted | PERM | recipe_versions_read phase73.sql:173 | MASTER |
| recipes | phase19.sql:40 | - | phase19.sql:144 | granted | PERM | recipes_read phase19.sql:149 | MASTER |
| release_requests | phase2.sql:51 | - | phase2.sql:282 | granted | OWN | release_read phase17.sql:362 |  |
| report_brand_map | phase9.sql:33 | Y | phase9.sql:39 | granted | ANY | report_brand_map_read phase9.sql:44 | MASTER |
| report_defs3 | phase24.sql:8 | - | phase24.sql:20 | granted | ANY | report_defs3_read phase24.sql:22 | CONFIG |
| report_views | phase8.sql:448 | - | phase8.sql:460 | granted | OWN | rv_read phase8.sql:465 |  |
| restore_drills | phase70.sql:14 | - | phase70.sql:33 | granted | OWNER | restore_drills_read phase70.sql:38 |  |
| role_favourites | phase8.sql:501 | - | phase8.sql:506 | granted | ANY | rolefav_read phase8.sql:509 +1 | CONFIG |
| role_form_perms | schema.sql:56 | - | schema.sql:439 | granted | ANY | perms_read schema.sql:467 +1 | CONFIG |
| role_option_view | phase91.sql:39 | - | phase91.sql:474 | granted | OWNER | role_option_view_read phase91.sql:481 | CONFIG |
| roles | schema.sql:17 | - | schema.sql:434 | granted | ANY | roles_read schema.sql:452 +1 | CONFIG |
| rule_grants | phase7.sql:89 | - | phase7.sql:101 | granted | ANY | rule_grants_read phase7.sql:103 | CONFIG |
| rules | phase7.sql:12 | - | phase7.sql:26 | granted | ANY | rules_read phase7.sql:27 | CONFIG |
| sale_form_links | phase61.sql:283 | Y | phase61.sql:629(DO) | granted | SCOPED | sale_form_links_sel phase61.sql:649 |  |
| sale_payments | phase6.sql:43 | Y | phase6.sql:439 | granted | SCOPED | sale_payments_read phase6.sql:442 |  |
| sale_return_packaging80 | phase80.sql:117 | Y | phase80.sql:130 | granted | SCOPED | srp80_read phase80.sql:132 |  |
| sale_returns | phase12.sql:488 | Y | phase12.sql:510 | granted | SCOPED | sale_returns_read phase12.sql:512 |  |
| sale_tier_use | phase43.sql:199 | - | phase43.sql:215 | granted | SCOPED | stu_read phase43.sql:225 |  |
| sales | phase3.sql:16 | Y | phase3.sql:136 | granted | SCOPED | sales_read phase3.sql:140 |  |
| sales_channels | phase76.sql:55 | Y | phase76.sql:739(DO) | granted | ANY | sales_channels_sel phase76.sql:752 |  |
| sales_fact_t | phase9.sql:98 | Y | phase9.sql:112 | revoked | CLOSED | (none) |  |
| scan_events | phase90.sql:97 | - | phase90.sql:129 | granted | OWN | scan_events_sel phase90.sql:137 |  |
| scan_jobs | phase90.sql:64 | Y | phase90.sql:128 | granted | OWN | scan_jobs_sel phase90.sql:135 |  |
| serials | phase2.sql:16 | Y | phase2.sql:279 | default [unverified] | CLOSED | (none) |  |
| settings | schema.sql:106 | - | schema.sql:444 | granted | ANY | settings_read schema.sql:478 +1 | CONFIG |
| settings_keys | phase16.sql:492 | - | phase16.sql:496 | granted | ANY | settings_keys_read phase16.sql:498 | CONFIG |
| settings_sheets | phase16.sql:570 | Y | phase16.sql:593 | granted | GRANT_LOC_WEAK | settings_sheets_read phase16.sql:596 |  |
| settings_values | phase16.sql:587 | - | phase16.sql:594 | granted | GRANT_LOC_WEAK | settings_values_read phase16.sql:598 |  |
| setup_apply_batches81 | phase81.sql:63 | - | phase81.sql:518 | granted | OWNER | setup_apply_batches81_sel phase81.sql:530 |  |
| setup_apply_lines81 | phase81.sql:69 | - | phase81.sql:519 | granted | OWNER | setup_apply_lines81_sel phase81.sql:532 |  |
| setup_check_defs81 | phase81.sql:44 | - | phase81.sql:516 | granted | PERM | setup_check_defs81_sel phase81.sql:526 | CONFIG |
| setup_rec_defs81 | phase81.sql:32 | - | phase81.sql:515 | granted | PERM | setup_rec_defs81_sel phase81.sql:524 | CONFIG |
| setup_topic_defs81 | phase81.sql:56 | - | phase81.sql:517 | granted | PERM | setup_topic_defs81_sel phase81.sql:528 | CONFIG |
| shadow_links | phase48.sql:61 | Y | phase48.sql:91(DO) | default [unverified] | SCOPED | shadow_links_sel phase48.sql:103 |  |
| shelf_life_rules | phase8.sql:329 | - | phase8.sql:347 | granted | ANY | shelf_read phase8.sql:350 +1 | MASTER |
| shifts | phase42.sql:76 | Y | phase42.sql:315(DO) | granted | ANY | shifts_read phase42.sql:325 |  |
| staff_roles | phase41.sql:94 | - | phase41.sql:337(DO) | granted | ANY | staff_roles_read phase41.sql:377 | MASTER |
| stock_balance | phase10.sql:111 | Y | phase10.sql:1336 | granted | SCOPED | stock_balance_read phase10.sql:1348 |  |
| stock_batches | phase10.sql:73 | Y | phase10.sql:1334 | granted | SCOPED | stock_batches_read phase10.sql:1344 |  |
| stock_ledger | phase10.sql:88 | Y | phase10.sql:1335 | granted | SCOPED | stock_ledger_read phase10.sql:1346 |  |
| stock_transfers | phase10.sql:134 | Y | phase10.sql:1338 | granted | SCOPED | stock_transfers_read phase10.sql:1352 |  |
| stock_wastage | phase10.sql:120 | Y | phase10.sql:1337 | granted | SCOPED | stock_wastage_read phase10.sql:1350 |  |
| supplier_payments | phase10.sql:194 | Y | phase10.sql:1341 | granted | SCOPED | supplier_payments_read phase10.sql:1359 |  |
| supplier_refunds | phase12.sql:350 | Y | phase12.sql:366 | granted | SCOPED | supplier_refunds_read phase12.sql:368 |  |
| suppliers | phase8.sql:152 | - | phase8.sql:167 | granted | PERM | suppliers_read phase8.sql:169 | MASTER |
| telegram_chat_links | phase86.sql:158 | - | phase86.sql:292(DO) | default [unverified] | CLOSED | (none) |  |
| telegram_secrets | phase86.sql:65 | - | phase86.sql:292(DO) | default [unverified] | CLOSED | (none) |  |
| unit_conversions | phase8.sql:262 | - | phase8.sql:275 | granted | ANY | unit_conv_read phase8.sql:278 +1 | MASTER |
| user_favourites | phase8.sql:473 | - | phase8.sql:482 | granted | OWN | fav_own phase8.sql:484 |  |
| user_grants | phase8.sql:51 | Y | phase8.sql:63 | granted | OWN | user_grants_read phase8.sql:65 |  |
| user_locations | schema.sql:39 | Y | schema.sql:437 | granted | OWN | user_locations_read schema.sql:461 +1 |  |
| user_option_view | phase91.sql:32 | - | phase91.sql:473 | granted | OWN | user_option_view_read phase91.sql:479 | CONFIG |
| user_roles | schema.sql:25 | - | schema.sql:435 | granted | OWN | user_roles_read schema.sql:455 +1 |  |
| wastage_requests | phase12.sql:193 | Y | phase12.sql:210 | granted | SCOPED | wastage_requests_read phase12.sql:212 |  |
| year_closes | phase53.sql:79 | - | phase53.sql:174 | granted | PERM | yc_read phase53.sql:186 |  |

## Appendix B - exposed SECURITY DEFINER functions that are not scope-aware and read tables (179 readers; 429 incl. writers/no-table)
Gate tokens are the access helpers that appear in the body; empty = none found (gate may sit in a helper not listed [unverified]). `W` = body also writes.

| function | file:line | gates | tables read |
|---|---|---|---|
| _all_locs() | phase10.sql:250 | _all_locs,is_active,is_owner | user_roles |
| _cat_newcode100(boolean) | phase100.sql:123 | - | item_categories,items,option_lists |
| _cat_seed100() | phase100.sql:145 | - | item_categories,items,option_lists W |
| category_list(boolean) | phase100.sql:275 | is_active | item_categories,items |
| category_save(bigint,bigint,text,text,integer,boolean,uuid) | phase100.sql:289 | - | item_categories W |
| category_reorder(bigint[]) | phase100.sql:321 | - | item_categories W |
| category_rename(bigint,text,text) | phase100.sql:334 | is_owner | item_categories W |
| category_merge(bigint,bigint,uuid) | phase100.sql:352 | is_owner | item_categories,profiles W |
| category_move(bigint,bigint) | phase100.sql:391 | - | item_categories W |
| item_set_category(uuid,bigint,bigint) | phase100.sql:408 | - | item_categories,items W |
| category_rule_state() | phase100.sql:443 | is_active | item_categories,items |
| items_missing_category(integer) | phase100.sql:452 | - | item_categories,items |
| opening_stock_apply96(text,integer,text,date,text,uuid) | phase103.sql:809 | is_active,is_owner | opening_stock_actions96,opening_stock_followups103,profiles W |
| setup_recommendations() | phase103.sql:971 | is_owner | rules,setup_check_defs81,setup_rec_defs81 |
| find_customer(text) | phase103.sql:1164 | can_do | customers |
| _bp_auto_ok105(text,text,int) | phase105.sql:92 | has_grant,is_owner | cost_source_bills,purchase_bills |
| customer_dues() | phase105.sql:336 | can_do | customers,sale_payments,sale_returns,sales |
| customer_save(uuid,jsonb,uuid) | phase105.sql:428 | can_do,is_active | customer_tiers,customers,profiles W |
| client_error_log(text,jsonb) | phase107.sql:187 | is_active | client_error_hits107,client_errors,profiles W |
| client_errors_list(timestamptz,timestamptz,text,int,text) | phase107.sql:250 | has_grant,is_owner | client_errors |
| client_errors_summary() | phase107.sql:262 | has_grant,is_owner | client_errors |
| client_error_resolve(bigint,text) | phase107.sql:273 | is_owner | client_errors,profiles W |
| client_errors_purge(int) | phase107.sql:289 | is_owner | client_error_hits107,client_error_seen107,client_errors,profiles W |
| setup_recommend_apply(uuid,text[],boolean,boolean) | phase109.sql:633 | is_owner | profiles,rules,setup_apply_batches81,setup_check_defs81,setup_rec_defs81 W |
| login_precheck(text) | phase11.sql:153 | - | login_failures |
| login_failed(text) | phase11.sql:167 | - | login_failures,profiles W |
| login_success() | phase11.sql:203 | - | login_failures,profiles W |
| unlock_staff(text) | phase11.sql:212 | is_owner | login_failures,profiles W |
| _c78_rows112(date,date,boolean) | phase112.sql:93 | - | cost_bill_shares,cost_source_bills,cost_source_types,cost_sources |
| _pl_extra112(date,date,integer[]) | phase112.sql:130 | - | card_settlements85,entries,payroll_lines,payroll_payments,stock_wastage |
| _pnl_truth112(date,date,integer[]) | phase112.sql:167 | - | locations |
| acct_post_pending(boolean,integer) | phase113.sql:426 | - | acct_post_errors72,coa_accounts,exceptions,journal_entries,journal_lines W |
| customer_dues_net113() | phase113.sql:604 | - | cash_moves,sale_payments,sales |
| stock_batch_reconcile(boolean) | phase114.sql:185 | is_owner | profiles,stock_balance,stock_batches W |
| loc_cost_driver_set116(int,text,numeric,numeric,numeric) | phase116.sql:605 | is_owner | locations W |
| cost_type_gl_set117(text,text,boolean) | phase117.sql:254 | is_owner | acct_mappings W |
| recon_export_log118(text,integer,jsonb) | phase118.sql:466 | biz_cost_ok,has_grant,is_active,is_owner | profiles W |
| wastage_cancel(uuid) | phase12.sql:320 | - | wastage_requests W |
| customer_ledger(uuid) | phase12.sql:556 | can_do | sale_payments,sale_returns,sales |
| backup_stock_ledger(bigint,int) | phase12.sql:725 | is_owner | stock_ledger |
| backup_stock_balance() | phase12.sql:731 | is_owner | stock_balance |
| item_next_code(text) | phase14.sql:253 | is_active | option_lists |
| item_apply(uuid,jsonb,text) | phase14.sql:394 | can_do,has_grant,is_owner | items,profiles W |
| item_new(jsonb,text) | phase14.sql:415 | can_do,has_grant,is_owner | item_types,items,option_lists,profiles W |
| item_dup_check(text,text,uuid) | phase14.sql:441 | is_active | items |
| item_type_set(text,jsonb) | phase14.sql:453 | is_owner | item_types W |
| item_class_map_set(text,text,boolean) | phase14.sql:474 | is_owner | item_types W |
| item_master_import_apply(jsonb,text,int) | phase14.sql:568 | is_owner | profiles W |
| item_mapping_load(jsonb) | phase14.sql:652 | is_owner | items W |
| item_mapping_autolink() | phase14.sql:687 | is_owner | item_mapping_review,item_master_links,items W |
| item_mapping_decide(uuid,text,text,text,boolean) | phase14.sql:703 | has_grant,is_owner | items W |
| _list_mgr(text) | phase15.sql:84 | has_grant,is_active,is_owner | list_managers |
| list_manager_set(text,uuid,boolean) | phase15.sql:90 | is_owner | list_defs,profiles W |
| option_similar(text,text,text,text) | phase15.sql:122 | is_active | option_lists |
| option_add(text,text,text,text,jsonb,boolean,uuid) | phase15.sql:233 | is_active,is_owner | list_defs,option_lists,option_requests W |
| option_request_decide(uuid,boolean,text,text,text,text) | phase15.sql:273 | is_owner | list_defs,option_requests W |
| option_other_log(text,text,jsonb) | phase15.sql:299 | is_active | list_defs,list_other_entries,option_lists W |
| option_other_resolve(uuid,text,text,text,text,text,text,boolean) | phase15.sql:333 | is_owner | list_defs,list_other_entries,option_lists W |
| option_retire(text,text,text) | phase15.sql:373 | - | option_lists W |
| list_def_set(text,jsonb) | phase15.sql:420 | is_owner | list_defs,option_lists W |
| list_queue_counts() | phase15.sql:445 | is_active | list_defs,list_other_entries,option_requests |
| location_save(int,jsonb) | phase16.sql:194 | - | locations,option_lists W |
| location_close_check(int) | phase16.sql:298 | - | entries,locations,sales,stock_balance,stock_transfers |
| location_set_status(int,text,text,boolean) | phase16.sql:323 | is_owner | locations W |
| location_set_active(int,boolean) | phase16.sql:365 | - | locations W |
| location_steps_init(int) | phase16.sql:377 | - | location_setup_steps,locations |
| location_step_set(int,int,boolean,text) | phase16.sql:388 | is_owner | location_setup_steps,locations W |
| location_block_override(int,text,int) | phase16.sql:438 | is_owner | locations W |
| sheet_list(int) | phase16.sql:671 | - | settings_sheets,settings_values |
| sheet_set(bigint,jsonb) | phase16.sql:741 | - | settings_sheets W |
| sheet_discard(bigint) | phase16.sql:759 | is_owner | settings_sheets W |
| sheet_approve(bigint,date,text) | phase16.sql:799 | has_grant,is_active,is_owner | locations,settings_sheets W |
| sheet_sync_all() | phase16.sql:823 | - | locations |
| control_counts() | phase16.sql:884 | has_grant,is_active,is_owner | emergency_requests,exceptions,item_changes,locations,profiles |
| rollout_mode(text,int) | phase17.sql:76 | - | form_rollout |
| rollout_set(text,int,text,text) | phase17.sql:86 | - | forms,locations W |
| rollout_set_many(text[],int[],text,text) | phase17.sql:102 | - | forms,locations |
| paper_serial_collisions() | phase17.sql:140 | is_owner | entries |
| decide_release(bigint,boolean,text) | phase17.sql:340 | has_grant,is_active,is_owner | entries,profiles,release_requests W |
| _release_can_see(uuid) | phase17.sql:356 | has_grant,is_active,is_owner | entries |
| decide_emergency(bigint,boolean,text) | phase17.sql:366 | is_owner | emergency_requests,profiles W |
| submit_item_change(uuid,jsonb,text) | phase17.sql:386 | can_do,is_owner | profiles W |
| decide_item_change(bigint,boolean,text) | phase17.sql:403 | can_do,has_grant,is_active,is_owner | item_changes,profiles,roles,user_roles W |
| reopen_entry(uuid,text) | phase17.sql:579 | is_owner | entries,profiles W |
| _other_approver_exists() | phase17.sql:626 | - | profiles,role_form_perms,roles,user_grants,user_roles |
| blind_active(text,int) | phase18.sql:63 | - | blind_count_cfg |
| count_unsubmitted_scan() | phase18.sql:236 | is_active | entries,entry_counts,exceptions W |
| _recipe_cost_ok() | phase19.sql:104 | _recipe_cost_ok,can_do,has_grant,is_active,is_owner | user_grants |
| packaging_set(uuid,uuid,numeric,text,boolean,text) | phase19.sql:272 | - | items W |
| staff_directory() | phase2.sql:96 | is_active | profiles |
| request_release(uuid,text,text) | phase2.sql:211 | is_owner | entries,profiles W |
| items_bulk_apply(jsonb,boolean,text,text) | phase22.sql:72 | can_do,has_grant,is_active,is_owner | item_bulk_batches,item_costs,item_map_actions,item_master_links,items W |
| item_map_decide2(uuid,text,text,text,boolean) | phase22.sql:235 | has_grant,is_owner | item_map_actions,item_mapping_review,item_master_links,items,stock_balance W |
| item_map_accept_confident(boolean) | phase22.sql:330 | has_grant,is_owner | item_mapping_review,item_master_links,items W |
| receipt_duplicates(int) | phase23.sql:188 | is_owner | stock_ledger |
| stock_blind_active(text,int) | phase23.sql:491 | - | blind_count_cfg |
| blind_cfg_set(text,int,boolean) | phase23.sql:521 | is_owner | locations W |
| pin_sig_active(text) | phase23.sql:621 | - | pin_sig_cfg |
| report_catalog3() | phase24.sql:47 | is_active | report_defs3 |
| log_report_export2(text,text,jsonb,int) | phase24.sql:156 | is_active,is_owner | profiles,report_defs3 W |
| _r3q_s10_orders(date,date,int[],jsonb) | phase25.sql:20 | - | entries |
| _r3q_d5_lapsed(date,date,int[],jsonb) | phase25.sql:46 | - | customers,sales |
| _r3q_m1_rfm(date,date,int[],jsonb) | phase25.sql:61 | - | customers,sales |
| _r3q_x2_bypass(date,date,int[],jsonb) | phase25.sql:73 | - | emergency_requests,entries,profiles,release_requests |
| _r3q_x3_audit_log(date,date,int[],jsonb) | phase25.sql:90 | - | audit_log |
| _r3q_x4_compliance(date,date,int[],jsonb) | phase25.sql:100 | - | entries,locations |
| _r3q_x5_staff_trend(date,date,int[],jsonb) | phase25.sql:121 | - | profiles,sales |
| _r3q_g2_paper_numbers(date,date,int[],jsonb) | phase25.sql:140 | - | entries,locations |
| _r3q_k3_store_ledger(date,date,int[],jsonb) | phase25.sql:162 | - | items,stock_ledger |
| _r3q_e2_expense_trend(date,date,int[],jsonb) | phase25.sql:175 | - | entries,option_lists |
| _r3q_e3_weak_control(date,date,int[],jsonb) | phase25.sql:189 | - | entries,locations |
| _r3q_e4_marketing_limit(date,date,int[],jsonb) | phase25.sql:226 | - | entries,location_settings,locations,option_lists |
| _r3q_w1_cash_flow(date,date,int[],jsonb) | phase25.sql:246 | - | locations |
| _r3q_w2_handover_vs_hub(date,date,int[],jsonb) | phase25.sql:259 | - | entries,entry_counts,locations |
| _r3q_p2_rate_trend(date,date,int[],jsonb) | phase26.sql:110 | - | items |
| _r3q_p4_supplier_score(date,date,int[],jsonb) | phase26.sql:128 | - | entries,suppliers |
| _r3q_p5_po_match(date,date,int[],jsonb) | phase26.sql:168 | - | locations |
| _r3q_k2_count_variance(date,date,int[],jsonb) | phase26.sql:224 | - | entries,items,locations,profiles |
| _r3q_f1_production(date,date,int[],jsonb) | phase26.sql:249 | - | entries,items,locations,production_runs,stock_transfers |
| _r3q_f2_yield(date,date,int[],jsonb) | phase26.sql:281 | - | entries,items,locations,production_runs |
| _r3q_f3_raw_vs_recipe(date,date,int[],jsonb) | phase26.sql:319 | - | items,locations,production_runs,stock_ledger |
| _r3q_f4_breakdowns(date,date,int[],jsonb) | phase26.sql:347 | - | entries,locations |
| _r3q_m2_marketing_vs_sales(date,date,int[],jsonb) | phase26.sql:383 | - | entries,locations,option_lists,sales |
| _r3q_q1_fridge_temp(date,date,int[],jsonb) | phase26.sql:411 | - | entries,location_settings,locations |
| _r3q_q2_hygiene(date,date,int[],jsonb) | phase26.sql:435 | - | entries,locations |
| _r3q_q3_complaints(date,date,int[],jsonb) | phase26.sql:458 | - | entries,items,locations,option_lists,sale_returns |
| _r3q_l2_margin(date,date,int[],jsonb) | phase27.sql:102 | - | item_costs,items,sale_returns,sales |
| _r3q_l4_owner_sheet(date,date,int[],jsonb) | phase27.sql:146 | - | entries,locations |
| _r3q_l5_breakeven(date,date,int[],jsonb) | phase27.sql:179 | - | location_settings,locations |
| _r3q_t3_payroll(date,date,int[],jsonb) | phase27.sql:198 | - | entries,locations |
| _r3q_t4_staff_cost_ratio(date,date,int[],jsonb) | phase27.sql:234 | - | locations |
| comparison_pair_save(text,text,text,text,text,bigint,boolean) | phase28.sql:76 | is_owner | forms W |
| parallel_waiting() | phase28.sql:180 | is_owner | comparison_days,form_rollout,parallel_months |
| biz_suggest(int,int) | phase4.sql:184 | is_owner | entries,location_settings |
| _acct_view() | phase40.sql:141 | _acct_view,has_grant,is_active,is_owner | locations |
| acct_set_start(date) | phase40.sql:575 | is_owner | journal_entries |
| acct_account_save(bigint,text,text,text,text,bigint,boolean,int,boolean) | phase40.sql:587 | - | acct_mappings,coa_accounts W |
| acct_mapping_set(text,bigint) | phase40.sql:619 | - | acct_mappings,coa_accounts W |
| acct_post_pending(boolean,int) | phase40.sql:633 | - | coa_accounts,journal_entries,journal_lines |
| acct_opening(jsonb,boolean,text,uuid,boolean) | phase40.sql:750 | - | acct_mappings,coa_accounts,journal_entries |
| _emp_pay_json(bigint) | phase41.sql:717 | - | employee_pay,employee_pay_components |
| _emp_pay_on(uuid,date) | phase41.sql:728 | - | employee_pay |
| _att_is_off(uuid,date) | phase42.sql:376 | - | employee_shift_assignments |
| _att_holiday(int,date) | phase42.sql:381 | - | holidays |
| _att_shift_for(uuid,int,date) | phase42.sql:385 | - | employee_shift_assignments,shifts |
| _att_locked(uuid,date) | phase42.sql:398 | - | payroll_lines,payroll_runs |
| _att_derive(uuid,date) | phase42.sql:424 | - | attendance_punches,employees,leave_requests,leave_types |
| _att_store(uuid,date) | phase42.sql:485 | - | attendance_days W |
| _leave_days(uuid,date,date) | phase42.sql:744 | - | employees |
| _leave_used(uuid,text,int,text,bigint) | phase42.sql:749 | - | leave_requests |
| _att_ingest(jsonb,int,int,text,uuid,boolean,int) | phase42.sql:841 | - | attendance_punches,employees W |
| attendance_punch_push(text,jsonb) | phase42.sql:888 | - | attendance_devices W |
| attendance_device_register(text,int,text,text) | phase42.sql:981 | is_owner | locations W |
| _adv_outstanding(bigint) | phase42.sql:1033 | - | employee_advance_recoveries,employee_advances |
| _adv_02_3(uuid) | phase42.sql:1037 | - | employees,entries,profiles |
| _payroll_calc(uuid,date,date) | phase42.sql:1124 | - | attendance_days,employee_advances,employee_pay_components,employees,payroll_bonus_events |
| _pr_put_line(bigint,uuid,date) | phase42.sql:1295 | - | payroll_lines W |
| _pr_run_json(bigint) | phase42.sql:1334 | - | payroll_lines,payroll_runs |
| payroll_approve(bigint) | phase42.sql:1413 | is_owner | payroll_lines,payroll_runs W |
| payroll_payment_void(bigint,text) | phase42.sql:1470 | is_owner | payroll_payments W |
| tier_save(bigint,jsonb,uuid) | phase43.sql:559 | is_owner | customer_tiers W |
| tier_reorder(bigint[]) | phase43.sql:610 | is_owner | customer_tiers W |
| gift_rule_save(bigint,jsonb) | phase43.sql:622 | is_owner | customer_tiers,gift_rules W |
| customer_set_tier(uuid,bigint,text,boolean) | phase43.sql:714 | - | customer_tiers,customers,profiles W |
| customer_points(uuid) | phase43.sql:798 | - | customer_points_ledger |
| customer_points_adjust(uuid,int,text,uuid) | phase43.sql:803 | - | customer_points_ledger,customers,profiles W |
| customer_points_redeem(uuid,int,text,uuid,boolean) | phase43.sql:824 | can_do,is_active | customer_points_ledger,customers,profiles W |
| gift_issue(uuid,text,text,numeric,date,text,uuid) | phase43.sql:927 | - | customer_gifts,customers W |
| partner_party_save(bigint,text,text,text,text,text,text,text,text,boolean,uuid) | phase44.sql:443 | - | partner_parties W |
| partner_venture_save(bigint,text,text,text,int,text,date,date,text,text,uuid) | phase44.sql:464 | - | locations,partner_agreements,partner_ventures W |
| partner_agreement_save(bigint,bigint,text,date,date,jsonb,text,uuid) | phase44.sql:503 | - | partner_agreements,partner_ventures W |
| partner_agreement_party_set(bigint,bigint,text,numeric,text,boolean) | phase44.sql:531 | - | partner_agreements,partner_parties W |
| partner_rule_save(bigint,int,text,text,jsonb,boolean) | phase44.sql:545 | - | partner_agreements,partner_rules W |
| partner_rules_reorder(bigint,jsonb) | phase44.sql:560 | - | partner_agreements,partner_rules W |
| partner_agreement_activate(bigint,boolean) | phase44.sql:600 | - | partner_agreements,partner_settlements W |
| partner_agreement_amend(bigint,uuid) | phase44.sql:625 | - | agreement_parties,partner_agreements,partner_rules W |
| partner_agreement_close(bigint,text,date) | phase44.sql:642 | - | partner_agreements W |
| partner_agreement_from_template(bigint,text,text,uuid) | phase44.sql:656 | - | partner_agreements,partner_templates,partner_ventures W |
| partner_capital_add(bigint,bigint,text,numeric,date,text,text,text,uuid) | phase44.sql:677 | - | agreement_parties,partner_agreements,partner_capital W |
| partner_capital_void(bigint,text) | phase44.sql:699 | - | partner_capital W |
| partner_capital_balances(bigint,date) | phase44.sql:714 | - | agreement_parties,partner_capital,partner_parties,partner_settlement_lines,partner_settlements |
| partner_settlement_approve(bigint) | phase44.sql:1008 | - | partner_settlements W |
| partner_settlement_void(bigint,text) | phase44.sql:1020 | - | partner_settlement_lines,partner_settlements W |
| partner_settlement_pay(bigint,numeric,text,date,text,uuid) | phase44.sql:1034 | - | partner_settlement_lines,partner_settlement_payments,partner_settlements W |
| partner_party_statement(bigint,date,date) | phase44.sql:1059 | - | partner_capital,partner_parties,partner_settlement_lines,partner_settlement_payments,partner_settlements |
| partner_overview() | phase44.sql:1092 | - | partner_agreements,partner_capital,partner_settlement_lines,partner_settlements,partner_ventures |
| owner_board_get() | phase45.sql:43 | is_active,is_owner | owner_board_items |
| owner_board_save(jsonb) | phase45.sql:52 | is_active,is_owner | owner_board_items W |
| _is_ops(text) | phase46.sql:79 | - | ops_accounts |
| ops_account_set(uuid,text,boolean) | phase46.sql:107 | is_owner | profiles,user_roles W |
| backup_status() | phase46.sql:234 | is_owner | backup_runs,ops_accounts |
| notify_scan() | phase46.sql:264 | is_owner | comparison_days,customers,emergency_requests,entries,exceptions |
| urgent_alerts(timestamptz) | phase46.sql:458 | is_owner | notifications |
| _day_sales(date) | phase46.sql:480 | - | sale_returns,sales |
| daily_digest(date) | phase46.sql:489 | is_owner | customers,emergency_requests,entries,exceptions,item_changes |
| assistant_note_save(bigint,uuid,text,text,text,text) | phase47.sql:101 | is_owner | assistant_notes W |
| assistant_note_retire(bigint,text) | phase47.sql:126 | is_owner | assistant_notes W |
| assistant_log(text,text,text[],int,int,int,boolean) | phase47.sql:166 | - | assistant_usage W |
| assistant_usage_summary(date) | phase47.sql:186 | is_owner | assistant_usage |
| assistant_proxy_check() | phase47.sql:204 | - | assistant_usage |
| path_cfg(text,int) | phase48.sql:107 | - | path_domains,path_switch |
| path_switch_set(text,int,boolean,boolean,text,text) | phase48.sql:140 | is_owner | locations,path_domains W |
| path_switches() | phase48.sql:157 | is_owner | path_domains,path_switch |
| shadow_void(bigint,text) | phase48.sql:203 | is_owner | shadow_links W |
| shadow_count_once_check() | phase48.sql:237 | is_owner | journal_entries,shadow_links |
| _r3q_e2_expense_trend(date,date,integer[],jsonb) | phase50.sql:597 | - | entries,option_lists,quick_expenses |
| owner_money_link(bigint,uuid,text) | phase51.sql:59 | is_owner | cash_moves,partner_capital |
| bank_stmt_import(bigint,jsonb,uuid,boolean) | phase53.sql:248 | - | bank_statement_lines W |
| bank_recon_unmatch(bigint,text) | phase53.sql:391 | - | bank_recon_matches W |
| bank_recon_lines(bigint,text,int) | phase53.sql:437 | - | bank_recon_matches,bank_statement_lines |
| year_close_reverse(bigint,text,uuid) | phase53.sql:512 | is_owner | year_closes W |
| year_close_list() | phase53.sql:533 | _acct_view,is_owner | year_closes |
| fa_asset_dispose(uuid,date,text) | phase53.sql:673 | - | fa_assets,fa_depr_posts W |
| fa_schedule(uuid) | phase53.sql:689 | _acct_view | fa_assets,fa_depr_posts |
| fa_register(date) | phase53.sql:748 | _acct_view | fa_assets,fa_depr_posts |
| attendance_self_punch(text,numeric,numeric,numeric,text,text) | phase54.sql:138 | - | att_evidence_reg,att_site_geo,attendance_punches,employees W |
| att_my_status() | phase54.sql:182 | is_active | att_evidence_reg,attendance_punches,employees |
| att_self_lock_set(text,text,boolean,text) | phase54.sql:199 | is_active,is_owner | employees,roles,staff_roles W |
| att_site_geo_set(int,numeric,numeric) | phase54.sql:213 | is_active,is_owner | locations W |
| void_collection(bigint,text) | phase6.sql:316 | - | sale_payments W |
| sale_form_link(uuid,uuid,text) | phase61.sql:323 | is_owner | entries,sale_form_links,sales W |
| sale_form_unlink(bigint,text) | phase61.sql:351 | is_owner | sale_form_links W |
| bi_export_log_list(int) | phase61.sql:619 | is_owner | bi_export_log |
| _i62_ok() | phase62.sql:31 | has_grant,is_active,is_owner | locations |
| notify_optin_set(uuid,text,boolean,text,text) | phase62.sql:141 | - | customers W |
| notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text) | phase62.sql:159 | - | customers,notify_optin,notify_outbox,notify_templates W |
| notify_outbox_summary() | phase62.sql:209 | - | notify_outbox |
| notify_outbox_claim(int) | phase62.sql:221 | - | notify_outbox W |
| notify_outbox_report(bigint,boolean,text,text) | phase62.sql:237 | - | notify_outbox W |
| payment_intent_set_ref(bigint,text) | phase62.sql:326 | - | payment_intents W |
| payment_intent_link(bigint,bigint) | phase62.sql:339 | - | payment_intents,sale_payments W |
| payment_webhook_receive(text,text,text,text,text,numeric,boolean,jsonb) | phase62.sql:351 | is_owner | payment_intents W |
| assistant_access_list() | phase62.sql:479 | is_owner | profiles,rule_grants,user_grants |
| rule_val(text) | phase7.sql:30 | - | rules |
| set_rule(text,jsonb) | phase7.sql:48 | is_owner | rules W |
| can_grant(text) | phase7.sql:125 | is_active,is_owner | roles,rule_grants,user_roles |
| set_grant(text,text,boolean) | phase7.sql:131 | is_owner | grant_defs,roles,rule_grants W |
| my_emergency() | phase7.sql:255 | - | emergency_requests |
| can_do(text,text) | phase7.sql:262 | can_do,is_active,is_owner | emergency_requests,role_form_perms,roles,user_roles |
| restore_drill_list(int) | phase70.sql:61 | is_owner | restore_drills |
| restore_drill_status() | phase70.sql:70 | is_owner | restore_drills |
| twofa_policy() | phase71.sql:47 | is_active | user_roles |
| twofa_status_report() | phase71.sql:63 | is_owner | profiles,user_roles |
| _r3q_l2_margin(date,date,integer[],jsonb) | phase72.sql:263 | - | items |
| _recipe_read() | phase73.sql:181 | _recipe_read,has_grant,is_active,is_owner | user_grants |
| _recipe_view_ok(int) | phase73.sql:192 | has_grant,is_active | artisans |
| artisan_save(int,text,text,text,text,text,int,uuid,text,uuid) | phase73.sql:225 | - | artisans,locations,profiles W |
| artisan_register() | phase73.sql:270 | - | artisans,recipes |
| artisan_list(boolean) | phase73.sql:282 | _recipe_read,has_grant | artisans |
| recipe_unassigned() | phase73.sql:310 | has_grant | items,recipes |
| recipe_steps_save(uuid,jsonb,uuid) | phase73.sql:318 | - | recipe_versions,recipes W |
| recipe_labour_suggest(uuid) | phase73.sql:360 | _recipe_read,has_grant | recipe_steps |
| recipe_save(uuid,uuid,numeric,text,text,jsonb,uuid,boolean) | phase73.sql:397 | - | items,recipes W |
| recipe_copy(uuid,uuid,boolean,uuid) | phase73.sql:441 | - | artisans,items,recipe_lines,recipe_steps,recipes W |
| recipe_cost_component_set(uuid,text,text,numeric,numeric,text,text,uuid) | phase74.sql:251 | _recipe_cost_ok | cost_component_types,recipe_cost_components,recipes W |
| recipe_cost_components_get(uuid) | phase74.sql:278 | _recipe_cost_ok | cost_component_types,recipe_cost_components |
| loc_cost_cfg_set(int,text,numeric) | phase74.sql:311 | is_owner | locations W |
| cost_source_type_add(text,text,text) | phase75.sql:180 | - | cost_component_types W |
| intake_bot_set(uuid,boolean) | phase76.sql:228 | is_owner | profiles,user_roles W |
| web_form_catalog(text) | phase76.sql:607 | is_owner | items,sales_channels |
| web_form_embed(text) | phase76.sql:618 | is_owner | sales_channels |
| intake_failures_list(text,int) | phase76.sql:632 | can_do,is_active,is_owner | intake_failures |
| cost_attrib_main_set(int,date,text,uuid) | phase78.sql:254 | - | cost_attrib_main,locations W |
| grant_separation_hint(uuid,text) | phase78.sql:372 | is_owner | grant_separation_pairs,user_roles |
| grant_separation_report() | phase78.sql:391 | is_owner | grant_separation_pairs,profiles,user_roles |
| set_user_grant(uuid,text,int,timestamptz,boolean,text) | phase8.sql:70 | is_owner | grant_defs,locations,profiles,user_grants W |
| has_grant(text,int) | phase8.sql:93 | has_grant,is_active,is_owner | emergency_requests,grant_defs,user_grants |
| save_supplier(uuid,jsonb) | phase8.sql:174 | has_grant | suppliers W |
| supplier_pick() | phase8.sql:201 | is_active | suppliers |
| unit_factor(uuid,text,text) | phase8.sql:294 | - | items |
| shelf_life_for(uuid,date) | phase8.sql:358 | - | items,shelf_life_rules |
| template_for(text,int) | phase8.sql:440 | is_active | invoice_templates |
| item_cost_free_set(uuid,boolean,text,uuid) | phase80.sql:57 | can_do,is_active,is_owner | item_cost_flags,items W |
| item_cost_flags_list() | phase80.sql:75 | - | item_cost_flags,items |
| intake_bot_create(uuid,int) | phase80.sql:992 | is_owner | locations,profiles,role_form_perms,user_roles W |
| intake_bot_check(uuid) | phase80.sql:1010 | is_owner | intake_bots,role_form_perms,roles,user_roles |
| setup_readiness(text) | phase81.sql:456 | - | setup_check_defs81,setup_topic_defs81 |
| setup_flow_check() | phase81.sql:482 | - | setup_check_defs81 |
| setup_apply_history(int) | phase81.sql:505 | is_owner | setup_apply_batches81,setup_apply_lines81 |
| unit_unknown_items() | phase82.sql:369 | is_owner | items |
| never_opened_negative_items() | phase82.sql:383 | is_owner | items,stock_balance,stock_ledger |
| guard_recommendations() | phase82.sql:432 | is_owner | stock_ledger |
| acct_pending_alert85(int) | phase85.sql:755 | _acct_view | acct_autopost_runs85 |
| manual_reasons85() | phase85.sql:801 | _acct_view | manual_reason_codes85 |
| sales_channel_save(int,text,text,text,text,int,text,text,boolean) | phase86.sql:39 | is_owner | locations,roles W |
| telegram_secret_set(int,text) | phase86.sql:90 | is_owner | profiles,sales_channels W |
| telegram_status() | phase86.sql:106 | is_owner | inbound_messages,intake_failures,sales_channels,telegram_secrets |
| telegram_message_receive(text,text,bigint,bigint,text,text,text,timestamptz,text) | phase86.sql:122 | - | sales_channels,telegram_secrets |
| items_with_cost() | phase88.sql:228 | can_do,has_grant,is_active,is_owner | user_grants |
| item_cost_status88() | phase88.sql:242 | can_do,has_grant,is_active,is_owner | items,user_grants |
| acct_status() | phase89.sql:760 | _acct_view,is_owner | acct_autopost_runs85,acct_post_errors72,coa_accounts,journal_entries |
| dup_suspects(date,date) | phase89.sql:825 | is_owner | cash_moves,entries,partner_capital,payroll_runs,production_runs |
| partner_calculate(bigint,date,date,jsonb) | phase89.sql:1102 | - | locations,partner_agreements,partner_parties,partner_rules,partner_settlements |
| partner_settlement_save(bigint,date,date,jsonb,text,uuid) | phase89.sql:1355 | - | partner_agreements,partner_rules,partner_settlements W |
| recipe_approve(uuid,text) | phase89.sql:1538 | has_grant,is_active,is_owner | profiles,recipe_lines,recipes W |
| sales_channel_save(integer,text,text,text,text,integer,text,text,boolean) | phase89.sql:1726 | is_owner | locations,roles W |
| stock_reconcile(boolean) | phase89.sql:1929 | is_owner | profiles,stock_balance,stock_ledger W |
| urgent_alerts(timestamp with time zone) | phase89.sql:1971 | is_owner | notifications |
| report_fact_rebuild() | phase9.sql:262 | is_owner | sales,sales_fact_t W |
| log_report_export(text,text,jsonb,int) | phase9.sql:1097 | is_active,is_owner | profiles W |
| scan_match_items(text,int) | phase90.sql:333 | has_grant,is_active,is_owner | items |
| scan_match_suppliers(text,int) | phase90.sql:346 | has_grant,is_active,is_owner | suppliers |
| option_views_for_user(uuid) | phase91.sql:213 | is_owner | forms,grant_defs,profiles,role_form_perms,role_option_view |
| role_option_views(text) | phase91.sql:249 | is_owner | role_option_view |
| permission_recommendations(uuid) | phase91.sql:342 | is_owner | forms,grant_defs,perm_conflict,perm_reco_ignore,perm_reco_role |
| reco_ignore_set(uuid,text,boolean,uuid) | phase91.sql:377 | is_owner | perm_reco_ignore,profiles W |
| reco_apply(uuid,text,uuid) | phase91.sql:396 | is_owner | grant_defs,perm_conflict,perm_reco_role,profiles,user_grants W |
| reco_role_set(text,text,boolean,text,text,text) | phase91.sql:427 | is_owner | grant_defs,perm_reco_role,roles W |
| set_doc_template(text,text,int) | phase93.sql:35 | is_owner | doc_template_choice,locations,profiles W |
| get_doc_templates(int) | phase93.sql:60 | is_active | doc_template_choice |
| intake_proof_set94(text,text) | phase94.sql:123 | is_owner | intake_proofs94,profiles W |
| intake_proof_status94() | phase94.sql:140 | is_owner | intake_proofs94 |
| inbound_message_receive(text,text,text,text,text,text,timestamp with time zone,text,boolean,text) | phase94.sql:148 | is_owner | sales_channels |
| intake_purge(int) | phase94.sql:272 | is_owner | intake_failures,intake_hits W |
| pii_exposure_report94() | phase94.sql:445 | is_owner | audit_log,role_form_perms,roles,user_roles |
| acct_autopost_runs_list(int) | phase94.sql:484 | _acct_view | acct_autopost_runs85 |
| drawer_report(date,date) | phase95.sql:140 | has_grant,is_owner | drawer_events,profiles |
| opening_stock_apply96(text,int,text,date,text,uuid) | phase96.sql:675 | is_active,is_owner | opening_stock_actions96,profiles W |
| landed_info() | phase97.sql:1157 | has_grant,is_active,is_owner | cost_charge_types,user_grants |
| landed_charge_type_save(text,text,text,text,text,text,text,boolean) | phase97.sql:1171 | is_owner | acct_mappings,cost_charge_types W |
| landed_logistics_set(uuid,numeric,numeric,text) | phase97.sql:1194 | has_grant,is_active,is_owner | items,user_grants W |
| landed_supplier_flag_set(uuid,text,boolean,text) | phase97.sql:1205 | has_grant,is_active,is_owner | suppliers,user_grants W |
| bill_pay_default_set99(text,text,text,boolean,text) | phase99.sql:520 | is_owner | cost_sources,suppliers W |
| bill_pay_defaults_list99() | phase99.sql:534 | is_owner | bill_pay_defaults99,cost_sources,suppliers |
| inbox_unmask_log_list99(int,uuid) | phase99.sql:629 | is_owner | inbox_unmask_log99 |
| is_active() | schema.sql:139 | is_active | profiles |
| is_owner() | schema.sql:144 | is_active,is_owner | user_roles |
| my_context() | schema.sql:293 | - | forms,profiles,role_form_perms,roles,user_locations |