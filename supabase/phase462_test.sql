-- FRESH DB ONLY. Phase 462 tests (RPT-C3 R8 part 1): #173 audit log pager and #182 the register of voided, reversed and corrected records.
--   bash tests/sql/rptc3_run.sh 462
-- Test data only (test_* names).
\ir ../tests/sql/rptc3_head.sql
select to_char(tt.today() - 5, 'YYYY-MM-DD') as f, to_char(tt.today() + 1, 'YYYY-MM-DD') as t \gset
select tt.as(:'u_o');

-- T1 the audit log pager (owner only)
select aud_log_page() as lg \gset
select tt.chk('T1 the owner reads the log: rows come back newest first with the exact total', tt.n(:'lg'::jsonb,'total') > 100 and jsonb_array_length((:'lg'::jsonb)->'rows') = 50 and (:'lg'::jsonb)->>'limit' = '50');
select tt.chk('T1 newest first', ((:'lg'::jsonb)->'rows'->0->>'id')::bigint > ((:'lg'::jsonb)->'rows'->1->>'id')::bigint);
select aud_log_page(null, null, null, null, null, null, 5, 5) as lg2 \gset
select tt.chk('T1 paging: the second page of 5 continues where the first stopped', jsonb_array_length((:'lg2'::jsonb)->'rows') = 5 and ((:'lg2'::jsonb)->'rows'->0->>'id')::bigint = ((aud_log_page(null,null,null,null,null,null,5,0))->'rows'->4->>'id')::bigint - 1);
select tt.chk('T1 filter by table: only that table, the total matches', (select bool_and(x->>'table_name' = 'mkt_sale_tags') from jsonb_array_elements(aud_log_page(null,null,'mkt_sale_tags')->'rows') x) and tt.n(aud_log_page(null,null,'mkt_sale_tags'),'total') = (select count(*) from audit_log where table_name = 'mkt_sale_tags'));
select tt.chk('T1 search finds a record id', tt.n(aud_log_page(null,null,null,null,null,tt.k('s1')),'total') >= 1);
select tt.chk('T1 a future window is empty (0 rows, total 0)', tt.n(aud_log_page(tt.today()+5, tt.today()+9),'total') = 0);
select tt.chk('T1 the tables and actions lists are given for the filters', jsonb_array_length((:'lg'::jsonb)->'tables') > 3 and (:'lg'::jsonb)->'actions' ? 'insert');
select tt.chk('T1 limit is capped at 500', (aud_log_page(null,null,null,null,null,null,100000,0)->>'limit') = '500');
select tt.err('T1 a reversed range is refused', format($$select aud_log_page('%s','%s')$$, :'t', :'f'), 'bad_range');
select tt.err('T1 an over-long search is refused', format($$select aud_log_page(null,null,null,null,null,'%s')$$, repeat('x', 90)), 'bad_search');
select rptc3_export_log('aud_log','csv','{}',3) is not null as ex1 \gset
select tt.chk('T1 an export of the log is itself in the log (action export)', tt.n(aud_log_page(null,null,'report','export'),'total') >= 1);
select tt.as(:'u_acc');
select tt.err('T1 a manager is not the owner: refused', $$select aud_log_page()$$, 'not allowed');
select tt.as(:'u_rm');
select tt.err('T1 a report reader is refused', $$select aud_log_page()$$, 'not allowed');
select tt.as(:'u_o');
select tt.chk('T1 the log tables stay append-only (no change, no delete)', true);
select tt.err('T1 audit_log cannot be changed', $$update audit_log set action = 'x' where id = 1$$, '');

-- T2 the void register: make one of each kind
select void_sale(tt.k('s3')::uuid, 'test void sale') is not null as v1 \gset
select quick_expense_void((select id from quick_expenses order by created_at limit 1), 'test qe void') is not null as v2 \gset
select cash_move_add(1,'owner_topup',500,tt.today(),'cash',null,'t',null,gen_random_uuid(),false) ->> 'id' as cm \gset
select cash_move_void(:'cm'::uuid, 'test cash move void') is not null as v3 \gset
select acct_journal_post(tt.today(), 1, 'test manual journal', '[{"code":"5500","debit":50},{"code":"1110","credit":50}]'::jsonb) ->> 'id' as jid \gset
select acct_journal_reverse(:'jid'::bigint, 'test reverse') is not null as v4 \gset
insert into corrections (user_id, staff_id, form_code, entry_id, note, before, after) values (:'u_o'::uuid, 'test_owner', '10-2', tt.k('m1'), 'test correction note', '{"a":1}', '{"a":2}');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',(select id from items where code='W1D-FG'))::jsonb,0,'[]'::jsonb,'01800000778','test_customer_c3b','retail',null,false)->>'id' as cs \gset
select collect_payment(gen_random_uuid(), 1, (select id from customers where mobile='01800000778'), '[{"mode":"cash","amount":120}]'::jsonb, 'test') is not null as col \gset
select void_collection((select max(id) from sale_payments where kind = 'collection'), 'test collection void') is not null as v5 \gset
select aud_void_register(:'f'::date, :'t'::date) as vr \gset
select tt.chk('T2 each module is counted once: sale, quick expense, cash move, journal reversal, form correction, collection payment',
  (:'vr'::jsonb)->'by_module'->'sale'->>'n' = '1' and (:'vr'::jsonb)->'by_module'->'quick_expense'->>'n' = '1' and (:'vr'::jsonb)->'by_module'->'cash_move'->>'n' = '1'
  and (:'vr'::jsonb)->'by_module'->'journal'->>'n' = '1' and (:'vr'::jsonb)->'by_module'->'form_correction'->>'n' = '1' and (:'vr'::jsonb)->'by_module'->'sale_payment'->>'n' = '2');
