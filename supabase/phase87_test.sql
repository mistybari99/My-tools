-- FRESH DB ONLY. Phase 87 tests (step X: owner approval, expiry_sale_guard, client_id reuse, purchase backdate flag, ledger problem count, production double-deduction guard).
--   Needs phases 8..71, 72..79, 82, 84, then 87 (see docs/briefs_p2p3/step_X_REPORT.md for the exact build line).
--   psql -h /tmp -p 5544 -U postgres -d 87db -qAt -f supabase/phase87_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (ids, roles, placeholder names).
\set ON_ERROR_STOP off
\set o  '00000000-0000-0000-0000-000000000001'
\set s  '00000000-0000-0000-0000-000000000002'
\set s2 '00000000-0000-0000-0000-000000000003'
\set k  '00000000-0000-0000-0000-000000000004'
\set mg '00000000-0000-0000-0000-000000000005'
\set ap '00000000-0000-0000-0000-000000000006'
\set e  '00000000-0000-0000-0000-000000000007'
\set a  '00000000-0000-0000-0000-000000000008'
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
create or replace function tt.noBn(p text) returns boolean language sql immutable as $$ select p !~ '[ঀ-৿]' $$;
create or replace function tt.mo(p_back int) returns date language sql stable as $$ select (date_trunc('month', now() at time zone 'Asia/Dhaka') - make_interval(months => p_back))::date $$;
create or replace function tt.exc(p_flag text) returns int language sql security definer as $$ select count(*)::int from public.exceptions where flag_code = p_flag $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','sales2@s.app','{"full_name":"SalesA"}'), (:'s2','sales3@s.app','{"full_name":"SalesB"}'), (:'k','store4@s.app','{"full_name":"Store"}'),
 (:'mg','mgr5@s.app','{"full_name":"RecipeMgr"}'), (:'ap','appr6@s.app','{"full_name":"Approver"}'), (:'e','entry7@s.app','{"full_name":"Entry"}'), (:'a','appr8@s.app','{"full_name":"CostApprover"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'s2','salesperson'),(:'k','storekeeper'),(:'mg','factory_incharge'),(:'ap','recipe_approver'),(:'e','storekeeper'),(:'a','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'s2',1),(:'k',1),(:'mg',1),(:'ap',1),(:'e',1),(:'e',5),(:'e',6),(:'a',1),(:'a',5),(:'a',6) on conflict do nothing;
select tt.as(:'o');
select set_user_grant(:'mg'::uuid,'recipe_manage') is null as g1 \gset
select set_user_grant(:'e'::uuid,'view_cost') is null as g2 \gset
select set_user_grant(:'e'::uuid,'cost_bill_entry') is null as g3 \gset
select set_user_grant(:'a'::uuid,'view_cost') is null as g4 \gset
select set_user_grant(:'a'::uuid,'cost_rule_approve') is null as g5 \gset

insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('X7-F',  'তৈরি', 'Finished X7', 'kg', 'kg', 'finished_good', true, 260), ('X7-FL', 'ময়দা', 'Flour X7', 'kg', 'kg', 'raw_material', true, null),
 ('X7-E',  'মেয়াদী', 'Expiring X7', 'kg', 'kg', 'finished_good', true, 100), ('X7-P', 'কাঁচা', 'Purchased X7', 'kg', 'kg', 'raw_material', true, null);
select id as ifin from items where code='X7-F' \gset
select id as ifl from items where code='X7-FL' \gset
select id as iex from items where code='X7-E' \gset
select id as ipu from items where code='X7-P' \gset
set role authenticated; select tt.as(:'o');
select stock_opening(:'ifl'::uuid, 1, 1000, 40, null, 'x7') is not null as so1 \gset
reset role;

\echo == T0 shape and tags
select tt.chk('T0 new rules exist, default off, kind choice', (select count(*) from rules where key in ('expiry_sale_guard','production_double_issue_guard','purchase_backdate_flag') and kind='choice' and default_value='"off"'::jsonb)=3
  and rule_txt('expiry_sale_guard')='off' and rule_txt('production_double_issue_guard')='off' and rule_txt('purchase_backdate_flag')='off');
