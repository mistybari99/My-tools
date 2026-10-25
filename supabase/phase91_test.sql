-- FRESH DB ONLY. Phase 91 tests (U-04 sale return control: restock choice, window per class, receipt, automatic write-off, expired batch, overrides).
--   ORDER="phase8 ... phase87 phase90 phase91" bash tests/sql/build_fresh_db.sh a91db          (port 5563 here)
--   psql -h /tmp -p 5563 -U postgres -d a91db -qAt -f supabase/phase91_test.sql | grep -E 'FAIL|RESULT'      (run from the repository root)
-- Test data only (test_* names). Hand-computed numbers are written above each block. The two hooks (sale_return, void_sale_return) are proved at the end
-- on a SCRATCH COPY of the database that this file creates and drops; the shared functions of the tested database are never patched.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000091'
\set u_c '00000000-0000-0000-0000-000000000191'
\set u_m '00000000-0000-0000-0000-000000000291'
\set u_mo '00000000-0000-0000-0000-000000000391'
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
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.jl(p_type text, p_sid text, p_code text, p_side text) returns numeric language sql stable as $$
  select coalesce(sum(case p_side when 'd' then l.debit else l.credit end), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
  where e.source_type = p_type and e.source_id = p_sid and e.reverses_id is null and a.code = p_code $$;
-- net debit of an account over all entries (reversals included)
create or replace function tt.nd(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.bal(p_item uuid) returns numeric language sql stable security definer as $$ select coalesce((select qty from public.stock_balance where item_id = p_item and location_id = 1), 0) $$;
create or replace function tt.wo_qty(p_ret uuid) returns numeric language sql stable security definer as $$
  select coalesce(sum(w.qty), 0) from public.stock_wastage w where w.id = any (select unnest(wastage_ids) from public.w1c_return_lines where return_id = p_ret) $$;
create or replace function tt.wo_id(p_ret uuid) returns text language sql stable security definer as $$
  select (select unnest(wastage_ids) from public.w1c_return_lines where return_id = p_ret limit 1)::text $$;
-- a sale of one item, then age it by N hours (fixture only: triggers off for the update)
create or replace function tt.sell(p_item uuid, p_qty numeric, p_price numeric) returns uuid language plpgsql as $$
begin
  return (record_sale2(gen_random_uuid(), 1, jsonb_build_array(jsonb_build_object('item_id', p_item, 'qty', p_qty, 'price', p_price, 'unit', 'kg')), 0,
          jsonb_build_array(jsonb_build_object('mode', 'cash', 'amount', p_qty * p_price)), null, null, 'retail', null, false) ->> 'id')::uuid;
end $$;
create or replace function tt.age(p_sale uuid, p_hours numeric) returns void language plpgsql security definer as $$
begin
  perform set_config('session_replication_role', 'replica', true);
  update public.sales set sold_at = now() - make_interval(secs => p_hours * 3600) where id = p_sale;
  perform set_config('session_replication_role', 'origin', true);
end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner91@s.app','{"full_name":"test_owner91"}'), (:'u_c','test_cashier91@s.app','{"full_name":"test_cashier91"}'),
 (:'u_m','test_manager91@s.app','{"full_name":"test_manager91"}'), (:'u_mo','test_manager91b@s.app','{"full_name":"test_manager91b"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_c','salesperson'),(:'u_m','management'),(:'u_mo','management') on conflict do nothing;
insert into user_locations values (:'u_c',1),(:'u_m',1),(:'u_mo',1) on conflict do nothing;
update items set unit='kg', base_unit='kg', tracked=true where code in ('I-001','I-002','I-003');
update items set category='test_perish', sell_price=200 where code='I-001';
update items set category='test_dry', sell_price=100 where code='I-002';
update items set category='test_fresh2', sell_price=150 where code='I-003';
select id as i1 from items where code='I-001' \gset
select id as i2 from items where code='I-002' \gset
select id as i3 from items where code='I-003' \gset

\echo == T0 shape, safe defaults, internals closed
select tt.chk('T0 phase91 present, tables have RLS and no browser write right',
  to_regprocedure('public._w1c_present91()') is not null and (select count(*) from pg_class c where c.relname in ('w1c_return_class_rules','w1c_returns','w1c_return_lines') and c.relrowsecurity)=3
  and not has_table_privilege('authenticated','public.w1c_returns','insert') and not has_table_privilege('authenticated','public.w1c_return_class_rules','update') and not has_table_privilege('anon','public.w1c_return_lines','select'));
select tt.chk('T0 defaults keep today: receipt off, window blank, expired = allow, no class rule, nothing written',
  not rule_on('return_needs_receipt') and rule_num('return_window_hours') is null and rule_txt('return_expired_restock')='allow' and not exists (select 1 from w1c_return_class_rules) and not exists (select 1 from w1c_returns));
select tt.chk('T0 three settings have English labels and hints; the grant and the wastage reason exist',
  (select count(*) from rules where key in ('return_needs_receipt','return_window_hours','return_expired_restock') and label_en ~ '^[A-Za-z]' and hint_en ~ '^[A-Za-z]')=3
  and exists (select 1 from grant_defs where grant_code='return_override') and exists (select 1 from option_lists where list_code='wastage_reasons' and value_code='customer_return' and active));
select tt.chk('T0 internals closed to browsers; the screen calls open to signed-in users only',
  not has_function_privilege('authenticated','public._w1c_return_finish(uuid,jsonb,text,text)','execute') and not has_function_privilege('authenticated','public._w1c_return_hook(uuid)','execute')
  and not has_function_privilege('authenticated','public._w1c_writeoff(uuid,int,numeric,bigint,numeric,text)','execute') and not has_function_privilege('authenticated','public._w1c_return_void_guard(uuid)','execute')
  and has_function_privilege('authenticated','public._w1c_sale_return(uuid,uuid,jsonb,text,text,text,text,text,jsonb,text,text)','execute')
  and not has_function_privilege('anon','public._w1c_sale_return(uuid,uuid,jsonb,text,text,text,text,text,jsonb,text,text)','execute'));
select tt.chk('T0 sale_return and void_sale_return are NOT patched here', position('bos91' in pg_get_functiondef('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'::regprocedure))=0
  and position('bos91' in pg_get_functiondef('public.void_sale_return(uuid,text)'::regprocedure))=0);

\echo == setup: accounting on, stock at place 1 (cost 100 / 50 / 80), grants
set role authenticated; select tt.as(:'u_o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
select set_user_grant(:'u_m'::uuid,'sale_return') is null as g1 \gset
select set_user_grant(:'u_mo'::uuid,'sale_return') is null as g2 \gset
reset role;
insert into shelf_life_rules (item_id, value, unit) values (:'i1'::uuid, 24, 'hours'), (:'i3'::uuid, 24, 'hours');
set role authenticated; select tt.as(:'u_o');
select stock_production_in(:'i1'::uuid,1,20,now(),null,'test tray',null,100) ->> 'batch_id' as b1 \gset
select stock_opening(:'i2'::uuid,1,50,50) is not null as o2 \gset
select stock_production_in(:'i3'::uuid,1,5,now()-interval '30 hours',null,'test old tray',null,80) ->> 'batch_id' as b3old \gset
select stock_production_in(:'i3'::uuid,1,6,now(),null,'test new tray',null,80) ->> 'batch_id' as b3new \gset
reset role;
select tt.chk('setup: stock 20 / 50 / 11, the old tray of item three is past its 24 hours', tt.bal(:'i1'::uuid)=20 and tt.bal(:'i2'::uuid)=50 and tt.bal(:'i3'::uuid)=11
  and (select expires_at < now() from stock_batches where id=:b3old) and (select expires_at > now() from stock_batches where id=:b3new));
set role authenticated; select tt.as(:'u_o'); select set_user_grant(:'u_mo'::uuid,'return_override') is null as g3 \gset
reset role;

\echo == T1 default settings = today: everything goes back on the shelf, nothing written off, no refusal
-- sale A: 4 kg of item one at 200 = 800 cash. Return all four through the wrapper.
set role authenticated; select tt.as(:'u_c');
select tt.sell(:'i1'::uuid,4,200) as sa \gset
select tt.as(:'u_m');
select _w1c_sale_return(gen_random_uuid(), :'sa'::uuid, format('[{"item_id":"%s","qty":4}]',:'i1')::jsonb, 'damaged', null, 'cash') as r1 \gset
reset role;
select tt.chk('T1 wrapper return works with all settings at default: 800 refunded, stock back to 20', (:'r1'::jsonb ->> 'amount')::numeric=800 and tt.bal(:'i1'::uuid)=20);
select tt.chk('T1 disposition kept: one header, one line "restocked", no wastage row, no exception, no override', (select count(*) from w1c_returns where return_id=(:'r1'::jsonb ->> 'id')::uuid and not override)=1
  and (select decision from w1c_return_lines where return_id=(:'r1'::jsonb ->> 'id')::uuid)='restocked' and not exists (select 1 from stock_wastage where reason_code='customer_return')
  and not exists (select 1 from exceptions where flag_code='return_override'));
set role authenticated; select tt.as(:'u_c');
select tt.err('T1 a cashier without the sale_return grant is refused by the wrapper (the old rule stands)', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb, 'damaged', null, 'cash')$$, :'sa', :'i1'), 'not allowed');
reset role;

\echo == T2 class rule: perishable sweets are never put back on the shelf
set role authenticated; select tt.as(:'u_m');
select tt.err('T2 only the owner can set a class rule', $$select _w1c_return_class_set('test_perish','no_restock',null,null,null,'x')$$, 'not allowed');
select tt.err('T2 the manager cannot read the settings either', $$select _w1c_return_settings()$$, 'not allowed');
select tt.as(:'u_o');
select tt.err('T2 unknown class refused', $$select _w1c_return_class_set('no_such_class','no_restock',null,null,null,null)$$, 'unknown_class');
select tt.err('T2 bad restock value refused', $$select _w1c_return_class_set('test_perish','sometimes',null,null,null,null)$$, 'bad_restock');
select tt.err('T2 zero hours refused', $$select _w1c_return_class_set('test_perish','no_restock',0,null,null,null)$$, 'bad_window');
select tt.err('T2 negative hours refused', $$select _w1c_return_class_set('test_perish','no_restock',-5,null,null,null)$$, 'bad_window');
select _w1c_return_class_set('test_perish','no_restock',null,null,null,'owner confirmed: perishable') ->> 'saved' as c2 \gset
select tt.chk('T2 owner set the class rule', :'c2'='true' and (select restock from w1c_return_class_rules where class_code='test_perish')='no_restock');
reset role;
select tt.chk('T2 audit_log: the rule change with old and new, and the table audit', exists (select 1 from audit_log where action='return_rule_changed' and record_id='test_perish' and detail #>> '{new,restock}'='no_restock')
  and exists (select 1 from audit_log where table_name='w1c_return_class_rules' and record_id='test_perish'));
-- sale B: 3 kg item one @ 200. Stock 20 -> 17 on sale. Return: 3 put back (20) then 3 written off (17). Cost 100 each = 300.
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i1'::uuid,3,200) as sb \gset
select tt.as(:'u_m');
select _w1c_sale_return(gen_random_uuid(), :'sb'::uuid, format('[{"item_id":"%s","qty":3}]',:'i1')::jsonb, 'quality', null, 'cash') as r2 \gset
reset role;
select (:'r2'::jsonb ->> 'id')::uuid as rid2 \gset
select tt.chk('T2 perishable return: customer gets the full 600 back, shelf stock stays at 17 (nothing sellable returned)', (:'r2'::jsonb ->> 'amount')::numeric=600 and tt.bal(:'i1'::uuid)=17);
select tt.chk('T2 wastage row reason customer_return, 3 kg, on the same batch; the return line says written_off by class rule', tt.wo_qty(:'rid2'::uuid)=3
  and (select reason_code from stock_wastage where id=tt.wo_id(:'rid2'::uuid)::uuid)='customer_return' and (select batch_id from stock_wastage where id=tt.wo_id(:'rid2'::uuid)::uuid)=:b1
  and (select decision || '/' || basis from w1c_return_lines where return_id=:'rid2'::uuid)='written_off/class_rule');
set role authenticated; select tt.as(:'u_o'); select acct_post_pending(false) as pp \gset
reset role;
select tt.chk('T2 books: posting run had no errors', jsonb_array_length(:'pp'::jsonb -> 'errors')=0);
select tt.chk('T2 journal: return entry Dr inventory 300 / Cr COGS 300, wastage entry Dr 5100 300 / Cr inventory 300, every entry balanced',
  tt.jl('sale_return',:'rid2','5000','c')=300 and tt.jl('sale_return',:'rid2','1310','d')=300 and tt.jl('wastage',tt.wo_id(:'rid2'::uuid),'5100','d')=300 and tt.jl('wastage',tt.wo_id(:'rid2'::uuid),'1310','c')=300 and tt.unbalanced()=0);
select tt.chk('T2 audit_log line for the automatic write-off', exists (select 1 from audit_log where action='return_writeoff' and record_id=:'rid2' and (detail #>> '{lines,0,writeoff_qty}')::numeric=3));

\echo == T3 the cashier may write off more, never restock a no-restock class without an override
-- item two (class test_dry has no rule = restock). Sale C: 4 kg @ 100. Stock 50 -> 46. Return 4 with restock 1: back to 50, written off 3 (cost 50 -> 150).
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,4,100) as sc \gset
select tt.as(:'u_m');
select tt.err('T3 restock more than returned refused', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":4}]'::jsonb, 'damaged', null, 'cash', null, null, '[{"item_id":"%s","restock_qty":5}]'::jsonb)$$, :'sc', :'i2', :'i2'), 'return_bad_restock_qty');
select tt.err('T3 malformed restock line refused', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":4}]'::jsonb, 'damaged', null, 'cash', null, null, '[{"item_id":"nope","restock_qty":1}]'::jsonb)$$, :'sc', :'i2'), 'return_bad_restock_qty');
select tt.err('T3 restock line for an item that is not in the return refused', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":4}]'::jsonb, 'damaged', null, 'cash', null, null, '[{"item_id":"%s","restock_qty":1}]'::jsonb)$$, :'sc', :'i2', :'i1'), 'return_bad_restock_qty');
select tt.chk('T3 nothing was written by the refused calls (stock still 46, no return for the sale)', tt.bal(:'i2'::uuid)=46 and not exists (select 1 from sale_returns where sale_id=:'sc'::uuid));
select _w1c_sale_return(gen_random_uuid(), :'sc'::uuid, format('[{"item_id":"%s","qty":4}]',:'i2')::jsonb, 'damaged', null, 'cash', null, null, format('[{"item_id":"%s","restock_qty":1}]',:'i2')::jsonb) as r3 \gset
reset role;
select (:'r3'::jsonb ->> 'id')::uuid as rid3 \gset
select tt.chk('T3 cashier choice: 1 kg back on the shelf, 3 kg written off, stock 47, line says split by cashier choice', tt.bal(:'i2'::uuid)=47 and tt.wo_qty(:'rid3'::uuid)=3
  and (select decision || '/' || basis || '/' || restock_qty || '/' || writeoff_qty from w1c_return_lines where return_id=:'rid3'::uuid)='split/cashier_choice/1.000000/3.000000');
-- no-restock class: sale D 2 kg item one. Stock 17 -> 15.
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i1'::uuid,2,200) as sd \gset
select tt.as(:'u_m');
select tt.err('T3 restocking a no-restock class without an override is refused', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":2}]'::jsonb, 'damaged', null, 'cash', null, null, '[{"item_id":"%s","restock_qty":2}]'::jsonb)$$, :'sd', :'i1', :'i1'), 'return_restock_not_allowed');
select tt.err('T3 a reason alone does not help a person without the grant', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":2}]'::jsonb, 'damaged', null, 'cash', null, null, '[{"item_id":"%s","restock_qty":2}]'::jsonb, null, 'customer insisted')$$, :'sd', :'i1', :'i1'), 'return_override_not_allowed');
select tt.as(:'u_mo');
select tt.err('T3 the grant holder needs a reason too', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":2}]'::jsonb, 'damaged', null, 'cash', null, null, '[{"item_id":"%s","restock_qty":2}]'::jsonb)$$, :'sd', :'i1', :'i1'), 'return_restock_not_allowed');
select tt.err('T3 a two letter reason is not a reason', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":2}]'::jsonb, 'damaged', null, 'cash', null, null, '[{"item_id":"%s","restock_qty":2}]'::jsonb, null, 'ok')$$, :'sd', :'i1', :'i1'), 'return_restock_not_allowed');
select tt.chk('T3 still nothing written by the refusals (stock 15, no return for sale D)', tt.bal(:'i1'::uuid)=15 and not exists (select 1 from sale_returns where sale_id=:'sd'::uuid));
select _w1c_sale_return(gen_random_uuid(), :'sd'::uuid, format('[{"item_id":"%s","qty":2}]',:'i1')::jsonb, 'damaged', null, 'cash', null, null, format('[{"item_id":"%s","restock_qty":2}]',:'i1')::jsonb, null, 'manager checked the cake, still sealed') as r4 \gset
reset role;
select (:'r4'::jsonb ->> 'id')::uuid as rid4 \gset
select tt.chk('T3 manager override: both kilos back on the shelf (stock 17), line basis override, header says override with the reason', tt.bal(:'i1'::uuid)=17 and tt.wo_qty(:'rid4'::uuid)=0
  and (select basis from w1c_return_lines where return_id=:'rid4'::uuid)='override' and (select override and override_reason like 'manager checked%' and 'return_restock_not_allowed'=any(override_kinds) from w1c_returns where return_id=:'rid4'::uuid));
select tt.chk('T3 one audit_log line and one row in the Exceptions list for the override', (select count(*) from audit_log where action='return_override' and record_id=:'rid4')=1
  and (select count(*) from exceptions where flag_code='return_override' and text->>'ref'=:'rid4' and status='open')=1);

\echo == T4 return window: global, per class, effective date, override
set role authenticated; select tt.as(:'u_o');
select _w1c_return_global_set(false, 24, 'allow') ->> 'window_hours' as gw \gset
reset role;
select tt.chk('T4 global window 24 hours saved through the rules table, audit_log has it', :'gw'='24' and rule_num('return_window_hours')=24 and exists (select 1 from audit_log where action='return_rules_changed' and detail #>> '{new,window_hours}'='24'));
-- sale E: item two, 1 kg, 30 hours old; sale F: item two, 1 kg, 2 hours old
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,1,100) as se \gset
select tt.sell(:'i2'::uuid,1,100) as sf \gset
reset role;
select tt.age(:'se'::uuid, 30); select tt.age(:'sf'::uuid, 2);
set role authenticated; select tt.as(:'u_m');
select tt.err('T4 a 30 hour old sale is refused when the window is 24', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb, 'damaged', null, 'cash')$$, :'se', :'i2'), 'return_window_exceeded');
select tt.chk('T4 a 2 hour old sale is accepted', (_w1c_sale_return(gen_random_uuid(), :'sf'::uuid, format('[{"item_id":"%s","qty":1}]',:'i2')::jsonb, 'damaged', null, 'cash') ->> 'id') is not null);
select tt.as(:'u_mo');
select _w1c_sale_return(gen_random_uuid(), :'se'::uuid, format('[{"item_id":"%s","qty":1}]',:'i2')::jsonb, 'damaged', null, 'cash', null, null, null, null, 'regular customer, receipt photo seen by the manager') as r5 \gset
reset role;
select (:'r5'::jsonb ->> 'id')::uuid as rid5 \gset
select tt.chk('T4 manager-approved return outside the window: accepted, audit_log line, Exceptions row, header lists the rule that was broken',
  (select 'return_window_exceeded'=any(override_kinds) and (age_hours between 29.9 and 30.5) from w1c_returns where return_id=:'rid5'::uuid)
  and (select count(*) from audit_log where action='return_override' and record_id=:'rid5' and detail->>'reason' like 'regular customer%')=1 and (select level from exceptions where flag_code='return_override' and text->>'ref'=:'rid5')='yellow');
-- a class window beats the global one: test_dry 100 hours
set role authenticated; select tt.as(:'u_o'); select _w1c_return_class_set('test_dry','restock',100,null,null,'sweets in boxes') is not null as c4 \gset
reset role;
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,1,100) as sg \gset
reset role;
select tt.age(:'sg'::uuid, 60);
set role authenticated; select tt.as(:'u_m');
select tt.chk('T4 class window 100 beats the global 24: a 60 hour old sale of that class is accepted', (_w1c_sale_return(gen_random_uuid(), :'sg'::uuid, format('[{"item_id":"%s","qty":1}]',:'i2')::jsonb, 'damaged', null, 'cash') ->> 'id') is not null);
reset role;
select tt.age(:'sg'::uuid, 150);
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,1,100) as sh \gset
reset role;
select tt.age(:'sh'::uuid, 150);
set role authenticated; select tt.as(:'u_m');
select tt.err('T4 150 hours is outside the class window of 100', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb, 'damaged', null, 'cash')$$, :'sh', :'i2'), 'return_window_exceeded');
-- an effective-from date in the future does not apply yet: a window of 1000 hours that starts in three days leaves the global 24 hours in force today
select tt.as(:'u_o'); select _w1c_return_class_set('test_dry','restock',1000,null,tt.today()+3,'future') is not null as c4b \gset
select tt.as(:'u_m');
select tt.err('T4 a class rule that starts in three days does not apply today: the global 24 hours still refuses', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb, 'damaged', null, 'cash')$$, :'sh', :'i2'), 'return_window_exceeded');
select tt.as(:'u_o'); select _w1c_return_class_set('test_dry','restock',100,null,null,'back to today, 100 hours') is not null as c4c \gset
-- window blank = old behaviour
select _w1c_return_class_off('test_dry','window not wanted for boxes') ->> 'active' as off1 \gset
select _w1c_return_global_set(false, null, 'allow') is not null as gw2 \gset
reset role;
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,1,100) as sh2 \gset
reset role;
select tt.age(:'sh2'::uuid, 150);
set role authenticated; select tt.as(:'u_m');
select tt.chk('T4 window blank and class rule off: a 150 hour old sale is accepted (old behaviour)', (_w1c_sale_return(gen_random_uuid(), :'sh2'::uuid, format('[{"item_id":"%s","qty":1}]',:'i2')::jsonb, 'damaged', null, 'cash') ->> 'id') is not null);
reset role;
select tt.chk('T4 the retired class rule is kept, not deleted, with its audit line', exists (select 1 from w1c_return_class_rules where class_code='test_dry' and not active) and exists (select 1 from audit_log where action='return_rule_off' and record_id='test_dry'));
set role authenticated; select tt.as(:'u_o'); select tt.err('T4 retiring needs a reason', $$select _w1c_return_class_off('test_perish','')$$, 'reason_required'); reset role;

\echo == T5 receipt number
set role authenticated; select tt.as(:'u_o'); select _w1c_return_global_set(true, null, 'allow') is not null as r5a \gset
select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,1,100) as si \gset
reset role;
select receipt::text as rc from sales where id=:'si'::uuid \gset
set role authenticated; select tt.as(:'u_m');
select tt.err('T5 receipt required and not given: refused', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb, 'damaged', null, 'cash')$$, :'si', :'i2'), 'return_receipt_required');
select tt.err('T5 a wrong receipt number is refused', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb, 'damaged', null, 'cash', null, null, null, '999999')$$, :'si', :'i2'), 'return_receipt_required');
select tt.chk('T5 the right number (typed with a hash sign) is accepted', (_w1c_sale_return(gen_random_uuid(), :'si'::uuid, format('[{"item_id":"%s","qty":1}]',:'i2')::jsonb, 'damaged', null, 'cash', null, null, null, '#' || :'rc') ->> 'id') is not null);
select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,1,100) as sj \gset
select tt.as(:'u_o'); select _w1c_return_class_set('test_dry','restock',null,false,null,'boxes never need the slip') is not null as c5 \gset
select tt.as(:'u_m');
select tt.chk('T5 a class that says receipt not required beats the global switch', (_w1c_sale_return(gen_random_uuid(), :'sj'::uuid, format('[{"item_id":"%s","qty":1}]',:'i2')::jsonb, 'damaged', null, 'cash') ->> 'id') is not null);
select tt.as(:'u_o'); select _w1c_return_global_set(false, null, 'allow') is not null as r5b \gset
select _w1c_return_class_off('test_dry','back to the global rule') is not null as c5b \gset
reset role;

