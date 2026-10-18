-- Phase 496 tests (XC-3): supplier price board, costliest list, rise alert (switches, blank threshold, same-day duplicates), recipe-cost preview, access.
--   Built on a database through phase496. Run on a fresh copy: psql -d <db> -f supabase/phase496_test.sql
\ir ../tests/sql/xc_head.sql
select set_config('request.jwt.claim.sub', :'o', false);

-- fixtures: two suppliers (test_*), two raw items, purchase bills (posted), one recipe for a test finished item
select set_config('session_replication_role', 'replica', false);
insert into suppliers (name) values ('test_supplier_xc1'), ('test_supplier_xc2');
select id as s1 from suppliers where name = 'test_supplier_xc1' \gset
select id as s2 from suppliers where name = 'test_supplier_xc2' \gset
insert into items (code, name_bn, name_en, unit, base_unit, sell_price, tracked, item_type)
  values ('T552-R', 'test_raw_xc', 'test_raw_xc', 'kg', 'kg', 0, true, 'raw_material'),
         ('T552-Q', 'test_stable_xc', 'test_stable_xc', 'kg', 'kg', 0, true, 'raw_material'),
         ('T552-F', 'test_cake_xc', 'test_cake_xc', 'piece', 'piece', 500, true, 'finished_good');
select id as i_r from items where code = 'T552-R' \gset
select id as i_q from items where code = 'T552-Q' \gset
select id as i_f from items where code = 'T552-F' \gset
-- bills: (supplier, date, item, rate); qty 10 kg each
create temp table bills_fx (sup uuid, d int, it uuid, rate numeric);
insert into bills_fx values (:'s1', -60, :'i_r', 40), (:'s1', -30, :'i_r', 40), (:'s1', -5, :'i_r', 50), (:'s2', -10, :'i_r', 45),
                            (:'s1', -20, :'i_q', 10), (:'s1', -2, :'i_q', 10);
do $b$
declare r record; bid uuid;
begin
  for r in select * from bills_fx loop
    insert into purchase_bills (kind, supplier_id, bill_date, location_id, status, subtotal, total, paid, created_by, posted_at)
      values ('bill', r.sup, (now() at time zone 'Asia/Dhaka')::date + r.d, 1, 'posted', r.rate * 10, r.rate * 10, r.rate * 10, (select id from auth.users where email = 'test_owner_xc@s.app'), now())
      returning id into bid;
    insert into purchase_lines (bill_id, line_no, item_id, description, qty, unit, unit_cost, amount, base_qty, unit_cost_base)
      values (bid, 1, r.it, 'test_line', 10, 'kg', r.rate, r.rate * 10, 10, r.rate);
  end loop;
end $b$;
insert into recipes (item_id, version, yield_qty, yield_unit, active, created_by) values (:'i_f', 1, 10, 'piece', true, :'o');
select id as rc from recipes where item_id = :'i_f' \gset
insert into recipe_lines (recipe_id, ingredient_item_id, qty, unit, sort, active) values (:'rc', :'i_r', 2, 'kg', 1, true);
select set_config('session_replication_role', 'origin', false);

-- T1 defaults: the alert is OFF and the threshold is blank
select tt.chk('T1 the price alert is OFF by default and its threshold is blank', not public.rule_on('xc_price_alert_on') and public.rule_num('xc_price_rise_pct') is null);

-- T2 the board (owner)
select xc_price_board(50) as b \gset
select tt.chk('T2 test_raw_xc: last rate 50 from the supplier of the last bill', (select (x ->> 'last_rate')::numeric = 50 and x ->> 'last_supplier' = 'test_supplier_xc1' from jsonb_array_elements(:'b'::jsonb -> 'items') x where x ->> 'item_code' = 'T552-R'));
select tt.chk('T2 the cheapest supplier is xc2 at 45 (xc1 last 50)', (select x ->> 'cheapest_supplier' = 'test_supplier_xc2' and (x ->> 'cheapest_rate')::numeric = 45 from jsonb_array_elements(:'b'::jsonb -> 'items') x where x ->> 'item_code' = 'T552-R'));
select tt.chk('T2 the 90-day trend is +25% (40 to 50)', (select (x ->> 'trend_90d_pct')::numeric = 25 from jsonb_array_elements(:'b'::jsonb -> 'items') x where x ->> 'item_code' = 'T552-R'));
select tt.chk('T2 spend in 90 days: 400 + 400 + 500 + 450 = 1750', (select (x ->> 'spend_90d')::numeric = 1750 from jsonb_array_elements(:'b'::jsonb -> 'items') x where x ->> 'item_code' = 'T552-R'));
select tt.chk('T2 the costliest list starts with the highest last rate (test_raw_xc)', (:'b'::jsonb -> 'costliest_by_last_rate' -> 0 ->> 'item_name') = 'test_raw_xc');
select tt.chk('T2 the board points to the existing purchase-rate report instead of repeating it', (select x ->> 'see' from jsonb_array_elements(:'b'::jsonb -> 'items') x where x ->> 'item_code' = 'T552-R') = '#/report/p2_rate_trend');

