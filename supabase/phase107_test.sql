-- FRESH DB ONLY. Phase 107 tests (Step Errlog: client_errors log, RLS, RPCs, rules, privacy; see docs/briefs_p2p3/step_Errlog_REPORT.md).
--   Build: bash tests/sql/final_build.sh <db> "<canonical order ... phase524 phase525 phase100 phase101 phase102 phase103>" then phase107.sql (tests/sql/run_all_sql.sh does it).
--   Run from the REPO ROOT (the last blocks paste phase107.sql again):
--     psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase107_test.sql | grep -E "FAIL|RESULT"
--   Test data only, no real names.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set p '00000000-0000-0000-0000-000000000004'
\set v '00000000-0000-0000-0000-000000000005'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.try(p_sql text) returns text language plpgsql as $$
declare r text;
begin execute p_sql into r; return r;
exception when others then return 'ERR:' || sqlerrm; end $$;
-- one-item batch helper
create or replace function tt.one(p_client text, p_cid text, p_kind text, p_msg text, p_route text default '#/home', p_extra jsonb default null, p_note text default null, p_count int default null) returns jsonb language sql as $$
  select public.client_error_log(p_client, jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('cid', p_cid, 'kind', p_kind, 'message', p_msg, 'route', p_route, 'extra', p_extra, 'note', p_note, 'count', p_count, 'app_build', 'b1', 'lang', 'en', 'ua', 'UA'))))
