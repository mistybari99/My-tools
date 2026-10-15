-- COPY of phase110_test.sql for the chain with phase114 + phase115 (BATCH 2): a re-paste of an older phase puts the older body of functions that 114/115 patch back, so this copy pastes 114/115 again after it (re-paste rule, docs/PASTE_ORDER.md section N). Assertions otherwise as in phase110_test.sql.
-- FRESH DB ONLY. Phase 110 tests (Step Perf: indexes + set-based / materialized report costs; results must be IDENTICAL to before).
--   Build: bash tests/sql/final_build.sh <db> "<canonical order from docs/PASTE_ORDER.md ... phase103 phase106 phase107 phase108 phase110>"
--   Run from the REPO ROOT (it pastes phase110.sql again):
--     psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase110_test.sql | grep -E "FAIL|RESULT"
--   Method: every patched function is compared with its previous body on the SAME data (the previous body is rebuilt from the new text by undoing the one change,
--   run, then the new body is restored by pasting phase110 again). The big-data equality (biz_daily, _p27_pl, biz_items, report_run, inventory_vs_gl, unmatched_forms,
--   _acct_docs on the 60k-line seed and on the e2e DB) is tests/sql/perf/equality.sh; the time budget is tests/sql/perf/budget.py.
--   Test data only, no real names.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
-- md5 of a query result (rows as text, order independent) and its row count, as 'md5:count'
create or replace function tt.h(p_sql text) returns text language plpgsql as $$
declare h text; n bigint;
begin execute 'select md5(coalesce(string_agg(x::text, ''|'' order by x::text), ''<empty>'')), count(*) from (' || p_sql || ') x' into h, n; return h || ':' || n;
exception when others then return 'ERR:' || sqlerrm; end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
create table if not exists tt.cur (name text primary key, def text);
truncate tt.cur;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','sales2@s.app','{"full_name":"Sales"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1) on conflict do nothing;
select tt.as(:'o');

\echo == T0 shape: eight indexes, valid, the right columns
select tt.chk('T0 stock_ledger (ref_id, ref_type)', pg_get_indexdef('public.stock_ledger_refid_idx'::regclass) like '%(ref_id, ref_type)%');
select tt.chk('T0 stock_ledger (item_id, location_id, reason, made_at)', pg_get_indexdef('public.stock_ledger_item_loc_reason_idx'::regclass) like '%(item_id, location_id, reason, made_at)%');
select tt.chk('T0 production_runs ((id::text)) and purchase_bills ((id::text))', pg_get_indexdef('public.production_runs_idtext_idx'::regclass) like '%((id)::text)%' and pg_get_indexdef('public.purchase_bills_idtext_idx'::regclass) like '%((id)::text)%');
select tt.chk('T0 partial last-cost index', pg_get_indexdef('public.stock_ledger_lastcost_idx'::regclass) like '%(item_id, id DESC)%WHERE%unit_cost%');
select tt.chk('T0 audit_log history index and partial view index', pg_get_indexdef('public.audit_log_tbl_rec_id_idx'::regclass) like '%(table_name, record_id, id DESC)%'
  and pg_get_indexdef('public.audit_log_view_at_idx'::regclass) like '%(table_name, at)%' and pg_get_indexdef('public.audit_log_view_at_idx'::regclass) like '%view%');
select tt.chk('T0 stock_ledger (reason, made_at)', pg_get_indexdef('public.stock_ledger_reason_made_idx'::regclass) like '%(reason, made_at)%');
select tt.chk('T0 all eight are valid and ready', (select count(*) from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname in ('stock_ledger_reason_made_idx','stock_ledger_refid_idx','stock_ledger_item_loc_reason_idx','production_runs_idtext_idx','purchase_bills_idtext_idx','stock_ledger_lastcost_idx','audit_log_tbl_rec_id_idx','audit_log_view_at_idx') and i.indisvalid and i.indisready) = 8);
select tt.chk('T0 the six functions carry their marker (bos110 on four, perf110 on inbox_list / _acct_stock_moves85) and kept their older tags',
  (select count(*) from pg_proc where oid in ('public._cogs_lines72(date,date,integer[])'::regprocedure, 'public._item_cost_eff88()'::regprocedure, 'public._rcs88()'::regprocedure) and prosrc like '%bos110%') = 3
  and (select prosrc like '%bos110%' and prosrc like '%bos14%' and prosrc like '%bos88%' from pg_proc where proname = 'rpt_agg_sql')
  and (select prosrc like '%bos80%' and prosrc like '%bos88%' and prosrc like '%bos89%' from pg_proc where proname = '_cogs_lines72')
  and (select prosrc like '%bos96%' and prosrc like '%bos103%' and prosrc like '%perf110%' and prosrc not like '%bos110%' from pg_proc where proname = '_acct_stock_moves85')
  and (select prosrc like '%bos99%' and prosrc like '%bos103%' and prosrc like '%perf110%' and prosrc not like '%bos110%' from pg_proc where proname = 'inbox_list'));
