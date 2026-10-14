-- A3 machine-checkable probes (added by the verification harness). Appended after a3_scenario.sql, same psql session.
-- Every probe asserts the CORRECT behaviour from docs/audit2/A3_real_profit.md; FAIL = the gap is still open.
-- Label = "C<n> ..." where C<n> is the check id of section 3 of the report (gap map: gap_map.tsv).
\echo == A3 PROBES (assert correct behaviour; FAIL = gap open)
create or replace function tt.try(p_sql text) returns boolean language plpgsql as $$ begin execute p_sql; return true; exception when others then return false; end $$;
select tt.as(:'o');
-- C11 / G1: one profit number: sum of branch profits (with shares) equals the company books
select tt.t('C11 sum of branch P&L profits (shop P&L incl. shares) equals company net profit in the books',
  abs(coalesce((select sum((x->>'profit')::numeric) from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[1,2,3,6], '{}'::jsonb) x),0)
    - coalesce((acct_income_statement(tt.today(), tt.today(), null)->>'net_profit')::numeric,0)) < 0.01);
-- C9 / G2: the S1 salary (300, sheet 02-2) is also in the books of S1
select tt.t('C9 salary 300 of S1 appears as an expense in the books (GL) of S1',
  exists (select 1 from jsonb_array_elements(acct_income_statement(tt.today(), tt.today(), 2)->'expense') x join coa_accounts a on a.id=(x->>'id')::bigint
          where (a.code like '52%' or a.name_en ilike '%salar%' or a.name_en ilike '%payroll%' or a.name_en ilike '%wage%') and (x->>'amount')::numeric >= 300));
-- C7 / G3: S2 wastage 40 reaches the branch P&L: profit 640-320-40(delivery)-40(waste)=240, or an explicit wastage field of 40
select tt.t('C7 wastage 40 of S2 is in the branch P&L (profit 240 or a wastage field = 40)',
  coalesce((select abs((o_net - o_cogs - coalesce(o_exp,0) - coalesce(o_sal,0) - coalesce(o_fixed,0)) - 240) < 0.01 from _p27_pl(tt.today(), tt.today(), array[3]) limit 1), false)
  or exists (select 1 from _p27_pl(tt.today(), tt.today(), array[3]) p, jsonb_each_text(to_jsonb(p)) e where e.key ilike '%wast%' and e.value ~ '^-?[0-9.]+$' and abs(e.value::numeric - 40) < 0.01)
  or exists (select 1 from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[3], '{}'::jsonb) x, jsonb_each_text(x) e where e.key ilike '%wast%' and e.value ~ '^-?[0-9.]+$' and abs(e.value::numeric - 40) < 0.01));
-- C8 / G4: card fee 7.20 of S1 reaches the branch P&L (a fee field of 7.2, or profit 110 - 7.2)
select tt.t('C8 card fee 7.20 of S1 is in the branch P&L (fee field = 7.2)',
  exists (select 1 from _p27_pl(tt.today(), tt.today(), array[2]) p, jsonb_each_text(to_jsonb(p)) e where e.key ilike '%fee%' and e.value ~ '^-?[0-9.]+$' and abs(e.value::numeric - 7.2) < 0.01)
  or exists (select 1 from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[2], '{}'::jsonb) x, jsonb_each_text(x) e where e.key ilike '%fee%' and e.value ~ '^-?[0-9.]+$' and abs(e.value::numeric - 7.2) < 0.01));
-- C10 / G5: revenue with unknown cost (item C, 200) is not counted as 100 % margin in the S1 profit
select tt.t('C10 S1 profit is NULL or split into costed-only / unknown-revenue when an item has no cost',
  exists (select 1 from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[2], '{}'::jsonb) x
          where coalesce(x->>'row_type','') <> 'cost_share' and (x->>'profit' is null or exists (select 1 from jsonb_object_keys(x) k where k ilike '%costed_only%' or k ilike '%unknown_rev%' or k ilike '%profit_known%'))));
-- C6 / G6: cost attribution inside the P&L is ON by default
select tt.t('C6 rule cost_attrib_in_pl default value is ON (shares are part of the P&L by default)', (select default_value from rules where key='cost_attrib_in_pl') = 'true'::jsonb);
-- C5 / G10: factory salary is not charged twice (typed recipe labour in product cost AND salary in the factory branch P&L)
select tt.t('C5 factory salary 200 is not also a factory branch loss while labour is already in product cost',
  coalesce((select o_sal from _p27_pl(tt.today(), tt.today(), array[6]) limit 1),0) = 0);
-- C15 / G8: shares of a monthly bill are pro-rated by days of the range
select tt.t('C15 cost shares of a one-day report are smaller than the whole-month shares (pro-rated)',
  (select coalesce(sum((x->>'expenses')::numeric),0) from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[1,2,3,6], '{}'::jsonb) x where x->>'row_type'='cost_share')
  < (select coalesce(sum((x->>'expenses')::numeric),0) from _r3q_l3_shop_pnl(date_trunc('month',tt.today())::date, (date_trunc('month',tt.today())+interval '1 month - 1 day')::date, array[1,2,3,6], '{}'::jsonb) x where x->>'row_type'='cost_share'));
-- C12 / G9: returns are netted in product sales (biz_items revenue == biz_daily revenue)
select tt.t('C12 sum of product revenue (biz_items) equals branch revenue (biz_daily): returns netted',
  abs((select sum(revenue) from biz_items(tt.today(), tt.today(), null)) - (select sum(revenue) from biz_daily(tt.today(), tt.today(), null))) < 0.01);
-- C16 / G11: sales-share allocation method is offered
select tt.t('C16 [NS] cost_rule_save accepts the method sales_share',
  tt.try(format($q$select cost_rule_save(%s,'sales_share',date_trunc('month',tt.today())::date,'[{"location_id":2,"dest":"showroom"},{"location_id":3,"dest":"showroom"}]'::jsonb,'x',gen_random_uuid())$q$, :'es')));
-- C19 / G13: contribution margin exists
select tt.t('C19 [NS] a contribution-margin function or measure exists', exists (select 1 from pg_proc where proname ilike '%contribution%'));
-- C25 / G15: delivery charge is part of sales/P&L
select tt.t('C25 [NS] delivery charge/cost is read by the P&L or the books posting',
  exists (select 1 from pg_proc where proname in ('_p27_pl','_r3q_l3_shop_pnl','_acct_docs','biz_daily') and prosrc ilike '%delivery_charge%'));
-- C26 / G14: head "rent" has its own account (not 5900 other expenses)
select tt.t('C26 quick expense of head rent (150) is not booked to 5900 Other expenses',
  not exists (select 1 from jsonb_array_elements(acct_income_statement(tt.today(), tt.today(), 2)->'expense') x join coa_accounts a on a.id=(x->>'id')::bigint where a.code='5900' and (x->>'amount')::numeric >= 150));
