-- Phase 422 tests (RPT-B2 R2b: the movement ledger with opening / running / closing and the source document of every row). Database built through phase 422.
-- Run from the repository root:  psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase422_test.sql | grep -E "FAIL|SUMMARY"
\set ON_ERROR_STOP off
\i tests/sql/p420_fixture.sql
reset role;
insert into rule_grants (grant_code, role_code) values ('report_stock','salesperson') on conflict do nothing;
create temp table b0 as select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('stock_movement_ledger','_r4_doc');
\i supabase/phase422.sql
select tt.chk('T0 pasting phase422 twice leaves both functions equal', (select count(*) from b0)=2 and not exists (select 1 from b0 join (select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace) a on a.proname=b0.proname and a.h<>b0.h));
select tt.chk('T0 the document resolver is private, the ledger is not open to anon', not has_function_privilege('authenticated','public._r4_doc(text,text,text,boolean)','execute') and not has_function_privilege('anon','public.stock_movement_ledger(uuid,int,date,date)','execute'));
set role authenticated; select tt.as(:'o');

\echo == T1 sweet at outlet 1: the whole chain in one ledger
select stock_movement_ledger(:'i_sw'::uuid, 1, tt.today()-30, tt.today())::text as lj \gset
create temp table lj0 as select :'lj'::jsonb as j;
select tt.chk('T1 opening 0 (nothing before the period), closing 7.7 = the cached balance, check ok', (select (j->>'opening')::numeric=0 and (j->>'closing')::numeric=7.7 and (j->'check'->>'ok')::boolean and (j->'check'->>'cached')::numeric=7.7 and (j->'check'->>'closing_is_latest')::boolean from lj0));
select tt.chk('T1 stock identity: opening + sum of the rows = closing', (select (j->>'opening')::numeric + (select sum((r->>'qty_delta')::numeric) from jsonb_array_elements(j->'rows') r) = (j->>'closing')::numeric from lj0));
select tt.chk('T1 the running balance is opening + the rows so far, on every row, and the last equals the closing', (select bool_and((r->>'running')::numeric = (j->>'opening')::numeric + (select sum((x->>'qty_delta')::numeric) from jsonb_array_elements(j->'rows') x where (x->>'id')::bigint <= (r->>'id')::bigint)) from lj0, jsonb_array_elements(j->'rows') r)
  and (select (j->'rows'->-1->>'running')::numeric = (j->>'closing')::numeric from lj0));
select tt.chk('T1 every kind of movement of the chain is there: transfer_in, sale_out, sale_void_in, sale_return, wastage x2, count_adjust', (select array_agg(distinct r->>'reason' order by r->>'reason') = array['count_adjust','sale_out','sale_return','sale_void_in','transfer_in','wastage'] from lj0, jsonb_array_elements(j->'rows') r));
select tt.chk('T1 the voided sale appears twice and nets to zero (out 3, back in 3)', (select sum((r->>'qty_delta')::numeric) from lj0, jsonb_array_elements(j->'rows') r where r->'doc'->'detail'->>'receipt'='990002')=0);
select tt.chk('T1 the refund row names the sale it belongs to', (select r->'doc'->>'label' from lj0, jsonb_array_elements(j->'rows') r where r->>'reason'='sale_return')='Refund of sale #990001');
select tt.chk('T1 the receipt row names the transfer from the factory', (select r->'doc'->>'label' like 'Transfer Cake Factory%' from lj0, jsonb_array_elements(j->'rows') r where r->>'reason'='transfer_in'));
select tt.chk('T1 the wastage rows name their reason', (select count(*) from lj0, jsonb_array_elements(j->'rows') r where r->>'reason'='wastage' and r->'doc'->>'label' in ('Wastage · Expired','Wastage · Broken'))=2);
select tt.chk('T1 the count row says who counted and why (note)', (select r->>'who' like 'test_owner%' and r->>'note'='test count' and r->'doc'->>'label'='Count adjust' from lj0, jsonb_array_elements(j->'rows') r where r->>'reason'='count_adjust'));
select tt.chk('T1 sales and refunds carry the batch they took from (the batch of the production) or none', (select count(*) from lj0, jsonb_array_elements(j->'rows') r where r->>'reason'='sale_out' and r->'batch_id' <> 'null'::jsonb)>=1);
select tt.chk('T1 the summary by reason adds up to the closing', (select sum((s->>'net')::numeric) from lj0, jsonb_array_elements(j->'summary') s) = 7.7);
select tt.chk('T1 the owner sees costs: unit cost on the receipt row and the value of the count difference', (select (j->>'cost_shown')::boolean and exists (select 1 from jsonb_array_elements(j->'rows') r where r->>'reason'='transfer_in' and (r->>'unit_cost')::numeric>0)
  and exists (select 1 from jsonb_array_elements(j->'rows') r where r->>'reason'='count_adjust' and (r->>'value')::numeric<0) from lj0));

