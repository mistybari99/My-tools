-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase83_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase509_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY. Phase 509 tests (step E-b: form vs screen, expense double count, transit shortage, offline POS).
--   Build: base phase8..phase71 + 73 74 75 78 (skip 72), then phase509. Run: psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase509_test.sql | grep -E "FAIL|RESULT"
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
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
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager'),(:'k','storekeeper') on conflict do nothing;
\set c '00000000-0000-0000-0000-000000000004'
\set m '00000000-0000-0000-0000-000000000005'
\set g '00000000-0000-0000-0000-000000000006'
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
 (:'c','cash4@s.app','{"full_name":"Cashier"}'), (:'m','mgr5@s.app','{"full_name":"Mgr2"}'), (:'g','gm6@s.app','{"full_name":"GM"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'k','storekeeper'),(:'c','salesperson'),(:'m','showroom_manager'),(:'g','management') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'c',1),(:'m',1),(:'g',1) on conflict do nothing;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant execute on function tt.today() to authenticated, anon;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('E-FL','Flour E','Flour E','kg','kg','raw_material',true,null), ('E-SU','Sugar E','Sugar E','kg','kg','raw_material',true,null),
 ('E-CK','Cake E','Cake E','kg','kg','finished_good',true,300), ('E-NR','NoRecipe E','NoRecipe E','kg','kg','finished_good',true,100),
 ('E-SL','Sale E','Sale E','kg','kg','finished_good',true,100), ('E-TR','Transit E','Transit E','kg','kg','raw_material',true,null);
select id as ifl from items where code='E-FL' \gset
select id as isu from items where code='E-SU' \gset
select id as ick from items where code='E-CK' \gset
select id as inr from items where code='E-NR' \gset
select id as isl from items where code='E-SL' \gset
select id as itr from items where code='E-TR' \gset
select set_config('request.jwt.claim.sub', :'o', false);
select set_user_grant(:'o'::uuid,'recipe_manage') is null as g0 \gset
select (recipe_save(null, :'ick'::uuid, 10, null, 'E v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'ifl','qty',6,'waste_pct',0), jsonb_build_object('ingredient_item_id',:'isu','qty',3,'waste_pct',0)))->>'id')::uuid as rc \gset
select tt.as(:'o');
select path_switch_set('stock_transfer',0,true,true,'a') is not null as swt \gset
select stock_opening(:'ifl'::uuid, 1, 100, 40, null, 'e') is not null as o1 \gset
select stock_opening(:'isu'::uuid, 1, 50, 20, null, 'e') is not null as o2 \gset
select stock_opening(:'itr'::uuid, 1, 100, 40, null, 'e') is not null as o3 \gset
select stock_opening(:'isl'::uuid, 1, 2, 60, null, 'e') is not null as o4 \gset
select set_rule('forms_post_to_ledger','true') is null as ron \gset

\echo == T0 shape
select tt.chk('T0 new switches exist with today''s defaults', (select default_value from rules where key='form_051_mode')='"reference"'::jsonb and (select default_value from rules where key='transit_short_mode')='"keep_in_transit"'::jsonb
  and (select default_value from rules where key='transit_open_hours') is null and (select default_value from rules where key='offline_soft_stock')='false'::jsonb);
select tt.chk('T0 transit_loss is a ledger reason', pg_get_constraintdef((select oid from pg_constraint where conname='stock_ledger_reason_check')) like '%transit_loss%' and pg_get_constraintdef((select oid from pg_constraint where conname='stock_ledger_reason_check')) like '%count_adjust%');
select tt.chk('T0 re-created functions carry bos83', position('bos83' in pg_get_functiondef('public._elp_post_line(entries,int,text,jsonb)'::regprocedure))>0 and position('bos83' in pg_get_functiondef('public.dup_suspects(date,date)'::regprocedure))>0
  and position('bos83' in pg_get_functiondef('public.stock_receive_transfer(uuid,numeric,text)'::regprocedure))>0 and position('bos83' in pg_get_functiondef('public.urgent_alerts(timestamptz)'::regprocedure))>0 and position('bos83' in pg_get_functiondef('public._sale_stock_out()'::regprocedure))>0);
select tt.chk('T0 internals closed to browsers, browser functions open', not has_function_privilege('authenticated','public._transit_loss83(uuid,numeric,text)','execute') and has_function_privilege('authenticated','public.pos_replay_override(jsonb,text,text)','execute')
  and not has_function_privilege('anon','public.pos_replay_override(jsonb,text,text)','execute') and not has_function_privilege('anon','public.unmatched_forms(date,date,int)','execute'));
select tt.chk('T0 failed-card and override tables: RLS on, no write grants', (select relrowsecurity from pg_class where relname='pos_failed_cards') and (select relrowsecurity from pg_class where relname='pos_replay_log')
  and not has_table_privilege('authenticated','pos_failed_cards','insert') and not has_table_privilege('authenticated','pos_replay_log','insert'));

select tt.chk('T0 English text of the new switches / grant has no Bangla letters, bn and mix exist', not exists (select 1 from rules where key in ('form_051_mode','transit_short_mode','transit_open_hours','offline_soft_stock') and (label_en ~ '[\u0980-\u09FF]' or hint_en ~ '[\u0980-\u09FF]' or label_mix is null or hint_mix is null or label_bn is null))
  and not exists (select 1 from grant_defs where grant_code='pos_replay_override' and label_en ~ '[\u0980-\u09FF]'));

\echo == E5.1 reference mode (default = today): finished goods enter with NO cost, nothing consumed, but now FLAGGED
select path_switch_set('production',0,true,true,'b') is not null as sw1 \gset
select save_entry(null,'05-1',1,tt.today(),jsonb_build_object('shift','m','output',jsonb_build_array(jsonb_build_object('item','E-CK','qty','5'))),'[]') ->> 'id' as f1 \gset
update entries set status='submitted' where id=:'f1'::uuid;
update entries set status='approved' where id=:'f1'::uuid;
select tt.chk('E5.1 05-1 line posted: +5 cake, cost NULL', (select qty_delta from stock_ledger where ref_type='entry' and item_id=:'ick' and reason='production_in')=5 and (select unit_cost from stock_ledger where ref_type='entry' and item_id=:'ick' and reason='production_in') is null);
select tt.chk('E5.1 ingredients NOT consumed in reference mode (flour 100, sugar 50)', (select qty from stock_balance where item_id=:'ifl' and location_id=1)=100 and (select qty from stock_balance where item_id=:'isu' and location_id=1)=50);
select tt.chk('E5.1 yellow flag form051_cost_null raised once', (select count(*) from exceptions where entry_id=:'f1'::uuid and flag_code='form051_cost_null' and level='yellow')=1);

\echo == E5.2 post mode: the sheet takes the recipe ingredients out at average cost
select set_rule('form_051_mode','"post"') is null as m1 \gset
select save_entry(null,'05-1',1,tt.today(),jsonb_build_object('shift','m','output',jsonb_build_array(jsonb_build_object('item','E-CK','qty','5'))),'[]') ->> 'id' as f2 \gset
update entries set status='submitted' where id=:'f2'::uuid;
update entries set status='approved' where id=:'f2'::uuid;
select tt.chk('E5.2 5 kg of cake = 0.5 batch: flour 100-3=97, sugar 50-1.5=48.5', (select qty from stock_balance where item_id=:'ifl' and location_id=1)=97 and (select qty from stock_balance where item_id=:'isu' and location_id=1)=48.5);
select tt.chk('E5.2 finished goods cost = (3x40 + 1.5x20)/5 = 30', (select unit_cost from stock_ledger where ref_id like :'f2'||'%' and reason='production_in')=30);
select tt.chk('E5.2 the ingredient rows are issue_out of the same entry ref', (select count(*) from stock_ledger where ref_type='entry' and ref_id like :'f2'||'%' and reason='issue_out')=2);
select tt.chk('E5.2 no cost-null flag for this sheet', (select count(*) from exceptions where entry_id=:'f2'::uuid and flag_code='form051_cost_null')=0);
select save_entry(null,'05-1',1,tt.today(),jsonb_build_object('shift','m','output',jsonb_build_array(jsonb_build_object('item','E-NR','qty','2'))),'[]') ->> 'id' as f3 \gset
update entries set status='submitted' where id=:'f3'::uuid;
update entries set status='approved' where id=:'f3'::uuid;
select tt.chk('E5.2 an item with no recipe is NOT minted from nothing: line failed, no stock', (select status from entry_ledger_posts where entry_id=:'f3'::uuid)='failed' and (select reason from entry_ledger_posts where entry_id=:'f3'::uuid) like 'no_recipe_for_051%'
  and (select count(*) from stock_ledger where item_id=:'inr')=0);
select save_entry(null,'05-1',1,tt.today(),jsonb_build_object('shift','m','output',jsonb_build_array(jsonb_build_object('item','E-CK','qty','200'))),'[]') ->> 'id' as f3b \gset
select set_rule('stock_negative_mode','"block"') is null as nb \gset
update entries set status='submitted' where id=:'f3b'::uuid;
select tt.as(:'g');
update entries set status='approved' where id=:'f3b'::uuid;
select tt.as(:'o');
select tt.chk('E5.2 not enough flour: whole line fails, nothing half-posted (flour/sugar/cake unchanged)', (select status from entry_ledger_posts where entry_id=:'f3b'::uuid)='failed' and (select qty from stock_balance where item_id=:'ifl' and location_id=1)=97
  and (select qty from stock_balance where item_id=:'ick' and location_id=1)=10);
select set_rule('stock_negative_mode','"warn"') is null as nb2 \gset

\echo == E5.3 refuse mode
select set_rule('form_051_mode','"refuse"') is null as m2 \gset
select save_entry(null,'05-1',1,tt.today(),jsonb_build_object('shift','m','output',jsonb_build_array(jsonb_build_object('item','E-CK','qty','7'))),'[]') ->> 'id' as f4 \gset
update entries set status='submitted' where id=:'f4'::uuid;
update entries set status='approved' where id=:'f4'::uuid;
select tt.chk('E5.3 refuse: line skipped form051_not_a_source, stock unchanged (cake still 10)', (select reason from entry_ledger_posts where entry_id=:'f4'::uuid)='form051_not_a_source' and (select qty from stock_balance where item_id=:'ick' and location_id=1)=10);
select set_rule('form_051_mode','"reference"') is null as m3 \gset

\echo == E5.4 screen is the record: slip with no screen record is listed, then matched
select path_switch_set('production',0,true,true,'a') is not null as sw2 \gset
select path_switch_set('stock_issue',0,true,true,'a') is not null as sw3 \gset
select save_entry(null,'05-1',1,tt.today(),jsonb_build_object('shift','m','output',jsonb_build_array(jsonb_build_object('item','E-CK','qty','4'))),'[]') ->> 'id' as f5 \gset
update entries set status='submitted' where id=:'f5'::uuid;
update entries set status='approved' where id=:'f5'::uuid;
select save_entry(null,'04-2',1,tt.today(),'{"purpose":"prod","not_overnight":true,"lines":[{"item":"E-FL","issued":"2","ret":"0"}]}','[]') ->> 'id' as f6 \gset
update entries set status='submitted' where id=:'f6'::uuid;
update entries set status='approved' where id=:'f6'::uuid;
select tt.chk('E5.4 both slips skipped as covered_by_screen, stock unchanged', (select reason from entry_ledger_posts where entry_id=:'f5'::uuid)='covered_by_screen' and (select reason from entry_ledger_posts where entry_id=:'f6'::uuid)='covered_by_screen' and (select qty from stock_balance where item_id=:'ifl' and location_id=1)=97);
select tt.chk('E5.4 a PENDING shadow link exists for each slip (domain, screen record owed)', (select count(*) from shadow_links where primary_type='entries' and shadow_type='stock_screen' and state='pending' and primary_id in (:'f5',:'f6'))=2
  and (select domain from shadow_links where primary_id=:'f5')='production' and (select domain from shadow_links where primary_id=:'f6')='stock_issue');
select unmatched_forms(tt.today(), tt.today(), 1) as u1 \gset
select tt.chk('E5.4 unmatched_forms lists both lines (labels in 3 languages, English has no Bangla)', jsonb_array_length(:'u1'::jsonb->'rows')=2 and (:'u1'::jsonb->>'lines_unmatched')='2' and (:'u1'::jsonb->>'label_bn')='স্ক্রিন-রেকর্ডহীন ফর্ম' and (:'u1'::jsonb->>'label_en') !~ '[^\x01-\x7F]' and (:'u1'::jsonb->>'label_mix') is not null);
select tt.chk('E5.4 owner-only widen: storekeeper (no approve right on these forms) sees nothing', (select jsonb_array_length(unmatched_forms(tt.today(), tt.today(), 1)->'rows') from (select tt.as(:'k')) z)=0);
select tt.as(:'o');
select stock_issue(:'ifl'::uuid, 1, 2, null, 'screen issue') is not null as si \gset
select tt.chk('E5.4 after the screen issue the 04-2 slip is matched, the 05-1 slip is still listed', jsonb_array_length(unmatched_forms(tt.today(), tt.today(), 1)->'rows')=1 and (unmatched_forms(tt.today(), tt.today(), 1)->'rows'->0->>'form_code')='05-1');
select unmatched_forms_sync() ->> 'confirmed' as cf \gset
select tt.chk('E5.4 sync confirms only the matched slip''s link', :'cf'='1' and (select state from shadow_links where primary_id=:'f6')='confirmed' and (select state from shadow_links where primary_id=:'f5')='pending');

\echo == E5.5 two finished-goods screens for the same item and day
select (production_post(1, :'rc'::uuid, 1, gen_random_uuid(), now(), 'run') ->> 'run_id') as run1 \gset
select tt.chk('E5.5 only the recipe run so far: no suspect', jsonb_array_length(dup_suspects(tt.today(), tt.today())->'production_screens')=0);
select stock_production_in(:'ick'::uuid, 1, 3, now(), null, 'plain entry') is not null as pi \gset
select tt.chk('E5.5 recipe run + plain finished-goods entry, same item and day = 1 possible duplicate', jsonb_array_length(dup_suspects(tt.today(), tt.today())->'production_screens')=1
  and (dup_suspects(tt.today(), tt.today())->'production_screens'->0->>'run_id')=:'run1' and (dup_suspects(tt.today(), tt.today())->'production_screens'->0->>'plain_qty')='3.0000');
select stock_production_in(:'inr'::uuid, 1, 3, now(), null, 'other item') is not null as pi2 \gset
select tt.chk('E5.5 a plain entry of ANOTHER item is not a suspect', jsonb_array_length(dup_suspects(tt.today(), tt.today())->'production_screens')=1);

\echo == E5.6 recommendations
select form_guard_recommendations() as fr \gset
select tt.chk('E5.6 four rows with key/current/recommended/reason in 3 languages', jsonb_array_length(:'fr'::jsonb)=4 and not exists (select 1 from jsonb_array_elements(:'fr'::jsonb) x where x->>'key' is null or x->>'reason_bn' is null or x->>'reason_mix' is null or x->>'reason_en' is null));
select tt.chk('E5.6 English reasons contain no Bangla characters', not exists (select 1 from jsonb_array_elements(:'fr'::jsonb) x where x->>'reason_en' ~ '[^\x01-\x7F]'));
select tt.chk('E5.6 recommendation does not change anything (switches still at defaults)', coalesce(rule_txt('form_051_mode'),'reference')='reference' and not rule_on('offline_soft_stock'));
select tt.chk('E5.6 form_051_mode recommended = reference while the screen is the record (path a)', (select x->>'recommended' from jsonb_array_elements(:'fr'::jsonb) x where x->>'key'='form_051_mode')='reference');
select path_switch_set('production',0,true,true,'b') is not null as sw4 \gset
select tt.chk('E5.6 ... and post when the 05-1 sheet is the record (path b, forms post)', (select x->>'recommended' from jsonb_array_elements(form_guard_recommendations()) x where x->>'key'='form_051_mode')='post');
select tt.err('E5.6 a non-owner cannot read the recommendations', $$select form_guard_recommendations()$$, 'not allowed') from (select tt.as(:'s')) z;
select tt.as(:'o');

\echo == E6 expense double count
select quick_expense_add(1, tt.today(), 'transport', 'x', 500, 'cash', false, null, gen_random_uuid()) ->> 'id' as q1 \gset
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","to":"y","receipt":"yes","amount":"500"}]}','[]') ->> 'id' as v1 \gset
update entries set status='submitted' where id=:'v1'::uuid;
update entries set status='approved' where id=:'v1'::uuid;
select tt.chk('E6.1 same place/day/head/amount in a quick entry and an approved 10-2, not linked = 1 suspect', jsonb_array_length(dup_suspects(tt.today(), tt.today())->'expense')=1 and (dup_suspects(tt.today(), tt.today())->'expense'->0->>'quick_id')=:'q1');
select tt.chk('E6.1 before linking the day book counts both (2 expense lines)', (select count(*) from (select typ from _daybook_lines(array[1], array[1], tt.today(), tt.today()) union all select typ from _daybook_lines12(array[1], tt.today(), tt.today()) union all select typ from _daybook_lines23(array[1], tt.today(), tt.today())) z where typ='expense')=2);
select suggest_expense_link(:'v1'::uuid) as sg \gset
select tt.chk('E6.2 suggest_expense_link: fully covered by the quick entry', (:'sg'::jsonb->>'fully_covered')='true' and (:'sg'::jsonb->'lines'->0->>'quick_id')=:'q1' and (:'sg'::jsonb->>'is_shadow')='false');
select tt.err('E6.2 a storekeeper cannot ask for or apply a link', format($$select suggest_expense_link('%s')$$, :'v1'), 'not allowed') from (select tt.as(:'k')) z;
select tt.as(:'o');
select expense_link_apply(:'v1'::uuid, 'same money') ->> 'linked' as lk \gset
select tt.chk('E6.3 applied: voucher is now the locked shadow of the quick entry, counted once', :'lk'='1' and is_shadow('entries', :'v1') and (select state from shadow_links where primary_id=:'q1' and shadow_type='entries')='confirmed'
  and (select count(*) from (select typ from _daybook_lines(array[1], array[1], tt.today(), tt.today()) union all select typ from _daybook_lines12(array[1], tt.today(), tt.today()) union all select typ from _daybook_lines23(array[1], tt.today(), tt.today())) z where typ='expense')=1);
select tt.chk('E6.3 the suspect is gone and a second apply is a no-op', jsonb_array_length(dup_suspects(tt.today(), tt.today())->'expense')=0 and (expense_link_apply(:'v1'::uuid) ->> 'noop')='true');
select tt.err('E6.3 the shadow voucher cannot be edited', format($$update entries set data = jsonb_set(data,'{lines,0,amount}','"900"') where id='%s'$$, :'v1'), 'shadow_locked');
select quick_expense_add(1, tt.today(), 'tea', 'x', 300, 'cash', false, null, gen_random_uuid()) ->> 'id' as q2 \gset
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"tea","to":"y","receipt":"yes","amount":"300"},{"head":"misc","to":"z","receipt":"no","amount":"200"}]}','[]') ->> 'id' as v2 \gset
update entries set status='submitted' where id=:'v2'::uuid;
update entries set status='approved' where id=:'v2'::uuid;
select tt.chk('E6.4 voucher with an extra uncovered line: not fully covered', (suggest_expense_link(:'v2'::uuid)->>'fully_covered')='false' and (suggest_expense_link(:'v2'::uuid)->>'matched')='1');
select tt.err('E6.4 apply is refused (it would hide the uncovered 200)', format($$select expense_link_apply('%s')$$, :'v2'), 'not_fully_covered');
select tt.chk('E6.4 the partial match is still a suspect for the owner to judge', jsonb_array_length(dup_suspects(tt.today(), tt.today())->'expense')=1 and not is_shadow('entries', :'v2'));
select quick_expense_add(1, tt.today(), 'gas', 'x', 100, 'cash', false, null, gen_random_uuid()) ->> 'id' as q3a \gset
select quick_expense_add(1, tt.today(), 'gas', 'x', 100, 'cash', false, null, gen_random_uuid()) ->> 'id' as q3b \gset
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"gas","to":"y","receipt":"yes","amount":"100"}]}','[]') ->> 'id' as v3 \gset
update entries set status='submitted' where id=:'v3'::uuid;
update entries set status='approved' where id=:'v3'::uuid;
select expense_link_apply(:'v3'::uuid) ->> 'linked' as lk3 \gset
select tt.chk('E6.5 two identical quick entries, one voucher line: exactly ONE quick entry is linked, the other stays pending', :'lk3'='1' and (select count(*) from shadow_links where primary_type='quick_expenses' and primary_id in (:'q3a',:'q3b') and state='confirmed')=1
  and (select count(*) from shadow_links where primary_type='quick_expenses' and primary_id in (:'q3a',:'q3b') and state='pending')=1);