select tt.chk('T0 AS MATERIALIZED is in _cogs_lines72 and _item_cost_eff88', (select prosrc ~* 'rcs as materialized' from pg_proc where proname = '_cogs_lines72') and (select prosrc ~* 'm as materialized' from pg_proc where proname = '_item_cost_eff88'));
select tt.chk('T0 internal functions stay closed to anon / authenticated', not has_function_privilege('anon','public._rcs88()','execute') and not has_function_privilege('authenticated','public._rcs88()','execute')
  and not has_function_privilege('authenticated','public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)','execute') and not has_function_privilege('anon','public._acct_stock_moves85(date)','execute'));

\echo == fixtures: 6 items, 6 sales (one void), a return, stock rows of every reason, 3 inbox messages
select acct_set_start(current_date - 30) is not null as a1 \gset
select set_rule('accounting_on', 'true') is null as a2 \gset
select set_rule('acct_count_adjust', 'true') is null as a3 \gset
select set_rule('acct_stock_opening', 'true') is null as a4 \gset
select set_rule('acct_issue_out', 'true') is null as a5 \gset
select set_rule('acct_transfer_mode', '"location_tagged"') is null as a6 \gset
select set_rule('inbox_on', 'true') is null as a7 \gset
select set_rule('inbox_pii_guard_on', 'true') is null as a8 \gset
set session_replication_role = replica;
insert into items (id, code, name_bn, name_en, category, unit, base_unit, sell_price, is_active, tracked, item_type, source, sellable, count_in_business) values
 (md5('t110a')::uuid, 'T110A', 'A', 'A', 'cat1', 'pc', 'pc', 50, true, true, 'resale', 'bought', true, true),   -- ledger cost on every row
 (md5('t110b')::uuid, 'T110B', 'B', 'B', 'cat1', 'pc', 'pc', 50, true, true, 'resale', 'bought', true, true),   -- one ledger row without cost -> list cost
 (md5('t110c')::uuid, 'T110C', 'C', 'C', 'cat2', 'pc', 'pc', 50, true, true, 'resale', 'bought', true, true),   -- no ledger row -> list cost
 (md5('t110d')::uuid, 'T110D', 'D', 'D', 'cat2', 'pc', 'pc', 50, true, true, 'resale', 'bought', true, true),   -- ledger cost 0, no list cost -> unknown
 (md5('t110e')::uuid, 'T110E', 'E', 'E', 'cat2', 'pc', 'pc', 50, true, true, 'resale', 'bought', true, false),  -- not counted in the business
 (md5('t110f')::uuid, 'T110F', 'F', 'F', 'cat1', 'pc', 'pc', 50, true, true, 'resale', 'bought', true, true);   -- free-cost item
insert into item_costs (item_id, cost_price) values (md5('t110a')::uuid, 8), (md5('t110b')::uuid, 6), (md5('t110c')::uuid, 7), (md5('t110e')::uuid, 9);
insert into item_cost_flags (item_id, cost_free) values (md5('t110f')::uuid, true);
create or replace function tt.ln(p_item text, p_qty numeric, p_amt numeric) returns jsonb language sql as $$
  select jsonb_build_object('item_id', md5(p_item)::uuid, 'code', upper(right(p_item, 5)), 'name', p_item, 'unit', 'pc', 'qty', p_qty, 'price', p_amt / nullif(p_qty, 0), 'amount', p_amt, 'override', false) $$;
create or replace function tt.sale(p_n int, p_days int, p_lines jsonb, p_status text default 'done') returns void language plpgsql as $$
declare t numeric := (select coalesce(sum((e->>'amount')::numeric), 0) from jsonb_array_elements(p_lines) e);
begin
  insert into public.sales (id, client_id, location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, quick, status, created_by, created_staff, sale_type, paid, due_amount)
  values (md5('t110s' || p_n)::uuid, md5('t110c' || p_n)::uuid, 1, 9000 + p_n, current_date - p_days, now() - make_interval(days => p_days, mins => 3), p_lines, t, 0, t, 'cash', false, p_status,
          '00000000-0000-0000-0000-000000000001', 'OWN1', 'retail', t, 0);
