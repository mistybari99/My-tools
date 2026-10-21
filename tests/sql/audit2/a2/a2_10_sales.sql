\echo == A2 10 sales -> stock (units, locations, batches, returns, void)
create or replace function tt.sale(p_loc int, p_code text, p_qty numeric, p_client uuid default gen_random_uuid(), p_at timestamptz default null) returns jsonb language plpgsql as $$
declare amt numeric; begin select round(p_qty * sell_price, 2) into amt from public.items where code = p_code;
  return public.record_sale2(p_client, p_loc, jsonb_build_array(jsonb_build_object('item_id', tt.iid(p_code), 'qty', p_qty)), 0, jsonb_build_array(jsonb_build_object('mode','cash','amount', amt)), null, null, 'retail', null, false, p_at); end $$;
create or replace function tt.bsum(p_code text, p_loc int) returns numeric language sql stable as $$ select coalesce(sum(qty_remaining),0) from public.stock_batches where item_id = tt.iid(p_code) and location_id = p_loc $$;
create or replace function tt.brem(p_code text, p_loc int) returns text language sql stable as $$ select coalesce(string_agg(trim_scale(qty_remaining)::text, ',' order by id),'') from public.stock_batches where item_id = tt.iid(p_code) and location_id = p_loc $$;
create or replace function tt.exc(p_flag text) returns bigint language sql stable as $$ select count(*) from public.exceptions where flag_code = p_flag $$;
grant execute on all functions in schema tt to authenticated, anon;

\echo -- (a1) 0.75 kg of an item stocked in kg
select tt.as(:'sp');
select tt.sale(1,'A-KG',0.75) as s1 \gset
select (:'s1'::jsonb->>'id')::uuid as sale1 \gset
select tt.eq('a1 total 0.75 x 200', 150, (:'s1'::jsonb->>'total')::numeric);
select tt.eq('a1 A-KG loc1 10 - 0.75', 9.25, tt.qty('A-KG',1));
select tt.eq('a1 ledger row qty_delta', -0.75, (select qty_delta from stock_ledger where ref_type='sale' and ref_id=:'sale1' and reason='sale_out'));
select tt.eq('a1 avg cost unchanged on sale', 100, tt.avg('A-KG',1));

\echo -- (a2) 3 pc of an item with 1 pc = 0.2 kg (item unit pc, stock base kg)
select tt.sale(1,'B-PC',3) as s2 \gset
select (:'s2'::jsonb->>'id')::uuid as sale2 \gset
select tt.eq('a2 total 3 x 50', 150, (:'s2'::jsonb->>'total')::numeric);
select tt.eq('a2 B-PC stock 5 kg - 3 pc x 0.2 = 4.4', 4.4, tt.qty('B-PC',1));

\echo -- (a2b) same unit but NO conversion row (default unit_conv_required = warn)
select tt.sale(1,'B-NOCONV',3) as s2b \gset
select tt.t('a2b no conversion: either sale refused or stock reduced (expected 5 - 0.6 = 4.4 or error)', tt.qty('B-NOCONV',1) <> 5, 'stock changed or refused', 'sale accepted, stock stays ' || tt.qty('B-NOCONV',1)::text);
select tt.eq('a2b yellow stock_unit_unknown raised (owner can see it)', 1, tt.exc('stock_unit_unknown'));
select tt.as(:'o');
select set_rule('unit_conv_required','"refuse"') is null as ucr \gset
select tt.as(:'sp');
select tt.err('a2b unit_conv_required=refuse -> sale refused', $$select tt.sale(1,'B-NOCONV',1)$$, 'unit_unknown');
select tt.as(:'o');
select set_rule('unit_conv_required','"warn"') is null as ucr2 \gset
select tt.as(:'sp');

\echo -- (a3) box of 12, stock held as loose pcs (same item: unit box, base pc, 1 box = 12 pc)
select tt.sale(1,'D-BOX',2) as s3 \gset
select tt.eq('a3 D-BOX total 2 x 600', 1200, (:'s3'::jsonb->>'total')::numeric);
select tt.eq('a3 D-BOX stock 120 pc - 2 box x 12 = 96', 96, tt.qty('D-BOX',1));
\echo -- (a3b) combo of a DIFFERENT loose item (COMBO12 untracked; LOOSE is the stock item)
select tt.as(:'o');
select tt.err('a3b packaging_set(combo, loose item) refused: component must be item_type packaging', format($$select packaging_set('%s','%s',12,'sale')$$, tt.iid('COMBO12'), tt.iid('LOOSE')), 'bad_ingredient_type');
select tt.as(:'sp');
select tt.sale(1,'COMBO12',1) as s3b \gset
select tt.eq('a3b selling 1 combo of 12 loose pc: LOOSE should be 108', 108, tt.qty('LOOSE',1));

