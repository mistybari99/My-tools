-- ============================================================
-- Phase 88 (bos88) - STEP R: ONE cost source for every report (audit a1-F6, a2-F5, a3-F1).
--   Needs phases 72..79, 82, 83, 84 pasted first. Additive, paste-twice safe: one rule, helper functions, create or replace only. No table, no data change.
--
--   Problem: the journal COGS is the stock-ledger unit_cost (weighted average), and since phase72 biz_daily / _p27_pl / l1 / l2 / l3 / brand_pnl / partner bases use that
--   cost first. But biz_items, the report builder (rpt_meas "cogs / gp / gp_pct" through rpt_agg_sql) and items_with_cost still read the hand-typed item_costs.
--   So one product showed one cost on one screen and another cost on the next.
--
--   Switch  report_cost_source  (owner rule, kind choice):
--     ledger_then_item_costs  DEFAULT. Stock-ledger cost of the units sold; item_costs only for quantity whose ledger cost is blank or 0 (shown as an estimate).
--                             This is what biz_daily / _p27_pl already did, so the main P&L numbers are unchanged. biz_items, the report builder and
--                             items_with_cost now follow it too (they read item_costs only before).
--     ledger_avg              Only the stock ledger. Anything without a ledger cost is UNKNOWN (never replaced by a typed cost).
--     item_costs              Only the hand-typed cost (the old behaviour of biz_items / report builder). The ledger is ignored by the reports.
--   The journal (GL) COGS always comes from the ledger: it is NOT switched. profit_source_check shows report vs journal.
--   Unknown cost is NEVER 0: biz_items cogs is NULL when part of an item's sales has no cost (revenue of that part = unknown_cost_rev in biz_daily /
--   biz_items_cost88), the report builder cogs stays blank (uncosted_pct / costed_net say how much), items_with_cost has no row for an item without a cost
--   (item_cost_status88 lists it with cost_missing = true).
--   Re-created (latest definition, only bos88 lines changed): _cogs_lines72 (so biz_daily, _p27_pl, l1/l2/l3, brand_pnl, partner base, profit_source_check,
--   acct_income_statement follow the switch), biz_items, items_with_cost, rpt_agg_sql. New: _rcs88, _item_cost_eff88, _line_cost88 (closed), item_cost_status88,
--   biz_items_cost88 (cost-grant holders only).
--   Cost secrecy / RLS / grants: unchanged. Cost columns only for biz_cost_ok() / view_cost holders; new internals are closed to the browser.
--   Other bosNN tags inside the re-created bodies (bos14 count_in_business filter, bos72 return share) are kept.
-- ============================================================

do $g$ begin
  if to_regprocedure('public._cogs_lines72(date, date, int[])') is null          -- 72
     or to_regprocedure('public._recipe_gate73(uuid)') is null                    -- 73
     or to_regprocedure('public._conv_cost(uuid, integer, numeric, numeric, date, text)') is null   -- 74
     or to_regprocedure('public._cs_alloc(bigint)') is null                       -- 75
     or to_regprocedure('public._inb_audit76()') is null                          -- 76
     or to_regprocedure('public._oo_flag_ro77()') is null                         -- 77
     or to_regprocedure('public._c78_rows(date, date)') is null                   -- 78
     or position('bos72' in pg_get_functiondef('public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)'::regprocedure)) = 0   -- 79
     or to_regprocedure('public._items_unit_conv82()') is null                -- 82
     or to_regprocedure('public._transit_loss83(uuid, numeric, text)') is null                       -- 83
     or to_regprocedure('public._aud84()') is null then                           -- 84
    raise exception 'phase88 needs phases 72..79, 82, 83 and 84 pasted first';
  end if;
end $g$;

-- ---------- the switch ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('report_cost_source', 'stock', 'choice', '"ledger_then_item_costs"', '["ledger_avg","item_costs","ledger_then_item_costs"]', null, null,
  'রিপোর্টে পণ্যের খরচ কোথা থেকে: স্টক খাতার গড় / হাতে লেখা খরচ / আগে স্টক খাতা, না থাকলে হাতে লেখা', 'Report এ product cost কোথা থেকে: ledger average / হাতে লেখা item cost / আগে ledger, না থাকলে item cost', 'Where every report takes the product cost from: stock-ledger average, typed item cost, or ledger first then typed item cost',
  'ledger_then_item_costs (default) = the cost the journal uses, typed item cost only where the ledger has none (marked as estimate). ledger_avg = ledger only, no ledger cost = unknown. item_costs = typed cost only. The journal itself always uses the ledger.', 195)
