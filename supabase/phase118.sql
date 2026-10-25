-- ============================================================
-- Phase 118 (bos118) - STEP B4: three READ-ONLY reconciliation reports (audit2 A2 G1/G2, A3 G13/C19/C20, A5 GAP-1).
--   1. stock_recon_statement   per item / location / period:  opening + production + purchases + transfers in + customer give-backs
--                              - used in production - sales - wastage - transit loss - transfers out +/- adjustments = closing, with a variance flag
--                              (ledger total against the cached stock_balance) and the sales lines that did not leave stock (stock_sales_unmatched).
--   2. factory_branch_statement per location / item / period: sent, received, short, in transit (with ageing), returned to the sender, sold, wasted,
--                              remaining, value at the transferred cost. Built from stock_transfers + stock_ledger + stock_balance (prototype a5_01b).
--   3. net_profit_report       per branch and per product: net sales, cost of goods, gross profit (costed part), wastage, card fees, variable expenses
--                              = CONTRIBUTION MARGIN; then other expenses, salary sheet, monthly fixed cost, attributed shared bills = NET PROFIT AFTER OVERHEAD.
--                              Every figure is labelled with what it includes; revenue with unknown cost is shown separately and never counted at 100 % margin.
--   Needs phases 72..103 (guard below). Additive and paste-twice safe (create or replace / if not exists / on conflict do nothing / where not exists).
--   Nothing existing is re-created or changed: no table, trigger, rule value, privilege or function of an older phase is touched. The reports only READ
--   (stable functions); the one write is the audit row of recon_export_log118 (a CSV export, same audit_log shape as log_report_export2).
--   Whole file = one transaction: if the guard refuses, nothing is created.
--   Objects:
--     grants   view_stock_recon (module stock)  - stock statement and the unmatched-sales list (quantities only)
--              view_branch_statement (module stock) - factory-to-branch statement
--              view_net_profit (module cost)    - net profit report; ALSO needs biz_cost_ok() (owner, ITEM_COST view, view_cost or view_profit): profit is cost-derived
--              Cost secrecy: in the two stock statements every cost / value key is left out unless biz_cost_ok(). Location rights: a row is shown only for a location the
--              caller can_loc() AND holds the grant for (has_grant(code, location)); the owner sees all.
--     rules    profit_variable_heads (text, default "transport")  expense heads treated as VARIABLE selling cost (inside the contribution margin);
--              branch_stmt_ageing_hours (text, default "24,72")   in-transit ageing boundaries in hours (A5: 0-24 h / 1-3 days / over 3 days)
--     RPC      stock_recon_statement(from, to, loc, item, category, limit)
--              stock_sales_unmatched(from, to, loc, item, limit)
--              factory_branch_statement(from, to, loc, item, category, limit)
--              net_profit_report(from, to, loc, category)
--              recon_export_log118(key, rows, filters)     audit row of a CSV export (owner, or grant + export_data)
--   Internal (closed to the browser): _rc118_locs, _rc118_buckets, _rc118_gap, _rc118_gap_summary.
--   Tag: bos118. No existing function is re-created.
-- ============================================================
begin;

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('72', 'public._p27_pl(date,date,integer[])'), ('78', 'public._c78_rows(date,date)'),
    ('78', 'public._c78_main_loc(date)'), ('80', 'public._cost_free80(uuid)'), ('88', 'public._rcs88()'), ('88', 'public.biz_cost_ok()'),
    ('82', 'public._base_qty(uuid,numeric,text)'), ('85', 'public._acct_from85()')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.card_settlements85') is null then miss := miss || ' 85'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if to_regclass('public.audit_log') is null or to_regclass('public.grant_defs') is null or to_regclass('public.rules') is null
     or to_regclass('public.stock_ledger') is null or to_regclass('public.stock_transfers') is null then miss := miss || ' base'; end if;
  if miss <> '' then
    raise exception 'phase118 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- grants ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'view_stock_recon', 'stock', 96, 'স্টকের হিসাব মেলানো (শুরু + আসা − গেছে = শেষ) দেখা', 'Stock-এর হিসাব মেলানো (শুরু + আসা − গেছে = শেষ) দেখা', 'See the stock reconciliation statement (opening + in - out = closing)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'view_stock_recon');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'view_branch_statement', 'stock', 97, 'কারখানা থেকে শাখার হিসাব (পাঠানো, পৌঁছানো, বিক্রি, বাকি) দেখা', 'Factory থেকে branch-এর হিসাব (পাঠানো, পৌঁছানো, বিক্রি, বাকি) দেখা', 'See the factory-to-branch statement (sent, received, sold, remaining)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'view_branch_statement');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'view_net_profit', 'cost', 22, 'পণ্য ও শাখা অনুযায়ী নিট লাভ (কন্ট্রিবিউশন ও ওভারহেড সহ) দেখা', 'Product ও branch অনুযায়ী net profit (contribution ও overhead সহ) দেখা', 'See net profit per product and branch (contribution margin and after overhead)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'view_net_profit');

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('profit_variable_heads', 'reports', 'text', '"transport"'::jsonb, null, null, null, null,
  'নিট লাভ রিপোর্টে যে খরচের হেড বিক্রির সাথে বদলায় (ভ্যারিয়েবল)', 'Net profit report-এ যে খরচের head বিক্রির সাথে বদলায় (variable)', 'Expense heads that count as variable cost in the net profit report',
  'কমা দিয়ে হেডের কোড লিখুন (যেমন transport)। এই হেডের খরচ কন্ট্রিবিউশন মার্জিনের ভেতরে ধরা হয়; বাকি সব খরচ ওভারহেড। ফাঁকা = কোনো হেড ভ্যারিয়েবল নয়।',
  'Comma দিয়ে head-এর code লিখুন (যেমন transport)। এই head-এর খরচ contribution margin-এর ভেতরে ধরা হয়; বাকি সব খরচ overhead। ফাঁকা = কোনো head variable নয়।',
  'Comma-separated expense head codes (for example transport). Spending on these heads is counted inside the contribution margin; every other expense is overhead. Blank = no head is variable.', 995),
 ('branch_stmt_ageing_hours', 'stock', 'text', '"24,72"'::jsonb, 'hours', null, null, null,
  'পথে থাকা মালের বয়স ভাগ (ঘণ্টা, কমা দিয়ে)', 'পথে থাকা মালের age ভাগ (ঘণ্টা, comma দিয়ে)', 'In-transit ageing boundaries (hours, comma-separated)',
  'দুটি সংখ্যা, যেমন 24,72 = ২৪ ঘণ্টার কম / ১-৩ দিন / ৩ দিনের বেশি। ফাঁকা বা ভুল হলে 24,72 ধরা হয়।',
  'দুটি সংখ্যা, যেমন 24,72 = ২৪ ঘণ্টার কম / ১-৩ দিন / ৩ দিনের বেশি। ফাঁকা বা ভুল হলে 24,72 ধরা হয়।',
  'Two numbers, for example 24,72 = under 24 hours / 1-3 days / over 3 days. Blank or invalid falls back to 24,72.', 996)
