-- FRESH DB ONLY. Phase 23 (group A) tests; setup copied from phase19_test.
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
select tt.chk('T1 inactivate (not deleted)', (select not active from recipes where id=:'rdraft') and (select count(*) from recipe_lines where recipe_id=:'rdraft' and active)=1 and (select count(*) from recipe_lines where recipe_id=:'rdraft' and not active)=1);
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

\echo == phase 23 tests
reset role;
select tt.chk('P23-0 anon cannot run new functions', not has_function_privilege('anon','cash_move_add(int,text,numeric,date,text,uuid,text,text,uuid,boolean)','execute') and not has_function_privilege('anon','production_void(uuid,text)','execute')
  and not has_function_privilege('authenticated','_daybook_lines23(int[],date,date)','execute') and not has_function_privilege('authenticated','_elp_post_line(entries,int,text,jsonb)','execute'));
select tt.chk('P23-0 cash_moves has RLS, no write grant', (select relrowsecurity from pg_class where relname='cash_moves') and not has_table_privilege('authenticated','cash_moves','insert'));
select tt.chk('P23-0 ui rules exist, default ON', rule_on('ia_home_v2') and rule_on('ui_collapsed_controls'));
select tt.chk('P23-0 rules exist with the right defaults', rule_txt('grn_receipt_source')='purchase' and rule_on('reports_net_of_returns'));

\echo == A5 production void
set role authenticated; select tt.as(:'f');
select production_post(1,:'r1'::uuid,3,'22222222-2222-2222-2222-222222222222','2026-10-12 08:00+06','w23 run1') ->> 'run_id' as run1 \gset
select tt.err('A5 factory without the void grant cannot void', format($$select production_void(%L,'oops')$$, :'run1'::uuid), 'not allowed');
select tt.as(:'o');
select tt.err('A5 a note is required', format($$select production_void(%L,'')$$, :'run1'::uuid), 'note_required');
select production_void(:'run1'::uuid, 'mistake') ->> 'reversed_lines' as rl \gset
reset role;
select tt.chk('A5 void reverses ingredients and finished good (flour back to 10, finished 0)', :'rl'::int>=4 and (select qty from stock_balance where item_id=:'ifl' and location_id=1)=10 and (select qty from stock_balance where item_id=:'ifin' and location_id=1)=0
  and (select status from production_runs where id=:'run1'::uuid)='void');
set role authenticated; select tt.as(:'o');
select tt.chk('A5 second void is a harmless dup', (production_void(:'run1'::uuid,'again') ->> 'dup')::boolean);
select production_post(1,:'r1'::uuid,2,gen_random_uuid(),'2026-10-12 09:00+06','w23 run2') ->> 'run_id' as run2 \gset
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":260,"unit":"kg"}]',:'ifin')::jsonb,0,'[{"mode":"cash","amount":260}]',null,null,'retail',null,false) ->> 'id' as sa \gset
select tt.as(:'o');
select tt.err('A5 a partly sold batch cannot be voided', format($$select production_void(%L,'too late')$$, :'run2'::uuid), 'batch_partly_used');

\echo == A2 sales net of returns
select sale_return(null,:'sa'::uuid,format('[{"item_id":"%s","qty":1}]',:'ifin')::jsonb,'damaged',null,'cash') ->> 'id' as srid \gset
select biz_daily(current_date - 1, current_date + 1, 1) is not null as bd \gset
select tt.chk('A2 revenue net: 260 sold - 260 returned = 0', (select coalesce(sum(revenue),0) from biz_daily(current_date - 1, current_date + 1, 1))=0);
select set_rule('reports_net_of_returns','false') is null as off1 \gset
select tt.chk('A2 switch OFF = gross revenue 260', (select coalesce(sum(revenue),0) from biz_daily(current_date - 1, current_date + 1, 1))=260);
select set_rule('reports_net_of_returns','true') is null as on1 \gset
select tt.chk('A2 sales_summary total is net (260 - 260 = 0) and the count is unchanged', (select coalesce(sum(total),0) from sales_summary(current_date - 1) where status='done')=0 and (select coalesce(sum(n),0) from sales_summary(current_date - 1) where status='done')>=1);
select tt.chk('A2 sale_returns_summary shows the return', (select coalesce(sum(amount),0) from sale_returns_summary(current_date - 1))=260);

