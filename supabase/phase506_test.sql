-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase80_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase506_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY. Phase 506 tests (step S1: free-cost item flag, partner base switch, packaging_return_mode, dedicated intake bot).
--   ORDER="phase8 ... phase78 phase79 phase506" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> a80db
--   psql -h /tmp -p 5544 -U postgres -d a80db -qAt -f supabase/phase506_test.sql | grep -E 'FAIL|RESULT'
-- All numbers are hand-computed (comment above each block). Test data only, no person names. Place 1 only.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set p '00000000-0000-0000-0000-000000000002'
\set b '00000000-0000-0000-0000-000000000003'
\set x '00000000-0000-0000-0000-000000000004'
\set n '00000000-0000-0000-0000-000000000005'
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
create or replace function tt.amt(c jsonb, p bigint) returns numeric language sql as $$ select coalesce(sum((e->>'amount')::numeric),0) from jsonb_array_elements(c->'party_totals') e where (e->>'party_id')::bigint = p $$;
create or replace function tt.warn(c jsonb, code text) returns boolean language sql as $$ select exists (select 1 from jsonb_array_elements(c->'warnings') e where e->>'code' = code) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'p','sales2@s.app','{"full_name":"Sales"}'), (:'b','bot3@s.app','{"full_name":"Intake bot"}'),
 (:'x','bot4@s.app','{"full_name":"Old style bot"}'), (:'n','sales5@s.app','{"full_name":"Other sales"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'p','salesperson'),(:'x','salesperson'),(:'n','salesperson') on conflict do nothing;
insert into user_locations values (:'p',1),(:'x',1),(:'n',1) on conflict do nothing;

\echo == T0 shape, tags, defaults, privileges
select tt.chk('T0 phase80 is applied: bos80 line in each of the 7 re-created functions',
  (select bool_and(position('bos80' in pg_get_functiondef(f::regprocedure)) > 0) from unnest(array[
    'public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)', 'public._acct_docs(date)', 'public._cogs_lines72(date,date,int[])', 'public.partner_calculate(bigint,date,date,jsonb)',
    'public.partner_settlement_save(bigint,date,date,jsonb,text,uuid)', 'public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)',
    'public.online_order_save(uuid,uuid,int,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text)']) f));
with want(fn, tag) as (values
  ('production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)', 'bos72'), ('production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)', 'bos73'), ('production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)', 'bos74'),
  ('_acct_docs(date)', 'bos50'), ('_acct_docs(date)', 'bos52'), ('_acct_docs(date)', 'bos72'), ('_acct_docs(date)', 'bos74'), ('_cogs_lines72(date,date,int[])', 'bos72'))
select tt.chk('T0 the older tags (bos50/52/72/73/74) survive in the re-created functions: ' || fn || ' ' || tag, position(tag in pg_get_functiondef(('public.' || fn)::regprocedure)) > 0 or tag = 'bos72' and fn like '_cogs%') from want;
select tt.chk('T0 defaults = today: partner_base_estimate warn, packaging_return_mode none, no item marked free',
  rule_txt('partner_base_estimate') = 'warn' and rule_txt('packaging_return_mode') = 'none' and (select count(*) from item_cost_flags) = 0);
select tt.chk('T0 internal helpers closed to browsers, screen functions open, anon none',
  not has_function_privilege('authenticated','public._cost_free80(uuid)','execute') and not has_function_privilege('authenticated','public._oo_gate80(int,boolean)','execute') and not has_function_privilege('authenticated','public._ret_pack80(uuid,uuid,jsonb)','execute')
  and has_function_privilege('authenticated','public.item_cost_free_set(uuid,boolean,text,uuid)','execute') and not has_function_privilege('anon','public.item_cost_free_set(uuid,boolean,text,uuid)','execute')
  and not has_function_privilege('anon','public.intake_bot_create(uuid,int)','execute') and not has_function_privilege('anon','public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)','execute'));
select tt.chk('T0 new tables: RLS on, browsers can only read',
  (select bool_and(relrowsecurity) from pg_class where relname in ('item_cost_flags','sale_return_packaging80'))
  and not has_table_privilege('authenticated','public.item_cost_flags','insert') and not has_table_privilege('authenticated','public.item_cost_flags','update') and not has_table_privilege('authenticated','public.sale_return_packaging80','insert')
  and not has_table_privilege('anon','public.item_cost_flags','select'));
select tt.chk('T0 role intake_bot has ONLY the intake form right (enter) and nothing on POS', exists (select 1 from role_form_perms where role_code='intake_bot' and form_code='ONLINE_INTAKE' and can_enter and not can_view and not can_approve)
  and not exists (select 1 from role_form_perms where role_code='intake_bot' and form_code <> 'ONLINE_INTAKE'));

\echo == setup: accounting on, items, stock at place 1
set role authenticated; select tt.as(:'o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
reset role;
insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values
 ('I80-FL','Flour','Flour','kg','kg',0,true,'raw_material'),
 ('I80-WA','Water','Water','kg','kg',0,true,'raw_material'),
 ('I80-DR','Drink','Drink','kg','kg',50,true,'finished_good'),
 ('I80-IC','Ice','Ice','kg','kg',10,true,'finished_good'),
 ('I80-CK','Cake','Cake','kg','kg',100,true,'finished_good'),
 ('I80-BX','Box','Box','pc','pc',0,true,'packaging');
select id as fl from items where code='I80-FL' \gset
select id as wa from items where code='I80-WA' \gset
select id as dr from items where code='I80-DR' \gset
select id as ic from items where code='I80-IC' \gset
select id as ck from items where code='I80-CK' \gset
select id as bx from items where code='I80-BX' \gset
set role authenticated; select tt.as(:'o');
-- Flour 100 kg @ 40 ; Water 100 kg, cost BLANK ; Ice 50 kg, cost BLANK ; Cake 50 kg @ 30 ; Box 100 @ 2
select stock_opening(:'fl'::uuid,1,100,40) is not null as a1 \gset
select stock_opening(:'wa'::uuid,1,100,null) is not null as a2 \gset
select stock_opening(:'ic'::uuid,1,50,null) is not null as a3 \gset
select stock_opening(:'ck'::uuid,1,50,30) is not null as a4 \gset
select stock_opening(:'bx'::uuid,1,100,2) is not null as a5 \gset
select tt.chk('setup: openings', :'a1' and :'a2' and :'a3' and :'a4' and :'a5');

\echo == A free-cost flag: who may set it, reason, idempotency, audit, cost secrecy
select tt.as(:'p');
select tt.err('A1 a salesperson (no cost right) cannot mark an item', format($$select item_cost_free_set(%L::uuid,true,'water is free')$$, :'wa'), 'not allowed');
select tt.err('A1 and cannot read the list', $$select item_cost_flags_list()$$, 'not allowed');
select tt.as(:'o');
select tt.err('A2 marking needs a reason', format($$select item_cost_free_set(%L::uuid,true,'  ')$$, :'wa'), 'reason_required');
select tt.err('A2 unknown item refused', $$select item_cost_free_set(gen_random_uuid(),true,'water is free')$$, 'not_found');
select tt.chk('A3 before the flag: the cost_missing list names Water and Ice (tracked, cost blank), not Flour (cost 40) or Cake',
  (select count(*) from jsonb_array_elements(cost_unknown_items(1)) e where e->>'code' in ('I80-WA','I80-IC') and e->>'label'='cost_missing') = 2
  and not exists (select 1 from jsonb_array_elements(cost_unknown_items(1)) e where e->>'code' in ('I80-FL','I80-CK')));
\echo == B production_requires_cost = refuse: a blank-cost ingredient refuses, a marked one does not
-- recipe Drink: 10 kg from 6 kg Flour + 4 kg Water
select (recipe_save(null, :'dr'::uuid, 10, null, 'RD', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'fl','qty',6,'waste_pct',0), jsonb_build_object('ingredient_item_id',:'wa','qty',4,'waste_pct',0)))->>'id')::uuid as rd \gset
select set_rule('production_requires_cost','"refuse"') is null as rf \gset
select tt.err('B1 Water cost blank + refuse: cost_missing (as before this phase)', format($$select production_post(1,%L::uuid,1,gen_random_uuid())$$, :'rd'), 'cost_missing');
select item_cost_free_set(:'wa'::uuid, true, 'tap water, no purchase cost', '10000000-0000-0000-0000-0000000000a1') as fs1 \gset
select tt.chk('A4 marked: answer says cost_free', (:'fs1'::jsonb->>'cost_free')::boolean);
select tt.chk('A4 same client id again = dup, nothing changes', (item_cost_free_set(:'wa'::uuid, true, 'tap water, no purchase cost', '10000000-0000-0000-0000-0000000000a1')->>'dup')::boolean);
select tt.chk('A4 same value without client id = noop', (item_cost_free_set(:'wa'::uuid, true, 'again')->>'noop')::boolean);
select tt.chk('A4 the list shows Water with its reason; cost_missing list no longer names Water but still Ice',
  exists (select 1 from jsonb_array_elements(item_cost_flags_list()) e where e->>'code'='I80-WA' and e->>'reason' = 'tap water, no purchase cost')
  and not exists (select 1 from jsonb_array_elements(cost_unknown_items(1)) e where e->>'code'='I80-WA') and exists (select 1 from jsonb_array_elements(cost_unknown_items(1)) e where e->>'code'='I80-IC'));
