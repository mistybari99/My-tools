-- A4 FIX probes (gap closure by phase113: G01 drawer shortage to the books, G03 dues net of advances, G04 period lock, G05 day book = journal,
-- G08 bank fee/interest from a statement line).  Scenario = a4_01_day.sql (the A4 audit day, hand-computed numbers in the HAND comments of that file
-- and here), own session on a clone of the template DB.  The batch switches are NOT set here: defaults = OFF -> FAIL = gap open by default;
-- switches_on.txt = ON -> PASS = closed.  Derived from supabase/phase113_test.sql T2..T7.  Labels FX4-G01 ... FX4-G08.
\set mode def
\i tests/sql/e2e/00_common.sql
\set ON_ERROR_STOP off
\set QUIET on
\i tests/sql/audit2/a4/a4_01_day.sql
select tt.as(:'o');
\echo == T2 audit A4 G01: the drawer shortage (counted 1770, expected 1780) - switch off = today
select tt.eq('FX4-G01 T2 drawer difference recorded -10', -10, (select diff from entry_counts where section='drawer' limit 1));
select submit_entry(:'dr'::uuid) is not null as sub \gset
select tt.t('FX4-G01 T2 form 14-1 submitted', (select status from entries where id=:'dr'::uuid)='submitted');
select acct_post_pending(false) is not null as pp \gset
select daybook_vs_journal(:'dd'::date, tt.today(), null) as dj0 \gset

\echo == T3 drawer_short_post = on
select acct_post_pending(false) as pp1 \gset
select tt.eq('FX4-G01 T3 one cash_variance entry posted', 1, (select count(*) from journal_entries where source_type='cash_variance'));
select tt.eq('FX4-G01 T3 account 5800 carries the shortage 10 (debit)', 10, tt.bal('5800'));
select tt.eq('FX4-G01 T3 cash in the books = physical 20350', 20350, tt.bal('1110'));
select tt.eq('FX4-G01 T3 entry is dated on the day of the count', 1, (select count(*) from journal_entries where source_type='cash_variance' and entry_date=:'dd'::date));
select tt.eq('FX4-G01 T3 second run posts nothing', 0, (acct_post_pending(false)->>'posted')::numeric);
select tt.eq('FX4-G01 T3 profit of the audit 186 is now 176 (shortage is an expense)', 176, (acct_income_statement(:'dd'::date, tt.today(), null)->>'net_profit')::numeric);
select tt.eq('FX4-G01 T3 books balanced', 0, tt.unbalanced());
select daybook_vs_journal(:'dd'::date, tt.today(), null) as dj1 \gset
select tt.eq('FX4-G01 T3 day book shows the cash_variance row too: no difference for this kind', 0, (select coalesce(sum((r->>'diff')::numeric),0) from jsonb_array_elements(:'dj1'::jsonb->'rows') r where r->>'kind'='cash_variance'));
-- a form that stops being final is reversed
select decide_entry(:'dr'::uuid, false, 'recount', null, '[]') is not null as rej \gset
select tt.t('FX4-G01 T3 form rejected', (select status from entries where id=:'dr'::uuid)='rejected');
select acct_post_pending(false) as pp2 \gset
select tt.eq('FX4-G01 T3 rejected count: the entry is reversed, 5800 back to 0', 0, tt.bal('5800'));
select tt.eq('FX4-G01 T3 cash back to 20360', 20360, tt.bal('1110'));

