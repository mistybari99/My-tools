-- FRESH DB ONLY. Phase 77 tests (Step E9: pack-time stock warning, keep order price, voided sale flag).
--   ORDER="phase8 ... phase62 phase70 phase71 phase76 phase77"; psql -d <db> -qAt -f supabase/phase77_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set p '00000000-0000-0000-0000-000000000004'
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

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'p','sales4@s.app','{"full_name":"Sales"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'p','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'p',1) on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('E1','E1','E1','kg','kg','finished_good',true,100), ('E2','E2 untracked','E2','kg','kg','finished_good',false,50);
select id as e1 from items where code='E1' \gset
select id as e2 from items where code='E2' \gset
select tt.as(:'o');
select stock_opening(:'e1'::uuid, 1, 40, 100, null, 'seed') is not null as op1 \gset
select set_rule('online_orders_on','true') is null as r0 \gset
select sales_channel_save(null,'phoneline','phone',null,'Phone',1,null,null,true) is not null as ch \gset
select id as cph from sales_channels where code='phoneline' \gset

\echo == T0 shape
select tt.chk('T0 switches default OFF', not rule_on('online_pack_warn_on') and not rule_on('online_pack_reserve_on') and not rule_on('online_keep_order_price'));
select tt.chk('T0 flags table read-only for browsers, RLS on, helpers closed', not has_table_privilege('authenticated','public.online_order_flags','insert') and not has_table_privilege('authenticated','public.online_order_flags','update')
  and (select relrowsecurity from pg_class where relname='online_order_flags') and not has_function_privilege('authenticated','public._oo_short77(uuid)','execute') and has_function_privilege('authenticated','public.online_order_stock_check(uuid)','execute'));

\echo == T1 pack-time stock warning
select tt.as(:'p');
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'Big', '01711000001', null, format('[{"item_id":"%s","qty":50},{"item_id":"%s","qty":2}]', :'e1', :'e2')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null)->>'id' as big \gset
select online_order_status(:'big'::uuid,'confirmed') is not null as c1 \gset
select online_order_status(:'big'::uuid,'packed')::text as pk1 \gset
select tt.chk('T1 switch OFF = today: packing a short order answers no warning', (:'pk1'::jsonb->>'status')='packed' and not (:'pk1'::jsonb ? 'warn'));
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'Big2', '01711000002', null, format('[{"item_id":"%s","qty":50},{"item_id":"%s","qty":2}]', :'e1', :'e2')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null)->>'id' as big2 \gset
select online_order_status(:'big2'::uuid,'confirmed') is not null as c2 \gset
select tt.as(:'o'); select set_rule('online_pack_warn_on','true') is null as w1 \gset
select tt.as(:'p');
select online_order_stock_check(:'big2'::uuid)::text as chk1 \gset
select tt.chk('T1 preview: read-only check lists the short tracked item (need 50, have 40) and ignores the untracked one', (:'chk1'::jsonb->>'on')::boolean and jsonb_array_length(:'chk1'::jsonb->'short')=1
  and (:'chk1'::jsonb->'short'->0->>'need')::numeric=50 and (:'chk1'::jsonb->'short'->0->>'have')::numeric=40);
select coalesce(sum(qty),0) as st0 from stock_balance where item_id=:'e1'::uuid \gset
select online_order_status(:'big2'::uuid,'packed')::text as pk2 \gset
select tt.chk('T1 switch ON: packing is NOT blocked, status packed, warning with the short list returned', (:'pk2'::jsonb->>'status')='packed' and (:'pk2'::jsonb->>'warn')::boolean and (:'pk2'::jsonb->'short'->0->>'short_by')::numeric=10);
select tt.chk('T1 the warning is on the order trail; nothing reserved or moved in stock', exists (select 1 from online_order_events where order_id=:'big2'::uuid and note like '%STOCK SHORT%') and (select coalesce(sum(qty),0) from stock_balance where item_id=:'e1'::uuid)=:st0);
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'Ok', '01711000003', null, format('[{"item_id":"%s","qty":5}]', :'e1')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null)->>'id' as okid \gset
select online_order_status(:'okid'::uuid,'confirmed') is not null as c3 \gset
select tt.chk('T1 enough stock: no warning', not (online_order_status(:'okid'::uuid,'packed') ? 'warn'));

