-- FRESH DB ONLY. Phase 40 tests (Module A: accounting - chart, journal, posting, reports).
--   ORDER="phase8 ... phase28 phase40" bash tests/sql/build_fresh_db.sh <db> ; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase40_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set h '00000000-0000-0000-0000-000000000004'
\set t '00000000-0000-0000-0000-000000000005'
\set u '00000000-0000-0000-0000-000000000006'
create schema if not exists tt;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
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
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}'), (:'h','head4@s.app','{"full_name":"Head"}'), (:'t','mgr5@s.app','{"full_name":"Manager Two"}'), (:'u','mgr6@s.app','{"full_name":"Loc2 Manager"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager'),(:'k','storekeeper'),(:'h','management'),(:'t','showroom_manager'),(:'u','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'h',1),(:'t',1),(:'u',2) on conflict do nothing;


\echo == shape
select tt.chk('A0 tables have RLS and no write grants', (select count(*) from pg_class where relname in ('coa_accounts','acct_mappings','journal_entries','journal_lines') and relrowsecurity)=4
  and not has_table_privilege('authenticated','journal_entries','insert') and not has_table_privilege('authenticated','journal_lines','insert') and not has_table_privilege('authenticated','coa_accounts','update')
  and not has_table_privilege('authenticated','acct_mappings','insert'));
select tt.chk('A0 anon cannot run anything', not has_function_privilege('anon','acct_post_pending(boolean,int)','execute') and not has_function_privilege('anon','acct_balance_sheet(date,int)','execute')
  and not has_function_privilege('authenticated','_acct_write(date,int,text,text,text,text,text,jsonb,bigint,uuid,text)','execute') and not has_function_privilege('authenticated','_acct_docs(date)','execute'));
select tt.chk('A0 chart is seeded (bakery chart) and every mapping points to a live account', (select count(*) from coa_accounts)>=45 and (select count(*) from acct_mappings)>=28
  and not exists (select 1 from acct_mappings m join coa_accounts a on a.id=m.account_id where not a.active or a.is_group));
select tt.chk('A0 rules start OFF / empty (nothing invented)', not rule_on('accounting_on') and rule_on('accounting_autopost') and rule_txt('accounting_start_date') is null);
select tt.chk('A0 grants exist', (select count(*) from grant_defs where grant_code in ('accounts_view','accounts_manage'))=2);

\echo == data (as postgres): items, supplier-less; users
with i as (insert into items (name_bn, name_en, unit, base_unit, sell_price, tracked, item_type) values ('Sugar','Sugar','kg','kg',0,true,'raw_material') returning id) select id as ie from i \gset
with i as (insert into items (name_bn, name_en, unit, base_unit, sell_price, tracked, item_type) values ('Cake','Cake','pc','pc',500,true,'resale') returning id) select id as ic from i \gset
with i as (insert into items (name_bn, name_en, unit, base_unit, sell_price, tracked, item_type) values ('Sweet','Sweet','kg','kg',500,true,'finished_good') returning id) select id as ifg from i \gset

\echo == access before anything
set role authenticated; select tt.as(:'o');
select tt.chk('A1 data needed while the start date is empty', (acct_balance_sheet(tt.today())->>'data_needed')::boolean and (acct_trial_balance(null,null)->>'data_needed')::boolean and (acct_post_pending(true)->>'data_needed')::boolean);
select tt.as(:'s'); select tt.err('A1 a manager without the grant cannot read', $$select acct_status()$$, 'not allowed'); select tt.err('A1 ... or post', $$select acct_post_pending(true)$$, 'not allowed');
select tt.as(:'k'); select tt.err('A1 storekeeper cannot read the trial balance', $$select acct_trial_balance(null,null)$$, 'not allowed');
select tt.as(:'o');
select set_user_grant(:'h'::uuid,'accounts_view') is null as g1 \gset
select set_user_grant(:'t'::uuid,'accounts_manage') is null as g2 \gset
select set_user_grant(:'u'::uuid,'accounts_view') is null as g3 \gset
select tt.err('A2 only the owner sets the start date', $$select 1$$, '') where false;
select tt.as(:'t'); select tt.err('A2 an accountant cannot set the start date', $$select acct_set_start(tt.today() - 1)$$, 'not allowed');
select tt.as(:'o');
select tt.err('A2 bad start date refused', $$select acct_set_start(null)$$, 'bad_date');
select acct_set_start(tt.today() - 1) ->> 'start' as sd \gset
select tt.chk('A2 start date saved in the rules', rule_txt('accounting_start_date') = :'sd');

