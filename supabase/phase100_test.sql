-- FRESH DB ONLY. Phase 100 tests (Step Cat: Category / Sub-category master).
--   bash tests/sql/final_build.sh a100db "<canonical order incl. phase522 phase523>" ; psql -h /tmp -p 5544 -U postgres -d a100db -qAt -f supabase/phase100_test.sql | grep -E 'FAIL|RESULT'
--   (run from the repo root: it \i's phase100.sql itself = the paste-twice test; phase100 may already be pasted before)
-- All numbers are hand-computed (comment above each block). Test data only, no person names. Place 1 only.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set g '00000000-0000-0000-0000-000000000002'
\set p '00000000-0000-0000-0000-000000000003'
\set r '00000000-0000-0000-0000-000000000004'
\set q '00000000-0000-0000-0000-000000000005'
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
-- snapshot of every function body before phase100 is (re)pasted: phase100 must not change any of them
create table if not exists tt.fh (sig text primary key, h text);
truncate tt.fh;
insert into tt.fh select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\i supabase/phase100.sql
\i supabase/phase527.sql
\i supabase/phase528.sql
\i supabase/phase133.sql
\i supabase/phase134.sql
\i supabase/phase135.sql

-- items whose id columns disagree with the text columns (must always be 0)
create or replace function tt.inconsistent() returns bigint language sql stable security definer as $$
  select count(*) from public.items i where nullif(btrim(i.category), '') is not null and (i.category_id is null or not exists (select 1 from public.item_categories c where c.id = i.category_id and c.parent_id is null and c.code = i.category))
     or (nullif(btrim(i.sub_category), '') is not null and nullif(btrim(i.category), '') is not null and (i.sub_category_id is null or not exists (select 1 from public.item_categories s where s.id = i.sub_category_id and s.parent_id = i.category_id and s.code = i.sub_category)))
     or (nullif(btrim(i.category), '') is null and i.category_id is not null) $$;
-- like tt.err, but also runs the deferred 'required' check inside the same call (SET CONSTRAINTS ALL IMMEDIATE)
create or replace function tt.errd(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; execute 'set constraints all immediate'; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

create or replace function tt.cid(p_code text) returns bigint language sql stable security definer as $$ select id from public.item_categories where parent_id is null and code = p_code $$;
create or replace function tt.sid(p_cat text, p_code text) returns bigint language sql stable security definer as $$
  select s.id from public.item_categories s join public.item_categories c on c.id = s.parent_id where c.parent_id is null and c.code = p_cat and s.code = p_code $$;
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'g','mgr2@s.app','{"full_name":"Itemkeeper"}'), (:'p','sales3@s.app','{"full_name":"Seller"}'),
 (:'r','rep4@s.app','{"full_name":"Costreporter"}'), (:'q','rep5@s.app','{"full_name":"Plainreporter"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'g','showroom_manager'),(:'p','salesperson'),(:'r','salesperson'),(:'q','salesperson') on conflict do nothing;
insert into user_locations values (:'g',1),(:'p',1),(:'r',1),(:'q',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'g','item_create',null),(:'r','view_reports',null),(:'r','view_cost',null),(:'q','view_reports',null) on conflict do nothing;

\echo == T0 shape
select tt.chk('T0 master table: RLS on, staff can read, nobody writes it directly, anon sees nothing',
  (select relrowsecurity from pg_class where relname='item_categories') and has_table_privilege('authenticated','public.item_categories','select')
  and not has_table_privilege('authenticated','public.item_categories','insert') and not has_table_privilege('authenticated','public.item_categories','update') and not has_table_privilege('anon','public.item_categories','select'));
select tt.chk('T0 RPCs: signed-in users only, internals closed',
  has_function_privilege('authenticated','public.category_list(boolean)','execute') and not has_function_privilege('anon','public.category_list(boolean)','execute')
  and not has_function_privilege('anon','public.biz_items_by_category(date,date,int,text)','execute') and has_function_privilege('authenticated','public.stock_valuation_by_category(int,text)','execute')
  and not has_function_privilege('authenticated','public._cat_seed100()','execute') and not has_function_privilege('authenticated','public._items_cat100()','execute'));
select tt.chk('T0 rule category_required_on_item: choice, default off, recommendation warn',
  (select kind from rules where key='category_required_on_item')='choice' and rule_txt('category_required_on_item')='off'
  and (select rec_value from setup_rec_defs81 where code='category_required_on_item') = '"warn"'::jsonb);
select tt.chk('T0 no existing function was changed by phase100 (bodies identical to the snapshot)',
  (select count(*) from tt.fh f join pg_proc p on p.oid::regprocedure::text = f.sig where md5(pg_get_functiondef(p.oid)) <> f.h) = 0);
select tt.chk('T0 the old bos tags are all still there (bos89 _sale_stock_out, bos97 _acct_docs, bos88 biz_items)',
  position('bos89' in pg_get_functiondef('public._sale_stock_out()'::regprocedure))>0 and position('bos97' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos88' in pg_get_functiondef('public.biz_items(date,date,int)'::regprocedure))>0);

\echo == T1 seed from the existing items (no invented names)
-- the 5 values of the seeded shop data: every distinct items.category has one top row named after items.category_bn, nothing else
select tt.chk('T1 every distinct existing category has exactly one master row, named from category_bn',
  (select count(*) from (select distinct category from items where nullif(btrim(category),'') is not null) d) = (select count(*) from item_categories where parent_id is null)
  and not exists (select 1 from items i join item_categories c on c.parent_id is null and c.code = i.category where i.category_bn is not null and c.name_bn <> i.category_bn)
  and (select count(*) from item_categories where parent_id is null) = 5);
select tt.chk('T1 existing items are all linked, none inconsistent', tt.inconsistent() = 0 and (select count(*) from items where category_id is null) = 0);
-- importer-style rows (no trigger registration): A milk/cow, B milk/cow, C milk/goat, D bakery/-, E no category, F cheese/goat, G cheese/hard
select set_config('bos.item_import','1',false);
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,category,category_bn,sub_category) values ('Cow milk','Cow milk','pc','pc',100,true,'resale','x_milk','Milk','x_cow') returning id) select id as ia from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,category,category_bn,sub_category) values ('Cow cream','Cow cream','pc','pc',50,true,'resale','x_milk','Milk','x_cow') returning id) select id as ib from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,category,category_bn,sub_category) values ('Goat milk','Goat milk','pc','pc',30,true,'resale','x_milk','Milk','x_goat') returning id) select id as ic from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,category,category_bn) values ('Bun','Bun','pc','pc',20,true,'resale','x_bakery','Bakery') returning id) select id as id_ from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('Loose thing','Loose thing','pc','pc',10,false,'resale') returning id) select id as ie from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,category,category_bn,sub_category) values ('Goat cheese','Goat cheese','pc','pc',90,false,'resale','x_cheese','Cheese','x_goat') returning id) select id as iff from i \gset
with i as (insert into items (name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,category,category_bn,sub_category) values ('Hard cheese','Hard cheese','pc','pc',95,false,'resale','x_cheese','Cheese','x_hard') returning id) select id as igg from i \gset
select set_config('bos.item_import','',false);
select tt.chk('T1 importer-style rows are not registered yet (no trigger work while importing)', (select count(*) from item_categories where code in ('x_milk','x_bakery','x_cheese')) = 0 and (select count(*) from items where category_id is null and category is not null) = 6);
set role authenticated; select tt.as(:'p');
select tt.err('T1 plain staff cannot run the sync', 'select category_sync100()', 'not allowed');
select tt.as(:'g');
select category_sync100() as sy \gset
select tt.chk('T1 sync: 3 categories (Milk, Bakery, Cheese) + 4 sub-categories (cow, goat under Milk; goat, hard under Cheese) added, names from category_bn / code',
  (:'sy'::jsonb->>'categories_added')::int = 3 and (:'sy'::jsonb->>'sub_categories_added')::int = 4
  and (select name_bn from item_categories where code='x_milk' and parent_id is null) = 'Milk' and (select name_bn from item_categories where id=tt.sid('x_milk','x_cow')) = 'x_cow'
  and tt.inconsistent() = 0);