-- T3 access: staff cannot read costs
select tt.as(:'st');
select tt.err('T3 a staff user cannot read the price board', 'select xc_price_board(10)', 'not allowed');
select tt.err('T3 a staff user cannot run the alert scan', 'select xc_price_alert_scan(true)', 'not allowed');
select tt.err('T3 a staff user cannot preview a recipe price', format($$select xc_recipe_price_preview('%s', '%s', 60)$$, :'rc', :'i_r'), 'not allowed');
select tt.as(:'o');

-- T4 the alert: off, blank, then on (dry run first, then one warning, then no duplicate the same day)
select tt.chk('T4 the scan is skipped while the switch is off', (xc_price_alert_scan(true) ->> 'skipped') = 'switch_off');
select set_config('session_replication_role', 'replica', false);
update rules set value = 'true'::jsonb where key = 'xc_price_alert_on';
select set_config('session_replication_role', 'origin', false);
select tt.chk('T4 with the threshold blank the scan says so and writes nothing', (xc_price_alert_scan(false) ->> 'skipped') = 'threshold_not_set');
select set_config('session_replication_role', 'replica', false);
update rules set value = '20'::jsonb where key = 'xc_price_rise_pct';
select set_config('session_replication_role', 'origin', false);
select tt.chk('T4 a dry run finds one rise (test_raw_xc +25% against the same supplier; test_stable_xc 0%)', (xc_price_alert_scan(true) ->> 'alerts')::int = 1);
select tt.chk('T4 a dry run writes no warning', not exists (select 1 from notifications where kind = 'price_rise'));
select xc_price_alert_scan(false) ->> 'alerts' as a1 \gset
select tt.chk('T4 the real run writes one warning', :'a1' = '1' and (select count(*) from notifications where kind = 'price_rise') = 1);
select xc_price_alert_scan(false) ->> 'alerts' as a2 \gset
select tt.chk('T4 the same day again writes no duplicate', :'a2' = '1' and (select count(*) from notifications where kind = 'price_rise') = 1);
select tt.chk('T4 the warning names the item and says how much it rose', exists (select 1 from notifications where kind = 'price_rise' and title_en like '%test_raw_xc%' and body_en like '%25%'));

-- T5 recipe-cost preview: 2 kg per batch; last rate 50 to 60 = +20 per batch, +2 per piece (yield 10)
select xc_recipe_price_preview(:'rc'::uuid, :'i_r'::uuid, 60) as p \gset
select tt.chk('T5 the ingredient is found and needs 2 kg per batch', (:'p'::jsonb ->> 'ingredient_in_recipe')::boolean = true and (:'p'::jsonb ->> 'need_base_per_batch')::numeric = 2);
select tt.chk('T5 the batch change is +20 and the unit change is +2 (yield 10)', (:'p'::jsonb ->> 'batch_change')::numeric = 20 and (:'p'::jsonb ->> 'unit_change')::numeric = 2);
select tt.chk('T5 the preview says nothing is saved', (:'p'::jsonb ->> 'note') like 'Preview only%');
select xc_recipe_price_preview(:'rc'::uuid, :'i_q'::uuid, 60) as p2 \gset
select tt.chk('T5 an item that is not in the recipe is reported as not in it', (:'p2'::jsonb ->> 'ingredient_in_recipe')::boolean = false);
select tt.err('T5 a negative price is refused', format($$select xc_recipe_price_preview('%s', '%s', -1)$$, :'rc', :'i_r'), 'bad_value');

-- T6 the settings are paste-safe
select tt.chk('T6 the two price settings exist once each', (select count(*) from rules where key in ('xc_price_alert_on', 'xc_price_rise_pct')) = 2);

select tt.summary();
