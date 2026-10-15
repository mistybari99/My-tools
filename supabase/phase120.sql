-- ============================================================
-- Phase 120 (bos120) - STEP C4: performance of the phase112..118 reports (review on a scratch copy at the owner's size, report in the C4 hand-over)
-- Run AFTER phase118 (it rewrites three functions of phase118). Additive and idempotent: paste twice = no error, same result. Whole file = one transaction: if a guard refuses, nothing changes.
--
-- Measured on 1,369 items / 229 categories / 329,000 stock_ledger rows / 50,500 sales over 2 years / 6,000 transfers / 6,000 production runs
-- (tests/sql/perf/seed.sql + seed_c4.sql), default work_mem 4 MB, 1 month = 30 days, best of 6 warm runs on a quiet box (on a loaded box the old times were 1.5x worse):
--                                    1 day            1 month          1 year          (before -> after)
--   stock_recon_statement            1.81 -> 0.46 s   2.14 -> 0.51 s   6.02 -> 2.24 s
--   factory_branch_statement         2.05 -> 0.54 s   2.28 -> 0.59 s   3.00 -> 0.74 s
--   stock_sales_unmatched            0.02 -> 0.01 s   0.31 -> 0.09 s   6.42 -> 1.55 s
-- Results are IDENTICAL: md5 of 621 outputs (periods x places x items x categories, incl. the internal buckets / gap functions) equal before and after on the 329k-row database
-- (tests/sql/perf/equality120.sh); the fixtures of supabase/phase120_test.sql give the same md5 for the phase118 bodies and these bodies on 1,116 cases and check the hand numbers.
--
-- What was slow, and the fix (each is a CREATE OR REPLACE of a phase118 function, same signature, same output, tag bos120 added next to bos118):
--   R1 _rc118_buckets  (under stock_recon_statement AND factory_branch_statement): every call read the whole ledger through 1,369 item-by-item bitmap scans, sorted 329k rows on disk and
--      ran 15 FILTER aggregates over every row. Now one pass, rows summed once per (place, item, period part, bucket) in a hash aggregate, the 15 columns read from those few sums; a reversal
--      row looks up its original only when it is a reversal; rows far from the period edges skip the time-zone conversion; the "returned to the sender" test is one hashed set of
--      transfer ids. The function carries SET work_mem = '64MB' and jit = off (the 4 MB default made the planner sort on disk; the 64 MB is used only while the call runs).
--   R2 _rc118_gap  (under stock_sales_unmatched and the summary of stock_recon_statement): _base_qty() (plpgsql, two lookups) was called twice for every sales line (186k calls for a year).
--      Now the unit factor is taken once per distinct (item, unit) pair (about 1,000) and multiplied: _base_qty(i, q, u) = q * _base_qty(i, 1, u), or NULL when the factor is unknown.
--      The item join (tracked flag) is done on those pairs too. Same SET work_mem / jit.
--   R3 stock_sales_unmatched: the list and the counts came from two separate runs of _rc118_gap; now one run (materialized) feeds both.
--
-- Indexes: NONE shipped. Tested and rejected (no measurable gain on this data; each measured on the real functions, then dropped): stock_transfers (item_id, from_location_id, to_location_id,
--   sent_at) for the "return" test; stock_ledger (ref_id) WHERE ref_type = 'transfer' AND reason = 'transfer_out' AND reverses_id IS NULL for the transfer cost lookup. The remaining time of the
--   year views of net_profit_report / profit_truth112 (5-7 s) is two runs of the phase110 function _cogs_lines72 (2.9 s each for 31,000 sales); that is an OLD function and is not touched here.
--
-- Re-paste rule: a re-paste of phase118 puts the older (slower, same result) bodies of these three functions back: paste phase120 again after it.
-- If a later phase re-creates one of the three, merge its change into the text below first: the check before the rewrites stops the paste when a body carries a tag this file does not know.
-- ============================================================
begin;

-- ============================ 0. GUARD ============================
do $g$
declare miss text := ''; m record; src text; t text; bad text := '';
begin
  for m in select * from (values
    ('118', 'public._rc118_buckets(date,date,integer[],uuid,text)'), ('118', 'public._rc118_gap(date,date,integer[],uuid)'), ('118', 'public._rc118_gap_summary(date,date,integer[],uuid)'),
    ('118', 'public._rc118_locs(text,integer)'), ('118', 'public.stock_sales_unmatched(date,date,integer,uuid,integer)'),
    ('118', 'public.stock_recon_statement(date,date,integer,uuid,text,integer)'), ('118', 'public.factory_branch_statement(date,date,integer,uuid,text,integer)'),
    ('82', 'public._base_qty(uuid,numeric,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null and position(' ' || m.ph in miss) = 0 then miss := miss || ' ' || m.ph; end if;
  end loop;
  if miss <> '' then
    raise exception 'phase120 needs phase118 (and 72..103) pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  -- stop when one of the three functions was changed by a phase this file does not know (merge that change into the text below first)
  for m in select * from (values
    ('public._rc118_buckets(date,date,integer[],uuid,text)', array['bos118','bos120']),
    ('public._rc118_gap(date,date,integer[],uuid)', array['bos118','bos120']),
    ('public.stock_sales_unmatched(date,date,integer,uuid,integer)', array['bos118','bos120'])) v(fn, known)
  loop
    select p.prosrc into src from pg_proc p where p.oid = to_regprocedure(m.fn);
    for t in select distinct x[1] from regexp_matches(src, '(bos[0-9]+)', 'g') x loop
      if not t = any (m.known) then bad := bad || ' ' || m.fn || ' has ' || t || ';'; end if;
    end loop;
  end loop;
  if bad <> '' then
    raise exception 'phase120 stopped: a function it re-creates was changed by a phase it does not know (merge that change into phase120 first):%', bad;
  end if;
end $g$;

-- ============================ 1. INDEXES ============================
-- none (see the header: two candidates were measured and gave nothing)

-- ============================ 2. FUNCTION REWRITES (same signature, same result) ============================

-- R1  _rc118_buckets: the one ledger scan under stock_recon_statement and factory_branch_statement.
--     before: items x (bitmap scan of the item's ledger rows) nested loop -> 329k rows sorted on disk (30 MB) -> GroupAggregate with 15 FILTER aggregates over every row.
--     now:    one pass over the ledger (a seq scan; an index probe when one item is asked for, a join to items only when a category is asked for), each row put in
--             (place, item, effective reason, period part, returned-to-sender) and summed ONCE in a hash aggregate; the 15 columns are then read from those few sums.
--     same numbers: numeric addition is exact, a reversal row still counts under the reason of the row it reverses, a transfer out is a return when the receiver sent the item
--     to the sender earlier (the old EXISTS, now one hashed set of transfer ids).
create or replace function public._rc118_buckets(p_from date, p_to date, p_locs integer[], p_item uuid, p_cat text)
returns table (location_id integer, item_id uuid, opening numeric, production numeric, used numeric, purchases numeric, transfer_in numeric,
               transfer_ret numeric, transfer_oth numeric, sales numeric, cust_back numeric, wastage numeric, transit_loss numeric,
               adjustments numeric, closing numeric, ledger_total numeric, moves bigint)
language sql stable security definer set search_path = public set work_mem = '64MB' set jit = off as $$
-- bos118: the one set of ledger buckets both statements use. A reversal row is counted in the bucket of the row it reverses (so a cancelled transfer nets to 0 in
-- "transfers out"); out-going buckets are positive numbers. A transfer out is a RETURN when the receiver had earlier sent the same item to the sender.
-- Identity per row:  closing = opening + production + purchases + transfer_in + cust_back - used - sales - wastage - transit_loss - transfer_ret - transfer_oth + adjustments
-- bos120: same result, cheaper plan (phase120.sql R1). code: 1 production 2 used 3 purchases 4 transfer in 5 return 6 other transfer out 7 sale 8 give-back 9 wastage 10 transit loss 11 adjustment.
  with ret as materialized (
    select t.id from public.stock_transfers t
     where exists (select 1 from public.stock_transfers t2
                    where t2.from_location_id = t.to_location_id and t2.to_location_id = t.from_location_id and t2.item_id = t.item_id and t2.sent_at < t.sent_at and t2.status <> 'cancelled')),
  src as (
    select sl.location_id, sl.item_id, sl.qty_delta, sl.made_at, sl.reason, sl.ref_type, sl.ref_id, sl.reverses_id
      from public.stock_ledger sl
     where p_item is not null and sl.item_id = p_item and sl.location_id = any (p_locs)
       and (p_cat is null or sl.item_id in (select i.id from public.items i where i.category = p_cat))
    union all
    select sl.location_id, sl.item_id, sl.qty_delta, sl.made_at, sl.reason, sl.ref_type, sl.ref_id, sl.reverses_id
      from public.stock_ledger sl join public.items i on i.id = sl.item_id
     where p_item is null and p_cat is not null and i.category = p_cat and sl.location_id = any (p_locs)
    union all
    select sl.location_id, sl.item_id, sl.qty_delta, sl.made_at, sl.reason, sl.ref_type, sl.ref_id, sl.reverses_id
      from public.stock_ledger sl
     where p_item is null and p_cat is null and sl.location_id = any (p_locs)),
  bnd as materialized (select ((p_from::timestamp - interval '2 days') at time zone 'Asia/Dhaka') as f0, ((p_to::timestamp + interval '3 days') at time zone 'Asia/Dhaka') as t1),
  e as (
    select s.location_id, s.item_id, s.qty_delta, s.ref_type, s.ref_id,
           (case when s.reverses_id is null then s.reason else (select o.reason from public.stock_ledger o where o.id = s.reverses_id) end) as eff,
           (case when s.made_at < b.f0 then 0 when s.made_at >= b.t1 then 2   -- far from both edges: no time-zone conversion needed
                 when (s.made_at at time zone 'Asia/Dhaka')::date < p_from then 0 when (s.made_at at time zone 'Asia/Dhaka')::date <= p_to then 1 else 2 end) as part
      from src s cross join bnd b),
  l as (
    select e.location_id, e.item_id, e.qty_delta, e.part,
           (case e.eff when 'production_in' then 1 when 'issue_out' then 2 when 'purchase_in' then 3 when 'purchase_return' then 3 when 'transfer_in' then 4
                       when 'transfer_out' then (case when e.ref_type = 'transfer' and (case when e.ref_id ~ '^[0-9a-f-]{36}$' then e.ref_id::uuid end) in (select r.id from ret r) then 5 else 6 end)
                       when 'sale_out' then 7 when 'sale_void_in' then 8 when 'sale_return' then 8 when 'wastage' then 9 when 'transit_loss' then 10 else 11 end) as code
      from e),
  a as (select l.location_id, l.item_id, l.part, l.code, sum(l.qty_delta) as q, count(*) as n from l group by 1, 2, 3, 4)
  select a.location_id, a.item_id,
    coalesce(sum(a.q) filter (where a.part = 0), 0),
    coalesce(sum(a.q) filter (where a.part = 1 and a.code = 1), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 2), 0),
    coalesce(sum(a.q) filter (where a.part = 1 and a.code = 3), 0),
    coalesce(sum(a.q) filter (where a.part = 1 and a.code = 4), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 5), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 6), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 7), 0),
    coalesce(sum(a.q) filter (where a.part = 1 and a.code = 8), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 9), 0),
    coalesce(-sum(a.q) filter (where a.part = 1 and a.code = 10), 0),
    coalesce(sum(a.q) filter (where a.part = 1 and a.code = 11), 0),
    coalesce(sum(a.q) filter (where a.part <= 1), 0),
    coalesce(sum(a.q), 0),
    coalesce(sum(a.n) filter (where a.part = 1), 0)::bigint
  from a group by a.location_id, a.item_id;
