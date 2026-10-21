-- FRESH DB ONLY. Phase 415 tests: the owner setting for the value of goods moved between units (package RPT-B4, R9a).
--   Build a database through phase 99, paste supabase/phase404.sql and phase415.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase415_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql (RB4-FG sells at 200). Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\set ON_ERROR_STOP off

\echo == T0 settings
select tt.chk('T0 the basis setting exists, is a choice with none as the default; the percentage is a number and BLANK', (select kind = 'choice' and default_value = '"none"'::jsonb and choices @> '["none","cost","price_pct"]'::jsonb from rules where key = 'transfer_valuation_basis')
  and (select kind = 'number' and default_value is null from rules where key = 'transfer_price_pct'));
select tt.chk('T0 as shipped, the basis in force is none', public.rule_txt('transfer_valuation_basis') is null or public.rule_txt('transfer_valuation_basis') = 'none');
select tt.chk('T0 the value function is closed to browsers', not has_function_privilege('authenticated','public._rb4_transfer_value(uuid,numeric,numeric,text,numeric)','execute'));

\echo == T1 the value of a transfer line
select tt.chk('T1 default (none): no value, state not_valued', (select state = 'not_valued' and value is null from public._rb4_transfer_value(:'i_fg'::uuid, 10, 60)));
select tt.chk('T1 cost: 10 x 60 = 600.00, state at_cost', (select state = 'at_cost' and value = 600 from public._rb4_transfer_value(:'i_fg'::uuid, 10, 60, 'cost')));
select tt.chk('T1 cost with an unknown cost: no value, cost_not_captured (never 0)', (select state = 'cost_not_captured' and value is null from public._rb4_transfer_value(:'i_fg'::uuid, 10, null, 'cost')) and (select state = 'cost_not_captured' from public._rb4_transfer_value(:'i_fg'::uuid, 10, 0, 'cost')));
select tt.chk('T1 price_pct 50 on a selling price of 200: 3 x 200 x 50 % = 300.00', (select state = 'pct_of_price' and value = 300 from public._rb4_transfer_value(:'i_fg'::uuid, 3, 60, 'price_pct', 50)));
select tt.chk('T1 price_pct with the percentage blank: no value, pct_not_set', (select state = 'pct_not_set' and value is null from public._rb4_transfer_value(:'i_fg'::uuid, 3, 60, 'price_pct', null)));
select tt.chk('T1 price_pct for an item with no selling price: no value, price_not_captured', (select state = 'price_not_captured' and value is null from public._rb4_transfer_value(:'i_rm'::uuid, 3, 60, 'price_pct', 50)));
update rules set value = '"cost"'::jsonb where key = 'transfer_valuation_basis';
select tt.chk('T1 the owner switches the basis on: the function follows the setting', (select state = 'at_cost' and value = 600 from public._rb4_transfer_value(:'i_fg'::uuid, 10, 60)));
update rules set value = '"price_pct"'::jsonb where key = 'transfer_valuation_basis';
select tt.chk('T1 price_pct without the percentage set stays "not valued" (a blank number blocks it)', (select state = 'pct_not_set' from public._rb4_transfer_value(:'i_fg'::uuid, 10, 60)));
update rules set value = '70'::jsonb where key = 'transfer_price_pct';
select tt.chk('T1 with 70 %: 10 x 200 x 70 % = 1400.00', (select value = 1400 from public._rb4_transfer_value(:'i_fg'::uuid, 10, 60)));

\echo == T2 paste twice
\ir phase415.sql
select tt.chk('T2 pasting the file again leaves the owner''s values alone', (select value = '"price_pct"'::jsonb from rules where key = 'transfer_valuation_basis') and (select value = '70'::jsonb from rules where key = 'transfer_price_pct'));

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