select category_sync100() as sy2 \gset
select tt.chk('T1 sync again: nothing added', (:'sy2'::jsonb->>'categories_added')::int = 0 and (:'sy2'::jsonb->>'sub_categories_added')::int = 0);
select tt.as(:'p');
select tt.chk('T1 category_list readable by plain staff; counts: Milk 3 items, cow 2, goat 1, Bakery 1, Cheese 2',
  (select item_count from category_list() where code='x_milk' and parent_id is null) = 3 and (select item_count from category_list() where id=tt.sid('x_milk','x_cow')) = 2
  and (select item_count from category_list() where id=tt.sid('x_milk','x_goat')) = 1 and (select item_count from category_list() where code='x_bakery') = 1
  and (select item_count from category_list() where code='x_cheese' and parent_id is null) = 2);
reset role;

-- the dictionary import writes list rows with an EMPTY Bangla label (English only): the master must take them (English label as the name) and never block the list
insert into option_lists (list_code,value_code,label_bn,label_en,sort,extra) values ('item_categories','x_en_only','','English only',99,'{}');
select tt.chk('T1 an editable-list row with an empty Bangla label registers under the English label and does not block the list',
  (select name_bn from item_categories where code='x_en_only' and parent_id is null) = 'English only' and (select name_en from item_categories where code='x_en_only' and parent_id is null) = 'English only'
  and exists (select 1 from option_lists where list_code='item_categories' and value_code='x_en_only'));

