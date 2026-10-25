-- Phase 326 (bos326, package CRM-G label 126, part 4 of 5) - TASKS: ADD, DONE, SNOOZE, SKIP, REASSIGN, MY TASKS (overdue first), COUNTS FOR THE HOME STRIP, OPTIONAL IN-APP REMINDERS.
-- Paste AFTER phase325. Paste-twice safe. Nothing here posts to the books and nothing here messages a customer.
-- Every function answers module_off while the switch crm_task_on is OFF (default). The reminder scan does nothing while crm_task_reminder_on is OFF (default).
-- A task is seen by: the person it is assigned to, the person who made it, the owner, holders of crm_task_all, and a holder of crm_lead_manage inside the outlet of the task.
-- Giving a task to another person needs the owner or the right crm_task_assign.

do $g$ begin
  if to_regprocedure('public._crmg_lead_convert(uuid,uuid,text,jsonb)') is null then raise exception 'phase326 needs phase325 first'; end if;
end $g$;

-- ============================================================================
-- 1. HELPERS
-- ============================================================================
create or replace function public._crmg_task_vis(p_loc int, p_assigned uuid, p_created uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_task_all') or p_assigned = auth.uid() or p_created = auth.uid()
    or (p_loc is not null and public.can_loc(p_loc) and public.has_grant('crm_lead_manage', p_loc))) $$;

create or replace function public._crmg_task_load(p_id uuid, p_lock boolean default true) returns public.crm_tasks
language plpgsql security definer set search_path = public as $$
declare t public.crm_tasks;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_task_on() then raise exception 'module_off: tasks are switched off'; end if;
  if p_lock then select * into t from public.crm_tasks where id = p_id for update; else select * into t from public.crm_tasks where id = p_id; end if;
  if not found or not public._crmg_task_vis(t.location_id, t.assigned_to, t.created_by) then raise exception 'not_found'; end if;
  return t;
end $$;

