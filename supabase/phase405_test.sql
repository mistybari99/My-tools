-- FRESH DB ONLY. Phase 405 tests: production capture entry functions (package RPT-B4, R3).
--   Build a database through phase 99, paste supabase/phase404.sql and phase405.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase405_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql and rb4_fixture2.sql (hand-computed numbers in the headers). Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\ir ../tests/sql/rb4_fixture2.sql
\set ON_ERROR_STOP off
select tt.today() as td \gset

\echo == T0 shape
select tt.chk('T0 five tables with row level security on, browsers can read but not write',
  (select count(*) from pg_class where relname in ('production_plans','production_orders','production_run_links','production_issue_actual','production_loss') and relrowsecurity) = 5
  and not has_table_privilege('authenticated','public.production_plans','insert') and not has_table_privilege('authenticated','public.production_loss','update') and has_table_privilege('authenticated','public.production_orders','select'));
select tt.chk('T0 internals closed to browsers, entry functions open to signed-in users only',
  not has_function_privilege('authenticated','public._rb4_run_booked(uuid)','execute') and not has_function_privilege('authenticated','public._rb4_order_made(bigint)','execute')
  and has_function_privilege('authenticated','public.prod_plan_add(date,int,uuid,numeric,numeric,text,uuid,text,uuid)','execute') and not has_function_privilege('anon','public.prod_plan_add(date,int,uuid,numeric,numeric,text,uuid,text,uuid)','execute'));
select tt.chk('T0 production_post was not touched (still the phase79 body, no bos404 marker)', position('bos404' in pg_get_functiondef('public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)'::regprocedure)) = 0);

\echo == T1 plan
select tt.chk('T1 plan A: 2 batches of a recipe that yields 10 kg -> planned quantity 20 (derived from the newest active recipe)', (select planned_batches = 2 and planned_qty = 20 and recipe_id = :'rc'::uuid and created_staff is not null from production_plans where id = :'plan_a'::uuid));
select tt.as(:'o');
select (prod_plan_add(:'td'::date, 5, :'i_fg'::uuid, null, 7.5, 'kg', null, 'test qty only', gen_random_uuid()) ->> 'id')::uuid as plan_q \gset
select tt.chk('T1 a plan with a quantity only keeps the batches blank (not captured), never 0', (select planned_batches is null and planned_qty = 7.5 from production_plans where id = :'plan_q'::uuid));
select tt.err('T1 no batches and no quantity: refused', format($$select prod_plan_add(%L::date,5,%L::uuid)$$, :'td', :'i_fg'), 'plan_needs_batches_or_qty');
select tt.err('T1 unknown item: refused', format($$select prod_plan_add(%L::date,5,gen_random_uuid(),1)$$, :'td'), 'item_not_found');
select tt.err('T1 an unknown unit is refused, not guessed', format($$select prod_plan_add(%L::date,5,%L::uuid,null,3,'bucket')$$, :'td', :'i_fg'), 'unit_unknown');
select tt.err('T1 a recipe of another item is refused', format($$select prod_plan_add(%L::date,5,%L::uuid,1,null,null,%L::uuid)$$, :'td', :'i_rm', :'rc'), 'recipe_not_found');
select (prod_plan_add(:'td'::date, 5, :'i_fg'::uuid, 1, null, null, null, null, '00000000-0000-0000-0000-00000000c001') ->> 'id')::uuid as plan_d \gset
select tt.chk('T1 the same client id twice returns the first plan, no second row', (select (prod_plan_add(:'td'::date, 5, :'i_fg'::uuid, 1, null, null, null, null, '00000000-0000-0000-0000-00000000c001') ->> 'dup')::boolean) and (select count(*) from production_plans where client_id = '00000000-0000-0000-0000-00000000c001') = 1);
select tt.err('T1 cancel needs a reason of 3 characters', format($$select prod_plan_cancel(%L::uuid,'x')$$, :'plan_d'), 'note_required');
select prod_plan_cancel(:'plan_d'::uuid, 'test cancel') is not null as w_c \gset
select tt.chk('T1 a cancelled plan stays as a row with who and when', (select status = 'cancelled' and cancelled_by is not null and cancel_note = 'test cancel' from production_plans where id = :'plan_d'::uuid));
select tt.as(:'shop');
select tt.err('T1 a salesperson cannot enter a plan (server refusal)', format($$select prod_plan_add(%L::date,5,%L::uuid,1)$$, :'td', :'i_fg'), 'not allowed');
select tt.as(:'rep');
select tt.err('T1 a report reader without the production grant cannot enter a plan', format($$select prod_plan_add(%L::date,5,%L::uuid,1)$$, :'td', :'i_fg'), 'not allowed');
select tt.as(:'o');

