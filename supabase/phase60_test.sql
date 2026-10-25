-- FRESH DB ONLY. Phase 60 tests (P3a: reorder, wastage reasons, GRN batch/expiry, QC).
--   ORDER="phase8 ... phase51 phase60" bash tests/sql/build_fresh_db.sh p60db   (see docs/briefs_p2p3/COMMON.md)
--   psql -h /tmp -p 5544 -U postgres -d p60db -qAt -f supabase/phase60_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;


insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Sales"}'), (:'k','store3@s.app','{"full_name":"Store"}'), ('00000000-0000-0000-0000-000000000004','far4@s.app','{"full_name":"Far"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'k','storekeeper'),('00000000-0000-0000-0000-000000000004','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),('00000000-0000-0000-0000-000000000004',3) on conflict do nothing;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant execute on function tt.today() to authenticated, anon;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price, min_stock) values
 ('R1','R1','R1','kg','kg','raw_material',true,0,null), ('R2','R2','R2','kg','kg','raw_material',true,0,50), ('R3','R3','R3','kg','kg','raw_material',true,0,null),
 ('FG','FG','FG','kg','kg','finished_good',true,10,null);
select id as r1 from items where code='R1' \gset
select id as r2 from items where code='R2' \gset
select id as r3 from items where code='R3' \gset
select id as fg from items where code='FG' \gset

\echo == T0 shape
select tt.chk('T0 tables are read-only for browsers', not has_table_privilege('authenticated','public.qc_records','insert') and not has_table_privilege('authenticated','public.grn_batch_links','insert') and has_table_privilege('authenticated','public.qc_records','select'));
select tt.chk('T0 callable by authenticated, not anon', has_function_privilege('authenticated','public.reorder_report(int,int)','execute') and not has_function_privilege('anon','public.reorder_report(int,int)','execute')
  and not has_function_privilege('authenticated','public._qc_batch_blocked60(bigint)','execute'));
select tt.chk('T0 quality_block_on defaults OFF; lead days 3', not rule_on('quality_block_on') and rule_num('reorder_lead_days')=3);
select tt.chk('T0 stock_post untouched by phase60', position('bos60' in pg_get_functiondef('public.stock_post(uuid,int,numeric,text,text,text,numeric,bigint,timestamptz,text,bigint,text,uuid,uuid)'::regprocedure))=0);

\echo == T1 reorder suggestion
set role authenticated; select tt.as(:'o');
select stock_opening(:'r1'::uuid,1,300,5,null,'s') is not null as a1 \gset
select stock_opening(:'r2'::uuid,1,20,5,null,'s') is not null as a2 \gset
select stock_opening(:'r3'::uuid,1,500,5,null,'s') is not null as a3 \gset
reset role;
-- 30 kg of R1 issued over the last 10 days; R3 used 3 kg only
insert into stock_ledger (item_id, location_id, qty_delta, reason, ref_type, ref_id, made_at) values
 (:'r1',1,-30,'issue_out','t','t1', now() - interval '5 days'), (:'r3',1,-3,'sale_out','t','t2', now() - interval '2 days'), (:'r1',1,-99,'issue_out','t','t3', now() - interval '60 days');
select tt.as(:'k'); set role authenticated;
select tt.chk('T1 R1: on hand 171, avg 1/day over 30d, need 1*(3+7)=10 < 70 -> not listed', not exists (select 1 from reorder_report(1) where item_id=:'r1'::uuid));
select tt.chk('T1 R2 below min 50: on hand 20, suggest 30, why below_min', (select suggest_qty from reorder_report(1) where item_id=:'r2'::uuid)=30 and (select why from reorder_report(1) where item_id=:'r2'::uuid)='below_min');
reset role; select tt.as(:'o'); set role authenticated;
select set_rule('reorder_lookback_days','10'::jsonb) is null as sr1 \gset
select set_rule('reorder_lead_days','60'::jsonb) is null as sr2 \gset
select tt.chk('T1 owner lead 60d, lookback 10d: R1 avg 3/day, need 3*(60+7)=201, suggest 201-171=30, runs_out_in_lead', (select suggest_qty from reorder_report(1) where item_id=:'r1'::uuid)=30 and (select why from reorder_report(1) where item_id=:'r1'::uuid)='runs_out_in_lead'
  and (select avg_daily from reorder_report(1) where item_id=:'r1'::uuid)=3 and (select days_left from reorder_report(1) where item_id=:'r1'::uuid)=57.0);
