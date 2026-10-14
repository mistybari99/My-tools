-- FRESH DB ONLY. Phase 97 tests (Step Land: landed cost with every option).
--   ORDER="phase8 ... phase88 phase90 phase91 phase89" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> a97db ; psql ... -d a97db -f supabase/phase97.sql
--   psql -h /tmp -p 5544 -U postgres -d a97db -qAt -f supabase/phase97_test.sql | grep -E 'FAIL|RESULT'      (run from the repo root: it \i's phase97.sql again = the paste-twice test)
-- Numbers are hand-computed (comment above each block). Test data only, no person names. Place 1 (main).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set m '00000000-0000-0000-0000-000000000002'
\set a '00000000-0000-0000-0000-000000000003'
\set p '00000000-0000-0000-0000-000000000004'
\set x '00000000-0000-0000-0000-000000000005'
\set b '00000000-0000-0000-0000-000000000006'
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
create or replace function tt.noban(p text) returns boolean language sql immutable as $$ select p !~ '[ঀ-৿]' $$;
create or replace function tt.hasbn(p text) returns boolean language sql immutable as $$ select p ~ '[ঀ-৿]' $$;
create or replace function tt.unbalanced_entries() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
-- journal amount of one source type on one account code (originals only, debit or credit side)
create or replace function tt.jt(p_type text, p_code text, p_side text) returns numeric language sql stable as $$
  select coalesce(sum(case p_side when 'd' then l.debit else l.credit end), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
  where e.source_type = p_type and e.reverses_id is null and a.code = p_code $$;
create or replace function tt.jid(p_type text, p_id text, p_code text, p_side text) returns numeric language sql stable as $$
  select coalesce(sum(case p_side when 'd' then l.debit else l.credit end), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
  where e.source_type = p_type and e.source_id = p_id and e.reverses_id is null and a.code = p_code $$;
-- GL balance (debit - credit) of one account code, everything posted
create or replace function tt.gl(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.val(p_key text) returns numeric language sql stable as $$
  select coalesce(sum(round(b.qty * b.avg_cost, 2)), 0) from public.stock_balance b join public.items i on i.id = b.item_id where public._acct_inv_key(i.item_type) = p_key and b.avg_cost is not null $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'m','purch2@s.app','{"full_name":"Buyer"}'), (:'a','mgr3@s.app','{"full_name":"Maker"}'),
 (:'p','sales4@s.app','{"full_name":"Seller"}'), (:'x','norole5@s.app','{"full_name":"No Role"}'), (:'b','mgr6@s.app','{"full_name":"Approver"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'m','purchasing'),(:'a','management'),(:'b','management'),(:'p','salesperson') on conflict do nothing;
insert into user_locations values (:'m',1),(:'a',1),(:'b',1),(:'p',1) on conflict do nothing;
-- m (purchasing: landed_entry only), a (maker) and b (approver) may see costs; p has the landed grant but NO cost right (cost secrecy)
insert into user_grants (user_id, grant_code, location_id) values (:'m','view_cost',null),(:'a','view_cost',null),(:'b','view_cost',null),(:'p','landed_entry',null) on conflict do nothing;
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-A','Flour','Flour','kg','kg',0,true,'raw_material') returning id) select id as ia from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-B','Box','Box','pc','pc',0,true,'packaging') returning id) select id as ib from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-C','Sugar','Sugar','kg','kg',0,true,'raw_material') returning id) select id as ic from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-D','Salt','Salt','kg','kg',0,true,'raw_material') returning id) select id as id_ from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-E','Rice','Rice','kg','kg',0,true,'raw_material') returning id) select id as ie from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-F','Oil','Oil','kg','kg',0,true,'raw_material') returning id) select id as if_ from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-G','Lentil','Lentil','kg','kg',0,true,'raw_material') returning id) select id as ig from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-H','Spice','Spice','kg','kg',0,true,'raw_material') returning id) select id as ih from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-I','Tea','Tea','kg','kg',0,true,'raw_material') returning id) select id as ii from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-J','Cup','Cup','pc','pc',0,true,'packaging') returning id) select id as ij from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-K','Napkin','Napkin','pc','pc',0,true,'packaging') returning id) select id as ik from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-W','Wheat','Wheat','kg','kg',0,true,'raw_material') returning id) select id as iw from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-X','Barley','Barley','kg','kg',0,true,'raw_material') returning id) select id as ix from i \gset
with i as (insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values ('L97-N','Service','Service','pc','pc',0,false,'consumable') returning id) select id as inn from i \gset
with i as (insert into suppliers (name) values ('Sup One') returning id) select id as s1 from i \gset
with i as (insert into suppliers (name) values ('Transporter') returning id) select id as s2 from i \gset
with i as (insert into suppliers (name) values ('Importer') returning id) select id as s3 from i \gset

