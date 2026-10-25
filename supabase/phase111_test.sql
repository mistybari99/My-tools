-- FRESH DB ONLY, built through the canonical order incl. phase111 (tests/sql/final_build.sh). Phase 111 tests: the merge of phase105 + phase109 on _bp_pay99, no tag lost, paste-twice identical.
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
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
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1) on conflict do nothing;

\echo == T1 merged body
create temp table f0 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace = 'public'::regnamespace;
select tt.chk('T1 _bp_pay99 carries bos105 (L4 client_id_reused), bos109 (FOR NO KEY UPDATE) and bos111', (select d ~ 'bos105' and d ~ 'client_id_reused' and d ~ 'bos109' and d ~ 'for no key update' and d !~ 'suppliers where id = pb.supplier_id for update' and d ~ 'bos111'
  from (select pg_get_functiondef('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)'::regprocedure) d) x));
select tt.chk('T1 phase105 tags kept in all 13 phase105 functions', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_bp_uuid99','_bp_auto99','_bp_pay99','_bp_sp_void99','inbox_unmask','_inb_mask_phones103','_cust_pii103','customer_dues','customer_advances','customer_profile','customer_save','_inb_pii_cols76') and pg_get_functiondef(p.oid) ~ 'bos105') = 12);
select tt.chk('T1 phase109 tag kept in all 12 phase109 functions', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('production_post','_post_purchase_p13','_void_purchase_p13','_bp_pay99','pay_supplier','void_supplier_payment','supplier_refund','void_supplier_refund','set_option_view_bulk','set_role_option_view_bulk','setup_recommend_apply','card_settle') and pg_get_functiondef(p.oid) ~ 'bos109') = 12);
select tt.chk('T1 older tags kept (bos99 object names, bos103 in setup_recommend_apply, bos82 in _void_purchase_p13)', (select bool_and(d ~ 'bos103') from (select pg_get_functiondef(p.oid) d from pg_proc p where p.proname = 'setup_recommend_apply') x)
  and (select bool_and(d ~ 'bos82') from (select pg_get_functiondef(p.oid) d from pg_proc p where p.proname = '_void_purchase_p13') x));
\echo == T2 paste twice, and phase109 after phase111
\i supabase/phase111.sql
\i supabase/phase109.sql
\i supabase/phase111.sql
\i supabase/phase527.sql
\i supabase/phase528.sql
\i supabase/phase133.sql
\i supabase/phase134.sql
\i supabase/phase135.sql
select tt.chk('T2 no function changed by pasting 111, 109, 111 again', (select count(*) from pg_proc p join f0 on f0.fn = p.oid::regprocedure::text where p.pronamespace = 'public'::regnamespace and md5(pg_get_functiondef(p.oid)) <> f0.h) = 0);
select tt.chk('T2 phase109 after 111 did not erase bos105/bos111', (select d ~ 'bos105' and d ~ 'bos111' from (select pg_get_functiondef('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)'::regprocedure) d) x));
\echo == T3 body guard: an unknown tag stops the paste (the error below is expected)
create temp table g3 as select pg_get_functiondef('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)'::regprocedure) d;
do $$ begin execute replace((select d from g3), '-- bos111:', '-- bos999:'); end $$;
\i supabase/phase111.sql
select tt.chk('T3 phase111 does not overwrite a body with an unknown tag (bos999 still there)', (select pg_get_functiondef('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)'::regprocedure) ~ 'bos999'));
do $$ begin execute (select d from g3); end $$;
select tt.chk('T3 restored; phase111 can be pasted again and nothing changes', (select count(*) from pg_proc p join f0 on f0.fn = p.oid::regprocedure::text where p.pronamespace = 'public'::regnamespace and md5(pg_get_functiondef(p.oid)) <> f0.h) = 0);
\echo == T4 behaviour: a supplier payment is still posted, client id of another bill refused
select tt.chk('T4 _bp_pay99 callable (signature unchanged)', to_regprocedure('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)') is not null);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
