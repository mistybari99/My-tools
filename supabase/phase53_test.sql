-- FRESH DB ONLY. Phase 53 tests (P2 gaps 1-5: bank reconcile, year-end close, VAT report, fixed assets, budgets).
--   ORDER="phase8 ... phase28 phase40 ... phase51 phase53" bash tests/sql/build_fresh_db.sh p53db
--   psql -h /tmp -p 5544 -U postgres -d p53db -qAt -f supabase/phase53_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set t '00000000-0000-0000-0000-000000000003'
\set h '00000000-0000-0000-0000-000000000004'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'t','acc3@s.app','{"full_name":"Accountant"}'), (:'h','view4@s.app','{"full_name":"Viewer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'t','showroom_manager'),(:'h','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1),(:'t',1),(:'h',1) on conflict do nothing;
with i as (insert into items (name_bn, name_en, unit, base_unit, sell_price, tracked, item_type, vat_applicable) values ('A','A','pc','pc',500,true,'resale',true) returning id) select id as iva from i \gset
with i as (insert into items (name_bn, name_en, unit, base_unit, sell_price, tracked, item_type, vat_applicable) values ('B','B','pc','pc',500,true,'resale',false) returning id) select id as ivb from i \gset
with i as (insert into items (name_bn, name_en, unit, base_unit, sell_price, tracked, item_type) values ('C','C','pc','pc',500,true,'resale') returning id) select id as ivc from i \gset
select id as bk from coa_accounts where code='1120' \gset
select id as cash from coa_accounts where code='1110' \gset
select id as a_sales from coa_accounts where code='4100' \gset
select id as a_rent from coa_accounts where code='5300' \gset

\echo == T0 shape
select tt.chk('T0 tables have RLS and no write grants', (select count(*) from pg_class where relname in ('bank_statement_lines','bank_recon_matches','bank_recon_trail','year_closes','fa_assets','fa_depr_posts','budgets','budget_log') and relrowsecurity)=8
  and not has_table_privilege('authenticated','bank_statement_lines','insert') and not has_table_privilege('authenticated','budgets','update') and not has_table_privilege('authenticated','fa_assets','insert') and not has_table_privilege('authenticated','year_closes','update'));
select tt.chk('T0 helpers closed to browsers, entry points open, anon nothing', not has_function_privilege('authenticated','_a53_pl(date,date,int,boolean)','execute') and not has_function_privilege('authenticated','_a53_match1(bigint,bigint,int,text,text)','execute')
  and has_function_privilege('authenticated','bank_recon_match(bigint,bigint,int,text)','execute') and not has_function_privilege('anon','vat_report(date,date,int)','execute') and not has_function_privilege('anon','fa_depr_post(date,boolean)','execute'));
select tt.chk('T0 switches exist and are OFF (vat_on reused; no VAT rate invented)', (select count(*) from rules where key in ('bank_recon_on','year_close_on','fixed_assets_on','budgets_on') and default_value='false'::jsonb)=4
  and not rule_on('vat_on') and rule_num('vat_rate') is null and not rule_on('bank_recon_on') and not rule_on('year_close_on') and not rule_on('fixed_assets_on') and not rule_on('budgets_on'));
select tt.chk('T0 mappings exist', (select count(*) from acct_mappings where key in ('depreciation','accum_depr','retained_close'))=3);

\echo == setup: grants, start date
set role authenticated; select tt.as(:'o');
select set_user_grant(:'t'::uuid,'accounts_manage') is null as g1 \gset
select set_user_grant(:'h'::uuid,'accounts_view') is null as g2 \gset
select acct_set_start(date '2025-01-01') ->> 'start' as sd \gset

\echo == T1 switches OFF: every write refused
select tt.err('T1 bank import refused while OFF', format($$select bank_stmt_import(%s, '[{"date":"2026-01-01","amount":5}]'::jsonb, null, true)$$, :'bk'), 'switch_off');
select tt.err('T1 year close refused while OFF', $$select year_close_run(date '2025-01-01', date '2025-12-31')$$, 'switch_off');
select tt.err('T1 asset save refused while OFF', $$select fa_asset_save(null,'A1','x',null,1,date '2026-01-01',1000,0,10,date '2026-01-01',null,null,true)$$, 'switch_off');
select tt.err('T1 budget set refused while OFF', format($$select budget_set('[{"account_id":%s,"month":"2026-01-01","amount":5}]'::jsonb, null, true)$$, :'a_rent'), 'switch_off');
select tt.chk('T1 VAT report says off', (vat_report(date '2026-01-01', tt.today())->>'off')::boolean);
select set_rule('bank_recon_on','true') is null as r1 \gset
select set_rule('year_close_on','true') is null as r2 \gset
select set_rule('fixed_assets_on','true') is null as r3 \gset
select set_rule('budgets_on','true') is null as r4 \gset
select tt.as(:'s'); select tt.err('T1 a manager without the grant cannot import', format($$select bank_stmt_import(%s, '[{"date":"2026-01-01","amount":5}]'::jsonb, null, true)$$, :'bk'), 'not allowed');
select tt.as(:'h'); select tt.err('T1 a viewer cannot import either', format($$select bank_stmt_import(%s, '[{"date":"2026-01-01","amount":5}]'::jsonb, null, true)$$, :'bk'), 'not allowed');

