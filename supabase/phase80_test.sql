-- FRESH DB ONLY. Phase 80 tests: opening balance in one step (G2/G3/G7) and owner approval modes (G15).
--   ORDER="phase8 ... phase79 phase80" bash tests/sql/build_fresh_db.sh a80db ; psql -h /tmp -p 5544 -U postgres -d a80db -qAt -f supabase/phase80_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). All numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set t '00000000-0000-0000-0000-000000000003'
\set m '00000000-0000-0000-0000-000000000004'
\set o2 '00000000-0000-0000-0000-000000000005'
\set q '00000000-0000-0000-0000-000000000006'
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
create or replace function tt.unbalanced_entries() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.bal(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner@s.app','{"full_name":"test_owner"}'), (:'s','test_manager@s.app','{"full_name":"test_manager"}'), (:'t','test_accountant@s.app','{"full_name":"test_accountant"}'),
 (:'m','test_mgmt@s.app','{"full_name":"test_mgmt"}'), (:'o2','test_owner2@s.app','{"full_name":"test_owner2"}'), (:'q','test_purch@s.app','{"full_name":"test_purch"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'o2','owner'),(:'s','showroom_manager'),(:'m','management'),(:'q','purchasing') on conflict do nothing;
insert into user_locations values (:'s',1),(:'m',1),(:'q',1) on conflict do nothing;
with i as (insert into items (name_bn, name_en, unit, base_unit, sell_price, tracked, item_type) values ('test_raw','test_raw','kg','kg',0,true,'raw_material') returning id) select id as ir from i \gset
with i as (insert into items (name_bn, name_en, unit, base_unit, sell_price, tracked, item_type) values ('test_fg','test_fg','pc','pc',100,true,'finished_good') returning id) select id as ig from i \gset
with c as (insert into customers (mobile, name) values ('01000000001','test_customer') returning id) select id as cu from c \gset
with c as (insert into suppliers (name) values ('test_supplier') returning id) select id as su from c \gset

\echo == T0 shape
select tt.chk('T0 functions exist, anon cannot run them', has_function_privilege('authenticated','opening_balance_post(jsonb,uuid,boolean,boolean)','execute') and not has_function_privilege('anon','opening_balance_post(jsonb,uuid,boolean,boolean)','execute')
  and not has_function_privilege('anon','owner_approval_mode_set(text,text,text)','execute'));
select tt.chk('T0 rules exist with safe defaults (mode self, no approver role)', (select count(*) from rules where key in ('owner_approval_mode','owner_approver_role'))=2);

\echo == A opening balance
set role authenticated; select tt.as(:'o');
select set_user_grant(:'t'::uuid,'accounts_manage') is null as g1 \gset
select tt.err('A1 start date missing: data needed', $$select opening_balance_post('{"cash":[{"mode":"cash","amount":10,"location_id":1}],"capital":[{"kind":"owner","amount":10}]}'::jsonb)$$, 'data_needed');
select acct_set_start(tt.today()) is not null as st \gset
select tt.as(:'s'); select tt.err('A2 no permission: refused', $$select opening_balance_post('{"cash":[{"mode":"cash","amount":10,"location_id":1}],"capital":[{"kind":"owner","amount":10}]}'::jsonb)$$, 'not allowed');
select tt.as(:'o');
select tt.err('A3 unbalanced is refused', $$select opening_balance_post('{"cash":[{"mode":"cash","amount":1000,"location_id":1}],"capital":[{"kind":"owner","amount":600}]}'::jsonb)$$, 'unbalanced');
select tt.err('A3 unknown section refused', $$select opening_balance_post('{"zzz":[]}'::jsonb)$$, 'bad_payload');
select tt.err('A3 stock without a cost is refused (no invented cost)', format($$select opening_balance_post('{"stock":[{"item_id":"%s","location_id":1,"qty":5}],"capital":[{"kind":"owner","amount":1}]}'::jsonb)$$, :'ir'), 'cost_missing');
select tt.err('A3 unknown item refused', $$select opening_balance_post('{"stock":[{"item_id":"00000000-0000-0000-0000-0000000000ff","location_id":1,"qty":5,"unit_cost":2}],"capital":[{"kind":"owner","amount":1}]}'::jsonb)$$, 'unknown_item');
select tt.err('A3 owner / partner kind must be known', $$select opening_balance_post('{"cash":[{"mode":"cash","amount":5,"location_id":1}],"capital":[{"kind":"x","amount":5}]}'::jsonb)$$, 'bad_kind');
-- numbers: stock raw 10 kg x 50 = 500 (place 1), finished 20 pc x 30 = 600 (place 1); cash place1 2000, place2 800, bank 3000, wallet (mobile) 700;
-- customer due 400; supplier due 900. Debit = 500+600+2000+800+3000+700+400 = 8000. Credit: supplier 900 + owner capital 4500 + partner capital 2600 = 8000.
select format('{"stock":[{"item_id":"%s","location_id":1,"qty":10,"unit":"kg","unit_cost":50},{"item_id":"%s","location_id":1,"qty":20,"unit":"pc","unit_cost":30}],
 "cash":[{"mode":"cash","amount":2000,"location_id":1},{"mode":"cash","amount":800,"location_id":2},{"mode":"bank","amount":3000},{"mode":"mobile","amount":700,"wallet":"test_wallet","location_id":1}],
 "customer_dues":[{"customer_id":"%s","amount":400,"location_id":1}],"supplier_dues":[{"supplier_id":"%s","amount":900,"location_id":1}],
 "capital":[{"kind":"owner","amount":4500},{"kind":"partner","amount":2600,"party_id":"test_partner"}]}', :'ir', :'ig', :'cu', :'su') as pay \gset
select opening_balance_post(:'pay'::jsonb, null, true) as dr \gset
select tt.chk('A4 dry run shows both totals 8000 and writes nothing', (:'dr'::jsonb->>'total_debit')::numeric=8000 and (:'dr'::jsonb->>'total_credit')::numeric=8000 and (:'dr'::jsonb->>'balanced')::boolean
  and (select count(*) from journal_entries)=0 and (select count(*) from stock_ledger where reason='opening')=0 and (select count(*) from opening_batches)=0);
-- atomic: second stock line has qty 0 -> stock_opening refuses AFTER the journal call; nothing may remain
select tt.err('A5 a failing stock line rolls everything back', format($$select opening_balance_post('{"stock":[{"item_id":"%s","location_id":1,"qty":0,"unit":"kg","unit_cost":5}],"capital":[{"kind":"owner","amount":0}],"cash":[]}'::jsonb)$$, :'ir'), '');
select tt.chk('A5 ... no journal, no stock, no batch, no audit line', (select count(*) from journal_entries)=0 and (select count(*) from stock_ledger where reason='opening')=0 and (select count(*) from opening_batches)=0
  and (select count(*) from audit_log where action='opening_post')=0);
select opening_balance_post(:'pay'::jsonb, 'b0000000-0000-0000-0000-0000000000b1') as pr \gset
select tt.chk('A6 posted: one opening entry, Dr = Cr = 8000', (select count(*) from journal_entries where source_type='opening')=1 and (select sum(debit)=8000 and sum(credit)=8000 from journal_lines where entry_id=(:'pr'::jsonb->>'id')::bigint) and tt.unbalanced_entries()=0);
select tt.chk('A6 inventory by type: raw 500, finished goods 600; stock ledger opening rows match', tt.bal('1320')=500 and tt.bal('1310')=600
  and (select count(*) from stock_ledger where reason='opening')=2);
select tt.chk('A6 cash per place and wallet and bank: cash 2800, bank 3000, wallets 700', tt.bal('1110')=2800 and tt.bal('1120')=3000 and tt.bal('1130')=700
  and (select sum(debit) from journal_lines where location_id=2)=800);
select tt.chk('A6 dues and payables with their party', tt.bal('1210')=400 and tt.bal('2100')=-900
  and exists (select 1 from journal_lines l where l.party_type='customer' and l.party_id=:'cu') and exists (select 1 from journal_lines l where l.party_type='supplier' and l.party_id=:'su'));
select tt.chk('A6 owner capital 4500 and partner capital 2600 (partner line carries the partner)', tt.bal('3100')=-4500 and tt.bal('3200')=-2600 and not exists (select 1 from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='opening' and a.code='3900'));
select tt.chk('A7 audit_log has one opening_post line with the totals; batch row written', (select count(*) from audit_log where action='opening_post' and record_id=(:'pr'::jsonb->>'id'))=1
  and (select (detail->>'total_debit')::numeric from audit_log where action='opening_post')=8000 and (select count(*) from opening_batches where client_id='b0000000-0000-0000-0000-0000000000b1')=1);
select tt.chk('A8 same client id again returns the saved result, nothing new', (opening_balance_post(:'pay'::jsonb, 'b0000000-0000-0000-0000-0000000000b1') ->> 'dup')='true' and (select count(*) from journal_entries where source_type='opening')=1);
select tt.err('A8 a second post (new client id) is refused', format($$select opening_balance_post(%L::jsonb, 'b0000000-0000-0000-0000-0000000000b2')$$, :'pay'), 'opening_exists');
select tt.err('A8 ... also with the plug option', format($$select opening_balance_post(%L::jsonb, null, false, true)$$, :'pay'), 'opening_exists');
select tt.chk('A8 ... and no stock was posted twice', (select count(*) from stock_ledger where reason='opening')=2 and (select count(*) from opening_batches)=1);
reset role;
select tt.err('A9 the batch trail is append-only', $$update opening_batches set summary='{}'$$, 'append-only');
select tt.err('A9 ... and cannot be deleted', $$delete from opening_batches$$, 'append-only');
set role authenticated; select tt.as(:'o');
select tt.chk('A10 balance sheet balances after the opening', (acct_balance_sheet(tt.today()) ->> 'unbalanced') = 'false');

\echo == B owner approval modes
select tt.chk('B0 default: mode self, legacy switch ON', (owner_approval_mode()->>'mode')='self' and rule_on('owner_self_approve'));
select save_entry(null,'10-2',1,current_date,'{}','[]') ->> 'id' as e1 \gset
select submit_entry(:'e1'::uuid) is not null as s1 \gset
select tt.chk('B1 self mode: the owner approves his own entry', (decide_entry(:'e1'::uuid, true, null, '{}', '[]') ->> 'status')='approved');
select tt.as(:'m'); select tt.err('B2 only the owner sets the mode', $$select owner_approval_mode_set('named','management')$$, 'not allowed');
select tt.as(:'o');
select tt.err('B2 unknown mode refused', $$select owner_approval_mode_set('zzz')$$, 'bad_value');
select tt.err('B2 named without a role: data needed (blank blocks)', $$select owner_approval_mode_set('named')$$, 'data_needed');
select tt.err('B2 named with an unknown role refused', $$select owner_approval_mode_set('named','no_such_role')$$, 'bad_role');
select tt.err('B2 named with a role nobody holds refused', $$select owner_approval_mode_set('named','storekeeper')$$, 'no_other_approver');
select tt.err('B2 the mode rule cannot be changed around the setter', $$select set_rule('owner_approval_mode','"off"')$$, 'owner_approval_mode_set');
select owner_approval_mode_set('named','management','test: owner away') as nm \gset
select tt.chk('B3 named: mode saved, legacy switch OFF, one audit line with old and new', (owner_approval_mode()->>'mode')='named' and not rule_on('owner_self_approve')
  and (select count(*) from audit_log where action='owner_approval_mode')=1 and (select detail->'old'->>'mode' from audit_log where action='owner_approval_mode')='self');
select save_entry(null,'10-2',1,current_date,'{}','[]') ->> 'id' as e2 \gset
select submit_entry(:'e2'::uuid) is not null as s2 \gset
select tt.err('B4 named mode BLOCKS owner self-approval', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'e2'), 'cannot approve your own');
select tt.as(:'o2'); select tt.err('B4 another owner who is not the named role cannot decide it', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'e2'), 'named_approver_only');
select tt.as(:'m'); select tt.chk('B4 the named role decides it', (decide_entry(:'e2'::uuid, true, null, '{}', '[]') ->> 'status')='approved');
select tt.as(:'o');
select owner_approval_mode_set('self', null, 'test: back') is not null as sf \gset
select save_entry(null,'10-2',1,current_date,'{}','[]') ->> 'id' as e3 \gset
select submit_entry(:'e3'::uuid) is not null as s3 \gset
select tt.chk('B5 self mode allows self-approval again', (decide_entry(:'e3'::uuid, true, null, '{}', '[]') ->> 'status')='approved' and rule_on('owner_self_approve'));
select owner_approval_mode_set('logged') is not null as lg \gset
select save_entry(null,'10-2',1,current_date,'{}','[]') ->> 'id' as e4 \gset
select submit_entry(:'e4'::uuid) is not null as s4 \gset
select decide_entry(:'e4'::uuid, true, null, '{}', '[]') is not null as d4 \gset
select owner_approval_log() as lgj \gset
select tt.chk('B6 logged mode: self-approved entries show in the log with how = self', (:'lgj'::jsonb->>'mode')='logged' and exists (select 1 from jsonb_array_elements(:'lgj'::jsonb->'rows') r where r->>'how'='self' and r->>'id'=:'e4'));
select tt.as(:'m'); select tt.err('B6 the log is owner only', $$select owner_approval_log()$$, 'not allowed'); select tt.as(:'o');
select owner_approval_mode_set('off') is not null as of \gset
select tt.chk('B7 off: mode saved, owner may self-approve, log still works', (owner_approval_mode()->>'mode')='off' and rule_on('owner_self_approve') and (owner_approval_log()->>'mode')='off');
select tt.chk('B8 every change wrote one audit line (named, self, logged, off = 4)', (select count(*) from audit_log where action='owner_approval_mode')=4);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
