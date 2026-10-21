-- Phase 420 tests (RPT-B2 R1, honesty fixes). Needs a database built through phase99 with phase420 pasted once (the test pastes it a second time).
-- Run from the repository root:  psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase420_test.sql | grep -E "FAIL|SUMMARY"
-- Neutral test_* data only (tests/sql/p420_fixture.sql: opening, purchase, production, transfer, sale, wastage, refund, count, closing).
\set ON_ERROR_STOP off
\i tests/sql/p420_fixture.sql
\set kk '00000000-0000-0000-0000-000000000003'
reset role;

\echo == T0 fixture sanity and the stock identity (opening + in - out = closing) per item and place
select tt.chk('T0 ledger sum = cached balance on every pair', not exists (select 1 from stock_balance b where b.qty <> coalesce((select sum(qty_delta) from stock_ledger l where l.item_id=b.item_id and l.location_id=b.location_id),0)));
select tt.chk('T0 stock_reconcile finds nothing', (select count(*) from (select * from stock_reconcile()) z)=0) from (select tt.as(:'o')) a;
select tt.chk('T0 draft + voided purchases entered no stock (flour store: 100 + 60 - 2 - 80 - 1 count = 77)', (select qty from stock_balance where item_id=:'i_fl'::uuid and location_id=7)=77);
select tt.chk('T0 the oversold cake is negative (-1) at outlet 1', (select qty from stock_balance where item_id=:'i_ck'::uuid and location_id=1)=-1);
select tt.chk('T0 a voided sale nets to zero, the refund added stock back (sweet outlet 1: 20 - 12 - 3 + 3 + 2 - 2 = 8, counted 7.7)', (select qty from stock_balance where item_id=:'i_sw'::uuid and location_id=1)=7.7);

\echo == T1 plumbing: pasted twice, one catalogue entry per key, other keys untouched
create temp table b0 as select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('report_run2','report_catalog2','_r3q_stock_balance','_r3q_expiry_soon','_r3q_p4_supplier_score','_r4d_stock_balance','_r4d_expiry_soon','_r4d_p4_supplier_score','_r4d_supplier_ageing','stock_reconcile','stock_reconcile_fix','wastage_by_reason2','log_report_export4','supplier_credit_gaps');
\i supabase/phase420.sql
select tt.chk('T1 pasting phase420 twice leaves every function byte for byte equal', (select count(*) from b0)=14 and not exists (select 1 from b0 join (select p.proname, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace='public'::regnamespace) a on a.proname=b0.proname and a.h<>b0.h));
select tt.chk('T1 report_defs3 rows are not duplicated', (select count(*) from report_defs3 where key in ('stock_balance','expiry_soon','p4_supplier_score'))=3);
set role authenticated; select tt.as(:'o');
select tt.chk('T1 the catalogue has stock_balance and expiry_soon once each', (select count(*) from jsonb_array_elements(report_catalog2()) e where e->>'key'='stock_balance')=1 and (select count(*) from jsonb_array_elements(report_catalog2()) e where e->>'key'='expiry_soon')=1);
select tt.chk('T1 the item_types filter is offered by stock_balance', (select e->'filters' ? 'item_types' from jsonb_array_elements(report_catalog2()) e where e->>'key'='stock_balance'));
select tt.chk('T1 stock_low and wastage still come from the old engine unchanged (no decorator)', report_run2('stock_low','{}'::jsonb) = tt.core('stock_low','{}'::jsonb) and report_run2('wastage','{"preset":"this_month"}'::jsonb) = tt.core('wastage','{"preset":"this_month"}'::jsonb));
select tt.chk('T1 decorators and engine-3 query functions are private', not has_function_privilege('authenticated','public._r4d_stock_balance(jsonb,jsonb)','execute') and not has_function_privilege('authenticated','public._r3q_expiry_soon(date,date,int[],jsonb)','execute')
  and not has_function_privilege('anon','public.report_run2(text,jsonb,text,text,int)','execute') and not has_function_privilege('anon','public.stock_reconcile_fix(text)','execute'));

