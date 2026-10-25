-- FRESH DB ONLY. Phase 305 tests (CRM-B duplicates: possible-duplicates list, review decisions, SOFT link, group view, link effect on consent, accounting snapshot).
--   bash tests/sql/crmb_run.sh        or by hand on a fresh database through phase 98 + 303 + 304 + 305:
--   psql -h /tmp -p 5572 -U postgres -d <db> -qAt -f supabase/phase305_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000030501'
\set u_m '00000000-0000-0000-0000-000000030502'
\set u_g '00000000-0000-0000-0000-000000030503'
\set u_c '00000000-0000-0000-0000-000000030504'
\set u_n '00000000-0000-0000-0000-000000030505'
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
create or replace function tt.q(p_sql text) returns text language plpgsql security definer as $$
declare r text; begin execute p_sql into r; return r; end $$;
create or replace function tt.je() returns bigint language sql security definer as $$ select count(*) from public.journal_entries $$;
-- everything accounting-ish about customers, as one hash: dues list, each ledger and balance, sales, payments, journal lines
create or replace function tt.acct_hash() returns text language plpgsql security definer as $$
declare r text;
begin
  select md5(concat_ws('|',
    (select coalesce(jsonb_agg(to_jsonb(d) order by d.id), '[]'::jsonb)::text from public.customer_dues() d),
    (select coalesce(string_agg(c.id::text || ':' || public._cust_bal(c.id)::text, ',' order by c.id), '') from public.customers c),
    (select coalesce(string_agg(c.id::text || '=' || (select coalesce(jsonb_agg(to_jsonb(x) - 'at' order by x.at, x.kind, x.debit, x.credit), '[]'::jsonb)::text from public.customer_ledger(c.id) x), ',' order by c.id), '') from public.customers c),
    (select coalesce(string_agg(s.id::text || ':' || s.total::text || ':' || coalesce(s.customer_id::text, ''), ',' order by s.id), '') from public.sales s),
    (select coalesce(string_agg(p.id::text || ':' || p.amount::text, ',' order by p.id), '') from public.sale_payments p),
    (select coalesce(string_agg(e.source_type || ':' || l.debit::text || ':' || l.credit::text || ':' || coalesce(l.party_id, ''), ',' order by l.entry_id, l.line_no), '') from public.journal_lines l join public.journal_entries e on e.id = l.entry_id))) into r;
  return r;
end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner305@s.app','{"full_name":"test_owner305"}'), (:'u_m','test_mgr305@s.app','{"full_name":"test_mgr305"}'), (:'u_g','test_merger305@s.app','{"full_name":"test_merger305"}'),
 (:'u_c','test_cashier305@s.app','{"full_name":"test_cashier305"}'), (:'u_n','test_nopos305@s.app','{"full_name":"test_nopos305"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_m', :'u_g', :'u_c', :'u_n');
insert into user_roles values (:'u_o','owner'),(:'u_m','showroom_manager'),(:'u_g','showroom_manager'),(:'u_c','salesperson'),(:'u_n','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_m',1),(:'u_g',1),(:'u_c',1),(:'u_n',1) on conflict do nothing;
select tt.as(:'u_o');
select set_user_grant(:'u_m'::uuid,'customer_manage') is null as g1 \gset
select set_user_grant(:'u_g'::uuid,'crm_merge') is null as g2 \gset
-- A and B: the same person typed twice. A sale for A (1200 paid) and for B (1200, 500 paid, 700 owed).
select (record_sale2(gen_random_uuid(),1,'[{"amount":1200}]',0,'[{"mode":"cash","amount":1200}]','01750500001','test_ali rahman','retail',null,true)) is not null as s1 \gset
select (record_sale2(gen_random_uuid(),1,'[{"amount":1200}]',0,'[{"mode":"cash","amount":500}]','01750500002','TEST ali-rahman','retail',null,true)) is not null as s2 \gset
insert into customers (mobile, name, address, birthday, whatsapp) values
 ('01750500003','test_ali rahmen', null, null, null),             -- C: one letter different from A
 ('01750500004','test_zed', null, null, '01750500001'),            -- D: its WhatsApp number is A's mobile
 ('01750500005','test_other person', 'test road 9', null, null);   -- E: nothing in common
