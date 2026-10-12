-- FRESH DB ONLY. Phase 14 (item master) tests.
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14" bash tests/sql/build_fresh_db.sh <db>; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase14_test.sql
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set p '00000000-0000-0000-0000-000000000004'
\set m '00000000-0000-0000-0000-000000000005'
\set x '00000000-0000-0000-0000-000000000006'
\set v '00000000-0000-0000-0000-000000000008'
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
create or replace function tt.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'ok'; exception when others then return sqlerrm; end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
 (:'p','buy4@s.app','{"full_name":"Buyer"}'), (:'m','mgr5@s.app','{"full_name":"Mgr"}'), (:'x','far6@s.app','{"full_name":"Far"}'),
 (:'v','cost8@s.app','{"full_name":"CostOnly"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'k','storekeeper'),(:'p','purchasing'),(:'m','management'),(:'x','salesperson'),(:'v','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'p',1),(:'x',3),(:'v',1) on conflict do nothing;
select id as ia from items where code='I-001' \gset
select id as ib from items where code='I-002' \gset
select id as ic from items where code='I-016' \gset

\echo == T0 shape, defaults, legacy items untouched
select tt.chk('T0 8 item types and 8 class mappings', (select count(*) from item_types)=8 and (select count(*) from item_class_map)=8);
select tt.chk('T0 57 legacy items: all counted, finished_good (priced), prices intact', (select count(*) from items)=57 and (select count(*) from items where item_type='finished_good' and count_in_business and sellable and sell_price is not null)=57
  and (select sell_price from items where code='I-001')=260 and (select sell_price from items where code='I-003')=350);
