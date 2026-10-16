-- Phase 98 (bos98, package W1-G, items U-11 and U-12) - JOURNAL FRESHNESS, SWITCH-COUPLING WARNING, DATA-PROTECTION SETTINGS.
-- Paste AFTER phase87 (needs the phase 40/72/87 accounting engine). Paste-twice safe. No earlier phase file is edited, no shared function is re-created.
-- The wave integrator (I-1, phase 99) wires the hooks written in docs/integration/W1-G.md; nothing here changes a figure, a screen or a workflow by itself.
--
-- WHY (plan U-11, A-29, G30, G33, G2): the books fill only when an authorised person opens Accounts. Turning on forms_post_to_ledger silently locks four stock screens.
-- WHAT THIS FILE ADDS (every new name starts _w1g_ / w1g_ so it cannot clash with another package)
--   1. _w1g_post_scheduled(p_dry)   scheduled poster. Same engine calls as acct_post_pending (_acct_docs -> _acct_resolve -> _acct_write / _acct_reverse, same
--                                   advisory lock, same acct_post_errors72 bookkeeping), plus: a watermark per source type (w1g_post_watermark), a cap per run,
--                                   fair rotation between source types, an optional source-type list and look-back window, one audit_log line per run that posted.
--                                   OFF by default (rule journal_sched_post_on). Called by the existing notify workflow (ops bot, purpose notify) or by the owner /
--                                   accounts manager, or from pg_cron when the database offers it [unverified: plan]. A dry run never writes and works while OFF.
--   2. _w1g_freshness()             data for the "last posted at" strip on Home and Accounts (read only).
--   3. _w1g_acct_readiness()        G2: start date, switch, opening entry, mappings, waiting documents, posting errors, scheduler state (read only).
--   4. _w1g_switch_coupling_warning(key, value) + _w1g_switch_coupling_ack(...)   the text shown BEFORE a coupled switch is saved: what locks / unlocks.
--      Rule switch_coupling_warning = off | warn (default) | confirm. In confirm mode a server trigger refuses turning a coupled switch ON without a fresh owner
--      confirmation, so a hidden button is also a refused request.
--   5. U-12 settings read by tools/backup_dump.py: backup_encrypt_on (OFF), backup_retention_days (blank). _w1g_backup_settings() for the backup bot.
-- DEFAULTS: every new rule defaults to OFF or blank, so with the defaults the books, reports and workflows behave exactly as before (proved by
-- tests/sql/phase98_before_after.sh). Re-pasting an older phase does not touch anything here (no shared function is patched).

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase98 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public._acct_docs(date)') is null or to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null
     or to_regprocedure('public._acct_reverse(bigint,date,text,uuid)') is null or to_regprocedure('public._is_ops(text)') is null
     or to_regclass('public.acct_post_errors72') is null or to_regclass('public.path_domains') is null then
    raise exception 'phase98 needs the accounting engine (phase 40, 46, 48, 72) first';
  end if;
end $g$;

create or replace function public._w1g_present() returns boolean language sql stable as $$ select true $$;