on conflict (key) do nothing;

-- advisor rows: owner-typed classification and boundaries, so no value is recommended
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('profit_variable_heads', 'profit_variable_heads', '118', 'reports', null, '{}'::text[],
  'কোন খরচ বিক্রির সাথে বদলায় তা আপনার ব্যবসার সিদ্ধান্ত, তাই কোনো মান ঠিক করা নেই। ডিফল্ট transport।',
  'কোন খরচ বিক্রির সাথে বদলায় তা আপনার business-এর decision, তাই কোনো মান ঠিক করা নেই। Default transport।',
  'Which costs move with sales is your business decision, so no value is recommended. The default is transport.', 995),
 ('branch_stmt_ageing_hours', 'branch_stmt_ageing_hours', '118', 'stock', null, '{}'::text[],
  'পথে থাকা মাল কত ঘণ্টায় "পুরনো" হয় তা আপনার সিদ্ধান্ত। ডিফল্ট 24,72 (অডিট A5 অনুযায়ী)।',
  'পথে থাকা মাল কত ঘণ্টায় "পুরনো" হয় তা আপনার decision। Default 24,72 (audit A5 অনুযায়ী)।',
  'How many hours make goods in transit "old" is your decision. The default is 24,72 (audit A5).', 996)
on conflict (code) do nothing;

-- ---------- internal helpers (no privilege for anyone but the definer) ----------
create or replace function public._rc118_locs(p_grant text, p_loc integer) returns integer[]
language plpgsql stable security definer set search_path = public as $$
-- bos118: the locations the caller may see for this grant (location right AND grant for that location); p_loc narrows to one; empty = refused
declare r integer[];
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l.id order by l.id), '{}') into r from public.locations l
   where public.can_loc(l.id) and public.has_grant(p_grant, l.id) and (p_loc is null or l.id = p_loc);
  if coalesce(array_length(r, 1), 0) = 0 then raise exception 'not allowed'; end if;
  return r;
end $$;

create or replace function public._rc118_buckets(p_from date, p_to date, p_locs integer[], p_item uuid, p_cat text)
returns table (location_id integer, item_id uuid, opening numeric, production numeric, used numeric, purchases numeric, transfer_in numeric,
               transfer_ret numeric, transfer_oth numeric, sales numeric, cust_back numeric, wastage numeric, transit_loss numeric,
               adjustments numeric, closing numeric, ledger_total numeric, moves bigint)
language sql stable security definer set search_path = public as $$
-- bos118: the one set of ledger buckets both statements use. A reversal row is counted in the bucket of the row it reverses (so a cancelled transfer nets to 0 in
-- "transfers out"); out-going buckets are positive numbers. A transfer out is a RETURN when the receiver had earlier sent the same item to the sender.
-- Identity per row:  closing = opening + production + purchases + transfer_in + cust_back - used - sales - wastage - transit_loss - transfer_ret - transfer_oth + adjustments
  with l as (
    select sl.location_id, sl.item_id, sl.qty_delta, (sl.made_at at time zone 'Asia/Dhaka')::date as d, coalesce(o.reason, sl.reason) as eff,
           (coalesce(o.reason, sl.reason) = 'transfer_out' and sl.ref_type = 'transfer' and exists (
              select 1 from public.stock_transfers t join public.stock_transfers t2
                on t2.from_location_id = t.to_location_id and t2.to_location_id = t.from_location_id and t2.item_id = t.item_id and t2.sent_at < t.sent_at and t2.status <> 'cancelled'
              where t.id = (case when sl.ref_id ~ '^[0-9a-f-]{36}$' then sl.ref_id::uuid end))) as is_ret
      from public.stock_ledger sl
      left join public.stock_ledger o on o.id = sl.reverses_id
      join public.items i on i.id = sl.item_id
     where sl.location_id = any (p_locs) and (p_item is null or sl.item_id = p_item) and (p_cat is null or i.category = p_cat))
  select l.location_id, l.item_id,
    coalesce(sum(l.qty_delta) filter (where l.d < p_from), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'production_in'), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'issue_out'), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff in ('purchase_in', 'purchase_return')), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transfer_in'), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transfer_out' and l.is_ret), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transfer_out' and not l.is_ret), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'sale_out'), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff in ('sale_void_in', 'sale_return')), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'wastage'), 0),
    coalesce(-sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff = 'transit_loss'), 0),
    coalesce(sum(l.qty_delta) filter (where l.d between p_from and p_to and l.eff not in ('production_in', 'issue_out', 'purchase_in', 'purchase_return', 'transfer_in', 'transfer_out',
                                                                                         'sale_out', 'sale_void_in', 'sale_return', 'wastage', 'transit_loss')), 0),
    coalesce(sum(l.qty_delta) filter (where l.d <= p_to), 0),
    coalesce(sum(l.qty_delta), 0),
    count(*) filter (where l.d between p_from and p_to)
  from l group by l.location_id, l.item_id;
$$;

