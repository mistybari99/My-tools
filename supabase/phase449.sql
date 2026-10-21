-- ============================================================
-- Phase 449 - RPT-C2 / R4 part 5 (reports #153 order register, #155 cake order register, #156 advance and outstanding order balances). READ ONLY.
-- Run AFTER phase 448. New file only. Paste twice = no error.
--
--   _c2_orders_base(from, to, loc, by)   the ONE normalised row list the order reports read: app orders (online_orders), paper form 20-1 (one row per order sheet) and paper form 20-6 (one row per ledger line).
--                                        The three sources are never merged: every row carries `source`. A sheet written on paper AND typed in the app shows twice, once per source (stated on screen).
--   c2_order_register(...)   #153    c2_cake_register(...)   #155    c2_order_balances(...)   #156    c2_order_detail(order)   drill-down of one app order
--   Balance rules (the old list `online_orders_list` is left as it is): open order = total - advance; delivered = what is still due on its sale after payments and after a posted advance that was applied
--   (a delivered order no longer shows as owed); cancelled = 0 owed, the advance is shown by state (refunded, refund due, refund not recorded, kept for adjustment, taken as income).
--   Every report is open to the existing order-report access (owner, report_orders, view_reports, or POS view) and only shows the places the person may see. When the online order module is not
--   switched on the answer says so (notes: module_off) and still returns the paper rows - nothing is hidden. Cost columns need the cost right (rpt_cost_ok).
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_cancel(uuid,text,text,text)') is null then raise exception 'phase449 needs phase448 pasted first'; end if;
end $guard$;

create or replace function public._c2_date(p text) returns date language plpgsql immutable as $$
begin if p ~ '^\d{4}-\d{2}-\d{2}$' then return p::date; end if; return null; exception when others then return null; end $$;
create or replace function public._c2_time(p text) returns time language plpgsql immutable as $$
begin if p ~ '^\d{1,2}:\d{2}' then return substring(p from '^\d{1,2}:\d{2}')::time; end if; return null; exception when others then return null; end $$;
create or replace function public._c2_num(p jsonb) returns numeric language sql immutable as $$
  select case when jsonb_typeof(p) = 'number' then (p #>> '{}')::numeric when jsonb_typeof(p) = 'string' and (p #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$' then (p #>> '{}')::numeric end;
$$;
-- one date range check for every order / customer / staff report
create or replace function public._c2_range(p_from date, p_to date) returns void language plpgsql immutable as $$
begin
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_date: from and to are required and to is not before from'; end if;
  if p_to - p_from > 1100 then raise exception 'bad_date: at most 1100 days in one report'; end if;
end $$;

create or replace function public._c2_orders_base(p_from date, p_to date, p_loc int default null, p_by text default 'order') returns table (
  source text, ref text, order_id uuid, entry_id uuid, line_no int, loc int, order_date date, created_at timestamptz,
  customer_name text, customer_mobile text, channel text, order_type text, status text, delivery_mode text, delivery_by text,
  promised_date date, promised_from time, promised_to time, delivered_at timestamptz, delivered_date date,
  total numeric, discount numeric, delivery_charge numeric, advance numeric, balance numeric, balance_basis text, advance_state text,
  sale_id uuid, receipt int, has_spec boolean, cancel_reason text, advance_fate text, delivery_cost numeric)
language plpgsql stable security definer set search_path = public as $$
declare mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok();
begin
  return query
  select 'app'::text, '#' || o.order_no::text, o.id, null::uuid, null::int, o.location_id, (o.created_at at time zone 'Asia/Dhaka')::date, o.created_at,
         o.customer_name, case when mob then o.customer_mobile end, o.channel,
         case when exists (select 1 from public.order_cake_specs c where c.order_id = o.id and c.state = 'active') then 'cake' else 'normal' end,
         o.status, o.delivery_mode, o.delivery_by, o.delivery_date, pr.slot_from, pr.slot_to, o.delivered_at, (o.delivered_at at time zone 'Asia/Dhaka')::date,
         o.subtotal - o.discount + o.delivery_charge, o.discount, o.delivery_charge, o.advance,
         case o.status when 'delivered' then case when s.id is null then null when s.status = 'void' then 0
                                                  else greatest(s.total - sp.paid - coalesce(case when ap.state = 'applied' then ap.applied_amount end, 0), 0) end
                       when 'cancelled' then 0 else o.subtotal - o.discount + o.delivery_charge - o.advance end,
         case o.status when 'delivered' then case when s.id is null then 'sale_missing' when s.status = 'void' then 'sale_voided' when ap.state = 'applied' then 'sale_due_after_payments_and_applied_advance' else 'sale_due_after_payments' end
                       when 'cancelled' then 'cancelled' else 'total_minus_advance' end,
         case when o.advance = 0 then 'none'
              when o.status in ('new', 'confirmed', 'packed') then case when ap.state = 'posted' then 'held_in_books' else 'held_not_in_books' end
              when o.status = 'delivered' then case when ap.state = 'applied' then 'applied_to_sale' when ap.state = 'posted' then 'held_not_applied' else 'paid_into_sale' end
              else case rf.state when 'paid' then 'refunded' when 'due' then 'refund_due' when 'void' then 'refund_closed'
                                 else case o.advance_fate when 'refund' then 'refund_not_recorded' when 'adjust' then case when ap.state = 'posted' then 'kept_as_customer_advance' else 'kept_for_adjustment' end
                                                          when 'income' then 'taken_as_income' else 'unknown' end end end,
         o.sale_id, s.receipt, exists (select 1 from public.order_cake_specs c where c.order_id = o.id and c.state = 'active'), o.cancel_reason, o.advance_fate,
         (select sum(c.amount) from public.order_delivery_costs c where c.order_id = o.id and c.state = 'active')
    from public.online_orders o
    left join public.sales s on s.id = o.sale_id
    left join lateral (select coalesce(sum(p.amount), 0) as paid from public.sale_payments p where p.sale_id = s.id and not p.voided) sp on true
    left join public.order_advance_posts ap on ap.order_id = o.id and ap.state in ('posted', 'applied')
    left join lateral (select r.state from public.order_refunds r where r.order_id = o.id order by r.id desc limit 1) rf on true
    left join lateral (select x.slot_from, x.slot_to from public.order_promises x where x.order_id = o.id and x.state = 'active' order by x.id desc limit 1) pr on true
   where public.can_loc(o.location_id) and (p_loc is null or o.location_id = p_loc)
     and case when p_by = 'promised' then o.delivery_date between p_from and p_to else (o.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to end;

  return query
  select 'paper_20_1'::text, '20-1/' || e.serial::text, null::uuid, e.id, null::int, e.location_id, e.entry_date, e.created_at,
         nullif(btrim(e.data ->> 'cust_name'), ''), case when mob then nullif(btrim(e.data ->> 'cust_phone'), '') end, nullif(btrim(e.data ->> 'channel'), ''),
         case when e.data ->> 'order_type' = 'custom' then 'cake' else coalesce(nullif(e.data ->> 'order_type', ''), 'normal') end,
         case when (e.data ->> 'not_collected') = 'true' then 'not_collected' when (e.data ->> 'cust_signed') = 'true' then 'handed' else 'open' end,
         nullif(e.data ->> 'deliv_mode', ''), nullif(e.data ->> 'deliv_by', ''),
         public._c2_date(e.data ->> 'deliv_date'), public._c2_time(e.data ->> 'deliv_time'), null::time, null::timestamptz, null::date,
         t.total, t.disc, null::numeric, t.adv,
         case when (e.data ->> 'not_collected') = 'true' then 0
              when (e.data ->> 'cust_signed') = 'true' then case when t.total is null then null when public._c2_num(e.data -> 'due_paid') is null then null else greatest(t.total - t.disc - t.adv - public._c2_num(e.data -> 'due_paid'), 0) end
              else case when t.total is null then null else t.total - t.disc - t.adv end end,
         case when (e.data ->> 'not_collected') = 'true' then 'cancelled_on_sheet' when (e.data ->> 'cust_signed') = 'true' then case when public._c2_num(e.data -> 'due_paid') is null then 'due_payment_not_written' else 'total_minus_advance_minus_due_paid' end else 'total_minus_advance' end,
         case when t.adv = 0 then 'none' when (e.data ->> 'not_collected') = 'true' then coalesce(e.data ->> 'adv_fate', 'unknown') else 'on_sheet' end,
         null::uuid, null::int, null::boolean, nullif(e.data ->> 'fate_reason', ''), nullif(e.data ->> 'adv_fate', ''), null::numeric
    from public.entries e
    cross join lateral (select public._c2_num(e.data -> 'total') as total, coalesce(public._c2_num(e.data -> 'discount'), 0) as disc, coalesce(public._c2_num(e.data -> 'advance'), 0) as adv) t
   where e.form_code = '20-1' and e.status in ('submitted', 'approved') and public.can_loc(e.location_id) and (p_loc is null or e.location_id = p_loc)
     and case when p_by = 'promised' then public._c2_date(e.data ->> 'deliv_date') between p_from and p_to else e.entry_date between p_from and p_to end;

  return query
  select 'paper_20_6'::text, '20-6/' || e.serial::text || '/' || l.ord::text, null::uuid, e.id, l.ord::int, e.location_id, e.entry_date, e.created_at,
         null::text, null::text, nullif(lower(btrim(l.v ->> 'platform')), ''), 'normal'::text, coalesce(nullif(l.v ->> 'outcome', ''), 'not_written'),
         null::text, nullif(btrim(l.v ->> 'delivery'), ''), null::date, null::time, null::time, null::timestamptz, null::date,
         public._c2_num(l.v -> 'amt'), null::numeric, public._c2_num(l.v -> 'dcharge'), null::numeric, null::numeric, 'ledger_line'::text, 'none'::text,
         null::uuid, null::int, null::boolean, null::text, null::text, null::numeric
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) with ordinality as l(v, ord)
   where e.form_code = '20-6' and e.status in ('submitted', 'approved') and public.can_loc(e.location_id) and (p_loc is null or e.location_id = p_loc)
     and p_by <> 'promised' and e.entry_date between p_from and p_to;
end $$;

-- notes every order report carries (codes the web turns into words)
create or replace function public._c2_order_notes(p_paper boolean default true) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n jsonb := '[]'::jsonb;
begin
  if not public.rule_on('online_orders_on') then n := n || '"module_off"'::jsonb; end if;
  if p_paper then n := n || '"sources_not_merged"'::jsonb; end if;
  if not public.rpt_cost_ok() then n := n || '"cost_hidden"'::jsonb; end if;
  if not (public.can_do('POS', 'view') or public.rpt_mobile_ok()) then n := n || '"mobile_hidden"'::jsonb; end if;
  return n;
end $$;

-- #153 the unified order register
create or replace function public.c2_order_register(p_from date, p_to date, p_loc int default null, p_source text default null, p_status text default null, p_by text default 'order', p_limit int default 500) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 500), 1), 2000); rows jsonb; tot jsonb; n int; cost boolean := public.rpt_cost_ok();
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_source is not null and p_source not in ('app', 'paper_20_1', 'paper_20_6') then raise exception 'bad_filter'; end if;
  if p_by not in ('order', 'promised') then raise exception 'bad_filter'; end if;
  with b as (select x.* from public._c2_orders_base(p_from, p_to, p_loc, p_by) x where (p_source is null or x.source = p_source) and (p_status is null or x.status = p_status)),
       t as (select * from b order by order_date desc, source, ref limit lim)
  select (select coalesce(jsonb_agg(case when cost then to_jsonb(r) else to_jsonb(r) - 'delivery_cost' end order by r.order_date desc, r.source, r.ref), '[]'::jsonb) from t r),
         (select count(*) from b),
         (select coalesce(jsonb_object_agg(q.source, q.v), '{}'::jsonb) from (
            select g.source, jsonb_build_object('rows', count(*), 'total', sum(g.total), 'advance', sum(g.advance), 'balance', sum(g.balance),
                   'rows_without_total', count(*) filter (where g.total is null), 'rows_without_balance', count(*) filter (where g.balance is null)) as v from b g group by g.source) q)
    into rows, n, tot;
  return jsonb_build_object('from', p_from, 'to', p_to, 'by', p_by, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(true),
    'truncated', n > lim, 'row_count', n, 'totals_by_source', tot, 'rows', rows);
