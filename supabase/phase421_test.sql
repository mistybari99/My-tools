-- Phase 421 tests (RPT-B2 R2a: transfers register, count variance in place, adjustment history, wastage %). Database built through phase 421 (420 and 421 pasted once).
-- Run from the repository root:  psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase421_test.sql | grep -E "FAIL|SUMMARY"
\set ON_ERROR_STOP off
\i tests/sql/p420_fixture.sql
reset role;
insert into rule_grants (grant_code, role_code) values ('report_stock','salesperson') on conflict do nothing;
create temp table b0 as select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('_r3q_transfers_register','_r3q_k2_count_variance','_r3q_stock_adjustments','_r3q_wastage_rate','_r4d_transfers_register','_r4d_k2_count_variance','_r4d_stock_adjustments','_r4d_wastage_rate');
\i supabase/phase421.sql
select tt.chk('T0 pasting phase421 twice leaves the functions equal, no duplicate registry row', (select count(*) from b0)=8 and not exists (select 1 from b0 join (select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace) a on a.proname=b0.proname and a.h<>b0.h)
  and (select count(*) from report_defs3 where key in ('transfers_register','k2_count_variance','stock_adjustments','wastage_rate'))=4);
select tt.chk('T0 the query functions are private', not has_function_privilege('authenticated','public._r3q_transfers_register(date,date,int[],jsonb)','execute') and not has_function_privilege('authenticated','public._r4d_wastage_rate(jsonb,jsonb)','execute'));
set role authenticated; select tt.as(:'o');

