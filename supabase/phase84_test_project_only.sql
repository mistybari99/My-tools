-- Phase 84 part 2 (bos84) - GUARDED TEST-PROJECT RESET (G13). TEST PROJECTS ONLY. NEVER PASTE THIS FILE INTO THE LIVE PROJECT.
-- Paste after phase84.sql, only in a scratch / test Supabase project. Paste-twice safe. Not part of the main paste order.
--   Refuses unless ALL of: caller is the owner, rule allow_test_reset is ON
--   (default OFF), and the confirmation phrase is exactly 'DELETE ALL TEST DATA'. It clears the transactional tables listed in
--   _e_reset_tables() and nothing else; setup tables (items, rules, roles, locations, forms, lists, chart of accounts ...) are protected by a
--   second list that is checked before anything is touched. It switches allow_test_reset OFF again when done, and writes one line to
--   _e_reset_log. It must never be run on the live project.
-- Hazard (HANDOVER_5): re-pasting an OLD phase never touches these functions; they call existing reports only.

-- ---------- rule (default OFF; owner sets it in the rules page) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('allow_test_reset', 'settings', 'switch', 'false', null, null, null, null,
  'টেস্ট প্রজেক্টে সব লেনদেন মুছে ফেলার অনুমতি', 'Test project: সব লেনদেন মুছে ফেলার অনুমতি', 'Allow clearing all transactions (TEST PROJECT ONLY)',
  'শুধু টেস্ট প্রজেক্টে চালু করুন। আসল প্রজেক্টে কখনও নয়। একবার মোছার পর নিজে থেকে বন্ধ হয়।',
  'Turn ON only in a test project, never in the live one. Switches itself OFF after one reset. Setup data (items, rules, roles, places) is never cleared.', 990)
on conflict (key) do nothing;

-- ---------- reset log (append only; never cleared by the reset) ----------
create table if not exists public._e_reset_log (
  id bigserial primary key,
  done_at timestamptz not null default now(),
  done_by uuid,
  database_name text,
  tables_cleared int,
  rows_cleared bigint,
  detail jsonb
);
alter table public._e_reset_log enable row level security;
revoke all on public._e_reset_log from public, anon, authenticated;
create or replace function public._e_reset_log_ro() returns trigger language plpgsql as $$
begin raise exception 'append_only: _e_reset_log is a record, it cannot be changed or deleted'; end $$;
drop trigger if exists e_reset_log_ro on public._e_reset_log;
create trigger e_reset_log_ro before update or delete on public._e_reset_log for each row execute function public._e_reset_log_ro();
drop trigger if exists e_reset_log_ro_t on public._e_reset_log;
create trigger e_reset_log_ro_t before truncate on public._e_reset_log for each statement execute function public._e_reset_log_ro();

-- ---------- the two lists (functions, so a paste can refresh them) ----------
-- Transactional tables a test reset may clear (only those that exist are used).
create or replace function public._e_reset_tables() returns text[] language sql immutable as $$
  select array[
    'journal_lines', 'journal_entries', 'acct_post_errors72', 'year_closes',
    'stock_ledger', 'stock_balance', 'stock_batches', 'stock_wastage', 'stock_transfers', 'wastage_requests', 'grn_batch_links', 'qc_records', 'production_runs',
    'sales', 'sale_payments', 'sale_returns', 'sale_tier_use', 'sale_form_links',
    'purchase_bills', 'purchase_lines', 'supplier_payments', 'supplier_refunds',
    'cash_moves', 'quick_expenses',
    'payroll_runs', 'payroll_lines', 'payroll_payments', 'payroll_bonus_events', 'employee_advances', 'employee_advance_recoveries',
    'attendance_punches', 'attendance_days',
    'entries', 'entry_change_requests', 'entry_revisions', 'entry_signatures', 'entry_counts', 'entry_count_seals', 'entry_count_peeks', 'entry_ledger_posts',
    'customer_points_ledger', 'online_orders', 'online_order_events', 'online_order_flags', 'order_dup_flags', 'inbound_messages', 'inbound_message_events',
    'bank_statement_lines', 'bank_recon_matches', 'bank_recon_trail', 'fa_depr_posts',
    'partner_capital', 'partner_settlement_lines', 'partner_settlement_payments', 'partner_settlements',
    'release_requests', 'sales_fact_t', 'customer_gifts', 'assets', 'asset_costs',
    'shortage_transit_events', 'shortage_transit', 'shortage_cash_cases', 'd_wallet_fees', 'd_wallet_moves', 'd_wallet_checks', 'c_month_close_log', 'opening_batches', /* bos85: tables of phases 80-83 */
    'shadow_links', 'corrections', 'exceptions', 'payment_intents', 'payment_webhook_log', 'notify_outbox']::text[]
$$;