reset role;
select tt.chk('A5 audit_log has the insert of the flag row', exists (select 1 from audit_log where table_name='item_cost_flags' and record_id = :'wa' and action='insert'));
select tt.chk('A5 other items untouched: 1 flag row, only Water', (select count(*) from item_cost_flags) = 1);
-- cost secrecy: a user without the cost right sees no flag row through the table either (RLS)
set role authenticated; select tt.as(:'p');
select tt.chk('A6 RLS: a user without the cost right reads 0 flag rows', (select count(*) from item_cost_flags) = 0);
select tt.as(:'o');
select tt.chk('A6 RLS: the owner reads 1', (select count(*) from item_cost_flags) = 1);

\echo == B2 the marked ingredient is a KNOWN cost of 0
-- Drink: 6 kg Flour x 40 = 240 ; Water 4 kg x 0 = 0 ; unit cost 240 / 10 = 24
select production_post(1,:'rd'::uuid,1,gen_random_uuid()) as pd \gset
select (:'pd'::jsonb->>'run_id') as rund \gset
select tt.chk('B2 refuse mode: the run is accepted, cost_complete true, unit cost 24', (:'pd'::jsonb->>'cost_complete')::boolean and (:'pd'::jsonb->>'unit_cost')::numeric = 24);
reset role;
select tt.chk('B2 ledger: Drink IN 10 kg at 24 ; Flour 94 ; Water 96', (select unit_cost from stock_ledger where ref_type='production' and ref_id=:'rund' and reason='production_in')=24
  and (select qty from stock_balance where item_id=:'fl'::uuid and location_id=1)=94 and (select qty from stock_balance where item_id=:'wa'::uuid and location_id=1)=96);
