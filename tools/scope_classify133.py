#!/usr/bin/env python3
"""Stage C3: classify every exposed SECURITY DEFINER function that scope_gaps133() lists (= not scope-aware by construction) and write
  tests/sql/scope_allowlist.txt   (reviewed list: name|class|reason, one line per function; phase133_test compares it with scope_gaps133())
  docs/audit_c1/C3_COVERAGE.md    (the coverage document: counts, classes, the table)
usage: python3 tools/scope_classify133.py <db built through phase133> [--check]       (env PGSOCK=/tmp PGPORT=5544)
--check only compares and exits 1 when a function has no class (a new function must be reviewed by a person: add it to RULES below with a reason, never to a catch-all).
The classes (final, per function; "FIXED" is found by the marker scope133 in the live body, everything else is the reviewed rule below):
  PRIM    permission / identity / pure helper: returns a flag or a date, reads no business row
  OWNER   group owner only (hard gate, or the group-level org_manage grant): group-wide on purpose
  OWN     only the caller's own rows (own favourites, own request, own log line)
  MASTER  shared master data (items, customers, suppliers, recipes, artisans, vocabularies): Stage C2 (phase132) scopes the rows; the function reads no place-bound business row
  CONFIG  configuration / catalogue / vocabulary / diagnostics without business rows
  INFRA   bot, device, webhook, queue or scheduler entry point: bound to its token, channel, device or place, or group infrastructure by design
  HELPER  reviewed: scoped through a helper, a trigger (<table>_xb133) or a grant WITH the row's place that the heuristic of scope_gaps133() does not see
  FIXED   scoped now by phase133 (a place filter, an owner gate while the switch is ON, a border trigger)
  DEFER   known gap, reason given (none left at the time of writing)
"""
import os, re, subprocess, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__)); REPO = os.path.dirname(HERE)
SOCK, PORT = os.environ.get('PGSOCK', '/tmp'), os.environ.get('PGPORT', '5544')
db = sys.argv[1]

def q(sql):
    r = subprocess.run(['psql', '-h', SOCK, '-p', PORT, '-U', 'postgres', '-d', db, '-qAt', '-F', '\x1f', '-R', '\x1e', '-c', sql], capture_output=True, text=True)
    if r.returncode: sys.exit(r.stderr)
    return [row.split('\x1f') for row in r.stdout.split('\x1e') if row.strip('\n')]

