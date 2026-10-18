-- ============================================================
-- Phase 492 - XB package part 2: custom-cake workflow on top of an app order.
-- Run AFTER phase 540 (and phase 445 / 448 for the order spec and cancel). New file only; no old phase or function is edited.
-- Paste twice = no error, no second row.
--
--   * cake_price_rules      owner-editable price table: base per kg, flavour extras and design extras (per kg or flat). Empty table = no quote
--                           (nothing is invented). Written only through xb_cake_price_rule_save (owner).
--   * xb_cake_quote         quote breakdown for a weight, flavour and design list (no write).
--   * cake_jobs             one cake job per app order: weight, flavour, layers, message, design notes, reference photos (paths),
--                           eggless / halal / allergen flags, due date and slot, quote lines, total, advance required, balance, state.
--   * cake_job_events       append-only trail of every state move: from, to, who (login and staff id), when, note.
--   * State chain: quoted -> confirmed (advance in the order) -> slip (production slip) -> baked -> decorated -> ready -> delivered.
--                  cancelled from any state before delivered; cancelling calls the existing c2_order_cancel (refund rules unchanged).
--                  delivered needs the app order to be delivered already (the money path stays the order's own path).
--   * Rules (OFF / blank): cake_flow_on (OFF), cake_capacity_day (blank = confirming and quoting are refused: no cap is invented),
--                  cake_lead_days (blank = refused), cake_photo_required (OFF: photo of the finished cake before delivery).
--   * xb_cake_create / xb_cake_confirm / xb_cake_move / xb_cake_photo / xb_cake_cancel: writers.
--   * xb_cake_due           production and decoration sheet for one day (printable in the web; no paper form code is invented).
--   * xb_cake_notify        customer confirmation: returns a wa.me text (the owner's phone taps send) and, when SMS is on and the customer
--                           has opted in and is not on do-not-contact, enqueues an SMS through notify_enqueue. Nothing is sent by this phase.
-- Birthday link to CRM and per-slot capacity: NOT built (see report).
-- Paper form code for a printed cake sheet: to be given by owner (none invented).
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.xb_pay_capture(uuid,text,text,text,numeric,timestamptz,text,int,text,uuid,uuid,text,text)') is null
     or to_regprocedure('public.c2_order_cancel(uuid,text,text,text)') is null or to_regprocedure('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)') is null
     or to_regprocedure('public.c2_order_spec_save(uuid,jsonb,text)') is null then
    raise exception 'phase541 needs phase540, phase445-448 and phase62 pasted first';
  end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('cake_flow_on', 'pos', 'switch', 'false', null, null, null, null, 'কাস্টম কেক ওয়ার্কফ্লো চালু', 'Custom cake workflow চালু', 'Custom cake workflow is on',
  'চালু হলে কেকের কোট, অ্যাডভান্স, উৎপাদন স্লিপ, ডেকোরেশন ও ডেলিভারি ধাপ লেখা যাবে।', 'When on, cake quote, advance, production slip, decoration and delivery steps can be recorded.', 542),
 ('cake_capacity_day', 'pos', 'number', null, 'cakes', null, 1, 1000, 'একদিনে সর্বোচ্চ কেক', 'Cake per day cap', 'Maximum cakes per day',
  'ফাঁকা থাকলে নতুন কেক কোট/নিশ্চিত করা যায় না। কোনো সংখ্যা ধরে নেওয়া হয় না।', 'Blank = cakes cannot be quoted or confirmed. No number is assumed.', 543),
 ('cake_lead_days', 'pos', 'number', null, 'days', null, 0, 90, 'কেক অর্ডারের আগাম দিন', 'Cake lead time (days)', 'Cake lead time (days)',
  'ফাঁকা থাকলে কেক নেওয়া যায় না। কত দিন আগে অর্ডার দিতে হবে তা মালিক ঠিক করেন।', 'Blank = cakes cannot be taken. The owner sets how many days ahead.', 544),
 ('cake_photo_required', 'pos', 'switch', 'false', null, null, null, null, 'ডেলিভারির আগে কেকের ছবি লাগবে', 'Cake photo before delivery', 'Photo of the finished cake is required before delivery',
  'চালু থাকলে তৈরি কেকের ছবি না থাকলে ডেলিভারি হবে না।', 'On = no delivery step without a photo of the finished cake.', 545)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('cake_price_manage', 'pos', 91, 'কেকের দামের তালিকা বদল', 'Cake price list বদল', 'Change the cake price list', 'once', null)
on conflict (grant_code) do nothing;

-- ---------- price rules ----------
create table if not exists public.cake_price_rules (
  id bigint generated always as identity primary key,
  code text not null unique check (code ~ '^[a-z0-9_]{2,40}$'),
  group_kind text not null check (group_kind in ('base', 'flavour', 'design')),
  rate_kind text not null check (rate_kind in ('per_kg', 'flat')),
  label_bn text not null check (char_length(btrim(label_bn)) between 1 and 80),
  label_en text not null check (char_length(btrim(label_en)) between 1 and 80),
  amount numeric not null check (amount >= 0 and amount <= 1000000000),
  active boolean not null default true,
  updated_by uuid, updated_at timestamptz not null default now()
);
create or replace function public._xb541_no_delete() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted: retire the row (active = false)'; end $$;
drop trigger if exists cake_price_rules_nodel on public.cake_price_rules;
create trigger cake_price_rules_nodel before delete on public.cake_price_rules for each row execute function public._xb541_no_delete();
drop trigger if exists audit_cake_price_rules on public.cake_price_rules;
create trigger audit_cake_price_rules after insert or update on public.cake_price_rules for each row execute function public.log_change('id');

create or replace function public.xb_cake_price_rule_save(p_code text, p_group text, p_rate text, p_label_bn text, p_label_en text, p_amount numeric, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('cake_price_manage', null)) then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,40}$' or p_group not in ('base', 'flavour', 'design') or p_rate not in ('per_kg', 'flat')
     or p_amount is null or p_amount < 0 or p_amount > 1000000000 or p_active is null then raise exception 'bad_input'; end if;
  if p_group = 'base' and p_rate <> 'per_kg' then raise exception 'bad_input: the base price is per kg'; end if;
  insert into public.cake_price_rules (code, group_kind, rate_kind, label_bn, label_en, amount, active, updated_by)
    values (p_code, p_group, p_rate, left(btrim(coalesce(p_label_bn, '')), 80), left(btrim(coalesce(p_label_en, '')), 80), p_amount, p_active, auth.uid())
    on conflict (code) do update set group_kind = excluded.group_kind, rate_kind = excluded.rate_kind, label_bn = excluded.label_bn, label_en = excluded.label_en,
      amount = excluded.amount, active = excluded.active, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('code', p_code, 'amount', p_amount, 'active', p_active);
end $$;

-- ---------- quote (no write) ----------
create or replace function public._xb541_quote(p_weight numeric, p_flavour text, p_designs text[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare base public.cake_price_rules; f public.cake_price_rules; d text; dr public.cake_price_rules; lines jsonb := '[]'; tot numeric := 0; amt numeric;
begin
  select * into base from public.cake_price_rules where group_kind = 'base' and active order by id limit 1;
  if not found then raise exception 'price_rules_missing: the owner has not set the cake base price'; end if;
  if p_weight is null or p_weight <= 0 or p_weight > 1000 then raise exception 'bad_weight'; end if;
  amt := round(p_weight * base.amount, 2);
  lines := lines || jsonb_build_object('code', base.code, 'group', 'base', 'label_en', base.label_en, 'label_bn', base.label_bn, 'rate', base.amount, 'basis', 'per_kg', 'qty', p_weight, 'amount', amt);
  tot := tot + amt;
  if nullif(btrim(coalesce(p_flavour, '')), '') is not null then
    select * into f from public.cake_price_rules where code = p_flavour and group_kind = 'flavour' and active;
    if not found then raise exception 'bad_flavour: no active flavour price with this code'; end if;
    amt := case when f.rate_kind = 'per_kg' then round(p_weight * f.amount, 2) else f.amount end;
    lines := lines || jsonb_build_object('code', f.code, 'group', 'flavour', 'label_en', f.label_en, 'label_bn', f.label_bn, 'rate', f.amount, 'basis', f.rate_kind, 'qty', case when f.rate_kind = 'per_kg' then p_weight else 1 end, 'amount', amt);
    tot := tot + amt;
  end if;
  foreach d in array coalesce(p_designs, '{}') loop
    select * into dr from public.cake_price_rules where code = d and group_kind = 'design' and active;
    if not found then raise exception 'bad_design: no active design extra with this code'; end if;
    amt := case when dr.rate_kind = 'per_kg' then round(p_weight * dr.amount, 2) else dr.amount end;
    lines := lines || jsonb_build_object('code', dr.code, 'group', 'design', 'label_en', dr.label_en, 'label_bn', dr.label_bn, 'rate', dr.amount, 'basis', dr.rate_kind, 'qty', case when dr.rate_kind = 'per_kg' then p_weight else 1 end, 'amount', amt);
    tot := tot + amt;
  end loop;
  return jsonb_build_object('lines', lines, 'total', round(tot, 2));
end $$;

create or replace function public.xb_cake_quote(p_weight numeric, p_flavour text default null, p_designs text[] default '{}') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  return public._xb541_quote(p_weight, p_flavour, p_designs);
end $$;

create or replace function public.xb_cake_price_rules_list() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_active() and (public.is_owner() or public.can_do('POS', 'view'))
    then coalesce((select jsonb_agg(to_jsonb(r) - 'updated_by' order by r.group_kind, r.code) from public.cake_price_rules r), '[]'::jsonb)
    else '[]'::jsonb end;
$$;

-- ---------- cake job ----------
create table if not exists public.cake_jobs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  order_id uuid not null unique references public.online_orders(id),
  location_id int not null references public.locations(id),
  due_date date not null,
  due_slot_from time,
  weight_kg numeric not null check (weight_kg > 0 and weight_kg <= 1000),
  flavour_code text references public.cake_price_rules(code),
  layers int check (layers is null or layers between 1 and 10),
  message text check (message is null or char_length(message) <= 200),
  design_notes text check (design_notes is null or char_length(design_notes) <= 500),
  design_codes text[] not null default '{}',
  ref_photos text[] not null default '{}',
  eggless boolean not null default false,
  halal boolean not null default false,
  allergen_note text check (allergen_note is null or char_length(allergen_note) <= 200),
  quote_lines jsonb not null,
  quote_total numeric not null check (quote_total >= 0),
  advance_required numeric not null check (advance_required >= 0 and advance_required <= quote_total),
  balance numeric generated always as (quote_total - advance_required) stored,
  photo_ready_path text check (photo_ready_path is null or char_length(photo_ready_path) <= 200),
  state text not null default 'quoted' check (state in ('quoted', 'confirmed', 'slip', 'baked', 'decorated', 'ready', 'delivered', 'cancelled')),
  state_at timestamptz not null default now(),
  cancel_reason text check (cancel_reason is null or char_length(cancel_reason) <= 300),
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists cake_jobs_due on public.cake_jobs (location_id, due_date) where state <> 'cancelled';

create table if not exists public.cake_job_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.cake_jobs(id),
  from_state text, to_state text not null, note text check (note is null or char_length(note) <= 300),
  by_user uuid, by_staff text, at timestamptz not null default now()
);
create index if not exists cake_job_events_job on public.cake_job_events (job_id, id);

-- trail and money-free fields: only state, photo and cancel fields move; nothing is deleted
create or replace function public._xb541_job_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted: a cake job is cancelled'; end if;
  if (to_jsonb(new) - 'state' - 'state_at' - 'photo_ready_path' - 'cancel_reason' - 'balance') is distinct from (to_jsonb(old) - 'state' - 'state_at' - 'photo_ready_path' - 'cancel_reason' - 'balance') then
    raise exception 'a cake job changes only its state, photo and cancel reason; the order and quote are fixed';
  end if;
  if old.state in ('delivered', 'cancelled') and new.state is distinct from old.state then raise exception 'closed: a delivered or cancelled cake job cannot change'; end if;
  return new;
end $$;
drop trigger if exists cake_jobs_ro on public.cake_jobs;
create trigger cake_jobs_ro before update or delete on public.cake_jobs for each row execute function public._xb541_job_ro();
drop trigger if exists audit_cake_jobs on public.cake_jobs;
create trigger audit_cake_jobs after insert or update on public.cake_jobs for each row execute function public.log_change('id');
drop trigger if exists cake_job_events_ro on public.cake_job_events;
create trigger cake_job_events_ro before update or delete on public.cake_job_events for each row execute function public._xb540_lines_ro();
drop trigger if exists audit_cake_job_events on public.cake_job_events;
create trigger audit_cake_job_events after insert on public.cake_job_events for each row execute function public.log_change('id');

create or replace function public._xb541_event(p_job uuid, p_from text, p_to text, p_note text) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.cake_job_events (job_id, from_state, to_state, note, by_user, by_staff)
    values (p_job, p_from, p_to, left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
end $$;

create or replace function public._xb541_gate(p_loc int) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('cake_flow_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', 'enter') or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
end $$;

-- create the job and its quote for an open app order. Capacity and lead time are checked here; the order spec is written too.
create or replace function public.xb_cake_create(p_order uuid, p_client uuid, p_due date, p_slot time, p_weight numeric, p_flavour text, p_layers int, p_message text,
  p_design_codes text[], p_design_notes text, p_eggless boolean, p_halal boolean, p_allergen text, p_ref_photos text[], p_advance numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; q jsonb; cap numeric := public.rule_num('cake_capacity_day'); lead numeric := public.rule_num('cake_lead_days'); n int; jid uuid; rec public.cake_jobs;
        photos text[] := coalesce(p_ref_photos, '{}'); adv numeric := coalesce(p_advance, 0);
begin
  if p_client is not null then
    select * into rec from public.cake_jobs where client_id = p_client;
    if found then return jsonb_build_object('id', rec.id, 'state', rec.state, 'dup', true); end if;
  end if;
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(o.location_id);
  if o.status not in ('new', 'confirmed') then raise exception 'order_closed: a cake is quoted on a new or confirmed order'; end if;
  if exists (select 1 from public.cake_jobs where order_id = o.id) then raise exception 'already_has_cake_job'; end if;
  if p_due is null or p_due < (now() at time zone 'Asia/Dhaka')::date then raise exception 'bad_date'; end if;
  if lead is null then raise exception 'lead_time_not_set: the owner must set the cake lead time'; end if;
  if p_due < (now() at time zone 'Asia/Dhaka')::date + lead::int then raise exception 'lead_time: a cake needs % day(s) notice', lead::int; end if;
  if cap is null then raise exception 'capacity_not_set: the owner must set the cakes per day'; end if;
  select count(*) into n from public.cake_jobs where location_id = o.location_id and due_date = p_due and state <> 'cancelled';
  if n >= cap::int then raise exception 'capacity_full: % cakes already due on this day', n; end if;
  if o.delivery_date is not null and o.delivery_date <> p_due then raise exception 'due_date_differs_from_order'; end if;
  if p_message is not null and char_length(p_message) > 200 then raise exception 'too_long'; end if;
  q := public._xb541_quote(p_weight, p_flavour, p_design_codes);
  if (q->>'total')::numeric > o.subtotal - o.discount + o.delivery_charge then raise exception 'order_total_below_quote: the order lines must carry the cake at its quoted total'; end if;
  if adv < 0 or adv > (q->>'total')::numeric then raise exception 'bad_advance'; end if;
  if array_length(photos, 1) > 5 then raise exception 'too_many_photos'; end if;
  perform public.c2_order_spec_save(o.id, jsonb_build_array(jsonb_build_object('weight_kg', p_weight, 'flavour', p_flavour, 'message', p_message,
      'design', p_design_notes, 'photo_ref', photos[1])), 'cake job');
  insert into public.cake_jobs (client_id, order_id, location_id, due_date, due_slot_from, weight_kg, flavour_code, layers, message, design_notes, design_codes, ref_photos,
      eggless, halal, allergen_note, quote_lines, quote_total, advance_required, created_by, created_staff)
    values (p_client, o.id, o.location_id, p_due, p_slot, p_weight, nullif(p_flavour, ''), p_layers, nullif(btrim(p_message), ''), nullif(btrim(p_design_notes), ''),
      coalesce(p_design_codes, '{}'), photos, coalesce(p_eggless, false), coalesce(p_halal, false), nullif(btrim(p_allergen), ''), q->'lines', (q->>'total')::numeric, adv,
      auth.uid(), (select staff_id from public.profiles where id = auth.uid()))
    returning id into jid;
  perform public._xb541_event(jid, null, 'quoted', 'quote ' || (q->>'total') || ', advance ' || adv::text);
  return jsonb_build_object('id', jid, 'state', 'quoted', 'quote', q, 'advance_required', adv, 'balance', (q->>'total')::numeric - adv, 'due_count_after', n + 1);
end $$;

-- quote -> confirmed: needs the advance already in the order (the order advance field) at least the advance required
create or replace function public.xb_cake_confirm(p_job uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; o public.online_orders;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if j.state = 'confirmed' then return jsonb_build_object('id', j.id, 'state', 'confirmed', 'noop', true); end if;
  if j.state <> 'quoted' then raise exception 'bad_status: only a quoted cake can be confirmed (now %)', j.state; end if;
  select * into o from public.online_orders where id = j.order_id;
  if o.advance < j.advance_required then raise exception 'advance_required: the order must carry at least % before the cake is confirmed', j.advance_required; end if;
  update public.cake_jobs set state = 'confirmed', state_at = now() where id = j.id;
  perform public._xb541_event(j.id, 'quoted', 'confirmed', 'advance ' || o.advance::text);
  return jsonb_build_object('id', j.id, 'state', 'confirmed');
end $$;

-- the forward chain. delivered also needs the app order delivered and, when the switch is on, the finished-cake photo.
create or replace function public.xb_cake_move(p_job uuid, p_to text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; o public.online_orders; nxt text;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if p_to not in ('slip', 'baked', 'decorated', 'ready', 'delivered') then raise exception 'bad_status'; end if;
  if j.state = p_to then return jsonb_build_object('id', j.id, 'state', j.state, 'noop', true); end if;
  nxt := case j.state when 'confirmed' then 'slip' when 'slip' then 'baked' when 'baked' then 'decorated' when 'decorated' then 'ready' when 'ready' then 'delivered' else null end;
  if nxt is distinct from p_to then raise exception 'bad_status: % -> % is not allowed', j.state, p_to; end if;
  if p_to = 'delivered' then
    select * into o from public.online_orders where id = j.order_id;
    if o.status <> 'delivered' then raise exception 'order_not_delivered: deliver the app order first (its own money path)'; end if;
    if public.rule_on('cake_photo_required') and j.photo_ready_path is null then raise exception 'photo_required: a photo of the finished cake is needed first'; end if;
  end if;
  update public.cake_jobs set state = p_to, state_at = now() where id = j.id;
  perform public._xb541_event(j.id, j.state, p_to, p_note);
  return jsonb_build_object('id', j.id, 'state', p_to);
end $$;

create or replace function public.xb_cake_photo(p_job uuid, p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if j.state not in ('decorated', 'ready') then raise exception 'bad_status: the photo is taken when the cake is decorated or ready'; end if;
  if p_path is null or p_path !~ ('^cake/' || j.location_id || '/[A-Za-z0-9_.-]{1,120}\.jpe?g$') then raise exception 'bad_path'; end if;
  update public.cake_jobs set photo_ready_path = p_path where id = j.id;
  perform public._xb541_event(j.id, j.state, j.state, 'photo of the finished cake');
  return jsonb_build_object('id', j.id, 'photo_ready_path', p_path);
end $$;

-- cancel before delivery: the refund and advance rules are the existing order cancel (phase 448)
create or replace function public.xb_cake_cancel(p_job uuid, p_reason text, p_advance_fate text default 'none', p_refund_mode text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; r jsonb;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if j.state = 'cancelled' then return jsonb_build_object('id', j.id, 'state', 'cancelled', 'noop', true); end if;
  if j.state = 'delivered' then raise exception 'order_closed: a delivered cake is not cancelled; use the sale return'; end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
  r := public.c2_order_cancel(j.order_id, btrim(p_reason), p_advance_fate, p_refund_mode);
  update public.cake_jobs set state = 'cancelled', state_at = now(), cancel_reason = left(btrim(p_reason), 300) where id = j.id;
  perform public._xb541_event(j.id, j.state, 'cancelled', btrim(p_reason));
  return jsonb_build_object('id', j.id, 'state', 'cancelled', 'order', r);
end $$;

-- the production and decoration sheet for one day (cakes due on that day, not cancelled)
create or replace function public.xb_cake_due(p_date date, p_loc int default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_active() or not public.can_do('POS', 'view') then '{"rows":[]}'::jsonb else jsonb_build_object(
    'date', p_date,
    'count', (select count(*) from public.cake_jobs j where j.due_date = p_date and j.state <> 'cancelled' and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)),
    'total_kg', (select coalesce(sum(j.weight_kg), 0) from public.cake_jobs j where j.due_date = p_date and j.state <> 'cancelled' and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('job_id', j.id, 'order_no', o.order_no, 'slot', j.due_slot_from, 'weight_kg', j.weight_kg, 'layers', j.layers,
        'flavour', j.flavour_code, 'message', j.message, 'design', j.design_notes, 'design_codes', j.design_codes, 'eggless', j.eggless, 'halal', j.halal,
        'allergen', j.allergen_note, 'state', j.state, 'delivery_mode', o.delivery_mode, 'customer', o.customer_name, 'balance', j.balance, 'ref_photos', j.ref_photos)
        order by j.due_slot_from nulls last, j.id)
      from public.cake_jobs j join public.online_orders o on o.id = j.order_id
      where j.due_date = p_date and j.state <> 'cancelled' and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)), '[]'::jsonb)) end;
$$;

-- customer confirmation: a wa.me text for the owner's tap, and an SMS queued only when SMS is on, the customer opted in and is not do-not-contact
create or replace function public.xb_cake_notify(p_job uuid, p_template text default 'cake_confirmed') returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; o public.online_orders; cu uuid; mob text; txt text; q jsonb; dnc boolean := false; enq jsonb := null;
begin
  select * into j from public.cake_jobs where id = p_job;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if p_template not in ('cake_confirmed', 'cake_ready') then raise exception 'bad_template'; end if;
  select * into o from public.online_orders where id = j.order_id;
  mob := public.norm_mobile(o.customer_mobile);
  txt := case when p_template = 'cake_ready' then 'Your cake (order #' || o.order_no || ') is ready for ' || j.due_date::text || '.'
              else 'Your cake order #' || o.order_no || ' is confirmed for ' || j.due_date::text || '. Advance ' || j.advance_required::text || ', balance ' || j.balance::text || ' taka.' end;
  select c.id into cu from public.customers c where c.mobile = mob;
  if cu is not null then select coalesce(p.dnc, false) into dnc from public.crm_contact_prefs p where p.customer_id = cu; end if;
  if cu is not null and not dnc and public.rule_on('notify_sms_on') then
    enq := public.notify_enqueue(gen_random_uuid(), cu, 'sms', p_template, jsonb_build_object('ref', '#' || o.order_no, 'date', j.due_date::text), 'en', 'cake_job', j.id::text);
  end if;
  return jsonb_build_object('id', j.id, 'wa_phone', case when mob like '01%' then '880' || substr(mob, 2) end, 'wa_text', txt,
    'sms', coalesce(to_jsonb(case when cu is null then 'no_customer_record' when dnc then 'do_not_contact' when not public.rule_on('notify_sms_on') then 'sms_off' end), enq));
end $$;

create or replace function public.xb_cake_job_get(p_order uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_active() or not public.can_do('POS', 'view') then null else (
    select to_jsonb(j) - 'client_id' || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_state, 'to', e.to_state, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
        from public.cake_job_events e where e.job_id = j.id), '[]'::jsonb))
    from public.cake_jobs j where j.order_id = p_order and public.can_loc(j.location_id) ) end;
$$;

-- ---------- privileges and RLS ----------
alter table public.cake_price_rules enable row level security;
alter table public.cake_jobs enable row level security;
alter table public.cake_job_events enable row level security;
revoke all on public.cake_price_rules, public.cake_jobs, public.cake_job_events from public, anon, authenticated;
grant select on public.cake_price_rules, public.cake_jobs, public.cake_job_events to authenticated;
drop policy if exists cake_price_rules_sel on public.cake_price_rules;
create policy cake_price_rules_sel on public.cake_price_rules for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')));
drop policy if exists cake_jobs_sel on public.cake_jobs;
create policy cake_jobs_sel on public.cake_jobs for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists cake_job_events_sel on public.cake_job_events;
create policy cake_job_events_sel on public.cake_job_events for select to authenticated
  using (public.is_active() and exists (select 1 from public.cake_jobs j where j.id = job_id and public.can_loc(j.location_id)));

insert into public.notify_templates (code, channel, body_bn, body_en) values
 ('cake_confirmed', 'sms', 'আপনার কেক অর্ডার {ref} নিশ্চিত হয়েছে, তারিখ {date}। - {shop}', 'Your cake order {ref} is confirmed for {date}. - {shop}'),
 ('cake_ready', 'sms', 'আপনার কেক {ref} প্রস্তুত, তারিখ {date}। - {shop}', 'Your cake {ref} is ready for {date}. - {shop}')
on conflict (code) do nothing;

do $x$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'xb\_cake\_%' or p.proname like '\_xb541\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname like 'xb\_cake\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $x$;
notify pgrst, 'reload schema';
