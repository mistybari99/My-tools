-- FRESH DB ONLY. Phase 95 tests (journal, chart and mapping controls: place of every manual line, mapping type guard, attachment above a total, control accounts by a non-owner).
--   ORDER="phase8 ... phase87 phase94 phase95" bash tests/sql/build_fresh_db.sh a95db        (any port; this run used 5565)
--   psql -h /tmp -p 5565 -U postgres -d a95db -qAt -f supabase/phase95_test.sql | grep -E 'FAIL|RESULT'      (run from the repository root: section T10 pastes supabase/phase95.sql again)
-- The acct_journal_post hook of docs/integration/W1-E.md is applied INSIDE this test (section T5) on the scratch database; the original body is restored at the end.
-- The location trigger and the mapping trigger need no hook and are tested first, with the shared function untouched.
-- Test data only (test_* names). The calls run as the signed-in user through the request claim; the API functions are security definer and check the caller themselves.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000095'
\set u_acc '00000000-0000-0000-0000-000000000195'
\set u_acc2 '00000000-0000-0000-0000-000000000295'
\set u_ap '00000000-0000-0000-0000-000000000395'
\set u_x '00000000-0000-0000-0000-000000000495'
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
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.exc(p_kind text) returns bigint language sql stable security definer as $$ select count(*) from public.money_exceptions where kind = p_kind $$;
create or replace function tt.exev(p_kind text, p_ev text) returns bigint language sql stable security definer as $$ select count(*) from public.money_exceptions where kind = p_kind and event_type = p_ev $$;
create or replace function tt.je(p_memo text) returns bigint language sql stable security definer as $$ select count(*) from public.journal_entries where memo like p_memo || '%' $$;
create or replace function tt.qid(p_memo text) returns bigint language sql stable security definer as $$ select max(id) from public.w1e_requests where kind = 'journal_control' and payload ->> 'memo' = p_memo $$;
create or replace function tt.acct(p_code text) returns bigint language sql stable security definer as $$ select id from public.coa_accounts where code = p_code $$;
create or replace function tt.mapacct(p_key text) returns bigint language sql stable security definer as $$ select account_id from public.acct_mappings where key = p_key $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner95@s.app','{"full_name":"test_owner"}'), (:'u_acc','test_acct95@s.app','{"full_name":"test_acct"}'), (:'u_acc2','test_acct95b@s.app','{"full_name":"test_acct2"}'),
 (:'u_ap','test_appr95@s.app','{"full_name":"test_appr"}'), (:'u_x','test_other95@s.app','{"full_name":"test_other"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_acc','salesperson'),(:'u_acc2','salesperson'),(:'u_ap','purchasing'),(:'u_x','salesperson') on conflict do nothing;