select tt.chk('T1 override p_days=60 (avg 2.15/day, need 144 < 171): R1 no longer listed', not exists (select 1 from reorder_report(1,60) where item_id=:'r1'::uuid));
select tt.err('T1 bad days refused', 'select * from reorder_report(1,0)', 'bad_days');
reset role; select tt.as(:'k'); set role authenticated;
select tt.err('T1 other location refused for a loc-1 user', 'select * from reorder_report(3)', '');
reset role; select tt.as(:'o');
select tt.chk('T1 read-only: no stock_ledger row was added by the report', (select count(*) from stock_ledger where reason='purchase_in')=0);
select set_rule('reorder_lead_days','3'::jsonb) is null as sr3 \gset
select set_rule('reorder_lookback_days','30'::jsonb) is null as sr4 \gset

\echo == T2 wastage reasons
select tt.as(:'o'); set role authenticated;
select tt.chk('T2 new reasons seeded, old ones kept', (select count(*) from option_lists where list_code='wastage_reasons' and value_code in ('qc_reject','spillage','pest','expired','spoiled'))=5);
select stock_wastage(:'r3'::uuid,1,5,'spoiled','old style') is not null as w1 \gset
select stock_wastage(:'r3'::uuid,1,2,'spillage','new reason') is not null as w2 \gset
select stock_wastage(:'r2'::uuid,1,1,'spillage','again') is not null as w3 \gset
select tt.err('T2 unknown reason still refused', format($$select stock_wastage('%s'::uuid,1,1,'nonsense','x')$$, :'r3'), 'bad_reason');
select tt.chk('T2 report by reason: spillage 2 entries qty 3, spoiled 1 entry qty 5', (select entries from wastage_by_reason(1) where reason_code='spillage')=2 and (select qty from wastage_by_reason(1) where reason_code='spillage')=3
  and (select qty from wastage_by_reason(1) where reason_code='spoiled')=5 and (select label_en from wastage_by_reason(1) where reason_code='spillage')='Spillage');
select tt.chk('T2 date range outside returns nothing', (select count(*) from wastage_by_reason(1, tt.today()-60, tt.today()-40))=0);
select tt.err('T2 bad range', 'select * from wastage_by_reason(1, current_date, current_date-5)', 'bad_range');
reset role;
select tt.chk('T2 wastage rows are still immutable (existing rows untouched)', (select count(*) from stock_wastage)=3);

\echo == T3 batch + expiry on a purchase bill
select tt.as(:'o'); set role authenticated;
select save_supplier(null,'{"name":"Sup","credit_days":7}') as sup \gset
reset role; select tt.as(:'k'); set role authenticated;
select save_purchase(null,null,:'sup',1,'B-1',tt.today(),format('[{"item_id":"%s","qty":40,"unit":"kg","unit_cost":10}]',:'r1')::jsonb) ->> 'id' as pb \gset
select post_purchase(:'pb'::uuid) is not null as pp \gset
select tt.chk('T3 purchase posted, R1 on hand 211', (select qty from stock_balance where item_id=:'r1'::uuid and location_id=1)=211);
select grn_batch_add('purchase', :'pb'::uuid, :'r1'::uuid, 25, 'kg', 'LOT-A', tt.today()+5, null, '60606060-0000-0000-0000-000000000001') ->> 'batch_id' as ba \gset
select grn_batch_add('purchase', :'pb'::uuid, :'r1'::uuid, 10, 'kg', 'LOT-B', tt.today()+2) ->> 'batch_id' as bb \gset
select tt.chk('T3 two batches stored in stock_batches with batch_no and expiry', (select count(*) from stock_batches where id in (:ba,:bb) and batch_no is not null and expires_at is not null)=2
  and (select qty_remaining from stock_batches where id=:ba)=25);