\echo -- (b) location isolation
select tt.eq('b0 A-KG loc2 opening', 4, tt.qty('A-KG',2));
select tt.sale(1,'A-KG',1) is not null as b1 \gset
select tt.eq('b1 sale at loc1 -> loc1 9.25-1', 8.25, tt.qty('A-KG',1));
select tt.eq('b1 loc2 untouched', 4, tt.qty('A-KG',2));
select tt.err('b2 seller of loc1 cannot sell at loc2', $$select tt.sale(2,'A-KG',1)$$, 'not allowed for this location');
select tt.as(:'rv');
select tt.sale(2,'A-KG',1.5) is not null as b3 \gset
select tt.eq('b3 seller2 sale at loc2 -> loc2 4-1.5', 2.5, tt.qty('A-KG',2));
select tt.eq('b3 loc1 untouched', 8.25, tt.qty('A-KG',1));
select tt.as(:'o');
select tt.sale(3,'A-KG',1) is not null as b4 \gset
select tt.eq('b4 owner sale at loc3 (no stock there): loc3 balance', -1, tt.qty('A-KG',3));
select tt.eq('b4 loc1 / loc2 untouched', 8.25 + 2.5, tt.qty('A-KG',1) + tt.qty('A-KG',2));

\echo -- (c) expiry / FIFO batches (shelf life 4 days; batches made out of order)
insert into shelf_life_rules (item_id, value, unit, active) values (tt.iid('F-BATCH'), 4, 'days', true);
select (stock_production_in(tt.iid('F-BATCH'),1,5,now()-interval '1 day'))->>'batch_id' as b_y \gset
select (stock_production_in(tt.iid('F-BATCH'),1,5,now()-interval '3 days'))->>'batch_id' as b_o \gset
select (stock_production_in(tt.iid('F-BATCH'),1,5,now()-interval '2 days'))->>'batch_id' as b_m \gset
select tt.eq('c0 F-BATCH 15 kg in 3 batches', 15, tt.qty('F-BATCH',1));
select tt.as(:'sp');
select tt.sale(1,'F-BATCH',7) as s4 \gset
select (:'s4'::jsonb->>'id')::uuid as sale4 \gset
select tt.is('c1 batches [youngest, oldest, middle] after selling 7 = 5,0,3 (oldest consumed first)', '5,0,3', tt.brem('F-BATCH',1)||'');
select tt.is('c1 ledger rows of the sale carry the batch ids (oldest, middle)', :'b_o' || ',' || :'b_m', (select string_agg(batch_id::text, ',' order by id) from stock_ledger where ref_id=:'sale4' and reason='sale_out'));
select tt.eq('c1 balance 15-7', 8, tt.qty('F-BATCH',1));
select tt.eq('c1 sum(batch remaining) = balance', tt.qty('F-BATCH',1), tt.bsum('F-BATCH',1));

\echo -- (d) returns -> same batch, same location
select tt.as(:'o');
select sale_return(gen_random_uuid(), :'sale4'::uuid, format('[{"item_id":"%s","qty":3}]', tt.iid('F-BATCH'))::jsonb, 'damaged','a2 return 3','cash') is not null as r1 \gset
select tt.is('d1 return 3 kg goes back to the OLDEST batch first (5,3,3)', '5,3,3', tt.brem('F-BATCH',1)||'');
select tt.eq('d1 balance 8+3', 11, tt.qty('F-BATCH',1));
select sale_return(gen_random_uuid(), :'sale4'::uuid, format('[{"item_id":"%s","qty":4}]', tt.iid('F-BATCH'))::jsonb, 'damaged','a2 return 4','cash') is not null as r2 \gset
select tt.is('d2 rest of the sale returned: all three batches full again (5,5,5)', '5,5,5', tt.brem('F-BATCH',1)||'');
select tt.err('d3 return more than sold refused', format($$select sale_return(gen_random_uuid(), '%s'::uuid, '[{"item_id":"%s","qty":1}]'::jsonb, 'damaged','x','cash')$$, :'sale4', tt.iid('F-BATCH')), 'return_exceeds_sale');
select tt.eq('d4 return of a loc1 sale never touches loc2', 2.5, tt.qty('A-KG',2));
select sale_return(gen_random_uuid(), :'sale2'::uuid, format('[{"item_id":"%s","qty":1}]', tt.iid('B-PC'))::jsonb, 'damaged','a2 return 1 pc','cash') is not null as r3 \gset
select tt.eq('d5 return 1 pc (0.2 kg) of B-PC: 4.4 + 0.2', 4.6, tt.qty('B-PC',1));
select tt.err('d6 void of a sale that has a return refused', format($$select void_sale('%s'::uuid,'x')$$, :'sale4'), 'sale_has_returns');

