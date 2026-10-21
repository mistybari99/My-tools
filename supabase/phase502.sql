-- Phase 502 (SW-3) - SWEETS PROFIT: the item analysis (biz_items) nets sale returns, as the returns line of the other reports already says.
-- Paste AFTER phase501. Paste-twice safe (create or replace, on conflict do nothing). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, A3 (real profit) and finding F-16: "biz_items / builder summaries do not consistently net sales returns".
-- Reproduced on a local throwaway database (before this file): 3 kg sold, 1 kg returned in the same period: biz_items shows qty 3 and the full revenue.
-- The audit names a "bos112 returns-netting block" that is live in biz_items but is NOT in this repository, and its text was not found (no backup text
-- in the repo, no scratch copy). It is not recreated from memory here. This file writes the netting from the return rows themselves (sale_returns.lines),
-- dated the way the other reports date a return: the day it was made (Asia/Dhaka), counted in that period and in the location of the return.
-- Switch biz_items_net_returns (default OFF). OFF = the report is exactly as before (sales only, returns not taken off).
-- The audit's other profit gaps (unknown cost shown as 100% margin, wastage and card fees, payroll double count, date cut-off for shared costs) are NOT changed here.
-- They are listed in docs/PLAN_NEXT.md with the decision for each.

do $g$ begin
  if to_regclass('public.sale_returns') is null then raise exception 'phase502 needs the sale returns table'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, v.module, 'switch', 'false'::jsonb, null, null, null, null, v.lab_bn, v.lab_mix, v.lab_en, v.hint_bn, v.hint_en, v.srt
  from (values
    ('biz_items_net_returns', 'reports',
     'আইটেম বিশ্লেষণে বিক্রি-ফেরত বাদ / Item analysis takes sale returns off: on', 'আইটেম বিশ্লেষণে বিক্রি-ফেরত বাদ / Item analysis takes sale returns off: on', 'Item analysis takes sale returns off: on', 'OFF = the item analysis shows sales before returns (today). ON = the returns of the period are taken off, the same as the returns line of the other reports.', 'OFF = the item analysis shows sales before returns (today). ON = the returns of the period are taken off, the same as the returns line of the other reports.', 5011)
  ) as v(key, module, lab_bn, lab_mix, lab_en, hint_bn, hint_en, srt)
on conflict (key) do nothing;

create or replace function public.biz_items(p_from date, p_to date, p_loc integer default null::integer)
returns table(item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric, cogs numeric, share_pct numeric, cum_pct numeric, abc text)
language plpgsql stable security definer set search_path = public as $function$
declare cost_ok boolean := public.biz_cost_ok();
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with ok as (
    select * from public.sales x
    where x.status = 'done' and x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ln as (
    select case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end qty,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then round((e->>'amount')::numeric * (case when o.subtotal > 0 then o.total / o.subtotal else 1 end), 2) end amt
    from ok o, jsonb_array_elements(case when jsonb_typeof(o.lines) = 'array' then o.lines else '[]'::jsonb end) e),
  -- phase 502: the returns of the period, taken off (negative lines); nothing when the switch is off
  rt as (
    select case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then -(e->>'qty')::numeric end qty,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then -round((e->>'amount')::numeric, 2) end amt
    from public.sale_returns sr, jsonb_array_elements(case when jsonb_typeof(sr.lines) = 'array' then sr.lines else '[]'::jsonb end) e
    where public.rule_on('biz_items_net_returns') and sr.status = 'done'
      and (sr.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
      and (p_loc is null or sr.location_id = p_loc) and sr.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  by_item as (select l.iid, sum(l.qty) q, sum(l.amt) r from (select * from ln union all select * from rt) l where l.iid is not null group by 1),
  tot as (select coalesce(sum(r), 0) t from by_item),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when cost_ok and c.cost_price is not null then coalesce(b.q, 0) * c.cost_price end cg
    from public.items i
    left join by_item b on b.iid = i.id left join (select bc.item_id, bc.cost_price from public._rptb1_biz_item_cost(p_from, p_to, p_loc) bc) c /* bos402 */ on c.item_id = i.id
    where (i.is_active and i.sellable) or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, r.cg, r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $function$;

revoke all on function public.biz_items(date, date, integer) from public, anon;
grant execute on function public.biz_items(date, date, integer) to authenticated;
