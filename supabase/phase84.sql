-- Phase 84 (bos84) - BALANCE CHECK (G11) and GUARDED TEST-PROJECT RESET (G13).
-- Paste after phase79 (or after whatever is latest). Additive, paste-twice safe: create table if not exists, create or replace function,
-- insert ... on conflict do nothing. No existing function, table or rule is changed.
--
-- PART 1  _e_balance_check(p_date, p_loc, p_days)   READ ONLY. One jsonb answer, one red/green status:
--   equation       assets = liabilities + equity + earnings (acct_balance_sheet), RED when the difference is not 0
--   trial_balance  total debit = total credit (acct_trial_balance), RED when not equal
--   journal        every journal entry where sum Dr <> sum Cr, and entries with no lines (list, max 200), RED when any
--   stock_identity per place and item: opening + in - out must equal stock_balance.qty (list, max 200), RED when any
--   cross_checks   AMBER only (they have known timing reasons and never turn the whole status red):
--                  day book vs journal (daybook_vs_journal), stock valuation vs journal (inventory_vs_gl),
--                  documents not yet posted and posting errors (acct_status)
--   status         red | green | data_needed (accounting start date not set). Amber cross-checks are listed in "warnings".
-- PART 2  _e_test_reset(p_phrase)   FOR A TEST PROJECT ONLY. Refuses unless ALL of: caller is the owner, rule allow_test_reset is ON
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
    'audit_log', 'backup_runs', 'restore_drills', 'login_attempts', 'login_failures', 'login_throttle', '_e_reset_log']::text[]
$$;

