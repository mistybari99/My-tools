-- Phase 131 (package R2-B) - TO-DO LIST: extra tasks and duties given by the owner (or a person he designates) to one person or to a role.
-- Paste after phase99 (needs phase7/8 rules + grants, phase11 no_hard_delete). Independent of phase130 and phase132. Paste-twice safe.
-- No earlier phase file is edited and NO shared function is patched or re-created (nothing to hook): with todo_on OFF (the default) nothing reads or writes
-- these tables and every screen is as before.
--
-- WHAT THIS FILE ADDS (every new name starts r2_ / _r2_)
--   1. Settings  todo_on (OFF)           the whole to-do list: OFF = no card on Home, nothing can be assigned, the screen shows "off".
--                todo_repeat_on (OFF)    repeating duties (daily / weekly). OFF = a repeat other than "none" is refused (repeat_off).
--   2. Grant     todo_assign             who may give tasks. Nobody holds it by default except the owner; the owner gives it to a role or one person
--                                        on the existing Delegation board.
--   3. Table     r2_todos                one row per person per task. A task given to a ROLE becomes one row for each active person who holds that role
--                                        at the moment it is given (people who join the role later do not get it). Fields: title, detail, due date, priority
--                                        (low|normal|high|urgent), status open|done|cannot|cancelled, the note (done note, or the reason for cannot / cancel),
--                                        who and when for every move, repeat kind, the task a repeat came from. Row level security: the assignee reads his own,
--                                        the assigner reads what he gave, the owner reads all; no browser write; no delete.
--   4. API       r2_todo_state()         switch, repeat switch, may I assign, my open / overdue counts and the next three (for the Home card)
--                r2_todo_assign(...)     give a task (person or role); a client id makes a retry harmless
--                r2_todo_mine(all)       MY list: open first (overdue marked), done / cannot of the last 30 days when asked
--                r2_todo_given(status)   what I gave (owner: everything), with the assignee and status
--                r2_todo_set(id, status, note)   the ASSIGNEE moves his own task: open -> done (note optional) or cannot (reason required)
--                r2_todo_manage(id, action, note)  the ASSIGNER (or owner): cancel (reason required) or reopen
--   5. Repeat    when a repeating task is marked done or cannot and todo_repeat_on is ON, the next one is created at once for the same person:
--                due = the later of (its due date, today) + 1 day (daily) or + 7 days (weekly); one open child at a time.

