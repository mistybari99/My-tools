-- ============================================================
-- Phase 447 - RPT-C2 / R4 part 3 (report #156): an advance taken on an app order becomes a real CUSTOMER ADVANCE (account 2300) - a setting, OFF.
-- Run AFTER phase 446. New file only. Paste twice = no error, no second row.
--
--   Today (OFF, unchanged): the advance written on an app order reaches the books only when the order is delivered (it is passed to record_sale2 as the first payment); a cancelled order never reaches them.
--   ON: c2_order_advance_post(order) records the advance with the EXISTING cash_move_add('cust_advance') - cash/bank/mobile in, account 2300 customer advance, on the customer's advance list - so
--       day book, journal and the advance list show it from the day it was taken. At delivery c2_order_deliver passes only what is collected NOW to record_sale2 and then applies the advance to
--       the sale with the EXISTING cash_move_add('cust_advance_used') (Dr 2300, Cr receivable). No money is counted twice.
--   Who: the existing cash_move right (owner or grant cash_move at that place) is needed to post, void or apply - the same right the Cash and bank screen needs. Without it nothing is posted, the order
--       stays as it was, and the order shows "advance not recorded in the books yet". Delivery still works (legacy way) when the advance was never posted.
--   * rules  order_advance_post_on (OFF)  and  order_advance_post_from (blank = every order): only orders created on or after that day are posted. Blank + ON = every open order.
--   * order_advance_posts  one row per posted advance (state posted -> applied | refunded | void). The cash move itself is the money record.
--   * c2_order_advance_post / _void / _apply, c2_order_deliver, trigger online_orders_c2_advance_guard (a posted advance cannot be edited on the order; void it first).
--   Known and left alone: the customer dues lists (customer_dues, customer_ledger) count sales and sale payments only, as for every 'cust_advance_used' today; an applied advance is shown beside the
--   due in the order register and in the credit reports, never hidden. The sale made at delivery shows the advance part as DUE until the advance is applied.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_cost_add(uuid,text,numeric,text,text,uuid)') is null then raise exception 'phase447 needs phase446 pasted first'; end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('order_advance_post_on', 'pos', 'switch', 'false', null, null, null, null, 'অর্ডারের অ্যাডভান্স গ্রাহকের অগ্রিম হিসেবে খাতায়', 'Order-এর advance গ্রাহকের অগ্রিম হিসেবে খাতায়', 'Post an order advance as a customer advance',
  'বন্ধ থাকলে আগের মতোই: অ্যাডভান্স খাতায় ওঠে ডেলিভারির সময়। চালু করলে অ্যাডভান্স নেওয়ার দিনই ক্যাশ/ব্যাংকে আসে ও অগ্রিম (২৩০০) হিসেবে দেখা যায়।', 'Off = as today: the advance reaches the books at delivery. On = it is recorded the day it is taken (cash/bank/mobile in, account 2300).', 650),
 ('order_advance_post_from', 'pos', 'text', null, null, null, null, null, 'এই তারিখ বা তার পরের অর্ডারের অ্যাডভান্স খাতায় তুলুন', 'এই date বা পরের order-এর advance খাতায় তুলুন', 'Post advances only for orders created on or after',
  'তারিখ লিখুন YYYY-MM-DD। ফাঁকা থাকলে চালু অবস্থায় সব খোলা অর্ডার।', 'A day, YYYY-MM-DD. Blank (with the switch ON) = every open order.', 651)
 on conflict (key) do nothing;

-- the customer behind an order: found by the normalised mobile, created the same way record_sale2 creates one
create or replace function public._c2_customer_for(p_mobile text, p_name text) returns uuid language plpgsql security definer set search_path = public as $$
declare mob text := public.norm_mobile(p_mobile); c public.customers;
begin
  if mob is null or char_length(mob) < 6 then raise exception 'bad_mobile'; end if;
  select * into c from public.customers where mobile = mob for update;
  if not found then
    if nullif(btrim(p_name), '') is null then raise exception 'customer_name_required'; end if;
    insert into public.customers (mobile, name, type, created_by) values (mob, left(btrim(p_name), 80), 'retail', auth.uid()) returning * into c;
  elsif not c.active then raise exception 'customer_inactive';
  end if;
  return c.id;
end $$;

