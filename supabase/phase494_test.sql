-- Phase 494 tests (XC-1): owner daily summary, recipients, send log, receipt continuity, sync alert.
--   psql -d <db> -f supabase/phase494_test.sql   (throwaway database only)
\ir ../tests/sql/xc_head.sql
select set_config('request.jwt.claim.sub', :'o', false);

-- fixtures (replica role: sales and payments are written without their triggers; the code under test runs as normal)
select set_config('session_replication_role', 'replica', false);
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, total, pay_mode, created_by, status)
values (1, 901, tt.today(), now(), '[{"name":"test_item","qty":1,"amount":500,"item_id":null}]', 500, 500, 'cash', :'o', 'done'),
       (1, 903, tt.today(), now(), '[]', 0, 0, 'cash', :'o', 'done'),
       (1, 801, tt.today() - 7, now(), '[]', 300, 300, 'cash', :'o', 'done'),
       (1, 802, tt.today() - 1, now(), '[]', 200, 200, 'cash', :'o', 'done'),
       (3, 701, tt.today() - 7, now() - interval '3 days', '[]', 90, 90, 'cash', :'o', 'done');
insert into sale_payments (sale_id, location_id, kind, mode, wallet, amount, paid_at, created_by)
  select id, 1, 'sale', 'mobile', 'test_wallet', 150, now(), :'o' from sales where receipt = 901 and location_id = 1;
insert into online_orders (order_no, location_id, channel, customer_name, customer_mobile, lines, subtotal, delivery_mode, delivery_date, status, created_by)
values (9001, 1, 'phone', 'test_customer_xc', '01000000000', '[{"name":"test_cake","qty":1,"amount":1000}]', 1000, 'pickup', tt.today() + 1, 'confirmed', :'o');
select set_config('session_replication_role', 'origin', false);

-- T1 defaults: every new switch is OFF, the threshold is blank
select tt.chk('T1 every new switch is OFF by default', not public.rule_on('xc_summary_on') and not public.rule_on('xc_summary_email_on')
  and not public.rule_on('xc_summary_telegram_on') and not public.rule_on('xc_sync_alert_on'));
select tt.chk('T1 the sync threshold is blank (nothing assumed)', public.rule_num('xc_sync_stale_hours') is null);
select tt.chk('T1 the targets read: switch off, no recipients yet', (public.xc_summary_targets() ->> 'on')::boolean = false and jsonb_array_length(public.xc_summary_targets() -> 'recipients') = 0);

-- T2 access
select tt.as(:'st');
select tt.err('T2 a staff user cannot compose the owner summary', format($$select xc_summary_compose(%L, null)$$, tt.today()), 'not allowed');
select tt.chk('T2 a staff user cannot read the targets or the history rows', (select (public.xc_summary_history(5) ->> 'denied')::boolean) is true);
select tt.err('T2 a staff user cannot save a recipient', $$select xc_recipient_save(null, '{"name":"test_x","channel":"email","address":"test_x@example.com"}')$$, 'not allowed');
select tt.as(:'o');