update customers set address='Test Road 1', birthday='1990-05-05' where mobile='01750500001';
update customers set address='test road, 1', birthday='1990-05-05' where mobile='01750500002';
select id as ca from customers where mobile='01750500001' \gset
select id as cb from customers where mobile='01750500002' \gset
select id as cc from customers where mobile='01750500003' \gset
select id as cd from customers where mobile='01750500004' \gset
select id as ce from customers where mobile='01750500005' \gset
select tt.acct_hash() as h0 \gset
select tt.je() as je0 \gset

\echo == T0 shape, safe defaults, closed internals
select tt.chk('T0 phase305 rules: dup check OFF, name distance blank; grant crm_merge exists and only the merger holds it',
  not rule_on('crm_dup_check_on') and not rule_on('crm_dup_similar_names_on') and exists (select 1 from grant_defs where grant_code='crm_merge') and (select count(*) from user_grants where grant_code='crm_merge')=1
  and not exists (select 1 from rules where key in ('crm_dup_check_on','crm_dup_similar_names_on') and (label_en ~ '[^\x01-\x7f]' or hint_en ~ '[^\x01-\x7f]')));
select tt.chk('T0 tables: RLS on, no browser writes', (select bool_and(relrowsecurity) from pg_class where relname in ('crm_customer_links','crm_dup_reviews'))
  and not has_table_privilege('authenticated','public.crm_customer_links','insert') and not has_table_privilege('authenticated','public.crm_customer_links','update') and not has_table_privilege('anon','public.crm_dup_reviews','select'));
select tt.chk('T0 API open to signed-in users only; helpers closed',
  has_function_privilege('authenticated','public._crmb_link_customers(uuid,uuid,uuid,text)','execute') and not has_function_privilege('anon','public._crmb_link_customers(uuid,uuid,uuid,text)','execute')
  and not has_function_privilege('authenticated','public._crmb_lev(text,text,int)','execute') and not has_function_privilege('authenticated','public._crmb_exc(text,text,text)','execute')
  and not has_function_privilege('authenticated','public._crmb_links_guard()','execute'));
select tt.chk('T0 customer_save / find_customer / record_sale2 / customer_dues carry no crmb text (nothing shared was re-created)',
  (select count(*) from pg_proc where proname in ('customer_save','find_customer','record_sale2','customer_dues','_cust_bal','customer_ledger','customer_balance') and position('crmb' in pg_get_functiondef(oid))>0)=0);
select tt.chk('T0 the Levenshtein helper: kitten/sitting = 3, equal = 0, cap respected', _crmb_lev('kitten','sitting',5)=3 and _crmb_lev('abc','abc',2)=0 and _crmb_lev('abcdef','uvwxyz',2)=3 and _crmb_lev('abc','abd',1)=1);
select tt.chk('T0 name normaliser ignores case, spaces and punctuation', _crmb_norm_name(' TEST ali-rahman ')=_crmb_norm_name('test_ali rahman') and _crmb_norm_name('test_ali rahman')='testalirahman');

\echo == T1 switch OFF (default): no list, no link; saving a customer behaves as today
set role authenticated; select tt.as(:'u_g');
select tt.chk('T1 candidates answer off and no rows', (select _crmb_dup_candidates() ->> 'off')='true' and (select jsonb_array_length(_crmb_dup_candidates() -> 'rows'))=0);
select tt.err('T1 link refused while OFF', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, 'same person')$$, :'ca', :'cb'), 'module_off');
select tt.err('T1 review refused while OFF', format($$select _crmb_dup_review(gen_random_uuid(), %L, %L, true, 'different people')$$, :'ca', :'cb'), 'module_off');
select tt.as(:'u_m');
select tt.chk('T1 customer_save on an exact mobile still answers dup (today)', (select customer_save(null, '{"mobile":"01750500001","name":"test_again"}'::jsonb, gen_random_uuid()) ->> 'dup')='true');
select tt.as(:'u_c');
select tt.err('T1 cashier has no access to the list', $$select _crmb_dup_candidates()$$, 'not allowed');
select tt.as(:'u_n');
select tt.err('T1 user without POS has no access', $$select _crmb_dup_candidates()$$, 'not allowed');
reset role; set role anon;
select tt.err('T1 anon has no execute', $$select _crmb_dup_candidates()$$, 'permission denied');
reset role;
select tt.chk('T1 nothing was created (no link, no review)', (select count(*) from crm_customer_links)=0 and (select count(*) from crm_dup_reviews)=0);

