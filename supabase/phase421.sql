-- ============================================================
-- BOS tool · Phase 421 (RPT-B2 R2a): stock movement reports, in place or new, all on the existing report engine 3 (viewer #/report/<key>, CSV and print there).
-- Needs phase420 (the decorator hook). Paste after phase420. Safe to paste twice. Read-only reports; they stay OPEN to report_stock holders; nothing is behind a setting.
--   #64 transfers_register     every transfer (sent, received, short, in transit, cancelled) with the shortage claim state; transfers_gap stays the exceptions-only view
--   #66 k2_count_variance      EXTENDED in place: the paper count sheets (04-3) AND the counts typed in the app (count adjust), with the value of the difference
--   #71 stock_adjustments      the stock adjustment history: who, why, how much, what it is worth
--   #77 wastage_rate           wastage as a share of stock handled, with the denominator shown (opening + received); value share of sales shown beside it
-- A value without a cost is empty with the basis named; a share without a denominator is empty (data not captured), never 0.
-- ============================================================

-- ---------- #64 all transfers ----------
create or replace function public._r3q_transfers_register(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Dhaka')::date as today, public.rpt_cost_ok() as cost)
  select jsonb_build_object('sent_day', (x.sent_at at time zone 'Asia/Dhaka')::date, 'from_bn', lf.name_bn, 'from_en', coalesce(lf.name_en, lf.name_bn), 'to_bn', lt.name_bn, 'to_en', coalesce(lt.name_en, lt.name_bn),
      'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id),
      'sent_qty', x.qty, 'received_qty', x.received_qty,
      'short_qty', case when x.status = 'received' then round(x.qty - coalesce(x.received_qty, x.qty), 4) end,
      'in_transit_qty', case when x.status = 'sent' then x.qty end,
      'flag', case when x.status = 'sent' then 'in_transit' when x.status = 'cancelled' then 'cancelled' when x.qty - coalesce(x.received_qty, x.qty) > 0 then 'short' else 'ok' end,
      'days_in_transit', case when x.status = 'sent' then t.today - (x.sent_at at time zone 'Asia/Dhaka')::date end,
      'received_day', (x.received_at at time zone 'Asia/Dhaka')::date, 'sent_staff', x.sent_staff, 'received_staff', x.received_staff,
      'note', coalesce(x.receive_note, x.note), 'claim', st.status,
      'value', case when t.cost then (select case when bool_and(l.unit_cost is not null) then round(sum(-l.qty_delta * l.unit_cost), 2) end from public.stock_ledger l
                                       where l.ref_type = 'transfer' and l.ref_id = x.id::text and l.reason = 'transfer_out') end,
      'short_value', case when t.cost and st.id is not null then st.value end,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[
                case when t.cost and not exists (select 1 from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = x.id::text and l.reason = 'transfer_out' and l.unit_cost is null) then null
                     when t.cost then 'value' end,
                case when t.cost and st.id is not null and st.value is null then 'short_value' end]) z where z is not null),
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, x.from_location_id))
    from public.stock_transfers x join public.items it on it.id = x.item_id join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id
      left join public.shortage_transit st on st.transfer_id = x.id cross join t
   where (x.sent_at at time zone 'Asia/Dhaka')::date between d1 and d2 and (x.from_location_id = any (locs) or x.to_location_id = any (locs));
$$;

