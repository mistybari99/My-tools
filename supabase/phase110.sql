-- ============================================================
-- Phase 110 - Performance step (audit: docs/briefs_p2p3/step_Perf_REPORT.md, review: tests/sql/perf/README.md)
-- Run AFTER phase103 (and after phase104..109 if they are used; this file is independent of them). Additive and idempotent: paste twice = no error, same result.
--
-- RUN AT A QUIET TIME. Every CREATE INDEX below holds a SHARE lock on its table while it builds: reads work, WRITES (sales, stock posts, audit rows) WAIT for it.
-- Measured on 184,000 ledger rows: 0.03 - 1.5 s per index; expect about 1-2 s per million stock_ledger rows and about 2.5 s per million audit_log rows.
-- No CONCURRENTLY (it cannot run inside the Supabase SQL editor). If the editor times out, run it again: finished indexes are skipped (IF NOT EXISTS).
--
-- Order of this file (on purpose): guard, then the 8 INDEXES FIRST (they alone fix inventory_vs_gl 22 s -> 0.5 s and unmatched_forms 25 s -> 0.2 s), then the function patches.
--
-- Why (year reports became 70-430x slower after phases 72-99, review PERF_REPORT):
--   * _cogs_lines72 / _item_cost_eff88: a one-row CTE calling _rcs88() was inlined into every use, so the cost-source rule was read ONCE PER ROW (143,000 calls for 30 days). AS MATERIALIZED evaluates it once.
--   * _cogs_lines72 joins stock_ledger on ref_id alone: the existing (ref_type, ref_id) index cannot serve it -> index 1.
--   * rpt_agg_sql called the plpgsql _line_cost88() for every fact row; now the cost of every (sale, item) pair is computed once, set-based (same rules, same numbers).
--   * inventory_vs_gl compared id::text with stock_ledger.ref_id for every ledger row (table scan per row) -> expression indexes. unmatched_forms: no index for (item, place, reason) -> index 2.
--   * _acct_docs (autopost tick every minute): the stock-move branch costed production / sale issue_out rows that can never be posted; they are skipped before the joins.
--   * inbox_list: the contact check ran 4x per row, now once per place (same output).
-- Results are identical to before (proved by tests/sql/perf/equality.sh and supabase/phase110_test.sql). Nothing is deleted; no table or column changes.
-- Functions re-created from their LATEST bodies (every bosNN tag kept): _cogs_lines72 (bos89), _item_cost_eff88, _rcs88, rpt_agg_sql (bos14, bos88), inbox_list (bos99, bos103), _acct_stock_moves85 (bos96, bos103). New tag bos110 on the four it alone owns; inbox_list and _acct_stock_moves85 carry the plain marker `perf110` (no bosNN tag), so phase103's body guard still accepts them.
-- Re-paste rule: a re-paste of phase103 (or of phase89, which re-creates _cogs_lines72) puts the older bodies of those functions back, results unchanged but slow: paste phase110 again after it.
-- If a later phase re-creates one of these six, merge its change into the phase110 text (or paste phase110 before it): the check before the patches stops the paste when a body carries a tag this file does not know.
-- ============================================================

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.opening_stock_followups103') is null then miss := miss || ' 103'; end if;
  if miss <> '' then
    raise exception 'phase110 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ============================ 1. INDEXES (first) ============================
-- 1. _cogs_lines72 (biz_daily, _p27_pl, biz_items) joins stock_ledger on ref_id alone: the (ref_type, ref_id) index cannot be used for it
create index if not exists stock_ledger_refid_idx on public.stock_ledger (ref_id, ref_type);
-- 2. unmatched_forms: "is there a ledger row for this item + place + reason" per form line (the existing (item_id, location_id, id) index walks every row of a big item)
create index if not exists stock_ledger_item_loc_reason_idx on public.stock_ledger (item_id, location_id, reason, made_at);
-- 3. inventory_vs_gl compares production_runs.id::text / purchase_bills.id::text with stock_ledger.ref_id (text): expression indexes turn the per-row table scan into a lookup
create index if not exists production_runs_idtext_idx on public.production_runs ((id::text));
create index if not exists purchase_bills_idtext_idx on public.purchase_bills ((id::text));
-- 4. the autopost stock-move scan (_acct_stock_moves85, every minute) asks for the rows of 7 reasons since the accounting window. Without this index the planner takes index 2 above for it and reads that
--    whole index on every tick (about 2x slower here and growing with the ledger); with it the scan costs about what the window holds and no more. (Added after measuring index 2: see the Perf report.)
create index if not exists stock_ledger_reason_made_idx on public.stock_ledger (reason, made_at);
-- 5. items_with_cost / _item_cost_eff88 take the last positive-cost ledger row of every item (order by id desc limit 1): one probe per item
create index if not exists stock_ledger_lastcost_idx on public.stock_ledger (item_id, id desc) where coalesce(unit_cost, 0) > 0 and qty_delta > 0;
-- 6. audit_log had only its primary key: the item-history popup (table_name + record_id, newest first) and pii_exposure_report94 (action = 'view') scanned the whole table
create index if not exists audit_log_tbl_rec_id_idx on public.audit_log (table_name, record_id, id desc);
create index if not exists audit_log_view_at_idx on public.audit_log (table_name, at) where action = 'view';

