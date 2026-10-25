-- FRESH DB ONLY. Phase 323 tests (CRM-G part 1: settings, rights, lists, tables, guards).
--   build: phases 8..98, then phase323 (tests/sql: crmg build recipe in docs/integration/CRM-G.md);  run from the repo root:
--   psql -h /tmp -p 5575 -U postgres -d <db> -qAt -f supabase/phase323_test.sql 2>&1 | grep -E 'FAIL|RESULT'
\ir ../tests/sql/crmg_common.sql

select tt.books() as b0 \gset
\echo == T0 shape, safe defaults, nothing shared patched
select tt.chk('T0 phase323 present', to_regprocedure('public._crmg_present()') is not null);
select tt.chk('T0 thirteen rules in module crm, English text only',
  (select count(*) from rules where module = 'crm' and key in ('crm_lead_on','crm_task_on','crm_lead_lost_by','crm_lead_reopen_mode','crm_lead_win_needs_quote','crm_lead_quote_valid_days','crm_quote_min_lead_days',
     'crm_lead_stale_days','crm_lead_list_add_mode','crm_task_default_due_hours','crm_task_snooze_max_days','crm_order_task_days','crm_task_reminder_on')) = 13
  and not exists (select 1 from rules where key like 'crm\_%' and (label_en is null or label_en ~ '[^\x01-\x7f]' or hint_en ~ '[^\x01-\x7f]' or label_bn is distinct from label_en)));
select tt.chk('T0 safe defaults: modules OFF, reminders OFF, numbers blank, choices manager / reason / owner',
  not rule_on('crm_lead_on') and not rule_on('crm_task_on') and not rule_on('crm_task_reminder_on') and not rule_on('crm_lead_win_needs_quote')
  and rule_num('crm_lead_quote_valid_days') is null and rule_num('crm_quote_min_lead_days') is null and rule_num('crm_lead_stale_days') is null and rule_num('crm_task_default_due_hours') is null
  and rule_num('crm_task_snooze_max_days') is null and rule_num('crm_order_task_days') is null
  and rule_txt('crm_lead_lost_by') = 'manager' and rule_txt('crm_lead_reopen_mode') = 'reason' and rule_txt('crm_lead_list_add_mode') = 'owner');
select tt.chk('T0 four rights exist and nobody holds them through a role',
  (select count(*) from grant_defs where grant_code in ('crm_lead_manage','crm_lead_all','crm_task_assign','crm_task_all')) = 4
  and not exists (select 1 from rule_grants where grant_code like 'crm\_%' and allowed));
select tt.chk('T0 the six CRM tables are closed to browser roles, RLS on',
  (select bool_and(relrowsecurity) from pg_class where relname in ('crm_leads','crm_lead_events','crm_lead_quotes','crm_tasks','crm_task_events','crm_lead_lists'))
  and not has_table_privilege('authenticated', 'public.crm_leads', 'select') and not has_table_privilege('authenticated', 'public.crm_tasks', 'insert') and not has_table_privilege('anon', 'public.crm_lead_events', 'select'));
select tt.chk('T0 API open to signed-in users only, helpers and the lock function closed',
  has_function_privilege('authenticated', 'public._crmg_lists(boolean)', 'execute') and not has_function_privilege('anon', 'public._crmg_lists(boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public._crmg_ev(uuid,text,text,text,text,jsonb)', 'execute') and not has_function_privilege('authenticated', 'public._crmg_lock(text[],text[])', 'execute')
  and not has_function_privilege('authenticated', 'public._crmg_lead_vis(integer,uuid,uuid)', 'execute'));
select tt.chk('T0 no shared function was patched (no crmg text inside the integrator-owned functions)',
  (select count(*) from (values ('public.notify_scan()'),('public.daily_digest()'),('public.lock_check(date)'),('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,uuid,boolean)'),('public.online_order_save2(uuid,uuid,integer,integer,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text,text,text,text,text,text,bigint,boolean)'),('public.save_entry(uuid,text,integer,date,jsonb,jsonb,text,jsonb)')) v(f)
     where to_regprocedure(v.f) is not null and position('crmg' in pg_get_functiondef(v.f::regprocedure)) > 0) = 0);
