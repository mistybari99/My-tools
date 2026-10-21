-- FRESH DB ONLY. Phase 130 tests (R2-A: announcements). Build: owner order phase8..99, then phase130 (a copy of the database, then this file):
--   psql -h /tmp -p 5600 -U postgres -d <db> -qAt -f supabase/phase130_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Every figure is hand-counted above its check.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000013001'
\set u_p '00000000-0000-0000-0000-000000013002'
\set u_pl '00000000-0000-0000-0000-000000013003'
\set u_a '00000000-0000-0000-0000-000000013004'
\set u_b '00000000-0000-0000-0000-000000013005'
\set u_c '00000000-0000-0000-0000-000000013006'
\set u_h '00000000-0000-0000-0000-000000013007'
\set u_x '00000000-0000-0000-0000-000000013008'
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
declare r bigint; begin execute p_sql into r; return r; end $$;                       -- a count run as the CURRENT role (so RLS applies)
create or replace function tt.has(j jsonb, p_id bigint) returns boolean language sql immutable as $$ select exists (select 1 from jsonb_array_elements(coalesce(j, '[]'::jsonb)) x where (x ->> 'id')::bigint = p_id) $$;
create or replace function tt.ids(j jsonb) returns text language sql immutable as $$ select coalesce(string_agg(x ->> 'id', ',' order by (x ->> 'id')::bigint), '') from jsonb_array_elements(coalesce(j, '[]'::jsonb)) x $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner130@s.app','{"full_name":"test_owner130"}'), (:'u_p','test_poster130@s.app','{"full_name":"test_poster130"}'), (:'u_pl','test_posterloc130@s.app','{"full_name":"test_posterloc130"}'),
 (:'u_a','test_staffa130@s.app','{"full_name":"test_staffa130"}'), (:'u_b','test_staffb130@s.app','{"full_name":"test_staffb130"}'), (:'u_c','test_staffc130@s.app','{"full_name":"test_staffc130"}'),
 (:'u_h','test_hr130@s.app','{"full_name":"test_hr130"}'), (:'u_x','test_pending130@s.app','{"full_name":"test_pending130"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_p', :'u_pl', :'u_a', :'u_b', :'u_c', :'u_h');       -- u_x stays pending (not an active login)
insert into user_roles values (:'u_o','owner'),(:'u_p','salesperson'),(:'u_pl','salesperson'),(:'u_a','salesperson'),(:'u_b','salesperson'),(:'u_c','storekeeper'),(:'u_h','hr') on conflict do nothing;
insert into user_locations values (:'u_p',1),(:'u_pl',1),(:'u_a',1),(:'u_b',2),(:'u_c',1),(:'u_h',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_p','announce_post',null), (:'u_pl','announce_post',1);

\echo == T0 shape, safe defaults, nothing shared patched, closed doors
select tt.chk('T0 phase130 present', to_regprocedure('public._r2a_present()') is not null);
select tt.chk('T0 announce_on exists, switch, default OFF, bn + en label, hint', (select kind = 'switch' and default_value = 'false'::jsonb and coalesce(label_bn,'') <> '' and coalesce(label_en,'') <> '' and coalesce(hint_en,'') <> '' from rules where key = 'announce_on') and not rule_on('announce_on'));
select tt.chk('T0 grant announce_post is defined and held by NO role by default', exists (select 1 from grant_defs where grant_code = 'announce_post') and not exists (select 1 from rule_grants where grant_code = 'announce_post'));
select tt.chk('T0 no shared function carries r2 text (nothing patched)', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname not like '%r2%' and p.prosrc ~ 'r2_announce') = 0);
select tt.chk('T0 tables: RLS on, browsers cannot write', (select bool_and(relrowsecurity) from pg_class where relname in ('r2_announcements','r2_announce_seen'))
  and not has_table_privilege('authenticated','public.r2_announcements','insert') and not has_table_privilege('authenticated','public.r2_announcements','update') and not has_table_privilege('authenticated','public.r2_announcements','delete')
  and not has_table_privilege('authenticated','public.r2_announce_seen','insert') and not has_table_privilege('anon','public.r2_announcements','select'));
select tt.chk('T0 API for signed-in users only; helper closed',
  has_function_privilege('authenticated','public.r2_announce_post(text,text,boolean,text,text,timestamptz,timestamptz,uuid)','execute') and not has_function_privilege('anon','public.r2_announce_post(text,text,boolean,text,text,timestamptz,timestamptz,uuid)','execute')
  and not has_function_privilege('anon','public.r2_announce_active()','execute') and not has_function_privilege('authenticated','public._r2_ann_audience(bigint)','execute'));

