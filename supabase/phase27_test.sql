-- FRESH DB ONLY. Phase 27 (profit reports L1-L5, T3, T4) tests.
--   ORDER="phase8 ... phase24 phase27" bash tests/sql/build_fresh_db.sh <db> ; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase27_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set r '00000000-0000-0000-0000-000000000003'
\set n '00000000-0000-0000-0000-000000000004'
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
-- row of a report by a text column value, e.g. tt.row(j, 'location_id', '1')
create or replace function tt.row(j jsonb, k text, v text) returns jsonb language sql immutable as $$ select r from jsonb_array_elements(j->'rows') r where r->>k = v limit 1 $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'r','rep3@s.app','{"full_name":"Reporter"}'), (:'n','none4@s.app','{"full_name":"None"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'r','salesperson'),(:'n','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'r',1),(:'r',2),(:'n',1) on conflict do nothing;

\echo == data (as postgres)
select (now() at time zone 'Asia/Dhaka')::date as td, date_trunc('month', (now() at time zone 'Asia/Dhaka')::date)::date as m1,
       (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) + interval '1 month - 1 day')::date as m2, to_char((now() at time zone 'Asia/Dhaka')::date, 'YYYY-MM') as tm \gset
select format('{"from":"%s","to":"%s"}', :'m1', :'m2') as per \gset
insert into items (code,name_bn,name_en,category,unit,tracked,is_active,sellable,sell_price) values
 ('P27-A','এ','Item A','Sweets','kg',true,true,true,100), ('P27-B','বি','Item B','Sweets','kg',true,true,true,50), ('P27-C','সি','Item C','Cakes','pc',true,true,true,20);
select id as ia from items where code='P27-A' \gset
select id as ib from items where code='P27-B' \gset
select id as ic from items where code='P27-C' \gset
insert into item_costs (item_id, cost_price) values (:'ia',60),(:'ic',10) on conflict (item_id) do update set cost_price = excluded.cost_price;
insert into sales (client_id,location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,paid,status) values
 (gen_random_uuid(),1,9701,:'td',now(),format('[{"item_id":"%s","qty":2,"price":100,"unit":"kg","amount":200},{"item_id":"%s","qty":1,"price":50,"unit":"kg","amount":50}]',:'ia',:'ib')::jsonb,250,0,250,'cash',:'s',250,'done'),
 (gen_random_uuid(),1,9702,:'td',now(),format('[{"item_id":"%s","qty":10,"price":20,"unit":"pc","amount":200}]',:'ic')::jsonb,200,20,180,'cash',:'s',180,'done'),
 (gen_random_uuid(),2,9703,:'td',now(),format('[{"item_id":"%s","qty":1,"price":100,"unit":"kg","amount":100}]',:'ia')::jsonb,100,0,100,'cash',:'s',100,'done'),
 (gen_random_uuid(),1,9704,:'td',now(),format('[{"item_id":"%s","qty":9,"price":100,"unit":"kg","amount":900}]',:'ia')::jsonb,999,0,999,'cash',:'s',999,'void');
select id as sid from sales where receipt=9701 and location_id=1 \gset
insert into sale_returns (sale_id,location_id,lines,amount,credit_amount,refund_amount,refund_mode,reason_code,status,created_at) values
 (:'sid',1,format('[{"item_id":"%s","qty":1,"price":100,"unit":"kg","amount":100}]',:'ia')::jsonb,100,0,100,'cash','x','done',now()),
 (:'sid',1,format('[{"item_id":"%s","qty":2,"price":100,"unit":"kg","amount":200}]',:'ia')::jsonb,200,0,200,'cash','x','void',now());
