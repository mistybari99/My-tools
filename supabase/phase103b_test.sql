-- FRESH DB ONLY. REPLACEMENT of phase103_test.sql for a chain that ends with phase105 (Step Sec2): the same file, every re-paste of phase103 is followed by a paste of phase105 (docs/PASTE_ORDER.md section H). Phase 103 tests (Step E2E: the defects of the independent end-to-end run, D-1 .. D-8; see docs/briefs_p2p3/step_E2E_REPORT.md).
--   Build: bash tests/sql/final_build.sh <db> "<canonical order ... phase98 phase99 phase100 phase101 phase103>"   (phase103 pasted last; docs/PASTE_ORDER.md)
--   Run from the REPO ROOT (the last block pastes phase103.sql again):
--     psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase103_test.sql | grep -E "FAIL|RESULT"
--   FAILING-BEFORE: on the same build WITHOUT phase103 every D-n block fails (the file is written so that a missing function or an unchanged result is a FAIL, not an abort).
--   PASSING-AFTER: 0 fail. Every expected number is computed by hand in the comment of its block. Test data only, no real names.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set p '00000000-0000-0000-0000-000000000004'
\set v '00000000-0000-0000-0000-000000000005'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
-- run a statement, return its single value as text, or ERR:<message>
create or replace function tt.try(p_sql text) returns text language plpgsql as $$
declare r text;
begin execute p_sql into r; return r;
exception when others then return 'ERR:' || sqlerrm; end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.iid(p_code text) returns uuid language sql stable as $$ select id from public.items where code = p_code $$;
-- one account row of inventory_vs_gl and one reason amount of it
create or replace function tt.ivg(p_loc int, p_key text) returns jsonb language plpgsql as $$
begin return (select x from jsonb_array_elements(public.inventory_vs_gl(tt.today(), p_loc)->'rows') x where x->>'key' = p_key);
exception when others then return null; end $$;
create or replace function tt.reason(p_row jsonb, p_code text) returns numeric language sql immutable as $$
  select coalesce((select (r->>'amount')::numeric from jsonb_array_elements(p_row->'reasons') r where r->>'code' = p_code), 0) $$;
