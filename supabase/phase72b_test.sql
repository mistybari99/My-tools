-- phase72b_test.sql = copy of phase72_test.sql for the FINAL build. Only change (bos89): T0 looks for bos72 in the 7-argument production_post core (since phase74 the 6-argument one is a thin wrapper).
-- FRESH DB ONLY. Phase 72 tests (Phase B: balanced inventory lines, one COGS source, return margin, unknown cost, inventory vs GL, posting status).
--   ORDER="phase8 ... phase51 phase52 phase53 phase54 phase60 phase61 phase62 phase70 phase71 phase72" bash tests/sql/build_fresh_db.sh a72db
--   psql -h /tmp -p 5544 -U postgres -d a72db -qAt -f supabase/phase72_test.sql | grep -E 'FAIL|RESULT'
-- All numbers are hand-computed (see the comment above each block). Place 1 = sales / production / returns / unknown cost; place 2 = return margin + inventory-vs-GL.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set t '00000000-0000-0000-0000-000000000003'
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
-- is every journal entry balanced? (debit = credit per entry)
create or replace function tt.unbalanced_entries() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
-- sum of one side of one account in one document's entry
create or replace function tt.jl(p_type text, p_sid text, p_code text, p_side text) returns numeric language sql stable as $$
  select coalesce(sum(case p_side when 'd' then l.debit else l.credit end), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
  where e.source_type = p_type and e.source_id = p_sid and e.reverses_id is null and a.code = p_code $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'t','acct3@s.app','{"full_name":"Accountant"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'t','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1),(:'t',1) on conflict do nothing;
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Sugar','Sugar','kg','kg',0,true,'raw_material') returning id) select id as sug from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Box2','Box2','pc','pc',0,true,'packaging') returning id) select id as bx2 from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Box','Box','pc','pc',20,true,'packaging') returning id) select id as box from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Sweet','Sweet','kg','kg',400,true,'finished_good') returning id) select id as swt from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Choco','Choco','kg','kg',300,true,'finished_good') returning id) select id as cho from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Ghost','Ghost','pc','pc',150,true,'resale') returning id) select id as gho from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Mystery','Mystery','pc','pc',77,true,'resale') returning id) select id as mys from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Freebie','Freebie','pc','pc',50,true,'resale') returning id) select id as fre from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Pastry','Pastry','pc','pc',100,true,'resale') returning id) select id as pas from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Nuts','Nuts','kg','kg',0,true,'raw_material') returning id) select id as nut from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Nutty','Nutty','kg','kg',100,true,'finished_good') returning id) select id as nty from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Water','Water','kg','kg',0,true,'raw_material') returning id) select id as wat from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Drink','Drink','kg','kg',50,true,'finished_good') returning id) select id as drk from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Flour','Flour','kg','kg',0,true,'raw_material') returning id) select id as flo from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Spice','Spice','kg','kg',0,true,'raw_material') returning id) select id as spi from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Salt','Salt','kg','kg',0,true,'raw_material') returning id) select id as sal from i \gset
with i as (insert into suppliers (name) values ('Sup') returning id) select id as sup from i \gset

\echo == T0 shape
select tt.chk('T0 rule production_requires_cost exists, default warn', rule_txt('production_requires_cost')='warn' and (select kind from rules where key='production_requires_cost')='choice');
select tt.chk('T0 error table has RLS and no browser grants', (select relrowsecurity from pg_class where relname='acct_post_errors72') and not has_table_privilege('authenticated','acct_post_errors72','select') and not has_table_privilege('authenticated','acct_post_errors72','insert'));
select tt.chk('T0 internals closed to the browser, new reports open to signed-in users only', not has_function_privilege('authenticated','public._cogs_lines72(date,date,int[])','execute') and not has_function_privilege('authenticated','public._acct_inv_split72(text[],text,text[],int)','execute')
  and not has_function_privilege('authenticated','public._p27_src72(date,date,int[])','execute') and not has_function_privilege('anon','public.inventory_vs_gl(date,int)','execute') and not has_function_privilege('anon','public.profit_source_check(date,date,int)','execute')
  and has_function_privilege('authenticated','public.inventory_vs_gl(date,int)','execute') and has_function_privilege('authenticated','public.profit_source_check(date,date,int)','execute'));
