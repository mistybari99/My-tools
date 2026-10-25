-- FRESH DB ONLY. Phase 479 tests (X1 foundation, part 1). Build through phase 479 (tests/sql/ORDER.txt), then from the repository root:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase479_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_*). Writes only to the throwaway test database.
\set ON_ERROR_STOP off
\i tests/sql/rpthub_tt.sql
\set u_o '00000000-0000-0000-0000-000000000480'
\set u_s '00000000-0000-0000-0000-000000000481'
\set u_b '00000000-0000-0000-0000-000000000482'
\set u_g '00000000-0000-0000-0000-000000000483'
\echo == setup
insert into auth.users (id, email, raw_user_meta_data) values
 (:'u_o', 'test_owner480@s.app', '{"full_name":"test_owner480"}'), (:'u_s', 'test_staff480@s.app', '{"full_name":"test_staff480"}'),
 (:'u_b', 'test_bot480@s.app', '{"full_name":"test_bot480"}'), (:'u_g', 'test_agent480@s.app', '{"full_name":"test_agent480"}') on conflict do nothing;
update public.profiles set status = 'active';
insert into public.user_roles (user_id, role_code) values (:'u_o', 'owner'), (:'u_s', 'salesperson') on conflict do nothing;
insert into public.ops_accounts (user_id, purpose, active) values (:'u_b', 'notify', true) on conflict do nothing;
insert into public.customers (id, mobile, name) values ('00000000-0000-0000-0000-0000000004a0', '01700000480', 'test_customer480') on conflict do nothing;
insert into public.crm_contact_prefs (customer_id, dnc) values ('00000000-0000-0000-0000-0000000004a0', false) on conflict do nothing;

\echo == T1 defaults: everything OFF, nothing connected, no budget
select tt.chk('T1 automation_on is OFF', public.rule_on('automation_on') = false);
select tt.chk('T1 no automation pause', public.rule_txt('automation_pause_until') is null);
select tt.chk('T1 all 13 connection rows exist, none enabled, none connected', (select count(*) = 13 and bool_and(not enabled) and bool_and(status = 'not_connected') from public.integration_registry));
select tt.chk('T1 every connection is read-only, dry-run and has no monthly budget yet', (select bool_and(read_only and dry_run and monthly_call_cap = 0 and rate_per_min = 10) from public.integration_registry));
select tt.chk('T1 kinds: payment kind covers bKash and Nagad', (select count(*) = 2 from public.integration_registry where kind = 'payment' and code in ('bkash', 'nagad')));
select tt.chk('T1 redaction helper hides phone and e-mail', public.x1_redact('call 01712345678 or a.b@mail.test now') = 'call [phone] or [email] now');

\echo == T2 anon and staff are refused
set role anon;
select tt.err('T2 anon: registry is not readable', 'select count(*) from public.integration_registry', 'permission denied');
select tt.err('T2 anon: site config table is not readable', 'select count(*) from public.site_config', 'permission denied');
select tt.err('T2 anon: the gate cannot be called', $q$select public.x1_gate('sms_send', 'website')$q$, 'permission denied');
select tt.err('T2 anon: site_config_get cannot be called', 'select public.site_config_get()', 'permission denied');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_s', false);
select tt.chk('T2 staff (no owner, no bot): the registry is empty to them', (select count(*) = 0 from public.integration_registry));
select tt.err('T2 staff: the gate says not allowed', $q$select public.x1_gate('sms_send', 'website')$q$, 'not allowed');
select tt.err('T2 staff: job_run_start says not allowed', $q$select public.job_run_start('notify_digest', true)$q$, 'not allowed');
select tt.err('T2 staff: integration_set says not allowed', $q$select public.integration_set('website', '{"enabled":true}')$q$, 'not allowed');
select tt.chk('T2 staff: site config reads for a signed-in user (published = false)', (select (public.site_config_get() ->> 'published')::boolean = false));
reset role;