select tt.chk('T0 new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('item_types','item_class_map','item_import_batches','item_mapping_review','item_master_links','assets','asset_costs') and c.relrowsecurity)=7);
select tt.chk('T0 rules defaults: tools off, register on, approval on, apply_ok off', not rule_on('tools_stock_on') and rule_on('asset_register_on') and rule_on('item_create_needs_approval') and not rule_on('item_master_apply_ok'));
select tt.chk('T0 grants item_create / asset_manage exist', (select count(*) from grant_defs where grant_code in ('item_create','asset_manage'))=2);
reset role;
select tt.chk('T0 default flags per type', (select o_count from _item_type_flags('finished_good')) and (select o_sell from _item_type_flags('resale')) and not (select o_sell from _item_type_flags('raw_material'))
  and not (select o_count from _item_type_flags('asset')) and not (select o_count from _item_type_flags('controlled')) and not (select o_count from _item_type_flags('consumable')) and (select o_count from _item_type_flags('packaging')));
select tt.chk('T0 unit map', _item_unit_code('pc')='pc' and _item_unit_code('pound')='lb' and _item_unit_code('gm')='gram' and _item_unit_code('ltr')='ltr' and _item_unit_code('xx') is null
  and (select count(*) from option_lists where list_code='units')=10 and (select label_bn from option_lists where list_code='units' and value_code='kg')='কেজি');
\i /home/user/My-tools/supabase/phase14.sql
select tt.chk('T0 phase14 re-runs; wrappers are not stacked', (select count(*) from pg_proc where proname in ('apply_item_patch','post_purchase','void_purchase'))=3
  and to_regprocedure('public._apply_item_patch_p12(uuid,jsonb)') is not null and position('bos12-details' in pg_get_functiondef('public.apply_item_patch(uuid,jsonb)'::regprocedure))>0 and (select count(*) from item_types)=8);
\i /home/user/My-tools/supabase/phase12.sql
select tt.chk('T0 phase12 re-run afterwards is a no-op for the wrapper', (select count(*) from pg_proc where proname='apply_item_patch')=1 and to_regprocedure('public._apply_item_patch_p12(uuid,jsonb)') is not null);

\echo == T1 import preview writes nothing; apply is idempotent
create temp table rows14 (j jsonb);
insert into rows14 values ('[
 {"code":"01-001","cat_no":"01","category":"Fixed Assets","name_en":"Mixer","name_bn":"মিক্সার","subcategory":"Machines","unit":"pc","control_class":"Asset","note":""},
 {"code":"01-002","cat_no":"01","category":"Fixed Assets","name_en":"Oven","name_bn":"ওভেন","subcategory":"Machines","unit":"pc","control_class":"Asset","note":""},
 {"code":"01-091","cat_no":"01","category":"Fixed Assets","name_en":"Chair","name_bn":"চেয়ার","subcategory":"Furniture","unit":"pc","control_class":"Asset","note":""},
 {"code":"01-093","cat_no":"01","category":"Fixed Assets","name_en":"RETIRED — Old table → 01-091","name_bn":"","subcategory":"Furniture","unit":"pc","control_class":"Asset","note":"Retired; merged into 01-091. Do not reuse this code."},
 {"code":"03-001","cat_no":"03","category":"Raw Materials","name_en":"Flour","name_bn":"ময়দা","subcategory":"Flour","unit":"kg","control_class":"Raw Material","note":""},
 {"code":"03-002","cat_no":"03","category":"Raw Materials","name_en":"Sugar","name_bn":"চিনি","subcategory":"Sweet","unit":"kg","control_class":"Raw Material","note":""},
 {"code":"05-001","cat_no":"05","category":"Packaging","name_en":"Box 1kg","name_bn":"বক্স","subcategory":"Boxes","unit":"pc","control_class":"Packaging","note":""},
 {"code":"14-001","cat_no":"14","category":"Finished Goods Sweet","name_en":"Roshogolla","name_bn":"রসগোল্লা","subcategory":"Chhana","unit":"kg","control_class":"Finished Good","note":""},
 {"code":"14-002","cat_no":"14","category":"Finished Goods Sweet","name_en":"Chomchom","name_bn":"চমচম","subcategory":"Chhana","unit":"kg","control_class":"Finished Good","note":""},
 {"code":"14-028","cat_no":"14","category":"Finished Goods Sweet","name_en":"Roshomalai","name_bn":"রসমালাই","subcategory":"Syrup","unit":"kg","control_class":"Finished Good","note":""},
 {"code":"17-001","cat_no":"17","category":"Kitchen Tools","name_en":"Ladle","name_bn":"হাতা","subcategory":"Tools","unit":"pc","control_class":"Controlled Item","note":""},
 {"code":"20-001","cat_no":"20","category":"Cleaning","name_en":"Soap","name_bn":"সাবান","subcategory":"Soap","unit":"pack","control_class":"Consumable","note":""},
 {"code":"19-001","cat_no":"19","category":"Electrical","name_en":"Wire","name_bn":"তার","subcategory":"Wire","unit":"meter","control_class":"Infrastructure Material","note":""},
 {"code":"08-001","cat_no":"08","category":"Biscuits","name_en":"Biscuit","name_bn":"বিস্কুট","subcategory":"Biscuit","unit":"pack","control_class":"Stock/Direct Sale","note":""},
 {"code":"99-001","cat_no":"99","category":"X","name_en":"Bad unit","name_bn":"","subcategory":"","unit":"yard","control_class":"Asset","note":""},
 {"code":"01-002","cat_no":"01","category":"Fixed Assets","name_en":"Oven dup","name_bn":"","subcategory":"","unit":"pc","control_class":"Asset","note":""}
]'::jsonb);
select j::text as rows14 from rows14 \gset
select count(*) as c_items0 from items \gset
select count(*) as c_opt0 from option_lists \gset
select count(*) as c_aud0 from audit_log \gset
set role authenticated; select tt.as(:'o');
select item_master_import_preview(:'rows14'::jsonb) as pv \gset
reset role;
select tt.chk('T1 preview counts: 16 rows, 14 to create (1 retired), 0 existing, 2 conflicts (unknown unit / duplicate code)', (:'pv'::jsonb->>'total')::int=16 and (:'pv'::jsonb->>'to_create')::int=14 and (:'pv'::jsonb->>'to_create_retired')::int=1
  and (:'pv'::jsonb->>'skip_existing')::int=0 and (:'pv'::jsonb->>'conflicts')::int=2);
select tt.chk('T1 preview by type', (:'pv'::jsonb->'by_type'->>'asset')::int=4 and (:'pv'::jsonb->'by_type'->>'raw_material')::int=2 and (:'pv'::jsonb->'by_type'->>'finished_good')::int=3 and (:'pv'::jsonb->'by_type'->>'controlled')::int=1);
select tt.chk('T1 preview lists the conflict reasons', (select string_agg(x->>'reason', ',' order by x->>'code') from jsonb_array_elements(:'pv'::jsonb->'conflict_list') x) like '%duplicate_in_file%' and (:'pv'::jsonb->'conflict_list')::text like '%unknown_unit%');
select tt.chk('T1 DRY RUN wrote nothing: items, option lists, audit log unchanged', (select count(*) from items)=:c_items0 and (select count(*) from option_lists)=:c_opt0 and (select count(*) from audit_log)=:c_aud0);
set role authenticated; select tt.as(:'s');
select tt.err('T1 preview is owner only', format($$select item_master_import_preview(%L::jsonb)$$, :'rows14'), 'not allowed');
select tt.err('T1 apply is owner only', format($$select item_master_import_apply(%L::jsonb,'b-staff')$$, :'rows14'), 'not allowed');
reset role; select tt.err('T1 anon cannot call apply', format($$set role anon; select item_master_import_apply(%L::jsonb,'b-anon')$$, :'rows14'), 'permission denied'); reset role;
set role authenticated; select tt.as(:'o');
select item_master_import_apply(:'rows14'::jsonb, 'test-batch-1', 16) as ap \gset
select tt.chk('T1 apply: 14 created, 1 retired, 2 conflicts', (:'ap'::jsonb->>'created')::int=14 and (:'ap'::jsonb->>'retired_created')::int=1 and (:'ap'::jsonb->>'conflicts')::int=2);
select item_master_import_apply(:'rows14'::jsonb, 'test-batch-1', 16) as ap2 \gset
select tt.chk('T1 apply twice (same batch): nothing created, all skipped', (:'ap2'::jsonb->>'created')::int=0 and (:'ap2'::jsonb->>'skipped_existing')::int=14);
select item_master_import_apply(:'rows14'::jsonb, 'test-batch-2') as ap3 \gset
reset role;
select tt.chk('T1 apply with another batch id: still nothing created; items not duplicated', (:'ap3'::jsonb->>'created')::int=0 and (select count(*) from items where import_batch is not null)=14 and (select count(*) from items)=71);
select tt.chk('T1 one audit line per batch (and no per-row item audit)', (select count(*) from audit_log where action='import' and record_id='test-batch-1')=1 and (select count(*) from audit_log where action='import' and record_id='test-batch-2')=1
  and (select count(*) from audit_log where table_name='items' and action='insert' and at > now() - interval '1 minute' and record_id in (select id::text from items where import_batch is not null))=0);
select tt.chk('T1 batch row counts', (select created from item_import_batches where batch_id='test-batch-1')=14 and (select chunks from item_import_batches where batch_id='test-batch-1')=2);
select tt.chk('T1 flags by type: asset not counted / not sellable; raw not sellable but counted; controlled off; FG sellable flag but NO price', 
  (select not count_in_business and not sellable from items where code='01-001') and (select count_in_business and not sellable from items where code='03-001') and (select not count_in_business from items where code='17-001')
  and (select count_in_business and sellable and sell_price is null from items where code='14-001') and (select count_in_business and sellable from items where code='08-001') and (select not count_in_business from items where code='20-001') and (select not count_in_business from items where code='19-001'));
select tt.chk('T1 retired row: inactive, reserved code, reason kept, not counted', (select not is_active and retired_at is not null and retired_reason like 'Retired%' and not count_in_business from items where code='01-093'));
select tt.chk('T1 category + subcategory lists created (bn empty allowed), units kept', (select label_en from option_lists where list_code='item_categories' and value_code='c01')='Fixed Assets' and (select label_bn from option_lists where list_code='item_categories' and value_code='c01')=''
  and (select count(*) from option_lists where list_code='item_subcategories')>=7 and (select unit from items where code='20-001')='pack' and (select unit from items where code='19-001')='meter' and (select unit from items where code='01-001')='pc');
select tt.chk('T1 old items untouched (57, prices, no type change)', (select count(*) from items where import_batch is null)=57 and (select sum(sell_price) from items where import_batch is null)=(select sum(sell_price) from items where code like 'I-%'));
-- chunked: second part of a file in several calls, resume after an interrupted chunk
set role authenticated; select tt.as(:'o');
select item_master_import_apply('[{"code":"02-001","cat_no":"02","category":"IT","name_en":"PC","name_bn":"","subcategory":"","unit":"pc","control_class":"Asset","note":""}]'::jsonb, 'test-batch-3', 2) as c1 \gset
select item_master_import_apply('[{"code":"02-001","cat_no":"02","category":"IT","name_en":"PC","name_bn":"","subcategory":"","unit":"pc","control_class":"Asset","note":""},{"code":"02-002","cat_no":"02","category":"IT","name_en":"Printer","name_bn":"","subcategory":"","unit":"pc","control_class":"Asset","note":""}]'::jsonb, 'test-batch-3', 2) as c2 \gset
reset role;
select tt.chk('T1 resume: an interrupted batch continues; the repeated row is skipped', (:'c1'::jsonb->>'created')::int=1 and (:'c2'::jsonb->>'created')::int=1 and (:'c2'::jsonb->>'skipped_existing')::int=1 and (select created from item_import_batches where batch_id='test-batch-3')=2 and (select name_bn from items where code='02-002')='Printer');
select tt.err('T1 more than 500 rows per call refused', 'select item_master_import_apply((select jsonb_agg(jsonb_build_object(''code'',''98-''||g)) from generate_series(1,501) g), ''test-big'')', 'too_many_rows');

\echo == T2 codes: next code, retired never reused, concurrency, categories
set role authenticated; select tt.as(:'o');
select tt.chk('T2 next code = highest suffix + 1 (01-093 is retired, so 01-094)', item_next_code('c01')='01-094');
select item_new('{"name_bn":"নতুন চেয়ার","category":"c01","item_type":"asset","unit":"pc"}'::jsonb) as n1 \gset
select tt.chk('T2 item_new gives 01-094, asset flags', (:'n1'::jsonb->>'code')='01-094' and (select not sellable and not count_in_business and item_type='asset' from items where code='01-094'));
select tt.chk('T2 next code moves on', item_next_code('c01')='01-095' and item_next_code('01')='01-095');
select tt.chk('T2 category without a number: no code preview', item_next_code('sweet_kg') is null and item_next_code('zzz') is null);
reset role;
update items set is_active=false, retired_at=now(), retired_reason='test' where code='01-094';
set role authenticated; select tt.as(:'o');
select tt.chk('T2 a retired code is never reused (01-094 retired -> next 01-095)', item_next_code('c01')='01-095');
select tt.err('T2 nothing is deleted (app role)', 'delete from items where code=''01-001''', 'permission denied');
reset role;
select tt.err('T2 item code cannot change', 'update items set code=''01-999'' where code=''01-001''', 'cannot be changed');
select tt.err('T2 delete as table owner is blocked too', 'delete from items where code=''01-001''', 'nothing is deleted');
set role authenticated; select tt.as(:'o');
select item_new('{"name_bn":"পুরনো ক্যাটাগরি","category":"sweet_kg","item_type":"finished_good","unit":"kg","sell_price":10}'::jsonb) ->> 'code' as oc \gset
select tt.chk('T2 old category (no number): the I- sequence continues (I-058)', :'oc'='I-058');
reset role; insert into option_lists (list_code,value_code,label_bn,label_en,sort,extra) values ('item_categories','myc','আমার','Mine',99,'{}');
set role authenticated; select tt.as(:'o');
select item_new('{"name_bn":"আমার আইটেম","category":"myc","item_type":"resale"}'::jsonb) as n2 \gset
select tt.chk('T2 owner-made category gets the next free number (after 20) -> code 21-001', (:'n2'::jsonb->>'code')='21-001' and (select extra->>'cat_no' from option_lists where value_code='myc')='21');
reset role;
\set conc `bash /home/user/My-tools/tests/sql/p14_conc.sh :DBNAME 00000000-0000-0000-0000-000000000001`
select tt.chk('T2 8 parallel creations in one category: 8 codes, all distinct, no error (' || :'conc' || ')', :'conc' = '8/8/0');
select tt.chk('T2 and the codes are consecutive', (select max(substring(code from 4)::int) - min(substring(code from 4)::int) from items where name_bn like 'conc %')=7);

\echo == T3 type rules, flags, lock
set role authenticated; select tt.as(:'o');
select tt.err('T3 bad type refused', 'select item_new(''{"name_bn":"x","item_type":"nope"}''::jsonb)', 'bad_item_type');
select item_apply((select id from items where code='03-001'), '{"sellable":true}'::jsonb);
select tt.chk('T3 raw material can never be sellable', (select not sellable from items where code='03-001'));
select item_apply((select id from items where code='01-001'), '{"sellable":true,"count_in_business":true}'::jsonb);
select tt.chk('T3 asset can never be sellable or counted', (select not sellable and not count_in_business from items where code='01-001'));
select item_apply((select id from items where code='20-001'), '{"item_type":"resale"}'::jsonb);
select tt.chk('T3 changing type starts from the new type defaults', (select item_type='resale' and count_in_business and sellable from items where code='20-001'));
select item_apply((select id from items where code='20-001'), '{"item_type":"consumable"}'::jsonb);
select tt.chk('T3 and back to consumable: not counted, not sellable', (select item_type='consumable' and not count_in_business and not sellable from items where code='20-001'));
select item_apply((select id from items where code='14-001'), '{"sell_price":300,"locked":true}'::jsonb);
select tt.chk('T3 owner sets a price and locks an item', (select locked and sell_price=300 from items where code='14-001'));
select tt.as(:'m');
select tt.err('T3 only the owner locks / unlocks (item_apply)', 'select item_apply((select id from items where code=''14-002''), ''{"locked":true}''::jsonb)', 'not allowed');
reset role; select tt.as(:'m');
select tt.chk('T3 locked item: a non-owner edit is refused', tt.try('update items set name_bn=''x'' where code=''14-001''')='item_locked');
select tt.chk('T3 locked item: a no-change touch is allowed', tt.try('update items set name_bn=name_bn where code=''14-001''')='ok');
select tt.as(:'o');
select tt.chk('T3 locked item: the owner may edit', tt.try('update items set details=''ok'' where code=''14-001''')='ok');
set role authenticated; select tt.as(:'o');
select item_apply((select id from items where code='14-001'), '{"locked":false}'::jsonb);
select tt.chk('T3 owner unlocks', (select not locked from items where code='14-001'));
select item_apply((select id from items where code='14-001'), '{"hidden":true}'::jsonb);
select tt.chk('T3 hidden is a flag only (still readable)', (select hidden from items where code='14-001') and (select count(*) from items where code='14-001')=1);
select item_apply((select id from items where code='14-001'), '{"hidden":false,"is_active":false,"retired_reason":"no longer made"}'::jsonb);
select tt.chk('T3 retire with a reason: inactive, retired_at, reason', (select not is_active and retired_at is not null and retired_reason='no longer made' from items where code='14-001'));
select item_apply((select id from items where code='14-001'), '{"is_active":true}'::jsonb);
select tt.chk('T3 reactivate clears the retirement', (select is_active and retired_at is null and retired_reason is null from items where code='14-001'));
select tt.err('T3 unknown field refused', format($$select item_apply(%L,'{"code":"zz"}'::jsonb)$$, (select id from items where code='14-001')), 'bad_field');
select tt.chk('T3 duplicate check finds the same name (and not itself)', (select count(*) from item_dup_check('রসগোল্লা', null, null))>=1 and (select count(*) from item_dup_check('রসগোল্লা', null, (select id from items where code='14-001')))=0);
reset role;

\echo == T4 who may add items (approval path)
set role authenticated; select tt.as(:'s');
select tt.chk('T4 staff without ITEMS enter cannot add', tt.try('select item_new(''{"name_bn":"নতুন S","category":"c14"}''::jsonb)')='not allowed');
reset role;
insert into role_form_perms (role_code, form_code, can_view, can_enter, can_approve) values ('salesperson','ITEMS',true,true,false) on conflict (role_code, form_code) do update set can_enter=true;
set role authenticated; select tt.as(:'s');
select item_new('{"name_bn":"অনুরোধ আইটেম","category":"c14","item_type":"finished_good","unit":"kg"}'::jsonb) as r1 \gset
select tt.chk('T4 rule on: a non-owner only files a request, nothing created', (:'r1'::jsonb->>'status')='pending' and not exists (select 1 from items where name_bn='অনুরোধ আইটেম'));
select tt.err('T4 requester cannot approve own', format($$select decide_item_change(%s, true)$$, (:'r1'::jsonb->>'id')), 'not allowed');
select tt.as(:'o');
select decide_item_change((:'r1'::jsonb->>'id')::bigint, true);
select tt.chk('T4 owner approves: item created with the next code in the category', (select code from items where name_bn='অনুরোধ আইটেম') ~ '^14-[0-9]{3}$');
select set_user_grant(:'m'::uuid, 'item_create');
select tt.as(:'m');
select item_new('{"name_bn":"গ্রান্ট আইটেম","category":"c14","item_type":"finished_good","unit":"kg"}'::jsonb) as g1 \gset
select tt.chk('T4 grant item_create: added at once', (:'g1'::jsonb->>'status')='created');
select tt.as(:'s');
select item_new('{"name_bn":"আরেকটা","category":"c14","item_type":"finished_good","unit":"kg"}'::jsonb) as r2 \gset
select tt.as(:'m');
select decide_item_change((:'r2'::jsonb->>'id')::bigint, true);
select tt.chk('T4 a grant-holder (not owner) approves a new-item request', exists (select 1 from items where name_bn='আরেকটা'));
select tt.as(:'o'); select set_user_grant(:'m'::uuid, 'item_create', null, null, false);
select tt.as(:'o'); select set_rule('item_create_needs_approval', 'false'::jsonb);
select tt.as(:'s');
select tt.chk('T4 rule off: anyone who may enter items adds at once', (select item_new('{"name_bn":"সরাসরি","category":"c14","item_type":"finished_good"}'::jsonb)->>'status')='created');
select tt.as(:'o'); select set_rule('item_create_needs_approval', 'true'::jsonb);
reset role;

\echo == T5 selling: only sellable, priced items
select id as i_fg from items where code='14-002' \gset
select id as i_asset from items where code='01-001' \gset
select id as i_raw from items where code='03-001' \gset
select id as i_cons from items where code='20-001' \gset
select id as i_nop from items where code='14-028' \gset
update items set sell_price=500 where code='14-002';
set role authenticated; select tt.as(:'o');
select tt.chk('T5 priced, sellable finished good: the sale goes through', (select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":500,"unit":"kg"}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":500}]',null,null,'retail',null,false)->>'receipt') is not null);
select tt.err('T5 item without a selling price and no override: refused (no_price)', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false)$$, :'i_nop'), 'no_price');
select tt.err('T5 item without a selling price, price typed over: refused (Data needed)', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":300,"unit":"kg","override":true}]'::jsonb,0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false)$$, :'i_nop'), 'item_not_sellable');
select tt.err('T5 asset refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":300,"override":true}]'::jsonb,0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false)$$, :'i_asset'), 'item_not_sellable');
select tt.err('T5 raw material refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":300,"override":true}]'::jsonb,0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false)$$, :'i_raw'), 'item_not_sellable');
select tt.err('T5 the old record_sale refuses an item without a price too', format($$select record_sale(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":300,"override":true}]'::jsonb,0,'cash',300,null,null,false)$$, :'i_nop'), 'item_not_sellable');
reset role;
update items set sell_price=50 where code='20-001';
set role authenticated; select tt.as(:'o');
select tt.err('T5 consumable with a price but sellable=false: refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":50}]'::jsonb,0,'[{"mode":"cash","amount":50}]',null,null,'retail',null,false)$$, :'i_cons'), 'item_not_sellable');
reset role; update items set sellable=false where code='14-002'; set role authenticated; select tt.as(:'o');
select tt.err('T5 sellable switched off: refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":500}]'::jsonb,0,'[{"mode":"cash","amount":500}]',null,null,'retail',null,false)$$, :'i_fg'), 'item_not_sellable');
reset role; update items set sellable=true, hidden=true where code='14-002'; set role authenticated; select tt.as(:'o');
select tt.chk('T5 hidden does not block a sale (pickers only)', (select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":500}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":500}]',null,null,'retail',null,false)->>'receipt') is not null);
reset role; update items set hidden=false where code='14-002';