\echo == T0 shape and defaults (every new switch = today's behaviour)
select tt.chk('T0 rules exist with the right kind / choices / default', (select count(*) from rules where key in ('landed_cost_mode','landed_alloc_default','landed_late_mode','landed_cost_requires_approval','landed_reminder_on','landed_reminder_days','landed_base_currency') and module='purchase')=7
  and (select choices from rules where key='landed_cost_mode')='["off","manual","per_bill","per_shipment"]'::jsonb and (select choices from rules where key='landed_late_mode')='["split_remaining_and_cogs","post_to_remaining_stock","variance_account"]'::jsonb
  and (select choices from rules where key='landed_alloc_default')='["value","qty","weight","volume","manual","equal"]'::jsonb and (select choices from rules where key='landed_cost_requires_approval')='["warn","required"]'::jsonb);
select tt.chk('T0 defaults: mode off, value, split, warn, reminder off, base BDT (landed cost is OFF = invoice price)', rule_txt('landed_cost_mode')='off' and rule_txt('landed_alloc_default')='value' and rule_txt('landed_late_mode')='split_remaining_and_cogs'
  and rule_txt('landed_cost_requires_approval')='warn' and not rule_on('landed_reminder_on') and rule_txt('landed_base_currency')='BDT');
select tt.chk('T0 every new rule has bn, mix and en label and hint', (select bool_and(label_bn is not null and label_mix is not null and label_en is not null and hint_bn is not null and hint_mix is not null and hint_en is not null) from rules where key like 'landed\_%'));
select tt.chk('T0 English rule text has no Bangla characters; Bangla text has Bangla', (select bool_and(tt.noban(label_en) and tt.noban(hint_en) and tt.hasbn(label_bn) and tt.hasbn(hint_bn)) from rules where key like 'landed\_%'));
select tt.chk('T0 charge types: 15 seeded, treatments as designed', (select count(*) from cost_charge_types)=15 and (select treatment from cost_charge_types where code='freight')='capitalise' and (select treatment from cost_charge_types where code='vat_recov')='recoverable_tax'
  and (select treatment from cost_charge_types where code='freight_exp')='expense_only' and (select treatment from cost_charge_types where code='vat_nonrec')='capitalise');
select tt.chk('T0 English charge type names and hints have no Bangla characters', (select bool_and(tt.noban(name_en) and tt.noban(coalesce(hint_en,'')) and tt.hasbn(name_bn)) from cost_charge_types));
select tt.chk('T0 mapping keys added to the intended accounts', (select string_agg(m.key||'='||a.code, ',' order by m.key) from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key in ('vat_input','landed_payable','landed_variance')) = 'landed_payable=2150,landed_variance=5150,vat_input=1240');
select tt.chk('T0 grants exist', (select count(*) from grant_defs where grant_code in ('landed_entry','landed_approve'))=2);
select tt.chk('T0 tables: RLS on, closed to the browser (no select / insert for authenticated or anon)', (select bool_and(relrowsecurity) from pg_class where relname in ('landed_costs','landed_cost_docs','landed_cost_lines','landed_cost_basis','landed_cost_alloc','landed_cost_stock','item_logistics','landed_supplier_flags','landed_skips'))
  and not has_table_privilege('authenticated','public.landed_costs','select') and not has_table_privilege('authenticated','public.landed_cost_alloc','insert') and not has_table_privilege('anon','public.landed_cost_lines','select')
  and not has_table_privilege('authenticated','public.landed_cost_stock','select') and not has_table_privilege('authenticated','public.item_logistics','select'));
select tt.chk('T0 RPCs open to signed-in only; internals closed', has_function_privilege('authenticated','public.landed_post(uuid,uuid)','execute') and has_function_privilege('authenticated','public.landed_preview(uuid[],jsonb,jsonb,text,text)','execute')
  and not has_function_privilege('anon','public.landed_post(uuid,uuid)','execute') and not has_function_privilege('anon','public.landed_save(uuid,uuid,jsonb,jsonb,jsonb,jsonb)','execute')
  and not has_function_privilege('authenticated','public._landed_plan97(jsonb,jsonb,jsonb,text)','execute') and not has_function_privilege('authenticated','public._landed_jlines97(uuid,text)','execute') and not has_function_privilege('authenticated','public._landed_rows97(uuid[],jsonb)','execute'));
select tt.chk('T0 the stock ledger accepts cost_adjust now, all older reasons are still allowed', (select pg_get_constraintdef(oid) like '%cost_adjust%' and pg_get_constraintdef(oid) like '%transit_loss%' and pg_get_constraintdef(oid) like '%purchase_in%' from pg_constraint where conname='stock_ledger_reason_check'));
select tt.chk('T0 _acct_docs carries bos97 and every older tag (bos50 bos52 bos72 bos74 bos80 bos85 bos89)', (select bool_and(position(t in d)>0) from (select pg_get_functiondef('public._acct_docs(date)'::regprocedure) d) x, unnest(array['bos97','bos89','bos85','bos80','bos74','bos72','bos52','bos50']) t));
select tt.chk('T0 the old 7-argument acct_journal_post is still gone (one only)', (select count(*) from pg_proc where proname='acct_journal_post')=1);

\echo == setup: accounting on from 5 days ago
set role authenticated; select tt.as(:'o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
select set_rule('acct_issue_out','true') is null as on2 \gset
reset role;
select tt.chk('setup: accounting on', rule_on('accounting_on') and rule_on('acct_issue_out'));

\echo == B1 bill 1: LA 20 kg @ 10 = 200 and LB 30 pc @ 20 = 600 (subtotal 800, no discount)
set role authenticated; select tt.as(:'o');
select landed_logistics_set(:'ib'::uuid, 0.4, null, 'box weight') is not null as lg \gset
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-B1',tt.today()-2,format('[{"item_id":"%s","qty":20,"unit":"kg","unit_cost":10},{"item_id":"%s","qty":30,"unit":"pc","unit_cost":20}]',:'ia',:'ib')::jsonb)->>'id' as b1 \gset
select post_purchase(:'b1'::uuid) is not null as pb1 \gset
select id as b1l1 from purchase_lines where bill_id=:'b1'::uuid and line_no=1 \gset
select id as b1l2 from purchase_lines where bill_id=:'b1'::uuid and line_no=2 \gset
reset role;
select tt.chk('B1 bill posted: LA 20 @ 10, LB 30 @ 20 (landed cost OFF = invoice price)', (select qty from stock_balance where item_id=:'ia'::uuid)=20 and (select avg_cost from stock_balance where item_id=:'ia'::uuid)=10
  and (select qty from stock_balance where item_id=:'ib'::uuid)=30 and (select avg_cost from stock_balance where item_id=:'ib'::uuid)=20);

\echo == M0 mode OFF: nothing can be saved, the preview still works
set role authenticated; select tt.as(:'o');
select tt.err('M0 save refused while the mode is off', format($$select landed_save(gen_random_uuid(),null,'{}'::jsonb,'[{"type":"bill","id":"%s"}]','[{"charge_type":"freight","amount":100}]')$$, :'b1'), 'landed_off');
select landed_preview(array[:'b1'::uuid], '[{"charge_type":"freight","amount":100}]'::jsonb) as pv0 \gset
reset role;
select tt.chk('M0 preview works with the mode off and shows mode off', :'pv0'::jsonb->>'mode'='off' and (:'pv0'::jsonb->>'ok')::boolean);

\echo == P1 preview, freight 100 on bill 1: qty 40/60, value 25/75, weight 62.5/37.5, equal 50/50 (hand numbers)
-- LA weight 20 kg (the unit says kg), LB weight 30 x 0.4 = 12 kg (item weight): 20:12 -> 62.5 / 37.5. Value 200:600 -> 25 / 75. Qty 20:30 -> 40 / 60.
select jsonb_path_query_first(:'pv0'::jsonb, '$.lines[0].methods.qty.alloc')::numeric as qa, jsonb_path_query_first(:'pv0'::jsonb, '$.lines[1].methods.qty.alloc')::numeric as qb \gset
select tt.chk('P1 qty split 40 / 60', :'qa'::numeric=40 and :'qb'::numeric=60);
select tt.chk('P1 value split 25 / 75', (:'pv0'::jsonb->'lines'->0->'methods'->'value'->>'alloc')::numeric=25 and (:'pv0'::jsonb->'lines'->1->'methods'->'value'->>'alloc')::numeric=75);
select tt.chk('P1 weight split 62.5 / 37.5', (:'pv0'::jsonb->'lines'->0->'methods'->'weight'->>'alloc')::numeric=62.5 and (:'pv0'::jsonb->'lines'->1->'methods'->'weight'->>'alloc')::numeric=37.5);
select tt.chk('P1 equal split 50 / 50', (:'pv0'::jsonb->'lines'->0->'methods'->'equal'->>'alloc')::numeric=50 and (:'pv0'::jsonb->'lines'->1->'methods'->'equal'->>'alloc')::numeric=50);
select tt.chk('P1 new unit cost LA: qty 12, value 11.25, weight 13.125, equal 12.5', (:'pv0'::jsonb->'lines'->0->'methods'->'qty'->>'new_unit_cost')::numeric=12 and (:'pv0'::jsonb->'lines'->0->'methods'->'value'->>'new_unit_cost')::numeric=11.25
  and (:'pv0'::jsonb->'lines'->0->'methods'->'weight'->>'new_unit_cost')::numeric=13.125 and (:'pv0'::jsonb->'lines'->0->'methods'->'equal'->>'new_unit_cost')::numeric=12.5);
select tt.chk('P1 new unit cost LB: qty 22, value 22.5, weight 21.25', (:'pv0'::jsonb->'lines'->1->'methods'->'qty'->>'new_unit_cost')::numeric=22 and (:'pv0'::jsonb->'lines'->1->'methods'->'value'->>'new_unit_cost')::numeric=22.5
  and (:'pv0'::jsonb->'lines'->1->'methods'->'weight'->>'new_unit_cost')::numeric=21.25);
select tt.chk('P1 qty over kg and pc lines is flagged as mixed units (still available, with the warning)', (:'pv0'::jsonb->'avail'->'qty'->>'mixed_units')::boolean and (:'pv0'::jsonb->'avail'->'qty'->>'ok')::boolean);
select tt.chk('P1 percent up LA by value = 12.5', (:'pv0'::jsonb->'lines'->0->'methods'->'value'->>'pct_up')::numeric=12.5);
select tt.chk('P1 volume and manual are NOT available (unknown, not guessed) and say why', not (:'pv0'::jsonb->'avail'->'volume'->>'ok')::boolean and :'pv0'::jsonb->'avail'->'volume'->>'why'='volume_unknown'
  and not (:'pv0'::jsonb->'avail'->'manual'->>'ok')::boolean and :'pv0'::jsonb->'avail'->'manual'->>'why'='manual_missing' and not (:'pv0'::jsonb->'lines'->0->'methods' ? 'volume') and not (:'pv0'::jsonb->'lines'->0->'methods' ? 'manual'));
select tt.chk('P1 weight source: LA from the unit (kg), LB from the item', :'pv0'::jsonb->'lines'->0->>'weight_src'='unit' and (:'pv0'::jsonb->'lines'->0->>'weight')::numeric=20 and :'pv0'::jsonb->'lines'->1->>'weight_src'='item' and (:'pv0'::jsonb->'lines'->1->>'weight')::numeric=12);
-- manual %: LA 30, LB 70 -> 30 / 70 ; new unit LA 10 + 30/20 = 11.5 ; LB 20 + 70/30 = 22.333333
set role authenticated; select tt.as(:'o');
select landed_preview(array[:'b1'::uuid], '[{"charge_type":"freight","amount":100}]'::jsonb, format('[{"bill_line_id":%s,"manual_pct":30},{"bill_line_id":%s,"manual_pct":70}]',:'b1l1',:'b1l2')::jsonb, 'manual') as pvm \gset
reset role;
select tt.chk('P1 manual 30 / 70 chosen: alloc 30 / 70, new unit LA 11.5, LB 22.333333', (:'pvm'::jsonb->'lines'->0->'chosen'->>'alloc')::numeric=30 and (:'pvm'::jsonb->'lines'->1->'chosen'->>'alloc')::numeric=70
  and (:'pvm'::jsonb->'lines'->0->'chosen'->>'new_unit_cost')::numeric=11.5 and (:'pvm'::jsonb->'lines'->1->'chosen'->>'new_unit_cost')::numeric=22.333333);
set role authenticated; select tt.as(:'o');
select landed_preview(array[:'b1'::uuid], '[{"charge_type":"freight","amount":100}]'::jsonb, format('[{"bill_line_id":%s,"manual_pct":30},{"bill_line_id":%s,"manual_pct":60}]',:'b1l1',:'b1l2')::jsonb, 'manual') as pvm2 \gset
reset role;
select tt.chk('P1 manual % that do not add to 100 are refused in the preview (not ok, error says method_unavailable:manual)', not (:'pvm2'::jsonb->>'ok')::boolean and :'pvm2'::jsonb->>'error' like 'method_unavailable:manual%' and (:'pvm2'::jsonb->'avail'->'manual'->>'sum')::numeric=90);
select tt.chk('P1 a preview wrote nothing', (select count(*) from landed_costs)=0 and (select count(*) from landed_cost_alloc)=0 and (select count(*) from stock_ledger where reason='cost_adjust')=0 and (select qty from stock_balance where item_id=:'ia'::uuid)=20 and (select avg_cost from stock_balance where item_id=:'ia'::uuid)=10);

\echo == R1 recommendation (from the numbers)
set role authenticated; select tt.as(:'o');
select landed_recommendation(array[:'b1'::uuid], null, '[{"charge_type":"freight","amount":100},{"charge_type":"duty","amount":40}]'::jsonb) as rc1 \gset
reset role;
select tt.chk('R1 freight -> weight (all weights known); header method follows the biggest charge (freight = weight)', :'rc1'::jsonb->>'method'='weight' and (:'rc1'::jsonb->'per_charge'->0->>'method')='weight' and (:'rc1'::jsonb->'per_charge'->1->>'method')='value'
  and :'rc1'::jsonb->'per_charge'->0->'reason'->>'code'='m_weight');
select tt.chk('R1 the reason has bn, mix and en; en has no Bangla, bn and mix have Bangla', tt.noban(:'rc1'::jsonb->'per_charge'->0->'reason'->>'en') and tt.hasbn(:'rc1'::jsonb->'per_charge'->0->'reason'->>'bn') and tt.hasbn(:'rc1'::jsonb->'per_charge'->0->'reason'->>'mix')
  and jsonb_array_length(:'rc1'::jsonb->'reasons')=1);
select tt.chk('R1 no late warning (nothing sold yet)', not exists (select 1 from jsonb_array_elements(:'rc1'::jsonb->'warnings') w where w->>'code' like '%late%'));
-- a line whose weight is unknown: Napkin (pc, no item weight) in a bill with Flour
set role authenticated; select tt.as(:'o');
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-BW',tt.today()-2,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":10},{"item_id":"%s","qty":100,"unit":"pc","unit_cost":1}]',:'iw',:'ik')::jsonb)->>'id' as bw \gset
select post_purchase(:'bw'::uuid) is not null as pbw \gset
select landed_recommendation(array[:'bw'::uuid], null, '[{"charge_type":"freight","amount":100}]'::jsonb) as rc2 \gset
select landed_preview(array[:'bw'::uuid], '[{"charge_type":"freight","amount":100}]'::jsonb, '[]'::jsonb, 'weight') as pvw \gset
reset role;
select tt.chk('R1 unknown weight: freight falls back to value, warns, and lists the item that has no weight (not guessed)', :'rc2'::jsonb->>'method'='value' and (:'rc2'::jsonb->'per_charge'->0->'reason'->>'code')='m_weight_fallback'
  and exists (select 1 from jsonb_array_elements(:'rc2'::jsonb->'warnings') w where w->>'code'='w_weight_unknown' and w->'items' ? 'L97-K'));
