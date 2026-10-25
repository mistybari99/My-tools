-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase131_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase527_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY (canonical build incl. phase527).  Phase 527 tests = reports Stage 1 (sales net of voids/returns, status + books tie-out, item profit, stock reconciliation,
--   wastage, cash book / day close, receivable + payable ageing). Hand-computed numbers on seeded data, two outlets, scope, cost / books secrecy, empty data, paging, export log.
--   psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase527_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root)
\i tests/sql/e2e/00_common.sql
\set mg1 '00000000-0000-0000-0000-000000000411'
\set mg2 '00000000-0000-0000-0000-000000000412'
\set nog '00000000-0000-0000-0000-000000000413'
\set cst '00000000-0000-0000-0000-000000000414'
\set acv '00000000-0000-0000-0000-000000000415'
\set nol '00000000-0000-0000-0000-000000000416'
\echo == T0 setup: sweets, two outlets (1 = main, 2 = branch), items, stock, sales on 3 days, voids, returns, a collection, purchases; posted in two batches so some documents stay unposted
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@r131.app','{"full_name":"Owner"}'),(:'mg1','mg1@r131.app','{"full_name":"Mgr1"}'),(:'mg2','mg2@r131.app','{"full_name":"Mgr2"}'),
 (:'nog','nog@r131.app','{"full_name":"NoGrant"}'),(:'cst','cst@r131.app','{"full_name":"CostUser"}'),(:'acv','acv@r131.app','{"full_name":"AcctView"}'),(:'nol','nol@r131.app','{"full_name":"NoPlace"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'mg1','salesperson'),(:'mg2','salesperson'),(:'nog','salesperson'),(:'cst','salesperson'),(:'acv','salesperson'),(:'nol','salesperson') on conflict do nothing;
insert into user_locations values (:'mg1',1),(:'mg2',2),(:'nog',1),(:'cst',1),(:'acv',1) on conflict do nothing;
select tt.as(:'o');
select set_user_grant(:'mg1'::uuid,'view_reports') is null as g1 \gset
select set_user_grant(:'mg2'::uuid,'view_reports') is null as g2 \gset
select set_user_grant(:'cst'::uuid,'view_reports') is null as g3 \gset
select set_user_grant(:'cst'::uuid,'view_cost') is null as g4 \gset
select set_user_grant(:'acv'::uuid,'view_reports') is null as g5 \gset
select set_user_grant(:'acv'::uuid,'accounts_view') is null as g6 \gset
select set_user_grant(:'nol'::uuid,'view_reports') is null as g7 \gset
select set_user_grant(:'mg1'::uuid,'view_stock_recon') is null as g8 \gset
select set_user_grant(:'mg2'::uuid,'view_stock_recon') is null as g9 \gset
select set_user_grant(:'mg1'::uuid,'wastage_write_off') is null as g10 \gset
select acct_set_start(tt.today()-10)->>'start' as sd \gset
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable,category) values
 ('R-CAKE','Cake','Cake','kg','kg','finished_good',true,300,true,'bakery'),('R-BUN','Bun','Bun','pc','pc','finished_good',true,20,true,'bakery'),('R-SWT','Sweet','Sweet','kg','kg','finished_good',true,100,true,'sweets'),
 ('R-FLR','Flour','Flour','kg','kg','raw_material',true,0,false,'raw'),('R-SUG','Sugar','Sugar','kg','kg','raw_material',true,0,false,'raw'),('R-NOC','No cost item','No cost item','pc','pc','finished_good',true,50,true,'bakery');
select stock_opening(tt.iid('R-CAKE'),1,50,180) is not null as o1 \gset
select stock_opening(tt.iid('R-BUN'),1,200,12) is not null as o2 \gset
select stock_opening(tt.iid('R-SWT'),1,40,60) is not null as o3 \gset
select stock_opening(tt.iid('R-SWT'),2,30,60) is not null as o4 \gset
select acct_opening('[{"code":"1110","debit":5000,"location_id":1},{"code":"3100","credit":5000}]'::jsonb)->>'id' as oj \gset
select set_rule('accounting_on','true') is null as a_on \gset
-- three days ago (D1)
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":3,"price":300}]',tt.iid('R-CAKE'))::jsonb,0,'[{"mode":"cash","amount":900}]',null,null,'retail',null,false,now()-interval '3 days')->>'id' as s1 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":10,"price":20}]',tt.iid('R-BUN'))::jsonb,20,'[{"mode":"mobile","amount":180}]',null,null,'retail',null,false,now()-interval '3 days')->>'id' as s2 \gset
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":4,"price":100}]',tt.iid('R-SWT'))::jsonb,0,'[{"mode":"card","amount":400}]',null,null,'retail',null,false,now()-interval '3 days')->>'id' as s3 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":300}]',tt.iid('R-CAKE'))::jsonb,0,'[{"mode":"cash","amount":100}]','01711000001','test_user_b','retail',null,false,now()-interval '3 days')->>'id' as s4 \gset
-- nine days ago (the server re-dates sales older than 72 h to now - audit gap A2-G10 - so the date is set by hand for this seed only)
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":300},{"item_id":"%s","qty":5,"price":20}]',tt.iid('R-CAKE'),tt.iid('R-BUN'))::jsonb,0,'[]','01711000002','test_user_a','retail',null,false,now()-interval '9 days')->>'id' as s10 \gset
update sales set sold_at = now() - interval '9 days', sale_date = tt.today() - 9 where id = :'s10'::uuid;
-- two days ago (D2)
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":5,"price":20}]',tt.iid('R-BUN'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,now()-interval '2 days')->>'id' as s5 \gset
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":1,"price":100}]',tt.iid('R-SWT'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,now()-interval '2 days')->>'id' as s6 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":6,"price":20}]',tt.iid('R-BUN'))::jsonb,0,'[{"mode":"cash","amount":120}]',null,null,'retail',null,false,now()-interval '2 days')->>'id' as s7 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":300}]',tt.iid('R-CAKE'))::jsonb,0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false,now()-interval '2 days')->>'id' as s8 \gset
select void_sale(:'s8'::uuid,'voided before it was ever posted') is not null as v8 \gset
-- purchases: Sup Main (7 credit days) 100 kg flour @40 = 4000 nine days ago, 1000 paid in cash; Sup Two (no credit days) 50 kg sugar @60 = 3000 two days ago
with s as (insert into suppliers (name, credit_days) values ('Sup Main', 7) returning id) select id as sp1 from s \gset
with s as (insert into suppliers (name, credit_days) values ('Sup Two', null) returning id) select id as sp2 from s \gset
select save_purchase(gen_random_uuid(),null,:'sp1'::uuid,1,'PB1',tt.today()-9,format('[{"item_id":"%s","qty":100,"unit":"kg","unit_cost":40}]',tt.iid('R-FLR'))::jsonb)->>'id' as pb1 \gset
select post_purchase(:'pb1'::uuid) is not null as pp1 \gset
select save_purchase(gen_random_uuid(),null,:'sp2'::uuid,1,'PB2',tt.today()-2,format('[{"item_id":"%s","qty":50,"unit":"kg","unit_cost":60}]',tt.iid('R-SUG'))::jsonb)->>'id' as pb2 \gset
select post_purchase(:'pb2'::uuid) is not null as pp2 \gset
select bill_pay_record('purchase',:'pb1','cash',1000,gen_random_uuid()) is not null as bp1 \gset
-- first posting batch, then a void that the next batch reverses (S6)
select acct_post_pending() ->> 'posted' as post1 \gset
select void_sale(:'s6'::uuid,'voided after posting') is not null as v6 \gset
select acct_post_pending() ->> 'posted' as post2 \gset
-- today: returns (R1 cash refund 300; R2 goes to the customer account as credit 300), a part collection 150
select sale_return(gen_random_uuid(), :'s1'::uuid, format('[{"item_id":"%s","qty":1}]',tt.iid('R-CAKE'))::jsonb, 'damaged','r1','cash') ->> 'id' as r1 \gset
select sale_return(gen_random_uuid(), :'s4'::uuid, format('[{"item_id":"%s","qty":1}]',tt.iid('R-CAKE'))::jsonb, 'damaged','r2','cash') ->> 'id' as r2 \gset
select collect_payment(gen_random_uuid(),1,(select customer_id from sales where id=:'s4'::uuid),'[{"mode":"cash","amount":150}]'::jsonb,'part') is not null as col \gset
select acct_post_pending() ->> 'posted' as post3 \gset
-- S7 is voided AFTER the last posting run and never reversed in the books
select void_sale(:'s7'::uuid,'voided, books not reversed') is not null as v7 \gset
-- wastage (owner: posted), a count adjustment
select stock_wastage(tt.iid('R-BUN'),1,4,'expired',null,null,null,gen_random_uuid()) ->> 'ledger_id' as w1 \gset
select stock_wastage(tt.iid('R-CAKE'),1,1,'broken',null,null,null,gen_random_uuid()) ->> 'ledger_id' as w2 \gset
select stock_wastage(tt.iid('R-SWT'),2,2,'expired',null,null,null,gen_random_uuid()) ->> 'ledger_id' as w3 \gset
select stock_count_adjust(tt.iid('R-SWT'),1,39,'count',null,gen_random_uuid()) is not null as ca \gset
-- documents after the last posting run: unposted
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":10,"price":20}]',tt.iid('R-BUN'))::jsonb,0,'[{"mode":"cash","amount":200}]',null,null,'retail',null,false)->>'id' as s9 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":4,"price":20}]',tt.iid('R-BUN'))::jsonb,0,'[]','01711000002','test_user_a','retail',null,false)->>'id' as s11 \gset
select sale_return(gen_random_uuid(), :'s5'::uuid, format('[{"item_id":"%s","qty":1}]',tt.iid('R-BUN'))::jsonb, 'damaged','r3','cash') ->> 'id' as r3 \gset
-- the daily showroom sheet 14-1 of outlet 1, three days ago: counted 50 short
insert into entries (form_code, location_id, serial, entry_date, status, data, flags, created_by, created_staff) values ('14-1', 1, 9001, tt.today()-3, 'submitted', '{}', '[{"code":"cash_short_over","amount":-50}]', :'o', 'OWN');
select tt.eq('T0 seed: 11 sales exist (4 + 1 + 4 + 2 documents of the story)', 11, (select count(*) from sales));
select tt.eq('T0 seed: statuses 8 done / 3 void', 8, (select count(*) from sales where status='done'));
select tt.eq('T0 seed: three returns, two cash refunds (300, 20) and one credit (300)', 3, (select count(*) from sale_returns where status='done' and ((refund_amount=300 and credit_amount=0) or (refund_amount=0 and credit_amount=300) or (refund_amount=20))));
select tt.eq('T0 seed: S6 original + reversal, S7 original only, S8 never posted', 3, (select (select count(*) from journal_entries where source_type='sale' and source_id=:'s6') + (select count(*) from journal_entries where source_type='sale' and source_id=:'s7')));
select tt.eq('T0 seed: S9, S11 and R3 are not in the books yet', 0, (select count(*) from journal_entries where (source_type='sale' and source_id in (:'s9', :'s11')) or (source_type='sale_return' and source_id=:'r3')));
select tt.t('T0 seed: the books are balanced (every entry debit = credit)', tt.unbalanced() = 0);

