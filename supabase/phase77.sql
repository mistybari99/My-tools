-- ============================================================
-- Phase 77 (bos77) - Step E9: existing online-order gaps (audit a2-F6). Run AFTER phase76. Additive + idempotent (paste twice = no error).
--   1. PACK-TIME STOCK WARNING   online_order_status('packed') now ANSWERS with a "short" list when the stock of a tracked item is below the order qty.
--                                It never blocks. Switch online_pack_warn_on (OFF). online_order_stock_check(id) = the same check as a read-only preview.
--                                Soft reservation (switch online_pack_reserve_on, OFF): other PACKED, undelivered orders of the same place count as reserved
--                                in the warning. It is advisory only - the counter (POS) is not blocked; nothing is written for it.
--   2. KEEP THE ORDER'S PRICE    switch online_keep_order_price (OFF = today: list price at delivery, price_changed exception if it moved).
--                                ON: online_order_deliver sends override=true for a line whose order price differs from today's list price; record_sale2 then
--                                keeps the order price, applies its own approval rule (price_override grant when pos_override_manager is on) and records
--                                its yellow 'price_override' exception. A refused approval rolls the whole delivery back (order stays packed).
--   3. VOIDED SALE => FLAG        trigger on sales: when the sale of a delivered/linked order is voided, an `online_order_flags` row (kind sale_voided, open),
--                                an order trail line and a RED exception are written. The order status is NOT silently changed. Owner/POS approver reviews the flag.
--   4. PACKAGING ON RETURN       NOT changed - see the proposal in docs/briefs_p2p3/step_E9_REPORT.md.
-- Re-created functions (latest definitions, only bos77 lines changed): online_order_status, online_order_deliver (phase61), online_orders_list, online_order_get (phase76).
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('online_pack_warn_on', 'pos', 'switch', 'false', null, null, null, null, 'প্যাক করার সময় স্টক কম হলে সতর্কতা', 'Pack করার সময় stock কম হলে warning', 'Warn at pack time when stock is short',
  'শুধু সতর্কতা; প্যাক আটকায় না।', 'Warning only; packing is never blocked.', 640),
 ('online_pack_reserve_on', 'pos', 'switch', 'false', null, null, null, null, 'প্যাক হওয়া অর্ডারের স্টক ধরে রাখা (নরম, শুধু সতর্কতায়)', 'Packed order-এর stock ধরে রাখা (soft, শুধু warning-এ)', 'Soft-reserve stock of packed orders (warnings only)',
  'চালু হলে অন্য প্যাক হওয়া অর্ডারের পরিমাণ সতর্কতার হিসাবে বাদ যায়। কাউন্টারের বিক্রি আটকায় না।', 'When on, quantities of other packed orders are deducted in the warning. The counter is not blocked.', 641),
 ('online_keep_order_price', 'pos', 'switch', 'false', null, null, null, null, 'ডেলিভারিতে অর্ডারের দাম ধরে রাখা', 'Delivery-তে order-এর দাম ধরে রাখা', 'Keep the order price at delivery',
  'বন্ধ = আজকের তালিকা দাম। চালু = অর্ডারে লেখা দাম; দাম বদলালে সাধারণ ওভাররাইড-অনুমতির নিয়ম লাগে ও হলুদ এক্সেপশন হয়।', 'Off = today''s list price. On = the price on the order; a different price needs the normal override approval and logs a yellow exception.', 642)
 on conflict (key) do nothing;

