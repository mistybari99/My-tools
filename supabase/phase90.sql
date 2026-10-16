-- Phase 90 (bos90) - U-03 STAFF EXIT REVOKES ACCESS. Paste after phase87 (needs phase41 employees), paste-twice safe. Earlier phase files are not edited.
-- Package W1-C (Wave 1). New functions all carry the prefix _w1c_. No shared function is changed by this file: the one hook line that
-- employee_status_set needs is written in docs/integration/W1-C.md and proved on a scratch copy in phase90_test.sql.
--
-- WHAT THIS ADDS
--   * When a person's employee status becomes one of the chosen exit statuses, their login (profiles.status), their grants (user_grants.valid_until),
--     their list-manager rows and, only if the owner switches it on, the attendance device tokens THEY registered are ended. One audit_log line per exit.
--   * Settings (rules, owner editable at any time, every change is an audit_log line through the rules audit trigger):
--       exit_revoke_mode      off [default: today's behaviour, nothing is touched] | alert (only a red exception) | auto (login is disabled)
--       exit_revoke_statuses  which statuses revoke, default resigned,terminated,retired (on_leave is allowed in the list but not recommended)
--       exit_alert_hours      blank = off; a linked login still active that many hours after the exit raises the red exception exit_access_open
--       exit_deactivate_devices  off [default]; on = also switch off attendance device tokens that this person registered
--   * Exception path: the owner, or any person the owner gave the grant exit_keep_access, can keep one person's access with a required reason
--     (audit_log line + a yellow row in the Exceptions list). A non-owner without the grant is refused on the server.
--   * Re-hire (status back to a non-exit status) re-enables the login that THIS feature disabled. Grants and device tokens are NOT restored.
--   * A departing owner login or the caller's own login is never disabled by this feature: a red exception tells the owner instead.
--   * Wrapper _w1c_employee_status_set(...) gives the same result without any hook (it calls employee_status_set and then the exit step once).
-- NOTHING CHANGES until the owner sets exit_revoke_mode to alert or auto (default off) or fills exit_alert_hours.

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase90 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public.employee_status_set(uuid,text,date,text)') is null or to_regprocedure('public._stock_exc(integer,text,text,text,text,uuid,date,text,numeric)') is null
     or to_regclass('public.employee_status_log') is null or to_regclass('public.attendance_devices') is null then
    raise exception 'phase90 needs phase41 (employees) and the stock exception helper';
  end if;
end $g$;

create or replace function public._w1c_present90() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text, marker passed in (same idea as phase87 _m_patch, whose marker is fixed to bos87) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist exactly once, otherwise nothing is changed. Marker already present = no-op.
create or replace function public._w1c_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos[0-9]{2,3}$' then raise exception 'w1c_patch: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1);
    if n = 0 then raise exception 'w1c_patch: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'w1c_patch: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'w1c_patch: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;
revoke all on function public._w1c_patch(regprocedure, text[], text) from public, anon, authenticated;

-- append-only guard for the logs of this package
create or replace function public._w1c_append_only() returns trigger language plpgsql as $$
begin raise exception 'w1c_append_only' using hint = 'This log is never edited or deleted'; end $$;

-- one audit_log line (who, when, what, from, to)
create or replace function public._w1c_audit(p_action text, p_table text, p_rec text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_rec, coalesce(p_detail, '{}'::jsonb));
end $$;
revoke all on function public._w1c_audit(text, text, text, jsonb) from public, anon, authenticated;

-- one row in the Exceptions list (same table the stock exceptions use); the same open one for the same ref is not written twice
create or replace function public._w1c_exc(p_loc int, p_form text, p_flag text, p_level text, p_en text, p_ref text, p_amount numeric default null, p_date date default null) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_ref is not null and exists (select 1 from public.exceptions x where x.flag_code = p_flag and x.status = 'open' and x.text ->> 'ref' = p_ref) then return false; end if;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, null, p_form, coalesce(p_loc, (select min(id) from public.locations)), coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date), p_flag, p_level, p_amount,
            jsonb_build_object('bn', p_en, 'en', p_en, 'ref', p_ref));
  return true;
