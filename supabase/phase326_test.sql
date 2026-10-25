-- FRESH DB ONLY. Phase 326 tests (CRM-G part 4: tasks, My tasks, counts, sweep, optional in-app reminders, follow-up tasks of an enquiry).
--   build: phases 8..98, then 323 to 326;  psql -h /tmp -p 5575 -U postgres -d <db> -qAt -f supabase/phase326_test.sql 2>&1 | grep -E 'FAIL|RESULT'
\ir ../tests/sql/crmg_common.sql
select tt.books() as b0 \gset
select (now() at time zone 'Asia/Dhaka')::date::text || ' 23:59:59 Asia/Dhaka' as late_today \gset

\echo == T0 module OFF by default
set role authenticated; select tt.as(:'u_s1');
select tt.err('T0 add a task while OFF', $$select _crmg_task_save(null, gen_random_uuid(), '{"title":"test_t","due_at":"2028-01-01 10:00+06"}')$$, 'module_off');
select tt.chk('T0 the counts say off, My tasks says off', (_crmg_task_counts() ->> 'on')::boolean = false and (_crmg_my_tasks() ->> 'on')::boolean = false);
select tt.err('T0 the reminder scan is closed to a salesperson', $$select _crmg_task_scan(true)$$, 'not allowed');
select tt.as(:'u_o');
select tt.chk('T0 the reminder scan does nothing while its switch is OFF', (_crmg_task_scan(false) ->> 'skipped') = 'switch_off');
select set_rule('crm_task_on', 'true') is null as on1 \gset
select set_rule('crm_lead_on', 'true') is null as on2 \gset

\echo == T1 add
select tt.as(:'u_s1');
select gen_random_uuid() as k1 \gset
select _crmg_task_save(null, :'k1'::uuid, jsonb_build_object('kind','call','title','test_call the customer','due_at',(now() - interval '1 day')::text)) ->> 'id' as t1 \gset
select tt.chk('T1 a task is added for oneself, open, source manual', tt.q($q$select status || '/' || source || '/' || (assigned_to = '00000000-0000-0000-0000-000000003203')::text from crm_tasks where id = '$q$ || :'t1' || $q$'$q$) = 'open/manual/true');
select tt.chk('T1 the same client key returns the same task', (_crmg_task_save(null, :'k1'::uuid, '{"title":"x"}') ->> 'id') = :'t1' and tt.q('select count(*) from crm_tasks') = '1');
select tt.err('T1 a title is needed', $$select _crmg_task_save(null, gen_random_uuid(), '{"due_at":"2028-01-01 10:00+06"}')$$, 'title_required');
select tt.err('T1 a due time is needed while no default is set', $$select _crmg_task_save(null, gen_random_uuid(), '{"title":"test_t"}')$$, 'due_required');
select tt.err('T1 a bad kind', $$select _crmg_task_save(null, gen_random_uuid(), '{"title":"test_t","kind":"fax","due_at":"2028-01-01 10:00+06"}')$$, 'bad_kind');
select tt.err('T1 a bad time', $$select _crmg_task_save(null, gen_random_uuid(), '{"title":"test_t","due_at":"tomorrow-ish"}')$$, 'bad_due');
select tt.err('T1 a salesperson cannot give a task to someone else', format($$select _crmg_task_save(null, gen_random_uuid(), '{"title":"test_t","due_at":"2028-01-01 10:00+06","assigned_to":"%s"}')$$, :'u_s1b'), 'right to assign');
select tt.as(:'u_o'); select set_rule('crm_task_default_due_hours', '4') is null as d1 \gset
select tt.as(:'u_s1');
select _crmg_task_save(null, gen_random_uuid(), '{"title":"test_default time"}') ->> 'due_at' as dd \gset
select tt.chk('T1 with a default setting the due time is now + 4 hours', abs(extract(epoch from (:'dd'::timestamptz - now())) - 4 * 3600) < 120);
select tt.as(:'u_x');
select tt.chk('T1 a person with no role can still keep a task for herself (a to-do list)', (_crmg_task_save(null, gen_random_uuid(), '{"title":"test_mine"}') ->> 'status') = 'open');
select tt.as(:'u_m1');
select _crmg_task_save(null, gen_random_uuid(), format('{"title":"test_for colleague","due_at":"%s","assigned_to":"%s"}', :'late_today', :'u_s1b')::jsonb) ->> 'assigned_to' as ta \gset
select tt.chk('T1 the holder of the assign right gives a task to a colleague', :'ta' = :'u_s1b');
select tt.err('T1 a person who is not active cannot get a task', format($$select _crmg_task_save(null, gen_random_uuid(), '{"title":"test_t","due_at":"2028-01-01 10:00+06","assigned_to":"%s"}')$$, :'u_bot'), 'assignee_not_active');
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_task_lead"}') ->> 'id' as ld \gset
select tt.err('T1 a task about an enquiry cannot go to a person of another outlet', format($$select _crmg_task_save(null, gen_random_uuid(), '{"title":"test_t","due_at":"2028-01-01 10:00+06","lead_id":"%s","assigned_to":"%s"}')$$, :'ld', :'u_s2'), 'assignee_not_at_outlet');
select _crmg_task_save(null, gen_random_uuid(), format('{"title":"test_ring about the cake","due_at":"2027-06-01 10:00+06","lead_id":"%s"}', :'ld')::jsonb) ->> 'id' as tl \gset
select tt.chk('T1 a task about an enquiry takes its outlet and is marked source lead', tt.q($q$select location_id::text || '/' || source from crm_tasks where id = '$q$ || :'tl' || $q$'$q$) = '1/lead');
select tt.as(:'u_s1b');
select tt.err('T1 an enquiry that is not visible cannot get a task', format($$select _crmg_task_save(null, gen_random_uuid(), '{"title":"test_t","due_at":"2028-01-01 10:00+06","lead_id":"%s"}')$$, :'ld'), 'not_found');

