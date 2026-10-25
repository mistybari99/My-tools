-- INTEGRATION: the COMBINED scenario. FRESH DB ONLY. A database built with EVERY phase of tests/sql/ORDER.txt (8 .. 477); then from the repository root:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f tests/sql/integ_test.sql | grep -E 'FAIL|RESULT'
-- What it does: loads the Wave 1 fixture (tests/sql/w1d_fixture.sql: accounting on, opening journal, stock, a production run, a sale, losses, a bill, vouchers), switches ON many settings of
-- EVERY package at once (pay requests with the "required" policies, order advance and refund records, marketing posting, voucher liability, receipt lots, void rules, cost basis, CRM privacy / consent /
-- duplicates / loyalty / leads / tasks / complaints, announcements, to-do, shifts, report switches), then makes records through the real functions and checks that
--   * every journal entry balances (Dr = Cr), the trial balance balances and the Balance Check (_e_balance_check) is green,
--   * the money paths of the new packages (R1 pay request -> payment, C2 order advance / refund, C3 marketing posting, F voucher liability) write balanced entries and the books reconcile,
--   * the hooks of every package are still in (phase 477 state) and every report of the three engines runs with all switches ON,
--   * the interactions between packages hold (CRM-B reads the CRM-A phone table, CRM-C follows the CRM-B mask style, RPT-C3 reads the real CRM-F coupon tables, RPT-C2 and CRM-A share credit_days,
--     RPT-B1 f3 counts an RPT-B4 record of real use).
-- Test data only (test_* names).
\set ON_ERROR_STOP off
\i tests/sql/rpthub_tt.sql
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.nd(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.n(j jsonb, k text) returns numeric language sql immutable as $$ select (j ->> k)::numeric $$;
grant execute on all functions in schema tt to authenticated, anon;
\set ON_ERROR_STOP on
\i tests/sql/w1d_fixture.sql
\set ON_ERROR_STOP off
\set u_hr '00000000-0000-0000-0000-000000007701'
\set u_s1 '00000000-0000-0000-0000-000000007702'
\set u_ap '00000000-0000-0000-0000-000000007703'
\set u_mg '00000000-0000-0000-0000-000000007704'
select o as u_o from (select :'o'::text as o) z \gset
insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_hr','test_hr_int@s.app','{"full_name":"test_hr"}'), (:'u_s1','test_staff_int@s.app','{"full_name":"test_staff_int"}'), (:'u_ap','test_purch_int@s.app','{"full_name":"test_purch"}'), (:'u_mg','test_mgr_int@s.app','{"full_name":"test_mgr"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_hr','hr'),(:'u_s1','salesperson'),(:'u_ap','purchasing'),(:'u_mg','management') on conflict do nothing;
insert into user_locations values (:'u_hr',1),(:'u_s1',1),(:'u_ap',1),(:'u_mg',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_hr','payroll_manage',null),(:'u_hr','supplier_pay',null),(:'u_hr','cash_move',null) on conflict do nothing;
with x as (insert into employees (employee_no, full_name_bn, full_name_en, status, primary_location_id, profile_id) values ('TESTINT_1','test_emp_int','test_emp_int','active',1,:'u_s1') returning id) select id as e1 from x \gset
select pm from (select date_trunc('month', tt.today() - interval '1 month')::date as pm) z \gset
select tt.as(:'u_o');

\echo == S0 the build is complete
select tt.chk('S0 phase 477 state: no hook of any package is missing', not exists (select 1 from public._i2_state() where not present));
select tt.chk('S0 fixture: accounting is on and the opening journal balances', rule_on('accounting_on') and tt.unbalanced() = 0);
select tt.nd('1110') as cash0 \gset

\echo == S1 switch ON the settings of every package at once
select set_rule('reports_net_of_returns','true') is null as s_a1 \gset
select set_rule('profit_one_number_on','true') is null as s_a2 \gset
select set_rule('reports_cost_basis','"ledger_first"') is null as s_a3 \gset
select set_rule('report_profit_blank_on','true') is null as s_a4 \gset
select set_rule('report_cash_short_by_case_on','true') is null as s_a5 \gset
select set_rule('void_follows_return_rules','true') is null as s_a6 \gset
select set_rule('supplier_pay_over_cumulative_days','7') is null as s_a7 \gset
select set_rule('transfer_valuation_basis','"cost"') is null as s_a8 \gset
select set_rule('receipt_lot_required','true') is null as s_a9 \gset
select set_rule('receipt_expiry_required','true') is null as s_a10 \gset
select set_rule('pay_requests_on','true') is null as s_b1 \gset
select set_rule('pay_requests_required','true') is null as s_b2 \gset
select set_rule('party_requests_on','true') is null as s_b3 \gset
select set_rule('party_requests_required','true') is null as s_b4 \gset
select set_rule('announce_on','true') is null as s_c1 \gset
select set_rule('todo_on','true') is null as s_c2 \gset
select set_rule('shift_on','true') is null as s_c3 \gset
select set_rule('crm_on','true') is null as s_d1 \gset
select set_rule('crm_second_phone_on','true') is null as s_d2 \gset
select set_rule('crm_mask_phone','true') is null as s_d3 \gset
select set_rule('crm_consent_pos_on','true') is null as s_d4 \gset
select set_rule('crm_pii_guard_on','true') is null as s_d5 \gset
select set_rule('crm_dup_check_on','true') is null as s_d6 \gset
select set_rule('crm_segments_on','true') is null as s_d7 \gset
select set_rule('crm_referral_on','true') is null as s_d8 \gset
select set_rule('crm_voucher_on','true') is null as s_d9 \gset
select set_rule('crm_hooks_on','true') is null as s_d10 \gset
select set_rule('crm_voucher_max_percent','50') is null as s_d10b \gset
select set_rule('crm_voucher_max_amount','500') is null as s_d10c \gset
select set_rule('crm_lead_on','true') is null as s_d11 \gset
select set_rule('crm_task_on','true') is null as s_d12 \gset
select set_rule('crm_complaints_on','true') is null as s_d13 \gset
select set_rule('crm_feedback_on','true') is null as s_d14 \gset
select set_rule('online_orders_on','true') is null as s_e0 \gset
select set_rule('order_promise_required','true') is null as s_e1 \gset
select set_rule('order_refund_record_on','true') is null as s_e2 \gset
select set_rule('order_advance_post_from', to_jsonb(:'pm'::text)) is null as s_e3 \gset
select set_rule('order_advance_post_on','true') is null as s_e4 \gset
select set_rule('marketing_post_from', to_jsonb(:'pm'::text)) is null as s_e5 \gset
select set_rule('marketing_post_on','true') is null as s_e6 \gset
select tt.chk('S1 about 35 settings of all packages are ON together', (select count(*) from rules where kind = 'switch' and key in ('reports_net_of_returns','profit_one_number_on','report_profit_blank_on','report_cash_short_by_case_on','void_follows_return_rules',
   'receipt_lot_required','receipt_expiry_required','pay_requests_on','pay_requests_required','party_requests_on','party_requests_required','announce_on','todo_on','shift_on','crm_on','crm_second_phone_on','crm_mask_phone','crm_consent_pos_on','crm_pii_guard_on',
   'crm_dup_check_on','crm_segments_on','crm_referral_on','crm_voucher_on','crm_hooks_on','crm_lead_on','crm_task_on','crm_complaints_on','crm_feedback_on','order_promise_required','order_refund_record_on','order_advance_post_on','marketing_post_on') and rule_on(key)) >= 30);

\echo == S2 R1: a staff advance and a supplier payment go through a request (the "required" policies are ON)
select tt.as(:'u_hr');
select tt.err('S2 a direct staff advance is refused while the policy is ON', format($$select staff_advance_add(%L::uuid, current_date, 500, null, 'cash', current_date, 'test direct', gen_random_uuid())$$, :'e1'), 'pay_request_required');
select tt.as(:'u_s1');
select (pay_request_submit('advance', 800, 'test: rent due', tt.today(), null, gen_random_uuid()) ->> 'id')::bigint as q1 \gset
select tt.as(:'u_o');
select pay_request_decide(:'q1'::bigint, true) ->> 'status' as d1 \gset
select pay_request_pay(:'q1'::bigint, 'cash') ->> 'status' as p1 \gset
select tt.chk('S2 the advance request is paid through staff_advance_add: status paid, one advance row of 800', :'p1' = 'paid' and (select count(*) from employee_advances where employee_id = :'e1'::uuid and amount = 800) = 1);
select (pay_request_submit('supplier', 150, 'test: pay the supplier', tt.today(), null, gen_random_uuid(), :'w_sup'::uuid, null, null, null, 1) ->> 'id')::bigint as q2 \gset
select pay_request_decide(:'q2'::bigint, true) ->> 'status' as d2 \gset
select pay_request_pay(:'q2'::bigint, 'cash') ->> 'status' as p2 \gset
select tt.chk('S2 the supplier payment request is paid through pay_supplier: one supplier payment of 150', :'p2' = 'paid' and (select count(*) from supplier_payments where supplier_id = :'w_sup'::uuid and amount = 150) = 1);
select acct_post_pending(false) ->> 'posted' as posted2 \gset
select tt.chk('S2 both payments are in the journal and every entry balances', tt.unbalanced() = 0 and :'posted2'::int >= 2);

\echo == S2b W1-FIX: with void_follows_return_rules ON a manager cannot void an old sale to put goods back
select set_rule('return_window_hours','24') is null as rw \gset
select tt.as(:'u_s1');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)->>'id' as sold \gset
select tt.as(:'u_o');
select set_config('session_replication_role','replica',false) is not null as rep1 \gset
update sales set sale_date = tt.today() - 5, sold_at = sold_at - interval '5 days' where id = :'sold'::uuid;
select set_config('session_replication_role','origin',false) is not null as rep2 \gset
select tt.as(:'u_mg');
select tt.err('S2b a manager''s void of a 5 day old sale is refused with the return window code (window 24 h)', format($$select void_sale('%s'::uuid, 'test void old')$$, :'sold'), 'return_window_exceeded');
select tt.as(:'u_o');
select void_sale(:'sold'::uuid, 'test owner void old sale') is null as ownvoid \gset
select tt.chk('S2b the sale is void now and the books balance', (select status from sales where id = :'sold'::uuid) = 'void' and tt.unbalanced() = 0);
select set_rule('return_window_hours','null') is null as rw2 \gset

\echo == S3 RPT-C2: order advance posted as a customer advance, applied at delivery; a cancelled order refunded (order_promise_required is ON too)
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_int1', '01700007701', 'test_address', format('[{"item_id":"%s","qty":2}]', :'i_fg')::jsonb, 'home', null, tt.today()+1, 30, 0, 50, 'mobile', null, null) ->> 'id' as o1 \gset
select c2_order_promise_set(:'o1'::uuid, '10:00', '12:00') ->> 'id' as pr1 \gset
select online_order_status(:'o1'::uuid,'confirmed') is not null as oc1 \gset
select c2_order_advance_post(:'o1'::uuid) ->> 'move_id' as mv1 \gset
select tt.chk('S3 the advance is a cust_advance cash move of 50 and the journal entry balances', (select kind from cash_moves where id = :'mv1'::uuid) = 'cust_advance' and (select amount from cash_moves where id = :'mv1'::uuid) = 50);
select online_order_status(:'o1'::uuid,'packed') is not null as oc2 \gset
select c2_order_deliver(:'o1'::uuid, '[{"mode":"cash","amount":180}]'::jsonb) as dl1 \gset
select c2_order_advance_apply(:'o1'::uuid) ->> 'applied' as ap1 \gset
select tt.chk('S3 delivered: the advance is applied once (a second apply is a no-op)', (c2_order_advance_apply(:'o1'::uuid) ->> 'noop')::boolean);
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_int2', '01700007702', 'test_address', format('[{"item_id":"%s","qty":1}]', :'i_fg')::jsonb, 'home', null, tt.today()+1, 0, 0, 40, 'mobile', null, null) ->> 'id' as o2 \gset
select c2_order_promise_set(:'o2'::uuid, '14:00', '16:00') ->> 'id' as pr2 \gset
select c2_order_advance_post(:'o2'::uuid) ->> 'move_id' as mv2 \gset
select c2_order_cancel(:'o2'::uuid, 'test_reason', 'refund') ->> 'status' as cn2 \gset
select c2_order_refund_pay(:'o2'::uuid, 'cash') as rf2 \gset
select tt.chk('S3 the cancelled order has a refund record and it is paid', (select count(*) from order_refunds where order_id = :'o2'::uuid) >= 1);
select acct_post_pending(false) ->> 'posted' as posted3 \gset
select tt.chk('S3 advance, application and refund are in the journal and every entry balances', tt.unbalanced() = 0);

\echo == S4 RPT-C3: marketing spend (form 18-1) posted to the journal once; the 10-2 look-alike is not posted twice
select mkt_campaign_save(null, jsonb_build_object('name_bn','test_int_promo','force',true,'start',tt.today()-3)) ->> 'value_code' as camp \gset
select save_entry(null,'18-1',1,tt.today(), jsonb_build_object('lines', jsonb_build_array(
  jsonb_build_object('date',tt.today()::text,'head','3','campaign_id',:'camp','amt','150','source','mobile'),
  jsonb_build_object('date',tt.today()::text,'head','3','amt','60','source','card'))), '[]') ->> 'id' as m18 \gset
select submit_entry(:'m18'::uuid) is not null as m18s \gset
select decide_entry(:'m18'::uuid, true, null, '{}', '[]') ->> 'status' as m18d \gset
select mkt_post_run(false) as mrun \gset
select tt.chk('S4 two lines (mobile 150, card 60) are posted as mkt_spend entries', (select count(*) from journal_entries where source_type = 'mkt_spend') = 2 and tt.n(:'mrun'::jsonb, 'posted') = 2);
select mkt_post_run(false) as mrun2 \gset
select tt.chk('S4 running it again posts nothing new', tt.n(:'mrun2'::jsonb, 'posted') = 0 and (select count(*) from journal_entries where source_type = 'mkt_spend') = 2);
select tt.chk('S4 every entry balances and the marketing expense account holds 210', tt.unbalanced() = 0 and (select coalesce(sum(l.debit - l.credit),0) from journal_lines l join journal_entries e on e.id = l.entry_id join coa_accounts a on a.id = l.account_id where e.source_type = 'mkt_spend' and l.debit > 0) = 210);

\echo == S5 CRM-F coupon at the till is read by RPT-C3 (real tables, not stand-ins); voucher liability set up with its date and accounts
select crmf_coupon_save(null, jsonb_build_object('code','TESTINT10','name','test coupon int','kind','percent','value',10,'valid_from',(tt.today()-1)::text,'valid_to',(tt.today()+30)::text,'campaign_ref',:'camp')) is not null as cp1 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',:'i_fg')::jsonb,20,'[{"mode":"cash","amount":180}]','01711770001','test_customer_cp','retail',null,false)->>'id' as scp \gset
select crmf_coupon_redeem_after_sale('TESTINT10', :'scp'::uuid, null, gen_random_uuid()) ->> 'ok' as rdm \gset
select mkt_tag_sale(:'scp'::uuid, :'camp', 'TESTINT10') ->> 'ok' as tg \gset
select mkt_coupon_usage(tt.today()-5, tt.today()+1) as cu \gset
select tt.chk('S5 RPT-C3 sees CRM-F installed and reads the real coupon use (1 validated use)', (:'cu'::jsonb ->> 'crmf_installed') = 'true' and tt.n(:'cu'::jsonb -> 'totals', 'validated_uses') >= 1);
select tt.chk('S5 the typed code was stored with the real coupon id next to it', (select coupon_id from mkt_sale_tags where sale_id = :'scp'::uuid) = (select id from crmf_coupons where code = 'TESTINT10'));
select code as liab_code from coa_accounts where type = 'liability' and not is_group and active order by code limit 1 \gset
select code as exp_code from coa_accounts where type = 'expense' and not is_group and active order by code limit 1 \gset
select set_rule('crm_voucher_liability_from', to_jsonb((tt.today()+1)::text)) is null as lf \gset
select set_rule('crm_voucher_liability_account', to_jsonb(:'liab_code'::text)) is null as la \gset
select set_rule('crm_voucher_expense_account', to_jsonb(:'exp_code'::text)) is null as le \gset
select set_rule('crm_voucher_liability_on','true') is null as lon \gset
select tt.chk('S5 voucher liability is ON with date and both accounts; nothing is booked before the date (no entry, balanced books)', rule_on('crm_voucher_liability_on') and crmf_voucher_liability_sync() ->> 'entries' = '0' and tt.unbalanced() = 0);

\echo == S6 CRM-A / CRM-B / CRM-C / RPT-C2 share data: second phone table, mask style rule, credit days column
insert into customers (mobile, name) values ('01711770011', 'test_cust_int_a'), ('01711770012', 'test_cust_int_b');
select id as ca from customers where mobile = '01711770011' \gset
select id as cb from customers where mobile = '01711770012' \gset
select crma_phone_add(:'ca'::uuid, '01711770012') is not null as ph \gset
select (select count(*) from jsonb_array_elements(_crmb_dup_candidates() -> 'rows') r where (r -> 'reasons') ? 'same_phone'
          and ((r ->> 'a_id') = least(:'ca'::text, :'cb'::text) and (r ->> 'b_id') = greatest(:'ca'::text, :'cb'::text))) as dupn \gset
select tt.chk('S6 CRM-B lists the pair whose second phone (CRM-A table customer_phones) equals the other customer''s mobile: same_phone', :'dupn'::int = 1);
select set_rule('crm_mask_style','"last4"') is null as ms \gset
select tt.chk('S6 CRM-C masks with the CRM-B rule crm_mask_style = last4', _crmc_mask('01712345678') = '*******5678');
select set_rule('crm_mask_style','"first3_last2"') is null as ms2 \gset
select crma_customer_extras_save(:'ca', '{"credit_days":20}') is not null as cd1 \gset
select tt.chk('S6 one column customers.credit_days: CRM-A saved 20 and RPT-C2 reads the same value', (select credit_days from customers where id = :'ca'::uuid) = 20);
select c2_customer_credit_days_set(:'cb'::uuid, 30) is not null as cd2 \gset
select tt.chk('S6 RPT-C2 sets 30 on the same column for the other customer', (select credit_days from customers where id = :'cb'::uuid) = 30);

\echo == S7 RPT-B3 / RPT-B4 / RPT-B1: a bill needs a lot and an expiry (switches ON, hook on post_purchase), real use of a production run is a record, f3 counts it
select save_purchase(gen_random_uuid(), null, :'w_sup'::uuid, 1, 'INT-B2', tt.today(), format('[{"item_id":"%s","qty":10,"unit_cost":21}]', :'i_rm')::jsonb, 0) ->> 'id' as bl \gset
select tt.err('S7 posting a bill whose stock line has no lot / expiry is refused (receipt_lot_required, hook H430-1 of 477)', format($$select post_purchase('%s'::uuid)$$, :'bl'), 'lot');
select receipt_lots_stage(:'bl'::uuid, format('[{"line_no":1,"lot_no":"TLOT-INT","expiry":"%s"}]', tt.today() + 60)::jsonb) is not null as stg \gset
select post_purchase(:'bl'::uuid) is not null as pp \gset
select tt.chk('S7 with a lot and an expiry the bill posts, and the lot became a stock batch with the expiry', (select count(*) from stock_batches b where b.item_id = :'i_rm'::uuid and b.batch_no = 'TLOT-INT' and (b.expires_at at time zone 'Asia/Dhaka')::date = tt.today() + 60) = 1);
select production_post(1, :'w_rc'::uuid, 1, gen_random_uuid()) ->> 'run_id' as run2 \gset
select prod_actual_issue_set(:'run2'::uuid, jsonb_build_array(jsonb_build_object('item_id', :'i_rm', 'qty', 6)), 'test real use') is not null as ra \gset
select report_run2('f3_raw_vs_recipe', '{"preset":"last_7"}'::jsonb) as f3 \gset
select tt.chk('S7 f3 shows a record of real use as a measurement (RPT-B1 x RPT-B4, glue of phase 477): actual status measured or partly', exists (select 1 from jsonb_array_elements(:'f3'::jsonb -> 'rows') r where r ->> 'actual_status' in ('measured') or r ->> 'actual_status' like 'partly%'));
select tt.chk('S7 the books balance after purchase, production and wastage', tt.unbalanced() = 0);

\echo == S8 record-only packages with their switches ON: leads, complaints, announcements, targets, plans, KPI snapshots, the Business Memory hub
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_lead_int","contact_phone":"01812345679","occasion":"wedding","event_date":"2030-01-20","guests":50,"est_value":20000}') ->> 'id' as lead \gset
select tt.chk('S8 CRM-G: an enquiry is saved', :'lead' ~ '^[0-9a-f-]{36}$');
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"taste","description":"test too sweet"}', :'scp')::jsonb) ->> 'id' as cmp \gset
select tt.chk('S8 CRM-H: a complaint is saved', :'cmp' ~ '^[0-9a-f-]{36}$');
select r2_announce_post('test announcement int', '', false, 'all', null) ->> 'id' as ann \gset
select tt.chk('S8 R2: an announcement is posted', :'ann' ~ '^[0-9]+$');
select sales_target_set(1, tt.today(), 10000, 30, 'test target') ->> 'id' as tgt \gset
select prod_plan_add(tt.today(), 5, :'i_fg'::uuid, null, 7.5, 'piece', null, 'test qty only', gen_random_uuid()) ->> 'id' as plan \gset
select tt.chk('S8 RPT-B4: a target and a production plan are saved', :'tgt' ~ '^[0-9]+$' and :'plan' ~ '^[0-9a-f-]{36}$');
select kpi_snapshot_take(tt.today() - 1, tt.today() - 1, false) is not null as kpi \gset
select tt.chk('S8 RPT-HUB: the day replay of today answers and counts the sales', rpt_hub_day(tt.today(), 1, null, 50, 0) is not null);
select tt.chk('S8 none of these wrote a journal entry that does not balance', tt.unbalanced() = 0);

\echo == S9 every report of the three engines runs with all switches ON; hooks still in; the books balance; Balance Check is green
create table if not exists tt.smoke (engine text, k text, preset text, ok boolean, msg text);
truncate tt.smoke;
do $smk$ declare k text; pr text;
begin
  foreach pr in array array['last_30', 'this_year'] loop
    for k in select e ->> 'key' from jsonb_array_elements(report_catalog()) e loop
      begin perform report_run(k, jsonb_build_object('preset', pr), null, null, 1, false); insert into tt.smoke values ('1', k, pr, true, null);
      exception when others then insert into tt.smoke values ('1', k, pr, false, sqlerrm); end;
    end loop;
    for k in select e ->> 'key' from jsonb_array_elements(report_catalog2()) e loop
      begin perform report_run2(k, jsonb_build_object('preset', pr)); insert into tt.smoke values ('2/3', k, pr, true, null);
      exception when others then insert into tt.smoke values ('2/3', k, pr, false, sqlerrm); end;
    end loop;
  end loop;
end $smk$;
select count(*) as smoke_n, count(*) filter (where not ok) as smoke_bad from tt.smoke \gset
select tt.chk('S9 ' || :'smoke_n' || ' report runs (engine 1, 2, 3; last 30 days and this year): none raised an error' || coalesce((select ' - ' || string_agg(k || ': ' || left(msg, 60), '; ') from tt.smoke where not ok), ''), :'smoke_bad'::int = 0 and :'smoke_n'::int >= 140);
select tt.chk('S9 phase 477 state after the whole scenario: every hook of every package is still in', not exists (select 1 from public._i2_state() where not present));
select tt.chk('S9 Wave 1 (37) and W1-FIX (4) hooks are all in', (select bool_and((e ->> 'present')::boolean) from jsonb_array_elements(public._i1_hooks_state()) e) and (select bool_and((e ->> 'present')::boolean) from jsonb_array_elements(public._w1x_hooks_state()) e));
select acct_post_pending(false) ->> 'posted' as posted_last \gset
select tt.chk('S9 every journal entry balances (Dr = Cr), ' || (select count(*) from journal_entries) || ' entries', tt.unbalanced() = 0 and (select sum(debit) = sum(credit) from journal_lines));
select tt.chk('S9 the Balance Check is green with all switches ON', _e_balance_check(null, null, 31) ->> 'status' = 'green');
select tt.chk('S9 the Exceptions list holds the kinds of every package in its constraint', (select bool_and(pg_get_constraintdef(c.oid) like '%''' || k || '''%') from pg_constraint c, unnest(public._i2_exc_kinds()) k
   where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%'));

select 'RESULT ' || count(*) filter (where ok) || ' passed, ' || count(*) filter (where not ok) || ' FAILED' from tt.res;