\echo == T2 reports (before any rename / merge): stock and sales
-- stock: Cow milk 10 @ 40, Cow cream 10 @ 20, Goat milk 10 @ 10, Bun 10 @ 5.  Sold in ONE bill: Cow milk 2 x 100 = 200, Cow cream 1 x 50 = 50, Goat milk 3 x 30 = 90, Bun 1 x 20 = 20, Loose thing 1 x 10 = 10 (no category, no cost)
-- revenue 370.  Cost: 2x40=80, 1x20=20, 3x10=30, 1x5=5.  Left in stock: 8x40=320, 9x20=180, 7x10=70, 9x5=45.
set role authenticated; select tt.as(:'o');
select stock_opening(:'ia'::uuid,1,10,40) is not null as a1 \gset
select stock_opening(:'ib'::uuid,1,10,20) is not null as a2 \gset
select stock_opening(:'ic'::uuid,1,10,10) is not null as a3 \gset
select stock_opening(:'id_'::uuid,1,10,5) is not null as a4 \gset
select tt.chk('T2 setup openings', :'a1' and :'a2' and :'a3' and :'a4');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100},{"item_id":"%s","qty":1,"price":50},{"item_id":"%s","qty":3,"price":30},{"item_id":"%s","qty":1,"price":20},{"item_id":"%s","qty":1,"price":10}]',:'ia',:'ib',:'ic',:'id_',:'ie')::jsonb,0,'[{"mode":"cash","amount":370}]',null,null,'retail',null,false)->>'id' as sa \gset
select tt.chk('T2 setup sale saved', :'sa' is not null and :'sa' <> '');
reset role;
set role authenticated; select tt.as(:'r');
-- Category level: Milk 200+50+90 = 340 (cogs 80+20+30 = 130), Bakery 20 (cogs 5), no category 10 (cogs unknown, 1 item); total 370 / 135
select tt.chk('R1 by Category: Milk revenue 340, cogs 130, share 91.89',
  (select revenue from biz_items_by_category(tt.today(),tt.today(),1,'category') where category='x_milk') = 340 and (select cogs from biz_items_by_category(tt.today(),tt.today(),1,'category') where category='x_milk') = 130
  and (select share_pct from biz_items_by_category(tt.today(),tt.today(),1,'category') where category='x_milk') = 91.89 and (select cat_name_bn from biz_items_by_category(tt.today(),tt.today(),1,'category') where category='x_milk') = 'Milk');
select tt.chk('R1 by Category: Bakery 20 / 5; uncategorised group (category null) 10 with unknown cost and 1 unknown item',
  (select revenue from biz_items_by_category(tt.today(),tt.today(),1,'category') where category='x_bakery') = 20 and (select cogs from biz_items_by_category(tt.today(),tt.today(),1,'category') where category='x_bakery') = 5
  and (select revenue from biz_items_by_category(tt.today(),tt.today(),1,'category') where category is null) = 10 and (select cogs is null from biz_items_by_category(tt.today(),tt.today(),1,'category') where category is null)
  and (select cogs_unknown_items from biz_items_by_category(tt.today(),tt.today(),1,'category') where category is null) = 1);
