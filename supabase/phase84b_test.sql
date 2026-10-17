-- TEST DATABASE ONLY. Tests for supabase/phase84b_test_project_only_wave1.sql (the guarded test reset knows the phase 87 and Wave 1 tables). Local throwaway Postgres only.
--   build a database through phase 99 (tests/sql/ORDER.txt), then from the repository root:
--   psql -h /tmp -p 5610 -U postgres -d a84bdb -qAt -f supabase/phase84b_test.sql | grep -E 'FAIL|RESULT'
-- The file pastes phase84_test_project_only.sql and phase84b_test_project_only_wave1.sql itself (\i, relative to the repository root) and RUNS A RESET in the database it is given: never run it anywhere else.
-- Test data only (test_* names).
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-00000000084b'
\set u_c '00000000-0000-0000-0000-00000000184b'
\set u_m '00000000-0000-0000-0000-00000000284b'
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
create or replace function tt.cnt(p_table text) returns bigint language plpgsql security definer as $$
declare n bigint; begin execute format('select count(*) from public.%I', p_table) into n; return n; end $$;
create or replace function tt.sell(p_item uuid, p_qty numeric, p_price numeric) returns uuid language plpgsql as $$
begin
  return (record_sale2(gen_random_uuid(), 1, jsonb_build_array(jsonb_build_object('item_id', p_item, 'qty', p_qty, 'price', p_price, 'unit', 'kg')), 0,
          jsonb_build_array(jsonb_build_object('mode', 'cash', 'amount', p_qty * p_price)), null, null, 'retail', null, false) ->> 'id')::uuid;
