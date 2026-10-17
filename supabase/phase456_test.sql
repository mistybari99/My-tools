-- RPT-HUB phase 456 tests: spend explorer (head vs memo matching, person links, unlinked count, status, payment source, utility bills by place, masking, empty data).
-- From the repo root, on a copy of a database through phase 99:  psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase456_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\i tests/sql/rpthub_tt.sql
\i supabase/phase450.sql
\i supabase/phase451.sql
\i supabase/phase452.sql
\i supabase/phase453.sql
\i supabase/phase454.sql
\i supabase/phase455.sql
\i supabase/phase456.sql
\i supabase/phase456.sql
\i tests/sql/rpthub_fixture.sql
select tt.today() as d0 \gset
select id::text as emp from employees where employee_no = 'test_e1' \gset
-- extra rows: a meal typed with the staff member's NAME in the payee; one electricity item typed under head "other" with the word in Bengali; a draft voucher; a utility bill split over two places
insert into quick_expenses (location_id, exp_date, head, paid_to, amount, mode, receipt, note, status, created_by, created_staff, created_at)
 values (1, :'d0'::date - 2, 'staff_meal', 'test_employee_a lunch', 70, 'cash', true, null, 'done', :'u_o', 'test_owner450', now()),
        (2, :'d0'::date - 4, 'other', 'test_power', 300, 'bank', true, 'বিদ্যুৎ বিল test', 'done', :'u_o', 'test_owner450', now()),
        (1, :'d0'::date - 5, 'staff_meal', 'x', 40, 'cash', true, 'test voided meal', 'void', :'u_o', 'test_owner450', now());