\echo == T2 the possible-duplicates list
select tt.as(:'u_o'); select set_rule('crm_dup_check_on','true') is null as don \gset
set role authenticated; select tt.as(:'u_m');
select _crmb_dup_candidates(100, 0) as cand \gset
select tt.chk('T2 pair A and D: strong, reason same_phone (D''s WhatsApp is A''s mobile)',
  exists (select 1 from jsonb_array_elements(:'cand'::jsonb -> 'rows') r where (r ->> 'strength')='strong' and (r -> 'reasons') ? 'same_phone'
     and ((r ->> 'a_id')=least(:'ca'::text,:'cd'::text) and (r ->> 'b_id')=greatest(:'ca'::text,:'cd'::text))));
select tt.chk('T2 pair A and B: strong, same_name + same_address + same_birthday (spaces, case, punctuation ignored)',
  exists (select 1 from jsonb_array_elements(:'cand'::jsonb -> 'rows') r where (r ->> 'strength')='strong' and (r -> 'reasons') ? 'same_name' and (r -> 'reasons') ? 'same_address' and (r -> 'reasons') ? 'same_birthday'
     and ((r ->> 'a_id')=least(:'ca'::text,:'cb'::text) and (r ->> 'b_id')=greatest(:'ca'::text,:'cb'::text))));
select tt.chk('T2 with similar names OFF, C (one letter off) is NOT listed, and E is in no pair',
  not exists (select 1 from jsonb_array_elements(:'cand'::jsonb -> 'rows') r where (r ->> 'a_id') = :'cc' or (r ->> 'b_id') = :'cc') and not exists (select 1 from jsonb_array_elements(:'cand'::jsonb -> 'rows') r where (r ->> 'a_id') = :'ce' or (r ->> 'b_id') = :'ce'));
select tt.chk('T2 strong pairs come first and the total counts them', (:'cand'::jsonb -> 'rows' -> 0 ->> 'strength')='strong' and (:'cand'::jsonb ->> 'total')::int = jsonb_array_length(:'cand'::jsonb -> 'rows'));
select tt.chk('T2 the guard is OFF: numbers are shown in full to this manager', (:'cand'::jsonb ->> 'masked')='false' and position('01750500001' in :'cand')>0);
select tt.as(:'u_o'); reset role; select set_rule('crm_dup_similar_names_on','true') is null as dist \gset
set role authenticated; select tt.as(:'u_m');
select _crmb_dup_candidates() as cand2 \gset
select tt.chk('T2 similar names ON: C appears against A as similar_name, strength weak (no address, no birthday in common)',
  exists (select 1 from jsonb_array_elements(:'cand2'::jsonb -> 'rows') r where (r -> 'reasons') ? 'similar_name' and (r ->> 'strength')='weak' and ((r ->> 'a_id')=least(:'ca'::text,:'cc'::text) and (r ->> 'b_id')=greatest(:'ca'::text,:'cc'::text))));
select tt.chk('T2 weak pairs are listed after strong ones', (:'cand2'::jsonb -> 'rows' -> (jsonb_array_length(:'cand2'::jsonb -> 'rows') - 1) ->> 'strength') in ('weak','possible'));
reset role; select tt.as(:'u_o'); select set_rule('crm_pii_guard_on','true') is null as gon \gset
set role authenticated; select tt.as(:'u_m');
select tt.chk('T2 guard ON: this manager (no crm_contact_view) gets masked numbers in the list', (_crmb_dup_candidates() ->> 'masked')='true' and position('01750500001' in _crmb_dup_candidates()::text)=0);
reset role; select tt.as(:'u_o'); select set_rule('crm_pii_guard_on','false') is null as goff \gset
set role authenticated; select tt.as(:'u_g');
select tt.chk('T2 the holder of crm_merge may open the list too', (select _crmb_dup_candidates() ->> 'off')='false');

