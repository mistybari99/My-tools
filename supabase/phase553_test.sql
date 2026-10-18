-- Phase 553 tests (XC-4): unsold list (expiry cut-off, no-expiry units apart), markdown price, outcomes (no stock movement), void, report with the wastage share, access.
--   Built on a database through phase553. Run on a fresh copy: psql -d <db> -f supabase/phase553_test.sql
\ir ../tests/sql/xc_head.sql
select set_config('request.jwt.claim.sub', :'o', false);

-- fixtures (replica role: the stock and sale triggers do not run; the code under test runs as normal)
select set_config('session_replication_role', 'replica', false);
insert into items (code, name_bn, name_en, unit, base_unit, sell_price, tracked, item_type)
  values ('T553-F', 'test_cake_unsold', 'test_cake_unsold', 'piece', 'piece', 100, true, 'finished_good');
select id as i_f from items where code = 'T553-F' \gset
insert into stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, note)
  values (:'i_f', 1, now() - interval '1 day', 5, 5, now() + interval '12 hours', 'test_batch_soon'),
         (:'i_f', 1, now() - interval '1 day', 4, 4, now() + interval '3 days', 'test_batch_later'),
         (:'i_f', 1, now() - interval '1 day', 2, 2, null, 'test_batch_no_expiry');
insert into stock_balance (item_id, location_id, qty, avg_cost) values (:'i_f', 1, 11, 20);
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, total, pay_mode, created_by, status)
  values (1, 1201, (now() at time zone 'Asia/Dhaka')::date, now(), jsonb_build_array(jsonb_build_object('name', 'test_cake_unsold', 'qty', 9, 'amount', 900, 'item_id', :'i_f')), 900, 900, 'cash', :'o', 'done');
insert into stock_wastage (item_id, location_id, qty, reason_code, note, made_at)
  values (:'i_f', 1, 1, 'test_reason', 'test_waste', now());
select set_config('session_replication_role', 'origin', false);

-- T1 defaults: OFF, blank markdown
select tt.chk('T1 the unsold list is OFF and the markdown % is blank by default', not public.rule_on('xc_unsold_on') and public.rule_num('xc_markdown_pct') is null);
select tt.chk('T1 the list says it is skipped while OFF', (xc_unsold_candidates(null, 1) ->> 'skipped') = 'switch_off');
select tt.err('T1 a record while OFF is refused', format($$select xc_unsold_record(null, 1, '%s', null, 1, 'staff_meal', null, null)$$, :'i_f'), 'switch_off');

-- switch on, markdown still blank
select set_config('session_replication_role', 'replica', false);
update rules set value = 'true'::jsonb where key = 'xc_unsold_on';
select set_config('session_replication_role', 'origin', false);

-- T2 blank markdown: the list asks for it and a markdown sale is refused
select xc_unsold_candidates(null, 1) as c2 \gset
select tt.chk('T2 with the markdown % blank the list says "data needed: xc_markdown_pct" and suggests no price', (:'c2'::jsonb -> 'data_needed') ? 'xc_markdown_pct' and (select (r ->> 'markdown_price') is null from jsonb_array_elements(:'c2'::jsonb -> 'rows') r limit 1));
select tt.err('T2 a markdown sale without a % is refused', format($$select xc_unsold_record(null, 1, '%s', %L, 1, 'sold_discount', null, null)$$, :'i_f', tt.today()), 'markdown_pct_not_set');

-- T3 markdown 30%: only the 5 units that expire before the end of tomorrow are at risk; the 2 units with no expiry are counted apart
select set_config('session_replication_role', 'replica', false);
update rules set value = '30'::jsonb where key = 'xc_markdown_pct';
select set_config('session_replication_role', 'origin', false);
select xc_unsold_candidates(null, 1) as c3 \gset
select tt.chk('T3 5 units at risk, markdown price 70, value at markdown 350', (select (r ->> 'qty_at_risk')::numeric = 5 and (r ->> 'markdown_price')::numeric = 70 and (r ->> 'value_at_markdown')::numeric = 350 from jsonb_array_elements(:'c3'::jsonb -> 'rows') r limit 1));
select tt.chk('T3 the batch that expires in 3 days is NOT in the list', (select count(*) from jsonb_array_elements(:'c3'::jsonb -> 'rows') r) = 1);
select tt.chk('T3 the 2 units with no expiry are counted apart (not treated as safe or expiring)', (:'c3'::jsonb -> 'no_expiry_captured' ->> 'units')::numeric = 2);

