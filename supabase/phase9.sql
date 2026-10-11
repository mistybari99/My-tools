-- ============================================================
-- BOS tool · Phase 9: REPORT ENGINE core + the P1 reports that need no new data capture.
-- Run AFTER phase3/4/5/6/7 (ALL_NEW.sql). Additive and idempotent: safe to run again. Nothing existing is changed or dropped.
-- Does not depend on phase8: optional phase8 columns (discount kind / percent) are detected and used only if they exist.
--
-- What is here
--   report_brand_map   location -> brand (owner editable; brand is not stored on sales)
--   rpt_bill / rpt_daily / sales_fact / rpt_pay   read-only fact views (NOT readable by the app: only report_run reads them)
--   report_presets()   date presets; a preset that needs a missing rule (fiscal year, week start) is returned as null
--   report_catalog()   the list of reports for the UI (names, group, grant, filters, dims, measures)
--   report_run(key, filters, group, sort, page, compare)   ONE server function; user input never becomes SQL
--                      (keys are looked up in a fixed whitelist; values are quoted with %L after type checks)
--
-- Security
--   * every call needs the grant report_<group> (owner always may; the owner edits it in "Who may do what")
--   * rows are limited to can_loc() locations, always
--   * cost columns (cogs, gp, gp_pct, uncosted_pct) are not even computed unless owner / ITEM_COST view / grant view_cost
--   * customer mobile numbers are masked unless owner / POS approve / grant view_customer_mobile
--   * thresholds (fiscal year start, week start, aging buckets, near-limit %, page size) are RULES with no built-in value:
--     missing -> the result says "data needed" instead of guessing
-- ============================================================

create index if not exists sales_date_loc on public.sales (sale_date, location_id);
create index if not exists sale_payments_paid_at on public.sale_payments (paid_at);

-- ---------- brand of a location (sales do not store a brand; the owner maps locations to brands) ----------
create table if not exists public.report_brand_map (
  location_id int primary key references public.locations(id),
  brand_code text not null,
  brand_bn text not null,
  brand_en text not null
);
alter table public.report_brand_map enable row level security;
revoke all on public.report_brand_map from public, anon;
grant select, insert, update, delete on public.report_brand_map to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'report_brand_map' and policyname = 'report_brand_map_read') then
    create policy report_brand_map_read on public.report_brand_map for select to authenticated using (public.is_active());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'report_brand_map' and policyname = 'report_brand_map_owner') then
    create policy report_brand_map_owner on public.report_brand_map for all to authenticated using (public.is_owner()) with check (public.is_owner());
  end if;
end $$;
-- the three brands named in the guidebook (docs/LANGUAGE.md); factories and the godown are left UNMAPPED on purpose (owner decides)
insert into public.report_brand_map (location_id, brand_code, brand_bn, brand_en)
  select l.id, v.b, v.bn, v.en from public.locations l join (values
    ('main', 'islamiya', 'ইসলামিয়া মিষ্টি ঘর', 'ISLAMIYA MISTY GHAR'),
    ('branch2', 'islamiya', 'ইসলামিয়া মিষ্টি ঘর', 'ISLAMIYA MISTY GHAR'),
    ('mishti_bari', 'misty_bari', 'মিষ্টি বাড়ি', 'MISTY BARI'),
    ('al_cakes', 'al_cakiz', 'AL-CAKIZ', 'AL-CAKIZ')) v(code, b, bn, en) on v.code = l.code
  on conflict (location_id) do nothing;

-- ---------- rules (no built-in values: empty = "data needed") ----------
insert into public.rules (key, module, kind, default_value, unit, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('fiscal_year_start_month', 'reports', 'number', null, 'মাস (১-১২)', 1, 12, 'অর্থবছর শুরুর মাস (১=জানুয়ারি … ১২=ডিসেম্বর)', 'অর্থবছর শুরুর মাস (1-12)', 'Fiscal year starts in month (1-12)', 'ফাঁকা থাকলে অর্থবছর রিপোর্ট ও প্রিসেট বন্ধ থাকে', 'Empty = fiscal-year presets and grouping are unavailable', 60),
 ('week_start_dow', 'reports', 'number', null, 'বার (০=রবি … ৬=শনি)', 0, 6, 'সপ্তাহ শুরুর বার (০=রবি, ১=সোম … ৬=শনি)', 'সপ্তাহ শুরুর বার (0=Sun … 6=Sat)', 'Week starts on (0=Sunday … 6=Saturday)', 'ফাঁকা থাকলে সাপ্তাহিক প্রিসেট বন্ধ; সপ্তাহ-ওয়াইজ ভাগে সোমবার ধরা হয় (নোটসহ)', 'Empty = week presets unavailable; weekly grouping uses Monday and says so', 61),
 ('report_aging_buckets', 'reports', 'text', null, 'দিন', null, null, 'বাকির বয়স ভাগ (দিন, কমা দিয়ে, যেমন 7,30,60)', 'বাকির বয়স bucket (দিন, comma দিয়ে)', 'Receivable aging buckets in days, comma separated (e.g. 7,30,60)', 'ফাঁকা থাকলে বয়স ভাগ দেখাবে না', 'Empty = no aging buckets are shown', 62),
 ('report_near_limit_pct', 'reports', 'number', null, '%', 1, 1000, 'ক্রেডিট সীমার কত % হলে "সীমার কাছে" ধরা হবে', 'Credit limit এর কত % হলে "কাছাকাছি"', 'Share of the credit limit that counts as "near the limit"', 'ফাঁকা থাকলে "কাছাকাছি" দেখানো হবে না', 'Empty = no "near" status is shown', 63),
 ('report_page_size', 'reports', 'number', null, 'সারি', 10, 200, 'রিপোর্টের এক পাতায় কত সারি (ফাঁকা = ৫০)', 'Report এক পাতায় কত row (ফাঁকা = 50)', 'Rows per report page (empty = 50)', null, null, 64)
 on conflict (key) do nothing;

-- ---------- grants: who may open which report group (owner always may; the owner edits these) ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('report_sales', 'reports', 60, 'রিপোর্ট: বিক্রি', 'Report: Sales', 'Reports: Sales', 'once', null),
 ('report_pos', 'reports', 61, 'রিপোর্ট: POS (দিনশেষ, বাতিল, কুইক)', 'Report: POS (day close, voids, quick)', 'Reports: POS (day close, voids, quick sales)', 'once', null),
 ('report_cash', 'reports', 62, 'রিপোর্ট: পেমেন্ট ও ওয়ালেট', 'Report: Payments & wallets', 'Reports: Payments and wallets', 'once', null),
 ('report_customers', 'reports', 63, 'রিপোর্ট: গ্রাহক ও বাকি', 'Report: Customers & dues', 'Reports: Customers and dues', 'once', null)
 on conflict (grant_code) do nothing;
-- start the same as today: whoever may approve on the POS form gets the report grants (the owner can change this at any time)
insert into public.rule_grants (grant_code, role_code)
  select g.grant_code, p.role_code from public.role_form_perms p
  cross join (values ('report_sales'), ('report_pos'), ('report_cash'), ('report_customers')) g(grant_code)
  where p.form_code = 'POS' and p.can_approve
  on conflict do nothing;

-- ---------- fact views (columns are fixed; optional phase8 columns are appended only when they exist) ----------
do $v$
declare dk text := 'null::text'; dp text := 'null::numeric';
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = 'discount_kind') then dk := 's.discount_kind::text'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = 'discount_pct') then dp := 's.discount_pct::numeric';
  elsif exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = 'discount_percent') then dp := 's.discount_percent::numeric'; end if;

  -- one row per sale (all statuses). Money columns bills/gross/discount/net/paid/due count only done sales; *_raw / total are as stored.
  execute $q$
  create or replace view public.rpt_bill as
  select s.id as sale_id, s.receipt, s.sale_date as day, s.sold_at,
    extract(hour from s.sold_at at time zone 'Asia/Dhaka')::int as hour,
    extract(dow from s.sale_date)::int as dow,
    s.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
    bm.brand_code, bm.brand_bn, bm.brand_en,
    s.created_staff as staff, s.status, s.pay_mode, s.sale_type, s.customer_id, cu.name as customer_name, cu.mobile, s.quick,
    s.subtotal, s.discount as discount_raw, s.total, s.paid as paid_raw, s.due_amount as due_raw,
    (s.status = 'done')::int as bills, (s.status = 'void')::int as void_bills,
    case when s.status = 'done' then s.subtotal else 0 end as gross,
    case when s.status = 'done' then s.discount else 0 end as discount,
    case when s.status = 'done' then s.total else 0 end as net,
    case when s.status = 'done' then s.paid else 0 end as paid,
    case when s.status = 'done' then s.due_amount else 0 end as due,
    (s.status = 'done' and s.quick)::int as quick_bills,
    case when s.status = 'void' then s.total else 0 end as void_amt,
    (s.status = 'done' and s.discount > 0)::int as disc_bills,
    s.void_staff, s.void_note, s.void_at,
    case when s.status = 'done' then coalesce(x.ov, 0) else 0 end as override_lines,
    case when s.status = 'done' then coalesce(x.cu_, 0) else 0 end as custom_lines,
    case when s.status = 'done' then coalesce(x.qk, 0) else 0 end as quick_lines,
    $q$ || dk || $q$ as discount_kind, $q$ || dp || $q$ as discount_pct
  from public.sales s
  join public.locations lo on lo.id = s.location_id
  left join public.report_brand_map bm on bm.location_id = s.location_id
  left join public.customers cu on cu.id = s.customer_id
  left join lateral (
    select count(*) filter (where e->>'override' = 'true') as ov,
           count(*) filter (where e->>'custom' = 'true') as cu_,
           count(*) filter (where nullif(e->>'item_id', '') is null and coalesce(e->>'custom', '') <> 'true') as qk
    from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e) x on true $q$;

  -- the day x location x staff x payment mode x sale type rollup (a plain grouped view: no lines, no customer, fast on a phone)
  execute $q$
  create or replace view public.rpt_daily as
  select s.sale_date as day, s.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
    bm.brand_code, bm.brand_bn, bm.brand_en, s.created_staff as staff, s.pay_mode, s.sale_type,
    count(*) filter (where s.status = 'done') as bills,
    count(*) filter (where s.status = 'void') as void_bills,
    coalesce(sum(s.subtotal) filter (where s.status = 'done'), 0) as gross,
    coalesce(sum(s.discount) filter (where s.status = 'done'), 0) as discount,
    coalesce(sum(s.total) filter (where s.status = 'done'), 0) as net,
    coalesce(sum(s.paid) filter (where s.status = 'done'), 0) as paid,
    coalesce(sum(s.due_amount) filter (where s.status = 'done'), 0) as due,
    count(*) filter (where s.status = 'done' and s.quick) as quick_bills,
    coalesce(sum(s.total) filter (where s.status = 'void'), 0) as void_amt,
    count(*) filter (where s.status = 'done' and s.discount > 0) as disc_bills
  from public.sales s
  join public.locations lo on lo.id = s.location_id
  left join public.report_brand_map bm on bm.location_id = s.location_id
  group by s.sale_date, s.location_id, lo.name_bn, lo.name_en, bm.brand_code, bm.brand_bn, bm.brand_en, s.created_staff, s.pay_mode, s.sale_type $q$;

  -- one row per sale LINE. The bill discount is spread over the lines in proportion to their amount (net). NO cost columns here.
  execute $q$
  create or replace view public.sales_fact as
  select s.id as sale_id, e.ord::int as line_no, s.receipt, s.sale_date as day, s.sold_at,
    extract(hour from s.sold_at at time zone 'Asia/Dhaka')::int as hour,
    extract(dow from s.sale_date)::int as dow,
    s.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
    bm.brand_code, bm.brand_bn, bm.brand_en,
    s.created_staff as staff, s.status, s.sale_type, s.pay_mode, s.customer_id,
    it.id as item_id, it.code as item_code,
    coalesce(it.name_bn, nullif(e.v->>'name', ''), 'Quick sale') as item_name,
    coalesce(it.name_en, it.name_bn, nullif(e.v->>'name', ''), 'Quick sale') as item_name_en,
    it.category, coalesce(it.unit, nullif(e.v->>'unit', '')) as unit,
    case when it.id is not null then 'listed' when e.v->>'custom' = 'true' then 'unlisted' else 'quick' end as line_kind,
    q.qty, q.price, q.amount as gross,
    q.amount * case when s.subtotal > 0 then s.total / s.subtotal else 1 end as net,
    q.amount - q.amount * case when s.subtotal > 0 then s.total / s.subtotal else 1 end as disc,
    (e.v->>'override' = 'true') as override,
    s.total as sale_total, s.discount as sale_discount,
    $q$ || dk || $q$ as discount_kind, $q$ || dp || $q$ as discount_pct
  from public.sales s
  join public.locations lo on lo.id = s.location_id
  left join public.report_brand_map bm on bm.location_id = s.location_id
  cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) with ordinality as e(v, ord)
  cross join lateral (select
      case when e.v->>'item_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (e.v->>'item_id')::uuid end as iid,
      case when e.v->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v->>'qty')::numeric end as qty,
      case when e.v->>'price' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v->>'price')::numeric end as price,
      case when e.v->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v->>'amount')::numeric else 0 end as amount) q
  left join public.items it on it.id = q.iid $q$;