\echo == T2 the production and the purchase side: raw material at the store, the factory batch
select stock_movement_ledger((select id from items where code='test_raw_flour'), 7, tt.today()-30, tt.today())::text as fj \gset
create temp table fj0 as select :'fj'::jsonb as j;
select tt.chk('T2 flour at the store: opening 100 (entered today = a row of the period, so opening before it is 0), closing 77, ok', (select (j->>'closing')::numeric=77 and (j->'check'->>'ok')::boolean from fj0));
select tt.chk('T2 the draft purchase never touched the ledger; the posted bill, the posted-then-voided bill (with its reversal) and the purchase return are named', (select count(*) from fj0, jsonb_array_elements(j->'rows') r where r->>'reason'='purchase_in')=2
  and exists (select 1 from fj0, jsonb_array_elements(j->'rows') r where r->>'reason'='purchase_return' and r->'doc'->>'label' like 'Purchase return T-R1%')
  and exists (select 1 from fj0, jsonb_array_elements(j->'rows') r where r->>'reason'='purchase_in' and r->'doc'->>'label' = 'Bill T-B1 · test_sup_one')
  and (select count(*) from fj0, jsonb_array_elements(j->'rows') r where r->>'reason'='reversal')=1 and not exists (select 1 from fj0, jsonb_array_elements(j->'rows') r where r->'doc'->>'label' like '%T-B3%'));
select stock_movement_ledger((select id from items where code='test_fg_sweet'), 6, tt.today()-30, tt.today())::text as pj \gset
create temp table pj0 as select :'pj'::jsonb as j;
select tt.chk('T2 the factory: production_in of 50 names the production run, 20+10+5 left by transfer, closing 15', (select (j->>'closing')::numeric=15 from pj0)
  and (select r->'doc'->>'label' like 'Production run %' and (r->>'qty_delta')::numeric=50 from pj0, jsonb_array_elements(j->'rows') r where r->>'reason'='production_in'));
select tt.chk('T2 a direct production entry (cakes) names its batch', (select r->'doc'->>'label' like 'Production batch #%' and (r->>'qty_delta')::numeric=12 from (select stock_movement_ledger((select id from items where code='test_fg_cake'), 6, tt.today()-30, tt.today()) j) z, jsonb_array_elements(j->'rows') r where r->>'reason'='production_in'));
select tt.chk('T2 a transfer in transit left the sender at once (transfer_out 5 with no matching in)', (select count(*) from pj0, jsonb_array_elements(j->'rows') r where r->>'reason'='transfer_out')=3);