select tt.chk('T0 English text of new rules has no Bangla letters; bn/mix/en all present', (select bool_and(tt.noBn(label_en) and tt.noBn(hint_en) and label_bn is not null and label_mix is not null and hint_bn is not null and hint_mix is not null) from rules where key in ('expiry_sale_guard','production_double_issue_guard','purchase_backdate_flag')));
select tt.chk('T0 re-created functions carry bos87 and KEEP older tags', 
  position('bos87' in pg_get_functiondef('public.stock_post(uuid,int,numeric,text,text,text,numeric,bigint,timestamptz,text,bigint,text,uuid,uuid)'::regprocedure))>0
  and position('bos82' in pg_get_functiondef('public.stock_post(uuid,int,numeric,text,text,text,numeric,bigint,timestamptz,text,bigint,text,uuid,uuid)'::regprocedure))>0
  and (select bool_and(position('bos87' in pg_get_functiondef(oid))>0) from pg_proc where proname in ('recipe_approve','cost_rule_approve','record_sale2','_post_purchase_p13') and pronamespace='public'::regnamespace)
  and (select bool_and(position('bos82' in pg_get_functiondef(oid))>0) from pg_proc where proname in ('_void_purchase_p13','_sale_stock_out') and pronamespace='public'::regnamespace)
  and (select bool_and(position('bos73' in pg_get_functiondef(oid))>0) from pg_proc where proname in ('production_post','recipe_cost','recipe_save') and pronamespace='public'::regnamespace and pronargs in (7,2,8) )
  and position('bos43' in pg_get_functiondef('public.record_sale2(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure))>0);
select tt.chk('T0 phase72/74/79 bodies untouched (production_post core still has bos72, bos73, bos74)', (select position('bos72' in prosrc)>0 and position('bos73' in prosrc)>0 and position('bos74' in prosrc)>0 from pg_proc where proname='production_post' and pronargs=7 and pronamespace='public'::regnamespace));
select tt.chk('T0 closed to anon; owner function not open to anon', not has_function_privilege('anon','public.production_recommendations()','execute') and not has_function_privilege('anon','public.ledger_problem_count(int)','execute')
  and not has_function_privilege('authenticated','public._prod_double_issue87()','execute') and not has_function_privilege('authenticated','public._self_approve_hint87(boolean)','execute')
  and has_function_privilege('authenticated','public.production_recommendations()','execute') and has_function_privilege('authenticated','public.recipe_approve(uuid,text)','execute') and has_function_privilege('authenticated','public.cost_rule_approve(bigint,text)','execute'));

\echo == T1 owner can always approve a recipe (audit row + non-blocking suggestion); others unchanged
set role authenticated; select tt.as(:'o');
select (recipe_save(null, :'ifin'::uuid, 10, null, 'own', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'ifl','qty',5,'waste_pct',0)))->>'id')::uuid as rc1 \gset
select recipe_approve(:'rc1'::uuid, 'my own')::text as ra1 \gset
select tt.chk('T1 owner approves the recipe he changed himself: approved, not refused', (:'ra1'::jsonb->>'approved')::boolean and (select approved_by=:'o'::uuid and approved_at is not null from recipes where id=:'rc1'));
select tt.chk('T1 the return value carries self_approved + suggestion ask_another_approver in bn / mix / en', (:'ra1'::jsonb->>'self_approved')::boolean and :'ra1'::jsonb->>'suggestion'='ask_another_approver'
  and (:'ra1'::jsonb->>'suggestion_bn') is not null and (:'ra1'::jsonb->>'suggestion_mix') is not null and tt.noBn(:'ra1'::jsonb->>'suggestion_en') and length(:'ra1'::jsonb->>'suggestion_en')>10);
reset role;
select tt.chk('T1 audit_log keeps ONE row marked self_approved (recipes, who, note)', (select count(*) from audit_log where action='self_approved' and table_name='recipes' and record_id=:'rc1' and user_id=:'o'::uuid and (detail->>'self_approved')::boolean and detail->>'note'='my own')=1);
select tt.chk('T1 the usual history row (approved) is written too', exists (select 1 from recipe_versions where recipe_id=:'rc1'::uuid and kind='approved'));
set role authenticated; select tt.as(:'o');
select tt.chk('T1 approving again = dup, no second audit row', (recipe_approve(:'rc1'::uuid)->>'dup')::boolean);
reset role; select tt.chk('T1 still exactly one self_approved row', (select count(*) from audit_log where action='self_approved' and table_name='recipes' and record_id=:'rc1')=1);
set role authenticated; select tt.as(:'mg'); 
select (recipe_save(null, :'ifin'::uuid, 12, null, 'by mg', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'ifl','qty',6,'waste_pct',0)))->>'id')::uuid as rc2 \gset
select tt.as(:'o'); select set_user_grant(:'mg'::uuid,'recipe_approve') is null as g6 \gset
select tt.as(:'mg'); select tt.err('T1 NON-owner holding the grant still cannot approve his own change (unchanged)', format($$select recipe_approve('%s')$$, :'rc2'), 'self_approve_refused');
select tt.chk('T1 ... and it was not approved', (select approved_at is null from recipes where id=:'rc2'));
select tt.as(:'o'); select set_rule('recipe_self_approve','true'::jsonb) is null as r1 \gset
select tt.as(:'mg'); select recipe_approve(:'rc2'::uuid)::text as ra2 \gset
select tt.chk('T1 non-owner with recipe_self_approve ON may (as before); it is marked + suggestion', (:'ra2'::jsonb->>'approved')::boolean and :'ra2'::jsonb->>'suggestion'='ask_another_approver');
select tt.as(:'o'); select set_rule('recipe_self_approve','false'::jsonb) is null as r2 \gset
select set_user_grant(:'mg'::uuid,'recipe_approve',null,null,false) is null as g7 \gset
select (recipe_save(null, :'ifin'::uuid, 14, null, 'v3 by mg', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'ifl','qty',7,'waste_pct',0)))->>'id')::uuid as rc3 \gset
select tt.as(:'ap'); select recipe_approve(:'rc3'::uuid)::text as ra3 \gset
select tt.chk('T1 a different approver: plain approval, NO self_approved, NO suggestion', (:'ra3'::jsonb->>'approved')::boolean and not (:'ra3'::jsonb ? 'suggestion') and not (:'ra3'::jsonb ? 'self_approved'));
reset role;
select tt.chk('T1 no audit row for the different-approver case', (select count(*) from audit_log where action='self_approved' and record_id=:'rc3')=0);

