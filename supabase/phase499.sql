-- Phase 499 (SW-1) - SWEETS STOCK TRANSFERS: partial receipt in steps, paused destination, over-send.
-- Paste AFTER phase498. Paste-twice safe (create or replace, on conflict do nothing). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, A5 (factory to branch) and findings F-14 / F-15. Reproduced on a local throwaway
-- database built from the owner paste chain (before this file):
--   R1 over-send: 120 kg sent from a place with 100 kg on hand under the default stock_negative_mode 'warn': sender stock became -20.
--   R2 paused destination: a send to a place with status 'paused' was accepted.
--   R3 partial receipt: 20 kg sent, 8 received, the second receipt returned status 'received' and dup = true; 12 kg stayed in transit for ever.
-- Three new switches, ALL OFF by default. With every switch off, every function behaves exactly as before this file.
--   transfer_overdraw_block  (false): refuse a send that is bigger than the sender's stock on hand (error insufficient_stock).
--   transfer_paused_block    (false): refuse a send to a place whose status is not 'live' (error destination_paused).
--   transfer_partial_on      (false): a receipt may be part of the delivery. The transfer stays open ('sent') until the whole quantity has
--                                     arrived or the owner closes the rest with stock_close_transfer_short (the rest is then a transit_short
--                                     yellow exception, as today). The second and later receipts take goods from the first lines of the
--                                     delivery that have not arrived yet, so batches and unit cost travel with the goods.
-- Damage on a partial receipt is added up over the steps (received_damaged_qty is the total).
-- Business reasons (decided, not asked): an over-send makes a negative balance at the factory that nobody physically holds, so the owner
-- can refuse it; a send to a paused place puts goods where no one is open to receive them; a split delivery is normal for a factory that ships
-- by van in several lots. Each switch is listed in web/data/info.json so the owner sees what it does before switching it on.

do $g$ begin
  if to_regclass('public.stock_transfers') is null or to_regclass('public.stock_ledger') is null or to_regclass('public.locations') is null then
    raise exception 'phase499 needs the stock tables and locations (phase 3 to 10)';
  end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, 'stock', 'switch', 'false'::jsonb, null, null, null, null, v.lab, v.lab, v.lab, v.hint, v.hint, v.srt
  from (values
    ('transfer_overdraw_block', 'পাঠানোর আগে স্টক যাচাই (স্টকের চেয়ে বেশি পাঠানো বন্ধ) / Refuse a send bigger than the stock on hand: on',
       'OFF = the send is accepted and the sender balance may go negative (today). ON = the send is refused with insufficient_stock.', 4991),
    ('transfer_paused_block', 'বন্ধ/স্থগিত জায়গায় পাঠানো বন্ধ / Refuse a send to a paused or closed place: on',
       'OFF = a send to a paused place is accepted (today). ON = refused with destination_paused.', 4992),
    ('transfer_partial_on', 'ভাগে ভাগে গ্রহণ (আংশিক রসিদ) / Receive a transfer in parts (partial receipt): on',
       'OFF = one receipt closes the transfer (today). ON = the transfer stays open until all arrives or is closed short by the owner.', 4993)
  ) as v(key, lab, hint, srt)
on conflict (key) do nothing;

