-- Union variant of the phase 92 suite: the advanced line has two rules whose key also starts with profit_ (profit_truth_mode, profit_variable_heads, bilingual labels); the checks of our profit rules skip them.
-- COPY of phase92_test.sql for the database that holds BOTH lines (tests/sql/run_all_union.sh, tests/sql/union_replaced_tests.txt). The original is not edited and is not run in the union.
-- FRESH DB ONLY. Phase 92 tests: U-05 one profit number (package W1-D).
--   bash <build script with your worktree paths and port> db92       (phases 8 .. 87, then phase92 is applied by this file's caller:  psql -f supabase/phase92.sql)
--   psql -h /tmp -p <port> -U postgres -d db92 -qAt -f supabase/phase92_test.sql | grep -E 'FAIL|RESULT'
-- The data comes from tests/sql/w1d_fixture.sql (hand-computed numbers in its header). Test data only (test_* names). Places 1 and 2 only.
\set ON_ERROR_STOP off
\ir ../tests/sql/w1d_fixture.sql
\set ON_ERROR_STOP off
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
-- the L1 profit of place 1 for the current month, and the pieces of _p27_pl for place 1
create or replace function tt.l1(p_key text) returns numeric language sql stable as $$
  select (x ->> p_key)::numeric from public._r3q_l1_pnl(date_trunc('month', tt.today())::date, tt.today(), array[1], '{}'::jsonb) x where x ->> 'month' = to_char(tt.today(), 'YYYY-MM') and x ->> 'row_type' is null limit 1 $$;
create or replace function tt.l3(p_key text) returns numeric language sql stable as $$
  select (x ->> p_key)::numeric from public._r3q_l3_shop_pnl(date_trunc('month', tt.today())::date, tt.today(), array[1], '{}'::jsonb) x where (x ->> 'location_id')::int = 1 and x ->> 'row_type' is null limit 1 $$;
create or replace function tt.pl(p_col text) returns numeric language plpgsql stable as $$
declare v numeric;
begin execute format('select sum(%I) from public._p27_pl(date_trunc(''month'', tt.today())::date, tt.today(), array[1])', p_col) into v; return v; end $$;
-- turn the six cause switches: all on / all off / only one on
create or replace function tt.causes(p_only text default null) returns void language plpgsql as $$
declare k text;
begin
  foreach k in array array['profit_loss_wastage', 'profit_loss_count', 'profit_loss_transit', 'profit_loss_cashshort', 'profit_loss_billopex', 'profit_overhead_once'] loop
    perform public.set_rule(k, to_jsonb(p_only is null or k = p_only));
  end loop;
end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
select (now() at time zone 'Asia/Dhaka')::date as td \gset
select date_trunc('month', :'td'::date)::date as m1 \gset
select (:'pm'::date) as d1 \gset

\echo == T0 shape, safe defaults, patches in place, internals closed
select tt.chk('T0 phase92 present; settings exist: master off, start date blank, six switches on, source management',
  to_regprocedure('public._w1d_p92_present()') is not null and not rule_on('profit_one_number_on') and rule_txt('profit_losses_from') is null
  and rule_on('profit_loss_wastage') and rule_on('profit_loss_count') and rule_on('profit_loss_transit') and rule_on('profit_loss_cashshort') and rule_on('profit_loss_billopex') and rule_on('profit_overhead_once')
  and rule_txt('profit_source') = 'management' and (select count(*) from rules where key like 'profit\_%' and key not in ('profit_truth_mode', 'profit_variable_heads') and module = 'reports') = 9);
select tt.chk('T0 labels and hints are English and not empty (owner rule 5)', not exists (select 1 from rules where key like 'profit\_%' and key not in ('profit_truth_mode', 'profit_variable_heads') and (label_en is null or hint_en is null or label_bn <> label_en or label_mix <> label_en or label_en ~ '[^ -~]')));
select tt.chk('T0 the patches are in place (marker bos92) in _p27_pl, partner_calculate, c_partner_month_split',
  (select count(*) from (values ('public._p27_pl(date,date,int[])'),('public.partner_calculate(bigint,date,date,jsonb)'),('public.c_partner_month_split(date)')) v(f) where position('bos92' in pg_get_functiondef(v.f::regprocedure)) > 0) = 3);
select tt.chk('T0 earlier tags survive inside _p27_pl (bos50, bos72, bos85, bos86)', (select bool_and(position(t in pg_get_functiondef('public._p27_pl(date,date,int[])'::regprocedure)) > 0) from unnest(array['bos50','bos72','bos85','bos86']) t));
select tt.chk('T0 internals closed to browsers, API open, anon has nothing',
  not has_function_privilege('authenticated','public._w1d_patch(regprocedure,text,text[])','execute') and not has_function_privilege('authenticated','public._w1d_pl_rows(date,date,int[])','execute')
  and not has_function_privilege('authenticated','public._w1d_pl_extra(date,date,int[])','execute') and not has_function_privilege('authenticated','public._w1d_mgmt_profit(date,date,int[])','execute')
  and has_function_privilege('authenticated','public.profit_recon(date,date,int)','execute') and has_function_privilege('authenticated','public.profit_exclude(text,text,text)','execute')
  and not has_function_privilege('anon','public.profit_recon(date,date,int)','execute') and not has_function_privilege('anon','public.profit_exclude(text,text,text)','execute'));
select tt.chk('T0 the exclusion table cannot be written by a browser role and cannot be deleted from', not has_table_privilege('authenticated','public.profit_row_exclusions','insert')
  and not has_table_privilege('authenticated','public.profit_row_exclusions','update') and not has_table_privilege('anon','public.profit_row_exclusions','select'));
select md5(pg_get_functiondef('public._p27_pl(date,date,int[])'::regprocedure)) || md5(pg_get_functiondef('public.partner_calculate(bigint,date,date,jsonb)'::regprocedure)) || md5(pg_get_functiondef('public.c_partner_month_split(date)'::regprocedure)) as h_before \gset
select count(*) as n_rules_before from rules \gset
\ir phase92.sql
select tt.chk('T0 pasting phase92 again changes nothing (function bodies identical, same number of rules)',
  md5(pg_get_functiondef('public._p27_pl(date,date,int[])'::regprocedure)) || md5(pg_get_functiondef('public.partner_calculate(bigint,date,date,jsonb)'::regprocedure)) || md5(pg_get_functiondef('public.c_partner_month_split(date)'::regprocedure)) = :'h_before'
  and (select count(*) from rules) = :n_rules_before);
select tt.err('T0 a patch whose site is missing stops with a clear message', $$select public._w1d_patch('public._w1d_losses_from()'::regprocedure, 'bos99', array['text that is not there', 'x /* bos99 */'])$$, 'patch site not found');
select tt.err('T0 a bad marker is refused', $$select public._w1d_patch('public._w1d_losses_from()'::regprocedure, 'oops', array['a','b'])$$, 'bad_marker');

\echo == T1 DEFAULTS KEEP TODAY: master off, nothing changes (net 400, cost of goods 56, expenses 800 = voucher 500 + quick 300, profit -456)
select tt.as(:'o');
select tt.chk('T1 _p27_pl: net sales 400, cogs 56, expenses 800, salary none', tt.pl('o_net') = 400 and tt.pl('o_cogs') = 56 and tt.pl('o_exp') = 800 and tt.pl('o_sal') is null);
select tt.chk('T1 the candidate rows exist (the data is there) but none is counted', (select count(*) from _w1d_pl_rows(:'d1'::date, :'td'::date, array[1,2])) = 7 and (select count(*) from _w1d_pl_extra(:'d1'::date, :'td'::date, array[1,2])) = 0);
select tt.chk('T1 L1 and L3 profit = 400 - 56 - 800 = -456', tt.l1('profit') = -456 and tt.l3('profit') = -456 and tt.l1('expenses') = 800);
select partner_party_save(null,'test_p_owner','company',null,null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pa \gset
select partner_party_save(null,'test_p_inv','individual',null,null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pb \gset
select partner_venture_save(null,'test venture','test venture','location',1,'own','2020-01-01',null,'draft',null,gen_random_uuid()) ->> 'id' as v1 \gset
select (partner_agreement_save(null, :v1::bigint, 'test deed', '2020-01-01', null, '[]'::jsonb, null, gen_random_uuid()) ->> 'id')::bigint as ag \gset
select partner_agreement_party_set(:ag, :pa::bigint, 'owner', 60, null) is not null as x1 \gset
select partner_agreement_party_set(:ag, :pb::bigint, 'investor', 40, null) is not null as x2 \gset
select partner_rule_save(:ag, null, 'Base', 'base', '{"base":"net_profit_before_fees"}'::jsonb) is not null as r1 \gset
select partner_rule_save(:ag, null, 'Split', 'split', '{"shares":[{"role":"owner","percent":60},{"role":"investor","percent":40}]}'::jsonb) is not null as r2 \gset
select partner_agreement_activate(:ag, true) is not null as act \gset
select tt.chk('T1 partner settlement base = management -456; the preview still uses the journal (-796: cash short not posted, count shortage not in the journal) and says so',
  (partner_calculate(:ag, :'m1', :'td') -> 'bases' ->> 'net_profit_before_fees')::numeric = -456
  and (c_partner_month_split(:'m1'::date) -> 'agreements' -> 0 ->> 'base_profit')::numeric = -796
  and c_partner_month_split(:'m1'::date) ->> 'basis' = 'journal net profit of the month (salary accrual included)');
select tt.chk('T1 the basis stored with a settlement says: one number off, source management, no extra rows', (partner_calculate(:ag, :'m1', :'td') -> 'profit_basis') = '{"note": null, "source": "management", "extra_rows": {}, "one_number": false, "losses_from": null}'::jsonb);
select tt.chk('T1 break-even and staff-cost ratio read the same unchanged figures', (select (x ->> 'net_sales')::numeric from _r3q_t4_staff_cost_ratio(:'d1'::date, :'td'::date, array[1], '{}'::jsonb) x) = 400);

\echo == T2 MASTER ON, all causes: expenses 800 + wastage 30 + count 120 + transit 50 + cash 15 + bill 300 - overhead 40 = 1275, profit -931
select set_rule('profit_one_number_on', 'true') is null as on1 \gset
select tt.chk('T2 _p27_pl expenses 1275, net 400, cogs 56 (sales and cogs untouched)', tt.pl('o_exp') = 1275 and tt.pl('o_net') = 400 and tt.pl('o_cogs') = 56);
select tt.chk('T2 L1 profit -931, expenses 1275', tt.l1('profit') = -931 and tt.l1('expenses') = 1275);
select tt.chk('T2 L3 (branch ranking) profit -931 and profit % = -232.75', tt.l3('profit') = -931 and tt.l3('profit_pct') = -232.75);
select tt.chk('T2 the piece amounts by cause: wastage 30, count 120, transit 50, cash 15, bill 300, overhead -40',
  (select jsonb_object_agg(cause, s) from (select cause, round(sum(amt),2) s from _w1d_pl_rows_on(:'d1'::date, :'td'::date, array[1]) group by 1) z) =
  '{"wastage":30.00,"count_shrink":120.00,"transit_loss":50.00,"cash_short":15.00,"bill_opex":300.00,"overhead_absorbed":-40.00}'::jsonb);
select tt.chk('T2 partner settlement base = management -931 and the PREVIEW now equals it', (partner_calculate(:ag, :'m1', :'td') -> 'bases' ->> 'net_profit_before_fees')::numeric = -931
  and (c_partner_month_split(:'m1'::date) -> 'agreements' -> 0 ->> 'base_profit')::numeric = -931 and c_partner_month_split(:'m1'::date) ->> 'basis' like 'management profit of the month%');
select tt.chk('T2 the settlement basis lists the rows it counted', (partner_calculate(:ag, :'m1', :'td') -> 'profit_basis' ->> 'source') = 'management' and (partner_calculate(:ag, :'m1', :'td') -> 'profit_basis' -> 'extra_rows' ->> 'wastage')::numeric = 30
  and (partner_calculate(:ag, :'m1', :'td') -> 'profit_basis' ->> 'one_number')::boolean);
select partner_settlement_save(:ag, :'m1', :'td', null, 'test month', gen_random_uuid()) ->> 'id' as ps \gset
select tt.chk('T2 every settlement STORES its basis (calc.profit_basis)', (select calc -> 'profit_basis' ->> 'source' from partner_settlements where id = :ps::bigint) = 'management'
  and (select (calc -> 'bases' ->> 'net_profit_before_fees')::numeric from partner_settlements where id = :ps::bigint) = -931);
select tt.chk('T2 factory overhead is NOT counted twice: the 40 of conversion cost sits in the cost of the run (16 of it in the cost of goods sold, 24 in stock); the expenses lose all 40',
  (select conversion_cost from production_runs where id = :'w_run'::uuid) = 40 and tt.pl('o_cogs') = 56 and (select amt from _w1d_pl_rows_on(:'d1'::date, :'td'::date, array[1]) where cause = 'overhead_absorbed') = -40);

\echo == T3 each cause alone (only that switch on)
select tt.causes('profit_loss_wastage'); select tt.chk('T3 wastage only: expenses 830, profit -486', tt.pl('o_exp') = 830 and tt.l1('profit') = -486);
select tt.causes('profit_loss_count'); select tt.chk('T3 count shortage only: expenses 920, profit -576', tt.pl('o_exp') = 920 and tt.l1('profit') = -576);
select tt.causes('profit_loss_transit'); select tt.chk('T3 transit only: expenses 850, profit -506', tt.pl('o_exp') = 850 and tt.l1('profit') = -506);
select tt.causes('profit_loss_cashshort'); select tt.chk('T3 cash short only: -20 short + 5 over = 15 loss, expenses 815, profit -471', tt.pl('o_exp') = 815 and tt.l1('profit') = -471);
select tt.causes('profit_loss_billopex'); select tt.chk('T3 bill-paid running cost only: 300 (the 100 of raw stock is not a cost), expenses 1100, profit -756', tt.pl('o_exp') = 1100 and tt.l1('profit') = -756);
select tt.causes('profit_overhead_once'); select tt.chk('T3 overhead only: expenses 760, profit -416', tt.pl('o_exp') = 760 and tt.l1('profit') = -416);
select tt.causes(null);
select tt.chk('T3 all back on: 1275', tt.pl('o_exp') = 1275);

\echo == T4 start date: nothing before it is touched
select set_rule('profit_losses_from', to_jsonb((:'td'::date + 1)::text)) is null as f1 \gset
select tt.chk('T4 start date tomorrow: nothing is counted yet (expenses back to 800)', tt.pl('o_exp') = 800 and (select count(*) from _w1d_pl_extra(:'d1'::date, :'td'::date, array[1])) = 0);
select set_rule('profit_losses_from', to_jsonb(:'td'::text)) is null as f2 \gset
select tt.chk('T4 start date today: counted (1275)', tt.pl('o_exp') = 1275);
select set_rule('profit_losses_from', '"not a date"'::jsonb) is null as f3 \gset
select tt.chk('T4 a start date that is not a date is ignored, never invented: counted from the start (1275)', tt.pl('o_exp') = 1275 and _w1d_losses_from() is null);
select set_rule('profit_losses_from', null) is null as f4 \gset
select tt.chk('T4 blank again', _w1d_losses_from() is null and tt.pl('o_exp') = 1275);

\echo == T5 exception path: leave ONE named loss out of the profit, with a reason; audit_log and the Exceptions list
set role authenticated; select tt.as(:'st');
select tt.err('T5 a salesperson cannot leave a loss out (server refuses)', format($$select profit_exclude('wastage', %L, 'a reason that is long enough')$$, :'w_waste'), 'not allowed');
select tt.err('T5 a salesperson cannot list', $$select profit_exclusions_list()$$, 'not allowed');
select tt.as(:'o');
select tt.err('T5 a reason is required (blank)', format($$select profit_exclude('wastage', %L, '  ')$$, :'w_waste'), 'reason_required');
select tt.err('T5 a reason is required (too short)', format($$select profit_exclude('wastage', %L, 'abc')$$, :'w_waste'), 'reason_required');
select tt.err('T5 unknown cause', format($$select profit_exclude('rent', %L, 'a reason that is long enough')$$, :'w_waste'), 'bad_cause');
select tt.err('T5 a row that does not exist', $$select profit_exclude('wastage', 'no-such-row', 'a reason that is long enough')$$, 'row_not_found');
select profit_exclude('wastage', :'w_waste', 'flood damage, owner decision') as x1 \gset
reset role;
select tt.chk('T5 the wastage 30 is left out: expenses 1245, profit -901', tt.pl('o_exp') = 1245 and tt.l1('profit') = -901);
select tt.chk('T5 audit_log has the line with the reason', exists (select 1 from audit_log where table_name = 'profit_row_exclusions' and action = 'insert' and detail -> 'new' ->> 'reason' = 'flood damage, owner decision'));
select tt.chk('T5 the Exceptions list has a yellow line with the amount', exists (select 1 from exceptions where flag_code = 'profit_row_excluded' and level = 'yellow' and amount = 30));
set role authenticated; select tt.as(:'o');
select tt.err('T5 the same row twice is refused', format($$select profit_exclude('wastage', %L, 'a reason that is long enough')$$, :'w_waste'), 'already_excluded');
select tt.chk('T5 the list shows it', jsonb_array_length(profit_exclusions_list('active')) = 1);
select tt.err('T5 revoke needs a reason', format($$select profit_exclusion_revoke(%s, 'x')$$, :'x1'), 'reason_required');
select tt.as(:'st'); select tt.err('T5 a salesperson cannot revoke', format($$select profit_exclusion_revoke(%s, 'a reason that is long enough')$$, :'x1'), 'not allowed');
select tt.as(:'acc');
select profit_exclude('count_shrink', :'w_cnt', 'recount agreed with the accountant') as x2 \gset
select tt.chk('T5 an accounts manager (not the owner) may also record the exception', :'x2' is not null);
select tt.as(:'o');
select profit_exclusion_revoke(:'x1'::bigint, 'counted again after the review') as rv \gset
select profit_exclusion_revoke(:'x2'::bigint, 'counted again after the review') as rv2 \gset
select tt.err('T5 revoking twice is refused', format($$select profit_exclusion_revoke(%s, 'a reason that is long enough')$$, :'x1'), 'not_active');
reset role;
select tt.chk('T5 revoked: the losses are counted again (1275) and the revoke is in audit_log and the Exceptions list', tt.pl('o_exp') = 1275
  and exists (select 1 from audit_log where table_name = 'profit_row_exclusions' and action = 'update' and detail -> 'new' ->> 'status' = 'revoked')
  and exists (select 1 from exceptions where flag_code = 'profit_row_exclusion_revoked'));

\echo == T6 a short that is booked as a staff receivable is not a loss; a new short is counted
reset role;
insert into employees (employee_no, full_name_bn) values ('E92','test_emp') returning id as emp \gset
select set_rule('cash_short_treatment', '"staff_receivable"') is null as tr1 \gset
insert into entries (form_code,location_id,serial,entry_date,status,created_by,created_staff) values ('14-1',1,92003,:'td',  'submitted',:'o','t');
select id as w_e3 from entries where serial=92003 and form_code='14-1' \gset
insert into exceptions (entry_id,form_code,location_id,entry_date,flag_code,level,amount,text) values (:'w_e3','14-1',1,:'td','cash_short_over','yellow',-12,'{}');
select id as w_cs3 from shortage_cash_cases where entry_id = :'w_e3' \gset
select tt.as(:'o');
select cash_short_decide(:'w_cs3'::uuid, true, 'collect from the cashier', :'emp'::uuid, true) ->> 'treatment' as trt \gset
select set_rule('cash_short_treatment', '"expense"') is null as tr2 \gset
select tt.chk('T6 the receivable short (12) adds nothing: cash short stays 15 and expenses stay 1275', :'trt' = 'staff_receivable' and tt.pl('o_exp') = 1275
  and (select round(sum(amt),2) from _w1d_pl_rows_on(:'d1'::date, :'td'::date, array[1]) where cause = 'cash_short') = 15);

\echo == T7 recon: management against the journal, the difference by named cause
select tt.chk('T7 journal first: sale, production, wastage, transit, bill, vouchers are posted; cash short and the count shortage are not',
  (select count(*) from journal_entries where source_type = 'cash_short') = 0 and tt.unbalanced() = 0);
set role authenticated; select tt.as(:'o');
select profit_recon(:'d1'::date, :'td'::date, null) as rc \gset
reset role;
select tt.chk('T7 management -931, journal -796, difference -135 = count shortage -120 + cash short -15 (the receivable short of 12 is on neither side)',
  (:'rc'::jsonb ->> 'management_profit')::numeric = -931 and (:'rc'::jsonb ->> 'ledger_profit')::numeric = -796 and (:'rc'::jsonb ->> 'difference')::numeric = -135);
select tt.chk('T7 the whole difference is explained by named causes (unexplained 0)', (:'rc'::jsonb ->> 'explained')::numeric = -135 and (:'rc'::jsonb ->> 'unexplained')::numeric = 0
  and (select r ->> 'reason' from jsonb_array_elements(:'rc'::jsonb -> 'rows') r where r ->> 'key' = 'count_shrink') = 'count_adjustment_not_in_journal_yet'
  and (select r ->> 'reason' from jsonb_array_elements(:'rc'::jsonb -> 'rows') r where r ->> 'key' = 'cash_short') = 'cash_short_not_posted_to_journal');
select tt.chk('T7 every other line agrees: sales 400, cost of goods -56, vouchers -800, wastage -30, transit -50, bill -300, overhead +40, no gap',
  (select bool_and((r ->> 'difference')::numeric = 0) from jsonb_array_elements(:'rc'::jsonb -> 'rows') r where r ->> 'key' not in ('count_shrink', 'cash_short'))
  and (select (r ->> 'ledger')::numeric from jsonb_array_elements(:'rc'::jsonb -> 'rows') r where r ->> 'key' = 'overhead_absorbed') = 40
  and (select (r ->> 'ledger')::numeric from jsonb_array_elements(:'rc'::jsonb -> 'rows') r where r ->> 'key' = 'bill_opex') = -300);
select tt.chk('T7 the effect before switching on is shown (would_add_if_counted: wastage 30, count 120, transit 50, cash 15, bill 300, overhead -40)',
  (:'rc'::jsonb -> 'would_add_if_counted' -> 'count_shrink' ->> 'amount')::numeric = 120 and (:'rc'::jsonb -> 'would_add_if_counted' -> 'overhead_absorbed' ->> 'amount')::numeric = -40
  and (:'rc'::jsonb -> 'would_add_if_counted' -> 'cash_short' ->> 'amount')::numeric = 15);
set role authenticated; select tt.as(:'o');
select set_rule('cash_short_post_on', 'true') is null as cp1 \gset
select acct_post_pending(false) ->> 'posted' as pp1 \gset
select profit_recon(:'d1'::date, :'td'::date, null) as rc2 \gset
reset role;
select tt.chk('T7 after the cash short is posted: difference -120 (only the count shortage), cash short agrees, journal still balanced', (:'rc2'::jsonb ->> 'difference')::numeric = -120
  and (select (r ->> 'difference')::numeric from jsonb_array_elements(:'rc2'::jsonb -> 'rows') r where r ->> 'key' = 'cash_short') = 0 and (:'rc2'::jsonb ->> 'unexplained')::numeric = 0 and tt.unbalanced() = 0);
select tt.chk('T7 the staff-receivable short is on neither profit side (journal Dr 1220 12, no expense)', exists (select 1 from journal_lines l join journal_entries e on e.id = l.entry_id join coa_accounts a on a.id = l.account_id where e.source_type = 'cash_short' and e.source_id = :'w_cs3' and a.code = '1220' and l.debit = 12));
set role authenticated; select tt.as(:'o');
select profit_recon(:'d1'::date, :'td'::date, 1) as rc3 \gset
select profit_recon(:'d1'::date, :'td'::date, 2) as rc4 \gset
reset role;
select tt.chk('T7 place filter: place 1 carries everything (-931), place 2 nothing', (:'rc3'::jsonb ->> 'management_profit')::numeric = -931 and (:'rc4'::jsonb ->> 'management_profit')::numeric = 0);
set role authenticated; select tt.as(:'st');
select tt.err('T7 a salesperson cannot run the reconciliation', format($$select profit_recon(%L, %L, null)$$, :'d1', :'td'), 'not allowed');
select tt.as(:'o');
select tt.err('T7 bad range', format($$select profit_recon(%L, %L, null)$$, :'td', :'d1'), 'bad_range');
select tt.err('T7 a range over ten years', $$select profit_recon(date '2000-01-01', date '2026-01-01', null)$$, 'bad_range');

\echo == T8 recon with the master OFF: the missing rows are explained by the switch
select set_rule('profit_one_number_on', 'false') is null as off1 \gset
select profit_recon(:'d1'::date, :'td'::date, null) as rc5 \gset
reset role;
select tt.chk('T8 master off: management -456, journal -796 (with cash short posted), the gap is explained row by row (switch off / count not in journal), unexplained 0',
  (:'rc5'::jsonb ->> 'management_profit')::numeric = -456 and (:'rc5'::jsonb ->> 'unexplained')::numeric = 0
  and (select r ->> 'reason' from jsonb_array_elements(:'rc5'::jsonb -> 'rows') r where r ->> 'key' = 'wastage') = 'not_counted_in_management_profit_switch_off'
  and (select r ->> 'reason' from jsonb_array_elements(:'rc5'::jsonb -> 'rows') r where r ->> 'key' = 'overhead_absorbed') = 'not_counted_in_management_profit_switch_off');
select tt.chk('T8 master off: every figure is back to today (expenses 800, L1 profit -456, partner base -456)', tt.pl('o_exp') = 800 and tt.l1('profit') = -456
  and (partner_calculate(:ag, :'m1', :'td') -> 'bases' ->> 'net_profit_before_fees')::numeric = -456);

\echo == T9 profit source = ledger (only while the master is ON)
select set_rule('profit_source', '"ledger"') is null as pl1 \gset
select tt.chk('T9 master off: the source choice does nothing (base still -456, basis says management)', (partner_calculate(:ag, :'m1', :'td') -> 'bases' ->> 'net_profit_before_fees')::numeric = -456
  and partner_calculate(:ag, :'m1', :'td') -> 'profit_basis' ->> 'source' = 'management');
select set_rule('profit_one_number_on', 'true') is null as on2 \gset
select tt.chk('T9 settlement base = journal profit and the preview equals it (journal profit now includes the posted cash short 15: -796 - 15 = -811)',
  (partner_calculate(:ag, :'m1', :'td') -> 'bases' ->> 'net_profit_before_fees')::numeric = -811 and (c_partner_month_split(:'m1'::date) -> 'agreements' -> 0 ->> 'base_profit')::numeric = -811
  and partner_calculate(:ag, :'m1', :'td') -> 'profit_basis' ->> 'source' = 'ledger');
select tt.chk('T9 the journal is not available before the accounting start: the override says so and the management figure is used',
  (select _w1d_profit_override(date '2000-01-01', date '2000-01-31', 1)) ->> 'note' like 'The journal has no data%' and (select _w1d_profit_override(date '2000-01-01', date '2000-01-31', 1)) ->> 'net_profit' is null);
select set_rule('profit_source', '"management"') is null as pl2 \gset
select tt.chk('T9 back to management: -931 minus nothing (cash short already counted) = -931', (partner_calculate(:ag, :'m1', :'td') -> 'bases' ->> 'net_profit_before_fees')::numeric = -931);

\echo == T10 settings: owner only, audited, English
set role authenticated; select tt.as(:'st');
select tt.err('T10 a salesperson cannot change a setting', $$select set_rule('profit_one_number_on', 'false')$$, 'not allowed');
select tt.as(:'o');
select tt.err('T10 a choice setting refuses a value that is not a choice', $$select set_rule('profit_source', '"both"')$$, 'bad_value');
select tt.err('T10 a switch refuses a text', $$select set_rule('profit_loss_wastage', '"yes"')$$, 'bad_value');
reset role;
select tt.chk('T10 every change of the master switch is in audit_log (old and new)', (select count(*) from audit_log where table_name = 'rules' and record_id = 'profit_one_number_on' and action = 'update') >= 3);

\echo == T11 the books: nothing of this phase posts or unbalances anything
select tt.chk('T11 every journal entry balances', tt.unbalanced() = 0);
select tt.chk('T11 phase92 wrote no journal entry of its own (no source type starts with profit)', not exists (select 1 from journal_entries where source_type like 'profit%'));
select tt.chk('T11 the balance check still runs', (public._e_balance_check() ->> 'status') is not null);

select 'RESULT: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from tt.res;
select name from tt.res where not ok;