end $$;
revoke all on function public._w1c_exc(int, text, text, text, text, text, numeric, date) from public, anon, authenticated;

-- ---------- tables ----------
create table if not exists public.w1c_exit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  employee_id uuid not null references public.employees(id),
  profile_id uuid,
  from_status text, to_status text,
  action text not null check (action in ('revoked', 'alert_only', 'kept', 'keep_ended', 'reenabled', 'skipped_owner', 'skipped_self', 'no_linked_login', 'already_disabled', 'scan_alert')),
  grants_ended int not null default 0, lists_ended int not null default 0, devices_off int not null default 0,
  reason text, by_user uuid
);
create index if not exists w1c_exit_log_emp on public.w1c_exit_log (employee_id, id);
drop trigger if exists w1c_exit_log_ro on public.w1c_exit_log;
create trigger w1c_exit_log_ro before update or delete on public.w1c_exit_log for each row execute function public._w1c_append_only();
alter table public.w1c_exit_log enable row level security;
drop policy if exists w1c_exit_log_read on public.w1c_exit_log;
create policy w1c_exit_log_read on public.w1c_exit_log for select to authenticated using (public.is_owner() or public._emp_any(array['employee_manage']));
revoke all on table public.w1c_exit_log from anon, authenticated; grant select on table public.w1c_exit_log to authenticated;
revoke all on sequence public.w1c_exit_log_id_seq from anon, authenticated;

create table if not exists public.w1c_exit_keep (
  employee_id uuid primary key references public.employees(id),
  profile_id uuid,
  reason text not null check (char_length(btrim(reason)) >= 3 and char_length(reason) <= 300),
  kept_by uuid, kept_at timestamptz not null default now(),
  ended_at timestamptz, ended_by uuid, end_reason text
);
drop trigger if exists audit_w1c_exit_keep on public.w1c_exit_keep;
create trigger audit_w1c_exit_keep after insert or update on public.w1c_exit_keep for each row execute function public.log_change('employee_id');
drop trigger if exists w1c_exit_keep_nodel on public.w1c_exit_keep;
create trigger w1c_exit_keep_nodel before delete on public.w1c_exit_keep for each row execute function public.no_hard_delete();
alter table public.w1c_exit_keep enable row level security;
drop policy if exists w1c_exit_keep_read on public.w1c_exit_keep;
create policy w1c_exit_keep_read on public.w1c_exit_keep for select to authenticated using (public.is_owner() or public._emp_any(array['employee_manage']));
revoke all on table public.w1c_exit_keep from anon, authenticated; grant select on table public.w1c_exit_keep to authenticated;

-- ---------- settings and grant (own keys only, on conflict do nothing) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('exit_revoke_mode', 'people', 'choice', '"off"'::jsonb, null, '["off","alert","auto"]'::jsonb, null, null,
  'When a person leaves: what happens to their login', 'When a person leaves: what happens to their login', 'When a person leaves: what happens to their login',
  'off = nothing is touched (today); alert = only a red line in Exceptions; auto = the login is disabled and the grants end',
  'off = nothing is touched (today); alert = only a red line in Exceptions; auto = the login is disabled and the grants end',
  'off = nothing is touched (today); alert = only a red line in Exceptions; auto = the login is disabled and the grants end', 905),
 ('exit_revoke_statuses', 'people', 'text', '"resigned,terminated,retired"'::jsonb, null, null, null, null,
  'Which statuses count as leaving', 'Which statuses count as leaving', 'Which statuses count as leaving',
  'Comma list of: resigned, terminated, retired, on_leave. Recommended: resigned, terminated, retired (not on_leave)',
  'Comma list of: resigned, terminated, retired, on_leave. Recommended: resigned, terminated, retired (not on_leave)',
  'Comma list of: resigned, terminated, retired, on_leave. Recommended: resigned, terminated, retired (not on_leave)', 906),
 ('exit_alert_hours', 'people', 'number', null, 'hours', null, 0, 8760,
  'Hours after leaving before an active login is flagged', 'Hours after leaving before an active login is flagged', 'Hours after leaving before an active login is flagged',
  'Blank = off. A person who left but still has an active login after this many hours becomes a red line in Exceptions',
  'Blank = off. A person who left but still has an active login after this many hours becomes a red line in Exceptions',
  'Blank = off. A person who left but still has an active login after this many hours becomes a red line in Exceptions', 907),
 ('exit_deactivate_devices', 'people', 'switch', 'false'::jsonb, null, null, null, null,
  'Also switch off attendance device tokens the person registered', 'Also switch off attendance device tokens the person registered', 'Also switch off attendance device tokens the person registered',
  'Off = device tokens are left alone (a token is shared by everyone at a place). On = tokens that this person registered are switched off when they leave',
  'Off = device tokens are left alone (a token is shared by everyone at a place). On = tokens that this person registered are switched off when they leave',
  'Off = device tokens are left alone (a token is shared by everyone at a place). On = tokens that this person registered are switched off when they leave', 908)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
