-- FRESH DB ONLY, built through the canonical order incl. phase112 (tests/sql/final_build.sh). Phase 112 tests (profit truth), scenario = audit A3 with hand-computed numbers.
-- Run from the repo root:  psql -qAt -f supabase/phase112_test.sql
\set mode def
\i tests/sql/e2e/00_common.sql
\set ON_ERROR_STOP off
\set QUIET on
\echo == setup (audit A3 scenario)
\i tests/sql/batch1_setup.sql
select date_trunc('month',tt.today())::date as m1, (date_trunc('month',tt.today())+interval '1 month - 1 day')::date as m2,
       extract(day from (date_trunc('month',tt.today())+interval '1 month - 1 day'))::int as dim \gset
select tt.as(:'o');

\echo == T1 rules and advisor rows exist, default off
select tt.t('T1 three rules, default off', (select count(*) from rules where key in ('profit_truth_mode','cost_share_prorate_mode','items_net_of_returns') and default_value='"off"'::jsonb)=3);
select tt.t('T1 three advisor rows (phase 112) recommending on', (select count(*) from setup_rec_defs81 where phase='112' and rec_value='"on"'::jsonb and rule_key in ('profit_truth_mode','cost_share_prorate_mode','items_net_of_returns'))=3);

\echo == T2 switches off = today's figures (audit A3 section 2)
select tt.eq('T2 S1 shop P&L profit (net 920 - cogs 360 - rent 150 - salary 300)', 110, (select (x->>'profit')::numeric from _r3q_l3_shop_pnl(:'m1',:'m2',array[1,2,3,6],'{}'::jsonb) x where x->>'location_id'='2' and x->>'row_type' is null));
select tt.eq('T2 S2 shop P&L profit (640 - 320 - 40; wastage 40 is NOT in it today)', 280, (select (x->>'profit')::numeric from _r3q_l3_shop_pnl(:'m1',:'m2',array[1,2,3,6],'{}'::jsonb) x where x->>'location_id'='3' and x->>'row_type' is null));
select tt.eq('T2 company sum of the shop P&L = 110 + 280 - 200', 190, (select sum((x->>'profit')::numeric) from _r3q_l3_shop_pnl(:'m1',:'m2',array[1,2,3,6],'{}'::jsonb) x));
select tt.eq('T2 biz_items A revenue ignores the return (450 + 640)', 1090, (select revenue from biz_items(:'m1',:'m2',null) where code='FG-A'));
select tt.eq('T2 sum of biz_items revenue 1650 vs sales 1560 (audit C12)', 1650, (select sum(revenue) from biz_items(:'m1',:'m2',null)));
select set_rule('cost_attrib_in_pl','true') is null as sw \gset
select cost_attrib_main_set(1, :'m1', 'b1 main centre', gen_random_uuid()) is not null as m1x \gset
select tt.eq('T2 one-day report: whole month of bills = 0 attributed yet (no attribution settings)', 0, (select coalesce(sum((x->>'expenses')::numeric),0) from _r3q_l3_shop_pnl(tt.today(),tt.today(),array[1,2,3,6],'{}'::jsonb) x where x->>'row_type'='cost_share'));
select cost_attrib_set(2, null, 'showroom', :'m1', 'b1', gen_random_uuid()) is not null as c1 \gset
select cost_attrib_set(3, null, 'showroom', :'m1', 'b1', gen_random_uuid()) is not null as c2 \gset
select cost_attrib_set(2, 'other', 'main_centre', :'m1', 'b1 admin to head office', gen_random_uuid()) is not null as c3 \gset
select tt.eq('T2 audit C15: a ONE-DAY report shows the whole month of bills (1020), as before', 1020, (select sum((x->>'expenses')::numeric) from _r3q_l3_shop_pnl(tt.today(),tt.today(),array[1,2,3,6],'{}'::jsonb) x where x->>'row_type'='cost_share'));
select tt.eq('T2 a whole-month report: 1020', 1020, (select sum((x->>'expenses')::numeric) from _r3q_l3_shop_pnl(:'m1',:'m2',array[1,2,3,6],'{}'::jsonb) x where x->>'row_type'='cost_share'));
select set_rule('cost_attrib_in_pl','false') is null as sw0 \gset

\echo == T3 cost_share_prorate_mode on
select set_rule('cost_attrib_in_pl','true') is null as sw1 \gset
select set_rule('cost_share_prorate_mode','"on"'::jsonb) is null as pr \gset
select tt.eq('T3 one day of a 30/31-day month = 1020 / days (hand: 1020 x 1 / days in month)', round(1020::numeric / :dim, 2), (select sum((x->>'expenses')::numeric) from _r3q_l3_shop_pnl(tt.today(),tt.today(),array[1,2,3,6],'{}'::jsonb) x where x->>'row_type'='cost_share'), 0.05);
select tt.eq('T3 a quiet day with no activity shows the same 1/days share, not 1020', round(1020::numeric / :dim, 2), (select sum((x->>'expenses')::numeric) from _r3q_l3_shop_pnl(tt.today()-1,tt.today()-1,array[1,2,3,6],'{}'::jsonb) x where x->>'row_type'='cost_share') , 0.05) ;
select tt.eq('T3 the whole month is unchanged: 1020', 1020, (select sum((x->>'expenses')::numeric) from _r3q_l3_shop_pnl(:'m1',:'m2',array[1,2,3,6],'{}'::jsonb) x where x->>'row_type'='cost_share'), 0.05);
select tt.eq('T3 two days of the month: 2 x 1020 / days', round(2 * 1020::numeric / :dim, 2), (select sum((x->>'expenses')::numeric) from _r3q_l3_shop_pnl(tt.today()-1,tt.today(),array[1,2,3,6],'{}'::jsonb) x where x->>'row_type'='cost_share'), 0.05);
select set_rule('cost_share_prorate_mode','"off"'::jsonb) is null as pr0 \gset
select set_rule('cost_attrib_in_pl','false') is null as sw2 \gset

