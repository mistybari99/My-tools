-- Phase 142 (bos142) - W1-FIX: a staff exit cannot be undone by linking a login or by a non-owner reactivation (finding 8 of the independent Wave 1 check).
-- Paste after phase99, paste-twice safe. Earlier phase files are not edited.
--
-- THE GAPS (both reproduced on a database built through phase 99 with exit_revoke_mode = auto, see tests in phase142_test.sql):
--   1. employee_link_profile on a person who has ALREADY left: the exit step ran when the status changed (and found no login, or an older one), so a login linked
--      afterwards stayed active. The leaver had a working login again.
--   2. When the owner counts on_leave as a leaving status (exit_revoke_statuses), a person with only the right employee_manage could set the status back to
--      active, and phase90 then enabled the login that the exit had disabled. (For resigned, terminated and retired employee_status_set already says owner_only.)
--
-- WHAT THIS CHANGES (no new switch: it follows the existing owner setting exit_revoke_mode; with it OFF nothing here does anything)
--   1. After a login is linked to a person whose status is a leaving status, the same exit step as at the moment of leaving runs again (_w1c_exit_apply):
--      mode auto = the new login is disabled and its grants end (unless the owner kept the access with a reason, or it is the owner role, or the caller's own login),
--      mode alert = the red line "login still active" is raised. Every outcome is in w1c_exit_log and one audit_log line (staff_exit_link_checked).
--   2. With mode auto, coming back from a leaving status when the login was disabled by the exit step needs the owner (error owner_only, the status is not changed).
--      The owner brings the person back as before; the existing step then enables the login and logs it with the reason (audit_log staff_exit_login_reenabled).
--
-- HOW: two exact-text lines, patched with _w1x_patch (markers bos142): one in employee_link_profile, one in employee_status_set (docs/integration/W1-FIX.md).
-- phase143 puts the lines back if phase12/phase41 is pasted again.

do $g$ begin
  if to_regprocedure('public._w1c_exit_apply(uuid,text,text,date,text)') is null then raise exception 'phase142 needs phase90 (and phase99)'; end if;
  if to_regprocedure('public._i1_apply_hooks()') is null then raise exception 'phase142 needs phase99 pasted first'; end if;
  if to_regprocedure('public.employee_link_profile(uuid,uuid)') is null or to_regprocedure('public.employee_status_set(uuid,text,date,text)') is null then
    raise exception 'phase142 needs the employee functions (phase41)';
  end if;
end $g$;

create or replace function public._w1x_present142() returns boolean language sql immutable as $$ select true $$;

-- patch helper of this package (same text as in phase140; create or replace is harmless to repeat)
create or replace function public._w1x_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos14[0-9]$' then raise exception 'w1x_patch: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1);
    if n = 0 then raise exception 'w1x_patch: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'w1x_patch: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'w1x_patch: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;
revoke all on function public._w1x_patch(regprocedure, text[], text) from public, anon, authenticated;

-- ---------- 1. a login linked after the person left ----------
create or replace function public._w1x_link_after(p_emp uuid, p_profile uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; mode text := coalesce(public.rule_txt('exit_revoke_mode'), 'off'); res jsonb;
begin
  if p_profile is null then return jsonb_build_object('skipped', 'unlinked'); end if;
  if mode = 'off' then return jsonb_build_object('skipped', 'mode_off'); end if;
  select * into e from public.employees where id = p_emp;
  if not found or not (e.status = any (public._w1c_exit_statuses())) then return jsonb_build_object('skipped', 'not_left'); end if;
  perform set_config('w1c.exit_done', '', true);                 -- the exit step may run again for the same person in this transaction
  res := public._w1c_exit_apply(e.id, e.status, e.status, coalesce(e.status_date, (now() at time zone 'Asia/Dhaka')::date), 'login linked after the person had left');
  perform public._w1c_audit('staff_exit_link_checked', 'employees', e.id::text, jsonb_build_object('profile', p_profile, 'status', e.status, 'mode', mode, 'result', res));
  return res;
end $$;
revoke all on function public._w1x_link_after(uuid, uuid) from public, anon, authenticated;

-- ---------- 2. coming back needs the owner when the exit step disabled the login ----------
create or replace function public._w1x_reactivate_guard(p_emp uuid, p_from text, p_to text) returns void language plpgsql security definer set search_path = public as $$
declare mode text := coalesce(public.rule_txt('exit_revoke_mode'), 'off'); sts text[] := public._w1c_exit_statuses(); e public.employees; st text; last_act text;
begin
  if mode <> 'auto' or public.is_owner() then return; end if;
  if not (p_from = any (sts)) or p_to = any (sts) then return; end if;      -- only a move from a leaving status to a staying one
  select * into e from public.employees where id = p_emp;
  if not found or e.profile_id is null then return; end if;
  select status into st from public.profiles where id = e.profile_id;
  if st is distinct from 'disabled' then return; end if;
  select x.action into last_act from public.w1c_exit_log x where x.employee_id = e.id and x.action in ('revoked', 'reenabled') order by x.id desc limit 1;
  if last_act = 'revoked' then raise exception 'owner_only'; end if;
end $$;
revoke all on function public._w1x_reactivate_guard(uuid, text, text) from public, anon, authenticated;

-- ---------- the hooks (idempotent: nothing happens when marker bos142 is already inside the function) ----------
create or replace function public._w1x142_hooks() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return jsonb_build_object(
    'employee_link_profile', public._w1x_patch('public.employee_link_profile(uuid,uuid)'::regprocedure, array[
      E'  return jsonb_build_object(''id'', e.id, ''profile_id'', p_profile);',
      E'  perform public._w1x_link_after(e.id, p_profile); /* bos142 */\n  return jsonb_build_object(''id'', e.id, ''profile_id'', p_profile);'
    ], 'bos142'),
    'employee_status_set', public._w1x_patch('public.employee_status_set(uuid,text,date,text)'::regprocedure, array[
      E'  update public.employees set status = p_status, status_date = p_date, status_reason = v_reason, updated_by = auth.uid(), updated_at = now() where id = e.id;',
      E'  perform public._w1x_reactivate_guard(e.id, e.status, p_status); /* bos142 */\n  update public.employees set status = p_status, status_date = p_date, status_reason = v_reason, updated_by = auth.uid(), updated_at = now() where id = e.id;'
    ], 'bos142'));
end $$;
revoke all on function public._w1x142_hooks() from public, anon, authenticated;

select public._w1x142_hooks();
