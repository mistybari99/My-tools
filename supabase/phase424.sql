-- ============================================================
-- BOS tool · Phase 424 (RPT-B2 R4a): batches and freshness. Read-only. Paste after phase423. Safe to paste twice. Open to report_stock holders at their own places.
--   #67 item_slow            EXTENDED in place (engine 3, same key): sales net of refunds, stock on hand, its value, the last movement, and a state (not moving / no net sales / sold)
--   #70 batch_stock_rows     stock batch by batch with expiry and FEFO order, and one "unbatched" line per item and place so that batches + unbatched = the balance
--   #68 fg_ageing_rows       the age of finished-goods stock by batch (days since made), by item (oldest and weighted average); age bands only if the owner set report_aging_buckets
-- Raw material received without a lot cannot be aged (nothing records when it arrived): it shows as unbatched. Capturing the supplier lot on receipt is the R5 package, not this one.
-- The answer of the RPCs has the shape of the report viewer {columns, rows, totals, notes, sections} so web/batchrep.js can draw and export it.
-- ============================================================

-- answer builder: columns come as [[key, bn, en, type], ...]
create or replace function public._r4_ans(p_cols jsonb, p_rows jsonb, p_totals jsonb, p_notes jsonb, p_extra jsonb default '{}'::jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object('columns', (select coalesce(jsonb_agg(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3,
            'role', case when c ->> 3 in ('money', 'int', 'num', 'pct') then 'measure' else 'dim' end)), '[]'::jsonb) from jsonb_array_elements(p_cols) c),
    'rows', coalesce(p_rows, '[]'::jsonb), 'totals', p_totals, 'notes', coalesce(p_notes, '[]'::jsonb)) || coalesce(p_extra, '{}'::jsonb);
