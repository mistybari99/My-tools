-- FRESH DB ONLY. Phase 102 tests (Step Img): item photo option rules, advisor rows, items_first_image RPC.
--   bash tests/sql/img_build.sh a102db ; psql -h /tmp -p 5544 -U postgres -d a102db -qAt -f supabase/phase102_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set n '00000000-0000-0000-0000-000000000004'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'n','none4@s.app','{"full_name":"Nobody"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'n','salesperson') on conflict do nothing;
insert into user_locations values (:'n',1) on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price, images) values
 ('IM1','IM1','IM1','kg','kg','finished_good',false,10,array['ITEMS/1/a.jpg','ITEMS/1/b.jpg']),
 ('IM2','IM2','IM2','kg','kg','finished_good',false,10,'{}'),
 ('IM3','IM3','IM3','kg','kg','finished_good',false,10,array['ITEMS/1/c.jpg']) on conflict do nothing;
select id as i1 from items where code='IM1' \gset
select id as i2 from items where code='IM2' \gset
select id as i3 from items where code='IM3' \gset

\echo == T0 rules + defaults
select tt.chk('T0 three rules exist with kinds', (select count(*) from rules where key='item_images_mode' and kind='choice')=1 and (select count(*) from rules where key='item_images_thumb_only' and kind='choice')=1 and (select count(*) from rules where key='item_images_cache_hours' and kind='number')=1);
select tt.chk('T0 defaults: mode off, thumb on, cache hours blank (no built-in number)', (select default_value from rules where key='item_images_mode')='"off"'::jsonb and (select default_value from rules where key='item_images_thumb_only')='"on"'::jsonb and (select default_value from rules where key='item_images_cache_hours') is null);
select tt.chk('T0 choices', (select choices from rules where key='item_images_mode')='["off","pos_only","everywhere"]'::jsonb);
select tt.chk('T0 advisor rows: 3, mode recommends pos_only, thumb on, hours none', (select count(*) from setup_rec_defs81 where phase='102')=3
  and (select rec_value from setup_rec_defs81 where code='item_images_mode')='"pos_only"'::jsonb and (select rec_value from setup_rec_defs81 where code='item_images_thumb_only')='"on"'::jsonb and (select rec_value from setup_rec_defs81 where code='item_images_cache_hours') is null);
select tt.chk('T0 advisor reason texts are non-empty (bn/mix/en)', (select bool_and(reason_bn<>'' and reason_mix<>'' and reason_en<>'') from setup_rec_defs81 where phase='102'));
select tt.chk('T0 no function of phases 72..99 changed: only items_first_image is new', to_regprocedure('public.items_first_image(uuid[])') is not null);

\echo == T1 RPC
select tt.as(:'o');
set role authenticated;
select tt.chk('T1 returns first path of items with a photo only', (select count(*) from items_first_image(array[:'i1'::uuid,:'i2'::uuid,:'i3'::uuid]))=2
  and (select path from items_first_image(array[:'i1'::uuid]))='ITEMS/1/a.jpg' and (select path from items_first_image(array[:'i3'::uuid]))='ITEMS/1/c.jpg');
select tt.chk('T1 empty / null input -> no rows, no error', (select count(*) from items_first_image('{}'::uuid[]))=0 and (select count(*) from items_first_image(null))=0);
select tt.chk('T1 more than 500 ids -> no rows', (select count(*) from items_first_image((select array_agg(gen_random_uuid()) from generate_series(1,501) g)))=0);
select tt.as(:'n');
select tt.chk('T1 any signed-in staff can call it (same as reading items)', (select count(*) from items_first_image(array[:'i1'::uuid]))=1);
reset role;
select tt.chk('T1 anon cannot call it', not has_function_privilege('anon','public.items_first_image(uuid[])','execute') and has_function_privilege('authenticated','public.items_first_image(uuid[])','execute'));
select tt.chk('T1 invoker (not definer) so RLS applies', (select not prosecdef from pg_proc where proname='items_first_image'));
select tt.chk('T1 returned columns', (select pg_get_function_result('public.items_first_image(uuid[])'::regprocedure))='TABLE(item_id uuid, path text)');
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
