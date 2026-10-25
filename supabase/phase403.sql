-- Phase 403 (bos403) - THREE REPORTS A SWEETS / BAKERY BUSINESS NEEDS (package RPT-B1, item 5). Paste after phase402. Paste-twice safe. Earlier phase files are not edited.
-- Matched by PURPOSE against the existing reports first (docs/integration/RPT-B1.md, table "Why these three"): none of them exists today.
--   y1_daily_sellout     Daily sell-out / unsold at closing, per outlet, per item, per day. Opening + produced + received against sold, wasted, sent and what is left at closing, the sell-through %
--                        and the cost of the wastage of the day. Source: the stock ledger (the one truth for stock). k3_store_ledger gives period totals per kind, not the day, and no closing.
--   y2_festival_compare  The same items over the dates you pick against the same dates one year earlier (or other dates you choose), quantity and sales after returns, with a plain "no previous data" state.
--                        Source: the sales lines (sales_fact) and the returns (rpt_ret_l, phase 400). The report hub compares whole periods and totals, not item by item with an empty-last-year state.
--   y3_customer_items    What each of the top customers buys: the top N customers by sales (setting report_top_customers_n, blank = 10) and their items. Source: sales lines with a customer, returns.
--                        best_customers lists customers, not their items.
-- All three are engine-3 reports (report_defs3 + one _r3q_ function each): date and place filters, paging, CSV, print and the phone layout come from the report viewer. Every row carries _drill, and
-- report_drill(key, ref) returns the TRANSACTIONS behind a row (ledger movements, sale lines) so a number can be traced to its source. Read-only: nothing here writes to a business table.
-- Never an estimate: an item that is not stock-tracked is named in a "not captured" note (y1); a year with no sales is "no previous data", not 0 (y2); sales with no customer are counted and said (y3).
-- Open to the roles that already hold the group grant (report_stock, report_sales, report_customers). The cost of wastage is shown only to holders of the cost right.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._rptb1_p402_present()') is null then raise exception 'phase403 needs phase402 (and 400, 401) first'; end if;
  if to_regclass('public.rpt_ret_l') is null or to_regclass('public.report_defs3') is null or to_regprocedure('public._r2_locs(jsonb)') is null or to_regclass('public.sales_fact') is null then
    raise exception 'phase403 needs the report engines (phases 9, 21, 24) and phase 400';
  end if;
end $g$;

create or replace function public._rptb1_p403_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- setting (owner): how many top customers y3 lists. Blank = 10. ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('report_top_customers_n', 'reports', 'number', null, 'customers', null, 1, 200,
  'Report: how many top customers "What the top customers buy" lists', 'Report: how many top customers "What the top customers buy" lists', 'Report: how many top customers "What the top customers buy" lists',
  'Top customers are ranked by their sales in the chosen dates. Blank = 10.', 'Top customers are ranked by their sales in the chosen dates. Blank = 10.', 'Top customers are ranked by their sales in the chosen dates. Blank = 10.', 881)
 on conflict (key) do nothing;