$$;
revoke all on function public._r4_ans(jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;

-- age band label for an age in days, from the owner's list of band ends (rule report_aging_buckets, e.g. 1,3,7: 0-1, 2-3, 4-7, 8+); null when no bands
create or replace function public._r4_band(p_age int, p_bands int[]) returns text
language plpgsql immutable set search_path = public as $$
declare i int; lo int := 0;
begin
  if p_bands is null or cardinality(p_bands) = 0 or p_age is null then return null; end if;
  for i in 1..cardinality(p_bands) loop
    if p_age <= p_bands[i] then return lo || '-' || p_bands[i]; end if;
    lo := p_bands[i] + 1;
  end loop;
  return lo || '+';
end $$;
revoke all on function public._r4_band(int, int[]) from public, anon, authenticated;

-- the owner's band ends from the existing rule; null when empty or not a rising list (no default is invented)
create or replace function public._r4_bands() returns int[]
language plpgsql stable security definer set search_path = public as $$
declare bk text := public.rule_txt('report_aging_buckets'); b int[]; i int;
begin
  if bk is null or bk !~ '^[0-9]{1,4}(,[0-9]{1,4}){0,5}$' then return null; end if;
  b := string_to_array(bk, ',')::int[];
  for i in 2..cardinality(b) loop if b[i] <= b[i - 1] then return null; end if; end loop;
  return b;
end $$;
revoke all on function public._r4_bands() from public, anon, authenticated;

-- the family of a production batch: the batch itself and every batch that came from it by transfer (a transfer in carries the batch to the receiver as a new batch row)
create or replace function public._r4_lineage() returns table (root bigint, batch bigint)
language sql stable security definer set search_path = public as $$
  with recursive o as (select l.id, l.ref_id, l.batch_id, row_number() over (partition by l.ref_id order by l.id) as rn from public.stock_ledger l where l.reason = 'transfer_out' and l.ref_type = 'transfer' and l.batch_id is not null),
  i as (select l.id, l.ref_id, l.batch_id, row_number() over (partition by l.ref_id order by l.id) as rn from public.stock_ledger l where l.reason = 'transfer_in' and l.ref_type = 'transfer' and l.batch_id is not null),
  pairs as (select o.batch_id as parent, i.batch_id as child from o join i on i.ref_id = o.ref_id and i.rn = o.rn),
  roots as (select distinct l.batch_id as r from public.stock_ledger l where l.reason = 'production_in' and l.batch_id is not null),
  tree(root, batch) as (select r, r from roots union all select t.root, p.child from tree t join pairs p on p.parent = t.batch)
  select root, batch from tree;
$$;
revoke all on function public._r4_lineage() from public, anon, authenticated;

-- ---------- #67 slow and non-moving items, in place ----------
create or replace function public._r3q_item_slow(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with p as (select public.rpt_arr_text(flt -> 'categories') as cat, public._r4_types(flt) as ty, public.rpt_cost_ok() as cost, (now() at time zone 'Asia/Dhaka')::date as today),
  s as (select f.item_id, sum(f.qty) as qty, sum(f.net) as net, count(distinct f.sale_id) as bills, max(f.day) as last_sold
          from public.sales_fact f where f.status = 'done' and f.item_id is not null and f.day between d1 and d2 and f.location_id = any (locs) group by 1),
  r as (select (e ->> 'item_id')::uuid as item_id, sum((e ->> 'qty')::numeric) as rqty, sum((e ->> 'amount')::numeric) as ramt
          from public.sale_returns x cross join lateral jsonb_array_elements(case when jsonb_typeof(x.lines) = 'array' then x.lines else '[]'::jsonb end) e
         where x.status = 'done' and (x.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and x.location_id = any (locs) and nullif(e ->> 'item_id', '') is not null group by 1),
  oh as (select b.item_id, sum(b.qty) as q, sum(round(b.qty * b.avg_cost, 2)) filter (where b.avg_cost is not null) as v, count(*) filter (where b.qty <> 0 and b.avg_cost is null) as unc
           from public.stock_balance b where b.location_id = any (locs) group by 1),
  mv as (select l.item_id, max((l.made_at at time zone 'Asia/Dhaka')::date) as d from public.stock_ledger l where l.location_id = any (locs) and l.reason not in ('opening', 'count_adjust') group by 1)
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'category', coalesce(it.category, '(none)'), 'item_type', coalesce(t.label_bn, it.item_type),
      'qty', coalesce(round(s.qty, 3), 0), 'net', coalesce(round(s.net, 2), 0), 'bills', coalesce(s.bills, 0), 'last_sold', s.last_sold,
      'refund_qty', coalesce(round(r.rqty, 3), 0), 'net_qty', coalesce(round(s.qty, 3), 0) - coalesce(round(r.rqty, 3), 0), 'net_after_refunds', coalesce(round(s.net, 2), 0) - coalesce(round(r.ramt, 2), 0),
      'on_hand', case when it.tracked then round(coalesce(oh.q, 0), 3) end, 'unit', public._item_base(it.id),
      'value', case when p.cost and it.tracked and coalesce(oh.q, 0) <> 0 and oh.v is not null then round(oh.v, 2) end, 'uncosted_lines', case when p.cost and it.tracked then coalesce(oh.unc, 0) end,
      'last_movement', mv.d, 'days_since_movement', p.today - mv.d,
      'state', case when it.tracked and coalesce(oh.q, 0) > 0 and (mv.d is null or mv.d < d1) then 'not_moving'
                    when coalesce(s.qty, 0) - coalesce(r.rqty, 0) <= 0 then 'no_net_sales' else 'sold' end,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[case when not it.tracked then 'on_hand' end, case when it.tracked and mv.d is null then 'last_movement' end,
                case when p.cost and it.tracked and coalesce(oh.q, 0) <> 0 and oh.v is null then 'value' end]) z where z is not null),
      'drill', format('#/stockrep/recon?from=%s&to=%s', d1, d2))
    from public.items it cross join p left join public.item_types t on t.code = it.item_type left join s on s.item_id = it.id left join r on r.item_id = it.id left join oh on oh.item_id = it.id left join mv on mv.item_id = it.id
   where it.is_active and it.sellable and it.retired_at is null and (p.cat is null or it.category = any (p.cat)) and (p.ty is null or it.item_type = any (p.ty));