insert into location_settings (location_id,key,value) values (1,'fixed_cost_month','3100') on conflict (location_id,key) do update set value='3100';
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('10-2',1,9711,:'td','approved','{"lines":[{"head":"transport","amount":"25"},{"head":"transport","amount":75}]}','[]',:'s','st'),
 ('10-2',1,9712,:'td','draft','{"lines":[{"head":"transport","amount":5000}]}','[]',:'s','st'),
 ('10-2',2,9713,:'td','submitted','{"lines":[{"head":"other","amount":40}]}','[]',:'s','st'),
 ('02-2',1,9721,:'td','approved','{"pay":[{"name":"TestK - Cook","due":1000,"overtime":100,"adv_ded":200},{"name":"TestF - Clerk","due":"800","other":50,"other_ded":30},{"name":""}]}','[]',:'s','st'),
 ('02-2',1,9722,:'td','draft','{"pay":[{"name":"TestK - Cook","due":99999}]}','[]',:'s','st'),
 ('02-3',1,9731,:'td','approved',format('{"staff":"TestK - Cook","adv":[{"date":"%s","amount":500,"ded_now":100,"balance":400},{"date":"%s","amount":300,"ded_now":0,"balance":300}]}',:'td',:'td')::jsonb,'[]',:'s','st'),
 ('02-3',1,9732,(:'m1'::date - 40),'approved','{"staff":"TestK - Cook","adv":[{"date":"2020-01-01","amount":9000,"balance":999}]}','[]',:'s','st'),
 ('02-3',1,9733,:'td','approved',format('{"staff":"Zed","adv":[{"date":"2020-02-02","amount":70,"balance":50}]}')::jsonb,'[]',:'s','st'),
 ('02-3',1,9734,:'td','draft','{"staff":"TestF - Clerk","adv":[{"date":"2020-02-02","amount":777,"balance":777}]}','[]',:'s','st');
-- the 02-2 names are "name - post"; the 02-3 staff for TestK is written the same so that the name match works
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('01-2',1,9741,:'td','approved',format('{"month":"%s","scope":"loc","sales":330,"open_stock":100,"purchases":500,"close_stock":400,"x_rent":50,"x_misc":50,"salary":1950,"bank_charges":10}',:'tm')::jsonb,'[]',:'s','st'),
 ('01-2',1,9742,:'td','draft',format('{"month":"%s","scope":"loc","sales":1}',:'tm')::jsonb,'[]',:'s','st'),
 ('01-2',1,9743,:'td','submitted',format('{"month":"%s","scope":"all","sales":400}',:'tm')::jsonb,'[]',:'s','st'),
 ('01-2',1,9744,:'td','submitted','{"month":"foo","scope":"loc","sales":5}','[]',:'s','st');

\echo == shape
select tt.chk('T0 seven profit reports registered', (select count(*) from report_defs3 where grp='profit')=7);
select tt.chk('T0 flags: salary reports owner-only, cost reports cost', (select bool_and(owner_only) from report_defs3 where key in ('l1_pnl','l3_shop_pnl','l4_owner_sheet','t3_payroll','t4_staff_cost_ratio'))
  and (select bool_and(cost) from report_defs3 where key in ('l1_pnl','l2_margin','l3_shop_pnl','l4_owner_sheet','l5_breakeven')) and not (select owner_only from report_defs3 where key in ('l2_margin','l5_breakeven') limit 1)
  and not (select bool_or(cost) from report_defs3 where key in ('t3_payroll','t4_staff_cost_ratio')));
select tt.chk('T0 _r3q and helper functions are private', not has_function_privilege('authenticated','_r3q_l1_pnl(date,date,int[],jsonb)','execute') and not has_function_privilege('anon','_r3q_t3_payroll(date,date,int[],jsonb)','execute')
  and not has_function_privilege('authenticated','_p27_pl(date,date,int[])','execute') and not has_function_privilege('anon','_p27_pl(date,date,int[])','execute'));

