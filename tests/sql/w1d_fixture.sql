-- W1-D fixture (phases 92 and 93): the records an existing install has, PLUS one example of every loss the management profit leaves out. Test data only (test_* names).
-- Used by supabase/phase92_test.sql, supabase/phase93_test.sql and tests/sql/w1d_before_after.sh. Needs a database built through phase87 (phase92 may or may not be pasted).
-- Hand-computed numbers (place 1, today unless said otherwise):
--   sale: 4 finished goods x 100 = 400 cash. Finished goods come from one production run: 5 kg raw @ 20 = 100 material + 40 conversion (labour per batch) = 140 for 10 units = 14 each,
--         so the cost of goods sold is 4 x 14 = 56 (of which 16 is overhead) and 40 of overhead sits in the cost of the run.
--   wastage 3 x 10 = 30   |  count shortage (50 booked, 47 counted) 3 x 40 = 120  |  transit: 10 sent, 8 received, 2 x 25 = 50 written off
--   cash short: -20 today, +5 the same day, both approved = a net loss of 15  |  supplier bill: 2 consumables x 150 = 300 (running cost) + 5 raw x 20 = 100 (stock) = 400
--   expenses: one approved 10-2 voucher 500 (transport) + one quick expense 300 (transport)
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-000000000092'
\set acc '00000000-0000-0000-0000-000000000192'
\set st '00000000-0000-0000-0000-000000000292'
create schema if not exists tt;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner_w1d@s.app','{"full_name":"test_owner"}'), (:'acc','test_acct_w1d@s.app','{"full_name":"test_acct"}'), (:'st','test_staff_w1d@s.app','{"full_name":"test_staff"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'acc','management'),(:'st','salesperson') on conflict do nothing;
insert into user_locations values (:'acc',1),(:'acc',2),(:'st',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'acc','accounts_manage',null),(:'acc','accounts_view',null) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset
select acct_set_start(:'pm'::date) is not null as w_s1 \gset
select set_rule('accounting_on','true') is null as w_s2 \gset
select acct_journal_post(:'pm'::date, 1, 'test opening', '[{"code":"1110","debit":900000},{"code":"3100","credit":900000}]'::jsonb) is not null as w_s3 \gset
insert into suppliers (name) values ('test_supplier_w1d');
select id as w_sup from suppliers where name = 'test_supplier_w1d' \gset
insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values
 ('W1D-RM','test_raw','test_raw','kg','kg',0,true,'raw_material'), ('W1D-FG','test_fin','test_fin','piece','piece',100,true,'finished_good'),
 ('W1D-CS','test_consumable','test_consumable','piece','piece',0,false,'consumable'), ('W1D-WS','test_waste','test_waste','kg','kg',0,true,'raw_material'),
 ('W1D-CT','test_count','test_count','kg','kg',0,true,'raw_material'), ('W1D-TR','test_transit','test_transit','kg','kg',0,true,'raw_material');
select id as i_rm from items where code='W1D-RM' \gset
select id as i_fg from items where code='W1D-FG' \gset
select id as i_cs from items where code='W1D-CS' \gset
select id as i_ws from items where code='W1D-WS' \gset
select id as i_ct from items where code='W1D-CT' \gset
select id as i_tr from items where code='W1D-TR' \gset
-- stock openings (cost 20 / 10 / 40 / 25)
select stock_opening(:'i_rm'::uuid,1,200,20) is not null as w_o1 \gset
select stock_opening(:'i_ws'::uuid,1,100,10) is not null as w_o2 \gset
select stock_opening(:'i_ct'::uuid,1,50,40) is not null as w_o3 \gset
select stock_opening(:'i_tr'::uuid,1,40,25) is not null as w_o4 \gset
-- production with conversion costing: 5 raw -> 10 finished, labour 40 per batch
select (recipe_save(null, :'i_fg'::uuid, 10, null, 'w1d v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'i_rm','qty',5,'waste_pct',0)))->>'id')::uuid as w_rc \gset
select loc_cost_cfg_set(1,'recipe') is null as w_c1 \gset
select recipe_cost_component_set(:'w_rc'::uuid, 'labour', 'per_batch', 40, null, null, 'w1d', gen_random_uuid()) ->> 'id' as w_cc \gset
select production_post(1, :'w_rc'::uuid, 1, gen_random_uuid())->>'run_id' as w_run \gset
-- the sale
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":4,"price":100}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":400}]',null,null,'retail',null,false)->>'id' as w_sale \gset
-- wastage, count shortage, transit loss
select stock_wastage(:'i_ws'::uuid,1,3,'spoiled','test') ->> 'id' as w_waste \gset
select stock_count_adjust(:'i_ct'::uuid,1,47,'test count') ->> 'ledger_id' as w_cnt \gset
select (stock_transfer(1,2,:'i_tr'::uuid,10)->>'id') as w_tr \gset
select stock_receive_transfer(:'w_tr'::uuid,8) is not null as w_r1 \gset
select id as w_sh from shortage_transit where transfer_id = :'w_tr'::uuid \gset
select transit_short_writeoff(:'w_sh'::uuid,'lost on the road') is not null as w_wo \gset
-- cash short -20 today and over +5 the same day (both approved)
insert into entries (form_code,location_id,serial,entry_date,status,created_by,created_staff) values ('14-1',1,92001,tt.today(),'submitted',:'o','t'), ('14-1',1,92002,tt.today(),'submitted',:'o','t');
select id as w_e1 from entries where serial=92001 and form_code='14-1' \gset
select id as w_e2 from entries where serial=92002 and form_code='14-1' \gset
insert into exceptions (entry_id,form_code,location_id,entry_date,flag_code,level,amount,text) values (:'w_e1','14-1',1,tt.today(),'cash_short_over','red',-20,'{}'), (:'w_e2','14-1',1,tt.today(),'cash_short_over','yellow',5,'{}');
select id as w_cs1 from shortage_cash_cases where entry_id=:'w_e1' \gset
select id as w_cs2 from shortage_cash_cases where entry_id=:'w_e2' \gset
select cash_short_decide(:'w_cs1'::uuid,true,'checked the slip') is not null as w_d1 \gset
select cash_short_decide(:'w_cs2'::uuid,true,'cash box had extra') is not null as w_d2 \gset
-- supplier bill: 2 consumables @ 150 + 5 raw @ 20
select save_purchase(gen_random_uuid(), null, :'w_sup'::uuid, 1, 'W1D-B1', tt.today(), format('[{"item_id":"%s","qty":2,"unit_cost":150},{"item_id":"%s","qty":5,"unit_cost":20}]',:'i_cs',:'i_rm')::jsonb, 0)->>'id' as w_bill \gset
select post_purchase(:'w_bill'::uuid) is not null as w_pb \gset
-- expenses: an approved 10-2 voucher (500) and a quick expense (300)
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","amount":"500"}]}'::jsonb,'[]') ->> 'id' as w_v1 \gset
select submit_entry(:'w_v1'::uuid) is not null as w_se \gset
select decide_entry(:'w_v1'::uuid,true,null,'{}','[]') ->> 'status' as w_de \gset
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 300, 'cash', false, 'test note', gen_random_uuid()) is not null as w_qe \gset
select acct_post_pending(false) ->> 'posted' as w_posted \gset
select :'w_posted' as posted;
