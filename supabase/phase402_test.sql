-- FRESH DB ONLY. Phase 402 tests: R7 one cost basis for item sales and the business analysis (package RPT-B1).
--   Build a database through phase 99, paste supabase/phase400.sql, 401.sql and 402.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase402_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rptb1_fixture.sql and rptb1_fixture2.sql (hand-computed numbers in their headers). The hooks (docs/integration/RPT-B1_hooks.sql) are installed by THIS file after the "before"
-- snapshot. Test data only (test_* names).
-- Ledger costs in the fixture: item A 60, item B 30 (place 1), item A 60 (place 2), test_fin = weighted average of two runs = 200 / 18 = 11.1111 per piece. The price list (item_costs) is EMPTY.
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
create or replace function tt.has_note(p_j jsonb, p_code text) returns boolean language sql immutable as $$ select exists (select 1 from jsonb_array_elements(p_j -> 'notes') n where n ->> 'code' = p_code) $$;
create or replace function tt.note(p_j jsonb, p_code text) returns jsonb language sql immutable as $$ select n from jsonb_array_elements(p_j -> 'notes') n where n ->> 'code' = p_code limit 1 $$;
create or replace function tt.row_of(p_j jsonb, p_key text, p_val text) returns jsonb language sql immutable as $$ select e from jsonb_array_elements(p_j -> 'rows') e where e ->> p_key = p_val limit 1 $$;
create or replace function tt.num(p_j jsonb, p_path text[]) returns numeric language sql immutable as $$ select (p_j #>> p_path)::numeric $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
select tt.today() as td \gset
create or replace function tt.cases() returns table (k text, g text) language sql as $$
  values ('item_sales', 'item'), ('item_sales', 'category'), ('item_sales', 'total'), ('item_sales', 'day'), ('category_sales', 'category'), ('category_sales', 'item'), ('sales_summary', 'total'),
    ('sales_summary', 'day'), ('sales_summary', 'location'), ('sales_combined', 'location'), ('sales_combined', 'brand') $$;
create or replace function tt.snapshot(p_phase text) returns void language plpgsql as $$
declare c record;
begin
  for c in select * from tt.cases() loop
    insert into tt.snap select p_phase, c.k || '|' || c.g, public.report_run(c.k, '{"preset":"last_7"}'::jsonb, c.g);
  end loop;
  insert into tt.snap select p_phase, 'biz_items', coalesce(jsonb_agg(to_jsonb(b) order by b.code), '[]') from public.biz_items(tt.today() - 6, tt.today(), null) b;
end $$;
-- keys that the earlier packages (R1) and the notes add: not part of the comparison
create or replace function tt.same_old(b jsonb, n jsonb) returns boolean language plpgsql as $$
declare r jsonb; nr jsonb; found boolean; nk text[] := array['returns_amt', 'net_after_returns', 'returns_qty', 'qty_after_returns', 'refund_paid', 'net_after_refunds'];
begin
  if tt.omit(b -> 'totals', nk) is distinct from tt.omit(n -> 'totals', nk) then raise notice 'totals differ'; return false; end if;
  if (select coalesce(jsonb_agg(c), '[]') from jsonb_array_elements(b -> 'columns') c) is distinct from (select coalesce(jsonb_agg(c), '[]') from jsonb_array_elements(n -> 'columns') c where c ->> 'key' <> all (nk)) then raise notice 'columns differ'; return false; end if;
  for r in select e from jsonb_array_elements(b -> 'rows') e loop
    found := false;
    for nr in select e from jsonb_array_elements(n -> 'rows') e loop if tt.omit(nr, nk) = r then found := true; exit; end if; end loop;
    if not found then raise notice 'old row missing: %', r; return false; end if;
  end loop;
  for nr in select e from jsonb_array_elements(n -> 'rows') e loop      -- a row that is only in the new answer must be a return-only group (R1): no sale in it
    found := false;
    for r in select e from jsonb_array_elements(b -> 'rows') e loop if tt.omit(nr, nk) = r then found := true; exit; end if; end loop;
    if not found and coalesce((nr ->> 'net')::numeric, 0) <> 0 then raise notice 'extra row is not return-only: %', nr; return false; end if;
  end loop;
  return true;
end $$;
create or replace function tt.sn(p_phase text, p_k text) returns jsonb language sql stable as $$ select j from tt.snap where phase = p_phase and k = p_k $$;

\echo == T0 shape: the setting, the view, the closed internals
select tt.chk('T0 phase402 present; the setting exists: a choice, default price_list, English labels (bn = mix = en)', to_regprocedure('public._rptb1_p402_present()') is not null
  and (select kind = 'choice' and default_value = '"price_list"'::jsonb and choices = '["price_list","ledger_first"]'::jsonb and label_bn = label_en and label_mix = label_en and label_en !~ '[^ -~]' and hint_en !~ '[^ -~]' and module = 'reports' from rules where key = 'reports_cost_basis'));
select tt.chk('T0 the setting reads price_list by default', public._rptb1_cost_basis() = 'price_list' and rule_txt('reports_cost_basis') = 'price_list');
select tt.chk('T0 the view is closed to browsers; internals closed; biz_cost_status open to signed-in users only', not has_table_privilege('authenticated','public.rpt_line_cost','select') and not has_table_privilege('anon','public.rpt_line_cost','select')
  and not has_function_privilege('authenticated','public._rptb1_biz_item_cost(date,date,integer)','execute') and not has_function_privilege('authenticated','public._rptb1_cost_notes(jsonb,jsonb,integer[],date,date,boolean,boolean)','execute')
  and not has_function_privilege('authenticated','public._rptb1_item_cost_split(date,date,integer)','execute') and has_function_privilege('authenticated','public.biz_cost_status(date,date,integer)','execute') and not has_function_privilege('anon','public.biz_cost_status(date,date,integer)','execute'));
select tt.chk('T0 no hook of section 3 yet', not exists (select 1 from jsonb_each_text(public._rptb1_hooked402()) where value = 'true'));
select tt.chk('T0 the view gives the ledger cost per line: A 60, B 30, test_fin 11.1111; the price list is empty', (select count(*) from rpt_line_cost where cost_src = 'ledger') = (select count(*) from sales_fact_t where item_id is not null and status in ('done', 'void'))
  and (select max(cost_price) from rpt_line_cost c join sales_fact_t t using (sale_id, line_no) join items i on i.id = t.item_id where i.code = 'RB1-A') = 60
  and (select round(max(cost_price), 4) from rpt_line_cost c join sales_fact_t t using (sale_id, line_no) join items i on i.id = t.item_id where i.code = 'RB1-FG') = 11.1111);

\echo == T1 BEFORE the hooks (the audit finding D2)
select tt.as(:'o');
select tt.snapshot('before');
select tt.chk('T1 D2: item sales shows cost "-" and 100 % uncosted although the ledger knows the cost', (select bool_and(e -> 'cogs' = 'null'::jsonb and (e ->> 'uncosted_pct')::numeric = 100) from jsonb_array_elements(tt.sn('before', 'item_sales|item') -> 'rows') e));
select tt.chk('T1 the margin report knows the cost (cogs of item A, net of returns, is 540)', (select (r ->> 'cogs')::numeric = 540 from jsonb_array_elements(public.report_run2('l2_margin', '{"preset":"last_7"}'::jsonb) -> 'rows') r where r ->> 'item_code' = 'RB1-A'));

\echo == T2 install the hooks
\ir ../docs/integration/RPT-B1_hooks.sql
select tt.chk('T2 every hook site carries its marker (5 + 5 + 3)', (select bool_and(value::boolean) from jsonb_each_text(public._rptb1_hooked())) and (select bool_and(value::boolean) from jsonb_each_text(public._rptb1_hooked401()))
  and (select bool_and(value::boolean) from jsonb_each_text(public._rptb1_hooked402())) and (select count(*) from jsonb_each_text(public._rptb1_hooked402())) = 3);
select md5(pg_get_functiondef('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)'::regprocedure) || pg_get_functiondef('public.biz_items(date,date,integer)'::regprocedure) || pg_get_functiondef('public.report_run(text,jsonb,text,text,integer,boolean)'::regprocedure)) as h1 \gset
\ir ../docs/integration/RPT-B1_hooks.sql
select tt.chk('T2 pasting the hooks again changes nothing', md5(pg_get_functiondef('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)'::regprocedure) || pg_get_functiondef('public.biz_items(date,date,integer)'::regprocedure) || pg_get_functiondef('public.report_run(text,jsonb,text,text,integer,boolean)'::regprocedure)) = :'h1');
select tt.chk('T2 the count-in-business rule (bos14) is kept: still in rpt_agg_sql, and in the helper that biz_items now calls', position('bos14' in pg_get_functiondef('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)'::regprocedure)) > 0
  and position('count_in_business' in pg_get_functiondef('public._rptb1_biz_item_cost(date,date,integer)'::regprocedure)) > 0);
select tt.as(:'o');
select tt.snapshot('default');

\echo == T3 DEFAULT KEEPS TODAY: with the setting at price_list every old figure of every report is the one from before the hooks
select tt.chk('T3 ' || b.k || ' (old columns, rows and totals identical)', tt.same_old(b.j, d.j)) from tt.snap b join tt.snap d on d.k = b.k and d.phase = 'default' where b.phase = 'before' and b.k <> 'biz_items' order by b.k;
select tt.chk('T3 biz_items: exactly the same rows as before the hooks (all 60 items, every column); the sold item A has no cost (price list empty)', tt.sn('before', 'biz_items') = tt.sn('default', 'biz_items') and jsonb_array_length(tt.sn('default', 'biz_items')) = 60
  and (select e -> 'cogs' = 'null'::jsonb from jsonb_array_elements(tt.sn('default', 'biz_items')) e where e ->> 'code' = 'RB1-A'));
select tt.chk('T3 the SQL text of the cost join is the text of today with the default setting (no ledger view in the query)',
  position('rpt_line_cost' in public.rpt_agg_sql('line', 'public.sales_fact', 'f', array['item'], array['qty', 'cogs'], 'true', null, null, '{T}.day', 6, 101, false, false, true)) = 0
  and position('cbi.count_in_business' in public.rpt_agg_sql('line', 'public.sales_fact', 'f', array['item'], array['qty', 'cogs'], 'true', null, null, '{T}.day', 6, 101, false, false, true)) > 0);

\echo == T4 the notes (both settings)
select tt.sn('default', 'item_sales|item') as is_d \gset
select tt.chk('T4 default basis: the unknown-cost note says the cost of 2200 (100 %) is unknown, what is needed, in both languages', (select (n ->> 'unknown_rev')::numeric = 2200 and (n ->> 'unknown_pct')::numeric = 100 and n ->> 'text_en' like '%item master%' and n ->> 'text_en' like '%Needed%' and n ->> 'text_bn' like '%দরকার%'
     from (select tt.note(:'is_d'::jsonb, 'cost_unknown') n) z));
select tt.chk('T4 default basis: the hint says the ledger holds a cost for those 2200 and names the setting', (select (n ->> 'ledger_could_cost_rev')::numeric = 2200 and n ->> 'text_en' like '%Report cost basis%' from (select tt.note(:'is_d'::jsonb, 'cost_basis_hint') n) z));
select tt.chk('T4 the note also sits under sales summary and combined sales and category sales, not under reports without cost', tt.has_note(tt.sn('default', 'sales_summary|total'), 'cost_unknown') and tt.has_note(tt.sn('default', 'sales_combined|location'), 'cost_unknown')
  and tt.has_note(tt.sn('default', 'category_sales|category'), 'cost_unknown') and not tt.has_note(public.report_run('hour_weekday', '{"preset":"last_7"}'::jsonb), 'cost_unknown') and not tt.has_note(public.report_run('receipt_register', '{"preset":"last_7"}'::jsonb), 'cost_unknown'));

\echo == T5 the owner switches to ledger first
select set_rule('reports_cost_basis', '"ledger_first"') is null as w_s \gset
select tt.err('T5 the setting refuses a value that is not a choice', $$select set_rule('reports_cost_basis', '"both"')$$, 'bad_value');
select tt.chk('T5 the change is in audit_log', exists (select 1 from audit_log where table_name = 'rules' and record_id = 'reports_cost_basis'));
select tt.snapshot('ledger');
select tt.sn('ledger', 'item_sales|item') as is_l \gset
select tt.chk('T5 item A: sold 11, cost 11 x 60 = 660, profit 440, 40 %, uncosted 0', tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-A'), '{cogs}') = 660 and tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-A'), '{gp}') = 440
  and tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-A'), '{gp_pct}') = 40 and tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-A'), '{uncosted_pct}') = 0);