select tt.chk('T0 re-created functions kept their signatures; bos72 lines present', position('bos72' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos72' in pg_get_functiondef('public.biz_daily(date,date,int)'::regprocedure))>0
  and position('bos72' in pg_get_functiondef('public._p27_pl(date,date,int[])'::regprocedure))>0 and position('bos72' in pg_get_functiondef('public.acct_post_pending(boolean,int)'::regprocedure))>0
  and position('bos72' in pg_get_functiondef('public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)'::regprocedure))>0 and position('bos72' in pg_get_functiondef('public.acct_income_statement(date,date,int)'::regprocedure))>0);

\echo == setup: accounting on, stock at place 1 (opening, not journalled)
set role authenticated; select tt.as(:'o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
select tt.chk('setup accounting on, start date set', rule_on('accounting_on') and :'sd'::date = tt.today()-5);
-- Sweet 20 kg @ 39.428571, Box 50 @ 9.714286, Sugar 100 @ 3.003, Box2 50 @ 2.5045
select stock_opening(:'swt'::uuid,1,20,39.428571) is not null as a1 \gset
select stock_opening(:'box'::uuid,1,50,9.714286) is not null as a2 \gset
select stock_opening(:'sug'::uuid,1,100,3.003) is not null as a3 \gset
select stock_opening(:'bx2'::uuid,1,50,2.5045) is not null as a4 \gset
select tt.chk('setup openings', :'a1' and :'a2' and :'a3' and :'a4');

\echo == B1 rounding: a sale with two item types (1.5 kg Sweet + 1 Box) posts balanced
-- ledger: Sweet 1.5 x 39.428571 = 59.1428565 ; Box 1 x 9.714286 = 9.714286 ; sum 68.8571425 -> COGS 68.86 ; parts 59.14 + 9.71 = 68.85 -> remainder 0.01 on the largest = 59.15
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1.5,"price":400},{"item_id":"%s","qty":1,"price":20}]',:'swt',:'box')::jsonb,0,'[{"mode":"cash","amount":620}]',null,null,'retail',null,false)->>'id' as sa \gset
select acct_post_pending(false) as p1 \gset
select tt.chk('B1 sale posted (no unbalanced error), nothing lost', (:'p1'::jsonb->>'posted')::int = 1 and jsonb_array_length(:'p1'::jsonb->'errors') = 0);
reset role;
select tt.chk('B1 sale entry: COGS 68.86 = inventory credits 59.15 (finished) + 9.71 (packaging)', tt.jl('sale',:'sa','5000','d') = 68.86 and tt.jl('sale',:'sa','1310','c') = 59.15 and tt.jl('sale',:'sa','1330','c') = 9.71);
select tt.chk('B1 every entry balanced', tt.unbalanced_entries() = 0);
select tt.chk('B1 split helper: parts add to the rounded total, remainder on the largest', (select sum(amt) from _acct_inv_split72(array['sale','sale_pack'], :'sa', array['sale_out','issue_out'], -1)) = 68.86
  and (select amt from _acct_inv_split72(array['sale','sale_pack'], :'sa', array['sale_out','issue_out'], -1) where t='finished_good') = 59.15);
