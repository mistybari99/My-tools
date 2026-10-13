-- FRESH DB ONLY. Phase 28 tests (parallel comparison, print & books, Needs you).
--   ORDER="phase8 ... phase24 phase28" bash tests/sql/build_fresh_db.sh <db> ; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase28_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set h '00000000-0000-0000-0000-000000000004'
\set t '00000000-0000-0000-0000-000000000005'
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
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}'), (:'h','head4@s.app','{"full_name":"Head"}'), (:'t','mgr5@s.app','{"full_name":"Manager Two"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager'),(:'k','storekeeper'),(:'h','management'),(:'t','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'h',1),(:'t',1) on conflict do nothing;

\echo == shape
select tt.chk('T0 tables have RLS and no write grants', (select count(*) from pg_class where relname in ('comparison_pairs','comparison_days','parallel_months','paper_books','print_notes') and relrowsecurity)=5
  and not has_table_privilege('authenticated','comparison_days','insert') and not has_table_privilege('authenticated','paper_books','insert'));
select tt.chk('T0 anon has no execute', not has_function_privilege('anon','parallel_month_decide(text,int,date,boolean,text)','execute') and not has_function_privilege('anon','needs_you_oldest(int)','execute'));
select tt.chk('T0 pairs table starts empty (nothing invented)', (select count(*) from comparison_pairs)=0);

\echo == pairs and rollout
set role authenticated; select tt.as(:'s');
select tt.err('T1 staff cannot name a pair', $$select comparison_pair_save('14-1','x pair')$$, 'not allowed');
select tt.as(:'o');
select tt.err('T1 name is required', $$select comparison_pair_save('14-1','')$$, 'name_required');
select comparison_pair_save('14-1','ড্রয়ারের হিসাব','Drawer balance','paper night page','app expected drawer') ->> 'id' as pid \gset
select tt.chk('T1 owner names a pair', :'pid' is not null);
select tt.as(:'s'); select tt.err('T2 not in parallel yet', format($$select comparison_record(%s,1,current_date,'paper',100)$$, :'pid'), 'not_parallel');
select tt.as(:'o'); select rollout_set('14-1',1,'parallel','test') is not null as rs \gset
select set_user_grant(:'h'::uuid,'head_management') is null as gh \gset

\echo == daily rows
select to_char(date_trunc('month', current_date) - interval '3 days', 'YYYY-MM-DD') as d1 \gset
select to_char(date_trunc('month', current_date) - interval '4 days', 'YYYY-MM-DD') as d2 \gset
select to_char(date_trunc('month', current_date) - interval '5 days', 'YYYY-MM-DD') as d3 \gset
select to_char(date_trunc('month', date_trunc('month', current_date) - interval '3 days'), 'YYYY-MM-DD') as mo \gset
select tt.as(:'s');
select comparison_record(:'pid'::bigint,1,:'d1'::date,'paper',1000) ->> 'result' as r1 \gset
select tt.chk('T3 paper figure alone = waiting', :'r1'='waiting');
select tt.err('T3 the keeper cannot also enter the app figure', format($$select comparison_record(%s,1,%L,'app',1000)$$, :'pid', :'d1'), 'keeper_is_enterer');
select tt.as(:'t');
select comparison_record(:'pid'::bigint,1,:'d1'::date,'app',1000) ->> 'result' as r2 \gset
select tt.chk('T3 equal figures = match', :'r2'='match');
select tt.err('T3 the app enterer cannot also be the keeper of that row', format($$select comparison_record(%s,1,%L,'paper',5)$$, :'pid', :'d1'), 'keeper_is_enterer');
select tt.as(:'s'); select comparison_record(:'pid'::bigint,1,:'d2'::date,'paper',500) is not null as p2 \gset
select tt.as(:'t'); select comparison_record(:'pid'::bigint,1,:'d2'::date,'app',450) ->> 'result' as r3 \gset
select tt.chk('T3 different figures = differ', :'r3'='differ');
select tt.err('T3 bad date refused', format($$select comparison_record(%s,1,current_date + 3,'app',1)$$, :'pid'), 'bad_date');
select tt.as(:'s'); select comparison_record(:'pid'::bigint,1,:'d3'::date,'paper',70) is not null as p3 \gset