select tt.chk('T5 item B: 14 x 30 = 420, profit 280; test_fin: 4 x 11.1111 = 44.44, profit 355.56', tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-B'), '{cogs}') = 420 and tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-B'), '{gp}') = 280
  and tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-FG'), '{cogs}') = 44.44 and tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-FG'), '{gp}') = 355.56);
select tt.chk('T5 THE ALIGNMENT: item sales cost less the cost of the returned goods equals the margin report cost (A: 660 - 2 x 60 = 540; B: 420 - 4 x 30 = 300)',
  tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-A'), '{cogs}') - tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-A'), '{returns_qty}') * 60 = (select (r ->> 'cogs')::numeric from jsonb_array_elements(public.report_run2('l2_margin', '{"preset":"last_7"}'::jsonb) -> 'rows') r where r ->> 'item_code' = 'RB1-A')
  and tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-B'), '{cogs}') - tt.num(tt.row_of(:'is_l'::jsonb, 'item_code', 'RB1-B'), '{returns_qty}') * 30 = (select (r ->> 'cogs')::numeric from jsonb_array_elements(public.report_run2('l2_margin', '{"preset":"last_7"}'::jsonb) -> 'rows') r where r ->> 'item_code' = 'RB1-B'));
select tt.chk('T5 sales summary total: cost 1124.44 = 660 + 420 + 44.44, profit 1075.56, uncosted 0 %', tt.num(tt.sn('ledger', 'sales_summary|total'), '{totals,cogs}') = 1124.44 and tt.num(tt.sn('ledger', 'sales_summary|total'), '{totals,gp}') = 1075.56
  and tt.num(tt.sn('ledger', 'sales_summary|total'), '{totals,uncosted_pct}') = 0);