set role authenticated; select tt.as(:'o');
select sale_return(gen_random_uuid(),:'sa'::uuid,format('[{"item_id":"%s","qty":1.5},{"item_id":"%s","qty":1}]',:'swt',:'box')::jsonb,(select value_code from option_lists where list_code='return_reasons' and active limit 1),null,'cash')->>'id' as ra \gset
select acct_post_pending(false) as p2 \gset
select tt.chk('B1 sale return (two types) posted', (:'p2'::jsonb->>'posted')::int = 1 and jsonb_array_length(:'p2'::jsonb->'errors') = 0);
reset role;
select tt.chk('B1 return entry: Dr finished 59.15 + Dr packaging 9.71 = Cr COGS 68.86', tt.jl('sale_return',:'ra','5000','c') = 68.86 and tt.jl('sale_return',:'ra','1310','d') = 59.15 and tt.jl('sale_return',:'ra','1330','d') = 9.71);
-- production: Sugar 1.5 x 3.003 = 4.5045 ; Box2 1 x 2.5045 ; sum 7.009 -> 7.01 ; parts 4.50 + 2.50 = 7.00 -> raw takes the 0.01 = 4.51
insert into recipes (item_id,version,yield_qty,yield_unit) values (:'cho',1,1,'kg') returning id as rcp \gset
insert into recipe_lines (recipe_id,ingredient_item_id,qty,unit,waste_pct) values (:'rcp',:'sug',1.5,'kg',0),(:'rcp',:'bx2',1,'pc',0);
set role authenticated; select tt.as(:'o');
select production_post(1,:'rcp'::uuid,1,gen_random_uuid()) as pr \gset
select (:'pr'::jsonb->>'run_id') as run1 \gset
select acct_post_pending(false) as p3 \gset
select tt.chk('B1 production (raw + packaging) posted balanced', (:'p3'::jsonb->>'posted')::int = 1 and jsonb_array_length(:'p3'::jsonb->'errors') = 0);
reset role;
select tt.chk('B1 production entry: Dr finished 7.01 = Cr raw 4.51 + Cr packaging 2.50', tt.jl('production',:'run1','1310','d') = 7.01 and tt.jl('production',:'run1','1320','c') = 4.51 and tt.jl('production',:'run1','1330','c') = 2.50);
select tt.chk('B1 the cost stored on the finished good is the exact 7.009 (ledger untouched)', (select unit_cost from stock_ledger where ref_type='production' and ref_id=:'run1' and reason='production_in') = 7.009000);
-- wastage of 1 kg Sweet at 39.428571 -> 39.43 (a wastage document has one item, so it cannot differ; the same split helper is used)
set role authenticated; select tt.as(:'o');
select stock_wastage(:'swt'::uuid,1,1,(select value_code from option_lists where list_code='wastage_reasons' and active limit 1),'t')->>'id' as w1 \gset
select acct_post_pending(false) as p4 \gset
select tt.chk('B1 wastage posted balanced', (:'p4'::jsonb->>'posted')::int = 1 and jsonb_array_length(:'p4'::jsonb->'errors') = 0);
reset role;
select tt.chk('B1 wastage entry: Dr wastage 39.43 = Cr finished 39.43', tt.jl('wastage',:'w1','5100','d') = 39.43 and tt.jl('wastage',:'w1','1310','c') = 39.43);
select tt.chk('B1 all entries so far balanced', tt.unbalanced_entries() = 0);

\echo == B2 one COGS source: ledger cost, not item_costs; journal and report agree
-- more sales at place 1: C = 3 kg Sweet cash 1200 ; D = 2 kg Sweet, discount 50, total 750 card, then 1 kg of D returned (amount 375)
set role authenticated; select tt.as(:'o');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":3,"price":400}]',:'swt')::jsonb,0,'[{"mode":"cash","amount":1200}]',null,null,'retail',null,false)->>'id' as sc \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":400}]',:'swt')::jsonb,50,'[{"mode":"card","amount":750}]',null,null,'retail',null,false)->>'id' as sd2 \gset
select sale_return(gen_random_uuid(),:'sd2'::uuid,format('[{"item_id":"%s","qty":1}]',:'swt')::jsonb,(select value_code from option_lists where list_code='return_reasons' and active limit 1),null,'card')->>'amount' as rdamt \gset
select tt.chk('B3 setup: return of 1 kg from the discounted sale = 400 x 750/800 = 375.00', :'rdamt'::numeric = 375.00);
reset role;
-- a typed catalog cost that DIFFERS from the ledger: the report must ignore it for sold units that have a ledger cost
insert into item_costs (item_id, cost_price) values (:'swt', 40) on conflict (item_id) do update set cost_price = 40;
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as p5 \gset
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd_
-- journal COGS = 68.86 - 68.86 + 118.29 + 78.86 - 39.43 = 157.72 ; ledger exact = 118.285713 + 78.857142 - 39.428571 = 157.714284 -> 157.71 (the 0.01 is the per-entry rounding)
-- revenue today = 620 + 1200 + 750 - 620 - 375 = 1575 ; costed_rev = 1575 (every line has a ledger cost)
select tt.chk('B2 biz_daily COGS = ledger cost (157.71), NOT the typed 40 per kg (would be 160.00)', :'bd_cogs'::numeric = 157.71);
select tt.chk('B2 biz_daily revenue 1575 and costed_rev 1575', :'bd_revenue'::numeric = 1575 and :'bd_costed_rev'::numeric = 1575);
select acct_income_statement(tt.today(), tt.today(), 1) as ist \gset
select tt.chk('B2 acct_income_statement COGS 157.72 = biz_daily within 0.01 (all cost known)', (:'ist'::jsonb->>'cogs')::numeric = 157.72 and abs((:'ist'::jsonb->>'cogs')::numeric - :'bd_cogs'::numeric) <= 0.01);
select tt.chk('B2 ... and nothing is provisional', (:'ist'::jsonb->>'unknown_cost_rev')::numeric = 0 and not (:'ist'::jsonb->>'provisional')::boolean);
select profit_source_check(tt.today(), tt.today(), 1) as psc \gset
select tt.chk('B2 profit_source_check: report 157.71 vs journal 157.72 (difference -0.01), no fallback, no unknown, nothing pending, agree',
  (:'psc'::jsonb->>'report_cogs')::numeric = 157.71 and (:'psc'::jsonb->>'journal_cogs')::numeric = 157.72 and (:'psc'::jsonb->>'difference')::numeric = -0.01
  and (:'psc'::jsonb->>'fallback_cogs')::numeric = 0 and (:'psc'::jsonb->>'unknown_cost_rev')::numeric = 0 and (:'psc'::jsonb->>'pending_docs')::int = 0 and (:'psc'::jsonb->>'agree')::boolean);
