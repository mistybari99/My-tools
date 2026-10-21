-- ============================================================
-- BOS tool · Phase 425 (RPT-B2 R4b): where did each production batch go. Read-only. Paste after phase424. Safe to paste twice. Open to report_stock holders at their own places.
--   #80 unsold_by_batch       for every production batch: made, sold (net of voids and refunds), wasted, other (count / issue), short in transit, still on the road, still in stock, and the check that they add up
--   #84 fg_distribution       the same by outlet: what each outlet received from each batch, sold, wasted, holds, is still waiting for; sales that carry no batch are a line of their own
--   #79 expired_damaged_unsold  wastage entries grouped as expired / damaged / unsold, and customer returns marked damaged (whether they went back into sellable stock)
--   fg_batch_rows(batch)      the source rows of one production batch family (drill of the three reports above)
-- Wastage reason "unsold" is added to the existing list wastage_reasons (a list value, BUILD-RULES 4); nothing else in the list is touched.
-- A batch family is the production batch plus the batch rows its transfers created at the receivers (the batch travels with the goods). Sales made beyond stock carry no batch and cannot be traced.
-- ============================================================

insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('wastage_reasons', 'unsold', 'বিক্রি হয়নি (অবিক্রীত)', 'বিক্রি হয়নি / Unsold', 'Unsold', 7)
on conflict (list_code, value_code) do nothing;

-- per production batch: where the quantity is (one row per root)
create or replace function public._r4_fg_batch_agg() returns table (root bigint, made_qty numeric, sold_net numeric, wasted numeric, other_qty numeric, in_transit numeric, short_qty numeric, remaining numeric, unaccounted numeric)
language sql stable security definer set search_path = public as $$
  with lin as (select * from public._r4_lineage()),
  lr as (select ln.root, l.* from lin ln join public.stock_ledger l on l.batch_id = ln.batch),
  tr as (
    select lr.root, lr.ref_id, -sum(lr.qty_delta) filter (where lr.reason = 'transfer_out') as out_q, sum(lr.qty_delta) filter (where lr.reason = 'transfer_in') as in_q, sum(lr.qty_delta) filter (where lr.reason = 'reversal') as rev_q
      from lr where lr.ref_type = 'transfer' group by 1, 2),
  trc as (
    select tr.root, sum(case when t.status = 'sent' then coalesce(tr.out_q, 0) - coalesce(tr.in_q, 0) - coalesce(tr.rev_q, 0) else 0 end) as in_transit,
           sum(case when t.status = 'received' then coalesce(tr.out_q, 0) - coalesce(tr.in_q, 0) else 0 end) as short_q
      from tr join public.stock_transfers t on t.id::text = tr.ref_id group by 1),
  rem as (select ln.root, sum(b.qty_remaining) as q from lin ln join public.stock_batches b on b.id = ln.batch group by 1),
  agg as (
    select lr.root,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason in ('sale_out', 'sale_void_in', 'sale_return')), 0) as sold_net,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason = 'wastage'), 0) as wasted,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason in ('count_adjust', 'issue_out', 'purchase_return') or (lr.reason = 'reversal' and coalesce(lr.ref_type, '') <> 'transfer')), 0) as other_q
      from lr group by lr.root)
  select b.id, b.qty_made, coalesce(a.sold_net, 0), coalesce(a.wasted, 0), coalesce(a.other_q, 0), coalesce(c.in_transit, 0), coalesce(c.short_q, 0), coalesce(r.q, 0),
         round(b.qty_made - (coalesce(a.sold_net, 0) + coalesce(a.wasted, 0) + coalesce(a.other_q, 0) + coalesce(c.in_transit, 0) + coalesce(c.short_q, 0) + coalesce(r.q, 0)), 4)
    from (select distinct root from lin) x join public.stock_batches b on b.id = x.root left join agg a on a.root = x.root left join trc c on c.root = x.root left join rem r on r.root = x.root;
$$;
revoke all on function public._r4_fg_batch_agg() from public, anon, authenticated;

