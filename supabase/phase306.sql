-- Phase 306 (package CRM-C, label 106) - CUSTOMER SCORES: one row of numbers per customer, RFM labels with the owner's own cut-offs, settings, rights.
-- Paste AFTER phase98 (it needs the customer module of phase 43, sale returns of phase 12 and the notify tables of phase 62). Paste-twice safe.
-- No earlier phase file is edited and no shared function is re-created: everything here is new, every function starts _crmc_ / crmc_, every table starts crm_.
-- Nothing starts by itself: scores are worked out only when someone presses "Refresh scores" or when the owner switches the schedule ON (and sets the hours).
-- All new settings default to OFF or blank, so with the defaults the books, reports and screens behave exactly as before (proved by tests/sql/crmc_before_after.sh).
--
-- WHAT THIS FILE ADDS
--   1. Settings (rules, module crm): crm_segments_on (OFF), crm_rfm_recent_days / crm_rfm_frequency_min / crm_rfm_spend_min (blank), crm_winback_days (blank),
--      crm_metrics_batch (2000, a technical batch size), crm_metrics_schedule_on (OFF), crm_metrics_schedule_hours (blank), crm_segment_max_members (5000, technical),
--      crm_seg_export_on (OFF), crm_seg_export_max_rows (blank). Grants: crm_view, crm_contact_view, crm_export, crm_settings_edit (nobody holds them until the owner gives them).
--   2. crm_metrics: one row per active customer (last visit, orders, spend net of returns, due, points, outlets, top three items). A cache the owner can rebuild at any time.
--      Money figures are COPIED from sales / returns, never changed. r/f/m flags and the label are NOT stored: they are worked out when read (see _crmc_scored), so a changed
--      cut-off applies at once without a rebuild.
--   3. crmc_metrics_refresh(dry): on demand, capped per run (crm_metrics_batch), oldest first; crmc_metrics_status(); crmc_scheduled_run() for the notify job (OFF by default).
--   4. crmc_me(): what the caller may do (the screens only ask; the server decides every call).
--   5. _crmc_patch(): the exact-text patch helper used for the one optional hook in notify_scan (docs/integration/CRM-C.md), marker bosCRMC.
-- Privacy: the cache is closed to browsers (no table right, no policy). Lists show a mobile number masked unless the privacy guard of package B is OFF (or absent) or the caller
-- holds crm_contact_view. Package B is read through rules with a safe fallback: if B is not installed the guard counts as OFF (today's behaviour) and no DNC table is consulted.

do $g$ begin
  if to_regprocedure('public._cust_stats43(uuid,boolean)') is null or to_regprocedure('public._cust_mgr43()') is null then raise exception 'phase306 needs phase43 (customers) first'; end if;
  if to_regclass('public.sale_returns') is null or to_regclass('public.customer_points_ledger') is null or to_regclass('public.notify_optin') is null then
    raise exception 'phase306 needs phases 12, 43 and 62 first'; end if;
  if to_regprocedure('public._is_ops(text)') is null or to_regprocedure('public.has_grant(text,integer)') is null then raise exception 'phase306 needs phases 8 and 46 first'; end if;
end $g$;

create or replace function public._crmc_present() returns boolean language sql stable as $$ select true $$;

-- ============================================================================
-- 1. SETTINGS (rules). English text everywhere (owner rule). Changes are logged by the existing audit_rules trigger.
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('crm_segments_on', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Customer lists: allow saving and freezing lists', 'Customer lists: allow saving and freezing lists', 'Customer lists: allow saving and freezing lists',
  'OFF = you can look at a list and see how many customers it holds, but you cannot save or freeze one (today). ON = people with the right can save lists. Nothing is sent to anyone either way.',
  'OFF = you can look at a list and see how many customers it holds, but you cannot save or freeze one (today). ON = people with the right can save lists. Nothing is sent to anyone either way.',
  'OFF = you can look at a list and see how many customers it holds, but you cannot save or freeze one (today). ON = people with the right can save lists. Nothing is sent to anyone either way.', 3060),
 ('crm_rfm_recent_days', 'crm', 'number', null, 'days', null, 1, 3650,
  'Customer score: a customer counts as recent if they bought within this many days', 'Customer score: a customer counts as recent if they bought within this many days', 'Customer score: a customer counts as recent if they bought within this many days',
  'Blank = the standard labels are used (the same cut-offs as the existing Customer value report). Set all three score numbers to use your own cut-offs.',
  'Blank = the standard labels are used (the same cut-offs as the existing Customer value report). Set all three score numbers to use your own cut-offs.',
  'Blank = the standard labels are used (the same cut-offs as the existing Customer value report). Set all three score numbers to use your own cut-offs.', 3061),
 ('crm_rfm_frequency_min', 'crm', 'number', null, 'orders', null, 1, 1000,
  'Customer score: a customer counts as frequent with at least this many orders in 12 months', 'Customer score: a customer counts as frequent with at least this many orders in 12 months', 'Customer score: a customer counts as frequent with at least this many orders in 12 months',
  'Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.', 'Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.', 'Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.', 3062),
 ('crm_rfm_spend_min', 'crm', 'number', null, '৳', null, 1, 1000000000,
  'Customer score: a customer counts as a big spender with at least this much spent in 12 months', 'Customer score: a customer counts as a big spender with at least this much spent in 12 months', 'Customer score: a customer counts as a big spender with at least this much spent in 12 months',
  'Spend is net of returns. Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.', 'Spend is net of returns. Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.',
  'Spend is net of returns. Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.', 3063),
 ('crm_winback_days', 'crm', 'number', null, 'days', null, 1, 3650,
  'Lapsed customer: not seen for this many days', 'Lapsed customer: not seen for this many days', 'Lapsed customer: not seen for this many days',
  'Blank = the lapsed list asks you to type the number of days each time. A number makes it the default for the lapsed list.',
  'Blank = the lapsed list asks you to type the number of days each time. A number makes it the default for the lapsed list.',
  'Blank = the lapsed list asks you to type the number of days each time. A number makes it the default for the lapsed list.', 3064),
 ('crm_metrics_batch', 'crm', 'number', '2000'::jsonb, 'customers', null, 100, 20000,
  'Most customers scored in one run', 'Most customers scored in one run', 'Most customers scored in one run',
  'A technical batch size, not a business limit. A bigger shop just presses Refresh scores a few times. Oldest scores are done first.',
  'A technical batch size, not a business limit. A bigger shop just presses Refresh scores a few times. Oldest scores are done first.',
  'A technical batch size, not a business limit. A bigger shop just presses Refresh scores a few times. Oldest scores are done first.', 3065),
 ('crm_metrics_schedule_on', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Refresh customer scores by itself', 'Refresh customer scores by itself', 'Refresh customer scores by itself',
  'OFF = scores are refreshed only when someone presses Refresh scores (today). ON = the 30-minute notify job refreshes them, but only as often as the hours below.',
  'OFF = scores are refreshed only when someone presses Refresh scores (today). ON = the 30-minute notify job refreshes them, but only as often as the hours below.',
  'OFF = scores are refreshed only when someone presses Refresh scores (today). ON = the 30-minute notify job refreshes them, but only as often as the hours below.', 3066),
 ('crm_metrics_schedule_hours', 'crm', 'number', null, 'hours', null, 1, 720,
  'Refresh customer scores by itself: at most once every this many hours', 'Refresh customer scores by itself: at most once every this many hours', 'Refresh customer scores by itself: at most once every this many hours',
  'Blank = the scheduled refresh does nothing even if switched ON. A big shop is finished over several runs; each run stays inside the batch size above.',
  'Blank = the scheduled refresh does nothing even if switched ON. A big shop is finished over several runs; each run stays inside the batch size above.',
  'Blank = the scheduled refresh does nothing even if switched ON. A big shop is finished over several runs; each run stays inside the batch size above.', 3067),
 ('crm_segment_max_members', 'crm', 'number', '5000'::jsonb, 'customers', null, 100, 50000,
  'Largest list that can be frozen', 'Largest list that can be frozen', 'Largest list that can be frozen',
  'A technical safety size. A list with more customers can still be looked at and counted, but it cannot be frozen until you narrow the rules or raise this number.',
  'A technical safety size. A list with more customers can still be looked at and counted, but it cannot be frozen until you narrow the rules or raise this number.',
  'A technical safety size. A list with more customers can still be looked at and counted, but it cannot be frozen until you narrow the rules or raise this number.', 3068),
 ('crm_seg_export_on', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Customer lists: allow export', 'Customer lists: allow export', 'Customer lists: allow export',
  'OFF = no list can be exported (today). ON = people with the Export right can download a list, with a reason, and every export is written to a log.',
  'OFF = no list can be exported (today). ON = people with the Export right can download a list, with a reason, and every export is written to a log.',
  'OFF = no list can be exported (today). ON = people with the Export right can download a list, with a reason, and every export is written to a log.', 3069),
 ('crm_seg_export_max_rows', 'crm', 'number', null, 'customers', null, 1, 50000,
  'Customer lists: most customers one export may hold', 'Customer lists: most customers one export may hold', 'Customer lists: most customers one export may hold',
  'Blank = export stays blocked even if switched ON. A list bigger than this number is refused, never cut short silently.',
  'Blank = export stays blocked even if switched ON. A list bigger than this number is refused, never cut short silently.',
  'Blank = export stays blocked even if switched ON. A list bigger than this number is refused, never cut short silently.', 3070)
on conflict (key) do nothing;

-- Rights. Nobody holds them until the owner gives them (the owner always can). Other CRM packages seed the same codes with "where not exists", so the first paste wins.
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select v.c, 'master', v.s, v.l, v.l, v.l, 'once', null
  from (values ('crm_view', 3060, 'See customer lists, scores and customer notes'),
               ('crm_contact_view', 3061, 'See full phone numbers and addresses in customer lists'),
               ('crm_export', 3062, 'Export customer lists'),
               ('crm_settings_edit', 3063, 'Save customer lists and refresh customer scores')) v(c, s, l)
 where not exists (select 1 from public.grant_defs d where d.grant_code = v.c);

-- ============================================================================
-- 2. WHO MAY DO WHAT (internal; closed to browsers)
-- ============================================================================
create or replace function public._crmc_view_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._cust_mgr43() or public.has_grant('crm_view') or public.has_grant('crm_settings_edit'));
$$;
create or replace function public._crmc_edit_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_settings_edit'));
$$;
create or replace function public._crmc_run_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._cust_mgr43() or public.has_grant('crm_settings_edit'));
$$;
create or replace function public._crmc_export_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_export'));
$$;
-- package B's privacy guard, read through the rule only: a missing rule is OFF (phones show as they do today)
create or replace function public._crmc_guard_on() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_on('crm_pii_guard_on'), false);
$$;
create or replace function public._crmc_contact_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_contact_view'));
$$;
create or replace function public._crmc_mobile_visible() returns boolean language sql stable security definer set search_path = public as $$
  select not public._crmc_guard_on() or public._crmc_contact_ok();