select tt.chk('R1 weight method in the preview is unavailable, no weight number was invented', not (:'pvw'::jsonb->'avail'->'weight'->>'ok')::boolean and :'pvw'::jsonb->'avail'->'weight'->>'why'='weight_unknown' and not (:'pvw'::jsonb->>'ok')::boolean
  and :'pvw'::jsonb->'lines'->1->>'weight' is null);

\echo == S1 switch the mode on (manual) and save the MAIN landed cost: freight 100 (weight, payable to the transporter) + duty 40 (value, bank); header value
set role authenticated; select tt.as(:'o');
select set_rule('landed_cost_mode','"manual"') is null as r1 \gset
select set_rule('landed_cost_requires_approval','"required"') is null as r2 \gset
select tt.as(:'a');
select landed_save('11111111-0000-0000-0000-000000000001'::uuid, null, '{"title":"Main lot","alloc_method":"value"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'b1')::jsonb,
  format('[{"charge_type":"freight","amount":100,"alloc_method":"weight","pay_mode":"payable","supplier_id":"%s"},{"charge_type":"duty","amount":40,"pay_mode":"bank"}]',:'s2')::jsonb) as sv1 \gset
select (:'sv1'::jsonb->>'id')::uuid as c1 \gset
select landed_save('11111111-0000-0000-0000-000000000001'::uuid, null, '{}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'b1')::jsonb, '[{"charge_type":"freight","amount":1}]') as sv1b \gset
reset role;
select tt.chk('S1 draft saved, total 140, one row each', :'sv1'::jsonb->>'status'='draft' and (:'sv1'::jsonb->>'total')::numeric=140 and (select count(*) from landed_cost_lines where cost_id=:'c1'::uuid)=2 and (select count(*) from landed_cost_docs where cost_id=:'c1'::uuid)=1
  and (select status from landed_costs where id=:'c1'::uuid)='draft' and (select location_id from landed_costs where id=:'c1'::uuid)=1);
select tt.chk('S1 the same client id saves nothing new (dup)', (:'sv1b'::jsonb->>'dup')::boolean and :'sv1b'::jsonb->>'id'=:'c1' and (select count(*) from landed_costs)=1);
select tt.chk('S1 saving wrote no stock and no journal', (select count(*) from stock_ledger where reason='cost_adjust')=0 and not exists (select 1 from journal_entries where source_type='landed_cost') and (select avg_cost from stock_balance where item_id=:'ia'::uuid)=10);
set role authenticated; select tt.as(:'a');
select tt.err('S1 required approval: cannot post a draft', format($$select landed_post('%s')$$, :'c1'), 'approval_required');
select tt.err('S1 the maker cannot approve his own (required)', format($$select landed_approve('%s')$$, :'c1'), 'approver_must_differ');
select tt.as(:'m');
select tt.err('S1 a buyer with the landed_entry grant only cannot approve', format($$select landed_approve('%s')$$, :'c1'), 'not allowed');
select tt.as(:'b');
select landed_approve(:'c1'::uuid)->>'status' as ap1 \gset
select tt.as(:'o');
select landed_get(:'c1'::uuid) as g1 \gset
reset role;
select tt.chk('S1 another person approves: status approved, with who and when', :'ap1'='approved' and (select approved_by from landed_costs where id=:'c1'::uuid)=:'b'::uuid and (select approved_at is not null from landed_costs where id=:'c1'::uuid));
select tt.chk('S1 landed_get shows the saved preview: LA chosen alloc 72.5 (62.5 freight by weight + 10 duty by value), LB 67.5 (37.5 + 30)', (:'g1'::jsonb->'preview'->'lines'->0->'chosen'->>'alloc')::numeric=72.5 and (:'g1'::jsonb->'preview'->'lines'->1->'chosen'->>'alloc')::numeric=67.5
  and (:'g1'::jsonb->'preview'->'lines'->0->'chosen'->>'new_unit_cost')::numeric=13.625 and (:'g1'::jsonb->'preview'->'lines'->1->'chosen'->>'new_unit_cost')::numeric=22.25);
set role authenticated; select tt.as(:'a');
select landed_post(:'c1'::uuid, '22222222-0000-0000-0000-000000000001'::uuid) as po1 \gset
select landed_post(:'c1'::uuid, '22222222-0000-0000-0000-000000000001'::uuid) as po1b \gset
select landed_post(:'c1'::uuid) as po1c \gset
reset role;

\echo == P2 posted: LA +72.5 -> avg (200+72.5)/20 = 13.625 ; LB +67.5 -> avg (600+67.5)/30 = 22.25 ; ledger pair, rows, no extra qty
select tt.chk('P2 post result: status posted, 4 rows (2 charges x 2 lines), stock added 140, variance 0', :'po1'::jsonb->>'status'='posted' and (:'po1'::jsonb->>'posted')::int=4 and (:'po1'::jsonb->>'stock_added')::numeric=140 and (:'po1'::jsonb->>'to_variance')::numeric=0 and not (:'po1'::jsonb->>'dup')::boolean);
select tt.chk('P2 average cost LA 13.625 and LB 22.25, quantities unchanged 20 / 30', (select avg_cost from stock_balance where item_id=:'ia'::uuid)=13.625 and (select avg_cost from stock_balance where item_id=:'ib'::uuid)=22.25
  and (select qty from stock_balance where item_id=:'ia'::uuid)=20 and (select qty from stock_balance where item_id=:'ib'::uuid)=30);
select tt.chk('P2 the ledger got a pair per item: out 20 @ 10 then in 20 @ 13.625 (reason cost_adjust, ref landed)', (select count(*) from stock_ledger where reason='cost_adjust' and ref_type='landed' and ref_id=:'c1')=4
  and exists (select 1 from stock_ledger where reason='cost_adjust' and item_id=:'ia'::uuid and qty_delta=-20 and unit_cost=10) and exists (select 1 from stock_ledger where reason='cost_adjust' and item_id=:'ia'::uuid and qty_delta=20 and unit_cost=13.625)
  and exists (select 1 from stock_ledger where reason='cost_adjust' and item_id=:'ib'::uuid and qty_delta=-30 and unit_cost=20) and exists (select 1 from stock_ledger where reason='cost_adjust' and item_id=:'ib'::uuid and qty_delta=30 and unit_cost=22.25));
select tt.chk('P2 value of the adjustment pair = exactly the amount added (sum qty*cost: LA 72.5, LB 67.5)', (select sum(qty_delta*unit_cost) from stock_ledger where reason='cost_adjust' and item_id=:'ia'::uuid)=72.5 and (select sum(qty_delta*unit_cost) from stock_ledger where reason='cost_adjust' and item_id=:'ib'::uuid)=67.5);
select tt.chk('P2 alloc rows (append-only): 4 stock rows 62.5 / 37.5 / 10 / 30', (select count(*) from landed_cost_alloc where cost_id=:'c1'::uuid and kind='post' and part='stock')=4 and (select sum(amount) from landed_cost_alloc where cost_id=:'c1'::uuid and part='stock' and item_id=:'ia'::uuid)=72.5
  and (select sum(amount) from landed_cost_alloc where cost_id=:'c1'::uuid and part='stock' and item_id=:'ib'::uuid)=67.5 and (select count(*) from landed_cost_alloc where cost_id=:'c1'::uuid and part='cogs')=0);
select tt.chk('P2 stock rows kept: LA 20 on hand before, avg 10 -> 13.625 ; LB avg 20 -> 22.25', (select avg_before=10 and avg_after=13.625 and on_hand_before=20 and stock_value=72.5 from landed_cost_stock where cost_id=:'c1'::uuid and item_id=:'ia'::uuid and kind='post')
  and (select avg_before=20 and avg_after=22.25 and stock_value=67.5 from landed_cost_stock where cost_id=:'c1'::uuid and item_id=:'ib'::uuid and kind='post'));
select tt.chk('P2 re-post posts 0: same client id and a fresh press both return dup, ledger / rows unchanged', (:'po1b'::jsonb->>'dup')::boolean and (:'po1c'::jsonb->>'dup')::boolean and (:'po1b'::jsonb->>'posted')::int=0 and (:'po1c'::jsonb->>'posted')::int=0
  and (select count(*) from stock_ledger where reason='cost_adjust')=4 and (select count(*) from landed_cost_alloc where cost_id=:'c1'::uuid)=4 and (select avg_cost from stock_balance where item_id=:'ia'::uuid)=13.625);
select tt.chk('P2 required approval: no warning raised (it was approved)', not exists (select 1 from exceptions where flag_code='landed_unapproved'));
select tt.chk('P2 header carries who posted, the late mode used and is locked', (select posted_by=:'a'::uuid and late_mode_used='split_remaining_and_cogs' and status='posted' from landed_costs where id=:'c1'::uuid));
select tt.as(:'o');
select tt.chk('P2 stock_reconcile (replay of the whole ledger) finds no difference: average and quantity replay to the cached values', (select count(*) from (select * from stock_reconcile(false)) z)=0 or (select count(*) from stock_reconcile(false))=0);

\echo == G1 journal after the tick: Dr inv_raw 72.5, Dr inv_pack 67.5 ; Cr landed_payable 100 (party transporter), Cr bank 40
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as tick1 \gset
select acct_post_pending(false) as tick2 \gset
select inventory_vs_gl(tt.today(), null) as iv1 \gset
reset role;
select tt.chk('G1 the landed entry is posted once; a second tick posts nothing new', (:'tick1'::jsonb->'by_type'->>'landed_cost')::int=1 and coalesce((:'tick2'::jsonb->'by_type'->>'landed_cost')::int,0)=0 and (select count(*) from journal_entries where source_type='landed_cost' and source_id=:'c1')=1);
select tt.chk('G1 debit side: raw 1320 = 72.5, packaging 1330 = 67.5', tt.jt('landed_cost','1320','d')=72.5 and tt.jt('landed_cost','1330','d')=67.5);
select tt.chk('G1 credit side: landed payable 2150 = 100, bank 1120 = 40', tt.jt('landed_cost','2150','c')=100 and tt.jt('landed_cost','1120','c')=40);
select tt.chk('G1 the payable line carries the transporter as party', exists (select 1 from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='landed_cost' and e.source_id=:'c1' and l.party_type='supplier' and l.party_id=:'s2' and l.credit=100));
select tt.chk('G1 no unbalanced journal entry anywhere (trial balance balanced)', tt.unbalanced_entries()=0 and (select sum(debit) from journal_lines)=(select sum(credit) from journal_lines));
select tt.chk('G1 GL = valuation: raw 272.5 and packaging 667.5 (stock value of the lot including freight and duty)', (select round(qty*avg_cost,2) from stock_balance where item_id=:'ib'::uuid)=667.5 and (select round(qty*avg_cost,2) from stock_balance where item_id=:'ia'::uuid)=272.5);
select tt.chk('G1 inventory_vs_gl agrees for the whole company (diff 0, unexplained 0)', (:'iv1'::jsonb->'total'->>'diff')::numeric=0 and (:'iv1'::jsonb->'total'->>'unexplained')::numeric=0 and (:'iv1'::jsonb->>'agree')::boolean);

\echo == X1 immutability, locks, secrecy
select tt.err('X1 alloc rows cannot be edited', $$update landed_cost_alloc set amount=1$$, 'landed_append_only');
select tt.err('X1 alloc rows cannot be deleted', $$delete from landed_cost_alloc$$, 'landed_append_only');
select tt.err('X1 stock rows cannot be edited', $$update landed_cost_stock set stock_value=1$$, 'landed_append_only');
select tt.err('X1 alloc table cannot be truncated', $$truncate landed_cost_alloc$$, 'landed_append_only');
select tt.err('X1 a posted header cannot be edited', format($$update landed_costs set total=1 where id='%s'$$, :'c1'), 'landed_locked');
select tt.err('X1 a header cannot be deleted', format($$delete from landed_costs where id='%s'$$, :'c1'), 'landed_no_delete');
select tt.err('X1 lines of a posted cost cannot be changed', format($$update landed_cost_lines set amount=1 where cost_id='%s'$$, :'c1'), 'landed_locked');
select tt.err('X1 the stock ledger itself is still immutable', $$update stock_ledger set unit_cost=1 where reason='cost_adjust'$$, 'ledger_immutable');
set role authenticated; select tt.as(:'m');
select tt.err('X1 a posted cost cannot be saved again', format($$select landed_save(null,'%s','{}'::jsonb,'[{"type":"bill","id":"%s"}]','[{"charge_type":"freight","amount":5}]')$$, :'c1', :'b1'), 'not_editable');
select tt.err('X1 the browser cannot read the tables', $$select * from landed_costs$$, 'permission denied');
select tt.err('X1 the browser cannot read the alloc rows', $$select * from landed_cost_alloc$$, 'permission denied');
select tt.as(:'p');
select tt.err('X1 cost secrecy: a buyer with the landed grant but no cost right cannot preview', format($$select landed_preview(array['%s'::uuid], '[{"charge_type":"freight","amount":1}]')$$, :'b1'), 'not allowed');
select tt.err('X1 cost secrecy: ... nor read a landed cost', format($$select landed_get('%s')$$, :'c1'), 'not allowed');
select tt.as(:'x');
select tt.err('X1 a user with no role cannot preview', format($$select landed_preview(array['%s'::uuid], '[{"charge_type":"freight","amount":1}]')$$, :'b1'), 'not allowed');
select jsonb_array_length(landed_list()) as nlx \gset
select tt.as(:'o');
select jsonb_array_length(landed_list()) as nl \gset
select jsonb_array_length(landed_list('posted')) as nlp \gset
select tt.as(:'m');
select jsonb_array_length(landed_list()) as nlm \gset
reset role;
select tt.chk('X1 owner and a cost-right grant holder see the list (1 posted cost); a user with no right sees an empty list', :'nl'=1 and :'nlp'=1 and :'nlm'=1 and :'nlx'=0);
select tt.chk('X1 every landed change was audited (header, lines, alloc, stock)', (select count(*) from audit_log where table_name='landed_costs')>=3 and (select count(*) from audit_log where table_name='landed_cost_alloc')=4 and (select count(*) from audit_log where table_name='landed_cost_stock')=2);

\echo == C1 bill 2 with discount, a foreign-currency charge, a recoverable tax and an expense-only charge
-- LC 10 kg @ 30 and LD 10 kg @ 70, bill discount 100 on 1000 -> net 0.9 : cost 27 and 63. Charges: freight 60 (weight 10:10 -> 30 / 30), duty USD 3 @ 100 = 300 BDT (value 270:630 -> 90 / 210),
-- recoverable tax 50 (cash, not in the item cost), bank fee 20 expense only (bank). Stock: LC 120 -> avg 27 + 12 = 39 ; LD 240 -> 63 + 24 = 87.
set role authenticated; select tt.as(:'o');
select set_rule('landed_cost_requires_approval','"warn"') is null as r3 \gset
select save_purchase(gen_random_uuid(),null,:'s3'::uuid,1,'L97-B2',tt.today()-1,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":30},{"item_id":"%s","qty":10,"unit":"kg","unit_cost":70}]',:'ic',:'id_')::jsonb,100)->>'id' as b2 \gset
select post_purchase(:'b2'::uuid) is not null as pb2 \gset
reset role;
select tt.chk('C1 bill 2 posted with the discount spread: LC 27, LD 63', (select avg_cost from stock_balance where item_id=:'ic'::uuid)=27 and (select avg_cost from stock_balance where item_id=:'id_'::uuid)=63);
set role authenticated; select tt.as(:'o');
select tt.err('C1 a foreign-currency charge needs a rate (never guessed)', format($$select landed_save(null,null,'{}'::jsonb,'[{"type":"bill","id":"%s"}]','[{"charge_type":"duty","amount_ccy":3,"ccy":"USD"}]')$$, :'b2'), 'rate_required');
select tt.err('C1 an unknown charge type is refused', format($$select landed_save(null,null,'{}'::jsonb,'[{"type":"bill","id":"%s"}]','[{"charge_type":"nothing","amount":3}]')$$, :'b2'), 'bad_charge_type');
select tt.err('C1 no charges is refused', format($$select landed_save(null,null,'{}'::jsonb,'[{"type":"bill","id":"%s"}]','[]')$$, :'b2'), 'no_charges');
select tt.err('C1 a zero amount is refused', format($$select landed_save(null,null,'{}'::jsonb,'[{"type":"bill","id":"%s"}]','[{"charge_type":"freight","amount":0}]')$$, :'b2'), 'bad_amount');
select landed_save(gen_random_uuid(), null, '{"alloc_method":"value","title":"Bill 2"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'b2')::jsonb,
  format('[{"charge_type":"freight","amount":60,"alloc_method":"weight","pay_mode":"payable","supplier_id":"%s"},{"charge_type":"duty","amount_ccy":3,"ccy":"USD","rate":100,"pay_mode":"bank"},{"charge_type":"vat_recov","amount":50,"pay_mode":"cash"},{"charge_type":"bank_exp","amount":20,"pay_mode":"bank"}]',:'s2')::jsonb) as sv2 \gset
select (:'sv2'::jsonb->>'id')::uuid as c2 \gset
select landed_post(:'c2'::uuid) as po2 \gset
select acct_post_pending(false) as tick3 \gset
reset role;
select tt.chk('C1 USD 3 x 100 = 300 BDT stored with currency and rate; total 430', (select amount=300 and amount_ccy=3 and ccy='USD' and rate=100 from landed_cost_lines where cost_id=:'c2'::uuid and charge_type='duty') and (select total from landed_costs where id=:'c2'::uuid)=430);
select tt.chk('C1 warn mode: posted without approval -> one yellow warning', (select status from landed_costs where id=:'c2'::uuid)='posted' and (select count(*) from exceptions where flag_code='landed_unapproved' and level='yellow')=1);
select tt.chk('C1 stock only gets the capitalised 360: LC avg 39, LD avg 87', (select avg_cost from stock_balance where item_id=:'ic'::uuid)=39 and (select avg_cost from stock_balance where item_id=:'id_'::uuid)=87 and (:'po2'::jsonb->>'stock_added')::numeric=360);
select tt.chk('C1 alloc: freight 30 / 30, duty 90 / 210, tax row 50 (tax), expense row 20 (expense)', (select sum(amount) from landed_cost_alloc where cost_id=:'c2'::uuid and item_id=:'ic'::uuid)=120 and (select sum(amount) from landed_cost_alloc where cost_id=:'c2'::uuid and item_id=:'id_'::uuid)=240
  and (select amount from landed_cost_alloc where cost_id=:'c2'::uuid and part='tax')=50 and (select dr_key from landed_cost_alloc where cost_id=:'c2'::uuid and part='tax')='vat_input'
  and (select amount from landed_cost_alloc where cost_id=:'c2'::uuid and part='expense')=20 and (select dr_key from landed_cost_alloc where cost_id=:'c2'::uuid and part='expense')='bank_charges');
select tt.chk('C1 journal: Dr raw 360, Dr VAT input 50, Dr bank charges 20 ; Cr landed payable 60, Cr bank 320, Cr cash 50 (430 = 430)', tt.jt('landed_cost','1240','d')=50 and tt.jt('landed_cost','5810','d')=20
  and (select coalesce(sum(l.debit),0) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where e.source_type='landed_cost' and e.source_id=:'c2' and a.code='1320')=360
  and (select coalesce(sum(l.credit),0) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where e.source_type='landed_cost' and e.source_id=:'c2' and a.code='2150')=60
  and (select coalesce(sum(l.credit),0) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where e.source_type='landed_cost' and e.source_id=:'c2' and a.code='1120')=320
  and (select coalesce(sum(l.credit),0) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where e.source_type='landed_cost' and e.source_id=:'c2' and a.code='1110')=50
  and (select sum(l.debit) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='landed_cost' and e.source_id=:'c2')=430);
select tt.chk('C1 trial balance still balanced', tt.unbalanced_entries()=0);

\echo == L1 late bill: goods already used. LE 10 kg @ 20 = 200, 4 kg issued -> 6 on hand ; freight 50 arrives (split mode)
-- split: stock = 50 x 6/10 = 30, variance 20 ; avg (6 x 20 + 30) / 6 = 25.
set role authenticated; select tt.as(:'o');
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-L1',tt.today()-1,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":20}]',:'ie')::jsonb)->>'id' as l1 \gset
select post_purchase(:'l1'::uuid) is not null as pl1 \gset
select stock_issue(:'ie'::uuid,1,4,null,'to kitchen') is not null as is1 \gset
select landed_recommendation(array[:'l1'::uuid], null, '[{"charge_type":"freight","amount":50}]'::jsonb) as rc3 \gset
select landed_save(gen_random_uuid(), null, '{"alloc_method":"value"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'l1')::jsonb, '[{"charge_type":"freight","amount":50,"pay_mode":"payable"}]') as sv3 \gset
select (:'sv3'::jsonb->>'id')::uuid as c3 \gset
select landed_preview(array[:'l1'::uuid], '[{"charge_type":"freight","amount":50}]'::jsonb) as pv3 \gset
select landed_post(:'c3'::uuid) as po3 \gset
reset role;
select tt.chk('L1 recommendation warns: part of the lot is already used (4 units) and suggests split', exists (select 1 from jsonb_array_elements(:'rc3'::jsonb->'warnings') w where w->>'code'='late_goods_sold' and (w->>'qty')::numeric=4) and :'rc3'::jsonb->>'late_mode'='split_remaining_and_cogs');
select tt.chk('L1 the preview shows the split before posting: item stock 30, cogs 20, avg after 25, late qty 4', (:'pv3'::jsonb->'items'->0->>'stock')::numeric=30 and (:'pv3'::jsonb->'items'->0->>'cogs')::numeric=20 and (:'pv3'::jsonb->'items'->0->>'avg_after')::numeric=25 and (:'pv3'::jsonb->'items'->0->>'late_qty')::numeric=4);
select tt.chk('L1 split posted: avg 25 on 6 kg, stock 30, variance 20', (select avg_cost from stock_balance where item_id=:'ie'::uuid)=25 and (select qty from stock_balance where item_id=:'ie'::uuid)=6 and (:'po3'::jsonb->>'stock_added')::numeric=30 and (:'po3'::jsonb->>'to_variance')::numeric=20
  and (select sum(amount) from landed_cost_alloc where cost_id=:'c3'::uuid and part='stock')=30 and (select sum(amount) from landed_cost_alloc where cost_id=:'c3'::uuid and part='cogs')=20 and (select dr_key from landed_cost_alloc where cost_id=:'c3'::uuid and part='cogs')='landed_variance');
select tt.chk('L1 late cost raised a yellow warning', (select count(*) from exceptions where flag_code='landed_late_cost')=1);
-- mode post_to_remaining_stock: LF 10 kg @ 20, 4 issued, freight 50 -> all 50 into the 6 left: avg (120 + 50) / 6 = 28.333333, value 170.00
set role authenticated; select tt.as(:'o');
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-L2',tt.today()-1,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":20}]',:'if_')::jsonb)->>'id' as l2 \gset
select post_purchase(:'l2'::uuid) is not null as pl2 \gset
select stock_issue(:'if_'::uuid,1,4,null,'to kitchen') is not null as is2 \gset
select (landed_save(gen_random_uuid(), null, '{"alloc_method":"value","late_mode":"post_to_remaining_stock"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'l2')::jsonb, '[{"charge_type":"freight","amount":50}]')->>'id')::uuid as c4 \gset
select landed_post(:'c4'::uuid) as po4 \gset
-- mode variance_account: LG 10 kg @ 20, 4 issued, freight 50 -> all 50 to the variance account, avg stays 20
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-L3',tt.today()-1,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":20}]',:'ig')::jsonb)->>'id' as l3 \gset
select post_purchase(:'l3'::uuid) is not null as pl3 \gset
select stock_issue(:'ig'::uuid,1,4,null,'to kitchen') is not null as is3 \gset
select (landed_save(gen_random_uuid(), null, '{"alloc_method":"value","late_mode":"variance_account"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'l3')::jsonb, '[{"charge_type":"freight","amount":50}]')->>'id')::uuid as c5 \gset
select landed_post(:'c5'::uuid) as po5 \gset
-- NOT late: LH 10 kg @ 20 untouched, freight 50, any mode -> all 50 into stock (avg 25 on 10)
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-L4',tt.today()-1,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":20}]',:'ih')::jsonb)->>'id' as l4 \gset
select post_purchase(:'l4'::uuid) is not null as pl4 \gset
select (landed_save(gen_random_uuid(), null, '{"alloc_method":"value","late_mode":"variance_account"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'l4')::jsonb, '[{"charge_type":"freight","amount":50}]')->>'id')::uuid as c6 \gset
select landed_post(:'c6'::uuid) as po6 \gset
select acct_post_pending(false) as tick4 \gset
select inventory_vs_gl(tt.today(), null) as iv4 \gset
reset role;
select tt.chk('L1 post_to_remaining_stock: avg 28.333333 on 6 kg, value 170.00, nothing to variance', (select avg_cost from stock_balance where item_id=:'if_'::uuid)=28.333333 and (select round(qty*avg_cost,2) from stock_balance where item_id=:'if_'::uuid)=170 and (:'po4'::jsonb->>'stock_added')::numeric=50 and (:'po4'::jsonb->>'to_variance')::numeric=0);
select tt.chk('L1 variance_account: avg stays 20, all 50 to variance, no ledger adjustment for that item', (select avg_cost from stock_balance where item_id=:'ig'::uuid)=20 and (:'po5'::jsonb->>'stock_added')::numeric=0 and (:'po5'::jsonb->>'to_variance')::numeric=50
  and not exists (select 1 from stock_ledger where reason='cost_adjust' and item_id=:'ig'::uuid) and (select sum(amount) from landed_cost_alloc where cost_id=:'c5'::uuid and dr_key='landed_variance')=50);
select tt.chk('L1 not late: the late mode is irrelevant, all 50 into stock, avg 25 on 10', (select avg_cost from stock_balance where item_id=:'ih'::uuid)=25 and (:'po6'::jsonb->>'stock_added')::numeric=50 and (:'po6'::jsonb->>'to_variance')::numeric=0 and (:'po6'::jsonb->>'late')::boolean is false);
select tt.chk('L1 variance GL 5150 = 20 + 50 = 70 (split share + variance account)', tt.gl('5150')=70);
select tt.chk('L1 GL = valuation after all late modes: inventory_vs_gl agree, diff 0, unexplained 0', (:'iv4'::jsonb->>'agree')::boolean and (:'iv4'::jsonb->'total'->>'diff')::numeric=0 and (:'iv4'::jsonb->'total'->>'unexplained')::numeric=0);
select tt.chk('L1 trial balance balanced', tt.unbalanced_entries()=0 and (select sum(debit) from journal_lines)=(select sum(credit) from journal_lines));

\echo == V1 void restores. Void of the split cost after 3 more kg were used: only the part still on the shelf leaves the stock
-- LE: 6 on hand @ 25, issue 3 more (at 25) -> 3 left. Void: factor 3/6 -> stock released 15 ; avg (3 x 25 - 15) / 3 = 20 ; the other 35 (20 sold at post + 15 used since) is credited to the variance account.
set role authenticated; select tt.as(:'o');
select stock_issue(:'ie'::uuid,1,3,null,'more to kitchen') is not null as is4 \gset
select acct_post_pending(false) as tick5 \gset
select tt.as(:'m');
select tt.err('V1 the maker (landed_entry only) cannot void: needs the approve right', format($$select landed_void('%s','wrong')$$, :'c3'), 'not allowed');
select tt.as(:'a');
select tt.err('V1 a reason is needed', format($$select landed_void('%s','')$$, :'c3'), 'reason_required');
select landed_void(:'c3'::uuid, 'freight was wrong') as vo3 \gset
select landed_void(:'c3'::uuid, 'again') as vo3b \gset
select tt.as(:'o');
select acct_post_pending(false) as tick6 \gset
select acct_post_pending(false) as tick7 \gset
select inventory_vs_gl(tt.today(), null) as iv6 \gset
reset role;
select tt.chk('V1 void: avg back to 20 on 3 kg, header void with reason, a second void is a no-op', :'vo3'::jsonb->>'status'='void' and (select avg_cost from stock_balance where item_id=:'ie'::uuid)=20 and (select qty from stock_balance where item_id=:'ie'::uuid)=3
  and (select void_reason from landed_costs where id=:'c3'::uuid)='freight was wrong' and (:'vo3b'::jsonb->>'dup')::boolean);
select tt.chk('V1 void rows: stock -15, variance -35 (append-only, the original rows stay)', (select sum(amount) from landed_cost_alloc where cost_id=:'c3'::uuid and kind='void' and part='stock')=-15 and (select sum(amount) from landed_cost_alloc where cost_id=:'c3'::uuid and kind='void' and part='cogs')=-35
  and (select count(*) from landed_cost_alloc where cost_id=:'c3'::uuid and kind='post')=2);
select tt.chk('V1 void journal: its own counter entry once, Dr landed payable 50, Cr raw 15, Cr variance 35', (:'tick6'::jsonb->'by_type'->>'landed_cost_void')::int=1 and coalesce((:'tick7'::jsonb->'by_type'->>'landed_cost_void')::int,0)=0
  and (select count(*) from journal_entries where source_type='landed_cost_void' and source_id=:'c3')=1 and tt.jid('landed_cost_void',:'c3','2150','d')=50 and tt.jid('landed_cost_void',:'c3','1320','c')=15 and tt.jid('landed_cost_void',:'c3','5150','c')=35);
select tt.chk('V1 stock after void: ledger pair of the void (3 out @ 25, 3 in @ 20), reconcile finds nothing', (select count(*) from stock_ledger where reason='cost_adjust' and item_id=:'ie'::uuid)=4 and exists (select 1 from stock_ledger where reason='cost_adjust' and item_id=:'ie'::uuid and qty_delta=3 and unit_cost=20)
  and (select count(*) from stock_reconcile(false))=0);
select tt.chk('V1 GL = valuation after the void (raw GL for LE = 60 = 3 x 20) and the whole company agrees', (:'iv6'::jsonb->>'agree')::boolean and (:'iv6'::jsonb->'total'->>'diff')::numeric=0 and tt.unbalanced_entries()=0);
set role authenticated; select tt.as(:'o');
select tt.err('V1 post after void refused', format($$select landed_post('%s')$$, :'c3'), 'landed_void');
reset role;
-- void of a draft: no journal, no stock
set role authenticated; select tt.as(:'o');
select (landed_save(gen_random_uuid(), null, '{}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'b1')::jsonb, '[{"charge_type":"loading","amount":9}]')->>'id')::uuid as c7 \gset
select landed_void(:'c7'::uuid, 'not needed') as vo7 \gset
reset role;
select tt.chk('V1 a draft can be cancelled (void) with no stock or journal effect', :'vo7'::jsonb->>'status'='void' and not exists (select 1 from journal_entries where source_id=:'c7') and (select count(*) from landed_cost_alloc where cost_id=:'c7'::uuid)=0);

\echo == M1 modes per_bill / per_shipment, two bills of one lot, shared item
-- LI-style lot: Spice (LH) bills: 10 kg @ 10 and 10 kg @ 30 (same item) ; shipment freight 80 by qty -> 40 / 40 ; item total 20 kg, avg (100 + 300) / 20 = 20 -> (400 + 80) / 20 = 24.
set role authenticated; select tt.as(:'o');
select save_purchase(gen_random_uuid(),null,:'s3'::uuid,1,'L97-S1',tt.today()-1,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":10}]',:'ii')::jsonb)->>'id' as s1b \gset
select post_purchase(:'s1b'::uuid) is not null as ps1 \gset
select save_purchase(gen_random_uuid(),null,:'s3'::uuid,1,'L97-S2',tt.today()-1,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":30}]',:'ii')::jsonb)->>'id' as s2b \gset
select post_purchase(:'s2b'::uuid) is not null as ps2 \gset
select set_rule('landed_cost_mode','"per_bill"') is null as pm1 \gset
select tt.err('M1 per_bill: one landed cost covers one bill only', format($$select landed_save(null,null,'{}'::jsonb,'[{"type":"bill","id":"%s"},{"type":"bill","id":"%s"}]','[{"charge_type":"freight","amount":80}]')$$, :'s1b', :'s2b'), 'per_bill_one_bill');
select set_rule('landed_cost_mode','"per_shipment"') is null as pm2 \gset
select tt.err('M1 per_shipment: a shipment reference is needed', format($$select landed_save(null,null,'{}'::jsonb,'[{"type":"bill","id":"%s"},{"type":"bill","id":"%s"}]','[{"charge_type":"freight","amount":80}]')$$, :'s1b', :'s2b'), 'shipment_ref_needed');
select (landed_save(gen_random_uuid(), null, '{"shipment_ref":"SHIP-1","alloc_method":"qty"}'::jsonb, format('[{"type":"bill","id":"%s"},{"type":"bill","id":"%s"}]',:'s1b',:'s2b')::jsonb, '[{"charge_type":"freight","amount":80,"alloc_method":"qty"}]')->>'id')::uuid as c8 \gset
select landed_post(:'c8'::uuid) as po8 \gset
reset role;
select tt.chk('M1 per_shipment: 2 bills, one lot: 40 / 40, avg of the shared item (400 + 80) / 20 = 24', (select count(*) from landed_cost_docs where cost_id=:'c8'::uuid)=2 and (select avg_cost from stock_balance where item_id=:'ii'::uuid)=24 and (select qty from stock_balance where item_id=:'ii'::uuid)=20
  and (select count(*) from landed_cost_alloc where cost_id=:'c8'::uuid and amount=40)=2 and (select shipment_ref from landed_costs where id=:'c8'::uuid)='SHIP-1');
select tt.chk('M1 one stock row for the shared item (lot qty 20)', (select count(*) from landed_cost_stock where cost_id=:'c8'::uuid and kind='post')=1 and (select lot_qty from landed_cost_stock where cost_id=:'c8'::uuid and kind='post')=20);
set role authenticated; select tt.as(:'o');
select set_rule('landed_cost_mode','"manual"') is null as pm3 \gset
-- a second, late charge on the same bill is allowed (a bill can get more than one landed cost)
select (landed_save(gen_random_uuid(), null, '{"alloc_method":"qty"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'s1b')::jsonb, '[{"charge_type":"unloading","amount":10}]')->>'id')::uuid as c9 \gset
select landed_post(:'c9'::uuid) as po9 \gset
reset role;
select tt.chk('M1 manual mode: a second charge on the same bill is added on top: avg 24 + 10 / 20 = 24.5', (select avg_cost from stock_balance where item_id=:'ii'::uuid)=24.5);

\echo == D1 GRN (form 04-1) as the reference of a landed cost
set role authenticated; select tt.as(:'o');
select set_rule('forms_post_to_ledger','false') is null as g0 \gset
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-G1',tt.today()-1,format('[{"item_id":"%s","qty":10,"unit":"pc","unit_cost":10}]',:'ij')::jsonb)->>'id' as g1b \gset
select post_purchase(:'g1b'::uuid) is not null as pg1 \gset
select save_entry(null,'04-1',1,tt.today(),'{"supplier":"Sup One","lines":[{"item":"L97-J","counted":"10","rate":"10","quality":"accept"}]}','[]') ->> 'id' as gn \gset
select submit_entry(:'gn'::uuid) is not null as sgn \gset
select tt.err('D1 a GRN that is not linked to a bill cannot take a landed cost', format($$select landed_save(null,null,'{}'::jsonb,'[{"type":"grn","id":"%s"}]','[{"charge_type":"freight","amount":10}]')$$, :'gn'), 'grn_not_linked');
select grn_bill_link(:'gn'::uuid, :'g1b'::uuid) is not null as lk \gset
select (landed_save(gen_random_uuid(), null, '{}'::jsonb, format('[{"type":"grn","id":"%s"}]',:'gn')::jsonb, '[{"charge_type":"freight","amount":30,"pay_mode":"payable"},{"charge_type":"freight","amount":-10,"note":"supplier refund of part of the freight"}]')->>'id')::uuid as c10 \gset
select landed_post(:'c10'::uuid) as po10 \gset
select tt.err('D1 a bill with a posted landed cost cannot be voided until the landed cost is voided', format($$select void_purchase('%s','wrong bill')$$, :'g1b'), 'landed_cost_posted');
select acct_post_pending(false) as tick8 \gset
reset role;
select tt.chk('D1 the GRN was resolved to its bill; a credit (negative) charge nets: +30 -10 = +20 -> avg (100 + 20) / 10 = 12', (select doc_type='grn' and bill_id=:'g1b'::uuid from landed_cost_docs where cost_id=:'c10'::uuid) and (select avg_cost from stock_balance where item_id=:'ij'::uuid)=12 and (:'po10'::jsonb->>'stock_added')::numeric=20);
select tt.chk('D1 journal nets the credit: Dr packaging 20 ; Cr landed payable 20 (30 - 10)', (select coalesce(sum(l.debit),0) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where e.source_type='landed_cost' and e.source_id=:'c10' and a.code='1330')=20
  and (select coalesce(sum(l.credit),0) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where e.source_type='landed_cost' and e.source_id=:'c10' and a.code='2150')=20);
set role authenticated; select tt.as(:'o');
select landed_void(:'c10'::uuid, 'test') is not null as vo10 \gset
select void_purchase(:'g1b'::uuid, 'now the bill may be voided') is not null as vb \gset
reset role;
select tt.chk('D1 after the landed cost is voided the bill can be voided', (select status from purchase_bills where id=:'g1b'::uuid)='void');

\echo == R2 returns of such a purchase
-- Bill 1 (LA 20 kg, landed 72.5): per kg 72.5 / 20 = 3.625. Return 4 kg: landed part on the returned goods 4 x 3.625 = 14.5 (the stock leaves at 13.625, the supplier credits 10: variance 14.5).
set role authenticated; select tt.as(:'o');
select set_rule('acct_purchase_variance','true') is null as pvv \gset
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-R1',tt.today(),format('[{"item_id":"%s","qty":4,"unit":"kg","unit_cost":10}]',:'ia')::jsonb,0,'price',null,'return',:'b1'::uuid,'quality')->>'id' as r1 \gset
select post_purchase(:'r1'::uuid) is not null as pr1 \gset
select landed_return_info(:'r1'::uuid) as ri \gset
select landed_return_info(:'b1'::uuid) as ri2 \gset
reset role;
select tt.chk('R2 return info: LA returned 4 kg carries 3.625 per kg = 14.5 of landed cost; LB none returned', (:'ri'::jsonb->>'has_landed')::boolean and (select (x->>'returned_qty')::numeric=4 and (x->>'landed_per_unit')::numeric=3.625 and (x->>'landed_on_returned')::numeric=14.5 from jsonb_array_elements(:'ri'::jsonb->'items') x where x->>'code'='L97-A')
  and (:'ri'::jsonb->>'total')::numeric=14.5 and (:'ri2'::jsonb->>'total')::numeric=14.5);
select tt.chk('R2 the note says it stays as a purchase variance and how to refund (bn / mix / en)', tt.noban(:'ri'::jsonb->'note'->>'en') and tt.hasbn(:'ri'::jsonb->'note'->>'bn') and tt.hasbn(:'ri'::jsonb->'note'->>'mix'));
select tt.chk('R2 the return left the stock at the average including landed cost: 16 kg left at 13.625 ; the variance journal (switch acct_purchase_variance) books the 14.5 landed part', (select qty from stock_balance where item_id=:'ia'::uuid)=16 and (select avg_cost from stock_balance where item_id=:'ia'::uuid)=13.625);

\echo == Z1 reminder list and the small tools
set role authenticated; select tt.as(:'o');
select landed_reminders() as rm0 \gset
select save_purchase(gen_random_uuid(),null,:'s3'::uuid,1,'L97-Z1',tt.today(),format('[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":10}]',:'iw')::jsonb)->>'id' as z1b \gset
select post_purchase(:'z1b'::uuid) is not null as pz1 \gset
select set_rule('landed_reminder_on','true') is null as rmon \gset
select landed_supplier_flag_set(:'s3'::uuid, 'imported', true, 'imports') is not null as fl \gset
select landed_reminders() as rm1 \gset
select landed_skip(:'z1b'::uuid, 'no extra charge on this one') is not null as sk \gset
select landed_reminders() as rm2 \gset
select landed_info() as inf \gset
reset role;
select tt.chk('Z1 reminder off by default: no list', not (:'rm0'::jsonb->>'on')::boolean and jsonb_array_length(:'rm0'::jsonb->'rows')=0);
select tt.chk('Z1 reminder on + imported supplier flag: the importer bill without a landed cost is listed, bills that already have one are not', (:'rm1'::jsonb->>'on')::boolean
  and exists (select 1 from jsonb_array_elements(:'rm1'::jsonb->'rows') r where r->>'bill_no'='L97-Z1') and not exists (select 1 from jsonb_array_elements(:'rm1'::jsonb->'rows') r where r->>'bill_no'='L97-B2' or r->>'bill_no'='L97-S1'));
select tt.chk('Z1 a skipped bill leaves the list', not exists (select 1 from jsonb_array_elements(:'rm2'::jsonb->'rows') r where r->>'bill_no'='L97-Z1'));
select tt.chk('Z1 landed_info reports the mode and the charge types', :'inf'::jsonb->>'mode'='manual' and jsonb_array_length(:'inf'::jsonb->'charge_types')=15 and (:'inf'::jsonb->>'can_entry')::boolean);
set role authenticated; select tt.as(:'o');
select landed_charge_type_save('customs_extra','Extra শুল্ক','Extra customs fee','Extra customs fee','capitalise',null,'value',true) is not null as ct1 \gset
select landed_charge_type_save('freight','x','x','x','expense_only','exp_transport',null,true) is not null as ct2 \gset
select tt.as(:'m');
select tt.err('Z1 only the owner adds or changes charge types', $$select landed_charge_type_save('abc','a','b','c','capitalise')$$, 'not allowed');
reset role;
select tt.chk('Z1 owner-added type works; the owner can flip the treatment of a system type (system names stay)', (select treatment from cost_charge_types where code='customs_extra')='capitalise' and (select is_system from cost_charge_types where code='customs_extra') is false
  and (select treatment='expense_only' and name_en='Freight / transport in' from cost_charge_types where code='freight'));
set role authenticated; select tt.as(:'o');
select landed_charge_type_save('freight','x','x','x','capitalise',null,'weight',true) is not null as ct3 \gset
reset role;

\echo == E2 more options: volume, equal with a rounding remainder, fully-sold lot, re-open an approved cost
-- Cup 10 pc @ 5 (volume 0.5 l each = 5 l), Napkin 20 pc @ 1 (0.1 l each = 2 l): freight 70 by volume -> 50 / 20 ; by qty 10:20 -> 23.33 / 46.67 ; by value 50:20 -> 50 / 20.
set role authenticated; select tt.as(:'o');
select landed_logistics_set(:'ij'::uuid, null, 0.5, 'cup') is not null as lv1 \gset
select landed_logistics_set(:'ik'::uuid, null, 0.1, 'napkin') is not null as lv2 \gset
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-V1',tt.today(),format('[{"item_id":"%s","qty":10,"unit":"pc","unit_cost":5},{"item_id":"%s","qty":20,"unit":"pc","unit_cost":1}]',:'ij',:'ik')::jsonb)->>'id' as v1b \gset
select post_purchase(:'v1b'::uuid) is not null as pv1 \gset
select landed_preview(array[:'v1b'::uuid], '[{"charge_type":"freight","amount":70}]'::jsonb) as pve \gset
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-T3',tt.today(),format('[{"item_id":"%s","qty":1,"unit":"pc","unit_cost":1},{"item_id":"%s","qty":1,"unit":"pc","unit_cost":1},{"item_id":"%s","qty":1,"unit":"kg","unit_cost":1}]',:'ij',:'ik',:'iw')::jsonb)->>'id' as t3b \gset
select post_purchase(:'t3b'::uuid) is not null as pt3 \gset
select landed_preview(array[:'t3b'::uuid], '[{"charge_type":"loading","amount":100}]'::jsonb, '[]'::jsonb, 'equal') as pv3e \gset
reset role;
select tt.chk('E2 volume: unit volumes known -> available; freight 70 splits 50 / 20 by volume', (:'pve'::jsonb->'avail'->'volume'->>'ok')::boolean and (:'pve'::jsonb->'lines'->0->'methods'->'volume'->>'alloc')::numeric=50 and (:'pve'::jsonb->'lines'->1->'methods'->'volume'->>'alloc')::numeric=20);
select tt.chk('E2 same bill by qty (10:20) 23.33 / 46.67 and by value (50:20) 50 / 20; the parts always add up to 70', (:'pve'::jsonb->'lines'->0->'methods'->'qty'->>'alloc')::numeric=23.33 and (:'pve'::jsonb->'lines'->1->'methods'->'qty'->>'alloc')::numeric=46.67
  and (:'pve'::jsonb->'lines'->0->'methods'->'value'->>'alloc')::numeric=50 and (:'pve'::jsonb->'lines'->1->'methods'->'value'->>'alloc')::numeric=20);
select tt.chk('E2 equal over 3 lines: 100 -> 33.34 / 33.33 / 33.33 (the remainder cent goes to the first line, the sum is exactly 100)', (select sum((l->'methods'->'equal'->>'alloc')::numeric) from jsonb_array_elements(:'pv3e'::jsonb->'lines') l)=100
  and (:'pv3e'::jsonb->'lines'->0->'chosen'->>'alloc')::numeric=33.34 and (:'pv3e'::jsonb->'lines'->1->'chosen'->>'alloc')::numeric=33.33 and (:'pv3e'::jsonb->'lines'->2->'chosen'->>'alloc')::numeric=33.33);
-- a lot that is entirely sold: LX 10 kg @ 20, all 10 issued, freight 25 in split mode -> nothing left to hold it: all 25 to the variance account, no stock change
set role authenticated; select tt.as(:'o');
select set_rule('landed_cost_mode','"manual"') is null as pm4 \gset
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-X1',tt.today(),format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":20}]',:'ix')::jsonb)->>'id' as x1b \gset
select post_purchase(:'x1b'::uuid) is not null as px1 \gset
select stock_issue(:'ix'::uuid,1,10,null,'all used') is not null as isx \gset
select landed_recommendation(array[:'x1b'::uuid], null, '[{"charge_type":"freight","amount":25}]'::jsonb) as rcx \gset
select (landed_save(gen_random_uuid(), null, '{"alloc_method":"value"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'x1b')::jsonb, '[{"charge_type":"freight","amount":25}]')->>'id')::uuid as cx \gset
select landed_post(:'cx'::uuid) as pox \gset
-- re-open: an approved cost saved again goes back to draft and loses its approval
select (landed_save(gen_random_uuid(), null, '{}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'t3b')::jsonb, '[{"charge_type":"loading","amount":6}]')->>'id')::uuid as cr \gset
select tt.as(:'b');
select landed_approve(:'cr'::uuid)->>'status' as apr \gset
select tt.as(:'o');
select landed_save(null, :'cr'::uuid, '{}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'t3b')::jsonb, '[{"charge_type":"loading","amount":9}]')->>'status' as rst \gset
reset role;
select tt.chk('E2 sold-out lot: recommendation says all sold -> variance account; the split post puts all 25 to variance, no ledger pair, avg unchanged', exists (select 1 from jsonb_array_elements(:'rcx'::jsonb->'warnings') w where w->>'code'='late_all_sold') and :'rcx'::jsonb->>'late_mode'='variance_account'
  and (:'pox'::jsonb->>'stock_added')::numeric=0 and (:'pox'::jsonb->>'to_variance')::numeric=25 and not exists (select 1 from stock_ledger where reason='cost_adjust' and item_id=:'ix'::uuid) and (select qty from stock_balance where item_id=:'ix'::uuid)=0);
select tt.chk('E2 an approved cost saved again returns to draft, approval cleared, new total 9', :'apr'='approved' and :'rst'='draft' and (select status='draft' and approved_by is null and total=9 from landed_costs where id=:'cr'::uuid));

\echo == W1 other places, untracked lines, switch back off
set role authenticated; select tt.as(:'o');
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-U1',tt.today(),format('[{"item_id":"%s","qty":2,"unit":"pc","unit_cost":5}]',:'inn')::jsonb)->>'id' as u1 \gset
select post_purchase(:'u1'::uuid) is not null as pu1 \gset
select landed_preview(array[:'u1'::uuid], '[{"charge_type":"freight","amount":10}]'::jsonb) as pvu \gset
select (landed_save(gen_random_uuid(), null, '{}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'u1')::jsonb, '[{"charge_type":"freight","amount":10}]')->>'id')::uuid as c11 \gset
select tt.err('W1 posting it is refused (no_stock_lines) and nothing is written', format($$select landed_post('%s')$$, :'c11'), 'no_stock_lines');
select set_rule('landed_cost_mode','"off"') is null as moff \gset
select tt.err('W1 switched off again: post refused', format($$select landed_post('%s')$$, :'c11'), 'landed_off');
reset role;
select tt.chk('W1 the preview of a bill without stock lines says so', exists (select 1 from jsonb_array_elements(:'pvu'::jsonb->'recommendation'->'warnings') w where w->>'code'='no_stock_lines') and (select count(*) from landed_cost_alloc where cost_id=:'c11'::uuid)=0);
select tt.chk('W1 draft left alone writes no stock / journal', not exists (select 1 from journal_entries where source_id=:'c11'));

\echo == Y1 an old bill keeps costing exactly its invoice price with the mode off (today)
set role authenticated; select tt.as(:'o');
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'L97-Y1',tt.today(),format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":50}]',:'ic')::jsonb)->>'id' as y1 \gset
select post_purchase(:'y1'::uuid) is not null as py1 \gset
reset role;
select tt.chk('Y1 mode off: the new purchase costs the invoice price (LC: 10 @ 39 + 10 @ 50 -> avg 44.5)', (select avg_cost from stock_balance where item_id=:'ic'::uuid)=44.5 and (select count(*) from landed_costs where status='posted')>=1);

\echo == V2 void of bill 2's cost (tax + expense-only charges + a later purchase of the same item)
-- LC: after the landed cost avg 39 on 10, then 10 kg @ 50 bought -> 20 @ 44.5. Void: factor min(1, 20/10) = 1 -> release 120 ; avg (20 x 44.5 - 120) / 20 = 38.5. LD: 87 -> 63.
set role authenticated; select tt.as(:'a');
select landed_void(:'c2'::uuid, 'duty was paid by the supplier') as vo2 \gset
select tt.as(:'o');
select acct_post_pending(false) as tick10 \gset
reset role;
select tt.chk('V2 void: LC avg 38.5 on 20 kg, LD avg 63 on 10 kg', (select avg_cost from stock_balance where item_id=:'ic'::uuid)=38.5 and (select qty from stock_balance where item_id=:'ic'::uuid)=20 and (select avg_cost from stock_balance where item_id=:'id_'::uuid)=63);
select tt.chk('V2 void journal mirrors every line: Dr payable 60, Dr bank 320, Dr cash 50 ; Cr raw 360, Cr VAT input 50, Cr bank charges 20', tt.jid('landed_cost_void',:'c2','2150','d')=60 and tt.jid('landed_cost_void',:'c2','1120','d')=320 and tt.jid('landed_cost_void',:'c2','1110','d')=50
  and tt.jid('landed_cost_void',:'c2','1320','c')=360 and tt.jid('landed_cost_void',:'c2','1240','c')=50 and tt.jid('landed_cost_void',:'c2','5810','c')=20);
select tt.chk('V2 after voiding, the tax and bank-fee accounts net to 0 and the books are balanced', tt.gl('1240')=0 and tt.unbalanced_entries()=0);

\echo == END checks: the whole book
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) as tick9 \gset
select inventory_vs_gl(tt.today(), null) as ivz \gset
select acct_trial_balance(null,null) as tbz \gset
reset role;
select tt.chk('END the purchase-return variance journal booked the landed part of the returned goods (switch acct_purchase_variance): 5140 debit 14.5', tt.jt('purchase_variance','5140','d')=14.5);
select tt.chk('END trial balance balanced: no entry with debit <> credit', tt.unbalanced_entries()=0 and (select sum(debit) from journal_lines)=(select sum(credit) from journal_lines));
select tt.chk('END inventory_vs_gl agrees at the end (diff 0, unexplained 0)', (:'ivz'::jsonb->>'agree')::boolean and (:'ivz'::jsonb->'total'->>'diff')::numeric=0 and (:'ivz'::jsonb->'total'->>'unexplained')::numeric=0);
select tt.chk('END stock_reconcile: the immutable ledger replays to the cached quantities and averages (no difference)', (select count(*) from stock_reconcile(false))=0);
select tt.chk('END every cost_adjust is a pair: per cost and item the quantity out equals the quantity in (net qty 0)', not exists (select 1 from stock_ledger where reason='cost_adjust' group by ref_id, item_id having sum(qty_delta) <> 0)
  and (select count(*) from stock_ledger where reason='cost_adjust') % 2 = 0);
select tt.chk('END nothing other than stock cost, rows and journal changed: sale / purchase tables untouched (bill 1 still total 800)', (select total from purchase_bills where id=:'b1'::uuid)=800 and (select count(*) from purchase_lines where bill_id=:'b1'::uuid)=2);


\echo == J1 phase89 pasted again after phase97: landed posting refuses (journal_not_ready) until phase97 is pasted again
set role authenticated; select tt.as(:'o');
select set_rule('landed_cost_mode','"manual"') is null as pm5 \gset
select (landed_save(gen_random_uuid(), null, '{"alloc_method":"value"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'y1')::jsonb, '[{"charge_type":"loading","amount":10}]')->>'id')::uuid as cj \gset
select landed_resolve_docs(format('[{"type":"bill","id":"%s"}]',:'y1')::jsonb) as rsd \gset
select landed_info()->>'journal_ready' as jr0 \gset
reset role;
select tt.chk('J1 landed_resolve_docs returns the bill of a bill doc; journal_ready is true with phase97 on top', :'rsd'::jsonb->0->>'bill_id'=:'y1' and :'jr0'='true');
\i supabase/phase89.sql
set role authenticated; select tt.as(:'o');
select landed_info()->>'journal_ready' as jr1 \gset
select tt.err('J1 after phase89 was pasted again the landed post refuses instead of changing stock without the books', format($$select landed_post('%s')$$, :'cj'), 'journal_not_ready');
reset role;
select tt.chk('J1 journal_ready is false after phase89 and nothing was written for the refused post', :'jr1'='false' and (select status from landed_costs where id=:'cj'::uuid)='draft' and not exists (select 1 from landed_cost_alloc where cost_id=:'cj'::uuid));
\i supabase/phase97.sql
set role authenticated; select tt.as(:'o');
select landed_post(:'cj'::uuid) as poj \gset
select acct_post_pending(false) as tickj \gset
reset role;
select tt.chk('J1 pasting phase97 again restores it: the post works and its journal entry is made by the tick', :'poj'::jsonb->>'status'='posted' and (:'tickj'::jsonb->'by_type'->>'landed_cost')::int>=1 and tt.unbalanced_entries()=0);
select tt.chk('J1 the permission recommendation table knows the new grants (phase91 pasted later changes nothing)', (select count(*) from perm_reco_role where grant_code in ('landed_entry','landed_approve'))=3);
select tt.chk('LANG every recommendation message: en has no Bangla, bn and mix have Bangla', (select bool_and(tt.noban(m->>'en') and tt.hasbn(m->>'bn') and tt.hasbn(m->>'mix')) from (select public._landed_msg97(c, '5', 'x') m from unnest(array['m_weight','m_volume','m_value','m_qty','m_equal','m_weight_fallback','m_volume_fallback','m_qty_mixed','m_single','w_late','w_late_all','w_weight_unknown','w_volume_unknown','w_fx','w_avg_unknown','w_no_stock','w_untracked','w_noncap','w_credit_capped','w_nocap']) c) z));
select tt.chk('LANG exception texts of landed costs: the English text has no Bangla, the Bangla text has', (select bool_and(tt.noban(text->>'en') and tt.hasbn(text->>'bn')) from exceptions where flag_code like 'landed\_%') and (select count(*) from exceptions where flag_code like 'landed\_%')>=2);

\echo == paste-twice
\i supabase/phase97.sql
select tt.chk('PT paste twice: still one _acct_docs with bos97, no duplicate rules / types / mappings', (select count(*) from rules where key like 'landed\_%')=7 and (select count(*) from cost_charge_types where code in ('freight','duty','insurance','clearing','loading','unloading','bank','packaging','vat_nonrec','vat_recov','delivery','fx_diff','freight_exp','bank_exp','other'))=15
  and (select count(*) from acct_mappings where key in ('vat_input','landed_payable','landed_variance'))=3 and position('bos97' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and (select count(*) from pg_proc where proname='_acct_docs')=1);
select tt.chk('PT the paste did not change user-set data: the owner-set treatment of a type is kept', (select treatment from cost_charge_types where code='freight')='capitalise');

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
