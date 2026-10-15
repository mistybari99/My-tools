-- phase73b_test.sql = copy of phase73_test.sql for the FINAL build. Changes (marked bos89): phase87 lets the OWNER approve his own change (owner decision), so the two owner self-approval asserts at T4 follow that.
-- FRESH DB ONLY. Phase 73 tests (step C-0: artisan register, recipe versions + approval, recipe steps, artisan-wise recipe book).
--   ORDER="phase8 ... phase62 phase70 phase71 phase73" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> 73db
--   psql -h /tmp -p 5544 -U postgres -d 73db -qAt -f supabase/phase73_test.sql | grep -E 'FAIL|RESULT'
-- No real person names anywhere: the artisan "names" below are placeholders typed as test data (nm-a1 ...).
\set ON_ERROR_STOP off
\set o  '00000000-0000-0000-0000-000000000001'
\set ap '00000000-0000-0000-0000-000000000002'
\set mg '00000000-0000-0000-0000-000000000003'
\set a1 '00000000-0000-0000-0000-000000000004'
\set a2 '00000000-0000-0000-0000-000000000005'
\set cv '00000000-0000-0000-0000-000000000006'
\set nn '00000000-0000-0000-0000-000000000007'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.ok(p_name text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, true);
exception when others then perform tt.chk(p_name, false); raise notice '  (got: %)', sqlerrm; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'ap','appr2@s.app','{"full_name":"Approver"}'), (:'mg','mgr3@s.app','{"full_name":"RecipeMgr"}'),
 (:'a1','art4@s.app','{"full_name":"login-artisan-1"}'), (:'a2','art5@s.app','{"full_name":"login-artisan-2"}'), (:'cv','cost6@s.app','{"full_name":"CostViewer"}'), (:'nn','none7@s.app','{"full_name":"Nobody"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'ap','recipe_approver'),(:'mg','factory_incharge'),(:'a1','factory_incharge'),(:'a2','factory_incharge'),(:'cv','storekeeper'),(:'nn','salesperson') on conflict do nothing;
insert into user_locations values (:'ap',1),(:'mg',1),(:'a1',1),(:'a2',1),(:'cv',1),(:'nn',1) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select set_user_grant(:'mg'::uuid,'recipe_manage') is null as g1 \gset
select set_user_grant(:'cv'::uuid,'view_cost') is null as g2 \gset
select set_user_grant(:'cv'::uuid,'recipe_view') is null as g3 \gset

insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('C0-F',  'রসগোল্লা', 'Rasgulla C0', 'kg', 'kg', 'finished_good', true, 260),
 ('C0-F2', 'সন্দেশ', 'Sandesh C0', 'kg', 'kg', 'finished_good', true, 300),
 ('C0-FL', 'ময়দা', 'Flour C0', 'kg', 'kg', 'raw_material', true, null),
 ('C0-SU', 'চিনি', 'Sugar C0', 'kg', 'kg', 'raw_material', true, null);
select id as ifin from items where code='C0-F' \gset
select id as ifin2 from items where code='C0-F2' \gset
select id as ifl from items where code='C0-FL' \gset
select id as isu from items where code='C0-SU' \gset
set role authenticated; select tt.as(:'o');
select stock_opening(:'ifl'::uuid, 1, 100, 40, null, 'c0') is not null as so1 \gset
select stock_opening(:'isu'::uuid, 1, 100, 60, null, 'c0') is not null as so2 \gset

\echo == T0 shape
select tt.chk('T0 new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('artisans','recipe_steps','recipe_versions') and c.relrowsecurity)=3);
select tt.chk('T0 defaults = today: approval off, self-approve off, self-view off', rule_txt('recipe_approval_required')='off' and not rule_on('recipe_self_approve') and not rule_on('artisan_self_view'));
select tt.chk('T0 grants exist; approver role holds recipe_view + recipe_approve; nobody else by default', (select count(*) from grant_defs where grant_code in ('recipe_view','recipe_approve','artisan_manage'))=3
  and (select count(*) from rule_grants where grant_code in ('recipe_view','recipe_approve'))=2 and not exists(select 1 from rule_grants where grant_code in ('recipe_view','recipe_approve','artisan_manage') and role_code<>'recipe_approver'));
select tt.chk('T0 browsers cannot read artisans.name (column grant)', not has_column_privilege('authenticated','public.artisans','name','select') and has_column_privilege('authenticated','public.artisans','code','select'));
select tt.chk('T0 anon cannot execute', not has_function_privilege('anon','recipe_book(int,boolean,int)','execute') and not has_function_privilege('anon','artisan_register()','execute'));
select tt.chk('T0 helpers closed', not has_function_privilege('authenticated','_rv_log(uuid,text,jsonb,text,uuid)','execute') and not has_function_privilege('authenticated','_recipe_gate73(uuid)','execute'));
select tt.chk('T0 functions re-created carry the bos73 tag', (select count(*) from pg_proc where proname in ('recipe_save','recipe_copy','recipe_cost','production_post') and position('bos73' in pg_get_functiondef(oid))>0)=4);

\echo == T1 artisan register (C0.1)
select tt.as(:'mg'); select tt.err('T1 recipe manager (no artisan_manage) cannot add an artisan', $$select artisan_save(null,'karigor',null,'nm-a1','mishti',null)$$, 'not allowed');
select tt.as(:'o');
select (artisan_save(null,'karigor',null,'nm-a1','mishti',null,1,:'a1'::uuid,null,'cccccccc-0000-0000-0000-000000000001'::uuid)->>'id')::int as ar1 \gset
select (artisan_save(null,'chef',null,'nm-a2','doi',null,1,:'a2'::uuid)->>'id')::int as ar2 \gset
select (artisan_save(null,'other','ice-cream maker','nm-a3','other','pastry',6)->>'id')::int as ar3 \gset
select tt.chk('T1 three artisans, ids 1.. and code artisan-N', :ar1 = 1 and :ar2 = 2 and :ar3 = 3 and (select code from artisans where id=:ar3)='artisan-3');
select tt.err('T1 post "other" needs the typed text', $$select artisan_save(null,'other',null,'nm-x','mishti',null)$$, 'post_other_needed');
select tt.err('T1 work type "other" needs the typed text', $$select artisan_save(null,'karigor',null,'nm-x','other',null)$$, 'work_other_needed');
select tt.err('T1 bad post refused', $$select artisan_save(null,'boss',null,'nm-x','mishti',null)$$, 'bad_post');
select tt.err('T1 name needed', $$select artisan_save(null,'karigor',null,' ','mishti',null)$$, 'name_needed');
select tt.chk('T1 same client id twice = one record', (artisan_save(null,'karigor',null,'nm-a1','mishti',null,1,null,null,'cccccccc-0000-0000-0000-000000000001'::uuid)->>'dup')::boolean is true and (select count(*) from artisans)=3);
select tt.chk('T1 artisan_list has id/code/post/work_type and NO name', (select bool_and(not (e ? 'name')) and count(*)=3 from jsonb_array_elements(artisan_list()) e) and position('nm-a' in artisan_list()::text)=0);
select tt.chk('T1 register (owner) shows the names', position('nm-a1' in artisan_register()::text)>0);
select tt.as(:'mg');
select tt.chk('T1 recipe manager sees the list without names', position('nm-a' in artisan_list()::text)=0 and jsonb_array_length(artisan_list())=3);
select tt.err('T1 recipe manager cannot read the register', $$select artisan_register()$$, 'not allowed');
select tt.err('T1 direct select of the name column is denied', $$select name from public.artisans$$, 'permission denied');
select tt.as(:'o');
select tt.chk('T1 audit log carries no name (insert + edit)', (select count(*) from audit_log where table_name='artisans')>=3 and not exists (select 1 from audit_log where table_name='artisans' and detail::text like '%nm-a%'));
select artisan_save(:ar2, 'chef', null, 'nm-a2-renamed', 'doi', null, 1, :'a2'::uuid) is not null as ed \gset
select tt.chk('T1 rename audited as name_changed without the text', exists (select 1 from audit_log where table_name='artisans' and record_id=:'ar2' and detail->'new' ? 'name_changed') and not exists (select 1 from audit_log where detail::text like '%nm-a2-renamed%'));
select tt.err('T1 retire needs a reason', format($$select artisan_set_active(%s,false,'')$$, :ar3), 'note_required');
select artisan_set_active(:ar3, false, 'left the factory') is null as ra \gset
select (artisan_save(null,'chef',null,'nm-a4','cake',null,6)->>'id')::int as ar4 \gset
select tt.chk('T1 ids are never reused: new artisan after a retirement gets 4, retired 3 stays', :ar4 = 4 and exists (select 1 from artisans where id=:ar3 and not active and retired_reason is not null));
reset role; select tt.err('T1 an artisan cannot be deleted (trigger, even for a superuser)', format($$delete from artisans where id=%s$$, :ar3), 'nothing is deleted'); set role authenticated; select tt.as(:'o');
select tt.chk('T1 artisan_list hides retired by default, shows them on request', jsonb_array_length(artisan_list())=3 and jsonb_array_length(artisan_list(true))=4);

\echo == T2 recipes: blank artisan still works (C0.2)
select tt.as(:'mg');
select (recipe_save(null, :'ifin'::uuid, 10, null, 'v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'ifl','qty',6,'waste_pct',10), jsonb_build_object('ingredient_item_id',:'isu','qty',3,'waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc1 \gset
select tt.chk('T2 recipe created with NO artisan (blank, nothing guessed)', (select artisan_id is null and changed_by = :'mg'::uuid from recipes where id=:'rc1'));
select tt.chk('T2 it is on the list "কারিগর নির্ধারিত নয়"', exists (select 1 from jsonb_array_elements(recipe_unassigned()) e where e->>'recipe_id' = :'rc1'));
select tt.as(:'o');
select tt.chk('T2 blank-artisan recipe still costs: (6.6x40 + 3x60)/10 = 44.4', (recipe_cost(:'rc1'::uuid,1)->>'unit_cost')::numeric = 44.4);
select tt.chk('T2 blank-artisan recipe still produces', (production_post(1, :'rc1'::uuid, 1, gen_random_uuid())->>'qty')::numeric = 10);
select tt.as(:'mg'); select tt.err('T2 cannot give a retired artisan', format($$select recipe_set_artisan('%s',%s)$$, :'rc1', :ar3), 'artisan_not_found');
select recipe_set_artisan(:'rc1'::uuid, :ar1, 'main artisan') is null as sa \gset
select tt.chk('T2 artisan set; now off the unassigned list', (select artisan_id=:ar1 from recipes where id=:'rc1') and not exists (select 1 from jsonb_array_elements(recipe_unassigned()) e where e->>'recipe_id' = :'rc1'));
select tt.chk('T2 setting the artisan wrote a history row with the previous value (null)', exists (select 1 from recipe_versions where recipe_id=:'rc1' and kind='artisan_set' and (prev->>'artisan_id') is null and (snap->>'artisan_id')::int=:ar1));
select tt.as(:'nn'); select tt.err('T2 nobody-role cannot set an artisan', format($$select recipe_set_artisan('%s',%s)$$, :'rc1', :ar1), 'not allowed');

\echo == T3 versions keep the old values (C0.3)
select tt.as(:'mg');
select tt.chk('T3 creation logged as version event 1', exists (select 1 from recipe_versions where recipe_id=:'rc1' and kind='created' and seq=1 and changed_by=:'mg'::uuid));
select (recipe_save(null, :'ifin'::uuid, 12, null, 'v2', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'ifl','qty',7,'waste_pct',5)))->>'id')::uuid as rc2 \gset
select tt.chk('T3 version 2 is a NEW row; version 1 unchanged (yield 10, 2 lines)', (select yield_qty from recipes where id=:'rc1')=10 and (select count(*) from recipe_lines where recipe_id=:'rc1' and active)=2 and (select version from recipes where id=:'rc2')=2);
select recipe_save(:'rc2'::uuid, :'ifin'::uuid, 13, null, 'v2 edited', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'ifl','qty',8,'waste_pct',5))) is not null as e2 \gset
select tt.chk('T3 editing a draft keeps the previous values in recipe_versions.prev', exists (select 1 from recipe_versions where recipe_id=:'rc2' and kind='edited' and (prev->>'yield_qty')::numeric=12 and (snap->>'yield_qty')::numeric=13
  and (prev->'lines'->0->>'qty')::numeric=7 and (snap->'lines'->0->>'qty')::numeric=8));
