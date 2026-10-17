-- FRESH DB ONLY. Phase 459 tests (RPT-C3 R7 part 2): reports #164 spend by campaign, #165 spend vs sales, #166 campaign revenue and contribution, #167 discount campaigns.
--   bash tests/sql/rptc3_run.sh 459      (builds a fresh local database through phase 459 and runs this file)
-- Hand-computed numbers are in tests/sql/rptc3_fixture.sql. Test data only (test_* names).
\ir ../tests/sql/rptc3_head.sql
select to_char(tt.today() - 5, 'YYYY-MM-DD') as f, to_char(tt.today() + 1, 'YYYY-MM-DD') as t \gset

-- T1 spend by campaign (#164)
select tt.as(:'u_o');
select mkt_spend_by_campaign(:'f'::date, :'t'::date) as sp \gset
select tt.chk('T1 total spend is the paid lines only: 300 + 200 + 100', tt.n((:'sp'::jsonb)->'totals','spend') = 600);
select tt.chk('T1 the sample (value without payment 80) is apart, never added', tt.n((:'sp'::jsonb)->'totals','nonpay_value') = 80);
select tt.chk('T1 campaign A: 300 from the list, 30.0% of its budget 1000', (select tt.n(x,'spend') = 300 and tt.n(x,'budget_used_pct') = 30.0 and tt.n(x,'budget') = 1000 from jsonb_array_elements((:'sp'::jsonb)->'rows') x where x->>'campaign_code' = tt.k('ca')));
select tt.chk('T1 campaign B: 200 found by its free-text name, no budget so no percentage', (select tt.n(x,'spend') = 200 and x->>'budget_used_pct' is null and tt.n(x,'matched_by_text') = 1 from jsonb_array_elements((:'sp'::jsonb)->'rows') x where x->>'campaign_code' = tt.k('cb')));
select tt.chk('T1 unassigned 100 is its own row (null campaign), not guessed', (select tt.n(x,'spend') = 100 from jsonb_array_elements((:'sp'::jsonb)->'rows') x where x->>'campaign_code' is null));
select tt.chk('T1 coverage: 2 of 3 paid lines have a campaign (66.7%), 83.3% of the money', tt.n((:'sp'::jsonb)->'coverage','pct') = 66.7 and tt.n((:'sp'::jsonb)->'coverage','spend_with_campaign_pct') = 83.3);
select tt.chk('T1 a month breakdown is returned', jsonb_array_length((:'sp'::jsonb)->'by_month') = 3);
select tt.chk('T1 the unassigned row sorts last', (select (x->>'campaign_code') is null from jsonb_array_elements((:'sp'::jsonb)->'rows') with ordinality t(x, o) order by o desc limit 1));
-- a draft sheet and a sheet outside the dates are not counted
select save_entry(null,'18-1',1,tt.today(), jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('date',tt.today()::text,'head','1','amt','999','source','bank'))), '[]') ->> 'id' as dr \gset
select tt.chk('T1 a draft sheet is not counted', tt.n(mkt_spend_by_campaign(:'f'::date, :'t'::date)->'totals','spend') = 600);
select tt.chk('T1 a period with no lines says null, not 0', mkt_spend_by_campaign(tt.today()-400, tt.today()-399)->'totals'->>'spend' is null);
-- two campaigns with the same name: the text is ambiguous, the line stays unassigned
insert into option_lists (list_code, value_code, label_bn, label_en, sort, active) values ('marketing_campaigns','tw1','test_twin','test_twin',90,true), ('marketing_campaigns','tw2','test_twin','test_twin',91,true);
select save_entry(null,'18-1',1,tt.today(), jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('date',tt.today()::text,'head','3','campaign','test_twin','amt','40','source','bank'))), '[]') ->> 'id' as tw \gset
select submit_entry(:'tw'::uuid) is not null as tws \gset
select tt.chk('T1 an ambiguous free-text name is not guessed (stays unassigned)', (select tt.n(x,'spend') = 140 from jsonb_array_elements(mkt_spend_by_campaign(:'f'::date, :'t'::date)->'rows') x where x->>'campaign_code' is null));
select tt.chk('T1 a submitted (not yet approved) sheet is counted, and the approved part is shown apart', (select tt.n(x,'spend') = 140 and tt.n(x,'spend_approved') = 100 from jsonb_array_elements(mkt_spend_by_campaign(:'f'::date, :'t'::date)->'rows') x where x->>'campaign_code' is null));

