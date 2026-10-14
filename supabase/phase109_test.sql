-- FRESH DB ONLY. Phase 109 tests (concurrency fixes F1 F2 F4 F5 F6): single-session behaviour is unchanged, hand-computed numbers.
--   bash tests/sql/final_build.sh p109db "<order from docs/PASTE_ORDER.md ... phase103 phase109>"
--   psql -h /tmp -p 5544 -U postgres -d p109db -qAt -f supabase/phase109_test.sql | grep -E 'FAIL|RESULT'
-- The parallel (failing-before / passing-after) checks are tests/sql/concurrency/verify_fixes.sh (S04 S08 S09b S12 S13).
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
\echo == T0 shape, paste twice
select tt.chk('T0 rule card_settle_over_mode: choice, default off', (select kind = 'choice' and default_value = '"off"'::jsonb and choices = '["off","warn","refuse"]'::jsonb from rules where key = 'card_settle_over_mode'));
select tt.chk('T0 advisor row recommends warn', (select rec_value = '"warn"'::jsonb and phase = '109' from setup_rec_defs81 where code = 'card_settle_over_mode'));
select tt.chk('T0 every supplier lock is FOR NO KEY UPDATE (7 functions)', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_post_purchase_p13','_void_purchase_p13','_bp_pay99','pay_supplier','void_supplier_payment','supplier_refund','void_supplier_refund')
  and pg_get_functiondef(p.oid) ~ 'suppliers where id = [a-z_.]+ for no key update;' and pg_get_functiondef(p.oid) !~ 'suppliers where id = [a-z_.]+ for update;') = 7);
select tt.chk('T0 no other function takes FOR UPDATE on suppliers', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and pg_get_functiondef(p.oid) ~ 'suppliers where id = [a-z_.]+ for update;'));
select tt.chk('T0 production_post locks balances in item order before the check', (select position('order by sbl.item_id for update' in pg_get_functiondef(p.oid)) > 0 and position('order by sbl.item_id for update' in pg_get_functiondef(p.oid)) < position('insufficient_stock' in pg_get_functiondef(p.oid))
  from pg_proc p where p.proname = 'production_post' and p.pronargs = 7));
select tt.chk('T0 older tags kept (bos72 73 74 80 in production_post, bos103 in setup_recommend_apply)', (select bool_and(case p.proname when 'production_post' then d ~ 'bos72' and d ~ 'bos73' and d ~ 'bos74' and d ~ 'bos80' else d ~ 'bos103' end)
  from (select proname, pg_get_functiondef(oid) d from pg_proc where proname in ('setup_recommend_apply') or (proname = 'production_post' and pronargs = 7)) p));

\echo == T1 option view bulk: unsorted keys, same result as before
select tt.as(:'o');
select tt.chk('T1 user bulk with descending keys: count 3, changed 3', (select (r ->> 'count')::int = 3 and (r ->> 'changed')::int = 3 from (select set_option_view_bulk(:'s'::uuid, '[{"key":"r:k003","mode":"hide"},{"key":"r:k001","mode":"hide"},{"key":"r:k002","mode":"locked"}]'::jsonb, gen_random_uuid()) r) z));
select tt.chk('T1 user overrides = 3, k002 locked', (select jsonb_array_length(option_views_for_user(:'s'::uuid) -> 'overrides') = 3 and (select mode from user_option_view where user_id = :'s'::uuid and option_key = 'r:k002') = 'locked'));
select tt.chk('T1 role bulk with descending keys: count 3', (select (set_role_option_view_bulk('salesperson', '[{"key":"r:k003","mode":"hide"},{"key":"r:k001","mode":"hide"},{"key":"r:k002","mode":"hide"}]'::jsonb, gen_random_uuid()) ->> 'count')::int = 3));
create temp table t1d as select set_option_view_bulk(:'s'::uuid, '[{"key":"r:k005","mode":"hide"},{"key":"r:k005","mode":"locked"}]'::jsonb, gen_random_uuid()) r;
select tt.chk('T1 duplicate key in one call: the later item wins (order kept by position)', (select (r ->> 'count')::int = 2 from t1d)
  and (select mode from user_option_view where user_id = :'s'::uuid and option_key = 'r:k005') = 'locked');

