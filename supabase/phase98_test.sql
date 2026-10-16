-- FRESH DB ONLY. Phase 98 tests (W1-G: scheduled journal posting, freshness strip data, readiness, switch-coupling warning, backup settings).
--   ORDER="phase8 ... phase87 phase98" (build_fresh_db.sh / /tmp/w1g/mk.sh), then
--   psql -h /tmp -p 5567 -U postgres -d <db> -qAt -f supabase/phase98_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000009801'
\set u_acc '00000000-0000-0000-0000-000000009802'
\set u_v '00000000-0000-0000-0000-000000009803'
\set u_s '00000000-0000-0000-0000-000000009804'
\set u_b '00000000-0000-0000-0000-000000009805'
\set u_bb '00000000-0000-0000-0000-000000009806'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.q(p_sql text) returns text language plpgsql security definer as $$
declare r text; begin execute p_sql into r; return r; end $$;       -- run a read as the table owner (the state tables are closed to browser roles)
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.unbalanced() returns bigint language sql security definer as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.je() returns bigint language sql security definer as $$ select count(*) from public.journal_entries $$;
create or replace function tt.n(p_type text) returns bigint language sql security definer as $$ select count(*) from public.journal_entries where source_type = p_type and reverses_id is null $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner98@s.app','{"full_name":"test_owner98"}'), (:'u_acc','test_acct98@s.app','{"full_name":"test_acct98"}'), (:'u_v','test_viewer98@s.app','{"full_name":"test_viewer98"}'),
 (:'u_s','test_staff98@s.app','{"full_name":"test_staff98"}'), (:'u_b','test_botn98@s.app','{"full_name":"test_botn98"}'), (:'u_bb','test_botb98@s.app','{"full_name":"test_botb98"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_acc', :'u_v', :'u_s');          -- the two bots stay unapproved on purpose (docs/OPS_SETUP.md: never approve the bot)
insert into user_roles values (:'u_o','owner'),(:'u_acc','management'),(:'u_v','management'),(:'u_s','salesperson') on conflict do nothing;
insert into user_locations values (:'u_acc',1),(:'u_acc',2),(:'u_v',1),(:'u_s',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_acc','accounts_manage',null),(:'u_acc','accounts_view',null),(:'u_v','accounts_view',null);
insert into ops_accounts (user_id, purpose) values (:'u_b','notify'), (:'u_bb','backup') on conflict do nothing;
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset

\echo == T0 shape, safe defaults, nothing shared patched, internals closed
select tt.chk('T0 phase98 present', to_regprocedure('public._w1g_present()') is not null);
select tt.chk('T0 eight new rules, English text, safe defaults (sched OFF, cap 1500, types/lookback/stale blank, warning=warn, encrypt OFF, retention blank)',
  (select count(*) from rules where key in ('journal_sched_post_on','journal_sched_post_cap','journal_sched_post_types','journal_sched_post_lookback_days','journal_stale_warn_hours','switch_coupling_warning','backup_encrypt_on','backup_retention_days'))=8
  and not rule_on('journal_sched_post_on') and rule_num('journal_sched_post_cap')=1500 and rule_txt('journal_sched_post_types') is null and rule_num('journal_sched_post_lookback_days') is null
  and rule_num('journal_stale_warn_hours') is null and rule_txt('switch_coupling_warning')='warn' and not rule_on('backup_encrypt_on') and rule_num('backup_retention_days') is null
  and not exists (select 1 from rules where key in ('journal_sched_post_on','journal_sched_post_cap','journal_sched_post_types','journal_sched_post_lookback_days','journal_stale_warn_hours','switch_coupling_warning','backup_encrypt_on','backup_retention_days')
                   and (label_en is null or label_en ~ '[^\x01-\x7f]' or hint_en ~ '[^\x01-\x7f]' or label_bn is distinct from label_en)));
select tt.chk('T0 no shared function was patched or re-created (no w1g/bos98 text inside the integrator-owned functions)',
  (select count(*) from (values ('public.acct_post_pending(boolean,int)'),('public._acct_docs(date)'),('public.notify_scan()'),('public.lock_check(date)'),('public._p27_pl(date,date,int[])')) v(f)
     where to_regprocedure(v.f) is not null and (position('w1g' in pg_get_functiondef(v.f::regprocedure))>0 or position('bos98' in pg_get_functiondef(v.f::regprocedure))>0))=0);
select tt.chk('T0 state tables: RLS on, closed to browser roles, no delete',
  (select bool_and(relrowsecurity) from pg_class where relname in ('w1g_post_watermark','w1g_sched_state','w1g_post_runs','w1g_switch_acks'))
  and not has_table_privilege('authenticated','public.w1g_post_runs','select') and not has_table_privilege('anon','public.w1g_post_watermark','select') and not has_table_privilege('authenticated','public.w1g_switch_acks','insert'));
select tt.chk('T0 API open to signed-in users only; helpers closed',
  has_function_privilege('authenticated','public._w1g_post_scheduled(boolean)','execute') and not has_function_privilege('anon','public._w1g_post_scheduled(boolean)','execute')
  and not has_function_privilege('anon','public._w1g_freshness()','execute') and not has_function_privilege('authenticated','public._w1g_bump(jsonb,text,text)','execute')
  and not has_function_privilege('authenticated','public._w1g_rules_coupling_guard()','execute') and not has_function_privilege('authenticated','public._w1g_primary_if(text,integer,boolean)','execute'));

select tt.as(:'u_o');
select acct_set_start(:'pm'::date) is not null as ast \gset
select set_rule('accounting_on','true') is null as on1 \gset
select acct_journal_post(:'pm'::date, 1, 'test opening', '[{"code":"1110","debit":900000},{"code":"1120","debit":300000},{"code":"3100","credit":1200000}]'::jsonb) is not null as s3 \gset
-- documents waiting to be posted: 3 sales (3 days ago, yesterday, today) and 2 quick expenses (today)
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values
 (1, 980001, tt.today() - 3, now() - interval '3 days', '[]', 800, 0, 800, 'cash', 'done', :'u_o'),
 (1, 980002, tt.today() - 1, now() - interval '1 day', '[]', 500, 0, 500, 'cash', 'done', :'u_o'),
 (1, 980003, tt.today(), now(), '[]', 1000, 0, 1000, 'cash', 'done', :'u_o');
insert into sale_payments (sale_id, location_id, kind, mode, amount, paid_at, created_by)
 select s.id, s.location_id, 'sale', 'cash', s.total, s.sold_at, :'u_o' from sales s where s.receipt in (980001, 980002, 980003);
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 300, 'cash', false, null, gen_random_uuid()) is not null as q1 \gset
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 120, 'cash', false, null, gen_random_uuid()) is not null as q2 \gset
select tt.je() as je0 \gset

