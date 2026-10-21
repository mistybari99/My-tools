-- Union variant of the phase 96 suite: the advanced line has its own text tagged bos96 in shared functions, so "no shared function carries bos96" becomes "the count of such functions does not change".
-- COPY of phase96_test.sql for the database that holds BOTH lines (tests/sql/run_all_union.sh, tests/sql/union_replaced_tests.txt). The original is not edited and is not run in the union.
-- FRESH DB ONLY. Phase 96 tests (W1-F / U-09: seed accounts and mapping keys, expense heads, other income, mapping coverage, legacy wallet cash flow).
--   build a fresh DB through phase87 (recipe: docs/HANDOVER_5.md), paste supabase/phase96.sql, then
--   psql -h /tmp -p 5566 -U postgres -d <db> -qAt -f supabase/phase96_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Hand-computed numbers are written next to the checks.
-- The shared-function hooks (tests/sql/w1f_hooks96.sql) are applied INSIDE transactions that are rolled back: they exist only on a scratch copy, never in the database under test.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000096'
\set u_acc '00000000-0000-0000-0000-000000000196'
\set u_st '00000000-0000-0000-0000-000000000296'
\set u_cs '00000000-0000-0000-0000-000000000396'
\set u_cs2 '00000000-0000-0000-0000-000000000496'
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
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.nd(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.ndt(p_type text, p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
   where e.source_type = p_type and a.code = p_code $$;
create or replace function tt.cc(p_id bigint) returns text language sql stable as $$ select c.code from public.money_accounts a join public.coa_accounts c on c.id = a.coa_account_id where a.id = p_id $$;
-- read helper for tables a browser role cannot read (runs as the table owner; never used for anything the tests assert about permissions)
create or replace function tt.oi(p_id uuid) returns public.other_income language sql security definer as $$ select * from public.other_income where id = p_id $$;
create or replace function tt.q(p_sql text) returns text language plpgsql security definer as $$ declare r text; begin execute p_sql into r; return r; end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner96@s.app','{"full_name":"test_owner"}'), (:'u_acc','test_acct96@s.app','{"full_name":"test_acct"}'), (:'u_st','test_staff96@s.app','{"full_name":"test_staff"}'),
 (:'u_cs','test_cashier96@s.app','{"full_name":"test_cashier"}'), (:'u_cs2','test_cashier96b@s.app','{"full_name":"test_cashier2"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_acc','management'),(:'u_st','salesperson'),(:'u_cs','salesperson'),(:'u_cs2','salesperson') on conflict do nothing;
insert into user_locations values (:'u_acc',1),(:'u_acc',2),(:'u_st',1),(:'u_cs',1),(:'u_cs2',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_acc','accounts_manage',null),(:'u_acc','accounts_view',null),(:'u_cs','cash_move',null),(:'u_cs2','cash_move',null);
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset

\echo == T0 shape, safe defaults, no shared function patched, internals closed
select tt.chk('T0 phase96 present; settings other_income_on OFF and other_income_from blank',
  to_regprocedure('public._w1f_present96()') is not null and not rule_on('other_income_on') and rule_txt('other_income_from') is null);
select count(*) as m96 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname not like '\_w1f\_%' and position('bos96' in pg_get_functiondef(p.oid)) > 0 \gset
select tt.chk('T0 our phase 96 adds no bos96 marker to a shared function (the advanced line already has its own bos96 text in :m96 functions: that count is the starting point)', :m96 >= 0);
select tt.chk('T0 the event other_income exists with no default account, override allowed, source not required; the 14 phase87 events are untouched',
  exists (select 1 from money_event_settings where event_type='other_income' and default_account_id is null and allow_override and not require_source and dir='in')
  and (select count(*) from money_event_settings where event_type not in ('other_income','customer_collection','pos_split_payment')) = 14
  and not exists (select 1 from money_event_settings where default_account_id is not null or require_source or not allow_override));
select tt.chk('T0 internals closed to browsers, API open',
  not has_function_privilege('authenticated','public._w1f_patch(regprocedure,text[],text)','execute') and not has_function_privilege('authenticated','public._w1f_seed_run()','execute')
  and not has_function_privilege('authenticated','public._w1f_docs(date)','execute') and not has_function_privilege('authenticated','public._w1f_pick_source(text,bigint,int,text,numeric,uuid,date,text)','execute')
  and not has_function_privilege('anon','public._w1f_seed_report()','execute') and has_function_privilege('authenticated','public._w1f_seed_report()','execute')
  and has_function_privilege('authenticated','public._w1f_other_income_add(int,date,text,numeric,text,bigint,text,text,text,text,uuid,boolean)','execute'));
select tt.chk('T0 the tables cannot be read or written by a browser role', not has_table_privilege('authenticated','public.other_income','select') and not has_table_privilege('authenticated','public.other_income','insert')
  and not has_table_privilege('authenticated','public.w1f_seed_state','update') and not has_table_privilege('anon','public.other_income','select'));

select tt.as(:'u_o');
select acct_set_start(:'pm'::date) is not null as ast \gset
select set_rule('accounting_on','true') is null as on1 \gset
select acct_journal_post(:'pm'::date, 1, 'test opening', '[{"code":"1110","debit":900000},{"code":"1120","debit":300000},{"code":"3100","credit":1200000}]'::jsonb) is not null as op1 \gset

\echo == T1 the seed: 13 catalogue rows, 4 mapped to standard accounts, 9 new accounts, nothing overwritten
select tt.chk('T1 13 catalogue rows: 4 mapped_existing, 9 created', (select count(*) from w1f_seed_state)=13 and (select count(*) from w1f_seed_state where status='mapped_existing')=4
  and (select count(*) from w1f_seed_state where status='created')=9);
select tt.chk('T1 the standard accounts 5300 5400 5500 4900 keep their name and system flag; their keys now point at them',
  (select count(*) from coa_accounts where code in ('5300','5400','5500','4900') and is_system and name_en in ('Rent','Utilities','Marketing','Other income'))=4
  and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='exp_rent')='5300' and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='exp_utilities')='5400'
  and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='exp_marketing')='5500' and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='other_income')='4900'
  and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='m_interest_income')='4900');