\echo == chart of accounts
select tt.as(:'t');
select acct_account_save(null,'1115','পেটি ক্যাশ','Petty cash','asset',(select id from coa_accounts where code='1100'),true,15) ->> 'id' as pc \gset
select tt.chk('A3 accountant adds an account under a header', (select parent_id from coa_accounts where code='1115')=(select id from coa_accounts where code='1100') and (select normal_side from coa_accounts where code='1115')='debit');
select tt.err('A3 code is unique', $$select acct_account_save(null,'1115','x','x','asset')$$, 'code_taken');
select tt.err('A3 a parent must be a header', $$select acct_account_save(null,'1116','x','x','asset',(select id from coa_accounts where code='1110'))$$, 'bad_parent');
select tt.err('A3 the parent must be the same type', $$select acct_account_save(null,'1117','x','x','asset',(select id from coa_accounts where code='2000'))$$, 'bad_parent');
select acct_account_save(null,'1595','অবচয় ২','Accum dep 2','asset',null,true,null,true) is not null as okc \gset
select tt.chk('A3 a contra asset is credit-normal', (select normal_side from coa_accounts where code='1595')='credit');
select acct_account_save(:'pc'::bigint,null,'পেটি ক্যাশ ২','Petty cash 2',null,null,true,null) is not null as ren \gset
select tt.chk('A3 rename works, code and type stay', (select name_en||code||type from coa_accounts where id=:'pc'::bigint)='Petty cash 21115asset');
select acct_account_save(:'pc'::bigint,null,'পেটি ক্যাশ ২','Petty cash 2',null,null,false,null) is not null as ret \gset
select tt.chk('A3 retire = active false, row stays', (select active from coa_accounts where id=:'pc'::bigint)=false);
select tt.err('A3 a mapped system account cannot be retired', $$select acct_account_save((select id from coa_accounts where code='1110'),null,'a','a',null,null,false,null)$$, 'account_in_use_by_mapping');
select tt.as(:'s'); select tt.err('A3 no grant, no chart change', $$select acct_account_save(null,'9999','x','x','asset')$$, 'not allowed');
reset role;
select tt.err('A3 code cannot change (any path)', $$update coa_accounts set code='7777' where code='1115'$$, 'account_fixed');
select tt.err('A3 an account is never deleted', $$delete from coa_accounts where code='1115'$$, 'nothing is deleted');
set role authenticated; select tt.as(:'t');
select tt.err('A3 a retired account cannot be posted to', format($$select acct_journal_post(tt.today(),1,'try retired',%L::jsonb)$$, '[{"code":"1115","debit":10},{"code":"1110","credit":10}]'), 'account_retired');
select tt.err('A3 a header cannot be posted to', format($$select acct_journal_post(tt.today(),1,'try header',%L::jsonb)$$, '[{"code":"1100","debit":10},{"code":"1110","credit":10}]'), 'account_is_group');
select acct_mapping_set('pay_bank',(select id from coa_accounts where code='1120')) ->> 'key' as mk \gset
select tt.err('A3 a mapping needs a real account', $$select acct_mapping_set('pay_bank',(select id from coa_accounts where code='1100'))$$, 'bad_account');
select tt.err('A3 an unknown mapping key is refused', $$select acct_mapping_set('zzz_new',(select id from coa_accounts where code='1120'))$$, 'bad_key');

\echo == opening balances
select tt.as(:'o');
select save_supplier(null,'{"name":"Sugar Co","credit_days":7}') as sup1 \gset
select tt.as(:'t');
select tt.err('B1 opening must balance (or ask for the balancing figure)', format($$select acct_opening(%L::jsonb)$$, '[{"code":"1110","debit":1000},{"code":"3100","credit":600}]'), 'unbalanced');
select tt.err('B1 opening is balance sheet only', format($$select acct_opening(%L::jsonb,true)$$, '[{"code":"1110","debit":1000},{"code":"4100","credit":1000}]'), 'opening_balance_sheet_only');
select acct_opening(format('[{"code":"1110","debit":1000},{"code":"1320","debit":500},{"code":"2100","credit":700,"party_type":"supplier","party_id":"%s"},{"code":"3100","credit":600}]', :'sup1')::jsonb, true, null, null, true) as od \gset
select tt.chk('B1 opening dry run shows the plug and writes nothing', (:'od'::jsonb->>'dry')::boolean and (:'od'::jsonb->>'plug')::numeric=200 and (:'od'::jsonb->>'total_debit')::numeric=1500 and (select count(*) from journal_entries)=0);
select acct_opening(format('[{"code":"1110","debit":1000},{"code":"1320","debit":500},{"code":"2100","credit":700,"party_type":"supplier","party_id":"%s"},{"code":"3100","credit":600}]', :'sup1')::jsonb, true, null, 'a0000000-0000-0000-0000-0000000000a1') ->> 'id' as oid \gset
select tt.chk('B1 opening posted, dated the start date, balanced with 200 to retained earnings', (select entry_date from journal_entries where id=:'oid'::bigint)=:'sd'::date
  and (select sum(debit)=1500 and sum(credit)=1500 from journal_lines where entry_id=:'oid'::bigint) and (select credit from journal_lines l join coa_accounts a on a.id=l.account_id where l.entry_id=:'oid'::bigint and a.code='3900')=200);
