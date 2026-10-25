\echo == S3 (c) multi-stage, by-product, packaging at packing stage
-- chhana (semi-finished) as an ingredient of the sweet
select loc_cost_cfg_set(1,'off') is null as lc \gset
select (recipe_save(null, tt.iid('FG-CHH'), 3, 'kg', 'chhana v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',tt.iid('RM-M'),'qty',20,'unit','ltr','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rch \gset
select recipe_approve(:'rch'::uuid,'ok') is not null as apc \gset
-- HAND: 20 ltr x 80 = 1600 -> 3 kg chhana -> 533.333/kg
select production_post(1, :'rch'::uuid, 1, gen_random_uuid(), null, 'chhana', null) as ppc \gset
select tt.eq('C1 chhana unit cost 1600/3', 533.3333, tt.avg('FG-CHH'), 0.0005);
select tt.err('C2 finished good (chhana) as ingredient of another recipe is refused', format($$select recipe_save(null,'%s',10,'kg','x','[{"ingredient_item_id":"%s","qty":3,"unit":"kg","waste_pct":0}]'::jsonb,gen_random_uuid())$$, tt.iid('FG-SW'), tt.iid('FG-CHH')), 'bad_ingredient_type');
-- by-product / co-product: structure check
select tt.t('C3 co/by-product support: production_runs has a single output item and no output-lines table', not exists (select 1 from information_schema.tables where table_schema='public' and table_name ~ 'byprod|coprod|production_out|production_line'), 'not supported', (select count(*)::text from information_schema.tables where table_schema='public' and table_name ~ 'byprod|coprod|production_out|production_line'));
-- packaging at packing stage, consumed at production, rule packaging_consume_on=production, 1 pouch per kg of PLANNED yield
select set_rule('packaging_consume_on','"production"') is null as pc \gset
select packaging_set(tt.iid('FG-OIL'), tt.iid('PK-P'), 1, 'production') is not null as ps \gset
select (recipe_save(null, tt.iid('FG-OIL'), 10, 'kg', 'oil product', jsonb_build_array(jsonb_build_object('ingredient_item_id',tt.iid('RM-O'),'qty',10,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as roil \gset
select recipe_approve(:'roil'::uuid,'ok') is not null as apo \gset
-- oil purchase 100@40 needed first
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'OIL1',tt.today()-10,format('[{"item_id":"%s","qty":100,"unit":"kg","unit_cost":40}]',tt.iid('RM-O'))::jsonb)->>'id' as bo1 \gset
select post_purchase(:'bo1'::uuid) is not null as pbo1 \gset
-- HAND: 3 batches planned 30 kg, actual 27 kg: oil 30x40=1200 ; pouches planned 30 x1 = 30 x 1 = 30 (consumed on PLANNED yield, not 27) ; total 1230 ; unit 1230/27 = 45.5556
select production_post(1, :'roil'::uuid, 3, gen_random_uuid(), null, 'oil 3 batches', 27) as ppo \gset
select tt.eq('C4 pouch left 300-30 (planned yield)', 270, tt.qty('PK-P'));
select tt.eq('C4 oil FG unit cost (1200+30)/27', 45.5556, tt.avg('FG-OIL'), 0.0005);
select tt.eq('C4 oil left 100-30', 70, tt.qty('RM-O'));
-- workaround for multi-stage: typed cost production-in (no recipe) -> consumes no milk
select set_rule('acct_manual_prod_in103','true') is null as mp \gset
select stock_production_in(tt.iid('FG-CHH'),1,3,now(),null,'manual chhana typed cost',gen_random_uuid(),533.33) as spi \gset
select acct_post_pending(false) as pp \gset
select tt.eq('C5 manual production-in 3kg x 533.33 posts Cr 5950 (overhead absorbed) = 1599.99 although no milk was consumed', 1599.99, (select coalesce(sum(l.credit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='stock_prodin' and a.code='5950'));
select tt.eq('C5 milk still in stock (never consumed) = 180 ltr, yet chhana value added to 1310', 180, tt.qty('RM-M'));
select set_rule('acct_manual_prod_in103',null) is null as mp0 \gset
