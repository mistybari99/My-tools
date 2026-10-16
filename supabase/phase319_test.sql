-- FRESH DB ONLY. Phase 319 tests (CRM-F: birthday / anniversary / festival hooks, points statement, loyalty summary, status). Build: phases 8..98, then 316..319.
--   psql -h /tmp -p 5574 -U postgres -d crmf_d -qAt -f supabase/phase319_test.sql | grep -E 'FAIL|RESULT'      (run from the repo root)
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000031901'
\set u_m '00000000-0000-0000-0000-000000031902'
\set u_c '00000000-0000-0000-0000-000000031903'
\set u_l '00000000-0000-0000-0000-000000031904'
\set u_n '00000000-0000-0000-0000-000000031905'
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
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.je() returns bigint language sql security definer as $$ select count(*) from public.journal_entries $$;
create or replace function tt.bal(p_c uuid) returns int language sql security definer as $$ select coalesce(sum(delta),0)::int from public.customer_points_ledger where customer_id = p_c $$;
create or replace function tt.cid(p_mobile text) returns uuid language sql security definer as $$ select id from public.customers where mobile = p_mobile $$;
create or replace function tt.grants() returns bigint language sql security definer as $$ select count(*) from public.crmf_hook_grants $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner319@s.app','{"full_name":"test_owner319"}'), (:'u_m','test_mgr319@s.app','{"full_name":"test_mgr319"}'), (:'u_c','test_cash319@s.app','{"full_name":"test_cash319"}'),
 (:'u_l','test_loy319@s.app','{"full_name":"test_loy319"}'), (:'u_n','test_none319@s.app','{"full_name":"test_none319"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_m', :'u_c', :'u_l', :'u_n');
insert into user_roles values (:'u_o','owner'),(:'u_m','showroom_manager'),(:'u_c','salesperson'),(:'u_l','management'),(:'u_n','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_m',1),(:'u_c',1),(:'u_l',1),(:'u_n',1) on conflict do nothing;
select tt.as(:'u_o');
select set_user_grant(:'u_m'::uuid,'customer_manage') is null as g1 \gset
select set_user_grant(:'u_l'::uuid,'crm_loyalty_manage') is null as g2 \gset
select tt.je() as je0 \gset
-- customers: A birthday in 3 days, B in 20 days, C today, D anniversary in 5 days (year 1990 / 2015: the year does not matter)
insert into customers (mobile, name, birthday, anniversary) values
 ('01711931601','test_hk_a', (tt.today()+3) - interval '30 years', null), ('01711931602','test_hk_b', (tt.today()+20) - interval '30 years', null),
 ('01711931603','test_hk_c', tt.today() - interval '40 years', null), ('01711931604','test_hk_d', null, (tt.today()+5) - interval '8 years'),
 ('01711931605','test_hk_e', null, null) on conflict do nothing;

\echo == T0 shape
select tt.chk('T0 the switch exists and is OFF', exists (select 1 from rules where key='crm_hooks_on' and module='crm') and not rule_on('crm_hooks_on'));
select tt.chk('T0 tables: RLS, no browser write', (select bool_and(relrowsecurity) from pg_class where relname in ('crmf_hooks','crmf_hook_grants')) and not has_table_privilege('authenticated','public.crmf_hooks','insert') and not has_table_privilege('authenticated','public.crmf_hook_grants','insert'));
select tt.chk('T0 yearly date helper: 29 February counts as 28 February in a year without one; otherwise next time round',
  _crmf_next_occ(date '2000-02-29', date '2027-01-10') = date '2027-02-28' and _crmf_next_occ(date '2000-02-29', date '2028-01-10') = date '2028-02-29'
  and _crmf_next_occ(date '1990-05-05', date '2026-05-06') = date '2027-05-05' and _crmf_next_occ(date '1990-05-05', date '2026-05-05') = date '2026-05-05');