\echo == T4 audit A4 G03: advance already used (Cust Two: advance 500, due sale 200, advance used 200)
select tt.eq('FX4-G03 T4 customer_dues_net113 already nets the advance: Cust Two not on the list', 0, (select count(*) from customer_dues_net113() where id=:'c2'::uuid));
select tt.eq('FX4-G03 T4 Cust One (380 - 80 cash) still owes 300 on the net list', 300, (select balance from customer_dues_net113() where id=:'c1'::uuid));
select tt.eq('FX4-G03 T4 customer_dues_net113 and customer_dues agree for a customer without advance', (select balance from customer_dues() where id=:'c1'::uuid), (select balance from customer_dues_net113() where id=:'c1'::uuid));
select tt.t('FX4-G03 T4 oldest open sale date of Cust One is the day of the due sale', (select oldest from customer_dues_net113() where id=:'c1'::uuid) = :'dd'::date);
select tt.err('FX4-G03 T4 collecting the 200 again is refused (overpaid)', format($$select collect_payment(gen_random_uuid(),1,'%s'::uuid,'[{"mode":"cash","amount":200}]'::jsonb,'again')$$, :'c2'), 'overpaid');
select collect_payment(gen_random_uuid(),1,:'c1'::uuid,'[{"mode":"cash","amount":100}]'::jsonb,'part') ->> 'balance' as cb \gset
select tt.eq('FX4-G03 T4 a normal collection from Cust One still works: 300 - 100 = 200 left', 200, :'cb'::numeric);

\echo == T5 audit A4 G05: day book vs journal
select acct_post_pending(false) is not null as ppx \gset
select daybook_vs_journal(:'dd'::date, tt.today(), null) as dj2 \gset
select tt.eq('FX4-G05 T5 10-2 voucher 150 paid by bank is a BANK line and the card fee 4 leaves the bank side: no differing kind', 0, (:'dj2'::jsonb->'total'->>'kinds_differing')::numeric);
select set_daybook_start(tt.today()-5) is not null as dbs \gset
select set_daybook_opening(20000, 50000, 0) is not null as dbo \gset
select day_book(null, :'dd'::date, tt.today()) as db \gset
select tt.eq('FX4-G05 T5 day book bank net = GL bank movement 400 - 150 - 300 + 196 = 146', 146, ((:'db'::jsonb)->'totals'->'net_close'->>'bank')::numeric);
select tt.eq('FX4-G05 T5 day book cash net = GL cash movement (360 of the audit + 100 collected from Cust One)', tt.bal('1110') - 20000, ((:'db'::jsonb)->'totals'->'net_close'->>'cash')::numeric);
select daybook_vs_journal(:'dd'::date, tt.today(), null) as dj3 \gset

\echo == T6 audit A4 G04: closed period
select set_rule('period_closed_until', to_jsonb(:'dds'::text)) is null as pcl \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,:'t12'::timestamptz)->>'id' as sl1 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,:'t12'::timestamptz)->>'id' as sl2 \gset
select tt.t('FX4-G04 T6 the owner can still sell (nothing blocked)', coalesce(:'sl2','')<>'');
select tt.eq('FX4-G04 T6 exactly one yellow exception for that date', 1, (select count(*) from exceptions where flag_code='closed_period_owner' and entry_date=:'dd'::date and level='yellow'));
select tt.as(:'sp');
select tt.err('FX4-G04 T6 the seller is still refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":100}]'::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,'%s'::timestamptz)$$, tt.iid('FG-X'), :'t12'), 'period_closed');
select tt.as(:'o');
-- scheduler (no signed-in user) with the lock: the late sale stays unbooked
select acct_post_pending(false) is not null as ownerpost \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,:'t12'::timestamptz)->>'id' as sl3 \gset
select set_config('request.jwt.claim.sub','',false) is not null as nouser \gset
select set_config('bos.autopost85','on',false) is not null as ap_on \gset
select acct_post_pending(false) as pl0 \gset
select tt.as(:'o'); select set_rule('period_lock_late_warn','"on"'::jsonb) is null as r5 \gset
select set_config('request.jwt.claim.sub','',false) is not null as nouser2 \gset
select acct_post_pending(false) as pl1 \gset
select set_config('bos.autopost85','',false) is not null as ap_off \gset
select tt.as(:'o');
select tt.eq('FX4-G04 T6 locked 1 and listed', 1, jsonb_array_length(:'pl1'::jsonb->'locked_docs'));
select tt.eq('FX4-G04 T6 one yellow exception late_docs_locked with the count', 1, (select amount from exceptions where flag_code='late_docs_locked' and status='open'));
select tt.eq('FX4-G04 T6 the late sale is still not in the books (no silent posting)', 0, (select count(*) from journal_entries where source_type='sale' and source_id=:'sl3'));
select set_rule('period_closed_until', null) is null as pcl0 \gset
select acct_post_pending(false) is not null as pl3 \gset
select tt.eq('FX4-G04 T6 after reopening the period the sale posts', 1, (select count(*) from journal_entries where source_type='sale' and source_id=:'sl3'));

