-- FRESH DB ONLY. Phase 463 tests (RPT-C3 R8 part 2): #180 approval delays, #174 stock adjustment approval history, #183 missing cost / recipe / batch / expiry data.
--   bash tests/sql/rptc3_run.sh 463
-- Test data only (test_* names). Timestamps of the crafted rows are set in the test so the hours are exact.
\ir ../tests/sql/rptc3_head.sql
select to_char(tt.today() - 5, 'YYYY-MM-DD') as f, to_char(tt.today() + 1, 'YYYY-MM-DD') as t \gset
select tt.as(:'u_o');
insert into user_grants (user_id, grant_code, location_id) values (:'u_ex', 'report_control', null) on conflict do nothing;
select set_config('app.fixed_now', now()::text, false);

-- crafted requests: two approved sheets (4.0 h and 6.0 h), one sheet still waiting for 50 h, a change request decided in 8.0 h, wastage decided in 3.0 h and one waiting 20 h
select save_entry(null,'18-1',1,tt.today(), jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('date',tt.today()::text,'head','2','amt','11','source','bank'))), '[]') ->> 'id' as e1 \gset
select save_entry(null,'18-1',1,tt.today(), jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('date',tt.today()::text,'head','2','amt','12','source','bank'))), '[]') ->> 'id' as e2 \gset
select save_entry(null,'18-1',1,tt.today(), jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('date',tt.today()::text,'head','2','amt','13','source','bank'))), '[]') ->> 'id' as e3 \gset
select submit_entry(:'e1'::uuid) is not null as s1 \gset
select submit_entry(:'e2'::uuid) is not null as s2 \gset
select submit_entry(:'e3'::uuid) is not null as s3 \gset
update entries set status = 'approved', submitted_at = now() - interval '10 hours', checked_at = now() - interval '6 hours', checked_staff = 'test_appr', checked_by = :'u_acc'::uuid where id = :'e1'::uuid;
update entries set status = 'approved', submitted_at = now() - interval '30 hours', checked_at = now() - interval '24 hours', checked_staff = 'test_appr', checked_by = :'u_acc'::uuid where id = :'e2'::uuid;
update entries set submitted_at = now() - interval '50 hours' where id = :'e3'::uuid;
insert into entry_change_requests (entry_id, base_rev, requested_by, requested_staff, reason, patch, status, created_at, decided_by, decided_staff, decided_at, decision_note)
  values (:'e1'::uuid, 1, :'u_st'::uuid, 'test_st', 'test change', '{}', 'approved', now() - interval '12 hours', :'u_acc'::uuid, 'test_appr', now() - interval '4 hours', 'ok');
select id as fg from items where code = 'W1D-FG' \gset
insert into wastage_requests (client_id, item_id, location_id, qty, reason_code, status, requested_by, requested_staff, requested_at, decided_by, decided_staff, decided_at)
  values (gen_random_uuid(), :'fg'::uuid, 1, 2, 'spoiled', 'approved', :'u_st'::uuid, 'test_st', now() - interval '9 hours', :'u_acc'::uuid, 'test_appr', now() - interval '6 hours'),
         (gen_random_uuid(), :'fg'::uuid, 1, 1, 'spoiled', 'pending', :'u_st'::uuid, 'test_st', now() - interval '20 hours', null, null, null);

-- T1 approval delays
select aud_approval_delays(:'f'::date, :'t'::date) as ad \gset
select tt.chk('T1 forms: asked, decided and waiting counted from the data', (select tt.n(x,'asked') = (select count(*) from entries where submitted_at is not null and status in ('submitted','approved','rejected') and (submitted_at at time zone 'Asia/Dhaka')::date between tt.today()-5 and tt.today()+1)
   and tt.n(x,'pending') = 1 from jsonb_array_elements((:'ad'::jsonb)->'by_kind') x where x->>'kind' = 'form'));
