-- ============================================================
-- BOS tool - Phase 316 (CRM package F, label 116): LOYALTY EXTRAS part 1 - shared helpers, points expiry, burn rules, manual adjustment alert.
-- Needs phase43 (customers, tiers, points ledger) and phase40 (books, only used by phase318). Paste after phase98/99. Paste twice is safe.
--
-- OWNER RULES KEPT (every item below is a SETTING, default = today's behaviour, nothing starts by itself):
--   * Nothing here writes a journal entry, a sale, a sale payment or a stock row. No existing function or file is edited or re-created.
--   * Points expiry: the month count AND the effective-from date are blank = points never expire (today). Nothing expires on its own: the owner
--     runs "Preview" (writes nothing) and then "Apply" (writes 'expire' rows once). Points earned before the effective-from date are treated as
--     earned ON that date, so switching expiry on never wipes old points the same day.
--   * Burn rules (cap as a percent of the bill, cap in points, step): all blank = the existing customer_points_redeem behaves as before.
--     The new wrapper crmf_points_redeem applies the rules and then calls the existing function; a rule can be passed with a reason
--     (owner or grant crm_loyalty_manage) which writes an audit line and a yellow Exceptions row.
--   * Manual adjustment: the existing customer_points_adjust already needs a reason. The wrapper crmf_points_adjust adds a yellow Exceptions row
--     when the size is above the alert setting (blank = no alert).
--
-- SETTINGS (rules, module crm; labels in English; the Switchboard / settings hub list them by themselves):
--   crm_points_expiry_months (blank)  crm_points_expiry_from (blank)  crm_points_expiry_warn_days (blank)
--   crm_burn_max_percent (blank)  crm_burn_max_points (blank)  crm_burn_step_points (blank)  crm_points_adjust_alert_over (blank)
-- GRANT: crm_loyalty_manage (apply expiry, rule override, referral decisions). The owner always may. `customer_manage` keeps its meaning (tier, credit limit, gifts, points).
-- EXPIRY RULE (no first-in-first-out tracking). The rule on screen is: points earned on or before the cut date, minus every point spent or expired since (oldest points are
--   assumed spent first, which is the kinder reading), never more than the balance. A second Apply the same day finds nothing.
-- Hooks for the POS (points burn at the till) are in docs/integration/CRM-F.md.
-- ============================================================

do $g$ begin
  if to_regclass('public.customer_points_ledger') is null or to_regprocedure('public._cust_mgr43()') is null or to_regprocedure('public.customer_points_redeem(uuid,int,text,uuid,boolean)') is null then
    raise exception 'phase316 needs phase43 first (customers, tiers, points ledger)';
  end if;
end $g$;

create or replace function public._crmf_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- 1. helpers (closed to the browser) ----------
create or replace function public._crmf_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
-- who manages loyalty extras: the owner, a holder of customer_manage (existing meaning), or a holder of crm_loyalty_manage
create or replace function public._crmf_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('customer_manage') or public.has_grant('crm_loyalty_manage'));
$$;
-- who may APPLY / OVERRIDE (stronger): the owner or the crm_loyalty_manage grant. customer_manage alone may preview, not apply.
create or replace function public._crmf_apply_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_loyalty_manage'));
$$;
create or replace function public._crmf_pos() returns boolean language sql stable security definer set search_path = public as $$
  select public._cust_pos43() or public._crmf_mgr();
$$;
create or replace function public._crmf_staff() returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = auth.uid();
$$;
create or replace function public._crmf_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void
language sql security definer set search_path = public as $$
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
  values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_id, p_detail) $$;