\echo == T3 review: these two are not the same person
select tt.as(:'u_m');
select gen_random_uuid() as rk \gset
select tt.err('T3 a reason is needed to say "not the same person"', format($$select _crmb_dup_review(gen_random_uuid(), %L, %L, true)$$, :'ca', :'cc'), 'reason_required');
select tt.err('T3 same customer twice', format($$select _crmb_dup_review(gen_random_uuid(), %L, %L, true, 'x y z')$$, :'ca', :'ca'), 'self_link');
select tt.err('T3 unknown customer', format($$select _crmb_dup_review(gen_random_uuid(), %L, gen_random_uuid(), true, 'x y z')$$, :'ca'), 'customer_not_found');
select _crmb_dup_review(:'rk'::uuid, :'cc', :'ca', true, 'different people, checked with the shop') ->> 'not_duplicate' as rv \gset
select tt.chk('T3 decision stored (pair stored in order) and the pair leaves the list', :'rv'='true' and tt.q(format($$select count(*) from crm_dup_reviews where a_id=%L and b_id=%L and undone_at is null$$, least(:'ca'::uuid,:'cc'::uuid), greatest(:'ca'::uuid,:'cc'::uuid)))='1'
  and not exists (select 1 from jsonb_array_elements(_crmb_dup_candidates() -> 'rows') r where (r ->> 'a_id')=least(:'ca'::text,:'cc'::text) and (r ->> 'b_id')=greatest(:'ca'::text,:'cc'::text)));
select tt.chk('T3 same client id again: duplicate, no second row', (select _crmb_dup_review(:'rk'::uuid, :'cc', :'ca', true, 'different people, checked with the shop') ->> 'duplicate')='true' and (select count(*) from crm_dup_reviews)=1);
select tt.chk('T3 the same decision with another client id: unchanged', (select _crmb_dup_review(gen_random_uuid(), :'ca', :'cc', true, 'again') ->> 'unchanged')='true' and (select count(*) from crm_dup_reviews)=1);
select tt.chk('T3 reopening the pair puts it back on the list', (select _crmb_dup_review(gen_random_uuid(), :'ca', :'cc', false) ->> 'not_duplicate')='false'
  and exists (select 1 from jsonb_array_elements(_crmb_dup_candidates() -> 'rows') r where (r ->> 'a_id')=least(:'ca'::text,:'cc'::text) and (r ->> 'b_id')=greatest(:'ca'::text,:'cc'::text)));
select tt.as(:'u_c');
select tt.err('T3 cashier cannot decide', format($$select _crmb_dup_review(gen_random_uuid(), %L, %L, true, 'x y z')$$, :'ca', :'cc'), 'not allowed');
reset role;

\echo == T4 the soft link
select tt.acct_hash() as h1 \gset
select tt.chk('T4 (setup) the accounting hash so far equals the one taken at the start', :'h1' = :'h0');
set role authenticated; select tt.as(:'u_m');
select tt.err('T4 a customer manager without crm_merge cannot link', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, 'same person')$$, :'ca', :'cb'), 'not allowed');
select tt.as(:'u_c');
select tt.err('T4 cashier cannot link', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, 'same person')$$, :'ca', :'cb'), 'not allowed');
select tt.as(:'u_g');
select tt.err('T4 self-duplicate: a customer cannot be linked to itself', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, 'same person')$$, :'ca', :'ca'), 'self_link');
select tt.err('T4 a reason is needed', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, null)$$, :'ca', :'cb'), 'reason_required');
select tt.err('T4 a 2-character reason is not a reason', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, 'ok')$$, :'ca', :'cb'), 'reason_required');
select tt.err('T4 reason too long', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, repeat('x',301))$$, :'ca', :'cb'), 'bad_input');
select tt.err('T4 missing client id', format($$select _crmb_link_customers(null, %L, %L, 'same person')$$, :'ca', :'cb'), 'bad_input');
select tt.err('T4 unknown customer', format($$select _crmb_link_customers(gen_random_uuid(), %L, gen_random_uuid(), 'same person')$$, :'ca'), 'customer_not_found');
select tt.q($$select count(*) from exceptions where flag_code='customers_linked'$$) as ex0 \gset
select gen_random_uuid() as lk \gset
select _crmb_link_customers(:'lk'::uuid, :'ca', :'cb', 'same person, second number on the paper form') ->> 'id' as lid \gset
select tt.chk('T4 B is linked under A (A is the primary); an audit line; one yellow Exceptions row',
  tt.q(format($$select count(*) from crm_customer_links where primary_id=%L and linked_id=%L and undone_at is null and reason like 'same person%%'$$, :'ca', :'cb'))='1'
  and tt.q($$select count(*) from audit_log where action='crm_link'$$)='1' and tt.q($$select count(*) from exceptions where flag_code='customers_linked' and level='yellow' and form_code='CRM'$$)::int=:'ex0'::int+1);
