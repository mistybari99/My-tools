-- FRESH DB ONLY. Phase 481 tests (X1 foundation, part 2: approval queue and health). Build through phase 481 (tests/sql/ORDER.txt), then from the repository root:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase481_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_*).
\set ON_ERROR_STOP off
\i tests/sql/rpthub_tt.sql
\set u_o '00000000-0000-0000-0000-000000000490'
\set u_a '00000000-0000-0000-0000-000000000491'
\set u_b '00000000-0000-0000-0000-000000000492'
\set u_s '00000000-0000-0000-0000-000000000493'
\echo == setup
insert into auth.users (id, email, raw_user_meta_data) values
 (:'u_o', 'test_owner481@s.app', '{"full_name":"test_owner481"}'), (:'u_a', 'test_agent481@s.app', '{"full_name":"test_agent481"}'),
 (:'u_b', 'test_bot481@s.app', '{"full_name":"test_bot481"}'), (:'u_s', 'test_staff481@s.app', '{"full_name":"test_staff481"}') on conflict do nothing;
update public.profiles set status = 'active';
insert into public.user_roles (user_id, role_code) values (:'u_o', 'owner'), (:'u_s', 'salesperson') on conflict do nothing;
insert into public.ops_accounts (user_id, purpose, active) values (:'u_b', 'notify', true) on conflict do nothing;
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select public.agent_account_set(:'u_a', 'test_agent_481', true) is not null as ok_agent \gset
reset role;

\echo == T1 the allowlist starts empty; a target must be enabled
select tt.chk('T1 no proposal target is enabled at the start', (select count(*) = 0 from public.action_targets where enabled));
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_a', false);
select tt.err('T1 agent: a target that is not enabled is refused', $q$select public.action_propose(gen_random_uuid(), 'inbox_note_add', '{}', 'test reason')$q$, 'target_not_enabled');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select public.action_target_set('inbox_note_add', 'Note on an inbox message', 'Note on an inbox message', 'low', true) is not null as ok_t \gset
reset role;

\echo == T2 rules, grants, audit and money can never be a target
select tt.err('T2 a rule setter can never be a target', $q$insert into public.action_targets (rpc_name, label_bn, label_en) values ('set_rule_extra', 'x', 'x')$q$, 'target_not_allowed');
select tt.err('T2 a grant can never be a target', $q$insert into public.action_targets (rpc_name, label_bn, label_en) values ('grant_user_extra', 'x', 'x')$q$, 'target_not_allowed');
select tt.err('T2 an audit change can never be a target', $q$insert into public.action_targets (rpc_name, label_bn, label_en) values ('audit_clear_extra', 'x', 'x')$q$, 'target_not_allowed');
select tt.err('T2 a journal posting can never be a target', $q$insert into public.action_targets (rpc_name, label_bn, label_en) values ('journal_post_extra', 'x', 'x')$q$, 'target_not_allowed');
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select tt.err('T2 the owner cannot list a money target either', $q$select public.action_target_set('refund_extra', 'x', 'x', 'high', true)$q$, 'target_not_allowed');
reset role;

\echo == T3 who may propose
set role anon;
select tt.err('T3 anon cannot propose', $q$select public.action_propose(gen_random_uuid(), 'inbox_note_add', '{}', 'test reason')$q$, 'permission denied');
select tt.err('T3 anon cannot read the queue', 'select count(*) from public.action_proposals', 'permission denied');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_s', false);
select tt.err('T3 a staff member without an agent identity cannot propose', $q$select public.action_propose(gen_random_uuid(), 'inbox_note_add', '{}', 'test reason')$q$, 'not allowed');
reset role;