values ('exit_keep_access', 'people', 905, 'Keep a login after the person has left', 'Keep a login after the person has left', 'Keep a login after the person has left', 'once')
on conflict (grant_code) do nothing;

-- the status list must contain only known statuses (the setting is free text on the Rules page)
create or replace function public._w1c_status_list_ok(p_txt text) returns boolean language sql immutable as $$
  select p_txt is not null and btrim(p_txt) <> '' and not exists (
    select 1 from unnest(string_to_array(lower(regexp_replace(p_txt, '\s', '', 'g')), ',')) t(s) where t.s not in ('resigned', 'terminated', 'retired', 'on_leave')) $$;
create or replace function public._w1c_rules_guard90() returns trigger language plpgsql as $$
begin
  if new.key = 'exit_revoke_statuses' and new.value is not null and jsonb_typeof(new.value) <> 'null' then
    if jsonb_typeof(new.value) <> 'string' or not public._w1c_status_list_ok(new.value #>> '{}') then raise exception 'bad_value'; end if;
  end if;
  return new;
end $$;
drop trigger if exists w1c_rules_guard90 on public.rules;
create trigger w1c_rules_guard90 before update on public.rules for each row when (new.key = 'exit_revoke_statuses') execute function public._w1c_rules_guard90();

create or replace function public._w1c_exit_statuses() returns text[] language plpgsql stable security definer set search_path = public as $$
declare t text := coalesce(public.rule_txt('exit_revoke_statuses'), 'resigned,terminated,retired');
begin
  if not public._w1c_status_list_ok(t) then t := 'resigned,terminated,retired'; end if;
  return string_to_array(lower(regexp_replace(t, '\s', '', 'g')), ',');
end $$;
revoke all on function public._w1c_exit_statuses() from public, anon, authenticated;

-- is an open keep record in force for this person
create or replace function public._w1c_exit_kept(p_emp uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.w1c_exit_keep k where k.employee_id = p_emp and k.ended_at is null) $$;
revoke all on function public._w1c_exit_kept(uuid) from public, anon, authenticated;

-- ---------- the exit step (called by the hook in employee_status_set, or by the wrapper below) ----------
create or replace function public._w1c_exit_apply(p_emp uuid, p_from text, p_to text, p_date date, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; mode text := coalesce(public.rule_txt('exit_revoke_mode'), 'off'); sts text[] := public._w1c_exit_statuses(); pr public.profiles;
        g int := 0; l int := 0; d int := 0; last_act text; nm text;
begin
  select * into e from public.employees where id = p_emp;
  if not found then return jsonb_build_object('skipped', 'not_found'); end if;
  if coalesce(current_setting('w1c.exit_done', true), '') = p_emp::text || ':' || p_to then return jsonb_build_object('skipped', 'done'); end if;
  perform set_config('w1c.exit_done', p_emp::text || ':' || p_to, true);
  nm := coalesce(nullif(e.employee_no, ''), '-') || ' ' || coalesce(e.full_name_en, e.full_name_bn);
  select * into pr from public.profiles where id = e.profile_id;

  -- coming back: the login THIS feature disabled is enabled again (grants and device tokens are not restored)
  if not (p_to = any (sts)) then
    if pr.id is not null and pr.status = 'disabled' then
      select x.action into last_act from public.w1c_exit_log x where x.employee_id = e.id and x.action in ('revoked', 'reenabled') order by x.id desc limit 1;
      if last_act = 'revoked' then
        update public.profiles set status = 'active' where id = pr.id;
        insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'reenabled', left(p_reason, 300), auth.uid());
        perform public._w1c_audit('staff_exit_login_reenabled', 'profiles', pr.id::text, jsonb_build_object('employee', e.id, 'from', p_from, 'to', p_to, 'reason', p_reason, 'grants_restored', false));
        update public.exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolved_note = 'person came back (' || p_to || ')'
          where flag_code = 'exit_access_open' and status = 'open' and text ->> 'ref' = e.id::text;
        return jsonb_build_object('action', 'reenabled');
      end if;
    end if;
    return jsonb_build_object('action', 'none');
  end if;

  -- leaving
  if mode = 'off' then return jsonb_build_object('action', 'mode_off'); end if;
  if e.profile_id is null or pr.id is null then
    insert into public.w1c_exit_log (employee_id, from_status, to_status, action, reason, by_user) values (e.id, p_from, p_to, 'no_linked_login', left(p_reason, 300), auth.uid());
    perform public._w1c_exc(e.primary_location_id, 'HR', 'exit_no_login_link', 'yellow', nm || ' left (' || p_to || ') and has no linked login, so nothing could be switched off. Check whether this person has a login.', e.id::text);
    return jsonb_build_object('action', 'no_linked_login');
  end if;
  if public._w1c_exit_kept(e.id) then
    insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'kept', 'access kept by the owner (see keep record)', auth.uid());
    return jsonb_build_object('action', 'kept');
  end if;
  if mode = 'alert' then
    insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'alert_only', left(p_reason, 300), auth.uid());
    if pr.status = 'active' then
      perform public._w1c_exc(e.primary_location_id, 'HR', 'exit_access_open', 'red', nm || ' left (' || p_to || ') but the login is still active. Disable it or keep it with a reason.', e.id::text);
    end if;
    return jsonb_build_object('action', 'alert_only');
  end if;
  -- mode auto
  if exists (select 1 from public.user_roles ur where ur.user_id = pr.id and ur.role_code = 'owner') then
    insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'skipped_owner', left(p_reason, 300), auth.uid());
    perform public._w1c_exc(e.primary_location_id, 'HR', 'exit_access_open', 'red', nm || ' left (' || p_to || ') but holds the owner role: the login was not disabled automatically.', e.id::text);
    return jsonb_build_object('action', 'skipped_owner');
  end if;
  if pr.id = auth.uid() then
    insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'skipped_self', left(p_reason, 300), auth.uid());
    perform public._w1c_exc(e.primary_location_id, 'HR', 'exit_access_open', 'red', nm || ' changed their own status to ' || p_to || ': the login was not disabled automatically.', e.id::text);
    return jsonb_build_object('action', 'skipped_self');
  end if;
  if pr.status = 'disabled' then
    insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'already_disabled', left(p_reason, 300), auth.uid());
    return jsonb_build_object('action', 'already_disabled');
  end if;
  update public.profiles set status = 'disabled' where id = pr.id;
  update public.user_grants set valid_until = now(), note = left(coalesce(note || ' ', '') || '[ended: staff exit ' || p_to || ']', 500)
    where user_id = pr.id and (valid_until is null or valid_until > now());
  get diagnostics g = row_count;
  update public.list_managers set active = false where user_id = pr.id and active;
  get diagnostics l = row_count;
  if public.rule_on('exit_deactivate_devices') then
    update public.attendance_devices set active = false where created_by = pr.id and active;
    get diagnostics d = row_count;
  end if;
  insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, grants_ended, lists_ended, devices_off, reason, by_user)
    values (e.id, pr.id, p_from, p_to, 'revoked', g, l, d, left(p_reason, 300), auth.uid());
  perform public._w1c_audit('staff_exit_access_revoked', 'profiles', pr.id::text,
    jsonb_build_object('employee', e.id, 'from', p_from, 'to', p_to, 'date', p_date, 'reason', p_reason, 'grants_ended', g, 'list_manager_rows_ended', l, 'device_tokens_off', d));
  return jsonb_build_object('action', 'revoked', 'grants_ended', g, 'devices_off', d);
