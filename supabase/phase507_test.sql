-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase81_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase507_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY. Phase 507 tests (Step S2: recommendations + activation guide; advisory only).
--   ORDER="phase8 ... phase79 phase507" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> 81db
--   psql -h /tmp -p 5544 -U postgres -d 81db -qAt -f supabase/phase507_test.sql | grep -E 'FAIL|RESULT'
-- Test data only, no person names. Place 1 only. Nothing needs phase506.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set p '00000000-0000-0000-0000-000000000004'
\set v '00000000-0000-0000-0000-000000000005'
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
-- the entry of one item in a list by code
create or replace function tt.rec(p_all jsonb, p_code text) returns jsonb language sql immutable as $$ select x from jsonb_array_elements(p_all->'items') x where x->>'code' = p_code $$;
create or replace function tt.chkrow(p_all jsonb, p_topic text, p_code text) returns jsonb language sql immutable as $$
  select c from jsonb_array_elements(p_all->'topics') t, jsonb_array_elements(t->'checks') c where t->>'topic' = p_topic and c->>'code' = p_code $$;
create or replace function tt.flow(p_all jsonb, p_code text) returns jsonb language sql immutable as $$ select c from jsonb_array_elements(p_all->'checks') c where c->>'code' = p_code $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'p','sales4@s.app','{"full_name":"Sales"}'), (:'v','costview5@s.app','{"full_name":"Viewer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'p','salesperson'),(:'v','management') on conflict do nothing;
insert into user_locations values (:'s',1),(:'p',1),(:'v',1) on conflict do nothing;
insert into user_grants (user_id, grant_code) values (:'v','view_cost');

select count(*) as rules0 from rules where value is not null \gset
select count(*) as audit0 from audit_log \gset

\echo == T0 shape, privileges, defaults untouched
select tt.chk('T0 phase81 changes no rule value (no rule has an own value after the paste)', :rules0 = 0);
select tt.chk('T0 tables: RLS on, browsers cannot write', (select bool_and(relrowsecurity) from pg_class where relname in ('setup_rec_defs81','setup_check_defs81','setup_topic_defs81','setup_apply_batches81','setup_apply_lines81'))
  and not has_table_privilege('authenticated','public.setup_rec_defs81','insert') and not has_table_privilege('authenticated','public.setup_apply_batches81','insert')
  and not has_table_privilege('authenticated','public.setup_apply_lines81','update') and not has_table_privilege('authenticated','public.setup_check_defs81','update'));
select tt.chk('T0 functions: anon has no access, authenticated has the five public ones, the helpers stay closed',
  not has_function_privilege('anon','public.setup_recommendations()','execute') and not has_function_privilege('anon','public.setup_recommend_apply(uuid,text[],boolean,boolean)','execute')
  and has_function_privilege('authenticated','public.setup_recommendations()','execute') and has_function_privilege('authenticated','public.setup_recommend_apply(uuid,text[],boolean,boolean)','execute')
  and has_function_privilege('authenticated','public.setup_readiness(text)','execute') and has_function_privilege('authenticated','public.setup_flow_check()','execute')
  and has_function_privilege('authenticated','public.setup_apply_history(int)','execute') and not has_function_privilege('authenticated','public._setup_chk81(text)','execute'));
select tt.chk('T0 every shipped rule of phases 72..79 has a row in the list (data-driven table)',
  (select count(*) from rules where key in ('production_requires_cost','recipe_approval_required','recipe_self_approve','artisan_self_view','cost_gap_warn_pct','yield_variance_warn_pct','production_manual_needs_reason','cost_rule_self_approve','cost_attrib_in_pl',
     'inbox_on','meta_intake_on','web_form_on','web_form_captcha_on','web_form_rate_max','web_form_rate_window_min','inbox_autodraft_on','inbox_pii_guard_on','inbox_silence_hours','intake_max_tries','intake_retry_min','web_form_public_url',
     'online_pack_warn_on','online_pack_reserve_on','online_keep_order_price')) = 24
  and (select count(*) from setup_rec_defs81 d where d.rule_key in (select key from rules) and d.phase between '72' and '79') >= 24);

\echo == T1 who may read / apply
select tt.as(:'p'); set role authenticated;
select tt.err('T1 a salesperson cannot read the recommendations', 'select setup_recommendations()', 'not allowed');
select tt.err('T1 a salesperson cannot read readiness', 'select setup_readiness()', 'not allowed');
select tt.err('T1 a salesperson cannot read the flow check', 'select setup_flow_check()', 'not allowed');
select tt.as(:'s');
select tt.err('T1 a showroom manager cannot read the recommendations', 'select setup_recommendations()', 'not allowed');
select tt.as(:'v');
select tt.chk('T1 a person who may see cost can read, but cannot apply', (setup_recommendations()->>'can_apply')::boolean = false);
select tt.err('T1 view-cost person cannot apply', 'select setup_recommend_apply(gen_random_uuid())', 'not allowed');
select tt.err('T1 view-cost person cannot read the owner trail', 'select setup_apply_history()', 'not allowed');
select tt.as(:'o');
select tt.err('T1 apply needs a client id (idempotency)', 'select setup_recommend_apply(null)', 'client_id_required');
reset role;

\echo == T2 the list: statuses on a fresh database
select tt.as(:'o'); set role authenticated;
select setup_recommendations()::text as r1 \gset
reset role;
select tt.chk('T2 advisory flag, owner can apply, all list rows present', (:'r1'::jsonb->>'advisory')::boolean and (:'r1'::jsonb->>'can_apply')::boolean and (:'r1'::jsonb->'summary'->>'total')::int = (select count(*) from setup_rec_defs81 where active));
select tt.chk('T2 production_requires_cost: default warn, recommended refuse -> status recommended; no unknown ingredient yet so ready',
  tt.rec(:'r1'::jsonb,'production_requires_cost')->>'status' = 'recommended' and tt.rec(:'r1'::jsonb,'production_requires_cost')->>'recommended' = 'refuse' and tt.rec(:'r1'::jsonb,'production_requires_cost')->>'current' = 'warn'
  and (tt.rec(:'r1'::jsonb,'production_requires_cost')->>'ready')::boolean);
select tt.chk('T2 meta_intake_on: default false = recommended false -> ok (stays off until the connection exists)', tt.rec(:'r1'::jsonb,'meta_intake_on')->>'status' = 'ok');
select tt.chk('T2 inbox_on: recommended true but not ready (no sales channel yet)', tt.rec(:'r1'::jsonb,'inbox_on')->>'status' = 'recommended' and not (tt.rec(:'r1'::jsonb,'inbox_on')->>'ready')::boolean
  and tt.rec(:'r1'::jsonb,'inbox_on')->'ready_issues'->0->>'code' = 'onl_channels');
select tt.chk('T2 numbers get NO recommended value (info), with the shipped default and range shown',
  tt.rec(:'r1'::jsonb,'web_form_rate_max')->>'status' = 'info' and tt.rec(:'r1'::jsonb,'web_form_rate_max')->'recommended' = 'null'::jsonb and (tt.rec(:'r1'::jsonb,'web_form_rate_max')->>'default')::numeric = 10
  and (tt.rec(:'r1'::jsonb,'web_form_rate_max')->>'max')::numeric = 1000 and tt.rec(:'r1'::jsonb,'cost_gap_warn_pct')->>'status' = 'info');
select tt.chk('T2 accounting_on: recommended true but not ready (start date, opening ... missing)', tt.rec(:'r1'::jsonb,'accounting_on')->>'status' = 'recommended' and not (tt.rec(:'r1'::jsonb,'accounting_on')->>'ready')::boolean
  and jsonb_array_length(tt.rec(:'r1'::jsonb,'accounting_on')->'ready_issues') = 2);
select tt.chk('T2 every row has bn / mix / en reason', (select bool_and(coalesce(x->>'reason_bn','')<>'' and coalesce(x->>'reason_mix','')<>'' and coalesce(x->>'reason_en','')<>'') from jsonb_array_elements(:'r1'::jsonb->'items') x));
select tt.chk('T2 reading changed nothing (no rule value, no audit row)', (select count(*) from rules where value is not null)=0 and (select count(*) from audit_log)=:audit0);

\echo == T3 one-tap apply
select tt.as(:'o'); set role authenticated;
select setup_recommend_apply('11111111-1111-1111-1111-111111111101', array['online_pack_warn_on','inbox_on','web_form_rate_max','meta_intake_on','no_such_code']) as a1 \gset
reset role;
select tt.chk('T3 pack_warn applied; inbox_on skipped not_ready; number skipped no_recommendation; already-right skipped; unknown code ignored',
  (:'a1'::jsonb->>'count')::int = 1 and :'a1'::jsonb->'applied'->0->>'code' = 'online_pack_warn_on'
  and (select count(*) from jsonb_array_elements(:'a1'::jsonb->'skipped') x where (x->>'code','x') in (('inbox_on','x')) and x->>'reason'='not_ready')=1
  and (select count(*) from jsonb_array_elements(:'a1'::jsonb->'skipped') x where x->>'code'='web_form_rate_max' and x->>'reason'='no_recommendation')=1
  and (select count(*) from jsonb_array_elements(:'a1'::jsonb->'skipped') x where x->>'code'='meta_intake_on' and x->>'reason'='already')=1);
select tt.chk('T3 the rule is really on, inbox untouched', rule_on('online_pack_warn_on') and not rule_on('inbox_on'));
select tt.chk('T3 trail: batch + line (old = null = was on its default) and audit rows (rules trigger + setup_apply)',
  (select count(*) from setup_apply_batches81)=1 and (select count(*) from setup_apply_lines81 where code='online_pack_warn_on' and old_value is null and new_value='true'::jsonb and not overwrote)=1
  and exists (select 1 from audit_log where action='setup_apply' and record_id='11111111-1111-1111-1111-111111111101')
  and exists (select 1 from audit_log where table_name='rules' and record_id='online_pack_warn_on'));
set role authenticated; select tt.as(:'o');
select setup_recommend_apply('11111111-1111-1111-1111-111111111101', array['online_pack_warn_on','inbox_on']) as a1b \gset
reset role;
select tt.chk('T3 same client id again: answered from the trail (dup), nothing written twice', (:'a1b'::jsonb->>'dup')::boolean and (select count(*) from setup_apply_batches81)=1 and (select count(*) from setup_apply_lines81)=1);
select tt.err('T3 the trail cannot be rewritten', 'update setup_apply_lines81 set new_value = ''false''::jsonb', 'append_only');
select tt.err('T3 the trail cannot be deleted', 'delete from setup_apply_batches81', 'append_only');

\echo == T4 never over the owner's own choice
select tt.as(:'o'); set role authenticated;
select set_rule('online_keep_order_price','false') is null as own1 \gset
select set_rule('recipe_approval_required','"on"') is null as own2 \gset
select setup_recommendations()::text as r2 \gset
select tt.chk('T4 owner_chosen is shown', tt.rec(:'r2'::jsonb,'online_keep_order_price')->>'status'='owner_chosen' and (tt.rec(:'r2'::jsonb,'online_keep_order_price')->>'owner_chosen')::boolean and tt.rec(:'r2'::jsonb,'recipe_approval_required')->>'status'='owner_chosen');
select setup_recommend_apply('11111111-1111-1111-1111-111111111102') as a2 \gset
select tt.chk('T4 apply-all leaves both owner choices alone', not rule_on('online_keep_order_price') and rule_txt('recipe_approval_required')='on'
  and (select count(*) from jsonb_array_elements(:'a2'::jsonb->'skipped') x where x->>'reason'='owner_chosen')>=2);
select setup_recommend_apply('11111111-1111-1111-1111-111111111103', null, true) as a3 \gset
select tt.chk('T4 overwrite=true WITHOUT naming codes still changes no owner choice', not rule_on('online_keep_order_price') and rule_txt('recipe_approval_required')='on');
select setup_recommend_apply('11111111-1111-1111-1111-111111111104', array['online_keep_order_price'], true) as a4 \gset
reset role;
select tt.chk('T4 overwrite=true + the code named: replaced, and the trail says overwrote with the old value', rule_on('online_keep_order_price') and rule_txt('recipe_approval_required')='on'
  and (select count(*) from setup_apply_lines81 where code='online_keep_order_price' and overwrote and old_value='false'::jsonb and new_value='true'::jsonb)=1);
select tt.chk('T4 the other applies (apply-all with no readiness issue) took the remaining safe recommendations', rule_on('online_pack_warn_on') and rule_on('production_manual_needs_reason') and rule_on('inbox_pii_guard_on') and not rule_on('inbox_autodraft_on'));
select tt.chk('T4 not-ready rows still not applied by apply-all (inbox, accounting_on, cost_attrib_in_pl)', not rule_on('inbox_on') and not rule_on('accounting_on') and not rule_on('cost_attrib_in_pl'));
select tt.chk('T4 production_requires_cost was applied (nothing unknown) to refuse', rule_txt('production_requires_cost')='refuse');
set role authenticated; select tt.as(:'o');
select setup_recommend_apply('11111111-1111-1111-1111-111111111105', array['inbox_on'], false, true) as a5 \gset
select setup_apply_history(5) as h1 \gset
reset role;
select tt.chk('T4 ignore_ready=true applies a not-ready row (the owner decides); history lists the batches newest first', rule_on('inbox_on') and jsonb_array_length(:'h1'::jsonb) = 5 and :'h1'::jsonb->0->>'client_id' = '11111111-1111-1111-1111-111111111105');

\echo == T5 readiness: stock tracking
select tt.as(:'o'); set role authenticated;
select setup_readiness('stock_tracking')::text as q1 \gset
reset role;
select tt.chk('T5 empty: no item tracked -> problem 1', (tt.chkrow(:'q1'::jsonb,'stock_tracking','stk_tracked')->>'problems')::int = 1 and not (:'q1'::jsonb->'topics'->0->>'ready')::boolean);
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price, sell_units) values
 ('A1','A1','A1','kg','kg','finished_good',true,100, array['kg','box']), ('B1','B1','B1','kg','kg','finished_good',true,100,'{}'), ('C1','C1','C1','kg',null,'finished_good',true,100,'{}');