\echo == T1 #64 transfers register: all transfers, not only the exceptions
select tt.chk('T1 eight transfers in the period (3 raw, 4 finished goods, 1 cancelled)', jsonb_array_length(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'rows')=8);
select tt.chk('T1 the exceptions-only report still lists just the short and the in-transit ones (2) and they are inside the register', jsonb_array_length(tt.run('transfers_gap','{"preset":"this_month"}'::jsonb)->'rows')=2);
select tt.chk('T1 the short transfer: sent 10, received 8, short 2, flag short, claim open', (select (r->>'sent_qty')::numeric=10 and (r->>'received_qty')::numeric=8 and (r->>'short_qty')::numeric=2 and r->>'flag'='short' and r->>'claim'='open'
  from jsonb_array_elements(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'flag'='short'));
select tt.chk('T1 the transfer still in transit: flag, 5 kg in transit, 0 days, no received qty', (select r->>'flag'='in_transit' and (r->>'in_transit_qty')::numeric=5 and (r->>'days_in_transit')::int=0 and r->'received_qty'='null'::jsonb and r->>'short_qty' is null
  from jsonb_array_elements(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'flag'='in_transit'));
select tt.chk('T1 the cancelled transfer is listed as cancelled (the exceptions report hides it)', (select count(*) from jsonb_array_elements(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'flag'='cancelled')=1);
select tt.chk('T1 the transfers received in full are ok with short 0', (select count(*) from jsonb_array_elements(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'flag'='ok' and (r->>'short_qty')::numeric=0)=5);
select tt.chk('T1 value of a transfer = cost at send (flour 80 kg at 40.75 or less per the average then), money, owner sees it', (select (r->>'value')::numeric>0 from jsonb_array_elements(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'item_code'='test_raw_flour'));
select tt.chk('T1 short value: the shortage record carries a cost (2 kg x cost at send)', (select (r->>'short_value')::numeric>0 from jsonb_array_elements(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'flag'='short'));
select tt.chk('T1 notice counts: 8 transfers, 1 in transit, 1 short', exists (select 1 from jsonb_array_elements(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'notes') n where n->>'text_en' like '8 transfer(s)%1 still in transit, 1 received short%'));
select tt.chk('T1 every row has a drill link to the sender ledger', not exists (select 1 from jsonb_array_elements(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'drill' not like '#/stockrep/ledger?item=%&loc=%'));
select tt.chk('T1 sum of the sent kg per transfer matches the ledger transfer_out rows', (select sum((r->>'sent_qty')::numeric) filter (where r->>'item_code'='test_fg_sweet') from jsonb_array_elements(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'rows') r) = tt.n('select -sum(qty_delta) from stock_ledger where reason=''transfer_out'' and item_id=(select id from items where code=''test_fg_sweet'')'));
reset role; select tt.as(:'x'); set role authenticated;
select tt.chk('T1 a person at outlet 3 sees only the transfers that touch outlet 3 (the short one), without cost columns', jsonb_array_length(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'rows')=1
  and not exists (select 1 from jsonb_array_elements(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'columns') c where c->>'key' in ('value','short_value')) and exists (select 1 from jsonb_array_elements(tt.run('transfers_register','{"preset":"this_month"}'::jsonb)->'notes') n where n->>'code'='cost_hidden'));
reset role; select tt.as(:'o'); set role authenticated;

\echo == T2 #66 count variance: sheets and app counts, with value
reset role;
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('04-3',1,9601,current_date,'approved',jsonb_build_object('counted_by','test_store','rows',jsonb_build_array(jsonb_build_object('item','test_fg_sweet','count',7.5,'book',8,'reason','test sheet reason'),jsonb_build_object('item','test_rs_tea','count',36,'book',36))),'[]',:'o','test_store');
set role authenticated; select tt.as(:'o');
select tt.chk('T2 the paper sheet rows are still there: sweet counted 7.5 vs book 8 (net -0.5), tea counted 36 = book (counted, no difference)', (select (r->>'counts')::int=1 and (r->>'off_n')::int=1 and (r->>'net_var')::numeric=-0.5 from jsonb_array_elements(tt.run('k2_count_variance','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'source'='sheet 04-3' and r->>'item_code'='test_fg_sweet')
  and (select (r->>'counts')::int=1 and (r->>'off_n')::int=0 from jsonb_array_elements(tt.run('k2_count_variance','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'source'='sheet 04-3' and r->>'item_code'='test_rs_tea'));
select tt.chk('T2 the counts typed in the app are included: sweet -0.3 at outlet 1, flour -1 at the store, tea +2, salt -1 (4 rows)', (select count(*) from jsonb_array_elements(tt.run('k2_count_variance','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'source'='count in app')=4
  and (select (r->>'net_var')::numeric from jsonb_array_elements(tt.run('k2_count_variance','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'source'='count in app' and r->>'item_code'='test_fg_sweet')=-0.3);
select tt.chk('T2 for an app count the number of counts and the off % are not captured (empty, flagged), not 0 and not 100', (select r->'counts'='null'::jsonb and r->'off_pct'='null'::jsonb and r->'_nc' ? 'counts' from jsonb_array_elements(tt.run('k2_count_variance','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'source'='count in app' and r->>'item_code'='test_fg_sweet'));
select tt.chk('T2 value of a difference = net variance x average cost now (sweet sheet: -0.5 x 42.53 = -21.27 approx; app flour -1 x avg)', (select abs((r->>'net_value')::numeric - (-0.5 * tt.n('select avg_cost from stock_balance where item_id=(select id from items where code=''test_fg_sweet'') and location_id=1'))) < 0.02
  from jsonb_array_elements(tt.run('k2_count_variance','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'source'='sheet 04-3' and r->>'item_code'='test_fg_sweet'));
select tt.chk('T2 salt has no cost: value empty and flagged (no estimate)', (select r->'net_value'='null'::jsonb and r->'_nc' ? 'net_value' from jsonb_array_elements(tt.run('k2_count_variance','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'source'='count in app' and r->>'item_code'='test_raw_salt'));
select tt.chk('T2 the explanation of the two sources is in the notices', exists (select 1 from jsonb_array_elements(tt.run('k2_count_variance','{"preset":"this_month"}'::jsonb)->'notes') n where n->>'text_en' like 'Two sources:%'));
select tt.chk('T2 the report is still registered under the same key and group', (select grp='stock' and key='k2_count_variance' from report_defs3 where key='k2_count_variance'));
reset role; select tt.as(:'x'); set role authenticated;
select tt.chk('T2 a person at outlet 3 sees no rows from other places and no value columns', jsonb_array_length(tt.run('k2_count_variance','{"preset":"this_month"}'::jsonb)->'rows')=0 and not exists (select 1 from jsonb_array_elements(tt.run('k2_count_variance','{"preset":"this_month"}'::jsonb)->'columns') c where c->>'key' in ('net_value','abs_value')));
reset role; select tt.as(:'o'); set role authenticated;

\echo == T3 #71 stock adjustment history
select tt.chk('T3 four adjustments in the period (sweet, flour, tea, salt)', jsonb_array_length(tt.run('stock_adjustments','{"preset":"this_month"}'::jsonb)->'rows')=4);
select tt.chk('T3 sweet: book 8, counted 7.7, difference -0.3, decrease, who is the owner, why = the note', (select (r->>'book_qty')::numeric=8 and (r->>'counted_qty')::numeric=7.7 and (r->>'qty_delta')::numeric=-0.3 and r->>'direction'='decrease' and r->>'who' like 'test_owner%' and r->>'why'='test count'
  from jsonb_array_elements(tt.run('stock_adjustments','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'item_code'='test_fg_sweet'));
select tt.chk('T3 a decrease is valued at the booked cost (basis says so)', (select r->>'basis'='booked cost' and (r->>'value')::numeric<0 from jsonb_array_elements(tt.run('stock_adjustments','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'item_code'='test_fg_sweet'));
select tt.chk('T3 a gain has no booked cost: valued at the average cost now and the basis says so (tea +2 x 12 = 24)', (select r->>'basis'='average cost now' and (r->>'value')::numeric=24 and r->>'direction'='increase' from jsonb_array_elements(tt.run('stock_adjustments','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'item_code'='test_rs_tea'));
select tt.chk('T3 salt (never costed): no value, basis no cost recorded, flagged, never 0', (select r->'value'='null'::jsonb and r->>'basis'='no cost recorded' and r->'_nc' ? 'value' from jsonb_array_elements(tt.run('stock_adjustments','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'item_code'='test_raw_salt'));
select tt.chk('T3 the book and counted quantities agree with the ledger (counted = book + difference on every row)', not exists (select 1 from jsonb_array_elements(tt.run('stock_adjustments','{"preset":"this_month"}'::jsonb)->'rows') r where (r->>'book_qty')::numeric + (r->>'qty_delta')::numeric <> (r->>'counted_qty')::numeric));
select tt.chk('T3 item type filter works (raw material only: flour and salt)', (select count(*) from jsonb_array_elements(tt.run('stock_adjustments','{"preset":"this_month","item_types":["raw_material"]}'::jsonb)->'rows') r)=2);
select tt.chk('T3 every row drills to the ledger of the item and place', not exists (select 1 from jsonb_array_elements(tt.run('stock_adjustments','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'drill' not like '#/stockrep/ledger?item=%&loc=%'));
select tt.chk('T3 the total value only adds the rows that have one', (tt.run('stock_adjustments','{"preset":"this_month"}'::jsonb)->'totals'->>'value')::numeric = (select sum((r->>'value')::numeric) from jsonb_array_elements(tt.run('stock_adjustments','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'value' is not null));
reset role; select tt.as(:'x'); set role authenticated;
select tt.chk('T3 outlet 3 person: nothing from other places', jsonb_array_length(tt.run('stock_adjustments','{"preset":"this_month"}'::jsonb)->'rows')=0);
reset role; select tt.as(:'o'); set role authenticated;

\echo == T4 #77 wastage % with the denominator
select tt.chk('T4 sweet at outlet 1: wastage 2.0 kg of 20 kg handled (opening 0 + received 20) = 10 %', (select (r->>'wastage_qty')::numeric=2 and (r->>'opening_qty')::numeric=0 and (r->>'received_qty')::numeric=20 and (r->>'handled_qty')::numeric=20 and (r->>'wastage_pct')::numeric=10 and (r->>'entries')::int=2
  from jsonb_array_elements(tt.run('wastage_rate','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'item_code'='test_fg_sweet' and r->>'location_en' like '%Main Showroom%'));
select tt.chk('T4 cake at the factory: 1 of 12 made = 8.33 %', (select (r->>'wastage_pct')::numeric=8.33 and r->>'unit'='pc' from jsonb_array_elements(tt.run('wastage_rate','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'item_code'='test_fg_cake'));
select tt.chk('T4 value of the wastage = quantity x ledger cost (costed entries); the cake has no cost so its value is empty and flagged', (select (r->>'wastage_value')::numeric>80 and (r->>'uncosted_entries')::int=0 from jsonb_array_elements(tt.run('wastage_rate','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'item_code'='test_fg_sweet')
  and (select r->'wastage_value'='null'::jsonb and (r->>'uncosted_entries')::int=1 and r->'_nc' ? 'wastage_value' from jsonb_array_elements(tt.run('wastage_rate','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'item_code'='test_fg_cake'));
select tt.chk('T4 value share of sales for the sweet = 85.06 / 3600 of that outlet', (select abs((r->>'value_pct_of_sales')::numeric - (r->>'wastage_value')::numeric * 100.0 / (r->>'sales_value')::numeric) < 0.01 and (r->>'sales_value')::numeric=3600
  from jsonb_array_elements(tt.run('wastage_rate','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'item_code'='test_fg_sweet'));
reset role;
insert into stock_ledger (item_id,location_id,qty_delta,unit_cost,reason,ref_type,made_at,note) values (:'i_te'::uuid,4,-1,null,'wastage','wastage',now(),'test: wasted with nothing held');
insert into stock_wastage (item_id,location_id,qty,reason_code,ledger_id,made_at) select :'i_te'::uuid,4,1,'spoiled',max(id),now() from stock_ledger where reason='wastage' and location_id=4;
set role authenticated; select tt.as(:'o');
select tt.chk('T4 nothing held and nothing received: the % is empty (no denominator), never 0 or a divide error', (select r->'wastage_pct'='null'::jsonb and r->'_nc' ? 'wastage_pct' and (r->>'handled_qty')::numeric<=0 from jsonb_array_elements(tt.run('wastage_rate','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'item_code'='test_rs_tea'));
select tt.chk('T4 item type filter: finished goods only', not exists (select 1 from jsonb_array_elements(tt.run('wastage_rate','{"preset":"this_month","item_types":["finished_good"]}'::jsonb)->'rows') r where r->>'item_code'='test_rs_tea') and jsonb_array_length(tt.run('wastage_rate','{"preset":"this_month","item_types":["finished_good"]}'::jsonb)->'rows')=2);
select tt.chk('T4 the explanation of the denominator is in the notices', exists (select 1 from jsonb_array_elements(tt.run('wastage_rate','{"preset":"this_month"}'::jsonb)->'notes') n where n->>'text_en' like 'Wastage % = wastage quantity /%'));
select tt.chk('T4 the old wastage report is untouched (same answer as the core engine)', tt.run('wastage','{"preset":"this_month"}'::jsonb) = tt.core('wastage','{"preset":"this_month"}'::jsonb));
reset role; select tt.as(:'x'); set role authenticated;
select tt.chk('T4 outlet 3 person: no cost columns', not exists (select 1 from jsonb_array_elements(tt.run('wastage_rate','{"preset":"this_month"}'::jsonb)->'columns') c where c->>'key' in ('wastage_value','sales_value')));
reset role; select tt.as(:'o'); set role authenticated;

\echo == T5 open to report_stock holders only; nothing behind a setting
reset role; select tt.as(:'k'); set role authenticated;
select tt.err('T5 a storekeeper with no report grant is refused', $q$select tt.run('stock_adjustments')$q$, 'not allowed');
reset role;
select tt.chk('T5 no new rule, no new grant', not exists (select 1 from rules where key in ('transfers_register','stock_adjustments','wastage_rate')) and (select count(*) from grant_defs where grant_code like 'report_%')=13);

\echo == SUMMARY
select 'SUMMARY ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