\echo == T2 access: the report stays open to report_stock holders only, scoped to their places
reset role; select tt.as(:'x'); set role authenticated;
select tt.err('T2 no grant -> not allowed', $q$select tt.run('stock_balance')$q$, 'not allowed');
reset role;
insert into rule_grants (grant_code, role_code) values ('report_stock','salesperson'),('report_purchase','salesperson') on conflict do nothing;
set role authenticated; select tt.as(:'x');
select tt.chk('T2 report_stock opens stock_balance for the salesperson, own place only (outlet 3)', (select count(*) from jsonb_array_elements(tt.run('stock_balance')->'rows') r where r->>'location_en' not like '%MISTY BARI%')=0 and jsonb_array_length(tt.run('stock_balance')->'rows')>0);
select tt.chk('T2 without the cost right: no cost column, no value total, cost_hidden notice', not exists (select 1 from jsonb_array_elements(tt.run('stock_balance')->'columns') c where c->>'key' in ('avg_cost','value','cost_note'))
  and not (tt.run('stock_balance')->'totals' ? 'value') and exists (select 1 from jsonb_array_elements(tt.run('stock_balance')->'notes') n where n->>'code'='cost_hidden'));
select tt.chk('T2 expiry_soon opens with report_stock as well', jsonb_typeof(tt.run('expiry_soon')->'rows')='array');
select tt.err('T2 purchase reports with a cost right stay closed to a person without it (p4)', $q$select tt.run('p4_supplier_score')$q$, 'not allowed');
reset role; select tt.as(:'o'); set role authenticated;

\echo == T3 #57 #60-62 stock_balance: states, item type filter, uncosted count, sub-totals
select tt.chk('T3 same lines as the old report for the same filters (only the state of a negative line differs)',
  (select count(*) from jsonb_array_elements(tt.run('stock_balance')->'rows') r) = least(50,tt.n('select count(*) from stock_balance b join items i on i.id=b.item_id where i.is_active'))
  and (select (tt.run('stock_balance')->'page'->>'groups')::int) = tt.n('select count(*) from stock_balance b join items i on i.id=b.item_id where i.is_active'));
select tt.chk('T3 old figures are the same: qty and value of every line equal the old engine', not exists (
  select 1 from jsonb_array_elements(tt.core('stock_balance','{"locations":[1,6,7]}'::jsonb)->'rows') o
  join jsonb_array_elements(tt.run('stock_balance','{"locations":[1,6,7]}'::jsonb)->'rows') n on n->>'item_code'=o->>'item_code' and n->>'location_en'=o->>'location_en'
  where (n->>'qty')::numeric <> (o->>'qty')::numeric or (n->>'value') is distinct from (o->>'value')));
select tt.chk('T3 a negative balance reads negative (the old report said low or ok): cake at outlet 1', (select r->>'state' from jsonb_array_elements(tt.run('stock_balance','{"locations":[1]}'::jsonb)->'rows') r where r->>'item_code'='test_fg_cake')='negative'
  and (select o->>'state' from jsonb_array_elements(tt.core('stock_balance','{"locations":[1]}'::jsonb)->'rows') o where o->>'item_code'='test_fg_cake') in ('low','ok'));
select tt.chk('T3 raw material filter: only raw lines (flour x2, sugar x2, salt)', (select count(*) from jsonb_array_elements(tt.run('stock_balance','{"item_types":["raw_material"]}'::jsonb)->'rows') r)=5
  and not exists (select 1 from jsonb_array_elements(tt.run('stock_balance','{"item_types":["raw_material"]}'::jsonb)->'rows') r where r->>'item_code' not like 'test_raw_%'));
select tt.chk('T3 packaging filter: the box at the store and the factory', (select count(*) from jsonb_array_elements(tt.run('stock_balance','{"item_types":["packaging"]}'::jsonb)->'rows') r where r->>'item_code'='test_pack_box')=2
  and (select count(*) from jsonb_array_elements(tt.run('stock_balance','{"item_types":["packaging"]}'::jsonb)->'rows') r)>=2);
