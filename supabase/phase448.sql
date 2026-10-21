-- ============================================================
-- Phase 448 - RPT-C2 / R4 part 4 (report #157): cancelling an app order with advance_fate = refund makes a REAL money record.
-- Run AFTER phase 447. New file only. Paste twice = no error, no second row.
--
--   Today (switch OFF, unchanged): online_order_cancel stores advance_fate and posts nothing - no cash move, no journal line, no day-book line.
--   ON (rule order_refund_record_on): every cancelled order with advance_fate = refund and an advance gets ONE refund row (state due) the moment it is cancelled - whichever screen cancelled it
--       (trigger online_orders_c2_refund_due). c2_order_cancel then pays it at once when the person may move money (owner or grant cash_move at that place); otherwise the refund waits as "due" in the
--       refund list for a person who may. Paying uses ONLY the existing cash_move_add:
--         * advance already posted (phase 447): one 'cust_advance_refund' (account 2300 debit, cash/bank/mobile out);
--         * advance never posted: two moves dated today and labelled so - 'cust_advance' (the money that came in with the order, not recorded before) then 'cust_advance_refund' (it goes out): net zero on the
--           books, but the cash-in and cash-out are both visible in the day book on the day it was found.
--   advance_fate adjust = the advance stays a customer advance when it was posted (nothing to do); income with a posted advance is refused (the accountant makes that journal by hand: 2300 -> income).
--   * rule order_refund_record_on (OFF)    * order_refunds  one row per refund (due -> paid | void), the money records are linked by id
--   * c2_order_cancel(order, reason, fate, refund_mode)   * c2_order_refund_pay(order, mode)   * c2_order_refund_void(order, note)   * c2_order_refunds_list(from, to, loc, state)
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_advance_post(uuid)') is null then raise exception 'phase448 needs phase447 pasted first'; end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('order_refund_record_on', 'pos', 'switch', 'false', null, null, null, null, 'বাতিল অর্ডারের অ্যাডভান্স ফেরত টাকার রেকর্ড হিসেবে লিখুন', 'Cancel order-এর advance ফেরত real money record হিসেবে লিখুন', 'Record the refund of a cancelled order advance as real money',
  'বন্ধ থাকলে আগের মতোই: ফেরত বেছে নিলে কোনো টাকার রেকর্ড হয় না। চালু করলে ফেরত রেকর্ড তৈরি হয়, ক্যাশ-অধিকার থাকা কেউ টাকা দিলে ক্যাশ/ব্যাংক খাতায় ওঠে।', 'Off = as today: choosing refund writes no money record. On = a refund record is made; a person with the cash right pays it and it reaches the day book and the journal.', 660)
 on conflict (key) do nothing;

create table if not exists public.order_refunds (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.online_orders(id),
  customer_id uuid references public.customers(id),
  amount numeric not null check (amount > 0),
  refund_mode text not null check (refund_mode in ('cash', 'bank', 'mobile')),
  state text not null default 'due' check (state in ('due', 'paid', 'void')),
  advance_post_id bigint references public.order_advance_posts(id),
  in_move_id uuid references public.cash_moves(id),       -- 'cust_advance' written now when the advance had never been posted
  out_move_id uuid references public.cash_moves(id),      -- 'cust_advance_refund'
  note text check (note is null or char_length(note) <= 300),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  paid_by uuid, paid_staff text, paid_at timestamptz, void_by uuid, void_at timestamptz, void_note text
);
create unique index if not exists order_refunds_live on public.order_refunds (order_id) where state in ('due', 'paid');
create index if not exists order_refunds_state on public.order_refunds (state);
drop trigger if exists audit_order_refunds on public.order_refunds;
create trigger audit_order_refunds after insert or update on public.order_refunds for each row execute function public.log_change('id');
create or replace function public._c2_refund_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: a refund record is never deleted'; end if;
  if old.state <> 'due' then raise exception 'append_only: a paid or void refund cannot change'; end if;
  if (to_jsonb(new) - 'state' - 'refund_mode' - 'customer_id' - 'advance_post_id' - 'in_move_id' - 'out_move_id' - 'paid_by' - 'paid_staff' - 'paid_at' - 'void_by' - 'void_at' - 'void_note' - 'note')
     is distinct from (to_jsonb(old) - 'state' - 'refund_mode' - 'customer_id' - 'advance_post_id' - 'in_move_id' - 'out_move_id' - 'paid_by' - 'paid_staff' - 'paid_at' - 'void_by' - 'void_at' - 'void_note' - 'note') then
    raise exception 'append_only: the amount and the order of a refund cannot change';
  end if;
  return new;
