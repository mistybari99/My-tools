-- Phase 453 (RPT-HUB, part 4): "what changed" and "why did this number change".
--   rpt_hub_metrics()                      the figures the hub can compare / drill, with a flag for what the caller may see
--   rpt_hub_compare(a_from,a_to,b_from,b_to,loc)   the same figures for two periods, change and percent, biggest movers by outlet
--   rpt_hub_drill(metric,from,to,loc,group,limit,offset)   the transactions behind one figure, with their sum (equals the figure) and a breakdown
-- READ ONLY. The figures are summed from the same event set as the day replay (phase 451), so a one-day compare equals that day's totals (tested).
-- Safe to paste twice. Needs phases 450-451.
do $$ begin if to_regprocedure('public._rh_events(date,date,int,text[],text,text,boolean)') is null then raise exception 'rpthub_needs_phase451'; end if; end $$;

-- one row per (figure, kind of event) : how the event adds to the figure.  v: amount | neg_amount | count | discount
create or replace function public._rh_metric_defs() returns table (metric text, kind text, stat text[], v text, area text, label_en text, label_bn text, money boolean)
language sql stable security definer set search_path = public as $$
  select * from (values
    ('sales_total',      'sale',             array['done'],               'amount',     'sales',    'Sales (before returns)',               'বিক্রি (ফেরতের আগে)', true),
    ('sales_discount',   'sale',             array['done'],               'discount',   'sales',    'Discounts given',                      'ডিসকাউন্ট', true),
    ('sales_count',      'sale',             array['done'],               'count',      'sales',    'Number of sales',                      'বিক্রির সংখ্যা', false),
    ('returns_total',    'return',           array['done'],               'amount',     'sales',    'Returns and refunds',                  'ফেরত', true),
    ('net_sales',        'sale',             array['done'],               'amount',     'sales',    'Net sales (after returns)',            'নিট বিক্রি (ফেরত বাদে)', true),
    ('net_sales',        'return',           array['done'],               case when coalesce(public.rule_on('reports_net_of_returns'), true) then 'neg_amount' else 'zero' end, 'sales', 'Net sales (after returns)', 'নিট বিক্রি (ফেরত বাদে)', true),
    ('void_count',       'void',             array['*'],                'count',      'sales',    'Voided sales',                         'বাতিল বিক্রি', false),
    ('void_total',       'void',             array['*'],                'amount',     'sales',    'Value of voided sales',                'বাতিল বিক্রির টাকা', true),
    ('collections_total','collection',       array['done'],               'amount',     'customers','Dues collected',                       'বাকি আদায়', true),
    ('expense_total',    'expense',          array['done'],               'amount',     'expense',  'Expenses (quick + vouchers)',          'খরচ (দ্রুত + ভাউচার)', true),
    ('expense_total',    'voucher',          array['submitted','approved'],'amount',    'expense',  'Expenses (quick + vouchers)',          'খরচ (দ্রুত + ভাউচার)', true),
    ('purchases_total',  'purchase',         array['posted'],             'amount',     'purchase', 'Purchases (after purchase returns)',   'ক্রয় (ক্রয় ফেরত বাদে)', true),
    ('purchases_total',  'purchase_return',  array['posted'],             'neg_amount', 'purchase', 'Purchases (after purchase returns)',   'ক্রয় (ক্রয় ফেরত বাদে)', true),
    ('supplier_paid',    'supplier_payment', array['done'],               'amount',     'purchase', 'Paid to suppliers',                    'সরবরাহকারীকে পরিশোধ', true),
    ('wastage_value',    'wastage',          array['done'],               'amount',     'cost',     'Wastage value',                        'অপচয়ের মূল্য', true),
    ('transit_short_value','transit_short',  null::text[],                'amount',     'cost',     'Goods short in transit (value)',       'পথে কম মালের মূল্য', true),
    ('cash_short_total', 'cash_short',       null::text[],                'amount',     'cash',     'Cash short',                           'ক্যাশ কম', true),
    ('other_income_total','other_income',    null::text[],                'amount',     'cash',     'Other income',                         'অন্যান্য আয়', true),
    ('exceptions_count', 'exception',        array['*'],                'count',      'control',  'Exceptions raised',                    'ব্যতিক্রম', false),
    ('production_runs',  'production',       array['done'],               'count',      'stock',    'Production runs',                      'উৎপাদন ব্যাচ', false),
    ('count_adjustments','count_adjust',     array['*'],                'count',      'stock',    'Stock count adjustments',              'গণনার সমন্বয়', false),
    ('advances_total',   'advance',          array['active'],             'amount',     'payroll',  'Staff advances',                       'কর্মীর অগ্রিম', true),
    ('salary_paid',      'payroll',          array['done'],               'amount',     'payroll',  'Salary paid',                          'বেতন পরিশোধ', true)
  ) t(metric, kind, stat, v, area, label_en, label_bn, money);
