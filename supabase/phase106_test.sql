-- FRESH DB ONLY. Phase 106 tests (backup / restore-drill coverage of the tables of phases 72..103).
--   bash tests/sql/final_build.sh p106db "<order from docs/PASTE_ORDER.md ... phase103 phase106>"
--   psql -h /tmp -p 5544 -U postgres -d p106db -qAt -f supabase/phase106_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1) on conflict do nothing;

\echo == T0 shape
select tt.chk('T0 perm_conflict is now in the backup list', 'perm_conflict' = any(public._backup_tables()));
select tt.chk('T0 secret-bearing tables stay out', not exists (select 1 from unnest(public._backup_tables()) t where t like 'ops\_%' or t like '%\_secret%'
  or t in ('login_failures','login_attempts','login_throttle','backup_runs','notifications','notification_reads','attendance_devices','intake_proofs94','telegram_secrets')));
select tt.chk('T0 assistant_usage (phase70) still in', 'assistant_usage' = any(public._backup_tables()));
select tt.chk('T0 _backup_tables and backup_coverage106 closed to anon', not has_function_privilege('anon','public._backup_tables()','execute') and not has_function_privilege('anon','public.backup_coverage106()','execute')
  and not has_function_privilege('authenticated','public._backup_tables()','execute') and has_function_privilege('authenticated','public.backup_coverage106()','execute'));

\echo == T1 every table created in phases 72..103 is covered or excluded on purpose
select tt.chk('T1 all ' || n || ' new tables exist', n = 71) from (select count(*) n from unnest(array['acct_autopost_runs85','acct_post_errors72','artisans','bill_pay_defaults99','bill_payments99','card_settlements85','cost_attrib_main','cost_bill_inputs','cost_bill_shares','cost_charge_types','cost_component_types','cost_share_reassign','cost_source_bills','cost_source_locs','cost_source_rule_shares','cost_source_rules','cost_source_types','cost_sources','doc_template_choice','drawer_events','factory_cost_pools','grant_separation_pairs','inbound_message_events','inbound_messages','inbox_unmask_log99','intake_bots','intake_failures','intake_hits','intake_proofs94','invoice_shares','item_categories','item_cost_flags','item_logistics','landed_cost_alloc','landed_cost_basis','landed_cost_docs','landed_cost_lines','landed_cost_stock','landed_costs','landed_skips','landed_supplier_flags','ledger_cost_supply96','location_cost_attribution','location_cost_cfg','manual_reason_codes85','online_order_flags','opening_stock_actions96','opening_stock_followups103','option_view_ops','order_dup_flags','perm_conflict','perm_reco_ignore','perm_reco_role','pos_failed_cards','pos_replay_log','recipe_cost_components','recipe_steps','recipe_versions','role_option_view','sale_return_packaging80','sales_channels','scan_events','scan_jobs','setup_apply_batches81','setup_apply_lines81','setup_check_defs81','setup_rec_defs81','setup_topic_defs81','telegram_chat_links','telegram_secrets','user_option_view']) t where to_regclass('public.'||t) is not null) x;
select tt.chk('T1 every new table is in _backup_tables() (' || count(*) || ')', count(*) = 69) from unnest(array['acct_autopost_runs85','acct_post_errors72','artisans','bill_pay_defaults99','bill_payments99','card_settlements85','cost_attrib_main','cost_bill_inputs','cost_bill_shares','cost_charge_types','cost_component_types','cost_share_reassign','cost_source_bills','cost_source_locs','cost_source_rule_shares','cost_source_rules','cost_source_types','cost_sources','doc_template_choice','drawer_events','factory_cost_pools','grant_separation_pairs','inbound_message_events','inbound_messages','inbox_unmask_log99','intake_bots','intake_failures','intake_hits','invoice_shares','item_categories','item_cost_flags','item_logistics','landed_cost_alloc','landed_cost_basis','landed_cost_docs','landed_cost_lines','landed_cost_stock','landed_costs','landed_skips','landed_supplier_flags','ledger_cost_supply96','location_cost_attribution','location_cost_cfg','manual_reason_codes85','online_order_flags','opening_stock_actions96','opening_stock_followups103','option_view_ops','order_dup_flags','perm_conflict','perm_reco_ignore','perm_reco_role','pos_failed_cards','pos_replay_log','recipe_cost_components','recipe_steps','recipe_versions','role_option_view','sale_return_packaging80','sales_channels','scan_events','scan_jobs','setup_apply_batches81','setup_apply_lines81','setup_check_defs81','setup_rec_defs81','setup_topic_defs81','telegram_chat_links','user_option_view']) t where t = any(public._backup_tables());
select tt.chk('T1 only telegram_secrets and intake_proofs94 are out on purpose', not exists (select 1 from unnest(array['intake_proofs94','telegram_secrets']) t where t = any(public._backup_tables())));
select tt.chk('T1 every public table is in the backup or has a documented reason', not exists (
  select 1 from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in ('r','p') and not c.relispartition and not (c.relname::text = any(public._backup_tables()))
   and c.relname::text not in ('attendance_devices','backup_runs','intake_proofs94','login_attempts','login_failures','login_throttle','notification_reads','notifications','ops_accounts','telegram_secrets')));