# (regex over the function name, class, reason). First match wins.
RULES = [
 (r'^(_a53_mgr|_acct_view|_assistant_ok|_cs_view|_i62_ok|_i62_pay_ok|_is_ops|_list_mgr|_loc_mgr|_org_on123|_other_approver_exists|_recipe_cost_ok|_recipe_read|_recipe_view_ok|_setup_view81|_sheet_viewer|biz_cost_ok|biz_ok|is_active|is_owner|rule_num|rule_on|rule_txt)$',
  'PRIM', 'permission / identity helper: returns a flag, reads no business row (the readers that use it filter by place themselves)'),
 (r'^(fiscal_year_end|fiscal_year_start|week_start_date|convert_qty|unit_factor|shelf_life_for|shelf_life_hours)$', 'PRIM', 'pure date / unit arithmetic over the shared item and unit tables (items are master data, Stage C2)'),
 (r'^(_release_can_see|decide_release)$', 'HELPER', 'has_grant(release_decide, <place of the entry>): the place is passed as a sub-select, scoped through has_grant (business border since phase123)'),
 (r'^(fa_asset_dispose)$', 'HELPER', 'updates one fixed asset by id: trigger fa_assets_xb133 refuses a foreign-business row ("not found" while the switch is ON)'),
 (r'^(payment_intent_set_ref)$', 'HELPER', 'updates one payment intent by id: trigger payment_intents_xb133 refuses a foreign-business row'),
 (r'^(request_release)$', 'HELPER', 'only the maker of the draft entry (or the owner) can ask; the entry is the caller\'s own'),
 (r'^(reopen_entry|assistant_log|cancel_emergency|client_error_log|dash_layout_get|dash_layout_save|entry_change_cancel|fav_meta_set|fav_order_set|login_success|my_context|my_emergency|my_option_views|option_views_for_user|set_my_lang|set_pin|touch_favourite|twofa_policy|wastage_cancel|log_report_export|log_report_export2|recon_export_log118|rpt131_log_export)$',
  'OWN', 'reads / writes only rows of the caller (own favourites, own request, own error line, own export log line, own roles)'),
 (r'^(assistant_access_list|assistant_note_retire|assistant_note_save|assistant_usage_summary|anon_exec_audit94|grant_separation_hint|grant_separation_report|permission_recommendations|reco_apply|reco_conflict_set|reco_ignore_set|reco_role_set|pii_exposure_report94|twofa_status_report|unlock_staff|ops_account_set|owner_self_approve_set|set_grant|set_user_grant|set_rule|set_role_option_view|set_role_option_view_bulk|set_option_view|set_option_view_bulk|role_option_views|staff_role_save)$',
  'OWNER', 'owner only (hard gate): people, roles, grants and group settings are group-wide; per-business values are rule_overrides / rule_grant_overrides133 / role_form_overrides133'),
 (r'^(role_scope_set133|grant_scope_set133|rule_override_set133|rule_grant_override_set133|role_form_override_set133|scope_gaps133|photo_unmapped133)$', 'OWNER', 'owner only (new in phase133): per-business settings, coverage checker, storage overview'),
 (r'^(att_self_lock_set|att_site_geo_set|attendance_device_register|attendance_device_set_active|attendance_device_token_reset|blind_cfg_set|comparison_pair_save|forms_ledger_cfg_set|loc_cost_cfg_set|loc_cost_driver_set116|location_block_override|manual_reason_set|notify_template_save|pin_sig_cfg_set|sales_channel_save|set_doc_template|set_daybook_opening|set_daybook_start|acct_set_start|year_close_reverse|cost_type_driver_set116|cost_type_gl_set117)$',
  'OWNER', 'owner only (hard gate): configuration of a place / of the books written by the group owner'),
 (r'^(backup_coverage106|backup_status|backup_stock_balance|backup_stock_ledger|bi_export_log_list|bill_pay_default_set99|bill_pay_defaults_list99|biz_suggest|dup_suspects|form_guard_recommendations|guard_recommendations|inbox_unmask_log_list99|never_opened_negative_items|owner_board_get|owner_board_save|owner_money_link|paper_serial_collisions|parallel_waiting|production_recommendations|receipt_duplicates|report_fact_rebuild|restore_drill_list|restore_drill_record|restore_drill_status|sale_form_unlink|setup_apply_history|setup_recommend_apply|setup_recommendations|shadow_count_once_check|shadow_void|stock_batch_reconcile|stock_reconcile|unit_unknown_items|web_form_embed|opening_stock_apply96|payroll_approve|payroll_payment_void|intake_bot_check|intake_bot_create|intake_bot_set|intake_failure_dismiss|intake_proof_set94|intake_proof_status94|intake_purge|telegram_secret_set|telegram_status)$',
  'OWNER', 'owner only (hard gate): whole-database tool of the group owner (reconciliation, backup, audit, bots and their secrets, payroll approval)'),
 (r'^(org_scope_grant|org_scope_revoke|org_scope_list|org_tree|org_unit_save|org_unit_deactivate)$', 'OWNER', 'group owner or the group-level org_manage grant (phase122/123); org_tree already shows a non-owner only the chain of his own places'),
 (r'^(master_share_create|master_share_revoke|master_share_list|master_scope_report132|org_masters_relax_unique|org_masters_restore_unique)$', 'OWNER', 'owner only (hard gate; list and report: owner or the group-level org_manage grant): the Stage C2 (phase132) share registry, the master coverage report and the unique-key relax / restore are group-level tools'),
 (r'^partner_', 'OWNER', 'partners module: every function starts with _a44_guard() = owner only'),
 (r'^(tier_reorder|tier_save|gift_rule_save|set_unit_conversion|list_def_set|list_manager_set|item_class_map_set|item_type_set|item_master_import_apply|item_master_import_preview|item_mapping_load|item_mapping_autolink|category_merge|category_rename)$',
  'OWNER', 'owner only (hard gate) and master data: the owner edits the shared vocabularies / master (Stage C2 scopes the rows)'),
 (r'^(artisan_list|artisan_register|artisan_save|artisan_set_active|category_list|category_move|category_reorder|category_rule_state|category_save|category_sync100|customer_points|customer_points_adjust|customer_points_redeem|customer_save|customer_set_tier|decide_item_change|gift_issue|item_apply|item_cost_free_set|item_dup_check|item_map_accept_confident|item_map_decide2|item_mapping_decide|item_new|item_next_code|item_set_category|item_set_category_bulk|items_bulk_apply|items_missing_category|items_search_info126|landed_logistics_set|landed_supplier_flag_set|packaging_set|recipe_approve|recipe_copy|recipe_cost_component_retire|recipe_cost_component_set|recipe_cost_components_get|recipe_labour_suggest|recipe_save|recipe_save_full|recipe_set_active|recipe_set_artisan|recipe_steps_save|recipe_unassigned|save_supplier|scan_match_items|scan_match_suppliers|submit_item_change|supplier_pick|option_add|option_other_log|option_reactivate|option_reorder|option_retire|option_similar|list_queue_counts|option_other_resolve|option_request_decide|option_update)$',
  'MASTER', 'shared master data (items, customers, suppliers, recipes, artisans, categories, vocabularies): rows are scoped by Stage C2 (phase132); the function reads no place-bound business row'),
 (r'^(benefit_type_save|cost_source_type_add|cost_type_add|cost_type_smoothing|landed_charge_type_save|landed_info|manual_reasons85|pin_sig_active|report_catalog|report_catalog2|report_catalog3|report_presets|rpt131_catalog|client_error_resolve|client_errors_list|client_errors_purge|client_errors_summary)$',
  'CONFIG', 'configuration / catalogue / vocabulary / diagnostics: no business rows (report catalogues list report names and filters; client errors are technical messages)'),
 (r'^(acct_autopost_runs_list|assistant_proxy_check|attendance_punch_push|backup_dump|backup_log|backup_manifest|backup_status|notify_config|web_form_catalog|inbound_message_receive|login_failed|login_precheck|notifications_mark_emailed|notify_enqueue|notify_optin_set|notify_outbox_claim|notify_outbox_report|notify_scan|payment_webhook_receive|telegram_message_receive|urgent_alerts)$',
  'INFRA', 'bot / device / webhook / queue / scheduler entry point: bound to its token, channel or device, or group infrastructure by design (writes are location-tagged and stopped by the border triggers for a business-limited bot; group scans belong to the owner or to a bot that is a member of every business)'),
]

