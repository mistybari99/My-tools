-- Phase 543 - printed form codes: the clean sequence (owner decision, 21 Oct 2026, final)
-- Tag: FORM-CODE-CLEAN-SEQUENCE-543
--
-- What it does: the 41 printed forms get the code NN-1, NN = position when the forms are sorted A-Z by their
-- English short name (docs/FORM_SEQUENCE.md, section 4). 0-1 (Location Settings) keeps its code.
-- The old code of every moved form is RETIRED: it must not be read as the form it used to name.
--
-- Changes, in one transaction (a failed step rolls everything back):
--   1. forms.code and forms.sort (the 41 printed forms; 0-1 untouched)
--   2. form_code in the 20 tables that store a form code (entries, serials, role_form_perms, ...)
--   3. code literals in the stored functions (CREATE OR REPLACE with the same signature), in the trigger
--      conditions, in the check constraint on sale_form_links, in one row policy (quick_expenses_sel)
--   4. label text that names a form code: rules, path_domains, report_defs3, list_defs, money_event_settings,
--      acct_mappings, setup_rec_defs81 (listed in the function below)
-- NOT changed: audit_log and _union_fn_backup (history); the non-printed codes POS, ITEMS, ITEM_COST, ONLINE_INTAKE;
--   free text typed by people (entries.data, notes): the phase prints a count of rows that still name an old code, so the owner can decide.
-- A row with a printed code the map does not know stops the phase before anything changes (the list is in the message).
--
-- Paste AFTER phase539 (the last phase in docs/PASTE_ORDER.md). Paste-twice safe: a second paste finds
-- public.form_code_migration_543 and changes nothing. Do NOT paste any earlier phase file again after this one:
-- an old phase file carries the old codes (see docs/FORM_SEQUENCE.md, section 3).
-- Live project: the owner pastes this file himself (CLAUDE.md, Database safety). Take a backup first.
-- Check at the end:  select * from public._i2_state() where not present;  -> must print no rows.

begin;

-- the mapping (single source: docs/FORM_SEQUENCE.md section 4 and tools/numbering_map.json)
create or replace function public._f543_pairs() returns table(old_code text, new_code text, sort_no int, name_en text)
language sql immutable as $$
  select * from (values
    ('02-4','01-1',1,'Appointment Letter — Terms & Duties'),
    ('06-4','02-1',2,'Bill Check & Payment Request'),
    ('10-1','03-1',3,'Cash Handover Slip'),
    ('10-4','04-1',4,'Cash Position & Purchase Budget'),
    ('20-1','05-1',5,'Customer Order Form'),
    ('14-1','06-1',6,'Daily Showroom Sheet'),
    ('10-3','07-1',7,'Digital Payment Reconciliation Register'),
    ('20-2','08-1',8,'Discount Approval Slip'),
    ('02-7','09-1',9,'Duty & Backup Card'),
    ('02-6','10-1',10,'Exit Clearance Form'),
    ('10-2','11-1',11,'Expense Voucher'),
    ('05-1','12-1',12,'Factory Daily Sheet'),
    ('04-1','13-1',13,'Goods Received Note (GRN)'),
    ('14-2','14-1',14,'Jalebi Counter Daily Record'),
    ('02-5','15-1',15,'Leave Application'),
    ('08-1','16-1',16,'Maintenance Request & Record'),
    ('18-1','17-1',17,'Marketing Expense Register'),
    ('04-2','18-1',18,'Material Issue Slip'),
    ('02-1','19-1',19,'Monthly Attendance Register'),
    ('01-2','20-1',20,'Monthly P&L and KPI Sheet'),
    ('02-2','21-1',21,'Monthly Salary Sheet'),
    ('05-5','22-1',22,'New Product Decision Sheet'),
    ('20-6','23-1',23,'Online & Delivery Ledger'),
    ('20-4','24-1',24,'Party & Wholesale Invoice'),
    ('20-5','25-1',25,'Party & Wholesale Ledger'),
    ('05-2','26-1',26,'Product Spec Card'),
    ('06-3','27-1',27,'Purchase Order (PO)'),
    ('06-1','28-1',28,'Purchase Requisition (PR)'),
    ('06-2','29-1',29,'Comparative Statement (CS)'),
    ('10-5','30-1',30,'Receivable & Advance Reconciliation'),
    ('05-3','31-1',31,'Recipe Card'),
    ('20-3','32-1',32,'Return & Complaint Register'),
    ('11-1','33-1',33,'Shift Handover Register'),
    ('02-8','34-1',34,'Skill Checklist'),
    ('02-3','35-1',35,'Staff Advance Register'),
    ('04-3','36-1',36,'Stock Count Sheet'),
    ('04-4','37-1',37,'Store Ledger'),
    ('06-5','38-1',38,'Supplier Ledger'),
    ('03-1','39-1',39,'Transfer Challan (IBT)'),
    ('01-1','40-1',40,'Weekly Review Note'),
    ('05-4','41-1',41,'Yield Test Sheet')
  ) as v(old_code, new_code, sort_no, name_en)
