-- Phase 400 (bos400) - REPORTS: RETURNS AND REFUND CONSISTENCY (package RPT-B1, item R1). Paste after phase99. Paste-twice safe. Earlier phase files are not edited.
-- WHY (docs/REPORTS_AUDIT_1.md, defects D1 and D1b): the sales reports of the first report engine (report_run: sales_summary, sales_trend, sales_combined, item_sales, category_sales)
--      and the POS day close ignore sale returns, while the dashboard, the branch P&L and the margin report subtract them (rule reports_net_of_returns). The same day showed two different
--      sales figures. Worse, the POS day close "expected cash in drawer" ignores cash that was handed back to customers, so the drawer looked 400 over.
-- WHAT THIS FILE ADDS (read-only; nothing here writes to a business table, no existing column is changed or removed):
--   1. Three internal views of the DONE returns, shaped like the report fact views so the existing grouping, filters and compare keep working:
--        rpt_ret_b (one row per return), rpt_ret_l (one row per returned item line, with the discount share of the sale taken off, exactly like _cogs_lines72), rpt_ret_p (one row per refund payout).
--      A return is counted on the day it was made (Asia/Dhaka), the same rule as the dashboard (biz_daily, sales_summary). A voided return is not counted.
--   2. _rptb1_agg_wrap: used by the report engine (hook, see docs/integration/RPT-B1.md) to add NEW columns to the grouped reports:
--        sales_summary / sales_trend / sales_combined : returns_amt, net_after_returns
--        item_sales / category_sales                  : returns_amt, returns_qty, net_after_returns, qty_after_returns
--        payment_modes                                : refund_paid (money handed back by that payment mode), net_after_refunds
--      The old columns (net, qty, amount ...) keep exactly today's numbers. net_after_returns follows the rule reports_net_of_returns (default ON): with the rule OFF it equals net
--      and the report says so in a note; returns_amt is still shown because it is a fact.
--   3. _rptb1_day_close_wrap: POS day close gets refund_cash / refund_mobile / refund_card and expected_cash_after_refunds. expected_cash stays as it was. A day with a refund and no sale shows up too.
--   4. _rptb1_notes: the plain notes shown under a report that has the new columns.
--   5. _rptb1_patch: the exact-text patch helper (same design as _w1b_patch, own marker). _rptb1_hooked(): which hook sites are in place.
-- Nothing changes until the integrator runs docs/integration/RPT-B1_hooks.sql (the hooks). With the hooks every old column of every report is identical (proved by supabase/phase400_test.sql).
-- !! Re-pasting phase 9 (report_run, rpt_def, rpt_meas, rpt_agg_build, rpt_raw) removes the bos400 hooks: run docs/integration/RPT-B1_hooks.sql again (it is paste-twice safe).
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.report_run(text,jsonb,text,text,integer,boolean)') is null or to_regprocedure('public.rpt_agg_build(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean)') is null
     or to_regprocedure('public.rpt_raw(text,jsonb,integer[],date,date,boolean,integer[],numeric,date)') is null or to_regclass('public.sale_returns') is null
     or to_regprocedure('public.rpt_meas(text)') is null or to_regprocedure('public.rpt_def(text)') is null or to_regclass('public.report_brand_map') is null then
    raise exception 'phase400 needs the report engine (phase 9) and sale returns (phase 12)';
  end if;
end $g$;

create or replace function public._rptb1_p400_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text (same design as _w1b_patch, marker is a parameter) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist, otherwise the call STOPS and nothing is half changed. Marker already inside = no-op (returns false).
create or replace function public._rptb1_patch(p_fn regprocedure, p_marker text, p_pairs text[]) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if p_marker is null or length(p_marker) < 4 then raise exception 'phase400 patch needs a marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'phase400 patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'phase400 patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;