select id as ia from items where code='A1' \gset
select id as ib from items where code='B1' \gset
select id as ic from items where code='C1' \gset
set role authenticated; select tt.as(:'o');
select setup_readiness('stock_tracking')::text as q2 \gset
reset role;
select tt.chk('T5 3 tracked: none has an opening yet -> 3; one without base unit -> 1; A1 sells in box with no conversion -> 1',
  (tt.chkrow(:'q2'::jsonb,'stock_tracking','stk_opening')->>'problems')::int = 3 and (tt.chkrow(:'q2'::jsonb,'stock_tracking','stk_unit')->>'problems')::int = 1
  and (tt.chkrow(:'q2'::jsonb,'stock_tracking','stk_conv')->>'problems')::int = 1 and (tt.chkrow(:'q2'::jsonb,'stock_tracking','stk_tracked')->>'ok')::boolean);
set role authenticated; select tt.as(:'o');
select stock_opening(:'ia'::uuid, 1, 10, 5, null, 'seed', gen_random_uuid()) is not null as op1 \gset
select stock_opening(:'ib'::uuid, 1, 10, null, null, 'seed', gen_random_uuid()) is not null as op2 \gset
select setup_readiness('stock_tracking')::text as q3 \gset
reset role;
select tt.chk('T5 two opened -> 1 left; B1 has stock but no cost -> 1 unknown cost (counts only)', (tt.chkrow(:'q3'::jsonb,'stock_tracking','stk_opening')->>'problems')::int = 1 and (tt.chkrow(:'q3'::jsonb,'stock_tracking','stk_cost')->>'problems')::int = 1);
select tt.chk('T5 cost secrecy: the readiness answer carries no cost value or cost column', :'q3'::text !~* 'avg_cost|cost_price|unit_cost');
update stock_balance set qty = -1 where item_id = :'ib'::uuid and location_id = 1;
set role authenticated; select tt.as(:'o');
select setup_readiness('stock_tracking')::text as q4 \gset
reset role;
select tt.chk('T5 negative balance shows', (tt.chkrow(:'q4'::jsonb,'stock_tracking','stk_neg')->>'problems')::int = 1);
update stock_balance set qty = 10 where item_id = :'ib'::uuid and location_id = 1;

