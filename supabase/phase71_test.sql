-- FRESH DB ONLY. Phase 71 tests (#18 2FA safe core). auth.mfa_factors and jwt aal are MOCKED here.
--   ORDER="phase8 ... phase51 phase52 phase53 phase54 phase60 phase61 phase62 phase71" bash tests/sql/build_fresh_db.sh a71db
--   psql -h /tmp -p 5544 -U postgres -d a71db -qAt -f supabase/phase71_test.sql | grep -E 'FAIL|RESULT'
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
create or replace function tt.ok(p_name text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, true);
exception when others then perform tt.chk(p_name, false); raise notice '  (got: %)', sqlerrm; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.aal(p text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', case when p is null then '' else json_build_object('aal', p)::text end, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'k','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1) on conflict do nothing;
-- MOCK of the Supabase table (only the columns we read)
create table if not exists auth.mfa_factors (id uuid default gen_random_uuid() primary key, user_id uuid, factor_type text default 'totp', status text);
truncate auth.mfa_factors;

\echo == T0 shape
select tt.chk('T0 rules exist with safe defaults', (select count(*) from rules where key in ('twofa_required_roles','twofa_enforce_owner_writes'))=2 and not rule_on('twofa_enforce_owner_writes') and coalesce(rule_val('twofa_required_roles') #>> '{}','x')='');
select tt.chk('T0 bos71 guard is in all five owner functions', (select count(*) from pg_proc where proname in ('set_rule','path_switch_set','acct_set_start','year_close_run','set_user_grant') and position('bos71' in pg_get_functiondef(oid))>0)=5);
select tt.chk('T0 helpers closed to browsers; policy/report callable', not has_function_privilege('authenticated','public._aal2()','execute') and not has_function_privilege('authenticated','public._twofa_guard71()','execute')
  and has_function_privilege('authenticated','public.twofa_policy()','execute') and not has_function_privilege('anon','public.twofa_status_report()','execute'));

\echo == T1 _aal2 reads the claim
select tt.aal(null); select tt.chk('T1 no claims -> false', not _aal2());
select tt.aal('aal1'); select tt.chk('T1 aal1 -> false', not _aal2());
select tt.aal('aal2'); select tt.chk('T1 aal2 -> true', _aal2());
select tt.aal(null);

\echo == T2 switch OFF: nothing changes even with a factor
select tt.as(:'o');
insert into auth.mfa_factors (user_id,status) values (:'o','verified');
select tt.ok('T2 set_rule works at aal1 while the switch is OFF', $$select set_rule('twofa_required_roles', to_jsonb('owner, Storekeeper'::text))$$);

\echo == T3 policy
select tt.chk('T3 owner: required, has factor, aal2 false, no must_enroll', (select (j->>'required')::boolean and (j->>'has_verified_factor')::boolean and not (j->>'aal2')::boolean and not (j->>'must_enroll')::boolean from (select twofa_policy() j) x));
select tt.as(:'k');
select tt.chk('T3 storekeeper (listed, no factor): must_enroll', (select (j->>'must_enroll')::boolean from (select twofa_policy() j) x));
select tt.as(:'s');
select tt.chk('T3 manager (not listed): not required', (select not (j->>'required')::boolean and not (j->>'must_enroll')::boolean from (select twofa_policy() j) x));
select tt.as(null);
select tt.err('T3 no user -> refused', 'select twofa_policy()', 'not allowed');

\echo == T4 report
select tt.as(:'s'); select tt.err('T4 non-owner refused', 'select twofa_status_report()', 'not allowed');
select tt.as(:'o');
select tt.chk('T4 report: owner has 2FA, storekeeper missing, no secret columns', (select (select (u->>'has_2fa')::boolean from jsonb_array_elements(j->'users') u where u->>'user_id'=:'o')
  and (select (u->>'missing')::boolean from jsonb_array_elements(j->'users') u where u->>'user_id'=:'k') and position('secret' in j::text)=0 from (select twofa_status_report() j) x));

\echo == T5 enforcement ON
select set_rule('twofa_enforce_owner_writes','true'::jsonb) is null as on1 \gset
select tt.aal('aal1');
select tt.err('T5 set_rule refused at aal1 (factor present)', $$select set_rule('twofa_required_roles','"owner"'::jsonb)$$, 'twofa_required');
select tt.err('T5 path_switch_set refused at aal1', $$select path_switch_set('stock_issue',0,true,true,'a')$$, 'twofa_required');
select tt.err('T5 acct_set_start refused at aal1', $$select acct_set_start(date '2025-01-01')$$, 'twofa_required');
select tt.err('T5 year_close_run refused at aal1', $$select year_close_run(date '2025-01-01', date '2025-12-31', 'x', null, true)$$, 'twofa_required');
select tt.err('T5 set_user_grant refused at aal1', format($$select set_user_grant('%s'::uuid,'release_decide',null,null,true,'x')$$, :'s'), 'twofa_required');
select tt.chk('T5 policy shows sensitive_actions_blocked_now', (twofa_policy()->>'sensitive_actions_blocked_now')::boolean);
select tt.aal('aal2');
select tt.ok('T5 set_rule works at aal2', $$select set_rule('twofa_required_roles','"owner"'::jsonb)$$);
select tt.chk('T5 path_switch_set works at aal2', path_switch_set('stock_issue',0,true,true,'a') is not null);
select tt.err('T5 at aal2 the old owner checks still apply (year_close needs its own switch)', $$select year_close_run(date '2025-01-01', date '2025-12-31', 'x', null, true)$$, 'switch_off');
select tt.as(:'s'); select tt.err('T5 non-owner still refused (not allowed, not twofa)', $$select set_rule('twofa_required_roles','"owner"'::jsonb)$$, 'not allowed');

\echo == T6 no lock-out: owner without a factor is not blocked
select tt.as(:'o'); select tt.aal('aal1');
delete from auth.mfa_factors where user_id=:'o'::uuid;
select tt.ok('T6 no verified factor -> set_rule works at aal1 even with the switch ON', $$select set_rule('twofa_required_roles','"owner,storekeeper"'::jsonb)$$);
insert into auth.mfa_factors (user_id,status) values (:'o','unverified');
select tt.ok('T6 an unverified (half-enrolled) factor does not lock the owner', $$select set_rule('twofa_required_roles','"owner"'::jsonb)$$);

\echo == T7 paste twice
select tt.aal(null);
select count(*) as n_before from rules \gset
\i supabase/phase71.sql
select tt.chk('T7 second apply: same rule count, still 5 guarded, defaults untouched', (select count(*) from rules)=:n_before and (select count(*) from pg_proc where proname in ('set_rule','path_switch_set','acct_set_start','year_close_run','set_user_grant') and (length(pg_get_functiondef(oid)) - length(replace(pg_get_functiondef(oid),'bos71','')))/5 = 1)=5);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