\echo == T6 stock: only counted items; tools switch; reports
update items set unit='kg', base_unit='kg', tracked=true where code in ('14-002','03-001');
select tt.chk('T6 an uncounted item cannot be tracked (forced off)', tt.try('update items set tracked=true where code=''01-001''')='ok' and (select not tracked from items where code='01-001'));
set role authenticated; select tt.as(:'o');
select tt.err('T6 opening stock for an asset refused', format($$select stock_opening(%L,1,5,10)$$, :'i_asset'), 'item_not_tracked');
reset role;
select tt.err('T6 the ledger itself refuses an uncounted item', format($$insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason) values (%L, 1, 1, 1, 'opening')$$, :'i_cons'), 'item_not_counted');
set role authenticated; select tt.as(:'o');
select stock_opening((select id from items where code='14-002'), 1, 10, 100);
select stock_opening((select id from items where code='03-001'), 1, 40, 50);
select tt.chk('T6 counted items get stock', (select qty from stock_balance where item_id=(select id from items where code='14-002') and location_id=1)=10);
select tt.err('T6 count_in_business off while stock exists: refused', format($$select item_apply(%L,'{"count_in_business":false}'::jsonb)$$, (select id from items where code='03-001')), 'item_has_stock');
select tt.chk('T6 stock list shows counted items only', (select count(*) from stock_levels(1, '{"include_zero":true}') where code='01-001')=0 and (select count(*) from stock_levels(1, '{}') where code='03-001')=1);
select tt.chk('T6 stock value lists the counted item', (select count(*) from stock_valuation(1) where code='03-001')=1);
reset role;
set session_replication_role = replica; update items set count_in_business=false where code='03-001'; set session_replication_role = origin;
set role authenticated; select tt.as(:'o');
select tt.chk('T6 reports leave out count_in_business=false: stock value', (select count(*) from stock_valuation(1) where code='03-001')=0);
reset role; update items set count_in_business=true where code='03-001';
insert into item_costs (item_id, cost_price) values (:'i_fg'::uuid, 200) on conflict (item_id) do update set cost_price=200;
update sales set sale_date=current_date, sold_at=now() where status='done' and lines::text like '%' || :'i_fg' || '%';
set role authenticated; select tt.as(:'o');
select coalesce(sum(cogs),0) as cg1 from biz_daily(current_date - 30, current_date) \gset
reset role; set session_replication_role = replica; update items set count_in_business=false where code='14-002'; set session_replication_role = origin;
set role authenticated; select tt.as(:'o');
select coalesce(sum(cogs),0) as cg2 from biz_daily(current_date - 30, current_date) \gset
select tt.chk('T6 COGS of an uncounted item disappears from the profit report (before ' || :'cg1' || ', after ' || :'cg2' || ')', :'cg1'::numeric > 0 and :'cg2'::numeric = 0);
reset role; update items set count_in_business=true where code='14-002';
select tt.chk('T6 controlled items start uncounted', (select count(*) from items where item_type='controlled' and count_in_business)=0);
set role authenticated; select tt.as(:'o');
select set_rule('tools_stock_on', 'true'::jsonb);
select tt.chk('T6 tools switch on: controlled items are counted', (select count(*) from items where item_type='controlled' and not count_in_business and is_active)=0 and (select count_in_business from items where code='17-001'));
select item_new('{"name_bn":"নতুন টুল","category":"c17","item_type":"controlled"}'::jsonb) ->> 'code' as tc \gset
select tt.chk('T6 a new controlled item follows the switch', (select count_in_business from items where code=:'tc'));
select set_rule('tools_stock_on', 'false'::jsonb);
select tt.chk('T6 switch off: back to uncounted', (select count_in_business from items where code='17-001')=false);
reset role;

