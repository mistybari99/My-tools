-- FRESH DB ONLY. Phase 316 tests (CRM-F: points expiry, burn rules, manual adjustment alert, shared helpers).
--   bash tests/sql/crmf_build.sh crmf_a ; psql -h /tmp -p 5574 -U postgres -d crmf_a -qAt -f supabase/phase316.sql ; run this file from the repo root:
--   psql -h /tmp -p 5574 -U postgres -d crmf_a -qAt -f supabase/phase316_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000031601'
\set u_m '00000000-0000-0000-0000-000000031602'
\set u_c '00000000-0000-0000-0000-000000031603'
\set u_l '00000000-0000-0000-0000-000000031604'
\set u_n '00000000-0000-0000-0000-000000031605'
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
create or replace function tt.aud(p_action text) returns bigint language sql security definer as $$ select count(*) from public.audit_log where action = p_action $$;
create or replace function tt.je() returns bigint language sql security definer as $$ select count(*) from public.journal_entries $$;
create or replace function tt.bal(p_c uuid) returns int language sql security definer as $$ select coalesce(sum(delta),0)::int from public.customer_points_ledger where customer_id = p_c $$;
create or replace function tt.exc(p_flag text) returns bigint language sql security definer as $$ select count(*) from public.exceptions where flag_code = p_flag $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner316@s.app','{"full_name":"test_owner316"}'), (:'u_m','test_mgr316@s.app','{"full_name":"test_mgr316"}'), (:'u_c','test_cash316@s.app','{"full_name":"test_cash316"}'),
 (:'u_l','test_loy316@s.app','{"full_name":"test_loy316"}'), (:'u_n','test_none316@s.app','{"full_name":"test_none316"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_m', :'u_c', :'u_l', :'u_n');
insert into user_roles values (:'u_o','owner'),(:'u_m','showroom_manager'),(:'u_c','salesperson'),(:'u_l','management'),(:'u_n','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_m',1),(:'u_c',1),(:'u_l',1),(:'u_n',1) on conflict do nothing;
select tt.as(:'u_o');
select set_user_grant(:'u_m'::uuid,'customer_manage') is null as g1 \gset
select set_user_grant(:'u_l'::uuid,'crm_loyalty_manage') is null as g2 \gset
select set_rule('loyalty_points_on', 'true'::jsonb) is null as r1 \gset
select tt.je() as je0 \gset

-- customers and a hand-built ledger (as the table owner; the dates are set back on purpose)
insert into customers (mobile, name) values ('01711631601','test_cust_a'),('01711631602','test_cust_b'),('01711631603','test_cust_c'),('01711631604','test_cust_d'),('01711631605','test_cust_e') on conflict do nothing;
select id as ca from customers where mobile='01711631601' \gset
select id as cb from customers where mobile='01711631602' \gset
select id as cc from customers where mobile='01711631603' \gset
select id as cd from customers where mobile='01711631604' \gset
select id as ce from customers where mobile='01711631605' \gset
-- A: +100 (400 days ago), +50 (200 days ago), -30 redeem (100 days ago), +20 (10 days ago) = 140.   B: +100 (10 days ago).   C: +100 (400 d) then -100 redeem (399 d) = 0.   D: +80 (400 d).   E: +500 today (burn tests)
insert into customer_points_ledger (customer_id, delta, reason, note, at) values
 (:'ca', 100, 'adjust', 't', now() - interval '400 days'), (:'ca', 50, 'adjust', 't', now() - interval '200 days'), (:'ca', -30, 'redeem', 't', now() - interval '100 days'), (:'ca', 20, 'adjust', 't', now() - interval '10 days'),
 (:'cb', 100, 'adjust', 't', now() - interval '10 days'),
 (:'cc', 100, 'adjust', 't', now() - interval '400 days'), (:'cc', -100, 'redeem', 't', now() - interval '399 days'),
 (:'cd', 80, 'adjust', 't', now() - interval '400 days'),
 (:'ce', 500, 'adjust', 't', now());

