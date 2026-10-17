-- Phase 452 (RPT-HUB, part 3): entity timelines (item, customer, supplier, staff, employee, outlet, batch) with running balance.
--   rpt_hub_find_entity(kind, text)   find the thing by name / code / mobile (only what the caller may see)
--   rpt_hub_entity(kind, id, from, to, loc, limit, offset)   every event for that thing in a date range; item and batch: running quantity; customer and supplier: running balance
-- READ ONLY. Same masking as phase 451. A customer's or supplier's balance uses the same rules as customer_ledger / supplier_ledger (tested to agree).
-- Safe to paste twice. Needs phases 450 and 451.
do $$ begin if to_regprocedure('public._rh_events(date,date,int,text[],text,text,boolean)') is null then raise exception 'rpthub_needs_phase451'; end if; end $$;

create or replace function public._rh_masked() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare m jsonb := '[]'::jsonb;
begin
  if not public._rh_area_ok('sales') then m := m || jsonb_build_array(jsonb_build_object('area', 'sales', 'kinds', jsonb_build_array('sale', 'void', 'return'))); end if;
  if not (public._rh_area_ok('customers') or public._rh_area_ok('sales')) then m := m || jsonb_build_array(jsonb_build_object('area', 'customers', 'kinds', jsonb_build_array('collection'))); end if;
  if not public._rh_area_ok('cash') then m := m || jsonb_build_array(jsonb_build_object('area', 'cash', 'kinds', jsonb_build_array('cash_move', 'cash_short', 'other_income', 'money_transfer', 'handover'))); end if;
  if not public._rh_area_ok('pos') then m := m || jsonb_build_array(jsonb_build_object('area', 'pos', 'kinds', jsonb_build_array('day_sheet'))); end if;
  if not public._rh_area_ok('stock') then m := m || jsonb_build_array(jsonb_build_object('area', 'stock', 'kinds', jsonb_build_array('production', 'transfer_sent', 'transfer_received', 'transfer_cancelled', 'wastage', 'count_adjust', 'ledger', 'count_sheet', 'factory_sheet', 'transit_short', 'price_change'))); end if;
  if not public._rh_area_ok('purchase') then m := m || jsonb_build_array(jsonb_build_object('area', 'purchase', 'kinds', jsonb_build_array('purchase', 'purchase_return', 'supplier_payment', 'supplier_refund'))); end if;
  if not public._rh_area_ok('expense') then m := m || jsonb_build_array(jsonb_build_object('area', 'expense', 'kinds', jsonb_build_array('expense', 'voucher'))); end if;
  if not public._rh_area_ok('payroll') then m := m || jsonb_build_array(jsonb_build_object('area', 'payroll', 'kinds', jsonb_build_array('payroll', 'advance'))); end if;
  if not public._rh_area_ok('hr') then m := m || jsonb_build_array(jsonb_build_object('area', 'hr', 'kinds', jsonb_build_array('staff_status', 'staff_exit'))); end if;
  if not public._rh_area_ok('control') then m := m || jsonb_build_array(jsonb_build_object('area', 'control', 'kinds', jsonb_build_array('approval', 'exception', 'exception_resolved'))); end if;
  if not public._rh_area_ok('accounts') then m := m || jsonb_build_array(jsonb_build_object('area', 'accounts', 'kinds', jsonb_build_array('period'))); end if;
  return m;
end $$;

