-- Phase 424 tests (RPT-B2 R4a: item_slow in place, batch-wise stock with the unbatched line, finished-goods ageing). Database through phase 424.
-- Run from the repository root:  psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase424_test.sql | grep -E "FAIL|SUMMARY"
\set ON_ERROR_STOP off
\i tests/sql/p420_fixture.sql
reset role;
insert into rule_grants (grant_code, role_code) values ('report_stock','salesperson'),('report_sales','salesperson') on conflict do nothing;
create temp table b0 as select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('_r4_ans','_r4_band','_r4_bands','_r4_lineage','_r3q_item_slow','_r4d_item_slow','_r4_batch_rows','batch_stock_rows','fg_ageing_rows');
\i supabase/phase424.sql
select tt.chk('T0 pasting phase424 twice leaves the 9 functions equal, one item_slow row', (select count(*) from b0)=9 and not exists (select 1 from b0 join (select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace) a on a.proname=b0.proname and a.h<>b0.h)
  and (select count(*) from report_defs3 where key='item_slow')=1);
select tt.chk('T0 the helpers are private, the two RPCs are not open to anon', not has_function_privilege('authenticated','public._r4_batch_rows(int[],uuid,text[],boolean)','execute') and not has_function_privilege('authenticated','public._r4_lineage()','execute')
  and not has_function_privilege('anon','public.batch_stock_rows(int,uuid,text[])','execute') and not has_function_privilege('anon','public.fg_ageing_rows(int,text[])','execute'));
select tt.chk('T0 the band helper: 1,3,7 -> 0-1, 2-3, 4-7, 8+; no bands -> null', _r4_band(0,array[1,3,7])='0-1' and _r4_band(2,array[1,3,7])='2-3' and _r4_band(7,array[1,3,7])='4-7' and _r4_band(8,array[1,3,7])='8+' and _r4_band(5,null) is null);

-- two sellable items with stock and no movement in the period: one with an old purchase, one with only an opening entry (never costed)
insert into items (code,name_bn,name_en,category,unit,tracked,is_active,sellable,sell_price,item_type) values
 ('test_fg_old','test_পুরনো','test_old','test_cat_fg','pc',true,true,true,10,'finished_good'),('test_fg_open','test_ওপেন','test_open_only','test_cat_fg','pc',true,true,true,10,'finished_good') on conflict (code) do nothing;
insert into stock_ledger (item_id,location_id,qty_delta,unit_cost,reason,ref_type,made_at,note) select id,1,6,5,'purchase_in','purchase',now()-interval '40 days','test old' from items where code='test_fg_old';
insert into stock_ledger (item_id,location_id,qty_delta,unit_cost,reason,ref_type,made_at,note) select id,1,3,null,'opening','opening',now()-interval '40 days','test opening only' from items where code='test_fg_open';
set role authenticated; select tt.as(:'o');

\echo == T1 #67 item_slow in place
select tt.run('item_slow', '{"preset":"this_month","categories":["test_cat_fg","test_cat_resale"]}'::jsonb)::text as sj \gset
create temp table sj0 as select :'sj'::jsonb as j;
select tt.chk('T1 the old columns are the same as the old report for the same items (qty, net, bills, last_sold)', not exists (
  select 1 from sj0, jsonb_array_elements(j->'rows') n join jsonb_array_elements(tt.core('item_slow','{"preset":"this_month","categories":["test_cat_fg","test_cat_resale"]}'::jsonb)->'rows') o on o->>'item_code'=n->>'item_code'
  where (n->>'qty')::numeric <> (o->>'qty')::numeric or (n->>'net')::numeric <> (o->>'net')::numeric or (n->>'bills')::int <> (o->>'bills')::int or n->>'last_sold' is distinct from o->>'last_sold'));