select tt.err('T3 a used version cannot be edited (new version needed)', format($$select recipe_save('%s','%s',10,null,'x',jsonb_build_array(jsonb_build_object('ingredient_item_id','%s','qty',1)))$$, :'rc1', :'ifin', :'ifl'), 'recipe_used');
select tt.chk('T3 history rows are append-only', (select count(*) from recipe_versions)>=4);
select tt.err('T3 history cannot be edited', $$update recipe_versions set summary='x'$$, 'permission denied');
reset role; select tt.err('T3 history cannot be edited even by a superuser (trigger)', $$update recipe_versions set summary='x'$$, 'append_only'); set role authenticated;
select tt.as(:'o');
select tt.chk('T3 history shows who/when/version', (select bool_and(changed_by is not null and changed_at is not null and version is not null) from recipe_versions));

\echo == T4 approval: the changer may not approve (C0.3)
select tt.as(:'mg'); select tt.err('T4 recipe manager without recipe_approve cannot approve', format($$select recipe_approve('%s')$$, :'rc2'), 'not allowed');
select tt.as(:'o'); select set_user_grant(:'mg'::uuid,'recipe_approve') is null as g4 \gset
select tt.as(:'mg'); select tt.err('T4 the person who last changed the version cannot approve it, even holding the grant', format($$select recipe_approve('%s')$$, :'rc2'), 'self_approve_refused');
select tt.as(:'o'); select set_user_grant(:'mg'::uuid,'recipe_approve',null,null,false) is null as g5 \gset
select (recipe_save(null, :'ifin2'::uuid, 5, null, 'f2 owner', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'isu','qty',2,'waste_pct',0)))->>'id')::uuid as rc3 \gset
select tt.chk('T4 (bos89: since phase87) owner who changed rc3 himself CAN approve it; the answer carries the ask_another_approver suggestion', (select (r->>'approved')::boolean and r->>'suggestion'='ask_another_approver' from (select recipe_approve(:'rc3'::uuid) r) x));
select tt.as(:'ap');
select tt.chk('T4 a separate approver (role recipe_approver) can approve', (recipe_approve(:'rc2'::uuid, 'checked on paper 05-3')->>'approved')::boolean);
select tt.chk('T4 approval stored with approver and time; history row written', (select approved_by=:'ap'::uuid and approved_at is not null from recipes where id=:'rc2') and exists (select 1 from recipe_versions where recipe_id=:'rc2' and kind='approved'));
select tt.chk('T4 approving twice is a no-op (dup)', (recipe_approve(:'rc2'::uuid)->>'dup')::boolean);
select tt.as(:'mg');
select tt.err('T4 an approved version cannot be edited', format($$select recipe_save('%s','%s',20,null,'x',jsonb_build_array(jsonb_build_object('ingredient_item_id','%s','qty',1)))$$, :'rc2', :'ifin', :'ifl'), 'recipe_approved');
reset role; select tt.err('T4 lines of an approved version are locked by trigger', format($$update recipe_lines set qty=99 where recipe_id='%s'$$, :'rc2'), 'recipe_approved'); set role authenticated;
select tt.as(:'o');
select tt.ok('T4 approval switch OFF (default): unapproved recipe still costs', format($$select recipe_cost('%s',1)$$, :'rc1'));
select set_rule('recipe_approval_required','"on"'::jsonb) is null as r1 \gset
select tt.err('T4 switch ON: recipe_cost refuses an unapproved recipe', format($$select recipe_cost('%s',1)$$, :'rc1'), 'recipe_not_approved');
select tt.err('T4 switch ON: production_post refuses an unapproved recipe', format($$select production_post(1,'%s',1)$$, :'rc1'), 'recipe_not_approved');
select tt.chk('T4 switch ON: an approved recipe is costed (approved=true)', (recipe_cost(:'rc2'::uuid,1)->>'approved')::boolean);
select tt.chk('T4 switch ON: an approved recipe is produced (yield 13)', (production_post(1, :'rc2'::uuid, 1, gen_random_uuid())->>'qty')::numeric = 13);
select set_rule('recipe_approval_required','"warn"'::jsonb) is null as r2 \gset
select production_post(1, :'rc1'::uuid, 1, gen_random_uuid())->>'run_id' as warnrun \gset
select tt.chk('T4 warn: unapproved still produces, owner gets a yellow line', :'warnrun' is not null and exists (select 1 from exceptions where flag_code='recipe_not_approved' and level='yellow'));
select set_rule('recipe_approval_required','"off"'::jsonb) is null as r3 \gset
select set_rule('recipe_self_approve','true'::jsonb) is null as r4 \gset
select tt.chk('T4 (bos89) with recipe_self_approve ON a second call on the same version is a plain no-op (dup)', (recipe_approve(:'rc3'::uuid)->>'dup')::boolean);
select set_rule('recipe_self_approve','false'::jsonb) is null as r5 \gset

