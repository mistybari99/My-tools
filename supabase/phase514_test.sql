-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase88_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase514_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY. Phase 514 tests (Step R: ONE cost source for every report; switch report_cost_source).
--   ORDER="phase8 ... phase79 phase508 phase509 phase510 phase514" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> a88db
--   psql -h /tmp -p 5544 -U postgres -d a88db -qAt -f supabase/phase514_test.sql | grep -E 'FAIL|RESULT'
-- All numbers are hand-computed (comment above each block). Test data only, no person names. Place 1 only.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set v '00000000-0000-0000-0000-000000000003'
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
create or replace function tt.jl(p_type text, p_sid text, p_code text, p_side text) returns numeric language sql stable as $$
  select coalesce(sum(case p_side when 'd' then l.debit else l.credit end), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
  where e.source_type = p_type and e.source_id = p_sid and e.reverses_id is null and a.code = p_code $$;
create or replace function tt.ledger_cost(p_sale text, p_item uuid) returns numeric language sql stable security definer as $$
  select sum(-qty_delta * unit_cost) from public.stock_ledger where ref_id = p_sale and item_id = p_item and reason = 'sale_out' $$;
create or replace function tt.rcs() returns text language sql stable security definer as $$ select public._rcs88() $$;
-- the report builder row of one item: column 'cogs' of report item_sales grouped by item (cost-grant holders only)
create or replace function tt.rb(p_item uuid, p_col text) returns numeric language sql stable as $$
  select (r ->> p_col)::numeric from jsonb_array_elements(public.report_run('item_sales', jsonb_build_object('from', tt.today()::text, 'to', tt.today()::text, 'locations', jsonb_build_array(1)), 'item') -> 'rows') r
  where r ->> 'item_id' = p_item::text or r ->> 'item' = p_item::text limit 1 $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Staff"}'), (:'v','cost3@s.app','{"full_name":"Costviewer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'v','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1),(:'v',1) on conflict do nothing;
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Cake','Cake','pc','pc',100,true,'resale') returning id) select id as ia from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Mango','Mango','pc','pc',80,true,'resale') returning id) select id as ib from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Typed','Typed','pc','pc',50,true,'resale') returning id) select id as ic from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Nothing','Nothing','pc','pc',20,true,'resale') returning id) select id as id_ from i \gset

\echo == T0 shape
select tt.chk('T0 rule exists, choice, default ledger_then_item_costs', (select kind from rules where key='report_cost_source')='choice' and rule_txt('report_cost_source')='ledger_then_item_costs' and tt.rcs()='ledger_then_item_costs');
select tt.chk('T0 internals closed to the browser; new reports open to signed-in users only', not has_function_privilege('authenticated','public._rcs88()','execute') and not has_function_privilege('authenticated','public._item_cost_eff88()','execute')
  and not has_function_privilege('authenticated','public._line_cost88(uuid,uuid)','execute') and not has_function_privilege('authenticated','public._cogs_lines72(date,date,int[])','execute')
  and not has_function_privilege('anon','public.item_cost_status88()','execute') and not has_function_privilege('anon','public.biz_items_cost88(date,date,int)','execute')
  and has_function_privilege('authenticated','public.item_cost_status88()','execute') and has_function_privilege('authenticated','public.biz_items_cost88(date,date,int)','execute')
  and has_function_privilege('authenticated','public.biz_items(date,date,int)','execute') and has_function_privilege('authenticated','public.items_with_cost()','execute'));
select tt.chk('T0 re-created functions carry bos88 and keep older tags', position('bos88' in pg_get_functiondef('public._cogs_lines72(date,date,int[])'::regprocedure))>0 and position('bos88' in pg_get_functiondef('public.biz_items(date,date,int)'::regprocedure))>0
  and position('bos88' in pg_get_functiondef('public.items_with_cost()'::regprocedure))>0 and position('bos88' in pg_get_functiondef('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,int,int,boolean,boolean,boolean)'::regprocedure))>0
  and position('bos14' in pg_get_functiondef('public.biz_items(date,date,int)'::regprocedure))>0);