$$;

-- R2  _rc118_gap: sales lines against the sale_out rows they posted.
--     before: _base_qty() (a plpgsql function with two lookups) was called TWICE per sales line (186k calls for a year).
--     now:    the conversion factor is taken once per distinct (item, unit) pair (about 1,000 calls) and multiplied: _base_qty(item, q, unit) is q * factor (or q, or NULL when the
--             factor is unknown), so q * _base_qty(item, 1, unit) is the same number.
create or replace function public._rc118_gap(p_from date, p_to date, p_locs integer[], p_item uuid)
returns table (sale_id uuid, receipt integer, sale_date date, location_id integer, item_id uuid, sold_qty numeric, base_qty numeric, ledger_qty numeric, diff_qty numeric, kind text)
language sql stable security definer set search_path = public set work_mem = '64MB' set jit = off as $$
-- bos118: done sales (voids excluded) per sale and item: quantity in the item's BASE unit against the sale_out rows the sale posted. Lines without an item (quick sales) are skipped.
-- bos120: unit factor once per (item, unit), not twice per line (phase120.sql R2).
  with ln as (
    select s.id as sid, s.receipt as rc, s.sale_date as sd, s.location_id as lid,
           (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end) as iid,
           (case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end) as q, nullif(btrim(e->>'unit'), '') as u
      from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
     where s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (p_locs)),
  ln2 as (select ln.* from ln where ln.iid is not null and ln.q is not null and (p_item is null or ln.iid = p_item)),
  fac as materialized (select d.iid, d.u, public._base_qty(d.iid, 1::numeric, d.u) as f, i.tracked
                         from (select distinct ln2.iid, ln2.u from ln2) d join public.items i on i.id = d.iid),
  g as (
    select ln2.sid, ln2.rc, ln2.sd, ln2.lid, ln2.iid, sum(ln2.q) as q, sum(ln2.q * fac.f) as bq, bool_or(fac.f is null) as unk, bool_and(fac.tracked) as tracked
      from ln2 join fac on fac.iid = ln2.iid and coalesce(fac.u, '') = coalesce(ln2.u, '') group by 1, 2, 3, 4, 5),
  led as (
    select sl.ref_id as rid, sl.item_id as iid, sum(-sl.qty_delta) as lq from public.stock_ledger sl
     where sl.ref_type = 'sale' and sl.reason = 'sale_out' and sl.ref_id in (select sid::text from g) group by 1, 2)
  select g.sid, g.rc, g.sd, g.lid, g.iid, g.q, g.bq, coalesce(led.lq, 0), coalesce(g.bq, 0) - coalesce(led.lq, 0),
         (case when not g.tracked then 'untracked' when g.unk then 'unit_unknown' when coalesce(led.lq, 0) = 0 then 'not_posted'
               when g.bq - led.lq > 0.0005 then 'short_posted' else 'over_posted' end)
    from g left join led on led.rid = g.sid::text and led.iid = g.iid
   where (not g.tracked) or g.unk or abs(coalesce(g.bq, 0) - coalesce(led.lq, 0)) > 0.0005;
