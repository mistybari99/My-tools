-- FRESH DB ONLY. Phase 318 tests (CRM-F: coupons and vouchers, redemption log, voucher liability). Build: phases 8..98, then 316, 317, 318.
--   psql -h /tmp -p 5574 -U postgres -d crmf_c -qAt -f supabase/phase318_test.sql | grep -E 'FAIL|RESULT'      (run from the repo root)
-- Test data only (test_* names). The double-redemption race (two sessions at once) is tests/sql/crmf_race.sh.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000031801'
\set u_m '00000000-0000-0000-0000-000000031802'
\set u_c '00000000-0000-0000-0000-000000031803'
\set u_v '00000000-0000-0000-0000-000000031804'
\set u_n '00000000-0000-0000-0000-000000031805'
\set u_x '00000000-0000-0000-0000-000000031806'
\set u_a '00000000-0000-0000-0000-000000031807'
\set u_c2 '00000000-0000-0000-0000-000000031808'
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
create or replace function tt.q(p_sql text) returns text language plpgsql security definer as $$ declare r text; begin execute p_sql into r; return r; end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.je() returns bigint language sql security definer as $$ select count(*) from public.journal_entries $$;
create or replace function tt.unbalanced() returns bigint language sql security definer as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.cid(p_mobile text) returns uuid language sql security definer as $$ select id from public.customers where mobile = p_mobile $$;
create or replace function tt.exc(p_flag text) returns bigint language sql security definer as $$ select count(*) from public.exceptions where flag_code = p_flag $$;
create or replace function tt.aud(p_action text) returns bigint language sql security definer as $$ select count(*) from public.audit_log where action = p_action $$;
create or replace function tt.cp(p_code text) returns uuid language sql security definer as $$ select id from public.crmf_coupons where code = p_code $$;
create or replace function tt.uses(p_code text) returns bigint language sql security definer as $$ select count(*) from public.crmf_coupon_uses u join public.crmf_coupons c on c.id = u.coupon_id where c.code = p_code $$;
create or replace function tt.held(p_code text) returns numeric language sql security definer as $$ select coalesce(sum(p.delta),0) from public.crmf_liab_postings p join public.crmf_coupons c on c.id = p.coupon_id where c.code = p_code $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner318@s.app','{"full_name":"test_owner318"}'), (:'u_m','test_mgr318@s.app','{"full_name":"test_mgr318"}'), (:'u_c','test_cash318@s.app','{"full_name":"test_cash318"}'),
 (:'u_v','test_issuer318@s.app','{"full_name":"test_issuer318"}'), (:'u_n','test_none318@s.app','{"full_name":"test_none318"}'), (:'u_x','test_override318@s.app','{"full_name":"test_override318"}'),
 (:'u_a','test_acct318@s.app','{"full_name":"test_acct318"}'), (:'u_c2','test_cash2_318@s.app','{"full_name":"test_cash2_318"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_m', :'u_c', :'u_v', :'u_n', :'u_x', :'u_a', :'u_c2');
insert into user_roles values (:'u_o','owner'),(:'u_m','showroom_manager'),(:'u_c','salesperson'),(:'u_v','management'),(:'u_n','storekeeper'),(:'u_x','salesperson'),(:'u_a','management'),(:'u_c2','salesperson') on conflict do nothing;
insert into user_locations values (:'u_m',1),(:'u_c',1),(:'u_v',1),(:'u_n',1),(:'u_x',1),(:'u_a',1),(:'u_c2',1) on conflict do nothing;
select tt.as(:'u_o');
select set_user_grant(:'u_m'::uuid,'customer_manage') is null as g1 \gset
select set_user_grant(:'u_v'::uuid,'crm_voucher_issue') is null as g2 \gset
select set_user_grant(:'u_x'::uuid,'crm_coupon_override') is null as g3 \gset
select set_user_grant(:'u_a'::uuid,'accounts_manage') is null as g4 \gset
insert into location_settings (location_id,key,value) values (1,'discount_limit','500'),(2,'discount_limit','500') on conflict (location_id,key) do update set value='500';
insert into items (code, name_bn, name_en, category, sell_price, is_active) values ('T-CRMF-X','test_item_x','test_item_x','test_cat_a',200,true),('T-CRMF-Y','test_item_y','test_item_y','test_cat_b',300,true) on conflict do nothing;
select id as ix from items where code='T-CRMF-X' \gset
select id as iy from items where code='T-CRMF-Y' \gset
insert into customers (mobile, name) values ('01711831601','test_cp_a'),('01711831602','test_cp_b'),('01711831603','test_cp_c'),('01711831604','test_cp_d'),('01711831605','test_cp_e'),('01711831606','test_cp_f') on conflict do nothing;
select tt.je() as je0 \gset