\echo == T7 asset register: purchase classification, costs, RLS
insert into suppliers (name) values ('Asset Sup') returning id as sa \gset
select id as i_chair from items where code='01-091' \gset
select id as i_sugar from items where code='03-002' \gset
set role authenticated; select tt.as(:'p');
select save_purchase(null,null,:'sa'::uuid,1,'A-1','2026-01-10'::date,format('[{"item_id":"%s","qty":3,"unit":"pc","unit_cost":1000},{"item_id":"%s","qty":2,"unit":"kg","unit_cost":40}]',:'i_chair',:'i_sugar')::jsonb) ->> 'id' as ab \gset
select post_purchase(:'ab'::uuid) as pr \gset
select tt.chk('T7 posting a bill with 3 chairs adds 3 register rows (result says so)', (:'pr'::jsonb->>'assets_added')::int=3 and (select count(*) from assets where item_id=:'i_chair'::uuid and purchase_bill_id=:'ab'::uuid)=3);
select tt.chk('T7 no stock for the asset: no ledger rows, no balance', (select count(*) from stock_ledger where item_id=:'i_chair'::uuid)=0 and (select count(*) from stock_balance where item_id=:'i_chair'::uuid)=0);
select tt.chk('T7 rows: location of the bill, buy date, condition new, unique tags', (select count(distinct tag)=3 and bool_and(location_id=1 and bought_on='2026-01-10' and condition='new' and status='in_use' and active) from assets where item_id=:'i_chair'::uuid));
select tt.as(:'s'); select tt.chk('T7 salesperson cannot read the cost', (select count(*) from asset_costs)=0);
select tt.as(:'o');
select tt.chk('T7 owner sees 3 costs of 1000', (select count(*) from asset_costs)=3 and (select min(cost) from asset_costs)=1000);
select tt.as(:'v'); select tt.chk('T7 cost-less staff sees the rows but no cost', (select count(*) from assets)=3 and (select count(*) from asset_costs)=0);
select tt.as(:'x'); select tt.chk('T7 a user at another location sees no rows', (select count(*) from assets)=0);
select tt.as(:'o'); select set_user_grant(:'v'::uuid, 'view_cost'); select tt.as(:'v');
select tt.chk('T7 view_cost grant shows the cost', (select count(*) from asset_costs)=3);
select tt.err('T7 no direct write to assets', 'update assets set note=''x''', 'permission denied');
select tt.err('T7 no direct write to costs', 'update asset_costs set cost=1', 'permission denied');
select tt.as(:'o');
select asset_add(jsonb_build_object('item_id',:'i_chair','location_id',1,'qty',2,'cost',1200,'condition','good','note','gift')) as aa \gset
select tt.chk('T7 asset_add: 2 rows, with cost, condition', (:'aa'::jsonb->>'count')::int=2 and (select count(*) from assets where note='gift' and condition='good')=2 and (select count(*) from asset_costs where cost=1200)=2);
select tt.err('T7 only asset items go in the register', format($$select asset_add(jsonb_build_object('item_id',%L,'location_id',1))$$, :'i_raw'), 'not_an_asset_item');
select tt.err('T7 bad condition refused', format($$select asset_add(jsonb_build_object('item_id',%L,'location_id',1,'condition','zz'))$$, :'i_chair'), 'bad_condition');
select tt.as(:'s'); select tt.err('T7 salesperson cannot add', format($$select asset_add(jsonb_build_object('item_id',%L,'location_id',1))$$, :'i_chair'), 'not allowed');
select tt.as(:'m'); select tt.chk('T7 management (asset_manage) may add', (select asset_add(jsonb_build_object('item_id',:'i_chair','location_id',1))->>'count')::int=1);
select tt.as(:'o'); select set_user_grant(:'v'::uuid, 'asset_manage'); select tt.as(:'v');
select tt.err('T7 a person with asset_manage but no ITEM_COST cannot write a cost', format($$select asset_update(%L,'{"cost":5}'::jsonb)$$, (select id from assets where note='gift' limit 1)), 'not allowed to change cost');
select tt.as(:'o');
select asset_update((select id from assets where note='gift' order by id limit 1), '{"condition":"fair","status":"under_repair","note":"fan fixed"}'::jsonb);
select tt.chk('T7 asset_update', (select count(*) from assets where status='under_repair' and condition='fair' and note='fan fixed')=1);
select tt.err('T7 maintenance link must be a 08-1 record', format($$select asset_update(%L,jsonb_build_object('maintenance_ref', %L::uuid))$$, (select id from assets where note='fan fixed'), gen_random_uuid()), 'bad_maintenance_ref');
reset role;
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values ('08-1', 1, 1, current_date, 'submitted', '{}', :'o') returning id as e81 \gset
set role authenticated; select tt.as(:'o');
select asset_update((select id from assets where note='fan fixed'), jsonb_build_object('maintenance_ref', :'e81'));
select tt.chk('T7 maintenance record linked', (select maintenance_ref from assets where note='fan fixed')=:'e81'::uuid);
select asset_retire((select id from assets where note='fan fixed'), 'scrapped', 'retired');
select tt.chk('T7 retire (not delete): inactive, reason, row kept', (select not active and status='retired' and retired_reason='scrapped' from assets where note='fan fixed'));
select tt.err('T7 retire needs a reason', format($$select asset_retire(%L,'')$$, (select id from assets where note='gift' limit 1)), 'note_required');
reset role;
select tt.err('T7 assets are never deleted', 'delete from assets', 'nothing is deleted');
select tt.chk('T7 a tag cannot change', tt.try('update assets set tag=''X'' where id=(select id from assets limit 1)') like '%immutable%');
set role authenticated; select tt.as(:'o');
select void_purchase(:'ab'::uuid, 'wrong bill') as vb \gset
select tt.chk('T7 voiding the bill retires its register rows', (:'vb'::jsonb->>'status')='void' and (select count(*) from assets where purchase_bill_id=:'ab'::uuid and active)=0 and (select count(*) from assets where purchase_bill_id=:'ab'::uuid and status='retired')=3);
select set_rule('asset_register_on', 'false'::jsonb); select tt.as(:'p');
select save_purchase(null,null,:'sa'::uuid,1,'A-2','2026-01-11'::date,format('[{"item_id":"%s","qty":1,"unit":"pc","unit_cost":900}]',:'i_chair')::jsonb) ->> 'id' as ab2 \gset
select post_purchase(:'ab2'::uuid) as pr2 \gset
select tt.chk('T7 register switch off: no rows added', (:'pr2'::jsonb->>'assets_added')::int=0 and (select count(*) from assets where purchase_bill_id=:'ab2'::uuid)=0);
select tt.as(:'o'); select set_rule('asset_register_on', 'true'::jsonb);
reset role;
select tt.err('T7 the old base functions are not callable by the app', 'set role authenticated; select _post_purchase_p13(gen_random_uuid(), null)', 'permission denied');
reset role;