-- ---------- the three views of done returns ----------
-- rpt_ret_b : one row per done return. Columns are the ones rpt_dims('bill') and rpt_where('bill') read from rpt_bill.
create or replace view public.rpt_ret_b as
select r.id as return_id, r.sale_id, s.receipt,
  (r.created_at at time zone 'Asia/Dhaka')::date as day, r.created_at as sold_at,
  extract(hour from r.created_at at time zone 'Asia/Dhaka')::int as hour,
  extract(dow from (r.created_at at time zone 'Asia/Dhaka')::date)::int as dow,
  r.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
  bm.brand_code, bm.brand_bn, bm.brand_en,
  s.created_staff as staff, 'done'::text as status, s.pay_mode, s.sale_type, s.customer_id, cu.name as customer_name, cu.mobile,
  s.total, r.amount as ret_amt, r.refund_amount, r.credit_amount,
  null::text as void_staff, null::text as void_note, null::text as discount_kind
from public.sale_returns r
join public.sales s on s.id = r.sale_id
join public.locations lo on lo.id = r.location_id
left join public.report_brand_map bm on bm.location_id = r.location_id
left join public.customers cu on cu.id = s.customer_id
where r.status = 'done';

-- rpt_ret_l : one row per returned line. ret_amt = line amount x (return amount / sum of the return's line amounts) = the sale's discount share already taken off (same rule as _cogs_lines72).
create or replace view public.rpt_ret_l as
select r.id as return_id, r.sale_id, s.receipt,
  (r.created_at at time zone 'Asia/Dhaka')::date as day, r.created_at as sold_at,
  extract(hour from r.created_at at time zone 'Asia/Dhaka')::int as hour,
  extract(dow from (r.created_at at time zone 'Asia/Dhaka')::date)::int as dow,
  r.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
  bm.brand_code, bm.brand_bn, bm.brand_en,
  s.created_staff as staff, 'done'::text as status, s.sale_type, s.pay_mode, s.customer_id,
  it.id as item_id, it.code as item_code,
  coalesce(it.name_bn, nullif(e.v ->> 'name', ''), 'Quick sale') as item_name,
  coalesce(it.name_en, it.name_bn, nullif(e.v ->> 'name', ''), 'Quick sale') as item_name_en,
  it.category, coalesce(it.unit, nullif(e.v ->> 'unit', '')) as unit,
  case when it.id is not null then 'listed' else 'quick' end as line_kind,
  q.qty, q.amount * case when la.s > 0 then r.amount / la.s else 1 end as ret_amt,
  s.total as sale_total, null::text as discount_kind
from public.sale_returns r
join public.sales s on s.id = r.sale_id
join public.locations lo on lo.id = r.location_id
left join public.report_brand_map bm on bm.location_id = r.location_id
cross join lateral jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) as e(v)
cross join lateral (select
    case when e.v ->> 'item_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (e.v ->> 'item_id')::uuid end as iid,
    case when e.v ->> 'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v ->> 'qty')::numeric else 0 end as qty,
    case when e.v ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v ->> 'amount')::numeric else 0 end as amount) q
cross join lateral (select coalesce(sum(case when x ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (x ->> 'amount')::numeric end), 0) as s
                    from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) x) la
left join public.items it on it.id = q.iid
where r.status = 'done';

-- rpt_ret_p : one row per money payout of a done return (refund_amount > 0), by the refund mode. Columns are the ones rpt_dims('pay') and rpt_where('pay') read from rpt_pay.
create or replace view public.rpt_ret_p as
select r.id as pay_id, r.sale_id, (r.created_at at time zone 'Asia/Dhaka')::date as day, r.created_at as paid_at,
  extract(hour from r.created_at at time zone 'Asia/Dhaka')::int as hour,
  extract(dow from (r.created_at at time zone 'Asia/Dhaka')::date)::int as dow,
  r.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
  bm.brand_code, bm.brand_bn, bm.brand_en,
  r.created_staff as staff, 'refund'::text as kind, r.refund_mode as mode, r.wallet, r.ref, r.refund_amount as amount, false as voided,
  r.customer_id, cu.name as customer_name, cu.mobile
from public.sale_returns r
join public.locations lo on lo.id = r.location_id
left join public.report_brand_map bm on bm.location_id = r.location_id
left join public.customers cu on cu.id = r.customer_id
where r.status = 'done' and r.refund_amount > 0;

