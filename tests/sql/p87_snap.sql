-- Phase 87 before/after helper: take a normalized snapshot of the reports that must not change when phase 87 is pasted on an install with no money account.
-- usage: psql ... -v label=before -f p87_snap.sql     (the owner session claim must be set by the caller; this file sets it)
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000987', false);
create schema if not exists tt;
create table if not exists tt.snap (label text, name text, val text);
create or replace function tt.norm_db(p jsonb) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg((d - 'lines') || jsonb_build_object('lines', coalesce((select jsonb_agg(l - 'at' - 'who' - 'ref' - 'src_id' order by l::text) from jsonb_array_elements(d -> 'lines') l), '[]'::jsonb)) order by d ->> 'date'), '[]'::jsonb)
    from jsonb_array_elements(p -> 'days') d $$;
delete from tt.snap where label = :'label';
select date_trunc('month', (now() at time zone 'Asia/Dhaka')::date - interval '1 month')::date as d1 \gset
select (now() at time zone 'Asia/Dhaka')::date as d2 \gset
insert into tt.snap select :'label', 'p27_pl_all', (select coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text), '[]'::jsonb)::text from public._p27_pl(:'d1'::date, :'d2'::date, array[1,2,3,4]) p);
insert into tt.snap select :'label', 'income_statement', public.acct_income_statement(:'d1'::date, :'d2'::date)::text;
insert into tt.snap select :'label', 'balance_sheet', public.acct_balance_sheet(:'d2'::date)::text;
insert into tt.snap select :'label', 'trial_balance', public.acct_trial_balance(:'d1'::date, :'d2'::date)::text;
insert into tt.snap select :'label', 'cash_flow', public.acct_cash_flow(:'d1'::date, :'d2'::date)::text;
insert into tt.snap select :'label', 'day_book_p1', tt.norm_db(public.day_book(1, :'d1'::date, :'d2'::date))::text;
insert into tt.snap select :'label', 'day_book_totals_p1', (public.day_book(1, :'d1'::date, :'d2'::date) -> 'totals')::text;
insert into tt.snap select :'label', 'day_book_all', tt.norm_db(public.day_book(null, :'d1'::date, :'d2'::date))::text;
insert into tt.snap select :'label', 'daybook_vs_journal', (public.daybook_vs_journal(:'d1'::date, :'d2'::date) - 'accounting_start')::text;
insert into tt.snap select :'label', 'journal_lines', (select coalesce(jsonb_agg(jsonb_build_array(e.source_type, a.code, l.debit, l.credit, e.entry_date) order by e.source_type, e.entry_date, a.code, l.debit, l.credit), '[]'::jsonb)::text
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id);
insert into tt.snap select :'label', 'balance_check_core', (select jsonb_build_object('status', x ->> 'status', 'equation', x -> 'equation', 'trial', x -> 'trial_balance', 'journal', x -> 'journal', 'stock', x -> 'stock_identity',
    'dvj', x #> '{cross_checks,daybook_vs_journal}', 'inv', x #> '{cross_checks,inventory_vs_gl}')::text from (select public._e_balance_check() x) z);
insert into tt.snap select :'label', 'post_dry', (public.acct_post_pending(true) - 'preview' - 'trial')::text;
select :'label' as label, count(*) as snapshots from tt.snap where label = :'label';
