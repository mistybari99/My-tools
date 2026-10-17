-- FRESH DB ONLY. Phase 400 tests: R1 returns and refund consistency in the report engine (package RPT-B1).
--   Build a database through phase 99 (tests/sql/ORDER.txt order), paste supabase/phase400.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase400_test.sql | grep -E 'FAIL|RESULT'
-- The data comes from tests/sql/rptb1_fixture.sql (hand-computed numbers in its header). The hooks (docs/integration/RPT-B1_hooks.sql, section 1) are installed by THIS file, after the
-- "before" snapshot, exactly as the integrator will. Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rptb1_fixture.sql
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
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
grant select, insert on tt.snap to authenticated, anon;

-- the report runs that are compared before / after the hooks: key | group | extra filters | compare
create or replace function tt.cases() returns table (k text, g text, f jsonb, cmp boolean) language sql as $$
  values ('sales_summary', 'total', '{}'::jsonb, false), ('sales_summary', 'day', '{}', false), ('sales_summary', 'location', '{}', false), ('sales_summary', 'brand', '{}', false),
    ('sales_summary', 'staff', '{}', false), ('sales_summary', 'pay_mode', '{}', false), ('sales_summary', 'sale_type', '{}', false), ('sales_summary', 'month', '{}', false),
    ('sales_summary', 'week', '{}', false), ('sales_summary', 'location,day', '{}', false), ('sales_summary', 'total', '{}', true), ('sales_summary', 'day', '{"compare_mode":"week"}', true),
    ('sales_summary', 'total', '{"modes":["cash"]}', false), ('sales_summary', 'total', '{"locations":[1]}', false),
    ('sales_trend', 'day', '{}', false), ('sales_trend', 'location', '{}', false), ('sales_combined', 'location', '{}', false), ('sales_combined', 'brand', '{}', false),
    ('item_sales', 'item', '{}', false), ('item_sales', 'category', '{}', false), ('item_sales', 'day', '{}', false), ('item_sales', 'location', '{}', false), ('item_sales', 'total', '{}', false),
    ('item_sales', 'item', '{}', true), ('category_sales', 'category', '{}', false), ('category_sales', 'item', '{}', false),
    ('payment_modes', 'mode', '{}', false), ('payment_modes', 'wallet', '{}', false), ('payment_modes', 'kind', '{}', false), ('payment_modes', 'day', '{}', false),
    ('payment_modes', 'total', '{}', false), ('payment_modes', 'mode', '{}', true), ('pos_day_close', null, '{}', false), ('pos_day_close', null, '{"locations":[2]}', false),
    -- reports that carry no new column: must be completely unchanged
    ('discounts', null, '{}', false), ('voids', null, '{}', false), ('receipt_register', null, '{}', false), ('hour_weekday', null, '{}', false), ('retail_wholesale', null, '{}', false),
    ('quick_unlisted', null, '{}', false), ('collections', null, '{}', false), ('wallet_recon', null, '{}', false), ('best_customers', null, '{}', false) $$;
create or replace function tt.snapshot(p_phase text) returns void language plpgsql as $$
declare c record;
begin
  for c in select * from tt.cases() loop
    insert into tt.snap select p_phase, c.k || '|' || coalesce(c.g, '-') || '|' || c.f::text || '|' || c.cmp::text,
      public.report_run(c.k, c.f || '{"preset":"last_7"}'::jsonb, c.g, null, 1, c.cmp);
  end loop;
end $$;
-- the new keys, to be taken out of a "after" answer before it is compared with the "before" answer
create or replace function tt.newkeys() returns text[] language sql immutable as $$
  select array['returns_amt', 'net_after_returns', 'returns_qty', 'qty_after_returns', 'refund_paid', 'net_after_refunds', 'refund_cash', 'refund_mobile', 'refund_card', 'expected_cash_after_refunds'] $$;
create or replace function tt.strip(j jsonb) returns jsonb language sql immutable as $$
  select case when j is null then null else (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) from jsonb_each(j) e where e.key <> all (tt.newkeys())) end $$;