create or replace function public._r4d_transfers_register(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb; n_all bigint; n_sh bigint; n_tr bigint; n_nc bigint; d1 date := (p_res #>> '{meta,from}')::date; d2 date := (p_res #>> '{meta,to}')::date;
        locs int[] := public._r2_locs(p_flt);
begin
  if d1 is null then return res; end if;
  select count(*), count(*) filter (where x.status = 'received' and x.qty - coalesce(x.received_qty, x.qty) > 0), count(*) filter (where x.status = 'sent') into n_all, n_sh, n_tr
    from public.stock_transfers x where (x.sent_at at time zone 'Asia/Dhaka')::date between d1 and d2 and (x.from_location_id = any (locs) or x.to_location_id = any (locs));
  res := public._r4_addnote(res, public._r4_note('info', n_all || ' transfer(s) in the period: ' || n_tr || ' still in transit, ' || n_sh || ' received short. This list shows ALL transfers; "Transfers not received or short" shows only the exceptions. Quantities are in each item''s own base unit, so they are not added up.',
    'এই সময়ে ' || n_all || 'টি ট্রান্সফার: ' || n_tr || 'টি পথে, ' || n_sh || 'টি কম পৌঁছেছে। এই তালিকায় সব ট্রান্সফার; "পৌঁছায়নি / কম পৌঁছেছে" রিপোর্টে শুধু ব্যতিক্রম। পরিমাণ প্রতিটি আইটেমের নিজের এককে, তাই যোগ করা হয়নি।'));
  if cost_ok then
    select count(*) into n_nc from public.shortage_transit st join public.stock_transfers x on x.id = st.transfer_id
     where st.value is null and (x.sent_at at time zone 'Asia/Dhaka')::date between d1 and d2 and (x.from_location_id = any (locs) or x.to_location_id = any (locs));
    if n_nc > 0 then res := public._r4_addnote(res, public._r4_note('data_needed', n_nc || ' short transfer(s) have no cost at send, so their value is not captured (it is not zero). The owner enters the cost on the shortage record.',
      n_nc || 'টি কম-পৌঁছানো ট্রান্সফারে পাঠানোর সময়ের খরচ নেই, তাই মূল্য লেখা হয়নি (শূন্য নয়)। মালিক ঘাটতির রেকর্ডে খরচ বসান।', 'shortage_transit.value')); end if;
  else
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('value', 'short_value') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return res;
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('transfers_register', 'S4', 'stock', 'সব ট্রান্সফার (পাঠানো, পৌঁছানো, কম, পথে)', 'All transfers (sent, received, short, in transit)', 'সব Transfer (sent, received, short, পথে)',
  '[["sent_day","পাঠানো","Sent","date"],["from_bn","কোথা থেকে","From","text"],["from_en","From (EN)","From (EN)","text"],["to_bn","কোথায়","To","text"],["to_en","To (EN)","To (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["unit","একক","Unit","text"],["sent_qty","পাঠানো","Sent qty","num"],["received_qty","পৌঁছেছে","Received qty","num"],["short_qty","কম","Short","num"],["in_transit_qty","পথে","In transit","num"],["flag","অবস্থা","State","text"],["days_in_transit","পথে দিন","Days in transit","int"],["received_day","গ্রহণ","Received","date"],["sent_staff","পাঠিয়েছে","Sent by","text"],["received_staff","গ্রহণ করেছে","Received by","text"],["claim","দাবির অবস্থা","Claim state","text"],["value","মূল্য (খরচে)","Value (at cost)","money"],["short_value","কমের মূল্য","Short value","money"],["note","নোট","Note","text"]]'::jsonb,
  '{}', 'sent_day', 'desc', array['locations','brands'], false, false, false, 4203)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #66 count variance (paper sheet 04-3 + counts typed in the app), with the value of the difference ----------
create or replace function public._r3q_k2_count_variance(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c, public.rpt_cost_ok() as cost),
  ln as (
    select e.location_id, e.entry_date, e.serial, nullif(btrim(e.data ->> 'counted_by'), '') as cb, r ->> 'item' as icode,
           public._r2_num(r -> 'count') as cnt, public._r2_num(r -> 'book') as bk, nullif(btrim(r ->> 'reason'), '') as reason
      from public.entries e cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'rows')) r
     where e.form_code = '04-3' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  g as (
    select ln.location_id, ln.cb, i.id as item_id, i.code, i.name_bn, count(*) as counts, count(*) filter (where ln.cnt <> ln.bk) as off_n,
           count(*) filter (where ln.cnt < ln.bk) as short_n, count(*) filter (where ln.cnt > ln.bk) as over_n,
           sum(ln.cnt - ln.bk) as net_var, sum(abs(ln.cnt - ln.bk)) as abs_var, max(ln.entry_date) as last_date,
           (array_agg(ln.reason order by ln.entry_date desc, ln.serial desc) filter (where ln.reason is not null and ln.cnt <> ln.bk))[1] as last_reason
      from ln join public.items i on i.code = ln.icode cross join cat
     where ln.cnt is not null and ln.bk is not null and (cat.c is null or i.category = any (cat.c))
     group by ln.location_id, ln.cb, i.id, i.code, i.name_bn),
  rp as (                                                       -- bos421: counts typed in the app (stock_count_adjust); a count with no difference writes nothing, so only differences are here
    select l.location_id, l.created_by, i.id as item_id, i.code, i.name_bn, count(*) as off_n, count(*) filter (where l.qty_delta < 0) as short_n, count(*) filter (where l.qty_delta > 0) as over_n,
           sum(l.qty_delta) as net_var, sum(abs(l.qty_delta)) as abs_var, max((l.made_at at time zone 'Asia/Dhaka')::date) as last_date,
           (array_agg(l.note order by l.id desc))[1] as last_reason
      from public.stock_ledger l join public.items i on i.id = l.item_id cross join cat
     where l.reason = 'count_adjust' and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and l.location_id = any (locs) and (cat.c is null or i.category = any (cat.c))
     group by l.location_id, l.created_by, i.id, i.code, i.name_bn)
  select jsonb_build_object('location_bn', l.name_bn, 'counter', coalesce(nullif(btrim(p.full_name), '') || ' · ' || g.cb, g.cb, '-'), 'item_code', g.code, 'item_bn', g.name_bn, 'source', 'sheet 04-3',
    'counts', g.counts, 'off_n', g.off_n, 'short_n', g.short_n, 'over_n', g.over_n, 'net_var', round(g.net_var, 3), 'abs_var', round(g.abs_var, 3),
    'off_pct', round(g.off_n * 100.0 / g.counts, 1),
    'net_value', case when cat.cost and sb.avg_cost is not null then round(g.net_var * sb.avg_cost, 2) end, 'abs_value', case when cat.cost and sb.avg_cost is not null then round(g.abs_var * sb.avg_cost, 2) end,
    '_nc', case when cat.cost and sb.avg_cost is null then '["net_value","abs_value"]'::jsonb end,
    'last_date', g.last_date, 'last_reason', g.last_reason, 'drill', format('#/stockrep/ledger?item=%s&loc=%s', g.item_id, g.location_id))
    from g join public.locations l on l.id = g.location_id left join public.profiles p on p.staff_id = g.cb cross join cat
      left join public.stock_balance sb on sb.item_id = g.item_id and sb.location_id = g.location_id
  union all
  select jsonb_build_object('location_bn', l.name_bn, 'counter', coalesce(nullif(btrim(p.full_name), '') || ' · ' || p.staff_id, p.staff_id, '-'), 'item_code', r.code, 'item_bn', r.name_bn, 'source', 'count in app',
    'counts', null, 'off_n', r.off_n, 'short_n', r.short_n, 'over_n', r.over_n, 'net_var', round(r.net_var, 3), 'abs_var', round(r.abs_var, 3), 'off_pct', null,
    'net_value', case when cat.cost and sb.avg_cost is not null then round(r.net_var * sb.avg_cost, 2) end, 'abs_value', case when cat.cost and sb.avg_cost is not null then round(r.abs_var * sb.avg_cost, 2) end,
    '_nc', case when cat.cost and sb.avg_cost is null then '["counts","off_pct","net_value","abs_value"]'::jsonb else '["counts","off_pct"]'::jsonb end,
    'last_date', r.last_date, 'last_reason', r.last_reason, 'drill', format('#/stockrep/ledger?item=%s&loc=%s', r.item_id, r.location_id))
    from rp r join public.locations l on l.id = r.location_id left join public.profiles p on p.id = r.created_by cross join cat
      left join public.stock_balance sb on sb.item_id = r.item_id and sb.location_id = r.location_id;
$$;

create or replace function public._r4d_k2_count_variance(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb; tot jsonb := coalesce(p_res -> 'totals', '{}'::jsonb);
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Two sources: "sheet 04-3" (paper count sheets, every counted line) and "count in app" (a count typed in the app). The app writes a line ONLY when the count differs from the book, so for those rows the number of counts and the off % are not captured. The value is the difference at the item''s average cost now; where no cost is recorded it is empty.',
    'দুটি উৎস: "sheet 04-3" (কাগজের গণনা শিট, প্রতিটি গোনা লাইন) এবং "count in app" (অ্যাপে লেখা গণনা)। অ্যাপ শুধু বইয়ের সাথে পার্থক্য হলেই লাইন লেখে, তাই ওই সারিতে গণনার সংখ্যা ও পার্থক্য % লেখা হয়নি। মূল্য = পার্থক্য × আইটেমের এখনকার গড় খরচ; খরচ না থাকলে ফাঁকা।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('net_value', 'abs_value') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); tot := tot - 'net_value' - 'abs_value'; res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return jsonb_set(res, '{totals}', tot);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('k2_count_variance', 'K2', 'stock', 'স্টক গণনার পার্থক্য', 'Stock count variance', 'Stock গণনার পার্থক্য',
  '[["location_bn","লোকেশন","Location","text"],["counter","গণনাকারী","Counter","text"],["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["source","উৎস","Source","text"],["counts","গণনা","Counts","int"],["off_n","পার্থক্য হয়েছে","Times off","int"],["short_n","কম","Short","int"],["over_n","বেশি","Over","int"],["net_var","নিট পার্থক্য","Net variance","num"],["abs_var","মোট পার্থক্য (চিহ্ন ছাড়া)","Absolute variance","num"],["net_value","নিট মূল্য (গড় খরচে)","Net value (avg cost)","money"],["abs_value","মোট মূল্য (গড় খরচে)","Absolute value (avg cost)","money"],["off_pct","পার্থক্য %","Off %","pct"],["last_date","শেষ তারিখ","Last date","date"],["last_reason","শেষ কারণ","Last reason","text"]]'::jsonb,
  array['counts','off_n','short_n','over_n','net_value','abs_value'], 'off_n', 'desc', array['locations','categories'], false, false, false, 2605)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #71 stock adjustment history ----------
create or replace function public._r3q_stock_adjustments(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c, public._r4_types(flt) as ty, public.rpt_cost_ok() as cost)
  select jsonb_build_object('day', (l.made_at at time zone 'Asia/Dhaka')::date, 'at', to_char(l.made_at at time zone 'Asia/Dhaka', 'HH24:MI'), 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
      'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id),
      'direction', case when l.qty_delta < 0 then 'decrease' else 'increase' end, 'book_qty', b.before_qty, 'counted_qty', b.before_qty + l.qty_delta, 'qty_delta', l.qty_delta,
      'value', case when cat.cost and coalesce(l.unit_cost, sb.avg_cost) is not null then round(l.qty_delta * coalesce(l.unit_cost, sb.avg_cost), 2) end,
      'basis', case when not cat.cost then null when l.unit_cost is not null then 'booked cost' when sb.avg_cost is not null then 'average cost now' else 'no cost recorded' end,
      '_nc', case when cat.cost and coalesce(l.unit_cost, sb.avg_cost) is null then '["value"]'::jsonb end,
      'who', coalesce(nullif(btrim(p.full_name), '') || ' · ' || p.staff_id, p.staff_id, '-'), 'why', l.note, 'ledger_id', l.id,
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, l.location_id))
    from public.stock_ledger l join public.items it on it.id = l.item_id join public.locations lo on lo.id = l.location_id cross join cat
      left join public.profiles p on p.id = l.created_by left join public.stock_balance sb on sb.item_id = l.item_id and sb.location_id = l.location_id
      cross join lateral (select coalesce(sum(z.qty_delta), 0) as before_qty from public.stock_ledger z where z.item_id = l.item_id and z.location_id = l.location_id and z.id < l.id) b
   where l.reason = 'count_adjust' and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and l.location_id = any (locs)
     and (cat.c is null or it.category = any (cat.c)) and (cat.ty is null or it.item_type = any (cat.ty));