\echo == T0 shape, safe defaults, nothing shared patched
select tt.chk('T0 phase316 present', to_regprocedure('public._crmf_present()') is not null);
select tt.chk('T0 seven settings exist, blank, English text, module crm',
  (select count(*) from rules where key in ('crm_points_expiry_months','crm_points_expiry_from','crm_points_expiry_warn_days','crm_burn_max_percent','crm_burn_max_points','crm_burn_step_points','crm_points_adjust_alert_over') and module='crm' and value is null and default_value is null)=7
  and not exists (select 1 from rules where key like 'crm\_%' and (label_en ~ '[^\x01-\x7f]' or label_bn is distinct from label_en)));
select tt.chk('T0 the grant exists', exists (select 1 from grant_defs where grant_code='crm_loyalty_manage'));
select tt.chk('T0 the ledger accepts referral and bonus, keeps the old four',
  (select pg_get_constraintdef(oid) from pg_constraint where conrelid='customer_points_ledger'::regclass and contype='c' and pg_get_constraintdef(oid) like '%reason%') ~ 'referral'
  and (select pg_get_constraintdef(oid) from pg_constraint where conrelid='customer_points_ledger'::regclass and contype='c' and pg_get_constraintdef(oid) like '%reason%') ~ 'expire');
select tt.chk('T0 no existing function was re-created (record_sale2, customer_points_redeem, customer_points_adjust carry no crmf text)',
  (select count(*) from pg_proc where proname in ('record_sale2','customer_points_redeem','customer_points_adjust','loyalty_award') and position('crmf' in pg_get_functiondef(oid))>0)=0);
select tt.chk('T0 new tables: RLS on, no write for browser roles',
  (select bool_and(relrowsecurity) from pg_class where relname in ('crmf_expiry_runs','crmf_expiry_lines'))
  and not has_table_privilege('authenticated','public.crmf_expiry_runs','insert') and not has_table_privilege('anon','public.crmf_expiry_runs','select') and not has_table_privilege('authenticated','public.crmf_expiry_lines','delete'));
select tt.chk('T0 API open to signed-in users only; helpers closed',
  has_function_privilege('authenticated','public.crmf_points_expiry_apply(uuid,text)','execute') and not has_function_privilege('anon','public.crmf_points_expiry_apply(uuid,text)','execute')
  and not has_function_privilege('authenticated','public._crmf_expiry_rows(date,date,uuid)','execute') and not has_function_privilege('authenticated','public._crmf_exception(text,int,date,numeric,text,uuid)','execute'));