end $$;
revoke all on function public._w1c_exit_apply(uuid, text, text, date, text) from public, anon, authenticated;

-- wrapper: same call as employee_status_set; does the exit step once (also when the hook line is not installed yet)
create or replace function public._w1c_employee_status_set(p_id uuid, p_status text, p_date date, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_from text; r jsonb; x jsonb;
begin
  select status into v_from from public.employees where id = p_id;
  r := public.employee_status_set(p_id, p_status, p_date, p_reason);
  x := public._w1c_exit_apply(p_id, v_from, p_status, p_date, nullif(left(btrim(coalesce(p_reason, '')), 300), ''));
  -- integration fix (phase99): with the hook installed the step already ran inside employee_status_set, so the call above answers "done". Report what that step logged in this transaction.
  if x ->> 'skipped' = 'done' then
    select jsonb_build_object('action', l.action, 'grants_ended', l.grants_ended, 'lists_ended', l.lists_ended, 'devices_off', l.devices_off) into x
      from public.w1c_exit_log l where l.employee_id = p_id and l.at = now() order by l.id desc limit 1;
    x := coalesce(x, jsonb_build_object('action', 'done_by_hook'));
  end if;
  return r || jsonb_build_object('exit', x);
end $$;
revoke all on function public._w1c_employee_status_set(uuid, text, date, text) from public, anon; grant execute on function public._w1c_employee_status_set(uuid, text, date, text) to authenticated;

-- ---------- exception path: keep one person's access ----------
create or replace function public._w1c_exit_keep(p_employee uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; pr public.profiles; v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 300), ''); restored boolean := false; last_act text;
begin
  if not public.has_grant('exit_keep_access') then raise exception 'not allowed'; end if;
  if v_reason is null or char_length(v_reason) < 3 then raise exception 'reason_required'; end if;
  select * into e from public.employees where id = p_employee for update;
  if not found then raise exception 'not_found'; end if;
  if e.profile_id is null then raise exception 'no_linked_login'; end if;
  select * into pr from public.profiles where id = e.profile_id;
  insert into public.w1c_exit_keep (employee_id, profile_id, reason, kept_by, kept_at, ended_at, ended_by, end_reason)
    values (e.id, e.profile_id, v_reason, auth.uid(), now(), null, null, null)
    on conflict (employee_id) do update set profile_id = excluded.profile_id, reason = excluded.reason, kept_by = excluded.kept_by, kept_at = now(), ended_at = null, ended_by = null, end_reason = null;
  if pr.status = 'disabled' then
    select x.action into last_act from public.w1c_exit_log x where x.employee_id = e.id and x.action in ('revoked', 'reenabled') order by x.id desc limit 1;
    if last_act = 'revoked' then update public.profiles set status = 'active' where id = pr.id; restored := true; end if;
  end if;
  insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, e.profile_id, e.status, e.status, 'kept', v_reason, auth.uid());
  perform public._w1c_audit('staff_exit_access_kept', 'profiles', e.profile_id::text, jsonb_build_object('employee', e.id, 'status', e.status, 'reason', v_reason, 'login_restored', restored));
  perform public._w1c_exc(e.primary_location_id, 'HR', 'exit_access_kept', 'yellow',
    coalesce(nullif(e.employee_no, ''), '-') || ' ' || coalesce(e.full_name_en, e.full_name_bn) || ': login kept although status is ' || e.status || '. Reason: ' || v_reason, e.id::text || ':keep:' || extract(epoch from now())::bigint);
  update public.exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolved_note = 'access kept: ' || v_reason
    where flag_code = 'exit_access_open' and status = 'open' and text ->> 'ref' = e.id::text;
  return jsonb_build_object('employee', e.id, 'kept', true, 'login_restored', restored);