select tt.chk('T4 same client id again: duplicate and no new row', (select _crmb_link_customers(:'lk'::uuid, :'ca', :'cb', 'same person, second number on the paper form') ->> 'duplicate')='true' and (select count(*) from crm_customer_links)=1);
select tt.err('T4 linking the same pair again: already_linked', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, 'same person')$$, :'ca', :'cb'), 'already_linked');
select tt.err('T4 MERGE LOOP: linking A under B while B is under A', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, 'reverse')$$, :'cb', :'ca'), 'primary_is_linked');
select tt.err('T4 a customer that is already linked cannot become a primary', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, 'chain')$$, :'cb', :'cc'), 'primary_is_linked');
select tt.err('T4 B cannot be linked under a second primary while it is under A', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, 'second parent')$$, :'ce', :'cb'), 'linked_elsewhere');
reset role;
select tt.chk('T4 ACCOUNTING UNCHANGED: dues list, every balance, every ledger, sales, payments and journal lines hash the same after the link', tt.acct_hash() = :'h0' and tt.je()=:'je0');
select tt.chk('T4 B''s balance is still 700 on B and A''s is still 0 (ledgers separate)', (select _cust_bal(:'cb'))=700 and (select _cust_bal(:'ca'))=0);
select tt.chk('T4 customer ids and mobiles did not change', (select mobile from customers where id=:'ca')='01750500001' and (select mobile from customers where id=:'cb')='01750500002');
set role authenticated; select tt.as(:'u_m');
select tt.chk('T4 the pair A+B left the possible-duplicates list; D+A is still there',
  not exists (select 1 from jsonb_array_elements(_crmb_dup_candidates() -> 'rows') r where (r ->> 'a_id')=least(:'ca'::text,:'cb'::text) and (r ->> 'b_id')=greatest(:'ca'::text,:'cb'::text))
  and exists (select 1 from jsonb_array_elements(_crmb_dup_candidates() -> 'rows') r where (r -> 'reasons') ? 'same_phone'));

\echo == T5 lists and the person view treat A and B as one (balances stay apart)
select tt.chk('T5 plain list (collapse off): B is still a row, linked_to A; A has linked_count 1; balances untouched',
  (select linked_to from _crmb_customer_list() where id=:'cb')=:'ca' and (select linked_count from _crmb_customer_list() where id=:'ca')=1 and (select balance from _crmb_customer_list() where id=:'cb')=700
  and (select spend from _crmb_customer_list() where id=:'ca')=1200);
select tt.chk('T5 collapsed list: B is folded into A; A shows spend 1200 + 1200 = 2400, orders 2, balance NOT combined (0)',
  not exists (select 1 from _crmb_customer_list(5000, true) where id=:'cb') and (select spend from _crmb_customer_list(5000, true) where id=:'ca')=2400
  and (select orders from _crmb_customer_list(5000, true) where id=:'ca')=2 and (select balance from _crmb_customer_list(5000, true) where id=:'ca')=0);
