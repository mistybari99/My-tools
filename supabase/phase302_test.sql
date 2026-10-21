-- FRESH DB ONLY. Phase 302 tests (CRM-A read functions: Customer 360, timeline, favourites, upcoming dates, masked directory, hook proof on a scratch copy).
--   Build a local throwaway database through phase 98 (or 99), paste phases 300, 301, 302 (twice each), then run from the repository root
--     psql -h /tmp -p 5571 -U postgres -d <db> -qAt -f supabase/phase302_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names); the fixture is tests/sql/crm_a_fixture.sql.
\set ON_ERROR_STOP off
\ir ../tests/sql/crm_a_fixture.sql
\set ON_ERROR_STOP off
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
-- all keys of a timeline, walked page by page
create or replace function tt.walk(p_c uuid, p_lim int) returns text[] language plpgsql as $$
declare r jsonb; b timestamptz; k text; acc text[] := '{}'; i int := 0; x jsonb;
begin
  loop
    r := public.crma_timeline(p_c, b, k, p_lim);
    for x in select * from jsonb_array_elements(r -> 'items') loop acc := acc || (x ->> 'key'); end loop;
    exit when not (r ->> 'has_more')::boolean;
    b := (r -> 'next' ->> 'before')::timestamptz; k := r -> 'next' ->> 'key';
    i := i + 1; exit when i > 60;
  end loop;
  return acc;
end $$;
-- exact-text patch of a COPY of a function under a new name (the live function is never touched)
create or replace function tt.patch_copy(p_fn regprocedure, p_old_name text, p_new_name text, p_pairs text[]) returns void language plpgsql as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  def := replace(def, p_old_name, p_new_name);
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'patch site not found: %', left(p_pairs[i], 80); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  execute def;
end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

\echo == T0 state function, defaults
select tt.as(:'u_o');
select tt.chk('T0 owner state: all three settings OFF, owner sees everything', (crma_state() ->> 'crm_on') = 'false' and (crma_state() ->> 'mask_phone') = 'false' and (crma_state() ->> 'is_owner') = 'true' and (crma_state() ->> 'view')::text is null
  and (crma_state() ->> 'can_view') = 'true' and (crma_state() ->> 'contact_ok') = 'true');
select tt.as(:'u_c');
select tt.chk('T0 cashier state: can write once crm_on is on, cannot view notes', (crma_state() ->> 'can_write') = 'true' and (crma_state() ->> 'can_view') = 'false' and (crma_state() ->> 'can_manage') = 'false' and (crma_state() ->> 'shows_phone') = 'true');
select tt.as(:'u_x');
select tt.err('T0 an outsider has no customers: 360 refused', format($q$select crma_customer_360(%L)$q$, :'c1'), 'not allowed');
select tt.err('T0 an outsider: timeline refused', format($q$select crma_timeline(%L)$q$, :'c1'), 'not allowed');
select tt.err('T0 an outsider: favourites refused', format($q$select crma_favourites(%L)$q$, :'c1'), 'not allowed');
select tt.err('T0 an outsider: directory refused', $q$select * from crma_customer_directory()$q$, 'not allowed');
select tt.err('T0 an outsider: upcoming dates refused', $q$select crma_dates_upcoming(30)$q$, 'not allowed');
select tt.as(:'u_c');
select tt.err('T0 a cashier without crm_view: upcoming dates refused', $q$select crma_dates_upcoming(30)$q$, 'not allowed');
select tt.err('T0 unknown customer: 360 refused', $q$select crma_customer_360(gen_random_uuid())$q$, 'customer_not_found');
select tt.err('T0 unknown customer: timeline refused', $q$select crma_timeline(gen_random_uuid())$q$, 'customer_not_found');