\echo == T3 writes only through functions; owner direct writes refused
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select tt.err('T3 owner: direct update of the registry is refused', $q$update public.integration_registry set enabled = true where code = 'website'$q$, 'permission denied');
select tt.err('T3 owner: direct insert into job_runs is refused', $q$insert into public.job_runs (job) values ('notify_digest')$q$, 'permission denied');
select tt.err('T3 owner: unknown field in integration_set is refused', $q$select public.integration_set('website', '{"status":"connected"}')$q$, 'field_not_allowed');
reset role;
select tt.err('T3 nothing is deleted (even by the database owner)', $q$delete from public.integration_registry where code = 'other'$q$, 'retire instead');

\echo == T4 the gate: every switch is a denial until all are on
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select tt.chk('T4 gate: automation OFF denies with automation_off', (public.x1_gate('sms_send', 'website') ->> 'reason') = 'automation_off');
reset role;
update public.rules set value = 'true' where key = 'automation_on';
set role authenticated;
select tt.chk('T4 gate: integration OFF denies', (public.x1_gate('sms_send', 'website') ->> 'reason') = 'integration_off');
select public.integration_set('website', '{"config":{"public_url":"https://test-site.invalid","domain":"test-site.invalid"},"enabled":true}') as r \gset
select tt.chk('T4 integration_set: a config makes it configured, never connected', (select status = 'configured' from public.integration_registry where code = 'website'));
select tt.chk('T4 integration_set: a change is versioned', (select config_version = 2 from public.integration_registry where code = 'website') and (select count(*) >= 1 from public.integration_config_versions where code = 'website'));
select tt.chk('T4 gate: no monthly budget set denies with budget_not_set', (public.x1_gate('sms_send', 'website') ->> 'reason') = 'budget_not_set');
select public.integration_set('website', '{"monthly_call_cap":5,"rate_per_min":10}') as r \gset
select tt.chk('T4 gate: a read is allowed', (public.x1_gate('site_read', 'website') ->> 'allow') = 'true');
select tt.chk('T4 gate: a write on a read-only connection is refused', (public.x1_gate('site_write', 'website', true) ->> 'reason') = 'read_only');
select public.integration_set('website', '{"read_only":false}') as r \gset
select tt.chk('T4 gate: a write while dry-run is ON is never allowed', (public.x1_gate('site_write', 'website', true) ->> 'reason') = 'dry_run' and (public.x1_gate('site_write', 'website', true) ->> 'allow') = 'false');
select tt.chk('T4 the gate logged every decision', (select count(*) >= 7 from public.x1_gate_log where code = 'website'));
reset role;

\echo == T5 do-not-contact, budget, rate, pause
update public.crm_contact_prefs set dnc = true where customer_id = '00000000-0000-0000-0000-0000000004a0';
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select tt.chk('T5 do-not-contact wins over an allowed read', (public.x1_gate('site_read', 'website', false, '00000000-0000-0000-0000-0000000004a0') ->> 'reason') = 'do_not_contact');
reset role;
update public.crm_contact_prefs set dnc = false where customer_id = '00000000-0000-0000-0000-0000000004a0';
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select public.integration_set('website', '{"rate_per_min":2}') as r \gset
select tt.chk('T5 rate: first call of the minute is allowed', (public.x1_gate('site_read', 'website') ->> 'allow') = 'true');
select tt.chk('T5 rate: second call in the same minute is rate_limited', (public.x1_gate('site_read', 'website') ->> 'reason') = 'rate_limited');
select public.integration_set('website', '{"rate_per_min":10,"monthly_call_cap":1}') as r \gset
select tt.chk('T5 budget: the monthly cap is reached and denies', (public.x1_gate('site_read', 'website') ->> 'reason') = 'budget_exhausted');
select public.integration_set('website', '{"monthly_call_cap":1000}') as r \gset
reset role;
update public.rules set value = '"2099-01-01T00:00:00+06:00"' where key = 'automation_pause_until';
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select tt.chk('T5 pause: a future pause denies with paused', (public.x1_gate('site_read', 'website') ->> 'reason') = 'paused');
reset role;
update public.rules set value = '"not a time"' where key = 'automation_pause_until';
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select tt.chk('T5 pause: an unreadable pause value counts as paused (fail closed)', (public.x1_gate('site_read', 'website') ->> 'reason') = 'paused');
reset role;
update public.rules set value = null where key = 'automation_pause_until';