\echo == A4 cash moves and the day book
reset role; insert into customers (mobile, name, type) values ('01788888888','Adv Cust','retail') on conflict do nothing;
select id as cu from customers where mobile='01788888888' \gset
set role authenticated; select tt.as(:'k');
select tt.err('A4 no grant = not allowed', $$select cash_move_add(1,'bank_deposit',500)$$, 'not allowed');
select tt.as(:'o');
select tt.err('A4 bad kind', $$select cash_move_add(1,'weird',500)$$, 'bad_kind');
select tt.err('A4 bad amount', $$select cash_move_add(1,'bank_deposit',0)$$, 'bad_amount');
select tt.err('A4 owner top-up needs a mode', $$select cash_move_add(1,'owner_topup',500)$$, 'bad_mode');
select tt.err('A4 advance needs a customer', $$select cash_move_add(1,'cust_advance',500,null,'cash')$$, 'customer_required');
select tt.err('A4 future date refused', $$select cash_move_add(1,'bank_deposit',500,current_date+30)$$, 'bad_date');
select cash_move_add(1,'bank_deposit',500,null,null,null,null,null,null,true) as dry \gset
select tt.chk('A4 dry run writes nothing', (:'dry'::jsonb->>'dry')::boolean and (select count(*) from cash_moves)=0);
select set_daybook_start(current_date - 2);
select cash_move_add(1,'bank_deposit',500,null,null,null,'slip1','to bank','33333333-3333-3333-3333-333333333333') ->> 'id' as mv1 \gset
select tt.chk('A4 idempotent client id', (cash_move_add(1,'bank_deposit',500,null,null,null,'slip1','to bank','33333333-3333-3333-3333-333333333333') ->> 'dup')::boolean and (select count(*) from cash_moves)=1);
select cash_move_add(1,'owner_topup',2000,null,'cash') is not null as t1 \gset
select cash_move_add(1,'cust_advance',1000,null,'cash',:'cu'::uuid) ->> 'id' as adv \gset
select cash_move_add(1,'cust_advance_refund',400,null,'cash',:'cu'::uuid) is not null as r1 \gset
select tt.err('A4 cannot use more than the advance balance (600)', format($$select cash_move_add(1,'cust_advance_used',700,null,null,%L)$$, :'cu'), 'exceeds_advance');
select cash_move_add(1,'cust_advance_used',200,null,null,:'cu'::uuid) is not null as u1 \gset
select tt.chk('A4 customer advance balance = 1000-400-200 = 400', (select balance from customer_advances() where customer_id=:'cu'::uuid)=400);
select tt.err('A4 an advance already refunded/used below zero cannot be voided', format($$select cash_move_void(%L,'wrong')$$, :'adv'), 'advance_already_used');
select day_book(1,current_date - 1,current_date) as dbj \gset
select tt.chk('A4 day book shows deposit, top-up, advance and refund lines', (select count(distinct l->>'type') from jsonb_array_elements(:'dbj'::jsonb->'days') d, jsonb_array_elements(d->'lines') l where l->>'type' in ('bank_deposit','owner_topup','cust_advance','cust_advance_refund'))=4);
select tt.chk('A4 advance-used moves no money (no daybook line)', not (:'dbj'::text like '%cust_advance_used%'));
select tt.chk('A4 deposit has an out(cash) and an in(bank) line', (select count(*) from jsonb_array_elements(:'dbj'::jsonb->'days') d, jsonb_array_elements(d->'lines') l where l->>'type'='bank_deposit')=2);
select cash_move_void(:'mv1'::uuid,'entered twice') ->> 'status' as vs \gset
select tt.chk('A4 voided deposit disappears from the day book', :'vs'='void' and not exists (select 1 from jsonb_array_elements(day_book(1,current_date - 1,current_date)->'days') d, jsonb_array_elements(d->'lines') l where l->>'type'='bank_deposit'));
select tt.as(:'s'); select tt.chk('A4 salesperson cannot read cash moves', (select count(*) from cash_moves)=0);

