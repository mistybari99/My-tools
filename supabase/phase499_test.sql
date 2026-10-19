-- Phase 499 tests (sweets stock transfers). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain through phase 499).
-- Prints PASS / FAIL per check. The switches are set straight in the rules table here (the owner's set_rule asks for two-factor), and put back to OFF at the end.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f499'
create schema if not exists t499;
create table if not exists t499.res (name text, ok boolean);
truncate t499.res;
create or replace function t499.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t499.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t499.err(p_name text, p_sql text, p_msg text) returns void language plpgsql as $$
begin execute p_sql; perform t499.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform t499.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;

insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner499@test.invalid', '{"full_name":"test_owner499"}') on conflict do nothing;
update profiles set status = 'active' where id = :'o';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);

insert into items (code, name_bn, name_en, unit, tracked, sell_price, is_active, sellable)
  values ('test_t499_a', 'test t499 a', 'test t499 a', 'kg', true, 100, true, true) on conflict do nothing;
select id as ia from items where code = 'test_t499_a' \gset

\echo == T0 switches exist and default OFF
select t499.chk('T0 three transfer switches exist, default off', (select count(*) = 3 from rules where key in ('transfer_overdraw_block', 'transfer_paused_block', 'transfer_partial_on') and default_value = 'false'::jsonb));
select t499.chk('T0 switches are off now', not rule_on('transfer_overdraw_block') and not rule_on('transfer_paused_block') and not rule_on('transfer_partial_on'));
select t499.chk('T0 close-short function exists and is not for anon', has_function_privilege('authenticated', 'public.stock_close_transfer_short(uuid,text)', 'execute') and not has_function_privilege('anon', 'public.stock_close_transfer_short(uuid,text)', 'execute'));

select stock_post(:'ia'::uuid, 1, 100, 'opening', 'test', 't499-seed', 50, null, now(), null, null, null, null, null) is not null as seeded \gset
select t499.chk('T0 seeded 100 kg at place 1', (select qty from stock_balance where item_id = :'ia'::uuid and location_id = 1) = 100);

\echo == T1 over-send: defect with the switch off, refused with it on
select stock_transfer(1, 2, :'ia'::uuid, 120, 'kg', 'overload off', gen_random_uuid()) ->> 'status' as s1 \gset
select t499.chk('T1a OFF: 120 kg sent from 100 on hand (today: accepted, stock negative)', :'s1' = 'sent' and (select qty from stock_balance where item_id = :'ia'::uuid and location_id = 1) = -20);
select stock_post(:'ia'::uuid, 1, 50, 'count_adjust', 'test', 't499-seed2', 50, null, now(), null, null, null, null, null) is not null as seeded2 \gset
update rules set value = 'true'::jsonb where key = 'transfer_overdraw_block';
select t499.err('T1b ON: send bigger than the 30 kg on hand refused', format('select stock_transfer(1, 2, %L::uuid, 31, ''kg'', ''over on'', gen_random_uuid())', :'ia'), 'insufficient_stock');
select t499.chk('T1c ON: a send within stock is still accepted', (select stock_transfer(1, 2, :'ia'::uuid, 1, 'kg', 'small', gen_random_uuid()) ->> 'status') = 'sent');
update rules set value = null where key = 'transfer_overdraw_block';

\echo == T2 paused destination: accepted with the switch off, refused with it on
select stock_transfer(1, 5, :'ia'::uuid, 1, 'kg', 'to paused off', gen_random_uuid()) ->> 'status' as s2 \gset
select t499.chk('T2a OFF: send to a paused place accepted (today)', :'s2' = 'sent');
update rules set value = 'true'::jsonb where key = 'transfer_paused_block';
select t499.err('T2b ON: send to a paused place refused', format('select stock_transfer(1, 5, %L::uuid, 1, ''kg'', ''paused on'', gen_random_uuid())', :'ia'), 'destination_paused');
select t499.chk('T2c ON: send to a live place still accepted', (select stock_transfer(1, 3, :'ia'::uuid, 1, 'kg', 'live', gen_random_uuid()) ->> 'status') = 'sent');
update rules set value = null where key = 'transfer_paused_block';