$$;

create or replace function public._r4d_item_slow(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb; tot jsonb := coalesce(p_res -> 'totals', '{}'::jsonb);
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Sales are the sales of the period; refunds of the same period are taken off ("net qty", "net after refunds"; the old columns qty and net are unchanged). Stock on hand is the book balance now at the chosen places. Last movement is the last ledger movement that is not an opening entry or a count correction. State: not moving = stock on hand and no movement in the period; no net sales = nothing left after refunds; sold. No limit is used to call an item "slow": sort by net qty.',
    'বিক্রি = সময়ের বিক্রি; একই সময়ের ফেরত বাদ ("নিট পরিমাণ", "ফেরতের পর নিট"; আগের qty ও net কলাম অপরিবর্তিত)। হাতে স্টক = বাছা জায়গার এখনকার বইয়ের ব্যালান্স। শেষ নড়াচড়া = ওপেনিং ও গণনা-সংশোধন ছাড়া শেষ খাতা-নড়াচড়া। অবস্থা: নড়ছে না = স্টক আছে কিন্তু সময়ে কোনো নড়াচড়া নেই; নিট বিক্রি নেই = ফেরতের পর কিছু নেই; বিক্রি হয়েছে। "ধীর" বলার কোনো সীমা বসানো হয়নি: নিট পরিমাণ অনুযায়ী সাজান।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('value', 'uncosted_lines') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); tot := tot - 'value'; res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return jsonb_set(res, '{totals}', tot);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('item_slow', 'S10', 'sales', 'ধীর ও অবিক্রীত আইটেম', 'Slow and unsold items', 'ধীর ও unsold Item',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["category","ক্যাটাগরি","Category","text"],["item_type","ধরন","Type","text"],["qty","বিক্রি পরিমাণ","Qty sold","num"],["refund_qty","ফেরত","Refunded qty","num"],["net_qty","নিট পরিমাণ","Net qty","num"],["net","বিক্রি","Sales","money"],["net_after_refunds","ফেরতের পর নিট","Net after refunds","money"],["bills","বিল","Bills","int"],["last_sold","শেষ বিক্রি","Last sold","date"],["on_hand","হাতে স্টক","On hand","num"],["unit","একক","Unit","text"],["value","স্টকের মূল্য","Stock value","money"],["uncosted_lines","খরচ অজানা লাইন","Lines with no cost","int"],["last_movement","শেষ নড়াচড়া","Last movement","date"],["days_since_movement","কত দিন নড়েনি","Days since movement","int"],["state","অবস্থা","State","text"]]'::jsonb,
  array['net','net_after_refunds','value'], 'net_qty', 'asc', array['locations','brands','categories','item_types'], false, false, false, 4210)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #70 / #68 batch rows: every open batch, plus the unbatched part of the balance ----------