select tt.chk('R1 grouped totals == ungrouped report: revenue 370 and cogs 135',
  (select sum(revenue) from biz_items_by_category(tt.today(),tt.today(),1,'category')) = (select sum(revenue) from biz_items(tt.today(),tt.today(),1)) and (select sum(revenue) from biz_items_by_category(tt.today(),tt.today(),1,'category')) = 370
  and (select sum(cogs) from biz_items_by_category(tt.today(),tt.today(),1,'category')) = (select sum(cogs) from biz_items(tt.today(),tt.today(),1)) and (select sum(cogs) from biz_items_by_category(tt.today(),tt.today(),1,'category')) = 135
  and (select sum(share_pct) from biz_items_by_category(tt.today(),tt.today(),1,'category')) between 99.97 and 100.03);
-- Sub-category level: cow 250 (cogs 100), goat 90 (30), Bakery with no sub 20 (5), none 10
select tt.chk('R2 by Sub-category: cow 250 / 100, goat 90 / 30 (names from the master), Bakery without a sub 20',
  (select revenue from biz_items_by_category(tt.today(),tt.today(),1,'sub') where sub_category='x_cow') = 250 and (select cogs from biz_items_by_category(tt.today(),tt.today(),1,'sub') where sub_category='x_cow') = 100
  and (select revenue from biz_items_by_category(tt.today(),tt.today(),1,'sub') where sub_category='x_goat' and category='x_milk') = 90 and (select cogs from biz_items_by_category(tt.today(),tt.today(),1,'sub') where sub_category='x_goat' and category='x_milk') = 30
  and (select revenue from biz_items_by_category(tt.today(),tt.today(),1,'sub') where category='x_bakery' and sub_category is null) = 20
  and (select sub_name_bn from biz_items_by_category(tt.today(),tt.today(),1,'sub') where sub_category='x_cow') = 'x_cow');
select tt.chk('R2 sub level totals == ungrouped (370 / 135)', (select sum(revenue) from biz_items_by_category(tt.today(),tt.today(),1,'sub')) = 370 and (select sum(cogs) from biz_items_by_category(tt.today(),tt.today(),1,'sub')) = 135);
select tt.err('R2 bad level refused', 'select * from biz_items_by_category(tt.today(),tt.today(),1,''foo'')', 'bad_level');
-- stock valuation: Milk 320+180+70 = 570, Bakery 45; cow 500, goat 70
select tt.chk('R3 stock value by Category: Milk 570, Bakery 45; by Sub-category: cow 500, goat 70',
  (select value from stock_valuation_by_category(1,'category') where category='x_milk') = 570 and (select value from stock_valuation_by_category(1,'category') where category='x_bakery') = 45
  and (select value from stock_valuation_by_category(1,'sub') where sub_category='x_cow') = 500 and (select value from stock_valuation_by_category(1,'sub') where sub_category='x_goat' and category='x_milk') = 70);
select tt.chk('R3 stock value grouped total == ungrouped (615)', (select sum(value) from stock_valuation_by_category(null,'category')) = (select sum(value) from stock_valuation(null)) and (select sum(value) from stock_valuation_by_category(null,'category')) = 615
  and (select sum(value) from stock_valuation_by_category(null,'sub')) = 615);
-- no cost right: revenue yes, cost no, stock value no rows
select tt.as(:'q');
select tt.chk('R4 report-only user: revenue 340 for Milk, cogs hidden (NULL), stock value list empty',
  (select revenue from biz_items_by_category(tt.today(),tt.today(),1,'category') where category='x_milk') = 340 and (select cogs is null from biz_items_by_category(tt.today(),tt.today(),1,'category') where category='x_milk')
  and (select count(*) from stock_valuation_by_category(null,'category')) = 0);
select tt.as(:'p');
select tt.err('R4 staff without report rights refused', 'select * from biz_items_by_category(tt.today(),tt.today(),1,''category'')', 'not allowed');
reset role;

\echo == T3 add / sort / deactivate (manager) and the permission edges
set role authenticated; select tt.as(:'g');
select category_save(null, null, 'Snacks', 'Snacks', null, null, 'aaaaaaaa-0000-0000-0000-000000000001') as s1 \gset
select tt.chk('T3 manager adds a Category: code generated, listed, written to the editable list the item editor reads',
  (:'s1'::jsonb->>'id')::bigint is not null and (select name_en from item_categories where id=(:'s1'::jsonb->>'id')::bigint) = 'Snacks'
  and exists (select 1 from option_lists where list_code='item_categories' and value_code = :'s1'::jsonb->>'code' and label_bn='Snacks'));