\echo == T6 secrets are never stored
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select tt.err('T6 config with a secret-looking key is refused', $q$select public.integration_set('website', '{"config":{"api_key":"x"}}')$q$, 'secret_not_allowed');
select tt.err('T6 config with a token-looking value is refused', $q$select public.integration_set('website', '{"config":{"endpoint":"sk-abcdefghijklmnop"}}')$q$, 'secret_not_allowed');
select tt.err('T6 env_names must hold a NAME, not a value', $q$select public.integration_set('website', '{"env_names":["sk-abcdefghijklmnop"]}')$q$, 'env_name_must_be_a_name');
select public.integration_set('website', '{"env_names":["WEBSITE_PUBLISH_TOKEN"]}') is not null as ok_name \gset
select tt.chk('T6 a secret NAME is accepted', (select 'WEBSITE_PUBLISH_TOKEN' = any(env_names) from public.integration_registry where code = 'website'));
reset role;
select tt.chk('T6 no column of any x1 table is named like a secret', not exists (select 1 from information_schema.columns c where c.table_schema = 'public'
  and c.table_name in ('integration_registry', 'integration_config_versions', 'job_runs', 'job_heartbeat', 'agent_accounts', 'x1_gate_log', 'webhook_rotations', 'site_config')
  and c.column_name ~* '(secret|token|passw|pwd|api_?key|private|credential|bearer|signing)'));
select tt.chk('T6 no x1 function takes a parameter named like a secret', not exists (select 1 from pg_proc p, unnest(coalesce(p.proargnames, '{}'::text[])) a
  where p.pronamespace = 'public'::regnamespace and p.proname ~ '(x1|job_|integration_|webhook_|agent_account|site_config)' and a ~* '(secret|token|passw|pwd|api_?key|private|credential|bearer|signing)'));
select tt.chk('T6 the backup whitelist still includes the x1 tables (no secret-named column)', (select count(*) = 8 from unnest(public._backup_tables()) t where t in ('integration_registry', 'integration_config_versions', 'job_runs', 'job_heartbeat', 'agent_accounts', 'x1_gate_log', 'webhook_rotations', 'site_config')));
select tt.chk('T6 webhook rotation keeps the NAME and time, never a value', (select count(*) = 0 from information_schema.columns where table_name = 'webhook_rotations' and column_name ~* 'value|secret'));

\echo == T7 job kill switch and heartbeat
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_b', false);
select public.job_run_start('notify_digest', true) as r \gset
select tt.chk('T7 bot: job runs while automation is ON', (:'r'::jsonb ->> 'allowed') = 'true');
select public.job_run_finish((:'r'::jsonb ->> 'run_id')::bigint, true, 'call 01712345678 failed', '{"sent":0}');
reset role;
select tt.chk('T7 finish: the error text is redacted and counts saved', (select error = 'call [phone] failed' and counts ->> 'sent' = '0' from public.job_runs where id = (:'r'::jsonb ->> 'run_id')::bigint));
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_b', false);
select public.job_heartbeat('notify_digest', 'ok') ;
reset role;
select tt.chk('T7 heartbeat recorded', (select count(*) = 1 from public.job_heartbeat where job = 'notify_digest'));
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_b', false);
reset role;
update public.rules set value = 'false' where key = 'automation_on';
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_b', false);
select public.job_run_start('notify_digest', true) as r \gset
select tt.chk('T7 kill switch: automation OFF stops the job (allowed false)', (:'r'::jsonb ->> 'allowed') = 'false' and (:'r'::jsonb ->> 'reason') = 'automation_off');
reset role;
select tt.chk('T7 kill switch: the skipped run is recorded, not counted as a failure', (select ok is null and error = 'skipped: automation_off' from public.job_runs where id = (:'r'::jsonb ->> 'run_id')::bigint));
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_b', false);
select tt.chk('T7 kill switch: the gate denies the bot too', (public.x1_gate('sms_send', 'website', true) ->> 'allow') = 'false');
reset role;
update public.rules set value = 'true' where key = 'automation_on';
update public.rules set value = '"2099-01-01T00:00:00+06:00"' where key = 'automation_pause_until';
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_b', false);
select tt.chk('T7 pause: job_run_start reports paused', (public.job_run_start('notify_digest', true) ->> 'reason') = 'paused');
reset role;
update public.rules set value = null where key = 'automation_pause_until';
update public.rules set value = 'false' where key = 'automation_on';