\echo == T7 audit A4 G08: bank fee 12.5 on the statement
select set_rule('bank_recon_on','true') is null as bro \gset
select id as bank_id from coa_accounts where code='1120' \gset
select bank_stmt_import(:bank_id, format('[{"date":"%s","amount":400,"reference":"DEP","description":"cash deposit"},{"date":"%s","amount":-12.5,"description":"monthly bank fee"},{"date":"%s","amount":3,"description":"interest"}]', :'dd', tt.today(), tt.today())::jsonb, gen_random_uuid(), false) is not null as bsi \gset
select id as fee_line from bank_statement_lines where amount=-12.5 \gset
select id as int_line from bank_statement_lines where amount=3 \gset
select id as dep_line from bank_statement_lines where amount=400 \gset
select tt.err('FX4-G08 T7 wrong sign: interest on a negative line', format($$select bank_stmt_post113(%s,'interest')$$, :fee_line), 'wrong_sign');
select tt.err('FX4-G08 T7 wrong sign: fee on a positive line', format($$select bank_stmt_post113(%s,'fee')$$, :int_line), 'wrong_sign');
select tt.err('FX4-G08 T7 bad kind', format($$select bank_stmt_post113(%s,'other')$$, :fee_line), 'bad_kind');
select bank_stmt_post113(:fee_line, 'fee', 1, null, null, true) as dry \gset
select tt.t('FX4-G08 T7 dry run writes nothing', (:'dry'::jsonb->>'dry')::boolean and (select count(*) from journal_entries where source_type='bank_stmt_line')=0);
select tt.eq('FX4-G08 T7 bank charges before = the card fee 4', 4, tt.bal('5810'));
select bank_stmt_post113(:fee_line, 'fee', 1, 'monthly fee', gen_random_uuid()) as pf \gset
select tt.eq('FX4-G08 T7 fee posted: 5810 = 4 + 12.5', 16.5, tt.bal('5810'));
select tt.eq('FX4-G08 T7 the bank account carries -12.5 for that entry', -12.5, (select sum(l.debit-l.credit) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='bank_stmt_line' and e.source_id=:'fee_line' and l.account_id=:'bank_id'));
select tt.t('FX4-G08 T7 the line is matched in the same step', exists (select 1 from bank_recon_matches where line_id=:fee_line and active));
select tt.err('FX4-G08 T7 posting the same line again is refused', format($$select bank_stmt_post113(%s,'fee')$$, :fee_line), 'line_already_matched');
select bank_stmt_post113(:int_line, 'interest', 1) as pi \gset
select tt.eq('FX4-G08 T7 interest 3 posted to other income 4900', -3, tt.bal('4900'));
select bank_recon_suggest(:bank_id, null, null, 3) as bsg \gset
select bank_recon_match_many((select coalesce(jsonb_agg(jsonb_build_object('line_id',(x->>'line_id')::bigint,'entry_id',(x->>'entry_id')::bigint,'line_no',(x->>'line_no')::int)),'[]'::jsonb) from jsonb_array_elements(:'bsg'::jsonb->'suggestions') x where (x->>'confident')::boolean and (x->>'line_id')::bigint = :dep_line), false) is not null as bmm \gset
select tt.t('FX4-G08 T7 the deposit line is now matched to its ledger entry', exists (select 1 from bank_recon_matches where line_id=:dep_line and active));
select tt.err('FX4-G08 T7 an already matched statement line cannot be posted again', format($$select bank_stmt_post113(%s,'interest')$$, :dep_line), 'line_already_matched');
select tt.eq('FX4-G08 T7 books balanced', 0, tt.unbalanced());
select tt.as(:'sp');
select tt.err('FX4-G08 T7 a seller (no accounts right) is refused', format($$select bank_stmt_post113(%s,'fee')$$, :fee_line), 'not allowed');
select tt.as(:'o');