end $$;
select tt.sale(1, 3, jsonb_build_array(tt.ln('t110a', 2, 100), tt.ln('t110b', 1, 50), tt.ln('t110c', 1, 50)));
select tt.sale(2, 4, jsonb_build_array(tt.ln('t110a', 1, 50), tt.ln('t110a', 2, 100), tt.ln('t110b', 1, 50)));      -- the same item on two lines
select tt.sale(3, 5, jsonb_build_array(tt.ln('t110d', 1, 50), tt.ln('t110e', 1, 50), tt.ln('t110f', 2, 100)));
select tt.sale(4, 5, jsonb_build_array(tt.ln('t110a', 1, 50)), 'void');
select tt.sale(5, 6, jsonb_build_array(tt.ln('t110a', 3, 150)));                                                     -- ledger holds 1 of the 3 sold: cost = ledger cost / sold qty
select tt.sale(6, 7, jsonb_build_array(tt.ln('t110a', 0, 0), tt.ln('t110b', 2, 100)));                              -- qty 0 line: cost = ledger cost / ledger qty
create or replace function tt.led(p_item text, p_qty numeric, p_cost numeric, p_reason text, p_reftype text, p_ref text, p_days int default 3, p_loc int default 1) returns void language sql as $$
  insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by)
  values (md5(p_item)::uuid, p_loc, p_qty, p_cost, p_reason, p_reftype, p_ref, now() - make_interval(days => p_days, mins => 2), '00000000-0000-0000-0000-000000000001') $$;
select tt.led('t110a', -2, 10, 'sale_out', 'sale', md5('t110s1')::uuid::text, 3);
select tt.led('t110b', -0.5, 5, 'sale_out', 'sale', md5('t110s1')::uuid::text, 3);
select tt.led('t110b', -0.5, 0, 'sale_out', 'sale', md5('t110s1')::uuid::text, 3);
select tt.led('t110a', -3, 11, 'sale_out', 'sale', md5('t110s2')::uuid::text, 4);
select tt.led('t110b', -1, 4, 'issue_out', 'sale_pack', md5('t110s2')::uuid::text, 4);
select tt.led('t110d', -1, 0, 'sale_out', 'sale', md5('t110s3')::uuid::text, 5);
select tt.led('t110e', -1, 3, 'sale_out', 'sale', md5('t110s3')::uuid::text, 5);
select tt.led('t110f', -2, 0, 'sale_out', 'sale', md5('t110s3')::uuid::text, 5);
select tt.led('t110a', -1, 10, 'sale_out', 'sale', md5('t110s4')::uuid::text, 5);
select tt.led('t110a', -1, 12, 'sale_out', 'sale', md5('t110s5')::uuid::text, 6);
select tt.led('t110a', -2, 12, 'sale_out', 'sale', md5('t110s6')::uuid::text, 7);
select tt.led('t110b', -2, 5, 'sale_out', 'sale', md5('t110s6')::uuid::text, 7);
-- a return of one A from sale 1, with its ledger row
insert into public.sale_returns (id, sale_id, location_id, lines, amount, credit_amount, reason_code, status, created_by, created_staff, created_at)
values (md5('t110r1')::uuid, md5('t110s1')::uuid, 1, jsonb_build_array(tt.ln('t110a', 1, 50)), 50, 50, 'wrong_item', 'done', '00000000-0000-0000-0000-000000000001', 'OWN1', now() - interval '2 days');
select tt.led('t110a', 1, 10, 'sale_return', 'sale_return', md5('t110r1')::uuid::text, 2);
-- stock rows of every reason the autopost stock-move branch looks at
select tt.led('t110a', 5, 8, 'count_adjust', 'count', 'c1', 3);
select tt.led('t110b', -2, 6, 'count_adjust', 'count', 'c2', 3);
select tt.led('t110c', 10, 7, 'opening', 'opening', null, 4);
select tt.led('t110a', -4, 8, 'issue_out', 'issue', 'f1', 3);                -- a posted issue slip (class issue)
select tt.led('t110b', -2, 6, 'issue_out', 'entry', 'f2', 3);                -- a form entry (class issue)
select tt.led('t110c', -3, 7, 'issue_out', 'production', 'p1', 3);           -- a production issue: never posted here
select tt.led('t110c', -1, 7, 'issue_out', 'sale', 'sx', 3);                 -- a sale issue: never posted here
select tt.led('t110a', -1, 8, 'issue_out', null, null, 3);                   -- an issue with no type
select tt.led('t110a', -3, 8, 'transfer_out', 'transfer', 't1', 3, 1);
select tt.led('t110a', 3, 0, 'transfer_in', 'transfer', 't1', 3, 2);
select tt.led('t110d', 6, 0, 'production_in', 'production', 'no-run', 3);    -- a direct production-in without a recipe run
select tt.led('t110e', 4, 2, 'count_adjust', 'count', 'c3', 2);
insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, created_by, reverses_id)
select item_id, location_id, -qty_delta, unit_cost, 'reversal', ref_type, ref_id, made_at + interval '1 minute', created_by, id from public.stock_ledger where ref_id = 'c3';
insert into sales_channels (code, kind, name_bn, location_id, active) values ('t110_tg', 'telegram', 'T110 Telegram', null, true);
insert into inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, msg_time, received_at, status)
select (select id from sales_channels where code = 't110_tg'), 1 + (k % 2), 'x' || k, '@h' || k, 'Cust ' || k, 'order message ' || k || ' please call 01712345678', now() - make_interval(mins => k), now() - make_interval(mins => k), case when k % 2 = 0 then 'new' else 'seen' end
from generate_series(1, 6) k;
reset session_replication_role;
select report_fact_rebuild() is not null as rf \gset
select tt.chk('F0 fixtures: 6 sales (5 done + 1 void), 17+ ledger rows, 6 inbox messages', (select count(*) from sales where client_id in (select md5('t110c' || n)::uuid from generate_series(1, 6) n)) = 6
  and (select count(*) from stock_ledger where created_by = :'o') >= 25 and (select count(*) from inbound_messages) = 6 and (select count(*) from sales_fact where sale_id = md5('t110s2')::uuid) >= 3);