select tt.chk('T5 category: test_cat_one = A 660 + test_fin 44.44 = 704.44', tt.num(tt.row_of(tt.sn('ledger', 'category_sales|category'), 'category', 'test_cat_one'), '{cogs}') = 704.44);
select tt.chk('T5 by location the costs add up to the total', (select sum((e ->> 'cogs')::numeric) from jsonb_array_elements(tt.sn('ledger', 'sales_combined|location') -> 'rows') e) = 1124.44);
select tt.chk('T5 the NON-cost columns are exactly the ones of today (qty, net, bills ...)', (select bool_and(tt.omit(d, array['cogs', 'gp', 'gp_pct', 'uncosted_pct']) = tt.omit(l, array['cogs', 'gp', 'gp_pct', 'uncosted_pct']))
  from jsonb_array_elements(tt.sn('default', 'item_sales|item') -> 'rows') d join jsonb_array_elements(:'is_l'::jsonb -> 'rows') l on l ->> 'item_id' = d ->> 'item_id'));
select tt.chk('T5 nothing is unknown any more: no cost_unknown, no estimate note, no hint', not tt.has_note(:'is_l'::jsonb, 'cost_unknown') and not tt.has_note(:'is_l'::jsonb, 'cost_estimate') and not tt.has_note(:'is_l'::jsonb, 'cost_basis_hint'));

