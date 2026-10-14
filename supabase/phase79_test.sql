-- FRESH DB ONLY. Phase 79 tests (INTEGRATION of phases 72..78: the merged function bodies keep EVERY tagged change).
--   ORDER="phase8 ... phase71 phase72 phase73 phase74 phase75 phase76 phase77 phase78 phase79" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> a79db
--   psql -h /tmp -p 5544 -U postgres -d a79db -qAt -f supabase/phase79_test.sql | grep -E 'FAIL|RESULT'
-- All numbers are hand-computed (comment above each block). Test data only, no person names. Place 1 only.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set ap '00000000-0000-0000-0000-000000000002'
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
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'ap','appr2@s.app','{"full_name":"Approver"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'ap','recipe_approver') on conflict do nothing;
insert into user_locations values (:'ap',1) on conflict do nothing;

\echo == T0 every tagged block of phases 72..78 survives in the final function bodies
select tt.chk('T0 phase79 is applied (the guard passed and the final bodies are there)', position('bos72' in pg_get_functiondef('public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)'::regprocedure))>0);
with want(fn, tag) as (values
  ('_acct_docs(date)', 'bos50'),
  ('_acct_docs(date)', 'bos52'),
  ('_acct_docs(date)', 'bos72'),
  ('_acct_docs(date)', 'bos74'),
  ('_p27_pl(date,date,int[])', 'bos50'),
  ('_p27_pl(date,date,int[])', 'bos72'),
  ('_r3q_l1_pnl(date,date,int[],jsonb)', 'bos72'),
  ('_r3q_l1_pnl(date,date,int[],jsonb)', 'bos78'),
  ('_r3q_l2_margin(date,date,int[],jsonb)', 'bos72'),
  ('_r3q_l3_shop_pnl(date,date,int[],jsonb)', 'bos72'),
  ('_r3q_l3_shop_pnl(date,date,int[],jsonb)', 'bos78'),
  ('biz_daily(date,date,int)', 'bos72'),
  ('acct_status()', 'bos72'),
  ('acct_overview(int)', 'bos72'),
  ('acct_income_statement(date,date,int)', 'bos72'),
  ('acct_post_pending(boolean,int)', 'bos72'),
  ('production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)', 'bos72'),
  ('production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)', 'bos73'),
  ('production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)', 'bos74'),
  ('recipe_cost(uuid,int)', 'bos73'),
  ('recipe_cost(uuid,int)', 'bos74'),
  ('recipe_save(uuid,uuid,numeric,text,text,jsonb,uuid,boolean)', 'bos73'),
  ('recipe_copy(uuid,uuid,boolean,uuid)', 'bos73'),
  ('_recipe_read()', 'bos73'),
  ('stock_production_in(uuid,int,numeric,timestamptz,text,text,uuid,numeric)', 'bos74'),
  ('pool_set(int,date,text,numeric,text,boolean,text,uuid)', 'bos75'),
  ('online_order_get(uuid)', 'bos76'),
  ('online_order_get(uuid)', 'bos77'),
  ('online_orders_list(int,text,date,date,int)', 'bos76'),
  ('online_orders_list(int,text,date,date,int)', 'bos77'),
  ('online_order_deliver(uuid,jsonb)', 'bos77'),
  ('online_order_status(uuid,text,text)', 'bos77')
), got as (select w.fn, w.tag, position(w.tag in pg_get_functiondef(to_regprocedure('public.' || w.fn))) > 0 ok from want w)
select tt.chk('T0 tag ' || tag || ' in ' || fn, ok) from got;
select tt.chk('T0 production_post: the 7-arg core and the 6-arg wrapper both exist, no default on the 7th (not ambiguous)', (select count(*) from pg_proc where proname='production_post')=2 and (select count(*) from pg_proc where proname='production_post' and pronargs=7 and pronargdefaults=0)=1);
select tt.chk('T0 the 6-arg wrapper only calls the core (thin)', position('null::numeric' in pg_get_functiondef('public.production_post(int,uuid,numeric,uuid,timestamptz,text)'::regprocedure))>0);
select tt.chk('T0 phase75 double-entry warning in pool_set', position('allocated_exists' in pg_get_functiondef('public.pool_set(int,date,text,numeric,text,boolean,text,uuid)'::regprocedure))>0);
select tt.chk('T0 the bos78 union rows and the bos72 columns are in the same l1 and l3 bodies', position('cogs_fallback' in pg_get_functiondef('public._r3q_l1_pnl(date,date,int[],jsonb)'::regprocedure))>0 and position('_c78_rows' in pg_get_functiondef('public._r3q_l1_pnl(date,date,int[],jsonb)'::regprocedure))>0
  and position('unknown_cost_rev' in pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,int[],jsonb)'::regprocedure))>0 and position('_c78_rows' in pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,int[],jsonb)'::regprocedure))>0);