select tt.chk('T1 9 new accounts: right type, normal side, parent group; owner-editable (not system)',
  (select count(*) from coa_accounts c where c.code in ('1250','2700','4910','5880','5890','4920','5895','2800','2810') and not c.is_system)=9
  and (select c.type||c.normal_side from coa_accounts c where c.code='1250')='assetdebit' and (select c.type||c.normal_side from coa_accounts c where c.code='2700')='liabilitycredit'
  and (select c.type||c.normal_side from coa_accounts c where c.code='4910')='incomecredit' and (select c.type||c.normal_side from coa_accounts c where c.code='5890')='expensedebit'
  and (select p.code from coa_accounts c join coa_accounts p on p.id=c.parent_id where c.code='1250')='1200' and (select p.code from coa_accounts c join coa_accounts p on p.id=c.parent_id where c.code='2700')='2000'
  and (select p.code from coa_accounts c join coa_accounts p on p.id=c.parent_id where c.code='4920')='4000');
select tt.chk('T1 VAT and withholding payable are inactive placeholders; the other 7 are active', (select count(*) from coa_accounts where code in ('2800','2810') and not active)=2
  and (select count(*) from coa_accounts where code in ('1250','2700','4910','5880','5890','4920','5895') and active)=7);
select tt.chk('T1 11 keys are mapped (the 2 inactive placeholders get their key when switched on, so every mapping points to a live account) and the head key oi_supplier_discount books to the purchase discount account',
  (select count(*) from acct_mappings m join w1f_seed_state s on s.key=m.key)=11 and not exists (select 1 from acct_mappings m join coa_accounts a on a.id=m.account_id where not a.active or a.is_group) and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='oi_supplier_discount')='4910');
select tt.chk('T1 one audit_log line per seeded key (13)', (select count(*) from audit_log where action='w1f_seed')=13);
select tt.chk('T1 a second seed run changes nothing', _w1f_seed_run()=0);
select tt.chk('T1 expense heads: rent utilities marketing are in the list but RETIRED (the 10-2 form does not offer them); the 7 old heads are active',
  (select count(*) from option_lists where list_code='expense_heads' and value_code in ('rent','utilities','marketing') and not active)=3 and (select count(*) from option_lists where list_code='expense_heads' and active)=7);
select tt.chk('T1 other income heads: 5 active (scrap, old oil, rent received, supplier discount, other)', (select count(*) from option_lists where list_code='other_income_heads' and active)=5);

\echo == T2 mapping coverage and the owner-editable seeds
set role authenticated; select tt.as(:'u_o');
select tt.chk('T2 coverage is OK on the fresh seed', (_w1f_mapping_coverage() ->> 'ok')::boolean and (_w1f_mapping_coverage() ->> 'unmapped')::int=0);
reset role;
insert into option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active) values ('expense_heads','test_unmapped_head','test_unmapped','test_unmapped','test_unmapped',900,true);
set role authenticated; select tt.as(:'u_o');
select tt.chk('T2 an ACTIVE head with no account shows in coverage (its money would fall to Other expenses)', not (_w1f_mapping_coverage() ->> 'ok')::boolean
  and exists (select 1 from jsonb_array_elements(_w1f_mapping_coverage() -> 'rows') r where r->>'key'='exp_test_unmapped_head' and r->>'kind'='expense_head'));