reset role;
select tt.chk('B2 _p27_pl (base of l1 / l3 / l4 / l5 / partner profit share): COGS 157.71, costed 1575, net 1575', (select o_cogs from _p27_pl(tt.today(), tt.today(), array[1])) = 157.71 and (select o_costed from _p27_pl(tt.today(), tt.today(), array[1])) = 1575 and (select o_net from _p27_pl(tt.today(), tt.today(), array[1])) = 1575);
select tt.chk('B2 l1 and l3 show the same COGS and carry the split keys', (select (j->>'cogs')::numeric from _r3q_l1_pnl(tt.today(), tt.today(), array[1], '{}'::jsonb) j) = 157.71
  and (select (j->>'cogs')::numeric from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[1], '{}'::jsonb) j) = 157.71
  and (select (j->>'cogs_fallback')::numeric from _r3q_l1_pnl(tt.today(), tt.today(), array[1], '{}'::jsonb) j) = 0);
select tt.chk('B2 l2 margin: Sweet row COGS 157.71 ; Box nets to 0 (sold and returned) ; categories add to 157.71',
  (select (j->>'cogs')::numeric from _r3q_l2_margin(tt.today(), tt.today(), array[1], '{}'::jsonb) j where j->>'level'='item' and j->>'item_name'='Sweet') = 157.71
  and (select (j->>'cogs')::numeric from _r3q_l2_margin(tt.today(), tt.today(), array[1], '{}'::jsonb) j where j->>'level'='item' and j->>'item_name'='Box') = 0
  and (select sum((j->>'cogs')::numeric) from _r3q_l2_margin(tt.today(), tt.today(), array[1], '{}'::jsonb) j where j->>'level'='category') = 157.71);
set role authenticated; select tt.as(:'o');
select tt.chk('B2 brand_pnl (through biz_daily) carries the same COGS', (select coalesce(sum(cogs),0) from brand_pnl(tt.today(), tt.today())) = 157.71);

\echo == B4 / B2: fallback and unknown cost shown separately
-- Ghost: never stocked, typed cost 100 -> sale of 2 x 150 = 300 : fallback COGS 200 (estimate), costed by the fallback
-- Mystery: never stocked, no typed cost -> 1 x 77 : unknown cost revenue 77
-- Freebie: stock with cost 0 -> 1 x 50 : cost 0 counts as UNKNOWN -> unknown cost revenue 50
reset role;
insert into item_costs (item_id, cost_price) values (:'gho', 100) on conflict (item_id) do update set cost_price = 100;
set role authenticated; select tt.as(:'o');
select stock_opening(:'fre'::uuid,1,5,0) is not null as fr0 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":150}]',:'gho')::jsonb,0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false)->>'id' as sg \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":77}]',:'mys')::jsonb,0,'[{"mode":"cash","amount":77}]',null,null,'retail',null,false)->>'id' as sm \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":50}]',:'fre')::jsonb,0,'[{"mode":"cash","amount":50}]',null,null,'retail',null,false)->>'id' as sf \gset
select tt.chk('B4 setup: the three sales were accepted', :'sg' <> '' and :'sm' <> '' and :'sf' <> '');
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd2_
select tt.chk('B2 biz_daily COGS = 157.71 ledger + 200.00 fallback = 357.71 ; costed_rev 1575 + 300 = 1875 ; revenue 1575 + 300 + 77 + 50 = 2002', :'bd2_cogs'::numeric = 357.71 and :'bd2_costed_rev'::numeric = 1875 and :'bd2_revenue'::numeric = 2002);
select * from biz_daily_src72(tt.today(), tt.today(), 1) \gset sr_
select tt.chk('B2 fallback shown separately: ledger 157.71, fallback 200.00 on revenue 300, unknown-cost revenue 77 + 50 = 127', :'sr_cogs_ledger'::numeric = 157.71 and :'sr_cogs_fallback'::numeric = 200 and :'sr_fallback_rev'::numeric = 300 and :'sr_unknown_cost_rev'::numeric = 127);
select profit_source_check(tt.today(), tt.today(), 1) as psc2 \gset
select tt.chk('B2 profit_source_check flags it: fallback 200, unknown 127, not agree, notes', (:'psc2'::jsonb->>'fallback_cogs')::numeric = 200 and (:'psc2'::jsonb->>'unknown_cost_rev')::numeric = 127
  and not (:'psc2'::jsonb->>'agree')::boolean and (:'psc2'::jsonb->'notes') @> '"fallback_used"' and (:'psc2'::jsonb->'notes') @> '"unknown_cost"');