end $$;
drop trigger if exists order_refunds_ro on public.order_refunds;
create trigger order_refunds_ro before update or delete on public.order_refunds for each row execute function public._c2_refund_ro();

-- every cancelled order with fate refund gets its refund row while the switch is ON, whichever screen cancelled it
create or replace function public._c2_refund_due() returns trigger language plpgsql security definer set search_path = public as $$
declare md text;
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' and new.advance_fate = 'refund' and new.advance > 0 and public.rule_on('order_refund_record_on')
     and not exists (select 1 from public.order_refunds where order_id = new.id and state in ('due', 'paid')) then
    md := coalesce(public._c2_money_mode(new.advance_mode), 'cash');
    insert into public.order_refunds (order_id, amount, refund_mode, created_by, created_staff, advance_post_id)
      values (new.id, new.advance, md, auth.uid(), public._c2_staff(), (select id from public.order_advance_posts where order_id = new.id and state = 'posted'));
  end if;
  return null;
end $$;
drop trigger if exists online_orders_c2_refund_due on public.online_orders;
create trigger online_orders_c2_refund_due after update on public.online_orders for each row when (new.status is distinct from old.status) execute function public._c2_refund_due();

-- pay a due refund through the existing cash_move_add (its own right check applies: owner or grant cash_move at the place)
create or replace function public._c2_refund_pay(p_refund bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.order_refunds; o public.online_orders; a public.order_advance_posts; cust uuid; mv jsonb; inmv jsonb; outid uuid; inid uuid; inmode text;
begin
  select * into r from public.order_refunds where id = p_refund for update;
  if not found then raise exception 'not_found'; end if;
  if r.state <> 'due' then return jsonb_build_object('id', r.id, 'state', r.state, 'noop', true); end if;
  select * into o from public.online_orders where id = r.order_id;
  select * into a from public.order_advance_posts where order_id = o.id and state = 'posted' for update;
  cust := coalesce(a.customer_id, public._c2_customer_for(o.customer_mobile, o.customer_name));
  if a.id is null then
    inmode := coalesce(public._c2_money_mode(o.advance_mode), r.refund_mode);
    inmv := public.cash_move_add(o.location_id, 'cust_advance', r.amount, public._dhaka_today(), inmode, cust, left('online order #' || o.order_no || ' advance (found at refund)', 80),
              'advance of a cancelled order, recorded now because it was not recorded when it was taken', md5('c2refin:' || r.id::text)::uuid);
    inid := (inmv ->> 'id')::uuid;
  end if;
  mv := public.cash_move_add(o.location_id, 'cust_advance_refund', r.amount, public._dhaka_today(), r.refund_mode, cust, left('online order #' || o.order_no || ' refund', 80),
          'advance refunded after the order was cancelled', md5('c2refout:' || r.id::text)::uuid);
  outid := (mv ->> 'id')::uuid;
  update public.order_refunds set state = 'paid', customer_id = cust, in_move_id = inid, out_move_id = outid, advance_post_id = a.id, paid_by = auth.uid(), paid_staff = public._c2_staff(), paid_at = now() where id = r.id;
  if a.id is not null then update public.order_advance_posts set state = 'refunded', refund_move_id = outid, closed_at = now(), closed_note = 'refunded after the order was cancelled' where id = a.id; end if;
  perform public._oo_event61(o.id, o.status, o.status, 'advance ' || r.amount::text || ' refunded (' || r.refund_mode || ')');
  return jsonb_build_object('id', r.id, 'state', 'paid', 'amount', r.amount, 'mode', r.refund_mode, 'out_move_id', outid, 'in_move_id', inid);
end $$;

create or replace function public._c2_can_move_money(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.has_grant('cash_move', p_loc));
$$;

create or replace function public.c2_order_cancel(p_id uuid, p_reason text, p_advance_fate text default 'none', p_refund_mode text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; v jsonb; r public.order_refunds; paid jsonb; fate text := coalesce(p_advance_fate, 'none');
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if p_refund_mode is not null and p_refund_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  if fate = 'income' and exists (select 1 from public.order_advance_posts where order_id = o.id and state = 'posted') then
    raise exception 'advance_posted_income: the advance is in the books as a customer advance; choose refund or adjust, or ask the accountant to move it to income';
  end if;
  v := public.online_order_cancel(p_id, p_reason, p_advance_fate);
  select * into r from public.order_refunds where order_id = o.id and state = 'due';
  if not found then
    return v || jsonb_build_object('refund', case when fate = 'refund' and o.advance > 0 and not public.rule_on('order_refund_record_on') then 'not_recorded'
                                                  when fate = 'adjust' and exists (select 1 from public.order_advance_posts where order_id = o.id and state = 'posted') then 'held_as_customer_advance' else null end);
  end if;
  if p_refund_mode is not null and p_refund_mode <> r.refund_mode then update public.order_refunds set refund_mode = p_refund_mode where id = r.id; end if;
  if public._c2_can_move_money(o.location_id) then
    paid := public._c2_refund_pay(r.id);
    return v || jsonb_build_object('refund', 'paid', 'refund_id', r.id, 'refund_detail', paid);
  end if;
  return v || jsonb_build_object('refund', 'due', 'refund_id', r.id);
end $$;

-- pay a refund that is waiting (a person with the cash right); the mode may be changed at that moment
create or replace function public.c2_order_refund_pay(p_order uuid, p_mode text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; r public.order_refunds;
begin
  select * into o from public.online_orders where id = p_order;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if p_mode is not null and p_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  select * into r from public.order_refunds where order_id = o.id and state in ('due', 'paid');
  if not found then raise exception 'no_refund_due'; end if;
  if r.state = 'paid' then return jsonb_build_object('id', r.id, 'state', 'paid', 'noop', true); end if;
  if not public._c2_can_move_money(o.location_id) then raise exception 'not allowed'; end if;
  if p_mode is not null and p_mode <> r.refund_mode then update public.order_refunds set refund_mode = p_mode where id = r.id; end if;
  return public._c2_refund_pay(r.id);
end $$;

-- the customer waived the refund / it was settled another way: close the due row with a reason (owner or the cash right). The advance is then still to be settled by hand - the report shows it.
create or replace function public.c2_order_refund_void(p_order uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; r public.order_refunds;
begin
  select * into o from public.online_orders where id = p_order;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if not public._c2_can_move_money(o.location_id) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null or char_length(p_note) > 300 then raise exception 'reason_required'; end if;
  select * into r from public.order_refunds where order_id = o.id and state = 'due' for update;
  if not found then raise exception 'no_refund_due'; end if;
  update public.order_refunds set state = 'void', void_by = auth.uid(), void_at = now(), void_note = btrim(p_note) where id = r.id;
  perform public._oo_event61(o.id, o.status, o.status, 'refund closed without payment: ' || btrim(p_note));
  return jsonb_build_object('id', r.id, 'state', 'void');
end $$;

-- the refund list (read): who is owed what, paid or waiting. Needs the order report access; rows only for places the person may see.
create or replace function public.c2_order_refunds_list(p_from date default null, p_to date default null, p_loc int default null, p_state text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return jsonb_build_object('module_on', public.rule_on('online_orders_on'), 'record_on', public.rule_on('order_refund_record_on'), 'rows', coalesce((
    select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
      select r.id, r.order_id, o.order_no, o.location_id, o.customer_name, r.amount, r.refund_mode, r.state, r.created_at, r.paid_at, r.in_move_id is not null as found_at_refund, r.void_note
        from public.order_refunds r join public.online_orders o on o.id = r.order_id
       where public.can_loc(o.location_id) and (p_loc is null or o.location_id = p_loc) and (p_state is null or r.state = p_state)
         and (p_from is null or (r.created_at at time zone 'Asia/Dhaka')::date >= p_from) and (p_to is null or (r.created_at at time zone 'Asia/Dhaka')::date <= p_to)
       order by r.created_at desc limit 500) z), '[]'::jsonb));
end $$;

alter table public.order_refunds enable row level security;
revoke all on public.order_refunds from public, anon, authenticated;
grant select on public.order_refunds to authenticated;
drop policy if exists order_refunds_sel on public.order_refunds;
create policy order_refunds_sel on public.order_refunds for select to authenticated using (public.c2_can_read_orders() and public.c2_order_visible(order_id));

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