select tt.chk('B2 run snapshot: material 240, complete', (select material_cost=240 and cost_complete from production_runs where id=:'rund'::uuid));
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as pj \gset
reset role;
select tt.chk('B3 journal: the run is posted with NO cogs_missing flag and no error; Dr finished 240 = Cr raw 240',
  jsonb_array_length(:'pj'::jsonb->'errors') = 0 and tt.jl('production',:'rund','1310','d')=240 and tt.jl('production',:'rund','1320','c')=240
  and not exists (select 1 from journal_entries where source_type='production' and source_id=:'rund' and flags='cogs_missing'));
-- the mark is the only difference: a second item Juice (5 kg Flour + 5 kg Water per 10 kg) is produced once with Water un-marked and once marked (read the posting source before it is posted)
reset role;
insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('I80-JU','Juice','Juice','kg','kg',30,true,'finished_good');
select id as ju from items where code='I80-JU' \gset
set role authenticated; select tt.as(:'o');
select (recipe_save(null, :'ju'::uuid, 10, null, 'RJ', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'fl','qty',5,'waste_pct',0), jsonb_build_object('ingredient_item_id',:'wa','qty',5,'waste_pct',0)))->>'id')::uuid as rj \gset
select set_rule('production_requires_cost',null) is null as rfw \gset
select item_cost_free_set(:'wa'::uuid, false, null) is not null as un \gset
select (production_post(1,:'rj'::uuid,1,gen_random_uuid())->>'run_id') as runj1 \gset
reset role;
select exists (select 1 from _acct_docs(tt.today()-5) d where d.source_type='production' and d.source_id=:'runj1' and d.flags='cogs_missing') as flag1 \gset
set role authenticated; select tt.as(:'o');
select item_cost_free_set(:'wa'::uuid, true, 'tap water, no purchase cost') is not null as re \gset
select (production_post(1,:'rj'::uuid,1,gen_random_uuid())->>'run_id') as runj2 \gset
reset role;
select tt.chk('B4 Water un-marked: _acct_docs flags that run cogs_missing (read before the mark was set again)', :'flag1');
select tt.chk('B4 Water marked: the next identical run has NO cogs_missing flag, and its unit cost is known (5 x 40 / 10 = 20)', not exists (select 1 from _acct_docs(tt.today()-5) d where d.source_type='production' and d.source_id=:'runj2' and d.flags='cogs_missing')
  and (select unit_cost from stock_ledger where ref_type='production' and ref_id=:'runj2' and reason='production_in')=20 and (select unit_cost is null from stock_ledger where ref_type='production' and ref_id=:'runj1' and reason='production_in'));