end $v$;

-- one row per payment (sale payments and later collections)
create or replace view public.rpt_pay as
select p.id as pay_id, p.sale_id, (p.paid_at at time zone 'Asia/Dhaka')::date as day, p.paid_at,
  extract(hour from p.paid_at at time zone 'Asia/Dhaka')::int as hour,
  extract(dow from (p.paid_at at time zone 'Asia/Dhaka')::date)::int as dow,
  p.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
  bm.brand_code, bm.brand_bn, bm.brand_en,
  p.created_staff as staff, p.kind, p.mode, p.wallet, p.ref, p.amount, p.voided,
  p.customer_id, cu.name as customer_name, cu.mobile
from public.sale_payments p
join public.locations lo on lo.id = p.location_id
left join public.report_brand_map bm on bm.location_id = p.location_id
left join public.customers cu on cu.id = p.customer_id;

revoke all on public.rpt_bill, public.rpt_daily, public.sales_fact, public.rpt_pay from public, anon, authenticated;

-- ---------- permission helpers ----------
create or replace function public.rpt_access(p_group text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_grant('report_' || p_group));
$$;
-- cost: owner, ITEM_COST view, or (if the grants exist) the grant view_cost
create or replace function public.rpt_cost_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view')
    or (exists (select 1 from public.grant_defs where grant_code = 'view_cost') and public.can_grant('view_cost')));
$$;
create or replace function public.rpt_mobile_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('POS', 'approve')
    or (exists (select 1 from public.grant_defs where grant_code = 'view_customer_mobile') and public.can_grant('view_customer_mobile')));
$$;