\echo == T1 hook rules
set role authenticated; select tt.as(:'u_c');
select tt.err('T1 a cashier cannot make a hook', $$select crmf_hook_save(null, '{"kind":"birthday","name":"x","offset_days":7,"bonus_points":100}')$$, 'not allowed');
select tt.as(:'u_m');
select tt.err('T1 a customer_manage holder alone cannot make a hook (needs the loyalty grant)', $$select crmf_hook_save(null, '{"kind":"birthday","name":"x","offset_days":7,"bonus_points":100}')$$, 'not allowed');
select tt.as(:'u_l');
select tt.err('T1 a name is required', $$select crmf_hook_save(null, '{"kind":"birthday","offset_days":7}')$$, 'name_required');
select tt.err('T1 a festival hook needs a date (none is invented)', $$select crmf_hook_save(null, '{"kind":"festival","name":"test festival","offset_days":7}')$$, 'festival_date_required');
select tt.err('T1 a festival hook never gives points', format($$select crmf_hook_save(null, '{"kind":"festival","name":"test festival","offset_days":7,"festival_date":"%s","bonus_points":50}')$$, tt.today()+5), 'festival_no_points');
select tt.err('T1 offset above 60 days is refused', $$select crmf_hook_save(null, '{"kind":"birthday","name":"x","offset_days":90}')$$, 'bad_number');
select crmf_hook_save(null, '{"kind":"birthday","name":"test birthday bonus","offset_days":7,"bonus_points":100}') ->> 'id' as hb \gset
select crmf_hook_save(null, '{"kind":"anniversary","name":"test anniversary bonus","offset_days":7,"bonus_points":50}') ->> 'id' as ha \gset
select crmf_hook_save(null, format('{"kind":"festival","name":"test festival","offset_days":7,"festival_date":"%s"}', tt.today()+5)::jsonb) ->> 'id' as hf \gset
select tt.chk('T1 hooks start INACTIVE', (select count(*) from jsonb_array_elements(crmf_hook_list()) e where (e->>'active')::boolean)=0 and jsonb_array_length(crmf_hook_list())=3);
select tt.as(:'u_c');
select tt.err('T1 a cashier cannot read the hook list', $$select crmf_hook_list()$$, 'not allowed');

\echo == T2 switch OFF: nothing is due, nothing is granted
select tt.as(:'u_l');
select crmf_hook_save(:hb::bigint, '{"active":true}') is not null as a1 \gset
select crmf_hook_save(:ha::bigint, '{"active":true}') is not null as a2 \gset
select crmf_hook_save(:hf::bigint, '{"active":true}') is not null as a3 \gset
select tt.chk('T2 OFF: the due list is empty', (crmf_hooks_due()->>'off')::boolean and jsonb_array_length(crmf_hooks_due()->'rows')=0);
select tt.err('T2 OFF: the run is refused', $$select crmf_hook_run(null, false)$$, 'hooks_off');
select tt.as(:'u_o');
select set_rule('crm_hooks_on','true'::jsonb) is null as on1 \gset
select tt.as(:'u_l');
-- due within 7 days: A (3 days) and C (today) birthdays; D anniversary (5 days); B (20 days) not; the festival hook (5 days) has no customer.
select tt.chk('T2 ON: birthdays of A and C and the anniversary of D are due, B is not, the festival row has no customer',
  (select count(*) from jsonb_array_elements(crmf_hooks_due()->'rows') e where e->>'kind'='birthday' and e->>'customer_name' in ('test_hk_a','test_hk_c'))=2
  and (select count(*) from jsonb_array_elements(crmf_hooks_due()->'rows') e where e->>'customer_name'='test_hk_b')=0
  and (select count(*) from jsonb_array_elements(crmf_hooks_due()->'rows') e where e->>'kind'='anniversary' and e->>'customer_name'='test_hk_d')=1
  and (select count(*) from jsonb_array_elements(crmf_hooks_due()->'rows') e where e->>'kind'='festival' and e->>'customer_name' is null)=1);