create or replace function public.rpt_hub_find_entity(p_kind text, p_q text, p_limit int default 20)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q text := btrim(coalesce(p_q, '')); lim int := least(greatest(coalesce(p_limit, 20), 1), 50); pat text; out jsonb := '[]'::jsonb; mob boolean := public.rpt_mobile_ok();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if length(q) < 1 then return '[]'::jsonb; end if;
  pat := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  if p_kind = 'item' then
    if not public._rh_area_ok('stock') then raise exception 'not allowed'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('kind', 'item', 'id', x.id, 'label', coalesce(x.name_en, x.name_bn), 'sub', x.code) order by x.name_en), '[]'::jsonb) into out
      from (select i.id, i.name_en, i.name_bn, i.code from public.items i where i.name_en ilike pat or i.name_bn ilike pat or i.name_mix ilike pat or i.code ilike pat or i.barcode ilike pat order by i.name_en limit lim) x;
  elsif p_kind = 'customer' then
    if not (public._rh_area_ok('customers') or public._rh_area_ok('sales')) then raise exception 'not allowed'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('kind', 'customer', 'id', x.id, 'label', x.name, 'sub', case when mob then x.mobile else '***' || right(coalesce(x.mobile, ''), 3) end) order by x.name), '[]'::jsonb) into out
      from (select c.id, c.name, c.mobile from public.customers c where c.name ilike pat or c.mobile ilike pat order by c.name limit lim) x;
  elsif p_kind = 'supplier' then
    if not public._rh_area_ok('purchase') then raise exception 'not allowed'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('kind', 'supplier', 'id', x.id, 'label', x.name, 'sub', case when mob then x.mobile else '***' || right(coalesce(x.mobile, ''), 3) end) order by x.name), '[]'::jsonb) into out
      from (select s.id, s.name, s.mobile from public.suppliers s where s.name ilike pat or s.mobile ilike pat order by s.name limit lim) x;
  elsif p_kind = 'staff' then
    if not (public._rh_area_ok('sales') or public._rh_area_ok('cash') or public._rh_area_ok('stock') or public._rh_area_ok('purchase') or public._rh_area_ok('expense') or public._rh_area_ok('hr') or public._rh_area_ok('payroll') or public._rh_area_ok('control')) then raise exception 'not allowed'; end if;
    select coalesce(jsonb_agg(x.j order by x.lb), '[]'::jsonb) into out from (
      select coalesce(p.full_name, p.staff_id) lb, jsonb_build_object('kind', 'staff', 'id', p.id, 'label', coalesce(nullif(p.full_name, ''), p.staff_id), 'sub', p.staff_id) j
        from public.profiles p where p.full_name ilike pat or p.staff_id ilike pat order by 1 limit lim) x;
    if public._rh_area_ok('hr') or public._rh_area_ok('payroll') then
      out := out || coalesce((select jsonb_agg(jsonb_build_object('kind', 'employee', 'id', e.id, 'label', coalesce(e.full_name_en, e.full_name_bn), 'sub', e.employee_no, 'profile_id', e.profile_id))
                        from (select * from public.employees e0 where e0.full_name_en ilike pat or e0.full_name_bn ilike pat or e0.nickname ilike pat or e0.employee_no ilike pat order by e0.full_name_en limit lim) e), '[]'::jsonb);
    end if;
  elsif p_kind = 'outlet' then
    select coalesce(jsonb_agg(jsonb_build_object('kind', 'outlet', 'id', l.id, 'label', coalesce(l.name_en, l.name_bn), 'sub', l.code) order by l.sort, l.id), '[]'::jsonb) into out
      from public.locations l where public.can_loc(l.id) and (l.name_en ilike pat or l.name_bn ilike pat or l.code ilike pat);
  elsif p_kind = 'batch' then
    if not public._rh_area_ok('stock') then raise exception 'not allowed'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('kind', 'batch', 'id', x.id, 'label', coalesce(x.batch_no, '#' || x.id) || ' · ' || coalesce(x.name_en, ''), 'sub', to_char(x.made_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD')) order by x.made_at desc), '[]'::jsonb) into out
      from (select b.id, b.batch_no, b.made_at, i.name_en from public.stock_batches b join public.items i on i.id = b.item_id
             where b.location_id = any (public._rh_locs()) and (b.batch_no ilike pat or b.id::text = q or i.name_en ilike pat or i.name_bn ilike pat) order by b.made_at desc limit lim) x;
  else raise exception 'bad_kind';
  end if;
  return out;
end $$;

create or replace function public.rpt_hub_entity(p_kind text, p_id text, p_from date, p_to date, p_loc int default null, p_limit int default 100, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  lim int := least(greatest(coalesce(p_limit, 100), 1), 500); off int := greatest(coalesce(p_offset, 0), 0);
  locs int[] := public._rh_locs(); label text; sub text; opening numeric := 0; has_bal boolean := false; bal_unit text;
  t0 timestamptz := (p_from::timestamp at time zone 'Asia/Dhaka'); from_eff date; ent text := p_kind; ev jsonb; kc jsonb; n bigint; closing numeric; notes jsonb := '[]'::jsonb; lid int;
  any_area boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind not in ('item', 'customer', 'supplier', 'staff', 'employee', 'outlet', 'batch') then raise exception 'bad_kind'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 3700 then raise exception 'bad_range'; end if;
  if p_loc is not null and not (p_loc = any (locs)) then raise exception 'not allowed'; end if;
  any_area := public._rh_area_ok('sales') or public._rh_area_ok('cash') or public._rh_area_ok('stock') or public._rh_area_ok('purchase') or public._rh_area_ok('expense') or public._rh_area_ok('hr') or public._rh_area_ok('payroll') or public._rh_area_ok('control');
  -- who may open which timeline, and the label
  if p_kind = 'item' then
    if not public._rh_area_ok('stock') then raise exception 'not allowed'; end if;
    select coalesce(i.name_en, i.name_bn), i.code, coalesce(i.base_unit, i.unit) into label, sub, bal_unit from public.items i where i.id::text = p_id;
    has_bal := true;
  elsif p_kind = 'batch' then
    if not public._rh_area_ok('stock') then raise exception 'not allowed'; end if;
    select coalesce(b.batch_no, '#' || b.id) || ' · ' || coalesce(i.name_en, ''), to_char(b.made_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD'), coalesce(i.base_unit, i.unit) into label, sub, bal_unit
      from public.stock_batches b join public.items i on i.id = b.item_id where b.id::text = p_id and b.location_id = any (locs);
    has_bal := true;
  elsif p_kind = 'customer' then
    if not (public._rh_area_ok('customers') or public._rh_area_ok('sales')) then raise exception 'not allowed'; end if;
    select c.name, case when public.rpt_mobile_ok() then c.mobile else '***' || right(coalesce(c.mobile, ''), 3) end into label, sub from public.customers c where c.id::text = p_id;
    has_bal := true;
  elsif p_kind = 'supplier' then
    if not public._rh_area_ok('purchase') then raise exception 'not allowed'; end if;
    select s.name, case when public.rpt_mobile_ok() then s.mobile else '***' || right(coalesce(s.mobile, ''), 3) end into label, sub from public.suppliers s where s.id::text = p_id;
    has_bal := true;
  elsif p_kind = 'staff' then
    if not any_area then raise exception 'not allowed'; end if;
    select coalesce(nullif(p.full_name, ''), p.staff_id), p.staff_id into label, sub from public.profiles p where p.id::text = p_id;
  elsif p_kind = 'employee' then
    if not (public._rh_area_ok('hr') or public._rh_area_ok('payroll')) then raise exception 'not allowed'; end if;
    select coalesce(e.full_name_en, e.full_name_bn), e.employee_no into label, sub from public.employees e where e.id::text = p_id;
  else   -- outlet
    begin lid := p_id::int; exception when others then raise exception 'bad_id'; end;
    if not (lid = any (locs)) or not any_area then raise exception 'not allowed'; end if;
    select coalesce(l.name_en, l.name_bn), l.code into label, sub from public.locations l where l.id = lid;
  end if;
  if label is null then raise exception 'not_found'; end if;
  from_eff := case when p_kind in ('customer', 'supplier') then date '2000-01-01' else p_from end;

  if p_kind = 'customer' and p_loc is null then opening := coalesce(public._w1a_cust_open(p_id::uuid), 0);
  elsif p_kind = 'supplier' and p_loc is null then select coalesce(s.opening_balance, 0) into opening from public.suppliers s where s.id::text = p_id;
  elsif p_kind in ('item', 'batch') then
    select coalesce(sum(l.qty_delta), 0) into opening from public.stock_ledger l
      where l.made_at < t0 and l.location_id = any (locs) and (p_loc is null or l.location_id = p_loc)
        and ((p_kind = 'item' and l.item_id::text = p_id) or (p_kind = 'batch' and l.batch_id::text = p_id));
  end if;
  if p_kind in ('customer', 'supplier') then notes := notes || jsonb_build_array('balance_is_amount_owed'); end if;
  if p_kind in ('item', 'batch') then notes := notes || jsonb_build_array('balance_is_quantity'); end if;
  if p_kind = 'staff' and not public._rh_area_ok('payroll') then notes := notes || jsonb_build_array('pay_events_hidden'); end if;
  if not public._rh_area_ok('cost') then notes := notes || jsonb_build_array('cost_hidden'); end if;

  with raw as materialized (
    select * from public._rh_events(from_eff, p_to, case when p_kind = 'outlet' then lid else p_loc end, null, case when p_kind = 'outlet' then null else ent end, case when p_kind = 'outlet' then null else p_id end, p_kind in ('item', 'batch'))
  ), cum as (
    select r.*, sum(coalesce(r.delta, 0)) over (order by r.ts, r.kind, r.ref_id rows between unbounded preceding and current row) + opening as bal from raw r
  ), vis as (select * from cum c where c.ts >= t0)
  select (select count(*) from vis),
         (select coalesce(jsonb_object_agg(z.kind, jsonb_build_object('n', z.c, 'amount', z.a)), '{}'::jsonb)
            from (select v.kind, count(*) c, sum(v.amount) filter (where coalesce(v.status, 'done') not in ('void', 'cancelled', 'rejected')) a from vis v group by v.kind) z),
         (select coalesce(jsonb_agg(jsonb_build_object('ts', x.ts, 'time', to_char(x.ts at time zone 'Asia/Dhaka', 'HH24:MI'), 'day', x.day, 'kind', x.kind, 'area', x.area, 'loc', x.loc, 'who', x.who, 'who_id', x.who_id,
            'amount', x.amount, 'qty', x.qty, 'dir', x.dir, 'title', x.title, 'status', x.status, 'detail', x.detail, 'ref_table', x.ref_table, 'ref_id', x.ref_id, 'link', x.link, 'item_id', x.item_id,
            'cust_id', x.cust_id, 'sup_id', x.sup_id, 'emp_id', x.emp_id, 'batch_id', x.batch_id, 'delta', x.delta, 'balance', case when has_bal then x.bal end) order by x.ts, x.kind, x.ref_id), '[]'::jsonb)
            from (select * from vis order by ts, kind, ref_id limit lim offset off) x),
         (select v.bal from vis v order by v.ts desc, v.kind desc, v.ref_id desc limit 1)
    into n, kc, ev, closing;

  return jsonb_build_object('generated_at', now(), 'entity', jsonb_build_object('kind', p_kind, 'id', p_id, 'label', label, 'sub', sub, 'unit', bal_unit),
    'filters', jsonb_build_object('from', p_from, 'to', p_to, 'loc', p_loc), 'has_balance', has_bal, 'opening', case when has_bal then opening end,
    'closing', case when has_bal then coalesce(closing, opening) end, 'total_events', n, 'limit', lim, 'offset', off, 'events', ev, 'kind_counts', kc, 'masked', public._rh_masked(), 'notes', notes);
end $$;

revoke all on function public._rh_masked() from public, anon, authenticated;
revoke all on function public.rpt_hub_find_entity(text, text, int), public.rpt_hub_entity(text, text, date, date, int, int, int) from public, anon;
grant execute on function public.rpt_hub_find_entity(text, text, int), public.rpt_hub_entity(text, text, date, date, int, int, int) to authenticated;