-- Tables a test reset must NEVER touch (setup, people, rules, audit). Checked before anything runs; a name in both lists stops the reset.
create or replace function public._e_reset_protected() returns text[] language sql immutable as $$
  select array[
    'items', 'item_types', 'item_costs', 'item_class_map', 'item_price_history', 'unit_conversions', 'recipes', 'recipe_lines', 'recipe_versions', 'recipe_steps', 'recipe_cost_components', 'product_packaging',
    'rules', 'rule_grants', 'grant_defs', 'user_grants', 'roles', 'user_roles', 'role_form_perms', 'role_favourites', 'user_favourites', 'staff_roles', 'profiles', 'user_locations',
    'locations', 'location_settings', 'location_setup_steps', 'location_cost_cfg', 'forms', 'form_rollout', 'forms_ledger_cfg',
    'option_lists', 'list_defs', 'list_managers', 'list_other_entries', 'option_requests',
    'coa_accounts', 'acct_mappings', 'settings', 'settings_keys', 'settings_sheets', 'settings_values', 'path_domains', 'path_switch',
    'customers', 'suppliers', 'employees', 'employee_locations', 'employee_pay', 'employee_pay_components', 'sales_channels', 'serials',
    'd_wallets', 'd_material_roles', 'd_item_roles', 'd_product_role_req', 'd_material_fixed_price', 'audit_log', 'backup_runs', 'restore_drills', 'login_attempts', 'login_failures', 'login_throttle', '_e_reset_log']::text[]
$$;

-- ---------- PART 2: guarded test reset ----------
-- Refuses unless: owner, allow_test_reset is ON, phrase exact. All three are checked before any table is touched.
create or replace function public._e_test_reset(p_phrase text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c_phrase constant text := 'DELETE ALL TEST DATA';
  want text[]; t text; n bigint; total bigint := 0; ntab int := 0; clash text[]; outside text; detail jsonb := '{}'::jsonb;
begin
  if not public.is_owner() then raise exception 'test_reset_refused: owner only'; end if;
  if not coalesce(public.rule_on('allow_test_reset'), false) then
    raise exception 'test_reset_refused: allow_test_reset is OFF (this is the default). Turn it on only in a test project.';
  end if;
  if p_phrase is distinct from c_phrase then raise exception 'test_reset_refused: wrong confirmation phrase'; end if;

  -- only tables that exist here
  select coalesce(array_agg(x), '{}') into want from unnest(public._e_reset_tables()) x where to_regclass('public.' || quote_ident(x)) is not null;
  -- a table must never be on both lists
  select array_agg(x) into clash from unnest(want) x where x = any (public._e_reset_protected());
  if clash is not null then raise exception 'test_reset_refused: protected table in the clear list: %', array_to_string(clash, ', '); end if;
  -- TRUNCATE needs every table that points at a cleared table to be cleared too; a setup table that points at one stops the reset
  select string_agg(distinct cl.relname || ' -> ' || pl.relname, ', ') into outside
    from pg_constraint k join pg_class cl on cl.oid = k.conrelid join pg_namespace ns on ns.oid = cl.relnamespace and ns.nspname = 'public'
    join pg_class pl on pl.oid = k.confrelid
   where k.contype = 'f' and pl.relname = any (want) and cl.relname <> all (want);
  if outside is not null then raise exception 'test_reset_refused: tables outside the clear list point at cleared tables: %', outside; end if;

  -- the append-only triggers are switched off for these tables only, inside this transaction, and switched on again
  foreach t in array want loop
    execute format('alter table public.%I disable trigger user', t);
  end loop;
  foreach t in array want loop
    execute format('select count(*) from public.%I', t) into n;
    detail := detail || jsonb_build_object(t, n); total := total + n; ntab := ntab + 1;
  end loop;
  execute 'truncate table ' || (select string_agg(format('public.%I', x), ', ') from unnest(want) x);
  foreach t in array want loop
    execute format('alter table public.%I enable trigger user', t);
  end loop;

  -- one reset per switch: turn the flag off again
  update public.rules set value = 'false'::jsonb, updated_at = now(), updated_by = auth.uid() where key = 'allow_test_reset';
  insert into public._e_reset_log (done_by, database_name, tables_cleared, rows_cleared, detail) values (auth.uid(), current_database(), ntab, total, detail);
  return jsonb_build_object('ok', true, 'tables_cleared', ntab, 'rows_cleared', total, 'flag_now', false, 'detail', detail);
end $$;
revoke all on function public._e_test_reset(text) from public, anon;
grant execute on function public._e_test_reset(text) to authenticated;

-- A harmless question the screen asks: is a reset even possible here? (no secrets, no data)
create or replace function public._e_test_reset_state() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('allowed', public.is_owner() and coalesce(public.rule_on('allow_test_reset'), false), 'owner', public.is_owner(),
    'flag', coalesce(public.rule_on('allow_test_reset'), false), 'last', (select max(done_at) from public._e_reset_log))
$$;
revoke all on function public._e_test_reset_state() from public, anon;
grant execute on function public._e_test_reset_state() to authenticated;