-- #80 unsold finished goods by production batch
create or replace function public.unsold_by_batch(p_from date default null, p_to date default null, p_loc int default null, p_types text[] default null, p_open_only boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
        locs int[]; ty text[]; cost_ok boolean := public.rpt_cost_ok(); rows_ jsonb; n int; notes jsonb := '[]'::jsonb; cols jsonb; bad int; thr numeric; cap constant int := 800; noexp int;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  ty := case when p_types is null or cardinality(p_types) = 0 then null else coalesce(array(select x.code from public.item_types x where x.code = any (p_types)), '{}') end;
  thr := coalesce(public.rule_num('report_expiry_soon_days'), public.rule_num('expiry_warn_days'));
  select coalesce(jsonb_agg(z.j order by (z.j ->> 'made_on') desc, z.j ->> 'item_code'), '[]'::jsonb), count(*) into rows_, n from (
    select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
        'batch_id', b.id, 'made_on', (b.made_at at time zone 'Asia/Dhaka')::date, 'age_days', today - (b.made_at at time zone 'Asia/Dhaka')::date, 'expires_on', (b.expires_at at time zone 'Asia/Dhaka')::date,
        'days_left', (b.expires_at at time zone 'Asia/Dhaka')::date - today,
        'state', case when a.remaining + a.in_transit <= 0 then 'finished' when b.expires_at is null then 'no_expiry' when (b.expires_at at time zone 'Asia/Dhaka')::date < today then 'expired'
                      when (b.expires_at at time zone 'Asia/Dhaka')::date <= today + coalesce(thr::int, -1) then 'soon' else 'ok' end,
        'unit', public._item_base(it.id), 'made_qty', a.made_qty, 'sold_qty', a.sold_net, 'wasted_qty', a.wasted, 'other_qty', a.other_qty, 'short_qty', a.short_qty, 'in_transit_qty', a.in_transit,
        'remaining_qty', a.remaining, 'unsold_qty', a.remaining + a.in_transit, 'unsold_pct', case when a.made_qty > 0 then round((a.remaining + a.in_transit) * 100.0 / a.made_qty, 1) end, 'unaccounted_qty', a.unaccounted,
        'unit_cost', case when cost_ok then pc.unit_cost end, 'unsold_value', case when cost_ok and pc.unit_cost is not null then round((a.remaining + a.in_transit) * pc.unit_cost, 2) end,
        '_nc', (select coalesce(jsonb_agg(zz), '[]'::jsonb) from unnest(array[case when b.expires_at is null then 'expires_on' end, case when b.expires_at is null then 'days_left' end,
                 case when cost_ok and pc.unit_cost is null then 'unit_cost' end, case when cost_ok and pc.unit_cost is null then 'unsold_value' end]) zz where zz is not null),
        'drill', format('#/batchrep/trace?batch=%s', b.id)) as j
      from public._r4_fg_batch_agg() a join public.stock_batches b on b.id = a.root join public.items it on it.id = b.item_id join public.locations lo on lo.id = b.location_id
        left join lateral (select l.unit_cost from public.stock_ledger l where l.batch_id = b.id and l.reason = 'production_in' order by l.id limit 1) pc on true
     where (b.made_at at time zone 'Asia/Dhaka')::date between f and t and b.location_id = any (locs) and (ty is null or it.item_type = any (ty))
       and (not p_open_only or a.remaining + a.in_transit > 0)
     order by b.made_at desc limit cap + 1) z;
  if n > cap then rows_ := rows_ - cap; notes := notes || jsonb_build_array(public._r4_note('truncated', 'More than ' || cap || ' batches: narrow the dates.', cap || 'টির বেশি ব্যাচ: তারিখ ছোট করুন।')); end if;
  select count(*) into bad from jsonb_array_elements(rows_) e where abs((e ->> 'unaccounted_qty')::numeric) > 0.0005;
  select count(*) into noexp from jsonb_array_elements(rows_) e where e ->> 'state' = 'no_expiry';
  notes := notes || jsonb_build_array(public._r4_note('info', 'Per production batch: made = sold (net of voids and refunds) + wasted + other (count corrections, issues) + short in transit + on the road + in stock. "Unsold" = in stock + on the road. The family of a batch includes the batch rows its transfers created at the outlets. Sales made beyond stock carry no batch and are not in any row (see the distribution report). Value = unsold quantity x the cost recorded at production; where none was recorded it is empty (not captured).',
    'প্রতিটি উৎপাদন ব্যাচ: তৈরি = বিক্রি (বাতিল ও ফেরত বাদে) + নষ্ট + অন্যান্য (গণনা সংশোধন, ইস্যু) + পথে কম + পথে আছে + স্টকে আছে। "অবিক্রীত" = স্টকে + পথে। ব্যাচের পরিবারে ট্রান্সফারে আউটলেটে তৈরি ব্যাচ-সারিও ধরা। স্টকের বাইরে বিক্রির কোনো ব্যাচ নেই, তাই কোনো সারিতে নেই (বিতরণ রিপোর্ট দেখুন)। মূল্য = অবিক্রীত পরিমাণ × উৎপাদনে লেখা খরচ; না থাকলে ফাঁকা।'));
  if bad > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', bad || ' batch(es) do not add up (made does not equal the parts). The column "not accounted" shows the difference; open the batch to see its rows.',
      bad || 'টি ব্যাচের হিসাব মিলছে না। "হিসাবহীন" কলামে পার্থক্য; ব্যাচ খুলে সারি দেখুন।', 'stock_batches.qty_remaining')); end if;
  if noexp > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', noexp || ' batch(es) have no expiry date captured (no shelf-life rule for the item).', noexp || 'টি ব্যাচে মেয়াদ লেখা নেই (আইটেমের শেলফ-লাইফ নিয়ম নেই)।', 'shelf_life_rules')); end if;
  if not cost_ok then notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
  cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["location_bn","কোথায় তৈরি","Made at","text"],["location_en","Made at (EN)","Made at (EN)","text"],["batch_id","ব্যাচ নং","Batch","int"],["made_on","তৈরি","Made","date"],["age_days","বয়স (দিন)","Age (days)","int"],["expires_on","মেয়াদ শেষ","Expires","date"],["days_left","বাকি দিন","Days left","int"],["state","অবস্থা","State","text"],["unit","একক","Unit","text"],["made_qty","তৈরি","Made","num"],["sold_qty","বিক্রি (নিট)","Sold (net)","num"],["wasted_qty","নষ্ট","Wasted","num"],["other_qty","অন্যান্য","Other","num"],["short_qty","পথে কম","Short in transit","num"],["in_transit_qty","পথে আছে","On the road","num"],["remaining_qty","স্টকে আছে","In stock","num"],["unsold_qty","অবিক্রীত","Unsold","num"],["unsold_pct","অবিক্রীত %","Unsold %","pct"],["unaccounted_qty","হিসাবহীন","Not accounted","num"]]'::jsonb
         || case when cost_ok then '[["unit_cost","উৎপাদন খরচ (প্রতি একক)","Cost per unit","money"],["unsold_value","অবিক্রীতের মূল্য","Unsold value","money"]]'::jsonb else '[]'::jsonb end;
  return public._r4_ans(cols, rows_, null, notes, jsonb_build_object('from', f, 'to', t, 'cost_shown', cost_ok, 'truncated', n > cap));
