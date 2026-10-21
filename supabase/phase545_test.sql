-- Phase 545 tests (purchase price check with freight, switch price_check_include_freight). TEST DATABASE ONLY:
-- a local throwaway Postgres built from the paste chain through phase 545 (fresh database, run ONCE).
-- Prints PASS / FAIL per check, then one fingerprint line FP545 (section F) that is compared with the same scenario on the
-- chain WITHOUT phase 545 (proof that switch OFF changes nothing). Test data only: test_* names, no person names.
-- Numbers are hand-computed (comment above each block).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000005451'
\set m '00000000-0000-0000-0000-000000005452'
\set s '00000000-0000-0000-0000-000000005453'
\set cx '6f1c2b3a-0000-4000-8000-000000000545'
create schema if not exists t545;
create table if not exists t545.res (name text, ok boolean);
truncate t545.res;
create or replace function t545.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t545.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t545.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema t545 to authenticated, anon; grant execute on all functions in schema t545 to authenticated, anon; grant select, insert on t545.res to authenticated, anon;

insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner545@test.invalid', '{"full_name":"test_owner545"}') on conflict do nothing;
update profiles set status = 'active' where id = :'o';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, sell_price, tracked, item_type, is_active, sellable)
  values ('test_t545_a', 'test t545 a', 'test t545 a', 'kg', 'kg', 0, true, 'raw_material', true, true) on conflict do nothing;
select id as ia from items where code = 'test_t545_a' \gset
insert into suppliers (name) values ('test_sup545') returning id as sp \gset
select :'sp' as sp_ \gset

\echo == T0 shape: the rule is OFF, the function and the trigger exist
select t545.chk('T0 rule price_check_include_freight exists, switch, default off, module purchase', (select count(*) = 1 from rules where key = 'price_check_include_freight' and kind = 'switch' and module = 'purchase' and default_value = 'false'::jsonb));
select t545.chk('T0 switch is off now', not rule_on('price_check_include_freight'));
select t545.chk('T0 label and hint have bn, mix and en; English has no Bangla characters', (select label_bn is not null and label_mix is not null and label_en is not null and hint_bn is not null and hint_mix is not null and hint_en is not null and label_en !~ '[ঀ-৿]' and hint_en !~ '[ঀ-৿]' from rules where key = 'price_check_include_freight'));
select t545.chk('T0 trigger on landed_costs exists (after update of status)', (select count(*) = 1 from pg_trigger where tgname = 'landed_costs_price_freight545' and tgrelid = 'public.landed_costs'::regclass));
select t545.chk('T0 variant closed to the browser', not has_function_privilege('authenticated', 'public.purchase_price_check_freight545(uuid)', 'execute') and not has_function_privilege('anon', 'public.purchase_price_check_freight545(uuid)', 'execute'));

\echo == setup: the threshold 15 % (rule purchase_cost_jump_pct, blank today), landed cost mode manual (needed to post a landed cost)
set role authenticated; select t545.as(:'o');
select set_rule('purchase_cost_jump_pct', '15') is null as r1 \gset
select set_rule('landed_cost_mode', '"manual"') is null as r2 \gset
reset role;