select tt.chk('T1 sweet: sold 12, refunded 2, net 10; sales 3600, after refunds 3000; sold state', (select (r->>'qty')::numeric=12 and (r->>'refund_qty')::numeric=2 and (r->>'net_qty')::numeric=10 and (r->>'net')::numeric=3600 and (r->>'net_after_refunds')::numeric=3000 and r->>'state'='sold' and (r->>'bills')::int=1
  from sj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet'));
select tt.chk('T1 sweet: on hand is the book balance of all places (7.7 + 8 + 15 = 30.7) and has a value; last movement today', (select (r->>'on_hand')::numeric=30.7 and (r->>'value')::numeric>1000 and (r->>'last_movement')::date=tt.today() and (r->>'days_since_movement')::int=0 from sj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet'));
select tt.chk('T1 cake (never costed): on hand 2 pcs (3 at the factory, -1 at the outlet), value empty and flagged, not 0', (select (r->>'on_hand')::numeric=2 and r->'value'='null'::jsonb and r->'_nc' ? 'value' from sj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_cake'));
select tt.chk('T1 stock with an old purchase and nothing since: not_moving, last movement 40 days ago', (select r->>'state'='not_moving' and (r->>'on_hand')::numeric=6 and (r->>'days_since_movement')::int=40 and (r->>'value')::numeric=30 from sj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_old'));
select tt.chk('T1 stock that has only an opening entry: not_moving, last movement empty (not captured), never "today"', (select r->>'state'='not_moving' and r->'last_movement'='null'::jsonb and r->'_nc' ? 'last_movement' from sj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_open'));
select tt.chk('T1 tea (resale) sold 4, no refund, net 4', (select (r->>'net_qty')::numeric=4 and (r->>'refund_qty')::numeric=0 from sj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_rs_tea'));
select tt.chk('T1 the explanation notice is in the answer, and no limit is used for "slow"', exists (select 1 from sj0, jsonb_array_elements(j->'notes') n where n->>'text_en' like 'Sales are the sales of the period%'));
select tt.chk('T1 the item type filter works: resale only', (select count(*) from jsonb_array_elements(tt.run('item_slow','{"preset":"this_month","item_types":["resale"]}'::jsonb)->'rows') r where r->>'item_code' like 'test_%')=1);
select tt.chk('T1 the report is still in the sales group of the report list (same access as before)', (select grp from report_defs3 where key='item_slow')='sales' and exists (select 1 from jsonb_array_elements(report_catalog2()) e where e->>'key'='item_slow') and (select count(*) from jsonb_array_elements(report_catalog2()) e where e->>'key'='item_slow')=1);
reset role; select tt.as(:'x'); set role authenticated;
select tt.chk('T1 a person with report_sales sees quantities of own place (outlet 3) and no cost columns', not exists (select 1 from jsonb_array_elements(tt.run('item_slow','{"preset":"this_month"}'::jsonb)->'columns') c where c->>'key' in ('value','uncosted_lines'))
  and (select (r->>'on_hand')::numeric from jsonb_array_elements(tt.run('item_slow','{"preset":"this_month","categories":["test_cat_fg"]}'::jsonb)->'rows') r where r->>'item_code'='test_fg_sweet')=8);
reset role; select tt.as(:'o'); set role authenticated;

\echo == T2 #70 batch-wise stock with the unbatched line
select stock_production_in((select id from items where code='test_fg_sweet'), 6, 5, now(), null, 'test second batch', gen_random_uuid()) is not null as pb2 \gset
select batch_stock_rows()::text as bj \gset
create temp table bj0 as select :'bj'::jsonb as j;
select tt.chk('T2 identity: for every item and place, the batches + the unbatched line = the balance of the item', not exists (
  select 1 from (select r->>'item_code' ic, r->>'location_en' lc, sum((r->>'qty')::numeric) q, max((r->>'item_balance')::numeric) bal from bj0, jsonb_array_elements(j->'rows') r group by 1, 2) z where abs(z.q - z.bal) > 0.0005));
select tt.chk('T2 sweet at the factory: two open batches in FEFO order (the older expiry first), nothing unbatched', (select count(*)=2 and min((r->>'fefo_rank')::int)=1 and (array_agg(r->>'expires_on' order by (r->>'fefo_rank')::int))[1] < (array_agg(r->>'expires_on' order by (r->>'fefo_rank')::int))[2]
  from bj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and r->>'location_en' like 'Cake Factory%' and r->>'row_kind'='batch')
  and not exists (select 1 from bj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and r->>'location_en' like 'Cake Factory%' and r->>'row_kind'='unbatched'));
select tt.chk('T2 flour at the store (raw, received with no lot): one unbatched line of 77 kg, flagged not captured', (select (r->>'qty')::numeric=77 and r->>'state'='unbatched' and r->'_nc' ? 'made_on' and r->'made_on'='null'::jsonb from bj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_raw_flour' and r->>'location_en' like 'Godown%'));
select tt.chk('T2 cake at the outlet (sold beyond stock): the unbatched line is -1', (select (r->>'qty')::numeric=-1 and r->>'row_kind'='unbatched' from bj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_cake' and r->>'location_en' like 'ISLAMIYA MISTY GHAR — Main%'));
select tt.chk('T2 the cake batch at the factory has no expiry: state no_expiry, expiry and days left empty and flagged', (select r->>'state'='no_expiry' and r->'expires_on'='null'::jsonb and r->'days_left'='null'::jsonb and r->'_nc' ? 'expires_on' from bj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_cake' and r->>'row_kind'='batch'));
select tt.chk('T2 the sweet batch that expires within the 7 day threshold is soon (threshold from expiry_warn_days, named in the notice)', exists (select 1 from bj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and r->>'state'='soon')
  and exists (select 1 from bj0, jsonb_array_elements(j->'notes') n where n->>'text_en' like '%Soon = expires within 7 day(s) (rule expiry_warn_days)%'));
select tt.chk('T2 batch rows know where they came from: production, and a transferred batch names the production batch it came from (root)', exists (select 1 from bj0, jsonb_array_elements(j->'rows') r where r->>'origin'='production_in') and exists (select 1 from bj0, jsonb_array_elements(j->'rows') r where r->>'origin'='transfer_in' and r->'root_batch' <> 'null'::jsonb));
select tt.chk('T2 notices: batches with no expiry, stock in no batch', exists (select 1 from bj0, jsonb_array_elements(j->'notes') n where n->>'what'='shelf_life_rules / expires_at') and exists (select 1 from bj0, jsonb_array_elements(j->'notes') n where n->>'what'='lot / batch on receipt'));
select tt.chk('T2 the owner sees value on a costed batch (sweet) and an empty value on the uncosted cake', (select (r->>'value')::numeric>0 from bj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and r->>'row_kind'='batch' limit 1)
  and (select r->'value'='null'::jsonb from bj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_cake' and r->>'row_kind'='batch'));
select tt.chk('T2 filters: packaging only gives the box lines (unbatched), one place keeps one place', (select count(distinct r->>'item_code') from (select batch_stock_rows(null, null, array['packaging']) j) z, jsonb_array_elements(j->'rows') r)=1
  and (select count(distinct r->>'location_en') from (select batch_stock_rows(7) j) z, jsonb_array_elements(j->'rows') r)=1);
select tt.chk('T2 a single item can be asked for', (select count(distinct r->>'item_code') from (select batch_stock_rows(null, (select id from items where code='test_fg_cake')) j) z, jsonb_array_elements(j->'rows') r)=1);
reset role; select tt.as(:'x'); set role authenticated;
select tt.chk('T2 outlet 3 person: own place only, no value', (select count(distinct r->>'location_en') from (select batch_stock_rows() j) z, jsonb_array_elements(j->'rows') r)=1 and not exists (select 1 from (select batch_stock_rows() j) z, jsonb_array_elements(j->'columns') c where c->>'key'='value'));
select tt.err('T2 a person at outlet 3 cannot ask for outlet 1', $q$select batch_stock_rows(1)$q$, 'not allowed for this location');
reset role; select tt.as(:'k'); set role authenticated;
select tt.err('T2 no report grant, no batch report', $q$select batch_stock_rows()$q$, 'not allowed');
reset role; select tt.as(:'o'); set role authenticated;

\echo == T3 #68 finished-goods ageing
select fg_ageing_rows()::text as aj \gset
create temp table aj0 as select :'aj'::jsonb as j;
select tt.chk('T3 only finished goods by default (no flour, no tea)', not exists (select 1 from aj0, jsonb_array_elements(j->'rows') r where r->>'item_code' not in ('test_fg_sweet','test_fg_cake','test_fg_old','test_fg_open') and r->>'item_code' like 'test_%'));
select tt.chk('T3 the production batch made 2 days ago is 2 days old; the new batch is 0 days old; oldest first', (select (r->>'age_days')::int=2 from aj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and r->>'location_en' like 'Cake Factory%' and (r->>'qty_made')::numeric=50)
  and (select (r->>'age_days')::int=0 from aj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and (r->>'qty_made')::numeric=5));
select tt.chk('T3 no age band is invented while report_aging_buckets is empty: bands empty and the notice names the rule', (select bool_and(r->'age_band'='null'::jsonb) from aj0, jsonb_array_elements(j->'rows') r where r->>'row_kind'='batch') and exists (select 1 from aj0, jsonb_array_elements(j->'notes') n where n->>'what'='report_aging_buckets'));
select tt.chk('T3 the per-item summary: sweet at the factory has 2 batches, oldest 2 days, average age weighted by quantity', (select (r->>'batches')::int=2 and (r->>'oldest_days')::int=2 and (r->>'avg_days')::numeric = round((15*2 + 5*0)/20.0, 1) from aj0, jsonb_array_elements(j->'sections'->0->'rows') r where r->>'item_name'='test_মিষ্টি' and r->>'location' like 'Cake Factory%'));
select tt.chk('T3 stock in no batch is listed as unbatched with the age empty (cake at the outlet, the two never-batched items)', (select count(*) from aj0, jsonb_array_elements(j->'rows') r where r->>'row_kind'='unbatched' and r->'age_days'='null'::jsonb)>=3);
select set_rule('report_aging_buckets','"1,3"') is null as sr \gset
select tt.chk('T3 with the owner''s bands (rule set) the age band appears: 2 days = 2-3, 0 days = 0-1', (select r->>'age_band'='2-3' from (select fg_ageing_rows() j) z, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and (r->>'qty_made')::numeric=50)
  and (select r->>'age_band'='0-1' from (select fg_ageing_rows() j) z, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and (r->>'qty_made')::numeric=5));
select set_rule('report_aging_buckets',null) is null as sr2 \gset
select tt.chk('T3 the types can be changed: resale shows the tea as unbatched', (select count(*) from (select fg_ageing_rows(null, array['resale']) j) z, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_rs_tea')>=1);
select tt.chk('T3 no new setting: the rule report_aging_buckets exists since phase 9 and is empty again', rule_val('report_aging_buckets') is null);
reset role; select tt.as(:'k'); set role authenticated;
select tt.err('T3 no report grant, no ageing', $q$select fg_ageing_rows()$q$, 'not allowed');
reset role;

\echo == T4 the family of a production batch (used by the next phase)
select tt.chk('T4 lineage: the 50 kg batch has 3 children (outlet 1, outlet 3; the in-transit one has none yet)', (select count(*) from _r4_lineage() l where l.root = (select batch_id from production_runs limit 1))=3);
select tt.chk('T4 every production batch is its own root', (select count(*) from _r4_lineage() l where l.root=l.batch) = (select count(distinct batch_id) from stock_ledger where reason='production_in' and batch_id is not null));

\echo == SUMMARY
select 'SUMMARY ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