create table if not exists public.online_order_flags (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.online_orders(id), location_id int not null, sale_id uuid,
  kind text not null check (kind in ('sale_voided')), note text,
  state text not null default 'open' check (state in ('open', 'reviewed')), review_note text, reviewed_by uuid, reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists online_order_flags_one on public.online_order_flags (order_id, kind, sale_id);
create or replace function public._oo_flag_ro77() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: a flag is reviewed, never deleted'; end if;
  if (to_jsonb(new) - 'state' - 'review_note' - 'reviewed_by' - 'reviewed_at') <> (to_jsonb(old) - 'state' - 'review_note' - 'reviewed_by' - 'reviewed_at') then raise exception 'append_only: only the review can change'; end if;
  return new;
end $$;
drop trigger if exists online_order_flags_ro77 on public.online_order_flags;
create trigger online_order_flags_ro77 before update or delete on public.online_order_flags for each row execute function public._oo_flag_ro77();
drop trigger if exists audit_online_order_flags on public.online_order_flags;
create trigger audit_online_order_flags after insert or update on public.online_order_flags for each row execute function public.log_change('id');

-- 3. the sale of an order was voided: no silent drift
create or replace function public._oo_salevoid77() returns trigger language plpgsql security definer set search_path = public as $$
declare o public.online_orders;
begin
  for o in select * from public.online_orders where sale_id = new.id loop
    insert into public.online_order_flags (order_id, location_id, sale_id, kind, note)
      values (o.id, o.location_id, new.id, 'sale_voided', left('sale receipt ' || new.receipt || ' was voided: ' || coalesce(new.void_note, ''), 300)) on conflict do nothing;
    perform public._oo_event61(o.id, o.status, o.status, 'SALE VOIDED (receipt ' || new.receipt || ') - the order still says delivered; check it');
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, new.id, 'POS', o.location_id, new.sale_date, 'online_order_sale_voided', 'red', new.total,
        jsonb_build_object('bn', 'অনলাইন অর্ডার #' || o.order_no || ' এর বিক্রি (রসিদ ' || new.receipt || ') বাতিল হয়েছে — অর্ডার এখনো "ডেলিভারি হয়েছে" দেখাচ্ছে, যাচাই করুন',
                           'en', 'The sale of online order #' || o.order_no || ' (receipt ' || new.receipt || ') was voided - the order still says delivered; please check'));
  end loop;
  return new;
end $$;
drop trigger if exists sales_void_oo77 on public.sales;
create trigger sales_void_oo77 after update of status on public.sales for each row
  when (old.status is distinct from new.status and new.status = 'void') execute function public._oo_salevoid77();

create or replace function public.online_order_flags_list(p_loc int default null, p_state text default 'open') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'order_id', f.order_id, 'order_no', o.order_no, 'kind', f.kind, 'note', f.note, 'state', f.state, 'sale_id', f.sale_id, 'location_id', f.location_id, 'at', f.created_at) order by f.id desc)
     from public.online_order_flags f join public.online_orders o on o.id = f.order_id
    where public.can_loc(f.location_id) and (p_loc is null or f.location_id = p_loc) and (p_state is null or f.state = p_state)), '[]'::jsonb);
end $$;

create or replace function public.online_order_flag_review(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.online_order_flags;
begin
  select * into f from public.online_order_flags where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.is_active() or not public.can_do('POS', 'approve') or not public.can_loc(f.location_id) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'reason_required'; end if;
  update public.online_order_flags set state = 'reviewed', review_note = left(btrim(p_note), 300), reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'state', 'reviewed');
end $$;

