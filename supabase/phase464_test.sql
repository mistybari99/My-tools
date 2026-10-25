-- FRESH DB ONLY. Phase 464 tests (RPT-C3 R8 part 3): #175 price-override approver captured and reported, #176 voids / refunds / unusual list, #177 per-user activity.
--   bash tests/sql/rptc3_run.sh 464
-- Test data only (test_* names).
\ir ../tests/sql/rptc3_head.sql
select to_char(tt.today() - 5, 'YYYY-MM-DD') as f, to_char(tt.today() + 1, 'YYYY-MM-DD') as t \gset
select id as fg from items where code = 'W1D-FG' \gset
select staff_id as o_staff from profiles where id = :'u_o'::uuid \gset
select staff_id as st_staff from profiles where id = :'u_st'::uuid \gset
select tt.as(:'u_o');
insert into user_grants (user_id, grant_code, location_id) values (:'u_ex', 'report_control', null) on conflict do nothing;

-- T1 capture of the price-override approver
select tt.chk('T1 the switch pos_override_manager is ON by default (today), so an approver is required', rule_on('pos_override_manager'));
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":90,"override":true}]',:'fg')::jsonb,0,'[{"mode":"cash","amount":180}]',null,null,'retail',null,false)->>'id' as ov1 \gset
select tt.chk('T1 the owner sells at 90 instead of 100: stored as approval "grant" with his staff id', (select approval = 'grant' and approver_staff = :'o_staff' and override_lines = 1 from sale_price_overrides where sale_id = :'ov1'::uuid));
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'fg')::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)->>'id' as nov \gset
select tt.chk('T1 a bill with no price change gets no row', not exists (select 1 from sale_price_overrides where sale_id = :'nov'::uuid));
select tt.as(:'u_st');
select tt.err('T1 a cashier without the right cannot change a price (unchanged behaviour)', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":80,"override":true}]'::jsonb,0,'[{"mode":"cash","amount":80}]',null,null,'retail',null,false)$$, :'fg'), 'override_needs_approval');
select request_emergency('price_override', 1, '{}'::jsonb, 'test emergency price change') is not null as rq \gset
select tt.as(:'u_o');
select id as em from emergency_requests where grant_code = 'price_override' and status = 'pending' order by id desc limit 1 \gset
select decide_emergency(:'em'::bigint, true, 'ok for the test') is not null as dc \gset
select tt.as(:'u_st');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":80,"override":true}]',:'fg')::jsonb,0,'[{"mode":"cash","amount":80}]',null,null,'retail',null,false)->>'id' as ov2 \gset
select tt.as(:'u_o');
select tt.chk('T1 with a one-off emergency approval the decider is stored: approval "emergency" with the owner as approver', (select approval = 'emergency' and approver_staff = :'o_staff' from sale_price_overrides where sale_id = :'ov2'::uuid));
select set_rule('pos_override_manager', 'false') is null as r0 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":70,"override":true}]',:'fg')::jsonb,0,'[{"mode":"cash","amount":70}]',null,null,'retail',null,false)->>'id' as ov3 \gset
select tt.chk('T1 with the switch OFF the row says "not_required" - no approver was asked for', (select approval = 'not_required' and approver_by is null from sale_price_overrides where sale_id = :'ov3'::uuid));
select set_rule('pos_override_manager', null) is null as r1 \gset
-- an older bill (made before the capture existed): no row at all
alter table sales disable trigger sales_c3_override_capture;
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":60,"override":true}]',:'fg')::jsonb,0,'[{"mode":"cash","amount":60}]',null,null,'retail',null,false)->>'id' as ov4 \gset
alter table sales enable trigger sales_c3_override_capture;
select tt.chk('T1 the capture row can be neither changed nor deleted', true);
select tt.err('T1 a capture row is a record', $$update sale_price_overrides set approval = 'grant'$$, 'append_only');
select tt.err('T1 nor deleted', $$delete from sale_price_overrides$$, 'append_only');

-- T2 the discount and override report (#175)
select aud_overrides(:'f'::date, :'t'::date) as ao \gset
select tt.chk('T2 the discount bill of the fixture (20 off) is listed with its approval state', exists (select 1 from jsonb_array_elements((:'ao'::jsonb)->'rows') x where tt.n(x,'discount') = 20));
select tt.chk('T2 override bills: grant / emergency / not_required / not_captured each appear', (select string_agg(distinct x->>'override_approval', ',' order by x->>'override_approval') from jsonb_array_elements((:'ao'::jsonb)->'rows') x where x->>'override_approval' is not null) = 'emergency,grant,not_captured,not_required');
select tt.chk('T2 the older bill says "not captured" and has no approver (never guessed)', (select x->>'override_approver' is null from jsonb_array_elements((:'ao'::jsonb)->'rows') x where x->>'override_approval' = 'not_captured'));
select tt.chk('T2 coverage: 4 bills with a price change, 3 captured = 75.0%', tt.n((:'ao'::jsonb)->'coverage','override_bills') = 4 and tt.n((:'ao'::jsonb)->'coverage','override_captured') = 3 and tt.n((:'ao'::jsonb)->'coverage','override_captured_pct') = 75.0);
select tt.chk('T2 by approver: the owner approved 2 price changes (grant + emergency)', (select tt.n(x,'bills') = 2 from jsonb_array_elements((:'ao'::jsonb)->'by_approver') x where x->>'kind' = 'price_override' and x->>'approver' = :'o_staff'));
select tt.chk('T2 the report says when the capture started and what the switches are', (:'ao'::jsonb)->>'capture_started' = tt.today()::text and ((:'ao'::jsonb)->'settings'->>'pos_override_manager') = 'true');
select tt.chk('T2 a bill with no discount and no price change is not listed', not exists (select 1 from jsonb_array_elements((:'ao'::jsonb)->'rows') x where x->>'sale_id' = :'nov'));

-- T3 unusual transactions (#176)
select void_sale(:'nov'::uuid, 'test void for unusual') is not null as vv \gset
select sale_return(gen_random_uuid(), tt.k('s4')::uuid, format('[{"item_id":"%s","qty":1}]', :'fg')::jsonb, 'damaged', null, 'cash', null, null) ->> 'id' as ret \gset
select sale_return(gen_random_uuid(), tt.k('s2')::uuid, format('[{"item_id":"%s","qty":1}]', :'fg')::jsonb, 'damaged', null, 'cash', null, null) ->> 'id' as ret2 \gset
select void_sale_return(:'ret2'::uuid, 'test void return') is not null as vr \gset
select aud_unusual(:'f'::date, :'t'::date) as au \gset
select tt.chk('T3 every kind is present: bill void, payment void, return, refund paid, voided return, exception', (select string_agg(x->>'type', ',' order by x->>'type') from jsonb_array_elements((:'au'::jsonb)->'by_type') x) like '%exception%payment_void%refund_paid%return%return_void%sale_void%');
select tt.chk('T3 the voided bill carries who and why', (select x->>'reason' = 'test void for unusual' and x->>'who' is not null and tt.n(x,'amount') = 100 from jsonb_array_elements((:'au'::jsonb)->'rows') x where x->>'type' = 'sale_void' and x->>'reason' = 'test void for unusual'));
select tt.chk('T3 the refund paid on the return is its own row (cash 100)', (select tt.n(x,'amount') = 100 and x->>'flag' = 'cash' from jsonb_array_elements((:'au'::jsonb)->'rows') x where x->>'type' = 'refund_paid' limit 1));
select tt.chk('T3 price-change exceptions raised on bills are included with their flag code', exists (select 1 from jsonb_array_elements((:'au'::jsonb)->'rows') x where x->>'type' = 'exception' and x->>'flag' in ('price_override', 'price_changed')));
select tt.chk('T3 the type filter works', (select bool_and(x->>'type' = 'return_void') from jsonb_array_elements(aud_unusual(:'f'::date, :'t'::date, null, 'return_void')->'rows') x));
select tt.chk('T3 no invented threshold: the note says events of known kinds', (:'au'::jsonb)->'notes' ? 'events_of_known_kinds_not_a_threshold');

-- T4 per-user activity (#177)
insert into login_attempts (staff_id, at, ok) values (:'st_staff', now(), true), (:'st_staff', now(), true), (:'st_staff', now(), false);
select aud_user_activity(:'f'::date, :'t'::date) as ua \gset
select tt.chk('T4 the owner sees the cashier: bills made, logins 2 ok / 1 failed', (select tt.n(x,'bills_made') >= 1 and tt.n(x,'logins_ok') = 2 and tt.n(x,'logins_failed') = 1 from jsonb_array_elements((:'ua'::jsonb)->'rows') x where x->>'staff_id' = :'st_staff'));
select tt.chk('T4 the owner has audit actions and the voids he made counted', (select tt.n(x,'audit_actions') > 0 and tt.n(x,'bills_voided_by_him') >= 1 from jsonb_array_elements((:'ua'::jsonb)->'rows') x where x->>'staff_id' = :'o_staff'));
select aud_user_activity(:'f'::date, :'t'::date, :'st_staff') as ua2 \gset
select tt.chk('T4 one person: a timeline and the login list come with it (owner only)', jsonb_array_length((:'ua2'::jsonb)->'timeline') >= 1 and jsonb_array_length((:'ua2'::jsonb)->'logins') = 3 and jsonb_array_length((:'ua2'::jsonb)->'rows') = 1);
select tt.as(:'u_ex');
select aud_user_activity(:'f'::date, :'t'::date) as ua3 \gset
select tt.chk('T4 a control reader who is not the owner gets business columns only; login and audit columns are null and the note says why', (select x->>'logins_ok' is null and x->>'audit_actions' is null and tt.n(x,'bills_made') >= 1 from jsonb_array_elements((:'ua3'::jsonb)->'rows') x where x->>'staff_id' = :'st_staff') and (:'ua3'::jsonb)->'notes' ? 'login_and_audit_columns_owner_only' and (:'ua3'::jsonb)->'timeline' is not distinct from 'null'::jsonb);
select tt.as(:'u_nb');
select tt.err('T5 nobody: overrides', format($$select aud_overrides('%s','%s')$$, :'f', :'t'), 'not allowed');
select tt.err('T5 nobody: unusual', format($$select aud_unusual('%s','%s')$$, :'f', :'t'), 'not allowed');
select tt.err('T5 nobody: user activity', format($$select aud_user_activity('%s','%s')$$, :'f', :'t'), 'not allowed');
select tt.as(:'u_o');
\i supabase/phase464.sql
select tt.chk('T6 paste twice keeps the captured rows and the single trigger', (select count(*) from sale_price_overrides) = 3 and (select count(*) from pg_trigger where tgname = 'sales_c3_override_capture') = 1);
select tt.chk('T6 the books stay balanced and nothing was posted by the reports', tt.unbalanced() = 0);
\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
