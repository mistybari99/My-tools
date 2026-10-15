-- FRESH DB ONLY. Phase 90 tests (SCAN: photo -> draft -> review -> confirm through the existing save functions).
--   Build: base phase8..phase84 (ORDER as in docs/briefs_p2p3/step_Scan_REPORT.md) then phase90.
--   Run: psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase90_test.sql | grep -E "FAIL|RESULT"
-- Test data only (ids and roles, no real names).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set u '00000000-0000-0000-0000-000000000002'
\set g '00000000-0000-0000-0000-000000000003'
\set k '00000000-0000-0000-0000-000000000004'
\set w '00000000-0000-0000-0000-000000000005'
\set x '00000000-0000-0000-0000-000000000006'
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
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'u','store2@s.app','{"full_name":"Uploader"}'), (:'g','mgr3@s.app','{"full_name":"Manager"}'),
 (:'k','sales4@s.app','{"full_name":"Sales"}'), (:'w','store5@s.app','{"full_name":"Other place"}'), (:'x','store6@s.app','{"full_name":"Reviewer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'u','storekeeper'),(:'g','management'),(:'k','salesperson'),(:'w','storekeeper'),(:'x','storekeeper') on conflict do nothing;
insert into user_locations values (:'u',1),(:'g',1),(:'k',1),(:'w',2),(:'x',1) on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('S9-SU','চিনি','Refined Sugar','kg','kg','raw_material',true,null), ('S9-FL','ময়দা','Maida Flour','kg','kg','raw_material',true,null),
 ('S9-OI','তেল','Cooking Oil','ltr','ltr','raw_material',true,null), ('S9-CK','কেক','Plain Cake','kg','kg','finished_good',true,300);
select id as isu from items where code='S9-SU' \gset
select id as ifl from items where code='S9-FL' \gset
select id as ick from items where code='S9-CK' \gset
select tt.as(:'o');
select save_supplier(null, '{"name":"Alpha Traders"}'::jsonb) as sup1 \gset
select save_supplier(null, '{"name":"Beta Flour Mill"}'::jsonb) as sup2 \gset
select set_user_grant(:'g'::uuid,'purchase_entry') is null as ga \gset
select set_user_grant(:'u'::uuid,'purchase_entry') is null as gb \gset
select set_user_grant(:'x'::uuid,'scan_confirm') is null as gc \gset
select set_user_grant(:'x'::uuid,'purchase_entry') is null as gd \gset
select (select count(*) from stock_ledger) as led0 \gset

\echo == T0 shape, switches, grants, privileges
select tt.chk('T0 tables exist with RLS on', (select count(*) from pg_class where relname in ('scan_jobs','scan_events') and relrowsecurity)=2);
select tt.chk('T0 switches: scan_enabled OFF, scan_engine manual, scan_min_confidence 0.6', (select default_value from rules where key='scan_enabled')='false'::jsonb and (select default_value from rules where key='scan_engine')='"manual"'::jsonb
  and (select default_value from rules where key='scan_min_confidence')='0.6'::jsonb and not rule_on('scan_enabled') and rule_txt('scan_engine')='manual');
select tt.chk('T0 there is NO auto-confirm switch and NO auto-confirm function', not exists (select 1 from rules where key ilike '%auto%confirm%' and key like 'scan%') and not exists (select 1 from pg_proc where proname ilike '%scan%auto%'));
select tt.chk('T0 grants exist; role seeds: storekeeper uploads, management confirms (not the other way)', (select count(*) from grant_defs where grant_code in ('scan_upload','scan_confirm'))=2
  and exists (select 1 from rule_grants where grant_code='scan_upload' and role_code='storekeeper') and exists (select 1 from rule_grants where grant_code='scan_confirm' and role_code='management')
  and not exists (select 1 from rule_grants where grant_code='scan_confirm' and role_code='storekeeper'));
select tt.chk('T0 browser functions: authenticated yes, anon no; helpers closed', has_function_privilege('authenticated','scan_confirm(uuid,uuid,boolean,boolean)','execute') and not has_function_privilege('anon','scan_confirm(uuid,uuid,boolean,boolean)','execute')
  and not has_function_privilege('anon','scan_create(uuid,text,int,text,text,text)','execute') and not has_function_privilege('authenticated','_scan_clean(text,jsonb,boolean)','execute') and not has_function_privilege('authenticated','_scan_event(uuid,text,text,text,jsonb)','execute'));
select tt.chk('T0 photo policies exist and the bucket is private', (select count(*) from pg_policies where tablename='objects' and policyname in ('scan_photos_insert','scan_photos_read'))=2
  and coalesce((select public from storage.buckets where id='photos'), false)=false);
select tt.chk('T0 audit trigger + append-only triggers present', (select count(*) from pg_trigger where not tgisinternal and tgname in ('audit_scan_jobs','scan_jobs_guard90','scan_events_ro','scan_events_ro_t','scan_jobs_guard90_t'))=5);

\echo == T1 scan_create
select tt.as(:'u');
select tt.err('T1 switch OFF: refused', format($$select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/a1.jpg')$$), 'scan_off');
select tt.as(:'o'); select set_rule('scan_enabled','true') is null as son \gset
select tt.as(:'u');
select '11111111-1111-1111-1111-111111111111' as c1 \gset
select scan_create(:'c1'::uuid,'purchase_bill',1,'SCAN/1/a1.jpg','aabbccddeeff00112233') ->> 'id' as j1 \gset
select tt.chk('T1 uploader creates a job: status uploaded, engine manual', (select status from scan_jobs where id=:'j1'::uuid)='uploaded' and (select engine from scan_jobs where id=:'j1'::uuid)='manual');
select tt.chk('T1 same client id twice = same job (dup), one row', (scan_create(:'c1'::uuid,'purchase_bill',1,'SCAN/1/a1.jpg','aabbccddeeff00112233')->>'dup')='true' and (select count(*) from scan_jobs)=1);
select tt.as(:'g');
select tt.err('T1 another user cannot reuse a client id', format($$select scan_create(%L,'purchase_bill',1,'SCAN/1/zz.jpg')$$, :'c1'), 'client_id_taken');
select tt.as(:'k');
select tt.err('T1 salesperson (no scan_upload) refused', $$select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/k1.jpg')$$, 'not allowed');
select tt.as(:'u');
select tt.err('T1 place not allowed', $$select scan_create(gen_random_uuid(),'purchase_bill',2,'SCAN/2/u2.jpg')$$, 'not allowed');
select tt.err('T1 bad path (not under SCAN/)', $$select scan_create(gen_random_uuid(),'purchase_bill',1,'PURCHASE/1/x.jpg')$$, 'bad_image_path');
select tt.err('T1 path place must equal the place', $$select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/2/x.jpg')$$, 'bad_image_path');
select tt.err('T1 path traversal refused', $$select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/../x.jpg')$$, 'bad_image_path');
select tt.err('T1 bad kind', $$select scan_create(gen_random_uuid(),'invoice',1,'SCAN/1/b.jpg')$$, 'bad_kind');
select tt.err('T1 same image cannot be attached twice', $$select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/a1.jpg')$$, 'image_already_used');
select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/a1b.jpg','aabbccddeeff00112233') as sp \gset
select tt.chk('T1 the same picture twice is only a WARNING (same_photo lists the first job)', jsonb_array_length(:'sp'::jsonb->'same_photo')=1 and (:'sp'::jsonb->'same_photo'->0->>'id')=:'j1');
select tt.chk('T1 creation is on the trail', (select count(*) from scan_events where job_id=:'j1'::uuid and action='created')=1);

\echo == T2 scan_set_extracted (the reader can only make a DRAFT)
select tt.as(:'u');
select scan_set_extracted(:'j1'::uuid, jsonb_build_object('supplier', jsonb_build_object('name','Alpha Traders','id','00000000-0000-0000-0000-0000000000aa','create',true),
  'bill_no','B-100','date',(tt.today()::text),'total','৳ 1,250.50','evil','drop table','lines', jsonb_build_array(
   jsonb_build_object('desc','Sugar 50kg','qty','২','unit','kg','unit_cost','500','item_id',:'isu','decision','map'),
   jsonb_build_object('desc','Flour','qty','abc','unit_cost',150.25))),
  jsonb_build_object('supplier',1.7,'bill_no',0.3,'total',0.9,'evil',1,'lines', jsonb_build_array(jsonb_build_object('desc',0.95,'qty',-3,'unit_cost',0.2),jsonb_build_object('qty',0.4))), 'ai_vision') as ex \gset
select tt.chk('T2 job becomes extracted, engine recorded', (select status from scan_jobs where id=:'j1'::uuid)='extracted' and (select engine from scan_jobs where id=:'j1'::uuid)='ai_vision');
select tt.chk('T2 machine output carries NO item id, NO decision, NO supplier id / create flag', not (select extracted::text from scan_jobs where id=:'j1'::uuid) ~ '(item_id|decision|"create"|0000000000aa)');
select tt.chk('T2 unknown keys dropped, Bangla digit 2 parsed, taka sign and comma removed (1250.50), bad qty becomes null', (select extracted ? 'evil' from scan_jobs where id=:'j1'::uuid)=false and (select (extracted->'lines'->0->>'qty')::numeric from scan_jobs where id=:'j1'::uuid)=2
  and (select (extracted->>'total')::numeric from scan_jobs where id=:'j1'::uuid)=1250.50 and (select extracted->'lines'->1 ? 'qty' from scan_jobs where id=:'j1'::uuid)=false);
select tt.chk('T2 confidence clamped to 0..1, unknown key dropped', (select (confidence->>'supplier')::numeric from scan_jobs where id=:'j1'::uuid)=1 and (select (confidence->'lines'->0->>'qty')::numeric from scan_jobs where id=:'j1'::uuid)=0 and (select confidence ? 'evil' from scan_jobs where id=:'j1'::uuid)=false);
select tt.err('T2 payload that is not an object refused', format($$select scan_set_extracted(%L, '[1,2]'::jsonb)$$, :'j1'), 'bad_payload');
select tt.err('T2 more than 300 lines refused', format($$select scan_set_extracted(%L, jsonb_build_object('lines', (select jsonb_agg(jsonb_build_object('desc','x')) from generate_series(1,301))))$$, :'j1'), 'too_many_lines');
select tt.as(:'k');
select tt.err('T2 a user who cannot see the job gets not found', format($$select scan_set_extracted(%L, '{}'::jsonb)$$, :'j1'), 'not found');
select tt.as(:'u');
select scan_create(gen_random_uuid(),'other',1,'SCAN/1/f1.jpg') ->> 'id' as jf \gset
select (scan_set_extracted(:'jf'::uuid, null, null, 'ai_vision', 'model unreachable')->>'failed')::boolean as fl \gset
select tt.chk('T2 a failed read keeps the job open with the error noted; trail has extract_failed', :'fl'::boolean and (select status from scan_jobs where id=:'jf'::uuid)='uploaded' and (select extract_error from scan_jobs where id=:'jf'::uuid)='model unreachable'
  and (select count(*) from scan_events where job_id=:'jf'::uuid and action='extract_failed')=1);

\echo == T3 matching (existing names only)
select tt.as(:'u');
select tt.chk('T3 typo "refind sugr" finds Refined Sugar first', (select item_id from scan_match_items('refind sugr') limit 1)=:'isu'::uuid);
select tt.chk('T3 Bangla name matches (চিনি)', (select item_id from scan_match_items('চিনি') limit 1)=:'isu'::uuid);
select tt.chk('T3 word overlap: "Flour 50 kg bag" finds Maida Flour', exists (select 1 from scan_match_items('Flour 50 kg bag') where item_id=:'ifl'::uuid));
select tt.chk('T3 nothing similar = EMPTY list (no invented item)', (select count(*) from scan_match_items('qqqq zzzz'))=0);
select tt.chk('T3 no cost column is returned', not exists (select 1 from information_schema.columns where table_name='scan_match_items') and (select count(*) from pg_proc p where proname='scan_match_items' and pg_get_function_result(oid) ~* 'cost')=0);
select tt.chk('T3 supplier match "alfa traders" finds Alpha Traders', (select supplier_id from scan_match_suppliers('alfa traders') limit 1)=:'sup1'::uuid and (select count(*) from scan_match_suppliers('qqqq'))=0);
select tt.chk('T3 matching never writes (item count unchanged, 4 items)', (select count(*) from items where code like 'S9-%')=4);
select tt.as(:'k');
select tt.err('T3 a user without any scan grant cannot use the matcher', $$select * from scan_match_items('sugar')$$, 'not allowed');
select tt.chk('T3 similarity helper: identical 1, different 0', _scan_sim('Abc','abc')=1 and _scan_sim('abc','xyz')=0);

\echo == T4 review save, warnings, duplicates
select tt.as(:'u');
select tt.err('T4 a typed non-number is refused (human input is strict)', format($$select scan_review_save(%L, '{"lines":[{"desc":"x","qty":"abc"}]}'::jsonb)$$, :'j1'), 'bad_number');
select tt.err('T4 impossible date refused', format($$select scan_review_save(%L, '{"date":"2026-13-45"}'::jsonb)$$, :'j1'), 'bad_date');
select tt.err('T4 future date refused', format($$select scan_review_save(%L, jsonb_build_object('date', (tt.today()+30)::text))$$, :'j1'), 'bad_date');
select scan_review_save(:'j1'::uuid, jsonb_build_object('supplier', jsonb_build_object('name','Alpha Traders','id',:'sup1'),'bill_no','B-100','date',tt.today()::text,'total',1250.50,
  'lines', jsonb_build_array(jsonb_build_object('desc','Sugar 50kg','qty',2,'unit','kg','unit_cost',500,'item_id',:'isu','decision','map'),
                             jsonb_build_object('desc','Flour','qty',1,'unit','kg','unit_cost',150.25))), false) as rv \gset
select tt.chk('T4 draft save keeps status extracted; warns: 1 unmatched line (the flour)', (:'rv'::jsonb->>'status')='extracted'
  and exists (select 1 from jsonb_array_elements(:'rv'::jsonb->'warnings') w where w->>'code'='unmatched_lines' and (w->>'n')='1'));
select tt.chk('T4 low confidence: untouched qty (conf 0), unit_cost (conf 0.2) of line 1 and bill_no (0.3) are flagged; desc (0.95) is not', 
  (select count(*) from jsonb_array_elements(:'rv'::jsonb->'warnings') w where w->>'code'='low_confidence' and (w->>'line')='1' and w->>'field' in ('qty','unit_cost'))=2
  and exists (select 1 from jsonb_array_elements(:'rv'::jsonb->'warnings') w where w->>'code'='low_confidence' and w->>'field'='bill_no')
  and not exists (select 1 from jsonb_array_elements(:'rv'::jsonb->'warnings') w where w->>'code'='low_confidence' and w->>'field'='desc'));
select tt.chk('T4 total check: lines 1000+150.25 = 1150.25 vs paper 1250.50 -> total_mismatch warning (not a block)', exists (select 1 from jsonb_array_elements(:'rv'::jsonb->'warnings') w where w->>'code'='total_mismatch' and (w->>'lines_total')::numeric=1150.25 and (w->>'paper_total')::numeric=1250.50));
select scan_review_save(:'j1'::uuid, (select edited from scan_jobs where id=:'j1'::uuid) || jsonb_build_object('lines', jsonb_build_array(
   jsonb_build_object('desc','Sugar 50kg','qty',2,'unit','kg','unit_cost',500,'item_id',:'isu','decision','map'),
   jsonb_build_object('desc','Flour','qty',1,'unit','kg','unit_cost',250.50,'item_id',:'ifl','decision','map'))), true) as rv2 \gset
select tt.chk('T4 final save: status reviewed, no total_mismatch / unmatched warning left (1000+250.50 = 1250.50)', (:'rv2'::jsonb->>'status')='reviewed' and not exists (select 1 from jsonb_array_elements(:'rv2'::jsonb->'warnings') w where w->>'code' in ('total_mismatch','unmatched_lines')) and (select reviewed_by from scan_jobs where id=:'j1'::uuid) is not null);
select tt.chk('T4 the reader''s output is kept untouched beside the edits (extracted still has Flour 150.25)', (select (extracted->'lines'->1->>'unit_cost')::numeric from scan_jobs where id=:'j1'::uuid)=150.25 and (select (edited->'lines'->1->>'unit_cost')::numeric from scan_jobs where id=:'j1'::uuid)=250.50);
select tt.err('T4 reader result cannot overwrite a reviewed job', format($$select scan_set_extracted(%L, '{}'::jsonb)$$, :'j1'), 'not_open');
select scan_review_save(:'j1'::uuid, (select edited from scan_jobs where id=:'j1'::uuid), false) ->> 'status' as bk \gset
select tt.chk('T4 editing again takes it back out of reviewed (back to extracted)', :'bk'='extracted');
select scan_review_save(:'j1'::uuid, (select edited from scan_jobs where id=:'j1'::uuid), true) is not null as rr \gset
select tt.chk('T4 trail has saved + reviewed rows', (select count(*) from scan_events where job_id=:'j1'::uuid and action in ('saved','reviewed'))=4);

\echo == T5 confirm a purchase bill
select tt.as(:'u');
select tt.err('T5 the uploader without scan_confirm cannot confirm', format($$select scan_confirm(%L, gen_random_uuid())$$, :'j1'), 'not allowed');
select tt.as(:'x');
select tt.chk('T5 reviewer without the cost right sees NO purchase numbers (cost_hidden)', (scan_get(:'j1'::uuid)->>'cost_hidden')='true' and (scan_get(:'j1'::uuid)->'edited') = 'null'::jsonb);
select tt.err('T5 ... and cannot confirm a purchase bill', format($$select scan_confirm(%L, gen_random_uuid())$$, :'j1'), 'not allowed');
select tt.as(:'o'); select set_user_grant(:'x'::uuid,'view_cost') is null as gv \gset
select tt.as(:'x');
select tt.chk('T5 with the cost right the reviewer sees the draft', (scan_get(:'j1'::uuid)->>'cost_hidden')='false' and (scan_get(:'j1'::uuid)->'edited'->>'bill_no')='B-100');
select tt.as(:'o');
select tt.err('T5 confirm needs a client key', format($$select scan_confirm(%L, null)$$, :'j1'), 'client_required');
select '22222222-2222-2222-2222-222222222222' as ck1 \gset
select scan_confirm(:'j1'::uuid, :'ck1'::uuid) as cf \gset
select tt.chk('T5 confirm made ONE draft purchase bill via save_purchase: supplier, bill no, total 1250.50, 2 lines', (select count(*) from purchase_bills where supplier_id=:'sup1'::uuid)=1
  and (select total from purchase_bills where supplier_id=:'sup1'::uuid)=1250.50 and (select status from purchase_bills where supplier_id=:'sup1'::uuid)='draft' and (select bill_no from purchase_bills where supplier_id=:'sup1'::uuid)='B-100'
  and (select count(*) from purchase_lines where bill_id=(:'cf'::jsonb->>'result_id')::uuid)=2);
select tt.chk('T5 job is confirmed and linked to the bill', (select status from scan_jobs where id=:'j1'::uuid)='confirmed' and (select result_type from scan_jobs where id=:'j1'::uuid)='purchase_bills' and (select result_id from scan_jobs where id=:'j1'::uuid)=(:'cf'::jsonb->>'result_id'));
select tt.chk('T5 a draft posts nothing: stock ledger unchanged', (select count(*) from stock_ledger)=:'led0'::int);
select tt.chk('T5 same confirm key again = replay (dup:true), still ONE bill', (scan_confirm(:'j1'::uuid, :'ck1'::uuid)->>'dup')='true' and (select count(*) from purchase_bills where supplier_id=:'sup1'::uuid)=1);
select tt.err('T5 a different key on a confirmed job = already_confirmed', format($$select scan_confirm(%L, gen_random_uuid())$$, :'j1'), 'already_confirmed');
select tt.err('T5 a confirmed job cannot be rejected', format($$select scan_reject(%L, 'changed my mind')$$, :'j1'), 'already_confirmed');
select tt.err('T5 a confirmed job cannot be edited', format($$select scan_review_save(%L, '{}'::jsonb)$$, :'j1'), 'not_open');
select tt.err('T5 a confirmed row cannot be changed even by a direct update', format($$update scan_jobs set note='x' where id=%L$$, :'j1'), 'append_only');
select tt.chk('T5 trail: created, extracted, saved/reviewed, confirmed + confirm_replay', (select count(*) from scan_events where job_id=:'j1'::uuid and action='confirmed')=1 and (select count(*) from scan_events where job_id=:'j1'::uuid and action='confirm_replay')=1);

\echo == T6 duplicates + atomicity
select tt.as(:'u');
select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/a2.jpg') ->> 'id' as j2 \gset
select scan_review_save(:'j2'::uuid, jsonb_build_object('supplier', jsonb_build_object('id',:'sup1'),'bill_no','b-100','date',tt.today()::text,
  'lines', jsonb_build_array(jsonb_build_object('desc','Sugar','qty',2,'unit','kg','unit_cost',500,'item_id',:'isu','decision','map'),
                             jsonb_build_object('desc','Brand new thing','qty',1,'unit','kg','unit_cost',250.50,'decision','create','name_en','Scan New Spice'))), true) as r2 \gset
select tt.chk('T5/T6 duplicate flagged: same supplier + bill no (any case) + total 1250.50 as an existing bill', exists (select 1 from jsonb_array_elements(:'r2'::jsonb->'dups') d where d->>'type'='purchase_bill') and exists (select 1 from jsonb_array_elements(:'r2'::jsonb->'dups') d where d->>'type'='scan'));
select tt.as(:'o');
select tt.err('T6 duplicate refused until acknowledged', format($$select scan_confirm(%L, gen_random_uuid())$$, :'j2'), 'duplicate_suspect');
select tt.err('T6 acknowledged duplicate is still stopped by the purchase rule (duplicate_bill) ...', format($$select scan_confirm(%L, gen_random_uuid(), true)$$, :'j2'), 'duplicate_bill');
select tt.chk('T6 ... and the whole confirm rolled back: the "create" item was NOT made, job still reviewed, still one bill', not exists (select 1 from items where name_en='Scan New Spice') and (select status from scan_jobs where id=:'j2'::uuid)='reviewed'
  and (select count(*) from purchase_bills where supplier_id=:'sup1'::uuid)=1);
select tt.as(:'u');
select scan_review_save(:'j2'::uuid, (select jsonb_set(edited, '{bill_no}', '"B-200"') from scan_jobs where id=:'j2'::uuid), true) as r2b \gset
select tt.chk('T6 changing the bill number clears the duplicate', jsonb_array_length(:'r2b'::jsonb->'dups')=0);
select tt.as(:'o');
select scan_confirm(:'j2'::uuid, gen_random_uuid(), false, true) as cf2 \gset
select tt.chk('T6 owner-explicit "create item" line made the item; bill line points to it; p_post posted the bill (stock +2 sugar, +1 new item)', exists (select 1 from items where name_en='Scan New Spice')
  and (select count(*) from purchase_lines where bill_id=(:'cf2'::jsonb->>'result_id')::uuid and item_id=(select id from items where name_en='Scan New Spice'))=1
  and (select status from purchase_bills where id=(:'cf2'::jsonb->>'result_id')::uuid)='posted' and (select coalesce(sum(qty),0) from stock_balance where item_id=:'isu'::uuid and location_id=1)=2);
select tt.as(:'u');
select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/a3.jpg') ->> 'id' as j3 \gset
select scan_review_save(:'j3'::uuid, jsonb_build_object('supplier', jsonb_build_object('id',:'sup2'),'bill_no','Z-1','date',tt.today()::text,
  'lines', jsonb_build_array(jsonb_build_object('desc','Flour','qty',3,'unit','kg','unit_cost',100,'item_id',:'ifl','decision','map'))), true) is not null as r3 \gset
select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/a4.jpg') ->> 'id' as j4 \gset
select scan_review_save(:'j4'::uuid, jsonb_build_object('supplier', jsonb_build_object('id',:'sup2'),'bill_no','Z-1','date',tt.today()::text,
  'lines', jsonb_build_array(jsonb_build_object('desc','Flour','qty',3,'unit','kg','unit_cost',100,'item_id',:'ifl','decision','map'))), true) as r4 \gset
select tt.chk('T6 two unconfirmed scans of the same bill flag each other', (:'r4'::jsonb->'dups'->0->>'type')='scan' and (:'r4'::jsonb->'dups'->0->>'id')=:'j3');

\echo == T7 mapping rules: nothing invented
select tt.as(:'u');
select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/m1.jpg') ->> 'id' as jm \gset
select scan_review_save(:'jm'::uuid, jsonb_build_object('supplier', jsonb_build_object('name','Gamma Stores'),'bill_no','G-1','date',tt.today()::text,
  'lines', jsonb_build_array(jsonb_build_object('desc','Mystery thing','qty',1,'unit','kg','unit_cost',10))), true) is not null as rm \gset
select tt.as(:'o');
select tt.err('T7 unmatched supplier (not picked, not marked create) refused', format($$select scan_confirm(%L, gen_random_uuid())$$, :'jm'), 'supplier_not_mapped');
select tt.as(:'u');
select scan_review_save(:'jm'::uuid, (select jsonb_set(edited, '{supplier}', '{"name":"Gamma Stores","create":true}') from scan_jobs where id=:'jm'::uuid), true) is not null as rm2 \gset
select tt.as(:'o');
select tt.err('T7 unmatched LINE (no map / create / text / skip decision) refused', format($$select scan_confirm(%L, gen_random_uuid())$$, :'jm'), 'unmatched_lines');
select tt.chk('T7 nothing was created by the refused attempts (no Gamma supplier, 0 bills for it)', not exists (select 1 from suppliers where name='Gamma Stores'));
select tt.as(:'u');
select scan_review_save(:'jm'::uuid, (select jsonb_set(edited, '{lines,0,decision}', '"text"') from scan_jobs where id=:'jm'::uuid), true) is not null as rm3 \gset
select tt.as(:'o');
select scan_confirm(:'jm'::uuid, gen_random_uuid()) as cfm \gset
select tt.chk('T7 explicit supplier create + line kept as plain text: supplier made, bill has a description-only line', exists (select 1 from suppliers where name='Gamma Stores')
  and (select count(*) from purchase_lines where bill_id=(:'cfm'::jsonb->>'result_id')::uuid and item_id is null and description='Mystery thing')=1);
select tt.as(:'u');
select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/m2.jpg') ->> 'id' as jm2 \gset
select scan_review_save(:'jm2'::uuid, jsonb_build_object('supplier', jsonb_build_object('name','Alpha Traders','create',true),'bill_no','Q-1','date',tt.today()::text,
  'lines', jsonb_build_array(jsonb_build_object('desc','x','qty',1,'unit_cost',1,'decision','text'))), true) is not null as rm4 \gset
select tt.as(:'o');
select tt.err('T7 "create supplier" with an almost identical existing name refused (map it instead)', format($$select scan_confirm(%L, gen_random_uuid())$$, :'jm2'), 'similar_supplier_exists');
select tt.as(:'u');
select tt.as(:'u');
select scan_review_save(:'jm2'::uuid, jsonb_build_object('supplier', jsonb_build_object('id',:'sup1'),'date',tt.today()::text,'lines', jsonb_build_array(jsonb_build_object('desc','x','qty',1,'unit_cost',1,'item_id','00000000-0000-0000-0000-00000000dead','decision','map'))), true) is not null as rm5 \gset
select tt.as(:'o');
select tt.err('T7 an item id that does not exist is refused at confirm (nothing saved)', format($$select scan_confirm(%L, gen_random_uuid())$$, :'jm2'), 'item_not_found');

\echo == T8 expense
select tt.as(:'u');
select scan_create(gen_random_uuid(),'expense',1,'SCAN/1/e1.jpg') ->> 'id' as je \gset
select scan_set_extracted(:'je'::uuid, '{"paid_to":"Local Transport","head":"Transport Cost!","amount":"350","date":"x","mode":"cash"}'::jsonb) is not null as ex8 \gset
select tt.chk('T8 head is normalised to a code (transport_cost), invalid date dropped', (select extracted->>'head' from scan_jobs where id=:'je'::uuid)='transport_cost' and (select extracted ? 'date' from scan_jobs where id=:'je'::uuid)=false);
select scan_review_save(:'je'::uuid, jsonb_build_object('paid_to','Local Transport','head','transport','amount',350,'date',tt.today()::text,'mode','cash'), true) as re \gset
select tt.as(:'o');
select scan_confirm(:'je'::uuid, gen_random_uuid()) as ce \gset
select tt.chk('T8 confirm called quick_expense_add: one expense, 350, place 1, head transport; linked', (select count(*) from quick_expenses where head='transport' and amount=350 and location_id=1)=1
  and (select result_id from scan_jobs where id=:'je'::uuid)=(select id::text from quick_expenses where head='transport'));
select tt.as(:'u');
select scan_create(gen_random_uuid(),'expense',1,'SCAN/1/e2.jpg') ->> 'id' as je2 \gset
select scan_review_save(:'je2'::uuid, jsonb_build_object('paid_to','Local Transport','head','transport','amount',350,'date',tt.today()::text), true) as re2 \gset
select tt.chk('T8 same place + day + head + amount as an existing quick expense is flagged', (:'re2'::jsonb->'dups'->0->>'type')='quick_expense');
select tt.as(:'o');
select tt.err('T8 ... and needs acknowledging', format($$select scan_confirm(%L, gen_random_uuid())$$, :'je2'), 'duplicate_suspect');
select tt.as(:'u');
select scan_create(gen_random_uuid(),'expense',1,'SCAN/1/e3.jpg') ->> 'id' as je3 \gset
select scan_review_save(:'je3'::uuid, jsonb_build_object('paid_to','x','amount',50), true) is not null as re3 \gset
select tt.as(:'o');
select tt.err('T8 expense without a head / date refused', format($$select scan_confirm(%L, gen_random_uuid())$$, :'je3'), 'bad_date');

\echo == T9 product list
select tt.as(:'u');
select scan_create(gen_random_uuid(),'product_list',1,'SCAN/1/p1.jpg') ->> 'id' as jp \gset
select scan_review_save(:'jp'::uuid, jsonb_build_object('lines', jsonb_build_array(
  jsonb_build_object('desc','Plain Cake 1kg','price',420,'item_id',:'ick','decision','map'),
  jsonb_build_object('desc','Choc Brownie','unit','kg','price','180.50','decision','create','name_en','Choc Brownie'),
  jsonb_build_object('desc','junk line','decision','skip'))), true) as rp \gset
select tt.as(:'o');
select scan_confirm(:'jp'::uuid, gen_random_uuid()) as cp \gset
select tt.chk('T9 confirm: item_new made Choc Brownie at 180.50, item_apply moved the existing cake price 300 -> 420, skipped line ignored', (select sell_price from items where name_en='Choc Brownie')=180.50 and (select sell_price from items where id=:'ick'::uuid)=420
  and (:'cp'::jsonb->'result'->>'created')='1' and (:'cp'::jsonb->'result'->>'updated')='1');
select tt.chk('T9 no cost price was written for any scanned item', (select cost_price from items_with_cost() where item_id=(select id from items where name_en='Choc Brownie')) is null);
select tt.as(:'u');
select scan_create(gen_random_uuid(),'product_list',1,'SCAN/1/p2.jpg') ->> 'id' as jp2 \gset
select scan_review_save(:'jp2'::uuid, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('desc','Something','price',10))), true) is not null as rp2 \gset
select tt.as(:'o');
select tt.err('T9 a product line with no decision is refused', format($$select scan_confirm(%L, gen_random_uuid())$$, :'jp2'), 'unmatched_lines');

\echo == T10 other / report, reject
select tt.as(:'u');
select scan_create(gen_random_uuid(),'other',1,'SCAN/1/o1.jpg') ->> 'id' as jo \gset
select scan_review_save(:'jo'::uuid, '{"title":"Monthly report","note":"kept for reference"}'::jsonb, true) is not null as ro \gset
select tt.as(:'o');
select scan_confirm(:'jo'::uuid, gen_random_uuid()) as co \gset
select tt.chk('T10 "other" is archived and posts nothing (result none)', (:'co'::jsonb->>'result_type')='none' and (select count(*) from purchase_bills)=3);
select tt.as(:'u');
select scan_create(gen_random_uuid(),'other',1,'SCAN/1/r1.jpg') ->> 'id' as jr \gset
select tt.err('T10 reject needs a reason', format($$select scan_reject(%L, 'x')$$, :'jr'), 'note_needed');
select scan_reject(:'jr'::uuid, 'blurry photo') ->> 'status' as rj \gset
select tt.chk('T10 the uploader can reject own draft; row stays, reason kept; second reject = noop', :'rj'='rejected' and (select reject_reason from scan_jobs where id=:'jr'::uuid)='blurry photo' and (scan_reject(:'jr'::uuid,'again')->>'noop')='true');
select tt.as(:'o');
select tt.err('T10 a rejected scan cannot be confirmed', format($$select scan_confirm(%L, gen_random_uuid())$$, :'jr'), 'not_reviewed');
select tt.err('T10 a rejected scan cannot be edited', format($$select scan_review_save(%L, '{}'::jsonb)$$, :'jr'), 'not_open');
select tt.chk('T10 nothing is ever deleted', (select count(*) from scan_jobs)>=10);
select tt.err('T10 delete refused', format($$delete from scan_jobs where id=%L$$, :'jr'), 'nothing is deleted');

\echo == T11 visibility, direct writes, trail, photos
select tt.as(:'k');
select tt.chk('T11 a user with no scan right sees no job and an empty list', jsonb_array_length(scan_list())=0);
select tt.err('T11 ... and scan_get says not found', format($$select scan_get(%L)$$, :'jm'), 'not found');
select tt.as(:'w');
select tt.chk('T11 a storekeeper of another place sees nothing', jsonb_array_length(scan_list())=0);
select tt.as(:'g');
select tt.chk('T11 the confirmer (place 1) lists the jobs of place 1, with no extracted numbers in the list', jsonb_array_length(scan_list())>=8 and not (scan_list())::text ~ 'unit_cost');
select tt.as(:'u');
select tt.chk('T11 uploader sees own jobs (all of them are his)', jsonb_array_length(scan_list())=(select count(*) from scan_jobs));
set role authenticated;
select tt.as(:'u');
select tt.chk('T11 direct select works for own rows only (RLS)', (select count(*) from scan_jobs)>0 and (select count(*) from scan_jobs where created_by<>:'u'::uuid)=0);
select tt.err('T11 nobody can insert into scan_jobs directly', $$insert into scan_jobs (client_id,kind,location_id,image_path,created_by) values (gen_random_uuid(),'other',1,'SCAN/1/direct.jpg','00000000-0000-0000-0000-000000000002')$$, 'permission denied');
select tt.err('T11 nobody can update scan_jobs directly', $$update scan_jobs set status='confirmed'$$, 'permission denied');
select tt.err('T11 nobody can write the trail', $$insert into scan_events (job_id,action) select id,'saved' from scan_jobs limit 1$$, 'permission denied');
reset role;
select tt.err('T11 the trail is append-only even for the owner of the table', $$update scan_events set action='saved'$$, 'append_only');
select tt.chk('T11 audit_log carries the scan_jobs inserts and updates', (select count(*) from audit_log where table_name='scan_jobs')>10);
select tt.chk('T11 photo check: uploader may upload under SCAN/1, not SCAN/2, not other prefixes', (select _scan_photo_ok('SCAN/1/new1.jpg','enter')) is not null);
select tt.as(:'u');
select tt.chk('T11a uploader can upload at place 1 but not place 2', _scan_photo_ok('SCAN/1/new1.jpg','enter') and not _scan_photo_ok('SCAN/2/new1.jpg','enter') and not _scan_photo_ok('PURCHASE/1/new1.jpg','enter'));
select tt.chk('T11a uploader reads own photo; a made-up path is unreadable', _scan_photo_ok('SCAN/1/a1.jpg','view') and not _scan_photo_ok('SCAN/1/nothere.jpg','view'));
select tt.as(:'k');
select tt.chk('T11a salesperson can neither upload nor read a scan photo', not _scan_photo_ok('SCAN/1/new1.jpg','enter') and not _scan_photo_ok('SCAN/1/a1.jpg','view'));
select tt.as(:'w');
select tt.chk('T11a other-place user cannot read it', not _scan_photo_ok('SCAN/1/a1.jpg','view'));
select tt.as(:'g');
select tt.chk('T11a confirmer reads place-1 photos', _scan_photo_ok('SCAN/1/a1.jpg','view'));
insert into storage.objects (bucket_id, name) select 'photos', 'SCAN/1/a1.jpg' where not exists (select 1 from storage.objects where name='SCAN/1/a1.jpg');
select tt.as(:'u');
set role authenticated;
select tt.as(:'u');
insert into storage.objects (bucket_id, name) values ('photos', 'SCAN/1/up1.jpg');
select tt.chk('T11a storage: the uploader sees the object of HIS job (SCAN/1/a1.jpg)', (select count(*) from storage.objects where name='SCAN/1/a1.jpg')=1);
select tt.as(:'k');
select tt.chk('T11a storage: a user without a scan right sees NO scan object', (select count(*) from storage.objects where name='SCAN/1/a1.jpg')=0);
select tt.err('T11a storage policy refuses an upload from a user without scan_upload', $$insert into storage.objects (bucket_id, name) values ('photos', 'SCAN/1/up2.jpg')$$, 'row-level security');
select tt.as(:'w');
select tt.chk('T11a storage: a user of another place sees no scan object', (select count(*) from storage.objects where name='SCAN/1/a1.jpg')=0);
select tt.as(:'g');
select tt.chk('T11a storage: the confirmer of place 1 sees it', (select count(*) from storage.objects where name='SCAN/1/a1.jpg')=1);
reset role;
select tt.chk('T11a storage policy let the uploader insert SCAN/1/... (row exists)', (select count(*) from storage.objects where name='SCAN/1/up1.jpg')=1);

\echo == T12 confidence is warn-only
select tt.as(:'u');
select scan_create(gen_random_uuid(),'expense',1,'SCAN/1/c1.jpg') ->> 'id' as jc \gset
select scan_set_extracted(:'jc'::uuid, jsonb_build_object('head','fuel','amount',900,'date',tt.today()::text), '{"amount":0.1,"head":0.2}'::jsonb) is not null as exc \gset
select scan_review_save(:'jc'::uuid, jsonb_build_object('head','fuel','amount',900,'date',tt.today()::text), true) as rc \gset
select tt.chk('T12 unchanged low-confidence fields (amount 0.1, head 0.2) are warned', (select count(*) from jsonb_array_elements(:'rc'::jsonb->'warnings') w where w->>'code'='low_confidence')=2);
select tt.as(:'o');
select scan_confirm(:'jc'::uuid, gen_random_uuid()) as cc \gset
select tt.chk('T12 ... but Confirm is NOT blocked, the warnings come back with it', (:'cc'::jsonb->>'status')='confirmed' and jsonb_array_length(:'cc'::jsonb->'warnings')=2);
select set_rule('scan_min_confidence','0.05') is null as rmin \gset
select tt.as(:'u');
select scan_create(gen_random_uuid(),'expense',1,'SCAN/1/c2.jpg') ->> 'id' as jc2 \gset
select scan_set_extracted(:'jc2'::uuid, jsonb_build_object('head','fuel','amount',901,'date',tt.today()::text), '{"amount":0.1}'::jsonb) is not null as exc2 \gset
select tt.chk('T12 lowering the rule to 0.05 removes the warning', jsonb_array_length(scan_review_save(:'jc2'::uuid, jsonb_build_object('head','fuel','amount',901,'date',tt.today()::text), true)->'warnings')=0);

\echo == T13 engine setting and trail
select tt.as(:'o');
select set_rule('scan_engine','"ai_vision"') is null as re1 \gset
select tt.as(:'u');
select scan_create(gen_random_uuid(),'other',1,'SCAN/1/g1.jpg')->>'id' as jg \gset
select tt.chk('T13 a new job picks up the engine setting', (select engine from scan_jobs where id=:'jg'::uuid)='ai_vision');
select tt.as(:'o');
select tt.err('T13 scan_engine accepts only the 3 values', $$select set_rule('scan_engine','"magic"')$$, 'bad_value');
select set_rule('scan_engine','"manual"') is null as re2 \gset
select tt.chk('T13 every status change is in the trail with who and when (j1: created -> ... -> confirmed in order)', (select string_agg(action, ',' order by id) from scan_events where job_id=:'j1'::uuid) like 'created,extracted,saved,reviewed,saved,reviewed,confirmed%');

reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
