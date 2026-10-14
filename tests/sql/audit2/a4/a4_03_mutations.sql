\echo == A4-03 bank statement, over-settlement, voids, collections, locks, rounding, manual journal
select tt.as(:'o');
select set_rule('bank_recon_on','true') is null as bro \gset
select id as bank_id from coa_accounts where code='1120' \gset
-- bank statement as the bank would show it (assumption: card payout lands the day after settlement entry = same day here)
select bank_stmt_import(:bank_id, format('[{"date":"%s","amount":400,"reference":"DEP","description":"cash deposit"},{"date":"%s","amount":-150,"reference":"V1","description":"courier"},{"date":"%s","amount":-300,"description":"supplier"},{"date":"%s","amount":196,"reference":"CARD","description":"card payout"},{"date":"%s","amount":-12.5,"description":"monthly bank fee"}]', :'dd', :'dd', tt.today(), tt.today(), tt.today())::jsonb, gen_random_uuid(), false) as bsi \gset
\echo BANK_IMPORT: :bsi
select bank_recon_suggest(:bank_id, null, null, 3) as bsg \gset
\echo BANK_SUGGEST_COUNT: :bsg
select bank_recon_report(:bank_id) as brr \gset
select tt.eq('B1 bank statement total (400-150-300+196-12.5 = 133.5) is shown', 133.5, (:'brr'::jsonb->>'statement_total')::numeric);
select tt.eq('B1 book movement on 1120 excluding opening journal = 146', 146, (:'brr'::jsonb->>'book_total')::numeric - 50000, 0.005, 'book_total includes the 50000 opening entry');
select tt.eq('B1 unmatched statement lines BEFORE matching = 5', 5, (:'brr'::jsonb->>'statement_unmatched_count')::numeric);
-- auto-match confident suggestions then report again
select bank_recon_match_many((select coalesce(jsonb_agg(jsonb_build_object('line_id',(x->>'line_id')::bigint,'entry_id',(x->>'entry_id')::bigint,'line_no',(x->>'line_no')::int)),'[]'::jsonb) from jsonb_array_elements(:'bsg'::jsonb->'suggestions') x where (x->>'confident')::boolean), false) as bmm \gset
\echo BANK_MATCH_MANY: :bmm
select bank_recon_report(:bank_id) as brr2 \gset
select tt.eq('B2 after matching: unmatched statement lines = 1 (the 12.5 fee not in books)', 1, (:'brr2'::jsonb->>'statement_unmatched_count')::numeric);
select tt.eq('B2 unmatched book lines (opening 50000 is not on the statement)', 1, (:'brr2'::jsonb->>'book_unmatched_count')::numeric);
-- fee 12.5 on statement has no ledger entry: no screen posts it (no bank_charge-from-statement action)
select tt.t('B3 a statement line without ledger entry can be turned into a journal entry from the reconciliation screen', false, 'supported', 'NOT SUPPORTED', 'bank_recon_* has match/unmatch only; posting is a manual journal');
select tt.eq('B3 multi bank accounts: pay_bank maps ONE account', 1, (select count(distinct account_id) from acct_mappings where key='pay_bank'));

-- ---- card settlement control
select card_settle(1, tt.today(), 5000, 0, 'over', gen_random_uuid()) as ov1 \gset
\echo OVER_SETTLE_DEFAULT: :ov1
select tt.t('C1 over-settlement 5000 with nothing unsettled accepted by default (card_settle_over_mode off)', (:'ov1'::jsonb->>'id') is not null);
select acct_post_pending(false) is not null as pp1 \gset
select tt.eq('C1 card receivable 1140 is now negative', -5000, tt.bal('1140'));
select card_settle_void((:'ov1'::jsonb->>'id')::uuid, 'undo') is not null as v1 \gset
select acct_post_pending(false) is not null as pp1b \gset
select tt.eq('C1 void settlement reverses it', 0, tt.bal('1140'));
select set_rule('card_settle_over_mode','"refuse"') is null as rr \gset
select tt.err('C2 over_settlement refused when rule = refuse', $$select card_settle(1, (now() at time zone 'Asia/Dhaka')::date, 5000, 0, 'over', gen_random_uuid())$$, 'over_settlement');
select tt.err('C2 second settlement of the same 200 refused (nothing unsettled)', $$select card_settle(1, (now() at time zone 'Asia/Dhaka')::date, 200, 4, 'twice', gen_random_uuid())$$, 'over_settlement');
select set_rule('card_settle_over_mode',null) is null as rr0 \gset
select tt.t('C3 card settlement is typed by a person: no link to the card sales it settles (no per-sale / per-batch matching, no terminal statement import)', false, 'supported', 'NOT SUPPORTED');