\echo == T1 default OFF: nothing shows, nothing posts, nothing is written
select count(*) as audit0 from audit_log \gset
set role authenticated;
select tt.as(:'u_o');
select tt.err('T1 OFF: even the owner cannot post (announce_off)', $q$select r2_announce_post('test hello', '', false, 'all', null)$q$, 'announce_off');
select tt.chk('T1 OFF: state says off, nobody can post', (r2_announce_state() ->> 'on') = 'false' and (r2_announce_state() ->> 'can_post') = 'false');
select tt.as(:'u_p');
select tt.err('T1 OFF: a designated poster cannot post either', $q$select r2_announce_post('test hello', '', false, 'all', null)$q$, 'announce_off');
select tt.as(:'u_a');
select tt.chk('T1 OFF: active list is empty', r2_announce_active() = '[]'::jsonb);
select tt.err('T1 OFF: seen is refused', $q$select r2_announce_seen(1)$q$, 'announce_off');
reset role;
select tt.chk('T1 OFF: no row anywhere and no audit line written by the feature', tt.q('select count(*) from r2_announcements') = '0' and tt.q('select count(*) from r2_announce_seen') = '0' and (select count(*) from audit_log) = :audit0);

\echo == T2 switch ON by the owner (set_rule), who may post
select tt.as(:'u_o');
set role authenticated;
select set_rule('announce_on', 'true'::jsonb) is null as on1 \gset
reset role;
select tt.chk('T2 announce_on is now true', rule_on('announce_on'));
set role authenticated;
select tt.as(:'u_a');
select tt.err('T2 a plain staff member cannot post (not allowed)', $q$select r2_announce_post('test hello', '', false, 'all', null)$q$, 'not allowed');
select tt.chk('T2 staff state: on, cannot post', (r2_announce_state() ->> 'on') = 'true' and (r2_announce_state() ->> 'can_post') = 'false');
select tt.as(:'u_o');
select (r2_announce_post('test all hands', 'test body text', false, 'all', null) ->> 'id')::bigint as a_all \gset
select tt.chk('T2 owner posted to everyone: audience = 7 active logins (pending one not counted)', (r2_announce_post('test all hands 2', '', false, 'all', null) ->> 'audience')::int = 7);
select tt.as(:'u_p');
select tt.chk('T2 grant holder (no place limit) can post to a role', (r2_announce_post('test sales role', 'x', false, 'role', 'salesperson') ->> 'audience')::int = 4);
select (r2_announce_post('test sales role 2', 'x', false, 'role', 'salesperson', now() - interval '1 hour', null) ->> 'id')::bigint as a_role \gset
select (r2_announce_post('test place one', 'x', true, 'location', '1') ->> 'id')::bigint as a_loc1 \gset
select (r2_announce_post('test place two', 'x', false, 'location', '2') ->> 'id')::bigint as a_loc2 \gset
select (r2_announce_post('test to staff a', 'x', false, 'person', :'u_a') ->> 'id')::bigint as a_pa \gset
select (r2_announce_post('test to storekeeper', 'x', false, 'role', 'storekeeper') ->> 'id')::bigint as a_store \gset
select tt.err('T2 bad role is refused', $q$select r2_announce_post('test x', '', false, 'role', 'no_such_role')$q$, 'bad_target');
select tt.err('T2 bad place text is refused', $q$select r2_announce_post('test x', '', false, 'location', 'abc')$q$, 'bad_target');
select tt.err('T2 a pending (not active) person is refused', format($q$select r2_announce_post('test x', '', false, 'person', %L)$q$, :'u_x'), 'bad_target');
select tt.err('T2 empty title is refused', $q$select r2_announce_post('   ', 'x', false, 'all', null)$q$, 'title_required');
select tt.err('T2 an end time in the past is refused', $q$select r2_announce_post('test x', '', false, 'all', null, null, now() - interval '1 hour')$q$, 'bad_date');
select tt.err('T2 an end before the start is refused', $q$select r2_announce_post('test x', '', false, 'all', null, now() + interval '2 hour', now() + interval '1 hour')$q$, 'bad_date');
select tt.err('T2 unknown kind is refused', $q$select r2_announce_post('test x', '', false, 'everybody', null)$q$, 'bad_target');
-- idempotent retry with a client id
select gen_random_uuid() as cid \gset
select (r2_announce_post('test retry', '', false, 'all', null, null, null, :'cid') ->> 'id')::bigint as a_c1 \gset
select tt.chk('T2 a retry with the same client id returns the same row and flags repeat', (r2_announce_post('test retry', '', false, 'all', null, null, null, :'cid') ->> 'id')::bigint = :a_c1
  and (r2_announce_post('test retry', '', false, 'all', null, null, null, :'cid') ->> 'repeat') = 'true');
