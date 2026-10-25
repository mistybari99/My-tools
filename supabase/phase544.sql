-- Phase 544 (SW-7) - SWEETS TRANSFERS: a client id reused by ANOTHER user is refused (switch, OFF by default).
-- Paste AFTER phase543. Paste-twice safe (create or replace, on conflict do nothing). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, A5 (minor). Reproduced on a local throwaway database built from the full chain
-- (docs/PLAN_NEXT.md item 20): user A sends 5 kg with client id X; user B then sends 7 kg with the same X. The answer to B was
--   {"dup": true, "id": <A's transfer>, "status": "sent"}: B's 7 kg was NOT moved, and B's phone would mark its send as done.
-- One new switch, OFF by default. With it off, stock_transfer behaves exactly as in phase 499 (dup and the first transfer's id, as today).
--   transfer_client_reuse_block (false): ON = a reused client id from a different user is refused with client_id_reused.
--                                        The same user replaying the same id (a lost reply) still gets dup, as before.
-- Business reason (decided, not asked): a silent "done" for goods that never moved is worse than a visible refusal the phone can show.

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, 'stock', 'switch', 'false'::jsonb, null, null, null, null, v.lab, v.lab, v.lab, v.hint, v.hint, v.srt
  from (values
    ('transfer_client_reuse_block', 'অন্য ব্যবহারকারীর একই ট্রান্সফার আইডি বন্ধ / Refuse a transfer id already used by another user: on',
       'OFF = the second send is answered as done with the first transfer id (today). ON = refused with client_id_reused; nothing moves.', 5441)
  ) as v(key, lab, hint, srt)
on conflict (key) do nothing;

-- stock_transfer: as phase 499, plus the reused-id check in both places where a duplicate is found
create or replace function public.stock_transfer(p_from integer, p_to integer, p_item uuid, p_qty numeric, p_unit text default null, p_note text default null, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare it public.items; bq numeric; tid uuid := gen_random_uuid(); sid text; t public.stock_transfers; lid bigint;
begin
  it := public._stock_guard(p_item, p_from, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into t from public.stock_transfers where client_id = p_client;
    if found then
      if public.rule_on('transfer_client_reuse_block') and t.sent_by is distinct from auth.uid() then raise exception 'client_id_reused'; end if;
      return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status);
    end if;
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
    if found then
      if public.rule_on('transfer_client_reuse_block') and t.sent_by is distinct from auth.uid() then raise exception 'client_id_reused'; end if;
      return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status);
    end if;
    raise;
  end;
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out', 'transfer', tid::text, null, null, now(), left(p_note, 200), null, 'full');
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);
end $function$;