\echo == E7 transit shortage
select (stock_transfer(1, 2, :'itr'::uuid, 10, null, 't1', gen_random_uuid()) ->> 'id') as t1 \gset
select tt.as(:'o');
select stock_receive_transfer(:'t1'::uuid, 6, 'short') is not null as r1 \gset
select tt.chk('E7.1 default (keep_in_transit = today): sent 10 recv 6: loc1 90, loc2 6, no transit_loss row, yellow flag', (select qty from stock_balance where item_id=:'itr' and location_id=1)=90 and (select qty from stock_balance where item_id=:'itr' and location_id=2)=6
  and (select count(*) from stock_ledger where reason='transit_loss')=0 and (select count(*) from exceptions where flag_code='transit_short')=1);
select transit_short_open(null) as so \gset
select tt.chk('E7.1 transit_short_open lists it: short 4, value 4 x 40 = 160 (owner sees cost)', jsonb_array_length(:'so'::jsonb)=1 and (:'so'::jsonb->0->>'short')::numeric=4 and (:'so'::jsonb->0->>'value')::numeric=160);
select tt.err('E7.2 resolve needs a reason', format($$select transit_short_resolve('%s','')$$, :'t1'), 'note_needed');
select transit_short_resolve(:'t1'::uuid, 'lost on the road') ->> 'short' as rs \gset
select tt.chk('E7.2 resolved: short 4 reported', :'rs'::numeric=4);
select tt.chk('E7.2 one transit_loss row of -4 at the sender cost 40', (select count(*) from stock_ledger where reason='transit_loss')=1 and (select qty_delta from stock_ledger where reason='transit_loss')=-4 and (select unit_cost from stock_ledger where reason='transit_loss')=40);
select tt.chk('E7.2 loc2 balance still 6 and its average cost unchanged (40)', (select qty from stock_balance where item_id=:'itr' and location_id=2)=6 and (select avg_cost from stock_balance where item_id=:'itr' and location_id=2)=40);
select tt.chk('E7.2 second resolve is a dup, list is empty', (transit_short_resolve(:'t1'::uuid, 'again') ->> 'dup')='true' and jsonb_array_length(transit_short_open(null))=0);
select set_rule('transit_short_mode','"loss"') is null as tm \gset
select (stock_transfer(1, 2, :'itr'::uuid, 10, null, 't2', gen_random_uuid()) ->> 'id') as t2 \gset
select stock_receive_transfer(:'t2'::uuid, 6, 'short again') is not null as r2 \gset
select tt.chk('E7.3 loss mode: booked at receipt. loc1 80, loc2 12, 2 transit_loss rows total (-4 each), nothing left on the open list', (select qty from stock_balance where item_id=:'itr' and location_id=1)=80 and (select qty from stock_balance where item_id=:'itr' and location_id=2)=12
  and (select count(*) from stock_ledger where reason='transit_loss')=2 and jsonb_array_length(transit_short_open(null))=0);