select tt.chk('T1 every public table has RLS (the drill checks it)', not exists (select 1 from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in ('r','p') and not c.relispartition and not c.relrowsecurity));
select tt.chk('T1 money / ledger tables in the list', 'journal_lines' = any(public._backup_tables()) and 'stock_ledger' = any(public._backup_tables()) and 'ledger_cost_supply96' = any(public._backup_tables())
  and 'bill_payments99' = any(public._backup_tables()) and 'landed_costs' = any(public._backup_tables()) and 'card_settlements85' = any(public._backup_tables()) and 'opening_stock_followups103' = any(public._backup_tables()));

\echo == T2 backup_coverage106 owner only
select tt.as(:'s');
select tt.err('T2 manager cannot read coverage', $$select backup_coverage106()$$, 'not allowed');
select tt.as(:'o');
select tt.chk('T2 owner: counts match _backup_tables()', (backup_coverage106() ->> 'in_backup')::int = array_length(public._backup_tables(),1)
  and (backup_coverage106() ->> 'tables')::int = (select count(*) from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in ('r','p') and not c.relispartition));
select tt.chk('T2 excluded tables carry a reason, included do not', not exists (select 1 from jsonb_array_elements(backup_coverage106() -> 'list') x
  where ((x ->> 'in_backup')::boolean and x -> 'reason' <> 'null'::jsonb) or (not (x ->> 'in_backup')::boolean and (x ->> 'reason') is null)));
select tt.chk('T2 intake_proofs94 reason names secret_hash', (select x ->> 'reason' from jsonb_array_elements(backup_coverage106() -> 'list') x where x ->> 'table' = 'intake_proofs94') like '%secret_hash%');
select tt.chk('T2 perm_conflict listed as in_backup', (select (x ->> 'in_backup')::boolean from jsonb_array_elements(backup_coverage106() -> 'list') x where x ->> 'table' = 'perm_conflict'));

\echo == T3 restore drill into a scratch schema: row counts of every backed-up table match
reset role;
insert into public.perm_conflict (token_a, token_b, reason_bn, reason_mix, reason_en) values ('zz_test_a','zz_test_b','x','x','x') on conflict do nothing;
drop schema if exists scratch106 cascade; create schema scratch106;
do $d$ declare t text; n1 bigint; n2 bigint; bad text := ''; cnt int := 0; tot bigint := 0;
begin
  foreach t in array public._backup_tables() loop
    execute format('create table scratch106.%I (like public.%I including defaults)', t, t);
    execute format('insert into scratch106.%I select * from public.%I', t, t);   -- the "restore"
    execute format('select count(*) from public.%I', t) into n1; execute format('select count(*) from scratch106.%I', t) into n2;
    cnt := cnt + 1; tot := tot + n2;
    if n1 <> n2 then bad := bad || ' ' || t; end if;
  end loop;
  perform tt.chk('T3 row counts equal for all ' || cnt || ' backed-up tables (' || tot || ' rows)' || bad, bad = '' and cnt = array_length(public._backup_tables(),1));
end $d$;
select tt.chk('T3 perm_conflict row restored', (select count(*) from scratch106.perm_conflict where token_a = 'zz_test_a') = 1);
select tt.chk('T3 new-table rows were really copied (not an empty comparison)', (select count(*) from scratch106.perm_conflict) >= 10 and (select count(*) from scratch106.setup_rec_defs81) > 0);
select tt.chk('T3 journal still balances in the copy', (select coalesce(sum(debit),0) = coalesce(sum(credit),0) from scratch106.journal_lines));
drop schema scratch106 cascade;

\echo == T4 paste twice changes nothing
select md5(pg_get_functiondef('public._backup_tables()'::regprocedure)) || md5(pg_get_functiondef('public.backup_coverage106()'::regprocedure)) as h1 \gset
\i supabase/phase106.sql
select tt.chk('T4 second paste: both bodies identical', md5(pg_get_functiondef('public._backup_tables()'::regprocedure)) || md5(pg_get_functiondef('public.backup_coverage106()'::regprocedure)) = :'h1');


select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
