-- FRESH DB ONLY. Phase 101 tests (Step Rec: the setup advisor covers every rule / switch added in phases 508..98).
--   Build: bash tests/sql/final_build.sh <db> "<canonical order ... phase524 phase101>"   (phase101 pasted last; docs/PASTE_ORDER.md)
--   Run from the REPO ROOT (the key list is read from supabase/phase508..97.sql by tests/sql/rec_keys.py; the last block pastes phase101.sql again):
--     psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase101_test.sql | grep -E "FAIL|RESULT"
--   FAILING-BEFORE: on a build WITHOUT phase101 the coverage / row / apply blocks fail (no rows). PASSING-AFTER: 0 fail. Test data only, no real names.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
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
create or replace function tt.rec(p_all jsonb, p_code text) returns jsonb language sql immutable as $$ select x from jsonb_array_elements(p_all->'items') x where x->>'code' = p_code $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'p','sales4@s.app','{"full_name":"Sales"}'), (:'v','costview5@s.app','{"full_name":"Viewer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'p','salesperson'),(:'v','management') on conflict do nothing;
insert into user_locations values (:'p',1),(:'v',1) on conflict do nothing;
insert into user_grants (user_id, grant_code) values (:'v','view_cost');

-- the rule keys the step reports list, read from the phase files (not typed here)
create table tt.keys101 (ph int, k text);
\copy tt.keys101 from program 'python3 tests/sql/rec_keys.py' csv
create table tt.new101 as select d.* from setup_rec_defs81 d where d.sort >= 300 and d.phase <> '109';
select count(*) as rules0 from rules where value is not null \gset
select count(*) as audit0 from audit_log \gset

\echo == T0 coverage: every rule key of phases 508..97 has a row
select tt.chk('T0 the extractor found the rules of the phase files (48 keys, 12 phases)', (select count(*) from tt.keys101) = 48 and (select count(distinct ph) from tt.keys101) = 12);
select tt.chk('T0 every one of those rule keys exists in rules', not exists (select 1 from tt.keys101 k where not exists (select 1 from rules r where r.key = k.k)));
select tt.chk('T0 every one of those rule keys has an active row in setup_rec_defs81 (code = key)', not exists (select 1 from tt.keys101 k where not exists (select 1 from setup_rec_defs81 d where d.rule_key = k.k and d.active)));
select tt.chk('T0 the row carries the phase of the file that added the rule', not exists (select 1 from tt.keys101 k join setup_rec_defs81 d on d.rule_key = k.k where d.phase <> k.ph::text and d.phase <> '94'));
select tt.chk('T0 phase101 added 43 rows (48 keys - 6 already listed by phase94 + stock_negative_mode) and no key has two rows', (select count(*) from tt.new101) = 43
  and (select count(*) from (select rule_key from setup_rec_defs81 group by 1 having count(*) > 1) z) = 0);
select tt.chk('T0 the 38 older rows (phase81 / phase94) are exactly as shipped', (select count(*) from setup_rec_defs81 where sort < 300) = 38
  and (select md5(string_agg(d::text, '|' order by code)) from setup_rec_defs81 d where sort < 300) = '51db4ae0bd2cc5437ed66f808ec5d25d');
select tt.chk('T0 no rule of phase99 / phase100 got a row here (Opt and Cat add their own)', not exists (select 1 from tt.new101 where phase in ('99', '100')));
select tt.chk('T0 phase101 changes no rule value, tables and rules keep their shape', :rules0 = 0 and (select count(*) from rules where key in (select k from tt.keys101)) = 48);
select tt.chk('T0 no function is created by phase101 (the three-function advisor is as phase81 shipped it: tags present, no bos101 body)',
  position('bos101' in pg_get_functiondef('public.setup_recommendations()'::regprocedure)) = 0 and position('bos101' in pg_get_functiondef('public.setup_recommend_apply(uuid,text[],boolean,boolean)'::regprocedure)) = 0
  and not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and prosrc like '%bos101%'));