-- T3 recipients (owner only; retire, never delete)
select xc_recipient_save(null, '{"name":"test_owner_mail","channel":"email","address":"test_owner_xc@example.com"}') ->> 'ok' as r1 \gset
select tt.chk('T3 an owner e-mail recipient is saved', :'r1' = 'true');
select id as rec_mail from xc_summary_recipients where name = 'test_owner_mail' \gset
select xc_recipient_save(null, '{"name":"test_owner_tg","channel":"telegram","address":"-1001234567"}') ->> 'ok' as r2 \gset
select id as rec_tg from xc_summary_recipients where name = 'test_owner_tg' \gset
select tt.err('T3 a telegram chat id must be a number', $$select xc_recipient_save(null, '{"name":"test_bad_tg","channel":"telegram","address":"abc"}')$$, 'bad_address');
select tt.err('T3 an e-mail must look like an e-mail', $$select xc_recipient_save(null, '{"name":"test_bad_mail","channel":"email","address":"not-an-email"}')$$, 'bad_address');
select tt.err('T3 an outlet recipient needs a place', $$select xc_recipient_save(null, '{"name":"test_outlet","channel":"email","address":"test_outlet@example.com","scope":"outlet"}')$$, 'location_required');
select xc_recipient_save(null, '{"name":"test_outlet","channel":"email","address":"test_outlet@example.com","scope":"outlet","location_id":3}') ->> 'ok' as r3 \gset
select id as rec_outlet from xc_summary_recipients where name = 'test_outlet' \gset
select tt.err('T3 a recipient cannot be deleted', 'delete from xc_summary_recipients', 'nothing is deleted');
select xc_recipient_save(:'rec_outlet'::bigint, '{"active":false}') ->> 'ok' as r4 \gset
select tt.chk('T3 a recipient is retired, not removed', (select count(*) from xc_summary_recipients where name = 'test_outlet') = 1 and (select active from xc_summary_recipients where name = 'test_outlet') = false);
select xc_recipient_save(:'rec_outlet'::bigint, '{"active":true}') is not null as r5 \gset

-- T4 the composed summary: owner view (company) and outlet view (one place)
select xc_summary_compose(tt.today(), null) as own \gset
select tt.chk('T4 owner: today net 500 (the bill 901; the zero bill is a bill, not a sale amount)', tt.n(:'own'::jsonb -> 'sales' -> 'today', 'net') = 500);
select tt.chk('T4 owner: yesterday net 200 and same weekday last week 390 (company: 300 at place 1 and 90 at place 3)', tt.n(:'own'::jsonb -> 'sales' -> 'yesterday', 'net') = 200 and tt.n(:'own'::jsonb -> 'sales' -> 'last_week', 'net') = 390);
select tt.chk('T4 owner: vs last week is +28.2% (500 against 390)', tt.n(:'own'::jsonb -> 'sales', 'vs_last_week_pct') = 28.2);
select tt.chk('T4 owner: the mobile wallet receipt 150 is in its own line', tt.n(:'own'::jsonb -> 'wallet_receipts', 'total') = 150 and (:'own'::jsonb -> 'wallet_receipts' -> 'by_wallet' -> 0 ->> 'wallet') = 'test_wallet');
select tt.chk('T4 owner: the cake due tomorrow is counted and makes the day not "nothing to report"', (:'own'::jsonb -> 'orders' ->> 'cakes_due_tomorrow')::int = 1 and (:'own'::jsonb ->> 'nothing_to_report')::boolean = false);
select tt.chk('T4 owner: the owner-only block is present (dues, approvals, failures)', :'own'::jsonb -> 'owner_only' ? 'dues' and :'own'::jsonb -> 'owner_only' ? 'failed_intake');
select xc_summary_compose(tt.today(), 1) as out1 \gset
select tt.chk('T4 outlet 1: net 500 and 2 bills (901 and 903), the company block is left out', tt.n(:'out1'::jsonb -> 'sales' -> 'today', 'net') = 500 and tt.n(:'out1'::jsonb -> 'sales' -> 'today', 'bills') = 2 and not (:'out1'::jsonb ? 'owner_only'));
select xc_summary_compose(tt.today(), 2) as out2 \gset
select tt.chk('T4 outlet 2 (no sales, no cakes): zero bills and nothing to report', (:'out2'::jsonb ->> 'nothing_to_report')::boolean = true and tt.n(:'out2'::jsonb -> 'sales' -> 'today', 'bills') = 0);
select tt.err('T4 a future date is refused', format($$select xc_summary_compose(%L, null)$$, tt.today() + 1), 'bad_date');
select tt.err('T4 an unknown place is refused', format($$select xc_summary_compose(%L, 999)$$, tt.today()), 'bad_location');

