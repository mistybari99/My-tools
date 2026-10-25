-- FRESH DB ONLY. Phase 401 tests: R2 "data not captured" notices (package RPT-B1).
--   Build a database through phase 99, paste supabase/phase400.sql and supabase/phase401.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase401_test.sql | grep -E 'FAIL|RESULT'
-- The data comes from tests/sql/rptb1_fixture.sql and rptb1_fixture2.sql (hand-computed numbers in their headers). The hooks (docs/integration/RPT-B1_hooks.sql) are installed by THIS file after the
-- "before" snapshot, exactly as the integrator will (section 3 of the hooks file is skipped here: phase 402 is not pasted). Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rptb1_fixture.sql
\ir ../tests/sql/rptb1_fixture2.sql
\set ON_ERROR_STOP off
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create table if not exists tt.snap (phase text, k text, j jsonb);
truncate tt.snap;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.omit(j jsonb, keys text[]) returns jsonb language sql immutable as $$
  select case when j is null then null else (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) from jsonb_each(j) e where e.key <> all (keys)) end $$;
create or replace function tt.rows(j jsonb) returns setof jsonb language sql immutable as $$ select e from jsonb_array_elements(j -> 'rows') e $$;
create or replace function tt.has_note(p_j jsonb, p_code text) returns boolean language sql immutable as $$ select exists (select 1 from jsonb_array_elements(p_j -> 'notes') n where n ->> 'code' = p_code) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
select tt.today() as td \gset
select (:'td'::date - 6) as d1 \gset

-- the engine-3 reports, taken as the owner for the last 7 days
create or replace function tt.e3(p_key text) returns jsonb language sql as $$ select public.report_run2(p_key, '{"preset":"last_7"}'::jsonb) $$;
create or replace function tt.snapshot(p_phase text) returns void language plpgsql as $$
declare k text;
begin
  foreach k in array array['f1_production', 'f2_yield', 'f3_raw_vs_recipe', 'l1_pnl', 'l2_margin', 'l3_shop_pnl', 'k2_count_variance', 'k3_store_ledger', 'q3_complaints', 's10_orders', 'x5_staff_trend'] loop
    insert into tt.snap values (p_phase, k, tt.e3(k));
  end loop;
  insert into tt.snap values (p_phase, 'prc', public.production_run_costs(1, current_date - 30, current_date + 1));
end $$;

\echo == T0 shape
select tt.chk('T0 phase401 present; the f3 report gets the status column', to_regprocedure('public._rptb1_p401_present()') is not null
  and exists (select 1 from report_defs3 where key = 'f3_raw_vs_recipe' and cols::text like '%actual_status%'));
select tt.chk('T0 no engine-3 hook is installed yet', not exists (select 1 from jsonb_each_text(public._rptb1_hooked401()) where value = 'true'));
select tt.chk('T0 internals are closed to browsers and anon', not has_function_privilege('authenticated','public._rptb1_loss_gaps(date,date,integer)','execute') and not has_function_privilege('authenticated','public._rptb1_r3_notes(text,date,date,integer[],jsonb)','execute')
  and not has_function_privilege('authenticated','public._rptb1_loss_rows(date,date,integer[])','execute') and not has_function_privilege('anon','public._rptb1_loss_summary(date,date,integer[])','execute'));
select tt.chk('T0 the f3 column is added once (pasting phase401 again does not add it twice)', (select jsonb_array_length(cols) from report_defs3 where key = 'f3_raw_vs_recipe') = (select jsonb_array_length(cols) from report_defs3 where key = 'f3_raw_vs_recipe'));

\echo == T1 BEFORE the hooks: the findings of the audit are reproduced (D3, D4, D5, D6)
select tt.as(:'o');
select tt.snapshot('before');
select tt.chk('T1 D4: raw material "actually issued" equals the recipe (10 = 10) and the difference is 0.00 %', (select (r ->> 'actual')::numeric = (r ->> 'expected')::numeric and (r ->> 'diff_pct')::numeric = 0 from tt.rows((select j from tt.snap where phase = 'before' and k = 'f3_raw_vs_recipe')) r limit 1));
select tt.chk('T1 D6: both runs show conversion cost 0 with mode off and "complete"', (select bool_and((e ->> 'conversion_cost')::numeric = 0 and e ->> 'conversion_mode' = 'off' and (e ->> 'conversion_complete')::boolean) from jsonb_array_elements((select j from tt.snap where phase = 'before' and k = 'prc')) e));
select tt.chk('T1 D5: the run without a typed yield shows actual cost = standard cost', (select (e ->> 'actual_cost')::numeric = (e ->> 'std_cost')::numeric from jsonb_array_elements((select j from tt.snap where phase = 'before' and k = 'prc')) e where e -> 'yield_actual' = 'null'::jsonb limit 1));
select tt.chk('T1 D3: the branch profit gaps column says nothing about the 60 of wastage', not exists (select 1 from tt.rows((select j from tt.snap where phase = 'before' and k = 'l1_pnl')) r where r ->> 'gaps' like '%wastage%'));