$$;
create or replace function public._crmc_mask(p_mobile text) returns text language sql stable security definer set search_path = public as $$
  select case when p_mobile is null then null
              when coalesce(public.rule_txt('crm_mask_style'), 'first3_last2') = 'hidden' then '****'
              when coalesce(public.rule_txt('crm_mask_style'), 'first3_last2') = 'last4' and length(p_mobile) > 4 then repeat('*', length(p_mobile) - 4) || right(p_mobile, 4)
              when length(p_mobile) >= 6 then left(p_mobile, 3) || repeat('*', length(p_mobile) - 5) || right(p_mobile, 2)
              else repeat('*', length(p_mobile)) end;
$$;
-- mobile as the caller may see it (never returns a full number to a masked caller)
create or replace function public._crmc_mobile_for_caller(p_mobile text) returns text language sql stable security definer set search_path = public as $$
  select case when public._crmc_mobile_visible() then p_mobile else public._crmc_mask(p_mobile) end;
$$;
create or replace function public._crmc_audit(p_action text, p_table text, p_rec text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_rec, coalesce(p_detail, '{}'::jsonb));
end $$;
create or replace function public._crmc_append_only() returns trigger language plpgsql as $$
begin raise exception 'crmc_append_only' using hint = 'This log is never edited or deleted'; end $$;