-- T5 the send log: one successful send per day, recipient and channel; failures may repeat
select xc_summary_record(tt.today(), :'rec_mail'::bigint, 'email', 'sent', 'hash-1', null) ->> 'ok' as l1 \gset
select tt.chk('T5 a sent line is written', :'l1' = 'true');
select tt.err('T5 a second sent line for the same day and recipient is refused', format($$select xc_summary_record(%L, %s, 'email', 'sent', 'hash-2', null)$$, tt.today(), :'rec_mail'), 'duplicate key');
select xc_summary_record(tt.today(), :'rec_mail'::bigint, 'email', 'failed', null, 'smtp timeout') ->> 'ok' as l2 \gset
select tt.chk('T5 a failed line does not block a later send', :'l2' = 'true' and xc_summary_already_sent(tt.today(), :'rec_mail'::bigint, 'email') = true);
select tt.err('T5 the channel must match the recipient', format($$select xc_summary_record(%L, %s, 'telegram', 'sent', null, null)$$, tt.today(), :'rec_mail'), 'channel_mismatch');
select tt.chk('T5 the telegram recipient has nothing sent yet', xc_summary_already_sent(tt.today(), :'rec_tg'::bigint, 'telegram') = false);
select tt.chk('T5 the history lists the lines without addresses', (select jsonb_array_length(public.xc_summary_history(10) -> 'rows')) >= 2
  and not (public.xc_summary_history(10)::text like '%test_owner_xc@example.com%'));

-- T6 receipt continuity and the sync report
select xc_sync_report(null, null, null) as rep \gset
select tt.chk('T6 a blank threshold is reported as "threshold not set"', (select r ->> 'sync_state' from jsonb_array_elements(:'rep'::jsonb -> 'rows') r where (r ->> 'location_id')::int = 1) = 'threshold_not_set');
select tt.chk('T6 place 1 shows a receipt gap (901 and 903 with 902 missing)', (select r ->> 'receipt_state' from jsonb_array_elements(:'rep'::jsonb -> 'rows') r where (r ->> 'location_id')::int = 1) = 'gap');
select tt.chk('T6 place 2 has no sales: receipt state empty, not "ok"', (select r ->> 'receipt_state' from jsonb_array_elements(:'rep'::jsonb -> 'rows') r where (r ->> 'location_id')::int = 2) is null);
select tt.err('T6 a range longer than 120 days is refused', $$select xc_sync_report('2025-01-01', '2026-01-01', null)$$, 'bad_range');

-- T7 the sync alert: off, then the threshold, then the alert (one per outlet per day)
select tt.chk('T7 the alert is skipped while the switch is off', (xc_sync_alert_scan(false) ->> 'skipped') = 'switch_off');
select set_config('session_replication_role', 'replica', false);
update rules set value = 'true'::jsonb where key = 'xc_sync_alert_on';
update rules set value = '6'::jsonb where key = 'xc_sync_stale_hours';
select set_config('session_replication_role', 'origin', false);
select tt.chk('T7 with the switch on and 6 hours: place 3 (last sale 3 days ago) is stale', (xc_sync_alert_scan(true) ->> 'stale_outlets')::int = 1);
select tt.chk('T7 a dry run writes no in-app warning', not exists (select 1 from notifications where kind = 'sync_stale'));
select xc_sync_alert_scan(false) ->> 'stale_outlets' as s1 \gset
select tt.chk('T7 a real run writes one warning for the stale place', (select count(*) from notifications where kind = 'sync_stale' and location_id = 3) = 1);
select xc_sync_alert_scan(false) is not null as s2 \gset
select tt.chk('T7 a second run the same day does not duplicate it', (select count(*) from notifications where kind = 'sync_stale' and location_id = 3) = 1);

-- T8 the paste-safety of the settings: the default rows exist once
select tt.chk('T8 the six settings exist once each', (select count(*) from rules where key in ('xc_summary_on','xc_summary_email_on','xc_summary_telegram_on','xc_summary_times','xc_sync_alert_on','xc_sync_stale_hours')) = 6);

select tt.summary();