\echo == T1 expiry
set role authenticated; select tt.as(:'u_o');
select tt.chk('T1 blank months: preview says off (months_blank), nothing listed', (crmf_points_expiry_preview()->>'off')::boolean and crmf_points_expiry_preview()->>'reason'='months_blank' and (crmf_points_expiry_preview()->>'points')::int=0);
select tt.err('T1 blank months: apply is refused', $$select crmf_points_expiry_apply(gen_random_uuid(), 'x')$$, 'expiry_not_set');
select set_rule('crm_points_expiry_months', '6'::jsonb) is null as s1 \gset
select tt.chk('T1 months set but no effective-from date: still off (from_blank)', crmf_points_expiry_preview()->>'reason'='from_blank');
select tt.err('T1 a bad date is refused when written', $$select set_rule('crm_points_expiry_from', '"2025-13-45"'::jsonb)$$, 'bad_value');
select tt.err('T1 text that is not a date is refused', $$select set_rule('crm_points_expiry_from', '"abc"'::jsonb)$$, 'bad_value');
select set_rule('crm_points_expiry_from', to_jsonb((tt.today() - 500)::text)) is null as s2 \gset
select count(*) as led0 from customer_points_ledger \gset
-- cut = today - 6 months. A earned 150 on or before the cut, used 30 -> min(140, 150-30) = 120. B earned nothing before the cut -> 0. C balance 0 -> 0. D: 80 earned 400 days ago but the effective date is today-500 -> counts: min(80, 80-0)=80.
select tt.chk('T1 preview: A 120 and D 80 can expire, B and C and E cannot -> 2 customers, 200 points', (crmf_points_expiry_preview()->>'customers')::int=2 and (crmf_points_expiry_preview()->>'points')::int=200);
select tt.chk('T1 preview wrote nothing', (select count(*) from customer_points_ledger)=:led0 and not exists (select 1 from crmf_expiry_runs));
select tt.chk('T1 preview lists names', (select count(*) from jsonb_array_elements(crmf_points_expiry_preview()->'sample') e where e->>'name' in ('test_cust_a','test_cust_d'))=2);
-- the effective-from date protects old points: move it to 100 days ago: D (80, earned 400 d ago) now counts as earned 100 days ago, after the cut -> 0; A: 100 and 50 count as earned on the from date -> 0 too.
select set_rule('crm_points_expiry_from', to_jsonb((tt.today() - 100)::text)) is null as s3 \gset
select tt.chk('T1 effective-from date later than the cut: old points are not wiped (0 points)', (crmf_points_expiry_preview()->>'points')::int=0);
select set_rule('crm_points_expiry_from', to_jsonb((tt.today() - 500)::text)) is null as s4 \gset
-- permissions
select tt.as(:'u_m');
select tt.chk('T1 a customer_manage holder may preview', (crmf_points_expiry_preview()->>'points')::int=200);
select tt.err('T1 a customer_manage holder may NOT apply', $$select crmf_points_expiry_apply(gen_random_uuid(), 'x')$$, 'not allowed');
select tt.as(:'u_c');
select tt.err('T1 a cashier cannot preview', $$select crmf_points_expiry_preview()$$, 'not allowed');
select tt.err('T1 a cashier cannot apply', $$select crmf_points_expiry_apply(gen_random_uuid(), 'x')$$, 'not allowed');
select tt.as(:'u_n');
select tt.err('T1 staff without any customer right cannot preview', $$select crmf_points_expiry_preview()$$, 'not allowed');
select tt.err('T1 staff without any customer right cannot apply', $$select crmf_points_expiry_apply(gen_random_uuid(), 'x')$$, 'not allowed');
select tt.err('T1 a signed-in user cannot write the run table', $$insert into crmf_expiry_runs (as_of,cut_date,months,from_date) values (current_date,current_date,1,current_date)$$, 'permission denied');
-- apply by the loyalty manager (grant)
select tt.as(:'u_l');
select gen_random_uuid() as cl1 \gset
select crmf_points_expiry_apply(:'cl1', 'first run') ->> 'run_id' as run1 \gset
select tt.chk('T1 apply: A lost 120 (140 -> 20), D lost 80 (80 -> 0), B untouched, nobody below zero', tt.bal(:'ca')=20 and tt.bal(:'cd')=0 and tt.bal(:'cb')=100 and tt.bal(:'cc')=0 and tt.bal(:'ce')=500);
select tt.chk('T1 the run lists 2 customers and 200 points', (select customers=2 and points=200 from jsonb_to_recordset(crmf_points_expiry_runs(5)) as x(id bigint, customers int, points int) where id=:run1));
select tt.chk('T1 expire rows are reason expire with the run in the note', (select count(*) from customer_points_ledger where reason='expire' and note like 'expiry run ' || :run1 || '%')=2);
select tt.chk('T1 same client id again: dup, nothing new', (crmf_points_expiry_apply(:'cl1','first run')->>'dup')::boolean and (select count(*) from customer_points_ledger where reason='expire')=2);
select tt.chk('T1 a second apply the same day finds nothing (no run, no rows)', crmf_points_expiry_apply(gen_random_uuid(),'again')->>'run_id' is null and (select count(*) from customer_points_ledger where reason='expire')=2);
select tt.chk('T1 apply wrote an audit line', tt.aud('crmf_expiry_apply')=1);
reset role;
select tt.err('T1 the ledger stays append-only (an expire row cannot be edited)', $$update customer_points_ledger set delta=-1 where reason='expire'$$, 'append_only');
select tt.err('T1 the run record stays append-only', $$update crmf_expiry_runs set note='x'$$, 'append_only');
set role authenticated; select tt.as(:'u_o');
-- warn list: warn 200 days. B (+100, 10 days ago) loses them when the cut passes 10 days ago: cut moves forward by 200 days -> 6 months before today+200 is about today+17 -> B and A's 20 both inside.
select set_rule('crm_points_expiry_warn_days', '200'::jsonb) is null as s5 \gset
select tt.chk('T1 warn list: B 100 and A 20 are coming up, the names only and the phone masked',
  (select count(*) from jsonb_array_elements(crmf_points_expiry_soon()->'rows') e where (e->>'name'='test_cust_b' and (e->>'points')::int=100 and e->>'mobile' like '017%****%') or (e->>'name'='test_cust_a' and (e->>'points')::int=20))=2);