end $$;
revoke all on function public._w1c_exit_keep(uuid, text) from public, anon; grant execute on function public._w1c_exit_keep(uuid, text) to authenticated;

create or replace function public._w1c_exit_keep_end(p_employee uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 300), ''); n int; x jsonb := '{}';
begin
  if not public.has_grant('exit_keep_access') then raise exception 'not allowed'; end if;
  if v_reason is null or char_length(v_reason) < 3 then raise exception 'reason_required'; end if;
  select * into e from public.employees where id = p_employee for update;
  if not found then raise exception 'not_found'; end if;
  update public.w1c_exit_keep set ended_at = now(), ended_by = auth.uid(), end_reason = v_reason where employee_id = e.id and ended_at is null;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_kept'; end if;
  insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, e.profile_id, e.status, e.status, 'keep_ended', v_reason, auth.uid());
  perform public._w1c_audit('staff_exit_keep_ended', 'profiles', coalesce(e.profile_id::text, '-'), jsonb_build_object('employee', e.id, 'status', e.status, 'reason', v_reason));
  perform set_config('w1c.exit_done', '', true);
  if e.status = any (public._w1c_exit_statuses()) then x := public._w1c_exit_apply(e.id, e.status, e.status, public._dhaka_today(), 'keep ended: ' || v_reason); end if;
  return jsonb_build_object('employee', e.id, 'kept', false, 'exit', x);