revoke all on public.rpt_ret_b, public.rpt_ret_l, public.rpt_ret_p from public, anon, authenticated;      -- like rpt_bill: only the report functions read them

-- ---------- the wrap used by rpt_agg_build ----------
-- Takes the SQL text of the old grouped query (p_t rows, p_tot totals) and returns the SQL of the same query WITH the new columns. Every old column is passed through untouched.
-- A group that has returns but no sales (a return made on a quiet day) appears as an extra row: the old columns of that row are 0 / empty, the new columns carry the return.
create or replace function public._rptb1_agg_wrap(p_def jsonb, p_gl text[], p_mkeys text[], p_flt jsonb, p_allowed int[], p_from date, p_to date, p_dexpr text, p_ws int, p_fym int,
  p_mobok boolean, p_costok boolean, p_t text, p_tot text) returns jsonb
language plpgsql stable set search_path = public as $$
declare src text := p_def ->> 'src'; al text := case src when 'bill' then 'b' when 'line' then 'f' else 'p' end;
  newk text[] := case src when 'bill' then array['returns_amt', 'net_after_returns'] when 'line' then array['returns_amt', 'returns_qty', 'net_after_returns', 'qty_after_returns']
                          else array['refund_paid', 'net_after_refunds'] end;
  basek text := case src when 'pay' then 'amount' else 'net' end;                          -- the old column the new "after" column starts from
  amtk text := case src when 'pay' then 'refund_paid' else 'returns_amt' end;               -- the new money column
  netk text := case src when 'pay' then 'net_after_refunds' else 'net_after_returns' end;   -- the new "after" column
  rel text := case src when 'bill' then 'public.rpt_ret_b' when 'line' then 'public.rpt_ret_l' else 'public.rpt_ret_p' end;
  net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
  dims jsonb := public.rpt_dims(src); meas jsonb := public.rpt_meas(src);
  allow text[]; w text; g text; c jsonb; dsel text[] := '{}'; dnames text[] := '{}'; n int; mk text; k text; ex text;
  amts text; rq text; rqt text; nsel text; jn text; rows_sel text[] := '{}'; tot_sel text[] := '{}'; extra text[] := array['cogs', 'gp', 'gp_pct', 'uncosted_pct'];
  cost_extra boolean := p_costok and src = 'bill' and coalesce((p_def ->> 'cost_join')::int, 0) = 1;
