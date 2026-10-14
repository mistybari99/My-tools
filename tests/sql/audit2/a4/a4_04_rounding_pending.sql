\echo == A4-04 rounding drift on 3-decimal cost, stale GL before posting, per-cashier dimension
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('FG-Y','Y','Item Y','pc','pc','finished_good',true,10,true) on conflict do nothing;
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'A4-B2',tt.today(),format('[{"item_id":"%s","qty":1000,"unit":"pc","unit_cost":41.3333}]',tt.iid('FG-Y'))::jsonb)->>'id' as b2 \gset
select post_purchase(:'b2'::uuid) is not null as pb2 \gset
select acct_post_pending(false) is not null as ppr0 \gset
select inventory_vs_gl(tt.today(), 1) as ivg0 \gset
select tt.as(:'sp');
select count(record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":0.7,"price":10}]',tt.iid('FG-Y'))::jsonb,0,'[{"mode":"cash","amount":7}]',null,null,'retail',null,false)) as n50 from generate_series(1,50) \gset
select tt.as(:'o');
select acct_post_pending(false) is not null as ppr1 \gset
select inventory_vs_gl(tt.today(), 1) as ivg1 \gset
\echo INV_VS_GL_AFTER_50_FRACTIONAL_SALES: :ivg1
select tt.eq('RD1 inventory_vs_gl unexplained after 50 sales at cost 41.3333 x 0.7 (rounding drift tolerance)', 0, (:'ivg1'::jsonb->'total'->>'unexplained')::numeric, 0.05);
select tt.eq('RD1 GL vs stock-ledger valuation drift (total diff)', 0, (:'ivg1'::jsonb->'total'->>'diff')::numeric, 0.05);
select tt.eq('RD2 trial balance still balanced', 0, (select sum(debit-credit) from journal_lines));
-- stale GL: a due sale is recorded but not posted -> reconciliation shows a difference until the next post
select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":10}]',tt.iid('FG-Y'))::jsonb,0,'[]','01700000001','Cust One','retail',null,false) is not null as dsale \gset
select tt.as(:'o');
select acct_reconcile('all')->>'customers_off' as stale_off \gset
select acct_overview(null)->'status'->>'pending' as stale_pending \gset
select tt.eq('ST1 reconcile before posting: customers differing (GL lags the sub-ledger)', 1, :'stale_off'::numeric);
select tt.eq('ST1 status strip shows pending documents', 1, :'stale_pending'::numeric, 0.5);
select acct_post_pending(false) is not null as ppr2 \gset
select tt.eq('ST2 after posting the difference is gone', 0, (acct_reconcile('all')->>'customers_off')::numeric);
-- per cashier: journal has no cashier dimension
select tt.t('PC1 journal_entries carries the cashier who made the sale', (select count(*) from information_schema.columns where table_name='journal_entries' and column_name in ('cashier','sale_staff'))>0, 'column', 'only created_by/created_staff = POSTER', 'created_by = auth.uid() of the posting run (owner or null for scheduler)');
select tt.eq('PC2 journal_entries.created_staff of sale entries filled with the cashier staff id (count of sale entries whose created_staff = seller staff)', 0, (select count(*) from journal_entries e join sales s on e.source_type='sale' and e.source_id=s.id::text where e.created_staff is not distinct from s.created_staff and s.created_staff = 'seller'));
select (select count(distinct created_staff) from sales) as nsellers \gset
\echo SALES_CREATED_STAFF_DISTINCT: :nsellers
select tt.eq('PC3 sale_payments by cashier and mode can be summed from sale_payments (supported)', 1, (select count(*) from (select created_staff, mode, sum(amount) from sale_payments where not voided group by 1,2) z where created_staff='seller' and mode='cash')::numeric);