select tt.chk('T0 defaults = today: production_requires_cost warn, recipe approval off, cost_attrib_in_pl off', rule_txt('production_requires_cost')='warn' and rule_txt('recipe_approval_required')='off' and not rule_on('cost_attrib_in_pl'));
select tt.chk('T0 no function privilege was opened by phase79', not has_function_privilege('anon','public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)','execute') and not has_function_privilege('anon','public._acct_docs(date)','execute')
  and not has_function_privilege('authenticated','public._r3q_l1_pnl(date,date,int[],jsonb)','execute'));

\echo == setup: accounting on, stock at place 1
set role authenticated; select tt.as(:'o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
reset role;
insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values
 ('I79-FL','Flour','Flour','kg','kg',0,true,'raw_material'),
 ('I79-SU','Sugar','Sugar','kg','kg',0,true,'raw_material'),
 ('I79-BX','Box','Box','pc','pc',0,true,'packaging'),
 ('I79-CA','Cake','Cake','kg','kg',400,true,'finished_good'),
 ('I79-CD','Candy','Candy','kg','kg',500,true,'finished_good'),
 ('I79-SW','Sweet','Sweet','kg','kg',400,true,'finished_good'),
 ('I79-PK','Pack','Pack','pc','pc',20,true,'packaging');
select id as fl from items where code='I79-FL' \gset
select id as su from items where code='I79-SU' \gset
select id as bx from items where code='I79-BX' \gset
select id as ca from items where code='I79-CA' \gset
select id as cd from items where code='I79-CD' \gset
select id as sw from items where code='I79-SW' \gset
select id as pk from items where code='I79-PK' \gset
set role authenticated; select tt.as(:'o');
-- Flour 100 kg @ 40.003 ; Sugar 100 kg with NO cost ; Box 1000 @ 0.50045 ; Sweet 20 kg @ 39.428571 ; Pack 50 @ 9.714286
select stock_opening(:'fl'::uuid,1,100,40.003) is not null as a1 \gset
select stock_opening(:'su'::uuid,1,100,null) is not null as a2 \gset
select stock_opening(:'bx'::uuid,1,1000,0.50045) is not null as a3 \gset
select stock_opening(:'sw'::uuid,1,20,39.428571) is not null as a4 \gset
select stock_opening(:'pk'::uuid,1,50,9.714286) is not null as a5 \gset
select tt.chk('setup: openings', :'a1' and :'a2' and :'a3' and :'a4' and :'a5');
-- RA (Cake): yield 10 kg from 6 kg Flour + 3 kg Sugar (Sugar cost unknown). RB (Candy): yield 10 kg from 5 kg Flour, + 2 Box per kg (packaging)
select set_rule('packaging_consume_on','"production"'::jsonb) is null as pkon \gset
select (recipe_save(null, :'ca'::uuid, 10, null, 'RA', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'fl','qty',6,'waste_pct',0), jsonb_build_object('ingredient_item_id',:'su','qty',3,'waste_pct',0)))->>'id')::uuid as ra \gset
select (recipe_save(null, :'cd'::uuid, 10, null, 'RB', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'fl','qty',5,'waste_pct',0)))->>'id')::uuid as rb \gset
select packaging_set(:'cd'::uuid, :'bx'::uuid, 2, 'production') is not null as pk2 \gset
-- conversion cost: location 1 in mode "recipe", RB has a labour component of 100 per batch
select loc_cost_cfg_set(1,'recipe') is null as m1 \gset
select recipe_cost_component_set(:'rb'::uuid, 'labour', 'per_batch', 100) is not null as c1 \gset