\echo == T2 install the hooks
\ir ../docs/integration/RPT-B1_hooks.sql
select tt.chk('T2 the five engine-3 hook sites carry the marker; section 3 (phase 402) was skipped', (select bool_and(value::boolean) from jsonb_each_text(public._rptb1_hooked401())) and (select count(*) from jsonb_each_text(public._rptb1_hooked401())) = 5
  and to_regprocedure('public._rptb1_p402_present()') is null);
select md5(pg_get_functiondef('public._r3q_f3_raw_vs_recipe(date,date,integer[],jsonb)'::regprocedure) || pg_get_functiondef('public._r3q_l1_pnl(date,date,integer[],jsonb)'::regprocedure) || pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)'::regprocedure)
  || pg_get_functiondef('public.report_run3(text,jsonb,text,text,integer)'::regprocedure) || pg_get_functiondef('public.production_run_costs(integer,date,date)'::regprocedure)) as h1 \gset
\ir ../docs/integration/RPT-B1_hooks.sql
select tt.chk('T2 pasting the hooks again changes nothing', md5(pg_get_functiondef('public._r3q_f3_raw_vs_recipe(date,date,integer[],jsonb)'::regprocedure) || pg_get_functiondef('public._r3q_l1_pnl(date,date,integer[],jsonb)'::regprocedure) || pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)'::regprocedure)
  || pg_get_functiondef('public.report_run3(text,jsonb,text,text,integer)'::regprocedure) || pg_get_functiondef('public.production_run_costs(integer,date,date)'::regprocedure)) = :'h1');
