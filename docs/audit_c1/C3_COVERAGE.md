# C3 coverage - behaviour, permissions and reports kept apart between businesses (Stage C3, phase133)

Branch `local-c3`. Written by `tools/scope_classify133.py` from a built database (do not edit by hand: change the RULES of the tool and run it again). Nothing here is pasted or pushed.

Plan and audit: `docs/GROUP_ERP_STAGE_A.md` sections 3.4 and 10, `docs/audit_c1/RLS_ISOLATION_AUDIT.md` (Appendix B: 179 read-only SECURITY DEFINER functions that are not scope-aware, 429 in total, global rules / grants / roles, `user_grants` with NULL place, storage, bot identity, negative tests 9, 10, 11, 13). Master data is Stage C2 (C2_COVERAGE.md of the C2 branch, other agent).

## 1. Method (three independent checks)

1. **Static, by construction** - `scope_gaps133()` (owner function in phase133) lists every exposed SECURITY DEFINER function whose body does not call a scope primitive (`can_loc`, `can_scope`, `_biz_ok123`, `_my_biz123`, `business_of_location`, `has_grant` / `can_do` with a place argument ...), directly or through a callee (fixpoint over the call graph; a callee without arguments only counts when it returns a set). Exposed = EXECUTE granted to `authenticated` (the scratch build mimics the Supabase default grants, so a function without an explicit revoke is exposed).
2. **Review** - each of those functions was read (or its family) and put in a class with a reason (section 4). `tests/sql/scope_allowlist.txt` is that reviewed list; `phase133_test` T11 fails when the checker and the list differ, so a new function without a scope call, or a function that stops being scope-aware, is noticed.
3. **Dynamic, differential probe** - `tests/sql/c3_probe.sql`: with the switch ON, three personas of business A (staff, manager, a user holding every role and every grant) and a notify bot call every exposed function (about 800) with plausible arguments inside a sub-transaction that is always rolled back; the answers are compared between a database where only A has data (S1) and one where B has data too (S2) - they must not change - and with B places / ids swapped in, which must look exactly like a missing id. `phase133_test` T13 fails on any difference that is not in `tests/sql/scope_probe_known.txt` (11 reviewed entries: master data of C2, group infrastructure, sequence ids).

## 2. Numbers

| Measure | Count |
|---|---|
| exposed SECURITY DEFINER functions (this build, after phase133; net 18 more than before) | 826 (13 of them also executable by `anon`: login, device and webhook entry points, reviewed in the C1 audit and in phase94/121) |
| scope-aware by construction (direct primitive or through a callee) | 520 |
| NOT scope-aware by construction, reviewed one by one (the list below) | 306 |
| ... before phase133 the same checker found | 338 of 808 |
| functions whose body phase133 re-creates or patches (marker `scope133`) | 45 (4 re-created with the old text as the OFF branch, 41 patched by exact-text insert) |
| border triggers `<table>_xb133` (write side, every table with a place column) | 95 |

Classes of the 306 reviewed functions (the audit asked for: scoped now / truly global / owner-only / deferred):

| Class | Count | Meaning |
|---|---|---|
| FIXED | 15 | scoped now by phase133 |
| HELPER | 5 | reviewed: scoped through a helper, a trigger or a grant with the place |
| OWNER | 138 | group owner only (group-wide on purpose) |
| OWN | 23 | only the caller's own rows |
| PRIM | 30 | permission / identity / pure helper |
| CONFIG | 17 | configuration / catalogue / vocabulary / diagnostics |
| INFRA | 18 | bot / device / webhook / queue / scheduler |
| MASTER | 60 | shared master data, Stage C2 (phase132) |
| DEFER | 0 | known gap |

Summary in the audit's words: **scoped now** = the 45 functions that carry the marker (they are scope-aware after the patch; those that only got an owner gate are listed as FIXED) + 95 border triggers + the restrictive policies; **truly global** = PRIM + CONFIG + OWN + INFRA (88); **owner-only** = OWNER (138); **shared master (Stage C2)** = MASTER (60); **deferred with a reason** = section 7.

## 3. What phase133 changed (switch ON only; OFF is byte-identical, proved by `tests/sql/c3_before_after.sh`)

