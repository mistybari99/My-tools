-- Phase 435 (bos435) - RPT-B3 / R7b: PURCHASING REPORTS - supplier returns and purchase adjustments (#100), agreed-price variance (#101), supplier rejection rate (#103),
-- supplier dependency and risk (#104), supplier delivery performance (#102).
-- Paste after phase434. Paste-twice safe. Earlier phase files are not edited; no shared function is re-created. All reports are READ ONLY.
--
-- Open to the roles that already hold the purchase report right (report_purchase, or view_reports) and the owner; money columns are shown only to who may see costs (rpt_cost_ok);
-- without that right the money keys are null and the answer says cost_hidden. A place a person may not see is never included.
-- Missing data is said, never turned into 0: a check with no quantity, a PO with no promised date, an item with no declared supplier, a bill line with no agreed price are all COUNTED and
-- named as "not captured" in the answer.
-- Drill-down: every row carries the id of its source (bill, quality check, purchase-order entry) so the screen can open it.
--   #100 supplier_returns_report(from, to, loc, supplier)       returns, bill discounts, voided bills, supplier refunds, per-supplier summary
--   #101 purch_price_variance(from, to, loc, supplier, item)    posted bill lines against the agreed price valid on the bill date
--   #103 supplier_rejection_rate(from, to, loc, supplier)       latest quality check per receipt: pass / hold / reject, by check and by quantity where typed
--   #104 supplier_dependency(from, to, loc)                     per item: suppliers really used, share of the biggest, declared preferred / alternative, risk flags
--   #102 supplier_delivery_perf(from, to, loc, supplier)        paper PO (06-3) promised date against the GRN (04-1) dates

do $g$ begin
  if to_regprocedure('public.item_supplier_list(uuid,uuid,boolean)') is null then raise exception 'phase435 needs phase434 first'; end if;
  if to_regprocedure('public._p26_po(date,date,int[])') is null then raise exception 'phase435 needs phase26 first'; end if;
end $g$;

-- the places the caller may see (and p_loc when given); a given place that is not allowed stops the call
create or replace function public._rb3_locs(p_loc int) returns int[] language plpgsql stable security definer set search_path = public as $$
begin
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return coalesce((select array_agg(l.id) from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
end $$;
create or replace function public._rb3_range(p_from date, p_to date, out f date, out t date) language plpgsql stable as $$
begin
  f := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
end $$;
create or replace function public._rb3_purch_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_access('purchase'));
$$;

-- ---------- #100 returns and adjustments ----------
create or replace function public.supplier_returns_report(p_from date default null, p_to date default null, p_loc int default null, p_supplier uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; locs int[]; cost boolean := public.rpt_cost_ok(); returns_ jsonb; disc jsonb; voids jsonb; refunds jsonb; summ jsonb; cap constant int := 300;
begin
  if not public._rb3_purch_ok() then raise exception 'not allowed'; end if;
  select * into r from public._rb3_range(p_from, p_to);
  locs := public._rb3_locs(p_loc);
  select coalesce(jsonb_agg(x.j order by x.d desc), '[]'::jsonb) into returns_ from (
    select b.bill_date as d, jsonb_build_object('bill_id', b.id, 'bill_no', b.bill_no, 'bill_date', b.bill_date, 'supplier_id', b.supplier_id, 'supplier', s.name, 'location_id', b.location_id, 'location', l.name_bn,
      'ref_bill_id', b.ref_bill_id, 'ref_bill_no', rb.bill_no, 'reason_code', b.reason_code,
      'reason_label', (select coalesce(o.label_en, o.value_code) from public.option_lists o where o.list_code = 'return_reasons' and o.value_code = b.reason_code),
      'reason_label_bn', (select o.label_bn from public.option_lists o where o.list_code = 'return_reasons' and o.value_code = b.reason_code),
      'total', case when cost then b.total end, 'variance', case when cost then b.variance end,
      'items', (select coalesce(jsonb_agg(jsonb_build_object('code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'qty', pl.qty, 'unit', pl.unit) order by pl.line_no), '[]'::jsonb)
                  from public.purchase_lines pl left join public.items i on i.id = pl.item_id where pl.bill_id = b.id)) as j
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id join public.locations l on l.id = b.location_id left join public.purchase_bills rb on rb.id = b.ref_bill_id
     where b.kind = 'return' and b.status = 'posted' and b.bill_date between r.f and r.t and b.location_id = any (locs) and (p_supplier is null or b.supplier_id = p_supplier)
     order by b.bill_date desc limit cap) x;
  select coalesce(jsonb_agg(x.j order by x.d desc), '[]'::jsonb) into disc from (
    select b.bill_date as d, jsonb_build_object('bill_id', b.id, 'bill_no', b.bill_no, 'bill_date', b.bill_date, 'supplier_id', b.supplier_id, 'supplier', s.name, 'location', l.name_bn,
      'subtotal', case when cost then b.subtotal end, 'discount', case when cost then b.discount end, 'total', case when cost then b.total end) as j
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id join public.locations l on l.id = b.location_id
     where b.kind = 'bill' and b.status = 'posted' and b.discount > 0 and b.bill_date between r.f and r.t and b.location_id = any (locs) and (p_supplier is null or b.supplier_id = p_supplier)
     order by b.bill_date desc limit cap) x;
  select coalesce(jsonb_agg(x.j order by x.d desc), '[]'::jsonb) into voids from (
    select b.bill_date as d, jsonb_build_object('bill_id', b.id, 'bill_no', b.bill_no, 'bill_date', b.bill_date, 'kind', b.kind, 'supplier_id', b.supplier_id, 'supplier', s.name, 'location', l.name_bn,
      'total', case when cost then b.total end, 'void_note', b.void_note, 'void_at', b.void_at) as j
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id join public.locations l on l.id = b.location_id
     where b.status = 'void' and b.bill_date between r.f and r.t and b.location_id = any (locs) and (p_supplier is null or b.supplier_id = p_supplier)
     order by b.bill_date desc limit cap) x;
  select coalesce(jsonb_agg(x.j order by x.d desc), '[]'::jsonb) into refunds from (
    select (f.refunded_at at time zone 'Asia/Dhaka')::date as d, jsonb_build_object('refund_id', f.id, 'day', (f.refunded_at at time zone 'Asia/Dhaka')::date, 'supplier_id', f.supplier_id, 'supplier', s.name, 'location', l.name_bn,
      'amount', case when cost then f.amount end, 'mode', f.mode, 'reason_code', f.reason_code, 'note', f.note) as j
      from public.supplier_refunds f join public.suppliers s on s.id = f.supplier_id join public.locations l on l.id = f.location_id
     where not f.voided and (f.refunded_at at time zone 'Asia/Dhaka')::date between r.f and r.t and f.location_id = any (locs) and (p_supplier is null or f.supplier_id = p_supplier)
     order by f.refunded_at desc limit cap) x;
  select coalesce(jsonb_agg(jsonb_build_object('supplier_id', z.sid, 'supplier', z.sname, 'purchases_n', z.pn, 'purchases_total', case when cost then z.pt end, 'returns_n', z.rn, 'returns_total', case when cost then z.rt end,
      'return_pct', case when cost and z.pt > 0 then round(z.rt / z.pt * 100, 2) end, 'discounts_total', case when cost then z.dt end, 'voided_n', z.vn, 'voided_total', case when cost then z.vt end,
      'refunds_n', z.fn, 'refunds_total', case when cost then z.ft end) order by z.sname), '[]'::jsonb) into summ from (
    select s.id as sid, s.name as sname,
      count(*) filter (where b.kind = 'bill' and b.status = 'posted') as pn, coalesce(sum(b.total) filter (where b.kind = 'bill' and b.status = 'posted'), 0) as pt,
      count(*) filter (where b.kind = 'return' and b.status = 'posted') as rn, coalesce(sum(b.total) filter (where b.kind = 'return' and b.status = 'posted'), 0) as rt,
      coalesce(sum(b.discount) filter (where b.kind = 'bill' and b.status = 'posted'), 0) as dt,
      count(*) filter (where b.status = 'void') as vn, coalesce(sum(b.total) filter (where b.status = 'void'), 0) as vt,
      (select count(*) from public.supplier_refunds f where f.supplier_id = s.id and not f.voided and (f.refunded_at at time zone 'Asia/Dhaka')::date between r.f and r.t and f.location_id = any (locs)) as fn,
      coalesce((select sum(f.amount) from public.supplier_refunds f where f.supplier_id = s.id and not f.voided and (f.refunded_at at time zone 'Asia/Dhaka')::date between r.f and r.t and f.location_id = any (locs)), 0) as ft
      from public.suppliers s left join public.purchase_bills b on b.supplier_id = s.id and b.bill_date between r.f and r.t and b.location_id = any (locs)
     where (p_supplier is null or s.id = p_supplier)
     group by s.id, s.name) z where z.pn + z.rn + z.vn + z.fn > 0;
  return jsonb_build_object('from', r.f, 'to', r.t, 'cost_hidden', not cost, 'returns', returns_, 'discounts', disc, 'voided', voids, 'refunds', refunds, 'summary', summ,
    'truncated', jsonb_array_length(returns_) >= cap or jsonb_array_length(disc) >= cap or jsonb_array_length(voids) >= cap or jsonb_array_length(refunds) >= cap);
end $$;

-- ---------- #101 agreed price variance ----------
create or replace function public.purch_price_variance(p_from date default null, p_to date default null, p_loc int default null, p_supplier uuid default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; locs int[]; rows_ jsonb; s jsonb; tot_lines int; with_p int; extra_tot numeric; cap constant int := 500;
begin
  if not (public._rb3_purch_ok() and public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  select * into r from public._rb3_range(p_from, p_to);
  locs := public._rb3_locs(p_loc);
  with b as (
    select b.id as bill_id, pl.line_no, b.bill_date, b.supplier_id, sp.name as sname, b.bill_no, l.name_bn as place, pl.item_id, i.code, i.name_bn, i.name_en,
           coalesce(pl.base_qty, pl.qty) as qty, coalesce(pl.unit_cost_base, pl.unit_cost) as actual, ap.price_base as agreed, ap.id as agreed_id, ap.effective_from as agreed_from,
           case when ap.id is not null then (coalesce(pl.unit_cost_base, pl.unit_cost) - ap.price_base) * coalesce(pl.base_qty, pl.qty) end as extra
      from public.purchase_bills b join public.purchase_lines pl on pl.bill_id = b.id join public.items i on i.id = pl.item_id join public.suppliers sp on sp.id = b.supplier_id join public.locations l on l.id = b.location_id
      left join lateral (select p.* from public.supplier_item_prices p where p.item_id = pl.item_id and p.supplier_id = b.supplier_id and p.effective_from <= b.bill_date
                          and (p.effective_to is null or p.effective_to >= b.bill_date) and (p.active or (p.retired_at at time zone 'Asia/Dhaka')::date > b.bill_date)
                          order by p.effective_from desc, p.id desc limit 1) ap on true
     where b.kind = 'bill' and b.status = 'posted' and b.bill_date between r.f and r.t and b.location_id = any (locs) and (p_supplier is null or b.supplier_id = p_supplier)
       and (p_item is null or pl.item_id = p_item) and pl.item_id is not null),
  lim as (select * from b order by bill_date desc, line_no limit cap)
  select (select coalesce(jsonb_agg(jsonb_build_object('bill_id', x.bill_id, 'bill_no', x.bill_no, 'bill_date', x.bill_date, 'supplier_id', x.supplier_id, 'supplier', x.sname, 'location', x.place,
              'item_id', x.item_id, 'code', x.code, 'name_bn', x.name_bn, 'name_en', x.name_en, 'base_unit', public._item_base(x.item_id), 'qty', x.qty, 'actual_price', round(x.actual, 4),
              'agreed_price', x.agreed, 'agreed_id', x.agreed_id, 'agreed_from', x.agreed_from,
              'diff', case when x.agreed_id is not null then round(x.actual - x.agreed, 4) end,
              'diff_pct', case when x.agreed_id is not null then round((x.actual - x.agreed) / x.agreed * 100, 2) end,
              'extra_cost', case when x.agreed_id is not null then round(x.extra, 2) end) order by x.bill_date desc, x.line_no), '[]'::jsonb) from lim x),
         (select coalesce(jsonb_agg(jsonb_build_object('supplier_id', z.supplier_id, 'supplier', z.sname, 'lines', z.n, 'lines_with_agreed', z.np, 'lines_without_agreed', z.n - z.np,
              'extra_cost', round(z.ex, 2), 'lines_above', z.up, 'lines_below', z.dn) order by z.sname), '[]'::jsonb)
            from (select supplier_id, sname, count(*) as n, count(agreed_id) as np, sum(extra) as ex, count(*) filter (where extra > 0.005) as up, count(*) filter (where extra < -0.005) as dn from b group by supplier_id, sname) z),
         (select count(*) from b), (select count(agreed_id) from b), (select round(sum(extra), 2) from b)
    into rows_, s, tot_lines, with_p, extra_tot;
  return jsonb_build_object('from', r.f, 'to', r.t, 'rows', rows_, 'summary', s, 'lines', tot_lines, 'lines_with_agreed', with_p, 'lines_without_agreed', tot_lines - with_p, 'extra_cost_total', extra_tot,
    'truncated', tot_lines > cap, 'basis', 'bill line price per base unit, before the bill discount, against the agreed price valid on the bill date');
end $$;

-- ---------- #103 supplier rejection rate ----------
create or replace function public.supplier_rejection_rate(p_from date default null, p_to date default null, p_loc int default null, p_supplier uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; locs int[]; rows_ jsonb; checks_ jsonb; cap constant int := 500;
begin
  if not (public.is_active() and (public.is_owner() or public.rpt_access('purchase') or public.rpt_access('quality'))) then raise exception 'not allowed'; end if;
  select * into r from public._rb3_range(p_from, p_to);
  locs := public._rb3_locs(p_loc);
  with last_ as (
    select distinct on (q.source_type, q.source_id) q.* from public.qc_records q
     where q.source_type = 'grn' order by q.source_type, q.source_id, q.created_at desc, q.id desc),
  c as (
    select l.* from last_ l where l.location_id = any (locs) and (l.created_at at time zone 'Asia/Dhaka')::date between r.f and r.t and (p_supplier is null or l.supplier_id = p_supplier))
  select coalesce(jsonb_agg(jsonb_build_object('supplier_id', z.sid, 'supplier', z.sname, 'checks', z.n, 'pass', z.np, 'hold', z.nh, 'reject', z.nr,
      'reject_rate_pct', case when z.n > 0 then round(z.nr::numeric / z.n * 100, 2) end,
      'qty_captured_n', z.nq, 'qty_not_captured_n', z.n - z.nq, 'qty_checked', z.qc, 'qty_rejected', z.qr,
      'reject_rate_qty_pct', case when z.qc > 0 then round(z.qr / z.qc * 100, 2) end,
      'receipts_n', z.rec, 'receipts_checked_n', z.n, 'share_checked_pct', case when z.rec > 0 then round(least(z.n, z.rec)::numeric / z.rec * 100, 1) end,
      'supplier_not_captured', z.sid is null) order by z.sname nulls last), '[]'::jsonb) into rows_ from (
    select c.supplier_id as sid, s.name as sname, count(*) as n, count(*) filter (where c.status = 'pass') as np, count(*) filter (where c.status = 'hold') as nh, count(*) filter (where c.status = 'reject') as nr,
           count(c.qty) as nq, sum(c.qty) as qc, coalesce(sum(c.qty) filter (where c.status = 'reject'), 0) as qr,
           case when c.supplier_id is null then null else (select count(*) from public.purchase_bills b where b.supplier_id = c.supplier_id and b.kind = 'bill' and b.status = 'posted'
                  and b.bill_date between r.f and r.t and b.location_id = any (locs)) end as rec
      from c left join public.suppliers s on s.id = c.supplier_id group by c.supplier_id, s.name) z;
  select coalesce(jsonb_agg(jsonb_build_object('check_id', c.id, 'source_id', c.source_id, 'day', (c.created_at at time zone 'Asia/Dhaka')::date, 'status', c.status, 'supplier_id', c.supplier_id, 'supplier', s.name,
      'item_id', c.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'qty', c.qty, 'base_unit', case when i.id is null then null else public._item_base(i.id) end, 'note', c.note, 'location_id', c.location_id,
      'is_bill', exists (select 1 from public.purchase_bills b where b.id = c.source_id)) order by c.created_at desc), '[]'::jsonb) into checks_ from (
    select distinct on (q.source_id) q.* from public.qc_records q where q.source_type = 'grn' order by q.source_id, q.created_at desc, q.id desc) c
    left join public.suppliers s on s.id = c.supplier_id left join public.items i on i.id = c.item_id
   where c.location_id = any (locs) and (c.created_at at time zone 'Asia/Dhaka')::date between r.f and r.t and (p_supplier is null or c.supplier_id = p_supplier);
  return jsonb_build_object('from', r.f, 'to', r.t, 'rows', rows_, 'checks', checks_,
    'basis', 'latest quality check of each received lot (purchase bill or paper GRN 04-1); the paper GRN rejected lines of the supplier scorecard are a separate count');
end $$;

-- ---------- #104 dependency and risk ----------
create or replace function public.supplier_dependency(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; locs int[]; cost boolean := public.rpt_cost_ok(); rows_ jsonb; summ jsonb;
begin
  if not _rb3_purch_ok() then raise exception 'not allowed'; end if;
  select * into r from public._rb3_range(p_from, p_to);
  locs := public._rb3_locs(p_loc);
  with u as (
    select pl.item_id, b.supplier_id, sum(coalesce(pl.base_qty, pl.qty)) as qty, sum(pl.amount) as val, count(distinct b.id) as bills
      from public.purchase_bills b join public.purchase_lines pl on pl.bill_id = b.id
     where b.kind = 'bill' and b.status = 'posted' and b.bill_date between r.f and r.t and b.location_id = any (locs) and pl.item_id is not null
     group by pl.item_id, b.supplier_id),
  t as (select item_id, sum(qty) as tq, count(*) as ns from u group by item_id),
  top as (select distinct on (u.item_id) u.item_id, u.supplier_id, u.qty from u order by u.item_id, u.qty desc, u.supplier_id),
  d as (select x.item_id,
               coalesce(jsonb_agg(jsonb_build_object('supplier_id', x.supplier_id, 'supplier', s.name)) filter (where x.rank = 'preferred'), '[]'::jsonb) as pref,
               coalesce(jsonb_agg(jsonb_build_object('supplier_id', x.supplier_id, 'supplier', s.name)) filter (where x.rank = 'alternative'), '[]'::jsonb) as alt,
               array_agg(x.supplier_id) as declared
          from public.item_suppliers x join public.suppliers s on s.id = x.supplier_id where x.active group by x.item_id),
  rowsq as (
    select i.id as item_id, i.code, i.name_bn, i.name_en, t.ns, t.tq, ts.name as top_name, ts.id as top_id, round(top.qty / nullif(t.tq, 0) * 100, 1) as top_share,
           (select sum(u2.val) from u u2 where u2.item_id = i.id) as val_total, d.pref, d.alt, d.declared,
           coalesce((select jsonb_agg(jsonb_build_object('supplier_id', u3.supplier_id, 'supplier', s3.name, 'qty', round(u3.qty, 4), 'share_pct', round(u3.qty / nullif(t.tq, 0) * 100, 1),
                     'value', case when cost then round(u3.val, 2) end, 'declared', u3.supplier_id = any (coalesce(d.declared, '{}'))) order by u3.qty desc)
                     from u u3 join public.suppliers s3 on s3.id = u3.supplier_id where u3.item_id = i.id), '[]'::jsonb) as used
      from t join public.items i on i.id = t.item_id join top on top.item_id = t.item_id join public.suppliers ts on ts.id = top.supplier_id left join d on d.item_id = t.item_id)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', q.item_id, 'code', q.code, 'name_bn', q.name_bn, 'name_en', q.name_en, 'base_unit', public._item_base(q.item_id),
      'suppliers_used', q.ns, 'qty_total', round(q.tq, 4), 'top_supplier_id', q.top_id, 'top_supplier', q.top_name, 'top_share_pct', q.top_share,
      'value_total', case when cost then round(q.val_total, 2) end,
      'preferred', coalesce(q.pref, '[]'::jsonb), 'alternatives', coalesce(q.alt, '[]'::jsonb), 'used', q.used,
      'flags', to_jsonb(array_remove(array[
        case when q.ns = 1 then 'single_supplier_used' end,
        case when q.declared is null then 'declared_suppliers_not_captured' end,
        case when q.declared is not null and jsonb_array_length(coalesce(q.alt, '[]'::jsonb)) = 0 then 'no_alternative_declared' end,
        case when q.declared is not null and jsonb_array_length(coalesce(q.pref, '[]'::jsonb)) > 0 and not exists (select 1 from jsonb_array_elements(q.pref) pp where (pp ->> 'supplier_id')::uuid = q.top_id) then 'preferred_not_the_main_supplier' end,
        case when q.declared is not null and exists (select 1 from jsonb_array_elements(q.used) uu where (uu ->> 'declared')::boolean is not true) then 'used_supplier_not_declared' end], null))
      ) order by q.top_share desc, q.code), '[]'::jsonb) into rows_ from rowsq q;
  select jsonb_build_object('items', jsonb_array_length(rows_),
      'single_supplier', (select count(*) from jsonb_array_elements(rows_) x where x -> 'flags' ? 'single_supplier_used'),
      'declared_not_captured', (select count(*) from jsonb_array_elements(rows_) x where x -> 'flags' ? 'declared_suppliers_not_captured'),
      'no_alternative', (select count(*) from jsonb_array_elements(rows_) x where x -> 'flags' ? 'no_alternative_declared'),
      'preferred_not_main', (select count(*) from jsonb_array_elements(rows_) x where x -> 'flags' ? 'preferred_not_the_main_supplier'),
      'used_not_declared', (select count(*) from jsonb_array_elements(rows_) x where x -> 'flags' ? 'used_supplier_not_declared')) into summ;
  return jsonb_build_object('from', r.f, 'to', r.t, 'cost_hidden', not cost, 'rows', rows_, 'summary', summ,
    'basis', 'posted purchase bills of the period; shares by quantity in the base unit; declared suppliers from the item_suppliers list');
end $$;

-- ---------- #102 delivery performance ----------
create or replace function public.supplier_delivery_perf(p_from date default null, p_to date default null, p_loc int default null, p_supplier uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; locs int[]; sname text; rows_ jsonb; summ jsonb; npo int; today date := (now() at time zone 'Asia/Dhaka')::date; cap constant int := 500;
begin
  if not (public.is_active() and (public.is_owner() or public.rpt_access('purchase'))) then raise exception 'not allowed'; end if;
  select * into r from public._rb3_range(p_from, p_to);
  locs := public._rb3_locs(p_loc);
  if p_supplier is not null then select lower(btrim(name)) into sname from public.suppliers where id = p_supplier; if sname is null then raise exception 'supplier_not_found'; end if; end if;
  with d as (
    select p.*, l.name_bn as place, x.st, x.late, x.lead
      from public._p26_po(r.f, r.t, locs) p join public.locations l on l.id = p.location_id
      cross join lateral (select
          case when p.grn_n > 0 and p.lines_open = 0 then
                 case when p.delivery_date is null then 'received_no_promised_date' when p.last_grn <= p.delivery_date then 'on_time' else 'late' end
               when p.grn_n > 0 then
                 case when p.delivery_date is null then 'partial_no_promised_date' when today > p.delivery_date then 'partial_overdue' else 'partial' end
               else
                 case when p.delivery_date is null then 'open_no_promised_date' when today > p.delivery_date then 'overdue_open' else 'open' end end as st,
          case when p.delivery_date is null then null
               when p.grn_n > 0 and p.lines_open = 0 then greatest(p.last_grn - p.delivery_date, 0)
               when today > p.delivery_date then today - p.delivery_date else 0 end as late,
          case when p.grn_n > 0 then p.first_grn - p.entry_date end as lead) x
     where p_supplier is null or p.sk = sname),
  lim as (select * from d order by entry_date desc, po_no limit cap)
  select (select coalesce(jsonb_agg(jsonb_build_object('entry_id', q.entry_id, 'po_no', q.po_no, 'po_date', q.entry_date, 'location_id', q.location_id, 'location', q.place, 'supplier', q.supplier,
              'promised_date', q.delivery_date, 'first_grn', q.first_grn, 'last_grn', q.last_grn, 'grn_n', q.grn_n, 'lines_open', q.lines_open, 'po_lines', q.po_lines,
              'status', q.st, 'days_late', q.late, 'lead_days', q.lead) order by q.entry_date desc, q.po_no), '[]'::jsonb) from lim q),
         (select coalesce(jsonb_agg(jsonb_build_object('supplier', z.nm, 'pos', z.n, 'received_complete', z.rc, 'on_time', z.ot, 'late', z.lt,
              'on_time_pct', case when z.ot + z.lt > 0 then round(z.ot::numeric / (z.ot + z.lt) * 100, 1) end,
              'avg_days_late', z.avgl, 'avg_lead_days', z.avgd, 'overdue_open', z.ov, 'partial', z.pa, 'promised_date_not_captured', z.nd) order by z.nm), '[]'::jsonb)
            from (select coalesce(supplier, '-') as nm, count(*) as n, count(*) filter (where st in ('on_time', 'late', 'received_no_promised_date')) as rc,
                         count(*) filter (where st = 'on_time') as ot, count(*) filter (where st = 'late') as lt,
                         round(avg(late) filter (where st = 'late'), 1) as avgl, round(avg(lead) filter (where lead is not null), 1) as avgd,
                         count(*) filter (where st in ('overdue_open', 'partial_overdue')) as ov, count(*) filter (where st like 'partial%') as pa,
                         count(*) filter (where st like '%no_promised_date') as nd
                    from d group by coalesce(supplier, '-')) z),
         (select count(*) from d)
    into rows_, summ, npo;
  return jsonb_build_object('from', r.f, 'to', r.t, 'rows', rows_, 'summary', summ, 'truncated', npo > cap,
    'basis', 'paper purchase orders (06-3) against goods received notes (04-1) carrying the same PO number; purchase bills carry no PO link, so they are not part of this report');
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb3_locs', '_rb3_range', '_rb3_purch_ok') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('supplier_returns_report', 'purch_price_variance', 'supplier_rejection_rate', 'supplier_dependency', 'supplier_delivery_perf') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