\echo == T6 expired batch: allow (today), writeoff, block
-- item three: old tray 5 kg (expired), new tray 6 kg. A sale of 8 kg takes the 6 from the new tray, then 2 from the old tray. Class test_fresh2 has no rule (restock).
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i3'::uuid,8,150) as s6a \gset
select tt.as(:'u_m');
select _w1c_sale_return(gen_random_uuid(), :'s6a'::uuid, format('[{"item_id":"%s","qty":8}]',:'i3')::jsonb, 'damaged', null, 'cash') as r6a \gset
reset role;
select tt.chk('T6 mode allow (today): all 8 kg go back on the shelf including the 2 kg of the expired tray', tt.bal(:'i3'::uuid)=11 and tt.wo_qty((:'r6a'::jsonb ->> 'id')::uuid)=0
  and (select decision from w1c_return_lines where return_id=(:'r6a'::jsonb ->> 'id')::uuid)='restocked');
set role authenticated; select tt.as(:'u_o'); select _w1c_return_global_set(false, null, 'writeoff') is not null as e6 \gset
select tt.as(:'u_c'); select tt.sell(:'i3'::uuid,8,150) as s6b \gset
select tt.as(:'u_m');
select _w1c_sale_return(gen_random_uuid(), :'s6b'::uuid, format('[{"item_id":"%s","qty":8}]',:'i3')::jsonb, 'damaged', null, 'cash') as r6b \gset
reset role;
select (:'r6b'::jsonb ->> 'id')::uuid as rid6b \gset
select tt.chk('T6 mode writeoff: the 2 kg that came from the expired tray are written off at once, 6 kg restocked, line split by expired batch', tt.wo_qty(:'rid6b'::uuid)=2 and tt.bal(:'i3'::uuid)=9
  and (select batch_id from stock_wastage where id=tt.wo_id(:'rid6b'::uuid)::uuid)=:b3old and (select decision || '/' || basis from w1c_return_lines where return_id=:'rid6b'::uuid)='split/expired_batch');