do $g$ begin
  if to_regprocedure('public.has_grant(text,integer)') is null or to_regprocedure('public.rule_on(text)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null
     or to_regprocedure('public._client_lock(uuid)') is null then
    raise exception 'phase131 needs the rules and grants engine (phase 7, 8, 10, 11) first';
  end if;
end $g$;

create or replace function public._r2b_present() returns boolean language sql stable as $$ select true $$;

-- ============================================================================
-- 1. SETTINGS and GRANT (safe defaults: OFF, nobody)
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('todo_on', 'people', 'switch', 'false'::jsonb, null, null, null, null,
  'করণীয় তালিকা (অতিরিক্ত কাজ দেওয়া) চালু', 'করণীয় / To-do list চালু', 'To-do list is on (extra tasks given to people)',
  'বন্ধ থাকলে হোমে কোনো কার্ড নেই এবং কাজ দেওয়া যায় না; অ্যাপ আগের মতোই চলে। চালু করলে যাকে কাজ দেওয়া হয়েছে সে শুধু নিজের তালিকা দেখে।',
  'বন্ধ থাকলে Home-এ card নেই, কাজ দেওয়া যায় না; app আগের মতোই। চালু করলে যাকে কাজ দেওয়া হয়েছে সে শুধু নিজের list দেখে।',
  'OFF = no card on Home and nothing can be assigned; the app is as before. ON = a person sees only his own tasks; whoever gave a task sees what he gave. Who may give tasks is the grant todo_assign.', 1310),
 ('todo_repeat_on', 'people', 'switch', 'false'::jsonb, null, null, null, null,
  'করণীয়: প্রতিদিন / প্রতি সপ্তাহের পুনরাবৃত্ত কাজ চালু', 'করণীয়: daily / weekly repeat চালু', 'To-do: repeating duties (daily / weekly) are allowed',
  'বন্ধ থাকলে "পুনরাবৃত্তি" বাছাই করা যায় না। চালু থাকলে পুনরাবৃত্ত কাজ শেষ হলে (বা করা গেল না লিখলে) পরেরটি নিজে তৈরি হয়।',
  'বন্ধ থাকলে repeat বাছা যায় না। চালু থাকলে repeat কাজ done / cannot হলে পরেরটি নিজে তৈরি হয়।',
  'OFF = a repeat cannot be chosen. ON = when a repeating task is marked done (or cannot), the next one is created for the same person. Needs todo_on.', 1311)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('todo_assign', 'people', 77, 'অতিরিক্ত কাজ / করণীয় দেওয়া (একজনকে বা ভূমিকাকে)', 'অতিরিক্ত কাজ / to-do দেওয়া (একজন বা role)', 'Give extra tasks and duties (to a person or a role)', 'window', null)
on conflict (grant_code) do nothing;

-- ============================================================================
-- 2. TABLE
-- ============================================================================
create table if not exists public.r2_todos (
  id bigserial primary key,
  client_id uuid,
  batch_id uuid not null default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  detail text not null default '' check (char_length(detail) <= 2000),
  due_date date,
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  assignee_user uuid not null references public.profiles(id),
  assigned_via text not null default 'person' check (assigned_via in ('person', 'role')),
  assigned_role text references public.roles(code),
  assigned_by uuid not null references public.profiles(id),
  assigned_at timestamptz not null default now(),
  status text not null default 'open' check (status in ('open', 'done', 'cannot', 'cancelled')),
  status_note text check (status_note is null or char_length(status_note) <= 500),
  status_by uuid, status_at timestamptz,
  repeat_kind text not null default 'none' check (repeat_kind in ('none', 'daily', 'weekly')),
  repeat_parent bigint references public.r2_todos(id),
  check (status not in ('cannot', 'cancelled') or char_length(btrim(coalesce(status_note, ''))) > 0)
);
create unique index if not exists r2_todos_client_uq on public.r2_todos (client_id, assignee_user) where client_id is not null;
create unique index if not exists r2_todos_one_child on public.r2_todos (repeat_parent) where repeat_parent is not null and status = 'open';
create index if not exists r2_todos_assignee on public.r2_todos (assignee_user, status, due_date);
create index if not exists r2_todos_assigner on public.r2_todos (assigned_by, assigned_at desc);

drop trigger if exists r2_todos_no_delete on public.r2_todos;
create trigger r2_todos_no_delete before delete on public.r2_todos for each row execute function public.no_hard_delete();
drop trigger if exists audit_r2_todos on public.r2_todos;
create trigger audit_r2_todos after insert or update on public.r2_todos for each row execute function public.log_change('id');

alter table public.r2_todos enable row level security;
revoke all on public.r2_todos from public, anon, authenticated;
grant select on public.r2_todos to authenticated;
drop policy if exists r2_todos_read on public.r2_todos;
create policy r2_todos_read on public.r2_todos for select to authenticated using (
  public.is_active() and (public.is_owner() or assignee_user = auth.uid() or assigned_by = auth.uid()));

-- ============================================================================
-- 3. HELPERS
-- ============================================================================
create or replace function public._r2b_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;

-- one task as json (the assignee and assigner names are looked up; used by the list functions)
create or replace function public._r2b_json(t public.r2_todos) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', t.id, 'batch_id', t.batch_id, 'title', t.title, 'detail', t.detail, 'due_date', t.due_date, 'priority', t.priority,
    'status', t.status, 'status_note', t.status_note, 'status_at', t.status_at, 'assigned_at', t.assigned_at, 'assigned_via', t.assigned_via, 'assigned_role', t.assigned_role,
    'assignee_id', t.assignee_user, 'assignee', (select coalesce(nullif(p.full_name, ''), p.staff_id) from public.profiles p where p.id = t.assignee_user),
    'assigner_id', t.assigned_by, 'assigner', (select coalesce(nullif(p.full_name, ''), p.staff_id) from public.profiles p where p.id = t.assigned_by),
    'repeat_kind', t.repeat_kind, 'repeat_parent', t.repeat_parent,
    'overdue', (t.status = 'open' and t.due_date is not null and t.due_date < public._r2b_today()));
$$;

-- the next occurrence of a repeating task (called after done / cannot; a no-op unless todo_repeat_on is ON)
create or replace function public._r2b_repeat_next(t public.r2_todos) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_due date;
begin
  if t.repeat_kind = 'none' or not public.rule_on('todo_repeat_on') then return null; end if;
  if exists (select 1 from public.r2_todos c where c.repeat_parent = t.id and c.status = 'open') then return null; end if;
  v_due := greatest(coalesce(t.due_date, public._r2b_today()), public._r2b_today()) + case t.repeat_kind when 'weekly' then 7 else 1 end;
  insert into public.r2_todos (batch_id, title, detail, due_date, priority, assignee_user, assigned_via, assigned_role, assigned_by, repeat_kind, repeat_parent)
    values (t.batch_id, t.title, t.detail, v_due, t.priority, t.assignee_user, t.assigned_via, t.assigned_role, t.assigned_by, t.repeat_kind, t.id) returning id into v_id;
  return v_id;