-- ---------- PART 1: balance check (read only) ----------
create or replace function public._e_balance_check(p_date date default null, p_loc int default null, p_days int default 31)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  st date := public._acct_start(); d date := coalesce(p_date, public._acct_today()); bs jsonb; tb jsonb; days int := least(greatest(coalesce(p_days, 31), 1), 366);
  eq jsonb; trial jsonb; jr jsonb; stk jsonb; dbk jsonb; invg jsonb; sts jsonb; xc jsonb := '{}'::jsonb; warn jsonb := '[]'::jsonb;
  jr_n bigint; jr_list jsonb; st_n bigint; st_list jsonb; red boolean := false; v_all boolean := public._acct_all();
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_loc is null and not v_all then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if st is null then return jsonb_build_object('status', 'data_needed', 'why', 'accounting_start_date', 'as_of', d, 'location_id', p_loc); end if;

  -- 1 the equation
  bs := public.acct_balance_sheet(d, p_loc);
  eq := jsonb_build_object('assets', bs -> 'total_assets', 'liabilities', bs -> 'total_liabilities', 'equity', bs -> 'total_equity', 'earnings', bs -> 'retained_earnings',
          'liabilities_equity_earnings', bs -> 'total_liabilities_and_equity', 'difference', bs -> 'difference', 'ok', not coalesce((bs ->> 'unbalanced')::boolean, true));
  -- 2 the trial balance
  tb := public.acct_trial_balance(st, d, p_loc);
  trial := jsonb_build_object('total_debit', tb -> 'total_debit', 'total_credit', tb -> 'total_credit', 'difference', tb -> 'diff', 'ok', coalesce((tb ->> 'balanced')::boolean, false));
  -- 3 journal entries where Dr <> Cr (or no lines at all)
  with z as (
    select e.id, e.entry_date, e.source_type, e.source_id, coalesce(sum(l.debit), 0) dr, coalesce(sum(l.credit), 0) cr, count(l.entry_id) n
      from public.journal_entries e left join public.journal_lines l on l.entry_id = e.id
     where e.entry_date <= d and (p_loc is null or exists (select 1 from public.journal_lines x where x.entry_id = e.id and x.location_id = p_loc))
     group by e.id, e.entry_date, e.source_type, e.source_id
    having coalesce(sum(l.debit), 0) <> coalesce(sum(l.credit), 0) or count(l.entry_id) = 0)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('entry_id', id, 'date', entry_date, 'source_type', source_type, 'source_id', source_id, 'debit', dr, 'credit', cr, 'diff', dr - cr, 'lines', n)
         order by id) filter (where rn <= 200), '[]'::jsonb)
    into jr_n, jr_list from (select z.*, row_number() over (order by z.id) rn from z) z;
  jr := jsonb_build_object('broken', jr_n, 'rows', jr_list, 'truncated', jr_n > 200, 'ok', jr_n = 0);
  -- 4 stock identity per place and item: opening + in - out = closing (stock_balance), as of now
  with l as (
    select item_id, location_id,
           coalesce(sum(qty_delta) filter (where reason = 'opening'), 0) op,
           coalesce(sum(qty_delta) filter (where reason <> 'opening' and qty_delta > 0), 0) qin,
           -coalesce(sum(qty_delta) filter (where reason <> 'opening' and qty_delta < 0), 0) qout
      from public.stock_ledger where p_loc is null or location_id = p_loc group by item_id, location_id),
  j as (
    select coalesce(l.item_id, b.item_id) item_id, coalesce(l.location_id, b.location_id) location_id, coalesce(l.op, 0) op, coalesce(l.qin, 0) qin, coalesce(l.qout, 0) qout,
           coalesce(b.qty, 0) closing, coalesce(l.op, 0) + coalesce(l.qin, 0) - coalesce(l.qout, 0) expected
      from l full join (select * from public.stock_balance where p_loc is null or location_id = p_loc) b on b.item_id = l.item_id and b.location_id = l.location_id),
  br as (select j.*, row_number() over (order by j.location_id, j.item_id) rn from j where j.expected <> j.closing)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('item_id', item_id, 'location_id', location_id, 'opening', op, 'in', qin, 'out', qout, 'expected_closing', expected,
         'stock_balance', closing, 'diff', closing - expected) order by rn) filter (where rn <= 200), '[]'::jsonb)
    into st_n, st_list from br;
  stk := jsonb_build_object('broken', st_n, 'rows', st_list, 'truncated', st_n > 200, 'ok', st_n = 0, 'as_of', 'now');

  -- 5 cross-checks (amber). Each is skipped, not failed, when the caller may not run the report.
  begin
    dbk := public.daybook_vs_journal(greatest(d - days, st), d, p_loc);
    xc := xc || jsonb_build_object('daybook_vs_journal', jsonb_build_object('ran', coalesce(dbk -> 'total' is not null, false), 'kinds_differing', dbk #> '{total,kinds_differing}',
            'diff', dbk #> '{total,diff}', 'rows', coalesce(dbk -> 'rows', '[]'::jsonb), 'from', dbk -> 'from', 'to', dbk -> 'to', 'ok', coalesce((dbk #>> '{total,kinds_differing}')::int, 0) = 0));
    if coalesce((dbk #>> '{total,kinds_differing}')::int, 0) > 0 then warn := warn || to_jsonb('daybook_vs_journal'::text); end if;
  exception when others then xc := xc || jsonb_build_object('daybook_vs_journal', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  begin
    invg := public.inventory_vs_gl(d, p_loc);
    xc := xc || jsonb_build_object('inventory_vs_gl', jsonb_build_object('ran', coalesce(invg -> 'total' is not null, false), 'gl', invg #> '{total,gl}', 'valuation', invg #> '{total,valuation}',
            'diff', invg #> '{total,diff}', 'unexplained', invg #> '{total,unexplained}', 'ok', coalesce((invg ->> 'agree')::boolean, true)));
    if not coalesce((invg ->> 'agree')::boolean, true) then warn := warn || to_jsonb('inventory_vs_gl'::text); end if;
  exception when others then xc := xc || jsonb_build_object('inventory_vs_gl', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  begin
    sts := public.acct_status();
    xc := xc || jsonb_build_object('unposted_sources', jsonb_build_object('ran', true, 'pending', sts -> 'pending', 'errors', sts -> 'errors', 'waiting', sts -> 'waiting',
            'ok', coalesce((sts ->> 'pending')::int, 0) = 0 and coalesce((sts ->> 'errors')::int, 0) = 0));
    if coalesce((sts ->> 'pending')::int, 0) > 0 or coalesce((sts ->> 'errors')::int, 0) > 0 then warn := warn || to_jsonb('unposted_sources'::text); end if;
  exception when others then xc := xc || jsonb_build_object('unposted_sources', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;

  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0;
  return jsonb_build_object('status', case when red then 'red' else 'green' end, 'as_of', d, 'location_id', p_loc, 'start', st,
    'equation', eq, 'trial_balance', trial, 'journal', jr, 'stock_identity', stk, 'cross_checks', xc, 'warnings', warn,
    'reds', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (values ('equation', not (eq ->> 'ok')::boolean), ('trial_balance', not (trial ->> 'ok')::boolean),
                ('journal', jr_n > 0), ('stock_identity', st_n > 0)) v(k, bad) where bad),
    'note', 'Read only: nothing is posted or changed. Red = a book rule is broken. Amber (warnings) = two reports disagree and need a look (timing or an unposted document is the usual reason); amber never turns the status red. Stock identity is checked as of now.');
end $$;
revoke all on function public._e_balance_check(date, int, int) from public, anon;
grant execute on function public._e_balance_check(date, int, int) to authenticated;

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