1. **Per-business settings.** `rule_overrides` (business x rule key): `rule_val` / `rule_on` / `rule_num` / `rule_txt` answer with the value of the caller's working business (the single business of the user, or the working business of phase132 when pasted), else the group value; the group owner without a working business gets the group value. `rule_override_set133` (owner; same validation as `set_rule`; group-only keys - security, assistant, ui, integrations, backup, scan quotas, `org_scope_on` - are refused), `rule_overrides_list133`, `rule_val_in133`, `rules_effective133` (for the screens). Audit test 10 is `phase133_test` T2.
2. **Per-business roles and grants.** `rule_grant_overrides133` (business x grant x role, allow or take away) and `role_form_overrides133` (form rights of a role); `can_grant`, `has_grant(code, place)` and `can_do` read the matrix of the place's business. `roles.org_unit_id` and `grant_defs.org_unit_id` (NULL = shared catalogue): a role / grant that belongs to one business is invisible to the others, with its `rule_grants` / `role_form_perms` rows. `management` is per business since phase123 (scope rows); the last readers of the role name (`assistant_health`, `org_scope_preflight`) are limited to the caller's businesses. A personal NULL-place grant means "my businesses" (phase123) and is not touched by a role override.
3. **Write border.** A trigger on 95 tables stops a non-owner from inserting / updating / deleting a row of a place outside his businesses, whatever function does it (id swap, parameter swap). `phase133_test` T5.
4. **Patched functions** (section 5). **Owner-only while ON** for the records that have no business column: chart of accounts, mappings, opening journal, bank statements and matches, scheduler, the main cost place, the setup advisors (they count the whole database), the SMS outbox summary / cancel.
5. **Reports and digests.** `report_run` (including `receivable_aging`) and `rpt131_*` were already place-scoped through `can_loc` (tested in T9 with hand numbers); `my_context` returns only the caller's own rows. `daily_digest` is the GROUP digest (owner or the notify bot); `daily_digest_biz133(business, date)` is the same digest for one business (owner, the notify bot, or the management of that business) with that business's rules. `acct_status`, `acct_post_pending`, `acct_pending_alert85`, `profit_source_check` count only the documents of the caller's places; `customer_dues_net113`, `_cust_bal` / `customer_balance` / `find_customer` count only the caller's businesses.
6. **Storage** (section 6). **Bot identity and notifications** (section 6). **Auth side channel** (audit test 13): while ON an unknown staff id is counted and locked like a known one, so `login_precheck` never tells whether an id exists.

## 4. The reviewed list (functions that are not scope-aware by construction)

### FIXED - scoped now by phase133

- owner gate while the switch is ON (company-level books / outbox record: one chart, one set of bank statements, one queue until the per-entity books)
  `acct_account_save`, `acct_mapping_set`, `acct_opening`, `acct_scheduler_disable`, `acct_scheduler_enable`, `bank_recon_lines`, `bank_recon_unmatch`, `bank_stmt_import`, `cost_attrib_main_set`, `notify_cancel`, `notify_outbox_summary`, `setup_flow_check`, `setup_readiness`, `setup_recommendations`
- patched in phase133: place filter / business check on the rows it reads or writes (old text kept as the OFF branch)
  `login_failed`

### HELPER - reviewed: scoped through a helper, a trigger or a grant with the place

- has_grant(release_decide, <place of the entry>): the place is passed as a sub-select, scoped through has_grant (business border since phase123)
  `_release_can_see`, `decide_release`
- updates one fixed asset by id: trigger fa_assets_xb133 refuses a foreign-business row ("not found" while the switch is ON)
  `fa_asset_dispose`
- updates one payment intent by id: trigger payment_intents_xb133 refuses a foreign-business row
  `payment_intent_set_ref`
- only the maker of the draft entry (or the owner) can ask; the entry is the caller's own
  `request_release`

### OWNER - group owner only (group-wide on purpose)