end $$;
revoke all on function public._w1c_exit_keep_end(uuid, text) from public, anon; grant execute on function public._w1c_exit_keep_end(uuid, text) to authenticated;

-- ---------- the alert scan (owner screen, scheduler or notification run) ----------
-- the work itself, no caller check: for a scheduler or the notification run (the hook line is in docs/integration/W1-C.md)
create or replace function public._w1c_exit_scan_run() returns jsonb language plpgsql security definer set search_path = public as $$
declare h numeric := public.rule_num('exit_alert_hours'); sts text[] := public._w1c_exit_statuses(); r record; n int := 0; nm text;
begin
  if h is null then return jsonb_build_object('raised', 0, 'skipped', 'alert_hours_blank'); end if;
  for r in
    select e.id, e.employee_no, e.full_name_en, e.full_name_bn, e.status, e.primary_location_id,
           coalesce((select max(x.at) from public.employee_status_log x where x.employee_id = e.id and x.to_status = e.status), e.status_date::timestamptz) as left_at
      from public.employees e join public.profiles pr on pr.id = e.profile_id
     where e.status = any (sts) and pr.status = 'active'
       and not exists (select 1 from public.user_roles ur where ur.user_id = pr.id and ur.role_code = 'owner')
       and not public._w1c_exit_kept(e.id)
  loop
    continue when r.left_at is null or r.left_at > now() - make_interval(secs => h * 3600);
    nm := coalesce(nullif(r.employee_no, ''), '-') || ' ' || coalesce(r.full_name_en, r.full_name_bn);
    if public._w1c_exc(r.primary_location_id, 'HR', 'exit_access_open', 'red', nm || ' left (' || r.status || ') and the login is still active after ' || h::text || ' hours.', r.id::text) then
      n := n + 1;
      insert into public.w1c_exit_log (employee_id, from_status, to_status, action, reason, by_user) values (r.id, r.status, r.status, 'scan_alert', 'still active after ' || h::text || ' hours', auth.uid());
    end if;
  end loop;
  return jsonb_build_object('raised', n, 'hours', h);
end $$;
revoke all on function public._w1c_exit_scan_run() from public, anon, authenticated;

create or replace function public._w1c_exit_scan() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not (public.is_owner() or public._emp_any(array['employee_manage'])) then raise exception 'not allowed'; end if;
  return public._w1c_exit_scan_run();
end $$;
revoke all on function public._w1c_exit_scan() from public, anon; grant execute on function public._w1c_exit_scan() to authenticated;

