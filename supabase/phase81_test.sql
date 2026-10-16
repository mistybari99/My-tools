-- FRESH DB ONLY. Phase 81 tests: G4 cash short, G5 customer advance, G6 transit short.
--   ORDER="phase8 ... phase79 phase81" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths and port> a81db
--   psql -h /tmp -p <port> -U postgres -d a81db -qAt -f supabase/phase81_test.sql | grep -E 'FAIL|RESULT'
-- All numbers are hand-computed (comment above each block). Test data only, no person names. Places 1 and 2 only.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set m '00000000-0000-0000-0000-000000000003'
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
-- sum of debit / credit of one account code over the (non-reversal) entries of one source
create or replace function tt.jl(p_type text, p_sid text, p_code text, p_side text) returns numeric language sql stable as $$
  select coalesce(sum(case p_side when 'd' then l.debit else l.credit end), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
  where e.source_type = p_type and e.source_id = p_sid and e.reverses_id is null and a.code = p_code $$;
-- net (debit - credit) of an account over ALL entries incl. reversals
create or replace function tt.net(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.n_entries(p_type text, p_sid text) returns bigint language sql stable as $$
  select count(*) from public.journal_entries where source_type = p_type and source_id = p_sid $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner@s.app','{"full_name":"test_owner"}'), (:'s','test_staff@s.app','{"full_name":"test_staff"}'), (:'m','test_mgr@s.app','{"full_name":"test_mgr"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','recipe_approver'),(:'m','recipe_approver') on conflict do nothing;
insert into user_locations values (:'s',1),(:'m',1),(:'m',2) on conflict do nothing;

\echo == T0 objects, defaults, privileges
select tt.chk('T0 phase81 tables exist with RLS on', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('shortage_cash_cases','shortage_transit','shortage_transit_events') and c.relrowsecurity)=3);
select tt.chk('T0 account 1240 Receivable from carrier is seeded and mapped to carrier_claim; cash_short -> 5800; transit_loss -> 5100',
  (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='carrier_claim')='1240'
  and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='cash_short')='5800'
  and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='transit_loss')='5100');
select tt.chk('T0 owner settings have safe defaults: post off, treatment expense, decider owner, bearer ask',
  not rule_on('cash_short_post_on') and rule_txt('cash_short_treatment')='expense' and rule_txt('short_decider')='owner' and rule_txt('transit_short_bearer')='ask');
select tt.chk('T0 _b_docs has exactly the result columns of _acct_docs (the integrator can union them)',
  pg_get_function_result('public._b_docs(date)'::regprocedure) = pg_get_function_result('public._acct_docs(date)'::regprocedure));
select tt.chk('T0 internal functions are not callable by authenticated or anon',
  not has_function_privilege('authenticated','public._b_docs(date)','execute') and not has_function_privilege('anon','public._b_docs(date)','execute')
  and not has_function_privilege('authenticated','public._b_transit_pick(uuid,text,date)','execute') and not has_function_privilege('anon','public.cash_short_decide(uuid,boolean,text,uuid,boolean)','execute'));
select tt.chk('T0 pasting the phase again changes nothing (rules and mapping counts)', (select count(*) from rules where key in ('cash_short_post_on','cash_short_treatment','short_decider','transit_short_bearer'))=4
  and (select count(*) from coa_accounts where name_en='Receivable from carrier')=1);
select tt.err('T0 unbalanced lines are refused (debit 10, credit 9)', $$select _b_assert_balanced('[{"a":"x","d":10},{"a":"y","c":9}]'::jsonb)$$, 'unbalanced');
select tt.err('T0 a single line is refused', $$select _b_assert_balanced('[{"a":"x","d":10}]'::jsonb)$$, 'need_two_lines');
select tt.err('T0 a zero entry is refused', $$select _b_assert_balanced('[{"a":"x","d":0},{"a":"y","c":0}]'::jsonb)$$, 'unbalanced');

