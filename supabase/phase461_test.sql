-- FRESH DB ONLY. Phase 461 tests (RPT-C3 R7 part 4): the setting marketing_post_on, posting 18-1 spend to the journal, no double counting with 10-2 / quick expenses.
--   bash tests/sql/rptc3_run.sh 461
-- Test data only (test_* names). The accounting engine is on with a start date (the w1d fixture does that).
\ir ../tests/sql/rptc3_head.sql
select to_char(date_trunc('month', tt.today() - interval '1 month'), 'YYYY-MM-DD') as pm, to_char(tt.today(), 'YYYY-MM-DD') as td \gset
select tt.as(:'u_o');

-- T1 the setting is OFF by default and cannot be switched on without its date
select tt.chk('T1 default OFF and the date is blank', not rule_on('marketing_post_on') and rule_txt('marketing_post_from') is null);
select tt.err('T1 cannot switch on without the start date', $$select set_rule('marketing_post_on','true')$$, 'marketing_post_needs_setup');
select tt.err('T1 a bad date is refused', $$select set_rule('marketing_post_from','"2026-99-99"')$$, 'bad_date');
select tt.err('T1 nothing is posted while it is off', $$select mkt_post_run(true)$$, 'marketing_post_off');
-- before the date is set, every line says so
select mkt_post_preview(tt.today()-5, tt.today()+1) as pv0 \gset
select tt.chk('T1 before the date is set every approved line is "not_set_up"', (:'pv0'::jsonb)->'counts' ? 'not_set_up' and not ((:'pv0'::jsonb)->'counts' ? 'to_post'));

-- the look-alikes: an approved 10-2 voucher (marketing 300) and a quick expense (marketing 200)
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"marketing","amount":"300","receipt":"yes"}]}'::jsonb,'[]') ->> 'id' as v1 \gset
select submit_entry(:'v1'::uuid) is not null as v1s \gset
select decide_entry(:'v1'::uuid,true,null,'{}','[]') ->> 'status' as v1d \gset
select quick_expense_add(1, tt.today(), 'marketing', 'test_adshop', 200, 'mobile', false, 'test', gen_random_uuid()) is not null as qe \gset
-- a second approved 18-1 sheet: mobile 150 (alpha), card 60, owner money 75, no source 90
select save_entry(null,'18-1',1,tt.today(), jsonb_build_object('lines', jsonb_build_array(
  jsonb_build_object('date',tt.today()::text,'head','3','campaign_id',tt.k('ca'),'amt','150','source','mobile'),
  jsonb_build_object('date',tt.today()::text,'head','3','amt','60','source','card'),
  jsonb_build_object('date',tt.today()::text,'head','4','amt','75','source','owner'),
  jsonb_build_object('date',tt.today()::text,'head','4','amt','90'))), '[]') ->> 'id' as m2 \gset
select submit_entry(:'m2'::uuid) is not null as m2s \gset
select decide_entry(:'m2'::uuid, true, null, '{}', '[]') ->> 'status' as m2d \gset
select set_rule('marketing_post_from', to_jsonb(:'pm'::text)) is null as sf \gset

-- T2 the classification (nothing is written)
select mkt_post_preview(tt.today()-5, tt.today()+1) as pv \gset
select tt.chk('T2 the 300 bank line has a 10-2 look-alike (same head, amount, place, date): possible_duplicate', (select x->>'cls' = 'possible_duplicate' from jsonb_array_elements((:'pv'::jsonb)->'rows') x where tt.n(x,'amt') = 300));
select tt.chk('T2 the 200 mobile line has a quick-expense look-alike: possible_duplicate', (select x->>'cls' = 'possible_duplicate' from jsonb_array_elements((:'pv'::jsonb)->'rows') x where tt.n(x,'amt') = 200));
select tt.chk('T2 the imprest line (100) is never posted here', (select x->>'cls' = 'skip_imprest' from jsonb_array_elements((:'pv'::jsonb)->'rows') x where tt.n(x,'amt') = 100));
select tt.chk('T2 mobile 150 and card 60 are to_post; owner money 75 and no-source 90 are not postable', (select string_agg(x->>'cls', ',' order by tt.n(x,'amt')) from jsonb_array_elements((:'pv'::jsonb)->'rows') x where tt.n(x,'amt') in (60,75,90,150)) = 'to_post,owner_money,needs_source,to_post');
select tt.chk('T2 counts: 2 to post for 210', tt.n((:'pv'::jsonb)->'counts'->'to_post','lines') = 2 and tt.n((:'pv'::jsonb)->'counts'->'to_post','amount') = 210);
select tt.chk('T2 the preview wrote nothing', (select count(*) from journal_entries where source_type = 'mkt_spend') = 0);
select tt.chk('T2 the sample line without a paid amount is not a line to post', not exists (select 1 from jsonb_array_elements((:'pv'::jsonb)->'rows') x where tt.n(x,'amt') = 80));