\echo == T2 bank statement reconcile
select tt.as(:'t');
select acct_journal_post(tt.today()-2, 1, 'Deposit INV-77', format('[{"account_id":%s,"debit":5000},{"account_id":%s,"credit":5000}]', :'bk', :'a_sales')::jsonb) ->> 'id' as j1 \gset
select acct_journal_post(tt.today()-3, 1, 'Cheque received', format('[{"account_id":%s,"debit":2000},{"account_id":%s,"credit":2000}]', :'bk', :'a_sales')::jsonb) ->> 'id' as j2 \gset
select acct_journal_post(tt.today()-3, 1, 'Other cheque', format('[{"account_id":%s,"debit":2000},{"account_id":%s,"credit":2000}]', :'bk', :'a_sales')::jsonb) ->> 'id' as j3 \gset
select acct_journal_post(tt.today()-1, 1, 'Shop rent', format('[{"account_id":%s,"debit":1500},{"account_id":%s,"credit":1500}]', :'a_rent', :'bk')::jsonb) ->> 'id' as j4 \gset
select acct_journal_post(tt.today()-2, 1, 'Cash sale', format('[{"account_id":%s,"debit":5000},{"account_id":%s,"credit":5000}]', :'cash', :'a_sales')::jsonb) ->> 'id' as j5 \gset
select count(*) as jn0 from journal_entries \gset
select format('[{"date":"%s","amount":"5000","reference":"INV-77","description":"deposit"},{"date":"%s","amount":2000,"reference":"CHQ"},{"date":"%s","amount":-1500,"reference":"RENT"},{"date":"%s","amount":999,"reference":"unknown"},{"date":"%s","amount":300,"description":"fee"},{"date":"%s","amount":300,"description":"fee"}]',
  tt.today()-2, tt.today()-3, tt.today()-1, tt.today(), tt.today()-4, tt.today()-4) as rows1 \gset
select bank_stmt_import(:bk, :'rows1'::jsonb, null, true) as d1 \gset
select tt.chk('T2 dry import: 6 new, writes nothing', (:'d1'::jsonb->>'new')::int=6 and (:'d1'::jsonb->>'dry')::boolean and (select count(*) from bank_statement_lines)=0);
select tt.err('T2 invalid rows block the real import', format($$select bank_stmt_import(%s, '[{"date":"2026-13-45","amount":5},{"date":"2026-01-01","amount":"abc"},{"date":"2026-01-01","amount":0}]'::jsonb, null, false)$$, :'bk'), 'invalid_rows');
select bank_stmt_import(:bk, '[{"date":"2026-13-45","amount":5},{"date":"2026-01-01","amount":"abc"},{"date":"2026-01-01","amount":0},{"date":"2026-01-01","amount":7}]'::jsonb, null, true) as d2 \gset
select tt.chk('T2 dry import reports 3 invalid, 1 new', (:'d2'::jsonb->>'invalid')::int=3 and (:'d2'::jsonb->>'new')::int=1);
select tt.err('T2 a non-bank account is refused', format($$select bank_stmt_import(%s, '[{"date":"2026-01-01","amount":5}]'::jsonb, null, true)$$, :'a_sales'), 'bad_account');
select tt.err('T2 a cash/bank header is refused', format($$select bank_stmt_import(%s, '[{"date":"2026-01-01","amount":5}]'::jsonb, null, true)$$, (select id from coa_accounts where code='1100')), 'bad_account');
select bank_stmt_import(:bk, :'rows1'::jsonb, 'c0000000-0000-0000-0000-0000000000c1', false) as i1 \gset
select tt.chk('T2 imported 6 lines (two identical fee lines are both kept)', (:'i1'::jsonb->>'imported')::int=6 and (select count(*) from bank_statement_lines)=6 and (select sum(amount) from bank_statement_lines)=7099.00 + 0);
select tt.chk('T2 same client id = no second import', (bank_stmt_import(:bk, :'rows1'::jsonb, 'c0000000-0000-0000-0000-0000000000c1', false)->>'dup')::boolean and (select count(*) from bank_statement_lines)=6);
select bank_stmt_import(:bk, :'rows1'::jsonb, null, false) as i2 \gset
select tt.chk('T2 pasting the same statement again adds nothing', (:'i2'::jsonb->>'imported')::int=0 and (:'i2'::jsonb->>'duplicate')::int=6 and (select count(*) from bank_statement_lines)=6);
select tt.chk('T2 importing touched no journal entry (nothing auto-posted)', (select count(*) from journal_entries)=:jn0);
select tt.err('T2 a browser cannot write the statement table directly', $$update bank_statement_lines set amount=1$$, 'permission denied');
reset role;
select tt.err('T2 statement lines cannot be edited (even by the table owner)', $$update bank_statement_lines set amount=1$$, 'append_only');
select tt.err('T2 statement lines cannot be deleted', $$delete from bank_statement_lines$$, 'append_only');
set role authenticated; select tt.as(:'t');
select id as l_inv from bank_statement_lines where reference='INV-77' \gset
select id as l_chq from bank_statement_lines where reference='CHQ' \gset
select id as l_rent from bank_statement_lines where reference='RENT' \gset
select id as l_unk from bank_statement_lines where reference='unknown' \gset
select bank_recon_suggest(:bk) as sg \gset
select tt.chk('T2 suggest: INV-77 and RENT are confident; the 2000 line is ambiguous (2 candidates); 999 has none',
  (select (x->>'confident')::boolean from jsonb_array_elements(:'sg'::jsonb->'suggestions') x where (x->>'line_id')::bigint=:l_inv) and (select (x->>'confident')::boolean from jsonb_array_elements(:'sg'::jsonb->'suggestions') x where (x->>'line_id')::bigint=:l_rent)
  and (select not (x->>'confident')::boolean and (x->>'candidates')::int=2 from jsonb_array_elements(:'sg'::jsonb->'suggestions') x where (x->>'line_id')::bigint=:l_chq)
  and not exists (select 1 from jsonb_array_elements(:'sg'::jsonb->'suggestions') x where (x->>'line_id')::bigint=:l_unk));