-- ---------- small parsers: bad input raises 'bad_filter' and never reaches SQL as text ----------
create or replace function public.rpt_arr_text(j jsonb) returns text[]
language plpgsql immutable set search_path = public as $$
declare a text[];
begin
  if j is null or jsonb_typeof(j) = 'null' then return null; end if;
  if jsonb_typeof(j) = 'array' then
    if jsonb_array_length(j) > 200 then raise exception 'bad_filter'; end if;
    select coalesce(array_agg(e), '{}') into a from jsonb_array_elements_text(j) e;
  else a := array[j #>> '{}']; end if;
  if exists (select 1 from unnest(a) x where length(x) > 100) then raise exception 'bad_filter'; end if;
  if cardinality(a) = 0 then return null; end if;
  return a;
end $$;
create or replace function public.rpt_arr_int(j jsonb) returns int[]
language plpgsql immutable set search_path = public as $$
declare a text[] := public.rpt_arr_text(j);
begin
  if a is null then return null; end if;
  if exists (select 1 from unnest(a) x where x is null or x !~ '^[0-9]{1,9}$') then raise exception 'bad_filter'; end if;
  return a::int[];
end $$;
create or replace function public.rpt_arr_uuid(j jsonb) returns uuid[]
language plpgsql immutable set search_path = public as $$
declare a text[] := public.rpt_arr_text(j);
begin
  if a is null then return null; end if;
  if exists (select 1 from unnest(a) x where x is null or x !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'bad_filter'; end if;
  return a::uuid[];
end $$;
create or replace function public.rpt_num(j jsonb) returns numeric
language plpgsql immutable set search_path = public as $$
declare t text;
begin
  if j is null or jsonb_typeof(j) = 'null' then return null; end if;
  t := j #>> '{}';
  if t !~ '^[0-9]{1,12}(\.[0-9]{1,4})?$' then raise exception 'bad_filter'; end if;
  return t::numeric;
end $$;
create or replace function public.rpt_date(t text) returns date
language plpgsql immutable set search_path = public as $$
begin
  if t is null or btrim(t) = '' then return null; end if;
  if t !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_filter'; end if;
  return t::date;
exception when others then raise exception 'bad_filter';
end $$;

-- ---------- date presets (null when the needed rule is missing: nothing is invented) ----------
create or replace function public.report_presets() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t date := (now() at time zone 'Asia/Dhaka')::date; ws numeric := public.rule_num('week_start_dow'); fm numeric := public.rule_num('fiscal_year_start_month');
  wk date; fs date; ms date := date_trunc('month', t)::date;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if ws is not null and ws between 0 and 6 and ws = trunc(ws) then wk := t - ((extract(dow from t)::int - ws::int + 7) % 7); end if;
  if fm is not null and fm between 1 and 12 and fm = trunc(fm) then
    fs := make_date(extract(year from t)::int - case when extract(month from t) < fm then 1 else 0 end, fm::int, 1); end if;
  return jsonb_build_object(
    'today', jsonb_build_object('from', t, 'to', t),
    'yesterday', jsonb_build_object('from', t - 1, 'to', t - 1),
    'last_7', jsonb_build_object('from', t - 6, 'to', t),
    'last_30', jsonb_build_object('from', t - 29, 'to', t),
    'this_month', jsonb_build_object('from', ms, 'to', t),
    'last_month', jsonb_build_object('from', (ms - interval '1 month')::date, 'to', ms - 1),
    'this_week', case when wk is not null then jsonb_build_object('from', wk, 'to', t) end,
    'last_week', case when wk is not null then jsonb_build_object('from', wk - 7, 'to', wk - 1) end,
    'this_fy', case when fs is not null then jsonb_build_object('from', fs, 'to', t) end,
    'last_fy', case when fs is not null then jsonb_build_object('from', (fs - interval '1 year')::date, 'to', fs - 1) end);
end $$;

-- ============================================================
-- THE WHITELIST CATALOGUE. Every expression that can ever appear in a report query is written here, once.
-- Tokens: {T} table alias, {D} the (possibly shifted) day, {WS} week start, {FYM} fiscal start month, {MOBOK} mobile visible.
-- ============================================================
create or replace function public.rpt_dims(p_src text) returns jsonb
language sql immutable set search_path = public as $j$
  select $c${
   "day":{"time":1,"daily":1,"cols":[["day","{D}","দিন","Day","date"]]},
   "week":{"time":1,"daily":1,"need":"ws","cols":[["week","({D} - ((extract(dow from {D})::int - {WS} + 7) % 7))::date","সপ্তাহ (শুরুর দিন)","Week starting","date"]]},
   "month":{"time":1,"daily":1,"cols":[["month","date_trunc('month', {D})::date","মাস","Month","date"]]},
   "fy":{"time":1,"daily":1,"need":"fy","cols":[["fiscal_year","(extract(year from {D})::int - case when extract(month from {D}) < {FYM} then 1 else 0 end)","অর্থবছর (শুরুর সাল)","Fiscal year (start year)","int"]]},
   "location":{"daily":1,"cols":[["location_id","{T}.location_id","","","id"],["location_bn","{T}.location_bn","লোকেশন","Location","text"],["location_en","{T}.location_en","Location (EN)","Location (EN)","text"]]},
   "brand":{"daily":1,"cols":[["brand_code","coalesce({T}.brand_code, 'none')","","","id"],["brand_bn","coalesce({T}.brand_bn, 'ব্র্যান্ড ঠিক করা নেই')","ব্র্যান্ড","Brand","text"],["brand_en","coalesce({T}.brand_en, 'No brand set')","Brand (EN)","Brand (EN)","text"]]},
   "staff":{"daily":1,"cols":[["staff","coalesce({T}.staff, '-')","কর্মী","Staff","text"]]},
   "hour":{"cols":[["hour","{T}.hour","ঘণ্টা","Hour","int"]]},
   "weekday":{"cols":[["dow","{T}.dow","বার (০=রবি)","Weekday (0=Sun)","int"]]}
  }$c$::jsonb || case p_src
   when 'bill' then $c${
   "pay_mode":{"daily":1,"cols":[["pay_mode","{T}.pay_mode","পেমেন্ট ধরন","Payment","text"]]},
   "sale_type":{"daily":1,"cols":[["sale_type","{T}.sale_type","খুচরা/পাইকারি","Retail/Wholesale","text"]]},
   "customer":{"cols":[["customer_id","coalesce({T}.customer_id::text, 'none')","","","id"],["customer_name","coalesce({T}.customer_name, '-')","গ্রাহক","Customer","text"],["mobile","case when {MOBOK} then {T}.mobile else left({T}.mobile, 3) || '****' || right({T}.mobile, 2) end","মোবাইল","Mobile","text"]]},
   "void_staff":{"cols":[["void_staff","coalesce({T}.void_staff, '-')","বাতিল করেছে","Voided by","text"]]},
   "void_reason":{"cols":[["void_reason","coalesce({T}.void_note, '-')","বাতিলের কারণ","Void reason","text"]]},
   "discount_kind":{"cols":[["discount_kind","coalesce({T}.discount_kind, 'n/a')","ছাড়ের ধরন","Discount kind","text"]]}
  }$c$::jsonb
   when 'line' then $c${
   "pay_mode":{"cols":[["pay_mode","{T}.pay_mode","পেমেন্ট ধরন","Payment","text"]]},
   "sale_type":{"cols":[["sale_type","{T}.sale_type","খুচরা/পাইকারি","Retail/Wholesale","text"]]},
   "item":{"cols":[["item_id","coalesce({T}.item_id::text, 'none')","","","id"],["item_code","coalesce({T}.item_code, '-')","কোড","Code","text"],["item_name","{T}.item_name","আইটেম","Item","text"],["item_name_en","{T}.item_name_en","Item (EN)","Item (EN)","text"]]},
   "category":{"cols":[["category","coalesce({T}.category, '(none)')","ক্যাটাগরি","Category","text"]]},
   "line_kind":{"cols":[["line_kind","{T}.line_kind","লাইনের ধরন","Line kind","text"]]},
   "discount_kind":{"cols":[["discount_kind","coalesce({T}.discount_kind, 'n/a')","ছাড়ের ধরন","Discount kind","text"]]}
  }$c$::jsonb
   else $c${
   "mode":{"cols":[["mode","{T}.mode","মাধ্যম","Mode","text"]]},
   "wallet":{"cols":[["wallet","coalesce({T}.wallet, '-')","ওয়ালেট","Wallet","text"]]},
   "kind":{"cols":[["kind","{T}.kind","ধরন (সেল/আদায়)","Kind (sale/collection)","text"]]},
   "customer":{"cols":[["customer_id","coalesce({T}.customer_id::text, 'none')","","","id"],["customer_name","coalesce({T}.customer_name, '-')","গ্রাহক","Customer","text"],["mobile","case when {MOBOK} then {T}.mobile else left({T}.mobile, 3) || '****' || right({T}.mobile, 2) end","মোবাইল","Mobile","text"]]}
  }$c$::jsonb end;
$j$;

create or replace function public.rpt_meas(p_src text) returns jsonb
language sql immutable set search_path = public as $j$
  select case p_src
   when 'bill' then $c${
   "bills":{"expr":"coalesce(sum({T}.bills), 0)","bn":"বিল","en":"Bills","type":"int"},
   "gross":{"expr":"coalesce(sum({T}.gross), 0)","bn":"মোট (ছাড়ের আগে)","en":"Gross","type":"money"},
   "discount":{"expr":"coalesce(sum({T}.discount), 0)","bn":"ছাড়","en":"Discount","type":"money"},
   "net":{"expr":"coalesce(sum({T}.net), 0)","bn":"বিক্রি","en":"Sales","type":"money"},
   "discount_pct":{"expr":"round(100 * sum({T}.discount) / nullif(sum({T}.gross), 0), 2)","bn":"ছাড় %","en":"Discount %","type":"pct"},
   "avg_bill":{"expr":"round(sum({T}.net) / nullif(sum({T}.bills), 0), 2)","bn":"গড় বিল","en":"Avg bill","type":"money"},
   "paid":{"expr":"coalesce(sum({T}.paid), 0)","bn":"পরিশোধ","en":"Paid","type":"money"},
   "due":{"expr":"coalesce(sum({T}.due), 0)","bn":"বাকি","en":"Due","type":"money"},
   "void_bills":{"expr":"coalesce(sum({T}.void_bills), 0)","bn":"বাতিল বিল","en":"Voided bills","type":"int"},
   "void_amt":{"expr":"coalesce(sum({T}.void_amt), 0)","bn":"বাতিল টাকা","en":"Voided amount","type":"money"},
   "void_pct":{"expr":"round(100 * sum({T}.void_bills)::numeric / nullif(sum({T}.bills) + sum({T}.void_bills), 0), 2)","bn":"বাতিল %","en":"Void %","type":"pct"},
   "quick_bills":{"expr":"coalesce(sum({T}.quick_bills), 0)","bn":"কুইক বিল","en":"Quick bills","type":"int"},
   "disc_bills":{"expr":"coalesce(sum({T}.disc_bills), 0)","bn":"ছাড়ের বিল","en":"Bills with discount","type":"int"},
   "avg_discount":{"expr":"round(sum({T}.discount) / nullif(sum({T}.disc_bills), 0), 2)","bn":"ছাড়ের বিলে গড় ছাড়","en":"Avg discount per discounted bill","type":"money"},
   "share_pct":{"expr":"round(100 * sum({T}.net) / nullif(sum(sum({T}.net)) over (), 0), 2)","tot":"100","bn":"অংশ %","en":"Share %","type":"pct"},
   "override_lines":{"expr":"coalesce(sum({T}.override_lines), 0)","bn":"দাম বদলের লাইন","en":"Price-override lines","type":"int","daily":0},
   "custom_lines":{"expr":"coalesce(sum({T}.custom_lines), 0)","bn":"তালিকা-বহির্ভূত লাইন","en":"Unlisted lines","type":"int","daily":0},
   "customers":{"expr":"count(distinct {T}.customer_id)","bn":"গ্রাহক","en":"Customers","type":"int","daily":0},
   "first_sale":{"expr":"min({T}.day) filter (where {T}.bills = 1)","bn":"প্রথম কেনা","en":"First purchase","type":"date","daily":0},
   "last_sale":{"expr":"max({T}.day) filter (where {T}.bills = 1)","bn":"শেষ কেনা","en":"Last purchase","type":"date","daily":0}
  }$c$::jsonb
   when 'line' then $c${
   "qty":{"expr":"coalesce(round(sum({T}.qty), 3), 0)","bn":"পরিমাণ","en":"Qty","type":"num"},
   "lines":{"expr":"count(*)","bn":"লাইন","en":"Lines","type":"int"},
   "bills":{"expr":"count(distinct {T}.sale_id)","bn":"বিল","en":"Bills","type":"int"},
   "gross":{"expr":"coalesce(round(sum({T}.gross), 2), 0)","bn":"মোট (ছাড়ের আগে)","en":"Gross","type":"money"},
   "disc":{"expr":"coalesce(round(sum({T}.disc), 2), 0)","bn":"ছাড় (ভাগ করা)","en":"Discount (allocated)","type":"money"},
   "net":{"expr":"coalesce(round(sum({T}.net), 2), 0)","bn":"বিক্রি","en":"Sales","type":"money"},
   "avg_price":{"expr":"round(sum({T}.gross) / nullif(sum({T}.qty), 0), 2)","bn":"গড় দাম","en":"Avg price","type":"money"},
   "share_pct":{"expr":"round(100 * sum({T}.net) / nullif(sum(sum({T}.net)) over (), 0), 2)","tot":"100","bn":"অংশ %","en":"Share %","type":"pct"},
   "override_lines":{"expr":"count(*) filter (where {T}.override)","bn":"দাম বদলের লাইন","en":"Price-override lines","type":"int"},
   "cogs":{"expr":"round(sum({T}.qty * c.cost_price) filter (where c.cost_price is not null), 2)","bn":"পণ্যের খরচ","en":"Cost of goods","type":"money","cost":1},
   "costed_net":{"expr":"sum({T}.net) filter (where c.cost_price is not null)","bn":"খরচ জানা বিক্রি","en":"Sales with known cost","type":"money","cost":1},
   "net_all":{"expr":"sum({T}.net)","bn":"মোট বিক্রি","en":"All sales","type":"money","cost":1},
   "gp":{"expr":"round(sum({T}.net) filter (where c.cost_price is not null) - sum({T}.qty * c.cost_price) filter (where c.cost_price is not null), 2)","bn":"মোট লাভ (খরচ জানা অংশে)","en":"Gross profit (costed part)","type":"money","cost":1},
   "gp_pct":{"expr":"round(100 * (sum({T}.net) filter (where c.cost_price is not null) - sum({T}.qty * c.cost_price) filter (where c.cost_price is not null)) / nullif(sum({T}.net) filter (where c.cost_price is not null), 0), 2)","bn":"লাভ %","en":"GP %","type":"pct","cost":1},
   "uncosted_pct":{"expr":"round(100 * (sum({T}.net) - coalesce(sum({T}.net) filter (where c.cost_price is not null), 0)) / nullif(sum({T}.net), 0), 2)","bn":"খরচ অজানা বিক্রি %","en":"Uncosted sales %","type":"pct","cost":1}
  }$c$::jsonb
   else $c${
   "payments":{"expr":"count(*)","bn":"পেমেন্ট","en":"Payments","type":"int"},
   "amount":{"expr":"coalesce(sum({T}.amount), 0)","bn":"টাকা","en":"Amount","type":"money"},
   "sale_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.kind = 'sale'), 0)","bn":"সেলের সময়ে","en":"At sale","type":"money"},
   "collection_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.kind = 'collection'), 0)","bn":"বাকি আদায়","en":"Collections","type":"money"},
   "cash_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.mode = 'cash'), 0)","bn":"ক্যাশ","en":"Cash","type":"money"},
   "mobile_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.mode = 'mobile'), 0)","bn":"মোবাইল","en":"Mobile money","type":"money"},
   "card_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.mode = 'card'), 0)","bn":"কার্ড","en":"Card","type":"money"},
   "missing_ref":{"expr":"count(*) filter (where {T}.mode = 'mobile' and nullif(btrim({T}.ref), '') is null)","bn":"রেফারেন্স ছাড়া","en":"Without reference","type":"int"},
   "dup_refs":{"expr":"count(nullif(btrim({T}.ref), '')) - count(distinct nullif(btrim({T}.ref), ''))","bn":"ডুপ্লিকেট রেফারেন্স","en":"Duplicate references","type":"int"},
   "share_pct":{"expr":"round(100 * sum({T}.amount) / nullif(sum(sum({T}.amount)) over (), 0), 2)","tot":"100","bn":"অংশ %","en":"Share %","type":"pct"}
  }$c$::jsonb end;
$j$;

