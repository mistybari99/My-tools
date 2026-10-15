-- ============================================================
-- Phase 131 (marker rpt131) - REPORTS STAGE 1 (sweets business): verified sales / status / profit / stock / wastage / cash / ageing reports.
-- ADDITIVE ONLY. Canonical order: after phase129 (phase130 is a test-only file). Paste twice = no change, no error.
-- Switch: rule rpt131_on, default OFF. While OFF every rpt131_* report returns {off:true, data_needed:true} and reads nothing. Nothing existing is changed or re-created.
-- Who may run: the existing report rights only (rpt_access('<group>') = owner, grant report_<group> or view_reports). Cost columns only for owner / rpt_cost_ok().
-- Scope: every report works on the places the caller may use (can_loc, which is business-safe when org_scope_on is ON). No company-wide figure is built for non-owners;
--   a place the caller may not use in p_locs is refused ('not allowed for this location'). Customer mobile numbers are not returned.
-- Books: the status / tie-out columns read journal_entries + journal_lines (posted entries, their reversals and voided originals); the books side is shown only to users who may
--   view accounts (_acct_view); others get null + a note, never a zero.
-- Honesty rules: empty result -> data_needed:true and totals:null (never a row of zeros); a quantity is never summed across items with different units; a cost that is not known
--   is counted and shown as unknown (cost_unknown), not as 0; an unset rule (age buckets) is reported as "data needed", not defaulted.
-- Statuses: a sale is posted | unposted (done, not yet in the books) | void (never in the books) | reversed (void, books reversed) | void_not_reversed (void, books still carry it).
--   Sales have no draft state in the database (the cart exists only on the phone), so "draft" is not a sale status here. Returns: same list; "refunded" = a done return exists.
-- Functions (browser): rpt131_catalog, rpt131_sales, rpt131_sales_recon, rpt131_item_profit, rpt131_stock_recon, rpt131_wastage, rpt131_cash_close, rpt131_ageing, rpt131_log_export.
-- Rollback: leave rpt131_on OFF. To remove: drop the functions below (nothing else refers to them).
-- ============================================================
begin;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('rpt131_on', 'reports', 'switch', 'false', null, null, null, null,
  'যাচাই করা রিপোর্ট (ধাপ ১) চালু', 'Verified reports (Stage 1) চালু', 'Verified reports (Stage 1)',
  'চালু করলে বিক্রি/স্ট্যাটাস, আইটেম লাভ, স্টক মিলানো, অপচয়, ক্যাশ ক্লোজ ও বাকি/পাওনার বয়স রিপোর্ট খোলে; সব হিসাব খাতার সাথে মেলানো।',
  'চালু করলে sales/status, item profit, stock reconcile, wastage, cash close ও ageing report খোলে; সব হিসাব books-এর সাথে মেলানো।',
  'When on, the sales / status, item profit, stock reconciliation, wastage, cash close and ageing reports open; every figure is tied to the books.', 1310)
on conflict (key) do nothing;

-- ---------- helpers (not callable from the browser) ----------
create or replace function public._rpt131_note(p_code text, p_en text, p_bn text, p_what text default null) returns jsonb
language sql immutable set search_path = public as
$$ select jsonb_strip_nulls(jsonb_build_object('code', p_code, 'text_en', p_en, 'text_bn', p_bn, 'what', p_what)) $$;

create or replace function public._rpt131_gate(p_group text) returns boolean
language plpgsql stable security definer set search_path = public as
$fn$
begin   -- rpt131: false = the module switch is OFF (caller returns the "off" answer); an unauthorised caller is refused either way
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rpt_access(p_group) then raise exception 'not allowed'; end if;
  return coalesce(public.rule_on('rpt131_on'), false);
end $fn$;

create or replace function public._rpt131_off(p_report text) returns jsonb
language sql stable set search_path = public as
$$ select jsonb_build_object('report', p_report, 'off', true, 'data_needed', true, 'generated_at', now(), 'rows', '[]'::jsonb, 'totals', null, 'row_count', 0,
   'notes', jsonb_build_array(public._rpt131_note('feature_off', 'Verified reports are switched off (rule rpt131_on).', 'যাচাই করা রিপোর্ট বন্ধ (rpt131_on নিয়ম)।'))) $$;

create or replace function public._rpt131_locs(p_locs int[]) returns int[]
language plpgsql stable security definer set search_path = public as
$fn$
declare acc int[]; bad int;
begin
  select coalesce(array_agg(l.id order by l.id), '{}') into acc from public.locations l where public.can_loc(l.id);
  if p_locs is not null and cardinality(p_locs) > 0 then
    select x into bad from unnest(p_locs) x where x is null or not (x = any (acc)) limit 1;
    if found then raise exception 'not allowed for this location'; end if;
    return (select array_agg(distinct x order by x) from unnest(p_locs) x);
  end if;
  return acc;
end $fn$;

create or replace function public._rpt131_dates(p_from date, p_to date, out d1 date, out d2 date, out defaulted boolean)
language plpgsql stable set search_path = public as
$fn$
declare td date := public._today();
begin
  if p_from is null and p_to is null then d1 := date_trunc('month', td)::date; d2 := td; defaulted := true;
  else d1 := coalesce(p_from, p_to); d2 := coalesce(p_to, td); defaulted := false; end if;
  if d1 < date '2000-01-01' or d2 > date '2100-01-01' or d2 < d1 or d2 - d1 > 366 then raise exception 'bad_range'; end if;
end $fn$;

-- search (any text in the row) + totals of the matching rows + sort + page. Totals are over ALL matching rows, not only the page.
create or replace function public._rpt131_finish(p_rows jsonb, p_sum text[], p_search text, p_sort text, p_page int, p_size int, p_defsort text) returns jsonb
language plpgsql stable set search_path = public as
$fn$
declare q text := nullif(btrim(coalesce(p_search, '')), ''); spec text := coalesce(nullif(btrim(p_sort), ''), p_defsort); sk text; sd text; sz int; pg int; n int;
        allrows jsonb; pagerows jsonb; tot jsonb := '{}'::jsonb; c text; v numeric;