\echo == S1 bill 1: 10 kg @ 10 (no freight). Bill 2: 20 kg @ 10.5 (+5 %, below the threshold: no invoice check flag)
set role authenticated; select t545.as(:'o');
select save_purchase(gen_random_uuid(), null, :'sp'::uuid, 1, 'test_b1_545', (now() at time zone 'Asia/Dhaka')::date - 4, format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":10}]', :'ia')::jsonb)->>'id' as b1 \gset
select post_purchase(:'b1'::uuid) is not null as pb1 \gset
select save_purchase(gen_random_uuid(), null, :'sp'::uuid, 1, 'test_b2_545', (now() at time zone 'Asia/Dhaka')::date - 3, format('[{"item_id":"%s","qty":20,"unit":"kg","unit_cost":10.5}]', :'ia')::jsonb)->>'id' as b2 \gset
select post_purchase(:'b2'::uuid) is not null as pb2 \gset
select id as b1l from purchase_lines where bill_id = :'b1'::uuid \gset
select id as b2l from purchase_lines where bill_id = :'b2'::uuid \gset
reset role;
select t545.chk('S1 bills 1 and 2 posted; 5 % move gives no yellow price flag at bill posting', :'pb1'::boolean and :'pb2'::boolean
  and (select count(*) from exceptions where flag_code = 'purchase_price_jump') = 0);

\echo == F OFF: landed cost with freight 60 on bill 2 (by qty: 3 per kg). Invoice 10.5 + 3 = 13.5 vs bill 1 10 = +35 %. Switch OFF: no freight check runs
-- Fingerprint is taken here (before any switch is on) so the same scenario can be compared with the chain without phase 545.
set role authenticated; select t545.as(:'o');
select landed_save(:'cx'::uuid, null, '{"title":"test freight 545","alloc_method":"qty"}'::jsonb, format('[{"type":"bill","id":"%s"}]', :'b2')::jsonb,
  format('[{"charge_type":"freight","amount":60,"alloc_method":"qty","pay_mode":"payable","supplier_id":"%s"}]', :'sp')::jsonb)->>'id' as c1 \gset
select landed_post(:'c1'::uuid) ->> 'status' as ps1 \gset
reset role;
select t545.chk('F1 landed cost posted', :'ps1' = 'posted');
select t545.chk('F2 OFF: the variant answers on=false and writes nothing (no yellow flag from freight)', (select count(*) from exceptions where flag_code = 'purchase_price_jump') = 0);
select t545.chk('F3 OFF: freight is in the stock books for bill 2 (60 allocated), as before', (select coalesce(sum(amount), 0) from landed_cost_alloc where bill_line_id = :'b2l'::bigint and kind = 'post' and part in ('stock', 'cogs')) = 60);
select 'FP545 ' || md5(concat_ws('|',
  (select count(*) from exceptions),
  (select coalesce(string_agg(flag_code || ':' || level || ':' || coalesce(text->>'en', '') || ':' || coalesce(entry_date::text, ''), '|' order by flag_code, entry_date, text->>'en'), '') from exceptions),
  (select coalesce(string_agg(s.qty::text || '/' || coalesce(s.avg_cost::text, '-'), ';' order by s.location_id), '') from stock_balance s where s.item_id = :'ia'::uuid),
  (select coalesce(string_agg(q.reason || ':' || q.n::text, ',' order by q.reason), '') from (select reason, count(*) n from stock_ledger where item_id = :'ia'::uuid group by reason) q),
  (select coalesce(sum(amount), 0)::text || '/' || count(*)::text from landed_cost_alloc),
  (select coalesce(string_agg(coalesce(unit_cost_base::text, '-'), ';' order by id), '') from purchase_lines where item_id = :'ia'::uuid),
  (select count(*) from journal_entries))) as fp545 \gset
select :'fp545' as fingerprint_line \gset
\echo :fingerprint_line

\echo == F ON: the owner turns the switch on (settings RPC). A new landed cost on bill 3 (20 kg @ 10.5, freight 120 by qty = 6 per kg): 16.5 vs bill 2 incl. 13.5 = +22.2 % -> one yellow flag
set role authenticated; select t545.as(:'o');
select set_rule('price_check_include_freight', 'true') is null as r3 \gset
select save_purchase(gen_random_uuid(), null, :'sp'::uuid, 1, 'test_b3_545', (now() at time zone 'Asia/Dhaka')::date - 2, format('[{"item_id":"%s","qty":20,"unit":"kg","unit_cost":10.5}]', :'ia')::jsonb)->>'id' as b3 \gset
select post_purchase(:'b3'::uuid) is not null as pb3 \gset
select id as b3l from purchase_lines where bill_id = :'b3'::uuid \gset
select landed_save(gen_random_uuid(), null, '{"title":"test freight 545 b3","alloc_method":"qty"}'::jsonb, format('[{"type":"bill","id":"%s"}]', :'b3')::jsonb,
  format('[{"charge_type":"freight","amount":120,"alloc_method":"qty","pay_mode":"payable","supplier_id":"%s"}]', :'sp')::jsonb)->>'id' as c2 \gset
select landed_post(:'c2'::uuid) ->> 'status' as ps2 \gset
reset role;
select t545.chk('F4 ON: the switch is on (set through set_rule)', rule_on('price_check_include_freight'));
select t545.chk('F5 ON: bill 3 posted and its landed cost posted', :'pb3'::boolean and :'ps2' = 'posted');
select t545.chk('F6 ON: exactly one yellow purchase_price_jump flag for bill 3, the text says freight', (select count(*) = 1 and bool_and(level = 'yellow' and text->>'en' like '%with freight%') from exceptions where flag_code = 'purchase_price_jump' and text->>'en' like '%test_b3_545%'));
select t545.chk('F7 ON: the flag shows +22.2 %', (select count(*) from exceptions where flag_code = 'purchase_price_jump' and text->>'en' like '%22.2%') = 1);
select t545.chk('F8 ON: freight of bill 3 line is 120 in the books', (select coalesce(sum(amount), 0) from landed_cost_alloc where bill_line_id = :'b3l'::bigint and kind = 'post' and part in ('stock', 'cogs')) = 120);

\echo == F9 void: voiding the bill 3 landed cost takes its freight back out of the variant (void rows count negative)
set role authenticated; select t545.as(:'o');
select landed_void(:'c2'::uuid, 'test void 545') ->> 'status' as v2 \gset
reset role;
select t545.chk('F9 void: the freight of bill 3 is back to 0 (void rows counted negative)', (select coalesce(sum(amount), 0) from landed_cost_alloc where bill_line_id = :'b3l'::bigint and part in ('stock', 'cogs')) = 0);
select t545.chk('F9b the variant alone returns on=true and checked=0 for a cost with no lines', (select (purchase_price_check_freight545(gen_random_uuid())->>'checked')::int = 0 and (purchase_price_check_freight545(gen_random_uuid())->>'on')::boolean));

\echo == F10 OFF again: no more flags from the variant; the threshold goes back to blank (today)
set role authenticated; select t545.as(:'o');
select set_rule('price_check_include_freight', 'false') is null as r4 \gset
reset role;
update rules set value = null where key = 'purchase_cost_jump_pct';
select t545.chk('F10 switch back to off', not rule_on('price_check_include_freight'));
select t545.chk('F10b switch off: the variant answers on=false again', (select (purchase_price_check_freight545(gen_random_uuid())->>'on')::boolean = false));
select t545.chk('F10c threshold blank again (default)', (select value is null from rules where key = 'purchase_cost_jump_pct'));

select count(*) filter (where not ok) as failing, count(*) as checks from t545.res;