\echo == T1 _rcs88: same answer as the old two-lookup body for every setting
create or replace function tt.rcs_old() returns text language sql stable as $$
  select case when public.rule_txt('report_cost_source') in ('ledger_avg', 'item_costs', 'ledger_then_item_costs') then public.rule_txt('report_cost_source') else 'ledger_then_item_costs' end $$;
do $$ declare v text; ok boolean := true; bad text := '';
begin
  foreach v in array array['"ledger_avg"', '"item_costs"', '"ledger_then_item_costs"', '"weird"', '""', 'null', '5', 'true'] loop
    update public.rules set value = v::jsonb where key = 'report_cost_source';
    if public._rcs88() is distinct from tt.rcs_old() then ok := false; bad := bad || ' ' || v; end if;
  end loop;
  update public.rules set value = null where key = 'report_cost_source';
  if public._rcs88() is distinct from tt.rcs_old() then ok := false; bad := bad || ' (value null)'; end if;
  update public.rules set value = null, default_value = '"item_costs"' where key = 'report_cost_source';
  if public._rcs88() is distinct from tt.rcs_old() or public._rcs88() <> 'item_costs' then ok := false; bad := bad || ' (default item_costs)'; end if;
  update public.rules set default_value = '"ledger_then_item_costs"' where key = 'report_cost_source';
  create temp table rr_save as select * from public.rules where key = 'report_cost_source';
  delete from public.rules where key = 'report_cost_source';
  if public._rcs88() is distinct from tt.rcs_old() or public._rcs88() <> 'ledger_then_item_costs' then ok := false; bad := bad || ' (no rule row)'; end if;
  insert into public.rules select * from rr_save;
  perform tt.chk('T1 _rcs88 = old body for 8 values, null, default value and a missing rule row' || bad, ok);
end $$;
select tt.chk('T1 the rule row is back (default ledger_then_item_costs)', public._rcs88() = 'ledger_then_item_costs');

\echo == T2 _cogs_lines72 and _item_cost_eff88: identical to the same text without AS MATERIALIZED, in all three cost modes
insert into tt.cur values ('cogs', pg_get_functiondef('public._cogs_lines72(date,date,integer[])'::regprocedure)), ('eff', pg_get_functiondef('public._item_cost_eff88()'::regprocedure));
create or replace function tt.cogs_h() returns text language sql as $$ select tt.h('select * from public._cogs_lines72(current_date - 30, current_date, array[1,2,3])') $$;
create or replace function tt.eff_h() returns text language sql as $$ select tt.h('select * from public._item_cost_eff88()') $$;
create or replace function tt.set_mode(p text) returns void language plpgsql as $$
begin update public.rules set value = to_jsonb(p) where key = 'report_cost_source'; end $$;
create temp table th (k text primary key, v text);
select tt.set_mode('ledger_then_item_costs');
insert into th values ('cogs_new_a', tt.cogs_h()), ('eff_new_a', tt.eff_h());
select tt.set_mode('ledger_avg');
insert into th values ('cogs_new_b', tt.cogs_h()), ('eff_new_b', tt.eff_h());
select tt.set_mode('item_costs');
insert into th values ('cogs_new_c', tt.cogs_h()), ('eff_new_c', tt.eff_h());
do $$ begin
  execute replace((select def from tt.cur where name = 'cogs'), 'rcs as materialized (select', 'rcs as (select');
  execute replace((select def from tt.cur where name = 'eff'), 'm as materialized (select', 'm as (select');
