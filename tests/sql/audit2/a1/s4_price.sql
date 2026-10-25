\echo == S4 (d) price change mid-month, today-price view, landed cost freight, raw-material return; (e) partner material
-- state: oil 70 kg @40 (after S3). HAND: buy 50@52 -> (2800+2600)/120 = 45.000
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'OIL2',tt.today()-2,format('[{"item_id":"%s","qty":50,"unit":"kg","unit_cost":52}]',tt.iid('RM-O'))::jsonb)->>'id' as bo2 \gset
select post_purchase(:'bo2'::uuid) is not null as pbo2 \gset
select tt.eq('D1 oil qty 120', 120, tt.qty('RM-O'));
select tt.eq('D1 oil weighted avg after price change', 45, tt.avg('RM-O'), 0.0001);
-- HAND: run 1 batch (10 kg oil @45 = 450, pouch 10 x 1 = 10) = 460 -> unit 46.0 (actual yield = planned)
select production_post(1, (select id from recipes where item_id=tt.iid('FG-OIL')), 1, gen_random_uuid(), null, 'oil batch after price change', null) as ppo2 \gset
select tt.eq('D2 oil FG batch cost uses weighted avg 45: unit', 46, (select unit_cost from production_runs where id=(:'ppo2'::jsonb->>'run_id')::uuid), 0.0005);
-- HAND today view: oil last purchase 52 x10 = 520 + pouch last purchase 1 x 10 = 10 -> 530 / 10 = 53.0 ; gap vs book (460) = 15.22 %
select recipe_cost((select id from recipes where item_id=tt.iid('FG-OIL')),1) as rco \gset
select tt.eq('D3 recipe_cost book unit cost (avg)', 46, (:'rco'::jsonb->>'unit_cost')::numeric, 0.0005);
select tt.eq('D3 today-price unit cost (last purchase)', 53, (:'rco'::jsonb->'today'->>'unit_cost')::numeric, 0.0005);
select tt.eq('D3 gap pct', 15.22, (:'rco'::jsonb->'today'->>'gap_pct')::numeric, 0.01);
-- landed cost freight 600 on bill OIL2 (by value). HAND: stock on hand after run = 110 kg @45 = 4950 ; +600 -> 5550 / 110 = 50.4545
select set_rule('landed_cost_mode','"manual"') is null as lm \gset
with s as (insert into suppliers (name, credit_days) values ('Transporter', null) returning id) select id as s2 from s \gset
select (landed_save(gen_random_uuid(), null, '{"title":"Freight oil","alloc_method":"value"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'bo2')::jsonb,
  format('[{"charge_type":"freight","amount":600,"alloc_method":"value","pay_mode":"payable","supplier_id":"%s"}]',:'s2')::jsonb)->>'id')::uuid as lc \gset
select landed_post(:'lc'::uuid, gen_random_uuid()) as lpo \gset
\echo LANDED_POST: :lpo
select tt.eq('D4 oil avg after freight', 50.4545, tt.avg('RM-O'), 0.0005);
select tt.eq('D4 today-price view still the invoice price 52 (freight not in it; landed price would be 52 + 600/50 = 64)', 64, _today_cost(tt.iid('RM-O'),1), 0.0005);
select tt.eq('D4 earlier run (D2) not re-priced: still 46', 46, (select unit_cost from production_runs where id=(:'ppo2'::jsonb->>'run_id')::uuid), 0.0005);
-- raw material return to supplier of 5 kg at invoice 52. HAND: out at avg 50.4545 (252.27); supplier credit 260; variance 7.73; avg unchanged; qty 105
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'OIL2-R',tt.today(),format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":52}]',tt.iid('RM-O'))::jsonb,0,null,null,'return',:'bo2'::uuid,'damaged')->>'id' as br \gset
select post_purchase(:'br'::uuid) as prt \gset
\echo RETURN_POST: :prt
select tt.eq('D5 oil qty after return', 105, tt.qty('RM-O'));
select tt.eq('D5 oil avg unchanged by the return', 50.4545, tt.avg('RM-O'), 0.0005);
select tt.eq('D5 purchase variance recorded on the return bill', 7.73, (select variance from purchase_bills where id=:'br'::uuid), 0.01);
-- next run uses the new avg: HAND oil 10 x 50.4545 = 504.545 + pouch 10 = 514.545 -> 51.4545
select production_post(1, (select id from recipes where item_id=tt.iid('FG-OIL')), 1, gen_random_uuid(), null, 'oil batch after freight', null) as ppo3 \gset
select tt.eq('D6 next oil run unit cost', 51.4545, (select unit_cost from production_runs where id=(:'ppo3'::jsonb->>'run_id')::uuid), 0.0005);
-- (e) partner-supplied material
select tt.t('E1 stock has an owner / consignment column', exists (select 1 from information_schema.columns where table_schema='public' and table_name in ('stock_balance','stock_ledger','production_runs','recipe_lines') and column_name ~ 'owner|consign|party|partner|supplied'), 'not supported', (select coalesce(string_agg(table_name||'.'||column_name,','),'none') from information_schema.columns where table_schema='public' and table_name in ('stock_balance','stock_ledger','production_runs','recipe_lines') and column_name ~ 'owner|consign|party|partner|supplied'));
select tt.t('E1 partner_capital kind in_kind exists (contribution in goods)?', exists (select 1 from pg_constraint where conrelid='partner_capital'::regclass and pg_get_constraintdef(oid) ~ 'in_kind'), 'in_kind mode known', (select string_agg(pg_get_constraintdef(oid),' | ') from pg_constraint where conrelid='partner_capital'::regclass and contype='c'));
