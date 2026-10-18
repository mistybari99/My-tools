-- Phase 540 tests (XB part 1: bKash / Nagad / Rocket capture, verification, statement import, tie-out). Neutral test_* data only.  bash tests/sql/xb_run.sh phase540
\ir ../tests/sql/c2_fixture.sql

\echo == T0 shape
select tt.chk('T0 functions: capture open to browsers, helpers closed; anon denied; table read-only; RLS on',
  has_function_privilege('authenticated', 'public.xb_pay_capture(uuid,text,text,text,numeric,timestamptz,text,int,text,uuid,uuid,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.xb_pay_tieout(date,text)', 'execute')
  and not has_function_privilege('anon', 'public.xb_pay_capture(uuid,text,text,text,numeric,timestamptz,text,int,text,uuid,uuid,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public._xb540_verifier(int)', 'execute')
  and not has_table_privilege('authenticated', 'public.pay_captures', 'update')
  and not has_table_privilege('anon', 'public.pay_captures', 'select')
  and (select relrowsecurity from pg_class where relname = 'pay_captures') and (select relrowsecurity from pg_class where relname = 'pay_statement_lines'));
select tt.chk('T0 switch OFF, tolerance blank, pay_verify grant defined and held by nobody', not rule_on('pay_capture_on') and rule_num('pay_capture_tol') is null
  and exists (select 1 from grant_defs where grant_code = 'pay_verify') and not exists (select 1 from user_grants where grant_code = 'pay_verify'));
select tt.chk('T0 the wallets bKash and Nagad exist and are active', exists (select 1 from d_wallets where code = 'bkash' and active) and exists (select 1 from d_wallets where code = 'nagad' and active));

\echo == T1 switch OFF: refused, nothing written
select tt.as(:'p');
select tt.err('T1 capture refused while the switch is OFF',
  $q$select xb_pay_capture(null,'bkash','BKTEST0001','01711000001',200,now(),'bkash',1,'none')$q$, 'module_off');
select count(*) = 0 as none0 from pay_captures \gset
select tt.chk('T1 no capture row was written', :'none0');

\echo == T2 switch ON (owner)
select tt.as(:'o');
select set_rule('pay_capture_on', 'true');
select tt.chk('T2 owner switches capture on', rule_on('pay_capture_on'));
select tt.as(:'p');
-- an open app order of 2 x 100 = 200 (no delivery charge, no advance)
select (online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_cust_pay', '01711000010', null,
        jsonb_build_array(jsonb_build_object('item_id', :'ia', 'qty', 2)), 'pickup', null, null, 0, 0, 0, null, null, null)->>'id')::uuid as oid \gset
select (xb_pay_capture(null,'bkash','BKTEST0001','01711000001',200,now(),'bkash',1,'order', :'oid'::uuid, null, 'manual', null)->>'flag') = 'ok' as f_ok \gset
select tt.chk('T2 exact order payment is flagged ok and pending', :'f_ok' and exists (select 1 from pay_captures where trx_id = 'BKTEST0001' and status = 'pending'));

\echo == T3 duplicate Trx-ID and client id
select tt.err('T3 same Trx-ID twice is refused',
  $q$select xb_pay_capture(null,'bkash','BKTEST0001','01711000001',200,now(),'bkash',1,'none')$q$, 'duplicate_trx');
select tt.err('T3 same Trx-ID with lower case is refused too (normalised)',
  $q$select xb_pay_capture(null,'nagad','bktest0001','01711000001',200,now(),'nagad',1,'none')$q$, 'duplicate_trx');
select (xb_pay_capture('11111111-1111-1111-1111-111111111111','nagad','NGTEST0009','01711000002',10,now(),'nagad',1,'none')->>'id')::bigint as c_a \gset
select (xb_pay_capture('11111111-1111-1111-1111-111111111111','nagad','NGTEST0009','01711000002',10,now(),'nagad',1,'none')->>'dup')::boolean as c_dup \gset
select tt.chk('T3 the same client id returns the earlier capture (dup true) and writes nothing new', :'c_dup' and (select count(*) from pay_captures where client_id = '11111111-1111-1111-1111-111111111111') = 1);