end $$;
revoke all on function public.unsold_by_batch(date, date, int, text[], boolean) from public, anon;
grant execute on function public.unsold_by_batch(date, date, int, text[], boolean) to authenticated;

-- #84 distribution of finished goods by outlet and batch
create or replace function public.fg_distribution(p_from date default null, p_to date default null, p_loc int default null, p_types text[] default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); locs int[]; ty text[]; cost_ok boolean := public.rpt_cost_ok();
        rows_ jsonb; n int; notes jsonb := '[]'::jsonb; cols jsonb; nobatch numeric; cap constant int := 1500;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  ty := case when p_types is null or cardinality(p_types) = 0 then null else coalesce(array(select x.code from public.item_types x where x.code = any (p_types)), '{}') end;
  with roots as (
    select b.id as root, b.item_id, b.location_id as made_loc, b.made_at, b.expires_at from public.stock_batches b join public.items it on it.id = b.item_id
     where b.id in (select distinct l.root from public._r4_lineage() l) and (b.made_at at time zone 'Asia/Dhaka')::date between f and t and (ty is null or it.item_type = any (ty))),
  lr as (select ln.root, l.* from public._r4_lineage() ln join roots r on r.root = ln.root join public.stock_ledger l on l.batch_id = ln.batch),
  perloc as (
    select lr.root, lr.location_id,
           coalesce(sum(lr.qty_delta) filter (where lr.reason in ('production_in', 'transfer_in')), 0) as in_qty,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason in ('sale_out', 'sale_void_in', 'sale_return')), 0) as sold_net,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason = 'wastage'), 0) as wasted,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason in ('count_adjust', 'issue_out', 'purchase_return')), 0) as other_q,
           coalesce(-sum(lr.qty_delta) filter (where lr.reason = 'transfer_out'), 0) as sent_on
      from lr group by lr.root, lr.location_id),
  rem as (select ln.root, b.location_id, sum(b.qty_remaining) as q from public._r4_lineage() ln join roots r on r.root = ln.root join public.stock_batches b on b.id = ln.batch group by 1, 2),
  tr as (
    select lr.root, lr.ref_id, -sum(lr.qty_delta) filter (where lr.reason = 'transfer_out') as out_q, sum(lr.qty_delta) filter (where lr.reason = 'transfer_in') as in_q, sum(lr.qty_delta) filter (where lr.reason = 'reversal') as rev_q
      from lr where lr.ref_type = 'transfer' group by 1, 2),
  dest as (
    select tr.root, x.to_location_id as location_id,
           sum(case when x.status = 'sent' then coalesce(tr.out_q, 0) - coalesce(tr.in_q, 0) - coalesce(tr.rev_q, 0) else 0 end) as on_road,
           sum(case when x.status = 'received' then coalesce(tr.out_q, 0) - coalesce(tr.in_q, 0) else 0 end) as short_q
      from tr join public.stock_transfers x on x.id::text = tr.ref_id group by 1, 2),
  keys as (select root, location_id from perloc union select root, location_id from rem union select root, location_id from dest),
  rr as (
    select r.root, r.item_id, k.location_id, r.made_at, r.expires_at, r.made_loc, coalesce(p.in_qty, 0) as in_qty, coalesce(p.sold_net, 0) as sold_net, coalesce(p.wasted, 0) as wasted, coalesce(p.other_q, 0) as other_q,
           coalesce(p.sent_on, 0) as sent_on, coalesce(m.q, 0) as remaining, coalesce(d.on_road, 0) as on_road, coalesce(d.short_q, 0) as short_q
      from keys k join roots r on r.root = k.root left join perloc p on p.root = k.root and p.location_id = k.location_id left join rem m on m.root = k.root and m.location_id = k.location_id
        left join dest d on d.root = k.root and d.location_id = k.location_id where k.location_id = any (locs)),
  js as (
    select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'batch_id', rr.root, 'made_on', (rr.made_at at time zone 'Asia/Dhaka')::date,
        'expires_on', (rr.expires_at at time zone 'Asia/Dhaka')::date, 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'role', case when rr.location_id = rr.made_loc then 'made_here' else 'outlet' end,
        'unit', public._item_base(it.id), 'received_qty', rr.in_qty, 'sold_qty', rr.sold_net, 'wasted_qty', rr.wasted, 'other_qty', rr.other_q, 'sent_on_qty', rr.sent_on, 'short_qty', rr.short_q,
        'on_road_qty', rr.on_road, 'remaining_qty', rr.remaining,
        'sold_pct', case when rr.in_qty > 0 then round(rr.sold_net * 100.0 / rr.in_qty, 1) end,
        '_nc', case when rr.expires_at is null then '["expires_on"]'::jsonb end,
        'drill', format('#/batchrep/trace?batch=%s', rr.root)) as j, rr.made_at as mk, it.code as ic
      from rr join public.items it on it.id = rr.item_id join public.locations lo on lo.id = rr.location_id
    union all
    select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'batch_id', null, 'made_on', null, 'expires_on', null, 'location_bn', lo.name_bn,
        'location_en', coalesce(lo.name_en, lo.name_bn), 'role', 'no_batch', 'unit', public._item_base(it.id), 'received_qty', null, 'sold_qty', -sum(l.qty_delta), 'wasted_qty', null, 'other_qty', null, 'sent_on_qty', null, 'short_qty', null,
        'on_road_qty', null, 'remaining_qty', null, 'sold_pct', null, '_nc', '["batch_id","made_on","expires_on","received_qty"]'::jsonb, 'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, l.location_id)), now() - interval '100 years', it.code
      from public.stock_ledger l join public.items it on it.id = l.item_id join public.locations lo on lo.id = l.location_id
     where l.batch_id is null and l.reason in ('sale_out', 'sale_void_in', 'sale_return') and (l.made_at at time zone 'Asia/Dhaka')::date between f and t and l.location_id = any (locs) and (ty is null or it.item_type = any (ty))
       and it.id in (select item_id from roots)
     group by it.id, it.code, it.name_bn, it.name_en, lo.id, lo.name_bn, lo.name_en, l.location_id having sum(l.qty_delta) <> 0)
  select coalesce(jsonb_agg(js.j order by js.mk desc, js.ic), '[]'::jsonb), count(*) into rows_, n from js;
  select coalesce(sum((e ->> 'sold_qty')::numeric), 0) into nobatch from jsonb_array_elements(rows_) e where e ->> 'role' = 'no_batch';
  if n > cap then rows_ := rows_ - cap; notes := notes || jsonb_build_array(public._r4_note('truncated', 'More than ' || cap || ' rows: narrow the dates or the place.', cap || 'টির বেশি সারি: তারিখ বা জায়গা ছোট করুন।')); end if;
  notes := notes || jsonb_build_array(public._r4_note('info', 'One row per production batch and place: what the place received from the batch (made here counts as received at the production place), what it sold (net of voids and refunds), wasted, corrected by a count, passed on to another place, holds now, and what is still on the road to it. "Short" is what was lost between sending and receiving. The line "no batch" is the sales of the same items that carry no batch (sold beyond stock): they cannot be linked to a production batch.',
    'প্রতিটি উৎপাদন ব্যাচ ও জায়গার জন্য একটি সারি: জায়গা ব্যাচ থেকে কত পেয়েছে (তৈরির জায়গায় তৈরি = পাওয়া), কত বিক্রি (বাতিল ও ফেরত বাদে), নষ্ট, গণনায় সংশোধন, অন্য জায়গায় পাঠানো, এখন কত আছে, আর কত এখনও পথে। "কম" = পাঠানো ও পাওয়ার মাঝে হারানো। "no batch" সারি = একই আইটেমের যে বিক্রির ব্যাচ নেই (স্টকের বাইরে বিক্রি); এগুলো উৎপাদন ব্যাচের সাথে মেলানো যায় না।'));
  if nobatch > 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', 'Sales with no batch exist for these items (sold beyond stock): their batch, made date and expiry are not captured.',
      'এই আইটেমগুলোর ব্যাচ-ছাড়া বিক্রি আছে (স্টকের বাইরে বিক্রি): এদের ব্যাচ, তৈরির তারিখ ও মেয়াদ লেখা নেই।', 'stock_ledger.batch_id')); end if;
  cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["batch_id","ব্যাচ নং","Batch","int"],["made_on","তৈরি","Made","date"],["expires_on","মেয়াদ শেষ","Expires","date"],["location_bn","জায়গা","Place","text"],["location_en","Place (EN)","Place (EN)","text"],["role","ভূমিকা","Role","text"],["unit","একক","Unit","text"],["received_qty","পেয়েছে","Received","num"],["sold_qty","বিক্রি (নিট)","Sold (net)","num"],["wasted_qty","নষ্ট","Wasted","num"],["other_qty","অন্যান্য","Other","num"],["sent_on_qty","আরেক জায়গায় পাঠিয়েছে","Sent on","num"],["short_qty","পথে কম","Short in transit","num"],["on_road_qty","পথে আছে","On the road","num"],["remaining_qty","এখন আছে","Holds now","num"],["sold_pct","বিক্রি % (পাওয়ার)","Sold % of received","pct"]]'::jsonb;
  return public._r4_ans(cols, rows_, null, notes, jsonb_build_object('from', f, 'to', t, 'cost_shown', cost_ok, 'truncated', n > cap));