select tt.err('B1 only one opening', $$select acct_opening('[{"code":"1110","debit":5},{"code":"3100","credit":5}]'::jsonb)$$, 'opening_exists');
select tt.as(:'o'); select tt.err('B1 start date cannot move past an existing entry', $$select acct_set_start(tt.today())$$, 'entries_before_start');

\echo == business events (as owner)
select tt.as(:'o');
select save_purchase(null,null,:'sup1'::uuid,1,'S-1',tt.today(),format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":100}]',:'ie')::jsonb) ->> 'id' as b1 \gset
select post_purchase(:'b1'::uuid, '[{"mode":"cash","amount":400}]') is not null as pp1 \gset
select save_purchase(null,null,:'sup1'::uuid,1,'S-2',tt.today(),format('[{"item_id":"%s","qty":10,"unit":"pc","unit_cost":300}]',:'ic')::jsonb) ->> 'id' as b2 \gset
select post_purchase(:'b2'::uuid) is not null as pp2 \gset
select save_purchase(null,null,:'sup1'::uuid,1,'S-3',tt.today(),'[{"description":"draft only","qty":1,"unit_cost":99}]'::jsonb) ->> 'id' as b3 \gset
select pay_supplier(:'sup1'::uuid,1,'[{"mode":"mobile","amount":500}]') is not null as ps \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":500}]',:'ic')::jsonb,0,'[{"mode":"cash","amount":1000}]',null,null,'retail',null,false) ->> 'id' as s1 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":500}]',:'ic')::jsonb,50,'[{"mode":"mobile","amount":200}]','01711111111','Rahim','retail',null,false) ->> 'id' as s2 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":500}]',:'ifg')::jsonb,0,'[{"mode":"card","amount":500}]',null,null,'retail',null,false) ->> 'id' as s3 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":500}]',:'ic')::jsonb,0,'[{"mode":"cash","amount":500}]',null,null,'retail',null,false) ->> 'id' as s4 \gset
select record_sale2(gen_random_uuid(),2,'[{"amount":100}]',0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,true) ->> 'id' as s5 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":500}]',:'ic')::jsonb,0,'[{"mode":"cash","amount":500}]',null,null,'retail',null,false,now() - interval '60 hours') ->> 'id' as sold \gset
select (select id from customers where mobile='01711111111') as cu \gset
select collect_payment(gen_random_uuid(),1,:'cu'::uuid,'[{"mode":"cash","amount":100}]',null) is not null as col \gset
select sale_return(gen_random_uuid(),:'s1'::uuid,format('[{"item_id":"%s","qty":1}]',:'ic')::jsonb,(select value_code from option_lists where list_code='return_reasons' and active limit 1),null,'cash') ->> 'id' as rt \gset
reset role;
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('10-2',1,9101,tt.today(),'approved','{"lines":[{"head":"transport","amount":"120","receipt":"yes"},{"head":"staff_meal","amount":"৮০","receipt":"yes"},{"head":"transport","amount":"abc"}]}','[]',:'s','st'),
 ('10-2',1,9102,tt.today(),'draft','{"lines":[{"head":"transport","amount":5000}]}','[]',:'s','st');
set role authenticated; select tt.as(:'o');
select cash_move_add(1,'bank_deposit',300,null,null,null,'slip',null,gen_random_uuid()) ->> 'id' as cm1 \gset
select cash_move_add(1,'owner_topup',5000,null,'cash',null,null,null,gen_random_uuid()) ->> 'id' as cm2 \gset
select cash_move_add(1,'owner_draw',70,null,'cash',null,null,null,gen_random_uuid()) ->> 'id' as cm3 \gset
select stock_wastage(:'ic'::uuid,1,1,'expired','test') is not null as ws \gset
select tt.chk('C0 nothing is posted yet (the books were not touched)', (select count(*) from journal_entries)=1);

\echo == posting: switch, dry run, real run
select tt.err('C1 posting needs the switch', $$select acct_post_pending(false)$$, 'accounting_off');
select tt.as(:'t');
select acct_post_pending(true) as dr \gset
select tt.chk('C1 dry run counts every document, writes nothing', (select count(*) from journal_entries)=1 and (:'dr'::jsonb->>'dry')::boolean
  and (:'dr'::jsonb->'by_type'->>'sale')::int=5 and (:'dr'::jsonb->'by_type'->>'purchase')::int=2 and (:'dr'::jsonb->'by_type'->>'supplier_payment')::int=2
  and (:'dr'::jsonb->'by_type'->>'collection')::int=1 and (:'dr'::jsonb->'by_type'->>'sale_return')::int=1 and (:'dr'::jsonb->'by_type'->>'expense_voucher')::int=1
  and (:'dr'::jsonb->'by_type'->>'cash_move')::int=3 and (:'dr'::jsonb->'by_type'->>'wastage')::int=1);
