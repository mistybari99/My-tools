-- FRESH DB ONLY. Phase 50 tests (P1 slice 3: payroll + expense shadow copies).
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49 phase50" bash tests/sql/build_fresh_db.sh a50db
--   psql -h /tmp -p 5544 -U postgres -d a50db -qAt -f supabase/phase50_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
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
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager'),(:'k','storekeeper') on conflict do nothing;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant execute on function tt.today() to authenticated, anon;
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'k','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',2) on conflict do nothing;

\echo == T0 shape
select tt.chk('T0 quick_expenses has RLS, no write grants', (select relrowsecurity from pg_class where relname='quick_expenses') and not has_table_privilege('authenticated','quick_expenses','insert') and not has_table_privilege('authenticated','quick_expenses','update'));
select tt.chk('T0 internals closed, browser calls open', not has_function_privilege('authenticated','public._payroll_pair50(bigint,uuid,int,text)','execute') and not has_function_privilege('anon','public.quick_expense_add(int,date,text,text,numeric,text,boolean,text,uuid)','execute')
  and has_function_privilege('authenticated','public.quick_expense_add(int,date,text,text,numeric,text,boolean,text,uuid)','execute') and has_function_privilege('authenticated','public.quick_expense_close_day(int,date)','execute'));
select tt.chk('T0 day-book/journal/P&L functions kept their signatures; bos50 blocks present', position('bos50' in pg_get_functiondef('public._daybook_lines(int[],int[],date,date)'::regprocedure))>0
  and position('bos50' in pg_get_functiondef('public._daybook_lines23(int[],date,date)'::regprocedure))>0 and position('bos50' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0
  and position('bos50' in pg_get_functiondef('public._p27_pl(date,date,int[])'::regprocedure))>0 and position('bos50' in pg_get_functiondef('public._r3q_e2_expense_trend(date,date,int[],jsonb)'::regprocedure))>0);

\echo == T1 payroll: app run wins, the 02-2 sheet becomes a locked shadow
select tt.as(:'o');
select date_trunc('month', tt.today())::date as m0, extract(month from tt.today())::int as mm, extract(year from tt.today())::int as yy \gset
with x as (insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
  ('02-2',1,9201,tt.today(),'submitted',format('{"month":"%s","year":"%s","receipts":[{"name":"Rahim","net":5000,"method":"cash","date":"%s"}],"pay":[]}',:'mm',:'yy',tt.today())::jsonb,'[]',:'s','st') returning id) select id as e22 from x \gset
select tt.chk('T1 before any run the 02-2 salary line is counted in the day book', (select count(*) from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='salary')=1);
select tt.chk('T1 no link yet', not is_shadow('entries', :'e22'));
with x as (insert into payroll_runs (month, location_id, status) values (:'m0', 1, 'draft') returning id) select id as run1 from x \gset
select tt.chk('T1 the form is now a shadow of the run (primary a by default)', is_shadow('entries', :'e22') and not is_shadow('payroll_runs', :'run1')
  and exists (select 1 from shadow_links where domain='payroll' and primary_type='payroll_runs' and primary_id=:'run1' and shadow_type='entries' and shadow_id=:'e22' and state='confirmed'));
select tt.chk('T1 the shadow salary line is gone from the day book (counted once)', (select count(*) from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='salary')=0);
select tt.err('T1 the shadow sheet cannot be edited', format($$update entries set data = jsonb_set(data,'{year}','"2030"') where id='%s'$$, :'e22'), 'shadow_locked');
select tt.err('T1 ... or re-opened', format($$update entries set status='draft' where id='%s'$$, :'e22'), 'shadow_locked');
with u as (update entries set status='approved' where id=:'e22'::uuid returning 1) select count(*)=1 as okap from u \gset
select tt.chk('T1 status moves (approve) are still allowed', :'okap');
update payroll_runs set status='void', void_reason='test' where id=:'run1';
select tt.chk('T1 voiding the run releases the form: it counts again', not is_shadow('entries', :'e22') and (select count(*) from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='salary')=1
  and (select state from shadow_links where domain='payroll' and primary_id=:'run1')='void');
with u as (update entries set data = jsonb_set(data,'{year}',to_jsonb(:'yy'::text)) where id=:'e22'::uuid returning 1) select count(*)=1 as okch from u \gset
select tt.chk('T1 released form can be changed again', :'okch');

\echo == T2 payroll: form arrives AFTER the run
with x as (insert into payroll_runs (month, location_id, status) values ((:'m0'::date - interval '1 month')::date, 1, 'draft') returning id) select id as run2 from x \gset
select extract(month from (:'m0'::date - interval '1 month'))::int as pm, extract(year from (:'m0'::date - interval '1 month'))::int as py \gset
with x as (insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
  ('02-2',1,9202,tt.today(),'draft',format('{"month":"%s","year":"%s"}',:'pm',:'py')::jsonb,'[]',:'s','st') returning id) select id as e23 from x \gset
select tt.chk('T2 a draft sheet is not linked yet', not is_shadow('entries', :'e23'));
update entries set status='submitted' where id=:'e23'::uuid;
select tt.chk('T2 once submitted it becomes the shadow of the existing run', is_shadow('entries', :'e23'));

\echo == T3 payroll: owner makes the FORM primary
select path_switch_set('payroll',1,true,true,'b') is not null as sw \gset
with x as (insert into payroll_runs (month, location_id, status) values (:'m0', 1, 'draft') returning id) select id as run3 from x \gset
select tt.chk('T3 primary=b: the form is primary, the run is the shadow', is_shadow('payroll_runs', :'run3') and not is_shadow('entries', :'e22'));
update payroll_runs set status='void', void_reason='t3' where id=:'run3';

\echo == T4 guards
select path_switch_set('payroll',1,false,true,'a') is not null as sw2 \gset
select tt.err('T4 payroll path A locked: a new run is refused', format($$insert into payroll_runs (month, location_id, status) values (%L, 1, 'draft')$$, (:'m0'::date - interval '2 months')::date), 'path_locked');
select path_switch_set('payroll',1,true,false,'a') is not null as sw3 \gset
select tt.err('T4 payroll path B locked: a new 02-2 is refused', format($$insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values ('02-2',1,9299,%L,'draft','{}','[]','%s','st')$$, tt.today(), :'s'), 'path_locked');
with u as (insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values ('02-2',2,9298,tt.today(),'draft','{}','[]',:'s','st') returning 1) select count(*)=1 as okoth from u \gset
select tt.chk('T4 other places and other forms are not affected', :'okoth');
select path_switch_set('payroll',1,true,true,'a') is not null as sw4 \gset

\echo == T5 quick expense
select tt.as(:'s');
select quick_expense_add(1, tt.today(), 'transport', 'Rickshaw', 120, 'cash', true, null, 'b0000000-0000-0000-0000-0000000000b1') ->> 'id' as q1 \gset
select quick_expense_add(1, tt.today(), 'staff_meal', 'Tea', 80, 'cash', false, null, null) ->> 'id' as q2 \gset
select tt.chk('T5 two quick expenses saved', (select count(*) from quick_expenses where location_id=1 and status='done')=2);
select tt.chk('T5 same client key = same row', (quick_expense_add(1, tt.today(), 'transport', 'Rickshaw', 120, 'cash', true, null, 'b0000000-0000-0000-0000-0000000000b1') ->> 'duplicate')='true' and (select count(*) from quick_expenses)=2);
select tt.chk('T5 each one has a pending shadow (10-2 owed)', (select count(*) from shadow_links where domain='expense' and state='pending')=2);
select tt.err('T5 amount must be positive', $$select quick_expense_add(1, tt.today(), 'transport', 'x', 0)$$, 'bad_amount');
select tt.err('T5 head needed', $$select quick_expense_add(1, tt.today(), ' ', 'x', 5)$$, 'head_needed');
select tt.err('T5 no future date', $$select quick_expense_add(1, tt.today()+1, 'transport', 'x', 5)$$, 'bad_date');
select tt.as(:'k');
select tt.err('T5 a user of another place cannot add', $$select quick_expense_add(1, tt.today(), 'transport', 'x', 5)$$, 'not allowed');
select tt.as(:'s');
select tt.chk('T5 the day book counts both quick expenses (200)', (select coalesce(sum(amount),0) from _daybook_lines23(array[1], tt.today(), tt.today()) where src='quick_expense')=200);
select quick_expense_day(1, tt.today()) as dy \gset
select tt.chk('T5 day view: total 200, 2 owed', (:'dy'::jsonb->>'total')::numeric=200 and (:'dy'::jsonb->>'owed')::int=2);
select tt.err('T5 void needs a note', format($$select quick_expense_void('%s','')$$, :'q2'), 'note_needed');
select quick_expense_void(:'q2'::uuid, 'typed twice') ->> 'status' as vs \gset
select tt.chk('T5 void works; its pending shadow is voided; day book now 120', :'vs'='void' and (select state from shadow_links where primary_id=:'q2')='void'
  and (select coalesce(sum(amount),0) from _daybook_lines23(array[1], tt.today(), tt.today()) where src='quick_expense')=120);
select tt.err('T5 a quick expense cannot be changed', format($$update quick_expenses set amount=1 where id='%s'$$, :'q1'), 'append_only');
select quick_expense_add(1, tt.today(), 'staff_meal', 'Tea', 80) ->> 'id' as q3 \gset

\echo == T6 close the day: one draft 10-2 as the locked shadow
select quick_expense_close_day(1, tt.today()) as cd \gset
select tt.chk('T6 one voucher made for the 2 live quick entries', (:'cd'::jsonb->>'made')::int=2 and (:'cd'::jsonb->>'entry_id') is not null);
select (:'cd'::jsonb->>'entry_id')::uuid as v1 \gset
select tt.chk('T6 the voucher is a draft with 2 lines (120 + 80)', (select status from entries where id=:'v1'::uuid)='draft' and (select jsonb_array_length(data->'lines') from entries where id=:'v1'::uuid)=2
  and (select sum((x->>'amount')::numeric) from entries e, jsonb_array_elements(e.data->'lines') x where e.id=:'v1'::uuid)=200);
select tt.chk('T6 both shadows confirmed, pointing at the voucher; it is a shadow', (select count(*) from shadow_links where domain='expense' and state='confirmed' and shadow_id=:'v1')=2 and is_shadow('entries', :'v1'));
select tt.chk('T6 closing again makes nothing', (quick_expense_close_day(1, tt.today()) ->> 'made')::int=0);
select tt.err('T6 a quick expense inside a voucher cannot be voided', format($$select quick_expense_void('%s','oops')$$, :'q1'), 'already_in_voucher');
select submit_entry(:'v1'::uuid) is not null as sub \gset
select tt.chk('T6 submitted shadow voucher is NOT counted: expense lines in the day book come only from the quick entries (200)',
  (select coalesce(sum(amount),0) from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='expense' and src='entry')=0
  and (select coalesce(sum(amount),0) from _daybook_lines23(array[1], tt.today(), tt.today()) where src='quick_expense')=200);
select tt.err('T6 the submitted shadow voucher is locked', format($$update entries set data = jsonb_set(data,'{lines,0,amount}','1') where id='%s'$$, :'v1'), 'shadow_locked');
select tt.as(:'o');
with u as (insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
  ('10-2',1,9501,tt.today(),'approved','{"lines":[{"head":"transport","amount":"50","receipt":"yes"}]}','[]',:'s','st') returning 1) select count(*)=1 as okv from u \gset
select tt.chk('T6 a normal voucher (not a shadow) is still counted once', :'okv'
  and (select coalesce(sum(amount),0) from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='expense' and src='entry')=50);

\echo == T7 journal + P&L + reports count once
select acct_set_start(tt.today() - 1) is not null as st \gset
select set_rule('accounting_on','true') is null as on1 \gset
select tt.as(:'o');
select acct_post_pending(true) as dr \gset
select tt.chk('T7 dry run: quick expenses (2) and the normal approved voucher (1) post; the shadow voucher does not', (:'dr'::jsonb->'by_type'->>'quick_expense')::int=2 and (:'dr'::jsonb->'by_type'->>'expense_voucher')::int=1);
select acct_post_pending(false)->>'posted' as pn \gset
select tt.chk('T7 posted 3 documents; journal expense total = 250 (200 quick + 50 voucher)', :'pn'::int=3
  and (select coalesce(sum(l.debit),0) from journal_lines l join journal_entries j on j.id=l.entry_id join coa_accounts a on a.id=l.account_id where a.type='expense' and j.source_type in ('quick_expense','expense_voucher'))=250);
select tt.chk('T7 quick expense journal lines: transport -> expense account, credit cash', exists (select 1 from journal_entries j join journal_lines l on l.entry_id=j.id join acct_mappings m on m.account_id=l.account_id and m.key='pay_cash' where j.source_type='quick_expense' and l.credit>0));
select tt.chk('T7 day book vs journal: expense no longer differs (quick entries count in both); only the 02-2 salary (no journal source yet) does', jsonb_array_length(daybook_vs_journal(tt.today()-1, tt.today())->'rows')=1
  and daybook_vs_journal(tt.today()-1, tt.today())->'rows'->0->>'kind' in ('salary','salary_form'));
select _p27_pl(tt.today(), tt.today(), array[1]) as plr \gset
select tt.chk('T7 P&L expense = 250 (quick 200 + voucher 50), the shadow voucher is not added again', (select o_exp from _p27_pl(tt.today(), tt.today(), array[1]))=250);
select tt.chk('T7 expense trend sees 250 in total', (select coalesce(sum((x->>'current')::numeric),0) from _r3q_e2_expense_trend(tt.today(), tt.today(), array[1], '{}'::jsonb) x)=250);
select tt.chk('T7 count-once check is clean', jsonb_array_length(shadow_count_once_check()->'shadow_in_journal')=0);

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