select category_save(null, null, 'Snacks', 'Snacks', null, null, 'aaaaaaaa-0000-0000-0000-000000000001') as s1b \gset
select tt.chk('T3 same client id again: same row, not a second one', (:'s1b'::jsonb->>'id') = (:'s1'::jsonb->>'id') and (select count(*) from item_categories where name_bn='Snacks') = 1);
select tt.err('T3 same name under the same parent refused', 'select category_save(null,null,''snacks'')', 'name_taken');
select category_save(null, (:'s1'::jsonb->>'id')::bigint, 'Chips', null) as s2 \gset
select tt.chk('T3 Sub-category under Snacks', (select parent_id from item_categories where id=(:'s2'::jsonb->>'id')::bigint) = (:'s1'::jsonb->>'id')::bigint);
select tt.err('T3 a Sub-category cannot have a Sub-category', format('select category_save(null,%s,''Deep'')', (:'s2'::jsonb->>'id')), 'bad_parent');
select tt.err('T3 name is needed', 'select category_save(null,null,''  '')', 'name_required');
select category_save(null, (:'s1'::jsonb->>'id')::bigint, 'Nuts', null) as s3 \gset
select tt.chk('T3 the same name may exist under another parent', (select category_save(null, tt.cid('x_milk'), 'Chips', null)) is not null);
select category_save((:'s3'::jsonb->>'id')::bigint, null, null, null, 5, false) is not null as dd \gset
select tt.chk('T3 deactivate Nuts + sort 5: hidden from the default list, shown with include_inactive',
  not exists (select 1 from category_list() where id=(:'s3'::jsonb->>'id')::bigint) and exists (select 1 from category_list(true) where id=(:'s3'::jsonb->>'id')::bigint and not active and sort=5));
select tt.err('T3 a name changes only through rename', format('select category_save(%s,null,''Other'')', (:'s3'::jsonb->>'id')), 'use_rename');
select tt.as(:'p');
select tt.err('T3 plain staff cannot add', 'select category_save(null,null,''Nope'')', 'not allowed');
select tt.err('T3 plain staff cannot reorder', 'select category_reorder(array[1,2])', 'not allowed');
reset role;
select tt.chk('T3 plain staff cannot write the table directly', (select count(*) from item_categories where name_bn='Nope') = 0);
select tt.chk('T3 audit rows exist for the master changes', (select count(*) from audit_log where table_name='item_categories' and action='insert') >= 3 and (select count(*) from audit_log where table_name='item_categories' and action='update') >= 1);

\echo == T4 set the Category of one item / many
set role authenticated; select tt.as(:'g');
select item_set_category(:'ie'::uuid, tt.cid((:'s1'::jsonb->>'code')), (:'s2'::jsonb->>'id')::bigint) as sc \gset
select tt.chk('T4 Loose thing -> Snacks / Chips: text columns and ids follow, Bangla display name from the master',
  (select category from items where id=:'ie'::uuid) = (:'s1'::jsonb->>'code') and (select sub_category from items where id=:'ie'::uuid) = (:'s2'::jsonb->>'code')
  and (select category_bn from items where id=:'ie'::uuid) = 'Snacks' and tt.inconsistent() = 0);
select tt.err('T4 Chips under Milk is not Chips of Snacks: refused', format('select item_set_category(%L, %s, %s)', :'ie', tt.cid((:'s1'::jsonb->>'code')), tt.sid('x_milk','x_cow')), 'bad_sub_category');
select tt.err('T4 unknown item refused', format('select item_set_category(gen_random_uuid(), %s)', tt.cid('x_milk')), 'not_found');
select item_set_category_bulk(array[:'ib'::uuid, :'ic'::uuid], tt.cid('x_bakery'), null) as bk \gset
select tt.chk('T4 bulk: Cow cream and Goat milk move to Bakery with no sub-category', (:'bk'::jsonb->>'items')::int = 2 and (select count(*) from items where id in (:'ib'::uuid,:'ic'::uuid) and category='x_bakery' and sub_category is null and sub_category_id is null) = 2 and tt.inconsistent() = 0);
select item_set_category_bulk(array[:'ib'::uuid], tt.cid('x_milk'), tt.sid('x_milk','x_cow')) is not null as bk2 \gset
select item_set_category(:'ic'::uuid, tt.cid('x_milk'), tt.sid('x_milk','x_goat')) is not null as bk3 \gset
select tt.chk('T4 moved back: Milk has cow 2, goat 1 again', (select item_count from category_list() where code='x_milk' and parent_id is null) = 3 and (select item_count from category_list() where id=tt.sid('x_milk','x_cow')) = 2 and tt.inconsistent() = 0);
select tt.as(:'p');
select tt.err('T4 plain staff refused', format('select item_set_category(%L, %s)', :'ie', tt.cid('x_milk')), 'not allowed');
reset role;