-- the reports. kind agg = grouped by whitelisted dims; raw = fixed query. group = access group (grant report_<group>).
create or replace function public.rpt_def(p_key text) returns jsonb
language sql immutable set search_path = public as $j$
  select ($c${
   "sales_summary":{"group":"sales","kind":"agg","src":"bill","bn":"বিক্রির সারসংক্ষেপ","en":"Sales summary","mix":"Sales সারসংক্ষেপ",
     "dims":["day","week","month","fy","location","brand","staff","pay_mode","sale_type"],"gdef":"",
     "measures":["bills","gross","discount","discount_pct","net","avg_bill","paid","due","void_bills","void_amt"],"sort":"net:desc","cmp":1,"cost_join":1},
   "sales_trend":{"group":"sales","kind":"agg","src":"bill","bn":"বিক্রির ধারা","en":"Sales trend","mix":"Sales এর ধারা",
     "dims":["day","week","month","fy","location","brand","staff"],"gdef":"day",
     "measures":["bills","net","avg_bill","discount","void_bills"],"sort":"@dim","cmp":1},
   "sales_combined":{"group":"sales","kind":"agg","src":"bill","bn":"একত্রিত দোকান/ব্র্যান্ড-ওয়াইজ","en":"Combined by shop / brand","mix":"একত্রিত দোকান/Brand-wise",
     "dims":["location","brand"],"gdef":"location",
     "measures":["bills","gross","discount","net","avg_bill","share_pct","paid","due","void_amt"],"sort":"net:desc","cmp":1,"cost_join":1},
   "item_sales":{"group":"sales","kind":"agg","src":"line","bn":"আইটেম-ওয়াইজ বিক্রি","en":"Item-wise sales","mix":"Item-wise বিক্রি",
     "dims":["item","category","day","week","month","fy","location","brand","staff","sale_type"],"gdef":"item",
     "measures":["qty","bills","gross","disc","net","avg_price","share_pct","override_lines","cogs","gp","gp_pct","uncosted_pct"],"sort":"net:desc","cmp":1,"base":"{T}.status = 'done'"},
   "category_sales":{"group":"sales","kind":"agg","src":"line","bn":"ক্যাটাগরি-ওয়াইজ বিক্রি","en":"Category-wise sales","mix":"Category-wise বিক্রি",
     "dims":["category","item","day","week","month","fy","location","brand","staff","sale_type"],"gdef":"category",
     "measures":["qty","bills","gross","disc","net","share_pct","cogs","gp","gp_pct","uncosted_pct"],"sort":"net:desc","cmp":1,"base":"{T}.status = 'done'"},
   "receipt_register":{"group":"sales","kind":"raw","bn":"রসিদ তালিকা","en":"Receipt register","mix":"Receipt তালিকা","nocompare":1,
     "allow":["locations","brands","staff","modes","sale_type","customer","min_amount","max_amount","status","search"],"sort":"sold_at:desc",
     "columns":[["sale_id","","","id"],["receipt","রসিদ নং","Receipt #","int"],["day","দিন","Day","date"],["time","সময়","Time","text"],["sold_at","","","id"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["staff","কর্মী","Staff","text"],["sale_type","খুচরা/পাইকারি","Retail/Wholesale","text"],["pay_mode","পেমেন্ট","Payment","text"],["status","অবস্থা","Status","text"],["customer_name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["subtotal","মোট","Subtotal","money"],["discount","ছাড়","Discount","money"],["total","পরিশোধযোগ্য","Total","money"],["paid","পরিশোধ","Paid","money"],["due","বাকি","Due","money"]]},
   "hour_weekday":{"group":"sales","kind":"agg","src":"bill","bn":"সময় ও বার অনুযায়ী","en":"Hour and weekday","mix":"ঘণ্টা ও বার অনুযায়ী",
     "dims":["hour","weekday","location","brand"],"gdef":"hour","measures":["bills","net","avg_bill","share_pct"],"sort":"@dim","cmp":1},
   "retail_wholesale":{"group":"sales","kind":"agg","src":"bill","bn":"খুচরা বনাম পাইকারি","en":"Retail vs wholesale","mix":"খুচরা vs পাইকারি",
     "dims":["sale_type","location","brand","day","week","month","fy","staff"],"gdef":"sale_type",
     "measures":["bills","gross","discount","net","avg_bill","share_pct","due"],"sort":"net:desc","cmp":1},
   "discounts":{"group":"sales","kind":"agg","src":"bill","bn":"ডিসকাউন্ট ও দাম বদল","en":"Discounts and price overrides","mix":"Discount ও দাম বদল","only_bill":1,
     "dims":["staff","location","brand","day","week","month","fy","discount_kind","sale_type"],"gdef":"staff",
     "measures":["bills","disc_bills","gross","discount","discount_pct","avg_discount","override_lines","net"],"sort":"discount:desc","cmp":1},
   "pos_day_close":{"group":"pos","kind":"raw","bn":"দিনশেষ রিপোর্ট (POS)","en":"POS day close","mix":"দিনশেষ (POS) report","nocompare":1,
     "allow":["locations","brands","staff"],"sort":"day:desc",
     "columns":[["day","দিন","Day","date"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["bills","বিল","Bills","int"],["net","বিক্রি","Sales","money"],["discount","ছাড়","Discount","money"],["void_bills","বাতিল বিল","Voided bills","int"],["void_amt","বাতিল টাকা","Voided amount","money"],["due_created","নতুন বাকি","New due","money"],["cash_in","ক্যাশ (সেল)","Cash at sale","money"],["mobile_in","মোবাইল (সেল)","Mobile at sale","money"],["card_in","কার্ড (সেল)","Card at sale","money"],["cash_collections","ক্যাশ আদায়","Cash collections","money"],["mobile_collections","মোবাইল আদায়","Mobile collections","money"],["card_collections","কার্ড আদায়","Card collections","money"],["total_in","মোট জমা","Total received","money"],["expected_cash","ড্রয়ারে থাকার কথা (ক্যাশ)","Expected cash in drawer","money"]]},
   "voids":{"group":"pos","kind":"agg","src":"bill","bn":"বাতিল বিল","en":"Voids","mix":"বাতিল Bill",
     "dims":["staff","void_staff","void_reason","location","brand","day","week","month","fy"],"gdef":"staff",
     "measures":["void_bills","void_amt","bills","void_pct"],"sort":"void_amt:desc","cmp":1,"having":"sum({T}.void_bills) > 0"},
   "quick_unlisted":{"group":"pos","kind":"agg","src":"line","bn":"কুইক ও তালিকা-বহির্ভূত বিক্রি","en":"Quick and unlisted sales","mix":"Quick ও unlisted বিক্রি",
     "dims":["line_kind","item","staff","location","brand","day","week","month","fy"],"gdef":"line_kind",
     "measures":["lines","bills","qty","net","share_pct"],"sort":"net:desc","cmp":1,"base":"{T}.status = 'done' and {T}.line_kind <> 'listed'"},
   "payment_modes":{"group":"cash","kind":"agg","src":"pay","bn":"পেমেন্ট মাধ্যম অনুযায়ী","en":"By payment mode","mix":"Payment mode অনুযায়ী",
     "dims":["mode","wallet","kind","day","week","month","fy","location","brand","staff"],"gdef":"mode",
     "measures":["payments","sale_amount","collection_amount","amount","share_pct"],"sort":"amount:desc","cmp":1,"base":"not {T}.voided"},
   "wallet_recon":{"group":"cash","kind":"agg","src":"pay","bn":"ওয়ালেট/মোবাইল পেমেন্ট মিল","en":"Wallet reconciliation","mix":"Wallet মিল",
     "dims":["wallet","day","week","month","fy","location","brand","staff"],"gdef":"wallet",
     "measures":["payments","amount","missing_ref","dup_refs"],"sort":"amount:desc","cmp":1,"base":"not {T}.voided and {T}.mode = 'mobile'"},
   "collections":{"group":"cash","kind":"agg","src":"pay","bn":"বাকি আদায়","en":"Collections","mix":"বাকি আদায়",
     "dims":["day","week","month","fy","mode","wallet","staff","customer","location","brand"],"gdef":"day",
     "measures":["payments","amount","cash_amount","mobile_amount","card_amount","share_pct"],"sort":"@dim","cmp":1,"base":"not {T}.voided and {T}.kind = 'collection'"},
   "best_customers":{"group":"customers","kind":"agg","src":"bill","bn":"সেরা গ্রাহক","en":"Best customers","mix":"সেরা Customer","only_bill":1,
     "dims":["customer"],"gdef":"customer","measures":["bills","net","avg_bill","discount","due","first_sale","last_sale"],"sort":"net:desc","cmp":1,"base":"{T}.customer_id is not null"},
   "customer_dues":{"group":"customers","kind":"raw","bn":"গ্রাহকের কাছে পাওনা","en":"Due from customers","mix":"Customer এর কাছে পাওনা","nocompare":1,"nodate":1,
     "allow":["customer","search"],"sort":"balance:desc",
     "columns":[["customer_id","","","id"],["name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["type","ধরন","Type","text"],["credit_limit","বাকির সীমা","Credit limit","money"],["balance","বাকি","Due","money"],["oldest_due","সবচেয়ে পুরনো বাকির তারিখ","Oldest due since","date"],["days_old","কত দিনের পুরনো","Days old","int"]]},
   "receivable_aging":{"group":"customers","kind":"raw","bn":"বাকির বয়স","en":"Receivable aging","mix":"বাকির বয়স","nocompare":1,"nodate":1,
     "allow":["customer","search"],"sort":"balance:desc"},
   "credit_limit_use":{"group":"customers","kind":"raw","bn":"ক্রেডিট সীমা ব্যবহার","en":"Credit-limit use","mix":"Credit limit ব্যবহার","nocompare":1,"nodate":1,
     "allow":["customer","search"],"sort":"use_pct:desc",
     "columns":[["customer_id","","","id"],["name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["type","ধরন","Type","text"],["credit_limit","বাকির সীমা","Credit limit","money"],["balance","বাকি","Due","money"],["use_pct","সীমার % ব্যবহার","Limit used %","pct"],["status","অবস্থা","Status","text"]]}
  }$c$::jsonb) -> p_key;
$j$;

create or replace function public.rpt_keys() returns text[]
language sql immutable as $$ select array['sales_summary','sales_trend','sales_combined','item_sales','category_sales','receipt_register','hour_weekday','retail_wholesale','discounts',
  'pos_day_close','voids','quick_unlisted','payment_modes','wallet_recon','collections','best_customers','customer_dues','receivable_aging','credit_limit_use']; $$;

-- which filters each source can apply
create or replace function public.rpt_filters_for(p_src text) returns text[]
language sql immutable as $$
  select case p_src
    when 'bill' then array['locations','brands','staff','modes','sale_type','customer','min_amount','max_amount']
    when 'line' then array['locations','brands','staff','modes','sale_type','customer','min_amount','max_amount','items','categories']
    else array['locations','brands','staff','modes','customer','min_amount','max_amount'] end;
$$;

-- token replacement
create or replace function public.rpt_tok(p_expr text, p_al text, p_dexpr text, p_ws int, p_fym int, p_mobok boolean) returns text
language sql immutable as $$
  select replace(replace(replace(replace(replace(p_expr, '{D}', p_dexpr), '{T}', p_al), '{WS}', coalesce(p_ws, 1)::text), '{FYM}', coalesce(p_fym, 1)::text),
                 '{MOBOK}', case when p_mobok then 'true' else 'false' end);
$$;

-- WHERE clause from the filters. Values are type-checked and quoted with %L; keys are looked up, never pasted.
create or replace function public.rpt_where(p_src text, p_al text, p_flt jsonb, p_allowed int[], p_from date, p_to date, p_allow text[], p_mobok boolean default false) returns jsonb
language plpgsql stable set search_path = public as $$
declare w text[] := '{}'; ign text[] := '{}'; k text; locs int[]; eff int[]; tx text[]; ux uuid[]; n1 numeric; n2 numeric; nb boolean := false; v text; col text;
begin
  for k in select jsonb_object_keys(p_flt) loop
    if k in ('from', 'to', 'preset', 'compare_mode') then continue; end if;
    if jsonb_typeof(p_flt -> k) = 'null' then continue; end if;
    if not (k = any (p_allow)) then ign := ign || left(k, 40); end if;
  end loop;
  locs := public.rpt_arr_int(p_flt -> 'locations');
  eff := case when locs is null then p_allowed else array(select unnest(p_allowed) intersect select unnest(locs)) end;
  w := w || format('%s.location_id = any (%L::int[])', p_al, eff);
  if p_from is not null then w := w || format('%s.day between %L::date and %L::date', p_al, p_from, p_to); end if;
  if 'brands' = any (p_allow) then tx := public.rpt_arr_text(p_flt -> 'brands'); if tx is not null then w := w || format('%s.brand_code = any (%L::text[])', p_al, tx); end if; end if;
  if 'staff' = any (p_allow) then tx := public.rpt_arr_text(p_flt -> 'staff'); if tx is not null then w := w || format('%s.staff = any (%L::text[])', p_al, tx); end if; end if;
  if 'modes' = any (p_allow) then tx := public.rpt_arr_text(p_flt -> 'modes');
    if tx is not null then w := w || format('%s.%s = any (%L::text[])', p_al, case when p_src = 'pay' then 'mode' else 'pay_mode' end, tx); end if; end if;
  if 'sale_type' = any (p_allow) and p_src <> 'pay' then v := p_flt ->> 'sale_type';
    if v is not null then w := w || format('%s.sale_type = %L', p_al, v); end if; end if;
  if 'customer' = any (p_allow) then ux := public.rpt_arr_uuid(p_flt -> 'customer');
    if ux is not null then w := w || format('%s.customer_id = any (%L::uuid[])', p_al, ux); nb := true; end if; end if;
  if 'items' = any (p_allow) and p_src = 'line' then ux := public.rpt_arr_uuid(p_flt -> 'items'); if ux is not null then w := w || format('%s.item_id = any (%L::uuid[])', p_al, ux); end if; end if;
  if 'categories' = any (p_allow) and p_src = 'line' then tx := public.rpt_arr_text(p_flt -> 'categories'); if tx is not null then w := w || format('%s.category = any (%L::text[])', p_al, tx); end if; end if;
  if 'min_amount' = any (p_allow) then n1 := public.rpt_num(p_flt -> 'min_amount'); n2 := public.rpt_num(p_flt -> 'max_amount');
    col := case p_src when 'bill' then 'total' when 'line' then 'sale_total' else 'amount' end;
    if n1 is not null then w := w || format('%s.%s >= %L::numeric', p_al, col, n1); nb := true; end if;
    if n2 is not null then w := w || format('%s.%s <= %L::numeric', p_al, col, n2); nb := true; end if; end if;
  if 'status' = any (p_allow) and p_src = 'bill' then v := p_flt ->> 'status';
    if v is not null then
      if v not in ('done', 'void') then raise exception 'bad_filter'; end if;
      w := w || format('%s.status = %L', p_al, v); nb := true; end if; end if;
  if 'search' = any (p_allow) and p_src = 'bill' then v := btrim(p_flt ->> 'search');
    if v is not null and v <> '' then
      if length(v) > 60 then raise exception 'bad_filter'; end if;
      w := w || format('(%s.receipt::text = %L or position(lower(%L) in lower(coalesce(%s.customer_name, ''''))) > 0 %s)', p_al, v, v, p_al,
        case when p_mobok then format('or position(%L in coalesce(%s.mobile, '''')) > 0', v, p_al) else '' end);
      nb := true; end if; end if;
  return jsonb_build_object('w', array_to_string(w, ' and '), 'ignored', to_jsonb(ign), 'needs_bill', nb);
end $$;

-- SQL text of one grouped query (plus joins to item_costs when the cost measures are wanted)
create or replace function public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text,
  p_dexpr text, p_ws int, p_fym int, p_mobok boolean, p_nodim boolean, p_withcost boolean) returns text
language plpgsql stable set search_path = public as $$
declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
begin
  if not p_nodim then
    foreach g in array p_gl loop
      for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
        sel := sel || (public.rpt_tok(c ->> 1, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(c ->> 0));
        n := n + 1;
      end loop;
    end loop;
  end if;
  foreach mk in array p_mkeys loop
    ex := case when p_nodim and meas -> mk ? 'tot' then meas -> mk ->> 'tot' else meas -> mk ->> 'expr' end;
    sel := sel || (public.rpt_tok(ex, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(mk));
  end loop;
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al
    || case when p_withcost then ' left join public.item_costs c on c.item_id = ' || p_al || '.item_id' else '' end
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');
  if n > 0 and not p_nodim then sql := sql || ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i); end if;
  if p_having is not null and not p_nodim then sql := sql || ' having ' || public.rpt_tok(p_having, p_al, p_dexpr, p_ws, p_fym, p_mobok); end if;
  return sql;
end $$;

-- builds the rows query and the totals query of an agg report for one period
create or replace function public.rpt_agg_build(p_def jsonb, p_gl text[], p_mkeys text[], p_flt jsonb, p_allowed int[], p_from date, p_to date,
  p_dexpr text, p_ws int, p_fym int, p_mobok boolean, p_costok boolean) returns jsonb
language plpgsql stable set search_path = public as $$
declare src text := p_def ->> 'src'; al text := case src when 'bill' then 'b' when 'line' then 'f' else 'p' end;
  dims jsonb := public.rpt_dims(src); g text; c jsonb; needb boolean := coalesce((p_def ->> 'only_bill')::int = 1, false);
  wj jsonb; wl jsonb; rel text; nodim boolean := cardinality(p_gl) = 0; mk text; meas jsonb := public.rpt_meas(src);
  t text; tot text; ts text; tj text; conds text[] := '{}'; cj text; lw text; ign jsonb;
  extra text := ', cq.cogs, round(cq.costed_net - cq.cogs, 2) as gp, round(100 * (cq.costed_net - cq.cogs) / nullif(cq.costed_net, 0), 2) as gp_pct, round(100 * (cq.net_all - cq.costed_net) / nullif(cq.net_all, 0), 2) as uncosted_pct';
begin
  wj := public.rpt_where(src, al, p_flt, p_allowed, p_from, p_to, coalesce((select array_agg(x) from jsonb_array_elements_text(p_def -> 'allow') x), public.rpt_filters_for(src)), p_mobok);
  ign := wj -> 'ignored';
  if src = 'bill' then
    foreach g in array p_gl loop if coalesce((dims -> g ->> 'daily')::int, 0) = 0 then needb := true; end if; end loop;
    foreach mk in array p_mkeys loop if coalesce((meas -> mk ->> 'daily')::int, 1) = 0 then needb := true; end if; end loop;
    if (wj ->> 'needs_bill')::boolean then needb := true; end if;
    rel := case when needb then 'public.rpt_bill' else 'public.rpt_daily' end;
  else rel := case src when 'line' then 'public.sales_fact' else 'public.rpt_pay' end; end if;
  t := public.rpt_agg_sql(src, rel, al, p_gl, p_mkeys, wj ->> 'w', p_def ->> 'base', p_def ->> 'having', p_dexpr, p_ws, p_fym, p_mobok, nodim, src = 'line' and p_costok);
  tot := public.rpt_agg_sql(src, rel, al, p_gl, p_mkeys, wj ->> 'w', p_def ->> 'base', null, p_dexpr, p_ws, p_fym, p_mobok, true, src = 'line' and p_costok);
  if p_costok and coalesce((p_def ->> 'cost_join')::int, 0) = 1 then
    wl := public.rpt_where('line', 'f', p_flt, p_allowed, p_from, p_to, array['locations','brands','staff','modes','sale_type','customer','min_amount','max_amount'], p_mobok);
    lw := wl ->> 'w';
    ts := public.rpt_agg_sql('line', 'public.sales_fact', 'f', p_gl, array['cogs','costed_net','net_all'], lw, '{T}.status = ''done''', null, p_dexpr, p_ws, p_fym, p_mobok, nodim, true);
    tj := public.rpt_agg_sql('line', 'public.sales_fact', 'f', p_gl, array['cogs','costed_net','net_all'], lw, '{T}.status = ''done''', null, p_dexpr, p_ws, p_fym, p_mobok, true, true);
    if not nodim then
      foreach g in array p_gl loop
        for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
          conds := conds || format('bq.%I is not distinct from cq.%I', c ->> 0, c ->> 0);
        end loop;
      end loop;
    end if;
    cj := coalesce(array_to_string(conds, ' and '), 'true'); if cj = '' then cj := 'true'; end if;
    t := format('select bq.*%s from (%s) bq left join (%s) cq on %s', extra, t, ts, cj);
    tot := format('select bq.*%s from (%s) bq cross join (%s) cq', extra, tot, tj);
  end if;
  return jsonb_build_object('t', t, 'tot', tot, 'ignored', ign);
end $$;

-- ============================================================
-- raw (non-grouped) reports: fixed SQL, only validated literals are inserted
-- ============================================================
create or replace function public.rpt_mobx(p_col text, p_ok boolean) returns text
language sql immutable as $$
  select case when p_ok then p_col else 'left(' || p_col || ', 3) || ''****'' || right(' || p_col || ', 2)' end;
$$;

create or replace function public.rpt_raw(p_key text, p_flt jsonb, p_allowed int[], p_from date, p_to date, p_mobok boolean, p_buckets int[], p_near numeric, p_today date) returns jsonb
language plpgsql stable set search_path = public as $$
declare def jsonb := public.rpt_def(p_key); al text[]; wj jsonb; wb text; wp text; sql text; tot text; cols jsonb; ign jsonb := '[]'::jsonb; notes jsonb := '[]'::jsonb;
  ux uuid[]; srch text; cfilter text := ''; alist text; i int; b text[] := '{}'; cond text; lo int; hi int; clist jsonb;
begin
  al := array(select jsonb_array_elements_text(def -> 'allow'));
  if p_key = 'receipt_register' then
    wj := public.rpt_where('bill', 'b', p_flt, p_allowed, p_from, p_to, al, p_mobok); wb := wj ->> 'w'; ign := wj -> 'ignored';
    sql := format($f$select b.sale_id, b.receipt, b.day, to_char(b.sold_at at time zone 'Asia/Dhaka', 'HH24:MI') as time, b.sold_at, b.location_id, b.location_bn, b.location_en,
      b.staff, b.sale_type, b.pay_mode, b.status, b.customer_name, %s as mobile, b.subtotal, b.discount_raw as discount, b.total, b.paid_raw as paid, b.due_raw as due
      from public.rpt_bill b where %s$f$, public.rpt_mobx('b.mobile', p_mobok), wb);
    tot := $f$count(*) as receipts, count(*) filter (where status = 'void') as void_receipts, coalesce(sum(subtotal) filter (where status = 'done'), 0) as subtotal,
      coalesce(sum(discount) filter (where status = 'done'), 0) as discount, coalesce(sum(total) filter (where status = 'done'), 0) as total,
      coalesce(sum(paid) filter (where status = 'done'), 0) as paid, coalesce(sum(due) filter (where status = 'done'), 0) as due$f$;
  elsif p_key = 'pos_day_close' then
    wj := public.rpt_where('bill', 'b', p_flt, p_allowed, p_from, p_to, al, p_mobok); wb := wj ->> 'w'; ign := wj -> 'ignored';
    wj := public.rpt_where('pay', 'p', p_flt, p_allowed, p_from, p_to, al, p_mobok); wp := wj ->> 'w';
    sql := format($f$with bb as (select b.day, b.location_id, b.location_bn, b.location_en, sum(b.bills) as bills, sum(b.net) as net, sum(b.discount) as discount,
        sum(b.void_bills) as void_bills, sum(b.void_amt) as void_amt, sum(b.due) as due_created
        from public.rpt_daily b where %s group by 1, 2, 3, 4),
      pb as (select p.day, p.location_id, p.location_bn, p.location_en,
        coalesce(sum(p.amount) filter (where p.kind = 'sale' and p.mode = 'cash'), 0) as cash_in,
        coalesce(sum(p.amount) filter (where p.kind = 'sale' and p.mode = 'mobile'), 0) as mobile_in,
        coalesce(sum(p.amount) filter (where p.kind = 'sale' and p.mode = 'card'), 0) as card_in,
        coalesce(sum(p.amount) filter (where p.kind = 'collection' and p.mode = 'cash'), 0) as cash_collections,
        coalesce(sum(p.amount) filter (where p.kind = 'collection' and p.mode = 'mobile'), 0) as mobile_collections,
        coalesce(sum(p.amount) filter (where p.kind = 'collection' and p.mode = 'card'), 0) as card_collections
        from public.rpt_pay p where not p.voided and %s group by 1, 2, 3, 4)
      select coalesce(bb.day, pb.day) as day, coalesce(bb.location_id, pb.location_id) as location_id, coalesce(bb.location_bn, pb.location_bn) as location_bn,
        coalesce(bb.location_en, pb.location_en) as location_en, coalesce(bb.bills, 0) as bills, coalesce(bb.net, 0) as net, coalesce(bb.discount, 0) as discount,
        coalesce(bb.void_bills, 0) as void_bills, coalesce(bb.void_amt, 0) as void_amt, coalesce(bb.due_created, 0) as due_created,
        coalesce(pb.cash_in, 0) as cash_in, coalesce(pb.mobile_in, 0) as mobile_in, coalesce(pb.card_in, 0) as card_in,
        coalesce(pb.cash_collections, 0) as cash_collections, coalesce(pb.mobile_collections, 0) as mobile_collections, coalesce(pb.card_collections, 0) as card_collections,
        coalesce(pb.cash_in + pb.mobile_in + pb.card_in + pb.cash_collections + pb.mobile_collections + pb.card_collections, 0) as total_in,
        coalesce(pb.cash_in + pb.cash_collections, 0) as expected_cash
      from bb full join pb on pb.day = bb.day and pb.location_id = bb.location_id$f$, wb, wp);
    tot := $f$sum(bills) as bills, sum(net) as net, sum(discount) as discount, sum(void_bills) as void_bills, sum(void_amt) as void_amt, sum(due_created) as due_created,
      sum(cash_in) as cash_in, sum(mobile_in) as mobile_in, sum(card_in) as card_in, sum(cash_collections) as cash_collections, sum(mobile_collections) as mobile_collections,
      sum(card_collections) as card_collections, sum(total_in) as total_in, sum(expected_cash) as expected_cash$f$;
  else
    -- customer reports: always all locations the caller may see; only customer / search filters apply
    ux := public.rpt_arr_uuid(p_flt -> 'customer');
    if ux is not null then cfilter := cfilter || format(' and cu.id = any (%L::uuid[])', ux); end if;
    srch := btrim(p_flt ->> 'search');
    if srch is not null and srch <> '' then
      if length(srch) > 60 then raise exception 'bad_filter'; end if;
      cfilter := cfilter || format(' and (position(lower(%L) in lower(cu.name)) > 0 %s)', srch, case when p_mobok then format('or position(%L in cu.mobile) > 0', srch) else '' end);
    end if;
    ign := (select coalesce(jsonb_agg(left(k, 40)), '[]'::jsonb) from jsonb_object_keys(p_flt) k
            where k not in ('from', 'to', 'preset', 'compare_mode') and not (k = any (al)) and jsonb_typeof(p_flt -> k) <> 'null');
    alist := format('%L::int[]', p_allowed);
    if p_key = 'customer_dues' then
      sql := format($f$with s as (select x.id, x.customer_id, x.sale_date, x.sold_at,
          x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) as rem
          from public.sales x where x.status = 'done' and x.customer_id is not null and x.location_id = any (%s)),
        cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) as cr from s where s.rem > 0),
        c as (select p.customer_id, sum(p.amount) as coll from public.sale_payments p where p.kind = 'collection' and not p.voided and p.customer_id is not null and p.location_id = any (%s) group by 1),
        t as (select customer_id, sum(rem) as rem from s group by 1)
        select cu.id as customer_id, cu.name, %s as mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0) as balance, o.od as oldest_due, %L::date - o.od as days_old
        from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
        left join lateral (select min(k.sale_date) as od from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0)) o on true
        where t.rem - coalesce(c.coll, 0) > 0%s$f$, alist, alist, public.rpt_mobx('cu.mobile', p_mobok), p_today, cfilter);
      tot := 'count(*) as customers, sum(balance) as balance, count(*) filter (where credit_limit is null) as no_limit_set';
    elsif p_key = 'receivable_aging' then
      -- buckets come from the rule report_aging_buckets (no built-in values)
      if p_buckets is not null and cardinality(p_buckets) > 0 then
        for i in 1..cardinality(p_buckets) + 1 loop
          lo := case when i = 1 then 0 else p_buckets[i - 1] + 1 end;
          hi := case when i <= cardinality(p_buckets) then p_buckets[i] end;
          cond := case when hi is null then format('age >= %s', lo) else format('age between %s and %s', lo, hi) end;
          b := b || format('coalesce(sum(portion) filter (where %s), 0) as bucket_%s', cond, i);
        end loop;
      end if;
      sql := format($f$with s as (select x.id, x.customer_id, x.sale_date, x.sold_at,
          x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) as rem
          from public.sales x where x.status = 'done' and x.customer_id is not null and x.location_id = any (%s)),
        cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) as cr from s where s.rem > 0),
        c as (select p.customer_id, sum(p.amount) as coll from public.sale_payments p where p.kind = 'collection' and not p.voided and p.customer_id is not null and p.location_id = any (%s) group by 1),
        pt as (select k.customer_id, %L::date - k.sale_date as age, greatest(0, least(k.rem, k.cr - coalesce(c.coll, 0))) as portion from cum k left join c on c.customer_id = k.customer_id)
        select cu.id as customer_id, cu.name, %s as mobile, coalesce(sum(pt.portion), 0) as balance%s, max(pt.age) filter (where pt.portion > 0) as oldest_days
        from pt join public.customers cu on cu.id = pt.customer_id where true%s
        group by cu.id, cu.name, cu.mobile having coalesce(sum(pt.portion), 0) > 0$f$,
        alist, alist, p_today, public.rpt_mobx('cu.mobile', p_mobok), case when cardinality(b) > 0 then ', ' || array_to_string(b, ', ') else '' end, cfilter);
      clist := '[["customer_id","","","id"],["name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["balance","মোট বাকি","Total due","money"]]';
      if p_buckets is not null and cardinality(p_buckets) > 0 then
        for i in 1..cardinality(p_buckets) + 1 loop
          lo := case when i = 1 then 0 else p_buckets[i - 1] + 1 end; hi := case when i <= cardinality(p_buckets) then p_buckets[i] end;
          clist := clist || jsonb_build_array(jsonb_build_array('bucket_' || i, case when hi is null then lo || '+ দিন' else lo || '-' || hi || ' দিন' end,
                                                               case when hi is null then lo || '+ days' else lo || '-' || hi || ' days' end, 'money'));
        end loop;
        tot := 'count(*) as customers, sum(balance) as balance, ' || array_to_string(array(select format('sum(bucket_%s) as bucket_%s', gs.n, gs.n) from generate_series(1, cardinality(p_buckets) + 1) gs(n)), ', ');
      else
        tot := 'count(*) as customers, sum(balance) as balance';
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_aging_buckets', 'text_bn', 'বাকির বয়স ভাগ নিয়মে (report_aging_buckets) লেখা নেই', 'text_en', 'Aging buckets are not set in the rule report_aging_buckets'));
      end if;
      clist := clist || '[["oldest_days","সবচেয়ে পুরনো (দিন)","Oldest (days)","int"]]'::jsonb;
      cols := clist;
    elsif p_key = 'credit_limit_use' then
      sql := format($f$with sold as (select x.customer_id, sum(x.total) as v from public.sales x where x.status = 'done' and x.customer_id is not null and x.location_id = any (%s) group by 1),
        paid as (select p.customer_id, sum(p.amount) as v from public.sale_payments p where not p.voided and p.customer_id is not null and p.location_id = any (%s) group by 1),
        r as (select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, coalesce(sold.v, 0) - coalesce(paid.v, 0) as balance
          from public.customers cu left join sold on sold.customer_id = cu.id left join paid on paid.customer_id = cu.id where cu.active%s)
        select r.id as customer_id, r.name, %s as mobile, r.type, r.credit_limit, r.balance,
          case when r.credit_limit > 0 then round(100 * r.balance / r.credit_limit, 1) end as use_pct,
          case when r.credit_limit is null then 'no_limit' when r.balance > r.credit_limit then 'over'
               %s else 'ok' end as status
        from r where r.credit_limit is not null or r.balance > 0$f$, alist, alist, cfilter, public.rpt_mobx('r.mobile', p_mobok),
        case when p_near is not null then format('when r.credit_limit > 0 and 100 * r.balance / r.credit_limit >= %L::numeric then ''near''', p_near) else '' end);
      tot := $f$count(*) as customers, count(*) filter (where status = 'over') as over_limit, count(*) filter (where status = 'near') as near_limit,
        count(*) filter (where status = 'no_limit') as no_limit_set, sum(balance) as balance$f$;
      if p_near is null then notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_near_limit_pct', 'text_bn', '"সীমার কাছে" দেখাতে নিয়ম report_near_limit_pct লিখুন', 'text_en', 'Set the rule report_near_limit_pct to show a "near the limit" status')); end if;
    end if;
  end if;
  return jsonb_build_object('t', sql, 'tot', tot, 'cols', cols, 'ignored', coalesce(ign, '[]'::jsonb), 'notes', notes);
end $$;

-- ============================================================
-- the catalogue for the UI
-- ============================================================
create or replace function public.report_catalog() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k text; d jsonb; out_ jsonb := '[]'::jsonb; cost_ok boolean; dims jsonb; meas jsonb; src text; dl jsonb; ml jsonb; g text; mk text; fl text[]; ok boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  cost_ok := public.rpt_cost_ok();
  foreach k in array public.rpt_keys() loop
    d := public.rpt_def(k); src := d ->> 'src';
    ok := public.rpt_access(d ->> 'group');
    dl := '[]'::jsonb; ml := '[]'::jsonb;
    if d ->> 'kind' = 'agg' then
      dims := public.rpt_dims(src); meas := public.rpt_meas(src);
      for g in select jsonb_array_elements_text(d -> 'dims') loop
        dl := dl || jsonb_build_array(jsonb_build_object('key', g, 'time', coalesce((dims -> g ->> 'time')::int = 1, false),
              'label_bn', dims -> g -> 'cols' -> (case when jsonb_array_length(dims -> g -> 'cols') > 1 then 1 else 0 end) ->> 2,
              'label_en', dims -> g -> 'cols' -> (case when jsonb_array_length(dims -> g -> 'cols') > 1 then 1 else 0 end) ->> 3,
              'needs_rule', dims -> g ->> 'need'));
      end loop;
      for mk in select jsonb_array_elements_text(d -> 'measures') loop
        if cost_ok or coalesce((meas -> mk ->> 'cost')::int, 0) = 0 then
          ml := ml || jsonb_build_array(jsonb_build_object('key', mk, 'label_bn', meas -> mk ->> 'bn', 'label_en', meas -> mk ->> 'en', 'type', meas -> mk ->> 'type', 'cost', coalesce((meas -> mk ->> 'cost')::int, 0) = 1));
        end if;
      end loop;
      if cost_ok and coalesce((d ->> 'cost_join')::int, 0) = 1 then
        ml := ml || '[{"key":"cogs","label_bn":"পণ্যের খরচ","label_en":"Cost of goods","type":"money","cost":true},{"key":"gp","label_bn":"মোট লাভ (খরচ জানা অংশে)","label_en":"Gross profit (costed part)","type":"money","cost":true},{"key":"gp_pct","label_bn":"লাভ %","label_en":"GP %","type":"pct","cost":true},{"key":"uncosted_pct","label_bn":"খরচ অজানা বিক্রি %","label_en":"Uncosted sales %","type":"pct","cost":true}]'::jsonb;
      end if;
      fl := coalesce((select array_agg(x) from jsonb_array_elements_text(d -> 'allow') x), public.rpt_filters_for(src));
    else
      fl := coalesce((select array_agg(x) from jsonb_array_elements_text(d -> 'allow') x), '{}');
      ml := coalesce((select jsonb_agg(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3)) from jsonb_array_elements(d -> 'columns') c where c ->> 3 <> 'id'), '[]'::jsonb);
    end if;
    out_ := out_ || jsonb_build_array(jsonb_build_object('key', k, 'group', d ->> 'group', 'grant', 'report_' || (d ->> 'group'), 'allowed', ok,
      'kind', d ->> 'kind', 'name_bn', d ->> 'bn', 'name_en', d ->> 'en', 'name_mix', d ->> 'mix',
      'filters', to_jsonb(array['date'] || fl), 'dims', dl, 'default_group', nullif(d ->> 'gdef', ''), 'columns', ml,
      'compare', coalesce((d ->> 'cmp')::int = 1, false), 'needs_date', coalesce((d ->> 'nodate')::int, 0) = 0));
  end loop;
  return out_;
end $$;

-- ============================================================
-- report_run
-- ============================================================
create or replace function public.report_run(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null,
  p_page int default 1, p_compare boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public set statement_timeout = '8s' as $$
declare
  def jsonb; flt jsonb; notes jsonb := '[]'::jsonb; today date := (now() at time zone 'Asia/Dhaka')::date;
  cost_ok boolean; mob_ok boolean; allowed int[]; d1 date; d2 date; fm numeric; wsn numeric; fym int; ws int;
  pgsize int; pg int := greatest(coalesce(p_page, 1), 1); off int; lim int; cap constant int := 500;
  kind text; src text; dims jsonb; meas jsonb; gl text[] := '{}'; tok text; g text; mk text; mkeys text[] := '{}'; gtxt text;
  cols jsonb := '[]'::jsonb; allowkeys text[] := '{}'; sk text; sd text; sraw text; sparts text[]; ordr text; dsort text;
  b jsonb; t text; tot text; rows_ jsonb; totals_ jsonb; ngroups bigint := 0; cmp_ jsonb := null; ign jsonb; c jsonb; pr jsonb; preset text;
  cmode text; cf date; ct date; shiftlit text; shiftdays int; b2 jsonb; rows2 jsonb; tot2 jsonb; buckets int[]; bk text; near numeric; extra_cols jsonb := '[]'::jsonb;
  hm boolean; dn boolean := false; i int; x record; raw jsonb; nloc int; delta jsonb := '{}'::jsonb; k text; cu numeric; pv numeric; first_dim text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  def := public.rpt_def(p_key);
  if def is null then raise exception 'unknown_report'; end if;
  if not public.rpt_access(def ->> 'group') then raise exception 'not allowed'; end if;
  kind := def ->> 'kind'; src := def ->> 'src';
  flt := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
  cost_ok := public.rpt_cost_ok(); mob_ok := public.rpt_mobile_ok();
  allowed := coalesce((select array_agg(l.id) from public.locations l where public.can_loc(l.id)), '{}');
  if cardinality(allowed) = 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_location', 'text_en', 'No location is open to you')); end if;
  select count(*) into nloc from public.locations;
  if cardinality(allowed) < nloc then notes := notes || jsonb_build_array(jsonb_build_object('code', 'location_scope', 'text_en', 'Only your locations are included', 'text_bn', 'শুধু আপনার লোকেশনের হিসাব')); end if;
  fm := public.rule_num('fiscal_year_start_month'); fym := case when fm between 1 and 12 and fm = trunc(fm) then fm::int end;
  wsn := public.rule_num('week_start_dow'); ws := case when wsn between 0 and 6 and wsn = trunc(wsn) then wsn::int end;
  pgsize := least(greatest(coalesce(public.rule_num('report_page_size'), 50), 10), 200)::int;
  off := (pg - 1) * pgsize; lim := greatest(least(pgsize, cap - off), 0);

  -- period
  if coalesce((def ->> 'nodate')::int, 0) = 0 then
    preset := flt ->> 'preset';
    if preset is not null then
      pr := public.report_presets() -> preset;
      if pr is null or jsonb_typeof(pr) = 'null' then
        return jsonb_build_object('report', p_key, 'columns', '[]'::jsonb, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
          'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', 0, 'cap', cap),
          'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', left(preset, 30), 'text_en', 'This date preset needs a rule that is not set (fiscal year start / week start) or the preset name is unknown',
            'text_bn', 'এই তারিখের প্রিসেটের জন্য দরকারি নিয়ম সেট করা নেই (অর্থবছর শুরু / সপ্তাহ শুরু) বা প্রিসেটের নাম ভুল')));
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

  -- ---------------- grouped reports ----------------
  if kind = 'agg' then
    dims := public.rpt_dims(src); meas := public.rpt_meas(src);
    gtxt := case when p_group is null or btrim(p_group) = '' then null else lower(btrim(p_group)) end;
    if gtxt is null then gl := coalesce(string_to_array(nullif(def ->> 'gdef', ''), ','), '{}');
    elsif gtxt in ('none', 'total', '-') then gl := '{}';
    else
      foreach tok in array string_to_array(gtxt, ',') loop
        tok := btrim(tok);
        if tok = '' then continue; end if;
        if (def -> 'dims') @> to_jsonb(tok) and not (tok = any (gl)) and cardinality(gl) < 3 then gl := gl || tok;
        else notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(tok, 30))); end if;
      end loop;
      if cardinality(gl) = 0 then gl := coalesce(string_to_array(nullif(def ->> 'gdef', ''), ','), '{}'); end if;
    end if;
    -- dims that need a rule
    foreach g in array gl loop
      if dims -> g ->> 'need' = 'fy' and fym is null then
        gl := array_remove(gl, g);
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'fiscal_year_start_month', 'text_en', 'Fiscal-year grouping needs the rule fiscal_year_start_month', 'text_bn', 'অর্থবছর অনুযায়ী ভাগের জন্য নিয়ম fiscal_year_start_month লিখুন'));
      elsif dims -> g ->> 'need' = 'ws' and ws is null then
        ws := 1;
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'week_default', 'text_en', 'Week start rule not set: weeks start on Monday', 'text_bn', 'সপ্তাহ শুরুর নিয়ম নেই: সোমবার ধরা হয়েছে'));
      end if;
    end loop;
    -- measures
    for mk in select jsonb_array_elements_text(def -> 'measures') loop
      if meas ? mk and (cost_ok or coalesce((meas -> mk ->> 'cost')::int, 0) = 0) then mkeys := mkeys || mk; end if;
    end loop;
    if not cost_ok and (coalesce((def ->> 'cost_join')::int, 0) = 1 or exists (select 1 from jsonb_array_elements_text(def -> 'measures') m where coalesce((meas -> m ->> 'cost')::int, 0) = 1)) then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden', 'text_en', 'Cost and profit columns are hidden for your role', 'text_bn', 'আপনার ভূমিকার জন্য খরচ ও লাভের কলাম বন্ধ'));
    end if;
    -- output columns
    foreach g in array gl loop
      for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
        cols := cols || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 2, 'label_en', c ->> 3, 'type', c ->> 4, 'role', 'dim'));
        allowkeys := allowkeys || (c ->> 0);
        if first_dim is null and c ->> 4 <> 'id' then first_dim := c ->> 0; end if;
      end loop;
    end loop;
    foreach mk in array mkeys loop
      cols := cols || jsonb_build_array(jsonb_build_object('key', mk, 'label_bn', meas -> mk ->> 'bn', 'label_en', meas -> mk ->> 'en', 'type', meas -> mk ->> 'type', 'role', 'measure', 'cost', coalesce((meas -> mk ->> 'cost')::int, 0) = 1));
      allowkeys := allowkeys || mk;
    end loop;
    if cost_ok and coalesce((def ->> 'cost_join')::int, 0) = 1 then
      cols := cols || '[{"key":"cogs","label_bn":"পণ্যের খরচ","label_en":"Cost of goods","type":"money","role":"measure","cost":true},{"key":"gp","label_bn":"মোট লাভ (খরচ জানা অংশে)","label_en":"Gross profit (costed part)","type":"money","role":"measure","cost":true},{"key":"gp_pct","label_bn":"লাভ %","label_en":"GP %","type":"pct","role":"measure","cost":true},{"key":"uncosted_pct","label_bn":"খরচ অজানা বিক্রি %","label_en":"Uncosted sales %","type":"pct","role":"measure","cost":true}]'::jsonb;
      allowkeys := allowkeys || array['cogs', 'gp', 'gp_pct', 'uncosted_pct'];
    end if;
    -- sort (only whitelisted output names; anything else is ignored with a note)
    sraw := lower(btrim(coalesce(p_sort, '')));
    if sraw <> '' then
      if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
      sparts := regexp_split_to_array(sraw, '[: ]+');
      if sparts[1] = any (allowkeys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
      else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
    end if;
    if sk is null then
      dsort := def ->> 'sort';
      if dsort = '@dim' then sk := first_dim; sd := 'asc';
      elsif dsort is not null and split_part(dsort, ':', 1) = any (allowkeys) then sk := split_part(dsort, ':', 1); sd := split_part(dsort, ':', 2); end if;
      if sk is null then sk := first_dim; sd := 'asc'; end if;
    end if;
    ordr := case when sk is null then '1' else quote_ident(sk) || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last, 1' end;

    -- main period
    b := public.rpt_agg_build(def, gl, mkeys, flt, allowed, d1, d2, '{T}.day', ws, fym, mob_ok, cost_ok);
    t := b ->> 't'; tot := b ->> 'tot'; ign := b -> 'ignored';
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''_n'' - ''_rn'' order by x._rn), ''[]''::jsonb), coalesce(max(x._n), 0) from (select q.*, count(*) over () as _n, row_number() over (order by %s) as _rn from (%s) q order by %s limit %s offset %s) x',
      ordr, t, ordr, lim, off) into rows_, ngroups;
    execute format('select to_jsonb(x) from (%s) x', tot) into totals_;
    hm := (off + pgsize) < least(ngroups, cap);
    if ngroups > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ngroups, 'text_en', 'More than 500 groups: only the first 500 (in the chosen order) can be paged; narrow the filters', 'text_bn', '৫০০-র বেশি গ্রুপ: বাছাই অনুযায়ী প্রথম ৫০০টি দেখা যাবে; ফিল্টার ছোট করুন')); end if;
    if jsonb_array_length(ign) > 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', ign)); end if;

    -- compare with an earlier period (same length, same weekday last week, or last year)
    if p_compare and coalesce((def ->> 'cmp')::int, 0) = 1 and d1 is not null then
      cmode := coalesce(flt ->> 'compare_mode', 'prev');
      if cmode not in ('prev', 'week', 'year') then cmode := 'prev'; notes := notes || jsonb_build_array(jsonb_build_object('code', 'compare_mode_ignored')); end if;
      if cmode = 'prev' then shiftdays := d2 - d1 + 1; cf := d1 - shiftdays; ct := d1 - 1; shiftlit := format('interval ''%s days''', shiftdays);
      elsif cmode = 'week' then shiftdays := 7; cf := d1 - 7; ct := d2 - 7; shiftlit := 'interval ''7 days''';
      else shiftdays := 365; cf := (d1 - interval '1 year')::date; ct := (d2 - interval '1 year')::date; shiftlit := 'interval ''1 year'''; end if;
      b2 := public.rpt_agg_build(def, gl, mkeys, flt, allowed, cf, ct, format('({T}.day + %s)::date', shiftlit), ws, fym, mob_ok, cost_ok);
      execute format('select coalesce(jsonb_agg(to_jsonb(q) order by q._rn), ''[]''::jsonb) from (select z.*, row_number() over (order by %s) as _rn from (%s) z order by %s limit %s) q',
        ordr, b2 ->> 't', ordr, cap) into rows2;
      execute format('select to_jsonb(x) from (%s) x', b2 ->> 'tot') into tot2;
      rows2 := (select coalesce(jsonb_agg(e - '_rn'), '[]'::jsonb) from jsonb_array_elements(rows2) e);
      for k in select jsonb_object_keys(totals_) loop
        if jsonb_typeof(totals_ -> k) = 'number' and jsonb_typeof(tot2 -> k) = 'number' then
          cu := (totals_ ->> k)::numeric; pv := (tot2 ->> k)::numeric;
          delta := delta || jsonb_build_object(k, jsonb_build_object('current', cu, 'previous', pv, 'abs', cu - pv, 'pct', case when pv <> 0 then round(100 * (cu - pv) / abs(pv), 2) end));
        end if;
      end loop;
      cmp_ := jsonb_build_object('mode', cmode, 'from', cf, 'to', ct, 'shifted_days', case when cmode = 'year' then null else shiftdays end, 'totals', tot2, 'rows', rows2, 'delta', delta,
        'note', 'Time columns of compare rows are shifted forward to line up with the current period');
    elsif p_compare then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'compare_unavailable'));
    end if;

  -- ---------------- fixed (list) reports ----------------
  else
    bk := public.rule_txt('report_aging_buckets');
    if bk is not null and bk ~ '^[0-9]{1,4}(,[0-9]{1,4}){0,5}$' then
      buckets := string_to_array(bk, ',')::int[];
      for i in 2..cardinality(buckets) loop if buckets[i] <= buckets[i - 1] then buckets := null; exit; end if; end loop;
    end if;
    near := public.rule_num('report_near_limit_pct');
    raw := public.rpt_raw(p_key, flt, allowed, d1, d2, mob_ok, buckets, near, today);
    t := raw ->> 't'; tot := raw ->> 'tot'; ign := raw -> 'ignored';
    if raw -> 'cols' is not null and jsonb_typeof(raw -> 'cols') = 'array' then
      for c in select * from jsonb_array_elements(raw -> 'cols') loop
        cols := cols || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3, 'role', 'col'));
        allowkeys := allowkeys || (c ->> 0);
      end loop;
    else
      for c in select * from jsonb_array_elements(def -> 'columns') loop
        cols := cols || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3, 'role', 'col'));
        allowkeys := allowkeys || (c ->> 0);
      end loop;
    end if;
    notes := notes || coalesce(raw -> 'notes', '[]'::jsonb);
    if jsonb_array_length(ign) > 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', ign)); end if;
    if p_group is not null and btrim(p_group) <> '' then notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(p_group, 30))); end if;
    if p_compare then notes := notes || jsonb_build_array(jsonb_build_object('code', 'compare_unavailable')); end if;
    sraw := lower(btrim(coalesce(p_sort, '')));
    if sraw <> '' then
      if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
      sparts := regexp_split_to_array(sraw, '[: ]+');
      if sparts[1] = any (allowkeys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
      else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
    end if;
    if sk is null then
      dsort := def ->> 'sort';
      if split_part(dsort, ':', 1) = any (allowkeys) then sk := split_part(dsort, ':', 1); sd := split_part(dsort, ':', 2); else sk := allowkeys[1]; sd := 'asc'; end if;
    end if;
    ordr := quote_ident(sk) || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last, 1';
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''_n'' - ''_rn'' order by x._rn), ''[]''::jsonb), coalesce(max(x._n), 0) from (select q.*, count(*) over () as _n, row_number() over (order by %s) as _rn from (%s) q order by %s limit %s offset %s) x',
      ordr, t, ordr, lim, off) into rows_, ngroups;
    execute format('select to_jsonb(x) from (select %s from (%s) q) x', tot, t) into totals_;
    hm := (off + pgsize) < least(ngroups, cap);
    if ngroups > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ngroups, 'text_en', 'More than 500 rows: only the first 500 (in the chosen order) can be paged; narrow the filters', 'text_bn', '৫০০-র বেশি সারি: বাছাই অনুযায়ী প্রথম ৫০০টি দেখা যাবে; ফিল্টার ছোট করুন')); end if;
  end if;

  if not mob_ok and exists (select 1 from jsonb_array_elements(cols) ce where ce ->> 'key' = 'mobile') then
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'mobile_masked', 'text_en', 'Customer mobile numbers are masked for your role', 'text_bn', 'আপনার ভূমিকার জন্য গ্রাহকের মোবাইল নম্বর ঢাকা'));
  end if;
  if jsonb_array_length(rows_) = 0 or ngroups = 0
     or (kind = 'agg' and cardinality(gl) = 0 and not exists (select 1 from jsonb_each_text(totals_) kv where kv.value ~ '^-?[0-9.]+$' and kv.value::numeric <> 0)) then
    dn := true;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_data', 'text_en', 'Data needed: nothing matches this period / filters', 'text_bn', 'তথ্য দরকার: এই সময়/ফিল্টারে কিছু নেই'));
  end if;
  return jsonb_build_object('report', p_key, 'columns', cols, 'rows', rows_, 'totals', totals_, 'compare', cmp_,
    'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', ngroups, 'cap', cap), 'has_more', coalesce(hm, false), 'notes', notes, 'data_needed', dn,
    'meta', jsonb_build_object('from', d1, 'to', d2, 'group', to_jsonb(gl), 'sort', sk, 'dir', sd, 'cost_shown', cost_ok, 'mobile_masked', not mob_ok, 'today', today));
