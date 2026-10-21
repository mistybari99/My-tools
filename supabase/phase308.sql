-- Phase 308 (package CRM-C, label 108) - CUSTOMER VALUE: overview (repeat-purchase rate, lifetime value), RFM labels and lists, lapsed and at-risk lists, customer profit view, export.
-- Paste AFTER phase307. Paste-twice safe. Nothing existing is edited or re-created. Names start crmc_ / _crmc_.
-- Everything here READS the cache of phase 306 (and sales / returns / the stock-ledger cost source of phase 72 for the profit view). No money table is written, no accounting figure changes.
-- The profit view needs the cost right (the same test the existing profit reports use: biz_cost_ok) on top of the CRM right; it uses the one cost source of the reports (_cogs_lines72), so a
-- customer's revenue and cost add up to the same numbers as the Profit report for the same days. Sales without a known cost are shown apart (unknown_cost_revenue), never guessed.
-- Export: off by default; needs the right crm_export, the switch crm_seg_export_on, a row limit (crm_seg_export_max_rows) and a written reason; a list bigger than the limit is refused, never cut short;
-- the phone column is masked unless the caller may see full numbers; address, notes and birthday are never exported; every export is written to an append-only log and the audit log.

do $g$ begin
  if to_regprocedure('public.crmc_segment_save(uuid,bigint,text,jsonb,text)') is null then raise exception 'phase308 needs phase307 first'; end if;
end $g$;

