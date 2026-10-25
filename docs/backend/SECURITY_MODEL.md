# Security model

Sources: `supabase/schema.sql`, `phase7.sql`, `phase8.sql`, `phase10.sql`, `phase11.sql`, `phase76.sql`, `phase80.sql`, `phase90.sql`, `phase94.sql`, `phase99.sql`, edge sources, `docs/briefs_p2p3/step_Sec_REPORT.md`, `docs/HANDOVER.md`. **Live ACLs of the production database were never inspected from this repository (UNVERIFIED);** use the audit functions in section 9 on the live database.

## 1. Identity and permission helpers

| Function | Meaning | Defined in |
|---|---|---|
| `is_active()` | profile exists and `status = 'active'` (new users stay `pending` until the owner approves; the very first user becomes the owner) | `schema.sql` |
| `is_owner()` | active and holds role `owner` | `schema.sql` |
| `can_do(form, action)` | action in `view` / `enter` / `approve` through `user_roles` -> `role_form_perms`; owner always; an approved emergency request `form_access` can open `view`/`enter` (never `ITEM_COST`) | `schema.sql`, re-created in `phase7.sql` |
| `can_loc(location)` | owner, or role `management`, or a row in `user_locations`, or an approved emergency request `loc_access` | `phase2.sql` / `phase7.sql` |
| `has_grant(code, loc)` | owner, or role grant (`can_grant`), or a person grant in `user_grants` (not expired; location null or equal), or an approved *window* emergency request | `phase8.sql` |
| `biz_ok()`, `biz_cost_ok()`, `_cost_ok(loc)`, `_recipe_cost_ok()`, `rpt_cost_ok()` | report / **cost** visibility: owner, `ITEM_COST` view, grant `view_cost` / `view_profit` | `phase8.sql`, later phases |

Grants (`grant_defs`) are delegable by the owner: per role (`rule_grants`) or per person with an end date (`user_grants`, `set_user_grant`, shown on the delegation board). A grant with `window_type = 'window'` or `'once'` can be obtained through an **emergency request** the owner approves for a short time (`emergency_requests`, rules `em_*` default OFF).
Non-blocking *separation* hints (phase 78 `grant_separation_hint`): the same person holding both "enter" and "approve" is suggested against, not forbidden; the owner may always approve (phase 87) and the approval is kept as an audit row (`self_approved`).

Pattern inside every write function: `is_active()` first, then `can_loc(loc)`, then `has_grant(...)` or `can_do(...)`, then `lock_check(date)` (closed period) - and raise `not allowed` / `not allowed for this location` otherwise.

## 2. Cost secrecy

Cost is secret by default. Rules that are enforced in the database:
1. `stock_ledger.unit_cost`, `stock_balance.avg_cost` and all value columns are **not granted** to `authenticated` (`phase10.sql`: `grant select (id, item_id, location_id, qty_delta, reason, ... ) on stock_ledger` leaves out `unit_cost`; `stock_balance` grants only `item_id, location_id, qty, updated_at`).
2. Cost reaches a browser only through functions that test `_cost_ok(loc)` / `biz_cost_ok()` / `_recipe_cost_ok()` (e.g. `stock_avg_cost`, `stock_valuation`, `recipe_cost`, `inventory_vs_gl`, all `landed_*`, `cost_wait_*`). Without the right they return nothing or `not allowed`.
3. Customer-facing outputs have no cost fields at all: `web/tpl_*.js` templates and `tpl_samples.js` contain none.
4. Scan: a purchase-bill photo is visible only with the cost right (`_scan_photo_ok` needs `_scan_content_ok`, phase 94 H1).
5. Landed-cost, cost-source and attribution tables are closed to the browser; every read/write is a definer function with cost right + grant.
6. Artisan names (phase 73) are stored only in `artisans.name`, a column the browser cannot read; everywhere else only the id (`artisan-N`) and post.
7. `repo`: `docs/SETUP.md` states `schema.sql` and the seed CSV contain cost prices - keep the source repository **private**. Only `web/` (public URL + publishable key) may be published.

## 3. RLS patterns

* Every table has RLS enabled (`alter table ... enable row level security`, `schema.sql`) and read policies of the form
  `using (public.can_loc(location_id) and (public.can_do('POS','view') or ... or public.has_grant('x', location_id)))`.