\echo == T5 steps (C0.4)
select tt.as(:'mg');
select (recipe_save(null, :'ifin2'::uuid, 5, null, 'f2 v2', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'isu','qty',2,'waste_pct',0)))->>'id')::uuid as rc4 \gset
select tt.chk('T5 save three steps in order', (recipe_steps_save(:'rc4'::uuid, jsonb_build_array(
   jsonb_build_object('step_name','boil milk','description','free text A','minutes',30,'people',2,'fuel','gas','flame_note','high','equipment','pot-1','qc_note','no skin','resp_post','karigor'),
   jsonb_build_object('step_name','shape','minutes',20,'people',3,'resp_post','asst_karigor'),
   jsonb_build_object('step_name','fry','minutes',45,'people',1,'fuel','other','fuel_other','charcoal')))->>'steps')::int = 3);
select tt.chk('T5 step numbers 1,2,3 in the given order', (select array_agg(step_name order by step_no) = array['boil milk','shape','fry'] from recipe_steps where recipe_id=:'rc4' and active));
select tt.chk('T5 suggested labour-hours = (30x2 + 20x3 + 45x1)/60 = 2.75 (a suggestion only)', (recipe_labour_suggest(:'rc4'::uuid)->>'suggested_labour_hours')::numeric = 2.75 and (recipe_labour_suggest(:'rc4'::uuid)->>'note') = 'suggestion_only');
select recipe_steps_save(:'rc4'::uuid, jsonb_build_array(
   jsonb_build_object('step_name','shape','minutes',20,'people',3), jsonb_build_object('step_name','boil milk','minutes',30,'people',2,'fuel','gas'), jsonb_build_object('step_name','fry','minutes',45,'people',1,'fuel','other','fuel_other','charcoal'))) is not null as mv \gset