\echo == owner
set role authenticated; select tt.as(:'o');
-- L1
select report_run2('l1_pnl', :'per'::jsonb) as j \gset
select tt.chk('L1 two shop-month rows', jsonb_array_length(:'j'::jsonb->'rows')=2 and tt.row(:'j'::jsonb,'location_id','1')->>'month'=:'tm');
select tt.chk('L1 loc1 sales 430, returns 100, net 330', (tt.row(:'j'::jsonb,'location_id','1')->>'sales')::numeric=430 and (tt.row(:'j'::jsonb,'location_id','1')->>'returns')::numeric=100 and (tt.row(:'j'::jsonb,'location_id','1')->>'net_sales')::numeric=330);
select tt.chk('L1 loc1 cogs 160 (costed lines net of returned cost), uncosted 15.15%', (tt.row(:'j'::jsonb,'location_id','1')->>'cogs')::numeric=160 and (tt.row(:'j'::jsonb,'location_id','1')->>'uncosted_pct')::numeric=15.15);
select tt.chk('L1 loc1 expenses 100 (draft out), salary 1950 (draft out), fixed 3100', (tt.row(:'j'::jsonb,'location_id','1')->>'expenses')::numeric=100 and (tt.row(:'j'::jsonb,'location_id','1')->>'salary')::numeric=1950 and (tt.row(:'j'::jsonb,'location_id','1')->>'fixed')::numeric=3100);
select tt.chk('L1 loc1 profit -4980, no gaps except the uncosted cogs', (tt.row(:'j'::jsonb,'location_id','1')->>'profit')::numeric=-4980 and tt.row(:'j'::jsonb,'location_id','1')->>'gaps'='cogs(uncosted)');
select tt.chk('L1 loc2: salary and fixed are null (not guessed), profit 0, gaps named', (tt.row(:'j'::jsonb,'location_id','2')->'salary') = 'null'::jsonb and (tt.row(:'j'::jsonb,'location_id','2')->'fixed')='null'::jsonb
  and (tt.row(:'j'::jsonb,'location_id','2')->>'expenses')::numeric=40 and (tt.row(:'j'::jsonb,'location_id','2')->>'profit')::numeric=0 and tt.row(:'j'::jsonb,'location_id','2')->>'gaps'='salary, fixed');
select tt.chk('L1 totals', (:'j'::jsonb->'totals'->>'net_sales')::numeric=430 and (:'j'::jsonb->'totals'->>'profit')::numeric=-4980 and (:'j'::jsonb->'totals'->>'salary')::numeric=1950);
select tt.chk('L1 location filter', jsonb_array_length(report_run2('l1_pnl', format('{"from":"%s","to":"%s","locations":[2]}',:'m1',:'m2')::jsonb)->'rows')=1);
select tt.chk('L1 partial period prorates fixed cost (1 of N days)', (select (tt.row(report_run2('l1_pnl', format('{"from":"%s","to":"%s"}',:'td',:'td')::jsonb),'location_id','1')->>'fixed')::numeric
  = round(3100.0 / extract(day from (date_trunc('month', :'td'::date) + interval '1 month - 1 day')), 2)));
-- returns rule off => gross
reset role; select set_rule('reports_net_of_returns','false') is null as roff \gset
set role authenticated; select tt.as(:'o');
select tt.chk('L1 rule reports_net_of_returns off: no return deduction', (tt.row(report_run2('l1_pnl', :'per'::jsonb),'location_id','1')->>'net_sales')::numeric=430);
reset role; select set_rule('reports_net_of_returns','true') is null as ron \gset
set role authenticated; select tt.as(:'o');
-- L3
select report_run2('l3_shop_pnl', :'per'::jsonb) as j \gset
select tt.chk('L3 shops side by side: loc1 profit -4980, -1509.09%, loc2 profit 0', jsonb_array_length(:'j'::jsonb->'rows')=2 and (tt.row(:'j'::jsonb,'location_id','1')->>'profit')::numeric=-4980
  and (tt.row(:'j'::jsonb,'location_id','1')->>'profit_pct')::numeric=-1509.09 and (tt.row(:'j'::jsonb,'location_id','2')->>'profit')::numeric=0 and (tt.row(:'j'::jsonb,'location_id','2')->>'uncosted_pct')::numeric=0);
select tt.chk('L3 default sort weakest shop first; totals', :'j'::jsonb->'rows'->0->>'location_id'='1' and (:'j'::jsonb->'totals'->>'net_sales')::numeric=430 and (:'j'::jsonb->'totals'->>'expenses')::numeric=140);
-- L2
select report_run2('l2_margin', :'per'::jsonb) as j \gset
select tt.chk('L2 item A: qty 2, revenue 200, cogs 120, margin 80 (40%)', (tt.row(:'j'::jsonb,'item_code','P27-A')->>'qty')::numeric=2 and (tt.row(:'j'::jsonb,'item_code','P27-A')->>'revenue')::numeric=200
  and (tt.row(:'j'::jsonb,'item_code','P27-A')->>'cogs')::numeric=120 and (tt.row(:'j'::jsonb,'item_code','P27-A')->>'margin')::numeric=80 and (tt.row(:'j'::jsonb,'item_code','P27-A')->>'margin_pct')::numeric=40);