select tt.chk('T0 tags of the other re-created functions untouched (bos72 biz_daily/_p27_pl, bos79 production_post, bos14 rpt_agg_sql history)', position('bos72' in pg_get_functiondef('public.biz_daily(date,date,int)'::regprocedure))>0
  and position('bos72' in pg_get_functiondef('public._p27_pl(date,date,int[])'::regprocedure))>0 and position('bos72' in pg_get_functiondef('public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)'::regprocedure))>0
  and position('bos72' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos74' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0);

\echo == setup: accounting on, stock at place 1
set role authenticated; select tt.as(:'o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
-- Cake 10 @ 70 ; Mango 10 @ 40 ; Typed 10 with NO ledger cost ; Nothing 10 with NO cost at all
select stock_opening(:'ia'::uuid,1,10,70) is not null as a1 \gset
select stock_opening(:'ib'::uuid,1,10,40) is not null as a2 \gset
select stock_opening(:'ic'::uuid,1,10,null) is not null as a3 \gset
select stock_opening(:'id_'::uuid,1,10,null) is not null as a4 \gset
select tt.chk('setup openings', :'a1' and :'a2' and :'a3' and :'a4');
reset role;
-- the hand-typed catalog costs DIFFER from the ledger for Cake (60 vs 70); Typed has only a typed cost (30); Mango and Nothing have none
insert into item_costs (item_id, cost_price) values (:'ia', 60), (:'ic', 30) on conflict (item_id) do update set cost_price = excluded.cost_price;
set role authenticated; select tt.as(:'o');
-- ONE bill: Cake 2 x 100 = 200 ; Mango 3 x 80 = 240 ; Typed 1 x 50 = 50 ; Nothing 1 x 20 = 20 ; revenue 510
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100},{"item_id":"%s","qty":3,"price":80},{"item_id":"%s","qty":1,"price":50},{"item_id":"%s","qty":1,"price":20}]',:'ia',:'ib',:'ic',:'id_')::jsonb,0,'[{"mode":"cash","amount":510}]',null,null,'retail',null,false)->>'id' as sa \gset
select acct_post_pending(false) as p1 \gset
select tt.chk('setup sale posted', (:'p1'::jsonb->>'posted')::int = 1 and jsonb_array_length(:'p1'::jsonb->'errors') = 0);
reset role;

\echo == R1 default (ledger_then_item_costs): every report shows the SAME cost as the journal
-- ledger: Cake 2 x 70 = 140 ; Mango 3 x 40 = 120 ; Typed + Nothing have no ledger cost.  Journal COGS = 260.
-- typed fallback: Typed 1 x 30 = 30 (estimate).  Nothing = unknown (20 revenue).  Report COGS = 260 + 30 = 290, costed revenue 490.
select tt.chk('R1 journal COGS of the sale = 260.00 (ledger only)', tt.jl('sale',:'sa','5000','d') = 260.00);
set role authenticated; select tt.as(:'o');
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd_
select tt.chk('R1 biz_daily: revenue 510, costed 490, COGS 290.00 (journal 260 + typed estimate 30)', :'bd_revenue'::numeric=510 and :'bd_costed_rev'::numeric=490 and :'bd_cogs'::numeric=290);
select tt.chk('R1 biz_items Cake = 140.00 (ledger 70, NOT typed 60 = 120)', (select cogs from biz_items(tt.today(),tt.today(),1) where item_id=:'ia'::uuid) = 140.00);
select tt.chk('R1 biz_items Mango = 120.00 (no typed cost, was blank before)', (select cogs from biz_items(tt.today(),tt.today(),1) where item_id=:'ib'::uuid) = 120.00);
select tt.chk('R1 biz_items Typed = 30.00 (typed fallback)', (select cogs from biz_items(tt.today(),tt.today(),1) where item_id=:'ic'::uuid) = 30.00);
select tt.chk('R1 biz_items Nothing = NULL (unknown), not 0', (select cogs is null from biz_items(tt.today(),tt.today(),1) where item_id=:'id_'::uuid));
select tt.chk('R1 biz_items total of the known items = biz_daily COGS 290', (select sum(cogs) from biz_items(tt.today(),tt.today(),1)) = :'bd_cogs'::numeric);
select tt.chk('R1 biz_items_cost88: Cake no estimate / Typed estimate 30 / Nothing cost_missing with 20 unknown revenue',
  (select fallback_cogs from biz_items_cost88(tt.today(),tt.today(),1) where item_id=:'ia'::uuid) = 0 and (select fallback_cogs from biz_items_cost88(tt.today(),tt.today(),1) where item_id=:'ic'::uuid) = 30
  and (select cost_missing from biz_items_cost88(tt.today(),tt.today(),1) where item_id=:'id_'::uuid) and (select unknown_cost_rev from biz_items_cost88(tt.today(),tt.today(),1) where item_id=:'id_'::uuid) = 20
  and not (select cost_missing from biz_items_cost88(tt.today(),tt.today(),1) where item_id=:'ia'::uuid));
select tt.chk('R1 report builder (item_sales) Cake cogs = 140.00', tt.rb(:'ia','cogs') = 140.00);
select tt.chk('R1 report builder Mango = 120.00, Typed = 30.00, Nothing blank (not 0)', tt.rb(:'ib','cogs') = 120.00 and tt.rb(:'ic','cogs') = 30.00 and tt.rb(:'id_','cogs') is null);
select tt.chk('R1 report builder: Cake = biz_items = ledger cost in the journal (140) - the same number on all three', tt.rb(:'ia','cogs') = (select cogs from biz_items(tt.today(),tt.today(),1) where item_id=:'ia'::uuid)
  and tt.ledger_cost(:'sa', :'ia'::uuid) = 140);
select tt.chk('R1 items_with_cost: Cake 70 (ledger average), Typed 30 (typed, no ledger), Mango 40 (ledger), Nothing has NO row', (select cost_price from items_with_cost() where item_id=:'ia'::uuid)=70
  and (select cost_price from items_with_cost() where item_id=:'ic'::uuid)=30 and (select cost_price from items_with_cost() where item_id=:'ib'::uuid)=40 and not exists (select 1 from items_with_cost() where item_id=:'id_'::uuid));
select tt.chk('R1 item_cost_status88: Nothing cost_missing, source none; Cake ledger; Typed item_costs', (select cost_missing and cost_price is null and source='none' from item_cost_status88() where item_id=:'id_'::uuid)
  and (select source from item_cost_status88() where item_id=:'ia'::uuid)='ledger' and (select source from item_cost_status88() where item_id=:'ic'::uuid)='item_costs');
select profit_source_check(tt.today(), tt.today(), 1) as psc \gset
select tt.chk('R1 profit_source_check: report 290 vs journal 260, fallback 30, unknown 20, flagged not agree', (:'psc'::jsonb->>'report_cogs')::numeric=290 and (:'psc'::jsonb->>'journal_cogs')::numeric=260 and (:'psc'::jsonb->>'fallback_cogs')::numeric=30
  and (:'psc'::jsonb->>'unknown_cost_rev')::numeric=20 and not (:'psc'::jsonb->>'agree')::boolean);
reset role;
select tt.chk('R1 _p27_pl (base of l1/l3/partner) COGS 290', (select o_cogs from _p27_pl(tt.today(), tt.today(), array[1])) = 290);

\echo == R2 ledger_avg: the typed cost is never used; what has no ledger cost is UNKNOWN
set role authenticated; select tt.as(:'o');
select set_rule('report_cost_source','"ledger_avg"') is null as r2 \gset
select tt.chk('R2 switch is ledger_avg', tt.rcs()='ledger_avg' and rule_txt('report_cost_source')='ledger_avg');
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd2_
-- known: Cake 140 + Mango 120 = 260 = the journal ; costed revenue 200 + 240 = 440 ; unknown revenue 70 (Typed 50 + Nothing 20)
select tt.chk('R2 biz_daily COGS 260 = journal 260, costed revenue 440', :'bd2_cogs'::numeric=260 and :'bd2_costed_rev'::numeric=440);
select tt.chk('R2 biz_items: Cake 140, Mango 120, Typed NULL, Nothing NULL', (select cogs from biz_items(tt.today(),tt.today(),1) where item_id=:'ia'::uuid)=140 and (select cogs from biz_items(tt.today(),tt.today(),1) where item_id=:'ib'::uuid)=120
  and (select cogs is null from biz_items(tt.today(),tt.today(),1) where item_id=:'ic'::uuid) and (select cogs is null from biz_items(tt.today(),tt.today(),1) where item_id=:'id_'::uuid));
select tt.chk('R2 report builder: Cake 140, Mango 120, Typed blank, Nothing blank', tt.rb(:'ia','cogs')=140 and tt.rb(:'ib','cogs')=120 and tt.rb(:'ic','cogs') is null and tt.rb(:'id_','cogs') is null);
select tt.chk('R2 items_with_cost: Cake 70, Mango 40, no row for Typed / Nothing', (select cost_price from items_with_cost() where item_id=:'ia'::uuid)=70 and (select cost_price from items_with_cost() where item_id=:'ib'::uuid)=40
  and not exists (select 1 from items_with_cost() where item_id in (:'ic'::uuid,:'id_'::uuid)));
select profit_source_check(tt.today(), tt.today(), 1) as psc2 \gset
select tt.chk('R2 profit_source_check: report 260 = journal 260, no fallback, unknown 70, difference 0', (:'psc2'::jsonb->>'report_cogs')::numeric=260 and (:'psc2'::jsonb->>'journal_cogs')::numeric=260 and (:'psc2'::jsonb->>'difference')::numeric=0
  and (:'psc2'::jsonb->>'fallback_cogs')::numeric=0 and (:'psc2'::jsonb->>'unknown_cost_rev')::numeric=70);
select acct_income_statement(tt.today(), tt.today(), 1) as ist2 \gset
select tt.chk('R2 income statement COGS 260 = biz_daily COGS (same place, same day)', (:'ist2'::jsonb->>'cogs')::numeric = :'bd2_cogs'::numeric);

\echo == R3 item_costs: the typed cost only (the old behaviour of biz_items / report builder)
select set_rule('report_cost_source','"item_costs"') is null as r3 \gset
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd3_
-- typed: Cake 2 x 60 = 120 ; Typed 1 x 30 = 30 ; Mango and Nothing have none -> COGS 150, costed revenue 250, unknown 260
select tt.chk('R3 biz_daily COGS 150 (typed only), costed revenue 250', :'bd3_cogs'::numeric=150 and :'bd3_costed_rev'::numeric=250);
select tt.chk('R3 biz_items: Cake 120, Typed 30, Mango NULL, Nothing NULL', (select cogs from biz_items(tt.today(),tt.today(),1) where item_id=:'ia'::uuid)=120 and (select cogs from biz_items(tt.today(),tt.today(),1) where item_id=:'ic'::uuid)=30
  and (select cogs is null from biz_items(tt.today(),tt.today(),1) where item_id=:'ib'::uuid) and (select cogs is null from biz_items(tt.today(),tt.today(),1) where item_id=:'id_'::uuid));
select tt.chk('R3 report builder: Cake 120, Typed 30, Mango / Nothing blank', tt.rb(:'ia','cogs')=120 and tt.rb(:'ic','cogs')=30 and tt.rb(:'ib','cogs') is null and tt.rb(:'id_','cogs') is null);
select tt.chk('R3 items_with_cost = the typed list exactly (Cake 60, Typed 30)', (select cost_price from items_with_cost() where item_id=:'ia'::uuid)=60 and (select cost_price from items_with_cost() where item_id=:'ic'::uuid)=30
  and not exists (select 1 from items_with_cost() where item_id in (:'ib'::uuid,:'id_'::uuid)));
select profit_source_check(tt.today(), tt.today(), 1) as psc3 \gset
select tt.chk('R3 the journal is NOT switched: journal COGS still 260, the report 150 is shown as a difference of -110', (:'psc3'::jsonb->>'journal_cogs')::numeric=260 and (:'psc3'::jsonb->>'report_cogs')::numeric=150 and (:'psc3'::jsonb->>'difference')::numeric=-110);
reset role;
select tt.chk('R3 journal entry itself unchanged by the switch (260.00)', tt.jl('sale',:'sa','5000','d') = 260.00);

\echo == R4 bad value falls back to the default; owner choice validated
set role authenticated; select tt.as(:'o');
select tt.err('R4 set_rule refuses a value that is not a choice', $q$select set_rule('report_cost_source','"nonsense"')$q$);
select set_rule('report_cost_source', null) is null as r4 \gset
select tt.chk('R4 back to the default (null = default) = ledger_then_item_costs', tt.rcs()='ledger_then_item_costs');
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd4_
select tt.chk('R4 default again = the R1 numbers (switch off = identical)', :'bd4_cogs'::numeric=290 and :'bd4_costed_rev'::numeric=490);

\echo == S1 cost secrecy: no cost for people without the cost grant
select tt.as(:'s');
select tt.chk('S1 plain staff: items_with_cost empty, item_cost_status88 empty', (select count(*) from items_with_cost())=0 and (select count(*) from item_cost_status88())=0);
select tt.err('S1 plain staff: biz_items_cost88 refused', $q$select * from biz_items_cost88(tt.today(),tt.today(),1)$q$, 'not allowed');
select tt.err('S1 plain staff: direct _cogs_lines72 / _line_cost88 / _item_cost_eff88 not callable', $q$select * from _cogs_lines72(tt.today(),tt.today(),array[1])$q$, 'permission denied');
select tt.err('S1 plain staff: _line_cost88 not callable', format($q$select _line_cost88(null,%L::uuid)$q$, :'ia'), 'permission denied');
select tt.chk('S1 plain staff: report builder returns no cost figure (cogs blank for every item)', tt.rb(:'ia','cogs') is null and tt.rb(:'ib','cogs') is null);
reset role;
insert into user_grants (user_id, grant_code) values (:'v','view_cost') on conflict do nothing;
set role authenticated; select tt.as(:'v');
select tt.chk('S1 cost-grant holder sees the effective cost list (Cake 70) and the same report cogs 140', (select cost_price from items_with_cost() where item_id=:'ia'::uuid)=70 and tt.rb(:'ia','cogs')=140);
select tt.chk('S1 cost-grant holder: item_cost_status88 lists the missing item', (select cost_missing from item_cost_status88() where item_id=:'id_'::uuid));
reset role;
select tt.chk('S1 item_costs table still not readable by plain staff (RLS untouched)', (select relrowsecurity from pg_class where relname='item_costs'));

\echo == P1 paste-twice
\i supabase/phase514.sql
select tt.chk('P1 second paste: rule value kept, same default', tt.rcs()='ledger_then_item_costs' and (select count(*) from rules where key='report_cost_source')=1);
select tt.chk('P1 second paste: numbers unchanged', (select o_cogs from _p27_pl(tt.today(), tt.today(), array[1])) = 290);

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