select tt.chk('T5 default list call is unchanged by the link feature (collapse defaults to off): same rows as customer_directory',
  (select count(*) from _crmb_customer_list())=(select count(*) from customer_directory()));
select _crmb_customer_group(:'cb') as grp \gset
select tt.chk('T5 person view from B: root is A, in_group, two members listed, ledgers_separate, balances 0 and 700 listed per member',
  (:'grp'::jsonb ->> 'root_id')=:'ca' and (:'grp'::jsonb ->> 'in_group')='true' and (:'grp'::jsonb ->> 'is_primary')='false' and jsonb_array_length(:'grp'::jsonb -> 'members')=2
  and (:'grp'::jsonb ->> 'ledgers_separate')='true'
  and (select (m ->> 'balance')::numeric from jsonb_array_elements(:'grp'::jsonb -> 'members') m where (m ->> 'id')=:'cb')=700 and (select (m ->> 'balance')::numeric from jsonb_array_elements(:'grp'::jsonb -> 'members') m where (m ->> 'id')=:'ca')=0
  and (:'grp'::jsonb -> 'combined' ->> 'spend')::numeric=2400 and (:'grp'::jsonb -> 'combined' ->> 'orders')::int=2);
select tt.chk('T5 person view of an unlinked customer: in_group false, one member', (select _crmb_customer_group(:'ce') ->> 'in_group')='false' and (select jsonb_array_length(_crmb_customer_group(:'ce') -> 'members'))=1);
select tt.as(:'u_n');
select tt.err('T5 user without POS cannot open the person view', format($$select _crmb_customer_group(%L)$$, :'ca'), 'not allowed');
select tt.as(:'u_c');
select tt.chk('T5 a cashier may open the person view (as with the profile), numbers follow the privacy switch', (select _crmb_customer_group(:'ca') ->> 'root_id')=:'ca');
select tt.as(:'u_m');
select tt.chk('T5 links list shows the active link (names, reason)', (select _crmb_links_list() -> 0 ->> 'linked_name')='TEST ali-rahman' and (select jsonb_array_length(_crmb_links_list()))=1);
select tt.as(:'u_c');
select tt.err('T5 cashier cannot read the links list', $$select _crmb_links_list()$$, 'not allowed');
reset role;

\echo == T6 the link protects the other number: a withdrawn yes or do-not-contact of one number blocks the person
select tt.as(:'u_o');
select _crmb_consent_set(gen_random_uuid(), :'ca', 'sms', true, 'paper_form', 'form 7') is not null as a_in \gset
select tt.chk('T6 A has a yes and is allowed', (select _crmb_send_allowed(:'ca','sms') ->> 'ok')='t' or (select _crmb_send_allowed(:'ca','sms') ->> 'ok')='true');
select _crmb_consent_set(gen_random_uuid(), :'cb', 'sms', false, 'phone', 'asked to stop on the second number') is not null as b_out \gset
select tt.chk('T6 B said no: A (linked) is blocked too, reason group_opted_out, not overridable', (select _crmb_send_allowed(:'ca','sms') ->> 'reason')='group_opted_out' and (select _crmb_send_allowed(:'ca','sms') ->> 'overridable')='false'
  and (select _crmb_block_reason(:'ca','sms'))='group_opted_out');
select tt.err('T6 the guard line used by the notify_enqueue hook refuses it', format($$select _crmb_enqueue_guard(%L,'sms')$$, :'ca'), 'not_opted_in');
select tt.chk('T6 the other channel of A is not affected', (select _crmb_block_reason(:'ca','whatsapp')) is null);
select _crmb_prefs_set(gen_random_uuid(), :'cb', true, 'asked not to be contacted', 'phone') is not null as b_dnc \gset
select tt.chk('T6 B do-not-contact: A is group_dnc on every channel', (select _crmb_block_reason(:'ca','whatsapp'))='group_dnc' and (select _crmb_send_allowed(:'ca','sms') ->> 'reason')='group_dnc');
select tt.err('T6 the guard raises do_not_contact for it', format($$select _crmb_enqueue_guard(%L,'whatsapp')$$, :'ca'), 'do_not_contact');
select tt.chk('T6 E (not linked to anyone) is not affected', (select _crmb_block_reason(:'ce','sms')) is null);