-- ---------- screen data ----------
create or replace function public._w1c_exit_settings() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public._emp_any(array['employee_manage'])) then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'mode', coalesce(public.rule_txt('exit_revoke_mode'), 'off'), 'statuses', to_jsonb(public._w1c_exit_statuses()), 'alert_hours', public.rule_num('exit_alert_hours'),
    'devices', public.rule_on('exit_deactivate_devices'), 'can_keep', public.has_grant('exit_keep_access'), 'is_owner', public.is_owner(),
    'allowed_statuses', jsonb_build_array('resigned', 'terminated', 'retired', 'on_leave'));
end $$;
revoke all on function public._w1c_exit_settings() from public, anon; grant execute on function public._w1c_exit_settings() to authenticated;

create or replace function public._w1c_exit_settings_set(p_mode text, p_statuses text, p_alert_hours numeric, p_devices boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old jsonb; st text := lower(regexp_replace(coalesce(p_statuses, ''), '\s', '', 'g'));
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('off', 'alert', 'auto') then raise exception 'bad_mode'; end if;
  if not public._w1c_status_list_ok(st) then raise exception 'bad_statuses'; end if;
  if p_alert_hours is not null and not (p_alert_hours between 0 and 8760) then raise exception 'bad_hours'; end if;
  old := jsonb_build_object('mode', coalesce(public.rule_txt('exit_revoke_mode'), 'off'), 'statuses', public._w1c_exit_statuses(), 'alert_hours', public.rule_num('exit_alert_hours'), 'devices', public.rule_on('exit_deactivate_devices'));
  perform public.set_rule('exit_revoke_mode', to_jsonb(p_mode));
  perform public.set_rule('exit_revoke_statuses', to_jsonb(st));
  perform public.set_rule('exit_alert_hours', case when p_alert_hours is null then 'null'::jsonb else to_jsonb(p_alert_hours) end);
  perform public.set_rule('exit_deactivate_devices', to_jsonb(coalesce(p_devices, false)));
  perform public._w1c_audit('exit_settings_changed', 'rules', 'exit_*', jsonb_build_object('old', old,
    'new', jsonb_build_object('mode', p_mode, 'statuses', string_to_array(st, ','), 'alert_hours', p_alert_hours, 'devices', coalesce(p_devices, false)), 'note', left(p_note, 300)));
  return public._w1c_exit_settings();
end $$;
revoke all on function public._w1c_exit_settings_set(text, text, numeric, boolean, text) from public, anon; grant execute on function public._w1c_exit_settings_set(text, text, numeric, boolean, text) to authenticated;

-- people who left and still have an active login (the list the owner acts on)
create or replace function public._w1c_exit_open_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare sts text[] := public._w1c_exit_statuses();
begin
  if not (public.is_owner() or public._emp_any(array['employee_manage'])) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'name_en', e.full_name_en, 'name_bn', e.full_name_bn, 'status', e.status,
           'status_date', e.status_date, 'staff_id', pr.staff_id, 'login_status', pr.status, 'kept', public._w1c_exit_kept(e.id),
           'kept_reason', (select k.reason from public.w1c_exit_keep k where k.employee_id = e.id and k.ended_at is null)) order by e.status_date desc nulls last, e.employee_no)
      from public.employees e join public.profiles pr on pr.id = e.profile_id
     where (e.status = any (sts) and pr.status = 'active') or public._w1c_exit_kept(e.id)), '[]'::jsonb);
end $$;
revoke all on function public._w1c_exit_open_list() from public, anon; grant execute on function public._w1c_exit_open_list() to authenticated;

create or replace function public._w1c_exit_log_list(p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public._emp_any(array['employee_manage'])) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(x) from (select jsonb_build_object('id', l.id, 'at', l.at, 'employee_id', l.employee_id, 'employee_no', e.employee_no, 'name_en', e.full_name_en, 'name_bn', e.full_name_bn,
           'from', l.from_status, 'to', l.to_status, 'action', l.action, 'grants_ended', l.grants_ended, 'lists_ended', l.lists_ended, 'devices_off', l.devices_off, 'reason', l.reason) x
      from public.w1c_exit_log l join public.employees e on e.id = l.employee_id order by l.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) q), '[]'::jsonb);
end $$;
revoke all on function public._w1c_exit_log_list(int) from public, anon; grant execute on function public._w1c_exit_log_list(int) to authenticated;