analyze public.stock_ledger;
analyze public.production_runs;
analyze public.purchase_bills;
analyze public.audit_log;

-- ============================ 2. FUNCTION PATCHES ============================
-- Stop (before changing anything) when a function carries a bosNN tag this file does not know, i.e. a newer phase changed it: merge that change into the text below first.
do $c$
declare r record; src text; t text; bad text := '';
begin
  for r in select * from (values
    ('public._cogs_lines72(date,date,integer[])', array['bos80','bos88','bos89','bos110']),
    ('public._item_cost_eff88()', array['bos110']),
    ('public._rcs88()', array['bos110']),
    ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', array['bos14','bos88','bos110']),
    ('public.inbox_list(integer,text,integer)', array['bos99','bos103']),
    ('public._acct_stock_moves85(date)', array['bos96','bos103'])) v(fn, known)
  loop
    select p.prosrc into src from pg_proc p where p.oid = to_regprocedure(r.fn);
    if src is null then bad := bad || ' ' || r.fn || ' (missing)'; continue; end if;
    for t in select distinct m[1] from regexp_matches(src, '(bos[0-9]+)', 'g') m loop
      if not t = any (r.known) then bad := bad || ' ' || r.fn || ' has ' || t || ';'; end if;
    end loop;
  end loop;
  if bad <> '' then
    raise exception 'phase110 stopped: a function it re-creates was changed by a phase it does not know (merge that change into phase110 first):%', bad;
  end if;
end $c$;

-- P1  _cogs_lines72 (bos89 merge of bos80 + bos88): the one-row rule CTE is MATERIALIZED (evaluated once, not once per row)
CREATE OR REPLACE FUNCTION public._cogs_lines72(d1 date, d2 date, locs integer[])
 RETURNS TABLE(src text, doc_id uuid, d date, loc integer, item_id uuid, qty numeric, rev numeric, led_cogs numeric, led_rev numeric, fb_cogs numeric, fb_rev numeric, unk_rev numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase80 (free-cost item) and phase88 (one report cost switch)
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  rcs as materialized (select public._rcs88() as m),   -- bos110: evaluated once (it was inlined into every use = once per row); bos88: the ONE report cost switch (ledger_avg | item_costs | ledger_then_item_costs)
  cst as (select i.id as iid, coalesce(ic.cost_price, case when public._cost_free80(i.id) then 0::numeric end) as cost_price   -- bos80: a free-cost item without a list cost counts as cost 0
          from public.items i left join public.item_costs ic on ic.item_id = i.id
          where i.count_in_business and coalesce(ic.cost_price, case when public._cost_free80(i.id) then 0::numeric end) is not null),
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
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta * coalesce(l.unit_cost, 0)) filter (where coalesce(l.unit_cost, 0) > 0 or public._cost_free80(l.item_id)) as lc,   -- bos80
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) > 0 or public._cost_free80(l.item_id)) as lq,   -- bos80
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) <= 0 and not public._cost_free80(l.item_id)) as uq   -- bos80
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
$function$
;