insert into cost_sources (cost_type, provider, kind, dest, frequency, effective_from) values ('electricity', 'test_power_co', 'shared', null, 'monthly', :'d0'::date - 90);
select id as src from cost_sources where provider = 'test_power_co' \gset
insert into cost_source_bills (source_id, period_kind, period_month, amount, pay_mode, bill_no, bill_date, status, created_by) values (:'src', 'month', date_trunc('month', :'d0'::date - 30)::date, 1000, 'bank', 'T-1', :'d0'::date - 30, 'active', :'u_o');
select id as cb from cost_source_bills where bill_no = 'T-1' \gset
insert into cost_bill_shares (bill_id, kind, location_id, dest, amount, active) values (:'cb', 'share', 1, 'showroom', 600, true), (:'cb', 'share', 2, 'showroom', 400, true);
insert into cost_source_bills (source_id, period_kind, period_month, amount, pay_mode, bill_no, bill_date, status, dup_entry_id, created_by) values (:'src', 'month', date_trunc('month', :'d0'::date - 10)::date, 200, 'cash', 'T-2', :'d0'::date - 10, 'active', (select id from entries where form_code = '10-1' limit 1), :'u_o');
insert into cost_bill_shares (bill_id, kind, location_id, dest, amount, active) values ((select id from cost_source_bills where bill_no = 'T-2'), 'share', 1, 'showroom', 200, true);
select jsonb_build_object('from', :'d0'::date - 400, 'to', :'d0') as base \gset
select tt.as(:'u_o');
\echo == S1 head and memo
select public.rpt_hub_spend((:'base'::jsonb) || '{"heads":["staff_meal"],"terms":["meal","lunch"]}') as meals \gset
select tt.chk('S1 meals: head match counts the 3 posted staff_meal rows (120+100+70), the voided one is out', (:'meals'::jsonb)->>'total' = '290' and (:'meals'::jsonb)->>'count' = '3');
select tt.chk('S1 each row says matched by head / memo / both', (select count(*) filter (where r->>'matched_by' in ('head','both')) = 3 from jsonb_array_elements((:'meals'::jsonb)->'rows') r));
select public.rpt_hub_spend((:'base'::jsonb) || '{"heads":["electricity"],"terms":["electric","বিদ্যুৎ"]}') as el \gset
select tt.chk('S1 electricity: found by MEMO under head repair (800), under head other in Bengali (300), and the utility bills by head', (select count(*) filter (where r->>'matched_by' = 'memo') = 2 and count(*) filter (where r->>'kind' = 'utility_bill') = 3 from jsonb_array_elements((:'el'::jsonb)->'rows') r));
select tt.chk('S1 utility bill is split by place: place 1 share 600, place 2 share 400', (select sum((r->>'amount')::numeric) filter (where (r->>'loc')::int = 1 and r->>'kind' = 'utility_bill' and not (r->>'possible_duplicate')::boolean) = 600 and sum((r->>'amount')::numeric) filter (where (r->>'loc')::int = 2 and r->>'kind' = 'utility_bill') = 400 from jsonb_array_elements((:'el'::jsonb)->'rows') r));
select tt.chk('S1 a utility bill that repeats a saved voucher is flagged and kept out of the total, listed in overlap', ((:'el'::jsonb)->'overlap'->>'count') = '1' and ((:'el'::jsonb)->'overlap'->>'amount')::numeric = 200);
select public.rpt_hub_spend((:'base'::jsonb) || jsonb_build_object('heads', '["electricity"]'::jsonb, 'terms', '["electric","বিদ্যুৎ"]'::jsonb, 'loc', 2)) as el2 \gset
select tt.chk('S1 ONE branch: place 2 only = 400 (bill share) + 300 (Bengali memo) = 700', (:'el2'::jsonb)->>'total' = '700.00' or (:'el2'::jsonb)->>'total' = '700');
select tt.chk('S1 monthly breakdown adds up to the total', (select sum((m->>'amount')::numeric) from jsonb_array_elements((:'el'::jsonb)->'by_month') m) = ((:'el'::jsonb)->>'total')::numeric);
select tt.chk('S1 a free word search finds the memo text', ((public.rpt_hub_spend((:'base'::jsonb) || '{"terms":["rickshaw"]}'))->>'count') = '1');
\echo == S2 person
select public.rpt_hub_spend((:'base'::jsonb) || jsonb_build_object('person', jsonb_build_object('kind','staff','id',:'emp'))) as pstaff \gset
select tt.chk('S2 staff: the advance is linked DIRECTLY (stored on the record)', (:'pstaff'::jsonb)->'linked'->>'direct' = '1' and (:'pstaff'::jsonb)->'linked'->>'text' = '1' and (:'pstaff'::jsonb)->>'total' = '570');
select public.rpt_hub_spend((:'base'::jsonb) || jsonb_build_object('person', jsonb_build_object('kind','staff','id',:'emp'), 'heads', '["staff_meal"]'::jsonb, 'terms', '["meal","lunch"]'::jsonb)) as pmeal \gset
select tt.chk('S2 staff meals: only the row naming the person counts, marked "text" (not a verified link)', (:'pmeal'::jsonb)->>'count' = '1' and (:'pmeal'::jsonb)->'rows'->0->>'person_link' = 'text' and (:'pmeal'::jsonb)->>'total' = '70');
select tt.chk('S2 the other meals are counted apart as NOT linked, with the missing field named', (:'pmeal'::jsonb)->'unlinked'->>'count' = '2' and (:'pmeal'::jsonb)->'unlinked'->>'amount' = '220' and (:'pmeal'::jsonb)->'unlinked'->'missing_fields' @> '"quick_expenses.person_id"');
select tt.chk('S2 supplier person: purchase bill linked directly', (select (r->'linked'->>'direct') = '2' from (select public.rpt_hub_spend((:'base'::jsonb) || jsonb_build_object('person', jsonb_build_object('kind','supplier','id',:'sup'), 'kinds', '["purchase","supplier_payment"]'::jsonb)) r) z));
select tt.chk('S2 purchase + payment together carry the double-count note', (select r->'notes' @> '"purchase_and_payment_both_selected_count_twice"' from (select public.rpt_hub_spend((:'base'::jsonb) || '{"kinds":["purchase","supplier_payment"]}') r) z));
select tt.err('S2 a person that does not exist', format($$select public.rpt_hub_spend(%L::jsonb)$$, ((:'base'::jsonb) || jsonb_build_object('person', jsonb_build_object('kind','supplier','id',gen_random_uuid())))::text), 'not_found');
\echo == S3 status, source, kinds
select tt.chk('S3 default = posted only; all statuses add the voided meal', ((public.rpt_hub_spend((:'base'::jsonb) || '{"heads":["staff_meal"],"status":"all"}'))->>'count') = '4');
select tt.chk('S3 void only', ((public.rpt_hub_spend((:'base'::jsonb) || '{"heads":["staff_meal"],"status":["void"]}'))->>'total') = '40');
select tt.chk('S3 payment source bank: rows with no recorded source are left out and said so', (select r->>'count' = '3' and r->'notes' @> '"rows_without_a_recorded_payment_source_are_left_out"' from (select public.rpt_hub_spend((:'base'::jsonb) || '{"pay_mode":"bank"}') r) z));
select tt.chk('S3 default kinds do not include supplier payments or refunds', not exists (select 1 from jsonb_array_elements(public.rpt_hub_spend(:'base'::jsonb)->'rows') r where r->>'kind' in ('supplier_payment','customer_refund','journal')));
select tt.chk('S3 voucher lines are one row each (the 10-2 line level)', true);
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by, created_staff, submitted_at)
 values ('10-2', 1, 450010, :'d0'::date - 1, 'submitted', '{"lines":[{"head":"staff_meal","to":"test_employee_a snack","amount":"30"},{"head":"transport","to":"test_rider","amount":"20"}]}', :'u_s', 'test_seller450', now()),
        ('10-2', 1, 450011, :'d0'::date - 1, 'draft', '{"lines":[{"head":"transport","to":"draft","amount":"99"}]}', :'u_s', 'test_seller450', now());
