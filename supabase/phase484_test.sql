-- FRESH DB ONLY. Phase 484 tests (X4 AI foundation): defaults, anon denied, forbidden grants and actions, untrusted-input rule, budget enforcement,
-- data-level rule, pause switch, agent provider match, append-only call log, actor_type, money estimate from owner prices only.
--   build a database through phase 484 (ORDER.txt), then from the repository root
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase484_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). No external call. No data outside the test database is touched.
\set ON_ERROR_STOP off
\i tests/sql/rpthub_tt.sql
\set u_o '00000000-0000-0000-0000-000000000510'
\set u_st '00000000-0000-0000-0000-000000000511'
\set u_no '00000000-0000-0000-0000-000000000512'
insert into auth.users (id, email, raw_user_meta_data) values
 (:'u_o', 'test_owner510@example.test', '{}'), (:'u_st', 'test_staff510@example.test', '{}'), (:'u_no', 'test_nogrant510@example.test', '{}')
 on conflict do nothing;
update public.profiles set status = 'active' where id in (:'u_st', :'u_no');
insert into public.user_grants (user_id, grant_code) values (:'u_st', 'assistant_use') on conflict do nothing;

\echo == T1 defaults and anon
select tt.chk('T1 ai_on is OFF by default', public.rule_on('ai_on') = false);
select tt.chk('T1 ai_pause_all is OFF by default', public.rule_on('ai_pause_all') = false);
select tt.chk('T1 only the local provider is enabled at the start', (select count(*) from public.ai_providers where enabled) = 1 and (select enabled from public.ai_providers where code = 'local_rules'));
select tt.chk('T1 every agent is disabled at the start', (select count(*) from public.ai_agents where enabled) = 0 and (select count(*) from public.ai_agents) = 10);
select tt.chk('T1 no provider or agent table has a key or secret column', not exists (select 1 from information_schema.columns where table_name in ('ai_providers', 'ai_agents') and column_name ~ '(api_?key|secret|password)'));
select tt.chk('T1 anon cannot run ai_check', not has_function_privilege('anon', 'public.ai_check(text,text,text,int)', 'execute'));
select tt.chk('T1 anon cannot read ai_calls', not has_table_privilege('anon', 'public.ai_calls', 'select'));
select tt.chk('T1 anon cannot read ai_providers', not has_table_privilege('anon', 'public.ai_providers', 'select'));
select tt.chk('T1 signed-in role has EXECUTE on ai_check', has_function_privilege('authenticated', 'public.ai_check(text,text,text,int)', 'execute'));

\echo == T2 forbidden actions and the untrusted-input rule (agent catalogue guards)
select tt.err('T2 an agent may not be given a payment action', $q$insert into public.ai_agents (code, label_bn, label_en, proposal_actions) values ('test_bad_pay', 'a', 'b', '{pay.supplier}')$q$, 'forbidden_action');
select tt.err('T2 an agent may not be given a publish action', $q$insert into public.ai_agents (code, label_bn, label_en, proposal_actions) values ('test_bad_pub', 'a', 'b', '{content.publish}')$q$, 'forbidden_action');
select tt.err('T2 an untrusted-input agent may not hold a proposal action', $q$insert into public.ai_agents (code, label_bn, label_en, proposal_actions, untrusted_input) values ('test_untr', 'a', 'b', '{insight.note}', true)$q$, 'untrusted_input_no_proposals');
select tt.err('T2 a bad action name is refused', $q$insert into public.ai_agents (code, label_bn, label_en, proposal_actions) values ('test_bad_name', 'a', 'b', '{Drop Table}')$q$, 'bad_action_name');
select tt.err('T2 a forbidden grant is refused (agent cannot hold owner rights)', $q$insert into public.ai_agent_grants values ('erp_guide', 'owner_rules')$q$, 'forbidden_grant');
select tt.err('T2 an agent may not hold assistant_use', $q$insert into public.ai_agent_grants values ('erp_guide', 'assistant_use')$q$, 'forbidden_grant');
select tt.chk('T2 seeded untrusted agents have no proposal action', not exists (select 1 from public.ai_agents where untrusted_input and cardinality(proposal_actions) > 0));