-- ============================================================================
-- 1. SETTINGS (rules). Every row: safe default, English label and hint. Changes are logged by the existing audit_rules trigger.
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('journal_sched_post_on', 'books', 'switch', 'false'::jsonb, null, null, null, null,
  'Post new documents to the books on a schedule', 'Post new documents to the books on a schedule', 'Post new documents to the books on a schedule',
  'OFF = the books fill only when someone presses Post now or opens Accounts (today). ON = the 30-minute notify job posts waiting documents by itself. Needs Accounting on and a start date.',
  'OFF = the books fill only when someone presses Post now or opens Accounts (today). ON = the 30-minute notify job posts waiting documents by itself. Needs Accounting on and a start date.',
  'OFF = the books fill only when someone presses Post now or opens Accounts (today). ON = the 30-minute notify job posts waiting documents by itself. Needs Accounting on and a start date.', 900),
 ('journal_sched_post_cap', 'books', 'number', '1500'::jsonb, 'documents', null, 1, 5000, 'Most documents one scheduled run may post', 'Most documents one scheduled run may post', 'Most documents one scheduled run may post',
  'A technical batch size, not a business limit (1500 = the same batch as Post now). Documents over the cap wait for the next run, oldest first.',
  'A technical batch size, not a business limit (1500 = the same batch as Post now). Documents over the cap wait for the next run, oldest first.',
  'A technical batch size, not a business limit (1500 = the same batch as Post now). Documents over the cap wait for the next run, oldest first.', 901),
 ('journal_sched_post_types', 'books', 'text', null, null, null, null, null, 'Scheduled posting: only these source types', 'Scheduled posting: only these source types', 'Scheduled posting: only these source types',
  'Blank = every source type. Otherwise a comma list such as sale,sale_return. Types left out are still posted by Post now.',
  'Blank = every source type. Otherwise a comma list such as sale,sale_return. Types left out are still posted by Post now.',
  'Blank = every source type. Otherwise a comma list such as sale,sale_return. Types left out are still posted by Post now.', 902),
 ('journal_sched_post_lookback_days', 'books', 'number', null, 'days', null, 1, 3650, 'Scheduled posting: look back this many days', 'Scheduled posting: look back this many days', 'Scheduled posting: look back this many days',
  'Blank = scan every document since the accounting start date (slowest, safest). A number makes each run look only at the last N days; older leftovers need Post now.',
  'Blank = scan every document since the accounting start date (slowest, safest). A number makes each run look only at the last N days; older leftovers need Post now.',
  'Blank = scan every document since the accounting start date (slowest, safest). A number makes each run look only at the last N days; older leftovers need Post now.', 903),
 ('journal_stale_warn_hours', 'books', 'number', null, 'hours', null, 1, 8760, 'Warn when waiting documents are not posted for this many hours', 'Warn when waiting documents are not posted for this many hours',
  'Warn when waiting documents are not posted for this many hours',
  'Blank = the "last posted at" strip never turns red (it only shows the facts). A number turns it red when documents wait and nothing was posted for that long.',
  'Blank = the "last posted at" strip never turns red (it only shows the facts). A number turns it red when documents wait and nothing was posted for that long.',
  'Blank = the "last posted at" strip never turns red (it only shows the facts). A number turns it red when documents wait and nothing was posted for that long.', 904),
 ('switch_coupling_warning', 'settings', 'choice', '"warn"'::jsonb, null, '["off","warn","confirm"]'::jsonb, null, null, 'Warning before a switch that locks other screens', 'Warning before a switch that locks other screens', 'Warning before a switch that locks other screens',
  'off = no warning. warn = the screen shows what the switch will lock or unlock before it is saved (default; changes nothing else). confirm = the owner must also tick a confirmation, enforced on the server.',
  'off = no warning. warn = the screen shows what the switch will lock or unlock before it is saved (default; changes nothing else). confirm = the owner must also tick a confirmation, enforced on the server.',
  'off = no warning. warn = the screen shows what the switch will lock or unlock before it is saved (default; changes nothing else). confirm = the owner must also tick a confirmation, enforced on the server.', 910),
 ('backup_encrypt_on', 'notify', 'switch', 'false'::jsonb, null, null, null, null, 'Encrypt the nightly backup files', 'Encrypt the nightly backup files', 'Encrypt the nightly backup files',
  'Keep OFF until the owner holds the passphrase (secret BACKUP_PASSPHRASE). ON with no passphrase makes the backup FAIL on purpose; it never falls back to plain files. Restore needs the same passphrase.',
  'Keep OFF until the owner holds the passphrase (secret BACKUP_PASSPHRASE). ON with no passphrase makes the backup FAIL on purpose; it never falls back to plain files. Restore needs the same passphrase.',
  'Keep OFF until the owner holds the passphrase (secret BACKUP_PASSPHRASE). ON with no passphrase makes the backup FAIL on purpose; it never falls back to plain files. Restore needs the same passphrase.', 920),
 ('backup_retention_days', 'notify', 'number', null, 'days', null, 1, 36500, 'Keep dated backup folders for this many days', 'Keep dated backup folders for this many days', 'Keep dated backup folders for this many days',
  'Blank = keep every dated folder (today). A number lets tools/backup_retention.py list (and, only when told to, remove) older dated folders. The newest folder is never removed. Git history still holds old files.',
  'Blank = keep every dated folder (today). A number lets tools/backup_retention.py list (and, only when told to, remove) older dated folders. The newest folder is never removed. Git history still holds old files.',
  'Blank = keep every dated folder (today). A number lets tools/backup_retention.py list (and, only when told to, remove) older dated folders. The newest folder is never removed. Git history still holds old files.', 921)
on conflict (key) do nothing;