select tt.chk('E7.3 conservation: remaining stock 92 = 100 sent in total - 8 lost', (select sum(qty) from stock_balance where item_id=:'itr')=92 and (select -sum(qty_delta) from stock_ledger where reason='transit_loss')=8);
select tt.chk('E7.3 a full receipt books no loss', (stock_receive_transfer((stock_transfer(1, 2, :'itr'::uuid, 5, null, 't3', gen_random_uuid()) ->> 'id')::uuid, null, null) ->> 'short')::numeric=0 and (select count(*) from stock_ledger where reason='transit_loss')=2);
select set_rule('transit_short_mode','"keep_in_transit"') is null as tm2 \gset
select (stock_transfer(1, 2, :'itr'::uuid, 1, null, 't4', gen_random_uuid()) ->> 'id') as t4 \gset
select tt.chk('E7.4 limit blank: an old open transfer raises no alert', not exists (select 1 from jsonb_array_elements(urgent_alerts(now() - interval '1 day')) x where x->>'kind'='transit_open'));
reset role; update stock_transfers set sent_at = now() - interval '3 hours' where id=:'t4'::uuid; select tt.as(:'o');
select set_rule('transit_open_hours','2') is null as th \gset
select tt.chk('E7.4 limit 2 hours: a transfer open 3 hours appears in urgent_alerts (1), and again later still only once', (select count(*) from jsonb_array_elements(urgent_alerts(now() - interval '1 day')) x where x->>'kind'='transit_open')=1
  and (select count(*) from jsonb_array_elements(urgent_alerts(now() - interval '1 day')) x where x->>'kind'='transit_open')=1);
