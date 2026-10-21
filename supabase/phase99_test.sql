-- FRESH DB ONLY. Phase 99 tests (Wave 1 integration: every hook applied, one Exceptions kind list, paste twice, missing site, re-patch, and the combined scenario).
--   ORDER="phase8 ... phase87 phase88 ... phase98 phase99" bash tests/sql/build_fresh_db.sh a99db
--   psql -h /tmp -p 5570 -U postgres -d a99db -qAt -f supabase/phase99_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Run it once on a DB WITHOUT phase 99 pasted and the T0 shape checks fail by design.
-- Sections: T0 shape; T1 one list of Exceptions kinds; T2 paste twice; T3 re-patch after an old phase is pasted again; T4 a missing site stops the paste and changes nothing;
--           T5 closed to browsers; C1..C12 the combined scenario (period lock, exit revoke, return window, one profit number, owner money approval, other income, bank receipt, opening dues,
--           late offline sale, scheduled posting all ON together; every entry balances; Balance Check has no new red).
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000099'
\set u_c '00000000-0000-0000-0000-000000000199'
\set u_a '00000000-0000-0000-0000-000000000299'
\set u_m '00000000-0000-0000-0000-000000000399'
\set u_x '00000000-0000-0000-0000-000000000499'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.ok(p_name text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, true);
exception when others then perform tt.chk(p_name, false); raise notice '  (got: %)', sqlerrm; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.nd(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.exec(p_sql text) returns void language plpgsql security definer as $$ begin execute p_sql; end $$;
create or replace function tt.fdef(p_fn text) returns text language sql stable security definer as $$ select pg_get_functiondef(to_regprocedure(p_fn)) $$;
create or replace function tt.fmd5() returns text language sql stable security definer as $$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;
create or replace function tt.sell(p_item uuid, p_qty numeric, p_price numeric, p_loc int default 1, p_pay text default 'cash', p_cust text default null) returns uuid language plpgsql as $$
begin
  return (record_sale2(gen_random_uuid(), p_loc, jsonb_build_array(jsonb_build_object('item_id', p_item, 'qty', p_qty, 'price', p_price, 'unit', 'kg')), 0,
          case when p_pay = 'credit' then '[]'::jsonb else jsonb_build_array(jsonb_build_object('mode', p_pay, 'amount', p_qty * p_price)) end, p_cust, case when p_cust is not null then 'test_customer_99' end, 'retail', null, false) ->> 'id')::uuid;
end $$;
create or replace function tt.age(p_sale uuid, p_hours numeric) returns void language plpgsql security definer as $$
begin
  perform set_config('session_replication_role', 'replica', true);
  update public.sales set sold_at = now() - make_interval(secs => p_hours * 3600) where id = p_sale;
  perform set_config('session_replication_role', 'origin', true);
end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner99@s.app','{"full_name":"test_owner99"}'), (:'u_c','test_cashier99@s.app','{"full_name":"test_cashier99"}'), (:'u_a','test_acct99@s.app','{"full_name":"test_acct99"}'),
 (:'u_m','test_manager99@s.app','{"full_name":"test_manager99"}'), (:'u_x','test_leaver99@s.app','{"full_name":"test_leaver99"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_c','salesperson'),(:'u_a','management'),(:'u_m','management'),(:'u_x','salesperson') on conflict do nothing;
insert into user_locations values (:'u_c',1),(:'u_a',1),(:'u_a',2),(:'u_m',1),(:'u_x',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_a','accounts_manage',null),(:'u_a','accounts_view',null),(:'u_c','cash_move',null),(:'u_c','supplier_pay',null),(:'u_m','sale_return',null);

\echo == T0 shape: every phase present, every hook in place, nothing switched on
select tt.chk('T0 phase99 present and phases 88 to 98 present', to_regprocedure('public._p99_present()') is not null and to_regprocedure('public._p88_present()') is not null and to_regprocedure('public._p89_present()') is not null
  and to_regprocedure('public._w1c_present90()') is not null and to_regprocedure('public._w1c_present91()') is not null and to_regprocedure('public._w1d_p92_present()') is not null and to_regprocedure('public._w1d_p93_present()') is not null
  and to_regprocedure('public._p94_present()') is not null and to_regprocedure('public._p95_present()') is not null and to_regprocedure('public._w1f_present96()') is not null and to_regprocedure('public._w1f_present97()') is not null
  and to_regprocedure('public._w1g_present()') is not null);
select tt.chk('T0 all expected hooks are in their functions (count and none missing)', (select count(*) from public._i1_expect()) = 37 and not exists (select 1 from jsonb_array_elements(public._i1_hooks_state()) x where not (x ->> 'present')::boolean)
  and jsonb_array_length(public._i1_hooks_state()) = 37);
select tt.chk('T0 the hooked functions of every package are named: A bos88 x4, B bos89 x7, C bos90 x2 and bos91 x2, D bos92 x3 and bos93 x7, E w1e x3, F bos96 x5 and bos97 x4',
  (select count(*) from public._i1_expect() where marker='bos88')=4 and (select count(*) from public._i1_expect() where marker='bos89')=7 and (select count(*) from public._i1_expect() where marker='bos90')=2
  and (select count(*) from public._i1_expect() where marker='bos91')=2 and (select count(*) from public._i1_expect() where marker='bos92')=3 and (select count(*) from public._i1_expect() where marker='bos93')=7
  and (select count(*) from public._i1_expect() where marker like 'w1e%')=3 and (select count(*) from public._i1_expect() where marker='bos96')=5 and (select count(*) from public._i1_expect() where marker='bos97')=4);
select tt.chk('T0 the phase87 tags and earlier tags survive next to the new ones in _acct_docs and _daybook_lines',
  position('bos87' in tt.fdef('public._acct_docs(date)'))>0 and position('bos85' in tt.fdef('public._acct_docs(date)'))>0 and position('bos50' in tt.fdef('public._acct_docs(date)'))>0
  and position('bos87' in tt.fdef('public._daybook_lines(integer[],integer[],date,date)'))>0 and position('bos50' in tt.fdef('public._daybook_lines(integer[],integer[],date,date)'))>0);
select tt.chk('T0 nothing new is switched on by phase 99 or by any Wave 1 phase (the only default that is not off is the harmless coupling warning text)',
  not rule_on('open_parties_link') and rule_txt('open_parties_freeze')='off' and rule_txt('period_lock_mode')='manual' and rule_txt('owner_closed_period_mode')='off' and rule_txt('late_sale_policy')='redate'
  and rule_txt('exit_revoke_mode')='off' and rule_num('return_window_hours') is null and not rule_on('return_needs_receipt') and not rule_on('profit_one_number_on') and not rule_on('report_expense_parity_on')
  and rule_txt('expense_count_on')='as_today' and not rule_on('brand_map_dated_on') and rule_txt('owner_money_entry_mode')='open' and not rule_on('bank_slip_required') and rule_txt('supplier_pay_dup_mode')='off'
  and not rule_on('journal_loc_check') and not rule_on('mapping_type_guard') and rule_txt('journal_control_acct_mode')='allow' and not rule_on('other_income_on') and not rule_on('receipt_bank_on')
  and not rule_on('journal_sched_post_on') and not rule_on('backup_encrypt_on') and rule_txt('switch_coupling_warning')='warn');

\echo == T1 the Exceptions list: one list of kinds, one place that writes the constraint
select count(*) as nk from jsonb_array_elements_text(to_jsonb(public._i1_exc_kinds())) \gset
select tt.chk('T1 the one list holds 18 kinds: phase87 (7), phase89 (3), phase94 (8)', :nk = 18 and public._i1_exc_kinds() @> array['negative_warn','recon_diff','late_sale_held','backdate_exception','w1e_journal_request','w1e_pay_account_changed']);
select tt.chk('T1 the check constraint on money_exceptions equals that list exactly (one constraint, same kinds)',
  (select count(*) from pg_constraint c where c.conrelid='public.money_exceptions'::regclass and c.contype='c' and pg_get_constraintdef(c.oid) like '%negative_warn%')=1
  and not exists (select 1 from unnest(public._i1_exc_kinds()) k where (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid='public.money_exceptions'::regclass and c.contype='c' and pg_get_constraintdef(c.oid) like '%negative_warn%') not like '%''' || k || '''%')
  and (select array_length(regexp_split_to_array(pg_get_constraintdef(c.oid), '::text'),1)-1 from pg_constraint c where c.conrelid='public.money_exceptions'::regclass and c.contype='c' and pg_get_constraintdef(c.oid) like '%negative_warn%') = 18);
create or replace function tt.kind_ok(p_kind text) returns boolean language plpgsql security definer as $$
begin
  insert into public.money_exceptions (kind, reason, src_table, src_id) values (p_kind, 'test_kind_probe', 'test', p_kind);
  return true;
exception when check_violation then return false; end $$;
-- the probes run in a transaction that is rolled back (the Exceptions list cannot be deleted from)
begin;
select (select bool_and(tt.kind_ok(k)) from unnest(public._i1_exc_kinds()) k) as all_ok, tt.kind_ok('test_not_a_kind') as bad_ok, (public._i1_exc_kinds_apply() ->> 'changed') as chg0 \gset
rollback;
begin;
alter table public.money_exceptions drop constraint money_exceptions_kind_check;
alter table public.money_exceptions add constraint money_exceptions_kind_check check (kind = any ('{negative_warn,test_future_kind}'::text[]));
select (public._i1_exc_kinds_apply() ->> 'changed') as chg, tt.kind_ok('test_future_kind') as fk, tt.kind_ok('w1e_vendor_duplicate') as ok2, tt.kind_ok('test_not_a_kind') as bad2 \gset
rollback;
select tt.chk('T1 every kind of the three packages is accepted by the constraint', :'all_ok'='t');
select tt.chk('T1 an unknown kind is refused', :'bad_ok'='f');
select tt.chk('T1 applying again changes nothing', :'chg0'='false');
select tt.chk('T1 the merge keeps a kind found in the live constraint (old braces form too), adds the 18 known, and still refuses an unknown kind', :'chg'='true' and :'fk'='t' and :'ok2'='t' and :'bad2'='f');
select tt.chk('T1 after the rollback the constraint is the canonical one again and nothing was left behind', (public._i1_exc_kinds_apply() ->> 'changed')='false' and not exists (select 1 from public.money_exceptions where reason='test_kind_probe'));

\echo == T2 paste twice: the hooks patch nothing the second time and no function text changes
select tt.fmd5() as m1 \gset
select count(*) filter (where e.value::text='true') as patched_again from jsonb_each(public._i1_apply_hooks()) e \gset
select tt.fmd5() as m2 \gset
select tt.chk('T2 a second run patches nothing (every entry false) and the hooked functions are byte for byte the same', :patched_again=0 and :'m1'=:'m2');
select tt.chk('T2 the result names every patch (36 entries) and the day book hook answers false/false', (select count(*) from jsonb_each(public._i1_apply_hooks()))=36
  and (public._i1_apply_hooks() #>> '{bos93:_w1d_hooks_apply,acct_docs_patched}')='false');

\echo == T3 an older phase is pasted again: the functions lose their hooks, phase 99 puts them back (and only them)
-- the inverse of two hooks stands in for "phase 6 / 12 pasted again" (the function returns to its text without the hook)
select tt.exec(replace(tt.fdef('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'), E'  perform public._w1c_return_hook(rid); /* bos91 */\n', '')) as x1 \gset
select tt.exec(replace(tt.fdef('public.lock_check(date)'),
  $n$if p_date is null then return; end if;
  if public._w1b_lock_allowed(p_date) then return; end if;   -- bos89: pure date test, owner mode, override windows
  raise exception 'period_closed';                            -- bos89: the statements below are the old body and are not reached any more$n$,
  $o$if p_date is null or public.is_owner() then return; end if;$o$)) as x2 \gset
select tt.chk('T3 simulated re-paste: the hooks are gone from sale_return and lock_check, the state function says which',
  position('bos91' in tt.fdef('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'))=0 and position('bos89' in tt.fdef('public.lock_check(date)'))=0
  and (select count(*) from jsonb_array_elements(public._i1_hooks_state()) x where not (x ->> 'present')::boolean)=2);
select public._i1_apply_hooks() as hk \gset
select (:'hk'::jsonb ->> 'C:sale_return') as r_sr, (:'hk'::jsonb ->> 'bos89:lock_check') as r_lc, (select count(*) from jsonb_each(:'hk'::jsonb) where value::text='true') as n_true \gset
select tt.fmd5() as m3 \gset
select tt.chk('T3 phase 99 patched exactly those two (the first run answered true for them), nothing else; all 37 hooks are back and the functions are identical to before',
  :'r_sr'='true' and :'r_lc'='true' and :n_true=2 and :'m3'=:'m1' and not exists (select 1 from jsonb_array_elements(public._i1_hooks_state()) x where not (x ->> 'present')::boolean));

\echo == T4 a missing patch site stops with a clear message and changes nothing (the whole call is one transaction)
select tt.fdef('public._cust_bal(uuid)') as d_cb \gset
select tt.fdef('public.void_sale_return(uuid,text)') as d_vr \gset
-- an early hook (bos88 on _cust_bal) is taken off AND a late one (void_sale_return) loses its anchor line: the run must stop and must not leave _cust_bal patched
select tt.exec(replace(:'d_cb', ' /* bos88: opening due */', '')) as y1 \gset
select tt.exec(replace(replace(:'d_vr', E'  perform public._w1c_return_void_guard(p_id); /* bos91 */\n', ''), $n$if r.status = 'void' then return jsonb_build_object('dup', true, 'status', 'void'); end if;$n$, $o$if r.status = 'void' then return jsonb_build_object('dup', true); end if;$o$)) as y2 \gset
select tt.err('T4 the run stops and names the function and the missing text', $$select public._i1_apply_hooks()$$, 'patch site not found');
select tt.chk('T4 nothing was half done: _cust_bal (an earlier hook of the same call) is still unpatched because the call rolled back', position('bos88' in tt.fdef('public._cust_bal(uuid)'))=0);
select tt.exec(:'d_vr') as y3 \gset
select tt.exec(:'d_cb') as y4 \gset
select tt.chk('T4 after the definitions are put back the run is clean again and the functions are identical to the start',
  (select count(*) from jsonb_each(public._i1_apply_hooks()) where value::text='true')=0 and tt.fmd5()=:'m1');

\echo == T5 closed to browsers
select tt.chk('T5 the helpers are not executable by the browser roles, only by the database owner',
  not has_function_privilege('anon','public._i1_apply_hooks()','execute') and not has_function_privilege('authenticated','public._i1_apply_hooks()','execute')
  and not has_function_privilege('authenticated','public._i1_exc_kinds_apply()','execute') and not has_function_privilege('authenticated','public._i1_hooks_state()','execute')
  and not has_function_privilege('authenticated','public._i1_expect()','execute') and not has_function_privilege('anon','public._i1_exc_kinds()','execute'));
set role authenticated; select tt.as(:'u_o');
select tt.err('T5 even the owner login cannot rewrite functions from the browser', $$select public._i1_apply_hooks()$$, 'permission denied');
reset role;

\echo ============ COMBINED SCENARIO: the new settings ON together ============
\echo == C0 setup: accounting start last month, an opening, stock, a money account, every Wave 1 setting ON
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset
select (:'pm'::date + 9) as dlock \gset
select (:'pm'::date + 3) as dclosed \gset
update items set unit='kg', base_unit='kg', tracked=true, sell_price=200 where code='I-001';
update items set unit='kg', base_unit='kg', tracked=true, sell_price=100 where code='I-002';
select id as i1 from items where code='I-001' \gset
select id as i2 from items where code='I-002' \gset
set role authenticated; select tt.as(:'u_o');
select acct_set_start(:'pm'::date) is not null as s1 \gset
select set_rule('accounting_on','true') is not null as s2 \gset
select stock_opening(:'i1'::uuid,1,100,100) is not null as o1 \gset
select stock_opening(:'i2'::uuid,1,100,50) is not null as o2 \gset
select (money_account_add('bank','test_bank_99',null,'Test Bank','Main','9901',null,null,0) ->> 'id')::bigint as mab \gset
select set_user_grant(:'u_m'::uuid,'return_override') is null as g1 \gset
select set_user_grant(:'u_a'::uuid,'closed_period_edit') is null as g2 \gset
reset role;
insert into suppliers (name, opening_balance) values ('test_supplier_99', 5000);
select id as sup1 from suppliers where name='test_supplier_99' \gset
select tt.chk('C0 setup done: accounting on from last month, stock 100 and 100, a bank account, a supplier', :'s2'='t' and :'o1'='t' and :'mab'::int>0 and :'sup1' is not null);

\echo == C1 switch the Wave 1 settings ON together (owner): period lock, exit revoke, return window, one profit number, owner money approval, other income, bank receipts, open dues link, park late sales
set role authenticated; select tt.as(:'u_o');
select period_lock_set(:'dlock'::date, null) is not null as pl \gset
select set_rule('owner_closed_period_mode','"reason"') is not null as r1 \gset
select set_rule('exit_revoke_mode','"auto"') is not null as r2 \gset
select set_rule('return_window_hours','48') is not null as r3 \gset
select set_rule('profit_one_number_on','true') is not null as r4 \gset
select set_rule('owner_money_entry_mode','"approval"') is not null as r5 \gset
select set_rule('other_income_on','true') is not null as r6 \gset
select set_rule('receipt_bank_on','true') is not null as r7 \gset
select set_rule('open_parties_link','true') is not null as r8 \gset
select set_rule('late_sale_policy','"park"') is not null as r9 \gset
select set_rule('supplier_pay_dup_mode','"block"') is not null as r10 \gset
select set_rule('bank_slip_required','true') is not null as r11 \gset
select set_rule('report_expense_parity_on','true') is not null as r12 \gset
select set_rule('journal_control_acct_mode','"request"') is not null as r13 \gset
reset role;
select tt.chk('C1 all thirteen settings are on at once', :'pl'='t' and :'r1'='t' and :'r2'='t' and :'r3'='t' and :'r4'='t' and :'r5'='t' and :'r6'='t' and :'r7'='t' and :'r8'='t' and :'r9'='t' and :'r10'='t' and :'r11'='t' and :'r12'='t' and :'r13'='t');
select tt.chk('C1 the period is closed until the lock date, the owner mode is reason, approval mode is on', rule_txt('owner_closed_period_mode')='reason' and rule_txt('owner_money_entry_mode')='approval' and rule_on('profit_one_number_on') and rule_on('other_income_on'));

\echo == C2 opening dues (W1-A hooks): the old due of a customer is typed once and can be collected, counted in the credit check
insert into customers (mobile, name, credit_limit) values ('01900000099', 'test_customer_99', 2000);
select id as c1 from customers where mobile='01900000099' \gset
set role authenticated; select tt.as(:'u_o');
select w1a_open_set('customer', :'c1'::uuid, 500, null, 'test paper page 1') ->> 'new' as op1 \gset
select balance as due1 from customer_dues() where mobile='01900000099' \gset
select tt.chk('C2 the typed opening 500 is the customer balance and shows in the dues list and the ledger', :'op1'::numeric=500 and :'due1'::numeric=500 and customer_balance(:'c1'::uuid)=500
  and exists (select 1 from customer_ledger(:'c1'::uuid) l where l.kind='opening' and l.debit=500));
-- the opening batch: cash 900000 and bank 300000 (other lines), the customer 500 and the supplier 5000 from the same typed figures, owner capital the rest (1195500)
select opening_balance_post(format('{"other":[{"code":"1110","debit":900000},{"code":"1120","debit":300000}],"customer_dues":[{"customer_id":"%s","amount":"500"}],"supplier_dues":[{"supplier_id":"%s","amount":"5000"}],"capital":[{"kind":"owner","amount":"1195500"}]}', :'c1', :'sup1')::jsonb, gen_random_uuid(), false, false) ->> 'id' as obid \gset
select set_rule('open_parties_freeze','"after_opening"') is not null as fz \gset
reset role;
select tt.chk('C2 the opening batch is one balanced entry; receivable 1210 = 500 and payable 2100 = 5000 from the same figures; the sub-ledgers agree with the books',
  :'obid' is not null and tt.nd('1210')=500 and tt.nd('2100')=-5000 and tt.nd('1110')=900000 and tt.unbalanced()=0
  and (select opening_balance from customers where id=:'c1'::uuid)=500 and (select opening_balance from suppliers where id=:'sup1'::uuid)=5000);
set role authenticated; select tt.as(:'u_o');
select tt.err('C2 after the batch a direct change of the opening is refused (freeze)', format($q$update customers set opening_balance = 900 where id = %L::uuid$q$, :'c1'), 'opening_frozen');
reset role;

\echo == C3 sales and receipts: credit sale counts the opening due; bank / cheque receipt through the shared collect_payment (W1-F hook), oldest item first
set role authenticated; select tt.as(:'u_c');
select tt.sell(:'i1'::uuid, 5, 200) as s_cash \gset
select tt.sell(:'i1'::uuid, 3.5, 200, 1, 'credit', '01900000099') as s_cred \gset
select tt.err('C3 a credit sale above the limit is refused: 500 opening + 700 + 1000 > 2000', format($q$select tt.sell(%L::uuid, 5, 200, 1, 'credit', '01900000099')$q$, :'i1'), 'credit_limit');
select tt.as(:'u_o');
select collect_payment(gen_random_uuid(), 1, :'c1'::uuid, jsonb_build_array(jsonb_build_object('mode','bank','amount',600,'ref','TX-99','cheque_no','CHQ-99','cheque_date',tt.today()::text,'money_account_id',:'mab'::bigint)), 'test cheque') ->> 'collected' as col1 \gset
reset role;
select tt.chk('C3 600 collected by bank with a cheque number into the chosen account; the balance is 1200 - 600 = 600',
  :'col1'::numeric=600 and (select balance from customer_dues() where mobile='01900000099')=600 and exists (select 1 from sale_payments where customer_id=:'c1'::uuid and mode='bank' and cheque_no='CHQ-99' and money_account_id=:'mab'::bigint and amount=600));
set role authenticated; select tt.as(:'u_o');
select tt.err('C3 collecting more than is owed is refused (overpaid), the opening is part of what is owed', format($q$select collect_payment(gen_random_uuid(),1,%L::uuid,'[{"mode":"cash","amount":700}]'::jsonb,'x')$q$, :'c1'), 'overpaid');
select tt.err('C3 a bank receipt without a reference or cheque number is allowed by default (receipt_ref_required is off), but a wrong mode is refused', format($q$select collect_payment(gen_random_uuid(),1,%L::uuid,'[{"mode":"crypto","amount":10}]'::jsonb,'x')$q$, :'c1'), 'bad_mode');
reset role;

\echo == C4 period lock + owner mode reason + override window (W1-B hooks on lock_check, quick_expense_add)
set role authenticated; select tt.as(:'u_c');
select tt.err('C4 the cashier cannot date a cash move into the closed period', format($q$select cash_move_add(1,'hub_receipt',100,%L::date,'cash',null,'test',null,gen_random_uuid(),false)$q$, :'dclosed'), 'period_closed');
select tt.as(:'u_o');
select tt.err('C4 the owner is refused too while owner_closed_period_mode is reason', format($q$select quick_expense_add(1, %L::date, 'transport', 'test_rider', 100, 'cash', false, null, gen_random_uuid())$q$, :'dclosed'), 'period_closed_reason_required');
select (period_override_start('test: late paper bill of last month', :'dclosed'::date, :'dclosed'::date, 30) ->> 'id')::bigint as w1 \gset
select quick_expense_add(1, :'dclosed'::date, 'transport', 'test_rider', 100, 'cash', false, null, gen_random_uuid()) is not null as qe_ok \gset
reset role;
select tt.chk('C4 under the owner window with a written reason the expense is saved; one audit line and one Exceptions line were written',
  :'qe_ok'='t' and exists (select 1 from audit_log where action='period_override_start' and record_id=:'w1') and exists (select 1 from audit_log where action='period_override_used')
  and exists (select 1 from money_exceptions where kind='period_lock_exception'));

\echo == C5 owner money waits for the approver (W1-E trigger + cash_move_add hook); bank slip is required (W1-E)
set role authenticated; select tt.as(:'u_c');
select cash_move_add(1,'owner_draw',1500,tt.today(),'cash',null,'test draw',null,gen_random_uuid(),false) as dr \gset
select tt.chk('C5 the cashier owner draw is not saved: the answer says pending with a request id (hook H2), nothing in cash_moves', (:'dr'::jsonb ->> 'pending')='true' and (:'dr'::jsonb ->> 'request_id') is not null
  and not exists (select 1 from cash_moves where kind='owner_draw' and ref='test draw'));
select tt.err('C5 a bank deposit without a slip number is refused', $q$select cash_move_add(1,'bank_deposit',500,tt.today(),null,null,null,null,gen_random_uuid(),false)$q$, 'bank_slip_required');
select cash_move_add(1,'bank_deposit',2000,tt.today(),null,null,'SLIP-99-1','SLIP-99-1',gen_random_uuid(),false) is not null as bd_ok \gset
select tt.as(:'u_c');
select tt.err('C5 the maker cannot decide his own request', format($q$select w1e_request_decide(%s, true, 'x')$q$, (:'dr'::jsonb ->> 'request_id')), 'self_approval');
select tt.as(:'u_o');
select w1e_request_decide((:'dr'::jsonb ->> 'request_id')::bigint, true, 'test approved') ->> 'status' as dec \gset
reset role;
select tt.chk('C5 slip given: bank deposit saved; the owner approves the draw and then the cash move exists once with the cashier as maker',
  :'bd_ok'='t' and :'dec' in ('approved','applied') and (select count(*) from cash_moves where kind='owner_draw' and ref='test draw')=1);

\echo == C6 supplier payment guard (hook H1), other income (W1-F hooks)
set role authenticated; select tt.as(:'u_c');
select pay_supplier(:'sup1'::uuid, 1, '[{"mode":"cash","amount":1000}]'::jsonb, gen_random_uuid(), 'test pay 1') ->> 'paid' as pp1 \gset
select tt.err('C6 the same supplier and the same total again today is blocked (supplier_pay_dup_mode = block)', format($q$select pay_supplier(%L::uuid, 1, '[{"mode":"cash","amount":1000}]'::jsonb, gen_random_uuid(), 'test pay 2')$q$, :'sup1'), 'duplicate_payment');
select pay_supplier(:'sup1'::uuid, 1, '[{"mode":"cash","amount":700}]'::jsonb, gen_random_uuid(), 'test pay 3') ->> 'paid' as pp3 \gset
select _w1f_other_income_add(1, tt.today(), 'scrap_sale', 300, 'cash', null, 'test_buyer', 'ref1', 'test scrap', null, gen_random_uuid()) ->> 'id' as oi1 \gset
select _w1f_other_income_add(1, tt.today(), 'rent_received', 1000, 'bank', :'mab'::bigint, 'test_tenant', 'ref2', 'test rent', null, gen_random_uuid()) ->> 'id' as oi2 \gset
reset role;
select tt.chk('C6 pay 1000 and 700 paid, the repeat refused; other income 300 cash and 1000 into the bank account are recorded', :'pp1'::numeric=1000 and :'pp3'::numeric=700 and :'oi1' is not null and :'oi2' is not null
  and (select count(*) from supplier_payments where supplier_id=:'sup1'::uuid)=2);

\echo == C7 sale return rules on the plain sale_return (W1-C hook): the 48 hour window; a fresh return is saved
set role authenticated; select tt.as(:'u_c');
select tt.sell(:'i2'::uuid, 2, 100) as s_old \gset
select tt.sell(:'i2'::uuid, 2, 100) as s_new \gset
select tt.age(:'s_old'::uuid, 60);
select tt.as(:'u_m');
select tt.err('C7 a 60 hour old sale is refused by the plain sale_return when the window is 48 hours', format($q$select sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb, 'damaged', null, 'cash', null, null)$q$, :'s_old', :'i2'), 'return_window_exceeded');
select sale_return(gen_random_uuid(), :'s_new'::uuid, format('[{"item_id":"%s","qty":1}]', :'i2')::jsonb, 'damaged', null, 'cash', null, null) ->> 'amount' as ret1 \gset
reset role;
select tt.chk('C7 the fresh return of 1 kg at 100 is saved (amount 100) and the refused one wrote nothing', :'ret1'::numeric=100 and (select count(*) from sale_returns where sale_id=:'s_old'::uuid)=0);

\echo == C8 staff exit revokes access (W1-C hook on employee_status_set)
set role authenticated; select tt.as(:'u_o');
select (employee_save(null, gen_random_uuid(), jsonb_build_object('full_name_bn','test_leaver99','full_name_en','test_leaver99','primary_location_id',1,'joining_date',(tt.today()-30)::text,'designation','cashier')) ->> 'id') as emp1 \gset
select employee_submit(:'emp1'::uuid) is not null as es \gset
select employee_link_profile(:'emp1'::uuid, :'u_x'::uuid) is not null as el \gset
select employee_status_set(:'emp1'::uuid, 'resigned', tt.today(), 'test left the job') is not null as ss \gset
reset role;
select tt.chk('C8 the status change through the plain employee_status_set disables the login of the leaver (the hook ran)', (select status from profiles where id=:'u_x'::uuid)='disabled'
  and exists (select 1 from w1c_exit_log where employee_id=:'emp1'::uuid and action='revoked'));

\echo == C9 late offline sale is parked (W1-B hook on record_sale2) and released by the owner
set role authenticated; select tt.as(:'u_c');
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":1,"price":200,"unit":"kg"}]', :'i1')::jsonb, 0, '[{"mode":"cash","amount":200}]'::jsonb, null, null, 'retail', null, false, now() - interval '100 hours', null, null) as lt \gset
select tt.chk('C9 a sale 100 hours old answers parked: true and is not in sales yet', (:'lt'::jsonb ->> 'parked')='true' and (:'lt'::jsonb ->> 'held_id') is not null);
select tt.as(:'u_o');
select late_sale_release((:'lt'::jsonb ->> 'held_id')::bigint, 'accept', 'test: paper slip seen') is not null as rel \gset
reset role;
select tt.chk('C9 after the owner accepts, the sale exists once with its cash payment', :'rel'='t' and (select count(*) from sales where total=200 and sold_at < now() - interval '90 hours')=1);

\echo == C10 one profit number (W1-D): a wastage is counted in the profit while the master is ON, and not when it is OFF
set role authenticated; select tt.as(:'u_o');
select stock_wastage(:'i1'::uuid,1,2,'spoiled','test') ->> 'id' as wid \gset
reset role;
select coalesce(sum(o_exp),0) as exp_on from _p27_pl(date_trunc('month', tt.today())::date, tt.today(), array[1]) \gset
set role authenticated; select tt.as(:'u_o');
select set_rule('profit_one_number_on','false') is not null as off1 \gset
reset role;
select coalesce(sum(o_exp),0) as exp_off from _p27_pl(date_trunc('month', tt.today())::date, tt.today(), array[1]) \gset
set role authenticated; select tt.as(:'u_o');
select set_rule('profit_one_number_on','true') is not null as on1 \gset
reset role;
select tt.chk('C10 the expenses with the master ON exceed the OFF figure by the wastage cost (2 kg x 100 = 200)', :'exp_on'::numeric - :'exp_off'::numeric = 200);

\echo == C11 scheduled posting (W1-G) posts everything that the hooks added to the poster: sales, collection, cash moves, supplier payments, return, wastage, other income
set role authenticated; select tt.as(:'u_o');
select set_rule('journal_sched_post_on','true') is not null as sp_on \gset
select _w1g_post_scheduled(false) as run1 \gset
select _w1g_post_scheduled(false) as run2 \gset
reset role;
select tt.chk('C11 the first scheduled run posted the waiting documents of every kind (sales, collection, cash moves, supplier payments, sale return, wastage, other income); the second run found nothing',
  :'sp_on'='t' and (:'run1'::jsonb ->> 'posted')::int >= 12 and (:'run2'::jsonb ->> 'posted')::int = 0 and (:'run1'::jsonb ->> 'ran')='true'
  and (:'run1'::jsonb #>> '{by_type,other_income,posted}')::int = 2 and (:'run1'::jsonb #>> '{by_type,collection,posted}')::int = 1 and (:'run1'::jsonb #>> '{by_type,supplier_payment,posted}')::int = 2
  and (:'run1'::jsonb #>> '{by_type,sale_return,posted}')::int = 1 and (:'run1'::jsonb #>> '{by_type,wastage,posted}')::int = 1 and (:'run1'::jsonb #>> '{by_type,cash_move,posted}')::int = 2);
select tt.chk('C11 the document in the closed month (the quick expense dated under the window) is held back for everyone, not posted by the scheduler either', (:'run1'::jsonb #>> '{by_type,quick_expense,locked}')::int = 1);

\echo == C12 the books after everything: balanced, receivable and payable equal the sub-ledgers, other income and the bank account carry their amounts, Balance Check has no red
select c.code as bank_code from money_accounts a join coa_accounts c on c.id = a.coa_account_id where a.id = :'mab'::bigint \gset
set role authenticated; select tt.as(:'u_o');
select acct_balance_sheet(tt.today()) ->> 'unbalanced' as bs_unb, (_e_balance_check() ->> 'status') as bc_status, (_e_balance_check() -> 'reds') as bc_reds \gset
select w1a_party_gate('customer') ->> 'status' as gate_c, w1a_party_gate('supplier') ->> 'status' as gate_s \gset
select (select count(*) from jsonb_array_elements(daybook_vs_journal(:'pm'::date, tt.today()) -> 'rows') r where r ->> 'kind' like '%income%') as dvj_inc \gset
select acct_cash_flow(:'pm'::date, tt.today()) is not null as cf_ok \gset
reset role;
select tt.chk('C12 every journal entry balances (Dr = Cr) and the balance sheet is balanced', tt.unbalanced()=0 and :'bs_unb'='false');
select tt.chk('C12 Balance Check is green with no red line', :'bc_status'='green' and :'bc_reds'='[]');
select tt.chk('C12 receivable 1210 = 600 = the customer dues list; payable 2100 = -3300 = 5000 opening - 1700 paid; the party gates are green', tt.nd('1210')=600 and tt.nd('2100')=-3300
  and (select balance from customer_dues() where mobile='01900000099')=600 and :'gate_c'='green' and :'gate_s'='green');
select tt.chk('C12 other income 4900 carries 1300 (scrap 300 + rent 1000); the bank account carries the cheque 600 and the rent 1000', tt.nd('4900')=-1300 and tt.nd(:'bank_code')=1600);
select tt.chk('C12 the day book and the journal agree on other income (no difference row), and the cash flow report runs', :'dvj_inc'::int=0 and :'cf_ok'='t');
select tt.chk('C12 the hooks are all still there after the whole scenario and a third run of phase 99 patches nothing', (select count(*) from jsonb_each(public._i1_apply_hooks()) where value::text='true')=0);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select 'FAIL ' || name from tt.res where not ok;
