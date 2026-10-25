-- RPT-B4 fixture, second part (needs phases 404 and 405): plans, orders, links, real use, losses. Runs after tests/sql/rb4_fixture.sql. Test data only (test_* names). Numbers: see the header of rb4_fixture.sql.
\set ON_ERROR_STOP on
select tt.as(:'fac');      -- the factory in-charge enters the capture (grant stock_production at place 5)
select (prod_plan_add(tt.today() - 3, 5, :'i_fg'::uuid, 2, null, null, null, 'test plan A', gen_random_uuid()) ->> 'id')::uuid as plan_a \gset
select (prod_plan_add(tt.today() + 2, 5, :'i_fg'::uuid, 1, null, null, null, 'test plan C', gen_random_uuid()) ->> 'id')::uuid as plan_c \gset
select (prod_order_add(tt.today() - 6, tt.today() - 1, 5, 1, :'i_fg'::uuid, 25, null, 'test order 1', gen_random_uuid()) ->> 'id')::bigint as ord1 \gset
select (prod_order_add(tt.today() - 2, tt.today() + 4, 5, null, :'i_fg'::uuid, 10, null, 'test order 2', gen_random_uuid()) ->> 'id')::bigint as ord2 \gset
select (prod_order_add(tt.today(), tt.today() + 5, 5, 2, :'i_fg'::uuid, 5, null, 'test order 3', gen_random_uuid()) ->> 'id')::bigint as ord3 \gset
select prod_run_link(:'run1'::uuid, :'plan_a'::uuid, :'ord1'::bigint) is not null as w_l1 \gset
select prod_run_link(:'run2'::uuid, null, :'ord2'::bigint) is not null as w_l2 \gset
select prod_actual_issue_set(:'run1'::uuid, jsonb_build_array(jsonb_build_object('item_id', :'i_rm', 'qty', 13), jsonb_build_object('item_id', :'i_sg', 'qty', 6)), 'test real use') is not null as w_a1 \gset
select prod_loss_add(:'run1'::uuid, 'reject', 1, null, 'burnt', 'test reject', gen_random_uuid()) is not null as w_x1 \gset
select prod_loss_add(:'run1'::uuid, 'rework', 0.5, 'kg', 'broken', 'test rework', gen_random_uuid()) is not null as w_x2 \gset
select prod_loss_add(:'run2'::uuid, 'none') is not null as w_x3 \gset
select tt.as(:'o');