-- T4 a markdown sale: 3 units at 70 = 210 (the value is computed on the server)
select xc_unsold_record('00000000-0000-0000-0000-00000000c001'::uuid, 1, :'i_f'::uuid, tt.today(), 3, 'sold_discount', null, 'test_sale') as r4 \gset
select tt.chk('T4 the sale of 3 at the markdown is 210, and the answer says stock is not moved', (:'r4'::jsonb ->> 'value')::numeric = 210 and (:'r4'::jsonb ->> 'duplicate')::boolean = false and (:'r4'::jsonb ->> 'note') like 'Stock is not moved%');
select xc_unsold_record('00000000-0000-0000-0000-00000000c001'::uuid, 1, :'i_f'::uuid, tt.today(), 3, 'sold_discount', null, 'test_sale') as r4b \gset
select tt.chk('T4 the same client id is a duplicate: no second line', (:'r4b'::jsonb ->> 'duplicate')::boolean = true and (select count(*) from xc_unsold_outcomes where client_id = '00000000-0000-0000-0000-00000000c001') = 1);
select xc_unsold_record(null, 1, :'i_f'::uuid, tt.today(), 2, 'waste', null, null) as r5 \gset
select tt.chk('T5 a waste line has no value (blank, not 0) and says to book the wastage screen', (select value is null from xc_unsold_outcomes where id = (:'r5'::jsonb ->> 'id')::bigint) and (:'r5'::jsonb ->> 'note') like '%wastage screen%');
select xc_unsold_record(null, 1, :'i_f'::uuid, tt.today(), 1, 'staff_meal', null, null) as r6 \gset

-- T6 bad input
select tt.err('T6 an unknown outcome is refused', format($$select xc_unsold_record(null, 1, '%s', null, 1, 'trash', null, null)$$, :'i_f'), 'bad_outcome');
select tt.err('T6 a zero quantity is refused', format($$select xc_unsold_record(null, 1, '%s', null, 0, 'waste', null, null)$$, :'i_f'), 'bad_value');
select tt.err('T6 a discount above 90% is refused', format($$select xc_unsold_record(null, 1, '%s', %L, 1, 'sold_discount', 95, null)$$, :'i_f', tt.today()), 'bad_discount');
select tt.err('T6 a date far in the past is refused', format($$select xc_unsold_record(null, 1, '%s', '2020-01-01', 1, 'waste', null, null)$$, :'i_f'), 'bad_date');

-- T7 void (never delete): with a reason; without one, refused
select tt.err('T7 a void without a reason is refused', format($$select xc_unsold_void(%s, ' ')$$, (:'r6'::jsonb ->> 'id')::bigint), 'reason_required');
select xc_unsold_void((:'r6'::jsonb ->> 'id')::bigint, 'test_void_reason') ->> 'ok' as v1 \gset
select tt.chk('T7 the staff meal line is voided and kept', :'v1' = 'true' and (select state from xc_unsold_outcomes where id = (:'r6'::jsonb ->> 'id')::bigint) = 'void');
select tt.err('T7 an outcome line cannot be deleted', 'delete from xc_unsold_outcomes', 'nothing is deleted');

-- T8 the report (owner): sold 9, wasted 1, share 1 / (9 + 1) = 10.0%, denominator shown; markdown 3 sold for 210; the voided staff meal is not counted
select xc_unsold_report(tt.today() - 2, tt.today(), 1) as rp \gset
select tt.chk('T8 wastage share is 10.0% with the denominator 10 (sold 9 + wasted 1)', (select (r ->> 'wastage_share_pct')::numeric = 10 and (r ->> 'share_denominator')::numeric = 10 from jsonb_array_elements(:'rp'::jsonb -> 'rows') r where r ->> 'item_code' = 'T553-F'));
select tt.chk('T8 the markdown sales are 3 units worth 210', (select (r ->> 'markdown_sold_qty')::numeric = 3 and (r ->> 'markdown_value')::numeric = 210 from jsonb_array_elements(:'rp'::jsonb -> 'rows') r where r ->> 'item_code' = 'T553-F'));
select tt.chk('T8 the voided staff meal is not counted (blank, not 0)', (select r ->> 'staff_meal_qty' is null from jsonb_array_elements(:'rp'::jsonb -> 'rows') r where r ->> 'item_code' = 'T553-F'));
select tt.chk('T8 the waste value uses the current average cost (1 x 20), shown to the owner', (select (r ->> 'wastage_value_at_current_avg_cost')::numeric = 20 from jsonb_array_elements(:'rp'::jsonb -> 'rows') r where r ->> 'item_code' = 'T553-F'));
select tt.chk('T8 the weekly trend has the wastage share with its own sold and wasted figures', jsonb_array_length(:'rp'::jsonb -> 'weekly_share') >= 1 and (:'rp'::jsonb -> 'weekly_share' -> 0 ? 'share_pct'));

-- T9 access
select tt.as(:'st');
select tt.err('T9 a staff user without a grant cannot see the list', format($$select xc_unsold_candidates(%L, 1)$$, tt.today()), 'not allowed');
select tt.err('T9 a staff user cannot record an outcome', format($$select xc_unsold_record(null, 1, '%s', null, 1, 'waste', null, null)$$, :'i_f'), 'not allowed');
select tt.err('T9 a staff user cannot read the report', 'select xc_unsold_report(null, null, null)', 'not allowed');
select tt.as(:'o');

-- T10 settings paste-safe
select tt.chk('T10 the two unsold settings exist once each', (select count(*) from rules where key in ('xc_unsold_on', 'xc_markdown_pct')) = 2);

select tt.summary();