\echo == T8 agent accounts: no role, no grant, ever
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select public.agent_account_set(:'u_g', 'test_agent_480', true) is not null as ok_agent \gset
select tt.err('T8 an owner cannot make a staff member with a role into an agent', $q$select public.agent_account_set('00000000-0000-0000-0000-000000000481', 'test_agent_481')$q$, 'agent_must_have_no_roles_or_grants');
reset role;
select tt.chk('T8 the agent row was created for a user with no roles or grants', (select count(*) = 1 from public.agent_accounts where user_id = :'u_g'));
select tt.err('T8 a role cannot be given to an agent', $q$insert into public.user_roles (user_id, role_code) values ('00000000-0000-0000-0000-000000000483', 'owner')$q$, 'agent_cannot_hold_roles');
select tt.err('T8 set_rule cannot be granted to an agent', $q$insert into public.user_grants (user_id, grant_code) values ('00000000-0000-0000-0000-000000000483', 'set_rule')$q$, 'agent_cannot_hold_grants');
select tt.err('T8 grant rights cannot be granted to an agent', $q$insert into public.user_grants (user_id, grant_code) values ('00000000-0000-0000-0000-000000000483', 'grant_admin')$q$, 'agent_cannot_hold_grants');
select tt.err('T8 audit view cannot be granted to an agent', $q$insert into public.user_grants (user_id, grant_code) values ('00000000-0000-0000-0000-000000000483', 'audit_view')$q$, 'agent_cannot_hold_grants');
select tt.err('T8 finance posting cannot be granted to an agent', $q$insert into public.user_grants (user_id, grant_code) values ('00000000-0000-0000-0000-000000000483', 'accounts_manage')$q$, 'agent_cannot_hold_grants');
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_g', false);
select tt.err('T8 agent: set_rule is refused', $q$select public.set_rule('automation_on', 'true')$q$, 'not allowed');
select tt.err('T8 agent: the gate is the only door, and it is refused without automation', $q$select public.integration_set('website', '{"enabled":true}')$q$, 'not allowed');
select tt.chk('T8 agent: the gate answers (and logs the agent)', (public.x1_gate('site_read', 'website') ->> 'reason') = 'automation_off');
reset role;
select tt.chk('T8 the gate log names the agent as actor_type agent', (select actor_type = 'agent' from public.x1_gate_log where actor = :'u_g' order by id desc limit 1));
select tt.chk('T8 an agent is never an owner', not exists (select 1 from public.user_roles where user_id = :'u_g' and role_code = 'owner'));

\echo == T9 audit actor columns
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_g', false);
reset role;
insert into public.audit_log (action, table_name, record_id) values ('probe', 'test_probe480', 'x');
select tt.chk('T9 audit: an agent write is marked agent with its agent_id', (select actor_type = 'agent' and agent_id = 'test_agent_480' from public.audit_log where table_name = 'test_probe480' order by id desc limit 1));
select set_config('request.jwt.claim.sub', '', false);
insert into public.audit_log (action, table_name, record_id) values ('probe', 'test_probe480', 'y');
select tt.chk('T9 audit: a write with nobody signed in is marked human (default)', (select actor_type = 'human' and agent_id is null from public.audit_log where table_name = 'test_probe480' and record_id = 'y'));
select tt.chk('T9 audit: the actor columns are nullable with default human', (select is_nullable = 'YES' and column_default like '%human%' from information_schema.columns where table_name = 'audit_log' and column_name = 'actor_type'));
select tt.err('T9 audit: a logged line can not be changed', $q$update public.audit_log set action = 'x' where table_name = 'test_probe480'$q$, 'append');

