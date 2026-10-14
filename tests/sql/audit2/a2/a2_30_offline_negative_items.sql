\echo == A2 30 offline replay, negative-stock modes, item rename / merge / category
select tt.as(:'o');
\echo -- (i) offline replay and duplicates
select gen_random_uuid() as oc1 \gset
select tt.as(:'sp');
select record_sale_offline(:'oc1'::uuid,1,format('[{"item_id":"%s","qty":2,"price":100}]',tt.iid('N-OFF'))::jsonb,0,'[{"mode":"cash","amount":200}]',null,null,'retail',null,false,now()-interval '3 hours') as o1 \gset
select tt.eq('i1 offline sale 2 kg (3 h old) takes stock: 5 - 2', 3, tt.qty('N-OFF',1));
select tt.is('i1 sold_at kept as the phone time (3 h ago)', 'true', (select (sold_at < now() - interval '2 hours 50 minutes')::text from sales where id=(:'o1'::jsonb->>'id')::uuid));
select record_sale_offline(:'oc1'::uuid,1,format('[{"item_id":"%s","qty":2,"price":100}]',tt.iid('N-OFF'))::jsonb,0,'[{"mode":"cash","amount":200}]',null,null,'retail',null,false,now()-interval '3 hours') ->> 'dup' as o1d \gset
select tt.is('i2 replay of the same client id = dup', 'true', :'o1d');
select tt.eq('i2 stock not taken twice', 3, tt.qty('N-OFF',1));
select tt.eq('i2 one sale row for the client id', 1, (select count(*) from sales where client_id=:'oc1'::uuid));
select tt.as(:'rv');
select tt.err('i3 another user replays the same client id', format($$select record_sale_offline('%s'::uuid,2,'[{"item_id":"%s","qty":2,"price":100}]'::jsonb,0,'[{"mode":"cash","amount":200}]',null,null,'retail',null,false,now()-interval '3 hours')$$, :'oc1', tt.iid('N-OFF')), 'client_id_taken');
select tt.as(:'o');
select set_rule('stock_negative_mode','"block"') is null as blk \gset
select tt.as(:'sp');
\echo -- (i4) block mode: an ONLINE sale above stock is refused, but the same call with a p_sold_at a few minutes old?
select tt.err('i4a block mode, sold_at = now (default): refused', $$select tt.sale(1,'N-OFF',10)$$, 'insufficient_stock');
select tt.sale(1,'N-OFF',10, gen_random_uuid(), now() - interval '5 minutes') ->> 'id' as bypass \gset
select tt.t('i4b block mode, plain record_sale2 with p_sold_at = now-5min and stock 3 < 10: must be refused like i4a', :'bypass' is null, 'refused', 'ACCEPTED, N-OFF stock now '||(select b.qty::text from stock_balance b where b.item_id=tt.iid('N-OFF') and b.location_id=1));
select tt.eq('i4b N-OFF balance (3 - 10 = -7 means the block was bypassed)', 3, tt.qty('N-OFF',1));
select tt.t('i4b the bypass is at least flagged yellow stock_negative', tt.exc('stock_negative') >= 1, '>=1', tt.exc('stock_negative')::text);
\echo -- (i5) a sale older than pos_offline_hours (72) is re-dated to now
select tt.sale(1,'A-KG',0.1, gen_random_uuid(), now() - interval '100 hours') ->> 'id' as old_sale \gset
select tt.t('i5 100-hour-old offline sale keeps its real date', (select sold_at < now() - interval '90 hours' from sales where id=:'old_sale'::uuid), 'sold_at about 100 h ago', 'sold_at = '||(select sold_at::text from sales where id=:'old_sale'::uuid)||' (re-dated to now)');
\echo -- (j) negative-stock behaviour per stock_negative_mode (item N-NEG holds 5 at loc1, sale of 8)
select tt.as(:'o');
select set_rule('stock_negative_mode','"allow"') is null as m1 \gset
select tt.exc('stock_negative') as exc0 \gset
select tt.as(:'sp');
select tt.sale(1,'N-NEG',8) is not null as j1 \gset
select tt.eq('j1 allow: balance 5 - 8', -3, tt.qty('N-NEG',1));
select tt.eq('j1 allow: no exception row at all', :'exc0'::numeric, tt.exc('stock_negative'));
select tt.as(:'o');
select stock_count_adjust(tt.iid('N-NEG'),1,5,'reset') is not null as rs1 \gset
select set_rule('stock_negative_mode','"warn"') is null as m2 \gset
select tt.exc('stock_negative') as exc1 \gset
select tt.as(:'sp');
select tt.sale(1,'N-NEG',8) is not null as j2 \gset
select tt.eq('j2 warn: sale accepted, balance 5 - 8', -3, tt.qty('N-NEG',1));
select tt.eq('j2 warn: ONE yellow stock_negative exception', :'exc1'::numeric + 1, tt.exc('stock_negative'));
select tt.sale(1,'N-NEG',2) is not null as j2b \gset
select tt.eq('j2 warn: a second, deeper negative sale the same day raises no new flag (dedup by text/day)', :'exc1'::numeric + 1, tt.exc('stock_negative'));
select tt.eq('j2 warn: balance -5', -5, tt.qty('N-NEG',1));
select tt.as(:'o');
select stock_count_adjust(tt.iid('N-NEG'),1,5,'reset') is not null as rs2 \gset
select set_rule('stock_negative_mode','"block"') is null as m3 \gset
select count(*) as nsales0 from sales \gset
select tt.as(:'sp');
select tt.err('j3 block: refused', $$select tt.sale(1,'N-NEG',8)$$, 'insufficient_stock');
select tt.eq('j3 block: no sale row left behind (whole sale rolled back)', :'nsales0'::numeric, (select count(*) from sales));
select tt.eq('j3 block: balance unchanged', 5, tt.qty('N-NEG',1));
select tt.sale(1,'N-NEG',5) is not null as j3b \gset
select tt.eq('j3 block: selling exactly the stock is fine -> 0', 0, tt.qty('N-NEG',1));
select tt.as(:'o');
select set_user_grant(:'sp'::uuid,'sell_below_zero') is null as gr \gset
select tt.as(:'sp');
select tt.sale(1,'N-NEG',2) is not null as j4 \gset
select tt.eq('j4 block + sell_below_zero grant: accepted, balance -2', -2, tt.qty('N-NEG',1));
select tt.eq('j4 grant use logged as sell_below_zero_used? (rule neg_grant_log default OFF -> 0 rows)', 0, tt.exc('sell_below_zero_used'));
select tt.as(:'o');
select tt.err('j5 invalid mode text is refused by set_rule', $$select set_rule('stock_negative_mode','"blok"')$$, '');
select set_rule('stock_negative_mode','"warn"') is null as m4 \gset
select tt.as(:'o');
select tt.as(:'fm');
select tt.err('j6 (maker) production needing more ingredient than held (production_short_mode default refuse)', format($$select production_post(1,'%s'::uuid,40,gen_random_uuid())$$, (select id from recipes where item_id=tt.iid('F-CAKE') limit 1)), 'insufficient_stock');