begin
  sz := least(greatest(coalesce(p_size, 50), 5), 200); pg := least(greatest(coalesce(p_page, 1), 1), 100000);
  sk := lower(split_part(spec, ':', 1)); sd := case lower(split_part(spec, ':', 2)) when 'asc' then 'asc' else 'desc' end;
  if sk !~ '^[a-z0-9_]{1,40}$' then sk := lower(split_part(p_defsort, ':', 1)); sd := case lower(split_part(p_defsort, ':', 2)) when 'asc' then 'asc' else 'desc' end; end if;
  if q is not null then q := '%' || lower(replace(replace(replace(left(q, 60), '\', '\\'), '%', '\%'), '_', '\_')) || '%'; end if;
  select coalesce(jsonb_agg(r), '[]'::jsonb) into allrows from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r where q is null or lower(r::text) like q;
  n := jsonb_array_length(allrows);
  foreach c in array coalesce(p_sum, '{}'::text[]) loop
    select sum((r ->> c)::numeric) into v from jsonb_array_elements(allrows) r where (r ->> c) ~ '^-?[0-9]+(\.[0-9]+)?$';
    tot := tot || jsonb_build_object(c, case when v is null then null else round(v, 4) end);
  end loop;
  if sd = 'asc' then
    select coalesce(jsonb_agg(x.r), '[]'::jsonb) into pagerows from (select r from jsonb_array_elements(allrows) r
      order by (case when r ->> sk ~ '^-?[0-9]+(\.[0-9]+)?$' then (r ->> sk)::numeric end) asc nulls last, r ->> sk asc nulls last, r::text asc offset (pg - 1) * sz limit sz) x;
  else
    select coalesce(jsonb_agg(x.r), '[]'::jsonb) into pagerows from (select r from jsonb_array_elements(allrows) r
      order by (case when r ->> sk ~ '^-?[0-9]+(\.[0-9]+)?$' then (r ->> sk)::numeric end) desc nulls last, r ->> sk desc nulls last, r::text asc offset (pg - 1) * sz limit sz) x;
  end if;
  return jsonb_build_object('rows', pagerows, 'totals', tot, 'row_count', n, 'page', pg, 'size', sz, 'has_more', n > pg * sz, 'sort', sk || ':' || sd);
end $fn$;

create or replace function public._rpt131_env(p_report text, p_filters jsonb, p_cols jsonb, p_fin jsonb, p_notes jsonb, p_extra jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare sid text;
begin
  select coalesce(nullif(btrim(full_name), ''), staff_id) into sid from public.profiles where id = auth.uid();
  return jsonb_build_object('report', p_report, 'off', false, 'generated_at', now(), 'generated_by', sid, 'filters', p_filters, 'columns', p_cols,
    'rows', p_fin -> 'rows', 'totals', case when (p_fin ->> 'row_count')::int = 0 then null else p_fin -> 'totals' end,
    'row_count', (p_fin ->> 'row_count')::int, 'page', (p_fin ->> 'page')::int, 'size', (p_fin ->> 'size')::int, 'has_more', (p_fin ->> 'has_more')::boolean, 'sort', p_fin ->> 'sort',
    'data_needed', (p_fin ->> 'row_count')::int = 0, 'cost_visible', public.rpt_cost_ok(), 'notes', coalesce(p_notes, '[]'::jsonb)) || coalesce(p_extra, '{}'::jsonb);
end $fn$;

-- ---------- catalogue ----------
create or replace function public.rpt131_catalog() returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare on_ boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  on_ := coalesce(public.rule_on('rpt131_on'), false);
  return jsonb_build_object('enabled', on_, 'reports', jsonb_build_array(
    jsonb_build_object('key', 'rpt131_sales', 'group', 'sales', 'allowed', public.rpt_access('sales'), 'name_en', 'Sales, net of voids and returns', 'name_bn', 'বিক্রি (বাতিল ও ফেরত বাদে)',
       'groups', jsonb_build_array('day', 'week', 'month', 'outlet', 'hour', 'weekday', 'staff', 'sale_type', 'pay_mode')),
    jsonb_build_object('key', 'rpt131_sales_recon', 'group', 'sales', 'allowed', public.rpt_access('sales'), 'name_en', 'Sales status and books tie-out', 'name_bn', 'বিক্রির স্ট্যাটাস ও খাতার সাথে মিল',
       'statuses', jsonb_build_array('all', 'posted', 'unposted', 'void', 'reversed', 'void_not_reversed', 'refunded', 'problems')),
    jsonb_build_object('key', 'rpt131_item_profit', 'group', 'profit', 'allowed', public.rpt_access('profit'), 'name_en', 'Item / category / outlet profit (real costs)', 'name_bn', 'আইটেম / ক্যাটাগরি / আউটলেট লাভ',
       'groups', jsonb_build_array('item', 'category', 'outlet')),
    jsonb_build_object('key', 'rpt131_stock_recon', 'group', 'stock', 'allowed', public.rpt_access('stock'), 'name_en', 'Stock reconciliation (opening + in - out = closing)', 'name_bn', 'স্টক মিলানো'),
    jsonb_build_object('key', 'rpt131_wastage', 'group', 'stock', 'allowed', public.rpt_access('stock'), 'name_en', 'Wastage by reason, item, outlet, status', 'name_bn', 'অপচয়',
       'groups', jsonb_build_array('reason', 'item', 'outlet', 'day', 'status', 'doc'), 'statuses', jsonb_build_array('all', 'posted', 'pending', 'rejected', 'cancelled', 'reversed')),
    jsonb_build_object('key', 'rpt131_cash_close', 'group', 'cash', 'allowed', public.rpt_access('cash'), 'name_en', 'Cash book and day close', 'name_bn', 'ক্যাশ বই ও দিনশেষ'),
    jsonb_build_object('key', 'rpt131_ageing', 'group', 'customers', 'allowed', public.rpt_access('customers') or public.rpt_access('purchase'), 'name_en', 'Receivable and payable ageing', 'name_bn', 'বাকি ও পাওনার বয়স',
       'kinds', jsonb_build_array('receivable', 'payable'))));
end $fn$;

-- ---------- 1. sales net of voids and returns ----------
create or replace function public.rpt131_sales(p_from date default null, p_to date default null, p_locs int[] default null, p_group text default 'day',
                                              p_search text default null, p_sort text default null, p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; g text := lower(btrim(coalesce(p_group, 'day'))); notes jsonb := '[]'::jsonb; rws jsonb; cols jsonb; fin jsonb; dimx text; lb text; le text; jn text := ''; defsort text;
        sumcols text[];
begin
  if not public._rpt131_gate('sales') then return public._rpt131_off('rpt131_sales'); end if;
  if g not in ('day', 'week', 'month', 'outlet', 'hour', 'weekday', 'staff', 'sale_type', 'pay_mode') then raise exception 'bad_group'; end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  locs := public._rpt131_locs(p_locs);
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_sales', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'group', g), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'dim:asc'), notes);
  end if;
  notes := notes || public._rpt131_note('basis', 'Voided bills are shown apart and never counted. Returns are counted on the day they were made, at the place they were made.', 'বাতিল বিল আলাদা দেখানো, গোনা হয়নি। ফেরত ফেরতের দিনে ধরা।');
  if g = 'week' then notes := notes || public._rpt131_note('week_start', 'Weeks start on Monday.', 'সপ্তাহ সোমবার থেকে শুরু।'); end if;

  if g = 'pay_mode' then
    notes := notes || public._rpt131_note('pay_basis', 'Received = money taken with the bill; Due = sold on credit; Refunded = cash/mobile/card given back plus credit given on returns; Collections (old dues paid) are shown for information and are not sales.', 'Received = বিলের সাথে নেওয়া টাকা; Due = বাকিতে বিক্রি; Refunded = ফেরত দেওয়া টাকা ও ক্রেডিট; Collections তথ্যের জন্য, বিক্রি নয়।');
    with pay as (
        select p.mode m, sum(p.amount) v, count(distinct p.sale_id) n from public.sale_payments p join public.sales s on s.id = p.sale_id
         where p.kind = 'sale' and not p.voided and s.status = 'done' and s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs) group by p.mode),
      col as (
        select p.mode m, sum(p.amount) v from public.sale_payments p
         where p.kind = 'collection' and not p.voided and (p.paid_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and p.location_id = any (locs) group by p.mode),
      rf as (
        select r.refund_mode m, sum(r.refund_amount) v from public.sale_returns r
         where r.status = 'done' and r.refund_amount > 0 and (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs) group by r.refund_mode),
      due as (
        select coalesce(sum(s.due_amount), 0) v, count(*) filter (where s.due_amount > 0) n from public.sales s
         where s.status = 'done' and s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs)),
      duer as (
        select coalesce(sum(r.credit_amount), 0) v from public.sale_returns r
         where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs)),
      modes as (select m from pay union select m from col union select m from rf),
      x as (
        select m.m dim, m.m label_en, m.m label_bn, coalesce(pay.n, 0) bills, coalesce(pay.v, 0) received, col.v collections, coalesce(rf.v, 0) refunded
          from modes m left join pay on pay.m = m.m left join col on col.m = m.m left join rf on rf.m = m.m
        union all
        select 'due', 'On credit (due)', 'বাকিতে', due.n, due.v, null, duer.v from due, duer where due.v > 0 or duer.v > 0)
    select coalesce(jsonb_agg(jsonb_build_object('dim', x.dim, 'label_en', x.label_en, 'label_bn', x.label_bn, 'bills', x.bills, 'received', round(x.received, 2), 'collections', round(x.collections, 2),
                    'refunded', round(x.refunded, 2), 'net_sales', round(x.received - x.refunded, 2)) order by x.dim), '[]'::jsonb) into rws from x;
    cols := '[{"k":"label","bn":"পেমেন্ট","en":"Payment","t":"text"},{"k":"bills","bn":"বিল","en":"Bills","t":"int"},{"k":"received","bn":"নেওয়া / বাকি","en":"Received / due","t":"money","sum":true},
              {"k":"refunded","bn":"ফেরত","en":"Refunded","t":"money","sum":true},{"k":"net_sales","bn":"নিট","en":"Net","t":"money","sum":true},{"k":"collections","bn":"আদায় (তথ্য)","en":"Collections (info)","t":"money","sum":true}]'::jsonb;
    sumcols := array['received', 'refunded', 'net_sales', 'collections'];
    fin := public._rpt131_finish(rws, sumcols, p_search, p_sort, p_page, p_size, 'net_sales:desc');
    return public._rpt131_env('rpt131_sales', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'group', g, 'search', p_search), cols, fin, notes);
  end if;

  dimx := case g when 'day' then 'u.d::text' when 'week' then $$date_trunc('week', u.d)::date::text$$ when 'month' then $$to_char(u.d, 'YYYY-MM')$$ when 'outlet' then 'u.loc::text'
            when 'hour' then $$lpad(extract(hour from (u.t at time zone 'Asia/Dhaka'))::int::text, 2, '0')$$ when 'weekday' then $$extract(isodow from (u.t at time zone 'Asia/Dhaka'))::int::text$$
            when 'staff' then 'u.staff' else $$coalesce(u.stype, 'retail')$$ end;
  lb := case g when 'outlet' then 'coalesce(lo.name_bn, a.dim)' when 'hour' then $$a.dim || ':00'$$ when 'weekday' then $$(array['সোম','মঙ্গল','বুধ','বৃহস্পতি','শুক্র','শনি','রবি'])[a.dim::int]$$ else 'a.dim' end;
  le := case g when 'outlet' then 'coalesce(lo.name_en, lo.name_bn, a.dim)' when 'hour' then $$a.dim || ':00'$$ when 'weekday' then $$(array['Mon','Tue','Wed','Thu','Fri','Sat','Sun'])[a.dim::int]$$ else 'a.dim' end;
  if g = 'outlet' then jn := 'left join public.locations lo on lo.id = a.dim::int'; end if;
  defsort := case when g in ('outlet', 'staff', 'sale_type') then 'net_sales:desc' else 'dim:asc' end;
  execute format($q$
    with u as (
      select 'sale'::text src, s.location_id loc, s.sale_date d, s.sold_at t, coalesce(nullif(btrim(s.created_staff), ''), '-') staff, s.sale_type stype, s.subtotal gross, s.discount disc, s.total net
        from public.sales s where s.status = 'done' and s.sale_date between $1 and $2 and s.location_id = any ($3)
      union all
      select 'void', s.location_id, s.sale_date, s.sold_at, coalesce(nullif(btrim(s.created_staff), ''), '-'), s.sale_type, s.subtotal, s.discount, s.total
        from public.sales s where s.status = 'void' and s.sale_date between $1 and $2 and s.location_id = any ($3)
      union all
      select 'ret', r.location_id, (r.created_at at time zone 'Asia/Dhaka')::date, r.created_at, coalesce(nullif(btrim(r.created_staff), ''), '-'), x.sale_type, 0, 0, r.amount
        from public.sale_returns r left join public.sales x on x.id = r.sale_id
       where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between $1 and $2 and r.location_id = any ($3)),
    a as (
      select %s as dim, count(*) filter (where src = 'sale') bills, coalesce(sum(gross) filter (where src = 'sale'), 0) gross, coalesce(sum(disc) filter (where src = 'sale'), 0) discount,
             coalesce(sum(net) filter (where src = 'sale'), 0) sales_net, count(*) filter (where src = 'void') void_bills, coalesce(sum(net) filter (where src = 'void'), 0) void_value,
             count(*) filter (where src = 'ret') return_count, coalesce(sum(net) filter (where src = 'ret'), 0) returns
        from u group by 1)
    select coalesce(jsonb_agg(jsonb_build_object('dim', a.dim, 'label_bn', %s, 'label_en', %s, 'bills', a.bills, 'gross', round(a.gross, 2), 'discount', round(a.discount, 2),
             'sales_net', round(a.sales_net, 2), 'return_count', a.return_count, 'returns', round(a.returns, 2), 'net_sales', round(a.sales_net - a.returns, 2),
             'avg_bill', case when a.bills > 0 then round(a.sales_net / a.bills, 2) end, 'return_pct', case when a.sales_net > 0 then round(100 * a.returns / a.sales_net, 2) end,
             'void_bills', a.void_bills, 'void_value', round(a.void_value, 2)) order by a.dim), '[]'::jsonb)
      from a %s$q$, dimx, lb, le, jn) into rws using dd.d1, dd.d2, locs;
  cols := jsonb_build_array(jsonb_build_object('k', 'label', 'bn', 'ভাগ', 'en', 'Group', 't', 'text'),
    '{"k":"bills","bn":"বিল","en":"Bills","t":"int","sum":true}'::jsonb, '{"k":"gross","bn":"মোট (ছাড়ের আগে)","en":"Gross","t":"money","sum":true}'::jsonb,
    '{"k":"discount","bn":"ছাড়","en":"Discount","t":"money","sum":true}'::jsonb, '{"k":"sales_net","bn":"বিক্রি","en":"Sales","t":"money","sum":true}'::jsonb,
    '{"k":"returns","bn":"ফেরত","en":"Returns","t":"money","sum":true}'::jsonb, '{"k":"net_sales","bn":"নিট বিক্রি","en":"Net sales","t":"money","sum":true}'::jsonb,
    '{"k":"avg_bill","bn":"গড় বিল","en":"Avg bill","t":"money"}'::jsonb, '{"k":"return_pct","bn":"ফেরত %","en":"Return %","t":"pct"}'::jsonb,
    '{"k":"void_bills","bn":"বাতিল বিল","en":"Void bills","t":"int","sum":true}'::jsonb, '{"k":"void_value","bn":"বাতিল টাকা","en":"Void value","t":"money","sum":true}'::jsonb);
  sumcols := array['bills', 'gross', 'discount', 'sales_net', 'return_count', 'returns', 'net_sales', 'void_bills', 'void_value'];
  fin := public._rpt131_finish(rws, sumcols, p_search, p_sort, p_page, p_size, defsort);
  return public._rpt131_env('rpt131_sales', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'group', g, 'search', p_search), cols, fin, notes);
end $fn$;

-- ---------- 2. sales / return documents: status and tie-out to the books ----------
create or replace function public.rpt131_sales_recon(p_from date default null, p_to date default null, p_locs int[] default null, p_status text default 'all',
                                                    p_search text default null, p_sort text default null, p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; v_st text := lower(btrim(coalesce(p_status, 'all'))); notes jsonb := '[]'::jsonb; rws jsonb; fin jsonb; cols jsonb; books boolean; a_s bigint; a_d bigint; a_r bigint;
        summ jsonb; tie jsonb; jb numeric; cap constant int := 5000; ndocs int;
begin
  if not public._rpt131_gate('sales') then return public._rpt131_off('rpt131_sales_recon'); end if;
  if v_st not in ('all', 'posted', 'unposted', 'void', 'reversed', 'void_not_reversed', 'refunded', 'problems') then raise exception 'bad_status'; end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  if dd.d2 - dd.d1 > 92 then raise exception 'bad_range'; end if;
  locs := public._rpt131_locs(p_locs);
  books := public._acct_view();
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_sales_recon', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'status', v_st), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'd:desc'), notes);
  end if;
  if not books then
    notes := notes || public._rpt131_note('books_hidden', 'You may not view the accounts: the books side (status, tie-out) is not shown.', 'আপনি হিসাব দেখতে পারেন না: খাতার দিক দেখানো হয়নি।');
    -- without the books the register still lists the documents, with the register status only
  end if;
  select account_id into a_s from public.acct_mappings where key = 'sales';
  select account_id into a_d from public.acct_mappings where key = 'sales_discount';
  select account_id into a_r from public.acct_mappings where key = 'sales_returns';
  notes := notes || public._rpt131_note('basis', 'Register amount = sale total (after discount) for a done sale, minus the return amount for a done return; a void document counts 0. Books amount = what the journal holds for that document (a reversed document nets to 0). Sales are posted to the books in batches, so a done sale can be "unposted" for a while. Draft does not exist for sales.', 'রেজিস্টার = বিক্রির মোট; ফেরত বিয়োগ; বাতিল = ০। খাতা = জার্নালে যা আছে। বিক্রি ব্যাচে খাতায় যায়, তাই কিছু বিল "unposted" থাকতে পারে।');

  with docs as (
      select 'sale'::text doc_type, s.id doc_id, s.receipt::text ref, s.sale_date d, s.location_id loc, s.status st, s.total amt, s.subtotal gross, s.discount disc,
             coalesce(nullif(btrim(s.customer), ''), '-') party, coalesce(nullif(btrim(s.created_staff), ''), '-') staff, null::uuid sale_id
        from public.sales s where s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs)
      union all
      select 'return', r.id, 'R-' || coalesce(x.receipt::text, '?'), (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, r.status, r.amount, 0, 0,
             coalesce(nullif(btrim(x.customer), ''), '-'), coalesce(nullif(btrim(r.created_staff), ''), '-'), r.sale_id
        from public.sale_returns r left join public.sales x on x.id = r.sale_id
       where (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs)),
    c as (
      select dc.*, case when books then jj.n_orig end n_orig, case when books then jj.n_rev end n_rev,
             case dc.doc_type when 'sale' then jj.bs else jj.br end books_abs,
             coalesce((select sum(r2.amount) from public.sale_returns r2 where dc.doc_type = 'sale' and r2.sale_id = dc.doc_id and r2.status = 'done'), 0) returned
        from docs dc
        left join lateral (
          select coalesce(sum(l.credit - l.debit) filter (where l.account_id in (a_s, a_d)), 0) bs, coalesce(sum(l.debit - l.credit) filter (where l.account_id = a_r), 0) br,
                 count(distinct e.id) filter (where e.reverses_id is null) n_orig, count(distinct e.id) filter (where e.reverses_id is not null) n_rev
            from public.journal_entries e join public.journal_lines l on l.entry_id = e.id
           where books and e.source_type = (case dc.doc_type when 'sale' then 'sale' else 'sale_return' end) and e.source_id = dc.doc_id::text) jj on true),
    k as (
      select c.*, (case c.doc_type when 'sale' then 1 else -1 end) sg,
             case when not books then case c.st when 'done' then 'done' else 'void' end
                  when c.st = 'done' then case when c.n_orig > 0 then 'posted' else 'unposted' end
                  else case when c.n_orig > 0 and c.n_rev > 0 then 'reversed' when c.n_orig > 0 then 'void_not_reversed' else 'void' end end dstatus,
             case when c.st = 'done' then c.amt else 0 end reg_abs
        from c),
    f as (
      select k.*, round(k.sg * k.reg_abs, 2) reg_net, case when books then round(k.sg * coalesce(k.books_abs, 0), 2) end books_net,
             case when books then round(k.sg * (k.reg_abs - coalesce(k.books_abs, 0)), 2) end diff,
             case when k.doc_type = 'sale' then case when k.returned <= 0.004 then 'none' when k.returned >= k.amt - 0.005 then 'full' else 'partial' end end refund_state
        from k)
  select count(*),
         jsonb_build_object('by_status', coalesce((select jsonb_object_agg(z.dstatus || '/' || z.doc_type, jsonb_build_object('docs', z.n, 'register_net', z.rn, 'books_net', z.bn))
                                                    from (select f.dstatus, f.doc_type, count(*) n, round(sum(f.reg_net), 2) rn, round(sum(f.books_net), 2) bn from f group by 1, 2) z), '{}'::jsonb),
                            'register_net_total', round(coalesce(sum(f.reg_net), 0), 2), 'docs_books_net_total', case when books then round(coalesce(sum(f.books_net), 0), 2) end,
                            'unposted_value', case when books then round(coalesce(sum(f.reg_net) filter (where f.dstatus = 'unposted'), 0), 2) end,
                            'amount_differs_value', case when books then round(coalesce(sum(f.diff) filter (where f.dstatus = 'posted' and abs(f.diff) > 0.005), 0), 2) end,
                            'not_reversed_docs', case when books then count(*) filter (where f.dstatus = 'void_not_reversed') end)
    into ndocs, summ from f;
  with docs as (
      select 'sale'::text doc_type, s.id doc_id, s.receipt::text ref, s.sale_date d, s.location_id loc, s.status st, s.total amt, s.subtotal gross, s.discount disc,
             coalesce(nullif(btrim(s.customer), ''), '-') party, coalesce(nullif(btrim(s.created_staff), ''), '-') staff
        from public.sales s where s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs)
      union all
      select 'return', r.id, 'R-' || coalesce(x.receipt::text, '?'), (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, r.status, r.amount, 0, 0,
             coalesce(nullif(btrim(x.customer), ''), '-'), coalesce(nullif(btrim(r.created_staff), ''), '-')
        from public.sale_returns r left join public.sales x on x.id = r.sale_id
       where (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs)),
    c as (
      select dc.*, case when books then jj.n_orig end n_orig, case when books then jj.n_rev end n_rev, case dc.doc_type when 'sale' then jj.bs else jj.br end books_abs,
             coalesce((select sum(r2.amount) from public.sale_returns r2 where dc.doc_type = 'sale' and r2.sale_id = dc.doc_id and r2.status = 'done'), 0) returned
        from docs dc
        left join lateral (
          select coalesce(sum(l.credit - l.debit) filter (where l.account_id in (a_s, a_d)), 0) bs, coalesce(sum(l.debit - l.credit) filter (where l.account_id = a_r), 0) br,
                 count(distinct e.id) filter (where e.reverses_id is null) n_orig, count(distinct e.id) filter (where e.reverses_id is not null) n_rev
            from public.journal_entries e join public.journal_lines l on l.entry_id = e.id
           where books and e.source_type = (case dc.doc_type when 'sale' then 'sale' else 'sale_return' end) and e.source_id = dc.doc_id::text) jj on true),
    k as (
      select c.*, (case c.doc_type when 'sale' then 1 else -1 end) sg,
             case when not books then case c.st when 'done' then 'done' else 'void' end
                  when c.st = 'done' then case when c.n_orig > 0 then 'posted' else 'unposted' end
                  else case when c.n_orig > 0 and c.n_rev > 0 then 'reversed' when c.n_orig > 0 then 'void_not_reversed' else 'void' end end dstatus,
             case when c.st = 'done' then c.amt else 0 end reg_abs
        from c),
    f as (
      select k.*, round(k.sg * k.reg_abs, 2) reg_net, case when books then round(k.sg * coalesce(k.books_abs, 0), 2) end books_net,
             case when books then round(k.sg * (k.reg_abs - coalesce(k.books_abs, 0)), 2) end diff,
             case when k.doc_type = 'sale' then case when k.returned <= 0.004 then 'none' when k.returned >= k.amt - 0.005 then 'full' else 'partial' end end refund_state,
             case when not books then null when k.dstatus = 'unposted' then 'unposted' when k.dstatus = 'void_not_reversed' then 'books_not_reversed'
                  when abs(k.sg * (k.reg_abs - coalesce(k.books_abs, 0))) > 0.005 then 'amount_differs' end flag
        from k),
    sel as (
      select f.* from f
       where case v_st when 'all' then true when 'refunded' then (f.doc_type = 'return' and f.st = 'done') or coalesce(f.refund_state, 'none') <> 'none'
                     when 'problems' then f.flag is not null else f.dstatus = v_st end
       order by f.d desc, f.ref desc limit cap)
  select coalesce(jsonb_agg(jsonb_build_object('doc_type', sel.doc_type, 'doc_id', sel.doc_id, 'ref', sel.ref, 'd', sel.d, 'loc', sel.loc,
           'outlet_en', (select coalesce(lo.name_en, lo.name_bn) from public.locations lo where lo.id = sel.loc), 'outlet_bn', (select lo.name_bn from public.locations lo where lo.id = sel.loc),
           'party', sel.party, 'staff', sel.staff, 'gross', case when sel.doc_type = 'sale' and sel.st = 'done' then sel.gross end, 'discount', case when sel.doc_type = 'sale' and sel.st = 'done' then sel.disc end,
           'register_net', sel.reg_net, 'books_net', sel.books_net, 'diff', sel.diff, 'status', sel.dstatus, 'refund_state', sel.refund_state, 'returned', case when sel.doc_type = 'sale' then round(sel.returned, 2) end,
           'flag', sel.flag, 'doc_status', sel.st)), '[]'::jsonb) into rws from sel;
  if books then
    select a_s is not null into books;   -- the three mappings must exist for the account view
    if books then
      select round(coalesce(sum(l.credit - l.debit) filter (where l.account_id in (a_s, a_d)), 0) - coalesce(sum(l.debit - l.credit) filter (where l.account_id = a_r), 0), 2) into jb
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where e.entry_date between dd.d1 and dd.d2 and l.location_id = any (locs) and l.account_id in (a_s, a_d, a_r);
    end if;
  end if;
  tie := jsonb_build_object('register_net_total', summ -> 'register_net_total', 'docs_books_net_total', summ -> 'docs_books_net_total', 'journal_by_entry_date', jb,
         'unposted_value', summ -> 'unposted_value', 'amount_differs_value', summ -> 'amount_differs_value', 'not_reversed_docs', summ -> 'not_reversed_docs',
         'explained_gap', case when summ ->> 'docs_books_net_total' is null then null else round((summ ->> 'register_net_total')::numeric - (summ ->> 'docs_books_net_total')::numeric, 2) end);
  if jb is not null and summ ->> 'docs_books_net_total' is not null and abs(jb - (summ ->> 'docs_books_net_total')::numeric) > 0.005 then
    notes := notes || public._rpt131_note('journal_date_gap', 'The journal by entry date differs from the documents of the period (a reversal or a manual entry fell in another period, or a document was posted on another date).', 'এন্ট্রির তারিখ ধরে জার্নাল আর এই সময়ের ডকুমেন্ট মেলেনি (রিভার্সাল/ম্যানুয়াল এন্ট্রি অন্য সময়ে)।');
  end if;
  if ndocs > cap then notes := notes || public._rpt131_note('truncated', 'More than 5000 documents: the list shows the newest 5000; the summary covers all. Narrow the filters.', '৫০০০-এর বেশি ডকুমেন্ট: তালিকায় নতুন ৫০০০, সারাংশে সব। ফিল্টার ছোট করুন।'); end if;
  fin := public._rpt131_finish(rws, array['gross', 'discount', 'register_net', 'books_net', 'diff'], p_search, p_sort, p_page, p_size, 'd:desc');
  cols := '[{"k":"d","bn":"তারিখ","en":"Date","t":"date"},{"k":"ref","bn":"রসিদ","en":"Receipt","t":"text"},{"k":"doc_type","bn":"ধরন","en":"Type","t":"text"},{"k":"outlet","bn":"আউটলেট","en":"Outlet","t":"text"},
            {"k":"party","bn":"গ্রাহক","en":"Customer","t":"text"},{"k":"register_net","bn":"রেজিস্টার","en":"Register","t":"money","sum":true},{"k":"books_net","bn":"খাতা","en":"Books","t":"money","sum":true},
            {"k":"diff","bn":"পার্থক্য","en":"Difference","t":"money","sum":true},{"k":"status","bn":"স্ট্যাটাস","en":"Status","t":"status"},{"k":"refund_state","bn":"ফেরত","en":"Refunded","t":"status"}]'::jsonb;
  return public._rpt131_env('rpt131_sales_recon', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'status', v_st, 'search', p_search), cols, fin, notes,
           jsonb_build_object('summary', summ, 'tie_out', tie, 'books_visible', books is true, 'truncated', ndocs > cap));