-- 1. send: the two checks in front of the stock movement (the rest is the same as phase 3 to 10 wrote it)
create or replace function public.stock_transfer(p_from integer, p_to integer, p_item uuid, p_qty numeric, p_unit text default null, p_note text default null, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare it public.items; bq numeric; tid uuid := gen_random_uuid(); sid text; t public.stock_transfers; lid bigint;
begin
  it := public._stock_guard(p_item, p_from, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into t from public.stock_transfers where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  end if;
  if p_to is null or p_to = p_from or not exists (select 1 from public.locations where id = p_to) then raise exception 'bad_location'; end if;
  if public.rule_on('transfer_paused_block') and coalesce((select l.status from public.locations l where l.id = p_to), '') <> 'live' then
    raise exception 'destination_paused';
  end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if not public._may('stock_transfer', p_from, 'transfer:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  if public.rule_on('transfer_overdraw_block') and coalesce((select sb.qty from public.stock_balance sb where sb.item_id = p_item and sb.location_id = p_from), 0) < bq then
    raise exception 'insufficient_stock';
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  begin
    insert into public.stock_transfers (id, client_id, from_location_id, to_location_id, item_id, qty, note, sent_by, sent_staff)
      values (tid, p_client, p_from, p_to, p_item, bq, left(p_note, 200), auth.uid(), sid);
  exception when unique_violation then          -- the same client id arrived twice at once: the first one wins
    select * into t from public.stock_transfers where p_client is not null and client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
    raise;
  end;
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out', 'transfer', tid::text, null, null, now(), left(p_note, 200), null, 'full');
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);
end $function$;

-- 2. receive: one step (as before) or several steps (switch transfer_partial_on)
create or replace function public.stock_receive_transfer(p_id uuid, p_received_qty numeric default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare t public.stock_transfers; it public.items; rq numeric; sid text; o record; rem numeric; take numeric; nb bigint; ob public.stock_batches;
  lid bigint; got numeric; skip numeric; avail numeric; left_qty numeric; partial boolean;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'received' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if not public._may('stock_transfer', t.to_location_id, 'receive:' || p_id::text, t.qty) then raise exception 'not allowed'; end if;
  -- what has already arrived in earlier steps of this delivery (always 0 when the switch is off: one receipt closes the transfer)
  got := coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_in'), 0);
  left_qty := t.qty - got;
  rq := coalesce(p_received_qty, left_qty);
  if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if rq > left_qty then raise exception 'over_received'; end if;
  partial := public.rule_on('transfer_partial_on') and rq < left_qty;
  rem := rq;
  skip := got;
  for o in select * from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' order by id loop
    exit when rem <= 0;
    avail := -o.qty_delta;
    if skip >= avail then skip := skip - avail; continue; end if;      -- this line already arrived in an earlier step
    avail := avail - skip;
    skip := 0;
    take := least(avail, rem);
    nb := null;
    if o.batch_id is not null then       -- the batch travels with the goods: same made-at and expiry at the destination
      select * into ob from public.stock_batches where id = o.batch_id;
      insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
        values (t.item_id, t.to_location_id, ob.made_at, take, take, ob.expires_at, ob.shelf_rule, 'transfer', auth.uid()) returning id into nb;
    end if;
    lid := public.stock_post(t.item_id, t.to_location_id, take, 'transfer_in', 'transfer', t.id::text, o.unit_cost, nb, now(), left(p_note, 200), null, 'none');
    rem := rem - take;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if partial then
    update public.stock_transfers set received_qty = got + rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
    return jsonb_build_object('id', t.id, 'status', 'sent', 'partial', true, 'received_qty', got + rq, 'remaining', left_qty - rq);
  end if;
  update public.stock_transfers set status = 'received', received_qty = got + rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
  if got + rq < t.qty then
    perform public._stock_exc(t.to_location_id, 'transit_short', 'yellow',
      it.name_bn || ': পাঠানো ' || t.qty::text || ', গ্রহণ ' || (got + rq)::text || ' — পথে কম', coalesce(it.name_en, it.name_bn) || ': sent ' || t.qty::text || ', received ' || (got + rq)::text || ' — short in transit');
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', got + rq, 'short', t.qty - got - rq);
end $function$;

-- 3. receive with the damage count (phase 3 to 10 wrapper); the damage is added up over the steps
create or replace function public.stock_receive_transfer(p_id uuid, p_received_qty numeric, p_note text, p_damaged_qty numeric, p_damaged_reason text)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare t public.stock_transfers; rq numeric; res jsonb; dq numeric := p_damaged_qty; rs text := nullif(btrim(p_damaged_reason), ''); it public.items; got numeric;
begin
  select * into t from public.stock_transfers where id = p_id;
  if not found then raise exception 'not found'; end if;
  got := coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_in'), 0);
  rq := coalesce(p_received_qty, t.qty - got);
  if dq is not null then
    if not (dq between 0 and 999999999) then raise exception 'bad_qty'; end if;
    if dq > rq then raise exception 'damaged_over_received'; end if;
    if dq > 0 and (rs is null or not exists (select 1 from public.option_lists where list_code = 'transfer_damage_reasons' and value_code = rs and active)) then raise exception 'damage_reason_required'; end if;
    if dq = 0 then rs := null; end if;
  end if;
  res := public.stock_receive_transfer(p_id, p_received_qty, p_note);          -- the 3-argument function: every rule (grant, short quantity, batches, exception, parts)
  if coalesce((res ->> 'dup')::boolean, false) then return res; end if;
  if dq is not null then
    update public.stock_transfers set received_damaged_qty = coalesce(received_damaged_qty, 0) + dq, damaged_reason = coalesce(rs, damaged_reason) where id = p_id;
    if dq > 0 then
      select * into it from public.items where id = t.item_id;
      perform public._stock_exc(t.to_location_id, 'transit_damaged', 'yellow', it.name_bn || ': গ্রহণ ' || rq::text || ', তার মধ্যে ' || dq::text || ' ক্ষতিগ্রস্ত',
        coalesce(it.name_en, it.name_bn) || ': received ' || rq::text || ', of which ' || dq::text || ' damaged');
    end if;
  end if;
  return res || jsonb_build_object('damaged', dq);
end $function$;

-- 4. the owner closes the rest of a split delivery as short (only when transfer_partial_on is on)
create or replace function public.stock_close_transfer_short(p_id uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare t public.stock_transfers; it public.items; got numeric; sid text;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'received' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  if not public.rule_on('transfer_partial_on') then raise exception 'partial_receipt_off'; end if;
  if not public._may('stock_transfer', t.to_location_id, 'receive:' || p_id::text, t.qty) then raise exception 'not allowed'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  got := coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_in'), 0);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.stock_transfers set status = 'received', received_qty = got, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
  if got < t.qty then
    perform public._stock_exc(t.to_location_id, 'transit_short', 'yellow',
      it.name_bn || ': পাঠানো ' || t.qty::text || ', গ্রহণ ' || got::text || ' — পথে কম (বাকি বন্ধ করা হয়েছে)',
      coalesce(it.name_en, it.name_bn) || ': sent ' || t.qty::text || ', received ' || got::text || ' — short in transit (rest closed by the owner)');
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', got, 'short', t.qty - got);
end $function$;

-- Privileges: the same as the functions they replace (authenticated only). New function: closing a split delivery.
revoke all on function public.stock_close_transfer_short(uuid, text) from public, anon;
grant execute on function public.stock_close_transfer_short(uuid, text) to authenticated;