reset role;
select tt.chk('B4 l1 shows cogs_fallback 200 and unknown_cost_rev 127', (select (j->>'cogs_fallback')::numeric from _r3q_l1_pnl(tt.today(), tt.today(), array[1], '{}'::jsonb) j) = 200 and (select (j->>'unknown_cost_rev')::numeric from _r3q_l1_pnl(tt.today(), tt.today(), array[1], '{}'::jsonb) j) = 127);
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as p6 \gset
select tt.chk('B4 the three sales still post their revenue (posted 3, no errors)', (:'p6'::jsonb->>'posted')::int = 3 and jsonb_array_length(:'p6'::jsonb->'errors') = 0);
reset role;
select tt.chk('B4 sales without a known cost (including the cost-0 one) are flagged cogs_missing in the journal', (select count(*) from journal_entries where source_type='sale' and flags like '%cogs_missing%' and source_id in (:'sg',:'sm',:'sf')) = 3);
set role authenticated; select tt.as(:'o');
select acct_income_statement(tt.today(), tt.today(), 1) as ist2 \gset
-- the books have no cost for Ghost (300), Mystery (77), Freebie (50) -> provisional by 427 ; the estimate item_costs would add (Ghost only) = 200
select tt.chk('B4 acct_income_statement: provisional, unknown_cost_rev 427 (Ghost 300 + Mystery 77 + Freebie 50), cogs_missing 3',
  (:'ist2'::jsonb->>'unknown_cost_rev')::numeric = 427 and (:'ist2'::jsonb->>'cogs_estimate_missing')::numeric = 200 and (:'ist2'::jsonb->>'provisional')::boolean and (:'ist2'::jsonb->>'cogs_missing')::int = 3);
select tt.chk('B4 acct_overview carries the figure', (acct_overview(1)->'income_month'->>'unknown_cost_rev')::numeric = (select (acct_income_statement(greatest(date_trunc('month', tt.today())::date, tt.today()-5), tt.today(), 1)->>'unknown_cost_rev')::numeric));
select tt.as(:'s');
select * from biz_daily(tt.today(), tt.today(), 1) \gset bds_
select tt.chk('B2 cost secrecy: a manager without a cost right sees no costed_rev / cogs', not :{?bds_cogs} and not :{?bds_costed_rev});
select tt.err('B2 profit_source_check needs the cost right', $$select profit_source_check(tt.today(), tt.today(), 1)$$, 'not allowed');
select tt.err('B5 inventory_vs_gl needs the accounts and cost rights', $$select inventory_vs_gl(tt.today(), 1)$$, 'not allowed');