create or replace function public._rc118_gap(p_from date, p_to date, p_locs integer[], p_item uuid)
returns table (sale_id uuid, receipt integer, sale_date date, location_id integer, item_id uuid, sold_qty numeric, base_qty numeric, ledger_qty numeric, diff_qty numeric, kind text)
language sql stable security definer set search_path = public as $$
-- bos118: done sales (voids excluded) per sale and item: quantity in the item's BASE unit against the sale_out rows the sale posted. Lines without an item (quick sales) are skipped.
  with ln as (
    select s.id as sid, s.receipt as rc, s.sale_date as sd, s.location_id as lid,
           (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end) as iid,
           (case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end) as q, nullif(btrim(e->>'unit'), '') as u
      from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
     where s.status = 'done' and s.sale_date between p_from and p_to and s.location_id = any (p_locs)),
  g as (
    select ln.sid, ln.rc, ln.sd, ln.lid, ln.iid, sum(ln.q) as q, sum(public._base_qty(ln.iid, ln.q, ln.u)) as bq, bool_or(public._base_qty(ln.iid, ln.q, ln.u) is null) as unk
      from ln where ln.iid is not null and ln.q is not null and (p_item is null or ln.iid = p_item) group by 1, 2, 3, 4, 5),
  led as (
    select sl.ref_id as rid, sl.item_id as iid, sum(-sl.qty_delta) as lq from public.stock_ledger sl
     where sl.ref_type = 'sale' and sl.reason = 'sale_out' and sl.ref_id in (select sid::text from g) group by 1, 2)
  select g.sid, g.rc, g.sd, g.lid, g.iid, g.q, g.bq, coalesce(led.lq, 0), coalesce(g.bq, 0) - coalesce(led.lq, 0),
         (case when not i.tracked then 'untracked' when g.unk then 'unit_unknown' when coalesce(led.lq, 0) = 0 then 'not_posted'
               when g.bq - led.lq > 0.0005 then 'short_posted' else 'over_posted' end)
    from g join public.items i on i.id = g.iid left join led on led.rid = g.sid::text and led.iid = g.iid
   where (not i.tracked) or g.unk or abs(coalesce(g.bq, 0) - coalesce(led.lq, 0)) > 0.0005;
$$;

create or replace function public._rc118_gap_summary(p_from date, p_to date, p_locs integer[], p_item uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(q.k, q.n), '{}'::jsonb) from (select g.kind as k, count(*) as n from public._rc118_gap(p_from, p_to, p_locs, p_item) g group by g.kind) q;
$$;

-- ---------- 1. stock reconciliation statement ----------
create or replace function public.stock_recon_statement(p_from date, p_to date, p_loc integer default null, p_item uuid default null, p_category text default null, p_limit integer default 2000)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- bos118: opening + production + purchases + transfers in + give-backs - used - sales - wastage - transit loss - transfers out +/- adjustments = closing, per item and location.
-- variance_qty = ledger total (all rows) - cached stock_balance.qty; flag 'variance' when it is not 0. Cost keys only when biz_cost_ok().
declare locs integer[]; cost_ok boolean; lim integer := least(greatest(coalesce(p_limit, 2000), 1), 5000); rows_j jsonb; n_all integer; sm jsonb; gap jsonb;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_period'; end if;
  if p_to - p_from > 370 then raise exception 'period_too_long'; end if;
  locs := public._rc118_locs('view_stock_recon', p_loc);
  cost_ok := public.biz_cost_ok();
  with b as (select * from public._rc118_buckets(p_from, p_to, locs, p_item, p_category)),
  x as (
    select b.*, i.code, i.name_bn, i.name_en, i.unit, i.tracked, lo.name_bn as loc_bn, lo.name_en as loc_en, coalesce(sb.qty, 0) as bal_qty, sb.avg_cost,
           (b.opening + b.production + b.purchases + b.transfer_in + b.cust_back - b.used - b.sales - b.wastage - b.transit_loss - b.transfer_ret - b.transfer_oth + b.adjustments) as calc_closing
      from b join public.items i on i.id = b.item_id join public.locations lo on lo.id = b.location_id
      left join public.stock_balance sb on sb.item_id = b.item_id and sb.location_id = b.location_id
     where b.moves > 0 or b.opening <> 0 or b.closing <> 0 or coalesce(sb.qty, 0) <> 0),
  y as (select x.*, (x.ledger_total - x.bal_qty) as variance, abs(x.closing - x.calc_closing) > 0.0005 as unbalanced from x)
  select count(*),
         coalesce(jsonb_agg(r.j order by r.lid, r.code) filter (where r.rn <= lim), '[]'::jsonb),
         jsonb_build_object('items', count(*), 'with_variance', count(*) filter (where r.var_flag), 'unbalanced', count(*) filter (where r.unb), 'adjusted', count(*) filter (where r.adj))
    into n_all, rows_j, sm
  from (
    select row_number() over (order by y.location_id, y.code) as rn, y.location_id as lid, y.code, (abs(y.variance) > 0.0005) as var_flag, y.unbalanced as unb, (abs(y.adjustments) > 0.0005) as adj,
      jsonb_strip_nulls(jsonb_build_object(
        'location_id', y.location_id, 'location_bn', y.loc_bn, 'location_en', coalesce(y.loc_en, y.loc_bn),
        'item_id', y.item_id, 'item_code', y.code, 'item_bn', y.name_bn, 'item_en', coalesce(y.name_en, y.name_bn), 'unit', y.unit, 'tracked', y.tracked,
        'opening_qty', round(y.opening, 4), 'production_qty', round(y.production, 4), 'purchases_qty', round(y.purchases, 4), 'transfer_in_qty', round(y.transfer_in, 4),
        'give_back_qty', round(y.cust_back, 4), 'used_qty', round(y.used, 4), 'sales_qty', round(y.sales, 4), 'wastage_qty', round(y.wastage, 4), 'transit_loss_qty', round(y.transit_loss, 4),
        'transfer_out_qty', round(y.transfer_ret + y.transfer_oth, 4), 'returned_to_sender_qty', round(y.transfer_ret, 4), 'adjustments_qty', round(y.adjustments, 4),
        'closing_qty', round(y.closing, 4), 'balance_qty', round(y.bal_qty, 4), 'variance_qty', round(y.variance, 4),
        'flags', (select coalesce(jsonb_agg(f), '[]'::jsonb) from unnest(array[case when abs(y.variance) > 0.0005 then 'variance' end, case when y.unbalanced then 'unbalanced' end,
                                                                               case when abs(y.adjustments) > 0.0005 then 'adjusted' end, case when y.closing < 0 then 'negative' end]) f where f is not null),
        'avg_cost', case when cost_ok then round(y.avg_cost, 4) end,
        'closing_value', case when cost_ok and y.avg_cost is not null then round(y.closing * y.avg_cost, 2) end)) as j
      from y) r;
  gap := public._rc118_gap_summary(p_from, p_to, locs, p_item);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_ids', to_jsonb(locs), 'cost_visible', cost_ok, 'rows', rows_j, 'row_count', n_all, 'truncated', n_all > lim,
    'summary', sm, 'sales_unmatched', gap,
    'formula', 'opening + production + purchases + transfers_in + give_backs - used - sales - wastage - transit_loss - transfers_out + adjustments = closing');