-- 1. stock short list for an order (tracked items only)
create or replace function public._oo_short77(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.online_orders; r record; res jsonb := '[]'::jsonb; rsv boolean := public.rule_on('online_pack_reserve_on'); have numeric; reserved numeric;
begin
  select * into o from public.online_orders where id = p_order;
  if not found then return res; end if;
  for r in select (l->>'item_id')::uuid as item_id, sum((l->>'qty')::numeric) as need from jsonb_array_elements(o.lines) l where nullif(l->>'item_id', '') is not null group by 1 loop
    if not exists (select 1 from public.items i where i.id = r.item_id and i.tracked) then continue; end if;
    select coalesce(b.qty, 0) into have from (select 1) z left join public.stock_balance b on b.item_id = r.item_id and b.location_id = o.location_id;
    reserved := 0;
    if rsv then
      select coalesce(sum((l2->>'qty')::numeric), 0) into reserved from public.online_orders o2, jsonb_array_elements(o2.lines) l2
       where o2.location_id = o.location_id and o2.status = 'packed' and o2.id <> o.id and l2->>'item_id' = r.item_id::text;
    end if;
    if r.need > have - reserved then
      res := res || jsonb_build_object('item_id', r.item_id, 'name', (select name_bn from public.items where id = r.item_id), 'need', r.need, 'have', have, 'reserved', reserved, 'short_by', r.need - (have - reserved));
    end if;
  end loop;
  return res;
end $$;

create or replace function public.online_order_stock_check(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.online_orders;
begin
  select * into o from public.online_orders where id = p_id;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id, 'view');
  if not public.rule_on('online_pack_warn_on') then return jsonb_build_object('on', false, 'short', '[]'::jsonb); end if;
  return jsonb_build_object('on', true, 'reserve', public.rule_on('online_pack_reserve_on'), 'short', public._oo_short77(o.id));
end $$;

-- re-created (phase61 definition): bos77 = the warning at pack time. Never blocks.
create or replace function public.online_order_status(p_id uuid, p_to text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; sh jsonb := '[]'::jsonb; nt text := p_note;   -- bos77
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if p_to not in ('confirmed', 'packed') then raise exception 'bad_status'; end if;
  if o.status = p_to then return jsonb_build_object('id', o.id, 'status', o.status, 'noop', true); end if;
  if not ((o.status = 'new' and p_to = 'confirmed') or (o.status = 'confirmed' and p_to = 'packed')) then raise exception 'bad_status: % -> % is not allowed', o.status, p_to; end if;
  if p_to = 'packed' and public.rule_on('online_pack_warn_on') then                                      -- bos77
    sh := public._oo_short77(o.id);                                                                       -- bos77
    if jsonb_array_length(sh) > 0 then nt := left(coalesce(nullif(btrim(p_note), '') || ' | ', '') || 'STOCK SHORT: ' || (select string_agg(x->>'name' || ' need ' || (x->>'need') || ' have ' || (x->>'have'), ', ') from jsonb_array_elements(sh) x), 300); end if;   -- bos77
  end if;                                                                                                 -- bos77
  update public.online_orders set status = p_to, updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, o.status, p_to, nt);
  return jsonb_build_object('id', o.id, 'status', p_to) || case when jsonb_array_length(sh) > 0 then jsonb_build_object('warn', true, 'short', sh) else '{}'::jsonb end;   -- bos77
end $$;

-- re-created (phase61 definition): bos77 = optional "keep the order price"
create or replace function public.online_order_deliver(p_id uuid, p_payments jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; sl jsonb := '[]'; ln jsonb; pay jsonb := '[]'; res jsonb; sid uuid; cur numeric; nl jsonb; keep boolean := public.rule_on('online_keep_order_price');   -- bos77
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if o.sale_id is not null then return jsonb_build_object('id', o.id, 'status', o.status, 'sale_id', o.sale_id, 'dup', true); end if;
  if o.status <> 'packed' then raise exception 'bad_status: only a packed order can be delivered (now %)', o.status; end if;
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for ln in select * from jsonb_array_elements(o.lines) loop
    select sell_price into cur from public.items where id = (ln->>'item_id')::uuid;                                                      -- bos77
    nl := jsonb_build_object('item_id', ln->>'item_id', 'qty', (ln->>'qty')::numeric, 'price', (ln->>'price')::numeric);
    if keep and cur is distinct from (ln->>'price')::numeric then nl := nl || jsonb_build_object('override', true); end if;   -- bos77
    sl := sl || nl;
  end loop;
  if o.delivery_charge > 0 then sl := sl || jsonb_build_object('name', 'Delivery charge', 'amount', o.delivery_charge); end if;
  if o.advance > 0 then pay := pay || jsonb_build_object('mode', o.advance_mode, 'amount', o.advance, 'wallet', o.advance_wallet, 'ref', 'online order #' || o.order_no || ' advance'); end if;
  pay := pay || coalesce(p_payments, '[]'::jsonb);
  res := public.record_sale2(o.sale_client, o.location_id, sl, o.discount, pay, o.customer_mobile, o.customer_name, 'retail', 'Online order #' || o.order_no, false, null);
  sid := (res->>'id')::uuid;
  if exists (select 1 from public.online_orders x where x.sale_id = sid and x.id <> o.id) then raise exception 'sale_already_linked'; end if;
  update public.online_orders set status = 'delivered', sale_id = sid, delivered_by = auth.uid(), delivered_at = now(), updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, 'packed', 'delivered', 'sale receipt ' || (res->>'receipt'));
  return jsonb_build_object('id', o.id, 'status', 'delivered', 'sale_id', sid, 'receipt', res->'receipt', 'total', res->'total', 'paid', res->'paid', 'due', res->'due');
end $$;

create or replace function public.online_orders_list(p_loc int default null, p_status text default null, p_from date default null, p_to date default null, p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$   -- bos76: was STABLE (now writes the view audit)
declare r jsonb;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  r := coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.id, o.order_no, o.location_id, o.channel, o.customer_name,
           case when public._inb_contact_ok(o.location_id) then o.customer_mobile end as customer_mobile,   -- bos76
           o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at,
           o.channel_id, o.is_draft, not public._inb_contact_ok(o.location_id) as masked,                          -- bos76
           (select count(*) from public.online_order_flags f where f.order_id = o.id and f.state = 'open') as flags_open   -- bos77
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then   -- bos76
    perform public._inb_audit_view('online_orders', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $$;

create or replace function public.online_order_get(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$   -- bos76: was STABLE
declare o public.online_orders; ok boolean; j jsonb;
begin
  select * into o from public.online_orders where id = p_id;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  ok := public._inb_contact_ok(o.location_id);                                                                -- bos76
  if ok then perform public._inb_audit_view('online_orders', o.id::text, jsonb_build_object('fields', 'customer_mobile,address')); end if;   -- bos76
  j := to_jsonb(o) - 'sale_client';
  if not ok then j := (j - 'customer_mobile' - 'address') || jsonb_build_object('masked', true); end if;      -- bos76
  j := j || jsonb_build_object('flags', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'note', f.note, 'state', f.state, 'at', f.created_at) order by f.id) from public.online_order_flags f where f.order_id = o.id), '[]'::jsonb));   -- bos77
  return j || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $$;


-- =====================================================================
-- RLS + privileges
-- =====================================================================
alter table public.online_order_flags enable row level security;
revoke all on public.online_order_flags from public, anon, authenticated;
drop policy if exists online_order_flags_sel on public.online_order_flags;
grant select on public.online_order_flags to authenticated;
create policy online_order_flags_sel on public.online_order_flags for select to authenticated using (public.can_do('POS', 'view') and public.can_loc(location_id));
revoke usage, select on sequence public.online_order_flags_id_seq from public, anon, authenticated;
revoke all on function public.online_order_flags_list(int, text), public.online_order_flag_review(bigint, text), public.online_order_stock_check(uuid), public.online_order_status(uuid, text, text),
  public.online_order_deliver(uuid, jsonb), public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid) from public, anon;
grant execute on function public.online_order_flags_list(int, text), public.online_order_flag_review(bigint, text), public.online_order_stock_check(uuid), public.online_order_status(uuid, text, text),
  public.online_order_deliver(uuid, jsonb), public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid) to authenticated;
revoke all on function public._oo_flag_ro77(), public._oo_salevoid77(), public._oo_short77(uuid) from public, anon, authenticated;
notify pgrst, 'reload schema';