-- sum of debit - credit of the account mapped to a key, optionally for one place / one source type
create or replace function tt.gl(p_key text, p_loc int default null, p_src text default null) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.acct_mappings m on m.account_id = l.account_id
   where m.key = p_key and (p_loc is null or l.location_id = p_loc) and (p_src is null or e.source_type = p_src) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'p','sales4@s.app','{"full_name":"Sales"}'), (:'v','phoneview5@s.app','{"full_name":"Viewer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'p','salesperson'),(:'v','salesperson') on conflict do nothing;
insert into user_locations values (:'p',1),(:'v',1) on conflict do nothing;
insert into rule_grants (role_code, grant_code, allowed) values ('salesperson','inbox_contact_view',true) on conflict (role_code, grant_code) do update set allowed=true;
select tt.as(:'o');
select set_user_grant(:'v'::uuid, 'view_customer_mobile') is null as g1 \gset
select acct_set_start(tt.today() - 5)->>'start' as sd \gset
select acct_opening('[{"code":"1110","debit":20000,"location_id":1},{"code":"3100","credit":20000}]'::jsonb)->>'id' as oj \gset
select set_rule('accounting_on', 'true') is null as aon \gset
select tt.chk('S0 setup: accounting start, opening journal, accounting on', :'oj' is not null and rule_on('accounting_on'));
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('W','W','Water','ltr','ltr','raw_material',true,0,false), ('A','A','Sugar','kg','kg','raw_material',true,0,false),
 ('P','P','Cake','kg','kg','finished_good',true,10,true), ('P2','P2','Cake free','kg','kg','finished_good',true,10,true),
 ('B','B','Biscuit','kg','kg','finished_good',true,10,true),
 ('H','H','Tin','kg','kg','raw_material',true,0,false), ('X2','X2','Glaze','kg','kg','raw_material',true,0,false),
 ('S','S','Salt','kg','kg','raw_material',true,0,false);
select stock_opening(tt.iid('W'), 1, 100, null) is not null as a1 \gset
select stock_opening(tt.iid('A'), 1, 50, 4) is not null as a2 \gset
select item_cost_free_set(tt.iid('W'), true, 'tap water, really free', gen_random_uuid()) is not null as fr \gset
select (recipe_save(null, tt.iid('P'), 10, 'kg', 'x', jsonb_build_array(jsonb_build_object('ingredient_item_id', tt.iid('W'), 'qty', 5, 'unit', 'ltr', 'waste_pct', 0),
        jsonb_build_object('ingredient_item_id', tt.iid('A'), 'qty', 5, 'unit', 'kg', 'waste_pct', 0)), gen_random_uuid())->>'id') as rc \gset
select (recipe_save(null, tt.iid('P2'), 10, 'kg', 'x', jsonb_build_array(jsonb_build_object('ingredient_item_id', tt.iid('W'), 'qty', 5, 'unit', 'ltr', 'waste_pct', 0)), gen_random_uuid())->>'id') as rc2 \gset

\echo == D-4 recipe_cost and the free-cost flag
-- recipe P: water 5 ltr (free, 0) + sugar 5 kg x 4 = 20 for a batch of 10 kg -> unit cost 20 / 10 = 2.000000, complete. Recipe P2: water only -> 0, complete.
select recipe_cost(:'rc'::uuid, 1) as rcj \gset
select recipe_cost(:'rc2'::uuid, 1) as rcj2 \gset
select tt.chk('D4 recipe with a free ingredient: complete = true', (:'rcj'::jsonb->>'complete') = 'true');
select tt.chk('D4 recipe with a free ingredient: unit_cost = (0 + 5 x 4) / 10 = 2', (:'rcj'::jsonb->>'unit_cost')::numeric = 2);
select tt.chk('D4 free-only recipe: complete = true and unit_cost = 0 (a known cost, not NULL)', (:'rcj2'::jsonb->>'complete') = 'true' and (:'rcj2'::jsonb->>'unit_cost')::numeric = 0);
select tt.chk('D4 the free ingredient line shows unit_cost 0 / line_cost 0, not NULL',
  exists (select 1 from jsonb_array_elements(:'rcj2'::jsonb->'lines') l where (l->>'unit_cost') is not null and (l->>'unit_cost')::numeric = 0 and (l->>'line_cost')::numeric = 0));

\echo == D-1 production run whose ingredients are all free-cost items
-- run 2 (P2: water only): ingredient cost 0, no conversion -> nothing to book, and it must NOT wait. run 1 (P: 5 kg sugar x 4 = 20): Dr finished goods 20 / Cr raw 20.
select production_post(1, :'rc2'::uuid, 1, gen_random_uuid())->>'unit_cost' as u2 \gset
select acct_post_pending(false) as pp1 \gset
select tt.chk('D1 free-only run: unit cost 0', :'u2'::numeric = 0);
select tt.chk('D1 free-only run: nothing waits for a cost (waiting = {})', (:'pp1'::jsonb->'waiting') = '{}'::jsonb);
select tt.chk('D1 free-only run: cost_wait_list96 has nothing to ask for', (cost_wait_list96()->>'total')::int = 0);
select production_post(1, :'rc'::uuid, 1, gen_random_uuid())->>'unit_cost' as u1 \gset
select acct_post_pending(false) as pp2 \gset
select tt.chk('D1 mixed run (water free + sugar 5 x 4): unit cost 2 and ONE production entry posted', :'u1'::numeric = 2 and (:'pp2'::jsonb->'by_type'->>'production') = '1');
select tt.chk('D1 mixed run: finished-goods debit = 5 x 4 = 20', tt.gl('inv_finished', 1, 'production') = 20);
-- a free-only run WITH a conversion cost of 25: Dr finished goods 25 / Cr overhead absorbed 25 (dry run only, then put back)
select production_post(1, :'rc2'::uuid, 1, gen_random_uuid())->>'run_id' as r3id \gset
select id as r3 from production_runs order by made_at desc, id desc limit 1 \gset
update production_runs set conversion_cost = 25 where id = :'r3';
select acct_post_pending(true) as prev \gset
select tt.chk('D1 free-only run with conversion 25: it is previewed (not waiting): Dr finished goods 25',
  (:'prev'::jsonb->'waiting') = '{}'::jsonb and exists (select 1 from jsonb_array_elements(:'prev'::jsonb->'preview') e, jsonb_array_elements(e->'lines') l where e->>'source_id' = :'r3' and (l->>'debit')::numeric = 25));
select tt.chk('D1 ... and Cr overhead absorbed 25', exists (select 1 from jsonb_array_elements(:'prev'::jsonb->'preview') e, jsonb_array_elements(e->'lines') l where e->>'source_id' = :'r3' and (l->>'credit')::numeric = 25));
update production_runs set conversion_cost = 0 where id = :'r3';

\echo == D-2 direct production-in without a recipe (place 4)
-- biscuit 3 kg x 80 typed cost = 240; cake 5 kg with NO cost. Switch off (default): cake 5 kg is in the cost-waiting list, biscuit is not (cost known), nothing in the books.
select tt.try(format($$select stock_production_in('%s'::uuid, 4, 3, now(), null, 'manual', gen_random_uuid(), 80)::text$$, tt.iid('B'))) as pi1 \gset
select tt.try(format($$select stock_production_in('%s'::uuid, 4, 5, now(), null, 'manual', gen_random_uuid(), null)::text$$, tt.iid('P'))) as pi2 \gset
select cost_wait_list96(4) as cw4 \gset
select tt.chk('D2 the cake production-in (no recipe, no cost) is in the cost-waiting list: total = 1, move production_in',
  (:'cw4'::jsonb->>'total')::int = 1 and (:'cw4'::jsonb->'items'->0->>'move') = 'production_in' and (:'cw4'::jsonb->'items'->0->>'kind') = 'ledger');
select tt.chk('D2 switch off: the entry would not post yet (gl_post = false)', (:'cw4'::jsonb->'items'->0->>'gl_post') = 'false');
select (:'cw4'::jsonb->'items'->0->>'ref') as pref \gset
select cost_wait_supply96('ledger', :'pref', 'manual', format('[{"item_id":"%s","cost":8}]', tt.iid('P'))::jsonb, 'typed cost', 'cccccccc-0000-0000-0000-0000000000a1'::uuid) is not null as sp1 \gset
select acct_post_pending(false) as pp3 \gset
select tt.chk('D2 after the cost is supplied the list is empty', (cost_wait_list96(4)->>'total')::int = 0);
-- cake 5 x 8 = 40, biscuit 3 x 80 = 240: stock 280 in place 4, books 0 (switch off) -> manual_in = -280 (explained, visible), unexplained 0
select tt.ivg(4, 'inv_finished') as iv4a \gset
select tt.chk('D2 switch off: books unchanged (0) and inventory_vs_gl names the 280 as manual_in, nothing unexplained',
  tt.gl('inv_finished', 4) = 0 and tt.reason(:'iv4a'::jsonb, 'manual_in') = -280 and (:'iv4a'::jsonb->>'unexplained')::numeric = 0);
select set_rule('acct_manual_prod_in103', 'true') is null as sw \gset
select acct_post_pending(false) as pp4 \gset
select acct_post_pending(false) as pp5 \gset
select tt.ivg(4, 'inv_finished') as iv4b \gset
select tt.chk('D2 switch on: ONE entry per row (2 stock_prodin entries), finished goods +280 = 40 + 240', (:'pp4'::jsonb->'by_type'->>'stock_prodin') = '2' and tt.gl('inv_finished', 4, 'stock_prodin') = 280);
select tt.chk('D2 counter side: overhead absorbed credit 280', tt.gl('overhead_absorbed', 4, 'stock_prodin') = -280);
select tt.chk('D2 a second posting run posts nothing new', (:'pp5'::jsonb->>'posted') = '0');
-- (the stock-balance cache keeps the cake at no cost: a cost supplied later is a ledger record only, so valuation = 240 and the 40 difference is the existing reason valuation_basis)
select tt.chk('D2 switch on: inventory_vs_gl gl = ledger value = 280, no manual_in, unexplained 0',
  (:'iv4b'::jsonb->>'gl')::numeric = 280 and (:'iv4b'::jsonb->>'ledger_value')::numeric = 280 and tt.reason(:'iv4b'::jsonb, 'manual_in') = 0 and tt.reason(:'iv4b'::jsonb, 'valuation_basis') = 40 and (:'iv4b'::jsonb->>'unexplained')::numeric = 0);
select tt.chk('D2 no unbalanced journal entry', (select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit) <> sum(credit)) z) = 0);
select set_rule('acct_manual_prod_in103', 'false') is null as sw0 \gset

