-- FRESH DB ONLY. Phase 306 tests (CRM-C: customer scores, RFM labels, settings, rights, scheduled refresh, patch helper).
--   build: phases 8..98 (tests/sql/ORDER.txt), then phase306 (the DB may also carry 307/308); run: psql -h /tmp -p 5573 -U postgres -d <db> -qAt -f supabase/phase306_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names, tests/sql/crmc_fixture.sql). Numbers are hand-computed in the fixture comments and below.
\set ON_ERROR_STOP off
\ir ../tests/sql/crmc_fixture.sql
truncate tt.res;
create or replace function tt.err_role(p_name text, p_role text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute format('set local role %I', p_role); execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
grant execute on function tt.err_role(text, text, text, text) to authenticated, anon;
create or replace function tt.snap() returns text language plpgsql security definer as $$
declare r text := ''; t text;
begin
  foreach t in array array['sales','sale_payments','sale_returns','customers','journal_entries','journal_lines','customer_points_ledger','notify_optin','stock_ledger'] loop
    execute format('select md5(coalesce(string_agg(x::text, '''' order by x::text), '''')) from public.%I x', t) into t;
    r := r || t;
  end loop;
  return md5(r);
end $$;
select tt.today() as t \gset
select tt.snap() as snap0 \gset

\echo == T0 shape, defaults, rights, nothing shared patched
select tt.chk('T0 phase306 present', to_regprocedure('public._crmc_present()') is not null);
select tt.chk('T0 eleven rules with safe defaults (segments OFF, cut-offs and winback blank, batch 2000, schedule OFF/blank, cap 5000, export OFF/blank)',
  (select count(*) from rules where key in ('crm_segments_on','crm_rfm_recent_days','crm_rfm_frequency_min','crm_rfm_spend_min','crm_winback_days','crm_metrics_batch','crm_metrics_schedule_on','crm_metrics_schedule_hours','crm_segment_max_members','crm_seg_export_on','crm_seg_export_max_rows')) = 11
  and not rule_on('crm_segments_on') and rule_num('crm_rfm_recent_days') is null and rule_num('crm_rfm_frequency_min') is null and rule_num('crm_rfm_spend_min') is null and rule_num('crm_winback_days') is null
  and rule_num('crm_metrics_batch') = 2000 and not rule_on('crm_metrics_schedule_on') and rule_num('crm_metrics_schedule_hours') is null and rule_num('crm_segment_max_members') = 5000
  and not rule_on('crm_seg_export_on') and rule_num('crm_seg_export_max_rows') is null);
select tt.chk('T0 the rule texts are English only, all three language slots equal',
  not exists (select 1 from rules where module = 'crm' and key in ('crm_segments_on','crm_rfm_recent_days','crm_rfm_frequency_min','crm_rfm_spend_min','crm_winback_days','crm_metrics_batch','crm_metrics_schedule_on','crm_metrics_schedule_hours','crm_segment_max_members','crm_seg_export_on','crm_seg_export_max_rows')
        and (label_en ~ '[^\x01-\x7f]' or hint_en ~ '[^\x01-\x7f]' or label_bn is distinct from label_en or hint_bn is distinct from hint_en)));
select tt.chk('T0 four rights exist and nobody but the owner holds them yet',
  (select count(*) from grant_defs where grant_code in ('crm_view','crm_contact_view','crm_export','crm_settings_edit')) = 4
  and not exists (select 1 from rule_grants where grant_code like 'crm\_%'));
select tt.chk('T0 the score cache and its run log are closed to browsers; helpers are closed; the screen functions are open to signed-in users only',
  not has_table_privilege('authenticated', 'public.crm_metrics', 'select') and not has_table_privilege('anon', 'public.crm_metrics_runs', 'select')
  and not has_function_privilege('authenticated', 'public._crmc_scored(date)', 'execute') and not has_function_privilege('authenticated', 'public._crmc_refresh_core(boolean,int)', 'execute')
  and not has_function_privilege('authenticated', 'public._crmc_patch(regprocedure,text[],text)', 'execute')
  and has_function_privilege('authenticated', 'public.crmc_metrics_refresh(boolean,int)', 'execute') and not has_function_privilege('anon', 'public.crmc_metrics_refresh(boolean,int)', 'execute')
  and not has_function_privilege('anon', 'public.crmc_me()', 'execute'));
select tt.chk('T0 no shared function carries any CRM-C text (notify_scan, record_sale2, customer_dues, _cust_bal untouched)',
  (select count(*) from pg_proc where proname in ('notify_scan','record_sale2','customer_dues','_cust_bal','customer_directory','_cust_stats43','daily_digest') and pg_get_functiondef(oid) ilike '%crmc%') = 0);

\echo == T1 who may do what (server side)
set role authenticated;
select tt.as(:'u_c');
select tt.err('T1 plain cashier cannot read status', $$select crmc_metrics_status()$$, 'not allowed');
select tt.err('T1 plain cashier cannot refresh', $$select crmc_metrics_refresh(false)$$, 'not allowed');
select tt.chk('T1 plain cashier sees no right in crmc_me', (select not (crmc_me()->>'view')::boolean and not (crmc_me()->>'edit')::boolean and not (crmc_me()->>'run')::boolean));
select tt.as(:'u_v');
select tt.chk('T1 viewer (crm_view) can read the status', (crmc_metrics_status()->>'customers')::int = 7);
select tt.err('T1 viewer cannot refresh', $$select crmc_metrics_refresh(false)$$, 'not allowed');
select tt.err('T1 viewer cannot even dry-run a refresh', $$select crmc_metrics_refresh(true)$$, 'not allowed');
select tt.as(:'u_x');
select tt.err('T1 exporter without view/edit grant cannot refresh', $$select crmc_metrics_refresh(false)$$, 'not allowed');
select tt.as(:'u_e');
select tt.chk('T1 editor (crm_settings_edit) may dry-run', (crmc_metrics_refresh(true)->>'dry')::boolean);
select tt.as(:'u_m');
select tt.chk('T1 customer manager may dry-run', (crmc_metrics_refresh(true)->>'stale')::int = 7);
reset role;
select tt.err_role('T1 anonymous is refused (no execute right)', 'anon', $$select public.crmc_me()$$, 'permission denied');
set role authenticated; select set_config('request.jwt.claim.sub', '', false);
select tt.err('T1 signed in but unknown user is refused', $$select crmc_metrics_status()$$, 'not allowed');
reset role;

\echo == T2 a dry run writes nothing; only active customers are in scope (7 active, 1 inactive)
select tt.as(:'u_o');
select tt.chk('T2 dry run says 7 stale, would process 7, and the cache and run log stay empty',
  (crmc_metrics_refresh(true)->>'stale')::int = 7 and (crmc_metrics_refresh(true)->>'would_process')::int = 7 and (select count(*) from crm_metrics) = 0 and (select count(*) from crm_metrics_runs) = 0);
select tt.err('T2 limit 0 is refused', $$select crmc_metrics_refresh(false, 0)$$, 'bad_value');
select tt.err('T2 limit above the technical maximum is refused', $$select crmc_metrics_refresh(false, 20001)$$, 'bad_value');

\echo == T3 capped runs: 3 + 3 + 1, then nothing is left; each real run is logged
select tt.chk('T3 first run 3 done 4 left', (select (r->>'processed')::int = 3 and (r->>'remaining')::int = 4 from (select crmc_metrics_refresh(false, 3) r) z));
select tt.chk('T3 second run 3 done 1 left', (select (r->>'processed')::int = 3 and (r->>'remaining')::int = 1 from (select crmc_metrics_refresh(false, 3) r) z));
select tt.chk('T3 third run 1 done 0 left', (select (r->>'processed')::int = 1 and (r->>'remaining')::int = 0 from (select crmc_metrics_refresh(false, 3) r) z));
select tt.chk('T3 a fourth run finds nothing to do (idempotent)', (select (r->>'processed')::int = 0 and (r->>'remaining')::int = 0 from (select crmc_metrics_refresh(false) r) z));
select tt.chk('T3 four manual runs logged, four audit lines', (select count(*) from crm_metrics_runs where kind = 'manual') = 4 and (select count(*) from audit_log where action = 'crm_scores_refresh') = 4);
select tt.chk('T3 the inactive customer has no score row; the other seven do', (select count(*) from crm_metrics) = 7 and not exists (select 1 from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a7'));

\echo == T4 numbers per customer (hand computed in the fixture)
select tt.chk('T4 champ: 3 orders, 3 in 12m, 600 net, last visit T-5, 200 average bill, 0 due, 50 points, outlet 1, two top items',
  exists (select 1 from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a1' and orders_total = 3 and orders_12m = 3 and lifetime_spend = 600 and spend_12m = 600 and avg_bill = 200
          and due_amount = 0 and points = 50 and last_visit = :'t'::date - 5 and first_visit = :'t'::date - 20 and top_location_id = 1 and outlet_ids = '{1}' and jsonb_array_length(top_items) = 2));
select tt.chk('T4 champ top item is item b (380 of amount: 80 + 300) before item a (220)',
  (select top_items -> 0 ->> 'item_id' from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a1') = 'aaaaaaaa-0000-0000-0000-0000000000a2'
  and (select (top_items -> 0 ->> 'amount')::numeric from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a1') = 380);
select tt.chk('T4 at-risk: 2 orders, gross 400, return 50 -> net 350 (12m too), average bill 200, last visit T-90',
  exists (select 1 from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a2' and orders_total = 2 and gross_spend = 400 and returns_total = 50 and lifetime_spend = 350 and spend_12m = 350 and avg_bill = 200 and last_visit = :'t'::date - 90));
select tt.chk('T4 one-time: 1 order of 80 at outlet 2', exists (select 1 from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a3' and orders_total = 1 and lifetime_spend = 80 and top_location_id = 2 and outlet_ids = '{2}'));
select tt.chk('T4 old: one order 400 days ago counts in the total (500) but not in 12 months; no outlet', exists (select 1 from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a4' and orders_total = 1 and orders_12m = 0 and lifetime_spend = 500 and spend_12m = 0 and outlet_ids = '{}' and top_location_id is null));
select tt.chk('T4 never: a row of zeros, no last visit, no average bill', exists (select 1 from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a5' and orders_total = 0 and lifetime_spend = 0 and last_visit is null and avg_bill is null));
select tt.chk('T4 void sale ignored: 1 order of 60', exists (select 1 from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a6' and orders_total = 1 and lifetime_spend = 60));
select tt.chk('T4 due customer owes 600 (1000 sale, 400 paid)', exists (select 1 from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a8' and due_amount = 600 and lifetime_spend = 1000));
select tt.chk('T4 lifetime spend, orders and orders in 12 months equal the existing customer figures (_cust_stats43) for every scored customer',
  not exists (select 1 from crm_metrics m, lateral _cust_stats43(m.customer_id, false) s where m.lifetime_spend is distinct from s.spend or m.orders_total is distinct from s.orders or m.orders_12m is distinct from s.orders_12m));
select tt.chk('T4 due amount equals the existing balance function for every scored customer', not exists (select 1 from crm_metrics m where m.due_amount is distinct from greatest(_cust_bal(m.customer_id), 0)));

\echo == T5 labels: standard mode equals the existing Customer value report (m1_rfm)
select tt.chk('T5 mode is standard while the three cut-offs are blank', (select mode from _crmc_cfg()) = 'standard');
select tt.chk('T5 standard labels: champ Champion, at-risk At-risk, onetime/void/due One-time, old Inactive, never No purchases',
  (select string_agg(c.name || '=' || s.label, ',' order by c.name) from _crmc_scored() s join customers c on c.id = s.customer_id)
  = 'test_cust_atrisk=At-risk,test_cust_champ=Champion,test_cust_due=One-time,test_cust_never=No purchases,test_cust_old=Inactive,test_cust_onetime=One-time,test_cust_void=One-time');
select tt.chk('T5 for the five customers the report lists, the label is the report segment',
  (select count(*) from _r3q_m1_rfm(:'t'::date - 364, :'t'::date, (select array_agg(id) from locations), '{}'::jsonb) r join _crmc_scored() s on s.customer_id = (r->>'customer_id')::uuid and s.label = r->>'segment') = 5
  and (select count(*) from _r3q_m1_rfm(:'t'::date - 364, :'t'::date, (select array_agg(id) from locations), '{}'::jsonb)) = 6);   -- the report also lists the inactive customer, which scores do not

\echo == T6 settings: owner only, bounds, owner mode, one blank brings the standard labels back
set role authenticated; select tt.as(:'u_e');
select tt.err('T6 a non-owner cannot change a rule', $$select set_rule('crm_rfm_recent_days', '30'::jsonb)$$, 'not allowed');
select tt.as(:'u_o');
select tt.err('T6 recent days 0 refused', $$select set_rule('crm_rfm_recent_days', '0'::jsonb)$$, 'bad_value');
select tt.err('T6 recent days 4000 refused', $$select set_rule('crm_rfm_recent_days', '4000'::jsonb)$$, 'bad_value');
select tt.err('T6 text for a number refused', $$select set_rule('crm_rfm_frequency_min', '"two"'::jsonb)$$, 'bad_value');
select tt.err('T6 batch below the technical minimum refused', $$select set_rule('crm_metrics_batch', '5'::jsonb)$$, 'bad_value');
select set_rule('crm_rfm_recent_days', '30'::jsonb), set_rule('crm_rfm_frequency_min', '2'::jsonb);
select tt.chk('T6 two of three set = still standard mode, status lists the missing one', (crmc_metrics_status()->>'mode') = 'standard' and crmc_metrics_status()->'missing' = '["crm_rfm_spend_min"]'::jsonb);
select set_rule('crm_rfm_spend_min', '400'::jsonb);
reset role; select tt.as(:'u_o');
select tt.chk('T6 owner mode labels: champ Champion, at-risk At risk, onetime Drifting, old Lost, never No purchases, void New, due Big spender',
  (select string_agg(c.name || '=' || s.label, ',' order by c.name) from _crmc_scored() s join customers c on c.id = s.customer_id)
  = 'test_cust_atrisk=At risk,test_cust_champ=Champion,test_cust_due=Big spender,test_cust_never=No purchases,test_cust_old=Lost,test_cust_onetime=Drifting,test_cust_void=New');
select tt.chk('T6 r/f/m flags for the champ are true,true,true; for the at-risk customer false,true,false',
  (select r_ok and f_ok and m_ok from _crmc_scored() where customer_id = '00000000-0000-0000-0000-00000000c3a1')
  and (select not r_ok and f_ok and not m_ok from _crmc_scored() where customer_id = '00000000-0000-0000-0000-00000000c3a2'));
select set_rule('crm_rfm_spend_min', '700'::jsonb);
select tt.chk('T6 a changed cut-off applies at once without a rebuild (spend 700 -> champ becomes Loyal)', (select label from _crmc_scored() where customer_id = '00000000-0000-0000-0000-00000000c3a1') = 'Loyal');
select set_rule('crm_rfm_spend_min', null), set_rule('crm_rfm_recent_days', null), set_rule('crm_rfm_frequency_min', null);
select tt.chk('T6 all blank again = standard labels again', (select mode from _crmc_cfg()) = 'standard' and (select label from _crmc_scored() where customer_id = '00000000-0000-0000-0000-00000000c3a1') = 'Champion');

\echo == T7 existing data is untouched by all of the above
select tt.chk('T7 sales, payments, returns, customers, journal, points, opt-in and stock ledger are byte for byte as before', tt.snap() = :'snap0');

\echo == T8 stale detection and incremental refresh
insert into sales (id, location_id, receipt, sale_date, sold_at, lines, subtotal, total, pay_mode, customer_id, status, created_by)
  values ('5a000000-0000-0000-0000-0000000000d1', 2, 9100, :'t'::date, now(), '[]', 25, 25, 'cash', '00000000-0000-0000-0000-00000000c3a3', 'done', :'u_o');
select tt.chk('T8 a newer sale makes exactly that customer stale', (select array_agg(x) from _crmc_stale(null) x) = array['00000000-0000-0000-0000-00000000c3a3'::uuid]);
select tt.chk('T8 dry run says 1', (crmc_metrics_refresh(true)->>'stale')::int = 1);
select crmc_metrics_refresh(false) ->> 'processed' as p8 \gset
select tt.chk('T8 refresh does 1 and the customer now has 2 orders, 105', :p8 = 1 and exists (select 1 from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a3' and orders_total = 2 and lifetime_spend = 105));
update crm_metrics set computed_on = computed_on - 1 where customer_id = '00000000-0000-0000-0000-00000000c3a4';
select tt.chk('T8 a score computed on an earlier day is stale again', (select array_agg(x) from _crmc_stale(null) x) = array['00000000-0000-0000-0000-00000000c3a4'::uuid]);
select crmc_metrics_refresh(false);
insert into sale_returns (sale_id, location_id, customer_id, lines, amount, credit_amount, refund_amount, reason_code, status, created_at)
  values ('5a000000-0000-0000-0000-000000000001', 1, '00000000-0000-0000-0000-00000000c3a1', '[]'::jsonb, 10, 10, 0, 'test', 'done', now());
select tt.chk('T8 a newer return makes the customer stale and the refresh nets it (590)', (select array_agg(x) from _crmc_stale(null) x) = array['00000000-0000-0000-0000-00000000c3a1'::uuid]
  );
select crmc_metrics_refresh(false) ->> 'processed' as p9 \gset
select tt.chk('T8 the refresh does 1 and nets the return (590)', :p9 = 1 and (select lifetime_spend from crm_metrics where customer_id = '00000000-0000-0000-0000-00000000c3a1') = 590);

\echo == T9 scheduled run: OFF does nothing, blank hours blocks, capped, continues until done, then waits
select count(*) as runs0 from crm_metrics_runs \gset
set role authenticated; select tt.as(:'u_bot');
select tt.chk('T9 switched OFF: nothing happens (the default)', (crmc_scheduled_run()->>'off')::boolean);
reset role; select tt.chk('T9 switched OFF: no run was logged', (select count(*) from crm_metrics_runs) = :runs0); set role authenticated;
select tt.as(:'u_c');
select tt.err('T9 a plain cashier cannot call the scheduled run', $$select crmc_scheduled_run()$$, 'not allowed');
select tt.as(:'u_e');
select tt.err('T9 an editor cannot call the scheduled run (ops bot or owner only)', $$select crmc_scheduled_run()$$, 'not allowed');
select tt.as(:'u_o'); select set_rule('crm_metrics_schedule_on', 'true'::jsonb);
select tt.as(:'u_bot');
select tt.chk('T9 ON but hours blank: blocked', crmc_scheduled_run() = '{"blocked": "set_hours"}'::jsonb);
reset role; select tt.chk('T9 ON but hours blank: nothing written', (select count(*) from crm_metrics_runs) = :runs0); select tt.as(:'u_o');
set role authenticated; select set_rule('crm_metrics_schedule_hours', '6'::jsonb), set_rule('crm_metrics_batch', '100'::jsonb); reset role;
insert into customers (mobile, name) select '0181' || lpad(g::text, 7, '0'), 'test_bulk_' || g from generate_series(1, 130) g;
select tt.as(:'u_bot'); set role authenticated;
select tt.chk('T9 first scheduled run is capped at the batch (100) and says 30 left', (select (r->>'processed')::int = 100 and (r->>'remaining')::int = 30 from (select crmc_scheduled_run() r) z));
select tt.chk('T9 it continues at once while something is left (30 done, 0 left)', (select (r->>'processed')::int = 30 and (r->>'remaining')::int = 0 from (select crmc_scheduled_run() r) z));
select tt.chk('T9 then it waits for the hours', crmc_scheduled_run() ->> 'skipped' = 'not_due');
reset role;
select tt.chk('T9 scheduled runs are logged (2) with the bot as the user', (select count(*) from crm_metrics_runs where kind = 'scheduled') = 2 and (select count(*) from crm_metrics_runs where kind = 'scheduled' and by_user = :'u_bot'::uuid) = 2);
select tt.chk('T9 all 137 active customers are scored (7 + 130)', (select count(*) from crm_metrics) = 137);

\echo == T10 helpers: next birthday (Feb 29), mask
select tt.chk('T10 days to next: same day 0', _crmc_days_to_next(date '1990-10-17', date '2026-10-17') = 0);
select tt.chk('T10 days to next: tomorrow 1, yesterday 364', _crmc_days_to_next(date '1990-10-18', date '2026-10-17') = 1 and _crmc_days_to_next(date '1990-10-16', date '2026-10-17') = 364);
select tt.chk('T10 Feb 29 birthday on 2026-03-01 -> Feb 28 2027 = 364 days; on 2028-02-20 -> 9', _crmc_days_to_next(date '2024-02-29', date '2026-03-01') = 364 and _crmc_days_to_next(date '2024-02-29', date '2028-02-20') = 9);
select tt.chk('T10 null in, null out', _crmc_days_to_next(null, date '2026-10-17') is null);
select tt.chk('T10 default mask keeps first three and last two digits', _crmc_mask('01712345678') = '017******78' and _crmc_mask('12345') = '*****' and _crmc_mask(null) is null);
insert into rules (key, module, kind, default_value, label_bn, label_mix, label_en) values ('crm_mask_style', 'crm', 'text', '"last4"'::jsonb, 'test', 'test', 'test');
select tt.chk('T10 mask style last4', _crmc_mask('01712345678') = '*******5678');
update rules set default_value = '"hidden"'::jsonb where key = 'crm_mask_style';
select tt.chk('T10 mask style hidden', _crmc_mask('01712345678') = '****');
delete from rules where key = 'crm_mask_style';

\echo == T11 the exact-text patch helper (used for the one optional hook)
create or replace function tt.pf() returns text language plpgsql as $$ begin return 'a'; end $$;
create or replace function tt.pf2() returns text language plpgsql as $$ begin perform 1; perform 1; return 'b'; end $$;
select tt.chk('T11 patch applies once (true) and carries the marker', _crmc_patch('tt.pf()'::regprocedure, array[E'return ''a'';', E'return ''a''; /* bosCRMC */'], 'bosCRMC') and pg_get_functiondef('tt.pf()'::regprocedure) like '%bosCRMC%');
select tt.chk('T11 second call patches nothing (false) and the function still works', not _crmc_patch('tt.pf()'::regprocedure, array[E'return ''a'';', E'return ''a''; /* bosCRMC */'], 'bosCRMC') and tt.pf() = 'a');
select tt.err('T11 missing site refused', $$select _crmc_patch('tt.pf2()'::regprocedure, array['no such text', 'x'], 'bosCRMC')$$, 'patch site not found');
select tt.err('T11 site that is not unique refused', $$select _crmc_patch('tt.pf2()'::regprocedure, array['perform 1;', 'perform 2; /* bosCRMC */'], 'bosCRMC')$$, 'not unique');
select tt.err('T11 bad marker refused', $$select _crmc_patch('tt.pf2()'::regprocedure, array['return', 'return'], 'bos87')$$, 'bad marker');

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
