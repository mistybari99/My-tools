-- ============================================================
-- Phase 446 - RPT-C2 / R4 part 2 (reports #162, #161): the ACTUAL delivery cost of an app order.
-- Run AFTER phase 445. New file only. Paste twice = no error, no second row.
--
--   * list order_delivery_cost_kinds (rider pay, fuel, platform / courier fee, Other): chosen from the list (BUILD-RULES 4), "Other" needs a written note. The owner adds kinds through Lists.
--   * order_delivery_costs   one row per cost of one order: kind, amount, who was paid (free name), the Dhaka date, note. Append-only: a wrong row is VOIDED with a reason, never edited.
--   * c2_order_cost_add / c2_order_cost_void   write (POS enter, module online_orders_on, the order's place). Idempotent on the client id.
--   The cost is INFORMATION for order costing (delivery cost report, order profit). It does NOT post to the books: the payment is entered as an expense as today, so nothing is counted twice.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_spec_save(uuid,jsonb,text)') is null then raise exception 'phase446 needs phase445 pasted first'; end if;
end $guard$;

insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active, extra) values
 ('order_delivery_cost_kinds', 'rider_pay', 'রাইডারকে দেওয়া টাকা', 'Rider pay', 'Rider pay', 10, true, '{}'),
 ('order_delivery_cost_kinds', 'fuel', 'জ্বালানি', 'Fuel', 'Fuel', 20, true, '{}'),
 ('order_delivery_cost_kinds', 'platform_fee', 'প্ল্যাটফর্ম / কুরিয়ার ফি', 'Platform / courier fee', 'Platform / courier fee', 30, true, '{}'),
 ('order_delivery_cost_kinds', 'other', 'অন্য (লিখুন)', 'Other (write it)', 'Other (write it)', 90, true, '{}')
on conflict (list_code, value_code) do nothing;
update public.list_defs set title_bn = coalesce(title_bn, 'ডেলিভারির খরচের ধরন'), title_en = coalesce(title_en, 'Delivery cost kinds') where list_code = 'order_delivery_cost_kinds';

create table if not exists public.order_delivery_costs (
  id bigint generated always as identity primary key,
  client_id uuid,
  order_id uuid not null references public.online_orders(id),
  kind text not null,
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  paid_to text check (paid_to is null or char_length(paid_to) <= 60),
  cost_date date not null,
  note text check (note is null or char_length(note) <= 300),
  state text not null default 'active' check (state in ('active', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text
);
create unique index if not exists order_delivery_costs_client on public.order_delivery_costs (created_by, client_id) where client_id is not null;
create index if not exists order_delivery_costs_order on public.order_delivery_costs (order_id) where state = 'active';
drop trigger if exists order_delivery_costs_ro on public.order_delivery_costs;
create trigger order_delivery_costs_ro before update or delete on public.order_delivery_costs for each row execute function public._c2_trail_ro();
drop trigger if exists audit_order_delivery_costs on public.order_delivery_costs;
create trigger audit_order_delivery_costs after insert or update on public.order_delivery_costs for each row execute function public.log_change('id');

create or replace function public.c2_order_cost_add(p_order uuid, p_kind text, p_amount numeric, p_paid_to text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; r public.order_delivery_costs; id_ bigint; amt numeric := round(coalesce(p_amount, 0), 2);
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.order_delivery_costs where created_by = auth.uid() and client_id = p_client;
    if found then return jsonb_build_object('id', r.id, 'order_id', o.id, 'dup', true); end if;
  end if;
  if o.status = 'new' then raise exception 'bad_status: a delivery cost is written once the order is confirmed'; end if;
  if amt = 'NaN'::numeric or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if p_kind is null or not exists (select 1 from public.option_lists where list_code = 'order_delivery_cost_kinds' and value_code = p_kind and active) then raise exception 'bad_kind'; end if;
  if p_kind = 'other' and nullif(btrim(p_note), '') is null then raise exception 'note_required: write what the other cost was'; end if;
  if char_length(coalesce(p_paid_to, '')) > 60 or char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long'; end if;
  insert into public.order_delivery_costs (client_id, order_id, kind, amount, paid_to, cost_date, note, created_by, created_staff)
    values (p_client, o.id, p_kind, amt, nullif(btrim(p_paid_to), ''), public._dhaka_today(), nullif(btrim(p_note), ''), auth.uid(), public._c2_staff()) returning id into id_;
  perform public._oo_event61(o.id, o.status, o.status, 'delivery cost ' || amt::text || ' (' || p_kind || ')');
  return jsonb_build_object('id', id_, 'order_id', o.id, 'amount', amt, 'kind', p_kind);
end $$;

create or replace function public.c2_order_cost_void(p_cost bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.order_delivery_costs; o public.online_orders;
begin
  select * into c from public.order_delivery_costs where id = p_cost for update;
  if not found then raise exception 'not_found'; end if;
  select * into o from public.online_orders where id = c.order_id;
  perform public._oo_gate61(o.location_id);
  if c.state = 'void' then return jsonb_build_object('id', c.id, 'noop', true); end if;
  if nullif(btrim(p_note), '') is null or char_length(p_note) > 300 then raise exception 'reason_required'; end if;
  update public.order_delivery_costs set state = 'void', void_by = auth.uid(), void_at = now(), void_note = btrim(p_note) where id = c.id;
  perform public._oo_event61(o.id, o.status, o.status, 'delivery cost voided: ' || btrim(p_note));
  return jsonb_build_object('id', c.id, 'state', 'void');
end $$;

alter table public.order_delivery_costs enable row level security;
revoke all on public.order_delivery_costs from public, anon, authenticated;
grant select on public.order_delivery_costs to authenticated;
drop policy if exists order_delivery_costs_sel on public.order_delivery_costs;
create policy order_delivery_costs_sel on public.order_delivery_costs for select to authenticated using (public.c2_can_read_orders() and public.c2_order_visible(order_id));

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