select tt.chk('T3 same client id is a no-op', (grn_batch_add('purchase', :'pb'::uuid, :'r1'::uuid, 25, 'kg', 'LOT-A', tt.today()+5, null, '60606060-0000-0000-0000-000000000001') ->> 'dup')::boolean and (select count(*) from stock_batches where batch_no is not null)=2);
select tt.err('T3 duplicate batch no refused', format($$select grn_batch_add('purchase','%s'::uuid,'%s'::uuid,1,'kg','lot-a',current_date+9)$$, :'pb', :'r1'), 'batch_no_exists');
select tt.err('T3 more than the bill received refused (25+10+10>40)', format($$select grn_batch_add('purchase','%s'::uuid,'%s'::uuid,10,'kg','LOT-C',current_date+9)$$, :'pb', :'r1'), 'more_than_received');
select tt.err('T3 past expiry refused', format($$select grn_batch_add('purchase','%s'::uuid,'%s'::uuid,1,'kg','LOT-D',current_date-1)$$, :'pb', :'r1'), 'bad_expiry');
select tt.err('T3 item not on the bill refused', format($$select grn_batch_add('purchase','%s'::uuid,'%s'::uuid,1,'kg','LOT-E',current_date+9)$$, :'pb', :'r3'), 'item_not_in_source');
select tt.err('T3 empty batch no refused', format($$select grn_batch_add('purchase','%s'::uuid,'%s'::uuid,1,'kg','  ',current_date+9)$$, :'pb', :'r1'), 'bad_batch_no');
select tt.chk('T3 stock balance unchanged by batch capture', (select qty from stock_balance where item_id=:'r1'::uuid and location_id=1)=211);
select tt.chk('T3 FEFO hint: LOT-B (2 days) is first, then LOT-A', (select batch_no from fefo_hint(:'r1'::uuid,1) where rank=1)='LOT-B' and (select batch_no from fefo_hint(:'r1'::uuid,1) where rank=2)='LOT-A');
select tt.chk('T3 near-expiry (3 days) shows LOT-B only; 7 days shows both', (select count(*) from near_expiry_report(1,3))=1 and (select batch_no from near_expiry_report(1,3))='LOT-B' and (select count(*) from near_expiry_report(1))=2);
reset role; select tt.as(:'o'); set role authenticated;
select stock_issue(:'r1'::uuid,1,12,null,'fefo') is not null as fi \gset
select tt.chk('T3 stock_post really takes FEFO: an issue of 12 empties LOT-B (10) then 2 from LOT-A', (select qty_remaining from stock_batches where id=:bb)=0 and (select qty_remaining from stock_batches where id=:ba)=23);
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T3 salesperson without grant cannot capture', format($$select grn_batch_add('purchase','%s'::uuid,'%s'::uuid,1,'kg','LOT-S',current_date+9)$$, :'pb', :'r1'), 'not allowed');
reset role; select tt.as('00000000-0000-0000-0000-000000000004'); set role authenticated;
select tt.err('T3 user of another location refused', format($$select grn_batch_add('purchase','%s'::uuid,'%s'::uuid,1,'kg','LOT-S',current_date+9)$$, :'pb', :'r1'), 'not allowed for this location');
select tt.err('T3 direct insert refused', format($$insert into grn_batch_links (batch_id,source_type,source_id,item_id,location_id,batch_no,expiry_date,qty_base) values (1,'grn','%s','%s',1,'x',current_date,1)$$, :'pb', :'r1'), 'permission denied');
reset role;
select tt.chk('T3 link table is append-only', (select count(*) from grn_batch_links)=2);
select tt.err('T3 link cannot be updated', 'update grn_batch_links set batch_no=''z''', 'append_only');
select tt.err('T3 link cannot be deleted', 'delete from grn_batch_links', 'append_only');