\echo == B3 return margin at place 2 : discounted sale 4 x 100, discount 100, total 300 ; return 2 -> 150
set role authenticated; select tt.as(:'o');
select stock_opening(:'pas'::uuid,2,20,60) is not null as pa \gset
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":4,"price":100}]',:'pas')::jsonb,100,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false)->>'id' as sp \gset
select sale_return(gen_random_uuid(),:'sp'::uuid,format('[{"item_id":"%s","qty":2}]',:'pas')::jsonb,(select value_code from option_lists where list_code='return_reasons' and active limit 1),null,'cash')->>'amount' as rpamt \gset
select tt.chk('B3 setup: return amount = 200 x 0.75 = 150', :'rpamt'::numeric = 150);
select * from biz_daily(tt.today(), tt.today(), 2) \gset b3_
select tt.chk('B3 biz_daily: revenue 150, costed_rev 150 (was 100 before the fix), cogs 120 = 4 x 60 - 2 x 60', :'b3_revenue'::numeric = 150 and :'b3_costed_rev'::numeric = 150 and :'b3_cogs'::numeric = 120);
reset role;
select tt.chk('B3 _p27_pl: net 150, costed 150, cogs 120', (select o_net from _p27_pl(tt.today(), tt.today(), array[2])) = 150 and (select o_costed from _p27_pl(tt.today(), tt.today(), array[2])) = 150 and (select o_cogs from _p27_pl(tt.today(), tt.today(), array[2])) = 120);
select tt.chk('B3 l2 margin of Pastry: revenue 150, margin 30 (150 - 120), uncosted 0 %', (select (j->>'revenue')::numeric from _r3q_l2_margin(tt.today(), tt.today(), array[2], '{}'::jsonb) j where j->>'item_name'='Pastry' and j->>'level'='item') = 150
  and (select (j->>'margin')::numeric from _r3q_l2_margin(tt.today(), tt.today(), array[2], '{}'::jsonb) j where j->>'item_name'='Pastry' and j->>'level'='item') = 30
  and (select (j->>'uncosted_pct')::numeric from _r3q_l2_margin(tt.today(), tt.today(), array[2], '{}'::jsonb) j where j->>'item_name'='Pastry' and j->>'level'='item') = 0);

\echo == B4 production_requires_cost (warn | refuse) and cost 0 = unknown
-- Nuts have no cost (opening without cost); Water has cost 0.
set role authenticated; select tt.as(:'o');
select stock_opening(:'nut'::uuid,1,10,null) is not null as n0 \gset
select stock_opening(:'wat'::uuid,1,10,0) is not null as w0 \gset
reset role;
insert into recipes (item_id,version,yield_qty,yield_unit) values (:'nty',1,1,'kg') returning id as rn \gset
insert into recipe_lines (recipe_id,ingredient_item_id,qty,unit,waste_pct) values (:'rn',:'nut',1,'kg',0);
insert into recipes (item_id,version,yield_qty,yield_unit) values (:'drk',1,1,'kg') returning id as rd \gset
insert into recipe_lines (recipe_id,ingredient_item_id,qty,unit,waste_pct) values (:'rd',:'wat',2,'kg',0);
set role authenticated; select tt.as(:'o');
select production_post(1,:'rn'::uuid,1,gen_random_uuid()) as pw \gset
select tt.chk('B4 warn (default): production with an unknown (NULL) ingredient cost posts as before, flagged cost_complete = false', (:'pw'::jsonb->>'run_id') is not null and (:'pw'::jsonb->>'cost_complete')::boolean = false);
select production_post(1,:'rd'::uuid,1,gen_random_uuid()) as pw0 \gset
select tt.chk('B4 warn: an ingredient with cost 0 counts as unknown (cost_complete = false)', (:'pw0'::jsonb->>'cost_complete')::boolean = false);
select set_rule('production_requires_cost','"refuse"') is null as rf \gset
select count(*) as runs_before from production_runs \gset
select tt.err('B4 refuse: unknown (NULL) ingredient cost -> cost_missing', format($$select production_post(1,%L::uuid,1,gen_random_uuid())$$, :'rn'), 'cost_missing');
select tt.err('B4 refuse: ingredient cost 0 -> cost_missing', format($$select production_post(1,%L::uuid,1,gen_random_uuid())$$, :'rd'), 'cost_missing');
select tt.chk('B4 refuse: nothing was written (no run, Nuts still 9 kg, Water 8 kg)', (select count(*) from production_runs) = :'runs_before'::bigint and (select qty from stock_balance where item_id=:'nut'::uuid and location_id=1) = 9 and (select qty from stock_balance where item_id=:'wat'::uuid and location_id=1) = 8);
select production_post(1,:'rcp'::uuid,1,gen_random_uuid()) as pok \gset
select tt.chk('B4 refuse: a fully costed recipe still posts', (:'pok'::jsonb->>'run_id') is not null and (:'pok'::jsonb->>'cost_complete')::boolean);
select set_rule('production_requires_cost',null) is null as rf2 \gset
select tt.chk('B4 back to the default warn', rule_txt('production_requires_cost') = 'warn');
select acct_post_pending(false) as p7 \gset
select tt.chk('B1 posted: 1 costed run + the place-2 sale and return; the 2 uncosted runs wait; no errors', (:'p7'::jsonb->>'posted')::int = 3 and (:'p7'::jsonb->'by_type'->>'production')::int = 1 and (:'p7'::jsonb->'waiting'->>'cost_missing')::int = 2 and jsonb_array_length(:'p7'::jsonb->'errors') = 0);
reset role;
select tt.chk('B1 all entries balanced', tt.unbalanced_entries() = 0);
set role authenticated; select tt.as(:'o');