\echo == D-3 cost supplied later to an opening row after the opening-stock helper (place 2)
-- tin 4 kg x 10 = 40 (costed), glaze 5 kg (no cost). Decision 'difference' books 40. Glaze cost 12 comes later: 5 x 12 = 60. Inventory at place 2 = 40 + 60 = 100.
select stock_opening(tt.iid('H'), 2, 4, 10) is not null as o1 \gset
select stock_opening(tt.iid('X2'), 2, 5, null) is not null as o2 \gset
select tt.try($$select (opening_stock_apply96('difference', 2, null, null, 'first decision', 'bbbbbbbb-0000-0000-0000-0000000000b1'::uuid)->>'amount')$$) as ap1 \gset
select tt.chk('D3 first decision books 4 x 10 = 40', :'ap1' = '40.00' or :'ap1' = '40');
select (select x->>'ref' from jsonb_array_elements(cost_wait_list96(2)->'items') x where x->>'move' = 'opening' limit 1) as cref \gset
select tt.chk('D3 the glaze opening row (no cost) waits in the list', :'cref' is not null and :'cref' <> '');
select cost_wait_supply96('ledger', :'cref', 'manual', format('[{"item_id":"%s","cost":12}]', tt.iid('X2'))::jsonb, 'supplier quote', 'cccccccc-0000-0000-0000-0000000000b2'::uuid) is not null as sp2 \gset
select acct_post_pending(false) as pp6 \gset
select tt.chk('D3 supplying the cost alone books nothing (switch acct_stock_opening stays off): inventory at place 2 still 40', tt.gl('inv_raw', 2) = 40);
select tt.try($$select (opening_stock_apply96('difference', 2, null, null, 'glaze cost supplied later', 'bbbbbbbb-0000-0000-0000-0000000000b3'::uuid)->>'amount')$$) as ap2 \gset
select tt.chk('D3 the follow-up decision books exactly 5 x 12 = 60', :'ap2' = '60.00' or :'ap2' = '60');
select tt.chk('D3 inventory at place 2 = 40 + 60 = 100', tt.gl('inv_raw', 2) = 100);
select tt.chk('D3 a second follow-up has nothing left: already_applied', tt.try($$select opening_stock_apply96('difference', 2, null, null, 'again', 'bbbbbbbb-0000-0000-0000-0000000000b4'::uuid)::text$$) like '%already_applied%');
select tt.chk('D3 the same client id again = dup, nothing booked twice',
  tt.try($$select (opening_stock_apply96('difference', 2, null, null, 'glaze cost supplied later', 'bbbbbbbb-0000-0000-0000-0000000000b3'::uuid)->>'dup')$$) = 'true' and tt.gl('inv_raw', 2) = 100);