create or replace function public._r4_batch_rows(p_locs int[], p_item uuid, p_types text[], p_cost boolean) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Dhaka')::date as today, coalesce(public.rule_num('report_expiry_soon_days'), public.rule_num('expiry_warn_days')) as thr, public._r4_bands() as bands),
  b as (
    select sb.id as bid, sb.batch_no, sb.item_id, sb.location_id, sb.made_at, sb.expires_at, sb.qty_made, sb.qty_remaining
      from public.stock_batches sb join public.items it on it.id = sb.item_id
     where sb.qty_remaining > 0 and sb.location_id = any (p_locs) and (p_item is null or sb.item_id = p_item) and (p_types is null or it.item_type = any (p_types)) and it.is_active),
  rk as (select b.bid, row_number() over (partition by b.item_id, b.location_id order by (b.expires_at is not null and b.expires_at <= now()), b.expires_at nulls last, b.made_at, b.bid) as r from b),
  rt as (select l.batch as bid, min(l.root) as root from public._r4_lineage() l group by 1),
  bs as (select b.item_id, b.location_id, sum(b.qty_remaining) as q from b group by 1, 2),
  bal as (
    select sbl.item_id, sbl.location_id, sbl.qty, sbl.avg_cost from public.stock_balance sbl join public.items it on it.id = sbl.item_id
     where sbl.location_id = any (p_locs) and (p_item is null or sbl.item_id = p_item) and (p_types is null or it.item_type = any (p_types)) and it.is_active and it.tracked)
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'item_type', coalesce(ty.label_bn, it.item_type), 'item_type_en', coalesce(ty.label_en, ty.label_bn, it.item_type),
      'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'row_kind', 'batch', 'batch_no', coalesce(b.batch_no, '#' || b.bid), 'batch_id', b.bid, 'root_batch', rt.root,
      'origin', (select l.reason from public.stock_ledger l where l.batch_id = b.bid and l.qty_delta > 0 order by l.id limit 1),
      'made_on', (b.made_at at time zone 'Asia/Dhaka')::date, 'age_days', t.today - (b.made_at at time zone 'Asia/Dhaka')::date, 'age_band', public._r4_band(t.today - (b.made_at at time zone 'Asia/Dhaka')::date, t.bands),
      'expires_on', (b.expires_at at time zone 'Asia/Dhaka')::date, 'days_left', (b.expires_at at time zone 'Asia/Dhaka')::date - t.today,
      'state', case when b.expires_at is null then 'no_expiry' when (b.expires_at at time zone 'Asia/Dhaka')::date < t.today then 'expired' when (b.expires_at at time zone 'Asia/Dhaka')::date <= t.today + coalesce(t.thr::int, -1) then 'soon' else 'ok' end,
      'qty', b.qty_remaining, 'unit', public._item_base(it.id), 'qty_made', b.qty_made, 'remaining_pct', round(b.qty_remaining * 100.0 / nullif(b.qty_made, 0), 1), 'item_balance', coalesce(bl.qty, 0), 'fefo_rank', rk.r,
      'value', case when p_cost and bl.avg_cost is not null then round(b.qty_remaining * bl.avg_cost, 2) end, 'qc_blocked', public._qc_batch_blocked60(b.bid),
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[case when b.expires_at is null then 'expires_on' end, case when b.expires_at is null then 'days_left' end,
               case when p_cost and bl.avg_cost is null then 'value' end]) z where z is not null),
      'drill', format('#/batchrep/trace?batch=%s', coalesce(rt.root, b.bid)))
    from b join public.items it on it.id = b.item_id join public.locations lo on lo.id = b.location_id join rk on rk.bid = b.bid left join rt on rt.bid = b.bid left join bal bl on bl.item_id = b.item_id and bl.location_id = b.location_id
      left join public.item_types ty on ty.code = it.item_type cross join t
  union all
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'item_type', coalesce(ty.label_bn, it.item_type), 'item_type_en', coalesce(ty.label_en, ty.label_bn, it.item_type),
      'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'row_kind', 'unbatched', 'batch_no', null, 'batch_id', null, 'root_batch', null, 'origin', null,
      'made_on', null, 'age_days', null, 'age_band', null, 'expires_on', null, 'days_left', null, 'state', 'unbatched', 'qty', round(bl.qty - coalesce(bs.q, 0), 4), 'unit', public._item_base(it.id), 'qty_made', null, 'remaining_pct', null,
      'item_balance', bl.qty, 'fefo_rank', null, 'value', case when p_cost and bl.avg_cost is not null then round((bl.qty - coalesce(bs.q, 0)) * bl.avg_cost, 2) end, 'qc_blocked', false,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array['made_on', 'age_days', 'expires_on', 'days_left', case when p_cost and bl.avg_cost is null then 'value' end]) z where z is not null),
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, bl.location_id))
    from bal bl join public.items it on it.id = bl.item_id join public.locations lo on lo.id = bl.location_id left join bs on bs.item_id = bl.item_id and bs.location_id = bl.location_id left join public.item_types ty on ty.code = it.item_type
   where abs(bl.qty - coalesce(bs.q, 0)) > 0.0005;