select tt.chk('E7.4 transit_open_list marks it over the limit', (transit_open_list(null)->'rows'->0->>'over_limit')='true' and (transit_open_list(null)->>'limit_hours')='2');
select set_rule('transit_open_hours','null') is null as th2 \gset

\echo == E8 offline POS
select set_rule('stock_negative_mode','"block"') is null as nb3 \gset
select tt.as(:'c');
select jsonb_build_object('p_client', gen_random_uuid(), 'p_loc', 1, 'p_lines', jsonb_build_array(jsonb_build_object('item_id', :'isl', 'qty', 5, 'price', 100)), 'p_discount', 0,
  'p_payments', jsonb_build_array(jsonb_build_object('mode','cash','amount',500)), 'p_sale_type','retail','p_quick', false, 'p_sold_at', now()) as pl \gset
select (:'pl'::jsonb->>'p_client') as cid \gset
select tt.err('E8.1 online path: sale above stock refused (block mode)', format($$select record_sale2('%s',1,'%s'::jsonb,0,'%s'::jsonb,null,null,'retail',null,false,now())$$, :'cid', :'pl'::jsonb->'p_lines', :'pl'::jsonb->'p_payments'), 'insufficient_stock');
select tt.err('E8.1 offline wrapper with the switch OFF behaves exactly the same (default)', format($$select record_sale_offline('%s',1,'%s'::jsonb,0,'%s'::jsonb,null,null,'retail',null,false,now())$$, :'cid', :'pl'::jsonb->'p_lines', :'pl'::jsonb->'p_payments'), 'insufficient_stock');
select tt.as(:'o'); select set_rule('offline_soft_stock','true') is null as ss \gset
select tt.as(:'c');
select tt.err('E8.2 switch ON: the ONLINE path is still refused', format($$select record_sale2('%s',1,'%s'::jsonb,0,'%s'::jsonb,null,null,'retail',null,false,now())$$, :'cid', :'pl'::jsonb->'p_lines', :'pl'::jsonb->'p_payments'), 'insufficient_stock');
select record_sale_offline(:'cid'::uuid,1,:'pl'::jsonb->'p_lines',0,:'pl'::jsonb->'p_payments',null,null,'retail',null,false,now()) ->> 'total' as tot1 \gset
select tt.chk('E8.2 switch ON: the replayed sale is accepted (total 500)', :'tot1'::numeric=500);
select tt.chk('E8.2 stock 2-5 = -3', (select qty from stock_balance where item_id=:'isl' and location_id=1)=-3);
select tt.chk('E8.2 one yellow flag offline_soft_stock', (select count(*) from exceptions where flag_code='offline_soft_stock' and level='yellow')=1);
select tt.chk('E8.2 replaying the same client_id again is a duplicate, not a second sale', (record_sale_offline(:'cid'::uuid,1,:'pl'::jsonb->'p_lines',0,:'pl'::jsonb->'p_payments',null,null,'retail',null,false,now()) ->> 'dup')='true' and (select count(*) from sales where client_id=:'cid'::uuid)=1);
select tt.as(:'o'); select set_rule('offline_soft_stock','false') is null as ss2 \gset