- owner only (hard gate): whole-database tool of the group owner (reconciliation, backup, audit, bots and their secrets, payroll approval)
  `backup_coverage106`, `backup_status`, `backup_stock_balance`, `backup_stock_ledger`, `bi_export_log_list`, `bill_pay_default_set99`, `bill_pay_defaults_list99`, `biz_suggest`, `dup_suspects`, `guard_recommendations`, `inbox_unmask_log_list99`, `intake_bot_check`, `intake_bot_create`, `intake_bot_set`, `intake_failure_dismiss`, `intake_proof_set94`, `intake_proof_status94`, `intake_purge`, `never_opened_negative_items`, `opening_stock_apply96`, `owner_board_get`, `owner_board_save`, `paper_serial_collisions`, `parallel_waiting`, `payroll_approve`, `payroll_payment_void`, `production_recommendations`, `receipt_duplicates`, `report_fact_rebuild`, `restore_drill_list`, `restore_drill_record`, `restore_drill_status`, `sale_form_unlink`, `setup_apply_history`, `setup_recommend_apply`, `shadow_count_once_check`, `shadow_void`, `stock_batch_reconcile`, `stock_reconcile`, `telegram_secret_set`, `telegram_status`, `unit_unknown_items`, `web_form_embed`
- owner only (hard gate): people, roles, grants and group settings are group-wide; per-business values are rule_overrides / rule_grant_overrides133 / role_form_overrides133
  `anon_exec_audit94`, `assistant_access_list`, `assistant_note_retire`, `assistant_note_save`, `assistant_usage_summary`, `grant_separation_hint`, `grant_separation_report`, `ops_account_set`, `owner_self_approve_set`, `permission_recommendations`, `pii_exposure_report94`, `reco_apply`, `reco_conflict_set`, `reco_ignore_set`, `reco_role_set`, `role_option_views`, `set_grant`, `set_option_view`, `set_option_view_bulk`, `set_role_option_view`, `set_role_option_view_bulk`, `set_rule`, `set_user_grant`, `staff_role_save`, `twofa_status_report`, `unlock_staff`
- owner only (hard gate): configuration of a place / of the books written by the group owner
  `acct_set_start`, `att_self_lock_set`, `att_site_geo_set`, `attendance_device_register`, `attendance_device_set_active`, `attendance_device_token_reset`, `blind_cfg_set`, `comparison_pair_save`, `cost_type_driver_set116`, `cost_type_gl_set117`, `forms_ledger_cfg_set`, `loc_cost_cfg_set`, `loc_cost_driver_set116`, `location_block_override`, `manual_reason_set`, `notify_template_save`, `pin_sig_cfg_set`, `sales_channel_save`, `set_daybook_opening`, `set_daybook_start`, `set_doc_template`, `year_close_reverse`
- partners module: every function starts with _a44_guard() = owner only
  `partner_agreement_activate`, `partner_agreement_amend`, `partner_agreement_close`, `partner_agreement_from_template`, `partner_agreement_party_set`, `partner_agreement_save`, `partner_calculate`, `partner_capital_add`, `partner_capital_balances`, `partner_capital_void`, `partner_overview`, `partner_party_save`, `partner_party_statement`, `partner_rule_save`, `partner_rule_validate`, `partner_rules_reorder`, `partner_settlement_approve`, `partner_settlement_pay`, `partner_settlement_save`, `partner_settlement_void`, `partner_venture_save`
- owner only (hard gate) and master data: the owner edits the shared vocabularies / master (Stage C2 scopes the rows)
  `category_merge`, `category_rename`, `gift_rule_save`, `item_class_map_set`, `item_mapping_autolink`, `item_mapping_load`, `item_master_import_apply`, `item_master_import_preview`, `item_type_set`, `list_def_set`, `list_manager_set`, `set_unit_conversion`, `tier_reorder`, `tier_save`
- owner only (new in phase133): per-business settings, coverage checker, storage overview
  `grant_scope_set133`, `role_form_override_set133`, `role_scope_set133`, `rule_grant_override_set133`, `rule_override_set133`, `scope_gaps133`
- [c2] owner tool of phase132 (master shares, unique-constraint relaxing, master scope report); present only when phase132 is pasted
  `master_scope_report132`, `master_share_create`, `master_share_list`, `master_share_revoke`, `org_masters_relax_unique`, `org_masters_restore_unique`
- group owner or the group-level org_manage grant (phase122/123); org_tree already shows a non-owner only the chain of his own places
  `org_scope_grant`, `org_scope_list`, `org_scope_revoke`, `org_tree`, `org_unit_deactivate`, `org_unit_save`

### OWN - only the caller's own rows