-- days from p_today to the next month/day of p_date (Feb 29 counts as Feb 28 in a year that has no Feb 29); null when p_date is null
create or replace function public._crmc_days_to_next(p_date date, p_today date) returns int language plpgsql immutable as $$
declare y int; m int := extract(month from p_date)::int; d int := extract(day from p_date)::int; c date;
begin
  if p_date is null or p_today is null then return null; end if;
  y := extract(year from p_today)::int;
  for i in 0 .. 1 loop
    c := make_date(y + i, m, case when m = 2 and d = 29 and not ((y + i) % 4 = 0 and ((y + i) % 100 <> 0 or (y + i) % 400 = 0)) then 28 else d end);
    if c >= p_today then return c - p_today; end if;
  end loop;
  return null;
end $$;

-- ============================================================================
-- 3. THE SCORE CACHE
-- ============================================================================
create table if not exists public.crm_metrics (
  customer_id uuid primary key references public.customers(id),
  first_visit date, last_visit date,
  orders_total int not null default 0,
  orders_12m int not null default 0,
  lifetime_spend numeric not null default 0,          -- net of returns, same rule as _cust_stats43
  spend_12m numeric not null default 0,               -- sales of the last 12 months minus returns of the last 12 months
  gross_spend numeric not null default 0,             -- before returns
  returns_total numeric not null default 0,
  avg_bill numeric,                                   -- gross spend / orders
  due_amount numeric not null default 0,              -- what the customer owes now (0 when nothing)
  points int not null default 0,
  top_location_id int,                                -- the outlet with most orders in the last 12 months
  outlet_ids int[] not null default '{}',             -- outlets used in the last 12 months
  top_items jsonb not null default '[]'::jsonb,       -- [{item_id,name,qty,amount}] three biggest items of the last 12 months
  computed_at timestamptz not null default now(),
  computed_on date not null default public._today43()
);
create index if not exists crm_metrics_last_visit on public.crm_metrics (last_visit);
create index if not exists crm_metrics_computed_on on public.crm_metrics (computed_on);
alter table public.crm_metrics enable row level security;
revoke all on public.crm_metrics from public, anon, authenticated;
drop trigger if exists crm_metrics_no_delete on public.crm_metrics;
create trigger crm_metrics_no_delete before delete on public.crm_metrics for each row execute function public.no_hard_delete();