-- a yellow line in the Exceptions list (same table POS uses) for something done with a reason outside the normal rule
create or replace function public._crmf_exception(p_flag text, p_loc int, p_date date, p_amount numeric, p_text text, p_sale uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare lc int := coalesce(p_loc, (select min(ul.location_id) from public.user_locations ul where ul.user_id = auth.uid()), (select min(id) from public.locations));
begin
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
  values (null, p_sale, 'POS', lc, coalesce(p_date, public._crmf_today()), p_flag, 'yellow', p_amount, jsonb_build_object('bn', left(p_text, 300), 'en', left(p_text, 300)));
end $$;
create or replace function public._crmf_mask(p_mobile text) returns text language sql immutable as $$
  select case when p_mobile is null then null when length(p_mobile) <= 5 then '****' else left(p_mobile, 3) || '****' || right(p_mobile, 2) end $$;
-- a stable uuid made from text, used as the client id of rows this package writes (so a rerun can never write the same row twice)
create or replace function public._crmf_uuid(p_text text) returns uuid language sql immutable as $$ select md5(p_text)::uuid $$;
create or replace function public._crmf_reason(p_text text) returns text language plpgsql immutable as $$
declare v text := left(btrim(coalesce(p_text, '')), 300);
begin if length(v) < 3 then raise exception 'reason_required'; end if; return v; end $$;

-- ---------- 2. the points ledger learns two more reasons (additive; the table stays append-only) ----------
do $c$
declare con text; def text; vals text[]; want text[] := array['sale', 'redeem', 'adjust', 'expire', 'referral', 'bonus'];
begin
  select c.conname, pg_get_constraintdef(c.oid) into con, def from pg_constraint c
   where c.conrelid = 'public.customer_points_ledger'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%reason%';
  if con is null then raise exception 'phase316: the reason check of customer_points_ledger was not found'; end if;
  select array_agg(distinct m[1]) into vals from regexp_matches(def, '''([a-z_]+)''', 'g') m;
  if vals is null or not (vals @> array['sale', 'redeem', 'adjust', 'expire']) then raise exception 'phase316: the reason check has an unknown shape: %', left(def, 150); end if;
  if vals @> want then return; end if;
  want := (select array_agg(distinct x order by x) from unnest(vals || want) x);
  execute format('alter table public.customer_points_ledger drop constraint %I', con);
  execute format('alter table public.customer_points_ledger add constraint %I check (reason = any (array[%s]))', con, (select string_agg(quote_literal(x), ', ' order by x) from unnest(want) x));
end $c$;

-- ---------- 3. grant ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_loyalty_manage', 'master', 72, 'Apply points expiry, referral decisions and loyalty rule overrides', 'Apply points expiry, referral decisions and loyalty rule overrides',
       'Apply points expiry, referral decisions and loyalty rule overrides', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_loyalty_manage');

-- ---------- 4. settings (all blank / OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'crm', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('crm_points_expiry_months', 'number', null::jsonb, 'months', 1::numeric, 120::numeric, 'Points expire after this many months',
   'Blank = points never expire (today). When set, points earned more than this many months ago (and not yet spent) can be expired by the owner after a preview. Needs the effective-from date as well.', 9610),
 ('crm_points_expiry_from', 'text', null, 'YYYY-MM-DD', null, null, 'Points expiry counts from this date',
   'Blank = expiry cannot be applied. Points earned before this date are treated as earned on this date, so old points are never wiped on the day expiry is switched on.', 9611),
 ('crm_points_expiry_warn_days', 'number', null, 'days', 1, 365, 'Warn customers this many days before points expire',
   'Blank = no warning list. The list shows who would lose points in this many days. Sending a message belongs to the campaign screens.', 9612),
 ('crm_burn_max_percent', 'number', null, '%', 1, 100, 'Points can pay at most this percent of a bill',
   'Blank = no limit (today). Used by the points-at-the-till check; the existing redeem function itself is unchanged.', 9613),
 ('crm_burn_max_points', 'number', null, 'pts', 1, 10000000, 'Most points that can be used on one bill',
   'Blank = no limit (today).', 9614),
 ('crm_burn_step_points', 'number', null, 'pts', 1, 100000, 'Points must be used in steps of',
   'Blank = any number of points (today). Example: 50 means 50, 100, 150 and so on.', 9615),
 ('crm_points_adjust_alert_over', 'number', null, 'pts', 1, 10000000, 'Tell the owner when a manual points change is larger than',
   'Blank = no alert. A change above this size still needs a reason and then also shows in the Exceptions list.', 9616)
 ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- text settings are checked when they are written, so a bad date or account can never sit in a setting waiting to fail later;
-- the voucher liability switch also needs its date, both accounts and accounting before it can go ON
create or replace function public._crmf_rules_guard() returns trigger language plpgsql set search_path = public as $$
declare v text; d date; a public.coa_accounts; was boolean; now_ boolean;
begin
  if new.key in ('crm_points_expiry_from', 'crm_voucher_liability_from') then
    v := nullif(btrim(coalesce(new.value, new.default_value) #>> '{}'), '');
    if v is not null then
      if v !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_value'; end if;
      begin d := v::date; exception when others then raise exception 'bad_value'; end;
      if d < date '2000-01-01' or d > date '2100-01-01' then raise exception 'bad_value'; end if;
    end if;
  end if;
  if new.key in ('crm_voucher_liability_account', 'crm_voucher_expense_account') then
    v := nullif(btrim(coalesce(new.value, new.default_value) #>> '{}'), '');
    if v is not null then
      select * into a from public.coa_accounts where code = v;
      if not found or a.is_group or not a.active then raise exception 'bad_account'; end if;
      if new.key = 'crm_voucher_liability_account' and a.type <> 'liability' then raise exception 'bad_account_type'; end if;
      if new.key = 'crm_voucher_expense_account' and a.type <> 'expense' then raise exception 'bad_account_type'; end if;
    end if;
  end if;
  if new.key = 'crm_voucher_liability_on' then
    now_ := coalesce((coalesce(new.value, new.default_value) #>> '{}')::boolean, false);
    was := case when tg_op = 'UPDATE' then coalesce((coalesce(old.value, old.default_value) #>> '{}')::boolean, false) else false end;
    if now_ and not was then
      v := public.rule_txt('crm_voucher_liability_from');
      if v is null then raise exception 'liability_from_needed'; end if;
      if v::date < (now() at time zone 'Asia/Dhaka')::date then raise exception 'liability_from_in_the_past'; end if;
      if public.rule_txt('crm_voucher_liability_account') is null or public.rule_txt('crm_voucher_expense_account') is null then raise exception 'liability_accounts_needed'; end if;
      if not public.rule_on('accounting_on') or public._acct_start() is null then raise exception 'accounting_not_on'; end if;
    end if;
  end if;
  return new;
end $$;

revoke all on function public._crmf_rules_guard() from public, anon, authenticated;
drop trigger if exists crmf_rules_guard on public.rules;
create trigger crmf_rules_guard before insert or update on public.rules for each row when (new.key like 'crm\_%') execute function public._crmf_rules_guard();

-- ---------- 5. expiry runs (append-only records) ----------
create table if not exists public.crmf_expiry_runs (
  id bigint generated by default as identity primary key,
  as_of date not null,
  cut_date date not null,
  months int not null,
  from_date date not null,
  client_id uuid unique,
  note text check (note is null or length(note) <= 300),
  by_user uuid, by_staff text,
  at timestamptz not null default now()
);
create table if not exists public.crmf_expiry_lines (
  run_id bigint not null references public.crmf_expiry_runs(id),
  customer_id uuid not null references public.customers(id),
  points int not null check (points > 0),
  ledger_id bigint references public.customer_points_ledger(id),
  primary key (run_id, customer_id)
);
drop trigger if exists crmf_expiry_runs_ro on public.crmf_expiry_runs;
create trigger crmf_expiry_runs_ro before update or delete on public.crmf_expiry_runs for each row execute function public._append_only43();
drop trigger if exists crmf_expiry_runs_ro_t on public.crmf_expiry_runs;
create trigger crmf_expiry_runs_ro_t before truncate on public.crmf_expiry_runs for each statement execute function public._append_only43();
drop trigger if exists crmf_expiry_lines_ro on public.crmf_expiry_lines;
create trigger crmf_expiry_lines_ro before update or delete on public.crmf_expiry_lines for each row execute function public._append_only43();
drop trigger if exists crmf_expiry_lines_ro_t on public.crmf_expiry_lines;
create trigger crmf_expiry_lines_ro_t before truncate on public.crmf_expiry_lines for each statement execute function public._append_only43();
alter table public.crmf_expiry_runs enable row level security;
alter table public.crmf_expiry_lines enable row level security;
drop policy if exists crmf_expiry_runs_read on public.crmf_expiry_runs;
create policy crmf_expiry_runs_read on public.crmf_expiry_runs for select to authenticated using (public._crmf_mgr());
drop policy if exists crmf_expiry_lines_read on public.crmf_expiry_lines;
create policy crmf_expiry_lines_read on public.crmf_expiry_lines for select to authenticated using (public._crmf_mgr());
revoke all on public.crmf_expiry_runs, public.crmf_expiry_lines from public, anon, authenticated;
grant select on public.crmf_expiry_runs, public.crmf_expiry_lines to authenticated;

-- ---------- 6. expiry: the one rule, in one place ----------
-- per customer: balance, earned (credits dated on or before the cut, where an earlier date counts as the effective-from date), used (every debit ever), expirable
create or replace function public._crmf_expiry_rows(p_cut date, p_from date, p_customer uuid default null)
returns table (customer_id uuid, balance int, earned int, used int, expirable int)
language sql stable security definer set search_path = public as $$
  select z.customer_id, z.bal, z.earned, z.used, least(z.bal, greatest(0, z.earned - z.used))
  from (select l.customer_id,
               sum(l.delta)::int as bal,
               coalesce(sum(l.delta) filter (where l.delta > 0 and greatest((l.at at time zone 'Asia/Dhaka')::date, p_from) <= p_cut), 0)::int as earned,
               (-coalesce(sum(l.delta) filter (where l.delta < 0), 0))::int as used
          from public.customer_points_ledger l
         where p_customer is null or l.customer_id = p_customer
         group by l.customer_id) z
  where z.bal > 0 and least(z.bal, greatest(0, z.earned - z.used)) > 0;
$$;

create or replace function public._crmf_expiry_cfg(p_as_of date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m numeric := public.rule_num('crm_points_expiry_months'); f text := public.rule_txt('crm_points_expiry_from'); a date := coalesce(p_as_of, public._crmf_today());
begin
  if m is null then return jsonb_build_object('off', true, 'reason', 'months_blank'); end if;
  if f is null then return jsonb_build_object('off', true, 'reason', 'from_blank'); end if;
  return jsonb_build_object('off', false, 'months', m::int, 'from', f::date, 'as_of', a, 'cut', (a - make_interval(months => m::int))::date);
end $$;

create or replace function public.crmf_points_expiry_preview(p_as_of date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cfg jsonb; pv numeric := coalesce(public.rule_num('point_value_taka'), 0); n int; pts bigint; smp jsonb;
begin
  if not public._crmf_mgr() then raise exception 'not allowed'; end if;
  if p_as_of is not null and (p_as_of > public._crmf_today() + 366 or p_as_of < date '2000-01-01') then raise exception 'bad_date'; end if;
  cfg := public._crmf_expiry_cfg(p_as_of);
  if (cfg->>'off')::boolean then return cfg || jsonb_build_object('customers', 0, 'points', 0, 'sample', '[]'::jsonb); end if;
  select count(*)::int, coalesce(sum(expirable), 0) into n, pts from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date);
  select coalesce(jsonb_agg(jsonb_build_object('customer_id', r.customer_id, 'name', c.name, 'points', r.expirable, 'balance', r.balance) order by r.expirable desc), '[]'::jsonb) into smp
    from (select * from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date) order by expirable desc limit 100) r join public.customers c on c.id = r.customer_id;
  return cfg || jsonb_build_object('customers', n, 'points', pts, 'value_taka', round(pts * pv, 2), 'sample', smp,
    'rule', 'Points earned on or before the cut date, minus every point spent or expired since, never more than the balance.');
end $$;

-- who would lose points in the next N days (N = the warn setting unless given); the names only, the phone is masked
create or replace function public.crmf_points_expiry_soon(p_days int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cfg jsonb; d int := coalesce(p_days, public.rule_num('crm_points_expiry_warn_days')::int); cfg2 jsonb; rows_ jsonb; n int;
begin
  if not public._crmf_mgr() then raise exception 'not allowed'; end if;
  if d is null then return jsonb_build_object('off', true, 'reason', 'warn_days_blank', 'rows', '[]'::jsonb); end if;
  if d < 1 or d > 365 then raise exception 'bad_number'; end if;
  cfg := public._crmf_expiry_cfg(null);
  if (cfg->>'off')::boolean then return cfg || jsonb_build_object('rows', '[]'::jsonb); end if;
  cfg2 := public._crmf_expiry_cfg(public._crmf_today() + d);
  with later as (select * from public._crmf_expiry_rows((cfg2->>'cut')::date, (cfg->>'from')::date)),
       now_ as (select * from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date)),
       x as (select l.customer_id, l.expirable - coalesce(n.expirable, 0) as soon from later l left join now_ n on n.customer_id = l.customer_id)
  select count(*)::int, coalesce(jsonb_agg(jsonb_build_object('customer_id', x.customer_id, 'name', c.name, 'mobile', public._crmf_mask(c.mobile), 'points', x.soon) order by x.soon desc), '[]'::jsonb)
    into n, rows_ from (select * from x where soon > 0 order by soon desc limit 200) x join public.customers c on c.id = x.customer_id;
  return jsonb_build_object('off', false, 'days', d, 'until', public._crmf_today() + d, 'customers', n, 'rows', rows_);
end $$;

create or replace function public.crmf_points_expiry_apply(p_client uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cfg jsonb; r record; cur record; run_id bigint; led bigint; tot int := 0; cnt int := 0; take int; note_ text := left(nullif(btrim(p_note), ''), 300); more_ boolean;
begin
  if not public._crmf_apply_ok() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select id into run_id from public.crmf_expiry_runs where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'run_id', run_id); end if;
  end if;
  cfg := public._crmf_expiry_cfg(null);
  if (cfg->>'off')::boolean then raise exception 'expiry_not_set: %', cfg->>'reason'; end if;
  perform pg_advisory_xact_lock(hashtextextended('crmf_expiry', 0));
  if not exists (select 1 from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date)) then
    return jsonb_build_object('dup', false, 'run_id', null, 'customers', 0, 'points', 0, 'more', false);        -- nothing to expire: no record is written
  end if;
  insert into public.crmf_expiry_runs (as_of, cut_date, months, from_date, client_id, note, by_user, by_staff)
    values ((cfg->>'as_of')::date, (cfg->>'cut')::date, (cfg->>'months')::int, (cfg->>'from')::date, p_client, note_, auth.uid(), public._crmf_staff()) returning id into run_id;
  for r in select * from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date) order by customer_id limit 5000 loop
    perform 1 from public.customers where id = r.customer_id for update;
    select * into cur from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date, r.customer_id);   -- again, under the lock
    if not found then continue; end if;
    take := least(cur.expirable, cur.balance);
    if take <= 0 then continue; end if;
    led := null;
    insert into public.customer_points_ledger (customer_id, delta, reason, client_id, note, by_user, by_staff)
      values (r.customer_id, -take, 'expire', public._crmf_uuid('crmf_expire:' || run_id || ':' || r.customer_id), 'expiry run ' || run_id || ' (earned on or before ' || (cfg->>'cut') || ')', auth.uid(), public._crmf_staff())
      on conflict do nothing returning id into led;
    if led is null then continue; end if;
    insert into public.crmf_expiry_lines (run_id, customer_id, points, ledger_id) values (run_id, r.customer_id, take, led);
    tot := tot + take; cnt := cnt + 1;
  end loop;
  more_ := exists (select 1 from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date));
  perform public._crmf_audit('crmf_expiry_apply', 'crmf_expiry_runs', run_id::text, jsonb_build_object('customers', cnt, 'points', tot, 'cut', cfg->>'cut', 'months', cfg->'months', 'from', cfg->>'from', 'note', note_));
  return jsonb_build_object('dup', false, 'run_id', run_id, 'customers', cnt, 'points', tot, 'more', more_);
end $$;

create or replace function public.crmf_points_expiry_runs(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmf_mgr() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select r.id, r.as_of, r.cut_date, r.months, r.from_date, r.note, r.at, r.by_staff, count(l.customer_id)::int as customers, coalesce(sum(l.points), 0)::int as points
      from public.crmf_expiry_runs r left join public.crmf_expiry_lines l on l.run_id = r.id group by r.id order by r.id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) z), '[]'::jsonb);
end $$;

-- ---------- 7. burn rules at the till ----------
-- Works out what the settings allow for this customer and bill. Writes nothing. p_bill = the bill total BEFORE points (needed when a percent cap is set).
create or replace function public._crmf_burn_eval(p_customer uuid, p_points int, p_bill numeric) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare bal int; pv numeric := coalesce(public.rule_num('point_value_taka'), 0); pct numeric := public.rule_num('crm_burn_max_percent'); mx numeric := public.rule_num('crm_burn_max_points');
        stp numeric := public.rule_num('crm_burn_step_points'); cap numeric; reasons text[] := '{}';
begin
  select coalesce(sum(delta), 0)::int into bal from public.customer_points_ledger where customer_id = p_customer;
  cap := bal;
  if mx is not null then cap := least(cap, mx); end if;
  if pct is not null then
    if p_bill is null then return jsonb_build_object('ok', false, 'reason', 'bill_total_needed', 'balance', bal); end if;
    if pv > 0 then cap := least(cap, floor(p_bill * pct / 100 / pv)); end if;
  end if;
  if stp is not null and stp > 0 then cap := floor(cap / stp) * stp; end if;
  if p_points is not null then
    if mx is not null and p_points > mx then reasons := reasons || 'over_max_points'::text; end if;
    if pct is not null and pv > 0 and p_points * pv > p_bill * pct / 100 then reasons := reasons || 'over_max_percent'::text; end if;
    if stp is not null and stp > 0 and (p_points % stp::int) <> 0 then reasons := reasons || 'not_in_steps'::text; end if;
  end if;
  return jsonb_build_object('ok', coalesce(array_length(reasons, 1), 0) = 0, 'reason', case when array_length(reasons, 1) > 0 then reasons[1] end, 'reasons', to_jsonb(reasons),
    'balance', bal, 'max_points', greatest(cap, 0)::int, 'max_value_taka', round(greatest(cap, 0) * pv, 2));
end $$;

create or replace function public.crmf_burn_check(p_customer uuid, p_points int default null, p_bill numeric default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmf_pos() then raise exception 'not allowed'; end if;
  if p_points is not null and (p_points <= 0 or p_points > 10000000) then raise exception 'bad_number'; end if;
  if p_bill is not null and (p_bill < 0 or p_bill = 'NaN'::numeric or p_bill > 1000000000000) then raise exception 'bad_number'; end if;
  return public._crmf_burn_eval(p_customer, p_points, p_bill);
end $$;

-- The till calls this instead of customer_points_redeem. All burn settings blank = the same answer the old function gives.
-- p_override: owner or crm_loyalty_manage may go past a burn rule with a reason (audit line + yellow Exceptions row). The balance and the
-- minimum-points rule of the old function are never overridden.
create or replace function public.crmf_points_redeem(p_customer uuid, p_points int, p_bill numeric default null, p_note text default null, p_client uuid default null,
  p_dry boolean default false, p_override text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ev jsonb; res jsonb; ov text := nullif(btrim(p_override), '');
begin
  if not (public._cust_mgr43() or (public.is_active() and public.can_do('POS', 'enter')) or public._crmf_apply_ok()) then raise exception 'not allowed'; end if;
  if p_points is null or p_points <= 0 or p_points > 10000000 then raise exception 'bad_number'; end if;
  if p_bill is not null and (p_bill < 0 or p_bill = 'NaN'::numeric or p_bill > 1000000000000) then raise exception 'bad_number'; end if;
  ev := public._crmf_burn_eval(p_customer, p_points, p_bill);
  if not (ev->>'ok')::boolean then
    if ev->>'reason' = 'bill_total_needed' then raise exception 'bill_total_needed'; end if;
    if ov is null then raise exception 'burn_rule: %', ev->>'reason'; end if;
    if not public._crmf_apply_ok() then raise exception 'not allowed'; end if;
    ov := public._crmf_reason(ov);
    if not coalesce(p_dry, false) and not (p_client is not null and exists (select 1 from public.customer_points_ledger where client_id = p_client)) then    -- a replay of the same client id writes no second line
      perform public._crmf_audit('crmf_burn_override', 'customer_points_ledger', p_customer::text, jsonb_build_object('points', p_points, 'bill', p_bill, 'rules', ev->'reasons', 'reason', ov));
      perform public._crmf_exception('loyalty_burn_override', null, null, p_points, 'Points used past a burn rule (' || (ev->>'reason') || '): ' || ov);
    end if;
  end if;
  res := public.customer_points_redeem(p_customer, p_points, p_note, p_client, p_dry);
  return res || jsonb_build_object('burn', ev);
end $$;

-- ---------- 8. manual adjustment: the existing function already needs a reason; this adds the owner alert for a large one ----------
create or replace function public.crmf_points_adjust(p_customer uuid, p_delta int, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb; lim numeric := public.rule_num('crm_points_adjust_alert_over');
begin
  res := public.customer_points_adjust(p_customer, p_delta, p_note, p_client);              -- permission, reason, balance floor (never below zero) and idempotency stay in the old function
  if lim is not null and abs(p_delta) > lim and not coalesce((res->>'dup')::boolean, false) then
    perform public._crmf_exception('loyalty_adjust_large', null, null, abs(p_delta), 'Manual points change of ' || p_delta || ': ' || left(btrim(p_note), 200));
  end if;
  return res;
end $$;

-- ---------- 9. privileges: signed-in users only, helpers closed ----------
revoke all on function public._crmf_present(), public._crmf_today(), public._crmf_mgr(), public._crmf_apply_ok(), public._crmf_pos(), public._crmf_staff(),
  public._crmf_audit(text, text, text, jsonb), public._crmf_exception(text, int, date, numeric, text, uuid), public._crmf_mask(text), public._crmf_uuid(text), public._crmf_reason(text),
  public._crmf_expiry_rows(date, date, uuid), public._crmf_expiry_cfg(date), public._crmf_burn_eval(uuid, int, numeric) from public, anon, authenticated;
-- the table policies call _crmf_mgr(), so signed-in users must be able to execute it (it only answers true / false)
grant execute on function public._crmf_mgr() to authenticated;
revoke all on function public.crmf_points_expiry_preview(date), public.crmf_points_expiry_soon(int), public.crmf_points_expiry_apply(uuid, text), public.crmf_points_expiry_runs(int),
  public.crmf_burn_check(uuid, int, numeric), public.crmf_points_redeem(uuid, int, numeric, text, uuid, boolean, text), public.crmf_points_adjust(uuid, int, text, uuid) from public, anon;
grant execute on function public.crmf_points_expiry_preview(date), public.crmf_points_expiry_soon(int), public.crmf_points_expiry_apply(uuid, text), public.crmf_points_expiry_runs(int),
  public.crmf_burn_check(uuid, int, numeric), public.crmf_points_redeem(uuid, int, numeric, text, uuid, boolean, text), public.crmf_points_adjust(uuid, int, text, uuid) to authenticated;

