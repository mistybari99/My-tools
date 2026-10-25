-- Phase 531 (UNION-3: biz_items and rpt_agg_sql keep the advanced cost source and returns netting (bos112, bos110) and our cost basis (bos402) and returns switch (phase 502)). Paste-twice safe. Earlier phase files are not edited.
-- What: biz_items(date,date,integer): the returns netting of the advanced line (rule items_net_of_returns, bos112, uses the margin report's own lines) is the one that counts; our phase 502
--   netting (rule biz_items_net_returns) is kept but does nothing while the advanced one is on, so a return is never taken off twice. Our cost basis hook (bos402, rule reports_cost_basis =
--   ledger_first) stays; the default basis is the advanced ONE report cost source (bos88). rpt_agg_sql: the advanced set-based cost join (bos110) is used, except when reports_cost_basis =
--   ledger_first (bos402), which keeps our join. Every rule defaults as before; with all rules at their defaults both functions return what the advanced line returned.
-- Paste AFTER phase530 and after phase 505. Same behaviour on a re-paste as phase530.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- biz_items(date,date,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.biz_items(date,date,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.biz_items(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS TABLE(item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric, cogs numeric, share_pct numeric, cum_pct numeric, abc text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cost_ok boolean := public.biz_cost_ok(); locs int[]; nr boolean := coalesce(public.rule_txt('items_net_of_returns'), 'off') = 'on';   -- bos88; bos112: returns netted when the rule is on
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));   -- bos88
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
    where public.rule_on('biz_items_net_returns') and not nr and sr.status = 'done'
      and (sr.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
      and (p_loc is null or sr.location_id = p_loc) and sr.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  by_item0 as (select l.iid, sum(l.qty) q, sum(l.amt) r from (select * from ln union all select * from rt) l where l.iid is not null group by 1),
  rtn as (   -- bos112: what came back (revenue with its discount share, quantity), from the same lines the margin report reads
    select h.item_id iid, sum(h.qty) q, round(sum(h.rev), 2) r from public._cogs_lines72(p_from, p_to, locs) h where nr and h.src = 'return' and h.item_id is not null group by 1),
  by_item as (select coalesce(a.iid, b.iid) iid, coalesce(a.q, 0) - coalesce(b.q, 0) q, coalesce(a.r, 0) - coalesce(b.r, 0) r from by_item0 a full join rtn b on b.iid = a.iid),
  tot as (select coalesce(sum(r), 0) t from by_item),
  cg as (   -- bos14: the count_in_business filter on the typed cost now lives in _cogs_lines72 (cst) and _line_cost88 ; bos88: cost of what was sold from the ONE report source (switch report_cost_source); NULL = some quantity has no known cost (never a silent 0)
    select h.item_id as iid, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as c, sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev) as u   -- bos112: returns subtracted (only present when the rule is on)
      from public._cogs_lines72(p_from, p_to, locs) h where (h.src = 'sale' or nr) and h.item_id is not null group by 1),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when not cost_ok then null
                when b.iid is null then (case when exists (select 1 from public._item_cost_eff88() e where e.item_id = i.id) then 0 end)
                when coalesce(g.u, 0) > 0.004 then null
                else g.c end cg
    from public.items i
    left join by_item b on b.iid = i.id left join cg g on g.iid = i.id left join (select bc.item_id, bc.cost_price from public._rptb1_biz_item_cost(p_from, p_to, p_loc) bc where public._rptb1_cost_basis() = 'ledger_first') c /* bos402: cost basis ledger_first (rule reports_cost_basis), off by default */ on c.item_id = i.id
    where (i.is_active and i.sellable) or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, round(r.cg, 2), r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $function$$r0_0$, null),
  ('public.biz_items(date,date,integer)', 'known', '05fcc50a4a496359af35a0a47ec8ad3f', null),
  ('public.biz_items(date,date,integer)', 'known', '2c0360a871e57cde9d3a7a439d493edc', null),
  ('public.biz_items(date,date,integer)', 'known', '57a0d3939bb344bd291e814966dc62d3', null),
  ('public.biz_items(date,date,integer)', 'known', 'afbe85dd4dbcf5b54944ebeab60f3354', null),
  ('public.biz_items(date,date,integer)', 'old', $o0_0$AS $function$
declare cost_ok boolean := public.biz_cost_ok();
begin$o0_0$, $n0_0$AS $function$
declare cost_ok boolean := public.biz_cost_ok(); locs int[]; nr boolean := coalesce(public.rule_txt('items_net_of_returns'), 'off') = 'on';   -- bos88; bos112: returns netted when the rule is on
begin$n0_0$),
  ('public.biz_items(date,date,integer)', 'old', $o1_0$  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query$o1_0$, $n1_0$  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));   -- bos88
  return query$n1_0$),
  ('public.biz_items(date,date,integer)', 'old', $o2_0$    from public.sale_returns sr, jsonb_array_elements(case when jsonb_typeof(sr.lines) = 'array' then sr.lines else '[]'::jsonb end) e
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
    where (i.is_active and i.sellable) or b.iid is not null),$o2_0$, $n2_0$    from public.sale_returns sr, jsonb_array_elements(case when jsonb_typeof(sr.lines) = 'array' then sr.lines else '[]'::jsonb end) e
    where public.rule_on('biz_items_net_returns') and not nr and sr.status = 'done'
      and (sr.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
      and (p_loc is null or sr.location_id = p_loc) and sr.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  by_item0 as (select l.iid, sum(l.qty) q, sum(l.amt) r from (select * from ln union all select * from rt) l where l.iid is not null group by 1),
  rtn as (   -- bos112: what came back (revenue with its discount share, quantity), from the same lines the margin report reads
    select h.item_id iid, sum(h.qty) q, round(sum(h.rev), 2) r from public._cogs_lines72(p_from, p_to, locs) h where nr and h.src = 'return' and h.item_id is not null group by 1),
  by_item as (select coalesce(a.iid, b.iid) iid, coalesce(a.q, 0) - coalesce(b.q, 0) q, coalesce(a.r, 0) - coalesce(b.r, 0) r from by_item0 a full join rtn b on b.iid = a.iid),
  tot as (select coalesce(sum(r), 0) t from by_item),
  cg as (   -- bos14: the count_in_business filter on the typed cost now lives in _cogs_lines72 (cst) and _line_cost88 ; bos88: cost of what was sold from the ONE report source (switch report_cost_source); NULL = some quantity has no known cost (never a silent 0)
    select h.item_id as iid, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as c, sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev) as u   -- bos112: returns subtracted (only present when the rule is on)
      from public._cogs_lines72(p_from, p_to, locs) h where (h.src = 'sale' or nr) and h.item_id is not null group by 1),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when not cost_ok then null
                when b.iid is null then (case when exists (select 1 from public._item_cost_eff88() e where e.item_id = i.id) then 0 end)
                when coalesce(g.u, 0) > 0.004 then null
                else g.c end cg
    from public.items i
    left join by_item b on b.iid = i.id left join cg g on g.iid = i.id left join (select bc.item_id, bc.cost_price from public._rptb1_biz_item_cost(p_from, p_to, p_loc) bc where public._rptb1_cost_basis() = 'ledger_first') c /* bos402: cost basis ledger_first (rule reports_cost_basis), off by default */ on c.item_id = i.id
    where (i.is_active and i.sellable) or b.iid is not null),$n2_0$),
  ('public.biz_items(date,date,integer)', 'old', $o3_0$    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, r.cg, r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end$o3_0$, $n3_0$    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, round(r.cg, 2), r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end$n3_0$);
-- rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text, p_dexpr text, p_ws integer, p_fym integer, p_mobok boolean, p_nodim boolean, p_withcost boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
  m text; keyq text; costq text; costj text := '';
begin
  if not p_nodim then
    foreach g in array p_gl loop
      for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
        sel := sel || (public.rpt_tok(c ->> 1, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(c ->> 0));
        n := n + 1;
      end loop;
    end loop;
  end if;
  foreach mk in array p_mkeys loop
    ex := case when p_nodim and meas -> mk ? 'tot' then meas -> mk ->> 'tot' else meas -> mk ->> 'expr' end;
    if p_src = 'line' and mk = 'bills' then      -- exact bill count without a slow count(distinct) when the grouping allows it
      if not p_nodim and 'item' = any (p_gl) then ex := 'count(*) filter (where {T}.first_of_item)';
      elsif (p_nodim or not (p_gl && array['item', 'category', 'line_kind'])) and p_where !~ '\.(item_id|category) = any' and coalesce(p_base, '') !~ 'line_kind' then ex := 'count(*) filter (where {T}.line_no = 1)'; end if;
    end if;
    sel := sel || (public.rpt_tok(ex, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(mk));
  end loop;
  if p_withcost and public._rptb1_cost_basis() = 'ledger_first' then
    costj := ' left join public.rpt_line_cost c on c.sale_id = ' || p_al || '.sale_id and c.line_no = ' || p_al || '.line_no';      /* bos402: ledger cost first */
  elsif p_withcost then
    -- bos110: the cost of every (sale, item) pair of the report is computed ONCE, set-based, instead of calling _line_cost88() for every fact row. Same rules, same answer per pair:
    --   ledger cost of the sale's own stock rows when all of them carry a cost (not in item_costs mode), else the list cost (not in ledger_avg mode), else null.
    m := public._rcs88();
    keyq := 'select distinct ' || p_al || '.sale_id as sale_id, ' || p_al || '.item_id as item_id from ' || p_rel || ' ' || p_al || ' where ' || p_where || ' and ' || p_al || '.item_id is not null';
    if m = 'item_costs' then
      costq := format($c$with k as (%s)
        select coalesce(k.sale_id, '00000000-0000-0000-0000-000000000000'::uuid) as sk, k.item_id as item_id, ic.cost_price as cost_price
          from k left join (select x.item_id, x.cost_price from public.item_costs x join public.items i on i.id = x.item_id where i.count_in_business) ic on ic.item_id = k.item_id$c$, keyq);
    else
      costq := format($c$with k as materialized (%s),
        g as (select k.sale_id, k.item_id, count(*) as n, bool_and(coalesce(l.unit_cost, 0) > 0) as allc,
                     coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 0) as lc, coalesce(sum(-l.qty_delta), 0) as lq
                from k join public.stock_ledger l on l.ref_id = k.sale_id::text and l.item_id = k.item_id
               where l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') group by k.sale_id, k.item_id),
        q as (select s.id as sale_id, e->>'item_id' as iid, coalesce(sum(case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end), 0) as q
                from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
               where s.id in (select g.sale_id from g where g.n > 0 and g.allc and g.lq > 0) group by s.id, e->>'item_id')
        select coalesce(k.sale_id, '00000000-0000-0000-0000-000000000000'::uuid) as sk, k.item_id as item_id,
               case when g.n > 0 and g.allc and g.lq > 0 then g.lc / coalesce(nullif(coalesce(q.q, 0), 0), g.lq) else %s end as cost_price
          from k left join g on g.sale_id = k.sale_id and g.item_id = k.item_id
               left join q on q.sale_id = g.sale_id and q.iid = g.item_id::text
               %s$c$, keyq,
        case when m = 'ledger_avg' then 'null::numeric' else 'ic.cost_price' end,
        case when m = 'ledger_avg' then '' else 'left join (select x.item_id, x.cost_price from public.item_costs x join public.items i on i.id = x.item_id where i.count_in_business) ic on ic.item_id = k.item_id' end);
    end if;
    costj := ' left join (' || costq || ') c on c.sk = coalesce(' || p_al || '.sale_id, ''00000000-0000-0000-0000-000000000000''::uuid) and c.item_id = ' || p_al || '.item_id /* bos14 count_in_business filter; bos88: one cost source, see report_cost_source; bos110: set-based */';
  end if;
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al || costj
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');
  if n > 0 and not p_nodim then sql := sql || ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i); end if;
  if p_having is not null and not p_nodim then sql := sql || ' having ' || public.rpt_tok(p_having, p_al, p_dexpr, p_ws, p_fym, p_mobok); end if;
  return sql;
end $function$$r0_0$, null),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'known', '06b6da348b8ac5840947802fcf9449a5', null),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'known', '3ec2d9cb01bd8522fb9d64335a4f4de9', null),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'known', '9f8766108c4745cfe438b6fc5da6f74d', null),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'old', $o0_0$declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
begin$o0_0$, $n0_0$declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
  m text; keyq text; costq text; costj text := '';