select tt.chk('T1 blank warn days: the list is off', (select (crmf_points_expiry_soon(null)->>'off')::boolean from (select set_rule('crm_points_expiry_warn_days', null) ) z));
-- months blank again: nothing expires any more
select set_rule('crm_points_expiry_months', null) is null as s6 \gset
select tt.chk('T1 months blank again: off, apply refused', (crmf_points_expiry_preview()->>'off')::boolean);
select tt.err('T1 months blank: apply refused', $$select crmf_points_expiry_apply(gen_random_uuid(), 'x')$$, 'expiry_not_set');

\echo == T2 burn rules (customer E has 500 points; point value 1 taka; minimum 100)
select tt.chk('T2 all burn rules blank: the wrapper answers like the old function (dry run)', (crmf_points_redeem(:'ce', 150, null, 'n', null, true)->>'value_taka')::numeric = (customer_points_redeem(:'ce', 150, 'n', null, true)->>'value_taka')::numeric
  and (crmf_points_redeem(:'ce', 150, null, 'n', null, true)->>'balance_after')::int=350);
select set_rule('crm_burn_max_percent', '20'::jsonb) is null as b1 \gset
select tt.err('T2 percent cap set but no bill total given', $$select crmf_points_redeem((select id from customers where mobile='01711631605'), 100, null, 'n', null, true)$$, 'bill_total_needed');
select tt.err('T2 bill 1000, cap 20 percent = 200 points: 300 is refused', $$select crmf_points_redeem((select id from customers where mobile='01711631605'), 300, 1000, 'n', null, true)$$, 'over_max_percent');
select tt.chk('T2 200 points on a 1000 bill passes', (crmf_points_redeem(:'ce', 200, 1000, 'n', null, true)->>'value_taka')::numeric=200);
select tt.chk('T2 the check shows the most allowed: 200 points = 200 taka', (crmf_burn_check(:'ce', null, 1000)->>'max_points')::int=200 and (crmf_burn_check(:'ce', null, 1000)->>'max_value_taka')::numeric=200);
select set_rule('crm_burn_max_points', '150'::jsonb) is null as b2 \gset
select set_rule('crm_burn_step_points', '50'::jsonb) is null as b3 \gset
select tt.err('T2 over the points cap (150): 200 refused', $$select crmf_points_redeem((select id from customers where mobile='01711631605'), 200, 1000, 'n', null, true)$$, 'over_max_points');
select tt.err('T2 not in steps of 50: 120 refused', $$select crmf_points_redeem((select id from customers where mobile='01711631605'), 120, 1000, 'n', null, true)$$, 'not_in_steps');
select tt.chk('T2 150 passes (cap 150, step 50)', (crmf_points_redeem(:'ce', 150, 1000, 'n', null, true)->>'value_taka')::numeric=150);
-- the cashier cannot override; the owner can, with a reason
select tt.as(:'u_c');
select tt.err('T2 a cashier cannot pass a burn rule even with a reason', $$select crmf_points_redeem((select id from customers where mobile='01711631605'), 200, 1000, 'n', null, true, 'manager said yes')$$, 'not allowed');
select tt.as(:'u_o');
select tt.err('T2 override without a reason is refused', $$select crmf_points_redeem((select id from customers where mobile='01711631605'), 200, 1000, 'n', null, false, ' ')$$, 'burn_rule');
select tt.err('T2 override with a too-short reason is refused', $$select crmf_points_redeem((select id from customers where mobile='01711631605'), 200, 1000, 'n', null, false, 'x')$$, 'reason_required');
select tt.exc('loyalty_burn_override') as exc0 \gset
select gen_random_uuid() as cl2 \gset
select (crmf_points_redeem(:'ce', 200, 1000, 'override test', :'cl2', false, 'owner agreed for a party order')->>'balance')::int as bal_after \gset
select tt.chk('T2 owner override: 200 points used, balance 300, audit line, yellow Exceptions row',
  :bal_after=300 and tt.bal(:'ce')=300 and tt.aud('crmf_burn_override')=1 and tt.exc('loyalty_burn_override')=:exc0+1);