\echo == T4 input checks
select tt.err('T4 bad Trx-ID format refused', $q$select xb_pay_capture(null,'bkash','ab-1','01711000001',5,now(),'bkash',1,'none')$q$, 'bad_trx_id');
select tt.err('T4 unknown provider refused', $q$select xb_pay_capture(null,'upaycard','ZZTEST0001','01711000001',5,now(),'bkash',1,'none')$q$, 'bad_provider');
select tt.err('T4 wallet not in the list refused', $q$select xb_pay_capture(null,'bkash','ZZTEST0002','01711000001',5,now(),'xx',1,'none')$q$, 'bad_wallet');
select tt.err('T4 zero amount refused', $q$select xb_pay_capture(null,'bkash','ZZTEST0003','01711000001',0,now(),'bkash',1,'none')$q$, 'bad_amount');
select tt.err('T4 a time in the future refused', $q$select xb_pay_capture(null,'bkash','ZZTEST0004','01711000001',5,now()+interval '1 day','bkash',1,'none')$q$, 'bad_time');
select tt.err('T4 a bad sender number refused', $q$select xb_pay_capture(null,'bkash','ZZTEST0005','12',5,now(),'bkash',1,'none')$q$, 'bad_mobile');
select tt.err('T4 an order of another place is refused', $q$select xb_pay_capture(null,'bkash','ZZTEST0006','01711000001',5,now(),'bkash',2,'order','00000000-0000-0000-0000-000000000001'::uuid)$q$, 'not allowed');

\echo == T5 flags: overpay, underpay, no target
select (xb_pay_capture(null,'bkash','OVTEST0001','01711000003',250,now(),'bkash',1,'order', :'oid'::uuid)->>'flag') = 'overpay' as f_over \gset
select (xb_pay_capture(null,'bkash','UNTEST0001','01711000003',150,now(),'bkash',1,'order', :'oid'::uuid)->>'flag') = 'underpay' as f_under \gset
select (xb_pay_capture(null,'bkash','NTTEST0001','01711000003',7,now(),'bkash',1,'none')->>'flag') = 'no_target' as f_none \gset
select tt.chk('T5 overpay, underpay and no-target are flagged, never silently ok', :'f_over' and :'f_under' and :'f_none');
select tt.chk('T5 the flagged capture carries the difference (250 paid, 200 due = 50 over)', (select diff from pay_captures where trx_id = 'OVTEST0001') = 50);

\echo == T6 sale target uses the amount still due
select (record_sale2(gen_random_uuid(), 1, ('[{"item_id":"' || :'ib' || '","qty":1}]')::jsonb, 0, '[{"mode":"cash","amount":30}]'::jsonb, '01711000020', 'test_sale_pay', 'retail', 'pay test', false, null)->>'id')::uuid as sid \gset
select (xb_pay_capture(null,'nagad','SATEST0001','01711000020',20,now(),'nagad',1,'sale', null, :'sid'::uuid)->>'flag') = 'ok' as s_ok \gset
select tt.chk('T6 a sale payment equal to the due (50 - 30 = 20) is ok', :'s_ok');

\echo == T7 verification: no self approval, notes for flags, decided is final
select tt.as(:'p');
select tt.err('T7 the capturer cannot verify own capture', $q$select xb_pay_capture_decide((select id from pay_captures where trx_id = 'BKTEST0001'), true, null)$q$, 'not allowed');
select tt.as(:'m');
select tt.err('T7 a manager without pay_verify cannot verify', $q$select xb_pay_capture_decide((select id from pay_captures where trx_id = 'BKTEST0001'), true, null)$q$, 'not allowed');
insert into user_grants (user_id, grant_code, location_id) values (:'m', 'pay_verify', 1) on conflict do nothing;
select tt.err('T7 a flagged capture needs a note to verify', $q$select xb_pay_capture_decide((select id from pay_captures where trx_id = 'OVTEST0001'), true, null)$q$, 'note_required');
select (xb_pay_capture_decide((select id from pay_captures where trx_id = 'BKTEST0001'), true, null)->>'status') = 'verified' as v1 \gset
select (xb_pay_capture_decide((select id from pay_captures where trx_id = 'OVTEST0001'), false, 'test: amount not received')->>'status') = 'rejected' as v2 \gset
select tt.chk('T7 the verifier verifies an ok capture and rejects a flagged one with a note', :'v1' and :'v2');
select tt.err('T7 a decided capture cannot be decided again', $q$select xb_pay_capture_decide((select id from pay_captures where trx_id = 'BKTEST0001'), false, 'test again')$q$, 'already_decided');

