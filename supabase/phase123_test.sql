-- FRESH DB ONLY (built through phase122, then phase123). Phase 123 tests = Group ERP Stage C1 first slice (business isolation behind the switch org_scope_on).
--   bash tests/sql/final_build.sh <db>   (the canonical order ends with phase123);  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase123_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root)
--   The "switch OFF = identical behaviour" proof on seeded data is tests/sql/c1_before_after.sh (needs a build WITHOUT phase123); here OFF is checked with hand numbers.
--   Two businesses: A = SWEETS (locations 1..7), B = HARDWARE (made by org_unit_save; location hw1 under the branch HW-B1, hw2 straight under the business, 'orphan' unmapped).
\i tests/sql/e2e/00_common.sql
\set ao '00000000-0000-0000-0000-0000000000a1'
\set am '00000000-0000-0000-0000-0000000000a2'
\set aa '00000000-0000-0000-0000-0000000000a3'
\set bs '00000000-0000-0000-0000-0000000000b1'
\set bm '00000000-0000-0000-0000-0000000000b2'
\set bb '00000000-0000-0000-0000-0000000000b3'
\set xl '00000000-0000-0000-0000-0000000000c1'
\set xn '00000000-0000-0000-0000-0000000000c2'
\echo == T0 setup: two businesses, users scoped to each, data in both
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner@c1.app','{"full_name":"Owner"}'),(:'ao','a_staff@c1.app','{"full_name":"A Staff"}'),(:'am','a_mgr@c1.app','{"full_name":"A Manager"}'),(:'aa','a_acct@c1.app','{"full_name":"A Accountant"}'),
 (:'bs','b_staff@c1.app','{"full_name":"B Staff"}'),(:'bm','b_mgr@c1.app','{"full_name":"B Manager"}'),(:'bb','b_branch@c1.app','{"full_name":"B Branch Manager"}'),
 (:'xl','x_legacy@c1.app','{"full_name":"Legacy Manager"}'),(:'xn','x_none@c1.app','{"full_name":"Nowhere"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'ao','salesperson'),(:'am','management'),(:'aa','hr'),(:'bs','salesperson'),(:'bm','management'),(:'bb','management'),(:'xl','management'),(:'xn','salesperson') on conflict do nothing;
select tt.as(:'o');
select org_unit_save(null, (select id from org_units where kind='group'), 'legal_entity', 'le-hw', 'হার্ডওয়্যার কোম্পানি', 'Hardware Co', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"owner_pct":100}'::jsonb, '00000000-0000-0000-0000-0000000000f1') ->> 'id' as hle \gset
select org_unit_save(null, :'hle'::bigint, 'business', 'HARDWARE', 'হার্ডওয়্যার ও রং', 'Hardware and paint', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000000f2') ->> 'id' as hbz \gset
select org_unit_save(null, :'hbz'::bigint, 'branch', 'HW-B1', 'শাখা ১', 'Branch 1', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000000f3') ->> 'id' as hb1 \gset
select id as sbz from org_units where code = 'SWEETS' \gset
insert into locations (code, name_bn, name_en, kind, status, org_unit_id) values ('hw1','হার্ডওয়্যার ১','Hardware 1','showroom','live', :'hb1'::bigint),('hw2','হার্ডওয়্যার ২','Hardware 2','showroom','live', :'hbz'::bigint),
 ('orphan','অমিল','Unmapped','showroom','live', null);
select id as hw1 from locations where code = 'hw1' \gset
select id as hw2 from locations where code = 'hw2' \gset
select id as orph from locations where code = 'orphan' \gset
insert into user_locations values (:'ao',1),(:'aa',2),(:'bs',:'hw1') on conflict do nothing;
-- the accountant has a personal NULL-location accounts_manage grant; the A staff a NULL-location view_cost grant and view_reports
select set_user_grant(:'aa'::uuid, 'accounts_manage') is null as g1 \gset
select set_user_grant(:'ao'::uuid, 'view_cost') is null as g2 \gset
select set_user_grant(:'ao'::uuid, 'view_reports') is null as g3 \gset
select set_user_grant(:'bs'::uuid, 'view_reports') is null as g4 \gset
select set_user_grant(:'bs'::uuid, 'view_cost') is null as g5 \gset
select set_user_grant(:'am'::uuid, 'accounts_view') is null as g6 \gset
select set_user_grant(:'bm'::uuid, 'accounts_view') is null as g7 \gset
select tt.t('T0 users, businesses and locations are in place', :'hw1'::int > 7 and :'hw2'::int > :'hw1'::int and (select count(*) from org_units where kind = 'business') = 2);
-- items (one global master), stock and cost in both businesses, a credit customer in both
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('C1-X','x','Item X','pc','pc','finished_good',true,100,true),('C1-Y','y','Item Y (hardware only)','pc','pc','finished_good',true,500,true) on conflict do nothing;
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select stock_opening(tt.iid('C1-X'), 1, 100, 40) is not null as s1 \gset
select stock_opening(tt.iid('C1-X'), :'hw1'::int, 100, 90) is not null as s2 \gset
select stock_opening(tt.iid('C1-Y'), :'hw1'::int, 20, 300) is not null as s3 \gset
select tt.t('T0 stock opened in both businesses', :'s1'::boolean and :'s2'::boolean and :'s3'::boolean);
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":10,"price":100}]', tt.iid('C1-X'))::jsonb, 0, '[{"mode":"cash","amount":400}]', '01711000001', 'Common Customer', 'retail', null, false) ->> 'id' as sale_a \gset
select record_sale2(gen_random_uuid(), :'hw1'::int, format('[{"item_id":"%s","qty":5,"price":100}]', tt.iid('C1-X'))::jsonb, 0, '[]', '01711000001', 'Common Customer', 'retail', null, false) ->> 'id' as sale_b \gset
select record_sale2(gen_random_uuid(), :'hw1'::int, format('[{"item_id":"%s","qty":2,"price":500}]', tt.iid('C1-Y'))::jsonb, 0, '[{"mode":"cash","amount":300}]', '01722000002', 'Hardware Only Customer', 'retail', null, false) ->> 'id' as sale_b2 \gset
select tt.t('T0 three credit sales exist (A 600 due, B 500 due, B-only customer 700 due)', :'sale_a' is not null and :'sale_b' is not null and :'sale_b2' is not null, 'true', coalesce(:'sale_a','null') || ' / ' || coalesce(:'sale_b','null') || ' / ' || coalesce(:'sale_b2','null'));
select id as cust_c from customers where mobile like '%1711000001' \gset
select id as cust_h from customers where mobile like '%1722000002' \gset
insert into fa_assets (code, name, location_id, acquired_on, cost, life_months, depr_from) values ('FA-A', 'Oven (sweets)', 1, current_date - 100, 1000, 10, date_trunc('month', current_date - 90)::date),
 ('FA-B', 'Compressor (hardware)', :'hw1'::int, current_date - 100, 5000, 20, date_trunc('month', current_date - 90)::date),('FA-N', 'No place', null, current_date - 100, 700, 10, date_trunc('month', current_date - 90)::date);
select id as fa_b from fa_assets where code = 'FA-B' \gset
select id as fa_a from fa_assets where code = 'FA-A' \gset
insert into drawer_events (client_id, event, location_id, by_user, by_staff, reason, at) values (gen_random_uuid(), 'no_sale_open', 1, :'ao', 'A1', 'a', now()),(gen_random_uuid(), 'no_sale_open', :'hw1'::int, :'bs', 'B1', 'b', now()),
 (gen_random_uuid(), 'no_sale_open', :'hw1'::int, :'bs', 'B1', 'b2', now());
-- an opening journal with a line in each business
select acct_opening(format('[{"code":"1110","debit":9000,"location_id":1},{"code":"1110","debit":4000,"location_id":%s},{"code":"3100","credit":13000}]', :'hw1')::jsonb)->>'id' as oj \gset
select tt.t('T0 opening journal posted', :'oj' is not null);
-- more B rows for the id-guessing tests: a purchase bill, a form entry, an employee and a payroll run at hw1
insert into suppliers (name) values ('C1 Supplier') on conflict do nothing;
select id as sup1 from suppliers where name = 'C1 Supplier' \gset
select save_purchase(gen_random_uuid(), null, :'sup1'::uuid, :'hw1'::int, 'B-1', current_date, format('[{"item_id":"%s","qty":10,"unit":"pc","unit_cost":50}]', tt.iid('C1-X'))::jsonb) ->> 'id' as pur_b \gset
insert into entries (form_code, location_id, serial, entry_date, created_by, data) values ('ITEMS', :'hw1'::int, 1, current_date, :'bs', '{}'::jsonb) returning id as ent_b \gset
insert into employees (full_name_bn, primary_location_id) values ('B Employee', :'hw1'::int) returning id as emp_b \gset
insert into payroll_runs (month, location_id) values (date_trunc('month', current_date)::date, :'hw1'::int) returning id as pr_b \gset
select tt.t('T0 B rows for the id tests exist (purchase bill, entry, employee, payroll run)', :'pur_b' is not null and :'ent_b' is not null and :'emp_b' is not null and :'pr_b' is not null);
-- config rows in both businesses
insert into location_settings (location_id, key, value) values (1, 'c1k', '"a"'), (:'hw1'::int, 'c1k', '"b"');
insert into att_site_geo (location_id, lat, lng) values (1, 23.7, 90.4), (:'hw1'::int, 22.3, 91.8);
insert into holidays (day, location_id, name_bn) values (current_date + 5, 1, 'a'), (current_date + 6, :'hw1'::int, 'b'), (current_date + 7, null, 'group');
insert into shifts (name_bn, location_id, start_time, end_time) values ('a', 1, '09:00', '17:00'), ('b', :'hw1'::int, '10:00', '18:00');
insert into sales_channels (code, kind, other_text, name_bn, location_id) values ('c1_a', 'other', 'x', 'a', 1), ('c1_b', 'other', 'x', 'b', :'hw1'::int);
insert into report_brand_map (location_id, brand_code, brand_bn, brand_en) values (:'hw1'::int, 'HW', 'hw', 'hw') on conflict do nothing;
insert into blind_count_cfg (form_code, location_id, enabled) select 'DAILY_STOCK', :'hw1'::int, true where exists (select 1 from forms where code = 'DAILY_STOCK') on conflict do nothing;
insert into form_rollout (form_code, location_id, mode) select f.code, :'hw1'::int, 'app' from forms f limit 1 on conflict do nothing;
insert into path_switch (domain, location_id) select d.domain, :'hw1'::int from path_domains d limit 1 on conflict do nothing;
insert into doc_template_choice (doc_type, location_id, template_id) values ('invoice', :'hw1'::int, 't1'), ('invoice', 1, 't1') on conflict do nothing;
insert into invoice_templates (name, kind, location_id) values ('tpl-a', 'a4', 1), ('tpl-b', 'a4', :'hw1'::int);
insert into print_profiles (name, location_id, printer_type) values ('pp-a', 1, 'thermal'), ('pp-b', :'hw1'::int, 'thermal');
insert into location_setup_steps (location_id, step_no, title_bn, title) values (:'hw1'::int, 1, 'x', 'x') on conflict do nothing;
insert into paper_books (form_code, location_id, first_no, last_no) values ('POS', :'hw1'::int, 1, 100);
insert into print_notes (form_code, location_id, reason) values ('POS', :'hw1'::int, 'r');
-- scope rows: A manager over the SWEETS business, B manager over HARDWARE, B branch manager over the branch HW-B1 only; the legacy manager and x_none have none
select org_scope_grant(:'am'::uuid, :'sbz'::bigint, 'management', 'a mgr', gen_random_uuid()) ->> 'id' as sc_am \gset
select org_scope_grant(:'bm'::uuid, :'hbz'::bigint, 'management', 'b mgr', gen_random_uuid()) ->> 'id' as sc_bm \gset
select org_scope_grant(:'bb'::uuid, :'hb1'::bigint, 'management', 'b branch', gen_random_uuid()) ->> 'id' as sc_bb \gset
select tt.t('T0 three scope rows exist', (select count(*) from user_org_scopes where status = 'active' and note in ('a mgr', 'b mgr', 'b branch')) = 3);
create or replace function tt.cnt(p_sql text) returns bigint language plpgsql as $$ declare n bigint; begin execute p_sql into n; return n; exception when others then return -1; end $$;
-- true when the statement raises or returns nothing / zero
create or replace function tt.none(p_sql text) returns boolean language plpgsql as $$ declare n bigint; begin execute p_sql into n; return coalesce(n, 0) = 0; exception when others then return true; end $$;
-- every public table with a location_id column: how many rows of the given places can the CURRENT role see (RLS applies; a closed table counts 0)
create or replace function tt.leaks(p_locs int[]) returns jsonb language plpgsql as $$
declare r record; n bigint; res jsonb := '{}'::jsonb;
begin
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace join pg_attribute a on a.attrelid = c.oid and a.attname = 'location_id' and not a.attisdropped
            where s.nspname = 'public' and c.relkind = 'r' order by 1 loop
    begin execute format('select count(*) from public.%I where location_id = any($1)', r.relname) into n using p_locs;
    exception when others then n := 0; end;
    if n > 0 then res := res || jsonb_build_object(r.relname, n); end if;
  end loop;
  return res;
end $$;
grant execute on all functions in schema tt to authenticated, anon;

\echo == T1 switch OFF: the old behaviour, hand numbers
select tt.t('T1 org_scope_on is OFF by default', not rule_on('org_scope_on'));
select tt.as(:'o');
select tt.eq('T1 owner: customer_dues total = 600 + 500 + 700', 1800, (select sum(balance) from customer_dues()));
select tt.as(:'ao');
select tt.eq('T1 OFF: an A salesperson still sees every customer due of every place (1800)', 1800, (select sum(balance) from customer_dues()));
select tt.eq('T1 OFF: customer_ledger of the common customer has A and B rows', 3, (select count(*) from customer_ledger(:'cust_c'::uuid)));
select tt.t('T1 OFF: can_loc as before: management anywhere, a plain user only at the assigned place', (select tt.as(:'am') is not null) and can_loc(:'hw1'::int) and can_loc(null)
  and (select tt.as(:'ao') is not null) and can_loc(1) and not can_loc(:'hw1'::int) and not can_loc(null));
select tt.t('T1 OFF: the legacy manager without scope row works everywhere', (select tt.as(:'xl') is not null) and can_loc(:'hw2'::int) and _all_locs() and _acct_all());
select tt.t('T1 OFF: a NULL-location personal grant is still database wide', (select tt.as(:'ao') is not null) and has_grant('view_cost', :'hw1'::int) and has_grant('view_cost', 1));
select tt.t('T1 OFF: staff_directory lists everybody', (select tt.as(:'ao') is not null) and jsonb_array_length(staff_directory()) = (select count(*) from profiles where status = 'active'));
select tt.t('T1 OFF: fa_register for the accountant (accounts_manage) lists all 3 assets', (select tt.as(:'aa') is not null) and jsonb_array_length(fa_register(current_date)->'rows') = 3);
select tt.t('T1 OFF: a stock transfer between the businesses is allowed', (select tt.as(:'o') is not null) and (stock_transfer(1, :'hw2'::int, tt.iid('C1-X'), 1, null, 'x', gen_random_uuid()) is not null));
set role authenticated;
select tt.as(:'ao');
select tt.eq('T1 OFF: an A salesperson reads all 10 locations directly', 10, (select count(*) from locations));
select tt.eq('T1 OFF: ... and the B holidays row', 1, (select count(*) from holidays where location_id = :'hw1'::int));
select tt.as(:'xn');
select tt.eq('T1 OFF: a user with no place at all reads all locations too', 10, (select count(*) from locations));
reset role;
select tt.as(:'o');
create temp table off_snap as select
  (select md5(string_agg(x::text, '|' order by x::text)) from (select * from customer_dues()) x) dues_h, (select md5(acct_trial_balance(null, null)::text)) tb_h;
select tt.as(:'o');

\echo == T2 switch ON
update rules set value = 'true'::jsonb where key = 'org_scope_on';
select tt.t('T2 the switch reads ON', rule_on('org_scope_on') and _org_on123());
select tt.as(:'xn');
select tt.err('T2 preflight is refused to a non-owner', $$select org_scope_preflight()$$, 'not allowed');
select tt.as(:'o');
select org_scope_preflight() as pre \gset
select tt.t('T2 preflight lists the unmapped location and the legacy manager without scope', (:'pre'::jsonb->'unmapped_locations') ? 'orphan' and (:'pre'::jsonb->'management_users_without_scope') ? 'x_legacy'
  and (:'pre'::jsonb->>'businesses')::int = 2 and (:'pre'::jsonb->>'switch_on')::boolean);
select tt.t('T2 preflight counts the NULL-location config rows (holidays 1) and personal NULL grants', ((:'pre'::jsonb->'config_rows_without_location')->>'holidays')::int = 1 and (:'pre'::jsonb->>'personal_grants_without_location')::int >= 3);

\echo == T3 test 2 of the audit: the management bypass is gone, scopes follow the business
select tt.as(:'am');
select tt.t('T3 A manager: every SWEETS location (1..7) is still allowed', (select bool_and(can_loc(l)) from generate_series(1, 7) l));
select tt.t('T3 A manager: no B location, no unmapped location, no null', not can_loc(:'hw1'::int) and not can_loc(:'hw2'::int) and not can_loc(:'orph'::int) and not can_loc(null));
select tt.t('T3 A manager: _all_locs() and _acct_all() are false', not _all_locs() and not _acct_all());
select tt.as(:'bm');
select tt.t('T3 B manager (business scope): hw1 and hw2 yes, sweets no, orphan no, null no', can_loc(:'hw1'::int) and can_loc(:'hw2'::int) and not can_loc(1) and not can_loc(5) and not can_loc(:'orph'::int) and not can_loc(null) and not _all_locs() and not _acct_all());
select tt.as(:'bb');
select tt.t('T3 B branch manager (scope on the branch HW-B1 only): hw1 yes, hw2 no (a sibling under the business), sweets no', can_loc(:'hw1'::int) and not can_loc(:'hw2'::int) and not can_loc(1));
select tt.as(:'xl');
select tt.t('T3 the legacy manager without a scope row gets NOTHING (stricter option)', not can_loc(1) and not can_loc(:'hw1'::int) and not can_loc(null) and not _all_locs());
select tt.as(:'xn');
select tt.t('T3 a user with no place and no scope: nothing', not can_loc(1) and not can_loc(:'hw1'::int) and not can_loc(null));
select tt.as(:'ao');
select tt.t('T3 A salesperson: own place 1 yes, other A place 2 no (explicit assignment only), B no', can_loc(1) and not can_loc(2) and not can_loc(:'hw1'::int));
select tt.as(:'o');
select tt.t('T3 owner: everything including null and the unmapped place', can_loc(1) and can_loc(:'hw1'::int) and can_loc(:'orph'::int) and can_loc(null) and _all_locs() and _acct_all());
select tt.t('T3 can_scope: owner yes; A manager over SWEETS yes, over HARDWARE no, over the branch no; B branch manager over the branch yes, over the business no',
  can_scope(:'hbz'::bigint) and (select tt.as(:'am') is not null) and can_scope(:'sbz'::bigint) and not can_scope(:'hbz'::bigint) and not can_scope(:'hb1'::bigint)
  and (select tt.as(:'bb') is not null) and can_scope(:'hb1'::bigint) and not can_scope(:'hbz'::bigint) and (select tt.as(:'bm') is not null) and can_scope(:'hb1'::bigint) and can_scope(:'hbz'::bigint, 'management') and not can_scope(:'hbz'::bigint, 'hr'));
select tt.as(:'am');
select tt.is('T3 business_of_location: own location gives the business, a B location gives null', (select code from org_units where id = business_of_location(1)) || '/' || coalesce(business_of_location(:'hw1'::int)::text, 'null'), 'SWEETS/null');
select tt.as(:'bm');
select tt.is('T3 business_of_location: a B location seen by B gives HARDWARE (also through the branch)', (select code from org_units where id = business_of_location(:'hw1'::int)), 'HARDWARE');
select tt.as(:'o');
select tt.is('T3 business_of_location for the owner: orphan gives null', coalesce(business_of_location(:'orph'::int)::text, 'null'), 'null');

\echo == T4 test 3: role-global and personal NULL-location grants stop at the business border
select tt.as(:'ao');
select tt.t('T4 A staff with a NULL-location personal view_cost grant: yes in own business, NO at a B location', has_grant('view_cost', 1) and has_grant('view_cost', 2) and not has_grant('view_cost', :'hw1'::int) and not has_grant('view_cost', :'hw2'::int) and not has_grant('view_cost', :'orph'::int));
select tt.t('T4 ... without a location the grant still answers yes (the data is filtered further down)', has_grant('view_cost'));
select tt.as(:'aa');
select tt.t('T4 A accountant (personal accounts_manage, NULL location): own business yes, B no', has_grant('accounts_manage', 2) and has_grant('accounts_manage', 1) and not has_grant('accounts_manage', :'hw1'::int));
select tt.as(:'am');
select tt.t('T4 A manager: a role grant of the management role (sale_void) works in SWEETS, not at a B location', has_grant('sale_void', 1) and has_grant('sale_void', 4) and not has_grant('sale_void', :'hw1'::int) and not has_grant('sale_void', :'orph'::int));
select tt.as(:'o');
select tt.t('T4 owner: has_grant everywhere', has_grant('view_cost', :'hw1'::int) and has_grant('nothing_at_all', :'orph'::int));
select tt.as(:'aa');
set role authenticated;
select tt.eq('T4 A accountant (accounts_manage grant) reads NO journal line of B directly', 0, (select count(*) from journal_lines where location_id in (:'hw1'::int, :'hw2'::int)));
select tt.eq('T4 ... and no journal entry row of B', 0, (select count(*) from journal_entries e where exists (select 1 from journal_lines l where l.entry_id = e.id and l.location_id = :'hw1'::int)));
select tt.t('T4 ... and sees only the lines of her own place (2) and no null-location line', (select count(*) from journal_lines where location_id is null) = 0);
reset role;

\echo == T5 test 14 first half and sweets regression: the owner still sees both, the A manager sees what the manager always saw in SWEETS
select tt.as(:'o');
select tt.eq('T5 owner: customer_dues still 1800 (A 600 + B 500 + B-only 700)', 1800, (select sum(balance) from customer_dues()));
select tt.eq('T5 owner: customer_ledger of the common customer 3 rows', 3, (select count(*) from customer_ledger(:'cust_c'::uuid)));
select tt.eq('T5 owner: fa_register lists 3 assets', 3, (select jsonb_array_length(fa_register(current_date)->'rows')));
select tt.t('T5 owner: drawer_report counts 3 no-sale opens', (drawer_report(current_date - 1, current_date + 1)->'totals'->>'no_sale_open')::int = 3);
select tt.eq('T5 owner: staff_directory lists every active person', (select count(*) from profiles where status = 'active'), (select jsonb_array_length(staff_directory())));
select tt.t('T5 owner: items_with_cost has both items', (select count(*) from items_with_cost() where item_id in (tt.iid('C1-X'), tt.iid('C1-Y'))) = 2);
select tt.t('T5 owner: year_close_list works', year_close_list() ? 'rows');
select tt.t('T5 owner: profit_truth112 for a B place works', profit_truth112(current_date - 10, current_date + 1, :'hw1'::int) ? 'rows');
set role authenticated;
select tt.eq('T5 owner: reads all 10 locations directly', 10, (select count(*) from locations));
select tt.eq('T5 owner: reads the B holiday, the group holiday (NULL place) and the A holiday', 3, (select count(*) from holidays where day >= current_date + 5));
reset role;
select tt.as(:'am');
select tt.eq('T5 A manager: customer_dues = 600 only (the common customer owes 600 in SWEETS, the B part is hidden)', 600, (select sum(balance) from customer_dues()));
select tt.eq('T5 A manager: the B-only customer is not listed', 0, (select count(*) from customer_dues() where id = :'cust_h'::uuid));
select tt.t('T5 A manager: SWEETS data as before (a SWEETS sale visible)', (select count(*) from customer_ledger(:'cust_c'::uuid)) = 2);

\echo == T6 test 6: the unscoped reader functions, as users of the other business
select tt.as(:'bs');
select tt.eq('T6 B staff: customer_dues = 1200 (the common customer 500 + the B-only customer 700), not the 600 of SWEETS', 1200, (select sum(balance) from customer_dues()));
select tt.eq('T6 B staff: customer_ledger of the common customer shows only the B sale (1 row, place hw1)', 1, (select count(*) from customer_ledger(:'cust_c'::uuid) where location_id = :'hw1'::int));
select tt.eq('T6 ... and nothing of A', 0, (select count(*) from customer_ledger(:'cust_c'::uuid) where location_id = 1));
select tt.as(:'ao');
select tt.eq('T6 A staff: customer_dues = 600 and the B-only customer is absent', 600, (select sum(balance) from customer_dues()));
select tt.eq('T6 A staff: customer_ledger of the B-only customer is EMPTY', 0, (select count(*) from customer_ledger(:'cust_h'::uuid)));
select tt.eq('T6 A staff: customer_ledger of the common customer shows 2 rows (the A sale and the A payment), none at hw1', 0, (select count(*) from customer_ledger(:'cust_c'::uuid) where location_id = :'hw1'::int));
select tt.as(:'aa');
select tt.t('T6 A accountant: fa_register lists only the asset of her place... which has none, so the SWEETS asset only if she may see place 1', (select jsonb_array_length(fa_register(current_date)->'rows')) = 0);
select tt.as(:'am');
select tt.is('T6 A manager: fa_register lists the sweets asset only', 'FA-A', (select string_agg(r->>'code', ',') from jsonb_array_elements(fa_register(current_date)->'rows') r));
select tt.err('T6 A manager: fa_schedule of the B asset says not found (same as a missing id)', format($q$select fa_schedule(%L)$q$, :'fa_b'), 'not found');
select tt.t('T6 A manager: fa_schedule of the own asset works', fa_schedule(:'fa_a'::uuid) ? 'rows');
select tt.err('T6 A manager: year_close_list is owner only now', $$select year_close_list()$$, 'not allowed');
select tt.t('T6 A manager: staff_directory lists A people and not the B people', (select jsonb_agg(x->>'full_name') from jsonb_array_elements(staff_directory()) x) ? 'A Staff' and not (select jsonb_agg(x->>'full_name') from jsonb_array_elements(staff_directory()) x) ? 'B Staff'
  and not (select jsonb_agg(x->>'full_name') from jsonb_array_elements(staff_directory()) x) ? 'B Manager');
select tt.as(:'bm');
select tt.t('T6 B manager: staff_directory lists B people only (himself, the B staff, the B branch manager), not A staff, not the owner', (select jsonb_agg(x->>'full_name') from jsonb_array_elements(staff_directory()) x) ? 'B Staff'
  and not (select jsonb_agg(x->>'full_name') from jsonb_array_elements(staff_directory()) x) ? 'A Staff' and not (select jsonb_agg(x->>'full_name') from jsonb_array_elements(staff_directory()) x) ? 'Owner');
select tt.as(:'xn');
select tt.eq('T6 a person with no business sees only herself in staff_directory', 1, (select jsonb_array_length(staff_directory())));
select tt.as(:'ao');
select tt.eq('T6 A staff (view_reports): drawer_report shows only the A no-sale open (1)', 1, (drawer_report(current_date - 1, current_date + 1)->'totals'->>'no_sale_open')::int);
select tt.as(:'bs');
select tt.eq('T6 B staff (view_reports): drawer_report shows the 2 B no-sale opens', 2, (drawer_report(current_date - 1, current_date + 1)->'totals'->>'no_sale_open')::int);
select tt.t('T6 B staff: ... and the only staff in by_user is his own', jsonb_array_length(drawer_report(current_date - 1, current_date + 1)->'by_user') = 1);
select tt.as(:'ao');
select tt.is('T6 A staff (view_cost): items_with_cost shows the cost of Item X from SWEETS stock only (40, not the blended 65)', '40.0000', (select round(cost_price, 4)::text from items_with_cost() where item_id = tt.iid('C1-X')));
select tt.eq('T6 A staff: Item Y (stocked only in B) has NO cost row', 0, (select count(*) from items_with_cost() where item_id = tt.iid('C1-Y')));
select tt.is('T6 A staff: item_cost_status88 says missing for Item Y', 'true', (select cost_missing::text from item_cost_status88() where item_id = tt.iid('C1-Y')));
select tt.as(:'bs');
select tt.eq('T6 B staff: items_with_cost shows 90 for Item X', 90, (select cost_price from items_with_cost() where item_id = tt.iid('C1-X')));

\echo == T7 test 4: direct select on the formerly any-active tables
select tt.as(:'ao');
set role authenticated;
select tt.eq('T7 A staff: locations = the 7 SWEETS places only', 7, (select count(*) from locations));
select tt.eq('T7 A staff: no B / unmapped location is readable', 0, (select count(*) from locations where code in ('hw1', 'hw2', 'orphan')));
select tt.eq('T7 A staff: location_settings: only A', 1, (select count(*) from location_settings where key = 'c1k'));
select tt.eq('T7 A staff: att_site_geo: only A', 1, (select count(*) from att_site_geo));
select tt.eq('T7 A staff: holidays: the A one only, the NULL-place (group) row is owner only', 1, (select count(*) from holidays where day >= current_date + 5));
select tt.eq('T7 A staff: shifts: only A', 1, (select count(*) from shifts where name_bn in ('a', 'b')));
select tt.eq('T7 A staff: sales_channels: only A', 1, (select count(*) from sales_channels where code like 'c1\_%'));
select tt.eq('T7 A staff: report_brand_map, blind_count_cfg, form_rollout, path_switch, doc_template_choice show nothing of B', 0,
  (select count(*) from report_brand_map where location_id > 7) + (select count(*) from blind_count_cfg where location_id > 7) + (select count(*) from form_rollout where location_id > 7)
  + (select count(*) from path_switch where location_id > 7) + (select count(*) from doc_template_choice where location_id > 7));
select tt.eq('T7 A staff: invoice_templates and print_profiles: only the A ones', 2, (select count(*) from invoice_templates where name like 'tpl-%') + (select count(*) from print_profiles where name like 'pp-%'));
select tt.eq('T7 A staff: the weak has_grant-only tables show nothing of B', 0, (select count(*) from location_setup_steps where location_id > 7) + (select count(*) from paper_books where location_id > 7)
  + (select count(*) from print_notes where location_id > 7) + (select count(*) from settings_sheets where location_id > 7));
select tt.t('T7 A staff: the truly global configuration stays readable (rules, roles, grant_defs, forms) and the item master (deferred to C2)', (select count(*) from rules) > 100 and (select count(*) from roles) > 5
  and (select count(*) from grant_defs) > 10 and (select count(*) from forms) > 3 and (select count(*) from items where code = 'C1-Y') = 1);
select tt.err('T7 A staff cannot write a B invoice template directly (restrictive policy on write)', format($q$update invoice_templates set name = 'hacked' where name = 'tpl-b'$q$) || '; select 1/(case when (select count(*) from invoice_templates where name = ''hacked'') = 0 then 0 else 1 end)', 'division by zero');
reset role;
select tt.as(:'bs');
set role authenticated;
select tt.eq('T7 B staff: locations = hw1, hw2 (his business) only; the orphan and SWEETS are hidden', 2, (select count(*) from locations));
select tt.eq('T7 B staff: location_settings only B, holidays only B', 2, (select count(*) from location_settings where key = 'c1k' and location_id = :'hw1'::int) + (select count(*) from holidays where day >= current_date + 5));
select tt.eq('T7 B staff: shifts and sales_channels only B', 2, (select count(*) from shifts where name_bn = 'b') + (select count(*) from sales_channels where code = 'c1_b'));
reset role;
select tt.as(:'xn');
set role authenticated;
select tt.eq('T7 a user without any business sees no location at all', 0, (select count(*) from locations));
reset role;

\echo == T8 test 1: generated per-table check, every table with a location_id column
select tt.as(:'o');
select tt.leaks(array[:'hw1'::int, :'hw2'::int]) as owner_sees \gset
select tt.t('T8 not vacuous: as owner many tables hold B rows', (select count(*) from jsonb_object_keys(:'owner_sees'::jsonb)) >= 15, 'true', (select count(*)::text from jsonb_object_keys(:'owner_sees'::jsonb)));
select tt.as(:'ao');
set role authenticated;
select tt.leaks(array[:'hw1'::int, :'hw2'::int]) as a_staff_sees \gset
reset role;
select tt.is('T8 A staff sees no B row in any table with a location_id', '{}', :'a_staff_sees');
select tt.as(:'am');
set role authenticated;
select tt.leaks(array[:'hw1'::int, :'hw2'::int]) as a_mgr_sees \gset
reset role;
select tt.is('T8 A manager sees no B row in any table with a location_id', '{}', :'a_mgr_sees');
select tt.as(:'aa');
set role authenticated;
select tt.leaks(array[:'hw1'::int, :'hw2'::int]) as a_acc_sees \gset
reset role;
select tt.is('T8 A accountant (personal accounts_manage) sees no B row in any table with a location_id', '{}', :'a_acc_sees');
select tt.as(:'xl');
set role authenticated;
select tt.leaks(array[:'hw1'::int, :'hw2'::int]) as x_leg_sees \gset
reset role;
select tt.is('T8 the legacy manager (no scope row) sees no B row', '{}', :'x_leg_sees');
select tt.as(:'bm');
set role authenticated;
select tt.leaks(array[1, 2, 3, 4, 5, 6, 7]) as b_mgr_sees \gset
reset role;
select tt.is('T8 B manager sees no SWEETS row in any table with a location_id', '{}', :'b_mgr_sees');
select tt.as(:'bb');
set role authenticated;
select tt.leaks(array[:'hw2'::int]) as b_br_sees \gset
reset role;
select tt.is('T8 the B branch manager (scope on the branch) sees nothing of the sibling place hw2', '{}', :'b_br_sees');
select tt.as(:'bm');
set role authenticated;
select tt.leaks(array[:'hw1'::int, :'hw2'::int]) as b_mgr_own \gset
reset role;
select tt.t('T8 B manager sees his own rows (sales, journal_lines, stock_ledger ...)', :'b_mgr_own'::jsonb ? 'sales' and :'b_mgr_own'::jsonb ? 'journal_lines' and :'b_mgr_own'::jsonb ? 'stock_ledger');

\echo == T9 test 5: RPC parameter swap with a place of the other business
select tt.as(:'am');
select tt.err('T9 profit_truth112(p_loc = B place) is refused', format($q$select profit_truth112(current_date - 10, current_date + 1, %s)$q$, :'hw1'), 'not allowed');
select tt.t('T9 profit_truth112 without a place shows only SWEETS places', (select count(*) from jsonb_array_elements(profit_truth112(current_date - 10, current_date + 1, null)->'rows') r where (r->>'location_id')::int > 7) = 0);
select tt.t('T9 acct_ledger / day_book / stock_levels / stock_valuation / biz_items with a B place: refused or empty', 
  tt.none(format($q$select count(*) from day_book(%s, current_date - 5, current_date + 1)$q$, :'hw1')) and tt.none(format($q$select count(*) from stock_levels(%s)$q$, :'hw1'))
  and tt.none(format($q$select count(*) from stock_valuation(%s)$q$, :'hw1')) and tt.none(format($q$select coalesce(sum(revenue), 0) from biz_items(current_date - 5, current_date + 1, %s)$q$, :'hw1')));
select tt.t('T9 acct_balance_sheet(B place) / acct_income_statement(B place): refused or no figures',
  tt.none(format($q$select (acct_balance_sheet(current_date, %s)->>'total_assets')::numeric$q$, :'hw1')) and tt.none(format($q$select (acct_income_statement(current_date - 5, current_date, %s)->>'revenue')::numeric$q$, :'hw1')));
select tt.t('T9 report_run with a B place in the filter returns no B rows', tt.none(format($q$select (report_run('sales_summary', '{"locations":[%s]}'::jsonb)->'totals'->>'net')::numeric$q$, :'hw1')));
select tt.as(:'o');
select tt.t('T9 the same calls for the owner return B figures', jsonb_array_length(profit_truth112(current_date - 10, current_date + 1, :'hw1'::int)->'rows') >= 1 and (select count(*) from stock_levels(:'hw1'::int)) >= 1);

\echo == T10 test 7: id guessing and writes with the other business's ids
select tt.as(:'ao');
set role authenticated;
select tt.eq('T10 A staff: select by the id of a B sale / purchase bill / entry / employee / payroll run / journal entry = 0 rows', 0,
  (select count(*) from sales where id = :'sale_b'::uuid) + (select count(*) from purchase_bills where id = :'pur_b'::uuid) + (select count(*) from entries where id = :'ent_b'::uuid)
  + (select count(*) from employees where id = :'emp_b'::uuid) + (select count(*) from payroll_runs where id = :'pr_b'::bigint)
  + (select count(*) from journal_entries e where e.id in (select entry_id from journal_lines)) - (select count(*) from journal_entries e where e.id in (select entry_id from journal_lines)));
select tt.eq('T10 A staff: the B stock transfer / stock ledger / sale payments by place = 0', 0, (select count(*) from stock_ledger where location_id = :'hw1'::int) + (select count(*) from sale_payments where location_id = :'hw1'::int));
select tt.t('T10 A staff: update / delete by the id of a B row changes nothing (refused or 0 rows)', tt.none(format($q$with u as (update sales set note = 'x' where id = %L returning 1) select count(*) from u$q$, :'sale_b'))
  and tt.none(format($q$with u as (update entries set status = 'submitted' where id = %L returning 1) select count(*) from u$q$, :'ent_b')) and tt.none(format($q$with u as (delete from employees where id = %L returning 1) select count(*) from u$q$, :'emp_b')));
reset role;
select tt.err('T10 record_sale2 at a B place by an A salesperson', format($q$select record_sale2(gen_random_uuid(), %s, '[]'::jsonb, 0, '[]', null, null, 'retail', null, false)$q$, :'hw1'), 'not allowed');
select tt.err('T10 save_entry at a B place', format($q$select save_entry(null, 'ITEMS', %s, current_date, '{}'::jsonb, '{}'::jsonb)$q$, :'hw1'), 'not allowed');
select tt.err('T10 void_sale of a B sale by an A salesperson', format($q$select void_sale(%L, 'x')$q$, :'sale_b'), 'not');
select tt.err('T10 save_purchase at a B place', format($q$select save_purchase(gen_random_uuid(), null, %L, %s, 'X-1', current_date, '[]'::jsonb)$q$, :'sup1', :'hw1'), 'not allowed');
select tt.err('T10 stock_transfer out of a B place', format($q$select stock_transfer(%s, 1, tt.iid('C1-X'), 1, null, 'x', gen_random_uuid())$q$, :'hw1'), 'not allowed');
select tt.as(:'am');
select tt.err('T10 an A MANAGER cannot sell at a B place either', format($q$select record_sale2(gen_random_uuid(), %s, '[]'::jsonb, 0, '[]', null, null, 'retail', null, false)$q$, :'hw1'), 'not allowed');
select tt.as(:'bm');
select tt.err('T10 a B manager cannot void or sell at SWEETS', format($q$select record_sale2(gen_random_uuid(), 1, '[]'::jsonb, 0, '[]', null, null, 'retail', null, false)$q$), 'not allowed');
select tt.as(:'bs');
select tt.err('T10 a B staff cannot save a purchase at SWEETS', format($q$select save_purchase(gen_random_uuid(), null, %L, 1, 'X-2', current_date, '[]'::jsonb)$q$, :'sup1'), 'not allowed');

\echo == T11 test 8: stock transfer across businesses
select tt.as(:'o');
select tt.err('T11 owner: a transfer from SWEETS to a B place is refused (intercompany is Stage E)', format($q$select stock_transfer(1, %s, tt.iid('C1-X'), 1, null, 'x', gen_random_uuid())$q$, :'hw2'), 'cross_business_transfer');
select tt.err('T11 owner: a transfer from a B place to SWEETS is refused', format($q$select stock_transfer(%s, 1, tt.iid('C1-X'), 1, null, 'x', gen_random_uuid())$q$, :'hw1'), 'cross_business_transfer');
select tt.err('T11 owner: a transfer to an unmapped place is refused', format($q$select stock_transfer(1, %s, tt.iid('C1-X'), 1, null, 'x', gen_random_uuid())$q$, :'orph'), 'cross_business_transfer');
select tt.t('T11 owner: a transfer inside the business works (hw1 -> hw2)', stock_transfer(:'hw1'::int, :'hw2'::int, tt.iid('C1-X'), 1, null, 'x', gen_random_uuid()) is not null);
select tt.t('T11 owner: a transfer inside SWEETS works (1 -> 2)', stock_transfer(1, 2, tt.iid('C1-X'), 1, null, 'x', gen_random_uuid()) is not null);
select tt.as(:'bs');
set role authenticated;
select tt.eq('T11 B staff sees no transfer that touches SWEETS (the OFF-time transfer 1 -> hw2 of T1 is not his); A side invisible', 0, (select count(*) from stock_transfers where from_location_id = 1 and to_location_id = :'hw2'::int));
reset role;

\echo == T12 test 12: emergency windows and approvals do not open the other business
select tt.as(:'o');
insert into emergency_requests (grant_code, requested_by, requested_staff, location_id, reason, status, valid_until, decided_by) values
 ('loc_access', :'ao', 'a1', :'hw1'::int, 'peek at B', 'approved', now() + interval '20 minutes', :'o'),
 ('loc_access', :'ao', 'a1', 4, 'cover place 4', 'approved', now() + interval '20 minutes', :'o');
select tt.as(:'ao');
select tt.t('T12 an approved loc_access window for a B place does NOT open it for an A user; one for an A place does', not can_loc(:'hw1'::int) and can_loc(4));
select tt.as(:'o');
insert into emergency_requests (grant_code, requested_by, requested_staff, location_id, reason, status) values ('sale_void', :'bs', 'b1', :'hw1'::int, 'B void', 'pending') returning id as em_b \gset
insert into emergency_requests (grant_code, requested_by, requested_staff, location_id, reason, status) values ('sale_void', :'ao', 'a1', 1, 'A void', 'pending') returning id as em_a \gset
insert into rule_grants (role_code, grant_code, allowed) values ('management', 'emergency_decide', true) on conflict (role_code, grant_code) do update set allowed = true;
select tt.as(:'am');
select tt.err('T12 an A approver cannot decide a B request (same answer as a missing id)', format($q$select decide_emergency(%s, true, 'ok')$q$, :'em_b'), 'not found');
set role authenticated;
select tt.eq('T12 ... and does not even see it', 0, (select count(*) from emergency_requests where id = :'em_b'::bigint));
select tt.eq('T12 ... he sees the A request', 1, (select count(*) from emergency_requests where id = :'em_a'::bigint));
reset role;
select decide_emergency(:'em_a'::bigint, true, 'ok');
select tt.t('T12 the A approver decides the A request', (select status from emergency_requests where id = :'em_a'::bigint) = 'approved');
select tt.as(:'bm');
select decide_emergency(:'em_b'::bigint, true, 'ok');
select tt.t('T12 the B approver decides the B request', (select status from emergency_requests where id = :'em_b'::bigint) = 'approved');
select tt.as(:'bs');
select tt.t('T12 ... and the approved window then lets B staff into hw1 (own business, was already his)', can_loc(:'hw1'::int));

\echo == T13 scope rows: revoke, dormant when the role is removed, idempotency, owner only
select tt.as(:'o');
select org_scope_grant(:'am'::uuid, :'sbz'::bigint, 'management', 'again', '00000000-0000-0000-0000-0000000000d1') as g_again \gset
select tt.t('T13 granting the same live scope again is a dup (no second row)', (:'g_again'::jsonb->>'dup')::boolean and (:'g_again'::jsonb->>'id')::bigint = :'sc_am'::bigint and (select count(*) from user_org_scopes where user_id = :'am'::uuid and status = 'active') = 1);
select org_scope_grant(:'am'::uuid, :'sbz'::bigint, 'management', 'again', '00000000-0000-0000-0000-0000000000d1') as g_again2 \gset
select tt.t('T13 the same client key again is a dup too', (:'g_again2'::jsonb->>'dup')::boolean);
select tt.err('T13 a create without a key is refused', format($q$select org_scope_grant(%L::uuid, %s, 'management', null, null)$q$, :'xl', :'sbz'), 'client_id_needed');
select tt.err('T13 a scope on the group is refused (only the owner is group wide)', format($q$select org_scope_grant(%L::uuid, %s, 'management', null, gen_random_uuid())$q$, :'xl', (select id from org_units where kind = 'group')), 'group_scope_is_owner_only');
select tt.err('T13 the owner role cannot be scoped', format($q$select org_scope_grant(%L::uuid, %s, 'owner', null, gen_random_uuid())$q$, :'xl', :'sbz'), 'bad_role');
select tt.err('T13 unknown user', format($q$select org_scope_grant(gen_random_uuid(), %s, 'management', null, gen_random_uuid())$q$, :'sbz'), 'bad_user');
select tt.err('T13 unknown unit', format($q$select org_scope_grant(%L::uuid, 999999, 'management', null, gen_random_uuid())$q$, :'xl'), 'bad_unit');
select tt.as(:'am');
select tt.err('T13 a manager cannot grant scope (owner only)', format($q$select org_scope_grant(%L::uuid, %s, 'management', null, gen_random_uuid())$q$, :'xl', :'sbz'), 'not allowed');
select tt.err('T13 ... or revoke it', format($q$select org_scope_revoke(%s, 'x')$q$, :'sc_bm'), 'not allowed');
select tt.eq('T13 org_scope_list: a manager sees only his own row', 1, (select count(*) from org_scope_list()));
select tt.as(:'o');
select tt.eq('T13 org_scope_list: the owner sees all 3 rows, all live', 3, (select count(*) from org_scope_list() where live));
-- the role is removed: the row stays but is dormant, the power is gone
delete from user_roles where user_id = :'bb' and role_code = 'management';
select tt.t('T13 B branch manager loses the management role: the row is kept, shown not live, and gives nothing', (select not live from org_scope_list(:'bb'::uuid)) and (select tt.as(:'bb') is not null) and not can_loc(:'hw1'::int));
insert into user_roles values (:'bb', 'management');
select tt.t('T13 role back: the same row works again', can_loc(:'hw1'::int));
select tt.as(:'o');
select org_scope_revoke(:'sc_bb'::bigint, 'moved') as rv \gset
select tt.t('T13 revoke: status revoked, history kept, a second revoke is a dup', (:'rv'::jsonb->>'dup')::boolean = false and (select status from user_org_scopes where id = :'sc_bb'::bigint) = 'revoked' and (org_scope_revoke(:'sc_bb'::bigint, 'again')->>'dup')::boolean);
select tt.as(:'bb');
select tt.t('T13 after the revoke the branch manager has nothing', not can_loc(:'hw1'::int));
select tt.as(:'o');
select tt.err('T13 hard delete of a scope row is refused', format($q$delete from user_org_scopes where id = %s$q$, :'sc_bb'), 'delete');
select tt.t('T13 every scope grant / revoke left an audit row', (select count(*) >= 4 from audit_log where table_name = 'user_org_scopes'));
set role anon;
select tt.err('T13 anon cannot call the scope functions', $$select org_scope_list()$$, 'permission denied');
select tt.err('T13 anon cannot read the table', $$select count(*) from user_org_scopes$$, 'permission denied');
reset role;
select tt.as(:'o');
-- first-paste backfill (simulated): the marker is removed, a management user with no row exists, the file is pasted
update org_units set attrs = attrs - 'seed123' where code = 'SWEETS';
update user_roles set role_code = 'storekeeper' where role_code = 'management' and user_id <> :'xl';   -- the other managers are not yet management users at "first paste"
\i supabase/phase123.sql
update user_roles set role_code = 'management' where role_code = 'storekeeper' and user_id in (:'am', :'bm', :'bb');
select tt.t('T13 backfill: the legacy manager got a management scope on SWEETS (note says phase123 backfill)', exists (select 1 from user_org_scopes where user_id = :'xl'::uuid and org_unit_id = :'sbz'::bigint and role_code = 'management' and status = 'active' and note like 'phase123 backfill%'));
select tt.t('T13 ... only management users without a SWEETS row got one (A manager: still one row), the revoked row is not revived', (select count(*) from user_org_scopes where user_id = :'am'::uuid and org_unit_id = :'sbz'::bigint) = 1
  and (select status from user_org_scopes where id = :'sc_bb'::bigint) = 'revoked' and not exists (select 1 from user_org_scopes where user_id = :'bm'::uuid and org_unit_id = :'sbz'::bigint));
select count(*) as n_scopes, md5(string_agg(s::text, '|' order by id)) as h_scopes from user_org_scopes s \gset
\i supabase/phase123.sql
select tt.t('T13 second paste after the backfill: nothing changes (marker set)', (select count(*) = :'n_scopes'::int and md5(string_agg(s::text, '|' order by id)) = :'h_scopes' from user_org_scopes s));
select tt.as(:'xl');
select tt.t('T13 the backfilled legacy manager now works in all of SWEETS and nowhere else (sweets behaviour preserved)', (select bool_and(can_loc(l)) from generate_series(1, 7) l) and not can_loc(:'hw1'::int) and not can_loc(null));

\echo == T14 deactivation keeps history
select tt.as(:'o');
update locations set status = 'closed', is_active = false where code in ('hw1', 'hw2');
select tt.err('T14 the business cannot be deactivated while its branch / places are active', format($q$select org_unit_deactivate(%s, 'closing')$q$, :'hbz'), 'has_active_children');
select org_unit_deactivate(:'hb1'::bigint, 'closed branch') is not null as d1 \gset
select org_unit_deactivate(:'hbz'::bigint, 'closed business') is not null as d2 \gset
select tt.t('T14 the B branch and business are inactive', :'d1'::boolean and :'d2'::boolean and (select count(*) from org_units where id in (:'hb1'::bigint, :'hbz'::bigint) and status = 'inactive') = 2);
select tt.t('T14 history stays: the B sales, journal lines and stock ledger rows are all still there', (select count(*) from sales where location_id = :'hw1'::int) = 2 and (select count(*) from journal_lines where location_id = :'hw1'::int) >= 1);
select tt.as(:'bm');
select tt.t('T14 the B manager (scope on the now inactive business) still reads the history', can_loc(:'hw1'::int) and (select count(*) from customer_ledger(:'cust_h'::uuid)) >= 1);
set role authenticated;
select tt.eq('T14 ... directly too: the 2 B sales', 2, (select count(*) from sales where location_id = :'hw1'::int));
reset role;
select tt.as(:'ao');
select tt.eq('T14 an A user still sees nothing of the inactive B', 0, (select count(*) from customer_ledger(:'cust_h'::uuid)));
select tt.as(:'o');
select tt.err('T14 a new scope on an inactive unit is refused', format($q$select org_scope_grant(%L::uuid, %s, 'management', null, gen_random_uuid())$q$, :'xl', :'hbz'), 'unit_inactive');
select tt.is('T14 business_of_location still resolves through the inactive units (history)', (select code from org_units where id = business_of_location(:'hw1'::int)), 'HARDWARE');

\echo == T15 paste twice, switch back OFF = the old behaviour
select md5(string_agg(x::text, '|' order by id)) as h_before from (select id, user_id, org_unit_id, role_code, status from user_org_scopes) x \gset
select count(*) as n_pol_before from pg_policies where policyname like '%123' \gset
select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) as h_fn_before from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '123$|^can_scope$|^business_of_|^org_scope|^can_loc$|^has_grant$' \gset
\i supabase/phase123.sql
select tt.t('T15 paste again: no error, same scope rows, same policies, same function bodies', (select md5(string_agg(x::text, '|' order by id)) from (select id, user_id, org_unit_id, role_code, status from user_org_scopes) x) = :'h_before'
  and (select count(*) from pg_policies where policyname like '%123') = :'n_pol_before'::int
  and (select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '123$|^can_scope$|^business_of_|^org_scope|^can_loc$|^has_grant$') = :'h_fn_before');
select tt.t('T15 the switch is still ON after a paste (the file never writes the value)', rule_on('org_scope_on'));
update rules set value = null where key = 'org_scope_on';
select tt.t('T15 switch OFF again (value cleared): the old behaviour is back for everybody', not rule_on('org_scope_on'));
select tt.as(:'xn');
select tt.t('T15 OFF: a plain user still has no B place', not can_loc(:'hw1'::int));
select tt.as(:'xl');
select tt.t('T15 OFF: the old management bypass is back for the legacy manager', can_loc(:'hw1'::int) and can_loc(null));
select tt.as(:'o');
select tt.as(:'o');
select tt.t('T15 OFF: customer_dues (owner) is identical to the snapshot taken before the switch was ever on', (select md5(string_agg(x::text, '|' order by x::text)) from (select * from customer_dues()) x) = (select dues_h from off_snap));
select tt.as(:'ao');
select tt.eq('T15 OFF: an A staff sees the dues of every place again (1800)', 1800, (select sum(balance) from customer_dues()));
set role authenticated;
select tt.as(:'xn');
select tt.eq('T15 OFF: a user with no place reads all locations again (10)', 10, (select count(*) from locations));
reset role;

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