end $$;

create or replace function public.stock_sales_unmatched(p_from date, p_to date, p_loc integer default null, p_item uuid default null, p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- bos118 (A2 G2): sales lines whose quantity did not leave stock as sold. kind: untracked (item not stock-tracked, expected), unit_unknown (no unit conversion, stock not reduced),
-- not_posted (tracked, nothing posted), short_posted / over_posted (quantity differs). Quantities only, no cost.
declare locs integer[]; lim integer := least(greatest(coalesce(p_limit, 500), 1), 2000); rows_j jsonb; cnt jsonb; tot integer;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_period'; end if;
  if p_to - p_from > 370 then raise exception 'period_too_long'; end if;
  locs := public._rc118_locs('view_stock_recon', p_loc);
  select coalesce(jsonb_agg(q.j order by q.sale_date desc, q.receipt desc), '[]'::jsonb) into rows_j from (
    select g.sale_date, g.receipt, jsonb_build_object('sale_id', g.sale_id, 'receipt', g.receipt, 'sale_date', g.sale_date, 'location_id', g.location_id,
             'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_id', g.item_id, 'item_code', i.code, 'item_bn', i.name_bn, 'item_en', coalesce(i.name_en, i.name_bn),
             'unit', i.unit, 'base_unit', coalesce(i.base_unit, i.unit), 'sold_qty', round(g.sold_qty, 4), 'sold_base_qty', round(g.base_qty, 4), 'ledger_qty', round(g.ledger_qty, 4),
             'diff_qty', round(g.diff_qty, 4), 'kind', g.kind) as j
      from public._rc118_gap(p_from, p_to, locs, p_item) g join public.items i on i.id = g.item_id join public.locations lo on lo.id = g.location_id
     order by g.sale_date desc, g.receipt desc limit lim) q;
  cnt := public._rc118_gap_summary(p_from, p_to, locs, p_item);
  select coalesce(sum(value::int), 0) into tot from jsonb_each_text(cnt);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_ids', to_jsonb(locs), 'rows', rows_j, 'counts', cnt, 'total', tot, 'truncated', tot > lim);
end $$;

-- ---------- 2. factory-to-branch statement ----------
create or replace function public.factory_branch_statement(p_from date, p_to date, p_loc integer default null, p_item uuid default null, p_category text default null, p_limit integer default 2000)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- bos118 (A5 GAP-1): per location and item. Supply side from stock_transfers (sent / received / short in the period, in transit at the end of the period with ageing),
-- stock side from the ledger buckets (opening, received, returned to the sender, sold, wasted, remaining). receive_mismatch = ledger transfer_in - received - resolved transit loss.
-- Value = quantity x the cost the sender's ledger row carried (cost keys only when biz_cost_ok()).
declare locs integer[]; cost_ok boolean; lim integer := least(greatest(coalesce(p_limit, 2000), 1), 5000); e_end timestamptz; asof timestamptz; rr text; b1 numeric := 24; b2 numeric := 72;
        rows_j jsonb; n_all integer; byloc jsonb;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_period'; end if;
  if p_to - p_from > 370 then raise exception 'period_too_long'; end if;
  locs := public._rc118_locs('view_branch_statement', p_loc);
  cost_ok := public.biz_cost_ok();
  e_end := ((p_to + 1)::timestamp at time zone 'Asia/Dhaka');
  asof := least(e_end, now());
  rr := btrim(coalesce(public.rule_val('branch_stmt_ageing_hours') #>> '{}', ''));
  if rr ~ '^[0-9]+(\.[0-9]+)?\s*,\s*[0-9]+(\.[0-9]+)?$' and btrim(split_part(rr, ',', 1))::numeric < btrim(split_part(rr, ',', 2))::numeric then
    b1 := btrim(split_part(rr, ',', 1))::numeric; b2 := btrim(split_part(rr, ',', 2))::numeric;
  end if;
  with b as (select * from public._rc118_buckets(p_from, p_to, locs, p_item, p_category)),
  tr0 as (
    select t.*, (t.sent_at at time zone 'Asia/Dhaka')::date as sd, (t.received_at at time zone 'Asia/Dhaka')::date as rd,
           extract(epoch from (asof - t.sent_at)) / 3600.0 as age_h
      from public.stock_transfers t join public.items i on i.id = t.item_id
     where t.status <> 'cancelled' and t.sent_at < e_end and (t.to_location_id = any (locs) or t.from_location_id = any (locs))
       and (p_item is null or t.item_id = p_item) and (p_category is null or i.category = p_category)),
  uc as (
    select sl.ref_id as tid, sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) / nullif(sum(-sl.qty_delta), 0) as cost
      from public.stock_ledger sl where sl.ref_type = 'transfer' and sl.reason = 'transfer_out' and sl.reverses_id is null and sl.ref_id in (select id::text from tr0) group by 1),
  tr as (select tr0.*, uc.cost as ucost, (tr0.sent_at < e_end and (tr0.status = 'sent' or tr0.received_at >= e_end)) as in_tr from tr0 left join uc on uc.tid = tr0.id::text),
  toa as (
    select tr.to_location_id as lid, tr.item_id,
           coalesce(sum(tr.qty) filter (where tr.sd between p_from and p_to), 0) as sent_to,
           coalesce(sum(tr.received_qty) filter (where tr.status = 'received' and tr.rd between p_from and p_to), 0) as received_to,
           coalesce(sum(tr.qty - tr.received_qty) filter (where tr.status = 'received' and tr.rd between p_from and p_to and tr.received_qty < tr.qty), 0) as short_to,
           coalesce(sum(tr.qty) filter (where tr.in_tr), 0) as tr_qty,
           coalesce(sum(tr.qty) filter (where tr.in_tr and tr.age_h < b1), 0) as tr_q0,
           coalesce(sum(tr.qty) filter (where tr.in_tr and tr.age_h >= b1 and tr.age_h < b2), 0) as tr_q1,
           coalesce(sum(tr.qty) filter (where tr.in_tr and tr.age_h >= b2), 0) as tr_q2,
           max(tr.age_h) filter (where tr.in_tr) as oldest_h,
           sum(tr.qty * tr.ucost) filter (where tr.sd between p_from and p_to) as sent_val,
           sum(tr.received_qty * tr.ucost) filter (where tr.status = 'received' and tr.rd between p_from and p_to) as recv_val,
           sum((tr.qty - tr.received_qty) * tr.ucost) filter (where tr.status = 'received' and tr.rd between p_from and p_to and tr.received_qty < tr.qty) as short_val,
           sum(tr.qty * tr.ucost) filter (where tr.in_tr) as tr_val,
           count(*) filter (where tr.sd between p_from and p_to) as n_sent, count(*) filter (where tr.status = 'received' and tr.rd between p_from and p_to and tr.received_qty < tr.qty) as n_short,
           count(*) filter (where tr.in_tr) as n_tr
      from tr where tr.to_location_id = any (locs) group by 1, 2),
  froma as (
    select tr.from_location_id as lid, tr.item_id, coalesce(sum(tr.qty) filter (where tr.sd between p_from and p_to), 0) as sent_from
      from tr where tr.from_location_id = any (locs) group by 1, 2),
  keys as (select location_id as lid, item_id from b union select lid, item_id from toa union select lid, item_id from froma),
  z as (
    select k.lid, k.item_id, i.code, i.name_bn, i.name_en, i.unit, lo.name_bn as loc_bn, lo.name_en as loc_en, lo.kind as loc_kind,
           coalesce(b.opening, 0) as opening, coalesce(b.production, 0) as production, coalesce(b.purchases, 0) as purchases, coalesce(b.transfer_in, 0) as t_in,
           coalesce(b.transfer_ret, 0) as t_ret, coalesce(b.transfer_oth, 0) as t_oth, coalesce(b.sales, 0) as sold, coalesce(b.cust_back, 0) as back, coalesce(b.wastage, 0) as wasted,
           coalesce(b.transit_loss, 0) as t_loss, coalesce(b.used, 0) as used, coalesce(b.adjustments, 0) as adj, coalesce(b.closing, 0) as closing, coalesce(b.ledger_total, 0) as ledger_total,
           coalesce(sb.qty, 0) as bal, sb.avg_cost,
           coalesce(toa.sent_to, 0) as sent_to, coalesce(toa.received_to, 0) as received_to, coalesce(toa.short_to, 0) as short_to, coalesce(toa.tr_qty, 0) as tr_qty,
           coalesce(toa.tr_q0, 0) as tr_q0, coalesce(toa.tr_q1, 0) as tr_q1, coalesce(toa.tr_q2, 0) as tr_q2, toa.oldest_h,
           toa.sent_val, toa.recv_val, toa.short_val, toa.tr_val, coalesce(toa.n_sent, 0) as n_sent, coalesce(toa.n_short, 0) as n_short, coalesce(toa.n_tr, 0) as n_tr,
           coalesce(froma.sent_from, 0) as sent_from, coalesce(b.moves, 0) as moves
      from keys k join public.items i on i.id = k.item_id join public.locations lo on lo.id = k.lid
      left join b on b.location_id = k.lid and b.item_id = k.item_id
      left join toa on toa.lid = k.lid and toa.item_id = k.item_id left join froma on froma.lid = k.lid and froma.item_id = k.item_id
      left join public.stock_balance sb on sb.location_id = k.lid and sb.item_id = k.item_id),
  z1 as (
    select z.* from z
     where z.moves > 0 or z.opening <> 0 or z.closing <> 0 or z.n_sent > 0 or z.n_tr > 0 or z.sent_from > 0 or z.received_to > 0 or z.bal <> 0),
  z2 as (
    select z1.*, (z1.t_in - z1.received_to - z1.t_loss) as mismatch, (z1.ledger_total - z1.bal) as variance,
           (case when z1.sent_to > 0 then round(100 * z1.short_to / z1.sent_to, 2) end) as short_pct from z1)
  select count(*),
         coalesce(jsonb_agg(r.j order by r.lid, r.code) filter (where r.rn <= lim), '[]'::jsonb)
    into n_all, rows_j
  from (
    select row_number() over (order by z2.lid, z2.code) as rn, z2.lid, z2.code,
      jsonb_strip_nulls(jsonb_build_object(
        'location_id', z2.lid, 'location_bn', z2.loc_bn, 'location_en', coalesce(z2.loc_en, z2.loc_bn), 'location_kind', z2.loc_kind,
        'item_id', z2.item_id, 'item_code', z2.code, 'item_bn', z2.name_bn, 'item_en', coalesce(z2.name_en, z2.name_bn), 'unit', z2.unit,
        'opening_qty', round(z2.opening, 4), 'production_qty', round(z2.production, 4), 'purchases_qty', round(z2.purchases, 4),
        'sent_in_qty', round(z2.sent_to, 4), 'received_qty', round(z2.received_to, 4), 'short_qty', round(z2.short_to, 4), 'short_pct', z2.short_pct,
        'ledger_received_qty', round(z2.t_in, 4), 'transit_loss_qty', round(z2.t_loss, 4),
        'in_transit_qty', round(z2.tr_qty, 4), 'in_transit_age_0_qty', round(z2.tr_q0, 4), 'in_transit_age_1_qty', round(z2.tr_q1, 4), 'in_transit_age_2_qty', round(z2.tr_q2, 4),
        'oldest_transit_hours', round(z2.oldest_h::numeric, 1),
        'sent_out_qty', round(z2.sent_from, 4), 'returned_qty', round(z2.t_ret, 4), 'other_transfer_out_qty', round(z2.t_oth, 4),
        'sold_qty', round(z2.sold, 4), 'give_back_qty', round(z2.back, 4), 'wasted_qty', round(z2.wasted, 4), 'used_qty', round(z2.used, 4), 'adjustments_qty', round(z2.adj, 4),
        'remaining_qty', round(z2.closing, 4), 'balance_qty', round(z2.bal, 4), 'variance_qty', round(z2.variance, 4), 'receive_mismatch_qty', round(z2.mismatch, 4),
        'flags', (select coalesce(jsonb_agg(f), '[]'::jsonb) from unnest(array[case when z2.short_to > 0 then 'short' end, case when z2.tr_q2 > 0 then 'transit_old' end,
                                                                               case when abs(z2.mismatch) > 0.0005 then 'receive_mismatch' end, case when abs(z2.variance) > 0.0005 then 'variance' end]) f where f is not null),
        'sent_value', case when cost_ok then round(z2.sent_val, 2) end, 'received_value', case when cost_ok then round(z2.recv_val, 2) end,
        'short_value', case when cost_ok then round(z2.short_val, 2) end, 'in_transit_value', case when cost_ok then round(z2.tr_val, 2) end,
        'avg_cost', case when cost_ok then round(z2.avg_cost, 4) end, 'remaining_value', case when cost_ok and z2.avg_cost is not null then round(z2.closing * z2.avg_cost, 2) end)) as j
      from z2) r;
  -- per location totals: counts always, values only for cost holders (quantities of different units are never added)
  with tr0 as (
    select t.*, (t.sent_at at time zone 'Asia/Dhaka')::date as sd, (t.received_at at time zone 'Asia/Dhaka')::date as rd
      from public.stock_transfers t join public.items i on i.id = t.item_id
     where t.status <> 'cancelled' and t.sent_at < e_end and t.to_location_id = any (locs) and (p_item is null or t.item_id = p_item) and (p_category is null or i.category = p_category)),
  uc as (
    select sl.ref_id as tid, sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) / nullif(sum(-sl.qty_delta), 0) as cost
      from public.stock_ledger sl where sl.ref_type = 'transfer' and sl.reason = 'transfer_out' and sl.reverses_id is null and sl.ref_id in (select id::text from tr0) group by 1),
  a as (
    select t.to_location_id as lid, count(*) filter (where t.sd between p_from and p_to) as n_sent,
           count(*) filter (where t.status = 'received' and t.rd between p_from and p_to and t.received_qty < t.qty) as n_short,
           count(*) filter (where t.status = 'sent' or t.received_at >= e_end) as n_transit,
           sum(t.qty * uc.cost) filter (where t.sd between p_from and p_to) as sent_val,
           sum(t.received_qty * uc.cost) filter (where t.status = 'received' and t.rd between p_from and p_to) as recv_val,
           sum((t.qty - t.received_qty) * uc.cost) filter (where t.status = 'received' and t.rd between p_from and p_to and t.received_qty < t.qty) as short_val,
           sum(t.qty * uc.cost) filter (where t.status = 'sent' or t.received_at >= e_end) as transit_val
      from tr0 t left join uc on uc.tid = t.id::text group by 1)
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('location_id', lo.id, 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
           'transfers_sent', a.n_sent, 'transfers_short', a.n_short, 'transfers_in_transit', a.n_transit,
           'sent_value', case when cost_ok then round(a.sent_val, 2) end, 'received_value', case when cost_ok then round(a.recv_val, 2) end,
           'short_value', case when cost_ok then round(a.short_val, 2) end, 'in_transit_value', case when cost_ok then round(a.transit_val, 2) end,
           'short_pct_of_value', case when cost_ok and a.sent_val > 0 then round(100 * coalesce(a.short_val, 0) / a.sent_val, 2) end)) order by lo.id), '[]'::jsonb)
    into byloc from a join public.locations lo on lo.id = a.lid;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_ids', to_jsonb(locs), 'cost_visible', cost_ok, 'ageing_hours', jsonb_build_array(b1, b2),
    'rows', rows_j, 'row_count', n_all, 'truncated', n_all > lim, 'by_location', byloc,
    'formula', 'remaining = opening + received + purchases + production + give_backs - returned - other_transfers_out - sold - wasted - transit_loss - used +/- adjustments');