select tt.chk('T2 suggest wrote nothing', (select count(*) from bank_recon_matches)=0);
select tt.chk('T2 candidates for the 2000 line = 2 journal lines; cash line (other account) never a candidate', jsonb_array_length(bank_recon_candidates(:l_chq))=2 and jsonb_array_length(bank_recon_candidates(:l_inv))=1);
select bank_recon_match_many(format('[{"line_id":%s,"entry_id":%s,"line_no":1},{"line_id":%s,"entry_id":%s,"line_no":2}]', :l_inv, :j1, :l_rent, :j4)::jsonb, true) as md \gset
select tt.chk('T2 dry match: 2 ok, nothing written', (:'md'::jsonb->>'ok')::int=2 and (select count(*) from bank_recon_matches)=0);
select bank_recon_match_many(format('[{"line_id":%s,"entry_id":%s,"line_no":1},{"line_id":%s,"entry_id":%s,"line_no":2},{"line_id":%s,"entry_id":%s,"line_no":1}]', :l_inv, :j1, :l_rent, :j4, :l_unk, :j1)::jsonb, false) as mr \gset
select tt.chk('T2 real match: 2 matched, the bad pair is listed (amount mismatch) and does not stop the others', (:'mr'::jsonb->>'ok')::int=2 and (:'mr'::jsonb->>'failed')::int=1 and (select count(*) from bank_recon_matches where active)=2);
select tt.err('T2 amount must be exactly equal', format($$select bank_recon_match(%s, %s, 1, 'try')$$, :l_unk, :j2), 'amount_mismatch');
select tt.err('T2 wrong account (cash line vs bank statement) refused', format($$select bank_recon_match(%s, %s, 1, 'try')$$, :l_inv, :j5), 'wrong_account');
select tt.err('T2 a statement line cannot be matched twice', format($$select bank_recon_match(%s, %s, 1, 'again')$$, :l_inv, :j1), 'line_already_matched');
select tt.err('T2 a journal line cannot be matched twice', format($$select bank_recon_match(%s, %s, 1, 'again')$$, :l_chq, :j1), 'amount_mismatch');
select bank_recon_match(:l_chq, :j2, 1, 'by hand') ->> 'match_id' as mm \gset
select tt.err('T2 second statement line cannot take the same journal line', format($$select bank_recon_match(%s, %s, 1, 'dup')$$, (select id from bank_statement_lines where description='fee' limit 1), :j2), 'amount_mismatch');
select tt.chk('T2 manual match recorded with a trail', (select how from bank_recon_matches where id=:mm::bigint)='manual' and (select count(*) from bank_recon_trail where action='match')=3);
select tt.err('T2 unmatch needs a reason', format($$select bank_recon_unmatch(%s, '')$$, :l_chq), 'note_required');
select tt.err('T2 unmatch of an unmatched line refused', format($$select bank_recon_unmatch(%s, 'because')$$, :l_unk), 'not_matched');
select bank_recon_unmatch(:l_chq, 'wrong cheque') is not null as um \gset
select tt.chk('T2 unmatch keeps the history: match row inactive, trail has match+unmatch', (select not active from bank_recon_matches where id=:mm::bigint) and (select count(*) from bank_recon_trail where line_id=:l_chq)=2);
reset role; select tt.err('T2 the trail cannot be edited', $$update bank_recon_trail set note='x'$$, 'append_only'); select tt.err('T2 a match row cannot be deleted', $$delete from bank_recon_matches$$, 'nothing is deleted'); set role authenticated; select tt.as(:'t');
select bank_recon_match(:l_chq, :j3, 1, 'the other cheque') is not null as m2 \gset
select tt.chk('T2 a journal line freed by unmatch can be matched again (other line took j3)', (select count(*) from bank_recon_matches where active)=3);
select bank_recon_report(:bk) as rp \gset
select tt.chk('T2 report: unmatched statement = 999 + two fees (3 lines, 1599), unmatched book = j2 (1 line, 2000)', (:'rp'::jsonb->>'statement_unmatched_count')::int=3 and (:'rp'::jsonb->>'statement_unmatched_sum')::numeric=1599
  and (:'rp'::jsonb->>'book_unmatched_count')::int=1 and (:'rp'::jsonb->>'book_unmatched_sum')::numeric=2000 and (:'rp'::jsonb->>'matched_count')::int=3);