-- T2 access: reports stay open to the existing grants, closed to everybody else
select tt.as(:'u_nb');
select tt.err('T2 nobody has no access', format($$select mkt_spend_by_campaign('%s','%s')$$, :'f', :'t'), 'not allowed');
select tt.as(:'u_st');
select tt.err('T2 a salesperson without a report grant has no access', format($$select mkt_campaign_performance('%s','%s')$$, :'f', :'t'), 'not allowed');
select tt.as(:'u_rm');
select tt.chk('T2 a report_marketing holder reads the report (place 1 only)', tt.n(mkt_spend_by_campaign(:'f'::date, :'t'::date)->'totals','spend') = 640);
select tt.err('T2 a reversed range is refused', format($$select mkt_spend_by_campaign('%s','%s')$$, :'t', :'f'), 'bad_range');
select tt.err('T2 a place he cannot see is refused', format($$select mkt_spend_by_campaign('%s','%s', 2)$$, :'f', :'t'), 'not allowed');
select tt.as(:'u_o');

-- T3 drill-down
select mkt_spend_lines(:'f'::date, :'t'::date, null, tt.k('ca')) as dl \gset
select tt.chk('T3 the lines of campaign A: one line of 300, not in the books', jsonb_array_length((:'dl'::jsonb)->'rows') = 1 and tt.n((:'dl'::jsonb)->'rows'->0,'amt') = 300 and ((:'dl'::jsonb)->'rows'->0->>'in_books') = 'false');
select tt.chk('T3 the lines with no campaign: 100 + the 80 sample + the 40 twin line + nothing else', jsonb_array_length(mkt_spend_lines(:'f'::date, :'t'::date, null, '__none')->'rows') = 3);
select tt.chk('T3 all lines (limit works)', jsonb_array_length(mkt_spend_lines(:'f'::date, :'t'::date, null, null, 2)->'rows') = 2);

-- T4 spend vs sales (#165)
select mkt_spend_vs_sales(:'f'::date, :'t'::date) as vs \gset
select tt.chk('T4 the same-day pairing: spend and bill totals side by side', tt.n((:'vs'::jsonb)->'totals','spend') >= 600 and tt.n((:'vs'::jsonb)->'totals','sales_total') > 0 and jsonb_array_length((:'vs'::jsonb)->'rows') >= 1);
select tt.chk('T4 it says "no causal claim" and "same day only"', (:'vs'::jsonb)->'notes' @> '["no_causal_claim","same_day_only"]'::jsonb);
select tt.chk('T4 campaign-tagged net sales are shown (300 + 180 = 480)', tt.n((:'vs'::jsonb)->'totals','campaign_tagged_net') = 480);

-- T5 campaign revenue and contribution (#166)
select mkt_campaign_performance(:'f'::date, :'t'::date) as pf \gset
select tt.chk('T5 campaign A: 2 bills, revenue 300, cost 42, contribution 258, spend 300, after spend -42', (select tt.n(x,'tagged_bills') = 2 and tt.n(x,'revenue_net') = 300 and tt.n(x,'cogs') = 42 and tt.n(x,'contribution_costed') = 258 and tt.n(x,'spend') = 300 and tt.n(x,'after_spend_costed') = -42 and tt.n(x,'cost_coverage_pct') = 100 from jsonb_array_elements((:'pf'::jsonb)->'rows') x where x->>'campaign_code' = tt.k('ca')));
select tt.chk('T5 campaign B: 1 bill of 180 after a discount of 20, contribution 152', (select tt.n(x,'tagged_bills') = 1 and tt.n(x,'revenue_net') = 180 and tt.n(x,'discount_given') = 20 and tt.n(x,'contribution_costed') = 152 from jsonb_array_elements((:'pf'::jsonb)->'rows') x where x->>'campaign_code' = tt.k('cb')));
select tt.chk('T5 attribution coverage is shown: 3 of 5 bills, 480 of 980', tt.n((:'pf'::jsonb)->'coverage','tagged_bills') = 3 and tt.n((:'pf'::jsonb)->'coverage','bills') = 5 and tt.n((:'pf'::jsonb)->'coverage','tagged_pct') = 60 and tt.n((:'pf'::jsonb)->'coverage','tagged_revenue_pct') = 49);
-- a campaign with spend and no tagged sales: money columns are null, not 0
select mkt_campaign_save(null, '{"name_bn":"test_lonely_c","force":true}') ->> 'value_code' as lo \gset
select save_entry(null,'18-1',1,tt.today(), jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('date',tt.today()::text,'head','2','campaign_id',:'lo','amt','60','source','bank'))), '[]') ->> 'id' as l1 \gset
select submit_entry(:'l1'::uuid) is not null as l1s \gset
select tt.chk('T5 spend but no tagged sale: revenue and contribution are null ("no tagged sales"), not 0', (select x->>'revenue_net' is null and x->>'contribution_costed' is null and (x->>'no_tagged_sales') = 'true' and tt.n(x,'spend') = 60 from jsonb_array_elements(mkt_campaign_performance(:'f'::date, :'t'::date)->'rows') x where x->>'campaign_code' = :'lo'));
-- an uncosted sale (a quick sale line has no item, so no cost): coverage drops, contribution stays on the costed part only
select record_sale2(gen_random_uuid(),1,'[{"amount":50}]'::jsonb,0,'[{"mode":"cash","amount":50}]',null,null,'retail',null,true)->>'id' as q1 \gset
select mkt_tag_sale(:'q1'::uuid, tt.k('ca'), null) ->> 'ok' as q1t \gset
select tt.chk('T5 an uncosted bill: revenue 350, costed 300 (coverage 85.7%), contribution still 258', (select tt.n(x,'revenue_net') = 350 and tt.n(x,'costed_net') = 300 and tt.n(x,'cost_coverage_pct') = 85.7 and tt.n(x,'contribution_costed') = 258 from jsonb_array_elements(mkt_campaign_performance(:'f'::date, :'t'::date)->'rows') x where x->>'campaign_code' = tt.k('ca')));
-- a return on a tagged bill reduces revenue and cost (rule reports_net_of_returns, default on)
select sale_return(gen_random_uuid(), tt.k('s4')::uuid, format('[{"item_id":"%s","qty":1}]', (select id from items where code='W1D-FG'))::jsonb, 'damaged', null, 'cash', null, null) is not null as rr \gset
select tt.chk('T5 after a return of 100 on bill 4: revenue 250, costed 200, cost 28, contribution 172', (select tt.n(x,'revenue_net') = 250 and tt.n(x,'costed_net') = 200 and tt.n(x,'cogs') = 28 and tt.n(x,'contribution_costed') = 172 from jsonb_array_elements(mkt_campaign_performance(:'f'::date, :'t'::date)->'rows') x where x->>'campaign_code' = tt.k('ca')));
select set_rule('reports_net_of_returns', 'false') is null as nr \gset
select tt.chk('T5 with returns not netted (the owner setting) the revenue is back to 350', (select tt.n(x,'revenue_net') = 350 from jsonb_array_elements(mkt_campaign_performance(:'f'::date, :'t'::date)->'rows') x where x->>'campaign_code' = tt.k('ca')));
select set_rule('reports_net_of_returns', null) is null as nr2 \gset
-- the drill rows
select tt.chk('T5 drill: the sales behind campaign A (s1, s4 and the quick bill)', jsonb_array_length(mkt_campaign_sales(:'f'::date, :'t'::date, null, tt.k('ca'))->'rows') = 3);
-- cost is hidden from a reader who has no cost right
select tt.as(:'u_rm');
select mkt_campaign_performance(:'f'::date, :'t'::date) as pf2 \gset
select tt.chk('T5 without the cost right the cost columns are null and the report says so', (select x->>'cogs' is null and x->>'contribution_costed' is null and x->>'costed_net' is null and tt.n(x,'revenue_net') = 250 from jsonb_array_elements((:'pf2'::jsonb)->'rows') x where x->>'campaign_code' = tt.k('ca')) and (:'pf2'::jsonb)->'notes' ? 'cost_hidden');
select tt.as(:'u_o');