end $$;

-- #155 the cake / custom order register: app cake specs next to paper 20-1 sheets of type custom
create or replace function public.c2_cake_register(p_from date, p_to date, p_loc int default null, p_source text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; noscap int;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_source is not null and p_source not in ('app', 'paper_20_1') then raise exception 'bad_filter'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.order_date desc, z.ref, z.line), '[]'::jsonb) into rows from (
    select 'app'::text as source, b.ref, b.order_id, null::uuid as entry_id, c.id::int as line, b.order_date, b.loc, b.customer_name, b.status, b.promised_date, b.promised_from, b.promised_to, b.delivery_mode,
           (select l ->> 'name' from public.online_orders o2, jsonb_array_elements(o2.lines) l where o2.id = b.order_id and l ->> 'item_id' = c.item_id::text limit 1) as item_name,
           c.weight_kg, c.flavour, c.message, c.design, c.photo_ref, c.note, null::text as description
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') b join public.order_cake_specs c on c.order_id = b.order_id and c.state = 'active'
     where b.source = 'app' and (p_source is null or p_source = 'app')
    union all
    select 'paper_20_1', b.ref, null::uuid, b.entry_id, i.ord::int, b.order_date, b.loc, b.customer_name, b.status, b.promised_date, b.promised_from, null::time, b.delivery_mode,
           nullif(btrim(i.v ->> 'item'), ''), null::numeric, null::text, nullif(btrim(i.v ->> 'msg'), ''), nullif(btrim(i.v ->> 'design'), ''), null::text, nullif(btrim(i.v ->> 'special'), ''), nullif(btrim(i.v ->> 'desc'), '')
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') b join public.entries e on e.id = b.entry_id
      cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'items') = 'array' then e.data -> 'items' else '[]'::jsonb end) with ordinality as i(v, ord)
     where b.source = 'paper_20_1' and b.order_type = 'cake' and (p_source is null or p_source = 'paper_20_1')
     order by 6 desc, 2, 5 limit 2000) z;
  select count(*) into noscap from public._c2_orders_base(p_from, p_to, p_loc, 'order') b where b.source = 'app' and not b.has_spec and b.status <> 'cancelled';
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(true), 'rows', rows,
    'app_orders_without_spec', noscap);