reset role;
select tt.chk('T2 the retry did not add a second row', (select count(*) from r2_announcements where title = 'test retry') = 1);
-- future one, for the time tests
set role authenticated; select tt.as(:'u_p');
select (r2_announce_post('test later', 'x', false, 'all', null, now() + interval '3 hour', now() + interval '5 hour') ->> 'id')::bigint as a_future \gset
select (r2_announce_post('test short', 'x', false, 'all', null, null, now() + interval '1 hour') ->> 'id')::bigint as a_short \gset
reset role;

\echo == T3 who sees what (the ticker function AND the table policy)
set role authenticated;
select tt.as(:'u_a');   -- salesperson, place 1
select tt.chk('T3 staff A sees: all x3 (all hands, all hands 2, retry) + short + role (2 sales role posts) + place 1 + person A; NOT place 2, NOT storekeeper role, NOT the future one',
  tt.ids(r2_announce_active()) = (select string_agg(i::text, ',' order by i) from unnest(array[:a_all, :a_all + 1, :a_c1, :a_short, :a_role - 1, :a_role, :a_loc1, :a_pa]) i));
select tt.chk('T3 urgent first: the first item is the urgent place-one message', (r2_announce_active() -> 0 ->> 'id')::bigint = :a_loc1);
select tt.chk('T3 table policy agrees for staff A (same rows as the function, plus nothing posted by him)', tt.c('select count(*) from r2_announcements') = 8);
select tt.chk('T3 staff A cannot read an announcement addressed to place 2 or to the storekeeper role', tt.c(format('select count(*) from r2_announcements where id in (%s,%s,%s)', :a_loc2, :a_store, :a_future)) = 0);
select tt.as(:'u_b');   -- salesperson, place 2
select tt.chk('T3 staff B sees: all x3 + short + role x2 + place 2; NOT place 1, NOT person A', tt.ids(r2_announce_active()) = (select string_agg(i::text, ',' order by i) from unnest(array[:a_all, :a_all + 1, :a_c1, :a_short, :a_role - 1, :a_role, :a_loc2]) i));
select tt.as(:'u_c');   -- storekeeper, place 1
select tt.chk('T3 storekeeper C sees: all x3 + short + place 1 + storekeeper role; NOT the sales role posts', tt.ids(r2_announce_active()) = (select string_agg(i::text, ',' order by i) from unnest(array[:a_all, :a_all + 1, :a_c1, :a_short, :a_loc1, :a_store]) i));
select tt.as(:'u_x');   -- pending login
select tt.chk('T3 a pending (not active) login sees nothing at all', r2_announce_active() = '[]'::jsonb and tt.c('select count(*) from r2_announcements') = 0);
select tt.as(:'u_o');
select tt.chk('T3 owner reads every announcement through the table', tt.c('select count(*) from r2_announcements') = 11);
select tt.chk('T3 the owner bar shows only what is addressed to the owner: all x3 + short', tt.ids(r2_announce_active()) = (select string_agg(i::text, ',' order by i) from unnest(array[:a_all, :a_all + 1, :a_c1, :a_short]) i));
select tt.as(:'u_p');
select tt.chk('T3 the poster reads what he posted (9) plus what is addressed to him and live (all x3 + short are his or the owner''s)', tt.c('select count(*) from r2_announcements where created_by = auth.uid()') = 9);
reset role;

\echo == T4 time and status: expired, withdrawn
update r2_announcements set starts_at = now() - interval '3 hour', ends_at = now() - interval '1 minute' where id = :a_short;      -- simulate that its time ran out
set role authenticated; select tt.as(:'u_a');
select tt.chk('T4 an expired announcement leaves the bar and the table view', not tt.has(r2_announce_active(), :a_short) and tt.c(format('select count(*) from r2_announcements where id = %s', :a_short)) = 0);
reset role;
update r2_announcements set starts_at = now() - interval '1 minute', ends_at = now() + interval '2 hour' where id = :a_future;        -- simulate that its time came
set role authenticated; select tt.as(:'u_a');
select tt.chk('T4 once its start time has come it appears', tt.has(r2_announce_active(), :a_future));