\echo == T7 regroup, unlink, and the shape stays one level deep
set role authenticated; select tt.as(:'u_g');
select _crmb_link_customers(gen_random_uuid(), :'cd', :'ca', 'D is the same person as A') ->> 'regrouped' as rg \gset
select tt.chk('T7 A had B under it: linking A under D moves B under D too (regrouped 1)', :'rg'='1'
  and tt.q(format($$select count(*) from crm_customer_links where primary_id=%L and undone_at is null$$, :'cd'))='2'
  and tt.q($$select count(*) from crm_customer_links where undone_at is null$$)='2'
  and tt.q(format($$select count(*) from crm_customer_links where linked_id=%L and undone_at is not null and undo_reason like 'regrouped under%%'$$, :'cb'))='1');
select tt.chk('T7 no active link has a primary that is itself linked (no chains, no loops)', tt.q($$select count(*) from crm_customer_links a join crm_customer_links b on b.linked_id=a.primary_id and b.undone_at is null where a.undone_at is null$$)='0');
select tt.chk('T7 the group view from B now has root D and three members', (select _crmb_customer_group(:'cb') ->> 'root_id')=:'cd' and (select jsonb_array_length(_crmb_customer_group(:'cb') -> 'members'))=3);
select tt.err('T7 A can no longer be a primary', format($$select _crmb_link_customers(gen_random_uuid(), %L, %L, 'x y z')$$, :'ca', :'ce'), 'primary_is_linked');
select tt.as(:'u_m');
select tt.err('T7 a customer manager without crm_merge cannot unlink', format($$select _crmb_unlink_customers(gen_random_uuid(), %L, 'x y z')$$, :'cb'), 'not allowed');
select tt.as(:'u_g');
select tt.err('T7 unlink needs a reason', format($$select _crmb_unlink_customers(gen_random_uuid(), %L, 'no')$$, :'cb'), 'reason_required');
select tt.err('T7 unlink of a customer that is not linked', format($$select _crmb_unlink_customers(gen_random_uuid(), %L, 'was a mistake')$$, :'ce'), 'not_linked');
select gen_random_uuid() as uk \gset
select _crmb_unlink_customers(:'uk'::uuid, :'cb', 'they are two people after all') ->> 'unlinked' as ul \gset
select tt.chk('T7 unlink: B is free again, the history row stays (stamped, not deleted)', :'ul'='true' and tt.q(format($$select count(*) from crm_customer_links where linked_id=%L and undone_at is null$$, :'cb'))='0'
  and tt.q(format($$select count(*) from crm_customer_links where linked_id=%L and undo_reason='they are two people after all'$$, :'cb'))='1' and tt.q($$select count(*) from audit_log where action='crm_unlink'$$)='1');
select tt.chk('T7 unlink with the same client id: duplicate, nothing else changes', (select _crmb_unlink_customers(:'uk'::uuid, :'cb', 'they are two people after all') ->> 'duplicate')='true');
select tt.chk('T7 after the unlink B shows as its own person again and its dues were never touched', (select _crmb_customer_group(:'cb') ->> 'in_group')='false' and (select customer_balance(:'cb'))=700);
select tt.chk('T7 links list: include_undone shows the stamped rows', (select jsonb_array_length(_crmb_links_list(100, true)))>(select jsonb_array_length(_crmb_links_list(100, false))));
reset role;
select tt.chk('T7 ACCOUNTING UNCHANGED after link, regroup and unlink', tt.acct_hash() = :'h0' and tt.je()=:'je0');