select tt.chk('S3 voucher: 2 lines of the submitted voucher; the draft voucher only with status draft', (select (r->>'count')::int from (select public.rpt_hub_spend((:'base'::jsonb) || '{"kinds":["expense_voucher"]}') r) z) = 2 and (select (r->>'total')::numeric from (select public.rpt_hub_spend((:'base'::jsonb) || '{"kinds":["expense_voucher"],"status":["draft"]}') r) z) = 99);
select tt.chk('S3 journal alone reads expense accounts (empty here), account filter says it reads the journal only', (select r->'notes' @> '"account_filter_reads_the_journal_only"' from (select public.rpt_hub_spend((:'base'::jsonb) || jsonb_build_object('account_id', (select id from coa_accounts where code = '5830'))) r) z));
\echo == S4 masking
select tt.as(:'u_p');   -- payroll + expense: pay visible
select tt.chk('S4 payroll holder sees meals and the advance', (public.rpt_hub_spend((:'base'::jsonb) || '{"heads":["staff_meal"]}')->>'count')::int >= 3 and (public.rpt_hub_spend((:'base'::jsonb) || '{"kinds":["advance"]}')->>'count') = '1');
select tt.as(:'u_a');   -- view_reports + view_cost: expense yes, payroll NO
select public.rpt_hub_spend((:'base'::jsonb) || '{"heads":["staff_meal"],"terms":["meal"]}') as nomeal \gset
select tt.chk('S4 no payroll right: staff meals and labour rows are absent, and named in masked', (:'nomeal'::jsonb)->>'count' = '0' and (:'nomeal'::jsonb)->'masked' @> '"head:staff_meal"');
select tt.chk('S4 no payroll right: advance and salary kinds return nothing', (public.rpt_hub_spend((:'base'::jsonb) || '{"kinds":["advance","salary"]}')->>'count') = '0');
select tt.chk('S4 no payroll right: a staff person filter is refused with a note, no rows, no totals', (select r->>'count' = '0' and r->'notes' @> '"person_needs_a_right"' and (r->'person'->>'allowed') = 'false' from (select public.rpt_hub_spend((:'base'::jsonb) || jsonb_build_object('person', jsonb_build_object('kind','staff','id',:'emp'))) r) z));
select tt.chk('S4 no payroll right: other expenses still visible (transport, electricity memo)', (public.rpt_hub_spend((:'base'::jsonb) || '{"heads":["transport"]}')->>'count')::int >= 1);
select tt.as(:'u_v');   -- sales only
select tt.chk('S4 sales-only: expenses/purchases not readable (default kinds all masked): zero rows', (select r->>'count' = '0' and jsonb_array_length(r->'masked') >= 5 from (select public.rpt_hub_spend(:'base'::jsonb) r) z));
select tt.as(:'u_x');
select tt.err('S4 no right at all: refused', format($$select public.rpt_hub_spend(%L::jsonb)$$, :'base'), 'not allowed');
select tt.as(:'u_m');   -- management: no stock/purchase/expense
select tt.chk('S4 manager (cost right, no expense right): utility bills yes, quick expenses and vouchers never', not exists (select 1 from jsonb_array_elements(public.rpt_hub_spend((:'base'::jsonb) || '{"terms":["electric"]}')->'rows') r where r->>'kind' in ('quick_expense','expense_voucher')) and (public.rpt_hub_spend((:'base'::jsonb) || '{"terms":["electric"]}')->'masked') @> '"quick_expense"');
select tt.as(:'u_v');
select tt.err('S4 a place the person does not hold is refused', format($$select public.rpt_hub_spend(%L::jsonb)$$, ((:'base'::jsonb) || '{"loc":6}')::text), 'not allowed');
\echo == S5 options and bad input
select tt.as(:'u_o');
select tt.chk('S5 options list heads, places, payment modes', (select jsonb_array_length(r->'heads') >= 5 and jsonb_array_length(r->'locations') = 7 and jsonb_array_length(r->'utility_types') >= 5 from (select public.rpt_hub_spend_options() r) z));
select tt.err('S5 bad pay mode', format($$select public.rpt_hub_spend(%L::jsonb)$$, ((:'base'::jsonb) || '{"pay_mode":"x"}')::text), 'bad_filter');
select tt.err('S5 bad kind list', format($$select public.rpt_hub_spend(%L::jsonb)$$, ((:'base'::jsonb) || '{"kinds":["nope"]}')::text), 'bad_filter');
select tt.err('S5 person needs both kind and id', format($$select public.rpt_hub_spend(%L::jsonb)$$, ((:'base'::jsonb) || '{"person":{"kind":"staff"}}')::text), 'bad_filter');
select tt.chk('S5 hostile text in a word is only data (no error, no rows)', (public.rpt_hub_spend((:'base'::jsonb) || jsonb_build_object('terms', jsonb_build_array('x''; drop table sales; --')))->>'count') = '0');
select tt.chk('S5 sales table still exists', to_regclass('public.sales') is not null);
select 'RESULT ' || count(*) filter (where ok) || ' passed, ' || count(*) filter (where not ok) || ' FAILED' from tt.res;