-- ============================================================================
-- 1. OVERVIEW: repeat-purchase rate, lifetime value, lapsed and at-risk counts
-- ============================================================================
create or replace function public.crmc_overview(p_outlet int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_today date := public._today43(); v_wb numeric := public.rule_num('crm_winback_days'); v_r jsonb; v_unscored int; v_tot int; v_mode text;
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  if p_outlet is not null and p_outlet < 1 then raise exception 'bad_value'; end if;
  select count(*) into v_tot from public.customers where active;
  select mode into v_mode from public._crmc_cfg();
  with sc as (
    select s.*, m.first_visit, m.top_location_id, m.avg_bill from public._crmc_scored(v_today) s join public.crm_metrics m on m.customer_id = s.customer_id
     where p_outlet is null or m.top_location_id = p_outlet),
  buyers as (select * from sc where orders_total > 0),
  dcl as (select b.*, ntile(10) over (order by b.lifetime_spend desc) dc from buyers b where b.lifetime_spend > 0)
  select jsonb_build_object(
    'customers_scored', (select count(*) from sc),
    'buyers', (select count(*) from buyers),
    'repeat_buyers', (select count(*) from buyers where orders_total >= 2),
    'repeat_rate_pct', (select round(100.0 * count(*) filter (where orders_total >= 2) / nullif(count(*), 0), 1) from buyers),
    'active_12m', (select count(*) from buyers where orders_12m > 0),
    'repeat_12m', (select count(*) from buyers where orders_12m >= 2),
    'repeat_rate_12m_pct', (select round(100.0 * count(*) filter (where orders_12m >= 2) / nullif(count(*) filter (where orders_12m > 0), 0), 1) from buyers),
    'new_12m', (select count(*) from buyers where first_visit > v_today - 365),
    'avg_lifetime_value', (select round(avg(lifetime_spend), 2) from buyers),
    'median_lifetime_value', (select round((percentile_cont(0.5) within group (order by lifetime_spend))::numeric, 2) from buyers),
    'avg_orders', (select round(avg(orders_total), 2) from buyers),
    'spend_12m', (select coalesce(sum(spend_12m), 0) from sc),
    'top_tenth_share_pct', (select round(100.0 * sum(lifetime_spend) filter (where dc = 1) / nullif(sum(lifetime_spend), 0), 1) from dcl),
    'owing_customers', (select count(*) from sc where due_amount > 0),
    'owed_total', (select coalesce(sum(due_amount), 0) from sc),
    'lapsed', case when v_wb is null then null else (select count(*) from buyers where days_since_last > v_wb) end,
    'at_risk', (select count(*) from sc where label in ('At risk', 'At-risk')),
    'by_label', (select coalesce(jsonb_object_agg(label, n), '{}'::jsonb) from (select label, count(*) n from sc group by 1) z)
  ) into v_r;
  select v_tot - count(*) into v_unscored from public.crm_metrics m join public.customers c on c.id = m.customer_id and c.active;
  return v_r || jsonb_build_object('total_customers', v_tot, 'unscored_customers', v_unscored, 'mode', v_mode, 'winback_days', v_wb, 'outlet', p_outlet,
    'note', 'Spend is net of returns. Rates count customers who have bought at least once. With an outlet chosen, a customer belongs to the outlet where they bought most in the last 12 months.');
end $$;

-- ============================================================================
-- 2. RFM
-- ============================================================================
create or replace function public.crmc_rfm_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_cfg record; v_rows jsonb; v_n int;
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  select * into v_cfg from public._crmc_cfg();
  select count(*) into v_n from public._crmc_scored();
  select coalesce(jsonb_agg(jsonb_build_object('label', label, 'customers', n, 'share_pct', round(100.0 * n / nullif(v_n, 0), 1), 'avg_lifetime_spend', al, 'spend_12m', s12, 'avg_days_since_last', ad) order by n desc, label), '[]'::jsonb)
    into v_rows
    from (select label, count(*) n, round(avg(lifetime_spend), 2) al, coalesce(sum(spend_12m), 0) s12, round(avg(days_since_last), 0) ad from public._crmc_scored() group by label) z;
  return jsonb_build_object('mode', v_cfg.mode, 'recent_days', v_cfg.rd, 'frequency_min', v_cfg.fm, 'spend_min', v_cfg.sm, 'customers_scored', v_n, 'labels', v_rows,
    'explain', case when v_cfg.mode = 'owner'
        then 'Recent = bought within ' || v_cfg.rd::text || ' days. Frequent = at least ' || v_cfg.fm::text || ' orders in 12 months. Big spender = at least ' || v_cfg.sm::text || ' spent in 12 months (net of returns).'
        else 'Standard labels, the same cut-offs as the Customer value report: Champion = 3 or more orders in 12 months and seen within 30 days; At-risk = 2 or more orders and not seen for over 60 days; One-time = one order. Set your own three numbers in Settings to change this.' end);
end $$;

create or replace function public.crmc_rfm_list(p_label text, p_sort text default 'lifetime', p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ids uuid[];
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  if p_label is null or not (p_label = any (public._crmc_labels())) then raise exception 'bad_value'; end if;
  select coalesce(array_agg(s.customer_id), '{}') into v_ids from public._crmc_scored() s where s.label = p_label;
  return public._crmc_page(v_ids, p_sort, p_limit, p_offset);
end $$;

-- biggest customers by value (lifetime value is realised spend, net of returns; there is no forecast)
create or replace function public.crmc_value_list(p_sort text default 'lifetime', p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ids uuid[];
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  select coalesce(array_agg(s.customer_id), '{}') into v_ids from public._crmc_scored() s where s.orders_total > 0;
  return public._crmc_page(v_ids, p_sort, p_limit, p_offset);
end $$;

-- lapsed (not seen for N days) or at risk (label At risk / At-risk). The days come from the call or from crm_winback_days; blank and not given = asked to set it first.
create or replace function public.crmc_lapsed(p_days int default null, p_kind text default 'lapsed', p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_days numeric := coalesce(p_days, public.rule_num('crm_winback_days')); v_ids uuid[];
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  if p_kind not in ('lapsed', 'at_risk') then raise exception 'bad_value'; end if;
  if p_kind = 'lapsed' then
    if v_days is null then raise exception 'set_winback_days'; end if;
    if v_days < 1 or v_days > 3650 then raise exception 'bad_value'; end if;
    select coalesce(array_agg(s.customer_id), '{}') into v_ids from public._crmc_scored() s where s.orders_total > 0 and s.days_since_last > v_days;
    return public._crmc_page(v_ids, 'lifetime', p_limit, p_offset) || jsonb_build_object('days', v_days, 'kind', p_kind);
  end if;
  select coalesce(array_agg(s.customer_id), '{}') into v_ids from public._crmc_scored() s where s.label in ('At risk', 'At-risk');
  return public._crmc_page(v_ids, 'lifetime', p_limit, p_offset) || jsonb_build_object('kind', p_kind);
end $$;

-- one customer's value card (for the customer screen). Same visibility as the existing customer profile (POS view).
create or replace function public.crmc_customer_value(p_customer uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s record; m public.crm_metrics;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into m from public.crm_metrics where customer_id = p_customer;
  if not found then return jsonb_build_object('scored', false); end if;
  select * into s from public._crmc_scored() where customer_id = p_customer;
  if s.customer_id is null then return jsonb_build_object('scored', false); end if;
  return jsonb_build_object('scored', true, 'label', s.label, 'mode', s.mode, 'days_since_last', s.days_since_last, 'orders_total', s.orders_total, 'orders_12m', s.orders_12m,
    'lifetime_spend', s.lifetime_spend, 'spend_12m', s.spend_12m, 'avg_bill', m.avg_bill, 'due_amount', s.due_amount, 'top_items', m.top_items, 'computed_at', s.computed_at);
end $$;

-- ============================================================================
-- 3. CUSTOMER PROFIT (read only; needs the cost right; same cost source as the Profit report)
-- ============================================================================
create or replace function public.crmc_profit(p_from date, p_to date, p_sort text default 'margin', p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_res jsonb; v_sort text := coalesce(p_sort, 'margin');
begin
  if not (public._crmc_view_ok() and coalesce(public.biz_cost_ok(), false)) then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  if v_sort not in ('margin', 'revenue', 'margin_pct') then raise exception 'bad_value'; end if;
  if to_regprocedure('public._cogs_lines72(date,date,integer[])') is null then raise exception 'cost_data_missing'; end if;
  with d as materialized (select * from public._cogs_lines72(p_from, p_to, public._cogs_locs72(null))),
  j as (select case d.src when 'sale' then s.customer_id else r.customer_id end cid, case d.src when 'sale' then 1 else -1 end sg, d.rev, d.led_rev, d.fb_rev, d.led_cogs, d.fb_cogs, d.unk_rev
          from d left join public.sales s on d.src = 'sale' and s.id = d.doc_id left join public.sale_returns r on d.src = 'return' and r.id = d.doc_id),
  g as (select cid, sum(sg * rev) revenue, sum(sg * (led_rev + fb_rev)) costed_rev, sum(sg * (led_cogs + fb_cogs)) cogs, sum(sg * unk_rev) unk from j where cid is not null group by cid),
  tot as (select coalesce(sum((case d.src when 'sale' then 1 else -1 end) * d.rev), 0) all_rev from d),
  rk as (select g.*, c.name, c.mobile, row_number() over (order by case v_sort when 'margin' then g.costed_rev - g.cogs when 'revenue' then g.revenue
                                                       when 'margin_pct' then case when g.costed_rev > 0 then (g.costed_rev - g.cogs) / g.costed_rev end end desc nulls last, c.name, c.id) ord
           from g join public.customers c on c.id = g.cid)
  select jsonb_build_object('from', p_from, 'to', p_to, 'customers', (select count(*) from rk), 'limit', v_lim, 'offset', v_off,
    'all_revenue', (select round(all_rev, 2) from tot), 'customer_revenue', (select round(coalesce(sum(revenue), 0), 2) from g), 'masked', not public._crmc_mobile_visible(),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('customer_id', rk.cid, 'name', rk.name, 'mobile', public._crmc_mobile_for_caller(rk.mobile), 'revenue', round(rk.revenue, 2),
               'costed_revenue', round(rk.costed_rev, 2), 'cogs', round(rk.cogs, 2), 'margin', round(rk.costed_rev - rk.cogs, 2),
               'margin_pct', case when rk.costed_rev > 0 then round(100 * (rk.costed_rev - rk.cogs) / rk.costed_rev, 1) end,
               'unknown_cost_revenue', round(rk.unk, 2), 'cost_partial', rk.unk > 0) order by rk.ord), '[]'::jsonb) from rk where rk.ord > v_off and rk.ord <= v_off + v_lim),
    'note', 'Only sales linked to a customer are listed. Cost comes from the stock ledger (item cost book only as a fallback). Revenue without a known cost is shown apart and left out of the margin.')
  into v_res;
  return v_res;
end $$;

-- ============================================================================
-- 4. EXPORT (off by default)
-- ============================================================================
create table if not exists public.crmc_export_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  by_user uuid, staff_id text,
  client_id uuid unique,
  segment_id bigint, rule jsonb,
  rows int not null, columns text[] not null, mobile_full boolean not null,
  reason text not null
);
alter table public.crmc_export_log enable row level security;
revoke all on public.crmc_export_log from public, anon, authenticated;
drop trigger if exists crmc_export_log_ro on public.crmc_export_log;
create trigger crmc_export_log_ro before update or delete on public.crmc_export_log for each row execute function public._crmc_append_only();

create or replace function public.crmc_export(p_client uuid, p_segment bigint, p_rule jsonb, p_reason text, p_fields text[] default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_all text[] := array['name', 'mobile', 'tier', 'last_visit', 'orders_12m', 'spend_12m', 'lifetime_spend', 'label', 'sms_opt_in', 'whatsapp_opt_in', 'do_not_contact'];
  v_cols text[]; v_ids uuid[]; v_max numeric := public.rule_num('crm_seg_export_max_rows'); v_full boolean := public._crmc_contact_ok(); v_dnc uuid[] := '{}'; v_rows jsonb; v_id bigint; v_f text;
begin
  if not public._crmc_export_ok() then raise exception 'not allowed'; end if;
  if (p_segment is null) = (p_rule is null) then raise exception 'bad_value'; end if;
  if not public.rule_on('crm_seg_export_on') then raise exception 'export_off'; end if;
  if v_max is null then raise exception 'set_export_max_rows'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'reason_required'; end if;
  if p_client is not null and exists (select 1 from public.crmc_export_log where client_id = p_client) then return jsonb_build_object('repeat', true, 'rows', 0); end if;
  v_cols := coalesce(p_fields, v_all);
  foreach v_f in array v_cols loop if not (v_f = any (v_all)) then raise exception 'bad_value'; end if; end loop;
  if cardinality(v_cols) = 0 or cardinality(v_cols) <> (select count(distinct x) from unnest(v_cols) x) then raise exception 'bad_value'; end if;
  v_ids := public._crmc_ids_of(p_segment, p_rule);
  if cardinality(v_ids) = 0 then raise exception 'empty_segment'; end if;
  if cardinality(v_ids) > v_max then raise exception 'over_export_cap:%', cardinality(v_ids); end if;
  if to_regclass('public.crm_contact_prefs') is not null then
    begin execute 'select coalesce(array_agg(customer_id), ''{}'') from public.crm_contact_prefs where dnc' into v_dnc; exception when others then v_dnc := '{}'; end;
  end if;
  select coalesce(jsonb_agg((select jsonb_agg(o -> f order by ord) from unnest(v_cols) with ordinality u(f, ord)) order by q.nm, q.cid), '[]'::jsonb) into v_rows from (
    select c.id cid, c.name nm,
           jsonb_build_object('name', c.name, 'mobile', case when v_full then c.mobile else public._crmc_mask(c.mobile) end, 'tier', t.code, 'last_visit', m.last_visit, 'orders_12m', m.orders_12m,
             'spend_12m', m.spend_12m, 'lifetime_spend', m.lifetime_spend,
             'label', case when m.customer_id is null then null else public._crmc_label(m.orders_total, m.orders_12m, m.spend_12m, case when m.last_visit is null then null else public._today43() - m.last_visit end, cfg.rd, cfg.fm, cfg.sm) end,
             'sms_opt_in', exists (select 1 from public.notify_optin n where n.customer_id = c.id and n.channel = 'sms' and n.status = 'in'),
             'whatsapp_opt_in', exists (select 1 from public.notify_optin n where n.customer_id = c.id and n.channel = 'whatsapp' and n.status = 'in'),
             'do_not_contact', c.id = any (v_dnc)) o
      from public.customers c left join public.crm_metrics m on m.customer_id = c.id left join public.customer_tiers t on t.id = c.tier_id cross join public._crmc_cfg() cfg
     where c.id = any (v_ids)) q;
  insert into public.crmc_export_log (by_user, staff_id, client_id, segment_id, rule, rows, columns, mobile_full, reason)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_client, p_segment, case when p_segment is null then public._crmc_rule_norm(p_rule) end,
            cardinality(v_ids), v_cols, v_full and 'mobile' = any (v_cols), btrim(p_reason)) returning id into v_id;
  perform public._crmc_audit('crm_list_export', 'crmc_export_log', v_id::text, jsonb_build_object('rows', cardinality(v_ids), 'segment_id', p_segment, 'columns', to_jsonb(v_cols), 'reason', btrim(p_reason)));
  return jsonb_build_object('log_id', v_id, 'columns', to_jsonb(v_cols), 'rows', v_rows, 'total', cardinality(v_ids), 'mobile_masked', 'mobile' = any (v_cols) and not v_full);
end $$;

create or replace function public.crmc_export_log_list(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmc_export_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'at', at, 'staff_id', staff_id, 'segment_id', segment_id, 'rows', rows, 'columns', columns, 'mobile_full', mobile_full, 'reason', reason) order by id desc)
                     from (select * from public.crmc_export_log order by id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) z), '[]'::jsonb);
end $$;

-- ============================================================================
-- 5. RIGHTS
-- ============================================================================
revoke all on function public.crmc_overview(int), public.crmc_rfm_summary(), public.crmc_rfm_list(text, text, int, int), public.crmc_value_list(text, int, int), public.crmc_lapsed(int, text, int, int),
  public.crmc_customer_value(uuid), public.crmc_profit(date, date, text, int, int), public.crmc_export(uuid, bigint, jsonb, text, text[]), public.crmc_export_log_list(int) from public, anon;
grant execute on function public.crmc_overview(int), public.crmc_rfm_summary(), public.crmc_rfm_list(text, text, int, int), public.crmc_value_list(text, int, int), public.crmc_lapsed(int, text, int, int),
  public.crmc_customer_value(uuid), public.crmc_profit(date, date, text, int, int), public.crmc_export(uuid, bigint, jsonb, text, text[]), public.crmc_export_log_list(int) to authenticated;