end $$;
select tt.set_mode('ledger_then_item_costs');
insert into th values ('cogs_old_a', tt.cogs_h()), ('eff_old_a', tt.eff_h());
select tt.set_mode('ledger_avg');
insert into th values ('cogs_old_b', tt.cogs_h()), ('eff_old_b', tt.eff_h());
select tt.set_mode('item_costs');
insert into th values ('cogs_old_c', tt.cogs_h()), ('eff_old_c', tt.eff_h());
do $$ begin execute (select def from tt.cur where name = 'cogs'); execute (select def from tt.cur where name = 'eff'); end $$;
select tt.chk('T2 _cogs_lines72 identical in ledger_then_item_costs / ledger_avg / item_costs and has rows', (select v from th where k = 'cogs_new_a') = (select v from th where k = 'cogs_old_a')
  and (select v from th where k = 'cogs_new_b') = (select v from th where k = 'cogs_old_b') and (select v from th where k = 'cogs_new_c') = (select v from th where k = 'cogs_old_c')
  and (select v from th where k = 'cogs_new_a') !~ ':0$' and (select v from th where k = 'cogs_new_a') <> (select v from th where k = 'cogs_new_c'));
select tt.chk('T2 _item_cost_eff88 identical in the three modes and has rows', (select v from th where k = 'eff_new_a') = (select v from th where k = 'eff_old_a')
  and (select v from th where k = 'eff_new_b') = (select v from th where k = 'eff_old_b') and (select v from th where k = 'eff_new_c') = (select v from th where k = 'eff_old_c') and (select v from th where k = 'eff_new_a') !~ ':0$');
select tt.chk('T2 the new bodies are back (AS MATERIALIZED present again)', (select prosrc ~* 'rcs as materialized' from pg_proc where proname = '_cogs_lines72') and (select prosrc ~* 'm as materialized' from pg_proc where proname = '_item_cost_eff88'));
select tt.set_mode('ledger_then_item_costs');
select tt.chk('T2 biz_daily has costed revenue and cogs > 0', (select sum(cogs) from public.biz_daily(current_date - 30, current_date, null)) > 0 and (select count(*) from public.biz_items(current_date - 30, current_date, null)) > 0
  and (select count(*) from public.items_with_cost()) >= 4);

\echo == T3 rpt_agg_sql: the set-based cost join gives the same rows as the per-row _line_cost88 join (3 modes x 4 groupings)
create or replace function tt.old_sql(p_sql text) returns text language sql as $$
  select regexp_replace(p_sql, ' left join \(with k .*?\*/ where ', ' left join lateral (select public._line_cost88(f.sale_id, f.item_id) as cost_price) c on true where ', 's') $$;
create or replace function tt.agg(p_gl text[], p_nodim boolean) returns text language sql as $$
  select public.rpt_agg_sql('line', 'public.sales_fact', 'f', p_gl, array['qty','gross','net','cogs','costed_net','net_all','gp','gp_pct','uncosted_pct'],
    format('f.day between %L and %L and f.location_id = any (%L)', current_date - 30, current_date, array[1,2,3]), '{T}.status = ''done''', null, '{T}.day', 1, 7, true, p_nodim, true) $$;
create or replace function tt.cmp(p_gl text[], p_nodim boolean) returns text language plpgsql as $$
declare q text := tt.agg(p_gl, p_nodim); o text := tt.old_sql(q); a text; b text;
begin
  if q = o or q not like '%bos110: set-based%' then return 'NOT-REWRITTEN'; end if;
  a := tt.h(q); b := tt.h(o);
  return case when a = b and a !~ ':0$' then 'same' else 'DIFF ' || a || ' / ' || b end;