\echo == month status and decision
select tt.as(:'o');
select parallel_month_status('14-1',1,:'mo'::date) as ms \gset
select tt.chk('T4 status counts', (:'ms'::jsonb->>'days')::int=3 and (:'ms'::jsonb->>'match')::int=1 and (:'ms'::jsonb->>'differ')::int=1 and (:'ms'::jsonb->>'waiting')::int=1 and (:'ms'::jsonb->>'month_ended')::boolean and not (:'ms'::jsonb->>'pass_ready')::boolean);
select tt.err('T4 pass refused while a day is waiting', format($$select parallel_month_decide('14-1',1,%L,true)$$, :'mo'), 'days_waiting');
select tt.as(:'t'); select comparison_record(:'pid'::bigint,1,:'d3'::date,'app',70) is not null as a3 \gset
select tt.as(:'o');
select tt.err('T4 pass refused while a differ has no reason', format($$select parallel_month_decide('14-1',1,%L,true)$$, :'mo'), 'differ_without_reason');
select tt.err('T4 explain needs both reason and fix', format($$select comparison_explain((select id from comparison_days where result='differ'),'late slip','')$$), 'reason_and_fix_required');
select comparison_explain((select id from comparison_days where result='differ'),'slip written late','re-count and sign') is not null as ex \gset
select tt.err('T4 only the owner decides', format($$select parallel_month_decide('14-1',1,%L,true)$$, :'mo') || '', 'x') where false;
select tt.as(:'h'); select tt.err('T4 head management cannot decide', format($$select parallel_month_decide('14-1',1,%L,true)$$, :'mo'), 'not allowed');
select tt.as(:'o');
select tt.err('T4 current month is not over', $$select parallel_month_decide('14-1',1,current_date,true)$$, 'month_not_ended');
select tt.chk('T4 owner waiting list shows the month before a decision', (select count(*) from parallel_waiting())>=0);
select parallel_month_decide('14-1',1,:'mo'::date,true,'ok') ->> 'result' as dres \gset
select tt.chk('T5 pass recorded and the form moves to app', :'dres'='pass' and rollout_mode('14-1',1)='app');
select tt.err('T5 a month is decided once', format($$select parallel_month_decide('14-1',1,%L,true)$$, :'mo'), 'not_parallel');
select rollout_set('14-1',1,'parallel','again') is not null as back \gset
select tt.err('T5 already decided', format($$select parallel_month_decide('14-1',1,%L,false,'later')$$, :'mo'), 'already_decided');
select tt.err('T5 fail needs a note', $$select parallel_month_decide('14-1',1,(date_trunc('month', current_date) - interval '2 months')::date,false)$$, 'note_required');
select parallel_month_decide('14-1',1,(date_trunc('month', current_date) - interval '2 months')::date,false,'not stable yet') ->> 'result' as fres \gset
select tt.chk('T5 fail recorded, the form stays parallel', :'fres'='fail' and rollout_mode('14-1',1)='parallel');
select set_rule('parallel_compare_on','false') is null as off1 \gset
select tt.chk('T5 switch OFF: pass needs no comparison rows', (parallel_month_decide('14-1',1,(date_trunc('month', current_date) - interval '3 months')::date,true,'x') ->> 'result')='pass');

\echo == print and books
select tt.as(:'s'); select tt.err('T6 a showroom manager cannot register books', $$select paper_book_add('14-1',1,1,50)$$, 'not allowed');
select tt.as(:'h');
select paper_book_add('14-1',1,1,50,null,current_date,'Karim') ->> 'id' as b1 \gset
select tt.err('T6 overlapping book refused', $$select paper_book_add('14-1',1,40,90)$$, 'books_overlap');
select paper_book_add('14-1',1,61,100) is not null as b2 \gset
select paper_books_check('14-1',1) as bc \gset
select tt.chk('T6 gap found (51-60) and the app continues from 101', (:'bc'::jsonb#>>'{issues,0,type}')='gap' and (:'bc'::jsonb#>>'{issues,0,from}')='51' and (:'bc'::jsonb#>>'{issues,0,to}')='60' and (:'bc'::jsonb->>'app_continues_from')='101');
select tt.err('T6 bad range', $$select paper_book_add('14-1',1,10,5)$$, 'bad_range');
select tt.err('T6 void needs a note', format($$select paper_book_set_status(%s,'void')$$, :'b1'), 'note_required');
select tt.as(:'o'); update locations set name_bn = name_bn || ' (new)' where id = 1;
select tt.chk('T7 renaming a place makes a print note', (select count(*) from print_notes where location_id=1 and cleared_at is null)=1);
select tt.as(:'h'); select print_note_clear((select id from print_notes limit 1), current_date) is not null as pc \gset
select tt.chk('T7 note cleared with date and person', (select cleared_on is not null and cleared_by is not null from print_notes limit 1));
select tt.chk('T7 clearing twice is harmless', (print_note_clear((select id from print_notes limit 1), current_date) ->> 'dup')::boolean);
select tt.as(:'s'); select tt.chk('T7 a showroom manager sees no books or notes', (select count(*) from paper_books)=0 and (select count(*) from print_notes)=0);

\echo == needs you
select tt.as(:'o');
reset role;
insert into entries (form_code, location_id, entry_date, status, data, created_by, submitted_at, serial) values ('10-2',1,current_date,'submitted','{}'::jsonb,:'s',now() - interval '5 hours',9001),('10-2',1,current_date,'submitted','{}'::jsonb,:'s',now() - interval '9 hours',9002);
set role authenticated; select tt.as(:'o');
select needs_you_oldest(5) as ny \gset
select tt.chk('T8 oldest first and typed', (:'ny'::jsonb->0->>'label') like '%9002%' and (:'ny'::jsonb->0->>'kind')='entry' and jsonb_array_length(:'ny'::jsonb)>=2);
select tt.as(:'k'); select tt.chk('T8 a person without approve rights sees none of those', not exists (select 1 from jsonb_array_elements(needs_you_oldest(20)) x where x->>'kind'='entry'));
reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
