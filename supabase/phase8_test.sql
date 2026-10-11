-- Phase 8 tests. Run on a fresh db built with: schema, phase2, (storage mock), phase3, phase4, ALL_NEW, phase8 (twice).
-- Needs the auth mock (auth.uid() reads request.jwt.claim.sub). Prints PASS / FAIL per check; a FAIL count is printed at the end.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
-- run a statement as the current role; PASS when it raises an error containing p_msg ('' = any error)
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false);
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); end $$;
create or replace function tt.cnt(p_sql text) returns bigint language plpgsql as $$ declare n bigint; begin execute 'select count(*) from (' || p_sql || ') x' into n; return n; end $$;
grant usage on schema tt to authenticated; grant execute on all functions in schema tt to authenticated; grant select, insert on tt.res to authenticated;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}') on conflict do nothing;
insert into auth.users (id,email,raw_user_meta_data) values (:'s','staff2@s.app','{"full_name":"Sales"}') on conflict do nothing;
insert into auth.users (id,email,raw_user_meta_data) values (:'k','store3@s.app','{"full_name":"Store"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson') on conflict do nothing;
insert into user_roles values (:'k','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1), (:'k',1) on conflict do nothing;

\echo == T0 re-run safety: phase8 applied twice earlier; rules keys unique
select tt.chk('T0 phase8 rule keys present', (select count(*) from rules where key in ('vat_on','vat_rate','stock_negative_mode','discount_mode_percent_on','fiscal_year_start_month')) = 5);
select tt.chk('T0 defaults: vat_on false, stock_negative warn, costing avg, noperm lock', rule_val('vat_on')='false'::jsonb and rule_txt('stock_negative_mode')='warn' and rule_txt('costing_method')='avg' and rule_txt('ui_noperm_mode')='lock');
select tt.chk('T0 no invented numbers: vat_rate / fiscal / week_start null', rule_val('vat_rate') is null and rule_val('fiscal_year_start_month') is null and rule_val('week_start') is null);

\echo == T1 staff cannot edit templates / rules / conversions / shelf rules / user grants
set role authenticated; select set_config('request.jwt.claim.sub',:'s',false);
select tt.err('T1 staff insert invoice template', $$insert into invoice_templates (name,kind) values ('x','a4')$$, 'row-level security');
select tt.err('T1 staff insert print profile', $$insert into print_profiles (name,printer_type) values ('x','a4')$$, 'row-level security');
select tt.err('T1 staff set_rule', $$select set_rule('vat_on','true')$$, 'not allowed');
select tt.err('T1 staff direct update rules', $$update rules set value='true' where key='vat_on'$$, 'permission denied');
select tt.err('T1 staff set_unit_conversion', $$select set_unit_conversion(null,'box','piece',12)$$, 'not allowed');
select tt.err('T1 staff insert unit_conversions', $$insert into unit_conversions (from_unit,to_unit,factor) values ('a','b',2)$$, 'row-level security');
select tt.err('T1 staff insert shelf rule', $$insert into shelf_life_rules (value,unit) values (1,'days')$$, 'row-level security');
select tt.err('T1 staff insert user_grants', $$insert into user_grants (user_id,grant_code) values (auth.uid(),'view_cost')$$, 'permission denied');
select tt.err('T1 staff set_user_grant', $$select set_user_grant(auth.uid(),'view_cost')$$, 'not allowed');
select tt.err('T1 staff save_supplier', $$select save_supplier(null,'{"name":"A"}')$$, 'not allowed');
select tt.chk('T1 staff cannot read supplier master', (select count(*) from suppliers) = 0);
select tt.chk('T1 staff cannot read cost table', (select count(*) from item_costs) = 0);
select tt.err('T1 staff set_grant', $$select set_grant('view_cost','salesperson',true)$$, 'not allowed');

\echo == T2 owner edits; staff reads
reset role; set role authenticated; select set_config('request.jwt.claim.sub',:'o',false);
insert into invoice_templates (name,kind,header,footer,show_flags,vat_line_on,paper_width_mm,margins,font_scale,is_default)
  values ('Shop 80','thermal80','{"bn":"ইসলামিয়া","en":"Islamia"}','{"en":"Thanks"}','{"logo":true,"customer":false}',false,80,'{"top":2,"left":2}',1.1,true);
insert into print_profiles (name,location_id,device_key,printer_type,paper_size,paper_width_mm,template_id) select 'Counter 1',1,'dev-a','thermal','80mm',80,id from invoice_templates limit 1;
select tt.chk('T2 owner created template + profile', (select count(*) from invoice_templates)=1 and (select count(*) from print_profiles)=1);
select tt.err('T2 second default of same kind/location refused', $$insert into invoice_templates (name,kind,is_default) values ('dup','thermal80',true)$$, 'duplicate');
select tt.err('T2 bad kind refused', $$insert into invoice_templates (name,kind) values ('z','pdf')$$, 'check');
select set_rule('vat_on','true');
select tt.err('T2 vat_rate over 100 refused', $$select set_rule('vat_rate','150')$$, 'bad_value');
select tt.err('T2 stock_negative_mode bad choice refused', $$select set_rule('stock_negative_mode','"maybe"')$$, 'bad_value');
select tt.err('T2 fiscal month 13 refused', $$select set_rule('fiscal_year_start_month','13')$$, 'bad_value');
select set_rule('vat_on',null);
select tt.chk('T2 vat_on back to default false', not rule_on('vat_on'));
select set_rule('stock_negative_mode','"block"');
select tt.chk('T2 stock_negative_mode set to block', rule_txt('stock_negative_mode')='block');
select set_rule('stock_negative_mode',null);
select set_rule('week_start','"sun"'); select tt.chk('T2 week start sun: 2026-10-11 is a Sunday -> itself', week_start_date('2026-10-11')='2026-10-11');
select set_rule('week_start',null); select tt.chk('T2 week start default sat: 2026-10-11 -> 2026-10-10', week_start_date('2026-10-11')='2026-10-10');
select tt.chk('T2 fiscal default = calendar year', fiscal_year_start('2026-10-11')='2026-01-01' and fiscal_year_end('2026-10-11')='2026-12-31');
select set_rule('fiscal_year_start_month','7'); select set_rule('fiscal_year_start_day','1');
select tt.chk('T2 fiscal Jul 1: Oct 2026 -> 2026-07-01..2027-06-30', fiscal_year_start('2026-10-11')='2026-07-01' and fiscal_year_end('2026-10-11')='2027-06-30');
select tt.chk('T2 fiscal Jul 1: Mar 2026 -> 2025-07-01', fiscal_year_start('2026-03-01')='2025-07-01');
select set_rule('fiscal_year_start_month',null); select set_rule('fiscal_year_start_day',null);
set role authenticated; select set_config('request.jwt.claim.sub',:'s',false);
select tt.chk('T2 staff reads template', (select count(*) from invoice_templates)=1);
update invoice_templates set name='hack';
select tt.chk('T2 staff update changed nothing', (select name from invoice_templates limit 1)='Shop 80');
select tt.err('T2 staff delete invoice_templates denied', $$delete from invoice_templates$$, 'permission denied');
select tt.chk('T2 template still there', (select count(*) from invoice_templates)=1);
select tt.chk('T2 template_for picks default', (select (template_for('thermal80',1)).name)='Shop 80');

\echo == T3 grants: personal, role, expiry, location, emergency window, report visibility
select set_config('request.jwt.claim.sub',:'k',false);
select tt.chk('T3 storekeeper: no report access', not biz_ok() and not biz_cost_ok() and not has_grant('view_reports'));
select tt.err('T3 biz_daily refused', $$select * from biz_daily('2026-10-01','2026-10-11')$$, 'not allowed');
select set_config('request.jwt.claim.sub',:'o',false);
select set_user_grant(:'k','view_reports');
select set_config('request.jwt.claim.sub',:'k',false);
select tt.chk('T3 personal view_reports -> biz_ok true, cost still false', biz_ok() and not biz_cost_ok());
select tt.chk('T3 biz_daily now runs (cost columns hidden)', (select count(*) from biz_daily('2026-10-01','2026-10-11')) >= 0 and (select count(*) from biz_daily('2026-10-01','2026-10-11') where cogs is not null) = 0);
select set_config('request.jwt.claim.sub',:'o',false);
select set_user_grant(:'k','view_cost');
select set_config('request.jwt.claim.sub',:'k',false);
select tt.chk('T3 personal view_cost -> biz_cost_ok true', biz_cost_ok());
select tt.chk('T3 view_cost does NOT open the item_costs table', (select count(*) from item_costs)=0);
select set_config('request.jwt.claim.sub',:'o',false);
select set_user_grant(:'k','view_cost',null,null,false); select set_user_grant(:'k','view_reports',null,null,false);
select set_config('request.jwt.claim.sub',:'k',false);
select tt.chk('T3 removed grants -> closed again', not biz_ok() and not biz_cost_ok());
select set_config('request.jwt.claim.sub',:'o',false);
select set_user_grant(:'k','export_data',null,now() - interval '1 minute');
select set_config('request.jwt.claim.sub',:'k',false);
select tt.chk('T3 expired personal grant does not count', not has_grant('export_data'));
select set_config('request.jwt.claim.sub',:'o',false);
select set_user_grant(:'k','salary_view',2);
select set_config('request.jwt.claim.sub',:'k',false);
select tt.chk('T3 location-limited grant: yes at loc 2, no at loc 1, no when location not given', has_grant('salary_view',2) and not has_grant('salary_view',1) and not has_grant('salary_view'));
-- role grant
select set_config('request.jwt.claim.sub',:'o',false);
select set_grant('settings_invoice','storekeeper',true);
select set_config('request.jwt.claim.sub',:'k',false);
insert into invoice_templates (name,kind) values ('By store','a4');
select tt.chk('T3 role grant settings_invoice lets storekeeper edit templates', (select count(*) from invoice_templates)=2);
select set_config('request.jwt.claim.sub',:'o',false);
select set_grant('settings_invoice','storekeeper',false);
select set_config('request.jwt.claim.sub',:'k',false);
select tt.err('T3 role grant removed -> refused again', $$insert into invoice_templates (name,kind) values ('again','a4')$$, 'row-level security');
-- supplier_manage
select set_config('request.jwt.claim.sub',:'o',false);
select save_supplier(null,'{"name":"Rahim Dairy","mobile":"01711-000000","type_code":"milk","credit_days":7}') as sup \gset
select tt.chk('T3 owner saved supplier', (select count(*) from suppliers where name='Rahim Dairy' and mobile='01711000000')=1);
select tt.err('T3 negative credit days refused', format($$select save_supplier(%L,'{"credit_days":-1}')$$, :'sup'), 'check');
select set_user_grant(:'k','supplier_manage');
select set_config('request.jwt.claim.sub',:'k',false);
select tt.chk('T3 granted person reads + edits supplier', (select count(*) from suppliers)=1 and save_supplier(:'sup','{"note":"hi"}') is not null);
select set_config('request.jwt.claim.sub',:'s',false);
select tt.chk('T3 supplier_pick shows name only to a plain staff', (select count(*) from supplier_pick())=1);
-- emergency window
select set_config('request.jwt.claim.sub',:'k',false);
select tt.err('T3 emergency for view_cost is off by default', $$select request_emergency('view_cost',1,'{}','need to check a price')$$, 'emergency_off');
select set_config('request.jwt.claim.sub',:'o',false);
select set_rule('em_view_cost','true');
select set_config('request.jwt.claim.sub',:'k',false);
select request_emergency('view_cost',1,'{}','need to check a price') as er \gset
select tt.chk('T3 pending request grants nothing', not biz_cost_ok());
select set_config('request.jwt.claim.sub',:'o',false);
select decide_emergency(:er,true,null);
select set_config('request.jwt.claim.sub',:'k',false);
select tt.chk('T3 approved emergency window opens cost figures', biz_cost_ok());
select set_config('request.jwt.claim.sub',:'o',false);
reset role; update emergency_requests set valid_until = now() - interval '1 minute' where id=:er; set role authenticated; select set_config('request.jwt.claim.sub',:'k',false);
select tt.chk('T3 expired window closes again', not biz_cost_ok());
select set_config('request.jwt.claim.sub',:'o',false); select set_rule('em_view_cost',null);

\echo == T4 shelf life
reset role; select id as i1 from items where code='I-001' \gset
select id as i2 from items where code='I-002' \gset
select id as ix from items where category='doi' limit 1 \gset
set role authenticated; select set_config('request.jwt.claim.sub',:'o',false);
select tt.chk('T4 no rules -> null (feature off)', shelf_life_for(:'i1') is null and shelf_life_hours(:'ix','2026-07-01') is null);
insert into shelf_life_rules (category,value,unit) values ('sweet_kg',24,'hours');
insert into shelf_life_rules (category,season_label,start_month,start_day,end_month,end_day,value,unit) values ('sweet_kg','winter',12,1,2,28,72,'hours');
insert into shelf_life_rules (item_id,value,unit) values (:'i1',2,'days');
insert into shelf_life_rules (item_id,season_label,start_month,start_day,end_month,end_day,value,unit) values (:'i1','long winter',11,15,2,10,5,'days');
insert into shelf_life_rules (item_id,season_label,start_month,start_day,end_month,end_day,value,unit) values (:'i1','deep winter',1,1,1,31,7,'days');
select tt.chk('T4 category fallback (item I-002, July) = 24h', shelf_life_hours(:'i2','2026-07-01')=24);
select tt.chk('T4 category season (I-002, Dec 20) = 72h', shelf_life_hours(:'i2','2026-12-20')=72);
select tt.chk('T4 category season wraps year end (I-002, Feb 28) = 72h; Mar 1 = 24h', shelf_life_hours(:'i2','2027-02-28')=72 and shelf_life_hours(:'i2','2027-03-01')=24);
select tt.chk('T4 item rule beats category (I-001, July) = 48h', shelf_life_hours(:'i1','2026-07-01')=48);
select tt.chk('T4 item season wrap: Nov 14=48h, Nov 15=120h, Dec 30=120h', shelf_life_hours(:'i1','2026-11-14')=48 and shelf_life_hours(:'i1','2026-11-15')=120 and shelf_life_hours(:'i1','2026-12-30')=120);
select tt.chk('T4 item season: Feb 10=120h, Feb 11=48h', shelf_life_hours(:'i1','2027-02-10')=120 and shelf_life_hours(:'i1','2027-02-11')=48);
select tt.chk('T4 overlap: narrower range wins (Jan 5 = deep winter 7 days = 168h)', shelf_life_hours(:'i1','2027-01-05')=168);
select tt.chk('T4 returns scope and rule id', shelf_life_for(:'i1','2027-01-05')->>'scope'='item' and shelf_life_for(:'i2','2026-07-01')->>'scope'='category');
select tt.chk('T4 other category still null', shelf_life_for(:'ix') is null);
update shelf_life_rules set active=false where item_id=:'i1' and season_label='deep winter';
select tt.chk('T4 inactive rule ignored (Jan 5 = 120h)', shelf_life_hours(:'i1','2027-01-05')=120);
insert into shelf_life_rules (value,unit) values (10,'days');
select tt.chk('T4 global rule applies to otherwise-null item = 240h; item rules still win', shelf_life_hours(:'ix','2026-07-01')=240 and shelf_life_hours(:'i1','2026-07-01')=48);
select tt.err('T4 half-set season refused', $$insert into shelf_life_rules (value,unit,start_month,start_day) values (1,'days',1,1)$$, 'check');
select tt.err('T4 item and category together refused', format($$insert into shelf_life_rules (item_id,category,value,unit) values (%L,'doi',1,'days')$$, :'i1'), 'check');
select set_config('request.jwt.claim.sub',:'s',false);
select tt.chk('T4 staff can read the resolution', shelf_life_hours(:'i2','2026-07-01')=24);

\echo == T5 unit conversion (+ item patch with new columns)
select set_config('request.jwt.claim.sub',:'o',false);
select set_unit_conversion(null,'box','piece',12,'global');
select set_unit_conversion(:'i1','kg','piece',20,'one kg = 20 pieces of this sweet');
select tt.chk('T5 item rule: 2 kg = 40 pieces', convert_qty(:'i1',2,'kg','piece')=40);
select tt.chk('T5 inverse: 10 pieces = 0.5 kg', convert_qty(:'i1',10,'piece','kg')=0.5);
select tt.chk('T5 global rule on another item: 3 box = 36 piece', convert_qty(:'i2',3,'box','piece')=36);
select tt.chk('T5 same unit = same qty, unknown pair = null', convert_qty(:'i2',3,'kg','kg')=3 and convert_qty(:'i2',3,'kg','piece') is null);
select submit_item_change(:'i1', '{"base_unit":"piece","sell_units":["kg","piece","box"],"wholesale_price":240,"tracked":true,"min_stock":5,"barcode":"8901234","source":"made","vat_applicable":null,"sub_category":"syrup"}'::jsonb);
select tt.chk('T5 patch wrote the new item columns', (select base_unit='piece' and sell_units=array['kg','piece','box'] and wholesale_price=240 and tracked and min_stock=5 and barcode='8901234' and source='made' and vat_applicable is null and sub_category='syrup' from items where id=:'i1'));
select tt.chk('T5 via base unit: 1 box -> kg uses box=12 piece and kg=20 piece = 0.6', convert_qty(:'i1',1,'box','kg')=0.6);
select tt.err('T5 zero factor refused', $$select set_unit_conversion(null,'a','b',0)$$, 'bad_factor');
select tt.err('T5 duplicate barcode refused', format($$select submit_item_change(%L,'{"barcode":"8901234"}')$$, :'i2'), 'duplicate');
select tt.err('T5 bad source refused', format($$select submit_item_change(%L,'{"source":"stolen"}')$$, :'i2'), 'check');
select submit_item_change(:'i1','{"name_bn":"X"}'::jsonb) is not null;
select tt.chk('T5 old-style patch leaves new columns alone', (select wholesale_price=240 and tracked from items where id=:'i1'));
select set_unit_conversion(null,'box','piece',null);
select tt.chk('T5 rule removed', convert_qty(:'i2',3,'box','piece') is null);
select tt.chk('T5 items table has no cost column', not exists (select 1 from information_schema.columns where table_name='items' and column_name like '%cost%'));

\echo == T6 discount by amount or percent; old calls still work
reset role; insert into location_settings (location_id,key,value) values (1,'discount_limit','100') on conflict (location_id,key) do update set value='100';
set role authenticated; select set_config('request.jwt.claim.sub',:'s',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true) as old11 \gset
select tt.chk('T6 OLD 11-arg call works: total 450', (:'old11'::jsonb->>'total')::numeric=450);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[{"mode":"cash","amount":500}]',null,null,'retail',null,true,now()) as old11b \gset
select tt.chk('T6 OLD call, no discount: total 500', (:'old11b'::jsonb->>'total')::numeric=500);
select record_sale2(p_client=>gen_random_uuid(),p_loc=>1,p_lines=>'[{"amount":500}]',p_discount=>50,p_payments=>'[{"mode":"cash","amount":450}]',p_customer_mobile=>null,p_customer_name=>null,p_sale_type=>'retail',p_note=>null,p_quick=>true) as oldnamed \gset
select tt.chk('T6 OLD named-arg call works', (:'oldnamed'::jsonb->>'total')::numeric=450);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true,null,'percent',10) as pct \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true,null,'amount',50) as amt \gset
select tt.chk('T6 10% of 500 and amount 50 give the same total, discount and paid', (:'pct'::jsonb->>'total')::numeric = (:'amt'::jsonb->>'total')::numeric and (:'pct'::jsonb->>'discount')::numeric=50 and (:'amt'::jsonb->>'discount')::numeric=50 and (:'pct'::jsonb->>'total')::numeric=450);
select tt.chk('T6 stored kind/input: percent 10 / amount 50', (select discount_kind||discount_input from sales where id=(:'pct'::jsonb->>'id')::uuid)='percent10' and (select discount_kind||discount_input from sales where id=(:'amt'::jsonb->>'id')::uuid)='amount50.00');
select record_sale2(gen_random_uuid(),1,'[{"amount":333.33}]',0,'[{"mode":"cash","amount":291.66}]',null,null,'retail',null,true,null,'percent',12.5) as r1 \gset
select tt.chk('T6 rounding 2dp: 12.5% of 333.33 = 41.67 (41.66625), total 291.66', (:'r1'::jsonb->>'discount')::numeric=41.67 and (:'r1'::jsonb->>'total')::numeric=291.66);
select record_sale2(gen_random_uuid(),1,(select jsonb_build_array(jsonb_build_object('item_id',id,'qty',2)) from items where code='I-003'),0,'[{"mode":"cash","amount":630}]',null,null,'retail',null,false,null,'percent',10) as r2 \gset
select tt.chk('T6 item sale 2 x list price, 10%: total = 90% of subtotal', (:'r2'::jsonb->>'total')::numeric = round(700*0.9,2));
select tt.err('T6 percent above the limit needs approval (25% of 500 = 125 > 100)', $$select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[]',null,null,'retail',null,true,null,'percent',25)$$, 'discount_needs_approval');
select tt.err('T6 percent over 100 refused', $$select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[]',null,null,'retail',null,true,null,'percent',101)$$, 'bad_discount');
select tt.err('T6 percent without a value refused', $$select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[]',null,null,'retail',null,true,null,'percent',null)$$, 'bad_discount');
select tt.err('T6 unknown kind refused', $$select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[]',null,null,'retail',null,true,null,'bogus',5)$$, 'bad_discount_kind');
select tt.err('T6 amount above subtotal refused', $$select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',501,'[]',null,null,'retail',null,true)$$, 'bad_discount');
select set_config('request.jwt.claim.sub',:'o',false); select set_rule('discount_mode_percent_on','false');
select set_config('request.jwt.claim.sub',:'s',false);
select tt.err('T6 percent mode switched off -> refused', $$select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true,null,'percent',10)$$, 'discount_mode_off');
select tt.chk('T6 amount mode still works with percent off', (record_sale2(gen_random_uuid(),1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true)->>'total')::numeric=450);
select set_config('request.jwt.claim.sub',:'o',false); select set_rule('discount_mode_percent_on',null); select set_rule('discount_mode_amount_on','false');
select set_config('request.jwt.claim.sub',:'s',false);
select tt.err('T6 amount mode switched off -> refused', $$select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true)$$, 'discount_mode_off');
select tt.chk('T6 no-discount sale unaffected by both switches', (record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[{"mode":"cash","amount":500}]',null,null,'retail',null,true)->>'total')::numeric=500);
select set_config('request.jwt.claim.sub',:'o',false); select set_rule('discount_mode_amount_on',null);
select set_config('request.jwt.claim.sub',:'s',false);
select tt.chk('T6 retry with same client id is idempotent', (record_sale2((select client_id from sales where id=(:'pct'::jsonb->>'id')::uuid),1,'[{"amount":500}]',0,'[]',null,null,'retail',null,true,null,'percent',10)->>'dup')::boolean);

\echo == T7 favourites and saved views (own rows only)
select touch_favourite('form','10-1'); select touch_favourite('form','10-1'); select set_pin('report','sales_day',true);
select tt.chk('T7 uses counted and pin set', (select uses from user_favourites where key='10-1')=2 and (select pinned from user_favourites where key='sales_day'));
select set_config('request.jwt.claim.sub',:'k',false);
select tt.chk('T7 other user sees none of them', (select count(*) from user_favourites)=0);
select tt.err('T7 cannot write a row for someone else', format($$insert into user_favourites (user_id,kind,key) values (%L,'form','x')$$, :'s'), 'row-level security');
select set_config('request.jwt.claim.sub',:'s',false);
insert into report_views (name,report_code,params) values ('My daily','sales_day','{"loc":1}'), ('Team view','sales_day','{"loc":2}');
update report_views set shared=true where name='Team view';
select set_config('request.jwt.claim.sub',:'k',false);
select tt.chk('T7 other user sees only the shared view', (select string_agg(name,',') from report_views)='Team view');
select tt.err('T7 cannot create a view as someone else', format($$insert into report_views (owner_id,name,report_code) values (%L,'x','y')$$, :'s'), 'row-level security');
update report_views set name='hack';
select tt.chk('T7 cannot edit someone else''s shared view', (select count(*) from report_views where name='hack')=0);
delete from report_views;
select tt.chk('T7 cannot delete it either', (select count(*) from report_views)=1);
select set_config('request.jwt.claim.sub',:'o',false);
select tt.chk('T7 owner sees all views', (select count(*) from report_views)=2);

\echo == T8 audit trail written for new tables
reset role;
select tt.chk('T8 audit rows for templates, grants, suppliers, rules', (select count(distinct table_name) from audit_log where table_name in ('invoice_templates','user_grants','suppliers','rules','shelf_life_rules','unit_conversions'))=6);
select tt.chk('T8 customers.type_code exists, option lists seeded', exists(select 1 from information_schema.columns where table_name='customers' and column_name='type_code') and (select count(*) from option_lists where list_code in ('supplier_types','customer_types','units'))>=15);
select '--- FAILED: ' || count(*) from tt.res where not ok;
select '--- TOTAL: ' || count(*) from tt.res;
select name from tt.res where not ok;