end $$;

-- #156 advance payments and outstanding order balances
create or replace function public.c2_order_balances(p_from date, p_to date, p_loc int default null, p_open_only boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.order_date desc, z.source, z.ref), '[]'::jsonb) into rows from (
    select b.source, b.ref, b.order_id, b.entry_id, b.loc, b.order_date, b.customer_name, b.customer_mobile, b.status, b.total, b.discount, b.advance, b.balance, b.balance_basis, b.advance_state, b.sale_id, b.receipt,
           (b.balance is not null and b.balance > 0 and b.status in ('delivered', 'handed')) as owed_after_delivery
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') b
     where b.source in ('app', 'paper_20_1') and (b.advance > 0 or coalesce(b.balance, 0) > 0)
       and (not p_open_only or b.status in ('new', 'confirmed', 'packed', 'open'))
     order by b.order_date desc limit 1000) z;
  select jsonb_build_object(
    'app', jsonb_build_object(
      'advance_held_open_orders', coalesce(sum(b.advance) filter (where b.source = 'app' and b.status in ('new', 'confirmed', 'packed')), 0),
      'balance_to_collect_open_orders', coalesce(sum(b.balance) filter (where b.source = 'app' and b.status in ('new', 'confirmed', 'packed')), 0),
      'still_owed_after_delivery', coalesce(sum(b.balance) filter (where b.source = 'app' and b.status = 'delivered'), 0),
      'advance_to_return_cancelled', coalesce(sum(b.advance) filter (where b.source = 'app' and b.advance_state in ('refund_due', 'refund_not_recorded')), 0),
      'advance_not_in_books_open', coalesce(sum(b.advance) filter (where b.source = 'app' and b.advance_state = 'held_not_in_books'), 0),
      'advance_posted_not_applied', coalesce(sum(b.advance) filter (where b.source = 'app' and b.advance_state = 'held_not_applied'), 0)),
    'paper_20_1', jsonb_build_object(
      'advance_open_sheets', coalesce(sum(b.advance) filter (where b.source = 'paper_20_1' and b.status = 'open'), 0),
      'balance_open_sheets', coalesce(sum(b.balance) filter (where b.source = 'paper_20_1' and b.status = 'open'), 0),
      'open_sheets_without_total', count(*) filter (where b.source = 'paper_20_1' and b.status = 'open' and b.total is null),
      'handed_without_due_payment_written', count(*) filter (where b.source = 'paper_20_1' and b.status = 'handed' and b.balance is null))) into sm
    from public._c2_orders_base(p_from, p_to, p_loc, 'order') b where b.source in ('app', 'paper_20_1');
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(true) || '"old_list_balance_differs"'::jsonb, 'summary', sm, 'rows', rows);
end $$;