create table if not exists public.crm_metrics_runs (
  id bigserial primary key,
  at timestamptz not null default now(),
  by_user uuid, kind text not null check (kind in ('manual', 'scheduled')),
  dry boolean not null default false,
  processed int not null default 0, remaining int not null default 0, batch int not null default 0
);
alter table public.crm_metrics_runs enable row level security;
revoke all on public.crm_metrics_runs from public, anon, authenticated;
drop trigger if exists crm_metrics_runs_ro on public.crm_metrics_runs;
create trigger crm_metrics_runs_ro before update or delete on public.crm_metrics_runs for each row execute function public._crmc_append_only();

-- the cut-offs in force: owner mode only when all three are set; otherwise the standard labels of the existing Customer value report
create or replace function public._crmc_cfg() returns table (rd numeric, fm numeric, sm numeric, mode text)
language sql stable security definer set search_path = public as $$
  select a, b, c, case when a is not null and b is not null and c is not null then 'owner' else 'standard' end
    from (select public.rule_num('crm_rfm_recent_days') a, public.rule_num('crm_rfm_frequency_min') b, public.rule_num('crm_rfm_spend_min') c) z;
$$;

-- the label of one customer. Owner mode: Champion, Loyal, Big spender, New, Recent, At risk, Drifting, Lost.
-- Standard mode (any cut-off blank) = exactly the labels of the Customer value report (m1_rfm): Champion (3+ orders, seen within 30 days), At-risk (2+ orders, not seen for over 60 days),
-- One-time (one order), Regular; plus Inactive (no order in 12 months). No order ever = No purchases.
create or replace function public._crmc_label(p_orders_total int, p_orders12 int, p_spend12 numeric, p_days int, p_rd numeric, p_fm numeric, p_sm numeric) returns text
language sql immutable as $$
  select case
    when coalesce(p_orders_total, 0) = 0 then 'No purchases'
    when p_rd is not null and p_fm is not null and p_sm is not null then
      case when p_days <= p_rd then
             case when p_orders12 >= p_fm and p_spend12 >= p_sm then 'Champion'
                  when p_orders12 >= p_fm then 'Loyal'
                  when p_spend12 >= p_sm then 'Big spender'
                  when p_orders_total = 1 then 'New'
                  else 'Recent' end
           else
             case when p_orders12 >= p_fm or p_spend12 >= p_sm then 'At risk'
                  when p_orders12 > 0 then 'Drifting'
                  else 'Lost' end end
    else
      case when p_orders12 = 0 then 'Inactive'
           when p_orders12 >= 3 and p_days <= 30 then 'Champion'
           when p_orders12 >= 2 and p_days > 60 then 'At-risk'
           when p_orders12 = 1 then 'One-time'
           else 'Regular' end end;