set role authenticated; select tt.as(:'u_o'); select _w1c_return_global_set(false, null, 'block') is not null as e6b \gset
select tt.as(:'u_c'); select tt.sell(:'i3'::uuid,8,150) as s6c \gset
select tt.as(:'u_m');
select tt.err('T6 mode block: restocking goods from an expired tray is refused', format($$select _w1c_sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":8}]'::jsonb, 'damaged', null, 'cash')$$, :'s6c', :'i3'), 'return_expired_restock');
select tt.chk('T6 the refusal wrote nothing (stock 1 after the sale, no return)', tt.bal(:'i3'::uuid)=1 and not exists (select 1 from sale_returns where sale_id=:'s6c'::uuid));
select _w1c_sale_return(gen_random_uuid(), :'s6c'::uuid, format('[{"item_id":"%s","qty":8}]',:'i3')::jsonb, 'damaged', null, 'cash', null, null, format('[{"item_id":"%s","restock_qty":6}]',:'i3')::jsonb) as r6c \gset
select tt.chk('T6 block mode: the cashier writes off the 2 kg himself (restock 6) and the return passes without an override', (select not override from w1c_returns where return_id=(:'r6c'::jsonb ->> 'id')::uuid) and tt.wo_qty((:'r6c'::jsonb ->> 'id')::uuid)=2);
select tt.as(:'u_c'); select tt.sell(:'i3'::uuid,8,150) as s6d \gset
select tt.as(:'u_mo');
select _w1c_sale_return(gen_random_uuid(), :'s6d'::uuid, format('[{"item_id":"%s","qty":8}]',:'i3')::jsonb, 'damaged', null, 'cash', null, null, null, null, 'tray was checked by hand, still fresh') as r6d \gset
reset role;
select tt.chk('T6 block mode with a manager override: restocked, RED row in the Exceptions list, audit_log line', (select 'return_expired_restock'=any(override_kinds) from w1c_returns where return_id=(:'r6d'::jsonb ->> 'id')::uuid)
  and (select level from exceptions where flag_code='return_override' and text->>'ref'=(:'r6d'::jsonb ->> 'id'))='red' and exists (select 1 from audit_log where action='return_override' and record_id=(:'r6d'::jsonb ->> 'id')));
set role authenticated; select tt.as(:'u_o'); select _w1c_return_global_set(false, null, 'allow') is not null as e6c \gset
reset role;

\echo == T7 books: every entry balanced, wastage by return equals the cost of the goods written off
set role authenticated; select tt.as(:'u_o'); select acct_post_pending(false) as pp2 \gset
reset role;
select tt.chk('T7 posting run: no errors, nothing unbalanced', jsonb_array_length(:'pp2'::jsonb -> 'errors')=0 and tt.unbalanced()=0);
-- written off: B 3 x 100 = 300; C 3 x 50 = 150; second sale of item three 2 x 80 = 160; r6c 2 x 80 = 160. Total 770 (account 5100)
select tt.chk('T7 account 5100 carries exactly the customer-return write-offs (300 + 150 + 160 + 160 = 770) and the wastage entries are Dr 5100 / Cr inventory',
  tt.nd('5100') = (select coalesce(sum(round(w.qty * l.unit_cost, 2)),0) from stock_wastage w join stock_ledger l on l.ref_type='wastage' and l.ref_id=w.id::text and l.reason='wastage' where w.reason_code='customer_return') and tt.nd('5100')=770);
select tt.chk('T7 no write-off for the restocked returns: wastage rows exist only for the 4 returns above', (select count(*) from stock_wastage where reason_code='customer_return')=4);

\echo == T8 report and settings screen data
set role authenticated; select tt.as(:'u_c');
select tt.err('T8 a cashier cannot read the report', $$select _w1c_return_report()$$, 'not allowed');
select tt.as(:'u_m');
select _w1c_return_report(tt.today()-1, tt.today(), null) as rep \gset
select tt.chk('T8 report by reason and class: written off 3 + 3 + 2 + 2 across classes, restocked quantities shown, overrides listed', (select coalesce(sum((x ->> 'written_off_qty')::numeric),0) from jsonb_array_elements(:'rep'::jsonb -> 'by_reason') x)=10
  and jsonb_array_length(:'rep'::jsonb -> 'overrides')=3 and (select count(*) from jsonb_array_elements(:'rep'::jsonb -> 'by_reason') x where x ->> 'class'='test_perish')>=1);
select tt.chk('T8 report value of write-offs equals 770', (select coalesce(sum((x ->> 'written_off_value')::numeric),0) from jsonb_array_elements(:'rep'::jsonb -> 'by_reason') x)=770);
select tt.as(:'u_o');
select _w1c_return_settings() as st \gset
select tt.chk('T8 settings screen data: classes with item counts, the perishable hint from the shelf-life rules, the configured one marked',
  (select (x ->> 'perishable')::boolean and (x ->> 'configured')::boolean and x ->> 'restock'='no_restock' from jsonb_array_elements(:'st'::jsonb -> 'classes') x where x ->> 'class_code'='test_perish')
  and (select not (x ->> 'configured')::boolean from jsonb_array_elements(:'st'::jsonb -> 'classes') x where x ->> 'class_code'='test_dry'));
reset role;

\echo == T9 not covered: a return made by the plain sale_return (no wrapper, no hook) is counted, never hidden
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,2,100) as sk \gset
select tt.as(:'u_m');
select sale_return(gen_random_uuid(), :'sk'::uuid, format('[{"item_id":"%s","qty":2}]',:'i2')::jsonb, 'damaged', null, 'cash') ->> 'id' as r9 \gset
select (_w1c_return_report(tt.today()-1, tt.today(), null) ->> 'not_covered')::int as nc \gset
reset role;
select tt.chk('T9 the plain call still works exactly as before (stock back) and the report counts it as not covered', :'nc'=1 and exists (select 1 from stock_ledger where reason='sale_return' and ref_id=:'r9') and not exists (select 1 from w1c_returns where return_id=:'r9'::uuid));

\echo == T10 append-only and nothing deleted
select tt.err('T10 return header cannot be edited', $$update w1c_returns set override=true$$, 'w1c_append_only');
select tt.err('T10 return lines cannot be deleted', $$delete from w1c_return_lines$$, 'w1c_append_only');
select tt.err('T10 class rules are never deleted', $$delete from w1c_return_class_rules$$, 'nothing is deleted');

\echo == T11 paste twice
select count(*) as nl from w1c_return_lines \gset
\i supabase/phase91.sql
select tt.chk('T11 second paste: no error, rows and settings survive, one grant row, one wastage reason', (select count(*) from w1c_return_lines)=:'nl'::int and (select count(*) from grant_defs where grant_code='return_override')=1
  and (select count(*) from option_lists where list_code='wastage_reasons' and value_code='customer_return')=1 and rule_txt('return_expired_restock')='allow');

\echo == T12 the two hooks, proved on a SCRATCH COPY (this database keeps the original sale_return and void_sale_return)
select current_database() as w1c_main \gset
select count(*) filter (where not ok) as f0 from tt.res \gset
\c postgres
drop database if exists w1c_scratch91;
create database w1c_scratch91 template :"w1c_main";
\c w1c_scratch91
select _w1c_patch('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);', E'  perform public._w1c_return_hook(rid); /* bos91 */\n  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);'], 'bos91') as pa \gset
select _w1c_patch('public.void_sale_return(uuid,text)'::regprocedure, array[
  E'  if r.status = ''void'' then return jsonb_build_object(''dup'', true, ''status'', ''void''); end if;', E'  if r.status = ''void'' then return jsonb_build_object(''dup'', true, ''status'', ''void''); end if;\n  perform public._w1c_return_void_guard(p_id); /* bos91 */'], 'bos91') as pb \gset