\echo == T2 order
select tt.chk('T2 three orders were entered, numbered by the system, with their places and base-unit quantities', (select count(*) from production_orders where id in (:'ord1', :'ord2', :'ord3')) = 3
  and (select qty = 25 and for_location_id = 1 and status = 'open' from production_orders where id = :'ord1'::bigint));
select tt.err('T2 due day before the order day: refused', format($$select prod_order_add(%L::date,%L::date,5,null,%L::uuid,5)$$, :'td', (:'td'::date - 2)::text, :'i_fg'), 'bad_date');
select tt.err('T2 the requesting outlet cannot be the producing place', format($$select prod_order_add(%L::date,null,5,5,%L::uuid,5)$$, :'td', :'i_fg'), 'bad_location');
select tt.chk('T2 made so far: order 1 = 18 (run 1), order 2 = 10 (run 2), order 3 = 0', public._rb4_order_made(:'ord1'::bigint) = 18 and public._rb4_order_made(:'ord2'::bigint) = 10 and public._rb4_order_made(:'ord3'::bigint) = 0);
select tt.err('T2 closing an order short of its quantity needs a reason', format($$select prod_order_close(%L::bigint)$$, :'ord1'), 'note_required');
select tt.chk('T2 closing a fully made order needs no reason', (prod_order_close(:'ord2'::bigint) ->> 'status') = 'closed');
select tt.chk('T2 closing it twice is a no-op', (prod_order_close(:'ord2'::bigint) ->> 'dup')::boolean);
select tt.chk('T2 closing short with a reason works', (prod_order_close(:'ord1'::bigint, 'test: customer agreed to 18') ->> 'status') = 'closed');
select tt.chk('T2 the reason is kept on the order', (select close_note like 'test:%' and closed_by is not null from production_orders where id = :'ord1'::bigint));
select tt.err('T2 a closed order cannot be cancelled', format($$select prod_order_cancel(%L::bigint,'test reason')$$, :'ord1'), 'order_not_open');
select prod_order_cancel(:'ord3'::bigint, 'test: not needed') is not null as w_oc \gset
select tt.chk('T2 a cancelled order stays as a row', (select status = 'cancelled' from production_orders where id = :'ord3'::bigint));
-- reopen a new open order for the later tests of this file
select (prod_order_add(:'td'::date, :'td'::date + 3, 5, 1, :'i_fg'::uuid, 12, null, 'test order 4', gen_random_uuid()) ->> 'id')::bigint as ord4 \gset
select tt.as(:'shop');
select tt.err('T2 a salesperson who may not move stock cannot raise an order', format($$select prod_order_add(%L::date,null,5,1,%L::uuid,5)$$, :'td', :'i_fg'), 'not allowed');
select tt.as(:'o');