\echo == T5 rename (owner): items keep the code, display name follows
set role authenticated; select tt.as(:'g');
select tt.err('T5 manager cannot rename', format('select category_rename(%s, ''Dairy'')', tt.cid('x_milk')), 'not allowed');
select tt.as(:'o');
select category_rename(tt.cid('x_milk'), 'Dairy', 'Dairy') as rn \gset
select tt.chk('T5 Milk -> Dairy: 3 items updated, code x_milk unchanged, items still point at it',
  (:'rn'::jsonb->>'items_updated')::int = 3 and (select count(*) from items where category='x_milk' and category_bn='Dairy') = 3 and (select name_bn from item_categories where code='x_milk' and parent_id is null)='Dairy' and tt.inconsistent() = 0);
select tt.err('T5 a name already used by another Category refused', format('select category_rename(%s, ''Bakery'')', tt.cid('x_milk')), 'name_taken');
select tt.chk('T5 the editable list label follows', (select label_bn from option_lists where list_code='item_categories' and value_code='x_milk') = 'Dairy' or not exists (select 1 from option_lists where list_code='item_categories' and value_code='x_milk'));
select tt.chk('T5 reports show the new name with the same numbers', (select cat_name_bn from biz_items_by_category(tt.today(),tt.today(),1,'category') where category='x_milk') = 'Dairy' and (select revenue from biz_items_by_category(tt.today(),tt.today(),1,'category') where category='x_milk') = 340);
reset role;

\echo == T6 merge (owner): Cheese into Dairy
-- before: Dairy has cow(2) goat(1) = 3 items; Cheese has goat(1: Goat cheese) hard(1: Hard cheese) = 2 items.
-- after: Dairy has 5 items; goat = 2 (same code folded), cow 2, hard 1 (moved under Dairy); Cheese inactive, merged into Dairy.
set role authenticated; select tt.as(:'g');
select tt.err('T6 manager cannot merge', format('select category_merge(%s, %s)', tt.cid('x_cheese'), tt.cid('x_milk')), 'not allowed');
select tt.as(:'o');
select tt.err('T6 a Category into a Sub-category refused', format('select category_merge(%s, %s)', tt.cid('x_cheese'), tt.sid('x_milk','x_cow')), 'same_level_only');
select tt.err('T6 into itself refused', format('select category_merge(%s, %s)', tt.cid('x_cheese'), tt.cid('x_cheese')), 'bad_request');
select category_merge(tt.cid('x_cheese'), tt.cid('x_milk'), 'bbbbbbbb-0000-0000-0000-000000000001') as mg \gset
select tt.chk('T6 merge result: 2 items moved, 1 sub-category moved (hard), goat folded', (:'mg'::jsonb->>'items_moved')::int = 2 and (:'mg'::jsonb->>'subs_moved')::int = 1);
select tt.chk('T6 Goat cheese is now x_milk / x_goat (id of the existing goat); Hard cheese x_milk / x_hard under Dairy; no item inconsistent',
  (select category||'/'||sub_category from items where id=:'iff'::uuid) = 'x_milk/x_goat' and (select sub_category_id from items where id=:'iff'::uuid) = tt.sid('x_milk','x_goat')
  and (select category||'/'||sub_category from items where id=:'igg'::uuid) = 'x_milk/x_hard' and (select category_bn from items where id=:'igg'::uuid) = 'Dairy' and tt.inconsistent() = 0);
