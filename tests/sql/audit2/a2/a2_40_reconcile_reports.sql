\echo == A2 40 reconciliation: is there an opening + movements = closing statement, and are mismatches visible?
select tt.as(:'o');
\echo -- (l1) functions that could be a per-item stock movement statement
select tt.t('l1 a stock movement statement function exists (opening / closing columns)', exists (select 1 from pg_proc where pronamespace='public'::regnamespace and proname ~ '(stock|inventory|item).*(statement|movement|rollforward|roll_forward|period)'), 'exists', 'none found by name');
select tt.t('l1 report k3_store_ledger has opening and closing columns', (select cols::text ~ 'opening' and cols::text ~ 'closing' from report_defs3 where key='k3_store_ledger'), 'opening+closing', (select string_agg(c->>0, ',') from report_defs3, jsonb_array_elements(cols) c where key='k3_store_ledger'));
select tt.t('l1 report k3_store_ledger has a location column', (select cols::text ~ 'location' from report_defs3 where key='k3_store_ledger'), 'location', 'no location column (rows are summed over the chosen places)');
select report_run3('k3_store_ledger', jsonb_build_object('from', tt.today(), 'to', tt.today()), null, null, 1) as k3 \gset
select tt.t('l1 k3_store_ledger runs for the owner', (:'k3'::jsonb->'rows') is not null and jsonb_array_length(:'k3'::jsonb->'rows') > 0, 'rows', jsonb_array_length(:'k3'::jsonb->'rows')::text || ' rows');
-- sum(net) over the period per item vs balance summed over all places (equation closes only if the report shows every place and every reason)
create temp table k3rows as select r->>'item_code' code, r->>'kind' kind, (r->>'in_qty')::numeric in_q, (r->>'out_qty')::numeric out_q, (r->>'net_qty')::numeric net from jsonb_array_elements(:'k3'::jsonb->'rows') r;
select tt.eq('l1 A-KG: report net over the day = balance of all places (opening is itself a movement row today)', (select coalesce(sum(qty),0) from stock_balance where item_id=tt.iid('A-KG')), (select coalesce(sum(net),0) from k3rows where code='A-KG'), 0.0005);
select tt.t('l1 report page covers every item that moved (rows < page size or has_more)', not coalesce((:'k3'::jsonb->>'has_more')::boolean,false), 'no truncation', (:'k3'::jsonb->>'has_more'));
select tt.t('l1 F-BATCH: kinds in report', true, 'info', (select string_agg(kind||':'||net, ' ' order by kind) from k3rows where code='F-BATCH'));
\echo -- (l2) mismatch visibility: ledger vs cached balance
select tt.eq('l2 stock_reconcile(false): rows that disagree on a clean run', 0, (select count(*) from stock_reconcile(false)));
update stock_balance set qty = qty + 1 where item_id=tt.iid('A-KG') and location_id=1;
select tt.eq('l2 cached balance tampered by +1: stock_reconcile shows 1 row', 1, (select count(*) from stock_reconcile(false)));
select tt.eq('l2 ... with qty_diff = +1', 1, (select qty_diff from stock_reconcile(false) limit 1));
select stock_reconcile(true) is not null as fx \gset
select tt.eq('l2 stock_reconcile(true) repairs it', 0, (select count(*) from stock_reconcile(false)));
\echo -- (l3) batch table vs balance is not part of stock_reconcile
select tt.t('l3 batches 13 vs balance 14 on F-BATCH is reported by stock_reconcile', exists (select 1 from stock_reconcile(false) where item_id=tt.iid('F-BATCH')), 'reported', 'stock_reconcile rows for F-BATCH: ' || (select count(*) from stock_reconcile(false) where item_id=tt.iid('F-BATCH'))::text);
select tt.t('l3 any function lists batches whose remaining qty exceeds the balance or ledger (batch consistency check)', exists (select 1 from pg_proc where pronamespace='public'::regnamespace and proname ~ 'batch.*(check|recon|consisten)'), 'exists', 'none found by name');
\echo -- (l4) sales vs stock ledger: sold quantity vs quantity taken out
create temp table sv as
 select i.code,
   (select coalesce(sum(public._base_qty(i.id,(l->>'qty')::numeric,l->>'unit')),0) from sales s, jsonb_array_elements(s.lines) l where s.status='done' and l->>'item_id'=i.id::text) as sold_base,
   (select coalesce(-sum(sl.qty_delta),0) from stock_ledger sl where sl.item_id=i.id and sl.reason in ('sale_out','sale_void_in')) as taken_base
 from items i where i.code in ('A-KG','B-PC','B-NOCONV','D-BOX','COMBO12','LOOSE','M-1','N-OFF','F-BATCH','F-SWPC');
select tt.t('l4 sold (sales lines) = taken out (ledger) for every sold item: mismatching items = ' || coalesce((select string_agg(code||'(sold '||round(sold_base,3)||' vs ledger '||round(taken_base,3)||')', ', ') from sv where abs(sold_base - taken_base) > 0.0005 and code <> 'COMBO12'),'none'), not exists (select 1 from sv where abs(sold_base - taken_base) > 0.0005 and code <> 'COMBO12'), 'no mismatch', 'mismatch');
select tt.t('l4 a report / function compares sales lines with the ledger per item (sales-to-stock check)', exists (select 1 from report_defs3 where is_active and key ~ 'sale.*(stock|ledger)|stock.*sale') or exists (select 1 from pg_proc where pronamespace='public'::regnamespace and proname ~ '(sale|sold).*(vs|recon|match).*(stock|ledger)'), 'exists', 'none found');
\echo -- (l5) existing production / usage variance reports
select report_run3('f3_raw_vs_recipe', jsonb_build_object('from', tt.today(), 'to', tt.today()), null, null, 1) as f3 \gset
select tt.t('l5 f3_raw_vs_recipe runs and shows expected vs actual use per run', jsonb_array_length(:'f3'::jsonb->'rows') > 0, 'rows', jsonb_array_length(:'f3'::jsonb->'rows')::text || ' rows');
select tt.eq('l5 f3 flour: expected = actual use (no variance, voided run excluded)', 0, (select coalesce(sum((r->>'diff')::numeric),0) from jsonb_array_elements(:'f3'::jsonb->'rows') r where r->>'ingredient_code'='RM-F'), 0.0005);
select inventory_vs_gl(tt.today(), 1) as ivg \gset
select tt.t('l5 inventory_vs_gl is value-only (money), needs accounting: result keys', true, 'info', (select string_agg(k, ',') from jsonb_object_keys(:'ivg'::jsonb) k));
select tt.t('l6 unmatched_forms is about paper forms vs screen records (not sales)', true, 'info', unmatched_forms(tt.today()-1, tt.today(), null)::text);