- reads / writes only rows of the caller (own favourites, own request, own error line, own export log line, own roles)
  `assistant_log`, `cancel_emergency`, `client_error_log`, `dash_layout_get`, `dash_layout_save`, `entry_change_cancel`, `fav_meta_set`, `fav_order_set`, `log_report_export`, `log_report_export2`, `login_success`, `my_context`, `my_emergency`, `my_option_views`, `option_views_for_user`, `recon_export_log118`, `reopen_entry`, `rpt131_log_export`, `set_my_lang`, `set_pin`, `touch_favourite`, `twofa_policy`, `wastage_cancel`

### PRIM - permission / identity / pure helper

- permission / identity helper: returns a flag, reads no business row (the readers that use it filter by place themselves)
  `_a53_mgr`, `_acct_view`, `_assistant_ok`, `_cs_view`, `_i62_ok`, `_i62_pay_ok`, `_is_ops`, `_list_mgr`, `_loc_mgr`, `_org_on123`, `_other_approver_exists`, `_recipe_cost_ok`, `_recipe_read`, `_recipe_view_ok`, `_setup_view81`, `_sheet_viewer`, `biz_cost_ok`, `biz_ok`, `is_active`, `is_owner`, `rule_num`, `rule_on`, `rule_txt`
- pure date / unit arithmetic over the shared item and unit tables (items are master data, Stage C2)
  `convert_qty`, `fiscal_year_end`, `fiscal_year_start`, `shelf_life_for`, `shelf_life_hours`, `unit_factor`, `week_start_date`

### CONFIG - configuration / catalogue / vocabulary / diagnostics

- configuration / catalogue / vocabulary / diagnostics: no business rows (report catalogues list report names and filters; client errors are technical messages)
  `benefit_type_save`, `client_error_resolve`, `client_errors_list`, `client_errors_purge`, `client_errors_summary`, `cost_source_type_add`, `cost_type_add`, `cost_type_smoothing`, `landed_charge_type_save`, `landed_info`, `manual_reasons85`, `pin_sig_active`, `report_catalog`, `report_catalog2`, `report_catalog3`, `report_presets`, `rpt131_catalog`

### INFRA - bot / device / webhook / queue / scheduler

- bot / device / webhook / queue / scheduler entry point: bound to its token, channel or device, or group infrastructure by design (writes are location-tagged and stopped by the border triggers for a business-limited bot; group scans belong to the owner or to a bot that is a member of every business)
  `acct_autopost_runs_list`, `assistant_proxy_check`, `attendance_punch_push`, `backup_dump`, `backup_log`, `backup_manifest`, `inbound_message_receive`, `login_precheck`, `notifications_mark_emailed`, `notify_config`, `notify_enqueue`, `notify_optin_set`, `notify_outbox_claim`, `notify_outbox_report`, `payment_webhook_receive`, `telegram_message_receive`, `urgent_alerts`, `web_form_catalog`

### MASTER - shared master data, Stage C2 (phase132)

- [c2] shared master data (items, customers, suppliers, recipes, artisans, categories, vocabularies): rows are scoped by Stage C2 (phase132); the function reads no place-bound business row
  `artisan_list`, `artisan_register`, `artisan_save`, `artisan_set_active`, `category_list`, `category_move`, `category_reorder`, `category_rule_state`, `category_save`, `category_sync100`, `customer_points`, `customer_points_adjust`, `customer_points_redeem`, `customer_save`, `customer_set_tier`, `decide_item_change`, `gift_issue`, `item_apply`, `item_cost_free_set`, `item_dup_check`, `item_map_accept_confident`, `item_map_decide2`, `item_mapping_decide`, `item_new`, `item_next_code`, `item_set_category`, `item_set_category_bulk`, `items_bulk_apply`, `items_missing_category`, `items_search_info126`, `landed_logistics_set`, `landed_supplier_flag_set`, `list_queue_counts`, `option_add`, `option_other_log`, `option_other_resolve`, `option_reactivate`, `option_reorder`, `option_request_decide`, `option_retire`, `option_similar`, `option_update`, `packaging_set`, `recipe_approve`, `recipe_copy`, `recipe_cost_component_retire`, `recipe_cost_component_set`, `recipe_cost_components_get`, `recipe_labour_suggest`, `recipe_save`, `recipe_save_full`, `recipe_set_active`, `recipe_set_artisan`, `recipe_steps_save`, `recipe_unassigned`, `save_supplier`, `scan_match_items`, `scan_match_suppliers`, `submit_item_change`, `supplier_pick`