\echo -- (e) void restores stock to the same batches
select tt.as(:'sp');
select tt.sale(1,'F-BATCH',7) as s5 \gset
select (:'s5'::jsonb->>'id')::uuid as sale5 \gset
select tt.is('e0 after 2nd sale of 7: 0,5,3 pattern by id (youngest 5, oldest 0, middle 3)', '5,0,3', tt.brem('F-BATCH',1)||'');
select tt.as(:'o');
select void_sale(:'sale5'::uuid, 'a2 void') is null as v1 \gset
select tt.is('e1 void puts the units back in the SAME batches (5,5,5)', '5,5,5', tt.brem('F-BATCH',1)||'');
select tt.eq('e1 balance back to 15', 15, tt.qty('F-BATCH',1));
select tt.err('e2 second void refused', format($$select void_sale('%s'::uuid,'x')$$, :'sale5'), 'already void');
select tt.as(:'sp');
select tt.sale(1,'B-PC',2) as s6 \gset
select tt.eq('e3 B-PC sale 2 pc: 4.6 - 0.4', 4.2, tt.qty('B-PC',1));
select tt.as(:'o');
select void_sale((:'s6'::jsonb->>'id')::uuid, 'a2 void pc') is null as v2 \gset
select tt.eq('e3 void restores 0.4 kg', 4.6, tt.qty('B-PC',1));
select void_sale(:'sale1'::uuid, 'a2 void A-KG') is null as v3 \gset
select tt.eq('e4 void of 0.75 kg sale: A-KG loc1 8.25 + 0.75', 9.0, tt.qty('A-KG',1));

\echo -- (d7) conversion factor changed AFTER the sale, then a return of that sale
select set_unit_conversion(tt.iid('B-PC'),'pc','kg',0.25,'factor changed') is null as cf \gset
select sale_return(gen_random_uuid(), :'sale2'::uuid, format('[{"item_id":"%s","qty":1}]', tt.iid('B-PC'))::jsonb, 'damaged','a2 return after factor change','cash') is not null as r4 \gset
select tt.eq('d7 2nd pc of the sale (sold at 0.2 kg/pc) returned after factor became 0.25: stock should be 4.6 + 0.2 = 4.8', 4.8, tt.qty('B-PC',1));
select set_unit_conversion(tt.iid('B-PC'),'pc','kg',0.2,'restore') is null as cf2 \gset

\echo -- (j-sales) unit of an item changed while stock exists
select tt.as(:'o');
update items set base_unit='pc' where code='M-1';
select tt.eq('k0 changing base_unit kg->pc on an item that holds 10: balance silently re-read as 10 pc', 10, tt.qty('M-1',1));
select tt.t('k0 base_unit change with stock on hand is refused or converted', false, 'refused', 'accepted, stock number unchanged');
update items set base_unit='kg' where code='M-1';

\echo -- batch vs balance drift after a count gain / opening (batches only exist for produced / received lots)
select tt.eq('x1 A-KG loc1 batches vs balance (opening has no batch)', 0, tt.bsum('A-KG',1));
select tt.t('x1 balance 9.0 kg but 0 kg is batch-tracked: no expiry / FIFO for opening stock', tt.qty('A-KG',1) = tt.bsum('A-KG',1), 'balance = sum(batches)', 'balance='||tt.qty('A-KG',1)||' batches='||tt.bsum('A-KG',1));
