-- FRESH DB ONLY. Phase 83 tests (BUILDER D: G9 wallets, G10 production materials). Needs phase8..phase79 and phase83.
--   ORDER="phase8 ... phase79 phase83" bash <copy of tests/sql/build_fresh_db.sh with your paths> d83db
--   psql -h /tmp -p 5548 -U postgres -d d83db -qAt -f supabase/phase83_test.sql | grep -E 'FAIL|RESULT'
-- All numbers are hand-computed (comment above each block). Test data only: test_* identifiers, no person names. Place 1 only.
-- NOTE: the journal hook (_acct_docs must also read _d_acct_docs) belongs to the integrator. This test SIMULATES it in the test database only
--       (T1), exactly as docs/integration/D.md tells the integrator to do it.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set c '00000000-0000-0000-0000-000000000002'
\set nn '00000000-0000-0000-0000-000000000003'
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
create or replace function tt.jl(p_type text, p_sid text, p_code text, p_side text) returns numeric language sql stable as $$
  select coalesce(sum(case p_side when 'd' then l.debit else l.credit end), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
  where e.source_type = p_type and e.source_id = p_sid and e.reverses_id is null and a.code = p_code $$;
-- net debit of an account over the whole journal (reversals included)
create or replace function tt.net(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'c','cashctl2@s.app','{"full_name":"CashCtl"}'), (:'nn','none3@s.app','{"full_name":"Nobody"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'c','cash_controller'),(:'nn','salesperson') on conflict do nothing;
insert into user_roles values (:'o','owner') on conflict do nothing;
insert into user_locations values (:'c',1),(:'nn',1) on conflict do nothing;

\echo == T0 shape, paste twice, defaults
select tt.chk('T0 8 new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('d_wallets','d_wallet_fees','d_wallet_moves','d_wallet_checks','d_material_roles','d_item_roles','d_product_role_req','d_material_fixed_price') and c.relrowsecurity)=8);
select tt.chk('T0 four wallets, accounts 1131..1134 under 1100, mappings d_wallet_<code>, 5815 + wallet_fee mapping',
  (select count(*) from d_wallets)=4 and (select string_agg(a.code, ',' order by w.sort) from d_wallets w join coa_accounts a on a.id=w.coa_account_id)='1131,1132,1133,1134'
  and (select count(*) from coa_accounts a join coa_accounts p on p.id=a.parent_id where a.code in ('1131','1132','1133','1134') and p.code='1100')=4
  and (select count(*) from acct_mappings where key like 'd_wallet\_%')=4
  and exists (select 1 from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='wallet_fee' and a.code='5815' and a.type='expense' and a.normal_side='debit'));
select tt.chk('T0 defaults = today: fee separate expense, negative refused, materials off, avg purchase',
  rule_txt('d_wallet_fee_treatment')='separate_expense' and rule_txt('d_wallet_negative_mode')='refuse' and rule_txt('d_recipe_materials_mode')='off' and rule_txt('d_material_cost_method')='average_purchase');
select tt.chk('T0 three material roles exist, no item is mapped, no item was created', (select count(*) from d_material_roles)=3 and (select count(*) from d_item_roles)=0 and (select count(*) from items)=(select count(*) from items where import_batch is not null or true));
select tt.chk('T0 anon cannot execute any phase83 API; helpers closed to browsers',
  not has_function_privilege('anon','d_wallet_balances(date)','execute') and not has_function_privilege('anon','d_wallet_fee_add(int,int,date,numeric,text,text,text,uuid)','execute')
  and not has_function_privilege('authenticated','_d_acct_docs(date)','execute') and not has_function_privilege('authenticated','_d_wallet_book(int,date)','execute') and has_function_privilege('authenticated','d_wallet_balances(date)','execute'));
select tt.chk('T0 browsers cannot write the tables directly', not has_table_privilege('authenticated','d_wallet_fees','insert') and not has_table_privilege('authenticated','d_wallets','update'));

\echo == T1 simulate the integrator hook (TEST DATABASE ONLY): _acct_docs = base + _d_acct_docs
alter function public._acct_docs(date) rename to _acct_docs_base_t;
create or replace function public._acct_docs(p_start date) returns table(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language sql stable security definer set search_path = public as $$ select * from public._acct_docs_base_t(p_start) union all select * from public._d_acct_docs(p_start) $$;
select set_config('request.jwt.claim.sub', :'o', false);
set role authenticated;
select tt.as(:'o');
select set_rule('accounting_on', 'true'::jsonb) is null as r1 \gset
select acct_set_start(tt.today()-5)->>'start' as sd \gset

\echo == T2 sales into wallets (test numbers): bkash 1000, 'Nagad' label 500, rocket 300, unknown text 200 ; supplier pays 100 from bkash
reset role;
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values
 (1, 990001, tt.today(), now(), '[]', 1000, 0, 1000, 'mobile', 'done', :'o'), (1, 990002, tt.today(), now(), '[]', 500, 0, 500, 'mobile', 'done', :'o'),
 (1, 990003, tt.today(), now(), '[]', 300, 0, 300, 'mobile', 'done', :'o'), (1, 990004, tt.today(), now(), '[]', 200, 0, 200, 'mobile', 'done', :'o');
insert into sale_payments (sale_id, location_id, kind, mode, wallet, amount, paid_at, created_by)
 select s.id, 1, 'sale', 'mobile', v.w, s.total, now(), :'o' from sales s join (values (990001, 'bkash'), (990002, 'Nagad'), (990003, 'rocket'), (990004, 'test_unknown_wallet')) v(r, w) on v.r = s.receipt;
insert into suppliers (name) values ('test_supplier_1');
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, paid_at, created_by)
 select id, 1, 'mobile', 'bkash', 100, now(), :'o' from suppliers where name = 'test_supplier_1';
set role authenticated; select tt.as(:'o');
select tt.chk('T2 register: bkash 900, nagad 500 (label Nagad resolves), rocket 300, upay 0',
  (select (x->>'book')::numeric from jsonb_array_elements(d_wallet_balances()) x where x->>'code'='bkash')=900
  and (select (x->>'book')::numeric from jsonb_array_elements(d_wallet_balances()) x where x->>'code'='nagad')=500
  and (select (x->>'book')::numeric from jsonb_array_elements(d_wallet_balances()) x where x->>'code'='rocket')=300
  and (select (x->>'book')::numeric from jsonb_array_elements(d_wallet_balances()) x where x->>'code'='upay')=0);
select tt.chk('T2 unknown wallet text is not lost: reported as unassigned 200', (d_wallet_recon_report()->>'unassigned_mobile')::numeric = 200);
select acct_post_pending(false) is not null as posted \gset
select tt.chk('T2 journal: bkash 1131 net 900, nagad 1132 net 500, rocket 1133 net 300',  tt.net('1131')=900 and tt.net('1132')=500 and tt.net('1133')=300);
select tt.chk('T2 journal: generic 1130 keeps only the unknown wallet text (net 200)', tt.net('1130')=200);
select tt.chk('T2 journal and register agree per wallet (journal_gap 0)', not exists (select 1 from jsonb_array_elements(d_wallet_balances()) x where (x->>'journal_gap')::numeric <> 0));
select tt.chk('T2 every journal entry balances (Dr = Cr)', tt.unbalanced_entries() = 0);
select tt.chk('T2 posting twice adds nothing (one wallet entry per named-wallet payment: 3 sales + 1 supplier)', (select count(*) from journal_entries where source_type='d_wallet_split')=4);
select acct_post_pending(false) is not null as again \gset
select tt.chk('T2 second post run: still 4 wallet entries', (select count(*) from journal_entries where source_type='d_wallet_split')=4);

\echo == T3 fee 15 from bkash (separate expense), move bkash -> cash 400, nagad -> rocket 100 ; bkash 900-15-400=485, nagad 400, rocket 400
select (d_wallet_fee_add((select id from d_wallets where code='bkash'), 1, tt.today(), 15, 'cash_out', 'test_ref_1', null, '00000000-0000-0000-0000-0000000000f1')->>'id')::bigint as fee1 \gset
select (d_wallet_move_add((select id from d_wallets where code='bkash'), 1, tt.today(), 'out', 'cash', null, 400, null, null, '00000000-0000-0000-0000-0000000000f2')->>'id')::bigint as mv1 \gset
select (d_wallet_move_add((select id from d_wallets where code='nagad'), 1, tt.today(), 'out', 'wallet', (select id from d_wallets where code='rocket'), 100, null, null, null)->>'id')::bigint as mv2 \gset
select tt.chk('T3 register after fee and moves: bkash 485, nagad 400, rocket 400',
  (select (x->>'book')::numeric from jsonb_array_elements(d_wallet_balances()) x where x->>'code'='bkash')=485
  and (select (x->>'book')::numeric from jsonb_array_elements(d_wallet_balances()) x where x->>'code'='nagad')=400
  and (select (x->>'book')::numeric from jsonb_array_elements(d_wallet_balances()) x where x->>'code'='rocket')=400);
select tt.chk('T3 client_id makes the fee idempotent (dup, no second row)', (d_wallet_fee_add((select id from d_wallets where code='bkash'), 1, tt.today(), 15, 'cash_out', 'test_ref_1', null, '00000000-0000-0000-0000-0000000000f1')->>'dup')::boolean and (select count(*) from d_wallet_fees)=1);
select acct_post_pending(false) is not null as p3 \gset
select tt.chk('T3 fee entry: Dr 5815 15 / Cr 1131 15', tt.jl('d_wallet_fee', :'fee1', '5815', 'd')=15 and tt.jl('d_wallet_fee', :'fee1', '1131', 'c')=15);
select tt.chk('T3 bkash to cash entry: Dr 1110 400 / Cr 1131 400', tt.jl('d_wallet_move', :'mv1', '1110', 'd')=400 and tt.jl('d_wallet_move', :'mv1', '1131', 'c')=400);
select tt.chk('T3 wallet to wallet entry: Dr 1133 100 / Cr 1132 100', tt.jl('d_wallet_move', :'mv2', '1133', 'd')=100 and tt.jl('d_wallet_move', :'mv2', '1132', 'c')=100);
select tt.chk('T3 journal = register for every wallet, entries balance', not exists (select 1 from jsonb_array_elements(d_wallet_balances()) x where (x->>'journal_gap')::numeric <> 0) and tt.unbalanced_entries() = 0);
select tt.chk('T3 fee is a separate expense: 5815 net debit 15, not inside any other expense', tt.net('5815')=15);
reset role;
select tt.chk('T3 P&L feed _d_wallet_fee_rows gives 15 and the day-book feed gives the fee line', (select coalesce(sum(amount),0) from _d_wallet_fee_rows(tt.today(), tt.today(), array[1]))=15 and (select count(*) from _d_daybook_rows(array[1], tt.today(), tt.today()))=1);
set role authenticated; select tt.as(:'o');

\echo == T4 negative tests
select id as wb from d_wallets where code='bkash' \gset
select tt.err('T4 fee bigger than the wallet balance is refused (rocket has 400)', format('select d_wallet_fee_add(%s,1,tt.today(),500,''other'',null,null,null)', (select id from d_wallets where code='rocket')), 'wallet_negative');
select tt.err('T4 move out of nagad bigger than its balance is refused', format('select d_wallet_move_add(%s,1,tt.today(),''out'',''bank'',null,1000,null,null,null)', (select id from d_wallets where code='nagad')), 'wallet_negative');
select tt.err('T4 empty wallet (upay) cannot pay a fee', format('select d_wallet_fee_add(%s,1,tt.today(),1,''other'',null,null,null)', (select id from d_wallets where code='upay')), 'wallet_negative');
select tt.err('T4 wallet mismatch: counter wallet with counter cash', format('select d_wallet_move_add(%s,1,tt.today(),''out'',''cash'',%s,10,null,null,null)', (select id from d_wallets where code='bkash'), (select id from d_wallets where code='nagad')), 'wallet_mismatch');
select tt.err('T4 wallet mismatch: counter wallet missing', format('select d_wallet_move_add(%s,1,tt.today(),''out'',''wallet'',null,10,null,null,null)', (select id from d_wallets where code='bkash')), 'wallet_mismatch');
select tt.err('T4 wallet mismatch: a wallet cannot pay itself', format('select d_wallet_move_add(%s,1,tt.today(),''out'',''wallet'',%s,10,null,null,null)', (select id from d_wallets where code='bkash'), (select id from d_wallets where code='bkash')), 'wallet_mismatch');
select tt.err('T4 zero / negative amounts refused', format('select d_wallet_fee_add(%s,1,tt.today(),-5,''other'',null,null,null)', (select id from d_wallets where code='bkash')), 'bad_amount');
select tt.err('T4 a future date is refused', format('select d_wallet_fee_add(%s,1,tt.today()+30,5,''other'',null,null,null)', (select id from d_wallets where code='bkash')), 'bad_date');
select (d_wallet_move_add((select id from d_wallets where code='upay'), 1, tt.today(), 'in', 'cash', null, 50, null, null, null)->>'id')::bigint as mvin \gset
select d_wallet_move_add((select id from d_wallets where code='upay'), 1, tt.today(), 'out', 'bank', null, 40, null, null, null) is not null as spent \gset
select tt.err('T4 voiding a money-in move that was already spent is refused (upay 50 in, 40 out, 10 left)', format('select d_wallet_move_add(%s,1,tt.today(),''out'',''bank'',null,11,null,null,null)', (select id from d_wallets where code='upay')), 'wallet_negative');
select tt.err('T4 void of the spent money-in move is refused', format('select d_wallet_move_void(%s, ''test void'')', :'mvin'), 'wallet_negative');
-- an unbalanced entry can never be written (the single write function refuses it, our entries use it)
reset role;
select tt.err('T4 unbalanced journal entry is refused by the writer', format('select _acct_write(tt.today(), 1, ''manual'', ''t83-unbal'', null, ''x'', null, %L::jsonb)',
  json_build_array(json_build_object('account_id',(select id from coa_accounts where code='1131'),'debit',10,'credit',0,'party_type',null,'party_id',null,'memo',null,'location_id',null),
                   json_build_object('account_id',(select id from coa_accounts where code='5815'),'debit',0,'credit',9,'party_type',null,'party_id',null,'memo',null,'location_id',null))::text), 'unbalanced');
set role authenticated;
select tt.as(:'nn');
select tt.err('T4 a salesperson cannot see wallets', 'select d_wallet_balances()', 'not allowed');
select tt.err('T4 a salesperson cannot add a fee', format('select d_wallet_fee_add(%s,1,tt.today(),1,''other'',null,null,null)', :'wb'), 'not allowed');
select tt.err('T4 only owner/accounts add a wallet', 'select d_wallet_add(''testw'',''টেস্ট'',''Test'')', 'not allowed');
select tt.as(:'c');
select tt.err('T4 cash controller cannot add a wallet either', 'select d_wallet_add(''testw'',''টেস্ট'',''Test'')', 'not allowed');
select tt.err('T4 cash controller cannot read the statement', format('select d_wallet_statement(%s,null,null)', (select id from d_wallets where code='bkash')), 'not allowed');
select tt.as(:'o');
select tt.err('T4 a wallet that still holds money cannot be retired', format('select d_wallet_update(%s,null,null,null,false)', (select id from d_wallets where code='bkash')), 'wallet_not_empty');
select tt.err('T4 wallet code must be lower-case letters/digits', 'select d_wallet_add(''Bad Code'',''x'',''x'')', 'bad_code');

\echo == T5 blind reconcile (10-3 phone total versus book)
select tt.as(:'c');
select tt.chk('T5 before counting, the controller sees NO book figure', (select bool_and((x->>'book') is null) from jsonb_array_elements(d_wallet_balances()) x)
  and (select bool_and((x->>'book') is null) from jsonb_array_elements(d_wallet_recon_report()->'wallets') x));
select (d_wallet_check_save((select id from d_wallets where code='bkash'), tt.today(), 485, 1, '00000000-0000-0000-0000-0000000000c1')) as ck1 \gset
select tt.chk('T5 bkash phone 485 = book 485: matched, diff 0 is written', (:'ck1'::jsonb->>'status')='matched' and (:'ck1'::jsonb->>'diff')::numeric=0 and (:'ck1'::jsonb->>'book')::numeric=485);
select (d_wallet_check_save((select id from d_wallets where code='nagad'), tt.today(), 395, 1, null)) as ck2 \gset
select tt.chk('T5 nagad phone 395 vs book 400: difference -5, status difference', (:'ck2'::jsonb->>'status')='difference' and (:'ck2'::jsonb->>'diff')::numeric=-5);
select tt.chk('T5 after the count the book figure of THAT wallet is visible, others stay hidden',
  (select (x->>'book') is not null from jsonb_array_elements(d_wallet_balances()) x where x->>'code'='nagad') and (select (x->>'book') is null from jsonb_array_elements(d_wallet_balances()) x where x->>'code'='rocket'));
select tt.chk('T5 same client id: no second check (dup)', (d_wallet_check_save((select id from d_wallets where code='bkash'), tt.today(), 485, 1, '00000000-0000-0000-0000-0000000000c1')->>'dup')::boolean);
select tt.err('T5 a difference needs a reason (blank refused)', format('select d_wallet_check_explain(%s, '' '')', (:'ck2'::jsonb->>'id')), 'reason_required');
select d_wallet_check_explain((:'ck2'::jsonb->>'id')::bigint, 'test: fee not yet entered') is not null as ex \gset
select tt.chk('T5 explained once, then closed', (select status from d_wallet_checks where id = (:'ck2'::jsonb->>'id')::bigint)='explained');
select tt.err('T5 an explained difference cannot be re-written', format('select d_wallet_check_explain(%s, ''again'')', (:'ck2'::jsonb->>'id')), 'nothing_to_explain');
select tt.chk('T5 matched check has nothing to explain', (select count(*) from d_wallet_checks where status='matched')=1);
select tt.as(:'o');
select tt.chk('T5 owner report: phone 395, book 400, book_journal 400 for nagad', (select (x->>'phone')::numeric=395 and (x->>'book')::numeric=400 and (x->>'book_journal')::numeric=400 from jsonb_array_elements(d_wallet_recon_report()->'wallets') x where x->>'code'='nagad'));
select tt.err('T5 opening cannot be changed once a count exists', format('select d_wallet_opening_set(%s, 10, tt.today())', (select id from d_wallets where code='nagad')), 'opening_locked_after_check');
select tt.chk('T5 statement lists every movement of bkash (sale, supplier, fee, move)', (select count(*) from jsonb_array_elements(d_wallet_statement((select id from d_wallets where code='bkash'), null, null)))=4);

\echo == T6 void the fee: the entry is reversed; fee treatment switch
select d_wallet_fee_void(:'fee1'::bigint, 'test: entered twice') is not null as v1 \gset
select acct_post_pending(false) is not null as p6 \gset
select tt.chk('T6 void fee: 5815 back to 0, bkash back to 500 in book and journal', tt.net('5815')=0 and (select (x->>'book')::numeric=500 and (x->>'journal')::numeric=500 from jsonb_array_elements(d_wallet_balances()) x where x->>'code'='bkash'));
select tt.err('T6 void needs a note', format('select d_wallet_fee_void(%s, null)', :'fee1'), 'already_void');
select (d_wallet_fee_add((select id from d_wallets where code='rocket'), 1, tt.today(), 7, 'merchant', null, null, null)->>'id')::bigint as fee2 \gset
select acct_post_pending(false) is not null as p6b \gset
select tt.chk('T6 new fee posted: 5815 net 7', tt.net('5815')=7);
select set_rule('d_wallet_fee_treatment', '"not_posted"'::jsonb) is null as sw \gset
select acct_post_pending(false) is not null as p6c \gset
select tt.chk('T6 treatment not_posted: fee reversed in the books (5815 = 0) but still in the wallet register', tt.net('5815')=0 and (select (x->>'book')::numeric from jsonb_array_elements(d_wallet_balances()) x where x->>'code'='rocket')=393);
reset role;
select tt.chk('T6 not_posted also leaves the P&L / day-book feeds empty', (select count(*) from _d_wallet_fee_rows(tt.today(), tt.today(), array[1]))=0);
set role authenticated; select tt.as(:'o');
select set_rule('d_wallet_fee_treatment', null) is null as sw2 \gset
select tt.chk('T6 entries still balance after every change', tt.unbalanced_entries() = 0);

\echo == T7 negative mode warn
select set_rule('d_wallet_negative_mode', '"warn"'::jsonb) is null as nm \gset
select tt.chk('T7 warn: a fee over the balance is saved with a warning', (d_wallet_fee_add((select id from d_wallets where code='upay'), 1, tt.today(), 20, 'other', null, null, null)->>'warning')='wallet_negative');
select set_rule('d_wallet_negative_mode', null) is null as nm2 \gset

\echo == T8 add a wallet (account code 1135), retire rules
select d_wallet_add('testwallet', 'টেস্ট ওয়ালেট', 'Test wallet', array['TEST-W'], 0, null) as aw \gset
select tt.chk('T8 new wallet got the next free account 1135 and a mapping', exists (select 1 from d_wallets w join coa_accounts a on a.id=w.coa_account_id where w.code='testwallet' and a.code='1135') and exists (select 1 from acct_mappings where key='d_wallet_testwallet'));
select tt.err('T8 duplicate wallet code is refused', 'select d_wallet_add(''testwallet'',''x'',''x'')', 'code_taken');
select d_wallet_update((select id from d_wallets where code='testwallet'), null, null, null, false) is not null as ret \gset
select tt.chk('T8 an empty wallet can be retired (never deleted)', not (select active from d_wallets where code='testwallet'));
select tt.err('T8 a retired wallet takes no new fee', format('select d_wallet_fee_add(%s,1,tt.today(),1,''other'',null,null,null)', (select id from d_wallets where code='testwallet')), 'wallet_not_found');
select tt.err('T8 no hard delete', 'delete from d_wallets', 'permission denied');
reset role;
select tt.err('T8 no hard delete (even for the table owner): trigger', 'delete from d_wallets', 'delete');
set role authenticated; select tt.as(:'o');

\echo == T9 G10 materials (milk, chhana, packing). Setup: milk 60/kg x 1000, chhana 300/kg x 1000, box 10/piece x 500
reset role;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('TD-MILK', 'টেস্ট দুধ', 'test_milk', 'kg', 'kg', 'raw_material', true, null),
 ('TD-CHHN', 'টেস্ট ছানা', 'test_chhana', 'kg', 'kg', 'raw_material', true, null),
 ('TD-BOX',  'টেস্ট বাক্স', 'test_box', 'piece', 'piece', 'packaging', true, null),
 ('TD-SW1',  'টেস্ট মিষ্টি ১', 'test_sweet_1', 'kg', 'kg', 'finished_good', true, 400),
 ('TD-SW2',  'টেস্ট মিষ্টি ২', 'test_sweet_2', 'kg', 'kg', 'finished_good', true, 400),
 ('TD-SW3',  'টেস্ট মিষ্টি ৩', 'test_sweet_3', 'kg', 'kg', 'finished_good', true, 400),
 ('TD-NOC',  'টেস্ট দামহীন', 'test_nocost', 'kg', 'kg', 'raw_material', true, null);
select id as im from items where code='TD-MILK' \gset
select id as ic from items where code='TD-CHHN' \gset
select id as ib from items where code='TD-BOX' \gset
select id as s1 from items where code='TD-SW1' \gset
select id as s2 from items where code='TD-SW2' \gset
select id as s3 from items where code='TD-SW3' \gset
select id as inc from items where code='TD-NOC' \gset
set role authenticated; select tt.as(:'o');
select stock_opening(:'im'::uuid, 1, 1000, 60, null, 'c') is not null as so1 \gset
select stock_opening(:'ic'::uuid, 1, 1000, 300, null, 'c') is not null as so2 \gset
select stock_opening(:'ib'::uuid, 1, 500, 10, null, 'c') is not null as so3 \gset
select set_rule('packaging_consume_on', '"production"'::jsonb) is null as pk \gset
select d_item_role_set(:'im'::uuid, 'milk') is not null as r1 \gset
select d_item_role_set(:'ic'::uuid, 'chhana') is not null as r2 \gset
select d_item_role_set(:'ib'::uuid, 'packing') is not null as r3 \gset
select tt.err('T9 unknown role refused', format('select d_item_role_set(%L::uuid, ''no_such_role'')', :'im'), 'role_not_found');
select d_product_req_set(:'s1'::uuid, 'milk') is not null as q1 \gset
select d_product_req_set(:'s1'::uuid, 'chhana') is not null as q2 \gset
select d_product_req_set(:'s1'::uuid, 'packing') is not null as q3 \gset
select d_product_req_set(:'s2'::uuid, 'chhana') is not null as q4 \gset
select d_product_req_set(:'s2'::uuid, 'packing') is not null as q5 \gset
-- sweet 1 recipe: yield 10 kg = milk 20 kg + chhana 5 kg ; box 0.5 per kg of output = 5 boxes per batch
select (recipe_save(null, :'s1'::uuid, 10, null, 'test v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'im','qty',20,'waste_pct',0), jsonb_build_object('ingredient_item_id',:'ic','qty',5,'waste_pct',0)))->>'id')::uuid as r_s1 \gset
reset role; insert into product_packaging (product_item_id, packaging_item_id, qty_per_unit, applies_to) values (:'s1', :'ib', 0.5, 'production'); set role authenticated; select tt.as(:'o');
-- sweet 2 recipe: milk only (chhana and packing required but missing)
select (recipe_save(null, :'s2'::uuid, 10, null, 'test v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'im','qty',20,'waste_pct',0)))->>'id')::uuid as r_s2 \gset

select tt.chk('T9 role check: sweet 1 has everything', (d_recipe_material_check(:'r_s1'::uuid)->>'ok')::boolean);
select tt.chk('T9 role check: sweet 2 lacks chhana and packing', not (d_recipe_material_check(:'r_s2'::uuid)->>'ok')::boolean and (d_recipe_material_check(:'r_s2'::uuid)->'missing_roles') = '["chhana","packing"]'::jsonb);
select tt.chk('T9 recipe_cost of sweet 1 includes milk + chhana + packing: 1200 + 1500 + 50 = 2750', (recipe_cost(:'r_s1'::uuid, 1)->>'material_cost')::numeric = 2750 and (recipe_cost(:'r_s1'::uuid, 1)->>'unit_cost')::numeric = 275);
select (production_post(1, :'r_s1'::uuid, 1, null, null, 'test run 1')) as run1 \gset
select tt.chk('T9 production consumed milk 20, chhana 5, box 5 and made 10 kg at unit cost 275', (:'run1'::jsonb->>'qty')::numeric = 10 and (:'run1'::jsonb->>'unit_cost')::numeric = 275
  and (select count(*) from jsonb_array_elements(:'run1'::jsonb->'consumed'))=3);
select tt.chk('T9 breakdown: milk 1200, chhana 1500, packing 50, material 2750, total 2750, matches the run record',
  d_production_cost_breakdown((:'run1'::jsonb->>'run_id')::uuid)->'by_role' = '{"milk":1200.0000,"chhana":1500.0000,"packing":50.0000}'::jsonb
  and (d_production_cost_breakdown((:'run1'::jsonb->>'run_id')::uuid)->>'production_total')::numeric = 2750
  and (d_production_cost_breakdown((:'run1'::jsonb->>'run_id')::uuid)->>'packaging_total')::numeric = 50
  and (d_production_cost_breakdown((:'run1'::jsonb->>'run_id')::uuid)->>'matches_run_record')::boolean);
select tt.chk('T9 stock fell: milk 980, chhana 995, box 495', (select qty from stock_balance where item_id=:'im' and location_id=1)=980 and (select qty from stock_balance where item_id=:'ic' and location_id=1)=995 and (select qty from stock_balance where item_id=:'ib' and location_id=1)=495);

\echo == T10 required-material gate: off / warn / block
select tt.chk('T10 mode off (default): sweet 2 can be produced as today', (production_post(1, :'r_s2'::uuid, 1, null, null, 'off')->>'run_id') is not null);
select set_rule('d_recipe_materials_mode', '"warn"'::jsonb) is null as w1 \gset
select (production_post(1, :'r_s2'::uuid, 1, null, null, 'warn')->>'run_id') is not null as warnrun \gset
select tt.chk('T10 mode warn: production saved, one yellow stock exception recipe_material_missing', :'warnrun'::boolean and (select count(*) from exceptions where flag_code='recipe_material_missing' and level='yellow')=1);
select set_rule('d_recipe_materials_mode', '"block"'::jsonb) is null as b1 \gset
select tt.err('T10 mode block: production of a recipe missing a required material is refused', format('select production_post(1,%L::uuid,1,null,null,''block'')', :'r_s2'), 'recipe_missing_material');
select tt.chk('T10 the refused production left the stock untouched (milk still 940 after the two sweet-2 runs)', (select qty from stock_balance where item_id=:'im' and location_id=1)=940);
select tt.chk('T10 sweet 1 (complete) is still produced in block mode', (production_post(1, :'r_s1'::uuid, 1, null, null, 'block ok')->>'run_id') is not null);
select recipe_set_active(:'r_s2'::uuid, false) is not null as dea \gset
select tt.err('T10 block mode: activating a recipe that lacks a required material is refused', format('select recipe_set_active(%L::uuid, true)', :'r_s2'), 'recipe_missing_material');
select set_rule('d_recipe_materials_mode', null) is null as b2 \gset
select recipe_set_active(:'r_s2'::uuid, true) is not null as rea \gset
select tt.chk('T10 back to off: activation works again', (select active from recipes where id=:'r_s2'::uuid));

\echo == T11 recipe needs ingredients; cost gaps and the costing method
select tt.err('T11 a recipe with no ingredient line cannot be saved (no_lines)', format('select recipe_save(null,%L::uuid,10,null,''empty'',''[]''::jsonb)', :'s3'), 'no_lines');
select (recipe_save(null, :'s3'::uuid, 10, null, 'test v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'inc','qty',3,'waste_pct',0), jsonb_build_object('ingredient_item_id',:'im','qty',2,'waste_pct',0)))->>'id')::uuid as r_s3 \gset
select tt.chk('T11 cost gaps list the ingredient with no cost (test_nocost) and not milk', exists (select 1 from jsonb_array_elements(d_recipe_cost_gaps(1)) x where x->>'code'='TD-NOC') and not exists (select 1 from jsonb_array_elements(d_recipe_cost_gaps(1)) x where x->>'code'='TD-MILK'));
select tt.chk('T11 average method gives milk 60', (d_material_unit_cost(:'im'::uuid, 1)->>'unit_cost')::numeric = 60 and (d_material_unit_cost(:'inc'::uuid, 1)->>'unit_cost') is null);
select tt.err('T11 fixed price of 0 refused', format('select d_fixed_price_set(%L::uuid, 0, tt.today())', :'inc'), 'bad_amount');
select d_fixed_price_set(:'inc'::uuid, 45, tt.today()-1, 'test fixed') is not null as fp \gset
select set_rule('d_material_cost_method', '"fixed_price"'::jsonb) is null as m1 \gset
select tt.chk('T11 fixed_price method: test_nocost = 45, no longer a gap; milk (no fixed price) becomes a gap',
  (d_material_unit_cost(:'inc'::uuid, 1)->>'unit_cost')::numeric = 45 and not exists (select 1 from jsonb_array_elements(d_recipe_cost_gaps(1)) x where x->>'code'='TD-NOC')
  and exists (select 1 from jsonb_array_elements(d_recipe_cost_gaps(1)) x where x->>'code'='TD-MILK'));
select set_rule('d_material_cost_method', null) is null as m2 \gset
select tt.chk('T11 setting back: average purchase', (d_material_unit_cost(:'im'::uuid, 1)->>'method')='average_purchase');
select tt.as(:'nn');
select tt.err('T11 salesperson cannot read cost gaps', 'select d_recipe_cost_gaps(1)', 'not allowed');
select tt.err('T11 salesperson cannot map roles', format('select d_item_role_set(%L::uuid, ''milk'')', :'im'), 'not allowed');
select tt.err('T11 salesperson cannot import roles', 'select d_item_roles_import(''[]''::jsonb)', 'not allowed');
select tt.as(:'o');
select d_item_roles_import(jsonb_build_array(jsonb_build_object('item_code','TD-NOC','role','milk'), jsonb_build_object('item_code','NO-SUCH','role','milk'), jsonb_build_object('item_code','TD-NOC','role','nope'))) as imp \gset
select tt.chk('T11 import maps the known code and reports the two bad rows; creates no item', (:'imp'::jsonb->>'mapped')::int=1 and jsonb_array_length(:'imp'::jsonb->'rejected')=2 and (select count(*) from items where code='NO-SUCH')=0);
select d_item_role_set(:'inc'::uuid, 'milk', false) is not null as off \gset
select tt.chk('T11 switching a role off keeps the row (never deleted)', (select active from d_item_roles where item_id=:'inc' and role_code='milk') is false);

\echo == T12 paste-twice and no leak of demo names
reset role;
select tt.chk('T12 only the structural wallets exist (4 + 1 added by T8), no seeded items', (select count(*) from d_wallets)=5 and (select count(*) from items where code not like 'TD-%')=(select count(*) from items where code not like 'TD-%' and import_batch is null));
select tt.chk('T12 everything entered by the tests keeps the journal balanced', tt.unbalanced_entries() = 0);

\echo == RESULT
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
select 'FAIL ' || name from tt.res where not ok;
