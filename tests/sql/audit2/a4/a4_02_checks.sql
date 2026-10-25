\echo == A4-02 hand-computed expectations vs system (end of today, after settlement)
-- HAND-COMPUTED (before running): cash 1110 = 20000+300+100+80+500-100-70-50-400 = 20360 ; bank 1120 = 50000+400-150-300+196 = 50146 ; mobile 1130 = 100 ; card 1140 = 200-200 = 0
-- receivable 1210 = 300+200-200 = 300 ; customer advances 2300 = 500-200 = 300 (cr) ; payable 2100 = 600-300 = 300 (cr)
-- sales 4100 = 300+200+100+400+100+200 = 1300 ; discount 4120 = 20 ; returns 4110 = 100 ; COGS 5000 = (13 units - 1 returned) x 60 = 720
-- 5700 transport 150+50 = 200 ; 5600 repair 70 ; 5810 bank charges 4 ; inventory = 6000 + 600 - 780 + 60 = 5880 ; capital 3100 = 76000 ; profit = 1300-20-100-720-200-70-4 = 186
select tt.eq('E1 cash 1110', 20360, tt.bal('1110'));
select tt.eq('E1 bank 1120', 50146, tt.bal('1120'));
select tt.eq('E1 mobile 1130', 100, tt.bal('1130'));
select tt.eq('E1 card receivable 1140', 0, tt.bal('1140'));
select tt.eq('E1 customer receivable 1210', 300, tt.bal('1210'));
select tt.eq('E1 customer advance 2300 (credit)', -300, tt.bal('2300'));
select tt.eq('E1 supplier payable 2100 (credit)', -300, tt.bal('2100'));
select tt.eq('E1 sales 4100 (credit)', -1300, tt.bal('4100'));
select tt.eq('E1 discount 4120', 20, tt.bal('4120'));
select tt.eq('E1 returns 4110', 100, tt.bal('4110'));
select tt.eq('E1 COGS 5000', 720, tt.bal('5000'));
select tt.eq('E1 transport 5700', 200, tt.bal('5700'));
select tt.eq('E1 repair 5600', 70, tt.bal('5600'));
select tt.eq('E1 bank charges 5810', 4, tt.bal('5810'));
select tt.eq('E1 inventory 1310+1320+1330', 5880, tt.bal('1310')+tt.bal('1320')+tt.bal('1330'));
select tt.eq('E1 cash short/over 5800 (physical shortage 10 NOT booked)', 0, tt.bal('5800'));
select tt.eq('E1 trial balance Dr-Cr', 0, (select sum(debit-credit) from journal_lines));
select tt.eq('E1 profit (income - expense accounts)', 186, (select -sum(l.debit-l.credit) from journal_lines l join coa_accounts a on a.id=l.account_id where a.type in ('income','expense')));
-- sub-ledgers
select acct_reconcile('all') as rc \gset
\echo ACCT_RECONCILE: :rc
select tt.eq('R1 receivable subledger vs GL: customers differing', 0, (:'rc'::jsonb->>'customers_off')::numeric);
select tt.eq('R1 payables subledger vs GL: suppliers differing', 0, (:'rc'::jsonb->>'suppliers_off')::numeric);
select tt.eq('R1 customer_dues total (dues list) vs GL receivable', 300, (select coalesce(sum(balance),0) from customer_dues()));
select tt.eq('R1 payables_summary total vs GL', 300, (select total_payable from payables_summary(null)));
-- payments by mode == GL
select tt.eq('P1 sale_payments cash (sale kind) = 300+80+100', 480, (select sum(amount) from sale_payments where mode='cash' and kind='sale' and not voided));
select tt.eq('P1 sale_payments card', 200, (select sum(amount) from sale_payments where mode='card' and not voided));
select tt.eq('P1 sale_payments mobile', 100, (select sum(amount) from sale_payments where mode='mobile' and not voided));
select tt.eq('P2 sum(sales.total) = sum(payments sale kind) + due', (select sum(total) from sales where status='done'), (select sum(amount) from sale_payments where kind='sale' and not voided) + (select sum(due_amount) from sales where status='done'));
select tt.eq('P2 sales.total sum = 1280 (1300 - 20 disc)', 1280, (select sum(total) from sales where status='done'));
select tt.eq('P3 GL (sales - discount) = sales.total sum', (select sum(total) from sales where status='done'), -tt.bal('4100') - tt.bal('4120'));
-- dates / time zone
select tt.eq('T1 midnight sale (00:30 Dhaka D) has sale_date = D', 1, (select count(*) from sales where id=:'s6id'::uuid and sale_date=:'dd'::date));
select tt.eq('T1 its journal entry_date = D', 1, (select count(*) from journal_entries where source_type='sale' and source_id=:'s6id' and entry_date=:'dd'::date));
select tt.eq('T1 its UTC date would be D-1 (cut-off hazard if reports used UTC)', 1, (select count(*) from sale_payments where sale_id=:'s6id'::uuid and (paid_at at time zone 'UTC')::date = :'dd'::date - 1));
-- day book vs journal
select daybook_vs_journal(:'dd'::date - 1, tt.today(), null) as dj \gset
\echo DAYBOOK_VS_JOURNAL: :dj
select tt.eq('D1 daybook_vs_journal kinds differing (expected 0 if both views agree)', 0, (:'dj'::jsonb->'total'->>'kinds_differing')::numeric);
select set_daybook_start(tt.today()-5) is not null as dbs \gset
select set_daybook_opening(20000, 50000, 0) is not null as dbo \gset
select day_book(null, :'dd'::date, tt.today()) as db \gset
\echo DAY_BOOK_TOTALS: :db
select tt.eq('D2 day_book CLOSE cash+bank+mobile (opening 20000/50000/0) vs GL cash+bank+mobile+card', tt.bal('1110')+tt.bal('1120')+tt.bal('1130')+tt.bal('1140'), ((:'db'::jsonb)->'totals'->'close'->>'total')::numeric);
select tt.eq('D2 day_book bank closing net (D..today) vs GL bank movement excl opening', 146, ((:'db'::jsonb)->'totals'->'net_close'->>'bank')::numeric, 0.005, 'GL bank movement = 400-150-300+196 = 146');
select tt.eq('D2 day_book cash net_close vs GL cash movement', 360, ((:'db'::jsonb)->'totals'->'net_close'->>'cash')::numeric, 0.005, 'GL cash movement = 20360-20000');
select tt.eq('D2 day_book mobile net_close', 100, ((:'db'::jsonb)->'totals'->'net_close'->>'mobile')::numeric);
-- drawer
select tt.eq('W1 drawer counted 1770, expected 1780, diff -10 recorded in entry_counts', -10, (select diff from entry_counts where section='drawer' limit 1));
select tt.eq('W1 expected drawer cash (typed form figures) vs GL cash movement on D for the till (300+100+80+500-100-400 deposit = 480; + float 1000)', 1780, (select expected from entry_counts where section='drawer' limit 1));
-- card
select card_settlement_list(1) as csl \gset
\echo CARD_SETTLEMENT_LIST: :csl
-- reports
select acct_overview(null) as ov \gset
\echo ACCT_OVERVIEW: :ov
select acct_trial_balance(tt.today()-5, tt.today(), null) as tb \gset
\echo TRIAL_BALANCE_KEYS: :tb
select acct_balance_sheet(tt.today(), null) as bs \gset
\echo BALANCE_SHEET: :bs
select inventory_vs_gl(tt.today(), 1) as ivg \gset
\echo INVENTORY_VS_GL: :ivg
select profit_source_check(tt.today()-5, tt.today(), 1) as psc \gset
\echo PROFIT_SOURCE_CHECK: :psc
select acct_cash_flow(tt.today()-5, tt.today(), null) as cf \gset
\echo ACCT_CASH_FLOW: :cf
select biz_daily(:'dd'::date, :'dd'::date, 1) as bd \gset
