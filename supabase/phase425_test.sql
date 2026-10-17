-- Phase 425 tests (RPT-B2 R4b: unsold by production batch, distribution by outlet and batch, expired / damaged / unsold, batch trace). Database through phase 425.
-- Run from the repository root:  psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase425_test.sql | grep -E "FAIL|SUMMARY"
\set ON_ERROR_STOP off
\i tests/sql/p420_fixture.sql
reset role;
insert into rule_grants (grant_code, role_code) values ('report_stock','salesperson') on conflict do nothing;
create temp table b0 as select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('_r4_fg_batch_agg','unsold_by_batch','fg_distribution','expired_damaged_unsold','fg_batch_rows');
\i supabase/phase425.sql
select tt.chk('T0 pasting phase425 twice leaves the 5 functions equal and the reason list has one "unsold"', (select count(*) from b0)=5 and not exists (select 1 from b0 join (select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace) a on a.proname=b0.proname and a.h<>b0.h)
  and (select count(*) from option_lists where list_code='wastage_reasons' and value_code='unsold')=1);
select tt.chk('T0 the old wastage reasons are untouched', (select count(*) from option_lists where list_code='wastage_reasons' and value_code in ('expired','spoiled','burnt','broken','sample','staff_meal','unknown'))=7);
select tt.chk('T0 the functions are not open to anon; the aggregate helper is private', not has_function_privilege('anon','public.unsold_by_batch(date,date,int,text[],boolean)','execute') and not has_function_privilege('anon','public.fg_distribution(date,date,int,text[])','execute')
  and not has_function_privilege('anon','public.expired_damaged_unsold(date,date,int)','execute') and not has_function_privilege('anon','public.fg_batch_rows(bigint)','execute') and not has_function_privilege('authenticated','public._r4_fg_batch_agg()','execute'));
set role authenticated; select tt.as(:'o');
select stock_wastage((select id from items where code='test_fg_sweet'), 3, 1, 'unsold', 'test unsold at the end of the day') is not null as wu \gset