select tt.chk('T2 earlier tags survive inside l1 / l3 (bos72, bos78) and report_run3 keeps its own', position('bos72' in pg_get_functiondef('public._r3q_l1_pnl(date,date,integer[],jsonb)'::regprocedure)) > 0 and position('bos78' in pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)'::regprocedure)) > 0);
select tt.as(:'o');
select tt.snapshot('after');

\echo == T3 nothing else changed
select tt.chk('T3 ' || b.k || ' is identical after the hooks (rows, totals, columns)', case
    when b.k = 'prc' then (select coalesce(jsonb_agg(tt.omit(e, array['conversion_cost', 'actual_cost', 'conversion_status', 'actual_status', 'unit_cost_basis']) order by e ->> 'made_at'), '[]') from jsonb_array_elements(a.j) e)
                          = (select coalesce(jsonb_agg(tt.omit(e, array['conversion_cost', 'actual_cost']) order by e ->> 'made_at'), '[]') from jsonb_array_elements(b.j) e)
    when b.k = 'f3_raw_vs_recipe' then (select coalesce(jsonb_agg(tt.omit(e, array['actual', 'diff', 'diff_pct', 'actual_status'])), '[]') from tt.rows(a.j) e) = (select coalesce(jsonb_agg(tt.omit(e, array['actual', 'diff', 'diff_pct'])), '[]') from tt.rows(b.j) e)
    when b.k in ('l1_pnl', 'l3_shop_pnl') then (select coalesce(jsonb_agg(tt.omit(e, array['gaps']) order by e::text), '[]') from tt.rows(a.j) e) = (select coalesce(jsonb_agg(tt.omit(e, array['gaps']) order by e::text), '[]') from tt.rows(b.j) e)
                                                and a.j -> 'totals' is not distinct from b.j -> 'totals'
    else a.j - 'notes' = b.j - 'notes' and a.j -> 'notes' = b.j -> 'notes' end)
  from tt.snap b join tt.snap a on a.k = b.k and a.phase = 'after' where b.phase = 'before' order by b.k;
select tt.chk('T3 the profit of every branch row is the same number before and after (l1 and l3)', (select bool_and(x) from (
    select (select (r ->> 'profit') from tt.rows(a.j) r where r ->> 'location_id' = o ->> 'location_id' and r ->> 'month' is not distinct from o ->> 'month' limit 1) is not distinct from (o ->> 'profit') as x
    from tt.snap b join tt.snap a on a.k = b.k and a.phase = 'after' cross join lateral tt.rows(b.j) o where b.phase = 'before' and b.k in ('l1_pnl', 'l3_shop_pnl')) z));

\echo == T4 F3: raw material used vs recipe
select j as f3a from tt.snap where phase = 'after' and k = 'f3_raw_vs_recipe' \gset
select tt.chk('T4 actual, difference and difference % are EMPTY (not 0) and the line says "not captured"', (select r ->> 'actual' is null and r ->> 'diff' is null and r ->> 'diff_pct' is null and r ->> 'actual_status' = 'not captured' and (r ->> 'expected')::numeric = 10 from tt.rows(:'f3a'::jsonb) r limit 1));
select tt.chk('T4 the note names what is needed (04-2 issue slip linked to the run, or an actual-use entry) in both languages', (select n ->> 'code' = 'not_captured' and n ->> 'text_en' like '%04-2%' and n ->> 'text_bn' like '%০৪-২%' and (n ->> 'lines')::int = 1 from jsonb_array_elements(:'f3a'::jsonb -> 'notes') n where n ->> 'code' = 'not_captured'));
select tt.chk('T4 the column is in the answer', exists (select 1 from jsonb_array_elements(:'f3a'::jsonb -> 'columns') c where c ->> 'key' = 'actual_status'));
-- a real measurement: a movement posted for the batch AFTER the automatic issue (own transaction = later created_at)
select stock_post(:'i_rm'::uuid, 1, -1, 'issue_out', 'production', :'run1', null, null, now(), 'test extra issue', null, 'full') is not null as w_x1 \gset
select tt.e3('f3_raw_vs_recipe') as f3b \gset
select tt.chk('T4 one of two runs measured: still not shown as a measurement, status says "partly (1 of 2 runs)"', (select r ->> 'actual' is null and r ->> 'actual_status' = 'partly (1 of 2 runs)' from tt.rows(:'f3b'::jsonb) r limit 1) and tt.has_note(:'f3b'::jsonb, 'not_captured'));
select stock_post(:'i_rm'::uuid, 1, -1, 'issue_out', 'production', :'run2', null, null, now(), 'test extra issue', null, 'full') is not null as w_x2 \gset
select tt.e3('f3_raw_vs_recipe') as f3c \gset
select tt.chk('T4 both runs measured: actual 10 + 1 + 1 = 12 against 10 per recipe -> difference 2, 20 %, status measured, no note',
  (select (r ->> 'actual')::numeric = 12 and (r ->> 'diff')::numeric = 2 and (r ->> 'diff_pct')::numeric = 20 and r ->> 'actual_status' = 'measured' from tt.rows(:'f3c'::jsonb) r limit 1) and not tt.has_note(:'f3c'::jsonb, 'not_captured'));
select tt.chk('T4 the extra movement is real stock: raw on hand is 200 - 5 - 5 - 3 - 1 - 1 = 185', (select qty from stock_balance where item_id = :'i_rm'::uuid and location_id = 1) = 185);

\echo == T5 L1 / L3: the gaps column names the losses that are left out of the profit
select j as l1a from tt.snap where phase = 'after' and k = 'l1_pnl' \gset
select tt.chk('T5 place 1 gaps: the old words stay, then "wastage (not in profit)"; place 2 (no loss) is unchanged', (select r ->> 'gaps' = 'expenses, salary, fixed, wastage (not in profit)' from tt.rows(:'l1a'::jsonb) r where r ->> 'location_id' = '1')
  and (select r ->> 'gaps' = 'expenses, salary, fixed' from tt.rows(:'l1a'::jsonb) r where r ->> 'location_id' = '2'));
select tt.chk('T5 L3 shows the same words', (select r ->> 'gaps' like '%wastage (not in profit)' from tt.rows((select j from tt.snap where phase = 'after' and k = 'l3_shop_pnl')) r where r ->> 'location_id' = '1'));
select tt.chk('T5 the note gives the amount from the ledger (60.00) in both languages', (select (n -> 'amounts' ->> 'wastage')::numeric = 60 and n ->> 'text_en' like '%wastage 60.00%' and n ->> 'text_bn' like '%অপচয় 60.00%' from jsonb_array_elements(:'l1a'::jsonb -> 'notes') n where n ->> 'code' = 'losses_not_counted'));
-- a count shortage (1 kg x 20) and the names in order
select stock_count_adjust(:'i_rm'::uuid, 1, 184, 'test count') ->> 'ledger_id' as w_cnt \gset
select tt.chk('T5 a count shortage is listed too, in a fixed order (count shrink before wastage)', (select r ->> 'gaps' = 'expenses, salary, fixed, count shrink (not in profit), wastage (not in profit)' from tt.rows(tt.e3('l1_pnl')) r where r ->> 'location_id' = '1'));
select tt.chk('T5 the profit number itself did not move (the losses are only named)', (select (r ->> 'profit')::numeric from tt.rows(tt.e3('l1_pnl')) r where r ->> 'location_id' = '1') = (select (r ->> 'profit')::numeric from tt.rows(:'l1a'::jsonb) r where r ->> 'location_id' = '1'));
-- the owner switches the one profit number ON: the losses are counted, so they are no longer "left out"
select set_rule('profit_one_number_on', 'true') is null as w_on \gset
select tt.chk('T5 master ON: nothing is left out any more (no word in the gaps column, no note), the profit now carries the losses',
  (select r ->> 'gaps' not like '%not in profit%' from tt.rows(tt.e3('l1_pnl')) r where r ->> 'location_id' = '1') and not tt.has_note(tt.e3('l1_pnl'), 'losses_not_counted')
  and (select (r ->> 'profit')::numeric from tt.rows(tt.e3('l1_pnl')) r where r ->> 'location_id' = '1') < (select (r ->> 'profit')::numeric from tt.rows(:'l1a'::jsonb) r where r ->> 'location_id' = '1'));
select set_rule('profit_loss_wastage', 'false') is null as w_off \gset
select tt.chk('T5 master ON but the wastage switch OFF: wastage is named again', (select r ->> 'gaps' like '%wastage (not in profit)%' and r ->> 'gaps' not like '%count shrink%' from tt.rows(tt.e3('l1_pnl')) r where r ->> 'location_id' = '1'));
select set_rule('profit_loss_wastage', 'true') is null as w_on2 \gset
select set_rule('profit_losses_from', to_jsonb((:'td'::date + 1)::text)) is null as w_from \gset
select tt.chk('T5 a start date after the loss: the loss is left out and named', (select r ->> 'gaps' like '%wastage (not in profit)%' from tt.rows(tt.e3('l1_pnl')) r where r ->> 'location_id' = '1'));
select set_rule('profit_losses_from', 'null'::jsonb) is null as w_from2 \gset
select set_rule('profit_one_number_on', 'false') is null as w_off2 \gset
select profit_exclude('wastage', (select source_id from _w1d_pl_rows(:'d1'::date, :'td'::date, array[1]) where cause = 'wastage' limit 1), 'test exclusion reason') is not null as w_ex \gset
select tt.chk('T5 a loss the owner left out on purpose (with a reason) is not named as a gap', (select r ->> 'gaps' = 'expenses, salary, fixed, count shrink (not in profit)' from tt.rows(tt.e3('l1_pnl')) r where r ->> 'location_id' = '1'));

\echo == T6 costing Runs tab (production_run_costs)
select public.production_run_costs(1, current_date - 30, current_date + 1) as prc \gset
select tt.chk('T6 run 1 (no actual yield): actual cost EMPTY with status not_captured; conversion cost EMPTY (method off) with status not_captured; unit cost basis material only',
  (select e -> 'actual_cost' = 'null'::jsonb and e ->> 'actual_status' = 'not_captured' and e -> 'conversion_cost' = 'null'::jsonb and e ->> 'conversion_status' = 'not_captured' and e ->> 'unit_cost_basis' = 'material_only'
     from jsonb_array_elements(:'prc'::jsonb) e where (e ->> 'run_id') = :'run1'));
select tt.chk('T6 run 2 (actual yield 8 typed): actual cost 12.5 is shown, no actual status; the unit cost 12.5 and the standard 10 are unchanged', (select (e ->> 'actual_cost')::numeric = 12.5 and e -> 'actual_status' = 'null'::jsonb and (e ->> 'unit_cost')::numeric = 12.5 and (e ->> 'std_cost')::numeric = 10 and (e ->> 'yield_var_pct')::numeric = -20
     from jsonb_array_elements(:'prc'::jsonb) e where (e ->> 'run_id') = :'run2'));
select tt.chk('T6 the material cost and the output are untouched (100 / 10 and 100 / 8)', (select bool_and((e ->> 'material_cost')::numeric = 100) and sum((e ->> 'output')::numeric) = 18 from jsonb_array_elements(:'prc'::jsonb) e));
select loc_cost_cfg_set(1, 'recipe') is null as w_c1 \gset
select recipe_cost_component_set(:'rc'::uuid, 'labour', 'per_batch', 40, null, null, 'rb1', gen_random_uuid()) ->> 'id' as w_cc \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid(), null, null, 10::numeric) ->> 'run_id' as run3 \gset
select public.production_run_costs(1, current_date - 30, current_date + 1) as prc2 \gset
select tt.chk('T6 run 3 with the method "recipe" and a labour rate of 40: conversion cost 40 shown, no status, unit cost basis material and conversion, unit cost 14',
  (select (e ->> 'conversion_cost')::numeric = 40 and e -> 'conversion_status' = 'null'::jsonb and e ->> 'unit_cost_basis' = 'material_and_conversion' and (e ->> 'unit_cost')::numeric = 14 and (e ->> 'actual_cost')::numeric = 14
     from jsonb_array_elements(:'prc2'::jsonb) e where (e ->> 'run_id') = :'run3'));