\echo == T3 the gate: owner switches, provider, budget
select tt.as(:'u_o');
set role authenticated;
select tt.chk('T3 gate says ai_off while the switch is OFF', public.ai_check('local_rules', null, 'none', 0)->>'reason' = 'ai_off');
reset role;
select public.set_rule('ai_on', 'true'::jsonb);
set role authenticated;
select tt.chk('T3 local provider is allowed once the switch is ON', (public.ai_check('local_rules', null, 'none', 0)->>'ok')::boolean);
select tt.err('T3 a paid provider cannot be enabled without a budget', $q$select public.ai_provider_save('anthropic', 'anthropic', 'Anthropic', 'test-model', true, 'none', 15000, 1024, null, null, null, null, 10)$q$, 'budget_needed');
select tt.err('T3 a paid provider cannot be enabled without a model name', $q$select public.ai_provider_save('anthropic', 'anthropic', 'Anthropic', null, true, 'none', 15000, 1024, 1000, null, null, null, 10)$q$, 'model_needed');
select tt.chk('T3 owner saves a paid provider with a token budget', (public.ai_provider_save('anthropic', 'anthropic', 'Anthropic', 'test-model', true, 'none', 15000, 1024, 1000, null, null, null, 10)->>'enabled')::boolean);
select tt.chk('T3 the paid provider now answers within budget', (public.ai_check('anthropic', null, 'none', 100)->>'ok')::boolean);
select tt.chk('T3 full data to a provider that shares none is refused', public.ai_check('anthropic', null, 'full', 10)->>'reason' = 'data_not_allowed');
select tt.chk('T3 redacted data to a provider that shares none is refused', public.ai_check('anthropic', null, 'redacted', 10)->>'reason' = 'data_not_allowed');
select tt.chk('T3 an unknown level is refused', public.ai_check('anthropic', null, 'everything', 10)->>'reason' = 'bad_level');
reset role;
select public.ai_log('anthropic', null, 'call', 600, 300, 1200) is not null as x \gset
set role authenticated;
select tt.chk('T3 budget: the used tokens are counted (900 of 1000)', (public.ai_check('anthropic', null, 'none', 0)->>'tokens_used')::int = 900);
select tt.chk('T3 budget: a call that would pass the limit is stopped', public.ai_check('anthropic', null, 'none', 200)->>'reason' = 'budget_spent');
select tt.chk('T3 budget: a small call still fits', (public.ai_check('anthropic', null, 'none', 50)->>'ok')::boolean);
select tt.chk('T3 the owner sees the token limit on the provider table (no key)', exists (select 1 from public.ai_providers where code = 'anthropic' and monthly_token_budget = 1000));
reset role;
select public.ai_provider_save('anthropic', 'anthropic', 'Anthropic', 'test-model', true, 'none', 15000, 1024, null, 5, null, null, 10) is not null as x8 \gset
select public.ai_check('anthropic', null, 'none', 0)->>'reason' as r8 \gset
select tt.chk('T3 with a money budget and no prices the gate says price_needed (never a made-up figure)', :'r8' = 'price_needed');

\echo == T4 money estimate uses only the owner's prices
select tt.chk('T4 no money figure is stored while the price is blank', (select money_est is null from public.ai_calls order by id desc limit 1));
select public.ai_provider_save('anthropic', 'anthropic', 'Anthropic', 'test-model', true, 'none', 15000, 1024, 1000, 5, 2, 10, 10) is not null as x2 \gset
select public.ai_log('anthropic', null, 'call', 1000000, 0, 10) is not null as x3 \gset
select tt.chk('T4 money estimate = tokens x owner price (1,000,000 input tokens at 2.00 = 2.000000)', (select money_est = 2.000000 from public.ai_calls order by id desc limit 1));

