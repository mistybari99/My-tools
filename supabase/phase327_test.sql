-- FRESH DB ONLY. Phase 327 tests (CRM-G part 5: status for the screens, settings overview, go-live checklist) and the whole-package checks.
--   build: phases 8..98, then 323 to 327;  psql -h /tmp -p 5575 -U postgres -d <db> -qAt -f supabase/phase327_test.sql 2>&1 | grep -E 'FAIL|RESULT'
\ir ../tests/sql/crmg_common.sql
select tt.books() as b0 \gset

\echo == T0 status: what each person may do (the server still decides every call)
set role authenticated;
select tt.as(:'u_o');
select _crmg_status() as so \gset
select tt.chk('T0 owner: everything, both modules OFF by default', (:'so'::jsonb ->> 'is_owner')::boolean and (:'so'::jsonb ->> 'can_manage_leads')::boolean and (:'so'::jsonb ->> 'sees_all_outlets')::boolean
  and not (:'so'::jsonb ->> 'lead_on')::boolean and not (:'so'::jsonb ->> 'task_on')::boolean and not (:'so'::jsonb ->> 'reminder_on')::boolean);
select tt.as(:'u_s1');
select _crmg_status() as ss \gset
select tt.chk('T0 salesperson: may create enquiries, not manage, sees one outlet, cannot assign or see all tasks, cannot edit lists',
  (:'ss'::jsonb ->> 'can_create_lead')::boolean and not (:'ss'::jsonb ->> 'can_manage_leads')::boolean and not (:'ss'::jsonb ->> 'sees_all_outlets')::boolean
  and not (:'ss'::jsonb ->> 'can_assign_tasks')::boolean and not (:'ss'::jsonb ->> 'sees_all_tasks')::boolean and not (:'ss'::jsonb ->> 'can_edit_lists')::boolean);
select tt.chk('T0 salesperson: the staff list is empty (no staff directory for someone who cannot assign)', jsonb_array_length(:'ss'::jsonb -> 'staff_here') = 0);
select tt.as(:'u_m1');
select _crmg_status() as sm \gset
select tt.chk('T0 manager with the rights: manages, assigns tasks, sees a staff list, still only her outlet', (:'sm'::jsonb ->> 'can_manage_leads')::boolean and (:'sm'::jsonb ->> 'can_assign_tasks')::boolean
  and jsonb_array_length(:'sm'::jsonb -> 'staff_here') >= 5 and not (:'sm'::jsonb ->> 'sees_all_outlets')::boolean);
select tt.as(:'u_x');
select tt.chk('T0 a person with no role: cannot create, cannot manage', not (_crmg_status() ->> 'can_create_lead')::boolean and not (_crmg_status() ->> 'can_manage_leads')::boolean);
select tt.as(:'u_bot');
select tt.chk('T0 a login that is not approved gets signed_in false', not (_crmg_status() ->> 'signed_in')::boolean);

\echo == T1 settings overview and checklist: owner and managers only
select tt.as(:'u_s1');
select tt.err('T1 a salesperson cannot read the settings overview', $$select _crmg_settings()$$, 'not allowed');
select tt.err('T1 a salesperson cannot read the checklist', $$select _crmg_readiness()$$, 'not allowed');
select tt.as(:'u_o');
select _crmg_settings() as st \gset
select tt.chk('T1 thirteen settings and four rights are listed with plain-English text', jsonb_array_length(:'st'::jsonb -> 'rules') = 13 and jsonb_array_length(:'st'::jsonb -> 'grants') = 4
  and not exists (select 1 from jsonb_array_elements(:'st'::jsonb -> 'rules') x where coalesce(x ->> 'label', '') = '' or coalesce(x ->> 'hint', '') = ''));
select tt.chk('T1 every setting shows its default and its effective value (= default now)', not exists (select 1 from jsonb_array_elements(:'st'::jsonb -> 'rules') x where (x -> 'effective') is distinct from (x -> 'default')));
select _crmg_readiness() as rd \gset
select tt.chk('T1 the checklist at defaults: not all ok, tells why', not (:'rd'::jsonb ->> 'all_ok')::boolean and jsonb_array_length(:'rd'::jsonb -> 'items') >= 8
  and not exists (select 1 from jsonb_array_elements(:'rd'::jsonb -> 'items') x where coalesce(x ->> 'hint', '') = ''));
select tt.chk('T1 lead and task switches show as not ok while OFF', exists (select 1 from jsonb_array_elements(:'rd'::jsonb -> 'items') x where x ->> 'key' = 'lead_on' and not (x ->> 'ok')::boolean)
  and exists (select 1 from jsonb_array_elements(:'rd'::jsonb -> 'items') x where x ->> 'key' = 'task_on' and not (x ->> 'ok')::boolean));
select set_rule('crm_lead_on', 'true') is null as a1 \gset
select set_rule('crm_task_on', 'true') is null as a2 \gset
select set_rule('online_orders_on', 'true') is null as a3 \gset
select set_rule('crm_lead_quote_valid_days', '14') is null as a4 \gset
reset role;
update forms set enabled = true where code in ('20-1', '20-4');
set role authenticated; select tt.as(:'u_m1');
select _crmg_readiness() as rd2 \gset
select tt.chk('T1 after setup every item is ok (a sales channel exists, a manager is named, forms are on)', (:'rd2'::jsonb ->> 'all_ok')::boolean);

\echo == T2 package-wide: paste order, privileges, naming
reset role;
select tt.chk('T2 every function of the package starts with _crmg_ and no browser role can run a helper',
  not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like '%crmg%' and p.proname not like '\_crmg\_%')
  and not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_crmg_ev','_crmg_audit','_crmg_exc','_crmg_lead_load','_crmg_task_load','_crmg_lead_vis','_crmg_lead_mgr','_crmg_can_create','_crmg_can_act','_crmg_quote_items','_crmg_lead_rows','_crmg_sched_ok','_crmg_lead_task_sync','_crmg_lead_tasks_close')
                   and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
select tt.chk('T2 the API functions are open to signed-in users only, never to anon',
  (select bool_and(has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('_crmg_lead_save','_crmg_lead_note','_crmg_lead_assign','_crmg_lead_stage','_crmg_lead_reopen','_crmg_quote_save','_crmg_quote_respond','_crmg_lead_get','_crmg_lead_convert','_crmg_lead_list',
       '_crmg_lead_board','_crmg_lead_report','_crmg_task_save','_crmg_task_done','_crmg_task_snooze','_crmg_task_skip','_crmg_my_tasks','_crmg_task_counts','_crmg_tasks_sweep','_crmg_task_scan','_crmg_lists','_crmg_list_save',
       '_crmg_status','_crmg_settings','_crmg_readiness')));
select tt.chk('T2 25 API functions exist', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and has_function_privilege('authenticated', p.oid, 'execute') and p.proname like '\_crmg\_%') = 25);
select tt.chk('T2 the package changed no shared function: no notify, digest, sale, order, form, journal function mentions crmg',
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname not like '%crmg%' and position('_crmg_' in pg_get_functiondef(p.oid)) > 0) = 0);
select tt.chk('T2 the books are exactly as they were', tt.books() = :'b0');
select 'RESULT ' || count(*) filter (where ok) || ' pass ' || count(*) filter (where not ok) || ' fail' from tt.res;