\echo == T4 batch on a GRN form 04-1
select tt.as(:'k'); set role authenticated;
select save_entry(null,'04-1',1,tt.today(),'{"supplier":"Sup A","lines":[{"item":"R3","counted":"20","rate":"5","quality":"accept"}]}','[]') ->> 'id' as g1 \gset
reset role;
select tt.err('T4 a draft GRN is not a source yet', format($$select grn_batch_add('grn','%s'::uuid,'%s'::uuid,5,'kg','G-1',current_date+9)$$, :'g1', :'r3'), 'source_not_found');
set role authenticated; select tt.as(:'k');
select submit_entry(:'g1'::uuid) is not null as sg \gset
select tt.chk('T4 submitted GRN: batch captured for R3 (500 on hand)', grn_batch_add('grn', :'g1'::uuid, :'r3'::uuid, 20, 'kg', 'G-1', tt.today()+30) is not null);
select tt.err('T4 item not on that GRN refused', format($$select grn_batch_add('grn','%s'::uuid,'%s'::uuid,1,'kg','G-2',current_date+9)$$, :'g1', :'r1'), 'item_not_in_source');

\echo == T5 QC (append-only, off by default)
select tt.chk('T5 storekeeper records a pass with checks', (qc_record('grn', :'g1'::uuid, 'pass', '[{"code":"smell","ok":true},{"code":"weight","ok":true}]', null, null, '60606060-0000-0000-0000-0000000000a1') ->> 'status')='pass');
select tt.chk('T5 same client id: dup, no second row', (qc_record('grn', :'g1'::uuid, 'pass', '[]', null, null, '60606060-0000-0000-0000-0000000000a1') ->> 'dup')::boolean and (select count(*) from qc_records)=1);
select tt.err('T5 pass with a failed check refused', format($$select qc_record('grn','%s'::uuid,'pass','[{"code":"smell","ok":false}]')$$, :'g1'), 'pass_has_failed_check');
select tt.err('T5 hold needs a note', format($$select qc_record('grn','%s'::uuid,'hold','[{"code":"smell","ok":false}]')$$, :'g1'), 'note_required');
select tt.err('T5 unknown check code refused', format($$select qc_record('grn','%s'::uuid,'pass','[{"code":"zzz","ok":true}]')$$, :'g1'), 'bad_check_code');
select tt.err('T5 bad status refused', format($$select qc_record('grn','%s'::uuid,'maybe','[]')$$, :'g1'), 'bad_status');
select tt.err('T5 unknown source refused', $$select qc_record('grn','99999999-0000-0000-0000-000000000000'::uuid,'pass','[]')$$, 'source_not_found');
select qc_record('grn', :'g1'::uuid, 'hold', '[{"code":"smell","ok":false}]', 'smells off', null) ->> 'id' as q2 \gset
select tt.chk('T5 hold with the switch OFF blocks nothing: gate not blocked, new batch still allowed', (qc_gate('grn',:'g1'::uuid) ->> 'status')='hold' and not (qc_gate('grn',:'g1'::uuid) ->> 'blocked')::boolean
  and (select count(*) from fefo_hint(:'r3'::uuid,1) where qc_blocked)=0);