end $$;
select tt.set_mode('ledger_then_item_costs');
select tt.chk('T3 mode ledger_then_item_costs: by item / category / day / no grouping', tt.cmp(array['item'], false) = 'same' and tt.cmp(array['category'], false) = 'same' and tt.cmp(array['day'], false) = 'same' and tt.cmp(array[]::text[], true) = 'same');
select tt.set_mode('ledger_avg');
select tt.chk('T3 mode ledger_avg: by item / category / day / no grouping', tt.cmp(array['item'], false) = 'same' and tt.cmp(array['category'], false) = 'same' and tt.cmp(array['day'], false) = 'same' and tt.cmp(array[]::text[], true) = 'same');
select tt.set_mode('item_costs');
select tt.chk('T3 mode item_costs: by item / category / day / no grouping', tt.cmp(array['item'], false) = 'same' and tt.cmp(array['category'], false) = 'same' and tt.cmp(array['day'], false) = 'same' and tt.cmp(array[]::text[], true) = 'same');
select tt.set_mode('ledger_then_item_costs');
-- the per-pair rule itself: ledger cost / sold qty, qty 0 -> ledger qty, partial cost -> list cost, no cost and no list cost -> unknown, not counted -> unknown unless the ledger knows it
select tt.chk('T3 per-pair costs are the documented ones (A in sale 1 = 10, A in sale 2 = 11, A in sale 5 = 12 / 3, A in sale 6 = 12, B in sale 1 = 6, C = 7, D = null, E in sale 3 = 3)',
  public._line_cost88(md5('t110s1')::uuid, md5('t110a')::uuid) = 10 and public._line_cost88(md5('t110s2')::uuid, md5('t110a')::uuid) = 11 and public._line_cost88(md5('t110s5')::uuid, md5('t110a')::uuid) = 4
  and public._line_cost88(md5('t110s6')::uuid, md5('t110a')::uuid) = 12 and public._line_cost88(md5('t110s1')::uuid, md5('t110b')::uuid) = 6 and public._line_cost88(md5('t110s1')::uuid, md5('t110c')::uuid) = 7
  and public._line_cost88(md5('t110s3')::uuid, md5('t110d')::uuid) is null and public._line_cost88(md5('t110s3')::uuid, md5('t110e')::uuid) = 3);
create or replace function tt.pairs() returns text language plpgsql as $$
declare k record; q text; bad int := 0; n int := 0;
begin
  for k in select distinct sale_id, item_id from public.sales_fact loop
    q := public.rpt_agg_sql('line', 'public.sales_fact', 'f', array[]::text[], array['qty','net','cogs','costed_net'], format('f.sale_id = %L and f.item_id = %L', k.sale_id, k.item_id), null, null, '{T}.day', 1, 7, true, true, true);
    n := n + 1;
    if tt.h(q) <> tt.h(tt.old_sql(q)) then bad := bad + 1; end if;
  end loop;
  return n || ' pairs, ' || bad || ' differ';
end $$;
select tt.set_mode('ledger_then_item_costs');
select tt.chk('T3 every (sale, item) pair of the fixtures costs the same one by one (' || tt.pairs() || ')', tt.pairs() like '1_ pairs, 0 differ' or tt.pairs() like '9 pairs, 0 differ');
select tt.set_mode('item_costs');
select tt.chk('T3 ... also in item_costs mode', tt.pairs() like '%pairs, 0 differ');
select tt.set_mode('ledger_avg');
select tt.chk('T3 ... also in ledger_avg mode', tt.pairs() like '%pairs, 0 differ');
select tt.set_mode('ledger_then_item_costs');
-- every pair through report_run's own SQL: item_sales grouped by item reports cogs = sum(qty x cost) of the pairs
select tt.chk('T3 report_run item_sales (by item) is the same with the set-based join and with the per-row join',
  (select tt.h(format($q$select * from (%s) t$q$, tt.agg(array['item'], false)))) = (select tt.h(format($q$select * from (%s) t$q$, tt.old_sql(tt.agg(array['item'], false))))));
select tt.chk('T3 report_run runs for the cost reports as owner (rows and totals present)', (select jsonb_array_length(public.report_run('item_sales', jsonb_build_object('from', (current_date - 30)::text, 'to', current_date::text, 'locations', jsonb_build_array(1,2,3)), 'item') -> 'rows')) > 0
  and (select public.report_run('sales_summary', jsonb_build_object('from', (current_date - 30)::text, 'to', current_date::text, 'locations', jsonb_build_array(1,2,3)), 'day') -> 'totals' ->> 'cogs') is not null);