\echo == T1 OFF by default: nothing posts, dry run shows what would post, permissions
set role authenticated; select tt.as(:'u_b');
select tt.chk('T1 the bot is not an approved user (realistic), yet is an ops notify bot', not is_active() and _is_ops('notify'));
select (_w1g_post_scheduled(false)) ->> 'skipped' as r1 \gset
select tt.chk('T1 switch OFF: a real run is skipped (switch_off) and posts nothing', :'r1' = 'switch_off' and tt.je() = :je0 and tt.q('select count(*) from w1g_post_runs') = '0');
select (_w1g_post_scheduled(true)) as d1 \gset
select tt.chk('T1 a dry run works while OFF: 5 documents (3 sales + 2 quick expenses), writes nothing',
  (:'d1'::jsonb ->> 'posted')::int = 5 and (:'d1'::jsonb) ->> 'dry' = 'true' and (:'d1'::jsonb #>> '{by_type,sale,posted}') = '3' and (:'d1'::jsonb #>> '{by_type,quick_expense,posted}') = '2' and tt.je() = :je0
  and tt.q('select count(*) from w1g_post_watermark') = '0' and tt.q('select count(*) from w1g_post_runs') = '0' and tt.q('select count(*) from w1g_sched_state') = '0');
select tt.err('T1 the unapproved backup bot may not run it', format($q$select tt.as(%L); select _w1g_post_scheduled(true)$q$, :'u_bb'), 'not allowed');
select tt.as(:'u_s');
select tt.err('T1 a salesperson is refused (server side)', $q$select _w1g_post_scheduled(true)$q$, 'not allowed');
select tt.as(:'u_v');
select tt.err('T1 an accounts viewer may not post', $q$select _w1g_post_scheduled(true)$q$, 'not allowed');
select tt.as(:'u_acc');
select tt.chk('T1 an accounts manager may run a dry run', (_w1g_post_scheduled(true) ->> 'posted')::int = 5);
select tt.as('');
select tt.err('T1 a session with no login at all is refused', $q$select _w1g_post_scheduled(true)$q$, 'not allowed');
reset role;
select tt.chk('T1 the database scheduler (no login, role none, as postgres) is allowed to dry-run', (_w1g_post_scheduled(true) ->> 'via') = 'database_scheduler');
set role anon;
select tt.err('T1 anon cannot execute', $q$select _w1g_post_scheduled(true)$q$, 'permission denied');
reset role;

\echo == T2 freshness and readiness before any posting
set role authenticated; select tt.as(:'u_v');
select _w1g_freshness() as f0 \gset
select tt.chk('T2 strip data (viewer): status waiting, 5 pending, nothing posted yet, switch off', (:'f0'::jsonb ->> 'status') = 'waiting' and (:'f0'::jsonb ->> 'pending')::int = 5 and (:'f0'::jsonb ->> 'last_posted_at') is null
  and (:'f0'::jsonb ->> 'sched_on') = 'false' and (:'f0'::jsonb ->> 'accounting_on') = 'true' and (:'f0'::jsonb ->> 'age_minutes') is null);
select tt.as(:'u_s');
select tt.err('T2 a salesperson cannot read the strip data', $q$select _w1g_freshness()$q$, 'not allowed');
select tt.err('T2 a salesperson cannot read readiness', $q$select _w1g_acct_readiness()$q$, 'not allowed');
select tt.as(:'u_v');
select _w1g_acct_readiness() as r0 \gset
select tt.chk('T2 readiness: start set, accounting on, NO opening entry yet, mappings fine, 5 waiting, no errors; blockers = [opening]; not ready',
  (:'r0'::jsonb ->> 'ready') = 'false' and (:'r0'::jsonb -> 'blockers') = '["opening"]'::jsonb and (:'r0'::jsonb ->> 'pending')::int = 5 and (:'r0'::jsonb ->> 'mappings_broken') = '0'
  and (:'r0'::jsonb ->> 'errors') = '0' and (:'r0'::jsonb ->> 'start') = :'pm' and (:'r0'::jsonb ->> 'autopost_on_open') = 'true');
reset role;
select tt.as(:'u_o');
update rules set value = '1'::jsonb where key = 'journal_stale_warn_hours';
set role authenticated; select tt.as(:'u_v');
select tt.chk('T2 stale warning: waiting documents and nothing ever posted, 1 hour set -> status stale', (_w1g_freshness() ->> 'status') = 'stale' and (_w1g_freshness() ->> 'stale') = 'true');
reset role;
update rules set value = null where key = 'journal_stale_warn_hours';
set role authenticated; select tt.as(:'u_v');
select tt.chk('T2 stale threshold blank again: status waiting (never red by itself)', (_w1g_freshness() ->> 'status') = 'waiting');
reset role;

\echo == T3 scheduled posting, cap and rotation (cap 1: five documents need five runs)
select tt.as(:'u_o');
select set_rule('journal_sched_post_on','true') is null as son \gset
select set_rule('journal_sched_post_cap','1') is null as scap \gset
set role authenticated; select tt.as(:'u_b');
select _w1g_post_scheduled(false) as c1 \gset
select tt.chk('T3 run 1 (cap 1): one document posted, cap hit, 4 left; the first type in turn is quick_expense', (:'c1'::jsonb ->> 'posted')::int = 1 and (:'c1'::jsonb ->> 'capped') = 'true' and (:'c1'::jsonb ->> 'left')::int = 4
  and (:'c1'::jsonb #>> '{by_type,quick_expense,posted}') = '1' and tt.n('quick_expense') = 1 and tt.n('sale') = 0 and (:'c1'::jsonb ->> 'via') = 'notify_bot');
select tt.chk('T3 watermark after run 1: quick_expense 1 left; sale 3 left, oldest waiting = 3 days ago, watermark = 4 days ago',
  tt.q($z$select pending_after from w1g_post_watermark where source_type='quick_expense'$z$) = '1' and tt.q($z$select pending_after from w1g_post_watermark where source_type='sale'$z$) = '3'
  and tt.q($z$select oldest_pending from w1g_post_watermark where source_type='sale'$z$) = (tt.today() - 3)::text and tt.q($z$select watermark_date from w1g_post_watermark where source_type='sale'$z$) = (tt.today() - 4)::text
  and tt.q($z$select posted_total from w1g_post_watermark where source_type='quick_expense'$z$) = '1');
select _w1g_post_scheduled(false) as c2 \gset
select tt.chk('T3 run 2: rotation serves the other type (sale), oldest first (3 days ago), not quick_expense again',
  (:'c2'::jsonb #>> '{by_type,sale,posted}') = '1' and tt.n('sale') = 1 and tt.n('quick_expense') = 1
  and tt.q($z$select count(*) from journal_entries where source_type='sale' and entry_date = tt.today() - 3$z$) = '1');
select _w1g_post_scheduled(false) as c3 \gset
select tt.chk('T3 run 3: back to quick_expense (the type served longest ago)', (:'c3'::jsonb #>> '{by_type,quick_expense,posted}') = '1' and tt.n('quick_expense') = 2 and tt.n('sale') = 1);
select _w1g_post_scheduled(false) as c4 \gset
select _w1g_post_scheduled(false) as c5 \gset
select tt.chk('T3 runs 4 and 5: the two remaining sales, oldest first; five documents in total', tt.n('sale') = 3 and tt.n('quick_expense') = 2 and (:'c5'::jsonb ->> 'left')::int = 0 and (:'c5'::jsonb ->> 'capped') = 'false');
select _w1g_post_scheduled(false) as c6 \gset
select tt.chk('T3 run 6: nothing waiting - posts 0, no run line written, journal unchanged (idempotent, no double post)', (:'c6'::jsonb ->> 'posted')::int = 0 and tt.je() = :je0 + 5
  and tt.q('select count(*) from w1g_post_runs') = '5' and tt.n('sale') = 3);
select tt.chk('T3 every entry balances, the bot is the author, the scheduler left one audit line per run that posted',
  tt.unbalanced() = 0 and tt.q($z$select count(*) from journal_entries where source_type in ('sale','quick_expense') and created_by = '00000000-0000-0000-0000-000000009805'$z$) = '5'
  and tt.q($z$select count(*) from audit_log where action='journal_sched_post'$z$) = '5');
select tt.chk('T3 the audit line names the way it ran and the counts', tt.q($z$select count(*) from audit_log where action='journal_sched_post' and detail ->> 'via' = 'notify_bot' and (detail ->> 'posted')::int = 1$z$)::int >= 1);
select tt.chk('T3 the watermark rows are clear (nothing waiting) and the scheduler state is kept even though run 6 posted nothing',
  tt.q('select coalesce(sum(pending_after),0) from w1g_post_watermark') = '0' and tt.q($z$select watermark_date from w1g_post_watermark where source_type='sale'$z$) = tt.today()::text
  and tt.q($z$select (last_run_at is not null and (last_result ->> 'posted') = '0')::text from w1g_sched_state where id = 1$z$) = 'true');
reset role;
select tt.as(:'u_o');
select tt.chk('T3 manual posting finds nothing more to do (the scheduler already did it all)', (acct_post_pending(true) ->> 'posted')::int = 0);

\echo == T4 freshness after posting
set role authenticated; select tt.as(:'u_v');
select _w1g_freshness() as f1 \gset
select tt.chk('T4 strip: fresh, 0 pending, last posted by an auto source, scheduler on, age in minutes small, per-type rows', (:'f1'::jsonb ->> 'status') = 'fresh' and (:'f1'::jsonb ->> 'pending')::int = 0
  and (:'f1'::jsonb ->> 'last_posted_at') is not null and (:'f1'::jsonb ->> 'age_minutes')::int between 0 and 5 and (:'f1'::jsonb ->> 'sched_on') = 'true'
  and jsonb_array_length(:'f1'::jsonb -> 'by_type') = 2 and (:'f1'::jsonb #>> '{last_check_result,posted}') = '0');
reset role;

\echo == T5 cap back to default; source-type list and look-back window
select tt.as(:'u_o');
select set_rule('journal_sched_post_cap','1500') is null as scap2 \gset
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values
 (1, 980004, tt.today(), now(), '[]', 200, 0, 200, 'cash', 'done', :'u_o'),
 (1, 980005, tt.today() - 6, now() - interval '6 days', '[]', 300, 0, 300, 'cash', 'done', :'u_o');
insert into sale_payments (sale_id, location_id, kind, mode, amount, paid_at, created_by) select s.id, s.location_id, 'sale', 'cash', s.total, s.sold_at, :'u_o' from sales s where s.receipt in (980004, 980005);
select set_rule('journal_sched_post_types','"sale_return, supplier_payment"') is null as st1 \gset
set role authenticated; select tt.as(:'u_b');
select _w1g_post_scheduled(false) as t1 \gset
select tt.chk('T5 type list = sale_return, supplier_payment: the two waiting sales are NOT posted by the scheduler (but stay posted-able by Post now)', (:'t1'::jsonb ->> 'posted')::int = 0 and tt.n('sale') = 3);
reset role;
select tt.as(:'u_o');
select set_rule('journal_sched_post_types','"no_such_type"') is null as st2 \gset
set role authenticated; select tt.as(:'u_b');
select tt.chk('T5 an unknown type name posts nothing and raises no error', (_w1g_post_scheduled(false) ->> 'posted')::int = 0 and tt.n('sale') = 3);
reset role;
select tt.as(:'u_o');
select set_rule('journal_sched_post_types', null) is null as st3 \gset
select set_rule('journal_sched_post_lookback_days','2') is null as lb1 \gset
set role authenticated; select tt.as(:'u_b');
select _w1g_post_scheduled(false) as l1 \gset
select tt.chk('T5 look-back 2 days: today''s sale is posted, the sale from 6 days ago is left alone', (:'l1'::jsonb ->> 'posted')::int = 1 and tt.n('sale') = 4
  and tt.q($z$select count(*) from journal_entries where source_type='sale' and entry_date = tt.today() - 6$z$) = '0' and (:'l1'::jsonb ->> 'floor')::date = tt.today() - 2);
reset role;
select tt.as(:'u_o');
select tt.chk('T5 the manual poster still sees the old sale (the window never hides it from Post now)', (acct_post_pending(true) ->> 'posted')::int = 1);
select tt.as(:'u_o');
select set_rule('journal_sched_post_lookback_days', null) is null as lb2 \gset
set role authenticated; select tt.as(:'u_b');
select tt.chk('T5 look-back blank again: the old sale is posted by the scheduler', (_w1g_post_scheduled(false) ->> 'posted')::int = 1 and tt.n('sale') = 5);
reset role;

\echo == T6 closed period: a bot is held back, the owner is not (same as Post now)
select tt.as(:'u_o');
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values
 (1, 980006, tt.today() - 8, now() - interval '8 days', '[]', 400, 0, 400, 'cash', 'done', :'u_o');
insert into sale_payments (sale_id, location_id, kind, mode, amount, paid_at, created_by) select s.id, s.location_id, 'sale', 'cash', s.total, s.sold_at, :'u_o' from sales s where s.receipt = 980006;
select set_rule('period_closed_until', to_jsonb((tt.today() - 7)::text)) is null as pc1 \gset
set role authenticated; select tt.as(:'u_b');
select _w1g_post_scheduled(false) as k1 \gset
select tt.chk('T6 period closed up to 7 days ago: the sale dated 8 days ago is counted locked, not posted; watermark shows it waiting', (:'k1'::jsonb ->> 'posted')::int = 0 and (:'k1'::jsonb ->> 'locked')::int = 1 and tt.n('sale') = 5
  and tt.q($z$select locked_after from w1g_post_watermark where source_type='sale'$z$) = '1' and tt.q($z$select watermark_date from w1g_post_watermark where source_type='sale'$z$) = (tt.today() - 9)::text);
reset role;
select tt.as(:'u_o');
select set_rule('period_closed_until', null) is null as pc2 \gset
set role authenticated; select tt.as(:'u_b');
select tt.chk('T6 period reopened by the owner: the next run posts it', (_w1g_post_scheduled(false) ->> 'posted')::int = 1 and tt.n('sale') = 6 and tt.q($z$select locked_after from w1g_post_watermark where source_type='sale'$z$) = '0');
reset role;

\echo == T7 a failing document is recorded, the others still post, and a fix clears it
select tt.as(:'u_o');
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values
 (1, 980007, tt.today(), now(), '[]', 650, 0, 650, 'cash', 'done', :'u_o');
insert into sale_payments (sale_id, location_id, kind, mode, amount, paid_at, created_by) select s.id, s.location_id, 'sale', 'cash', s.total, s.sold_at, :'u_o' from sales s where s.receipt = 980007;
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 55, 'cash', false, null, gen_random_uuid()) is not null as q3 \gset
update coa_accounts set active = false where id = (select account_id from acct_mappings where key = 'sales');     -- break the sales mapping on purpose (superuser, test only)
set role authenticated; select tt.as(:'u_b');
select _w1g_post_scheduled(false) as e1 \gset
select tt.chk('T7 the sale fails (retired account), the quick expense still posts; one error line, one failed run line',
  (:'e1'::jsonb ->> 'error_count')::int = 1 and (:'e1'::jsonb ->> 'posted')::int = 1 and tt.n('quick_expense') = 3 and tt.n('sale') = 6
  and tt.q($z$select count(*) from acct_post_errors72 where source_type='sale'$z$) = '1' and tt.q($z$select errors_after from w1g_post_watermark where source_type='sale'$z$) = '1'
  and (:'e1'::jsonb #>> '{errors,0,error}') like 'account_retired%');
select _w1g_post_scheduled(false) as e2 \gset
select tt.chk('T7 the failed sale is retried at the next run (tries goes up) and does not block anything else', (:'e2'::jsonb ->> 'error_count')::int = 1 and tt.q($z$select tries from acct_post_errors72 where source_type='sale'$z$) = '2');
select tt.as(:'u_v');
select _w1g_acct_readiness() as r1 \gset
select tt.chk('T7 readiness shows the posting error as a blocker', (:'r1'::jsonb -> 'blockers') @> '"no_errors"'::jsonb and (:'r1'::jsonb ->> 'errors') = '1');
select tt.chk('T7 the strip data counts the error', (_w1g_freshness() ->> 'errors') = '1');
reset role;
update coa_accounts set active = true where id = (select account_id from acct_mappings where key = 'sales');
update coa_accounts set active = false where id = (select account_id from acct_mappings where key = 'cogs');
select tt.as(:'u_o');
select tt.chk('T7 readiness: a mapping that points to a retired account is a blocker (mappings)', (_w1g_acct_readiness() -> 'blockers') @> '"mappings"'::jsonb);
update coa_accounts set active = true where id = (select account_id from acct_mappings where key = 'cogs');
set role authenticated; select tt.as(:'u_b');
select tt.chk('T7 fix applied: the sale posts, the error line disappears', (_w1g_post_scheduled(false) ->> 'posted')::int = 1 and tt.n('sale') = 7 and tt.q('select count(*) from acct_post_errors72') = '0');
reset role;

\echo == T8 a voided sale is reversed by the scheduler
select tt.as(:'u_o');
select id as vid from sales where receipt = 980003 \gset
select void_sale(:'vid'::uuid, 'test void') is null as vs \gset
set role authenticated; select tt.as(:'u_b');
select _w1g_post_scheduled(false) as v1 \gset
select tt.chk('T8 the void is reversed (1 reversal), the original is marked void, still balanced', (:'v1'::jsonb ->> 'reversed')::int = 1 and tt.unbalanced() = 0
  and tt.q(format($z$select count(*) from journal_entries r join journal_entries o on o.id = r.reverses_id where o.source_type='sale' and o.source_id = %L$z$, :'vid')) = '1'
  and tt.q(format($z$select status from journal_entries where source_type='sale' and source_id = %L and reverses_id is null$z$, :'vid')) = 'void');
select tt.chk('T8 a second run reverses nothing more', (_w1g_post_scheduled(false) ->> 'reversed')::int = 0);
reset role;

\echo == T9 accounting switched off, start date missing, the owner and a manager can run it, the database scheduler can post
select tt.as(:'u_o');
select set_rule('accounting_on','false') is null as ao \gset
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values (1, 980008, tt.today(), now(), '[]', 90, 0, 90, 'cash', 'done', :'u_o');
insert into sale_payments (sale_id, location_id, kind, mode, amount, paid_at, created_by) select s.id, s.location_id, 'sale', 'cash', s.total, s.sold_at, :'u_o' from sales s where s.receipt = 980008;
set role authenticated; select tt.as(:'u_b');
select tt.chk('T9 accounting OFF: skipped (accounting_off), nothing posted, same rule as Post now', (_w1g_post_scheduled(false) ->> 'skipped') = 'accounting_off' and tt.n('sale') = 7);
select tt.as(:'u_v');
select tt.chk('T9 strip status = off while accounting is off', (_w1g_freshness() ->> 'status') = 'off');
reset role;
select tt.as(:'u_o');
select set_rule('accounting_on','true') is null as ao2 \gset
reset role; select tt.as('');
select _w1g_post_scheduled(false) as dsr \gset
select tt.chk('T9 the database scheduler (no login) posts the waiting sale; via database_scheduler; author is empty; balanced',
  (:'dsr'::jsonb ->> 'posted')::int = 1 and (:'dsr'::jsonb ->> 'via') = 'database_scheduler' and tt.n('sale') = 8 and tt.unbalanced() = 0
  and (select created_by from journal_entries where source_type='sale' and source_id = (select id::text from sales where receipt = 980008) and reverses_id is null) is null);
set role authenticated; select tt.as('');
select tt.err('T9 an authenticated session with no login is not the database scheduler', $q$select _w1g_post_scheduled(false)$q$, 'not allowed');
reset role;
select tt.as(:'u_o');
set role authenticated; select tt.as(:'u_o');
select tt.chk('T9 the owner may run it (nothing waiting)', (_w1g_post_scheduled(false) ->> 'posted')::int = 0);
select tt.as(:'u_acc');
select tt.chk('T9 an accounts manager may run it (nothing waiting)', (_w1g_post_scheduled(false) ->> 'posted')::int = 0);
reset role;
select tt.as(:'u_o');
select set_rule('journal_sched_post_on','false') is null as soff \gset
set role authenticated; select tt.as(:'u_b');
select tt.chk('T9 switch OFF again = previous behaviour (skipped)', (_w1g_post_scheduled(false) ->> 'skipped') = 'switch_off');
reset role;

\echo == T10 readiness turns ready when the opening entry exists
select tt.as(:'u_o');
select _acct_write(:'pm'::date, null, 'opening', 'test_opening_98', null, 'test opening entry', null,
  (select jsonb_build_array(jsonb_build_object('account_id', (select id from coa_accounts where code='1110'), 'debit', 10, 'credit', 0), jsonb_build_object('account_id', (select id from coa_accounts where code='3100'), 'debit', 0, 'credit', 10)))) is not null as op \gset
set role authenticated; select tt.as(:'u_v');
select tt.chk('T10 ready: all five checks pass, no blockers', (_w1g_acct_readiness() ->> 'ready') = 'true' and (_w1g_acct_readiness() -> 'blockers') = '[]'::jsonb and (_w1g_acct_readiness() ->> 'opening') = 'true');
reset role;

\echo == T11 switch-coupling warning: forms_post_to_ledger
select tt.as(:'u_o');
set role authenticated; select tt.as(:'u_o');
select _w1g_switch_coupling_warning('forms_post_to_ledger', 'true'::jsonb) as w1 \gset
select tt.chk('T11 warning for ON: 4 stock/production actions flip from screen (a) to form (b); severity high; mentions path_locked and #/paths',
  (:'w1'::jsonb ->> 'locks') = '4' and (:'w1'::jsonb ->> 'unlocks') = '0' and (:'w1'::jsonb ->> 'severity') = 'high' and jsonb_array_length(:'w1'::jsonb -> 'actions') = 4
  and (:'w1'::jsonb ->> 'text') like '%path_locked%' and (:'w1'::jsonb ->> 'fix') like '%#/paths%' and (:'w1'::jsonb ->> 'show') = 'true' and (:'w1'::jsonb ->> 'confirm') = 'false'
  and (:'w1'::jsonb ->> 'on_now') = 'false' and (:'w1'::jsonb ->> 'mode') = 'warn');
select tt.chk('T11 the four domains are exactly stock_issue, stock_transfer, stock_count, production', (select array_agg(a ->> 'domain' order by a ->> 'domain') from jsonb_array_elements(:'w1'::jsonb -> 'actions') a) = array['production','stock_count','stock_issue','stock_transfer']);
select tt.chk('T11 asking with no value means "flip": same answer', (_w1g_switch_coupling_warning('forms_post_to_ledger') ->> 'locks') = '4');
select tt.chk('T11 asking for OFF while OFF = "No change", nothing shown', (_w1g_switch_coupling_warning('forms_post_to_ledger','false'::jsonb) ->> 'text') like 'No change%' and (_w1g_switch_coupling_warning('forms_post_to_ledger','false'::jsonb) ->> 'show') = 'false');
select tt.err('T11 a value that is not true/false is refused', $q$select _w1g_switch_coupling_warning('forms_post_to_ledger','"maybe"'::jsonb)$q$, 'bad_value');
select tt.chk('T11 an unknown key is known:false, nothing shown', (_w1g_switch_coupling_warning('no_such_rule','true'::jsonb) ->> 'known') = 'false');
reset role;
-- the prediction must equal the real behaviour: with an explicit owner setting for stock_issue the warning counts 3, and the real switch gives the same primaries
select tt.as(:'u_o');
select path_switch_set('stock_issue', 0, true, true, 'a', 'test explicit') is not null as ps \gset
set role authenticated; select tt.as(:'u_o');
select _w1g_switch_coupling_warning('forms_post_to_ledger', 'true'::jsonb) as w2 \gset
select tt.chk('T11 an explicit owner setting is respected: now 3 flips (stock_issue keeps the screen)', (:'w2'::jsonb ->> 'locks') = '3' and not (:'w2'::jsonb -> 'actions') @> '[{"domain":"stock_issue"}]'::jsonb);
reset role;
select set_rule('forms_post_to_ledger','true') is null as fon \gset
select tt.chk('T11 the prediction equals the real result after the switch is turned ON (stock_issue a; the other three b)',
  path_primary('stock_issue',0) = 'a' and path_primary('stock_transfer',0) = 'b' and path_primary('stock_count',0) = 'b' and path_primary('production',0) = 'b');
set role authenticated; select tt.as(:'u_o');
select _w1g_switch_coupling_warning('forms_post_to_ledger', 'false'::jsonb) as w3 \gset
select tt.chk('T11 warning for OFF while ON: 3 unlocks, text says the screens come back', (:'w3'::jsonb ->> 'unlocks') = '3' and (:'w3'::jsonb ->> 'locks') = '0' and (:'w3'::jsonb ->> 'text') like 'Turning this OFF gives the stock screens back%');
reset role;
select set_rule('forms_post_to_ledger','false') is null as foff \gset
select tt.chk('T11 switch OFF = old behaviour: all four back on the screen', path_primary('stock_transfer',0) = 'a' and path_primary('stock_count',0) = 'a' and path_primary('production',0) = 'a');
select path_switch_set('stock_issue', 0, true, true, null, 'test reset') is not null as ps2 \gset

\echo == T12 the screen really is locked while the switch is on (the warning is true)
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('TW98','test_item98','test_item98','kg','kg','raw_material',true,0);
select stock_opening((select id from items where code='TW98'), 1, 100, 10, null, 'seed', null) is not null as so \gset
select tt.chk('T12 before: the stock screen issue works', (stock_issue((select id from items where code='TW98'), 1, 3, null, 'x', null) ->> 'qty') = '3');
select set_rule('forms_post_to_ledger','true') is null as fon2 \gset
select tt.err('T12 switch ON: the same stock screen is refused (path_locked) - exactly what the warning said', $q$select stock_issue((select id from items where code='TW98'), 1, 2, null, 'x', null)$q$, 'path_locked');
select set_rule('forms_post_to_ledger','false') is null as foff2 \gset
select tt.chk('T12 switch OFF: the screen works again', (stock_issue((select id from items where code='TW98'), 1, 1, null, 'x', null) ->> 'qty') = '1');

\echo == T13 switch-coupling warning: path switches and the scheduler switch
set role authenticated; select tt.as(:'u_o');
select _w1g_switch_coupling_warning('path:stock_count', '"b"'::jsonb) as p1 \gset
select tt.chk('T13 path b while the form switch is OFF: severity high ("nothing posts"), shown', (:'p1'::jsonb ->> 'severity') = 'high' and (:'p1'::jsonb ->> 'text') like '%NOTHING posts%' and (:'p1'::jsonb ->> 'show') = 'true');
select tt.chk('T13 path a: info only, not shown', (_w1g_switch_coupling_warning('path:stock_count', '"a"'::jsonb) ->> 'severity') = 'info' and (_w1g_switch_coupling_warning('path:stock_count', '"a"'::jsonb) ->> 'show') = 'false');
select tt.err('T13 unknown place-of-two-paths domain refused', $q$select _w1g_switch_coupling_warning('path:no_such', '"a"'::jsonb)$q$, 'unknown_domain');
select tt.err('T13 bad path value refused', $q$select _w1g_switch_coupling_warning('path:stock_count', '"z"'::jsonb)$q$, 'bad_value');
reset role;
select set_rule('forms_post_to_ledger','true') is null as fon3 \gset
set role authenticated; select tt.as(:'u_o');
select tt.chk('T13 path b while the form switch is ON: no longer high', (_w1g_switch_coupling_warning('path:stock_count', '"b"'::jsonb) ->> 'severity') = 'info');
reset role;
select set_rule('forms_post_to_ledger','false') is null as foff3 \gset
set role authenticated; select tt.as(:'u_o');
select _w1g_switch_coupling_warning('journal_sched_post_on', 'true'::jsonb) as sw \gset
select tt.chk('T13 scheduler switch: text says what it does; ready now so no blocker text; severity info', (:'sw'::jsonb ->> 'severity') = 'info' and (:'sw'::jsonb ->> 'text') like 'Turning this ON lets the 30-minute notify job post%' and (:'sw'::jsonb #>> '{readiness,ready}') = 'true');
reset role;
select set_rule('accounting_on','false') is null as ao3 \gset
set role authenticated; select tt.as(:'u_o');
select tt.chk('T13 scheduler switch while accounting is OFF: severity high and the text names the missing step', (_w1g_switch_coupling_warning('journal_sched_post_on', 'true'::jsonb) ->> 'severity') = 'high'
  and (_w1g_switch_coupling_warning('journal_sched_post_on', 'true'::jsonb) ->> 'text') like '%Accounting is switched on%');
reset role;
select set_rule('accounting_on','true') is null as ao4 \gset
set role authenticated; select tt.as(:'u_s');
select tt.err('T13 a salesperson cannot read the warning', $q$select _w1g_switch_coupling_warning('forms_post_to_ledger','true'::jsonb)$q$, 'not allowed');
select tt.as(:'u_v');
select tt.chk('T13 an accounts viewer can read the warning', (_w1g_switch_coupling_warning('forms_post_to_ledger','true'::jsonb) ->> 'locks') = '4');
reset role;

\echo == T14 warning modes: off, warn (default), confirm (enforced on the server)
select tt.as(:'u_o');
select set_rule('switch_coupling_warning','"off"') is null as m0 \gset
set role authenticated; select tt.as(:'u_o');
select tt.chk('T14 mode off: the answer says show:false (the switch itself still works)', (_w1g_switch_coupling_warning('forms_post_to_ledger','true'::jsonb) ->> 'show') = 'false' and (_w1g_switch_coupling_warning('forms_post_to_ledger','true'::jsonb) ->> 'confirm') = 'false');
reset role;
select set_rule('forms_post_to_ledger','true') is null as fon4 \gset
select tt.chk('T14 mode off: turning the switch on needs nothing extra', rule_on('forms_post_to_ledger'));
select set_rule('forms_post_to_ledger','false') is null as foff4 \gset
select tt.err('T14 a bad mode is refused', $q$select set_rule('switch_coupling_warning','"loud"')$q$, 'bad_value');
select set_rule('switch_coupling_warning','"confirm"') is null as m2 \gset
set role authenticated; select tt.as(:'u_o');
select tt.chk('T14 mode confirm: the answer asks for confirmation when turning ON', (_w1g_switch_coupling_warning('forms_post_to_ledger','true'::jsonb) ->> 'confirm') = 'true');
select tt.err('T14 confirm mode: turning ON without a confirmation is refused by the database', $q$select set_rule('forms_post_to_ledger','true')$q$, 'coupling_confirm_needed');
reset role;
select tt.chk('T14 ... and the switch is still OFF', not rule_on('forms_post_to_ledger'));
set role authenticated; select tt.as(:'u_acc');
select tt.err('T14 only the owner can confirm', $q$select _w1g_switch_coupling_ack('forms_post_to_ledger','true'::jsonb,'x')$q$, 'not allowed');
select tt.as(:'u_o');
select tt.err('T14 only coupled keys can be confirmed', $q$select _w1g_switch_coupling_ack('accounting_on','true'::jsonb,'x')$q$, 'unknown_key');
select _w1g_switch_coupling_ack('forms_post_to_ledger','true'::jsonb,'test owner read the warning') as ack \gset
select tt.chk('T14 the confirmation returns the warning and is written to the change log (who, when, what)', (:'ack'::jsonb ->> 'locks') = '4' and (:'ack'::jsonb ->> 'ack_id') is not null
  and exists (select 1 from audit_log where action='switch_coupling_confirm' and record_id='forms_post_to_ledger' and detail ->> 'note' = 'test owner read the warning' and user_id = :'u_o'));
select set_rule('forms_post_to_ledger','true') is null as fon5 \gset
select tt.chk('T14 after the confirmation the switch turns ON', rule_on('forms_post_to_ledger'));
select set_rule('forms_post_to_ledger','false') is null as foff5 \gset
select tt.chk('T14 turning OFF needed no confirmation and is in force', not rule_on('forms_post_to_ledger'));
select tt.err('T14 a confirmation is single use: turning ON a second time is refused', $q$select set_rule('forms_post_to_ledger','true')$q$, 'coupling_confirm_needed');
reset role;
select set_rule('switch_coupling_warning','"warn"') is null as m3 \gset
select set_rule('forms_post_to_ledger','true') is null as fon6 \gset
select tt.chk('T14 back to warn: switch works without a confirmation, as before this phase', rule_on('forms_post_to_ledger'));
select set_rule('forms_post_to_ledger','false') is null as foff6 \gset
select set_rule('switch_coupling_warning','"confirm"') is null as m4 \gset
select tt.err('T14 confirm mode also guards the scheduler switch', $q$select set_rule('journal_sched_post_on','true')$q$, 'coupling_confirm_needed');
select set_rule('journal_stale_warn_hours','5') is null as swx \gset
select tt.chk('T14 the guard does not touch other rules (an unrelated rule changes freely in confirm mode)', rule_num('journal_stale_warn_hours') = 5);
select set_rule('journal_stale_warn_hours', null) is null as sw0 \gset
select set_rule('switch_coupling_warning','"warn"') is null as m5 \gset
select set_rule('journal_sched_post_on','false') is null as soff8 \gset

\echo == T15 U-12 settings for the backup tool
set role authenticated; select tt.as(:'u_bb');
select tt.chk('T15 the backup bot reads the defaults: encrypt OFF, retention blank', (_w1g_backup_settings() ->> 'encrypt_on') = 'false' and (_w1g_backup_settings() -> 'retention_days') = 'null'::jsonb);
select tt.as(:'u_b');
select tt.chk('T15 the notify bot may read it too', (_w1g_backup_settings() ->> 'encrypt_on') = 'false');
select tt.as(:'u_s');
select tt.err('T15 a salesperson cannot read it', $q$select _w1g_backup_settings()$q$, 'not allowed');
select tt.as('');
select tt.err('T15 no login cannot read it', $q$select _w1g_backup_settings()$q$, 'not allowed');
reset role;
select tt.as(:'u_o');
select set_rule('backup_encrypt_on','true') is null as be \gset
select set_rule('backup_retention_days','400') is null as br \gset
set role authenticated; select tt.as(:'u_bb');
select tt.chk('T15 after the owner sets them: encrypt ON, retention 400', (_w1g_backup_settings() ->> 'encrypt_on') = 'true' and (_w1g_backup_settings() ->> 'retention_days') = '400');
reset role;
select tt.as(:'u_o');
select set_rule('backup_encrypt_on','false') is null as be2 \gset
select set_rule('backup_retention_days',null) is null as br2 \gset

\echo == T16 setting validation and the change log
select tt.as(:'u_o');
select tt.err('T16 cap 0 refused', $q$select set_rule('journal_sched_post_cap','0')$q$, 'bad_value');
select tt.err('T16 cap 6000 refused', $q$select set_rule('journal_sched_post_cap','6000')$q$, 'bad_value');
select tt.err('T16 retention 0 refused', $q$select set_rule('backup_retention_days','0')$q$, 'bad_value');
select tt.err('T16 look-back 0 refused', $q$select set_rule('journal_sched_post_lookback_days','0')$q$, 'bad_value');
select tt.err('T16 a non-owner cannot change a setting', format($q$select tt.as(%L); select set_rule('journal_sched_post_on','true')$q$, :'u_acc'), 'not allowed');
select tt.as(:'u_o');
select tt.chk('T16 every setting change is in the change log (audit_rules)', (select count(*) from audit_log where table_name = 'rules' and record_id in ('journal_sched_post_on','journal_sched_post_cap','forms_post_to_ledger','backup_encrypt_on','switch_coupling_warning')) >= 10);
select tt.chk('T16 rules: nothing deleted; the new rows keep a label and hint in English', (select count(*) from rules where key like 'journal_sched%' or key in ('journal_stale_warn_hours','switch_coupling_warning','backup_encrypt_on','backup_retention_days')) = 8);

\echo == T17 append-only and balance
select tt.err('T17 the run log cannot be deleted', $q$delete from w1g_post_runs$q$, 'nothing is deleted');
select tt.err('T17 the watermark cannot be deleted', $q$delete from w1g_post_watermark$q$, 'nothing is deleted');
select tt.err('T17 a confirmation cannot be deleted', $q$delete from w1g_switch_acks$q$, 'nothing is deleted');
select tt.chk('T17 after everything above every journal entry still balances', tt.unbalanced() = 0);
select tt.chk('T17 the balance check core is not red', (select (_e_balance_check() ->> 'status') <> 'red'));

\echo == T18 paste twice
\i supabase/phase98.sql
select tt.chk('T18 paste twice: rules, watermark and runs keep their values; the guard trigger exists once',
  (select count(*) from w1g_post_runs) > 0 and (select count(*) from rules where key = 'journal_sched_post_cap') = 1 and rule_num('journal_sched_post_cap') = 1500
  and (select count(*) from pg_trigger where tgname = 'rules_coupling_guard98') = 1);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