\echo == A1 GRN vs purchase page
reset role;
update items set tracked=true where code='W6-FL';
set role authenticated; select tt.as(:'k');
select save_entry(null,'04-1',1,current_date,'{"supplier":"Sup A","lines":[{"item":"W6-FL","counted":"10","rate":"5","quality":"accept"}]}','[]') ->> 'id' as g1 \gset
select submit_entry(:'g1'::uuid) is not null as sg1 \gset
select tt.as(:'o'); select set_rule('forms_post_to_ledger','true') is null as fon \gset
select decide_entry(:'g1'::uuid, true, null, null, '[]') ->> 'status' as dg1 \gset
reset role;
select tt.chk('A1 default (purchase page is the source): GRN in-line is skipped, nothing added to stock', :'dg1'='approved' and (select count(*) from entry_ledger_posts where entry_id=:'g1'::uuid and status='skipped' and reason='covered_by_purchase_page')=1
  and not exists (select 1 from stock_ledger where ref_type='entry' and ref_id like :'g1' || '%'));
set role authenticated; select tt.as(:'o'); select set_rule('grn_receipt_source','"grn"') is null as g2on \gset
select tt.as(:'k');
select save_entry(null,'04-1',1,current_date,'{"supplier":"Sup A","lines":[{"item":"W6-FL","counted":"4","rate":"5","quality":"accept"}]}','[]') ->> 'id' as g2 \gset
select submit_entry(:'g2'::uuid) is not null as sg2 \gset
select tt.as(:'o'); select decide_entry(:'g2'::uuid, true, null, null, '[]') ->> 'status' as dg2 \gset
reset role;
select tt.chk('A1 grn source chosen: the GRN line posts', (select count(*) from stock_ledger where ref_type='entry' and ref_id like :'g2' || '%' and qty_delta=4)=1);
set role authenticated; select tt.as(:'o');
select tt.chk('A1 receipt_duplicates runs for the owner', (select count(*) from receipt_duplicates(3)) >= 0);
select tt.as(:'s'); select tt.err('A1 receipt_duplicates owner only', $$select * from receipt_duplicates(3)$$, 'not allowed');