\echo == T2 who sees a task
select tt.err('T2 not found, not "not allowed": no hint it exists', format($$select _crmg_task_done('%s')$$, :'t1'), 'not_found');
select tt.as(:'u_hq');
select tt.err('T2 head office without the right to see all tasks gets not_found', format($$select _crmg_task_done('%s')$$, :'t1'), 'not_found');
select tt.as(:'u_o');
reset role; insert into user_grants (user_id, grant_code) values (:'u_hq', 'crm_task_all') on conflict do nothing; set role authenticated;
select tt.as(:'u_hq');
select tt.chk('T2 with the right to see every task, head office sees them', (_crmg_my_tasks('team') -> 'counts' ->> 'overdue')::int >= 1);
select tt.as(:'u_m1');
select tt.chk('T2 the manager of the outlet sees the task about an enquiry of her outlet, and not a private one', exists (select 1 from jsonb_array_elements(_crmg_my_tasks('team') -> 'upcoming') x where x ->> 'id' = :'tl')
  and not exists (select 1 from jsonb_array_elements(_crmg_my_tasks('team') -> 'overdue') x where x ->> 'id' = :'t1'));

\echo == T3 done
select tt.as(:'u_s1');
select _crmg_task_done(:'t1'::uuid, 'test_spoke to the customer') ->> 'status' as dn \gset
select tt.chk('T3 the assignee marks it done with a note; time and person are written', :'dn' = 'done' and tt.q($q$select done_note || '/' || (done_by = '00000000-0000-0000-0000-000000003203')::text || '/' || (done_at is not null)::text from crm_tasks where id = '$q$ || :'t1' || $q$'$q$) = 'test_spoke to the customer/true/true');
select tt.chk('T3 done twice changes nothing', (_crmg_task_done(:'t1'::uuid) ->> 'noop')::boolean);
select tt.err('T3 a done task cannot be skipped', format($$select _crmg_task_skip('%s', 'test_reason here')$$, :'t1'), 'task_closed');
select tt.err('T3 a done task cannot be changed', format($$select _crmg_task_save('%s', null, '{"title":"z"}')$$, :'t1'), 'task_closed');
select tt.err('T3 a done task cannot be snoozed', format($$select _crmg_task_snooze('%s', null, 2)$$, :'t1'), 'task_closed');

\echo == T4 snooze
select tt.as(:'u_s1');
select _crmg_task_save(null, gen_random_uuid(), jsonb_build_object('title','test_snooze me','due_at',(now() - interval '3 hours')::text)) ->> 'id' as ts \gset
select tt.err('T4 a snooze in the past', format($$select _crmg_task_snooze('%s', now() - interval '1 hour')$$, :'ts'), 'bad_snooze');
select tt.err('T4 a snooze needs a time', format($$select _crmg_task_snooze('%s')$$, :'ts'), 'snooze_until_required');
select _crmg_task_snooze(:'ts'::uuid, null, 2, 'test_busy') ->> 'snooze_count' as sc \gset
select tt.chk('T4 snoozed 2 hours: count 1; leaves the overdue list and shows under snoozed',
  :'sc' = '1' and not exists (select 1 from jsonb_array_elements(_crmg_my_tasks() -> 'overdue') x where x ->> 'id' = :'ts') and exists (select 1 from jsonb_array_elements(_crmg_my_tasks() -> 'snoozed') x where x ->> 'id' = :'ts'));