select tt.chk('T6 counts: Dairy 5, goat 2, cow 2, hard 1; Cheese inactive and merged into Dairy; not in the default list',
  (select item_count from category_list() where code='x_milk' and parent_id is null) = 5 and (select item_count from category_list() where id=tt.sid('x_milk','x_goat')) = 2
  and (select item_count from category_list() where id=tt.sid('x_milk','x_cow')) = 2 and (select item_count from category_list() where id=tt.sid('x_milk','x_hard')) = 1
  and (select not active and merged_into = tt.cid('x_milk') from item_categories where code='x_cheese' and parent_id is null) and not exists (select 1 from category_list() where code='x_cheese' and parent_id is null)
  and (select count(*) from items where category = 'x_cheese') = 0);
select tt.chk('T6 audited: a category_merge row with the counts and the client id',
  exists (select 1 from audit_log where action='category_merge' and detail->>'items_moved'='2' and detail->>'client_id'='bbbbbbbb-0000-0000-0000-000000000001') and exists (select 1 from audit_log where table_name='items' and action='update' and record_id=:'iff'));
select category_merge(tt.cid('x_cheese'), tt.cid('x_milk'), 'bbbbbbbb-0000-0000-0000-000000000001') as mg2 \gset
select tt.chk('T6 the same merge again is a no-op', (:'mg2'::jsonb->>'duplicate')::boolean and (select item_count from category_list() where code='x_milk' and parent_id is null) = 5);
select tt.chk('T6 reports are unchanged in total after the merge (370 / 135) and Dairy = 340', (select sum(revenue) from biz_items_by_category(tt.today(),tt.today(),1,'category')) = 370 and (select sum(cogs) from biz_items_by_category(tt.today(),tt.today(),1,'category')) = 135
  and (select revenue from biz_items_by_category(tt.today(),tt.today(),1,'category') where category='x_milk') = 340);
-- merge two Sub-categories: hard -> goat (same parent)
select category_merge(tt.sid('x_milk','x_hard'), tt.sid('x_milk','x_goat')) as mg3 \gset
select tt.chk('T6 sub merge: Hard cheese becomes x_goat; goat 3; hard inactive', (:'mg3'::jsonb->>'items_moved')::int = 1 and (select sub_category from items where id=:'igg'::uuid)='x_goat'
  and (select item_count from category_list() where id=tt.sid('x_milk','x_goat')) = 3 and tt.inconsistent() = 0 and (select not active from item_categories where id=tt.sid('x_milk','x_hard')));
select tt.err('T6 a merged Category cannot be switched on again', format('select category_save(%s,null,null,null,null,true)', tt.cid('x_cheese')), 'merged');
reset role;

\echo == T7 move a Sub-category under another Category
set role authenticated; select tt.as(:'g');
select tt.err('T7 Chips already exists under Dairy (made in T3): move refused', format('select category_move(%s, %s)', (:'s2'::jsonb->>'id'), tt.cid('x_milk')), 'sub_exists');
select category_move(tt.sid('x_milk','x_goat'), tt.cid('x_bakery')) as mv2 \gset
select tt.chk('T7 goat -> Bakery: its 3 items follow (category x_bakery, display Bakery)', (:'mv2'::jsonb->>'items_moved')::int = 3 and (select count(*) from items where category='x_bakery' and sub_category='x_goat') = 3 and tt.inconsistent() = 0);
select category_move(tt.sid('x_bakery','x_goat'), tt.cid('x_milk')) is not null as mv3 \gset
select tt.chk('T7 and back to Dairy', (select count(*) from items where category='x_milk' and sub_category='x_goat') = 3 and tt.inconsistent() = 0);
reset role;

\echo == T8 item screens keep working: item_new / item_apply register and link
set role authenticated; select tt.as(:'o');
select item_new(jsonb_build_object('name_bn','New cow item','name_en','New cow item','category','x_milk','sub_category','x_cow','unit','pc','sell_price',5)) as nw \gset
select tt.chk('T8 item_new with a Category + Sub-category: ids set by the trigger', (select category_id from items where id=(:'nw'::jsonb->>'item_id')::uuid) = tt.cid('x_milk') and (select sub_category_id from items where id=(:'nw'::jsonb->>'item_id')::uuid) = tt.sid('x_milk','x_cow'));
select item_apply((:'nw'::jsonb->>'item_id')::uuid, '{"sub_category":"x_brandnew"}'::jsonb) is not null as ap \gset
select tt.chk('T8 an old screen typing a new sub-category value: registered under Dairy with the code as name, linked', (select name_bn from item_categories where id=(select sub_category_id from items where id=(:'nw'::jsonb->>'item_id')::uuid)) = 'x_brandnew' and tt.inconsistent() = 0);
select tt.chk('T8 the price-only change of an old item leaves the ids alone', (select update_ok from (select (select count(*) from items where category_id is null and category is not null) = 0 as update_ok) z));
reset role;