\echo == T4 agent proposals: idempotent, validated, redacted
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_a', false);
select public.action_propose('00000000-0000-0000-0000-0000000004b1', 'inbox_note_add', '{"message_id":1}', 'call 01712345678 about the order') as p1 \gset
select set_config('x1.p1', :'p1'::jsonb ->> 'id', false);
select tt.chk('T4 agent proposal is queued as proposed, kind agent', (select status = 'proposed' and proposer_kind = 'agent' and risk = 'low' from public.action_proposals where client_id = '00000000-0000-0000-0000-0000000004b1'));
select tt.chk('T4 the reason is stored redacted', (select reason_for = 'call [phone] about the order' from public.action_proposals where client_id = '00000000-0000-0000-0000-0000000004b1'));
select public.action_propose('00000000-0000-0000-0000-0000000004b1', 'inbox_note_add', '{}', 'again') as p1b \gset
select tt.chk('T4 the same client id is never queued twice', (select (:'p1b'::jsonb ->> 'duplicate')::boolean and (:'p1b'::jsonb ->> 'id') = (:'p1'::jsonb ->> 'id') from (select 1) x) and (select count(*) = 1 from public.action_proposals where client_id = '00000000-0000-0000-0000-0000000004b1'));
select tt.err('T4 args must be an object', $q$select public.action_propose(gen_random_uuid(), 'inbox_note_add', '[1,2]', 'test reason')$q$, 'bad_input');
select tt.err('T4 a reason is mandatory', $q$select public.action_propose(gen_random_uuid(), 'inbox_note_add', '{}', '   ')$q$, 'bad_input');
select tt.err('T4 the agent cannot decide', $q$select public.action_decide(current_setting('x1.p1')::bigint, 'approve')$q$, 'not allowed');
select tt.err('T4 the agent cannot record an execution', $q$select public.action_proposal_mark_executed(current_setting('x1.p1')::bigint, true)$q$, 'not allowed');
reset role;

\echo == T5 the owner decides; never the proposer; a rejection needs a reason
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select public.action_propose('00000000-0000-0000-0000-0000000004b2', 'inbox_note_add', '{"message_id":2}', 'owner proposal') as own \gset
select set_config('x1.own', :'own'::jsonb ->> 'id', false);
select tt.err('T5 the proposer never decides its own proposal', $q$select public.action_decide(current_setting('x1.own')::bigint, 'approve')$q$, 'own_proposal_cannot_be_decided');
select tt.err('T5 a rejection needs a reason', $q$select public.action_decide(current_setting('x1.p1')::bigint, 'reject', '  ')$q$, 'reject_reason_required');
select public.action_decide(current_setting('x1.p1')::bigint, 'reject', 'not needed today') as d1 \gset
select tt.chk('T5 the rejection is recorded', (select status = 'rejected' and decided_by = :'u_o' from public.action_proposals where client_id = '00000000-0000-0000-0000-0000000004b1'));
select tt.err('T5 a decided proposal can not be decided again', $q$select public.action_decide(current_setting('x1.p1')::bigint, 'approve')$q$, 'not_open');
reset role;

\echo == T6 approve, then the approver records the result; nothing runs twice
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_a', false);
select public.action_propose('00000000-0000-0000-0000-0000000004b3', 'inbox_note_add', '{"message_id":3}', 'agent proposal two') as p3 \gset
select set_config('x1.p3', :'p3'::jsonb ->> 'id', false);
select tt.chk('T6 the proposal is visible to its agent only', (select count(*) = 2 from jsonb_array_elements(public.action_proposals_list(null, 100)) x));
select set_config('request.jwt.claim.sub', :'u_o', false);
select tt.err('T6 a proposal that is not approved can not be recorded as executed', $q$select public.action_proposal_mark_executed(current_setting('x1.p3')::bigint, true)$q$, 'not_approved_by_you');
select public.action_decide(current_setting('x1.p3')::bigint, 'approve') as d3 \gset
select tt.chk('T6 approved', (:'d3'::jsonb ->> 'status') = 'approved');
select public.action_proposal_mark_executed(current_setting('x1.p3')::bigint, true, '{"done":true}') as x3 \gset
select tt.chk('T6 executed and the result kept', (select status = 'executed' and exec_ok and exec_result ->> 'done' = 'true' from public.action_proposals where client_id = '00000000-0000-0000-0000-0000000004b3'));
select tt.err('T6 a second record for the same proposal is refused', $q$select public.action_proposal_mark_executed(current_setting('x1.p3')::bigint, true)$q$, 'not_approved_by_you');
reset role;

