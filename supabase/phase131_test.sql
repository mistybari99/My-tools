-- FRESH DB ONLY. Phase 131 tests (R2-B: to-do list). Build: owner order phase8..99, then phase131 (a copy of the database, then this file):
--   psql -h /tmp -p 5600 -U postgres -d <db> -qAt -f supabase/phase131_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names).
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000013101'
\set u_g '00000000-0000-0000-0000-000000013102'
\set u_g2 '00000000-0000-0000-0000-000000013103'
\set u_a '00000000-0000-0000-0000-000000013104'
\set u_b '00000000-0000-0000-0000-000000013105'
\set u_c '00000000-0000-0000-0000-000000013106'
\set u_x '00000000-0000-0000-0000-000000013107'
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
declare r text; begin execute p_sql into r; return r; end $$;
create or replace function tt.c(p_sql text) returns bigint language plpgsql as $$
declare r bigint; begin execute p_sql into r; return r; end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.titles(j jsonb) returns text language sql immutable as $$ select coalesce(string_agg(x ->> 'title', '|' order by ord), '') from jsonb_array_elements(coalesce(j, '[]'::jsonb)) with ordinality t(x, ord) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner131@s.app','{"full_name":"test_owner131"}'), (:'u_g','test_giver131@s.app','{"full_name":"test_giver131"}'), (:'u_g2','test_giver2131@s.app','{"full_name":"test_giver2131"}'),
 (:'u_a','test_staffa131@s.app','{"full_name":"test_staffa131"}'), (:'u_b','test_staffb131@s.app','{"full_name":"test_staffb131"}'), (:'u_c','test_staffc131@s.app','{"full_name":"test_staffc131"}'),
 (:'u_x','test_pending131@s.app','{"full_name":"test_pending131"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_g', :'u_g2', :'u_a', :'u_b', :'u_c');