begin
  if not (p_mkeys && newk) or not (basek = any (p_mkeys)) or (src = 'line' and not ('qty' = any (p_mkeys))) then return jsonb_build_object('t', p_t, 'tot', p_tot); end if;
  allow := coalesce((select array_agg(x) from jsonb_array_elements_text(p_def -> 'allow') x), public.rpt_filters_for(src));
  w := public.rpt_where(src, al, p_flt, p_allowed, p_from, p_to, allow, p_mobok) ->> 'w';      -- the same filters as the main query (locations the caller may see, brand, staff, mode ...)
  foreach g in array p_gl loop
    for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
      dsel := dsel || (public.rpt_tok(c ->> 1, al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(c ->> 0));      -- the same dimension expressions as the main query
      dnames := dnames || (c ->> 0);
    end loop;
  end loop;
  n := cardinality(dnames);
  amts := case src when 'line' then format('coalesce(round(sum(%s.ret_amt), 2), 0) as r_amt, coalesce(round(sum(%s.qty), 3), 0) as r_qty', al, al)
                   when 'bill' then format('coalesce(sum(%s.ret_amt), 0) as r_amt', al) else format('coalesce(sum(%s.amount), 0) as r_amt', al) end;
  rqt := format('select %s from %s %s where %s', amts, rel, al, w);                                       -- the returns of the whole period (totals row)
  rq := format('select %s from %s %s where %s', array_to_string(dsel || amts, ', '), rel, al, w)          -- the returns per group
        || case when n > 0 then ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i) else '' end;
  -- old columns, passed through. A sum / count column of a return-only group is 0 (its own expression starts with coalesce or count); ratios stay empty.
  foreach k in array dnames loop rows_sel := rows_sel || format('coalesce(bq.%I, rq.%I) as %I', k, k, k); end loop;
  foreach mk in array p_mkeys loop
    continue when mk = any (newk);
    ex := coalesce(meas -> mk ->> 'expr', '');
    rows_sel := rows_sel || case when ex like 'coalesce(%' or ex like 'count(%' then format('coalesce(bq.%I, 0) as %I', mk, mk) else format('bq.%I as %I', mk, mk) end;
    tot_sel := tot_sel || format('bq.%I as %I', mk, mk);
  end loop;
  if cost_extra then
    foreach k in array extra loop rows_sel := rows_sel || format('bq.%I as %I', k, k); tot_sel := tot_sel || format('bq.%I as %I', k, k); end loop;
  end if;
  -- the new columns. "after returns" follows the rule reports_net_of_returns; with the rule off it equals the old column.
  nsel := format('coalesce(rq.r_amt, 0) as %I, %s as %I', amtk, case when net_on then format('coalesce(bq.%I, 0) - coalesce(rq.r_amt, 0)', basek) else format('coalesce(bq.%I, 0)', basek) end, netk);
  if src = 'line' then
    nsel := nsel || format(', coalesce(rq.r_qty, 0) as returns_qty, %s as qty_after_returns', case when net_on then 'coalesce(bq.qty, 0) - coalesce(rq.r_qty, 0)' else 'coalesce(bq.qty, 0)' end);
  end if;
  if n > 0 then
    jn := (select string_agg(format('bq.%I = rq.%I', k2, k2), ' and ') from unnest(dnames) k2);      -- dimension columns are never null, so this is a hash join
    return jsonb_build_object(
      't', format('select %s, %s from (%s) bq full join (%s) rq on %s', array_to_string(rows_sel, ', '), nsel, p_t, rq, jn),
      'tot', format('select %s, %s from (%s) bq cross join (%s) rq', array_to_string(tot_sel, ', '), nsel, p_tot, rqt));
  end if;
  return jsonb_build_object(
    't', format('select %s, %s from (%s) bq cross join (%s) rq', array_to_string(rows_sel, ', '), nsel, p_t, rqt),
    'tot', format('select %s, %s from (%s) bq cross join (%s) rq', array_to_string(tot_sel, ', '), nsel, p_tot, rqt));
end $$;

-- ---------- the notes shown under a report that has the new columns ----------
create or replace function public._rptb1_notes(p_def jsonb, p_gl text[], p_mkeys text[]) returns jsonb
language plpgsql stable set search_path = public as $$
declare src text := p_def ->> 'src'; out_ jsonb := '[]'::jsonb;
begin
  if src = 'pay' then
    if not (p_mkeys && array['refund_paid', 'net_after_refunds']) then return out_; end if;
    return out_ || jsonb_build_array(jsonb_build_object('code', 'refund_basis',
      'text_en', 'Refund columns: money handed back to customers for sale returns, on the day of the return, by the refund mode. Returns settled against a customer due are not a payout and are not here.',
      'text_bn', 'ফেরতের কলাম: বিক্রি-ফেরতে গ্রাহককে ফেরত দেওয়া টাকা, ফেরতের দিনে, ফেরতের মাধ্যম অনুযায়ী। বাকির সাথে মেলানো ফেরত টাকা দেওয়া নয়, তাই এখানে নেই।'));
  end if;
  if not (p_mkeys && array['returns_amt', 'net_after_returns']) then return out_; end if;
  out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'returns_basis',
    'text_en', 'Returns columns: goods taken back, with the sale''s discount share taken off, counted on the day of the return (the same rule as the dashboard). Voided returns are not counted.',
    'text_bn', 'ফেরতের কলাম: ফেরত নেওয়া পণ্যের দাম (বিক্রির ছাড়ের অংশ বাদে), ফেরতের দিনে ধরা হয় (ড্যাশবোর্ডের মতোই)। বাতিল ফেরত ধরা হয় না।'));
  if not coalesce(public.rule_on('reports_net_of_returns'), true) then
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'returns_not_netted',
      'text_en', 'The setting "Sales figures are net of sale returns" is off: the "after returns" columns equal the old columns. Returns are shown only for information.',
      'text_bn', '"বিক্রির হিসাব থেকে বিক্রি-ফেরত বাদ" নিয়মটি বন্ধ: "ফেরত বাদে" কলাম আগের কলামের সমান। ফেরত শুধু তথ্য হিসেবে দেখানো হলো।'));
  end if;
  return out_;