TAIL = """## 6. Storage, bot identity, notifications, login

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
"""

def write_doc(out, q, marked):
    tot = int(q("select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosecdef and p.prorettype <> 'trigger'::regtype and has_function_privilege('authenticated', p.oid, 'execute')")[0][0])
    anon = int(q("select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosecdef and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'execute')")[0][0])
    trg = int(q("select count(*) from pg_trigger where tgname like '%\\_xb133'")[0][0])
    chg = sorted(x for x in marked)
    cnt = collections.Counter(c for _, c, _ in out)
    gaps = len(out) - sum(1 for fn, _, why in out if why.startswith('[c2] owner tool'))
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    for fn, c, why in sorted(out): by[c][why].append(fn)
    names = {'PRIM': 'PRIM - permission / identity / pure helper', 'OWNER': 'OWNER - group owner only (group-wide on purpose)', 'OWN': 'OWN - only the caller\'s own rows', 'MASTER': 'MASTER - shared master data, Stage C2 (phase132)',
             'CONFIG': 'CONFIG - configuration / catalogue / vocabulary / diagnostics', 'INFRA': 'INFRA - bot / device / webhook / queue / scheduler', 'HELPER': 'HELPER - reviewed: scoped through a helper, a trigger or a grant with the place',
             'FIXED': 'FIXED - scoped now by phase133', 'DEFER': 'DEFER - known gap'}
    L = []
    L.append('# C3 coverage - behaviour, permissions and reports kept apart between businesses (Stage C3, phase133)\n')
    L.append('Branch `local-c3`. Written by `tools/scope_classify133.py` from a built database (do not edit by hand: change the RULES of the tool and run it again). Nothing here is pasted or pushed.\n')
    L.append('Plan and audit: `docs/GROUP_ERP_STAGE_A.md` sections 3.4 and 10, `docs/audit_c1/RLS_ISOLATION_AUDIT.md` (Appendix B: 179 read-only SECURITY DEFINER functions that are not scope-aware, 429 in total, global rules / grants / roles, `user_grants` with NULL place, storage, bot identity, negative tests 9, 10, 11, 13). Master data is Stage C2 (C2_COVERAGE.md of the C2 branch, other agent).\n')
    L.append('## 1. Method (three independent checks)\n')
    L.append('1. **Static, by construction** - `scope_gaps133()` (owner function in phase133) lists every exposed SECURITY DEFINER function whose body does not call a scope primitive (`can_loc`, `can_scope`, `_biz_ok123`, `_my_biz123`, `business_of_location`, `has_grant` / `can_do` with a place argument ...), directly or through a callee (fixpoint over the call graph; a callee without arguments only counts when it returns a set). Exposed = EXECUTE granted to `authenticated` (the scratch build mimics the Supabase default grants, so a function without an explicit revoke is exposed).')
    L.append('2. **Review** - each of those functions was read (or its family) and put in a class with a reason (section 4). `tests/sql/scope_allowlist.txt` is that reviewed list; `phase133_test` T11 fails when the checker and the list differ, so a new function without a scope call, or a function that stops being scope-aware, is noticed.')
    L.append('3. **Dynamic, differential probe** - `tests/sql/c3_probe.sql`: with the switch ON, three personas of business A (staff, manager, a user holding every role and every grant) and a notify bot call every exposed function (about 800) with plausible arguments inside a sub-transaction that is always rolled back; the answers are compared between a database where only A has data (S1) and one where B has data too (S2) - they must not change - and with B places / ids swapped in, which must look exactly like a missing id. `phase133_test` T13 fails on any difference that is not in `tests/sql/scope_probe_known.txt` (11 reviewed entries: master data of C2, group infrastructure, sequence ids).\n')
    L.append('## 2. Numbers\n')
    L.append('| Measure | Count |\n|---|---|')
    L.append('| exposed SECURITY DEFINER functions (this build, after phase133; net 18 more than before) | %d (%d of them also executable by `anon`: login, device and webhook entry points, reviewed in the C1 audit and in phase94/121) |' % (tot, anon))
    L.append('| scope-aware by construction (direct primitive or through a callee) | %d |' % (tot - gaps))
    L.append('| NOT scope-aware by construction, reviewed one by one (the list below) | %d |' % gaps)
    L.append('| ... before phase133 the same checker found | 338 of 808 |')
    L.append('| functions whose body phase133 re-creates or patches (marker `scope133`) | %d (4 re-created with the old text as the OFF branch, %d patched by exact-text insert) |' % (len(chg), len(chg) - 4))
    L.append('| border triggers `<table>_xb133` (write side, every table with a place column) | %d |' % trg)
    L.append('')
    L.append('Classes of the %d reviewed functions (the audit asked for: scoped now / truly global / owner-only / deferred):\n' % gaps)
    L.append('| Class | Count | Meaning |\n|---|---|---|')
    for c in ('FIXED', 'HELPER', 'OWNER', 'OWN', 'PRIM', 'CONFIG', 'INFRA', 'MASTER', 'DEFER'):
        n = sum(1 for fn, cc, why in out if cc == c and not why.startswith('[c2] owner tool')) if c == 'OWNER' else cnt.get(c, 0)
        L.append('| %s | %d | %s |' % (c, n, names[c].split(' - ', 1)[1]))
    L.append('')
    L.append('Summary in the audit\'s words: **scoped now** = the %d functions that carry the marker (they are scope-aware after the patch; those that only got an owner gate are listed as FIXED) + %d border triggers + the restrictive policies; **truly global** = PRIM + CONFIG + OWN + INFRA (%d); **owner-only** = OWNER (%d); **shared master (Stage C2)** = MASTER (%d); **deferred with a reason** = section 7.\n' % (len(chg), trg, cnt['PRIM'] + cnt['CONFIG'] + cnt['OWN'] + cnt['INFRA'], cnt['OWNER'] - 6, cnt['MASTER']))
    L.append('## 3. What phase133 changed (switch ON only; OFF is byte-identical, proved by `tests/sql/c3_before_after.sh`)\n')
    L.append('1. **Per-business settings.** `rule_overrides` (business x rule key): `rule_val` / `rule_on` / `rule_num` / `rule_txt` answer with the value of the caller\'s working business (the single business of the user, or the working business of phase132 when pasted), else the group value; the group owner without a working business gets the group value. `rule_override_set133` (owner; same validation as `set_rule`; group-only keys - security, assistant, ui, integrations, backup, scan quotas, `org_scope_on` - are refused), `rule_overrides_list133`, `rule_val_in133`, `rules_effective133` (for the screens). Audit test 10 is `phase133_test` T2.')
    L.append('2. **Per-business roles and grants.** `rule_grant_overrides133` (business x grant x role, allow or take away) and `role_form_overrides133` (form rights of a role); `can_grant`, `has_grant(code, place)` and `can_do` read the matrix of the place\'s business. `roles.org_unit_id` and `grant_defs.org_unit_id` (NULL = shared catalogue): a role / grant that belongs to one business is invisible to the others, with its `rule_grants` / `role_form_perms` rows. `management` is per business since phase123 (scope rows); the last readers of the role name (`assistant_health`, `org_scope_preflight`) are limited to the caller\'s businesses. A personal NULL-place grant means "my businesses" (phase123) and is not touched by a role override.')
    L.append('3. **Write border.** A trigger on %d tables stops a non-owner from inserting / updating / deleting a row of a place outside his businesses, whatever function does it (id swap, parameter swap). `phase133_test` T5.' % trg)
    L.append('4. **Patched functions** (section 5). **Owner-only while ON** for the records that have no business column: chart of accounts, mappings, opening journal, bank statements and matches, scheduler, the main cost place, the setup advisors (they count the whole database), the SMS outbox summary / cancel.')
    L.append('5. **Reports and digests.** `report_run` (including `receivable_aging`) and `rpt131_*` were already place-scoped through `can_loc` (tested in T9 with hand numbers); `my_context` returns only the caller\'s own rows. `daily_digest` is the GROUP digest (owner or the notify bot); `daily_digest_biz133(business, date)` is the same digest for one business (owner, the notify bot, or the management of that business) with that business\'s rules. `acct_status`, `acct_post_pending`, `acct_pending_alert85`, `profit_source_check` count only the documents of the caller\'s places; `customer_dues_net113`, `_cust_bal` / `customer_balance` / `find_customer` count only the caller\'s businesses.')
    L.append('6. **Storage** (section 6). **Bot identity and notifications** (section 6). **Auth side channel** (audit test 13): while ON an unknown staff id is counted and locked like a known one, so `login_precheck` never tells whether an id exists.\n')
    L.append('## 4. The reviewed list (functions that are not scope-aware by construction)\n')
    for c in ('FIXED', 'HELPER', 'OWNER', 'OWN', 'PRIM', 'CONFIG', 'INFRA', 'MASTER', 'DEFER'):
        if c not in by: continue
        L.append('### %s\n' % names[c])
        for why, fns in sorted(by[c].items(), key=lambda kv: -len(kv[1])):
            L.append('- %s\n  `%s`' % (why, '`, `'.join(fns)))
        L.append('')
    L.append('## 5. Functions patched or re-created by phase133 (marker `scope133`)\n')
    L.append('`' + '`, `'.join(chg) + '`\n')
    L.append(TAIL)
    with open(os.path.join(REPO, 'docs/audit_c1/C3_COVERAGE.md'), 'w') as fh: fh.write('\n'.join(L).rstrip('\n') + '\n')

