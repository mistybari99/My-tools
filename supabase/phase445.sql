-- ============================================================
-- Phase 445 - RPT-C2 / R4 part 1 (reports #153-163): what the app order must capture - cake specification and the promised time slot.
-- Run AFTER phase 99 (needs phase61 online_orders). New file only: no old phase or function is edited. Paste twice = no error, no second row.
--
--   * order_cake_specs   one row per cake on an app order: weight (kg), flavour, message on the cake, design, photo reference. Replace = the old rows are voided, new rows added (history stays).
--   * order_promises     the promised time slot of an app order (from / to, Dhaka time). The promised DATE stays online_orders.delivery_date. Every change is a new row with a reason (append-only).
--   * c2_order_spec_save, c2_order_promise_set       write (POS enter, module online_orders_on, the order's place). Nothing here posts to the books.
--   * rule order_promise_required (OFF)             when ON an order cannot be confirmed before a promised slot exists. OFF = today.
--   * rule order_late_grace_minutes (blank)         blank = on time means delivered at or before the END of the promised slot (no grace invented).
--   * c2_orders_features()                           what the server has (the web asks once; older servers answer "no" and the screens fall back).
-- Paper form code for any printed version of the cake sheet: to be given by owner (the app sheet is a digital entry only; no new paper code is invented).
-- Helpers named _c2_* are closed to browsers; c2_can_read_orders() and c2_order_visible() are open because the row policies call them.
-- ============================================================
do $guard$ begin
  if to_regclass('public.online_orders') is null or to_regprocedure('public._i1_apply_hooks()') is null then
    raise exception 'phase445 needs phase61 (online orders) and phase99 pasted first';
  end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('order_promise_required', 'pos', 'switch', 'false', null, null, null, null, 'অর্ডার নিশ্চিত করার আগে ডেলিভারির সময়-স্লট লাগবে', 'Order confirm করার আগে promised time slot লাগবে', 'A promised time slot is needed before an order is confirmed',
  'বন্ধ থাকলে আগের মতোই; চালু করলে স্লট ছাড়া অর্ডার নিশ্চিত হবে না।', 'Off = as today. On = an app order cannot be confirmed until a promised time slot is written.', 640),
 ('order_late_grace_minutes', 'reports', 'number', null, 'min', null, 0, 1440, 'দেরি ধরার আগে কত মিনিট ছাড়', 'Late ধরার আগে কত minute ছাড়', 'Minutes of grace before a delivery counts as late',
  'ফাঁকা থাকলে স্লটের শেষ সময়ের পর দেরি ধরা হয়; কোনো ছাড় ধরা হয় না।', 'Blank = late means after the END of the promised slot; no grace is assumed.', 641)
 on conflict (key) do nothing;

-- ---------- helpers ----------
create or replace function public.c2_can_read_orders() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_grant('report_orders') or public.rpt_grant('view_reports') or public.can_do('POS', 'view'));
$$;
create or replace function public.c2_order_visible(p_order uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.online_orders o where o.id = p_order and public.can_loc(o.location_id));
$$;
create or replace function public._c2_staff() returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = auth.uid();
$$;
-- a trail table row may only be voided (state active -> void with the void_* fields); nothing else changes, nothing is deleted
create or replace function public._c2_trail_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.state = 'active' and new.state = 'void'
     and (to_jsonb(new) - 'state' - 'void_by' - 'void_at' - 'void_note') = (to_jsonb(old) - 'state' - 'void_by' - 'void_at' - 'void_note') then return new; end if;
  raise exception 'append_only: % is a trail, void the row instead', tg_table_name;
end $$;

-- ---------- cake specification ----------
create table if not exists public.order_cake_specs (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.online_orders(id),
  item_id uuid references public.items(id),
  weight_kg numeric check (weight_kg is null or (weight_kg > 0 and weight_kg <= 1000)),
  flavour text check (flavour is null or char_length(flavour) <= 80),
  message text check (message is null or char_length(message) <= 200),
  design text check (design is null or char_length(design) <= 300),
  photo_ref text check (photo_ref is null or char_length(photo_ref) <= 300),
  note text check (note is null or char_length(note) <= 300),
  state text not null default 'active' check (state in ('active', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text,
  check (weight_kg is not null or nullif(btrim(flavour), '') is not null or nullif(btrim(message), '') is not null or nullif(btrim(design), '') is not null or nullif(btrim(photo_ref), '') is not null or nullif(btrim(note), '') is not null)
);
create index if not exists order_cake_specs_order on public.order_cake_specs (order_id) where state = 'active';
drop trigger if exists order_cake_specs_ro on public.order_cake_specs;
create trigger order_cake_specs_ro before update or delete on public.order_cake_specs for each row execute function public._c2_trail_ro();
drop trigger if exists audit_order_cake_specs on public.order_cake_specs;
create trigger audit_order_cake_specs after insert or update on public.order_cake_specs for each row execute function public.log_change('id');

-- ---------- promised time slot ----------
create table if not exists public.order_promises (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.online_orders(id),
  slot_from time not null,
  slot_to time,
  reason text check (reason is null or char_length(reason) <= 300),
  state text not null default 'active' check (state in ('active', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text,
  check (slot_to is null or slot_to > slot_from)
);
create index if not exists order_promises_order on public.order_promises (order_id, id desc);
drop trigger if exists order_promises_ro on public.order_promises;
create trigger order_promises_ro before update or delete on public.order_promises for each row execute function public._c2_trail_ro();
drop trigger if exists audit_order_promises on public.order_promises;
create trigger audit_order_promises after insert or update on public.order_promises for each row execute function public.log_change('id');

-- the newest active promise of an order
create or replace function public._c2_promise_of(p_order uuid) returns public.order_promises language sql stable security definer set search_path = public as $$
  select * from public.order_promises where order_id = p_order and state = 'active' order by id desc limit 1;
$$;

-- optional gate: confirm needs a promised slot while the rule is ON (OFF = today)
create or replace function public._c2_promise_gate() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'confirmed' and old.status is distinct from 'confirmed' and public.rule_on('order_promise_required')
     and not exists (select 1 from public.order_promises where order_id = new.id and state = 'active') then
    raise exception 'promise_required: write the promised time slot before confirming this order';
  end if;
  return new;
end $$;
drop trigger if exists online_orders_c2_promise_gate on public.online_orders;
create trigger online_orders_c2_promise_gate before update on public.online_orders for each row when (new.status is distinct from old.status) execute function public._c2_promise_gate();

-- ---------- writers ----------
-- replace the cake specs of an open order. p_specs = [{item_id?, weight_kg?, flavour?, message?, design?, photo_ref?, note?}]; an empty array clears them.
create or replace function public.c2_order_spec_save(p_order uuid, p_specs jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; sp jsonb; n int := 0; w numeric; iid uuid; cur jsonb; nw jsonb := '[]'; fl text; ms text; dz text; ph text; nt text;
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if o.status in ('delivered', 'cancelled') then raise exception 'order_closed: a delivered or cancelled order cannot change'; end if;
  if p_specs is null or jsonb_typeof(p_specs) <> 'array' or jsonb_array_length(p_specs) > 20 then raise exception 'bad_specs'; end if;
  for sp in select * from jsonb_array_elements(p_specs) loop
    w := nullif(btrim(sp ->> 'weight_kg'), '')::numeric;
    if w is not null and (w = 'NaN'::numeric or w <= 0 or w > 1000) then raise exception 'bad_weight'; end if;
    iid := nullif(btrim(sp ->> 'item_id'), '')::uuid;
    if iid is not null and not exists (select 1 from jsonb_array_elements(o.lines) l where l ->> 'item_id' = iid::text) then raise exception 'item_not_on_order'; end if;
    fl := left(nullif(btrim(sp ->> 'flavour'), ''), 80); ms := left(nullif(btrim(sp ->> 'message'), ''), 200); dz := left(nullif(btrim(sp ->> 'design'), ''), 300);
    ph := left(nullif(btrim(sp ->> 'photo_ref'), ''), 300); nt := left(nullif(btrim(sp ->> 'note'), ''), 300);
    if w is null and fl is null and ms is null and dz is null and ph is null and nt is null then raise exception 'empty_spec'; end if;
    nw := nw || jsonb_build_object('item_id', iid, 'weight_kg', w, 'flavour', fl, 'message', ms, 'design', dz, 'photo_ref', ph, 'note', nt);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', item_id, 'weight_kg', weight_kg, 'flavour', flavour, 'message', message, 'design', design, 'photo_ref', photo_ref, 'note', note) order by id), '[]'::jsonb)
    into cur from public.order_cake_specs where order_id = o.id and state = 'active';
  if cur = nw then return jsonb_build_object('order_id', o.id, 'specs', jsonb_array_length(nw), 'noop', true); end if;
  update public.order_cake_specs set state = 'void', void_by = auth.uid(), void_at = now(), void_note = left(coalesce(nullif(btrim(p_note), ''), 'replaced'), 300) where order_id = o.id and state = 'active';
  for sp in select * from jsonb_array_elements(nw) loop
    insert into public.order_cake_specs (order_id, item_id, weight_kg, flavour, message, design, photo_ref, note, created_by, created_staff)
      values (o.id, nullif(sp ->> 'item_id', '')::uuid, nullif(sp ->> 'weight_kg', '')::numeric, sp ->> 'flavour', sp ->> 'message', sp ->> 'design', sp ->> 'photo_ref', sp ->> 'note', auth.uid(), public._c2_staff());
    n := n + 1;
  end loop;
  perform public._oo_event61(o.id, o.status, o.status, 'cake specification ' || case when n = 0 then 'cleared' else 'saved (' || n || ')' end);
  return jsonb_build_object('order_id', o.id, 'specs', n);
end $$;

-- write or change the promised time slot of an open order (a change needs a reason). Times are Dhaka clock times.
create or replace function public.c2_order_promise_set(p_order uuid, p_from time, p_to time default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; cur public.order_promises; id_ bigint;
begin
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if o.status in ('delivered', 'cancelled') then raise exception 'order_closed: a delivered or cancelled order cannot change'; end if;
  if p_from is null then raise exception 'slot_required'; end if;
  if p_to is not null and p_to <= p_from then raise exception 'bad_slot: the end must be after the start'; end if;
  if o.delivery_date is null then raise exception 'delivery_date_required: the promised date comes from the order delivery date'; end if;
  cur := public._c2_promise_of(o.id);
  if cur.id is not null then
    if cur.slot_from = p_from and cur.slot_to is not distinct from p_to then return jsonb_build_object('order_id', o.id, 'noop', true); end if;
    if nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  end if;
  insert into public.order_promises (order_id, slot_from, slot_to, reason, created_by, created_staff)
    values (o.id, p_from, p_to, left(nullif(btrim(p_reason), ''), 300), auth.uid(), public._c2_staff()) returning id into id_;
  perform public._oo_event61(o.id, o.status, o.status, 'promised slot ' || p_from::text || coalesce(' - ' || p_to::text, '') || coalesce(' | ' || nullif(btrim(p_reason), ''), ''));
  return jsonb_build_object('order_id', o.id, 'id', id_, 'slot_from', p_from, 'slot_to', p_to, 'date', o.delivery_date);
end $$;

-- what this server can do (the web asks once; a missing function = an older server = the old screens)
create or replace function public.c2_orders_features() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('v', 445,
    'spec', to_regprocedure('public.c2_order_spec_save(uuid,jsonb,text)') is not null,
    'promise', to_regprocedure('public.c2_order_promise_set(uuid,time without time zone,time without time zone,text)') is not null,
    'cost', to_regprocedure('public.c2_order_cost_add(uuid,text,numeric,text,text,uuid)') is not null,
    'cancel', to_regprocedure('public.c2_order_cancel(uuid,text,text,text)') is not null,
    'advance', to_regprocedure('public.c2_order_advance_post(uuid)') is not null,
    'detail', to_regprocedure('public.c2_order_detail(uuid)') is not null,
    'online_orders_on', public.rule_on('online_orders_on'), 'promise_required', public.rule_on('order_promise_required'),
    'refund_record_on', coalesce(public.rule_on('order_refund_record_on'), false), 'advance_post_on', coalesce(public.rule_on('order_advance_post_on'), false));
end $$;

-- ---------- RLS and privileges ----------
do $$ declare t text; begin
  foreach t in array array['order_cake_specs', 'order_promises'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.c2_can_read_orders() and public.c2_order_visible(order_id))', t || '_sel', t);
  end loop;
end $$;
do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