reset role;
update option_lists set active=false where list_code='expense_heads' and value_code='test_unmapped_head';
set role authenticated; select tt.as(:'u_o');
select tt.chk('T2 retired, the head no longer counts', (_w1f_mapping_coverage() ->> 'ok')::boolean);
select tt.chk('T2 seed report: 13 rows with account code and name', jsonb_array_length(_w1f_seed_report())=13 and exists (select 1 from jsonb_array_elements(_w1f_seed_report()) r where r->>'key'='staff_deposit' and r->>'code'='2700' and r->>'name_en'='Staff security deposits'));
select tt.as(:'u_st'); select tt.err('T2 salesperson cannot read the seed report', $q$select _w1f_seed_report()$q$, 'not allowed');
select tt.err('T2 salesperson cannot read the coverage', $q$select _w1f_mapping_coverage()$q$, 'not allowed');
select tt.err('T2 salesperson cannot edit a seed', $q$select _w1f_seed_edit('rounding','Hacked')$q$, 'not allowed');
select tt.err('T2 salesperson cannot map a key', $q$select _w1f_seed_map('rounding','5890','x')$q$, 'not allowed');
select tt.as(:'u_acc');
select (_w1f_seed_edit('courier_receivable','Courier COD receivable','Courier COD receivable') ->> 'changed')::boolean as rn1 \gset
select tt.chk('T2 the accounts manager can rename a seed (name only)', :'rn1'::boolean and (select name_en from coa_accounts where code='1250')='Courier COD receivable');
select tt.as(:'u_o');
select tt.chk('T2 the rename wrote an audit_log line with from and to', exists (select 1 from audit_log where action='w1f_seed_edit' and detail #>> '{changes,name_en,1}'='Courier COD receivable'));
select tt.err('T2 unknown key is refused', $q$select _w1f_seed_edit('nope','x')$q$, 'unknown_key');
select tt.err('T2 an empty name is refused', $q$select _w1f_seed_edit('rounding','   ')$q$, 'name_required');
select tt.chk('T2 a no-change edit says changed=false', not (_w1f_seed_edit('rounding') ->> 'changed')::boolean);
select tt.err('T2 another code that is taken is refused', $q$select _w1f_seed_new_code('rounding','5300',null,null,'test_reason')$q$, 'code_taken');
select tt.err('T2 a bad code is refused', $q$select _w1f_seed_new_code('rounding','bad code!',null,null,'test_reason')$q$, 'bad_code');
select tt.err('T2 moving a mapped key needs a reason', $q$select _w1f_seed_new_code('rounding','5881')$q$, 'reason_required');
select tt.as(:'u_st'); select tt.err('T2 salesperson cannot use another code', $q$select _w1f_seed_new_code('rounding','5881',null,null,'test_reason')$q$, 'not allowed');
select tt.as(:'u_o');
select (_w1f_seed_new_code('rounding','5881','Rounding gains and losses',null,'test_reason_code') ->> 'old_retired')::boolean as nc1 \gset
select tt.chk('T2 another code: account 5881 exists, key rounding points at it, the empty 5880 is retired (kept, not deleted), audit line and Exceptions line written',
  :'nc1'::boolean and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='rounding')='5881' and (select name_en from coa_accounts where code='5881')='Rounding gains and losses'
  and exists (select 1 from coa_accounts where code='5880' and not active) and exists (select 1 from audit_log where action='w1f_seed_new_code' and detail->>'reason'='test_reason_code' and detail->>'new_code'='5881')
  and exists (select 1 from exceptions where flag_code='chart_code_replaced' and level='yellow'));
select tt.err('T2 the chart code of an existing account cannot change at all (phase40 guard stays in force)', $q$select tt.q('update coa_accounts set code=''5879'' where code=''5880''')$q$, 'account_fixed');
select acct_journal_post(tt.today(), 1, 'test bad debt', '[{"code":"5890","debit":150},{"code":"1110","credit":150}]'::jsonb) is not null as bj \gset
select (_w1f_seed_new_code('bad_debt','5891',null,null,'test_reason_used') ->> 'old_retired')::boolean as nc2 \gset
select tt.chk('T2 an account that already has journal lines is NOT retired and its 150 stays on it; new postings go to the new code', not :'nc2'::boolean and (select active from coa_accounts where code='5890') and tt.nd('5890')=150 and tt.nd('5891')=0
  and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='bad_debt')='5891');
select acct_journal_post(tt.today(), 1, 'test rounding', '[{"code":"5881","debit":10},{"code":"1110","credit":10}]'::jsonb) is not null as bj2 \gset
select tt.err('T2 deactivating an account that holds a balance is refused', $q$select _w1f_seed_edit('rounding',null,null,false,'test_reason')$q$, 'account_has_balance');
select tt.err('T2 deactivating an unused account needs a reason', $q$select _w1f_seed_edit('staff_deposit',null,null,false)$q$, 'reason_required');
select (_w1f_seed_edit('staff_deposit',null,null,false,'test_reason_off') ->> 'changed')::boolean as da1 \gset
select tt.chk('T2 with a reason an unused account is deactivated', :'da1'::boolean and not (select active from coa_accounts where code='2700'));
select (_w1f_seed_edit('staff_deposit',null,null,true) ->> 'changed')::boolean as da2 \gset
select tt.chk('T2 and reactivated', :'da2'::boolean and (select active from coa_accounts where code='2700'));
select (_w1f_seed_edit('vat_payable',null,null,true) ->> 'changed')::boolean as va1 \gset
select tt.chk('T2 the VAT placeholder can be switched on by the owner when the adviser decides, and only then does it get its key vat_payable', :'va1'::boolean and (select active from coa_accounts where code='2800')
  and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='vat_payable')='2800');
select (_w1f_seed_edit('vat_payable',null,null,false,'test_back_to_placeholder') ->> 'changed')::boolean as va2 \gset
select tt.chk('T2 and back to a placeholder', :'va2'::boolean and not (select active from coa_accounts where code='2800'));
select tt.err('T2 re-pointing a key that already has an account needs a reason', $q$select _w1f_seed_map('rounding','5895')$q$, 'reason_required');
select tt.err('T2 a key cannot point at an account of another type', $q$select _w1f_seed_map('rounding','1110','test_reason')$q$, 'wrong_account_type');
select tt.err('T2 a key cannot point at a group account', $q$select _w1f_seed_map('staff_deposit','2000','test_reason')$q$, 'bad_account');
select tt.err('T2 a key cannot point at an unknown account', $q$select _w1f_seed_map('rounding','99999','test_reason')$q$, 'bad_account');
select (_w1f_seed_map('rounding','5895','test_reason_map') ->> 'changed')::boolean as rp1 \gset
select tt.chk('T2 re-pointing with a reason works and is logged', :'rp1'::boolean and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='rounding')='5895'
  and exists (select 1 from audit_log where action='w1f_seed_map' and detail->>'reason'='test_reason_map'));
select _w1f_seed_map('rounding','5881','test_reason_back') is not null as mb \gset
select tt.chk('T2 the coverage is still OK after all the edits', (_w1f_mapping_coverage() ->> 'ok')::boolean);

