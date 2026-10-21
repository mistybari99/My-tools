-- ============================================================
-- BOS tool · Phase 420 (RPT-B2 R1): HONESTY FIXES in the existing stock and purchase reports (audit docs/REPORTS_AUDIT_2.md, items #57 #69 #94 #98 and findings 6, 7, 10).
-- Paste after phase99. Additive and safe to paste twice. No old phase file is edited. Nothing here writes business data; every report stays OPEN to the roles that already hold
-- report_stock / report_purchase (no new grant, no setting is switched, nothing sits behind an OFF setting).
--
-- Rules kept (owner): a missing figure is shown as "not captured" naming the field or form, never as 0 and never as an estimate; no limit, default or price is invented
-- (a threshold that is not set is told in a notice); existing figures are not changed, columns and notices are added. The only value changes are the three the owner asked for:
-- a negative balance reads 'negative' (was 'low'), the expiry list uses ONE threshold, the supplier overdue is empty (not 0) where credit days are not set.
--
-- What this phase adds
--   1. Plumbing, so a report of engine 2 or 3 can be extended in place without copying its query:
--        * report_catalog2(): an engine-3 row (report_defs3) with the same key REPLACES the engine-2 entry (no duplicate in the list).
--        * report_run2(): after the normal answer, a private decorator  _r4d_<key>(filters, answer)  (if one exists) may add notes, sub-totals, hide cost columns.
--          Later phases (421 to 425) add decorators by creating a function; they never re-create report_run2 again.
--   2. #57 / #60-62  stock_balance (engine 3, same key and route): item-type filter, state 'negative', per-line "no cost recorded" flag, notice with the uncosted count,
--        sub-totals per place, per place kind and per item type (answer field "subtotals"), drill to the item ledger.
--   3. #69 expiry_soon (engine 3, same key): ONE threshold = rule report_expiry_soon_days if set, else the existing rule expiry_warn_days; batches with stock but no expiry date
--        are listed in a "no expiry captured" row per item and place (never "nothing expiring"); notices say which rule gave the threshold.
--   4. #94 p4_supplier_score: reads posted purchase bills, purchase returns (with reason) and quality checks; a leg that was never captured (GRN 04-1, bill check 06-4, PO 06-3)
--        is empty with the form code named (not 0).
--   5. #98 supplier_ageing: overdue is empty where the supplier has no credit days (it showed 0.00), with a notice. The age buckets stay on rule report_aging_buckets, no hidden default.
--   6. wastage_by_reason2(): the reason report without adding quantities of different units (one quantity per unit).
--   7. stock_reconcile(p_fix): unchanged for the owner, but the rewrite of the cache now leaves an audit line; stock_reconcile_fix(p_confirm) is the confirmed path the stock screen uses.
--   8. log_report_export4(): audit line for the CSV of the new report pages (same right as every export: owner or grant export_data).
-- ============================================================

-- ---------- 1. plumbing ----------
create or replace function public._r4_note(p_code text, p_en text, p_bn text, p_what text default null) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object('code', p_code, 'what', p_what, 'text_en', p_en, 'text_bn', p_bn));
$$;
create or replace function public._r4_addnote(p_res jsonb, p_note jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_set(p_res, '{notes}', coalesce(p_res -> 'notes', '[]'::jsonb) || jsonb_build_array(p_note));
$$;
-- item types chosen in the filter (only codes that exist); null = no filter
create or replace function public._r4_types(p_flt jsonb) returns text[]
language sql stable security definer set search_path = public as $$
  select case when v is null then null else coalesce((select array_agg(t.code) from public.item_types t where t.code = any (v)), '{}') end
    from (select public.rpt_arr_text(p_flt -> 'item_types') as v) x;
$$;

create or replace function public.report_catalog2() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select jsonb_agg(e) from jsonb_array_elements(public.report_catalog2_core()) e
                    where not exists (select 1 from public.report_defs3 d where d.key = e ->> 'key' and d.is_active)), '[]'::jsonb) || public.report_catalog3();
end $$;

create or replace function public.report_run2(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null, p_page int default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb; flt jsonb := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
begin
  if exists (select 1 from public.report_defs3 where key = p_key and is_active) then r := public.report_run3(p_key, p_filters, p_group, p_sort, p_page);
  else r := public.report_run2_core(p_key, p_filters, p_group, p_sort, p_page); end if;
  if p_key ~ '^[a-z0-9_]{2,40}$' and to_regprocedure('public._r4d_' || p_key || '(jsonb,jsonb)') is not null then      -- bos420: the in-place extension of this report
    execute format('select public.%I($1, $2)', '_r4d_' || p_key) into r using flt, r;
  end if;
  return r;
end $$;
revoke all on function public.report_catalog2(), public.report_run2(text, jsonb, text, text, int), public._r4_note(text, text, text, text), public._r4_addnote(jsonb, jsonb), public._r4_types(jsonb) from public, anon;
grant execute on function public.report_catalog2(), public.report_run2(text, jsonb, text, text, int) to authenticated;
revoke all on function public._r4_note(text, text, text, text), public._r4_addnote(jsonb, jsonb), public._r4_types(jsonb) from authenticated;

-- every decorator is private (run as definer, no access check of its own: report_run2 already checked the right)
create or replace function public._r4_lockdown() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select p.oid::regprocedure::text as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like '\_r4d\_%' or p.proname like '\_r4q\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig); n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public._r4_lockdown() from public, anon, authenticated;

-- ---------- 2. #57 / #60-62 stock_balance, in place (engine 3 row with the same key) ----------
create or replace function public._r3q_stock_balance(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with p as (select public.rpt_arr_text(flt -> 'categories') as cat, public._r4_types(flt) as ty, public.rpt_cost_ok() as cost)
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
      'item_type', coalesce(t.label_bn, it.item_type), 'item_type_en', coalesce(t.label_en, t.label_bn, it.item_type),
      'category', coalesce(it.category, '(none)'), 'location_bn', l.name_bn, 'location_en', coalesce(l.name_en, l.name_bn), 'qty', b.qty, 'unit', it.unit, 'min_stock', it.min_stock,
      'state', case when b.qty < 0 then 'negative' when it.min_stock is null then 'no_min' when b.qty <= it.min_stock then 'low' else 'ok' end,
      'avg_cost', case when p.cost then b.avg_cost end,
      'value', case when p.cost and b.avg_cost is not null then round(b.qty * b.avg_cost, 2) end,
      'cost_note', case when p.cost and b.qty <> 0 and b.avg_cost is null then 'no cost recorded' end,
      '_nc', case when p.cost and b.qty <> 0 and b.avg_cost is null then '["avg_cost","value"]'::jsonb end,
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, b.location_id))
    from public.stock_balance b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
      left join public.item_types t on t.code = it.item_type cross join p
   where b.location_id = any (locs) and it.is_active and (p.cat is null or it.category = any (p.cat)) and (p.ty is null or it.item_type = any (p.ty));
