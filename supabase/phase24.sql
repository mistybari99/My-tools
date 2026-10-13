-- ============================================================
-- PHASE 24 (group C): report engine 3 = a registry of reports (table report_defs3) + one function per report
--   _r3q_<key>(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb   (one jsonb object per row, keys = the column keys; private: nobody may call it directly)
--   report_run3(key, filters, group, sort, page) does access, locations, dates, sort, paging, totals - same answer shape as report_run2, so the reports hub shows them with no new screen.
--   report_catalog2 / report_run2 / log_report_export2 are wrapped: a key that is in report_defs3 goes to engine 3, every other key to the old code (renamed *_core).
-- Needs phase21. Run in order after it (do not paste phase21 again afterwards). Additive and idempotent. Costs only for cost-right holders; owner-only reports stay owner-only.
-- ============================================================
create table if not exists public.report_defs3 (
  key text primary key check (key ~ '^[a-z0-9_]{2,40}$'),
  code text,                                   -- number in docs/plan_v2/REPORTS.md (S10, P2 ...)
  grp text not null,                           -- access group: report_<grp> grant (or view_reports)
  name_bn text not null, name_en text not null, name_mix text,
  cols jsonb not null,                         -- [[key, label_bn, label_en, type]]  type: text | id | date | int | num | money | pct
  tot text[] not null default '{}',            -- column keys summed into the totals
  sort_key text, sort_dir text not null default 'desc',
  allow text[] not null default array['locations'],
  nodate boolean not null default false, cost boolean not null default false, owner_only boolean not null default false,
  sort int not null default 0, is_active boolean not null default true
);
alter table public.report_defs3 enable row level security;
drop policy if exists report_defs3_read on public.report_defs3;
create policy report_defs3_read on public.report_defs3 for select to authenticated using (public.is_active());
revoke all on public.report_defs3 from public, anon, authenticated;
grant select on public.report_defs3 to authenticated;

do $$
declare r record;
begin
  for r in select * from (values
    ('report_profit',    69, 'রিপোর্ট: লাভ-ক্ষতি', 'Report: Profit & loss', 'Reports: Profit and loss'),
    ('report_quality',   70, 'রিপোর্ট: মান ও পরিচ্ছন্নতা', 'Report: Quality & hygiene', 'Reports: Quality and hygiene'),
    ('report_marketing', 71, 'রিপোর্ট: মার্কেটিং', 'Report: Marketing', 'Reports: Marketing'),
    ('report_orders',    72, 'রিপোর্ট: অর্ডার ও ডেলিভারি', 'Report: Orders & delivery', 'Reports: Orders and delivery')) v(code, sort, bn, mix, en)
  loop
    if not exists (select 1 from public.grant_defs where grant_code = r.code) then
      insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values (r.code, 'reports', r.sort, r.bn, r.mix, r.en, 'once', null);
    end if;
  end loop;
end $$;

create or replace function public._r3_ok(d public.report_defs3) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return d.is_active and public.rpt_access(d.grp) and (not d.cost or public.rpt_cost_ok()) and (not d.owner_only or public.is_owner());
end $$;

create or replace function public.report_catalog3() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d public.report_defs3; out_ jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  for d in select * from public.report_defs3 where is_active order by sort, key loop
    out_ := out_ || jsonb_build_array(jsonb_build_object('key', d.key, 'code', d.code, 'group', d.grp, 'grant', 'report_' || d.grp, 'allowed', public._r3_ok(d), 'kind', 'raw', 'engine', 2,
      'name_bn', d.name_bn, 'name_en', d.name_en, 'name_mix', coalesce(d.name_mix, d.name_bn),
      'filters', to_jsonb(case when d.nodate then '{}'::text[] else array['date'] end || d.allow),
      'dims', '[]'::jsonb, 'default_group', null, 'columns', '[]'::jsonb, 'compare', false, 'needs_date', not d.nodate, 'cost_only', d.cost));
  end loop;
  return out_;
end $$;

create or replace function public.report_run3(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null, p_page int default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  d public.report_defs3; flt jsonb; notes jsonb := '[]'::jsonb; today date := (now() at time zone 'Asia/Dhaka')::date; eff int[]; d1 date; d2 date; pr jsonb; preset text;
  pgsize int; pg int := least(greatest(coalesce(p_page, 1), 1), 1000); off int; lim int; cap constant int := 500; c jsonb; outc jsonb := '[]'::jsonb; keys text[] := '{}'; types jsonb := '{}'::jsonb;
  sk text; sd text; sraw text; sparts text[]; ordr text; rows_ jsonb; totals_ jsonb; ng bigint := 0; hm boolean; dn boolean := false; fn text; k text; targs text := ''; g text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into d from public.report_defs3 where key = p_key and is_active;
  if not found then raise exception 'unknown_report'; end if;
  if not public._r3_ok(d) then raise exception 'not allowed'; end if;
  fn := '_r3q_' || d.key;
  flt := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
  for c in select jsonb_array_elements(d.cols) loop
    outc := outc || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3,
      'role', case when c ->> 3 in ('money', 'int', 'num', 'pct') then 'measure' else 'dim' end, 'cost', d.cost));
    keys := keys || (c ->> 0); types := types || jsonb_build_object(c ->> 0, c ->> 3);
  end loop;
  if to_regprocedure('public.' || fn || '(date,date,int[],jsonb)') is null then
    return jsonb_build_object('report', p_key, 'columns', outc, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
      'page', jsonb_build_object('n', pg, 'size', 0, 'groups', 0, 'cap', cap), 'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'text_en', 'This report is not installed yet', 'text_bn', 'এই রিপোর্ট এখনও বসানো হয়নি')));
  end if;
  eff := public._r2_locs(flt);
  if cardinality(eff) = 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_location', 'text_en', 'No location is open to you', 'text_bn', 'কোনো লোকেশন আপনার জন্য খোলা নেই')); end if;
  pgsize := least(greatest(coalesce(public.rule_num('report_page_size'), 50), 10), 200)::int;
  off := (pg - 1) * pgsize; lim := greatest(least(pgsize, cap - off), 0);
  for g in select jsonb_object_keys(flt) loop
    if g in ('from', 'to', 'preset', 'compare_mode') or jsonb_typeof(flt -> g) = 'null' then continue; end if;
    if not (g = any (d.allow)) then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', left(g, 40))); end if;
  end loop;
  if not d.nodate then
    preset := flt ->> 'preset';
    if preset is not null then
      pr := public.report_presets() -> preset;
      if pr is null or jsonb_typeof(pr) = 'null' then
        return jsonb_build_object('report', p_key, 'columns', outc, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
          'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', 0, 'cap', cap), 'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', left(preset, 30), 'text_en', 'Unknown date preset', 'text_bn', 'তারিখের প্রিসেটের নাম ভুল')));
      end if;
      d1 := (pr ->> 'from')::date; d2 := (pr ->> 'to')::date;
    else
      d1 := public.rpt_date(flt ->> 'from'); d2 := public.rpt_date(flt ->> 'to');
      if d1 is null and d2 is null then d1 := date_trunc('month', today)::date; d2 := today;
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'default_period', 'text_en', 'No period given: this month to date', 'text_bn', 'সময় দেওয়া হয়নি: এই মাসের শুরু থেকে আজ পর্যন্ত'));
      elsif d1 is null then d1 := d2; elsif d2 is null then d2 := today; end if;
    end if;
    if d2 < d1 or d2 - d1 > 365 then raise exception 'bad_range'; end if;
  else d1 := today; d2 := today;
  end if;
  sraw := lower(btrim(coalesce(p_sort, '')));
  if sraw <> '' then
    if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
    sparts := regexp_split_to_array(sraw, '[: ]+');
    if sparts[1] = any (keys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
  end if;
  if sk is null then
    if d.sort_key is not null and d.sort_key = any (keys) then sk := d.sort_key; sd := d.sort_dir;
    else sk := coalesce((select c2 ->> 0 from jsonb_array_elements(d.cols) c2 where c2 ->> 3 <> 'id' limit 1), keys[1]); sd := 'asc'; end if;
  end if;
  ordr := case when types ->> sk in ('money', 'int', 'num', 'pct') then format('(r ->> %L)::numeric', sk) else format('r ->> %L', sk) end || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last';
  execute format('select coalesce(jsonb_agg(x.r order by x.rn), ''[]''::jsonb), coalesce(max(x.n), 0) from (select r, count(*) over () as n, row_number() over (order by %s) as rn from public.%I($1, $2, $3, $4) r order by %s limit %s offset %s) x',
    ordr, fn, ordr, lim, off) into rows_, ng using d1, d2, eff, flt;
  if cardinality(d.tot) > 0 then
    foreach k in array d.tot loop targs := targs || format('%L, round(coalesce(sum((r ->> %L)::numeric), 0), 4), ', k, k); end loop;
    execute format('select jsonb_build_object(%s) from public.%I($1, $2, $3, $4) r', left(targs, length(targs) - 2), fn) into totals_ using d1, d2, eff, flt;
  end if;
  hm := (off + pgsize) < least(ng, cap);
  if ng > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ng)); end if;
  if jsonb_array_length(rows_) = 0 or ng = 0 then
    dn := true; notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_data', 'text_en', 'Data needed: nothing matches this period / filters', 'text_bn', 'তথ্য দরকার: এই সময়/ফিল্টারে কিছু নেই'));
  end if;
  return jsonb_build_object('report', p_key, 'columns', outc, 'rows', rows_, 'totals', totals_, 'compare', null,
    'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', ng, 'cap', cap), 'has_more', coalesce(hm, false), 'notes', notes, 'data_needed', dn,
    'meta', jsonb_build_object('from', d1, 'to', d2, 'group', '[]'::jsonb, 'sort', sk, 'dir', sd, 'cost_shown', public.rpt_cost_ok(), 'today', today));