\echo == T8 the table itself refuses loops and rewrites, even to a direct write
select tt.err('T8 direct insert that would make a chain is refused by the table', format($$insert into crm_customer_links (primary_id, linked_id, reason) values (%L, %L, 'direct write')$$, :'ca', :'ce'), 'primary_is_linked');
select tt.err('T8 direct insert of a self link', format($$insert into crm_customer_links (primary_id, linked_id, reason) values (%L, %L, 'self')$$, :'ce', :'ce'), 'violates check');
select tt.err('T8 a link cannot be pointed somewhere else', format($$update crm_customer_links set primary_id=%L where undone_at is null$$, :'ce'), 'can only be undone once');
select tt.err('T8 an undone link cannot be changed again', $$update crm_customer_links set undo_reason='again' where undone_at is not null$$, 'can only be undone once');
select tt.err('T8 a link cannot be deleted', $$delete from crm_customer_links$$, 'append-only');
select tt.err('T8 a review cannot be deleted', $$delete from crm_dup_reviews$$, 'nothing is deleted');
set role authenticated; select tt.as(:'u_g');
select tt.err('T8 a browser user cannot write links directly', format($$insert into crm_customer_links (primary_id, linked_id, reason) values (%L, %L, 'direct')$$, :'ce', :'cb'), 'permission denied');
reset role;

\echo == T9 a second phone table of the profile package (customer_phones) is read when it exists
create table customer_phones (customer_id uuid, phone text, active boolean default true);
insert into customer_phones values (:'ce', '01750500003', true), (:'ce', '01750500009', false);
select tt.as(:'u_m'); set role authenticated;
select tt.chk('T9 E''s second phone equals C''s mobile: pair E and C is listed as same_phone, strong',
  exists (select 1 from jsonb_array_elements(_crmb_dup_candidates() -> 'rows') r where (r -> 'reasons') ? 'same_phone' and (r ->> 'strength')='strong'
     and ((r ->> 'a_id')=least(:'cc'::text,:'ce'::text) and (r ->> 'b_id')=greatest(:'cc'::text,:'ce'::text))));
reset role;
update customer_phones set active=false;
set role authenticated;
select tt.chk('T9 an inactive second phone is ignored', not exists (select 1 from jsonb_array_elements(_crmb_dup_candidates() -> 'rows') r where ((r ->> 'a_id')=least(:'cc'::text,:'ce'::text) and (r ->> 'b_id')=greatest(:'cc'::text,:'ce'::text)) and (r -> 'reasons') ? 'same_phone'));
reset role;
drop table customer_phones;
select tt.chk('T9 without the table everything still works', (select _crmb_dup_candidates() ->> 'off') is not null);

\echo == T10 speed on a larger book (2000 customers, similar names ON)
insert into customers (mobile, name) select '0188' || lpad(g::text, 7, '0'), 'test_bulk customer ' || md5(g::text) from generate_series(1, 2000) g;
select clock_timestamp() as t0 \gset
select tt.as(:'u_o');
select (_crmb_dup_candidates(100, 0) ->> 'total')::int as tot \gset
select (extract(epoch from clock_timestamp() - :'t0'::timestamptz)) as secs \gset
select tt.chk('T10 the list on about 2000 customers answers in under 20 seconds (' || round(:'secs'::numeric, 2) || ' s)', :'secs'::numeric < 20);
select tt.chk('T10 the bulk names (all different) create no new pair', :'tot'::int >= 2 and :'tot'::int < 12);

\echo == T11 paste again: nothing doubles
select count(*) as rules_n, (select count(*) from crm_customer_links) as l_n, (select count(*) from crm_dup_reviews) as r_n, (select count(*) from pg_proc where proname like '\_crmb\_%') as fn_n, (select count(*) from grant_defs where grant_code like 'crm\_%') as gd_n from rules where key like 'crm\_%' \gset
\ir phase305.sql
select tt.chk('T11 re-pasting phase305 changes nothing', (select count(*) from rules where key like 'crm\_%')=:'rules_n' and (select count(*) from crm_customer_links)=:'l_n' and (select count(*) from crm_dup_reviews)=:'r_n'
  and (select count(*) from pg_proc where proname like '\_crmb\_%')=:'fn_n' and (select count(*) from grant_defs where grant_code like 'crm\_%')=:'gd_n' and rule_on('crm_dup_check_on'));
select tt.chk('T11 grants still in place', has_function_privilege('authenticated','public._crmb_link_customers(uuid,uuid,uuid,text)','execute'));

select 'RESULT phase305: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