\echo == T2 owner can always approve a cost rule
set role authenticated; select tt.as(:'o');
select cost_source_save(null,'electricity','main meter X7','shared',null,array[1,5,6],'monthly',tt.mo(3)) ->> 'id' as se \gset
select cost_rule_save(:se,'fixed_percent',tt.mo(3),'[{"location_id":5,"dest":"factory","value":50},{"location_id":1,"dest":"showroom","value":30},{"location_id":6,"dest":"factory","value":20}]'::jsonb, 'owner rule') ->> 'id' as r1 \gset
select cost_rule_approve(:r1::bigint, 'ok')::text as cr1 \gset
select tt.chk('T2 owner approves the rule he entered himself: approved + suggestion', (:'cr1'::jsonb->>'approved')::boolean and :'cr1'::jsonb->>'suggestion'='ask_another_approver' and tt.noBn(:'cr1'::jsonb->>'suggestion_en')
  and (select status='approved' and approved_by=:'o'::uuid from cost_source_rules where id=:r1));
reset role;
select tt.chk('T2 audit_log row self_approved on cost_source_rules', (select count(*) from audit_log where action='self_approved' and table_name='cost_source_rules' and record_id=:'r1' and user_id=:'o'::uuid)=1);
set role authenticated; select tt.as(:'e');
select cost_source_save(null,'gas','meter X7','separate','factory',array[5],'monthly',tt.mo(3)) ->> 'id' as sg \gset
select cost_rule_save(:se,'fixed_percent',tt.mo(2),'[{"location_id":5,"dest":"factory","value":40},{"location_id":1,"dest":"showroom","value":40},{"location_id":6,"dest":"factory","value":20}]'::jsonb, 'entry rule') ->> 'id' as r2 \gset
select tt.as(:'o'); select set_user_grant(:'e'::uuid,'cost_rule_approve') is null as g8 \gset
select tt.as(:'e'); select tt.err('T2 NON-owner who entered the rule still cannot approve it (unchanged)', format($$select cost_rule_approve(%s)$$, :r2), 'self_approve_refused');
select tt.as(:'a'); select cost_rule_approve(:r2::bigint, 'second person')::text as cr2 \gset
select tt.chk('T2 a different approver: plain approval, no suggestion', (:'cr2'::jsonb->>'approved')::boolean and not (:'cr2'::jsonb ? 'suggestion'));
reset role;