\echo == T4 profit_truth_mode on: ONE figure (audit A3 hand-computed table)
select set_rule('profit_truth_mode','"on"'::jsonb) is null as pt \gset
create temp table pt1 as select profit_truth112(:'m1',:'m2',null) j;
select tt.eq('T4 S1 net profit = 720 - 360 - rent 150 - salary 300 - card fee 7.20 - shares 610', -707.20, (select (r->>'profit')::numeric from pt1, jsonb_array_elements(j->'rows') r where r->>'location_id'='2'));
select tt.eq('T4 S2 net profit = 640 - 320 - delivery 40 - wastage 40 - shares 290', -50, (select (r->>'profit')::numeric from pt1, jsonb_array_elements(j->'rows') r where r->>'location_id'='3'));
select tt.eq('T4 factory = salary 200', -200, (select (r->>'profit')::numeric from pt1, jsonb_array_elements(j->'rows') r where r->>'location_id'='6'));
select tt.eq('T4 main centre = admin bill 120', -120, (select (r->>'profit')::numeric from pt1, jsonb_array_elements(j->'rows') r where r->>'location_id'='1'));
select tt.eq('T4 company net profit (revenue of item C with no cost left out)', -1077.20, (select (j->'company'->>'net_profit')::numeric from pt1));
select tt.eq('T4 company net profit if C really cost nothing', -877.20, (select (j->'company'->>'net_profit_if_uncosted_free')::numeric from pt1));
select tt.eq('T4 uncosted revenue shown apart (item C 2 x 100)', 200, (select (j->'company'->>'uncosted_rev')::numeric from pt1));
select tt.t('T4 provisional flag set and listed', (select (j->>'provisional')::boolean and j->'incomplete' ? 'uncosted_revenue' from pt1));
select tt.eq('T4 wastage 1 kg x cost 40 reaches the branch profit', 40, (select (j->'company'->>'wastage')::numeric from pt1));
select tt.eq('T4 card fee 7.20 reaches the branch profit', 7.20, (select (j->'company'->>'card_fees')::numeric from pt1));
select tt.eq('T4 sum of the rows = company figure', -1077.20, (select sum((x->>'profit')::numeric) from _r3q_l3_shop_pnl(:'m1',:'m2',array[1,2,3,6],'{}'::jsonb) x));
select tt.t('T4 shop P&L rows with the switch on: no separate cost_share rows (shares are inside the place)', (select count(*) from _r3q_l3_shop_pnl(:'m1',:'m2',array[1,2,3,6],'{}'::jsonb) x where x->>'row_type'='cost_share')=0);
select tt.t('T4 books figure is NOT touched (acct_income_statement still the journal)', (acct_income_statement(:'m1',:'m2',null)->>'net_profit')::numeric <> -1077.20);

\echo == T5 unallocated shared bills are their own row
create temp table sn as select s.id from cost_bill_shares s where s.active;
select cost_attrib_set(2, 'electricity', 'unallocated', :'m1', 'b1 test', gen_random_uuid()) is not null as ua \gset
create temp table pt2 as select profit_truth112(:'m1',:'m2',null) j;
select tt.t('T5 electricity share of S1 (400) now unallocated: a row of its own', (select (r->>'unallocated')::numeric from pt2, jsonb_array_elements(j->'rows') r where r->>'row_type'='unallocated')=400);
select tt.eq('T5 company figure is the same (the bill is only moved from S1 to the unallocated row)', -1077.20, (select (j->'company'->>'net_profit')::numeric from pt2));
select tt.t('T5 flagged incomplete', (select j->'incomplete' ? 'unallocated_shared_costs' from pt2));