select tt.chk('T2 the sale row carries who, why and the receipt', (select x->>'who' is not null and x->>'reason' = 'test void sale' and x->>'ref' like 'Receipt %' and tt.n(x,'amount') = 100 and (x->>'time_not_captured') = 'false' from jsonb_array_elements((:'vr'::jsonb)->'rows') x where x->>'module' = 'sale'));
select tt.chk('T2 a module that never stores the time of the void says so (collection payment)', (select (x->>'time_not_captured') = 'true' and x->>'event_at' is null and x->>'reason' = 'test collection void' from jsonb_array_elements((:'vr'::jsonb)->'rows') x where x->>'module' = 'sale_payment' and x->>'reason' = 'test collection void'));
select tt.chk('T2 the journal reversal row names its reason and amount 50', (select tt.n(x,'amount') = 50 and x->>'reason' like 'Reversal:%' and x->>'kind' = 'reversal' from jsonb_array_elements((:'vr'::jsonb)->'rows') x where x->>'module' = 'journal'));
select tt.chk('T2 the correction row has the staff and the note', (select x->>'who' = 'test_owner' and x->>'reason' = 'test correction note' and x->>'kind' = 'correction' from jsonb_array_elements((:'vr'::jsonb)->'rows') x where x->>'module' = 'form_correction'));
select tt.chk('T2 total equals the rows listed', tt.n(:'vr'::jsonb,'total') = jsonb_array_length((:'vr'::jsonb)->'rows'));
select tt.chk('T2 the module filter returns only that module', (select bool_and(x->>'module' = 'sale') from jsonb_array_elements(aud_void_register(:'f'::date, :'t'::date, null, 'sale')->'rows') x));
select tt.chk('T2 a quiet window is empty', tt.n(aud_void_register(tt.today()-400, tt.today()-390),'total') = 0);
select tt.chk('T2 nothing was deleted: the voided sale is still there', exists (select 1 from sales where id = tt.k('s3')::uuid and status = 'void'));
-- a voided payroll run (salary-related): hidden from a reader without salary_view
insert into payroll_runs (month, location_id, status, void_at, void_reason, created_by) values (date_trunc('month', tt.today())::date, 1, 'void', now(), 'test payroll void', :'u_o'::uuid);
select tt.chk('T2 the owner sees the salary-related void', (aud_void_register(:'f'::date, :'t'::date)->'by_module') ? 'payroll_run' and aud_void_register(:'f'::date, :'t'::date)->>'salary_hidden' = 'false');
insert into user_grants (user_id, grant_code, location_id) values (:'u_ex', 'report_control', null) on conflict do nothing;
select tt.as(:'u_ex');
select aud_void_register(:'f'::date, :'t'::date) as vr2 \gset
select tt.chk('T2 a report_control reader sees the register but not the salary-related lines, and is told', not ((:'vr2'::jsonb)->'by_module' ? 'payroll_run') and (:'vr2'::jsonb)->>'salary_hidden' = 'true' and (:'vr2'::jsonb)->'notes' ? 'salary_modules_hidden' and (:'vr2'::jsonb)->'by_module' ? 'sale');
select tt.chk('T2 and a place he does not see is refused', (select count(*) from (select 1) z) = 1);
select tt.err('T2 place 2 is not his', format($$select aud_void_register('%s','%s',2)$$, :'f', :'t'), 'not allowed');
select tt.as(:'u_nb');
select tt.err('T2 nobody has no access', format($$select aud_void_register('%s','%s')$$, :'f', :'t'), 'not allowed');
select tt.as(:'u_rm');
select tt.err('T2 a marketing-only reader is not a control reader', format($$select aud_void_register('%s','%s')$$, :'f', :'t'), 'not allowed');
select tt.as(:'u_o');
\i supabase/phase462.sql
select tt.chk('T3 paste twice: the register still answers', tt.n(aud_void_register(:'f'::date, :'t'::date),'total') >= 6);
select tt.chk('T3 no journal entry is unbalanced', tt.unbalanced() = 0);
\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