select _w1c_patch('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);', E'  perform public._w1c_return_hook(rid); /* bos91 */\n  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);'], 'bos91') as pa2 \gset
select tt.chk('T12 both hooks applied once; a second call is a no-op', :'pa'='t' and :'pb'='t' and :'pa2'='f'
  and position('bos91' in pg_get_functiondef('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'::regprocedure))>0 and position('bos91' in pg_get_functiondef('public.void_sale_return(uuid,text)'::regprocedure))>0);
-- state now: class test_perish = no_restock, global defaults (receipt off, window blank, expired allow); item one stock 17
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i1'::uuid,2,200) as s12a \gset
select tt.as(:'u_m');
select sale_return(gen_random_uuid(), :'s12a'::uuid, format('[{"item_id":"%s","qty":2}]',:'i1')::jsonb, 'quality', null, 'cash') ->> 'id' as r12a \gset
reset role;
select tt.chk('T12 the PLAIN sale_return now obeys the class rule by itself: 2 kg written off, stock unchanged by the pair', tt.wo_qty(:'r12a'::uuid)=2 and exists (select 1 from w1c_returns where return_id=:'r12a'::uuid));
-- window by a direct call
update rules set value='24' where key='return_window_hours';
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,1,100) as s12b \gset
reset role;
select tt.age(:'s12b'::uuid, 40);
set role authenticated; select tt.as(:'u_m');
select tt.err('T12 a direct sale_return call past the window is refused (a hidden button is also a refused request)', format($$select sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb, 'damaged', null, 'cash')$$, :'s12b', :'i2'), 'return_window_exceeded');
select tt.chk('T12 and nothing was written (no return for that sale)', not exists (select 1 from sale_returns where sale_id=:'s12b'::uuid));
-- wrapper on top of the hook: one header only, args honoured
select tt.as(:'u_mo');
select _w1c_sale_return(gen_random_uuid(), :'s12b'::uuid, format('[{"item_id":"%s","qty":1}]',:'i2')::jsonb, 'damaged', null, 'cash', null, null, null, null, 'checked by the manager') as r12b \gset
reset role;
select tt.chk('T12 wrapper over the hook: override honoured, exactly one header', (select count(*) from w1c_returns where sale_id=:'s12b'::uuid)=1 and (select override from w1c_returns where sale_id=:'s12b'::uuid));
update rules set value=null where key='return_window_hours';
-- void guard
select (:'r12a')::text <> '' as dummy \gset
set role authenticated; select tt.as(:'u_o');
select tt.err('T12 void of a return that wrote goods off is refused (the write-off cannot be undone in the books)', format($$select void_sale_return(%L::uuid,'typo')$$, :'r12a'), 'return_written_off');
select tt.chk('T12 void of a return that only restocked still works', (void_sale_return((:'r12b'::jsonb ->> 'id')::uuid, 'typo') ->> 'status')='void');
reset role;
-- defaults + hook = the same stock movements as without the hook
update w1c_return_class_rules set active=false;
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,3,100) as s12c \gset
select tt.as(:'u_m');
select sale_return(gen_random_uuid(), :'s12c'::uuid, format('[{"item_id":"%s","qty":3}]',:'i2')::jsonb, 'damaged', null, 'cash') ->> 'id' as r12c \gset
reset role;
select tt.chk('T12 all settings at default + hook: one stock row "sale_return +3", no wastage, nothing refused: exactly what the original function did',
  (select string_agg(reason || ':' || qty_delta::text, ',' order by id) from stock_ledger where ref_id=:'r12c' and ref_type='sale_return')='sale_return:3.0000' and tt.wo_qty(:'r12c'::uuid)=0
  and not exists (select 1 from stock_ledger where reason='wastage' and ref_id in (select unnest(wastage_ids)::text from w1c_return_lines where return_id=:'r12c'::uuid)));
select count(*) filter (where not ok) as f1 from tt.res \gset
\c postgres
drop database if exists w1c_scratch91;
\c :w1c_main
select tt.chk('T12 hook proof on the scratch copy: no failed check (scratch failures: ' || (:'f1'::int - :'f0'::int) || ')', (:'f1'::int - :'f0'::int) = 0);
select tt.chk('T12 the tested database still has the ORIGINAL sale_return and void_sale_return (hooks were not committed)', position('bos91' in pg_get_functiondef('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'::regprocedure))=0
  and position('bos91' in pg_get_functiondef('public.void_sale_return(uuid,text)'::regprocedure))=0);
select tt.chk('T12 no demo data: every name in this file starts with test_', not exists (select 1 from profiles where full_name <> '' and full_name not like 'test\_%'));
select tt.chk('T12 every journal entry in the tested database balances', tt.unbalanced()=0);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