\echo == T6 readiness: accounting
set role authenticated; select tt.as(:'o');
select setup_readiness('accounting')::text as w1 \gset
reset role;
select tt.chk('T6 no start date, no opening entry; chart and mappings present', (tt.chkrow(:'w1'::jsonb,'accounting','acc_start')->>'problems')::int = 1 and (tt.chkrow(:'w1'::jsonb,'accounting','acc_opening')->>'problems')::int = 1
  and (tt.chkrow(:'w1'::jsonb,'accounting','acc_coa')->>'ok')::boolean and (tt.chkrow(:'w1'::jsonb,'accounting','acc_map')->>'ok')::boolean and not (:'w1'::jsonb->'topics'->0->>'ready')::boolean);
select a.id as payacc from acct_mappings m join coa_accounts a on a.id = m.account_id where m.key = 'pay_cash' \gset
update coa_accounts set active = false where id = :payacc;
set role authenticated; select tt.as(:'o');
select setup_readiness('accounting')::text as w2 \gset
reset role;
select tt.chk('T6 a missing mapping is counted', (tt.chkrow(:'w2'::jsonb,'accounting','acc_map')->>'problems')::int = 1);
update coa_accounts set active = true where id = :payacc;
select set_rule('accounting_start_date','"2026-10-01"') is null as sd \gset
set role authenticated; select tt.as(:'o');
select set_rule('accounting_start_date','"2026-10-01"') is null as sd2 \gset
select setup_readiness('accounting')::text as w3 \gset
reset role;
select tt.chk('T6 start date set -> that check is clean', (tt.chkrow(:'w3'::jsonb,'accounting','acc_start')->>'ok')::boolean);