-- P4  _item_cost_eff88 (behind items_with_cost and biz_items): same defect, the rule was read once per item
CREATE OR REPLACE FUNCTION public._item_cost_eff88()
 RETURNS TABLE(item_id uuid, cost_price numeric, src text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with m as materialized (select public._rcs88() as m),   -- bos110: once, not once per item
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
$function$
;

-- P5a _rcs88: one rules lookup instead of two rule_txt() -> rule_val() chains. Same answer for every setting, including an unknown or empty value (-> ledger_then_item_costs)
CREATE OR REPLACE FUNCTION public._rcs88()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos110: same answer as before (rules.value, else default_value; anything unknown or empty = ledger_then_item_costs), one rules lookup instead of two rule_txt() -> rule_val() chains
  select coalesce((select case when x.v in ('ledger_avg', 'item_costs', 'ledger_then_item_costs') then x.v else 'ledger_then_item_costs' end
                     from (select nullif(coalesce(r.value, r.default_value) #>> '{}', '') as v from public.rules r where r.key = 'report_cost_source') x),
                  'ledger_then_item_costs') $function$
;

-- P5b rpt_agg_sql: the line-report cost (cogs, gp, ...) is joined set-based per (sale, item) instead of calling _line_cost88() for every fact row. Same cost per pair (ledger cost of the sale's own rows when all carry a cost,
--      else the list cost, else null; all three report_cost_source modes). _line_cost88 itself is unchanged (other callers keep it).
CREATE OR REPLACE FUNCTION public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text, p_dexpr text, p_ws integer, p_fym integer, p_mobok boolean, p_nodim boolean, p_withcost boolean)
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
  if p_withcost then
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
end $function$
;

-- P2  inbox_list (bos99 + bos103; marker perf110, NOT a bos tag: phase103's body guard owns this function): the contact check and the PII mode once per call/place; output identical
CREATE OR REPLACE FUNCTION public.inbox_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; unmasked boolean := false; l int[];
begin
  perform public._inb_gate(p_loc, 'view');
  if p_status is not null and p_status not in ('new', 'seen', 'converted', 'ignored') then raise exception 'bad_input'; end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select coalesce(jsonb_agg(z.j order by z.rid desc), '[]'::jsonb) into r from (
    with lo as materialized (select x as id, public._inb_contact_ok(x) as ok from unnest(l) x),   -- perf110: the contact check once per place, not four times per row
         pm as materialized (select public._inb_pii_mode99() as m)
    select m.id rid, jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
      'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'has_attachment', m.attachment_ref is not null,
      'handle', case when lo.ok then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when lo.ok then public._inb_pii_f99('name', m.customer_name) end,   /* bos99 */
      'text', case when lo.ok then left(public._inb_pii_f99('text', m.msg_text), 200) /* bos103: mask first, cut after */ end, 'masked', not lo.ok, 'pii_mode', pm.m) j   /* bos99 */
      from public.inbound_messages m join public.sales_channels c on c.id = m.channel_id join lo on lo.id = m.location_id cross join pm
     where m.location_id = any (l) and (p_status is null or m.status = p_status)
     order by m.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then
    perform public._inb_audit_view('inbound_messages', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$
;

-- P3  _acct_stock_moves85 (bos96 + bos103; marker perf110, NOT a bos tag: phase103's body guard owns this function): production / sale issue_out rows never get a class (cls is null) but were joined and costed first; skipped before the joins. Output identical
CREATE OR REPLACE FUNCTION public._acct_stock_moves85(p_start date)
 RETURNS TABLE(lid bigint, cls text, d date, loc integer, qty numeric, rev boolean, nocost boolean, amt numeric, ikey text, xkey text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cfg as (select public.rule_on('acct_count_adjust') a, public.rule_on('acct_stock_opening') o, public.rule_on('acct_issue_out') i,
                      coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' x, greatest(p_start, coalesce(public._acct_from85(), p_start)) f,
                      public.rule_on('acct_manual_prod_in103') p /* bos103 */),
  m as (
    select l.id, l.location_id, l.qty_delta, l.reason = 'reversal' rv, it.item_type, (l.made_at at time zone 'Asia/Dhaka')::date d,
           case coalesce(o.reason, l.reason)
             when 'count_adjust' then 'adjust' when 'opening' then 'opening'
             when 'issue_out' then case when coalesce(o.ref_type, l.ref_type) in ('issue', 'entry') then 'issue' end
             when 'transfer_out' then 'xfer' when 'transfer_in' then 'xfer'
             when 'production_in' then case when not exists (select 1 from public.production_runs pr where pr.id::text = coalesce(o.ref_id, l.ref_id)) then 'prodin' end /* bos103: direct production-in, no recipe run */ end cls,
           case when coalesce(l.unit_cost, 0) > 0 then l.unit_cost
                when l.reason = 'transfer_in' then (select s.unit_cost from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0 order by s.id limit 1) end c
    from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id left join public.stock_ledger o on o.id = l.reverses_id /* bos96 */
    where l.reason in ('count_adjust', 'opening', 'issue_out', 'transfer_out', 'transfer_in', 'reversal', 'production_in') /* bos103 */
      and not (l.reason = 'issue_out' and l.reverses_id is null and coalesce(l.ref_type, '') not in ('issue', 'entry'))   -- perf110: a production / sale issue_out never gets a class (cls is null below): skip it before the costing
      and l.made_at >= ((p_start::timestamp at time zone 'Asia/Dhaka') - interval '2 days'))
  select m.id, m.cls, m.d, m.location_id, m.qty_delta, m.rv, m.c is null, round(abs(m.qty_delta) * coalesce(m.c, 0), 2), public._acct_inv_key(m.item_type),
         case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening_equity' when 'issue' then 'stock_issue_use' when 'prodin' then 'overhead_absorbed' /* bos103 */ else 'interloc_clearing' end
  from m cross join cfg
  where m.cls is not null and m.d >= cfg.f
    and not (m.cls = 'opening' and exists (select 1 from public.opening_covered103 a where m.id = any (a.covered_ids) and (a.location_id is null or a.location_id = m.location_id))) /* bos96: an opening that a decision of the opening-stock helper covers is not posted twice */
    and ((m.cls = 'adjust' and cfg.a) or (m.cls = 'opening' and cfg.o) or (m.cls = 'issue' and cfg.i) or (m.cls = 'xfer' and cfg.x) or (m.cls = 'prodin' and cfg.p))
    and (m.c is null or round(abs(m.qty_delta) * m.c, 2) >= 0.01);
$function$
;