$$;

-- sub-totals for the same filters: one helper used by the decorator and by the tests
create or replace function public._r4_levels_agg(p_locs int[], p_cat text[], p_ty text[], p_cost boolean) returns jsonb
language sql stable security definer set search_path = public as $$
  with x as (
    select b.item_id, b.location_id, b.qty, b.avg_cost, it.min_stock, coalesce(l.name_bn, '') as lbn, coalesce(l.name_en, l.name_bn, '') as len, coalesce(l.kind, '(not set)') as kind,
           coalesce(t.label_bn, it.item_type) as tbn, coalesce(t.label_en, t.label_bn, it.item_type) as ten, it.item_type
      from public.stock_balance b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id left join public.item_types t on t.code = it.item_type
     where b.location_id = any (p_locs) and it.is_active and (p_cat is null or it.category = any (p_cat)) and (p_ty is null or it.item_type = any (p_ty))),
  a as (select 'place' as g, x.location_id::text as k, x.lbn as bn, x.len as en, count(*) as lines, count(*) filter (where x.qty <> 0) as stocked_lines,
          count(*) filter (where x.qty < 0) as negative_lines, count(*) filter (where x.qty <> 0 and x.avg_cost is null) as uncosted_lines,
          sum(round(x.qty * x.avg_cost, 2)) filter (where x.avg_cost is not null) as value from x group by x.location_id, x.lbn, x.len
        union all
        select 'kind', x.kind, x.kind, x.kind, count(*), count(*) filter (where x.qty <> 0), count(*) filter (where x.qty < 0), count(*) filter (where x.qty <> 0 and x.avg_cost is null),
          sum(round(x.qty * x.avg_cost, 2)) filter (where x.avg_cost is not null) from x group by x.kind
        union all
        select 'type', x.item_type, x.tbn, x.ten, count(*), count(*) filter (where x.qty <> 0), count(*) filter (where x.qty < 0), count(*) filter (where x.qty <> 0 and x.avg_cost is null),
          sum(round(x.qty * x.avg_cost, 2)) filter (where x.avg_cost is not null) from x group by x.item_type, x.tbn, x.ten)
  select jsonb_build_object(
    'place', coalesce((select jsonb_agg(jsonb_build_object('name', a.bn, 'name_en', a.en, 'lines', a.lines, 'negative_lines', a.negative_lines, 'uncosted_lines', case when p_cost then a.uncosted_lines end,
        'value', case when p_cost then coalesce(a.value, 0) end) order by a.bn) from a where a.g = 'place'), '[]'::jsonb),
    'kind', coalesce((select jsonb_agg(jsonb_build_object('name', a.bn, 'name_en', a.en, 'lines', a.lines, 'negative_lines', a.negative_lines, 'uncosted_lines', case when p_cost then a.uncosted_lines end,
        'value', case when p_cost then coalesce(a.value, 0) end) order by a.bn) from a where a.g = 'kind'), '[]'::jsonb),
    'type', coalesce((select jsonb_agg(jsonb_build_object('name', a.bn, 'name_en', a.en, 'lines', a.lines, 'negative_lines', a.negative_lines, 'uncosted_lines', case when p_cost then a.uncosted_lines end,
        'value', case when p_cost then coalesce(a.value, 0) end) order by a.bn) from a where a.g = 'type'), '[]'::jsonb),
    'lines', (select count(*) from x), 'negative_lines', (select count(*) from x where qty < 0), 'uncosted_lines', (select count(*) from x where qty <> 0 and avg_cost is null),
    'low_lines', (select count(*) from x where qty >= 0 and min_stock is not null and qty <= min_stock), 'no_min_lines', (select count(*) from x where qty >= 0 and min_stock is null),
    'value', case when p_cost then (select coalesce(sum(round(qty * avg_cost, 2)) filter (where avg_cost is not null), 0) from x) end);
$$;
revoke all on function public._r4_levels_agg(int[], text[], text[], boolean) from public, anon, authenticated;