end $$;

-- ============================================================================
-- 4. API
-- ============================================================================
create or replace function public.r2_todo_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_on boolean := public.rule_on('todo_on'); v_open int; v_over int; v_next jsonb;
begin
  if not public.is_active() then return jsonb_build_object('on', false, 'repeat_on', false, 'can_assign', false, 'open', 0, 'overdue', 0, 'next', '[]'::jsonb); end if;
  if not v_on then return jsonb_build_object('on', false, 'repeat_on', false, 'can_assign', false, 'open', 0, 'overdue', 0, 'next', '[]'::jsonb); end if;
  select count(*), count(*) filter (where due_date is not null and due_date < public._r2b_today()) into v_open, v_over
    from public.r2_todos where assignee_user = auth.uid() and status = 'open';
  select coalesce(jsonb_agg(public._r2b_json(t) order by (t.due_date is not null and t.due_date < public._r2b_today()) desc,
                            case t.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, t.due_date nulls last, t.id), '[]'::jsonb) into v_next
    from (select * from public.r2_todos where assignee_user = auth.uid() and status = 'open'
           order by (due_date is not null and due_date < public._r2b_today()) desc, case priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, due_date nulls last, id limit 3) t;
  return jsonb_build_object('on', true, 'repeat_on', public.rule_on('todo_repeat_on'), 'can_assign', (public.is_owner() or public.has_grant('todo_assign')),
                            'open', v_open, 'overdue', v_over, 'next', v_next);
end $$;

create or replace function public.r2_todo_assign(p_title text, p_detail text, p_due date, p_priority text, p_kind text, p_target text,
                                                 p_repeat text default 'none', p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_role text; v_user uuid; v_batch uuid := gen_random_uuid(); v_title text := btrim(coalesce(p_title, '')); v_detail text := btrim(coalesce(p_detail, ''));
        v_pri text := coalesce(nullif(btrim(p_priority), ''), 'normal'); v_rep text := coalesce(nullif(btrim(p_repeat), ''), 'none'); ids bigint[] := '{}'; v_id bigint; r record;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('todo_on') then raise exception 'todo_off'; end if;
  if not (public.is_owner() or public.has_grant('todo_assign')) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('person', 'role') then raise exception 'bad_target'; end if;
  begin
    if p_kind = 'role' then v_role := nullif(btrim(coalesce(p_target, '')), ''); else v_user := p_target::uuid; end if;
  exception when others then raise exception 'bad_target'; end;
  perform public._client_lock(p_client);
  if p_client is not null then
    select array_agg(id order by id) into ids from public.r2_todos where client_id = p_client and assigned_by = auth.uid();
    if ids is not null then return jsonb_build_object('count', cardinality(ids), 'ids', to_jsonb(ids), 'repeat', true); end if;
  end if;
  if char_length(v_title) < 1 or char_length(v_title) > 120 then raise exception 'title_required'; end if;
  if char_length(v_detail) > 2000 then raise exception 'text_too_long'; end if;
  if v_pri not in ('low', 'normal', 'high', 'urgent') then raise exception 'bad_priority'; end if;
  if v_rep not in ('none', 'daily', 'weekly') then raise exception 'bad_repeat'; end if;
  if v_rep <> 'none' and not public.rule_on('todo_repeat_on') then raise exception 'repeat_off'; end if;
  if p_due is not null and (p_due < public._r2b_today() or p_due > public._r2b_today() + 730) then raise exception 'bad_date'; end if;
  if p_kind = 'person' then
    if not exists (select 1 from public.profiles where id = v_user and status = 'active') then raise exception 'bad_target'; end if;
    insert into public.r2_todos (client_id, batch_id, title, detail, due_date, priority, assignee_user, assigned_via, assigned_by, repeat_kind)
      values (p_client, v_batch, v_title, v_detail, p_due, v_pri, v_user, 'person', auth.uid(), v_rep) returning id into v_id;
    ids := array[v_id];
  else
    if not exists (select 1 from public.roles where code = v_role and active) then raise exception 'bad_target'; end if;
    for r in select distinct p.id from public.profiles p join public.user_roles ur on ur.user_id = p.id and ur.role_code = v_role where p.status = 'active' order by p.id loop
      insert into public.r2_todos (client_id, batch_id, title, detail, due_date, priority, assignee_user, assigned_via, assigned_role, assigned_by, repeat_kind)
        values (p_client, v_batch, v_title, v_detail, p_due, v_pri, r.id, 'role', v_role, auth.uid(), v_rep) returning id into v_id;
      ids := ids || v_id;
    end loop;
    if cardinality(ids) = 0 then raise exception 'no_recipients'; end if;
  end if;
  return jsonb_build_object('count', cardinality(ids), 'ids', to_jsonb(ids), 'batch_id', v_batch);
end $$;

-- MY list. p_all = also the done / cannot ones of the last 30 days. Cancelled tasks are not shown to the assignee.
create or replace function public.r2_todo_mine(p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.rule_on('todo_on') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(public._r2b_json(t) order by (t.status = 'open') desc, (t.status = 'open' and t.due_date is not null and t.due_date < public._r2b_today()) desc,
                                    case t.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, t.due_date nulls last, t.id)
     from public.r2_todos t
    where t.assignee_user = auth.uid() and (t.status = 'open' or (coalesce(p_all, false) and t.status in ('done', 'cannot') and t.status_at > now() - interval '30 days'))), '[]'::jsonb);
