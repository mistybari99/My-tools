-- ============================================================
-- Phase 70 - Gap #17: restore drill (record of "did we prove the backup can be restored?")
-- Run AFTER phase46 (backup). Additive and idempotent (paste it twice = no error). Nothing is deleted.
--   * restore_drills            append-only trail of drills (tools/restore_drill.py prints the result; the owner records it here)
--   * restore_drill_record(...) owner only
--   * restore_drill_list(n)     owner only
--   * restore_drill_status()    owner only: last drill, its age, warn when none in restore_drill_warn_days (default 90)
--   * rule restore_drill_warn_days (90)
--   * bos70: public._backup_tables() re-created ONLY to stop the blunt "token" column filter from hiding assistant_usage
--            (its tokens_in / tokens_out are plain counters, not secrets). attendance_devices (token_hash), ops_*, login_*, *_secret*,
--            backup_runs, notifications, notification_reads stay excluded - see docs/RESTORE_DRILL.md.
-- ============================================================

create table if not exists public.restore_drills (
  id bigserial primary key,
  drilled_at timestamptz not null default now(),
  backup_name text not null check (length(btrim(backup_name)) between 1 and 200),
  result text not null check (result in ('pass', 'fail')),
  tables_ok boolean not null default false,
  rows_ok boolean not null default false,
  notes text check (notes is null or length(notes) <= 2000),
  recorded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists restore_drills_at on public.restore_drills (drilled_at desc);

create or replace function public._append_only70() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
revoke all on function public._append_only70() from public, anon, authenticated;
drop trigger if exists restore_drills_ro on public.restore_drills;
create trigger restore_drills_ro before update or delete on public.restore_drills for each row execute function public._append_only70();

alter table public.restore_drills enable row level security;
revoke all on public.restore_drills from public, anon, authenticated;
grant select on public.restore_drills to authenticated;
revoke usage, select on sequence public.restore_drills_id_seq from public, anon, authenticated;
drop policy if exists restore_drills_read on public.restore_drills;
create policy restore_drills_read on public.restore_drills for select to authenticated using (public.is_owner());

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('restore_drill_warn_days', 'notify', 'number', '90', 'দিন', null, 7, 730, 'রিস্টোর ড্রিল কত দিনের মধ্যে একবার করতে হবে', 'Restore drill কত দিনে একবার', 'Run a restore drill at least every (days)', 'এর বেশি দিন ড্রিল না হলে অ্যাপ সতর্ক করে।', 'The app warns when no drill was recorded within this many days.', 331)
 on conflict (key) do nothing;

create or replace function public.restore_drill_record(p_backup_name text, p_result text, p_tables_ok boolean default false, p_rows_ok boolean default false,
                                                       p_notes text default null, p_drilled_at timestamptz default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare rid bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_backup_name is null or length(btrim(p_backup_name)) not between 1 and 200 then raise exception 'bad_input'; end if;
  if p_result is null or p_result not in ('pass', 'fail') then raise exception 'bad_input'; end if;
  if p_notes is not null and length(p_notes) > 2000 then raise exception 'bad_input'; end if;
  if p_drilled_at is not null and p_drilled_at > now() + interval '5 minutes' then raise exception 'bad_input'; end if;
  if p_result = 'pass' and not (coalesce(p_tables_ok, false) and coalesce(p_rows_ok, false)) then raise exception 'pass_needs_tables_and_rows_ok'; end if;
  insert into public.restore_drills (drilled_at, backup_name, result, tables_ok, rows_ok, notes, recorded_by)
    values (coalesce(p_drilled_at, now()), btrim(p_backup_name), p_result, coalesce(p_tables_ok, false), coalesce(p_rows_ok, false), nullif(btrim(coalesce(p_notes, '')), ''), auth.uid())
    returning id into rid;
  return rid;
end $$;

create or replace function public.restore_drill_list(p_limit int default 20) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.drilled_at desc, x.id desc)
    from (select d.id, d.drilled_at, d.backup_name, d.result, d.tables_ok, d.rows_ok, d.notes, d.recorded_by
            from public.restore_drills d order by d.drilled_at desc, d.id desc limit least(greatest(coalesce(p_limit, 20), 1), 200)) x), '[]'::jsonb);
end $$;

create or replace function public.restore_drill_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare warn_days numeric := coalesce(public.rule_num('restore_drill_warn_days'), 90); last_ record; lastpass record; age numeric; agep numeric;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into last_ from public.restore_drills order by drilled_at desc, id desc limit 1;
  select * into lastpass from public.restore_drills where result = 'pass' order by drilled_at desc, id desc limit 1;
  age := case when last_.id is null then null else round(extract(epoch from (now() - last_.drilled_at)) / 86400, 1) end;
  agep := case when lastpass.id is null then null else round(extract(epoch from (now() - lastpass.drilled_at)) / 86400, 1) end;
  return jsonb_build_object('warn_days', warn_days, 'drills', (select count(*) from public.restore_drills),
    'last', case when last_.id is null then null else jsonb_build_object('id', last_.id, 'at', last_.drilled_at, 'result', last_.result, 'backup_name', last_.backup_name) end,
    'age_days', age, 'last_pass_age_days', agep,
    'never', last_.id is null,
    'warn', (agep is null or agep > warn_days),
    'last_failed', coalesce(last_.result = 'fail', false));
end $$;

-- bos70: same as phase46 except the column filter no longer matches tokens_in / tokens_out (assistant_usage counters)
create or replace function public._backup_tables() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}'::text[])
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relispartition
     and c.relname::text not like '%\_secret%' escape '\'
     and c.relname::text not like 'ops\_%' escape '\'
     and c.relname::text not in ('login_failures', 'login_attempts', 'login_throttle', 'backup_runs', 'notifications', 'notification_reads')
     and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                      and a.attname::text !~ '^tokens_(in|out)$'
                      and a.attname::text ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)');
$$;

do $$ declare f text; r regprocedure; begin
  foreach f in array array['restore_drill_record', 'restore_drill_list', 'restore_drill_status'] loop
    for r in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f loop
      execute format('revoke all on function %s from public, anon, authenticated', r);
      execute format('grant execute on function %s to authenticated', r);
    end loop;
  end loop;
end $$;
notify pgrst, 'reload schema';