\echo == T2 setup_recommend_apply: a second apply with another client id changes and audits nothing twice
select tt.as(:'o');
create temp table t2a as select setup_recommend_apply(gen_random_uuid()) r;
create temp table t2b as select setup_recommend_apply(gen_random_uuid()) r;
select tt.chk('T2 first apply changed at least one rule', (select (r ->> 'count')::int > 0 from t2a));
select tt.chk('T2 second apply changed 0 rules', (select (r ->> 'count')::int = 0 from t2b));
select tt.chk('T2 no rule in setup_apply_lines81 twice', not exists (select 1 from setup_apply_lines81 group by rule_key having count(*) > 1));
select tt.chk('T2 card_settle_over_mode was set to warn by the advisor', (select value = '"warn"'::jsonb from rules where key = 'card_settle_over_mode'));
select set_rule('card_settle_over_mode', '"off"'::jsonb);

\echo == T3 card_settle (card receivable 1140: GL 600, then +1000)
reset role;
with e as (insert into journal_entries (entry_date, location_id, source_type, source_id, memo) values (current_date, 1, 'manual', 'p109-a', 'p109 seed') returning id)
insert into journal_lines (entry_id, line_no, account_id, debit, credit, location_id) select e.id, 1, 6, 600, 0, 1 from e union all select e.id, 2, 3, 0, 600, 1 from e;
select tt.as(:'o');
create temp table t3 (n int, r jsonb);
-- off (default): exactly the old behaviour, the flag only knows the booked balance
insert into t3 select 1, card_settle(1, current_date, 600, 12, 'a', gen_random_uuid());
insert into t3 select 2, card_settle(1, current_date, 100, 0, 'b', gen_random_uuid());
select tt.chk('T3 off: 600 against 600 -> over false, unsettled 600', (select (r ->> 'over')::boolean = false and (r ->> 'unsettled')::numeric = 600 from t3 where n = 1));
select tt.chk('T3 off: the next 100 is still "not over" (unchanged blindness), no exception', (select (r ->> 'over')::boolean = false and (r ->> 'unsettled')::numeric = 600 from t3 where n = 2) and not exists (select 1 from exceptions where flag_code = 'card_settle_over'));
select set_rule('card_settle_over_mode', '"warn"'::jsonb);
insert into t3 select 3, card_settle(1, current_date, 50, 0, 'c', gen_random_uuid());
select tt.chk('T3 warn: 600 - (600 + 100 saved, not booked) = -100 unsettled, over true', (select (r ->> 'over')::boolean and (r ->> 'unsettled')::numeric = -100 from t3 where n = 3));
select tt.chk('T3 warn: saved (3 rows) and one yellow exception of 50', (select count(*) from card_settlements85) = 3 and (select count(*) from exceptions where flag_code = 'card_settle_over' and level = 'yellow' and amount = 50) = 1);
select set_rule('card_settle_over_mode', '"refuse"'::jsonb);
select tt.err('T3 refuse: 10 against -100 -> over_settlement', $$select card_settle(1, current_date, 10, 0, 'd', gen_random_uuid())$$, 'over_settlement');
select tt.chk('T3 refuse: nothing saved by the refused call', (select count(*) from card_settlements85) = 3);
reset role;
with e as (insert into journal_entries (entry_date, location_id, source_type, source_id, memo) values (current_date, 1, 'manual', 'p109-b', 'p109 seed 2') returning id)
insert into journal_lines (entry_id, line_no, account_id, debit, credit, location_id) select e.id, 1, 6, 1000, 0, 1 from e union all select e.id, 2, 3, 0, 1000, 1 from e;
select tt.as(:'o');
insert into t3 select 4, card_settle(1, current_date, 800, 0, 'e', gen_random_uuid());
select tt.chk('T3 refuse: 1600 - 750 = 850 unsettled; 800 accepted, over false', (select (r ->> 'over')::boolean = false and (r ->> 'unsettled')::numeric = 850 from t3 where n = 4));
select tt.err('T3 refuse: another 100 > 50 left -> over_settlement', $$select card_settle(1, current_date, 100, 0, 'f', gen_random_uuid())$$, 'over_settlement');
create temp table t3c as select card_settle(1, current_date, 800, 0, 'e', (select client_id from card_settlements85 where note = 'e')) r;
select tt.chk('T3 same client id replayed: dup, still 4 rows', (select (r ->> 'dup')::boolean from t3c) and (select count(*) from card_settlements85) = 4);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