\echo == T7 readiness: production and costing
insert into recipes (item_id, version, yield_qty, yield_unit, active) values (:'ia'::uuid, 1, 5, 'kg', true);
select id as rc from recipes limit 1 \gset
insert into recipe_lines (recipe_id, ingredient_item_id, qty, unit, sort, active) values (:'rc'::uuid, :'ib'::uuid, 2, 'kg', 1, true);
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('N1','N1','N1','kg','kg','raw_material',true,0);
select id as inn from items where code='N1' \gset
insert into recipe_lines (recipe_id, ingredient_item_id, qty, unit, sort, active) values (:'rc'::uuid, :'inn'::uuid, 1, 'kg', 2, true);
set role authenticated; select tt.as(:'o');
select setup_readiness('production')::text as pr1 \gset
reset role;
select tt.chk('T7 recipe present; not approved -> 1 (info level); ingredients: B1 has no cost, N1 has none -> 2 unknown', (tt.chkrow(:'pr1'::jsonb,'production','prd_recipes')->>'ok')::boolean
  and (tt.chkrow(:'pr1'::jsonb,'production','prd_approve')->>'problems')::int = 1 and tt.chkrow(:'pr1'::jsonb,'production','prd_approve')->>'level' = 'info'
  and (tt.chkrow(:'pr1'::jsonb,'production','prd_icost')->>'problems')::int = 2 and (tt.chkrow(:'pr1'::jsonb,'production','prd_lines')->>'ok')::boolean);