-- ============================================================================
-- 2. STATE TABLES (no browser access; read only through the definer functions below)
-- ============================================================================
create table if not exists public.w1g_post_watermark (            -- one row per journal source type the scheduler has seen
  source_type text primary key,
  last_run_at timestamptz,                  -- last run in which a document of this type was handled (rotation: the type served longest ago goes first)
  last_posted_at timestamptz,               -- last time the scheduler posted or reversed a document of this type
  last_posted_date date,                    -- document date of the newest document the scheduler posted
  posted_total bigint not null default 0,
  reversed_total bigint not null default 0,
  pending_after int not null default 0,     -- still waiting after the last run (over the cap, period locked, or failed)
  capped_after int not null default 0,
  locked_after int not null default 0,
  errors_after int not null default 0,
  oldest_pending date,
  watermark_date date,                      -- everything of this type dated up to here was posted at the last run (today when nothing waits)
  updated_at timestamptz not null default now()
);
create table if not exists public.w1g_sched_state (               -- one row: when the scheduler last looked, even when there was nothing to post
  id int primary key check (id = 1),
  last_run_at timestamptz, last_run_by uuid, last_via text, last_result jsonb
);
create table if not exists public.w1g_post_runs (                 -- append only: one line per real run that posted, reversed, failed or hit the cap
  id bigserial primary key,
  at timestamptz not null default now(),
  run_by uuid, via text not null,
  posted int not null default 0, reversed int not null default 0, locked int not null default 0, errors int not null default 0,
  capped boolean not null default false, left_after int not null default 0, floor_date date, by_type jsonb
);
create table if not exists public.w1g_switch_acks (               -- owner confirmations used by switch_coupling_warning = confirm (single use)
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid not null, rule_key text not null, new_value jsonb, note text,
  used_at timestamptz
);
do $t$ declare t text; begin
  foreach t in array array['w1g_post_watermark', 'w1g_sched_state', 'w1g_post_runs', 'w1g_switch_acks'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $t$;

-- ============================================================================
-- 3. SCHEDULED POSTER
-- ============================================================================
create or replace function public._w1g_bump(j jsonb, ty text, k text) returns jsonb language sql immutable as $$
  select jsonb_set(case when j ? ty then j else jsonb_set(j, array[ty], '{}'::jsonb) end, array[ty, k], to_jsonb(coalesce((j #>> array[ty, k])::int, 0) + 1)) $$;
create or replace function public._w1g_oldest(j jsonb, ty text, d date) returns jsonb language sql immutable as $$
  select case when d is null or (j #>> array[ty, 'oldest']) is not null and (j #>> array[ty, 'oldest'])::date <= d then j
         else jsonb_set(case when j ? ty then j else jsonb_set(j, array[ty], '{}'::jsonb) end, array[ty, 'oldest'], to_jsonb(d::text)) end $$;

create or replace function public._w1g_post_scheduled(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare uid uuid := auth.uid(); via text; st date; today date := public._acct_today(); cap int; lb int; floor_ date; types text[]; txt text;
        d record; orig public.journal_entries; ln jsonb; rdate date; eid bigint; n int := 0; posted int := 0; rev int := 0; locked int := 0; waiting int := 0; nerr int := 0;
        capped boolean := false; left_ int := 0; bt jsonb := '{}'; errs jsonb := '[]'; ty text; k text; rid bigint; sid text; res jsonb; seen text[] := '{}';
begin
  -- who may call: the notify bot, the owner, an accounts manager; or the database's own scheduler (no login, role none) - never a browser session without a login
  if uid is not null then
    if not (public._is_ops('notify') or public.is_owner() or public._acct_manage()) then raise exception 'not allowed'; end if;
    via := case when public._is_ops('notify') then 'notify_bot' else 'manual' end;
  else
    if not (session_user in ('postgres', 'supabase_admin') and coalesce(nullif(current_setting('role', true), ''), 'none') = 'none') then raise exception 'not allowed'; end if;
    via := 'database_scheduler';
  end if;
  if not p_dry and not public.rule_on('journal_sched_post_on') then return jsonb_build_object('ran', false, 'skipped', 'switch_off'); end if;
  st := public._acct_start();
  if st is null then return jsonb_build_object('ran', false, 'skipped', 'data_needed', 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then return jsonb_build_object('ran', false, 'skipped', 'accounting_off'); end if;
  if not p_dry and not pg_try_advisory_xact_lock(hashtextextended('acct_post', 0)) then return jsonb_build_object('ran', false, 'skipped', 'busy'); end if;   -- same lock as acct_post_pending
  cap := least(greatest(coalesce(public.rule_num('journal_sched_post_cap'), 1500), 1), 5000)::int;
  lb := public.rule_num('journal_sched_post_lookback_days')::int;
  floor_ := case when lb is null then st else greatest(st, today - lb) end;
  txt := regexp_replace(coalesce(public.rule_txt('journal_sched_post_types'), ''), '\s', '', 'g');
  types := case when txt = '' then null else string_to_array(txt, ',') end;
  -- oldest document first inside a type; types served longest ago go first; a document that failed before goes last, so a poison document cannot starve the rest
  for d in
    select x.* from public._acct_docs(floor_) x
      left join public.w1g_post_watermark w on w.source_type = x.source_type
      left join public.acct_post_errors72 e on e.source_type = x.source_type and e.source_id = x.source_id
     where types is null or x.source_type = any(types)
     order by coalesce(w.last_run_at, '-infinity'::timestamptz), x.source_type, (e.source_id is not null), x.entry_date, x.source_id
  loop
    ty := d.source_type;
    if not (ty = any(seen)) then seen := seen || ty; bt := jsonb_set(bt, array[ty], '{}'::jsonb); end if;
    if d.waiting is not null then waiting := waiting + 1; continue; end if;
    if n >= cap then
      capped := true; left_ := left_ + 1; bt := public._w1g_bump(bt, ty, 'capped'); bt := public._w1g_oldest(bt, ty, d.entry_date); continue;
    end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then
          locked := locked + 1; left_ := left_ + 1; bt := public._w1g_bump(bt, ty, 'locked'); bt := public._w1g_oldest(bt, ty, d.entry_date); continue;
        end if;
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        if not p_dry then eid := public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln); end if;
        posted := posted + 1; bt := public._w1g_bump(bt, ty, 'posted');
        if (bt #>> array[ty, 'last_date']) is null or (bt #>> array[ty, 'last_date'])::date < d.entry_date then bt := jsonb_set(bt, array[ty, 'last_date'], to_jsonb(d.entry_date::text)); end if;
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then
          locked := locked + 1; left_ := left_ + 1; bt := public._w1g_bump(bt, ty, 'locked'); bt := public._w1g_oldest(bt, ty, d.entry_date); continue;
        end if;
        if not p_dry then eid := public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo); end if;
        rev := rev + 1; bt := public._w1g_bump(bt, ty, 'reversed');
      end if;
      if not p_dry then delete from public.acct_post_errors72 where source_type = d.source_type and source_id = d.source_id; end if;
      n := n + 1;
    exception when others then
      nerr := nerr + 1; left_ := left_ + 1; bt := public._w1g_bump(bt, ty, 'errors'); bt := public._w1g_oldest(bt, ty, d.entry_date);
      if jsonb_array_length(errs) < 20 then errs := errs || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', left(sqlerrm, 200)); end if;
      if not p_dry then
        insert into public.acct_post_errors72 (source_type, source_id, error) values (d.source_type, d.source_id, left(sqlerrm, 300))
          on conflict (source_type, source_id) do update set error = excluded.error, tries = public.acct_post_errors72.tries + 1, last_at = now();
      end if;
      n := n + 1;
    end;
  end loop;
  res := jsonb_build_object('ran', not p_dry, 'dry', p_dry, 'posted', posted, 'reversed', rev, 'locked', locked, 'waiting', waiting, 'errors', errs, 'error_count', nerr,
    'capped', capped, 'cap', cap, 'left', left_, 'floor', floor_, 'via', via, 'by_type', bt);
  if p_dry then return res; end if;
  -- watermark per source type
  for ty in select jsonb_object_keys(bt) loop
    k := ty;
    insert into public.w1g_post_watermark as w0 (source_type, last_run_at, last_posted_at, last_posted_date, posted_total, reversed_total, pending_after, capped_after, locked_after, errors_after, oldest_pending, watermark_date, updated_at)
      values (k,
        case when coalesce((bt #>> array[k, 'posted'])::int, 0) + coalesce((bt #>> array[k, 'reversed'])::int, 0) + coalesce((bt #>> array[k, 'errors'])::int, 0) + coalesce((bt #>> array[k, 'locked'])::int, 0) > 0 then now() end,
        case when coalesce((bt #>> array[k, 'posted'])::int, 0) + coalesce((bt #>> array[k, 'reversed'])::int, 0) > 0 then now() end,
        (bt #>> array[k, 'last_date'])::date,
        coalesce((bt #>> array[k, 'posted'])::int, 0), coalesce((bt #>> array[k, 'reversed'])::int, 0),
        coalesce((bt #>> array[k, 'capped'])::int, 0) + coalesce((bt #>> array[k, 'locked'])::int, 0) + coalesce((bt #>> array[k, 'errors'])::int, 0),
        coalesce((bt #>> array[k, 'capped'])::int, 0), coalesce((bt #>> array[k, 'locked'])::int, 0), coalesce((bt #>> array[k, 'errors'])::int, 0),
        (bt #>> array[k, 'oldest'])::date,
        case when (bt #>> array[k, 'oldest']) is null then today else (bt #>> array[k, 'oldest'])::date - 1 end, now())
    on conflict (source_type) do update set
      last_run_at = coalesce(excluded.last_run_at, w0.last_run_at),
      last_posted_at = coalesce(excluded.last_posted_at, w0.last_posted_at),
      last_posted_date = coalesce(excluded.last_posted_date, w0.last_posted_date),
      posted_total = w0.posted_total + excluded.posted_total, reversed_total = w0.reversed_total + excluded.reversed_total,
      pending_after = excluded.pending_after, capped_after = excluded.capped_after, locked_after = excluded.locked_after, errors_after = excluded.errors_after,
      oldest_pending = excluded.oldest_pending, watermark_date = excluded.watermark_date, updated_at = now();
  end loop;
  -- types that had waiting documents at an earlier run and have none now (someone pressed Post now): clear them, but only inside this run's scope
  update public.w1g_post_watermark w set pending_after = 0, capped_after = 0, locked_after = 0, errors_after = 0, oldest_pending = null, watermark_date = today, updated_at = now()
   where not (w.source_type = any(seen)) and (types is null or w.source_type = any(types)) and w.pending_after > 0;
  insert into public.w1g_sched_state as s (id, last_run_at, last_run_by, last_via, last_result)
    values (1, now(), uid, via, jsonb_build_object('posted', posted, 'reversed', rev, 'locked', locked, 'errors', nerr, 'capped', capped, 'left', left_))
    on conflict (id) do update set last_run_at = excluded.last_run_at, last_run_by = excluded.last_run_by, last_via = excluded.last_via, last_result = excluded.last_result;
  if posted + rev + nerr > 0 or capped then
    insert into public.w1g_post_runs (run_by, via, posted, reversed, locked, errors, capped, left_after, floor_date, by_type)
      values (uid, via, posted, rev, locked, nerr, capped, left_, floor_, bt) returning id into rid;
    res := res || jsonb_build_object('run_id', rid);
    if posted + rev > 0 then
      select staff_id into sid from public.profiles where id = uid;
      insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
        values (uid, sid, 'journal_sched_post', 'journal_entries', rid::text, jsonb_build_object('via', via, 'posted', posted, 'reversed', rev, 'errors', nerr, 'capped', capped, 'left', left_, 'by_type', bt));
    end if;
  end if;
  return res;
end $function$;

-- ============================================================================
-- 4. STRIP DATA AND READINESS (read only)
-- ============================================================================
create or replace function public._w1g_freshness() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare st date := public._acct_start(); now_ timestamptz := now(); on_ boolean := public.rule_on('accounting_on'); sch boolean := public.rule_on('journal_sched_post_on');
        hrs numeric := public.rule_num('journal_stale_warn_hours'); last_at timestamptz; last_src text; pend int := 0; oldest date; wt int := 0; nerr int := 0; status text; stale boolean := false;
        sstate public.w1g_sched_state; bt jsonb;
begin
  if not (public.is_owner() or public._acct_view()) then raise exception 'not allowed'; end if;
  select e.created_at, e.source_type into last_at, last_src from public.journal_entries e where e.source_type not in ('manual', 'opening') order by e.id desc limit 1;
  select * into sstate from public.w1g_sched_state where id = 1;
  if st is not null then
    select count(*) filter (where d.waiting is null), min(d.entry_date) filter (where d.waiting is null), count(*) filter (where d.waiting is not null)
      into pend, oldest, wt from public._acct_docs(st) d;
    select count(*) into nerr from public.acct_post_errors72;
  end if;
  stale := hrs is not null and pend > 0 and (last_at is null or now_ - last_at > make_interval(hours => hrs::int));
  status := case when st is null then 'data_needed' when not on_ then 'off' when stale then 'stale' when pend > 0 then 'waiting' else 'fresh' end;
  select coalesce(jsonb_agg(jsonb_build_object('source_type', w.source_type, 'last_posted_at', w.last_posted_at, 'last_posted_date', w.last_posted_date, 'watermark_date', w.watermark_date,
      'pending_after', w.pending_after, 'capped_after', w.capped_after, 'locked_after', w.locked_after, 'errors_after', w.errors_after, 'oldest_pending', w.oldest_pending,
      'posted_total', w.posted_total, 'reversed_total', w.reversed_total) order by w.source_type), '[]'::jsonb) into bt from public.w1g_post_watermark w;
  return jsonb_build_object('status', status, 'now', now_, 'accounting_on', on_, 'start', st, 'sched_on', sch,
    'last_posted_at', last_at, 'last_posted_source', last_src, 'age_minutes', case when last_at is null then null else round(extract(epoch from (now_ - last_at)) / 60)::int end,
    'last_check_at', sstate.last_run_at, 'last_check_via', sstate.last_via, 'last_check_result', sstate.last_result,
    'pending', pend, 'oldest_pending', oldest, 'waiting', wt, 'errors', nerr, 'stale_after_hours', hrs, 'stale', stale, 'by_type', bt);
end $function$;

create or replace function public._w1g_acct_readiness() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare st date := public._acct_start(); on_ boolean := public.rule_on('accounting_on'); op boolean; mt int; mb int; mbl jsonb; pend int := 0; lck int := 0; wt int := 0; nerr int := 0; erl jsonb := '[]'::jsonb;
        checks jsonb := '[]'::jsonb; blockers jsonb := '[]'::jsonb;
begin
  if not (public.is_owner() or public._acct_view()) then raise exception 'not allowed'; end if;
  op := exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null
                  and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id));
  select count(*), count(*) filter (where a.id is null or not a.active or a.is_group) into mt, mb
    from public.acct_mappings m left join public.coa_accounts a on a.id = m.account_id;
  select coalesce(jsonb_agg(z.key order by z.key), '[]'::jsonb) into mbl
    from (select m.key from public.acct_mappings m left join public.coa_accounts a on a.id = m.account_id where a.id is null or not a.active or a.is_group order by m.key limit 20) z;
  if st is not null then
    with dd as materialized (select * from public._acct_docs(st)),
         e as (select x.* from public.acct_post_errors72 x where exists (select 1 from dd where dd.source_type = x.source_type and dd.source_id = x.source_id and dd.waiting is null))
    select (select count(*) from dd where dd.waiting is null),
           (select count(*) from dd where dd.waiting is null and public._acct_locked(case when dd.live then dd.entry_date else coalesce(dd.void_date, public._acct_today()) end)),
           (select count(*) from dd where dd.waiting is not null), (select count(*) from e),
           (select coalesce(jsonb_agg(jsonb_build_object('source_type', y.source_type, 'source_id', y.source_id, 'error', y.error, 'tries', y.tries) order by y.last_at desc), '[]'::jsonb)
              from (select * from e order by e.last_at desc limit 5) y)
      into pend, lck, wt, nerr, erl;
  end if;
  checks := jsonb_build_array(
    jsonb_build_object('key', 'start_date', 'ok', st is not null, 'text', 'Accounting start date is set'),
    jsonb_build_object('key', 'accounting_on', 'ok', on_, 'text', 'Accounting is switched on'),
    jsonb_build_object('key', 'opening', 'ok', op, 'text', 'An opening balance entry exists'),
    jsonb_build_object('key', 'mappings', 'ok', mt > 0 and mb = 0, 'text', 'Every account mapping points to an active, postable account'),
    jsonb_build_object('key', 'no_errors', 'ok', nerr = 0, 'text', 'No document failed to post'));
  select coalesce(jsonb_agg(c ->> 'key'), '[]'::jsonb) into blockers from jsonb_array_elements(checks) c where not (c ->> 'ok')::boolean;
  return jsonb_build_object('ready', jsonb_array_length(blockers) = 0, 'blockers', blockers, 'checks', checks, 'start', st, 'accounting_on', on_, 'opening', op,
    'mappings', mt, 'mappings_broken', mb, 'mappings_broken_keys', mbl, 'pending', pend, 'locked', lck, 'waiting', wt, 'errors', nerr, 'error_list', erl,
    'autopost_on_open', public.rule_on('accounting_autopost'), 'sched_on', public.rule_on('journal_sched_post_on'));
end $function$;

-- ============================================================================
-- 5. SWITCH-COUPLING WARNING (G30, G33)
-- ============================================================================
create or replace function public._w1g_coupled_keys() returns text[] language sql immutable as $$ select array['forms_post_to_ledger', 'journal_sched_post_on']::text[] $$;

-- the primary path path_cfg() would return if the legacy rule had this value (same row choice as path_cfg: the place row beats the all-places row)
create or replace function public._w1g_primary_if(p_domain text, p_loc integer, p_legacy_on boolean) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(x.primary_rule, case when d.legacy_rule is not null and p_legacy_on then 'b' else d.default_primary end)
    from public.path_domains d
    left join lateral (select s.* from public.path_switch s where s.domain = d.domain and s.location_id in (0, case when coalesce(p_loc, 0) > 0 then p_loc else 0 end)
                        order by s.location_id desc limit 1) x on true
   where d.domain = p_domain $$;

create or replace function public._w1g_switch_coupling_warning(p_key text, p_value jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare mode text := coalesce(public.rule_txt('switch_coupling_warning'), 'warn'); nowv boolean; newv boolean; dom record; loc int; pn text; pa text; places jsonb; acts jsonb := '[]'::jsonb;
        locks int := 0; unlocks int := 0; names text := ''; txt text; fix text; sev text := 'info'; dkey text; newp text; lr text; rd jsonb; showit boolean;
begin
  if not (public.is_owner() or public._acct_view()) then raise exception 'not allowed'; end if;
  showit := mode <> 'off';
  if p_key = 'forms_post_to_ledger' then
    nowv := public.rule_on(p_key);
    if p_value is null or jsonb_typeof(p_value) = 'null' then newv := not nowv;
    elsif jsonb_typeof(p_value) = 'boolean' then newv := (p_value #>> '{}')::boolean;
    else raise exception 'bad_value'; end if;
    for dom in select * from public.path_domains where legacy_rule = p_key order by sort, domain loop
      places := '[]'::jsonb;
      for loc in select distinct s.location_id from (select 0 as location_id union select location_id from public.path_switch where domain = dom.domain) s order by 1 loop
        pn := public._w1g_primary_if(dom.domain, loc, nowv); pa := public._w1g_primary_if(dom.domain, loc, newv);
        if pn is distinct from pa then
          places := places || jsonb_build_object('location_id', loc, 'from', pn, 'to', pa);
          if pa = 'b' then locks := locks + 1; else unlocks := unlocks + 1; end if;
        end if;
      end loop;
      if jsonb_array_length(places) > 0 then
        acts := acts || jsonb_build_object('domain', dom.domain, 'screen', dom.a_en, 'form', dom.b_en, 'places', places);
        names := names || case when names = '' then '' else '; ' end || dom.a_en || ' -> ' || dom.b_en;
      end if;
    end loop;
    if newv = nowv then
      txt := 'No change: the switch is already ' || case when nowv then 'ON' else 'OFF' end || '.';
    elsif newv and locks > 0 then
      sev := 'high';
      txt := 'Turning this ON makes the paper form the only record for: ' || names || '. From the moment it is saved the matching stock screens REFUSE new records ("path_locked") at ' || locks::text
        || ' place setting(s). Approved forms 04-1 (goods receipt) also start posting stock. Nothing already recorded changes.';
      fix := 'To keep a stock screen working, first set its owner switch on #/paths to "Screen" (path a): an explicit owner setting beats this switch. Turning the switch OFF again gives the screens back.';
    elsif newv then
      txt := 'Turning this ON lets approved stock forms (04-1, 04-2, 04-3, 03-1, 05-1) post to the stock ledger. Every place already has an explicit owner setting, so no stock screen is locked by it.';
    elsif locks = 0 and unlocks > 0 then
      txt := 'Turning this OFF gives the stock screens back as the record for: ' || names || '. The paper forms become references again. Nothing already recorded changes.';
    else
      txt := 'Turning this OFF stops stock forms from posting to the stock ledger. Nothing already recorded changes.';
    end if;
    return jsonb_build_object('key', p_key, 'known', true, 'mode', mode, 'show', showit and newv <> nowv, 'confirm', mode = 'confirm' and newv and not nowv,
      'on_now', nowv, 'new_value', newv, 'severity', sev, 'locks', locks, 'unlocks', unlocks, 'actions', acts, 'text', txt, 'fix', fix);
  elsif p_key like 'path:%' then
    dkey := substr(p_key, 6);
    select * into dom from public.path_domains where domain = dkey;
    if not found then raise exception 'unknown_domain'; end if;
    newp := p_value #>> '{}';
    if newp is null or newp not in ('a', 'b', 'first') then raise exception 'bad_value'; end if;
    lr := dom.legacy_rule;
    if newp = 'b' and lr is not null and not public.rule_on(lr) then
      sev := 'high';
      txt := 'Making the paper form the record for "' || dom.a_en || '" while the switch "' || lr || '" is OFF means NOTHING posts this action to the stock ledger: the screen is refused and the form does not post.';
      fix := 'Turn "' || lr || '" ON first, or keep the screen as the record (path a).';
    elsif newp = 'b' and lr is not null then
      txt := 'The paper form (' || dom.b_en || ') becomes the record for "' || dom.a_en || '". The stock screen will refuse new records here.';
    elsif newp = 'a' then
      txt := 'The screen (' || dom.a_en || ') stays the record. The paper form (' || dom.b_en || ') is kept as a reference and posts nothing twice.';
    else
      txt := 'Whichever path records first wins; the other becomes a locked shadow for that record.';
    end if;
    return jsonb_build_object('key', p_key, 'known', true, 'mode', mode, 'show', showit and sev = 'high', 'confirm', mode = 'confirm' and sev = 'high', 'severity', sev,
      'domain', dom.domain, 'new_value', newp, 'text', txt, 'fix', fix);
  elsif p_key = 'journal_sched_post_on' then
    nowv := public.rule_on(p_key);
    if p_value is null or jsonb_typeof(p_value) = 'null' then newv := not nowv;
    elsif jsonb_typeof(p_value) = 'boolean' then newv := (p_value #>> '{}')::boolean;
    else raise exception 'bad_value'; end if;
    rd := public._w1g_acct_readiness();
    if newv = nowv then txt := 'No change.';
    elsif newv then
      txt := 'Turning this ON lets the 30-minute notify job post every waiting sale, return, collection, purchase and expense to the books by itself, in batches, oldest first. They are posted by the same rules as Post now; a posted document is undone only by voiding the document.';
      if jsonb_array_length(rd -> 'blockers') > 0 then
        sev := 'high';
        txt := txt || ' It will do nothing until these are fixed: ' || (select string_agg(c ->> 'text', '; ') from jsonb_array_elements(rd -> 'checks') c where not (c ->> 'ok')::boolean) || '.';
      end if;
    else txt := 'Turning this OFF returns to today: the books fill only when someone presses Post now or opens Accounts.'; end if;
    return jsonb_build_object('key', p_key, 'known', true, 'mode', mode, 'show', showit and newv <> nowv, 'confirm', mode = 'confirm' and newv and not nowv, 'on_now', nowv, 'new_value', newv,
      'severity', sev, 'text', txt, 'readiness', rd);
  end if;
  return jsonb_build_object('key', p_key, 'known', false, 'show', false, 'confirm', false);
end $function$;

-- the owner confirms a warning; in confirm mode the trigger below needs one fresh, unused confirmation per switch-on (single use, valid for one hour)
create or replace function public._w1g_switch_coupling_ack(p_key text, p_value jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare w jsonb; sid text; id_ bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not (p_key = any(public._w1g_coupled_keys())) then raise exception 'unknown_key'; end if;
  w := public._w1g_switch_coupling_warning(p_key, p_value);
  insert into public.w1g_switch_acks (user_id, rule_key, new_value, note) values (auth.uid(), p_key, p_value, left(p_note, 300)) returning id into id_;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'switch_coupling_confirm', 'rules', p_key, jsonb_build_object('value', p_value, 'ack_id', id_, 'severity', w ->> 'severity', 'locks', w -> 'locks', 'text', left(w ->> 'text', 500), 'note', left(p_note, 300)));
  return w || jsonb_build_object('ack_id', id_);
end $function$;

create or replace function public._w1g_rules_coupling_guard() returns trigger
language plpgsql security definer set search_path = public as $function$
declare was boolean; will boolean; a public.w1g_switch_acks;
begin
  if not (new.key = any(public._w1g_coupled_keys())) then return new; end if;
  if coalesce(public.rule_txt('switch_coupling_warning'), 'warn') <> 'confirm' then return new; end if;
  was := coalesce((old.value #>> '{}')::boolean, (old.default_value #>> '{}')::boolean, false);
  will := coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false);
  if not will or was then return new; end if;                      -- only turning ON needs a confirmation; turning OFF restores the old behaviour
  select * into a from public.w1g_switch_acks x
   where x.rule_key = new.key and x.user_id = auth.uid() and x.used_at is null and x.at > now() - interval '1 hour' and coalesce((x.new_value #>> '{}')::boolean, true)
   order by x.id desc limit 1 for update;
  if not found then raise exception 'coupling_confirm_needed: read the warning (_w1g_switch_coupling_warning) and confirm it (_w1g_switch_coupling_ack) before turning % on', new.key; end if;
  update public.w1g_switch_acks set used_at = now() where id = a.id;
  return new;
end $function$;
drop trigger if exists rules_coupling_guard98 on public.rules;
create trigger rules_coupling_guard98 before update of value on public.rules for each row when (old.value is distinct from new.value) execute function public._w1g_rules_coupling_guard();

-- ============================================================================
-- 6. U-12: what the backup tool may read (the backup bot, the notify bot or the owner)
-- ============================================================================
create or replace function public._w1g_backup_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
begin
  if not (public._is_ops('backup') or public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  return jsonb_build_object('encrypt_on', public.rule_on('backup_encrypt_on'), 'retention_days', public.rule_num('backup_retention_days'));
end $function$;

-- ============================================================================
-- 7. PRIVILEGES: internals closed to browsers, API open to signed-in users (each function checks its own permission)
-- ============================================================================
revoke all on function public._w1g_present(), public._w1g_bump(jsonb, text, text), public._w1g_oldest(jsonb, text, date), public._w1g_coupled_keys(),
  public._w1g_primary_if(text, integer, boolean), public._w1g_rules_coupling_guard() from public, anon, authenticated;
revoke all on function public._w1g_post_scheduled(boolean), public._w1g_freshness(), public._w1g_acct_readiness(), public._w1g_switch_coupling_warning(text, jsonb),
  public._w1g_switch_coupling_ack(text, jsonb, text), public._w1g_backup_settings() from public, anon, authenticated;
grant execute on function public._w1g_post_scheduled(boolean), public._w1g_freshness(), public._w1g_acct_readiness(), public._w1g_switch_coupling_warning(text, jsonb),
  public._w1g_switch_coupling_ack(text, jsonb, text), public._w1g_backup_settings() to authenticated;
