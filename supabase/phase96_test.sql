-- FRESH DB ONLY. Phase 96 tests (step D23): D2 opening stock helper, D3 cost waiting list.
--   ORDER="phase8 ... phase93 phase96" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> a96db
--   psql -h /tmp -p 5544 -U postgres -d a96db -qAt -f supabase/phase96_test.sql | grep -E 'FAIL|RESULT'
-- All numbers are hand-computed (comment above each block). Test data only, no person names.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set w '00000000-0000-0000-0000-000000000003'
\set k '00000000-0000-0000-0000-000000000004'
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
-- journal amount of one source type on one account code (originals only, debit or credit side)
create or replace function tt.jt(p_type text, p_code text, p_side text) returns numeric language sql stable as $$
  select coalesce(sum(case p_side when 'd' then l.debit else l.credit end), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
  where e.source_type = p_type and e.reverses_id is null and a.code = p_code $$;
-- same, restricted to one place
create or replace function tt.jtl(p_type text, p_code text, p_side text, p_loc int) returns numeric language sql stable as $$
  select coalesce(sum(case p_side when 'd' then l.debit else l.credit end), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
  where e.source_type = p_type and e.reverses_id is null and a.code = p_code and l.location_id = p_loc $$;
create or replace function tt.noban(p text) returns boolean language sql immutable as $$ select p !~ '[ঀ-৿]' $$;
create or replace function tt.n(p_type text) returns bigint language sql stable as $$ select count(*) from public.journal_entries where source_type = p_type and reverses_id is null $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'),
  (:'w','store3@s.app','{"full_name":"Store"}'), (:'k','costkeeper4@s.app','{"full_name":"Cost keeper"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'w','storekeeper'),(:'k','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'w',1),(:'k',1) on conflict do nothing;
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I96-FL','Flour','Flour','kg','kg',0,true,'raw_material') returning id) select id as fl from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I96-SU','Sugar','Sugar','kg','kg',0,true,'raw_material') returning id) select id as su from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I96-CK','Cake','Cake','pc','pc',100,true,'finished_good') returning id) select id as ck from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I96-GM','Gum','Gum','kg','kg',0,true,'raw_material') returning id) select id as gm from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I96-GX','Glaze','Glaze','kg','kg',0,true,'raw_material') returning id) select id as gx from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I96-C2','Cake two','Cake two','pc','pc',100,true,'finished_good') returning id) select id as c2 from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I96-SK','Skip item','Skip item','kg','kg',0,true,'raw_material') returning id) select id as sk from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I96-FZ','Free item','Free item','kg','kg',0,true,'raw_material') returning id) select id as fz from i \gset
with i as (insert into suppliers (name) values ('Sup') returning id) select id as sup from i \gset

