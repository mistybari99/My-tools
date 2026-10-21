-- CRM-A before/after helper: the accounting snapshot of tests/sql/p87_snap.sql PLUS every existing customer function and customer report, as the owner of the p87 fixture.
-- usage: psql ... -v label=before -f crm_a_snap.sql
\set ON_ERROR_STOP on
\ir p87_snap.sql
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000030201', false);
insert into tt.snap select :'label', 'customer_directory', (select coalesce(jsonb_agg(to_jsonb(d) order by d.name, d.mobile), '[]'::jsonb)::text from public.customer_directory() d);
insert into tt.snap select :'label', 'customer_dues', (select coalesce(jsonb_agg(to_jsonb(d) order by d.name), '[]'::jsonb)::text from public.customer_dues() d);
insert into tt.snap select :'label', 'customer_profile_all', (select coalesce(jsonb_agg(public.customer_profile(c.id) - 'history' order by c.mobile), '[]'::jsonb)::text from public.customers c);
insert into tt.snap select :'label', 'customer_ledger_all', (select coalesce(jsonb_agg(to_jsonb(l) order by c.mobile), '[]'::jsonb)::text from public.customers c cross join lateral public.customer_ledger(c.id) l);
insert into tt.snap select :'label', 'find_customer_all', (select coalesce(jsonb_agg(public.find_customer(c.mobile) order by c.mobile), '[]'::jsonb)::text from public.customers c);
insert into tt.snap select :'label', 'customer_pos_info_all', (select coalesce(jsonb_agg(public.customer_pos_info(c.mobile) order by c.mobile), '[]'::jsonb)::text from public.customers c);
insert into tt.snap select :'label', 'customer_balance_all', (select coalesce(jsonb_agg(jsonb_build_array(c.mobile, public.customer_balance(c.id), public._cust_bal(c.id)) order by c.mobile), '[]'::jsonb)::text from public.customers c);
insert into tt.snap select :'label', 'rpt_best_customers', (select (public.report_run('best_customers', jsonb_build_object('from', (current_date - 90)::text, 'to', current_date::text)) - 'generated_at')::text);
insert into tt.snap select :'label', 'rpt_customer_dues', (select (public.report_run('customer_dues', '{}'::jsonb) - 'generated_at')::text);
insert into tt.snap select :'label', 'customer_save_dup', (select public.customer_save(null, '{"mobile":"01711032001","name":"test_cust_one"}'::jsonb)::text);
-- the definitions of every shared customer / sale / notify function: a hash, so "no shared function was patched" is a number
insert into tt.snap select :'label', 'shared_function_hashes', (select string_agg(p.oid::regprocedure::text || '=' || md5(pg_get_functiondef(p.oid)), ';' order by p.oid::regprocedure::text) from pg_proc p
  where p.pronamespace = 'public'::regnamespace and (p.proname in ('record_sale2','find_customer','customer_save','customer_directory','customer_profile','customer_pos_info','_cust_bal','customer_balance','customer_dues','customer_ledger','collect_payment','notify_scan','notify_enqueue','notify_optin_set','norm_mobile','_acct_docs','day_book','loyalty_award')));
select :'label' as label, count(*) as snapshots from tt.snap where label = :'label';