-- ---------- y1: daily sell-out / unsold at closing ----------
create or replace function public._r3q_y1_daily_sellout(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare cats text[] := public.rpt_arr_text(flt -> 'categories'); its uuid[] := public.rpt_arr_uuid(flt -> 'items'); cost_ok boolean := public.rpt_cost_ok();
        t1 timestamptz := (d1::timestamp at time zone 'Asia/Dhaka'); t2 timestamptz := ((d2 + 1)::timestamp at time zone 'Asia/Dhaka');
begin
  return query
  with it as (select i.id, i.code, i.name_bn, i.name_en, i.unit from public.items i
               where i.tracked and (cats is null or i.category = any (cats)) and (its is null or i.id = any (its))),
  base as (select l.location_id, l.item_id, sum(l.qty_delta) as q from public.stock_ledger l join it on it.id = l.item_id
            where l.location_id = any (locs) and l.made_at < t1 group by 1, 2),
  mv as (
    select l.location_id, l.item_id, (l.made_at at time zone 'Asia/Dhaka')::date as d,
      coalesce(sum(l.qty_delta) filter (where l.reason = 'production_in'), 0) as produced,
      coalesce(sum(l.qty_delta) filter (where l.reason = 'transfer_in'), 0) as received,
      coalesce(sum(l.qty_delta) filter (where l.reason = 'sale_return'), 0) as returned,
      coalesce(-sum(l.qty_delta) filter (where l.reason in ('sale_out', 'sale_void_in')), 0) as sold,
      coalesce(-sum(l.qty_delta) filter (where l.reason = 'wastage'), 0) as wasted,
      coalesce(-sum(l.qty_delta) filter (where l.reason = 'transfer_out'), 0) as sent,
      coalesce(sum(l.qty_delta) filter (where l.reason not in ('production_in', 'transfer_in', 'sale_return', 'sale_out', 'sale_void_in', 'wastage', 'transfer_out')), 0) as other,
      sum(l.qty_delta) as total,
      sum(-l.qty_delta * l.unit_cost) filter (where l.reason = 'wastage' and coalesce(l.unit_cost, 0) > 0) as w_cost,
      count(*) filter (where l.reason = 'wastage' and coalesce(l.unit_cost, 0) <= 0) as w_nocost
      from public.stock_ledger l join it on it.id = l.item_id
     where l.location_id = any (locs) and l.made_at >= t1 and l.made_at < t2
     group by 1, 2, 3),
  cu as (select mv.*, coalesce(b.q, 0) + sum(mv.total) over (partition by mv.location_id, mv.item_id order by mv.d) as closing
           from mv left join base b on b.location_id = mv.location_id and b.item_id = mv.item_id)
  select jsonb_build_object('day', cu.d, 'location_id', cu.location_id, 'location_bn', lo.name_bn, 'item_code', it.code, 'item_bn', it.name_bn, 'unit', it.unit,
      'opening', round(cu.closing - cu.total, 4), 'produced', round(cu.produced, 4), 'received', round(cu.received, 4), 'returned', round(cu.returned, 4),
      'sold', round(cu.sold, 4), 'wasted', round(cu.wasted, 4), 'sent', round(cu.sent, 4), 'other', round(cu.other, 4), 'closing', round(cu.closing, 4),
      'sell_through_pct', case when (cu.closing - cu.total) + cu.produced + cu.received > 0 then round(100 * (cu.sold - cu.returned) / ((cu.closing - cu.total) + cu.produced + cu.received), 1) end,
      'waste_cost', case when not cost_ok then null when cu.wasted = 0 then 0 when cu.w_nocost > 0 then null else round(cu.w_cost, 2) end,
      '_drill', jsonb_build_object('day', cu.d, 'loc', cu.location_id, 'item', it.id))
    from cu join it on it.id = cu.item_id join public.locations lo on lo.id = cu.location_id;
end $$;

-- ---------- y2: festival / season comparison ----------
create or replace function public._r3q_y2_festival_compare(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare cats text[] := public.rpt_arr_text(flt -> 'categories'); its uuid[] := public.rpt_arr_uuid(flt -> 'items');
        pf date := coalesce(public.rpt_date(flt ->> 'prev_from'), (d1 - interval '1 year')::date); pt date := coalesce(public.rpt_date(flt ->> 'prev_to'), (d2 - interval '1 year')::date);
        net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true); anyprev boolean;
begin
  if pt < pf or pt - pf > 365 then raise exception 'bad_range'; end if;
  anyprev := exists (select 1 from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.day between pf and pt);
  return query
  with k as (
    select 'cur'::text as per, f.item_id, f.qty, f.net from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.day between d1 and d2
    union all select 'prev', f.item_id, f.qty, f.net from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.day between pf and pt
    union all select 'cur', r.item_id, -r.qty, -r.ret_amt from public.rpt_ret_l r where net_on and r.location_id = any (locs) and r.day between d1 and d2
    union all select 'prev', r.item_id, -r.qty, -r.ret_amt from public.rpt_ret_l r where net_on and r.location_id = any (locs) and r.day between pf and pt),
  agg as (
    select k.item_id,
      sum(k.qty) filter (where k.per = 'cur') as qn, sum(k.net) filter (where k.per = 'cur') as nn,
      sum(k.qty) filter (where k.per = 'prev') as qp, sum(k.net) filter (where k.per = 'prev') as np
      from k left join public.items i on i.id = k.item_id
     where (cats is null or i.category = any (cats)) and (its is null or k.item_id = any (its))
     group by k.item_id)
  select jsonb_build_object('item_code', coalesce(i.code, 'quick'), 'item_bn', coalesce(i.name_bn, 'Quick / unlisted sales (no item)'), 'category', i.category, 'unit', i.unit,
      'qty_now', round(coalesce(a.qn, 0), 3), 'net_now', round(coalesce(a.nn, 0), 2),
      'qty_prev', case when anyprev then round(coalesce(a.qp, 0), 3) end, 'net_prev', case when anyprev then round(coalesce(a.np, 0), 2) end,
      'qty_change', case when anyprev then round(coalesce(a.qn, 0) - coalesce(a.qp, 0), 3) end,
      'qty_change_pct', case when anyprev and coalesce(a.qp, 0) > 0 then round(100 * (coalesce(a.qn, 0) - a.qp) / a.qp, 1) end,
      'net_change_pct', case when anyprev and coalesce(a.np, 0) > 0 then round(100 * (coalesce(a.nn, 0) - a.np) / a.np, 1) end,
      'state', case when not anyprev then 'আগের তথ্য নেই / no previous data'
                    when coalesce(case when a.item_id is null then a.np else a.qp end, 0) <= 0 and coalesce(case when a.item_id is null then a.nn else a.qn end, 0) > 0 then 'গত বছর বিক্রি হয়নি / not sold last year'
                    when coalesce(case when a.item_id is null then a.nn else a.qn end, 0) <= 0 and coalesce(case when a.item_id is null then a.np else a.qp end, 0) > 0 then 'এবার বিক্রি হয়নি / not sold this time'
                    when coalesce(case when a.item_id is null then a.nn else a.qn end, 0) > coalesce(case when a.item_id is null then a.np else a.qp end, 0) then 'বেড়েছে / up'
                    when coalesce(case when a.item_id is null then a.nn else a.qn end, 0) < coalesce(case when a.item_id is null then a.np else a.qp end, 0) then 'কমেছে / down' else 'একই / same' end,
      '_drill', jsonb_build_object('item', a.item_id, 'from', d1, 'to', d2, 'pf', pf, 'pt', pt))
    from agg a left join public.items i on i.id = a.item_id;
end $$;

-- ---------- y3: what the top customers buy ----------
create or replace function public._r3q_y3_customer_items(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare n int := least(greatest(coalesce(public.rule_num('report_top_customers_n'), 10), 1), 200)::int; cust uuid[] := public.rpt_arr_uuid(flt -> 'customer');
        mob_ok boolean := public.rpt_mobile_ok(); net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
begin
  return query
  with k as (
    select f.customer_id, f.item_id, f.sale_id, f.day, f.qty, f.net from public.sales_fact f
     where f.status = 'done' and f.customer_id is not null and f.item_id is not null and f.location_id = any (locs) and f.day between d1 and d2 and (cust is null or f.customer_id = any (cust))
    union all
    select r.customer_id, r.item_id, null, null, -r.qty, -r.ret_amt from public.rpt_ret_l r
     where net_on and r.customer_id is not null and r.item_id is not null and r.location_id = any (locs) and r.day between d1 and d2 and (cust is null or r.customer_id = any (cust))),
  ci as (select k.customer_id, k.item_id, sum(k.qty) as qty, sum(k.net) as net, count(distinct k.sale_id) as bills, max(k.day) as last_day from k group by 1, 2),
  ct as (select ci.customer_id, sum(ci.net) as cnet, dense_rank() over (order by sum(ci.net) desc, ci.customer_id) as rk from ci group by ci.customer_id),
  top as (select * from ct where rk <= n)
  select jsonb_build_object('rank', top.rk, 'customer_name', coalesce(cu.name, '-'),
      'mobile', case when mob_ok then cu.mobile else left(cu.mobile, 3) || '****' || right(cu.mobile, 2) end,
      'customer_net', round(top.cnet, 2), 'item_code', it.code, 'item_bn', it.name_bn, 'unit', it.unit,
      'qty', round(ci.qty, 3), 'net', round(ci.net, 2), 'share_pct', case when top.cnet > 0 then round(100 * ci.net / top.cnet, 1) end, 'bills', ci.bills, 'last_bought', ci.last_day,
      '_drill', jsonb_build_object('customer', ci.customer_id, 'item', ci.item_id, 'from', d1, 'to', d2))
    from top join ci on ci.customer_id = top.customer_id join public.items it on it.id = ci.item_id left join public.customers cu on cu.id = top.customer_id
   where ci.qty <> 0 or ci.net <> 0;
end $$;

-- ---------- notes under the three reports (called by _rptb1_r3_notes, phase 401) ----------
create or replace function public._rptb1_y_notes(p_key text, d1 date, d2 date, locs int[], flt jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; n_items int; q numeric; n_quick int; a_quick numeric; pf date; pt date; anyprev boolean; tot numeric; withc numeric; cats text[] := public.rpt_arr_text(flt -> 'categories');
        net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true); nn int;
begin
  if p_key = 'y1_daily_sellout' then
    select count(distinct f.item_id), coalesce(sum(f.qty), 0) into n_items, q from public.sales_fact f join public.items i on i.id = f.item_id
     where f.status = 'done' and f.location_id = any (locs) and f.day between d1 and d2 and not i.tracked and (cats is null or i.category = any (cats));
    select count(*), coalesce(sum(f.net), 0) into n_quick, a_quick from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.day between d1 and d2 and f.item_id is null and cats is null;
    if n_items > 0 or n_quick > 0 then
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'not_captured', 'what', 'untracked_items', 'items', n_items, 'quick_lines', n_quick,
        'text_en', 'Not in this report: ' || n_items || ' item(s) sold in these dates are not stock-tracked (quantity sold ' || q::text || ')' || case when n_quick > 0 then ' and ' || n_quick || ' quick / unlisted line(s) (' || round(a_quick, 2)::text || ') have no item' else '' end
                   || '. Their stock is not counted, so nothing can be said about what was left. Needed: switch stock tracking on for the item (item master, "tracked") and enter an opening stock; sell quick items from the item list.',
        'text_bn', 'এই রিপোর্টে নেই: এই সময়ে বিক্রি হওয়া ' || n_items || 'টি আইটেমের স্টক গোনা হয় না (বিক্রির পরিমাণ ' || q::text || ')' || case when n_quick > 0 then ' এবং ' || n_quick || 'টি কুইক/তালিকা-বহির্ভূত লাইনে (' || round(a_quick, 2)::text || ') আইটেম নেই' else '' end
                   || '। তাই কত বাকি ছিল বলা যায় না। দরকার: আইটেম মাস্টারে স্টক গোনা চালু করা ("tracked") ও শুরুর স্টক দেওয়া; কুইক আইটেম তালিকা থেকে বিক্রি করা।'));
    end if;
    if not public.rpt_cost_ok() then
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'cost_hidden', 'text_en', 'The cost of wastage is hidden for your role', 'text_bn', 'অপচয়ের খরচ আপনার ভূমিকার জন্য ঢাকা'));
    end if;
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'sellout_basis',
      'text_en', 'Left at closing = opening + produced + received + returned - sold - wasted - sent + other (counts, purchases, corrections). Sell-through % = (sold - returned) / (opening + produced + received). One row per day, place and item that had any stock movement.',
      'text_bn', 'দিনের শেষে বাকি = শুরু + তৈরি + গৃহীত + ফেরত − বিক্রি − নষ্ট − পাঠানো + অন্যান্য (গণনা, ক্রয়, সংশোধন)। বিক্রির হার % = (বিক্রি − ফেরত) / (শুরু + তৈরি + গৃহীত)। যে দিন, জায়গা ও আইটেমে স্টকের নড়াচড়া হয়েছে তার জন্য একটি সারি।'));
  elsif p_key = 'y2_festival_compare' then
    pf := coalesce(public.rpt_date(flt ->> 'prev_from'), (d1 - interval '1 year')::date); pt := coalesce(public.rpt_date(flt ->> 'prev_to'), (d2 - interval '1 year')::date);
    anyprev := exists (select 1 from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.day between pf and pt);
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'compare_range', 'from', pf, 'to', pt,
      'text_en', 'Compared with ' || pf::text || ' to ' || pt::text || ' (the same dates one year earlier unless you chose other dates in "Compare with"). Quantity and sales ' || case when net_on then 'are after returns.' else 'are before returns (the setting "Sales figures are net of sale returns" is off).' end,
      'text_bn', pf::text || ' থেকে ' || pt::text || ' এর সাথে তুলনা (এক বছর আগের একই তারিখ, "Compare with"-এ অন্য তারিখ না দিলে)। পরিমাণ ও বিক্রি ' || case when net_on then 'ফেরত বাদে।' else 'ফেরত বাদ দেওয়ার আগে ("বিক্রির হিসাব থেকে বিক্রি-ফেরত বাদ" নিয়ম বন্ধ)।' end));
    if not anyprev then
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'not_captured', 'what', 'previous_sales',
        'text_en', 'No sales were recorded between ' || pf::text || ' and ' || pt::text || ' at the chosen places, so there is nothing to compare with and no previous figure is shown (not 0). The shop may not have used the app then. Needed: sales of that period in the app, or choose other dates in "Compare with".',
        'text_bn', pf::text || ' থেকে ' || pt::text || ' পর্যন্ত বাছা জায়গায় কোনো বিক্রি লেখা নেই, তাই তুলনা করার কিছু নেই; আগের কোনো সংখ্যা (০ নয়) দেখানো হয়নি। তখন হয়তো অ্যাপ ব্যবহার হয়নি। দরকার: সেই সময়ের বিক্রি অ্যাপে থাকা, অথবা "Compare with"-এ অন্য তারিখ বাছা।'));
    end if;
  elsif p_key = 'y3_customer_items' then
    select coalesce(sum(f.net), 0), coalesce(sum(f.net) filter (where f.customer_id is not null), 0) into tot, withc from public.sales_fact f
     where f.status = 'done' and f.location_id = any (locs) and f.day between d1 and d2;
    if tot > 0 and withc < tot then
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'customer_coverage', 'no_customer_rev', round(tot - withc, 2), 'pct', round(100 * (tot - withc) / tot, 1),
        'text_en', round(tot - withc, 2)::text || ' (' || round(100 * (tot - withc) / tot, 1)::text || ' %) of the sales in these dates have no customer recorded (walk-in), so they cannot be in this list. Only sales with a customer on the receipt are analysed.',
        'text_bn', 'এই সময়ের ' || round(tot - withc, 2)::text || ' টাকা (' || round(100 * (tot - withc) / tot, 1)::text || ' %) বিক্রিতে গ্রাহক লেখা নেই (সরাসরি ক্রেতা), তাই এই তালিকায় আসেনি। শুধু রসিদে গ্রাহক থাকা বিক্রি দেখা হয়।'));
    end if;
    nn := least(greatest(coalesce(public.rule_num('report_top_customers_n'), 10), 1), 200)::int;
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'top_n', 'n', nn,
      'text_en', 'The top ' || nn || ' customers by sales in these dates' || case when net_on then ' (after returns)' else '' end || '. The number is the setting "Report: how many top customers ... lists" (blank = 10).',
      'text_bn', 'এই সময়ে বিক্রি অনুযায়ী সেরা ' || nn || ' জন গ্রাহক' || case when net_on then ' (ফেরত বাদে)' else '' end || '। সংখ্যাটি নিয়ম "Report: how many top customers ... lists" (ফাঁকা = ১০)।'));
  end if;
  return out_;
