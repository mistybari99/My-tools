-- OPTIONAL source patches (NOT indexes). Same results, fewer calls. Each is a create-or-replace of the CURRENT final body with one small change.
-- PASTE_ORDER rule: these functions are owned by phase89 / phase98 (_cogs_lines72, _acct_stock_moves85) and phase99 (inbox_list): merge the change into those texts
-- (keep every bosNN tag) rather than pasting this file after phase99/101 as a free-standing phase, or a later re-paste of phase89/98/99 silently undoes it.

-- P1. _cogs_lines72: the one-row CTE rcs (public._rcs88()) was inlined into every use, so rule_txt/rule_val ran ~7 times PER ROW (143k _rcs88 calls for 30 days). AS MATERIALIZED evaluates it once.
--     Tested: 30-day _cogs_lines72 16.0 s -> 2.9 s alone, -> 0.2 s together with index 1 (stock_ledger_refid_idx).
CREATE OR REPLACE FUNCTION public._cogs_lines72(d1 date, d2 date, locs integer[])
 RETURNS TABLE(src text, doc_id uuid, d date, loc integer, item_id uuid, qty numeric, rev numeric, led_cogs numeric, led_rev numeric, fb_cogs numeric, fb_rev numeric, unk_rev numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase80 (free-cost item) and phase88 (one report cost switch)
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  rcs as materialized (select public._rcs88() as m),   -- bos88: the ONE report cost switch (ledger_avg | item_costs | ledger_then_item_costs)
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

-- P2. inbox_list: _inb_contact_ok() and _inb_pii_mode99() were called 4x / 1x per row; now once per place. Output byte-identical (md5 checked). 233 ms -> ~50 ms for 50 rows.
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
    with lo as materialized (select x as id, public._inb_contact_ok(x) as ok from unnest(l) x),   -- bos101: once per place, not four times per row
         pm as materialized (select public._inb_pii_mode99() as m)
    select m.id rid, jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
      'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'has_attachment', m.attachment_ref is not null,
      'handle', case when lo.ok then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when lo.ok then public._inb_pii_f99('name', m.customer_name) end,   /* bos99 */
      'text', case when lo.ok then public._inb_pii_f99('text', left(m.msg_text, 200)) end, 'masked', not lo.ok, 'pii_mode', pm.m) j   /* bos99 */
      from public.inbound_messages m join public.sales_channels c on c.id = m.channel_id join lo on lo.id = m.location_id cross join pm
     where m.location_id = any (l) and (p_status is null or m.status = p_status)
     order by m.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then
    perform public._inb_audit_view('inbound_messages', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$

;

-- P3. _acct_stock_moves85: production / sale issue_out rows can never get a class (cls is null) but were joined and costed first; skip them in the inner WHERE. Output identical (md5 checked with the three acct_* switches on). 322 ms -> 46 ms inside _acct_docs.
CREATE OR REPLACE FUNCTION public._acct_stock_moves85(p_start date)
 RETURNS TABLE(lid bigint, cls text, d date, loc integer, qty numeric, rev boolean, nocost boolean, amt numeric, ikey text, xkey text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cfg as (select public.rule_on('acct_count_adjust') a, public.rule_on('acct_stock_opening') o, public.rule_on('acct_issue_out') i,
                      coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' x, greatest(p_start, coalesce(public._acct_from85(), p_start)) f),
  m as (
    select l.id, l.location_id, l.qty_delta, l.reason = 'reversal' rv, it.item_type, (l.made_at at time zone 'Asia/Dhaka')::date d,
           case coalesce(o.reason, l.reason)
             when 'count_adjust' then 'adjust' when 'opening' then 'opening'
             when 'issue_out' then case when coalesce(o.ref_type, l.ref_type) in ('issue', 'entry') then 'issue' end
             when 'transfer_out' then 'xfer' when 'transfer_in' then 'xfer' end cls,
           case when coalesce(l.unit_cost, 0) > 0 then l.unit_cost
                when l.reason = 'transfer_in' then (select s.unit_cost from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0 order by s.id limit 1) end c
    from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id left join public.stock_ledger o on o.id = l.reverses_id /* bos96 */
    where l.reason in ('count_adjust', 'opening', 'issue_out', 'transfer_out', 'transfer_in', 'reversal')
      and not (l.reason = 'issue_out' and coalesce(l.ref_type, '') not in ('issue', 'entry'))   -- perf: a production / sale issue_out never classifies (cls is null below), skip it before the joins
      and l.made_at >= ((p_start::timestamp at time zone 'Asia/Dhaka') - interval '2 days'))
  select m.id, m.cls, m.d, m.location_id, m.qty_delta, m.rv, m.c is null, round(abs(m.qty_delta) * coalesce(m.c, 0), 2), public._acct_inv_key(m.item_type),
         case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening_equity' when 'issue' then 'stock_issue_use' else 'interloc_clearing' end
  from m cross join cfg
  where m.cls is not null and m.d >= cfg.f
    and not (m.cls = 'opening' and exists (select 1 from public.opening_stock_actions96 a where m.id = any (a.covered_ids) and (a.location_id is null or a.location_id = m.location_id))) /* bos96: an opening that a decision of the opening-stock helper covers is not posted twice */
    and ((m.cls = 'adjust' and cfg.a) or (m.cls = 'opening' and cfg.o) or (m.cls = 'issue' and cfg.i) or (m.cls = 'xfer' and cfg.x))
    and (m.c is null or round(abs(m.qty_delta) * m.c, 2) >= 0.01);
$function$

;

-- P4. _item_cost_eff88 (behind items_with_cost, biz_items): same inlined-CTE defect, public._rcs88() ran once per item (1671 calls for 557 rows). Output md5-identical. items_with_cost 230 ms -> 8 ms together with index 4 (stock_ledger_lastcost_idx).
CREATE OR REPLACE FUNCTION public._item_cost_eff88()
 RETURNS TABLE(item_id uuid, cost_price numeric, src text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with m as materialized (select public._rcs88() as m),
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

-- P5. _rcs88 (called once PER ROW by _line_cost88 from rpt_agg_sql, i.e. 13,176 times for a 30-day item report): two rule_txt() -> rule_val() chains replaced by one rules lookup. Same answer for every setting incl. unknown values (checked).
--     Report engine with cost (report_run item_sales 30 days, under heavy load): 11.9 s -> 2.6 s, output md5-identical. Still ~10x the old speed because the cost is looked up row by row: see the report.
CREATE OR REPLACE FUNCTION public._rcs88()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- same answer as before (rules.value, else default_value; anything unknown = ledger_then_item_costs), one rules lookup instead of two rule_txt() -> rule_val() chains
  select coalesce((select case when x.v in ('ledger_avg', 'item_costs', 'ledger_then_item_costs') then x.v else 'ledger_then_item_costs' end
                     from (select nullif(coalesce(r.value, r.default_value) #>> '{}', '') as v from public.rules r where r.key = 'report_cost_source') x),
                  'ledger_then_item_costs') $function$
;