begin$n0_0$),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'old', $o1_0$  end loop;
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al
    || case when p_withcost then case when public._rptb1_cost_basis() = 'ledger_first' then ' left join public.rpt_line_cost c on c.sale_id = ' || p_al || '.sale_id and c.line_no = ' || p_al || '.line_no'      /* bos402: ledger cost first */
            else ' left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = ' || p_al || '.item_id' end else '' end
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');$o1_0$, $n1_0$  end loop;
  if p_withcost and public._rptb1_cost_basis() = 'ledger_first' then
    costj := ' left join public.rpt_line_cost c on c.sale_id = ' || p_al || '.sale_id and c.line_no = ' || p_al || '.line_no';      /* bos402: ledger cost first */
  elsif p_withcost then
    -- bos110: the cost of every (sale, item) pair of the report is computed ONCE, set-based, instead of calling _line_cost88() for every fact row. Same rules, same answer per pair:
    --   ledger cost of the sale's own stock rows when all of them carry a cost (not in item_costs mode), else the list cost (not in ledger_avg mode), else null.
    m := public._rcs88();
    keyq := 'select distinct ' || p_al || '.sale_id as sale_id, ' || p_al || '.item_id as item_id from ' || p_rel || ' ' || p_al || ' where ' || p_where || ' and ' || p_al || '.item_id is not null';
    if m = 'item_costs' then
      costq := format($c$with k as (%s)
        select coalesce(k.sale_id, '00000000-0000-0000-0000-000000000000'::uuid) as sk, k.item_id as item_id, ic.cost_price as cost_price
          from k left join (select x.item_id, x.cost_price from public.item_costs x join public.items i on i.id = x.item_id where i.count_in_business) ic on ic.item_id = k.item_id$c$, keyq);
    else
      costq := format($c$with k as materialized (%s),
        g as (select k.sale_id, k.item_id, count(*) as n, bool_and(coalesce(l.unit_cost, 0) > 0) as allc,
                     coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 0) as lc, coalesce(sum(-l.qty_delta), 0) as lq
                from k join public.stock_ledger l on l.ref_id = k.sale_id::text and l.item_id = k.item_id
               where l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') group by k.sale_id, k.item_id),
        q as (select s.id as sale_id, e->>'item_id' as iid, coalesce(sum(case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end), 0) as q
                from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
               where s.id in (select g.sale_id from g where g.n > 0 and g.allc and g.lq > 0) group by s.id, e->>'item_id')
        select coalesce(k.sale_id, '00000000-0000-0000-0000-000000000000'::uuid) as sk, k.item_id as item_id,
               case when g.n > 0 and g.allc and g.lq > 0 then g.lc / coalesce(nullif(coalesce(q.q, 0), 0), g.lq) else %s end as cost_price
          from k left join g on g.sale_id = k.sale_id and g.item_id = k.item_id
               left join q on q.sale_id = g.sale_id and q.iid = g.item_id::text
               %s$c$, keyq,
        case when m = 'ledger_avg' then 'null::numeric' else 'ic.cost_price' end,
        case when m = 'ledger_avg' then '' else 'left join (select x.item_id, x.cost_price from public.item_costs x join public.items i on i.id = x.item_id where i.count_in_business) ic on ic.item_id = k.item_id' end);
    end if;
    costj := ' left join (' || costq || ') c on c.sk = coalesce(' || p_al || '.sale_id, ''00000000-0000-0000-0000-000000000000''::uuid) and c.item_id = ' || p_al || '.item_id /* bos14 count_in_business filter; bos88: one cost source, see report_cost_source; bos110: set-based */';
  end if;
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al || costj
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');$n1_0$);
do $u531$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase531: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase531: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase531: % function(s) changed', nfix;
end $u531$;
drop table if exists _u_plan;