end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner84b@s.app','{"full_name":"test_owner84b"}'), (:'u_c','test_cashier84b@s.app','{"full_name":"test_cashier84b"}'), (:'u_m','test_manager84b@s.app','{"full_name":"test_manager84b"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_c','salesperson'),(:'u_m','management') on conflict do nothing;
insert into user_locations values (:'u_c',1),(:'u_m',1) on conflict do nothing;

\echo == T0 the OLD file alone: lists written before phase 87 and Wave 1
\i supabase/phase84_test_project_only.sql
select _e_reset_tables() as old_t, _e_reset_protected() as old_p \gset
select tt.chk('T0 old lists: the Wave 1 tables are in neither list', not (_e_reset_tables() && array['w1c_returns','w1e_requests','other_income','entry_approvers']) and not (_e_reset_protected() && array['w1c_returns','w1c_return_class_rules','money_accounts']));

\echo == setup: Wave 1 records through the real functions and by insert
update items set unit='kg', base_unit='kg', tracked=true, category='test_perish84b', sell_price=200 where code='I-001';
select id as i1 from items where code='I-001' \gset
set role authenticated; select tt.as(:'u_o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
select set_user_grant(:'u_m'::uuid,'sale_return') is null as g1 \gset
select stock_production_in(:'i1'::uuid,1,30,now(),null,'test tray',null,100) ->> 'batch_id' as b1 \gset
select _w1c_return_class_set('test_perish84b','no_restock',null,null,null,'test: never put back') is not null as c1 \gset
select tt.as(:'u_c'); select tt.sell(:'i1'::uuid,4,200) as sa \gset
select tt.as(:'u_m');
select _w1c_sale_return(gen_random_uuid(), :'sa'::uuid, format('[{"item_id":"%s","qty":4}]',:'i1')::jsonb, 'damaged', null, 'cash') ->> 'id' as r1 \gset
reset role;
insert into late_sales_held (user_id, location_id, sold_at, payload) values (:'u_c', 1, now() - interval '80 hours', '{}'::jsonb);
insert into customers (name, mobile) values ('test_customer_84b', '01800084000') returning id as cu \gset
insert into open_party_adjustments (kind, party_id, old_amount, new_amount, delta, reason, mode, status) values ('customer', :'cu'::uuid, 0, 10, 10, 'test adjustment', 'direct', 'approved');
insert into other_income (location_id, income_date, head, amount, mode) values (1, tt.today(), 'test_head', 50, 'cash');
insert into period_overrides (scope, user_id, from_date, to_date, reason, started_by, expires_at) values ('both', :'u_m', tt.today()-3, tt.today(), 'test override', :'u_o', now() + interval '1 day');
insert into profit_row_exclusions (cause, source_id, reason) values ('wastage', 'test-1', 'test exclusion reason');
insert into w1e_requests (kind, summary, payload, requested_by) values ('supplier_pay', 'test request', '{}'::jsonb, :'u_m');
insert into w1g_post_runs (via) values ('manual');
insert into w1g_post_watermark (source_type) values ('test_type');
select tt.chk('setup: a return with a write-off exists and every Wave 1 table named below holds a row',
  tt.cnt('w1c_returns')=1 and tt.cnt('w1c_return_lines')>=1 and tt.cnt('late_sales_held')=1 and tt.cnt('open_party_adjustments')=1 and tt.cnt('other_income')=1 and tt.cnt('period_overrides')=1
  and tt.cnt('profit_row_exclusions')=1 and tt.cnt('w1e_requests')=1 and tt.cnt('w1g_post_runs')>=1 and tt.cnt('w1g_post_watermark')=1);
select count(*) as n_rules, (select count(*) from w1c_return_class_rules) as n_cr, (select count(*) from audit_log) as n_audit_before, (select count(*) from items) as n_items from rules \gset

\echo == T1 the OLD reset refuses on this database (this is the finding)
set role authenticated; select tt.as(:'u_o');
select set_rule('allow_test_reset','true') is null as f1 \gset
select tt.err('T1 old lists: the reset stops before touching anything and names the Wave 1 table', $$select _e_test_reset('DELETE ALL TEST DATA')$$, 'w1c_returns');
reset role;
select tt.chk('T1 nothing was cleared by the refused reset', tt.cnt('w1c_returns')=1 and tt.cnt('sales')>=1);

\echo == T2 paste phase84b: the new lists
\i supabase/phase84b_test_project_only_wave1.sql
select tt.chk('T2 the new lists contain every table of the old lists', _e_reset_tables() @> :'old_t'::text[] and _e_reset_protected() @> :'old_p'::text[]);
select tt.chk('T2 the two lists do not overlap (the old function would stop the reset otherwise)', not exists (select 1 from unnest(_e_reset_tables()) a join unnest(_e_reset_protected()) b on a=b));
select tt.chk('T2 every Wave 1 table (w1*_ prefix and the named ones) is in exactly one list',
  not exists (select 1 from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in ('r','p')
                and (c.relname ~ '^w1[a-g]_' or c.relname in ('late_sales_held','open_party_adjustments','other_income','period_overrides','profit_row_exclusions','report_brand_map','report_brand_map_hist'))
                and (c.relname = any (_e_reset_tables())) = (c.relname = any (_e_reset_protected()))));
select tt.chk('T2 the phase 87 tables are classified too (entry_approvers is the one that stopped the old reset)', 'entry_approvers' = any (_e_reset_tables()) and 'money_accounts' = any (_e_reset_protected()));
select tt.chk('T2 setup stays protected: return class rules, staff exit records, mapping types, rules, items, roles, audit_log',
  _e_reset_protected() @> array['w1c_return_class_rules','w1c_exit_keep','w1c_exit_log','w1e_mapping_types','rules','items','roles','audit_log','coa_accounts','locations']);
select tt.chk('T2 no table that points at a cleared table is left outside both lists unsafely (every FK source of a cleared table is itself cleared)',
  not exists (select 1 from pg_constraint k join pg_class cl on cl.oid=k.conrelid join pg_class pl on pl.oid=k.confrelid
               where k.contype='f' and cl.relnamespace='public'::regnamespace and pl.relname = any (_e_reset_tables()) and cl.relname <> all (_e_reset_tables())));
select _e_reset_tables() as t1, _e_reset_protected() as p1 \gset
\i supabase/phase84b_test_project_only_wave1.sql
select tt.chk('T2 pasting the file a second time changes nothing', _e_reset_tables() = :'t1'::text[] and _e_reset_protected() = :'p1'::text[]);

\echo == T3 the reset, with the three checks unchanged
set role authenticated; select tt.as(:'u_m');
select tt.err('T3 not the owner: refused', $$select _e_test_reset('DELETE ALL TEST DATA')$$, 'owner only');
select tt.as(:'u_o');
select tt.err('T3 wrong phrase: refused', $$select _e_test_reset('delete all test data')$$, 'wrong confirmation phrase');
select set_rule('allow_test_reset','false') is null as f0 \gset
select tt.err('T3 switch OFF: refused', $$select _e_test_reset('DELETE ALL TEST DATA')$$, 'allow_test_reset is OFF');
select set_rule('allow_test_reset','true') is null as f2 \gset
select _e_test_reset('DELETE ALL TEST DATA') as res \gset
reset role;
select tt.chk('T3 the reset ran: ok, the flag is OFF again, one line in the reset log', (:'res'::jsonb ->> 'ok')='true' and (:'res'::jsonb ->> 'flag_now')='false' and tt.cnt('_e_reset_log')=1
  and coalesce(rule_on('allow_test_reset'), false) = false);
select tt.chk('T3 the Wave 1 records are gone (returns and lines, held late sale, adjustment, other income, override, exclusion, request, posting runs and watermark)',
  tt.cnt('w1c_returns')=0 and tt.cnt('w1c_return_lines')=0 and tt.cnt('late_sales_held')=0 and tt.cnt('open_party_adjustments')=0 and tt.cnt('other_income')=0 and tt.cnt('period_overrides')=0
  and tt.cnt('profit_row_exclusions')=0 and tt.cnt('w1e_requests')=0 and tt.cnt('w1g_post_runs')=0 and tt.cnt('w1g_post_watermark')=0);
select tt.chk('T3 and the daily records they hang on are gone too (sales, returns, stock movements, journal)', tt.cnt('sales')=0 and tt.cnt('sale_returns')=0 and tt.cnt('stock_ledger')=0 and tt.cnt('journal_entries')=0 and tt.cnt('stock_wastage')=0);
select tt.chk('T3 setup is untouched: the return class rule, rules, items and the audit log are still there',
  (select count(*) from w1c_return_class_rules)=:n_cr and (select count(*) from rules)=:n_rules and (select count(*) from items)=:n_items and (select count(*) from audit_log)>=:n_audit_before);
select tt.chk('T3 the reset log says what was cleared (w1c_returns is in the detail)', (select detail ? 'w1c_returns' and (detail ->> 'w1c_returns')::int = 1 from _e_reset_log order by id desc limit 1));
set role authenticated; select tt.as(:'u_o');
select tt.err('T3 a second reset needs the switch again', $$select _e_test_reset('DELETE ALL TEST DATA')$$, 'allow_test_reset is OFF');
reset role;

\echo == T4 this file is for test projects only
select tt.chk('T4 no demo data: every name in this file starts with test_', not exists (select 1 from profiles where full_name <> '' and full_name not like 'test\_%'));
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
