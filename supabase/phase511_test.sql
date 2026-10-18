-- FRESH DB ONLY. Phase 511 tests (X4 AI knowledge, suggestions, feedback, evaluation). Run on a database through phase 511.
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase511_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). No external call.
\set ON_ERROR_STOP off
\i tests/sql/rpthub_tt.sql
\set u_o '00000000-0000-0000-0000-000000000510'
\set u_o2 '00000000-0000-0000-0000-000000000513'
\set u_st '00000000-0000-0000-0000-000000000511'
\set u_no '00000000-0000-0000-0000-000000000512'
insert into auth.users (id, email, raw_user_meta_data) values
 (:'u_o', 'test_owner511@example.test', '{}'), (:'u_st', 'test_staff511@example.test', '{}'), (:'u_no', 'test_nogrant511@example.test', '{}'), (:'u_o2', 'test_owner2_511@example.test', '{}')
 on conflict do nothing;
update public.profiles set status = 'active' where id in (:'u_st', :'u_no', :'u_o2');
insert into public.user_grants (user_id, grant_code) values (:'u_st', 'assistant_use') on conflict do nothing;
insert into public.user_roles (user_id, role_code) values (:'u_o2', 'owner') on conflict do nothing;
select tt.as(:'u_o');
select public.set_rule('ai_on', 'true'::jsonb);
select public.ai_agent_save('erp_guide', true, 'local_rules', 'none', '{assistant_me}', '{setup.draft_checklist}', false, null, 'owner', 'v1') is not null as e1 \gset
select public.ai_agent_save('enquiry_classifier', true, 'local_rules', 'none', '{}', '{}', true, null, 'approver', 'v1') is not null as e2 \gset

\echo == K1 knowledge: propose, verify, publish; self-verify refused; verified is locked
select public.ai_kb_propose('test.sales_rule', 'Sample rule v1', 'Sales are counted when the bill is paid at the till.', 'test source', '1', 'owner') is not null as k1 \gset
select tt.as(:'u_o');
select tt.err('K1 the proposer cannot verify their own text', $q$select public.ai_kb_verify((select id from public.ai_kb_entries where key = 'test.sales_rule' and version = 1))$q$, 'self_verify');
select tt.as(:'u_o2');
select public.ai_kb_verify((select id from public.ai_kb_entries where key = 'test.sales_rule' and version = 1)) is not null as k2 \gset
select tt.chk('K1 a second owner verifies it', (select status = 'verified' from public.ai_kb_entries where key = 'test.sales_rule' and version = 1));
select tt.err('K1 a verified text cannot be edited in place', $q$update public.ai_kb_entries set body = 'changed text here for test' where key = 'test.sales_rule' and version = 1$q$, 'verified_is_locked');
select tt.as(:'u_o');
select public.ai_kb_propose('test.sales_rule', 'Sample rule v2', 'Sales are counted when the bill is paid at the till, and returns are netted.', 'test source', '2', 'owner') is not null as k3 \gset
select tt.as(:'u_o2');
select public.ai_kb_verify((select id from public.ai_kb_entries where key = 'test.sales_rule' and version = 2)) is not null as k4 \gset
select tt.chk('K1 publishing v2 retires v1 (one verified text per key)', (select count(*) from public.ai_kb_entries where key = 'test.sales_rule' and status = 'verified') = 1
   and (select status from public.ai_kb_entries where key = 'test.sales_rule' and version = 1) = 'retired');
select tt.chk('K1 retired v1 is still in the table (history kept)', (select count(*) from public.ai_kb_entries where key = 'test.sales_rule') = 2);
select tt.as(:'u_st');
set role authenticated;
select tt.chk('K1 a staff member sees the verified text only', (select count(*) from jsonb_array_elements(public.ai_kb_list('verified'))) = 1);
select tt.chk('K1 a staff member does not see proposals (no unverified text)', (select count(*) from jsonb_array_elements(public.ai_kb_list('proposed'))) = 0);
select tt.err('K1 a proposal with a key-like string is refused', $q$select public.ai_kb_propose('test.bad', 'Bad', 'token sk-abcdefghijklmnopqrstu1234 in text', 'x', '1', 'owner')$q$, 'not allowed');
reset role;
select tt.as(:'u_o');
select tt.err('K1 a proposal with a key-like string is refused', $q$select public.ai_kb_propose('test.bad2', 'Bad', 'token sk-abcdefghijklmnopqrstu1234 in text', 'x', '1', 'owner')$q$, 'looks_like_secret');