\echo == E8.3 manager override with the ORIGINAL client_id
select set_rule('stock_negative_mode','"block"') is null as nb4 \gset
select jsonb_build_object('p_client', gen_random_uuid(), 'p_loc', 1, 'p_lines', jsonb_build_array(jsonb_build_object('item_id', :'isl', 'qty', 4, 'price', 100)), 'p_discount', 0,
  'p_payments', jsonb_build_array(jsonb_build_object('mode','cash','amount',400)), 'p_sale_type','retail','p_quick', false, 'p_sold_at', now(), 'p_note', 'walk-in') as pl2 \gset
select (:'pl2'::jsonb->>'p_client') as cid2 \gset
select tt.as(:'c');
select pos_failed_note(jsonb_build_array(jsonb_build_object('client_id', :'cid2', 'loc', 1, 'total', 400, 'err', 'insufficient_stock', 'sold_at', now(), 'lines_n', 1))) as pn \gset
select tt.chk('E8.3 device reports its failed card; reporting twice adds nothing', :'pn'='1' and pos_failed_note(jsonb_build_array(jsonb_build_object('client_id', :'cid2', 'loc', 1, 'total', 400, 'err', 'x')))=0);
select tt.err('E8.3 cashier without the grant cannot override', format($$select pos_replay_override('%s'::jsonb, 'manager ok', 'insufficient_stock')$$, :'pl2'), 'replay_override_needs_approval');
select tt.as(:'o'); select set_user_grant(:'m'::uuid,'pos_replay_override') is null as gm \gset
select tt.as(:'m');
select tt.err('E8.3 a reason is required', format($$select pos_replay_override('%s'::jsonb, 'x', 'insufficient_stock')$$, :'pl2'), 'note_needed');
select pos_replay_override(:'pl2'::jsonb, 'goods already handed over', 'insufficient_stock') as ov \gset
select tt.chk('E8.3 override: sale recorded (400), under its ORIGINAL client_id, stock -3-4 = -7, note carries the reason', (:'ov'::jsonb->>'total')='400.00' and (select count(*) from sales where client_id=:'cid2'::uuid)=1
  and (select qty from stock_balance where item_id=:'isl' and location_id=1)=-7 and (select note from sales where client_id=:'cid2'::uuid) like 'manager override: goods already handed over%');