select tt.chk('D3 one follow-up record, one decision record, journal keys loc:2 and loc:2:f1',
  (select count(*) from opening_stock_followups103) = 1 and (select count(*) from opening_stock_actions96 where location_id = 2) = 1
  and (select count(*) from journal_entries where source_type = 'opening_stock96' and source_id in ('loc:2', 'loc:2:f1')) = 2);
select set_rule('acct_stock_opening', 'true') is null as so \gset
select acct_post_pending(false) as pp7 \gset
select tt.chk('D3 switch acct_stock_opening ON afterwards: the covered rows are not posted again, inventory at place 2 stays 100', tt.gl('inv_raw', 2) = 100 and tt.gl('inv_raw', 2, 'stock_opening') = 0);
select set_rule('acct_stock_opening', 'false') is null as so0 \gset

\echo == D-5 GRN double count: recommendation and health check
select set_rule('forms_post_to_ledger', 'true') is null as f1 \gset
select set_rule('grn_receipt_source', '"grn"') is null as f2 \gset
select setup_recommendations() as sr \gset
select tt.chk('D5 GRN is the source and the guard was never chosen: purchase_grn_guard is recommended = skip (status recommended)',
  (select x->>'status' from jsonb_array_elements(:'sr'::jsonb->'items') x where x->>'code' = 'purchase_grn_guard') = 'recommended'
  and (select x->>'recommended' from jsonb_array_elements(:'sr'::jsonb->'items') x where x->>'code' = 'purchase_grn_guard') = 'skip');