-- T3 switch on, dry run, real run
select set_rule('marketing_post_on', 'true') is null as on1 \gset
select tt.chk('T3 now ON', rule_on('marketing_post_on'));
select tt.as(:'u_st');
select tt.err('T3 a salesperson cannot run the posting', $$select mkt_post_run(false)$$, 'not allowed');
select tt.as(:'u_o');
select mkt_post_run(true) as dry \gset
select tt.chk('T3 dry run: 2 would be posted, none written', tt.n(:'dry'::jsonb,'posted') = 2 and (:'dry'::jsonb->>'dry') = 'true' and (select count(*) from journal_entries where source_type = 'mkt_spend') = 0);
select mkt_post_run(false) as run1 \gset
select tt.chk('T3 real run posts 2 balanced entries', tt.n(:'run1'::jsonb,'posted') = 2 and (select count(*) from journal_entries where source_type = 'mkt_spend') = 2 and tt.unbalanced() = 0 and jsonb_array_length(:'run1'::jsonb->'errors') = 0);
select tt.chk('T3 the marketing expense account holds 210 from this file (Dr), credited to wallet and bank', (select sum(l.debit) from journal_lines l join journal_entries e on e.id = l.entry_id join coa_accounts a on a.id = l.account_id where e.source_type = 'mkt_spend' and a.code = '5500') = 210
  and (select sum(l.credit) from journal_lines l join journal_entries e on e.id = l.entry_id where e.source_type = 'mkt_spend') = 210);
select tt.chk('T3 the entry key is sheet : revision : line', exists (select 1 from journal_entries where source_type = 'mkt_spend' and source_id = :'m2' || ':1:1'));
select tt.chk('T3 run again: nothing more is posted (safe to repeat)', tt.n(mkt_post_run(false),'posted') = 0 and (select count(*) from journal_entries where source_type = 'mkt_spend') = 2);
select tt.chk('T3 the drill-down says the posted line is in the books', (select (x->>'in_books') = 'true' from jsonb_array_elements(mkt_spend_lines(tt.today()-5, tt.today()+1, null, tt.k('ca'))->'rows') x where tt.n(x,'amt') = 150));