$$;

-- R3  stock_sales_unmatched: the list and the counts come from ONE run of _rc118_gap (it ran twice: once for the rows, once for _rc118_gap_summary).
create or replace function public.stock_sales_unmatched(p_from date, p_to date, p_loc integer default null, p_item uuid default null, p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- bos118 (A2 G2): sales lines whose quantity did not leave stock as sold. kind: untracked (item not stock-tracked, expected), unit_unknown (no unit conversion, stock not reduced),
-- not_posted (tracked, nothing posted), short_posted / over_posted (quantity differs). Quantities only, no cost.
-- bos120: one gap run for rows + counts (phase120.sql R3).
declare locs integer[]; lim integer := least(greatest(coalesce(p_limit, 500), 1), 2000); rows_j jsonb; cnt jsonb; tot integer;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_period'; end if;
  if p_to - p_from > 370 then raise exception 'period_too_long'; end if;
  locs := public._rc118_locs('view_stock_recon', p_loc);
  with gp as materialized (select * from public._rc118_gap(p_from, p_to, locs, p_item))
  select (select coalesce(jsonb_agg(q.j order by q.sale_date desc, q.receipt desc), '[]'::jsonb) from (
            select g.sale_date, g.receipt, jsonb_build_object('sale_id', g.sale_id, 'receipt', g.receipt, 'sale_date', g.sale_date, 'location_id', g.location_id,
                     'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_id', g.item_id, 'item_code', i.code, 'item_bn', i.name_bn, 'item_en', coalesce(i.name_en, i.name_bn),
                     'unit', i.unit, 'base_unit', coalesce(i.base_unit, i.unit), 'sold_qty', round(g.sold_qty, 4), 'sold_base_qty', round(g.base_qty, 4), 'ledger_qty', round(g.ledger_qty, 4),
                     'diff_qty', round(g.diff_qty, 4), 'kind', g.kind) as j
              from gp g join public.items i on i.id = g.item_id join public.locations lo on lo.id = g.location_id
             order by g.sale_date desc, g.receipt desc limit lim) q),
         (select coalesce(jsonb_object_agg(k.kind, k.n), '{}'::jsonb) from (select g2.kind, count(*) as n from gp g2 group by g2.kind) k)
    into rows_j, cnt;
  select coalesce(sum(value::int), 0) into tot from jsonb_each_text(cnt);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_ids', to_jsonb(locs), 'rows', rows_j, 'counts', cnt, 'total', tot, 'truncated', tot > lim);
end $$;

commit;