select tt.chk('T2 the phone is masked in the list', (select bool_and(e->>'mobile' like '017%****%') from jsonb_array_elements(crmf_hooks_due()->'rows') e where e->>'customer_name' is not null));
select tt.chk('T2 a dry run counts 3 (A, C birthday 100 each; D anniversary 50), writes nothing', (crmf_hook_run(null, true)->>'due')::int=3 and tt.grants()=0 and tt.bal(tt.cid('01711931601'))=0);
select tt.err('T2 loyalty points OFF: a real run is refused', $$select crmf_hook_run(null, false)$$, 'loyalty_off');
select tt.as(:'u_o');
select set_rule('loyalty_points_on','true'::jsonb) is null as lp \gset
select tt.as(:'u_c');
select tt.err('T2 a cashier cannot run it', $$select crmf_hook_run(null, false)$$, 'not allowed');
select tt.as(:'u_l');
select crmf_hook_run(null, false) ->> 'granted' as g3, crmf_hook_run(null, true) ->> 'due' as d3 \gset
select tt.chk('T2 the real run granted 3 times (A and C 100 each, D 50 = 250 points); a repeat finds nothing due', :'g3'::int=3 and :'d3'::int=0 and tt.grants()=3);
select tt.chk('T2 balances: A 100, C 100, D 50, B 0, E 0', tt.bal(tt.cid('01711931601'))=100 and tt.bal(tt.cid('01711931603'))=100 and tt.bal(tt.cid('01711931604'))=50 and tt.bal(tt.cid('01711931602'))=0 and tt.bal(tt.cid('01711931605'))=0);
select tt.chk('T2 the second run the same year grants nothing more', (crmf_hook_run(null, false)->>'granted')::int=0 and tt.grants()=3);
select tt.chk('T2 the ledger rows are reason bonus with the hook name', (select count(*) from jsonb_array_elements(crmf_points_statement(tt.cid('01711931601'))->'rows') e where e->>'reason'='bonus' and e->>'note' like 'test birthday bonus%')=1);
select tt.chk('T2 the due list now marks them granted', (select bool_and((e->>'granted')::boolean) from jsonb_array_elements(crmf_hooks_due()->'rows') e where e->>'customer_name' is not null));
select tt.as(:'u_n');
select tt.err('T2 staff without rights cannot see the due list', $$select crmf_hooks_due()$$, 'not allowed');
reset role;
select tt.err('T2 a grant row is append-only', $$update crmf_hook_grants set points=1$$, 'append_only');
select tt.err('T2 a hook is never deleted', $$delete from crmf_hooks$$, '');

\echo == T3 points statement
-- customer F: +100 (20 days ago), +50 (10 days ago), -30 redeem (5 days ago), +20 (2 days ago) = 140
insert into customers (mobile, name) values ('01711931606','test_hk_f') on conflict do nothing;
insert into customer_points_ledger (customer_id, delta, reason, note, at) values
 (tt.cid('01711931606'), 100, 'adjust', 'a', now() - interval '20 days'), (tt.cid('01711931606'), 50, 'adjust', 'b', now() - interval '10 days'),
 (tt.cid('01711931606'), -30, 'redeem', 'c', now() - interval '5 days'), (tt.cid('01711931606'), 20, 'adjust', 'd', now() - interval '2 days');
set role authenticated; select tt.as(:'u_c');
select tt.chk('T3 whole history: opening 0, closing 140, earned 170, used 30, running balances 100 / 150 / 120 / 140',
  (crmf_points_statement(tt.cid('01711931606'))->>'opening')::int=0 and (crmf_points_statement(tt.cid('01711931606'))->>'closing')::int=140 and (crmf_points_statement(tt.cid('01711931606'))->>'earned')::int=170
  and (crmf_points_statement(tt.cid('01711931606'))->>'used')::int=30
  and (select array_agg((e->>'balance')::int order by (e->>'id')::int) from jsonb_array_elements(crmf_points_statement(tt.cid('01711931606'))->'rows') e)=array[100,150,120,140]);
select tt.chk('T3 a range from 7 days ago: opening 150, closing 140, earned 20, used 30, two rows with the running balance carried on',
  (crmf_points_statement(tt.cid('01711931606'), tt.today()-7)->>'opening')::int=150 and (crmf_points_statement(tt.cid('01711931606'), tt.today()-7)->>'closing')::int=140
  and (crmf_points_statement(tt.cid('01711931606'), tt.today()-7)->>'earned')::int=20 and (crmf_points_statement(tt.cid('01711931606'), tt.today()-7)->>'used')::int=30
  and jsonb_array_length(crmf_points_statement(tt.cid('01711931606'), tt.today()-7)->'rows')=2);
