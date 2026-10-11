-- ============================================================
-- BOS tool · Phase 2 schema: form entries, serials, exceptions,
-- red-control release requests, location settings.
-- Run AFTER schema.sql (SQL Editor -> paste -> Run). Run once.
-- ============================================================

create table public.location_settings (
  location_id int not null references public.locations(id),
  key text not null,
  value jsonb,                    -- null = "data needed"
  updated_at timestamptz not null default now(),
  updated_by uuid,
  primary key (location_id, key)
);

create table public.serials (
  form_code text not null, location_id int not null, last int not null default 0,
  primary key (form_code, location_id)
);

create table public.entries (
  id uuid primary key default gen_random_uuid(),
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  serial int not null,
  entry_date date not null,
  status text not null default 'draft' check (status in ('draft','submitted','approved','rejected')),
  data jsonb not null default '{}',
  flags jsonb not null default '[]',               -- [{code, level:'red'|'yellow', amount, text:{bn,en}}]
  check_data jsonb not null default '{}',          -- the checker/receiver's part of the form
  created_by uuid not null, created_staff text, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  checked_by uuid, checked_staff text, checked_at timestamptz, check_note text,
  unique (form_code, location_id, serial)
);
create index entries_lookup on public.entries (form_code, location_id, entry_date desc);

create table public.exceptions (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  form_code text not null, location_id int not null, entry_date date not null,
  flag_code text not null, level text not null check (level in ('red','yellow')),
  amount numeric, text jsonb,
  status text not null default 'open' check (status in ('open','resolved')),
  created_at timestamptz not null default now(),
  resolved_by uuid, resolved_staff text, resolved_at timestamptz, resolved_note text
);
create index exceptions_open on public.exceptions (status, created_at desc);

create table public.release_requests (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  flag_code text not null,
  flag_amount numeric,                 -- a release only covers the amount that was asked about
  reason text not null check (length(btrim(reason)) > 0),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_by uuid not null, requested_staff text, requested_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text
);
create unique index release_one_pending on public.release_requests (entry_id, flag_code) where status = 'pending';