* Write policies are normally absent for `authenticated`: writes go through `SECURITY DEFINER` functions (`set search_path = public`). Owner-only tables use `for all ... using (public.is_owner()) with check (public.is_owner())`.
* Column-level grants hide secret columns (cost, phone, address); a rule can toggle them: trigger `rules_pii76` revokes/grants `select (customer_mobile, address) on online_orders` when `inbox_pii_guard_on` changes.
* Read-only helpers used inside policies are granted explicitly (`_cost_ok`, `_pur_ok`, `_all_locs`); other internal helpers are revoked from `public, anon, authenticated`.
* Append-only tables use triggers (`_append_only23`, `_shadow_ro`, `_inb_ro76`) so even `postgres`-level updates are refused.

## 4. PII masking

* Online orders and inbox messages hold customer phone and address (`phase76`). Switch `inbox_pii_guard_on` (default OFF; recommendation row says ON): when ON, phone/address are hidden unless owner or grant `inbox_contact_view`; each view is written to `audit_log` (`_inb_audit_view`).
* `phase99`: rule `inbox_pii_mode` = off (default) / mask_phone / mask_phone_address / mask_all_pii; `inbox_unmask(kind, id, reason)` (grant `inbox_unmask`, owner always) reveals ONE message/order; every reveal goes to `inbox_unmask_log99` and `audit_log`; optional daily cap `inbox_unmask_daily_max`. Phase 103 extends masking to `customer_directory` / `find_customer` (`_cust_pii103`).
* Not masked (documented gaps): a direct table read of `online_orders.customer_mobile/address` when the guard is OFF; the order edit form of `salesx.js`; `online_order_get` still returns `to_jsonb(o)` (phase 94 L10). A direct column read cannot be logged by the database.
* `pii_exposure_report94()` (owner): guard state, whether `authenticated` can read the columns directly, POS-view user count, audited views in 30 days.
* Photos may contain personal data: bucket `photos` is forced private (phase 90).

## 5. Idempotency (`client_id`)

A retried request must never create a second record:
| Place | Key |
|---|---|
| POS sale | `record_sale2(p_client)` - same user returns the old sale; another user's id -> `client_id_taken` |
| Stock ledger | unique `(client_id, reason)` (`stock_ledger_client`); `stock_post` returns the old row |
| Form entries outbox (phase 17), payroll, expense, opening stock, landed cost, cost supply, scan confirm | client uuid parameter (many functions raise `client_id_needed` / `client_id_required` when it is missing) |
| Online order | `online_orders.sale_client` (given to `record_sale2`), unique `sale_id` per order; web form `submission uuid` |
| Inbox / Telegram | unique `(channel, external id)` / `(channel, update_id)` |
| Payment webhooks | unique `(provider, event_id)` |
| Journal | unique `je_source_uq (source_type, source_id)` where not a reversal |
Known gap: no payload hash on a `client_id` replay (phase 94 L4 not built).

## 6. Audit and append-only trails

* `audit_log` is append-only: triggers `audit_log_no_change` (update/delete) and `audit_log_no_truncate`; refused for everyone (`phase11.sql`). `log_change(keycols)` triggers write audit rows on settings tables (rules, grants, path switches, mappings ...).
* Immutable by design: `stock_ledger`, `journal_entries/lines` (a fix is a reversing entry), `shadow_links` trail, `item_bulk_batches`, `bank_statement_lines`, `bank_recon_trail`, `ledger_cost_supply96`, `opening_stock_followups103`, `landed_cost_alloc/stock`, `scan_events`, `drawer_events`, `invoice_share_log92`, `payment_webhook_log`, `restore_drills`, `cost_share_reassign`.
* `no_hard_delete` triggers: nothing is deleted; retire with `active=false`/void flag. Codes of locations/forms are immutable.
* Recipe versions used by a production run are immutable; partner agreements become immutable once active.

## 7. Intake bot, ops bot, anon