end $$;

-- what I gave (the owner sees everything). p_status null = all, or open|done|cannot|cancelled
create or replace function public.r2_todo_given(p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('todo_on') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(public._r2b_json(t) order by (t.status = 'open') desc, (t.status = 'open' and t.due_date is not null and t.due_date < public._r2b_today()) desc,
                                    t.due_date nulls last, t.id desc)
     from (select * from public.r2_todos x where (public.is_owner() or x.assigned_by = auth.uid()) and (p_status is null or x.status = p_status)
            order by x.assigned_at desc, x.id desc limit 300) t), '[]'::jsonb);
end $$;

-- the ASSIGNEE moves his own task
create or replace function public.r2_todo_set(p_id bigint, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.r2_todos; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_next bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('todo_on') then raise exception 'todo_off'; end if;
  select * into t from public.r2_todos where id = p_id for update;
  if not found or t.assignee_user <> auth.uid() then raise exception 'not allowed'; end if;
  if p_status is null or p_status not in ('done', 'cannot') then raise exception 'bad_status'; end if;
  if v_note is not null and char_length(v_note) > 500 then raise exception 'text_too_long'; end if;
  if p_status = 'cannot' and v_note is null then raise exception 'reason_required'; end if;
  if t.status = p_status then return jsonb_build_object('id', p_id, 'status', t.status, 'repeat', true); end if;
  if t.status <> 'open' then raise exception 'not_open'; end if;
  update public.r2_todos set status = p_status, status_note = v_note, status_by = auth.uid(), status_at = now() where id = p_id returning * into t;
  v_next := public._r2b_repeat_next(t);
  return jsonb_build_object('id', p_id, 'status', p_status, 'next_id', v_next);
end $$;

-- the ASSIGNER (or the owner): cancel with a reason, or reopen
create or replace function public.r2_todo_manage(p_id bigint, p_action text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.r2_todos; v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('todo_on') then raise exception 'todo_off'; end if;
  select * into t from public.r2_todos where id = p_id for update;
  if not found or not (public.is_owner() or t.assigned_by = auth.uid()) then raise exception 'not allowed'; end if;
  if p_action is null or p_action not in ('cancel', 'reopen') then raise exception 'bad_status'; end if;
  if v_note is not null and char_length(v_note) > 500 then raise exception 'text_too_long'; end if;
  if p_action = 'cancel' then
    if v_note is null then raise exception 'reason_required'; end if;
    if t.status = 'cancelled' then return jsonb_build_object('id', p_id, 'status', 'cancelled', 'repeat', true); end if;
    if t.status <> 'open' then raise exception 'not_open'; end if;
    update public.r2_todos set status = 'cancelled', status_note = v_note, status_by = auth.uid(), status_at = now() where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'cancelled');
  end if;
  if t.status = 'open' then return jsonb_build_object('id', p_id, 'status', 'open', 'repeat', true); end if;
  update public.r2_todos set status = 'open', status_note = case when v_note is null then null else 'reopened: ' || v_note end, status_by = auth.uid(), status_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'open');
end $$;

-- ============================================================================
-- 5. WHO MAY CALL WHAT
-- ============================================================================
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('r2_todo_state', 'r2_todo_assign', 'r2_todo_mine', 'r2_todo_given', 'r2_todo_set', 'r2_todo_manage',
                                                            '_r2b_today', '_r2b_json', '_r2b_repeat_next', '_r2b_present') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('r2_todo_state', 'r2_todo_assign', 'r2_todo_mine', 'r2_todo_given', 'r2_todo_set', 'r2_todo_manage') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
