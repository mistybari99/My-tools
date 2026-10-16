-- Phase 88 before/after helper: the phase 87 snapshots (P&L, balance sheet, trial balance, cash flow, day book, journal lines, balance check, posting dry run) plus the customer and supplier sub-ledger figures.
-- usage: psql ... -v label=before -f p88_snap.sql      (the owner session claim is set by p87_snap.sql)
\set ON_ERROR_STOP on
\ir p87_snap.sql
insert into tt.snap select :'label', 'p88_cust_bal', (select coalesce(jsonb_agg(jsonb_build_array(c.mobile, public._cust_bal(c.id)) order by c.mobile), '[]'::jsonb)::text from public.customers c);
insert into tt.snap select :'label', 'p88_customer_dues', (select coalesce(jsonb_agg(jsonb_build_array(d.mobile, d.name, d.credit_limit, d.balance, d.oldest) order by d.mobile), '[]'::jsonb)::text from public.customer_dues() d);
insert into tt.snap select :'label', 'p88_customer_ledger', (select coalesce(jsonb_agg(jsonb_build_array(c.mobile, l.kind, l.debit, l.credit, l.balance) order by c.mobile, l.at, l.kind, l.debit), '[]'::jsonb)::text
  from public.customers c, lateral public.customer_ledger(c.id) l);
insert into tt.snap select :'label', 'p88_customer_directory', (select coalesce(jsonb_agg(jsonb_build_array(d.mobile, d.balance) order by d.mobile), '[]'::jsonb)::text from public.customer_directory() d);
insert into tt.snap select :'label', 'p88_sup_balance', (select coalesce(jsonb_agg(jsonb_build_array(s.name, public._sup_balance(s.id)) order by s.name), '[]'::jsonb)::text from public.suppliers s);
insert into tt.snap select :'label', 'p88_supplier_ledger', (select coalesce(jsonb_agg(jsonb_build_array(s.name, l.kind, l.debit, l.credit, l.balance) order by s.name, l.at, l.kind), '[]'::jsonb)::text from public.suppliers s, lateral public.supplier_ledger(s.id) l);
insert into tt.snap select :'label', 'p88_acct_reconcile', (select jsonb_build_object('c', coalesce((select jsonb_agg(jsonb_build_array(x ->> 'name', x ->> 'journal', x ->> 'existing', x ->> 'difference') order by x ->> 'name') from jsonb_array_elements(r -> 'customers') x), '[]'::jsonb),
  's', coalesce((select jsonb_agg(jsonb_build_array(x ->> 'name', x ->> 'journal', x ->> 'existing', x ->> 'difference') order by x ->> 'name') from jsonb_array_elements(r -> 'suppliers') x), '[]'::jsonb), 'u', r -> 'unattributed_receivable')::text from (select public.acct_reconcile('all') r) z);
select :'label' as label, count(*) as p88_snapshots from tt.snap where label = :'label' and name like 'p88_%';