\echo == T6 unknown stays unknown; the price list is only a fallback, and it is said to be an estimate
-- a quick sale with no item (cost can never be known), an untracked item with a typed cost, and a tracked item whose stock came in with NO cost
insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,category) values ('RB1-C','test_item_c','test_item_c','piece','piece',60,false,'finished_good','test_cat_two'), ('RB1-D','test_item_d','test_item_d','piece','piece',40,true,'finished_good','test_cat_two');
select id as i_c from items where code = 'RB1-C' \gset
select id as i_d from items where code = 'RB1-D' \gset
insert into item_costs (item_id, cost_price) values (:'i_c'::uuid, 30);
select stock_opening(:'i_d'::uuid, 1, 10, null) is not null as w_od \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":90}]'::jsonb,0,'[{"mode":"cash","amount":90}]','','','retail',null,true) ->> 'id' as s_q \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":60}]',:'i_c')::jsonb,0,'[{"mode":"cash","amount":120}]','','','retail',null,false) ->> 'id' as s_c \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":40}]',:'i_d')::jsonb,0,'[{"mode":"cash","amount":40}]','','','retail',null,false) ->> 'id' as s_d \gset
select public.report_run('item_sales', '{"preset":"last_7"}'::jsonb, 'item') as is2 \gset
select tt.chk('T6 item C (untracked, price list 30): cost 2 x 30 = 60 from the price list, profit 60', tt.num(tt.row_of(:'is2'::jsonb, 'item_code', 'RB1-C'), '{cogs}') = 60 and tt.num(tt.row_of(:'is2'::jsonb, 'item_code', 'RB1-C'), '{gp}') = 60);
select tt.chk('T6 item D (stock came in with no cost, no typed cost): cost EMPTY, profit EMPTY, 100 % uncosted - never 0', (select e -> 'cogs' = 'null'::jsonb and e -> 'gp' = 'null'::jsonb and (e ->> 'uncosted_pct')::numeric = 100 from (select tt.row_of(:'is2'::jsonb, 'item_code', 'RB1-D') e) z));
select tt.chk('T6 the quick sale line (no item) is in the unknown amount: 90 + 40 = 130 unknown, 130 / 2450 = 5.3 %', (select (n ->> 'unknown_rev')::numeric = 130 and round((n ->> 'unknown_pct')::numeric, 1) = 5.3 and n ->> 'text_en' like '%no stock-ledger cost and no cost in the item master%' from (select tt.note(:'is2'::jsonb, 'cost_unknown') n) z));
select tt.chk('T6 the price-list part is called an estimate: 120 of sales, in both languages', (select (n ->> 'price_list_rev')::numeric = 120 and n ->> 'text_en' like '%price list%estimate%' and n ->> 'text_bn' like '%অনুমান%' from (select tt.note(:'is2'::jsonb, 'cost_estimate') n) z));
select tt.chk('T6 a line where one ledger row has no cost is not half-costed with the other rows: all-or-nothing (item D is unknown, not 0)', (select count(*) from rpt_line_cost c join sales_fact_t t using (sale_id, line_no) where t.item_id = :'i_d'::uuid and c.cost_price is null) = 1);
select tt.chk('T6 the sales summary total keeps profit only on the costed part: uncosted % = 130 / 2450', round(tt.num(public.report_run('sales_summary', '{"preset":"last_7"}'::jsonb, 'total'), '{totals,uncosted_pct}'), 2) = round(100 * 130 / 2450.0, 2));