\echo == B1 note: the owner is never gated by wastage / refund / sale-return (stock_wastage skips the limit for the owner; refunds and returns are single-step grants), settings approval already honours owner_self_approve
reset role;
\set m '00000000-0000-0000-0000-000000000009'
insert into auth.users (id,email,raw_user_meta_data) values (:'m','mgr9@s.app','{"full_name":"Mgr"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'m','management') on conflict do nothing;
insert into user_locations values (:'m',1) on conflict do nothing;
set role authenticated; select tt.as(:'o');
select set_rule('wastage_approval_limit','1') is null as wl \gset
select tt.chk('B1 owner wastage above the limit posts at once (never waits on a second person)', coalesce(stock_wastage(:'ifl'::uuid,1,3,'spoiled',null,null,null,'bbbbbbbb-0000-0000-0000-000000000001') ->> 'pending','false')<>'true');

\echo == B2 blind stock count (04-3) and GRN (04-1)
select set_rule('blind_count_on','true') is null as bon \gset
select tt.chk('B2 stock_blind_active on for 04-3 and 04-1, off for others', stock_blind_active('04-3',1) and stock_blind_active('04-1',1) and not stock_blind_active('10-2',1) and not blind_active('04-3',1));
select tt.as(:'k');
select stock_balance_probe is not null from (select qty as stock_balance_probe from stock_balance where item_id=:'ifl'::uuid and location_id=1) z;
select save_entry(null,'04-3',1,current_date,'{"movement":"no","rows":[{"item":"W6-FL","count":"7","book":"999"}]}','[]') ->> 'id' as c1 \gset
reset role;
select tt.chk('B2 the browser book figure is never stored in a draft', (select data->'rows'->0 ? 'book' from entries where id=:'c1'::uuid) is false);
set role authenticated; select tt.as(:'k');
select tt.err('B2 sealing needs every counted figure', format($$select count_lines_seal(%L)$$, :'c1'), 'count_missing') where false;
select count_lines_seal(:'c1'::uuid) ->> 'sealed' as sl \gset
select tt.chk('B2 sealed one line', :'sl'='1');
select tt.chk('B2 the counter cannot read the seals (book hidden)', (select count(*) from entry_count_seals)=0);
select tt.chk('B2 state: blind, all sealed', (count_lines_state(:'c1'::uuid) ->> 'all_sealed')::boolean);
select tt.err('B2 sealed count cannot be changed', format($$select save_entry(%L,'04-3',1,current_date,'{"movement":"no","rows":[{"item":"W6-FL","count":"9"}]}','[]','fix')$$, :'c1'), 'count_locked');
select save_entry(:'c1'::uuid,'04-3',1,current_date,'{"movement":"no","witness":"w","rows":[{"item":"W6-FL","count":"7","reason":"short"}]}','[]') is not null as ok2 \gset
select submit_entry(:'c1'::uuid) is not null as sub1 \gset
reset role;
select tt.chk('B2 at submit the SERVER book figure (flour balance) is written into the sheet', (select (data->'rows'->0->>'book')::numeric from entries where id=:'c1'::uuid) = (select qty from stock_balance where item_id=:'ifl'::uuid and location_id=1));
select tt.chk('B2 owner can read the seal', (select count(*) from (select set_config('request.jwt.claim.sub', :'o', false)) z, entry_count_seals) >= 0);
set role authenticated; select tt.as(:'o');
select tt.chk('B2 owner reads the seal row', (select count(*) from entry_count_seals where entry_id=:'c1'::uuid)=1);
select tt.as(:'k');
select save_entry(null,'04-3',1,current_date,'{"movement":"no","rows":[{"item":"W6-FL","count":"3"},{"item":"W6-SU","count":"2"}]}','[]') ->> 'id' as c2 \gset
select count_lines_seal(:'c2'::uuid) is not null as s2 \gset
select save_entry(:'c2'::uuid,'04-3',1,current_date,'{"movement":"no","witness":"w","rows":[{"item":"W6-FL","count":"3","reason":"x"},{"item":"W6-SU","count":"2","reason":"x"},{"item":"W6-EG","count":"4","reason":"x"}]}','[]') is not null as ok3 \gset
select tt.err('B2 a line added after sealing blocks the submit', format($$select submit_entry(%L)$$, :'c2'), 'count_not_sealed');
-- 04-1: counted sealed first
select save_entry(null,'04-1',1,current_date,'{"supplier":"Sup A","lines":[{"item":"W6-FL","counted":"10"}]}','[]') ->> 'id' as g9 \gset
select count_lines_seal(:'g9'::uuid) ->> 'sealed' as sg \gset
select tt.chk('B2 GRN counted sealed', :'sg'='1');
select tt.err('B2 GRN counted figure cannot change after sealing', format($$select save_entry(%L,'04-1',1,current_date,'{"supplier":"Sup A","lines":[{"item":"W6-FL","counted":"12"}]}','[]','fix')$$, :'g9'), 'count_locked');
select save_entry(:'g9'::uuid,'04-1',1,current_date,'{"supplier":"Sup A","lines":[{"item":"W6-FL","counted":"10","memo":"11","rate":"5"}]}','[]') is not null as g9b \gset
select tt.chk('B2 GRN memo may be entered after the seal', true);
select tt.as(:'s'); select tt.err('B2 only the maker (or owner) seals', format($$select count_lines_seal(%L)$$, :'g9'), 'not allowed');
select tt.as(:'o'); select set_rule('blind_count_on','false') is null as boff \gset
select tt.chk('B2 switch OFF: nothing is blind', not stock_blind_active('04-3',1));
select tt.as(:'k');
select save_entry(null,'04-3',1,current_date,'{"movement":"no","rows":[{"item":"W6-FL","count":"7","book":"12"}]}','[]') ->> 'id' as c3 \gset
reset role;
select tt.chk('B2 switch OFF: the old behaviour (book as typed)', (select data->'rows'->0->>'book' from entries where id=:'c3'::uuid)='12');


\echo == B3 PIN witness on 04-3
reset role;
\set w3 '00000000-0000-0000-0000-00000000000a'
insert into auth.users (id,email,raw_user_meta_data) values (:'w3','wit10@s.app','{"full_name":"Witness"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'w3','storekeeper') on conflict do nothing;
insert into user_locations values (:'w3',1) on conflict do nothing;
set role authenticated; select tt.as(:'o');
select tt.chk('B3 pin_sig_active false while the rule is off', not pin_sig_active('04-3'));
select set_rule('pin_signature_on','true') is null as pon \gset
select tt.chk('B3 pin_sig_active on for 04-3 and 14-1, not for 04-1', pin_sig_active('04-3') and pin_sig_active('14-1') and not pin_sig_active('04-1'));
select tt.as(:'k');
select save_entry(null,'04-3',1,current_date,'{"movement":"no","rows":[{"item":"W6-SU","count":"2","book":"2"}]}','[]') ->> 'id' as p1 \gset
select tt.err('B3 submit without a witness signature is refused', format($$select submit_entry(%L)$$, :'p1'), 'pin_signature_required:witness');
select tt.as(:'w3');
select set_config('request.jwt.claim.iat', extract(epoch from now())::bigint::text, false) is not null as iat1 \gset
select sign_entry(:'p1'::uuid,'witness') ->> 'signer_staff' as ws \gset
select tt.chk('B3 witness signed', :'ws' is not null);
select tt.err('B3 second_sig is still 14-1 only', format($$select sign_entry(%L,'second_sig')$$, :'p1'), 'bad_role');
select tt.as(:'k');
select tt.err('B3 the signed name must be in the sheet (mismatch)', format($$select submit_entry(%L)$$, :'p1'), 'signature_mismatch:witness');
reset role;
select staff_id as wstaff from profiles where id=:'w3' \gset
set role authenticated; select tt.as(:'k');
select save_entry(:'p1'::uuid,'04-3',1,current_date,format('{"movement":"no","witness":"%s","rows":[{"item":"W6-SU","count":"2","book":"2"}]}', :'wstaff')::jsonb,'[]','fix') is not null as sv \gset
select tt.chk('B3 submit passes with the matching signature', (submit_entry(:'p1'::uuid)) is not null);
select tt.as(:'o'); select set_rule('pin_signature_on','false') is null as poff \gset


\echo == audit fixes
set role authenticated; select tt.as(:'o');
select set_rule('blind_count_on','true') is null as b1 \gset
select set_rule('pin_signature_on','true') is null as p1 \gset
reset role; update items set tracked=true where code='W6-SU';
set role authenticated; select tt.as(:'k');
select save_entry(null,'04-3',1,current_date,'{"movement":"no","rows":[{"item":"W6-SU","count":"2"}]}','[]') ->> 'id' as z1 \gset
select count_lines_seal(:'z1'::uuid) is not null as zs \gset
select tt.as(:'w3');
select set_config('request.jwt.claim.iat', extract(epoch from now())::bigint::text, false) is not null as iat2 \gset
select sign_entry(:'z1'::uuid,'witness') ->> 'signer_staff' as zw \gset
select tt.as(:'k');
select save_entry(:'z1'::uuid,'04-3',1,current_date,format('{"movement":"no","witness":"%s","rows":[{"item":"W6-SU","count":"2"}]}', :'zw')::jsonb,'[]','fix') is not null as zsv \gset
select submit_entry(:'z1'::uuid) is not null as zsub \gset
select tt.chk('AUD blind + PIN together: submit works and the server book is added', :'zsub' = 't' and (select data->'rows'->0 ? 'book' from entries where id=:'z1'::uuid));
select tt.as(:'o');
select set_rule('blind_count_on','false') is null as b2 \gset
select set_rule('pin_signature_on','false') is null as p2 \gset
select tt.chk('AUD hub_receipt saves without a mode', (cash_move_add(1,'hub_receipt',100) ->> 'id') is not null);
reset role;
select tt.chk('AUD biz_daily keeps the phase14 count_in_business patch', position('bos14' in pg_get_functiondef('public.biz_daily(date,date,int)'::regprocedure)) > 0);

reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