on conflict (key) do nothing;

-- the effective switch value (anything unknown falls back to the default)
create or replace function public._rcs88() returns text language sql stable security definer set search_path = public as $$
  select case when public.rule_txt('report_cost_source') in ('ledger_avg', 'item_costs', 'ledger_then_item_costs') then public.rule_txt('report_cost_source') else 'ledger_then_item_costs' end $$;
revoke all on function public._rcs88() from public, anon, authenticated;

-- effective CURRENT cost per item under the switch. ledger = quantity-weighted average of the stock balances (the same average the next issue would take);
-- an item with no known cost has no row.
create or replace function public._item_cost_eff88() returns table(item_id uuid, cost_price numeric, src text) language sql stable security definer set search_path = public as $$
  with m as (select public._rcs88() as m),
  lg as (
    select b.item_id as iid,
           coalesce(sum(b.qty * b.avg_cost) filter (where b.qty > 0 and coalesce(b.avg_cost, 0) > 0) / nullif(sum(b.qty) filter (where b.qty > 0 and coalesce(b.avg_cost, 0) > 0), 0),
                    (select l.unit_cost from public.stock_ledger l where l.item_id = b.item_id and coalesce(l.unit_cost, 0) > 0 and l.qty_delta > 0 order by l.id desc limit 1)) as c
    from public.stock_balance b group by b.item_id),
  ic as (select x.item_id as iid, x.cost_price as c from public.item_costs x where x.cost_price is not null)
  select z.iid, z.cp, z.s from (
    select coalesce(lg.iid, ic.iid) as iid,
           case m.m when 'item_costs' then ic.c when 'ledger_avg' then lg.c else coalesce(lg.c, ic.c) end as cp,
           case m.m when 'item_costs' then 'item_costs' when 'ledger_avg' then 'ledger' else (case when lg.c is not null then 'ledger' else 'item_costs' end) end as s
    from lg full join ic on ic.iid = lg.iid cross join m) z
  where z.cp is not null;
$$;
revoke all on function public._item_cost_eff88() from public, anon, authenticated;

-- cost per unit of ONE sale line for the report builder. Ledger: the cost the journal booked for that sale and item / the units on the sale lines
-- (so qty x cost = the journal figure); only when EVERY ledger row of that sale+item has a cost > 0. item_costs: the typed cost (count_in_business items).
-- NULL = unknown.
create or replace function public._line_cost88(p_sale uuid, p_item uuid) returns numeric language plpgsql stable security definer set search_path = public as $$
declare m text := public._rcs88(); lc numeric; lq numeric; allc boolean; n int; q numeric; v numeric;
begin
  if p_item is null then return null; end if;
  if m <> 'item_costs' and p_sale is not null then
    select count(*), bool_and(coalesce(l.unit_cost, 0) > 0), coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 0), coalesce(sum(-l.qty_delta), 0) into n, allc, lc, lq
    from public.stock_ledger l where l.ref_type in ('sale', 'sale_pack') and l.ref_id = p_sale::text and l.item_id = p_item and l.reason in ('sale_out', 'issue_out');
    if n > 0 and allc and lq > 0 then
      select coalesce(sum(case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end), 0) into q
      from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
      where s.id = p_sale and e->>'item_id' = p_item::text;
      return lc / coalesce(nullif(q, 0), lq);
    end if;
  end if;
  if m <> 'ledger_avg' then
    select ic.cost_price into v from public.item_costs ic join public.items i on i.id = ic.item_id where ic.item_id = p_item and i.count_in_business;
    return v;
  end if;
  return null;
end $$;
revoke all on function public._line_cost88(uuid, uuid) from public, anon, authenticated;