end $fn$;

-- ---------- 3. item / category / outlet profit with real costs ----------
create or replace function public.rpt131_item_profit(p_from date default null, p_to date default null, p_locs int[] default null, p_group text default 'item',
                                                    p_category text default null, p_item uuid default null, p_search text default null, p_sort text default null,
                                                    p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; g text := lower(btrim(coalesce(p_group, 'item'))); notes jsonb := '[]'::jsonb; rws jsonb; fin jsonb; cols jsonb; cost_ok boolean; net_on boolean;
        cat text := nullif(btrim(coalesce(p_category, '')), '');
begin
  if not public._rpt131_gate('profit') then return public._rpt131_off('rpt131_item_profit'); end if;
  if g not in ('item', 'category', 'outlet') then raise exception 'bad_group'; end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  locs := public._rpt131_locs(p_locs);
  cost_ok := public.rpt_cost_ok();
  net_on := coalesce(public.rule_on('reports_net_of_returns'), true);
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_item_profit', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'group', g), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'revenue:desc'), notes);
  end if;
  notes := notes || public._rpt131_note('basis', 'Revenue is after the bill discount. Real cost = the cost recorded in the stock ledger when the item was sold. Margin is worked out only on the part of the revenue that has a real cost; revenue without a known cost is shown as uncosted, never as free.', 'রেভিনিউ = বিল ছাড়ের পরে। আসল খরচ = বিক্রির সময় স্টক লেজারে লেখা খরচ। মার্জিন শুধু খরচ জানা অংশে; অজানা খরচ আলাদা দেখানো।');
  if not net_on then notes := notes || public._rpt131_note('returns_not_netted', 'Rule reports_net_of_returns is OFF: returns are NOT taken out of these figures.', 'reports_net_of_returns বন্ধ: ফেরত বাদ দেওয়া হয়নি।'); end if;
  if not cost_ok then notes := notes || public._rpt131_note('cost_hidden', 'Cost and margin columns are hidden for your role.', 'আপনার ভূমিকার জন্য খরচ ও মার্জিন লুকানো।'); end if;
  with l as (select * from public._cogs_lines72(dd.d1, dd.d2, locs)),
    x as (
      select case g when 'item' then coalesce(l.item_id::text, '-') when 'category' then coalesce(nullif(i.category, ''), '-') else l.loc::text end k,
             max(case g when 'item' then coalesce(i.name_bn, 'Unlisted') when 'category' then coalesce(nullif(i.category_bn, ''), nullif(i.category, ''), '-') else lo.name_bn end) nbn,
             max(case g when 'item' then coalesce(i.name_en, i.name_bn, 'Unlisted / quick') when 'category' then coalesce(nullif(i.category, ''), '-') else coalesce(lo.name_en, lo.name_bn) end) nen,
             max(case g when 'item' then coalesce(nullif(i.category, ''), '-') end) catx, max(i.unit) unit,
             sum(case l.src when 'sale' then 1 else -1 end * l.qty) qty, sum(case l.src when 'sale' then 1 else -1 end * l.rev) rev,
             sum(case l.src when 'sale' then 1 else -1 end * l.led_rev) led_rev, sum(case l.src when 'sale' then 1 else -1 end * l.led_cogs) led_cogs,
             sum(case l.src when 'sale' then 1 else -1 end * l.fb_rev) fb_rev, sum(case l.src when 'sale' then 1 else -1 end * l.fb_cogs) fb_cogs,
             sum(case l.src when 'sale' then 1 else -1 end * l.unk_rev) unk_rev, count(distinct l.item_id) n_items
        from l left join public.items i on i.id = l.item_id left join public.locations lo on lo.id = l.loc
       where (p_item is null or l.item_id = p_item) and (cat is null or i.category = cat)
       group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('key', x.k, 'name_bn', x.nbn, 'name_en', x.nen, 'category', x.catx, 'unit', x.unit,
           'qty', case when g = 'item' then round(x.qty, 4) end, 'items', case when g <> 'item' then x.n_items end, 'revenue', round(x.rev, 2),
           'cost_real', case when cost_ok and (x.led_rev <> 0 or x.led_cogs <> 0) then round(x.led_cogs, 2) end,
           'margin', case when cost_ok and x.led_rev <> 0 then round(x.led_rev - x.led_cogs, 2) end,
           'margin_pct', case when cost_ok and x.led_rev > 0 then round(100 * (x.led_rev - x.led_cogs) / x.led_rev, 2) end,
           'costed_pct', case when x.rev > 0 then round(100 * x.led_rev / x.rev, 1) end,
           'cost_estimated', case when cost_ok then round(x.fb_cogs, 2) end, 'estimated_rev', round(x.fb_rev, 2), 'uncosted_rev', round(x.unk_rev, 2)) order by x.k), '[]'::jsonb) into rws from x;
  cols := jsonb_build_array(jsonb_build_object('k', 'label', 'bn', 'নাম', 'en', 'Name', 't', 'text'),
    '{"k":"qty","bn":"পরিমাণ","en":"Qty","t":"qty"}'::jsonb, '{"k":"revenue","bn":"রেভিনিউ","en":"Revenue","t":"money","sum":true}'::jsonb,
    '{"k":"cost_real","bn":"আসল খরচ","en":"Real cost","t":"money","sum":true,"cost":true}'::jsonb, '{"k":"margin","bn":"মার্জিন (খরচ জানা অংশে)","en":"Margin (costed part)","t":"money","sum":true,"cost":true}'::jsonb,
    '{"k":"margin_pct","bn":"মার্জিন %","en":"Margin %","t":"pct","cost":true}'::jsonb, '{"k":"costed_pct","bn":"খরচ জানা %","en":"Costed %","t":"pct"}'::jsonb,
    '{"k":"uncosted_rev","bn":"খরচ অজানা রেভিনিউ","en":"Uncosted revenue","t":"money","sum":true}'::jsonb);
  fin := public._rpt131_finish(rws, array['revenue', 'cost_real', 'margin', 'cost_estimated', 'estimated_rev', 'uncosted_rev'], p_search, p_sort, p_page, p_size, 'revenue:desc');
  return public._rpt131_env('rpt131_item_profit', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'group', g, 'category', cat, 'item', p_item, 'search', p_search), cols, fin, notes,
           jsonb_build_object('returns_netted', net_on));