select tt.chk('C1 the sale before the start date and the draft bill / draft voucher are not in the list', (:'dr'::jsonb->>'posted')::int=16 and (:'dr'::jsonb->>'locked')::int=0 and jsonb_array_length(:'dr'::jsonb->'errors')=0);
select tt.chk('C1 dry run trial is balanced and shown', (:'dr'::jsonb->>'total_debit')::numeric=(:'dr'::jsonb->>'total_credit')::numeric and jsonb_array_length(:'dr'::jsonb->'trial')>5 and jsonb_array_length(:'dr'::jsonb->'preview')>0);
select tt.chk('C1 the sale with no cost is flagged, nothing guessed', (:'dr'::jsonb->>'cogs_missing')::int=1);
select tt.chk('C1 missing salary / advance tables are reported', :'dr'::jsonb->'skipped_sources' @> '"staff_advances"'::jsonb);
select tt.as(:'o'); select set_rule('accounting_on','true') is null as on1 \gset
select tt.as(:'t');
select acct_post_pending(false) as pr \gset
select tt.chk('C2 real run posts the same 16 documents', (:'pr'::jsonb->>'posted')::int=16 and (select count(*) from journal_entries)=17 and jsonb_array_length(:'pr'::jsonb->'errors')=0);
select acct_post_pending(false) as pr2 \gset
select tt.chk('C2 posting again posts nothing (idempotent)', (:'pr2'::jsonb->>'posted')::int=0 and (:'pr2'::jsonb->>'reversed')::int=0 and (select count(*) from journal_entries)=17);
reset role;
select tt.chk('C2 every entry balances, no line has both sides', not exists (select 1 from journal_lines group by entry_id having sum(debit)<>sum(credit)) and not exists (select 1 from journal_lines where debit>0 and credit>0));
select tt.chk('C2 the 10-2 voucher posted 200 (Bangla digits read, the unreadable line flagged)', (select flags from journal_entries where source_type='expense_voucher')='unreadable_lines'
  and (select sum(l.debit) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='expense_voucher')=200);
select tt.chk('C2 sale of the cost-less item has no COGS line and carries the flag', (select flags from journal_entries where source_type='sale' and source_id=:'s3')='cogs_missing'
  and not exists (select 1 from journal_lines l join coa_accounts a on a.id=l.account_id where l.entry_id=(select id from journal_entries where source_type='sale' and source_id=:'s3') and a.code='5000'));
select tt.chk('C2 sale S2 split: mobile 200, receivable 250 for the customer, discount 50, sales 500, COGS 300', (
  select string_agg(a.code||':'||l.debit::int||'/'||l.credit::int||coalesce(':'||l.party_type,''), ',' order by a.code) from journal_lines l join coa_accounts a on a.id=l.account_id
  where l.entry_id=(select id from journal_entries where source_type='sale' and source_id=:'s2')) = '1130:200/0,1210:250/0:customer,1310:0/300,4100:0/500,4120:50/0,5000:300/0');
set role authenticated; select tt.as(:'t');

\echo == reports (numbers)
select acct_trial_balance(null,null) as tb \gset
select tt.chk('D1 trial balance balances', (:'tb'::jsonb->>'balanced')::boolean and (:'tb'::jsonb->>'total_debit')::numeric>0);
select acct_balance_sheet(tt.today()) as bs \gset
select tt.chk('D2 balance sheet balances: assets = liabilities + equity', not (:'bs'::jsonb->>'unbalanced')::boolean and (:'bs'::jsonb->>'difference')::numeric=0);
select tt.chk('D2 an accountant with a company-wide grant sees every place: assets 10180 = liabilities 3800 + equity 5730 + earnings 650', (:'bs'::jsonb->>'total_assets')::numeric = 10180 and (:'bs'::jsonb->>'total_liabilities')::numeric = 3800
  and (:'bs'::jsonb->>'total_equity')::numeric = 5730 and (:'bs'::jsonb->>'retained_earnings')::numeric = 650);
select tt.as(:'h');
select acct_balance_sheet(tt.today()) as bsh \gset
select tt.chk('D2 head management (all places) sees the same figures and the sheet balances', (:'bsh'::jsonb->>'total_assets')::numeric = 10180 and (:'bsh'::jsonb->>'total_liabilities')::numeric = 3800
  and (:'bsh'::jsonb->>'total_equity')::numeric = 5730 and (:'bsh'::jsonb->>'retained_earnings')::numeric = 650 and not (:'bsh'::jsonb->>'unbalanced')::boolean);