select tt.chk('B4 audit_log kept every change of the Water flag (insert + 2 updates)', (select count(*) from audit_log where table_name='item_cost_flags' and record_id=:'wa') = 3);
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as pjx \gset
reset role;
select tt.chk('B4 posting the two Juice runs raises no error and everything balances', jsonb_array_length(:'pjx'::jsonb->'errors') = 0 and tt.unbalanced_entries() = 0);

\echo == C reports: a sold item with a blank cost is "unknown cost revenue" until it is marked free
-- sale 1: 5 kg Ice @ 10 = 50 revenue, cost unknown. sale 2: 2 kg Drink @ 50 = 100 revenue, cost 2 x 24 = 48
set role authenticated; select tt.as(:'o');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":5,"price":10}]',:'ic')::jsonb,0,'[{"mode":"cash","amount":50}]',null,null,'retail',null,false)->>'id' as si \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":50}]',:'dr')::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)->>'id' as sd2 \gset
select profit_source_check(tt.today(), tt.today(), 1) as ps1 \gset
select tt.chk('C1 Ice not marked: revenue 150, COGS 48, unknown-cost revenue 50 (provisional)', (:'ps1'::jsonb->>'net_revenue')::numeric=150 and (:'ps1'::jsonb->>'report_cogs')::numeric=48 and (:'ps1'::jsonb->>'unknown_cost_rev')::numeric=50);
select acct_income_statement(tt.today(), tt.today(), 1) as is1 \gset
select tt.chk('C1 income statement: unknown_cost_rev 50, provisional', (:'is1'::jsonb->>'unknown_cost_rev')::numeric=50 and (:'is1'::jsonb->>'provisional')::boolean);
select item_cost_free_set(:'ic'::uuid, true, 'ice made from tap water, no cost') is not null as fi \gset
select profit_source_check(tt.today(), tt.today(), 1) as ps2 \gset
select tt.chk('C2 Ice marked free: unknown-cost revenue 0, COGS still 48 (Ice costs 0), net revenue 150', (:'ps2'::jsonb->>'unknown_cost_rev')::numeric=0 and (:'ps2'::jsonb->>'report_cogs')::numeric=48 and (:'ps2'::jsonb->>'net_revenue')::numeric=150);
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd_
select tt.chk('C2 biz_daily: revenue 150, costed revenue 150, COGS 48', :'bd_revenue'::numeric=150 and :'bd_costed_rev'::numeric=150 and :'bd_cogs'::numeric=48);
select acct_post_pending(false) as pj2 \gset
reset role;
select tt.chk('C3 the Ice sale posts without a cogs_missing flag (revenue 50, no COGS line)', not exists (select 1 from journal_entries where source_type='sale' and source_id=:'si' and flags='cogs_missing') and tt.jl('sale',:'si','5000','d') = 0);
select tt.chk('C3 the Drink sale: COGS 48', tt.jl('sale',:'sd2','5000','d') = 48);
select tt.chk('C3 every entry balanced', tt.unbalanced_entries() = 0);
set role authenticated; select tt.as(:'o');
select tt.chk('C4 production_requires_cost back to the default warn', rule_txt('production_requires_cost')='warn');

\echo == D partner profit base: estimated cost of goods
-- item Pa untracked with list cost 60 -> NO stock-ledger cost -> the cost of goods is the ESTIMATE : sale of 10 kg @ 100 = 1000, estimate 600, gross profit 400
reset role;
insert into items (code,name_bn,name_en,unit,sell_price,tracked,sellable) values ('I80-PA','Pa','Item Pa','kg',100,false,true);
select id as ip from items where code='I80-PA' \gset
insert into item_costs (item_id, cost_price) values (:'ip', 60) on conflict (item_id) do update set cost_price = 60;
insert into sales (client_id,location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,paid,status) values
 (gen_random_uuid(),1,9801,'2026-01-10','2026-01-10 10:00+06',format('[{"item_id":"%s","qty":10,"price":100,"unit":"kg","amount":1000}]',:'ip')::jsonb,1000,0,1000,'cash',:'o',1000,'done');