-- ---------- re-created from the latest definitions (bos88 lines only) ----------
CREATE OR REPLACE FUNCTION public._cogs_lines72(d1 date, d2 date, locs integer[])
 RETURNS TABLE(src text, doc_id uuid, d date, loc integer, item_id uuid, qty numeric, rev numeric, led_cogs numeric, led_rev numeric, fb_cogs numeric, fb_rev numeric, unk_rev numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  rcs as (select public._rcs88() as m),   -- bos88: the ONE report cost switch (ledger_avg | item_costs | ledger_then_item_costs)
  cst as (select ic.item_id as iid, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  docs as (
    select 'sale'::text as src, x.id as doc, x.sale_date as d, x.location_id as loc, (case when x.subtotal > 0 then x.total / x.subtotal else 1 end) as f, x.lines
    from public.sales x where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)
    union all
    select 'return'::text, r.id, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, (case when la.s > 0 then r.amount / la.s else 1 end), r.lines
    from public.sale_returns r cross join net_on
    cross join lateral (select coalesce(sum(case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end), 0) as s
                        from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e) la
    where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  ln as (
    select docs.src, docs.doc,
           coalesce(case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end, '00000000-0000-0000-0000-000000000000'::uuid) as k,
           coalesce(sum(case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end * docs.f), 0) as rev,
           coalesce(sum(case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end), 0) as qty
    from docs cross join lateral jsonb_array_elements(case when jsonb_typeof(docs.lines) = 'array' then docs.lines else '[]'::jsonb end) e group by 1, 2, 3),
  led as (
    select docs.src, docs.doc, l.item_id as k,
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta * l.unit_cost) filter (where coalesce(l.unit_cost, 0) > 0) as lc,
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) > 0) as lq,
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) <= 0) as uq
    from public.stock_ledger l
    join docs on l.ref_id = docs.doc::text
             and ((docs.src = 'sale' and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out'))
               or (docs.src = 'return' and l.ref_type = 'sale_return' and l.reason = 'sale_return'))
    group by 1, 2, 3),
  keys as (select src, doc, k from ln union select src, doc, k from led),
  j as (
    select docs.src, docs.doc, docs.d, docs.loc, keys.k, coalesce(ln.qty, 0) as jq, coalesce(ln.rev, 0) as rev,
           case when rcs.m = 'item_costs' then 0 else coalesce(led.lc, 0) end as lc, case when rcs.m = 'item_costs' then 0 else coalesce(led.lq, 0) end as lq,
           case when rcs.m = 'item_costs' then 0 else coalesce(led.uq, 0) end as uq, ((led.lq is not null or led.uq is not null) and rcs.m <> 'item_costs') as hl,
           (case when rcs.m = 'ledger_avg' then null else c.cost_price end) as cost_price, rcs.m as m   -- bos88
    from keys join docs on docs.src = keys.src and docs.doc = keys.doc cross join rcs
    left join ln on ln.src = keys.src and ln.doc = keys.doc and ln.k = keys.k
    left join led on led.src = keys.src and led.doc = keys.doc and led.k = keys.k
    left join cst c on c.iid = keys.k),
  q as (select j.*, (case when hl then uq else jq end) as unk_q, (case when hl then lq + uq else jq end) as tot_q from j),
  w as (select q.*, (case when tot_q > 0 then rev * lq / tot_q else 0 end) as lrev from q)
  select w.src, w.doc, w.d, w.loc, nullif(w.k, '00000000-0000-0000-0000-000000000000'::uuid), w.jq, w.rev,
         w.lc + (case when w.m = 'item_costs' and w.cost_price is not null then w.unk_q * w.cost_price else 0 end),   -- bos88: item_costs mode = item_costs IS the primary source (no fallback flag)
         w.lrev + (case when w.m = 'item_costs' and w.cost_price is not null then w.rev - w.lrev else 0 end),
         (case when w.m <> 'item_costs' and w.cost_price is not null then w.unk_q * w.cost_price else 0 end),
         (case when w.m <> 'item_costs' and w.cost_price is not null then w.rev - w.lrev else 0 end),
         (case when w.cost_price is null then w.rev - w.lrev else 0 end)
  from w;
$function$;