update stock_balance set qty = 10, avg_cost = 7 where item_id = :'ib'::uuid and location_id = 1;
insert into item_costs (item_id, cost_price) values (:'inn'::uuid, 3) on conflict (item_id) do update set cost_price = 3;
set role authenticated; select tt.as(:'o');
select setup_readiness('production')::text as pr2 \gset
reset role;
select tt.chk('T7 costs entered (stock avg cost / item cost) -> 0 unknown', (tt.chkrow(:'pr2'::jsonb,'production','prd_icost')->>'problems')::int = 0);
insert into location_cost_cfg (location_id, mode, normal_monthly_output) values (1, 'pool', null) on conflict (location_id) do update set mode = 'pool', normal_monthly_output = null;
set role authenticated; select tt.as(:'o');
select setup_readiness('production')::text as pr3 \gset
select setup_flow_check()::text as fl0 \gset
reset role;
select tt.chk('T7 pool mode without a normal monthly output -> incomplete (never guessed)', (tt.chkrow(:'pr3'::jsonb,'production','prd_conv')->>'problems')::int = 1);
select tt.chk('T7 pool mode with no figures this month shows in the flow check', tt.flow(:'fl0'::jsonb,'flw_pool')->>'level' = 'warn');
update location_cost_cfg set mode = 'off' where location_id = 1;