\echo == B6 posting status
select acct_status() as stt \gset
select tt.chk('B6 status keys present, last_post_at set', (:'stt'::jsonb) ?& array['last_post_at','pending','locked','waiting','errors','error_list','last_post','on','start'] and (:'stt'::jsonb->>'last_post_at') is not null);
select tt.chk('B6 pending 0, errors 0, waiting 2 (the two uncosted runs)', (:'stt'::jsonb->>'pending')::int = 0 and (:'stt'::jsonb->>'errors')::int = 0 and (:'stt'::jsonb->>'waiting')::int = 2);
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":400}]',:'swt')::jsonb,0,'[{"mode":"cash","amount":400}]',null,null,'retail',null,false)->>'id' as se \gset
select tt.chk('B6 a new sale is pending 1', (acct_status()->>'pending')::int = 1);
-- an error: point the COGS mapping at a header account -> the document cannot post; the failure is kept and shown
reset role;
select account_id as cogs_acc from acct_mappings where key='cogs' \gset
select id as grp_acc from coa_accounts where is_group order by id limit 1 \gset
update acct_mappings set account_id = :grp_acc where key='cogs';
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as pe \gset
select tt.chk('B6/B1 the failure is returned by acct_post_pending', jsonb_array_length(:'pe'::jsonb->'errors') = 1 and (:'pe'::jsonb->'errors'->0->>'source_id') = :'se');
select acct_status() as ste \gset
select tt.chk('B6 status: errors 1, pending 1, error_list names the sale', (:'ste'::jsonb->>'errors')::int = 1 and (:'ste'::jsonb->>'pending')::int = 1 and (:'ste'::jsonb->'error_list'->0->>'source_type') = 'sale' and (:'ste'::jsonb->'error_list'->0->>'source_id') = :'se');
select acct_post_pending(false) as pe2 \gset
reset role;
select tt.chk('B6 the second failure counts tries = 2 (one row, not two)', (select tries from acct_post_errors72 where source_id = :'se') = 2 and (select count(*) from acct_post_errors72) = 1);
update acct_mappings set account_id = :cogs_acc where key='cogs';
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as pe3 \gset
select tt.chk('B6 after the cause is fixed the sale posts and the error disappears', (:'pe3'::jsonb->>'posted')::int = 1 and (acct_status()->>'errors')::int = 0 and (acct_status()->>'pending')::int = 0);
reset role;
select tt.chk('B6 error table is empty again', (select count(*) from acct_post_errors72) = 0);
-- locked: a sale of 3 days ago after the period was closed up to yesterday -> locked 1 for a non-owner accountant, 0 for the owner
set role authenticated; select tt.as(:'o');
select set_user_grant(:'t'::uuid,'accounts_manage') is null as gt \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":400}]',:'swt')::jsonb,0,'[{"mode":"cash","amount":400}]',null,null,'retail',null,false, now() - interval '3 days')->>'id' as sl \gset
select set_rule('period_closed_until', to_jsonb((tt.today()-1)::text)) is null as cl \gset
select tt.as(:'t');
select tt.chk('B6 locked: the accountant sees pending 1 / locked 1', (acct_status()->>'pending')::int = 1 and (acct_status()->>'locked')::int = 1);
select tt.as(:'o');
select tt.chk('B6 locked: the owner (who may post into a closed period) sees locked 0', (acct_status()->>'locked')::int = 0);
select set_rule('period_closed_until', null) is null as cl2 \gset
select acct_post_pending(false) as p8 \gset
select tt.chk('B6 then it posts; pending 0', (acct_status()->>'pending')::int = 0 and (:'p8'::jsonb->>'posted')::int = 1);