select tt.chk('D5 health check exists, no problem yet (no GRN stock, no bill stock): level ok',
  (select c->>'level' from jsonb_array_elements(setup_flow_check()->'checks') c where c->>'code' = 'flw_grn_double103') = 'ok');
select setup_recommend_apply('dddddddd-0000-0000-0000-0000000000c1'::uuid, array['purchase_grn_guard']) as sa \gset
select tt.chk('D5 apply sets the guard to skip (one applied row)', (:'sa'::jsonb->>'count') = '1' and rule_txt('purchase_grn_guard') = 'skip');
select set_rule('purchase_grn_guard', '"link"') is null as lk \gset
select setup_recommend_apply('dddddddd-0000-0000-0000-0000000000c2'::uuid, array['purchase_grn_guard']) as sb \gset
select tt.chk('D5 an owner-chosen value (link) is never overwritten: skipped owner_chosen, value stays link',
  (:'sb'::jsonb->>'count') = '0' and rule_txt('purchase_grn_guard') = 'link' and (:'sb'::jsonb->'skipped'->0->>'reason') = 'owner_chosen');
select set_rule('grn_receipt_source', '"purchase"') is null as f3 \gset
select tt.chk('D5 GRN is NOT the source: no recommendation (status owner info / ok as before, recommended null)',
  (select x->'recommended' from jsonb_array_elements(setup_recommendations()->'items') x where x->>'code' = 'purchase_grn_guard') = 'null'::jsonb);
select set_rule('grn_receipt_source', '"grn"') is null as f4 \gset