## 5. Functions patched or re-created by phase133 (marker `scope133`)

`_cust_bal`, `_qc_latest60`, `acct_account_save`, `acct_mapping_set`, `acct_opening`, `acct_pending_alert85`, `acct_post_pending`, `acct_scheduler_disable`, `acct_scheduler_enable`, `acct_status`, `assistant_health`, `bank_recon_candidates`, `bank_recon_lines`, `bank_recon_match`, `bank_recon_match_many`, `bank_recon_report`, `bank_recon_suggest`, `bank_recon_unmatch`, `bank_stmt_import`, `blind_active`, `can_do`, `can_grant`, `control_counts`, `cost_attrib_main_set`, `cost_source_set_active`, `count_unsubmitted_scan`, `customer_dues_net113`, `get_doc_templates`, `has_grant`, `intake_failures_list`, `login_failed`, `notify_cancel`, `notify_outbox_summary`, `path_cfg`, `payment_intent_link`, `profit_source_check`, `rollout_mode`, `rule_val`, `setup_flow_check`, `setup_readiness`, `setup_recommendations`, `sheet_sync_all`, `stock_blind_active`, `template_for`, `void_collection
`

## 6. Storage, bot identity, notifications, login

**Storage (audit test 11).** Every upload path of the web already has the shape `<PREFIX>/<place id>/<file>` (STOCK, PURCHASE, SCAN, EMP, EMPDOC, ITEMS or a form code); the place id identifies the business through `locations.org_unit_id`. The read and insert policies on `storage.objects` (`photo_ok`, `_scan_photo_ok`, `_emp_photo_ok`) all call `can_loc`, which is business-safe since phase123, so a new upload already carries the business and a signed URL cannot be made for a foreign path (the select policy fails first). phase133 adds: restrictive policies `photos_scope133_read` / `_write` (while the switch is ON the place in the path must be one of the caller's businesses; the owner and, for reading only, the backup bot pass), `photo_business133(path)`, `photo_path133(prefix, place, name)` (a path for a new upload, refused for a foreign place) and `photo_unmapped133()` (owner: objects per business, objects whose path has no mapped place). A path without a numeric place (for example weird/x.jpg) is readable by nobody - not a leak, but such files should be moved. `phase133_test` T6 uses the mock bucket of the scratch build.

*What cannot be done on the free Supabase plan:* one bucket per business with its own size limit, MIME list and quota; separate storage backups or egress accounting per business; per-business signed-URL lifetime (it is one value, 1 hour). The free plan has one 1 GB pool and the bucket settings are bucket-wide, so the separation here is by policy and by path, not by bucket. The web upload code is unchanged (it already writes `<PREFIX>/<place>/...`).

**Bot identity.** The intake / Telegram bot is a login. `intake_bot_create(user, place)` (owner) gives it the place, so its `can_loc` is the business of that place; the border trigger on `inbound_messages` / `online_orders` refuses a message for a channel outside the bot's businesses (the call returns `failed`, the failure is queued for the owner, `phase133_test` T9). One bot per business is the supported set-up; one group bot keeps working if it is a member of every business (it then crosses the border by design). Anonymous entry points (`telegram_message_receive` secret hash, `attendance_punch_push` device token, `web_order_submit` channel code) are bound to their secret / device / channel and write rows tagged with that place.

**Notifications.** `_notif_ok` (phase123) filters the notes of a place by `can_loc`; phase133 adds nothing there (T9 proves a manager reads only his business's notes). `notify_scan`, `urgent_alerts`, `daily_digest` are group scans for the owner and the notify bot (group infrastructure); their notes carry the place, owner-audience notes are the owner's.

**Login side channel (audit test 13).** `login_precheck` returned the same shape for every id but `login_failed` only counted known ids, so a locked answer told that the id exists. While the switch is ON an unknown id is counted and locked like a known one (the table is cleaned of old unknown ids at random 1 in 50 calls). Locking is by staff id for the whole database - the usual risk of guessing ids to lock someone out exists with or without businesses.

## 7. Deferred and known limits (nothing is hidden)

1. **Per-business chart of accounts / per-entity books (Stage C2b).** There is ONE chart, one set of mappings, one opening journal, one bank-statement table. While the switch is ON those records are owner-only (a business accountant keeps posting and reading the journal of his own places through `can_loc`, but cannot edit the chart, the mappings, the opening journal or the bank reconciliation). Year closes were closed the same way in phase123.
2. **Master data (items, customers, suppliers, recipes, artisans, vocabularies)** is Stage C2 (phase132, other agent): the 60 MASTER functions are classified, not scoped, here. Until phase132 is pasted a second business sees the one item master.
3. **Books keys as per-business rule overrides** (`accounting_on`, `period_closed_until`, `acct_*`, fiscal year ...) can be overridden and user actions follow the caller's business (T2 proves a closed period of A does not close B), but the scheduler and the posting engine still run on ONE ledger with the group values until C2b. Use them only for limits and display; do not override `accounting_on` per business before C2b.
4. **The owner's own actions use the group values** unless the owner has chosen a working business (`master_context_set132`, phase132). A user who belongs to several businesses also gets the group values (the business is ambiguous). `rule_val_in133(key, business)` answers for a named business.
5. **The web still lists the global rule values** (it reads the `rules` table directly). A screen that shows the value a business really uses must call `rules_effective133()`; the Switchboard needs a business selector for `rule_override_set133` (B2 / web owner, `docs/regs/` line to be written by the lead).
6. **`org_manage`** is a GROUP-level grant (phase122): a holder sees and edits every business unit. Give it only to group administrators; it is not part of the "every grant" test persona of a business.
7. **Outbox of SMS / WhatsApp (`notify_*`)** has no business column: summary and cancel are owner-only while ON; the sender bot uses `notify_outbox_claim / report`. A per-business outbox needs a column (C2b).
8. **`cost_attrib_main_set`** (one main cost place for the whole database) is owner-only while ON; a per-business row set belongs to the per-business costing.
9. **Group scans** (`notify_scan`, `daily_digest`, `urgent_alerts`) stay group-wide for the owner and the notify bot by design; a business owner who is not the group owner reads `daily_digest_biz133`.
10. **Hot-path cost.** The border triggers read the switch once per transaction; `rule_val` is faster than before (the switch is cached per transaction); `can_do` is about 15 percent slower while OFF (one extra switch read). Measured on the scratch box only (`record_sale2` x 300: 1.09-1.21 s with phase133 against 1.31-1.37 s without; `rule_on` x 200,000: 1.8 s against 5.0 s; `can_do` x 100,000: 13.9 s against 11.9 s). With the switch ON every written row of a non-owner costs one `_biz_ok123` lookup per distinct place per transaction.

## 8. Not verified

Nothing ran on the owner's live Supabase or on a phone. The storage policies were tested on the mock bucket of the scratch build, not on the real `storage.objects` (on the real one the SQL editor must be allowed to create policies on it, as phase3 / phase41 / phase90 already do). The Supabase default-grant assumption (a function without an explicit revoke stays executable by `authenticated`) is the audit's assumption; the checker uses the scratch build, which mimics it. phase132 was tested only against C2's committed file (`5b39aa7`) in a scratch merge: `phase133_test` 269 / 0 and `phase132_test` 176 / 0 on the merged build; the lead must re-run both after the real merge and regenerate `tests/sql/scope_allowlist.txt` (`python3 tools/scope_classify133.py <db>`).

## 9. Keeping it current

* `select * from scope_gaps133();` (owner) lists what is not scope-aware by construction. After a change run `python3 tools/scope_classify133.py <db built through phase133 with the c3 seed users>`; it stops with `NO CLASS for ...` when a function has no reviewed class - add a rule with a reason, never a catch-all - and rewrites `tests/sql/scope_allowlist.txt` and this file.
* `bash tests/sql/final_build.sh <db>` then `psql ... -f supabase/phase133_test.sql | grep -E 'FAIL|RESULT'` (about 2 minutes; `-v skip_probe=1` skips the probe and takes 5 seconds, 266 checks).
* `bash tests/sql/c3_before_after.sh <db built WITHOUT phase133>` proves OFF = identical, ON owner = identical, and that the changed bodies are exactly the marked ones.