end $$;
revoke all on function public.fg_distribution(date, date, int, text[]) from public, anon;
grant execute on function public.fg_distribution(date, date, int, text[]) to authenticated;

-- #79 expired, damaged and unsold: wastage entries by class, and customer returns marked damaged
create or replace function public.expired_damaged_unsold(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); locs int[]; cost_ok boolean := public.rpt_cost_ok(); rows_ jsonb; n int;
        notes jsonb := '[]'::jsonb; cols jsonb; sec jsonb; cap constant int := 1500; n_unsold int; n_other int; nrules int; n_ret int; n_ret_back int;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  select coalesce(jsonb_agg(z.j order by z.j ->> 'day' desc, z.j ->> 'item_code'), '[]'::jsonb), count(*) into rows_, n from (
    select jsonb_build_object('day', (w.made_at at time zone 'Asia/Dhaka')::date, 'class', case w.reason_code when 'expired' then 'expired' when 'unsold' then 'unsold' else 'damaged' end, 'source', 'wastage',
        'reason', coalesce(o.label_en, w.reason_code), 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
        'qty', w.qty, 'unit', public._item_base(it.id), 'batch_id', sb.id, 'batch_made_on', (sb.made_at at time zone 'Asia/Dhaka')::date, 'batch_age_days', case when sb.id is not null then (w.made_at at time zone 'Asia/Dhaka')::date - (sb.made_at at time zone 'Asia/Dhaka')::date end,
        'value', case when cost_ok and sl.unit_cost is not null then round(w.qty * sl.unit_cost, 2) end, 'back_in_stock', null, 'note', w.note, 'who', w.created_staff,
        '_nc', (select coalesce(jsonb_agg(zz), '[]'::jsonb) from unnest(array[case when cost_ok and sl.unit_cost is null then 'value' end, case when sb.id is null then 'batch_id' end]) zz where zz is not null),
        'drill', case when sb.id is not null then format('#/batchrep/trace?batch=%s', coalesce((select min(l2.root) from public._r4_lineage() l2 where l2.batch = sb.id), sb.id)) else format('#/stockrep/ledger?item=%s&loc=%s', it.id, w.location_id) end) as j
      from public.stock_wastage w join public.items it on it.id = w.item_id join public.locations lo on lo.id = w.location_id left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.reason_code
        left join public.stock_ledger sl on sl.id = w.ledger_id left join public.stock_batches sb on sb.id = coalesce(w.batch_id, sl.batch_id)
     where w.reason_code in ('expired', 'unsold', 'broken', 'burnt', 'spoiled') and (w.made_at at time zone 'Asia/Dhaka')::date between f and t and w.location_id = any (locs)
    union all
    select jsonb_build_object('day', (r.created_at at time zone 'Asia/Dhaka')::date, 'class', 'damaged', 'source', 'customer return', 'reason', 'Damaged (customer return)', 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn),
        'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'qty', (e ->> 'qty')::numeric, 'unit', e ->> 'unit', 'batch_id', null, 'batch_made_on', null, 'batch_age_days', null,
        'value', null, 'back_in_stock', coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.item_id = it.id), 0) > 0,
        'note', r.note, 'who', r.created_staff, '_nc', '["batch_id","value"]'::jsonb, 'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, r.location_id))
      from public.sale_returns r cross join lateral jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
        join public.items it on it.id::text = e ->> 'item_id' join public.locations lo on lo.id = r.location_id
     where r.status = 'done' and r.reason_code = 'damaged' and (r.created_at at time zone 'Asia/Dhaka')::date between f and t and r.location_id = any (locs)) z;
  if n > cap then rows_ := rows_ - cap; notes := notes || jsonb_build_array(public._r4_note('truncated', 'More than ' || cap || ' rows: narrow the dates.', cap || 'টির বেশি সারি: তারিখ ছোট করুন।')); end if;
  select count(*) into n_unsold from public.stock_wastage w where w.reason_code = 'unsold' and (w.made_at at time zone 'Asia/Dhaka')::date between f and t and w.location_id = any (locs);
  select count(*) into n_other from public.stock_wastage w where w.reason_code not in ('expired', 'unsold', 'broken', 'burnt', 'spoiled') and (w.made_at at time zone 'Asia/Dhaka')::date between f and t and w.location_id = any (locs);
  select count(*), count(*) filter (where (e ->> 'back_in_stock')::boolean) into n_ret, n_ret_back from jsonb_array_elements(rows_) e where e ->> 'source' = 'customer return';
  select count(*) into nrules from public.w1c_return_class_rules;
  sec := jsonb_build_array(jsonb_build_object('id', 'by_class', 'title_bn', 'ধরন অনুযায়ী', 'title_en', 'By class',
    'columns', '[{"key":"class","label_bn":"ধরন","label_en":"Class","type":"text"},{"key":"entries","label_bn":"এন্ট্রি","label_en":"Entries","type":"int"}]'::jsonb || case when cost_ok then '[{"key":"value","label_bn":"মূল্য (খরচ জানা অংশ)","label_en":"Value (costed part)","type":"money"},{"key":"uncosted","label_bn":"খরচ অজানা","label_en":"No cost","type":"int"}]'::jsonb else '[]'::jsonb end,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('class', g.c, 'entries', g.n, 'value', case when cost_ok then g.v end, 'uncosted', case when cost_ok then g.u end) order by g.c)
                        from (select e ->> 'class' as c, count(*) as n, coalesce(sum((e ->> 'value')::numeric), 0) as v, count(*) filter (where e ->> 'source' = 'wastage' and e -> 'value' = 'null'::jsonb) as u from jsonb_array_elements(rows_) e group by 1) g), '[]'::jsonb)));
  notes := notes || jsonb_build_array(public._r4_note('info', 'Classes: expired = wastage reason Expired; unsold = reason Unsold (unsold stock written off at the end of the day); damaged = reasons Broken, Burnt, Spoiled, and customer returns marked Damaged. Other reasons (sample, staff meal, unknown: ' || n_other || ' entries in the period) are not in this list; see the Wastage report.',
    'ধরন: expired = কারণ "মেয়াদ শেষ"; unsold = কারণ "অবিক্রীত" (দিনশেষে অবিক্রীত মাল বাদ); damaged = কারণ ভেঙে/পুড়ে/নষ্ট এবং গ্রাহকের "ক্ষতিগ্রস্ত" ফেরত। অন্য কারণ (নমুনা, স্টাফ খাবার, অজানা: ' || n_other || 'টি) এই তালিকায় নেই; "অপচয়" রিপোর্ট দেখুন।'));
  if n_unsold = 0 then notes := notes || jsonb_build_array(public._r4_note('info', 'No entry with the reason Unsold in this period. Staff write unsold stock off with the reason Unsold (the reason was added to the wastage reasons list).',
      'এই সময়ে "অবিক্রীত" কারণে কোনো এন্ট্রি নেই। অবিক্রীত মাল বাদ দিতে কারণ "অবিক্রীত" দিন (কারণটি অপচয়ের কারণ তালিকায় যোগ হয়েছে)।')); end if;
  if n_ret > 0 and nrules = 0 then notes := notes || jsonb_build_array(public._r4_note('data_needed', n_ret_back || ' of ' || n_ret || ' damaged customer return(s) went BACK into sellable stock: no return class rules are set (damaged items are restocked unless the owner sets a rule).',
      n_ret || 'টি ক্ষতিগ্রস্ত ফেরতের মধ্যে ' || n_ret_back || 'টি বিক্রির স্টকে ফিরে গেছে: ফেরতের শ্রেণি-নিয়ম বসানো নেই (মালিক নিয়ম না দিলে ক্ষতিগ্রস্ত মালও স্টকে ফেরে)।', 'w1c_return_class_rules')); end if;
  if not cost_ok then notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
  cols := '[["day","তারিখ","Date","date"],["class","ধরন","Class","text"],["source","উৎস","Source","text"],["reason","কারণ","Reason","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["qty","পরিমাণ","Qty","num"],["unit","একক","Unit","text"],["batch_id","ব্যাচ","Batch","int"],["batch_made_on","ব্যাচ তৈরি","Batch made","date"],["batch_age_days","ক্ষতির সময়ে বয়স (দিন)","Age when lost (days)","int"],["back_in_stock","স্টকে ফিরেছে","Back in stock","text"],["note","নোট","Note","text"],["who","কে","Who","text"]]'::jsonb
         || case when cost_ok then '[["value","মূল্য","Value","money"]]'::jsonb else '[]'::jsonb end;
  return public._r4_ans(cols, rows_, null, notes, jsonb_build_object('from', f, 'to', t, 'cost_shown', cost_ok, 'sections', sec, 'truncated', n > cap));