\echo == T5 pause, staff and grants, agent provider match
select public.ai_pause_all(true) is not null as x4 \gset
set role authenticated;
select tt.chk('T5 pause all stops the gate', public.ai_check('local_rules', null, 'none', 0)->>'reason' = 'paused');
reset role;
select public.ai_pause_all(false) is not null as x5 \gset
select tt.as(:'u_st');
set role authenticated;
select tt.chk('T5 a staff member with assistant_use passes the gate', (public.ai_check('local_rules', null, 'none', 0)->>'ok')::boolean);
select tt.chk('T5 a staff member cannot read the provider table (owner only)', (select count(*) from public.ai_providers) = 0);
reset role;
select tt.as(:'u_no');
set role authenticated;
select tt.chk('T5 a person without assistant_use is refused', public.ai_check('local_rules', null, 'none', 0)->>'reason' = 'not_allowed');
reset role;
select tt.as(:'u_o');
select public.ai_agent_save('erp_guide', true, 'local_rules', 'none', '{assistant_me,assistant_health}', '{setup.draft_checklist}', false, null, 'owner', 'v1') is not null as x6 \gset
set role authenticated;
select tt.chk('T5 an enabled agent passes the gate on its own provider', (public.ai_check('local_rules', 'erp_guide', 'none', 0)->>'ok')::boolean);
select tt.chk('T5 an agent on another provider is refused (agent_provider_mismatch)', public.ai_check('anthropic', 'erp_guide', 'none', 0)->>'reason' = 'agent_provider_mismatch');
select tt.chk('T5 an unknown agent is refused', public.ai_check('local_rules', 'no_such_agent', 'none', 0)->>'reason' = 'unknown_agent');
select tt.chk('T5 the picker lists only enabled agents', (select count(*) from jsonb_array_elements(public.ai_agents_me())) = 1);
reset role;
select tt.as(:'u_st');
set role authenticated;
select tt.err('T5 staff cannot save an agent (owner only)', $q$select public.ai_agent_save('sales_analyst', true, 'local_rules', 'none', '{}', '{}', false, null, 'owner', 'v1')$q$, 'not allowed');
select tt.err('T5 staff cannot save a provider (owner only)', $q$select public.ai_provider_save('gemini', 'gemini', 'G', 'm', false, 'none', 1000, 64, null, null, null, null, 30)$q$, 'not allowed');
reset role;

\echo == T6 call log: append-only, actor type
select public.ai_log('local_rules', 'erp_guide', 'call', 10, 10, 5) is not null as x7 \gset
select tt.chk('T6 a call made for an agent is recorded with actor_type agent', (select actor_type = 'agent' from public.ai_calls where agent_code = 'erp_guide' order by id desc limit 1));
select tt.chk('T6 a call with no agent is recorded as human', (select actor_type = 'human' from public.ai_calls where agent_code is null order by id desc limit 1));
select tt.err('T6 the call log cannot be changed', $q$update public.ai_calls set ok = false$q$, 'append-only');
select tt.err('T6 the call log cannot be deleted', $q$delete from public.ai_calls$q$, 'append-only');
select tt.err('T6 a bad call kind is refused', $q$select public.ai_log('local_rules', null, 'publish', 0, 0, 0)$q$, 'bad_kind');
select tt.err('T6 a negative token count is refused', $q$select public.ai_log('local_rules', null, 'call', -5, 0, 0)$q$, 'bad_number');

\echo == T7 nothing is deleted from configuration
select tt.err('T7 a provider cannot be deleted', $q$delete from public.ai_providers where code = 'anthropic'$q$, 'nothing is deleted');
select tt.err('T7 an agent cannot be deleted', $q$delete from public.ai_agents where code = 'erp_guide'$q$, 'nothing is deleted');

\echo == T8 paste twice (run this file on a database where phase510 was pasted twice)
select tt.chk('T8 the switches still exist once', (select count(*) = 1 from public.rules where key = 'ai_on'));
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