select tt.chk('T0 the Exceptions list keeps its old kinds and has the three new ones',
  (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%') ~ 'crmg_lead_reopen'
  and (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%') ~ 'crmg_late_quote'
  and (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%') ~ 'crmg_win_without_quote'
  and (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%') ~ 'w1e_duplicate_payment');

\echo == T1 lists
select tt.chk('T1 every list has the entry Other', (select count(distinct kind) from crm_lead_lists where code = 'other') = 3);
set role authenticated;
select tt.as(:'u_o');
select tt.chk('T1 the owner sees the three lists', jsonb_array_length((_crmg_lists(false))->'lost_reason') >= 6 and (_crmg_lists(false)->>'can_edit')::boolean);
select tt.as(:'u_s1');
select tt.chk('T1 a salesperson sees the lists but cannot edit', not (_crmg_lists(false)->>'can_edit')::boolean);
select tt.err('T1 a salesperson cannot add a list entry', $$select _crmg_list_save('source','test_fair','Fair')$$, 'not allowed');
select tt.as(:'u_m1');
select tt.err('T1 a manager cannot add while the mode is owner (default)', $$select _crmg_list_save('source','test_fair','Fair')$$, 'not allowed');
select tt.as(:'u_x');
select tt.err('T1 a person with no role cannot add', $$select _crmg_list_save('source','test_fair','Fair')$$, 'not allowed');
select tt.as(:'u_o');
select _crmg_list_save('source','test_fair','Fair or exhibition') ->> 'created' as c1 \gset
select tt.chk('T1 the owner adds a source', :'c1' = 'true' and tt.q($q$select active from crm_lead_lists where kind='source' and code='test_fair'$q$)::boolean);
select tt.chk('T1 the new entry sorts before Other', tt.q($q$select sort from crm_lead_lists where kind='source' and code='test_fair'$q$)::int < tt.q($q$select sort from crm_lead_lists where kind='source' and code='other'$q$)::int);
select tt.err('T1 a bad code is refused', $$select _crmg_list_save('source','Bad Code','x')$$, 'bad_code');
select tt.err('T1 an unknown list is refused', $$select _crmg_list_save('colour','test_red','Red')$$, 'bad_list');
select tt.err('T1 Other can never be retired', $$select _crmg_list_save('lost_reason','other','Other',false)$$, 'other_stays');
select _crmg_list_save('source','test_fair','Fair or exhibition',false) ->> 'updated' as c2 \gset
select tt.chk('T1 an entry is retired, not deleted', :'c2' = 'true' and tt.q($q$select count(*) from crm_lead_lists where kind='source' and code='test_fair' and not active$q$)='1'
  and not exists (select 1 from jsonb_array_elements((_crmg_lists(false))->'source') x where x->>'code' = 'test_fair')
  and exists (select 1 from jsonb_array_elements((_crmg_lists(true))->'source') x where x->>'code' = 'test_fair'));
reset role;
select set_config('request.jwt.claim.sub', :'u_o', false);
set role authenticated;
select set_rule('crm_lead_list_add_mode', '"manager"') is null as r1 \gset
select tt.as(:'u_m1');
select _crmg_list_save('occasion','test_open_day','Open day') ->> 'created' as c3 \gset
select tt.chk('T1 with mode manager the holder of Manage enquiries may add', :'c3' = 'true');
select tt.as(:'u_s1');
select tt.err('T1 with mode manager a plain salesperson still cannot', $$select _crmg_list_save('occasion','test_x','X')$$, 'not allowed');
select tt.as(:'u_o');
select set_rule('crm_lead_list_add_mode', '"owner"') is null as r2 \gset
select tt.as(:'u_hq');
select tt.err('T1 head office without the right is refused', $$select _crmg_list_save('occasion','test_y','Y')$$, 'not allowed');
reset role;
select tt.chk('T1 every list change is in the audit log', (select count(*) from audit_log where table_name = 'crm_lead_lists') >= 3);

\echo == T2 guards (direct writes as the table owner: the database itself refuses)
insert into crm_leads (id, location_id, contact_name, stage, owner_user, created_by) values ('00000000-0000-0000-0000-00000000a000', 1, 'test_g0', 'won', :'u_o', :'u_o');
select tt.err('T2 an illegal stage jump written directly is refused (won to enquiry)', $$update crm_leads set stage = 'enquiry' where id = '00000000-0000-0000-0000-00000000a000'$$, 'illegal_stage_move');
insert into crm_leads (id, location_id, contact_name, owner_user, created_by) values ('00000000-0000-0000-0000-00000000a001', 1, 'test_g1', :'u_o', :'u_o');
select tt.err('T2 lost needs a reason from the list', $$update crm_leads set stage = 'lost', lost_reason = 'test_not_listed' where id = '00000000-0000-0000-0000-00000000a001'$$, 'lost_reason_required');
select tt.err('T2 lost without a reason is refused by the table rule', $$update crm_leads set stage = 'lost' where id = '00000000-0000-0000-0000-00000000a001'$$, 'lost_reason_required');
update crm_leads set stage = 'lost', lost_reason = 'no_reply' where id = '00000000-0000-0000-0000-00000000a001';
select tt.chk('T2 a lost lead has a closed time', (select closed_at is not null from crm_leads where id = '00000000-0000-0000-0000-00000000a001'));
select tt.err('T2 lost to won written directly is refused', $$update crm_leads set stage = 'won', lost_reason = null where id = '00000000-0000-0000-0000-00000000a001'$$, 'illegal_stage_move');
select tt.err('T2 lost to enquiry written directly is refused (only the reopen function may)', $$update crm_leads set stage = 'enquiry', lost_reason = null where id = '00000000-0000-0000-0000-00000000a001'$$, 'illegal_stage_move');
select tt.err('T2 a lost lead cannot be edited', $$update crm_leads set contact_name = 'test_g2' where id = '00000000-0000-0000-0000-00000000a001'$$, 'lead_closed');
select tt.err('T2 a lead cannot be deleted', $$delete from crm_leads where id = '00000000-0000-0000-0000-00000000a001'$$, 'nothing is deleted');
insert into crm_lead_events (lead_id, kind, note) values ('00000000-0000-0000-0000-00000000a001', 'note', 'test');
select tt.err('T2 the trail cannot be changed', $$update crm_lead_events set note = 'x' where lead_id = '00000000-0000-0000-0000-00000000a001'$$, 'append_only');
select tt.err('T2 the trail cannot be deleted', $$delete from crm_lead_events where lead_id = '00000000-0000-0000-0000-00000000a001'$$, 'nothing is deleted');
insert into crm_lead_quotes (id, lead_id, version, status, valid_until, items, subtotal, total, created_by) values ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000a001', 1, 'sent', tt.today() + 5, '[{"desc":"x","qty":1,"price":10,"amount":10}]', 10, 10, :'u_o');
select tt.err('T2 a sent quote keeps its prices', $$update crm_lead_quotes set total = 5 where id = '00000000-0000-0000-0000-00000000b001'$$, 'quote_sent');
insert into crm_tasks (id, kind, title, due_at, assigned_to, created_by) values ('00000000-0000-0000-0000-00000000c001', 'call', 'test_t', now(), :'u_o', :'u_o');
update crm_tasks set status = 'done', done_at = now(), done_by = :'u_o' where id = '00000000-0000-0000-0000-00000000c001';
select tt.err('T2 a done task cannot be reopened', $$update crm_tasks set status = 'open', done_at = null where id = '00000000-0000-0000-0000-00000000c001'$$, 'task_closed');
select tt.err('T2 a done task cannot be changed', $$update crm_tasks set title = 'z' where id = '00000000-0000-0000-0000-00000000c001'$$, 'task_closed');
select tt.err('T2 a task cannot be deleted', $$delete from crm_tasks where id = '00000000-0000-0000-0000-00000000c001'$$, 'nothing is deleted');
select tt.chk('T2 nothing here touched the books', tt.books() = :'b0');

select 'RESULT ' || count(*) filter (where ok) || ' pass ' || count(*) filter (where not ok) || ' fail' from tt.res;