\echo == T3 receipt in one step (switch off): one receipt closes the transfer, as before
select stock_transfer(1, 2, :'ia'::uuid, 20, 'kg', 'one step', gen_random_uuid()) ->> 'id' as t3 \gset
select stock_receive_transfer(:'t3'::uuid, 8, 'first') ->> 'status' as r3a \gset
select t499.chk('T3a OFF: first receipt of 8 closes the transfer (today)', :'r3a' = 'received');
select stock_receive_transfer(:'t3'::uuid, 12, 'second') ->> 'dup' as r3b \gset
select t499.chk('T3b OFF: the second receipt is a duplicate (today; the 12 kg stay in transit)', :'r3b' = 'true');

\echo == T4 receipt in steps (switch on): 20 sent, 8 then 12 received
update rules set value = 'true'::jsonb where key = 'transfer_partial_on';
select count(*) as short_before from exceptions where flag_code = 'transit_short' \gset
select stock_transfer(1, 2, :'ia'::uuid, 20, 'kg', 'split', gen_random_uuid()) ->> 'id' as t4 \gset
select stock_receive_transfer(:'t4'::uuid, 8, 'part 1') as p4a \gset
select t499.chk('T4a ON: first step keeps the transfer open', (select status from stock_transfers where id = :'t4'::uuid) = 'sent' and (select received_qty from stock_transfers where id = :'t4'::uuid) = 8);
select t499.chk('T4b ON: first step reports the remaining 12', (:'p4a'::jsonb ->> 'remaining')::numeric = 12);
select stock_receive_transfer(:'t4'::uuid, 12, 'part 2') ->> 'status' as p4b \gset
select t499.chk('T4c ON: second step closes it received with 20', :'p4b' = 'received' and (select received_qty from stock_transfers where id = :'t4'::uuid) = 20);
select t499.chk('T4d ON: no short exception for a full delivery in steps', (select count(*) from exceptions where flag_code = 'transit_short') = :short_before);
select t499.chk('T4e ON: destination holds the 20 kg once, no double count', (select qty from stock_balance where item_id = :'ia'::uuid and location_id = 2) >= 20);

\echo == T5 close the rest short (switch on): 10 sent, 4 received, owner closes the rest
select stock_transfer(1, 2, :'ia'::uuid, 10, 'kg', 'close short', gen_random_uuid()) ->> 'id' as t5 \gset
select stock_receive_transfer(:'t5'::uuid, 4, 'part') ->> 'remaining' as r5a \gset
select t499.chk('T5a ON: 6 kg still in transit after the first 4', :'r5a'::numeric = 6);
select stock_close_transfer_short(:'t5'::uuid, 'van lost 6') ->> 'short' as r5b \gset
select t499.chk('T5b ON: close short gives short 6 and status received', :'r5b'::numeric = 6 and (select status from stock_transfers where id = :'t5'::uuid) = 'received');
select t499.chk('T5c ON: close short writes one transit_short exception', (select count(*) from exceptions where flag_code = 'transit_short') = :short_before + 1);
select t499.chk('T5d ON: a closed transfer received again gives dup and moves no stock', (select stock_receive_transfer(:'t5'::uuid, 6, 'late') ->> 'dup') = 'true' and (select received_qty from stock_transfers where id = :'t5'::uuid) = 4);

\echo == T6 close short is refused with the switch off
update rules set value = 'false'::jsonb where key = 'transfer_partial_on';
select stock_transfer(1, 2, :'ia'::uuid, 2, 'kg', 'off close', gen_random_uuid()) ->> 'id' as t6 \gset
select t499.err('T6a OFF: close short refused', format('select stock_close_transfer_short(%L::uuid, ''x'')', :'t6'), 'partial_receipt_off');

\echo == T7 the switches go back to OFF (the test leaves the database as it was)
update rules set value = null where key in ('transfer_overdraw_block', 'transfer_paused_block', 'transfer_partial_on');
select t499.chk('T7 switches back to default off', not rule_on('transfer_overdraw_block') and not rule_on('transfer_paused_block') and not rule_on('transfer_partial_on'));

\echo == RESULT
select 'phase499 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t499.res;
select name from t499.res where not ok;