\echo == T3 link
select tt.chk('T3 run 1 is linked to plan A and order 1', (select plan_id = :'plan_a'::uuid and order_id = :'ord1'::bigint from production_run_links where run_id = :'run1'::uuid));
select (prod_plan_add(:'td'::date, 6, :'i_fg'::uuid, 1) ->> 'id')::uuid as plan_other \gset
select tt.err('T3 a plan of another place cannot be linked', format($$select prod_run_link(%L::uuid,%L::uuid)$$, :'run1', :'plan_other'), 'link_mismatch');
select tt.err('T3 a cancelled plan cannot be linked', format($$select prod_run_link(%L::uuid,%L::uuid)$$, :'run2', :'plan_d'), 'plan_cancelled');
select tt.err('T3 a closed order cannot get a new link', format($$select prod_run_link(%L::uuid,null,%L::bigint)$$, :'run2', :'ord1'), 'order_not_open');
select prod_run_link(:'run2'::uuid, null, :'ord4'::bigint) is not null as w_l3 \gset
select tt.chk('T3 linking run 2 to order 4 works; the plan stays blank', (select order_id = :'ord4'::bigint and plan_id is null from production_run_links where run_id = :'run2'::uuid));
select tt.chk('T3 the change is in the audit log', (select count(*) from audit_log where table_name = 'production_run_links' and record_id = :'run2') >= 2);
select prod_run_link(:'run2'::uuid, null, null, false, true) is not null as w_l5 \gset
select tt.chk('T3 clearing the order link leaves the row, order blank', (select order_id is null from production_run_links where run_id = :'run2'::uuid));
select prod_run_link(:'run2'::uuid, null, :'ord4'::bigint) is not null as w_l6 \gset

\echo == T4 real use of ingredients (blind until saved)
select tt.chk('T4 run 1: both lines saved: milk 13, sugar 6', (select count(*) from production_issue_actual where run_id = :'run1'::uuid and status = 'active') = 2
  and (select actual_qty from production_issue_actual where run_id = :'run1'::uuid and item_id = :'i_rm'::uuid and status = 'active') = 13);
select public.prod_run_detail(:'run2'::uuid) as d2 \gset
select tt.chk('T4 run 2 (nothing saved): the booked recipe quantity is NOT shown (blind), the actual is empty', (select bool_and(l -> 'booked_qty' = 'null'::jsonb and l -> 'actual_qty' = 'null'::jsonb) from jsonb_array_elements(:'d2'::jsonb -> 'issue_lines') l)
  and jsonb_array_length(:'d2'::jsonb -> 'issue_lines') = 2);
select public.prod_run_detail(:'run1'::uuid) as d1 \gset
select tt.chk('T4 run 1 (saved): the booked quantity is shown after the save: milk booked 12, real 13, diff +1; sugar diff 0', (select tt.n(l, 'booked_qty') = 12 and tt.n(l, 'actual_qty') = 13 and tt.n(l, 'diff') = 1 from jsonb_array_elements(:'d1'::jsonb -> 'issue_lines') l where l ->> 'code' = 'RB4-RM')
  and (select tt.n(l, 'diff') = 0 from jsonb_array_elements(:'d1'::jsonb -> 'issue_lines') l where l ->> 'code' = 'RB4-SG'));
select prod_actual_issue_set(:'run1'::uuid, jsonb_build_array(jsonb_build_object('item_id', :'i_rm', 'qty', 13.5)), 'test second look') is not null as w_a2 \gset
select tt.chk('T4 a second value for milk replaces the first; the first stays as history (replaced); sugar untouched', (select count(*) from production_issue_actual where run_id = :'run1'::uuid and item_id = :'i_rm'::uuid) = 2
  and (select actual_qty from production_issue_actual where run_id = :'run1'::uuid and item_id = :'i_rm'::uuid and status = 'active') = 13.5
  and (select count(*) from production_issue_actual where run_id = :'run1'::uuid and item_id = :'i_sg'::uuid) = 1);