select tt.chk('T5 move a step up/down = resave the list in the new order; numbers follow', (select array_agg(step_name order by step_no) = array['shape','boil milk','fry'] from recipe_steps where recipe_id=:'rc4' and active));
select tt.chk('T5 old steps are kept (inactive), not deleted; history keeps the previous list', (select count(*) from recipe_steps where recipe_id=:'rc4' and not active)=3
  and exists (select 1 from recipe_versions where recipe_id=:'rc4' and kind='steps_edited' and jsonb_array_length(prev->'steps')=3 and prev->'steps'->0->>'step_name'='boil milk'));
select tt.err('T5 a step needs a name', format($$select recipe_steps_save('%s', '[{"minutes":5}]'::jsonb)$$, :'rc4'), 'step_name_needed');
select tt.err('T5 fuel other needs the typed text', format($$select recipe_steps_save('%s', '[{"step_name":"x","fuel":"other"}]'::jsonb)$$, :'rc4'), 'fuel_other_needed');
select tt.err('T5 negative minutes refused', format($$select recipe_steps_save('%s', '[{"step_name":"x","minutes":-1}]'::jsonb)$$, :'rc4'), 'bad_qty');
select tt.err('T5 bad fuel refused', format($$select recipe_steps_save('%s', '[{"step_name":"x","fuel":"coal"}]'::jsonb)$$, :'rc4'), 'bad_value');
select tt.chk('T5 blank minutes/people = incomplete flag (nothing guessed)', (recipe_steps_save(:'rc4'::uuid, '[{"step_name":"only name"}]'::jsonb)->>'incomplete')::boolean);
select recipe_steps_save(:'rc4'::uuid, jsonb_build_array(jsonb_build_object('step_name','boil','minutes',30,'people',2), jsonb_build_object('step_name','fry','minutes',45,'people',1)), 'aaaaaaaa-0000-0000-0000-000000000001'::uuid) is not null as rs \gset
select tt.chk('T5 steps_save with the same client id twice = one change (dup)', (recipe_steps_save(:'rc4'::uuid, '[{"step_name":"zzz"}]'::jsonb, 'aaaaaaaa-0000-0000-0000-000000000001'::uuid)->>'dup')::boolean and (select count(*) from recipe_steps where recipe_id=:'rc4' and active)=2);
select tt.as(:'o');
select tt.chk('T5 steps do NOT enter cost: recipe_cost identical with 0 steps and with steps', (recipe_cost(:'rc4'::uuid,1)->>'unit_cost')::numeric = 24 and (recipe_cost(:'rc4'::uuid,1)->>'batch_cost')::numeric = 120);
select production_post(1, :'rc4'::uuid, 1, gen_random_uuid())->>'run_id' as run4 \gset
reset role; select tt.chk('T5 production unit cost = ingredient cost only (2 kg x 60 / 5 = 24)', (select unit_cost from stock_ledger where ref_type='production' and ref_id=:'run4' and reason='production_in')=24); set role authenticated; select tt.as(:'o');
select tt.as(:'ap'); select tt.chk('T5 approver approves a recipe changed by someone else', (recipe_approve(:'rc4'::uuid)->>'approved')::boolean);
select tt.as(:'mg'); select tt.err('T5 steps of an approved version are locked', format($$select recipe_steps_save('%s', '[{"step_name":"x"}]'::jsonb)$$, :'rc4'), 'recipe_approved');
select tt.as(:'nn'); select tt.err('T5 non-manager cannot write steps', format($$select recipe_steps_save('%s', '[{"step_name":"x"}]'::jsonb)$$, :'rc2'), 'not allowed');
select tt.as(:'mg');

