-- COPY of phase22_test.sql (phase22b): ONLY the two fixture deletes of stock_balance are wrapped so they still work after phase84 (the old file is untouched).
-- FRESH DB ONLY. Phase 22 (bulk item editor, old-item decisions) tests.
--   ORDER="phase8 ... phase21 phase22" bash tests/sql/build_fresh_db.sh w22db; psql -h /tmp -p 5544 -U postgres -d w22db -qAt -f supabase/phase22_test.sql
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set m '00000000-0000-0000-0000-000000000005'
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
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'k','store3@s.app','{"full_name":"Store"}'), (:'m','mgr5@s.app','{"full_name":"Mgr"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'k','storekeeper'),(:'m','management') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'m',1) on conflict do nothing;
insert into user_grants (user_id, grant_code) values (:'k','item_bulk');

-- dictionary items (owner import)
set role authenticated; select tt.as(:'o');
select item_master_import_apply('[
 {"code":"14-001","cat_no":"14","category":"Finished Goods Sweet","name_en":"Roshogolla","name_bn":"রসগোল্লা","subcategory":"Chhana","unit":"kg","control_class":"Finished Good","note":""},
 {"code":"14-002","cat_no":"14","category":"Finished Goods Sweet","name_en":"Chomchom","name_bn":"চমচম","subcategory":"Chhana","unit":"kg","control_class":"Finished Good","note":""},
 {"code":"14-003","cat_no":"14","category":"Finished Goods Sweet","name_en":"Sandesh","name_bn":"সন্দেশ","subcategory":"Chhana","unit":"kg","control_class":"Finished Good","note":""},
 {"code":"14-004","cat_no":"14","category":"Finished Goods Sweet","name_en":"Jilapi","name_bn":"জিলাপি","subcategory":"Fried","unit":"kg","control_class":"Finished Good","note":""},
 {"code":"15-001","cat_no":"15","category":"Resale","name_en":"Chips","name_bn":"চিপস","subcategory":"","unit":"pc","control_class":"Stock/Direct Sale","note":""},
 {"code":"01-001","cat_no":"01","category":"Fixed Assets","name_en":"Mixer","name_bn":"মিক্সার","subcategory":"Machines","unit":"pc","control_class":"Asset","note":""},
 {"code":"03-002","cat_no":"03","category":"Raw Materials","name_en":"Sugar","name_bn":"চিনি","subcategory":"Sweet","unit":"kg","control_class":"Raw Material","note":""}]'::jsonb, 'p22-batch') as ap \gset
reset role;
select id as i1 from items where code='I-001' \gset
select id as i2 from items where code='I-002' \gset
select id as i3 from items where code='I-003' \gset
select id as i4 from items where code='I-004' \gset
select id as i5 from items where code='I-005' \gset
select id as d1 from items where code='14-001' \gset
select id as d2 from items where code='14-002' \gset
select id as d3 from items where code='14-003' \gset
select id as d4 from items where code='14-004' \gset
select id as dr from items where code='15-001' \gset
select id as da from items where code='01-001' \gset
select id as dm from items where code='03-002' \gset
select tt.chk('S0 rules, grant, tables, RLS', (select count(*) from rules where key in ('items_hide_unpriced_in_pos','item_map_accept_min_conf'))=2 and rule_on('items_hide_unpriced_in_pos')
  and (select count(*) from grant_defs where grant_code='item_bulk')=1 and (select count(*) from pg_class where relname in ('item_bulk_batches','item_map_actions') and relrowsecurity)=2);
select tt.chk('S0 dictionary items imported unpriced', (select count(*) from items where import_batch='p22-batch')=7 and (select sell_price from items where code='14-001') is null);
\i /home/user/My-tools/supabase/phase22.sql
select tt.chk('S0 phase22 re-runs', (select count(*) from rules where key='items_hide_unpriced_in_pos')=1 and (select count(*) from grant_defs where grant_code='item_bulk')=1);

\echo == B1 access
set role authenticated; select tt.as(:'s');
select tt.err('B1 no right -> refused', $$select items_bulk_apply('[{"code":"14-001","sell_price":100}]'::jsonb, true)$$, 'not allowed');
reset role; set role anon;
select tt.err('B1 anon cannot call', $$select items_bulk_apply('[{"code":"14-001","sell_price":100}]'::jsonb, true)$$, 'permission denied');
reset role; set role authenticated; select tt.as(:'o');
select tt.err('B1 empty list refused', $$select items_bulk_apply('[]'::jsonb, true)$$, 'bad_request');
select tt.err('B1 not an array refused', $$select items_bulk_apply('{"a":1}'::jsonb, true)$$, 'bad_request');
select tt.err('B1 201 rows refused (cap 200)', $$select items_bulk_apply((select jsonb_agg(jsonb_build_object('code','14-001','sell_price',1)) from generate_series(1,201)), true)$$, 'too_many_rows');
select tt.chk('B1 200 rows accepted (dry; duplicates flagged per row)', (select (items_bulk_apply((select jsonb_agg(jsonb_build_object('code','14-001','sell_price',1)) from generate_series(1,200)), true))->>'rows')='200');
select tt.err('B1 apply needs a batch id', $$select items_bulk_apply('[{"code":"14-001","sell_price":100}]'::jsonb, false)$$, 'batch_required');

\echo == B2 dry run writes nothing
select count(*) as nb0 from item_bulk_batches \gset
select count(*) as nh0 from item_price_history \gset
select count(*) as na0 from audit_log \gset
select items_bulk_apply('[{"code":"14-001","sell_price":120,"unit":"kg","tracked":true,"min_stock":5},{"code":"I-001","sell_price":270},{"code":"nope","sell_price":1}]'::jsonb, true) as dry1 \gset
select tt.chk('B2 dry result: 2 would change, 1 error', (:'dry1'::jsonb->>'dry')='true' and (:'dry1'::jsonb->>'ok')='2' and (:'dry1'::jsonb->>'error')='1' and (:'dry1'::jsonb->'results'->0->'changes'->'sell_price'->>1)='120');
select tt.chk('B2 dry run changed nothing: price, batch table, history, audit', (select sell_price from items where code='14-001') is null and (select sell_price from items where code='I-001')=260
  and (select count(*) from item_bulk_batches)=:nb0 and (select count(*) from item_price_history)=:nh0 and (select count(*) from audit_log)=:na0);

\echo == B3 owner apply: direct, audited, idempotent
select items_bulk_apply('[{"code":"14-001","sell_price":120,"wholesale_price":110,"unit":"kg","tracked":true,"min_stock":5},{"code":"14-002","sell_price":"95.5","unit":"Pound"},{"code":"I-001","sell_price":270},
  {"code":"I-002","sell_price":null},{"code":"14-003","sell_price":"abc"},{"code":"nope","sell_price":1}]'::jsonb, false, 'b-1', 'first load') as r1 \gset
select tt.chk('B3 counts: 3 ok, 1 skipped (nochange), 2 errors', (:'r1'::jsonb->>'ok')='3' and (:'r1'::jsonb->>'skipped')='1' and (:'r1'::jsonb->>'error')='2' and (:'r1'::jsonb->>'mode')='direct');
select tt.chk('B3 values written', (select sell_price from items where code='14-001')=120 and (select wholesale_price from items where code='14-001')=110 and (select tracked from items where code='14-001') and (select min_stock from items where code='14-001')=5
  and (select sell_price from items where code='14-002')=95.5 and (select unit from items where code='14-002')='lb' and (select sell_price from items where code='I-001')=270);
select tt.chk('B3 price history kept (old 260 and new 270)', (select count(*) from item_price_history h join items i on i.id=h.item_id where i.code='I-001' and h.sell_price in (260,270))>=2);
select tt.chk('B3 error reasons', (:'r1'::jsonb->'results'->4->>'reason') like 'bad_price%' and (:'r1'::jsonb->'results'->5->>'reason')='item_not_found' and (:'r1'::jsonb->'results'->3->>'reason')='nochange');
select tt.chk('B3 ONE audit batch row with all results', (select count(*) from item_bulk_batches where client_batch='b-1')=1 and (select jsonb_array_length(results) from item_bulk_batches where client_batch='b-1')=6 and (select rows_n from item_bulk_batches where client_batch='b-1')=6);
select tt.chk('B3 idempotent: same batch id returns the saved result, nothing redone', (select items_bulk_apply('[{"code":"14-001","sell_price":999}]'::jsonb, false, 'b-1')->>'already')='true'
  and (select sell_price from items where code='14-001')=120 and (select count(*) from item_bulk_batches where client_batch='b-1')=1);
select tt.err('B3 the batch table is append-only (update)', $$update item_bulk_batches set note='x'$$, 'permission denied');
select tt.err('B3 the batch table is append-only (delete)', $$delete from item_bulk_batches$$, 'permission denied');
reset role; select tt.err('B3 truncate refused for the DB owner too', 'truncate item_bulk_batches', 'append_only'); set role authenticated; select tt.as(:'o');

\echo == B4 price guards
select items_bulk_apply(jsonb_build_array(
  jsonb_build_object('code','14-003','sell_price','NaN'), jsonb_build_object('code','14-004','sell_price','Infinity'), jsonb_build_object('code','15-001','sell_price','-5'),
  jsonb_build_object('code','I-003','sell_price','1e9'), jsonb_build_object('code','I-004','sell_price','1000000001'), jsonb_build_object('code','I-005','sell_price','12,5'),
  jsonb_build_object('code','I-006','wholesale_price','NaN'), jsonb_build_object('code','I-007','min_stock','Infinity')), false, 'b-guard') as r2 \gset
select tt.chk('B4 NaN / Infinity / negative / 1e9 / too big / comma -> all 8 are errors, nothing written', (:'r2'::jsonb->>'error')='8' and (:'r2'::jsonb->>'ok')='0'
  and (select sell_price from items where code='14-003') is null and (select sell_price from items where code='I-003')=350 and (select min_stock from items where code='I-007') is null);
select tt.chk('B4 the 1,000,000,000 edge is allowed', (select items_bulk_apply('[{"code":"14-003","sell_price":1000000000}]'::jsonb, true)->>'ok')='1');
select tt.chk('B4 unknown unit refused', (select items_bulk_apply('[{"code":"14-003","unit":"parsec"}]'::jsonb, true)->'results'->0->>'reason')='bad_unit');
select tt.chk('B4 unknown field refused (category cannot be changed here)', (select items_bulk_apply('[{"code":"14-003","category":"x"}]'::jsonb, true)->'results'->0->>'reason') like 'bad_field%');
select tt.chk('B4 same item twice in one batch: second is an error', (select items_bulk_apply(format('[{"code":"14-003","sell_price":5},{"item_id":"%s","sell_price":6}]', :'d3')::jsonb, true)->'results'->1->>'reason')='duplicate_row');
select tt.chk('B4 tracked needs counting in business (asset item)', (select items_bulk_apply('[{"code":"01-001","tracked":true}]'::jsonb, true)->'results'->0->>'reason')='tracked_needs_count');
select tt.chk('B4 raw material cannot be made sellable', (select items_bulk_apply('[{"code":"03-002","sellable":true}]'::jsonb, true)->'results'->0->>'reason')='type_not_sellable');

\echo == B5 locked items refused, costs untouched
reset role; update items set locked = true where code = 'I-008'; set role authenticated; select tt.as(:'o');
select tt.chk('B5 locked item is skipped even for the owner (dry and real)', (select items_bulk_apply('[{"code":"I-008","sell_price":1}]'::jsonb, true)->'results'->0->>'reason')='locked'
  and (select items_bulk_apply('[{"code":"I-008","sell_price":1}]'::jsonb, false, 'b-lock')->>'skipped')='1' and (select sell_price from items where code='I-008')<>1);
reset role; insert into item_costs (item_id, cost_price) values (:'i1', 111.11) on conflict (item_id) do update set cost_price=111.11; set role authenticated; select tt.as(:'o');
select items_bulk_apply('[{"code":"I-001","sell_price":280}]'::jsonb, false, 'b-nocost') as r3 \gset
select tt.chk('B5 a price batch without cost column leaves costs alone', (select cost_price from item_costs where item_id=:'i1')=111.11);
select items_bulk_apply('[{"code":"I-001","cost_price":120.5}]'::jsonb, false, 'b-cost') as r4 \gset
select tt.chk('B5 owner passes cost explicitly -> cost changes; the saved audit row does not carry the figure', (select cost_price from item_costs where item_id=:'i1')=120.5 and (select results::text from item_bulk_batches where client_batch='b-cost') not like '%120.5%');

\echo == B6 grant holder = direct, no grant = requests, cost refused for non-owner
set role authenticated; select tt.as(:'k');
select items_bulk_apply('[{"code":"14-004","sell_price":70},{"code":"I-009","cost_price":5}]'::jsonb, false, 'k-1') as r5 \gset
select tt.chk('B6 item_bulk holder applies at once; cost is refused for non-owner', (:'r5'::jsonb->>'mode')='direct' and (select sell_price from items where code='14-004')=70 and (:'r5'::jsonb->'results'->1->>'reason')='cost_owner_only');
select tt.chk('B6 holder sees the batch row; salesperson does not', (select count(*) from item_bulk_batches where client_batch='k-1')=1);
select tt.as(:'m');
select tt.chk('B6 batch of someone else is not visible to management', (select count(*) from item_bulk_batches where client_batch='k-1')=0);
select items_bulk_apply('[{"code":"I-010","sell_price":300},{"code":"15-001","sell_price":25,"hidden":true},{"code":"I-011","cost_price":9}]'::jsonb, false, 'm-1', 'price review') as r6 \gset
reset role;
select tt.chk('B6 non-owner without grant: mode requests, 2 requested, cost refused, nothing applied', (:'r6'::jsonb->>'mode')='requests' and (:'r6'::jsonb->>'requested')='2' and (:'r6'::jsonb->>'error')='1'
  and (select sell_price from items where code='I-010')<>300 and (select sell_price from items where code='15-001') is null);
select tt.chk('B6 two pending item_changes with the patch', (select count(*) from item_changes where status='pending' and note='price review')=2 and (select count(*) from item_changes where patch->>'sell_price'='300' and item_id=(select id from items where code='I-010'))=1);
set role authenticated; select tt.as(:'o');
select decide_item_change((select id from item_changes where patch->>'sell_price'='300'), true);
select tt.chk('B6 owner approval applies the requested price', (select sell_price from items where code='I-010')=300);
select decide_item_change((select id from item_changes where patch->>'sell_price'='25'), true);
select tt.chk('B6 approved request with hidden flag applied too', (select hidden from items where code='15-001') and (select sell_price from items where code='15-001')=25);

\echo == B7 bulk hide / inactivate with reason, flags
select items_bulk_apply('[{"code":"14-001","hidden":true},{"code":"14-002","is_active":false,"reason":"duplicate"},{"code":"14-004","is_active":false}]'::jsonb, false, 'b-hide', 'clutter') as r7 \gset
select tt.chk('B7 hidden / inactive set, reasons kept (own reason, else batch note), nothing deleted', (select hidden from items where code='14-001') and not (select is_active from items where code='14-002') and (select retired_reason from items where code='14-002')='duplicate'
  and (select retired_reason from items where code='14-004')='clutter' and (select count(*) from items)>=64);
reset role; insert into stock_balance (item_id, location_id, qty) values (:'i5', 1, 4) on conflict do nothing; set role authenticated; select tt.as(:'o');
select tt.chk('B7 count_in_business off refused while stock exists (dry and real)', (select items_bulk_apply('[{"code":"I-005","count_in_business":false}]'::jsonb, true)->'results'->0->>'reason')='item_has_stock'
  and (select items_bulk_apply('[{"code":"I-005","count_in_business":false}]'::jsonb, false, 'b-stock')->>'error')='1' and (select count_in_business from items where code='I-005'));
select items_bulk_apply('[{"code":"14-001","hidden":false},{"code":"14-002","is_active":true}]'::jsonb, false, 'b-unhide') as r8 \gset
select tt.chk('B7 reversible: unhide and reactivate', not (select hidden from items where code='14-001') and (select is_active from items where code='14-002') and (select retired_at from items where code='14-002') is null);

\echo == M1 mapping decisions
reset role;
insert into item_mapping_review (item_id, suggested_code, confidence, auto_ok) values (:'i1','14-001',0.95,true), (:'i2','14-002',0.60,false), (:'i3','14-003',0.90,false), (:'i4','15-001',0.40,false) on conflict (item_id) do nothing;
update items set sell_price = 260, unit='kg' where code='I-001';
set role authenticated; select tt.as(:'m');
select tt.err('M1 management without item_create cannot decide', format($$select item_map_decide2(%L,'keep')$$, :'i4'), 'not allowed');
select tt.as(:'o');
select tt.chk('M1 dry accept-all: only auto (rule empty)', (select item_map_accept_confident(true)->>'accepted')='1' and (select status from item_mapping_review where item_id=:'i1')='pending');
select set_rule('item_map_accept_min_conf', '0.85'::jsonb);
select tt.chk('M1 dry accept-all with rule 0.85: 2 (auto + 0.90), writes nothing', (select item_map_accept_confident(true)->>'accepted')='2' and (select count(*) from item_master_links)=0);
select item_map_accept_confident(false) as acc \gset
select tt.chk('M1 accept-all result: 2 linked', (:'acc'::jsonb->>'accepted')='2');
select tt.chk('M1 accept-all: review rows linked, master code on the old item, twin hidden', (select status from item_mapping_review where item_id=:'i1')='linked' and (select hidden from items where code='14-001') and (select master_code from items where code='I-001')='14-001');
select tt.chk('M1 accept-all is logged per row', (select count(*) from item_map_actions where action='accept_all')=2);
select tt.chk('M1 accept-all rerun is a no-op', (select item_map_accept_confident(false)->>'accepted')='0');
select item_map_decide2(:'i1','undo') as u1 \gset
select tt.chk('M1 undo a link (reversible)', (:'u1'::jsonb->>'status')='pending' and not (select hidden from items where code='14-001') and (select master_code from items where code='I-001') is null);
select item_map_decide2(:'i1','link','14-001') as u2 \gset
select tt.chk('M1 link by hand', (:'u2'::jsonb->>'status')='linked' and (select hidden from items where code='14-001'));
select item_map_decide2(:'i4','keep') as u3 \gset
select tt.chk('M1 keep separate', (:'u3'::jsonb->>'status')='rejected' and (select status from item_mapping_review where item_id=:'i4')='rejected');
select item_map_decide2(:'i4','later') as u3b \gset
select tt.chk('M1 decide later', (:'u3b'::jsonb->>'status')='later' and (select status from item_mapping_review where item_id=:'i4')='later');
select item_map_decide2(:'i3','later') as u4 \gset
select tt.chk('M1 later on a linked item unlinks it first', (:'u4'::jsonb->>'status')='later' and (select master_code from items where code='I-003') is null and not (select hidden from items where code='14-003'));

\echo == M2 use dictionary item instead
reset role; update items set wholesale_price = 240 where code = 'I-002'; set role authenticated; select tt.as(:'o');
reset role; update items set barcode='BC-I2' where code='I-002'; insert into user_grants (user_id, grant_code) values (:'k','item_create'); set role authenticated; select tt.as(:'o');
select tt.err('M2 audit1: dictionary price differs -> needs the owner confirmation (force)', format($$select item_map_decide2(%L,'use_dict','14-002')$$, :'i2'), 'dict_price_differs');
reset role; insert into stock_balance (item_id, location_id, qty) values (:'d2', 1, 3); set role authenticated; select tt.as(:'o');
select tt.err('M2 audit1: dictionary has stock and another unit -> refused even with force', format($$select item_map_decide2(%L,'use_dict','14-002',null,true)$$, :'i2'), 'dict_unit_has_stock');
reset role; alter table stock_balance disable trigger stock_balance_guard84; delete from stock_balance where item_id=:'d2'; alter table stock_balance enable trigger stock_balance_guard84; update items set unit='kg', sell_price=null where code='14-002'; insert into stock_balance (item_id, location_id, qty) values (:'d2', 1, 3); set role authenticated; select tt.as(:'o');
select tt.err('M2 audit1: dictionary has stock (same unit) -> needs confirmation', format($$select item_map_decide2(%L,'use_dict','14-002')$$, :'i2'), 'dict_has_stock');
reset role; alter table stock_balance disable trigger stock_balance_guard84; delete from stock_balance where item_id=:'d2'; alter table stock_balance enable trigger stock_balance_guard84; update items set unit='lb', sell_price=95.5 where code='14-002'; set role authenticated; select tt.as(:'o');
select item_map_decide2(:'i2','use_dict','14-002','looks the same',true) as u5 \gset
select tt.chk('M2 use_dict: copies price/unit to dictionary item, retires the old one', (:'u5'::jsonb->>'status')='replaced'
  and (select sell_price from items where code='14-002')=(select sell_price from items where code='I-002') and (select unit from items where code='14-002')=(select unit from items where code='I-002')
  and (select wholesale_price from items where code='14-002')=240 and not (select hidden from items where code='14-002') and (select sellable from items where code='14-002') and (select is_active from items where code='14-002')
  and not (select is_active from items where code='I-002') and (select retired_reason from items where code='I-002')='replaced by 14-002' and (select retired_at from items where code='I-002') is not null);
select tt.chk('M2 audit1: barcode moved to the dictionary item, legacy cleared', (select barcode from items where code='14-002')='BC-I2' and (select barcode from items where code='I-002') is null and (:'u5'::jsonb->>'barcode_moved')='true');
select tt.as(:'k');
select tt.err('M2 audit3: undo of a replacement is the owner only', format($$select item_map_decide2(%L,'undo')$$, :'i2'), 'not allowed');
select tt.as(:'o');
select tt.err('M2 audit4: link refused while replaced', format($$select item_map_decide2(%L,'link','14-004')$$, :'i2'), 'undo_first');
select tt.chk('M2 audit6: bulk edit of a replaced item (either side) is skipped', (select items_bulk_apply('[{"code":"I-002","sell_price":5},{"code":"14-002","sell_price":6}]'::jsonb, true)->>'skipped')='2');
select tt.chk('M2 old code and price history are kept, review marked replaced, action logged', (select sell_price from items where code='I-002') is not null and (select count(*) from item_price_history h where h.item_id=:'i2')>=1
  and (select status from item_mapping_review where item_id=:'i2')='replaced' and (select count(*) from item_map_actions where action='use_dict' and item_id=:'i2')=1);
select tt.err('M2 second use of the same dictionary item refused', format($$select item_map_decide2(%L,'use_dict','14-002')$$, :'i3'), 'master_code_taken');
select tt.err('M2 an already replaced item cannot be decided again', format($$select item_map_decide2(%L,'keep')$$, :'i2'), 'undo_first');
select tt.err('M2 asset dictionary item refused', format($$select item_map_decide2(%L,'use_dict','01-001')$$, :'i3'), 'master_type_mismatch');
select tt.err('M2 unknown dictionary code refused', format($$select item_map_decide2(%L,'use_dict','99-999')$$, :'i3'), 'master_code_not_found');
select tt.err('M2 old item with a link must be unlinked first', format($$select item_map_decide2(%L,'use_dict','14-004')$$, :'i1'), 'unlink_first');
reset role; update items set sell_price = 301 where code = '14-002'; set role authenticated; select tt.as(:'o');
select tt.err('M2 undo refused when the dictionary price changed since', format($$select item_map_decide2(%L,'undo')$$, :'i2'), 'changed_since');
reset role; update items set sell_price = (select sell_price from items where code='I-002') where code = '14-002'; set role authenticated; select tt.as(:'o');
select item_map_decide2(:'i2','undo') as u6 \gset
select tt.chk('M2 audit1: undo moves the barcode back', (select barcode from items where code='I-002')='BC-I2' and (select barcode from items where code='14-002') is null);
select tt.chk('M2 undo restores both items', (:'u6'::jsonb->>'status')='pending' and (select sell_price from items where code='14-002')=95.5 and (select unit from items where code='14-002')='lb' and (select wholesale_price from items where code='14-002') is null and (select is_active from items where code='I-002')
  and (select retired_at from items where code='I-002') is null and (select status from item_mapping_review where item_id=:'i2')='pending' and (select count(*) from item_map_actions where action='undo_use_dict')=1);
select item_map_decide2(:'i2','use_dict','14-002',null,true) as u7 \gset
select tt.chk('M2 use_dict again after undo works', (:'u7'::jsonb->>'status')='replaced');
select tt.err('M2 action table is append-only (update)', $$update item_map_actions set note='x'$$, 'permission denied');

\echo == A5 audit fixes: bulk inactive guards, price 0, late offline sale
select tt.chk('A5 sell_price 0 refused in bulk', (select items_bulk_apply('[{"code":"14-003","sell_price":0},{"code":"14-003","sell_price":"0.00"}]'::jsonb, true)->>'error')::int>=1 and (select items_bulk_apply('[{"code":"14-003","sell_price":0}]'::jsonb, true)->'results'->0->>'reason') like 'bad_price%');
reset role; insert into item_master_links (item_id, dict_code, via) values (:'i3','14-003','test'); set role authenticated; select tt.as(:'o');
select tt.chk('A5 inactive refused: item has stock', (select items_bulk_apply('[{"code":"I-005","is_active":false}]'::jsonb, true)->'results'->0->>'reason')='item_has_stock');
select tt.chk('A5 inactive refused: active master link (either side)', (select items_bulk_apply('[{"code":"I-003","is_active":false},{"code":"14-003","is_active":false}]'::jsonb, true)->>'error')='2');
reset role; update item_master_links set active=false where item_id=:'i3'; set role authenticated; select tt.as(:'o');
select tt.chk('A5 inactive allowed when no stock and no link', (select items_bulk_apply('[{"code":"14-003","is_active":false,"reason":"x"}]'::jsonb, true)->>'ok')='1');
-- late offline sale of an item retired after the sale
reset role; update items set sell_price=40, sellable=true, is_active=true where code='14-004'; set role authenticated; select tt.as(:'o');
select items_bulk_apply('[{"code":"14-004","is_active":false,"reason":"r"}]'::jsonb, false, 'a5-off2') as ina \gset
select tt.chk('A5 item now inactive', not (select is_active from items where code='14-004'));
select tt.err('A5 online sale of the inactive item refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":40,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":40}]',null,null,'retail',null,false)$$, :'d4'), 'item_not_found');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":40,"unit":"kg"}]', :'d4')::jsonb,0,'[{"mode":"cash","amount":40}]',null,null,'retail',null,false, now() - interval '1 hour') as ls \gset
select tt.chk('A5 late offline sale of the retired item goes through', (:'ls'::jsonb->>'receipt') is not null);
select tt.chk('A5 ... and raises the red exception offline_sale_item_changed', (select count(*) from exceptions where flag_code='offline_sale_item_changed' and level='red')>=1);

\echo == F1 grants
reset role;
select tt.chk('F1 anon / public cannot run the new functions', not has_function_privilege('anon','public.item_map_decide2(uuid,text,text,text,boolean)','execute') and not has_function_privilege('anon','public.items_bulk_apply(jsonb,boolean,text,text)','execute')
  and not has_function_privilege('anon','public.item_map_accept_confident(boolean)','execute') and not has_function_privilege('anon','public._bulk_num(jsonb,text)','execute'));
select tt.chk('F1 no direct write on the new tables', not has_table_privilege('authenticated','public.item_bulk_batches','insert') and not has_table_privilege('authenticated','public.item_map_actions','insert'));

select '--- FAILED: ' || count(*) filter (where not ok) || ' of ' || count(*) from tt.res;
select name from tt.res where not ok;