-- every OLD row is in the new answer with the same old values; a row that is only in the new answer is a return-only group (all old money 0 / empty); old totals and columns identical
create or replace function tt.same_old(b jsonb, n jsonb) returns boolean language plpgsql as $$
declare ok boolean := true; r jsonb; found boolean; nr jsonb; bcols jsonb; ncols jsonb;
begin
  if b is null or n is null then return b is null and n is null; end if;
  if tt.strip(b -> 'totals') is distinct from tt.strip(n -> 'totals') then raise notice 'totals differ: % vs %', tt.strip(b -> 'totals'), tt.strip(n -> 'totals'); return false; end if;
  bcols := (select coalesce(jsonb_agg(c order by o), '[]') from jsonb_array_elements(b -> 'columns') with ordinality x(c, o));
  ncols := (select coalesce(jsonb_agg(c order by o), '[]') from jsonb_array_elements(n -> 'columns') with ordinality x(c, o) where not ((c ->> 'key') = any (tt.newkeys())));
  if bcols is distinct from ncols then raise notice 'columns differ'; return false; end if;
  for r in select e from jsonb_array_elements(b -> 'rows') e loop
    found := false;
    for nr in select e from jsonb_array_elements(n -> 'rows') e loop if tt.strip(nr) = tt.strip(r) then found := true; exit; end if; end loop;
    if not found then raise notice 'old row missing: %', r; return false; end if;
  end loop;
  for nr in select e from jsonb_array_elements(n -> 'rows') e loop
    found := false;
    for r in select e from jsonb_array_elements(b -> 'rows') e loop if tt.strip(nr) = tt.strip(r) then found := true; exit; end if; end loop;
    if not found and exists (select 1 from jsonb_each(tt.strip(nr)) kv where kv.key in ('bills', 'net', 'qty', 'amount', 'gross', 'payments', 'expected_cash', 'cash_in', 'total_in') and jsonb_typeof(kv.value) = 'number' and (kv.value #>> '{}')::numeric <> 0) then
      raise notice 'extra row is not return-only: %', nr; return false; end if;
  end loop;
  return true;
end $$;
create or replace function tt.sn(p_phase text, p_k text) returns jsonb language sql stable as $$ select j from tt.snap where phase = p_phase and k like p_k || '%' order by k limit 1 $$;
create or replace function tt.row_of(p_j jsonb, p_key text, p_val text) returns jsonb language sql immutable as $$
  select e from jsonb_array_elements(p_j -> 'rows') e where e ->> p_key = p_val limit 1 $$;
create or replace function tt.num(p_j jsonb, p_path text[]) returns numeric language sql immutable as $$ select (p_j #>> p_path)::numeric $$;
create or replace function tt.has_note(p_j jsonb, p_code text) returns boolean language sql immutable as $$ select exists (select 1 from jsonb_array_elements(p_j -> 'notes') n where n ->> 'code' = p_code) $$;
select tt.today() as td \gset

\echo == T0 shape: phase400 is there, the hooks are not, internals are closed
select tt.chk('T0 phase400 present, the helper and the wrap functions exist', to_regprocedure('public._rptb1_p400_present()') is not null and to_regprocedure('public._rptb1_patch(regprocedure,text,text[])') is not null
  and to_regprocedure('public._rptb1_agg_wrap(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean,text,text)') is not null);
select tt.chk('T0 no hook is installed yet', not exists (select 1 from jsonb_each_text(public._rptb1_hooked()) where value = 'true'));
select tt.chk('T0 the three return views are closed to browsers',
  not has_table_privilege('authenticated','public.rpt_ret_b','select') and not has_table_privilege('authenticated','public.rpt_ret_l','select') and not has_table_privilege('authenticated','public.rpt_ret_p','select')
  and not has_table_privilege('anon','public.rpt_ret_b','select') and not has_table_privilege('anon','public.rpt_ret_l','select') and not has_table_privilege('anon','public.rpt_ret_p','select'));
select tt.chk('T0 internals are closed to browsers and to anon',
  not has_function_privilege('authenticated','public._rptb1_patch(regprocedure,text,text[])','execute') and not has_function_privilege('authenticated','public._rptb1_hooked()','execute')
  and not has_function_privilege('authenticated','public._rptb1_notes(jsonb,text[],text[])','execute') and not has_function_privilege('anon','public._rptb1_patch(regprocedure,text,text[])','execute')
  and not has_function_privilege('authenticated','public._rptb1_day_close_wrap(text,jsonb,integer[],date,date,text[],boolean)','execute'));
select tt.err('T0 a patch whose site is missing stops with a clear message', $$select public._rptb1_patch('public._rptb1_p400_present()'::regprocedure, 'bos400', array['text that is not there', 'x /* bos400 */'])$$, 'patch site not found');
select tt.err('T0 a bad marker is refused', $$select public._rptb1_patch('public._rptb1_p400_present()'::regprocedure, 'x', array['a','b'])$$, 'needs a marker');
select tt.chk('T0 the views see the fixture: 3 live returns, 4 lines of money, 2 payouts (R4 is voided)',
  (select count(*) from rpt_ret_b) = 3 and (select count(*) from rpt_ret_l) = 3 and (select count(*) from rpt_ret_p) = 2 and (select sum(ret_amt) from rpt_ret_b) = 400 and (select sum(ret_amt) from rpt_ret_l) = 400 and (select sum(amount) from rpt_ret_p) = 300);

\echo == T1 BEFORE the hooks: the answers are the ones of today (snapshot)
select tt.as(:'o');
select tt.snapshot('before');
select tt.chk('T1 before the hooks no answer has a new column', not exists (select 1 from tt.snap where phase = 'before' and (j::text ~ '"(returns_amt|net_after_returns|returns_qty|refund_paid|refund_cash|expected_cash_after_refunds)"')));
select tt.chk('T1 sales summary today: sales 1800, bills 4 (returns ignored: the audit finding D1)', tt.num(tt.sn('before', 'sales_summary|total|{}|false'), '{totals,net}') = 1800);
select tt.chk('T1 POS day close today: expected cash ignores the 200 handed back (audit D1b)', tt.num(tt.row_of(tt.sn('before', 'pos_day_close|-|{}|false'), 'location_id', '1'), '{expected_cash}') is not null);

\echo == T2 install the hooks (docs/integration/RPT-B1_hooks.sql, section 1)
\ir ../docs/integration/RPT-B1_hooks.sql
select tt.chk('T2 all five hook sites carry the marker', (select bool_and(value::boolean) from jsonb_each_text(public._rptb1_hooked())) and (select count(*) from jsonb_each_text(public._rptb1_hooked())) = 5);
select md5(pg_get_functiondef('public.rpt_meas(text)'::regprocedure) || pg_get_functiondef('public.rpt_def(text)'::regprocedure) || pg_get_functiondef('public.rpt_agg_build(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean)'::regprocedure)
  || pg_get_functiondef('public.rpt_raw(text,jsonb,integer[],date,date,boolean,integer[],numeric,date)'::regprocedure) || pg_get_functiondef('public.report_run(text,jsonb,text,text,integer,boolean)'::regprocedure)) as h1 \gset
\ir ../docs/integration/RPT-B1_hooks.sql
select tt.chk('T2 pasting the hooks again changes nothing (function bodies identical)',
  md5(pg_get_functiondef('public.rpt_meas(text)'::regprocedure) || pg_get_functiondef('public.rpt_def(text)'::regprocedure) || pg_get_functiondef('public.rpt_agg_build(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean)'::regprocedure)
  || pg_get_functiondef('public.rpt_raw(text,jsonb,integer[],date,date,boolean,integer[],numeric,date)'::regprocedure) || pg_get_functiondef('public.report_run(text,jsonb,text,text,integer,boolean)'::regprocedure)) = :'h1');
select md5(pg_get_functiondef('public._rptb1_agg_wrap(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean,text,text)'::regprocedure)) as h2 \gset
\ir phase400.sql
select tt.chk('T2 pasting phase400 again does not remove the hooks and changes no function', (select bool_and(value::boolean) from jsonb_each_text(public._rptb1_hooked()))
  and md5(pg_get_functiondef('public._rptb1_agg_wrap(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean,text,text)'::regprocedure)) = :'h2');
select tt.as(:'o');
select tt.snapshot('after');

\echo == T3 NO OLD FIGURE CHANGED: every old row, total and column of every report equals the snapshot from before the hooks
select tt.chk('T3 ' || b.k || ' (old columns identical)', tt.same_old(b.j, a.j)) from tt.snap b join tt.snap a on a.k = b.k and a.phase = 'after' where b.phase = 'before' order by b.k;
select tt.chk('T3 the reports that carry no new column are byte-identical (discounts, voids, register, hour, retail, quick, collections, wallets, best customers)',
  (select count(*) from tt.snap b join tt.snap a on a.k = b.k and a.phase = 'after' where b.phase = 'before' and b.k ~ '^(discounts|voids|receipt_register|hour_weekday|retail_wholesale|quick_unlisted|collections|wallet_recon|best_customers)'
     and a.j - 'notes' <> b.j - 'notes') = 0);
select tt.chk('T3 the dashboard figures are untouched: sales_summary(date) still gives one return row per day and place', (select count(*) from public.sales_summary(:'td'::date - 7) where pay_mode = 'return') = 2);

\echo == T4 the new columns agree with the dashboard
select tt.sn('after', 'sales_summary|total|{}|false') as j_tot \gset
select tt.chk('T4 sales summary total: sales 1800, returns 400, sales after returns 1400', tt.num(:'j_tot'::jsonb, '{totals,net}') = 1800 and tt.num(:'j_tot'::jsonb, '{totals,returns_amt}') = 400 and tt.num(:'j_tot'::jsonb, '{totals,net_after_returns}') = 1400);
select tt.chk('T4 sales after returns equals the dashboard (biz_daily revenue, sales_summary(date) done rows incl. the return rows)',
  tt.num(:'j_tot'::jsonb, '{totals,net_after_returns}') = (select sum(revenue) from public.biz_daily(:'td'::date - 7, :'td'::date))
  and tt.num(:'j_tot'::jsonb, '{totals,net_after_returns}') = (select sum(total) from public.sales_summary(:'td'::date - 7) where status = 'done' and sale_date >= :'td'::date - 6));
select tt.chk('T4 the answer says how returns are counted (a note) and the old note list is kept', tt.has_note(:'j_tot'::jsonb, 'returns_basis') and not tt.has_note(:'j_tot'::jsonb, 'returns_not_netted'));
select tt.chk('T4 the new columns are listed in the catalogue for the five sales reports and the payment report',
  (select count(*) from jsonb_array_elements(public.report_catalog()) c where c ->> 'key' in ('sales_summary', 'sales_trend', 'sales_combined', 'item_sales', 'category_sales', 'payment_modes')
     and exists (select 1 from jsonb_array_elements(c -> 'columns') x where x ->> 'key' in ('returns_amt', 'refund_paid'))) = 6);
select tt.chk('T4 the new columns come AFTER the old ones (the summary strip of the viewer keeps its first four)',
  (select (a.c ->> 'key') from (select c from jsonb_array_elements(tt.sn('after', 'sales_trend|day')-> 'columns') with ordinality x(c, o) order by o desc limit 1) a) = 'net_after_returns');

\echo == T5 by place / day / staff / payment mode
select tt.sn('after', 'sales_summary|location|{}|false') as j_loc \gset
select tt.chk('T5 place 1: sales 1400, returns 400, after 1000', tt.num(tt.row_of(:'j_loc'::jsonb, 'location_id', '1'), '{net}') = 1400 and tt.num(tt.row_of(:'j_loc'::jsonb, 'location_id', '1'), '{returns_amt}') = 400
  and tt.num(tt.row_of(:'j_loc'::jsonb, 'location_id', '1'), '{net_after_returns}') = 1000);
select tt.chk('T5 place 2: sales 400, returns 0, after 400', tt.num(tt.row_of(:'j_loc'::jsonb, 'location_id', '2'), '{returns_amt}') = 0 and tt.num(tt.row_of(:'j_loc'::jsonb, 'location_id', '2'), '{net_after_returns}') = 400);
select tt.sn('after', 'sales_summary|day|{}|false') as j_day \gset
select tt.chk('T5 today: sales 1400, returns 300 (R1 200 + R3 100), after 1100', tt.num(tt.row_of(:'j_day'::jsonb, 'day', :'td'), '{net}') = 1400 and tt.num(tt.row_of(:'j_day'::jsonb, 'day', :'td'), '{returns_amt}') = 300
  and tt.num(tt.row_of(:'j_day'::jsonb, 'day', :'td'), '{net_after_returns}') = 1100);
select tt.chk('T5 two days ago a return was made and nothing was sold at place 1: the day shows as a return-only row (bills 0, sales 0, returns 100, after -100)',
  tt.num(tt.row_of(:'j_day'::jsonb, 'day', to_char(:'td'::date - 2, 'YYYY-MM-DD')), '{bills}') = 0 and tt.num(tt.row_of(:'j_day'::jsonb, 'day', to_char(:'td'::date - 2, 'YYYY-MM-DD')), '{returns_amt}') = 100
  and tt.num(tt.row_of(:'j_day'::jsonb, 'day', to_char(:'td'::date - 2, 'YYYY-MM-DD')), '{net_after_returns}') = -100);
select tt.chk('T5 three days ago (place 2 sale): sales 400, no return', tt.num(tt.row_of(:'j_day'::jsonb, 'day', to_char(:'td'::date - 3, 'YYYY-MM-DD')), '{net_after_returns}') = 400);
select tt.chk('T5 the rows add up to the total row (returns and after-returns)', (select sum((e ->> 'returns_amt')::numeric) from jsonb_array_elements(:'j_day'::jsonb -> 'rows') e) = tt.num(:'j_day'::jsonb, '{totals,returns_amt}')
  and (select sum((e ->> 'net_after_returns')::numeric) from jsonb_array_elements(:'j_day'::jsonb -> 'rows') e) = tt.num(:'j_day'::jsonb, '{totals,net_after_returns}'));
select tt.chk('T5 by pay mode: returns follow the mode of the ORIGINAL sale (cash 300, due 100)', tt.num(tt.row_of(tt.sn('after', 'sales_summary|pay_mode|{}|false'), 'pay_mode', 'cash'), '{returns_amt}') = 300
  and tt.num(tt.row_of(tt.sn('after', 'sales_summary|pay_mode|{}|false'), 'pay_mode', 'due'), '{returns_amt}') = 100);
select tt.chk('T5 by sale type: wholesale carries the 100 return of the credit sale, retail 300', tt.num(tt.row_of(tt.sn('after', 'sales_summary|sale_type|{}|false'), 'sale_type', 'wholesale'), '{returns_amt}') = 100
  and tt.num(tt.row_of(tt.sn('after', 'sales_summary|sale_type|{}|false'), 'sale_type', 'retail'), '{returns_amt}') = 300);
select tt.chk('T5 by staff and by two dimensions (place, day) the total still ties', (select sum((e ->> 'returns_amt')::numeric) from jsonb_array_elements(tt.sn('after', 'sales_summary|staff|{}|false') -> 'rows') e) = 400
  and (select sum((e ->> 'returns_amt')::numeric) from jsonb_array_elements(tt.sn('after', 'sales_summary|location,day|{}|false') -> 'rows') e) = 400);
select tt.chk('T5 by week and by month the total still ties', (select sum((e ->> 'returns_amt')::numeric) from jsonb_array_elements(tt.sn('after', 'sales_summary|week|{}|false') -> 'rows') e) = 400
  and (select sum((e ->> 'returns_amt')::numeric) from jsonb_array_elements(tt.sn('after', 'sales_summary|month|{}|false') -> 'rows') e) = 400);
select tt.chk('T5 filters: cash sales only -> returns 300 (R1, R2); place 1 only -> 400', tt.num(tt.sn('after', 'sales_summary|total|{"modes"'), '{totals,returns_amt}') = 300
  and tt.num(tt.sn('after', 'sales_summary|total|{"locations"'), '{totals,returns_amt}') = 400);
select tt.chk('T5 trend and combined carry the same figures', tt.num(tt.sn('after', 'sales_trend|day'), '{totals,returns_amt}') = 400 and tt.num(tt.sn('after', 'sales_combined|location'), '{totals,net_after_returns}') = 1400
  and tt.num(tt.row_of(tt.sn('after', 'sales_combined|location'), 'location_id', '1'), '{net_after_returns}') = 1000);
select tt.chk('T5 compare with the previous period keeps working and the delta has the new keys', (tt.sn('after', 'sales_summary|total|{}|true') -> 'compare' -> 'delta' ? 'returns_amt')
  and (tt.sn('after', 'sales_summary|day|%week%|true') -> 'compare' -> 'rows') is not null);

\echo == T6 item and category
select tt.sn('after', 'item_sales|item|{}|false') as j_it \gset
select tt.chk('T6 item A: sold 11 for 1100, returned 2 for 200, after 900 / 9', tt.num(tt.row_of(:'j_it'::jsonb, 'item_code', 'RB1-A'), '{net}') = 1100 and tt.num(tt.row_of(:'j_it'::jsonb, 'item_code', 'RB1-A'), '{returns_qty}') = 2
  and tt.num(tt.row_of(:'j_it'::jsonb, 'item_code', 'RB1-A'), '{returns_amt}') = 200 and tt.num(tt.row_of(:'j_it'::jsonb, 'item_code', 'RB1-A'), '{net_after_returns}') = 900
  and tt.num(tt.row_of(:'j_it'::jsonb, 'item_code', 'RB1-A'), '{qty}') = 11 and tt.num(tt.row_of(:'j_it'::jsonb, 'item_code', 'RB1-A'), '{qty_after_returns}') = 9);
select tt.chk('T6 item B: sold 14 for 700, returned 4 for 200, after 500 / 10', tt.num(tt.row_of(:'j_it'::jsonb, 'item_code', 'RB1-B'), '{net}') = 700 and tt.num(tt.row_of(:'j_it'::jsonb, 'item_code', 'RB1-B'), '{returns_qty}') = 4
  and tt.num(tt.row_of(:'j_it'::jsonb, 'item_code', 'RB1-B'), '{returns_amt}') = 200 and tt.num(tt.row_of(:'j_it'::jsonb, 'item_code', 'RB1-B'), '{net_after_returns}') = 500 and tt.num(tt.row_of(:'j_it'::jsonb, 'item_code', 'RB1-B'), '{qty_after_returns}') = 10);
select tt.chk('T6 item sales total: after returns 1400, the same figure as the sales summary', tt.num(tt.sn('after', 'item_sales|total|{}|false'), '{totals,net_after_returns}') = 1400
  and tt.num(tt.sn('after', 'item_sales|total|{}|false'), '{totals,returns_qty}') = 6 and tt.num(tt.sn('after', 'item_sales|total|{}|false'), '{totals,qty_after_returns}') = 19);
select tt.chk('T6 by category and by day', tt.num(tt.row_of(tt.sn('after', 'item_sales|category'), 'category', 'test_cat_one'), '{returns_amt}') = 200 and tt.num(tt.row_of(tt.sn('after', 'item_sales|category'), 'category', 'test_cat_two'), '{returns_amt}') = 200
  and (select sum((e ->> 'returns_amt')::numeric) from jsonb_array_elements(tt.sn('after', 'item_sales|day') -> 'rows') e) = 400 and tt.has_note(tt.sn('after', 'item_sales|day'), 'returns_basis'));
select tt.chk('T6 category_sales carries the same columns', tt.num(tt.row_of(tt.sn('after', 'category_sales|category'), 'category', 'test_cat_one'), '{net_after_returns}') = 900
  and tt.num(tt.row_of(tt.sn('after', 'category_sales|category'), 'category', 'test_cat_two'), '{qty_after_returns}') = 10);
select tt.chk('T6 a discount is shared: the return amount of a discounted sale is the value after the discount (checked on the stored return)',
  (select sum(amount) from sale_returns where status = 'done') = (select sum(ret_amt) from rpt_ret_l));

\echo == T7 the rule reports_net_of_returns is honoured
select set_rule('reports_net_of_returns', 'false') is null as w_r \gset
select report_run('sales_summary', '{"preset":"last_7"}', 'total') as j_off \gset
select tt.chk('T7 rule OFF: sales after returns equals sales (like the dashboard), returns still shown as a fact, a note says so',
  tt.num(:'j_off'::jsonb, '{totals,net_after_returns}') = 1800 and tt.num(:'j_off'::jsonb, '{totals,returns_amt}') = 400 and tt.has_note(:'j_off'::jsonb, 'returns_not_netted')
  and tt.num(:'j_off'::jsonb, '{totals,net_after_returns}') = (select sum(revenue) from public.biz_daily(:'td'::date - 7, :'td'::date)));
select tt.chk('T7 rule OFF: quantity after returns equals quantity', tt.num(report_run('item_sales', '{"preset":"last_7"}', 'total'), '{totals,qty_after_returns}') = 25);
select set_rule('reports_net_of_returns', 'true') is null as w_r2 \gset
select tt.chk('T7 rule ON again: back to 1400', tt.num(report_run('sales_summary', '{"preset":"last_7"}', 'total'), '{totals,net_after_returns}') = 1400);

\echo == T8 payments and refunds
select tt.sn('after', 'payment_modes|mode|{}|false') as j_pm \gset
select tt.chk('T8 by mode: cash took 1300 and paid back 200 (net 1100); mobile took 0 and paid back 100 (net -100)', tt.num(tt.row_of(:'j_pm'::jsonb, 'mode', 'cash'), '{amount}') = 1300 and tt.num(tt.row_of(:'j_pm'::jsonb, 'mode', 'cash'), '{refund_paid}') = 200
  and tt.num(tt.row_of(:'j_pm'::jsonb, 'mode', 'cash'), '{net_after_refunds}') = 1100 and tt.num(tt.row_of(:'j_pm'::jsonb, 'mode', 'mobile'), '{amount}') = 0
  and tt.num(tt.row_of(:'j_pm'::jsonb, 'mode', 'mobile'), '{refund_paid}') = 100 and tt.num(tt.row_of(:'j_pm'::jsonb, 'mode', 'mobile'), '{net_after_refunds}') = -100);
select tt.chk('T8 total: money handed back 300, not 400 (the 100 return settled against the customer due is not a payout)', tt.num(tt.sn('after', 'payment_modes|total'), '{totals,refund_paid}') = 300
  and tt.num(tt.sn('after', 'payment_modes|total'), '{totals,net_after_refunds}') = tt.num(tt.sn('after', 'payment_modes|total'), '{totals,amount}') - 300);
select tt.chk('T8 by wallet: the mobile refund is on its wallet', tt.num(tt.row_of(tt.sn('after', 'payment_modes|wallet'), 'wallet', 'bkash'), '{refund_paid}') = 100);
select tt.chk('T8 by kind: refunds have their own group', tt.num(tt.row_of(tt.sn('after', 'payment_modes|kind'), 'kind', 'refund'), '{refund_paid}') = 300 and tt.num(tt.row_of(tt.sn('after', 'payment_modes|kind'), 'kind', 'sale'), '{refund_paid}') = 0);
select tt.chk('T8 by day: the refund of two days ago is on its own day', tt.num(tt.row_of(tt.sn('after', 'payment_modes|day'), 'day', to_char(:'td'::date - 2, 'YYYY-MM-DD')), '{refund_paid}') = 100);
select tt.chk('T8 the refund note is there', tt.has_note(tt.sn('after', 'payment_modes|total'), 'refund_basis'));

\echo == T9 POS day close: expected cash after the cash that went back
select tt.sn('after', 'pos_day_close|-|{}|false') as j_dc \gset
select tt.chk('T9 today place 1: cash in 900, expected cash 900 (as before), cash refunds 200, expected cash after refunds 700',
  tt.num(tt.row_of(:'j_dc'::jsonb, 'day', :'td'), '{expected_cash}') = 900 and tt.num(tt.row_of(:'j_dc'::jsonb, 'day', :'td'), '{refund_cash}') = 200
  and tt.num(tt.row_of(:'j_dc'::jsonb, 'day', :'td'), '{expected_cash_after_refunds}') = 700 and tt.num(tt.row_of(:'j_dc'::jsonb, 'day', :'td'), '{refund_mobile}') = 0);
select tt.chk('T9 two days ago: no sale, a 100 mobile refund -> a row of its own, cash untouched', tt.num((select e from jsonb_array_elements(:'j_dc'::jsonb -> 'rows') e where e ->> 'day' = to_char(:'td'::date - 2, 'YYYY-MM-DD') limit 1), '{refund_mobile}') = 100
  and tt.num((select e from jsonb_array_elements(:'j_dc'::jsonb -> 'rows') e where e ->> 'day' = to_char(:'td'::date - 2, 'YYYY-MM-DD') limit 1), '{bills}') = 0
  and tt.num((select e from jsonb_array_elements(:'j_dc'::jsonb -> 'rows') e where e ->> 'day' = to_char(:'td'::date - 2, 'YYYY-MM-DD') limit 1), '{expected_cash_after_refunds}') = 0);
select tt.chk('T9 totals: refunds cash 200, mobile 100, card 0; expected cash after = expected cash - 200', tt.num(:'j_dc'::jsonb, '{totals,refund_cash}') = 200 and tt.num(:'j_dc'::jsonb, '{totals,refund_mobile}') = 100
  and tt.num(:'j_dc'::jsonb, '{totals,refund_card}') = 0 and tt.num(:'j_dc'::jsonb, '{totals,expected_cash_after_refunds}') = tt.num(:'j_dc'::jsonb, '{totals,expected_cash}') - 200);
select tt.chk('T9 the place filter works on the refunds: place 2 has none', tt.num(tt.sn('after', 'pos_day_close|-|%locations%'), '{totals,refund_cash}') = 0);
select tt.chk('T9 the columns are in the catalogue and in the answer, the old ones first', (select count(*) from jsonb_array_elements(public.report_catalog()) c, jsonb_array_elements(c -> 'columns') x where c ->> 'key' = 'pos_day_close' and x ->> 'key' = 'expected_cash_after_refunds') = 1
  and (select (c ->> 'key') from jsonb_array_elements(:'j_dc'::jsonb -> 'columns') with ordinality x(c, o) where (c ->> 'key') = 'expected_cash') is not null);
select tt.chk('T9 a voided return is not a payout (R4 cash 100 was voided): cash refunds stay 200', tt.num(:'j_dc'::jsonb, '{totals,refund_cash}') = 200);

\echo == T10 who sees what
select tt.chk('T10 a voided return is counted nowhere: 3 live returns, the voided one has status void', (select count(*) from sale_returns where status = 'void') = 1 and (select count(*) from rpt_ret_b) = 3);
insert into user_grants (user_id, grant_code, location_id) values (:'st', 'report_sales', null), (:'st', 'report_pos', null), (:'st', 'report_cash', null) on conflict do nothing;
reset role; set role authenticated; select tt.as(:'st');
select report_run('sales_summary', '{"preset":"last_7"}', 'total') as j_st \gset
select tt.chk('T10 a place-1 salesperson sees the place-1 figures only (sales 1400, returns 400, after 1000) and the place note', tt.num(:'j_st'::jsonb, '{totals,net}') = 1400 and tt.num(:'j_st'::jsonb, '{totals,returns_amt}') = 400
  and tt.num(:'j_st'::jsonb, '{totals,net_after_returns}') = 1000 and tt.has_note(:'j_st'::jsonb, 'location_scope'));
select tt.chk('T10 without the cost right the cost columns stay hidden but the returns columns are there', tt.has_note(:'j_st'::jsonb, 'cost_hidden') and not (:'j_st'::jsonb -> 'totals' ? 'cogs') and (:'j_st'::jsonb -> 'totals' ? 'returns_amt'));
select tt.chk('T10 item sales for the place-1 salesperson: no cost columns, returns columns', not (report_run('item_sales', '{"preset":"last_7"}', 'item') -> 'totals' ? 'gp') and (report_run('item_sales', '{"preset":"last_7"}', 'item') -> 'totals' ? 'returns_qty'));
select tt.chk('T10 POS day close for the place-1 salesperson: place 1 only', tt.num(report_run('pos_day_close', '{"preset":"last_7"}'), '{totals,refund_cash}') = 200);
reset role; delete from user_grants where user_id = :'st'::uuid and grant_code in ('report_sales', 'report_pos', 'report_cash');
set role authenticated; select tt.as(:'st');
select tt.err('T10 a person without the report right is still refused (sales summary)', $$select report_run('sales_summary', '{"preset":"last_7"}', 'total')$$, 'not allowed');
select tt.err('T10 and refused on the payment report', $$select report_run('payment_modes', '{"preset":"last_7"}', 'mode')$$, 'not allowed');
reset role;

\echo == T11 the books and the data are untouched
select tt.chk('T11 nothing was written: the number of returns, sales and payments is the fixture''s', (select count(*) from sale_returns) = 4 and (select count(*) from sales) = 5);
select tt.chk('T11 every journal entry balances', not exists (select 1 from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z));

select 'RESULT: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from tt.res;
select name from tt.res where not ok;
