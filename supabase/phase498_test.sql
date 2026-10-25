-- Phase 498 tests (XC-5): staff coaching board - owner only, switch OFF by default, no ranking, blanks are blanks, access.
--   Built on a database through phase498. Run on a fresh copy: psql -d <db> -f supabase/phase498_test.sql
\ir ../tests/sql/xc_head.sql
select set_config('request.jwt.claim.sub', :'o', false);

-- fixtures (replica role: the sale triggers do not run)
select set_config('session_replication_role', 'replica', false);
update profiles set staff_id = 'test_staff_xc', full_name = 'test_staff_full' where id = :'st';
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, total, discount, pay_mode, created_by, created_staff, status)
  values (1, 1301, tt.today(), now(), '[]', 300, 300, 0, 'cash', :'st', 'test_staff_xc', 'done'),
         (1, 1302, tt.today(), now(), '[]', 200, 180, 20, 'cash', :'st', 'test_staff_xc', 'done'),
         (1, 1303, tt.today(), now(), '[]', 100, 100, 0, 'cash', :'st', 'test_staff_xc', 'void');
update sales set void_staff = 'test_staff_xc', void_at = now() where receipt = 1303 and location_id = 1;
select set_config('session_replication_role', 'origin', false);

-- T1 default OFF
select tt.chk('T1 the board is OFF by default', not public.rule_on('xc_coaching_on'));
select tt.chk('T1 the owner sees "skipped" while OFF', (xc_staff_board(null, null, null) ->> 'skipped') = 'switch_off');

-- switch on (test only)
select set_config('session_replication_role', 'replica', false);
update rules set value = 'true'::jsonb where key = 'xc_coaching_on';
select set_config('session_replication_role', 'origin', false);

-- T2 the owner sees the figures per person
select xc_staff_board(tt.today(), tt.today(), 1) as b \gset
select tt.chk('T2 the person shows the name from the profile', (select r ->> 'name' = 'test_staff_full' from jsonb_array_elements(:'b'::jsonb -> 'rows') r where r ->> 'staff_id' = 'test_staff_xc'));
select tt.chk('T2 two bills, one with a discount (50% of bills), one void', (select (r ->> 'sales_bills')::int = 2 and (r ->> 'discount_bills')::int = 1 and (r ->> 'discount_share_pct')::numeric = 50 and (r ->> 'voids')::int = 1 from jsonb_array_elements(:'b'::jsonb -> 'rows') r where r ->> 'staff_id' = 'test_staff_xc'));
select tt.chk('T2 the sales amount is 480 (300 + 180) and the discount 20', (select (r ->> 'sales_amount')::numeric = 480 and (r ->> 'discount_amount')::numeric = 20 from jsonb_array_elements(:'b'::jsonb -> 'rows') r where r ->> 'staff_id' = 'test_staff_xc'));

-- T3 blanks are blanks, not zeros (no shortage case, no attendance, no production for this person)
select tt.chk('T3 cash shortage, attendance and production are blank (null), not 0', (select r ->> 'cash_shortage_cases' is null and r ->> 'attendance_days' is null and r ->> 'production_yield' is null from jsonb_array_elements(:'b'::jsonb -> 'rows') r where r ->> 'staff_id' = 'test_staff_xc'));

-- T4 no ranking, owner only
select tt.chk('T4 the board has no rank or score field and says it is owner only', (:'b'::jsonb ->> 'owner_only')::boolean = true and not (:'b'::jsonb::text like '%"rank"%') and not (:'b'::jsonb::text like '%"score"%'));

-- T5 access: staff cannot read it, even with the switch on
select tt.as(:'st');
select tt.err('T5 a staff user cannot read the coaching board', 'select xc_staff_board(null, null, null)', 'not allowed');
select tt.as(:'o');
select tt.err('T5 a bad range is refused', $$select xc_staff_board('2020-01-01', '2026-01-01', null)$$, 'bad_range');

-- T6 settings paste-safe
select tt.chk('T6 the coaching setting exists once', (select count(*) from rules where key = 'xc_coaching_on') = 1);

select tt.summary();
