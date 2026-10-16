-- W1-D before/after helper: a normalized snapshot of every figure that phases 92 and 93 must not change while all their settings are at the default.
-- usage: psql ... -v label=before -f w1d_snap.sql     (the owner session claim is set here)
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', false);
create schema if not exists tt;
create table if not exists tt.snap (label text, name text, val text);
create or replace function tt.norm_db(p jsonb) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg((d - 'lines') || jsonb_build_object('lines', coalesce((select jsonb_agg(l - 'at' - 'who' - 'ref' - 'src_id' order by l::text) from jsonb_array_elements(d -> 'lines') l), '[]'::jsonb)) order by d ->> 'date'), '[]'::jsonb)
    from jsonb_array_elements(p -> 'days') d $$;
delete from tt.snap where label = :'label';
select (now() at time zone 'Asia/Dhaka')::date as d2 \gset
select date_trunc('month', :'d2'::date - interval '1 month')::date as d1 \gset
select date_trunc('month', :'d2'::date)::date as m1 \gset
select v as ag from tt.kv where k = 'ag' \gset
insert into tt.snap select :'label', 'p27_pl', (select coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text), '[]'::jsonb)::text from public._p27_pl(:'d1'::date, :'d2'::date, array[1,2,3,4]) p);
insert into tt.snap select :'label', 'l1_pnl', (select coalesce(jsonb_agg(x order by x::text), '[]'::jsonb)::text from public._r3q_l1_pnl(:'d1'::date, :'d2'::date, array[1,2,3,4], '{}'::jsonb) x);
insert into tt.snap select :'label', 'l3_shop_pnl', (select coalesce(jsonb_agg(x order by x::text), '[]'::jsonb)::text from public._r3q_l3_shop_pnl(:'d1'::date, :'d2'::date, array[1,2,3,4], '{}'::jsonb) x);
insert into tt.snap select :'label', 'l4_owner_sheet', (select coalesce(jsonb_agg(x order by x::text), '[]'::jsonb)::text from public._r3q_l4_owner_sheet(:'d1'::date, :'d2'::date, array[1,2,3,4], '{}'::jsonb) x);
insert into tt.snap select :'label', 'l5_breakeven', (select coalesce(jsonb_agg(x order by x::text), '[]'::jsonb)::text from public._r3q_l5_breakeven(:'d1'::date, :'d2'::date, array[1,2,3,4], '{}'::jsonb) x);
insert into tt.snap select :'label', 't4_staff_cost', (select coalesce(jsonb_agg(x order by x::text), '[]'::jsonb)::text from public._r3q_t4_staff_cost_ratio(:'d1'::date, :'d2'::date, array[1,2,3,4], '{}'::jsonb) x);
insert into tt.snap select :'label', 'e2_expense_trend', (select coalesce(jsonb_agg(x order by x::text), '[]'::jsonb)::text from public._r3q_e2_expense_trend(:'d1'::date, :'d2'::date, array[1,2,3,4], '{}'::jsonb) x);
insert into tt.snap select :'label', 'e3_weak_control', (select coalesce(jsonb_agg(x order by x::text), '[]'::jsonb)::text from public._r3q_e3_weak_control(:'d1'::date, :'d2'::date, array[1,2,3,4], '{}'::jsonb) x);
insert into tt.snap select :'label', 'expense_by_head', (public.report_run2_core('expense_by_head', jsonb_build_object('from', :'d1'::date, 'to', :'d2'::date), null) - 'generated_at')::text;
insert into tt.snap select :'label', 'partner_calculate', ((c - 'profit_basis') || jsonb_build_object('steps', (select coalesce(jsonb_agg(s - 'key'), '[]'::jsonb) from jsonb_array_elements(c -> 'steps') s)))::text from (select public.partner_calculate(:'ag'::bigint, :'m1'::date, :'d2'::date) c) z;   -- step keys are random uuids; profit_basis is new in phase 92
insert into tt.snap select :'label', 'partner_month_split', (public.c_partner_month_split(:'m1'::date))::text;
insert into tt.snap select :'label', 'brand_pnl', (select coalesce(jsonb_agg(to_jsonb(b) order by to_jsonb(b)::text), '[]'::jsonb)::text from public.brand_pnl(:'d1'::date, :'d2'::date, null) b);
insert into tt.snap select :'label', 'income_statement', public.acct_income_statement(:'d1'::date, :'d2'::date)::text;
insert into tt.snap select :'label', 'balance_sheet', public.acct_balance_sheet(:'d2'::date)::text;
insert into tt.snap select :'label', 'trial_balance', public.acct_trial_balance(:'d1'::date, :'d2'::date)::text;
insert into tt.snap select :'label', 'cash_flow', public.acct_cash_flow(:'d1'::date, :'d2'::date)::text;
insert into tt.snap select :'label', 'day_book_all', tt.norm_db(public.day_book(null, :'d1'::date, :'d2'::date))::text;
insert into tt.snap select :'label', 'day_book_totals', (public.day_book(null, :'d1'::date, :'d2'::date) -> 'totals')::text;
insert into tt.snap select :'label', 'daybook_vs_journal', (public.daybook_vs_journal(:'d1'::date, :'d2'::date) - 'accounting_start')::text;
insert into tt.snap select :'label', 'journal_lines', (select coalesce(jsonb_agg(jsonb_build_array(e.source_type, a.code, l.debit, l.credit, e.entry_date) order by e.source_type, e.entry_date, a.code, l.debit, l.credit), '[]'::jsonb)::text
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id);
insert into tt.snap select :'label', 'post_dry', (public.acct_post_pending(true) - 'preview' - 'trial')::text;
select :'label' as label, count(*) as snapshots from tt.snap where label = :'label';