\echo == T5 read receipts
select tt.chk('T5 before: not seen', (select (x ->> 'seen')::boolean from jsonb_array_elements(r2_announce_active()) x where (x ->> 'id')::bigint = :a_loc1) = false);
select (r2_announce_seen(:a_loc1) ->> 'seen')::boolean as s1 \gset
select tt.chk('T5 staff A marks the place-one message seen', :'s1' = 't');
select tt.chk('T5 the same call twice is harmless (still one receipt)', (r2_announce_seen(:a_loc1) ->> 'seen')::boolean and tt.c(format('select count(*) from r2_announce_seen where announcement_id = %s', :a_loc1)) = 1);
select tt.chk('T5 after: the bar says seen', (select (x ->> 'seen')::boolean from jsonb_array_elements(r2_announce_active()) x where (x ->> 'id')::bigint = :a_loc1) = true);
select tt.err('T5 staff A cannot mark seen an announcement for place 2', format('select r2_announce_seen(%s)', :a_loc2), 'not allowed');
select tt.err('T5 staff A cannot mark seen an announcement that does not exist', $q$select r2_announce_seen(999999)$q$, 'not allowed');
select tt.err('T5 staff A cannot read the receipts of the message (only poster and owner)', format('select r2_announce_receipts(%s)', :a_loc1), 'not allowed');
select tt.chk('T5 staff A sees only his own receipt rows', tt.c('select count(*) from r2_announce_seen') = 1 and tt.c('select count(*) from r2_announce_seen where user_id = auth.uid()') = 1);
select tt.as(:'u_c'); select r2_announce_seen(:a_loc1) is not null as s2 \gset            -- storekeeper C, place 1, also reads it
select tt.as(:'u_p');
select tt.chk('T5 the poster sees who has read it: A and C, with times', jsonb_array_length(r2_announce_receipts(:a_loc1) -> 'seen') = 2 and (r2_announce_receipts(:a_loc1) -> 'seen' -> 0 ->> 'seen_at') is not null);
select tt.chk('T5 the poster sees who has NOT read it: the other place-one people (test_poster130, test_posterloc130, test_hr130) = 3', jsonb_array_length(r2_announce_receipts(:a_loc1) -> 'unseen') = 3);
select tt.chk('T5 the poster reads the receipt rows of his message through the table', tt.c(format('select count(*) from r2_announce_seen where announcement_id = %s', :a_loc1)) = 2);
select tt.as(:'u_pl');   -- another poster: not the author
select tt.err('T5 another poster cannot see receipts of a message he did not post', format('select r2_announce_receipts(%s)', :a_loc1), 'not allowed');
select tt.as(:'u_o');
select tt.chk('T5 the owner can read every receipt list', jsonb_array_length(r2_announce_receipts(:a_loc1) -> 'seen') = 2);
reset role;
select tt.err('T5 a receipt can never be changed', format('update r2_announce_seen set seen_at = now() where announcement_id = %s', :a_loc1), 'never changed or removed');
select tt.err('T5 a receipt can never be removed', format('delete from r2_announce_seen where announcement_id = %s', :a_loc1), 'never changed or removed');

\echo == T6 withdraw
set role authenticated; select tt.as(:'u_a');
select tt.err('T6 staff A cannot withdraw', format($q$select r2_announce_withdraw(%s, 'x')$q$, :a_loc1), 'not allowed');
select tt.as(:'u_pl');
select tt.err('T6 a poster cannot withdraw another poster''s message', format($q$select r2_announce_withdraw(%s, 'x')$q$, :a_loc1), 'not allowed');
select tt.as(:'u_p');
select tt.err('T6 withdrawing needs a reason', format($q$select r2_announce_withdraw(%s, '  ')$q$, :a_loc1), 'reason_required');
select (r2_announce_withdraw(:a_loc1, 'test wrong place') ->> 'status') as w1 \gset
select tt.chk('T6 the poster withdraws his message', :'w1' = 'withdrawn');
select tt.chk('T6 a second withdraw is harmless', (r2_announce_withdraw(:a_loc1, 'again') ->> 'repeat') = 'true');
select tt.as(:'u_a');
select tt.chk('T6 a withdrawn message leaves the bar', not tt.has(r2_announce_active(), :a_loc1));
select tt.err('T6 a withdrawn message cannot be marked seen', format('select r2_announce_seen(%s)', :a_loc1), 'not allowed');
select tt.as(:'u_o');
select tt.chk('T6 the owner can withdraw any message', (r2_announce_withdraw(:a_pa, 'test owner stop') ->> 'status') = 'withdrawn');
reset role;
select tt.chk('T6 the rows stay (withdrawn, with who, when, why)', (select count(*) from r2_announcements where status = 'withdrawn' and withdrawn_by is not null and withdrawn_at is not null and withdrawn_reason is not null) = 2);
select tt.err('T6 nothing is hard-deleted', format('delete from r2_announcements where id = %s', :a_loc1), 'nothing is deleted');