select tt.chk('D2 per-account balances: cash 6230, bank 300, mobile -300, card 500, receivable 150, finished goods 1800, raw 1500',
  (select string_agg(r->>'code'||'='||(r->>'amount')::numeric::int, ',' order by r->>'code') from jsonb_array_elements(:'bsh'::jsonb->'assets') r where not (r->>'is_group')::boolean)
   = '1110=6230,1120=300,1130=-300,1140=500,1210=150,1310=1800,1320=1500');
select acct_balance_sheet(tt.today(), 1) as bs1 \gset
select tt.chk('D2 place filter: place 1 only (no opening, no place-2 sale)', (:'bs1'::jsonb->>'total_assets')::numeric = 8580 and (:'bs1'::jsonb->>'total_liabilities')::numeric = 3100 and (:'bs1'::jsonb->>'retained_earnings')::numeric = 550 and not (:'bs1'::jsonb->>'unbalanced')::boolean);
select tt.as(:'o');
select acct_income_statement(null,null) as is_all \gset
select tt.chk('D3 P&L (all places): income 2050, COGS 900, gross 1150, expenses 1400 (incl. COGS) → net 650', (:'is_all'::jsonb->>'total_income')::numeric = 2050 and (:'is_all'::jsonb->>'cogs')::numeric = 900
  and (:'is_all'::jsonb->>'gross_profit')::numeric = 1150 and (:'is_all'::jsonb->>'total_expense')::numeric = 1400 and (:'is_all'::jsonb->>'net_profit')::numeric = 650);
select tt.chk('D3 P&L says how many sales had no cost', (:'is_all'::jsonb->>'cogs_missing')::int = 1);
select tt.chk('D3 income lines: sales 2600, returns -500, discounts -50', (select string_agg(r->>'code'||'='||(r->>'amount')::numeric::int, ',' order by r->>'code') from jsonb_array_elements(:'is_all'::jsonb->'income') r where not (r->>'is_group')::boolean) = '4100=2600,4110=-500,4120=-50');
select acct_ledger((select id from coa_accounts where code='1110'), null, null) as lg \gset
select tt.chk('D4 cash ledger: opening 0, running balance ends at the balance-sheet figure', (:'lg'::jsonb->>'closing')::numeric = 6230 and jsonb_array_length(:'lg'::jsonb->'rows') > 8
  and (:'lg'::jsonb->'rows'->0->>'balance')::numeric = 1000);
select tt.chk('D4 ledger rows carry the source document link', (select bool_and(r->>'source_type' is not null and r->>'source_id' is not null) from jsonb_array_elements(:'lg'::jsonb->'rows') r));
select tt.chk('D4 a header ledger adds its children (Cash & bank)', (acct_ledger((select id from coa_accounts where code='1100'), null, null)->>'closing')::numeric = 6230+300-300+500);
select acct_cash_flow(null,null) as cf \gset
select tt.chk('D5 cash flow: closing = opening + in - out and equals cash+bank+wallet (6230+300-300)', (:'cf'::jsonb->>'closing')::numeric = 6230 and (:'cf'::jsonb->>'opening')::numeric = 0
  and (:'cf'::jsonb->>'total_in')::numeric - (:'cf'::jsonb->>'total_out')::numeric = 6230);
select acct_journal_book(null,null) as jb \gset
select tt.chk('D6 journal book lists entries with their lines', (:'jb'::jsonb->>'total')::int = 17 and jsonb_array_length(:'jb'::jsonb->'rows'->0->'lines') >= 2);
select acct_party_ledger('customer', :'cu') as pl \gset
select tt.chk('D7 customer sub-ledger: 250 sale due - 100 collection = 150', (:'pl'::jsonb->>'closing')::numeric = 150 and jsonb_array_length(:'pl'::jsonb->'rows') = 2);
select acct_party_ledger('supplier', :'sup1') as pls \gset
select tt.chk('D7 supplier sub-ledger: opening 700 + 4000 bills - 400 - 500 paid = 3800', (:'pls'::jsonb->>'closing')::numeric = 3800);
select tt.err('D7 bad party type', $$select acct_party_ledger('alien','x')$$, 'bad_party');

