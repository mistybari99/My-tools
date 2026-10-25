-- FRESH DB ONLY. Phase 308 tests (CRM-C: overview and repeat rate, RFM lists, lapsed and at-risk, customer value card, customer profit view, export).
--   build: phases 8..98, 306, 307, 308; run: psql -h /tmp -p 5573 -U postgres -d <db> -qAt -f supabase/phase308_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names, tests/sql/crmc_fixture.sql). Expected numbers are hand-computed from the fixture (comments above each block).
\set ON_ERROR_STOP off
\ir ../tests/sql/crmc_fixture.sql
truncate tt.res;
create or replace function tt.snap() returns text language plpgsql security definer as $$
declare r text := ''; t text;
begin
  foreach t in array array['sales','sale_payments','sale_returns','customers','journal_entries','journal_lines','customer_points_ledger','notify_optin','stock_ledger','item_costs','items'] loop
    execute format('select md5(coalesce(string_agg(x::text, '''' order by x::text), '''')) from public.%I x', t) into t;
    r := r || t;
  end loop;
  return md5(r);
end $$;
create or replace function tt.err_role(p_name text, p_role text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute format('set local role %I', p_role); execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
grant execute on function tt.snap(), tt.err_role(text, text, text, text) to authenticated, anon;
select tt.today() as t \gset
select tt.snap() as snap0 \gset
select tt.as(:'u_o');
select crmc_metrics_refresh(false) ->> 'processed' as p \gset
select tt.chk('T0 setup: seven customers scored', :p = 7);

\echo == T0 shape and rights
select tt.chk('T0 phase308 functions exist; the page builder and the export log are closed; screen functions open to signed-in users only',
  to_regprocedure('public.crmc_overview(integer)') is not null and not has_function_privilege('authenticated', 'public._crmc_page(uuid[],text,int,int)', 'execute')
  and not has_table_privilege('authenticated', 'public.crmc_export_log', 'select') and has_function_privilege('authenticated', 'public.crmc_profit(date,date,text,int,int)', 'execute')
  and not has_function_privilege('anon', 'public.crmc_export(uuid,bigint,jsonb,text,text[])', 'execute') and not has_function_privilege('anon', 'public.crmc_overview(integer)', 'execute'));
select tt.chk('T0 nothing in a money table is written by this phase file: it only reads (no insert/update/delete on sales, payments, returns, journal in any crmc function source)',
  not exists (select 1 from pg_proc where proname like '%crmc%' and prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?(sales|sale_payments|sale_returns|journal_entries|journal_lines|items|item_costs|stock_ledger|customers)\M'));

\echo == T1 who may read what
set role authenticated;
select tt.as(:'u_c');
select tt.err('T1 cashier: overview', $$select crmc_overview()$$, 'not allowed');
select tt.err('T1 cashier: rfm summary', $$select crmc_rfm_summary()$$, 'not allowed');
select tt.err('T1 cashier: rfm list', $$select crmc_rfm_list('Champion')$$, 'not allowed');
select tt.err('T1 cashier: value list', $$select crmc_value_list()$$, 'not allowed');
select tt.err('T1 cashier: lapsed', $$select crmc_lapsed(60)$$, 'not allowed');
select tt.err('T1 cashier: profit', $$select crmc_profit(current_date - 30, current_date)$$, 'not allowed');
select tt.err('T1 cashier: export', $$select crmc_export(null, null, '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}', 'test reason')$$, 'not allowed');
select tt.as(:'u_v');
select tt.chk('T1 viewer: overview works', (crmc_overview()->>'total_customers')::int = 7);
select tt.as(:'u_n');
select tt.chk('T1 crm_view without the cost right can read the overview', (crmc_overview()->>'total_customers')::int = 7);
select tt.err('T1 crm_view without the cost right: profit refused', $$select crmc_profit(current_date - 30, current_date)$$, 'not allowed');
select tt.as(:'u_v');
select tt.err('T1 viewer: export needs the export right', $$select crmc_export(null, null, '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}', 'test reason')$$, 'not allowed');
select tt.err('T1 viewer: the export log is for exporters', $$select crmc_export_log_list()$$, 'not allowed');
select tt.as(:'u_k');
select tt.chk('T1 crm_view + view_cost: profit works', (crmc_profit(tt.today() - 30, tt.today())->>'customers')::int = 3);
reset role;
select tt.err_role('T1 anonymous: no execute right on overview', 'anon', $$select public.crmc_overview()$$, 'permission denied');
select tt.as(:'u_o');

\echo == T2 overview (6 buyers: champ 3 orders 600, atrisk 2 orders 350 net, onetime 1/80, old 1/500 a year ago, void-customer 1/60, due 1/1000; never has no order)
select tt.chk('T2 counts: 7 scored, 6 buyers, 2 repeat buyers (champ, atrisk) = 33.3 percent',
  (select (r->>'customers_scored')::int = 7 and (r->>'buyers')::int = 6 and (r->>'repeat_buyers')::int = 2 and (r->>'repeat_rate_pct')::numeric = 33.3 from (select crmc_overview() r) z));
select tt.chk('T2 12 months: 5 active, 2 repeat = 40.0 percent, 5 new (old customer started a year ago)',
  (select (r->>'active_12m')::int = 5 and (r->>'repeat_12m')::int = 2 and (r->>'repeat_rate_12m_pct')::numeric = 40.0 and (r->>'new_12m')::int = 5 from (select crmc_overview() r) z));
select tt.chk('T2 value: average 431.67 (2590 / 6), median 425 ((350+500)/2), average orders 1.50, 12-month spend 2090, top tenth holds 38.6 percent (1000 of 2590)',
  (select (r->>'avg_lifetime_value')::numeric = 431.67 and (r->>'median_lifetime_value')::numeric = 425 and (r->>'avg_orders')::numeric = 1.5 and (r->>'spend_12m')::numeric = 2090 and (r->>'top_tenth_share_pct')::numeric = 38.6 from (select crmc_overview() r) z));
select tt.chk('T2 owing: 1 customer, 600; at risk 1; lapsed not shown while the days setting is blank; labels counted',
  (select (r->>'owing_customers')::int = 1 and (r->>'owed_total')::numeric = 600 and (r->>'at_risk')::int = 1 and r->'lapsed' = 'null'::jsonb
     and r->'by_label' = '{"Champion":1,"At-risk":1,"One-time":3,"Inactive":1,"No purchases":1}'::jsonb and (r->>'unscored_customers')::int = 0 and r->>'mode' = 'standard' from (select crmc_overview() r) z));
select tt.chk('T2 by outlet 2 (customers whose main outlet is 2: onetime, void): 2 buyers, no repeat = 0.0', (select (r->>'buyers')::int = 2 and (r->>'repeat_rate_pct')::numeric = 0.0 from (select crmc_overview(2) r) z));
select tt.chk('T2 by outlet 1 (champ, atrisk, due): 3 buyers, 2 repeat = 66.7', (select (r->>'buyers')::int = 3 and (r->>'repeat_rate_pct')::numeric = 66.7 from (select crmc_overview(1) r) z));
select tt.err('T2 outlet 0 refused', $$select crmc_overview(0)$$, 'bad_value');
set role authenticated; select set_rule('crm_winback_days', '60'::jsonb); reset role;
select tt.chk('T2 with the days setting at 60: lapsed = atrisk (90) and old (400) = 2', (crmc_overview()->>'lapsed')::int = 2);

\echo == T3 RFM summary and lists
select tt.chk('T3 summary: standard mode, 7 customers, One-time 3 = 42.9 percent, explained in words', (select r->>'mode' = 'standard' and (r->>'customers_scored')::int = 7
  and (select (l->>'customers')::int = 3 and (l->>'share_pct')::numeric = 42.9 from jsonb_array_elements(r->'labels') l where l->>'label' = 'One-time') and r->>'explain' like 'Standard labels%' from (select crmc_rfm_summary() r) z));
select tt.chk('T3 list Champion: 1 customer, the champ, with top items', (select (r->>'total')::int = 1 and r->'rows' -> 0 ->> 'name' = 'test_cust_champ' and jsonb_array_length(r->'rows' -> 0 -> 'top_items') = 2 from (select crmc_rfm_list('Champion') r) z));
select tt.chk('T3 list One-time sorted by last-12-month spend: due, onetime, void', (select string_agg(x ->> 'name', ',' order by o) = 'test_cust_due,test_cust_onetime,test_cust_void' from (select crmc_rfm_list('One-time', 'last12m') r) z, jsonb_array_elements(z.r->'rows') with ordinality t(x, o)));
select tt.err('T3 unknown label refused', $$select crmc_rfm_list('Hacker')$$, 'bad_value');
select tt.err('T3 unknown sort refused', $$select crmc_rfm_list('Champion', 'name; drop table customers')$$, 'bad_value');
set role authenticated; select set_rule('crm_rfm_recent_days', '30'::jsonb), set_rule('crm_rfm_frequency_min', '2'::jsonb), set_rule('crm_rfm_spend_min', '400'::jsonb); reset role;
select tt.chk('T3 owner cut-offs: the summary says so in words and counts At risk (atrisk), Drifting (onetime), Lost (old), New (void), Big spender (due), Champion (champ)',
  (select r->>'mode' = 'owner' and r->>'explain' like 'Recent = bought within 30 days. Frequent = at least 2 orders%' and
     (select jsonb_object_agg(l->>'label', (l->>'customers')::int) from jsonb_array_elements(r->'labels') l) = '{"At risk":1,"Drifting":1,"Lost":1,"New":1,"Big spender":1,"Champion":1,"No purchases":1}'::jsonb from (select crmc_rfm_summary() r) z));
select tt.chk('T3 the overview follows: at risk 1, owner mode', (select (r->>'at_risk')::int = 1 and r->>'mode' = 'owner' from (select crmc_overview() r) z));
select set_rule('crm_rfm_recent_days', null), set_rule('crm_rfm_frequency_min', null), set_rule('crm_rfm_spend_min', null);

\echo == T4 biggest customers
select tt.chk('T4 by lifetime value: due 1000, champ 600, old 500, atrisk 350, onetime 80, void 60; 6 in total (never has no order)',
  (select r->>'total' = '6' and (select string_agg(x ->> 'name', ',' order by o) from jsonb_array_elements(r->'rows') with ordinality t(x, o)) = 'test_cust_due,test_cust_champ,test_cust_old,test_cust_atrisk,test_cust_onetime,test_cust_void'
     from (select crmc_value_list() r) z));
select tt.chk('T4 by orders: champ first; by silence: old (400 days) first; by amount owed: due first',
  (select crmc_value_list('orders') -> 'rows' -> 0 ->> 'name') = 'test_cust_champ' and (select crmc_value_list('silent_longest') -> 'rows' -> 0 ->> 'name') = 'test_cust_old' and (select crmc_value_list('due') -> 'rows' -> 0 ->> 'name') = 'test_cust_due');
select tt.err('T4 unknown sort refused', $$select crmc_value_list('x')$$, 'bad_value');
select tt.chk('T4 paging: limit 2 offset 4 = onetime, void', (select (select string_agg(x ->> 'name', ',' order by o) from jsonb_array_elements(r->'rows') with ordinality t(x, o)) = 'test_cust_onetime,test_cust_void' from (select crmc_value_list('lifetime', 2, 4) r) z));

\echo == T5 lapsed and at-risk
set role authenticated; select set_rule('crm_winback_days', null); reset role;
select tt.err('T5 days blank and not given: asked to set it first', $$select crmc_lapsed()$$, 'set_winback_days');
select tt.chk('T5 not seen for 60 days: old (500) then atrisk (350), most valuable first', (select (r->>'total')::int = 2 and (select string_agg(x ->> 'name', ',' order by o) from jsonb_array_elements(r->'rows') with ordinality t(x, o)) = 'test_cust_old,test_cust_atrisk' and (r->>'days')::int = 60 from (select crmc_lapsed(60) r) z));
select tt.chk('T5 not seen for 30 days adds onetime (40 days)', (crmc_lapsed(30)->>'total')::int = 3);
select tt.err('T5 0 days refused', $$select crmc_lapsed(0)$$, 'bad_value');
select tt.err('T5 unknown kind refused', $$select crmc_lapsed(60, 'x')$$, 'bad_value');
set role authenticated; select set_rule('crm_winback_days', '60'::jsonb); reset role;
select tt.chk('T5 with the days setting at 60 the call needs no number', (crmc_lapsed()->>'total')::int = 2);
select tt.chk('T5 at risk (standard label At-risk): the atrisk customer only', (select (r->>'total')::int = 1 and r->'rows' -> 0 ->> 'name' = 'test_cust_atrisk' from (select crmc_lapsed(null, 'at_risk') r) z));
select tt.chk('T5 a customer who never bought is never "lapsed"', not exists (select 1 from jsonb_array_elements(crmc_lapsed(1, 'lapsed', 200) -> 'rows') x where x ->> 'name' = 'test_cust_never'));

\echo == T6 one customer value card
set role authenticated; select tt.as(:'u_c');
select tt.chk('T6 a counter user (POS) can read the card: label Champion, 3 orders, 600', (select r->>'label' = 'Champion' and (r->>'orders_total')::int = 3 and (r->>'lifetime_spend')::numeric = 600 and (r->>'scored')::boolean from (select crmc_customer_value('00000000-0000-0000-0000-00000000c3a1') r) z));
select tt.chk('T6 a customer without a score row (inactive) = scored false', crmc_customer_value('00000000-0000-0000-0000-00000000c3a7') = '{"scored": false}'::jsonb);
select tt.chk('T6 an unknown id = scored false', crmc_customer_value('00000000-0000-0000-0000-00000000ffff') = '{"scored": false}'::jsonb);
reset role; select tt.as(:'u_o');

\echo == T7 customer profit (window = last 30 days; cost of item a is 40, item b has no cost anywhere)
-- champ: sales 100 + 200 + 300 = 600; costed = item a lines 100 (ledger 2 x 40 = 80) + 120 (ledger 3 x 40 = 120) = 220, cogs 200, margin 20 (9.1 percent), unknown (item b) 80 + 300 = 380
-- due: 1000 of item a, no ledger -> cost book 10 x 40 = 400, margin 600 (60.0 percent); void-customer: 60 item b unknown
-- walk-in sale of 70 (item a, cost 40) is in the totals but not in any customer row: all revenue 1730 = 600 + 1000 + 60 + 70, customers 1660
select crmc_profit(:'t'::date - 30, :'t'::date) as pr \gset
select tt.chk('T7 three customers, ranked by margin: due 600, champ 20, void 0', (select (r->>'customers')::int = 3 and (select string_agg(x ->> 'name', ',' order by o) from jsonb_array_elements(r->'rows') with ordinality t(x, o)) = 'test_cust_due,test_cust_champ,test_cust_void'
  from (select :'pr'::jsonb r) z));
select tt.chk('T7 due: revenue 1000, costed 1000, cogs 400, margin 600, 60.0 percent, cost complete',
  (select (x->>'revenue')::numeric = 1000 and (x->>'costed_revenue')::numeric = 1000 and (x->>'cogs')::numeric = 400 and (x->>'margin')::numeric = 600 and (x->>'margin_pct')::numeric = 60.0 and not (x->>'cost_partial')::boolean
     from jsonb_array_elements(:'pr'::jsonb -> 'rows') x where x->>'name' = 'test_cust_due'));
select tt.chk('T7 champ: revenue 600, costed 220, cogs 200, margin 20, 9.1 percent, unknown-cost revenue 380 shown apart and flagged partial',
  (select (x->>'revenue')::numeric = 600 and (x->>'costed_revenue')::numeric = 220 and (x->>'cogs')::numeric = 200 and (x->>'margin')::numeric = 20 and (x->>'margin_pct')::numeric = 9.1 and (x->>'unknown_cost_revenue')::numeric = 380 and (x->>'cost_partial')::boolean
     from jsonb_array_elements(:'pr'::jsonb -> 'rows') x where x->>'name' = 'test_cust_champ'));
select tt.chk('T7 void-customer: revenue 60, nothing costed, margin 0, percent empty (never guessed), unknown 60',
  (select (x->>'revenue')::numeric = 60 and (x->>'costed_revenue')::numeric = 0 and (x->>'margin')::numeric = 0 and x->'margin_pct' = 'null'::jsonb and (x->>'unknown_cost_revenue')::numeric = 60
     from jsonb_array_elements(:'pr'::jsonb -> 'rows') x where x->>'name' = 'test_cust_void'));
select tt.chk('T7 totals: all revenue 1730, attributed to customers 1660', (:'pr'::jsonb ->> 'all_revenue')::numeric = 1730 and (:'pr'::jsonb ->> 'customer_revenue')::numeric = 1660);
select tt.chk('T7 same cost source as the Profit report: the cost of goods of the customers + the walk-in sale (40) = the daily profit report cogs for the same days',
  (select sum((x->>'cogs')::numeric) from jsonb_array_elements(:'pr'::jsonb -> 'rows') x) + 40 = (select sum(cogs) from biz_daily(:'t'::date - 30, :'t'::date, null)));
select tt.chk('T7 120 days with the return netted: at-risk revenue 150 + 250 - 50 = 350, costed 150, cogs 40, margin 110 (73.3 percent), unknown 250 - 50 = 200',
  (select (x->>'revenue')::numeric = 350 and (x->>'costed_revenue')::numeric = 150 and (x->>'cogs')::numeric = 40 and (x->>'margin')::numeric = 110 and (x->>'margin_pct')::numeric = 73.3 and (x->>'unknown_cost_revenue')::numeric = 200
     from jsonb_array_elements(crmc_profit(:'t'::date - 120, :'t'::date) -> 'rows') x where x->>'name' = 'test_cust_atrisk'));
select tt.chk('T7 paging: limit 1 offset 1 = champ', (crmc_profit(:'t'::date - 30, :'t'::date, 'margin', 1, 1) -> 'rows' -> 0 ->> 'name') = 'test_cust_champ');
select tt.chk('T7 sort by revenue puts due first, champ second', (crmc_profit(:'t'::date - 30, :'t'::date, 'revenue') -> 'rows' -> 1 ->> 'name') = 'test_cust_champ');
select tt.err('T7 range over 400 days refused', format($$select crmc_profit('%s', '%s')$$, :'t'::date - 401, :'t'::date), 'bad_range');
select tt.err('T7 end before start refused', format($$select crmc_profit('%s', '%s')$$, :'t'::date, :'t'::date - 1), 'bad_range');
select tt.err('T7 null dates refused', $$select crmc_profit(null, null)$$, 'bad_range');
select tt.err('T7 unknown sort refused', format($$select crmc_profit('%s', '%s', 'name; drop')$$, :'t'::date - 30, :'t'::date), 'bad_value');
select tt.chk('T7 an empty period gives an empty list', (crmc_profit(:'t'::date - 650, :'t'::date - 600) ->> 'customers')::int = 0);

\echo == T8 export (off by default)
select tt.err('T8 default OFF: refused even for the owner', $$select crmc_export(null, null, '{"conditions":[{"field":"orders_total","op":"ge","value":0}]}', 'test reason')$$, 'export_off');
set role authenticated; select set_rule('crm_seg_export_on', 'true'::jsonb); reset role;
select tt.err('T8 ON but the row limit is blank: still blocked', $$select crmc_export(null, null, '{"conditions":[{"field":"orders_total","op":"ge","value":0}]}', 'test reason')$$, 'set_export_max_rows');
set role authenticated; select set_rule('crm_seg_export_max_rows', '5'::jsonb); reset role;
select tt.err('T8 no reason: refused', $$select crmc_export(null, null, '{"conditions":[{"field":"orders_total","op":"ge","value":0}]}', ' x ')$$, 'reason_required');
select tt.err('T8 7 customers over a limit of 5: refused with the size, never cut short', $$select crmc_export(null, null, '{"conditions":[{"field":"orders_total","op":"ge","value":0}]}', 'test reason')$$, 'over_export_cap:7');
select tt.err('T8 empty list: refused', $$select crmc_export(null, null, '{"conditions":[{"field":"tier","op":"in","value":["elite"]}]}', 'test reason')$$, 'empty_segment');
select tt.err('T8 rule and list both missing', $$select crmc_export(null, null, null, 'test reason')$$, 'bad_value');
select tt.err('T8 a bad rule is refused with the reason', $$select crmc_export(null, null, '{"conditions":[{"field":"x","op":"ge","value":1}]}', 'test reason')$$, 'bad_rule:unknown_field');
select tt.err('T8 a column that is not exportable (address)', $$select crmc_export(null, null, '{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}', 'test reason', array['name','address'])$$, 'bad_value');
select tt.err('T8 the same column twice', $$select crmc_export(null, null, '{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}', 'test reason', array['name','name'])$$, 'bad_value');
select tt.chk('T8 nothing was logged by the refused attempts', (select count(*) from crmc_export_log) = 0);
set role authenticated; select tt.as(:'u_x');
select crmc_export('c0000000-0000-0000-0000-0000000000e1', null, '{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}', 'test: win-back call list') as ex \gset
reset role;
select tt.chk('T8 exporter (crm_export + crm_view): 3 rows (atrisk, old, onetime) in name order, all 11 columns, the phone is masked because the exporter may not see full numbers',
  (select (r->>'total')::int = 3 and jsonb_array_length(r->'columns') = 11 and (r->>'mobile_masked')::boolean and r->'rows' -> 0 ->> 1 ~ '^017\*+\d\d$' and r->'rows' -> 0 ->> 0 = 'test_cust_atrisk' and r->'rows' -> 2 ->> 0 = 'test_cust_onetime'
     and position('01700000002' in r::text) = 0 from (select :'ex'::jsonb r) z));
select tt.chk('T8 consent columns: onetime has a whatsapp opt-in and no sms opt-in; atrisk opted out of sms so false', (select r->'rows' -> 2 ->> 8 = 'false' and r->'rows' -> 2 ->> 9 = 'true' and r->'rows' -> 0 ->> 8 = 'false' and r->'rows' -> 0 ->> 10 = 'false' from (select :'ex'::jsonb r) z));
select tt.chk('T8 no address, birthday or note anywhere in the answer', position('address' in :'ex') = 0 and position('birthday' in :'ex') = 0 and position('note' in :'ex') = 0);
select tt.chk('T8 one log line: who, rows 3, reason, columns, phone not full; one audit line', (select count(*) from crmc_export_log where rows = 3 and reason = 'test: win-back call list' and not mobile_full and by_user = :'u_x'::uuid and array_length(columns, 1) = 11) = 1
  and (select count(*) from audit_log where action = 'crm_list_export') = 1);
set role authenticated; select tt.as(:'u_x');
select tt.chk('T8 same client id again: nothing new, marked repeat', (crmc_export('c0000000-0000-0000-0000-0000000000e1', null, '{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}', 'test: again')->>'repeat')::boolean);
select tt.chk('T8 exporter reads the log', jsonb_array_length(crmc_export_log_list()) = 1);
select tt.chk('T8 choosing columns: name and tier only, 2 cells per row', (select jsonb_array_length(r->'rows' -> 0) = 2 and r->'columns' = '["name","tier"]'::jsonb from (select crmc_export(null, null, '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}', 'test: two columns', array['name','tier']) r) z));
select tt.as(:'u_e');
select tt.err('T8 an editor without the export right: refused', $$select crmc_export(null, null, '{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}', 'test reason')$$, 'not allowed');
select tt.as(:'u_d');
select tt.err('T8 holder of crm_contact_view without the export right: refused', $$select crmc_export(null, null, '{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}', 'test reason')$$, 'not allowed');
reset role; select tt.as(:'u_o');
select crmc_export(null, null, '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}', 'test: owner export') as exo \gset
select tt.chk('T8 owner export has the full number', (select r->'rows' -> 0 ->> 1 = '01700000001' and not (r->>'mobile_masked')::boolean from (select :'exo'::jsonb r) z) and exists (select 1 from crmc_export_log where reason = 'test: owner export' and mobile_full));
select tt.err('T8 the export log cannot be changed', $$update crmc_export_log set reason = 'x'$$, 'crmc_append_only');
select tt.err('T8 the export log cannot be deleted', $$delete from crmc_export_log$$, 'crmc_append_only');
set role authenticated; select set_rule('crm_seg_export_on', 'false'::jsonb); reset role;
select tt.err('T8 switched OFF again: refused', $$select crmc_export(null, null, '{"conditions":[{"field":"tier","op":"in","value":["gold"]}]}', 'test reason')$$, 'export_off');

\echo == T9 existing data untouched by every read in this file
select tt.chk('T9 sales, payments, returns, customers, journal, points, opt-in, stock ledger, items and costs are byte for byte as before', tt.snap() = :'snap0');

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