-- T6 discount campaigns (#167)
select mkt_discount_campaigns(:'f'::date, :'t'::date) as dc \gset
select tt.chk('T6 campaign B: 1 discount bill, 20 off 200 = 10.0%, average bill 180', (select tt.n(x,'discount_bills') = 1 and tt.n(x,'discount_total') = 20 and tt.n(x,'discount_pct_of_gross') = 10.0 and tt.n(x,'avg_bill_net') = 180 from jsonb_array_elements((:'dc'::jsonb)->'rows') x where x->>'campaign_code' = tt.k('cb')));
select tt.chk('T6 campaign A carries a code on a bill without any discount: counted apart, no discount figure invented', (select tt.n(x,'offer_code_without_discount') = 1 and x->>'discount_total' is null from jsonb_array_elements((:'dc'::jsonb)->'rows') x where x->>'campaign_code' = tt.k('ca')));
select tt.chk('T6 the baseline of bills with no discount is shown', tt.n((:'dc'::jsonb)->'baseline_no_discount','bills') >= 3);
select tt.chk('T6 a note says the comparison is not proof', (:'dc'::jsonb)->'notes' ? 'compare_with_baseline_is_not_proof');
select tt.chk('T6 nothing was written to the journal by any of these reports', (select count(*) from journal_entries where source_type like 'mkt%') = 0);

select tt.chk('T7 no journal entry is unbalanced', tt.unbalanced() = 0);
\i supabase/phase459.sql
select tt.chk('T7 paste twice keeps the answers', tt.n(mkt_spend_by_campaign(:'f'::date, :'t'::date)->'totals','spend') = 700);
\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