select tt.chk('L2 item B has no cost: cogs/margin null, uncosted 100%', tt.row(:'j'::jsonb,'item_code','P27-B')->'cogs'='null'::jsonb and tt.row(:'j'::jsonb,'item_code','P27-B')->'margin'='null'::jsonb
  and (tt.row(:'j'::jsonb,'item_code','P27-B')->>'uncosted_pct')::numeric=100 and (tt.row(:'j'::jsonb,'item_code','P27-B')->>'revenue')::numeric=50);
select tt.chk('L2 item C discount share: revenue 180, cogs 100, margin 80, 44.44%', (tt.row(:'j'::jsonb,'item_code','P27-C')->>'revenue')::numeric=180 and (tt.row(:'j'::jsonb,'item_code','P27-C')->>'cogs')::numeric=100
  and (tt.row(:'j'::jsonb,'item_code','P27-C')->>'margin_pct')::numeric=44.44);
select tt.chk('L2 category Sweets: revenue 250, margin 80 on costed 200 (40%), uncosted 20%', (tt.row(:'j'::jsonb,'category','Sweets') is not null) and
  (select (r->>'revenue')::numeric=250 and (r->>'margin')::numeric=80 and (r->>'margin_pct')::numeric=40 and (r->>'uncosted_pct')::numeric=20 from jsonb_array_elements(:'j'::jsonb->'rows') r where r->>'level'='category' and r->>'category'='Sweets'));
select tt.chk('L2 category Cakes margin 80', (select (r->>'margin')::numeric=80 from jsonb_array_elements(:'j'::jsonb->'rows') r where r->>'level'='category' and r->>'category'='Cakes'));
select tt.chk('L2 5 rows (3 items + 2 categories); voided sale and void return not counted', jsonb_array_length(:'j'::jsonb->'rows')=5);
select report_run2('l2_margin', format('{"from":"%s","to":"%s","categories":["Cakes"]}',:'m1',:'m2')::jsonb) as j2 \gset
select tt.chk('L2 category filter keeps only Cakes (item + category row)', jsonb_array_length(:'j2'::jsonb->'rows')=2 and not exists (select 1 from jsonb_array_elements(:'j2'::jsonb->'rows') r where r->>'category'<>'Cakes'));
-- L4
select report_run2('l4_owner_sheet', :'per'::jsonb) as j \gset
select tt.chk('L4 submitted/approved sheets only (draft out): 3 rows', jsonb_array_length(:'j'::jsonb->'rows')=3);
select tt.chk('L4 loc sheet: sheet cogs 200, expenses 100, net -1930 vs system sales 330/cogs 160/net -1880, zero diffs',
  (select (r->>'sheet_cogs')::numeric=200 and (r->>'sheet_expenses')::numeric=100 and (r->>'sheet_net')::numeric=-1930 and (r->>'sys_sales')::numeric=330 and (r->>'sys_cogs')::numeric=160 and (r->>'sys_net')::numeric=-1880
     and (r->>'diff_sales')::numeric=0 and (r->>'diff_expenses')::numeric=0 and (r->>'diff_salary')::numeric=0 and (r->>'sys_uncosted_pct')::numeric=15.15
   from jsonb_array_elements(:'j'::jsonb->'rows') r where r->>'scope'='loc' and r->>'month'=:'tm'));
select tt.chk('L4 scope-all sheet compared with all shops: sheet 400 vs 430 = -30, sys cogs 220, sys expenses 140',
  (select (r->>'diff_sales')::numeric=-30 and (r->>'sys_cogs')::numeric=220 and (r->>'sys_expenses')::numeric=140 and r->'sheet_cogs'='null'::jsonb and r->'diff_salary'='null'::jsonb
   from jsonb_array_elements(:'j'::jsonb->'rows') r where r->>'scope'='all'));
