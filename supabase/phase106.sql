-- ============================================================
-- Phase 106 - Backup / restore-drill coverage for everything added in phases 72..103 (audit: docs/backend/BACKUP_COVERAGE.md)
-- Run AFTER phase103 (and phase102 if used). Additive and idempotent (paste twice = no error). Nothing is deleted. Independent of phase104 / 105.
--   * The backup list is COMPUTED at call time (public._backup_tables(), phase46 / phase70), so all new tables of phases 72..103 are already
--     included automatically, EXCEPT where the blunt column-name filter hides a table that holds no secret:
--       perm_conflict (phase91) has the columns token_a / token_b = permission tokens ("purchase_entry" + "supplier_pay" must not be held together),
--       not credentials. It is owner-edited segregation-of-duties data and was silently left out of every backup.
--   * bos106: public._backup_tables() re-created from its LATEST body (phase70) with ONE change: columns token_a / token_b no longer count as secret
--     (same pattern phase70 used for tokens_in / tokens_out). Everything else is identical: *_secret*, ops_*, login_*, backup_runs, notifications,
--     notification_reads and every table with a password / pin_hash / secret / token / salt / api_key / private_key column stay out
--     (telegram_secrets, intake_proofs94, attendance_devices: on purpose, hashes of secrets are set again after a restore).
--   * public.backup_coverage106()  owner only, read only: every public table, whether it is in the backup, its row count and, when it is out, the reason.
--     The restore drill (docs/RESTORE_DRILL.md) compares this with the manifest; tools/restore_drill.py reports it as optional.
--   * Storage objects (Supabase bucket "photos": item / receipt / staff pictures and scan photos SCAN/...) are NOT in any SQL dump: see docs/backend/BACKUP_COVERAGE.md.
-- ============================================================

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.opening_stock_followups103') is null then miss := miss || ' 103'; end if;
  if to_regprocedure('public._backup_tables()') is null then miss := miss || ' 46'; end if;
  if miss <> '' then
    raise exception 'phase106 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- bos106: identical to phase70 except token_a / token_b (permission tokens of perm_conflict) are not secret-looking
create or replace function public._backup_tables() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}'::text[])
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relispartition
     and c.relname::text not like '%\_secret%' escape '\'
     and c.relname::text not like 'ops\_%' escape '\'
     and c.relname::text not in ('login_failures', 'login_attempts', 'login_throttle', 'backup_runs', 'notifications', 'notification_reads')
     and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                      and a.attname::text !~ '^(tokens_(in|out)|token_[ab])$'
                      and a.attname::text ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)');
$$;
comment on function public._backup_tables() is 'bos106: backup / restore-drill table list (computed). token_a/token_b (perm_conflict) are not secrets.';

-- owner-only coverage report: which public tables are in the backup, which are not and why (read only)
create or replace function public.backup_coverage106() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare bk text[] := public._backup_tables(); r record; n bigint; arr jsonb := '[]'::jsonb; why text; bad text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  for r in select c.oid, c.relname::text t from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and not c.relispartition order by c.relname loop
    execute format('select count(*) from public.%I', r.t) into n;
    why := null;
    if not (r.t = any (bk)) then
      select string_agg(a.attname::text, ',' order by a.attnum) into bad from pg_attribute a
       where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped and a.attname::text !~ '^(tokens_(in|out)|token_[ab])$'
         and a.attname::text ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)';
      why := case when r.t like '%\_secret%' then 'name contains _secret'
                  when r.t like 'ops\_%' then 'ops_* bot account'
                  when r.t in ('login_failures', 'login_attempts', 'login_throttle') then 'login throttle data (re-created by use)'
                  when r.t in ('backup_runs', 'notifications', 'notification_reads') then 'run-time table (re-created by the app)'
                  when bad is not null then 'secret-looking column(s): ' || bad
                  else 'excluded' end;
    end if;
    arr := arr || jsonb_build_object('table', r.t, 'in_backup', r.t = any (bk), 'rows', n, 'reason', why);
  end loop;
  return jsonb_build_object('tables', jsonb_array_length(arr), 'in_backup', coalesce(array_length(bk, 1), 0), 'rows_in_backup',
           coalesce((select sum((x ->> 'rows')::bigint) from jsonb_array_elements(arr) x where (x ->> 'in_backup')::boolean), 0), 'list', arr);
end $$;

do $$ declare r regprocedure; begin
  for r in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_backup_tables', 'backup_coverage106') loop
    execute format('revoke all on function %s from public, anon, authenticated', r);
    if r::text like 'backup_coverage106%' then execute format('grant execute on function %s to authenticated', r); end if;
  end loop;
end $$;
notify pgrst, 'reload schema';
