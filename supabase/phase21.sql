-- ============================================================
-- BOS tool · Phase 21: MORE REPORTS (12) for the Reports hub, beside the phase9 engine.
-- Run AFTER phase9 (needs report_presets, rpt_* helpers, report_brand_map) and phase10 (stock tables) and the purchase tables.
-- Additive and idempotent: safe to run again. NOTHING from phase9 is replaced or edited.
--
-- Why a second function: phase9's report_run reads its whitelist from rpt_def / rpt_keys (immutable SQL functions inside an already
-- applied file). Replacing them would silently lose the new reports the day phase9 is pasted again. So the new reports have their OWN
-- whitelist and their own three functions with the SAME answer shape as report_run (columns, rows, totals, page, has_more, notes, meta):
--   report_catalog2()                              list for the hub (same fields as report_catalog)
--   report_run2(key, filters, group, sort, page)   the data; user input never becomes SQL (keys in a fixed list, values quoted with %L)
--   log_report_export2(key, kind, filters, rows)   audit row after a CSV / print (owner or grant export_data)
-- The app (web/reports.js + web/reports2.js) merges the two catalogues and sends a key to the function that owns it.
--
-- Security (same rules as phase9)
--   * every call needs the grant report_<group> or view_reports (owner always); rows limited to can_loc() locations
--   * cost columns exist only for owner / ITEM_COST view / grant view_cost or view_profit (not computed otherwise);
--     the two supplier-money reports are cost-only: without that right they are locked, not shown empty
--   * numbers read from the jsonb of forms are parsed safely (text that is not a plain number is skipped and counted, never guessed)
--   * thresholds are RULES with no built-in value: aging buckets reuse report_aging_buckets; "expiring soon" needs report_expiry_soon_days
-- ============================================================

-- ---------- grants (seeded only when missing; nobody gets them by default except the owner: the owner gives them in Who may do what) ----------
do $$
declare r record;
begin
  for r in select * from (values
    ('report_stock',    64, 'রিপোর্ট: স্টক ও অপচয়', 'Report: Stock & wastage', 'Reports: Stock and wastage'),
    ('report_purchase', 65, 'রিপোর্ট: ক্রয় ও সরবরাহকারী', 'Report: Purchases & suppliers', 'Reports: Purchases and suppliers'),
    ('report_expense',  66, 'রিপোর্ট: খরচ', 'Report: Expenses', 'Reports: Expenses'),
    ('report_staff',    67, 'রিপোর্ট: কর্মীর হাজিরা', 'Report: Staff attendance', 'Reports: Staff attendance'),
    ('report_control',  68, 'রিপোর্ট: ব্যতিক্রম (গরমিল)', 'Report: Exceptions', 'Reports: Exceptions')) v(code, sort, bn, mix, en)
  loop
    if not exists (select 1 from public.grant_defs where grant_code = r.code) then
      insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
        values (r.code, 'reports', r.sort, r.bn, r.mix, r.en, 'once', null);
    end if;
  end loop;
end $$;