end $$;

-- ---------- registry rows ----------
insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('y1_daily_sellout', 'Y1', 'stock', 'দৈনিক বিক্রি-শেষ / অবিক্রীত (আউটলেট ও আইটেম)', 'Daily sell-out / unsold at closing', 'দৈনিক sell-out / অবিক্রীত',
  '[["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["unit","একক","Unit","text"],["opening","শুরুতে","Opening","num"],["produced","তৈরি","Produced","num"],["received","গৃহীত","Received","num"],["returned","ফেরত (গ্রাহক)","Returned by customers","num"],["sold","বিক্রি","Sold","num"],["wasted","নষ্ট","Wasted","num"],["sent","পাঠানো","Sent out","num"],["other","অন্যান্য (±)","Other (+/-)","num"],["closing","শেষে বাকি","Left at closing","num"],["sell_through_pct","বিক্রির হার %","Sell-through %","pct"],["waste_cost","নষ্টের খরচ","Waste cost","money"]]'::jsonb,
  array['produced','received','returned','sold','wasted','sent','other','waste_cost'], 'day', 'desc', array['locations','categories'], false, false, false, 3101),
 ('y2_festival_compare', 'Y2', 'sales', 'উৎসব / মৌসুম তুলনা (গত বছরের সাথে)', 'Festival / season comparison (vs last year)', 'উৎসব / season তুলনা',
  '[["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["category","ক্যাটাগরি","Category","text"],["unit","একক","Unit","text"],["qty_now","এবার পরিমাণ","Quantity now","num"],["net_now","এবার বিক্রি","Sales now","money"],["qty_prev","আগের পরিমাণ","Quantity before","num"],["net_prev","আগের বিক্রি","Sales before","money"],["qty_change","পরিমাণের পার্থক্য","Quantity change","num"],["qty_change_pct","পরিমাণ %","Quantity %","pct"],["net_change_pct","বিক্রি %","Sales %","pct"],["state","অবস্থা","State","text"]]'::jsonb,
  array['net_now','net_prev'], 'net_now', 'desc', array['locations','categories','items','prev_from','prev_to'], false, false, false, 3102),
 ('y3_customer_items', 'Y3', 'customers', 'সেরা গ্রাহকরা কী কেনেন', 'What the top customers buy', 'সেরা Customer কী কেনেন',
  '[["rank","ক্রম","Rank","int"],["customer_name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["customer_net","গ্রাহকের মোট","Customer total","money"],["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["unit","একক","Unit","text"],["qty","পরিমাণ","Quantity","num"],["net","বিক্রি","Sales","money"],["share_pct","গ্রাহকের মোটের %","% of customer total","pct"],["bills","বিল","Bills","int"],["last_bought","শেষ কেনা","Last bought","date"]]'::jsonb,
  array['net'], 'rank', 'asc', array['locations','customer'], false, false, false, 3103)
 on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
   sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- drill-down: the transactions behind one row ----------
