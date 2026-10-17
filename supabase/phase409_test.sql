-- FRESH DB ONLY. Phase 409 tests: sales targets and KPI snapshot tables, settings, grant and target entry (package RPT-B4, R5a).
--   Build a database through phase 99, paste supabase/phase404.sql and phase409.sql (405-408 are not needed), then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase409_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql (hand-computed numbers in its header). Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\set ON_ERROR_STOP off
select tt.today() as td \gset
select date_trunc('month', :'td'::date)::date as m0 \gset
\echo == T0 shape
select tt.chk('T0 two tables with row level security; browsers cannot write them, the internals are closed',
  (select count(*) from pg_class where relname in ('sales_targets','kpi_snapshots') and relrowsecurity) = 2 and not has_table_privilege('authenticated','public.sales_targets','insert') and not has_table_privilege('authenticated','public.kpi_snapshots','update')
  and has_function_privilege('authenticated','public.sales_target_set(int,date,numeric,numeric,text)','execute') and not has_function_privilege('anon','public.sales_target_list(date,date,int,boolean)','execute'));
select tt.chk('T0 the grant exists and no role holds it by default (only the owner may set targets)', exists (select 1 from grant_defs where grant_code = 'sales_target_manage') and not exists (select 1 from rule_grants where grant_code = 'sales_target_manage'));
select tt.chk('T0 the three alert settings exist with a blank default (no limit invented)', (select count(*) from rules where key in ('kpi_alert_sales_drop_pct','kpi_alert_discount_pct','kpi_alert_void_n') and default_value is null and kind = 'number') = 3);

\echo == T1 target entry
select (sales_target_set(1, :'td'::date + 0, 10000, 30, 'test target') ->> 'id')::bigint as tg1 \gset
select tt.chk('T1 any day of the month is stored as the first of that month', (select month = :'m0'::date and amount = 10000 and gp_pct = 30 and status = 'active' and created_staff is not null from sales_targets where id = :'tg1'::bigint));
select sales_target_set(2, :'td'::date, 5000) is not null as w_t2 \gset
select tt.chk('T1 the same call again is a no-op', (sales_target_set(1, :'td'::date, 10000, 30, 'test target') ->> 'dup')::boolean and (select count(*) from sales_targets where location_id = 1) = 1);
select (sales_target_set(1, :'td'::date, 12000, 30, 'test raised') ->> 'replaced')::bigint as old1 \gset
select tt.chk('T1 a new amount retires the old line (kept) and writes a new one: one active, one retired', (select count(*) from sales_targets where location_id = 1 and status = 'active') = 1 and (select status = 'retired' and retired_by is not null from sales_targets where id = :'tg1'::bigint));
select tt.chk('T1 the list shows the active line only; with retired it shows both', jsonb_array_length(public.sales_target_list(:'m0'::date, :'m0'::date, 1) -> 'rows') = 1 and jsonb_array_length(public.sales_target_list(:'m0'::date, :'m0'::date, 1, true) -> 'rows') = 2);
select tt.err('T1 a negative amount is refused', format($$select sales_target_set(1,%L::date,-1)$$, :'td'), 'bad_amount');
select tt.err('T1 a gross-profit % above 100 is refused', format($$select sales_target_set(1,%L::date,1,120)$$, :'td'), 'bad_gp_pct');
select tt.err('T1 a missing month is refused', $$select sales_target_set(1,null,100)$$, 'bad_date');
select tt.err('T1 an unknown place is refused', format($$select sales_target_set(999,%L::date,100)$$, :'td'), 'bad_location');
select tt.as(:'fac');
select tt.err('T1 the factory in-charge cannot set a target (server refusal)', format($$select sales_target_set(5,%L::date,100)$$, :'td'), 'not allowed');
select tt.as(:'o');
insert into user_grants (user_id, grant_code) values (:'rep', 'sales_target_manage'), (:'rep', 'report_sales') on conflict do nothing;
select tt.as(:'rep');
select tt.chk('T1 a holder of the grant can set a target for a place of his own', (sales_target_set(5, :'td'::date, 700) ->> 'month')::date = :'m0'::date);
select tt.err('T1 ... but not for a place that is not his', format($$select sales_target_set(2,%L::date,100)$$, :'td'), 'not allowed');
select tt.err('T1 retiring needs a reason', $$select sales_target_retire((select id from sales_targets where location_id = 1 and status = 'active'), 'x')$$, 'note_required');
select tt.as(:'o');
delete from user_grants where user_id = :'rep' and grant_code = 'sales_target_manage';
select (sales_target_retire((select id from sales_targets where location_id = 5 and status = 'active'), 'test: not needed') ->> 'status') as w_r \gset
select tt.chk('T1 a retired target stays as a row', (select status = 'retired' and retired_note like 'test:%' from sales_targets where location_id = 5));
select tt.chk('T1 audit lines exist for targets', (select count(*) from audit_log where table_name = 'sales_targets') >= 4);


\echo == T2 paste twice
\ir phase409.sql
select tt.chk('T2 pasting phase 409 again keeps the data and the settings', (select count(*) from sales_targets) = 4 and (select count(*) from rules where key like 'kpi_alert%') = 3);

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