-- ---------- helpers ----------
create or replace function public.can_loc(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (
    public.is_owner()
    or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management')
    or exists (select 1 from public.user_locations where user_id = auth.uid() and location_id = p_loc));
$$;

-- true when an existing non-empty value in "o" is changed or removed in "n" (filling blanks is free)
create or replace function public.jsonb_overwrites(o jsonb, n jsonb) returns boolean
language plpgsql immutable as $$
declare k text; i int;
begin
  if o is null or o = 'null'::jsonb or o = '""'::jsonb or o = '[]'::jsonb or o = '{}'::jsonb or o = 'false'::jsonb then return false; end if;
  if n is null then return true; end if;
  if jsonb_typeof(o) = 'object' then
    if jsonb_typeof(n) <> 'object' then return true; end if;
    for k in select jsonb_object_keys(o) loop
      if public.jsonb_overwrites(o->k, n->k) then return true; end if;
    end loop;
    return false;
  elsif jsonb_typeof(o) = 'array' then
    if jsonb_typeof(n) <> 'array' then return true; end if;
    for i in 0 .. jsonb_array_length(o) - 1 loop
      if public.jsonb_overwrites(o->i, n->i) then return true; end if;
    end loop;
    return false;
  else
    return o is distinct from n;
  end if;
end $$;

create or replace function public.staff_directory() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_active()
    then coalesce((select jsonb_agg(jsonb_build_object('id', id, 'staff_id', staff_id, 'full_name', full_name) order by full_name)
                   from public.profiles where status = 'active'), '[]'::jsonb)
    else '[]'::jsonb end;
$$;

-- ---------- entry workflow (all writes go through these) ----------
create or replace function public.save_entry(p_id uuid, p_form text, p_loc int, p_date date, p_data jsonb, p_flags jsonb, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; n int; ow boolean;
begin
  if not public.can_do(p_form, 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if not exists (select 1 from public.forms where code = p_form and enabled) then raise exception 'form is switched off'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_id is null then
    insert into public.serials (form_code, location_id, last) values (p_form, p_loc, 1)
      on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
    insert into public.entries (form_code, location_id, serial, entry_date, data, flags, created_by, created_staff)
      values (p_form, p_loc, n, p_date, coalesce(p_data, '{}'), coalesce(p_flags, '[]'), auth.uid(), sid) returning * into e;
    return jsonb_build_object('id', e.id, 'serial', e.serial);
  end if;
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status <> 'draft' then raise exception 'entry is locked'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can edit'; end if;
  ow := public.jsonb_overwrites(e.data, coalesce(p_data, '{}'));
  if ow and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  if ow then
    insert into public.corrections (user_id, staff_id, form_code, entry_id, note, before, after)
      values (auth.uid(), sid, e.form_code, e.id::text, btrim(p_note), e.data, p_data);
  end if;
  update public.entries set data = coalesce(p_data, '{}'), flags = coalesce(p_flags, '[]'), entry_date = p_date, updated_at = now() where id = p_id;
  return jsonb_build_object('id', e.id, 'serial', e.serial, 'overwrote', ow);
end $$;

create or replace function public.submit_entry(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; f public.forms; fl jsonb; blocked text[] := '{}'; auto boolean;
begin
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status <> 'draft' then raise exception 'entry is locked'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can submit'; end if;
  if not public.can_do(e.form_code, 'enter') or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  select * into f from public.forms where code = e.form_code;
  if f.red_block then
    for fl in select * from jsonb_array_elements(e.flags) loop
      if fl->>'level' = 'red' and not exists (select 1 from public.release_requests r
           where r.entry_id = e.id and r.flag_code = fl->>'code' and r.status = 'approved'
             and r.flag_amount is not distinct from nullif(fl->>'amount','')::numeric) then
        blocked := blocked || (fl->>'code');
      end if;
    end loop;
    if array_length(blocked, 1) > 0 then raise exception 'red_blocked:%', array_to_string(blocked, ','); end if;
  end if;
  update public.entries set status = 'submitted', submitted_at = now(), updated_at = now() where id = p_id;
  select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
  delete from public.exceptions where entry_id = e.id and status = 'open';
  if auto then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
      from jsonb_array_elements(e.flags) x;
  end if;
  return jsonb_build_object('status', 'submitted');
end $$;

create or replace function public.decide_entry(p_id uuid, p_approve boolean, p_note text default null, p_check jsonb default null, p_flags jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; self_ok boolean; auto boolean; newflags jsonb;
begin
  select * into e from public.entries where id = p_id for update;
  if not found or e.status <> 'submitted' then raise exception 'entry is not waiting for a decision'; end if;
  if not (public.can_do(e.form_code, 'approve') and public.can_loc(e.location_id)) then raise exception 'not allowed'; end if;
  self_ok := public.is_owner() or exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code
              where ur.user_id = auth.uid() and r.allow_self_approve);
  if e.created_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own entry'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  -- flags found while checking (receiver's count, etc.) are added to the maker's flags
  newflags := coalesce(p_flags, '[]'::jsonb);
  update public.entries set status = case when p_approve then 'approved' else 'rejected' end,
    check_data = coalesce(p_check, check_data),
    flags = (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(e.flags) x where coalesce(x->>'src','') <> 'check') || newflags,
    checked_by = auth.uid(), checked_staff = sid, checked_at = now(), check_note = p_note, updated_at = now() where id = p_id;
  select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
  if auto and jsonb_array_length(newflags) > 0 then
    delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code in (select x->>'code' from jsonb_array_elements(newflags) x);
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
      from jsonb_array_elements(newflags) x;
  end if;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;

-- send a submitted/rejected entry back to draft (note is mandatory, before/after kept in corrections)
create or replace function public.reopen_entry(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status = 'draft' then return jsonb_build_object('status', 'draft'); end if;
  if e.status = 'approved' and not public.is_owner() then raise exception 'only the owner can reopen an approved entry'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can reopen'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.corrections (user_id, staff_id, form_code, entry_id, note, before, after)
    values (auth.uid(), sid, e.form_code, e.id::text, btrim(p_note), jsonb_build_object('status', e.status, 'data', e.data), null);
  update public.entries set status = 'draft', submitted_at = null, checked_by = null, checked_staff = null, checked_at = null, check_note = null, check_data = '{}', updated_at = now() where id = p_id;
  return jsonb_build_object('status', 'draft');
end $$;

create or replace function public.request_release(p_entry uuid, p_flag text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; rid bigint;
begin
  if p_reason is null or length(btrim(p_reason)) = 0 then raise exception 'note_required'; end if;
  select * into e from public.entries where id = p_entry;
  if not found or e.status <> 'draft' then raise exception 'entry must be a draft'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can ask'; end if;
  if not exists (select 1 from jsonb_array_elements(e.flags) x where x->>'code' = p_flag and x->>'level' = 'red') then raise exception 'no such red control'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.release_requests (entry_id, flag_code, flag_amount, reason, requested_by, requested_staff)
    values (p_entry, p_flag, (select nullif(x->>'amount','')::numeric from jsonb_array_elements(e.flags) x where x->>'code' = p_flag limit 1),
            btrim(p_reason), auth.uid(), sid) returning id into rid;
  return jsonb_build_object('id', rid);
end $$;

create or replace function public.decide_release(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; r public.release_requests;
begin
  if not public.is_owner() then raise exception 'owner only'; end if;
  select * into r from public.release_requests where id = p_id for update;
  if not found or r.status <> 'pending' then raise exception 'request is not pending'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.release_requests set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;

create or replace function public.resolve_exception(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare x public.exceptions; sid text;
begin
  select * into x from public.exceptions where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public.is_owner() or public.can_do(x.form_code, 'approve')) then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_staff = sid, resolved_at = now(), resolved_note = btrim(p_note) where id = p_id;
end $$;

-- audit: status changes of entries, and the new decision tables
create or replace function public.log_entry_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare sid text;
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    select staff_id into sid from public.profiles where id = auth.uid();
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'status', 'entries', new.id::text,
              jsonb_build_object('form', new.form_code, 'serial', new.serial, 'from', case when tg_op = 'INSERT' then null else old.status end, 'to', new.status));
  end if;
  return new;
end $$;
create trigger entries_status_log after insert or update on public.entries for each row execute function public.log_entry_status();
create trigger audit_release after insert or update on public.release_requests for each row execute function public.log_change('id');
create trigger audit_exceptions after update on public.exceptions for each row execute function public.log_change('id');
create trigger audit_loc_settings after insert or update on public.location_settings for each row execute function public.log_change('location_id,key');

-- ---------- privileges and row level security ----------
grant select on public.location_settings, public.entries, public.exceptions, public.release_requests to authenticated;
grant insert, update on public.location_settings to authenticated;
grant execute on function public.can_loc(int), public.staff_directory(),
  public.save_entry(uuid, text, int, date, jsonb, jsonb, text), public.submit_entry(uuid),
  public.decide_entry(uuid, boolean, text, jsonb, jsonb), public.reopen_entry(uuid, text),
  public.request_release(uuid, text, text), public.decide_release(bigint, boolean, text),
  public.resolve_exception(bigint, text) to authenticated;
alter table public.location_settings enable row level security;
alter table public.serials enable row level security;
alter table public.entries enable row level security;
alter table public.exceptions enable row level security;
alter table public.release_requests enable row level security;

create policy locset_read on public.location_settings for select to authenticated using (public.is_active());
create policy locset_owner_write on public.location_settings for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy entries_read on public.entries for select to authenticated using (public.can_do(form_code, 'view') and public.can_loc(location_id));
create policy exceptions_read on public.exceptions for select to authenticated using (public.is_owner() or public.can_do(form_code, 'approve'));
create policy release_read on public.release_requests for select to authenticated using (requested_by = auth.uid() or public.is_owner());

insert into public.settings (key, value, label_bn, label_mix, label_en) values
  ('auto_exceptions', 'true', 'গরমিল নিজে নিজে কাজের তালিকায় উঠবে', 'গরমিল নিজে নিজে Exception List-এ উঠবে', 'Variances go to the exceptions list automatically');