create or replace function public.report_drill(p_key text, p_ref jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d public.report_defs3; locs int[]; it uuid; lc int; dd date; df date; dt date; pf date; pt date; cu uuid; rows_ jsonb := '[]'::jsonb; cols jsonb; notes jsonb := '[]'::jsonb; cost_ok boolean := public.rpt_cost_ok();
        net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true); ttl_bn text; ttl_en text; nm_bn text; nm_en text; cnt int; has_item boolean;
        uuid_re constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into d from public.report_defs3 where key = p_key and is_active;
  if not found or p_key not in ('y1_daily_sellout', 'y2_festival_compare', 'y3_customer_items') then raise exception 'unknown_report'; end if;
  if not public._r3_ok(d) then raise exception 'not allowed'; end if;
  if p_ref is null or jsonb_typeof(p_ref) <> 'object' then raise exception 'bad_filter'; end if;
  locs := public._r2_locs('{}'::jsonb);
  has_item := p_ref ? 'item' and jsonb_typeof(p_ref -> 'item') = 'string';
  if has_item then
    if (p_ref ->> 'item') !~ uuid_re then raise exception 'bad_filter'; end if;
    it := (p_ref ->> 'item')::uuid;
  end if;

  if p_key = 'y1_daily_sellout' then
    dd := public.rpt_date(p_ref ->> 'day'); lc := case when p_ref ->> 'loc' ~ '^[0-9]{1,9}$' then (p_ref ->> 'loc')::int end;
    if dd is null or lc is null or it is null then raise exception 'bad_filter'; end if;
    select coalesce(name_bn, ''), coalesce(name_en, name_bn, '') into nm_bn, nm_en from public.items where id = it;
    ttl_bn := nm_bn || ' · ' || dd::text || ' · স্টকের নড়াচড়া'; ttl_en := nm_en || ' · ' || dd::text || ' · stock movements';
    cols := '[["time","সময়","Time","text"],["reason","ধরন","Kind","text"],["qty","পরিমাণ (±)","Quantity (+/-)","num"],["ref","উৎস","Source","text"],["staff","কে","By","text"],["note","নোট","Note","text"]'
            || case when cost_ok then ',["unit_cost","একক খরচ","Unit cost","money"]' else '' end || ']';
    select coalesce(jsonb_agg(jsonb_build_object('time', to_char(l.made_at at time zone 'Asia/Dhaka', 'HH24:MI'), 'reason', l.reason, 'qty', l.qty_delta,
        'ref', case when l.ref_type = 'sale' then coalesce((select 'Receipt ' || s.receipt::text from public.sales s where s.id::text = l.ref_id), 'sale') else coalesce(l.ref_type, '') || case when l.ref_id is not null then ' ' || left(l.ref_id, 8) else '' end end,
        'staff', (select p.staff_id from public.profiles p where p.id = l.created_by), 'note', l.note, 'unit_cost', case when cost_ok then l.unit_cost end) order by l.made_at, l.id), '[]'::jsonb)
      into rows_ from public.stock_ledger l
     where lc = any (locs) and l.location_id = lc and l.item_id = it and (l.made_at at time zone 'Asia/Dhaka')::date = dd;
  elsif p_key = 'y2_festival_compare' then
    df := public.rpt_date(p_ref ->> 'from'); dt := public.rpt_date(p_ref ->> 'to'); pf := public.rpt_date(p_ref ->> 'pf'); pt := public.rpt_date(p_ref ->> 'pt');
    if df is null or dt is null or pf is null or pt is null then raise exception 'bad_filter'; end if;
    if has_item then select coalesce(name_bn, ''), coalesce(name_en, name_bn, '') into nm_bn, nm_en from public.items where id = it; else nm_bn := 'কুইক / তালিকা-বহির্ভূত'; nm_en := 'Quick / unlisted'; end if;
    ttl_bn := nm_bn || ' · বিক্রির লেনদেন'; ttl_en := nm_en || ' · sales transactions';
    cols := '[["period","সময়","Period","text"],["day","তারিখ","Date","date"],["receipt","রসিদ","Receipt","int"],["location_bn","লোকেশন","Location","text"],["kind","ধরন","Kind","text"],["qty","পরিমাণ","Quantity","num"],["amount","টাকা","Amount","money"]]';
    select coalesce(jsonb_agg(x.j order by x.d, x.rc), '[]'::jsonb) into rows_ from (
      select f.day as d, f.receipt as rc, jsonb_build_object('period', case when f.day between df and dt then 'এবার / this time' else 'আগের / before' end, 'day', f.day, 'receipt', f.receipt, 'location_bn', f.location_bn,
             'kind', 'বিক্রি / sale', 'qty', f.qty, 'amount', round(f.net, 2)) as j
        from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and (f.item_id is not distinct from case when has_item then it end) and (f.day between df and dt or f.day between pf and pt)
      union all
      select r.day, r.receipt, jsonb_build_object('period', case when r.day between df and dt then 'এবার / this time' else 'আগের / before' end, 'day', r.day, 'receipt', r.receipt, 'location_bn', r.location_bn,
             'kind', 'ফেরত / return', 'qty', -r.qty, 'amount', -round(r.ret_amt, 2))
        from public.rpt_ret_l r where net_on and r.location_id = any (locs) and (r.item_id is not distinct from case when has_item then it end) and (r.day between df and dt or r.day between pf and pt)) x;
  else
    cu := case when (p_ref ->> 'customer') ~ uuid_re then (p_ref ->> 'customer')::uuid end; df := public.rpt_date(p_ref ->> 'from'); dt := public.rpt_date(p_ref ->> 'to');
    if cu is null or it is null or df is null or dt is null then raise exception 'bad_filter'; end if;
    select coalesce(name, '-') into nm_bn from public.customers where id = cu; select coalesce(name_bn, ''), coalesce(name_en, name_bn, '') into ttl_bn, ttl_en from public.items where id = it;
    ttl_en := nm_bn || ' · ' || ttl_en || ' · sales'; ttl_bn := nm_bn || ' · ' || ttl_bn || ' · বিক্রির লেনদেন';
    cols := '[["day","তারিখ","Date","date"],["receipt","রসিদ","Receipt","int"],["location_bn","লোকেশন","Location","text"],["kind","ধরন","Kind","text"],["qty","পরিমাণ","Quantity","num"],["amount","টাকা","Amount","money"]]';
    select coalesce(jsonb_agg(x.j order by x.d, x.rc), '[]'::jsonb) into rows_ from (
      select f.day as d, f.receipt as rc, jsonb_build_object('day', f.day, 'receipt', f.receipt, 'location_bn', f.location_bn, 'kind', 'বিক্রি / sale', 'qty', f.qty, 'amount', round(f.net, 2)) as j
        from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.customer_id = cu and f.item_id = it and f.day between df and dt
      union all
      select r.day, r.receipt, jsonb_build_object('day', r.day, 'receipt', r.receipt, 'location_bn', r.location_bn, 'kind', 'ফেরত / return', 'qty', -r.qty, 'amount', -round(r.ret_amt, 2))
        from public.rpt_ret_l r where net_on and r.location_id = any (locs) and r.customer_id = cu and r.item_id = it and r.day between df and dt) x;
  end if;
  cnt := jsonb_array_length(rows_);
  if cnt > 500 then
    rows_ := (select jsonb_agg(e) from (select e from jsonb_array_elements(rows_) e limit 500) z);
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', 500, 'groups', cnt));
  end if;
  return jsonb_build_object('title_bn', ttl_bn, 'title_en', ttl_en, 'rows', rows_, 'notes', notes, 'count', cnt,
    'columns', (select jsonb_agg(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3)) from jsonb_array_elements(cols) c));
end $$;

revoke all on function public._rptb1_p403_present(), public._r3q_y1_daily_sellout(date, date, int[], jsonb), public._r3q_y2_festival_compare(date, date, int[], jsonb), public._r3q_y3_customer_items(date, date, int[], jsonb),
  public._rptb1_y_notes(text, date, date, int[], jsonb) from public, anon, authenticated;
revoke all on function public.report_drill(text, jsonb) from public, anon;
grant execute on function public.report_drill(text, jsonb) to authenticated;