insert into user_locations values (:'u_acc',1),(:'u_acc2',1),(:'u_ap',1),(:'u_x',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_acc','accounts_manage',1),(:'u_acc2','accounts_manage',null);
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset

\echo == T0 shape and safe defaults
select tt.chk('T0 phase95 present, 35 mapping type rows, all active', to_regprocedure('public._p95_present()') is not null and (select count(*) from w1e_mapping_types)=35 and not exists (select 1 from w1e_mapping_types where not active));
select tt.chk('T0 five settings in module books, defaults = today: off, off, blank, allow, code prefixes',
  (select count(*) from rules where key in ('journal_loc_check','mapping_type_guard','journal_attach_over','journal_control_acct_mode','journal_control_prefixes') and module='books')=5
  and not rule_on('journal_loc_check') and not rule_on('mapping_type_guard') and rule_num('journal_attach_over') is null and rule_txt('journal_control_acct_mode')='allow' and rule_txt('journal_control_prefixes')='11,1210,13,2100');
select tt.chk('T0 labels are English and have a hint', not exists (select 1 from rules where key in ('journal_loc_check','mapping_type_guard','journal_attach_over','journal_control_acct_mode','journal_control_prefixes') and (label_en !~ '^[ -~]+$' or coalesce(hint_en,'')='')));
select tt.chk('T0 the shared journal functions are untouched', position('w1e' in pg_get_functiondef('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'::regprocedure))=0
  and position('w1e' in pg_get_functiondef('public.acct_mapping_set(text,bigint)'::regprocedure))=0 and position('w1e' in pg_get_functiondef('public._acct_resolve(jsonb,integer)'::regprocedure))=0 and position('w1e' in pg_get_functiondef('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)'::regprocedure))=0);
select tt.chk('T0 internals closed, API open', not has_function_privilege('authenticated','public._w1e_journal_gate(date,int,text,jsonb,text,uuid,numeric)','execute') and not has_function_privilege('authenticated','public._w1e_apply_journal_control(public.w1e_requests)','execute')
  and has_function_privilege('authenticated','public.w1e_mapping_check(text,bigint)','execute') and not has_function_privilege('anon','public.w1e_mapping_types_list()','execute'));
select tt.chk('T0 mapping type table: no direct browser access', not has_table_privilege('authenticated','public.w1e_mapping_types','select') and not has_table_privilege('authenticated','public.w1e_mapping_types','update'));
select tt.chk('T0 the seeded types follow the real chart: every existing mapping of this database already satisfies its rule',
  not exists (select 1 from acct_mappings m join coa_accounts a on a.id=m.account_id join lateral (select w.allowed from w1e_mapping_types w where m.key like w.key_like order by length(w.key_like) desc limit 1) t on true where not (a.type = any (t.allowed))));

select tt.as(:'u_o');
select acct_set_start(:'pm'::date) is not null as ast \gset
select set_rule('accounting_on','true') is null as on1 \gset

\echo == T1 defaults keep today: a branch accountant posts to another place and company-wide, maps sales to an expense account, journals any size on cash
select tt.as(:'u_acc');
select acct_journal_post(tt.today(), 1, 't1-other-place', '[{"code":"1110","debit":100,"location_id":2},{"code":"4900","credit":100,"location_id":2}]'::jsonb, gen_random_uuid()) ->> 'id' as j1 \gset
select acct_journal_post(tt.today(), null, 't1-company-wide', '[{"code":"1110","debit":110},{"code":"4900","credit":110}]'::jsonb, gen_random_uuid()) ->> 'id' as j2 \gset
select acct_journal_post(tt.today(), 1, 't1-big-cash', '[{"code":"1110","debit":9000000},{"code":"4900","credit":9000000}]'::jsonb, gen_random_uuid(), null) ->> 'id' as j3 \gset
select tt.chk('T1 all three manual journals are posted as today (the holes the controls close)', tt.je('t1-other-place')=1 and tt.je('t1-company-wide')=1 and tt.je('t1-big-cash')=1);
select tt.mapacct('sales') as sales_acct \gset
select acct_mapping_set('sales', tt.acct('5900')) is not null as mp1 \gset
select tt.chk('T1 sales mapped to an expense account is accepted as today', tt.mapacct('sales')=tt.acct('5900'));
select acct_mapping_set('sales', :'sales_acct'::bigint) is not null as mp2 \gset
select tt.chk('T1 mapping restored', tt.mapacct('sales')=:'sales_acct'::bigint);

\echo == T2 journal_loc_check: every line of a manual journal needs a place the caller may use (a trigger: no hook needed)
select tt.as(:'u_o');
select set_rule('journal_loc_check','true') is null as lc1 \gset
select tt.as(:'u_acc');
select tt.err('T2 a line in another place is refused', $$select acct_journal_post(tt.today(), 1, 't2-other', '[{"code":"1110","debit":100,"location_id":2},{"code":"4900","credit":100,"location_id":1}]'::jsonb, gen_random_uuid())$$, 'journal_place_not_allowed');
select tt.err('T2 even the second line in another place is refused', $$select acct_journal_post(tt.today(), 1, 't2-other2', '[{"code":"1110","debit":100,"location_id":1},{"code":"4900","credit":100,"location_id":2}]'::jsonb, gen_random_uuid())$$, 'journal_place_not_allowed');
select tt.err('T2 a company-wide journal (no place) is refused for a branch accountant', $$select acct_journal_post(tt.today(), null, 't2-company', '[{"code":"1110","debit":100},{"code":"4900","credit":100}]'::jsonb, gen_random_uuid())$$, 'journal_place_not_allowed');
select tt.err('T2 a line in his own place under a company-wide header: the header-less line 4900 has no place, so it is refused', $$select acct_journal_post(tt.today(), null, 't2-company2', '[{"code":"1110","debit":100,"location_id":1},{"code":"4900","credit":100}]'::jsonb, gen_random_uuid())$$, 'journal_place_not_allowed');
select tt.chk('T2 nothing was written by the refused journals', tt.je('t2-')=0);
select acct_journal_post(tt.today(), 1, 't2-own-place', '[{"code":"1110","debit":100},{"code":"4900","credit":100,"location_id":1}]'::jsonb, gen_random_uuid()) ->> 'id' as j4 \gset
select tt.chk('T2 his own place is fine (header place and line place)', tt.je('t2-own-place')=1);
select tt.as(:'u_acc2');
select acct_journal_post(tt.today(), null, 't2-all-places', '[{"code":"1110","debit":100,"location_id":2},{"code":"4900","credit":100}]'::jsonb, gen_random_uuid()) ->> 'id' as j5 \gset
select tt.chk('T2 a person with the all-places accounts right posts anywhere, also with no place', tt.je('t2-all-places')=1);
select tt.as(:'u_o');
select acct_journal_post(tt.today(), null, 't2-owner', '[{"code":"1110","debit":100,"location_id":2},{"code":"4900","credit":100}]'::jsonb, gen_random_uuid()) ->> 'id' as j6 \gset
select tt.chk('T2 the owner posts anywhere', tt.je('t2-owner')=1);
select money_exception_grant('override','test: head office asked the branch accountant to book the other shop',:'u_acc'::uuid,null,'w1e_journal_loc') ->> 'id' as gx1 \gset
select tt.as(:'u_acc');
select acct_journal_post(tt.today(), 1, 't2-exc', '[{"code":"1110","debit":100,"location_id":2},{"code":"4900","credit":100,"location_id":2}]'::jsonb, gen_random_uuid()) ->> 'id' as j7 \gset
select tt.chk('T2 one-off exception: the whole journal (two lines in another place) goes through once, one Exceptions row, one audit line', tt.je('t2-exc')=1 and tt.exev('override_exception','w1e_journal_loc')=1
  and exists (select 1 from audit_log where action='money_exception_used' and detail ->> 'rule'='override' and detail ->> 'event'='w1e_journal_loc'));
select tt.err('T2 the exception is used up', $$select acct_journal_post(tt.today(), 1, 't2-exc2', '[{"code":"1110","debit":100,"location_id":2},{"code":"4900","credit":100,"location_id":2}]'::jsonb, gen_random_uuid())$$, 'journal_place_not_allowed');
-- automatic postings are never touched
select tt.as(:'u_o');
select cash_move_add(2,'owner_topup',321,tt.today(),'cash',null,'t2-auto',null,gen_random_uuid(),false) is not null as cm1 \gset
select tt.as(:'u_acc2');
select acct_post_pending(false) is not null as pp1 \gset
select tt.chk('T2 posting of a document of another place by the branch accountant''s page open still works (source is not manual)', exists (select 1 from journal_entries e where e.source_type='cash_move' and e.source_id=(select id::text from cash_moves where ref='t2-auto')));
select tt.as(:'u_acc');
select acct_journal_reverse((select id from journal_entries where memo like 't2-exc%' limit 1), 'test reversal of the exception journal', gen_random_uuid()) is not null as rv1 \gset
select tt.chk('T2 a reversal mirrors the original and is not blocked by the place check', exists (select 1 from journal_entries where reverses_id=(select id from journal_entries where memo like 't2-exc%' limit 1)));
select tt.as(:'u_o');
select set_rule('journal_loc_check','false') is null as lc2 \gset
select tt.as(:'u_acc');
select acct_journal_post(tt.today(), 1, 't2-off', '[{"code":"1110","debit":100,"location_id":2},{"code":"4900","credit":100,"location_id":2}]'::jsonb, gen_random_uuid()) ->> 'id' as j8 \gset
select tt.chk('T2 switched off = old behaviour', tt.je('t2-off')=1);

\echo == T3 mapping_type_guard: a mapping key may only point to the listed account types (a trigger: no hook needed)
select tt.as(:'u_acc');
select tt.chk('T3 guard OFF: the check function still tells the screen what would happen', (w1e_mapping_check('sales', tt.acct('5900')) ->> 'ok')='false' and (w1e_mapping_check('sales', tt.acct('4100')) ->> 'ok')='true' and (w1e_mapping_check('sales', tt.acct('5900')) ->> 'guard_on')='false');
select tt.as(:'u_o');
select set_rule('mapping_type_guard','true') is null as mg1 \gset
select tt.as(:'u_acc');
select tt.err('T3 sales to an expense account is refused', format($$select acct_mapping_set('sales', %s)$$, tt.acct('5900')), 'mapping_type_mismatch');
select tt.err('T3 payable to an asset account is refused', format($$select acct_mapping_set('payable', %s)$$, tt.acct('1110')), 'mapping_type_mismatch');
select tt.err('T3 an expense head (exp_transport) to an income account is refused', format($$select acct_mapping_set('exp_transport', %s)$$, tt.acct('4900')), 'mapping_type_mismatch');
select tt.chk('T3 the mappings did not move', tt.mapacct('sales')=:'sales_acct'::bigint);
select acct_mapping_set('sales', tt.acct('4900')) is not null as mp3 \gset
select acct_mapping_set('sales', :'sales_acct'::bigint) is not null as mp4 \gset
select acct_mapping_set('exp_transport', tt.acct('5600')) is not null as mp5 \gset
select acct_mapping_set('exp_transport', tt.acct('5700')) is not null as mp6 \gset
select acct_mapping_set('exp_brand_new_head', tt.acct('5900')) is not null as mp7 \gset
select tt.chk('T3 correct types are accepted (income for sales, expense for expense heads, a new exp_ key)', tt.mapacct('exp_transport')=tt.acct('5700') and tt.mapacct('exp_brand_new_head')=tt.acct('5900'));
select tt.chk('T3 the check function agrees', (w1e_mapping_check('sales', tt.acct('5900')) ->> 'ok')='false' and (w1e_mapping_check('sales', tt.acct('5900')) -> 'allowed')='["income"]'::jsonb and (w1e_mapping_check('sales', tt.acct('5900')) ->> 'guard_on')='true');
select tt.as(:'u_o');
select tt.err('T3 the owner is checked too', format($$select acct_mapping_set('sales', %s)$$, tt.acct('5900')), 'mapping_type_mismatch');
select money_exception_grant('override','test: temporary parking of sales on another account while the chart is rebuilt',:'u_o'::uuid,null,'w1e_mapping') ->> 'id' as gx2 \gset
select acct_mapping_set('sales', tt.acct('5900')) is not null as mp8 \gset
select tt.chk('T3 one-off exception (reason): the owner can do it once; Exceptions row + audit line', tt.mapacct('sales')=tt.acct('5900') and tt.exev('override_exception','w1e_mapping')=1);
select tt.err('T3 and only once', format($$select acct_mapping_set('sales', %s)$$, tt.acct('5800')), 'mapping_type_mismatch');
select acct_mapping_set('sales', :'sales_acct'::bigint) is not null as mp9 \gset
select tt.chk('T3 moving it back to the right type needs no exception', tt.mapacct('sales')=:'sales_acct'::bigint);
select tt.err('T3 changing the type list needs the owner, a reason', $$select w1e_mapping_type_set('sales', array['income','expense'], true, '')$$, 'reason_required');
select tt.err('T3 a type that does not exist is refused', $$select w1e_mapping_type_set('sales', array['income','spaceship'], true, 'test reason')$$, 'allowed');
select w1e_mapping_type_set('sales', array['income','expense'], true, 'test: sales may be parked on an expense account') ->> 'key_like' as ms1 \gset
select acct_mapping_set('sales', tt.acct('5900')) is not null as mp10 \gset
select tt.chk('T3 the owner widened the list: now the expense account is allowed for sales, and the change is in audit_log', tt.mapacct('sales')=tt.acct('5900') and exists (select 1 from audit_log where action='w1e_mapping_type_set' and record_id='sales'));
select w1e_mapping_type_set('sales', array['income'], false, 'test: row switched off, nothing is deleted') is not null as ms2 \gset
select acct_mapping_set('sales', :'sales_acct'::bigint) is not null as mp11 \gset
select tt.err('T3 a type row is never deleted', $$delete from w1e_mapping_types$$, 'nothing is deleted');
select tt.chk('T3 a switched-off row stops checking its keys', exists (select 1 from w1e_mapping_types where key_like='sales' and not active));
select w1e_mapping_type_set('sales', array['income'], true, 'test: back on') is not null as ms3 \gset
select tt.as(:'u_acc');
select tt.err('T3 a non-owner cannot change the type list', $$select w1e_mapping_type_set('sales', array['income','expense'], true, 'test reason')$$, 'not allowed');
select tt.as(:'u_x');
select tt.err('T3 a person without accounts rights cannot ask the check', format($$select w1e_mapping_check('sales', %s)$$, tt.acct('5900')), 'not allowed');
select tt.err('T3 nor list the types', $$select w1e_mapping_types_list()$$, 'not allowed');
select tt.as(:'u_o');
select set_rule('mapping_type_guard','false') is null as mg2 \gset
select tt.as(:'u_acc');
select acct_mapping_set('sales', tt.acct('5900')) is not null as mp12 \gset
select acct_mapping_set('sales', :'sales_acct'::bigint) is not null as mp13 \gset
select tt.chk('T3 switched off = old behaviour (any account accepted)', tt.mapacct('sales')=:'sales_acct'::bigint);

\echo == T4 the hook of docs/integration/W1-E.md for acct_journal_post is applied here, on this scratch database
select set_config('w1e.orig_jp', pg_get_functiondef('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'::regprocedure), false) is not null as sv1 \gset
select _m_patch('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'::regprocedure, array[
 $h$declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb;$h$,
 $h$declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb; gate jsonb; /* bos87 w1e95 */$h$,
 $h$  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);$h$,
 $h$  gate := public._w1e_journal_gate(p_date, p_loc, p_memo, ln, p_photo, p_client, td);
  if gate is not null then return gate; end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);$h$]) as hooked \gset