\echo == T0 shape, defaults
select tt.chk('T0 seven settings: voucher OFF, liability OFF, every number / date / account blank', (select count(*) from rules where key in ('crm_voucher_on','crm_voucher_max_percent','crm_voucher_max_amount','crm_voucher_liability_on','crm_voucher_liability_from','crm_voucher_liability_account','crm_voucher_expense_account'))=7
  and not rule_on('crm_voucher_on') and not rule_on('crm_voucher_liability_on') and rule_num('crm_voucher_max_percent') is null and rule_num('crm_voucher_max_amount') is null
  and rule_txt('crm_voucher_liability_from') is null and rule_txt('crm_voucher_liability_account') is null and rule_txt('crm_voucher_expense_account') is null);
select tt.chk('T0 two grants exist', (select count(*) from grant_defs where grant_code in ('crm_voucher_issue','crm_coupon_override'))=2);
select tt.chk('T0 four tables: RLS on, no browser write, redemption and posting logs closed to anon',
  (select bool_and(relrowsecurity) from pg_class where relname in ('crmf_coupons','crmf_coupon_scope','crmf_coupon_uses','crmf_liab_postings'))
  and not has_table_privilege('authenticated','public.crmf_coupons','insert') and not has_table_privilege('authenticated','public.crmf_coupon_uses','insert') and not has_table_privilege('anon','public.crmf_coupons','select'));
select tt.chk('T0 helpers closed, API open to signed-in only', not has_function_privilege('authenticated','public._crmf_liab_post(uuid,boolean)','execute') and not has_function_privilege('anon','public.crmf_coupon_check(text,int,uuid,jsonb,numeric,text)','execute')
  and has_function_privilege('authenticated','public.crmf_coupon_redeem_after_sale(text,uuid,text,uuid)','execute'));