\echo == T6 atomic editor save + copy (C0.2 / C0.4)
select tt.as(:'mg');
select recipe_save_full(null, :'ifin'::uuid, 8, null, 'full', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'isu','qty',1)), '[{"step_name":"mix","minutes":10,"people":1}]'::jsonb, :ar1, true, 'CARD-05-3-0007', 'bbbbbbbb-0000-0000-0000-000000000001'::uuid) as sf \gset
select (:'sf'::jsonb->>'id')::uuid as rc5 \gset
select tt.chk('T6 one call saved lines + steps + artisan + card reference', (select artisan_id=:ar1 and form_ref='CARD-05-3-0007' from recipes where id=:'rc5') and (select count(*) from recipe_steps where recipe_id=:'rc5' and active)=1);
select tt.chk('T6 same client id again = dup, no second set of steps', (recipe_save_full(null, :'ifin'::uuid, 8, null, 'full', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'isu','qty',1)), '[{"step_name":"mix"}]'::jsonb, :ar1, true, null, 'bbbbbbbb-0000-0000-0000-000000000001'::uuid)->>'dup')::boolean
  and (select count(*) from recipe_steps where recipe_id=:'rc5')=1);
select (recipe_copy(:'rc5'::uuid)->>'id')::uuid as rc6 \gset
select tt.chk('T6 copy to a new version of the same product keeps artisan + steps', (select artisan_id=:ar1 and version=(select version+1 from recipes where id=:'rc5') and approved_at is null from recipes where id=:'rc6') and (select count(*) from recipe_steps where recipe_id=:'rc6' and active)=1);
select (recipe_copy(:'rc5'::uuid, :'ifin2'::uuid)->>'id')::uuid as rc7 \gset
select tt.chk('T6 copy to ANOTHER product: artisan stays blank (nothing guessed)', (select artisan_id is null from recipes where id=:'rc7'));