select tt.chk('T4 the hook text patches acct_journal_post exactly once', :'hooked'='t' and not _m_patch('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'::regprocedure, array['x','y']) and position('w1e95' in pg_get_functiondef('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'::regprocedure))>0);
select tt.as(:'u_o');
select tt.chk('T4 w1e_state sees the hook', (w1e_state() #>> '{hooks,acct_journal_post}')='true');
select tt.as(:'u_acc');
select acct_journal_post(tt.today(), 1, 't4-default-big', '[{"code":"1110","debit":9000000},{"code":"4900","credit":9000000}]'::jsonb, gen_random_uuid()) ->> 'id' as j9 \gset
select tt.chk('T4 hook installed, every setting at default: the same big cash journal is still posted at once (today)', tt.je('t4-default-big')=1);

\echo -- T4a attachment above a total
select tt.as(:'u_o');
select set_rule('journal_attach_over','1000') is null as at1 \gset
select tt.as(:'u_acc');
select tt.err('T4a above the total, no attachment: refused', $$select acct_journal_post(tt.today(), 1, 't4a-nophoto', '[{"code":"5900","debit":1500},{"code":"4900","credit":1500}]'::jsonb, gen_random_uuid())$$, 'attachment_required');
select tt.err('T4a a blank attachment is no attachment', $$select acct_journal_post(tt.today(), 1, 't4a-blank', '[{"code":"5900","debit":1500},{"code":"4900","credit":1500}]'::jsonb, gen_random_uuid(), '   ')$$, 'attachment_required');
select acct_journal_post(tt.today(), 1, 't4a-photo', '[{"code":"5900","debit":1500},{"code":"4900","credit":1500}]'::jsonb, gen_random_uuid(), 'JNL/test_scan_1.jpg') ->> 'id' as ap1 \gset
select acct_journal_post(tt.today(), 1, 't4a-small', '[{"code":"5900","debit":900},{"code":"4900","credit":900}]'::jsonb, gen_random_uuid()) ->> 'id' as ap2 \gset
select acct_journal_post(tt.today(), 1, 't4a-exact', '[{"code":"5900","debit":1000},{"code":"4900","credit":1000}]'::jsonb, gen_random_uuid()) ->> 'id' as ap3 \gset
select tt.chk('T4a with an attachment, below, and exactly at the total: posted', tt.je('t4a-photo')=1 and tt.je('t4a-small')=1 and tt.je('t4a-exact')=1 and (select photo from journal_entries where memo like 't4a-photo%')='JNL/test_scan_1.jpg');
select tt.err('T4a an unbalanced journal is still refused first (never excepted)', $$select acct_journal_post(tt.today(), 1, 't4a-unbal', '[{"code":"5900","debit":1500},{"code":"4900","credit":1400}]'::jsonb, gen_random_uuid())$$, 'unbalanced');
select tt.as(:'u_o');
select tt.err('T4a the owner needs an attachment too', $$select acct_journal_post(tt.today(), 1, 't4a-owner', '[{"code":"5900","debit":1500},{"code":"4900","credit":1500}]'::jsonb, gen_random_uuid())$$, 'attachment_required');
select gen_random_uuid() as c4 \gset
select money_exception_grant('override','test: scan will follow tomorrow, supplier waiting',null,:'c4'::uuid,'w1e_journal_attach') ->> 'id' as gx3 \gset
select acct_journal_post(tt.today(), 1, 't4a-exc', '[{"code":"5900","debit":1500},{"code":"4900","credit":1500}]'::jsonb, :'c4'::uuid) ->> 'id' as ap4 \gset
select tt.chk('T4a one-off exception for that journal (client id): posted, Exceptions row, audit line', tt.je('t4a-exc')=1 and tt.exev('override_exception','w1e_journal_attach')=1);
select acct_journal_post(tt.today(), 1, 't4a-dry', '[{"code":"5900","debit":1500},{"code":"4900","credit":1500}]'::jsonb, gen_random_uuid(), null, true) ->> 'dry' as dry \gset
select tt.chk('T4a a dry run is not stopped and writes nothing', :'dry'='true' and tt.je('t4a-dry')=0);
select set_rule('journal_attach_over',null) is null as at2 \gset
select tt.as(:'u_acc');
select acct_journal_post(tt.today(), 1, 't4a-off', '[{"code":"5900","debit":5000000},{"code":"4900","credit":5000000}]'::jsonb, gen_random_uuid()) ->> 'id' as ap5 \gset
select tt.chk('T4a blank = off', tt.je('t4a-off')=1);

\echo -- T4b control accounts: request, block, allow
select tt.as(:'u_o');
select set_rule('journal_control_acct_mode','"request"') is null as cr1 \gset
select tt.as(:'u_acc');
select gen_random_uuid() as c5 \gset
select acct_journal_post(tt.today(), 1, 't4b-cash', '[{"code":"1110","debit":200},{"code":"4900","credit":200}]'::jsonb, :'c5'::uuid) as r5 \gset
select tt.chk('T4b a journal on cash by a non-owner is NOT posted: it answers pending with a request id', (:'r5'::jsonb ->> 'pending')='true' and tt.je('t4b-cash')=0 and tt.qid('t4b-cash') is not null);
select acct_journal_post(tt.today(), 1, 't4b-cash', '[{"code":"1110","debit":200},{"code":"4900","credit":200}]'::jsonb, :'c5'::uuid) as r5b \gset
select tt.chk('T4b the same client id sent again does not make a second request', (select count(*) from w1e_requests where kind='journal_control')=1 and (:'r5b'::jsonb ->> 'pending')='true');
select acct_journal_post(tt.today(), 1, 't4b-bank', '[{"code":"5900","debit":300},{"code":"1120","credit":300}]'::jsonb, gen_random_uuid()) ->> 'pending' as p6 \gset
select acct_journal_post(tt.today(), 1, 't4b-recv', '[{"code":"1210","debit":310},{"code":"4900","credit":310}]'::jsonb, gen_random_uuid()) ->> 'pending' as p7 \gset
select acct_journal_post(tt.today(), 1, 't4b-pay', '[{"code":"2100","debit":320},{"code":"4900","credit":320}]'::jsonb, gen_random_uuid()) ->> 'pending' as p8 \gset
select acct_journal_post(tt.today(), 1, 't4b-inv', '[{"code":"1310","debit":330},{"code":"4900","credit":330}]'::jsonb, gen_random_uuid()) ->> 'pending' as p9 \gset
select tt.chk('T4b bank, receivable, payable and inventory are control accounts too', :'p6'='true' and :'p7'='true' and :'p8'='true' and :'p9'='true' and (select count(*) from w1e_requests where kind='journal_control')=5);
select acct_journal_post(tt.today(), 1, 't4b-expense', '[{"code":"5900","debit":340},{"code":"4900","credit":340}]'::jsonb, gen_random_uuid()) ->> 'id' as j10 \gset
select tt.chk('T4b a journal that touches no control account is posted at once', tt.je('t4b-expense')=1);
select acct_journal_post(tt.today(), 1, 't4b-dry', '[{"code":"1110","debit":200},{"code":"4900","credit":200}]'::jsonb, gen_random_uuid(), null, true) ->> 'dry' as dry2 \gset
select tt.chk('T4b a dry run creates no request', :'dry2'='true' and (select count(*) from w1e_requests where kind='journal_control')=5);
select tt.as(:'u_o');
select acct_journal_post(tt.today(), 1, 't4b-owner', '[{"code":"1110","debit":350},{"code":"4900","credit":350}]'::jsonb, gen_random_uuid()) ->> 'id' as j11 \gset
select tt.chk('T4b the owner is not held', tt.je('t4b-owner')=1);
select tt.qid('t4b-cash') as q1 \gset
select tt.as(:'u_acc');
select tt.err('T4b the maker cannot decide his own request', format($$select w1e_request_decide(%s, true, null)$$, :'q1'), 'self_approval');
select tt.as(:'u_x');
select tt.err('T4b someone who is not the approver cannot decide it', format($$select w1e_request_decide(%s, true, null)$$, :'q1'), 'approver_only');
select tt.as(:'u_o');
select w1e_request_decide(:'q1'::bigint, true, 'test checked the voucher') ->> 'status' as ap6 \gset
select tt.chk('T4b the owner approves (mode self): the journal exists once, balanced, same lines, memo marks the request, the maker''s photo and client id are kept', :'ap6'='approved' and tt.je('t4b-cash')=1
  and (select count(*) from journal_entries e join journal_lines l on l.entry_id=e.id where e.memo like 't4b-cash%')=2 and (select client_id from journal_entries where memo like 't4b-cash%')=:'c5'::uuid
  and (select memo from journal_entries where memo like 't4b-cash%') like '%[request %]' and tt.unbalanced()=0);
select tt.err('T4b a decided request cannot be decided again', format($$select w1e_request_decide(%s, true, null)$$, :'q1'), 'request_not_pending');
select tt.qid('t4b-bank') as q2 \gset
select tt.err('T4b a rejection needs a note', format($$select w1e_request_decide(%s, false, '')$$, :'q2'), 'note_required');
select w1e_request_decide(:'q2'::bigint, false, 'test: wrong account') ->> 'status' as rj2 \gset
select tt.chk('T4b rejected: nothing posted', :'rj2'='rejected' and tt.je('t4b-bank')=0);
select tt.qid('t4b-recv') as q3 \gset
select tt.as(:'u_acc');
select w1e_request_cancel(:'q3'::bigint, 'test: entered twice') ->> 'status' as cn3 \gset
select tt.chk('T4b the maker can cancel his own request', :'cn3'='cancelled' and tt.je('t4b-recv')=0);
-- named approver: the one chosen under phase87
select tt.as(:'u_o');
select owner_approval_mode_set2('named','purchasing',null,'test named role') ->> 'mode' as nm1 \gset
select tt.qid('t4b-pay') as q4 \gset
select tt.err('T4b in named mode the owner is not the approver (phase87 choice)', format($$select w1e_request_decide(%s, true, null)$$, :'q4'), 'approver_only');
select tt.as(:'u_ap');
select w1e_request_decide(:'q4'::bigint, true, 'test by the role holder') ->> 'status' as ap7 \gset
select tt.chk('T4b the role holder the owner named approves; nothing was hard-coded', :'ap7'='approved' and tt.je('t4b-pay')=1);
select tt.as(:'u_o');
select owner_approval_mode_set2('named','-',array[:'u_acc'::uuid],'test the maker is also named') ->> 'mode' as nm2 \gset
select tt.qid('t4b-inv') as q5 \gset
select tt.as(:'u_acc');
select tt.err('T4b a named approver cannot approve his own request', format($$select w1e_request_decide(%s, true, null)$$, :'q5'), 'self_approval');
select tt.as(:'u_o');
select owner_approval_mode_set2('self') ->> 'mode' as nm3 \gset
select w1e_request_decide(:'q5'::bigint, true, 'test') ->> 'status' as ap8 \gset
select tt.chk('T4b back to self, the owner decides', :'ap8'='approved' and tt.je('t4b-inv')=1);
-- the maker''s place rights are checked at request time
select set_rule('journal_loc_check','true') is null as lc3 \gset
select tt.as(:'u_acc');
select tt.err('T4b a request that would post to another place is refused when the request is made', $$select acct_journal_post(tt.today(), 1, 't4b-place', '[{"code":"1110","debit":200,"location_id":2},{"code":"4900","credit":200,"location_id":1}]'::jsonb, gen_random_uuid())$$, 'journal_place_not_allowed');
select tt.as(:'u_o');
select set_rule('journal_loc_check','false') is null as lc4 \gset
-- block
select set_rule('journal_control_acct_mode','"block"') is null as cb1 \gset
select tt.as(:'u_acc');
select tt.err('T4b block: refused', $$select acct_journal_post(tt.today(), 1, 't4b-blocked', '[{"code":"1110","debit":200},{"code":"4900","credit":200}]'::jsonb, gen_random_uuid())$$, 'control_account_blocked');
select tt.as(:'u_o');
select gen_random_uuid() as c6 \gset
select money_exception_grant('override','test: month-end correction agreed with the owner',:'u_acc'::uuid,null,'w1e_journal_control') ->> 'id' as gx4 \gset
select tt.as(:'u_acc');
select acct_journal_post(tt.today(), 1, 't4b-block-exc', '[{"code":"1110","debit":200},{"code":"4900","credit":200}]'::jsonb, :'c6'::uuid) ->> 'id' as j12 \gset
select tt.chk('T4b block + one-off exception with a reason: posted once, Exceptions row exists', tt.je('t4b-block-exc')=1 and tt.exev('override_exception','w1e_journal_control')=1);
select tt.as(:'u_o');
select set_rule('journal_control_acct_mode','"allow"') is null as ca1 \gset
select tt.as(:'u_acc');
select acct_journal_post(tt.today(), 1, 't4b-allow', '[{"code":"1110","debit":200},{"code":"4900","credit":200}]'::jsonb, gen_random_uuid()) ->> 'id' as j13 \gset
select tt.chk('T4b allow = today', tt.je('t4b-allow')=1);
-- the list of control accounts is a setting
select tt.as(:'u_o');
select set_rule('journal_control_acct_mode','"request"') is null as cr2 \gset
select set_rule('journal_control_prefixes','"5900"') is null as cp1 \gset
select tt.as(:'u_acc');
select acct_journal_post(tt.today(), 1, 't4b-prefix-cash', '[{"code":"1110","debit":200},{"code":"4900","credit":200}]'::jsonb, gen_random_uuid()) ->> 'id' as j14 \gset
select acct_journal_post(tt.today(), 1, 't4b-prefix-exp', '[{"code":"5900","debit":200},{"code":"4900","credit":200}]'::jsonb, gen_random_uuid()) ->> 'pending' as p15 \gset
select tt.chk('T4b the owner can change what counts as a control account: now 5900 is held and cash is not', tt.je('t4b-prefix-cash')=1 and :'p15'='true');
select tt.as(:'u_o');
select set_rule('journal_control_prefixes','"11,1210,13,2100"') is null as cp2 \gset
select set_rule('journal_control_acct_mode','"allow"') is null as ca2 \gset

\echo == T5 requests list, permissions, audit, paste twice, restore
select tt.as(:'u_acc');
select tt.chk('T5 the maker sees his requests (and only his)', (select count(*) from jsonb_array_elements(w1e_requests_list(null,100) -> 'rows') x where (x ->> 'mine')::boolean)=(select jsonb_array_length(w1e_requests_list(null,100) -> 'rows')) and jsonb_array_length(w1e_requests_list(null,100) -> 'rows')>=5);
select tt.as(:'u_x');
select tt.chk('T5 a person with no part sees none', jsonb_array_length(w1e_requests_list(null,100) -> 'rows')=0);
select tt.as(:'u_o');
select tt.chk('T5 the owner sees all journal requests', (select count(*) from jsonb_array_elements(w1e_requests_list(null,100) -> 'rows') x where x ->> 'kind'='journal_control')>=5);
select tt.chk('T5 every rule change is in audit_log', (select count(*) from audit_log where table_name='rules' and record_id in ('journal_loc_check','mapping_type_guard','journal_attach_over','journal_control_acct_mode','journal_control_prefixes'))>=10);
select tt.chk('T5 the books balance after everything', tt.unbalanced()=0);
select tt.chk('T5 the Exceptions list of this package shows the requests and the overrides', (select count(*) from jsonb_array_elements(w1e_exceptions_list(null,500) -> 'rows') x where x ->> 'kind'='w1e_journal_request')>=5
  and (select count(*) from jsonb_array_elements(w1e_exceptions_list(null,500) -> 'rows') x where x ->> 'kind'='override_exception')>=4);
do $r$ begin execute current_setting('w1e.orig_jp'); end $r$;
select tt.chk('T5 the original acct_journal_post is restored (no marker)', position('w1e' in pg_get_functiondef('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'::regprocedure))=0);
\i supabase/phase95.sql
select tt.chk('T5 paste twice: the second paste kept the settings, requests and the 35 type rows', rule_txt('journal_control_acct_mode')='allow' and (select count(*) from w1e_requests where kind='journal_control')>=5 and (select count(*) from w1e_mapping_types)=35);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