\echo == T2 soft reservation (switch)
-- packed now: big (50), big2 (50), ok (5). Use a fresh item so numbers are clean.
select tt.as(:'o');
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('E3','E3','E3','kg','kg','finished_good',true,10);
select id as e3 from items where code='E3' \gset
select stock_opening(:'e3'::uuid, 1, 40, 10, null, 'seed') is not null as op3 \gset
select tt.as(:'p');
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'RA', '01711000004', null, format('[{"item_id":"%s","qty":30}]', :'e3')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null)->>'id' as ra \gset
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'RB', '01711000005', null, format('[{"item_id":"%s","qty":30}]', :'e3')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null)->>'id' as rb \gset
select online_order_status(:'ra'::uuid,'confirmed') is not null as x1 \gset
select online_order_status(:'rb'::uuid,'confirmed') is not null as x2 \gset
select online_order_status(:'ra'::uuid,'packed') is not null as x3 \gset
select tt.chk('T2 reservation switch OFF: second order of 30 against stock 40 shows no warning (stock only)', not (online_order_status(:'rb'::uuid,'packed') ? 'warn'));
-- put rb back? orders only go forward: use a third order for the ON case
select tt.as(:'o'); select set_rule('online_pack_reserve_on','true') is null as rv \gset
select tt.as(:'p');
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'RC', '01711000006', null, format('[{"item_id":"%s","qty":10}]', :'e3')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null)->>'id' as rc \gset
select online_order_status(:'rc'::uuid,'confirmed') is not null as x4 \gset
select online_order_stock_check(:'rc'::uuid)::text as chk2 \gset
select tt.chk('T2 reservation ON: other packed orders (30+30) are deducted: need 10, have 40, reserved 60 => warns', (:'chk2'::jsonb->>'reserve')::boolean and (:'chk2'::jsonb->'short'->0->>'reserved')::numeric=60);
select tt.chk('T2 still advisory: the counter can sell the stock (a sale of 35 is NOT blocked)', record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":35}]',:'e3')::jsonb,0,'[{"mode":"cash","amount":350}]'::jsonb,null,null,'retail',null,false,null) is not null);

\echo == T3 keep the order price at delivery
select tt.as(:'o'); select set_rule('online_pack_warn_on','false') is null as w0 \gset
select tt.as(:'s');
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'Pr1', '01711000007', null, format('[{"item_id":"%s","qty":3}]', :'e1')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null)->>'id' as pr1 \gset
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'Pr2', '01711000008', null, format('[{"item_id":"%s","qty":3}]', :'e1')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null)->>'id' as pr2 \gset
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'Pr3', '01711000009', null, format('[{"item_id":"%s","qty":3}]', :'e1')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null)->>'id' as pr3 \gset
select online_order_status(x,'confirmed') is not null as pc1 from (values (:'pr1'::uuid),(:'pr2'::uuid),(:'pr3'::uuid)) v(x) limit 1 \gset
select online_order_status(:'pr2'::uuid,'confirmed') is not null as pc2 \gset
select online_order_status(:'pr3'::uuid,'confirmed') is not null as pc3 \gset
select online_order_status(x,'packed') is not null as pp from (values (:'pr1'::uuid)) v(x) \gset
select online_order_status(:'pr2'::uuid,'packed') is not null as pp2 \gset
select online_order_status(:'pr3'::uuid,'packed') is not null as pp3 \gset
select tt.as(:'o'); update items set sell_price = 120 where id = :'e1'::uuid;
select tt.as(:'s');
select online_order_deliver(:'pr1'::uuid, '[{"mode":"cash","amount":360}]')->>'sale_id' as sale1 \gset
select tt.chk('T3 switch OFF = today: the sale uses TODAY''S list price (3 x 120 = 360), a price_changed exception is logged', (select total from sales where id=:'sale1'::uuid)=360
  and exists (select 1 from exceptions where sale_id=:'sale1'::uuid and flag_code='price_changed'));
select tt.as(:'o'); select set_rule('online_keep_order_price','true') is null as k1 \gset
select tt.as(:'s');
select online_order_deliver(:'pr2'::uuid, '[{"mode":"cash","amount":300}]')->>'sale_id' as sale2 \gset
select tt.chk('T3 switch ON: the ORDER price holds (3 x 100 = 300) and the price_override exception is logged (no silent change)', (select total from sales where id=:'sale2'::uuid)=300
  and exists (select 1 from exceptions where sale_id=:'sale2'::uuid and flag_code='price_override'));