\echo == A1 approval gate ON + production_requires_cost = refuse: the refusals come in order and write nothing
select set_rule('recipe_approval_required','"on"') is null as g_on \gset
select set_rule('production_requires_cost','"refuse"') is null as rf \gset
reset role;
select count(*) as runs0 from production_runs \gset
set role authenticated; select tt.as(:'o');
select tt.err('A1 unapproved recipe RB: refused by the approval gate (bos73)', format($$select production_post(1,%L::uuid,1,gen_random_uuid())$$, :'rb'), 'recipe_not_approved');
select tt.err('A1 unapproved recipe RA: refused by the approval gate too', format($$select production_post(1,%L::uuid,1,gen_random_uuid())$$, :'ra'), 'recipe_not_approved');
select tt.as(:'ap');
select (recipe_approve(:'rb'::uuid, 'checked')->>'approved')::boolean as apb \gset
select (recipe_approve(:'ra'::uuid, 'checked')->>'approved')::boolean as apa \gset
select tt.chk('A1 a separate approver approved both versions', :'apb' and :'apa');
select tt.as(:'o');
select tt.err('A1 approved RA, Sugar cost unknown, refuse: cost_missing (bos72) naming the ingredient', format($$select production_post(1,%L::uuid,1,gen_random_uuid())$$, :'ra'), 'cost_missing');
reset role;
select tt.chk('A1 nothing was written by the three refusals (no run; Flour 100, Sugar 100)', (select count(*) from production_runs)=:'runs0'::bigint and (select qty from stock_balance where item_id=:'fl'::uuid and location_id=1)=100 and (select qty from stock_balance where item_id=:'su'::uuid and location_id=1)=100);

\echo == A2 approved + all costs known + overhead: RB 1 batch
-- material: Flour 5 x 40.003 = 200.015 ; Box 20 x 0.50045 = 10.009 ; sum 210.024 ; conversion (labour per batch) 100 ; unit cost (210.024 + 100) / 10 = 31.0024
set role authenticated; select tt.as(:'o');
select production_post(1,:'rb'::uuid,1,gen_random_uuid()) as pb \gset
select (:'pb'::jsonb->>'run_id') as runb \gset
select tt.chk('A2 refuse mode does not block a fully costed run; cost_complete, conversion_complete', (:'pb'::jsonb->>'cost_complete')::boolean and (:'pb'::jsonb->>'conversion_complete')::boolean and (:'pb'::jsonb->>'unit_cost')::numeric = 31.0024);
reset role;
select tt.chk('A2 ledger: finished good IN 10 kg at 31.0024 ; Flour 95, Box 980', (select unit_cost from stock_ledger where ref_type='production' and ref_id=:'runb' and reason='production_in')=31.002400 and (select qty_delta from stock_ledger where ref_type='production' and ref_id=:'runb' and reason='production_in')=10
  and (select qty from stock_balance where item_id=:'fl'::uuid and location_id=1)=95 and (select qty from stock_balance where item_id=:'bx'::uuid and location_id=1)=980);