CREATE OR REPLACE FUNCTION public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text, p_dexpr text, p_ws integer, p_fym integer, p_mobok boolean, p_nodim boolean, p_withcost boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
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
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al
    || case when p_withcost then ' left join lateral (select public._line_cost88(' || p_al || '.sale_id, ' || p_al || '.item_id) as cost_price) c on true /* bos14 count_in_business filter lives in _line_cost88 ; bos88: one cost source, see report_cost_source */' else '' end
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');
  if n > 0 and not p_nodim then sql := sql || ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i); end if;
  if p_having is not null and not p_nodim then sql := sql || ' having ' || public.rpt_tok(p_having, p_al, p_dexpr, p_ws, p_fym, p_mobok); end if;
  return sql;
end $function$;

CREATE OR REPLACE FUNCTION public.biz_items(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS TABLE(item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric, cogs numeric, share_pct numeric, cum_pct numeric, abc text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cost_ok boolean := public.biz_cost_ok(); locs int[];   -- bos88
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
  by_item as (select l.iid, sum(l.qty) q, sum(l.amt) r from ln l where l.iid is not null group by 1),
  tot as (select coalesce(sum(r), 0) t from by_item),
  cg as (   -- bos14: the count_in_business filter on the typed cost now lives in _cogs_lines72 (cst) and _line_cost88 ; bos88: cost of what was sold from the ONE report source (switch report_cost_source); NULL = some quantity has no known cost (never a silent 0)
    select h.item_id as iid, sum(h.led_cogs + h.fb_cogs) as c, sum(h.unk_rev) as u from public._cogs_lines72(p_from, p_to, locs) h where h.src = 'sale' and h.item_id is not null group by 1),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when not cost_ok then null
                when b.iid is null then (case when exists (select 1 from public._item_cost_eff88() e where e.item_id = i.id) then 0 end)
                when coalesce(g.u, 0) > 0.004 then null
                else g.c end cg
    from public.items i
    left join by_item b on b.iid = i.id left join cg g on g.iid = i.id
    where (i.is_active and i.sellable) or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, round(r.cg, 2), r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $function$;

CREATE OR REPLACE FUNCTION public.items_with_cost()
 RETURNS TABLE(item_id uuid, cost_price numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.item_id, c.cost_price from public._item_cost_eff88() c   -- bos88: the effective cost of the ONE source (report_cost_source); an item with no known cost has NO row = unknown, never 0
  -- a location-scoped personal view_cost grant counts too (the list is company wide, so any location grant is enough; role grants and the owner as before)
  where public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$function$;

-- ---------- new read-only reports (cost-grant holders only) ----------
-- every active counted item with its effective cost, the source and cost_missing (true = no cost known: show "unknown", never 0)
create or replace function public.item_cost_status88() returns table(item_id uuid, code text, cost_price numeric, source text, cost_missing boolean)
language sql stable security definer set search_path = public as $$
  select i.id, i.code, e.cost_price, coalesce(e.src, 'none'), e.cost_price is null
  from public.items i left join public._item_cost_eff88() e on e.item_id = i.id
  where i.is_active and i.count_in_business and public.is_active()
    and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
         or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())))
  order by i.code;
$$;
revoke all on function public.item_cost_status88() from public, anon;
grant execute on function public.item_cost_status88() to authenticated;

-- per sold item: cost of what was sold under the switch, the part that is an estimate (typed cost used as fallback), the revenue with NO known cost, cost_missing
create or replace function public.biz_items_cost88(p_from date, p_to date, p_loc int default null)
returns table(item_id uuid, cogs numeric, fallback_cogs numeric, unknown_cost_rev numeric, cost_missing boolean)
language plpgsql stable security definer set search_path = public as $$
declare locs int[];
begin
  if not public.biz_ok() or not public.biz_cost_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));
  return query
    select h.item_id, round(sum(h.led_cogs + h.fb_cogs), 2), round(sum(h.fb_cogs), 2), round(sum(h.unk_rev), 2), sum(h.unk_rev) > 0.004
    from public._cogs_lines72(p_from, p_to, locs) h where h.src = 'sale' and h.item_id is not null group by h.item_id;
end $$;
revoke all on function public.biz_items_cost88(date, date, int) from public, anon;
grant execute on function public.biz_items_cost88(date, date, int) to authenticated;