select tt.chk('T3 balance now and its value in taka (point value 1)', (crmf_points_statement(tt.cid('01711931606'))->>'balance_now')::int=140 and (crmf_points_statement(tt.cid('01711931606'))->>'value_taka')::numeric=140);
select tt.err('T3 end before start', format($$select crmf_points_statement(%L::uuid, current_date, current_date - 5)$$, tt.cid('01711931606')), 'bad_date');
select tt.err('T3 unknown customer', $$select crmf_points_statement(gen_random_uuid())$$, 'customer_not_found');
select tt.as(:'u_n');
select tt.err('T3 staff without rights cannot read a statement', format($$select crmf_points_statement(%L::uuid)$$, tt.cid('01711931606')), 'not allowed');

\echo == T4 loyalty summary
select tt.as(:'u_c');
select tt.err('T4 a cashier cannot read the summary', $$select crmf_loyalty_summary()$$, 'not allowed');
select tt.as(:'u_m');
-- everything in the last 30 days: F's ledger (+170, -30 redeem), the three bonus grants (+250)
select tt.chk('T4 points in the last 30 days: adjusted up 170 + 0, redeemed 30, bonus 250', (crmf_loyalty_summary(tt.today()-30, tt.today())->'points'->>'adjusted_up')::int=170 and (crmf_loyalty_summary(tt.today()-30, tt.today())->'points'->>'redeemed')::int=30
  and (crmf_loyalty_summary(tt.today()-30, tt.today())->'points'->>'earned_bonus')::int=250);
select tt.chk('T4 outstanding points = 140 (F) + 250 (bonus) = 390 with 4 members; value 390 taka; the note says it is not booked',
  (crmf_loyalty_summary()->>'outstanding_points')::int=390 and (crmf_loyalty_summary()->>'members_with_points')::int=4 and (crmf_loyalty_summary()->>'outstanding_value_taka')::numeric=390 and crmf_loyalty_summary()->>'note' like '%not booked%');
select tt.chk('T4 hooks: 3 grants and 250 points', (crmf_loyalty_summary(tt.today()-30, tt.today())->'hooks'->>'grants')::int=3 and (crmf_loyalty_summary(tt.today()-30, tt.today())->'hooks'->>'points')::int=250);
select tt.chk('T4 referral, coupon and liability blocks are present and zero', (crmf_loyalty_summary()->'referrals'->>'rewarded')::int=0 and (crmf_loyalty_summary()->'coupons'->>'uses')::int=0 and (crmf_loyalty_summary()->>'voucher_liability_held')::numeric=0);
select tt.err('T4 end before start', $$select crmf_loyalty_summary(current_date, current_date - 3)$$, 'bad_date');

\echo == T5 status
select tt.as(:'u_c');
select tt.chk('T5 a cashier sees the switches and what is still blank, and cannot manage', crmf_status()->'voucher'->>'on'='false' and crmf_status()->'expiry'->>'months' is null and not (crmf_status()->'can'->>'manage')::boolean and (crmf_status()->>'hooks_on')::boolean);
select tt.as(:'u_o');
select tt.chk('T5 the owner can manage and apply', (crmf_status()->'can'->>'manage')::boolean and (crmf_status()->'can'->>'apply')::boolean and (crmf_status()->'can'->>'override')::boolean);
select tt.as(:'u_n');
select tt.err('T5 staff without rights get nothing', $$select crmf_status()$$, 'not allowed');

\echo == T6 books untouched, paste twice
reset role;
select tt.chk('T6 no journal entry from hooks, statement or summary', tt.je()=:je0);
select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.proname)) as h1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%crmf%' \gset
\i supabase/phase319.sql
select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.proname)) as h2 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%crmf%' \gset
select tt.chk('T6 paste twice: functions identical, hooks and grants kept', :'h1'=:'h2' and tt.grants()=3 and (select count(*) from crmf_hooks)=3);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