\echo == reconciliation with customer_dues / supplier_dues
select acct_reconcile('all') as rc \gset
select tt.chk('E1 customers agree with the existing balance', (:'rc'::jsonb->>'customers_off')::int = 0);
select tt.chk('E1 suppliers differ by exactly the opening balance not yet in the supplier record (700)', (:'rc'::jsonb->>'suppliers_off')::int = 1 and (:'rc'::jsonb->'suppliers'->0->>'unexplained')::numeric = 700);
reset role; update suppliers set opening_balance = 700 where id = :'sup1'::uuid; set role authenticated; select tt.as(:'o');
select tt.chk('E1 after the supplier opening balance is recorded: no differences', (acct_reconcile('supplier')->>'suppliers_off')::int = 0);
select tt.chk('E1 sub-ledger total agrees with supplier_dues()', (select balance from supplier_dues(null) where supplier_id = :'sup1'::uuid) = (select (acct_party_ledger('supplier', :'sup1')->>'closing')::numeric));
select tt.chk('E1 sub-ledger total agrees with customer_dues()', (select balance from customer_dues() where id = :'cu'::uuid) = (select (acct_party_ledger('customer', :'cu')->>'closing')::numeric));
select tt.as(:'u'); select tt.err('E1 reconciliation covers every place: owner / head / company-wide accountant only', $$select acct_reconcile('all')$$, 'not allowed');

\echo == voids reverse, they never edit
select tt.as(:'o');
select void_sale(:'s4'::uuid, 'wrong bill') is null as v1 \gset
select cash_move_void(:'cm3'::uuid, 'typed twice') is not null as v2 \gset
select tt.as(:'t');
select acct_post_pending(true) as vd \gset
select tt.chk('F1 dry run lists the two reversals', (:'vd'::jsonb->>'reversed')::int = 2 and (select count(*) from journal_entries)=17);
select acct_post_pending(false) as vr \gset
select tt.chk('F1 void sale + void cash move = 2 reversing entries', (:'vr'::jsonb->>'reversed')::int = 2 and (select count(*) from journal_entries)=19);
select acct_post_pending(false) as vr2 \gset
select tt.chk('F1 reversing again does nothing', (:'vr2'::jsonb->>'reversed')::int = 0 and (:'vr2'::jsonb->>'posted')::int = 0);
reset role;
select tt.chk('F1 the originals are marked void and each reversal mirrors it exactly', (select count(*) from journal_entries where status='void')=2
  and (select count(*) from journal_entries r join journal_entries o on o.id=r.reverses_id where
     (select sum(debit) from journal_lines where entry_id=r.id)=(select sum(credit) from journal_lines where entry_id=o.id))=2);
set role authenticated; select tt.as(:'o');
select acct_balance_sheet(tt.today()) as bsv \gset
select tt.chk('F1 after the voids: the sale (500, cost 300) and the owner draw (70) are undone, still balanced', (:'bsv'::jsonb->>'total_assets')::numeric = 10050 and (:'bsv'::jsonb->>'retained_earnings')::numeric = 450 and (:'bsv'::jsonb->>'total_liabilities')::numeric = 3800 and not (:'bsv'::jsonb->>'unbalanced')::boolean);

\echo == immutability
reset role;
select tt.err('G1 a journal line cannot be edited', $$update journal_lines set debit = debit + 1 where entry_id = (select min(id) from journal_entries)$$, 'append_only');
select tt.err('G1 a journal line cannot be deleted', $$delete from journal_lines where entry_id = (select min(id) from journal_entries)$$, 'append_only');
select tt.err('G1 an entry cannot be deleted', $$delete from journal_entries where id = (select min(id) from journal_entries)$$, 'append_only');
select tt.err('G1 an entry cannot be edited (memo)', $$update journal_entries set memo = 'x' where id = (select min(id) from journal_entries)$$, 'append_only');
select tt.err('G1 a posted entry cannot be voided without its reversal', $$update journal_entries set status = 'void' where id = (select max(id) from journal_entries where reverses_id is null and status='posted')$$, 'append_only');
select tt.err('G1 truncate refused', $$truncate journal_lines$$, 'append_only');
select tt.err('G1 an unbalanced entry cannot be committed', $$do $x$ declare i bigint; begin insert into journal_entries (entry_date, source_type, source_id, memo) values (tt.today(),'t','unb','x') returning id into i;
  insert into journal_lines (entry_id, line_no, account_id, debit) values (i,1,(select id from coa_accounts where code='1110'),10); set constraints all immediate; end $x$ $$, 'unbalanced');
select tt.err('G1 one entry per source document', $$insert into journal_entries (entry_date, source_type, source_id, memo) select entry_date,source_type,source_id,'dup' from journal_entries where source_type='sale' limit 1$$, 'duplicate key');
set role authenticated; select tt.as(:'o');
select tt.err('G1 direct writes are refused for everyone', $$insert into journal_entries (entry_date, source_type, source_id, memo) values (tt.today(),'x','y','z')$$, 'permission denied');
select tt.chk('G1 audit log records chart changes', (select count(*) from audit_log where table_name='coa_accounts')>=3);