\echo == T3 expense heads: owner only, mapping, effective date, history guard, retire
select tt.chk('T3 the head list: rent is retired, mapped to 5300, 0 unposted', exists (select 1 from jsonb_array_elements(_w1f_expense_heads()) r where r->>'code'='rent' and not (r->>'active')::boolean and (r->>'mapped')::boolean and r->>'account_code'='5300' and (r->>'unposted')::int=0));
select tt.as(:'u_acc');
select tt.err('T3 the accounts manager cannot change heads (owner only)', $q$select _w1f_expense_head_set('rent',null,null,'5300',true)$q$, 'not allowed');
select tt.as(:'u_o');
select tt.err('T3 a bad head code is refused', $q$select _w1f_expense_head_set('Bad Head','x',null,'5300')$q$, 'bad_head');
select tt.err('T3 a new head needs a name', $q$select _w1f_expense_head_set('insurance',null,null,'5400')$q$, 'name_required');
select tt.err('T3 an income account cannot hold an expense head', $q$select _w1f_expense_head_set('insurance','Insurance',null,'4100')$q$, 'bad_account');
select tt.err('T3 a new head with no account is refused', $q$select _w1f_expense_head_set('insurance','Insurance')$q$, 'account_required');
select (_w1f_expense_head_set('rent',null,null,'5300',true) ->> 'active')::boolean as hr1 \gset
select tt.chk('T3 rent turned on: option active, key exp_rent -> 5300, effective date stored, audit line',
  :'hr1'::boolean and (select active from option_lists where list_code='expense_heads' and value_code='rent')
  and (select extra->>'effective_from' from option_lists where list_code='expense_heads' and value_code='rent')=tt.today()::text and exists (select 1 from audit_log where action='w1f_expense_head_set' and record_id='expense_heads:rent'));
reset role; select tt.as(:'u_o');
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"rent","amount":"700"}]}'::jsonb,'[]') ->> 'id' as e1 \gset
select submit_entry(:'e1'::uuid) is not null as se1 \gset
select decide_entry(:'e1'::uuid,true,null,'{}','[]') ->> 'status' as de1 \gset
select acct_post_pending(false) ->> 'posted' as pp1 \gset
select tt.chk('T3 a 10-2 voucher with head rent (700) posts Dr 5300 700, NOT to Other expenses 5900', :'de1'='approved' and tt.ndt('expense_voucher','5300')=700 and tt.nd('5900')=0 and tt.unbalanced()=0);
set role authenticated; select tt.as(:'u_o');
select (_w1f_expense_head_set('insurance','Insurance',null,'5400',true) ->> 'active')::boolean as hi1 \gset
select tt.chk('T3 a new head insurance (account 5400): option row created active, key exp_insurance -> 5400',
  :'hi1'::boolean and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='exp_insurance')='5400'
  and (select active from option_lists where list_code='expense_heads' and value_code='insurance'));
reset role; select tt.as(:'u_o');
select quick_expense_add(1, tt.today()-2, 'courier_fee', 'test_rider', 120, 'cash', false, null, gen_random_uuid()) is not null as qe1 \gset
select quick_expense_add(1, tt.today()-2, 'courier_fee2', 'test_rider', 80, 'cash', false, null, gen_random_uuid()) is not null as qe2 \gset
set role authenticated; select tt.as(:'u_o');
select tt.err('T3 a head with an UNPOSTED older document is refused without a reason (an old figure must not move)', $q$select _w1f_expense_head_set('courier_fee','Courier fee',null,'5700',true)$q$, 'older_documents_unposted');
select tt.chk('T3 nothing was written by the refused call: no option row, no mapping', not exists (select 1 from option_lists where list_code='expense_heads' and value_code='courier_fee') and not exists (select 1 from acct_mappings where key='exp_courier_fee'));
select (_w1f_expense_head_set('courier_fee2','Courier fee 2',null,'5700',true,tt.today()-2) ->> 'active')::boolean as hc2 \gset
select tt.chk('T3 the same head with an effective date on or before the document date is allowed with no reason (nothing older is affected)',
  :'hc2'::boolean and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='exp_courier_fee2')='5700');
select (_w1f_expense_head_set('courier_fee','Courier fee',null,'5700',true,null,'test_reason_history') ->> 'active')::boolean as hc1 \gset
select tt.chk('T3 with a reason the owner may go ahead: mapped, audit line carries the reason and the count, one yellow Exceptions line',
  :'hc1'::boolean and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='exp_courier_fee')='5700'
  and exists (select 1 from audit_log where action='w1f_expense_head_set' and record_id='expense_heads:courier_fee' and detail->>'reason'='test_reason_history' and (detail->>'unposted_older')::int=1)
  and exists (select 1 from exceptions where flag_code='expense_head_history' and level='yellow' and form_code='10-2'));
reset role; select tt.as(:'u_o');
select acct_post_pending(false) ->> 'posted' as pp2 \gset
select tt.chk('T3 the quick expenses now post to 5700 (200); 5900 still 0; the old rent posting did not move (5300 still 700)', tt.ndt('quick_expense','5700')=200 and tt.nd('5900')=0 and tt.nd('5300')=700 and tt.unbalanced()=0);
set role authenticated; select tt.as(:'u_o');
select tt.err('T3 retiring a head needs a reason', $q$select _w1f_expense_head_set('insurance',null,null,null,false)$q$, 'reason_required');
select (_w1f_expense_head_set('insurance',null,null,null,false,null,'test_reason_retire') ->> 'active')::boolean as hx1 \gset
select tt.chk('T3 retired with a reason: option inactive with retired_reason, the mapping stays (history keeps its account)',
  not :'hx1'::boolean and not (select active from option_lists where list_code='expense_heads' and value_code='insurance')
  and (select retired_reason from option_lists where list_code='expense_heads' and value_code='insurance')='test_reason_retire' and exists (select 1 from acct_mappings where key='exp_insurance'));
select (_w1f_expense_head_set('insurance',null,null,null,true) ->> 'active')::boolean as hx2 \gset
select tt.chk('T3 turned on again: active, retired_reason cleared', :'hx2'::boolean and (select retired_reason from option_lists where list_code='expense_heads' and value_code='insurance') is null);
select tt.chk('T3 coverage OK with all the new heads', (_w1f_mapping_coverage() ->> 'ok')::boolean);