\echo == T1 switch OFF (default): every report says off, reads nothing; no right = refused
select tt.t('T1 rule rpt131_on exists, switch, default OFF', (select kind='switch' and default_value='false'::jsonb from rules where key='rpt131_on') and not rule_on('rpt131_on'));
select tt.t('T1 catalogue says disabled', (rpt131_catalog() ->> 'enabled')::boolean is false);
select tt.t('T1 sales: off:true, data_needed:true, no rows, totals null', (select (j->>'off')::boolean and (j->>'data_needed')::boolean and jsonb_array_length(j->'rows')=0 and j->'totals'='null'::jsonb from (select rpt131_sales(tt.today()-3, tt.today()) j) z));
select tt.t('T1 all seven reports answer off', (select bool_and((j->>'off')::boolean) from (select rpt131_sales(tt.today()-3, tt.today()) j union all select rpt131_sales_recon(tt.today()-3, tt.today()) union all select rpt131_item_profit(tt.today()-3, tt.today())
   union all select rpt131_stock_recon(tt.today()-3, tt.today()) union all select rpt131_wastage(tt.today()-3, tt.today()) union all select rpt131_cash_close(tt.today()-3, tt.today()) union all select rpt131_ageing('receivable')) z));
select tt.as(:'nog');
select tt.err('T1 a user without a report right is refused (even while off)', $$select rpt131_sales(current_date-3, current_date)$$, 'not allowed');
select tt.as(:'o'); select set_rule('rpt131_on','true') is null as on1 \gset

\echo == T2 switch ON: catalogue and rights
select tt.t('T2 catalogue enabled, seven reports', (rpt131_catalog() ->> 'enabled')::boolean and jsonb_array_length(rpt131_catalog() -> 'reports') = 7);
select tt.as(:'nog');
select tt.t('T2 catalogue for a user without rights: every report allowed:false', (select bool_and(not (r->>'allowed')::boolean) from jsonb_array_elements(rpt131_catalog()->'reports') r));
select tt.err('T2 no right: sales refused', $$select rpt131_sales(current_date-3, current_date)$$, 'not allowed');
select tt.err('T2 no right: ageing refused', $$select rpt131_ageing('payable')$$, 'not allowed');
select tt.as(:'mg1');
select tt.t('T2 view_reports user: every report allowed', (select bool_and((r->>'allowed')::boolean) from jsonb_array_elements(rpt131_catalog()->'reports') r));
select tt.as(:'o');