$$;

create or replace function public._r4d_stock_adjustments(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb; tot jsonb := coalesce(p_res -> 'totals', '{}'::jsonb);
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Adjustments made by a stock count in the app (book quantity, counted quantity, difference, who, why). Wastage, transfers and corrections of a bill are not adjustments; they have their own lists. Value uses the booked cost; where a gain has none, the average cost now (the basis column says which).',
    'অ্যাপে স্টক গণনা দিয়ে করা সমন্বয় (বই, গোনা, পার্থক্য, কে, কেন)। নষ্ট, ট্রান্সফার ও বিল সংশোধন সমন্বয় নয়; সেগুলোর আলাদা তালিকা আছে। মূল্য লেখা খরচে; ঘাটতির খরচ না থাকলে এখনকার গড় খরচে (basis কলামে লেখা)।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('value', 'basis') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); tot := tot - 'value'; res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return jsonb_set(res, '{totals}', tot);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('stock_adjustments', 'S5', 'stock', 'স্টক সমন্বয়ের ইতিহাস (কে, কেন, মূল্য)', 'Stock adjustment history (who, why, value)', 'Stock সমন্বয়ের ইতিহাস (কে, কেন, মূল্য)',
  '[["day","তারিখ","Date","date"],["at","সময়","Time","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["unit","একক","Unit","text"],["direction","দিক","Direction","text"],["book_qty","বইয়ে ছিল","Book qty","num"],["counted_qty","গুনে পাওয়া","Counted qty","num"],["qty_delta","পার্থক্য","Difference","num"],["value","মূল্য","Value","money"],["basis","মূল্যের ভিত্তি","Value basis","text"],["who","কে","Who","text"],["why","কেন","Why","text"]]'::jsonb,
  array['value'], 'day', 'desc', array['locations','brands','categories','item_types'], false, false, false, 4204)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #77 wastage as a share of stock handled ----------
