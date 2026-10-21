-- Phase 324 (bos324, package CRM-G label 124, part 2 of 5) - LEADS: SAVE, NOTES, ASSIGN, STAGE MOVES, LOST WITH A REASON, REOPEN WITH A REASON, QUOTES.
-- Paste AFTER phase323. Paste-twice safe. Nothing here posts to the books: no journal, sale, payment or stock line is written; a quote is a priced list, not an invoice.
-- Rights: see phase323 (a lead is visible to the owner, to crm_lead_all, and otherwise only inside the outlets of the person as assignee, maker or crm_lead_manage).
-- Every function answers module_off while the switch crm_lead_on is OFF (default), and refuses a person without the right on the SERVER (a hidden button is also a refused request).

do $g$ begin
  if to_regprocedure('public._crmg_present()') is null or to_regclass('public.crm_leads') is null then raise exception 'phase324 needs phase323 first'; end if;
end $g$;

-- ============================================================================
-- 1. HELPERS
-- ============================================================================
-- a phone number as typed: a Bangladesh mobile is normalised (01XXXXXXXXX); any other number (a landline, a foreign number) is kept as digits and +
create or replace function public._crmg_norm_phone(p text) returns text language plpgsql immutable as $$
declare d text;
begin
  if p is null or btrim(p) = '' then return null; end if;
  begin return public.norm_mobile(p); exception when others then null; end;
  d := regexp_replace(translate(p, '০১২৩৪৫৬৭৮৯', '0123456789'), '[^0-9+]', '', 'g');
  if char_length(d) not between 6 and 20 or p ~ '[A-Za-z]' then raise exception 'bad_phone: the phone number is not valid'; end if;
  return d;
end $$;

-- may the caller work on this lead (not only see it)
create or replace function public._crmg_can_act(p_loc int, p_owner uuid, p_created uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._crmg_lead_mgr(p_loc) or (public.can_loc(p_loc) and (p_owner = auth.uid() or p_created = auth.uid()))) $$;

-- load a lead the caller may see, locked for update; the answer for an unseen lead is the same as for a missing one (no hint that another outlet has it)
create or replace function public._crmg_lead_load(p_id uuid, p_lock boolean default true) returns public.crm_leads
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_lead_on() then raise exception 'module_off: enquiry tracking is switched off'; end if;
  if p_lock then select * into l from public.crm_leads where id = p_id for update; else select * into l from public.crm_leads where id = p_id; end if;
  if not found or not public._crmg_lead_vis(l.location_id, l.owner_user, l.created_by) then raise exception 'not_found'; end if;
  return l;
end $$;