end $fn$;

-- ---------- 4. stock reconciliation (adapter over stock_recon_statement: paging, search, status, no cross-unit totals) ----------
create or replace function public.rpt131_stock_recon(p_from date default null, p_to date default null, p_locs int[] default null, p_category text default null, p_item uuid default null,
                                                    p_issues_only boolean default false, p_search text default null, p_sort text default null, p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; notes jsonb := '[]'::jsonb; rws jsonb := '[]'::jsonb; fin jsonb; cols jsonb; s jsonb; x int; trunc boolean := false; n_unb int := 0; n_var int := 0; n_all int := 0;
        cat text := nullif(btrim(coalesce(p_category, '')), '');
begin
  if not public._rpt131_gate('stock') then return public._rpt131_off('rpt131_stock_recon'); end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  if dd.d2 - dd.d1 > 366 then raise exception 'bad_range'; end if;
  locs := public._rpt131_locs(p_locs);
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_stock_recon', jsonb_build_object('from', dd.d1, 'to', dd.d2), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'item_code:asc'), notes);
  end if;
  notes := notes || public._rpt131_note('formula', 'opening + in (production, purchases, transfers in, customer give-backs) - out (used, sold, wasted, transit loss, transfers out) + adjustments = closing. "check" must be 0. "variance" = stock ledger total minus the stored balance. Quantities are never added across items.', 'শুরু + আসা - যাওয়া + সমন্বয় = শেষ। "check" ০ হতে হবে। পরিমাণ ভিন্ন আইটেমে যোগ করা হয় না।');
  for x in select unnest(case when p_locs is null or cardinality(p_locs) = 0 then array[null::int] else locs end) loop
    s := public.stock_recon_statement(dd.d1, dd.d2, x, p_item, cat, 5000);
    if (s ->> 'truncated')::boolean then trunc := true; end if;
    n_unb := n_unb + coalesce((s -> 'summary' ->> 'unbalanced')::int, 0); n_var := n_var + coalesce((s -> 'summary' ->> 'with_variance')::int, 0); n_all := n_all + coalesce((s ->> 'row_count')::int, 0);
    rws := rws || coalesce((
      select jsonb_agg(jsonb_build_object('location_id', r -> 'location_id', 'outlet_bn', r ->> 'location_bn', 'outlet_en', r ->> 'location_en', 'item_id', r -> 'item_id', 'item_code', r ->> 'item_code',
               'item_bn', r ->> 'item_bn', 'item_en', r ->> 'item_en', 'unit', r ->> 'unit',
               'opening_qty', (r ->> 'opening_qty')::numeric,
               'in_qty', round(coalesce((r ->> 'production_qty')::numeric, 0) + coalesce((r ->> 'purchases_qty')::numeric, 0) + coalesce((r ->> 'transfer_in_qty')::numeric, 0) + coalesce((r ->> 'give_back_qty')::numeric, 0), 4),
               'out_qty', round(coalesce((r ->> 'used_qty')::numeric, 0) + coalesce((r ->> 'sales_qty')::numeric, 0) + coalesce((r ->> 'wastage_qty')::numeric, 0) + coalesce((r ->> 'transit_loss_qty')::numeric, 0) + coalesce((r ->> 'transfer_out_qty')::numeric, 0), 4),
               'adjust_qty', (r ->> 'adjustments_qty')::numeric, 'closing_qty', (r ->> 'closing_qty')::numeric,
               'check_qty', round(coalesce((r ->> 'opening_qty')::numeric, 0) + coalesce((r ->> 'production_qty')::numeric, 0) + coalesce((r ->> 'purchases_qty')::numeric, 0) + coalesce((r ->> 'transfer_in_qty')::numeric, 0)
                     + coalesce((r ->> 'give_back_qty')::numeric, 0) - coalesce((r ->> 'used_qty')::numeric, 0) - coalesce((r ->> 'sales_qty')::numeric, 0) - coalesce((r ->> 'wastage_qty')::numeric, 0)
                     - coalesce((r ->> 'transit_loss_qty')::numeric, 0) - coalesce((r ->> 'transfer_out_qty')::numeric, 0) + coalesce((r ->> 'adjustments_qty')::numeric, 0) - coalesce((r ->> 'closing_qty')::numeric, 0), 4),
               'balance_qty', (r ->> 'balance_qty')::numeric, 'variance_qty', (r ->> 'variance_qty')::numeric, 'flags', r -> 'flags',
               'status', case when r -> 'flags' @> '"unbalanced"' then 'unbalanced' when r -> 'flags' @> '"variance"' then 'variance' when r -> 'flags' @> '"negative"' then 'negative' else 'ok' end,
               'closing_value', r -> 'closing_value'))
        from jsonb_array_elements(s -> 'rows') r
       where not p_issues_only or r -> 'flags' @> '"unbalanced"' or r -> 'flags' @> '"variance"' or r -> 'flags' @> '"negative"'), '[]'::jsonb);
  end loop;
  if trunc then notes := notes || public._rpt131_note('truncated', 'More than 5000 rows for one place: narrow the filters (category / item).', '৫০০০-এর বেশি সারি: ফিল্টার ছোট করুন।'); end if;
  if not public.biz_cost_ok() then notes := notes || public._rpt131_note('cost_hidden', 'Stock value is hidden for your role.', 'স্টকের দাম আপনার ভূমিকার জন্য লুকানো।'); end if;
  cols := '[{"k":"item","bn":"আইটেম","en":"Item","t":"text"},{"k":"outlet","bn":"আউটলেট","en":"Outlet","t":"text"},{"k":"opening_qty","bn":"শুরু","en":"Opening","t":"qty"},{"k":"in_qty","bn":"আসা","en":"In","t":"qty"},
            {"k":"out_qty","bn":"যাওয়া","en":"Out","t":"qty"},{"k":"adjust_qty","bn":"সমন্বয়","en":"Adjust","t":"qty"},{"k":"closing_qty","bn":"শেষ","en":"Closing","t":"qty"},
            {"k":"check_qty","bn":"চেক","en":"Check","t":"qty"},{"k":"variance_qty","bn":"ভেরিয়েন্স","en":"Variance","t":"qty"},{"k":"closing_value","bn":"শেষ দাম","en":"Closing value","t":"money","sum":true,"cost":true},
            {"k":"status","bn":"স্ট্যাটাস","en":"Status","t":"status"}]'::jsonb;
  fin := public._rpt131_finish(rws, array['closing_value'], p_search, p_sort, p_page, p_size, 'item_code:asc');
  return public._rpt131_env('rpt131_stock_recon', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'category', cat, 'item', p_item, 'issues_only', p_issues_only, 'search', p_search), cols, fin, notes,
           jsonb_build_object('summary', jsonb_build_object('lines', n_all, 'unbalanced', n_unb, 'with_variance', n_var), 'truncated', trunc));