select tt.as(:'p');
select tt.err('T3 switch ON, caller without the price_override approval: refused, atomic', format($$select online_order_deliver('%s'::uuid,'[]')$$, :'pr3'), 'override_needs_approval');
select tt.chk('T3 the refused delivery left no sale and the order still packed', (select status from online_orders where id=:'pr3'::uuid)='packed' and (select sale_id from online_orders where id=:'pr3'::uuid) is null);
select tt.as(:'o'); update items set sell_price = 100 where id = :'e1'::uuid;
select tt.as(:'s');
select tt.chk('T3 switch ON and the price did not move: delivery works for everyone, no override flag', (online_order_deliver(:'pr3'::uuid, '[{"mode":"cash","amount":300}]')->>'status')='delivered'
  and not exists (select 1 from exceptions where sale_id=(select sale_id from online_orders where id=:'pr3'::uuid) and flag_code='price_override'));
select tt.chk('T3 retry of a delivered order = dup, no 2nd sale', (online_order_deliver(:'pr2'::uuid,'[]')->>'dup')::boolean);

\echo == T4 voided sale of an order => flag
select tt.as(:'o'); select set_rule('online_keep_order_price','false') is null as k0 \gset
select tt.as(:'o');
select void_sale(:'sale2'::uuid, 'wrong customer') is null as v1 \gset
select tt.chk('T4 voiding the sale of a delivered order raises an OPEN flag on the order, the order status is not silently changed', (select count(*) from online_order_flags where order_id=:'pr2'::uuid and kind='sale_voided' and state='open')=1
  and (select status from online_orders where id=:'pr2'::uuid)='delivered');
select tt.chk('T4 order trail has the SALE VOIDED line and a RED exception exists for the sale', exists (select 1 from online_order_events where order_id=:'pr2'::uuid and note like 'SALE VOIDED%')
  and exists (select 1 from exceptions where sale_id=:'sale2'::uuid and flag_code='online_order_sale_voided' and level='red'));
select tt.as(:'p');
select tt.chk('T4 list + get show the open flag', jsonb_array_length(online_order_flags_list(1,'open'))=1 and (online_orders_list(1,'delivered',null,null,50)->0->>'flags_open') is not null
  and jsonb_array_length(online_order_get(:'pr2'::uuid)->'flags')=1);
select tt.err('T4 salesperson (no approve) cannot review', format($$select online_order_flag_review(%s,'ok')$$, (select id from online_order_flags limit 1)), 'not allowed');
select tt.as(:'s');
select tt.err('T4 review needs a note', format($$select online_order_flag_review(%s,'')$$, (select id from online_order_flags limit 1)), 'reason_required');
select tt.chk('T4 manager reviews the flag', online_order_flag_review((select id from online_order_flags limit 1),'customer informed, sale re-entered')->>'state'='reviewed');
select tt.err('T4 a flag is never deleted', $$delete from online_order_flags$$, 'append_only');
select tt.as(:'o');
select id as osale from sales where id not in (select sale_id from online_orders where sale_id is not null) and status='done' order by sold_at limit 1 \gset
select void_sale(:'osale'::uuid, 'test') is null as v2 \gset
select tt.chk('T4 voiding an ordinary sale (not from an order) works and raises no flag', (select status from sales where id=:'osale'::uuid)='void' and (select count(*) from online_order_flags)=1);
select tt.chk('T4 still only one flag after the unrelated void', (select count(*) from online_order_flags)=1);

\echo == T5 H7-style: normal flow unchanged with all switches off
select tt.as(:'p');
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'Plain', '01711000010', null, format('[{"item_id":"%s","qty":2}]', :'e1')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null)->>'id' as pl \gset
select online_order_status(:'pl'::uuid,'confirmed') is not null as pa \gset
select online_order_status(:'pl'::uuid,'packed')::text as pb \gset
select online_order_deliver(:'pl'::uuid, '[{"mode":"cash","amount":200}]')->>'status' as pd \gset
select tt.chk('T5 confirm -> pack (no warn keys) -> deliver works as before', not (:'pb'::jsonb ? 'warn') and :'pd'='delivered');

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
