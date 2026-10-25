-- W1-F before/after helper (adds to p87_snap.sql): what a paste of phases 96 + 97 must not move.
-- usage: psql ... -v label=before -f w1f_snap.sql     (the owner session claim is set here)
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000987', false);
create schema if not exists tt;
create table if not exists tt.snap (label text, name text, val text);
delete from tt.snap where label = :'label' and name in ('w1f_dry_trial', 'w1f_dry_accounts', 'w1f_payments', 'w1f_sales_pay_mode', 'w1f_pending_by_type', 'w1f_receivable_party', 'w1f_expense_heads_active');
-- the account every unposted document WOULD post to (a head mapping that moved would show here)
insert into tt.snap select :'label', 'w1f_dry_trial', (public.acct_post_pending(true) -> 'trial')::text;
insert into tt.snap select :'label', 'w1f_dry_accounts', (select coalesce(jsonb_agg(jsonb_build_array(x ->> 'code', x ->> 'debit', x ->> 'credit') order by x::text), '[]'::jsonb)::text
    from jsonb_array_elements(public.acct_post_pending(true) -> 'trial') x);
insert into tt.snap select :'label', 'w1f_payments', (select coalesce(jsonb_agg(jsonb_build_array(kind, mode, amount, wallet, ref, voided, location_id) order by id), '[]'::jsonb)::text from public.sale_payments);
insert into tt.snap select :'label', 'w1f_sales_pay_mode', (select coalesce(jsonb_agg(jsonb_build_array(receipt, pay_mode, total) order by receipt), '[]'::jsonb)::text from public.sales);
insert into tt.snap select :'label', 'w1f_pending_by_type', (public.acct_post_pending(true) -> 'by_type')::text;
insert into tt.snap select :'label', 'w1f_receivable_party', (select coalesce(jsonb_agg(jsonb_build_array(c.name, public.customer_balance(c.id)) order by c.name), '[]'::jsonb)::text from public.customers c);
insert into tt.snap select :'label', 'w1f_expense_heads_active', (select coalesce(jsonb_agg(value_code order by value_code), '[]'::jsonb)::text from public.option_lists where list_code = 'expense_heads' and active);
select :'label' as label, count(*) as w1f_snapshots from tt.snap where label = :'label' and name like 'w1f\_%';