$$;

-- one-pass remap of the printed codes in a text: every code is replaced by a placeholder first, then the placeholders
-- are replaced by the new codes, so 02-4 -> 01-1 never continues to 40-1.
create or replace function public._f543_remap(t text) returns text
language plpgsql set search_path = public as $f$
declare p record; s text := t;
begin
  if t is null or t !~ '(?<![0-9A-Za-z_.:/-])[0-9][0-9]-[0-9](?![0-9A-Za-z_.:/-])' then return t; end if;
  for p in select old_code, row_number() over (order by old_code) as k from public._f543_pairs() loop
    s := regexp_replace(s, '(?<![0-9A-Za-z_.:/-])' || p.old_code || '(?![0-9A-Za-z_.:/-])', chr(1) || p.k || chr(2), 'g');
  end loop;
  for p in select new_code, row_number() over (order by old_code) as k from public._f543_pairs() loop
    s := replace(s, chr(1) || p.k || chr(2), p.new_code);
  end loop;
  return s;
end $f$;

create or replace function public._f543_run() returns text
language plpgsql set search_path = public as $run$
declare
  tbls text[] := array['blind_count_cfg', 'comparison_days', 'comparison_pairs', 'corrections', 'entries', 'entry_count_seals',
    'entry_ledger_posts', 'exceptions', 'form_rollout', 'forms_ledger_cfg', 'list_other_entries', 'paper_books', 'parallel_months',
    'pin_sig_cfg', 'print_notes', 'role_form_overrides133', 'role_form_perms', 'sale_form_links', 'serials', 'shortage_cash_cases'];
  re text := '(?<![0-9A-Za-z_.:/-])[0-9][0-9]-[0-9](?![0-9A-Za-z_.:/-])';
  r record; r2 record; n int; bad text; kind text;
  n_forms int := 0; n_rows int := 0; n_labels int := 0; n_funcs int := 0; n_trg int := 0; n_pol int := 0; n_chk int := 0;