end $$;

-- ---------- privileges: nobody anonymous; signed-in users reach data only through the functions above ----------
revoke all on function public.rpt_access(text), public.rpt_cost_ok(), public.rpt_mobile_ok(), public.rpt_arr_text(jsonb), public.rpt_arr_int(jsonb), public.rpt_arr_uuid(jsonb),
  public.rpt_num(jsonb), public.rpt_date(text), public.rpt_dims(text), public.rpt_meas(text), public.rpt_def(text), public.rpt_keys(), public.rpt_filters_for(text),
  public.rpt_tok(text, text, text, int, int, boolean), public.rpt_where(text, text, jsonb, int[], date, date, text[], boolean),
  public.rpt_agg_sql(text, text, text, text[], text[], text, text, text, text, int, int, boolean, boolean, boolean),
  public.rpt_agg_build(jsonb, text[], text[], jsonb, int[], date, date, text, int, int, boolean, boolean), public.rpt_mobx(text, boolean),
  public.rpt_raw(text, jsonb, int[], date, date, boolean, int[], numeric, date),
  public.report_presets(), public.report_catalog(), public.report_run(text, jsonb, text, text, int, boolean) from public, anon, authenticated;
grant execute on function public.report_presets(), public.report_catalog(), public.report_run(text, jsonb, text, text, int, boolean) to authenticated;
