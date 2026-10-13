-- FRESH DB ONLY. Phase 45 tests (owner board).
--   ORDER="phase8 ... phase28 phase45" bash tests/sql/build_fresh_db.sh <db> ; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase45_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set h '00000000-0000-0000-0000-000000000004'
\set t '00000000-0000-0000-0000-000000000005'
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
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}'), (:'h','head4@s.app','{"full_name":"Head"}'), (:'t','mgr5@s.app','{"full_name":"Manager Two"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'h','owner') on conflict do nothing;   -- a second owner, to prove rows are private per owner

\echo == shape
select tt.chk('E0 table has RLS and no write grants', (select relrowsecurity from pg_class where relname='owner_board_items')
  and not has_table_privilege('authenticated','owner_board_items','insert') and not has_table_privilege('authenticated','owner_board_items','delete') and has_table_privilege('authenticated','owner_board_items','select'));
select tt.chk('E0 anon has no execute', not has_function_privilege('anon','owner_board_save(jsonb)','execute') and not has_function_privilege('anon','owner_board_get()','execute'));
select tt.chk('E0 helper not callable by the browser', not has_function_privilege('authenticated','_ob_kinds()','execute'));
select tt.chk('E0 the switch exists and is ON', (select default_value from rules where key='owner_board_on')='true');

\echo == who may use it
set role authenticated; select tt.as(:'s');
select tt.err('E1 staff cannot save', $$select owner_board_save('[{"widget":"sales_vs"}]'::jsonb)$$, 'not allowed');
select tt.err('E1 staff cannot read', $$select owner_board_get()$$, 'not allowed');
select tt.chk('E1 staff sees no rows through the table', (select count(*) from owner_board_items)=0);

\echo == save and read
select tt.as(:'o');
select tt.chk('E2 empty board to start', owner_board_get()='[]'::jsonb);
select owner_board_save('[{"widget":"sales_vs","config":{"size":"wide","warn_lt":0}},{"widget":"note","config":{"text":"check cash counts","repeat":"daily"}},{"widget":"cust_dues","enabled":false}]'::jsonb) ->> 'count' as c1 \gset
select tt.chk('E2 three saved', :'c1'='3');
select tt.chk('E2 order and fields kept', (select string_agg(x->>'widget',',' order by (x->>'sort')::int) from jsonb_array_elements(owner_board_get()) x)='sales_vs,note,cust_dues'
  and (owner_board_get()->2->>'enabled')='false' and (owner_board_get()->0->'config'->>'size')='wide');
select owner_board_save('[{"widget":"note","config":{"text":"b"}},{"widget":"sales_vs"}]'::jsonb) ->> 'count' as c2 \gset
select tt.chk('E2 save replaces the list atomically', :'c2'='2' and (select count(*) from owner_board_items where user_id=:'o')=2 and (owner_board_get()->0->>'widget')='note');
select tt.chk('E2 the same kind may appear twice (two notes)', (owner_board_save('[{"widget":"note"},{"widget":"note"}]'::jsonb)->>'count')='2');

\echo == validation
select tt.err('E3 unknown widget', $$select owner_board_save('[{"widget":"drop_table"}]'::jsonb)$$, 'bad_widget');
select tt.err('E3 not an array', $$select owner_board_save('{"widget":"note"}'::jsonb)$$, 'bad_items');
select tt.err('E3 null', $$select owner_board_save(null)$$, 'bad_items');
select tt.err('E3 item not an object', $$select owner_board_save('[1]'::jsonb)$$, 'bad_item');
select tt.err('E3 missing widget', $$select owner_board_save('[{"config":{}}]'::jsonb)$$, 'bad_widget');
select tt.err('E3 config must be an object', $$select owner_board_save('[{"widget":"note","config":[1]}]'::jsonb)$$, 'bad_config');
select tt.err('E3 threshold must be a number', $$select owner_board_save('[{"widget":"sales_vs","config":{"warn_gt":"x"}}]'::jsonb)$$, 'bad_threshold');
select tt.err('E3 threshold range', $$select owner_board_save('[{"widget":"sales_vs","config":{"bad_gt":1e13}}]'::jsonb)$$, 'bad_threshold');
select tt.err('E3 size', $$select owner_board_save('[{"widget":"sales_vs","config":{"size":"huge"}}]'::jsonb)$$, 'bad_size');
select tt.err('E3 repeat', $$select owner_board_save('[{"widget":"note","config":{"repeat":"hourly"}}]'::jsonb)$$, 'bad_repeat');
select tt.err('E3 note too long', format($$select owner_board_save(%L::jsonb)$$, jsonb_build_array(jsonb_build_object('widget','note','config',jsonb_build_object('text',repeat('x',301))))), 'text_too_long');
select tt.err('E3 enabled must be boolean', $$select owner_board_save('[{"widget":"note","enabled":"yes"}]'::jsonb)$$, 'bad_item');
select tt.err('E3 config too big', format($$select owner_board_save(%L::jsonb)$$, jsonb_build_array(jsonb_build_object('widget','note','config',jsonb_build_object('text',repeat('x',300),'label',repeat('a',100),'route',repeat('b',100),'report',repeat('c',100),'table',repeat('d',100),'preset',repeat('e',100),'done_on',repeat('f',100),'zzz',repeat('z',3500))))), 'config_too_big');
select tt.err('E3 max 60 items', format($$select owner_board_save(%L::jsonb)$$, (select jsonb_agg(jsonb_build_object('widget','note')) from generate_series(1,61))), 'too_many_items');
select tt.chk('E3 exactly 60 is fine', (owner_board_save((select jsonb_agg(jsonb_build_object('widget','note')) from generate_series(1,60)))->>'count')='60');
select tt.chk('E3 a refused save kept the previous list (nothing half-written)', (select count(*) from owner_board_items where user_id=:'o')=60);

