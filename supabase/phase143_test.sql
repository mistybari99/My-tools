-- FRESH DB ONLY. Phase 143 tests (W1-FIX re-patch: one call puts the hooks of phases 140 to 142 back; state check; works together with phase99's _i1_apply_hooks).
--   build a database through phase 99, paste phases 140 to 143 once, then:
--   psql -h /tmp -p 5610 -U postgres -d a143db -qAt -f supabase/phase143_test.sql | grep -E 'FAIL|RESULT'      (run from the repository root)
-- Everything that removes a hook runs inside a transaction that is rolled back, so the tested database keeps its hooks. No data is written.
\set ON_ERROR_STOP off
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
-- put the four functions back to the text they had before phases 140 to 142 (the exact reverse of the hook texts); returns how many were changed
create or replace function tt.revert_w1x() returns int language plpgsql as $$
declare d text; n int := 0; r record;
begin
  for r in select * from (values
      ('public.void_sale(uuid,text)'::regprocedure, E'\n  perform public._w1x_void_guard(s.id, p_note); /* bos140 */', ''),
      ('public._w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)'::regprocedure, ' + public._w1x_pay_prior(p_supplier)', ''),
      ('public._w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)'::regprocedure, '   /* bos141 */', ''),
      ('public._w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)'::regprocedure, ' || public._w1x_pay_note(p_supplier)', ''),
      ('public.employee_link_profile(uuid,uuid)'::regprocedure, E'  perform public._w1x_link_after(e.id, p_profile); /* bos142 */\n', ''),
      ('public.employee_status_set(uuid,text,date,text)'::regprocedure, E'  perform public._w1x_reactivate_guard(e.id, e.status, p_status); /* bos142 */\n', '')) v(fn, a, b) loop
    d := pg_get_functiondef(r.fn);
    if position(r.a in d) > 0 then execute replace(d, r.a, r.b); n := n + 1; end if;
  end loop;
  return n;
end $$;

\echo == T0 shape
select tt.chk('T0 phase143 present; the four expected hooks are listed and all present', to_regprocedure('public._w1x_present143()') is not null and (select count(*) from public._w1x_expect())=4
  and (select count(*) from jsonb_array_elements(public._w1x_hooks_state()) x where (x->>'present')::boolean)=4);
select tt.chk('T0 internals closed to browsers', not has_function_privilege('authenticated','public._w1x_apply_hooks()','execute') and not has_function_privilege('authenticated','public._w1x_hooks_state()','execute')
  and not has_function_privilege('anon','public._w1x_expect()','execute'));
select tt.chk('T0 phase99 state is untouched: all 37 Wave 1 hooks are still present', (select count(*) from jsonb_array_elements(public._i1_hooks_state()) x where (x->>'present')::boolean)=37);

\echo == T1 an old phase pasted again removes the hooks; one call puts them back  (checks are read inside a transaction that is rolled back, then recorded)
begin;
select tt.revert_w1x() as n_rev \gset
select (select count(*) from jsonb_array_elements(public._w1x_hooks_state()) x where not (x->>'present')::boolean) as miss1 \gset
select public._w1x_apply_hooks() as r1 \gset
select (select count(*) from jsonb_array_elements(public._w1x_hooks_state()) x where (x->>'present')::boolean) as pres1 \gset
select public._w1x_apply_hooks() as r2 \gset
select position('bos90' in pg_get_functiondef('public.employee_status_set(uuid,text,date,text)'::regprocedure))>0 and position('bos142' in pg_get_functiondef('public.employee_status_set(uuid,text,date,text)'::regprocedure))>0 as both_marks \gset
rollback;
select tt.chk('T1 simulation: the 6 hook texts of the 4 functions are removed and the state shows 4 missing', :n_rev = 6 and :miss1 = 4);
select tt.chk('T1 one call patches all four (every entry true) and the state shows all present', (select count(*) from jsonb_each_text(:'r1'::jsonb) where value='true')=4 and :pres1 = 4);
select tt.chk('T1 a second call changes nothing (every entry false)', (select count(*) from jsonb_each_text(:'r2'::jsonb) where value='false')=4);
select tt.chk('T1 bos90 and bos142 live side by side in employee_status_set', :'both_marks'::boolean);

\echo == T2 all or nothing: a missing patch site stops the call and nothing is half patched
begin;
select tt.revert_w1x() as n_rev2 \gset
-- damage the site of the LAST hook (employee_status_set) so that it cannot be found
do $t$ declare d text := replace(pg_get_functiondef('public.employee_status_set(uuid,text,date,text)'::regprocedure), 'update public.employees set status = p_status, status_date', 'update public.employees set status = p_status, status_dat_'); begin execute d; end $t$;
create temp table t2msg (m text) on commit drop;
do $t$ begin
  begin perform public._w1x_apply_hooks(); insert into t2msg values ('NO ERROR');
  exception when others then insert into t2msg values (sqlerrm); end;
end $t$;
select (select m from t2msg) as msg2 \gset
select position('bos140' in pg_get_functiondef('public.void_sale(uuid,text)'::regprocedure))=0 and position('bos141' in pg_get_functiondef('public._w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)'::regprocedure))=0
  and position('bos142' in pg_get_functiondef('public.employee_link_profile(uuid,uuid)'::regprocedure))=0 as unpatched \gset
rollback;
select tt.chk('T2 the call stops with a clear message', :'msg2' like '%patch site not found in%employee_status_set%');
select tt.chk('T2 the first three hooks were rolled back with it: void_sale, _w1e_pay_gate and employee_link_profile are still unpatched', :'unpatched'::boolean);
select tt.chk('T2 after the rollback the tested database has all four hooks again', (select count(*) from jsonb_array_elements(public._w1x_hooks_state()) x where (x->>'present')::boolean)=4);

\echo == T3 together with phase99: either order, both idempotent
begin;
select tt.revert_w1x() as n_rev3 \gset
select public._i1_apply_hooks() as i1 \gset
select public._w1x_apply_hooks() as w1 \gset
select (select count(*) from jsonb_array_elements(public._i1_hooks_state()) x where (x->>'present')::boolean) as i1_present \gset
select (select count(*) from jsonb_each_text(public._i1_apply_hooks()) x where x.value='true') as again_i1 \gset
select (select count(*) from jsonb_array_elements(public._w1x_hooks_state()) x where (x->>'present')::boolean) as w1_present \gset
rollback;
select tt.chk('T3 after phase99 then W1-FIX: all 37 Wave 1 hooks and all 4 W1-FIX hooks are present; W1-FIX patched what had been removed', :i1_present = 37 and :w1_present = 4 and (select count(*) from jsonb_each_text(:'w1'::jsonb) where value='true')=4);
select tt.chk('T3 phase99 hooks stay idempotent after W1-FIX (a repeat patches nothing)', :again_i1 = 0);

\echo == T4 the hook functions can be called twice in a row on the live text
select tt.chk('T4 each hook function reports false when the hook is already inside', (public._w1x140_hooks() ->> 'void_sale')='false' and (public._w1x141_hooks() ->> '_w1e_pay_gate')='false'
  and (public._w1x142_hooks() ->> 'employee_link_profile')='false' and (public._w1x142_hooks() ->> 'employee_status_set')='false');
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