select prod_actual_issue_set(:'run1'::uuid, jsonb_build_array(jsonb_build_object('item_id', :'i_rm', 'qty', 13)), 'test back to 13') is not null as w_a3 \gset
select tt.err('T4 a negative quantity is refused', format($$select prod_actual_issue_set(%L::uuid, '[{"item_id":"%s","qty":"-1"}]'::jsonb)$$, :'run2', :'i_rm'), 'bad_qty');
select tt.err('T4 an unknown unit is refused', format($$select prod_actual_issue_set(%L::uuid, '[{"item_id":"%s","qty":1,"unit":"bucket"}]'::jsonb)$$, :'run2', :'i_rm'), 'unit_unknown');
select tt.err('T4 the same ingredient twice in one call is refused', format($$select prod_actual_issue_set(%L::uuid, '[{"item_id":"%s","qty":1},{"item_id":"%s","qty":2}]'::jsonb)$$, :'run2', :'i_rm', :'i_rm'), 'duplicate_item');
select tt.err('T4 an empty call is refused', format($$select prod_actual_issue_set(%L::uuid, '[]'::jsonb)$$, :'run2'), 'no_lines');
select tt.chk('T4 a refused call wrote nothing for run 2', (select count(*) from production_issue_actual where run_id = :'run2'::uuid) = 0);
select tt.chk('T4 stock was NOT moved by the capture: milk at place 5 is still 100 - 12 - 6 = 82', (select qty from stock_balance where item_id = :'i_rm'::uuid and location_id = 5) = 82);
select tt.as(:'shop');
select tt.err('T4 a salesperson cannot record real use', format($$select prod_actual_issue_set(%L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb)$$, :'run2', :'i_rm'), 'not allowed');
select tt.err('T4 a salesperson at place 1 cannot read a run of place 5', format($$select prod_run_detail(%L::uuid)$$, :'run2'), 'not allowed');
select tt.as(:'o');

\echo == T5 reject / rework
select tt.chk('T5 run 1: reject 1 kg (burnt) and rework 0.5 kg (broken) are saved', (select count(*) from production_loss where run_id = :'run1'::uuid and status = 'active' and kind in ('reject','rework')) = 2
  and (select qty from production_loss where run_id = :'run1'::uuid and kind = 'rework') = 0.5);
select tt.chk('T5 run 2: "checked, none" is saved with quantity 0', (select kind = 'none' and qty = 0 and reason_code is null from production_loss where run_id = :'run2'::uuid and status = 'active'));
select tt.err('T5 a reject needs a reason from the wastage list', format($$select prod_loss_add(%L::uuid,'reject',1,null,null)$$, :'run2'), 'reason_required');
select tt.err('T5 a reason that is not in the list is refused', format($$select prod_loss_add(%L::uuid,'reject',1,null,'made_up')$$, :'run2'), 'reason_required');
select tt.err('T5 more reject + rework than the run made is refused (18 made, 1.5 already)', format($$select prod_loss_add(%L::uuid,'reject',17,null,'burnt')$$, :'run1'), 'exceeds_output');
select tt.err('T5 a quantity of 0 is refused (use "none")', format($$select prod_loss_add(%L::uuid,'reject',0,null,'burnt')$$, :'run1'), 'bad_qty');
select tt.err('T5 an unknown kind is refused', format($$select prod_loss_add(%L::uuid,'lost',1,null,'burnt')$$, :'run1'), 'bad_kind');
select tt.err('T5 "none" after a recorded loss is refused', format($$select prod_loss_add(%L::uuid,'none')$$, :'run1'), 'loss_already_recorded');
select prod_loss_add(:'run2'::uuid, 'reject', 0.25, null, 'spoiled', 'test later find') is not null as w_x4 \gset
select tt.chk('T5 a recorded loss voids the earlier "none" line of that run (history kept)', (select count(*) from production_loss where run_id = :'run2'::uuid and kind = 'none' and status = 'void') = 1
  and (select count(*) from production_loss where run_id = :'run2'::uuid and kind = 'reject' and status = 'active') = 1);