$$;


create or replace function public._rh_stat_ok(p_stat text[], p_status text) returns boolean language sql immutable as $$
  select case when p_stat is null then coalesce(p_status, 'done') not in ('void', 'cancelled', 'rejected') when '*' = any (p_stat) then true else p_status = any (p_stat) end;
$$;

create or replace function public.rpt_hub_metrics() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('key', m.metric, 'label_en', m.label_en, 'label_bn', m.label_bn, 'money', m.money, 'area', m.area, 'allowed', public._rh_area_ok(m.area)) order by m.o)
     from (select d.metric, min(d.label_en) label_en, min(d.label_bn) label_bn, bool_or(d.money) money, min(d.area) area, min(row_number) o
             from (select x.*, row_number() over () from public._rh_metric_defs() x) d group by d.metric) m), '[]'::jsonb);
end $$;

-- value of one event for one figure
create or replace function public._rh_val(p_v text, p_amount numeric, p_detail jsonb) returns numeric language sql immutable as $$
  select case p_v when 'amount' then p_amount when 'neg_amount' then -p_amount when 'count' then 1::numeric when 'zero' then 0::numeric
                  when 'discount' then case when p_detail ->> 'discount' ~ '^-?[0-9.]+$' then (p_detail ->> 'discount')::numeric end end;
$$;

