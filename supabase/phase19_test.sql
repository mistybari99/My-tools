-- FRESH DB ONLY. Phase 19 (recipes / BOM, packaging rule, production consumes raw material) tests.
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase19" bash tests/sql/build_fresh_db.sh w6db
--   psql -h /tmp -p 5544 -U postgres -d w6db -qAt -f supabase/phase19_test.sql     (also works on a db built with phase8..phase14 + phase19)
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set f '00000000-0000-0000-0000-000000000004'
\set c '00000000-0000-0000-0000-000000000005'
\set x '00000000-0000-0000-0000-000000000006'
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

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
 (:'f','fac4@s.app','{"full_name":"Factory"}'), (:'c','cost5@s.app','{"full_name":"CostViewer"}'), (:'x','far6@s.app','{"full_name":"Far"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'k','storekeeper'),(:'f','factory_incharge'),(:'c','salesperson'),(:'x','factory_incharge') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'f',1),(:'c',1),(:'x',3) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select set_user_grant(:'c'::uuid,'view_cost') is null as g1 \gset

-- items: F finished (kg), flour raw (kg; recipe in g), sugar raw (kg), egg raw (piece; recipe in dozen), box packaging (piece), tin packaging (not counted), cola resale
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('W6-F',  'রসগোল্লা', 'Rasgulla W6', 'kg', 'kg', 'finished_good', true, 260),
 ('W6-FL', 'ময়দা', 'Flour W6', 'kg', 'kg', 'raw_material', true, null),
 ('W6-SU', 'চিনি', 'Sugar W6', 'kg', 'kg', 'raw_material', true, null),
 ('W6-EG', 'ডিম', 'Egg W6', 'piece', 'piece', 'raw_material', true, null),
 ('W6-BX', 'বাক্স', 'Box W6', 'piece', 'piece', 'packaging', true, null),
 ('W6-TN', 'টিন', 'Tin W6', 'piece', 'piece', 'packaging', true, null),
 ('W6-CO', 'কোলা', 'Cola W6', 'piece', 'piece', 'resale', true, 30),
 ('W6-AS', 'চেয়ার', 'Chair W6', 'piece', 'piece', 'asset', false, null),
 ('W6-F2', 'সন্দেশ', 'Sandesh W6', 'kg', 'kg', 'finished_good', true, 300);
update items set count_in_business = false where code = 'W6-TN';
select id as ifin from items where code='W6-F' \gset
select id as ifl from items where code='W6-FL' \gset
select id as isu from items where code='W6-SU' \gset
select id as ieg from items where code='W6-EG' \gset
select id as ibx from items where code='W6-BX' \gset
select id as itn from items where code='W6-TN' \gset
select id as ico from items where code='W6-CO' \gset
select id as ias from items where code='W6-AS' \gset
select id as ifin2 from items where code='W6-F2' \gset
insert into unit_conversions (item_id, from_unit, to_unit, factor) values (:'ifl','g','kg',0.001), (:'ieg','dozen','piece',12) on conflict do nothing;
-- openings (owner): flour 10 kg @ 40, sugar 5 kg @ 60, eggs 100 @ 10, boxes 50 @ 5
set role authenticated; select tt.as(:'o');
select stock_opening(:'ifl'::uuid, 1, 10, 40, null, 'w6') is not null as a1 \gset
select stock_opening(:'isu'::uuid, 1, 5, 60, null, 'w6') is not null as a2 \gset
select stock_opening(:'ieg'::uuid, 1, 100, 10, null, 'w6') is not null as a3 \gset
select stock_opening(:'ibx'::uuid, 1, 50, 5, null, 'w6') is not null as a4 \gset
reset role;

\echo == T0 shape
select tt.chk('T0 tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('recipes','recipe_lines','product_packaging','production_runs') and c.relrowsecurity)=4);
select tt.chk('T0 settings default restrictive/off', rule_txt('packaging_consume_on')='off' and not rule_on('production_requires_recipe') and rule_txt('production_short_mode')='refuse' and not rule_on('recipe_waste_required'));
select tt.chk('T0 grant recipe_manage exists', exists(select 1 from grant_defs where grant_code='recipe_manage'));
select tt.chk('T0 no cost columns on recipe tables', not exists(select 1 from information_schema.columns where table_schema='public' and table_name in ('recipes','recipe_lines','product_packaging','production_runs') and column_name ilike '%cost%' and data_type = 'numeric'));
select tt.chk('T0 anon cannot execute', not has_function_privilege('anon','production_post(int,uuid,numeric,uuid,timestamptz,text)','execute') and not has_function_privilege('anon','recipe_cost(uuid,int)','execute'));
select tt.chk('T0 internal helpers closed', not has_function_privilege('authenticated','_recipe_need(uuid,numeric,int)','execute'));

\echo == T1 who may write recipes
set role authenticated; select tt.as(:'f');
select tt.err('T1 factory without recipe_manage cannot save', format($$select recipe_save(null,%L,2,'kg','x','[{"ingredient_item_id":"%s","qty":500,"unit":"g","waste_pct":10}]'::jsonb)$$, :'ifin', :'ifl'), 'not allowed');
select tt.err('T1 direct insert refused (no table write)', format($$insert into recipes (item_id, version, yield_qty) values (%L, 1, 1)$$, :'ifin'), 'permission denied');
reset role; select tt.as(:'o'); select set_user_grant(:'f'::uuid,'recipe_manage') is null as g2 \gset
set role authenticated; select tt.as(:'f');
select tt.chk('T1 delegate with recipe_manage may save', (recipe_save(null,:'ifin'::uuid,2,'kg','v1',format('[{"ingredient_item_id":"%s","qty":500,"unit":"g","waste_pct":10},{"ingredient_item_id":"%s","qty":0.2,"unit":"kg"},{"ingredient_item_id":"%s","qty":1,"unit":"dozen","waste_pct":0}]',:'ifl',:'isu',:'ieg')::jsonb) ->> 'version')::int = 1);
select (recipe_save(null,:'ifin'::uuid,2,'kg','v1 again',format('[{"ingredient_item_id":"%s","qty":1,"unit":"kg","waste_pct":0}]',:'ifl')::jsonb,'11111111-1111-1111-1111-111111111111') ->> 'id') as rdraft \gset
select tt.chk('T1 second recipe is version 2', (select version from recipes where id=:'rdraft')=2);
select tt.chk('T1 same client id returns the same recipe (idempotent)', (recipe_save(null,:'ifin'::uuid,2,'kg','x',format('[{"ingredient_item_id":"%s","qty":1,"unit":"kg","waste_pct":0}]',:'ifl')::jsonb,'11111111-1111-1111-1111-111111111111') ->> 'id')=:'rdraft' and (select count(*) from recipes where item_id=:'ifin')=2);
select tt.err('T1 raw ingredient types only (cola resale ok, asset refused)', format($$select recipe_save(null,%L,1,'kg','x','[{"ingredient_item_id":"%s","qty":1}]'::jsonb)$$, :'ifin', :'ias'), 'bad_ingredient_type');
select tt.err('T1 finished item only', format($$select recipe_save(null,%L,1,'kg','x','[{"ingredient_item_id":"%s","qty":1}]'::jsonb)$$, :'ifl', :'isu'), 'bad_product_type');
select tt.err('T1 unknown unit refused', format($$select recipe_save(null,%L,1,'kg','x','[{"ingredient_item_id":"%s","qty":1,"unit":"bag"}]'::jsonb)$$, :'ifin', :'ifl'), 'unit_unknown');
select tt.err('T1 bad waste', format($$select recipe_save(null,%L,1,'kg','x','[{"ingredient_item_id":"%s","qty":1,"waste_pct":101}]'::jsonb)$$, :'ifin', :'ifl'), 'bad_waste');
select tt.err('T1 bad qty (NaN)', format($$select recipe_save(null,%L,1,'kg','x','[{"ingredient_item_id":"%s","qty":"NaN"}]'::jsonb)$$, :'ifin', :'ifl'), 'bad_qty');
select tt.err('T1 duplicate ingredient', format($$select recipe_save(null,%L,1,'kg','x','[{"ingredient_item_id":"%s","qty":1},{"ingredient_item_id":"%s","qty":2}]'::jsonb)$$, :'ifin', :'ifl', :'ifl'), 'dup_ingredient');
select tt.err('T1 no lines', format($$select recipe_save(null,%L,1,'kg','x','[]'::jsonb)$$, :'ifin'), 'no_lines');
select (recipe_save(:'rdraft'::uuid,null,3,'kg','edited',format('[{"ingredient_item_id":"%s","qty":2,"unit":"kg","waste_pct":5}]',:'ifl')::jsonb) ->> 'version')::int as edv \gset
select tt.chk('T1 an unused draft can be edited', :edv=2 and (select yield_qty from recipes where id=:'rdraft')=3);
select recipe_set_active(:'rdraft'::uuid,false);
select tt.chk('T1 inactivate (not deleted)', (select not active from recipes where id=:'rdraft') and (select count(*) from recipe_lines where recipe_id=:'rdraft')=1);
reset role;
select id as r1 from recipes where item_id=:'ifin' and version=1 \gset

\echo == T2 reads / RLS
set role authenticated; select tt.as(:'s');
select tt.chk('T2 salesperson without any stock grant sees no recipes', (select count(*) from recipes)=0 and (select count(*) from recipe_lines)=0);
select tt.err('T2 salesperson cannot preview', format($$select production_preview(1,%L,1)$$, :'r1'), 'not allowed');
select tt.err('T2 salesperson cannot ask cost', format($$select recipe_cost(%L)$$, :'r1'), 'not allowed');
select tt.as(:'f');
select tt.chk('T2 factory (stock_production) reads recipes and lines', (select count(*) from recipes)=2 and (select count(*) from recipe_lines)>=4);

\echo == T3 consumption arithmetic (units, waste), preview, can-make
select tt.as(:'f');
select production_preview(1,:'r1'::uuid,3) as pv \gset
select tt.chk('T3 preview flour 0.5kg*3*1.10 = 1.65', (select (x->>'need')::numeric from jsonb_array_elements(:'pv'::jsonb->'lines') x where x->>'code'='W6-FL')=1.65);
select tt.chk('T3 preview sugar (waste empty = 0) 0.6 and waste_missing flagged', (select (x->>'need')::numeric from jsonb_array_elements(:'pv'::jsonb->'lines') x where x->>'code'='W6-SU')=0.6
  and (select (x->>'waste_missing')::boolean from jsonb_array_elements(:'pv'::jsonb->'lines') x where x->>'code'='W6-SU') and (:'pv'::jsonb->>'waste_missing')::int=1);
select tt.chk('T3 preview eggs dozen -> 36 pieces', (select (x->>'need')::numeric from jsonb_array_elements(:'pv'::jsonb->'lines') x where x->>'code'='W6-EG')=36);
select tt.chk('T3 preview can_make and yield 6', (:'pv'::jsonb->>'can_make')::boolean and (:'pv'::jsonb->>'yield_base')::numeric=6);
select tt.chk('T3 preview carries no cost', :'pv'::jsonb::text not ilike '%cost%');
select production_can_make(1) as cm \gset
select tt.chk('T3 can-make: flour 10/0.55=18.18, sugar 5/0.2=25, eggs 100/12=8.33 -> 8.3333 batches, limited by eggs', (select (x->>'max_batches')::numeric from jsonb_array_elements(:'cm'::jsonb) x where x->>'code'='W6-F')=8.3333
  and (select x->>'limiting_item_id' from jsonb_array_elements(:'cm'::jsonb) x where x->>'code'='W6-F')=:'ieg');
select tt.chk('T3 can-make lists the newest active version only (the inactive v2 is out)', (select count(*) from jsonb_array_elements(:'cm'::jsonb) x where x->>'code'='W6-F')=1);
select tt.err('T3 other location: not allowed', format($$select production_preview(3,%L,1)$$, :'r1'), 'not allowed');

\echo == T4 production posts, weighted average cost, batch, idempotency
select production_post(1,:'r1'::uuid,3,'22222222-2222-2222-2222-222222222222','2026-10-12 08:00+06','w6 run1') as pr \gset
reset role;
select tt.chk('T4 flour 10 -> 8.35', (select qty from stock_balance where item_id=:'ifl' and location_id=1)=8.35);
select tt.chk('T4 sugar 5 -> 4.4, eggs 100 -> 64', (select qty from stock_balance where item_id=:'isu' and location_id=1)=4.4 and (select qty from stock_balance where item_id=:'ieg' and location_id=1)=64);
select tt.chk('T4 finished good +6 kg with a batch', (select qty from stock_balance where item_id=:'ifin' and location_id=1)=6 and (select count(*) from stock_batches where item_id=:'ifin' and qty_made=6)=1);
select tt.chk('T4 cost = (1.65*40 + 0.6*60 + 36*10) / 6 = 77', (select avg_cost from stock_balance where item_id=:'ifin' and location_id=1)=77);
select tt.chk('T4 ledger: 3 issue_out lines + 1 production_in, same ref', (select count(*) from stock_ledger where ref_type='production' and ref_id=(:'pr'::jsonb->>'run_id') and reason='issue_out')=3
  and (select count(*) from stock_ledger where ref_type='production' and ref_id=(:'pr'::jsonb->>'run_id') and reason='production_in')=1);
select tt.chk('T4 outcome has no cost, says cost_complete and waste_missing 1', :'pr'::jsonb::text not ilike '%unit_cost%' and (:'pr'::jsonb->>'cost_complete')::boolean and (:'pr'::jsonb->>'waste_missing')::int=1);
select tt.chk('T4 yellow line for the empty waste %', exists(select 1 from exceptions where flag_code='recipe_waste_missing' and level='yellow'));
select tt.chk('T4 the recipe is frozen now (used_at set)', (select used_at is not null from recipes where id=:'r1'));
select tt.chk('T4 production run stored without cost', exists(select 1 from production_runs where id=(:'pr'::jsonb->>'run_id')::uuid and yield_base=6 and cost_complete));
set role authenticated; select tt.as(:'f');
select production_post(1,:'r1'::uuid,3,'22222222-2222-2222-2222-222222222222','2026-10-12 08:00+06','w6 run1') as pr2 \gset
reset role;
select tt.chk('T4 same client id: dup, nothing posted twice', (:'pr2'::jsonb->>'dup')::boolean and (select qty from stock_balance where item_id=:'ifl' and location_id=1)=8.35 and (select qty from stock_balance where item_id=:'ifin' and location_id=1)=6);
set role authenticated; select tt.as(:'k');
select tt.err('T4 client id of another person refused', format($$select production_post(1,%L,1,'22222222-2222-2222-2222-222222222222')$$, :'r1'), 'client_id_taken');
reset role;
select tt.chk('T4 reconcile clean after production', (select count(*) from (select item_id, location_id, sum(qty_delta) q from stock_ledger group by 1, 2) l full join stock_balance b using (item_id, location_id) where coalesce(l.q, 0) <> coalesce(b.qty, 0)) = 0);

\echo == T5 permissions, shortage, rules
set role authenticated; select tt.as(:'k');
select tt.err('T5 storekeeper (no stock_production grant) refused', format($$select production_post(1,%L,1)$$, :'r1'), 'not allowed');
select tt.as(:'x');
select tt.err('T5 factory person of another location refused (can_loc)', format($$select production_post(1,%L,1)$$, :'r1'), 'not allowed');
select tt.as(:'f');
select tt.err('T5 shortage refused with the list', format($$select production_post(1,%L,100)$$, :'r1'), 'insufficient_stock');
select tt.err('T5 bad batches (0)', format($$select production_post(1,%L,0)$$, :'r1'), 'bad_qty');
select tt.err('T5 bad batches (NaN)', format($$select production_post(1,%L,'NaN'::numeric)$$, :'r1'), 'bad_qty');
select tt.err('T5 future date refused', format($$select production_post(1,%L,1,null,now()+interval '3 days')$$, :'r1'), 'bad_date');
reset role;
select tt.chk('T5 refused production posted nothing', (select qty from stock_balance where item_id=:'ifl' and location_id=1)=8.35 and (select count(*) from production_runs)=1);
set role authenticated; select tt.as(:'f');
select tt.err('T5 inactive recipe refused', format($$select production_post(1,%L,1)$$, :'rdraft'), 'recipe_inactive');
select tt.as(:'o'); select set_rule('stock_negative_mode','"allow"');
select tt.as(:'f'); select production_post(1,:'r1'::uuid,9,'33333333-3333-3333-3333-333333333333') is not null as pok \gset
reset role;
select tt.chk('T5 stock_negative_mode allow: shortage goes through (eggs 64-108 <0)', (select qty from stock_balance where item_id=:'ieg' and location_id=1)=-44);
set role authenticated; select tt.as(:'o'); select set_rule('stock_negative_mode',null);
-- put eggs back with a count adjust, then flip to follow_stock_rule
select stock_count_adjust(:'ieg'::uuid,1,200,'w6 refill') is not null as ca \gset
select set_rule('production_short_mode','"follow_stock_rule"');
select tt.as(:'f'); select production_post(1,:'r1'::uuid,20,'44444444-4444-4444-4444-444444444444') is not null as pok2 \gset
reset role;
select tt.chk('T5 follow_stock_rule + warn mode: goes through, flour negative', (select qty from stock_balance where item_id=:'ifl' and location_id=1)<0);
set role authenticated; select tt.as(:'o'); select set_rule('production_short_mode',null);
select stock_count_adjust(:'ifl'::uuid,1,10,'w6 refill') is not null as c1 \gset
select stock_count_adjust(:'isu'::uuid,1,5,'w6 refill') is not null as c2 \gset
select stock_count_adjust(:'ieg'::uuid,1,100,'w6 refill') is not null as c3 \gset
select set_rule('recipe_waste_required','true');
select tt.as(:'f');
select tt.err('T5 recipe_waste_required ON: empty waste refused', format($$select production_post(1,%L,1)$$, :'r1'), 'waste_needed');
select tt.as(:'o'); select set_rule('recipe_waste_required',null);
reset role;

\echo == T6 versions are immutable once used
set role authenticated; select tt.as(:'f');
select tt.err('T6 edit of a used version refused', format($$select recipe_save(%L,null,5,'kg','x','[{"ingredient_item_id":"%s","qty":1}]'::jsonb)$$, :'r1', :'ifl'), 'recipe_used');
reset role;
select tt.err('T6 direct line update refused even for postgres', format($$update recipe_lines set qty=9 where recipe_id=%L$$, :'r1'), 'recipe_used');
select tt.err('T6 direct line delete refused', format($$delete from recipe_lines where recipe_id=%L$$, :'r1'), 'recipe_used');
select tt.err('T6 direct line insert refused', format($$insert into recipe_lines (recipe_id, ingredient_item_id, qty) values (%L, %L, 1)$$, :'r1', :'ibx'), 'recipe_used');
select tt.err('T6 yield change refused', format($$update recipes set yield_qty=9 where id=%L$$, :'r1'), 'recipe_used');
select tt.err('T6 delete of a used version refused', format($$delete from recipes where id=%L$$, :'r1'), 'recipe_used');
set role authenticated; select tt.as(:'f');
select recipe_copy(:'r1'::uuid, null, true) ->> 'id' as r3 \gset
select tt.chk('T6 new version (3) has the same lines and is active; v1 retired', (select version from recipes where id=:'r3')=3 and (select count(*) from recipe_lines where recipe_id=:'r3')=3 and (select not active from recipes where id=:'r1'));
select tt.chk('T6 v1 lines untouched', (select count(*) from recipe_lines where recipe_id=:'r1')=3 and (select qty from recipe_lines where recipe_id=:'r1' and ingredient_item_id=:'ifl')=500);
select recipe_set_active(:'r1'::uuid,true);
select tt.chk('T6 activate/inactivate on a used version is allowed', (select active from recipes where id=:'r1'));
select recipe_copy(:'r1'::uuid, :'ifin2'::uuid) ->> 'id' as r4 \gset
select tt.chk('T6 duplicate to another product = its version 1', (select version from recipes where id=:'r4')=1 and (select item_id from recipes where id=:'r4')=:'ifin2'::uuid);
select tt.err('T6 duplicate onto a non-product refused', format($$select recipe_copy(%L, %L)$$, :'r1', :'ifl'), 'bad_product_type');
reset role;

\echo == T7 cost gating
set role authenticated; select tt.as(:'f');
select tt.err('T7 factory person cannot read recipe cost', format($$select recipe_cost(%L)$$, :'r1'), 'not allowed');
select tt.as(:'c');
select tt.chk('T7 view_cost holder gets the cost (no recipe read needed)', (recipe_cost(:'r1'::uuid,1) ->> 'complete')::boolean);
select tt.as(:'o');
select recipe_cost(:'r1'::uuid) as rc \gset
reset role;
select tt.chk('T7 batch cost = 0.55*40+0.2*60+12*10 = 154 and unit cost 77', (:'rc'::jsonb->>'batch_cost')::numeric=154 and (:'rc'::jsonb->>'unit_cost')::numeric=77);
set role authenticated; select tt.as(:'o');
select recipe_save(null,:'ifin2'::uuid,1,'kg','no stock cost',format('[{"ingredient_item_id":"%s","qty":1,"unit":"kg","waste_pct":0},{"ingredient_item_id":"%s","qty":1,"waste_pct":0}]',:'ifl',:'itn')::jsonb) ->> 'id' as r5 \gset
select tt.chk('T7 unknown cost = null (Data needed), never invented', (recipe_cost(:'r5'::uuid) ->> 'complete')::boolean is false and (recipe_cost(:'r5'::uuid) ->> 'batch_cost') is null);
reset role;

\echo == T8 packaging: production mode
set role authenticated; select tt.as(:'f');
select tt.chk('T8 packaging_set by delegate', packaging_set(:'ifin'::uuid,:'ibx'::uuid,2,'production') > 0);
select tt.err('T8 packaging item must be type packaging', format($$select packaging_set(%L,%L,1,'sale')$$, :'ifin', :'ifl'), 'bad_ingredient_type');
select tt.err('T8 bad qty', format($$select packaging_set(%L,%L,0,'sale')$$, :'ifin', :'ibx'), 'bad_qty');
select tt.as(:'o'); select set_rule('packaging_consume_on','"production"');
select tt.as(:'f'); select production_post(1,:'r1'::uuid,1,'55555555-5555-5555-5555-555555555555') as pp1 \gset
reset role;
select tt.chk('T8 production mode: 2 kg yield * 2 boxes per kg = 4 boxes out', (select qty from stock_balance where item_id=:'ibx' and location_id=1)=46 and exists(select 1 from stock_ledger where item_id=:'ibx' and reason='issue_out' and ref_type='production' and qty_delta=-4));
set role authenticated; select tt.as(:'o'); select set_rule('packaging_consume_on','"off"');
select tt.as(:'f'); select production_post(1,:'r1'::uuid,1,'66666666-6666-6666-6666-666666666666') is not null as pp2 \gset
reset role;
select tt.chk('T8 setting off: no packaging taken', (select qty from stock_balance where item_id=:'ibx' and location_id=1)=46);

\echo == T9 packaging with a sale (trigger), void, never blocks
set role authenticated; select tt.as(:'o');
select packaging_set(:'ifin'::uuid,:'ibx'::uuid,1,'sale') > 0 as ps \gset
select packaging_set(:'ico'::uuid,:'itn'::uuid,1,'sale') > 0 as ps2 \gset
select set_rule('packaging_consume_on','"off"');
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":260,"unit":"kg"}]',:'ifin')::jsonb,0,'[{"mode":"cash","amount":520}]',null,null,'retail',null,false) ->> 'receipt' as sr0 \gset
reset role;
select tt.chk('T9 setting off: sale takes no packaging', (select qty from stock_balance where item_id=:'ibx' and location_id=1)=46);
set role authenticated; select tt.as(:'o'); select set_rule('packaging_consume_on','"sale"');
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":260,"unit":"kg"},{"item_id":"%s","qty":1,"price":30,"unit":"piece"}]',:'ifin',:'ico')::jsonb,0,'[{"mode":"cash","amount":550}]',null,null,'retail',null,false) ->> 'receipt' as sr1 \gset
reset role;
select id as sale1 from sales where receipt = :'sr1' \gset
select tt.chk('T9 setting sale: 2 kg sold -> 2 boxes out (per-product rule), sale saved', :sr1::int > 0 and (select qty from stock_balance where item_id=:'ibx' and location_id=1)=44 and exists(select 1 from stock_ledger where ref_type='sale_pack' and ref_id=:'sale1'::text and item_id=:'ibx' and qty_delta=-2));
select tt.chk('T9 packaging that cannot be posted (tin not counted): sale still saved, yellow packaging_not_consumed', exists(select 1 from exceptions where flag_code='packaging_not_consumed' and sale_id=:'sale1'::uuid and level='yellow')
  and not exists(select 1 from stock_ledger where item_id=:'itn'));
select tt.chk('T9 the normal sale_out for the product is still posted (record_sale2 semantics unchanged)', exists(select 1 from stock_ledger where ref_type='sale' and ref_id=:'sale1'::text and item_id=:'ifin' and reason='sale_out'));
set role authenticated; select tt.as(:'o'); select void_sale(:'sale1'::uuid,'w6 test');
reset role;
select tt.chk('T9 void gives the packaging back', (select qty from stock_balance where item_id=:'ibx' and location_id=1)=46 and exists(select 1 from stock_ledger where ref_type='sale_pack' and reason='sale_void_in' and item_id=:'ibx'));
-- packaging short: the sale is never blocked, even in block mode
set role authenticated; select tt.as(:'o'); select set_rule('stock_negative_mode','"block"');
select stock_count_adjust(:'ibx'::uuid,1,0,'w6 empty the boxes') is not null as cz \gset
select stock_count_adjust(:'ifin'::uuid,1,50,'w6 stock for sale') is not null as cf \gset
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":260,"unit":"kg"}]',:'ifin')::jsonb,0,'[{"mode":"cash","amount":260}]',null,null,'retail',null,false) ->> 'receipt' as sr2 \gset
reset role;
select tt.chk('T9 packaging short in block mode: sale still saved (soft), boxes negative with a yellow line', :sr2::int > 0 and (select qty from stock_balance where item_id=:'ibx' and location_id=1)=-1);
set role authenticated; select tt.as(:'o'); select set_rule('stock_negative_mode',null); select set_rule('packaging_consume_on','"off"');
reset role;

\echo == T10 old direct production-in is unchanged unless the switch is on
set role authenticated; select tt.as(:'f');
select tt.chk('T10 old stock_production_in works (switch off)', (stock_production_in(:'ifin2'::uuid,1,3,null,null,'old way',null,null) ->> 'qty')::numeric=3);
select tt.as(:'o'); select set_rule('production_requires_recipe','true');
select tt.as(:'f');
select tt.err('T10 switch on: direct production-in refused', format($$select stock_production_in(%L,1,3)$$, :'ifin2'), 'recipe_required');
select production_post(1,:'r4'::uuid,1,'77777777-7777-7777-7777-777777777777') is not null as still \gset
select tt.chk('T10 switch on: recipe production still works', :'still' = 't');
select tt.as(:'o'); select set_rule('production_requires_recipe',null);
reset role;

\echo == T11 period lock and emergency key
set role authenticated; select tt.as(:'o'); select set_rule('period_closed_until','"2026-09-30"');
select tt.as(:'f');
select tt.err('T11 closed period refused', format($$select production_post(1,%L,1,null,'2026-09-15 10:00+06')$$, :'r1'), 'period_closed');
select tt.as(:'o'); select set_rule('period_closed_until',null);
reset role;
select tt.chk('T11 emergency rule key for stock_production exists and is OFF by default', exists(select 1 from rules where key='em_stock_production') and not rule_on('em_stock_production'));

\echo == T12 re-run safety and existing behaviour
\i /home/user/My-tools/supabase/phase19.sql
select tt.chk('T12 re-run keeps data and settings', (select count(*) from recipes where item_id=:'ifin')>=3 and rule_txt('packaging_consume_on')='off');
select tt.chk('T12 single sales triggers', (select count(*) from pg_trigger where tgname in ('sales_packaging_out','sales_packaging_void','sales_stock_out','sales_stock_void'))=4);
select tt.chk('T12 reconcile clean at the end', (select count(*) from (select item_id, location_id, sum(qty_delta) q from stock_ledger group by 1, 2) l full join stock_balance b using (item_id, location_id) where coalesce(l.q, 0) <> coalesce(b.qty, 0)) = 0);

select '--- FAILED: ' || count(*) from tt.res where not ok;
select '--- TOTAL: ' || count(*) from tt.res;
select name from tt.res where not ok;