* **Intake bot** (phase 76 `intake_bots`, phase 80 role `intake_bot` + form `ONLINE_INTAKE` enter-only): a normal Auth user marked by the owner (`intake_bot_create(user, place)`; `intake_bot_set` refuses the owner). It can create online orders and receive messages/web orders; it has **no POS right** (cannot sell, edit, confirm, deliver or read the inbox). The edge functions sign in as this user.
* **Ops bot** (phase 46 `ops_account_set(user, purpose, active)`, `_is_ops(purpose)`): least-privilege user for backup and notification workers. `service_role` is never used anywhere.
* **Anon:** `phase94` M6 revokes execute from `public, anon` on the re-created functions (and `online_order_save`, `rpt_agg_sql`, `stock_post`, `recipe_save`, `recipe_copy`); `authenticated` keeps exactly what it had. Functions that anon legitimately runs: `login_precheck`, `login_failed`, `attendance_punch_push` and some old helpers (expected list in the Sec report). The phase 94 harness showed 24 more definer functions anon could run (`record_sale`, `resolve_exception`, `request_release`, `staff_directory` ...) - whether the live ACL equals the harness is **UNVERIFIED**.
* New functions: always `revoke all ... from public, anon` then `grant execute ... to authenticated` (see any `phaseNN.sql` tail).
* Intake flood control (phase 94): rules `intake_reject_max_per_min`, `inbox_rate_max_per_min`, `intake_purge(days)`; proof hashes `intake_proofs94` (`intake_proof_set94`), constant-time compare; Telegram secret token required in the edge function and compared by hash in the DB.
* PIN: wrong-PIN lock is server-side since phase 11 (`login_precheck`, `login_failed`, `unlock_staff`). Supabase's own rate limits still apply. PIN signatures (phase 18) are a second *login* on the same phone. TOTP 2FA (phase 71) uses Supabase Auth MFA; `twofa_enforce_owner_writes` default OFF.
* Offline sale age (`offline_sale_max_age`), AI scan limits (`scan_ai_max_per_job`, `scan_ai_max_per_user_day`) are empty = unlimited until the owner types a number.

## 8. Secrets handling

Never in the repo, never in chat, never in `web/config.js` (public URL + publishable key only). Names only:
| Secret | Where it lives | Used by |
|---|---|---|
| `ANTHROPIC_API_KEY`, `SCAN_AI_MODEL` | Supabase secrets | `scan-extract` (and `assistant-proxy`) |
| `INTAKE_BOT_EMAIL`, `INTAKE_BOT_PASSWORD` | Supabase secrets | `telegram-webhook`, `meta-webhook`, `web-order` |
| `TELEGRAM_SECRET_TOKEN` | Supabase secrets; the same value given to Telegram `setWebhook` and (hashed) to `telegram_secret_set` | `telegram-webhook` (required since bos94) |
| `INTAKE_PROOF_SECRET` | Supabase secrets + `intake_proof_set94` | optional proof for Meta / web form |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | provided to edge functions by Supabase; GitHub secrets for workflows | all |
| Backup/notify secrets (`BOT_EMAIL`, `BOT_PASSWORD`, Drive credentials ...) | GitHub Actions secrets | `.github/workflows/*.yml`; setup in `docs/OPS_SETUP.md` |
| Telegram bot token | the owner only; **not read by any function in this repo** | owner's own `setWebhook` calls |
Rotate `INTAKE_BOT_PASSWORD` after any suspicion. Scheduled workflows run only from the repository **default branch**; the backup workflow stops itself on a public repo (backups contain sales, costs, salaries - the repo must be private).

## 9. What only the owner can do (no agent, no repo change can replace it)
1. Paste SQL into the Supabase SQL editor (phones only; the agent sandbox cannot reach the database) in the order of `docs/PASTE_ORDER.md`.
2. Turn on / choose every switch and number: `accounting_on`, `accounting_start_date`, `inbox_pii_guard_on`, `offline_sale_max_age`, `scan_ai_max_*`, `inbox_rate_max_per_min`, `landed_cost_mode`, costing mode per place, path switches, `purchase_grn_guard`, `report_cost_source` ... (the setup advisor `setup_recommendations()` only *recommends*).
3. Create the Auth users (ops bot, intake bot), then `ops_account_set` / `intake_bot_create`; enable MFA in the Supabase dashboard (docs/TWOFA.md); Confirm-email setting (docs/SETUP.md).
4. Deploy edge functions (needs a computer + Supabase CLI), set their secrets, register the Telegram/Meta webhooks, create the bot at the messaging provider.
5. Run, on the live database: `select anon_exec_audit94()`, `select pii_exposure_report94()`, `stock_reconcile()`, `inventory_vs_gl(...)`, `shadow_count_once_check()`, and `intake_purge(days)` now and then.
6. Decide the "owner decision" items listed under **Not done** in each `docs/briefs_p2p3/*_REPORT.md` (e.g. landed late-cost mode, counter account for manual production-in, opening-stock option).
7. Record restore drills (`restore_drill_record`) after actually restoring a backup.