select tt.chk('L4 unreadable month: system figures null, not guessed', (select r->'sys_sales'='null'::jsonb and r->'diff_sales'='null'::jsonb from jsonb_array_elements(:'j'::jsonb->'rows') r where r->>'month'='foo'));
-- L5
select report_run2('l5_breakeven', :'per'::jsonb) as j \gset
select tt.chk('L5 loc1: uncosted 15.15%, gm 42.86%, fixed 3100, break-even 7233.33, gap -6903.33, coverage 4.56%, monthly figures',
  (tt.row(:'j'::jsonb,'location_id','1')->>'uncosted_pct')::numeric=15.15 and (tt.row(:'j'::jsonb,'location_id','1')->>'gm_pct')::numeric=42.86 and (tt.row(:'j'::jsonb,'location_id','1')->>'fixed')::numeric=3100
  and (tt.row(:'j'::jsonb,'location_id','1')->>'be_sales')::numeric=7233.33 and (tt.row(:'j'::jsonb,'location_id','1')->>'gap')::numeric=-6903.33 and (tt.row(:'j'::jsonb,'location_id','1')->>'coverage_pct')::numeric=4.56
  and (tt.row(:'j'::jsonb,'location_id','1')->>'fixed_month')::numeric=3100 and (tt.row(:'j'::jsonb,'location_id','1')->>'be_month')::numeric=7233.33);
select tt.chk('L5 loc2 without fixed cost: gm 40%, break-even null', (tt.row(:'j'::jsonb,'location_id','2')->>'gm_pct')::numeric=40 and tt.row(:'j'::jsonb,'location_id','2')->'be_sales'='null'::jsonb and tt.row(:'j'::jsonb,'location_id','2')->'fixed_month'='null'::jsonb);
-- T3
select report_run2('t3_payroll', :'per'::jsonb) as j \gset
select tt.chk('T3 three people (TestK, TestF, Zed); drafts out', jsonb_array_length(:'j'::jsonb->'rows')=3);
select tt.chk('T3 TestK: gross 1100, adv ded 200, net 900, advance given 800, register ded 100, outstanding 700 (latest page, older page ignored)',
  (tt.row(:'j'::jsonb,'person','TestK - Cook')->>'gross_pay')::numeric=1100 and (tt.row(:'j'::jsonb,'person','TestK - Cook')->>'adv_deducted')::numeric=200 and (tt.row(:'j'::jsonb,'person','TestK - Cook')->>'net_pay')::numeric=900
  and (tt.row(:'j'::jsonb,'person','TestK - Cook')->>'adv_given')::numeric=800 and (tt.row(:'j'::jsonb,'person','TestK - Cook')->>'adv_register_deduction')::numeric=100 and (tt.row(:'j'::jsonb,'person','TestK - Cook')->>'adv_outstanding')::numeric=700);
select tt.chk('T3 TestF: gross 850, other ded 30, net 820, no advance register page', (tt.row(:'j'::jsonb,'person','TestF - Clerk')->>'net_pay')::numeric=820 and (tt.row(:'j'::jsonb,'person','TestF - Clerk')->>'other_deducted')::numeric=30 and tt.row(:'j'::jsonb,'person','TestF - Clerk')->'adv_outstanding'='null'::jsonb);
select tt.chk('T3 Zed: advance outstanding 50 with no salary sheet (net pay null)', (tt.row(:'j'::jsonb,'person','Zed')->>'adv_outstanding')::numeric=50 and tt.row(:'j'::jsonb,'person','Zed')->'net_pay'='null'::jsonb);
select tt.chk('T3 totals', (:'j'::jsonb->'totals'->>'gross_pay')::numeric=1950 and (:'j'::jsonb->'totals'->>'net_pay')::numeric=1720 and (:'j'::jsonb->'totals'->>'adv_outstanding')::numeric=750 and (:'j'::jsonb->'totals'->>'adv_given')::numeric=800);
-- T4
select report_run2('t4_staff_cost_ratio', :'per'::jsonb) as j \gset
select tt.chk('T4 loc1 salary 1950 / sales 330 = 590.91%; loc2 null (no salary sheet)', (tt.row(:'j'::jsonb,'location_id','1')->>'salary_pct')::numeric=590.91 and tt.row(:'j'::jsonb,'location_id','2')->'salary_pct'='null'::jsonb);
select tt.chk('T4 not a cost report (no cost used) but owner only', not (select cost from report_defs3 where key='t4_staff_cost_ratio') and (select owner_only from report_defs3 where key='t4_staff_cost_ratio'));