begin
  if to_regclass('public.form_code_migration_543') is not null then
    raise notice 'phase543: already applied (public.form_code_migration_543); nothing changed';
    return 'already applied';
  end if;

  -- 0. the map must match the database: every old code is a form, every printed form is in the map
  select string_agg(p.old_code, ' ') into bad from public._f543_pairs() p
    where not exists (select 1 from public.forms f where f.code = p.old_code);
  if bad is not null then raise exception 'phase543 refused: map codes that are not forms in this database: %', bad; end if;
  select string_agg(f.code, ' ') into bad from public.forms f
    where f.code ~ '^[0-9][0-9]-[0-9]$' and f.code not in (select old_code from public._f543_pairs());
  if bad is not null then raise exception 'phase543 refused: printed codes that the map does not know: %', bad; end if;

  create temp table if not exists _f543_lbl (tbl text, col text);
  delete from _f543_lbl;
  insert into _f543_lbl values ('rules', 'label_bn'), ('rules', 'label_en'), ('rules', 'label_mix'), ('rules', 'hint_bn'),
    ('rules', 'hint_en'), ('rules', 'hint_mix'), ('acct_mappings', 'label_en'), ('path_domains', 'b_bn'), ('path_domains', 'b_en'),
    ('path_domains', 'note_bn'), ('path_domains', 'note_en'), ('report_defs3', 'name_mix'), ('report_defs3', 'cols'),
    ('list_defs', 'note'), ('money_event_settings', 'label_en'), ('setup_rec_defs81', 'reason_bn'), ('setup_rec_defs81', 'reason_en'),
    ('setup_rec_defs81', 'reason_mix');

  -- 1. pre-flight: rows that carry a printed code the map does not know (listed, nothing changed)
  create temp table if not exists _f543_bad (tbl text, code text, cnt bigint);
  delete from _f543_bad;
  foreach kind in array tbls loop
    execute format('insert into _f543_bad select %L, form_code, count(*) from public.%I where form_code ~ %L and form_code not in (select old_code from public._f543_pairs()) group by form_code',
      kind, kind, '^[0-9][0-9]-[0-9]$');
  end loop;
  select string_agg(b.tbl || '.' || b.code || ' x' || b.cnt, '; ') into bad from _f543_bad b;
  if bad is not null then raise exception 'phase543 refused: rows with a printed code the map does not know: %', bad; end if;
  raise notice 'phase543 pre-flight: every form_code row maps (or is a non-printed code); the map matches the database';

  -- 1b. what will NOT change, counted before any change (free text, history): listed in the notices
  for r in select table_name as tbl, column_name as col, data_type as dt from information_schema.columns
    where table_schema = 'public' and data_type in ('text', 'jsonb', 'character varying')
      and table_name not in ('audit_log', '_union_fn_backup') and column_name not in ('form_code', 'code')
      and not exists (select 1 from _f543_lbl l where l.tbl = table_name and l.col = column_name) loop
    if r.dt = 'jsonb' then
      execute format('select count(*) from public.%I where %I::text ~ %L and public._f543_remap(%I::text) <> %I::text', r.tbl, r.col, re, r.col, r.col) into n;
    else
      execute format('select count(*) from public.%I where %I ~ %L and public._f543_remap(%I) <> %I', r.tbl, r.col, re, r.col, r.col) into n;
    end if;
    if n > 0 then raise notice 'phase543 NOT changed (review by hand): %.% has % row(s) with an old code', r.tbl, r.col, n; end if;
  end loop;

  -- 2. remember the enabled user triggers of the tables we touch, then switch them off for this transaction
  create temp table if not exists _f543_trg (rel text, tgname name);
  delete from _f543_trg;
  insert into _f543_trg select c.oid::regclass::text, t.tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where c.relnamespace = 'public'::regnamespace and not t.tgisinternal and t.tgenabled <> 'D'
      and (c.relname = 'forms' or c.relname = any(tbls));
  for r in select distinct rel from _f543_trg loop execute format('alter table %s disable trigger user', r.rel); end loop;

  -- 3. drop the foreign keys to forms(code) and the check constraints that name a code (re-added below)
  create temp table if not exists _f543_fk (rel text, name name, def text);
  delete from _f543_fk;
  insert into _f543_fk select c.oid::regclass::text, k.conname, pg_get_constraintdef(k.oid) from pg_constraint k join pg_class c on c.oid = k.conrelid
    where k.contype = 'f' and k.confrelid = 'public.forms'::regclass;
  create temp table if not exists _f543_chk (rel text, name name, def text);
  delete from _f543_chk;
  insert into _f543_chk select c.oid::regclass::text, k.conname, pg_get_constraintdef(k.oid) from pg_constraint k join pg_class c on c.oid = k.conrelid
    where k.contype = 'c' and k.connamespace = 'public'::regnamespace and pg_get_constraintdef(k.oid) ~ re;
  for r in select * from _f543_fk loop execute format('alter table %s drop constraint %I', r.rel, r.name); end loop;
  for r in select * from _f543_chk loop execute format('alter table %s drop constraint %I', r.rel, r.name); end loop;

  -- 4. forms: two steps (temporary code first) so that no two rows ever share a code
  update public.forms set code = '~543~' || code where code in (select old_code from public._f543_pairs());
  get diagnostics n_forms = row_count;
  update public.forms f set code = p.new_code, sort = p.sort_no from public._f543_pairs() p where f.code = '~543~' || p.old_code;

  -- 5. form_code in the 20 tables, two steps each
  foreach kind in array tbls loop
    execute format('update public.%I set form_code = %L || form_code where form_code in (select old_code from public._f543_pairs())', kind, '~543~');
    get diagnostics n = row_count;
    n_rows := n_rows + n;
    execute format('update public.%I t set form_code = p.new_code from public._f543_pairs() p where t.form_code = %L || p.old_code', kind, '~543~');
  end loop;

  -- 6. label text that names a code
  for r in select tbl, col from _f543_lbl loop
    select data_type into kind from information_schema.columns where table_schema = 'public' and table_name = r.tbl and column_name = r.col;
    if kind is null then raise notice 'phase543: %.% not found, skipped', r.tbl, r.col; continue; end if;
    if kind = 'jsonb' then
      execute format('update public.%I set %I = public._f543_remap(%I::text)::jsonb where public._f543_remap(%I::text) <> %I::text', r.tbl, r.col, r.col, r.col, r.col);
    else
      execute format('update public.%I set %I = public._f543_remap(%I) where public._f543_remap(%I) <> %I', r.tbl, r.col, r.col, r.col, r.col);
    end if;
    get diagnostics n = row_count;
    n_labels := n_labels + n;
  end loop;

  -- 7. re-add the foreign keys (checked now) and the check constraints with the new codes
  for r in select * from _f543_fk loop execute format('alter table %s add constraint %I %s', r.rel, r.name, r.def); end loop;
  for r in select * from _f543_chk loop
    execute format('alter table %s add constraint %I %s', r.rel, r.name, public._f543_remap(r.def)); n_chk := n_chk + 1;
  end loop;

  -- 8. row policies that name a code
  for r in select schemaname, tablename, policyname, qual, with_check from pg_policies
    where schemaname = 'public' and (qual ~ re or with_check ~ re) loop
    if r.qual is not null then
      execute format('alter policy %I on public.%I using (%s)', r.policyname, r.tablename, public._f543_remap(r.qual));
    end if;
    if r.with_check is not null then
      execute format('alter policy %I on public.%I with check (%s)', r.policyname, r.tablename, public._f543_remap(r.with_check));
    end if;
    n_pol := n_pol + 1;
  end loop;

  -- 9. stored functions: the same function, the code literals in its text changed (signature and grants stay)
  for r in select p.oid, pg_get_functiondef(p.oid) as def from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and left(p.proname, 5) <> '_f543' loop
    if r.def ~ re and public._f543_remap(r.def) <> r.def then
      execute public._f543_remap(r.def);
      n_funcs := n_funcs + 1;
    end if;
  end loop;

  -- 10. triggers whose condition names a code (dropped and created again with the same definition)
  for r in select c.oid::regclass::text as rel, t.tgname, pg_get_triggerdef(t.oid) as def from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where c.relnamespace = 'public'::regnamespace and not t.tgisinternal loop
    if r.def ~ re and public._f543_remap(r.def) <> r.def then
      execute format('drop trigger %I on %s', r.tgname, r.rel);
      execute public._f543_remap(r.def);
      n_trg := n_trg + 1;
    end if;
  end loop;

  -- 11. switch the triggers back on, as they were (only those that were on)
  for r in select * from _f543_trg loop
    if exists (select 1 from pg_trigger t where t.tgname = r.tgname and t.tgrelid = r.rel::regclass) then
      execute format('alter table %s enable trigger %I', r.rel, r.tgname);
    end if;
  end loop;

  -- 13. the applied marker (ends the phase, and the second paste is a no-op)
  create table if not exists public.form_code_migration_543 (
    tag text primary key default 'FORM-CODE-CLEAN-SEQUENCE-543', applied_at timestamptz not null default now(),
    forms_changed int, form_rows_changed int, label_rows_changed int, functions_changed int, triggers_changed int,
    policies_changed int, checks_changed int);
  alter table public.form_code_migration_543 enable row level security;
  revoke all on public.form_code_migration_543 from anon, authenticated;
  insert into public.form_code_migration_543 (forms_changed, form_rows_changed, label_rows_changed, functions_changed, triggers_changed, policies_changed, checks_changed)
    values (n_forms, n_rows, n_labels, n_funcs, n_trg, n_pol, n_chk);

  drop table if exists _f543_bad, _f543_trg, _f543_fk, _f543_chk, _f543_lbl;
  drop function if exists public._f543_remap(text);
  drop function if exists public._f543_pairs();
  return format('phase543 applied: forms %s, form_code rows %s, label rows %s, functions %s, triggers %s, policies %s, checks %s',
    n_forms, n_rows, n_labels, n_funcs, n_trg, n_pol, n_chk);
end $run$;

select public._f543_run();
drop function if exists public._f543_run();
drop function if exists public._f543_remap(text);
drop function if exists public._f543_pairs();

commit;