\echo == T8 readiness: cost sources and online
set role authenticated; select tt.as(:'o');
select setup_readiness()::text as all1 \gset
reset role;
select tt.chk('T8 all five topics are listed; cost sources empty -> info problem; channels empty -> warn', jsonb_array_length(:'all1'::jsonb->'topics') = 5
  and (tt.chkrow(:'all1'::jsonb,'cost_sources','cs_sources')->>'problems')::int = 1 and (tt.chkrow(:'all1'::jsonb,'online','onl_channels')->>'problems')::int = 1);
select tt.chk('T8 web form url check does not apply while the web form is off; meta bot likewise', not (tt.chkrow(:'all1'::jsonb,'online','onl_url')->>'applies')::boolean and not (tt.chkrow(:'all1'::jsonb,'online','onl_bot')->>'applies')::boolean);
select set_rule('web_form_on','true') is null as wf \gset
set role authenticated; select tt.as(:'o');
select set_rule('web_form_on','true') is null as wf2 \gset
select setup_readiness('online')::text as on1 \gset
reset role;
select tt.chk('T8 web form on with no public URL -> flagged (needs the outside setup)', (tt.chkrow(:'on1'::jsonb,'online','onl_url')->>'problems')::int = 1);
select tt.chk('T8 an unknown topic returns an empty list, no error', (select jsonb_array_length(setup_readiness('nope')->'topics')) = 0);

\echo == T9 flow checks (post-activation)
set role authenticated; select tt.as(:'o');
select setup_flow_check()::text as f1 \gset
reset role;
select tt.chk('T9 systems that are off show na (accounting off, online orders off)', tt.flow(:'f1'::jsonb,'flw_acc_old')->>'level' = 'na' and tt.flow(:'f1'::jsonb,'flw_oo_flags')->>'level' = 'na');
-- inbox is on (T4). A channel + an old unseen message + a failed intake
insert into sales_channels (code, kind, name_bn, location_id, active) values ('ph81','phone','Phone',1,true) on conflict do nothing;
select id as chid from sales_channels where code='ph81' \gset
insert into inbound_messages (channel_id, location_id, external_id, msg_text, msg_time, received_at, status) values (:chid, 1, 'x81', 'hi', now() - interval '3 days', now() - interval '3 days', 'new');
insert into intake_failures (kind, state, error) values ('message','failed','test');
set role authenticated; select tt.as(:'o');
select setup_flow_check()::text as f2 \gset
reset role;
select tt.chk('T9 an unseen message from an earlier day -> warn; a failed intake -> warn', tt.flow(:'f2'::jsonb,'flw_inbox_new')->>'level' = 'warn' and (tt.flow(:'f2'::jsonb,'flw_inbox_new')->>'problems')::int = 1
  and tt.flow(:'f2'::jsonb,'flw_intake_fail')->>'level' = 'warn');
select tt.chk('T9 silence check: last message 3 days ago > 24 h default -> warn', tt.flow(:'f2'::jsonb,'flw_inbox_silent')->>'level' = 'warn');
update inbound_messages set status = 'seen' where external_id = 'x81';
update intake_failures set state = 'done';
insert into inbound_messages (channel_id, location_id, external_id, msg_text, msg_time, received_at, status) values (:chid, 1, 'x82', 'hi', now(), now(), 'seen');
set role authenticated; select tt.as(:'o');
select setup_flow_check()::text as f3 \gset
reset role;
select tt.chk('T9 handled and recent -> ok', tt.flow(:'f3'::jsonb,'flw_inbox_new')->>'level' = 'ok' and tt.flow(:'f3'::jsonb,'flw_intake_fail')->>'level' = 'ok' and tt.flow(:'f3'::jsonb,'flw_inbox_silent')->>'level' = 'ok');
update stock_balance set qty = -2 where item_id = :'ib'::uuid and location_id = 1;
set role authenticated; select tt.as(:'o');
select setup_flow_check()::text as f4 \gset
reset role;
select tt.chk('T9 negative stock shows in the flow check; production flow n/a-or-ok with no run', tt.flow(:'f4'::jsonb,'flw_neg')->>'level' = 'warn' and tt.flow(:'f4'::jsonb,'flw_prod_cost')->>'level' = 'ok');
update stock_balance set qty = 10 where item_id = :'ib'::uuid and location_id = 1;

