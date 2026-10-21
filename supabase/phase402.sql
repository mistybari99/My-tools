-- Phase 402 (bos402) - REPORTS: ONE COST BASIS FOR ITEM SALES AND BUSINESS ANALYSIS (package RPT-B1, item R7). Paste after phase401. Paste-twice safe. Earlier phase files are not edited.
-- WHY (docs/REPORTS_AUDIT_1.md D2): two cost bases for the same item. The margin report (l2_margin) and the dashboard take the cost from the STOCK LEDGER (what the goods really cost when bought / made),
--      with the typed price list (item_costs) only as a fallback. The first report engine (item_sales, category_sales, sales_summary, sales_combined) and the ABC list of the business page
--      (biz_items) use the typed price list ONLY. On the same day item_sales showed profit "-" and "100 % uncosted" where l2_margin showed a margin of 83.71 %.
-- WHAT THIS FILE ADDS (money-affecting, therefore a SETTING whose default keeps today's figures):
--   1. Setting reports_cost_basis (owner): price_list (default = today: only the typed price list) | ledger_first (ledger cost first, the price list only where the ledger has no cost).
--   2. View rpt_line_cost: the cost per sold line = the ledger cost of that sale for that item (all-or-nothing: if any ledger row of the sale and item has no cost, the ledger is not used for that line),
--      else the price-list cost. cost_src says which. Read only by the report engine, only when the setting is ledger_first.
--   3. _rptb1_item_cost_split / _rptb1_biz_item_cost: the same rule per item for the business analysis page (biz_items). With the setting at its default they return exactly the rows biz_items used before.
--   4. _rptb1_cost_notes: the unknown-cost notes under the first-engine reports (the same idea as l2_margin: cost of goods covers the costed part only; an estimate from the price list is said to be an estimate;
--      when the price list has no cost but the ledger does, the note says so and names the setting). Shown in both settings: today's reports gain a note, not a number.
--   5. biz_cost_status(from, to, place): read-only answer for the business page note and its CSV: revenue, costed from the ledger, costed from the price list, unknown, and the basis in use.
-- Nothing changes until the hooks (docs/integration/RPT-B1_hooks.sql, section 3) are installed AND the owner sets ledger_first; the notes appear with the hooks.
-- !! Re-pasting phase 9 (rpt_agg_sql, report_run) or phase 4 / 14 (biz_items) removes the bos402 hooks: run the hooks file again.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._rptb1_p401_present()') is null then raise exception 'phase402 needs phase401 (and phase400) first'; end if;
  if to_regprocedure('public.biz_items(date,date,integer)') is null or to_regclass('public.item_costs') is null or to_regclass('public.sales_fact_t') is null
     or to_regprocedure('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)') is null then
    raise exception 'phase402 needs the report engine (phase 9), item costs and the business analysis functions (phase 4 / 14)';
  end if;
end $g$;

create or replace function public._rptb1_p402_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- 1. the setting (English only, default = today) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('reports_cost_basis', 'reports', 'choice', '"price_list"', null, '["price_list","ledger_first"]', null, null,
  'Report cost basis: where item sales reports take the cost from', 'Report cost basis: where item sales reports take the cost from', 'Report cost basis: where item sales reports take the cost from',
  'price_list (default) = only the cost typed in the item master, as today. ledger_first = the cost from the stock ledger (what the goods really cost) first, the typed cost only where the ledger has none. Used by item sales, category sales, sales summary, combined sales and the business analysis page. The margin report already uses the ledger first.',
  'price_list (default) = only the cost typed in the item master, as today. ledger_first = the cost from the stock ledger (what the goods really cost) first, the typed cost only where the ledger has none. Used by item sales, category sales, sales summary, combined sales and the business analysis page. The margin report already uses the ledger first.',
  'price_list (default) = only the cost typed in the item master, as today. ledger_first = the cost from the stock ledger (what the goods really cost) first, the typed cost only where the ledger has none. Used by item sales, category sales, sales summary, combined sales and the business analysis page. The margin report already uses the ledger first.', 880)
 on conflict (key) do nothing;

create or replace function public._rptb1_cost_basis() returns text language sql stable security definer set search_path = public as $$
  select case when public.rule_txt('reports_cost_basis') = 'ledger_first' then 'ledger_first' else 'price_list' end $$;

-- ---------- 2. cost per sold line, ledger first ----------
-- cost_price is per unit of the sale line (ledger total cost of that sale and item divided by the quantity sold in that sale), so qty x cost_price is the cost of the line like item_costs.cost_price is.
-- Ledger = rows of the sale itself (ref_type sale, reasons sale_out / issue_out). A pack sale posts its parts under another ref_type: those lines use the price list or stay unknown.
create or replace view public.rpt_line_cost as
select t.sale_id, t.line_no,
  coalesce(lc.unit_cost, ic.cost_price) as cost_price,
  case when lc.unit_cost is not null then 'ledger' when ic.cost_price is not null then 'price_list' end as cost_src
from public.sales_fact_t t
left join (select x.item_id, x.cost_price from public.item_costs x join public.items b on b.id = x.item_id where b.count_in_business) ic on ic.item_id = t.item_id
left join lateral (
  select sum(-l.qty_delta * l.unit_cost) / nullif((select sum(q.qty) from public.sales_fact_t q where q.sale_id = t.sale_id and q.item_id = t.item_id), 0) as unit_cost
    from public.stock_ledger l
   where l.ref_type = 'sale' and l.ref_id = t.sale_id::text and l.item_id = t.item_id and l.reason in ('sale_out', 'issue_out') and t.item_id is not null
  having count(*) > 0 and bool_and(coalesce(l.unit_cost, 0) > 0)) lc on true;
revoke all on public.rpt_line_cost from public, anon, authenticated;

-- ---------- 3. the same rule per item (business analysis page) ----------
-- one row per item sold in the period (done sales at the places the caller may see): revenue, quantity, ledger unit cost (all-or-nothing over the item's sales) and price-list cost (items that count in the business)
create or replace function public._rptb1_item_cost_split(p_from date, p_to date, p_loc int) returns table (item_id uuid, rev numeric, qty numeric, lp numeric, pl numeric)
language sql stable security definer set search_path = public as $$
  with ln as (
    select t.sale_id, t.item_id, sum(t.qty) as q, sum(t.net) as r
      from public.sales_fact_t t
     where t.status = 'done' and t.day between p_from and p_to and (p_loc is null or t.location_id = p_loc) and t.location_id in (select l.id from public.locations l where public.can_loc(l.id)) and t.item_id is not null
     group by 1, 2),
  ps as (
    select ln.item_id, ln.q, ln.r,
           (select sum(-l.qty_delta * l.unit_cost) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = ln.sale_id::text and l.item_id = ln.item_id and l.reason in ('sale_out', 'issue_out')) as c,
           (select count(*) > 0 and bool_and(coalesce(l.unit_cost, 0) > 0) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = ln.sale_id::text and l.item_id = ln.item_id and l.reason in ('sale_out', 'issue_out')) as ok
      from ln),
  ag as (select ps.item_id, sum(ps.r) as rev, sum(ps.q) as qty, case when bool_and(coalesce(ps.ok, false)) then sum(ps.c) / nullif(sum(ps.q), 0) end as lp from ps group by 1)
  select ag.item_id, ag.rev, ag.qty, ag.lp, (select ic.cost_price from public.item_costs ic join public.items b on b.id = ic.item_id where ic.item_id = ag.item_id and b.count_in_business) as pl
    from ag;
$$;

-- the cost rows biz_items joins: default basis = exactly the rows it used before (the price list of items that count in the business); ledger_first = ledger unit cost first
create or replace function public._rptb1_biz_item_cost(p_from date, p_to date, p_loc int) returns table (item_id uuid, cost_price numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if public._rptb1_cost_basis() <> 'ledger_first' then
    return query select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business;
    return;
  end if;
  return query
    select i.id, coalesce(s.lp, ic.cost_price)
      from public.items i
      left join public._rptb1_item_cost_split(p_from, p_to, p_loc) s on s.item_id = i.id
      left join (select x.item_id, x.cost_price from public.item_costs x join public.items b on b.id = x.item_id where b.count_in_business) ic on ic.item_id = i.id
     where coalesce(s.lp, ic.cost_price) is not null;
end $$;

-- ---------- 4. read-only status for the business page (note + CSV) ----------
create or replace function public.biz_cost_status(p_from date, p_to date, p_loc integer default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare basis text := public._rptb1_cost_basis(); rev numeric; led numeric; fb numeric; unk numeric; could numeric; allrev numeric; pl_only numeric;
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if not public.biz_cost_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  select coalesce(sum(t.net), 0) into allrev from public.sales_fact_t t
   where t.status = 'done' and t.day between p_from and p_to and (p_loc is null or t.location_id = p_loc) and t.location_id in (select l.id from public.locations l where public.can_loc(l.id));
  select coalesce(sum(s.rev), 0),
         coalesce(sum(s.rev) filter (where basis = 'ledger_first' and s.lp is not null), 0),
         coalesce(sum(s.rev) filter (where s.pl is not null and (basis = 'price_list' or s.lp is null)), 0),
         coalesce(sum(s.rev) filter (where basis = 'price_list' and s.pl is null and s.lp is not null), 0)
    into rev, led, fb, could
    from public._rptb1_item_cost_split(p_from, p_to, p_loc) s;
  unk := greatest(allrev - led - fb, 0);                    -- quick / unlisted lines and items with no cost anywhere
  return jsonb_build_object('basis', basis, 'revenue', round(allrev, 2), 'ledger_rev', round(led, 2), 'price_list_rev', round(fb, 2), 'unknown_rev', round(unk, 2),
    'unknown_pct', case when allrev > 0 then round(100 * unk / allrev, 2) end, 'ledger_could_cost_rev', round(could, 2));
end $$;

-- ---------- 5. the notes under the first-engine reports ----------
create or replace function public._rptb1_cost_notes(p_def jsonb, p_flt jsonb, p_allowed int[], p_from date, p_to date, p_mobok boolean, p_costok boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare basis text := public._rptb1_cost_basis(); w text; tot numeric; led numeric; fb numeric; unk numeric; could numeric; out_ jsonb := '[]'::jsonb;
begin
  if not p_costok or not (p_def ->> 'src' = 'line' or coalesce((p_def ->> 'cost_join')::int, 0) = 1) then return out_; end if;
  w := public.rpt_where('line', 'f', p_flt, p_allowed, p_from, p_to, array['locations', 'brands', 'staff', 'modes', 'sale_type', 'customer', 'min_amount', 'max_amount', 'items', 'categories'], p_mobok) ->> 'w';
  -- price_list: only the lines without a typed cost look at the ledger (for the hint); ledger_first: every line does (that is the basis in use)
  execute format($q$with f0 as (select f.sale_id, f.line_no, f.net, ic.cost_price as pl from public.sales_fact f left join (select x.item_id, x.cost_price from public.item_costs x join public.items b on b.id = x.item_id where b.count_in_business) ic on ic.item_id = f.item_id where %s and f.status = 'done')
    select coalesce(sum(f0.net), 0),
      coalesce(sum(f0.net) filter (where %L = 'ledger_first' and c.cost_src = 'ledger'), 0),
      coalesce(sum(f0.net) filter ( where (%L = 'price_list' and f0.pl is not null) or (%L = 'ledger_first' and c.cost_src = 'price_list')), 0),
      coalesce(sum(f0.net) filter (where %L = 'price_list' and f0.pl is null and c.cost_src = 'ledger'), 0)
    from f0 left join public.rpt_line_cost c on c.sale_id = f0.sale_id and c.line_no = f0.line_no and (%L = 'ledger_first' or f0.pl is null)$q$, w, basis, basis, basis, basis, basis) into tot, led, fb, could;
  unk := greatest(tot - led - fb, 0);
  if unk > 0.004 then
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'cost_unknown', 'unknown_rev', round(unk, 2), 'unknown_pct', round(100 * unk / nullif(tot, 0), 2),
      'text_en', 'Cost is unknown for sales of ' || round(unk, 2)::text || ' (' || round(100 * unk / nullif(tot, 0), 1)::text || ' %): no '
                 || case basis when 'ledger_first' then 'stock-ledger cost and no cost in the item master' else 'cost in the item master' end
                 || '. Cost of goods and profit cover the costed part only. Needed: receive or produce the item with a cost, or type its cost price in the item master.',
      'text_bn', round(unk, 2)::text || ' টাকার বিক্রির খরচ জানা নেই (' || round(100 * unk / nullif(tot, 0), 1)::text || ' %): '
                 || case basis when 'ledger_first' then 'স্টক-হিসাবে খরচ নেই, আইটেম মাস্টারেও নেই' else 'আইটেম মাস্টারে খরচ লেখা নেই' end
                 || '। মালের খরচ ও লাভ শুধু খরচ-জানা অংশের। দরকার: খরচসহ মাল কেনা/বানানো, অথবা আইটেম মাস্টারে ক্রয়মূল্য লেখা।'));
  end if;
  if basis = 'ledger_first' and fb > 0.004 then
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'cost_estimate', 'price_list_rev', round(fb, 2),
      'text_en', 'Sales of ' || round(fb, 2)::text || ' have no stock-ledger cost; their cost comes from the typed price list (an estimate from the book cost).',
      'text_bn', round(fb, 2)::text || ' টাকার বিক্রির স্টক-হিসাবে খরচ নেই; খরচ নেওয়া হয়েছে লিখে রাখা খরচ-তালিকা থেকে (বইয়ের খরচ থেকে অনুমান)।'));
  end if;
  if basis = 'price_list' and could > 0.004 then
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'cost_basis_hint', 'ledger_could_cost_rev', round(could, 2),
      'text_en', 'The stock ledger holds a cost for sales of ' || round(could, 2)::text || ' that have no cost in the item master. The setting "Report cost basis" = ledger_first would use it (the margin report already does).',
      'text_bn', round(could, 2)::text || ' টাকার বিক্রির খরচ আইটেম মাস্টারে নেই, কিন্তু স্টক-হিসাবে আছে। "Report cost basis" = ledger_first করলে তা ব্যবহার হবে (মার্জিন রিপোর্ট আগেই তা করে)।'));
  end if;
  return out_;
end $$;

create or replace function public._rptb1_hooked402() returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'rpt_agg_sql', position('bos402' in pg_get_functiondef('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)'::regprocedure)) > 0,
    'report_run', position('bos402' in pg_get_functiondef('public.report_run(text,jsonb,text,text,integer,boolean)'::regprocedure)) > 0,
    'biz_items', position('bos402' in pg_get_functiondef('public.biz_items(date,date,integer)'::regprocedure)) > 0);
$$;

revoke all on function public._rptb1_p402_present(), public._rptb1_cost_basis(), public._rptb1_item_cost_split(date, date, int), public._rptb1_biz_item_cost(date, date, int),
  public._rptb1_cost_notes(jsonb, jsonb, int[], date, date, boolean, boolean), public._rptb1_hooked402() from public, anon, authenticated;
revoke all on function public.biz_cost_status(date, date, integer) from public, anon;
grant execute on function public.biz_cost_status(date, date, integer) to authenticated;