\echo == T7 artisan-wise recipe book (C0.5 / C0.6)
select tt.as(:'o');
select tt.chk('T7 owner gets the book of artisan 1: recipes, ingredients, steps, version, approval date', (select jsonb_array_length(b->'recipes')>=3 from (select recipe_book(:ar1) b) x)
  and (select bool_or((e->>'approved')::boolean is false) from jsonb_array_elements(recipe_book(:ar1)->'recipes') e) and position('"steps"' in recipe_book(:ar1)::text)>0);
select tt.chk('T7 the book has code + post but NO artisan name anywhere', position('nm-a' in recipe_book(:ar1)::text)=0 and recipe_book(:ar1)->'artisan'->>'code'='artisan-1' and recipe_book(:ar1)->'artisan'->>'post'='karigor');
select tt.chk('T7 default view has no cost key at all', not (recipe_book(:ar1)::text like '%"cost"%') and not (recipe_book(:ar1)->>'with_cost')::boolean);
select tt.chk('T7 owner asking for cost gets it', (recipe_book(:ar1, true, 1)->>'with_cost')::boolean and position('"cost"' in recipe_book(:ar1, true, 1)::text)>0);
select recipe_set_active(:'rc5'::uuid,false) is null as ia \gset
select tt.chk('T7 only active recipes are in the book (inactive hidden)', not exists (select 1 from jsonb_array_elements(recipe_book(:ar1)->'recipes') e where e->>'recipe_id'=:'rc5'));
select recipe_set_active(:'rc5'::uuid,true) is null as rr \gset
select tt.as(:'cv');
select tt.chk('T7 recipe_view + view_cost holder gets cost', (recipe_book(:ar1, true, 1)->>'with_cost')::boolean);
select tt.as(:'ap'); select tt.chk('T7 approver role has recipe_view by default', jsonb_array_length(recipe_book(:ar1)->'recipes')>=3);
select tt.chk('T7 recipe_view WITHOUT cost right: cost requested but hidden', not (recipe_book(:ar1, true, 1)->>'with_cost')::boolean and not (recipe_book(:ar1, true, 1)::text like '%"cost"%'));
select tt.as(:'nn'); select tt.err('T7 a user with no recipe_view is refused', format($$select recipe_book(%s)$$, :ar1), 'not allowed');
select tt.as(:'mg'); select tt.err('T7 recipe_manage alone is not recipe_view', format($$select recipe_book(%s)$$, :ar1), 'not allowed');
select tt.as(:'a1'); select tt.err('T7 switch OFF: even the artisan himself is refused', format($$select recipe_book(%s)$$, :ar1), 'not allowed');
select tt.as(:'o'); select set_rule('artisan_self_view','true'::jsonb) is null as sv \gset
select tt.as(:'a1');
select tt.chk('T7 switch ON: artisan 1 sees his own book (no argument = own)', jsonb_array_length(recipe_book()->'recipes')>=3 and recipe_book()->'artisan'->>'code'='artisan-1');
select tt.err('T7 switch ON: the other artisan''s book stays invisible', format($$select recipe_book(%s)$$, :ar2), 'not allowed');
select tt.chk('T7 switch ON: own book has no cost even when asked (no cost right)', not (recipe_book(:ar1, true, 1)::text like '%"cost"%'));
select tt.as(:'a2');
select tt.chk('T7 switch ON: artisan 2 sees his own (empty) book, not artisan 1''s', jsonb_array_length(recipe_book()->'recipes')=0);
select tt.err('T7 artisan 2 cannot read artisan 1', format($$select recipe_book(%s)$$, :ar1), 'not allowed');
select tt.as(:'nn'); select tt.err('T7 an unlinked user is still refused with the switch ON', format($$select recipe_book(%s)$$, :ar1), 'not allowed');
select tt.as(:'o');
select tt.chk('T7 every view is in the audit log (action view, table recipe_book)', (select count(*) from audit_log where action='view' and table_name='recipe_book')>=6);
select tt.chk('T7 the audit rows hold no artisan name', not exists (select 1 from audit_log where action='view' and detail::text like '%nm-a%'));
select set_rule('artisan_self_view','false'::jsonb) is null as sv0 \gset
select artisan_set_active(:ar1, false, 'moved away') is null as ret \gset
select tt.chk('T7 a retired artisan''s recipes stay readable by the owner (history kept)', (recipe_book(:ar1)->'artisan'->>'active')::boolean is false and jsonb_array_length(recipe_book(:ar1)->'recipes')>=3);

\echo == T8 older production behaviour is unchanged with everything at defaults
select tt.chk('T8 production_post still returns cost_complete for the owner', (production_post(1, :'rc1'::uuid, 0.5, gen_random_uuid()) ? 'cost_complete'));
select tt.chk('T8 recipe_cost shape intact (lines, complete, batch_cost, unit_cost)', (select recipe_cost(:'rc1'::uuid,1) ?& array['lines','complete','batch_cost','unit_cost','yield_base']));

reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select 'FAIL ' || name from tt.res where not ok;