def main():
    owner = q("select user_id from public.user_roles where role_code = 'owner' limit 1")
    if not owner: sys.exit('no owner in the database: build with tests/sql/e2e/00_common.sql users first')
    owner = [[owner[0][0].strip()]]
    rows = q("select set_config('request.jwt.claim.sub', '" + owner[0][0] + "', false); ")  # session-local only
    # scope_gaps133 needs the claim in the SAME session: run one psql with both statements
    import tempfile
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as fh:
        fh.write("\\o /dev/null\nselect set_config('request.jwt.claim.sub', '" + owner[0][0] + "', false);\n\\o\nselect fn, args, gate, coalesce(tables_, '') from public.scope_gaps133() order by fn, args;\n")
    r = subprocess.run(['psql', '-h', SOCK, '-p', PORT, '-U', 'postgres', '-d', db, '-qAt', '-F', '\x1f', '-R', '\x1e', '-f', fh.name], capture_output=True, text=True)
    os.unlink(fh.name)
    if r.returncode: sys.exit(r.stderr)
    gaps = [x.split('\x1f') for x in r.stdout.split('\x1e') if x.strip('\n')]
    marked = {x[0] for x in q("select distinct proname from pg_proc where pronamespace = 'public'::regnamespace and prosrc like '%scope133%' and proname !~ '133$'")}
    out, missing = [], []
    for fn, args, gate, tabs in gaps:
        fn = fn.strip()
        if fn in marked and fn not in ('rule_val', 'can_grant', 'can_do', 'has_grant'):
            body = q("select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = '" + fn + "' limit 1")[0][0]
            why = 'owner gate while the switch is ON (company-level books / outbox record: one chart, one set of bank statements, one queue until the per-entity books)' if re.search(r"_org_on123\(\) and auth\.uid\(\) is not null and not public\.is_owner\(\)", body) \
                  else 'patched in phase133: place filter / business check on the rows it reads or writes (old text kept as the OFF branch)'
            out.append((fn, 'FIXED', why)); continue
        for rx, cls, why in RULES:
            if re.search(rx, fn): out.append((fn, cls, ('[c2] ' + why) if cls == 'MASTER' else why)); break
        else:
            missing.append(fn)
    # owner tools of phase132 (C2, master data per business): they exist only when that phase is pasted; listed here so the merged build needs no second review
    for fn in ('master_scope_report132', 'master_share_create', 'master_share_list', 'master_share_revoke', 'org_masters_relax_unique', 'org_masters_restore_unique'):
        if fn not in {x[0] for x in out}: out.append((fn, 'OWNER', '[c2] owner tool of phase132 (master shares, unique-constraint relaxing, master scope report); present only when phase132 is pasted'))
    if missing:
        print('NO CLASS for %d function(s): %s' % (len(missing), ', '.join(missing))); sys.exit(1)
    if '--check' in sys.argv:
        cur = {l.split('|')[0] for l in open(os.path.join(REPO, 'tests/sql/scope_allowlist.txt')) if l.strip() and not l.startswith('#')}
        new = {x[0] for x in out}
        if cur != new: print('allowlist differs: missing', sorted(new - cur), 'stale', sorted(cur - new)); sys.exit(1)
        print('allowlist OK (%d functions)' % len(new)); return
    write_doc(out, q, marked)
    with open(os.path.join(REPO, 'tests/sql/scope_allowlist.txt'), 'w') as fh:
        fh.write('# Reviewed list for phase133_test: every exposed SECURITY DEFINER function that scope_gaps133() reports (not scope-aware by construction).\n')
        fh.write('# name|class|reason   classes: PRIM OWNER OWN MASTER CONFIG INFRA HELPER FIXED DEFER (tools/scope_classify133.py, docs/audit_c1/C3_COVERAGE.md).\n')
        fh.write('# A new function that lands in scope_gaps133() makes the test fail until a person adds it here with a reason (never a catch-all).\n')
        for fn, cls, why in sorted(out): fh.write('%s|%s|%s\n' % (fn, cls, why))
    cnt = collections.Counter(c for _, c, _ in out)
    print('allowlist written: %d functions %s' % (len(out), dict(cnt)))

if __name__ == '__main__':
    main()