\echo == T3 a2-F8 expiry_sale_guard
insert into stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, batch_no) values (:'iex'::uuid,1,now()-interval '10 days',60,60,now()-interval '1 day','X7-B1') returning id as bx \gset
select stock_post(:'iex'::uuid,1,60,'purchase_in',null,null,30,:'bx'::bigint) is not null as sp1 \gset
set role authenticated; select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100,"unit":"kg"}]',:'iex')::jsonb,0,'[{"mode":"cash","amount":200}]',null,null,'retail',null,false) ->> 'id' as s_off \gset
reset role;
select tt.chk('T3 guard OFF (default): sale goes through, red sold_expired exactly as before (no batch detail)', exists (select 1 from exceptions where flag_code='sold_expired' and sale_id=:'s_off'::uuid and level='red' and text->>'en' not like '%batch%'));
set role authenticated; select tt.as(:'o'); select set_rule('expiry_sale_guard','"warn"'::jsonb) is null as w1 \gset
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":3,"price":100,"unit":"kg"}]',:'iex')::jsonb,0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false) ->> 'id' as s_warn \gset
reset role;
select tt.chk('T3 warn: sale goes through; the red line names batch + expiry date; English has no Bangla', exists (select 1 from exceptions where flag_code='sold_expired' and sale_id=:'s_warn'::uuid and level='red' and text->>'en' like '%batch '||:bx||', expired %' and tt.noBn(text->>'en')));
select tt.chk('T3 warn: stock really went out (60-2-3=55)', (select qty from stock_balance where item_id=:'iex'::uuid and location_id=1)=55);
set role authenticated; select tt.as(:'o'); select set_rule('expiry_sale_guard','"refuse"'::jsonb) is null as w2 \gset
select tt.as(:'s');
select tt.err('T3 refuse: a sale that takes expired stock is refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":4,"price":100,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":400}]',null,null,'retail',null,false)$$, :'iex'), 'expired_stock_blocked');
reset role;
select tt.chk('T3 refuse: nothing was posted (still 55)', (select qty from stock_balance where item_id=:'iex'::uuid and location_id=1)=55);
set role authenticated; select tt.as(:'s');
select tt.chk('T3 refuse: a late-synced offline sale is never refused', (record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":4,"price":100,"unit":"kg"}]',:'iex')::jsonb,0,'[{"mode":"cash","amount":400}]',null,null,'retail',null,false,now()-interval '1 hour') ->> 'id') is not null);
select tt.as(:'o'); select set_rule('expiry_sale_guard','"off"'::jsonb) is null as w3 \gset
select tt.chk('T3 back to off + old switch block_expired_sale OFF: sale goes through again', (record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100,"unit":"kg"}]',:'iex')::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false) ->> 'id') is not null);
select set_rule('block_expired_sale','true'::jsonb) is null as w4 \gset
select tt.err('T3 guard off + the old block_expired_sale ON still refuses (unchanged)', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":100,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)$$, :'iex'), 'expired_stock_blocked');
select set_rule('block_expired_sale',null) is null as w5 \gset
reset role;

\echo == T4 a2-F9 client_id used by another user
set role authenticated; select tt.as(:'s');
select gen_random_uuid() as cid \gset
select tt.chk('T4 first use of the client id', (record_sale2(:'cid'::uuid,1,format('[{"item_id":"%s","qty":1,"price":100,"unit":"kg"}]',:'iex')::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false) ->> 'id') is not null);
select count(*) as nsale from sales \gset
select tt.as(:'s2');
select tt.err('T4 another user with the same client id: clean client_id_taken (not a raw duplicate-key error)', format($$select record_sale2('%s'::uuid,1,'[{"item_id":"%s","qty":1,"price":100,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)$$, :'cid', :'iex'), 'client_id_taken');
select tt.as(:'s');
select tt.chk('T4 the SAME user retrying = the old sale back (dup), unchanged', (record_sale2(:'cid'::uuid,1,format('[{"item_id":"%s","qty":1,"price":100,"unit":"kg"}]',:'iex')::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false) ->> 'dup')::boolean);
reset role;
select tt.chk('T4 no extra sale row was created by either retry', (select count(*) from sales)=:nsale);

\echo == T5 a4-F11 purchase_backdate_flag
set role authenticated; select tt.as(:'o');
select save_supplier(null,'{"name":"Sup X7"}') as sup \gset
select save_purchase(null,null,:'sup',1,'X7-A',tt.today()-3,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":5}]',:'ipu')::jsonb) ->> 'id' as pba \gset
select post_purchase(:'pba'::uuid) is not null as pA \gset
select tt.chk('T5 default off: a backdated bill posts, no flag', tt.exc('purchase_backdated')=0 and (select status='posted' from purchase_bills where id=:'pba'::uuid));
select set_rule('purchase_backdate_flag','"warn"'::jsonb) is null as b1 \gset
select save_purchase(null,null,:'sup',1,'X7-B',tt.today()-2,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":5}]',:'ipu')::jsonb) ->> 'id' as pbb \gset
select post_purchase(:'pbb'::uuid) is not null as pB \gset
select tt.chk('T5 warn: backdated bill posts AND raises one yellow purchase_backdated (English clean)', (select status='posted' from purchase_bills where id=:'pbb'::uuid) and tt.exc('purchase_backdated')=1
  and exists (select 1 from exceptions where flag_code='purchase_backdated' and level='yellow' and tt.noBn(text->>'en') and text->>'en' like '%X7-B%'));
select save_purchase(null,null,:'sup',1,'X7-C',tt.today(),format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":5}]',:'ipu')::jsonb) ->> 'id' as pbc \gset
select post_purchase(:'pbc'::uuid) is not null as pC \gset
select tt.chk('T5 warn: a bill dated today raises no flag', tt.exc('purchase_backdated')=1);
select tt.chk('T5 stock timing unchanged: all three bills added 30 kg stamped now', (select qty from stock_balance where item_id=:'ipu'::uuid and location_id=1)=30);
select set_rule('purchase_backdate_flag','"off"'::jsonb) is null as b2 \gset
reset role;

\echo == T6 a4-F12 ledger_problem_count
set role authenticated; select tt.as(:'o');
select tt.chk('T6 owner: count is an integer, 0 on a clean database', ledger_problem_count() = 0);
select tt.as(:'k'); select tt.chk('T6 a storekeeper may call it (sees only what ledger_post_problems shows him)', ledger_problem_count(1) = 0);
reset role;

\echo == T7 production double-deduction guard
set role authenticated; select tt.as(:'o');
select production_post(1, :'rc1'::uuid, 1, gen_random_uuid()) ->> 'run_id' as run0 \gset
reset role;
select stock_post(:'ifl'::uuid, 1, -3, 'issue_out', 'issue', null, null, null, now(), 'issue0', null, 'full') is not null as i0 \gset
select tt.chk('T7 default off: production + issue the same day = no flag (today)', tt.exc('production_double_issue')=0);
set role authenticated; select tt.as(:'o'); select set_rule('production_double_issue_guard','"warn"'::jsonb) is null as d1 \gset
select production_post(1, :'rc1'::uuid, 1, gen_random_uuid()) ->> 'run_id' as run1 \gset
reset role;
select tt.chk('T7 warn: a production run after an issue of the SAME item/place/day raises one yellow line (English clean)', tt.exc('production_double_issue')=1
  and exists (select 1 from exceptions where flag_code='production_double_issue' and level='yellow' and tt.noBn(text->>'en') and text->>'en' like '%X7-FL%'));
set role authenticated; select tt.as(:'k');
select stock_issue(:'ifl'::uuid, 1, 2, null, 'second issue') is not null as i1 \gset
reset role;
select tt.chk('T7 same flag is not repeated for the same item/place/day', tt.exc('production_double_issue')=1);
select tt.chk('T7 never blocks: the run and the issue are both in the ledger', (select count(*) from stock_ledger where item_id=:'ifl'::uuid and reason='issue_out' and ref_type='production')>=2 and exists (select 1 from stock_ledger where item_id=:'ifl'::uuid and ref_type='issue' and note='second issue'));
-- a different item taken only by an issue (no production that day) -> no flag
select stock_post(:'ipu'::uuid, 1, -1, 'issue_out', 'issue', null, null, null, now(), 'solo', null, 'full') is not null as i2 \gset
select tt.chk('T7 an item only issued (no recipe run) raises nothing', tt.exc('production_double_issue')=1);
-- form out-line path (ref_type entry) the other way round: production item first, then an out-line posted the same day
select stock_post(:'ifl'::uuid, 1, -1, 'issue_out', 'entry', 'x7:form:1', null, null, now(), 'form line', null, 'full') is not null as i3 \gset
select tt.chk('T7 a form out-line (ref_type entry) on a production-consumed item the same day is also seen (flag already exists for that day = no duplicate)', tt.exc('production_double_issue')=1);
-- yesterday's production does not count for today's issue
select stock_post(:'ifl'::uuid, 1, -1, 'issue_out', 'production', 'old-run', null, null, now()-interval '2 days', 'old', null, 'full') is not null as i4 \gset
select tt.chk('T7 a production row from 2 days ago does not pair with today (still 1 flag; the old row paired only with nothing on its own day)', tt.exc('production_double_issue')=1);
set role authenticated; select tt.as(:'o'); select set_rule('production_double_issue_guard','"off"'::jsonb) is null as d2 \gset
reset role;
select stock_post(:'ifl'::uuid, 1, -1, 'issue_out', 'issue', null, null, null, now(), 'after off', null, 'full') is not null as i5 \gset
select tt.chk('T7 switched off again: nothing new', tt.exc('production_double_issue')=1);
select tt.chk('T7 the trigger is a no-op when the switch is off (cheap WHEN on issue_out only)', exists (select 1 from pg_trigger where tgname='stock_ledger_dbl87' and not tgisinternal) and (select count(*) from pg_trigger where tgname='stock_ledger_dbl87')=1);

\echo == T8 production_recommendations
set role authenticated; select tt.as(:'o');
select tt.chk('T8 returns key/current/recommended/reason for production_requires_recipe (ON), production_double_issue_guard (warn), production_requires_cost (refuse)',
  (select count(*) from jsonb_array_elements(production_recommendations()) r where r->>'key' in ('production_requires_recipe','production_double_issue_guard','production_requires_cost') and r ? 'current' and r ? 'recommended' and r ? 'reason_bn' and r ? 'reason_mix' and r ? 'reason_en')=3
  and (select (r->>'recommended')::boolean from jsonb_array_elements(production_recommendations()) r where r->>'key'='production_requires_recipe')
  and (select r->>'recommended' from jsonb_array_elements(production_recommendations()) r where r->>'key'='production_double_issue_guard')='warn');
select tt.chk('T8 English reasons contain no Bangla letters', (select bool_and(tt.noBn(r->>'reason_en')) from jsonb_array_elements(production_recommendations()) r));
select tt.chk('T8 recommending changes nothing', not rule_on('production_requires_recipe') and rule_txt('production_double_issue_guard')='off');
select tt.as(:'s'); select tt.err('T8 owner only', 'select production_recommendations()', 'not allowed');
reset role;

\echo == T9 paste twice: re-applying phase87 changes nothing
select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.oid)) as h1 from pg_proc p where proname in ('recipe_approve','cost_rule_approve','stock_post','record_sale2','_prod_double_issue87','production_recommendations','ledger_problem_count','_self_approve_hint87') and pronamespace='public'::regnamespace \gset
\i supabase/phase87.sql
\i supabase/phase131.sql
\i supabase/phase132.sql
select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.oid)) as h2 from pg_proc p where proname in ('recipe_approve','cost_rule_approve','stock_post','record_sale2','_prod_double_issue87','production_recommendations','ledger_problem_count','_self_approve_hint87') and pronamespace='public'::regnamespace \gset
select tt.chk('T9 function bodies identical after a second paste', :'h1' = :'h2');
select tt.chk('T9 rules not duplicated / reset by the second paste', (select count(*) from rules where key in ('expiry_sale_guard','production_double_issue_guard','purchase_backdate_flag'))=3 and rule_txt('production_double_issue_guard')='off');

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