end $$;
revoke all on function public.expired_damaged_unsold(date, date, int) from public, anon;
grant execute on function public.expired_damaged_unsold(date, date, int) to authenticated;

-- the source rows of one production batch family (drill target of the three reports and of the batch stock list)
create or replace function public.fg_batch_rows(p_batch bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cost_ok boolean := public.rpt_cost_ok(); b public.stock_batches; it public.items; rt_id bigint; agg record; fam jsonb; rows_ jsonb; n int; cap constant int := 1000;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  select min(l.root) into rt_id from public._r4_lineage() l where l.batch = p_batch;
  if rt_id is null then rt_id := p_batch; end if;
  select * into b from public.stock_batches where id = rt_id;
  if not found then raise exception 'batch_not_found'; end if;
  if not public.can_loc(b.location_id) and not exists (select 1 from public._r4_lineage() l join public.stock_batches x on x.id = l.batch where l.root = rt_id and public.can_loc(x.location_id)) then raise exception 'not allowed for this location'; end if;
  select * into it from public.items where id = b.item_id;
  select * into agg from public._r4_fg_batch_agg() a where a.root = b.id;
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', x.id, 'location_id', x.location_id, 'location', coalesce(lo.name_en, lo.name_bn), 'made_on', (x.made_at at time zone 'Asia/Dhaka')::date,
      'expires_on', (x.expires_at at time zone 'Asia/Dhaka')::date, 'qty_made', x.qty_made, 'qty_remaining', x.qty_remaining, 'is_root', x.id = rt_id) order by x.id), '[]'::jsonb) into fam
    from public._r4_lineage() l join public.stock_batches x on x.id = l.batch join public.locations lo on lo.id = x.location_id where l.root = rt_id and public.can_loc(x.location_id);
  select coalesce(jsonb_agg(z.j order by z.mk, z.id), '[]'::jsonb), count(*) into rows_, n from (
    select jsonb_build_object('id', l.id, 'at', l.made_at, 'day', (l.made_at at time zone 'Asia/Dhaka')::date, 'time', to_char(l.made_at at time zone 'Asia/Dhaka', 'HH24:MI'), 'location', coalesce(lo.name_en, lo.name_bn), 'batch_id', l.batch_id,
        'reason', l.reason, 'qty_delta', l.qty_delta, 'unit_cost', case when cost_ok then l.unit_cost end, 'note', l.note, 'doc', public._r4_doc(l.reason, l.ref_type, l.ref_id, cost_ok)) as j, l.made_at as mk, l.id
      from public._r4_lineage() ln join public.stock_ledger l on l.batch_id = ln.batch join public.locations lo on lo.id = l.location_id where ln.root = rt_id and public.can_loc(l.location_id) order by l.made_at, l.id limit cap + 1) z;
  if n > cap then rows_ := rows_ - cap; end if;
  return jsonb_build_object('batch_id', rt_id, 'item', jsonb_build_object('code', it.code, 'name_bn', it.name_bn, 'name_en', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id)),
    'made_on', (b.made_at at time zone 'Asia/Dhaka')::date, 'expires_on', (b.expires_at at time zone 'Asia/Dhaka')::date, 'location_id', b.location_id,
    'summary', jsonb_build_object('made_qty', agg.made_qty, 'sold_qty', agg.sold_net, 'wasted_qty', agg.wasted, 'other_qty', agg.other_qty, 'short_qty', agg.short_qty, 'in_transit_qty', agg.in_transit, 'remaining_qty', agg.remaining, 'unaccounted_qty', agg.unaccounted),
    'family', fam, 'rows', rows_, 'truncated', n > cap, 'cost_shown', cost_ok);
end $$;
revoke all on function public.fg_batch_rows(bigint) from public, anon;
grant execute on function public.fg_batch_rows(bigint) to authenticated;

select public._r4_lockdown();
notify pgrst, 'reload schema';