create or replace function public._r4d_stock_balance(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare agg jsonb; cost_ok boolean := public.rpt_cost_ok(); res jsonb := p_res; col jsonb; cols jsonb := '[]'::jsonb; sec jsonb := '[]'::jsonb; mcols jsonb;
begin
  agg := public._r4_levels_agg(public._r2_locs(p_flt), public.rpt_arr_text(p_flt -> 'categories'), public._r4_types(p_flt), cost_ok);
  res := jsonb_set(res, '{totals}', coalesce(res -> 'totals', '{}'::jsonb) || jsonb_build_object('lines', agg -> 'lines', 'low_lines', agg -> 'low_lines', 'no_min_lines', agg -> 'no_min_lines', 'negative_lines', agg -> 'negative_lines'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop
      if col ->> 'key' not in ('avg_cost', 'value', 'cost_note') then cols := cols || jsonb_build_array(col); end if;
    end loop;
    res := jsonb_set(res, '{columns}', cols);
    res := jsonb_set(res, '{totals}', coalesce(res -> 'totals', '{}'::jsonb) - 'value');
    res := jsonb_set(res, '{rows}', coalesce((select jsonb_agg(r - 'avg_cost' - 'value' - 'cost_note' - '_nc') from jsonb_array_elements(res -> 'rows') r), '[]'::jsonb));
    res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  else
    res := jsonb_set(res, '{totals}', coalesce(res -> 'totals', '{}'::jsonb) || jsonb_build_object('value', agg -> 'value'));
    if (agg ->> 'uncosted_lines')::int > 0 then
      res := public._r4_addnote(res, public._r4_note('data_needed',
        (agg ->> 'uncosted_lines') || ' stock line(s) with a quantity have no cost recorded. The value total leaves them out; their value is not captured (it is not zero). A cost is recorded by a purchase bill line with a unit cost, an opening entered with a cost, or a production post with a cost.',
        (agg ->> 'uncosted_lines') || 'টি স্টক লাইনে পরিমাণ আছে কিন্তু খরচ লেখা নেই। মোট মূল্যে এগুলো ধরা হয়নি; এদের মূল্য অজানা (শূন্য নয়)। খরচ লেখা হয় ক্রয় বিলের লাইনে দর দিলে, খরচসহ ওপেনিং দিলে বা খরচসহ উৎপাদন পোস্ট করলে।', 'unit cost'));
    end if;
  end if;
  if (agg ->> 'negative_lines')::int > 0 then
    res := public._r4_addnote(res, public._r4_note('data_needed',
      (agg ->> 'negative_lines') || ' line(s) are NEGATIVE: more went out than the book had (a sale beyond stock). State shows "negative", not "low". Open the negative and integrity list to see them with their source.',
      (agg ->> 'negative_lines') || 'টি লাইন ঋণাত্মক: বইয়ে যা ছিল তার চেয়ে বেশি বের হয়েছে (স্টকের বাইরে বিক্রি)। অবস্থা "ঋণাত্মক" দেখানো হয়, "কম" নয়।', 'negative stock'));
  end if;
  sec := jsonb_build_array(
    jsonb_build_object('id', 'by_place', 'title_bn', 'লোকেশন অনুযায়ী মোট', 'title_en', 'Totals by place', 'rows', agg -> 'place'),
    jsonb_build_object('id', 'by_kind', 'title_bn', 'লোকেশনের ধরন অনুযায়ী মোট', 'title_en', 'Totals by kind of place', 'rows', agg -> 'kind'),
    jsonb_build_object('id', 'by_type', 'title_bn', 'আইটেমের ধরন অনুযায়ী মোট', 'title_en', 'Totals by item type', 'rows', agg -> 'type'));
  mcols := '[{"key":"name","label_bn":"নাম","label_en":"Name","type":"text"},{"key":"lines","label_bn":"লাইন","label_en":"Lines","type":"int"},{"key":"negative_lines","label_bn":"ঋণাত্মক","label_en":"Negative","type":"int"}]'::jsonb
          || case when cost_ok then '[{"key":"uncosted_lines","label_bn":"খরচ লেখা নেই","label_en":"No cost recorded","type":"int"},{"key":"value","label_bn":"মূল্য (খরচ জানা অংশে)","label_en":"Value (costed part)","type":"money"}]'::jsonb else '[]'::jsonb end;
  sec := (select jsonb_agg(s || jsonb_build_object('columns', mcols)) from jsonb_array_elements(sec) s);
  return jsonb_set(res, '{subtotals}', sec);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('stock_balance', 'S2', 'stock', 'স্টক ব্যালান্স', 'Stock balance', 'Stock balance',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["item_type","ধরন","Type","text"],["item_type_en","Type (EN)","Type (EN)","text"],["category","ক্যাটাগরি","Category","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["qty","আছে","On hand","num"],["unit","একক","Unit","text"],["min_stock","ন্যূনতম","Minimum","num"],["state","অবস্থা","State","text"],["avg_cost","গড় খরচ","Avg cost","money"],["value","মূল্য","Value","money"],["cost_note","খরচ","Cost","text"]]'::jsonb,
  array['value'], 'item_name', 'asc', array['locations','brands','categories','item_types'], true, false, false, 4201)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- 3. #69 expiry_soon, in place: one threshold, and the batches that have no expiry ----------
create or replace function public._r3q_expiry_soon(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Dhaka')::date as today, coalesce(public.rule_num('report_expiry_soon_days'), public.rule_num('expiry_warn_days')) as thr,
                    public.rpt_arr_text(flt -> 'categories') as cat, public.rpt_cost_ok() as cost),
  dated as (
    select it.id as item_id, it.code, it.name_bn, coalesce(it.name_en, it.name_bn) as name_en, l.id as loc_id, l.name_bn as lbn, coalesce(l.name_en, l.name_bn) as len,
           (b.made_at at time zone 'Asia/Dhaka')::date as made_on, (b.expires_at at time zone 'Asia/Dhaka')::date as exp_on, b.qty_remaining as qty, it.unit, sb.avg_cost, t.today, t.cost
      from public.stock_batches b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        left join public.stock_balance sb on sb.item_id = b.item_id and sb.location_id = b.location_id cross join t
     where b.qty_remaining > 0 and b.expires_at is not null and b.location_id = any (locs) and (t.cat is null or it.category = any (t.cat))
       and (b.expires_at at time zone 'Asia/Dhaka')::date <= t.today + coalesce(t.thr::int, -1)),
  noexp as (
    select it.id as item_id, it.code, it.name_bn, coalesce(it.name_en, it.name_bn) as name_en, l.id as loc_id, l.name_bn as lbn, coalesce(l.name_en, l.name_bn) as len,
           min((b.made_at at time zone 'Asia/Dhaka')::date) as made_on, sum(b.qty_remaining) as qty, count(*) as batches, it.unit, sb.avg_cost, t.cost
      from public.stock_batches b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        left join public.stock_balance sb on sb.item_id = b.item_id and sb.location_id = b.location_id cross join t
     where b.qty_remaining > 0 and b.expires_at is null and b.location_id = any (locs) and (t.cat is null or it.category = any (t.cat))
     group by it.id, it.code, it.name_bn, it.name_en, l.id, l.name_bn, l.name_en, it.unit, sb.avg_cost, t.cost)
  select jsonb_build_object('item_code', d.code, 'item_name', d.name_bn, 'item_name_en', d.name_en, 'location_id', d.loc_id, 'location_bn', d.lbn, 'location_en', d.len, 'made_on', d.made_on, 'expires_on', d.exp_on,
      'n_dated', 1, 'n_expired', case when d.exp_on < d.today then 1 else 0 end,
      'days_left', d.exp_on - d.today, 'qty', d.qty, 'unit', d.unit, 'batches', 1, 'state', case when d.exp_on < d.today then 'expired' else 'soon' end,
      'value', case when d.cost and d.avg_cost is not null then round(d.qty * d.avg_cost, 2) end, 'drill', format('#/batchrep/batches?item=%s&loc=%s', d.item_id, d.loc_id))
    from dated d
  union all
  select jsonb_build_object('item_code', n.code, 'item_name', n.name_bn, 'item_name_en', n.name_en, 'location_id', n.loc_id, 'location_bn', n.lbn, 'location_en', n.len, 'made_on', n.made_on, 'expires_on', null,
      'n_dated', 0, 'n_expired', 0,
      'days_left', null, 'qty', n.qty, 'unit', n.unit, 'batches', n.batches, 'state', 'no_expiry',
      'value', case when n.cost and n.avg_cost is not null then round(n.qty * n.avg_cost, 2) end, '_nc', '["expires_on","days_left"]'::jsonb,
      'drill', format('#/batchrep/batches?item=%s&loc=%s', n.item_id, n.loc_id))
    from noexp n;
$$;

create or replace function public._r4d_expiry_soon(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; thr numeric; src text; cost_ok boolean := public.rpt_cost_ok(); nb bigint; ni bigint; locs int[] := public._r2_locs(p_flt); cat text[] := public.rpt_arr_text(p_flt -> 'categories');
        col jsonb; cols jsonb := '[]'::jsonb;
begin
  thr := public.rule_num('report_expiry_soon_days');
  if thr is not null then src := 'report_expiry_soon_days';
  else thr := public.rule_num('expiry_warn_days'); src := case when thr is not null then 'expiry_warn_days' end; end if;
  if thr is null then
    res := public._r4_addnote(res, public._r4_note('data_needed', 'No "days ahead" rule is set (report_expiry_soon_days or expiry_warn_days), so only batches already past their expiry are listed.',
      'কত দিন আগে সতর্ক করা হবে তার নিয়ম বসানো নেই (report_expiry_soon_days বা expiry_warn_days); তাই শুধু মেয়াদ-শেষ ব্যাচ দেখাচ্ছে।', 'expiry_warn_days'));
  else
    res := public._r4_addnote(res, public._r4_note('info', 'Batches that expire within ' || thr::int || ' day(s) are listed (threshold from the rule ' || src || '); the same threshold is used on the stock reports page.',
      'আগামী ' || thr::int || ' দিনের মধ্যে মেয়াদ শেষ হবে এমন ব্যাচ দেখানো হচ্ছে (সীমা নিয়ম ' || src || ' থেকে); স্টক রিপোর্ট পাতাতেও একই সীমা।'));
  end if;
  select count(*), count(distinct b.item_id) into nb, ni from public.stock_batches b join public.items it on it.id = b.item_id
   where b.qty_remaining > 0 and b.expires_at is null and b.location_id = any (locs) and (cat is null or it.category = any (cat));
  if nb > 0 then
    res := public._r4_addnote(res, public._r4_note('data_needed', nb || ' batch(es) of ' || ni || ' item(s) hold stock with NO expiry date captured. They are listed as "no expiry" rows; they are not "safe". Expiry is captured only when the item has a shelf-life rule (Settings > shelf life) or the batch is entered with an expiry.',
      nb || 'টি ব্যাচে (' || ni || 'টি আইটেম) স্টক আছে কিন্তু মেয়াদ লেখা নেই। এগুলো "মেয়াদ নেই" সারিতে দেখানো হয়েছে; এগুলো নিরাপদ নয়। আইটেমের শেলফ-লাইফ নিয়ম থাকলে বা ব্যাচে মেয়াদ দিলে তবেই মেয়াদ লেখা হয়।', 'shelf_life_rules / expires_at'));
  end if;
  res := jsonb_set(res, '{totals}', (coalesce(res -> 'totals', '{}'::jsonb) - 'n_dated' - 'n_expired') || jsonb_build_object('batches', coalesce((res #>> '{totals,n_dated}')::numeric::int, 0), 'expired_batches', coalesce((res #>> '{totals,n_expired}')::numeric::int, 0)));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' <> 'value' then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols);
    res := jsonb_set(res, '{totals}', coalesce(res -> 'totals', '{}'::jsonb) - 'value');
    res := jsonb_set(res, '{rows}', coalesce((select jsonb_agg(r - 'value') from jsonb_array_elements(res -> 'rows') r), '[]'::jsonb));
    res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return res;
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('expiry_soon', 'S3', 'stock', 'মেয়াদ শেষ / শিগগির শেষ', 'Expired and expiring soon', 'Expiry শেষ / শিগগির শেষ',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["made_on","তৈরি","Made","date"],["expires_on","মেয়াদ শেষ","Expires","date"],["days_left","বাকি দিন","Days left","int"],["qty","পরিমাণ (বাকি)","Qty left","num"],["unit","একক","Unit","text"],["batches","ব্যাচ","Batches","int"],["state","অবস্থা","State","text"],["value","আনুমানিক মূল্য","Approx. value","money"]]'::jsonb,
  array['n_dated','n_expired','value'], 'days_left', 'asc', array['locations','brands','categories'], true, false, false, 4202)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- 4. #94 supplier scorecard: bills, returns and quality checks are read; a leg never captured is empty with its form code, not 0 ----------
create or replace function public._r3q_p4_supplier_score(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with sup as (
    select e.id, e.form_code, e.data, lower(btrim(coalesce(s.name, e.data ->> 'supplier'))) as sk, btrim(coalesce(s.name, e.data ->> 'supplier')) as sname
      from public.entries e left join public.suppliers s on s.id::text = e.data ->> 'supplier_id'
     where e.form_code in ('04-1', '06-4') and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
       and nullif(btrim(coalesce(s.name, e.data ->> 'supplier')), '') is not null),
  gl as (
    select s.sk, s.sname, s.id, r ->> 'quality' as q, public._r2_num(r -> 'counted') as cnt, public._r2_num(r -> 'memo') as memo
      from sup s cross join lateral jsonb_array_elements(public._p26_arr(s.data -> 'lines')) r where s.form_code = '04-1'),
  grn as (
    select sk, min(sname) as sname, count(distinct id) as grns, count(*) as lines, count(*) filter (where memo is not null and cnt is not null and cnt < memo) as short_lines,
           count(*) filter (where q = 'return') as rejected, count(*) filter (where q = 'hold') as held, count(*) filter (where q = 'reduced') as reduced
      from gl group by sk),
  bil as (
    select sk, min(sname) as sname, count(*) as bills, count(*) filter (where data ->> 'short' = 'yes') as short_claims, count(*) filter (where data ->> 'returned' = 'yes') as return_claims
      from sup where form_code = '06-4' group by sk),
  po as (
    select p.sk, min(p.supplier) as sname, count(*) as pos, count(*) filter (where p.grn_n > 0 and p.delivery_date is not null) as pos_matched,
           count(*) filter (where p.grn_n > 0 and p.delivery_date is not null and p.first_grn > p.delivery_date) as late_pos,
           count(*) filter (where p.grn_n = 0 and p.delivery_date is not null and p.delivery_date < (now() at time zone 'Asia/Dhaka')::date) as overdue_open
      from public._p26_po(d1, d2, locs) p where p.sk is not null and p.sk <> '' group by p.sk),
  rr as (select * from public._p26_rates(d1, d2, locs)),
  rc as (
    select sk, avg(chg) as chg, count(*) as items
      from (select sk, item_id, (l - f) / f * 100 as chg
              from (select sk, item_id, (array_agg(rate order by dt, ord))[1] as f, (array_agg(rate order by dt desc, ord desc))[1] as l, count(*) as n from rr group by sk, item_id) a
             where n > 1 and f > 0) b group by sk),
  pb as (                                                                    -- bos420: posted purchase bills and purchase returns of the period
    select lower(btrim(s.name)) as sk, min(btrim(s.name)) as sname, count(*) filter (where b.kind = 'bill') as bills_n, coalesce(sum(b.total) filter (where b.kind = 'bill'), 0) as bills_total,
           count(*) filter (where b.kind = 'return') as returns_n, coalesce(sum(b.total) filter (where b.kind = 'return'), 0) as returns_total
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id
     where b.status = 'posted' and b.bill_date between d1 and d2 and b.location_id = any (locs) group by lower(btrim(s.name))),
  qc as (                                                                    -- bos420: quality checks of goods received (bill or GRN sheet), the latest status of each source
    select z.sk, min(z.sname) as sname, count(*) as qc_n, count(*) filter (where z.st in ('hold', 'reject')) as qc_bad
      from (select coalesce(lower(btrim(sb.name)), lower(btrim(coalesce(s2.name, e.data ->> 'supplier')))) as sk, coalesce(btrim(sb.name), btrim(coalesce(s2.name, e.data ->> 'supplier'))) as sname,
                   (select q.status from public.qc_records q where q.source_type = c.source_type and q.source_id = c.source_id order by q.created_at desc, q.id desc limit 1) as st
              from (select distinct source_type, source_id from public.qc_records
                     where source_type = 'grn' and (created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and location_id = any (locs)) c
              left join public.purchase_bills bb on bb.id = c.source_id left join public.suppliers sb on sb.id = bb.supplier_id
              left join public.entries e on e.id = c.source_id and e.form_code = '04-1' left join public.suppliers s2 on s2.id::text = e.data ->> 'supplier_id') z
     where z.sk is not null and z.sk <> '' group by z.sk),
  keys as (select sk, sname from grn union select sk, sname from bil union select sk, sname from po union select sk, min(sname) from rr group by sk
           union select sk, sname from pb union select sk, sname from qc)
  select jsonb_build_object('supplier', k.sname,
    'grns', g.grns, 'lines', g.lines, 'short_lines', g.short_lines, 'rejected', g.rejected, 'held', g.held, 'reduced', g.reduced,
    'bills_checked', b.bills, 'short_claims', b.short_claims, 'return_claims', b.return_claims,
    'pos', p.pos, 'late_pos', case when coalesce(p.pos_matched, 0) > 0 then p.late_pos end, 'overdue_open', p.overdue_open,
    'rate_change_pct', case when c.chg is not null then round(c.chg, 2) end, 'rate_items', coalesce(c.items, 0),
    'bills_n', coalesce(x.bills_n, 0), 'bills_total', coalesce(x.bills_total, 0), 'returns_n', coalesce(x.returns_n, 0), 'returns_total', coalesce(x.returns_total, 0),
    'return_pct', case when coalesce(x.bills_total, 0) > 0 then round(x.returns_total * 100.0 / x.bills_total, 1) end,
    'qc_n', q.qc_n, 'qc_bad', q.qc_bad, 'qc_bad_pct', case when q.qc_n > 0 then round(q.qc_bad * 100.0 / q.qc_n, 1) end,
    'not_captured', nullif(concat_ws(', ', case when g.sk is null then '04-1' end, case when b.sk is null then '06-4' end, case when p.sk is null then '06-3' end, case when q.sk is null then 'QC' end), ''),
    '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[
      case when g.sk is null then 'grns' end, case when g.sk is null then 'lines' end, case when g.sk is null then 'short_lines' end, case when g.sk is null then 'rejected' end,
      case when g.sk is null then 'held' end, case when g.sk is null then 'reduced' end,
      case when b.sk is null then 'bills_checked' end, case when b.sk is null then 'short_claims' end, case when b.sk is null then 'return_claims' end,
      case when p.sk is null then 'pos' end, case when p.sk is null then 'late_pos' end, case when p.sk is null then 'overdue_open' end,
      case when q.sk is null then 'qc_n' end, case when q.sk is null then 'qc_bad' end, case when q.sk is null then 'qc_bad_pct' end]) z where z is not null))
    from (select sk, min(sname) as sname from keys where sk is not null and sk <> '' group by sk) k
    left join grn g on g.sk = k.sk left join bil b on b.sk = k.sk left join po p on p.sk = k.sk left join rc c on c.sk = k.sk left join pb x on x.sk = k.sk left join qc q on q.sk = k.sk;
$$;

create or replace function public._r4d_p4_supplier_score(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; d1 date := (p_res #>> '{meta,from}')::date; d2 date := (p_res #>> '{meta,to}')::date; locs int[] := public._r2_locs(p_flt); n_grn bigint; n_bil bigint; n_po bigint; tot jsonb;
begin
  if d1 is null or d2 is null then return res; end if;
  select count(*) into n_grn from public.entries e where e.form_code = '04-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs);
  select count(*) into n_bil from public.entries e where e.form_code = '06-4' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs);
  select count(*) into n_po from public._p26_po(d1, d2, locs);
  tot := coalesce(res -> 'totals', '{}'::jsonb);
  if n_grn = 0 then tot := tot - 'grns' - 'lines' - 'short_lines' - 'rejected' - 'held' - 'reduced';
    res := public._r4_addnote(res, public._r4_note('data_needed', 'No goods-received sheet (04-1) was captured in this period: the GRN columns are empty (not captured), not 0. Purchase bills below come from posted bills.',
      'এই সময়ে কোনো মাল-গ্রহণ শিট (০৪-১) লেখা হয়নি: GRN-এর কলাম ফাঁকা (লেখা হয়নি), ০ নয়। ক্রয় বিলের কলাম পোস্ট করা বিল থেকে এসেছে।', '04-1')); end if;
  if n_bil = 0 then tot := tot - 'bills_checked' - 'short_claims' - 'return_claims';
    res := public._r4_addnote(res, public._r4_note('data_needed', 'No supplier bill check (06-4) was captured in this period: bills checked and claims are empty (not captured), not 0.',
      'এই সময়ে সরবরাহকারীর বিল যাচাই (০৬-৪) লেখা হয়নি: যাচাই করা বিল ও দাবির কলাম ফাঁকা (লেখা হয়নি), ০ নয়।', '06-4')); end if;
  if n_po = 0 then tot := tot - 'pos' - 'late_pos' - 'overdue_open';
    res := public._r4_addnote(res, public._r4_note('data_needed', 'No purchase order (06-3) was captured in this period: the PO columns are empty (not captured), not 0.',
      'এই সময়ে কোনো ক্রয় অর্ডার (০৬-৩) লেখা হয়নি: PO-এর কলাম ফাঁকা (লেখা হয়নি), ০ নয়।', '06-3')); end if;
  res := public._r4_addnote(res, public._r4_note('info', 'Purchase returns come from posted purchase returns (reason on the return). Quality checks are counted for goods-received checks whose source is a posted bill or a GRN sheet; a check on a source that has no supplier is not counted.',
    'ক্রয় ফেরত পোস্ট করা ফেরত থেকে। কোয়ালিটি চেক গোনা হয় যেগুলোর উৎস পোস্ট করা বিল বা GRN শিট; যে উৎসে সরবরাহকারী নেই তা গোনা হয়নি।'));
  return jsonb_set(res, '{totals}', tot);
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('p4_supplier_score', 'P4', 'purchase', 'সাপ্লায়ার স্কোরকার্ড', 'Supplier scorecard', 'Supplier স্কোরকার্ড',
  '[["supplier","সাপ্লায়ার","Supplier","text"],["bills_n","ক্রয় বিল (পোস্টেড)","Purchase bills","int"],["bills_total","ক্রয় বিলের টাকা","Bills amount","money"],["returns_n","ক্রয় ফেরত","Purchase returns","int"],["returns_total","ফেরতের টাকা","Returns amount","money"],["return_pct","ফেরত % (টাকার)","Return % (amount)","pct"],["qc_n","কোয়ালিটি চেক","Quality checks","int"],["qc_bad","আটক/বাতিল","Held or rejected","int"],["qc_bad_pct","আটক/বাতিল %","Held or rejected %","pct"],["grns","গ্রহণ রসিদ","GRNs","int"],["lines","লাইন","Lines","int"],["short_lines","কম পাওয়া লাইন","Short lines","int"],["rejected","ফেরত লাইন","Returned lines","int"],["held","আটক লাইন","Held lines","int"],["reduced","দর কমানো লাইন","Reduced-rate lines","int"],["bills_checked","যাচাই বিল","Bills checked","int"],["short_claims","ঘাটতির দাবি","Shortage claims","int"],["return_claims","ফেরতের দাবি","Return claims","int"],["pos","পারচেজ অর্ডার","POs","int"],["late_pos","দেরিতে আসা PO","Late POs","int"],["overdue_open","মেয়াদ পেরোনো খোলা PO","Overdue open POs","int"],["rate_change_pct","গড় দর বদল %","Avg rate change %","pct"],["rate_items","তুলনার আইটেম","Items compared","int"],["not_captured","লেখা হয়নি (ফর্ম)","Not captured (form)","text"]]'::jsonb,
  array['bills_n','bills_total','returns_n','returns_total','qc_n','qc_bad','grns','lines','short_lines','rejected','held','reduced','bills_checked','short_claims','return_claims','pos','late_pos','overdue_open'], 'rejected', 'desc', array['locations'], false, true, false, 2602)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- 5. #98 supplier_ageing: overdue is empty (not 0.00) where the supplier has no credit days ----------
create or replace function public._r4d_supplier_ageing(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; rw jsonb; rows_ jsonb := '[]'::jsonb; n_all bigint; n_page int := 0; names text;
begin
  for rw in select * from jsonb_array_elements(coalesce(res -> 'rows', '[]'::jsonb)) loop
    if rw -> 'credit_days' is null or jsonb_typeof(rw -> 'credit_days') = 'null' then
      rw := (rw - 'overdue') || jsonb_build_object('overdue', null, '_nc', jsonb_build_array('overdue', 'credit_days')); n_page := n_page + 1;
    end if;
    rows_ := rows_ || jsonb_build_array(rw);
  end loop;
  res := jsonb_set(res, '{rows}', rows_);
  select count(*), string_agg(s.name, ', ' order by s.name) into n_all, names from public.suppliers s
   where s.credit_days is null and exists (select 1 from public._sup_open(s.id) o where o.open_amt > 0);
  if n_all > 0 then
    res := public._r4_addnote(res, public._r4_note('data_needed', n_all || ' supplier(s) with open payables have NO credit days set (' || left(names, 160) || '). Their overdue amount cannot be worked out: it is shown as "not captured", not as 0.00. Set the credit days on the supplier (Settings > Suppliers).',
      'খোলা দেনা আছে এমন ' || n_all || ' জন সরবরাহকারীর বাকির মেয়াদ (দিন) বসানো নেই (' || left(names, 160) || ')। তাদের মেয়াদ-পার অঙ্ক হিসাব করা যায় না: ০.০০ নয়, "লেখা হয়নি" দেখানো হয়। সরবরাহকারীর তথ্যে বাকির মেয়াদ বসান।', 'credit_days'));
  end if;
  return res;
end $$;

-- the same flag for the payables screen (supplier_dues / payables_summary show 0 overdue where credit days are empty): the suppliers that cannot be judged
create or replace function public.supplier_credit_gaps() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_access('purchase') or public._pur_ok(null)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('supplier_id', s.id, 'name', s.name) order by s.name) from public.suppliers s
                    where s.credit_days is null and exists (select 1 from public._sup_open(s.id) o where o.open_amt > 0)), '[]'::jsonb);
end $$;
revoke all on function public.supplier_credit_gaps() from public, anon;
grant execute on function public.supplier_credit_gaps() to authenticated;

-- ---------- 6. wastage by reason without adding different units ----------
create or replace function public.wastage_by_reason2(p_loc int default null, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('reason_code', r.reason_code, 'label_bn', r.lbn, 'label_mix', r.lmix, 'label_en', r.len, 'entries', r.entries, 'items', r.items,
        'qty', case when jsonb_array_length(r.units) = 1 then (r.units -> 0 ->> 'qty')::numeric end, 'unit', case when jsonb_array_length(r.units) = 1 then r.units -> 0 ->> 'unit' end,
        'mixed_units', jsonb_array_length(r.units) > 1, 'units', r.units) order by r.entries desc, r.reason_code)
    from (select g.reason_code, g.lbn, g.lmix, g.len, sum(g.entries) as entries, sum(g.items) as items,
                 jsonb_agg(jsonb_build_object('unit', g.unit, 'qty', g.qty, 'entries', g.entries) order by g.unit) as units
            from (select w.reason_code, coalesce(o.label_bn, w.reason_code) as lbn, coalesce(o.label_mix, o.label_bn, w.reason_code) as lmix, coalesce(o.label_en, w.reason_code) as len,
                         coalesce(public._item_base(w.item_id), '?') as unit, round(sum(w.qty), 4) as qty, count(*) as entries, count(distinct w.item_id) as items
                    from public.stock_wastage w left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.reason_code
                   where public.can_loc(w.location_id) and (p_loc is null or w.location_id = p_loc) and (w.made_at at time zone 'Asia/Dhaka')::date between f and t
                   group by w.reason_code, o.label_bn, o.label_mix, o.label_en, coalesce(public._item_base(w.item_id), '?')) g
           group by g.reason_code, g.lbn, g.lmix, g.len) r), '[]'::jsonb);
end $$;
revoke all on function public.wastage_by_reason2(int, date, date) from public, anon;
grant execute on function public.wastage_by_reason2(int, date, date) to authenticated;

-- ---------- 7. stock_reconcile: the rewrite of the cache leaves an audit line; the stock screen uses the confirmed path ----------
-- stock_reconcile(false) is unchanged (a read). stock_reconcile(true) is owner only as before and now writes one audit line (action stock_reconcile_fix) when it changed a row.
create or replace function public.stock_reconcile(p_fix boolean default false)
returns table (item_id uuid, location_id int, ledger_qty numeric, cached_qty numeric, qty_diff numeric, cached_avg numeric, replay_avg numeric)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare r record; l record; q numeric; a numeric; bq numeric; bavg numeric; n int := 0; sid text; log_ jsonb := '[]'::jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  for r in
    select k.iid, k.lid from (select x.item_id iid, x.location_id lid from public.stock_ledger x group by 1, 2
                              union select y.item_id, y.location_id from public.stock_balance y) k order by 1, 2 loop
    if p_fix then
      insert into public.stock_balance (item_id, location_id) values (r.iid, r.lid) on conflict do nothing;
      perform 1 from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid for update;     -- nobody can post to this pair until we are done
    end if;
    select z.qty, z.avg_cost into bq, bavg from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid;
    bq := coalesce(bq, 0);
    q := 0; a := null;
    for l in select x.qty_delta, x.unit_cost, x.reason from public.stock_ledger x where x.item_id = r.iid and x.location_id = r.lid order by x.id loop
      a := public._avg_next(q, a, l.qty_delta, l.unit_cost, l.reason); q := q + l.qty_delta;
    end loop;
    if q <> bq or bavg is distinct from a then
      item_id := r.iid; location_id := r.lid; ledger_qty := q; cached_qty := bq; qty_diff := bq - q; cached_avg := bavg; replay_avg := a;
      if p_fix then
        update public.stock_balance z set qty = q, avg_cost = a, updated_at = now() where z.item_id = r.iid and z.location_id = r.lid;
        n := n + 1; if n <= 50 then log_ := log_ || jsonb_build_array(jsonb_build_object('item_id', r.iid, 'location_id', r.lid, 'old_qty', bq, 'new_qty', q, 'old_avg', bavg, 'new_avg', a)); end if;   -- bos420
      end if;
      return next;
    end if;
  end loop;
  if p_fix and n > 0 then                                                                                                   -- bos420: the cache was rewritten, say who and what
    select p.staff_id into sid from public.profiles p where p.id = auth.uid();
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'stock_reconcile_fix', 'stock_balance', null, jsonb_build_object('rows_fixed', n, 'confirmed', coalesce(current_setting('bos.reconcile_confirm', true), '') = 'yes', 'first_rows', log_));
  end if;
end $$;

-- the confirmed path: owner only, the owner types the word FIX, one audit line (the stock screen calls this, not stock_reconcile(true))
create or replace function public.stock_reconcile_fix(p_confirm text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; sid text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_confirm is distinct from 'FIX' then raise exception 'confirm_required'; end if;
  perform set_config('bos.reconcile_confirm', 'yes', true);
  select count(*) into n from public.stock_reconcile(true);
  select p.staff_id into sid from public.profiles p where p.id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'stock_reconcile_confirm', 'stock_balance', null, jsonb_build_object('rows_fixed', n, 'typed', 'FIX'));
  return jsonb_build_object('fixed', n);
end $$;
revoke all on function public.stock_reconcile_fix(text) from public, anon;
grant execute on function public.stock_reconcile_fix(text) to authenticated;

-- ---------- 8. export audit line for the new report pages ----------
create or replace function public._r4_export_keys() returns text[]
language sql immutable set search_path = public as $$
  select array['stock_ledger','stock_recon','batch_stock','fg_ageing','unsold_by_batch','fg_distribution','expired_damaged_unsold','batch_trace','stockx_reorder','stockx_expiry','stockx_wastage'];
$$;
create or replace function public.log_report_export4(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or not (p_key = any (public._r4_export_keys())) then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;
revoke all on function public._r4_export_keys() from public, anon, authenticated;
revoke all on function public.log_report_export4(text, text, jsonb, int) from public, anon;
grant execute on function public.log_report_export4(text, text, jsonb, int) to authenticated;

select public._r3_lockdown();
select public._r4_lockdown();
notify pgrst, 'reload schema';
