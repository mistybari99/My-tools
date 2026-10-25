-- FRESH DB ONLY. Phase 478 tests (helper functions closed to anon).
--   build a database through phase 478 in the owner order (tests/sql/ORDER.txt), then from the repository root
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase478_test.sql | grep -E 'FAIL|RESULT'
-- Test data only; no data is written.
\set ON_ERROR_STOP off
\i tests/sql/rpthub_tt.sql
\echo == T1 rights
select tt.chk('T1 no helper (_..._present, _w1*_) is open to anon or PUBLIC any more', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname ~ '^_[a-z0-9]+_present[0-9]*$' or p.proname ~ '^_w1[a-z]*_') and (has_function_privilege('anon', p.oid, 'execute') or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'))));
select tt.chk('T1 the signed-in role still has EXECUTE on the five read helpers', has_function_privilege('authenticated', 'public._p89_present()', 'execute') and has_function_privilege('authenticated', 'public._p120_present()', 'execute') and has_function_privilege('authenticated', 'public._w1c_present90()', 'execute') and has_function_privilege('authenticated', 'public._w1c_present91()', 'execute') and has_function_privilege('authenticated', 'public._w1c_status_list_ok(text)', 'execute'));
select tt.chk('T1 the W1-FIX helpers that phase 143 closed to everybody stay closed', not has_function_privilege('authenticated', 'public._w1x_present143()', 'execute') and not has_function_privilege('anon', 'public._w1x_present143()', 'execute'));
\echo == T2 the paths still work
select tt.chk('T2 database owner: the helpers answer', public._p89_present() is not null and public._p120_present() is not null and public._w1c_present90() is not null);
set role authenticated;
select tt.chk('T2 signed-in role: _w1c_status_list_ok answers', public._w1c_status_list_ok('ok') is not null);
select tt.chk('T2 signed-in role: _p89_present answers', public._p89_present() is not null);
reset role;
set role anon;
select tt.err('T2 anon: _p89_present is refused', 'select public._p89_present()', 'permission denied');
select tt.err('T2 anon: _w1c_status_list_ok is refused', $q$select public._w1c_status_list_ok('ok')$q$, 'permission denied');
reset role;
\echo == T3 phase 477 and the state functions still work
select tt.chk('T3 _i2_state(): no expected hook is missing', not exists (select 1 from public._i2_state() where not present));
select public._i2_apply_all() as r \gset
select tt.chk('T3 phase 477 call after 478: patches nothing new', (select bool_and(value::int = 0) from jsonb_each_text(:'r'::jsonb)));
select tt.chk('T3 the Wave 1 hook state function still reports all 37 hooks', (select count(*) filter (where (e ->> 'present')::boolean) = count(*) and count(*) = 37 from jsonb_array_elements(public._i1_hooks_state()) e));
\echo == T4 paste twice
\i supabase/phase478.sql
select tt.chk('T4 second paste: still closed to anon', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname ~ '^_[a-z0-9]+_present[0-9]*$' or p.proname ~ '^_w1[a-z]*_') and has_function_privilege('anon', p.oid, 'execute')));
select tt.chk('T4 second paste: signed-in role keeps EXECUTE', has_function_privilege('authenticated', 'public._p89_present()', 'execute'));
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
