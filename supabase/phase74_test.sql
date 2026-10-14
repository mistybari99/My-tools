-- FRESH DB ONLY. Phase 74 tests (step C: costing + overhead). Needs phase8..phase71, phase73, phase74.
--   ORDER="phase8 ... phase71 phase73 phase74" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> 74db
--   psql -h /tmp -p 5544 -U postgres -d 74db -qAt -f supabase/phase74_test.sql | grep -E 'FAIL|RESULT'
-- All amounts below are test data. No person names. Pool months are relative to today so the test can run on any date.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set f '00000000-0000-0000-0000-000000000002'
\set cv '00000000-0000-0000-0000-000000000003'
\set nn '00000000-0000-0000-0000-000000000004'
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
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.mo(p_back int) returns date language sql stable as $$ select (date_trunc('month', now() at time zone 'Asia/Dhaka') - make_interval(months => p_back))::date $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'f','fac2@s.app','{"full_name":"Factory"}'), (:'cv','cost3@s.app','{"full_name":"CostViewer"}'), (:'nn','none4@s.app','{"full_name":"Nobody"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'f','factory_incharge'),(:'cv','storekeeper'),(:'nn','salesperson') on conflict do nothing;
insert into user_locations values (:'f',1),(:'cv',1),(:'nn',1) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select set_user_grant(:'cv'::uuid,'view_cost') is null as g1 \gset
select set_user_grant(:'cv'::uuid,'recipe_manage') is null as g2 \gset
select set_user_grant(:'f'::uuid,'recipe_manage') is null as g3 \gset

insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('C-F',  'রসগোল্লা', 'Rasgulla C', 'kg', 'kg', 'finished_good', true, 260),
 ('C-F2', 'সন্দেশ', 'Sandesh C', 'kg', 'kg', 'finished_good', true, 300),
 ('C-FL', 'ময়দা', 'Flour C', 'kg', 'kg', 'raw_material', true, null),
 ('C-SU', 'চিনি', 'Sugar C', 'kg', 'kg', 'raw_material', true, null),
 ('C-GG', 'ঘি', 'Ghee C', 'kg', 'kg', 'raw_material', true, null),
 ('C-BX', 'বাক্স', 'Box C', 'piece', 'piece', 'packaging', true, null),
 ('C-F3', 'কেক', 'Cake C', 'piece', 'piece', 'finished_good', true, 500);
select id as ifin from items where code='C-F' \gset
select id as ifin2 from items where code='C-F2' \gset
select id as ifl from items where code='C-FL' \gset
select id as isu from items where code='C-SU' \gset
select id as igg from items where code='C-GG' \gset
select id as ibx from items where code='C-BX' \gset
select id as ifin3 from items where code='C-F3' \gset
set role authenticated; select tt.as(:'o');
select stock_opening(:'ifl'::uuid, 1, 1000, 40, null, 'c') is not null as so1 \gset
select stock_opening(:'isu'::uuid, 1, 1000, 60, null, 'c') is not null as so2 \gset
select stock_opening(:'ibx'::uuid, 1, 500, 5, null, 'c') is not null as so3 \gset
select stock_opening(:'igg'::uuid, 1, 100, 50, null, 'c') is not null as so4 \gset
select (recipe_save(null, :'ifin'::uuid, 10, null, 'C v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'ifl','qty',6,'waste_pct',10), jsonb_build_object('ingredient_item_id',:'isu','qty',3,'waste_pct',0)))->>'id')::uuid as rc \gset
select (recipe_save(null, :'ifin3'::uuid, 12, null, 'C3 v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'igg','qty',1,'waste_pct',0)))->>'id')::uuid as rp \gset
select (recipe_save(null, :'ifin2'::uuid, 1, null, 'C2 v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'igg','qty',1,'waste_pct',0)))->>'id')::uuid as rg \gset

\echo == T0 shape
select tt.chk('T0 new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('cost_component_types','recipe_cost_components','factory_cost_pools','location_cost_cfg') and c.relrowsecurity)=4);
select tt.chk('T0 8 builtin types; smoothing windows are settings (gas/electricity 3, repair 12, licence yearly)', (select count(*) from cost_component_types where builtin)=8
  and (select smooth||avg_months from cost_component_types where code='gas')='avg_n3' and (select smooth||avg_months from cost_component_types where code='machine_repair')='avg_n12' and (select smooth from cost_component_types where code='licence_fee')='yearly12');
select tt.chk('T0 defaults = today: gap/yield thresholds blank, manual-reason switch off, no location is in a cost mode', rule_num('cost_gap_warn_pct') is null and rule_num('yield_variance_warn_pct') is null and not rule_on('production_manual_needs_reason') and not exists (select 1 from location_cost_cfg));
select tt.chk('T0 production_post: the 7-arg core (p_actual_yield) + the 6-arg wrapper both exist, not ambiguous', (select count(*) from pg_proc where proname='production_post')=2 and (select count(*) from pg_proc where proname='production_post' and pronargs=7 and pronargdefaults=0)=1);
select tt.chk('T0 bos74 tags in recipe_cost, production_post, stock_production_in, _acct_docs', (select count(*) from pg_proc where proname in ('recipe_cost','production_post','stock_production_in','_acct_docs') and position('bos74' in pg_get_functiondef(oid))>0)=4);
select tt.chk('T0 mapping overhead_absorbed -> account 5950 (credit-normal expense)', exists (select 1 from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='overhead_absorbed' and a.code='5950' and a.normal_side='credit' and a.type='expense'));
select tt.chk('T0 anon cannot execute; helpers closed', not has_function_privilege('anon','recipe_cost(uuid,int)','execute') and not has_function_privilege('anon','production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)','execute')
  and not has_function_privilege('authenticated','_conv_cost(uuid,int,numeric,numeric,date,text)','execute') and not has_function_privilege('authenticated','_pool_rate(int,date,text)','execute'));
select tt.chk('T0 the new production_runs columns are NOT readable by browsers', not has_column_privilege('authenticated','public.production_runs','material_cost','select') and not has_column_privilege('authenticated','public.production_runs','conversion_cost','select')
  and not has_column_privilege('authenticated','public.production_runs','unit_cost','select') and has_column_privilege('authenticated','public.production_runs','yield_base','select'));

\echo == T1 default (location mode off) = today's behaviour; actual yield (C7)
select tt.chk('T1 recipe_cost with mode off: material only (6.6x40 + 3x60)/10 = 44.4, conversion 0', (recipe_cost(:'rc'::uuid,1)->>'unit_cost')::numeric=44.4 and (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=0 and recipe_cost(:'rc'::uuid,1)->>'conversion_mode'='off');
select production_post(1, :'rc'::uuid, 1, gen_random_uuid())->>'run_id' as run1 \gset
reset role;
select tt.chk('T1 run 1: FG ledger cost 44.4 (as before phase74), snapshot material 444, conversion 0, unit 44.4', (select unit_cost from stock_ledger where ref_type='production' and ref_id=:'run1' and reason='production_in')=44.4
  and (select material_cost=444 and conversion_cost=0 and unit_cost=44.4 and std_cost=44.4 and actual_cost=44.4 and conversion_mode='off' from production_runs where id=:'run1'::uuid));
set role authenticated; select tt.as(:'o');
select set_rule('yield_variance_warn_pct','5'::jsonb) is null as yw \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid(), null, 'actual yield test', 9)->>'run_id' as run2 \gset
reset role;
select tt.chk('T1 actual yield 9 of 10: 9 kg booked, unit cost 444/9 = 49.333333 (+11.1%), std cost stays 44.4, variance -10%', (select qty_delta from stock_ledger where ref_type='production' and ref_id=:'run2' and reason='production_in')=9
  and (select unit_cost from stock_ledger where ref_type='production' and ref_id=:'run2' and reason='production_in')=49.333333 and (select std_cost=44.4 and actual_cost=49.333333 and yield_std=10 and yield_actual=9 and yield_var_pct=-10 and yield_base=9 from production_runs where id=:'run2'::uuid));
select tt.chk('T1 yield variance above the setting raises a yellow flag', exists (select 1 from exceptions where flag_code='yield_variance' and level='yellow'));
set role authenticated; select tt.as(:'o');
select tt.err('T1 actual yield 0 refused', format($$select production_post(1,'%s',1,null,null,null,0)$$, :'rc'), 'bad_qty');
select tt.chk('T1 same client id again = dup', (production_post(1, :'rc'::uuid, 1, 'dddddddd-0000-0000-0000-000000000001'::uuid)->>'run_id') is not null and (production_post(1, :'rc'::uuid, 1, 'dddddddd-0000-0000-0000-000000000001'::uuid)->>'dup')::boolean);
select production_void((select id from production_runs where client_id='dddddddd-0000-0000-0000-000000000001'), 'test cleanup') is not null as vd0 \gset

\echo == T2 recipe mode: overhead 100 per batch, yield 10 => unit cost +10 (C1, C3)
select tt.as(:'cv'); select tt.err('T2 a cost-right holder who is not the owner cannot switch the mode', $$select loc_cost_cfg_set(1,'recipe')$$, 'not allowed');
select tt.as(:'o'); select loc_cost_cfg_set(1,'recipe') is null as m1 \gset
select tt.chk('T2 recipe mode with NO components yet: flagged incomplete (reason no_components), conversion 0', (recipe_cost(:'rc'::uuid,1)->>'conversion_complete')::boolean is false and recipe_cost(:'rc'::uuid,1)->>'conversion_reason'='no_components' and recipe_cost(:'rc'::uuid,1)->>'conversion_flag'='রূপান্তর খরচ অসম্পূর্ণ');
select recipe_cost_component_set(:'rc'::uuid, 'labour', 'per_batch', 100, null, null, 'test overhead', 'eeeeeeee-0000-0000-0000-000000000001'::uuid) ->> 'id' as cc1 \gset
select tt.chk('T2 same client id = dup, one active row', (recipe_cost_component_set(:'rc'::uuid, 'labour', 'per_batch', 100, null, null, null, 'eeeeeeee-0000-0000-0000-000000000001'::uuid)->>'dup')::boolean and (select count(*) from recipe_cost_components where recipe_id=:'rc'::uuid and active)=1);
select tt.chk('T2 recipe_cost: raw 444 | packaging 0 | conversion 100 as separate rows; unit cost 54.4', (select (x->>'amount')::numeric from jsonb_array_elements(recipe_cost(:'rc'::uuid,1)->'rows') x where x->>'row'='raw')=444
  and (select (x->>'amount')::numeric from jsonb_array_elements(recipe_cost(:'rc'::uuid,1)->'rows') x where x->>'row'='packaging')=0 and (select (x->>'amount')::numeric from jsonb_array_elements(recipe_cost(:'rc'::uuid,1)->'rows') x where x->>'row'='conversion')=100
  and (recipe_cost(:'rc'::uuid,1)->>'unit_cost')::numeric=54.4 and (recipe_cost(:'rc'::uuid,1)->>'batch_cost')::numeric=544);
select production_post(1, :'rc'::uuid, 1, gen_random_uuid())->>'run_id' as run3 \gset
reset role;
select tt.chk('T2 posted run: unit cost = 44.4 + 100/10 = 54.4 (+10); FG ledger carries it', (select unit_cost from stock_ledger where ref_type='production' and ref_id=:'run3' and reason='production_in')=54.4
  and (select material_cost=444 and conversion_cost=100 and unit_cost=54.4 and std_cost=54.4 and conversion_mode='recipe' and conversion_complete from production_runs where id=:'run3'::uuid));
select tt.chk('T2 recipe_cost unit cost == the posted run unit cost', (select (public.recipe_cost(:'rc'::uuid,1)->>'unit_cost')::numeric from (select set_config('request.jwt.claim.sub', :'o', false)) s)=(select unit_cost from production_runs where id=:'run3'::uuid));
set role authenticated; select tt.as(:'o');
select tt.chk('T2 recipe_cost without a location uses the recipe rate (aggregate path): unit 54.4', (recipe_cost(:'rc'::uuid)->>'unit_cost')::numeric=54.4);
-- 3 batches: per_batch scales (3 x 100 / 30 = +10)
select production_post(1, :'rc'::uuid, 3, gen_random_uuid())->>'run_id' as run3b \gset
reset role;
select tt.chk('T2 three batches: conversion 300 on 30 kg, still +10 per kg', (select conversion_cost=300 and unit_cost=54.4 from production_runs where id=:'run3b'::uuid));
set role authenticated; select tt.as(:'o');

\echo == T3 void reverses at original cost
select (select qty from stock_balance where item_id=:'ifin' and location_id=1) as fgq0 \gset
select production_void(:'run3'::uuid, 'wrong batch') is not null as vd \gset
reset role;
select tt.chk('T3 void: FG ledger reversal at the ORIGINAL cost 54.4 (incl. conversion), ingredients returned', exists (select 1 from stock_ledger l where l.ref_type='production' and l.ref_id=:'run3' and l.reason='reversal' and l.item_id=:'ifin' and l.unit_cost=54.4 and l.qty_delta=-10)
  and (select count(*) from stock_ledger where ref_type='production' and ref_id=:'run3' and reason='reversal')=3);
select tt.chk('T3 FG stock down by 10 after the void', (select qty from stock_balance where item_id=:'ifin' and location_id=1)=:fgq0 - 10);
set role authenticated; select tt.as(:'o');

\echo == T4 other bases (per unit, per labour-hour) and the labour suggestion (C0.4 / C1)
select recipe_cost_component_set(:'rc'::uuid, 'gas', 'per_unit', 1.5) is not null as c_gas \gset
select tt.chk('T4 gas per base unit 1.5 x 10 kg = +15 batch cost (conversion 115 with labour 100)', (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=115);
select recipe_cost_component_set(:'rc'::uuid, 'labour', 'per_labour_hour', 50) is not null as c_lab \gset
select tt.chk('T4 per labour-hour with NO typed hours: incomplete, labour counts 0 (the step suggestion never flows in by itself)', (recipe_cost(:'rc'::uuid,1)->>'conversion_complete')::boolean is false and (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=15);
select recipe_steps_save(:'rc'::uuid, '[{"step_name":"cook","minutes":60,"people":2}]'::jsonb) is not null as st \gset
select tt.chk('T4 steps now suggest 2 labour-hours - but the conversion cost is unchanged (still 15, still incomplete)', (recipe_cost_components_get(:'rc'::uuid)->'suggested_labour_hours')::numeric=2 and (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=15 and (recipe_cost(:'rc'::uuid,1)->>'conversion_complete')::boolean is false);
select recipe_cost_component_set(:'rc'::uuid, 'labour', 'per_labour_hour', 50, 2) is not null as c_lab2 \gset
select tt.chk('T4 owner types the hours (2 per batch): 50 x 2 = 100 -> conversion 115, complete', (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=115 and (recipe_cost(:'rc'::uuid,1)->>'conversion_complete')::boolean);
select tt.chk('T4 previous values kept: the first labour row (100 per batch) is inactive, not deleted', (select count(*) from recipe_cost_components where recipe_id=:'rc'::uuid and component_type='labour')=3 and (select count(*) from recipe_cost_components where recipe_id=:'rc'::uuid and component_type='labour' and active)=1
  and exists (select 1 from recipe_cost_components where id=:'cc1'::bigint and not active and amount=100));
select tt.err('T4 type "other" needs its typed note', format($$select recipe_cost_component_set('%s','other','per_batch',5)$$, :'rc'), 'type_note_needed');
select tt.err('T4 unknown type refused', format($$select recipe_cost_component_set('%s','nope','per_batch',5)$$, :'rc'), 'unknown_type');
select tt.err('T4 negative amount refused', format($$select recipe_cost_component_set('%s','gas','per_batch',-1)$$, :'rc'), 'bad_cost');
select cost_type_add('ঝাল মসলা ভাড়া', 'Spice grinder hire') ->> 'code' as xt \gset
select tt.chk('T4 owner-added type is usable on a recipe', (recipe_cost_component_set(:'rc'::uuid, :'xt', 'per_batch', 7) ->> 'id') is not null and (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=122);
select recipe_cost_component_retire((select id from recipe_cost_components where recipe_id=:'rc'::uuid and component_type=:'xt' and active)) is null as rt \gset

\echo == T5 blank amount => রূপান্তর খরচ অসম্পূর্ণ
select recipe_cost_component_set(:'rc'::uuid, 'electricity', 'per_batch', null) is not null as c_el \gset
select tt.chk('T5 components_get flags the blank amount', (recipe_cost_components_get(:'rc'::uuid)->>'incomplete')::boolean and recipe_cost_components_get(:'rc'::uuid)->>'flag'='রূপান্তর খরচ অসম্পূর্ণ'
  and exists (select 1 from jsonb_array_elements(recipe_cost_components_get(:'rc'::uuid)->'components') x where x->>'type'='electricity' and (x->>'incomplete')::boolean));
select tt.chk('T5 recipe_cost: partial conversion (known part only) + flag', (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=115 and (recipe_cost(:'rc'::uuid,1)->>'conversion_complete')::boolean is false and recipe_cost(:'rc'::uuid,1)->>'conversion_flag'='রূপান্তর খরচ অসম্পূর্ণ');
select production_post(1, :'rc'::uuid, 1, gen_random_uuid())->>'run_id' as run5 \gset
select tt.chk('T5 production posts with the known part and says so (conversion_complete false in the answer)', (select (production_post(1, :'rc'::uuid, 0.5, gen_random_uuid())->>'conversion_complete')::boolean) is false);
reset role;
select tt.chk('T5 yellow exception conversion_incomplete written; run snapshot not complete', exists (select 1 from exceptions where flag_code='conversion_incomplete' and level='yellow') and (select not conversion_complete from production_runs where id=:'run5'::uuid));
set role authenticated; select tt.as(:'o');
select recipe_cost_component_set(:'rc'::uuid, 'electricity', 'per_batch', 12) is not null as c_el2 \gset
select tt.chk('T5 filled: complete again, conversion 127 (labour 100 + gas 15 + electricity 12)', (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=127 and (recipe_cost(:'rc'::uuid,1)->>'conversion_complete')::boolean);

\echo == T6 cost secrecy (C1, C3)
select tt.as(:'f');
select tt.err('T6 factory in-charge (no cost right): recipe_cost refused', format($$select recipe_cost('%s',1)$$, :'rc'), 'not allowed');
select tt.err('T6 production_run_costs refused', $$select production_run_costs(1, null, null)$$, 'not allowed');
select tt.err('T6 the new run columns are denied on a direct select', $$select material_cost from public.production_runs$$, 'permission denied');
select tt.chk('T6 recipe_cost_components rows are invisible without the cost right', (select count(*) from recipe_cost_components)=0 and (select count(*) from factory_cost_pools)=0);
select tt.err('T6 cannot write a component', format($$select recipe_cost_component_set('%s','gas','per_batch',1)$$, :'rc'), 'not allowed');
select tt.err('T6 cannot read the components', format($$select recipe_cost_components_get('%s')$$, :'rc'), 'not allowed');
select tt.err('T6 cannot write a pool', $$select pool_set(1, tt.mo(0), 'labour', 1)$$, 'not allowed');
select tt.err('T6 cannot read the true-up', $$select overhead_trueup(1, tt.mo(0))$$, 'not allowed');
select tt.chk('T6 production_post answer carries no cost keys for him', not (production_post(1, :'rc'::uuid, 0.1, gen_random_uuid()) ?| array['cost_complete','conversion_complete','unit_cost']));
select tt.as(:'cv');
select tt.chk('T6 cost-right holder sees the run costs and the components', jsonb_array_length(production_run_costs(1, null, null))>=3 and (recipe_cost_components_get(:'rc'::uuid)->'components')::text like '%gas%' and (select count(*) from recipe_cost_components)>=1);
select tt.chk('T6 cost-right holder may edit a component (audited)', (recipe_cost_component_set(:'rc'::uuid, 'gas', 'per_unit', 1.5, null, null, 'same value') ->> 'id') is not null);
select tt.as(:'nn'); select tt.err('T6 salesperson: nothing', format($$select recipe_cost('%s',1)$$, :'rc'), 'not allowed');
select tt.as(:'o');
select tt.chk('T6 component changes are in the audit log', (select count(*) from audit_log where table_name='recipe_cost_components')>=5);

\echo == T7 C4: packaging in recipe_cost and in the run (same _recipe_need)
select set_rule('packaging_consume_on','"production"'::jsonb) is null as pk1 \gset
select packaging_set(:'ifin'::uuid, :'ibx'::uuid, 2, 'production') is not null as pk2 \gset
select tt.chk('T7 recipe_cost packaging row = 2 boxes/kg x 10 kg x 5 = 100; raw row still 444; the line says kind packaging', (select (x->>'amount')::numeric from jsonb_array_elements(recipe_cost(:'rc'::uuid,1)->'rows') x where x->>'row'='packaging')=100
  and (recipe_cost(:'rc'::uuid,1)->>'raw_cost')::numeric=444 and exists (select 1 from jsonb_array_elements(recipe_cost(:'rc'::uuid,1)->'lines') l where l->>'kind'='packaging'));
select recipe_cost(:'rc'::uuid,1)->>'unit_cost' as rcu \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid())->>'run_id' as run7 \gset
reset role;
select tt.chk('T7 run unit cost == recipe_cost unit cost (both include packaging): (444 + 100 + 127)/10 = 67.1', (select unit_cost from production_runs where id=:'run7'::uuid)=:'rcu'::numeric and :'rcu'::numeric=67.1);
select tt.chk('T7 the run issued the 20 boxes (packaging consumed in the same transaction)', (select -sum(qty_delta) from stock_ledger where ref_type='production' and ref_id=:'run7' and item_id=:'ibx')=20);
set role authenticated; select tt.as(:'o');
select set_rule('packaging_consume_on','"off"'::jsonb) is null as pk3 \gset

\echo == T8 C5: today's purchase price in its own row, gap % and a yellow warning; no effect on the booked cost
reset role;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at) values (:'igg', 1, 100, 70, 'purchase_in', 'test', 'p1', now());
select (select avg_cost from stock_balance where item_id=:'igg' and location_id=1) as gavg \gset
set role authenticated; select tt.as(:'o');
select tt.chk('T8 avg cost of ghee is the blend (100@50 + 100@70 = 60)', :'gavg'::numeric=60);
select tt.chk('T8 recipe_cost: average basis 60 | today basis 70 | gap +16.67% | no warning while the threshold is blank', (recipe_cost(:'rg'::uuid,1)->>'material_cost')::numeric=60 and (recipe_cost(:'rg'::uuid,1)->'today'->>'material_cost')::numeric=70
  and (recipe_cost(:'rg'::uuid,1)->'today'->>'gap_pct')::numeric=16.67 and not (recipe_cost(:'rg'::uuid,1)->'today'->>'gap_warn')::boolean and (recipe_cost(:'rg'::uuid,1)->'lines'->0->>'today_unit_cost')::numeric=70);
select set_rule('cost_gap_warn_pct','10'::jsonb) is null as gw \gset
select tt.chk('T8 threshold 10 -> yellow warning flag', (recipe_cost(:'rg'::uuid,1)->'today'->>'gap_warn')::boolean);
select set_rule('cost_gap_warn_pct','20'::jsonb) is null as gw2 \gset
select tt.chk('T8 threshold 20 -> no warning (gap 16.67)', not (recipe_cost(:'rg'::uuid,1)->'today'->>'gap_warn')::boolean);
select production_post(1, :'rg'::uuid, 1, gen_random_uuid())->>'run_id' as run8 \gset
reset role;
select tt.chk('T8 booked cost uses the AVERAGE (60), not today''s price', (select unit_cost from production_runs where id=:'run8'::uuid)=60 and (select unit_cost from stock_ledger where ref_type='production' and ref_id=:'run8' and reason='production_in')=60);
set role authenticated; select tt.as(:'o');

\echo == T9 C2 pool mode: rate = pool / NORMAL output, smoothing windows, slow month
select loc_cost_cfg_set(1,'pool') is null as pm \gset
select tt.chk('T9 pool mode with the normal output BLANK: incomplete (normal_output_blank), conversion 0', (recipe_cost(:'rc'::uuid,1)->>'conversion_complete')::boolean is false and recipe_cost(:'rc'::uuid,1)->>'conversion_reason'='normal_output_blank' and (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=0);
select loc_cost_cfg_set(1,'pool',1000) is null as pm2 \gset
select tt.chk('T9 normal output set but no pool entered: incomplete (no_pool) - never guessed', recipe_cost(:'rc'::uuid,1)->>'conversion_reason'='no_pool' and (recipe_cost(:'rc'::uuid,1)->>'conversion_complete')::boolean is false);
select pool_set(1, tt.mo(0), 'labour', 5000) ->> 'id' as pl1 \gset
select tt.chk('T9 one pool: labour 5000 / normal 1000 = 5 per kg -> 10 kg run = 50, unit +5', (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=50 and (recipe_cost(:'rc'::uuid,1)->>'conversion_complete')::boolean and (recipe_cost(:'rc'::uuid,1)->>'unit_cost')::numeric=49.4);
select pool_set(1, tt.mo(2), 'gas', 3000) is not null as pg1 \gset
select pool_set(1, tt.mo(1), 'gas', 6000) is not null as pg2 \gset
select tt.chk('T9 gas = 3-month average inside the window; current month has no bill = a gap, NOT filled by a guess: (3000+6000+0)/3 = 3000 -> 3 per kg', exists (select 1 from jsonb_array_elements(recipe_cost(:'rc'::uuid,1)->'conversion_detail') d where d->>'type'='gas' and (d->>'rate')::numeric=3 and (d->>'gap_months')::int=1 and (d->>'months')::int=3));
select pool_set(1, tt.mo(1), 'licence_fee', 12000, 'year') is not null as pf \gset
select tt.chk('T9 yearly licence 12000 / 12 = 1000 a month -> 1 per kg', exists (select 1 from jsonb_array_elements(recipe_cost(:'rc'::uuid,1)->'conversion_detail') d where d->>'type'='licence_fee' and (d->>'rate')::numeric=1));
select pool_set(1, tt.mo(3), 'machine_repair', 24000, 'month', true, 'big one-off overhaul') is not null as pr \gset
select tt.chk('T9 repair = trailing average over its window (12) since the first entry: 24000 / 4 months = 6000 -> 6 per kg', exists (select 1 from jsonb_array_elements(recipe_cost(:'rc'::uuid,1)->'conversion_detail') d where d->>'type'='machine_repair' and (d->>'rate')::numeric=6 and (d->>'months')::int=4));
select tt.chk('T9 a piece-based product cannot use the per-kg pool rate: incomplete (pool_unit_not_kg), never a wrong number', recipe_cost(:'rp'::uuid,1)->>'conversion_reason'='pool_unit_not_kg' and (recipe_cost(:'rp'::uuid,1)->>'conversion_cost')::numeric=0 and (recipe_cost(:'rp'::uuid,1)->>'conversion_complete')::boolean is false);
select tt.chk('T9 total rate 5 + 3 + 1 + 6 = 15 per kg -> 150 on 10 kg, unit cost 44.4 + 15 = 59.4', (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=150 and (recipe_cost(:'rc'::uuid,1)->>'unit_cost')::numeric=59.4);
select production_post(1, :'rc'::uuid, 1, gen_random_uuid())->>'run_id' as run9 \gset
select production_post(1, :'rc'::uuid, 0.2, gen_random_uuid())->>'run_id' as run9s \gset
reset role;
select tt.chk('T9 posted: unit cost 59.4; a SLOW month (2 kg run) costs the same per kg - the product cost does not jump', (select unit_cost from production_runs where id=:'run9'::uuid)=59.4 and (select unit_cost from production_runs where id=:'run9s'::uuid)=59.4
  and (select conversion_cost from production_runs where id=:'run9s'::uuid)=30);
set role authenticated; select tt.as(:'o');
select pool_set(1, tt.mo(0), 'labour', 5200) is not null as pl_re \gset
select tt.chk('T9 pool rows: the previous manual value is kept (inactive), one active', (select count(*) from factory_cost_pools where location_id=1 and component_type='labour' and month=tt.mo(0))=2 and (select count(*) from factory_cost_pools where location_id=1 and component_type='labour' and month=tt.mo(0) and active)=1);
select pool_set(1, tt.mo(0), 'labour', 5000) is not null as pl_back \gset
select tt.err('T9 negative pool refused', $$select pool_set(1, tt.mo(0), 'gas', -1)$$, 'bad_cost');
select tt.err('T9 unknown type refused', $$select pool_set(1, tt.mo(0), 'zzz', 1)$$, 'unknown_type');
select pool_set(1, tt.mo(0), 'depreciation', 100, 'month', false, null, 'ffffffff-0000-0000-0000-000000000001'::uuid) ->> 'id' as pd1 \gset
select tt.chk('T9 pool_set same client id = dup', (pool_set(1, tt.mo(0), 'depreciation', 100, 'month', false, null, 'ffffffff-0000-0000-0000-000000000001'::uuid)->>'dup')::boolean);

\echo == T10 C6 true-up: ACTUAL factory cost vs ABSORBED; the gap is the row unabsorbed overhead
select overhead_trueup(1, tt.mo(0)) as tu \gset
select tt.chk('T10 actual this month: labour 5000 + licence 1000 + depreciation 100 (gas/repair have no bill this month = no actual) = 6100', (:'tu'::jsonb->>'actual_total')::numeric=6100);
reset role; select coalesce(sum(conversion_cost),0) as exp_abs from production_runs where location_id=1 and status='done' and (made_at at time zone 'Asia/Dhaka')::date >= tt.mo(0) \gset
select coalesce(sum((d->>'amount')::numeric),0) as exp_lab from production_runs r, jsonb_array_elements(r.conversion_detail) d where r.location_id=1 and r.status='done' and (r.made_at at time zone 'Asia/Dhaka')::date >= tt.mo(0) and d->>'type'='labour' \gset
set role authenticated; select tt.as(:'o');
select tt.chk('T10 absorbed = the conversion cost of the DONE runs of the month (voided runs excluded)', abs((:'tu'::jsonb->>'absorbed_total')::numeric - :exp_abs) < 0.01 and :exp_abs > 180);
select tt.chk('T10 unabsorbed overhead row = actual - absorbed, labelled অনাবশোষিত ওভারহেড', abs((:'tu'::jsonb->>'unabsorbed_overhead')::numeric - (6100 - :exp_abs)) < 0.01 and :'tu'::jsonb->>'unabsorbed_label_bn'='অনাবশোষিত ওভারহেড');
select tt.chk('T10 per type: labour unabsorbed = 5000 - absorbed labour; gas has no actual this month (null)', abs((select (x->>'unabsorbed')::numeric from jsonb_array_elements(:'tu'::jsonb->'rows') x where x->>'type'='labour') - (5000 - :exp_lab)) < 0.01
  and (select (x->>'actual') is null from jsonb_array_elements(:'tu'::jsonb->'rows') x where x->>'type'='gas'));
select tt.chk('T10 showroom / admin are not absorbed: the report says so and has no showroom rows', :'tu'::jsonb->>'note' like '%not absorbed%');
select tt.as(:'cv'); select tt.err('T10 a cost-right holder sees only his own locations (location 2 refused)', $$select overhead_trueup(2, tt.mo(0))$$, 'not allowed'); select tt.as(:'o');

\echo == T11 C6 journal: Dr 1310 / Cr 1320 (+1330) + overhead_absorbed; balanced; void reverses
select acct_set_start(tt.today() - 1) is not null as st1 \gset
select set_rule('accounting_on','true'::jsonb) is null as acc \gset
select acct_post_pending(false)->>'posted' as pn \gset
reset role;
select je.id as je3 from journal_entries je where je.source_type='production' and je.source_id=:'run9' and je.reverses_id is null \gset
select tt.chk('T11 the production journal of run 9 exists and is balanced (debit = credit)', (select sum(debit) = sum(credit) and sum(debit) > 0 from journal_lines where entry_id=:je3));
select tt.chk('T11 Dr 1310 finished goods = material 444 + conversion 150 = 594', (select l.debit from journal_lines l join coa_accounts a on a.id=l.account_id where l.entry_id=:je3 and a.code='1310')=594);
select tt.chk('T11 Cr 1320 raw materials = 444; Cr overhead_absorbed (5950) = 150', (select l.credit from journal_lines l join coa_accounts a on a.id=l.account_id where l.entry_id=:je3 and a.code='1320')=444
  and (select l.credit from journal_lines l join coa_accounts a on a.id=l.account_id where l.entry_id=:je3 and a.code='5950')=150);
select tt.chk('T11 a run with conversion in recipe mode (run 7, packaging) also balances', (select sum(debit)=sum(credit) from journal_lines l join journal_entries j on j.id=l.entry_id where j.source_type='production' and j.source_id=:'run7' and j.reverses_id is null));
select tt.chk('T11 a mode-off run (run 1) still posts exactly as before: no overhead line', (select count(*) from journal_lines l join journal_entries j on j.id=l.entry_id join coa_accounts a on a.id=l.account_id where j.source_type='production' and j.source_id=:'run1' and a.code='5950')=0
  and (select sum(debit)=sum(credit) and sum(debit)=444 from journal_lines l join journal_entries j on j.id=l.entry_id where j.source_type='production' and j.source_id=:'run1' and j.reverses_id is null));
select tt.chk('T11 the trial balance is balanced and 5950 carries a credit balance (reduces expenses in the P&L)', (select (acct_trial_balance(tt.today()-1, tt.today())->>'balanced')::boolean) and (select coalesce(sum(l.credit-l.debit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='5950')>0);
set role authenticated; select tt.as(:'o');
select production_void(:'run9'::uuid, 'journal reversal test') is not null as vd9 \gset
select acct_post_pending(false)->>'posted' as pn2 \gset
reset role;
select tt.chk('T11 after the void the journal is reversed: net overhead_absorbed from run 9 = 0', (select coalesce(sum(l.credit - l.debit),0) from journal_lines l join journal_entries j on j.id=l.entry_id join coa_accounts a on a.id=l.account_id where a.code='5950' and j.source_type='production' and j.source_id=:'run9')=0
  and exists (select 1 from journal_entries r join journal_entries o on o.id=r.reverses_id where o.source_type='production' and o.source_id=:'run9'));
set role authenticated; select tt.as(:'o');
select overhead_trueup(1, tt.mo(0))->>'absorbed_total' as abs_after \gset
select tt.chk('T11 true-up after the void: absorbed dropped by the voided run (150)', abs((:exp_abs - :abs_after) - 150) < 0.01);

\echo == T12 C7 05-4 yield test = a SUGGESTION only
reset role;
insert into entries (form_code, location_id, serial, entry_date, status, data, flags, created_by, created_staff) values
  ('05-4', 1, 9701, tt.today(), 'approved', jsonb_build_object('item','C-F','b', jsonb_build_array(jsonb_build_object('date',tt.today()::text,'input','100','good','90','second','5','waste','5'), jsonb_build_object('date',tt.today()::text,'input','100','good','90','second','5','waste','5'))), '[]', :'o', 'st');
set role authenticated; select tt.as(:'o');
select tt.chk('T12 suggestion = waste 5 / (90+5+5) = 5%, source serial shown, applied false', (recipe_yield_suggestion(:'rc'::uuid)->>'suggested_waste_pct')::numeric=5 and (recipe_yield_suggestion(:'rc'::uuid)->>'source_serial')='9701' and not (recipe_yield_suggestion(:'rc'::uuid)->>'applied')::boolean);
select tt.chk('T12 the recipe itself is unchanged (flour waste still 10)', (select waste_pct from recipe_lines where recipe_id=:'rc'::uuid and ingredient_item_id=:'ifl' and active)=10);
select tt.chk('T12 no 05-4 for the product: suggestion null', (recipe_yield_suggestion(:'rg'::uuid)->>'suggested_waste_pct') is null);

\echo == T13 C8 the manual production path
select tt.chk('T13 default (switch off): direct production-in works with no note, exactly as today', (stock_production_in(:'ifin'::uuid, 1, 5, null, null, null, gen_random_uuid(), null) ->> 'ledger_id') is not null);
select stock_production_in(:'ifin'::uuid, 1, 5, null, null, null, gen_random_uuid(), 99) ->> 'ledger_id' as spi \gset
select tt.chk('T13 a typed cost raises the yellow flag production_manual_cost', :'spi' is not null and exists (select 1 from exceptions where flag_code='production_manual_cost' and level='yellow'));
select set_rule('production_manual_needs_reason','true'::jsonb) is null as mr \gset
select tt.err('T13 switch on: no reason = refused', format($$select stock_production_in('%s'::uuid, 1, 5)$$, :'ifin'), 'note_required');
select tt.chk('T13 switch on: with a reason it posts', (stock_production_in(:'ifin'::uuid, 1, 5, null, null, 'recipe sheet was lost', gen_random_uuid(), null) ->> 'ledger_id') is not null);
select set_rule('production_requires_recipe','true'::jsonb) is null as rr \gset
select tt.err('T13 production_requires_recipe ON (recommended): the manual path is closed', format($$select stock_production_in('%s'::uuid, 1, 5, null, null, 'x')$$, :'ifin'), 'recipe_required');
select set_rule('production_requires_recipe','false'::jsonb) is null as rr0 \gset
select set_rule('production_manual_needs_reason','false'::jsonb) is null as mr0 \gset

\echo == T14 off again = today
select loc_cost_cfg_set(1,'off') is null as off1 \gset
select tt.chk('T14 mode back to off: conversion 0, unit cost = material only (44.4), no flag', (recipe_cost(:'rc'::uuid,1)->>'unit_cost')::numeric=44.4 and (recipe_cost(:'rc'::uuid,1)->>'conversion_cost')::numeric=0 and (recipe_cost(:'rc'::uuid,1)->>'conversion_complete')::boolean);
select tt.chk('T14 owner-only audit of the mode changes', (select count(*) from audit_log where table_name='location_cost_cfg')>=4);

reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select 'FAIL ' || name from tt.res where not ok;