\echo == T1 Customer 360 as the owner (all places)
select tt.as(:'u_o');
select crma_customer_360(:'c1') as o1 \gset
select tt.chk('T1 identity, type label, credit terms, language, outlet, tag', (:'o1'::jsonb #>> '{customer,name}') = 'test_cust_one' and (:'o1'::jsonb #>> '{customer,type_label}') = 'Party / event' and (:'o1'::jsonb #>> '{customer,credit_days}') = '15'
  and (:'o1'::jsonb #>> '{customer,language}') = 'en' and (:'o1'::jsonb #>> '{customer,preferred_location,id}') = '1' and (:'o1'::jsonb #>> '{tags,0,code}') = 'test_tag' and (:'o1'::jsonb #>> '{customer,source}') = 'test_source');
select tt.chk('T1 phones: main + WhatsApp + one extra', jsonb_array_length(:'o1'::jsonb -> 'phones') = 3 and (:'o1'::jsonb #>> '{phones,0,kind}') = 'main' and (:'o1'::jsonb #>> '{phones,0,phone}') = '01711032001'
  and (:'o1'::jsonb #>> '{phones,1,kind}') = 'whatsapp' and (:'o1'::jsonb #>> '{phones,1,phone}') = '01711032009' and (:'o1'::jsonb #>> '{phones,2,phone}') = '01711032011' and (:'o1'::jsonb #>> '{phones,2,shared}') = 'false');
select tt.chk('T1 addresses: the main one is not the default because a delivery point is', jsonb_array_length(:'o1'::jsonb -> 'addresses') = 2 and (:'o1'::jsonb #>> '{addresses,0,address}') = 'test_addr_main_1' and (:'o1'::jsonb #>> '{addresses,0,is_default}') = 'false'
  and (:'o1'::jsonb #>> '{addresses,1,is_default}') = 'true' and (:'o1'::jsonb #>> '{addresses,1,landmark}') = 'near test_mosque');
select tt.chk('T1 dates: own birthday and anniversary + two family dates, sorted by next occurrence', jsonb_array_length(:'o1'::jsonb -> 'dates') = 4
  and (select count(*) from jsonb_array_elements(:'o1'::jsonb -> 'dates') d where (d ->> 'own')::boolean) = 2
  and (select bool_and((d ->> 'days_until')::int between 0 and 366) from jsonb_array_elements(:'o1'::jsonb -> 'dates') d)
  and (select (array_agg((d ->> 'days_until')::int order by ord))[1] <= (array_agg((d ->> 'days_until')::int order by ord))[4] from jsonb_array_elements(:'o1'::jsonb -> 'dates') with ordinality t(d, ord)));
select tt.chk('T1 the 29 February family date has a next date (28 Feb in a year without a 29th)', exists (select 1 from jsonb_array_elements(:'o1'::jsonb -> 'dates') d where d ->> 'person' = 'Parents' and (d ->> 'next_date')::date >= tt.today()
  and extract(month from (d ->> 'next_date')::date) = 2));
select tt.chk('T1 turning age comes from the year when known', exists (select 1 from jsonb_array_elements(:'o1'::jsonb -> 'dates') d where d ->> 'person' = 'Spouse' and (d ->> 'turning')::int = extract(year from (d ->> 'next_date')::date)::int - 1992));
select tt.chk('T1 totals: spend 1100 (done sales 1200 minus return 100), 3 orders, points 40, balance equals the existing _cust_bal',
  (:'o1'::jsonb #>> '{stats,spend}')::numeric = 1100 and (:'o1'::jsonb #>> '{stats,orders}')::int = 3 and (:'o1'::jsonb #>> '{stats,points}')::int = 40 and (:'o1'::jsonb #>> '{stats,balance}')::numeric = (select _cust_bal(:'c1'))
  and (:'o1'::jsonb #>> '{stats,avg_bill}')::numeric = round(1100 / 3.0, 2));
select tt.chk('T1 favourites (top 5): item A 2 orders / 5 kg / 1000, item B 1 / 1 / 150, quick line last; the void sale is not counted',
  (:'o1'::jsonb #>> '{favourites,0,item_id}') = :'i1' and (:'o1'::jsonb #>> '{favourites,0,orders}') = '2' and (:'o1'::jsonb #>> '{favourites,0,qty}')::numeric = 5 and (:'o1'::jsonb #>> '{favourites,0,amount}')::numeric = 1000
  and (:'o1'::jsonb #>> '{favourites,1,item_id}') = :'i2' and (:'o1'::jsonb #>> '{favourites,1,amount}')::numeric = 150 and (:'o1'::jsonb #>> '{favourites,2,name}') = 'test_quick' and (:'o1'::jsonb #>> '{favourites,2,amount}')::numeric = 50
  and (:'o1'::jsonb #>> '{favourites,0,name_en}') is not null);
select tt.chk('T1 counts for the owner: 1 note (the retired one is not counted), 2 open online orders (both places), 0 messages waiting', (:'o1'::jsonb #>> '{counts,notes}') = '1' and (:'o1'::jsonb #>> '{counts,open_orders}') = '2' and (:'o1'::jsonb #>> '{counts,messages_waiting}') = '0');
select tt.chk('T1 the old single note is shown to a viewer', (:'o1'::jsonb #>> '{customer,note}') = 'test_old_note');
select crma_customer_360(:'c3') as o3 \gset
select tt.chk('T1 a customer with nothing extra still shows a complete profile with no migration: main phone only, no address, no dates, no tags',
  jsonb_array_length(:'o3'::jsonb -> 'phones') = 1 and (:'o3'::jsonb #>> '{phones,0,phone}') = '01711032003' and jsonb_array_length(:'o3'::jsonb -> 'addresses') = 0 and jsonb_array_length(:'o3'::jsonb -> 'dates') = 0
  and jsonb_array_length(:'o3'::jsonb -> 'tags') = 0 and jsonb_array_length(:'o3'::jsonb -> 'favourites') = 0 and (:'o3'::jsonb #>> '{stats,spend}')::numeric = 0 and jsonb_typeof(:'o3'::jsonb -> 'next_date') = 'null');

\echo == T2 Customer 360 as a cashier (place 1 only, no crm_view), masking OFF
select tt.as(:'u_c');
select crma_customer_360(:'c1') as k1 \gset
select tt.chk('T2 phones are full while crm_mask_phone is OFF (today)', (:'k1'::jsonb #>> '{phones,0,phone}') = '01711032001' and (:'k1'::jsonb #>> '{phones,0,masked}') = 'false' and (:'k1'::jsonb #>> '{addresses,0,address}') = 'test_addr_main_1');
select tt.chk('T2 the cashier sees only place 1 in the totals (sale at place 2 left out): spend 1050 = 550 + 600 - 100', (:'k1'::jsonb #>> '{stats,spend}')::numeric = 1050 and (:'k1'::jsonb #>> '{stats,orders}')::int = 2);
select tt.chk('T2 no notes, no old note, no messages for a cashier without crm_view', (:'k1'::jsonb #>> '{counts,notes}') is null and (:'k1'::jsonb #>> '{customer,note}') is null and (:'k1'::jsonb #>> '{counts,messages_waiting}') is null);
select tt.chk('T2 open orders limited to place 1: 1', (:'k1'::jsonb #>> '{counts,open_orders}') = '1');
select tt.chk('T2 favourites limited to place 1 (the quick line from place 2 is gone)', jsonb_array_length(:'k1'::jsonb -> 'favourites') = 2);
select tt.as(:'u_r');
select tt.chk('T2 a read-only person (POS view only) may read the 360', (crma_customer_360(:'c1') #>> '{customer,name}') = 'test_cust_one' and (crma_customer_360(:'c1') #>> '{can,edit}') = 'false');

\echo == T3 Timeline
select tt.as(:'u_o');
select jsonb_array_length(crma_timeline(:'c1', null, null, 100) -> 'items') as n_o \gset
select tt.chk('T3 owner: 17 touchpoints (4 sales, 1 return, 1 collection, 3 orders, 3 points, 1 gift, 1 tier, 1 message, 1 note, 1 enquiry); the retired note is not there', :'n_o'::int = 17
  and (select count(*) from jsonb_array_elements(crma_timeline(:'c1', null, null, 100) -> 'items') x where x ->> 'kind' = 'sale') = 4
  and (select count(*) from jsonb_array_elements(crma_timeline(:'c1', null, null, 100) -> 'items') x where x ->> 'kind' = 'note') = 1);
select tt.chk('T3 newest first', (select bool_and(a >= b) from (select (x ->> 'at')::timestamptz a, lead((x ->> 'at')::timestamptz) over (order by ord) b from jsonb_array_elements(crma_timeline(:'c1', null, null, 100) -> 'items') with ordinality t(x, ord)) z where b is not null));
select tt.chk('T3 a sale row carries receipt, total, due and status; the void sale is shown as void', exists (select 1 from jsonb_array_elements(crma_timeline(:'c1', null, null, 100) -> 'items') x where x ->> 'title' = 'Sale #932002' and (x ->> 'amount')::numeric = 600 and (x #>> '{detail,due}')::numeric = 200 and x ->> 'status' = 'done')
  and exists (select 1 from jsonb_array_elements(crma_timeline(:'c1', null, null, 100) -> 'items') x where x ->> 'title' = 'Sale #932003' and x ->> 'status' = 'void'));
select tt.chk('T3 the online order matched by the +880 form, and the one matched by the extra number, both appear with total = subtotal - discount + delivery', exists (select 1 from jsonb_array_elements(crma_timeline(:'c1', null, null, 100) -> 'items') x where x ->> 'title' = 'Order #932001' and (x ->> 'amount')::numeric = 950)
  and exists (select 1 from jsonb_array_elements(crma_timeline(:'c1', null, null, 100) -> 'items') x where x ->> 'title' = 'Order #932002' and (x ->> 'amount')::numeric = 500));
select tt.chk('T3 the enquiry matched through the extra number is in the timeline', exists (select 1 from jsonb_array_elements(crma_timeline(:'c1', null, null, 100) -> 'items') x where x ->> 'kind' = 'enquiry' and x #>> '{detail,text}' = 'test_enquiry_text'));
select tt.chk('T3 customer two lists customer one''s main number as an extra: the number is shared, so none of customer one''s orders or messages appear for customer two', crma_timeline(:'c2', null, null, 100) -> 'items' = '[]'::jsonb
  and (crma_customer_360(:'c2') #>> '{phones,1,shared}') = 'true' and (crma_customer_360(:'c2') #>> '{counts,open_orders}') = '0');
select tt.chk('T3 a customer with nothing has an empty timeline, no more pages', (crma_timeline(:'c3') -> 'items') = '[]'::jsonb and (crma_timeline(:'c3') ->> 'has_more') = 'false');
select tt.chk('T3 kinds filter: sales only', (select count(*) from jsonb_array_elements(crma_timeline(:'c1', null, null, 100, array['sale']) -> 'items') x where x ->> 'kind' = 'sale') = 4 and jsonb_array_length(crma_timeline(:'c1', null, null, 100, array['sale']) -> 'items') = 4);
select tt.chk('T3 paging by 5 walks all 17 rows once each, no duplicates and no gaps', (select array_length(tt.walk(:'c1', 5), 1)) = 17 and (select count(distinct k) from unnest(tt.walk(:'c1', 5)) k) = 17
  and (select tt.walk(:'c1', 5)) = (select tt.walk(:'c1', 100)));
select tt.chk('T3 paging by 1 gives the same order', (select tt.walk(:'c1', 1)) = (select tt.walk(:'c1', 100)));
select tt.chk('T3 first page of 5 says there is more and gives a cursor', (crma_timeline(:'c1', null, null, 5) ->> 'has_more') = 'true' and (crma_timeline(:'c1', null, null, 5) #>> '{next,key}') is not null and jsonb_array_length(crma_timeline(:'c1', null, null, 5) -> 'items') = 5);
select tt.chk('T3 the limit is clamped (0 gives 1 row, 100000 gives at most 100)', jsonb_array_length(crma_timeline(:'c1', null, null, 0) -> 'items') = 1 and jsonb_array_length(crma_timeline(:'c1', null, null, 100000) -> 'items') = 17);
select tt.as(:'u_c');
select tt.chk('T3 cashier (place 1, no crm_view): 12 touchpoints - no message, note or enquiry, nothing from place 2', jsonb_array_length(crma_timeline(:'c1', null, null, 100) -> 'items') = 12
  and not exists (select 1 from jsonb_array_elements(crma_timeline(:'c1', null, null, 100) -> 'items') x where x ->> 'kind' in ('message','note','enquiry') or x ->> 'title' in ('Sale #932004','Order #932003')));
select tt.as(:'u_v');
select tt.chk('T3 viewer with crm_view (place 1): 15 touchpoints, including message, note, enquiry', jsonb_array_length(crma_timeline(:'c1', null, null, 100) -> 'items') = 15
  and (select count(*) from jsonb_array_elements(crma_timeline(:'c1', null, null, 100) -> 'items') x where x ->> 'kind' in ('message','note','enquiry')) = 3);
select tt.chk('T3 a note in the timeline shows the author', exists (select 1 from jsonb_array_elements(crma_timeline(:'c1', null, null, 100) -> 'items') x where x ->> 'kind' = 'note' and x #>> '{detail,by}' = 'test_viewer302'));
select crma_customer_360(:'c1') as v1 \gset
select tt.chk('T3 the viewer sees notes count and old note', (:'v1'::jsonb #>> '{counts,notes}') = '1' and (:'v1'::jsonb #>> '{customer,note}') = 'test_old_note');

\echo == T4 Privacy: crm_mask_phone ON
select tt.as(:'u_o');
select set_rule('crm_mask_phone', 'true'::jsonb) is null as s1 \gset
select tt.as(:'u_c');
select crma_customer_360(:'c1') as m1 \gset
select crma_timeline(:'c1', null, null, 100) as mt \gset
select tt.chk('T4 a cashier gets masked numbers: main 017******01, WhatsApp, extra', (:'m1'::jsonb #>> '{phones,0,phone}') = '017******01' and (:'m1'::jsonb #>> '{phones,0,masked}') = 'true' and (:'m1'::jsonb #>> '{phones,1,phone}') = '017******09' and (:'m1'::jsonb #>> '{phones,2,phone}') = '017******11');
select tt.chk('T4 addresses are hidden (area stays)', (:'m1'::jsonb #>> '{addresses,0,address}') is null and (:'m1'::jsonb #>> '{addresses,0,hidden}') = 'true' and (:'m1'::jsonb #>> '{addresses,1,address}') is null and (:'m1'::jsonb #>> '{addresses,1,landmark}') is null
  and (:'m1'::jsonb #>> '{addresses,1,delivery_note}') is null and (:'m1'::jsonb #>> '{addresses,1,area}') = 'test_area');
select tt.chk('T4 the full numbers and addresses appear nowhere in the JSON the server returned (not just hidden by the screen)', position('01711032' in :'m1') = 0 and position('test_addr_main_1' in :'m1') = 0 and position('test_addr_office_1' in :'m1') = 0 and position('test_mosque' in :'m1') = 0);
select tt.chk('T4 the stats and everything else still work while masked', (:'m1'::jsonb #>> '{stats,spend}')::numeric = 1050 and (:'m1'::jsonb #>> '{customer,name}') = 'test_cust_one');
select tt.as(:'u_v');
select crma_customer_360(:'c1') as m2 \gset
select crma_timeline(:'c1', null, null, 100) as mt2 \gset
select tt.chk('T4 crm_view alone does not unmask (viewer sees notes but masked numbers)', (:'m2'::jsonb #>> '{phones,0,phone}') = '017******01' and (:'m2'::jsonb #>> '{counts,notes}') = '1');
select tt.chk('T4 the message in the timeline shows a masked number and no raw number anywhere in the timeline', position('01711032' in :'mt2') = 0 and exists (select 1 from jsonb_array_elements(:'mt2'::jsonb -> 'items') x where x ->> 'kind' = 'message' and x #>> '{detail,to}' = '017******01'));
select tt.as(:'u_cv');
select tt.chk('T4 the holder of crm_contact_view sees full numbers', (crma_customer_360(:'c1') #>> '{phones,0,phone}') = '01711032001' and (crma_customer_360(:'c1') #>> '{addresses,0,address}') = 'test_addr_main_1');
select tt.as(:'u_mg');
select tt.chk('T4 a person who already sees mobiles in reports (POS approve) sees full numbers', (crma_customer_360(:'c1') #>> '{phones,0,phone}') = '01711032001');
select tt.as(:'u_o');
select tt.chk('T4 the owner sees full numbers', (crma_customer_360(:'c1') #>> '{phones,0,phone}') = '01711032001');
select tt.as(:'u_r');
select tt.chk('T4 a POS-view-only person is masked too', (crma_customer_360(:'c1') #>> '{phones,0,phone}') = '017******01');
select tt.as(:'u_c');
select tt.chk('T4 the lookup by any number masks the extra-number answer? no: the cashier typed the number, the main number is needed for the sale', (crma_find_by_any_phone('01711032011') ->> 'mobile') is not null);

\echo == T5 Directory: masked variant and the exposure of the old function
select tt.as(:'u_o');
select set_rule('crm_mask_phone', 'false'::jsonb) is null as s2 \gset
select tt.as(:'u_c');
select tt.chk('T5 masking OFF (default): the new directory returns exactly the rows of customer_directory (same columns, same values, same order)',
  (select md5(coalesce(jsonb_agg(to_jsonb(a) order by a.name, a.mobile)::text, '')) from crma_customer_directory() a) = (select md5(coalesce(jsonb_agg(to_jsonb(b) order by b.name, b.mobile)::text, '')) from customer_directory() b)
  and (select count(*) from crma_customer_directory()) = (select count(*) from customer_directory()));
select tt.as(:'u_o');
select set_rule('crm_mask_phone', 'true'::jsonb) is null as s3 \gset
select tt.as(:'u_c');
select tt.chk('T5 masking ON, cashier: mobile and WhatsApp masked, address and note hidden, the rest of the row unchanged',
  (select bool_and(a.mobile like '017______' || '%' and a.mobile like '%*%' and a.address is null and a.note is null and (a.whatsapp is null or a.whatsapp like '%*%')) from crma_customer_directory() a)
  and (select count(*) from crma_customer_directory()) = (select count(*) from customer_directory())
  and (select spend from crma_customer_directory() where name = 'test_cust_one') = (select spend from customer_directory() where name = 'test_cust_one')
  and (select balance from crma_customer_directory() where name = 'test_cust_one') = (select balance from customer_directory() where name = 'test_cust_one'));
select tt.chk('T5 the OLD customer_directory is unchanged and still exposes the full number until the hook is applied (documented exposure)', (select mobile from customer_directory() where name = 'test_cust_one') = '01711032001');
select tt.as(:'u_v');
select tt.chk('T5 masking ON, crm_view holder: numbers masked, note visible', (select a.mobile like '%*%' and a.note = 'test_old_note' from crma_customer_directory() a where a.name = 'test_cust_one'));
select tt.as(:'u_cv');
select tt.chk('T5 masking ON, crm_contact_view holder: identical to customer_directory', (select md5(jsonb_agg(to_jsonb(a) order by a.name, a.mobile)::text) from crma_customer_directory() a) = (select md5(jsonb_agg(to_jsonb(b) order by b.name, b.mobile)::text) from customer_directory() b));

\echo == T6 Hook proof on a scratch copy of customer_directory (the live function is not touched)
select tt.patch_copy('public.customer_directory(integer)'::regprocedure, 'public.customer_directory', 'tt.customer_directory_hooked', array[
  'select c.id, c.mobile, c.name, c.type,', 'select c.id, public._crma_ph(c.mobile) /* bos300 */, c.name, c.type,',
  'c.birthday, c.anniversary, c.address, c.whatsapp, c.note,', 'c.birthday, c.anniversary, case when public._crma_show_phone() then c.address end, public._crma_ph(c.whatsapp), case when public._crma_show_phone() or public._crma_view_ok() then c.note end,']);
grant execute on function tt.customer_directory_hooked(integer) to authenticated;
select tt.chk('T6 the live customer_directory carries no hook', pg_get_functiondef('public.customer_directory(integer)'::regprocedure) !~ 'bos300');
select tt.as(:'u_c');
select tt.chk('T6 hooked copy, cashier, masking ON: same rows as crma_customer_directory', (select md5(jsonb_agg(to_jsonb(a) order by a.name, a.mobile)::text) from tt.customer_directory_hooked() a) = (select md5(jsonb_agg(to_jsonb(b) order by b.name, b.mobile)::text) from crma_customer_directory() b)
  and (select bool_and(a.mobile like '%*%') from tt.customer_directory_hooked() a));
select tt.as(:'u_v');
select tt.chk('T6 hooked copy, crm_view holder, masking ON: same rows as crma_customer_directory', (select md5(jsonb_agg(to_jsonb(a) order by a.name, a.mobile)::text) from tt.customer_directory_hooked() a) = (select md5(jsonb_agg(to_jsonb(b) order by b.name, b.mobile)::text) from crma_customer_directory() b));
select tt.as(:'u_o');
select tt.chk('T6 hooked copy, owner, masking ON: identical to the live customer_directory', (select md5(jsonb_agg(to_jsonb(a) order by a.name, a.mobile)::text) from tt.customer_directory_hooked() a) = (select md5(jsonb_agg(to_jsonb(b) order by b.name, b.mobile)::text) from customer_directory() b));
select set_rule('crm_mask_phone', 'false'::jsonb) is null as s4 \gset
select tt.as(:'u_c');
select tt.chk('T6 hooked copy, cashier, masking OFF (default): identical to the live customer_directory = today''s behaviour', (select md5(jsonb_agg(to_jsonb(a) order by a.name, a.mobile)::text) from tt.customer_directory_hooked() a) = (select md5(jsonb_agg(to_jsonb(b) order by b.name, b.mobile)::text) from customer_directory() b));

\echo == T7 Upcoming dates
select tt.as(:'u_v');
select tt.chk('T7 next 366 days: the four dates of customer one, ordered, with person and turning age', jsonb_array_length(crma_dates_upcoming(366)) = 4 and (select bool_and((x ->> 'days_until')::int between 0 and 366) from jsonb_array_elements(crma_dates_upcoming(366)) x)
  and (select (array_agg(x ->> 'person' order by ord) filter (where x ->> 'kind' = 'birthday'))[1] is not null from jsonb_array_elements(crma_dates_upcoming(366)) with ordinality t(x, ord)));
select tt.chk('T7 a small window returns only what falls inside it', (select bool_and((x ->> 'days_until')::int <= 20) from jsonb_array_elements(crma_dates_upcoming(20)) x) is not false);
select tt.chk('T7 the phone is full here while masking is OFF', not exists (select 1 from jsonb_array_elements(crma_dates_upcoming(366)) x where (x ->> 'phone') <> '01711032001'));
select tt.as(:'u_o');
select set_rule('crm_mask_phone', 'true'::jsonb) is null as s5 \gset
select tt.as(:'u_v');
select tt.chk('T7 and masked once masking is ON', not exists (select 1 from jsonb_array_elements(crma_dates_upcoming(366)) x where (x ->> 'phone') <> '017******01'));
select tt.as(:'u_o');
select set_rule('crm_mask_phone', 'false'::jsonb) is null as s6 \gset

\echo == T8 Read functions write nothing
select tt.chk('T8 the read functions are STABLE (cannot write)', (select count(*) from pg_proc where proname in ('crma_customer_360','crma_timeline','crma_favourites','crma_dates_upcoming','crma_customer_directory','crma_state') and provolatile = 's') = 6);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