set role authenticated; select tt.as(:'o');
select partner_party_save(null,'Party O','company',null,null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pa \gset
select partner_party_save(null,'Party F','individual',null,null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pd \gset
select partner_venture_save(null,'Place deal','Place deal','location',1,'franchise','2026-01-01',null,'draft',null,gen_random_uuid()) ->> 'id' as v2 \gset
-- agreement G: split of the GROSS PROFIT 40/60 ; agreement R: royalty 10% of net sales (no profit base)
select (partner_agreement_save(null,:v2,'Gross profit deed','2026-01-01',null,'[]'::jsonb,null,gen_random_uuid()) ->> 'id')::bigint as ag \gset
select partner_agreement_party_set(:ag,:pa::bigint,'owner',null,null) is not null as pp1 \gset
select partner_agreement_party_set(:ag,:pd::bigint,'franchisee',null,null) is not null as pp2 \gset
select partner_rule_save(:ag,null,'Base gross profit','base','{"base":"gross_profit"}'::jsonb) is not null as r1 \gset
select partner_rule_save(:ag,null,'40/60','split',format('{"shares":[{"party_id":%s,"percent":40},{"party_id":%s,"percent":60}]}',:pa,:pd)::jsonb) is not null as r2 \gset
select partner_agreement_activate(:ag) is not null as act \gset
select partner_calculate(:ag,'2026-01-01','2026-01-31') as c1 \gset
select tt.chk('D1 default warn: gross profit 400 is computed from the estimate, shared 160 / 240', (:'c1'::jsonb #>> '{bases,gross_profit}')::numeric=400 and tt.amt(:'c1'::jsonb,:pa)=160 and tt.amt(:'c1'::jsonb,:pd)=240 and :'c1'::jsonb->>'status'='ok');
select tt.chk('D1 and it carries the estimated_base warning: detail 600, refuse flag false', tt.warn(:'c1'::jsonb,'estimated_base')
  and (select (e->>'detail')::numeric=600 and not (e->>'refuse')::boolean from jsonb_array_elements(:'c1'::jsonb->'warnings') e where e->>'code'='estimated_base'));
select partner_settlement_save(:ag,'2026-01-01','2026-01-31',null,'warn mode',gen_random_uuid()) ->> 'id' as st1 \gset
select tt.chk('D2 warn mode: the settlement is saved as before', :'st1' is not null and (select total_distributable from partner_settlements where id=:'st1'::bigint)=400);
select partner_settlement_void(:st1::bigint,'test redo') is not null as vd \gset
select set_rule('partner_base_estimate','"refuse"') is null as rr \gset
select partner_calculate(:ag,'2026-01-01','2026-01-31') as c2 \gset
select tt.chk('D3 refuse: the preview still computes (400) and says refuse = true', (:'c2'::jsonb #>> '{bases,gross_profit}')::numeric=400 and (select (e->>'refuse')::boolean from jsonb_array_elements(:'c2'::jsonb->'warnings') e where e->>'code'='estimated_base'));
select tt.err('D3 refuse: saving the settlement is refused (base_estimated)', format($$select partner_settlement_save(%s,'2026-01-01','2026-01-31',null,'refuse mode')$$, :ag), 'base_estimated');
select partner_settlement_save(:ag,'2026-01-01','2026-01-31','{"gross_profit":400}'::jsonb,'typed base',gen_random_uuid()) ->> 'id' as st2 \gset
select tt.chk('D4 refuse + a typed manual gross profit: saved (the owner states the base)', :'st2' is not null);
select partner_settlement_void(:st2::bigint,'test redo 2') is not null as vd2 \gset
-- a deed on net sales only is not touched by the switch
select (partner_agreement_save(null,:v2,'Royalty deed','2026-02-01',null,'[]'::jsonb,null,gen_random_uuid()) ->> 'id')::bigint as ag2 \gset
select partner_agreement_party_set(:ag2,:pa::bigint,'owner',null,null) is not null as pq1 \gset
select partner_agreement_party_set(:ag2,:pd::bigint,'franchisee',null,null) is not null as pq2 \gset
select partner_rule_save(:ag2,null,'Base net sales','base','{"base":"net_sales"}'::jsonb) is not null as q1 \gset
select partner_rule_save(:ag2,null,'All to owner','split',format('{"shares":[{"party_id":%s,"percent":100}]}',:pa)::jsonb) is not null as q2 \gset
select partner_agreement_activate(:ag2) is not null as act2 \gset
reset role;
insert into sales (client_id,location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,paid,status) values
 (gen_random_uuid(),1,9802,'2026-02-10','2026-02-10 10:00+06',format('[{"item_id":"%s","qty":10,"price":100,"unit":"kg","amount":1000}]',:'ip')::jsonb,1000,0,1000,'cash',:'o',1000,'done');
set role authenticated; select tt.as(:'o');
select partner_settlement_save(:ag2,'2026-02-01','2026-02-28',null,'net sales base',gen_random_uuid()) ->> 'id' as st3 \gset
select tt.chk('D5 refuse + a net-sales base: saved (no profit base is used)', :'st3' is not null and (select total_distributable from partner_settlements where id=:'st3'::bigint)=1000);
select set_rule('partner_base_estimate',null) is null as rr0 \gset
select tt.chk('D6 default warn again', rule_txt('partner_base_estimate')='warn');

\echo == E packaging on a sale return
-- Cake sells 3 kg @ 100 ; 1 Box per kg of Cake leaves the stock at the sale (packaging_consume_on = sale) ; Box 100 @ 2 -> 97
select packaging_set(:'ck'::uuid, :'bx'::uuid, 1, 'sale') is not null as pk1 \gset
select set_rule('packaging_consume_on','"sale"'::jsonb) is null as pkon \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":3,"price":100}]',:'ck')::jsonb,0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false)->>'id' as sk \gset
reset role;
select tt.chk('E0 the sale took 3 Box out: Box 97', (select qty from stock_balance where item_id=:'bx'::uuid and location_id=1)=97);
set role authenticated; select tt.as(:'o');
-- mode none (default): return 1 kg -> Cake back, Box stays 97, no record
select sale_return(gen_random_uuid(),:'sk'::uuid,format('[{"item_id":"%s","qty":1}]',:'ck')::jsonb,'damaged','r1','cash') ->> 'id' as r1 \gset
reset role;
select tt.chk('E1 none (default): Box stays 97, no packaging record, Cake 48', (select qty from stock_balance where item_id=:'bx'::uuid and location_id=1)=97 and (select count(*) from sale_return_packaging80)=0
  and (select qty from stock_balance where item_id=:'ck'::uuid and location_id=1)=48);
-- mode restore: return 1 kg (second return) -> Box +1 = 98 ; record 1
set role authenticated; select tt.as(:'o');
select set_rule('packaging_return_mode','"restore"'::jsonb) is null as m1 \gset
select sale_return(gen_random_uuid(),:'sk'::uuid,format('[{"item_id":"%s","qty":1}]',:'ck')::jsonb,'damaged','r2','cash') ->> 'id' as r2 \gset
reset role;
select tt.chk('E2 restore: Box 98 (+1), one record mode restore qty 1; the ledger row is on the return (ref sale_return) at the sale cost 2',
  (select qty from stock_balance where item_id=:'bx'::uuid and location_id=1)=98 and (select count(*) from sale_return_packaging80 where return_id=:'r2'::uuid and mode='restore' and qty=1 and item_id=:'bx'::uuid)=1
  and (select unit_cost from stock_ledger where ref_type='sale_return' and ref_id=:'r2' and item_id=:'bx'::uuid)=2);
-- third return of the last kilo: Box +1 = 99 ; and the cap: the sale took out 3 and 2 were already settled by returns 2 and 3 only
set role authenticated; select tt.as(:'o');
select sale_return(gen_random_uuid(),:'sk'::uuid,format('[{"item_id":"%s","qty":1}]',:'ck')::jsonb,'damaged','r3','cash') ->> 'id' as r3 \gset
select tt.err('E3 the whole sale is returned: a 4th kilo is refused as before', format($$select sale_return(gen_random_uuid(),%L::uuid,'[{"item_id":"%s","qty":1}]'::jsonb,'damaged','r4','cash')$$, :'sk', :'ck'), 'return_exceeds_sale');
select acct_post_pending(false) as pj3 \gset
reset role;
select tt.chk('E3 Box 99 after the third return (3 sold out, 2 restored)', (select qty from stock_balance where item_id=:'bx'::uuid and location_id=1)=99 and (select count(*) from sale_return_packaging80 where mode='restore')=2);
-- journal of return 2: Cake 1 x 30 = 30 and Box 1 x 2 = 2 come back to stock
select tt.chk('E4 books: the return entry has Dr packaging 2 (restored Box) and finished goods 30; every entry balanced', tt.jl('sale_return',:'r2','1330','d')=2 and tt.jl('sale_return',:'r2','1310','d')=30 and tt.unbalanced_entries()=0);
-- void the 2nd return: its Box comes out again (98) and the record no longer counts against the cap
set role authenticated; select tt.as(:'o');
select void_sale_return(:'r2'::uuid,'entered by mistake') ->> 'status' as vs \gset
reset role;
select tt.chk('E5 void of the restoring return takes its Box out again: Box 98; the record stays (append-only)', :'vs'='void' and (select qty from stock_balance where item_id=:'bx'::uuid and location_id=1)=98 and (select count(*) from sale_return_packaging80 where return_id=:'r2'::uuid)=1);
select tt.err('E5 the record can not be changed or deleted', $$delete from sale_return_packaging80$$, 'append_only');
-- mode wastage: a new sale of 2 kg (Box 98 -> 96), return 1 kg -> Box stays 96, a wastage record, a yellow exception
set role authenticated; select tt.as(:'o');
select set_rule('packaging_return_mode','"wastage"'::jsonb) is null as m2 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',:'ck')::jsonb,0,'[{"mode":"cash","amount":200}]',null,null,'retail',null,false)->>'id' as sk2 \gset
select sale_return(gen_random_uuid(),:'sk2'::uuid,format('[{"item_id":"%s","qty":1}]',:'ck')::jsonb,'damaged','w1','cash') ->> 'id' as w1 \gset
reset role;
select tt.chk('E6 wastage: Box 96 (not restored), one record mode wastage qty 1, a yellow exception return_packaging_wastage',
  (select qty from stock_balance where item_id=:'bx'::uuid and location_id=1)=96 and (select count(*) from sale_return_packaging80 where return_id=:'w1'::uuid and mode='wastage' and qty=1)=1
  and exists (select 1 from exceptions where flag_code='return_packaging_wastage' and sale_id=:'sk2'::uuid and level='yellow'));
-- browsers: the record table is readable only with POS view at the place; an unrelated role sees nothing
set role authenticated; select tt.as(:'p');
select tt.chk('E7 a salesperson of the place can read the records, a user without any POS right reads none',
  (select count(*) from sale_return_packaging80) = 3);
select tt.as(:'b');
select tt.chk('E7 the intake bot (no POS right) reads none', (select count(*) from sale_return_packaging80) = 0);
select tt.as(:'o'); select set_rule('packaging_return_mode',null) is null as m0 \gset
select set_rule('packaging_consume_on','"off"'::jsonb) is null as pkoff \gset
select tt.chk('E8 default none again', rule_txt('packaging_return_mode')='none');
reset role;

\echo == F dedicated intake bot: can create online orders, cannot enter POS
set role authenticated; select tt.as(:'p');
select tt.err('F1 staff cannot set up a bot', format($$select intake_bot_create(%L::uuid,1)$$, :'b'), 'not allowed');
select tt.as(:'o');
select tt.err('F1 the owner cannot be a bot', format($$select intake_bot_create(%L::uuid,1)$$, :'o'), 'owner_cannot_be_bot');
select tt.err('F1 a user who already holds a POS-enter role is refused', format($$select intake_bot_create(%L::uuid,1)$$, :'n'), 'bot_has_pos_role');
select tt.err('F1 unknown place refused', format($$select intake_bot_create(%L::uuid,9999)$$, :'b'), 'location_not_found');
select intake_bot_create(:'b'::uuid, 1) as cb \gset
select tt.chk('F2 owner one-step setup: role intake_bot, place 1, bot active', (:'cb'::jsonb->>'role')='intake_bot');
select intake_bot_check(:'b'::uuid) as chb \gset
select tt.chk('F2 check says: is_bot, has the intake role, NO POS enter/approve right', (:'chb'::jsonb->>'is_bot')::boolean and (:'chb'::jsonb->>'has_intake_role')::boolean and not (:'chb'::jsonb->>'pos_enter')::boolean);
select tt.chk('F2 the setup is audited (user role + place)', exists (select 1 from audit_log where table_name='user_roles' and detail::text like '%intake_bot%') or exists (select 1 from audit_log where table_name='intake_bots'));
select tt.chk('F2 paste-twice style: setting up the same bot again is harmless', (intake_bot_create(:'b'::uuid, 1)->>'active')::boolean);
select set_rule('inbox_on','true') is null as ri \gset
select set_rule('online_orders_on','true') is null as ro \gset
select set_rule('web_form_on','true') is null as rw \gset
select sales_channel_save(null,'webform','web_form',null,'Web form',1,null,'FORM1',true) ->> 'id' as chid \gset
select sales_channel_save(null,'phoneline','phone',null,'Phone',1,null,null,true) ->> 'id' as chph \gset
select tt.as(:'b');
select web_order_submit('webform',gen_random_uuid(),'Web Cust','01811000001','Dhaka 5','home',format('[{"item_id":"%s","qty":2}]',:'ck')::jsonb,'note') as wo \gset
select tt.chk('F3 the bot creates a web order (server-side price 2 x 100 = 200)', (:'wo'::jsonb->>'ok')::boolean and (:'wo'::jsonb->>'subtotal')::numeric=200);
select online_order_save2(null, gen_random_uuid(), 1, :chph::int, 'Phone Cust', '01811000002', 'Dhaka 6', format('[{"item_id":"%s","qty":1}]',:'ck')::jsonb, 'home', null, null, 0, 0, 0, null, null, 'phone order') ->> 'id' as ph \gset
select tt.chk('F3 the bot creates an order on a phone channel directly too', :'ph' is not null);
reset role;
select tt.chk('F3 both orders exist with created_by = the bot', (select count(*) from online_orders where created_by=:'b'::uuid)=2);
set role authenticated; select tt.as(:'b');
select tt.err('F4 the bot can NOT edit an order', format($$select online_order_save2(%L::uuid, null, 1, %s, 'Phone Cust', '01811000002', 'Dhaka 7', '[{"item_id":"%s","qty":1}]'::jsonb, 'home', null, null, 0, 0, 0, null, null, 'x')$$, :'ph', :'chph', :'ck'), 'not allowed');
select tt.err('F4 the bot can NOT confirm / pack / deliver an order', format($$select online_order_status(%L::uuid,'confirmed',null)$$, :'ph'), 'not allowed');
select tt.err('F4 the bot can NOT sell at the counter', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":100}]'::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)$$, :'ck'), 'not allowed');
select tt.err('F4 the bot can NOT read the inbox or the order list', $$select inbox_list(1)$$, 'not allowed');
select tt.err('F4 the bot can NOT return a sale', format($$select sale_return(gen_random_uuid(),%L::uuid,'[{"item_id":"%s","qty":1}]'::jsonb,'damaged','x','cash')$$, :'sk2', :'ck'), 'not allowed');
select tt.chk('F4 the bot has no POS form right at all', not public.can_do('POS','view') and not public.can_do('POS','enter') and public.can_do('ONLINE_INTAKE','enter'));
select tt.as(:'n');
select tt.err('F5 a normal staff member without the bot flag still cannot use the intake entry', format($$select web_order_submit('webform',gen_random_uuid(),'A','01811000009','x','home','[{"item_id":"%s","qty":1}]'::jsonb,null)$$, :'ck'), 'not allowed');
select tt.as(:'p');
select tt.chk('F5 a salesperson (POS enter) still creates online orders as before (today)', (online_order_save2(null, gen_random_uuid(), 1, :chph::int, 'Walk Cust', '01811000003', 'Dhaka 8', format('[{"item_id":"%s","qty":1}]',:'ck')::jsonb, 'home', null, null, 0, 0, 0, null, null, 'by staff') ->> 'id') is not null);
-- an old-style bot (flag + a salesperson role, as phase76 allowed) keeps working: nothing is taken away from an existing setup
select tt.as(:'o'); select intake_bot_set(:'x'::uuid, true) is not null as bx0 \gset
select tt.as(:'x');
select tt.chk('F6 old-style bot (salesperson role + flag) still creates a web order', (web_order_submit('webform',gen_random_uuid(),'Old Cust','01811000004','Dhaka 9','home',format('[{"item_id":"%s","qty":1}]',:'ck')::jsonb,null)->>'ok')::boolean);
select tt.as(:'o');
select set_rule('online_orders_on','false') is null as rof \gset
select tt.as(:'b');
select tt.err('F7 module off', format($$select online_order_save2(null, gen_random_uuid(), 1, %s, 'P', '01811000005', 'D', '[{"item_id":"%s","qty":1}]'::jsonb, 'home', null, null, 0, 0, 0, null, null, null)$$, :'chph', :'ck'), 'module_off');
select tt.as(:'o'); select set_rule('online_orders_on','true') is null as ro2 \gset
reset role;
select tt.chk('F8 every entry still balanced at the end', tt.unbalanced_entries() = 0);

select count(*) filter (where ok) as pass, count(*) filter (where not ok) as fail from tt.res \gset
\echo RESULT :pass pass :fail fail
select name from tt.res where not ok;