select id as lx from production_loss where run_id = :'run2'::uuid and kind = 'reject' \gset
select tt.err('T5 voiding a loss needs a reason', format($$select prod_loss_void(%L::uuid,'')$$, :'lx'), 'note_required');
select prod_loss_void(:'lx'::uuid, 'test entered twice') is not null as w_xv \gset
select tt.chk('T5 a voided loss stays as a row', (select status = 'void' and void_note = 'test entered twice' from production_loss where id = :'lx'::uuid));
select prod_loss_add(:'run2'::uuid, 'none') is not null as w_x5 \gset
select tt.chk('T5 stock was NOT moved by the loss capture (finished sweet at place 5 still 10)', (select qty from stock_balance where item_id = :'i_fg'::uuid and location_id = 5) = 10);

\echo == T6 void run, reading rights, lists
select production_post(5, :'rc'::uuid, 1, gen_random_uuid(), now() - interval '2 hours', 'test run to void') ->> 'run_id' as run3 \gset
select production_void(:'run3'::uuid, 'test void') is not null as w_pv \gset
select tt.err('T6 real use on a voided run is refused', format($$select prod_actual_issue_set(%L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb)$$, :'run3', :'i_rm'), 'run_void');
select tt.err('T6 a loss on a voided run is refused', format($$select prod_loss_add(%L::uuid,'none')$$, :'run3'), 'run_void');
select tt.err('T6 linking a voided run is refused', format($$select prod_run_link(%L::uuid,null,%L::bigint)$$, :'run3', :'ord4'), 'run_void');
select tt.as(:'rep');
select tt.chk('T6 a report reader at place 5 sees the recent runs (voided one left out) and cannot edit', jsonb_array_length(public.prod_runs_recent(:'td'::date - 10, :'td'::date, 5) -> 'rows') = 2
  and (select bool_and(not (r ->> 'can_edit')::boolean) from jsonb_array_elements(public.prod_runs_recent(:'td'::date - 10, :'td'::date, 5) -> 'rows') r));
select tt.err('T6 a bad range is refused', $$select prod_runs_recent(current_date, current_date - 5)$$, 'bad_range');
select tt.as(:'fac');
select tt.chk('T6 the factory in-charge sees can_edit = true on its runs', (select bool_and((r ->> 'can_edit')::boolean) from jsonb_array_elements(public.prod_runs_recent(:'td'::date - 10, :'td'::date, 5) -> 'rows') r));
select tt.chk('T6 run list shows capture state: run 1 = 2 issue lines + loss recorded + linked; run 2 = 0 lines + loss none + linked',
  (select (r ->> 'actual_issue_lines')::int = 2 and r ->> 'loss_state' = 'recorded' and (r ->> 'linked')::boolean from jsonb_array_elements(public.prod_runs_recent(:'td'::date - 10, :'td'::date, 5) -> 'rows') r where r ->> 'run_id' = :'run1')
  and (select (r ->> 'actual_issue_lines')::int = 0 and r ->> 'loss_state' = 'none' and (r ->> 'linked')::boolean from jsonb_array_elements(public.prod_runs_recent(:'td'::date - 10, :'td'::date, 5) -> 'rows') r where r ->> 'run_id' = :'run2'));
select tt.as(:'o');

\echo == T7 paste twice and audit
\ir phase404.sql
\ir phase405.sql
select tt.chk('T7 pasting both files again changes nothing (counts unchanged)', (select count(*) from production_plans) = 5 and (select count(*) from production_orders) = 4);
select tt.chk('T7 every capture table writes audit lines', (select count(distinct table_name) from audit_log where table_name in ('production_plans','production_orders','production_run_links','production_issue_actual','production_loss')) = 5);
select tt.chk('T7 the shared helpers did not change the visibility of the other tables (production_runs policy unchanged)', (select count(*) from pg_policy where polrelid = 'public.production_runs'::regclass) = 1);

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