\echo == T8 append-only
select tt.err('T8 a capture cannot be deleted', $q$delete from pay_captures where trx_id = 'NTTEST0001'$q$, 'append_only');
select tt.err('T8 the amount cannot be changed under a capture', $q$update pay_captures set amount = 1 where trx_id = 'BKTEST0001'$q$, 'append_only');

\echo == T9 screenshot
select tt.err('T9 a path outside the pay/<place>/ folder is refused', $q$select xb_pay_capture_screenshot((select id from pay_captures where trx_id = 'NTTEST0001'), 'other/1/a.jpg')$q$, 'bad_path');
select (xb_pay_capture_screenshot((select id from pay_captures where trx_id = 'NTTEST0001'), 'pay/1/proof_1.jpg')->>'screenshot_path') = 'pay/1/proof_1.jpg' as ss1 \gset
select tt.err('T9 the screenshot is attached once', $q$select xb_pay_capture_screenshot((select id from pay_captures where trx_id = 'NTTEST0001'), 'pay/1/proof_2.jpg')$q$, 'already_attached');
select tt.chk('T9 the first screenshot path is stored', :'ss1');

\echo == T10 statement import and tie-out
select tt.as(:'p');
select tt.err('T10 a salesperson cannot import a statement', $q$select xb_pay_statement_import('bkash', '[]'::jsonb)$q$, 'not allowed');
select tt.as(:'o');
select (xb_pay_statement_import('bkash', ('[{"trx_id":"bktest0001","direction":"in","amount":200,"at":"' || (now() - interval '1 hour')::text || '"},{"trx_id":"STMTONLY01","direction":"in","amount":500,"at":"' || (now() - interval '2 hour')::text || '"}]')::jsonb)->>'inserted')::int = 2 as i1 \gset
select (xb_pay_statement_import('bkash', ('[{"trx_id":"BKTEST0001","direction":"in","amount":200,"at":"' || (now() - interval '1 hour')::text || '"},{"trx_id":"??","direction":"in","amount":5,"at":"' || now()::text || '"}]')::jsonb)->>'already_there')::int = 1 as i2 \gset
select tt.chk('T10 the statement import writes new lines once and counts the repeat and the bad row', :'i1' and :'i2');
select (xb_pay_tieout(tt.today(), 'bkash')->'wallets'->0->>'status') = 'difference' as t1 \gset
select (xb_pay_tieout(tt.today(), 'bkash')->'wallets'->0->>'statement_lines_without_capture')::int = 1 as t2 \gset
select (xb_pay_tieout(tt.today(), 'bkash')->'wallets'->0->>'captured_verified')::numeric = 200 as t3 \gset
select tt.chk('T10 tie-out: one statement line without a capture makes the day a difference; the verified 200 is shown', :'t1' and :'t2' and :'t3');
select (xb_pay_tieout(tt.today(), 'nagad')->'wallets'->0->>'status') = 'no_statement_imported' as t4 \gset
select tt.chk('T10 a wallet with no statement imported is reported as such, never as matched', :'t4');
select tt.chk('T10 no journal entry is written by any capture or import', (select count(*) from journal_entries where source_type like 'xb%') = 0);
select tt.err('T8 the statement lines cannot be changed', $q$update pay_statement_lines set amount = 1 where trx_id = 'STMTONLY01'$q$, 'append_only');
