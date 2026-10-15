-- FRESH DB ONLY. Phase 95 tests (Step Drw: cash drawer option; rules cash_drawer_*; grant drawer_nosale; append-only drawer_events; drawer_settings, drawer_event_log, drawer_report).
--   ORDER="phase8 ... phase88 phase90 ... phase93" bash <copy of tests/sql/build_fresh_db.sh with worktree paths> a95db
--   psql -h /tmp -p 5544 -U postgres -d a95db -qAt -f supabase/phase95_test.sql | grep -E 'FAIL|RESULT'      (run from the repo root: it \i's phase95.sql again)
-- Test data only, no person names. Place 1 (main) and place 2.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set v '00000000-0000-0000-0000-000000000003'
\set m '00000000-0000-0000-0000-000000000004'
\set x '00000000-0000-0000-0000-000000000005'
\set y '00000000-0000-0000-0000-000000000006'
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
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','sales2@s.app','{"full_name":"Seller"}'), (:'v','sales3@s.app','{"full_name":"Other Seller"}'),
 (:'m','mgr4@s.app','{"full_name":"Manager"}'), (:'x','norole5@s.app','{"full_name":"No Role"}'), (:'y','sales6@s.app','{"full_name":"Branch Seller"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'v','salesperson'),(:'m','showroom_manager'),(:'y','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'v',1),(:'m',1),(:'y',2) on conflict do nothing;
-- v holds the no-sale grant for place 1 (standing); s does not
insert into user_grants (user_id, grant_code, location_id) values (:'v', 'drawer_nosale', 1);

\echo == T0 shape
select tt.chk('T0 four rules exist with the right kinds and safe defaults (off / after_payment / none / reason on)',
  (select count(*) from rules where key in ('cash_drawer_mode','cash_drawer_when','cash_drawer_method','cash_drawer_no_sale_requires_reason')) = 4
  and rule_txt('cash_drawer_mode') = 'off' and rule_txt('cash_drawer_when') = 'after_payment' and rule_txt('cash_drawer_method') = 'none' and rule_on('cash_drawer_no_sale_requires_reason'));
select tt.chk('T0 mode choices', (select choices from rules where key='cash_drawer_mode') = '["off","on_cash_sale","on_any_sale","manual_only"]'::jsonb);
select tt.chk('T0 method choices incl. planned kiosk_url', (select choices from rules where key='cash_drawer_method') = '["none","browser_print_pulse","web_serial","web_usb","bluetooth","kiosk_url"]'::jsonb);
select tt.chk('T0 all rules have 3 languages and an English hint without Bangla letters',
  (select bool_and(label_bn is not null and label_mix is not null and label_en is not null and hint_en is not null and hint_en !~ '[ঀ-৿]' and label_en !~ '[ঀ-৿]') from rules where key like 'cash_drawer_%'));
select tt.chk('T0 grant drawer_nosale defined; English label has no Bangla', (select count(*) from grant_defs where grant_code='drawer_nosale' and label_en !~ '[ঀ-৿]') = 1);
select tt.chk('T0 table closed to the browser; functions open to signed-in only',
  (select relrowsecurity from pg_class where relname='drawer_events') and not has_table_privilege('authenticated','public.drawer_events','select') and not has_table_privilege('authenticated','public.drawer_events','insert')
  and not has_table_privilege('anon','public.drawer_events','select')
  and has_function_privilege('authenticated','public.drawer_settings(int)','execute') and has_function_privilege('authenticated','public.drawer_report(date,date)','execute')
  and has_function_privilege('authenticated','public.drawer_event_log(uuid,text,int,text,text,text,timestamptz)','execute')
  and not has_function_privilege('anon','public.drawer_settings(int)','execute') and not has_function_privilege('anon','public.drawer_report(date,date)','execute')
  and not has_function_privilege('anon','public.drawer_event_log(uuid,text,int,text,text,text,timestamptz)','execute'));
select tt.chk('T0 drawer_events has no amount / cost / customer column', not exists (select 1 from information_schema.columns where table_name='drawer_events' and column_name ~* 'amount|cost|price|total|mobile|phone|customer|email'));

\echo == settings
set role authenticated; select tt.as(:'s');
select tt.chk('T1 settings default: off, no_sale needs reason, seller cannot report or no-sale', (drawer_settings()->>'mode') = 'off' and (drawer_settings()->>'method') = 'none'
  and (drawer_settings()->>'no_sale_requires_reason')::boolean and not (drawer_settings()->>'can_report')::boolean and not (drawer_settings()->>'can_no_sale')::boolean);
select tt.chk('T1 methods list marks kiosk_url planned and bluetooth experimental', (select count(*) from jsonb_array_elements(drawer_settings()->'methods') e where (e->>'id'='kiosk_url' and e->>'status'='planned') or (e->>'id'='bluetooth' and e->>'status'='experimental')) = 2);
select tt.as(:'v'); select tt.chk('T1 no-sale holder (grant for place 1) sees can_no_sale for place 1 only', (drawer_settings(1)->>'can_no_sale')::boolean and not (drawer_settings(2)->>'can_no_sale')::boolean);
select tt.as(:'x'); select tt.chk('T1 settings hold nothing secret: any active user reads them, no rights come with it', not (drawer_settings()->>'can_no_sale')::boolean and not (drawer_settings()->>'can_report')::boolean);
select tt.as(:'o'); select set_rule('cash_drawer_mode', '"on_cash_sale"') is null as r1 \gset
select set_rule('cash_drawer_method', '"web_serial"') is null as r2 \gset
select tt.chk('T2 owner changes mode/method through set_rule and settings reflect it', (drawer_settings()->>'mode') = 'on_cash_sale' and (drawer_settings()->>'method') = 'web_serial' and (drawer_settings()->>'can_report')::boolean);
select tt.err('T2 invalid mode refused', $$select set_rule('cash_drawer_mode', '"always"')$$, '');
select tt.as(:'s'); select tt.err('T2 seller cannot change the rule', $$select set_rule('cash_drawer_mode', '"off"')$$, '');
select tt.as(:'o'); select set_rule('cash_drawer_mode', null) is null as r3 \gset
select set_rule('cash_drawer_method', null) is null as r4 \gset
select tt.chk('T2 reset to default = off / none', (drawer_settings()->>'mode') = 'off' and (drawer_settings()->>'method') = 'none');

\echo == logging
select tt.as(:'s');
select drawer_event_log('11111111-0000-0000-0000-000000000001', 'auto_open', 1, 'REC-1', null, 'web_serial', null) as a1 \gset
select tt.chk('T3 seller logs auto_open', (:'a1'::jsonb->>'dup')::boolean is false and (select count(*) from (select 1) q) = 1);
select drawer_event_log('11111111-0000-0000-0000-000000000001', 'auto_open', 1, 'REC-1', null, 'web_serial', null) as a2 \gset
select tt.chk('T3 same client id replays as dup, no second row', (:'a2'::jsonb->>'dup')::boolean);
select drawer_event_log('11111111-0000-0000-0000-000000000002', 'failed', 1, null, 'Drawer not connected', 'web_serial', null) as a3 \gset
select tt.chk('T3 seller logs failed', (:'a3'::jsonb->>'dup')::boolean is false);
select tt.err('T4 seller without grant cannot log no_sale_open', $$select drawer_event_log('11111111-0000-0000-0000-000000000003','no_sale_open',1,null,'change request',null,null)$$, 'not allowed');
select drawer_event_log('11111111-0000-0000-0000-000000000004','test_open',1,null,null,'web_serial',null) as tt4 \gset
select tt.chk('T4 seller (setting up the till) may log test_open', (:'tt4'::jsonb->>'id') is not null);
select tt.err('T4 bad event refused', $$select drawer_event_log('11111111-0000-0000-0000-000000000005','steal',1,null,null,null,null)$$, 'bad_event');
select tt.err('T4 null client id refused', $$select drawer_event_log(null,'auto_open',1,null,null,null,null)$$, 'client_required');
select tt.err('T4 unknown place refused', $$select drawer_event_log('11111111-0000-0000-0000-000000000006','auto_open',99,null,null,null,null)$$, 'bad_location');
select tt.err('T4 other place refused', $$select drawer_event_log('11111111-0000-0000-0000-000000000007','auto_open',2,null,null,null,null)$$, 'not allowed');
select tt.as(:'x'); select tt.err('T4 no-role user refused', $$select drawer_event_log('11111111-0000-0000-0000-000000000008','auto_open',1,null,null,null,null)$$, 'not allowed');
select tt.as(:'v');
select tt.err('T5 no-sale without a reason refused (rule on)', $$select drawer_event_log('11111111-0000-0000-0000-000000000009','no_sale_open',1,null,'   ',null,null)$$, 'reason_required');
select tt.err('T5 no-sale grant is for place 1 only', $$select drawer_event_log('11111111-0000-0000-0000-00000000000a','no_sale_open',2,null,'x',null,null)$$, 'not allowed');
select drawer_event_log('11111111-0000-0000-0000-00000000000b', 'no_sale_open', 1, null, 'customer needs change', 'web_serial', null) as n1 \gset
select drawer_event_log('11111111-0000-0000-0000-00000000000c', 'no_sale_open', 1, null, 'swap notes', 'web_serial', now() - interval '1 hour') as n2 \gset
select drawer_event_log('11111111-0000-0000-0000-00000000000d', 'no_sale_open', 1, null, 'x', 'web_serial', now() + interval '3 days') as n3 \gset
select tt.chk('T5 grant holder logs three no-sale opens', (:'n1'::jsonb->>'id') is not null and (:'n2'::jsonb->>'id') is not null and (:'n3'::jsonb->>'id') is not null);
select tt.as(:'o');
select set_rule('cash_drawer_no_sale_requires_reason','false') is null as r5 \gset
select tt.as(:'v');
select drawer_event_log('11111111-0000-0000-0000-00000000000e', 'no_sale_open', 1, null, null, null, null) as n4 \gset
select tt.chk('T5 reason rule off: no-sale without reason is accepted', (:'n4'::jsonb->>'id') is not null);
select tt.as(:'o');
select set_rule('cash_drawer_no_sale_requires_reason', null) is null as r6 \gset
select drawer_event_log('11111111-0000-0000-0000-00000000000f', 'test_open', 1, null, null, 'web_serial', null) as t1 \gset
select tt.chk('T5 owner logs test_open and a no-sale (owner always holds the grant)', (:'t1'::jsonb->>'id') is not null);
select drawer_event_log('11111111-0000-0000-0000-000000000010', 'auto_open', null, 'x', 'p', 'weird method!', null) as t2 \gset
reset role;
select tt.chk('T6 rows landed with server staff id, trimmed fields; unknown method text dropped; wild device time replaced by server time',
  (select count(*) from drawer_events) = 9
  and (select by_staff is not null from drawer_events where client_id='11111111-0000-0000-0000-000000000001')
  and (select method is null from drawer_events where client_id='11111111-0000-0000-0000-000000000010')
  and (select at <= now() + interval '1 minute' from drawer_events where client_id='11111111-0000-0000-0000-00000000000d')
  and (select at < now() - interval '30 minutes' from drawer_events where client_id='11111111-0000-0000-0000-00000000000c'));
select tt.chk('T6 audit_log has a row per event', (select count(*) from audit_log where table_name='drawer_events') = 9);

\echo == append-only
select tt.err('T7 update refused', $$update drawer_events set reason='x'$$, 'append-only');
select tt.err('T7 delete refused', $$delete from drawer_events$$, 'append-only');
select tt.err('T7 truncate refused', $$truncate drawer_events$$, 'append-only');
set role authenticated; select tt.as(:'s');
select tt.err('T7 browser cannot write the table directly', $$insert into drawer_events (client_id, event) values (gen_random_uuid(), 'auto_open')$$, 'permission denied');
select tt.err('T7 browser cannot read the table directly', $$select * from drawer_events$$, 'permission denied');

\echo == report
select tt.err('T8 seller refused', $$select drawer_report()$$, 'not allowed');
select tt.as(:'v'); select tt.err('T8 no-sale holder is not a report reader', $$select drawer_report()$$, 'not allowed');
select tt.as(:'o');
select drawer_report() as rep \gset
-- hand count: no_sale_open = 4 by v (b, c, d, e); auto_open = 2 (seller's one + owner's one: client 01 and 10); test_open 2; failed 1
select tt.chk('T9 totals: 4 no-sale, 2 auto, 2 test, 1 failed', (:'rep'::jsonb#>>'{totals,no_sale_open}')::int = 4 and (:'rep'::jsonb#>>'{totals,auto_open}')::int = 2 and (:'rep'::jsonb#>>'{totals,test_open}')::int = 2 and (:'rep'::jsonb#>>'{totals,failed}')::int = 1);
select tt.chk('T9 by_user lists the heaviest no-sale user first with count 4', (:'rep'::jsonb#>>'{by_user,0,no_sale_open}')::int = 4 and (:'rep'::jsonb#>>'{by_user,0,user_id}') = :'v');
select tt.chk('T9 recent_no_sale carries reasons', jsonb_array_length(:'rep'::jsonb->'recent_no_sale') = 4 and :'rep'::jsonb::text like '%customer needs change%');
select tt.chk('T9 report carries no amount/cost key', :'rep'::jsonb::text !~* '"(amount|cost|price|total_amount)"');
select tt.chk('T9 range with nothing in it is empty, not an error', (drawer_report(current_date - 400 + 100, current_date - 300)#>>'{totals,no_sale_open}')::int = 0);
select tt.err('T9 reversed range refused', $$select drawer_report(current_date, current_date - 3)$$, 'bad_range');
select tt.err('T9 range over a year refused', $$select drawer_report(current_date - 400, current_date)$$, 'range_too_long');
reset role; select tt.as(:'m');
insert into user_grants (user_id, grant_code) values (:'m', 'view_reports');
set role authenticated; select tt.chk('T9 a view_reports holder may read the report', (drawer_report()#>>'{totals,no_sale_open}')::int = 4);

\echo == paste twice
reset role;
\i supabase/phase95.sql
select tt.chk('T10 second paste keeps data, rules and grant (no duplicates)', (select count(*) from drawer_events) = 9 and (select count(*) from rules where key like 'cash_drawer_%') = 4 and (select count(*) from grant_defs where grant_code='drawer_nosale') = 1);
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