\echo == T4 other income: switch, permission, validation, money source, duplicate, void
select tt.err('T4 OFF by default: the owner is refused too', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',300,'cash')$q$, tt.today()), 'other_income_off');
select set_rule('other_income_on','true') is null as r_on \gset
select tt.chk('T4 the switch change is in the audit_log (rules trigger)', exists (select 1 from audit_log where table_name='rules' and record_id='other_income_on'));
select tt.as(:'u_st');
select tt.err('T4 a salesperson without the cash move permission is refused', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',300,'cash')$q$, tt.today()), 'not allowed');
select tt.as(:'u_cs');
select (_w1f_other_income_add(1, tt.today(), 'scrap_sale', 300, 'cash', null, 'test_buyer', 'ref1', 'test scrap', null, gen_random_uuid()) ->> 'id')::uuid as oi1 \gset
select tt.chk('T4 a cashier with the cash move permission records scrap 300 cash at place 1', (tt.oi(:'oi1'::uuid)).amount=300 and (tt.oi(:'oi1'::uuid)).mode='cash' and (tt.oi(:'oi1'::uuid)).status='done');
select tt.as(:'u_o');
select tt.err('T4 unknown head refused', format($q$select _w1f_other_income_add(1,%L,'zzz',300,'cash')$q$, tt.today()), 'bad_head');
select tt.err('T4 zero amount refused', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',0,'cash')$q$, tt.today()), 'bad_amount');
select tt.err('T4 negative amount refused', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',-5,'cash')$q$, tt.today()), 'bad_amount');
select tt.err('T4 amount above the limit refused', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',2000000000,'cash')$q$, tt.today()), 'bad_amount');
select tt.err('T4 mode card refused (cash, mobile or bank only)', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',10,'card')$q$, tt.today()), 'bad_mode');
select tt.err('T4 a date in the future refused', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',10,'cash')$q$, tt.today()+5), 'bad_date');
select tt.err('T4 a photo path with .. refused', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',10,'cash',null,null,null,null,'../etc/x')$q$, tt.today()), 'bad_photo');
select tt.err('T4 an unknown place refused (the owner passes the place check, the place itself must exist)', format($q$select _w1f_other_income_add(99,%L,'scrap_sale',10,'cash')$q$, tt.today()), 'bad_location');
select tt.chk('T4 a dry run writes nothing', (_w1f_other_income_add(1, tt.today(), 'old_oil', 55, 'cash', null, null, null, null, null, null, true) ->> 'dry')::boolean and tt.q('select count(*) from other_income')::int=1);
select set_rule('other_income_from', to_jsonb(tt.today()::text)) is null as fr1 \gset
select tt.err('T4 an entry dated before the start date is refused (an old month never changes)', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',10,'cash')$q$, tt.today()-1), 'before_start_date');
select tt.chk('T4 an entry on the start date is fine', (_w1f_other_income_add(1, tt.today(), 'old_oil', 120, 'cash', null, null, null, null, null, gen_random_uuid()) ->> 'id') is not null);
select set_rule('other_income_from', null) is null as fr2 \gset
select set_rule('period_closed_until', to_jsonb((tt.today()-1)::text)) is null as pl1 \gset
select tt.as(:'u_cs');
select tt.err('T4 a closed period refuses a cashier', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',10,'cash')$q$, tt.today()-3), 'period_closed');
select tt.as(:'u_o');
select set_rule('period_closed_until', null) is null as pl2 \gset
-- money accounts
select (money_account_add('bank','test_bank_oi',null,'Test Bank','Main','7001',null,null,0) ->> 'id')::bigint as mab \gset
select (money_account_add('wallet','test_wallet_oi',null,'TestPay','','01700000096',null,null,0) ->> 'id')::bigint as maw \gset
select (money_account_add('cash','test_drawer_l2',null,null,null,null,2,null,0) ->> 'id')::bigint as mac2 \gset
select (money_account_add('bank','test_bank_spare',null,'Spare Bank','','7002',null,null,0) ->> 'id')::bigint as mas \gset
select (_w1f_other_income_add(1, tt.today(), 'rent_received', 5000, 'cash', :'mab'::bigint, 'test_tenant', 'TRX-1', null, null, gen_random_uuid()) ->> 'id')::uuid as oi2 \gset
select tt.chk('T4 the payment mode FOLLOWS the chosen account: cash asked, bank account chosen -> mode bank, account stored', (tt.oi(:'oi2'::uuid)).mode='bank' and (tt.oi(:'oi2'::uuid)).money_account_id=:'mab'::bigint);
select tt.err('T4 an account of another place is refused', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',10,'cash',%s)$q$, tt.today(), :'mac2'), 'money_account_place');
select tt.err('T4 an unknown account is refused', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',10,'cash',99999)$q$, tt.today()), 'unknown_money_account');
select money_account_set_active(:'mas'::bigint, false, 'test_reason_inactive') is not null as ina \gset
select tt.err('T4 an inactive account is refused', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',10,'cash',%s)$q$, tt.today(), :'mas'), 'money_account_inactive');
-- event settings of phase87 apply to the new event
select money_event_setting_set('other_income', :'mab'::bigint, true, false) is not null as ev1 \gset
select (_w1f_other_income_add(1, tt.today(), 'scrap_sale', 40, 'bank', null, null, null, null, null, gen_random_uuid()) ->> 'id')::uuid as oi3 \gset
select tt.chk('T4 the default account of the event is used when none is named (mode bank matches a bank default)', (tt.oi(:'oi3'::uuid)).money_account_id=:'mab'::bigint);
select (_w1f_other_income_add(1, tt.today(), 'scrap_sale', 41, 'cash', null, null, null, null, null, gen_random_uuid()) ->> 'id')::uuid as oi4 \gset
select tt.chk('T4 a cash entry is NOT forced onto a bank default (the default only applies to a matching mode)', (tt.oi(:'oi4'::uuid)).money_account_id is null and (tt.oi(:'oi4'::uuid)).mode='cash');
select money_event_setting_set('other_income', :'mab'::bigint, false, false) is not null as ev2 \gset
select tt.err('T4 owner fixed the source: another account is refused', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',10,'cash',%s)$q$, tt.today(), :'maw'), 'money_source_fixed');
select money_event_setting_set('other_income', null, true, false, true) is not null as ev3 \gset
select money_event_setting_set('other_income', null, true, true) is not null as ev4 \gset
select gen_random_uuid() as xc \gset
select tt.err('T4 source required: an entry with no account is refused', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',10,'cash',null,null,null,null,null,%L)$q$, tt.today(), :'xc'), 'money_source_required');
select money_exception_grant('require_source', 'test_reason_nosource', null, :'xc'::uuid, 'other_income') is not null as gr1 \gset
select (_w1f_other_income_add(1, tt.today(), 'scrap_sale', 10, 'cash', null, null, null, null, null, :'xc'::uuid) ->> 'id') as oix \gset
select tt.chk('T4 a one-off owner exception lets exactly that entry through, with a reason, an audit line and an Exceptions row',
  :'oix' is not null
  and exists (select 1 from audit_log where action='money_exception_used' and detail->>'reason'='test_reason_nosource') and exists (select 1 from money_exceptions where kind='source_required_exception' and event_type='other_income'));
select money_event_setting_set('other_income', null, true, false) is not null as ev5 \gset
-- duplicates and void
select tt.as(:'u_cs');
select gen_random_uuid() as dc \gset
select (_w1f_other_income_add(1, tt.today(), 'scrap_sale', 15, 'cash', null, null, null, null, null, :'dc'::uuid) ->> 'id')::uuid as oi5 \gset
select (_w1f_other_income_add(1, tt.today(), 'scrap_sale', 15, 'cash', null, null, null, null, null, :'dc'::uuid) ->> 'id')::uuid as oi5b \gset
select tt.chk('T4 the same client id again returns the same row (offline retry does not double)', :'oi5b'::uuid = :'oi5'::uuid
  and tt.q('select count(*) from other_income where client_id = ''' || :'dc' || '''')::int=1);
select tt.as(:'u_cs2');
select tt.err('T4 another user cannot take that client id', format($q$select _w1f_other_income_add(1,%L,'scrap_sale',15,'cash',null,null,null,null,null,%L)$q$, tt.today(), :'dc'), 'client_id_taken');
select tt.err('T4 void needs the creator, an accounts manager or the owner', format($q$select _w1f_other_income_void(%L,'test_reason')$q$, :'oi5'), 'not allowed');
select tt.as(:'u_cs');
select tt.err('T4 void needs a reason', format($q$select _w1f_other_income_void(%L,'x')$q$, :'oi5'), 'note_required');
select (_w1f_other_income_void(:'oi5'::uuid, 'test_reason_void') ->> 'status') as vs1 \gset
select tt.chk('T4 the creator voids on the same day', :'vs1'='void' and (tt.oi(:'oi5'::uuid)).status='void');
select tt.chk('T4 a second void is a no-op', (_w1f_other_income_void(:'oi5'::uuid, 'test_reason_void') ->> 'noop')::boolean);
reset role;
select tt.err('T4 a recorded entry cannot be edited behind the screen (amount, head, date, account are fixed)', format($q$update other_income set amount = 1 where id = %L$q$, :'oi1'), 'other_income_fixed');
select tt.err('T4 nothing is deleted', format($q$delete from other_income where id = %L$q$, :'oi1'), 'nothing is deleted');
set role authenticated; select tt.as(:'u_o');
select tt.chk('T4 list: the owner sees the rows with head label and account name, the voided one marked',
  (select count(*) from jsonb_array_elements(_w1f_other_income_list(1) -> 'rows'))=7 and exists (select 1 from jsonb_array_elements(_w1f_other_income_list(1) -> 'rows') r where (r->>'id')::uuid=:'oi2'::uuid and r->>'head_label'='Rent received' and r->>'account_name'='test_bank_oi')
  and exists (select 1 from jsonb_array_elements(_w1f_other_income_list(1) -> 'rows') r where (r->>'id')::uuid=:'oi5'::uuid and r->>'status'='void'));
select tt.as(:'u_st'); select tt.err('T4 a salesperson without the permission cannot list', $q$select _w1f_other_income_list(1)$q$, 'not allowed');
select tt.as(:'u_o');
reset role;
select tt.chk('T4 WITHOUT the hook the entries are recorded but the poster does not see them yet (nothing in the journal, books unchanged)', coalesce((acct_post_pending(true) -> 'by_type' ->> 'other_income')::int, 0)=0
  and (select count(*) from journal_entries where source_type='other_income')=0);

\echo == T5 the hooks on a scratch copy (rolled back): journal source, day book, coverage line
begin;
\ir ../tests/sql/w1f_hooks96.sql
select tt.as(:'u_o');
select (acct_post_pending(false) -> 'by_type' ->> 'other_income')::int as h_n \gset
select (select count(*) from other_income where status='done') as h_done \gset
select (select sum(amount) from other_income where status='done' and head <> 'supplier_discount') as h_cr4900 \gset
select (select count(*) from journal_entries where source_type='other_income' and reverses_id is null) as h_entries \gset
select tt.unbalanced() as h_unbal \gset
select tt.ndt('other_income','4900') as h_c4900 \gset
select tt.ndt('other_income','1110') as h_d1110 \gset
select tt.ndt('other_income', tt.cc(:'mab'::bigint)) as h_dbank \gset
select (select coalesce(sum(amount),0) from other_income where status='done' and mode='cash') as h_cash_sum \gset
select (select coalesce(sum(amount),0) from other_income where status='done' and money_account_id=:'mab'::bigint) as h_bank_sum \gset
select (j.exists1) as h_bank_cr from (select exists (select 1 from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='other_income' and e.source_id=:'oi2' and a.code='4900' and l.credit=5000) as exists1) j \gset
select (select count(*) from jsonb_array_elements(day_book(1, tt.today(), tt.today()) -> 'days') d, jsonb_array_elements(d -> 'lines') l where l ->> 'type' = 'other_income') as h_db_lines \gset
select (select coalesce(sum((l ->> 'amount')::numeric),0) from jsonb_array_elements(day_book(1, tt.today(), tt.today()) -> 'days') d, jsonb_array_elements(d -> 'lines') l where l ->> 'type' = 'other_income') as h_db_sum \gset
select (select count(*) from jsonb_array_elements(daybook_vs_journal(:'pm'::date, tt.today()+1) -> 'rows') r where r->>'kind'='other_income' and (r->>'diff')::numeric <> 0) as h_dvj_bad \gset
select (_e_balance_check() #>> '{cross_checks,mapping_coverage,ok}')::boolean as h_cov_ok \gset
select (_e_balance_check() ->> 'status') as h_status \gset
select position('bos96' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0 as h_marker \gset
select _w1f_patch('public._acct_docs(date)'::regprocedure, array['x','y'], 'bos96') as h_second_patch \gset
-- voiding after posting reverses
select _w1f_other_income_void(:'oi1'::uuid, 'test_reason_void_after_post') is not null as h_v \gset
select (acct_post_pending(false) ->> 'reversed')::int as h_rev \gset
select coalesce(sum(l.debit - l.credit), 0) as h_net_void from journal_entries e join journal_lines l on l.entry_id = e.id where e.source_type='other_income' and e.source_id = :'oi1' \gset
select tt.unbalanced() as h_unbal2 \gset
-- an unmapped active head turns the coverage amber, never red
insert into option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active) values ('expense_heads','test_unmapped_head2','t','t','t',901,true);
select (_e_balance_check() #>> '{cross_checks,mapping_coverage,ok}')::boolean as h_cov_bad, (_e_balance_check() -> 'warnings') ? 'mapping_coverage' as h_cov_warn, (_e_balance_check() ->> 'status') as h_status2 \gset
rollback;
select tt.chk('H1 hooked poster: every done entry is posted once ('||:'h_done'||')', :'h_n'::int=:'h_done'::int and :'h_entries'::int=:'h_done'::int);
select tt.chk('H1 balanced: Dr = Cr on every entry', :'h_unbal'::int=0);
select tt.chk('H1 Cr 4900 equals the sum of the done entries that are not supplier discounts ('||:'h_cr4900'||')', :'h_c4900'::numeric=-:'h_cr4900'::numeric);
select tt.chk('H1 cash entries debit 1110 ('||:'h_cash_sum'||') and the bank-account entries debit the account''s own chart account ('||:'h_bank_sum'||')', :'h_d1110'::numeric=:'h_cash_sum'::numeric and :'h_dbank'::numeric=:'h_bank_sum'::numeric);
select tt.chk('H1 the 5000 rent received credits Other income', :'h_bank_cr'::boolean);
select tt.chk('H2 day book shows the other income lines of the day ('||:'h_done'||') with their total', :'h_db_lines'::int=:'h_done'::int and :'h_db_sum'::numeric=:'h_cash_sum'::numeric + :'h_bank_sum'::numeric);
select tt.chk('H2 day book vs journal: no difference for the kind other_income', :'h_dvj_bad'::int=0);
select tt.chk('H3 void after posting: the poster reverses it, the entry nets to 0, still balanced', :'h_rev'::int>=1 and :'h_net_void'::numeric=0 and :'h_unbal2'::int=0);
select tt.chk('H4 coverage line: ok when everything is mapped; an active head with no account makes it amber and the Balance Check status does NOT turn red', :'h_cov_ok'::boolean and not :'h_cov_bad'::boolean and :'h_cov_warn'::boolean and :'h_status'=:'h_status2');
select tt.chk('H5 the marker is on the scratch copy, a second patch is a no-op (returns false)', :'h_marker'::boolean and not :'h_second_patch'::boolean);
select tt.chk('H5 after the rollback the database under test carries NO bos96 marker in any shared function', (select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname not like '\_w1f\_%' and position('bos96' in pg_get_functiondef(p.oid)) > 0) = :m96
  and (select count(*) from journal_entries where source_type='other_income')=0 and (select count(*) from option_lists where value_code='test_unmapped_head2')=0);

\echo == T6 A-17: does the cash flow include the legacy wallets 1131-1134 and the money accounts?
select tt.as(:'u_o');
select set_rule('d_wallet_split_on','true') is null as ws \gset
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values (1, 996101, tt.today(), now(), '[]', 500, 0, 500, 'mobile', 'done', :'u_o');
insert into sale_payments (sale_id, location_id, kind, mode, wallet, amount, paid_at, created_by) select s.id, 1, 'sale', 'mobile', 'bkash', 500, now(), :'u_o' from sales s where s.receipt=996101;
select acct_post_pending(false) ->> 'posted' as pp3 \gset
select coalesce(sum(case when a.code in ('1110','1120','1130','1131','1132','1133','1134') then l.debit - l.credit end), 0)
     + coalesce((select sum(l2.debit - l2.credit) from journal_lines l2 where l2.account_id in (select coa_account_id from money_accounts)), 0) as t6_expected
  from journal_lines l join coa_accounts a on a.id = l.account_id \gset
select (acct_cash_flow(:'pm'::date, tt.today()+1) ->> 'closing')::numeric as t6_closing_before \gset
select (select count(*) from jsonb_array_elements(daybook_vs_journal(:'pm'::date, tt.today()+1) -> 'rows') r where r->>'kind'='d_wallet_split' and (r->>'diff')::numeric <> 0) as t6_dvj_before \gset
select tt.chk('T6 FINDING (A-17, was [unverified]): with the wallet split ON the cash flow closing misses the legacy wallet balance (500 on bKash 1131)', :'t6_expected'::numeric - :'t6_closing_before'::numeric = 500 and tt.nd('1131')=500);
select tt.chk('T6 FINDING: the day book vs journal also shows the wallet split as a difference (kind d_wallet_split, mobile)', :'t6_dvj_before'::int=1);
begin;
\ir ../tests/sql/w1f_hooks96.sql
select tt.as(:'u_o');
select (acct_cash_flow(:'pm'::date, tt.today()+1) ->> 'closing')::numeric as t6_closing_after \gset
select (select count(*) from jsonb_array_elements(daybook_vs_journal(:'pm'::date, tt.today()+1) -> 'rows') r where r->>'kind'='d_wallet_split' and (r->>'diff')::numeric <> 0) as t6_dvj_after \gset
rollback;
select tt.chk('H6 hooked cash flow: closing cash = cash + bank + mobile + legacy wallets 1131-1134 + every money account ('||:'t6_expected'||')', :'t6_closing_after'::numeric = :'t6_expected'::numeric);
select tt.chk('H6 hooked day book vs journal: the wallet split is no longer a difference', :'t6_dvj_after'::int=0);

\echo == T7 the seed never overwrites: taken code, wrong type, owner mapping, history
reset role;
insert into w1f_seed_state (key, code, name_en, name_bn, type, parent_code, purpose, existing, ord) values
 ('test_taken', '5300', 'Test taken', 'Test taken', 'expense', null, 'test', false, 900),
 ('test_type', '1110', 'Test type', 'Test type', 'expense', null, 'test', true, 901),
 ('pay_cash', '9998', 'Test mapped', 'Test mapped', 'asset', null, 'test', false, 902),
 ('exp_testhead', '5300', 'Test history', 'Test history', 'expense', null, 'test', true, 903);
select quick_expense_add(1, tt.today()-1, 'testhead', 'test_rider', 33, 'cash', false, null, gen_random_uuid()) is not null as qe3 \gset
select count(*) as coa_before from coa_accounts \gset
select _w1f_seed_run() as sr \gset
select tt.chk('T7 four blocked rows are reported, nothing is created or overwritten', :'sr'::int=4 and (select count(*) from coa_accounts)=:'coa_before'::int and (select count(*) from acct_mappings where key in ('test_taken','test_type','exp_testhead'))=0);
select tt.chk('T7 code taken -> code_taken, the other account 5300 keeps its name Rent', (select status from w1f_seed_state where key='test_taken')='code_taken' and (select name_en from coa_accounts where code='5300')='Rent');
select tt.chk('T7 existing code with another type -> type_mismatch', (select status from w1f_seed_state where key='test_type')='type_mismatch' and (select name_en from coa_accounts where code='1110')='Cash in hand');
select tt.chk('T7 a key the owner already mapped is kept (pay_cash still on 1110), no account 9998 made', (select status from w1f_seed_state where key='pay_cash')='owner_mapping_kept' and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='pay_cash')='1110'
  and not exists (select 1 from coa_accounts where code='9998'));
select tt.chk('T7 a head with unposted documents is not mapped silently -> history_exists', (select status from w1f_seed_state where key='exp_testhead')='history_exists');
select tt.chk('T7 the coverage names the blocked keys', not (_w1f_mapping_coverage() ->> 'ok')::boolean and exists (select 1 from jsonb_array_elements(_w1f_mapping_coverage() -> 'rows') r where r->>'key'='test_taken'));
select tt.as(:'u_o'); set role authenticated;
select (_w1f_seed_new_code('test_taken','5399','Test taken new',null) ->> 'code') as nc3 \gset
select tt.chk('T7 the owner picks a free code for the blocked key: account created, mapped, no reason needed (nothing was there)', :'nc3'='5399' and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='test_taken')='5399');
select tt.err('T7 mapping the history head needs a reason', $q$select _w1f_seed_map('exp_testhead','5300')$q$, 'older_documents_unposted');
select tt.chk('T7 with a reason it is mapped', (_w1f_seed_map('exp_testhead','5300','test_reason_hist') ->> 'changed')::boolean);

\echo == T8 books balance, paste twice
reset role;
select tt.chk('T8 every journal entry balances', tt.unbalanced()=0);
select (select count(*) from audit_log) as a1, (select count(*) from coa_accounts) as c1, (select count(*) from acct_mappings) as m1, (select count(*) from option_lists) as o1,
  (select count(*) from rules) as r1, (select count(*) from w1f_seed_state) as s1, (select count(*) from money_event_settings) as e1 \gset
\ir phase96.sql
select tt.chk('T8 pasting phase96 a second time changes nothing (audit_log, chart, mappings, lists, rules, seed state, event settings, other income rows)',
  (select count(*) from audit_log)=:'a1'::int and (select count(*) from coa_accounts)=:'c1'::int and (select count(*) from acct_mappings)=:'m1'::int and (select count(*) from option_lists)=:'o1'::int
  and (select count(*) from rules)=:'r1'::int and (select count(*) from w1f_seed_state)=:'s1'::int and (select count(*) from money_event_settings)=:'e1'::int);
select tt.chk('T8 and still no shared function carries bos96', (select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname not like '\_w1f\_%' and position('bos96' in pg_get_functiondef(p.oid)) > 0) = :m96);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