\echo == T3 sales net of voids and returns - hand numbers (7 done bills 2480 gross, 20 discount, 2460 sales; 3 returns 620; 3 voids 520; net 1840)
select rpt131_sales(tt.today()-3, tt.today(), null, 'day') as jd \gset
select tt.eq('T3 bills', 7, (:'jd'::jsonb #>> '{totals,bills}')::numeric);
select tt.eq('T3 gross 900+200+400+600+100+200+80', 2480, (:'jd'::jsonb #>> '{totals,gross}')::numeric);
select tt.eq('T3 discount', 20, (:'jd'::jsonb #>> '{totals,discount}')::numeric);
select tt.eq('T3 sales 2460', 2460, (:'jd'::jsonb #>> '{totals,sales_net}')::numeric);
select tt.eq('T3 returns 300+300+20', 620, (:'jd'::jsonb #>> '{totals,returns}')::numeric);
select tt.eq('T3 net sales 2460 - 620', 1840, (:'jd'::jsonb #>> '{totals,net_sales}')::numeric);
select tt.eq('T3 void bills 3 (S6 100, S7 120, S8 300), never counted in sales', 3, (:'jd'::jsonb #>> '{totals,void_bills}')::numeric);
select tt.eq('T3 void value 520', 520, (:'jd'::jsonb #>> '{totals,void_value}')::numeric);
select tt.eq('T3 three day rows', 3, (:'jd'::jsonb ->> 'row_count')::numeric);
select tt.is('T3 day 1 (3 days ago): 4 bills, 2080, no returns', '4|2080.00|0.00|2080.00|520.00', (select (r->>'bills')||'|'||(r->>'sales_net')||'|'||(r->>'returns')||'|'||(r->>'net_sales')||'|'||(r->>'avg_bill') from jsonb_array_elements(:'jd'::jsonb->'rows') r where r->>'dim' = (tt.today()-3)::text));
select tt.is('T3 day 2: 1 bill 100; 3 voids 520', '1|100.00|3|520.00', (select (r->>'bills')||'|'||(r->>'net_sales')||'|'||(r->>'void_bills')||'|'||(r->>'void_value') from jsonb_array_elements(:'jd'::jsonb->'rows') r where r->>'dim' = (tt.today()-2)::text));
select tt.is('T3 today: 2 bills 280, 3 returns 620 -> net -340 (a day can be negative)', '2|280.00|3|620.00|-340.00', (select (r->>'bills')||'|'||(r->>'sales_net')||'|'||(r->>'return_count')||'|'||(r->>'returns')||'|'||(r->>'net_sales') from jsonb_array_elements(:'jd'::jsonb->'rows') r where r->>'dim' = tt.today()::text));
select tt.t('T3 generated-at, filters, columns and notes are in the answer', (:'jd'::jsonb ? 'generated_at') and (:'jd'::jsonb #>> '{filters,from}') = (tt.today()-3)::text and jsonb_array_length(:'jd'::jsonb->'columns') >= 8 and jsonb_array_length(:'jd'::jsonb->'notes') >= 1);
select rpt131_sales(tt.today()-3, tt.today(), null, 'outlet') as jo \gset
select tt.is('T3 outlet 1: 6 bills, sales 2060, returns 620, net 1440', '6|2060.00|620.00|1440.00', (select (r->>'bills')||'|'||(r->>'sales_net')||'|'||(r->>'returns')||'|'||(r->>'net_sales') from jsonb_array_elements(:'jo'::jsonb->'rows') r where r->>'dim' = '1'));
select tt.is('T3 outlet 2: 1 bill 400, one void 100', '1|400.00|0.00|400.00|1|100.00', (select (r->>'bills')||'|'||(r->>'sales_net')||'|'||(r->>'returns')||'|'||(r->>'net_sales')||'|'||(r->>'void_bills')||'|'||(r->>'void_value') from jsonb_array_elements(:'jo'::jsonb->'rows') r where r->>'dim' = '2'));
select tt.eq('T3 two-outlet reconciliation: outlet 1 net + outlet 2 net = combined net', 1840, (select sum((r->>'net_sales')::numeric) from jsonb_array_elements(:'jo'::jsonb->'rows') r));
select rpt131_sales(tt.today()-3, tt.today(), null, 'pay_mode') as jp \gset
select tt.is('T3 payment method cash: received 1300 (900+100+100+200), refunded 320, net 980; collections 150 shown apart', '1300.00|320.00|980.00|150.00', (select (r->>'received')||'|'||(r->>'refunded')||'|'||(r->>'net_sales')||'|'||(r->>'collections') from jsonb_array_elements(:'jp'::jsonb->'rows') r where r->>'dim'='cash'));
select tt.is('T3 payment method mobile 180 / card 400', '180.00|400.00', (select (select (r->>'net_sales') from jsonb_array_elements(:'jp'::jsonb->'rows') r where r->>'dim'='mobile')||'|'||(select (r->>'net_sales') from jsonb_array_elements(:'jp'::jsonb->'rows') r where r->>'dim'='card')));
select tt.is('T3 on credit: sold 500+80 = 580, credit given back on returns 300, net 280', '580.00|300.00|280.00', (select (r->>'received')||'|'||(r->>'refunded')||'|'||(r->>'net_sales') from jsonb_array_elements(:'jp'::jsonb->'rows') r where r->>'dim'='due'));
select tt.eq('T3 payment-method net total = net sales 1840 (980+180+400+280)', 1840, (:'jp'::jsonb #>> '{totals,net_sales}')::numeric);
select tt.t('T3 every grouping adds up to the same net 1840', (select bool_and((rpt131_sales(tt.today()-3, tt.today(), null, g) #>> '{totals,net_sales}')::numeric = 1840) from unnest(array['day','week','month','outlet','hour','weekday','staff','sale_type']) g));
select tt.eq('T3 weekday: three different days -> three rows', 3, (rpt131_sales(tt.today()-3, tt.today(), null, 'weekday') ->> 'row_count')::numeric);
select tt.eq('T3 sale type: retail only', 1, (rpt131_sales(tt.today()-3, tt.today(), null, 'sale_type') ->> 'row_count')::numeric);
select tt.eq('T3 one outlet only (p_locs = {2})', 400, (rpt131_sales(tt.today()-3, tt.today(), array[2], 'day') #>> '{totals,net_sales}')::numeric);
select tt.is('T3 sort by net sales ascending: first row is the negative day', '-340.00', (rpt131_sales(tt.today()-3, tt.today(), null, 'day', null, 'net_sales:asc') -> 'rows' -> 0 ->> 'net_sales'));
select tt.is('T3 paging: size 5 of 3 rows -> no more', 'false', (rpt131_sales(tt.today()-3, tt.today(), null, 'day', null, null, 1, 5) ->> 'has_more'));
select tt.err('T3 bad group refused', $$select rpt131_sales(current_date-3, current_date, null, 'colour')$$, 'bad_group');
select tt.err('T3 range over 366 days refused', $$select rpt131_sales(current_date-400, current_date)$$, 'bad_range');
select tt.err('T3 from after to refused', $$select rpt131_sales(current_date, current_date-3)$$, 'bad_range');
select tt.t('T3 no dates: month to date with a note', (select exists (select 1 from jsonb_array_elements(rpt131_sales() -> 'notes') n where n->>'code' = 'default_period')));

\echo == T4 sales documents: status, books tie-out, no double counting of voids / refunds / reversals
select rpt131_sales_recon(tt.today()-3, tt.today()) as jr \gset
select tt.eq('T4 13 documents = 10 sales (S1-S9, S11) + 3 returns', 13, (:'jr'::jsonb ->> 'row_count')::numeric);
select tt.eq('T4 register net = 1840 (same as the sales report)', 1840, (:'jr'::jsonb #>> '{summary,register_net_total}')::numeric);
select tt.eq('T4 books net by document = 1700', 1700, (:'jr'::jsonb #>> '{summary,docs_books_net_total}')::numeric);
select tt.eq('T4 journal by entry date = 1700 (same: the S6 reversal falls inside the period)', 1700, (:'jr'::jsonb #>> '{tie_out,journal_by_entry_date}')::numeric);
select tt.eq('T4 journal by entry date = income statement total income for the period', (acct_income_statement(tt.today()-3, tt.today()) ->> 'total_income')::numeric, (:'jr'::jsonb #>> '{tie_out,journal_by_entry_date}')::numeric);
select tt.eq('T4 gap register - books = 140 = unposted 260 (S9 200 + S11 80 - R3 20) - not reversed 120', 140, (:'jr'::jsonb #>> '{tie_out,explained_gap}')::numeric);
select tt.eq('T4 unposted value 200 + 80 - 20', 260, (:'jr'::jsonb #>> '{summary,unposted_value}')::numeric);
select tt.eq('T4 one void sale still carried by the books', 1, (:'jr'::jsonb #>> '{summary,not_reversed_docs}')::numeric);
select tt.eq('T4 no posted document differs from its books amount', 0, (:'jr'::jsonb #>> '{summary,amount_differs_value}')::numeric);
select tt.is('T4 posted sales: 5 documents 2180', '5|2180.00', (select (v->>'docs')||'|'||(v->>'register_net') from (select :'jr'::jsonb #> '{summary,by_status,posted/sale}' v) z));
select tt.is('T4 reversed sale (S6): register 0, books 0 (original + reversal)', '1|0.00|0.00', (select (v->>'docs')||'|'||(v->>'register_net')||'|'||(v->>'books_net') from (select :'jr'::jsonb #> '{summary,by_status,reversed/sale}' v) z));
select tt.is('T4 void never posted (S8): register 0, books 0', '1|0.00|0.00', (select (v->>'docs')||'|'||(v->>'register_net')||'|'||(v->>'books_net') from (select :'jr'::jsonb #> '{summary,by_status,void/sale}' v) z));
select tt.is('T4 void not reversed (S7): register 0, books 120', '1|0.00|120.00', (select (v->>'docs')||'|'||(v->>'register_net')||'|'||(v->>'books_net') from (select :'jr'::jsonb #> '{summary,by_status,void_not_reversed/sale}' v) z));
select tt.is('T4 posted returns: 2 documents -600 in both', '2|-600.00|-600.00', (select (v->>'docs')||'|'||(v->>'register_net')||'|'||(v->>'books_net') from (select :'jr'::jsonb #> '{summary,by_status,posted/return}' v) z));
select tt.is('T4 unposted return R3: register -20, books 0', '1|-20.00|0.00', (select (v->>'docs')||'|'||(v->>'register_net')||'|'||(v->>'books_net') from (select :'jr'::jsonb #> '{summary,by_status,unposted/return}' v) z));
select tt.is('T4 unposted sales S9 + S11: 280', '2|280.00', (select (v->>'docs')||'|'||(v->>'register_net') from (select :'jr'::jsonb #> '{summary,by_status,unposted/sale}' v) z));
select tt.eq('T4 status filter unposted: 3 rows', 3, (rpt131_sales_recon(tt.today()-3, tt.today(), null, 'unposted') ->> 'row_count')::numeric);
select tt.eq('T4 status filter void_not_reversed: 1 row', 1, (rpt131_sales_recon(tt.today()-3, tt.today(), null, 'void_not_reversed') ->> 'row_count')::numeric);
select tt.eq('T4 status filter reversed: 1', 1, (rpt131_sales_recon(tt.today()-3, tt.today(), null, 'reversed') ->> 'row_count')::numeric);
select tt.eq('T4 status filter void: 1', 1, (rpt131_sales_recon(tt.today()-3, tt.today(), null, 'void') ->> 'row_count')::numeric);
select tt.eq('T4 status filter posted: 7 (5 sales + 2 returns)', 7, (rpt131_sales_recon(tt.today()-3, tt.today(), null, 'posted') ->> 'row_count')::numeric);
select tt.eq('T4 status filter refunded: 3 returns + 3 sales that have a return', 6, (rpt131_sales_recon(tt.today()-3, tt.today(), null, 'refunded') ->> 'row_count')::numeric);
select tt.eq('T4 status filter problems: 3 unposted + 1 not reversed', 4, (rpt131_sales_recon(tt.today()-3, tt.today(), null, 'problems') ->> 'row_count')::numeric);
select tt.is('T4 refund state: S1 partial (1 of 3 kg), S4 partial', 'partial|partial', (select (select r->>'refund_state' from jsonb_array_elements(:'jr'::jsonb->'rows') r where r->>'doc_id' = :'s1')||'|'||(select r->>'refund_state' from jsonb_array_elements(:'jr'::jsonb->'rows') r where r->>'doc_id' = :'s4')));
select tt.is('T4 flags: unposted / books_not_reversed', 'unposted|books_not_reversed', (select (select r->>'flag' from jsonb_array_elements(:'jr'::jsonb->'rows') r where r->>'doc_id' = :'s9')||'|'||(select r->>'flag' from jsonb_array_elements(:'jr'::jsonb->'rows') r where r->>'doc_id' = :'s7')));
select tt.eq('T4 gross total counts only done bills (2480, not the voids)', 2480, (:'jr'::jsonb #>> '{totals,gross}')::numeric);
select tt.eq('T4 paging size 5: page 2 has 5 rows, more follows', 5, jsonb_array_length(rpt131_sales_recon(tt.today()-3, tt.today(), null, 'all', null, null, 2, 5) -> 'rows'));
select tt.is('T4 paging page 3: 3 rows, no more', '3|false', (select jsonb_array_length(j->'rows')||'|'||(j->>'has_more') from (select rpt131_sales_recon(tt.today()-3, tt.today(), null, 'all', null, null, 3, 5) j) z));
select tt.is('T4 sort by register net ascending: first row is a 300 return', '-300.00', (rpt131_sales_recon(tt.today()-3, tt.today(), null, 'all', null, 'register_net:asc') -> 'rows' -> 0 ->> 'register_net'));
select tt.eq('T4 search test_user_a: the one sale', 1, (rpt131_sales_recon(tt.today()-3, tt.today(), null, 'all', 'test_user_a') ->> 'row_count')::numeric);
select tt.eq('T4 search test_user_b: the sale and its return', 2, (rpt131_sales_recon(tt.today()-3, tt.today(), null, 'all', 'test_user_b') ->> 'row_count')::numeric);
select tt.eq('T4 search total follows the rows (test_user_a 80)', 80, (rpt131_sales_recon(tt.today()-3, tt.today(), null, 'all', 'test_user_a') #>> '{totals,register_net}')::numeric);
select rpt131_sales_recon(tt.today()-2, tt.today()-2) as jn \gset
select tt.eq('T4 narrow period (2 days ago): books by document 220 (S5 100 + S7 120)', 220, (:'jn'::jsonb #>> '{summary,docs_books_net_total}')::numeric);
select tt.eq('T4 narrow period: journal by entry date 320 (the S6 reversal is dated later)', 320, (:'jn'::jsonb #>> '{tie_out,journal_by_entry_date}')::numeric);
select tt.t('T4 the date gap is explained in a note', exists (select 1 from jsonb_array_elements(:'jn'::jsonb->'notes') n where n->>'code' = 'journal_date_gap'));
select tt.err('T4 recon range over 92 days refused', $$select rpt131_sales_recon(current_date-100, current_date)$$, 'bad_range');
select tt.err('T4 bad status refused', $$select rpt131_sales_recon(current_date-3, current_date, null, 'draft')$$, 'bad_status');
select tt.t('T4 sales have no draft state - said in the notes', exists (select 1 from jsonb_array_elements(:'jr'::jsonb->'notes') n where n->>'text_en' like '%Draft does not exist%'));

\echo == T5 item / category / outlet profit with real ledger costs (cake 3 kg 900 cost 540; bun 28 pc 540 cost 336; sweet 4 kg 400 cost 240)
select rpt131_item_profit(tt.today()-3, tt.today(), null, 'item') as ji \gset
select tt.eq('T5 revenue total 1840 = net sales (three-way agreement with T3 and T4)', 1840, (:'ji'::jsonb #>> '{totals,revenue}')::numeric);
select tt.eq('T5 real cost total 540+336+240', 1116, (:'ji'::jsonb #>> '{totals,cost_real}')::numeric);
select tt.eq('T5 margin total 360+204+160', 724, (:'ji'::jsonb #>> '{totals,margin}')::numeric);
select tt.is('T5 cake: qty 3 (5 sold - 2 returned), revenue 900, cost 540, margin 360, 40.00 %', '3.0000|900.00|540.00|360.00|40.00|100.0', (select (r->>'qty')||'|'||(r->>'revenue')||'|'||(r->>'cost_real')||'|'||(r->>'margin')||'|'||(r->>'margin_pct')||'|'||(r->>'costed_pct') from jsonb_array_elements(:'ji'::jsonb->'rows') r where r->>'name_en'='Cake'));
select tt.is('T5 bun: qty 28 (10+5+10+4-1), revenue 180+100+200+80-20 = 540, cost 336, margin 204, 37.78 %', '28.0000|540.00|336.00|204.00|37.78', (select (r->>'qty')||'|'||(r->>'revenue')||'|'||(r->>'cost_real')||'|'||(r->>'margin')||'|'||(r->>'margin_pct') from jsonb_array_elements(:'ji'::jsonb->'rows') r where r->>'name_en'='Bun'));
select tt.is('T5 sweet: 4 kg 400 cost 240 (the voided S6 is not counted)', '4.0000|400.00|240.00|160.00', (select (r->>'qty')||'|'||(r->>'revenue')||'|'||(r->>'cost_real')||'|'||(r->>'margin') from jsonb_array_elements(:'ji'::jsonb->'rows') r where r->>'name_en'='Sweet'));
select rpt131_item_profit(tt.today()-3, tt.today(), null, 'category') as jc \gset
select tt.is('T5 category bakery 1440 / 876 / 564; sweets 400 / 240 / 160', '1440.00|876.00|564.00|400.00|240.00|160.00', (select (select (r->>'revenue')||'|'||(r->>'cost_real')||'|'||(r->>'margin') from jsonb_array_elements(:'jc'::jsonb->'rows') r where r->>'key'='bakery')||'|'||(select (r->>'revenue')||'|'||(r->>'cost_real')||'|'||(r->>'margin') from jsonb_array_elements(:'jc'::jsonb->'rows') r where r->>'key'='sweets')));
select rpt131_item_profit(tt.today()-3, tt.today(), null, 'outlet') as jt \gset
select tt.is('T5 outlet 1 revenue 1440, outlet 2 revenue 400 (= T3 net by outlet)', '1440.00|400.00', (select (select r->>'revenue' from jsonb_array_elements(:'jt'::jsonb->'rows') r where r->>'key'='1')||'|'||(select r->>'revenue' from jsonb_array_elements(:'jt'::jsonb->'rows') r where r->>'key'='2')));
select tt.eq('T5 item filter: cake only 900', 900, (rpt131_item_profit(tt.today()-3, tt.today(), null, 'item', null, tt.iid('R-CAKE')) #>> '{totals,revenue}')::numeric);
select tt.eq('T5 category filter: sweets only 400', 400, (rpt131_item_profit(tt.today()-3, tt.today(), null, 'item', 'sweets') #>> '{totals,revenue}')::numeric);
select tt.eq('T5 search bun', 1, (rpt131_item_profit(tt.today()-3, tt.today(), null, 'item', null, null, 'bun') ->> 'row_count')::numeric);
select tt.eq('T5 outlet filter {2}: sweet only 400', 400, (rpt131_item_profit(tt.today()-3, tt.today(), array[2], 'item') #>> '{totals,revenue}')::numeric);
select tt.is('T5 sort by margin ascending: sweet (160) first', 'Sweet', (rpt131_item_profit(tt.today()-3, tt.today(), null, 'item', null, null, null, 'margin:asc') -> 'rows' -> 0 ->> 'name_en'));
select tt.as(:'mg1');
select rpt131_item_profit(tt.today()-3, tt.today(), null, 'item') as jm \gset
select tt.t('T5 no cost right: revenue visible (outlet 1 = 1440), cost / margin null, a note says so', (:'jm'::jsonb #>> '{totals,revenue}')::numeric = 1440 and (:'jm'::jsonb #>> '{totals,cost_real}') is null and (:'jm'::jsonb #>> '{totals,margin}') is null
   and (select bool_and(r->'cost_real' = 'null'::jsonb and r->'margin' = 'null'::jsonb and r->'margin_pct' = 'null'::jsonb) from jsonb_array_elements(:'jm'::jsonb->'rows') r) and exists (select 1 from jsonb_array_elements(:'jm'::jsonb->'notes') n where n->>'code'='cost_hidden') and not (:'jm'::jsonb ->> 'cost_visible')::boolean);
select tt.as(:'cst');
select tt.eq('T5 view_cost user (outlet 1 only) sees the margin 360 + 204 = 564', 564, (rpt131_item_profit(tt.today()-3, tt.today(), null, 'item') #>> '{totals,margin}')::numeric);
select tt.as(:'o');

\echo == T6 stock reconciliation: opening + in - out + adjustments = closing, check 0, variance against the stored balance
select rpt131_stock_recon(tt.today()-4, tt.today()) as js \gset
select tt.eq('T6 six item-place lines', 6, (:'js'::jsonb ->> 'row_count')::numeric);
select tt.is('T6 cake outlet 1: open 0, in 2 (two returns), out 7 (6 sold net of the void + 1 wasted), adj 50 (opening stock), close 45, check 0, balance 45', '0.0000|2.0000|7.0000|50.0000|45.0000|0.0000|45.0000', (select (r->>'opening_qty')||'|'||(r->>'in_qty')||'|'||(r->>'out_qty')||'|'||(r->>'adjust_qty')||'|'||(r->>'closing_qty')||'|'||(r->>'check_qty')||'|'||(r->>'balance_qty') from jsonb_array_elements(:'js'::jsonb->'rows') r where r->>'item_code'='R-CAKE' and r->>'location_id'='1'));
select tt.is('T6 bun outlet 1: in 1 (return), out 38 (sold 40 - 6 voided + 4 wasted), adj 200, close 163', '1.0000|38.0000|200.0000|163.0000|0.0000', (select (r->>'in_qty')||'|'||(r->>'out_qty')||'|'||(r->>'adjust_qty')||'|'||(r->>'closing_qty')||'|'||(r->>'check_qty') from jsonb_array_elements(:'js'::jsonb->'rows') r where r->>'item_code'='R-BUN' and r->>'location_id'='1'));
select tt.is('T6 sweet outlet 2: out 6 (4 sold + 1 sold - 1 voided + 2 wasted), adj 30, close 24', '6.0000|30.0000|24.0000', (select (r->>'out_qty')||'|'||(r->>'adjust_qty')||'|'||(r->>'closing_qty') from jsonb_array_elements(:'js'::jsonb->'rows') r where r->>'item_code'='R-SWT' and r->>'location_id'='2'));
select tt.is('T6 sweet outlet 1: opening 40 then a count of 39 -> adjustments 39, close 39', '39.0000|39.0000', (select (r->>'adjust_qty')||'|'||(r->>'closing_qty') from jsonb_array_elements(:'js'::jsonb->'rows') r where r->>'item_code'='R-SWT' and r->>'location_id'='1'));
select tt.is('T6 flour 100 bought, sugar 50 bought', '100.0000|50.0000', (select (select r->>'in_qty' from jsonb_array_elements(:'js'::jsonb->'rows') r where r->>'item_code'='R-FLR')||'|'||(select r->>'in_qty' from jsonb_array_elements(:'js'::jsonb->'rows') r where r->>'item_code'='R-SUG')));
select tt.t('T6 every line balances (check 0) and none has a variance', (select bool_and((r->>'check_qty')::numeric = 0 and r->>'status' = 'ok') from jsonb_array_elements(:'js'::jsonb->'rows') r));
select tt.eq('T6 closing value 1956 + 8100 + 4000 + 3000 + 2340 + 1440', 20836, (:'js'::jsonb #>> '{totals,closing_value}')::numeric);
select tt.t('T6 quantities are not totalled across items (no qty totals)', not ((:'js'::jsonb -> 'totals') ? 'closing_qty') and not ((:'js'::jsonb -> 'totals') ? 'in_qty'));
select tt.eq('T6 the summary: 6 lines, 0 unbalanced, 0 with variance', 0, (:'js'::jsonb #>> '{summary,unbalanced}')::numeric + (:'js'::jsonb #>> '{summary,with_variance}')::numeric);
select rpt131_stock_recon(tt.today()-2, tt.today(), null, null, tt.iid('R-CAKE')) as jo2 \gset
select tt.is('T6 window from 2 days ago: cake opening -5 (3 + 2 sold before, the opening stock row is dated today), still balanced', '-5.0000|0.0000|45.0000', (select (r->>'opening_qty')||'|'||(r->>'check_qty')||'|'||(r->>'closing_qty') from jsonb_array_elements(:'jo2'::jsonb->'rows') r where r->>'location_id'='1'));
update stock_balance set qty = qty + 3 where item_id = tt.iid('R-FLR') and location_id = 1;
select rpt131_stock_recon(tt.today()-4, tt.today(), null, null, null, true) as jv \gset
select tt.is('T6 a stored balance that disagrees with the ledger shows as variance -3, status variance; issues-only lists only it', '1|variance|-3.0000', (select (:'jv'::jsonb->>'row_count')||'|'||(r->>'status')||'|'||(r->>'variance_qty') from jsonb_array_elements(:'jv'::jsonb->'rows') r));
update stock_balance set qty = qty - 3 where item_id = tt.iid('R-FLR') and location_id = 1;
select tt.eq('T6 search by item code r-swt: 2 lines', 2, (rpt131_stock_recon(tt.today()-4, tt.today(), null, null, null, false, 'r-swt') ->> 'row_count')::numeric);
select tt.eq('T6 outlet 2 only: one line', 1, (rpt131_stock_recon(tt.today()-4, tt.today(), array[2]) ->> 'row_count')::numeric);
select tt.eq('T6 category filter sweets: 2 lines', 2, (rpt131_stock_recon(tt.today()-4, tt.today(), null, 'sweets') ->> 'row_count')::numeric);
select tt.as(:'acv');
select tt.err('T6 without the stock-reconciliation right the report is refused (existing right reused)', $$select rpt131_stock_recon(current_date-4, current_date)$$, 'not allowed');
select tt.as(:'mg1');
select tt.t('T6 no cost right: no stock value', (rpt131_stock_recon(tt.today()-4, tt.today(), array[1]) #>> '{totals,closing_value}') is null);
select tt.as(:'o');

\echo == T7 wastage: posted vs pending / rejected / cancelled / reversed
select set_rule('wastage_approval_limit','10') is null as wl \gset
select tt.as(:'mg1');
select stock_wastage(tt.iid('R-BUN'),1,30,'spoiled',null,null,null,gen_random_uuid()) ->> 'request_id' as q1 \gset
select stock_wastage(tt.iid('R-BUN'),1,25,'spoiled',null,null,null,gen_random_uuid()) ->> 'request_id' as q2 \gset
select stock_wastage(tt.iid('R-SWT'),1,20,'expired',null,null,null,gen_random_uuid()) ->> 'request_id' as q3 \gset
select wastage_cancel(:'q2'::uuid) is not null as wc \gset
select tt.as(:'o');
select wastage_decide(:'q3'::uuid, false, 'not credible') is not null as wd \gset
select stock_post(tt.iid('R-SWT'), 2, 2, 'reversal', null, null, null, null, null, 'undo the wastage', :'w3'::bigint) is not null as wrv \gset
select rpt131_wastage(tt.today()-3, tt.today(), null, 'status') as jw \gset
select tt.eq('T7 five statuses', 5, (:'jw'::jsonb ->> 'row_count')::numeric);
select tt.is('T7 posted: 2 entries, value 48 + 180 = 228 (unit cost from the ledger)', '2|228.00', (select (r->>'entries')||'|'||(r->>'value') from jsonb_array_elements(:'jw'::jsonb->'rows') r where r->>'dim'='posted'));
select tt.is('T7 pending 1, cancelled 1, rejected 1, reversed 1 - none of them carries a value', '1|1|1|1|true', (select (select r->>'entries' from jsonb_array_elements(:'jw'::jsonb->'rows') r where r->>'dim'='pending')||'|'||(select r->>'entries' from jsonb_array_elements(:'jw'::jsonb->'rows') r where r->>'dim'='cancelled')
   ||'|'||(select r->>'entries' from jsonb_array_elements(:'jw'::jsonb->'rows') r where r->>'dim'='rejected')||'|'||(select r->>'entries' from jsonb_array_elements(:'jw'::jsonb->'rows') r where r->>'dim'='reversed')||'|'||(select bool_and(r->'value' = 'null'::jsonb) from jsonb_array_elements(:'jw'::jsonb->'rows') r where r->>'dim' <> 'posted')));
select tt.eq('T7 posted value total = 228', 228, (:'jw'::jsonb #>> '{totals,value}')::numeric);
select rpt131_wastage(tt.today()-3, tt.today(), null, 'reason') as jw2 \gset
select tt.is('T7 by reason: expired = posted 48 (the 2 kg sweet entry was reversed, the 20 kg request rejected); broken 180; spoiled none posted', '3|48.00|1|180.00|2', (select (select r->>'entries' from jsonb_array_elements(:'jw2'::jsonb->'rows') r where r->>'dim'='expired')||'|'||(select r->>'value' from jsonb_array_elements(:'jw2'::jsonb->'rows') r where r->>'dim'='expired')||'|'||(select r->>'entries' from jsonb_array_elements(:'jw2'::jsonb->'rows') r where r->>'dim'='broken')||'|'||(select r->>'value' from jsonb_array_elements(:'jw2'::jsonb->'rows') r where r->>'dim'='broken')||'|'||(select r->>'entries' from jsonb_array_elements(:'jw2'::jsonb->'rows') r where r->>'dim'='spoiled')));
select tt.t('T7 by reason: the label comes from the owner list; quantity is not totalled across items', (select r->>'label_en' from jsonb_array_elements(:'jw2'::jsonb->'rows') r where r->>'dim'='broken') = (select label_en from option_lists where list_code='wastage_reasons' and value_code='broken') and (select bool_and(r->'qty'='null'::jsonb) from jsonb_array_elements(:'jw2'::jsonb->'rows') r));
select tt.is('T7 status filter posted by item: bun 4 pcs 48, cake 1 kg 180', '4.0000|48.00|1.0000|180.00', (select (select r->>'qty' from jsonb_array_elements(j->'rows') r where r->>'label_en'='Bun')||'|'||(select r->>'value' from jsonb_array_elements(j->'rows') r where r->>'label_en'='Bun')||'|'||(select r->>'qty' from jsonb_array_elements(j->'rows') r where r->>'label_en'='Cake')||'|'||(select r->>'value' from jsonb_array_elements(j->'rows') r where r->>'label_en'='Cake') from (select rpt131_wastage(tt.today()-3, tt.today(), null, 'item', 'posted') j) z));
select tt.is('T7 by outlet (all statuses): outlet 1 has 5 entries, outlet 2 has 1 (reversed) ', '5|1', (select (select r->>'entries' from jsonb_array_elements(j->'rows') r where r->>'dim'='1')||'|'||(select r->>'entries' from jsonb_array_elements(j->'rows') r where r->>'dim'='2') from (select rpt131_wastage(tt.today()-3, tt.today(), null, 'outlet') j) z));
select tt.eq('T7 documents list (group doc), pending only', 1, (rpt131_wastage(tt.today()-3, tt.today(), null, 'doc', 'pending') ->> 'row_count')::numeric);
select tt.eq('T7 category filter sweets: 3 entries (posted-then-reversed, rejected... see below)', 2, (rpt131_wastage(tt.today()-3, tt.today(), null, 'doc', 'all', 'sweets') ->> 'row_count')::numeric);
select tt.eq('T7 item filter bun: 4 entries (4 posted, 30 pending, 25 cancelled = 3 docs)', 3, (rpt131_wastage(tt.today()-3, tt.today(), null, 'doc', 'all', null, tt.iid('R-BUN')) ->> 'row_count')::numeric);
select tt.is('T7 the books side: wastage is not journaled while the stock-to-books switch is off, so the gap is shown plainly', '228.00|0.00|228.00', (select (j#>>'{tie_out,posted_value}')||'|'||(j#>>'{tie_out,books_wastage_loss}')||'|'||(j#>>'{tie_out,gap}') from (select rpt131_wastage(tt.today()-3, tt.today(), null, 'reason') j) z));
select tt.as(:'mg1');
select tt.t('T7 no cost right: no value, no cost-unknown count', (select (j #>> '{totals,value}') is null and (select bool_and(r->'value'='null'::jsonb and r->'cost_unknown'='null'::jsonb) from jsonb_array_elements(j->'rows') r) from (select rpt131_wastage(tt.today()-3, tt.today(), null, 'reason') j) z));
select tt.as(:'o');
select tt.err('T7 bad status refused', $$select rpt131_wastage(current_date-3, current_date, null, 'reason', 'lost')$$, 'bad_status');
select tt.err('T7 bad group refused', $$select rpt131_wastage(current_date-3, current_date, null, 'colour')$$, 'bad_group');

\echo == T8 cash book and day close
select set_rule('wastage_approval_limit',null) is null as wl0 \gset
select rpt131_cash_close(tt.today()-3, tt.today()) as jc2 \gset
select tt.is('T8 outlet 1, 3 days ago: expected 900+100 = 1000, books 1000, gap 0; opening 5000 -> closing 6000; the sheet says 50 short', '1000.00|1000.00|0.00|5000.00|6000.00|-50.00|short', (select (r->>'expected_cash')||'|'||(r->>'books_sales_cash')||'|'||(r->>'unposted_gap')||'|'||(r->>'opening')||'|'||(r->>'closing')||'|'||(r->>'sheet_short_over')||'|'||(r->>'flag') from jsonb_array_elements(:'jc2'::jsonb->'rows') r where r->>'loc'='1' and r->>'d'=(tt.today()-3)::text));
select tt.is('T8 outlet 1, 2 days ago: register 100 (S5), books 220 (S7 voided but still in the books) -> gap -120', '100.00|220.00|-120.00|books_differ|6220.00', (select (r->>'expected_cash')||'|'||(r->>'books_sales_cash')||'|'||(r->>'unposted_gap')||'|'||(r->>'flag')||'|'||(r->>'closing') from jsonb_array_elements(:'jc2'::jsonb->'rows') r where r->>'loc'='1' and r->>'d'=(tt.today()-2)::text));
select tt.is('T8 outlet 1, today: S9 200 + collection 150 - refunds 300+20 = 30 expected; books -150 (collection in, R1 out); gap 180 = S9 200 - R3 20; cash out 1300 (refund 300 + supplier payment 1000)', '200.00|150.00|320.00|30.00|-150.00|180.00|150.00|1300.00|5070.00', (select (r->>'sales_cash')||'|'||(r->>'collections_cash')||'|'||(r->>'refunds_cash')||'|'||(r->>'expected_cash')||'|'||(r->>'books_sales_cash')||'|'||(r->>'unposted_gap')||'|'||(r->>'cash_in')||'|'||(r->>'cash_out')||'|'||(r->>'closing') from jsonb_array_elements(:'jc2'::jsonb->'rows') r where r->>'loc'='1' and r->>'d'=tt.today()::text));
select tt.is('T8 outlet 2: the S6 cash sale was posted 2 days ago and reversed today: -100 then +100, nets to 0', '-100.00|100.00', (select (select r->>'unposted_gap' from jsonb_array_elements(:'jc2'::jsonb->'rows') r where r->>'loc'='2' and r->>'d'=(tt.today()-2)::text)||'|'||(select r->>'unposted_gap' from jsonb_array_elements(:'jc2'::jsonb->'rows') r where r->>'loc'='2' and r->>'d'=tt.today()::text)));
select tt.is('T8 outlet 1 non-cash on the first day: mobile 180 (S2); outlet 2 card 400', '180.00|400.00', (select (select r->>'noncash_net' from jsonb_array_elements(:'jc2'::jsonb->'rows') r where r->>'loc'='1' and r->>'d'=(tt.today()-3)::text)||'|'||(select r->>'noncash_net' from jsonb_array_elements(:'jc2'::jsonb->'rows') r where r->>'loc'='2' and r->>'d'=(tt.today()-3)::text)));
select tt.is('T8 totals: summary opening 5000, net movement 70, closing 5070 (= the cash account of the books)', '5000.00|70.00|5070.00', (select (j#>>'{summary,opening_total}')||'|'||(j#>>'{summary,net_movement}')||'|'||(j#>>'{summary,closing_total}') from (select :'jc2'::jsonb j) z));
select tt.eq('T8 closing in the report = the trial balance cash in hand 1110', (select coalesce(sum(debit - credit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='1110'), (:'jc2'::jsonb #>> '{summary,closing_total}')::numeric);
select tt.eq('T8 not-yet-posted gap total 60 (0 - 120 + 180 + 0 - 100 + 100)', 60, (:'jc2'::jsonb #>> '{totals,unposted_gap}')::numeric);
select tt.eq('T8 expected cash total 1130', 1130, (:'jc2'::jsonb #>> '{totals,expected_cash}')::numeric);
select tt.is('T8 a day with cash sales and no sheet is flagged no_sheet, never 0 short', 'null', (select coalesce(r->'sheet_short_over','null'::jsonb)::text from jsonb_array_elements(:'jc2'::jsonb->'rows') r where r->>'loc'='1' and r->>'d'=tt.today()::text));
select tt.eq('T8 sheet short total -50', -50, (:'jc2'::jsonb #>> '{totals,sheet_short_over}')::numeric);
select tt.eq('T8 one outlet only {2}: 6 -> 3 rows', 3, (rpt131_cash_close(tt.today()-3, tt.today(), array[2]) ->> 'row_count')::numeric);
select tt.t('T8 without a sheet in the period: data-needed note, short/over total null', (select exists (select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='no_day_close_sheet') and (j #>> '{totals,sheet_short_over}') is null from (select rpt131_cash_close(tt.today()-2, tt.today()) j) z));
select tt.as(:'mg1');
select tt.t('T8 no accounts right: register columns only, books columns null, a note says so', (select (j #>> '{summary,opening_total}') is null and not (j->>'books_visible')::boolean and (select bool_and(r->'opening'='null'::jsonb and r->'closing'='null'::jsonb and r->'unposted_gap'='null'::jsonb) from jsonb_array_elements(j->'rows') r)
   and (j #>> '{totals,expected_cash}')::numeric = 1130 and exists (select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='books_hidden') from (select rpt131_cash_close(tt.today()-3, tt.today()) j) z));
select tt.as(:'o');

\echo == T9 ageing: receivable (buckets from the rule) and payable, tie-out to the books
select rpt131_ageing('receivable') as ja0 \gset
select tt.t('T9 buckets rule not set: totals only and a data-needed note', exists (select 1 from jsonb_array_elements(:'ja0'::jsonb->'notes') n where n->>'code'='data_needed') and not ((:'ja0'::jsonb -> 'totals') ? 'b1') and (:'ja0'::jsonb #>> '{totals,balance}')::numeric = 530);
select set_rule('report_aging_buckets','"7,30"') is null as bk \gset
select rpt131_ageing('receivable') as ja \gset
select tt.eq('T9 receivable total 530 = test_user_a 480 + test_user_b 50', 530, (:'ja'::jsonb #>> '{totals,balance}')::numeric);
select tt.is('T9 test_user_a: 480 over 2 bills, 80 within 7 days and 400 in 8-30 (oldest 9 days)', '480.00|80.00|400.00|0.00|2|9', (select (r->>'balance')||'|'||(r->>'b1')||'|'||(r->>'b2')||'|'||(r->>'b3')||'|'||(r->>'bills')||'|'||(r->>'oldest_days') from jsonb_array_elements(:'ja'::jsonb->'rows') r where r->>'name'='test_user_a'));
select tt.is('T9 test_user_b: 600 - 100 paid - 300 credit on the return - 150 collected = 50, 3 days old', '50.00|50.00|3', (select (r->>'balance')||'|'||(r->>'b1')||'|'||(r->>'oldest_days') from jsonb_array_elements(:'ja'::jsonb->'rows') r where r->>'name'='test_user_b'));
select tt.eq('T9 bucket totals add up to the balance (130 + 400 + 0)', 530, (:'ja'::jsonb #>> '{totals,b1}')::numeric + (:'ja'::jsonb #>> '{totals,b2}')::numeric + (:'ja'::jsonb #>> '{totals,b3}')::numeric);
select tt.is('T9 books tie-out: the books hold 450 (S11 80 is not posted); gap 80 explained by 1 unposted bill', '530.00|0.00|450.00|80.00|1|80.00|0.00', (select (j#>>'{tie_out,register_net}')||'|'||(j#>>'{tie_out,advances}')||'|'||(j#>>'{tie_out,books_receivable}')||'|'||(j#>>'{tie_out,gap}')||'|'||(j#>>'{tie_out,unposted_bills}')||'|'||(j#>>'{tie_out,unposted_value}')||'|'||(j#>>'{tie_out,unexplained}') from (select :'ja'::jsonb j) z));
select tt.t('T9 customer mobile numbers are not in the answer', position('0171100' in :'ja'::text) = 0);
select tt.eq('T9 search test_user_a: one row', 1, (rpt131_ageing('receivable', null, null, 'test_user_a') ->> 'row_count')::numeric);
select tt.eq('T9 as of 5 days ago: only test_user_a bill of 400 (9 days before today = 4 days old then); test_user_b not yet', 400, (rpt131_ageing('receivable', tt.today()-5) #>> '{totals,balance}')::numeric);
select rpt131_ageing('payable') as jb \gset
select tt.is('T9 payable: Sup Main 3000 (4000 - 1000 paid) 9 days old, overdue 3000 (credit days 7); Sup Two 3000, 2 days, overdue 0', '3000.00|3000.00|9|3000.00|3000.00|0.00', (select (select r->>'balance' from jsonb_array_elements(:'jb'::jsonb->'rows') r where r->>'name'='Sup Main')||'|'||(select r->>'overdue' from jsonb_array_elements(:'jb'::jsonb->'rows') r where r->>'name'='Sup Main')||'|'||(select r->>'oldest_days' from jsonb_array_elements(:'jb'::jsonb->'rows') r where r->>'name'='Sup Main')||'|'||(select r->>'balance' from jsonb_array_elements(:'jb'::jsonb->'rows') r where r->>'name'='Sup Two')||'|'||(select r->>'b1' from jsonb_array_elements(:'jb'::jsonb->'rows') r where r->>'name'='Sup Two')||'|'||(select r->>'overdue' from jsonb_array_elements(:'jb'::jsonb->'rows') r where r->>'name'='Sup Two')));
select tt.is('T9 payable total 6000 = supplier payables in the books 6000, gap 0', '6000.00|6000.00|0.00', (select (j#>>'{tie_out,register_open}')||'|'||(j#>>'{tie_out,books_payable}')||'|'||(j#>>'{tie_out,gap}') from (select :'jb'::jsonb j) z));
select tt.eq('T9 payable total agrees with the existing supplier_dues function', (select sum(balance) from supplier_dues()), (:'jb'::jsonb #>> '{totals,balance}')::numeric);
select tt.eq('T9 payable bucket 8-30 holds Sup Main 3000', 3000, (:'jb'::jsonb #>> '{totals,b2}')::numeric);
select tt.t('T9 a date for payables is ignored with a note (always today)', exists (select 1 from jsonb_array_elements(rpt131_ageing('payable', tt.today()-5) -> 'notes') n where n->>'code'='as_of_today'));
-- an advance: test_user_b pays 100 more than he owes (balance 50): his balance is 0, 50 is an advance
select tt.err('T9 the collection function itself refuses to take more than the balance', format($q$select collect_payment(gen_random_uuid(),1,%L::uuid,'[{"mode":"cash","amount":100}]'::jsonb,'over')$q$, (select customer_id from sales where id=:'s4'::uuid)), 'overpaid');
-- an advance can only exist from old / imported data: seeded directly for this test (a collection row beyond the balance, not posted to the books)
insert into sale_payments (sale_id, customer_id, location_id, kind, mode, amount, created_staff) values (null, (select customer_id from sales where id=:'s4'::uuid), 1, 'collection', 'cash', 100, 'seed');
select rpt131_ageing('receivable') as ja2 \gset
select tt.is('T9 over-payment: test_user_b leaves the list, 50 shown as advance, register net 480 - 50 = 430', '1|50.00|430.00', (select (:'ja2'::jsonb->>'row_count')||'|'||(:'ja2'::jsonb#>>'{tie_out,advances}')||'|'||(:'ja2'::jsonb#>>'{tie_out,register_net}')));
select tt.is('T9 the new collection is not posted yet: books still 450 -> gap -20 = unposted bill 80 - unposted collection 100, nothing unexplained', '-20.00|1|100.00|-20.00|0.00', (select (j#>>'{tie_out,gap}')||'|'||(j#>>'{tie_out,unposted_collections}')||'|'||(j#>>'{tie_out,unposted_collections_value}')||'|'||(j#>>'{tie_out,explained}')||'|'||(j#>>'{tie_out,unexplained}') from (select :'ja2'::jsonb j) z));
select tt.as(:'mg1');
select tt.t('T9 no accounts right: no tie-out, the register numbers still show', (select (j->'tie_out') = 'null'::jsonb and not (j->>'books_visible')::boolean and (j #>> '{totals,balance}')::numeric = 480 from (select rpt131_ageing('receivable') j) z));
select tt.as(:'o');
select tt.err('T9 bad kind refused', $$select rpt131_ageing('stock')$$, 'bad_kind');
select tt.err('T9 a future date refused', $$select rpt131_ageing('receivable', current_date + 3)$$, 'bad_range');

\echo == T10 scope: a user sees only the places he may use; refused when he names another
select tt.as(:'mg2');
select tt.eq('T10 outlet-2 manager: sales net 400 only', 400, (rpt131_sales(tt.today()-3, tt.today(), null, 'day') #>> '{totals,net_sales}')::numeric);
select tt.eq('T10 outlet-2 manager: documents are only outlet-2 documents (S3 and the voided S6)', 2, (rpt131_sales_recon(tt.today()-3, tt.today()) ->> 'row_count')::numeric);
select tt.eq('T10 outlet-2 manager: stock lines only outlet 2', 1, (rpt131_stock_recon(tt.today()-4, tt.today()) ->> 'row_count')::numeric);
select tt.eq('T10 outlet-2 manager: customers of outlet 1 are not in the ageing', 0, (rpt131_ageing('receivable') ->> 'row_count')::numeric);
select tt.err('T10 naming outlet 1 is refused (sales)', $$select rpt131_sales(current_date-3, current_date, array[1], 'day')$$, 'not allowed for this location');
select tt.err('T10 naming outlet 1 is refused (cash)', $$select rpt131_cash_close(current_date-3, current_date, array[1])$$, 'not allowed for this location');
select tt.err('T10 naming outlet 1 is refused (wastage)', $$select rpt131_wastage(current_date-3, current_date, array[1])$$, 'not allowed for this location');
select tt.as(:'mg1');
select tt.eq('T10 outlet-1 manager: sales net 1440 only (1840 - 400)', 1440, (rpt131_sales(tt.today()-3, tt.today(), null, 'day') #>> '{totals,net_sales}')::numeric);
select tt.err('T10 outlet-1 manager naming outlet 2 is refused', $$select rpt131_sales(current_date-3, current_date, array[2], 'day')$$, 'not allowed for this location');
select tt.err('T10 outlet-1 manager naming outlet 2 is refused (profit)', $$select rpt131_item_profit(current_date-3, current_date, array[2])$$, 'not allowed for this location');
select tt.as(:'o');
select tt.eq('T10 owner: both outlets 1840 = 1440 + 400', 1840, (rpt131_sales(tt.today()-3, tt.today(), null, 'day') #>> '{totals,net_sales}')::numeric);
select tt.as(:'nol');
select tt.t('T10 a user with no place: empty answer, no figures, a note (not zeros)', (select (j->>'data_needed')::boolean and j->'totals' = 'null'::jsonb and exists (select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='no_location') from (select rpt131_sales(tt.today()-3, tt.today()) j) z));
select tt.as(:'acv');
select tt.t('T10 accounts-view user (outlet 1) sees the books side (1300) but not the cost', (select (j->>'books_visible')::boolean and (j #>> '{tie_out,journal_by_entry_date}')::numeric = 1300 from (select rpt131_sales_recon(tt.today()-3, tt.today()) j) z) and (rpt131_item_profit(tt.today()-3, tt.today()) #>> '{totals,cost_real}') is null);
select tt.as(:'mg1');
select rpt131_sales_recon(tt.today()-3, tt.today()) as jh \gset
select tt.t('T10 no accounts right: the document list shows register status only (done / void), no books amounts, no tie-out', (not (:'jh'::jsonb->>'books_visible')::boolean) and (:'jh'::jsonb #>> '{summary,docs_books_net_total}') is null and (:'jh'::jsonb -> 'tie_out' ->> 'journal_by_entry_date') is null
   and (select bool_and(r->>'status' in ('done','void') and r->'books_net'='null'::jsonb) from jsonb_array_elements(:'jh'::jsonb->'rows') r) and (:'jh'::jsonb #>> '{totals,register_net}')::numeric = 1440);
select tt.as(:'o');

\echo == T11 empty data: nothing in the period -> data needed, totals null, no row of zeros
select tt.t('T11 every report on an empty period: data_needed true, rows empty, totals null', (select bool_and((j->>'data_needed')::boolean and jsonb_array_length(j->'rows')=0 and j->'totals'='null'::jsonb) from (
   select rpt131_sales(tt.today()-60, tt.today()-50) j union all select rpt131_sales(tt.today()-60, tt.today()-50, null, 'pay_mode') union all select rpt131_sales_recon(tt.today()-60, tt.today()-50) union all select rpt131_item_profit(tt.today()-60, tt.today()-50)
   union all select rpt131_wastage(tt.today()-60, tt.today()-50) union all select rpt131_cash_close(tt.today()-60, tt.today()-50) union all select rpt131_stock_recon(tt.today()-60, tt.today()-50, null, null, tt.iid('R-NOC'))) z));

\echo == T11b unknown cost is shown as unknown, never as free (an item with no cost in the ledger)
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":50}]',tt.iid('R-NOC'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)->>'id' as s12 \gset
select stock_wastage(tt.iid('R-NOC'),1,1,'broken',null,null,null,gen_random_uuid()) ->> 'ledger_id' as w9 \gset
select rpt131_item_profit(tt.today()-3, tt.today(), null, 'item', null, tt.iid('R-NOC')) as jn2 \gset
select tt.is('T11b no-cost item: revenue 100, all of it uncosted, costed 0 %, no margin and no cost figure (null, not 0)', '100.00|100.00|0.0|null|null|null', (select (r->>'revenue')||'|'||(r->>'uncosted_rev')||'|'||(r->>'costed_pct')||'|'||coalesce((r->'margin')::text,'x')||'|'||coalesce((r->'cost_real')::text,'x')||'|'||coalesce((r->'margin_pct')::text,'x') from jsonb_array_elements(:'jn2'::jsonb->'rows') r));
select rpt131_wastage(tt.today()-1, tt.today(), null, 'item', 'posted', null, tt.iid('R-NOC')) as jw3 \gset
select tt.is('T11b wastage of an item with no cost: 1 entry, value null, cost unknown 1', '1|null|1', (select (r->>'entries')||'|'||(r->'value')::text||'|'||(r->>'cost_unknown') from jsonb_array_elements(:'jw3'::jsonb->'rows') r));
select tt.t('T11b the wastage total value is null (data needed), not 0', (:'jw3'::jsonb #>> '{totals,value}') is null);

\echo == T11c the business wall: with org_scope_on ON the same users see the same figures
select set_rule('org_scope_on','true') is null as ws1 \gset
select tt.as(:'mg1');
select tt.eq('T11c ON: outlet-1 manager net 1440 + the 100 no-cost sale of T11b', 1540, (rpt131_sales(tt.today()-3, tt.today(), null, 'day') #>> '{totals,net_sales}')::numeric);
select tt.err('T11c ON: outlet-1 manager naming outlet 2 refused', $$select rpt131_sales(current_date-3, current_date, array[2], 'day')$$, 'not allowed for this location');
select tt.as(:'mg2');
select tt.eq('T11c ON: outlet-2 manager net 400', 400, (rpt131_sales(tt.today()-3, tt.today(), null, 'day') #>> '{totals,net_sales}')::numeric);
select tt.as(:'o');
select tt.eq('T11c ON: owner net 1840 + 100', 1940, (rpt131_sales(tt.today()-3, tt.today(), null, 'day') #>> '{totals,net_sales}')::numeric);
select set_rule('org_scope_on','false') is null as ws0 \gset

\echo == T12 CSV / print export log, the order of rights, ACL, paste twice, switch back OFF
select rpt131_log_export('rpt131_sales','csv','{"from":"x"}'::jsonb, 3) is null as lg \gset
select tt.eq('T12 export logged in the audit log', 1, (select count(*) from audit_log where action='export' and record_id='rpt131_sales' and (detail->>'rows')::int = 3));
select tt.err('T12 unknown report key refused', $$select rpt131_log_export('sales_summary','csv','{}'::jsonb, 1)$$, 'unknown_report');
select tt.as(:'mg1');
select tt.err('T12 a user without the export right is refused', $$select rpt131_log_export('rpt131_sales','csv','{}'::jsonb, 1)$$, 'not allowed');
select tt.as(:'o');
select tt.t('T12 anon cannot run any report', (select not bool_or(has_function_privilege('anon', p.oid, 'execute')) from pg_proc p where p.proname like 'rpt131\_%' escape '\'  and p.pronamespace='public'::regnamespace));
select tt.t('T12 helpers (_rpt131_*) are not callable by the browser role', (select not bool_or(has_function_privilege('authenticated', p.oid, 'execute')) from pg_proc p where p.proname like '\_rpt131\_%' escape '\' and p.pronamespace='public'::regnamespace));
select tt.t('T12 nine browser functions exist for authenticated', (select count(*)=9 and bool_and(has_function_privilege('authenticated', p.oid, 'execute')) from pg_proc p where p.proname like 'rpt131\_%' escape '\' and p.proname not like '\_%' and p.pronamespace='public'::regnamespace));
select tt.t('T12 no new table (the reports read only)', not exists (select 1 from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relname like '%rpt131%'));
create temp table k1 as select (select md5(string_agg(proname || pg_get_functiondef(oid), ',' order by proname)) from pg_proc where pronamespace='public'::regnamespace and proname not like '%rpt131%') f_old, (select count(*) from pg_proc where proname like '%rpt131%') n_new;
\i supabase/phase527.sql
select tt.t('T12 paste twice: no error, same functions, no older function touched', (select n_new = (select count(*) from pg_proc where proname like '%rpt131%') and f_old = (select md5(string_agg(proname || pg_get_functiondef(oid), ',' order by proname)) from pg_proc where pronamespace='public'::regnamespace and proname not like '%rpt131%') from k1));
select tt.eq('T12 the rule exists once', 1, (select count(*) from rules where key='rpt131_on'));
select set_rule('rpt131_on','false') is null as off2 \gset
select tt.t('T12 switch back OFF: the reports answer off again, the data is untouched', (rpt131_sales(tt.today()-3, tt.today()) ->> 'off')::boolean and (select count(*) from sales) = 12);

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.ea;