\echo == privacy between owners
select owner_board_save('[{"widget":"exceptions"}]'::jsonb) is not null as o1 \gset
select tt.as(:'h');
select tt.chk('E4 other owner starts with an empty board', owner_board_get()='[]'::jsonb and (select count(*) from owner_board_items)=0);
select owner_board_save('[{"widget":"backup"},{"widget":"page","config":{"route":"stock"}}]'::jsonb) is not null as h1 \gset
select tt.chk('E4 other owner has his own two', (select count(*) from owner_board_items)=2);
select tt.as(:'o');
select tt.chk('E4 first owner still has exactly his one, untouched', (select count(*) from owner_board_items)=1 and (owner_board_get()->0->>'widget')='exceptions');
select tt.err('E4 browser cannot write the table directly', $$insert into owner_board_items(user_id,widget) values (auth.uid(),'note')$$, 'permission denied');
select tt.err('E4 browser cannot delete directly', $$delete from owner_board_items$$, 'permission denied');


\echo == favourites: order, label, hide
select tt.as(:'s');
select tt.err('F1 order needs an array', $$select fav_order_set('{}'::jsonb)$$, 'bad_items');
select tt.err('F1 kind checked', $$select fav_order_set('[{"kind":"x","key":"a"}]'::jsonb)$$, 'bad_item');
select tt.err('F1 key length', format($$select fav_order_set(%L::jsonb)$$, jsonb_build_array(jsonb_build_object('kind','route','key',repeat('k',121)))), 'bad_item');
select set_pin('route','dues',true) is null as p1 \gset
select set_pin('route','items',true) is null as p2 \gset
select set_pin('form','14-1',true) is null as p3 \gset
select fav_order_set('[{"kind":"form","key":"14-1"},{"kind":"route","key":"items"},{"kind":"route","key":"dues"}]'::jsonb) as fo \gset
select tt.chk('F2 order saved by position', :'fo'=3 and (select string_agg(key,',' order by sort) from user_favourites where pinned)='14-1,items,dues');
select tt.chk('F2 setting the order does not unpin', (select count(*) from user_favourites where pinned)=3);
select fav_meta_set('route','items','  My items  ',false) is null as m1 \gset
select fav_meta_set('route','pos',null,true) is null as m2 \gset
select tt.chk('F3 label trimmed and kept', (select label from user_favourites where key='items')='My items');
select tt.chk('F3 hide creates an unpinned row', (select hidden and not pinned from user_favourites where key='pos'));
select tt.err('F3 label too long', format($$select fav_meta_set('route','items',%L,false)$$, repeat('x',41)), 'label_too_long');
select tt.as(:'k'); select tt.chk('F4 other people see none of it', (select count(*) from user_favourites where label is not null or hidden or sort is not null)=0);
select tt.as(:'o'); select tt.chk('F4 owner has none of the staff rows', (select count(*) from user_favourites where key in ('pos','items'))=0);
select tt.chk('F4 no execute for anon', not has_function_privilege('anon','fav_order_set(jsonb)','execute') and not has_function_privilege('anon','fav_meta_set(text,text,text,boolean)','execute'));

\echo == switch
reset role;
update rules set default_value='false' where key='owner_board_on';
set role authenticated; select tt.as(:'o');
select tt.err('E5 switch OFF refuses the save', $$select owner_board_save('[{"widget":"note"}]'::jsonb)$$, 'feature_off');
select tt.chk('E5 reading still works with the switch OFF', owner_board_get() is not null);
reset role;
update rules set default_value='true' where key='owner_board_on';
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