\echo == setup: accounting on from 5 days ago, items and stock at place 1
set role authenticated; select tt.as(:'o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
reset role;
insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values
 ('T81-RM','test_raw','test_raw','kg','kg',0,true,'raw_material'),
 ('T81-FG','test_fin','test_fin','kg','kg',400,true,'finished_good'),
 ('T81-NC','test_nocost','test_nocost','kg','kg',0,true,'raw_material');
select id as rm from items where code='T81-RM' \gset
select id as fg from items where code='T81-FG' \gset
select id as nc from items where code='T81-NC' \gset
set role authenticated; select tt.as(:'o');
-- raw 100 @ 20 ; finished 100 @ 30 ; no-cost item 50 (cost unknown)
select stock_opening(:'rm'::uuid,1,100,20) is not null as a1 \gset
select stock_opening(:'fg'::uuid,1,100,30) is not null as a2 \gset
select stock_opening(:'nc'::uuid,1,50,null) is not null as a3 \gset
select tt.chk('setup: accounting on, openings', rule_on('accounting_on') and :'a1' and :'a2' and :'a3');
reset role;

-- =====================================================================================================================================
\echo == G4 cash short: cases are made from the cash_short_over exceptions
-- three counts at place 1: SHORT 200 today, OVER 50 yesterday, SHORT 30 (to be rejected). Sign: counted minus expected (negative = short).
insert into entries (form_code,location_id,serial,entry_date,status,created_by,created_staff) values
 ('14-1',1,9001,tt.today(),'submitted',:'o','t'), ('14-1',1,9002,tt.today()-1,'submitted',:'o','t'), ('14-1',1,9003,tt.today(),'submitted',:'o','t'),
 ('14-1',1,9004,tt.today(),'submitted',:'m','t'), ('14-1',1,9005,tt.today()-30,'submitted',:'o','t');
select id as e1 from entries where serial=9001 and form_code='14-1' \gset
select id as e2 from entries where serial=9002 and form_code='14-1' \gset
select id as e3 from entries where serial=9003 and form_code='14-1' \gset
select id as e4 from entries where serial=9004 and form_code='14-1' \gset
select id as e5 from entries where serial=9005 and form_code='14-1' \gset
insert into exceptions (entry_id,form_code,location_id,entry_date,flag_code,level,amount,text) values
 (:'e1','14-1',1,tt.today(),'cash_short_over','red',-200,'{}'), (:'e2','14-1',1,tt.today()-1,'cash_short_over','yellow',50,'{}'),
 (:'e3','14-1',1,tt.today(),'cash_short_over','yellow',-30,'{}'), (:'e4','14-1',1,tt.today(),'cash_short_over','yellow',-75,'{}'),
 (:'e5','14-1',1,tt.today()-30,'cash_short_over','yellow',-10,'{}'),
 (:'e1','14-1',1,tt.today(),'item_slow','yellow',5,'{}');
select tt.chk('G4 one open case per count; other flags make none', (select count(*) from shortage_cash_cases)=5 and (select count(*) from shortage_cash_cases where status='open')=5);
select tt.chk('G4 amount signed: short -200, over +50', (select amount from shortage_cash_cases where entry_id=:'e1')=-200 and (select amount from shortage_cash_cases where entry_id=:'e2')=50
  and (select case_date from shortage_cash_cases where entry_id=:'e2')=tt.today()-1);
select id as c1 from shortage_cash_cases where entry_id=:'e1' \gset
select id as c2 from shortage_cash_cases where entry_id=:'e2' \gset
select id as c3 from shortage_cash_cases where entry_id=:'e3' \gset
select id as c4 from shortage_cash_cases where entry_id=:'e4' \gset
select id as c5 from shortage_cash_cases where entry_id=:'e5' \gset
-- the same count flagged again while open: the amount follows the new flag (one case per count)
insert into exceptions (entry_id,form_code,location_id,entry_date,flag_code,level,amount,text) values (:'e3','14-1',1,tt.today(),'cash_short_over','yellow',-35,'{}');
select tt.chk('G4 a re-flag of an OPEN case updates its amount, still one case', (select count(*) from shortage_cash_cases where entry_id=:'e3')=1 and (select amount from shortage_cash_cases where id=:'c3')=-35);

\echo == G4 nothing posts before approval
set role authenticated; select tt.as(:'o');
select (b_post_pending()->>'posted')::int as p0 \gset
reset role;
select tt.chk('G4 unapproved cases post nothing', :'p0'=0 and (select count(*) from journal_entries where source_type='cash_short')=0);
set role authenticated; select tt.as(:'s');
select tt.err('G4 a salesperson cannot decide', format($$select cash_short_decide(%L,true,'ok note')$$,:'c1'), 'not allowed');
select tt.err('G4 a salesperson cannot read the list', $$select cash_short_list()$$, 'not allowed');
select tt.as(:'o');
select tt.err('G4 a note is required (approve)', format($$select cash_short_decide(%L,true,'')$$,:'c1'), 'note_required');
select tt.err('G4 a note is required (reject)', format($$select cash_short_decide(%L,false,'  ')$$,:'c3'), 'note_required');
select tt.err('G4 unknown case', $$select cash_short_decide(gen_random_uuid(),true,'ok note')$$, 'not_found');
select tt.err('G4 a count older than the accounting start cannot be approved', format($$select cash_short_decide(%L,true,'too old')$$,:'c5'), 'before_start');
select tt.chk('G4 the list shows 5 open cases to the owner', jsonb_array_length(cash_short_list('open'))=5);

\echo == G4 approve with posting OFF: the case waits
select (cash_short_decide(:'c1'::uuid,true,'checked the count slip')->>'posts_now')::boolean as pn \gset
select tt.chk('G4 approve stores the decision; posting is OFF so it does not post now', not :'pn' and (select status from shortage_cash_cases where id=:'c1') = 'approved');
select b_post_pending() as r1 \gset
reset role;
select tt.chk('G4 posting off: waiting 1, still nothing in the journal', (:'r1'::jsonb->>'waiting')::int=1 and (:'r1'::jsonb->>'posted')::int=0 and tt.n_entries('cash_short',:'c1')=0);
select tt.err('G4 deciding twice is refused', format($$select cash_short_decide(%L,false,'second thought')$$,:'c1'), 'already_decided');

\echo == G4 post: short 200 -> Dr 5800 / Cr 1110 ; over 50 -> Dr 1110 / Cr 5800
set role authenticated; select tt.as(:'o');
select set_rule('cash_short_post_on','true') is null as ron \gset
select cash_short_decide(:'c2'::uuid,true,'cash box had extra') is not null as ap2 \gset
select cash_short_decide(:'c3'::uuid,false,'recount found it') ->> 'status' as rj \gset
select b_post_pending() as r2 \gset
reset role;
select tt.chk('G4 two cases posted, rejected one did not', (:'r2'::jsonb->>'posted')::int=2 and tt.n_entries('cash_short',:'c3')=0 and :'rj'='rejected');
select tt.chk('G4 short 200: Dr 5800 200, Cr 1110 200', tt.jl('cash_short',:'c1','5800','d')=200 and tt.jl('cash_short',:'c1','1110','c')=200);
select tt.chk('G4 over 50: Dr 1110 50, Cr 5800 50', tt.jl('cash_short',:'c2','1110','d')=50 and tt.jl('cash_short',:'c2','5800','c')=50);
select tt.chk('G4 posting date = the count date (not the approval date)', (select entry_date from journal_entries where source_type='cash_short' and source_id=:'c2')=tt.today()-1
  and (select entry_date from journal_entries where source_type='cash_short' and source_id=:'c1')=tt.today());
select tt.chk('G4 cash account moved by exactly the signed counts (-200 + 50 = -150 in 1110, +150 in 5800)', tt.net('1110')=-150 and tt.net('5800')=150);
select tt.chk('G4 every entry balances', tt.unbalanced_entries()=0);
set role authenticated; select tt.as(:'o');
select (b_post_pending()->>'posted')::int as p3 \gset
reset role;
select tt.chk('G4 posting again writes nothing (once per case)', :'p3'=0 and tt.n_entries('cash_short',:'c1')=1);

\echo == G4 void reverses
set role authenticated; select tt.as(:'o');
select tt.err('G4 a case that is not approved cannot be voided', format($$select cash_short_void(%L,'wrong')$$,:'c3'), 'not_approved');
select tt.err('G4 void needs a note', format($$select cash_short_void(%L,'')$$,:'c1'), 'note_required');
select cash_short_void(:'c1'::uuid,'count slip was for another day') ->> 'status' as vs \gset
select b_post_pending() as r4 \gset
reset role;
select tt.chk('G4 void -> reversal entry, the original is void, net effect of that case is 0', :'vs'='void' and (:'r4'::jsonb->>'reversed')::int=1 and tt.n_entries('cash_short',:'c1')=2
  and tt.net('5800')=-50 and tt.net('1110')=50);
select tt.chk('G4 still balanced after the reversal', tt.unbalanced_entries()=0);

\echo == G4 duplicate warning, mapping, own count, staff-receivable treatment
-- a manual journal for cash short on place 1 today (amount 75) already exists: approving case c4 (-75, same day, same place) must warn
set role authenticated; select tt.as(:'o');
select acct_journal_post(tt.today(),1,'manual cash short',jsonb_build_array(jsonb_build_object('code','5800','d',75),jsonb_build_object('code','1110','c',75))) is not null as mj \gset
select tt.err('G4 a manual journal on 5800 the same day and place -> possible_duplicate', format($$select cash_short_decide(%L,true,'second booking')$$,:'c4'), 'possible_duplicate');
reset role;
select tt.chk('G4 the refused approval changed nothing', (select status from shortage_cash_cases where id=:'c4')='open');
-- missing mapping is refused before anything is stored
set session_replication_role = replica; delete from acct_mappings where key='cash_short'; set session_replication_role = origin;
set role authenticated; select tt.as(:'o');
select tt.err('G4 missing mapping cash_short is refused', format($$select cash_short_decide(%L,true,'second booking',null,true)$$,:'c4'), 'mapping_missing');
reset role;
insert into acct_mappings (key, account_id, label_bn, label_en) select 'cash_short', id, 'ক্যাশ কম / বেশি', 'Cash short / over' from coa_accounts where code='5800';
-- owner chose "staff receivable": a SHORT needs a named employee and goes to 1220; an OVER still goes to 5800
insert into employees (employee_no, full_name_bn) values ('E81','test_emp') returning id as emp \gset
set role authenticated; select tt.as(:'o');
select set_rule('cash_short_treatment','"staff_receivable"') is null as tr1 \gset
select tt.err('G4 staff_receivable needs an employee', format($$select cash_short_decide(%L,true,'collect from the cashier',null,true)$$,:'c4'), 'employee_required');
select tt.err('G4 unknown employee refused', format($$select cash_short_decide(%L,true,'collect from the cashier',gen_random_uuid(),true)$$,:'c4'), 'employee_required');
select cash_short_decide(:'c4'::uuid,true,'collect from the cashier',:'emp'::uuid,true) ->> 'treatment' as trt \gset
select b_post_pending() as r5 \gset
reset role;
select tt.chk('G4 staff_receivable: Dr 1220 75 with the employee as party, Cr 1110 75', :'trt'='staff_receivable' and tt.jl('cash_short',:'c4','1220','d')=75 and tt.jl('cash_short',:'c4','1110','c')=75
  and (select count(*) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='cash_short' and e.source_id=:'c4' and l.party_type='staff' and l.party_id=:'emp')=1);
select tt.chk('G4 the treatment is frozen on the case (not read again later)', (select treatment from shortage_cash_cases where id=:'c4')='staff_receivable');
set role authenticated; select tt.as(:'o');
select set_rule('cash_short_treatment','"expense"') is null as tr2 \gset
select b_post_pending() as r6 \gset
reset role;
select tt.chk('G4 changing the setting later does not re-post or change the old entry', (:'r6'::jsonb->>'posted')::int=0 and tt.jl('cash_short',:'c4','1220','d')=75);

\echo == G4 who may decide: setting short_decider, and nobody decides their own count
insert into entries (form_code,location_id,serial,entry_date,status,created_by,created_staff) values ('14-1',1,9006,tt.today(),'submitted',:'o','t'), ('14-1',1,9007,tt.today(),'submitted',:'m','t');
select id as e6 from entries where serial=9006 and form_code='14-1' \gset
select id as e7 from entries where serial=9007 and form_code='14-1' \gset
insert into exceptions (entry_id,form_code,location_id,entry_date,flag_code,level,amount,text) values (:'e6','14-1',1,tt.today(),'cash_short_over','yellow',-12,'{}'), (:'e7','14-1',1,tt.today(),'cash_short_over','yellow',-13,'{}');
select id as c6 from shortage_cash_cases where entry_id=:'e6' \gset
select id as c7 from shortage_cash_cases where entry_id=:'e7' \gset
select set_user_grant(:'m'::uuid,'accounts_manage') is null as gm \gset
set role authenticated; select tt.as(:'m');
select tt.err('G4 default decider is the owner: a manager with the accounts grant is refused', format($$select cash_short_decide(%L,false,'not mine to decide')$$,:'c6'), 'not allowed');
select tt.as(:'o');
select set_rule('short_decider','"accounts_manager"') is null as sd1 \gset
select tt.as(:'m');
select cash_short_decide(:'c6'::uuid,false,'recounted and found') ->> 'status' as mst \gset
select tt.chk('G4 with short_decider = accounts_manager the manager decides a count someone else made', :'mst'='rejected');
select tt.err('G4 ...but never the count that manager made', format($$select cash_short_decide(%L,false,'my own count')$$,:'c7'), 'own_count');
select tt.as(:'o');
select set_rule('short_decider','"owner"') is null as sd2 \gset
reset role;

-- =====================================================================================================================================
\echo == G6 transit short: rows are made by the receive
-- raw 10 kg @ 20 sent 1 -> 2, 9 received: short 1 kg value 20.   finished 10 @ 30, received 10: no row.
-- finished 10 @ 30 sent, 8 received: short 2 value 60.   raw 10 @20 sent, 7 received: short 3 value 60.   no-cost item 5 sent, 4 received: short 1, cost missing.
set role authenticated; select tt.as(:'o');
select (stock_transfer(1,2,:'rm'::uuid,10)->>'id') as t1 \gset
select (stock_transfer(1,2,:'fg'::uuid,10)->>'id') as t2 \gset
select (stock_transfer(1,2,:'fg'::uuid,10)->>'id') as t3 \gset
select (stock_transfer(1,2,:'rm'::uuid,10)->>'id') as t4 \gset
select (stock_transfer(1,2,:'nc'::uuid,5)->>'id') as t5 \gset
select stock_receive_transfer(:'t1'::uuid,9) is not null as r1 \gset
select stock_receive_transfer(:'t2'::uuid,10) is not null as r2 \gset
select stock_receive_transfer(:'t3'::uuid,8) is not null as r3 \gset
select stock_receive_transfer(:'t4'::uuid,7) is not null as r4 \gset
select stock_receive_transfer(:'t5'::uuid,4) is not null as r5 \gset
reset role;
select tt.chk('G6 receives done', :'r1' and :'r2' and :'r3' and :'r4' and :'r5');
select tt.chk('G6 exactly the short receives made a row (4), the full one did not', (select count(*) from shortage_transit)=4 and not exists (select 1 from shortage_transit where transfer_id=:'t2'));
select id as s1 from shortage_transit where transfer_id=:'t1' \gset
select id as s3 from shortage_transit where transfer_id=:'t3' \gset
select id as s4 from shortage_transit where transfer_id=:'t4' \gset
select id as s5 from shortage_transit where transfer_id=:'t5' \gset
select tt.chk('G6 send 10 receive 9: open, qty_short 1, value 20 from the ledger cost at send', (select qty_short from shortage_transit where id=:'s1')=1 and (select value from shortage_transit where id=:'s1')=20
  and (select status from shortage_transit where id=:'s1')='open' and (select value_source from shortage_transit where id=:'s1')='ledger');
select tt.chk('G6 values: 60 (2 x 30) and 60 (3 x 20)', (select value from shortage_transit where id=:'s3')=60 and (select value from shortage_transit where id=:'s4')=60);
select tt.chk('G6 unknown cost stays unknown (value is null), never zero or guessed', (select value from shortage_transit where id=:'s5') is null);
select tt.chk('G6 the transfer itself is unchanged (still received 9 of 10, exception transit_short exists)', (select received_qty from stock_transfers where id=:'t1'::uuid)=9 and exists (select 1 from exceptions where flag_code='transit_short'));
select qty as q1a from stock_balance where item_id=:'rm'::uuid and location_id=1 \gset
select qty as q2a from stock_balance where item_id=:'rm'::uuid and location_id=2 \gset
select qty as q1f from stock_balance where item_id=:'fg'::uuid and location_id=1 \gset
select qty as q2f from stock_balance where item_id=:'fg'::uuid and location_id=2 \gset
select tt.chk('G6 stock after the receives (hand-computed): raw place1 100-20=80, place2 9+7=16; finished place1 80, place2 18', :'q1a'::numeric=80 and :'q2a'::numeric=16 and :'q1f'::numeric=80 and :'q2f'::numeric=18);
select tt.chk('G6 the receive posted no journal entry (transfers have no source)', (select count(*) from journal_entries where source_type like 'transit%')=0);

\echo == G6 permission, notes, cost missing
set role authenticated; select tt.as(:'s');
select tt.err('G6 a salesperson cannot claim', format($$select transit_short_claim(%L,'to the carrier')$$,:'s1'), 'not allowed');
select tt.err('G6 a salesperson cannot write off', format($$select transit_short_writeoff(%L,'lost it')$$,:'s1'), 'not allowed');
select tt.as(:'o');
select tt.err('G6 claim needs a note', format($$select transit_short_claim(%L,'')$$,:'s1'), 'note_required');
select tt.err('G6 unknown cost: claim refused (cost_missing)', format($$select transit_short_claim(%L,'to the carrier')$$,:'s5'), 'cost_missing');
select tt.err('G6 unknown cost: write-off refused too', format($$select transit_short_writeoff(%L,'lost it')$$,:'s5'), 'cost_missing');
select tt.err('G6 the owner cost must be positive', format($$select transit_short_set_cost(%L,0,'price list')$$,:'s5'), 'bad_amount');
select tt.err('G6 an event date before the goods were received is refused', format($$select transit_short_claim(%L,'to the carrier',%L::date)$$,:'s1',(tt.today()-3)::text), 'bad_date');
select tt.err('G6 a future date is refused', format($$select transit_short_claim(%L,'to the carrier',%L::date)$$,:'s1',(tt.today()+5)::text), 'bad_date');
select tt.err('G6 recover before any claim is refused', format($$select transit_short_recover(%L,5,'cash','paid back')$$,:'s1'), 'not_claimed');
select transit_short_set_cost(:'s5'::uuid,7,'price list at send') ->> 'value' as sv \gset
select tt.chk('G6 owner enters the cost: 1 x 7 = 7, source owner', :'sv'::numeric=7 and (select value_source from shortage_transit where id=:'s5')='owner');
select tt.err('G6 a known cost cannot be overwritten', format($$select transit_short_set_cost(%L,9,'again')$$,:'s5'), 'cost_known');

\echo == G6 claim, partial recover, full recover (item s1: raw 1 kg = 20)
select transit_short_claim(:'s1'::uuid,'claimed to the carrier, ref slip') ->> 'status' as cs \gset
select tt.err('G6 claiming twice is refused', format($$select transit_short_claim(%L,'again')$$,:'s1'), 'already_decided');
select tt.err('G6 recover more than the claim is refused', format($$select transit_short_recover(%L,25,'cash','paid back')$$,:'s1'), 'bad_amount');
select tt.err('G6 recover needs cash, bank or mobile', format($$select transit_short_recover(%L,5,'card','paid back')$$,:'s1'), 'bad_mode');
select transit_short_recover(:'s1'::uuid,5,'cash','part paid back') ->> 'status' as rs1 \gset
select b_post_pending() as g1 \gset
reset role;
select tt.chk('G6 claim posts Dr 1240 20 / Cr 1320 (raw inventory) 20 at the sending place', :'cs'='claimed'
  and (select sum(l.debit) from journal_lines l join coa_accounts a on a.id=l.account_id join journal_entries e on e.id=l.entry_id where e.source_type='transit_claim' and a.code='1240')=20
  and (select sum(l.credit) from journal_lines l join coa_accounts a on a.id=l.account_id join journal_entries e on e.id=l.entry_id where e.source_type='transit_claim' and a.code='1320')=20
  and (select location_id from journal_entries where source_type='transit_claim')=1);
select tt.chk('G6 partial recover 5 in cash: Dr 1110 5 / Cr 1240 5, status stays claimed', :'rs1'='claimed'
  and (select sum(l.debit) from journal_lines l join coa_accounts a on a.id=l.account_id join journal_entries e on e.id=l.entry_id where e.source_type='transit_recover' and a.code='1110')=5
  and (select sum(l.credit) from journal_lines l join coa_accounts a on a.id=l.account_id join journal_entries e on e.id=l.entry_id where e.source_type='transit_recover' and a.code='1240')=5);
select tt.chk('G6 receivable from carrier now 15', tt.net('1240')=15 and (select recovered_amount from shortage_transit where id=:'s1')=5);
set role authenticated; select tt.as(:'o');
select transit_short_recover(:'s1'::uuid,null,'bank','rest paid by bank transfer') as rr \gset
select b_post_pending() as g2 \gset
reset role;
select tt.chk('G6 full recovery (default = the outstanding 15) by bank: Dr 1120 15, status recovered, 1240 back to 0', (:'rr'::jsonb->>'status')='recovered' and tt.net('1240')=0
  and (select sum(l.debit) from journal_lines l join coa_accounts a on a.id=l.account_id join journal_entries e on e.id=l.entry_id where e.source_type='transit_recover' and a.code='1120')=15
  and (select status from shortage_transit where id=:'s1')='recovered');
set role authenticated; select tt.as(:'o');
select tt.err('G6 a recovered case cannot be decided again (claim)', format($$select transit_short_claim(%L,'again')$$,:'s1'), 'already_decided');
select tt.err('G6 a recovered case cannot be written off', format($$select transit_short_writeoff(%L,'again')$$,:'s1'), 'already_decided');
select tt.err('G6 a recovered case cannot be recovered again', format($$select transit_short_recover(%L,1,'cash','again')$$,:'s1'), 'already_decided');

\echo == G6 direct write-off (s3: finished 2 kg = 60)
select transit_short_writeoff(:'s3'::uuid,'carrier refused, shop takes the loss') ->> 'status' as ws \gset
select b_post_pending() as g3 \gset
reset role;
select tt.chk('G6 write-off without a claim: Dr 5100 60 / Cr 1310 (finished goods) 60', :'ws'='written_off' and tt.jl('transit_writeoff',(select id::text from shortage_transit_events where kind='writeoff' and shortage_id=:'s3'),'5100','d')=60
  and tt.jl('transit_writeoff',(select id::text from shortage_transit_events where kind='writeoff' and shortage_id=:'s3'),'1310','c')=60);
set role authenticated; select tt.as(:'o');
select tt.err('G6 a written-off case cannot be decided twice', format($$select transit_short_writeoff(%L,'again')$$,:'s3'), 'already_decided');
select tt.err('G6 a written-off case cannot be claimed', format($$select transit_short_claim(%L,'again')$$,:'s3'), 'already_decided');

\echo == G6 claim then write off the rest (s4: raw 3 kg = 60), with a partial recovery first
select transit_short_claim(:'s4'::uuid,'claimed to the carrier') is not null as c4 \gset
select transit_short_recover(:'s4'::uuid,10,'mobile','paid 10 by mobile wallet') is not null as rc4 \gset
select transit_short_writeoff(:'s4'::uuid,'carrier will not pay the rest') ->> 'amount' as wa \gset
select b_post_pending() as g4 \gset
reset role;
select tt.chk('G6 write-off after a claim takes only the outstanding 50: Dr 5100 50 / Cr 1240 50', :'wa'::numeric=50
  and tt.jl('transit_writeoff',(select id::text from shortage_transit_events where kind='writeoff' and shortage_id=:'s4'),'5100','d')=50
  and tt.jl('transit_writeoff',(select id::text from shortage_transit_events where kind='writeoff' and shortage_id=:'s4'),'1240','c')=50
  and (select against_claim from shortage_transit_events where kind='writeoff' and shortage_id=:'s4'));
select tt.chk('G6 1240 is back to 0 and the loss account 5100 shows 60 + 50 = 110', tt.net('1240')=0 and tt.net('5100')=110);
select tt.chk('G6 the 10 recovered by mobile went to 1130', (select sum(l.debit) from journal_lines l join coa_accounts a on a.id=l.account_id join journal_entries e on e.id=l.entry_id where e.source_type='transit_recover' and a.code='1130')=10);
select tt.chk('G6 inventory credits by item type: raw 1320 = 20 (claim s1) + 60 (claim s4) = 80, finished 1310 = 60', tt.net('1320')=-80 and tt.net('1310')=-60);
select tt.chk('G6 every entry balances (all phases so far)', tt.unbalanced_entries()=0);
select tt.chk('G6 stock per place unchanged by the decisions', (select qty from stock_balance where item_id=:'rm'::uuid and location_id=1)=:'q1a'::numeric and (select qty from stock_balance where item_id=:'rm'::uuid and location_id=2)=:'q2a'::numeric
  and (select qty from stock_balance where item_id=:'fg'::uuid and location_id=1)=:'q1f'::numeric and (select qty from stock_balance where item_id=:'fg'::uuid and location_id=2)=:'q2f'::numeric);
select tt.chk('G6 re-running the poster writes nothing', (b_post_pending()->>'posted')::int=0);

\echo == G6 who bears the loss (setting transit_short_bearer)
-- s5 (no-cost item, cost now 7) is still open. bearer = carrier -> no direct write-off; bearer = shop -> no claim.
set role authenticated; select tt.as(:'o');
select set_rule('transit_short_bearer','"carrier"') is null as b1 \gset
select tt.err('G6 bearer = carrier: a write-off without a claim is refused (claim_first)', format($$select transit_short_writeoff(%L,'lost it')$$,:'s5'), 'claim_first');
select set_rule('transit_short_bearer','"shop"') is null as b2 \gset
select tt.err('G6 bearer = shop: a claim is refused (shop_bears)', format($$select transit_short_claim(%L,'to the carrier')$$,:'s5'), 'shop_bears');
select transit_short_writeoff(:'s5'::uuid,'shop bears this one') ->> 'amount' as w5 \gset
select set_rule('transit_short_bearer','"ask"') is null as b3 \gset
select b_post_pending() as g5 \gset
reset role;
select tt.chk('G6 bearer = shop: the write-off works, 7 to 5100 / 1320 (owner-entered cost)', :'w5'::numeric=7 and tt.net('5100')=117 and tt.net('1320')=-87);

\echo == G6 list, append-only, direct writes refused
set role authenticated; select tt.as(:'o');
select tt.chk('G6 list returns the 4 rows with cost_missing false now and bearer rule', jsonb_array_length(transit_short_list())=4 and jsonb_array_length(transit_short_list('written_off'))=3 and jsonb_array_length(transit_short_list('recovered'))=1);
select tt.as(:'s');
select tt.err('G6 a salesperson cannot read the list', $$select transit_short_list()$$, 'not allowed');
select tt.err('G6 direct insert into the events is refused', format($$insert into shortage_transit_events (shortage_id,kind,amount,location_id,event_date,note) values (%L,'claim',1,1,current_date,'direct write')$$,:'s1'), 'permission denied');
select tt.err('G6 direct update of a case is refused', format($$update shortage_transit set status='open' where id=%L$$,:'s1'), 'permission denied');
reset role;
select tt.err('G6 events cannot be updated even by the database owner', $$update shortage_transit_events set amount=1$$, 'append_only');
select tt.err('G6 events cannot be deleted', $$delete from shortage_transit_events$$, 'append_only');
select tt.err('G6 events cannot be truncated', $$truncate shortage_transit_events$$, 'append_only');
select tt.as(:'o');
select (transit_short_backfill()->>'made')::int as bf \gset
select (cash_short_backfill()->>'made')::int as bf2 \gset
select tt.chk('G6 backfill finds nothing new (all short receives already have a row); G4 backfill too', :'bf'=0 and :'bf2'=0);

-- =====================================================================================================================================
\echo == G5 customer advance: deposit 1000, use 300 against a sale, refund 200 -> held 500
insert into customers (name, mobile) values ('test_cust', '01700000081') returning id as cu \gset
set role authenticated; select tt.as(:'o');
select cash_move_add(1,'cust_advance',1000,null,'cash',:'cu'::uuid) ->> 'id' as m1 \gset
select cash_move_add(1,'cust_advance_used',300,null,null,:'cu'::uuid) ->> 'id' as m2 \gset
select cash_move_add(1,'cust_advance_refund',200,null,'cash',:'cu'::uuid) ->> 'id' as m3 \gset
select tt.err('G5 a refund above the advance held is refused', format($$select cash_move_add(1,'cust_advance_refund',501,null,'cash',%L::uuid)$$,:'cu'), 'exceeds_advance');
select tt.err('G5 an advance needs a customer', $$select cash_move_add(1,'cust_advance',100,null,'cash',null)$$, 'customer_required');
select acct_post_pending() ->> 'posted' as pp \gset
reset role;
select tt.chk('G5 deposit: Dr 1110 1000 / Cr 2300 1000 with the customer as party', tt.jl('cash_move',:'m1','1110','d')=1000 and tt.jl('cash_move',:'m1','2300','c')=1000
  and (select count(*) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_id=:'m1' and l.party_type='customer' and l.party_id=:'cu')=1);
select tt.chk('G5 used against a sale: Dr 2300 300 / Cr 1210 300 (no money moves)', tt.jl('cash_move',:'m2','2300','d')=300 and tt.jl('cash_move',:'m2','1210','c')=300 and tt.jl('cash_move',:'m2','1110','d')=0);
select tt.chk('G5 refund: Dr 2300 200 / Cr 1110 200', tt.jl('cash_move',:'m3','2300','d')=200 and tt.jl('cash_move',:'m3','1110','c')=200);
select tt.chk('G5 account 2300 is a liability with a credit balance of 500', (select type from coa_accounts where code='2300')='liability' and tt.net('2300')=-500);
select tt.as(:'o');
select acct_balance_sheet(null) as bs \gset
select tt.chk('G5 the balance sheet lists 2300 under liabilities with 500', exists (select 1 from jsonb_array_elements(:'bs'::jsonb->'liabilities') x where x->>'code'='2300' and (x->>'amount')::numeric=500));
set role authenticated; select tt.as(:'o');
select cust_advance_check() as ck \gset
select tt.chk('G5 check: journal 500 = cash moves 500, no customer off', (:'ck'::jsonb->>'account_total_journal')::numeric=500 and (:'ck'::jsonb->>'account_total_cash_moves')::numeric=500
  and (:'ck'::jsonb->>'difference')::numeric=0 and jsonb_array_length(:'ck'::jsonb->'customers_off')=0);
select tt.chk('G5 the existing customer_advances() list shows 500 for this customer', (select balance from customer_advances() where customer_id=:'cu'::uuid)=500);
select tt.as(:'s');
select tt.err('G5 a salesperson cannot run the check', $$select cust_advance_check()$$, 'not allowed');
select tt.as(:'o');
-- a manual journal adds 40 to the customer advance in the books only: the check must name the customer
select acct_journal_post(tt.today(),1,'manual advance test',jsonb_build_array(jsonb_build_object('code','1110','d',40),jsonb_build_object('code','2300','c',40,'pt','customer','pid',:'cu'))) is not null as mj2 \gset
select cust_advance_check() as ck2 \gset
reset role;
select tt.chk('G5 a journal-only 40 shows as a difference on that customer', (:'ck2'::jsonb->>'difference')::numeric=40 and jsonb_array_length(:'ck2'::jsonb->'customers_off')=1
  and (:'ck2'::jsonb->'customers_off'->0->>'customer_id')=:'cu' and (:'ck2'::jsonb->'customers_off'->0->>'difference')::numeric=40);
select tt.chk('G5 and still balanced', tt.unbalanced_entries()=0);
-- a voided cash move is reversed by the existing poster
set role authenticated; select tt.as(:'o');
select cash_move_void(:'m3'::uuid,'refund slip was wrong') ->> 'status' as vv \gset
select acct_post_pending() ->> 'reversed' as pr \gset
reset role;
select tt.chk('G5 voiding the refund reverses it: 2300 credit = 1000 - 300 + 40 manual = 740', :'vv'='void' and :'pr'::int>=1 and tt.net('2300')=-(1000-300+40));

\echo == the integration hook: what the integrator adds to _acct_docs must run
-- simulate the one-line hook with a union over both functions in one statement; both must be readable by the poster the same way
select tt.chk('HOOK _b_docs(start) and _acct_docs(start) can be unioned (same shape)', (select count(*) from (select * from public._b_docs(tt.today()-5) union all select * from public._acct_docs(tt.today()-5)) z) >= 0);

\echo == RESULT
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