$$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'p','sales4@s.app','{"full_name":"Sales"}'), (:'v','viewer5@s.app','{"full_name":"Viewer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'p','salesperson'),(:'v','salesperson') on conflict do nothing;
insert into user_locations values (:'p',1),(:'v',1) on conflict do nothing;
select tt.as(:'o');
select set_user_grant(:'v'::uuid, 'view_client_errors') is null as g1 \gset

-- T0 objects, defaults, advisor rows
select tt.chk('T0 table, 3 rules (client_errors_on default OFF), grant, 3 advisor rows, RPCs exist',
  to_regclass('public.client_errors') is not null
  and (select default_value from rules where key = 'client_errors_on') = 'false'::jsonb
  and (select default_value is null and max_value = 200 from rules where key = 'client_error_rate_max')
  and (select default_value is null from rules where key = 'client_errors_keep_days')
  and exists (select 1 from grant_defs where grant_code = 'view_client_errors')
  and (select rec_value from setup_rec_defs81 where code = 'client_errors_on') = 'true'::jsonb
  and (select count(*) from setup_rec_defs81 where phase = '107') = 3
  and to_regprocedure('public.client_error_log(text,jsonb)') is not null and to_regprocedure('public.client_errors_purge(integer)') is not null);
select tt.chk('T0 client_errors_purge default is 60 (function default only), rule keep_days is blank = keep',
  pg_get_function_arguments('public.client_errors_purge(integer)'::regprocedure) like '%DEFAULT 60%' and rule_num('client_errors_keep_days') is null);
select tt.chk('T0 the typed rate number can only lower the ceiling: 201 refused, 5 accepted',
  tt.try($$select set_rule('client_error_rate_max', '201'::jsonb)::text$$) like 'ERR:%bad_value%' and tt.try($$select set_rule('client_error_rate_max', '5'::jsonb)::text$$) = '');
select set_rule('client_error_rate_max', null) is null as rr \gset

-- T1 rule OFF: automatic kinds are not stored; a user_report is
select tt.as(:'p');
select tt.one('dev1', 'c1', 'js_error', 'boom while off') ->> 'off' as off1 \gset
select tt.chk('T1 rule off: js_error not stored (off=1, no row)', :'off1' = '1' and (select count(*) from client_errors) = 0);
select tt.one('dev1', 'c2', 'user_report', 'Report a problem', '#/reportproblem', null, 'the total looks wrong') ->> 'accepted' as ur \gset
select tt.chk('T1 rule off: a user_report is stored with its note', :'ur' = '1' and (select user_note from client_errors where kind = 'user_report') = 'the total looks wrong');
select tt.chk('T1 the row carries the user, staff id and no secret column', (select user_id from client_errors where kind = 'user_report') = :'p'::uuid and (select staff_id from client_errors where kind = 'user_report') is not null);
delete from client_errors;

-- T2 rule ON: stored, fields, fingerprint
select tt.as(:'o'); select set_rule('client_errors_on', 'true') is null as on1 \gset
select tt.as(:'p');
select tt.one('dev1', 'a1', 'js_error', E'TypeError: x is undefined\n    at foo (app.js:10:5)', '#/items?search=milk', '{"line":10}') ->> 'accepted' as a1 \gset
select tt.chk('T2 rule on: js_error stored, route query stripped, kind/message/build/lang kept',
  :'a1' = '1' and (select route from client_errors) = '#/items' and (select kind from client_errors) = 'js_error' and (select message from client_errors) like 'TypeError: x is undefined%'
  and (select app_build from client_errors) = 'b1' and (select lang from client_errors) = 'en' and (select count from client_errors) = 1 and (select fingerprint from client_errors) ~ '^[0-9a-f]{32}$');
select tt.chk('T2 uuid and long numbers in a route become :id',
  _ce_route107('#/sale/3f2c1a9e-1111-4222-8333-444455556666/edit?x=1') = '#/sale/:id/edit' and _ce_route107('#/customer/123456') = '#/customer/:id' and _ce_route107('#/home') = '#/home');
select tt.chk('T2 fingerprint ignores digits in the message and differs by route/kind',
  _ce_fp107('js_error', 'fail 12 of 99', '#/a') = _ce_fp107('js_error', 'fail 7 of 3', '#/a') and _ce_fp107('js_error', 'fail', '#/a') <> _ce_fp107('js_error', 'fail', '#/b') and _ce_fp107('js_error', 'fail', '#/a') <> _ce_fp107('rpc_error', 'fail', '#/a'));

-- T3 dedupe within 10 minutes -> count, not a new row; user_report never deduped; after 10 minutes a new row
select tt.one('dev1', 'a2', 'js_error', E'TypeError: x is undefined\n    at foo (app.js:99:1)', '#/items') ->> 'deduped' as d1 \gset
select tt.chk('T3 same fingerprint inside 10 minutes: deduped=1, still one row, count=2', :'d1' = '1' and (select count(*) from client_errors) = 1 and (select count from client_errors) = 2);
select tt.one('dev1', 'a3', 'js_error', 'TypeError: x is undefined', '#/items', null, null, 5) ->> 'deduped' as d2 \gset
select tt.chk('T3 a client-side count of 5 adds 5', (select count from client_errors) = 7);
update client_errors set last_at = now() - interval '11 minutes';
select tt.one('dev1', 'a4', 'js_error', 'TypeError: x is undefined', '#/items') ->> 'accepted' as d3 \gset
select tt.chk('T3 after 10 minutes the same error is a new row (count 1)', :'d3' = '1' and (select count(*) from client_errors) = 2 and (select count from client_errors order by id desc limit 1) = 1);
select tt.one('dev1', 'r1', 'user_report', 'Report', '#/reportproblem', null, 'n1') ->> 'accepted' as u1 \gset
select tt.one('dev1', 'r2', 'user_report', 'Report', '#/reportproblem', null, 'n1') ->> 'accepted' as u2 \gset
select tt.chk('T3 two user_reports with the same text are two rows', :'u1' = '1' and :'u2' = '1' and (select count(*) from client_errors where kind = 'user_report') = 2);

-- T4 idempotent by client id
select tt.one('dev1', 'a4', 'js_error', 'TypeError: x is undefined', '#/items') ->> 'duplicate' as dp \gset
select tt.chk('T4 same p_client + client id again: duplicate=1, nothing changes', :'dp' = '1' and (select count(*) from client_errors) = 4 and (select sum(count) from client_errors) = 10);
select tt.one('dev2', 'a4', 'js_error', 'other device same cid', '#/z') ->> 'accepted' as dp2 \gset
select tt.chk('T4 the same client id from another device is a different key', :'dp2' = '1');

-- T5 caps / truncation / PII
delete from client_errors;
select public.client_error_log('dev1', jsonb_build_array(jsonb_build_object('cid', 'cap1', 'kind', 'js_error', 'message', repeat('m', 900), 'stack', repeat('s', 3000), 'ua', repeat('u', 400), 'lang', 'bnbnbnbnbnbnbn',
  'app_build', repeat('b', 80), 'route', '#/' || repeat('r', 400), 'note', repeat('n', 1500)))) ->> 'accepted' as c1 \gset
select tt.chk('T5 caps: message 500, stack 2000, ua 200, lang 10, build 40, route 200, note 1000',
  :'c1' = '1' and (select char_length(message) = 500 and char_length(stack) = 2000 and char_length(ua) = 200 and char_length(lang) = 10 and char_length(app_build) = 40 and char_length(route) = 200 and char_length(user_note) = 1000 from client_errors));
delete from client_errors;
select tt.one('dev1', 'ex1', 'js_error', 'extra test', '#/x', '{"ok":"yes","token":"T1","API_KEY":"K","apikey":"K2","Password":"P","client_secret":"S","Authorization":"Bearer abc","Cookie":"c","nested":{"x":1,"access_token":"T2","deep":[{"password":"p","fine":2}]},"line":7}') ->> 'accepted' as e1 \gset
select tt.chk('T5 no PII: keys matching token|key|password|secret|authorization|cookie are removed at every depth',
  :'e1' = '1' and (select extra ? 'ok' and extra ? 'line' and not (extra ?| array['token','API_KEY','apikey','Password','client_secret','Authorization','Cookie']) and not (extra->'nested' ? 'access_token')
     and (extra->'nested'->'deep'->0) = '{"fine":2}'::jsonb and extra->'nested'->'x' = '1'::jsonb from client_errors));
delete from client_errors;
select tt.one('dev1', 'ex2', 'js_error', 'big extra', '#/x', (select jsonb_object_agg('k' || g, repeat('v', 190)) from generate_series(1, 25) g)) ->> 'accepted' as e2 \gset
select tt.chk('T5 extra is capped at 2 KB (always stored valid)', :'e2' = '1' and (select octet_length(extra::text) <= 2048 from client_errors));
delete from client_errors;
select tt.one('dev1', 'pii1', 'js_error', 'fail eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcDEF123 for bob@example.com phone 01712345678 Bearer abc.def', '#/x') ->> 'accepted' as p1 \gset
select tt.chk('T5 message loses JWT, e-mail, 8+ digit runs and Bearer values',
  (select message not like '%eyJ%' and message not like '%@%' and message not like '%0171%' and message not like '%abc.def%' and message like '%[jwt]%' and message like '%[email]%' and message like '%[num]%' from client_errors));
select tt.chk('T5 a non-object extra is ignored, a bad kind is skipped, a non-array batch is refused softly',
  (tt.one('dev1', 'ex3', 'js_error', 'extra array', '#/x', '[1,2]'::jsonb) ->> 'accepted') = '1'
  and (public.client_error_log('dev1', '[{"cid":"k1","kind":"nope","message":"x"}]'::jsonb) ->> 'skipped') = '1'
  and (public.client_error_log('dev1', '{"a":1}'::jsonb) ->> 'error') = 'bad_batch' and (public.client_error_log('dev1', null) ->> 'ok') = 'false');
delete from client_errors;

-- T6 batch of 20 max
select public.client_error_log('dev3', (select jsonb_agg(jsonb_build_object('cid', 'b' || g, 'kind', 'js_error', 'message', 'distinct error number ' || chr(64 + g), 'route', '#/b' || g)) from generate_series(1, 25) g)) as bj \gset
select tt.chk('T6 batch of 25: 20 accepted, 5 dropped', (:'bj'::jsonb ->> 'accepted') = '20' and (:'bj'::jsonb ->> 'dropped') = '5' and (select count(*) from client_errors) = 20);

-- T7 rate limit: owner-typed lowers; blank = internal ceiling 200
delete from client_errors; delete from client_error_hits107; delete from client_error_seen107;
select tt.as(:'o'); select set_rule('client_error_rate_max', '3'::jsonb) is null as r3 \gset
select tt.as(:'p');
select public.client_error_log('dev4', (select jsonb_agg(jsonb_build_object('cid', 'r' || g, 'kind', 'js_error', 'message', 'rate error ' || chr(64 + g), 'route', '#/r')) from generate_series(1, 5) g)) as rj \gset
select tt.chk('T7 rate max 3: 3 accepted, 2 limited, 3 rows', (:'rj'::jsonb ->> 'accepted') = '3' and (:'rj'::jsonb ->> 'limited') = '2' and (select count(*) from client_errors) = 3);
select tt.one('dev4', 'r9', 'js_error', 'one more', '#/r') ->> 'limited' as rl \gset
select tt.chk('T7 still limited inside the same hour; a different user is not limited', :'rl' = '1');
select tt.as(:'v'); select tt.one('devv', 'v1', 'js_error', 'viewer error', '#/r') ->> 'accepted' as vl \gset
select tt.chk('T7 the limit is per user', :'vl' = '1');
select tt.as(:'o'); select set_rule('client_error_rate_max', null) is null as r0 \gset
select tt.as(:'p');
delete from client_errors; delete from client_error_hits107; delete from client_error_seen107;
do $$ declare i int; begin for i in 1..15 loop perform public.client_error_log('dev5', (select jsonb_agg(jsonb_build_object('cid', 'x' || i || '_' || g, 'kind', 'js_error', 'message', 'flood ' || i || chr(64 + g), 'route', '#/f' || i || '_' || g)) from generate_series(1, 20) g)); end loop; end $$;
select tt.chk('T7 blank rule: the built-in ceiling of 200 per user per hour holds against a flood of 300',
  (select count(*) from client_errors where user_id = :'p'::uuid) = 200 and (select n from client_error_hits107 where user_id = :'p'::uuid) = 200);
update client_error_hits107 set hr = hr - interval '1 hour';
select tt.one('dev5', 'next', 'js_error', 'new hour', '#/n') ->> 'accepted' as nh \gset
select tt.chk('T7 a new hour starts a new count', :'nh' = '1');
delete from client_errors; delete from client_error_hits107; delete from client_error_seen107;

-- T8 not signed in / inactive
select set_config('request.jwt.claim.sub', '', false);
select tt.chk('T8 no session: soft refusal, nothing stored', (tt.one('devx', 'z1', 'js_error', 'no session') ->> 'ok') = 'false' and (select count(*) from client_errors) = 0);
select tt.as(:'p');

-- T9 RLS (role authenticated)
select tt.as(:'p'); select tt.one('dev1', 'rls1', 'js_error', 'p error', '#/p');
select tt.as(:'v'); select tt.one('devv', 'rls2', 'js_error', 'v error', '#/v');
set role authenticated; select tt.as(:'p');
select tt.chk('T9 a plain user reads no rows directly (not even their own)', (select count(*) from client_errors) = 0);
select tt.chk('T9 direct insert / update / delete are refused',
  tt.try($$insert into client_errors (kind, message) values ('js_error', 'x')$$) like 'ERR:%' and tt.try($$update client_errors set count = 9$$) like 'ERR:%' and tt.try($$delete from client_errors$$) like 'ERR:%');
select tt.chk('T9 non-owner list / summary / resolve / purge refused',
  tt.try($$select client_errors_list()::text$$) like 'ERR:%not allowed%' and tt.try($$select client_errors_summary()::text$$) like 'ERR:%not allowed%'
  and tt.try($$select client_error_resolve(1, 'x')::text$$) like 'ERR:%not allowed%' and tt.try($$select client_errors_purge(1)::text$$) like 'ERR:%not allowed%');
select tt.chk('T9 the idempotency / counter tables are closed', tt.try($$select count(*) from client_error_seen107$$) like 'ERR:%' and tt.try($$select count(*) from client_error_hits107$$) like 'ERR:%');
select tt.as(:'v');
select tt.chk('T9 a holder of view_client_errors sees all rows and lists them', (select count(*) from client_errors) = 2 and jsonb_array_length(client_errors_list()) = 2 and jsonb_array_length(client_errors_summary()) = 2);
select tt.chk('T9 the viewer still cannot resolve or purge', tt.try($$select client_error_resolve(1, 'x')::text$$) like 'ERR:%not allowed%' and tt.try($$select client_errors_purge(1)::text$$) like 'ERR:%not allowed%');
select tt.as(:'o');
select tt.chk('T9 the owner sees everything', (select count(*) from client_errors) = 2);
reset role;

-- T10 list filters + summary
select tt.as(:'o');
select tt.one('dev1', 'l1', 'rpc_error', 'rpc failed: fn_x', '#/stock') is not null as l1 \gset
select tt.chk('T10 list filters: kind', jsonb_array_length(client_errors_list(null, null, 'rpc_error', 50)) = 1 and jsonb_array_length(client_errors_list(null, null, 'js_error', 50)) = 2);
select tt.chk('T10 list filters: from/to, limit clamp, status', jsonb_array_length(client_errors_list(now() + interval '1 day', null)) = 0 and jsonb_array_length(client_errors_list(null, now() - interval '1 day')) = 0
  and jsonb_array_length(client_errors_list(null, null, null, 1)) = 1 and jsonb_array_length(client_errors_list(null, null, null, 200, 'open')) = 3 and jsonb_array_length(client_errors_list(null, null, null, 200, 'resolved')) = 0);
select tt.chk('T10 summary: one entry per fingerprint, with total / users / open', (select bool_and((e->>'total')::int >= 1 and (e->>'open')::boolean) and count(*) = 3 from jsonb_array_elements(client_errors_summary()) e));
update client_errors set last_at = now() - interval '8 days', at = now() - interval '8 days' where message = 'v error';
select tt.chk('T10 summary covers the last 7 days only', jsonb_array_length(client_errors_summary()) = 2);

-- T11 resolve (owner, audited, resolves the fingerprint group; a new occurrence re-opens)
select id as rid from client_errors where message = 'p error' \gset
select tt.as(:'o');
select (client_error_resolve(:rid, 'fixed in b2') ->> 'resolved') as rs \gset
select tt.chk('T11 resolve marks the row, keeps the note', :'rs' = '1' and (select resolved_at is not null and resolve_note = 'fixed in b2' and resolved_by = :'o'::uuid from client_errors where id = :rid));
select tt.chk('T11 resolve is audited', exists (select 1 from audit_log where action = 'resolve' and table_name = 'client_errors' and record_id = :'rid' and detail->>'note' = 'fixed in b2'));
select tt.as(:'p'); select tt.one('dev1', 'rs2', 'js_error', 'p error', '#/p') ->> 'accepted' as ra \gset
select tt.chk('T11 the same error after resolve is a NEW open row (not merged into the resolved one)', :'ra' = '1' and (select count(*) from client_errors where message = 'p error') = 2 and (select count(*) from client_errors where message = 'p error' and resolved_at is null) = 1);
select tt.as(:'o'); select id as rid2 from client_errors where message = 'p error' and resolved_at is null \gset
select (client_error_resolve(:rid2, null) ->> 'resolved') as rs2 \gset
select tt.chk('T11 resolving again resolves only the still-open rows of that fingerprint', :'rs2' = '1');
select tt.chk('T11 unknown id refused', tt.try($$select client_error_resolve(999999, 'x')::text$$) like 'ERR:%not found%');
select tt.chk('T11 the status filter follows', jsonb_array_length(client_errors_list(null, null, null, 200, 'resolved')) = 2);

-- T12 purge
update client_errors set at = now() - interval '90 days', last_at = now() - interval '90 days' where message = 'v error';
select tt.as(:'o');
select client_errors_purge() as pg1 \gset
select tt.chk('T12 purge() default 60 days deletes the 90-day-old row only', :'pg1' = '1' and not exists (select 1 from client_errors where message = 'v error') and (select count(*) from client_errors) >= 3);
select tt.chk('T12 purge is audited', exists (select 1 from audit_log where action = 'purge' and table_name = 'client_errors' and (detail->>'deleted')::int = 1 and (detail->>'days')::int = 60));
select tt.chk('T12 purge with null days and a blank keep_days rule keeps everything (0)', client_errors_purge(null) = 0);
select tt.chk('T12 purge(0) refused', tt.try($$select client_errors_purge(0)::text$$) like 'ERR:%bad_value%');
update client_errors set at = now() - interval '5 days', last_at = now() - interval '5 days' where id = :rid;
select set_rule('client_errors_keep_days', '3'::jsonb) is null as kd \gset
select _client_errors_autopurge107() as apn \gset
select tt.chk('T12 the automatic purge follows client_errors_keep_days (3): the 5-day-old row goes', :'apn'::int >= 1 and not exists (select 1 from client_errors where id = :rid));
select set_rule('client_errors_keep_days', null) is null as kd0 \gset
update client_errors set at = now() - interval '400 days', last_at = now() - interval '400 days';
select _client_errors_autopurge107() as apn0 \gset
select tt.chk('T12 keep_days blank = keep: nothing is deleted automatically', :'apn0'::int = 0 and (select count(*) from client_errors) >= 1);
delete from client_error_hits107; delete from client_error_seen107; delete from client_errors;
insert into client_error_seen107 (user_id, client_key, at) values (:'p', 'old', now() - interval '3 days');
select _client_errors_autopurge107() is not null as ap \gset
select tt.chk('T12 old idempotency keys are cleaned', not exists (select 1 from client_error_seen107 where client_key = 'old'));

-- T13 privileges + paste twice + guard
select tt.chk('T13 internal helpers closed to the browser; anon cannot call the RPCs',
  not has_function_privilege('authenticated', 'public._ce_strip107(jsonb,integer)', 'execute') and not has_function_privilege('authenticated', 'public._client_errors_autopurge107()', 'execute')
  and not has_function_privilege('anon', 'public.client_error_log(text,jsonb)', 'execute') and has_function_privilege('authenticated', 'public.client_error_log(text,jsonb)', 'execute'));
select md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) as fa0 from pg_proc p where p.pronamespace = 'public'::regnamespace \gset
select (select count(*) from rules) as rn0, (select count(*) from setup_rec_defs81) as sn0, (select count(*) from grant_defs) as gn0 \gset
\i supabase/phase107.sql
select md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) as fa1 from pg_proc p where p.pronamespace = 'public'::regnamespace \gset
select tt.chk('T13 paste twice: no function body, rule, advisor row or grant row changes', :'fa0' = :'fa1' and (select count(*) from rules) = :rn0 and (select count(*) from setup_rec_defs81) = :sn0 and (select count(*) from grant_defs) = :gn0);
select tt.chk('T13 paste twice keeps the owner-set values (client_errors_on stays true)', rule_on('client_errors_on'));
alter function public._cust_pii103(text, text) rename to _cust_pii103_hold;
delete from setup_rec_defs81 where code = 'client_error_rate_max'; delete from rules where key = 'client_error_rate_max' and false;
create or replace function public.client_errors_summary() returns jsonb language sql as $$ select '{"held":true}'::jsonb $$;
\i supabase/phase107.sql
select tt.chk('T13 guard: with phase103 missing the paste raises and changes nothing (the held function stays, the deleted row is not re-added)', (client_errors_summary() ->> 'held') = 'true' and not exists (select 1 from setup_rec_defs81 where code = 'client_error_rate_max'));
alter function public._cust_pii103_hold(text, text) rename to _cust_pii103;
\i supabase/phase107.sql
select tt.chk('T13 with phase103 back it works again (summary restored, row re-added)', (client_errors_summary() ->> 'held') is null and exists (select 1 from setup_rec_defs81 where code = 'client_error_rate_max'));

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