end $$;

-- ---------- wrap the engine-2 entry points (renamed once; a re-run keeps the wrappers) ----------
do $$ begin
  if to_regprocedure('public.report_run2_core(text,jsonb,text,text,int)') is null then alter function public.report_run2(text, jsonb, text, text, int) rename to report_run2_core; end if;
  if to_regprocedure('public.report_catalog2_core()') is null then alter function public.report_catalog2() rename to report_catalog2_core; end if;
end $$;
revoke all on function public.report_run2_core(text, jsonb, text, text, int), public.report_catalog2_core() from public, anon, authenticated;

create or replace function public.report_run2(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null, p_page int default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if exists (select 1 from public.report_defs3 where key = p_key and is_active) then return public.report_run3(p_key, p_filters, p_group, p_sort, p_page); end if;
  return public.report_run2_core(p_key, p_filters, p_group, p_sort, p_page);
end $$;
create or replace function public.report_catalog2() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return public.report_catalog2_core() || public.report_catalog3();
end $$;

create or replace function public.log_report_export2(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or not (p_key = any (public._r2_keys()) or exists (select 1 from public.report_defs3 d where d.key = p_key and d.is_active)) then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- every _r3q_* report function is private (they run as definer and do no access checks of their own): report files end with  select public._r3_lockdown();
create or replace function public._r3_lockdown() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select p.oid::regprocedure::text as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like '\_r3q\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig); n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public._r3_lockdown() from public, anon, authenticated;

revoke all on function public.report_run3(text, jsonb, text, text, int), public.report_catalog3(), public._r3_ok(public.report_defs3), public.report_run2(text, jsonb, text, text, int), public.report_catalog2(), public.log_report_export2(text, text, jsonb, int) from public, anon;
grant execute on function public.report_run3(text, jsonb, text, text, int), public.report_catalog3(), public.report_run2(text, jsonb, text, text, int), public.report_catalog2(), public.log_report_export2(text, text, jsonb, int) to authenticated;
revoke all on function public._r3_ok(public.report_defs3) from authenticated;
notify pgrst, 'reload schema';
