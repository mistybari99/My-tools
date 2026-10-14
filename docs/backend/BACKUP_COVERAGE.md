# Backup / export / restore-drill coverage, phases 72..105 (audit)

Branch docs/d4. Method: fresh build of the canonical paste order (docs/PASTE_ORDER.md, through phase103, phase102 last), every `create table` of phases 72..103 (71 tables) compared with `public._backup_tables()`, and everything else that backs up, exports or restores was read: `supabase/phase46.sql` (backup_manifest, backup_dump), `supabase/phase70.sql` (restore drill, latest body of `_backup_tables`), `tools/backup_dump.py`, `tools/restore_backup.py`, `tools/restore_drill.py`, `tools/backup_photos.py`, `web/restoredrill.js`, `.github/workflows/backup.yml`.

## How coverage works (finding 1)

There is NO hard-coded table list anywhere. `public._backup_tables()` is computed at call time from `pg_class`: every table of schema `public` except names `%_secret%`, `ops_*`, `login_failures/login_attempts/login_throttle`, `backup_runs/notifications/notification_reads`, and any table with a column named like password / passwd / pin_hash / secret / token / salt / api_key / private_key (phase70 exempted `tokens_in/tokens_out`). `backup_manifest()`, `backup_dump()`, `tools/restore_backup.py` (reads the manifest) and `tools/restore_drill.py` (checks manifest tables == `_backup_tables()` of the scratch schema, then row counts per table, RLS on every table, journal debit = credit, stock ledger = balance) all use that one function. So a new table is included automatically. The risk is the other direction: a table silently dropped by the name filter.

## Result on the final build (248 tables in `public`, 237 before phase106)

| Group | Count | Status |
|---|---|---|
| New tables phases 72..103 in the backup | 68 of 71 | OK |
| `perm_conflict` (phase91) | 1 | MISSING until phase106: columns `token_a`/`token_b` match the secret filter, but they are permission names, not credentials |
| `telegram_secrets` (86), `intake_proofs94` (94) | 2 | Excluded on purpose (hash of a secret). Set the secret again after a restore |
| Older excluded tables (`attendance_devices`, `ops_accounts`, `login_*`, `backup_runs`, `notifications`, `notification_reads`) | 9 | Unchanged, by design |