\echo == T7 business analysis (biz_items) and its status
select * into temp table biz_l from public.biz_items(:'td'::date - 6, :'td'::date, null);
select tt.chk('T7 biz_items with ledger first: item A cost = 11 x 60 = 660 (empty before), item B 14 x 30 = 420, test_fin 44.44 (the average of its two runs)',
  (select cogs from biz_l where code = 'RB1-A') = 660 and (select cogs from biz_l where code = 'RB1-B') = 420 and round((select cogs from biz_l where code = 'RB1-FG'), 2) = 44.44);
select tt.chk('T7 biz_items: item C from the price list (60), item D empty', (select cogs from biz_l where code = 'RB1-C') = 60 and (select cogs from biz_l where code = 'RB1-D') is null);
select public.biz_cost_status(:'td'::date - 6, :'td'::date, null) as bs \gset
select tt.chk('T7 biz_cost_status: basis ledger_first; revenue 2450; from the ledger 2200 (sales returned are not netted here); from the price list 120; unknown 130 (quick line 90 + item D 40)',
  :'bs'::jsonb ->> 'basis' = 'ledger_first' and tt.num(:'bs'::jsonb, '{revenue}') = 2450 and tt.num(:'bs'::jsonb, '{ledger_rev}') = 2200 and tt.num(:'bs'::jsonb, '{price_list_rev}') = 120 and tt.num(:'bs'::jsonb, '{unknown_rev}') = 130);
select tt.chk('T7 biz_cost_status for place 2 only: 400 from the ledger, nothing unknown', (select (s ->> 'ledger_rev')::numeric = 400 and (s ->> 'unknown_rev')::numeric = 0 from (select public.biz_cost_status(:'td'::date - 6, :'td'::date, 2) s) z));
select tt.err('T7 biz_cost_status refuses a range over 400 days', format($$select public.biz_cost_status(%L, %L, null)$$, :'td'::date - 500, :'td'::date), 'bad_range');