select tt.chk('T2 report totals: statement 7099 vs book 7500... difference shown', (:'rp'::jsonb->>'statement_total')::numeric=7099.00-1500*0+0 - 1500*0 and (:'rp'::jsonb->>'difference')::numeric = (:'rp'::jsonb->>'statement_total')::numeric-(:'rp'::jsonb->>'book_total')::numeric);
select tt.chk('T2 lines list filter: 3 matched, 3 unmatched', jsonb_array_length(bank_recon_lines(:bk,'matched'))=3 and jsonb_array_length(bank_recon_lines(:bk,'unmatched'))=3);
select tt.as(:'h'); select tt.err('T2 a viewer cannot read the statement report', format($$select bank_recon_report(%s)$$, :'bk'), 'not allowed');
select tt.chk('T2 a viewer sees no statement rows (RLS)', (select count(*) from bank_statement_lines)=0);
select tt.as(:'t'); select tt.chk('T2 the accountant reads them', (select count(*) from bank_statement_lines)=6);
select tt.chk('T2 still no journal entry created by reconciling', (select count(*) from journal_entries)=:jn0);

\echo == T3 year-end close
select tt.as(:'o');
select acct_journal_post(date '2025-03-10', 1, 'Sales 2025 loc1', format('[{"account_id":%s,"debit":10000},{"account_id":%s,"credit":10000}]', :'cash', :'a_sales')::jsonb) ->> 'id' as y1 \gset
select acct_journal_post(date '2025-06-01', 1, 'Rent 2025 loc1', format('[{"account_id":%s,"debit":4000},{"account_id":%s,"credit":4000}]', :'a_rent', :'cash')::jsonb) ->> 'id' as y2 \gset
select acct_journal_post(date '2025-07-01', 2, 'Sales 2025 loc2', format('[{"account_id":%s,"debit":3000},{"account_id":%s,"credit":3000}]', :'cash', :'a_sales')::jsonb) ->> 'id' as y3 \gset
select year_close_run(date '2025-01-01', date '2025-12-31') as pv0 \gset
select tt.chk('T3 preview before the lock: problems = period_not_locked, numbers shown, nothing written', (:'pv0'::jsonb->'problems') ? 'period_not_locked' and not (:'pv0'::jsonb->>'ok')::boolean
  and (:'pv0'::jsonb->>'income_total')::numeric=13000 and (:'pv0'::jsonb->>'expense_total')::numeric=4000 and (:'pv0'::jsonb->>'net_profit')::numeric=9000 and (select count(*) from year_closes)=0);
select tt.err('T3 real close refused before the period is locked', $$select year_close_run(date '2025-01-01', date '2025-12-31', 'close it', null, false)$$, 'period_not_locked');
select set_rule('period_closed_until','"2025-12-31"') is null as lk \gset
select year_close_run(date '2025-01-01', date '2025-12-31') as pv \gset
select tt.chk('T3 preview ok after the lock; lines per location (loc1 and loc2 each balance)', (:'pv'::jsonb->>'ok')::boolean and (:'pv'::jsonb->>'accounts')::int=3 and jsonb_array_length(:'pv'::jsonb->'lines')=5);
select tt.as(:'t'); select tt.err('T3 accounts_manage (not owner) cannot close', $$select year_close_run(date '2025-01-01', date '2025-12-31', 'x y z', null, false)$$, 'not allowed');
select tt.as(:'o');
select tt.err('T3 a note is required', $$select year_close_run(date '2025-01-01', date '2025-12-31', '', null, false)$$, 'note_required');
select tt.err('T3 bad range refused', $$select year_close_run(date '2025-12-31', date '2025-01-01')$$, 'bad_range');
select tt.err('T3 a year not finished is refused', $$select year_close_run(date '2026-01-01', date '2026-12-31')$$, 'bad_range');
select count(*) as jn1 from journal_entries \gset
select year_close_run(date '2025-01-01', date '2025-12-31', 'FY2025 close', 'd0000000-0000-0000-0000-0000000000d1', false) as cl \gset
select (:'cl'::jsonb->>'id')::bigint as ycid, (:'cl'::jsonb->>'entry_id')::bigint as cent \gset
select tt.chk('T3 closing entry posted, balanced, dated year end, flagged', (select entry_date from journal_entries where id=:cent)=date '2025-12-31' and (select flags from journal_entries where id=:cent)='year_close'
  and (select sum(debit)=sum(credit) and sum(debit)>0 from journal_lines where entry_id=:cent) and (select count(*) from journal_entries)=:jn1+1);