\echo == T8 consumable purchase: no stock, no register
select id as i_soap from items where code='20-001' \gset
set role authenticated; select tt.as(:'p');
select save_purchase(null,null,:'sa'::uuid,1,'C-1','2026-01-12'::date,format('[{"item_id":"%s","qty":5,"unit":"pack","unit_cost":30}]',:'i_soap')::jsonb) ->> 'id' as cb \gset
select tt.chk('T8 consumable bill posts without stock lines', (select post_purchase(:'cb'::uuid)->>'status')='posted' and (select count(*) from stock_ledger where item_id=:'i_soap'::uuid)=0);
reset role;

\echo == T9 old seed items -> dictionary mapping
set role authenticated; select tt.as(:'o');
select item_mapping_load('[{"seed_code":"I-001","best_code":"14-001","confidence":0.6,"auto":0},{"seed_code":"I-002","best_code":"14-002","confidence":0.95,"auto":1},{"seed_code":"I-003","best_code":"14-777","confidence":0.97,"auto":1},{"seed_code":"I-999","best_code":"14-001","confidence":0.97,"auto":1}]'::jsonb) as ml \gset
select tt.chk('T9 mapping load: 3 rows kept, the unknown seed code skipped', (:'ml'::jsonb->>'loaded')::int=3 and (select count(*) from item_mapping_review)=3);
select tt.chk('T9 load twice changes nothing', (select (item_mapping_load('[{"seed_code":"I-001","best_code":"14-002","confidence":0.99,"auto":1}]'::jsonb)->>'skipped')::int)=1 and (select suggested_code from item_mapping_review r join items i on i.id=r.item_id where i.code='I-001')='14-001');
select item_mapping_autolink() as nl \gset
select tt.chk('T9 auto-link: only the high-confidence row whose target exists (I-002 -> 14-002)', :nl=1 and (select master_code from items where code='I-002')='14-002'
  and (select master_code from items where code='I-001') is null and (select master_code from items where code='I-003') is null);