\echo == T1 each recommended value is a valid value of its rule
select tt.chk('T1 recommended switch = boolean, choice = one of rules.choices, number = inside min..max, text = string',
  not exists (select 1 from tt.new101 d join rules r on r.key = d.rule_key where d.rec_value is not null and not (
     (r.kind = 'switch' and jsonb_typeof(d.rec_value) = 'boolean') or (r.kind = 'choice' and r.choices @> jsonb_build_array(d.rec_value #>> '{}'))
     or (r.kind = 'number' and jsonb_typeof(d.rec_value) = 'number' and (d.rec_value #>> '{}')::numeric between coalesce(r.min_value, 0) and coalesce(r.max_value, 1000000000))
     or (r.kind = 'text' and jsonb_typeof(d.rec_value) = 'string'))));
select tt.chk('T1 owner-typed numbers, dates and currencies get NO recommended value (all number / text rules among the 48 keys are info rows)',
  (select count(*) from rules r join tt.keys101 k on k.k = r.key where r.kind in ('number', 'text')) = 12
  and not exists (select 1 from rules r join tt.keys101 k on k.k = r.key join setup_rec_defs81 d on d.rule_key = r.key where r.kind in ('number', 'text') and d.rec_value is not null));
select tt.chk('T1 no JSON null is stored as a recommendation (null means info)', not exists (select 1 from setup_rec_defs81 where rec_value = 'null'::jsonb));
select tt.chk('T1 where a rule has a shipped choice list the recommended value is never the "off / as before" word for a SAFETY rule that would weaken it',
  not exists (select 1 from tt.new101 where rule_key in ('purchase_void_guard', 'unit_conv_required', 'production_negative_reason', 'expiry_sale_guard', 'manual_journal_guard') and rec_value in ('"off"'::jsonb, '"allow"'::jsonb, '"void"'::jsonb)));
select tt.chk('T1 the example from the owner: pos_show_invoice_after_sale is recommended always', (select rec_value from setup_rec_defs81 where code = 'pos_show_invoice_after_sale') = '"always"'::jsonb
  and (select default_value from rules where key = 'pos_show_invoice_after_sale') = '"never"'::jsonb);
select tt.chk('T1 the switches that would double count or post a backlog are never recommended ON blindly: acct_stock_opening recommended OFF; backlog switches need accounting basics',
  (select rec_value from setup_rec_defs81 where code = 'acct_stock_opening') = 'false'::jsonb
  and not exists (select 1 from tt.new101 where code in ('acct_count_adjust', 'acct_issue_out', 'acct_purchase_variance') and not (ready_checks @> '{acc_start,acc_coa,acc_map}'::text[])));
select tt.chk('T1 every ready check named by a new row exists and is active', not exists (select 1 from tt.new101 d, unnest(d.ready_checks) c where not exists (select 1 from setup_check_defs81 x where x.code = c and x.active)));

\echo == T2 language rule
select tt.chk('T2 all three reasons filled', not exists (select 1 from tt.new101 where coalesce(reason_bn, '') = '' or coalesce(reason_mix, '') = '' or coalesce(reason_en, '') = ''));
select tt.chk('T2 English reason has NO Bangla letter (English mode is all English)', not exists (select 1 from tt.new101 where reason_en ~ '[ঀ-৿]'));
select tt.chk('T2 Bangla and mixed reasons are Bangla text (common words may stay English)', not exists (select 1 from tt.new101 where reason_bn !~ '[ঀ-৿]' or reason_mix !~ '[ঀ-৿]'));
select tt.chk('T2 the English reason is a real sentence (not a copy of the Bangla)', not exists (select 1 from tt.new101 where length(reason_en) < 40 or reason_en = reason_bn));

\echo == T3 the owner reads the list: statuses on a fresh database
select tt.as(:'o'); set role authenticated;
select setup_recommendations()::text as r1 \gset
reset role;
select tt.chk('T3 total = all active rows (81) and the new rows are in the output', (:'r1'::jsonb->'summary'->>'total')::int = (select count(*) from setup_rec_defs81 where active)
  and (select count(*) from tt.new101 d where tt.rec(:'r1'::jsonb, d.code) is not null) = 43);
select tt.chk('T3 none of the 48 keys shows not_installed', not exists (select 1 from tt.keys101 k where tt.rec(:'r1'::jsonb, k.k)->>'status' = 'not_installed' or tt.rec(:'r1'::jsonb, k.k) is null));
select tt.chk('T3 pos_show_invoice_after_sale: current never -> recommended always, status recommended, ready, one tap',
  tt.rec(:'r1'::jsonb,'pos_show_invoice_after_sale')->>'status' = 'recommended' and tt.rec(:'r1'::jsonb,'pos_show_invoice_after_sale')->>'recommended' = 'always'
  and tt.rec(:'r1'::jsonb,'pos_show_invoice_after_sale')->>'current' = 'never' and (tt.rec(:'r1'::jsonb,'pos_show_invoice_after_sale')->>'ready')::boolean
  and tt.rec(:'r1'::jsonb,'pos_show_invoice_after_sale')->>'rule_label_en' is not null and tt.rec(:'r1'::jsonb,'pos_show_invoice_after_sale')->>'reason_en' like '%Print, Email, SMS and WhatsApp%');
select tt.chk('T3 defaults already right show ok (acct_stock_opening off, report_cost_source, landed_alloc_default, cash_drawer_when)',
  tt.rec(:'r1'::jsonb,'acct_stock_opening')->>'status' = 'ok' and tt.rec(:'r1'::jsonb,'report_cost_source')->>'status' = 'ok'
  and tt.rec(:'r1'::jsonb,'landed_alloc_default')->>'status' = 'ok' and tt.rec(:'r1'::jsonb,'cash_drawer_when')->>'status' = 'ok' and tt.rec(:'r1'::jsonb,'cash_drawer_no_sale_requires_reason')->>'status' = 'ok');
select tt.chk('T3 numbers: info, recommended null, the shipped default and the allowed range come with the row',
  tt.rec(:'r1'::jsonb,'transit_open_hours')->>'status' = 'info' and tt.rec(:'r1'::jsonb,'transit_open_hours')->'recommended' = 'null'::jsonb
  and (tt.rec(:'r1'::jsonb,'transit_open_hours')->>'min')::numeric = 1 and (tt.rec(:'r1'::jsonb,'transit_open_hours')->>'max')::numeric = 8760
  and (tt.rec(:'r1'::jsonb,'acct_pending_alert_days')->>'default')::numeric = 1 and (tt.rec(:'r1'::jsonb,'acct_pending_alert_days')->>'max')::numeric = 365
  and (tt.rec(:'r1'::jsonb,'scan_min_confidence')->>'default')::numeric = 0.6 and (tt.rec(:'r1'::jsonb,'scan_min_confidence')->>'max')::numeric = 1
  and (tt.rec(:'r1'::jsonb,'acct_cost_wait_alert_days')->>'max')::numeric = 3650 and (tt.rec(:'r1'::jsonb,'landed_reminder_days')->>'default')::numeric = 30);
select tt.chk('T3 no number rule is recommended anywhere in the list (status info, recommended null, for every kind number row)',
  not exists (select 1 from jsonb_array_elements(:'r1'::jsonb->'items') x where x->>'kind' = 'number' and (x->>'status' <> 'info' or x->'recommended' <> 'null'::jsonb)));
select tt.chk('T3 text rules and the choices that depend on the shop (grn source, 05-1, transfer mode, drawer, landed mode) are info rows',
  (select bool_and(tt.rec(:'r1'::jsonb, c)->>'status' = 'info') from unnest(array['purchase_grn_guard','form_051_mode','acct_transfer_mode','acct_transit_loss','acct_stock_moves_from','acct_scheduler_on','telegram_intake_on',
     'cash_drawer_mode','cash_drawer_method','landed_cost_mode','landed_cost_requires_approval','landed_reminder_on','landed_base_currency','stock_negative_mode']) c));
select tt.chk('T3 backlog accounting switches are recommended but NOT ready on a fresh database (no accounting start / chart / mapping) and say which check fails',
  tt.rec(:'r1'::jsonb,'acct_count_adjust')->>'status' = 'recommended' and not (tt.rec(:'r1'::jsonb,'acct_count_adjust')->>'ready')::boolean
  and jsonb_array_length(tt.rec(:'r1'::jsonb,'acct_count_adjust')->'ready_issues') >= 1
  and tt.rec(:'r1'::jsonb,'acct_issue_out')->>'reason_en' like '%posts the backlog%' and tt.rec(:'r1'::jsonb,'acct_purchase_variance')->>'reason_en' like '%posts the backlog%'
  and tt.rec(:'r1'::jsonb,'acct_stock_opening')->>'reason_en' like '%counts the same stock twice%');
select tt.chk('T3 the safety choices: void guard refuse, void payments keep, expiry warn, backdate warn, double issue warn, negative reason required, transit short loss, soft stock on',
  tt.rec(:'r1'::jsonb,'purchase_void_guard')->>'recommended' = 'refuse' and tt.rec(:'r1'::jsonb,'purchase_void_payments')->>'recommended' = 'keep' and tt.rec(:'r1'::jsonb,'expiry_sale_guard')->>'recommended' = 'warn'
  and tt.rec(:'r1'::jsonb,'purchase_backdate_flag')->>'recommended' = 'warn' and tt.rec(:'r1'::jsonb,'production_double_issue_guard')->>'recommended' = 'warn'
  and tt.rec(:'r1'::jsonb,'production_negative_reason')->>'recommended' = 'required' and tt.rec(:'r1'::jsonb,'transit_short_mode')->>'recommended' = 'loss'
  and tt.rec(:'r1'::jsonb,'offline_soft_stock')->>'recommended' = 'true' and tt.rec(:'r1'::jsonb,'neg_grant_log')->>'recommended' = 'true' and tt.rec(:'r1'::jsonb,'manual_journal_guard')->>'recommended' = 'on');
select tt.chk('T3 reading changed nothing (no rule value, no audit row)', (select count(*) from rules where value is not null) = 0 and (select count(*) from audit_log) = :audit0);
select tt.chk('T3 every row of the list carries bn / mix / en reason and the three rule labels', (select bool_and(coalesce(x->>'reason_bn','') <> '' and coalesce(x->>'reason_mix','') <> '' and coalesce(x->>'reason_en','') <> '' and coalesce(x->>'rule_label_en','') <> '') from jsonb_array_elements(:'r1'::jsonb->'items') x where x->>'status' <> 'not_installed'));

\echo == T4 unit_conv_required becomes not ready while a tracked item has a sell unit with no conversion
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price, sell_units) values ('A1','A1','A1','kg','kg','finished_good',true,100, array['kg','box']);
select tt.as(:'o'); set role authenticated;
select setup_recommendations()::text as r2 \gset
reset role;
select tt.chk('T4 unit_conv_required: recommended refuse, not ready, the stock-tracking check "stk_conv" is named', tt.rec(:'r2'::jsonb,'unit_conv_required')->>'status' = 'recommended'
  and not (tt.rec(:'r2'::jsonb,'unit_conv_required')->>'ready')::boolean and tt.rec(:'r2'::jsonb,'unit_conv_required')->'ready_issues'->0->>'code' = 'stk_conv');
select tt.as(:'o'); set role authenticated;
select setup_recommend_apply('22222222-2222-2222-2222-222222222201', array['unit_conv_required']) as a0 \gset
reset role;
select tt.chk('T4 apply skips it as not_ready and the rule stays warn', :'a0'::jsonb->'skipped'->0->>'reason' = 'not_ready' and (:'a0'::jsonb->>'count')::int = 0 and rule_txt('unit_conv_required') = 'warn');
update items set tracked = false where code = 'A1';

\echo == T5 who may apply
select tt.as(:'v'); set role authenticated;
select tt.chk('T5 a person who may see cost reads the new rows but cannot apply', (setup_recommendations()->>'can_apply')::boolean = false and tt.rec(setup_recommendations(), 'transit_short_mode') is not null);
select tt.err('T5 view-cost person cannot apply', 'select setup_recommend_apply(gen_random_uuid(), array[''transit_short_mode''])', 'not allowed');
select tt.as(:'p');
select tt.err('T5 a salesperson cannot read', 'select setup_recommendations()', 'not allowed');
select tt.err('T5 a salesperson cannot apply', 'select setup_recommend_apply(gen_random_uuid(), array[''transit_short_mode''])', 'not allowed');
reset role;
select tt.chk('T5 nothing changed by the refused calls', (select count(*) from rules where value is not null) = 0);

\echo == T6 one-tap apply of choice / switch values (set_rule: validated, audited)
select tt.as(:'o'); set role authenticated;
select setup_recommend_apply('22222222-2222-2222-2222-222222222202', array['pos_show_invoice_after_sale','transit_short_mode','purchase_void_guard','offline_soft_stock','scan_min_confidence','acct_stock_opening','nope_code']) as a1 \gset
reset role;
select tt.chk('T6 four values applied (3 choices + 1 switch); a number is skipped no_recommendation; acct_stock_opening skipped already; unknown code ignored',
  (:'a1'::jsonb->>'count')::int = 4
  and (select count(*) from jsonb_array_elements(:'a1'::jsonb->'skipped') x where x->>'code' = 'scan_min_confidence' and x->>'reason' = 'no_recommendation') = 1
  and (select count(*) from jsonb_array_elements(:'a1'::jsonb->'skipped') x where x->>'code' = 'acct_stock_opening' and x->>'reason' = 'already') = 1);
select tt.chk('T6 the rules really changed (strings stay strings)', rule_txt('pos_show_invoice_after_sale') = 'always' and rule_txt('transit_short_mode') = 'loss' and rule_txt('purchase_void_guard') = 'refuse'
  and rule_on('offline_soft_stock') and (select value from rules where key = 'pos_show_invoice_after_sale') = '"always"'::jsonb and (select value from rules where key = 'scan_min_confidence') is null);
select tt.chk('T6 audited: setup trail lines (old = null: was on its default), setup_apply audit row and the rules audit rows by set_rule',
  (select count(*) from setup_apply_lines81 where batch_id = '22222222-2222-2222-2222-222222222202') = 4
  and (select count(*) from setup_apply_lines81 where code = 'pos_show_invoice_after_sale' and old_value is null and new_value = '"always"'::jsonb and not overwrote) = 1
  and exists (select 1 from audit_log where action = 'setup_apply' and record_id = '22222222-2222-2222-2222-222222222202')
  and (select count(*) from audit_log where table_name = 'rules' and record_id in ('pos_show_invoice_after_sale','transit_short_mode','purchase_void_guard','offline_soft_stock')) >= 4);
select tt.as(:'o'); set role authenticated;
select setup_recommendations()::text as r3 \gset
select setup_recommend_apply('22222222-2222-2222-2222-222222222202', array['pos_show_invoice_after_sale']) as a1b \gset
reset role;
select tt.chk('T6 after the apply the rows show ok; the same client id again is answered from the trail (dup), nothing written twice',
  tt.rec(:'r3'::jsonb,'pos_show_invoice_after_sale')->>'status' = 'ok' and tt.rec(:'r3'::jsonb,'transit_short_mode')->>'status' = 'ok' and (:'a1b'::jsonb->>'dup')::boolean
  and (select count(*) from setup_apply_lines81 where batch_id = '22222222-2222-2222-2222-222222222202') = 4);

\echo == T7 the owner's own value is never replaced unless he asks
select tt.as(:'o'); set role authenticated;
select set_rule('expiry_sale_guard', '"refuse"'::jsonb);
select setup_recommend_apply('22222222-2222-2222-2222-222222222203', array['expiry_sale_guard']) as a2 \gset
select setup_recommend_apply('22222222-2222-2222-2222-222222222204', array['expiry_sale_guard'], true, false) as a3 \gset
reset role;
select tt.chk('T7 owner-chosen refuse is skipped (owner_chosen) without the overwrite flag', :'a2'::jsonb->'skipped'->0->>'reason' = 'owner_chosen' and (:'a2'::jsonb->>'count')::int = 0);
select tt.chk('T7 with overwrite AND the code named it is replaced and the trail says overwrote', (:'a3'::jsonb->>'count')::int = 1 and rule_txt('expiry_sale_guard') = 'warn'
  and (select count(*) from setup_apply_lines81 where code = 'expiry_sale_guard' and overwrote and old_value = '"refuse"'::jsonb and new_value = '"warn"'::jsonb) = 1);
select tt.as(:'o'); set role authenticated;
select set_rule('expiry_sale_guard', null);
select set_rule('production_negative_reason', '"warn"'::jsonb);
reset role;

\echo == T8 apply ALL recommended: only recommended values, never a number, never a row that is not ready
select tt.as(:'o'); set role authenticated;
select setup_recommend_apply('22222222-2222-2222-2222-222222222205') as a4 \gset
reset role;
select tt.chk('T8 apply-all wrote nothing to a number or text rule', not exists (select 1 from rules where value is not null and kind in ('number', 'text')));
select tt.chk('T8 every applied line equals the recommended value of its row and its rule', not exists (select 1 from setup_apply_lines81 l join setup_rec_defs81 d on d.code = l.code where l.batch_id = '22222222-2222-2222-2222-222222222205' and l.new_value is distinct from d.rec_value)
  and (select count(*) from setup_apply_lines81 where batch_id = '22222222-2222-2222-2222-222222222205') = (:'a4'::jsonb->>'count')::int);
select tt.chk('T8 the backlog accounting switches were skipped not_ready (a fresh database has no accounting start / chart)',
  (select count(*) from jsonb_array_elements(:'a4'::jsonb->'skipped') x where x->>'code' in ('acct_count_adjust','acct_issue_out','acct_purchase_variance') and x->>'reason' = 'not_ready') = 3
  and not rule_on('acct_count_adjust') and not rule_on('acct_issue_out') and not rule_on('acct_purchase_variance'));
select tt.chk('T8 production_negative_reason: the owner chose warn earlier, so apply-all left it alone', rule_txt('production_negative_reason') = 'warn'
  and (select count(*) from jsonb_array_elements(:'a4'::jsonb->'skipped') x where x->>'code' = 'production_negative_reason' and x->>'reason' = 'owner_chosen') = 1);
select tt.chk('T8 info rows are skipped no_recommendation (never applied)', (select count(*) from jsonb_array_elements(:'a4'::jsonb->'skipped') x where x->>'reason' = 'no_recommendation') >= 25
  and rule_txt('landed_cost_mode') = 'off' and rule_txt('cash_drawer_mode') = 'off' and rule_txt('cash_drawer_method') = 'none' and not rule_on('telegram_intake_on'));
select tt.chk('T8 safe values applied by apply-all: manual_journal_guard on, expiry warn, backdate warn, scan manual engine, scan on',
  rule_txt('manual_journal_guard') = 'on' and rule_txt('expiry_sale_guard') = 'warn' and rule_txt('purchase_backdate_flag') = 'warn' and rule_on('scan_enabled') and rule_txt('scan_engine') = 'manual'
  and rule_txt('landed_late_mode') = 'split_remaining_and_cogs');

\echo == T9 text and choice values through the same apply (a test row, removed again): good value, bad value
insert into setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('zz_t_text', 'landed_base_currency', '97', 'purchase', '"USD"', '{}', 'x', 'x', 'x', 900), ('zz_t_badchoice', 'landed_late_mode', '97', 'purchase', '"not_a_choice"', '{}', 'x', 'x', 'x', 901),
 ('zz_t_badtype', 'acct_issue_out', '85', 'stock', '"yes"', '{}', 'x', 'x', 'x', 902), ('zz_t_badnum', 'landed_reminder_days', '97', 'purchase', '99999', '{}', 'x', 'x', 'x', 903),
 ('zz_t_gone', 'zz_no_such_rule', '97', 'purchase', 'true', '{}', 'x', 'x', 'x', 904);
select tt.as(:'o'); set role authenticated;
select setup_recommend_apply('22222222-2222-2222-2222-222222222206', array['zz_t_text','zz_t_badchoice','zz_t_badtype','zz_t_badnum','zz_t_gone']) as a5 \gset
reset role;
select tt.chk('T9 a text value is applied as a string through set_rule', rule_txt('landed_base_currency') = 'USD' and (select value from rules where key = 'landed_base_currency') = '"USD"'::jsonb
  and (select count(*) from setup_apply_lines81 where code = 'zz_t_text' and new_value = '"USD"'::jsonb) = 1);
select tt.chk('T9 a value outside the choices, a wrong type and a number outside the range are rejected (rule unchanged); a missing rule is not_installed',
  (select count(*) from jsonb_array_elements(:'a5'::jsonb->'skipped') x where x->>'code' in ('zz_t_badchoice','zz_t_badtype','zz_t_badnum') and x->>'reason' = 'rejected') = 3
  and (select count(*) from jsonb_array_elements(:'a5'::jsonb->'skipped') x where x->>'code' = 'zz_t_gone' and x->>'reason' = 'not_installed') = 1
  and rule_txt('landed_late_mode') = 'split_remaining_and_cogs' and not rule_on('acct_issue_out') and (select value from rules where key = 'landed_reminder_days') is null);
select tt.as(:'o'); set role authenticated;
select setup_recommendations()::text as r4 \gset
reset role;
select tt.chk('T9 the list shows the missing rule as not_installed and the text row as ok', tt.rec(:'r4'::jsonb,'zz_t_gone')->>'status' = 'not_installed' and tt.rec(:'r4'::jsonb,'zz_t_text')->>'status' = 'ok');
delete from setup_rec_defs81 where code like 'zz\_t\_%';
update rules set value = null where key = 'landed_base_currency';

\echo == T10 paste twice: nothing changes
select md5(string_agg(d::text, '|' order by code)) as h1 from setup_rec_defs81 d \gset
select md5(pg_get_functiondef('public.setup_recommendations()'::regprocedure) || pg_get_functiondef('public.setup_recommend_apply(uuid,text[],boolean,boolean)'::regprocedure)) as f1 \gset
select count(*) as n1 from setup_rec_defs81 \gset
select count(*) as ru1 from rules where value is not null \gset
\i supabase/phase101.sql
select tt.chk('T10 second paste: same rows, same functions, no rule value touched', (select md5(string_agg(d::text, '|' order by code)) from setup_rec_defs81 d) = :'h1' and (select count(*) from setup_rec_defs81) = :n1
  and md5(pg_get_functiondef('public.setup_recommendations()'::regprocedure) || pg_get_functiondef('public.setup_recommend_apply(uuid,text[],boolean,boolean)'::regprocedure)) = :'f1' and (select count(*) from rules where value is not null) = :ru1);
-- an owner-edited row is not overwritten by a re-paste, a deleted row comes back
update setup_rec_defs81 set rec_value = '"ask"'::jsonb where code = 'pos_show_invoice_after_sale';
delete from setup_rec_defs81 where code = 'landed_reminder_days';
\i supabase/phase101.sql
select tt.chk('T10 re-paste: an edited row stays as edited (ON CONFLICT DO NOTHING), a missing row is restored', (select rec_value from setup_rec_defs81 where code = 'pos_show_invoice_after_sale') = '"ask"'::jsonb
  and exists (select 1 from setup_rec_defs81 where code = 'landed_reminder_days'));
update setup_rec_defs81 set rec_value = '"always"'::jsonb where code = 'pos_show_invoice_after_sale';

\echo == T11 guard: a database without phase524 or the advisor is refused and nothing is inserted
delete from setup_rec_defs81 where code = 'landed_reminder_days';
alter function public._acct_docs(date) rename to _acct_docs_hold101;
select count(*) as g0 from setup_rec_defs81 \gset
\i supabase/phase101.sql
select tt.chk('T11 with the phase98 marker function missing the paste raises and inserts nothing', (select count(*) from setup_rec_defs81) = :g0);
alter function public._acct_docs_hold101(date) rename to _acct_docs;
\i supabase/phase101.sql
select tt.chk('T11 with the markers back it works again', exists (select 1 from setup_rec_defs81 where code = 'landed_reminder_days'));

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