\echo == T10 site config (read by the website)
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select tt.err('T10 public base URL must be https', $q$select public.site_config_set('{"public_base_url":"http://test-site.invalid"}')$q$, 'bad_input');
select tt.err('T10 an allowed origin must be https', $q$select public.site_config_set('{"allowed_origins":["http://test-site.invalid"]}')$q$, 'bad_input');
select tt.err('T10 unknown field refused', $q$select public.site_config_set('{"secret_key":"x"}')$q$, 'field_not_allowed');
select public.site_config_set('{"domain":"test-site.invalid","public_base_url":"https://test-site.invalid","allowed_origins":["https://test-site.invalid"],"brand_name_en":"test_brand480"}') is not null as ok_set \gset
select tt.chk('T10 owner sets the domain and origins', (public.site_config_get() ->> 'domain') = 'test-site.invalid' and (public.site_config_get() -> 'allowed_origins') ->> 0 = 'https://test-site.invalid');
select tt.chk('T10 published stays OFF until the owner switches it on', (public.site_config_get() ->> 'published')::boolean = false);
reset role;
select tt.chk('T10 the site config row is never deleted', (select count(*) = 1 from public.site_config));

\echo == T11 integration test result and webhook rotation record
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_b', false);
select public.integration_test_record('website', false, 'failed for test_user01712345678@mail.test') is not null as t1 \gset
reset role;
select tt.chk('T11 failed test: status error, detail redacted', (select status = 'error' and last_test_detail not like '%@%' and last_test_detail not like '%0171%' from public.integration_registry where code = 'website'));
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_b', false);
select public.integration_test_record('website', true, 'ok') is not null as t2 \gset
reset role;
select tt.chk('T11 a passed test: status connected (only a test sets it)', (select status = 'connected' and last_ok_at is not null from public.integration_registry where code = 'website'));
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_b', false);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_s', false);
select tt.err('T11 staff cannot record a test', $q$select public.integration_test_record('website', true, 'ok')$q$, 'not allowed');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :'u_o', false);
select public.webhook_rotation_record('website', 'WEBSITE_PUBLISH_TOKEN', 'rotated 01712345678') is not null as t3 \gset
select tt.chk('T11 rotation record: name and time only, note redacted', (select note = 'rotated [phone]' from public.webhook_rotations order by id desc limit 1));
select tt.err('T11 rotation record refuses a value-like name', $q$select public.webhook_rotation_record('website', 'sk-abc')$q$, 'check constraint');
reset role;

\echo == T12 helpers closed to browsers; paste-twice
select tt.chk('T12 anon cannot run the pause helper', not has_function_privilege('anon', 'public._x1_pause_active()', 'execute') and not has_function_privilege('authenticated', 'public._x1_pause_active()', 'execute'));
select tt.chk('T12 anon cannot run the job helper', not has_function_privilege('anon', 'public._x1_job_ok()', 'execute'));
select tt.chk('T12 signed-in role may run the gate and the job functions', has_function_privilege('authenticated', 'public.x1_gate(text,text,boolean,uuid)', 'execute') and has_function_privilege('authenticated', 'public.job_run_start(text,boolean)', 'execute'));
select tt.chk('T12 anon may run no x1 function', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '(x1|job_|integration_|webhook_|agent_account|site_config)' and has_function_privilege('anon', p.oid, 'execute')));
\i supabase/phase480.sql
select tt.chk('T12 second paste: the seeded connections are still 13 (no duplicates)', (select count(*) = 13 from public.integration_registry));
select tt.chk('T12 second paste: automation still OFF', public.rule_on('automation_on') = false);
select tt.chk('T12 second paste: the agent guard still works', (select count(*) = 1 from pg_trigger where tgname = 'user_grants_agent_guard'));
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