select tt.chk('E8.3 audit: one log row, one yellow exception, the failed card is closed as resent', (select count(*) from pos_replay_log where client_id=:'cid2'::uuid and result='sold' and reason='goods already handed over')=1
  and (select count(*) from exceptions where flag_code='pos_replay_override')=1 and (select status from pos_failed_cards where client_id=:'cid2'::uuid)='resent');
select tt.chk('E8.3 override sent twice = still ONE sale (dup), no second stock movement', (pos_replay_override(:'pl2'::jsonb, 'again please', null) ->> 'dup')='true' and (select count(*) from sales where client_id=:'cid2'::uuid)=1 and (select qty from stock_balance where item_id=:'isl' and location_id=1)=-7);
select tt.chk('E8.3 the override trail is append-only', (select count(*) from pos_replay_log)=1);
select tt.as(:'c');
set role authenticated;
select tt.chk('E8.3 a cashier cannot read the override trail', (select count(*) from pos_replay_log)=0);
select tt.err('E8.3 nobody can write the trail directly', $$insert into pos_replay_log (client_id, location_id, reason, result) values (gen_random_uuid(), 1, 'abc', 'sold')$$, 'permission denied');
reset role;
select tt.as(:'o');
select set_rule('period_closed_until', to_jsonb(tt.today()::text)) is null as pc \gset
select tt.as(:'m');
select tt.err('E8.3 closed period still refuses an override (other rules are not bypassed)', format($$select pos_replay_override('%s'::jsonb, 'try anyway', null)$$, jsonb_set(:'pl2'::jsonb, '{p_client}', to_jsonb(gen_random_uuid()::text))), 'period_closed');
select tt.as(:'o'); select set_rule('period_closed_until','null') is null as pc2 \gset

