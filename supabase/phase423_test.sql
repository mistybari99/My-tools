-- Phase 423 tests (RPT-B2 R3: reconciliation and integrity: negative / mismatch list, period reconciliation, daily closing vs next-day, turnover). Database through phase 423.
-- Run from the repository root:  psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase423_test.sql | grep -E "FAIL|SUMMARY"
\set ON_ERROR_STOP off
\i tests/sql/p420_fixture.sql
reset role;
insert into rule_grants (grant_code, role_code) values ('report_stock','salesperson') on conflict do nothing;
create temp table b0 as select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('_r4_closing_daily','_r3q_stock_integrity','_r4d_stock_integrity','stock_recon_period','_r3q_daily_closing','_r4d_daily_closing','_r3q_item_turnover','_r4d_item_turnover');
\i supabase/phase423.sql
select tt.chk('T0 pasting phase423 twice leaves the 8 functions equal, 3 registry rows, no duplicates', (select count(*) from b0)=8 and not exists (select 1 from b0 join (select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace) a on a.proname=b0.proname and a.h<>b0.h)
  and (select count(*) from report_defs3 where key in ('stock_integrity','daily_closing','item_turnover'))=3);
select tt.chk('T0 private helpers, public recon not open to anon', not has_function_privilege('authenticated','public._r4_closing_daily(date,date,int[],text[],text[])','execute') and not has_function_privilege('anon','public.stock_recon_period(date,date,int,text[])','execute'));
set role authenticated; select tt.as(:'o');

\echo == T1 #72 negative and integrity list
select tt.chk('T1 one finding at the start: the cake sold beyond stock at outlet 1', jsonb_array_length(tt.run('stock_integrity')->'rows')=1
  and (select r->>'issue'='negative' and r->>'item_code'='test_fg_cake' and (r->>'cached_qty')::numeric=-1 and (r->>'short_qty')::numeric=1 and (r->>'unbatched_out_qty')::numeric=1 and (r->>'since')::date=tt.today() from jsonb_array_elements(tt.run('stock_integrity')->'rows') r));
select tt.chk('T1 the balance read by stock_balance says negative for the same line', (select r->>'state' from jsonb_array_elements(tt.run('stock_balance','{"locations":[1]}'::jsonb)->'rows') r where r->>'item_code'='test_fg_cake')='negative');
select tt.chk('T1 the explanation notice is present', exists (select 1 from jsonb_array_elements(tt.run('stock_integrity')->'notes') n where n->>'text_en' like 'Three checks:%'));
reset role;
update stock_balance set qty = qty + 2 where item_id=:'i_fl'::uuid and location_id=7;
update stock_batches set qty_remaining = qty_remaining + 40 where id = (select max(id) from stock_batches where item_id=:'i_sw'::uuid and location_id=6 and qty_remaining > 0);
set role authenticated; select tt.as(:'o');
select tt.chk('T1 a cached balance that differs from the ledger is listed (flour at the store, +2)', (select (r->>'diff')::numeric=2 and (r->>'ledger_qty')::numeric=77 and (r->>'cached_qty')::numeric=79 from jsonb_array_elements(tt.run('stock_integrity')->'rows') r where r->>'issue'='cache_differs'));
select tt.chk('T1 batches that hold more than the balance are listed (sweet at the factory)', (select (r->>'diff')::numeric>0 and r->>'item_code'='test_fg_sweet' from jsonb_array_elements(tt.run('stock_integrity')->'rows') r where r->>'issue'='batches_exceed_balance'));
select tt.chk('T1 three findings now; the raw-material filter keeps only the flour one', jsonb_array_length(tt.run('stock_integrity')->'rows')=3 and jsonb_array_length(tt.run('stock_integrity','{"item_types":["raw_material"]}'::jsonb)->'rows')=1);
select tt.chk('T1 every finding drills to a ledger or a batch list', not exists (select 1 from jsonb_array_elements(tt.run('stock_integrity')->'rows') r where r->>'drill' not like '#/stockrep/ledger?item=%' and r->>'drill' not like '#/batchrep/batches?item=%'));
select tt.chk('T1 a filter that leaves nothing gives the "nothing to report" notice', exists (select 1 from jsonb_array_elements(tt.run('stock_integrity','{"item_types":["packaging"]}'::jsonb)->'notes') n where n->>'text_en' like 'Nothing to report:%'));
reset role;
update stock_balance set qty = qty - 2 where item_id=:'i_fl'::uuid and location_id=7;
update stock_batches set qty_remaining = qty_remaining - 40 where id = (select max(id) from stock_batches where item_id=:'i_sw'::uuid and location_id=6 and qty_remaining > 0);
set role authenticated; select tt.as(:'o');