select tt.chk('A2 run snapshot: material 210.024, conversion 100, unit 31.0024', (select material_cost=210.024 and conversion_cost=100 and unit_cost=31.0024 and conversion_mode='recipe' and cost_complete from production_runs where id=:'runb'::uuid));
set role authenticated; select tt.as(:'o');
select tt.chk('A2 recipe_cost (bos73 gate + bos74 rows) agrees with the run: unit 31.0024, approved', (recipe_cost(:'rb'::uuid,1)->>'unit_cost')::numeric=31.0024 and (recipe_cost(:'rb'::uuid,1)->>'approved')::boolean);
select acct_post_pending(false) as pj \gset
reset role;
select tt.chk('A2 journal: the run is posted without error', (:'pj'::jsonb->'by_type'->>'production')::int = 1 and jsonb_array_length(:'pj'::jsonb->'errors') = 0);
-- journal: total material round(210.024,2) = 210.02 ; parts 200.015 -> 200.02, 10.009 -> 10.01 ; sum 210.03 -> remainder -0.01 on the largest part (raw) = 200.01
-- Dr finished 210.02 + 100 = 310.02 ; Cr raw 200.01 + Cr packaging 10.01 + Cr overhead absorbed 100 = 310.02
select tt.chk('A2 journal lines: Dr finished 310.02 (material + conversion) = Cr raw 200.01 + Cr packaging 10.01 (bos72 remainder on the largest) + Cr overhead absorbed 100 (bos74)',
  tt.jl('production',:'runb','1310','d')=310.02 and tt.jl('production',:'runb','1320','c')=200.01 and tt.jl('production',:'runb','1330','c')=10.01 and tt.jl('production',:'runb','5950','c')=100);
select tt.chk('A2 every entry balanced', tt.unbalanced_entries()=0);

\echo == A3 warn (the default) = today: the unknown-cost run posts, the finished good has NO cost, and it waits in the journal
set role authenticated; select tt.as(:'o');
select set_rule('production_requires_cost',null) is null as rf2 \gset
select tt.chk('A3 back to default warn', rule_txt('production_requires_cost')='warn');
select production_post(1,:'ra'::uuid,1,gen_random_uuid()) as pa \gset
select (:'pa'::jsonb->>'run_id') as runa \gset
select tt.chk('A3 RA posted with cost_complete = false (Sugar cost unknown counts as unknown)', (:'pa'::jsonb->>'cost_complete')::boolean = false);
reset role;
select tt.chk('A3 the finished Cake has no ledger cost; Sugar unchanged cost null; Flour 89', (select unit_cost is null from stock_ledger where ref_type='production' and ref_id=:'runa' and reason='production_in') and (select qty from stock_balance where item_id=:'fl'::uuid and location_id=1)=89);
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as pj2 \gset
reset role;
-- Flour 6 x 40.003 = 240.018 -> 240.02 is known, Sugar is not: the entry carries the KNOWN part and the flag cogs_missing (as in phase72)
select tt.chk('A3 the run is journalled only for its known part (Dr finished 240.02 = Cr raw 240.02) and flagged cogs_missing', tt.jl('production',:'runa','1310','d')=240.02 and tt.jl('production',:'runa','1320','c')=240.02
  and exists (select 1 from journal_entries where source_type='production' and source_id=:'runa' and flags='cogs_missing') and tt.jl('production',:'runa','5950','c')=0);

\echo == B1 rounding: a sale of two item types (1.5 kg Sweet + 1 Pack) posts balanced
-- ledger: Sweet 1.5 x 39.428571 = 59.1428565 ; Pack 9.714286 ; sum 68.8571425 -> COGS 68.86 ; parts 59.14 + 9.71 = 68.85 -> remainder 0.01 on the largest = 59.15
set role authenticated; select tt.as(:'o');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1.5,"price":400},{"item_id":"%s","qty":1,"price":20}]',:'sw',:'pk')::jsonb,0,'[{"mode":"cash","amount":620}]',null,null,'retail',null,false)->>'id' as sa \gset
-- candy: 4 kg x 31.0024 = 124.0096 -> 124.01 (one type)
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":4,"price":500}]',:'cd')::jsonb,0,'[{"mode":"cash","amount":2000}]',null,null,'retail',null,false)->>'id' as sc \gset
select acct_post_pending(false) as pj3 \gset
reset role;
select tt.chk('B1 both sales posted, no error', (:'pj3'::jsonb->>'posted')::int >= 2 and jsonb_array_length(:'pj3'::jsonb->'errors')=0);
select tt.chk('B1 two-type sale: COGS 68.86 = Cr finished 59.15 + Cr packaging 9.71', tt.jl('sale',:'sa','5000','d')=68.86 and tt.jl('sale',:'sa','1310','c')=59.15 and tt.jl('sale',:'sa','1330','c')=9.71);
select tt.chk('B1 candy sale: COGS 124.01 = Cr finished 124.01 (conversion cost is inside the product cost)', tt.jl('sale',:'sc','5000','d')=124.01 and tt.jl('sale',:'sc','1310','c')=124.01);
select tt.chk('B1 every entry balanced', tt.unbalanced_entries()=0);