\echo == B5 inventory_vs_gl at place 2 (raw materials): count adjust + issue + opening + transfer + manual + pre-start purchase
-- Flour bought 100 kg @ 30 = 3000 (journalled). count -> 95 (ledger -150). issue 2 kg (-60). transfer 10 kg out (-300). Spice opening 10 @ 25 (+250, not journalled).
-- Salt purchase dated BEFORE the start (10 @ 20 = +200 in the ledger, not journalled). Manual journal Dr 1320 40 / Cr 1110 40.
-- GL raw = 3000 + 40 = 3040 ; valuation = 83 x 30 + 250 + 200 = 2940 ; diff = 100 = +150 (count) +60 (issue) -250 (opening) +300 (transfer) -200 (pre-start) +40 (manual)
select save_purchase(gen_random_uuid(),null,:'sup'::uuid,2,'PF',tt.today()-3,format('[{"item_id":"%s","qty":100,"unit":"kg","unit_cost":30}]',:'flo')::jsonb)->>'id' as bf \gset
select post_purchase(:'bf'::uuid) is not null as pf \gset
select save_purchase(gen_random_uuid(),null,:'sup'::uuid,2,'PS',tt.today()-10,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":20}]',:'sal')::jsonb)->>'id' as bs \gset
select post_purchase(:'bs'::uuid) is not null as ps \gset
select stock_opening(:'spi'::uuid,2,10,25) is not null as sp0 \gset
select acct_post_pending(false) as p9 \gset
select inventory_vs_gl(tt.today(), 2) as iv0 \gset
-- only purchases so far: GL raw 3000 ; valuation 3000 + 250 + 200 = 3450 ; diff -450 = -250 (opening) -200 (pre-start)
select tt.chk('B5 before the adjustments: raw GL 3000, valuation 3450, diff -450, unexplained 0',
  (select (r->>'gl')::numeric = 3000 and (r->>'valuation')::numeric = 3450 and (r->>'diff')::numeric = -450 and (r->>'unexplained')::numeric = 0 from jsonb_array_elements(:'iv0'::jsonb->'rows') r where r->>'key'='inv_raw'));
select stock_count_adjust(:'flo'::uuid,2,95,'count') is not null as ca \gset
select stock_issue(:'flo'::uuid,2,2,null,'to kitchen') is not null as si \gset
select stock_transfer(2,7,:'flo'::uuid,10,null,'to godown') is not null as tr \gset
select acct_journal_post(tt.today(),2,'inventory top-up by hand','[{"code":"1320","debit":40},{"code":"1110","credit":40}]'::jsonb)->>'id' as mj \gset
select count(*) as je_before from journal_entries \gset
select inventory_vs_gl(tt.today(), 2) as iv \gset
select tt.chk('B5 raw materials at place 2: GL 3040, valuation 2940, diff 100',
  (select (r->>'gl')::numeric = 3040 and (r->>'valuation')::numeric = 2940 and (r->>'diff')::numeric = 100 from jsonb_array_elements(:'iv'::jsonb->'rows') r where r->>'key'='inv_raw'));
select tt.chk('B5 reasons: count_adjust +150, issue_out +60, transfer +300, opening -250, purchase_before_start -200, manual_journal +40 ; unexplained 0',
  (select (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='count_adjust') = 150
      and (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='issue_out') = 60
      and (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='transfer') = 300
      and (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='opening') = -250
      and (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='purchase_before_start') = -200
      and (select (x->>'amount')::numeric from jsonb_array_elements(r->'reasons') x where x->>'code'='manual_journal') = 40
      and (r->>'unexplained')::numeric = 0
   from jsonb_array_elements(:'iv'::jsonb->'rows') r where r->>'key'='inv_raw'));
select tt.chk('B5 valuation basis is the average cost for today; the report says the books and the stock do not agree', :'iv'::jsonb->>'valuation_basis' = 'average_cost' and not (:'iv'::jsonb->>'agree')::boolean);
select tt.chk('B5 read only: no journal entry was added by the report', (select count(*) from journal_entries) = :'je_before'::bigint);
select tt.chk('B5 an earlier date uses the ledger replay', inventory_vs_gl(tt.today()-1, 2)->>'valuation_basis' = 'ledger_replay');
select tt.chk('B5 all places: the owner can run it; finished goods differ (the openings are not journalled)', (select (r->>'diff')::numeric <> 0 from jsonb_array_elements(inventory_vs_gl(tt.today(), null)->'rows') r where r->>'key'='inv_finished'));

select count(*) filter (where ok) as pass, count(*) filter (where not ok) as fail from tt.res \gset
\echo RESULT :pass pass :fail fail
select name from tt.res where not ok;