\echo == T7 a grant limited to one place can post only to that place
set role authenticated; select tt.as(:'u_pl');
select tt.chk('T7 state: can post, only place 1', (r2_announce_state() ->> 'can_post') = 'true' and (r2_announce_state() ->> 'can_post_all') = 'false' and (r2_announce_state() -> 'post_locations') = '[1]'::jsonb);
select tt.chk('T7 posts to his own place', (r2_announce_post('test only here', '', false, 'location', '1') ->> 'id') is not null);
select tt.err('T7 refused: another place', $q$select r2_announce_post('test x', '', false, 'location', '2')$q$, 'not allowed');
select tt.err('T7 refused: everyone', $q$select r2_announce_post('test x', '', false, 'all', null)$q$, 'not allowed');
select tt.err('T7 refused: a role', $q$select r2_announce_post('test x', '', false, 'role', 'salesperson')$q$, 'not allowed');
select tt.err('T7 refused: one person', format($q$select r2_announce_post('test x', '', false, 'person', %L)$q$, :'u_b'), 'not allowed');
reset role;

\echo == T8 a role can be designated too (rule_grants), and taken away
set role authenticated; select tt.as(:'u_h');
select tt.err('T8 hr cannot post yet', $q$select r2_announce_post('test x', '', false, 'all', null)$q$, 'not allowed');
reset role;
insert into rule_grants (grant_code, role_code) values ('announce_post', 'hr');
set role authenticated; select tt.as(:'u_h');
select tt.chk('T8 after the owner gives the grant to the hr role, hr can post to everyone', (r2_announce_post('test from hr', '', false, 'all', null) ->> 'id') is not null);
reset role;
update rule_grants set allowed = false where grant_code = 'announce_post' and role_code = 'hr';
set role authenticated; select tt.as(:'u_h');
select tt.err('T8 taken away again: refused', $q$select r2_announce_post('test x', '', false, 'all', null)$q$, 'not allowed');

\echo == T9 my list
select tt.as(:'u_a');
select tt.chk('T9 staff A has posted nothing: empty list', r2_announce_mine() = '[]'::jsonb);
select tt.as(:'u_p');
select tt.chk('T9 the poster sees exactly his own (9), with audience and seen counts', jsonb_array_length(r2_announce_mine()) = 9 and (select (x ->> 'audience')::int from jsonb_array_elements(r2_announce_mine()) x where (x ->> 'id')::bigint = :a_loc1) = 5);
select tt.as(:'u_o');
select tt.chk('T9 the owner sees all 13 (owner 2 + poster 9 + place-only 1 + hr 1)', jsonb_array_length(r2_announce_mine(200)) = 13);
select tt.chk('T9 a withdrawn one is marked not live and carries its reason', (select (x ->> 'live')::boolean = false and x ->> 'withdrawn_reason' = 'test owner stop' from jsonb_array_elements(r2_announce_mine(200)) x where (x ->> 'id')::bigint = :a_pa));
reset role;

\echo == T10 change log
select tt.chk('T10 every post and withdraw wrote an audit_log line (who, what)', (select count(*) from audit_log where table_name = 'r2_announcements' and action = 'insert') = 13
  and (select count(*) from audit_log where table_name = 'r2_announcements' and action = 'update' and detail -> 'new' ->> 'status' = 'withdrawn') = 2);

\echo == T11 switch OFF again: the bar disappears at once, history stays
set role authenticated; select tt.as(:'u_o'); select set_rule('announce_on', 'false'::jsonb) is null as off1 \gset
select tt.as(:'u_a');
select tt.chk('T11 OFF again: staff bar empty', r2_announce_active() = '[]'::jsonb and tt.c('select count(*) from r2_announcements') = 0);
select tt.as(:'u_o');
select tt.chk('T11 the owner can still read the history', tt.c('select count(*) from r2_announcements') = 13);
reset role;

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