\echo == K2 suggestions: untrusted rule, allowed actions, self-decision refused, outcome by owner
select tt.as(:'u_st');
set role authenticated;
select public.ai_suggestion_add('erp_guide', 'proposal', 'Add a checklist for missing setup', '[]', 'setup.draft_checklist', 'v1', 'r1', 'none', gen_random_uuid()) is not null as s1 \gset
select tt.chk('K2 the proposal is stored as a suggestion, not executed', (select status = 'new' and authoritative = false from public.ai_suggestions where proposal_action = 'setup.draft_checklist' order by created_at desc limit 1));
select tt.err('K2 a proposal action outside the agent list is refused', $q$select public.ai_suggestion_add('erp_guide', 'proposal', 'Pay a supplier now', '[]', 'pay.supplier', 'v1', 'r1', 'none', null)$q$, 'action_not_allowed');
select tt.err('K2 an untrusted-input agent cannot make a proposal', $q$select public.ai_suggestion_add('enquiry_classifier', 'proposal', 'Reply to customer', '[]', 'content.draft', 'v1', 'r1', 'none', null)$q$, 'untrusted_input_no_proposals');
select tt.err('K2 a proposal without an agent is refused', $q$select public.ai_suggestion_add(null, 'proposal', 'No agent', '[]', 'setup.draft_checklist', 'v1', 'r1', 'none', null)$q$, 'proposal_needs_agent');
select tt.err('K2 a disabled agent cannot add a suggestion', $q$select public.ai_suggestion_add('sales_analyst', 'insight', 'Sales are up', '[]', null, 'v1', 'r1', 'none', null)$q$, 'agent_off');
select public.ai_suggestion_add(null, 'insight', 'Plain staff note', '[]', null, null, null, null, null) is not null as s2 \gset
select gen_random_uuid() as cid \gset
select public.ai_suggestion_add(null, 'insight', 'Dup test one', '[]', null, null, null, null, :'cid') is not null as d0 \gset
select tt.chk('K2 a repeated client id returns the first row (dup = true, one row only)', (public.ai_suggestion_add(null, 'insight', 'Dup test two', '[]', null, null, null, null, :'cid')->>'dup')::boolean and (select count(*) = 1 from public.ai_suggestions where client_id = :'cid'));
select tt.err('K2 the person who asked cannot decide their own suggestion', $q$select public.ai_suggestion_decide((select id from public.ai_suggestions where summary = 'Plain staff note'), 'accepted', null)$q$, 'self_decision');
select tt.err('K2 a direct insert into the suggestions table is refused', $q$insert into public.ai_suggestions (kind, summary, authoritative) values ('insight', 'direct', false)$q$, 'permission denied');
reset role;
select tt.as(:'u_o2');
set role authenticated;
select public.ai_suggestion_decide((select id from public.ai_suggestions where summary = 'Plain staff note'), 'corrected', 'Use the approved wording') is not null as d1 \gset
select tt.chk('K2 a second person corrects it (the correction is stored)', (select status = 'corrected' and correction = 'Use the approved wording' from public.ai_suggestions where summary = 'Plain staff note'));
select tt.err('K2 a decided suggestion cannot be decided again', $q$select public.ai_suggestion_decide((select id from public.ai_suggestions where summary = 'Plain staff note'), 'rejected', null)$q$, 'already_decided');
select tt.err('K2 a correction needs the text', $q$select public.ai_suggestion_decide((select id from public.ai_suggestions where kind = 'proposal' limit 1), 'corrected', null)$q$, 'correction_required');
reset role;
select tt.as(:'u_o');
set role authenticated;
select public.ai_suggestion_outcome((select id from public.ai_suggestions where summary = 'Plain staff note'), 'good', 'checked a week later') is not null as o1 \gset
select tt.chk('K2 the owner records the outcome later', (select outcome = 'good' from public.ai_suggestions where summary = 'Plain staff note'));
reset role;
select tt.as(:'u_st');
set role authenticated;
select tt.err('K2 staff cannot record an outcome', $q$select public.ai_suggestion_outcome((select id from public.ai_suggestions where summary = 'Plain staff note'), 'bad', null)$q$, 'not allowed');
reset role;

\echo == K3 pause stops suggestions; the flag is on the row
select tt.as(:'u_o');
select public.ai_pause_all(true) is not null as p1 \gset
select tt.as(:'u_st');
set role authenticated;
select tt.err('K3 while paused a suggestion is refused', $q$select public.ai_suggestion_add(null, 'insight', 'While paused', '[]', null, null, null, null, null)$q$, 'ai_off');
reset role;
select tt.as(:'u_o');
select public.ai_pause_all(false) is not null as p2 \gset

\echo == K4 evaluation and dashboards
select tt.as(:'u_o');
select tt.chk('K4 six golden questions are seeded and active', (select count(*) = 6 from public.ai_eval_cases where active));
select tt.chk('K4 the injection cases expect no tool', (select count(*) = 2 from public.ai_eval_cases where code like 'injection_%' and expect_tool is null));
select public.ai_eval_record('local_rules', 'local', 6, 5, '[{"code":"stock_low_q","ok":false}]') is not null as v1 \gset
select tt.err('K4 an eval run with a wrong count is refused', $q$select public.ai_eval_record('local_rules', 'local', 6, 7, '[]')$q$, 'check');
select tt.chk('K4 the scorecard lists the agents and the humans', (select count(*) >= 2 from jsonb_array_elements(public.ai_scorecard(30))));
select tt.chk('K4 the usage summary lists the providers', (select count(*) = 5 from jsonb_array_elements(public.ai_usage_summary(null))));
reset role;
select tt.as(:'u_st');
set role authenticated;
select tt.chk('K4 staff get no scorecard', (select count(*) = 0 from jsonb_array_elements(public.ai_scorecard(30))));
reset role;

\echo == K5 anon
select tt.chk('K5 anon cannot add a suggestion', not has_function_privilege('anon', 'public.ai_suggestion_add(text,text,text,jsonb,text,text,text,text,uuid)', 'execute'));
select tt.chk('K5 anon cannot read the suggestions table', not has_table_privilege('anon', 'public.ai_suggestions', 'select'));
select tt.chk('K5 anon cannot read the knowledge table', not has_table_privilege('anon', 'public.ai_kb_entries', 'select'));
select tt.chk('K5 anon cannot read the evaluation runs', not has_table_privilege('anon', 'public.ai_eval_runs', 'select'));

\echo == K6 paste twice (this file runs on a database where phase511 was pasted twice)
select tt.chk('K6 the verified knowledge still has one current text per key', (select count(*) = 1 from public.ai_kb_entries where key = 'test.sales_rule' and status = 'verified'));
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
