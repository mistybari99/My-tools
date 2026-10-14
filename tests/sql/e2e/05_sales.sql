\echo == 05 POS sales
select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":3,"price":300}]',tt.iid('FG-CAKE'))::jsonb,0,'[{"mode":"cash","amount":900}]',null,null,'retail',null,false) as sa \gset
select tt.eq('X1 cash sale total', 900, (:'sa'::jsonb->>'total')::numeric);
select (:'sa'::jsonb->>'id')::uuid as sale_a \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":300}]',tt.iid('FG-CAKE'))::jsonb,0,'[{"mode":"card","amount":600}]',null,null,'retail',null,false) as sb \gset
select (:'sb'::jsonb->>'id')::uuid as sale_b \gset
select tt.eq('X1 card sale total', 600, (:'sb'::jsonb->>'total')::numeric);
select tt.eq('X1 cake stock 30-5', 25, tt.qty('FG-CAKE'));

\echo -- two-unit item (kg base, sold in pc, 1 kg = 20 pc)
select tt.as(:'o');
select tt.eq('X2 UI conversion helper: 5 pc of sweet = 0.25 kg', 0.25, _base_qty(tt.iid('FG-SW'),5,'pc'));
select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":0.25,"price":400}]',tt.iid('FG-SW'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false) as sc \gset
select (:'sc'::jsonb->>'id')::uuid as sale_c \gset
select tt.eq('X2 sweet total 0.25 kg x 400 (= 5 pc x 20)', 100, (:'sc'::jsonb->>'total')::numeric);
select tt.eq('X2 sweet stock 10 kg - 5 pc (0.25 kg) = 9.75', 9.75, tt.qty('FG-SW'));

\echo -- sale packaging + return restore
select tt.as(:'o');
select packaging_set(tt.iid('FG-SNK'), tt.iid('PK-SN'), 1, 'sale') is not null as pk \gset
select set_rule('packaging_consume_on','"sale"') is null as pco \gset
select rule_txt('packaging_return_mode') as prm0 \gset
\echo PACKAGING_RETURN_MODE_AT_START=:prm0
select set_rule('packaging_return_mode','"restore"') is null as prm \gset
select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":3,"price":25}]',tt.iid('FG-SNK'))::jsonb,0,'[{"mode":"cash","amount":75}]',null,null,'retail',null,false)->>'id' as sd_ \gset
select :'sd_'::uuid as sale_d \gset
select tt.eq('X3 snack 50-3', 47, tt.qty('FG-SNK'));
select tt.eq('X3 snack box 100-3', 97, tt.qty('PK-SN'));
select tt.as(:'o');
select sale_return(gen_random_uuid(), :'sale_d'::uuid, format('[{"item_id":"%s","qty":1}]',tt.iid('FG-SNK'))::jsonb, 'damaged','e2e snack return','cash') as ret_d \gset
select tt.eq('X3 snack after return 47+1', 48, tt.qty('FG-SNK'));
select tt.eq('X3 snack box restored 97+1', 98, tt.qty('PK-SN'));
select sale_return(gen_random_uuid(), :'sale_a'::uuid, format('[{"item_id":"%s","qty":1}]',tt.iid('FG-CAKE'))::jsonb, 'damaged','e2e cake return','cash') as ret_a \gset
select tt.eq('X3 cake after return 25+1', 26, tt.qty('FG-CAKE'));

\echo -- offline replay that goes negative
select set_rule('stock_negative_mode','"block"') is null as snm \gset
select jsonb_build_object('c', gen_random_uuid()) ->> 'c' as ocid \gset
select format('[{"item_id":"%s","qty":60,"price":25}]', tt.iid('FG-SNK'))::jsonb as ol \gset
select tt.as(:'sp');
select tt.err('X4 online sale of 60 snack (stock 48) refused in block mode', format($$select record_sale2('%s'::uuid,1,'%s'::jsonb,0,'[{"mode":"cash","amount":1500}]',null,null,'retail',null,false)$$, :'ocid', :'ol'), 'insufficient_stock');
select rule_on('offline_soft_stock') as oss0 \gset
\echo OFFLINE_SOFT_STOCK_AT_START=:oss0
\if :oss0
\else
select tt.err('X4 offline replay with offline_soft_stock OFF (default) refused', format($$select record_sale_offline('%s'::uuid,1,'%s'::jsonb,0,'[{"mode":"cash","amount":1500}]',null,null,'retail',null,false,now())$$, :'ocid', :'ol'), 'insufficient_stock');
select tt.as(:'o');
select set_rule('offline_soft_stock','true') is null as oss1 \gset
select tt.as(:'sp');
\endif
select record_sale_offline(:'ocid'::uuid,1,:'ol'::jsonb,0,'[{"mode":"cash","amount":1500}]',null,null,'retail',null,false,now()) as so \gset
select tt.eq('X4 offline replay accepted, total 1500', 1500, (:'so'::jsonb->>'total')::numeric);
select tt.eq('X4 snack stock 48-60 = -12', -12, tt.qty('FG-SNK'));
select tt.eq('X4 snack box 98-60', 38, tt.qty('PK-SN'));
select tt.eq('X4 yellow flag offline_soft_stock count', 1, (select count(*) from exceptions where flag_code='offline_soft_stock'));
select record_sale_offline(:'ocid'::uuid,1,:'ol'::jsonb,0,'[{"mode":"cash","amount":1500}]',null,null,'retail',null,false,now()) ->> 'dup' as odup \gset
select tt.is('X4 replay same client id = dup, one sale', 'true', :'odup');
select tt.eq('X4 sales rows with that client id', 1, (select count(*) from sales where client_id=:'ocid'::uuid));
select tt.as(:'o');
select set_rule('stock_negative_mode','"warn"') is null as snm2 \gset

\echo -- milk with expired batch (expiry guard)
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'B-MILK',tt.today()-1,format('[{"item_id":"%s","qty":20,"unit":"kg","unit_cost":30}]',tt.iid('FG-MILK'))::jsonb)->>'id' as bm \gset
select post_purchase(:'bm'::uuid) is not null as pbm \gset
insert into stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, batch_no) values (tt.iid('FG-MILK'),1,now()-interval '10 days',20,20,now()-interval '1 day','MILK-OLD') returning id as mb \gset
select tt.eq('X5 milk stock 20', 20, tt.qty('FG-MILK'));
select rule_txt('expiry_sale_guard') as esg0 \gset
\echo EXPIRY_GUARD_AT_START=:esg0
select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',tt.iid('FG-MILK'))::jsonb,0,'[{"mode":"cash","amount":200}]',null,null,'retail',null,false)->>'id' as sm \gset
select tt.t('X5 expired milk sold under guard=' || :'esg0' || ' (off/warn pass)', :'sm' is not null);
select tt.eq('X5 red sold_expired flag raised', 1, (select count(*) from exceptions where flag_code='sold_expired' and level='red'));
select tt.is('X5 flag text names the batch only when guard is warn/refuse', case when :'esg0'='off' then 'false' else 'true' end, (select (text->>'en' like '%batch%')::text from exceptions where flag_code='sold_expired' limit 1));
select tt.as(:'o');
select set_rule('expiry_sale_guard','"refuse"') is null as esg1 \gset
select tt.as(:'sp');
select tt.err('X5 refuse: expired milk refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":100}]'::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)$$, tt.iid('FG-MILK')), 'expired_stock_blocked');
select tt.eq('X5 milk stock 18', 18, tt.qty('FG-MILK'));
select tt.as(:'o');
