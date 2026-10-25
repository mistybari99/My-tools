-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase99_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase525_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY. Phase 525 tests (Step Opt): bill payment options (cost bills, purchase bills) and inbox PII masking with audited unmask.
--   bash tests/sql/opt_build.sh a99db          (builds phase8..71, 72..97 and phase525)
--   psql -h /tmp -p 5544 -U postgres -d a99db -qAt -f supabase/phase525_test.sql | grep -E 'FAIL|RESULT'      (paste-twice check: paste supabase/phase525.sql a second time on the build first)
-- All numbers are hand-computed (comment above each block). Test data only, no person names.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set e '00000000-0000-0000-0000-000000000002'
\set u '00000000-0000-0000-0000-000000000003'
\set n '00000000-0000-0000-0000-000000000004'
\set sp '00000000-0000-0000-0000-000000000005'
\set q '00000000-0000-0000-0000-000000000006'
\set r '00000000-0000-0000-0000-000000000007'
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
create or replace function tt.noban(p text) returns boolean language sql immutable as $$ select p !~ '[ঀ-৿]' $$;
create or replace function tt.unbalanced_entries() returns bigint language plpgsql stable as $$
declare n bigint; begin select count(*) into n from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z; return n; end $$;
-- total debit / credit of the ORIGINAL entries of one source type, and the number of reversing entries
create or replace function tt.jd(p_type text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id where e.source_type = p_type and e.reverses_id is null $$;
create or replace function tt.jrev(p_type text) returns bigint language sql stable as $$
  select count(*) from public.journal_entries e where e.source_type = p_type and e.reverses_id is not null $$;
create or replace function tt.jcnt(p_type text) returns bigint language sql stable as $$
  select count(*) from public.journal_entries e where e.source_type = p_type and e.reverses_id is null $$;
-- cash-book (day_book, the screen's own function) sum of one direction / mode (/ source) for one place today; call it as the owner
create or replace function tt.dsum(p_loc int, p_dir text, p_mode text, p_src text default null) returns numeric language sql stable as $$
  select coalesce(sum((l->>'amount')::numeric), 0) from jsonb_array_elements(public.day_book(p_loc, tt.today(), tt.today())->'days') d cross join lateral jsonb_array_elements(d->'lines') l
   where l->>'dir' = p_dir and l->>'mode' = p_mode and (p_src is null or l->>'src' = p_src) $$;
create or replace function tt.autokey(p_kind text, p_ref text) returns uuid language sql stable security definer set search_path = public as $$ select public._bp_uuid99(p_kind, p_ref) $$;
create or replace function tt.autopay(p_kind text, p_ref text, p_mode text) returns jsonb language sql security definer set search_path = public as $$ select public._bp_pay99(p_kind, p_ref, p_mode, null, 'auto', public._bp_uuid99(p_kind, p_ref), null, false) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'e','entry2@s.app','{"full_name":"Entry"}'), (:'u','buyer3@s.app','{"full_name":"Buyer"}'), (:'n','none4@s.app','{"full_name":"Nobody"}'),
 (:'sp','sales5@s.app','{"full_name":"Seller"}'), (:'q','sales6@s.app','{"full_name":"Revealer"}'), (:'r','sales7@s.app','{"full_name":"Contact only"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'e','storekeeper'),(:'u','storekeeper'),(:'n','salesperson'),(:'sp','salesperson'),(:'q','salesperson'),(:'r','salesperson') on conflict do nothing;
insert into user_locations values (:'e',1),(:'e',5),(:'u',1),(:'n',1),(:'sp',1),(:'q',1),(:'r',1) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select set_user_grant(:'e'::uuid,'view_cost') is null as g1 \gset
select set_user_grant(:'e'::uuid,'cost_bill_entry') is null as g2 \gset
select set_user_grant(:'u'::uuid,'purchase_entry') is null as g3 \gset
select set_user_grant(:'u'::uuid,'supplier_pay') is null as g4 \gset
select set_user_grant(:'q'::uuid,'inbox_unmask') is null as g5 \gset
-- contact right for q and r when the guard is on (inbox_contact_view is a role grant in phase76's tests)
insert into rule_grants (role_code, grant_code, allowed) values ('salesperson','inbox_contact_view',true) on conflict (role_code, grant_code) do update set allowed=true;
with s as (insert into suppliers (name, credit_days) values ('Cash supplier', null) returning id) select id as sup1 from s \gset
with s as (insert into suppliers (name, credit_days) values ('Credit supplier', 30) returning id) select id as sup2 from s \gset
with s as (insert into suppliers (name, credit_days) values ('Keep supplier A', null) returning id) select id as sup3 from s \gset
with s as (insert into suppliers (name, credit_days) values ('Keep supplier B', null) returning id) select id as sup4 from s \gset
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('O1','O1','O1','kg','kg','raw_material',true,0) on conflict do nothing;
select id as it1 from items where code='O1' \gset
select tt.as(:'o');   -- the tests run as the table owner; every gate under test is inside the functions (auth.uid() = the claim set by tt.as)

\echo == T0 shape and defaults (everything = today's behaviour)
select tt.chk('T0 the five option rules + 3 helper rules exist with the right kinds', (select count(*) from rules where key in ('cost_bill_creates_payment','purchase_bill_creates_payment','bill_void_payment_mode','bill_pay_auto_credit_ok','bill_pay_large_amount','bill_pay_small_cash_max','inbox_pii_mode','inbox_unmask_daily_max'))=8);
select tt.chk('T0 defaults: both payment rules off, void mode void, auto-credit off, mask off', rule_txt('cost_bill_creates_payment')='off' and rule_txt('purchase_bill_creates_payment')='off' and rule_txt('bill_void_payment_mode')='void'
  and not rule_on('bill_pay_auto_credit_ok') and rule_txt('inbox_pii_mode')='off' and not rule_on('inbox_pii_guard_on'));
select tt.chk('T0 NO built-in numbers: large / small / daily max are blank', rule_num('bill_pay_large_amount') is null and rule_num('bill_pay_small_cash_max') is null and rule_num('inbox_unmask_daily_max') is null);
select tt.chk('T0 choices', (select choices from rules where key='cost_bill_creates_payment')='["off","ask","auto_cash","auto_bank","auto_by_supplier_default"]'::jsonb
  and (select choices from rules where key='inbox_pii_mode')='["off","mask_phone","mask_phone_address","mask_all_pii"]'::jsonb and (select choices from rules where key='bill_void_payment_mode')='["void","keep_credit"]'::jsonb);
select tt.chk('T0 grant inbox_unmask defined', exists (select 1 from grant_defs where grant_code='inbox_unmask'));
select tt.chk('T0 tables: RLS on, browser has no write; the log is closed', (select bool_and(relrowsecurity) from pg_class where relname in ('bill_pay_defaults99','bill_payments99','inbox_unmask_log99'))
  and not has_table_privilege('authenticated','bill_payments99','insert') and not has_table_privilege('authenticated','bill_payments99','update') and not has_table_privilege('authenticated','bill_payments99','delete')
  and not has_table_privilege('authenticated','bill_pay_defaults99','select') and not has_table_privilege('authenticated','inbox_unmask_log99','insert') and not has_table_privilege('authenticated','inbox_unmask_log99','delete'));
select tt.chk('T0 internals closed; calls open to signed-in only', not has_function_privilege('authenticated','public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)','execute') and not has_function_privilege('authenticated','public._inb_pii_f99(text,text)','execute')
  and has_function_privilege('authenticated','public.bill_pay_record(text,text,text,numeric,uuid,text,boolean)','execute') and has_function_privilege('authenticated','public.inbox_unmask(text,text,text)','execute')
  and not has_function_privilege('anon','public.bill_pay_record(text,text,text,numeric,uuid,text,boolean)','execute') and not has_function_privilege('anon','public.inbox_unmask(text,text,text)','execute')
  and not has_function_privilege('anon','public.payment_recommendation(text,text)','execute'));
select tt.chk('T0 re-created functions carry bos99 AND keep their older tags', position('bos99' in pg_get_functiondef('public.online_orders_list(int,text,date,date,int)'::regprocedure))>0
  and position('bos76' in pg_get_functiondef('public.online_orders_list(int,text,date,date,int)'::regprocedure))>0 and position('bos77' in pg_get_functiondef('public.online_orders_list(int,text,date,date,int)'::regprocedure))>0
  and position('bos99' in pg_get_functiondef('public.online_order_get(uuid)'::regprocedure))>0 and position('bos76' in pg_get_functiondef('public.online_order_get(uuid)'::regprocedure))>0 and position('bos77' in pg_get_functiondef('public.online_order_get(uuid)'::regprocedure))>0
  and position('bos99' in pg_get_functiondef('public.inbox_list(int,text,int)'::regprocedure))>0 and position('bos99' in pg_get_functiondef('public.inbox_get(bigint)'::regprocedure))>0 and position('bos99' in pg_get_functiondef('public.telegram_chat_info(bigint)'::regprocedure))>0);
select tt.chk('T0 recommendation rows added (8) with the recommended values', (select count(*) from setup_rec_defs81 where phase='99')=8
  and (select rec_value from setup_rec_defs81 where code='inbox_pii_mode')='"mask_phone_address"'::jsonb and (select rec_value from setup_rec_defs81 where code='cost_bill_creates_payment')='"ask"'::jsonb
  and (select rec_value from setup_rec_defs81 where code='bill_pay_large_amount') is null and (select rec_value from setup_rec_defs81 where code='bill_void_payment_mode')='"void"'::jsonb);
select tt.chk('T0 setup_recommendations shows them (status recommended for ask / mask, info for the numbers)',
  (select count(*) from jsonb_array_elements(setup_recommendations()->'items') x where x->>'code' in ('cost_bill_creates_payment','purchase_bill_creates_payment','inbox_pii_mode') and x->>'status'='recommended')=3
  and (select count(*) from jsonb_array_elements(setup_recommendations()->'items') x where x->>'code' in ('bill_pay_large_amount','bill_pay_small_cash_max','inbox_unmask_daily_max') and x->>'status'='info')=3
  and (select x->>'status' from jsonb_array_elements(setup_recommendations()->'items') x where x->>'code'='bill_void_payment_mode')='ok');
select tt.err('T0 bad mode value refused by set_rule', $$select set_rule('inbox_pii_mode','"mask_everything"')$$, 'bad_value');
select tt.err('T0 bad payment mode value refused', $$select set_rule('cost_bill_creates_payment','"sometimes"')$$, 'bad_value');

\echo == setup: accounting on (from 5 days ago), a gas source (place 1), an internet source (place 1)
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
select tt.as(:'e');
select cost_source_save(null,'gas','meter G-1','separate','factory',array[1],'monthly',tt.mo(3)) ->> 'id' as sg \gset
select cost_source_save(null,'internet','ISP-1','separate','showroom',array[1],'monthly',tt.mo(3)) ->> 'id' as si \gset
select tt.as(:'o');

\echo == D1-A cost bill, default OFF = today (information only, no payment)
select tt.as(:'e');
select cost_bill_add(:sg::bigint,'month',tt.mo(0),1000,'cash','B-1',tt.today(),false,null,null,'b0000000-0000-0000-0000-000000000001'::uuid) ->> 'id' as cb1 \gset
select tt.chk('A1 default off: bill saved, NO payment record anywhere', (select count(*) from bill_payments99)=0 and (select count(*) from quick_expenses)=0 and (select count(*) from supplier_payments)=0);
select tt.chk('A1 info: remaining 1000, rule off, payments none', (bill_pay_info99('cost',:'cb1')->>'remaining')::numeric=1000 and bill_pay_info99('cost',:'cb1')->>'rule'='off' and jsonb_array_length(bill_pay_info99('cost',:'cb1')->'payments')=0);
select tt.chk('A1 the bill shows in "Bills without payment" (1000 due)', (select count(*) from jsonb_array_elements(bills_without_payment99('cost',null,50)->'rows') x where x->>'ref'=:'cb1' and (x->>'due')::numeric=1000)=1);
select tt.as(:'o');
select set_rule('cost_bill_creates_payment','"ask"') is null as r1 \gset
select tt.as(:'e');
select cost_bill_add(:sg::bigint,'month',tt.mo(1),600,'bank','B-2',tt.today(),false,null,null,'b0000000-0000-0000-0000-000000000002'::uuid) ->> 'id' as cb2 \gset
select tt.chk('A2 mode ask: saving still writes no payment by itself (the sheet asks)', (select count(*) from bill_payments99)=0 and (select count(*) from quick_expenses)=0);

\echo == D1-B ask: bill 1000 -> pay 400 cash, then 600 bank (hand: 400+600 = 1000, remaining 600 then 0)
select tt.as(:'n'); select tt.err('B1 nobody without the entry right may record', format($$select bill_pay_record('cost','%s','cash',100)$$, :'cb1'), 'not allowed');
select tt.as(:'e');
select bill_pay_record('cost',:'cb1','cash',400,'c0000000-0000-0000-0000-000000000001'::uuid) as p1 \gset
select tt.chk('B1 first payment 400 cash: ok, remaining 600, counted', (:'p1'::jsonb->>'ok')::boolean and (:'p1'::jsonb->>'amount')::numeric=400 and (:'p1'::jsonb->>'remaining')::numeric=600 and (:'p1'::jsonb->>'counted')::boolean and :'p1'::jsonb->>'money_type'='quick_expense');
select tt.chk('B1 one quick expense of 400, cash, head repair (gas), place 1; a pending form-10-2 shadow exists', (select count(*) from quick_expenses where amount=400 and mode='cash' and head='repair' and location_id=1 and status='done')=1
  and exists (select 1 from shadow_links where primary_type='quick_expenses' and state='pending'));
select bill_pay_record('cost',:'cb1','cash',400,'c0000000-0000-0000-0000-000000000001'::uuid)->>'dup' as d1 \gset
select tt.chk('B1 same client id again = dup, still ONE payment', :'d1'='true' and (select count(*) from quick_expenses)=1 and (select count(*) from bill_payments99)=1);
select tt.err('B2 more than remaining refused (700 > 600)', format($$select bill_pay_record('cost','%s','cash',700)$$, :'cb1'), 'overpaid');
select bill_pay_record('cost',:'cb1','bank',600,'c0000000-0000-0000-0000-000000000002'::uuid) as p2 \gset
select tt.chk('B3 second payment 600 bank: remaining 0', (:'p2'::jsonb->>'remaining')::numeric=0 and (select count(*) from quick_expenses where amount=600 and mode='bank')=1);
select tt.err('B3 nothing left to pay', format($$select bill_pay_record('cost','%s','cash',1)$$, :'cb1'), 'nothing_due');
select tt.chk('B3 paid in full: leaves "Bills without payment"; info shows 2 payments', (select count(*) from jsonb_array_elements(bills_without_payment99('cost',null,50)->'rows') x where x->>'ref'=:'cb1')=0
  and jsonb_array_length(bill_pay_info99('cost',:'cb1')->'payments')=2 and (bill_pay_info99('cost',:'cb1')->>'paid')::numeric=1000);
select tt.chk('B3 the other bill (600) is still listed as unpaid', (select count(*) from jsonb_array_elements(bills_without_payment99('cost',null,50)->'rows') x where x->>'ref'=:'cb2' and (x->>'due')::numeric=600)=1);
select tt.err('B4 mode card is not a cost-bill mode', format($$select bill_pay_record('cost','%s','card',10)$$, :'cb2'), 'bad_mode');
select tt.err('B4 bad reference', $$select bill_pay_record('cost','abc','cash',10)$$, 'bad_ref');
select bill_pay_record('cost',:'cb2','other',200,'c0000000-0000-0000-0000-000000000003'::uuid) as p3 \gset
select tt.chk('B5 mode other = NOTE ONLY: recorded, not counted, no cash book line, no quick expense', (:'p3'::jsonb->>'counted')::boolean is false and :'p3'::jsonb->>'money_type'='note_only' and (select count(*) from quick_expenses)=2);
select tt.as(:'n');
select tt.err('B6 a person with no cost right cannot read the info', format($$select bill_pay_info99('cost','%s')$$, :'cb1'), 'not allowed');
select tt.as(:'o');

\echo == D1-C counted ONCE: cash book, journal, trial balance (hand: cash 400, bank 600 = 1000 out; journal debit 1000)
select posted from (select (acct_post_pending(false)->>'posted')::int posted) z \gset
select tt.chk('C1 journal: two quick-expense entries, total debit 1000 (400 + 600), nothing for the bill itself or its note-only line', tt.jcnt('quick_expense')=2 and tt.jd('quick_expense')=1000
  and not exists (select 1 from journal_entries where source_type like 'cost%' or source_type like 'bill%'));
select tt.chk('C1 trial balance: every entry balanced', tt.unbalanced_entries()=0);
select tt.chk('C2 cash book of place 1 (gas bill 1000): out cash 400, out bank 600 (exactly; the note-only 200 is not there)', tt.dsum(1,'out','cash')=400 and tt.dsum(1,'out','bank')=600 and tt.dsum(1,'out','mobile')=0);
select tt.chk('C3 day book vs journal: no expense difference', not exists (select 1 from jsonb_array_elements(daybook_vs_journal(tt.today()-1, tt.today(), null)->'rows') x where x->>'kind' in ('expense','supplier_payment')));
select tt.chk('C4 the 10-2 shadow is a COPY: closing the day makes ONE form and does not add a second expense', (select quick_expense_close_day(1, tt.today())->>'made')='2');
select acct_post_pending(false) is not null as p_again \gset
select tt.chk('C4 after the form: journal still 2 entries / 1000; the form (shadow) posted nothing', tt.jcnt('quick_expense')=2 and tt.jd('quick_expense')=1000 and tt.jcnt('expense_voucher')=0);

\echo == D1-D void of the bill (mode void): payments follow; but a payment already inside the day-end form is KEPT (flag)
select tt.as(:'e');
select cost_source_save(null,'water','WASA','separate','factory',array[1],'monthly',tt.mo(3)) ->> 'id' as sw \gset
select cost_bill_add(:sw::bigint,'month',tt.mo(0),500,'cash','W-1',tt.today(),false,null,null,'b0000000-0000-0000-0000-000000000003'::uuid) ->> 'id' as cb3 \gset
select bill_pay_record('cost',:'cb3','cash',500,'c0000000-0000-0000-0000-000000000004'::uuid) is not null as pw \gset
select tt.as(:'o'); select acct_post_pending(false) is not null as p_pre \gset
select tt.as(:'e');
select cost_bill_void(:cb3::bigint, 'entered by mistake')::text as v3 \gset
select tt.chk('D1 bill 500 voided: its quick expense is void, link row void, none kept', (select status from quick_expenses where amount=500)='void' and (select status from bill_payments99 where bill_ref=:'cb3')='void');
select tt.as(:'o'); select acct_post_pending(false) is not null as p_v \gset
select tt.chk('D1 journal: the 500 entry (posted before the void) has a REVERSING entry; the original is untouched; still balanced', tt.jcnt('quick_expense')=3 and tt.jrev('quick_expense')=1 and tt.jd('quick_expense')=1500 and tt.unbalanced_entries()=0);
select tt.as(:'e');
select cost_bill_void(:cb1::bigint, 'wrong month')::text as v1 \gset
select tt.chk('D2 bill 1000 voided although its payments are in the day-end form: payments KEPT (kept_credit) + yellow flag, nothing deleted',
  (select count(*) from bill_payments99 where bill_ref=:'cb1' and status='kept_credit')=2 and (select count(*) from quick_expenses where status='done' and amount in (400,600))=2
  and exists (select 1 from exceptions where flag_code='bill_pay_kept'));
select cost_bill_void(:cb1::bigint, 'again')::text as v1b \gset
select tt.chk('D2 void again is a no-op', (select count(*) from bill_payments99 where bill_ref=:'cb1')=2 and (select count(*) from bill_payments99 where status='kept_credit' and bill_ref=:'cb1')=2);
-- keep_credit (owner rule) on a fresh bill
select tt.as(:'o'); select set_rule('bill_void_payment_mode','"keep_credit"') is null as k1 \gset
select tt.as(:'e');
select cost_bill_add(:sw::bigint,'month',tt.mo(1),250,'cash','W-2',tt.today(),false,null,null,'b0000000-0000-0000-0000-000000000004'::uuid) ->> 'id' as cb4 \gset
select bill_pay_record('cost',:'cb4','cash',250,'c0000000-0000-0000-0000-000000000005'::uuid) is not null as pw4 \gset
select cost_bill_void(:cb4::bigint, 'keep the money')::text as v4 \gset
select tt.chk('D3 keep_credit: bill void, payment stays done (250 cash), link kept_credit', (select status from quick_expenses where amount=250)='done' and (select status from bill_payments99 where bill_ref=:'cb4')='kept_credit');
select tt.as(:'o'); select set_rule('bill_void_payment_mode','"void"') is null as k2 \gset

\echo == D1-E auto modes for cost bills
select set_rule('cost_bill_creates_payment','"auto_cash"') is null as a1 \gset
select tt.as(:'e');
select cost_bill_add(:si::bigint,'month',tt.mo(0),300,null,'I-1',tt.today(),false,null,null,'b0000000-0000-0000-0000-000000000005'::uuid) ->> 'id' as cb5 \gset
select tt.chk('E1 auto_cash: bill 300 saved -> ONE quick expense 300 cash at place 1 (internet = head repair), link origin auto', (select count(*) from quick_expenses where amount=300 and mode='cash' and location_id=1)=1
  and (select origin||mode from bill_payments99 where bill_ref=:'cb5')='autocash');
select tt.chk('E1 fully paid at once: not in the unpaid list', (select count(*) from jsonb_array_elements(bills_without_payment99('cost',null,50)->'rows') x where x->>'ref'=:'cb5')=0);
select tt.as(:'o');
select tt.autopay('cost', :'cb5', 'cash') ->> 'dup' as e1d \gset
select tt.chk('E1 the automatic payment cannot be made twice for one bill (same key = dup; one row)', :'e1d'='true' and (select count(*) from bill_payments99 where bill_ref=:'cb5')=1 and (select count(*) from quick_expenses where amount=300)=1);
select set_rule('cost_bill_creates_payment','"auto_bank"') is null as a2 \gset
select tt.as(:'e');
select cost_bill_add(:si::bigint,'month',tt.mo(1),120,null,'I-2',tt.today(),false,null,null,'b0000000-0000-0000-0000-000000000006'::uuid) ->> 'id' as cb6 \gset
select tt.chk('E2 auto_bank: 120 bank', (select count(*) from quick_expenses where amount=120 and mode='bank')=1);
select tt.as(:'o'); select set_rule('cost_bill_creates_payment','"auto_by_supplier_default"') is null as a3 \gset
select tt.as(:'e');
select cost_bill_add(:si::bigint,'month',tt.mo(2),90,null,'I-3',tt.today(),false,null,null,'b0000000-0000-0000-0000-000000000007'::uuid) ->> 'id' as cb7 \gset
select tt.chk('E3 by_default with NO default known and no bill mode: nothing paid (it behaves like ask, bill stays listed)', (select count(*) from bill_payments99 where bill_ref=:'cb7')=0 and (select count(*) from jsonb_array_elements(bills_without_payment99('cost',null,50)->'rows') x where x->>'ref'=:'cb7')=1);
select cost_bill_add(:si::bigint,'month',tt.mo(3),80,'mobile','I-4',tt.today(),false,null,null,'b0000000-0000-0000-0000-000000000008'::uuid) ->> 'id' as cb8 \gset
select tt.chk('E3 by_default: the mode typed on the bill (mobile) is used when the source has no default', (select mode from bill_payments99 where bill_ref=:'cb8')='mobile');
select tt.err('E3 only the owner sets a default', format($$select bill_pay_default_set99('cost_source','%s','bank',false)$$, :'si'), 'not allowed');
select tt.as(:'o');
select bill_pay_default_set99('cost_source', :'si', 'bank', false) is not null as ds \gset
select tt.as(:'e');
select cost_bill_add(:si::bigint,'month',tt.mo(4),70,null,'I-5',tt.today(),false,null,null,'b0000000-0000-0000-0000-000000000009'::uuid) ->> 'id' as cb9 \gset
select tt.chk('E4 by_default: the source default (bank) is used', (select mode from bill_payments99 where bill_ref=:'cb9')='bank');
-- credit terms: never auto
select tt.as(:'o'); select bill_pay_default_set99('cost_source', :'si', 'bank', true) is not null as dc \gset
select tt.as(:'e');
select cost_bill_add(:si::bigint,'month',tt.mo(5),60,null,'I-6',tt.today(),false,null,null,'b0000000-0000-0000-0000-00000000000a'::uuid) ->> 'id' as cb10 \gset
select tt.chk('E5 credit-terms source: NOT paid automatically; yellow flag; bill stays listed', (select count(*) from bill_payments99 where bill_ref=:'cb10')=0 and exists (select 1 from exceptions where flag_code='bill_pay_auto_skipped')
  and (select count(*) from jsonb_array_elements(bills_without_payment99('cost',null,50)->'rows') x where x->>'ref'=:'cb10')=1);
select tt.as(:'o'); select set_rule('bill_pay_auto_credit_ok','true') is null as ok1 \gset
select tt.as(:'e');
select cost_bill_add(:si::bigint,'month',tt.mo(6),50,null,'I-7',tt.today(),false,null,null,'b0000000-0000-0000-0000-00000000000b'::uuid) ->> 'id' as cb11 \gset
select tt.chk('E5 owner allows auto for credit parties: now paid (bank 50)', (select mode from bill_payments99 where bill_ref=:'cb11')='bank');
select tt.as(:'o'); select set_rule('bill_pay_auto_credit_ok','false') is null as ok2 \gset

\echo == D1-F double-count guards (a quick expense of the same cost already exists)
select tt.as(:'o');
insert into quick_expenses (location_id, exp_date, head, paid_to, amount, mode, created_by) values (1, tt.today(), 'repair', 'ISP', 777, 'cash', :'o'::uuid);
select tt.as(:'e');
select cost_bill_add(:sg::bigint,'month',tt.mo(0),777,null,'G-77',tt.today(),false,null,null,'b0000000-0000-0000-0000-00000000000c'::uuid) ->> 'id' as cb12 \gset
select tt.as(:'o'); select set_rule('cost_bill_creates_payment','"auto_cash"') is null as a5 \gset
select tt.as(:'e');
select cost_bill_add(:sg::bigint,'month',tt.mo(0),777,null,'G-78',tt.today(),false,null,null,'b0000000-0000-0000-0000-00000000000d'::uuid) ->> 'id' as cb13 \gset
select tt.chk('F1 auto mode skips a bill that looks like an existing quick expense (same place, head, amount): no second expense, flag, bill listed', (select count(*) from bill_payments99 where bill_ref=:'cb13')=0
  and (select count(*) from quick_expenses where amount=777)=1 and exists (select 1 from exceptions where flag_code='bill_pay_auto_skipped' and text->>'en' like '%quick_expense_similar%'));
select bill_pay_record('cost',:'cb12','cash',777) as w1 \gset
select tt.chk('F2 ask path warns first (needs_confirm), writes nothing', (:'w1'::jsonb->>'needs_confirm')::boolean and (:'w1'::jsonb->'warnings') @> '"quick_expense_similar"'::jsonb and (select count(*) from quick_expenses where amount=777)=1);
select bill_pay_record('cost',:'cb12','cash',777,null,null,true) ->> 'ok' as w2 \gset
select tt.chk('F2 after the person confirms "it is a different cost" the payment is written', :'w2'='true' and (select count(*) from quick_expenses where amount=777)=2);
select tt.as(:'o'); select set_rule('cost_bill_creates_payment','"off"') is null as a6 \gset
-- the owner made the 10-2 form the record: path A is locked, the payment cannot be written as a quick expense
select path_switch_set('expense', 1, false, true, 'b') is not null as lk \gset
select tt.as(:'e');
select cost_bill_add(:sg::bigint,'month',tt.mo(4),55,null,'G-55',tt.today(),false,null,null,'b0000000-0000-0000-0000-00000000000e'::uuid) ->> 'id' as cb14 \gset
select tt.err('F3 path A of the expense domain locked by the owner (form 10-2 is the record): refused, no quick expense', format($$select bill_pay_record('cost','%s','cash',55)$$, :'cb14'), 'path_locked');
select tt.as(:'o'); select path_switch_set('expense', 1, true, true, 'a') is not null as lk2 \gset
select tt.chk('F3 nothing was written by the refused attempt', (select count(*) from bill_payments99 where bill_ref=:'cb14')=0);

-- a 10-2 voucher already carries the cost (approved, same place, month, head, amount 888)
insert into entries (form_code, location_id, serial, entry_date, status, data, flags, check_data, created_by, created_staff)
  values ('10-2', 1, 9901, tt.mo(0), 'approved', '{"lines":[{"head":"repair","to":"gas cylinder","amount":"888","receipt":"yes"}]}', '[]', '{}', :'o', 'st');
select tt.as(:'o'); select set_rule('cost_bill_creates_payment','"auto_cash"') is null as a7 \gset
select tt.as(:'e');
select cost_bill_add(:sg::bigint,'month',tt.mo(0),888,null,'G-88',tt.today(),false,null,null,'b0000000-0000-0000-0000-000000000011'::uuid) ->> 'id' as cb17 \gset
select tt.chk('F4 a 10-2 voucher with the same place / month / head / amount: the auto mode does NOT pay (would count the cost twice), the bill is flagged and stays listed', (select count(*) from bill_payments99 where bill_ref=:'cb17')=0
  and (select dup_entry_id is not null from cost_source_bills where id=:cb17::bigint) and (select count(*) from jsonb_array_elements(bills_without_payment99('cost',null,50)->'rows') x where x->>'ref'=:'cb17')=1);
select bill_pay_record('cost',:'cb17','cash',888) as w3 \gset
select tt.chk('F4 ask: warns form_10_2_matches first, writes nothing', (:'w3'::jsonb->>'needs_confirm')::boolean and (:'w3'::jsonb->'warnings') @> '"form_10_2_matches"'::jsonb and (select count(*) from quick_expenses where amount=888)=0);
select cost_bill_dup_ack(:cb17::bigint, 'this is the second gas cylinder, a different cost')::text as ak \gset
select bill_pay_record('cost',:'cb17','cash',888) ->> 'ok' as w4 \gset
select tt.chk('F4 after the person says "different cost" (cost_bill_dup_ack) the payment is written once', :'w4'='true' and (select count(*) from quick_expenses where amount=888)=1);
select tt.as(:'o'); select set_rule('cost_bill_creates_payment','"off"') is null as a8 \gset

\echo == D1-G purchase bills: default OFF, ask (1000 = 400 + 600), void, keep_credit, auto, credit-terms
select tt.as(:'u');
select save_purchase(null,null,:'sup1',1,'P-1',tt.today(),format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb1 \gset
select post_purchase(:'pb1'::uuid) is not null as pp1 \gset
select tt.chk('G1 default off: posted bill 1000 stays unpaid (today)', (select paid from purchase_bills where id=:'pb1'::uuid)=0 and (select count(*) from supplier_payments)=0 and (select count(*) from bill_payments99 where bill_kind='purchase')=0);
select tt.as(:'o'); select set_rule('purchase_bill_creates_payment','"ask"') is null as pa \gset
select tt.as(:'u');
select tt.chk('G1 info: total 1000, remaining 1000, modes cash/bank/mobile/card', (bill_pay_info99('purchase',:'pb1')->>'total')::numeric=1000 and (bill_pay_info99('purchase',:'pb1')->>'remaining')::numeric=1000 and bill_pay_info99('purchase',:'pb1')->'modes'='["cash","bank","mobile","card"]'::jsonb);
select tt.as(:'n'); select tt.err('G1 no purchase right: cannot read the info', format($$select bill_pay_info99('purchase','%s')$$, :'pb1'), 'not allowed');
select tt.err('G1 no payment grant: cannot record', format($$select bill_pay_record('purchase','%s','cash',10)$$, :'pb1'), 'not allowed');
select tt.as(:'u');
select bill_pay_record('purchase',:'pb1','cash',400,'d0000000-0000-0000-0000-000000000001'::uuid) as q1 \gset
select tt.chk('G2 pay 400 cash: remaining 600; supplier payment tied to the bill; bill paid 400; supplier balance 600', (:'q1'::jsonb->>'remaining')::numeric=600 and (select paid from purchase_bills where id=:'pb1'::uuid)=400
  and (select count(*) from supplier_payments where bill_id=:'pb1'::uuid and amount=400 and mode='cash' and not voided)=1 and _sup_balance(:'sup1'::uuid)=600);
select bill_pay_record('purchase',:'pb1','cash',400,'d0000000-0000-0000-0000-000000000001'::uuid)->>'dup' as qd \gset
select tt.chk('G2 replay with the same client id = dup, one payment', :'qd'='true' and (select count(*) from supplier_payments where bill_id=:'pb1'::uuid)=1 and (select paid from purchase_bills where id=:'pb1'::uuid)=400);
select tt.err('G2 700 > 600 refused', format($$select bill_pay_record('purchase','%s','bank',700)$$, :'pb1'), 'overpaid');
select tt.err('G2 mode other is not a supplier-payment mode', format($$select bill_pay_record('purchase','%s','other',10)$$, :'pb1'), 'bad_mode');
select bill_pay_record('purchase',:'pb1','bank',600,'d0000000-0000-0000-0000-000000000002'::uuid) as q2 \gset
select tt.chk('G3 pay 600 bank: remaining 0, bill paid 1000, due 0, supplier balance 0', (:'q2'::jsonb->>'remaining')::numeric=0 and (select paid from purchase_bills where id=:'pb1'::uuid)=1000 and (select due from purchase_bills where id=:'pb1'::uuid)=0 and _sup_balance(:'sup1'::uuid)=0);
select tt.err('G3 nothing left', format($$select bill_pay_record('purchase','%s','cash',1)$$, :'pb1'), 'nothing_due');
select tt.chk('G3 not in "Bills without payment" any more; supplier_open_bills agrees (nothing open)', (select count(*) from jsonb_array_elements(bills_without_payment99('purchase',null,50)->'rows') x where x->>'ref'=:'pb1')=0
  and not exists (select 1 from supplier_open_bills(:'sup1'::uuid, 1)));
select tt.as(:'o'); select acct_post_pending(false) is not null as pg \gset
select tt.chk('G4 journal: supplier payments debit 1000 in total (2 entries), cash book out 400 cash + 600 bank, balanced', tt.jcnt('supplier_payment')=2 and tt.jd('supplier_payment')=1000 and tt.unbalanced_entries()=0

  and tt.dsum(1,'out','cash','bill')=400 and tt.dsum(1,'out','bank','bill')=600);
-- void of the bill (mode void): both payments voided with it (existing behaviour), link rows void, reversing entries
select void_purchase(:'pb1'::uuid, 'wrong supplier') is not null as vp \gset
select tt.chk('G5 bill voided: both payments voided, links void, supplier balance 0', (select count(*) from supplier_payments where bill_id=:'pb1'::uuid and voided)=2 and (select count(*) from bill_payments99 where bill_ref=:'pb1' and status='void')=2 and _sup_balance(:'sup1'::uuid)=0);
select acct_post_pending(false) is not null as pg2 \gset
select tt.chk('G5 journal: 2 reversing entries for the payments, still balanced', tt.jrev('supplier_payment')=2 and tt.unbalanced_entries()=0);
-- keep_credit: payment stays, becomes supplier credit
select set_rule('bill_void_payment_mode','"keep_credit"') is null as kc \gset
select tt.as(:'u');
select save_purchase(null,null,:'sup3',1,'P-2',tt.today(),format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb2 \gset
select post_purchase(:'pb2'::uuid) is not null as pp2 \gset
select bill_pay_record('purchase',:'pb2','cash',500,'d0000000-0000-0000-0000-000000000003'::uuid) is not null as q3 \gset
select tt.as(:'o');
select void_purchase(:'pb2'::uuid, 'supplier credit please') is not null as vp2 \gset
select tt.chk('G6 keep_credit: payment NOT voided, un-tied from the bill = supplier credit (balance -500); link kept_credit; flag', (select count(*) from supplier_payments where amount=500 and not voided and bill_id is null)=1
  and _sup_balance(:'sup3'::uuid)=-500 and (select status from bill_payments99 where bill_ref=:'pb2')='kept_credit' and exists (select 1 from exceptions where flag_code='bill_pay_kept' and form_code='PURCHASE'));
select set_rule('bill_void_payment_mode','"void"') is null as kv \gset
-- existing rule purchase_void_payments = keep: links say kept_credit although mode is void
select set_rule('purchase_void_payments','"keep"') is null as pk \gset
select tt.as(:'u');
select save_purchase(null,null,:'sup4',1,'P-3',tt.today(),format('[{"item_id":"%s","qty":2,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb3 \gset
select post_purchase(:'pb3'::uuid) is not null as pp3 \gset
select bill_pay_record('purchase',:'pb3','cash',200,'d0000000-0000-0000-0000-000000000004'::uuid) is not null as q4 \gset
select tt.as(:'o');
select void_purchase(:'pb3'::uuid, 'test keep') is not null as vp3 \gset
select tt.chk('G7 existing rule purchase_void_payments=keep: payment stays, link row says kept_credit (no silent mismatch)', (select status from bill_payments99 where bill_ref=:'pb3')='kept_credit' and (select count(*) from supplier_payments where amount=200 and not voided)=1);
select set_rule('purchase_void_payments','"void"') is null as pk2 \gset

\echo == D1-H purchase auto modes
select set_rule('purchase_bill_creates_payment','"auto_cash"') is null as pac \gset
select tt.as(:'u');
select save_purchase(null,null,:'sup1',1,'P-4',tt.today(),format('[{"item_id":"%s","qty":7,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb4 \gset
select tt.chk('H1 a DRAFT never pays (nothing happens before posting)', (select count(*) from bill_payments99 where bill_ref=:'pb4')=0);
select post_purchase(:'pb4'::uuid) is not null as pp4 \gset
select tt.chk('H1 auto_cash on posting: bill 700 paid in cash once; paid 700, due 0; one supplier payment', (select paid from purchase_bills where id=:'pb4'::uuid)=700 and (select count(*) from supplier_payments where bill_id=:'pb4'::uuid and amount=700 and mode='cash')=1
  and (select count(*) from bill_payments99 where bill_ref=:'pb4' and origin='auto')=1);
select tt.chk('H1 supplier balance back to 0 (hand: bill 700 - payment 700; the kept credits belong to other suppliers)', _sup_balance(:'sup1'::uuid)=0 and _sup_balance(:'sup3'::uuid)=-500);
-- paid at posting by the poster -> auto does nothing (no double)
select save_purchase(null,null,:'sup1',1,'P-5',tt.today(),format('[{"item_id":"%s","qty":3,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb5 \gset
select post_purchase(:'pb5'::uuid, '[{"mode":"cash","amount":100}]'::jsonb) is not null as pp5 \gset
select tt.chk('H2 the poster paid 100 at posting: the automatic mode does NOT add another (one payment of 100, paid 100)', (select count(*) from supplier_payments where bill_id=:'pb5'::uuid)=1 and (select paid from purchase_bills where id=:'pb5'::uuid)=100 and (select count(*) from bill_payments99 where bill_ref=:'pb5')=0);
-- credit-terms supplier: never auto
select save_purchase(null,null,:'sup2',1,'P-6',tt.today(),format('[{"item_id":"%s","qty":4,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb6 \gset
select post_purchase(:'pb6'::uuid) is not null as pp6 \gset
select tt.chk('H3 supplier with credit terms (30 days): NOT paid automatically, flag, listed as unpaid 400', (select paid from purchase_bills where id=:'pb6'::uuid)=0 and exists (select 1 from exceptions where flag_code='bill_pay_auto_skipped' and form_code='PURCHASE')
  and (select count(*) from jsonb_array_elements(bills_without_payment99('purchase',null,50)->'rows') x where x->>'ref'=:'pb6' and (x->>'due')::numeric=400)=1);
select tt.as(:'o'); select set_rule('purchase_bill_creates_payment','"auto_by_supplier_default"') is null as pad \gset
select bill_pay_default_set99('supplier', :'sup1', 'bank', false) is not null as dsb \gset
select tt.as(:'u');
select save_purchase(null,null,:'sup1',1,'P-7',tt.today(),format('[{"item_id":"%s","qty":1,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb7 \gset
select post_purchase(:'pb7'::uuid) is not null as pp7 \gset
select tt.chk('H4 auto_by_supplier_default: supplier default bank used (100 bank)', (select mode from supplier_payments where bill_id=:'pb7'::uuid)='bank' and (select paid from purchase_bills where id=:'pb7'::uuid)=100);
select tt.as(:'o'); select set_rule('purchase_bill_creates_payment','"off"') is null as pof \gset
select acct_post_pending(false) is not null as pg3 \gset
select tt.chk('H5 after all purchase payments: journal balanced, each supplier payment counted once (je_source_uq: entries = payments)', tt.unbalanced_entries()=0
  and (select count(*) from supplier_payments where not voided)=(select count(*) from journal_entries e where e.source_type='supplier_payment' and e.reverses_id is null and not exists (select 1 from journal_entries r where r.reverses_id=e.id))
  );

\echo == D1-I payment_recommendation (thresholds are owner-typed; none built in)
select tt.as(:'u');
select save_purchase(null,null,:'sup1',1,'P-8',tt.today(),format('[{"item_id":"%s","qty":3,"unit":"kg","unit_cost":100}]',:'it1')::jsonb) ->> 'id' as pb8 \gset
select post_purchase(:'pb8'::uuid) is not null as pp8 \gset
select tt.chk('I1 no limits typed: recommendation is ask (basis no_numbers) - never invents a number', payment_recommendation('purchase',:'pb8')->>'mode'='ask' and payment_recommendation('purchase',:'pb8')->>'basis'='no_numbers');
select tt.as(:'o');
select set_rule('bill_pay_small_cash_max','500') is null as sm \gset
select set_rule('bill_pay_large_amount','5000') is null as lg \gset
select bill_pay_default_set99('supplier', :'sup1', 'cash', false) is not null as dsc \gset
select tt.as(:'u');
select tt.chk('I2 small (300 <= 500), cash default, no credit: auto_cash', payment_recommendation('purchase',:'pb8')->>'mode'='auto_cash' and payment_recommendation('purchase',:'pb8')->>'basis'='small_cash');
select tt.as(:'o'); select bill_pay_default_set99('supplier', :'sup1', 'bank', false) is not null as dsb2 \gset
select tt.as(:'u');
select tt.chk('I2 small, bank default: auto_bank', payment_recommendation('purchase',:'pb8')->>'mode'='auto_bank');
select tt.chk('I3 credit-terms supplier (bill 400): ask and never_auto, even though small', payment_recommendation('purchase',:'pb6')->>'mode'='ask' and (payment_recommendation('purchase',:'pb6')->>'never_auto')::boolean and payment_recommendation('purchase',:'pb6')->>'basis'='credit');
select tt.as(:'o'); select bill_pay_default_set99('supplier', :'sup1', 'cash', false) is not null as dsc2 \gset
select set_rule('bill_pay_large_amount','250') is null as lg2 \gset
select tt.as(:'u');
select tt.chk('I4 large limit 250: the 300 bill is now "large" -> ask (large beats small)', payment_recommendation('purchase',:'pb8')->>'mode'='ask' and payment_recommendation('purchase',:'pb8')->>'basis'='large');
select tt.as(:'o'); select set_rule('bill_pay_large_amount','5000') is null as lg3 \gset
select tt.as(:'e');
select cost_bill_add(:sg::bigint,'month',tt.mo(5),400,'cash','G-400',tt.today(),false,null,null,'b0000000-0000-0000-0000-00000000000f'::uuid) ->> 'id' as cb15 \gset
select cost_bill_add(:sg::bigint,'month',tt.mo(6),6000,'cash','G-6000',tt.today(),false,null,null,'b0000000-0000-0000-0000-000000000010'::uuid) ->> 'id' as cb16 \gset
select tt.chk('I5 cost bill 400 cash (bill mode cash, small limit 500, no credit): auto_cash; the 6000 bill (large limit 5000): ask; the 600 bank-mode bill: ask', payment_recommendation('cost',:'cb15')->>'mode'='auto_cash'
  and payment_recommendation('cost',:'cb16')->>'mode'='ask' and payment_recommendation('cost',:'cb16')->>'basis'='large' and payment_recommendation('cost',:'cb2')->>'basis'='default');
select tt.chk('I5 reasons exist in 3 languages; English has no Bangla', payment_recommendation('cost',:'cb15') ? 'reason_bn' and payment_recommendation('cost',:'cb15') ? 'reason_mix' and tt.noban(payment_recommendation('cost',:'cb15')->>'reason_en')
  and tt.noban(payment_recommendation('purchase',:'pb6')->>'reason_en') and tt.noban(payment_recommendation('purchase',:'pb8')->>'reason_en'));
select tt.as(:'o'); select set_rule('bill_pay_small_cash_max',null) is null as sm0 \gset
select set_rule('bill_pay_large_amount',null) is null as lg0 \gset
select tt.chk('I6 limits cleared (blank) again = no limits', rule_num('bill_pay_small_cash_max') is null and rule_num('bill_pay_large_amount') is null);

\echo == D1-J immutable link ledger, audit
select tt.err('J1 a link row cannot be deleted', $$delete from bill_payments99$$, 'append_only');
reset role;
select tt.err('J1 nor changed (amount)', $$update bill_payments99 set amount = amount + 1$$, 'append_only');
select tt.err('J1 nor its status moved back to active', $$update bill_payments99 set status='active' where status='void'$$, 'append_only');
select tt.chk('J2 every link row is in the audit log (insert + the close)', (select count(*) from audit_log where table_name='bill_payments99' and action='insert')=(select count(*) from bill_payments99)
  and (select count(*) from audit_log where table_name='bill_pay_defaults99')>=3);
select tt.chk('J3 options99_state (owner) counts unpaid cost / purchase bills', (options99_state()->>'unpaid_cost')::int >= 1 and (options99_state()->>'unpaid_purchase')::int >= 1 and options99_state()->>'cost_bill_creates_payment' = 'off');
select tt.as(:'n'); select tt.err('J3 options99_state is owner only', $$select options99_state()$$, 'not allowed'); select tt.as(:'o');

\echo == D1-K final sweeps for decision 1 (everything above: cost bills, purchase bills, all modes)
select acct_post_pending(false) is not null as pgz \gset
select tt.chk('K1 every journal entry balanced; total debit = total credit', tt.unbalanced_entries()=0 and (select sum(debit) from journal_lines)=(select sum(credit) from journal_lines));
select tt.chk('K2 day book vs journal: no expense / supplier-payment difference in the whole span', not exists (select 1 from jsonb_array_elements(daybook_vs_journal(tt.today()-1, tt.today(), null)->'rows') x where x->>'kind' in ('expense','supplier_payment','bill','supplier')));
select tt.chk('K3 one journal entry per money record (je_source_uq): quick expenses live = entries minus reversed', (select count(*) from quick_expenses where status='done')=
  (select count(*) from journal_entries e where e.source_type='quick_expense' and e.reverses_id is null and not exists (select 1 from journal_entries r where r.reverses_id=e.id)));
select tt.chk('K4 no cost bill, link row or note-only line ever became a journal source', not exists (select 1 from journal_entries where source_type not in (select distinct source_type from journal_entries where source_type in ('quick_expense','supplier_payment','purchase','sale','sale_return','sale_payment','expense_voucher') )
  and (source_type like '%cost%' or source_type like '%bill_pay%' or source_type like '%99%')));
select tt.chk('K5 money records made through the option: every active link has exactly one live money record (or is a note-only line)', not exists (select 1 from bill_payments99 l where l.status='active' and l.money_type='quick_expense'
  and not exists (select 1 from quick_expenses q where q.id::text=l.money_ref and q.status='done'))
  and not exists (select 1 from bill_payments99 l where l.status='active' and l.money_type='supplier_payment' and not exists (select 1 from supplier_payments s where s.id::text=l.money_ref and not s.voided and s.bill_id::text=l.bill_ref)));

\echo == D2 inbox masking: setup (a channel, two messages, one order)
select set_rule('inbox_on','true') is null as ion \gset
select sales_channel_save(null,'fbpage','facebook',null,'FB page',1,null,'PAGE1',true) is not null as ch1 \gset
select id as chf from sales_channels where code='fbpage' \gset
insert into inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, received_at, attachment_ref)
  values (:chf, 1, 'm-1', '01711000111', 'Customer A', 'I want 2 kg sweets, call 01711000111', now(), 'https://x/a.jpg') returning id as m1 \gset
insert into inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, received_at)
  values (:chf, 1, 'm-2', 'psid-77', 'Customer B', 'price?', now()) returning id as m2 \gset
insert into online_orders (order_no, location_id, channel, customer_name, customer_mobile, address, lines, subtotal, delivery_mode)
  values (501, 1, 'phone', 'Customer A', '01711000111', 'House 5, Road 3, Dhaka', '[{"name":"Sweets","qty":2,"price":100}]', 200, 'home') returning id as ord \gset
select tt.as(:'sp');
\echo == M0 default off = today: everything readable by a POS-view person
select tt.chk('M0 inbox_get shows handle, name, text and attachment as they are', inbox_get(:m1)->>'handle'='01711000111' and inbox_get(:m1)->>'name'='Customer A' and inbox_get(:m1)->>'text' like 'I want 2 kg%' and inbox_get(:m1)->>'attachment_ref'='https://x/a.jpg' and not (inbox_get(:m1)->>'masked')::boolean);
select tt.chk('M0 inbox_list likewise', (select e->>'handle' from jsonb_array_elements(inbox_list(1,null,50)) e where (e->>'id')::bigint=:m1)='01711000111');
select tt.chk('M0 online order get / list show mobile, address, name as they are', online_order_get(:'ord'::uuid)->>'customer_mobile'='01711000111' and online_order_get(:'ord'::uuid)->>'address'='House 5, Road 3, Dhaka' and online_order_get(:'ord'::uuid)->>'customer_name'='Customer A'
  and online_orders_list(1,null,null,null,50)->0->>'customer_mobile'='01711000111');
select tt.chk('M0 mode reported off', inbox_get(:m1)->>'pii_mode'='off' and online_order_get(:'ord'::uuid) is not null);
select tt.as(:'o');
select inbox_unmask('message', :m1::text) as u0 \gset
select tt.chk('M0 owner unmask while mode off: ok, nothing logged (nothing was hidden)', (:'u0'::jsonb->>'ok')::boolean and :'u0'::jsonb->>'mode'='off' and not (:'u0'::jsonb->>'logged')::boolean and (select count(*) from inbox_unmask_log99)=0);

\echo == M1 mask_phone
select set_rule('inbox_pii_mode','"mask_phone"') is null as m_1 \gset
select tt.as(:'sp');
select tt.chk('M1 order mobile masked: 11 digits -> 8 dots + last 3 (••••••••111); address and name still shown', online_order_get(:'ord'::uuid)->>'customer_mobile'='••••••••111' and online_order_get(:'ord'::uuid)->>'address'='House 5, Road 3, Dhaka' and online_order_get(:'ord'::uuid)->>'customer_name'='Customer A'
  and online_order_get(:'ord'::uuid)->>'pii_mode'='mask_phone');
select tt.chk('M1 order list mobile masked too', online_orders_list(1,null,null,null,50)->0->>'customer_mobile'='••••••••111' and online_orders_list(1,null,null,null,50)->0->>'pii_mode'='mask_phone');
select tt.chk('M1 message: a PHONE-like handle is masked, name and text shown; a non-phone handle (psid-77) is left alone', inbox_get(:m1)->>'handle'='••••••••111' and inbox_get(:m1)->>'name'='Customer A' and inbox_get(:m1)->>'text' like 'I want 2 kg%'
  and inbox_get(:m2)->>'handle'='psid-77');
select tt.chk('M1 message list masked likewise', (select e->>'handle' from jsonb_array_elements(inbox_list(1,null,50)) e where (e->>'id')::bigint=:m1)='••••••••111');

\echo == M2 mask_phone_address
select tt.as(:'o'); select set_rule('inbox_pii_mode','"mask_phone_address"') is null as m_2 \gset
select tt.as(:'sp');
select tt.chk('M2 address fully hidden (••••), mobile masked, name shown', online_order_get(:'ord'::uuid)->>'address'='••••' and online_order_get(:'ord'::uuid)->>'customer_mobile'='••••••••111' and online_order_get(:'ord'::uuid)->>'customer_name'='Customer A');

\echo == M3 mask_all_pii
select tt.as(:'o'); select set_rule('inbox_pii_mode','"mask_all_pii"') is null as m_3 \gset
select tt.as(:'sp');
select tt.chk('M3 name -> first letter + •••, text and attachment hidden, any handle masked', inbox_get(:m1)->>'name'='C•••' and inbox_get(:m1)->>'text'='••••' and inbox_get(:m1)->>'attachment_ref'='••••' and inbox_get(:m2)->>'handle'='p•••'
  and inbox_get(:m2)->>'name'='C•••' and inbox_get(:m2)->>'text'='••••');
select tt.chk('M3 order: name C•••, mobile and address masked; the order itself (order_no, status, lines) still usable', online_order_get(:'ord'::uuid)->>'customer_name'='C•••' and online_order_get(:'ord'::uuid)->>'customer_mobile'='••••••••111' and online_order_get(:'ord'::uuid)->>'address'='••••'
  and online_order_get(:'ord'::uuid)->>'order_no' is not null and online_order_get(:'ord'::uuid)->>'status'='new');
select tt.chk('M3 list: name masked', online_orders_list(1,null,null,null,50)->0->>'customer_name'='C•••');

\echo == M4 unmask: who may, audit, GUC does not leak
select tt.err('M4 a POS person without grant inbox_unmask cannot reveal', format($$select inbox_unmask('message','%s')$$, :m1), 'not allowed');
select tt.chk('M4 and nothing was logged for the refusal', (select count(*) from inbox_unmask_log99)=0);
select tt.as(:'u'); select tt.err('M4 a person without POS cannot reveal (storekeeper)', format($$select inbox_unmask('message','%s')$$, :m1), 'not allowed');
select tt.as(:'q');
select inbox_unmask('message', :m1::text, 'customer called') as u1 \gset
select tt.chk('M4 authorised person reveals ONE message: real handle, name, text, attachment', (:'u1'::jsonb->>'ok')::boolean and :'u1'::jsonb->'data'->>'handle'='01711000111' and :'u1'::jsonb->'data'->>'name'='Customer A' and :'u1'::jsonb->'data'->>'text' like 'I want 2 kg%'
  and :'u1'::jsonb->'data'->>'attachment_ref'='https://x/a.jpg' and (:'u1'::jsonb->>'logged')::boolean);
select tt.chk('M4 the reveal is in the log: who (user), which message, fields, reason, outcome', (select count(*) from inbox_unmask_log99 where user_id=:'q'::uuid and kind='message' and ref_id=:m1::text and outcome='revealed' and reason='customer called' and fields like 'handle%' and location_id=1)=1);
select tt.chk('M4 and in audit_log (action view, table inbox_unmask, the reason)', (select count(*) from audit_log where table_name='inbox_unmask' and record_id='message:'||:m1::text and user_id=:'q'::uuid and detail->>'reason'='customer called')=1);
select tt.chk('M4 the very next plain read is masked again (the reveal did not leak into the session)', inbox_get(:m1)->>'handle'='••••••••111' and inbox_get(:m1)->>'text'='••••' and online_order_get(:'ord'::uuid)->>'customer_mobile'='••••••••111');
select inbox_unmask('order', :'ord') as u2 \gset
select tt.chk('M4 an order is revealed the same way: mobile, address, name real; logged as kind order', :'u2'::jsonb->'data'->>'customer_mobile'='01711000111' and :'u2'::jsonb->'data'->>'address'='House 5, Road 3, Dhaka' and :'u2'::jsonb->'data'->>'customer_name'='Customer A'
  and (select count(*) from inbox_unmask_log99 where kind='order' and ref_id=:'ord' and outcome='revealed')=1);
select tt.err('M4 bad input', $$select inbox_unmask('thread','1')$$, 'bad_input');
select tt.err('M4 not found', $$select inbox_unmask('message','999999')$$, 'not_found');

\echo == M5 rate limit (owner types it; blank = none; owner not limited)
select tt.as(:'o'); select set_rule('inbox_unmask_daily_max','2') is null as rl \gset
select tt.as(:'q');
select inbox_unmask('message', :m2::text) as u3 \gset
select tt.chk('M5 limit 2 per day: q has used 2 (message + order) -> the 3rd is blocked, nothing revealed', not (:'u3'::jsonb->>'ok')::boolean and :'u3'::jsonb->>'error'='rate_limited' and (:'u3'::jsonb->>'used')::int=2 and (:'u3'::jsonb->>'max')::int=2 and not (:'u3'::jsonb ? 'data'));
select tt.chk('M5 the blocked attempt is logged as blocked; revealed count still 2', (select count(*) from inbox_unmask_log99 where user_id=:'q'::uuid and outcome='blocked')=1 and (select count(*) from inbox_unmask_log99 where user_id=:'q'::uuid and outcome='revealed')=2);
select tt.as(:'o');
select inbox_unmask('message', :m2::text) as u4 \gset
select tt.chk('M5 the owner is not limited', (:'u4'::jsonb->>'ok')::boolean and :'u4'::jsonb->'data'->>'name'='Customer B');
select set_user_grant(:'r'::uuid,'inbox_unmask') is null as g6 \gset
select tt.as(:'r');
select inbox_unmask('message', :m2::text) as u5 \gset
select tt.chk('M5 another person has his own counter (r reveals once: ok)', (:'u5'::jsonb->>'ok')::boolean);
select tt.as(:'o'); select set_rule('inbox_unmask_daily_max',null) is null as rl0 \gset
select tt.as(:'q');
select inbox_unmask('message', :m2::text) as u6 \gset
select tt.chk('M5 blank limit = none: q reveals again', (:'u6'::jsonb->>'ok')::boolean and rule_num('inbox_unmask_daily_max') is null);
select tt.as(:'o');
select tt.err('M5 the minimum of the rule is 1 (0 would mean "never"): refused', $$select set_rule('inbox_unmask_daily_max','0')$$, 'bad_value');

\echo == M6 the old guard (inbox_pii_guard_on) still works on top
select set_rule('inbox_pii_guard_on','true') is null as gon \gset
delete from rule_grants where role_code='salesperson' and grant_code='inbox_contact_view';
select tt.as(:'sp');
select tt.chk('M6 guard on, no contact grant: nothing at all (null) as before; masked flag true', inbox_get(:m1)->>'text' is null and (inbox_get(:m1)->>'masked')::boolean and (online_order_get(:'ord'::uuid) ? 'customer_mobile') is false);
select tt.as(:'q');
select tt.err('M6 a grant holder WITHOUT the contact right cannot reveal (both rights are needed)', format($$select inbox_unmask('message','%s')$$, :m1), 'not allowed');
select tt.as(:'o');
select inbox_unmask('message', :m1::text) as u7 \gset
select tt.chk('M6 owner reveals', (:'u7'::jsonb->>'ok')::boolean and :'u7'::jsonb->'data'->>'handle'='01711000111');
select set_rule('inbox_pii_guard_on','false') is null as goff \gset
insert into rule_grants (role_code, grant_code, allowed) values ('salesperson','inbox_contact_view',true) on conflict (role_code, grant_code) do update set allowed=true;

\echo == M7 log access, back to off, language
select tt.chk('M7 owner reads the log list (who, when, which)', jsonb_array_length(inbox_unmask_log_list99(100,null)) >= 5 and (inbox_unmask_log_list99(100,:'q'::uuid)->0->>'staff') is not null);
select tt.as(:'q'); select tt.err('M7 others cannot read the log list', $$select inbox_unmask_log_list99(10,null)$$, 'not allowed');
set role authenticated;
select tt.chk('M7 and not the table either (RLS: owner only)', (select count(*) from inbox_unmask_log99)=0);
select tt.err('M7 browser cannot write the log', $$insert into inbox_unmask_log99 (kind, ref_id, outcome) values ('message','1','revealed')$$, 'permission denied');
reset role;
select tt.chk('M7 the log cannot be changed or deleted', true);
select tt.err('M7 log is append-only (delete)', $$delete from inbox_unmask_log99$$, 'append_only');
select tt.err('M7 log is append-only (update)', $$update inbox_unmask_log99 set outcome='blocked'$$, 'append_only');
select tt.as(:'o'); select set_rule('inbox_pii_mode','"off"') is null as moff \gset
select tt.as(:'sp');
select tt.chk('M7 mode off again: everything readable as today', online_order_get(:'ord'::uuid)->>'customer_mobile'='01711000111' and inbox_get(:m1)->>'text' like 'I want 2 kg%');
select tt.chk('M7 direct column read of phone / address is NOT changed by the mode (documented; inbox_pii_guard_on does that)', has_column_privilege('authenticated','public.online_orders','customer_mobile','select'));

\echo == L language rule and recommendations
select tt.as(:'o');
select tt.chk('L1 all new rules have 3 languages; English labels/hints have no Bangla', (select bool_and(label_bn is not null and label_mix is not null and label_en is not null and tt.noban(label_en) and tt.noban(coalesce(hint_en,''))) from rules where key in ('cost_bill_creates_payment','purchase_bill_creates_payment','bill_void_payment_mode','bill_pay_auto_credit_ok','bill_pay_large_amount','bill_pay_small_cash_max','inbox_pii_mode','inbox_unmask_daily_max')));
select tt.chk('L1 grant label (English) has no Bangla', (select tt.noban(label_en) from grant_defs where grant_code='inbox_unmask'));
select tt.chk('L1 recommendation reasons: bn / mix / en present; English has no Bangla', (select bool_and(reason_bn is not null and reason_mix is not null and reason_en is not null and tt.noban(reason_en)) from setup_rec_defs81 where phase='99'));
select tt.chk('L1 the reasons say WHY (not empty) for the two main recommendations', (select length(reason_en) > 80 from setup_rec_defs81 where code='inbox_pii_mode') and (select length(reason_en) > 80 from setup_rec_defs81 where code='cost_bill_creates_payment'));
select tt.chk('L1 recommendations do not invent numbers: the three number rows carry NO recommended value', (select count(*) from setup_rec_defs81 where code in ('bill_pay_large_amount','bill_pay_small_cash_max','inbox_unmask_daily_max') and rec_value is null)=3);
select tt.chk('L1 English texts of the flags written by the option have no Bangla', (select bool_and(tt.noban(text->>'en')) from exceptions where flag_code like 'bill_pay%'));
select tt.chk('L2 setup_recommend_apply could apply them but only on the owner''s tap: nothing changed by the build', rule_txt('cost_bill_creates_payment')='off' and rule_txt('purchase_bill_creates_payment')='off' and rule_txt('inbox_pii_mode')='off');