-- ---- customer wrongly collected after advance used
select tt.eq('V0 customer_dues shows Cust Two owing 200 although advance 500-200 applied', 200, (select balance from customer_dues() where id=:'c2'::uuid));
select collect_payment(gen_random_uuid(),1,:'c2'::uuid,'[{"mode":"cash","amount":200}]'::jsonb,'a4 collect') as col \gset
select acct_post_pending(false) is not null as ppc \gset
select tt.eq('V1 GL receivable of Cust Two after collection = -200 (debt cleared twice: advance_used + cash)', -200, (select coalesce(sum(l.debit-l.credit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='1210' and l.party_type='customer' and l.party_id=:'c2'));
select tt.eq('V1 advance liability of Cust Two still 300 (customer holds credit AND was charged)', -300, (select coalesce(sum(debit-credit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='2300' and party_id=:'c2'));
select (select id from sale_payments where kind='collection' order by id desc limit 1) as colid \gset
select void_collection(:colid, 'undo') is null as vc \gset
select acct_post_pending(false) is not null as ppc2 \gset

-- ---- void sale 1 which already has a return (refund 100) must be refused
select tt.err('V2 void_sale of a sale that has a return is refused (sale_has_returns)', format($$select void_sale('%s'::uuid,'a4 void after return')$$, :'s1id'), 'sale_has_returns');
-- ---- void the part-paid due sale 4 (cash 80 + due 300 Cust One)
select tt.bal('1110') as cash0 \gset
select tt.qty('FG-X') as q0 \gset
select void_sale(:'s4id'::uuid, 'a4 void due sale') is null as vs4 \gset
select acct_post_pending(false) as ppv \gset
select tt.eq('V2b void due sale: cash -80', -80, tt.bal('1110') - :cash0::numeric);
select tt.eq('V2b void due sale: Cust One receivable back to 0', 0, (select coalesce(sum(l.debit-l.credit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='1210' and l.party_id=:'c1'));
select tt.eq('V2b void due sale: stock +4', 4, tt.qty('FG-X') - :q0::numeric);
select tt.eq('V2b void due sale: customer_dues list no longer has Cust One', 0, (select count(*) from customer_dues() where id=:'c1'::uuid));
-- ---- void settled card sale (sale 2)
select void_sale(:'s2id'::uuid, 'a4 void settled card sale') is null as vs2 \gset
select acct_post_pending(false) is not null as ppv2 \gset
select tt.eq('V3 void of an already settled card sale: card receivable goes negative (-200); bank keeps the payout', -200, tt.bal('1140'));
-- ---- void supplier payment (paid today) and journal reversal date
select (select id from supplier_payments order by id desc limit 1) as spid \gset
select void_supplier_payment(:spid, 'a4') is null as vsp \gset
select acct_post_pending(false) is not null as ppsp \gset
select tt.eq('V4 payable back to 600 after void of the 300 payment', -600, tt.bal('2100'));
select tt.eq('V4 trial balance still balanced', 0, (select sum(debit-credit) from journal_lines));

-- ---- reversal dating: voided sale 1 (day D) - P&L of D by report vs by GL
select tt.eq('V5 GL sales credit dated D still 1300 after voids of sale 2 and 4 (reversals are dated today, not D)', 1300, (select -sum(l.debit-l.credit) from journal_lines l join coa_accounts a on a.id=l.account_id join journal_entries e on e.id=l.entry_id where a.code='4100' and e.entry_date=:'dd'::date));
select biz_daily(:'dd'::date, :'dd'::date, 1) as bd2 \gset
\echo BIZ_DAILY_AFTER_VOID: :bd2

-- ---- double posting protection
select tt.err('J1 duplicate journal entry for the same source (je_source_uq)', $$insert into journal_entries (entry_date, source_type, source_id, memo) select entry_date, source_type, source_id, 'dup' from journal_entries where source_type='sale' and reverses_id is null limit 1$$, 'duplicate key');
select tt.err('J2 journal line cannot be edited', $$update journal_lines set debit = debit + 1 where entry_id = (select min(entry_id) from journal_lines)$$, '');
select tt.err('J2 journal line cannot be deleted', $$delete from journal_lines where entry_id = (select min(entry_id) from journal_lines)$$, '');

-- ---- manual journal on a cash account (guard default)
select rule_txt('manual_journal_guard') as mjg \gset
\echo MANUAL_JOURNAL_GUARD_DEFAULT: :mjg
select acct_journal_post(tt.today(), 1, 'a4 manual cash fix', '[{"code":"1110","debit":5},{"code":"3100","credit":5}]'::jsonb, gen_random_uuid()) as mj \gset
\echo MANUAL_JOURNAL: :mj
select daybook_vs_journal(tt.today(), tt.today(), null) as dj2 \gset
\echo DAYBOOK_VS_JOURNAL_AFTER_MANUAL: :dj2
select tt.t('M1 manual journal touching cash is visible to daybook_vs_journal as a difference', (:'dj2'::jsonb->'total'->>'kinds_differing')::int >= 1);

-- ---- period lock
select set_rule('period_closed_until', to_jsonb(:'dds'::text)) is null as pcl \gset
select tt.as(:'sp');
select tt.err('L1 seller: new sale dated inside the closed period refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":100}]'::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,'%s'::timestamptz)$$, tt.iid('FG-X'), :'t12'), 'period_closed');
select tt.t('L1 void of a sale of a closed period is refused for non-owners (trigger sales_lock: lock_check(old.sale_date) on UPDATE; not executed here, seller lacks sale_void in this fixture)', true, 'by code', 'sales_lock()');
select tt.err('L1 seller: cash_move dated in closed period refused', format($$select cash_move_add(1,'owner_topup',10,'%s'::date,'cash')$$, :'dds'), 'period_closed');
select tt.as(:'o');
-- owner bypass: sale into a closed period, then post it
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,:'t12'::timestamptz)->>'id' as sl1 \gset
select tt.t('L2 owner can sell INTO a closed period (is_owner bypass in lock_check)', coalesce(:'sl1','') <> '');
select acct_post_pending(false) as pl1 \gset
select tt.eq('L2 owner-run autopost posts that late sale into the closed period (entry_date = D)', 1, (select count(*) from journal_entries where source_type='sale' and source_id=:'sl1' and entry_date=:'dd'::date));
-- the scheduler (no signed-in user) respects the lock: a second late sale stays unposted
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,:'t12'::timestamptz)->>'id' as sl2 \gset
select set_config('request.jwt.claim.sub','',false) is not null as nouser \gset
select set_config('bos.autopost85','on',false) is not null as ap_on \gset
select acct_post_pending(false) as pl2 \gset
select set_config('bos.autopost85','',false) is not null as ap_off \gset
select tt.as(:'o');
\echo SCHEDULER_RUN_IN_CLOSED_PERIOD: :pl2
select tt.eq('L3 scheduler run: late sale of closed period NOT posted, counted as locked', 1, (:'pl2'::jsonb->>'locked')::numeric);
select tt.eq('L3 the sale exists in sales/payments but has no journal entry (cash in drawer, not in GL)', 0, (select count(*) from journal_entries where source_type='sale' and source_id=:'sl2'));
select tt.t('L4 sale_return in a closed period is checked against TODAY, not the sale date', true, 'by design', 'lock_check(today) in sale_return', 'return of a sale of a closed period books on today');
select set_rule('period_closed_until', null) is null as pcl0 \gset
select acct_post_pending(false) as pl3 \gset
select tt.eq('L5 after reopening the period the pending sale posts', 1, (select count(*) from journal_entries where source_type='sale' and source_id=:'sl2'));

-- ---- rounding
select tt.as(:'o');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":3,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"cash","amount":289.99}]',null,null,'retail',null,false,null,'percent',3.337) as r1 \gset
\echo ROUNDING_SALE: :r1
select (:'r1'::jsonb->>'id')::uuid as r1id \gset
select tt.eq('Q1 percent discount 3.337% of 300 = 10.01, total 289.99', 289.99, (:'r1'::jsonb->>'total')::numeric);
select sale_return(gen_random_uuid(), :'r1id'::uuid, format('[{"item_id":"%s","qty":1}]',tt.iid('FG-X'))::jsonb, 'damaged','a4 r1','cash') as rr1 \gset
select sale_return(gen_random_uuid(), :'r1id'::uuid, format('[{"item_id":"%s","qty":2}]',tt.iid('FG-X'))::jsonb, 'damaged','a4 r2','cash') as rr2 \gset
select tt.eq('Q2 partial returns add up to the sale total 289.99 (96.66 + 193.33)', 289.99, (:'rr1'::jsonb->>'amount')::numeric + (:'rr2'::jsonb->>'amount')::numeric);
select acct_post_pending(false) is not null as ppq \gset
select tt.eq('Q3 net revenue of the rounding sale in GL is 0 after full return', 0, (select coalesce(sum(-(l.debit-l.credit)),0) from journal_lines l join coa_accounts a on a.id=l.account_id join journal_entries e on e.id=l.entry_id where a.code in ('4100','4110','4120') and ((e.source_type='sale' and e.source_id=:'r1id') or (e.source_type='sale_return' and e.source_id in (select id::text from sale_returns where sale_id=:'r1id'::uuid)))), 0.005);
select tt.eq('Q3 trial balance balanced after all mutations', 0, (select sum(debit-credit) from journal_lines));
-- ---- final health reads
select acct_overview(null)->'status' as st2 \gset
\echo FINAL_STATUS: :st2
select acct_reconcile('all') as rc2 \gset
\echo FINAL_RECONCILE: :rc2
select inventory_vs_gl(tt.today(), 1) as ivg2 \gset
\echo FINAL_INV_VS_GL_AGREE: :ivg2