select tt.chk('T3 finished good + resale together', (select count(distinct r->>'item_code') from jsonb_array_elements(tt.run('stock_balance','{"item_types":["finished_good","resale"],"locations":[1,3,6]}'::jsonb)->'rows') r)=3);
select tt.chk('T3 a type code that does not exist lists nothing (it is not ignored)', jsonb_array_length(tt.run('stock_balance','{"item_types":["nope"]}'::jsonb)->'rows')=0);
select tt.chk('T3 the salt (opened with no cost) says "no cost recorded", value empty, flagged not captured', (select r->>'cost_note' = 'no cost recorded' and r->'value' = 'null'::jsonb and r->'_nc' ? 'value' from jsonb_array_elements(tt.run('stock_balance','{"item_types":["raw_material"]}'::jsonb)->'rows') r where r->>'item_code'='test_raw_salt'));
select tt.chk('T3 notice with the uncosted count (data_needed) on the raw filter = 1 line', exists (select 1 from jsonb_array_elements(tt.run('stock_balance','{"item_types":["raw_material"]}'::jsonb)->'notes') n where n->>'code'='data_needed' and n->>'text_en' like '1 stock line(s)%'));
select tt.chk('T3 the value total = qty x avg of the costed lines only (salt left out, not counted as 0 cost)', (tt.run('stock_balance','{"item_types":["raw_material"]}'::jsonb)->'totals'->>'value')::numeric
  = tt.n('select round(sum(round(b.qty*b.avg_cost,2)),2) from stock_balance b join items i on i.id=b.item_id where i.item_type=''raw_material'' and b.avg_cost is not null and i.is_active'));
select tt.chk('T3 sub-totals per place add up to the total', (select round(sum((r->>'value')::numeric),2) from jsonb_array_elements(tt.run('stock_balance')->'subtotals'->0->'rows') r) = (tt.run('stock_balance')->'totals'->>'value')::numeric);
select tt.chk('T3 sub-totals per kind: factory + godown + showroom, sum equals the total', (select round(sum((r->>'value')::numeric),2) from jsonb_array_elements(tt.run('stock_balance')->'subtotals'->1->'rows') r) = (tt.run('stock_balance')->'totals'->>'value')::numeric
  and (select count(*) from jsonb_array_elements(tt.run('stock_balance')->'subtotals'->1->'rows') r where r->>'name' in ('factory','godown','showroom'))>=3);
select tt.chk('T3 sub-totals per item type add up and name the types', (select round(sum((r->>'value')::numeric),2) from jsonb_array_elements(tt.run('stock_balance')->'subtotals'->2->'rows') r) = (tt.run('stock_balance')->'totals'->>'value')::numeric
  and exists (select 1 from jsonb_array_elements(tt.run('stock_balance')->'subtotals'->2->'rows') r where r->>'name_en'='Raw material'));
select tt.chk('T3 the uncosted count is in the sub-total rows too', (select sum((r->>'uncosted_lines')::int) from jsonb_array_elements(tt.run('stock_balance')->'subtotals'->0->'rows') r) = tt.n('select count(*) from stock_balance b join items i on i.id=b.item_id where i.is_active and b.qty<>0 and b.avg_cost is null'));
select tt.chk('T3 negative notice present and every line has a drill link to its ledger', exists (select 1 from jsonb_array_elements(tt.run('stock_balance')->'notes') n where n->>'text_en' like '%NEGATIVE%')
  and not exists (select 1 from jsonb_array_elements(tt.run('stock_balance')->'rows') r where r->>'drill' not like '#/stockrep/ledger?item=%&loc=%'));

