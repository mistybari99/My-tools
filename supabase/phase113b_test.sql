-- COPY of phase113_test.sql for the full chain 112..118 (integration): pasting phase113 again re-creates _acct_docs without the b2s115 patch, so T9 pastes 114 and 115 after it (re-paste rule, docs/PASTE_ORDER.md Invariant). Assertions otherwise as phase113_test.sql.
-- FRESH DB ONLY, built through the canonical order incl. phase113 (tests/sql/final_build.sh). Phase 113 tests (books truth), scenario = audit A4 (tests/sql/audit2/a4/a4_01_day.sql) with its hand-computed numbers.
-- Run from the repo root:  psql -qAt -f supabase/phase113_test.sql
\set mode def
\i tests/sql/e2e/00_common.sql
\set ON_ERROR_STOP off
\set QUIET on
\i tests/sql/audit2/a4/a4_01_day.sql
select tt.as(:'o');

\echo == T1 rules exist, default off; advisor rows
select tt.t('T1 six rules, default off', (select count(*) from rules where key in ('drawer_short_post','dues_net_advance','period_lock_owner_mode','period_lock_late_warn','daybook_align_mode','bank_stmt_post_on') and default_value='"off"'::jsonb)=6);
select tt.t('T1 six advisor rows (phase 113)', (select count(*) from setup_rec_defs81 where phase='113')=6);
select tt.t('T1 mapping cash_short -> 5800', (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='cash_short')='5800');

\echo == T2 audit A4 G01: the drawer shortage (counted 1770, expected 1780) - switch off = today
select tt.eq('T2 drawer difference recorded -10', -10, (select diff from entry_counts where section='drawer' limit 1));
select submit_entry(:'dr'::uuid) is not null as sub \gset
select tt.t('T2 form 14-1 submitted', (select status from entries where id=:'dr'::uuid)='submitted');
select acct_post_pending(false) is not null as pp \gset
select tt.eq('T2 off: cash in the books 20360 (physical 20350), 5800 empty', 20360, tt.bal('1110'));
select tt.eq('T2 off: nothing on 5800', 0, tt.bal('5800'));
select daybook_vs_journal(:'dd'::date, tt.today(), null) as dj0 \gset
select tt.t('T2 off: day book vs journal differ (voucher mode, card fee) - audit D1', (:'dj0'::jsonb->'total'->>'kinds_differing')::int >= 2);

\echo == T3 drawer_short_post = on
select set_rule('drawer_short_post','"on"'::jsonb) is null as r1 \gset
select acct_post_pending(true)->'by_type' as dry \gset
select tt.t('T3 dry run shows the variance and writes nothing', (:'dry'::jsonb->>'cash_variance')::int=1 and (select count(*) from journal_entries where source_type='cash_variance')=0);
select acct_post_pending(false) as pp1 \gset
select tt.eq('T3 one cash_variance entry posted', 1, (select count(*) from journal_entries where source_type='cash_variance'));
select tt.eq('T3 account 5800 carries the shortage 10 (debit)', 10, tt.bal('5800'));
select tt.eq('T3 cash in the books = physical 20350', 20350, tt.bal('1110'));
select tt.eq('T3 entry is dated on the day of the count', 1, (select count(*) from journal_entries where source_type='cash_variance' and entry_date=:'dd'::date));
select tt.eq('T3 second run posts nothing', 0, (acct_post_pending(false)->>'posted')::numeric);
select tt.eq('T3 profit of the audit 186 is now 176 (shortage is an expense)', 176, (acct_income_statement(:'dd'::date, tt.today(), null)->>'net_profit')::numeric);
select tt.eq('T3 books balanced', 0, tt.unbalanced());
select daybook_vs_journal(:'dd'::date, tt.today(), null) as dj1 \gset
select tt.eq('T3 day book shows the cash_variance row too: no difference for this kind', 0, (select coalesce(sum((r->>'diff')::numeric),0) from jsonb_array_elements(:'dj1'::jsonb->'rows') r where r->>'kind'='cash_variance'));
-- a form that stops being final is reversed
select decide_entry(:'dr'::uuid, false, 'recount', null, '[]') is not null as rej \gset
select tt.t('T3 form rejected', (select status from entries where id=:'dr'::uuid)='rejected');
select acct_post_pending(false) as pp2 \gset
select tt.eq('T3 rejected count: the entry is reversed, 5800 back to 0', 0, tt.bal('5800'));
select tt.eq('T3 cash back to 20360', 20360, tt.bal('1110'));
select set_rule('drawer_short_post','"off"'::jsonb) is null as r1off \gset

