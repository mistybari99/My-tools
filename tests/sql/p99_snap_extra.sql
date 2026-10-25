-- Phase 99 before/after helper, part 2 (part 1 is tests/sql/w1d_snap.sql: P&L, L1 L3 L4 L5 T4 E2 E3, expense report, partner calculation and split, brand P&L, income statement, balance sheet,
-- trial balance, cash flow, day book, day book versus journal, journal lines, posting dry run). This part adds the STOCK reports and the sub-ledgers the Wave 1 hooks read (customer dues, ledger, balance,
-- supplier balance, sale returns, stock movements). Item ids are left out so a twin database compares equal. usage: psql ... -v label=before -f p99_snap_extra.sql
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', false);
create schema if not exists tt;
create table if not exists tt.snap (label text, name text, val text);
delete from tt.snap where label = :'label' and name like 'x\_%';
insert into tt.snap select :'label', 'x_stock_levels', (select coalesce(jsonb_agg((to_jsonb(x) - 'item_id') order by x.code), '[]'::jsonb)::text from public.stock_levels(1, '{}'::jsonb) x);
insert into tt.snap select :'label', 'x_stock_levels_all', (select coalesce(jsonb_agg((to_jsonb(x) - 'item_id') order by x.location_id, x.code), '[]'::jsonb)::text from public.stock_levels(null, '{}'::jsonb) x);
insert into tt.snap select :'label', 'x_stock_valuation', (select coalesce(jsonb_agg((to_jsonb(x) - 'item_id') order by x.location_id, x.code), '[]'::jsonb)::text from public.stock_valuation(null) x);
insert into tt.snap select :'label', 'x_stock_movements', (select coalesce(jsonb_agg(jsonb_build_array(i.code, s.location_id, s.reason, s.qty_delta, s.unit_cost, s.ref_type) order by i.code, s.location_id, s.reason, s.qty_delta, s.unit_cost, s.ref_type), '[]'::jsonb)::text
    from public.stock_ledger s join public.items i on i.id = s.item_id);
insert into tt.snap select :'label', 'x_customer_dues', (select coalesce(jsonb_agg((to_jsonb(x) - 'id') order by x.mobile), '[]'::jsonb)::text from public.customer_dues() x);
insert into tt.snap select :'label', 'x_customer_ledger', (select coalesce(jsonb_agg(jsonb_build_array(l.kind, l.debit, l.credit, l.note) order by l.at, l.kind, l.debit), '[]'::jsonb)::text
    from public.customers c cross join lateral public.customer_ledger(c.id) l where c.mobile = '01800000999');
insert into tt.snap select :'label', 'x_customer_balance', (select coalesce(jsonb_agg(jsonb_build_array(c.mobile, public.customer_balance(c.id)) order by c.mobile), '[]'::jsonb)::text from public.customers c);
insert into tt.snap select :'label', 'x_supplier_balance', (select coalesce(jsonb_agg(jsonb_build_array(s.name, public._sup_balance(s.id)) order by s.name), '[]'::jsonb)::text from public.suppliers s);
insert into tt.snap select :'label', 'x_sale_returns', (select coalesce(jsonb_agg(jsonb_build_array(r.amount, r.refund_amount, r.refund_mode) order by r.amount, r.refund_mode), '[]'::jsonb)::text from public.sale_returns r);
insert into tt.snap select :'label', 'x_payments', (select coalesce(jsonb_agg(jsonb_build_array(p.kind, p.mode, p.wallet, p.amount, p.voided) order by p.kind, p.mode, p.amount, p.wallet), '[]'::jsonb)::text from public.sale_payments p);
insert into tt.snap select :'label', 'x_cash_moves', (select coalesce(jsonb_agg(jsonb_build_array(m.kind, m.amount, m.mode, m.status) order by m.kind, m.amount, m.mode, m.status), '[]'::jsonb)::text from public.cash_moves m);
insert into tt.snap select :'label', 'x_acct_reconcile', (select coalesce(jsonb_agg(x order by x::text), '[]'::jsonb)::text from (select public.acct_reconcile('customer') x union all select public.acct_reconcile('supplier')) z);
select :'label' as label, count(*) as extra_snapshots from tt.snap where label = :'label' and name like 'x\_%';