$$;

-- scores read live: one row per ACTIVE customer that has a cache row. Internal contract for the other CRM packages (campaigns, automation, dashboard).
create or replace function public._crmc_scored(p_today date default null)
returns table (customer_id uuid, days_since_last int, orders_total int, orders_12m int, spend_12m numeric, lifetime_spend numeric, due_amount numeric, points int,
               last_visit date, r_ok boolean, f_ok boolean, m_ok boolean, label text, mode text, computed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_d date := coalesce(p_today, public._today43()); v_rd numeric; v_fm numeric; v_sm numeric; v_mode text;
begin
  select c.rd, c.fm, c.sm, c.mode into v_rd, v_fm, v_sm, v_mode from public._crmc_cfg() c;   -- cut-offs and today are read once, not once per customer
  return query
  select m.customer_id, case when m.last_visit is null then null else v_d - m.last_visit end, m.orders_total, m.orders_12m, m.spend_12m, m.lifetime_spend, m.due_amount, m.points, m.last_visit,
         case when v_mode = 'owner' and m.last_visit is not null then (v_d - m.last_visit) <= v_rd end,
         case when v_mode = 'owner' then m.orders_12m >= v_fm end,
         case when v_mode = 'owner' then m.spend_12m >= v_sm end,
         public._crmc_label(m.orders_total, m.orders_12m, m.spend_12m, case when m.last_visit is null then null else v_d - m.last_visit end, v_rd, v_fm, v_sm), v_mode, m.computed_at
    from public.crm_metrics m join public.customers c on c.id = m.customer_id and c.active;
end $$;

-- which customers need new scores: no row, computed on an earlier day, or a sale / return newer than the row (oldest first)
create or replace function public._crmc_stale(p_limit int default null) returns setof uuid language sql stable security definer set search_path = public as $$
  select c.id
    from public.customers c left join public.crm_metrics m on m.customer_id = c.id
   where c.active and (m.customer_id is null or m.computed_on < public._today43()
          or exists (select 1 from public.sales s where s.customer_id = c.id and s.sold_at > m.computed_at)
          or exists (select 1 from public.sale_returns r where r.customer_id = c.id and r.created_at > m.computed_at))
   order by m.computed_at nulls first, c.id
   limit coalesce(p_limit, 2147483647);
$$;

-- the worker. p_limit never exceeds crm_metrics_batch. No permission test here (the callers test).
create or replace function public._crmc_refresh_core(p_dry boolean, p_limit int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare today date := public._today43(); cap int; ids uuid[]; v_n int := 0; total_stale int; rem int;
begin
  cap := least(greatest(coalesce(p_limit, 2147483647), 1), greatest(coalesce(public.rule_num('crm_metrics_batch'), 2000), 1))::int;
  select count(*) into total_stale from public._crmc_stale(null);
  if p_dry then
    return jsonb_build_object('dry', true, 'stale', total_stale, 'would_process', least(total_stale, cap), 'batch', cap);
  end if;
  if not pg_try_advisory_xact_lock(hashtext('crmc_refresh')) then return jsonb_build_object('busy', true); end if;
  select coalesce(array_agg(x), '{}') into ids from public._crmc_stale(cap) x;
  if cardinality(ids) > 0 then
    with s as (
      select x.customer_id cid, count(*)::int n, coalesce(sum(x.total), 0) amt, min(x.sale_date) fd, max(x.sale_date) ld,
             count(*) filter (where x.sale_date > today - 365)::int n12, coalesce(sum(x.total) filter (where x.sale_date > today - 365), 0) amt12
        from public.sales x where x.customer_id = any (ids) and x.status = 'done' group by 1),
    r as (
      select y.customer_id cid, coalesce(sum(y.amount), 0) amt,
             coalesce(sum(y.amount) filter (where (y.created_at at time zone 'Asia/Dhaka')::date > today - 365), 0) amt12
        from public.sale_returns y where y.customer_id = any (ids) and y.status = 'done' group by 1),
    lo as (
      select x.customer_id cid, x.location_id loc, count(*) n, max(x.sale_date) ld
        from public.sales x where x.customer_id = any (ids) and x.status = 'done' and x.sale_date > today - 365 group by 1, 2),
    tp as (select distinct on (cid) cid, loc from lo order by cid, n desc, ld desc, loc),
    oa as (select cid, array_agg(loc order by loc) locs from lo group by cid),
    it0 as (
      select x.customer_id cid, e ->> 'item_id' iid, max(e ->> 'name') nm,
             sum(case when e ->> 'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'qty')::numeric else 0 end) q,
             sum(case when e ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'amount')::numeric else 0 end) a
        from public.sales x cross join lateral jsonb_array_elements(case when jsonb_typeof(x.lines) = 'array' then x.lines else '[]'::jsonb end) e
       where x.customer_id = any (ids) and x.status = 'done' and x.sale_date > today - 365 and (e ->> 'item_id') ~ '^[0-9a-f-]{36}$' group by 1, 2),
    it1 as (select it0.*, row_number() over (partition by cid order by a desc, iid) rn from it0),
    it as (select cid, jsonb_agg(jsonb_build_object('item_id', iid, 'name', nm, 'qty', q, 'amount', a) order by rn) arr from it1 where rn <= 3 group by cid)
    insert into public.crm_metrics as m (customer_id, first_visit, last_visit, orders_total, orders_12m, lifetime_spend, spend_12m, gross_spend, returns_total, avg_bill, due_amount, points,
                                         top_location_id, outlet_ids, top_items, computed_at, computed_on)
    select b.cid, s.fd, s.ld, coalesce(s.n, 0), coalesce(s.n12, 0), coalesce(s.amt, 0) - coalesce(r.amt, 0), coalesce(s.amt12, 0) - coalesce(r.amt12, 0), coalesce(s.amt, 0), coalesce(r.amt, 0),
           case when coalesce(s.n, 0) > 0 then round(s.amt / s.n, 2) end, greatest(public._cust_bal(b.cid), 0),
           coalesce((select sum(l.delta) from public.customer_points_ledger l where l.customer_id = b.cid), 0)::int,
           tp.loc, coalesce(oa.locs, '{}'), coalesce(it.arr, '[]'::jsonb), now(), today
      from (select unnest(ids) cid) b left join s on s.cid = b.cid left join r on r.cid = b.cid left join tp on tp.cid = b.cid left join oa on oa.cid = b.cid left join it on it.cid = b.cid
    on conflict (customer_id) do update set first_visit = excluded.first_visit, last_visit = excluded.last_visit, orders_total = excluded.orders_total, orders_12m = excluded.orders_12m,
       lifetime_spend = excluded.lifetime_spend, spend_12m = excluded.spend_12m, gross_spend = excluded.gross_spend, returns_total = excluded.returns_total, avg_bill = excluded.avg_bill,
       due_amount = excluded.due_amount, points = excluded.points, top_location_id = excluded.top_location_id, outlet_ids = excluded.outlet_ids, top_items = excluded.top_items,
       computed_at = excluded.computed_at, computed_on = excluded.computed_on;
    get diagnostics v_n = row_count;
  end if;
  select count(*) into rem from public._crmc_stale(null);
  return jsonb_build_object('dry', false, 'processed', v_n, 'remaining', rem, 'batch', cap);
end $$;

-- on demand
create or replace function public.crmc_metrics_refresh(p_dry boolean default false, p_limit int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if not public._crmc_run_ok() then raise exception 'not allowed'; end if;
  if p_limit is not null and (p_limit < 1 or p_limit > 20000) then raise exception 'bad_value'; end if;
  r := public._crmc_refresh_core(coalesce(p_dry, false), p_limit);
  if coalesce((r ->> 'busy')::boolean, false) then return r; end if;
  if not coalesce(p_dry, false) then
    insert into public.crm_metrics_runs (by_user, kind, dry, processed, remaining, batch) values (auth.uid(), 'manual', false, (r ->> 'processed')::int, (r ->> 'remaining')::int, (r ->> 'batch')::int);
    perform public._crmc_audit('crm_scores_refresh', 'crm_metrics', 'manual', r);
  end if;
  return r;
end $$;

-- for the 30-minute notify job (ops bot, purpose notify) or the owner. Does nothing unless the owner switched it ON and set the hours.
create or replace function public.crmc_scheduled_run() returns jsonb
language plpgsql security definer set search_path = public as $$
declare hrs numeric; last_run record; r jsonb;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_metrics_schedule_on') then return jsonb_build_object('off', true); end if;
  hrs := public.rule_num('crm_metrics_schedule_hours');
  if hrs is null then return jsonb_build_object('blocked', 'set_hours'); end if;
  select * into last_run from public.crm_metrics_runs where kind = 'scheduled' and not dry order by id desc limit 1;
  if found and last_run.remaining = 0 and last_run.at > now() - make_interval(secs => hrs * 3600) then return jsonb_build_object('skipped', 'not_due', 'last_run', last_run.at); end if;
  r := public._crmc_refresh_core(false, null);
  if coalesce((r ->> 'busy')::boolean, false) then return r; end if;
  insert into public.crm_metrics_runs (by_user, kind, dry, processed, remaining, batch) values (auth.uid(), 'scheduled', false, (r ->> 'processed')::int, (r ->> 'remaining')::int, (r ->> 'batch')::int);
  perform public._crmc_audit('crm_scores_refresh', 'crm_metrics', 'scheduled', r);
  return r;
end $$;

create or replace function public.crmc_metrics_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cfg record; tot int; scored int; stale int; lr record;
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  select * into cfg from public._crmc_cfg();
  select count(*) into tot from public.customers where active;
  select count(*) into scored from public.crm_metrics m join public.customers c on c.id = m.customer_id and c.active;
  select count(*) into stale from public._crmc_stale(null);
  select * into lr from public.crm_metrics_runs where not dry order by id desc limit 1;
  return jsonb_build_object('customers', tot, 'scored', scored, 'never_scored', tot - scored, 'stale', stale,
    'oldest', (select min(m.computed_at) from public.crm_metrics m join public.customers c on c.id = m.customer_id and c.active),
    'newest', (select max(m.computed_at) from public.crm_metrics m),
    'mode', cfg.mode, 'recent_days', cfg.rd, 'frequency_min', cfg.fm, 'spend_min', cfg.sm,
    'missing', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (select 'crm_rfm_recent_days' k where cfg.rd is null union all select 'crm_rfm_frequency_min' where cfg.fm is null union all select 'crm_rfm_spend_min' where cfg.sm is null) z),
    'batch', coalesce(public.rule_num('crm_metrics_batch'), 2000), 'schedule_on', public.rule_on('crm_metrics_schedule_on'), 'schedule_hours', public.rule_num('crm_metrics_schedule_hours'),
    'last_run', case when lr.id is null then null else jsonb_build_object('at', lr.at, 'kind', lr.kind, 'processed', lr.processed, 'remaining', lr.remaining) end,
    'winback_days', public.rule_num('crm_winback_days'));
end $$;

-- what the caller may do (for showing or hiding buttons; the server still decides every call)
create or replace function public.crmc_me() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('view', public._crmc_view_ok(), 'edit', public._crmc_edit_ok(), 'run', public._crmc_run_ok(), 'export', public._crmc_export_ok(),
    'contact', public._crmc_mobile_visible(), 'cost', coalesce(public.biz_cost_ok(), false), 'owner', public.is_owner(),
    'segments_on', public.rule_on('crm_segments_on'), 'export_on', public.rule_on('crm_seg_export_on'), 'export_max', public.rule_num('crm_seg_export_max_rows'),
    'guard_on', public._crmc_guard_on());
$$;

-- exact-text patch helper for the one optional hook (docs/integration/CRM-C.md). Same contract as the earlier packages: marker, unique site, nothing half done.
create or replace function public._crmc_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos[A-Z]{3,6}$' then raise exception 'crmc_patch: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1);
    if n = 0 then raise exception 'crmc_patch: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'crmc_patch: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'crmc_patch: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;

-- ============================================================================
-- 4. RIGHTS ON THE FUNCTIONS: internal helpers are closed to browsers, the screens' functions are open to signed-in users (each one tests the caller itself)
-- ============================================================================
revoke all on function public._crmc_present(), public._crmc_view_ok(), public._crmc_edit_ok(), public._crmc_run_ok(), public._crmc_export_ok(), public._crmc_guard_on(), public._crmc_contact_ok(),
  public._crmc_mobile_visible(), public._crmc_mask(text), public._crmc_mobile_for_caller(text), public._crmc_audit(text, text, text, jsonb), public._crmc_append_only(), public._crmc_days_to_next(date, date),
  public._crmc_cfg(), public._crmc_label(int, int, numeric, int, numeric, numeric, numeric), public._crmc_scored(date), public._crmc_stale(int), public._crmc_refresh_core(boolean, int),
  public._crmc_patch(regprocedure, text[], text) from public, anon, authenticated;
revoke all on function public.crmc_metrics_refresh(boolean, int), public.crmc_scheduled_run(), public.crmc_metrics_status(), public.crmc_me() from public, anon;
grant execute on function public.crmc_metrics_refresh(boolean, int), public.crmc_scheduled_run(), public.crmc_metrics_status(), public.crmc_me() to authenticated;