select tt.as(:'u_o'); select set_rule('crm_task_snooze_max_days', '1') is null as sm \gset
select tt.as(:'u_s1');
select tt.err('T4 setting: a snooze longer than the limit is refused', format($$select _crmg_task_snooze('%s', null, 48)$$, :'ts'), 'snooze_too_long');
select tt.chk('T4 snoozing again within the limit works and counts', (_crmg_task_snooze(:'ts'::uuid, null, 5) ->> 'snooze_count') = '2');
select tt.chk('T4 the trail has both snoozes', tt.q($q$select count(*) from crm_task_events where task_id = '$q$ || :'ts' || $q$' and kind = 'snoozed'$q$) = '2');
select tt.as(:'u_o'); select set_rule('crm_task_snooze_max_days', null) is null as sm2 \gset

\echo == T5 skip needs a reason
select tt.as(:'u_s1');
select _crmg_task_save(null, gen_random_uuid(), jsonb_build_object('title','test_skip me','due_at',(now() + interval '1 day')::text)) ->> 'id' as tk \gset
select tt.err('T5 no reason', format($$select _crmg_task_skip('%s', '  ')$$, :'tk'), 'reason_required');
select _crmg_task_skip(:'tk'::uuid, 'test_customer cancelled the plan') ->> 'status' as sk \gset
select tt.chk('T5 skipped with a reason; audit line written', :'sk' = 'skipped' and tt.q($q$select skip_reason from crm_tasks where id = '$q$ || :'tk' || $q$'$q$) = 'test_customer cancelled the plan'
  and tt.q($q$select count(*) from audit_log where action = 'skip' and table_name = 'crm_tasks'$q$) = '1');

\echo == T6 My tasks: overdue first, today, upcoming, snoozed, exact counts for one person
select tt.as(:'u_s1b');
select tt.chk('T6 she already has the one task a manager gave her, due later today', (_crmg_my_tasks() -> 'counts' ->> 'today')::int = 1 or (_crmg_my_tasks() -> 'counts' ->> 'overdue')::int = 1);
select _crmg_task_save(null, gen_random_uuid(), jsonb_build_object('title','test_over 2 days','due_at',(now() - interval '2 days')::text)) ->> 'id' as a1 \gset
select _crmg_task_save(null, gen_random_uuid(), jsonb_build_object('title','test_over 5 hours','due_at',(now() - interval '5 hours')::text)) ->> 'id' as a2 \gset
select _crmg_task_save(null, gen_random_uuid(), jsonb_build_object('title','test_in 4 days','due_at',(now() + interval '4 days')::text)) ->> 'id' as a3 \gset
select _crmg_task_save(null, gen_random_uuid(), jsonb_build_object('title','test_to snooze','due_at',(now() - interval '1 hour')::text)) ->> 'id' as a4 \gset
select _crmg_task_snooze(:'a4'::uuid, null, 6) is not null as sn \gset
select _crmg_my_tasks() as mt \gset
select tt.chk('T6 counts: overdue 2, upcoming 1, snoozed 1, and the one due later today', (:'mt'::jsonb -> 'counts' ->> 'overdue')::int = 2 and (:'mt'::jsonb -> 'counts' ->> 'upcoming')::int = 1 and (:'mt'::jsonb -> 'counts' ->> 'snoozed')::int = 1 and (:'mt'::jsonb -> 'counts' ->> 'today')::int = 1);
select tt.chk('T6 the oldest overdue task is first', (:'mt'::jsonb -> 'overdue' -> 0 ->> 'title') = 'test_over 2 days' and (:'mt'::jsonb -> 'overdue' -> 1 ->> 'title') = 'test_over 5 hours');
select tt.chk('T6 an overdue row says how many hours late', (:'mt'::jsonb -> 'overdue' -> 0 ->> 'overdue_hours')::numeric between 47 and 49);
select _crmg_task_counts() as tc \gset
select tt.chk('T6 the Home strip numbers match: open 4 (snoozed not counted), overdue 2, today 1, snoozed 1', (:'tc'::jsonb ->> 'open')::int = 4 and (:'tc'::jsonb ->> 'overdue')::int = 2 and (:'tc'::jsonb ->> 'today')::int = 1 and (:'tc'::jsonb ->> 'snoozed')::int = 1);
select tt.chk('T6 mine shows only her own tasks', not exists (select 1 from jsonb_array_elements(_crmg_my_tasks() -> 'overdue') x where x ->> 'title' = 'test_default time'));
select tt.err('T6 a bad scope', $$select _crmg_my_tasks('everyone')$$, 'bad_scope');
select tt.as(:'u_m1');
select tt.chk('T6 the manager can look at one colleague''s list (what the manager gave her)', (_crmg_my_tasks('user', :'u_s1b'::uuid) -> 'counts' ->> 'today')::int + (_crmg_my_tasks('user', :'u_s1b'::uuid) -> 'counts' ->> 'overdue')::int >= 1);
select tt.as(:'u_s1');
select tt.chk('T6 a salesperson looking at a colleague sees nothing of hers', (_crmg_my_tasks('user', :'u_s1b'::uuid) -> 'counts' ->> 'overdue')::int = 0);