\echo == access
select tt.as(:'n');
select tt.err('A1 no grant: l2 closed', $$select report_run2('l2_margin','{}'::jsonb)$$, 'not allowed');
select tt.err('A1 no grant: t4 closed', $$select report_run2('t4_staff_cost_ratio','{}'::jsonb)$$, 'not allowed');
select tt.chk('A1 catalog: none allowed', not exists (select 1 from jsonb_array_elements(report_catalog2()) c where c->>'group'='profit' and (c->>'allowed')::boolean));
select tt.as(:'o'); select set_user_grant(:'r'::uuid,'report_profit') is null as g1 \gset
select tt.as(:'r');
select tt.err('A2 report_profit alone: cost report l2 closed', $$select report_run2('l2_margin','{}'::jsonb)$$, 'not allowed');
select tt.err('A2 report_profit alone: l5 closed', $$select report_run2('l5_breakeven','{}'::jsonb)$$, 'not allowed');
select tt.err('A2 report_profit alone: l1 (cost+owner) closed', $$select report_run2('l1_pnl','{}'::jsonb)$$, 'not allowed');
select tt.err('A2 report_profit alone: t3 (salary) closed', $$select report_run2('t3_payroll','{}'::jsonb)$$, 'not allowed');
select tt.err('A2 report_profit alone: t4 closed', $$select report_run2('t4_staff_cost_ratio','{}'::jsonb)$$, 'not allowed');
select tt.err('A2 report_profit alone: l3, l4 closed', $$select report_run2('l3_shop_pnl','{}'::jsonb)$$, 'not allowed');
select tt.err('A2 l4 closed', $$select report_run2('l4_owner_sheet','{}'::jsonb)$$, 'not allowed');
select tt.chk('A2 catalog: all seven flagged not allowed', (select count(*) from jsonb_array_elements(report_catalog2()) c where c->>'group'='profit' and not (c->>'allowed')::boolean)=7);
select tt.as(:'o'); select set_user_grant(:'r'::uuid,'view_cost') is null as g2 \gset
select tt.as(:'r');
select tt.chk('A3 report_profit + cost right: l2 opens; two locations', jsonb_array_length(report_run2('l2_margin', :'per'::jsonb)->'rows')=5);
select tt.chk('A3 l5 opens for cost right, two shops', jsonb_array_length(report_run2('l5_breakeven', :'per'::jsonb)->'rows')=2);
select tt.err('A3 cost right still does not open salary: l1', $$select report_run2('l1_pnl','{}'::jsonb)$$, 'not allowed');
select tt.err('A3 cost right still does not open salary: t3', $$select report_run2('t3_payroll','{}'::jsonb)$$, 'not allowed');
select tt.err('A3 cost right still does not open salary: t4', $$select report_run2('t4_staff_cost_ratio','{}'::jsonb)$$, 'not allowed');
select tt.err('A3 l4 closed', $$select report_run2('l4_owner_sheet','{}'::jsonb)$$, 'not allowed');
-- location scoping: staff of location 1 only
select tt.as(:'o'); select set_user_grant(:'s'::uuid,'report_profit') is null as g3 \gset
select set_user_grant(:'s'::uuid,'view_cost') is null as g4 \gset
select tt.as(:'s');
select report_run2('l2_margin', :'per'::jsonb) as j \gset
select tt.chk('A4 location-1 user: item A revenue 100 (sale 200 - return 100 at loc 1 only, loc2 sale hidden)', (tt.row(:'j'::jsonb,'item_code','P27-A')->>'revenue')::numeric=100 and (tt.row(:'j'::jsonb,'item_code','P27-A')->>'qty')::numeric=1);
select report_run2('l5_breakeven', :'per'::jsonb) as j \gset
select tt.chk('A4 location-1 user sees only shop 1 in l5', jsonb_array_length(:'j'::jsonb->'rows')=1 and tt.row(:'j'::jsonb,'location_id','1') is not null);
select tt.as(:'o');
select tt.chk('A5 owner catalog: seven allowed', (select count(*) from jsonb_array_elements(report_catalog2()) c where c->>'group'='profit' and (c->>'allowed')::boolean)=7);
reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