\echo == T10 flow: accounting on (a sale dated earlier is not in the books -> warn; after posting -> ok)
set role authenticated; select tt.as(:'o');
select set_rule('accounting_on','true') is null as acc1 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'ia')::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)->>'id' as sa \gset
reset role;
update sales set sale_date = sale_date - 3 where id = :'sa'::uuid;
set role authenticated; select tt.as(:'o');
select setup_flow_check()::text as g1 \gset
reset role;
select tt.chk('T10 accounting on: the earlier-dated sale is waiting -> flw_acc_old warn n=1', tt.flow(:'g1'::jsonb,'flw_acc_old')->>'level' = 'warn' and (tt.flow(:'g1'::jsonb,'flw_acc_old')->>'problems')::int >= 1);
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) is not null as pp \gset
select setup_flow_check()::text as g2 \gset
reset role;
select tt.chk('T10 after posting the pending list: ok, no errors', tt.flow(:'g2'::jsonb,'flw_acc_old')->>'level' = 'ok' and tt.flow(:'g2'::jsonb,'flw_acc_err')->>'level' = 'ok');

\echo == T11 data-driven: a later phase adds its rule by INSERT only
insert into rules (key, module, kind, default_value, label_bn, label_mix, label_en, sort) values ('zz_s1_test', 'stock', 'switch', 'false', 'পরীক্ষা', 'Test', 'Test rule', 9999) on conflict do nothing;
insert into setup_rec_defs81 (code, rule_key, phase, module, rec_value, reason_bn, reason_mix, reason_en, sort) values
 ('zz_s1_test', 'zz_s1_test', '80', 'stock', 'true', 'কারণ', 'কারণ', 'A reason', 9999), ('zz_missing', 'zz_not_there', '80', 'stock', 'true', 'কারণ', 'কারণ', 'A reason', 9998) on conflict do nothing;
set role authenticated; select tt.as(:'o');
select setup_recommendations()::text as r3 \gset
select setup_recommend_apply('11111111-1111-1111-1111-111111111106', array['zz_s1_test','zz_missing']) as a6 \gset
reset role;
select tt.chk('T11 new row appears as recommended; a row whose rule does not exist is not_installed (no error)', tt.rec(:'r3'::jsonb,'zz_s1_test')->>'status'='recommended' and tt.rec(:'r3'::jsonb,'zz_missing')->>'status'='not_installed');
select tt.chk('T11 one-tap apply works for the new row and skips the missing one', rule_on('zz_s1_test') and (select count(*) from jsonb_array_elements(:'a6'::jsonb->'skipped') x where x->>'code'='zz_missing' and x->>'reason'='not_installed')=1);

\echo == T12 language rule: English strings have no Bangla characters, every text exists in 3 modes
select tt.chk('T12 English texts of the guide contain no Bangla character',
  not exists (select 1 from setup_rec_defs81 where reason_en ~ '[ঀ-৿]' or reason_mix is null)
  and not exists (select 1 from setup_check_defs81 where label_en ~ '[ঀ-৿]' or coalesce(fix_en,'') ~ '[ঀ-৿]')
  and not exists (select 1 from setup_topic_defs81 where label_en ~ '[ঀ-৿]'));
select tt.chk('T12 the function answers carry the English strings too, with no Bangla in them', (select not bool_or(coalesce(x->>'reason_en','') ~ '[ঀ-৿]') from jsonb_array_elements(:'r3'::jsonb->'items') x)
  and (select not bool_or(coalesce(x->>'label_en','') ~ '[ঀ-৿]') from jsonb_array_elements(:'all1'::jsonb->'topics') t, jsonb_array_elements(t->'checks') x));
select tt.chk('T12 bn / mix texts exist for every check and topic', not exists (select 1 from setup_check_defs81 where coalesce(label_bn,'')='' or coalesce(label_mix,'')='') and not exists (select 1 from setup_topic_defs81 where coalesce(label_mix,'')=''));

\echo == T13 advisory only: nothing the guide does blocks an operation
select tt.chk('T13 no trigger or policy of the guide sits on an operational table', not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid where p.proname like '%81' and not t.tgisinternal and t.tgrelid::regclass::text not like 'setup_%'));
set role authenticated; select tt.as(:'p');
select tt.chk('T13 a salesperson still sells while the guide shows warnings and refuses to answer him', (record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'ia')::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)->>'id') is not null);
reset role;

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