$$;
revoke all on function public._r4_batch_rows(int[], uuid, text[], boolean) from public, anon, authenticated;

create or replace function public.batch_stock_rows(p_loc int default null, p_item uuid default null, p_types text[] default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; ty text[]; cost_ok boolean; rows_ jsonb; n int; nb int; nu numeric; thr numeric; src text; notes jsonb := '[]'::jsonb; cap constant int := 1500; cols jsonb; nne int;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  ty := case when p_types is null or cardinality(p_types) = 0 then null else coalesce(array(select t.code from public.item_types t where t.code = any (p_types)), '{}') end;
  cost_ok := public.rpt_cost_ok();
  select coalesce(jsonb_agg(r order by r ->> 'item_code', r ->> 'location_en', (r ->> 'fefo_rank')::int nulls last), '[]'::jsonb), count(*) into rows_, n from (select * from public._r4_batch_rows(locs, p_item, ty, cost_ok) r limit cap + 1) z(r);
  if n > cap then rows_ := rows_ - cap; notes := notes || jsonb_build_array(public._r4_note('truncated', 'More than ' || cap || ' rows: narrow by place, item or type.', cap || 'টির বেশি সারি: জায়গা, আইটেম বা ধরন দিয়ে ছোট করুন।')); end if;
  select count(*) filter (where e ->> 'row_kind' = 'batch'), coalesce(sum((e ->> 'qty')::numeric) filter (where e ->> 'row_kind' = 'unbatched' and (e ->> 'qty')::numeric > 0), 0), count(*) filter (where e ->> 'state' = 'no_expiry')
    into nb, nu, nne from jsonb_array_elements(rows_) e;
  thr := coalesce(public.rule_num('report_expiry_soon_days'), public.rule_num('expiry_warn_days'));
  src := case when public.rule_num('report_expiry_soon_days') is not null then 'report_expiry_soon_days' when public.rule_num('expiry_warn_days') is not null then 'expiry_warn_days' end;
  notes := notes || jsonb_build_array(public._r4_note('info', 'Every open batch of the chosen items and places, in the order the system takes them (FEFO: not expired first, earliest expiry first, expired last), and one "unbatched" line per item and place for the part of the balance that is in no batch (negative = sold beyond stock). Batches + unbatched = the balance of the item at that place. '
      || case when thr is not null then 'Soon = expires within ' || thr::int || ' day(s) (rule ' || src || ').' else 'No "days ahead" rule is set, so only expired batches are marked.' end,
    'প্রতিটি খোলা ব্যাচ, সিস্টেম যে ক্রমে নেয় (FEFO) সেই ক্রমে, আর প্রতিটি আইটেম-জায়গায় ব্যাচ-বহির্ভূত অংশের জন্য একটি "unbatched" লাইন (ঋণাত্মক = স্টকের বাইরে বিক্রি)। ব্যাচ + unbatched = সেই জায়গায় আইটেমের ব্যালান্স।'));
  if nne > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', nne || ' batch(es) have no expiry date captured (shown as "no expiry", not safe). Expiry is captured when the item has a shelf-life rule or the batch is entered with an expiry.',
      nne || 'টি ব্যাচে মেয়াদ লেখা নেই ("no expiry", নিরাপদ নয়)। আইটেমের শেলফ-লাইফ নিয়ম থাকলে বা ব্যাচে মেয়াদ দিলে মেয়াদ লেখা হয়।', 'shelf_life_rules / expires_at')); end if;
  if nu > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', 'Stock of ' || nu::numeric(14,3) || ' (summed over items of different units, so only a pointer) sits in no batch: its receipt date and expiry are not captured, so it cannot be aged or traced.',
      'ব্যাচ ছাড়া স্টক আছে (' || nu::numeric(14,3) || ', ভিন্ন এককের যোগ, তাই শুধু ইঙ্গিত): এর গ্রহণের তারিখ ও মেয়াদ লেখা নেই, তাই বয়স বা ট্রেস করা যায় না।', 'lot / batch on receipt')); end if;
  if not cost_ok then notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
  cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["item_type","ধরন","Type","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["row_kind","ধরন (ব্যাচ/ব্যাচ-ছাড়া)","Row","text"],["batch_no","ব্যাচ","Batch","text"],["origin","উৎস","Origin","text"],["made_on","তৈরি/গ্রহণ","Made / received","date"],["expires_on","মেয়াদ শেষ","Expires","date"],["days_left","বাকি দিন","Days left","int"],["state","অবস্থা","State","text"],["qty","পরিমাণ","Qty","num"],["unit","একক","Unit","text"],["remaining_pct","বাকি %","Remaining %","pct"],["item_balance","আইটেমের ব্যালান্স","Item balance","num"],["fefo_rank","FEFO ক্রম","FEFO order","int"]]'::jsonb
         || case when cost_ok then '[["value","মূল্য","Value","money"]]'::jsonb else '[]'::jsonb end;
  return public._r4_ans(cols, rows_, null, notes, jsonb_build_object('cost_shown', cost_ok, 'batches', nb, 'truncated', n > cap));
end $$;
revoke all on function public.batch_stock_rows(int, uuid, text[]) from public, anon;
grant execute on function public.batch_stock_rows(int, uuid, text[]) to authenticated;

-- #68 ageing of finished goods: batch rows with the age, and a per-item summary (oldest and the quantity-weighted average age)
create or replace function public.fg_ageing_rows(p_loc int default null, p_types text[] default array['finished_good']) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; ty text[]; cost_ok boolean; rows_ jsonb; n int; bands int[]; notes jsonb := '[]'::jsonb; cap constant int := 1500; cols jsonb; sec jsonb; nu int;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  ty := case when p_types is null or cardinality(p_types) = 0 then null else coalesce(array(select t.code from public.item_types t where t.code = any (p_types)), '{}') end;
  cost_ok := public.rpt_cost_ok(); bands := public._r4_bands();
  select coalesce(jsonb_agg(r order by (r ->> 'age_days')::int desc nulls last, r ->> 'item_code'), '[]'::jsonb), count(*) into rows_, n from (select * from public._r4_batch_rows(locs, null, ty, cost_ok) r limit cap + 1) z(r);
  if n > cap then rows_ := rows_ - cap; notes := notes || jsonb_build_array(public._r4_note('truncated', 'More than ' || cap || ' rows: narrow by place or type.', cap || 'টির বেশি সারি: জায়গা বা ধরন দিয়ে ছোট করুন।')); end if;
  select count(*) into nu from jsonb_array_elements(rows_) e where e ->> 'row_kind' = 'unbatched' and (e ->> 'qty')::numeric > 0;
  sec := jsonb_build_array(jsonb_build_object('id', 'by_item', 'title_bn', 'আইটেম অনুযায়ী বয়স', 'title_en', 'Age by item',
    'columns', '[{"key":"item_name","label_bn":"আইটেম","label_en":"Item","type":"text"},{"key":"location","label_bn":"লোকেশন","label_en":"Location","type":"text"},{"key":"batches","label_bn":"ব্যাচ","label_en":"Batches","type":"int"},{"key":"qty","label_bn":"পরিমাণ","label_en":"Qty","type":"num"},{"key":"oldest_days","label_bn":"সবচেয়ে পুরনো (দিন)","label_en":"Oldest (days)","type":"int"},{"key":"avg_days","label_bn":"গড় বয়স (পরিমাণ ধরে, দিন)","label_en":"Average age (qty weighted, days)","type":"num"}]'::jsonb,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('item_name', g.nm, 'location', g.loc, 'batches', g.c, 'qty', g.q, 'oldest_days', g.o, 'avg_days', g.a) order by g.o desc, g.nm)
                        from (select e ->> 'item_name' as nm, e ->> 'location_en' as loc, count(*) as c, sum((e ->> 'qty')::numeric) as q, max((e ->> 'age_days')::int) as o,
                                     round(sum((e ->> 'qty')::numeric * (e ->> 'age_days')::int) / nullif(sum((e ->> 'qty')::numeric), 0), 1) as a
                                from jsonb_array_elements(rows_) e where e ->> 'row_kind' = 'batch' group by 1, 2) g), '[]'::jsonb)));
  if bands is null then
    notes := notes || jsonb_build_array(public._r4_note('data_needed', 'No age bands are set (rule report_aging_buckets, e.g. 1,3,7). The age is shown in days for every batch; no band is invented.',
      'বয়সের ভাগ বসানো নেই (নিয়ম report_aging_buckets, যেমন 1,3,7)। প্রতিটি ব্যাচের বয়স দিনে দেখানো; কোনো ভাগ নিজে বানানো হয়নি।', 'report_aging_buckets'));
  else notes := notes || jsonb_build_array(public._r4_note('info', 'Age bands (days) come from the rule report_aging_buckets.', 'বয়সের ভাগ (দিন) নিয়ম report_aging_buckets থেকে।')); end if;
  notes := notes || jsonb_build_array(public._r4_note('info', 'Age = days since the batch was made. Finished goods are made in the app, so the made date is known; a transferred batch keeps the made date of its production. Stock that sits in no batch has no made date and is listed as "unbatched".',
    'বয়স = ব্যাচ তৈরির পর কত দিন। তৈরি পণ্য অ্যাপেই তৈরি হয়, তাই তৈরির তারিখ জানা; ট্রান্সফার হলেও ব্যাচ উৎপাদনের তারিখ রাখে। যে স্টক কোনো ব্যাচে নেই তার তৈরির তারিখ নেই, "unbatched" দেখানো হয়।'));
  if nu > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', nu || ' item/place line(s) hold stock in no batch (age not captured).', nu || 'টি আইটেম-জায়গায় ব্যাচ ছাড়া স্টক আছে (বয়স লেখা নেই)।', 'batch')); end if;
  if not cost_ok then notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
  cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["row_kind","ধরন","Row","text"],["batch_no","ব্যাচ","Batch","text"],["made_on","তৈরি","Made","date"],["age_days","বয়স (দিন)","Age (days)","int"],["age_band","বয়সের ভাগ","Age band","text"],["expires_on","মেয়াদ শেষ","Expires","date"],["days_left","বাকি দিন","Days left","int"],["state","অবস্থা","State","text"],["qty","বাকি পরিমাণ","Qty left","num"],["unit","একক","Unit","text"],["qty_made","তৈরি হয়েছিল","Qty made","num"],["remaining_pct","বাকি %","Remaining %","pct"]]'::jsonb
         || case when cost_ok then '[["value","মূল্য","Value","money"]]'::jsonb else '[]'::jsonb end;
  return public._r4_ans(cols, rows_, null, notes, jsonb_build_object('cost_shown', cost_ok, 'sections', sec, 'truncated', n > cap, 'bands', to_jsonb(bands)));
end $$;
revoke all on function public.fg_ageing_rows(int, text[]) from public, anon;
grant execute on function public.fg_ageing_rows(int, text[]) to authenticated;

select public._r3_lockdown();
select public._r4_lockdown();
notify pgrst, 'reload schema';