\echo == T4 audit A4 G03: advance already used (Cust Two: advance 500, due sale 200, advance used 200)
select tt.eq('T4 customer_dues (unchanged) shows Cust Two owing 200 (the audit FAIL)', 200, (select balance from customer_dues() where id=:'c2'::uuid));
select tt.eq('T4 customer_dues_net113 already nets the advance: Cust Two not on the list', 0, (select count(*) from customer_dues_net113() where id=:'c2'::uuid));
select tt.eq('T4 collect_payment with the rule off still allows the double collection (today)', 200, (select (collect_payment(gen_random_uuid(),1,:'c2'::uuid,'[{"mode":"cash","amount":200}]'::jsonb,'today') ->> 'collected')::numeric));
select (select id from sale_payments where kind='collection' and customer_id=:'c2'::uuid order by id desc limit 1) as dblcol \gset
select void_collection(:dblcol, 'test undo') is null as vcx \gset
select set_rule('dues_net_advance','"on"'::jsonb) is null as r2 \gset
select tt.eq('T4 on: Cust One (380 - 80 cash) still owes 300 on the net list', 300, (select balance from customer_dues_net113() where id=:'c1'::uuid));
select tt.eq('T4 customer_dues_net113 and customer_dues agree for a customer without advance', (select balance from customer_dues() where id=:'c1'::uuid), (select balance from customer_dues_net113() where id=:'c1'::uuid));
select tt.t('T4 oldest open sale date of Cust One is the day of the due sale', (select oldest from customer_dues_net113() where id=:'c1'::uuid) = :'dd'::date);
select tt.err('T4 on: collecting the 200 again is refused (overpaid)', format($$select collect_payment(gen_random_uuid(),1,'%s'::uuid,'[{"mode":"cash","amount":200}]'::jsonb,'again')$$, :'c2'), 'overpaid');
select collect_payment(gen_random_uuid(),1,:'c1'::uuid,'[{"mode":"cash","amount":100}]'::jsonb,'part') ->> 'balance' as cb \gset
select tt.eq('T4 on: a normal collection from Cust One still works: 300 - 100 = 200 left', 200, :'cb'::numeric);
select set_rule('dues_net_advance','"off"'::jsonb) is null as r2off \gset

\echo == T5 audit A4 G05: day book vs journal
select acct_post_pending(false) is not null as ppx \gset
select set_rule('daybook_align_mode','"on"'::jsonb) is null as r3 \gset
select daybook_vs_journal(:'dd'::date, tt.today(), null) as dj2 \gset
select tt.eq('T5 on: 10-2 voucher 150 paid by bank is a BANK line and the card fee 4 leaves the bank side: no differing kind', 0, (:'dj2'::jsonb->'total'->>'kinds_differing')::numeric);
select set_daybook_start(tt.today()-5) is not null as dbs \gset
select set_daybook_opening(20000, 50000, 0) is not null as dbo \gset
select day_book(null, :'dd'::date, tt.today()) as db \gset
select tt.eq('T5 on: day book bank net = GL bank movement 400 - 150 - 300 + 196 = 146', 146, ((:'db'::jsonb)->'totals'->'net_close'->>'bank')::numeric);
select tt.eq('T5 on: day book cash net = GL cash movement (360 of the audit + 100 collected from Cust One)', tt.bal('1110') - 20000, ((:'db'::jsonb)->'totals'->'net_close'->>'cash')::numeric);
select set_rule('daybook_align_mode','"off"'::jsonb) is null as r3off \gset
select daybook_vs_journal(:'dd'::date, tt.today(), null) as dj3 \gset
select tt.t('T5 off again: the old differences are back (nothing was stored)', (:'dj3'::jsonb->'total'->>'kinds_differing')::int >= 2);