insert into user_roles values (:'u_o','owner'),(:'u_g','management'),(:'u_g2','management'),(:'u_a','salesperson'),(:'u_b','salesperson'),(:'u_c','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_a',1),(:'u_b',1),(:'u_c',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_g','todo_assign',null), (:'u_g2','todo_assign',null);

\echo == T0 shape, safe defaults
select tt.chk('T0 phase131 present', to_regprocedure('public._r2b_present()') is not null);
select tt.chk('T0 todo_on and todo_repeat_on: switches, default OFF, labels in bn and en', (select count(*) from rules where key in ('todo_on','todo_repeat_on') and kind = 'switch' and default_value = 'false'::jsonb and coalesce(label_bn,'') <> '' and coalesce(label_en,'') <> '') = 2
  and not rule_on('todo_on') and not rule_on('todo_repeat_on'));
select tt.chk('T0 grant todo_assign defined and held by no role', exists (select 1 from grant_defs where grant_code = 'todo_assign') and not exists (select 1 from rule_grants where grant_code = 'todo_assign'));
select tt.chk('T0 table: RLS on, no browser write', (select relrowsecurity from pg_class where relname = 'r2_todos') and not has_table_privilege('authenticated','public.r2_todos','insert')
  and not has_table_privilege('authenticated','public.r2_todos','update') and not has_table_privilege('authenticated','public.r2_todos','delete') and not has_table_privilege('anon','public.r2_todos','select'));
select tt.chk('T0 API for signed-in users only; helpers closed', has_function_privilege('authenticated','public.r2_todo_mine(boolean)','execute') and not has_function_privilege('anon','public.r2_todo_mine(boolean)','execute')
  and not has_function_privilege('authenticated','public._r2b_repeat_next(public.r2_todos)','execute') and not has_function_privilege('authenticated','public._r2b_json(public.r2_todos)','execute'));

\echo == T1 default OFF: nothing shows, nothing is assigned
select count(*) as audit0 from audit_log \gset
set role authenticated; select tt.as(:'u_o');
select tt.err('T1 OFF: even the owner cannot assign (todo_off)', format($q$select r2_todo_assign('test job', '', null, 'normal', 'person', %L)$q$, :'u_a'), 'todo_off');
select tt.chk('T1 OFF: state is off with zero counts', (r2_todo_state() ->> 'on') = 'false' and (r2_todo_state() ->> 'open') = '0' and (r2_todo_state() ->> 'can_assign') = 'false');
select tt.as(:'u_a');
select tt.chk('T1 OFF: my list and given list are empty', r2_todo_mine(true) = '[]'::jsonb and r2_todo_given() = '[]'::jsonb);
select tt.err('T1 OFF: set is refused', $q$select r2_todo_set(1, 'done')$q$, 'todo_off');
reset role;
select tt.chk('T1 OFF: no row, no audit line', tt.q('select count(*) from r2_todos') = '0' and (select count(*) from audit_log) = :audit0);

\echo == T2 ON: who may assign, validation
set role authenticated; select tt.as(:'u_o'); select set_rule('todo_on', 'true'::jsonb) is null as on1 \gset
reset role;
select tt.chk('T2 todo_on is true', rule_on('todo_on'));
set role authenticated; select tt.as(:'u_a');
select tt.err('T2 staff A cannot assign (not allowed)', format($q$select r2_todo_assign('test job', '', null, 'normal', 'person', %L)$q$, :'u_b'), 'not allowed');
select tt.chk('T2 staff state: on, cannot assign', (r2_todo_state() ->> 'on') = 'true' and (r2_todo_state() ->> 'can_assign') = 'false');
select tt.as(:'u_g');
select tt.chk('T2 giver state: can assign', (r2_todo_state() ->> 'can_assign') = 'true');
select (r2_todo_assign('test clean the oven', 'test detail', tt.today() + 1, 'high', 'person', :'u_a') ->> 'count')::int as n1 \gset
select tt.chk('T2 one task to one person: 1 row', :n1 = 1);
select (r2_todo_assign('test count the boxes', '', tt.today() + 3, 'normal', 'role', 'salesperson') -> 'ids') as ids2 \gset
select tt.chk('T2 a task to the role salesperson becomes one row per person (A and B = 2)', jsonb_array_length(:'ids2'::jsonb) = 2);
select tt.chk('T2 the storekeeper (other role) got nothing from it', tt.q(format('select count(*) from r2_todos where assignee_user = %L and title = %L', :'u_c', 'test count the boxes')) = '0');
select tt.err('T2 a role with nobody in it is refused', $q$select r2_todo_assign('test x', '', null, 'normal', 'role', 'recipe_approver')$q$, 'no_recipients');
select tt.err('T2 unknown role refused', $q$select r2_todo_assign('test x', '', null, 'normal', 'role', 'no_such_role')$q$, 'bad_target');
select tt.err('T2 pending person refused', format($q$select r2_todo_assign('test x', '', null, 'normal', 'person', %L)$q$, :'u_x'), 'bad_target');
select tt.err('T2 bad kind refused', $q$select r2_todo_assign('test x', '', null, 'normal', 'everyone', null)$q$, 'bad_target');
select tt.err('T2 empty title refused', format($q$select r2_todo_assign('  ', '', null, 'normal', 'person', %L)$q$, :'u_a'), 'title_required');
select tt.err('T2 due date in the past refused', format($q$select r2_todo_assign('test x', '', current_date - 3, 'normal', 'person', %L)$q$, :'u_a'), 'bad_date');
select tt.err('T2 bad priority refused', format($q$select r2_todo_assign('test x', '', null, 'huge', 'person', %L)$q$, :'u_a'), 'bad_priority');
select tt.err('T2 a repeat is refused while todo_repeat_on is OFF (repeat_off)', format($q$select r2_todo_assign('test x', '', null, 'normal', 'person', %L, 'daily')$q$, :'u_a'), 'repeat_off');
select tt.err('T2 bad repeat word refused', format($q$select r2_todo_assign('test x', '', null, 'normal', 'person', %L, 'monthly')$q$, :'u_a'), 'bad_repeat');
select gen_random_uuid() as cid \gset
select (r2_todo_assign('test retry job', '', null, 'low', 'role', 'salesperson', 'none', :'cid') ->> 'count')::int as n3 \gset
select tt.chk('T2 retry with the same client id changes nothing: same count, flagged repeat', (r2_todo_assign('test retry job', '', null, 'low', 'role', 'salesperson', 'none', :'cid') ->> 'repeat') = 'true' and :n3 = 2);
reset role;
select tt.chk('T2 the retry added no extra rows (A and B once each)', (select count(*) from r2_todos where title = 'test retry job') = 2);
select tt.chk('T2 total rows now 1 + 2 + 2 = 5', (select count(*) from r2_todos) = 5);

\echo == T3 who sees what
set role authenticated; select tt.as(:'u_a');
select tt.chk('T3 staff A sees exactly his 3 tasks, high priority first', tt.titles(r2_todo_mine()) = 'test clean the oven|test count the boxes|test retry job');
select tt.chk('T3 staff A through the table sees only rows where he is the assignee', tt.c('select count(*) from r2_todos') = 3 and tt.c('select count(*) from r2_todos where assignee_user <> auth.uid()') = 0);
select tt.chk('T3 staff A gave nothing: given list empty', r2_todo_given() = '[]'::jsonb);
select tt.as(:'u_b');
select tt.chk('T3 staff B sees only the 2 role tasks', tt.titles(r2_todo_mine()) = 'test count the boxes|test retry job' and tt.c('select count(*) from r2_todos') = 2);
select tt.as(:'u_c');
select tt.chk('T3 storekeeper C sees nothing', r2_todo_mine() = '[]'::jsonb and tt.c('select count(*) from r2_todos') = 0);
select tt.as(:'u_g');
select tt.chk('T3 giver sees all 5 he gave', jsonb_array_length(r2_todo_given()) = 5 and tt.c('select count(*) from r2_todos') = 5);
select tt.chk('T3 giver given list shows the assignee name and status', (select bool_and(x ->> 'assignee' like 'test_staff%' and x ->> 'status' = 'open') from jsonb_array_elements(r2_todo_given()) x));
select tt.as(:'u_g2');
select tt.chk('T3 a second giver sees none of the first giver''s tasks', r2_todo_given() = '[]'::jsonb and tt.c('select count(*) from r2_todos') = 0);
select tt.as(:'u_o');
select tt.chk('T3 the owner sees all', jsonb_array_length(r2_todo_given()) = 5 and tt.c('select count(*) from r2_todos') = 5);
select tt.chk('T3 the owner''s own list is empty (nothing was given to him)', r2_todo_mine() = '[]'::jsonb);
reset role;

\echo == T4 the assignee moves his own task
set role authenticated; select tt.as(:'u_a');
select (x ->> 'id')::bigint as t_oven from jsonb_array_elements(r2_todo_mine()) x where x ->> 'title' = 'test clean the oven' \gset
select (x ->> 'id')::bigint as t_box_a from jsonb_array_elements(r2_todo_mine()) x where x ->> 'title' = 'test count the boxes' \gset
select (x ->> 'id')::bigint as t_retry_a from jsonb_array_elements(r2_todo_mine()) x where x ->> 'title' = 'test retry job' \gset
select tt.as(:'u_b');
select tt.err('T4 staff B cannot move staff A''s task', format($q$select r2_todo_set(%s, 'done')$q$, :t_oven), 'not allowed');
select tt.as(:'u_a');
select tt.err('T4 cannot-do needs a reason', format($q$select r2_todo_set(%s, 'cannot', '  ')$q$, :t_box_a), 'reason_required');
select tt.err('T4 unknown status refused', format($q$select r2_todo_set(%s, 'cancelled', 'x')$q$, :t_box_a), 'bad_status');
select tt.chk('T4 done with a note', (r2_todo_set(:t_oven, 'done', 'test cleaned with the new brush') ->> 'status') = 'done');
select tt.chk('T4 cannot-do with a reason', (r2_todo_set(:t_box_a, 'cannot', 'test shelf locked') ->> 'status') = 'cannot');
select tt.chk('T4 the same move twice is harmless (flagged repeat)', (r2_todo_set(:t_oven, 'done', 'again') ->> 'repeat') = 'true');
select tt.err('T4 done then cannot is refused (not open)', format($q$select r2_todo_set(%s, 'cannot', 'x')$q$, :t_oven), 'not_open');
select tt.chk('T4 open list now has 1 task (the retry job); done and cannot are hidden', tt.titles(r2_todo_mine()) = 'test retry job');
select tt.chk('T4 with the history flag the done and cannot ones show, open first, with notes', tt.titles(r2_todo_mine(true)) = 'test retry job|test clean the oven|test count the boxes'
  or tt.titles(r2_todo_mine(true)) = 'test retry job|test count the boxes|test clean the oven');
select tt.chk('T4 notes and who/when are stored', (select x ->> 'status_note' = 'test cleaned with the new brush' and x ->> 'status_at' is not null from jsonb_array_elements(r2_todo_mine(true)) x where x ->> 'title' = 'test clean the oven'));
select tt.as(:'u_g');
select tt.chk('T4 the giver sees both notes', (select count(*) from jsonb_array_elements(r2_todo_given()) x where (x ->> 'status' = 'done' and x ->> 'status_note' = 'test cleaned with the new brush') or (x ->> 'status' = 'cannot' and x ->> 'status_note' = 'test shelf locked')) = 2);
select tt.chk('T4 a filter by status works', jsonb_array_length(r2_todo_given('open')) = 3 and jsonb_array_length(r2_todo_given('done')) = 1 and jsonb_array_length(r2_todo_given('cannot')) = 1);
reset role;

\echo == T5 overdue, state counts, ordering
update r2_todos set due_date = tt.today() - 2 where id = :t_retry_a;                               -- simulate that the due date has passed
set role authenticated; select tt.as(:'u_a');
select tt.chk('T5 overdue is flagged on the open task', (select (x ->> 'overdue')::boolean from jsonb_array_elements(r2_todo_mine()) x where (x ->> 'id')::bigint = :t_retry_a));
select tt.chk('T5 state: open 1, overdue 1, next list has it', (r2_todo_state() ->> 'open') = '1' and (r2_todo_state() ->> 'overdue') = '1' and jsonb_array_length(r2_todo_state() -> 'next') = 1);
select tt.chk('T5 a done task is never overdue', (select not bool_or((x ->> 'overdue')::boolean) from jsonb_array_elements(r2_todo_mine(true)) x where x ->> 'status' = 'done'));
select tt.as(:'u_g');
select tt.chk('T5 in the giver list the overdue open task comes first', (r2_todo_given() -> 0 ->> 'id')::bigint = :t_retry_a);
-- ordering in the Home card: overdue, then priority
select r2_todo_assign('test urgent small', '', tt.today() + 5, 'urgent', 'person', :'u_a') is not null as o1 \gset
select r2_todo_assign('test low big', '', null, 'low', 'person', :'u_a') is not null as o2 \gset
select tt.as(:'u_a');
select tt.chk('T5 Home order: overdue first, then urgent, then low', tt.titles(r2_todo_state() -> 'next') = 'test retry job|test urgent small|test low big');
reset role;

\echo == T6 the assigner manages: cancel (reason), reopen; the assignee cannot
set role authenticated; select tt.as(:'u_a');
select tt.err('T6 the assignee cannot cancel or reopen (not allowed)', format($q$select r2_todo_manage(%s, 'cancel', 'x')$q$, :t_retry_a), 'not allowed');
select tt.as(:'u_g2');
select tt.err('T6 another giver cannot cancel it', format($q$select r2_todo_manage(%s, 'cancel', 'x')$q$, :t_retry_a), 'not allowed');
select tt.as(:'u_g');
select tt.err('T6 cancel needs a reason', format($q$select r2_todo_manage(%s, 'cancel', '')$q$, :t_retry_a), 'reason_required');
select tt.chk('T6 the giver cancels with a reason', (r2_todo_manage(:t_retry_a, 'cancel', 'test no longer needed') ->> 'status') = 'cancelled');
select tt.err('T6 a done task cannot be cancelled', format($q$select r2_todo_manage(%s, 'cancel', 'x')$q$, :t_oven), 'not_open');
select tt.chk('T6 the giver reopens the done task', (r2_todo_manage(:t_oven, 'reopen', 'test redo') ->> 'status') = 'open');
select tt.as(:'u_a');
select tt.chk('T6 the cancelled task has left A''s list; the reopened one is back', tt.titles(r2_todo_mine()) like '%test clean the oven%' and tt.titles(r2_todo_mine()) not like '%test retry job%');
select tt.as(:'u_o');
select tt.chk('T6 the owner can manage anyone''s task', (r2_todo_manage(:t_oven, 'cancel', 'test owner cancel') ->> 'status') = 'cancelled');
reset role;
select tt.chk('T6 rows stay: cancelled ones keep who, when and the reason', (select count(*) from r2_todos where status = 'cancelled' and status_by is not null and status_at is not null and status_note is not null) = 2);
select tt.err('T6 nothing is hard-deleted', format('delete from r2_todos where id = %s', :t_oven), 'nothing is deleted');

\echo == T7 repeating duties (setting todo_repeat_on)
set role authenticated; select tt.as(:'u_o'); select set_rule('todo_repeat_on', 'true'::jsonb) is null as r1 \gset
select tt.as(:'u_g');
select (r2_todo_assign('test daily sweep', '', tt.today(), 'normal', 'person', :'u_b', 'daily') -> 'ids' ->> 0)::bigint as d1 \gset
select (r2_todo_assign('test weekly stock', '', tt.today() + 2, 'normal', 'person', :'u_b', 'weekly') -> 'ids' ->> 0)::bigint as w1 \gset
select tt.as(:'u_b');
select tt.chk('T7 state now says repeat is on', (r2_todo_state() ->> 'repeat_on') = 'true');
select (r2_todo_set(:d1, 'done', 'test swept') ->> 'next_id')::bigint as d2 \gset
select tt.chk('T7 marking the daily task done made the next one', :d2 is not null);
reset role;
select tt.chk('T7 next daily: due tomorrow, open, same person and giver, linked to the one before', (select due_date = tt.today() + 1 and status = 'open' and repeat_kind = 'daily' and repeat_parent = :d1 and assignee_user = :'u_b' and assigned_by = :'u_g' from r2_todos where id = :d2));
set role authenticated; select tt.as(:'u_b');
select (r2_todo_set(:w1, 'cannot', 'test no stock room key') ->> 'next_id')::bigint as w2 \gset
select tt.chk('T7 a weekly task that cannot be done still repeats', :w2 is not null);
reset role;
select tt.chk('T7 next weekly: due = the later of (due, today) + 7 = today + 9', (select due_date = tt.today() + 9 from r2_todos where id = :w2));
update r2_todos set due_date = tt.today() - 5 where id = :d2;                                       -- a late one: the next is counted from today
set role authenticated; select tt.as(:'u_b');
select (r2_todo_set(:d2, 'done') ->> 'next_id')::bigint as d3 \gset
reset role;
select tt.chk('T7 finishing late: next daily is due tomorrow (today + 1), not in the past', (select due_date = tt.today() + 1 from r2_todos where id = :d3));
select tt.chk('T7 only one open child at a time', (select count(*) from r2_todos where repeat_parent = :d2 and status = 'open') = 1);
set role authenticated; select tt.as(:'u_o'); select set_rule('todo_repeat_on', 'false'::jsonb) is null as r2 \gset
select tt.as(:'u_b');
select (r2_todo_set(:d3, 'done') ->> 'next_id') is null as no_next \gset
reset role;
select tt.chk('T7 with todo_repeat_on OFF again, finishing a repeating task creates no next one', :'no_next' = 't');

\echo == T8 change log and closed doors
select tt.chk('T8 every assign and move wrote audit_log lines', (select count(*) from audit_log where table_name = 'r2_todos' and action = 'insert') = (select count(*) from r2_todos)
  and (select count(*) from audit_log where table_name = 'r2_todos' and action = 'update') >= 8);
set role authenticated; select tt.as(:'u_a');
select tt.err('T8 a browser cannot insert directly', format($q$insert into r2_todos (title, assignee_user, assigned_by) values ('test sneaky', %L, %L)$q$, :'u_a', :'u_a'), 'permission denied');
select tt.err('T8 a browser cannot update a task directly', $q$update r2_todos set status = 'done'$q$, 'permission denied');
reset role;

\echo == T9 switch OFF again
set role authenticated; select tt.as(:'u_o'); select set_rule('todo_on', 'false'::jsonb) is null as off1 \gset
select tt.as(:'u_a');
select tt.chk('T9 OFF: Home state is off and the list is empty', (r2_todo_state() ->> 'on') = 'false' and r2_todo_mine() = '[]'::jsonb);
select tt.as(:'u_g');
select tt.err('T9 OFF: assigning is refused again', format($q$select r2_todo_assign('test x', '', null, 'normal', 'person', %L)$q$, :'u_a'), 'todo_off');
reset role;

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