create or replace function public._crmg_task_ev(p_task uuid, p_kind text, p_note text, p_detail jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare lid uuid;
begin
  insert into public.crm_task_events (task_id, by_user, by_staff, kind, note, detail) values (p_task, auth.uid(), public._crmg_staff(), p_kind, left(nullif(btrim(p_note), ''), 300), p_detail);
  -- work on a task counts as activity on its enquiry (it keeps the stale clock honest)
  select lead_id into lid from public.crm_tasks where id = p_task;
  if lid is not null and p_kind in ('done', 'snoozed') then update public.crm_leads set last_activity_at = now() where id = lid and stage not in ('won', 'lost'); end if;
end $$;

-- may the caller close, snooze or edit this task: assignee, maker, owner, crm_task_all, manager of the outlet
create or replace function public._crmg_task_act(t public.crm_tasks) returns boolean language sql stable security definer set search_path = public as $$
  select public._crmg_task_vis(t.location_id, t.assigned_to, t.created_by) $$;

-- ============================================================================
-- 2. SAVE (create or edit an open task). p_data: kind, title, due_at, assigned_to, lead_id, customer_id, order_id, location_id.
-- ============================================================================
create or replace function public._crmg_task_save(p_id uuid, p_client uuid, p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'::jsonb); t public.crm_tasks; kd text; ttl text; due timestamptz; asg uuid; lid uuid; cid uuid; oid uuid; loc int; defh numeric := public.rule_num('crm_task_default_due_hours');
        l public.crm_leads; oo public.online_orders; src text := 'manual'; is_new boolean := p_id is null; changed text[] := '{}';
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_task_on() then raise exception 'module_off: tasks are switched off'; end if;
  if jsonb_typeof(d) <> 'object' then raise exception 'bad_data'; end if;
  if is_new then
    perform public._client_lock(p_client);
    if p_client is not null then
      select * into t from public.crm_tasks where created_by = auth.uid() and client_id = p_client;
      if found then return jsonb_build_object('id', t.id, 'status', t.status, 'due_at', t.due_at, 'dup', true); end if;
    end if;
  else
    t := public._crmg_task_load(p_id, true);
    if t.status <> 'open' then raise exception 'task_closed: a done or skipped task cannot be changed'; end if;
  end if;

  kd := coalesce(nullif(btrim(d->>'kind'), ''), case when is_new then 'other' else t.kind end);
  if kd not in ('call', 'message', 'visit', 'follow_up', 'other') then raise exception 'bad_kind'; end if;
  ttl := case when d ? 'title' then left(btrim(coalesce(d->>'title', '')), 120) else t.title end;
  if coalesce(ttl, '') = '' then raise exception 'title_required: write what has to be done'; end if;
  begin due := case when d ? 'due_at' then nullif(d->>'due_at', '')::timestamptz else t.due_at end; exception when others then raise exception 'bad_due'; end;
  if due is null then
    if defh is null then raise exception 'due_required: write the date and time the task is due'; end if;
    due := now() + (defh || ' hours')::interval;
  end if;
  if due > now() + interval '3 years' then raise exception 'bad_due'; end if;

  -- links: an enquiry (must be visible), a customer, an online order
  lid := case when d ? 'lead_id' then nullif(d->>'lead_id', '')::uuid else t.lead_id end;
  cid := case when d ? 'customer_id' then nullif(d->>'customer_id', '')::uuid else t.customer_id end;
  oid := case when d ? 'order_id' then nullif(d->>'order_id', '')::uuid else t.order_id end;
  loc := t.location_id;
  if lid is not null then
    select * into l from public.crm_leads where id = lid;
    if not found or not public._crmg_lead_vis(l.location_id, l.owner_user, l.created_by) then raise exception 'not_found'; end if;
    loc := l.location_id; cid := coalesce(cid, l.customer_id); src := 'lead';
  end if;
  if cid is not null and not exists (select 1 from public.customers where id = cid) then raise exception 'customer_not_found'; end if;
  if oid is not null then
    select * into oo from public.online_orders where id = oid;
    if not found or not public.can_loc(oo.location_id) then raise exception 'not_found'; end if;
    loc := coalesce(loc, oo.location_id); src := case when lid is null then 'order' else src end;
  end if;
  if loc is null and nullif(d->>'location_id', '') is not null then
    loc := (d->>'location_id')::int;
    if not exists (select 1 from public.locations where id = loc) or not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  end if;

  -- who does it
  asg := case when d ? 'assigned_to' and nullif(d->>'assigned_to', '') is not null then (d->>'assigned_to')::uuid else coalesce(t.assigned_to, auth.uid()) end;
  if asg <> auth.uid() and asg is distinct from t.assigned_to then
    if not (public.is_owner() or public.has_grant('crm_task_assign') or (loc is not null and public._crmg_lead_mgr(loc))) then raise exception 'not allowed: giving a task to someone else needs the right to assign tasks'; end if;
    if not exists (select 1 from public.profiles where id = asg and status = 'active') then raise exception 'assignee_not_active'; end if;
    if loc is not null and not public._crmg_user_at(asg, loc) then raise exception 'assignee_not_at_outlet: this person does not work at this outlet'; end if;
  end if;

  if is_new then
    insert into public.crm_tasks (client_id, location_id, customer_id, lead_id, order_id, kind, title, due_at, assigned_to, source, created_by)
      values (p_client, loc, cid, lid, oid, kd, ttl, due, asg, src, auth.uid()) returning * into t;
    perform public._crmg_task_ev(t.id, 'created', null, jsonb_build_object('assigned_to', asg, 'due_at', due));
    if lid is not null then perform public._crmg_ev(lid, 'task', null, null, 'task added: ' || ttl, jsonb_build_object('task_id', t.id, 'due_at', due)); end if;
  else
    if ttl is distinct from t.title then changed := changed || 'title'::text; end if;
    if due is distinct from t.due_at then changed := changed || 'due_at'::text; end if;
    if kd is distinct from t.kind then changed := changed || 'kind'::text; end if;
    if asg is distinct from t.assigned_to then changed := changed || 'assigned_to'::text; end if;
    update public.crm_tasks set kind = kd, title = ttl, due_at = due, assigned_to = asg, customer_id = cid, lead_id = lid, order_id = oid, location_id = loc,
        snooze_until = case when due is distinct from t.due_at then null else snooze_until end where id = t.id returning * into t;
    if cardinality(changed) > 0 then perform public._crmg_task_ev(t.id, case when 'assigned_to' = any (changed) then 'assigned' else 'edited' end, null, jsonb_build_object('changed', changed, 'assigned_to', asg)); end if;
  end if;
  return jsonb_build_object('id', t.id, 'status', t.status, 'due_at', t.due_at, 'assigned_to', t.assigned_to);
end $$;

-- ============================================================================
-- 3. DONE, SNOOZE, SKIP
-- ============================================================================
create or replace function public._crmg_task_done(p_id uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.crm_tasks;
begin
  t := public._crmg_task_load(p_id, true);
  if not public._crmg_task_act(t) then raise exception 'not allowed'; end if;
  if t.status = 'done' then return jsonb_build_object('id', t.id, 'status', 'done', 'noop', true); end if;
  if t.status <> 'open' then raise exception 'task_closed: a skipped task cannot be marked done'; end if;
  update public.crm_tasks set status = 'done', done_note = left(nullif(btrim(p_note), ''), 300), done_by = auth.uid(), done_at = now() where id = t.id;
  perform public._crmg_task_ev(t.id, 'done', p_note, null);
  return jsonb_build_object('id', t.id, 'status', 'done');
end $$;

-- put a task off until a later time. p_until, or p_hours from now. Not longer than crm_task_snooze_max_days when that is set.
create or replace function public._crmg_task_snooze(p_id uuid, p_until timestamptz default null, p_hours numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.crm_tasks; u timestamptz; mx numeric := public.rule_num('crm_task_snooze_max_days');
begin
  t := public._crmg_task_load(p_id, true);
  if not public._crmg_task_act(t) then raise exception 'not allowed'; end if;
  if t.status <> 'open' then raise exception 'task_closed: a done or skipped task cannot be snoozed'; end if;
  u := coalesce(p_until, case when p_hours is not null then now() + (p_hours || ' hours')::interval end);
  if u is null then raise exception 'snooze_until_required: say until when'; end if;
  if u <= now() then raise exception 'bad_snooze: the time must be in the future'; end if;
  if mx is not null and u > now() + (mx || ' days')::interval then raise exception 'snooze_too_long: the longest snooze is % days', mx::int; end if;
  update public.crm_tasks set snooze_until = u, snooze_count = snooze_count + 1 where id = t.id;
  perform public._crmg_task_ev(t.id, 'snoozed', p_note, jsonb_build_object('until', u));
  return jsonb_build_object('id', t.id, 'snooze_until', u, 'snooze_count', t.snooze_count + 1);
end $$;

-- skip a task: a written reason is needed (an exception that stays in the task trail and the audit log)
create or replace function public._crmg_task_skip(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.crm_tasks; why text;
begin
  t := public._crmg_task_load(p_id, true);
  if not public._crmg_task_act(t) then raise exception 'not allowed'; end if;
  if t.status = 'skipped' then return jsonb_build_object('id', t.id, 'status', 'skipped', 'noop', true); end if;
  if t.status <> 'open' then raise exception 'task_closed: a done task cannot be skipped'; end if;
  why := public._crmg_reason(p_reason);
  update public.crm_tasks set status = 'skipped', skip_reason = why where id = t.id;
  perform public._crmg_task_ev(t.id, 'skipped', why, null);
  perform public._crmg_audit('skip', 'crm_tasks', t.id::text, jsonb_build_object('reason', why));
  return jsonb_build_object('id', t.id, 'status', 'skipped');
end $$;

-- ============================================================================
-- 4. MY TASKS   p_scope: mine (default) | team (every task the caller may see) | user (p_user, if the caller may see them)
--    Buckets: overdue (the due time has passed and no snooze runs), today (due later today), upcoming, snoozed. Done and skipped are not listed (recent_done: last 7 days of the caller's own).
-- ============================================================================
create or replace function public._crmg_my_tasks(p_scope text default 'mine', p_user uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sc text := coalesce(p_scope, 'mine'); who uuid; today date := public._crmg_today(); res jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_task_on() then return jsonb_build_object('on', false); end if;
  if sc not in ('mine', 'team', 'user') then raise exception 'bad_scope'; end if;
  who := case when sc = 'mine' then auth.uid() when sc = 'user' then coalesce(p_user, auth.uid()) end;
  with t as (
    select t.*, (select pr.staff_id from public.profiles pr where pr.id = t.assigned_to) as staff, l.lead_no, l.contact_name as lead_name, l.stage as lead_stage, oo.order_no, oo.status as order_status,
           case when t.snooze_until is not null and t.snooze_until > now() then 'snoozed'
                when t.due_at < now() then 'overdue'
                when (t.due_at at time zone 'Asia/Dhaka')::date = today then 'today' else 'upcoming' end as bucket
      from public.crm_tasks t
      left join public.crm_leads l on l.id = t.lead_id
      left join public.online_orders oo on oo.id = t.order_id
     where t.status = 'open' and (who is null or t.assigned_to = who)
       and public._crmg_task_vis(t.location_id, t.assigned_to, t.created_by)
       and not (t.source = 'order' and oo.status in ('delivered', 'cancelled'))),
  j as (select bucket, jsonb_build_object('id', t.id, 'kind', t.kind, 'title', t.title, 'due_at', t.due_at, 'snooze_until', t.snooze_until, 'snooze_count', t.snooze_count, 'assigned_to', t.assigned_to,
        'assigned_staff', t.staff, 'lead_id', t.lead_id, 'lead_no', t.lead_no, 'lead_name', t.lead_name, 'customer_id', t.customer_id, 'order_id', t.order_id, 'order_no', t.order_no, 'source', t.source,
        'location_id', t.location_id, 'overdue_hours', case when t.bucket = 'overdue' then round(extract(epoch from now() - t.due_at) / 3600, 1) end) as r, t.due_at, t.snooze_until from t)
  select jsonb_build_object('on', true, 'now', now(), 'scope', sc,
    'counts', jsonb_build_object('overdue', (select count(*) from j where bucket = 'overdue'), 'today', (select count(*) from j where bucket = 'today'),
        'upcoming', (select count(*) from j where bucket = 'upcoming'), 'snoozed', (select count(*) from j where bucket = 'snoozed')),
    'overdue', coalesce((select jsonb_agg(r order by due_at) from (select * from j where bucket = 'overdue' order by due_at limit 200) z), '[]'::jsonb),
    'today', coalesce((select jsonb_agg(r order by due_at) from (select * from j where bucket = 'today' order by due_at limit 200) z), '[]'::jsonb),
    'upcoming', coalesce((select jsonb_agg(r order by due_at) from (select * from j where bucket = 'upcoming' order by due_at limit 100) z), '[]'::jsonb),
    'snoozed', coalesce((select jsonb_agg(r order by snooze_until) from (select * from j where bucket = 'snoozed' order by snooze_until limit 100) z), '[]'::jsonb),
    'recent_done', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title, 'done_at', d.done_at, 'done_note', d.done_note) order by d.done_at desc)
        from (select * from public.crm_tasks d where d.status = 'done' and d.done_by = auth.uid() and d.done_at > now() - interval '7 days' order by d.done_at desc limit 20) d), '[]'::jsonb))
  into res;
  return res;
end $$;

-- numbers for the Home strip: the caller's own open tasks and own open enquiries with a missed follow-up. Cheap; never raises for a person without tasks.
create or replace function public._crmg_task_counts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := public._crmg_today(); r jsonb;
begin
  if not public.is_active() then return jsonb_build_object('on', false); end if;
  r := jsonb_build_object('on', public._crmg_task_on(), 'lead_on', public._crmg_lead_on());
  if public._crmg_task_on() then
    r := r || (select jsonb_build_object(
      'open', count(*) filter (where not (t.snooze_until is not null and t.snooze_until > now())),
      'overdue', count(*) filter (where t.due_at < now() and not (t.snooze_until is not null and t.snooze_until > now())),
      'today', count(*) filter (where t.due_at >= now() and (t.due_at at time zone 'Asia/Dhaka')::date = today and not (t.snooze_until is not null and t.snooze_until > now())),
      'snoozed', count(*) filter (where t.snooze_until is not null and t.snooze_until > now()))
      from public.crm_tasks t left join public.online_orders oo on oo.id = t.order_id
     where t.status = 'open' and t.assigned_to = auth.uid() and not (t.source = 'order' and oo.status in ('delivered', 'cancelled')));
  end if;
  if public._crmg_lead_on() then
    r := r || jsonb_build_object('leads_overdue', (select count(*) from public.crm_leads l where l.owner_user = auth.uid() and l.stage not in ('won', 'lost') and l.next_follow_up is not null and l.next_follow_up < now()));
  end if;
  return r;
end $$;

-- ============================================================================
-- 5. SWEEP AND REMINDERS (both run only for the owner, the notify bot or the database scheduler; the reminder does nothing while crm_task_reminder_on is OFF)
-- ============================================================================
create or replace function public._crmg_sched_ok() returns text language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is not null then
    if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
    return case when public._is_ops('notify') then 'notify_bot' else 'manual' end;
  end if;
  if not (session_user in ('postgres', 'supabase_admin') and coalesce(nullif(current_setting('role', true), ''), 'none') = 'none') then raise exception 'not allowed'; end if;
  return 'database_scheduler';
end $$;

-- end the open tasks that follow a delivered or cancelled order (the My tasks list already hides them; this makes it stick)
create or replace function public._crmg_tasks_sweep(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare via text := public._crmg_sched_ok(); r record; n int := 0;
begin
  if not public._crmg_task_on() then return jsonb_build_object('ran', false, 'skipped', 'switch_off'); end if;
  for r in select t.id, oo.status from public.crm_tasks t join public.online_orders oo on oo.id = t.order_id where t.status = 'open' and t.source in ('order', 'lead') and oo.status in ('delivered', 'cancelled') and t.order_id is not null for update of t loop
    n := n + 1;
    if not p_dry then
      update public.crm_tasks set status = 'skipped', skip_reason = 'the order was ' || r.status where id = r.id;
      insert into public.crm_task_events (task_id, kind, note, detail) values (r.id, 'skipped', 'the order was ' || r.status, jsonb_build_object('via', via));
    end if;
  end loop;
  return jsonb_build_object('ran', not p_dry, 'closed', n, 'dry', p_dry, 'via', via);
end $$;

-- the in-app reminder: one line per person per day, counts only (no customer name or phone). The existing notify job calls this (hook in docs/integration/CRM-G.md).
create or replace function public._crmg_task_scan(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare via text := public._crmg_sched_ok(); r record; made int := 0; people int := 0; stale numeric := public.rule_num('crm_lead_stale_days'); sweep jsonb; n_over int; n_today int; n_stale int; body text;
begin
  if not public.rule_on('crm_task_reminder_on') then return jsonb_build_object('ran', false, 'skipped', 'switch_off'); end if;
  if not p_dry and public._crmg_task_on() then sweep := public._crmg_tasks_sweep(false); end if;
  for r in
    select p.id as uid, p.staff_id,
           (select count(*) from public.crm_tasks t left join public.online_orders oo on oo.id = t.order_id where public._crmg_task_on() and t.status = 'open' and t.assigned_to = p.id and t.due_at < now()
              and not (t.snooze_until is not null and t.snooze_until > now()) and not (t.source = 'order' and oo.status in ('delivered', 'cancelled'))) as over_n,
           (select count(*) from public.crm_tasks t left join public.online_orders oo on oo.id = t.order_id where public._crmg_task_on() and t.status = 'open' and t.assigned_to = p.id and t.due_at >= now()
              and (t.due_at at time zone 'Asia/Dhaka')::date = public._crmg_today() and not (t.snooze_until is not null and t.snooze_until > now()) and not (t.source = 'order' and oo.status in ('delivered', 'cancelled'))) as today_n,
           (select count(*) from public.crm_leads l where public._crmg_lead_on() and l.owner_user = p.id and l.stage not in ('won', 'lost')
              and ((l.next_follow_up is not null and l.next_follow_up < now()) or (stale is not null and l.last_activity_at < now() - (stale || ' days')::interval))) as lead_n
      from public.profiles p where p.status = 'active'
  loop
    if r.over_n + r.today_n + r.lead_n = 0 then continue; end if;
    people := people + 1;
    if p_dry then continue; end if;
    body := r.over_n || ' overdue, ' || r.today_n || ' due today' || case when r.lead_n > 0 then ', ' || r.lead_n || ' enquiries need a follow-up' else '' end;
    insert into public.notifications (user_id, audience, kind, level, title_bn, title_en, body_bn, body_en, route, key)
      values (r.uid, 'all', 'crm_task_due', case when r.over_n > 0 then 'warn' else 'info' end, 'You have tasks to do', 'You have tasks to do', body, body, 'crmtasks', r.uid::text)
      on conflict (kind, key, day) do nothing;
    if found then made := made + 1; end if;
  end loop;
  return jsonb_build_object('ran', not p_dry, 'people', people, 'created', made, 'dry', p_dry, 'via', via, 'swept', sweep);
end $$;

-- ============================================================================
-- 6. PRIVILEGES
-- ============================================================================
select public._crmg_lock(array['_crmg_task_vis', '_crmg_task_load', '_crmg_task_ev', '_crmg_task_act', '_crmg_task_save', '_crmg_task_done', '_crmg_task_snooze', '_crmg_task_skip', '_crmg_my_tasks',
  '_crmg_task_counts', '_crmg_sched_ok', '_crmg_tasks_sweep', '_crmg_task_scan'],
  array['_crmg_task_save', '_crmg_task_done', '_crmg_task_snooze', '_crmg_task_skip', '_crmg_my_tasks', '_crmg_task_counts', '_crmg_tasks_sweep', '_crmg_task_scan']);