select tt.chk('T9 the linked old item keeps its code and price; the dictionary twin is hidden', (select sell_price from items where code='I-002')=260 and (select hidden and not sellable from items where code='14-002'));
select tt.chk('T9 the rest stay on the needs-decision list', (select count(*) from item_mapping_review where status='pending')=2 and (select status from item_mapping_review r join items i on i.id=r.item_id where i.code='I-002')='linked');
select item_mapping_decide((select id from items where code='I-001'), '14-001', 'linked', 'owner chose');
select tt.chk('T9 manual link', (select master_code from items where code='I-001')='14-001' and (select count(*) from item_master_links where active)=2);
select tt.err('T9 one dictionary item cannot stand for two old items', format($$select item_mapping_decide(%L,'14-001','linked')$$, (select id from items where code='I-003')), 'master_code_taken');
select tt.err('T9 target must be a dictionary item', format($$select item_mapping_decide(%L,'I-005','linked')$$, (select id from items where code='I-003')), 'master_code_not_found');
select item_mapping_decide((select id from items where code='I-001'), null, 'rejected', 'wrong match');
select tt.chk('T9 reject/undo: link inactive (history kept), twin visible again', (select master_code from items where code='I-001') is null and (select count(*) from item_master_links where active)=1 and (select count(*) from item_master_links)=2 and (select not hidden from items where code='14-001'));
select tt.chk('T9 old item prices intact (I-001 260, I-003 350)', (select sell_price from items where code='I-001')=260 and (select sell_price from items where code='I-003')=350);
select tt.as(:'s'); select tt.err('T9 staff cannot decide', format($$select item_mapping_decide(%L,'14-001','linked')$$, (select id from items where code='I-003')), 'not allowed');
select tt.chk('T9 staff cannot read the review list', (select count(*) from item_mapping_review)=0);
reset role;