end $$;

-- ---------- 3. net profit report ----------
create or replace function public.net_profit_report(p_from date, p_to date, p_loc integer default null, p_category text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
-- bos118 (A3 G13 / C19 / C20). Branch = net sales (after discount and returns) - cost of goods = gross profit (COSTED part only) - wastage and transit loss at ledger cost
-- - card fees - variable expenses = CONTRIBUTION MARGIN; - other expenses - salary sheet 02-2 - monthly fixed cost - attributed shared bills (pro-rated by days) = NET PROFIT AFTER OVERHEAD.
-- Revenue with no known cost is shown as uncosted_sales and is NOT in any profit figure. Product view: the same lines per item; fees, variable expenses and overhead of a branch
-- are shared out to its products by the product's share of that branch's net sales (an allocation, labelled as such), so product profits add up to the branch profit.
-- Needs the grant view_net_profit AND biz_cost_ok().
declare locs integer[]; vh text[]; br jsonb; pr jsonb; pb jsonb; unal numeric; total jsonb; rcs text;
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_period'; end if;
  if p_to - p_from > 370 then raise exception 'period_too_long'; end if;
  if not public.biz_cost_ok() then raise exception 'not allowed'; end if;
  locs := public._rc118_locs('view_net_profit', p_loc);
  vh := coalesce((select array_agg(btrim(x)) from unnest(string_to_array(coalesce(public.rule_val('profit_variable_heads') #>> '{}', ''), ',')) x where btrim(x) <> ''), '{}');
  rcs := public._rcs88();
  with cl as (
    select h.loc, h.item_id,
           sum((case h.src when 'sale' then 1 else -1 end) * h.qty) as qty, sum((case h.src when 'sale' then 1 else -1 end) * h.rev) as net,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.rev - h.unk_rev)) as costed, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as cogs,
           sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev) as unk
      from public._cogs_lines72(p_from, p_to, locs) h left join public.items i on i.id = h.item_id
     where p_category is null or i.category = p_category group by 1, 2),
  wc as (
    select sl.location_id as loc, sl.item_id, sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) as cost, coalesce(sum(-sl.qty_delta) filter (where coalesce(sl.unit_cost, 0) = 0), 0) as unc_qty
      from public.stock_ledger sl join public.items i on i.id = sl.item_id
     where sl.reason in ('wastage', 'transit_loss') and sl.reverses_id is null and not exists (select 1 from public.stock_ledger r where r.reverses_id = sl.id)
       and (sl.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to and sl.location_id = any (locs) and (p_category is null or i.category = p_category) group by 1, 2),
  fee as (select c.location_id as loc, sum(c.fee) as fee from public.card_settlements85 c where c.status = 'done' and c.settle_date between p_from and p_to and c.location_id = any (locs) group by 1),
  vx as (
    select u.loc, sum(u.amt) as amt from (
      select q.location_id as loc, q.amount as amt from public.quick_expenses q where q.status = 'done' and q.exp_date between p_from and p_to and q.location_id = any (locs) and q.head = any (vh)
      union all
      select e.location_id, public._r2_num(ln -> 'amount') from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
       where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) and e.entry_date between p_from and p_to
         and e.location_id = any (locs) and (ln ->> 'head') = any (vh)) u group by 1),
  pl as (select o_loc as loc, sum(o_exp) as ex, sum(o_sal) as sal, sum(o_fixed) as fx, bool_or(o_sal is not null) as has_sal from public._p27_pl(p_from, p_to, locs) group by 1),
  sh as (
    select r.dloc as loc, sum(r.amount * ((least(p_to, (r.mth + interval '1 month')::date - 1) - greatest(p_from, r.mth) + 1)::numeric / ((r.mth + interval '1 month')::date - r.mth))) as amt
      from public._c78_rows(p_from, p_to) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1),
  keys as (select loc from cl union select loc from wc union select loc from fee union select loc from vx union select loc from pl union select loc from sh),
  b as (
    select k.loc, coalesce(c.net, 0) as net, coalesce(c.costed, 0) as costed, coalesce(c.unk, 0) as unk, coalesce(c.cogs, 0) as cogs, coalesce(c.qty, 0) as qty,
           coalesce(w.cost, 0) as wcost, coalesce(w.unc, 0) as wunc, coalesce(f.fee, 0) as fee, coalesce(v.amt, 0) as vexp,
           greatest(coalesce(p.ex, 0) - coalesce(v.amt, 0), 0) as oexp, coalesce(p.sal, 0) as sal, coalesce(p.fx, 0) as fx, coalesce(s.amt, 0) as shr, coalesce(p.has_sal, false) as has_sal
      from keys k
      left join (select loc, sum(net) net, sum(costed) costed, sum(unk) unk, sum(cogs) cogs, sum(qty) qty from cl group by loc) c on c.loc = k.loc
      left join (select loc, sum(cost) cost, sum(unc_qty) unc from wc group by loc) w on w.loc = k.loc
      left join fee f on f.loc = k.loc left join vx v on v.loc = k.loc left join pl p on p.loc = k.loc left join sh s on s.loc = k.loc),
  b2 as (
    select b.*, (b.costed - b.cogs) as gp, (b.costed - b.cogs - b.wcost - b.fee - b.vexp) as cm, (b.oexp + b.sal + b.fx + b.shr) as oh,
           (b.costed - b.cogs - b.wcost - b.fee - b.vexp - b.oexp - b.sal - b.fx - b.shr) as np from b),
  pb0 as (
    select k.loc, k.item_id, coalesce(c.qty, 0) as qty, coalesce(c.net, 0) as net, coalesce(c.costed, 0) as costed, coalesce(c.unk, 0) as unk, coalesce(c.cogs, 0) as cogs,
           coalesce(w.cost, 0) as wcost, coalesce(w.unc_qty, 0) as wunc
      from (select loc, item_id from cl union select loc, item_id from wc) k
      left join cl c on c.loc = k.loc and c.item_id is not distinct from k.item_id left join wc w on w.loc = k.loc and w.item_id is not distinct from k.item_id),
  pb as (
    select p.*, i.code, i.name_bn, i.name_en, i.category,
           (b2.fee + b2.vexp) * (case when b2.net > 0 then p.net / b2.net else 0 end) as var_alloc,
           b2.oh * (case when b2.net > 0 then p.net / b2.net else 0 end) as oh_alloc
      from pb0 p join b2 on b2.loc = p.loc left join public.items i on i.id = p.item_id),
  pb2 as (
    select pb.*, (pb.costed - pb.cogs - pb.wcost - pb.var_alloc) as cm, (pb.costed - pb.cogs - pb.wcost - pb.var_alloc - pb.oh_alloc) as np from pb)
  select
    (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'location_id', lo.id, 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
        'net_sales', round(b2.net, 2), 'costed_sales', round(b2.costed, 2), 'uncosted_sales', round(b2.unk, 2),
        'uncosted_pct', case when b2.net > 0 then round(100 * b2.unk / b2.net, 2) end,
        'cogs', round(b2.cogs, 2), 'gross_profit', round(b2.gp, 2), 'gross_margin_pct', case when b2.costed > 0 then round(100 * b2.gp / b2.costed, 2) end,
        'wastage_cost', round(b2.wcost, 2), 'wastage_uncosted_qty', round(b2.wunc, 4), 'card_fees', round(b2.fee, 2), 'variable_expenses', round(b2.vexp, 2),
        'contribution_margin', round(b2.cm, 2), 'contribution_pct', case when b2.costed > 0 then round(100 * b2.cm / b2.costed, 2) end,
        'other_expenses', round(b2.oexp, 2), 'salary', round(b2.sal, 2), 'fixed_monthly', round(b2.fx, 2), 'shared_costs', round(b2.shr, 2),
        'overhead_total', round(b2.oh, 2), 'net_profit', round(b2.np, 2), 'net_profit_pct', case when b2.costed > 0 then round(100 * b2.np / b2.costed, 2) end,
        'complete', (b2.unk = 0 and b2.has_sal),
        'gaps', (select coalesce(jsonb_agg(g), '[]'::jsonb) from unnest(array[case when b2.unk <> 0 then 'uncosted_sales' end, case when not b2.has_sal then 'salary_not_recorded' end,
                                                                               case when b2.wunc > 0 then 'wastage_uncosted' end]) g where g is not null))) order by lo.id), '[]'::jsonb)
       from b2 join public.locations lo on lo.id = b2.loc),
    (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'item_id', q.item_id, 'item_code', coalesce(q.code, 'no_item'), 'item_bn', q.name_bn, 'item_en', coalesce(q.name_en, q.name_bn), 'category', q.category,
        'qty', round(q.qty, 4), 'net_sales', round(q.net, 2), 'costed_sales', round(q.costed, 2), 'uncosted_sales', round(q.unk, 2), 'cogs', round(q.cogs, 2),
        'gross_profit', round(q.costed - q.cogs, 2), 'gross_margin_pct', case when q.costed > 0 then round(100 * (q.costed - q.cogs) / q.costed, 2) end,
        'wastage_cost', round(q.wcost, 2), 'allocated_variable', round(q.var_alloc, 2), 'contribution_margin', round(q.cm, 2),
        'contribution_pct', case when q.costed > 0 then round(100 * q.cm / q.costed, 2) end,
        'allocated_overhead', round(q.oh_alloc, 2), 'net_profit', round(q.np, 2), 'net_profit_pct', case when q.costed > 0 then round(100 * q.np / q.costed, 2) end,
        'cost_complete', (q.unk = 0))) order by q.net desc, q.code), '[]'::jsonb)
       from (select p.item_id, p.code, p.name_bn, p.name_en, p.category, sum(p.qty) qty, sum(p.net) net, sum(p.costed) costed, sum(p.unk) unk, sum(p.cogs) cogs, sum(p.wcost) wcost,
                    sum(p.var_alloc) var_alloc, sum(p.oh_alloc) oh_alloc, sum(p.cm) cm, sum(p.np) np
               from pb2 p group by p.item_id, p.code, p.name_bn, p.name_en, p.category) q),
    (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'location_id', p.loc, 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_id', p.item_id, 'item_code', coalesce(p.code, 'no_item'),
        'item_bn', p.name_bn, 'item_en', coalesce(p.name_en, p.name_bn), 'category', p.category, 'qty', round(p.qty, 4), 'net_sales', round(p.net, 2), 'costed_sales', round(p.costed, 2),
        'uncosted_sales', round(p.unk, 2), 'cogs', round(p.cogs, 2), 'gross_profit', round(p.costed - p.cogs, 2), 'wastage_cost', round(p.wcost, 2),
        'allocated_variable', round(p.var_alloc, 2), 'contribution_margin', round(p.cm, 2), 'allocated_overhead', round(p.oh_alloc, 2), 'net_profit', round(p.np, 2),
        'cost_complete', (p.unk = 0))) order by p.loc, p.net desc, p.code), '[]'::jsonb)
       from pb2 p join public.locations lo on lo.id = p.loc),
    (select coalesce(sum(r.amount * ((least(p_to, (r.mth + interval '1 month')::date - 1) - greatest(p_from, r.mth) + 1)::numeric / ((r.mth + interval '1 month')::date - r.mth))), 0)
       from public._c78_rows(p_from, p_to) r where r.dkind = 'unallocated' and r.share_loc = any (locs)),
    (select jsonb_build_object('net_sales', round(coalesce(sum(net), 0), 2), 'costed_sales', round(coalesce(sum(costed), 0), 2), 'uncosted_sales', round(coalesce(sum(unk), 0), 2),
        'cogs', round(coalesce(sum(cogs), 0), 2), 'gross_profit', round(coalesce(sum(gp), 0), 2), 'contribution_margin', round(coalesce(sum(cm), 0), 2),
        'overhead_total', round(coalesce(sum(oh), 0), 2), 'net_profit', round(coalesce(sum(np), 0), 2)) from b2)
    into br, pr, pb, unal, total;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_ids', to_jsonb(locs), 'category', p_category,
    'branches', br, 'products', pr, 'product_branch', pb, 'company', coalesce(total, '{}'::jsonb) || jsonb_build_object('unallocated_shared_costs', round(coalesce(unal, 0), 2)),
    'cost_source', rcs, 'variable_heads', to_jsonb(vh),
    'included', jsonb_build_array('net_sales_after_discount_and_returns', 'cogs_from_stock_ledger_cost', 'wastage_and_transit_loss_at_ledger_cost', 'card_fees_by_settlement_date',
      'variable_expense_heads', 'other_expenses_quick_and_form_10_2', 'salary_sheet_02_2', 'monthly_fixed_cost', 'shared_bills_attributed_pro_rated_by_days'),
    'not_included', jsonb_build_array('profit_on_sales_with_unknown_cost', 'payroll_app_payments', 'shared_bills_not_attributed_to_a_place', 'online_delivery_charge',
      'depreciation_and_other_books_only_entries', 'product_conversion_cost_when_factory_costing_is_off'),
    'allocation', 'product fees, variable expenses and overhead = branch amount x product share of the branch net sales');
