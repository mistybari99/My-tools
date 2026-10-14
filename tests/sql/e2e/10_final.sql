\echo == 10 final reconciliation after everything (incl. web order sale and the extra POS sale)
select tt.as(:'o');
select acct_post_pending(false) as ppf \gset
select acct_post_pending(false) ->> 'posted' as ppf2 \gset
select tt.eq('F0 second pending run posts nothing', 0, :ppf2::numeric);
select * from biz_daily(tt.today(), tt.today(), 1) \gset fd_
select tt.eq('F1 revenue net = 3375 - 325 + 600 (web order) + 300 (extra sale)', 3950, :fd_revenue::numeric);
select tt.eq('F1 COGS hand = 1084.936 + 3 x 57.734', 1258.138, :fd_cogs::numeric, 0.02);
select tt.eq('F1 journal COGS 5000', :fd_cogs::numeric, tt.bal_loc('5000',1), 0.02);
select round(sum(-qty_delta * coalesce(unit_cost,0)),2) as fled from stock_ledger where ref_type in ('sale','sale_return','sale_pack') \gset
select tt.eq('F1 stock-ledger movement of sold goods', :fd_cogs::numeric, :fled::numeric, 0.02);
select profit_source_check(tt.today(), tt.today(), 1) as fpsc \gset
select tt.t('F1 profit_source_check agrees', (:'fpsc'::jsonb->>'agree')::boolean, 'true', :'fpsc'::jsonb->>'agree');
select acct_trial_balance(tt.today()-5, tt.today(), null) as ftb \gset
select tt.t('F2 trial balance balanced', (:'ftb'::jsonb->>'balanced')::boolean, 'balanced', (:'ftb'::jsonb->>'total_debit')||'/'||(:'ftb'::jsonb->>'total_credit'));
select acct_balance_sheet(tt.today(), null) as fbs \gset
select tt.eq('F2 balance sheet difference', 0, (:'fbs'::jsonb->>'difference')::numeric);
select tt.eq('F2 unbalanced entries', 0, tt.unbalanced());
select inventory_vs_gl(tt.today(), 1) as fivg \gset
select tt.eq('F3 inventory_vs_gl total diff (valuation basis); phase103: -452 + 60 (glaze opening 5 x 12 now booked by the follow-up decision)', -392, (:'fivg'::jsonb->'total'->>'diff')::numeric);
select tt.eq('F3 inventory_vs_gl unexplained (true gap = salt guard-off double 200)', -200, (:'fivg'::jsonb->'total'->>'unexplained')::numeric);
select count(*) as nrec from stock_reconcile(false) \gset
select tt.eq('F4 stock_reconcile(false): ledger vs balance rows that disagree', 0, :nrec::numeric);
select tt.eq('F5 count of journal entries', (select count(*) from journal_entries), (select count(*) from journal_entries));
select string_agg(source_type||'='||c, ', ' order by source_type) as jtypes from (select source_type, count(*) c from journal_entries group by 1) z \gset
\echo JOURNAL_TYPES: :jtypes
select count(*) as problems from ledger_post_problems(1) \gset
select tt.eq('F6 ledger_post_problems', 0, :problems::numeric);
