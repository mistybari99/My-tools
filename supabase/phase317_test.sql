-- FRESH DB ONLY. Phase 317 tests (CRM-F: referral codes and rewards). Build: phases 8..98, then 316, 317.
--   psql -h /tmp -p 5574 -U postgres -d crmf_b -qAt -f supabase/phase317_test.sql | grep -E 'FAIL|RESULT'      (run from the repo root)
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000031701'
\set u_m '00000000-0000-0000-0000-000000031702'
\set u_c '00000000-0000-0000-0000-000000031703'
\set u_l '00000000-0000-0000-0000-000000031704'
\set u_n '00000000-0000-0000-0000-000000031705'
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
create or replace function tt.je() returns bigint language sql security definer as $$ select count(*) from public.journal_entries $$;
create or replace function tt.bal(p_c uuid) returns int language sql security definer as $$ select coalesce(sum(delta),0)::int from public.customer_points_ledger where customer_id = p_c $$;
create or replace function tt.nref(p_c uuid) returns bigint language sql security definer as $$ select count(*) from public.customer_points_ledger where customer_id = p_c and reason = 'referral' $$;
create or replace function tt.cid(p_mobile text) returns uuid language sql security definer as $$ select id from public.customers where mobile = p_mobile $$;
create or replace function tt.rstat(p_referred uuid) returns text language sql security definer as $$ select status from public.crmf_referrals where referred_id = p_referred $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner317@s.app','{"full_name":"test_owner317"}'), (:'u_m','test_mgr317@s.app','{"full_name":"test_mgr317"}'), (:'u_c','test_cash317@s.app','{"full_name":"test_cash317"}'),
 (:'u_l','test_loy317@s.app','{"full_name":"test_loy317"}'), (:'u_n','test_none317@s.app','{"full_name":"test_none317"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_m', :'u_c', :'u_l', :'u_n');
insert into user_roles values (:'u_o','owner'),(:'u_m','showroom_manager'),(:'u_c','salesperson'),(:'u_l','management'),(:'u_n','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_m',1),(:'u_c',1),(:'u_l',1),(:'u_n',1) on conflict do nothing;
select tt.as(:'u_o');
select set_user_grant(:'u_m'::uuid,'customer_manage') is null as g1 \gset
select set_user_grant(:'u_l'::uuid,'crm_loyalty_manage') is null as g2 \gset
select tt.je() as je0 \gset
insert into customers (mobile, name) values ('01711731601','test_ref_a'),('01711731602','test_ref_b'),('01711731603','test_ref_c'),('01711731604','test_ref_d'),('01711731605','test_ref_e'),
  ('01711731606','test_ref_f'),('01711731607','test_ref_g'),('01711731608','test_ref_h') on conflict do nothing;

\echo == T0 shape, defaults
select tt.chk('T0 four settings, switch OFF, numbers blank', (select count(*) from rules where key in ('crm_referral_on','crm_referral_reward_points','crm_referral_referred_points','crm_referral_min_bill'))=4
  and not rule_on('crm_referral_on') and rule_num('crm_referral_reward_points') is null and rule_num('crm_referral_referred_points') is null and rule_num('crm_referral_min_bill') is null);
select tt.chk('T0 tables: RLS on, closed to browser writes', (select bool_and(relrowsecurity) from pg_class where relname in ('crmf_referral_codes','crmf_referrals'))
  and not has_table_privilege('authenticated','public.crmf_referrals','insert') and not has_table_privilege('authenticated','public.crmf_referrals','update') and not has_table_privilege('anon','public.crmf_referral_codes','select'));