select tt.chk('T1 forms: the longest wait among the decided is 6.0 hours', (select tt.n(x,'max_hours') = 6.0 from jsonb_array_elements((:'ad'::jsonb)->'by_kind') x where x->>'kind' = 'form'));
select tt.chk('T1 forms: the average equals the hand calculation over the decided sheets', (select abs(tt.n(x,'avg_hours') - (select round(avg(extract(epoch from (checked_at - submitted_at)) / 3600.0), 1) from entries where submitted_at is not null and status in ('approved','rejected') and (submitted_at at time zone 'Asia/Dhaka')::date between tt.today()-5 and tt.today()+1)) < 0.11 from jsonb_array_elements((:'ad'::jsonb)->'by_kind') x where x->>'kind' = 'form'));
select tt.chk('T1 change request: 1 decided in 8.0 hours', (select tt.n(x,'decided') = 1 and tt.n(x,'avg_hours') = 8.0 from jsonb_array_elements((:'ad'::jsonb)->'by_kind') x where x->>'kind' = 'change_request'));
select tt.chk('T1 wastage: 2 asked, 1 approved in 3.0 hours, 1 waiting', (select tt.n(x,'asked') = 2 and tt.n(x,'approved') = 1 and tt.n(x,'pending') = 1 and tt.n(x,'avg_hours') = 3.0 and tt.n(x,'median_hours') = 3.0 from jsonb_array_elements((:'ad'::jsonb)->'by_kind') x where x->>'kind' = 'wastage'));
select tt.chk('T1 by approver: test_appr decided 4 (two sheets, a change request, a wastage request), longest 8.0 h', (select tt.n(x,'decided') = 4 and tt.n(x,'max_hours') = 8.0 from jsonb_array_elements((:'ad'::jsonb)->'by_approver') x where x->>'approver' = 'test_appr'));
select tt.chk('T1 the waiting list is oldest first: the 50 h sheet, then the 20 h wastage request', (:'ad'::jsonb)->'pending'->0->>'kind' = 'form' and tt.n((:'ad'::jsonb)->'pending'->0,'age_hours') >= 50 and (:'ad'::jsonb)->'pending'->1->>'kind' = 'wastage' and tt.n((:'ad'::jsonb)->'pending'->1,'age_hours') >= 20);
select tt.chk('T1 it says hours are clock hours and no "late" limit is invented', (:'ad'::jsonb)->'notes' @> '["clock_hours_not_working_hours","no_late_limit_invented"]'::jsonb);
select tt.chk('T1 a quiet window gives empty lists, not zero rows of numbers', jsonb_array_length(aud_approval_delays(tt.today()-400, tt.today()-390)->'by_kind') = 0);

-- T2 access
select tt.as(:'u_nb');
select tt.err('T2 nobody: approval delays', format($$select aud_approval_delays('%s','%s')$$, :'f', :'t'), 'not allowed');
select tt.err('T2 nobody: stock adjustments', format($$select aud_stock_adjustments('%s','%s')$$, :'f', :'t'), 'not allowed');
select tt.err('T2 nobody: gaps', $$select aud_cost_gaps()$$, 'not allowed');
select tt.as(:'u_rm');
select tt.err('T2 a marketing reader: approval delays', format($$select aud_approval_delays('%s','%s')$$, :'f', :'t'), 'not allowed');
select tt.as(:'u_ex');
select tt.chk('T2 a report_control reader may read', jsonb_array_length(aud_approval_delays(:'f'::date, :'t'::date)->'by_kind') >= 3);
select tt.err('T2 a place he cannot see', format($$select aud_approval_delays('%s','%s',2)$$, :'f', :'t'), 'not allowed');
select tt.as(:'u_o');