\echo == B2 one COGS source: the report equals the journal
-- report COGS = ledger exact 68.8571425 + 124.0096 = 192.8667425 -> 192.87 ; journal 68.86 + 124.01 = 192.87 ; revenue 620 + 2000 = 2620
set role authenticated; select tt.as(:'o');
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd_
select tt.chk('B2 biz_daily: revenue 2620, COGS 192.87, costed revenue 2620', :'bd_revenue'::numeric=2620 and :'bd_cogs'::numeric=192.87 and :'bd_costed_rev'::numeric=2620);
select profit_source_check(tt.today(), tt.today(), 1) as psc \gset
select tt.chk('B2 profit_source_check: report 192.87 = journal 192.87, difference 0, no fallback, no unknown', (:'psc'::jsonb->>'report_cogs')::numeric=192.87 and (:'psc'::jsonb->>'journal_cogs')::numeric=192.87 and (:'psc'::jsonb->>'difference')::numeric=0
  and (:'psc'::jsonb->>'fallback_cogs')::numeric=0 and (:'psc'::jsonb->>'unknown_cost_rev')::numeric=0);
select acct_income_statement(tt.today(), tt.today(), 1) as ist \gset
select tt.chk('B2 acct_income_statement COGS 192.87 = report; provisional only because of the one cogs_missing run (RA), no unknown-cost revenue yet', (:'ist'::jsonb->>'cogs')::numeric=192.87 and (:'ist'::jsonb->>'cogs_missing')::int=1 and (:'ist'::jsonb->>'unknown_cost_rev')::numeric=0 and (:'ist'::jsonb->>'provisional')::boolean);
reset role;
select tt.chk('B2 _p27_pl (base of l1 / l3 / partner profit): COGS 192.87, net 2620', (select o_cogs from _p27_pl(tt.today(), tt.today(), array[1]))=192.87 and (select o_net from _p27_pl(tt.today(), tt.today(), array[1]))=2620);
set role authenticated; select tt.as(:'o');
select inventory_vs_gl(tt.today(), 1) as ivg \gset
select tt.chk('B2 inventory_vs_gl exists and is read only (valuation basis given)', :'ivg'::jsonb ? 'valuation_basis');

\echo == B4 unknown cost: 1 kg of the uncosted Cake is sold
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":400}]',:'ca')::jsonb,0,'[{"mode":"cash","amount":400}]',null,null,'retail',null,false)->>'id' as sk \gset
select * from biz_daily(tt.today(), tt.today(), 1) \gset bk_
select tt.chk('B4 biz_daily: revenue 3020, costed 2620, the 400 is unknown-cost revenue, COGS unchanged 192.87', :'bk_revenue'::numeric=3020 and :'bk_costed_rev'::numeric=2620 and :'bk_cogs'::numeric=192.87);
select acct_income_statement(tt.today(), tt.today(), 1) as ist2 \gset
select tt.chk('B4 income statement is provisional by 400', (:'ist2'::jsonb->>'unknown_cost_rev')::numeric=400 and (:'ist2'::jsonb->>'provisional')::boolean);

\echo == C attribution rows (bos78) and the bos72 columns come out of the SAME l1 / l3 report
reset role;
select (now() at time zone 'Asia/Dhaka')::date as td, date_trunc('month', (now() at time zone 'Asia/Dhaka')::date)::date as m1,
       (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) + interval '1 month - 1 day')::date as m2 \gset