\echo == T3 opening and the period window
select stock_movement_ledger((select id from items where code='test_fg_sweet'), 1, tt.today()+1, tt.today()+5)::text as nj \gset
create temp table nj0 as select :'nj'::jsonb as j;
select tt.chk('T3 a period after everything: opening = closing = 7.7, no rows, later_rows 0', (select (j->>'opening')::numeric=7.7 and (j->>'closing')::numeric=7.7 and jsonb_array_length(j->'rows')=0 from nj0));
select stock_movement_ledger((select id from items where code='test_fg_sweet'), 1, tt.today()-30, tt.today()-1)::text as oj \gset
create temp table oj0 as select :'oj'::jsonb as j;
select tt.chk('T3 a period before the movements: no rows, opening 0, and the check says later rows exist (closing is not the latest)', (select (j->>'closing')::numeric=0 and jsonb_array_length(j->'rows')=0 and (j->'check'->>'later_rows')::int>0 and not (j->'check'->>'closing_is_latest')::boolean from oj0));
select tt.err('T3 a range longer than 800 days is refused', format($$select stock_movement_ledger(%L, 1, '2020-01-01', tt.today())$$, :'i_sw'), 'bad_range');
select tt.err('T3 an unknown item is refused', $q$select stock_movement_ledger(gen_random_uuid(), 1)$q$, 'item_not_found');

\echo == T4 a cached balance that does not match the ledger is shown, not hidden
reset role; update stock_balance set qty = qty + 2 where item_id=(select id from items where code='test_fg_sweet') and location_id=1; set role authenticated; select tt.as(:'o');
select tt.chk('T4 check ok = false, ledger total 7.7 against cached 9.7', (select not (j->'check'->>'ok')::boolean and (j->'check'->>'ledger_total_all')::numeric=7.7 and (j->'check'->>'cached')::numeric=9.7 from (select stock_movement_ledger((select id from items where code='test_fg_sweet'), 1, tt.today()-30, tt.today()) j) z));
reset role; update stock_balance set qty = qty - 2 where item_id=(select id from items where code='test_fg_sweet') and location_id=1; set role authenticated; select tt.as(:'o');

\echo == T5 access
reset role; select tt.as(:'x'); set role authenticated;
select tt.err('T5 a person at outlet 3 cannot read the ledger of outlet 1', format($$select stock_movement_ledger(%L, 1)$$, :'i_sw'), 'not allowed for this location');
select tt.chk('T5 the same person reads outlet 3, without cost fields', (select not (j->>'cost_shown')::boolean and not exists (select 1 from jsonb_array_elements(j->'rows') r where r ? 'unit_cost' and r->'unit_cost' <> 'null'::jsonb) and (j->'check'->>'ok')::boolean
  from (select stock_movement_ledger((select id from items where code='test_fg_sweet'), 3) j) z));
select tt.chk('T5 the money of a bill or sale is not in the document detail for a person without the cost right', not exists (select 1 from (select stock_movement_ledger((select id from items where code='test_fg_sweet'), 3) j) z, jsonb_array_elements(j->'rows') r where r->'doc'->'detail' ? 'total'));
reset role; select tt.as(:'k'); set role authenticated;
select tt.err('T5 a storekeeper with no report grant is refused', format($$select stock_movement_ledger(%L, 7)$$, :'i_fl'), 'not allowed');

\echo == T6 a long ledger is cut at the last 1000 rows, the closing stays right
reset role; select tt.as(:'o');
insert into stock_ledger (item_id,location_id,qty_delta,unit_cost,reason,ref_type,made_at,note) select :'i_ck'::uuid, 4, case when g % 2 = 0 then 1 else 2 end, null, 'count_adjust', 'count', now() - (1200 - g) * interval '1 minute', 'test bulk' from generate_series(1, 1100) g;
set role authenticated;
select stock_movement_ledger(:'i_ck'::uuid, 4, tt.today()-3, tt.today()+1)::text as bj \gset
create temp table bj0 as select :'bj'::jsonb as j;
select tt.chk('T6 1100 rows: 1000 shown, truncated, notice present, closing = sum of all 1100 (1650) and the check is ok', (select jsonb_array_length(j->'rows')=1000 and (j->>'truncated')::boolean and (j->>'row_count')::int=1100 and (j->>'closing')::numeric=1650 and (j->'check'->>'ok')::boolean
  and exists (select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='truncated') from bj0));
select tt.chk('T6 the running balance of the first shown row is consistent with the hidden part', (select (j->'rows'->0->>'running')::numeric = (j->>'shown_from_running')::numeric + (j->'rows'->0->>'qty_delta')::numeric from bj0));

\echo == SUMMARY
select 'SUMMARY ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