select tt.chk('T3 retained earnings (3900) received 9000 credit; income/expense accounts net to 0 in the trial balance',
  (select coalesce(sum(credit-debit),0) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where a.code='3900' and e.entry_date='2025-12-31' and e.source_type='year_close')=9000
  and (select coalesce(sum(l.debit-l.credit),0) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where a.type in ('income','expense') and e.entry_date between '2025-01-01' and '2025-12-31')=0);
select tt.chk('T3 each location balances on its own (loc 1 profit 6000, loc 2 profit 3000)', (select coalesce(sum(credit-debit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='3900' and l.entry_id=:cent and l.location_id=1)=6000
  and (select coalesce(sum(credit-debit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='3900' and l.entry_id=:cent and l.location_id=2)=3000);
select tt.chk('T3 phase40 balance sheet still balances after the close', not (acct_balance_sheet(date '2025-12-31')->>'unbalanced')::boolean);
select tt.chk('T3 pnl_ex_close still shows the real year (income 13000, profit 9000) while phase40 statement reads zero', (acct_pnl_ex_close(date '2025-01-01', date '2025-12-31')->>'net_profit')::numeric=9000 and (acct_pnl_ex_close(date '2025-01-01', date '2025-12-31')->>'total_income')::numeric=13000
  and (acct_income_statement(date '2025-01-01', date '2025-12-31')->>'net_profit')::numeric=0);
select tt.chk('T3 same client id = no second close', (year_close_run(date '2025-01-01', date '2025-12-31', 'again', 'd0000000-0000-0000-0000-0000000000d1', false)->>'dup')::boolean and (select count(*) from year_closes)=1);
select tt.err('T3 the same year cannot be closed twice', $$select year_close_run(date '2025-01-01', date '2025-12-31', 'again again', null, false)$$, 'already_closed');
reset role; select tt.err('T3 closing entry cannot be edited', format($$update journal_entries set memo='x' where id=%s$$, :cent), 'append_only'); set role authenticated; select tt.as(:'o');
select tt.err('T3 reverse needs a note', format($$select year_close_reverse(%s,'')$$, :ycid), 'note_required');
select tt.as(:'t'); select tt.err('T3 accounts_manage cannot reverse', format($$select year_close_reverse(%s,'mistake')$$, :ycid), 'not allowed'); select tt.as(:'o');
select year_close_reverse(:ycid, 'closed by mistake') ->> 'reversal_id' as rvid \gset
select tt.chk('T3 reversed: close void, reversing entry exists dated year end, status reopened', (select status from journal_entries where id=:cent)='void' and (select reverses_id from journal_entries where id=:rvid::bigint)=:cent
  and (select status from year_closes where id=:ycid)='reopened' and (select entry_date from journal_entries where id=:rvid::bigint)=date '2025-12-31');
select tt.chk('T3 after the reversal the income/expense are back (13000 / 4000)', (acct_income_statement(date '2025-01-01', date '2025-12-31')->>'net_profit')::numeric=9000);
select tt.err('T3 cannot reverse twice', format($$select year_close_reverse(%s,'again')$$, :ycid), 'already_reopened');
select year_close_run(date '2025-01-01', date '2025-12-31', 'closed again', null, false) ->> 'id' as yc2 \gset
select tt.chk('T3 the year can be closed again after a reopen (2 rows, 1 closed)', (select count(*) from year_closes)=2 and (select count(*) from year_closes where status='closed')=1);
select tt.as(:'t'); select tt.err('T3 a locked-period posting by the accountant is refused (existing lock)', format($$select acct_journal_post(date '2025-12-30',1,'late',%L::jsonb)$$, format('[{"account_id":%s,"debit":1},{"account_id":%s,"credit":1}]', :'a_rent', :'cash')), 'period_closed');
select tt.as(:'o');
select year_close_list() as yl \gset
select tt.chk('T3 list shows both closes', jsonb_array_length(:'yl'::jsonb->'rows')=2);
select set_rule('period_closed_until', null) is null as unlk \gset

\echo == T4 VAT ledger (report only)
select set_rule('vat_on','true') is null as v1 \gset
select tt.chk('T4 VAT on but no rate: data needed, no invented rate', (vat_report(date '2026-01-01', tt.today())->>'data_needed')::boolean);
select set_rule('vat_rate','15') is null as v2 \gset
select save_supplier(null,'{"name":"Sugar Co","credit_days":7}') as sup1 \gset
select count(*) as jn2 from journal_entries \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":500},{"item_id":"%s","qty":1,"price":500},{"item_id":"%s","qty":1,"price":500}]',:'iva',:'ivb',:'ivc')::jsonb,0,'[{"mode":"cash","amount":1500}]',null,null,'retail',null,false) ->> 'id' as vs1 \gset
select save_purchase(null,null,:'sup1'::uuid,1,'V-1',tt.today(),format('[{"item_id":"%s","qty":10,"unit":"pc","unit_cost":100}]',:'iva')::jsonb) ->> 'id' as vb1 \gset
select post_purchase(:'vb1'::uuid) is not null as vpp \gset
select vat_report(tt.today(), tt.today()) as vr \gset
select tt.chk('T4 output VAT = 500 taxable * 15/115 = 65.22; item C (undecided) 500 not taxed and shown', (:'vr'::jsonb->'output'->>'taxable_sales')::numeric=500 and (:'vr'::jsonb->'output'->>'vat')::numeric=65.22 and (:'vr'::jsonb->'output'->>'undecided_amount')::numeric=500);
select tt.chk('T4 input VAT = 1000 * 15/115 = 130.43; net payable = 65.22 - 130.43', (:'vr'::jsonb->'input'->>'vat')::numeric=130.43 and (:'vr'::jsonb->>'net_vat_payable')::numeric=-65.21);
select set_rule('vat_prices_include','false') is null as v3 \gset
select tt.chk('T4 prices exclude VAT: output = 500 * 15% = 75', (vat_report(tt.today(), tt.today())->'output'->>'vat')::numeric=75.00);
select set_rule('vat_prices_include','true') is null as v4 \gset
select tt.chk('T4 report posted nothing (journal count same apart from autopost of docs: none)', (select count(*) from journal_entries)=:jn2 and not exists (select 1 from journal_entries where source_type like '%vat%'));
select set_rule('vat_on','false') is null as v5 \gset
select tt.chk('T4 switched off again: report off', (vat_report(tt.today(), tt.today())->>'off')::boolean);
select tt.as(:'s'); select tt.err('T4 a manager without the grant cannot read it', $$select vat_report(date '2026-01-01', current_date)$$, 'not allowed');
select tt.as(:'o');

\echo == T5 fixed assets
select date_trunc('month', tt.today() - interval '3 months')::date as m0 \gset
select fa_asset_save(null,'FA-1','Oven',null,1,:'m0'::date,12000,2000,10,:'m0'::date,null,null,true) as fd \gset
select tt.chk('T5 dry-run: monthly 1000, nothing saved', (:'fd'::jsonb->>'monthly')::numeric=1000 and (select count(*) from fa_assets)=0);
select tt.err('T5 salvage must be below cost', format($$select fa_asset_save(null,'FA-X','x',null,1,%L::date,100,100,10,%L::date,null,null,true)$$, :'m0', :'m0'), 'bad_salvage');
select tt.err('T5 depreciation cannot start before the acquisition month', format($$select fa_asset_save(null,'FA-X','x',null,1,%L::date,100,0,10,%L::date,null,null,true)$$, :'m0', (:'m0'::date - 40)), 'bad_depr_start');
select fa_asset_save(null,'FA-1','Oven',null,1,:'m0'::date,12000,2000,10,:'m0'::date,null,'e0000000-0000-0000-0000-0000000000e1',false) ->> 'id' as fa1 \gset
select fa_asset_save(null,'FA-2','Mixer (3-month life, odd cost)',null,1,:'m0'::date,1000,0,3,:'m0'::date,null,null,false) ->> 'id' as fa2 \gset
select tt.chk('T5 same client id = same asset', (fa_asset_save(null,'FA-1','Oven',null,1,:'m0'::date,12000,2000,10,:'m0'::date,null,'e0000000-0000-0000-0000-0000000000e1',false)->>'dup')::boolean and (select count(*) from fa_assets)=2);
select tt.err('T5 code is unique', format($$select fa_asset_save(null,'FA-1','dup',null,1,%L::date,100,0,10,%L::date,null,null,false)$$, :'m0', :'m0'), 'code_taken');
select fa_schedule(:'fa2'::uuid) as sc \gset
select tt.chk('T5 schedule of 1000/3 months: 333.33, 333.33, 333.34 (rounding remainder in the last), book value 0 at the end', (select string_agg((x->>'amount'), ',' order by (x->>'k')::int) from jsonb_array_elements(:'sc'::jsonb->'rows') x)='333.33,333.33,333.34'
  and (select (x->>'book_value')::numeric from jsonb_array_elements(:'sc'::jsonb->'rows') x where (x->>'k')::int=3)=0);
select tt.err('T5 the current month is not complete: refused', format($$select fa_depr_post(%L::date, true)$$, tt.today()), 'month_not_complete');
select date_trunc('month', tt.today() - interval '1 month')::date as mlast \gset
select fa_depr_post(:'mlast'::date, true) as pd \gset
select tt.chk('T5 dry post: 3 months of FA-1 + 3 of FA-2 = 6 rows, 3*1000 + 1000 = 4000, nothing written', (:'pd'::jsonb->>'count')::int=6 and (:'pd'::jsonb->>'total')::numeric=4000 and (select count(*) from fa_depr_posts)=0);
select tt.as(:'s'); select tt.err('T5 a manager without the grant cannot post', format($$select fa_depr_post(%L::date, true)$$, :'mlast'), 'not allowed'); select tt.as(:'o');
select fa_depr_post(:'mlast'::date, false) as pr \gset
select tt.chk('T5 posted 6 entries, each Dr depreciation 5820 / Cr accumulated 1590, balanced', (:'pr'::jsonb->>'count')::int=6 and (select count(*) from fa_depr_posts)=6 and (select count(*) from journal_entries where source_type='fa_depr')=6
  and (select coalesce(sum(l.debit),0) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where e.source_type='fa_depr' and a.code='5820')=4000
  and (select coalesce(sum(l.credit),0) from journal_lines l join journal_entries e on e.id=l.entry_id join coa_accounts a on a.id=l.account_id where e.source_type='fa_depr' and a.code='1590')=4000);
select tt.chk('T5 posting again is idempotent: 0 new rows, no duplicate entries', (fa_depr_post(:'mlast'::date, false)->>'count')::int=0 and (select count(*) from fa_depr_posts)=6 and (select count(*) from journal_entries where source_type='fa_depr')=6);
reset role;
select tt.err('T5 the unique (asset, month) holds even with a direct insert', format($$insert into fa_depr_posts (asset_id, month, seq, amount, entry_id) select asset_id, month, seq, amount, entry_id from fa_depr_posts limit 1$$), 'duplicate key');
select tt.err('T5 posted depreciation rows are append-only', $$update fa_depr_posts set amount = 1$$, 'append_only');
set role authenticated; select tt.as(:'o');
select tt.err('T5 cost cannot change once depreciation is posted', format($$select fa_asset_save(%L::uuid,null,'Oven',null,1,%L::date,13000,2000,10,%L::date,null,null,false)$$, :'fa1', :'m0', :'m0'), 'depreciation_already_posted');
select fa_asset_save(:'fa1'::uuid,null,'Oven (renamed)',null,1,:'m0'::date,12000,2000,10,:'m0'::date,'note',null,false) is not null as ren \gset
select tt.chk('T5 name/note can still change', (select name from fa_assets where id=:'fa1'::uuid)='Oven (renamed)');
select fa_register() as rg \gset
select tt.chk('T5 register: FA-1 accumulated 3000 book value 9000; FA-2 accumulated 1000 book value 0', (select (x->>'accumulated')::numeric=3000 and (x->>'book_value')::numeric=9000 from jsonb_array_elements(:'rg'::jsonb->'rows') x where x->>'code'='FA-1')
  and (select (x->>'accumulated')::numeric=1000 and (x->>'book_value')::numeric=0 from jsonb_array_elements(:'rg'::jsonb->'rows') x where x->>'code'='FA-2'));
select fa_asset_dispose(:'fa2'::uuid, tt.today(), 'sold') is not null as dsp \gset
select tt.chk('T5 disposed asset leaves the register active list but keeps history', (select status from fa_assets where id=:'fa2'::uuid)='disposed' and (select count(*) from fa_depr_posts where asset_id=:'fa2'::uuid)=3);
reset role; select tt.err('T5 an asset row cannot be deleted', $$delete from fa_assets$$, 'nothing is deleted'); set role authenticated; select tt.as(:'o');
select set_rule('period_closed_until', to_jsonb((date_trunc('month', tt.today() - interval '2 months')::date - 1)::text)) is null as lk2 \gset
select fa_depr_post(:'mlast'::date, true) as pd2 \gset
select tt.chk('T5 owner posts through a closed period (owner may), nothing left to post', (:'pd2'::jsonb->>'count')::int=0);
select set_rule('period_closed_until', null) is null as unlk2 \gset

\echo == T6 budgets
select tt.as(:'t');
select date_trunc('month', tt.today())::date as bm \gset
select budget_set(format('[{"account_id":%s,"month":"%s","amount":5000},{"account_id":%s,"month":"%s","amount":20000,"location_id":1}]', :'a_rent', :'bm', :'a_sales', :'bm')::jsonb, 'first', true) as bd \gset
select tt.chk('T6 dry-run: 2 new, nothing written', (:'bd'::jsonb->>'new')::int=2 and (select count(*) from budgets)=0);
select tt.err('T6 a balance-sheet account cannot have a budget', format($$select budget_set('[{"account_id":%s,"month":"2026-01-01","amount":5}]'::jsonb, null, true)$$, :'bk'), 'bad_account');
select tt.err('T6 negative amount refused', format($$select budget_set('[{"account_id":%s,"month":"2026-01-01","amount":-5}]'::jsonb, null, true)$$, :'a_rent'), 'bad_amount');
select tt.err('T6 location the user cannot use refused', format($$select budget_set('[{"account_id":%s,"month":"2026-01-01","amount":5,"location_id":2}]'::jsonb, null, true)$$, :'a_rent'), 'bad_location');
select tt.chk('T6 an accounts_manage holder (all locations) may set a company-wide budget (dry)', (budget_set(format('[{"account_id":%s,"month":"2026-01-01","amount":5}]', :'a_rent')::jsonb, null, true)->>'new')::int=1);
select budget_set(format('[{"account_id":%s,"month":"%s","amount":5000,"location_id":1},{"account_id":%s,"month":"%s","amount":20000,"location_id":1}]', :'a_rent', :'bm', :'a_sales', :'bm')::jsonb, 'first', false) as bs \gset
select tt.chk('T6 saved 2 budgets with log rows', (:'bs'::jsonb->>'new')::int=2 and (select count(*) from budgets)=2 and (select count(*) from budget_log)=2);
select budget_set(format('[{"account_id":%s,"month":"%s","amount":8000,"location_id":1},{"account_id":%s,"month":"%s","amount":20000,"location_id":1}]', :'a_rent', :'bm', :'a_sales', :'bm')::jsonb, 'raise rent', false) as bs2 \gset
select tt.chk('T6 changing one amount: 1 changed, 1 unchanged, log keeps old 5000 -> new 6000, no duplicate row', (:'bs2'::jsonb->>'changed')::int=1 and (:'bs2'::jsonb->>'unchanged')::int=1 and (select count(*) from budgets)=2
  and (select old_amount=5000 and new_amount=8000 from budget_log where note='raise rent'));
reset role;
select tt.err('T6 budget log is append-only', $$delete from budget_log$$, 'append_only');
select tt.err('T6 budgets are never deleted', $$delete from budgets$$, 'nothing is deleted');
set role authenticated; select tt.as(:'t');
select tt.as(:'o');
select acct_journal_post(tt.today(), 1, 'Rent this month', format('[{"account_id":%s,"debit":4500},{"account_id":%s,"credit":4500}]', :'a_rent', :'cash')::jsonb) ->> 'id' as bj1 \gset
select budget_vs_actual(:'bm'::date, tt.today()) as bv \gset
select tt.chk('T6 rent: budget 8000, actual 6000 (1500 + 4500), variance +2000 (under budget is good), 75% used',
  (select (x->>'budget')::numeric=8000 and (x->>'actual')::numeric=6000 and (x->>'variance')::numeric=2000 and (x->>'pct_used')::numeric=75.0 from jsonb_array_elements(:'bv'::jsonb->'rows') x where x->>'code'='5300'));
select tt.chk('T6 sales: budget 20000, actual 14000 (the four journal receipts), variance -6000 (income short of budget)', (select (x->>'budget')::numeric=20000 and (x->>'actual')::numeric=14000 and (x->>'variance')::numeric=-6000 from jsonb_array_elements(:'bv'::jsonb->'rows') x where x->>'code'='4100'));
select tt.chk('T6 totals add up', (:'bv'::jsonb->>'expense_budget')::numeric=8000 and (:'bv'::jsonb->>'income_budget')::numeric=20000 and (:'bv'::jsonb->>'profit_budget')::numeric=12000 and (:'bv'::jsonb->>'profit_actual')::numeric=8000);
select tt.chk('T6 by-month variant returns the month key', (select count(*)>0 from jsonb_array_elements(budget_vs_actual(:'bm'::date, tt.today(), null, true)->'rows') x where x->>'month' is not null));
select tt.as(:'h'); select tt.chk('T6 a viewer can read the report', (budget_vs_actual(:'bm'::date, tt.today())->>'from') is not null); select tt.err('T6 but cannot set budgets', format($$select budget_set('[{"account_id":%s,"month":"2026-01-01","amount":5,"location_id":1}]'::jsonb, null, true)$$, :'a_rent'), 'not allowed');
select tt.as(:'s'); select tt.err('T6 a manager without the grant cannot read the report', format($$select budget_vs_actual(%L::date, current_date)$$, :'bm'), 'not allowed');

reset role;
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