\echo == T6 audit A4 G04: closed period
select set_rule('period_closed_until', to_jsonb(:'dds'::text)) is null as pcl \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,:'t12'::timestamptz)->>'id' as sl1 \gset
select tt.eq('T6 off: the owner sells into the closed period and nothing is written down', 0, (select count(*) from exceptions where flag_code='closed_period_owner'));
select set_rule('period_lock_owner_mode','"warn"'::jsonb) is null as r4 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,:'t12'::timestamptz)->>'id' as sl2 \gset
select tt.t('T6 warn: the owner can still sell (nothing blocked)', coalesce(:'sl2','')<>'');
select tt.eq('T6 warn: exactly one yellow exception for that date', 1, (select count(*) from exceptions where flag_code='closed_period_owner' and entry_date=:'dd'::date and level='yellow'));
select tt.as(:'sp');
select tt.err('T6 the seller is still refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":100}]'::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,'%s'::timestamptz)$$, tt.iid('FG-X'), :'t12'), 'period_closed');
select tt.as(:'o');
-- scheduler (no signed-in user) with the lock: the late sale stays unbooked
select acct_post_pending(false) is not null as ownerpost \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,:'t12'::timestamptz)->>'id' as sl3 \gset
select set_config('request.jwt.claim.sub','',false) is not null as nouser \gset
select set_config('bos.autopost85','on',false) is not null as ap_on \gset
select acct_post_pending(false) as pl0 \gset
select tt.eq('T6 off: the scheduler skips it (locked 1) and nothing says so', 0, (select count(*) from exceptions where flag_code='late_docs_locked'));
select tt.t('T6 off: result has no locked_docs', not (:'pl0'::jsonb ? 'locked_docs'));
select tt.as(:'o'); select set_rule('period_lock_late_warn','"on"'::jsonb) is null as r5 \gset
select set_config('request.jwt.claim.sub','',false) is not null as nouser2 \gset
select acct_post_pending(false) as pl1 \gset
select set_config('bos.autopost85','',false) is not null as ap_off \gset
select tt.as(:'o');
select tt.eq('T6 on: locked 1 and listed', 1, jsonb_array_length(:'pl1'::jsonb->'locked_docs'));
select tt.eq('T6 on: one yellow exception late_docs_locked with the count', 1, (select amount from exceptions where flag_code='late_docs_locked' and status='open'));
select tt.eq('T6 the late sale is still not in the books (no silent posting)', 0, (select count(*) from journal_entries where source_type='sale' and source_id=:'sl3'));
select set_rule('period_closed_until', null) is null as pcl0 \gset
select set_rule('period_lock_owner_mode','"off"'::jsonb) is null as r4off \gset
select set_rule('period_lock_late_warn','"off"'::jsonb) is null as r5off \gset
select acct_post_pending(false) is not null as pl3 \gset
select tt.eq('T6 after reopening the period the sale posts', 1, (select count(*) from journal_entries where source_type='sale' and source_id=:'sl3'));

\echo == T7 audit A4 G08: bank fee 12.5 on the statement
select set_rule('bank_recon_on','true') is null as bro \gset
select id as bank_id from coa_accounts where code='1120' \gset
select bank_stmt_import(:bank_id, format('[{"date":"%s","amount":400,"reference":"DEP","description":"cash deposit"},{"date":"%s","amount":-12.5,"description":"monthly bank fee"},{"date":"%s","amount":3,"description":"interest"}]', :'dd', tt.today(), tt.today())::jsonb, gen_random_uuid(), false) is not null as bsi \gset
select id as fee_line from bank_statement_lines where amount=-12.5 \gset
select id as int_line from bank_statement_lines where amount=3 \gset
select id as dep_line from bank_statement_lines where amount=400 \gset
select tt.err('T7 off: refused (switch)', format($$select bank_stmt_post113(%s,'fee')$$, :fee_line), 'switch_off');
select set_rule('bank_stmt_post_on','"on"'::jsonb) is null as r6 \gset
select tt.err('T7 wrong sign: interest on a negative line', format($$select bank_stmt_post113(%s,'interest')$$, :fee_line), 'wrong_sign');
select tt.err('T7 wrong sign: fee on a positive line', format($$select bank_stmt_post113(%s,'fee')$$, :int_line), 'wrong_sign');
select tt.err('T7 bad kind', format($$select bank_stmt_post113(%s,'other')$$, :fee_line), 'bad_kind');
select bank_stmt_post113(:fee_line, 'fee', 1, null, null, true) as dry \gset
select tt.t('T7 dry run writes nothing', (:'dry'::jsonb->>'dry')::boolean and (select count(*) from journal_entries where source_type='bank_stmt_line')=0);
select tt.eq('T7 bank charges before = the card fee 4', 4, tt.bal('5810'));
select bank_stmt_post113(:fee_line, 'fee', 1, 'monthly fee', gen_random_uuid()) as pf \gset
select tt.eq('T7 fee posted: 5810 = 4 + 12.5', 16.5, tt.bal('5810'));
select tt.eq('T7 the bank account carries -12.5 for that entry', -12.5, (select sum(l.debit-l.credit) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='bank_stmt_line' and e.source_id=:'fee_line' and l.account_id=:'bank_id'));
select tt.t('T7 the line is matched in the same step', exists (select 1 from bank_recon_matches where line_id=:fee_line and active));
select tt.err('T7 posting the same line again is refused', format($$select bank_stmt_post113(%s,'fee')$$, :fee_line), 'line_already_matched');
select bank_stmt_post113(:int_line, 'interest', 1) as pi \gset
select tt.eq('T7 interest 3 posted to other income 4900', -3, tt.bal('4900'));
select bank_recon_suggest(:bank_id, null, null, 3) as bsg \gset
select bank_recon_match_many((select coalesce(jsonb_agg(jsonb_build_object('line_id',(x->>'line_id')::bigint,'entry_id',(x->>'entry_id')::bigint,'line_no',(x->>'line_no')::int)),'[]'::jsonb) from jsonb_array_elements(:'bsg'::jsonb->'suggestions') x where (x->>'confident')::boolean and (x->>'line_id')::bigint = :dep_line), false) is not null as bmm \gset
select tt.t('T7 the deposit line is now matched to its ledger entry', exists (select 1 from bank_recon_matches where line_id=:dep_line and active));
select tt.err('T7 an already matched statement line cannot be posted again', format($$select bank_stmt_post113(%s,'interest')$$, :dep_line), 'line_already_matched');
select tt.eq('T7 books balanced', 0, tt.unbalanced());
select tt.as(:'sp');
select tt.err('T7 a seller (no accounts right) is refused', format($$select bank_stmt_post113(%s,'fee')$$, :fee_line), 'not allowed');
select tt.as(:'o');