end $fn$;

-- ---------- 5. wastage by reason / item / outlet / day / status / document ----------
create or replace function public.rpt131_wastage(p_from date default null, p_to date default null, p_locs int[] default null, p_group text default 'reason', p_status text default 'all',
                                                p_category text default null, p_item uuid default null, p_search text default null, p_sort text default null,
                                                p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; g text := lower(btrim(coalesce(p_group, 'reason'))); st text := lower(btrim(coalesce(p_status, 'all'))); notes jsonb := '[]'::jsonb; rws jsonb; fin jsonb; cols jsonb;
        cost_ok boolean; cat text := nullif(btrim(coalesce(p_category, '')), ''); dimx text; lb text; le text; a_w bigint; books_w numeric; reg_w numeric; defsort text;
begin
  if not public._rpt131_gate('stock') then return public._rpt131_off('rpt131_wastage'); end if;
  if g not in ('reason', 'item', 'outlet', 'day', 'status', 'doc') then raise exception 'bad_group'; end if;
  if st not in ('all', 'posted', 'pending', 'rejected', 'cancelled', 'reversed') then raise exception 'bad_status'; end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  locs := public._rpt131_locs(p_locs);
  cost_ok := public.rpt_cost_ok();
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_wastage', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'group', g), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'entries:desc'), notes);
  end if;
  notes := notes || public._rpt131_note('basis', 'Posted = already taken out of stock. Pending / rejected / cancelled requests did not change stock and carry no value. Value = quantity x the cost in the stock ledger at the time; a posted entry whose cost is not known is counted as "cost unknown", never as 0.', 'Posted = স্টক থেকে কাটা। Pending/rejected/cancelled স্টক বদলায়নি, দাম নেই। দাম = পরিমাণ x লেজারের খরচ; খরচ অজানা হলে "cost unknown"।');
  if g in ('reason', 'outlet', 'day', 'status') then notes := notes || public._rpt131_note('no_qty_total', 'Quantities are shown per item only; they are not added across different units.', 'পরিমাণ শুধু আইটেম ধরে; ভিন্ন একক যোগ করা হয় না।'); end if;
  if not cost_ok then notes := notes || public._rpt131_note('cost_hidden', 'Value columns are hidden for your role.', 'দামের কলাম আপনার ভূমিকার জন্য লুকানো।'); end if;
  dimx := case g when 'reason' then 'w.rc' when 'item' then 'w.item_id::text' when 'outlet' then 'w.loc::text' when 'day' then 'w.d::text' when 'status' then 'w.fstatus' else 'w.doc_id' end;
  lb := case g when 'reason' then 'coalesce(max(o.label_bn), w.rc)' when 'item' then 'max(i.name_bn)' when 'outlet' then 'max(lo.name_bn)' when 'doc' then $$max(i.name_bn)$$ else dimx end;
  le := case g when 'reason' then 'coalesce(max(o.label_en), w.rc)' when 'item' then 'coalesce(max(i.name_en), max(i.name_bn))' when 'outlet' then 'coalesce(max(lo.name_en), max(lo.name_bn))' when 'doc' then $$coalesce(max(i.name_en), max(i.name_bn))$$ else dimx end;
  defsort := case g when 'day' then 'dim:asc' when 'doc' then 'at:desc' else 'entries:desc' end;
  execute format($q$
    with w0 as (
      select 'posted'::text st, x.id::text doc_id, x.item_id, x.location_id loc, x.qty, x.reason_code rc, x.made_at at_, coalesce(nullif(btrim(x.created_staff), ''), '-') staff, x.note, l.unit_cost uc,
             exists (select 1 from public.stock_ledger rv where rv.reverses_id = x.ledger_id) rev
        from public.stock_wastage x left join public.stock_ledger l on l.id = x.ledger_id
       where (x.made_at at time zone 'Asia/Dhaka')::date between $1 and $2 and x.location_id = any ($3)
      union all
      select r.status, r.id::text, r.item_id, r.location_id, r.qty, r.reason_code, r.requested_at, coalesce(nullif(btrim(r.requested_staff), ''), '-'), r.note, null::numeric, false
        from public.wastage_requests r
       where r.status in ('pending', 'rejected', 'cancelled') and (r.requested_at at time zone 'Asia/Dhaka')::date between $1 and $2 and r.location_id = any ($3)),
    w as (
      select w0.*, (w0.at_ at time zone 'Asia/Dhaka')::date d, case when w0.rev then 'reversed' else w0.st end fstatus from w0
        join public.items i on i.id = w0.item_id where ($4::uuid is null or w0.item_id = $4) and ($5::text is null or i.category = $5)),
    a as (
      select %s as dim, %s lbn, %s len, count(*) entries, count(distinct w.item_id) items,
             case when %L = 'item' or %L = 'doc' then sum(w.qty) end qty, max(i.unit) unit,
             sum(w.qty * w.uc) filter (where w.fstatus = 'posted' and coalesce(w.uc, 0) > 0) value, count(*) filter (where w.fstatus = 'posted' and coalesce(w.uc, 0) <= 0) cost_unknown,
             max(w.at_) at_, max(w.fstatus) fstatus, max(w.staff) staff, max(w.note) note, max(w.rc) rc, max(w.loc) loc
        from w join public.items i on i.id = w.item_id left join public.locations lo on lo.id = w.loc
        left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.rc
       where %L = 'all' or w.fstatus = %L
       group by %s)
    select coalesce(jsonb_agg(jsonb_build_object('dim', a.dim, 'label_bn', a.lbn, 'label_en', a.len, 'entries', a.entries, 'items', a.items, 'qty', round(a.qty, 4), 'unit', a.unit,
             'value', case when %L then round(a.value, 2) end, 'cost_unknown', case when %L then a.cost_unknown end, 'at', a.at_, 'status', a.fstatus, 'staff', a.staff, 'note', a.note,
             'reason', a.rc, 'loc', a.loc) order by a.dim), '[]'::jsonb) from a$q$,
    dimx, lb, le, g, g, st, st, case g when 'doc' then 'w.doc_id, w.rc' else dimx end, cost_ok, cost_ok) into rws using dd.d1, dd.d2, locs, p_item, cat;
  if cost_ok and public._acct_view() then
    select account_id into a_w from public.acct_mappings where key = 'wastage';
    select round(coalesce(sum(l.debit - l.credit), 0), 2) into books_w from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
     where l.account_id = a_w and e.entry_date between dd.d1 and dd.d2 and l.location_id = any (locs);
    select round(coalesce(sum(x.qty * l.unit_cost) filter (where coalesce(l.unit_cost, 0) > 0 and not exists (select 1 from public.stock_ledger rv where rv.reverses_id = x.ledger_id)), 0), 2) into reg_w
      from public.stock_wastage x left join public.stock_ledger l on l.id = x.ledger_id
     where (x.made_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and x.location_id = any (locs);
  end if;
  cols := jsonb_build_array(jsonb_build_object('k', 'label', 'bn', 'ভাগ', 'en', 'Group', 't', 'text'), '{"k":"entries","bn":"এন্ট্রি","en":"Entries","t":"int","sum":true}'::jsonb,
    '{"k":"items","bn":"আইটেম","en":"Items","t":"int"}'::jsonb, '{"k":"qty","bn":"পরিমাণ","en":"Qty","t":"qty"}'::jsonb,
    '{"k":"value","bn":"দাম","en":"Value","t":"money","sum":true,"cost":true}'::jsonb, '{"k":"cost_unknown","bn":"খরচ অজানা","en":"Cost unknown","t":"int","sum":true,"cost":true}'::jsonb,
    '{"k":"status","bn":"স্ট্যাটাস","en":"Status","t":"status"}'::jsonb);
  fin := public._rpt131_finish(rws, array['entries', 'value', 'cost_unknown'], p_search, p_sort, p_page, p_size, defsort);
  return public._rpt131_env('rpt131_wastage', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'group', g, 'status', st, 'category', cat, 'item', p_item, 'search', p_search), cols, fin, notes,
           jsonb_build_object('tie_out', case when cost_ok and public._acct_view() then jsonb_build_object('posted_value', reg_w, 'books_wastage_loss', books_w, 'gap', round(coalesce(reg_w, 0) - coalesce(books_w, 0), 2)) end));
end $fn$;

-- ---------- 6. cash book and day close ----------
create or replace function public.rpt131_cash_close(p_from date default null, p_to date default null, p_locs int[] default null, p_search text default null, p_sort text default null,
                                                   p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare dd record; locs int[]; notes jsonb := '[]'::jsonb; rws jsonb; fin jsonb; cols jsonb; books boolean; a_c bigint; a_sh bigint; open_t numeric; net_t numeric; nsheets int := 0;
begin
  if not public._rpt131_gate('cash') then return public._rpt131_off('rpt131_cash_close'); end if;
  select * into dd from public._rpt131_dates(p_from, p_to);
  locs := public._rpt131_locs(p_locs);
  books := public._acct_view();
  if dd.defaulted then notes := notes || public._rpt131_note('default_period', 'No period given: this month to date.', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত।'); end if;
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_cash_close', jsonb_build_object('from', dd.d1, 'to', dd.d2), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'd:desc'), notes);
  end if;
  select account_id into a_c from public.acct_mappings where key = 'pay_cash';
  select account_id into a_sh from public.acct_mappings where key = 'cash_short';
  if not books then notes := notes || public._rpt131_note('books_hidden', 'You may not view the accounts: the cash book columns (opening, in, out, closing, books cash) are not shown.', 'আপনি হিসাব দেখতে পারেন না: ক্যাশ বইয়ের কলাম দেখানো হয়নি।'); end if;
  notes := notes || public._rpt131_note('basis', 'Register cash = cash taken with bills + cash dues collected - cash refunds, from the sales records. Books cash = what the journal holds on the cash account for sales, collections and returns. The gap is cash not yet posted. Counted cash comes from the daily showroom sheet (14-1); a day with no sheet shows "no sheet", not 0. A sale voided after it was posted is reversed on the void date, so its gap shows on both days and nets to 0.', 'রেজিস্টার ক্যাশ = বিলের ক্যাশ + আদায় - ক্যাশ ফেরত। খাতা ক্যাশ = জার্নালে। পার্থক্য = এখনো পোস্ট হয়নি। গোনা ক্যাশ দৈনিক শিট (১৪-১) থেকে; শিট না থাকলে "no sheet"।');
  with sc as (
      select s.location_id loc, s.sale_date d, sum(p.amount) v from public.sale_payments p join public.sales s on s.id = p.sale_id
       where p.kind = 'sale' and not p.voided and s.status = 'done' and p.mode = 'cash' and s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs) group by 1, 2),
    cc as (
      select p.location_id loc, (p.paid_at at time zone 'Asia/Dhaka')::date d, sum(p.amount) v from public.sale_payments p
       where p.kind = 'collection' and not p.voided and p.mode = 'cash' and (p.paid_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and p.location_id = any (locs) group by 1, 2),
    cr as (
      select r.location_id loc, (r.created_at at time zone 'Asia/Dhaka')::date d, sum(r.refund_amount) v from public.sale_returns r
       where r.status = 'done' and r.refund_mode = 'cash' and (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs) group by 1, 2),
    nc as (
      select z.loc, z.d, sum(z.v) v from (
        select s.location_id loc, s.sale_date d, p.amount v from public.sale_payments p join public.sales s on s.id = p.sale_id
         where p.kind = 'sale' and not p.voided and s.status = 'done' and p.mode <> 'cash' and s.sale_date between dd.d1 and dd.d2 and s.location_id = any (locs)
        union all select p.location_id, (p.paid_at at time zone 'Asia/Dhaka')::date, p.amount from public.sale_payments p
         where p.kind = 'collection' and not p.voided and p.mode <> 'cash' and (p.paid_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and p.location_id = any (locs)
        union all select r.location_id, (r.created_at at time zone 'Asia/Dhaka')::date, -r.refund_amount from public.sale_returns r
         where r.status = 'done' and r.refund_mode <> 'cash' and (r.created_at at time zone 'Asia/Dhaka')::date between dd.d1 and dd.d2 and r.location_id = any (locs)) z group by 1, 2),
    jb as (
      select l.location_id loc, e.entry_date d, sum(l.debit) cin, sum(l.credit) cout,
             sum(l.debit - l.credit) filter (where e.source_type in ('sale', 'collection', 'sale_return')) sales_net
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where books and l.account_id = a_c and e.entry_date between dd.d1 and dd.d2 and l.location_id = any (locs) group by 1, 2),
    op as (
      select l.location_id loc, sum(l.debit - l.credit) v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where books and l.account_id = a_c and e.entry_date < dd.d1 and l.location_id = any (locs) group by 1),
    sh as (
      select e.location_id loc, e.entry_date d, count(*) sheets,
             sum(coalesce((select sum(public._r2_num(f -> 'amount')) from jsonb_array_elements(case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end) f where f ->> 'code' = 'cash_short_over'), 0)) so
        from public.entries e where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between dd.d1 and dd.d2 and e.location_id = any (locs) group by 1, 2),
    bs as (
      select l.location_id loc, e.entry_date d, sum(l.debit - l.credit) v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where books and l.account_id = a_sh and e.entry_date between dd.d1 and dd.d2 and l.location_id = any (locs) group by 1, 2),
    keys as (select loc, d from sc union select loc, d from cc union select loc, d from cr union select loc, d from nc union select loc, d from jb union select loc, d from sh union select loc, d from bs),
    r as (
      select k.loc, k.d, coalesce(sc.v, 0) sales_cash, coalesce(cc.v, 0) coll_cash, coalesce(cr.v, 0) ref_cash, coalesce(nc.v, 0) noncash, jb.cin, jb.cout, jb.sales_net, sh.sheets, sh.so, bs.v bshort,
             coalesce(op.v, 0) + coalesce(sum(coalesce(jb.cin, 0) - coalesce(jb.cout, 0)) over (partition by k.loc order by k.d rows between unbounded preceding and 1 preceding), 0) opening
        from keys k left join sc on sc.loc = k.loc and sc.d = k.d left join cc on cc.loc = k.loc and cc.d = k.d left join cr on cr.loc = k.loc and cr.d = k.d left join nc on nc.loc = k.loc and nc.d = k.d
        left join jb on jb.loc = k.loc and jb.d = k.d left join sh on sh.loc = k.loc and sh.d = k.d left join bs on bs.loc = k.loc and bs.d = k.d left join op on op.loc = k.loc)
  select coalesce(jsonb_agg(jsonb_build_object('d', r.d, 'loc', r.loc, 'outlet_bn', lo.name_bn, 'outlet_en', coalesce(lo.name_en, lo.name_bn),
           'sales_cash', round(r.sales_cash, 2), 'collections_cash', round(r.coll_cash, 2), 'refunds_cash', round(r.ref_cash, 2),
           'expected_cash', round(r.sales_cash + r.coll_cash - r.ref_cash, 2), 'noncash_net', round(r.noncash, 2),
           'opening', case when books then round(r.opening, 2) end, 'cash_in', case when books then round(coalesce(r.cin, 0), 2) end, 'cash_out', case when books then round(coalesce(r.cout, 0), 2) end,
           'closing', case when books then round(r.opening + coalesce(r.cin, 0) - coalesce(r.cout, 0), 2) end,
           'books_sales_cash', case when books then round(coalesce(r.sales_net, 0), 2) end,
           'unposted_gap', case when books then round(r.sales_cash + r.coll_cash - r.ref_cash - coalesce(r.sales_net, 0), 2) end,
           'sheets', coalesce(r.sheets, 0), 'sheet_short_over', case when r.sheets is null then null else round(r.so, 2) end,
           'books_cash_short', case when books then round(coalesce(r.bshort, 0), 2) end,
           'flag', case when books and abs(r.sales_cash + r.coll_cash - r.ref_cash - coalesce(r.sales_net, 0)) > 0.005 then 'books_differ'
                        when r.sheets is null and (r.sales_cash + r.coll_cash) > 0 then 'no_sheet' when r.so < -0.005 then 'short' when r.so > 0.005 then 'over' end)), '[]'::jsonb),
         coalesce(sum(r.sheets), 0)
    into rws, nsheets from r join public.locations lo on lo.id = r.loc;
  if books then
    select coalesce(sum(v), 0) into open_t from (select l.location_id, sum(l.debit - l.credit) v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
        where l.account_id = a_c and e.entry_date < dd.d1 and l.location_id = any (locs) group by 1) z;
    select coalesce(sum(l.debit - l.credit), 0) into net_t from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
     where l.account_id = a_c and e.entry_date between dd.d1 and dd.d2 and l.location_id = any (locs);
  end if;
  if nsheets = 0 then notes := notes || public._rpt131_note('no_day_close_sheet', 'No daily showroom sheet (14-1) was submitted in this period: counted cash and the short / over figure are data needed.', 'এই সময়ে কোনো দৈনিক শিট (১৪-১) জমা হয়নি: গোনা ক্যাশ ও কম/বেশি = তথ্য দরকার।'); end if;
  cols := '[{"k":"d","bn":"তারিখ","en":"Date","t":"date"},{"k":"outlet","bn":"আউটলেট","en":"Outlet","t":"text"},{"k":"opening","bn":"শুরু (খাতা)","en":"Opening (books)","t":"money"},
            {"k":"expected_cash","bn":"হওয়ার কথা (রেজিস্টার)","en":"Expected (register)","t":"money","sum":true},{"k":"books_sales_cash","bn":"খাতার বিক্রির ক্যাশ","en":"Books sales cash","t":"money","sum":true},
            {"k":"unposted_gap","bn":"পোস্ট হয়নি","en":"Not yet posted","t":"money","sum":true},{"k":"cash_in","bn":"ক্যাশ ঢুকেছে","en":"Cash in","t":"money","sum":true},{"k":"cash_out","bn":"ক্যাশ বেরিয়েছে","en":"Cash out","t":"money","sum":true},
            {"k":"closing","bn":"শেষ (খাতা)","en":"Closing (books)","t":"money"},{"k":"sheet_short_over","bn":"শিটে কম(-)/বেশি(+)","en":"Sheet short(-)/over(+)","t":"money","sum":true},
            {"k":"books_cash_short","bn":"খাতায় কম","en":"Books short","t":"money","sum":true},{"k":"flag","bn":"চিহ্ন","en":"Flag","t":"status"}]'::jsonb;
  fin := public._rpt131_finish(rws, array['sales_cash', 'collections_cash', 'refunds_cash', 'expected_cash', 'noncash_net', 'cash_in', 'cash_out', 'books_sales_cash', 'unposted_gap', 'sheet_short_over', 'books_cash_short'], p_search, p_sort, p_page, p_size, 'd:desc');
  return public._rpt131_env('rpt131_cash_close', jsonb_build_object('from', dd.d1, 'to', dd.d2, 'locs', p_locs, 'search', p_search), cols, fin, notes,
           jsonb_build_object('summary', jsonb_build_object('opening_total', case when books then round(open_t, 2) end, 'net_movement', case when books then round(net_t, 2) end,
                                                          'closing_total', case when books then round(open_t + net_t, 2) end, 'sheets', nsheets), 'books_visible', books));
end $fn$;

-- ---------- 7. receivable / payable ageing with the books tie-out ----------
create or replace function public.rpt131_ageing(p_kind text default 'receivable', p_as_of date default null, p_locs int[] default null, p_search text default null, p_sort text default null,
                                               p_page int default 1, p_size int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as
$fn$
declare kd text := lower(btrim(coalesce(p_kind, 'receivable'))); asof date := coalesce(p_as_of, public._today()); locs int[]; notes jsonb := '[]'::jsonb; rws jsonb; fin jsonb; cols jsonb;
        bk int[]; bt text; i int; lo int; hi int; bsel text := ''; bcols jsonb := '[]'::jsonb; books boolean; a_x bigint; gl numeric; reg numeric := 0; adv numeric := 0; n_unposted int; v_unposted numeric; n_ucol int := 0; v_ucol numeric := 0; v_ucred numeric := 0;
        allp boolean; sql_ text;
begin
  if kd not in ('receivable', 'payable') then raise exception 'bad_kind'; end if;
  if not public._rpt131_gate(case kd when 'receivable' then 'customers' else 'purchase' end) then return public._rpt131_off('rpt131_ageing'); end if;
  if asof > public._today() or asof < date '2000-01-01' then raise exception 'bad_range'; end if;
  locs := public._rpt131_locs(p_locs);
  books := public._acct_view();
  if cardinality(locs) = 0 then
    notes := notes || public._rpt131_note('no_location', 'No place is open to you.', 'কোনো লোকেশন আপনার জন্য খোলা নেই।');
    return public._rpt131_env('rpt131_ageing', jsonb_build_object('kind', kd, 'as_of', asof), '[]'::jsonb, public._rpt131_finish('[]'::jsonb, '{}'::text[], null, null, 1, 50, 'balance:desc'), notes);
  end if;
  -- age buckets come from the rule report_aging_buckets (days, ascending, e.g. 30,60,90): no built-in values
  bt := nullif(btrim(coalesce(public.rule_txt('report_aging_buckets'), '')), '');
  if bt is not null and bt ~ '^[0-9]+(\s*,\s*[0-9]+){0,7}$' then bk := string_to_array(regexp_replace(bt, '\s', '', 'g'), ',')::int[]; end if;
  if bk is not null then
    for i in 2..cardinality(bk) loop if bk[i] <= bk[i - 1] then bk := null; exit; end if; end loop;
  end if;
  if bk is null then notes := notes || public._rpt131_note('data_needed', 'The age buckets are not set (rule report_aging_buckets, e.g. 30,60,90): only the total and the oldest age are shown.', 'বয়সের ভাগ নিয়মে (report_aging_buckets) লেখা নেই: শুধু মোট ও সবচেয়ে পুরনো বয়স।'); end if;
  if bk is not null then
    for i in 1..cardinality(bk) + 1 loop
      lo := case when i = 1 then 0 else bk[i - 1] + 1 end; hi := case when i <= cardinality(bk) then bk[i] end;
      bsel := bsel || format(', round(coalesce(sum(%I) filter (where %s), 0), 2) as b%s', 'portion', case when hi is null then format('age >= %s', lo) else format('age between %s and %s', lo, hi) end, i);
      bcols := bcols || jsonb_build_array(jsonb_build_object('k', 'b' || i, 'bn', case when hi is null then lo || '+ দিন' else lo || '-' || hi || ' দিন' end,
                                                             'en', case when hi is null then lo || '+ days' else lo || '-' || hi || ' days' end, 't', 'money', 'sum', true));
    end loop;
  end if;

  if kd = 'receivable' then
    select account_id into a_x from public.acct_mappings where key = 'receivable';
    notes := notes || public._rpt131_note('basis', 'Open bills are cleared oldest first by the dues collected and by the credit given on returns. Money received in advance or credit beyond the bills is shown as "advances", not subtracted from other people. Customer mobile numbers are not shown.', 'খোলা বিল পুরনো থেকে আদায় ও ফেরতের ক্রেডিট দিয়ে মেটে। অগ্রিম আলাদা "advances"। মোবাইল নম্বর দেখানো হয়নি।');
    execute format($q$
      with s as (
        select s.id, s.customer_id, s.sale_date, s.sold_at, s.total - coalesce(pp.v, 0) rem
          from public.sales s left join (select sale_id, sum(amount) v from public.sale_payments where not voided and kind = 'sale' and sale_id is not null
                                           and (paid_at at time zone 'Asia/Dhaka')::date <= $1 group by 1) pp on pp.sale_id = s.id
         where s.status = 'done' and s.customer_id is not null and s.sale_date <= $1 and s.location_id = any ($2)),
      cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0.004),
      cred as (
        select z.customer_id, sum(z.v) v from (
          select p.customer_id, p.amount v from public.sale_payments p where p.kind = 'collection' and not p.voided and p.customer_id is not null
             and (p.paid_at at time zone 'Asia/Dhaka')::date <= $1 and p.location_id = any ($2)
          union all select r.customer_id, r.credit_amount from public.sale_returns r where r.status = 'done' and r.customer_id is not null and r.credit_amount > 0
             and (r.created_at at time zone 'Asia/Dhaka')::date <= $1 and r.location_id = any ($2)) z group by 1),
      tot as (select customer_id, sum(rem) allrem, count(*) bills from cum group by 1),
      pt as (select k.customer_id, $1 - k.sale_date age, greatest(0, least(k.rem, k.cr - coalesce(c.v, 0))) portion from cum k left join cred c on c.customer_id = k.customer_id),
      pc as (select pt.customer_id, round(sum(pt.portion), 2) balance, max(pt.age) filter (where pt.portion > 0) oldest %s from pt group by 1),
      cust as (select customer_id from tot union select customer_id from cred)
      select coalesce(jsonb_agg(jsonb_build_object('id', cu.id, 'name', cu.name, 'balance', round(pc.balance, 2), 'oldest_days', pc.oldest, 'bills', tot.bills %s) order by pc.balance desc) filter (where pc.balance > 0.004), '[]'::jsonb),
             coalesce(sum(pc.balance) filter (where pc.balance > 0.004), 0),
             coalesce(sum(greatest(0, coalesce(cred.v, 0) - coalesce(tot.allrem, 0))), 0)
        from cust x join public.customers cu on cu.id = x.customer_id left join tot on tot.customer_id = x.customer_id left join cred on cred.customer_id = x.customer_id left join pc on pc.customer_id = x.customer_id$q$,
      bsel, (select string_agg(format(', %L, pc.b%s', 'b' || n, n), '') from generate_series(1, case when bk is null then 0 else cardinality(bk) + 1 end) n))
      into rws, reg, adv using asof, locs;
    if books and a_x is not null then
      select round(coalesce(sum(l.debit - l.credit), 0), 2) into gl from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where l.account_id = a_x and e.entry_date <= asof and l.location_id = any (locs);
      select count(*), coalesce(sum(p.amount), 0) into n_ucol, v_ucol from public.sale_payments p
       where p.kind = 'collection' and not p.voided and p.customer_id is not null and (p.paid_at at time zone 'Asia/Dhaka')::date <= asof and p.location_id = any (locs)
         and not exists (select 1 from public.journal_entries e where e.source_type = 'collection' and e.source_id = p.id::text and e.reverses_id is null);
      select coalesce(sum(r.credit_amount), 0) into v_ucred from public.sale_returns r
       where r.status = 'done' and r.customer_id is not null and r.credit_amount > 0 and (r.created_at at time zone 'Asia/Dhaka')::date <= asof and r.location_id = any (locs)
         and not exists (select 1 from public.journal_entries e where e.source_type = 'sale_return' and e.source_id = r.id::text and e.reverses_id is null);
      select count(*), coalesce(sum(s.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided), 0)), 0) into n_unposted, v_unposted
        from public.sales s where s.status = 'done' and s.customer_id is not null and s.sale_date <= asof and s.location_id = any (locs) and s.total > coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided), 0)
         and not exists (select 1 from public.journal_entries e where e.source_type = 'sale' and e.source_id = s.id::text and e.reverses_id is null);
    end if;
    cols := '[{"k":"name","bn":"গ্রাহক","en":"Customer","t":"text"},{"k":"balance","bn":"মোট বাকি","en":"Total due","t":"money","sum":true},{"k":"oldest_days","bn":"সবচেয়ে পুরনো (দিন)","en":"Oldest (days)","t":"int"},{"k":"bills","bn":"বিল","en":"Bills","t":"int"}]'::jsonb || bcols;
    fin := public._rpt131_finish(rws, array['balance'] || coalesce((select array_agg('b' || n) from generate_series(1, case when bk is null then 0 else cardinality(bk) + 1 end) n), '{}'::text[]), p_search, p_sort, p_page, p_size, 'balance:desc');
    return public._rpt131_env('rpt131_ageing', jsonb_build_object('kind', kd, 'as_of', asof, 'locs', p_locs, 'search', p_search), cols, fin, notes,
      jsonb_build_object('tie_out', case when books and a_x is not null then jsonb_build_object('register_dues', round(reg, 2), 'advances', round(adv, 2), 'register_net', round(reg - adv, 2), 'books_receivable', gl,
                                                 'gap', round(reg - adv - gl, 2), 'unposted_bills', n_unposted, 'unposted_value', round(v_unposted, 2),
                                                 'unposted_collections', n_ucol, 'unposted_collections_value', round(v_ucol, 2), 'unposted_return_credit', round(v_ucred, 2),
                                                 'explained', round(v_unposted - v_ucol - v_ucred, 2), 'unexplained', round(reg - adv - gl - (v_unposted - v_ucol - v_ucred), 2)) end, 'books_visible', books and a_x is not null));
  end if;

  -- payable: the supplier open items are as of NOW (the payment allocation is not kept per date)
  if p_as_of is not null and p_as_of <> public._today() then notes := notes || public._rpt131_note('as_of_today', 'Payables are always as of today: the date you gave was ignored.', 'পাওনা সবসময় আজকের হিসাবে: দেওয়া তারিখ ধরা হয়নি।'); end if;
  asof := public._today();
  allp := public._acct_all();
  if not allp then notes := notes || public._rpt131_note('opening_hidden', 'Supplier opening balances have no place and are shown to the owner only.', 'সরবরাহকারীর শুরুর ব্যালেন্সের লোকেশন নেই, শুধু মালিক দেখেন।'); end if;
  select account_id into a_x from public.acct_mappings where key = 'payable';
  notes := notes || public._rpt131_note('basis', 'Open supplier bills after payments, returns and refunds. Age = days since the bill date. Overdue uses the supplier credit days when set.', 'পেমেন্ট, রিটার্ন, রিফান্ড বাদে খোলা বিল। বয়স = বিলের তারিখ থেকে দিন। মেয়াদ = সরবরাহকারীর ক্রেডিট দিন।');
  execute format($q$
    with o as (
      select o.supplier_id, o.bill_date, o.open_amt, s.name, s.credit_days, case when o.bill_date is null then null else $1 - o.bill_date end age
        from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id
       where o.open_amt > 0.004 and (o.location_id = any ($2) or (o.location_id is null and $3))),
    pt as (select o.*, o.open_amt portion from o),
    pc as (select pt.supplier_id, max(pt.name) name, round(sum(pt.portion), 2) balance, max(pt.age) oldest, count(*) bills,
                  round(coalesce(sum(pt.portion) filter (where pt.credit_days is not null and pt.bill_date is not null and pt.bill_date + pt.credit_days < $1), 0), 2) overdue,
                  round(coalesce(sum(pt.portion) filter (where pt.age is null), 0), 2) undated %s
             from pt group by pt.supplier_id)
    select coalesce(jsonb_agg(jsonb_build_object('id', pc.supplier_id, 'name', pc.name, 'balance', pc.balance, 'oldest_days', pc.oldest, 'bills', pc.bills, 'overdue', pc.overdue, 'undated', pc.undated %s) order by pc.balance desc), '[]'::jsonb),
           coalesce(sum(pc.balance), 0)
      from pc$q$,
    case when bk is null then '' else replace(bsel, 'portion', 'portion') end,
    (select string_agg(format(', %L, pc.b%s', 'b' || n, n), '') from generate_series(1, case when bk is null then 0 else cardinality(bk) + 1 end) n))
    into rws, reg using asof, locs, allp;
  if books and a_x is not null then
    select round(coalesce(sum(l.credit - l.debit), 0), 2) into gl from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
     where l.account_id = a_x and e.entry_date <= asof and (l.location_id = any (locs) or (l.location_id is null and allp));
  end if;
  cols := '[{"k":"name","bn":"সরবরাহকারী","en":"Supplier","t":"text"},{"k":"balance","bn":"মোট পাওনা","en":"Total owed","t":"money","sum":true},{"k":"overdue","bn":"মেয়াদ পার","en":"Overdue","t":"money","sum":true},
            {"k":"oldest_days","bn":"সবচেয়ে পুরনো (দিন)","en":"Oldest (days)","t":"int"},{"k":"bills","bn":"বিল","en":"Bills","t":"int"},{"k":"undated","bn":"তারিখহীন (শুরুর)","en":"Undated (opening)","t":"money","sum":true}]'::jsonb || bcols;
  fin := public._rpt131_finish(rws, array['balance', 'overdue', 'undated'] || coalesce((select array_agg('b' || n) from generate_series(1, case when bk is null then 0 else cardinality(bk) + 1 end) n), '{}'::text[]), p_search, p_sort, p_page, p_size, 'balance:desc');
  return public._rpt131_env('rpt131_ageing', jsonb_build_object('kind', kd, 'as_of', asof, 'locs', p_locs, 'search', p_search), cols, fin, notes,
    jsonb_build_object('tie_out', case when books and a_x is not null then jsonb_build_object('register_open', round(reg, 2), 'books_payable', gl, 'gap', round(reg - gl, 2)) end, 'books_visible', books and a_x is not null));