\echo == T4 #69 expiry: one threshold, the no-expiry row, expired batches
select tt.chk('T4 the old report listed nothing soon (no report_expiry_soon_days): the sweet batch at outlet 1 expires in about a day', jsonb_array_length(tt.core('expiry_soon','{}'::jsonb)->'rows')=0);
select tt.chk('T4 the new list shows the soon batches (threshold = expiry_warn_days 7)', (select count(*) from jsonb_array_elements(tt.run('expiry_soon')->'rows') r where r->>'state'='soon' and r->>'item_code'='test_fg_sweet')>=1);
select tt.chk('T4 notice names the rule that gave the threshold', exists (select 1 from jsonb_array_elements(tt.run('expiry_soon')->'notes') n where n->>'text_en' like '%7 day%expiry_warn_days%'));
select tt.chk('T4 batches with no expiry get one row per item and place: the cakes (factory 4 left, outlet 1 had 8, sold 8 + 1 beyond)', exists (
  select 1 from jsonb_array_elements(tt.run('expiry_soon')->'rows') r where r->>'state'='no_expiry' and r->>'item_code'='test_fg_cake' and r->'expires_on'='null'::jsonb and r->'days_left'='null'::jsonb and (r->>'qty')::numeric>0));
select tt.chk('T4 no-expiry rows are flagged not captured (never days_left 0)', not exists (select 1 from jsonb_array_elements(tt.run('expiry_soon')->'rows') r where r->>'state'='no_expiry' and r->>'days_left' is not null));
select tt.chk('T4 a notice counts the batches with no expiry date and names the field', exists (select 1 from jsonb_array_elements(tt.run('expiry_soon')->'notes') n where n->>'code'='data_needed' and n->>'what'='shelf_life_rules / expires_at'));
reset role; update stock_batches set expires_at = now() - interval '2 days' where id = (select min(id) from stock_batches where item_id=:'i_sw'::uuid and location_id=6 and qty_remaining>0); set role authenticated; select tt.as(:'o');
select tt.chk('T4 an expired batch is listed as expired with negative days left', exists (select 1 from jsonb_array_elements(tt.run('expiry_soon')->'rows') r where r->>'state'='expired' and (r->>'days_left')::int<0));
select set_rule('report_expiry_soon_days','2') is null as sr \gset
select tt.chk('T4 report_expiry_soon_days wins when it is set, and the notice says so', exists (select 1 from jsonb_array_elements(tt.run('expiry_soon')->'notes') n where n->>'text_en' like '%2 day%report_expiry_soon_days%'));
select set_rule('report_expiry_soon_days',null) is null as sr2 \gset

