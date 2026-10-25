-- CRM-B before/after snapshot: customer-side figures that must not change (the accounting reports come from p87_snap.sql, run first with the same label).
-- usage: psql ... -v label=before -f tests/sql/crmb_snap.sql      (adds rows to tt.snap)
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000987', false);
create schema if not exists tt;
create table if not exists tt.snap (label text, name text, val text);
create or replace function tt.safe_run(p_key text) returns text language plpgsql as $$
begin return coalesce((public.report_run2(p_key, '{}'::jsonb, null, null, 1) -> 'rows')::text, 'null');
exception when others then begin return coalesce((public.report_run(p_key, '{}'::jsonb, null, null, 1, false) -> 'rows')::text, 'null'); exception when others then return 'n/a: ' || sqlerrm; end; end $$;
delete from tt.snap where label = :'label' and name like 'crm\_%';
insert into tt.snap select :'label', 'crm_customer_dues', (select coalesce(jsonb_agg(to_jsonb(d) order by d.id), '[]'::jsonb)::text from public.customer_dues() d);
insert into tt.snap select :'label', 'crm_customer_directory', (select coalesce(jsonb_agg(to_jsonb(d) order by d.id), '[]'::jsonb)::text from public.customer_directory() d);
insert into tt.snap select :'label', 'crm_customer_ledgers', (select coalesce(string_agg(c.id::text || '=' || (select coalesce(jsonb_agg(to_jsonb(x) - 'at' order by x.at, x.kind, x.debit, x.credit), '[]'::jsonb)::text from public.customer_ledger(c.id) x), ',' order by c.id), '') from public.customers c);
insert into tt.snap select :'label', 'crm_customer_balances', (select coalesce(string_agg(c.id::text || ':' || public._cust_bal(c.id)::text, ',' order by c.id), '') from public.customers c);
insert into tt.snap select :'label', 'crm_customer_profiles', (select coalesce(string_agg(public.customer_profile(c.id)::text, ',' order by c.id), '') from public.customers c);
insert into tt.snap select :'label', 'crm_sales_payments', (select coalesce(string_agg(s.id::text || ':' || s.total::text || ':' || coalesce(s.customer_id::text, ''), ',' order by s.id), '') from public.sales s)
  || '|' || (select coalesce(string_agg(p.id::text || ':' || p.amount::text || ':' || p.mode, ',' order by p.id), '') from public.sale_payments p);
insert into tt.snap select :'label', 'crm_journal_party_lines', (select coalesce(string_agg(e.source_type || ':' || l.debit::text || ':' || l.credit::text || ':' || coalesce(l.party_type, '') || ':' || coalesce(l.party_id, ''), ',' order by l.entry_id, l.line_no), '')
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id);
insert into tt.snap select :'label', 'crm_report_best_customers', tt.safe_run('best_customers');
insert into tt.snap select :'label', 'crm_report_d5_lapsed', tt.safe_run('d5_lapsed');
insert into tt.snap select :'label', 'crm_report_m1_rfm', tt.safe_run('m1_rfm');
insert into tt.snap select :'label', 'crm_non_crm_rules', (select coalesce(string_agg(key || '=' || coalesce(value::text, 'default'), ',' order by key), '') from public.rules where key not like 'crm\_%');
insert into tt.snap select :'label', 'crm_notify_state', (select count(*)::text from public.notify_optin) || '/' || (select count(*)::text from public.notify_outbox);
select :'label' as label, count(*) as crm_snapshots from tt.snap where label = :'label' and name like 'crm\_%';