\echo == T1 #80 unsold by production batch
select unsold_by_batch(tt.today()-30, tt.today())::text as uj \gset
create temp table uj0 as select :'uj'::jsonb as j;
select tt.chk('T1 two production batches (sweet 50 kg, cake 12 pcs)', (select jsonb_array_length(j->'rows')=2 from uj0));
select tt.chk('T1 sweet: made 50 = sold 10 + wasted 3 (2 + the unsold 1) + other 0.3 + short 2 + on the road 5 + in stock 29.7; nothing unaccounted', (select (r->>'made_qty')::numeric=50 and (r->>'sold_qty')::numeric=10 and (r->>'wasted_qty')::numeric=3 and (r->>'other_qty')::numeric=0.3 and (r->>'short_qty')::numeric=2
  and (r->>'in_transit_qty')::numeric=5 and (r->>'remaining_qty')::numeric=29.7 and (r->>'unaccounted_qty')::numeric=0 from uj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet'));
select tt.chk('T1 sweet: unsold = in stock + on the road = 34.7 (69.4 % of the batch)', (select (r->>'unsold_qty')::numeric=34.7 and (r->>'unsold_pct')::numeric=69.4 from uj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet'));
select tt.chk('T1 cake: made 12 = sold 8 + wasted 1 + in stock 3; the 9th cake sold beyond stock is not in the batch', (select (r->>'made_qty')::numeric=12 and (r->>'sold_qty')::numeric=8 and (r->>'wasted_qty')::numeric=1 and (r->>'remaining_qty')::numeric=3 and (r->>'unaccounted_qty')::numeric=0 from uj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_cake'));
select tt.chk('T1 the sweet cost per unit is the recorded production cost and the unsold value = unsold x cost', (select (r->>'unit_cost')::numeric>0 and abs((r->>'unsold_value')::numeric - (r->>'unsold_qty')::numeric * (r->>'unit_cost')::numeric) < 0.02 from uj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet'));
select tt.chk('T1 the cake (production entered with no cost): cost and value empty and flagged, never 0', (select r->'unit_cost'='null'::jsonb and r->'unsold_value'='null'::jsonb and r->'_nc' ? 'unsold_value' from uj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_cake'));
select tt.chk('T1 the sweet expires within the 7 day threshold: soon; the cake has no expiry: no_expiry, flagged', (select r->>'state'='soon' from uj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet')
  and (select r->>'state'='no_expiry' and r->'_nc' ? 'expires_on' from uj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_cake'));
select tt.chk('T1 the notices explain the parts, the no-expiry batches, and there is no "does not add up" warning', exists (select 1 from uj0, jsonb_array_elements(j->'notes') n where n->>'text_en' like 'Per production batch:%') and exists (select 1 from uj0, jsonb_array_elements(j->'notes') n where n->>'what'='shelf_life_rules')
  and not exists (select 1 from uj0, jsonb_array_elements(j->'notes') n where n->>'what'='stock_batches.qty_remaining'));
select tt.chk('T1 a place filter on the production place keeps both; on an outlet nothing (outlets do not make batches)', jsonb_array_length(unsold_by_batch(tt.today()-30, tt.today(), 6)->'rows')=2 and jsonb_array_length(unsold_by_batch(tt.today()-30, tt.today(), 1)->'rows')=0);
select tt.chk('T1 the item type filter: finished goods keeps both, packaging none', jsonb_array_length(unsold_by_batch(tt.today()-30, tt.today(), null, array['finished_good'])->'rows')=2 and jsonb_array_length(unsold_by_batch(tt.today()-30, tt.today(), null, array['packaging'])->'rows')=0);
select tt.chk('T1 the made date window is respected: a window before the production lists nothing', jsonb_array_length(unsold_by_batch(tt.today()-30, tt.today()-5)->'rows')=0);
reset role; update stock_batches set qty_remaining = qty_remaining + 3 where id = (select max(id) from stock_batches where item_id=(select id from items where code='test_fg_sweet') and location_id=6 and qty_remaining>0); set role authenticated; select tt.as(:'o');
select tt.chk('T1 a batch row that breaks the identity is shown with the difference (-3) and a warning', (select (r->>'unaccounted_qty')::numeric=-3 from (select unsold_by_batch(tt.today()-30, tt.today()) j) z, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet')
  and exists (select 1 from (select unsold_by_batch(tt.today()-30, tt.today()) j) z, jsonb_array_elements(j->'notes') n where n->>'what'='stock_batches.qty_remaining'));
reset role; update stock_batches set qty_remaining = qty_remaining - 3 where id = (select max(id) from stock_batches where item_id=(select id from items where code='test_fg_sweet') and location_id=6 and qty_remaining>0); set role authenticated; select tt.as(:'o');
select tt.err('T1 range over 800 days refused', $q$select unsold_by_batch('2020-01-01', tt.today())$q$, 'bad_range');

\echo == T2 #84 distribution by outlet and batch
select fg_distribution(tt.today()-30, tt.today())::text as dj \gset
create temp table dj0 as select :'dj'::jsonb as j;
select tt.chk('T2 sweet at the factory: made here 50, sent on 35, holds 15', (select (r->>'received_qty')::numeric=50 and (r->>'sent_on_qty')::numeric=35 and (r->>'remaining_qty')::numeric=15 and r->>'role'='made_here' from dj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and r->>'location_en' like 'Cake Factory%'));
select tt.chk('T2 sweet at outlet 1: received 20, sold 10 (50 %), wasted 2, count 0.3, holds 7.7', (select (r->>'received_qty')::numeric=20 and (r->>'sold_qty')::numeric=10 and (r->>'sold_pct')::numeric=50 and (r->>'wasted_qty')::numeric=2 and (r->>'other_qty')::numeric=0.3 and (r->>'remaining_qty')::numeric=7.7
  from dj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and r->>'location_en' like 'ISLAMIYA MISTY GHAR — Main%'));
select tt.chk('T2 sweet at MISTY BARI: received 8 of the 10 sent (2 short), the unsold 1 written off, holds 7', (select (r->>'received_qty')::numeric=8 and (r->>'short_qty')::numeric=2 and (r->>'wasted_qty')::numeric=1 and (r->>'remaining_qty')::numeric=7
  from dj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and r->>'location_en' like 'MISTY BARI%'));
select tt.chk('T2 sweet at AL-CAKIZ: nothing received yet, 5 on the road', (select (r->>'received_qty')::numeric=0 and (r->>'on_road_qty')::numeric=5 from dj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and r->>'location_en' like 'AL-CAKIZ%'));
select tt.chk('T2 the batch family adds up across places: received (incl. made here) - sent on = held + sold + wasted + other; the short and the road part are the sent-but-not-received difference', (select abs(sum((r->>'received_qty')::numeric) - sum((r->>'sent_on_qty')::numeric) - (sum((r->>'remaining_qty')::numeric) + sum((r->>'sold_qty')::numeric) + sum((r->>'wasted_qty')::numeric) + sum((r->>'other_qty')::numeric))) < 0.0005
  from dj0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_sweet' and r->>'role'<>'no_batch'));
select tt.chk('T2 the cake sold beyond stock is a line of its own: no batch, 1 piece, batch fields empty and flagged', (select (r->>'sold_qty')::numeric=1 and r->'batch_id'='null'::jsonb and r->'_nc' ? 'batch_id' from dj0, jsonb_array_elements(j->'rows') r where r->>'role'='no_batch' and r->>'item_code'='test_fg_cake'));
select tt.chk('T2 a notice says that sales with no batch cannot be traced', exists (select 1 from dj0, jsonb_array_elements(j->'notes') n where n->>'what'='stock_ledger.batch_id'));
select tt.chk('T2 filter by outlet 1 keeps only outlet 1 rows (sweet, cake and the no-batch line)', (select count(distinct r->>'location_en') from (select fg_distribution(tt.today()-30, tt.today(), 1) j) z, jsonb_array_elements(j->'rows') r)=1);
reset role; select tt.as(:'x'); set role authenticated;
select tt.chk('T2 the person at outlet 3 sees only outlet 3: the sweet batch, received 8', (select count(*)=1 and (min((r->>'received_qty')::numeric))=8 from (select fg_distribution(tt.today()-30, tt.today()) j) z, jsonb_array_elements(j->'rows') r));
select tt.err('T2 and cannot ask for outlet 1', $q$select fg_distribution(tt.today()-30, tt.today(), 1)$q$, 'not allowed for this location');
reset role; select tt.as(:'o'); set role authenticated;

\echo == T3 #79 expired, damaged, unsold
select expired_damaged_unsold(tt.today()-30, tt.today())::text as ej \gset
create temp table ej0 as select :'ej'::jsonb as j;
select tt.chk('T3 the classes: expired 2 (sweet 1.5, cake 1), unsold 1, damaged 2 (broken 0.5 + the damaged customer return)', (select count(*) filter (where r->>'class'='expired')=2 and count(*) filter (where r->>'class'='unsold')=1 and count(*) filter (where r->>'class'='damaged')=2 from ej0, jsonb_array_elements(j->'rows') r));
select tt.chk('T3 the section by class agrees', (select (s->>'entries')::int from ej0, jsonb_array_elements(j->'sections'->0->'rows') s where s->>'class'='unsold')=1 and (select (s->>'entries')::int from ej0, jsonb_array_elements(j->'sections'->0->'rows') s where s->>'class'='expired')=2);
select tt.chk('T3 the unsold write-off names its batch family and the age of the batch when it was lost (batch made 2 days ago)', (select r->'batch_id' <> 'null'::jsonb and (r->>'batch_age_days')::int=2 from ej0, jsonb_array_elements(j->'rows') r where r->>'class'='unsold'));
select tt.chk('T3 value = qty x ledger cost; the cake wastage has no cost: value empty and flagged', (select (r->>'value')::numeric>0 from ej0, jsonb_array_elements(j->'rows') r where r->>'class'='unsold')
  and (select r->'value'='null'::jsonb and r->'_nc' ? 'value' from ej0, jsonb_array_elements(j->'rows') r where r->>'item_code'='test_fg_cake' and r->>'class'='expired'));
select tt.chk('T3 the damaged customer return went back into sellable stock (no class rules are set) and the notice says so', (select r->>'back_in_stock'='true' from ej0, jsonb_array_elements(j->'rows') r where r->>'source'='customer return')
  and exists (select 1 from ej0, jsonb_array_elements(j->'notes') n where n->>'what'='w1c_return_class_rules' and n->>'text_en' like '1 of 1 damaged customer return(s) went BACK%'));
select tt.chk('T3 the other reasons are named as not in this list (none in this data: 0 entries)', exists (select 1 from ej0, jsonb_array_elements(j->'notes') n where n->>'text_en' like 'Classes: expired = wastage reason Expired%0 entries%'));
select tt.chk('T3 with an Unsold entry present, the "no unsold entries" notice is gone', not exists (select 1 from ej0, jsonb_array_elements(j->'notes') n where n->>'text_en' like 'No entry with the reason Unsold%'));
select tt.chk('T3 a window with no unsold entries gets the helpful notice', exists (select 1 from (select expired_damaged_unsold(tt.today()-30, tt.today()-5) j) z, jsonb_array_elements(j->'notes') n where n->>'text_en' like 'No entry with the reason Unsold%'));
select tt.chk('T3 every row drills to a batch trace or to a ledger', not exists (select 1 from ej0, jsonb_array_elements(j->'rows') r where r->>'drill' not like '#/batchrep/trace?batch=%' and r->>'drill' not like '#/stockrep/ledger?item=%'));
reset role; select tt.as(:'x'); set role authenticated;
select tt.chk('T3 outlet 3 person: only own place (the unsold entry), no cost columns', (select count(*)=1 from (select expired_damaged_unsold(tt.today()-30, tt.today()) j) z, jsonb_array_elements(j->'rows') r) and not exists (select 1 from (select expired_damaged_unsold(tt.today()-30, tt.today()) j) z, jsonb_array_elements(j->'columns') c where c->>'key'='value'));
reset role; select tt.as(:'o'); set role authenticated;

\echo == T4 the trace of one production batch
select (select batch_id from production_runs limit 1) as rb \gset
select fg_batch_rows(:rb::bigint)::text as tj \gset
create temp table tj0 as select :'tj'::jsonb as j;
select tt.chk('T4 the family: the root and its three children (outlet 1, outlet 3), the numbers equal the unsold report', (select jsonb_array_length(j->'family')=3 and (j->'summary'->>'made_qty')::numeric=50 and (j->'summary'->>'remaining_qty')::numeric=29.7 and (j->'summary'->>'unaccounted_qty')::numeric=0 from tj0));
select tt.chk('T4 the rows are the ledger rows of the whole family, each with its document: production, transfers, sales, refund, wastage, count', (select array_agg(distinct r->>'reason' order by r->>'reason') @> array['count_adjust','production_in','sale_out','sale_return','sale_void_in','transfer_in','transfer_out','wastage'] from tj0, jsonb_array_elements(j->'rows') r)
  and not exists (select 1 from tj0, jsonb_array_elements(j->'rows') r where r->'doc'->>'label' is null));
select tt.chk('T4 asking with a child batch id gives the same family (the root)', (select (j->>'batch_id')::bigint = :rb::bigint from (select fg_batch_rows(tt.n(format('select max(batch) from _r4_lineage() where root=%s and batch<>root', :rb))::bigint) j) z));
reset role; select tt.as(:'x'); set role authenticated;
select tt.chk('T4 the person at outlet 3 can open the batch that reached outlet 3 and sees only own rows (the receipt)', (select jsonb_array_length(j->'family')=1 and (select count(*) from jsonb_array_elements(j->'rows') r where r->>'location' not like 'MISTY BARI%')=0 from (select fg_batch_rows(:rb::bigint) j) z));
reset role; select tt.as(:'k'); set role authenticated;
select tt.err('T4 no report grant, no trace', format($$select fg_batch_rows(%s)$$, :rb), 'not allowed');
reset role; select tt.as(:'o'); set role authenticated;
select tt.err('T4 a batch that does not exist', $q$select fg_batch_rows(999999)$q$, 'batch_not_found');

\echo == SUMMARY
select 'SUMMARY ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