end $$;

-- ---------- POS day close: the cash that went back to customers ----------
-- p_sql is the old day-close query. The result has every old column unchanged plus refund_cash, refund_mobile, refund_card and expected_cash_after_refunds.
create or replace function public._rptb1_day_close_wrap(p_sql text, p_flt jsonb, p_allowed int[], p_from date, p_to date, p_allow text[], p_mobok boolean) returns text
language plpgsql stable set search_path = public as $$
declare w text := public.rpt_where('pay', 'r', p_flt, p_allowed, p_from, p_to, p_allow, p_mobok) ->> 'w';
begin
  return format($f$select coalesce(z.day, rf.day) as day, coalesce(z.location_id, rf.location_id) as location_id, coalesce(z.location_bn, rf.location_bn) as location_bn,
      coalesce(z.location_en, rf.location_en) as location_en, coalesce(z.bills, 0) as bills, coalesce(z.net, 0) as net, coalesce(z.discount, 0) as discount,
      coalesce(z.void_bills, 0) as void_bills, coalesce(z.void_amt, 0) as void_amt, coalesce(z.due_created, 0) as due_created,
      coalesce(z.cash_in, 0) as cash_in, coalesce(z.mobile_in, 0) as mobile_in, coalesce(z.card_in, 0) as card_in,
      coalesce(z.cash_collections, 0) as cash_collections, coalesce(z.mobile_collections, 0) as mobile_collections, coalesce(z.card_collections, 0) as card_collections,
      coalesce(z.total_in, 0) as total_in, coalesce(z.expected_cash, 0) as expected_cash,
      coalesce(rf.refund_cash, 0) as refund_cash, coalesce(rf.refund_mobile, 0) as refund_mobile, coalesce(rf.refund_card, 0) as refund_card,
      coalesce(z.expected_cash, 0) - coalesce(rf.refund_cash, 0) as expected_cash_after_refunds
    from (%s) z full join (
      select r.day, r.location_id, r.location_bn, r.location_en,
        coalesce(sum(r.amount) filter (where r.mode = 'cash'), 0) as refund_cash,
        coalesce(sum(r.amount) filter (where r.mode = 'mobile'), 0) as refund_mobile,
        coalesce(sum(r.amount) filter (where r.mode = 'card'), 0) as refund_card
      from public.rpt_ret_p r where %s group by 1, 2, 3, 4) rf on rf.day = z.day and rf.location_id = z.location_id$f$, p_sql, w);
end $$;

-- ---------- which hook sites are in place (the integrator and the tests read this) ----------
create or replace function public._rptb1_hooked() returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'rpt_meas', position('bos400' in pg_get_functiondef('public.rpt_meas(text)'::regprocedure)) > 0,
    'rpt_def', position('bos400' in pg_get_functiondef('public.rpt_def(text)'::regprocedure)) > 0,
    'rpt_agg_build', position('bos400' in pg_get_functiondef('public.rpt_agg_build(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean)'::regprocedure)) > 0,
    'rpt_raw', position('bos400' in pg_get_functiondef('public.rpt_raw(text,jsonb,integer[],date,date,boolean,integer[],numeric,date)'::regprocedure)) > 0,
    'report_run', position('bos400' in pg_get_functiondef('public.report_run(text,jsonb,text,text,integer,boolean)'::regprocedure)) > 0);
$$;

revoke all on function public._rptb1_p400_present(), public._rptb1_patch(regprocedure, text, text[]),
  public._rptb1_agg_wrap(jsonb, text[], text[], jsonb, int[], date, date, text, int, int, boolean, boolean, text, text), public._rptb1_notes(jsonb, text[], text[]),
  public._rptb1_day_close_wrap(text, jsonb, int[], date, date, text[], boolean), public._rptb1_hooked() from public, anon, authenticated;