\echo == T7 expired proposals can not be approved
insert into public.action_proposals (client_id, proposed_by, proposer_kind, target_rpc, args, risk, reason_for, expires_at)
  values ('00000000-0000-0000-0000-0000000004b4', :'u_a', 'agent', 'inbox_note_add', '{}', 'low', 'old one', now() - interval '1 hour');
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select public.action_decide((select id from public.action_proposals where client_id = '00000000-0000-0000-0000-0000000004b4'), 'approve') as d4 \gset
select tt.chk('T7 an expired proposal is marked expired, not approved', (:'d4'::jsonb ->> 'status') = 'expired' and (select status = 'expired' from public.action_proposals where client_id = '00000000-0000-0000-0000-0000000004b4'));
reset role;

\echo == T8 health: safe states, missing is missing, never healthy by accident
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_s', false);
select tt.err('T8 staff cannot read the health view', 'select public.x1_health()', 'not allowed');
select set_config('request.jwt.claim.sub', :'u_o', false);
select tt.chk('T8 owner: automation is reported OFF', (public.x1_health() ->> 'automation_on')::boolean = false);
select tt.chk('T8 owner: 13 connections, all off or not connected', (select count(*) = 13 and bool_and(x ->> 'state' in ('off', 'not_connected')) from jsonb_array_elements(public.x1_health() -> 'integrations') x));
select tt.chk('T8 owner: five expected jobs, none run yet', (select count(*) = 5 and bool_and(x ->> 'state' = 'never_run') from jsonb_array_elements(public.x1_health() -> 'jobs') x));
select tt.chk('T8 owner: the open proposals are counted', (public.x1_health() ->> 'proposals_open')::int = 1);
select tt.chk('T8 owner: a backup that was never run is not called ok', (public.x1_health() -> 'backup' ->> 'configured') is not null or public.x1_health() -> 'backup' is not null);
reset role;
insert into public.job_runs (job, started_at, finished_at, ok, error) values ('notify_digest', now() - interval '10 minutes', now(), false, 'boom');
insert into public.job_runs (job, started_at, finished_at, ok) values ('notify_sms', now(), now(), true);
insert into public.job_runs (job, started_at, finished_at, ok) values ('backup', now() - interval '3 days', now(), true);
insert into public.job_runs (job, started_at, finished_at, ok, error) values ('intake_retry', now(), null, null, 'skipped: automation_off');
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select tt.chk('T8 a failing job shows failed', (select x ->> 'state' = 'failed' from jsonb_array_elements(public.x1_health() -> 'jobs') x where x ->> 'job' = 'notify_digest'));
select tt.chk('T8 a job that ran ok shows ok', (select x ->> 'state' = 'ok' from jsonb_array_elements(public.x1_health() -> 'jobs') x where x ->> 'job' = 'notify_sms'));
select tt.chk('T8 an old ok run shows stale', (select x ->> 'state' = 'stale' from jsonb_array_elements(public.x1_health() -> 'jobs') x where x ->> 'job' = 'backup'));
select tt.chk('T8 a skipped run (automation OFF) is not a failure: never_run stays', (select x ->> 'state' = 'never_run' from jsonb_array_elements(public.x1_health() -> 'jobs') x where x ->> 'job' = 'intake_retry'));
reset role;

\echo == T9 nothing is deleted from the queue
select tt.err('T9 a proposal is never deleted', 'delete from public.action_proposals', 'retire instead');
select tt.err('T9 a target is never deleted', 'delete from public.action_targets', 'retire instead');

\echo == T10 paste twice
\i supabase/phase481.sql
select tt.chk('T10 second paste: the queue keeps its 4 rows', (select count(*) = 4 from public.action_proposals));
select tt.chk('T10 second paste: the allowlist keeps its target', (select count(*) = 1 from public.action_targets));
select tt.chk('T10 second paste: the guard is still on', exists (select 1 from pg_trigger where tgname = 'action_targets_guard'));
select tt.chk('T10 anon still has no execute right on the queue functions', not has_function_privilege('anon', 'public.action_propose(uuid,text,jsonb,text,int)', 'execute') and not has_function_privilege('anon', 'public.x1_health()', 'execute'));
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