select tt.chk('T5 history keeps both records, the second supersedes the first', (select count(*) from qc_history('grn',:'g1'::uuid))=2 and (select supersedes_id from qc_records where id=:'q2'::uuid) is not null);
select tt.chk('T5 qc_list shows ONE line (latest) for the source', (select count(*) from qc_list(1))=1 and (select status from qc_list(1))='hold' and (select history_n from qc_list(1))=2);
reset role;
select tt.err('T5 qc record cannot be updated', 'update qc_records set status=''pass''', 'append_only');
select tt.err('T5 qc record cannot be deleted', 'delete from qc_records', 'append_only');
select tt.chk('T5 yellow exception raised for the hold (not red)', exists (select 1 from exceptions where flag_code='qc_hold' and level='yellow'));
select tt.as(:'s'); set role authenticated;
select tt.err('T5 salesperson cannot record QC', format($$select qc_record('grn','%s'::uuid,'pass','[]')$$, :'g1'), 'not allowed');
reset role;

\echo == T6 quality_block_on
select tt.as(:'o'); set role authenticated;
select set_rule('quality_block_on','true'::jsonb) is null as sw \gset
select tt.chk('T6 switch ON: gate blocked, GRN batch marked blocked in FEFO hint', (qc_gate('grn',:'g1'::uuid) ->> 'blocked')::boolean and (select qc_blocked from fefo_hint(:'r3'::uuid,1) limit 1));
select tt.err('T6 switch ON: a new batch on the held GRN is refused', format($$select grn_batch_add('grn','%s'::uuid,'%s'::uuid,1,'kg','G-9',current_date+9)$$, :'g1', :'r3'), 'qc_blocked');
select tt.chk('T6 switch ON: batch of an OTHER source is not blocked', (select count(*) from fefo_hint(:'r1'::uuid,1) where qc_blocked)=0);
select qc_record('grn', :'g1'::uuid, 'pass', '[{"code":"smell","ok":true}]') ->> 'status' as qp \gset
select tt.chk('T6 a later pass clears the block', :'qp'='pass' and not (qc_gate('grn',:'g1'::uuid) ->> 'blocked')::boolean);
select tt.chk('T6 stock_wastage / stock_issue still work (nothing posts through QC)', stock_issue(:'r3'::uuid,1,1,null,'x') is not null);
select set_rule('quality_block_on','false'::jsonb) is null as swoff \gset
reset role;

\echo == T7 QC on a production run
select tt.as(:'o'); set role authenticated;
select recipe_save(null,:'fg'::uuid,2,'kg','v1',format('[{"ingredient_item_id":"%s","qty":1,"unit":"kg","waste_pct":0}]',:'r3')::jsonb) ->> 'id' as rc \gset
select production_post(1,:'rc'::uuid,1,'70707070-0000-0000-0000-000000000001') ->> 'run_id' as run \gset
select (production_post(1,:'rc'::uuid,1,'70707070-0000-0000-0000-000000000001') ->> 'batch_id') as pbatch \gset
select tt.chk('T7 production run exists', :'run' is not null);
select tt.chk('T7 QC reject on the run is stored', (qc_record('production', :'run'::uuid, 'reject', '[{"code":"taste","ok":false}]', 'bitter', null) ->> 'status')='reject');
select tt.chk('T7 run gate (switch OFF) reports reject but not blocked', (qc_gate('production',:'run'::uuid) ->> 'status')='reject' and not (qc_gate('production',:'run'::uuid) ->> 'blocked')::boolean);
select set_rule('quality_block_on','true'::jsonb) is null as sw2 \gset
select tt.chk('T7 switch ON: the production batch is marked blocked in FEFO hint', (select qc_blocked from fefo_hint(:'fg'::uuid,1) where batch_id=:'pbatch'::bigint));
select set_rule('quality_block_on','false'::jsonb) is null as sw3 \gset
reset role;

\echo == T8 RLS
select tt.as('00000000-0000-0000-0000-000000000004'); set role authenticated;
select tt.chk('T8 other-location user sees no QC / batch link rows', (select count(*) from qc_records)=0 and (select count(*) from grn_batch_links)=0 and (select count(*) from qc_list())=0);
reset role;

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