end $fn$;

-- ---------- 8. export log (CSV / print), same right as the other report exports ----------
create or replace function public.rpt131_log_export(p_key text, p_kind text, p_filters jsonb, p_rows integer) returns void
language plpgsql security definer set search_path = public as
$fn$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('rpt131_sales', 'rpt131_sales_recon', 'rpt131_item_profit', 'rpt131_stock_recon', 'rpt131_wastage', 'rpt131_cash_close', 'rpt131_ageing') then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $fn$;

-- ---------- grants ----------
revoke all on function public._rpt131_note(text, text, text, text), public._rpt131_gate(text), public._rpt131_off(text), public._rpt131_locs(int[]), public._rpt131_dates(date, date),
  public._rpt131_finish(jsonb, text[], text, text, int, int, text), public._rpt131_env(text, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.rpt131_catalog(), public.rpt131_sales(date, date, int[], text, text, text, int, int), public.rpt131_sales_recon(date, date, int[], text, text, text, int, int),
  public.rpt131_item_profit(date, date, int[], text, text, uuid, text, text, int, int), public.rpt131_stock_recon(date, date, int[], text, uuid, boolean, text, text, int, int),
  public.rpt131_wastage(date, date, int[], text, text, text, uuid, text, text, int, int), public.rpt131_cash_close(date, date, int[], text, text, int, int),
  public.rpt131_ageing(text, date, int[], text, text, int, int), public.rpt131_log_export(text, text, jsonb, integer) from public, anon;
grant execute on function public.rpt131_catalog(), public.rpt131_sales(date, date, int[], text, text, text, int, int), public.rpt131_sales_recon(date, date, int[], text, text, text, int, int),
  public.rpt131_item_profit(date, date, int[], text, text, uuid, text, text, int, int), public.rpt131_stock_recon(date, date, int[], text, uuid, boolean, text, text, int, int),
  public.rpt131_wastage(date, date, int[], text, text, text, uuid, text, text, int, int), public.rpt131_cash_close(date, date, int[], text, text, int, int),
  public.rpt131_ageing(text, date, int[], text, text, int, int), public.rpt131_log_export(text, text, jsonb, integer) to authenticated;

commit;