select tt.chk('T0 the two sales triggers exist once; record_sale2 untouched', (select count(*) from pg_trigger where tgname in ('sales_referral_crmf','sales_referral_void_crmf') and not tgisinternal)=2
  and position('crmf' in pg_get_functiondef('public.record_sale2(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure))=0);

\echo == T1 switch OFF: nothing happens
set role authenticated; select tt.as(:'u_c');
select tt.err('T1 OFF: no code is made', $$select crmf_referral_code(tt.cid('01711731601'))$$, 'referral_off');
select tt.err('T1 OFF: no link is saved', $$select crmf_referral_apply(tt.cid('01711731602'), 'ABCDEF')$$, 'referral_off');
select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',0,'[{"mode":"cash","amount":1000}]','01711731607','test_ref_g','retail',null,true) is not null as s_off \gset
reset role;
select tt.chk('T1 OFF: tables are empty', (select count(*) from crmf_referrals)=0 and (select count(*) from crmf_referral_codes)=0 and (select count(*) from customer_points_ledger where reason='referral')=0);

\echo == T2 ON, reward blank: links are kept, nothing is paid
set role authenticated; select tt.as(:'u_o');
select set_rule('crm_referral_on','true'::jsonb) is null as o1 \gset
select set_rule('loyalty_points_on','true'::jsonb) is null as o2 \gset
select tt.as(:'u_c');
select crmf_referral_code(tt.cid('01711731601')) ->> 'code' as codea \gset
select tt.chk('T2 code is 6 characters of the safe alphabet', :'codea' ~ '^[A-HJ-NP-Z2-9]{6}$');
select tt.chk('T2 asking again gives the same code, not a new one', crmf_referral_code(tt.cid('01711731601')) ->> 'code' = :'codea' and not (crmf_referral_code(tt.cid('01711731601')) ->> 'new')::boolean);
select tt.chk('T2 a bad code is refused (answer, not a crash)', crmf_referral_apply(tt.cid('01711731602'), 'ab')->>'reason'='bad_code');
select tt.chk('T2 an unknown code is refused', crmf_referral_apply(tt.cid('01711731602'), 'ZZZZZZ')->>'reason'='code_not_found');
select tt.chk('T2 own code is refused', crmf_referral_apply(tt.cid('01711731601'), :'codea')->>'reason'='self_referral');
select tt.chk('T2 a customer who already bought is not new', crmf_referral_apply(tt.cid('01711731607'), :'codea')->>'reason'='not_a_new_customer');
select gen_random_uuid() as clr \gset
select tt.chk('T2 B is linked to A (pending)', crmf_referral_apply(tt.cid('01711731602'), lower(:'codea'), :'clr')->>'status'='pending' and tt.rstat(tt.cid('01711731602'))='pending');
select tt.chk('T2 same client id again: dup, one row', (crmf_referral_apply(tt.cid('01711731602'), :'codea', :'clr')->>'dup')::boolean and tt.rstat(tt.cid('01711731602'))='pending');
select tt.chk('T2 B cannot be linked twice', crmf_referral_apply(tt.cid('01711731602'), :'codea')->>'reason'='already_referred');
select record_sale2(gen_random_uuid(),1,'[{"amount":1500}]',0,'[{"mode":"cash","amount":1500}]','01711731602','test_ref_b','retail',null,true) is not null as sB1 \gset
reset role;
select tt.chk('T2 reward blank: the first sale pays nothing, the link stays pending', tt.rstat(tt.cid('01711731602'))='pending' and tt.nref(tt.cid('01711731601'))=0 and tt.nref(tt.cid('01711731602'))=0);
set role authenticated; select tt.as(:'u_c');
select record_sale2(gen_random_uuid(),1,'[{"amount":1500}]',0,'[{"mode":"cash","amount":1500}]','01711731602','test_ref_b','retail',null,true) is not null as sB2 \gset
reset role;
select tt.chk('T2 the second sale closes the link: not the first sale, still nothing paid', tt.rstat(tt.cid('01711731602'))='rejected' and tt.nref(tt.cid('01711731601'))=0);

\echo == T3 reward 50 / 20, minimum first bill 500
set role authenticated; select tt.as(:'u_o');
select set_rule('crm_referral_reward_points','50'::jsonb) is null as r1 \gset
select set_rule('crm_referral_referred_points','20'::jsonb) is null as r2 \gset
select set_rule('crm_referral_min_bill','500'::jsonb) is null as r3 \gset
select tt.as(:'u_c');
select crmf_referral_apply(tt.cid('01711731603'), :'codea')->>'status' as st3 \gset
select crmf_referral_apply(tt.cid('01711731604'), :'codea')->>'status' as st4 \gset
-- C: first bill 300 < 500 -> closed, no reward.
select record_sale2(gen_random_uuid(),1,'[{"amount":300}]',0,'[{"mode":"cash","amount":300}]','01711731603','test_ref_c','retail',null,true) is not null as sC \gset
reset role;
select tt.chk('T3 first bill below the minimum: link closed, no points', tt.rstat(tt.cid('01711731603'))='rejected' and tt.nref(tt.cid('01711731601'))=0 and tt.nref(tt.cid('01711731603'))=0);
-- D: first bill 1200 -> A +50, D +20 (plus D earns 12 sale points: floor(1200 x 1 /100))
set role authenticated; select tt.as(:'u_c');
select (record_sale2(gen_random_uuid(),1,'[{"amount":1200}]',0,'[{"mode":"cash","amount":1200}]','01711731604','test_ref_d','retail',null,true))->>'id' as sd \gset
reset role;
select tt.chk('T3 first bill 1200: referrer +50 and new customer +20, status rewarded, sale recorded', tt.bal(tt.cid('01711731601'))=50 and tt.nref(tt.cid('01711731601'))=1 and tt.nref(tt.cid('01711731604'))=1
  and tt.bal(tt.cid('01711731604'))=20+12 and tt.rstat(tt.cid('01711731604'))='rewarded' and (select first_sale_id::text from crmf_referrals where referred_id=tt.cid('01711731604'))=:'sd');
set role authenticated; select tt.as(:'u_c');
select record_sale2(gen_random_uuid(),1,'[{"amount":1200}]',0,'[{"mode":"cash","amount":1200}]','01711731604','test_ref_d','retail',null,true) is not null as sD2 \gset
reset role;
select tt.chk('T3 a second sale pays nothing more', tt.bal(tt.cid('01711731601'))=50 and tt.nref(tt.cid('01711731604'))=1);
-- the referrer spends 40 of the 50 before the first sale is voided: the take-back is only the 10 left, balance never negative
insert into customer_points_ledger (customer_id, delta, reason, note) values (tt.cid('01711731601'), -40, 'redeem', 'test spend');
set role authenticated; select tt.as(:'u_m');
select void_sale(:'sd'::uuid, 'test void of the first sale');
reset role;
select tt.chk('T3 void of the first sale: referrer takes back only what is left (10), balance 0 not below, link reversed', tt.bal(tt.cid('01711731601'))=0 and tt.rstat(tt.cid('01711731604'))='reversed');
select tt.chk('T3 new customer: welcome 20 and the 12 sale points are taken back, second sale points stay', tt.bal(tt.cid('01711731604'))=12 and (select count(*) from customer_points_ledger where customer_id=tt.cid('01711731604') and delta<0)=2);
select tt.chk('T3 no negative balance anywhere', (select count(*) from (select customer_id from customer_points_ledger group by 1 having sum(delta)<0) z)=0);

\echo == T4 loyalty points OFF: no reward is written
set role authenticated; select tt.as(:'u_o');
select set_rule('loyalty_points_on','false'::jsonb) is null as l0 \gset
select crmf_referral_apply(tt.cid('01711731605'), :'codea')->>'status' as st5 \gset
select tt.as(:'u_c');
select record_sale2(gen_random_uuid(),1,'[{"amount":1200}]',0,'[{"mode":"cash","amount":1200}]','01711731605','test_ref_e','retail',null,true) is not null as sE \gset
reset role;
select tt.chk('T4 loyalty OFF: link stays pending, no referral points', tt.rstat(tt.cid('01711731605'))='pending' and tt.nref(tt.cid('01711731605'))=0);

\echo == T5 reject with a reason; permissions
set role authenticated; select tt.as(:'u_o');
select set_rule('loyalty_points_on','true'::jsonb) is null as l1 \gset
select crmf_referral_apply(tt.cid('01711731606'), :'codea')->>'status' as st6 \gset
select id as rid6 from crmf_referrals where referred_id = tt.cid('01711731606') \gset
select tt.as(:'u_c');
select tt.err('T5 a cashier cannot reject', format($$select crmf_referral_reject(%s, 'not a real friend')$$, :rid6), 'not allowed');
select tt.as(:'u_m');
select tt.err('T5 a customer_manage holder alone cannot reject (needs the loyalty grant)', format($$select crmf_referral_reject(%s, 'not a real friend')$$, :rid6), 'not allowed');
select tt.as(:'u_l');
select tt.err('T5 a reason is required', format($$select crmf_referral_reject(%s, ' ')$$, :rid6), 'reason_required');
select tt.chk('T5 the loyalty manager rejects with a reason', crmf_referral_reject(:rid6, 'not a real friend')->>'status'='rejected');
select tt.err('T5 a decided referral cannot be rejected again', format($$select crmf_referral_reject(%s, 'again please')$$, :rid6), 'not_pending');
select tt.chk('T5 the list shows it (manager only)', jsonb_array_length(crmf_referral_list('rejected'))>=1);
select tt.as(:'u_c');
select tt.err('T5 a cashier cannot read the list', $$select crmf_referral_list()$$, 'not allowed');
select tt.as(:'u_n');
select tt.err('T5 staff without rights cannot make a code', $$select crmf_referral_code((select id from customers where mobile='01711731601'))$$, 'not allowed');
select tt.err('T5 staff without rights cannot link', $$select crmf_referral_apply((select id from customers where mobile='01711731608'), 'ABCDEF')$$, 'not allowed');
select tt.err('T5 a signed-in user cannot write the table', $$update crmf_referrals set status='rewarded'$$, 'permission denied');
reset role;

\echo == T6 books untouched, paste twice
select tt.chk('T6 sale totals are what record_sale2 computed (referral changed no sale)', (select count(*) from sales where customer_id in (tt.cid('01711731604')) and total=1200)=2);
select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.proname)) as h1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%crmf%' \gset
\i supabase/phase317.sql
select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.proname)) as h2 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%crmf%' \gset
select tt.chk('T6 paste twice: functions identical, values kept, triggers once', :'h1'=:'h2' and rule_num('crm_referral_reward_points')=50 and (select count(*) from pg_trigger where tgname in ('sales_referral_crmf','sales_referral_void_crmf'))=2);
select tt.chk('T6 the books: no journal entry came from referral work beyond what sales posting did (referral writes none)', (select count(*) from journal_entries where source_type like 'crmf%')=0);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