\echo == T2 #75 period reconciliation: opening + in - out = closing, per item and place
select stock_recon_period(date_trunc('month', tt.today())::date, tt.today())::text as rj \gset
create temp table rj0 as select :'rj'::jsonb as j;
select tt.chk('T2 every row balances: opening + the movements = closing, nothing unclassified, identity diff 0', (select bool_and(abs((r->>'opening')::numeric + (r->>'opening_entry')::numeric + (r->>'purchase_in')::numeric + (r->>'production_in')::numeric + (r->>'transfer_in')::numeric + (r->>'sales_back')::numeric
    + (r->>'sale_out')::numeric + (r->>'issue_out')::numeric + (r->>'wastage')::numeric + (r->>'transfer_out')::numeric + (r->>'purchase_return')::numeric + (r->>'count_adjust')::numeric + (r->>'reversal')::numeric - (r->>'closing')::numeric) < 0.00005
    and (r->>'unclassified')::numeric=0 and (r->>'identity_diff')::numeric=0) from rj0, jsonb_array_elements(j->'rows') r));
select tt.chk('T2 flour at the store: entered 100, bought 948 (60 + 888 later voided), voided -888, returned -2, transferred -80, counted -1, closing 77 = cached 77, ok', (select (r->>'opening_entry')::numeric=100 and (r->>'purchase_in')::numeric=948 and (r->>'reversal')::numeric=-888 and (r->>'purchase_return')::numeric=-2 and (r->>'transfer_out')::numeric=-80
  and (r->>'count_adjust')::numeric=-1 and (r->>'closing')::numeric=77 and (r->>'cached')::numeric=77 and r->>'state'='ok' from rj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_raw_flour' and (r->>'location_id')::int=7));
select tt.chk('T2 sweet at the factory: production 50, transfers out 35, closing 15; 5 kg are in transit', (select (r->>'production_in')::numeric=50 and (r->>'transfer_out')::numeric=-35 and (r->>'closing')::numeric=15 and (r->>'in_transit_out')::numeric=5 from rj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and (r->>'location_id')::int=6));
select tt.chk('T2 sweet at outlet 1: received 20, sold 15 out (12 + the voided 3), back 5 (refund 2 + the void 3), wastage -2, count -0.3, closing 7.7', (select (r->>'transfer_in')::numeric=20 and (r->>'sale_out')::numeric=-15 and (r->>'sales_back')::numeric=5 and (r->>'wastage')::numeric=-2 and (r->>'count_adjust')::numeric=-0.3 and (r->>'closing')::numeric=7.7
  from rj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and (r->>'location_id')::int=1));
select tt.chk('T2 the closing agrees with the movement ledger of the same item and place', (select (j->>'closing')::numeric from (select stock_movement_ledger((select id from items where code='test_fg_sweet'),1,date_trunc('month', tt.today())::date,tt.today()) j) z) = (select (r->>'closing')::numeric from rj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and (r->>'location_id')::int=1));
select tt.chk('T2 the transit list has the 5 kg on the road to AL-CAKIZ', (select jsonb_array_length(j->'transit')=1 and (j->'transit'->0->>'qty')::numeric=5 and j->'transit'->0->>'to_name' like 'AL-CAKIZ%' from rj0));
select tt.chk('T2 the short list has the 2 kg short with its claim and value (cost shown to the owner)', (select jsonb_array_length(j->'short')=1 and (j->'short'->0->>'short_qty')::numeric=2 and j->'short'->0->>'claim'='open' and (j->'short'->0->>'short_value')::numeric>0 from rj0));
select tt.chk('T2 summary: identity holds, cache checked (period ends today), no cache difference, one transit and one short line', (select (j->'summary'->>'identity_holds')::boolean and (j->'summary'->>'cache_checked')::boolean and (j->'summary'->>'cache_differs')::int=0 and (j->'summary'->>'in_transit_lines')::int=1 and (j->'summary'->>'short_lines')::int=1 from rj0));
select tt.chk('T2 a period that starts today replays the opening: sweet at the factory opens at 50', (select (r->>'opening')::numeric=50 and (r->>'production_in')::numeric=0 and (r->>'closing')::numeric=15 from (select stock_recon_period(tt.today(), tt.today()) j) z, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and (r->>'location_id')::int=6));
select tt.chk('T2 a period that ended yesterday: sweet at the factory closes at 50, the later movements are shown, the cache is not judged against it', (select (r->>'closing')::numeric=50 and (r->>'later_qty')::numeric=-35 and r->>'state'='ok' and not (j->'summary'->>'cache_checked')::boolean and jsonb_array_length(j->'transit')=0
  from (select stock_recon_period(tt.today()-3, tt.today()-1) j) z, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and (r->>'location_id')::int=6));
select tt.chk('T2 a place filter keeps one place; the packaging filter keeps the boxes', (select count(distinct (r->>'location_id')) from (select stock_recon_period(tt.today()-3, tt.today(), 7) j) z, jsonb_array_elements(j->'rows') r)=1
  and (select count(*) from (select stock_recon_period(tt.today()-3, tt.today(), null, array['packaging']) j) z, jsonb_array_elements(j->'rows') r where r->>'item_code'<>'test_pack_box')=0);
reset role; update stock_balance set qty = qty + 2 where item_id=:'i_fl'::uuid and location_id=7; set role authenticated; select tt.as(:'o');
select tt.chk('T2 a cached balance that differs from the ledger turns the row to cache_differs with the difference (+2), the identity still holds', (select r->>'state'='cache_differs' and (r->>'cache_diff')::numeric=2 and (j->'summary'->>'cache_differs')::int=1 and (j->'summary'->>'identity_holds')::boolean
  from (select stock_recon_period(date_trunc('month', tt.today())::date, tt.today()) j) z, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_raw_flour' and (r->>'location_id')::int=7));
reset role; update stock_balance set qty = qty - 2 where item_id=:'i_fl'::uuid and location_id=7; set role authenticated; select tt.as(:'o');
select tt.err('T2 end before start refused', $q$select stock_recon_period(tt.today(), tt.today()-1)$q$, 'bad_range');
select tt.err('T2 more than 400 days refused', $q$select stock_recon_period(tt.today()-500, tt.today())$q$, 'bad_range');
select tt.chk('T2 a place that does not exist gives an empty list (the owner is not refused, nothing is invented)', jsonb_array_length(stock_recon_period(tt.today()-1, tt.today(), 999)->'rows')=0);

\echo == T3 #82 closing stock of each day against the next day's sales and loss
reset role;
insert into stock_ledger (item_id,location_id,qty_delta,unit_cost,reason,ref_type,made_at,note) values
 (:'i_te'::uuid,4,10,null,'opening','opening',(tt.today()-3)::timestamp + interval '4 hours','test day -3'),
 (:'i_te'::uuid,4,-4,null,'sale_out','sale',(tt.today()-2)::timestamp + interval '6 hours','test day -2'),
 (:'i_te'::uuid,4,-1,null,'wastage','wastage',(tt.today()-2)::timestamp + interval '9 hours','test day -2');
set role authenticated; select tt.as(:'o');
select tt.run('daily_closing', jsonb_build_object('from', tt.today()-3, 'to', tt.today(), 'locations', jsonb_build_array(4)))::text as dj \gset
create temp table dj0 as select :'dj'::jsonb as j;
select tt.chk('T3 day -3: closing 10, next day sales 4, loss 1 (40 % and 10 % of the closing)', (select (r->>'closing_qty')::numeric=10 and (r->>'next_sales_qty')::numeric=4 and (r->>'next_loss_qty')::numeric=1 and (r->>'sales_pct')::numeric=40 and (r->>'loss_pct')::numeric=10 from dj0, jsonb_array_elements(j->'rows') r where (r->>'day')::date=tt.today()-3));
select tt.chk('T3 day -2: closing 5; the next day really had no sales: 0 (a day that happened), not empty', (select (r->>'closing_qty')::numeric=5 and (r->>'next_sales_qty')::numeric=0 and not (r->'_nc' ? 'next_sales_qty') from dj0, jsonb_array_elements(j->'rows') r where (r->>'day')::date=tt.today()-2));
select tt.chk('T3 today: the next day has not happened, so sales and loss are empty and flagged, never 0', (select r->'next_sales_qty'='null'::jsonb and r->'next_loss_qty'='null'::jsonb and r->'_nc' ? 'next_sales_qty' and r->'sales_pct'='null'::jsonb from dj0, jsonb_array_elements(j->'rows') r where (r->>'day')::date=tt.today()));
select tt.chk('T3 the value of the closing is empty for a never-costed item (flagged), no estimate', (select r->'closing_value'='null'::jsonb and r->'_nc' ? 'closing_value' from dj0, jsonb_array_elements(j->'rows') r where (r->>'day')::date=tt.today()-3));
select tt.chk('T3 days with no stock and no next-day movement are not listed (4 days)', (select count(*) from dj0, jsonb_array_elements(j->'rows') r)=4);
select tt.chk('T3 the rows of a costed item show the value: sweet at the factory, closing 50 x average', (select (r->>'closing_value')::numeric>2000 and (r->>'closing_qty')::numeric=50 from (select tt.run('daily_closing', jsonb_build_object('from', tt.today()-2, 'to', tt.today(), 'locations', jsonb_build_array(6), 'item_types', jsonb_build_array('finished_good'))) j) z, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and (r->>'day')::date=tt.today()-1));
select tt.chk('T3 every row drills to the ledger of that day', not exists (select 1 from dj0, jsonb_array_elements(j->'rows') r where r->>'drill' not like '#/stockrep/ledger?item=%&loc=4&from=%&to=%'));

\echo == T4 #73 turnover and days on hand
select tt.run('item_turnover', jsonb_build_object('from', tt.today()-3, 'to', tt.today(), 'locations', jsonb_build_array(4)))::text as tj \gset
create temp table tj0 as select :'tj'::jsonb as j;
select tt.chk('T4 tea at AL-CAKIZ over 4 days: used 4, average stock (10+5+5+5)/4 = 6.25, turnover 0.64, days on hand 6.3, on hand 5, cover now 5.0', (select (r->>'used_qty')::numeric=4 and (r->>'sold_qty')::numeric=4 and (r->>'avg_stock_qty')::numeric=6.25 and (r->>'turnover')::numeric=0.64 and (r->>'days_on_hand')::numeric=6.3 and (r->>'on_hand_qty')::numeric=5 and (r->>'cover_days_now')::numeric=5
  from tj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_rs_tea'));
select tt.run('item_turnover', jsonb_build_object('from', date_trunc('month', tt.today())::date, 'to', tt.today(), 'locations', jsonb_build_array(7)))::text as t2j \gset
create temp table t2j0 as select :'t2j'::jsonb as j;
select tt.chk('T4 flour at the store alone: nothing sold or issued there, so turnover and days are empty and flagged (not 0, no division by zero)', (select r->'turnover'='null'::jsonb and r->'days_on_hand'='null'::jsonb and r->'_nc' ? 'turnover' and (r->>'used_qty')::numeric=0 from t2j0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_raw_flour'));
select tt.run('item_turnover', jsonb_build_object('from', date_trunc('month', tt.today())::date, 'to', tt.today()))::text as t3j \gset
create temp table t3j0 as select :'t3j'::jsonb as j;
select tt.chk('T4 all places: flour is issued to production (30 kg), so turnover = used / average stock and days on hand = average x days / used', (select (r->>'issued_qty')::numeric=30 and abs((r->>'turnover')::numeric - 30 / (r->>'avg_stock_qty')::numeric) < 0.001
  and abs((r->>'days_on_hand')::numeric - ((r->>'avg_stock_qty')::numeric * (extract(day from tt.today())::int) / 30)) < 0.06 from t3j0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_raw_flour'));
select tt.chk('T4 the explanation of the formula is in the notices', exists (select 1 from jsonb_array_elements(tt.run('item_turnover')->'notes') n where n->>'text_en' like 'Used = sold%'));

\echo == T5 access
reset role; select tt.as(:'x'); set role authenticated;
select tt.err('T5 a person at outlet 3 cannot reconcile outlet 1', $q$select stock_recon_period(tt.today()-1, tt.today(), 1)$q$, 'not allowed for this location');
select tt.chk('T5 the same person reconciles outlet 3 (the 8 kg received short) and sees no short value', (select jsonb_array_length(j->'rows')=1 and (j->'rows'->0->>'closing')::numeric=8 and j->'short'->0->'short_value' = 'null'::jsonb and not (j->>'cost_shown')::boolean from (select stock_recon_period(tt.today()-1, tt.today(), 3) j) z));
select tt.chk('T5 the three new viewer reports open with report_stock and show only own places', (select count(*) from jsonb_array_elements(report_catalog2()) e where e->>'key' in ('stock_integrity','daily_closing','item_turnover') and (e->>'allowed')::boolean)=3
  and jsonb_array_length(tt.run('stock_integrity')->'rows')=0);
reset role; select tt.as(:'k'); set role authenticated;
select tt.err('T5 a storekeeper with no report grant is refused (recon)', $q$select stock_recon_period(tt.today()-1, tt.today())$q$, 'not allowed');
select tt.err('T5 and for the viewer reports', $q$select tt.run('daily_closing')$q$, 'not allowed');
reset role;
select tt.chk('T5 no setting was added', not exists (select 1 from rules where key in ('stock_integrity','item_turnover','daily_closing','stock_recon_period')));

\echo == SUMMARY
select 'SUMMARY ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