end $$;

-- ---------- CSV export audit ----------
create or replace function public.recon_export_log118(p_key text, p_rows integer default 0, p_filters jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb); need text;
begin
  if p_key is null or p_key not in ('stock_recon', 'sales_unmatched', 'factory_branch', 'net_profit_branch', 'net_profit_product') then raise exception 'unknown_report'; end if;
  need := case when p_key in ('stock_recon', 'sales_unmatched') then 'view_stock_recon' when p_key = 'factory_branch' then 'view_branch_statement' else 'view_net_profit' end;
  if not public.is_active() or not (public.is_owner() or (public.has_grant(need) and public.rpt_grant('export_data') and (need <> 'view_net_profit' or public.biz_cost_ok()))) then raise exception 'not allowed'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'recon_report', p_key, jsonb_build_object('kind', 'csv', 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges ----------
revoke all on function public._rc118_locs(text, integer), public._rc118_buckets(date, date, integer[], uuid, text), public._rc118_gap(date, date, integer[], uuid),
  public._rc118_gap_summary(date, date, integer[], uuid) from public, anon, authenticated;
revoke all on function public.stock_recon_statement(date, date, integer, uuid, text, integer), public.stock_sales_unmatched(date, date, integer, uuid, integer),
  public.factory_branch_statement(date, date, integer, uuid, text, integer), public.net_profit_report(date, date, integer, text),
  public.recon_export_log118(text, integer, jsonb) from public, anon;
grant execute on function public.stock_recon_statement(date, date, integer, uuid, text, integer), public.stock_sales_unmatched(date, date, integer, uuid, integer),
  public.factory_branch_statement(date, date, integer, uuid, text, integer), public.net_profit_report(date, date, integer, text),
  public.recon_export_log118(text, integer, jsonb) to authenticated;

commit;