\echo == manual journal
select tt.as(:'t');
select acct_journal_post(tt.today(),1,'Rent for October',format('[{"code":"5300","debit":3000},{"code":"1110","credit":3000}]')::jsonb,'b0000000-0000-0000-0000-0000000000b1',null,true) as mjd \gset
select tt.chk('H1 dry run validates and writes nothing', (:'mjd'::jsonb->>'dry')::boolean and (:'mjd'::jsonb->>'total_debit')::numeric=3000 and (select count(*) from journal_entries)=19);
select acct_journal_post(tt.today(),1,'Rent for October','[{"code":"5300","debit":3000},{"code":"1110","credit":3000}]'::jsonb,'b0000000-0000-0000-0000-0000000000b1') ->> 'id' as mj \gset
select tt.chk('H1 manual entry saved', (select count(*) from journal_entries where source_type='manual')=1 and (select count(*) from journal_entries)=20);
select tt.chk('H1 same client id = no second entry', (acct_journal_post(tt.today(),1,'Rent for October','[{"code":"5300","debit":3000},{"code":"1110","credit":3000}]'::jsonb,'b0000000-0000-0000-0000-0000000000b1')->>'dup')::boolean and (select count(*) from journal_entries)=20);
select tt.err('H1 unbalanced refused', $$select acct_journal_post(tt.today(),1,'unbalanced try','[{"code":"5300","debit":100},{"code":"1110","credit":90}]'::jsonb)$$, 'unbalanced');
select tt.err('H1 both sides on one line refused', $$select acct_journal_post(tt.today(),1,'both sides','[{"code":"5300","debit":100,"credit":100},{"code":"1110","credit":0}]'::jsonb)$$, 'line_debit_xor_credit');
select tt.err('H1 a single line refused', $$select acct_journal_post(tt.today(),1,'one line','[{"code":"5300","debit":100}]'::jsonb)$$, 'unbalanced');
select tt.err('H1 memo required', $$select acct_journal_post(tt.today(),1,'','[{"code":"5300","debit":100},{"code":"1110","credit":100}]'::jsonb)$$, 'memo_required');
select tt.err('H1 text amounts refused (NaN)', $$select acct_journal_post(tt.today(),1,'nan try','[{"code":"5300","debit":"NaN"},{"code":"1110","credit":"NaN"}]'::jsonb)$$, 'bad_amount');
select tt.err('H1 absurd amount refused', $$select acct_journal_post(tt.today(),1,'huge try','[{"code":"5300","debit":1e13},{"code":"1110","credit":1e13}]'::jsonb)$$, 'bad_amount');
select tt.err('H1 unknown account refused', $$select acct_journal_post(tt.today(),1,'unknown acct','[{"code":"0000","debit":100},{"code":"1110","credit":100}]'::jsonb)$$, 'unknown_account');
select tt.err('H1 nothing before the start date', $$select acct_journal_post(tt.today() - 5,1,'too early','[{"code":"5300","debit":100},{"code":"1110","credit":100}]'::jsonb)$$, 'before_start');
select tt.err('H1 no future dates', $$select acct_journal_post(tt.today() + 9,1,'future','[{"code":"5300","debit":100},{"code":"1110","credit":100}]'::jsonb)$$, 'bad_date');
select tt.err('H1 a party needs an id', $$select acct_journal_post(tt.today(),1,'party try','[{"code":"1210","debit":100,"party_type":"customer"},{"code":"1110","credit":100}]'::jsonb)$$, 'party_id_required');
select tt.err('H1 a place the accountant does not have', $$select acct_journal_post(tt.today(),2,'other place','[{"code":"5300","debit":100},{"code":"1110","credit":100}]'::jsonb)$$, 'not allowed for this location');
select tt.as(:'s'); select tt.err('H1 no grant, no journal', $$select acct_journal_post(tt.today(),1,'no grant','[{"code":"5300","debit":100},{"code":"1110","credit":100}]'::jsonb)$$, 'not allowed');
select tt.as(:'t');
select tt.err('H2 an automatic entry cannot be reversed by hand', $$select acct_journal_reverse((select id from journal_entries where source_type='sale' limit 1),'no good reason')$$, 'use_source');
select acct_journal_reverse(:'mj'::bigint, 'booked to the wrong month', 'b0000000-0000-0000-0000-0000000000b2') ->> 'id' as mr \gset
select tt.chk('H2 a manual entry is corrected by a reversing entry', (select reverses_id from journal_entries where id=:'mr'::bigint)=:'mj'::bigint and (select status from journal_entries where id=:'mj'::bigint)='void');
select tt.err('H2 reversed once only', format($$select acct_journal_reverse(%s,'again please')$$, :'mj'), 'already_reversed');
select tt.chk('H2 reversal retried with the same client id = no second one', (acct_journal_reverse(:'mj'::bigint, 'booked to the wrong month', 'b0000000-0000-0000-0000-0000000000b2')->>'dup')::boolean);