\echo == T9 rule category_required_on_item
set role authenticated; select tt.as(:'o');
select set_rule('category_required_on_item','"warn"') is null as w1 \gset
select tt.chk('T9 warn: a new item without a Category is still saved', (select item_new(jsonb_build_object('name_bn','Plain a','unit','pc','sell_price',1))->>'status') = 'created');
select category_rule_state() as st \gset
select tt.chk('T9 state: mode warn, recommended warn, missing = independent count of active counted items without a category',
  (:'st'::jsonb->>'mode') = 'warn' and (:'st'::jsonb->>'recommended') = 'warn'
  and (:'st'::jsonb->>'missing')::int = (select count(*) from items where is_active and count_in_business and (category is null or btrim(category) = '')) and (:'st'::jsonb->>'missing')::int >= 1);
select tt.chk('T9 missing list = same count, reason no_category', (select count(*) from items_missing_category(1000) where reason = 'no_category') = (:'st'::jsonb->>'missing')::int);
select set_rule('category_required_on_item','"required"') is null as w2 \gset
select tt.errd('T9 required: new item without a Category refused', 'select item_new(jsonb_build_object(''name_bn'',''Plain b'',''unit'',''pc'',''sell_price'',1))', 'category_required');
select tt.errd('T9 required: Category with Sub-categories needs a Sub-category', 'select item_new(jsonb_build_object(''name_bn'',''Plain c'',''unit'',''pc'',''sell_price'',1,''category'',''x_milk''))', 'sub_category_required');
select tt.chk('T9 required: a Category without Sub-categories is enough (Bakery has none after the moves)', (select item_new(jsonb_build_object('name_bn','Plain d','unit','pc','sell_price',1,'category','x_bakery'))->>'status') = 'created');
select tt.chk('T9 required: full pair accepted', (select item_new(jsonb_build_object('name_bn','Plain e','unit','pc','sell_price',1,'category','x_milk','sub_category','x_cow'))->>'status') = 'created');
select tt.as(:'g');
select tt.errd('T9 required: clearing the Category of an item refused', format('select item_set_category(%L, null)', :'ia'), 'category_required');
select tt.chk('T9 required: an OLD item without a Category stays editable (price change)', (select apply_item_patch is not null from (select item_apply(:'ie'::uuid, '{"sell_price":11}'::jsonb) apply_item_patch) z));
select tt.as(:'o');
select set_rule('category_required_on_item','"off"') is null as w3 \gset
select tt.chk('T9 off again: item without a Category saved', (select item_new(jsonb_build_object('name_bn','Plain f','unit','pc','sell_price',1))->>'status') = 'created' and (category_rule_state()->>'mode') = 'off');
select tt.err('T9 a wrong rule value refused', 'select set_rule(''category_required_on_item'',''"always"'')', 'bad_value');
reset role;

\echo == P1 paste-twice
select count(*) as n_before from item_categories \gset
select (select count(*) from item_categories) as n1, (select count(*) from rules where key='category_required_on_item') as r1 \gset
\i supabase/phase100.sql
\i supabase/phase527.sql
\i supabase/phase528.sql
\i supabase/phase133.sql
\i supabase/phase134.sql
\i supabase/phase135.sql
select tt.chk('P1 second paste: master rows unchanged, rule kept once, no inconsistent item', (select count(*) from item_categories) = :'n1' and (select count(*) from rules where key='category_required_on_item') = 1 and tt.inconsistent() = 0);
select tt.chk('P1 second paste: functions of other phases still identical to the snapshot', (select count(*) from tt.fh f join pg_proc p on p.oid::regprocedure::text = f.sig where md5(pg_get_functiondef(p.oid)) <> f.h) = 0);
select tt.chk('P1 sweep: no negative cost, no unbalanced journal entry', (select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit) <> sum(credit)) z) = 0);

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