\echo == D-6 inventory_vs_gl and GRN stock covered by a bill (place 3)
insert into suppliers (name) values ('Sup One');
select set_rule('purchase_grn_guard', '"skip"') is null as g_skip \gset
-- A: GRN 5 kg x 20 + bill 5 x 20 with guard skip: stock 5 (GRN), books 100 (bill): gl 100 = valuation 100, diff 0, no manual_in, unexplained 0
select (save_entry(null, '04-1', 3, tt.today(), format('{"supplier":"Sup One","lines":[{"item":"S","counted":"5","rate":"20","quality":"accept"}]}')::jsonb, '[]'::jsonb)->>'id') as ga \gset
select submit_entry(:'ga'::uuid) is not null as sa1 \gset
select decide_entry(:'ga'::uuid, true, null, null, '[]'::jsonb)->>'status' as da \gset
select (save_purchase(null, null, (select id from suppliers where name = 'Sup One'), 3, 'BA', tt.today(), format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":20}]', tt.iid('S'))::jsonb)->>'id') as ba \gset
select post_purchase(:'ba'::uuid)->>'stock_from_grn' as flag_a \gset
select acct_post_pending(false) as pp8 \gset
select tt.ivg(3, 'inv_raw') as iv3a \gset
select tt.chk('D6 A: GRN approved, bill says stock came from the GRN', :'da' = 'approved' and :'flag_a' = 'true');
select tt.chk('D6 A: gl 100 = valuation 100, diff 0', (:'iv3a'::jsonb->>'gl')::numeric = 100 and (:'iv3a'::jsonb->>'valuation')::numeric = 100 and (:'iv3a'::jsonb->>'diff')::numeric = 0);
select tt.chk('D6 A: the GRN stock is NOT called manual_in any more (0, was -100) and nothing is unexplained (0, was 100)',
  tt.reason(:'iv3a'::jsonb, 'manual_in') = 0 and (:'iv3a'::jsonb->>'unexplained')::numeric = 0);
-- B: guard OFF: GRN 10 x 20 + bill 10 x 20 -> stock +20 kg (500 total), books +200 -> gl 300, valuation 5+20 = 25 kg x 20 = 500, diff -200.
--    manual_in = -(GRN 100 + 200) + covered by the skip bill 100 + duplicate bill stock 200 = 0 -> unexplained = the whole gap -200 (before: manual_in -300, unexplained +100)
select set_rule('purchase_grn_guard', '"off"') is null as g_off \gset
select (save_entry(null, '04-1', 3, tt.today(), format('{"supplier":"Sup One","lines":[{"item":"S","counted":"10","rate":"20","quality":"accept"}]}')::jsonb, '[]'::jsonb)->>'id') as gb \gset
select submit_entry(:'gb'::uuid) is not null as sb1 \gset
select decide_entry(:'gb'::uuid, true, null, null, '[]'::jsonb)->>'status' as db \gset
select (save_purchase(null, null, (select id from suppliers where name = 'Sup One'), 3, 'BB', tt.today(), format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":20}]', tt.iid('S'))::jsonb)->>'id') as bb \gset
select post_purchase(:'bb'::uuid)->>'stock_from_grn' as flag_b \gset
select acct_post_pending(false) as pp9 \gset
select tt.ivg(3, 'inv_raw') as iv3b \gset
select tt.chk('D6 B: guard off double count: stock is 25 kg (5 + 10 + 10)', (select b.qty from stock_balance b where b.item_id = tt.iid('S') and b.location_id = 3) = 25);
select tt.chk('D6 B: gl 300, valuation 500, diff -200', (:'iv3b'::jsonb->>'gl')::numeric = 300 and (:'iv3b'::jsonb->>'valuation')::numeric = 500 and (:'iv3b'::jsonb->>'diff')::numeric = -200);
select tt.chk('D6 B: unexplained = the true gap -200 (the duplicate is not hidden as manual_in)', (:'iv3b'::jsonb->>'unexplained')::numeric = -200 and tt.reason(:'iv3b'::jsonb, 'manual_in') = 0);

\echo == D-5 health check after the double count
-- guard off + GRN source + one bill (BB) that added its own stock after the first GRN row: problems = 1, level warn (never blocks)
select (select c from jsonb_array_elements(setup_flow_check()->'checks') c where c->>'code' = 'flw_grn_double103') as fc \gset
select tt.chk('D5 flow check: level warn, 1 bill adds stock besides the GRN', (:'fc'::jsonb->>'level') = 'warn' and (:'fc'::jsonb->>'problems') = '1');
select tt.chk('D5 the check is counted in setup_flow_check warnings', (setup_flow_check()->>'warnings')::int >= 1);
select set_rule('purchase_grn_guard', '"skip"') is null as g_skip2 \gset
select tt.chk('D5 guard skip: the check is not applicable any more (na)', (select c->>'level' from jsonb_array_elements(setup_flow_check()->'checks') c where c->>'code' = 'flw_grn_double103') = 'na');

\echo == D-7 / D-8 phone numbers in free text and the customer screens
select set_rule('inbox_on', 'true') is null as r1 \gset
select set_rule('meta_intake_on', 'true') is null as r2 \gset
select set_rule('online_orders_on', 'true') is null as r3 \gset
select set_rule('web_form_on', 'true') is null as r4 \gset
select sales_channel_save(null, 'fbpage', 'facebook', null, 'FB page', 1, null, 'PAGE1', true) is not null as c1 \gset
select sales_channel_save(null, 'webform', 'web_form', null, 'Web form', 1, null, null, true) is not null as c2 \gset
select inbound_message_receive('facebook', 'PAGE1', 'm-1', '01711000111', 'Customer A', 'I want 2 kg, call 01711000111 or ০১৭১১০০০২২২ on 2026-10-14, order 1500 taka', now(), null, true) is not null as m1 \gset
select id as mid from inbound_messages where external_id = 'm-1' \gset
select web_order_submit('webform', gen_random_uuid(), 'Web Cust', '01811000001', 'Dhaka 5', 'home', format('[{"item_id":"%s","qty":1,"price":1}]', tt.iid('P'))::jsonb, 'please call 01911000333') is not null as w1 \gset
select id as ooid from online_orders where customer_mobile = '01811000001' limit 1 \gset
select tt.as(:'p');
-- mode off (today's behaviour): the text is shown as typed
select tt.chk('D7 mode off: the text is unchanged', (inbox_get(:mid)->>'text') like '%01711000111%');
select tt.as(:'o'); select set_rule('inbox_pii_mode', '"mask_phone_address"') is null as pm \gset
select tt.as(:'p');
select inbox_get(:mid) as ig \gset
select inbox_list(1, null, 50) as il \gset
-- the 11-digit number keeps its last 3 digits: 8 bullets + 111; the Bangla-digit number 8 bullets + ২২২; the date 2026-10-14 and 1500 are not phone numbers
select tt.chk('D7 mask_phone_address: handle masked as before', (:'ig'::jsonb->>'handle') = '••••••••111');
select tt.chk('D7 the typed number 01711000111 is masked in the text (inbox_get)', (:'ig'::jsonb->>'text') like '%call ••••••••111 or%' and (:'ig'::jsonb->>'text') not like '%01711000111%');
select tt.chk('D7 a number typed with Bangla digits is masked too', (:'ig'::jsonb->>'text') like '%or ••••••••২২২ on%' and (:'ig'::jsonb->>'text') not like '%০১৭১১০০০%');
select tt.chk('D7 a date and an amount are left alone', (:'ig'::jsonb->>'text') like '%on 2026-10-14, order 1500 taka');
select tt.chk('D7 inbox_list masks the text as well', (:'il'::jsonb->0->>'text') like '%call ••••••••111 or%' and (:'il'::jsonb->0->>'text') not like '%01711000111%');
select tt.chk('D7 international and bracketed forms: +8801711000111, 01711-000111, +1 (415) 555-0132 are masked; a 5-digit number and a 7-digit reference are not',
  public._inb_mask_phones103('+8801711000111') = repeat('•', 10) || '111' and public._inb_mask_phones103('call 01711-000111 now') = 'call ' || repeat('•', 8) || '111 now'
  and public._inb_mask_phones103('+1 (415) 555-0132') = repeat('•', 8) || '132' and public._inb_mask_phones103('order 12345 qty 2 ref 1234567 ok') = 'order 12345 qty 2 ref 1234567 ok');
select online_order_get(:'ooid'::uuid) as og \gset
select tt.chk('D7 the order note is masked too (please call ••••••••333) and the mobile as before', (:'og'::jsonb->>'note') = 'please call ••••••••333' and (:'og'::jsonb->>'customer_mobile') = '••••••••001');
select tt.as(:'o'); select set_rule('inbox_pii_mode', '"mask_all_pii"') is null as pm2 \gset
select tt.as(:'p');
select tt.chk('D7 mask_all_pii: the whole text is hidden as before', (inbox_get(:mid)->>'text') = '••••');
select tt.as(:'o'); select set_rule('inbox_pii_mode', '"mask_phone_address"') is null as pm3 \gset
select inbox_unmask('message', :mid::text, 'customer called') as um \gset
select tt.chk('D7 unmask by the owner shows the real text, one log row, one audit row',
  (:'um'::jsonb->'data'->>'text') like '%01711000111%' and (select count(*) from inbox_unmask_log99 where kind = 'message' and ref_id = :mid::text and outcome = 'revealed') = 1
  and (select count(*) from audit_log where table_name = 'inbox_unmask' and record_id = 'message:' || :mid::text) = 1);
select tt.as(:'p');
select tt.chk('D7 the next plain read is masked again', (inbox_get(:mid)->>'text') not like '%01711000111%');
-- D-8 customers
select tt.as(:'o');
select customer_save(null, '{"mobile":"01711000222","name":"Cust Z","address":"Dhaka 5, call 01711000333","note":"phone 01711000444"}'::jsonb, gen_random_uuid()) is not null as cs \gset
select tt.as(:'p');
select (select mobile from customer_directory() where name = 'Cust Z') as dm_p \gset
select (select note from customer_directory() where name = 'Cust Z') as dn_p \gset
select find_customer('01711000222')->>'mobile' as fm_p \gset
select tt.chk('D8 salesperson: customer_directory mobile masked (••••••••222)', :'dm_p' = '••••••••222');
select tt.chk('D8 salesperson: the phone number typed in the customer note is masked', :'dn_p' = 'phone ••••••••444');
select tt.chk('D8 salesperson: find_customer returns the masked mobile, still finds the customer', :'fm_p' = '••••••••222' and (find_customer('01711000222')->>'found') = 'true');
select tt.as(:'v');
select tt.chk('D8 a holder of view_customer_mobile sees the real mobile', (select mobile from customer_directory() where name = 'Cust Z') = '01711000222' and (find_customer('01711000222')->>'mobile') = '01711000222');
select tt.as(:'o');
select tt.chk('D8 the owner sees the real mobile', (select mobile from customer_directory() where name = 'Cust Z') = '01711000222');
select set_rule('inbox_pii_mode', '"off"') is null as pm4 \gset
select tt.as(:'p');
select tt.chk('D8 mode off (default): nothing changes, the salesperson sees the mobile as before', (select mobile from customer_directory() where name = 'Cust Z') = '01711000222' and (find_customer('01711000222')->>'mobile') = '01711000222');
select tt.as(:'o');

\echo == T9 every bos tag is kept, paste twice = no change, guard
select tt.chk('T9 tags kept: _acct_docs carries bos50 bos52 bos72 bos74 bos80 bos85 bos89 bos96 bos97 bos98 + bos103',
  (select bool_and(position(t in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0) from unnest(array['bos50','bos52','bos72','bos74','bos80','bos85','bos89','bos96','bos97','bos98','bos103']) t));
select tt.chk('T9 tags kept: inventory_vs_gl bos85 bos96 bos103, recipe_cost bos73 bos74 bos103, inbox_list bos99 bos103',
  (select bool_and(position(t in pg_get_functiondef('public.inventory_vs_gl(date,integer)'::regprocedure)) > 0) from unnest(array['bos85','bos96','bos103']) t)
  and (select bool_and(position(t in pg_get_functiondef('public.recipe_cost(uuid,integer)'::regprocedure)) > 0) from unnest(array['bos73','bos74','bos103']) t)
  and (select bool_and(position(t in pg_get_functiondef('public.inbox_list(integer,text,integer)'::regprocedure)) > 0) from unnest(array['bos99','bos103']) t));
select md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) as fh0 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%bos103%' \gset
select md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) as fa0 from pg_proc p where p.pronamespace = 'public'::regnamespace \gset
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase132.sql
\i supabase/phase133.sql
\i supabase/phase134.sql
\i supabase/phase135.sql
select md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) as fa1 from pg_proc p where p.pronamespace = 'public'::regnamespace \gset
select tt.chk('T9 paste twice: no function body changes', :'fa0' = :'fa1');
select tt.chk('T9 the switch is OFF by default and the new check row is installed once', (select default_value from rules where key = 'acct_manual_prod_in103') = 'false'::jsonb and (select count(*) from setup_check_defs81 where code = 'flw_grn_double103') = 1);
select tt.chk('T9 the three internal helpers and the follow-up table are closed to the browser',
  not has_function_privilege('authenticated', 'public._inb_mask_phones103(text)', 'execute') and not has_function_privilege('authenticated', 'public._cust_pii103(text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public._rec_value103(text,jsonb)', 'execute') and not has_table_privilege('authenticated', 'public.opening_stock_followups103', 'select'));
-- guard: a database without the phase99 marker is refused and nothing is touched
alter function public._inb_pii_f99(text, text) rename to _inb_pii_f99_hold103;
select md5(pg_get_functiondef('public.recipe_cost(uuid,integer)'::regprocedure)) as rc0 \gset
create or replace function public.recipe_cost(p_recipe uuid, p_loc integer default null) returns jsonb language sql as $$ select '{"held":true}'::jsonb $$;
\i supabase/phase103.sql
\i supabase/phase105.sql
select tt.chk('T9 guard: with the phase99 marker missing the paste raises and re-creates nothing (the held recipe_cost stays)', (recipe_cost(null) ->> 'held') = 'true' and current_setting('phase103.ok') = 'off');
alter function public._inb_pii_f99_hold103(text, text) rename to _inb_pii_f99;
\i supabase/phase103.sql
\i supabase/phase105.sql
select tt.chk('T9 with the markers back it works again: recipe_cost restored to the phase103 body', md5(pg_get_functiondef('public.recipe_cost(uuid,integer)'::regprocedure)) = :'rc0');

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
