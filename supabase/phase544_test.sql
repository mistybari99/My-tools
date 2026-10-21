-- Phase 544 tests (sweets transfers: reused client id from another user). TEST DATABASE ONLY (a local throwaway Postgres built from the paste chain through phase 544).
-- Run ONCE on a fresh database (it seeds opening stock, which the chain allows once). Prints PASS / FAIL per check. The switch is set straight in the rules table here and put back to OFF (default) at the end.
\set ON_ERROR_STOP off
\set a '00000000-0000-0000-0000-0000000544aa'
\set b '00000000-0000-0000-0000-0000000544bb'
create schema if not exists t544;
create table if not exists t544.res (name text, ok boolean);
truncate t544.res;
create or replace function t544.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t544.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;

insert into auth.users (id, email, raw_user_meta_data) values (:'a', 'test_a544@test.invalid', '{"full_name":"test_a544"}'), (:'b', 'test_b544@test.invalid', '{"full_name":"test_b544"}') on conflict do nothing;
update profiles set status = 'active' where id in (:'a', :'b');
insert into user_roles values (:'a', 'owner') on conflict do nothing;
insert into user_roles values (:'b', 'owner') on conflict do nothing;
insert into items (code, name_bn, name_en, unit, tracked, sell_price, is_active, sellable)
  values ('test_t544_a', 'test t544 a', 'test t544 a', 'kg', true, 100, true, true) on conflict do nothing;
select id as ia from items where code = 'test_t544_a' \gset

\echo == T0 switch exists, default OFF
select t544.chk('T0 transfer_client_reuse_block exists, default off', (select count(*) = 1 from rules where key = 'transfer_client_reuse_block' and default_value = 'false'::jsonb));
select t544.chk('T0 switch is off now', not rule_on('transfer_client_reuse_block'));

select set_config('request.jwt.claim.sub', :'a', false);
select stock_post(:'ia'::uuid, 1, 100, 'opening', 'test', 't544-seed', 50, null, now(), null, null, null, null, null) is not null as seeded \gset
select t544.chk('T0 seeded 100 kg at place 1', (select qty from stock_balance where item_id = :'ia'::uuid and location_id = 1) = 100);
\set cx '6f1c2b3a-0000-4000-8000-000000000544'
select stock_transfer(1, 2, :'ia'::uuid, 5, 'kg', 'by a', :'cx'::uuid) ->> 'status' as s_a \gset
select t544.chk('T0 user A sends 5 kg with client id X', :'s_a' = 'sent');

\echo == T1 OFF: user B reuses X (today: dup with A transfer id, nothing moves for B)
select set_config('request.jwt.claim.sub', :'b', false);
select stock_transfer(1, 2, :'ia'::uuid, 7, 'kg', 'by b', :'cx'::uuid) ->> 'dup' as d_b \gset
select t544.chk('T1 OFF: B gets dup (today)', :'d_b' = 'true');
select t544.chk('T1 OFF: B 7 kg not moved (only 5 out so far)', (select qty from stock_balance where item_id = :'ia'::uuid and location_id = 1) = 95);

\echo == T2 ON: user B reuses X is refused, nothing moves
update rules set value = 'true'::jsonb where key = 'transfer_client_reuse_block';
select t544.chk('T2 switch is on', rule_on('transfer_client_reuse_block'));
select set_config('request.jwt.claim.sub', :'b', false);
do $t$ begin perform stock_transfer(1, 2, (select id from items where code = 'test_t544_a'), 7, 'kg', 'by b again', '6f1c2b3a-0000-4000-8000-000000000544'::uuid);
  perform t544.chk('T2 ON: B reuse refused', false);
exception when others then perform t544.chk('T2 ON: B reuse refused with client_id_reused', sqlerrm = 'client_id_reused'); end $t$;
select t544.chk('T2 ON: nothing moved for B (still 95)', (select qty from stock_balance where item_id = (select id from items where code = 'test_t544_a') and location_id = 1) = 95);

\echo == T3 ON: user A replays X (lost reply): still dup, as before
select set_config('request.jwt.claim.sub', :'a', false);
select stock_transfer(1, 2, :'ia'::uuid, 5, 'kg', 'by a again', :'cx'::uuid) ->> 'dup' as d_a \gset
select t544.chk('T3 ON: same user replay is still dup', :'d_a' = 'true');

\echo == T4 ON: B sends with its own new id: accepted
select set_config('request.jwt.claim.sub', :'b', false);
select stock_transfer(1, 2, :'ia'::uuid, 3, 'kg', 'own id', '6f1c2b3a-0000-4000-8000-000000000507'::uuid) ->> 'status' as s_b2 \gset
select t544.chk('T4 ON: B send with a new client id is accepted', :'s_b2' = 'sent');

update rules set value = null where key = 'transfer_client_reuse_block';
select t544.chk('T5 switch back to off (default)', not rule_on('transfer_client_reuse_block'));
select count(*) filter (where not ok) as failing, count(*) as checks from t544.res;