select tt.chk('T6 the older runs keep their status (their method at that time was off)', (select count(*) from jsonb_array_elements(:'prc2'::jsonb) e where e ->> 'conversion_status' = 'not_captured') = 2);
select tt.as('00000000-0000-0000-0000-000000000401'); set role authenticated;
select tt.err('T6 a person without the cost right is still refused', $$select public.production_run_costs(1, current_date - 30, current_date + 1)$$, 'not allowed');
reset role; select tt.as(:'o');

\echo == T7 other reports and rights
select tt.chk('T7 the notes are only added when there are rows (an empty period has no "not captured" note)', not tt.has_note(public.report_run2('f3_raw_vs_recipe', '{"from":"2020-01-01","to":"2020-01-02"}'::jsonb), 'not_captured'));
insert into user_grants (user_id, grant_code, location_id) values (:'st', 'report_stock', null) on conflict do nothing;
set role authenticated; select tt.as(:'st');
select tt.chk('T7 a place-1 stock person sees f3 with the note (no cost right needed for quantities)', tt.has_note(public.report_run2('f3_raw_vs_recipe', '{"preset":"last_7"}'::jsonb), 'not_captured') );
select tt.err('T7 the branch profit report is still refused without the profit right (l1)', $$select public.report_run2('l1_pnl', '{"preset":"last_7"}'::jsonb)$$, 'not allowed');
reset role; delete from user_grants where user_id = :'st'::uuid and grant_code = 'report_stock'; select tt.as(:'o');

\echo == T8 pasting phase401 again
select md5(pg_get_functiondef('public._rptb1_loss_gaps(date,date,integer)'::regprocedure) || pg_get_functiondef('public._rptb1_r3_notes(text,date,date,integer[],jsonb)'::regprocedure)) as h3 \gset
\ir phase401.sql
select tt.chk('T8 phase401 again: helper bodies unchanged, hooks still in place, the f3 column still once', md5(pg_get_functiondef('public._rptb1_loss_gaps(date,date,integer)'::regprocedure) || pg_get_functiondef('public._rptb1_r3_notes(text,date,date,integer[],jsonb)'::regprocedure)) = :'h3'
  and (select bool_and(value::boolean) from jsonb_each_text(public._rptb1_hooked401())) and (select count(*) from jsonb_array_elements((select cols from report_defs3 where key = 'f3_raw_vs_recipe')) c where c ->> 0 = 'actual_status') = 1);
select tt.chk('T8 every journal entry balances', not exists (select 1 from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z));

select 'RESULT: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from tt.res;
select name from tt.res where not ok;