\echo == E8.4 failed-card board
select tt.as(:'c');
select pos_failed_note(jsonb_build_array(jsonb_build_object('client_id', gen_random_uuid(), 'loc', 1, 'total', 250, 'err', 'item_not_sellable'), jsonb_build_object('client_id', gen_random_uuid(), 'loc', 1, 'total', 150, 'err', 'item_not_sellable'))) as pn2 \gset
select tt.as(:'o');
select pos_failed_board() as bd \gset
select tt.chk('E8.4 owner board: 2 open cards at place 1, total 400', (:'bd'::jsonb->>'open')='2' and (:'bd'::jsonb->'by_location'->0->>'n')='2' and (:'bd'::jsonb->'by_location'->0->>'total')='400');
select tt.as(:'c');
select pos_failed_close((select client_id from pos_failed_cards where status='open' order by total limit 1), 'discarded', 'customer left') ->> 'status' as dc \gset
select tt.chk('E8.4 the reporter can discard one card; the board drops to 1', :'dc'='discarded' and (pos_failed_board()->>'open')='1');
select tt.as(:'k');
select (select client_id from pos_failed_cards where status='open' limit 1) as oc \gset
select tt.err('E8.4 another user cannot close someone else''s card', format($$select pos_failed_close('%s','discarded','x')$$, :'oc'), 'not allowed');
select tt.as(:'o');
select tt.chk('E8.4 cards are never deleted', (select count(*) from pos_failed_cards)=3);

reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