\echo == T8 back to the default: the figures of today return
select set_rule('reports_cost_basis', '"price_list"') is null as w_b \gset
select tt.as(:'o');
select tt.chk('T8 setting back to price_list: item sales cost is empty again for items A, B, test_fin; item C keeps its price-list cost', (select bool_and(e -> 'cogs' = 'null'::jsonb) from jsonb_array_elements(public.report_run('item_sales', '{"preset":"last_7"}'::jsonb, 'item') -> 'rows') e where e ->> 'item_code' in ('RB1-A', 'RB1-B', 'RB1-FG'))
  and tt.num(tt.row_of(public.report_run('item_sales', '{"preset":"last_7"}'::jsonb, 'item'), 'item_code', 'RB1-C'), '{cogs}') = 60);
select tt.chk('T8 biz_items cost is empty again for item A (the price list has no row)', (select cogs from public.biz_items(:'td'::date - 6, :'td'::date, null) where code = 'RB1-A') is null);
select * into temp table biz_p from public.biz_items(:'td'::date - 6, :'td'::date, null);
select tt.chk('T8 biz_items: between the two settings only the cost column moved (revenue, quantity, shares and the ABC class are identical for all 62 items)',
  (select count(*) from biz_l l join biz_p p using (item_id) where l.revenue = p.revenue and l.qty = p.qty and l.share_pct = p.share_pct and l.cum_pct = p.cum_pct and l.abc = p.abc) = (select count(*) from biz_l) and (select count(*) from biz_l) = 62);

\echo == T9 who sees what
select set_rule('reports_cost_basis', '"ledger_first"') is null as w_s2 \gset
insert into user_grants (user_id, grant_code, location_id) values (:'st', 'report_sales', null) on conflict do nothing;
set role authenticated; select tt.as(:'st');
select report_run('item_sales', '{"preset":"last_7"}'::jsonb, 'item') as is_st \gset
select tt.chk('T9 a salesperson without the cost right: no cost columns, no cost notes (the cost stays secret)', not (:'is_st'::jsonb -> 'totals' ? 'cogs') and not tt.has_note(:'is_st'::jsonb, 'cost_unknown') and not tt.has_note(:'is_st'::jsonb, 'cost_estimate') and not tt.has_note(:'is_st'::jsonb, 'cost_basis_hint') and tt.has_note(:'is_st'::jsonb, 'cost_hidden'));
select tt.err('T9 biz_cost_status is refused without the right', format($$select public.biz_cost_status(%L, %L, null)$$, :'td'::date - 6, :'td'::date), 'not allowed');
select tt.err('T9 the setting cannot be changed by a salesperson', $$select set_rule('reports_cost_basis', '"price_list"')$$, 'not allowed');
reset role; delete from user_grants where user_id = :'st'::uuid and grant_code = 'report_sales'; select tt.as(:'o');

\echo == T10 pasting phase402 again, books
select count(*) as n_rules from rules where key = 'reports_cost_basis' \gset
select md5(pg_get_functiondef('public._rptb1_cost_notes(jsonb,jsonb,integer[],date,date,boolean,boolean)'::regprocedure) || pg_get_functiondef('public._rptb1_biz_item_cost(date,date,integer)'::regprocedure)) as h2 \gset
\ir phase402.sql
select tt.chk('T10 phase402 again: one setting row, the chosen value kept, helpers unchanged, hooks in place', (select count(*) from rules where key = 'reports_cost_basis') = :n_rules and rule_txt('reports_cost_basis') = 'ledger_first'
  and md5(pg_get_functiondef('public._rptb1_cost_notes(jsonb,jsonb,integer[],date,date,boolean,boolean)'::regprocedure) || pg_get_functiondef('public._rptb1_biz_item_cost(date,date,integer)'::regprocedure)) = :'h2'
  and (select bool_and(value::boolean) from jsonb_each_text(public._rptb1_hooked402())));
select tt.chk('T10 nothing was posted: every journal entry balances and the sales / returns / ledger are the fixture''s', not exists (select 1 from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z) and (select count(*) from sale_returns) = 4);

select 'RESULT: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from tt.res;
select name from tt.res where not ok;