create or replace function public.rpt_hub_compare(p_a_from date, p_a_to date, p_b_from date, p_b_to date, p_loc int default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare locs int[] := public._rh_locs(); kinds text[]; res jsonb; hidden jsonb := '[]'::jsonb; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_a_from is null or p_a_to is null or p_b_from is null or p_b_to is null or p_a_to < p_a_from or p_b_to < p_b_from or p_a_to - p_a_from > 3700 or p_b_to - p_b_from > 3700 then raise exception 'bad_range'; end if;
  if p_loc is not null and not (p_loc = any (locs)) then raise exception 'not allowed'; end if;
  select array_agg(distinct d.kind) into kinds from public._rh_metric_defs() d where public._rh_area_ok(d.area);
  select coalesce(jsonb_agg(distinct d.metric), '[]'::jsonb) into hidden from public._rh_metric_defs() d where not public._rh_area_ok(d.area);
  if kinds is null then
    return jsonb_build_object('generated_at', now(), 'a', jsonb_build_object('from', p_a_from, 'to', p_a_to), 'b', jsonb_build_object('from', p_b_from, 'to', p_b_to), 'metrics', '[]'::jsonb, 'hidden_metrics', hidden, 'masked', public._rh_masked(), 'notes', '[]'::jsonb);
  end if;
  with ea as materialized (select * from public._rh_events(p_a_from, p_a_to, p_loc, kinds)),
       eb as materialized (select * from public._rh_events(p_b_from, p_b_to, p_loc, kinds)),
       d as (select * from public._rh_metric_defs() x where public._rh_area_ok(x.area)),
       va as (select m.metric, e.loc, sum(public._rh_val(m.v, e.amount, e.detail)) val from d m join ea e on e.kind = m.kind and public._rh_stat_ok(m.stat, e.status) group by 1, 2),
       vb as (select m.metric, e.loc, sum(public._rh_val(m.v, e.amount, e.detail)) val from d m join eb e on e.kind = m.kind and public._rh_stat_ok(m.stat, e.status) group by 1, 2),
       lc as (select coalesce(a.metric, b.metric) metric, coalesce(a.loc, b.loc) loc, coalesce(a.val, 0) av, coalesce(b.val, 0) bv from va a full join vb b on a.metric = b.metric and a.loc is not distinct from b.loc),
       mt as (select metric, sum(av) av, sum(bv) bv from lc group by 1),
       names as (select metric, min(label_en) le, min(label_bn) lb, bool_or(money) mny, min(ord) o from (select x.*, row_number() over () ord from d x) q group by 1)
  select jsonb_agg(jsonb_build_object('key', n.metric, 'label_en', n.le, 'label_bn', n.lb, 'money', n.mny, 'a', coalesce(t.av, 0), 'b', coalesce(t.bv, 0), 'delta', coalesce(t.bv, 0) - coalesce(t.av, 0),
           'pct', case when coalesce(t.av, 0) <> 0 then round((coalesce(t.bv, 0) - t.av) / abs(t.av) * 100, 1) end,
           'movers', coalesce((select jsonb_agg(jsonb_build_object('loc', z.loc, 'a', z.av, 'b', z.bv, 'delta', z.bv - z.av) order by abs(z.bv - z.av) desc) from (select * from lc where lc.metric = n.metric and lc.av <> lc.bv order by abs(lc.bv - lc.av) desc limit 5) z), '[]'::jsonb)) order by n.o)
    into res from names n left join mt t on t.metric = n.metric;
  if (p_a_to - p_a_from) <> (p_b_to - p_b_from) then notes := notes || jsonb_build_array('periods_differ_in_length'); end if;
  if not public._rh_area_ok('cost') then notes := notes || jsonb_build_array('cost_hidden'); end if;
  return jsonb_build_object('generated_at', now(), 'a', jsonb_build_object('from', p_a_from, 'to', p_a_to, 'days', p_a_to - p_a_from + 1), 'b', jsonb_build_object('from', p_b_from, 'to', p_b_to, 'days', p_b_to - p_b_from + 1),
    'loc', p_loc, 'metrics', coalesce(res, '[]'::jsonb), 'hidden_metrics', hidden, 'masked', public._rh_masked(), 'notes', notes);
end $$;

create or replace function public.rpt_hub_drill(p_metric text, p_from date, p_to date, p_loc int default null, p_group text default null, p_limit int default 100, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 100), 1), 500); off int := greatest(coalesce(p_offset, 0), 0); locs int[] := public._rh_locs(); kinds text[]; area text; lbl_en text; lbl_bn text;
        rows_ jsonb; total numeric; n bigint; groups jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 3700 then raise exception 'bad_range'; end if;
  if p_loc is not null and not (p_loc = any (locs)) then raise exception 'not allowed'; end if;
  if p_group is not null and p_group not in ('day', 'loc', 'who', 'kind') then raise exception 'bad_group'; end if;
  select array_agg(distinct d.kind), min(d.area), min(d.label_en), min(d.label_bn) into kinds, area, lbl_en, lbl_bn from public._rh_metric_defs() d where d.metric = p_metric;
  if kinds is null then raise exception 'unknown_metric'; end if;
  if not public._rh_area_ok(area) then raise exception 'not allowed'; end if;
  with e as materialized (select * from public._rh_events(p_from, p_to, p_loc, kinds)),
       c as (select e.*, m.v, public._rh_val(m.v, e.amount, e.detail) val from e join public._rh_metric_defs() m on m.metric = p_metric and m.kind = e.kind
              where public._rh_stat_ok(m.stat, e.status))
  select (select coalesce(sum(val), 0) from c), (select count(*) from c),
         (select coalesce(jsonb_agg(jsonb_build_object('ts', x.ts, 'time', to_char(x.ts at time zone 'Asia/Dhaka', 'HH24:MI'), 'day', x.day, 'kind', x.kind, 'loc', x.loc, 'who', x.who, 'amount', x.amount, 'value', x.val, 'status', x.status,
              'title', x.title, 'detail', x.detail, 'ref_table', x.ref_table, 'ref_id', x.ref_id, 'link', x.link) order by x.ts, x.ref_id), '[]'::jsonb) from (select * from c order by ts, ref_id limit lim offset off) x),
         case p_group when 'day' then (select coalesce(jsonb_agg(jsonb_build_object('key', g.k, 'n', g.n, 'value', g.s) order by g.k), '[]'::jsonb) from (select day::text k, count(*) n, sum(val) s from c group by 1) g)
                      when 'loc' then (select coalesce(jsonb_agg(jsonb_build_object('key', g.k, 'n', g.n, 'value', g.s) order by g.s desc nulls last), '[]'::jsonb) from (select coalesce(loc::text, '-') k, count(*) n, sum(val) s from c group by 1) g)
                      when 'who' then (select coalesce(jsonb_agg(jsonb_build_object('key', g.k, 'n', g.n, 'value', g.s) order by g.s desc nulls last), '[]'::jsonb) from (select coalesce(who, 'not recorded') k, count(*) n, sum(val) s from c group by 1) g)
                      when 'kind' then (select coalesce(jsonb_agg(jsonb_build_object('key', g.k, 'n', g.n, 'value', g.s) order by g.s desc nulls last), '[]'::jsonb) from (select kind k, count(*) n, sum(val) s from c group by 1) g)
                      else '[]'::jsonb end
    into total, n, rows_, groups;
  return jsonb_build_object('generated_at', now(), 'metric', p_metric, 'label_en', lbl_en, 'label_bn', lbl_bn, 'filters', jsonb_build_object('from', p_from, 'to', p_to, 'loc', p_loc, 'group', p_group),
    'total', total, 'count', n, 'limit', lim, 'offset', off, 'rows', rows_, 'groups', groups, 'masked', public._rh_masked());
end $$;

revoke all on function public._rh_metric_defs(), public._rh_stat_ok(text[], text), public._rh_val(text, numeric, jsonb) from public, anon, authenticated;
revoke all on function public.rpt_hub_metrics(), public.rpt_hub_compare(date, date, date, date, int), public.rpt_hub_drill(text, date, date, int, text, int, int) from public, anon;
grant execute on function public.rpt_hub_metrics(), public.rpt_hub_compare(date, date, date, date, int), public.rpt_hub_drill(text, date, date, int, text, int, int) to authenticated;