\echo == T6 salary: sheet and payroll app are never both counted
insert into employees (employee_no, full_name_bn) values ('E112','Staff One') returning id as emp \gset
with x as (insert into payroll_runs (month, location_id, status) values (date_trunc('month', tt.today())::date, 3, 'approved') returning id) select id as run1 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, net, advance_recovery, gross) values (:'run1', date_trunc('month', tt.today())::date, :'emp', 3, 1000, 0, 1000) returning id) select id as ln1 from x \gset
select payroll_pay(:'run1'::bigint, array[:'ln1'::bigint], 'cash', tt.today(), 'r1', null, gen_random_uuid(), 1000) is not null as pay1 \gset
select tt.eq('T6 app payroll alone: S2 salary = 1000 (the old shop P&L shows none)', 1000, (select (r->>'salary')::numeric from jsonb_array_elements(profit_truth112(:'m1',:'m2',3)->'rows') r where r->>'location_id'='3'));
select format('{"month":"%s","year":"%s","pay":[{"name":"S2 Clerk - Clerk","due":400}]}', extract(month from tt.today())::int, extract(year from tt.today())::int) as sheetdata \gset
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('02-2',3,8103,tt.today(),'approved',:'sheetdata'::jsonb,'[]',:'o','st');
select id as sheet2 from entries where form_code='02-2' and serial=8103 \gset
select tt.t('T6 the pair (sheet 400 for the same month and place, app 1000) was linked by the system', exists (select 1 from shadow_links x where x.state <> 'void' and ((x.shadow_type='entries' and x.shadow_id=:'sheet2') or (x.shadow_type='payroll_runs' and x.shadow_id=:'run1'::text))));
select tt.t('T6 salary of S2 is one of the two records (1000 or 400), never 1400', (select (r->>'salary')::numeric in (1000, 400) from jsonb_array_elements(profit_truth112(:'m1',:'m2',3)->'rows') r where r->>'location_id'='3'));
select tt.eq('T6 and it is the primary record', case when is_shadow('entries', :'sheet2') then 1000 else 400 end, (select (r->>'salary')::numeric from jsonb_array_elements(profit_truth112(:'m1',:'m2',3)->'rows') r where r->>'location_id'='3'));

\echo == T7 items_net_of_returns
select tt.eq('T7 off: A revenue 1090', 1090, (select revenue from biz_items(:'m1',:'m2',null) where code='FG-A'));
select set_rule('items_net_of_returns','"on"'::jsonb) is null as nr \gset
select tt.eq('T7 on: A revenue 1090 - 90 refund = 1000', 1000, (select revenue from biz_items(:'m1',:'m2',null) where code='FG-A'));
select tt.eq('T7 on: A quantity 13 - 1 = 12', 12, (select qty from biz_items(:'m1',:'m2',null) where code='FG-A'));
select tt.eq('T7 on: A cost 520 - 40 = 480', 480, (select cogs from biz_items(:'m1',:'m2',null) where code='FG-A'));
select tt.eq('T7 on: S1 only, A revenue 450 - 90 = 360 (audit: product A at S1)', 360, (select revenue from biz_items(:'m1',:'m2',2) where code='FG-A'));
select tt.eq('T7 on: all items 1650 - 90 = 1560 = biz_daily revenue (audit C12)', (select sum(revenue) from biz_daily(:'m1',:'m2',null)), (select sum(revenue) from biz_items(:'m1',:'m2',null)));
select tt.eq('T7 on: costs add up to the journal (680), item C stays unknown', 680, (select sum(cogs) from biz_items(:'m1',:'m2',null)));
select tt.t('T7 on: the by-category report follows (sweet_kg revenue 1000)', (select revenue from biz_items_by_category(:'m1',:'m2',null,'category') where category='sweet_kg')=1000);
select set_rule('items_net_of_returns','"off"'::jsonb) is null as nr0 \gset

\echo == T8 secrecy and tags
select tt.as(:'ap');
select tt.err('T8 a person without cost / accounts rights cannot read the true profit', $$select profit_truth112(date_trunc('month',now())::date, now()::date, null)$$, 'not allowed');
select tt.as(:'o');
select tt.t('T8 bos112 tag in the three re-created functions, older tags kept',
  (select bool_and(d ~ 'bos112') from (select pg_get_functiondef(p.oid) d from pg_proc p where p.proname in ('_r3q_l3_shop_pnl','biz_items','_c78_rows','profit_truth112','_pnl_truth112','_pl_extra112','_c78_rows112')) x)
  and pg_get_functiondef('public.biz_items(date,date,integer)'::regprocedure) ~ 'bos88' and pg_get_functiondef('public.biz_items(date,date,integer)'::regprocedure) ~ 'bos14'
  and pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)'::regprocedure) ~ 'bos72' and pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)'::regprocedure) ~ 'bos78');
select tt.t('T8 the internal helpers are not callable from the app', not has_function_privilege('authenticated', 'public._pnl_truth112(date,date,integer[])', 'execute') and has_function_privilege('authenticated', 'public.profit_truth112(date,date,integer)', 'execute'));

\echo == T9 paste twice changes nothing
create temp table f0 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace = 'public'::regnamespace;
\i supabase/phase112.sql
select tt.t('T9 no function changed by pasting phase112 again', (select count(*) from pg_proc p join f0 on f0.fn = p.oid::regprocedure::text where p.pronamespace = 'public'::regnamespace and md5(pg_get_functiondef(p.oid)) <> f0.h) = 0);
select tt.t('T9 no rule row duplicated', (select count(*) from rules where key in ('profit_truth_mode','cost_share_prorate_mode','items_net_of_returns'))=3);
select tt.t('T9 the books stay balanced', tt.unbalanced()=0);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