\echo == T8 audit A4 G06: the card over-settlement guard is the rule card_settle_over_mode (phase109)
select tt.t('T8 advisor recommends warn', (select rec_value from setup_rec_defs81 where code='card_settle_over_mode')='"warn"'::jsonb);
select set_rule('card_settle_over_mode','"refuse"'::jsonb) is null as r7 \gset
select tt.err('T8 refuse: 5000 settlement with nothing unsettled', $$select card_settle(1, (now() at time zone 'Asia/Dhaka')::date, 5000, 0, 'over', gen_random_uuid())$$, 'over_settlement');
select set_rule('card_settle_over_mode','"off"'::jsonb) is null as r7off \gset

\echo == T9 tags, privileges, paste twice
select tt.t('T9 bos113 in the re-created functions, older tags kept',
  (select bool_and(d ~ 'bos113') from (select pg_get_functiondef(p.oid) d from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('_acct_docs','acct_post_pending','_daybook_lines','customer_dues_net113','collect_payment','lock_check','bank_stmt_post113')) x)
  and pg_get_functiondef('public._acct_docs(date)'::regprocedure) ~ 'bos98' and pg_get_functiondef('public._acct_docs(date)'::regprocedure) ~ 'bos103'
  and pg_get_functiondef('public.acct_post_pending(boolean,integer)'::regprocedure) ~ 'bos85' and pg_get_functiondef('public.customer_dues()'::regprocedure) !~ 'bos113'
  and pg_get_functiondef('public._daybook_lines(integer[],integer[],date,date)'::regprocedure) ~ 'bos50');
select tt.t('T9 bank_stmt_post113 only for signed-in users', not has_function_privilege('anon','public.bank_stmt_post113(bigint,text,integer,text,uuid,boolean)','execute') and has_function_privilege('authenticated','public.bank_stmt_post113(bigint,text,integer,text,uuid,boolean)','execute'));
create temp table f0 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace = 'public'::regnamespace;
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.t('T9 no function changed by pasting phase113 again (followed by 114, 115: they patch _acct_docs / stock functions 113 re-creates)', (select count(*) from pg_proc p join f0 on f0.fn = p.oid::regprocedure::text where p.pronamespace = 'public'::regnamespace and md5(pg_get_functiondef(p.oid)) <> f0.h) = 0);
select tt.t('T9 no rule / mapping row duplicated', (select count(*) from rules where key in ('drawer_short_post','dues_net_advance','period_lock_owner_mode','period_lock_late_warn','daybook_align_mode','bank_stmt_post_on'))=6 and (select count(*) from acct_mappings where key='cash_short')=1);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