select tt.chk('T0 record_sale2 and the journal writer carry no crmf text', position('crmf' in pg_get_functiondef('public.record_sale2(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure))=0 and position('crmf' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))=0);

\echo == T1 creating coupons
set role authenticated; select tt.as(:'u_v');
select tt.err('T1 blank percent maximum: a percent coupon cannot be created', $$select crmf_coupon_save(null, '{"code":"TEST10","name":"test ten","kind":"percent","value":10,"valid_from":"2020-01-01","valid_to":"2099-01-01"}')$$, 'max_percent_not_set');
select tt.err('T1 blank amount maximum: an amount coupon cannot be created', $$select crmf_coupon_save(null, '{"code":"TESTAMT","name":"test amt","kind":"amount","value":50,"valid_from":"2020-01-01","valid_to":"2099-01-01"}')$$, 'max_amount_not_set');
select tt.as(:'u_o');
select set_rule('crm_voucher_max_percent','20'::jsonb) is null as m1 \gset
select set_rule('crm_voucher_max_amount','200'::jsonb) is null as m2 \gset
select tt.as(:'u_c');
select tt.err('T1 a cashier cannot create a coupon', $$select crmf_coupon_save(null, '{"code":"TEST10","name":"test ten","kind":"percent","value":10,"valid_from":"2020-01-01","valid_to":"2099-01-01"}')$$, 'not allowed');
select tt.as(:'u_v');
select tt.err('T1 validity is required', $$select crmf_coupon_save(null, '{"code":"TEST10","name":"test ten","kind":"percent","value":10}')$$, 'validity_required');
select tt.err('T1 bad code', $$select crmf_coupon_save(null, '{"code":"a b","name":"x","kind":"percent","value":10,"valid_from":"2020-01-01","valid_to":"2099-01-01"}')$$, 'bad_code');
select tt.err('T1 end before start', $$select crmf_coupon_save(null, '{"code":"TESTBAD","name":"x","kind":"percent","value":10,"valid_from":"2030-01-01","valid_to":"2029-01-01"}')$$, 'bad_date');
select tt.err('T1 percent above 100', $$select crmf_coupon_save(null, '{"code":"TESTBAD","name":"x","kind":"percent","value":101,"valid_from":"2020-01-01","valid_to":"2099-01-01"}')$$, 'bad_number');
select tt.err('T1 above the maximum percent (20): the issuer is refused', $$select crmf_coupon_save(null, '{"code":"TESTBIG","name":"x","kind":"percent","value":25,"valid_from":"2020-01-01","valid_to":"2099-01-01"}')$$, 'over_maximum');
select tt.err('T1 above the maximum amount (200): the issuer is refused', $$select crmf_coupon_save(null, '{"code":"TESTBIGA","name":"x","kind":"amount","value":250,"valid_from":"2020-01-01","valid_to":"2099-01-01"}')$$, 'over_maximum');
select gen_random_uuid() as clc \gset
select crmf_coupon_save(null, jsonb_build_object('code','test10','name','test ten percent','kind','percent','value',10,'min_bill',500,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'max_uses',2,'per_customer_uses',1), :'clc') ->> 'code' as c1 \gset
select tt.chk('T1 code is stored in capitals', :'c1'='TEST10');
select tt.chk('T1 same client id again: dup, one coupon', (crmf_coupon_save(null, '{"code":"TESTXX","name":"x","kind":"percent","value":5,"valid_from":"2020-01-01","valid_to":"2099-01-01"}', :'clc')->>'dup')::boolean and tt.cp('TESTXX') is null);
select tt.err('T1 a second coupon with the same code', $$select crmf_coupon_save(null, '{"code":"TEST10","name":"x","kind":"percent","value":5,"valid_from":"2020-01-01","valid_to":"2099-01-01"}')$$, 'code_exists');
select tt.as(:'u_o');
select tt.err('T1 the owner above the maximum needs a reason', $$select crmf_coupon_save(null, '{"code":"TESTBIG","name":"x","kind":"percent","value":25,"valid_from":"2020-01-01","valid_to":"2099-01-01"}')$$, 'reason_required');
select tt.chk('T1 the owner above the maximum with a reason: created, audit line', crmf_coupon_save(null, '{"code":"TESTBIG","name":"big one","kind":"percent","value":25,"valid_from":"2020-01-01","valid_to":"2099-01-01","max_uses":1}', null, 'owner decision for a launch day') ->> 'code' = 'TESTBIG' and tt.aud('crmf_coupon_over_maximum')=1);
select tt.as(:'u_v');
-- more coupons used below
select crmf_coupon_save(null, jsonb_build_object('code','TESTAMT','name','test amount','kind','amount','value',150,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'max_uses',5,'per_customer_uses',2)) is not null as c2 \gset
select crmf_coupon_save(null, jsonb_build_object('code','TESTOLD','name','test expired','kind','amount','value',50,'valid_from',(tt.today()-60)::text,'valid_to',(tt.today()-30)::text)) is not null as c3 \gset
select crmf_coupon_save(null, jsonb_build_object('code','TESTNEW','name','test not started','kind','amount','value',50,'valid_from',(tt.today()+10)::text,'valid_to',(tt.today()+40)::text)) is not null as c4 \gset
select crmf_coupon_save(null, jsonb_build_object('code','TESTOUT','name','test outlet 2 only','kind','amount','value',50,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'scope','{"locations":[2]}'::jsonb)) is not null as c5 \gset
select crmf_coupon_save(null, jsonb_build_object('code','TESTITEM','name','test item x only','kind','percent','value',10,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'scope',jsonb_build_object('items',jsonb_build_array(:'ix')))) is not null as c6 \gset
select crmf_coupon_save(null, jsonb_build_object('code','TESTCAT','name','test category b only','kind','amount','value',100,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'scope','{"categories":["test_cat_b"]}'::jsonb)) is not null as c7 \gset
select crmf_coupon_save(null, jsonb_build_object('code','TESTCAP','name','test capped','kind','percent','value',20,'max_discount',60,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text)) is not null as c8 \gset
select crmf_coupon_save(null, jsonb_build_object('code','TESTPERS','name','test personal','kind','amount','value',100,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'customer_id',tt.cid('01711831605'),'max_uses',1)) is not null as c9 \gset
select tt.chk('T1 the list shows the coupons with their scope (issuer may read, cashier may not)', jsonb_array_length(crmf_coupon_list(true))>=9
  and (select count(*) from jsonb_array_elements(crmf_coupon_list()) e where e->>'code'='TESTITEM' and jsonb_array_length(e->'scope')=1)=1);
select tt.as(:'u_c');
select tt.err('T1 a cashier cannot read the coupon list', $$select crmf_coupon_list()$$, 'not allowed');
select tt.chk('T1 a cashier sees no coupon row through the table (RLS)', (select count(*) from crmf_coupons)=0);

\echo == T2 the check at the till (writes nothing)
select tt.as(:'u_c');
select tt.err('T2 vouchers OFF: the check is refused', $$select crmf_coupon_check('TEST10', 1, null, '[]', 1000)$$, 'vouchers_off');
select tt.as(:'u_o');
select set_rule('crm_voucher_on','true'::jsonb) is null as v1 \gset
select tt.as(:'u_c');
select tt.chk('T2 unknown code', crmf_coupon_check('NOPE', 1, tt.cid('01711831601'), '[]', 1000)->>'reason'='not_found');
select tt.chk('T2 10 percent of 1000 = 100 for a known customer', (crmf_coupon_check('test10', 1, tt.cid('01711831601'), '[]', 1000)->>'discount')::numeric=100 and (crmf_coupon_check('TEST10', 1, tt.cid('01711831601'), '[]', 1000)->>'ok')::boolean);
select tt.chk('T2 no customer: refused (the per-customer limit cannot be checked)', crmf_coupon_check('TEST10', 1, null, '[]', 1000)->>'reason'='customer_needed');
select tt.chk('T2 minimum bill 500: a 400 bill is refused', crmf_coupon_check('TEST10', 1, tt.cid('01711831601'), '[]', 400)->>'reason'='min_bill');
select tt.chk('T2 expired', crmf_coupon_check('TESTOLD', 1, tt.cid('01711831601'), '[]', 1000)->>'reason'='expired');
select tt.chk('T2 not started', crmf_coupon_check('TESTNEW', 1, tt.cid('01711831601'), '[]', 1000)->>'reason'='not_started');
select tt.chk('T2 wrong outlet (coupon is for outlet 2, till is outlet 1)', crmf_coupon_check('TESTOUT', 1, tt.cid('01711831601'), '[]', 1000)->>'reason'='wrong_outlet');
select tt.err('T2 a till cannot ask for an outlet it does not work at', $$select crmf_coupon_check('TESTOUT', 2, null, '[]', 1000)$$, 'not allowed for this location');
select tt.chk('T2 amount coupon 150 on a 1000 bill = 150; on a 90 bill it cannot exceed the bill = 90', (crmf_coupon_check('TESTAMT', 1, tt.cid('01711831601'), '[]', 1000)->>'discount')::numeric=150 and (crmf_coupon_check('TESTAMT', 1, tt.cid('01711831601'), '[]', 90)->>'discount')::numeric=90);
select tt.chk('T2 cap: 20 percent of 1000 = 200 but the cap is 60', (crmf_coupon_check('TESTCAP', 1, tt.cid('01711831601'), '[]', 1000)->>'discount')::numeric=60);
-- item scope: two of item X (2 x 200 = 400) and one of item Y (300) -> subtotal 700; 10 percent of 400 = 40
select tt.chk('T2 item scope: only item X lines count, 10 percent of 400 = 40', (crmf_coupon_check('TESTITEM', 1, tt.cid('01711831601'), jsonb_build_array(jsonb_build_object('item_id',:'ix','qty',2,'price',200), jsonb_build_object('item_id',:'iy','qty',1,'price',300)), 700)->>'discount')::numeric=40);
select tt.chk('T2 item scope: a bill with no item X gets nothing_in_scope', crmf_coupon_check('TESTITEM', 1, tt.cid('01711831601'), jsonb_build_array(jsonb_build_object('item_id',:'iy','qty',1,'price',300)), 300)->>'reason'='nothing_in_scope');
select tt.chk('T2 category scope: amount 100 capped by the 300 of category B items', (crmf_coupon_check('TESTCAT', 1, tt.cid('01711831601'), jsonb_build_array(jsonb_build_object('item_id',:'ix','qty',1,'price',200), jsonb_build_object('item_id',:'iy','qty',1,'price',300)), 500)->>'discount')::numeric=100);
select tt.chk('T2 a personal coupon is refused for another customer', crmf_coupon_check('TESTPERS', 1, tt.cid('01711831601'), '[]', 1000)->>'reason'='wrong_customer' and (crmf_coupon_check('TESTPERS', 1, tt.cid('01711831605'), '[]', 1000)->>'ok')::boolean);
select tt.err('T2 a cashier cannot use an override', $$select crmf_coupon_check('TESTOLD', 1, null, '[]', 1000, 'boss said so')$$, 'not allowed');
select tt.as(:'u_x');
select tt.err('T2 override needs a real reason', $$select crmf_coupon_check('TESTOLD', 1, (select id from customers where mobile='01711831601'), '[]', 1000, 'x')$$, 'reason_required');
select tt.chk('T2 override holder with a reason: expired coupon accepted, the answer lists what was waived', (crmf_coupon_check('TESTOLD', 1, tt.cid('01711831601'), '[]', 1000, 'owner agreed, late festival')->>'ok')::boolean
  and crmf_coupon_check('TESTOLD', 1, tt.cid('01711831601'), '[]', 1000, 'owner agreed, late festival')->'overridden' ? 'expired');
select tt.chk('T2 a personal coupon of another customer can never be overridden', crmf_coupon_check('TESTPERS', 1, tt.cid('01711831601'), '[]', 1000, 'owner agreed, special case')->>'reason'='wrong_customer');
select tt.as(:'u_n');
select tt.err('T2 staff without POS rights cannot check', $$select crmf_coupon_check('TEST10', 1, null, '[]', 1000)$$, 'not allowed');
reset role;
select tt.chk('T2 checks wrote nothing (no use, no exception)', tt.uses('TEST10')=0 and tt.exc('coupon_override')=0);

\echo == T3 recording the use after the sale
set role authenticated; select tt.as(:'u_c');
-- sale 1: customer A, bill 1000, discount 100 (what TEST10 gives)
select (record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',100,'[{"mode":"cash","amount":900}]','01711831601','test_cp_a','retail',null,true))->>'id' as s1 \gset
select crmf_coupon_redeem_after_sale('test10', :'s1'::uuid, null, gen_random_uuid()) ->> 'ok' as r1 \gset
select tt.chk('T3 use recorded: expected 100, given 100, no mismatch', :'r1'='true' and tt.uses('TEST10')=1 and tt.q($$select discount_expected||'/'||discount_given||'/'||mismatch from crmf_coupon_uses limit 1$$)='100.00/100.00/false');
select tt.chk('T3 the same sale and coupon again: dup, still one use', (crmf_coupon_redeem_after_sale('TEST10', :'s1'::uuid)->>'dup')::boolean and tt.uses('TEST10')=1);
select tt.chk('T3 a second coupon on the same sale is refused', crmf_coupon_redeem_after_sale('TESTAMT', :'s1'::uuid)->>'reason'='sale_has_coupon');
-- sale 2: same customer again, per-customer limit 1 -> refused, and the discount already on the bill becomes a yellow row
select (record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',100,'[{"mode":"cash","amount":900}]','01711831601','test_cp_a','retail',null,true))->>'id' as s2 \gset
select tt.chk('T3 the same customer again: refused (customer_limit), overridable', crmf_coupon_redeem_after_sale('TEST10', :'s2'::uuid)->>'reason'='customer_limit' and (crmf_coupon_redeem_after_sale('TEST10', :'s2'::uuid)->>'overridable')::boolean);
select tt.chk('T3 the refused redemption left a yellow Exceptions row (the bill carries a discount)', tt.exc('coupon_refused')>=1 and tt.uses('TEST10')=1);
select tt.as(:'u_x');
select tt.err('T3 override without a reason is refused', format($$select crmf_coupon_redeem_after_sale('TEST10', %L::uuid, 'x')$$, :'s2'), 'reason_required');
select tt.chk('T3 override holder with a reason: accepted, audit line and yellow row', crmf_coupon_redeem_after_sale('TEST10', :'s2'::uuid, 'owner agreed, loyal customer')->>'ok'='true' and tt.uses('TEST10')=2 and tt.aud('crmf_coupon_override')=1 and tt.exc('coupon_override')=1);
select tt.as(:'u_c');
-- sale 3: another customer, TEST10 is now at its total limit of 2 -> used_up, never overridable
select (record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',100,'[{"mode":"cash","amount":900}]','01711831602','test_cp_b','retail',null,true))->>'id' as s3 \gset
select tt.chk('T3 total limit reached: used_up', crmf_coupon_redeem_after_sale('TEST10', :'s3'::uuid)->>'reason'='used_up');
select tt.as(:'u_x');
select tt.chk('T3 used_up cannot be overridden', crmf_coupon_redeem_after_sale('TEST10', :'s3'::uuid, 'owner agreed, special case')->>'reason'='used_up');
-- a voided sale gives its use back
select tt.as(:'u_m');
select void_sale(:'s1'::uuid, 'test void to free a use');
select tt.as(:'u_c');
select tt.chk('T3 after the void of sale 1 the coupon has a free use again: sale 3 is accepted', crmf_coupon_redeem_after_sale('TEST10', :'s3'::uuid)->>'ok'='true');
select tt.err('T3 a voided sale cannot be used', format($$select crmf_coupon_redeem_after_sale('TESTAMT', %L::uuid)$$, :'s1'), 'sale_not_done');
-- mismatch: coupon gives 150 but the bill discount is 100
select (record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',100,'[{"mode":"cash","amount":900}]','01711831603','test_cp_c','retail',null,true))->>'id' as s4 \gset
select tt.exc('coupon_discount_mismatch') as mm0 \gset
select tt.chk('T3 discount on the bill (100) differs from the coupon (150): recorded with mismatch, yellow row', crmf_coupon_redeem_after_sale('TESTAMT', :'s4'::uuid)->>'mismatch'='true' and tt.exc('coupon_discount_mismatch')=:mm0+1);
-- item scope redeem: sale with 2 x item X (400) + quick 600 = 1000, coupon 10 percent of 400 = 40
select (record_sale2(gen_random_uuid(),1,jsonb_build_array(jsonb_build_object('item_id',:'ix','qty',2), jsonb_build_object('amount',600)),40,'[{"mode":"cash","amount":960}]','01711831604','test_cp_d','retail',null,false))->>'id' as s5 \gset
select tt.chk('T3 item scope: expected 40 and given 40, no mismatch', crmf_coupon_redeem_after_sale('TESTITEM', :'s5'::uuid)->>'mismatch'='false' and tt.q($$select discount_expected from crmf_coupon_uses u join crmf_coupons c on c.id=u.coupon_id where c.code='TESTITEM'$$)='40.00');
-- personal coupon used by its owner
select (record_sale2(gen_random_uuid(),1,'[{"amount":800}]',100,'[{"mode":"cash","amount":700}]','01711831605','test_cp_e','retail',null,true))->>'id' as s6 \gset
select tt.chk('T3 personal coupon: its customer may use it', crmf_coupon_redeem_after_sale('TESTPERS', :'s6'::uuid)->>'ok'='true');
-- sale of a customer-less bill: the per-customer limit cannot be checked
select (record_sale2(gen_random_uuid(),1,'[{"amount":800}]',100,'[{"mode":"cash","amount":700}]',null,null,'retail',null,true))->>'id' as s7 \gset
select tt.chk('T3 walk-in sale with no customer: customer_needed', crmf_coupon_redeem_after_sale('TESTAMT', :'s7'::uuid)->>'reason'='customer_needed');
-- someone else's sale
select tt.as(:'u_c2');
select tt.err('T3 another cashier cannot redeem on this cashier''s sale', format($$select crmf_coupon_redeem_after_sale('TESTCAP', %L::uuid)$$, :'s7'), 'not allowed');
select tt.as(:'u_n');
select tt.err('T3 staff without POS rights cannot redeem', format($$select crmf_coupon_redeem_after_sale('TESTCAP', %L::uuid)$$, :'s7'), 'not allowed');
select tt.as(:'u_v');
select tt.chk('T3 the redemption log (issuer): rows for TEST10 show receipt, discount, status', (select count(*) from jsonb_array_elements(crmf_coupon_uses_list(tt.cp('TEST10'))) e where e->>'receipt' is not null)=3);
select tt.as(:'u_c');
select tt.err('T3 a cashier cannot read the redemption log', $$select crmf_coupon_uses_list()$$, 'not allowed');
select tt.err('T3 a use row cannot be edited from outside', $$update crmf_coupon_uses set discount_given=0$$, 'permission denied');
reset role;
select tt.err('T3 a use row cannot be edited even by the owner of the table (append-only)', $$update crmf_coupon_uses set discount_given=0$$, 'append_only');
-- editing a coupon after use: the money terms are locked
set role authenticated; select tt.as(:'u_v');
select tt.err('T3 value cannot change after the first use', $$select crmf_coupon_save(tt.cp('TEST10'), '{"value":12}')$$, 'locked_after_use');
select tt.chk('T3 the name and the end date can still change', crmf_coupon_save(tt.cp('TEST10'), '{"name":"test ten percent v2"}') is not null);
-- retired coupon
select crmf_coupon_save(tt.cp('TESTCAP'), '{"active":false}') is not null as ret \gset
select tt.as(:'u_c');
select tt.chk('T3 a retired coupon is refused and never overridable', crmf_coupon_check('TESTCAP', 1, tt.cid('01711831601'), '[]', 1000)->>'reason'='retired');
select tt.as(:'u_o');
select set_rule('crm_voucher_on','false'::jsonb) is null as voff \gset
select tt.as(:'u_c');
select tt.err('T3 vouchers OFF again: redemption refused', format($$select crmf_coupon_redeem_after_sale('TESTAMT', %L::uuid)$$, :'s7'), 'vouchers_off');
select tt.as(:'u_o');
select set_rule('crm_voucher_on','true'::jsonb) is null as von \gset
reset role;
select tt.chk('T3 no journal entry from coupons so far', tt.je()=:je0 or (select count(*) from journal_entries where source_type like 'crmf%')=0);
select tt.chk('T3 coupons did not change any sale total (sale 2: 1000 - 100 = 900)', (select total from sales where id=:'s2'::uuid)=900);

\echo == T4 voucher liability (OFF by default; the only writer to the books)
select tt.je() as je1 \gset
select code as liab_code from coa_accounts where type='liability' and not is_group and active order by code limit 1 \gset
select code as exp_code from coa_accounts where type='expense' and not is_group and active order by code limit 1 \gset
set role authenticated; select tt.as(:'u_v');
select crmf_coupon_save(null, jsonb_build_object('code','TESTLIAB0','name','test liability before the date','kind','amount','value',100,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'max_uses',5,'post_liability',true)) is not null as l0 \gset
select tt.err('T4 post_liability needs an amount coupon with a total use limit', $$select crmf_coupon_save(null, jsonb_build_object('code','TESTLIABX','name','x','kind','percent','value',10,'valid_from','2020-01-01','valid_to','2099-01-01','post_liability',true))$$, 'liability_needs_amount_and_max_uses');
select tt.err('T4 ... or a limit', $$select crmf_coupon_save(null, jsonb_build_object('code','TESTLIABX','name','x','kind','amount','value',10,'valid_from','2020-01-01','valid_to','2099-01-01','post_liability',true))$$, 'liability_needs_amount_and_max_uses');
select tt.chk('T4 setting OFF: marking a coupon for liability writes nothing', tt.je()=:je1 and tt.held('TESTLIAB0')=0);
select tt.as(:'u_o');
select tt.err('T4 cannot switch on without the effective-from date', $$select set_rule('crm_voucher_liability_on','true'::jsonb)$$, 'liability_from_needed');
select tt.err('T4 a date that is not a date is refused', $$select set_rule('crm_voucher_liability_from','"soon"'::jsonb)$$, 'bad_value');
select set_rule('crm_voucher_liability_from', to_jsonb((tt.today()-3)::text)) is null as f0 \gset
select tt.err('T4 an effective-from date in the past cannot be switched on', $$select set_rule('crm_voucher_liability_on','true'::jsonb)$$, 'liability_from_in_the_past');
select set_rule('crm_voucher_liability_from', to_jsonb((tt.today()+1)::text)) is null as f1 \gset
select tt.err('T4 cannot switch on without both accounts', $$select set_rule('crm_voucher_liability_on','true'::jsonb)$$, 'liability_accounts_needed');
select tt.err('T4 an unknown account code is refused', $$select set_rule('crm_voucher_liability_account','"9999"'::jsonb)$$, 'bad_account');
select tt.err('T4 the liability account must be a liability', $$select set_rule('crm_voucher_liability_account','"5000"'::jsonb)$$, 'bad_account_type');
select tt.err('T4 the expense account must be an expense', format($$select set_rule('crm_voucher_expense_account', %L::jsonb)$$, to_jsonb(:'liab_code'::text)::text), 'bad_account_type');
select set_rule('crm_voucher_liability_account', to_jsonb(:'liab_code'::text)) is null as a1 \gset
select set_rule('crm_voucher_expense_account', to_jsonb(:'exp_code'::text)) is null as a2 \gset
select tt.err('T4 the accounts must be on (accounting is OFF in this database)', $$select set_rule('crm_voucher_liability_on','true'::jsonb)$$, 'accounting_not_on');
select set_rule('accounting_start_date', to_jsonb((tt.today()-30)::text)) is null as st \gset
select set_rule('accounting_on','true'::jsonb) is null as acc \gset
select set_rule('crm_voucher_liability_on','true'::jsonb) is null as son \gset
select tt.chk('T4 switch on with the date, both accounts and accounting on', rule_on('crm_voucher_liability_on'));
-- the effective date is TOMORROW: a coupon made today is before it, so nothing is booked
select tt.as(:'u_a');
select tt.chk('T4 a coupon made before the effective-from date is skipped; nothing booked', crmf_voucher_liability_sync()->>'entries'='0' and tt.je()=:je1 and tt.held('TESTLIAB0')=0);
select tt.as(:'u_c');
select tt.err('T4 a cashier cannot run the liability sync', $$select crmf_voucher_liability_sync()$$, 'not allowed');
select tt.as(:'u_v');
select tt.err('T4 the coupon issuer cannot run it either', $$select crmf_voucher_liability_sync()$$, 'not allowed');
select tt.as(:'u_v');
select crmf_coupon_save(tt.cp('TESTLIAB0'), '{"active":false}') is not null as ret0 \gset      -- retired, so the later move of the date to today does not book it
-- move the effective date to today (switch off, set, switch on)
select tt.as(:'u_o');
select set_rule('crm_voucher_liability_on','false'::jsonb) is null as o0 \gset
select set_rule('crm_voucher_liability_from', to_jsonb(tt.today()::text)) is null as f2 \gset
select set_rule('crm_voucher_liability_on','true'::jsonb) is null as o1 \gset
select tt.as(:'u_v');
select crmf_coupon_save(null, jsonb_build_object('code','TESTLIAB','name','test liability','kind','amount','value',100,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'max_uses',5,'post_liability',true)) is not null as l1 \gset
reset role;
-- 100 x 5 = 500 held: Dr expense 500, Cr liability 500, two lines, balanced
select tt.chk('T4 issue: 500 held, ONE entry of two lines, Dr = Cr, the chosen accounts', tt.held('TESTLIAB')=500 and tt.je()=:je1+1 and tt.unbalanced()=0
  and tt.q($$select count(*) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='crmf_voucher'$$)='2'
  and tt.q($$select sum(debit) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where e.source_type='crmf_voucher' and a.code=$$ || quote_literal(:'exp_code'))='500.00'
  and tt.q($$select sum(credit) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where e.source_type='crmf_voucher' and a.code=$$ || quote_literal(:'liab_code'))='500.00');
set role authenticated; select tt.as(:'u_a');
select tt.chk('T4 the sync is self-healing: running it again posts nothing', crmf_voucher_liability_sync()->>'entries'='0' and tt.je()=:je1+1);
-- a sale uses 100: held falls to 400
select tt.as(:'u_c');
select (record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',100,'[{"mode":"cash","amount":900}]','01711831606','test_cp_f','retail',null,true))->>'id' as s8 \gset
select crmf_coupon_redeem_after_sale('TESTLIAB', :'s8'::uuid)->>'ok' as r8 \gset
reset role;
select tt.chk('T4 a use of 100: held 400, a second balanced entry (Dr liability 100, Cr expense 100)', :'r8'='true' and tt.held('TESTLIAB')=400 and tt.unbalanced()=0
  and tt.q($$select count(*) from journal_entries where source_type='crmf_voucher'$$)='2');
-- the sale is voided: the use is given back, held returns to 500
set role authenticated; select tt.as(:'u_m');
select void_sale(:'s8'::uuid, 'test void: coupon use comes back');
reset role;
select tt.chk('T4 void of the sale: held back to 500 by the void trigger', tt.held('TESTLIAB')=500 and tt.unbalanced()=0);
-- expiry: the end date moves to yesterday -> target 0 -> released
set role authenticated; select tt.as(:'u_v');
select crmf_coupon_save(tt.cp('TESTLIAB'), jsonb_build_object('valid_from',(tt.today()-3)::text,'valid_to',(tt.today()-1)::text)) is not null as exp1 \gset
reset role;
select tt.chk('T4 expired coupon: the provision is released (held 0), still balanced', tt.held('TESTLIAB')=0 and tt.unbalanced()=0);
-- a closed period stops posting but never the sale; the sync repairs it later
set role authenticated; select tt.as(:'u_v');
select crmf_coupon_save(null, jsonb_build_object('code','TESTLIAB2','name','test liability two','kind','amount','value',50,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'max_uses',4,'post_liability',true)) is not null as l2 \gset
reset role;
select tt.chk('T4 second coupon: 50 x 4 = 200 held', tt.held('TESTLIAB2')=200);
set role authenticated; select tt.as(:'u_o');
select set_rule('period_closed_until', to_jsonb(tt.today()::text)) is null as pc \gset
select tt.as(:'u_v');
select tt.chk('T4 closed period: saving a coupon marked for liability is not blocked (warning only); nothing booked', crmf_coupon_save(null, jsonb_build_object('code','TESTLIAB3','name','test liability three','kind','amount','value',50,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'max_uses',2,'post_liability',true)) is not null and tt.held('TESTLIAB3')=0);
select tt.as(:'u_o');
select set_rule('period_closed_until', null) is null as pc0 \gset
select tt.as(:'u_a');
select tt.chk('T4 period open again: the sync books the missing 100 (50 x 2)', crmf_voucher_liability_sync()->>'entries'='1' and tt.held('TESTLIAB3')=100 and tt.unbalanced()=0);
select tt.chk('T4 report shows held = should hold', (select bool_and((e->>'held')::numeric = (e->>'should_hold')::numeric) from jsonb_array_elements(crmf_voucher_liability_report()->'rows') e));
select tt.err('T4 wind down needs a reason', $$select crmf_voucher_liability_wind_down(' ')$$, 'reason_required');
select tt.as(:'u_c');
select tt.err('T4 a cashier cannot wind down', $$select crmf_voucher_liability_wind_down('end of the offer')$$, 'not allowed');
select tt.as(:'u_a');
select crmf_voucher_liability_wind_down('end of the offer season') ->> 'coupons' as wd \gset
reset role;
select tt.chk('T4 wind down: everything back to zero, balanced, audit line', tt.held('TESTLIAB2')=0 and tt.held('TESTLIAB3')=0 and tt.unbalanced()=0 and tt.aud('crmf_voucher_liability_wind_down')=1);
set role authenticated; select tt.as(:'u_o');
select set_rule('crm_voucher_liability_on','false'::jsonb) is null as off1 \gset
select tt.as(:'u_a');
select tt.chk('T4 switched OFF: the sync does nothing', (crmf_voucher_liability_sync()->>'off')::boolean);
select tt.as(:'u_v');
select crmf_coupon_save(null, jsonb_build_object('code','TESTLIAB4','name','test liability four','kind','amount','value',50,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'max_uses',2,'post_liability',true)) is not null as l4 \gset
reset role;
select tt.chk('T4 switched OFF: a new marked coupon books nothing', tt.held('TESTLIAB4')=0);
select tt.chk('T4 only crmf_voucher entries were written by this package, each with exactly two lines', (select bool_and(n=2) from (select count(*) n from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='crmf_voucher' group by e.id) z));
select tt.chk('T4 the entries are dated today and carry the coupon code in the memo', (select bool_and(entry_date=tt.today() and memo like 'Coupon TESTLIAB%') from journal_entries where source_type='crmf_voucher'));

\echo == T5 paste twice
select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.proname)) as h1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%crmf%' \gset
\i supabase/phase318.sql
select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.proname)) as h2 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%crmf%' \gset
select tt.chk('T5 paste twice: functions identical, settings kept, triggers once', :'h1'=:'h2' and rule_num('crm_voucher_max_percent')=20 and (select count(*) from pg_trigger where tgname in ('sales_void_coupon_crmf','crmf_rules_guard') and not tgisinternal)=2);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