create table if not exists public.order_advance_posts (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.online_orders(id),
  customer_id uuid not null references public.customers(id),
  amount numeric not null check (amount > 0),
  mode text not null check (mode in ('cash', 'bank', 'mobile')),
  state text not null default 'posted' check (state in ('posted', 'applied', 'refunded', 'void')),
  move_id uuid not null references public.cash_moves(id),             -- the cash_moves row 'cust_advance' (the money record)
  applied_move_id uuid references public.cash_moves(id),              -- 'cust_advance_used'
  applied_sale_id uuid references public.sales(id),
  applied_amount numeric,
  refund_move_id uuid references public.cash_moves(id),               -- 'cust_advance_refund' (phase 448)
  note text check (note is null or char_length(note) <= 300),
  created_by uuid, created_staff text, created_at timestamptz not null default now(), closed_at timestamptz, closed_note text
);
create unique index if not exists order_advance_posts_live on public.order_advance_posts (order_id) where state in ('posted', 'applied');
create index if not exists order_advance_posts_order on public.order_advance_posts (order_id);
drop trigger if exists audit_order_advance_posts on public.order_advance_posts;
create trigger audit_order_advance_posts after insert or update on public.order_advance_posts for each row execute function public.log_change('id');
-- only the state and the closing fields move; nothing is deleted, no money field is edited
create or replace function public._c2_advance_post_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: an advance post is never deleted'; end if;
  if old.state in ('refunded', 'void') then raise exception 'append_only: a closed advance post cannot change'; end if;
  if (to_jsonb(new) - 'state' - 'applied_move_id' - 'applied_sale_id' - 'applied_amount' - 'refund_move_id' - 'closed_at' - 'closed_note')
     is distinct from (to_jsonb(old) - 'state' - 'applied_move_id' - 'applied_sale_id' - 'applied_amount' - 'refund_move_id' - 'closed_at' - 'closed_note') then
    raise exception 'append_only: an advance post only changes state';
  end if;
  return new;
end $$;
drop trigger if exists order_advance_posts_ro on public.order_advance_posts;
create trigger order_advance_posts_ro before update or delete on public.order_advance_posts for each row execute function public._c2_advance_post_ro();

-- a posted advance is the money record: the order's advance figure cannot be edited under it
create or replace function public._c2_advance_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.advance is distinct from old.advance or new.advance_mode is distinct from old.advance_mode)
     and exists (select 1 from public.order_advance_posts where order_id = old.id and state in ('posted', 'applied')) then
    raise exception 'advance_posted: the advance of this order is already recorded in the books; void it first';
  end if;
  return new;
end $$;
drop trigger if exists online_orders_c2_advance_guard on public.online_orders;
create trigger online_orders_c2_advance_guard before update on public.online_orders for each row execute function public._c2_advance_guard();

create or replace function public._c2_advance_started(o public.online_orders) returns boolean language plpgsql stable security definer set search_path = public as $$
declare f text := public.rule_txt('order_advance_post_from');
begin
  if not public.rule_on('order_advance_post_on') then return false; end if;
  if f is null then return true; end if;
  if f !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
  return (o.created_at at time zone 'Asia/Dhaka')::date >= f::date;
end $$;

create or replace function public._c2_money_mode(p_mode text) returns text language sql immutable as $$
  select case p_mode when 'cash' then 'cash' when 'mobile' then 'mobile' when 'card' then 'bank' else null end;
$$;

