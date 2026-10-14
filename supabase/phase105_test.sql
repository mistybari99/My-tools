-- FRESH DB ONLY. Phase 105 tests (Step Sec2: the findings of the second security review; see docs/briefs_p2p3/step_Sec2_REPORT.md).
--   Build: bash tests/sql/final_build.sh <db> "<canonical order ... phase101 phase102 phase103>"   (phase105 is NOT pasted by the build of this test: the file below pastes it)
--   Run from the REPO ROOT:  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase105_test.sql | grep -E "FAIL|RESULT"
--   FAILING-BEFORE: every block is written so that the OLD behaviour is a FAIL, not an abort: the first run of this file on a build WITHOUT phase105 fails the blocks marked (F);
--   the file pastes phase105.sql in the middle (block "P"), after the "before" values have been recorded. PASSING-AFTER: 0 fail.
--   Every expected number is computed by hand in the comment of its block. Test data only, no real names.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set e '00000000-0000-0000-0000-000000000002'
\set u '00000000-0000-0000-0000-000000000003'
\set b '00000000-0000-0000-0000-000000000004'
\set p '00000000-0000-0000-0000-000000000005'
\set v '00000000-0000-0000-0000-000000000006'
\set q '00000000-0000-0000-0000-000000000007'
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
create or replace function tt.mo(p int) returns date language sql stable as $$ select (date_trunc('month', now() at time zone 'Asia/Dhaka') - make_interval(months => p))::date $$;
-- run a statement, return its single value as text, or ERR:<message>
create or replace function tt.try(p_sql text) returns text language plpgsql as $$
declare r text;
begin execute p_sql into r; return r;
exception when others then return 'ERR:' || sqlerrm; end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'e','entry2@s.app','{"full_name":"Entry"}'), (:'u','buyer3@s.app','{"full_name":"Buyer"}'), (:'b','buyer4@s.app','{"full_name":"Buyer no pay"}'),
 (:'p','sales5@s.app','{"full_name":"Seller"}'), (:'v','sales6@s.app','{"full_name":"Phone viewer"}'), (:'q','sales7@s.app','{"full_name":"Revealer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'e','storekeeper'),(:'u','storekeeper'),(:'b','storekeeper'),(:'p','salesperson'),(:'v','salesperson'),(:'q','salesperson') on conflict do nothing;
insert into user_locations values (:'e',1),(:'e',5),(:'u',1),(:'b',1),(:'p',1),(:'v',1),(:'q',1) on conflict do nothing;
select tt.as(:'o');
select set_user_grant(:'e'::uuid,'view_cost') is null as g1 \gset
select set_user_grant(:'e'::uuid,'cost_bill_entry') is null as g2 \gset
select set_user_grant(:'u'::uuid,'purchase_entry') is null as g3 \gset
select set_user_grant(:'u'::uuid,'supplier_pay') is null as g4 \gset
select set_user_grant(:'b'::uuid,'purchase_entry') is null as g5 \gset
select set_user_grant(:'v'::uuid,'view_customer_mobile') is null as g6 \gset
select set_user_grant(:'q'::uuid,'inbox_unmask') is null as g7 \gset
select set_user_grant(:'p'::uuid,'view_daybook') is null as g8 \gset
insert into rule_grants (role_code, grant_code, allowed) values ('salesperson','inbox_contact_view',true) on conflict (role_code, grant_code) do update set allowed=true;
with s as (insert into suppliers (name, credit_days) values ('Cash supplier', null) returning id) select id as sup1 from s \gset
with s as (insert into suppliers (name, credit_days) values ('Keep supplier', null) returning id) select id as sup2 from s \gset
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('O1','O1','O1','kg','kg','raw_material',true,0) on conflict do nothing;
select id as it1 from items where code='O1' \gset
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
select tt.as(:'e');
select cost_source_save(null,'gas','meter G-1','separate','factory',array[1],'monthly',tt.mo(3)) ->> 'id' as sg \gset
select tt.as(:'o');

-- ======== BEFORE phase105: record what the old code does (these values are compared below) ========
select (select count(*) from pg_proc where proname = '_bp_auto_ok105') = 0 as fresh \gset
select tt.chk('P0 (info) fresh build = phase105 not pasted yet: the "before" probes below are real; on a chain that already has it this block pastes it a second time', true);

-- customers: C = 'Cust Z', due 700 (a credit sale), advance 1000, whatsapp / address / note carry numbers
select customer_save(null, '{"mobile":"01711000222","name":"Cust Z","address":"Dhaka 5, call 01711000333","note":"phone 01711000444","whatsapp":"01711000555"}'::jsonb, gen_random_uuid())->>'id' as cu \gset
insert into sales (location_id, receipt, subtotal, total, pay_mode, created_by, customer_id) values (1, 90001, 700, 700, 'cash', :'o'::uuid, :'cu'::uuid);
select cash_move_add(1,'cust_advance',1000,null,'cash',:'cu'::uuid) is not null as adv \gset

-- M6 before: the old pattern misses dotted / slashed / underscored / NBSP / tab numbers
select public._inb_mask_phones103('call 01711.111.111 now') as m6_old1, public._inb_mask_phones103('x 01711/222333 y') as m6_old2 \gset

-- M1 / L5 / M2 / M3 / L3 / L4 "before" probes
select md5('bos99auto:cost:1')::uuid = public._bp_uuid99('cost','1') as l3_old \gset

\echo == P: paste phase105 (the fixes)
\i supabase/phase105.sql

\echo == T0 shape, defaults, tags
select tt.chk('T0 phase105 applied: helper, salt table and the opt-in switch exist', to_regprocedure('public._bp_auto_ok105(text,text,integer)') is not null and to_regclass('public.bos_salt105') is not null and exists (select 1 from rules where key = 'customers_pii_guard_on'));
select tt.chk('T0 the new switch is OFF by default (=today), kind switch; inbox_pii_mode still off', (select default_value from rules where key = 'customers_pii_guard_on') = 'false'::jsonb and not rule_on('customers_pii_guard_on') and rule_txt('inbox_pii_mode') = 'off');
select tt.chk('T0 the helper and the salt table are closed to the browser', not has_function_privilege('authenticated', 'public._bp_auto_ok105(text,text,integer)', 'execute') and not has_function_privilege('anon', 'public._bp_auto_ok105(text,text,integer)', 'execute')
  and not has_table_privilege('authenticated', 'public.bos_salt105', 'select') and not has_function_privilege('authenticated', 'public._bp_uuid99(text,text)', 'execute'));
select tt.chk('T0 tags kept: customer_directory bos103 + the marker sec2-L6 (no bos105, so phase103 can still be re-pasted), _bp_uuid99 keeps its own text, every other re-created function carries bos105',
  position('bos103' in pg_get_functiondef('public.customer_directory(integer)'::regprocedure)) > 0 and position('sec2-L6' in pg_get_functiondef('public.customer_directory(integer)'::regprocedure)) > 0
  and position('bos105' in pg_get_functiondef('public.customer_directory(integer)'::regprocedure)) = 0
  and (select bool_and(position('bos105' in pg_get_functiondef(f::regprocedure)) > 0) from unnest(array['public._bp_auto99(text,text,integer,text,text,text,integer,text)','public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)','public._bp_sp_void99()',
      'public.inbox_unmask(text,text,text)','public._inb_mask_phones103(text)','public._cust_pii103(text,text)','public.customer_dues()','public.customer_advances()','public.customer_profile(uuid)','public.customer_save(uuid,jsonb,uuid)','public._inb_pii_cols76()']) f));

\echo == H1 customer phone / address bypass paths follow inbox_pii_mode (hand numbers: 01711000222 -> 8 dots + 222; due 700; advance 1000)
select tt.as(:'p');
select tt.chk('H1 mode off (default) = today: salesperson sees dues / advances / profile exactly as before',
  (select mobile from customer_dues() where id = :'cu'::uuid) = '01711000222' and (select mobile from customer_advances() where customer_id = :'cu'::uuid) = '01711000222'
  and customer_profile(:'cu'::uuid)->'customer'->>'mobile' = '01711000222' and customer_profile(:'cu'::uuid)->'customer'->>'address' = 'Dhaka 5, call 01711000333'
  and customer_profile(:'cu'::uuid)->'customer'->>'note' = 'phone 01711000444' and customer_profile(:'cu'::uuid)->'customer'->>'whatsapp' = '01711000555');
select tt.as(:'o'); select set_rule('inbox_pii_mode', '"mask_phone"') is null as pm1 \gset
select tt.as(:'p');
select tt.chk('H1 (F) mask_phone: customer_dues mobile masked (••••••••222), the balance is untouched (700)', (select mobile from customer_dues() where id = :'cu'::uuid) = '••••••••222' and (select balance from customer_dues() where id = :'cu'::uuid) = 700);
select tt.chk('H1 (F) mask_phone: customer_advances mobile masked, balance 1000', (select mobile from customer_advances() where customer_id = :'cu'::uuid) = '••••••••222' and (select balance from customer_advances() where customer_id = :'cu'::uuid) = 1000);
select tt.chk('H1 (F) mask_phone: customer_profile mobile + whatsapp masked, a number typed in address / note masked',
  customer_profile(:'cu'::uuid)->'customer'->>'mobile' = '••••••••222' and customer_profile(:'cu'::uuid)->'customer'->>'whatsapp' = '••••••••555'
  and customer_profile(:'cu'::uuid)->'customer'->>'address' = 'Dhaka 5, call ••••••••333' and customer_profile(:'cu'::uuid)->'customer'->>'note' = 'phone ••••••••444');
select tt.chk('H1 the profile keeps its numbers: orders / spend / balance are not masked (balance 700)', (customer_profile(:'cu'::uuid)->>'balance')::numeric = 700);
select tt.as(:'v');
select tt.chk('H1 a holder of view_customer_mobile sees the real values on all three paths', (select mobile from customer_dues() where id = :'cu'::uuid) = '01711000222' and customer_profile(:'cu'::uuid)->'customer'->>'mobile' = '01711000222'
  and customer_profile(:'cu'::uuid)->'customer'->>'note' = 'phone 01711000444');
select tt.as(:'o');
select tt.chk('H1 the owner sees the real values on all three paths', (select mobile from customer_dues() where id = :'cu'::uuid) = '01711000222' and (select mobile from customer_advances() where customer_id = :'cu'::uuid) = '01711000222'
  and customer_profile(:'cu'::uuid)->'customer'->>'address' = 'Dhaka 5, call 01711000333');
select set_rule('inbox_pii_mode', '"mask_phone_address"') is null as pm2 \gset
select tt.as(:'p');
select tt.chk('H1 mask_phone_address: the profile address is fully hidden (••••)', customer_profile(:'cu'::uuid)->'customer'->>'address' = '••••');
select tt.as(:'o'); select set_rule('inbox_pii_mode', '"mask_all_pii"') is null as pm3 \gset
select tt.as(:'p');
select tt.chk('H1 (F) L6 mask_all_pii: customer_directory name -> first letter + three dots (C•••); the owner sees Cust Z', (select name from customer_directory() where id = :'cu'::uuid) = 'C•••');
select tt.chk('H1 mask_all_pii: the debtor name in customer_dues stays (collecting needs it), the mobile is masked', (select name from customer_dues() where id = :'cu'::uuid) = 'Cust Z' and (select mobile from customer_dues() where id = :'cu'::uuid) = '••••••••222');
select tt.try(format($$select customer_save(%L::uuid, '{"name":"C•••","address":"••••","note":"edited"}'::jsonb, gen_random_uuid()) is not null$$, :'cu')) as sv1 \gset
select tt.try(format($$select customer_save(%L::uuid, '{"whatsapp":"••••••••555"}'::jsonb, gen_random_uuid()) is not null$$, :'cu')) as sv2 \gset
select tt.chk('H1 (F) a masked screen value is never saved over the real one: save name C••• + address •••• + note "edited" -> only the note changes; a masked whatsapp is ignored, not an error',
  :'sv1' = 'true' and :'sv2' = 'true' and (select name from customers where id = :'cu'::uuid) = 'Cust Z' and (select address from customers where id = :'cu'::uuid) = 'Dhaka 5, call 01711000333' and (select note from customers where id = :'cu'::uuid) = 'edited'
  and (select whatsapp from customers where id = :'cu'::uuid) = '01711000555');
select tt.as(:'o');
select tt.chk('H1 mask_all_pii: the owner still sees the name in the directory', (select name from customer_directory() where id = :'cu'::uuid) = 'Cust Z');
select set_rule('inbox_pii_mode', '"off"') is null as pm0 \gset
select tt.as(:'p');
select tt.chk('H1 mode off again: nothing is masked on any path', (select mobile from customer_dues() where id = :'cu'::uuid) = '01711000222' and (select name from customer_directory() where id = :'cu'::uuid) = 'Cust Z');
select tt.as(:'o');

\echo == H1 direct table columns follow the guard switches (browser role); both OFF by default
select tt.chk('H1 default: every column readable as today', has_column_privilege('authenticated', 'public.online_orders', 'note', 'select') and has_column_privilege('authenticated', 'public.online_orders', 'lines', 'select')
  and has_column_privilege('authenticated', 'public.customers', 'mobile', 'select') and has_column_privilege('authenticated', 'public.customers', 'note', 'select'));
select set_rule('inbox_pii_guard_on', 'true') is null as gon \gset
select tt.chk('H1 (F) inbox_pii_guard_on: online_orders customer_mobile, address AND note, draft_note, lines are closed; id and status stay readable',
  not has_column_privilege('authenticated', 'public.online_orders', 'customer_mobile', 'select') and not has_column_privilege('authenticated', 'public.online_orders', 'address', 'select')
  and not has_column_privilege('authenticated', 'public.online_orders', 'note', 'select') and not has_column_privilege('authenticated', 'public.online_orders', 'draft_note', 'select')
  and not has_column_privilege('authenticated', 'public.online_orders', 'lines', 'select') and has_column_privilege('authenticated', 'public.online_orders', 'id', 'select') and has_column_privilege('authenticated', 'public.online_orders', 'status', 'select'));
select set_rule('inbox_pii_guard_on', 'false') is null as goff \gset
select tt.chk('H1 guard off again: all five columns are granted back', has_column_privilege('authenticated', 'public.online_orders', 'note', 'select') and has_column_privilege('authenticated', 'public.online_orders', 'lines', 'select')
  and has_column_privilege('authenticated', 'public.online_orders', 'customer_mobile', 'select') and has_column_privilege('authenticated', 'public.online_orders', 'draft_note', 'select'));
select set_rule('customers_pii_guard_on', 'true') is null as con \gset
select tt.chk('H1 customers_pii_guard_on: mobile / whatsapp / address / note closed, name / id / credit_limit readable',
  not has_column_privilege('authenticated', 'public.customers', 'mobile', 'select') and not has_column_privilege('authenticated', 'public.customers', 'whatsapp', 'select') and not has_column_privilege('authenticated', 'public.customers', 'address', 'select')
  and not has_column_privilege('authenticated', 'public.customers', 'note', 'select') and has_column_privilege('authenticated', 'public.customers', 'name', 'select') and has_column_privilege('authenticated', 'public.customers', 'id', 'select')
  and has_column_privilege('authenticated', 'public.customers', 'credit_limit', 'select'));
select tt.as(:'p');
select tt.chk('H1 with the customers guard ON the RPCs still work for the salesperson (dues 700, directory finds the row)', (select balance from customer_dues() where id = :'cu'::uuid) = 700 and exists (select 1 from customer_directory() where id = :'cu'::uuid));
select tt.as(:'o');
select set_rule('customers_pii_guard_on', 'false') is null as coff \gset
select tt.chk('H1 customers guard off again: the whole table is readable as before', has_column_privilege('authenticated', 'public.customers', 'mobile', 'select') and has_column_privilege('authenticated', 'public.customers', 'note', 'select') and has_table_privilege('authenticated', 'public.customers', 'select'));

\echo == M6 phone numbers typed in free text (hand: 11 digits -> 8 dots + the last 3)
select tt.chk('M6 (F) dotted number 01711.111.111 -> ••••••••111', public._inb_mask_phones103('call 01711.111.111 now') = 'call ••••••••111 now');
select tt.chk('M6 (F) slash 01711/222333 and underscore 01711_444555', public._inb_mask_phones103('x 01711/222333 y') = 'x ••••••••333 y' and public._inb_mask_phones103('01711_444555') = '••••••••555');
select tt.chk('M6 (F) no-break space and tab as separators', public._inb_mask_phones103('01711' || chr(160) || '666777') = '••••••••777' and public._inb_mask_phones103('01711' || chr(9) || '888999') = '••••••••999');
select tt.chk('M6 (F) three spaces between the groups, Bangla digits with dots', public._inb_mask_phones103('01711   222333') = '••••••••333' and public._inb_mask_phones103('০১৭১১.৩৩৩.৪৪৪') = '••••••••৪৪৪');
select tt.chk('M6 the old forms still work: +8801711000111 (10 dots + 111), 01711-000111, +1 (415) 555-0132 (8 dots + 132)', public._inb_mask_phones103('+8801711000111') = repeat('•', 10) || '111' and public._inb_mask_phones103('call 01711-000111 now') = 'call ' || repeat('•', 8) || '111 now'
  and public._inb_mask_phones103('+1 (415) 555-0132') = repeat('•', 8) || '132');
select tt.chk('M6 dates, amounts and short numbers are left alone (14/10/2026, 2026.10.14, 2026-10-14, 14-10-2026, 1,234,567, 12345, 3.5 kg, 120.75)',
  public._inb_mask_phones103('on 14/10/2026 and 2026.10.14 and 2026-10-14 and 14-10-2026') = 'on 14/10/2026 and 2026.10.14 and 2026-10-14 and 14-10-2026'
  and public._inb_mask_phones103('total 1,234,567 order 12345 qty 3.5 kg at 120.75') = 'total 1,234,567 order 12345 qty 3.5 kg at 120.75');

\echo == M2 automatic payment honours bill_pay_large_amount and the supplier_pay grant
select set_rule('purchase_bill_creates_payment', '"auto_cash"') is null as pac \gset
select set_rule('cost_bill_creates_payment', '"auto_cash"') is null as cac \gset
select set_rule('bill_pay_large_amount', '5000') is null as lg \gset
select count(*) as fl0 from exceptions where flag_code = 'bill_pay_auto_skipped' \gset
-- b may enter and post a purchase bill but holds no supplier_pay: the 700 bill is NOT paid (before: paid 700)
select tt.as(:'b');
select save_purchase(null,null,:'sup1',1,'P-1',tt.today(),format('[{"item_id":"%s","qty":7,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb1 \gset
select post_purchase(:'pb1'::uuid) is not null as pp1 \gset
select tt.chk('M2 (F) poster without supplier_pay: bill 700 stays unpaid (paid 0, no supplier payment), a yellow flag says it was skipped', (select paid from purchase_bills where id = :'pb1'::uuid) = 0 and (select count(*) from supplier_payments where bill_id = :'pb1'::uuid) = 0
  and (select count(*) from exceptions where flag_code = 'bill_pay_auto_skipped') = :fl0 + 1);
-- u holds supplier_pay: small bill 700 is paid as before
select tt.as(:'u');
select save_purchase(null,null,:'sup1',1,'P-2',tt.today(),format('[{"item_id":"%s","qty":7,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb2 \gset
select post_purchase(:'pb2'::uuid) is not null as pp2 \gset
select tt.chk('M2 poster with supplier_pay and a small bill (700 < 5000): paid 700 automatically, as before', (select paid from purchase_bills where id = :'pb2'::uuid) = 700 and (select count(*) from supplier_payments where bill_id = :'pb2'::uuid and amount = 700 and mode = 'cash') = 1);
-- large bills: 6000 and exactly 5000 are not paid automatically, 4999 is
select save_purchase(null,null,:'sup1',1,'P-3',tt.today(),format('[{"item_id":"%s","qty":60,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb3 \gset
select post_purchase(:'pb3'::uuid) is not null as pp3 \gset
select save_purchase(null,null,:'sup1',1,'P-4',tt.today(),format('[{"item_id":"%s","qty":50,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb4 \gset
select post_purchase(:'pb4'::uuid) is not null as pp4 \gset
select save_purchase(null,null,:'sup1',1,'P-5',tt.today(),format('[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":4999}]',:'it1')::jsonb) ->> 'id' as pb5 \gset
select post_purchase(:'pb5'::uuid) is not null as pp5 \gset
select tt.chk('M2 (F) bill 6000 (> 5000) and bill 5000 (= the limit, "at or above") stay unpaid; bill 4999 is paid in full', (select paid from purchase_bills where id = :'pb3'::uuid) = 0 and (select paid from purchase_bills where id = :'pb4'::uuid) = 0
  and (select paid from purchase_bills where id = :'pb5'::uuid) = 4999 and (select count(*) from exceptions where flag_code = 'bill_pay_auto_skipped') = :fl0 + 3);
select tt.as(:'o');
select save_purchase(null,null,:'sup1',1,'P-6',tt.today(),format('[{"item_id":"%s","qty":60,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb6 \gset
select post_purchase(:'pb6'::uuid) is not null as pp6 \gset
select tt.chk('M2 the owner posting a large bill: the limit still applies (6000 unpaid)', (select paid from purchase_bills where id = :'pb6'::uuid) = 0);
select bill_pay_record('purchase', :'pb6', 'bank', 6000, gen_random_uuid())->>'ok' as man \gset
select tt.chk('M2 the manual way (bill_pay_record) still pays the large bill (6000)', :'man' = 'true' and (select paid from purchase_bills where id = :'pb6'::uuid) = 6000);
-- cost bills: the large limit only (no supplier grant for cost bills)
select tt.as(:'e');
select cost_bill_add(:sg::bigint,'month',tt.mo(0),300,'cash','C-1',tt.today(),false,null,null,'b0000000-0000-0000-0000-0000000000a1'::uuid) ->> 'id' as cb1 \gset
select cost_bill_add(:sg::bigint,'month',tt.mo(1),5000,'cash','C-2',tt.today(),false,null,null,'b0000000-0000-0000-0000-0000000000a2'::uuid) ->> 'id' as cb2 \gset
select tt.chk('M2 (F) cost bill 300 is paid automatically (a quick expense of 300), cost bill 5000 (= the limit) is not', (select count(*) from bill_payments99 where bill_kind = 'cost' and bill_ref = :'cb1' and amount = 300 and origin = 'auto') = 1
  and (select count(*) from bill_payments99 where bill_kind = 'cost' and bill_ref = :'cb2') = 0 and (select count(*) from quick_expenses where amount = 5000) = 0);
select tt.as(:'o');
select set_rule('purchase_bill_creates_payment', '"off"') is null as pof \gset
select set_rule('cost_bill_creates_payment', '"off"') is null as cof \gset
select set_rule('bill_pay_large_amount', null) is null as lg0 \gset

\echo == L3 / L4 the automatic client id and the client id check
select tt.chk('L3 (F) the automatic-payment client id is not md5(kind + ref) any more, is stable, differs per bill', public._bp_uuid99('cost','1') <> md5('bos99auto:cost:1')::uuid and public._bp_uuid99('cost','1') = public._bp_uuid99('cost','1') and public._bp_uuid99('cost','1') <> public._bp_uuid99('cost','2'));
select tt.chk('L3 the old (before paste) id was the guessable md5 (checked only on a fresh build)', not :'fresh' or :'l3_old');
select tt.as(:'u');
select save_purchase(null,null,:'sup2',1,'P-7',tt.today(),format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb7 \gset
select post_purchase(:'pb7'::uuid) is not null as pp7 \gset
select save_purchase(null,null,:'sup2',1,'P-8',tt.today(),format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb8 \gset
select post_purchase(:'pb8'::uuid) is not null as pp8 \gset
select bill_pay_record('purchase', :'pb7', 'cash', 100, 'd0000000-0000-0000-0000-0000000000a1'::uuid) as w1 \gset
select tt.chk('L4 same client id, same bill = dup (one payment of 100, bill paid 100)', (bill_pay_record('purchase', :'pb7', 'cash', 100, 'd0000000-0000-0000-0000-0000000000a1'::uuid)->>'dup') = 'true' and (select paid from purchase_bills where id = :'pb7'::uuid) = 100);
select tt.err('L4 (F) the same client id used for ANOTHER bill is refused (client_id_reused), not answered "paid"', format($$select bill_pay_record('purchase','%s','cash',100,'d0000000-0000-0000-0000-0000000000a1'::uuid)$$, :'pb8'), 'client_id_reused');
select tt.chk('L4 and the other bill is still unpaid (paid 0)', (select paid from purchase_bills where id = :'pb8'::uuid) = 0);

\echo == M3 keep_credit: a direct void of a linked payment is refused, the bill void still turns it into supplier credit
select tt.as(:'o'); select set_rule('bill_void_payment_mode', '"keep_credit"') is null as kc \gset
select id as spid from supplier_payments where bill_id = :'pb7'::uuid and not voided \gset
select tt.err('M3 (F) a direct update that voids the linked payment raises void_the_bill (before: silently dropped, no error)', format($$update supplier_payments set voided = true, void_note = 'typo' where id = %s$$, :'spid'), 'void_the_bill');
select tt.chk('M3 the payment is untouched (not voided, still tied to the bill, link row active); the bill is still paid 100', (select not voided and bill_id = :'pb7'::uuid from supplier_payments where id = :'spid'::bigint) and (select status from bill_payments99 where money_ref = :'spid') = 'active'
  and (select paid from purchase_bills where id = :'pb7'::uuid) = 100);
select void_purchase(:'pb7'::uuid, 'supplier credit please') is not null as vp \gset
select tt.chk('M3 void of the BILL in keep_credit mode: payment stays, un-tied from the bill = supplier credit (balance -100); link kept_credit', (select not voided and bill_id is null from supplier_payments where id = :'spid'::bigint) and (select status from bill_payments99 where money_ref = :'spid') = 'kept_credit'
  and _sup_balance(:'sup2'::uuid) = 400);   -- hand: the other bill 500 is open, the kept payment 100 is credit: 500 - 100 = 400
select set_rule('bill_void_payment_mode', '"void"') is null as kv \gset
select void_purchase(:'pb8'::uuid, 'no payment on it') is not null as vp8 \gset
select tt.chk('M3 void mode (default): the bill void still works (status void)', :'vp8' and (select status from purchase_bills where id = :'pb8'::uuid) = 'void');

\echo == M1 / L5 unmask: blocked attempts are logged at most once a minute (the race itself is in tests/sql/p105_conc.sh)
select tt.chk('M1 inbox_unmask counts the daily reveals under an advisory lock', position('pg_advisory_xact_lock' in pg_get_functiondef('public.inbox_unmask(text,text,text)'::regprocedure)) > 0);
select set_rule('inbox_on','true') is null as ion \gset
select sales_channel_save(null,'fbpage','facebook',null,'FB page',1,null,'PAGE1',true) is not null as ch1 \gset
select id as chf from sales_channels where code='fbpage' \gset
insert into inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, received_at)
  values (:chf, 1, 'm-1', '01711000111', 'Customer A', 'call 01711000111', now()) returning id as m1 \gset
insert into inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, received_at)
  values (:chf, 1, 'm-2', '01711000112', 'Customer B', 'price?', now()) returning id as m2 \gset
select set_rule('inbox_pii_mode','"mask_phone"') is null as m_1 \gset
select set_rule('inbox_unmask_daily_max','1') is null as rl \gset
select tt.as(:'q');
select inbox_unmask('message', :m1::text) as u1 \gset
select inbox_unmask('message', :m2::text) as u2 \gset
select inbox_unmask('message', :m2::text) as u3 \gset
select inbox_unmask('message', :m1::text) as u4 \gset
select tt.chk('L5 limit 1: 1 reveal, then 3 blocked attempts -> the reveal count stays 1', (select count(*) from inbox_unmask_log99 where user_id = :'q'::uuid and outcome = 'revealed') = 1 and not (:'u2'::jsonb->>'ok')::boolean and :'u2'::jsonb->>'error' = 'rate_limited'
  and :'u4'::jsonb->>'error' = 'rate_limited');
select tt.chk('L5 (F) ... but only ONE blocked line is written for those 3 attempts (within a minute)', (select count(*) from inbox_unmask_log99 where user_id = :'q'::uuid and outcome = 'blocked') = 1);
select tt.as(:'o'); select set_rule('inbox_unmask_daily_max', null) is null as rl0 \gset
select set_rule('inbox_pii_mode','"off"') is null as m_0 \gset

\echo == paste twice and the guard
select md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) as fa0 from pg_proc p where p.pronamespace = 'public'::regnamespace \gset
select v as salt0 from bos_salt105 where k = 'auto99' \gset
\i supabase/phase105.sql
select md5(string_agg(md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) as fa1 from pg_proc p where p.pronamespace = 'public'::regnamespace \gset
select tt.chk('PT paste twice: no function body changes, the salt is kept (the ids of earlier automatic payments stay valid)', :'fa0' = :'fa1' and (select v from bos_salt105 where k = 'auto99') = :'salt0' and (select count(*) from rules where key = 'customers_pii_guard_on') = 1);
-- guard: a database without the phase103 marker is refused and nothing is touched
alter function public._cust_pii103(text, text) rename to _cust_pii103_hold;
select md5(pg_get_functiondef('public.customer_dues()'::regprocedure)) as cd0 \gset
create or replace function public.customer_dues() returns table(id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date) language sql as $$ select null::uuid, 'held'::text, null::text, null::text, null::numeric, null::numeric, null::date $$;
\i supabase/phase105.sql
select tt.chk('PT guard: with the phase103 marker missing the paste raises and re-creates nothing (the held customer_dues stays)', (select name from customer_dues() limit 1) = 'held' and current_setting('phase105.ok') = 'off');
alter function public._cust_pii103_hold(text, text) rename to _cust_pii103;
\i supabase/phase105.sql
select tt.chk('PT with the marker back it works again: customer_dues restored to the phase105 body', md5(pg_get_functiondef('public.customer_dues()'::regprocedure)) = :'cd0');
-- body guard: a body with a tag this file does not know is not overwritten
create or replace function public._bp_sp_void99() returns trigger language plpgsql as $$ begin /* bos999 */ return new; end $$;
\i supabase/phase105.sql
select tt.chk('PT body guard: a newer tag (bos999) on _bp_sp_void99 stops the paste, nothing is overwritten', position('bos999' in pg_get_functiondef('public._bp_sp_void99()'::regprocedure)) > 0 and current_setting('phase105.ok') = 'guard1');

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