-- open follow-up tasks of a lead are replaced by one task for the new date (only when tasks are switched on); nothing happens while crm_task_on is OFF
create or replace function public._crmg_lead_task_sync(p_lead uuid, p_due timestamptz, p_title text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; t uuid; r record;
begin
  if not public._crmg_task_on() then return null; end if;
  select * into l from public.crm_leads where id = p_lead;
  if not found then return null; end if;
  for r in select id from public.crm_tasks where lead_id = p_lead and source = 'lead' and kind = 'follow_up' and status = 'open' for update loop
    update public.crm_tasks set status = 'skipped', skip_reason = 'replaced by a new follow-up date', done_by = null where id = r.id;
    insert into public.crm_task_events (task_id, by_user, by_staff, kind, note) values (r.id, auth.uid(), public._crmg_staff(), 'skipped', 'replaced by a new follow-up date');
  end loop;
  if p_due is null then return null; end if;
  insert into public.crm_tasks (location_id, customer_id, lead_id, kind, title, due_at, assigned_to, source, created_by)
    values (l.location_id, l.customer_id, l.id, 'follow_up', left(coalesce(nullif(btrim(p_title), ''), 'Follow up: ' || l.contact_name), 120), p_due, l.owner_user, 'lead', auth.uid()) returning id into t;
  insert into public.crm_task_events (task_id, by_user, by_staff, kind, note) values (t, auth.uid(), public._crmg_staff(), 'created', 'made from the enquiry follow-up date');
  return t;
end $$;

-- the open lead tasks end when the lead is closed
create or replace function public._crmg_lead_tasks_close(p_lead uuid, p_why text) returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select id from public.crm_tasks where lead_id = p_lead and source = 'lead' and status = 'open' for update loop
    update public.crm_tasks set status = 'skipped', skip_reason = p_why where id = r.id;
    insert into public.crm_task_events (task_id, by_user, by_staff, kind, note) values (r.id, auth.uid(), public._crmg_staff(), 'skipped', p_why);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ============================================================================
-- 2. SAVE (create or edit). p_data keys: contact_name, contact_phone, customer_id, source, occasion, event_date, guests, est_value, owner_user, next_follow_up,
--    note, inbound_message_id, quote_ref, make_task. On an edit only the keys that are present change. Idempotent on p_client.
-- ============================================================================
create or replace function public._crmg_lead_save(p_id uuid, p_client uuid, p_loc int, p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'::jsonb); l public.crm_leads; loc int; nm text; ph text; cust uuid; own uuid; nfu timestamptz; ev date; gs int; est numeric; src text; occ text; nt text; qr text;
        msg bigint; m public.inbound_messages; c public.customers; dups jsonb; changed text[] := '{}'; mob text; is_new boolean := p_id is null;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_lead_on() then raise exception 'module_off: enquiry tracking is switched off'; end if;
  if jsonb_typeof(d) <> 'object' then raise exception 'bad_data'; end if;
  if is_new then
    perform public._client_lock(p_client);
    if p_client is not null then
      select * into l from public.crm_leads where created_by = auth.uid() and client_id = p_client;
      if found then return jsonb_build_object('id', l.id, 'lead_no', l.lead_no, 'stage', l.stage, 'dup', true); end if;
    end if;
    loc := p_loc;
    if loc is null or not exists (select 1 from public.locations where id = loc and is_active) then raise exception 'location_required'; end if;
    if not public._crmg_can_create(loc) then raise exception 'not allowed'; end if;
  else
    l := public._crmg_lead_load(p_id, true);
    loc := l.location_id;
    if not public._crmg_can_act(loc, l.owner_user, l.created_by) then raise exception 'not allowed'; end if;
    if l.stage in ('won', 'lost') then raise exception 'lead_closed: a won or lost enquiry cannot be edited'; end if;
  end if;

  -- customer (an existing record only; a lead never creates a customer)
  cust := case when d ? 'customer_id' then nullif(d->>'customer_id', '')::uuid else l.customer_id end;
  if cust is not null then
    select * into c from public.customers where id = cust;
    if not found then raise exception 'customer_not_found'; end if;
  end if;
  nm := case when d ? 'contact_name' then left(btrim(coalesce(d->>'contact_name', '')), 80) else l.contact_name end;
  ph := case when d ? 'contact_phone' then public._crmg_norm_phone(d->>'contact_phone') else l.contact_phone end;
  -- an enquiry from the inbox: fill what is blank from the message; one message belongs to one enquiry
  msg := case when d ? 'inbound_message_id' then nullif(d->>'inbound_message_id', '')::bigint else l.inbound_message_id end;
  if msg is not null and msg is distinct from l.inbound_message_id then
    select * into m from public.inbound_messages where id = msg;
    if not found or not public.can_loc(m.location_id) then raise exception 'message_not_found'; end if;
    if m.location_id <> loc then raise exception 'message_other_outlet'; end if;
    if exists (select 1 from public.crm_leads x where x.inbound_message_id = msg) then raise exception 'message_already_tracked: this message already has an enquiry'; end if;
    if coalesce(nm, '') = '' then nm := left(btrim(coalesce(m.customer_name, '')), 80); end if;
  end if;
  if coalesce(nm, '') = '' and c.id is not null then nm := left(c.name, 80); end if;
  if coalesce(btrim(nm), '') = '' then raise exception 'contact_name_required'; end if;
  if cust is null and ph is not null then          -- link the customer who owns this exact mobile, if there is one
    begin mob := public.norm_mobile(ph); select id into cust from public.customers where mobile = mob; exception when others then null; end;
  end if;
  src := case when d ? 'source' then nullif(btrim(d->>'source'), '') else l.source end;
  if src is not null and not public._crmg_list_ok('source', src) then raise exception 'unknown_source'; end if;
  occ := case when d ? 'occasion' then nullif(btrim(d->>'occasion'), '') else l.occasion end;
  if occ is not null and not public._crmg_list_ok('occasion', occ) then raise exception 'unknown_occasion'; end if;
  begin ev := case when d ? 'event_date' then nullif(d->>'event_date', '')::date else l.event_date end; exception when others then raise exception 'bad_date'; end;
  begin gs := case when d ? 'guests' then nullif(d->>'guests', '')::int else l.guests end; exception when others then raise exception 'bad_guests'; end;
  if gs is not null and gs not between 1 and 100000 then raise exception 'bad_guests'; end if;
  begin est := case when d ? 'est_value' then nullif(d->>'est_value', '')::numeric else l.est_value end; exception when others then raise exception 'bad_amount'; end;
  if est is not null and (est = 'NaN'::numeric or est < 0 or est > 1000000000000) then raise exception 'bad_amount'; end if;
  begin nfu := case when d ? 'next_follow_up' then nullif(d->>'next_follow_up', '')::timestamptz else l.next_follow_up end; exception when others then raise exception 'bad_follow_up'; end;
  if nfu is not null and nfu > now() + interval '2 years' then raise exception 'bad_follow_up'; end if;
  nt := case when d ? 'note' then left(nullif(btrim(d->>'note'), ''), 300) else l.note end;
  qr := case when d ? 'quote_ref' then left(nullif(btrim(d->>'quote_ref'), ''), 80) else l.quote_ref end;
  own := case when d ? 'owner_user' and nullif(d->>'owner_user', '') is not null then (d->>'owner_user')::uuid else coalesce(l.owner_user, auth.uid()) end;
  if own is distinct from coalesce(l.owner_user, auth.uid()) or (is_new and own <> auth.uid()) then
    if not public._crmg_lead_mgr(loc) then raise exception 'not allowed: only a manager can give an enquiry to someone else'; end if;
    if not public._crmg_user_at(own, loc) then raise exception 'assignee_not_at_outlet: this person does not work at this outlet'; end if;
  end if;

  if is_new then
    insert into public.crm_leads (client_id, location_id, customer_id, contact_name, contact_phone, source, inbound_message_id, occasion, event_date, guests, est_value, owner_user,
        next_follow_up, quote_ref, note, created_by)
      values (p_client, loc, cust, btrim(nm), ph, src, msg, occ, ev, gs, est, own, nfu, qr, nt, auth.uid()) returning * into l;
    perform public._crmg_ev(l.id, 'created', null, 'enquiry', nt, jsonb_build_object('lead_no', l.lead_no, 'source', src, 'occasion', occ, 'owner_user', own));
    if msg is not null then
      insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) select msg, status, status, 'tracked as enquiry ' || l.lead_no, auth.uid() from public.inbound_messages where id = msg;
    end if;
  else
    if nm is distinct from l.contact_name then changed := changed || 'contact_name'::text; end if;
    if ph is distinct from l.contact_phone then changed := changed || 'contact_phone'::text; end if;
    if cust is distinct from l.customer_id then changed := changed || 'customer_id'::text; end if;
    if src is distinct from l.source then changed := changed || 'source'::text; end if;
    if occ is distinct from l.occasion then changed := changed || 'occasion'::text; end if;
    if ev is distinct from l.event_date then changed := changed || 'event_date'::text; end if;
    if gs is distinct from l.guests then changed := changed || 'guests'::text; end if;
    if est is distinct from l.est_value then changed := changed || 'est_value'::text; end if;
    if nfu is distinct from l.next_follow_up then changed := changed || 'next_follow_up'::text; end if;
    if own is distinct from l.owner_user then changed := changed || 'owner_user'::text; end if;
    if msg is distinct from l.inbound_message_id then changed := changed || 'inbound_message_id'::text; end if;
    update public.crm_leads set contact_name = btrim(nm), contact_phone = ph, customer_id = cust, source = src, occasion = occ, event_date = ev, guests = gs, est_value = est,
        owner_user = own, next_follow_up = nfu, quote_ref = qr, note = nt, inbound_message_id = msg where id = l.id returning * into l;
    if cardinality(changed) > 0 then
      perform public._crmg_ev(l.id, case when 'owner_user' = any (changed) then 'assign' else 'edited' end, l.stage, l.stage, null, jsonb_build_object('changed', changed));
    end if;
  end if;

  if coalesce((d->>'make_task')::boolean, false) and l.next_follow_up is not null and (is_new or 'next_follow_up' = any (changed)) then
    perform public._crmg_lead_task_sync(l.id, l.next_follow_up);
  end if;
  select coalesce(jsonb_agg(x.id), '[]'::jsonb) into dups from public.crm_leads x
    where x.id <> l.id and x.location_id = l.location_id and x.stage not in ('won', 'lost') and l.contact_phone is not null and x.contact_phone = l.contact_phone;
  return jsonb_build_object('id', l.id, 'lead_no', l.lead_no, 'stage', l.stage, 'customer_id', l.customer_id, 'same_phone_open_leads', dups);
end $$;

-- ============================================================================
-- 3. NOTES (call, visit, message, note) and ASSIGN
-- ============================================================================
create or replace function public._crmg_lead_note(p_lead uuid, p_kind text, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; k text := coalesce(nullif(btrim(p_kind), ''), 'note'); b text := btrim(coalesce(p_body, ''));
begin
  l := public._crmg_lead_load(p_lead, true);
  if not public._crmg_can_act(l.location_id, l.owner_user, l.created_by) then raise exception 'not allowed'; end if;
  if k not in ('call', 'visit', 'message', 'note') then raise exception 'bad_note_kind'; end if;
  if char_length(b) not between 1 and 1000 then raise exception 'note_required: write 1 to 1000 letters'; end if;
  perform public._crmg_ev(l.id, 'note', l.stage, l.stage, b, jsonb_build_object('activity', k));
  return jsonb_build_object('id', l.id, 'noted', true);
end $$;

create or replace function public._crmg_lead_assign(p_lead uuid, p_user uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; n int;
begin
  l := public._crmg_lead_load(p_lead, true);
  if not public._crmg_lead_mgr(l.location_id) then raise exception 'not allowed: only a manager can give an enquiry to someone else'; end if;
  if l.stage in ('won', 'lost') then raise exception 'lead_closed: a won or lost enquiry cannot be given to someone else'; end if;
  if p_user is null or not public._crmg_user_at(p_user, l.location_id) then raise exception 'assignee_not_at_outlet: this person does not work at this outlet'; end if;
  if p_user = l.owner_user then return jsonb_build_object('id', l.id, 'noop', true); end if;
  update public.crm_leads set owner_user = p_user where id = l.id;
  update public.crm_tasks set assigned_to = p_user where lead_id = l.id and source = 'lead' and status = 'open';
  get diagnostics n = row_count;
  perform public._crmg_ev(l.id, 'assign', l.stage, l.stage, p_reason, jsonb_build_object('from', l.owner_user, 'to', p_user, 'tasks_moved', n));
  return jsonb_build_object('id', l.id, 'owner_user', p_user, 'tasks_moved', n);
end $$;

-- ============================================================================
-- 4. STAGE MOVES
--    p_args: lost_reason (code from the list), follow_up (timestamp), make_task (boolean), reason (only to win without a quote, manager, an exception)
-- ============================================================================
create or replace function public._crmg_lead_stage(p_lead uuid, p_to text, p_note text default null, p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; a jsonb := coalesce(p_args, '{}'::jsonb); lr text; fu timestamptz; has_q boolean; why text; closed_tasks int := 0; old_stage text;
begin
  l := public._crmg_lead_load(p_lead, true);
  if not public._crmg_can_act(l.location_id, l.owner_user, l.created_by) then raise exception 'not allowed'; end if;
  if p_to not in ('enquiry', 'quoted', 'following_up', 'won', 'lost') then raise exception 'bad_stage'; end if;
  if l.stage = p_to then return jsonb_build_object('id', l.id, 'stage', l.stage, 'noop', true); end if;
  if l.stage = 'lost' then raise exception 'illegal_stage_move: a lost enquiry can only be reopened (with a reason)'; end if;
  if l.stage = 'won' then raise exception 'illegal_stage_move: a won enquiry is final'; end if;
  if not public._crmg_stage_ok(l.stage, p_to) then raise exception 'illegal_stage_move: % to % is not allowed', l.stage, p_to; end if;
  select exists (select 1 from public.crm_lead_quotes where lead_id = l.id and status in ('sent', 'accepted')) into has_q;
  begin fu := nullif(a->>'follow_up', '')::timestamptz; exception when others then raise exception 'bad_follow_up'; end;

  if p_to = 'quoted' and not has_q then raise exception 'quote_needed: send a quote first (the quote moves the enquiry to Quoted by itself)'; end if;
  if p_to = 'won' and not has_q and public.rule_on('crm_lead_win_needs_quote') then
    if not public._crmg_lead_mgr(l.location_id) then raise exception 'quote_needed_to_win: a sent quote is needed first'; end if;
    why := public._crmg_reason(a->>'reason');
    perform public._crmg_exc('crmg_win_without_quote', l.est_value, l.id::text, why);
  end if;
  if p_to = 'lost' then
    if public.rule_txt('crm_lead_lost_by') is distinct from 'assignee' and not public._crmg_lead_mgr(l.location_id) then raise exception 'not allowed: only a manager can close an enquiry as lost'; end if;
    lr := nullif(btrim(a->>'lost_reason'), '');
    if lr is null or not public._crmg_list_ok('lost_reason', lr) then raise exception 'lost_reason_required: choose a lost reason from the list'; end if;
    if lr = 'other' and char_length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'lost_note_required: write a few words when the reason is Other'; end if;
  end if;

  old_stage := l.stage;
  update public.crm_leads set stage = p_to,
      lost_reason = case when p_to = 'lost' then lr else null end,
      lost_note = case when p_to = 'lost' then left(nullif(btrim(p_note), ''), 300) else null end,
      next_follow_up = case when p_to in ('won', 'lost') then null when fu is not null then fu else next_follow_up end
    where id = l.id returning * into l;
  perform public._crmg_ev(l.id, 'stage', old_stage, p_to, p_note, jsonb_strip_nulls(jsonb_build_object('lost_reason', lr, 'follow_up', fu, 'exception_reason', why)));
  if p_to in ('won', 'lost') then
    closed_tasks := public._crmg_lead_tasks_close(l.id, case when p_to = 'won' then 'the enquiry was won' else 'the enquiry was closed as lost' end);
    if p_to = 'won' then
      update public.crm_lead_quotes set status = 'accepted', responded_at = now() where id = (select id from public.crm_lead_quotes where lead_id = l.id and status = 'sent' order by version desc limit 1);
    else
      update public.crm_lead_quotes set status = 'declined', responded_at = now() where lead_id = l.id and status = 'sent';
    end if;
  elsif fu is not null and coalesce((a->>'make_task')::boolean, false) then
    perform public._crmg_lead_task_sync(l.id, fu);
  end if;
  return jsonb_build_object('id', l.id, 'stage', l.stage, 'tasks_closed', closed_tasks);
end $$;

-- reopen a lost enquiry. An exception: needs a written reason, goes to the Exceptions list, setting crm_lead_reopen_mode decides who may (reason / owner / off)
create or replace function public._crmg_lead_reopen(p_lead uuid, p_reason text, p_to text default 'enquiry') returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; mode text := coalesce(public.rule_txt('crm_lead_reopen_mode'), 'reason'); why text; old_reason text;
begin
  l := public._crmg_lead_load(p_lead, true);
  if mode = 'off' then raise exception 'reopen_off: reopening is switched off - start a new enquiry'; end if;
  if mode = 'owner' then if not public.is_owner() then raise exception 'not allowed: only the owner can reopen a lost enquiry'; end if;
  elsif not public._crmg_lead_mgr(l.location_id) then raise exception 'not allowed: only a manager can reopen a lost enquiry'; end if;
  if l.stage <> 'lost' then raise exception 'not_lost: only a lost enquiry can be reopened'; end if;
  if p_to not in ('enquiry', 'following_up') then raise exception 'bad_stage'; end if;
  why := public._crmg_reason(p_reason);
  old_reason := l.lost_reason;
  perform set_config('crmg.reopen', '1', true);
  update public.crm_leads set stage = p_to, lost_reason = null, lost_note = null, reopened_count = reopened_count + 1 where id = l.id returning * into l;
  perform set_config('crmg.reopen', '', true);
  insert into public.crm_lead_events (lead_id, by_user, by_staff, kind, from_stage, to_stage, note, detail)
    values (l.id, auth.uid(), public._crmg_staff(), 'reopen', 'lost', p_to, why, jsonb_build_object('was_lost_because', old_reason));
  perform public._crmg_exc('crmg_lead_reopen', l.est_value, l.id::text, why);
  return jsonb_build_object('id', l.id, 'stage', l.stage, 'reopened', l.reopened_count);
end $$;

-- ============================================================================
-- 5. QUOTES (items, validity). A quote is a priced list; it is not an invoice and posts nothing.
--    p_data: quote_id (edit this draft), items [{item_id?, desc?, unit?, qty, price?}], discount, valid_until, note, late_reason, send (boolean)
-- ============================================================================
create or replace function public._crmg_quote_items(p_items jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e jsonb; it public.items; out jsonb := '[]'; q numeric; pr numeric; dsc text; sub numeric := 0; n int := 0; iid uuid;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'no_items: add at least one line'; end if;
  for e in select * from jsonb_array_elements(p_items) loop
    n := n + 1;
    iid := null; it := null;
    begin iid := nullif(e->>'item_id', '')::uuid; exception when others then raise exception 'item_not_found'; end;
    if iid is not null then
      select * into it from public.items where id = iid and is_active;
      if not found then raise exception 'item_not_found'; end if;
    end if;
    dsc := left(nullif(btrim(coalesce(e->>'desc', '')), ''), 160);
    if iid is null and dsc is null then raise exception 'line_needs_item_or_description'; end if;
    begin q := (e->>'qty')::numeric; exception when others then raise exception 'bad_qty'; end;
    if q is null or q = 'NaN'::numeric or q <= 0 or q > 1000000 then raise exception 'bad_qty'; end if;
    begin pr := nullif(e->>'price', '')::numeric; exception when others then raise exception 'bad_price'; end;
    if pr is null and iid is not null then pr := it.sell_price; end if;
    if pr is null then raise exception 'price_required: write the price of line %', n; end if;
    if pr = 'NaN'::numeric or pr < 0 or pr > 1000000000 then raise exception 'bad_price'; end if;
    out := out || jsonb_build_object('item_id', iid, 'code', it.code, 'desc', coalesce(dsc, coalesce(it.name_en, it.name_bn)), 'unit', left(nullif(btrim(coalesce(e->>'unit', it.unit, '')), ''), 20),
                                     'qty', q, 'price', round(pr, 2), 'amount', round(q * pr, 2));
    sub := sub + round(q * pr, 2);
  end loop;
  return jsonb_build_object('items', out, 'subtotal', sub);
end $$;

create or replace function public._crmg_quote_save(p_lead uuid, p_client uuid, p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'::jsonb); l public.crm_leads; qq public.crm_lead_quotes; norm jsonb; sub numeric; dsc numeric; vu date; send boolean := coalesce((d->>'send')::boolean, false);
        ver int; late boolean := false; lr text; minlead numeric := public.rule_num('crm_quote_min_lead_days'); defdays numeric := public.rule_num('crm_lead_quote_valid_days'); qid uuid := nullif(d->>'quote_id', '')::uuid;
        new_stage text;
begin
  l := public._crmg_lead_load(p_lead, true);
  if not public._crmg_can_act(l.location_id, l.owner_user, l.created_by) then raise exception 'not allowed'; end if;
  if l.stage in ('won', 'lost') then raise exception 'lead_closed: a won or lost enquiry cannot get a new quote'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into qq from public.crm_lead_quotes where created_by = auth.uid() and client_id = p_client;
    if found then return jsonb_build_object('quote_id', qq.id, 'version', qq.version, 'status', qq.status, 'total', qq.total, 'dup', true); end if;
  end if;
  norm := public._crmg_quote_items(d->'items'); sub := (norm->>'subtotal')::numeric;
  begin dsc := coalesce(nullif(d->>'discount', '')::numeric, 0); exception when others then raise exception 'bad_amount'; end;
  if dsc = 'NaN'::numeric or dsc < 0 or dsc > sub then raise exception 'bad_discount: the discount cannot be more than the total of the lines'; end if;
  begin vu := nullif(d->>'valid_until', '')::date; exception when others then raise exception 'bad_date'; end;
  if vu is null and send and defdays is not null then vu := public._crmg_today() + defdays::int; end if;
  if send and vu is null then raise exception 'validity_required: write the date until which the quote is valid'; end if;
  lr := left(nullif(btrim(d->>'late_reason'), ''), 300);
  if send then
    late := (vu < public._crmg_today()) or (minlead is not null and l.event_date is not null and (l.event_date - public._crmg_today()) < minlead);
    if late then
      lr := public._crmg_reason(lr);
      perform public._crmg_exc('crmg_late_quote', sub - dsc, l.id::text, lr);
    end if;
  end if;
  if qid is not null then
    select * into qq from public.crm_lead_quotes where id = qid and lead_id = l.id for update;
    if not found then raise exception 'not_found'; end if;
    if qq.status <> 'draft' then raise exception 'quote_sent: a sent quote cannot be changed - make a new version'; end if;
    update public.crm_lead_quotes set items = norm->'items', subtotal = sub, discount = dsc, total = sub - dsc, valid_until = vu, note = left(nullif(btrim(d->>'note'), ''), 300),
        late_reason = case when late then lr else null end, client_id = coalesce(client_id, p_client) where id = qq.id returning * into qq;
  else
    select coalesce(max(version), 0) + 1 into ver from public.crm_lead_quotes where lead_id = l.id;
    insert into public.crm_lead_quotes (lead_id, version, client_id, items, subtotal, discount, total, valid_until, note, late_reason, created_by)
      values (l.id, ver, p_client, norm->'items', sub, dsc, sub - dsc, vu, left(nullif(btrim(d->>'note'), ''), 300), case when late then lr else null end, auth.uid()) returning * into qq;
  end if;
  if send then
    update public.crm_lead_quotes set status = 'superseded' where lead_id = l.id and id <> qq.id and status in ('draft', 'sent');
    update public.crm_lead_quotes set status = 'sent', sent_at = now() where id = qq.id returning * into qq;
    new_stage := case when l.stage in ('enquiry', 'following_up') then 'quoted' else l.stage end;
    update public.crm_leads set stage = new_stage, est_value = coalesce(est_value, qq.total) where id = l.id returning * into l;
    perform public._crmg_ev(l.id, 'quote', null, l.stage, d->>'note', jsonb_build_object('quote_id', qq.id, 'version', qq.version, 'total', qq.total, 'valid_until', qq.valid_until, 'late', late));
  else
    perform public._crmg_ev(l.id, 'quote', l.stage, l.stage, 'draft saved', jsonb_build_object('quote_id', qq.id, 'version', qq.version, 'total', qq.total, 'draft', true));
  end if;
  return jsonb_build_object('quote_id', qq.id, 'version', qq.version, 'status', qq.status, 'total', qq.total, 'valid_until', qq.valid_until, 'stage', l.stage);
end $$;

create or replace function public._crmg_quote_respond(p_quote uuid, p_result text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare qq public.crm_lead_quotes; l public.crm_leads;
begin
  select * into qq from public.crm_lead_quotes where id = p_quote for update;
  if not found then raise exception 'not_found'; end if;
  l := public._crmg_lead_load(qq.lead_id, true);
  if not public._crmg_can_act(l.location_id, l.owner_user, l.created_by) then raise exception 'not allowed'; end if;
  if p_result not in ('accepted', 'declined') then raise exception 'bad_result'; end if;
  if qq.status = p_result then return jsonb_build_object('quote_id', qq.id, 'status', qq.status, 'noop', true); end if;
  if qq.status <> 'sent' then raise exception 'quote_not_sent: only a sent quote can be answered'; end if;
  update public.crm_lead_quotes set status = p_result, responded_at = now(), response_note = left(nullif(btrim(p_note), ''), 300) where id = qq.id;
  perform public._crmg_ev(l.id, 'quote', l.stage, l.stage, p_note, jsonb_build_object('quote_id', qq.id, 'version', qq.version, 'answer', p_result));
  return jsonb_build_object('quote_id', qq.id, 'status', p_result);
end $$;

-- ============================================================================
-- 6. ONE LEAD WITH ITS QUOTES, TRAIL AND OPEN TASKS (the lead sheet)
-- ============================================================================
create or replace function public._crmg_lead_get(p_lead uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l public.crm_leads; sale_ok boolean; mgr boolean; act boolean; stale numeric := public.rule_num('crm_lead_stale_days'); cn text; ow text;
begin
  l := public._crmg_lead_load(p_lead, false);
  mgr := public._crmg_lead_mgr(l.location_id); act := public._crmg_can_act(l.location_id, l.owner_user, l.created_by);
  select name into cn from public.customers where id = l.customer_id;
  select staff_id into ow from public.profiles where id = l.owner_user;
  return jsonb_build_object(
    'lead', jsonb_build_object('id', l.id, 'lead_no', l.lead_no, 'location_id', l.location_id, 'customer_id', l.customer_id, 'customer_name', cn, 'contact_name', l.contact_name,
        'contact_phone', public._crmg_phone(l.contact_phone, l.owner_user), 'source', l.source, 'occasion', l.occasion, 'event_date', l.event_date, 'guests', l.guests, 'est_value', l.est_value,
        'stage', l.stage, 'lost_reason', l.lost_reason, 'lost_note', l.lost_note, 'owner_user', l.owner_user, 'owner_staff', ow, 'next_follow_up', l.next_follow_up, 'quote_ref', l.quote_ref,
        'online_order_id', l.online_order_id, 'entry_id', l.entry_id, 'converted_at', l.converted_at, 'reopened_count', l.reopened_count, 'note', l.note, 'stage_at', l.stage_at,
        'last_activity_at', l.last_activity_at, 'created_at', l.created_at, 'inbound_message_id', l.inbound_message_id,
        'overdue', l.stage not in ('won', 'lost') and l.next_follow_up is not null and l.next_follow_up < now(),
        'stale', l.stage not in ('won', 'lost') and stale is not null and l.last_activity_at < now() - (stale || ' days')::interval),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'version', q.version, 'status', q.status, 'expired', q.status = 'sent' and q.valid_until < public._crmg_today(), 'valid_until', q.valid_until,
        'items', q.items, 'subtotal', q.subtotal, 'discount', q.discount, 'total', q.total, 'note', q.note, 'late_reason', q.late_reason, 'sent_at', q.sent_at, 'responded_at', q.responded_at) order by q.version desc)
        from public.crm_lead_quotes q where q.lead_id = l.id), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'at', z.at, 'kind', z.kind, 'from', z.from_stage, 'to', z.to_stage, 'note', z.note, 'by', z.by_staff, 'detail', z.detail) order by z.id desc)
        from (select * from public.crm_lead_events e where e.lead_id = l.id order by e.id desc limit 200) z), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'kind', t.kind, 'due_at', t.due_at, 'snooze_until', t.snooze_until, 'assigned_to', t.assigned_to, 'status', t.status) order by t.due_at)
        from public.crm_tasks t where t.lead_id = l.id and t.status = 'open'), '[]'::jsonb),
    'can', jsonb_build_object('edit', act and l.stage not in ('won', 'lost'), 'note', act, 'quote', act and l.stage not in ('won', 'lost'), 'move', act and l.stage not in ('won', 'lost'),
        'assign', mgr and l.stage not in ('won', 'lost'), 'close_lost', l.stage not in ('won', 'lost') and (mgr or (act and public.rule_txt('crm_lead_lost_by') = 'assignee')),
        'reopen', l.stage = 'lost' and coalesce(public.rule_txt('crm_lead_reopen_mode'), 'reason') <> 'off' and case when coalesce(public.rule_txt('crm_lead_reopen_mode'), 'reason') = 'owner' then public.is_owner() else mgr end,
        'convert', mgr and l.converted_at is null and l.stage <> 'lost'));
end $$;

-- ============================================================================
-- 7. PRIVILEGES
-- ============================================================================
select public._crmg_lock(array['_crmg_norm_phone', '_crmg_can_act', '_crmg_lead_load', '_crmg_lead_task_sync', '_crmg_lead_tasks_close', '_crmg_lead_save', '_crmg_lead_note', '_crmg_lead_assign',
  '_crmg_lead_stage', '_crmg_lead_reopen', '_crmg_quote_items', '_crmg_quote_save', '_crmg_quote_respond', '_crmg_lead_get'],
  array['_crmg_lead_save', '_crmg_lead_note', '_crmg_lead_assign', '_crmg_lead_stage', '_crmg_lead_reopen', '_crmg_quote_save', '_crmg_quote_respond', '_crmg_lead_get']);