\echo == T4 inbox_list: identical to the previous body (masked and unmasked users)
create or replace function public.inbox_list_old110(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare r jsonb; unmasked boolean := false; l int[];
begin
  perform public._inb_gate(p_loc, 'view');
  if p_status is not null and p_status not in ('new', 'seen', 'converted', 'ignored') then raise exception 'bad_input'; end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select coalesce(jsonb_agg(z.j order by z.rid desc), '[]'::jsonb) into r from (
    select m.id rid, jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
      'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'has_attachment', m.attachment_ref is not null,
      'handle', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('name', m.customer_name) end,
      'text', case when public._inb_contact_ok(m.location_id) then left(public._inb_pii_f99('text', m.msg_text), 200) end, 'masked', not public._inb_contact_ok(m.location_id), 'pii_mode', public._inb_pii_mode99()) j
      from public.inbound_messages m join public.sales_channels c on c.id = m.channel_id
     where m.location_id = any (l) and (p_status is null or m.status = p_status)
     order by m.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then
    perform public._inb_audit_view('inbound_messages', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$;
select tt.chk('T4 owner: all / loc 1 / status new / limit 2 / bad status error', public.inbox_list(null, null, 100)::text = public.inbox_list_old110(null, null, 100)::text and jsonb_array_length(public.inbox_list(null, null, 100)) = 6
  and public.inbox_list(1, null, 100)::text = public.inbox_list_old110(1, null, 100)::text and public.inbox_list(null, 'new', 100)::text = public.inbox_list_old110(null, 'new', 100)::text
  and public.inbox_list(null, null, 2)::text = public.inbox_list_old110(null, null, 2)::text and jsonb_array_length(public.inbox_list(null, null, 2)) = 2);
insert into rule_grants (role_code, grant_code, allowed) values ('salesperson', 'inbox_contact_view', false) on conflict (role_code, grant_code) do update set allowed = false;
select tt.as(:'s');
select tt.chk('T4 salesperson (place 1; contact data masked): same text, masked flag true', public.inbox_list(null, null, 100)::text = public.inbox_list_old110(null, null, 100)::text
  and jsonb_array_length(public.inbox_list(null, null, 100)) = 3 and (public.inbox_list(null, null, 100) -> 0 ->> 'masked') = 'true');
insert into rule_grants (role_code, grant_code, allowed) values ('salesperson', 'inbox_contact_view', true) on conflict (role_code, grant_code) do update set allowed = true;
select tt.chk('T4 salesperson with the contact grant: same text, masked false', public.inbox_list(null, null, 100)::text = public.inbox_list_old110(null, null, 100)::text and (public.inbox_list(null, null, 100) -> 0 ->> 'masked') = 'false');
select tt.as(:'o');
drop function public.inbox_list_old110(integer, text, integer);

\echo == T5 _acct_stock_moves85 and _acct_docs: identical to the previous body on stock rows of every reason
insert into tt.cur values ('moves', pg_get_functiondef('public._acct_stock_moves85(date)'::regprocedure));
create or replace function tt.moves_h() returns text language sql as $$ select tt.h('select * from public._acct_stock_moves85(public._acct_start())') $$;
create or replace function tt.docs_h() returns text language sql as $$ select tt.h('select * from public._acct_docs(public._acct_start())') $$;
create or replace function tt.post_h() returns text language sql as $$ select tt.h($q$select acct_post_pending(true, 5000) - 'preview'$q$) $$;
insert into th values ('moves_new', tt.moves_h()), ('docs_new', tt.docs_h()), ('post_new', tt.post_h());
do $$ declare d text := (select def from tt.cur where name = 'moves'); d2 text;
begin
  d2 := regexp_replace(d, E'\n +and not \\(l\\.reason = ''issue_out'' and l\\.reverses_id is null[^\n]*', '');
  if d2 = d then raise exception 'could not build the old body'; end if;
  execute d2;
end $$;
insert into th values ('moves_old', tt.moves_h()), ('docs_old', tt.docs_h()), ('post_old', tt.post_h());
do $$ begin execute (select def from tt.cur where name = 'moves'); end $$;
select tt.chk('T5 _acct_stock_moves85 identical, and it returns rows of the classes adjust / opening / issue / xfer / prodin', (select v from th where k = 'moves_new') = (select v from th where k = 'moves_old')
  and (select count(distinct cls) from public._acct_stock_moves85(public._acct_start())) >= 4);
select tt.chk('T5 _acct_docs identical (' || (select v from th where k = 'docs_new') || ')', (select v from th where k = 'docs_new') = (select v from th where k = 'docs_old') and (select v from th where k = 'docs_new') !~ ':0$');
select tt.chk('T5 acct_post_pending (dry run) identical', (select v from th where k = 'post_new') = (select v from th where k = 'post_old'));
select tt.chk('T5 the new _acct_stock_moves85 is back', (select prosrc like '%perf110%' from pg_proc where proname = '_acct_stock_moves85'));
-- production / sale issue_out rows never produce a posting
select tt.chk('T5 issue_out of type production / sale / none gives no stock-move row, issue / entry do', not exists (select 1 from public._acct_stock_moves85(public._acct_start()) m join public.stock_ledger l on l.id = m.lid where l.reason = 'issue_out' and coalesce(l.ref_type, '') not in ('issue', 'entry'))
  and (select count(*) from public._acct_stock_moves85(public._acct_start()) m join public.stock_ledger l on l.id = m.lid where l.reason = 'issue_out' and l.ref_type in ('issue', 'entry')) = 2);
-- a real post: the same journal as with the old body
begin;
select acct_post_pending(false, 5000) is not null as p1 \gset
select tt.h('select e.source_type, e.source_id, e.entry_date, e.location_id, e.memo, e.flags, l.line_no, l.account_id, l.debit, l.credit, l.location_id lloc from journal_entries e join journal_lines l on l.entry_id = e.id') as jh \gset
select coalesce(sum(debit) - sum(credit), 1)::text as tb from journal_lines \gset
rollback;
select tt.chk('T5 a real autopost balances (debit - credit = 0) and posts journal lines (' || :'jh' || ')', :'tb'::numeric = 0 and :'jh' !~ ':0$');

\echo == T6 paste twice, and a body with an unknown tag stops the paste
create temp table hh as select oid, md5(pg_get_functiondef(oid)) h from pg_proc where pronamespace = 'public'::regnamespace;
\i supabase/phase110.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase132.sql
\i supabase/phase133.sql
select tt.chk('T6 second paste changes no function at all', not exists (select 1 from pg_proc p join hh on hh.oid = p.oid where md5(pg_get_functiondef(p.oid)) <> hh.h));
select tt.chk('T6 second paste: still eight indexes, one of each', (select count(*) from pg_class where relname in ('stock_ledger_reason_made_idx','stock_ledger_refid_idx','stock_ledger_item_loc_reason_idx','production_runs_idtext_idx','purchase_bills_idtext_idx','stock_ledger_lastcost_idx','audit_log_tbl_rec_id_idx','audit_log_view_at_idx')) = 8);
insert into tt.cur values ('moves2', pg_get_functiondef('public._acct_stock_moves85(date)'::regprocedure));
do $$ begin execute replace(replace((select def from tt.cur where name = 'moves2'), 'bos96', 'bos999'), 'perf110', 'perf111'); end $$;
begin;   -- like the Supabase SQL editor: one error and nothing of the paste stays
\i supabase/phase110.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase132.sql
\i supabase/phase133.sql
rollback;
select tt.chk('T6 an unknown tag (bos999) in a target body stops the paste: the body is not replaced', (select prosrc like '%bos999%' and prosrc not like '%perf110%' and prosrc like '%perf111%' from pg_proc where proname = '_acct_stock_moves85'));
do $$ begin execute (select def from tt.cur where name = 'moves2'); end $$;
\i supabase/phase110.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase132.sql
\i supabase/phase133.sql
select tt.chk('T6 with the tag gone the paste works again (perf110 in the body)', (select prosrc like '%perf110%' and prosrc not like '%bos999%' from pg_proc where proname = '_acct_stock_moves85'));
select tt.chk('T6 no function outside the six changed by phase110 (compared with the snapshot of T6)', not exists (select 1 from pg_proc p join hh on hh.oid = p.oid where md5(pg_get_functiondef(p.oid)) <> hh.h));

\echo == T7 the indexes are used (EXPLAIN on the fixtures; the big-data effect is tests/sql/perf/index_effect.py)
create or replace function tt.plan(p_sql text) returns text language plpgsql as $$
declare r text; t text := '';
begin for r in execute 'explain ' || p_sql loop t := t || r || E'\n'; end loop; return t; end $$;
set enable_seqscan = off;
select tt.chk('T7 ref_id join can use stock_ledger_refid_idx', tt.plan($q$select 1 from sales x join stock_ledger l on l.ref_id = x.id::text and l.ref_type in ('sale', 'sale_pack') where x.sale_date >= current_date - 30$q$) ~ 'stock_ledger_(refid_idx|ref)');
select tt.chk('T7 (item, place, reason) probe uses stock_ledger_item_loc_reason_idx', tt.plan($q$select 1 from stock_ledger where item_id = md5('t110a')::uuid and location_id = 1 and reason = 'sale_out' limit 1$q$) like '%stock_ledger_item_loc_reason_idx%');
select tt.chk('T7 last positive cost probe uses stock_ledger_lastcost_idx', tt.plan($q$select unit_cost from stock_ledger where item_id = md5('t110a')::uuid and coalesce(unit_cost, 0) > 0 and qty_delta > 0 order by id desc limit 1$q$) like '%stock_ledger_lastcost_idx%');
select tt.chk('T7 id::text lookup uses the expression index', tt.plan($q$select 1 from production_runs where id::text = 'x'$q$) like '%production_runs_idtext_idx%' and tt.plan($q$select 1 from purchase_bills where id::text = 'x'$q$) like '%purchase_bills_idtext_idx%');
select tt.chk('T7 audit_log history and view queries use their indexes', tt.plan($q$select * from audit_log where table_name = 'items' and record_id = 'x' order by id desc limit 50$q$) like '%audit_log_tbl_rec_id_idx%'
  and tt.plan($q$select count(*) from audit_log where action = 'view' and table_name = 'inbound_messages' and at > now() - interval '30 days'$q$) like '%audit_log_view_at_idx%');
reset enable_seqscan;

-- clean up what the tests added to shared settings
select tt.set_mode('ledger_then_item_costs');
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