-- per item and place: wastage qty / (stock at the start of the period + goods received in the period). The two parts of the denominator are columns. Value share of sales is shown beside it.
create or replace function public._r3q_wastage_rate(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c, public._r4_types(flt) as ty, public.rpt_cost_ok() as cost),
  w as (
    select w.item_id, w.location_id, sum(w.qty) as wq, count(*) as n, sum(w.qty * sl.unit_cost) filter (where sl.unit_cost is not null) as wv, count(*) filter (where sl.unit_cost is null) as w_uncosted
      from public.stock_wastage w left join public.stock_ledger sl on sl.id = w.ledger_id
     where (w.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and w.location_id = any (locs) group by w.item_id, w.location_id),
  h as (
    select w.item_id, w.location_id,
           coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.item_id = w.item_id and l.location_id = w.location_id and (l.made_at at time zone 'Asia/Dhaka')::date < d1), 0) as opening_qty,
           coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.item_id = w.item_id and l.location_id = w.location_id and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
                      and l.reason in ('opening', 'purchase_in', 'production_in', 'transfer_in')), 0) as received_qty
      from w),
  s as (select f.item_id, f.location_id, sum(f.net) as net from public.sales_fact f where f.status = 'done' and f.day between d1 and d2 and f.location_id = any (locs) and f.item_id is not null group by 1, 2)
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
      'unit', public._item_base(it.id), 'entries', w.n, 'wastage_qty', round(w.wq, 4), 'opening_qty', round(h.opening_qty, 4), 'received_qty', round(h.received_qty, 4), 'handled_qty', round(h.opening_qty + h.received_qty, 4),
      'wastage_pct', case when h.opening_qty + h.received_qty > 0 then round(w.wq * 100.0 / (h.opening_qty + h.received_qty), 2) end,
      'wastage_value', case when cat.cost then round(w.wv, 2) end, 'uncosted_entries', case when cat.cost then w.w_uncosted end,
      'sales_value', round(s.net, 2), 'value_pct_of_sales', case when cat.cost and s.net > 0 and w.wv is not null then round(w.wv * 100.0 / s.net, 2) end,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[case when h.opening_qty + h.received_qty <= 0 then 'wastage_pct' end, case when cat.cost and w.wv is null then 'wastage_value' end,
                case when s.net is null or s.net <= 0 then 'value_pct_of_sales' end]) z where z is not null),
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, w.location_id))
    from w join h on h.item_id = w.item_id and h.location_id = w.location_id join public.items it on it.id = w.item_id join public.locations lo on lo.id = w.location_id cross join cat
      left join s on s.item_id = w.item_id and s.location_id = w.location_id
   where (cat.c is null or it.category = any (cat.c)) and (cat.ty is null or it.item_type = any (cat.ty));