-- drill-down: one app order with its trail, cake specs, promise, costs, advance, refund and sale
create or replace function public.c2_order_detail(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.online_orders; s public.sales; paid numeric; cost boolean := public.rpt_cost_ok();
begin
  select * into o from public.online_orders where id = p_order;
  if not found or not public.c2_can_read_orders() or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  if o.sale_id is not null then select * into s from public.sales where id = o.sale_id; select coalesce(sum(amount), 0) into paid from public.sale_payments where sale_id = s.id and not voided; end if;
  return jsonb_build_object(
    'order', to_jsonb(o) - 'sale_client',
    'events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id) from public.online_order_events e where e.order_id = o.id), '[]'::jsonb),
    'specs', coalesce((select jsonb_agg(to_jsonb(c) - 'created_by' - 'void_by' order by c.id) from public.order_cake_specs c where c.order_id = o.id and c.state = 'active'), '[]'::jsonb),
    'spec_history', (select count(*) from public.order_cake_specs c where c.order_id = o.id and c.state = 'void'),
    'promise', (select to_jsonb(x) - 'created_by' - 'void_by' from (select * from public.order_promises where order_id = o.id and state = 'active' order by id desc limit 1) x),
    'promise_history', coalesce((select jsonb_agg(jsonb_build_object('slot_from', x.slot_from, 'slot_to', x.slot_to, 'reason', x.reason, 'at', x.created_at, 'by', x.created_staff) order by x.id) from public.order_promises x where x.order_id = o.id and x.state = 'active'), '[]'::jsonb),
    'costs', case when cost then coalesce((select jsonb_agg(to_jsonb(c) - 'created_by' - 'void_by' order by c.id) from public.order_delivery_costs c where c.order_id = o.id), '[]'::jsonb) else null end,
    'cost_hidden', not cost,
    'advance_post', (select to_jsonb(a) - 'created_by' from public.order_advance_posts a where a.order_id = o.id order by a.id desc limit 1),
    'refund', (select to_jsonb(r) - 'created_by' - 'paid_by' - 'void_by' from public.order_refunds r where r.order_id = o.id order by r.id desc limit 1),
    'sale', case when s.id is null then null else jsonb_build_object('id', s.id, 'receipt', s.receipt, 'status', s.status, 'total', s.total, 'paid', paid, 'due', greatest(s.total - paid, 0)) end,
    'register_row', (select to_jsonb(b) from public._c2_orders_base((o.created_at at time zone 'Asia/Dhaka')::date, (o.created_at at time zone 'Asia/Dhaka')::date, o.location_id, 'order') b where b.order_id = o.id),
    'can_move_money', public._c2_can_move_money(o.location_id), 'module_on', public.rule_on('online_orders_on'));
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