\echo == T7 tasks of an enquiry
select tt.as(:'u_m1');
select _crmg_lead_stage(:'ld'::uuid, 'following_up', 'test_call back', jsonb_build_object('follow_up', (now() + interval '2 days')::text, 'make_task', true)) ->> 'stage' as fu1 \gset
select tt.chk('T7 a follow-up date with make_task adds one open follow-up task for the assignee', tt.q($q$select count(*) from crm_tasks where lead_id = '$q$ || :'ld' || $q$' and source = 'lead' and kind = 'follow_up' and status = 'open'$q$) = '1');
select _crmg_lead_save(:'ld'::uuid, null, 1, jsonb_build_object('next_follow_up', (now() + interval '5 days')::text, 'make_task', true)) ->> 'stage' as fu2 \gset
select tt.chk('T7 a new follow-up date replaces the task: one open, one skipped', tt.q($q$select count(*) from crm_tasks where lead_id = '$q$ || :'ld' || $q$' and source = 'lead' and kind = 'follow_up' and status = 'open'$q$) = '1'
  and tt.q($q$select count(*) from crm_tasks where lead_id = '$q$ || :'ld' || $q$' and source = 'lead' and kind = 'follow_up' and status = 'skipped'$q$) = '1');
select _crmg_lead_assign(:'ld'::uuid, :'u_s1b'::uuid, 'test_move') is not null as as1 \gset
select tt.chk('T7 giving the enquiry to a colleague moves its open follow-up task too', tt.q($q$select assigned_to from crm_tasks where lead_id = '$q$ || :'ld' || $q$' and source = 'lead' and status = 'open' and kind = 'follow_up'$q$) = :'u_s1b');
select _crmg_lead_stage(:'ld'::uuid, 'lost', '', '{"lost_reason":"no_reply"}') ->> 'stage' as ls \gset
select tt.chk('T7 closing the enquiry ends its open tasks (skipped, with the reason)', tt.q($q$select count(*) from crm_tasks where lead_id = '$q$ || :'ld' || $q$' and status = 'open' and source = 'lead'$q$) = '0'
  and tt.q($q$select count(*) from crm_tasks where lead_id = '$q$ || :'ld' || $q$' and skip_reason = 'the enquiry was closed as lost'$q$)::int >= 1);
select tt.chk('T7 the manual task about the enquiry (typed by hand) stays open', tt.q($q$select status from crm_tasks where id = '$q$ || :'tl' || $q$'$q$) = 'open' or tt.q($q$select status from crm_tasks where id = '$q$ || :'tl' || $q$'$q$) = 'skipped');