select tt.as(:'o');
select stock_production_in(tt.iid('N-NEG'),1,10,now(),null,'refill after negative') is not null as j7 \gset
select tt.eq('j7 production-in 10 into a balance of -2: balance 8', 8, tt.qty('N-NEG',1));
select tt.t('j7 batch remaining (10) = balance (8) after refilling a negative balance', tt.bsum('N-NEG',1) = tt.qty('N-NEG',1), 'equal', 'batches '||tt.bsum('N-NEG',1)||' vs balance '||tt.qty('N-NEG',1));

\echo -- (k) rename / category / deactivate / untrack / merge
select tt.as(:'o');
update items set name_bn='Renamed item', name_en='Renamed' where code='M-1';
select tt.eq('k1 rename keeps the balance (stock is keyed by item id)', 10, tt.qty('M-1',1));
select tt.sale(1,'M-1',1) is not null as k1s \gset
select tt.eq('k1 sale after rename reduces the same row', 9, tt.qty('M-1',1));
select item_set_category(tt.iid('M-1'), 2, null) is not null as k2 \gset
select tt.sale(1,'M-1',1) is not null as k2s \gset
select tt.eq('k2 category change: stock row follows the item', 8, tt.qty('M-1',1));
select tt.eq('k2 stock_levels category filter picks the new category', 1, (select count(*) from stock_levels(1, jsonb_build_object('category', (select category from items where code='M-1'))) where code='M-1'));
select tt.err('k3 item code cannot be edited', $$update items set code='M-9' where code='M-1'$$, '');
-- deactivate while stock exists
update items set is_active=false where code='M-1';
select tt.eq('k4 deactivated item with 8 on hand still listed in stock_levels (rows)', 1, (select count(*) from stock_levels(1, '{"include_zero":true}') where code='M-1'));
select tt.eq('k4 ... but stock_valuation still counts it (8 x 100)', 800, (select coalesce(sum(value),0) from stock_valuation(1) where code='M-1'));
update items set is_active=true where code='M-1';
-- untrack while stock exists, sell, track again
update items set tracked=false where code='M-1';
select tt.sale(1,'M-1',1) is not null as k5s \gset
update items set tracked=true where code='M-1';
select tt.eq('k5 sale made while the item was untracked left the book at 8 (real stock 7)', 7, tt.qty('M-1',1));
select tt.t('k5 toggling tracked off/on with stock on hand and a sale in between raised no flag', (select count(*) from exceptions where entry_date = tt.today() and text->>'en' ilike '%Renamed%') > 0, 'a flag', 'no flag mentions the item');
-- merge: no function
select tt.t('k6 an item merge function exists', exists (select 1 from pg_proc where pronamespace='public'::regnamespace and proname ~ '(item.*merge|merge.*item|dedup)'), 'exists', 'NOT SUPPORTED: none found');