insert into public.rules (key, module, kind, default_value, unit, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('report_expiry_soon_days', 'reports', 'number', null, 'দিন', 0, 3650, 'মেয়াদ কত দিনের মধ্যে শেষ হলে "শিগগির শেষ" ধরা হবে', 'Expiry কত দিনের মধ্যে হলে "শিগগির শেষ"', 'Days ahead that count as "expiring soon"', 'ফাঁকা থাকলে শুধু মেয়াদ-শেষ ব্যাচ দেখাবে', 'Empty = only batches already past expiry are listed', 65)
 on conflict (key) do nothing;
-- the staff home lists "today's sheets to fill": empty = every sheet the person may enter; the owner can narrow it to the daily sheets (codes separated by commas)
insert into public.rules (key, module, kind, default_value, unit, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('home_daily_forms', 'settings', 'text', null, null, null, null, 'হোমে "আজকের শিট"-এ কোন ফর্মগুলো দেখাবে (কোড, কমা দিয়ে)', 'Home-এ "আজকের Sheet"-এ কোন Form (code, comma দিয়ে)', 'Daily sheets shown on the staff home (form codes, comma separated)', 'ফাঁকা = কর্মী যে ফর্মে লিখতে পারে সবগুলো', 'Empty = every form the person may enter', 66)
 on conflict (key) do nothing;

-- ---------- small helpers ----------
create or replace function public._r2_num(j jsonb) returns numeric
language sql immutable set search_path = public as $$
  select case when j is null then null
    when jsonb_typeof(j) = 'number' then case when (j #>> '{}')::numeric between -1000000000000 and 1000000000000 then (j #>> '{}')::numeric end
    when jsonb_typeof(j) = 'string' and btrim(j #>> '{}') ~ '^-?[0-9]{1,12}(\.[0-9]{1,4})?$' then btrim(j #>> '{}')::numeric end;
$$;

-- locations the caller may use, narrowed by the filters locations / brands
create or replace function public._r2_locs(p_flt jsonb) returns int[]
language plpgsql stable security definer set search_path = public as $$
declare al int[]; lo int[]; br text[];
begin
  al := coalesce((select array_agg(l.id) from public.locations l where public.can_loc(l.id)), '{}');
  lo := public.rpt_arr_int(p_flt -> 'locations');
  if lo is not null then al := coalesce(array(select unnest(al) intersect select unnest(lo)), '{}'); end if;
  br := public.rpt_arr_text(p_flt -> 'brands');
  if br is not null then al := coalesce(array(select x from unnest(al) x where exists (select 1 from public.report_brand_map m where m.location_id = x and m.brand_code = any (br))), '{}'); end if;
  return al;
end $$;

-- the whitelist: group, names, which filters, sort, groups (dims) and fixed columns [key, bn, en, type]
create or replace function public._r2_def(p_key text) returns jsonb
language sql immutable set search_path = public as $j$
  select ($c${
   "item_slow":{"group":"sales","bn":"ধীর ও অবিক্রীত আইটেম","en":"Slow and unsold items","mix":"ধীর ও unsold Item","allow":["locations","brands","categories"],"sort":"qty:asc"},
   "stock_low":{"group":"stock","bn":"স্টক কম (ন্যূনতমের নিচে)","en":"Stock at or below minimum","mix":"Stock কম (minimum-এর নিচে)","allow":["locations","brands","categories"],"nodate":1,"sort":"short_by:desc"},
   "stock_balance":{"group":"stock","bn":"স্টক ব্যালান্স","en":"Stock balance","mix":"Stock balance","allow":["locations","brands","categories"],"nodate":1,"sort":"item_name:asc"},
   "wastage":{"group":"stock","bn":"অপচয় (কারণ / আইটেম অনুযায়ী)","en":"Wastage by reason / item","mix":"অপচয় (reason / item অনুযায়ী)","allow":["locations","brands"],"gdef":"reason","dims":["reason","item","location","day"],"sort":"@dim"},
   "expiry_soon":{"group":"stock","bn":"মেয়াদ শেষ / শিগগির শেষ","en":"Expired and expiring soon","mix":"Expiry শেষ / শিগগির শেষ","allow":["locations","brands","categories"],"nodate":1,"sort":"days_left:asc"},
   "transfers_gap":{"group":"stock","bn":"ট্রান্সফার: পৌঁছায়নি / কম পৌঁছেছে","en":"Transfers not received or short","mix":"Transfer: পৌঁছায়নি / কম","allow":["locations","brands"],"sort":"sent_day:desc"},
   "supplier_ageing":{"group":"purchase","bn":"সরবরাহকারীকে দেনার বয়স","en":"Supplier payables ageing","mix":"Supplier-কে দেনার বয়স","allow":["locations","brands"],"nodate":1,"cost":1,"sort":"balance:desc"},
   "purchases_by_supplier":{"group":"purchase","bn":"ক্রয় (সরবরাহকারী অনুযায়ী)","en":"Purchases by supplier","mix":"Purchase (supplier অনুযায়ী)","allow":["locations","brands"],"cost":1,"gdef":"supplier","dims":["supplier","location","day"],"sort":"total:desc"},
   "expense_by_head":{"group":"expense","bn":"খরচ (খাত অনুযায়ী)","en":"Expenses by head","mix":"খরচ (head অনুযায়ী)","allow":["locations","brands"],"gdef":"head","dims":["head","location","day"],"sort":"amount:desc"},
   "cash_short_over":{"group":"cash","bn":"ক্যাশ কম / বেশি","en":"Cash short / over","mix":"Cash কম / বেশি","allow":["locations","brands"],"gdef":"location","dims":["location","day","staff"],"sort":"net:asc"},
   "attendance_summary":{"group":"staff","bn":"হাজিরার সারসংক্ষেপ","en":"Attendance summary","mix":"হাজিরার summary","allow":["locations","brands"],"gdef":"person","dims":["person","location"],"sort":"absent:desc"},
   "exceptions_summary":{"group":"control","bn":"ব্যতিক্রম (গরমিল) সারসংক্ষেপ","en":"Exceptions summary","mix":"Exception summary","allow":["locations","brands"],"gdef":"form","dims":["form","location","flag","level","day"],"sort":"total:desc"}
  }$c$::jsonb) -> p_key;
$j$;

create or replace function public._r2_keys() returns text[]
language sql immutable set search_path = public as $$
  select array['item_slow','stock_low','stock_balance','wastage','expiry_soon','transfers_gap','supplier_ageing','purchases_by_supplier','expense_by_head','cash_short_over','attendance_summary','exceptions_summary'];
$$;

-- group (dimension) labels for the hub / group picker
create or replace function public._r2_dimlab(p_dim text) returns jsonb
language sql immutable set search_path = public as $$
  select ($c${"reason":["কারণ","Reason"],"item":["আইটেম","Item"],"location":["লোকেশন","Location"],"day":["দিন","Day"],"supplier":["সরবরাহকারী","Supplier"],
    "head":["খরচের খাত","Expense head"],"staff":["কর্মী","Staff"],"person":["কর্মী","Person"],"form":["ফর্ম","Form"],"flag":["ব্যতিক্রমের ধরন","Exception type"],"level":["মাত্রা","Level"]}$c$::jsonb) -> p_dim;
$$;

-- access: group grant (or view_reports), cost-only reports also need the cost right
create or replace function public._r2_ok(p_key text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare d jsonb := public._r2_def(p_key);
begin
  if d is null then return false; end if;
  return public.rpt_access(d ->> 'group') and (coalesce((d ->> 'cost')::int, 0) = 0 or public.rpt_cost_ok());
end $$;

-- ---------- catalogue ----------
create or replace function public.report_catalog2() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k text; d jsonb; out_ jsonb := '[]'::jsonb; dl jsonb; g text; ok boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  foreach k in array public._r2_keys() loop
    d := public._r2_def(k); ok := public._r2_ok(k); dl := '[]'::jsonb;
    if d ? 'dims' then
      for g in select jsonb_array_elements_text(d -> 'dims') loop
        dl := dl || jsonb_build_array(jsonb_build_object('key', g, 'time', g = 'day', 'label_bn', public._r2_dimlab(g) ->> 0, 'label_en', public._r2_dimlab(g) ->> 1, 'needs_rule', null));
      end loop;
    end if;
    out_ := out_ || jsonb_build_array(jsonb_build_object('key', k, 'group', d ->> 'group', 'grant', 'report_' || (d ->> 'group'), 'allowed', ok, 'kind', 'raw', 'engine', 2,
      'name_bn', d ->> 'bn', 'name_en', d ->> 'en', 'name_mix', d ->> 'mix',
      'filters', to_jsonb(case when coalesce((d ->> 'nodate')::int, 0) = 0 then array['date'] else '{}'::text[] end || coalesce((select array_agg(x) from jsonb_array_elements_text(d -> 'allow') x), '{}')),
      'dims', dl, 'default_group', nullif(d ->> 'gdef', ''), 'columns', '[]'::jsonb, 'compare', false, 'needs_date', coalesce((d ->> 'nodate')::int, 0) = 0, 'cost_only', coalesce((d ->> 'cost')::int, 0) = 1));
  end loop;
  return out_;
end $$;

-- ---------- the data ----------
create or replace function public.report_run2(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null, p_page int default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  def jsonb; flt jsonb; notes jsonb := '[]'::jsonb; today date := (now() at time zone 'Asia/Dhaka')::date; cost_ok boolean; eff int[]; nloc int;
  d1 date; d2 date; pr jsonb; preset text; pgsize int; pg int := least(greatest(coalesce(p_page, 1), 1), 1000); off int; lim int; cap constant int := 500;
  g text; t text; tot text; cols jsonb := '[]'::jsonb; outc jsonb := '[]'::jsonb; allowkeys text[] := '{}'; c jsonb; sk text; sd text; sraw text; sparts text[]; ordr text; dsort text;
  rows_ jsonb; totals_ jsonb; ngroups bigint := 0; hm boolean; dn boolean := false; cat text[]; cf text := ''; days_ numeric; bk text; buckets int[]; i int; lo int; hi int; bsel text := '';
  de text; dcols jsonb; dgrp text; n_unset bigint; n_bad bigint; cs text := ''; ct text := ''; allow_all boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  def := public._r2_def(p_key);
  if def is null then raise exception 'unknown_report'; end if;
  if not public._r2_ok(p_key) then raise exception 'not allowed'; end if;
  flt := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
  cost_ok := public.rpt_cost_ok();
  eff := public._r2_locs(flt);
  select count(*) into nloc from public.locations;
  if cardinality(public._r2_locs('{}'::jsonb)) < nloc then notes := notes || jsonb_build_array(jsonb_build_object('code', 'location_scope')); end if;
  if cardinality(eff) = 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_location', 'text_en', 'No location is open to you', 'text_bn', 'কোনো লোকেশন আপনার জন্য খোলা নেই')); end if;
  pgsize := least(greatest(coalesce(public.rule_num('report_page_size'), 50), 10), 200)::int;
  off := (pg - 1) * pgsize; lim := greatest(least(pgsize, cap - off), 0);
  -- unknown filter keys are reported, never used
  for g in select jsonb_object_keys(flt) loop
    if g in ('from', 'to', 'preset', 'compare_mode') or jsonb_typeof(flt -> g) = 'null' then continue; end if;
    if not (def -> 'allow' @> to_jsonb(g)) then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', left(g, 40))); end if;
  end loop;
  cat := case when def -> 'allow' @> '"categories"' then public.rpt_arr_text(flt -> 'categories') end;

  if coalesce((def ->> 'nodate')::int, 0) = 0 then
    preset := flt ->> 'preset';
    if preset is not null then
      pr := public.report_presets() -> preset;
      if pr is null or jsonb_typeof(pr) = 'null' then
        return jsonb_build_object('report', p_key, 'columns', '[]'::jsonb, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
          'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', 0, 'cap', cap),
          'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', left(preset, 30), 'text_en', 'Unknown date preset', 'text_bn', 'তারিখের প্রিসেটের নাম ভুল')));
      end if;
      d1 := (pr ->> 'from')::date; d2 := (pr ->> 'to')::date;
    else
      d1 := public.rpt_date(flt ->> 'from'); d2 := public.rpt_date(flt ->> 'to');
      if d1 is null and d2 is null then d1 := date_trunc('month', today)::date; d2 := today;
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'default_period', 'text_en', 'No period given: this month to date', 'text_bn', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত'));
      elsif d1 is null then d1 := d2; elsif d2 is null then d2 := today; end if;
    end if;
    if d2 < d1 or d2 - d1 > 365 then raise exception 'bad_range'; end if;
  end if;

  -- group (one dimension)
  if def ? 'dims' then
    dgrp := lower(btrim(coalesce(p_group, '')));
    if dgrp = '' then dgrp := def ->> 'gdef';
    elsif dgrp like '%,%' then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(split_part(dgrp, ',', 2), 30))); dgrp := split_part(dgrp, ',', 1);
    end if;
    if dgrp in ('none', 'total', '-') then dgrp := null;
    elsif dgrp is not null and not (def -> 'dims' @> to_jsonb(dgrp)) then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(dgrp, 30))); dgrp := def ->> 'gdef';
    end if;
  elsif p_group is not null and btrim(p_group) <> '' then
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(p_group, 30)));
  end if;

  -- ============ the queries ============
  if p_key = 'item_slow' then
    if cat is not null then cf := format(' and it.category = any (%L::text[])', cat); end if;
    t := format($f$with s as (select f.item_id, sum(f.qty) as qty, sum(f.net) as net, count(distinct f.sale_id) as bills, max(f.day) as last_sold
        from public.sales_fact f where f.status = 'done' and f.item_id is not null and f.day between %L and %L and f.location_id = any (%L::int[]) group by 1)
      select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, coalesce(it.category, '(none)') as category,
        coalesce(round(s.qty, 3), 0) as qty, coalesce(round(s.net, 2), 0) as net, coalesce(s.bills, 0) as bills, s.last_sold
      from public.items it left join s on s.item_id = it.id
      where it.is_active and it.sellable and it.retired_at is null%s$f$, d1, d2, eff, cf);
    tot := 'count(*) as items, count(*) filter (where qty = 0) as unsold_items, coalesce(sum(net), 0) as net';
    cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["category","ক্যাটাগরি","Category","text"],["qty","বিক্রি পরিমাণ","Qty sold","num"],["net","বিক্রি","Sales","money"],["bills","বিল","Bills","int"],["last_sold","শেষ বিক্রি","Last sold","date"]]';
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Active sellable items with no sale in the period show 0. Smallest quantity first.', 'text_bn', 'এই সময়ে বিক্রি না হওয়া চালু আইটেম ০ দেখাবে। কম বিক্রি আগে।'));

  elsif p_key = 'stock_low' or p_key = 'stock_balance' then
    if cat is not null then cf := format(' and it.category = any (%L::text[])', cat); end if;
    if p_key = 'stock_low' then
      cs := case when cost_ok then ', round(greatest(it.min_stock - b.qty, 0) * b.avg_cost, 2) as reorder_value' else '' end;
      t := format($f$select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, coalesce(it.category, '(none)') as category, l.id as location_id,
          l.name_bn as location_bn, l.name_en as location_en, b.qty, it.min_stock, round(it.min_stock - b.qty, 3) as short_by, it.unit%s
        from public.stock_balance b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        where b.location_id = any (%L::int[]) and it.is_active and it.min_stock is not null and b.qty <= it.min_stock%s$f$, cs, eff, cf);
      tot := 'count(*) as lines, count(*) filter (where qty <= 0) as at_zero' || case when cost_ok then ', sum(reorder_value) as reorder_value' else '' end;
      cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["category","ক্যাটাগরি","Category","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["qty","আছে","On hand","num"],["min_stock","ন্যূনতম","Minimum","num"],["short_by","ঘাটতি","Short by","num"],["unit","একক","Unit","text"]]';
      select count(*) into n_unset from public.items it where it.is_active and it.tracked and it.min_stock is null;
      if n_unset > 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'min_stock', 'text_en', n_unset || ' tracked items have no minimum set, so they cannot be checked', 'text_bn', n_unset || 'টি ট্র্যাক করা আইটেমে ন্যূনতম স্টক বসানো নেই, তাই যাচাই হয়নি')); end if;
    else
      cs := case when cost_ok then ', b.avg_cost, round(b.qty * b.avg_cost, 2) as value' else '' end;
      t := format($f$select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, coalesce(it.category, '(none)') as category, l.id as location_id,
          l.name_bn as location_bn, l.name_en as location_en, b.qty, it.unit, it.min_stock,
          case when it.min_stock is null then 'no_min' when b.qty <= it.min_stock then 'low' else 'ok' end as state%s
        from public.stock_balance b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        where b.location_id = any (%L::int[]) and it.is_active%s$f$, cs, eff, cf);
      tot := 'count(*) as lines, count(*) filter (where state = ''low'') as low_lines, count(*) filter (where state = ''no_min'') as no_min_lines' || case when cost_ok then ', sum(value) as value' else '' end;
      cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["category","ক্যাটাগরি","Category","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["qty","আছে","On hand","num"],["unit","একক","Unit","text"],["min_stock","ন্যূনতম","Minimum","num"],["state","অবস্থা","State","text"]]';
    end if;
    if cost_ok then
      cols := cols || case when p_key = 'stock_low' then '[["reorder_value","পূরণের আনুমানিক খরচ","Approx. cost to refill","money"]]'::jsonb
                           else '[["avg_cost","গড় খরচ","Avg cost","money"],["value","মূল্য","Value","money"]]'::jsonb end;
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;

  elsif p_key = 'wastage' then
    dcols := case dgrp when 'item' then '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["unit","একক","Unit","text"]]'
                       when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'day' then '[["day","দিন","Day","date"]]'
                       when 'reason' then '[["reason","","","id"],["reason_bn","কারণ","Reason","text"],["reason_en","Reason (EN)","Reason (EN)","text"]]'
                       else '[]' end::jsonb;
    cs := case when cost_ok then ', round(sum(w.qty * sl.unit_cost) filter (where sl.unit_cost is not null), 2) as value, count(*) filter (where sl.unit_cost is null) as uncosted_entries' else '' end;
    t := format($f$select %s count(*) as entries%s%s
      from public.stock_wastage w join public.items it on it.id = w.item_id join public.locations l on l.id = w.location_id
        left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.reason_code
        left join public.stock_ledger sl on sl.id = w.ledger_id
      where (w.made_at at time zone 'Asia/Dhaka')::date between %L and %L and w.location_id = any (%L::int[])%s$f$,
      case dgrp when 'item' then 'it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, it.unit as unit,'
                when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,'
                when 'day' then '(w.made_at at time zone ''Asia/Dhaka'')::date as day,'
                when 'reason' then 'w.reason_code as reason, coalesce(o.label_bn, w.reason_code) as reason_bn, coalesce(o.label_en, w.reason_code) as reason_en,'
                else '' end,
      case when dgrp = 'item' then ', round(sum(w.qty), 3) as qty' else '' end, cs, d1, d2, eff,
      case dgrp when 'item' then ' group by it.id, it.code, it.name_bn, it.name_en, it.unit'
                when 'location' then ' group by l.id, l.name_bn, l.name_en'
                when 'day' then ' group by 1'
                when 'reason' then ' group by w.reason_code, o.label_bn, o.label_en'
                else '' end);
    tot := 'sum(entries) as entries' || case when cost_ok then ', sum(value) as value, sum(uncosted_entries) as uncosted_entries' else '' end;
    cols := dcols || '[["entries","বার","Entries","int"]]'::jsonb || case when dgrp = 'item' then '[["qty","পরিমাণ","Qty","num"]]'::jsonb else '[]'::jsonb end;
    if cost_ok then cols := cols || '[["value","মূল্য (খরচ জানা অংশে)","Value (costed part)","money"],["uncosted_entries","খরচ অজানা সারি","Entries with no cost","int"]]'::jsonb;
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
    if dgrp is distinct from 'item' then notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Quantity is shown only per item (units differ between items).', 'text_bn', 'পরিমাণ শুধু আইটেম অনুযায়ী দেখানো হয় (আইটেমের একক আলাদা)।')); end if;

  elsif p_key = 'expiry_soon' then
    days_ := public.rule_num('report_expiry_soon_days');
    if cat is not null then cf := format(' and it.category = any (%L::text[])', cat); end if;
    cs := case when cost_ok then ', round(b.qty_remaining * sb.avg_cost, 2) as value' else '' end;
    t := format($f$select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,
        (b.made_at at time zone 'Asia/Dhaka')::date as made_on, (b.expires_at at time zone 'Asia/Dhaka')::date as expires_on,
        (b.expires_at at time zone 'Asia/Dhaka')::date - %L::date as days_left, b.qty_remaining as qty, it.unit,
        case when (b.expires_at at time zone 'Asia/Dhaka')::date < %L::date then 'expired' else 'soon' end as state%s
      from public.stock_batches b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        left join public.stock_balance sb on sb.item_id = b.item_id and sb.location_id = b.location_id
      where b.qty_remaining > 0 and b.expires_at is not null and b.location_id = any (%L::int[])
        and (b.expires_at at time zone 'Asia/Dhaka')::date <= %L::date + %s%s$f$,
      today, today, cs, eff, today, case when days_ is null then '-1' else (days_::int)::text end, cf);
    tot := 'count(*) as batches, count(*) filter (where state = ''expired'') as expired_batches' || case when cost_ok then ', sum(value) as value' else '' end;
    cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["made_on","তৈরি","Made","date"],["expires_on","মেয়াদ শেষ","Expires","date"],["days_left","বাকি দিন","Days left","int"],["qty","পরিমাণ (বাকি)","Qty left","num"],["unit","একক","Unit","text"],["state","অবস্থা","State","text"]]';
    if cost_ok then cols := cols || '[["value","আনুমানিক মূল্য","Approx. value","money"]]'::jsonb; else notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
    if days_ is null then notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_expiry_soon_days', 'text_en', 'Set "days ahead" in Rules to also see batches that expire soon. Only batches already expired are listed.', 'text_bn', 'শিগগির শেষ হবে এমন ব্যাচ দেখতে নিয়মে দিনের সংখ্যা বসান। এখন শুধু মেয়াদ-শেষ ব্যাচ দেখাচ্ছে।')); end if;

  elsif p_key = 'transfers_gap' then
    t := format($f$select (x.sent_at at time zone 'Asia/Dhaka')::date as sent_day, lf.name_bn as from_bn, lf.name_en as from_en, lt.name_bn as to_bn, lt.name_en as to_en,
        it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, x.qty as sent_qty, x.received_qty,
        case when x.status = 'received' then round(x.qty - coalesce(x.received_qty, x.qty), 3) end as diff_qty, x.status, x.sent_staff, x.received_staff
      from public.stock_transfers x join public.items it on it.id = x.item_id join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id
      where (x.sent_at at time zone 'Asia/Dhaka')::date between %L and %L and (x.from_location_id = any (%L::int[]) or x.to_location_id = any (%L::int[]))
        and x.status <> 'cancelled' and (x.status = 'sent' or coalesce(x.received_qty, x.qty) <> x.qty)$f$, d1, d2, eff, eff);
    tot := 'count(*) as transfers, count(*) filter (where status = ''sent'') as not_received, count(*) filter (where diff_qty <> 0) as short_received';
    cols := '[["sent_day","পাঠানো","Sent","date"],["from_bn","কোথা থেকে","From","text"],["from_en","From (EN)","From (EN)","text"],["to_bn","কোথায়","To","text"],["to_en","To (EN)","To (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["sent_qty","পাঠানো পরিমাণ","Sent qty","num"],["received_qty","পৌঁছেছে","Received qty","num"],["diff_qty","পার্থক্য","Difference","num"],["status","অবস্থা","Status","text"],["sent_staff","পাঠিয়েছে","Sent by","text"],["received_staff","গ্রহণ করেছে","Received by","text"]]';

  elsif p_key = 'supplier_ageing' then
    allow_all := public._all_locs() and public.rpt_arr_int(flt -> 'locations') is null and public.rpt_arr_text(flt -> 'brands') is null;
    bk := public.rule_txt('report_aging_buckets');
    if bk is not null and bk ~ '^[0-9]{1,4}(,[0-9]{1,4}){0,5}$' then
      buckets := string_to_array(bk, ',')::int[];
      for i in 2..cardinality(buckets) loop if buckets[i] <= buckets[i - 1] then buckets := null; exit; end if; end loop;
    end if;
    cols := '[["supplier_id","","","id"],["supplier","সরবরাহকারী","Supplier","text"],["balance","মোট দেনা","Total payable","money"],["opening_part","শুরুর বাকি (তারিখ ছাড়া)","Opening balance part","money"]]';
    if buckets is not null and cardinality(buckets) > 0 then
      for i in 1..cardinality(buckets) + 1 loop
        lo := case when i = 1 then 0 else buckets[i - 1] + 1 end; hi := case when i <= cardinality(buckets) then buckets[i] end;
        bsel := bsel || format(', round(coalesce(sum(o.open_amt) filter (where o.bill_date is not null and (%L::date - o.bill_date) %s), 0), 2) as bucket_%s', today,
          case when hi is null then '>= ' || lo else 'between ' || lo || ' and ' || hi end, i);
        cols := cols || jsonb_build_array(jsonb_build_array('bucket_' || i, case when hi is null then lo || '+ দিন' else lo || '–' || hi || ' দিন' end, case when hi is null then lo || '+ days' else lo || '–' || hi || ' days' end, 'money'));
      end loop;
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_aging_buckets', 'text_en', 'Set the ageing buckets (days) in Rules to split by age', 'text_bn', 'বয়স ভাগ করতে নিয়মে দিনের ভাগ বসান')); end if;
    cols := cols || '[["oldest_days","সবচেয়ে পুরনো (দিন)","Oldest (days)","int"],["credit_days","বাকির মেয়াদ (দিন)","Credit days","int"],["overdue","মেয়াদ পার","Past credit days","money"]]'::jsonb;
    t := format($f$with o as (select * from public._sup_open(null) where open_amt > 0)
      select s.id as supplier_id, s.name as supplier, round(sum(o.open_amt), 2) as balance, round(coalesce(sum(o.open_amt) filter (where o.bill_date is null), 0), 2) as opening_part%s,
        max(%L::date - o.bill_date) as oldest_days, s.credit_days,
        round(coalesce(sum(o.open_amt) filter (where s.credit_days is not null and o.bill_date is not null and o.bill_date + s.credit_days < %L::date), 0), 2) as overdue
      from o join public.suppliers s on s.id = o.supplier_id
      where o.location_id = any (%L::int[]) or (o.location_id is null and %L::boolean)
      group by s.id, s.name, s.credit_days$f$, bsel, today, today, eff, allow_all);
    tot := 'count(*) as suppliers, sum(balance) as balance, sum(overdue) as overdue' || (select coalesce(string_agg(format(', sum(bucket_%s) as bucket_%s', n, n), ''), '') from generate_series(1, coalesce(cardinality(buckets), -1) + 1) n where buckets is not null);
    if not allow_all then notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Opening balances (no shop) are included only when all locations are selected', 'text_bn', 'শুরুর বাকি (দোকান ছাড়া) শুধু সব লোকেশন বাছা থাকলে ধরা হয়')); end if;

  elsif p_key = 'purchases_by_supplier' then
    de := case dgrp when 'supplier' then 's.id as supplier_id, s.name as supplier,' when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,'
                    when 'day' then 'b.bill_date as day,' else '' end;
    t := format($f$select %s count(*) filter (where b.kind = 'bill') as bills, coalesce(sum(b.subtotal) filter (where b.kind = 'bill'), 0) as subtotal,
        coalesce(sum(b.discount) filter (where b.kind = 'bill'), 0) as discount, coalesce(sum(b.total) filter (where b.kind = 'bill'), 0) as total,
        coalesce(sum(b.paid) filter (where b.kind = 'bill'), 0) as paid, coalesce(sum(b.total - b.paid) filter (where b.kind = 'bill'), 0) as due,
        count(*) filter (where b.kind = 'return') as returns, coalesce(sum(b.total) filter (where b.kind = 'return'), 0) as returns_total
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id join public.locations l on l.id = b.location_id
      where b.status = 'posted' and b.bill_date between %L and %L and b.location_id = any (%L::int[])%s$f$, de, d1, d2, eff,
      case dgrp when 'supplier' then ' group by s.id, s.name' when 'location' then ' group by l.id, l.name_bn, l.name_en' when 'day' then ' group by b.bill_date' else '' end);
    tot := 'sum(bills) as bills, sum(subtotal) as subtotal, sum(discount) as discount, sum(total) as total, sum(paid) as paid, sum(due) as due, sum(returns) as returns, sum(returns_total) as returns_total';
    cols := (case dgrp when 'supplier' then '[["supplier_id","","","id"],["supplier","সরবরাহকারী","Supplier","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'day' then '[["day","দিন","Day","date"]]' else '[]' end)::jsonb
      || '[["bills","বিল","Bills","int"],["subtotal","সাবটোটাল","Subtotal","money"],["discount","ছাড়","Discount","money"],["total","মোট","Total","money"],["paid","পরিশোধ","Paid","money"],["due","বাকি","Due","money"],["returns","রিটার্ন","Returns","int"],["returns_total","রিটার্নের টাকা","Returns amount","money"]]'::jsonb;

  elsif p_key = 'expense_by_head' then
    t := format($f$select %s count(*) filter (where x.amt is not null) as lines, coalesce(sum(x.amt), 0) as amount,
        count(*) filter (where x.amt is not null and x.rcpt = 'no') as no_receipt_lines, coalesce(sum(x.amt) filter (where x.rcpt = 'no'), 0) as no_receipt_amount,
        round(100 * coalesce(sum(x.amt), 0) / nullif(sum(sum(x.amt)) over (), 0), 2) as share_pct, count(*) filter (where x.amt is null) as skipped_lines
      from (select e.id, e.location_id, e.entry_date, public._r2_num(ln -> 'amount') as amt, ln ->> 'receipt' as rcpt, coalesce(nullif(btrim(ln ->> 'head'), ''), '-') as head
            from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
            where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])) x
        join public.locations l on l.id = x.location_id left join public.option_lists o on o.list_code = 'expense_heads' and o.value_code = x.head
      %s$f$,
      case dgrp when 'head' then 'x.head as head, coalesce(o.label_bn, x.head) as head_bn, coalesce(o.label_en, x.head) as head_en,'
                when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,'
                when 'day' then 'x.entry_date as day,' else '' end, d1, d2, eff,
      case dgrp when 'head' then 'group by x.head, o.label_bn, o.label_en' when 'location' then 'group by l.id, l.name_bn, l.name_en' when 'day' then 'group by x.entry_date' else '' end);
    tot := 'sum(lines) as lines, sum(amount) as amount, sum(no_receipt_lines) as no_receipt_lines, sum(no_receipt_amount) as no_receipt_amount, sum(skipped_lines) as skipped_lines';
    cols := (case dgrp when 'head' then '[["head","","","id"],["head_bn","খাত","Head","text"],["head_en","Head (EN)","Head (EN)","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'day' then '[["day","দিন","Day","date"]]' else '[]' end)::jsonb
      || '[["lines","লাইন","Lines","int"],["amount","টাকা","Amount","money"],["share_pct","অংশ %","Share %","pct"],["no_receipt_lines","রসিদ ছাড়া লাইন","Lines without receipt","int"],["no_receipt_amount","রসিদ ছাড়া টাকা","Amount without receipt","money"],["skipped_lines","পড়া যায়নি এমন লাইন","Unreadable lines","int"]]'::jsonb;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'From submitted and approved expense vouchers (10-2). Drafts are not counted. A line whose amount is not a plain number is skipped and counted.', 'text_bn', 'জমা ও অনুমোদিত ব্যয় ভাউচার (১০-২) থেকে। খসড়া ধরা হয়নি। অঙ্ক পড়া না গেলে লাইন বাদ ও গণনা।'));

  elsif p_key = 'cash_short_over' then
    t := format($f$select %s count(*) as sheets, count(*) filter (where x.so < 0) as short_sheets, count(*) filter (where x.so > 0) as over_sheets,
        coalesce(-sum(x.so) filter (where x.so < 0), 0) as short_amount, coalesce(sum(x.so) filter (where x.so > 0), 0) as over_amount, coalesce(sum(x.so), 0) as net,
        coalesce(max(abs(x.so)), 0) as worst
      from (select e.id, e.location_id, e.entry_date, coalesce(nullif(btrim(e.created_staff), ''), '-') as staff,
              coalesce((select sum(public._r2_num(f -> 'amount')) from jsonb_array_elements(case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end) f where f ->> 'code' = 'cash_short_over'), 0) as so
            from public.entries e where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])) x
        join public.locations l on l.id = x.location_id
      %s$f$,
      case dgrp when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,' when 'day' then 'x.entry_date as day,' when 'staff' then 'x.staff as staff,' else '' end, d1, d2, eff,
      case dgrp when 'location' then 'group by l.id, l.name_bn, l.name_en' when 'day' then 'group by x.entry_date' when 'staff' then 'group by x.staff' else '' end);
    tot := 'sum(sheets) as sheets, sum(short_sheets) as short_sheets, sum(over_sheets) as over_sheets, sum(short_amount) as short_amount, sum(over_amount) as over_amount, sum(net) as net, max(worst) as worst';
    cols := (case dgrp when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]' when 'day' then '[["day","দিন","Day","date"]]'
                       when 'staff' then '[["staff","কর্মী (শিট লেখক)","Staff (sheet writer)","text"]]' else '[]' end)::jsonb
      || '[["sheets","শিট","Sheets","int"],["short_sheets","কম হওয়া শিট","Sheets short","int"],["over_sheets","বেশি হওয়া শিট","Sheets over","int"],["short_amount","কম (মোট)","Short (total)","money"],["over_amount","বেশি (মোট)","Over (total)","money"],["net","নিট (বেশি − কম)","Net (over − short)","money"],["worst","সবচেয়ে বড় পার্থক্য","Largest gap","money"]]'::jsonb;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Taken from the short/over flag of each daily showroom sheet (14-1), worked out on the phone when the sheet was saved. A sheet with an exact match carries no flag and counts as 0.', 'text_bn', 'প্রতিটি দৈনিক শোরুম শিটের (১৪-১) কম/বেশি চিহ্ন থেকে, যা ফোনে শিট সেভের সময় হিসাব হয়েছিল। ঠিকঠাক মিললে চিহ্ন থাকে না, ০ ধরা হয়।'));

  elsif p_key = 'attendance_summary' then
    t := format($f$select %s count(distinct x.id) as sheets, coalesce(sum(x.present), 0) as present, coalesce(sum(x.late), 0) as late, coalesce(sum(x.absent), 0) as absent,
        coalesce(sum(x.leave_unpaid), 0) as leave_unpaid, coalesce(sum(x.leave_paid), 0) as leave_paid, coalesce(sum(x.ot_hours), 0) as ot_hours
      from (select e.id, e.location_id, btrim(r ->> 'name') as person, public._r2_num(r -> 'present') as present, public._r2_num(r -> 'late') as late, public._r2_num(r -> 'absent') as absent,
              public._r2_num(r -> 'leave_unpaid') as leave_unpaid, public._r2_num(r -> 'leave_paid') as leave_paid, public._r2_num(r -> 'ot_hours') as ot_hours
            from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'staff') = 'array' then e.data -> 'staff' else '[]'::jsonb end) r
            where e.form_code = '02-1' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])
              and btrim(coalesce(r ->> 'name', '')) <> '') x
        join public.locations l on l.id = x.location_id
      %s$f$,
      case dgrp when 'person' then 'x.person as person,' when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,' else '' end, d1, d2, eff,
      case dgrp when 'person' then 'group by x.person' when 'location' then 'group by l.id, l.name_bn, l.name_en' else '' end);
    tot := 'sum(present) as present, sum(late) as late, sum(absent) as absent, sum(leave_unpaid) as leave_unpaid, sum(leave_paid) as leave_paid, sum(ot_hours) as ot_hours';
    cols := (case dgrp when 'person' then '[["person","কর্মী","Person","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]' else '[]' end)::jsonb
      || '[["sheets","শিট","Sheets","int"],["present","উপস্থিত","Present","num"],["late","দেরি","Late","num"],["absent","অনুপস্থিত","Absent","num"],["leave_unpaid","বিনা বেতনের ছুটি","Unpaid leave","num"],["leave_paid","সবেতন ছুটি","Paid leave","num"],["ot_hours","ওভারটাইম ঘণ্টা","Overtime hours","num"]]'::jsonb;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'From monthly attendance registers (02-1) dated inside the period. Same person on two sheets is added up by name.', 'text_bn', 'সময়ের মধ্যে তারিখের মাসিক হাজিরা রেজিস্টার (০২-১) থেকে। একই নাম দুই শিটে থাকলে যোগ হয়।'));

  elsif p_key = 'exceptions_summary' then
    t := format($f$select %s count(*) as total, count(*) filter (where x.status = 'open') as open, count(*) filter (where x.status = 'resolved') as resolved,
        count(*) filter (where x.level = 'red') as red, count(*) filter (where x.level = 'yellow') as yellow,
        round(avg(extract(epoch from (x.resolved_at - x.created_at)) / 3600.0) filter (where x.status = 'resolved' and x.resolved_at is not null), 1) as avg_hours_to_resolve
      from public.exceptions x join public.locations l on l.id = x.location_id
      where x.entry_date between %L and %L and x.location_id = any (%L::int[])
      %s$f$,
      case dgrp when 'form' then 'x.form_code as form,' when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,' when 'flag' then 'x.flag_code as flag,'
                when 'level' then 'x.level as level,' when 'day' then 'x.entry_date as day,' else '' end, d1, d2, eff,
      case dgrp when 'form' then 'group by x.form_code' when 'location' then 'group by l.id, l.name_bn, l.name_en' when 'flag' then 'group by x.flag_code' when 'level' then 'group by x.level' when 'day' then 'group by x.entry_date' else '' end);
    tot := 'sum(total) as total, sum(open) as open, sum(resolved) as resolved, sum(red) as red, sum(yellow) as yellow';
    cols := (case dgrp when 'form' then '[["form","ফর্ম","Form","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'flag' then '[["flag","ধরন","Type","text"]]' when 'level' then '[["level","মাত্রা","Level","text"]]' when 'day' then '[["day","দিন (শিটের)","Day (of sheet)","date"]]' else '[]' end)::jsonb
      || '[["total","মোট","Total","int"],["open","খোলা","Open","int"],["resolved","সমাধান","Resolved","int"],["red","লাল","Red","int"],["yellow","হলুদ","Yellow","int"],["avg_hours_to_resolve","গড় সমাধানের ঘণ্টা","Avg hours to resolve","num"]]'::jsonb;
  end if;

  -- columns -> response shape, sort whitelist
  for c in select * from jsonb_array_elements(cols) loop
    outc := outc || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3,
      'role', case when c ->> 3 in ('money', 'int', 'num', 'pct') then 'measure' else 'dim' end, 'cost', (c ->> 0) in ('value', 'avg_cost', 'reorder_value', 'uncosted_entries')));
    allowkeys := allowkeys || (c ->> 0);
  end loop;
  sraw := lower(btrim(coalesce(p_sort, '')));
  if sraw <> '' then
    if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
    sparts := regexp_split_to_array(sraw, '[: ]+');
    if sparts[1] = any (allowkeys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
  end if;
  if sk is null then
    dsort := def ->> 'sort';
    if dsort = '@dim' or split_part(dsort, ':', 1) <> all (allowkeys) then
      sk := coalesce((select c2 ->> 0 from jsonb_array_elements(cols) c2 where c2 ->> 3 <> 'id' limit 1), allowkeys[1]); sd := 'asc';
    else sk := split_part(dsort, ':', 1); sd := split_part(dsort, ':', 2); end if;
  end if;
  ordr := quote_ident(sk) || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last, 1';

  execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''_n'' - ''_rn'' order by x._rn), ''[]''::jsonb), coalesce(max(x._n), 0) from (select q.*, count(*) over () as _n, row_number() over (order by %s) as _rn from (%s) q order by %s limit %s offset %s) x',
    ordr, t, ordr, lim, off) into rows_, ngroups;
  execute format('select to_jsonb(x) from (select %s from (%s) q) x', tot, t) into totals_;
  hm := (off + pgsize) < least(ngroups, cap);
  if ngroups > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ngroups)); end if;
  if jsonb_array_length(rows_) = 0 or ngroups = 0 then
    dn := true;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_data', 'text_en', 'Data needed: nothing matches this period / filters', 'text_bn', 'তথ্য দরকার: এই সময়/ফিল্টারে কিছু নেই'));
  end if;
  return jsonb_build_object('report', p_key, 'columns', outc, 'rows', rows_, 'totals', totals_, 'compare', null,
    'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', ngroups, 'cap', cap), 'has_more', coalesce(hm, false), 'notes', notes, 'data_needed', dn,
    'meta', jsonb_build_object('from', d1, 'to', d2, 'group', case when dgrp is null then '[]'::jsonb else jsonb_build_array(dgrp) end, 'sort', sk, 'dir', sd, 'cost_shown', cost_ok, 'today', today));
end $$;

-- ---------- export log ----------
create or replace function public.log_report_export2(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or not (p_key = any (public._r2_keys())) then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges ----------
revoke all on function public._r2_num(jsonb), public._r2_locs(jsonb), public._r2_def(text), public._r2_keys(), public._r2_dimlab(text), public._r2_ok(text),
  public.report_catalog2(), public.report_run2(text, jsonb, text, text, int), public.log_report_export2(text, text, jsonb, int) from public, anon, authenticated;
grant execute on function public.report_catalog2(), public.report_run2(text, jsonb, text, text, int), public.log_report_export2(text, text, jsonb, int) to authenticated;

notify pgrst, 'reload schema';