\echo == closed period, places, switches
select tt.as(:'o');
select record_sale2(gen_random_uuid(),1,'[{"amount":40}]',0,'[{"mode":"cash","amount":40}]',null,null,'retail',null,true) ->> 'id' as s6 \gset
select set_rule('period_closed_until', to_jsonb(tt.today()::text)) is null as cl \gset
select tt.as(:'t');
select tt.err('I1 a closed period blocks a manual journal for a non-owner', $$select acct_journal_post(tt.today(),1,'closed try','[{"code":"5300","debit":10},{"code":"1110","credit":10}]'::jsonb)$$, 'period_closed');
select acct_post_pending(false) as lk \gset
select tt.chk('I1 a closed day is not posted by a non-owner (counted as locked), nothing lost', (:'lk'::jsonb->>'locked')::int = 1 and (:'lk'::jsonb->>'posted')::int = 0);
select tt.as(:'o');
select acct_post_pending(false) as lk2 \gset
select tt.chk('I1 the owner may post into a closed period', (:'lk2'::jsonb->>'posted')::int = 1);
select set_rule('period_closed_until', null) is null as cl2 \gset
select tt.as(:'u');
select tt.chk('I2 a place-2 reader sees only place 2: sales 100, nothing else', (acct_income_statement(null,null)->>'total_income')::numeric = 100 and (acct_balance_sheet(tt.today())->>'total_assets')::numeric = 100);
select tt.err('I2 ... and not place 1', $$select acct_balance_sheet(tt.today(), 1)$$, 'not allowed for this location');
select tt.err('I2 view grant alone cannot post', $$select acct_post_pending(true)$$, 'not allowed');
select tt.err('I2 view grant alone cannot add accounts', $$select acct_account_save(null,'8888','x','x','asset')$$, 'not allowed');
select tt.chk('I2 direct table read is scoped too', (select count(*) from journal_lines where location_id=1)=0 and (select count(*) from journal_lines where location_id=2)>0);
select tt.as(:'s'); select tt.chk('I2 no grant: direct read shows nothing', (select count(*) from journal_lines)=0 and (select count(*) from coa_accounts)=0);
select tt.as(:'o');
select set_rule('accounting_on','false') is null as off1 \gset
select tt.err('I3 switch off: no real posting', $$select acct_post_pending(false)$$, 'accounting_off');
select tt.chk('I3 ... but reports and dry run still open', (acct_post_pending(true)->>'dry')::boolean and (acct_trial_balance(null,null)->>'balanced')::boolean);

\echo == production run and mappings
reset role;
insert into recipes (item_id, version, yield_qty) values (:'ifg'::uuid, 1, 5) returning id as rcp \gset
insert into production_runs (location_id, recipe_id, item_id, batches, made_at, yield_base, status) values (1, :'rcp'::uuid, :'ifg'::uuid, 1, now(), 5, 'done') returning id as pr1 \gset
select stock_post(:'ie'::uuid, 1, -2, 'issue_out', 'production', :'pr1', null, null, now(), null, null, 'none') is not null as sp \gset
set role authenticated; select tt.as(:'o');
select set_rule('accounting_on','true') is null as on2 \gset
select acct_post_pending(true) -> 'by_type' ->> 'production' as pd \gset
select tt.chk('J1 production dry run sees the run', :'pd' = '1');
select acct_post_pending(false) is not null as pp3 \gset
select tt.chk('J1 production moves ingredients at real cost: raw -200, finished goods +200', (select string_agg(a.code||':'||l.debit::int||'/'||l.credit::int, ',' order by a.code) from journal_lines l join coa_accounts a on a.id=l.account_id
  where l.entry_id=(select id from journal_entries where source_type='production' and source_id=:'pr1')) = '1310:200/0,1320:0/200');
select tt.chk('J1 posting again: nothing', (acct_post_pending(false)->>'posted')::int = 0);
select acct_mapping_set('pay_card',(select id from coa_accounts where code='1120')) is not null as remap \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":60}]',0,'[{"mode":"card","amount":60}]',null,null,'retail',null,true) ->> 'id' as s7 \gset
select acct_post_pending(false) is not null as pp4 \gset
select tt.chk('J1 a re-pointed mapping is used from then on (card sale lands in the bank account)', (select a.code from journal_lines l join coa_accounts a on a.id=l.account_id where l.entry_id=(select id from journal_entries where source_type='sale' and source_id=:'s7') and l.debit=60)='1120');
select tt.chk('J1 retired / re-pointed mappings keep old entries untouched', (select a.code from journal_lines l join coa_accounts a on a.id=l.account_id where l.entry_id=(select id from journal_entries where source_type='sale' and source_id=:'s3') and l.debit=500)='1140');

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