\echo == T0 shape and defaults
select tt.chk('T0 tags: bos96 in every re-created function, earlier tags kept (bos50 bos52 bos72 bos74 bos85 in _acct_docs)',
  position('bos96' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos96' in pg_get_functiondef('public._acct_stock_moves85(date)'::regprocedure))>0
  and position('bos96' in pg_get_functiondef('public._pvar85(uuid)'::regprocedure))>0 and position('bos96' in pg_get_functiondef('public._acct_inv_split72(text[],text,text[],int)'::regprocedure))>0
  and position('bos96' in pg_get_functiondef('public.inventory_vs_gl(date,int)'::regprocedure))>0
  and position('bos50' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos52' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0
  and position('bos72' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos74' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0
  and position('bos85' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos85' in pg_get_functiondef('public.inventory_vs_gl(date,int)'::regprocedure))>0);
select tt.chk('T0 internals closed to the browser, the calls open to signed-in people only; the ledger view and the new tables are closed',
  not has_function_privilege('authenticated','public._ob_plan96(text,int,text,date)','execute') and not has_function_privilege('authenticated','public._cw_plan96(text,text,text,jsonb)','execute')
  and not has_function_privilege('authenticated','public._cw_rows96(text,text)','execute') and not has_function_privilege('anon','public.cost_wait_supply96(text,text,text,jsonb,text,uuid,boolean)','execute')
  and not has_function_privilege('anon','public.opening_stock_apply96(text,int,text,date,text,uuid)','execute') and has_function_privilege('authenticated','public.opening_stock_apply96(text,int,text,date,text,uuid)','execute')
  and has_function_privilege('authenticated','public.cost_wait_list96(int,int)','execute')
  and not has_table_privilege('authenticated','public.stock_ledger_eff96','select') and not has_table_privilege('authenticated','public.ledger_cost_supply96','select')
  and not has_table_privilege('authenticated','public.opening_stock_actions96','select') and not has_table_privilege('authenticated','public.ledger_cost_supply96','insert'));
select tt.chk('T0 new tables: RLS on; append-only (update/delete/truncate refused for everyone)', (select relrowsecurity from pg_class where relname='ledger_cost_supply96') and (select relrowsecurity from pg_class where relname='opening_stock_actions96')
  and exists (select 1 from pg_trigger where tgname='ledger_cost_supply96_ro') and exists (select 1 from pg_trigger where tgname='opening_stock_actions96_ro'));
select tt.chk('T0 rule acct_cost_wait_alert_days: number, NO built-in value (blank), 0..3650', (select kind='number' and default_value is null and value is null and min_value=0 and max_value=3650 from rules where key='acct_cost_wait_alert_days')
  and rule_num('acct_cost_wait_alert_days') is null);
select tt.chk('T0 English rule label and hint have no Bangla characters', (select tt.noban(coalesce(label_en,'')) and tt.noban(coalesce(hint_en,'')) from rules where key='acct_cost_wait_alert_days'));

\echo == setup: accounting on from 5 days ago; openings; an opening journal that already carries raw material of place 1
set role authenticated; select tt.as(:'o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
-- place 1: flour 100 @ 40 = 4000 ; sugar 50 @ 30 = 1500 ; cake 10 @ 25 = 250 ; gum 19 and glaze 5 WITHOUT cost.  place 2: sugar 20 @ 30 = 600
select stock_opening(:'fl'::uuid,1,100,40) is not null as o1 \gset
select stock_opening(:'su'::uuid,1,50,30) is not null as o2 \gset
select stock_opening(:'ck'::uuid,1,10,25) is not null as o3 \gset
select stock_opening(:'gm'::uuid,1,19,null) is not null as o4 \gset
select stock_opening(:'gx'::uuid,1,5,null) is not null as o5 \gset
select stock_opening(:'su'::uuid,2,20,30) is not null as o6 \gset
-- the opening journal (acct_opening) already carries 1000 of raw material at place 1
select acct_opening('[{"code":"1320","debit":1000,"location_id":1},{"code":"3100","credit":1000}]'::jsonb)->>'id' as oj \gset
reset role;
select tt.chk('setup: openings and the opening journal exist', :'o1' and :'o2' and :'o3' and :'o4' and :'o5' and :'o6' and :'oj' is not null and rule_on('accounting_on') and tt.n('opening')=1);

\echo == D2 the check (read only)
-- place 1: opening value = 4000 + 1500 + 250 = 5750 (5 rows, 2 without cost) ; the opening journal carries 1000 ; GL inventory 1000 ; valuation 5750 (gum / glaze have no average) -> diff -4750
-- place 2: opening 600 (1 row) ; journal 0 ; GL 0 ; valuation 600 ; diff -600.  total: 6350 / 1000 / 1000 / 6350 / -5350
set role authenticated; select tt.as(:'o');
select opening_stock_check96() as ck0 \gset
reset role;
select tt.chk('D2 check place 1: value 5750, rows 5, uncosted 2, opening journal 1000, GL 1000, valuation 5750, diff -4750',
  (select (r->>'opening_value')::numeric=5750 and (r->>'opening_rows')::int=5 and (r->>'uncosted_rows')::int=2 and (r->>'opening_journal_inventory')::numeric=1000 and (r->>'gl_inventory')::numeric=1000
      and (r->>'valuation')::numeric=5750 and (r->>'diff')::numeric=-4750 from jsonb_array_elements(:'ck0'::jsonb->'rows') r where (r->>'location_id')::int=1));
select tt.chk('D2 check place 2: value 600, rows 1, journal 0, GL 0, valuation 600, diff -600',
  (select (r->>'opening_value')::numeric=600 and (r->>'opening_rows')::int=1 and (r->>'uncosted_rows')::int=0 and (r->>'opening_journal_inventory')::numeric=0 and (r->>'gl_inventory')::numeric=0
      and (r->>'valuation')::numeric=600 and (r->>'diff')::numeric=-600 from jsonb_array_elements(:'ck0'::jsonb->'rows') r where (r->>'location_id')::int=2));
select tt.chk('D2 check total: 6350 / 1000 / 1000 / 6350 / -5350', (:'ck0'::jsonb->'total'->>'opening_value')::numeric=6350 and (:'ck0'::jsonb->'total'->>'opening_journal_inventory')::numeric=1000
  and (:'ck0'::jsonb->'total'->>'gl_inventory')::numeric=1000 and (:'ck0'::jsonb->'total'->>'valuation')::numeric=6350 and (:'ck0'::jsonb->'total'->>'diff')::numeric=-5350);
select tt.chk('D2 double count risk is shown BEFORE the switch is turned on (switch is off)', (:'ck0'::jsonb->>'risk')::boolean and not (:'ck0'::jsonb->>'switch_on')::boolean
  and :'ck0'::jsonb->'warnings' ? 'opening_journal_has_inventory' and :'ck0'::jsonb->'warnings' ? 'switch_would_double_count' and :'ck0'::jsonb->'warnings' ? 'uncosted_openings' and not (:'ck0'::jsonb->'warnings' ? 'switch_on_double_count'));
select tt.chk('D2 the check wrote nothing', tt.n('opening_stock96')=0 and (select count(*) from opening_stock_actions96)=0);

\echo == D2 dry run of every option (no writes)
set role authenticated; select tt.as(:'o');
select opening_stock_preview96('owner_capital',1) as pa \gset
select opening_stock_preview96('difference',1) as pd \gset
select opening_stock_preview96('existing_account',1,'3900') as pb \gset
select opening_stock_preview96('skip',1) as pc \gset
reset role;
-- (a) Dr 1320 4000+1500 = 5500, Dr 1310 250, Cr 3100 5750
select tt.chk('D2 preview owner_capital place 1: Dr 1320 5500 + Dr 1310 250 / Cr 3100 5750, dry', (:'pa'::jsonb->>'ok')::boolean and (:'pa'::jsonb->>'amount')::numeric=5750 and (:'pa'::jsonb->>'dry')::boolean
  and (select count(*) from jsonb_array_elements(:'pa'::jsonb->'lines'))=3
  and (select sum((x->>'debit')::numeric) from jsonb_array_elements(:'pa'::jsonb->'lines') x where x->>'code'='1320')=5500 and (select sum((x->>'debit')::numeric) from jsonb_array_elements(:'pa'::jsonb->'lines') x where x->>'code'='1310')=250
  and (select sum((x->>'credit')::numeric) from jsonb_array_elements(:'pa'::jsonb->'lines') x where x->>'code'='3100')=5750 and :'pa'::jsonb->>'counter_code'='3100' and not (:'pa'::jsonb ? 'post_lines'));
-- (d) the opening journal already carries raw 1000: raw 5500-1000 = 4500, finished 250 -> 4750
select tt.chk('D2 preview difference place 1: only what the opening journal lacks: 4500 + 250 = 4750', (:'pd'::jsonb->>'ok')::boolean and (:'pd'::jsonb->>'amount')::numeric=4750 and (:'pd'::jsonb->'by_key'->>'inv_raw')::numeric=4500
  and (:'pd'::jsonb->'by_key'->>'inv_finished')::numeric=250 and (:'pd'::jsonb->>'already_in_opening_journal')::numeric=1000);
select tt.chk('D2 preview existing_account 3900: same 5750 against 3900', (:'pb'::jsonb->>'ok')::boolean and (:'pb'::jsonb->>'amount')::numeric=5750 and :'pb'::jsonb->>'counter_code'='3900');
select tt.chk('D2 preview skip: amount 0, warns that the opening journal (1000) does not cover 5750', (:'pc'::jsonb->>'ok')::boolean and (:'pc'::jsonb->>'amount')::numeric=0 and :'pc'::jsonb->'warnings' ? 'skip_but_not_in_opening_journal');
select tt.chk('D2 previews wrote nothing', tt.n('opening_stock96')=0 and (select count(*) from opening_stock_actions96)=0 and (select count(*) from audit_log where table_name='opening_stock_actions96')=0);
set role authenticated; select tt.as(:'o');
select tt.chk('D2 preview errors: bad option / place needed / account needed / inventory account / expense account refused',
  (opening_stock_preview96('xx',1)->>'error')='bad_option' and (opening_stock_preview96('owner_capital',null)->>'error')='place_needed' and (opening_stock_preview96('existing_account',1)->>'error')='account_needed'
  and (opening_stock_preview96('existing_account',1,'1320')->>'error')='bad_account' and (opening_stock_preview96('existing_account',1,'5110')->>'error')='bad_account'
  and (opening_stock_preview96('existing_account',1,'9999')->>'error')='bad_account' and (opening_stock_preview96('owner_capital',99)->>'error')='bad_location');
select tt.chk('D2 difference for one place is refused when part of the opening journal is not split by place; here it is split (place 1) so company wide also works: raw 6100-1000 + finished 250 = 5350',
  (opening_stock_preview96('difference',null)->>'amount')::numeric=5350);
select opening_stock_recommend96(1) as r1 \gset
select opening_stock_recommend96(2) as r2 \gset
reset role;
select tt.chk('D2 recommend place 1: difference (journal 1000 < value 5750), alternatives with numbers, never auto', :'r1'::jsonb->>'recommended'='difference' and (:'r1'::jsonb->>'never_auto')::boolean
  and (:'r1'::jsonb->'numbers'->>'opening_value')::numeric=5750 and (:'r1'::jsonb->'numbers'->>'already_in_opening_journal')::numeric=1000
  and (select (x->>'amount')::numeric from jsonb_array_elements(:'r1'::jsonb->'alternatives') x where x->>'option'='owner_capital')=5750
  and (select (x->>'amount')::numeric from jsonb_array_elements(:'r1'::jsonb->'alternatives') x where x->>'option'='difference')=4750);
select tt.chk('D2 recommend place 2: owner_capital (the opening journal has no stock there), value 600', :'r2'::jsonb->>'recommended'='owner_capital' and (:'r2'::jsonb->'numbers'->>'opening_value')::numeric=600);
select tt.chk('D2 recommendation text in 3 modes, English has no Bangla', tt.noban(:'r1'::jsonb->'reason'->>'en') and :'r1'::jsonb->'reason'->>'bn' ~ '[ঀ-৿]' and :'r1'::jsonb->'reason'->>'mix' ~ '[ঀ-৿]');
select tt.chk('D2 recommending changed nothing', tt.n('opening_stock96')=0 and (select count(*) from opening_stock_actions96)=0);

\echo == D2 turning the switch ON while the opening journal carries stock leaves a warning in the audit trail
set role authenticated; select tt.as(:'o');
select set_rule('acct_stock_opening','true') is null as sw1 \gset
select opening_stock_check96() as ck1 \gset
reset role;
select tt.chk('D2 audit warning written once (code switch_on_double_count, journal 1000, to post 6350)', (select count(*) from audit_log where action='warn' and table_name='rules' and record_id='acct_stock_opening')=1
  and (select (detail->>'opening_journal_inventory')::numeric=1000 and (detail->>'opening_stock_to_post')::numeric=6350 and detail->>'code'='switch_on_double_count' from audit_log where action='warn' and record_id='acct_stock_opening'));
select tt.chk('D2 check now says the double count is happening (switch on)', :'ck1'::jsonb->'warnings' ? 'switch_on_double_count' and (:'ck1'::jsonb->>'switch_on')::boolean);
-- WITHOUT the helper the switch would post all 4 costed openings: 4000 + 1500 + 250 + 600 = 6350 on top of the 1000 already in the opening journal (rolled back below)
begin;
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as pcontrast \gset
reset role;
select tt.chk('D2 contrast (rolled back): the switch alone would post 4 opening entries = 6350 on top of the opening journal', (:'pcontrast'::jsonb->'by_type'->>'stock_opening')::int=4
  and tt.jt('stock_opening','1320','d')=5500+600 and tt.jt('stock_opening','1310','d')=250);
rollback;
set role authenticated; select tt.as(:'o');
select set_rule('acct_stock_opening','false') is null as sw0 \gset
reset role;
select tt.chk('D2 contrast rolled back: nothing posted, switch off again', tt.n('stock_opening')=0 and not rule_on('acct_stock_opening'));

\echo == D2 apply (owner only, audited, idempotent)
set role authenticated; select tt.as(:'s');
select tt.err('D2 apply: a manager is refused', $$select opening_stock_apply96('difference',1,null,null,'x','00000000-0000-0000-0000-0000000000d1')$$, 'not allowed');
select tt.as(:'w');
select tt.err('D2 check: a storekeeper (no cost right) is refused', $$select opening_stock_check96(1)$$, 'not allowed');
select tt.err('D2 preview: a storekeeper is refused', $$select opening_stock_preview96('owner_capital',1)$$, 'not allowed');
select tt.as(:'o');
select tt.err('D2 apply needs a client id', $$select opening_stock_apply96('difference',1)$$, 'client_id_needed');
select tt.err('D2 apply: bad option refused', $$select opening_stock_apply96('zz',1,null,null,null,'00000000-0000-0000-0000-0000000000d9')$$, 'bad_option');
select opening_stock_apply96('difference',1,null,null,'opening journal has part of it','00000000-0000-0000-0000-0000000000d1') as ap1 \gset
select opening_stock_apply96('difference',1,null,null,'opening journal has part of it','00000000-0000-0000-0000-0000000000d1') as ap1b \gset
select tt.err('D2 a second option for the same place is refused (already applied)', $$select opening_stock_apply96('owner_capital',1,null,null,null,'00000000-0000-0000-0000-0000000000d2')$$, 'already_applied');
select tt.err('D2 company wide is refused while a place is applied', $$select opening_stock_apply96('difference',null,null,null,null,'00000000-0000-0000-0000-0000000000d3')$$, 'already_applied');
select opening_stock_apply96('existing_account',2,'3900',null,'retained opening','00000000-0000-0000-0000-0000000000d4') as ap2 \gset
reset role;
-- place 1: Dr 1320 4500, Dr 1310 250 / Cr 3100 4750 ; place 2: Dr 1320 600 / Cr 3900 600
select tt.chk('D2 apply difference place 1: one entry, amount 4750, Dr 1320 4500 + Dr 1310 250 / Cr 3100 4750, every line tagged place 1', (:'ap1'::jsonb->>'amount')::numeric=4750 and tt.n('opening_stock96')=2
  and tt.jtl('opening_stock96','1320','d',1)=4500 and tt.jtl('opening_stock96','1310','d',1)=250 and tt.jtl('opening_stock96','3100','c',1)=4750);
select tt.chk('D2 apply is idempotent by client id (same id: dup, same entry, no second entry)', (:'ap1b'::jsonb->>'dup')::boolean and :'ap1b'::jsonb->>'entry_id' = :'ap1'::jsonb->>'entry_id' and (select count(*) from opening_stock_actions96 where location_id=1)=1);
select tt.chk('D2 apply existing_account place 2: Dr 1320 600 / Cr 3900 600', tt.jtl('opening_stock96','1320','d',2)=600 and tt.jtl('opening_stock96','3900','c',2)=600);
select tt.chk('D2 decision rows: 2, audited (audit_log insert rows), covering 3 costed rows at place 1 (gum and glaze stay open) and 1 at place 2',
  (select array_length(covered_ids,1) from opening_stock_actions96 where location_id=1)=3 and (select array_length(covered_ids,1) from opening_stock_actions96 where location_id=2)=1
  and (select count(*) from audit_log where table_name='opening_stock_actions96' and action='insert')=2);
select tt.chk('D2 the entry is a real journal entry: balanced, source opening_stock96 / loc:1 and loc:2, unique per place', tt.unbalanced_entries()=0
  and (select count(*) from journal_entries where source_type='opening_stock96' and source_id in ('loc:1','loc:2'))=2);
select tt.chk('D2 the append-only decision table refuses update and delete (even for the database owner)', (select count(*) from opening_stock_actions96)=2);
select tt.err('D2 decision update refused', $$update opening_stock_actions96 set amount=1$$, 'ledger_immutable');
select tt.err('D2 decision delete refused', $$delete from opening_stock_actions96$$, 'ledger_immutable');
-- after the apply GL = valuation at both places: place 1 = 1000 + 4750 = 5750 = 5750 ; place 2 = 600 = 600
set role authenticated; select tt.as(:'o');
select opening_stock_check96() as ck2 \gset
select inventory_vs_gl(tt.today(), null) as iv1 \gset
select opening_stock_recommend96(1) as r1b \gset
reset role;
select tt.chk('D2 after: place 1 GL 5750 = valuation 5750, place 2 GL 600 = valuation 600, nothing left to post (value 0), decisions shown',
  (select (r->>'gl_inventory')::numeric=5750 and (r->>'valuation')::numeric=5750 and (r->>'diff')::numeric=0 and (r->>'opening_value')::numeric=0 and r->>'decision'='difference' and (r->>'uncosted_rows')::int=2 from jsonb_array_elements(:'ck2'::jsonb->'rows') r where (r->>'location_id')::int=1)
  and (select (r->>'gl_inventory')::numeric=600 and (r->>'valuation')::numeric=600 and r->>'decision'='existing_account' from jsonb_array_elements(:'ck2'::jsonb->'rows') r where (r->>'location_id')::int=2));
select tt.chk('D2 inventory_vs_gl: GL = valuation (raw 6100, finished 250), diff 0, unexplained 0 (the new opening entries are counted as opening)', (:'iv1'::jsonb->'total'->>'gl')::numeric=6350 and (:'iv1'::jsonb->'total'->>'valuation')::numeric=6350
  and (:'iv1'::jsonb->'total'->>'diff')::numeric=0 and (:'iv1'::jsonb->'total'->>'unexplained')::numeric=0 and (:'iv1'::jsonb->>'agree')::boolean);
select tt.chk('D2 recommend after the apply: nothing more to do', :'r1b'::jsonb->>'recommended'='none');
-- the switch on again: the covered openings are NOT posted a second time; the two rows without cost wait (cost_missing)
set role authenticated; select tt.as(:'o');
select set_rule('acct_stock_opening','true') is null as sw2 \gset
select acct_post_pending(false) as pp1 \gset
reset role;
select tt.chk('D2 switch ON after the helper: no stock_opening entry for the covered rows (no double count); gum and glaze openings wait as cost_missing = 2',
  tt.n('stock_opening')=0 and coalesce((:'pp1'::jsonb->'by_type'->>'stock_opening')::int,0)=0 and (:'pp1'::jsonb->'waiting'->>'cost_missing')::int=2 and jsonb_array_length(:'pp1'::jsonb->'errors')=0);

\echo == D2 an opening added AFTER the decision of a place is not covered: the switch posts it (once); a skip decision at another place posts nothing
set role authenticated; select tt.as(:'o');
select stock_opening(:'sk'::uuid,2,7,10) is not null as ok_sk \gset
select stock_opening(:'sk'::uuid,3,7,10) is not null as ok_sk3 \gset
select opening_stock_check96() as ck3 \gset
select opening_stock_apply96('skip',3,null,null,'already in the books','00000000-0000-0000-0000-0000000000d5') as ap3 \gset
select acct_post_pending(false) as pp2 \gset
select acct_post_pending(false) as pp3 \gset
reset role;
-- new opening 7 @ 10 = 70 at place 2 (after its decision) -> the switch posts Dr 1320 70 / Cr 3100 70 at place 2 ; the same at place 3 is skipped
select tt.chk('D2 check shows 70 to post at place 2 and at place 3', (select (r->>'opening_value')::numeric=70 from jsonb_array_elements(:'ck3'::jsonb->'rows') r where (r->>'location_id')::int=2)
  and (select (r->>'opening_value')::numeric=70 from jsonb_array_elements(:'ck3'::jsonb->'rows') r where (r->>'location_id')::int=3));
select tt.chk('D2 skip: decision kept, no entry; the switch posted ONLY the place-2 opening (1 entry, 70) and posts nothing the second time',
  (:'ap3'::jsonb->>'amount')::numeric=0 and (:'ap3'::jsonb->>'entry_id') is null and (select count(*) from opening_stock_actions96 where option='skip')=1
  and tt.n('stock_opening')=1 and tt.jtl('stock_opening','1320','d',2)=70 and tt.jtl('stock_opening','3100','c',2)=70 and tt.jtl('stock_opening','1320','d',3)=0
  and (:'pp2'::jsonb->'by_type'->>'stock_opening')::int=1 and (:'pp3'::jsonb->>'posted')::int=0);
select tt.chk('D2 every entry so far balances', tt.unbalanced_entries()=0);

\echo ============================================================ D3 cost waiting
\echo == D3 moves without a cost (real functions): gum has no cost yet (opening 19 without cost)
set role authenticated; select tt.as(:'o');
-- W1 wastage gum 2 ; L2 sugar count 50 -> 53 (a gain, NULL cost, switch off) ; T1 transfer gum 3 place 1 -> 2 received in full ; P1 recipe 4 gum -> 10 cake two, one batch ;
-- W2 wastage cake two 1 ; W3 wastage glaze 1.   Gum qty at place 1: 19 - 2 - 3 - 4 = 10 ; glaze 5 - 1 = 4
select stock_wastage(:'gm'::uuid,1,2,'spoiled','w1') is not null as w1 \gset
select stock_count_adjust(:'su'::uuid,1,53,'count sugar') is not null as l2 \gset
select (stock_transfer(1,2,:'gm'::uuid,3,null,'t1')->>'id')::uuid as t1 \gset
select stock_receive_transfer(:'t1'::uuid, 3, null)->>'status' as t1st \gset
select (recipe_save(null, :'c2'::uuid, 10, null, 'v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'gm','qty',4,'waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid())->>'qty' as pq \gset
select stock_wastage(:'c2'::uuid,1,1,'spoiled','w2') is not null as w2 \gset
select stock_wastage(:'gx'::uuid,1,1,'spoiled','w3') is not null as w3 \gset
reset role;
select id as w1id from stock_wastage where item_id=:'gm'::uuid \gset
select id as w2id from stock_wastage where item_id=:'c2'::uuid \gset
select id as w3id from stock_wastage where item_id=:'gx'::uuid \gset
select id as pid from production_runs where recipe_id=:'rc'::uuid \gset
select id as l2id from stock_ledger where item_id=:'su'::uuid and reason='count_adjust' and ref_type is distinct from 'x' order by id desc limit 1 \gset
select id as l1id from stock_ledger where item_id=:'gm'::uuid and reason='opening' \gset
select id as l3id from stock_ledger where item_id=:'gx'::uuid and reason='opening' \gset
select tt.chk('D3 setup: the moves happened and have NO cost in the ledger (NULL)', :'w1' and :'l2' and :'t1st'='received' and :'w2' and :'w3' and :'pq'::numeric=10
  and (select unit_cost is null from stock_ledger where reason='wastage' and ref_id=:'w1id') and (select unit_cost is null from stock_ledger where reason='wastage' and ref_id=:'w2id') and (select unit_cost is null from stock_ledger where reason='wastage' and ref_id=:'w3id')
  and (select count(*) from stock_ledger where ref_type='transfer' and ref_id=:'t1' and unit_cost is null)=2 and (select unit_cost is null from stock_ledger where reason='count_adjust' and item_id=:'su'::uuid)
  and (select count(*) from stock_ledger where reason='issue_out' and ref_type='production' and ref_id=:'pid' and unit_cost is null)>=1 and (select unit_cost is null from stock_ledger where reason='production_in' and ref_id=:'pid'));
select tt.chk('D3 setup: gum qty place 1 = 10, glaze 4', (select qty from stock_balance where item_id=:'gm'::uuid and location_id=1)=10 and (select qty from stock_balance where item_id=:'gx'::uuid and location_id=1)=4);

\echo == purchases of gum after the moves: 10 @ 12 and 20 @ 18 -> average (10 x 12... first purchase sets 12, then (20x12 + 20x18)/40 = 15), last purchase 18 ; a gum count gain afterwards is uncosted
set role authenticated; select tt.as(:'o');
select save_purchase(gen_random_uuid(),null,:'sup'::uuid,1,'B96-1',tt.today()-1,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":12}]',:'gm')::jsonb)->>'id' as b1 \gset
select post_purchase(:'b1'::uuid) is not null as pb1 \gset
select save_purchase(gen_random_uuid(),null,:'sup'::uuid,1,'B96-2',tt.today(),format('[{"item_id":"%s","qty":20,"unit":"kg","unit_cost":18}]',:'gm')::jsonb)->>'id' as b2 \gset
select post_purchase(:'b2'::uuid) is not null as pb2 \gset
select stock_count_adjust(:'gm'::uuid,1,42,'count gum') is not null as l4 \gset
reset role;
select id as l4id from stock_ledger where item_id=:'gm'::uuid and reason='count_adjust' \gset
select tt.chk('D3 setup: gum average at place 1 = 15, qty 42 after the count; the gain row has NULL cost (switch off)', :'pb1' and :'pb2' and :'l4' and (select avg_cost from stock_balance where item_id=:'gm'::uuid and location_id=1)=15
  and (select qty from stock_balance where item_id=:'gm'::uuid and location_id=1)=42 and (select unit_cost is null and qty_delta=2 from stock_ledger where id=:'l4id'));

\echo == D3 switches on and the books post what has a cost; the uncosted moves wait
set role authenticated; select tt.as(:'o');
select set_rule('acct_count_adjust','true') is null as s1 \gset
select set_rule('acct_transfer_mode','"location_tagged"') is null as s2 \gset
select acct_post_pending(false) as pw \gset
select acct_post_pending(false) as pw2 \gset
reset role;
-- cost_missing documents the books wait for: wastage 3 + production 1 + count gains 2 + openings (gum, glaze) 2 + transfer rows 2 = 10
select tt.chk('D3 the books wait for 10 documents as cost_missing (3 wastage, 1 production, 2 count gains, 2 openings, 2 transfer rows); no errors', (:'pw'::jsonb->'waiting'->>'cost_missing')::int=10 and jsonb_array_length(:'pw'::jsonb->'errors')=0
  and (:'pw2'::jsonb->>'posted')::int=0 and tt.n('wastage')=0 and tt.n('production')=0 and tt.n('stock_transfer')=0 and tt.n('stock_adjust')=0);

\echo == D3 the waiting list
set role authenticated; select tt.as(:'o');
select cost_wait_list96() as lst \gset
select cost_wait_alert96() as al0 \gset
reset role;
select tt.chk('D3 list: 9 documents (4 ledger moves, 3 wastage, 1 production, 1 transfer), all age 0, all would post (gl_post)', (:'lst'::jsonb->>'total')::int=9 and (:'lst'::jsonb->'by_kind'->>'ledger')::int=4 and (:'lst'::jsonb->'by_kind'->>'wastage')::int=3
  and (:'lst'::jsonb->'by_kind'->>'production')::int=1 and (:'lst'::jsonb->'by_kind'->>'transfer')::int=1 and (:'lst'::jsonb->>'oldest_days')::int=0
  and (select bool_and((x->>'gl_post')::boolean and (x->>'age_days')::int=0) from jsonb_array_elements(:'lst'::jsonb->'items') x));
select tt.chk('D3 list: the wastage of gum shows item I96-GM qty 2; the production shows the gum ingredient qty 4; the transfer shows gum qty 3 (out side only)',
  (select (x->'items'->0->>'code')='I96-GM' and (x->'items'->0->>'qty')::numeric=2 from jsonb_array_elements(:'lst'::jsonb->'items') x where x->>'kind'='wastage' and x->>'ref'=:'w1id')
  and (select (x->'items'->0->>'qty')::numeric=4 from jsonb_array_elements(:'lst'::jsonb->'items') x where x->>'kind'='production' and x->>'ref'=:'pid')
  and (select (x->'items'->0->>'qty')::numeric=3 and (x->>'rows')::int=2 from jsonb_array_elements(:'lst'::jsonb->'items') x where x->>'kind'='transfer' and x->>'ref'=:'t1'));
select tt.chk('D3 list: ledger documents carry what the move is (opening / count_adjust)', (select x->>'move' from jsonb_array_elements(:'lst'::jsonb->'items') x where x->>'kind'='ledger' and x->>'ref'=:'l1id'::text)='opening'
  and (select x->>'move' from jsonb_array_elements(:'lst'::jsonb->'items') x where x->>'kind'='ledger' and x->>'ref'=:'l2id'::text)='count_adjust');
select tt.chk('D3 aging: the number is blank (no built-in value) -> list shown, alert off, old_count null', not (:'lst'::jsonb->>'alert_enabled')::boolean and (:'lst'::jsonb->'alert_days') = 'null'::jsonb and (:'lst'::jsonb->'old_count') = 'null'::jsonb
  and not (:'al0'::jsonb->>'alert')::boolean and jsonb_array_length(:'al0'::jsonb->'items')=0);

\echo == D3 who may see and supply (owner or cost right, and the place)
set role authenticated; select tt.as(:'w');
select tt.err('D3 storekeeper without cost right: list refused', $$select cost_wait_list96()$$, 'not allowed');
select tt.err('D3 storekeeper: alert refused', $$select cost_wait_alert96()$$, 'not allowed');
select tt.err('D3 storekeeper: preview refused', format($$select cost_wait_preview96('wastage','%s','item_average')$$, :'w1id'), 'not allowed');
select tt.err('D3 storekeeper: recommend refused', format($$select cost_wait_recommend96('wastage','%s')$$, :'w1id'), 'not allowed');
select tt.err('D3 storekeeper: supply refused', format($$select cost_wait_supply96('wastage','%s','item_average',null,null,'00000000-0000-0000-0000-0000000000e0')$$, :'w1id'), 'not allowed');
select tt.as(:'o');
select set_user_grant(:'k'::uuid,'view_cost') is null as gk \gset
select tt.as(:'k');
select cost_wait_list96() as lstk \gset
reset role;
select tt.chk('D3 a view_cost holder of place 1 sees the documents of place 1', (:'lstk'::jsonb->>'total')::int=9);
set role authenticated; select tt.as(:'k');
select tt.err('D3 the same person cannot supply the transfer (it touches place 2 where he has no access)', format($$select cost_wait_supply96('transfer','%s','item_average',null,null,'00000000-0000-0000-0000-0000000000e1')$$, :'t1'), 'not allowed');
reset role;

\echo == D3 preview and recommendation (dry runs; numbers hand-computed)
-- W1 gum 2: average 15 -> 30.00 ; last purchase none before the wastage -> null ; recommended = item_average
-- W2 cake two 1: no average, no purchase ; recipe: 4 gum x 15 / 10 = 6 -> recommended recipe_standard 6.00
-- W3 glaze 1: nothing known -> manual
-- L4 gum gain +2 : average 15 -> 30 ; last purchase 18 -> 36 ; recommended item_average
set role authenticated; select tt.as(:'o');
select cost_wait_preview96('wastage', :'w1id', 'item_average') as pv1 \gset
select cost_wait_preview96('wastage', :'w1id', 'last_purchase') as pv1b \gset
select cost_wait_recommend96('wastage', :'w1id') as rc1 \gset
select cost_wait_recommend96('wastage', :'w2id') as rc2 \gset
select cost_wait_recommend96('wastage', :'w3id') as rc3 \gset
select cost_wait_recommend96('ledger', :'l4id'::text) as rc4 \gset
select cost_wait_preview96('wastage', :'w3id', 'item_average') as pv3 \gset
select cost_wait_preview96('wastage', :'w3id', 'manual', jsonb_build_array(jsonb_build_object('item_id', :'gx', 'cost', 8))) as pv3m \gset
select cost_wait_preview96('production', :'pid', 'item_average') as pvp \gset
reset role;
select tt.chk('D3 preview item_average for W1: cost 15, amount 30, dry, gl_post true', (:'pv1'::jsonb->>'ok')::boolean and (:'pv1'::jsonb->'items'->0->>'unit_cost')::numeric=15 and (:'pv1'::jsonb->'items'->0->>'amount')::numeric=30 and (:'pv1'::jsonb->>'total')::numeric=30
  and (:'pv1'::jsonb->>'dry')::boolean and (:'pv1'::jsonb->>'gl_post')::boolean and not (:'pv1'::jsonb->'items'->0 ? 'lids'));
select tt.chk('D3 preview last_purchase for W1: there was no purchase before the wastage -> cost_unavailable (nothing invented)', not (:'pv1b'::jsonb->>'ok')::boolean and :'pv1b'::jsonb->>'error'='cost_unavailable' and :'pv1b'::jsonb->>'detail'='I96-GM');
select tt.chk('D3 recommend W1: item_average 15 (30.00); the alternatives list the average only', :'rc1'::jsonb->'items'->0->>'recommended'='item_average' and (:'rc1'::jsonb->'items'->0->>'unit_cost')::numeric=15 and (:'rc1'::jsonb->>'never_auto')::boolean
  and jsonb_array_length(:'rc1'::jsonb->'items'->0->'alternatives')=1);
select tt.chk('D3 recommend W2: recipe_standard 6 (4 gum x 15 / 10), amount 6.00', :'rc2'::jsonb->'items'->0->>'recommended'='recipe_standard' and (:'rc2'::jsonb->'items'->0->>'unit_cost')::numeric=6 and (:'rc2'::jsonb->'items'->0->>'amount')::numeric=6);
select tt.chk('D3 recommend W3: nothing is known -> manual, the person is asked to type the cost; no number is made up', (:'rc3'::jsonb->>'ok')::boolean and :'rc3'::jsonb->'items'->0->>'recommended'='manual' and (:'rc3'::jsonb->'items'->0->'unit_cost') = 'null'::jsonb
  and :'rc3'::jsonb->'needs_manual' ? 'I96-GX');
select tt.chk('D3 recommend L4 (gum gain +2): item_average 15 -> 30; last purchase 18 -> 36 shown as the alternative', :'rc4'::jsonb->'items'->0->>'recommended'='item_average'
  and (select (a->>'amount')::numeric from jsonb_array_elements(:'rc4'::jsonb->'items'->0->'alternatives') a where a->>'method'='last_purchase')=36
  and (select (a->>'amount')::numeric from jsonb_array_elements(:'rc4'::jsonb->'items'->0->'alternatives') a where a->>'method'='item_average')=30);
select tt.chk('D3 recommendation reasons in 3 modes; the English text has no Bangla', tt.noban(:'rc1'::jsonb->'items'->0->'reason'->>'en') and :'rc1'::jsonb->'items'->0->'reason'->>'bn' ~ '[ঀ-৿]' and :'rc1'::jsonb->'items'->0->'reason'->>'mix' ~ '[ঀ-৿]'
  and tt.noban(:'rc3'::jsonb->'items'->0->'reason'->>'en'));
select tt.chk('D3 preview item_average for W3 (glaze): cost_unavailable; manual 8 -> amount 8', not (:'pv3'::jsonb->>'ok')::boolean and :'pv3'::jsonb->>'error'='cost_unavailable' and (:'pv3m'::jsonb->>'ok')::boolean and (:'pv3m'::jsonb->>'total')::numeric=8);
select tt.chk('D3 preview production: ingredient gum 4 x 15 = 60 ; the finished cake two gets 60 / 10 = 6 per piece (derived record)', (:'pvp'::jsonb->>'ok')::boolean and (:'pvp'::jsonb->>'total')::numeric=60 and (:'pvp'::jsonb->'derived'->0->>'unit_cost')::numeric=6);
select tt.chk('D3 previews and recommendations wrote nothing', (select count(*) from ledger_cost_supply96)=0 and tt.n('wastage')=0 and tt.n('production')=0);

\echo == D3 aging alert: the owner types the number
set role authenticated; select tt.as(:'o');
reset role;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at) values (:'su'::uuid, 1, -1, null, 'count_adjust', 'count', 'old96', now() - interval '4 days');
select id as oldid from stock_ledger where ref_id='old96' \gset
set role authenticated; select tt.as(:'o');
select tt.err('D3 alert days below 0 refused by the rule', $$select set_rule('acct_cost_wait_alert_days','-1')$$, '');
select tt.err('D3 alert days above 3650 refused by the rule', $$select set_rule('acct_cost_wait_alert_days','3651')$$, '');
select cost_wait_alert96() as a_blank \gset
select set_rule('acct_cost_wait_alert_days','3') is null as r3 \gset
select cost_wait_alert96() as a3 \gset
select set_rule('acct_cost_wait_alert_days','4') is null as r4 \gset
select cost_wait_alert96() as a4 \gset
select set_rule('acct_cost_wait_alert_days','0') is null as r0 \gset
select cost_wait_alert96() as a0 \gset
select cost_wait_list96() as lst2 \gset
select set_rule('acct_cost_wait_alert_days','null') is null as rn \gset
reset role;
-- the old count loss (-1 sugar, 4 days old) is the 10th document: age 4
select tt.chk('D3 list now 10 documents, the oldest is 4 days', (:'lst2'::jsonb->>'total')::int=10 and (:'lst2'::jsonb->>'oldest_days')::int=4 and (:'lst2'::jsonb->'items'->0->>'ref')=:'oldid');
select tt.chk('D3 alert: blank number -> no alert even with an old document', not (:'a_blank'::jsonb->>'alert')::boolean and not (:'a_blank'::jsonb->>'alert_enabled')::boolean);
select tt.chk('D3 alert after the owner typed 3: 1 document older than 3 days (age 4), alert on', (:'a3'::jsonb->>'alert')::boolean and (:'a3'::jsonb->>'old_count')::int=1 and jsonb_array_length(:'a3'::jsonb->'items')=1 and (:'a3'::jsonb->'items'->0->>'age_days')::int=4
  and (:'a3'::jsonb->'items'->0->>'over_alert')::boolean);
select tt.chk('D3 alert with 4: age 4 is not older than 4 -> no alert; with 0: only the old one (the others are 0 days old)', not (:'a4'::jsonb->>'alert')::boolean and (:'a4'::jsonb->>'old_count')::int=0 and (:'a0'::jsonb->>'alert')::boolean and (:'a0'::jsonb->>'old_count')::int=1);
select tt.chk('D3 alert message in 3 modes, English has no Bangla', tt.noban(:'a3'::jsonb->'message'->>'en') and :'a3'::jsonb->'message'->>'bn' ~ '[ঀ-৿]' and :'a3'::jsonb->'message'->>'mix' ~ '[ঀ-৿]');
select tt.chk('D3 the typed number is cleared again (blank)', rule_num('acct_cost_wait_alert_days') is null);

\echo == D3 supply: manual needs a reason; a cost-right person (not an accounts manager) supplies, the owner's posting then books it once
set role authenticated; select tt.as(:'k');
select tt.err('D3 manual cost without a reason refused', format($$select cost_wait_supply96('wastage','%s','manual','[{"item_id":"%s","cost":14}]'::jsonb,null,'00000000-0000-0000-0000-0000000000f1')$$, :'w1id', :'gm'), 'reason_needed');
select tt.err('D3 a client id is needed', format($$select cost_wait_supply96('wastage','%s','item_average')$$, :'w1id'), 'client_id_needed');
select tt.err('D3 an unknown method is refused', format($$select cost_wait_supply96('wastage','%s','guess',null,null,'00000000-0000-0000-0000-0000000000f2')$$, :'w1id'), 'bad_method');
select tt.err('D3 "recommended" is not a method to supply with (the person chooses)', format($$select cost_wait_supply96('wastage','%s','recommended',null,null,'00000000-0000-0000-0000-0000000000f3')$$, :'w1id'), 'bad_method');
select tt.err('D3 a manual cost of 0 or a wrong item is refused', format($$select cost_wait_supply96('wastage','%s','manual','[{"item_id":"%s","cost":0}]'::jsonb,'x','00000000-0000-0000-0000-0000000000f4')$$, :'w1id', :'gm'), 'bad_manual');
select tt.err('D3 a manual cost missing for the item is refused (cost_unavailable)', format($$select cost_wait_supply96('wastage','%s','manual','[]'::jsonb,'x','00000000-0000-0000-0000-0000000000f5')$$, :'w1id'), 'cost_unavailable');
select tt.err('D3 an unknown document: nothing_waiting', $$select cost_wait_supply96('wastage','00000000-0000-0000-0000-000000000000','item_average',null,null,'00000000-0000-0000-0000-0000000000f6')$$, 'nothing_waiting');
select tt.err('D3 a bad kind is refused', $$select cost_wait_supply96('zz','1','item_average',null,null,'00000000-0000-0000-0000-0000000000f7')$$, 'bad_kind');
select cost_wait_supply96('wastage', :'w1id', 'manual', format('[{"item_id":"%s","cost":14}]', :'gm')::jsonb, 'quoted price from the supplier', '00000000-0000-0000-0000-0000000000f8') as sp1 \gset
select cost_wait_supply96('wastage', :'w1id', 'manual', format('[{"item_id":"%s","cost":14}]', :'gm')::jsonb, 'quoted price from the supplier', '00000000-0000-0000-0000-0000000000f8') as sp1b \gset
reset role;
select tt.chk('D3 W1 supplied by the cost-right person: manual 14 x 2 = 28, one ledger row, not posted yet (he is no accounts manager)', (:'sp1'::jsonb->>'rows')::int=1 and (:'sp1'::jsonb->>'total')::numeric=28 and not (:'sp1'::jsonb->>'posted')::boolean
  and (select unit_cost=14 and method='manual' and reason='quoted price from the supplier' and doc_kind='wastage' and doc_ref=:'w1id' and supplied_by=:'k'::uuid from ledger_cost_supply96 where ledger_id=(select id from stock_ledger where reason='wastage' and ref_id=:'w1id')));
select tt.chk('D3 same client id again: dup, no second row', (:'sp1b'::jsonb->>'dup')::boolean and (select count(*) from ledger_cost_supply96)=1);
select tt.chk('D3 the stock ledger row itself is untouched (cost still NULL, immutable); the books read the supplied cost through the view', (select unit_cost is null from stock_ledger where reason='wastage' and ref_id=:'w1id')
  and (select unit_cost=14 and cost_supplied from stock_ledger_eff96 where reason='wastage' and ref_id=:'w1id'));
select tt.err('D3 a supplied cost cannot be edited', $$update ledger_cost_supply96 set unit_cost=1$$, 'ledger_immutable');
select tt.err('D3 a supplied cost cannot be deleted', $$delete from ledger_cost_supply96$$, 'ledger_immutable');
select tt.err('D3 the ledger itself still refuses edits', $$update stock_ledger set unit_cost=1 where reason='wastage'$$, 'ledger_immutable');
select tt.chk('D3 audited: one audit_log insert row for the supply', (select count(*) from audit_log where table_name='ledger_cost_supply96' and action='insert')=1);
set role authenticated; select tt.as(:'k');
select tt.err('D3 supplying the same document again: nothing is waiting any more', format($$select cost_wait_supply96('wastage','%s','item_average',null,null,'00000000-0000-0000-0000-0000000000f9')$$, :'w1id'), 'nothing_waiting');
select tt.as(:'o');
select acct_post_pending(false) as pk1 \gset
select acct_post_pending(false) as pk2 \gset
reset role;
-- W1: Dr wastage 28 / Cr 1320 28, one entry
select tt.chk('D3 the owner posting books W1 once: Dr wastage 28 / Cr 1320 28 (source wastage / ref)', (:'pk1'::jsonb->'by_type'->>'wastage')::int=1 and tt.n('wastage')=1 and (:'pk2'::jsonb->>'posted')::int=0
  and (select sum(l.debit) from journal_entries e join journal_lines l on l.entry_id=e.id where e.source_type='wastage' and e.source_id=:'w1id')=28 and tt.jt('wastage','1320','c')=28);
set role authenticated; select tt.as(:'o');
select tt.err('D3 once posted, a second supply is refused (already_posted)', format($$select cost_wait_supply96('wastage','%s','item_average',null,null,'00000000-0000-0000-0000-0000000000fa')$$, :'w1id'), 'already_posted');
reset role;

\echo == D3 the other documents (owner is an accounts manager: the supply posts at once)
set role authenticated; select tt.as(:'o');
-- P1: 4 gum x 15 = 60 : Dr 1310 60 / Cr 1320 60 ; the cake two row gets 6 per piece (record)
select cost_wait_supply96('production', :'pid', 'item_average', null, 'average', '00000000-0000-0000-0000-0000000000a1') as sp2 \gset
-- W2: recipe standard 6 x 1 : Dr wastage 6 / Cr 1310 6
select cost_wait_supply96('wastage', :'w2id', 'recipe_standard', null, null, '00000000-0000-0000-0000-0000000000a2') as sp3 \gset
-- T1: gum average 15 x 3 = 45 : send Dr 1230 45 / Cr 1320 45 (place 1), receive Dr 1320 45 / Cr 1230 45 (place 2)
select cost_wait_supply96('transfer', :'t1', 'item_average', null, null, '00000000-0000-0000-0000-0000000000a3') as sp4 \gset
-- L1: gum opening 19 x 15 = 285 : Dr 1320 / Cr 3100
select cost_wait_supply96('ledger', :'l1id'::text, 'item_average', null, null, '00000000-0000-0000-0000-0000000000a4') as sp5 \gset
-- L2: sugar gain 3 x 30 = 90 : Dr 1320 90 / Cr 5110 90
select cost_wait_supply96('ledger', :'l2id'::text, 'item_average', null, null, '00000000-0000-0000-0000-0000000000a5') as sp6 \gset
-- L4: gum gain 2 x 18 = 36 (last purchase) : Dr 1320 36 / Cr 5110 36
select cost_wait_supply96('ledger', :'l4id'::text, 'last_purchase', null, null, '00000000-0000-0000-0000-0000000000a6') as sp7 \gset
-- W3 and L3 (glaze, nothing known): average / last purchase / recipe are refused, manual 8 with a reason
select tt.err('D3 glaze: item_average is unavailable (nothing invented)', format($$select cost_wait_supply96('wastage','%s','item_average',null,null,'00000000-0000-0000-0000-0000000000a7')$$, :'w3id'), 'cost_unavailable');
select tt.err('D3 glaze: last_purchase is unavailable', format($$select cost_wait_supply96('wastage','%s','last_purchase',null,null,'00000000-0000-0000-0000-0000000000a8')$$, :'w3id'), 'cost_unavailable');
select tt.err('D3 glaze: recipe_standard is unavailable', format($$select cost_wait_supply96('wastage','%s','recipe_standard',null,null,'00000000-0000-0000-0000-0000000000a9')$$, :'w3id'), 'cost_unavailable');
select cost_wait_supply96('wastage', :'w3id', 'manual', format('{"%s": 8}', :'gx')::jsonb, 'supplier quote', '00000000-0000-0000-0000-0000000000b1') as sp8 \gset
select cost_wait_supply96('ledger', :'l3id'::text, 'manual', '8'::jsonb, 'supplier quote', '00000000-0000-0000-0000-0000000000b2') as sp9 \gset
-- the old count loss: sugar average 30 x 1 : Dr 5110 30 / Cr 1320 30, dated 4 days ago
select cost_wait_supply96('ledger', :'oldid'::text, 'item_average', null, null, '00000000-0000-0000-0000-0000000000b3') as sp10 \gset
select acct_post_pending(false) as pz \gset
select cost_wait_list96() as lst3 \gset
select cost_wait_alert96() as al3 \gset
reset role;
select tt.chk('D3 every supply posted its document at once (posted true)', (:'sp2'::jsonb->>'posted')::boolean and (:'sp3'::jsonb->>'posted')::boolean and (:'sp4'::jsonb->>'posted')::boolean and (:'sp5'::jsonb->>'posted')::boolean
  and (:'sp6'::jsonb->>'posted')::boolean and (:'sp7'::jsonb->>'posted')::boolean and (:'sp8'::jsonb->>'posted')::boolean and (:'sp9'::jsonb->>'posted')::boolean and (:'sp10'::jsonb->>'posted')::boolean);
select tt.chk('D3 supply totals: production 60, W2 6, transfer 45, L1 285, L2 90, L4 36, W3 8, L3 40, old 30', (:'sp2'::jsonb->>'total')::numeric=60 and (:'sp3'::jsonb->>'total')::numeric=6 and (:'sp4'::jsonb->>'total')::numeric=45
  and (:'sp5'::jsonb->>'total')::numeric=285 and (:'sp6'::jsonb->>'total')::numeric=90 and (:'sp7'::jsonb->>'total')::numeric=36 and (:'sp8'::jsonb->>'total')::numeric=8 and (:'sp9'::jsonb->>'total')::numeric=40 and (:'sp10'::jsonb->>'total')::numeric=30);
select tt.chk('D3 production: the ingredient row(s) got 15 each and the cake two row 6 (from_ingredients); the stock average cache of cake two is NOT changed (stays blank)',
  (select count(*) from ledger_cost_supply96 where doc_kind='production' and method='item_average' and unit_cost=15)>=1 and (select unit_cost=6 and method='from_ingredients' from ledger_cost_supply96 where ledger_id=(select id from stock_ledger where reason='production_in' and ref_id=:'pid'))
  and (select avg_cost is null from stock_balance where item_id=:'c2'::uuid and location_id=1));
-- hand-computed journal: wastage 28 + 6 + 8 = 42 ; production 60 ; transfer 45 out + 45 in ; openings 70 (earlier) + 285 + 40 = 395 ; stock_adjust 90 + 36 (gain) and 30 (loss)
select tt.chk('D3 journal entries by kind: wastage 3, production 1, stock_transfer 2, stock_opening 3, stock_adjust 3', tt.n('wastage')=3 and tt.n('production')=1 and tt.n('stock_transfer')=2 and tt.n('stock_opening')=3 and tt.n('stock_adjust')=3);
select tt.chk('D3 wastage: Dr wastage 42 / Cr 1320 36 + Cr 1310 6', tt.jt('wastage','1320','c')=36 and tt.jt('wastage','1310','c')=6 and
  (select sum(l.debit) from journal_entries e join journal_lines l on l.entry_id=e.id where e.source_type='wastage' and e.reverses_id is null)=42);
select tt.chk('D3 production: Dr 1310 60 / Cr 1320 60', tt.jt('production','1310','d')=60 and tt.jt('production','1320','c')=60);
select tt.chk('D3 transfer pair through the clearing account, each side balanced alone and tagged: out place 1 Dr 1230 45 / Cr 1320 45 ; in place 2 Dr 1320 45 / Cr 1230 45; clearing nets 0',
  tt.jtl('stock_transfer','1230','d',1)=45 and tt.jtl('stock_transfer','1320','c',1)=45 and tt.jtl('stock_transfer','1320','d',2)=45 and tt.jtl('stock_transfer','1230','c',2)=45
  and tt.jt('stock_transfer','1230','d')=tt.jt('stock_transfer','1230','c'));
select tt.chk('D3 openings: Dr 1320 395 (70 + 285 + 40) / Cr 3100 395', tt.jt('stock_opening','1320','d')=395 and tt.jt('stock_opening','3100','c')=395);
select tt.chk('D3 count moves: Dr 1320 126 (90 + 36) + Cr 1320 30 ; Cr 5110 126 + Dr 5110 30', tt.jt('stock_adjust','1320','d')=126 and tt.jt('stock_adjust','1320','c')=30 and tt.jt('stock_adjust','5110','c')=126 and tt.jt('stock_adjust','5110','d')=30);
select tt.chk('D3 the old document posted at its own date (4 days ago)', (select e.entry_date from journal_entries e where e.source_type='stock_adjust' and e.source_id=:'oldid')=tt.today()-4);
select tt.chk('D3 waiting list is empty, no alert; the books wait for nothing', (:'lst3'::jsonb->>'total')::int=0 and not (:'al3'::jsonb->>'alert')::boolean and coalesce((:'pz'::jsonb->'waiting'->>'cost_missing')::int,0)=0 and jsonb_array_length(:'pz'::jsonb->'errors')=0);

\echo == closing: nothing posts twice, reports equal journals, trial balance balanced
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as pf \gset
select acct_trial_balance(null,null) as tb \gset
select acct_balance_sheet(tt.today()) as bs \gset
select acct_income_statement(tt.today()-5, tt.today(), null) as ist \gset
select inventory_vs_gl(tt.today(), null) as ivf \gset
reset role;
select tt.chk('closing: re-post posts 0, reverses 0; no source posted twice; every entry balances', (:'pf'::jsonb->>'posted')::int=0 and (:'pf'::jsonb->>'reversed')::int=0 and tt.unbalanced_entries()=0
  and not exists (select 1 from journal_entries where reverses_id is null group by source_type, source_id having count(*)>1));
select tt.chk('closing: trial balance balanced; its rows add up to the journal totals', (:'tb'::jsonb->>'balanced')::boolean
  and (select sum((r->>'dr')::numeric) from jsonb_array_elements(:'tb'::jsonb->'rows') r where not (r->>'is_group')::boolean) = (select sum(debit) from journal_lines)
  and (select sum((r->>'cr')::numeric) from jsonb_array_elements(:'tb'::jsonb->'rows') r where not (r->>'is_group')::boolean) = (select sum(credit) from journal_lines));
select tt.chk('closing: report == journal per account (trial balance row = journal sums)',
  (select bool_and((r->>'dr')::numeric = j.d and (r->>'cr')::numeric = j.c) from jsonb_array_elements(:'tb'::jsonb->'rows') r join (select a.code, sum(l.debit) d, sum(l.credit) c from journal_lines l join coa_accounts a on a.id=l.account_id group by a.code) j on j.code = r->>'code' where not (r->>'is_group')::boolean));
-- expenses: wastage 42 ; stock count gain/loss 5110 = 30 - 126 = -96 ; (no other expense posted)
select tt.chk('closing: income statement expense == journal (wastage 42, 5110 -96), balance sheet balanced', (:'ist'::jsonb->>'total_expense')::numeric = (select sum(l.debit-l.credit) from journal_lines l join coa_accounts a on a.id=l.account_id where a.type='expense')
  and (:'ist'::jsonb->>'total_expense')::numeric = -54 and (select (r->>'amount')::numeric from jsonb_array_elements(:'ist'::jsonb->'expense') r where r->>'code'='5110') = -96
  and not (:'bs'::jsonb->>'unbalanced')::boolean and (:'bs'::jsonb->>'difference')::numeric=0);
select tt.chk('closing: inventory_vs_gl has no unexplained part (the supplied-cost entries are counted)', (:'ivf'::jsonb->'total'->>'unexplained')::numeric=0);
select tt.chk('closing: entries memos in English have no Bangla characters', (select bool_and(tt.noban(memo)) from journal_entries where source_type in ('opening_stock96','wastage','production','stock_transfer','stock_opening','stock_adjust')));
select tt.chk('closing: cost secrecy: the browser roles cannot read the supply table, the ledger view or the decisions', not has_table_privilege('anon','ledger_cost_supply96','select') and not has_table_privilege('anon','stock_ledger_eff96','select')
  and not has_table_privilege('authenticated','opening_stock_actions96','select'));
-- the documented limit: the stock AVERAGE cost cache is not changed by a supplied cost. Finished goods: GL 250 + 60 production - 6 wastage = 304 ; valuation 250 (cake two: 9 pieces, no average) ; diff 54 = 9 x 6
select tt.chk('closing: documented limit - finished goods GL 304 vs valuation 250 (diff 54 = 9 pieces x 6; the cost record exists but the average cache is not changed); still unexplained 0',
  (select (r->>'gl')::numeric=304 and (r->>'valuation')::numeric=250 and (r->>'diff')::numeric=54 and (r->>'unexplained')::numeric=0 from jsonb_array_elements(:'ivf'::jsonb->'rows') r where r->>'key'='inv_finished'));

\echo == D3 with accounting switched off the cost is kept and nothing posts; when accounting is on again the posting books it once
reset role;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at) values (:'su'::uuid, 1, 1, null, 'count_adjust', 'count', 'off96', now());
select id as offid from stock_ledger where ref_id='off96' \gset
select tt.jt('stock_adjust','1320','d') as adj_before \gset
set role authenticated; select tt.as(:'o');
select set_rule('accounting_on','false') is null as acc0 \gset
select cost_wait_supply96('ledger', :'offid'::text, 'item_average', null, null, '00000000-0000-0000-0000-0000000000c1') as sp11 \gset
select set_rule('accounting_on','true') is null as acc1 \gset
select cost_wait_list96() as lst4 \gset
reset role;
select tt.n('stock_adjust') as nadj0 \gset
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as pq \gset
select acct_post_pending(false) as pq2 \gset
reset role;
select tt.chk('D3 accounting off: the cost (sugar average 30) is kept, nothing posts, it has its cost, so it leaves the cost-waiting list and waits only for the posting run', not (:'sp11'::jsonb->>'posted')::boolean and :'sp11'::jsonb->'post_run' = 'null'::jsonb and (:'sp11'::jsonb->>'total')::numeric=30
  and :'nadj0'::int=3 and (select count(*) from jsonb_array_elements(:'lst4'::jsonb->'items') x where x->>'ref'=:'offid'::text)=0);
select tt.chk('D3 accounting on again: the posting run books it once (Dr 1320 30 / Cr 5110 30), a second run posts nothing', (:'pq'::jsonb->'by_type'->>'stock_adjust')::int=1 and tt.n('stock_adjust')=4
  and tt.jt('stock_adjust','1320','d')=:'adj_before'::numeric+30 and (:'pq2'::jsonb->>'posted')::int=0 and tt.unbalanced_entries()=0);

\echo == D3 an item marked "cost really zero" (phase80) is a KNOWN cost: it never waits
set role authenticated; select tt.as(:'o');
select stock_opening(:'fz'::uuid,1,4,null) is not null as ofz \gset
select cost_wait_list96() as lz1 \gset
select item_cost_free_set(:'fz'::uuid, true, 'free sample', '00000000-0000-0000-0000-0000000000c2') is not null as fzset \gset
select cost_wait_list96() as lz2 \gset
reset role;
select tt.chk('D3 before the flag the opening of the free item waits (1 document); after "cost really zero" it does not wait', :'ofz' and :'fzset' and (:'lz1'::jsonb->>'total')::int=1 and (:'lz2'::jsonb->>'total')::int=0);
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