-- T4 decisions on the look-alikes
select tt.as(:'u_acc');
select tt.err('T4 a reason is required', format($$select mkt_post_decide('%s', 1, 'skip', ' ')$$, tt.k('m1')), 'reason_required');
select tt.err('T4 only post or skip', format($$select mkt_post_decide('%s', 1, 'maybe', 'because')$$, tt.k('m1')), 'bad_decision');
select tt.err('T4 a line without a paid amount cannot be decided', format($$select mkt_post_decide('%s', 4, 'skip', 'because')$$, tt.k('m1')), 'bad_line');
select tt.err('T4 a line that does not exist', format($$select mkt_post_decide('%s', 9, 'skip', 'because')$$, tt.k('m1')), 'bad_line');
select mkt_post_decide(tt.k('m1')::uuid, 1, 'skip', 'same as the voucher') ->> 'ok' as d1 \gset
select mkt_post_decide(tt.k('m1')::uuid, 2, 'post', 'the quick expense was something else') ->> 'ok' as d2 \gset
select mkt_post_decide(tt.k('m1')::uuid, 3, 'post', 'try to force the imprest line') ->> 'ok' as d3 \gset
select tt.as(:'u_st');
select tt.err('T4 a salesperson cannot decide', format($$select mkt_post_decide('%s', 1, 'skip', 'because')$$, tt.k('m1')), 'not allowed');
select tt.as(:'u_o');
select mkt_post_preview(tt.today()-5, tt.today()+1) as pv2 \gset
select tt.chk('T4 the skipped line is decided_skip', (select x->>'cls' = 'decided_skip' from jsonb_array_elements((:'pv2'::jsonb)->'rows') x where tt.n(x,'amt') = 300));
select tt.chk('T4 the line that was decided "post" is now to_post', (select x->>'cls' = 'to_post' from jsonb_array_elements((:'pv2'::jsonb)->'rows') x where tt.n(x,'amt') = 200));
select tt.chk('T4 an imprest line stays out even when someone says post', (select x->>'cls' = 'skip_imprest' from jsonb_array_elements((:'pv2'::jsonb)->'rows') x where tt.n(x,'amt') = 100));
select tt.chk('T4 decisions are kept (3) and cannot be changed or deleted', (select count(*) from mkt_post_decisions) = 3);
select tt.err('T4 a decision is never deleted', $$delete from mkt_post_decisions$$, 'append_only');
select tt.chk('T4 the decisions are in audit_log', (select count(*) from audit_log where action = 'mkt_post_decide') = 3);
select mkt_post_run(false) as run2 \gset
select tt.chk('T4 the decided line (200) is posted on the next run; the total from this file is 410', tt.n(:'run2'::jsonb,'posted') = 1 and (select sum(l.debit) from journal_lines l join journal_entries e on e.id = l.entry_id where e.source_type = 'mkt_spend') = 410);

-- T5 no double count with 10-2: the voucher and the quick expense post through their own paths, this file never touched them
select acct_post_pending(false) ->> 'posted' as pp \gset
select tt.chk('T5 the 10-2 voucher is in the books through its own entry (300 marketing), and the 300 18-1 line was skipped', (select sum(l.debit) from journal_lines l join journal_entries e on e.id = l.entry_id join coa_accounts a on a.id = l.account_id where e.source_type = 'expense_voucher' and e.source_id like :'v1' || ':%' and a.code = '5500') = 300);
select tt.chk('T5 the books are balanced', tt.unbalanced() = 0);

-- T6 a sheet that is no longer approved: its entries are reversed on the next run
update entries set status = 'submitted' where id = :'m2'::uuid;
select mkt_post_run(false) as run3 \gset
select tt.chk('T6 the sheet left approved: its 2 entries are reversed, nothing deleted', tt.n(:'run3'::jsonb,'reversed') = 2 and (select count(*) from journal_entries where source_type = 'mkt_spend' and reverses_id is not null) = 2);
select tt.chk('T6 what stays from this file: only the decided 200 line', (select coalesce(sum(l.debit - l.credit) filter (where a.code = '5500'), 0) from journal_lines l join journal_entries e on e.id = l.entry_id join coa_accounts a on a.id = l.account_id where e.source_type = 'mkt_spend') = 200);
update entries set status = 'approved' where id = :'m2'::uuid;

-- T7 wind down, access, paste twice
select tt.as(:'u_acc');
select tt.err('T7 only the owner winds the posting down', $$select mkt_post_wind_down('stop')$$, 'not allowed');
select tt.as(:'u_o');
select tt.err('T7 a reason is required', $$select mkt_post_wind_down(' ')$$, 'reason_required');
select mkt_post_wind_down('test: back to nothing') as wd \gset
select tt.chk('T7 wind down moves everything back to zero (net 0 from this file)', (select coalesce(sum(l.debit - l.credit), 0) from journal_lines l join journal_entries e on e.id = l.entry_id where e.source_type = 'mkt_spend') = 0 and tt.unbalanced() = 0);
select tt.as(:'u_nb');
select tt.err('T7 nobody cannot see the preview', format($$select mkt_post_preview('%s','%s')$$, :'pm', :'td'), 'not allowed');
select tt.as(:'u_o');
select set_rule('marketing_post_on', 'false') is null as off1 \gset
select tt.err('T7 off again: the run refuses', $$select mkt_post_run(false)$$, 'marketing_post_off');
\i supabase/phase461.sql
select tt.chk('T7 paste twice keeps the decisions and the setting', (select count(*) from mkt_post_decisions) = 3 and rule_txt('marketing_post_from') = :'pm');
\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