select format('{"from":"%s","to":"%s"}', :'m1', :'m2') as per \gset
set role authenticated; select tt.as(:'o');
select cost_source_save(null,'internet',null,'separate','showroom',array[1],'monthly',:'m1'::date - 90) ->> 'id' as si \gset
select cost_bill_add(:si,'month',:'m1'::date,1200,'cash','I-0') ->> 'id' as bi0 \gset
select cost_attrib_set(1,null,'showroom',:'m1'::date) ->> 'id' as at1 \gset
select report_run2('l1_pnl', :'per'::jsonb) as l1_off \gset
select tt.chk('C1 switch OFF (default): no cost-share row in l1; the bos72 keys are there', not exists (select 1 from jsonb_array_elements(:'l1_off'::jsonb->'rows') r where r->>'row_type'='cost_share')
  and exists (select 1 from jsonb_array_elements(:'l1_off'::jsonb->'rows') r where r ? 'cogs_fallback' and r ? 'unknown_cost_rev'));
select tt.chk('C1 l1 (OFF) numbers: net sales 3020, COGS 192.87, unknown-cost revenue 400', (select (r->>'net_sales')::numeric=3020 and (r->>'cogs')::numeric=192.87 and (r->>'unknown_cost_rev')::numeric=400 from jsonb_array_elements(:'l1_off'::jsonb->'rows') r where r->>'location_id'='1' and r->>'row_type' is null limit 1));
select set_rule('cost_attrib_in_pl','true') is null as son \gset
select report_run2('l1_pnl', :'per'::jsonb) as l1_on \gset
select report_run2('l3_shop_pnl', :'per'::jsonb) as l3_on \gset
select tt.chk('C2 switch ON: ONE separate cost-share row in l1: internet 1200 on place 1, profit -1200', (select count(*) from jsonb_array_elements(:'l1_on'::jsonb->'rows') r where r->>'row_type'='cost_share')=1
  and (select (r->>'expenses')::numeric=1200 and (r->>'profit')::numeric=-1200 and r->>'cost_type'='internet' from jsonb_array_elements(:'l1_on'::jsonb->'rows') r where r->>'row_type'='cost_share'));
select tt.chk('C2 the normal rows are unchanged and still carry the bos72 split (COGS 192.87, unknown 400)', (select (r->>'cogs')::numeric=192.87 and (r->>'unknown_cost_rev')::numeric=400 from jsonb_array_elements(:'l1_on'::jsonb->'rows') r where r->>'location_id'='1' and r->>'row_type' is null limit 1));
select tt.chk('C2 l3 (shop P&L) has the same: one cost-share row AND the bos72 keys on the shop row', (select count(*) from jsonb_array_elements(:'l3_on'::jsonb->'rows') r where r->>'row_type'='cost_share')=1
  and (select (r->>'cogs')::numeric=192.87 and r ? 'cogs_fallback' from jsonb_array_elements(:'l3_on'::jsonb->'rows') r where r->>'location_id'='1' and r->>'row_type' is null limit 1));
select set_rule('cost_attrib_in_pl','false') is null as soff \gset
select tt.chk('C3 switch OFF again: l1 identical to the first OFF report', report_run2('l1_pnl', :'per'::jsonb) = :'l1_off'::jsonb);
reset role;
select tt.chk('C4 attribution rows (internal): 1200 to place 1 (destination kind location)', (select sum(amount) from _c78_rows(:'m1'::date, :'m2'::date) where dkind='location' and dloc=1)=1200);

\echo == D the rest: defaults and journal stay sane
select tt.chk('D1 every entry balanced at the end', tt.unbalanced_entries()=0);
set role authenticated; select tt.as(:'o');
select set_rule('recipe_approval_required',null) is null as g_off \gset
select set_rule('packaging_consume_on','"off"'::jsonb) is null as pkoff \gset
select tt.chk('D2 recipe_approval_required back to off', rule_txt('recipe_approval_required')='off');
select acct_status() as st \gset
select tt.chk('D3 acct_status (bos72) answers with its keys', :'st'::jsonb ? 'pending' and :'st'::jsonb ? 'errors' and :'st'::jsonb ? 'last_post_at');
reset role;

select count(*) filter (where ok) as pass, count(*) filter (where not ok) as fail from tt.res \gset
\echo RESULT :pass pass :fail fail
select name from tt.res where not ok;