Other checks: every public table has RLS (the drill's `rls` check passes); sequences are re-set by `restore_backup.py` after each table; generated columns are skipped; append-only triggers are switched off only during the restore and put back.

## Audit table: every table created in phases 72..103

Severity = what is lost if the table is not in the backup. High = money, ledger, cost or stock values.

| Table | Phase (first) | Rows on fresh build | In backup / restore drill | Severity |
|---|---|---|---|---|
| acct_post_errors72 | 72 | 0 | Yes (computed list) | High (money / ledger / cost) |
| artisans | 73 | 0 | Yes (computed list) | Medium (business records) |
| recipe_steps | 73 | 0 | Yes (computed list) | Medium (business records) |
| recipe_versions | 73 | 0 | Yes (computed list) | Medium (business records) |
| cost_component_types | 74 | 8 | Yes (computed list) | High (money / ledger / cost) |
| factory_cost_pools | 74 | 0 | Yes (computed list) | High (money / ledger / cost) |
| location_cost_cfg | 74 | 0 | Yes (computed list) | High (money / ledger / cost) |
| recipe_cost_components | 74 | 0 | Yes (computed list) | High (money / ledger / cost) |
| cost_bill_inputs | 75 | 0 | Yes (computed list) | High (money / ledger / cost) |
| cost_bill_shares | 75 | 0 | Yes (computed list) | High (money / ledger / cost) |
| cost_source_bills | 75 | 0 | Yes (computed list) | High (money / ledger / cost) |
| cost_source_locs | 75 | 0 | Yes (computed list) | High (money / ledger / cost) |
| cost_source_rule_shares | 75 | 0 | Yes (computed list) | High (money / ledger / cost) |
| cost_source_rules | 75 | 0 | Yes (computed list) | High (money / ledger / cost) |
| cost_source_types | 75 | 8 | Yes (computed list) | High (money / ledger / cost) |
| cost_sources | 75 | 0 | Yes (computed list) | High (money / ledger / cost) |
| inbound_message_events | 76 | 0 | Yes (computed list) | Medium (business records) |
| inbound_messages | 76 | 0 | Yes (computed list) | Medium (business records) |
| intake_bots | 76 | 0 | Yes (computed list) | Medium (business records) |
| intake_failures | 76 | 0 | Yes (computed list) | Medium (business records) |
| intake_hits | 76 | 0 | Yes (computed list) | Medium (business records) |
| order_dup_flags | 76 | 0 | Yes (computed list) | Medium (business records) |
| sales_channels | 76 | 0 | Yes (computed list) | Medium (business records) |
| online_order_flags | 77 | 0 | Yes (computed list) | Medium (business records) |
| cost_attrib_main | 78 | 0 | Yes (computed list) | High (money / ledger / cost) |
| cost_share_reassign | 78 | 0 | Yes (computed list) | High (money / ledger / cost) |
| grant_separation_pairs | 78 | 2 | Yes (computed list) | Medium (business records) |
| location_cost_attribution | 78 | 0 | Yes (computed list) | High (money / ledger / cost) |
| item_cost_flags | 80 | 0 | Yes (computed list) | High (money / ledger / cost) |
| sale_return_packaging80 | 80 | 0 | Yes (computed list) | High (money / ledger / cost) |
| setup_apply_batches81 | 81 | 0 | Yes (computed list) | Low (settings / helper) |
| setup_apply_lines81 | 81 | 0 | Yes (computed list) | Low (settings / helper) |
| setup_check_defs81 | 81 | 36 | Yes (computed list) | Low (settings / helper) |
| setup_rec_defs81 | 81 | 93 | Yes (computed list) | Low (settings / helper) |
| setup_topic_defs81 | 81 | 5 | Yes (computed list) | Low (settings / helper) |
| pos_failed_cards | 83 | 0 | Yes (computed list) | High (money / ledger / cost) |
| pos_replay_log | 83 | 0 | Yes (computed list) | High (money / ledger / cost) |
| acct_autopost_runs85 | 85 | 0 | Yes (computed list) | High (money / ledger / cost) |
| card_settlements85 | 85 | 0 | Yes (computed list) | High (money / ledger / cost) |
| manual_reason_codes85 | 85 | 4 | Yes (computed list) | High (money / ledger / cost) |
| telegram_chat_links | 86 | 0 | Yes (computed list) | Medium (business records) |
| telegram_secrets | 86 | 0 | NO - excluded on purpose (secret hash column) | Low (secret hashes, by design) |
| scan_events | 90 | 0 | Yes (computed list) | Medium (business records) |
| scan_jobs | 90 | 0 | Yes (computed list) | Medium (business records) |
| option_view_ops | 91 | 0 | Yes (computed list) | Low (settings / helper) |
| perm_conflict | 91 | 15 | NO before phase106 (token_a/token_b false positive); YES after | Medium (access-control rules) |
| perm_reco_ignore | 91 | 0 | Yes (computed list) | Low (settings / helper) |
| perm_reco_role | 91 | 63 | Yes (computed list) | Low (settings / helper) |
| role_option_view | 91 | 0 | Yes (computed list) | Low (settings / helper) |
| user_option_view | 91 | 0 | Yes (computed list) | Low (settings / helper) |
| invoice_shares | 92 | 0 | Yes (computed list) | High (money / ledger / cost) |
| doc_template_choice | 93 | 0 | Yes (computed list) | Low (settings / helper) |
| intake_proofs94 | 94 | 0 | NO - excluded on purpose (secret hash column) | Low (secret hashes, by design) |
| drawer_events | 95 | 0 | Yes (computed list) | High (money / ledger / cost) |
| ledger_cost_supply96 | 96 | 0 | Yes (computed list) | High (money / ledger / cost) |
| opening_stock_actions96 | 96 | 0 | Yes (computed list) | High (money / ledger / cost) |
| cost_charge_types | 97 | 15 | Yes (computed list) | High (money / ledger / cost) |
| item_logistics | 97 | 0 | Yes (computed list) | High (money / ledger / cost) |
| landed_cost_alloc | 97 | 0 | Yes (computed list) | High (money / ledger / cost) |
| landed_cost_basis | 97 | 0 | Yes (computed list) | High (money / ledger / cost) |
| landed_cost_docs | 97 | 0 | Yes (computed list) | High (money / ledger / cost) |
| landed_cost_lines | 97 | 0 | Yes (computed list) | High (money / ledger / cost) |
| landed_cost_stock | 97 | 0 | Yes (computed list) | High (money / ledger / cost) |
| landed_costs | 97 | 0 | Yes (computed list) | High (money / ledger / cost) |
| landed_skips | 97 | 0 | Yes (computed list) | High (money / ledger / cost) |
| landed_supplier_flags | 97 | 0 | Yes (computed list) | High (money / ledger / cost) |
| bill_pay_defaults99 | 99 | 0 | Yes (computed list) | High (money / ledger / cost) |
| bill_payments99 | 99 | 0 | Yes (computed list) | High (money / ledger / cost) |
| inbox_unmask_log99 | 99 | 0 | Yes (computed list) | Low (settings / helper) |
| item_categories | 100 | 5 | Yes (computed list) | Medium (business records) |
| opening_stock_followups103 | 103 | 0 | Yes (computed list) | High (money / ledger / cost) |
(Phase column is the first phase file that creates the table. Row counts are the seed rows of the fresh test build, not live data.)

## Not tables

| Item | In SQL backup? | Notes |
|---|---|---|
| Supabase Storage bucket `photos` (item pictures, receipts, staff photos, and from phase90 the scan photos `SCAN/<place id>/<uuid>.jpg`) | No: Storage objects are not in a SQL dump | `tools/backup_photos.py` (called by `.github/workflows/backup.yml`) copies the bucket nightly to the `backups` branch (up to 80 MB) or Google Drive; `photos_manifest.json` lists every path. The drill does not restore photos. Manual option: Supabase dashboard -> Storage -> bucket `photos`, or the Supabase CLI. This is phone-impossible / needs the dashboard or a computer |
| Auth users (logins) | No | Supabase Auth, not schema `public`. Same ids are needed before restoring into a new project |
| Policies on `storage.objects` (`scan_photos_insert`, `scan_photos_read`, phase90) | No | Come from the phase SQL files, not the backup |
| Views (`opening_covered103` ...) , functions, rules | Schema, not data | Rebuilt from the phase files in paste order; `rule_*` values are in tables `rules` / `rule_grants` and ARE in the backup |
| CSV / business exports in the web app | Not a backup | They are reports for reading; none of them is used by the restore |

## Fix: supabase/phase106.sql

* Re-creates `_backup_tables()` from its latest body (phase70) with one change: `token_a` / `token_b` are not treated as secrets. Result: `perm_conflict` is dumped, restored and checked by the drill. Tag `bos106`; nothing else changes (237 -> 238 tables).
* Adds owner-only, read-only `backup_coverage106()`: every public table, in backup yes/no, rows, and the reason when it is out. Use it to compare against `backup_manifest()` after any new phase.
* `tools/restore_drill.py`: the `skipped_by_dump` report uses the same exemption; `backup_coverage106` is listed as an optional function.
* Guard: raises `phase106 needs phases 72..103 pasted first` with the missing phase numbers. Paste twice is safe.
* `supabase/phase106_test.sql`: all 71 new tables covered or excluded on purpose, restore of every backed-up table into a scratch schema with equal row counts, owner-only access, second paste identical.
* Rule for the next phase: a new table is covered automatically unless it has a column whose name contains password / passwd / pin_hash / secret / token / salt / api_key / private_key. Name such columns differently, or add the exemption to `_backup_tables()` and to `skipped_by_dump` in `tools/restore_drill.py`. Always look at `backup_coverage106()`.

## Recommendation for the owner

* Run the restore drill (docs/RESTORE_DRILL.md) once a month for the first three months, then every quarter, and always after a new phase that adds tables. The app warns after 90 days (rule `restore_drill_warn_days`).
* Photos: the nightly backup copies the `photos` bucket, but check `photos_manifest.json` for a warning (photos larger than the git limit and no Drive set up are NOT copied). A full copy of the bucket by hand needs the Supabase dashboard or a computer; it cannot be done from the phone.
* After a restore, set the Telegram secret and the intake proofs again, and enrol attendance devices again (hashes are not backed up on purpose).