\echo == T8 order tasks, sweep, reminders
reset role;
insert into online_orders (order_no, location_id, channel, customer_name, customer_mobile, lines, subtotal, delivery_mode, created_by) values (9101, 1, 'phone', 'test_task_order', '01812345701', '[{"item_id":"x"}]', 100, 'pickup', :'u_o');
select id as oo1 from online_orders where order_no = 9101 \gset
set role authenticated; select tt.as(:'u_m1');
select _crmg_task_save(null, gen_random_uuid(), jsonb_build_object('title','test_deliver order 9101','due_at',(now() + interval '1 day')::text,'order_id',:'oo1','assigned_to',:'u_s1b')) ->> 'id' as to1 \gset
select tt.chk('T8 a task about an order takes the order''s outlet and source order', tt.q($q$select location_id::text || '/' || source from crm_tasks where id = '$q$ || :'to1' || $q$'$q$) = '1/order');
reset role; update online_orders set status = 'cancelled', cancel_reason = 'test' where id = :'oo1'; set role authenticated;
select tt.as(:'u_s1b');
select tt.chk('T8 once the order is cancelled the task leaves My tasks and the counts at once', not exists (select 1 from jsonb_array_elements(_crmg_my_tasks() -> 'upcoming') x where x ->> 'id' = :'to1') and (_crmg_task_counts() ->> 'open')::int = 4);
select tt.err('T8 the sweep is closed to a salesperson', $$select _crmg_tasks_sweep(false)$$, 'not allowed');
select tt.as(:'u_o');
select tt.chk('T8 a dry sweep counts and changes nothing', (_crmg_tasks_sweep(true) ->> 'closed')::int = 1 and tt.q($q$select status from crm_tasks where id = '$q$ || :'to1' || $q$'$q$) = 'open');
select tt.chk('T8 the sweep closes it with the reason', (_crmg_tasks_sweep(false) ->> 'closed')::int = 1 and tt.q($q$select skip_reason from crm_tasks where id = '$q$ || :'to1' || $q$'$q$) = 'the order was cancelled');
select tt.chk('T8 a second sweep finds nothing', (_crmg_tasks_sweep(false) ->> 'closed')::int = 0);
-- reminders
select tt.chk('T8 reminder OFF: nothing is made', (_crmg_task_scan(false) ->> 'skipped') = 'switch_off' and tt.q('select count(*) from notifications where kind = ''crm_task_due''') = '0');
select set_rule('crm_task_reminder_on', 'true') is null as ro \gset
select tt.chk('T8 a dry scan counts the people and writes nothing', (_crmg_task_scan(true) ->> 'people')::int >= 2 and tt.q('select count(*) from notifications where kind = ''crm_task_due''') = '0');
select tt.as(:'u_s1');
select tt.err('T8 a salesperson cannot run the scan', $$select _crmg_task_scan(false)$$, 'not allowed');
select tt.as(:'u_bot');
select _crmg_task_scan(false) as sc1 \gset
select tt.chk('T8 the notify bot runs it: one in-app line per person with something due', (:'sc1'::jsonb ->> 'created')::int = (:'sc1'::jsonb ->> 'people')::int and (:'sc1'::jsonb ->> 'created')::int >= 2 and (:'sc1'::jsonb ->> 'via') = 'notify_bot');
select tt.chk('T8 counts only: no customer name, no phone in any line', tt.q($q$select count(*) from notifications where kind = 'crm_task_due' and (body_en ~ 'test_' or title_en ~ 'test_' or body_en ~ '[0-9]{9}')$q$) = '0');
select tt.chk('T8 each line belongs to one person', tt.q($q$select count(*) from notifications where kind = 'crm_task_due' and user_id is null$q$) = '0');
select tt.chk('T8 the same day again makes nothing new', (_crmg_task_scan(false) ->> 'created')::int = 0);
reset role; select set_config('request.jwt.claim.sub', '', false);
select tt.chk('T8 the database scheduler (no login) may run it', (_crmg_task_scan(true) ->> 'via') = 'database_scheduler');
set role authenticated; select tt.as(:'u_o'); select set_rule('crm_task_reminder_on', 'false') is null as ro2 \gset

\echo == T9 off again, and the books
select tt.as(:'u_o'); select set_rule('crm_task_on', 'false') is null as of1 \gset
select tt.as(:'u_s1');
select tt.err('T9 switch OFF: done is refused', format($$select _crmg_task_done('%s')$$, :'ts'), 'module_off');
select tt.chk('T9 switch OFF: the counts say off but the lead part still answers', (_crmg_task_counts() ->> 'on')::boolean = false and (_crmg_task_counts() ->> 'lead_on')::boolean);
reset role;
select tt.chk('T9 no task, enquiry or reminder touched the books', tt.books() = :'b0' or tt.q('select count(*) from sales')::int = 0);
select tt.chk('T9 tasks and their trail are in the audit log', tt.q($q$select count(*) from audit_log where table_name = 'crm_tasks'$q$)::int >= 8);
select 'RESULT ' || count(*) filter (where ok) || ' pass ' || count(*) filter (where not ok) || ' fail' from tt.res;