select tt.chk('T2 same client id again: dup, no second redeem', (crmf_points_redeem(:'ce', 200, 1000, 'override test', :'cl2', false, 'owner agreed for a party order')->>'dup')::boolean and tt.bal(:'ce')=300 and tt.aud('crmf_burn_override')=1 and tt.exc('loyalty_burn_override')=:exc0+1);
select tt.err('T2 more than the balance is refused even with an override (never below zero)', $$select crmf_points_redeem((select id from customers where mobile='01711631605'), 450, 100000, 'n', null, false, 'owner agreed for a party order')$$, 'not_enough_points');
select tt.err('T2 below the old minimum is still refused (50 < 100)', $$select crmf_points_redeem((select id from customers where mobile='01711631605'), 50, 1000, 'n', null, false, 'owner agreed for a party order')$$, 'below_min_points');
select tt.chk('T2 balance is still 300 after the refusals', tt.bal(:'ce')=300);
select tt.as(:'u_n');
select tt.err('T2 staff without POS or customer rights cannot redeem', $$select crmf_points_redeem((select id from customers where mobile='01711631605'), 100, 1000, 'n', null, true)$$, 'not allowed');
select tt.err('T2 ... or check', $$select crmf_burn_check((select id from customers where mobile='01711631605'), 100, 1000)$$, 'not allowed');

\echo == T3 manual adjustment alert
select tt.as(:'u_o');
select set_rule('crm_points_adjust_alert_over', '50'::jsonb) is null as a1 \gset
select tt.exc('loyalty_adjust_large') as ex1 \gset
select tt.as(:'u_m');
select tt.chk('T3 +10 (below the alert) no Exceptions row', (crmf_points_adjust(:'cb', 10, 'goodwill after a complaint')->>'balance')::int=110 and tt.exc('loyalty_adjust_large')=:ex1);
select tt.chk('T3 +100 (above 50): done, with a yellow Exceptions row', (crmf_points_adjust(:'cb', 100, 'compensation for a late cake order')->>'balance')::int=210 and tt.exc('loyalty_adjust_large')=:ex1+1);
select tt.err('T3 a reason is required', $$select crmf_points_adjust((select id from customers where mobile='01711631602'), 5, 'ab')$$, 'note_required');
select tt.err('T3 below zero is refused', $$select crmf_points_adjust((select id from customers where mobile='01711631602'), -5000, 'wrong entry fix')$$, 'not_enough_points');
select tt.chk('T3 the balance did not move on the refusals', tt.bal(:'cb')=210);
select tt.as(:'u_c');
select tt.err('T3 a cashier cannot adjust points', $$select crmf_points_adjust((select id from customers where mobile='01711631602'), 5, 'try it on')$$, 'not allowed');
select tt.as(:'u_m');
select tt.chk('T3 an idempotent client id changes nothing the second time',
  (crmf_points_adjust(:'cb', 7, 'once only', '00000000-0000-0000-0000-0000000316aa')->>'dup')::boolean is false
  and (crmf_points_adjust(:'cb', 7, 'once only', '00000000-0000-0000-0000-0000000316aa')->>'dup')::boolean and tt.bal(:'cb')=217);

\echo == T4 nothing touched the books, paste twice
reset role;
select tt.chk('T4 no journal entry was written by anything in this phase', tt.je()=:je0);
select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.proname)) as h1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%crmf%' \gset
select count(*) as nrules1 from rules where key like 'crm\_%' \gset
\i supabase/phase316.sql
select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.proname)) as h2 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%crmf%' \gset
select tt.chk('T4 paste twice: functions byte for byte identical, rules not duplicated, values kept', :'h1'=:'h2' and (select count(*) from rules where key like 'crm\_%')=:nrules1 and rule_num('crm_burn_max_percent')=20);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