$$;

create or replace function public._r4d_wastage_rate(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb; tot jsonb := coalesce(p_res -> 'totals', '{}'::jsonb);
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Wastage % = wastage quantity / (stock at the start of the period + goods received in the period: opening entries, purchases, production, transfers in). Both parts are shown. Where nothing was held or received the % is empty (no denominator), it is not 0. Value % of sales = wastage value (costed entries only) / sales value of the same item and place.',
    'নষ্ট % = নষ্টের পরিমাণ / (সময়ের শুরুর স্টক + সময়ে পাওয়া মাল: ওপেনিং, ক্রয়, উৎপাদন, ট্রান্সফার ইন)। দুটি অংশই দেখানো হয়েছে। কিছু না থাকলে/না এলে % ফাঁকা (ভাগ করার সংখ্যা নেই), ০ নয়। বিক্রির % = নষ্টের মূল্য (শুধু খরচ জানা এন্ট্রি) / একই আইটেম ও জায়গার বিক্রির মূল্য।'));
  res := public._r4_addnote(res, public._r4_note('info', 'Quantities are per item in its own base unit; different units are never added. Use the existing Wastage report for totals by reason, item, place or day.',
    'পরিমাণ প্রতিটি আইটেমের নিজের এককে; ভিন্ন একক যোগ করা হয়নি। কারণ, আইটেম, জায়গা বা দিন অনুযায়ী মোটের জন্য আগের "অপচয়" রিপোর্ট দেখুন।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('wastage_value', 'uncosted_entries', 'sales_value', 'value_pct_of_sales') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); tot := tot - 'wastage_value' - 'uncosted_entries'; res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return jsonb_set(res, '{totals}', tot);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('wastage_rate', 'S6', 'stock', 'অপচয় % (কত মালের মধ্যে কত নষ্ট)', 'Wastage % of stock handled', 'অপচয় % (stock handled-এর মধ্যে)',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["unit","একক","Unit","text"],["entries","বার","Entries","int"],["wastage_qty","নষ্ট পরিমাণ","Wastage qty","num"],["opening_qty","শুরুর স্টক","Opening qty","num"],["received_qty","পাওয়া মাল","Received qty","num"],["handled_qty","মোট ছিল (ভাগ করার সংখ্যা)","Handled (denominator)","num"],["wastage_pct","নষ্ট %","Wastage %","pct"],["wastage_value","নষ্টের মূল্য (খরচ জানা অংশ)","Wastage value (costed part)","money"],["uncosted_entries","খরচ অজানা এন্ট্রি","Entries with no cost","int"],["sales_value","বিক্রির মূল্য","Sales value","money"],["value_pct_of_sales","বিক্রির %","Value % of sales","pct"]]'::jsonb,
  array['entries','wastage_value','uncosted_entries'], 'wastage_pct', 'desc', array['locations','brands','categories','item_types'], false, false, false, 4205)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

select public._r3_lockdown();
select public._r4_lockdown();
notify pgrst, 'reload schema';