-- T3 stock adjustments (#174)
select aud_stock_adjustments(:'f'::date, :'t'::date) as sa \gset
select tt.chk('T3 the four kinds are all present: wastage request, direct wastage, direct count, transit loss', (select count(distinct x->>'kind') from jsonb_array_elements((:'sa'::jsonb)->'rows') x) >= 4);
select tt.chk('T3 the approved wastage request shows asker, approver and 3.0 hours', (select x->>'asked_by' = 'test_st' and x->>'approver' = 'test_appr' and tt.n(x,'hours_to_decide') = 3.0 and tt.n(x,'qty') = -2 from jsonb_array_elements((:'sa'::jsonb)->'rows') x where x->>'kind' = 'wastage_request' and x->>'status' = 'approved'));
select tt.chk('T3 the waiting request has no approver yet and is NOT counted as missing', (select x->>'approver' is null and (x->>'approver_missing') = 'false' from jsonb_array_elements((:'sa'::jsonb)->'rows') x where x->>'kind' = 'wastage_request' and x->>'status' = 'pending'));
select tt.chk('T3 direct wastage (3 x 10) has no approver by nature and a value of -30', (select x->>'approver' is null and tt.n(x,'value') = -30 from jsonb_array_elements((:'sa'::jsonb)->'rows') x where x->>'kind' = 'wastage_direct'));
select tt.chk('T3 the direct count adjustment (50 -> 47 at 40) is -3 and -120', (select tt.n(x,'qty') = -3 and tt.n(x,'value') = -120 from jsonb_array_elements((:'sa'::jsonb)->'rows') x where x->>'kind' = 'count_direct'));
select tt.chk('T3 the transit loss decision names who decided', (select x->>'approver' is not null and tt.n(x,'qty') = -2 from jsonb_array_elements((:'sa'::jsonb)->'rows') x where x->>'kind' = 'transit_loss'));
select tt.as(:'u_ex');
select aud_stock_adjustments(:'f'::date, :'t'::date) as sa2 \gset
select tt.chk('T3 a reader without the cost right sees no unit values and is told', (select bool_and(x->>'unit_cost' is null and x->>'value' is null) from jsonb_array_elements((:'sa2'::jsonb)->'rows') x) and (:'sa2'::jsonb)->'notes' ? 'cost_hidden');
select tt.as(:'u_o');

-- T4 data gaps (#183)
insert into items (code, name_bn, name_en, unit, base_unit, sell_price, tracked, item_type) values
 ('C3-NOCOST', 'test_nocost', 'test_nocost', 'piece', 'piece', 50, false, 'resale'), ('C3-FG2', 'test_fg2', 'test_fg2', 'piece', 'piece', 80, true, 'finished_good'), ('C3-ING', 'test_ing', 'test_ing', 'kg', 'kg', 0, true, 'raw_material');
select id as ing from items where code = 'C3-ING' \gset
select id as fg2 from items where code = 'C3-FG2' \gset
select (recipe_save(null, :'fg2'::uuid, 10, null, 'c3 gap recipe', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'ing','qty',2)))->>'id') is not null as rcp \gset
insert into stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, batch_no) values (:'fg'::uuid, 1, now(), 5, 5, null, 'TEST-B-NOEXP'), (:'fg'::uuid, 1, now(), 5, 5, now() + interval '5 days', 'TEST-B-EXP');
select aud_cost_gaps() as gp \gset
select tt.chk('T4 an item with no cost price is listed (and one with a cost is not)', exists (select 1 from jsonb_array_elements((:'gp'::jsonb)->'sections'->'item_no_cost'->'rows') x where x->>'code' = 'C3-NOCOST') and not exists (select 1 from jsonb_array_elements((:'gp'::jsonb)->'sections'->'item_no_cost'->'rows') x where x->>'code' = 'W1D-FG'));
select tt.chk('T4 a finished good with no recipe is listed; one with a recipe is not', exists (select 1 from jsonb_array_elements((:'gp'::jsonb)->'sections'->'fg_no_recipe'->'rows') x where x->>'code' = 'W1D-FG') is false and exists (select 1 from jsonb_array_elements((:'gp'::jsonb)->'sections'->'fg_no_recipe'->'rows') x where x->>'code' = 'C3-FG2') is false);
select tt.chk('T4 the recipe line with no waste percentage is listed', exists (select 1 from jsonb_array_elements((:'gp'::jsonb)->'sections'->'recipe_waste_missing'->'rows') x where x->>'ingredient' = 'C3-ING'));
select tt.chk('T4 an ingredient with no cost under the method is listed (wraps d_recipe_cost_gaps)', exists (select 1 from jsonb_array_elements((:'gp'::jsonb)->'sections'->'ingredient_no_cost'->'rows') x where x->>'code' = 'C3-ING'));
select tt.chk('T4 a stock batch with no expiry date is listed; one with a date is not', exists (select 1 from jsonb_array_elements((:'gp'::jsonb)->'sections'->'batch_no_expiry'->'rows') x where x->>'batch_no' = 'TEST-B-NOEXP') and not exists (select 1 from jsonb_array_elements((:'gp'::jsonb)->'sections'->'batch_no_expiry'->'rows') x where x->>'batch_no' = 'TEST-B-EXP'));
select tt.chk('T4 every section carries an exact total', tt.n((:'gp'::jsonb)->'sections'->'item_no_cost','total') >= 1 and tt.n((:'gp'::jsonb)->'sections'->'batch_no_expiry','total') = 1);
select tt.as(:'u_ex');
select aud_cost_gaps() as gp2 \gset
select tt.chk('T4 without the cost right the ingredient-cost section is withheld and says why', (:'gp2'::jsonb)->'sections'->'ingredient_no_cost'->>'cost_hidden' = 'true' and (:'gp2'::jsonb)->'notes' ? 'ingredient_costs_need_the_cost_right' and tt.n((:'gp2'::jsonb)->'sections'->'item_no_cost','total') >= 1);
select tt.as(:'u_o');
\i supabase/phase463.sql
select tt.chk('T5 paste twice: still answers', tt.n(aud_stock_adjustments(:'f'::date, :'t'::date)->'totals','rows') >= 4);
select tt.chk('T5 nothing was written to the books', tt.unbalanced() = 0);
\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