\echo == T5 #94 supplier scorecard
select tt.chk('T5 test_sup_one: 1 posted bill of 3740, 1 return of 84 (2.2 %), draft and voided bills not counted', (select (r->>'bills_n')::int=1 and (r->>'bills_total')::numeric=3740 and (r->>'returns_n')::int=1 and (r->>'returns_total')::numeric=84 and (r->>'return_pct')::numeric=2.2
  from jsonb_array_elements(tt.run('p4_supplier_score','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'supplier'='test_sup_one'));
select tt.chk('T5 never-captured legs are empty, not 0, and flagged (GRN 04-1, bill check 06-4, PO 06-3, QC)', (select r->'grns'='null'::jsonb and r->'bills_checked'='null'::jsonb and r->'pos'='null'::jsonb and r->'qc_n'='null'::jsonb and r->'_nc' ? 'grns' and r->'_nc' ? 'pos' and r->>'not_captured'='04-1, 06-4, 06-3, QC'
  from jsonb_array_elements(tt.run('p4_supplier_score','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'supplier'='test_sup_one'));
select tt.chk('T5 notices name the forms that were not captured', (select count(*) from jsonb_array_elements(tt.run('p4_supplier_score','{"preset":"this_month"}'::jsonb)->'notes') n where n->>'code'='data_needed' and n->>'what' in ('04-1','06-4','06-3'))=3);
select tt.chk('T5 totals leave the uncaptured legs out (no 0 total for grns)', not (tt.run('p4_supplier_score','{"preset":"this_month"}'::jsonb)->'totals' ? 'grns'));
reset role;
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('04-1',7,9501,tt.today(),'approved','{"supplier":"test_sup_one","lines":[{"item":"test_raw_flour","memo":10,"counted":9,"quality":"return"},{"item":"test_raw_sugar","memo":5,"counted":5,"quality":"ok"}]}'::jsonb,'[]',:'o','test_store');
set role authenticated; select tt.as(:'o');
select qc_record('grn',:'pb1'::uuid,'reject','[]'::jsonb,'test bad lot') is not null as q1 \gset
select tt.chk('T5 once a GRN sheet and a QC check exist the legs show numbers: grns 1, lines 2, short 1, rejected 1, qc 1 / bad 1 (100 %)', (select (r->>'grns')::int=1 and (r->>'lines')::int=2 and (r->>'short_lines')::int=1 and (r->>'rejected')::int=1 and (r->>'qc_n')::int=1 and (r->>'qc_bad')::int=1 and (r->>'qc_bad_pct')::numeric=100 and r->>'not_captured'='06-4, 06-3'
  from jsonb_array_elements(tt.run('p4_supplier_score','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'supplier'='test_sup_one'));
select tt.chk('T5 a supplier with only bills still appears (test_sup_nocredit, 1 bill of 300)', (select (r->>'bills_n')::int=1 and (r->>'bills_total')::numeric=300 from jsonb_array_elements(tt.run('p4_supplier_score','{"preset":"this_month"}'::jsonb)->'rows') r where r->>'supplier'='test_sup_nocredit'));

\echo == T6 #98 supplier ageing: overdue empty where credit days are not set
select tt.chk('T6 the old report showed overdue 0 for a supplier with no credit days', (select (r->>'overdue')::numeric=0 from jsonb_array_elements(tt.core('supplier_ageing','{}'::jsonb)->'rows') r where r->>'supplier'='test_sup_nocredit'));
select tt.chk('T6 the new one leaves it empty and flags it', (select r->'overdue'='null'::jsonb and r->'_nc' ? 'overdue' from jsonb_array_elements(tt.run('supplier_ageing','{}'::jsonb)->'rows') r where r->>'supplier'='test_sup_nocredit'));
select tt.chk('T6 a supplier with credit days keeps its number (3740 - 84 return open, no overdue yet)', (select (r->>'overdue')::numeric>=0 and r->'overdue' <> 'null'::jsonb from jsonb_array_elements(tt.run('supplier_ageing','{}'::jsonb)->'rows') r where r->>'supplier'='test_sup_one'));
select tt.chk('T6 notice names the supplier and the field', exists (select 1 from jsonb_array_elements(tt.run('supplier_ageing','{}'::jsonb)->'notes') n where n->>'what'='credit_days' and n->>'text_en' like '%test_sup_nocredit%'));
select tt.chk('T6 no age bucket default is invented: with report_aging_buckets empty the report says so', exists (select 1 from jsonb_array_elements(tt.run('supplier_ageing','{}'::jsonb)->'notes') n where n->>'what'='report_aging_buckets') and not exists (select 1 from jsonb_array_elements(tt.run('supplier_ageing','{}'::jsonb)->'columns') c where c->>'key' like 'bucket_%'));
select tt.chk('T6 supplier_credit_gaps lists the supplier for the payables screen', (select count(*) from jsonb_array_elements(supplier_credit_gaps()) g where g->>'name'='test_sup_nocredit')=1);

\echo == T7 wastage by reason: no sum across units
select tt.chk('T7 the old report added kg and pieces into one number (expired 1.5 kg + 1 pc = 2.5)', (select qty from wastage_by_reason(null, tt.today()-1, tt.today()+1) where reason_code='expired')=2.5);
select tt.chk('T7 the new one has no single quantity for a mixed reason and lists one quantity per unit', (select r->'qty'='null'::jsonb and (r->>'mixed_units')::boolean and jsonb_array_length(r->'units')=2 from jsonb_array_elements(wastage_by_reason2(null, tt.today()-1, tt.today()+1)) r where r->>'reason_code'='expired'));
select tt.chk('T7 a reason with one unit keeps its quantity and unit (broken 0.5 kg)', (select (r->>'qty')::numeric=0.5 and r->>'unit'='kg' and not (r->>'mixed_units')::boolean from jsonb_array_elements(wastage_by_reason2(null, tt.today()-1, tt.today()+1)) r where r->>'reason_code'='broken'));
select tt.chk('T7 entries and items are the same as the old report', (select (r->>'entries')::int from jsonb_array_elements(wastage_by_reason2(null, tt.today()-1, tt.today()+1)) r where r->>'reason_code'='expired') = (select entries from wastage_by_reason(null, tt.today()-1, tt.today()+1) where reason_code='expired'));
select tt.err('T7 bad range refused', $q$select wastage_by_reason2(null,'2020-01-01','2026-12-31')$q$, 'bad_range');

\echo == T8 stock_reconcile fix: owner only, typed confirmation, audit line
select tt.chk('T8 nothing to fix at the start', (select count(*) from stock_reconcile())=0);
reset role; update stock_balance set qty = qty + 7 where item_id=:'i_fl'::uuid and location_id=7; set role authenticated; select tt.as(:'o');
select tt.chk('T8 the drift is found (diff 7)', (select qty_diff from stock_reconcile() where item_id=:'i_fl'::uuid and location_id=7)=7);
select tt.err('T8 the confirm word is required', $q$select stock_reconcile_fix(null)$q$, 'confirm_required');
select tt.err('T8 a wrong word is refused', $q$select stock_reconcile_fix('fix')$q$, 'confirm_required');
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T8 a salesperson cannot use the confirmed path', $q$select stock_reconcile_fix('FIX')$q$, 'not allowed');
select tt.err('T8 nor the direct path', $q$select * from stock_reconcile(true)$q$, 'not allowed');
reset role; select tt.as(:'o'); set role authenticated;
select (stock_reconcile_fix('FIX')->>'fixed')::int as fixed \gset
select tt.chk('T8 the confirmed fix repaired exactly the one row', :fixed=1 and (select count(*) from stock_reconcile())=0 and (select qty from stock_balance where item_id=:'i_fl'::uuid and location_id=7)=77);
select tt.chk('T8 two audit lines: the rewrite (confirmed) and the confirmation', (select count(*) from audit_log where action='stock_reconcile_fix' and (detail->>'confirmed')::boolean and (detail->>'rows_fixed')::int=1)=1 and (select count(*) from audit_log where action='stock_reconcile_confirm')=1);
reset role; update stock_balance set qty = qty + 3 where item_id=:'i_fl'::uuid and location_id=7; set role authenticated; select tt.as(:'o');
select count(*) as nfix from stock_reconcile(true) \gset
select tt.chk('T8 the old direct call still works for the owner (existing behaviour) and now logs a line with confirmed = false', :nfix=1 and (select count(*) from audit_log where action='stock_reconcile_fix' and not (detail->>'confirmed')::boolean)=1);
select tt.chk('T8 a clean ledger writes no audit line (no change)', (select count(*) from stock_reconcile(true))=0 and (select count(*) from audit_log where action='stock_reconcile_fix')=2);

\echo == T9 export audit line
select log_report_export4('stock_recon','csv','{"a":1}'::jsonb,12) is null as lg \gset
select tt.chk('T9 the owner can log an export, one audit line', (select count(*) from audit_log where action='export' and record_id='stock_recon' and (detail->>'rows')::int=12)=1);
select tt.err('T9 unknown key refused', $q$select log_report_export4('nope','csv','{}',1)$q$, 'unknown_report');
select tt.err('T9 bad kind refused', $q$select log_report_export4('stock_recon','C S V!','{}',1)$q$, 'bad_kind');
reset role; select tt.as(:'x'); set role authenticated;
select tt.err('T9 a person without the export right is refused', $q$select log_report_export4('stock_recon','csv','{}',1)$q$, 'not allowed');
reset role;

\echo == T10 no new setting, grant or default was created
select tt.chk('T10 phase420 added no rule and no grant', not exists (select 1 from rules where key like '%420%') and (select count(*) from grant_defs where grant_code in ('report_stock','report_purchase','report_quality'))=3);
select tt.chk('T10 report_expiry_soon_days and report_aging_buckets are still empty (no default invented)', rule_val('report_expiry_soon_days') is null and rule_val('report_aging_buckets') is null);

\echo == SUMMARY
select 'SUMMARY ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