create or replace function public.c2_order_advance_post(p_order uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; cust uuid; mv jsonb; pid bigint; mid uuid; md text; cnt int;
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if not public._c2_advance_started(o) then raise exception 'advance_post_off: the order advance posting switch is off (or starts later)'; end if;
  if o.status not in ('new', 'confirmed', 'packed') then raise exception 'order_closed: only an open order can have its advance posted'; end if;
  if o.advance <= 0 then raise exception 'no_advance'; end if;
  if exists (select 1 from public.order_advance_posts where order_id = o.id and state in ('posted', 'applied')) then
    return jsonb_build_object('order_id', o.id, 'noop', true);
  end if;
  md := public._c2_money_mode(o.advance_mode);
  if md is null then raise exception 'bad_mode'; end if;
  cust := public._c2_customer_for(o.customer_mobile, o.customer_name);
  select count(*) into cnt from public.order_advance_posts where order_id = o.id;
  mv := public.cash_move_add(o.location_id, 'cust_advance', o.advance, public._dhaka_today(), md, cust, left('online order #' || o.order_no || ' advance', 80), 'advance taken on an app order',
          md5('c2adv:' || o.id::text || ':' || cnt::text)::uuid);
  mid := (mv ->> 'id')::uuid;
  if mid is null then raise exception 'advance_not_recorded'; end if;
  insert into public.order_advance_posts (order_id, customer_id, amount, mode, move_id, created_by, created_staff)
    values (o.id, cust, o.advance, md, mid, auth.uid(), public._c2_staff()) returning id into pid;
  perform public._oo_event61(o.id, o.status, o.status, 'advance ' || o.advance::text || ' recorded as a customer advance');
  return jsonb_build_object('order_id', o.id, 'post_id', pid, 'move_id', mid, 'amount', o.advance, 'mode', md);
end $$;

-- take the posted advance back out of the books (before delivery). Voids the cash move (needs the cash_move right); the order advance figure can then be edited again.
create or replace function public.c2_order_advance_void(p_order uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; a public.order_advance_posts;
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  select * into a from public.order_advance_posts where order_id = o.id and state = 'posted' for update;
  if not found then raise exception 'no_posted_advance'; end if;
  if nullif(btrim(p_note), '') is null or char_length(p_note) > 300 then raise exception 'reason_required'; end if;
  perform public.cash_move_void(a.move_id, 'order advance voided: ' || btrim(p_note));
  update public.order_advance_posts set state = 'void', closed_at = now(), closed_note = btrim(p_note) where id = a.id;
  perform public._oo_event61(o.id, o.status, o.status, 'posted advance voided: ' || btrim(p_note));
  return jsonb_build_object('order_id', o.id, 'state', 'void');
end $$;

-- apply a posted advance to the sale of a delivered order (cust_advance_used: Dr 2300, Cr receivable; no money moves)
create or replace function public.c2_order_advance_apply(p_order uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; a public.order_advance_posts; s public.sales; paid numeric; due numeric; amt numeric; mv jsonb;
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  select * into a from public.order_advance_posts where order_id = o.id and state = 'posted' for update;
  if not found then
    if exists (select 1 from public.order_advance_posts where order_id = o.id and state = 'applied') then return jsonb_build_object('order_id', o.id, 'noop', true); end if;
    raise exception 'no_posted_advance';
  end if;
  if o.status <> 'delivered' or o.sale_id is null then raise exception 'bad_status: the advance is applied to the sale of a delivered order'; end if;
  select * into s from public.sales where id = o.sale_id;
  select coalesce(sum(amount), 0) into paid from public.sale_payments where sale_id = s.id and not voided;
  due := greatest(s.total - paid, 0);
  amt := least(a.amount, due);
  if amt <= 0 then raise exception 'nothing_to_apply: the sale has no amount left to cover'; end if;
  mv := public.cash_move_add(o.location_id, 'cust_advance_used', amt, public._dhaka_today(), null, a.customer_id, left('online order #' || o.order_no || ' applied to receipt ' || s.receipt, 80),
          'advance applied to the delivered order sale', md5('c2use:' || a.id::text)::uuid);
  update public.order_advance_posts set state = 'applied', applied_move_id = (mv ->> 'id')::uuid, applied_sale_id = s.id, applied_amount = amt, closed_at = now() where id = a.id;
  perform public._oo_event61(o.id, o.status, o.status, 'advance ' || amt::text || ' applied to receipt ' || s.receipt);
  return jsonb_build_object('order_id', o.id, 'sale_id', s.id, 'applied', amt, 'left_on_advance', a.amount - amt);
end $$;

-- deliver: the existing online_order_deliver while the advance was never posted (identical result); with a posted advance the sale is made WITHOUT the advance payment and the advance is applied after.
create or replace function public.c2_order_deliver(p_id uuid, p_payments jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; a public.order_advance_posts; sl jsonb := '[]'; ln jsonb; res jsonb; sid uuid; ap jsonb; can_apply boolean;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  select * into a from public.order_advance_posts where order_id = o.id and state = 'posted';
  if not found or o.sale_id is not null then
    return public.online_order_deliver(p_id, p_payments) || jsonb_build_object('advance_posted', false);
  end if;
  if o.status <> 'packed' then raise exception 'bad_status: only a packed order can be delivered (now %)', o.status; end if;
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for ln in select * from jsonb_array_elements(o.lines) loop
    sl := sl || jsonb_build_object('item_id', ln ->> 'item_id', 'qty', (ln ->> 'qty')::numeric, 'price', (ln ->> 'price')::numeric);
  end loop;
  if o.delivery_charge > 0 then sl := sl || jsonb_build_object('name', 'Delivery charge', 'amount', o.delivery_charge); end if;
  res := public.record_sale2(o.sale_client, o.location_id, sl, o.discount, coalesce(p_payments, '[]'::jsonb), o.customer_mobile, o.customer_name, 'retail', 'Online order #' || o.order_no, false, null);
  sid := (res ->> 'id')::uuid;
  if exists (select 1 from public.online_orders x where x.sale_id = sid and x.id <> o.id) then raise exception 'sale_already_linked'; end if;
  update public.online_orders set status = 'delivered', sale_id = sid, delivered_by = auth.uid(), delivered_at = now(), updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, 'packed', 'delivered', 'sale receipt ' || (res ->> 'receipt') || ' (advance ' || a.amount::text || ' posted earlier)');
  can_apply := public.is_owner() or public.has_grant('cash_move', o.location_id);
  if can_apply then ap := public.c2_order_advance_apply(o.id); end if;
  return jsonb_build_object('id', o.id, 'status', 'delivered', 'sale_id', sid, 'receipt', res -> 'receipt', 'total', res -> 'total', 'paid', res -> 'paid', 'due', res -> 'due',
    'advance_posted', true, 'advance_applied', can_apply, 'advance_apply', ap);
end $$;

alter table public.order_advance_posts enable row level security;
revoke all on public.order_advance_posts from public, anon, authenticated;
grant select on public.order_advance_posts to authenticated;
drop policy if exists order_advance_posts_sel on public.order_advance_posts;
create policy order_advance_posts_sel on public.order_advance_posts for select to authenticated using (public.c2_can_read_orders() and public.c2_order_visible(order_id));

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