\echo == T10 settings tables
set role authenticated; select tt.as(:'o');
select item_type_set('consumable', '{"count_in_business":true}'::jsonb);
select tt.chk('T10 owner edits a type default (applies to new items)', (select count_in_business from item_types where code='consumable'));
select item_type_set('consumable', '{"count_in_business":false}'::jsonb);
select item_type_set('asset', '{"count_in_business":true,"sellable":true}'::jsonb);
select tt.chk('T10 the asset default cannot be turned into stock/sales', (select not count_in_business and not sellable from item_types where code='asset'));
select item_type_set('service', '{"label_bn":"সেবা","sellable":true,"count_in_business":false}'::jsonb);
select tt.chk('T10 owner adds a type', (select active and sellable from item_types where code='service'));
select item_type_set('service', '{"active":false}'::jsonb);
select item_class_map_set('Service Item', 'service');
select tt.chk('T10 class map edit; a type is retired, never deleted', (select item_type from item_class_map where control_class='Service Item')='service' and (select not active from item_types where code='service'));
select tt.as(:'s'); select tt.err('T10 staff cannot edit types', 'select item_type_set(''resale'', ''{"sellable":false}''::jsonb)', 'not allowed');
select tt.err('T10 staff cannot edit the class map', 'select item_class_map_set(''Asset'', ''resale'')', 'not allowed');
select tt.chk('T10 types and map are readable', (select count(*) from item_types)>=9 and (select count(*) from item_class_map)>=9);
reset role;
select tt.err('T10 no delete on types', 'set role authenticated; delete from item_types where code=''resale''', 'permission denied');
reset role;

select '--- FAILED: ' || count(*) filter (where not ok) || ' of ' || count(*) from tt.res;
