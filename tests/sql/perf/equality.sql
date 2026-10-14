-- Result-equality capture (EXPLAIN-independent). Prints one line per case:  EQ <name> <md5> (<rows>)
-- Run it on a database BEFORE phase110 and on a clone AFTER phase110, then diff the EQ lines (see equality.sh).
-- Reports are run as the owner; the date window follows the data (last sale date), so it also works on the e2e scenario DB.
-- Everything runs inside a transaction that is rolled back (set_rule for the three cost modes, acct_post_pending).
\set ON_ERROR_STOP off
\pset tuples_only on
select user_id as own from user_roles where role_code = 'owner' order by user_id limit 1 \gset
select coalesce(max(sale_date), current_date) as dmax from sales \gset
select set_config('perf.dmax', :'dmax', false) is not null as x0 \gset
create or replace function pg_temp.eq(p_name text, p_sql text) returns void language plpgsql as $$
declare h text; n bigint;
begin
  execute 'select md5(coalesce(string_agg(x::text, ''|'' order by x::text), ''<empty>'')), count(*) from (' || p_sql || ') x' into h, n;
  raise notice 'EQ % % (% rows)', p_name, h, n;
exception when others then raise notice 'EQ % ERROR %', p_name, sqlerrm;
end $$;
create or replace function pg_temp.rr(p_name text, p_key text, p_from date, p_to date, p_group text) returns void language plpgsql as $$
declare r jsonb; flt jsonb := jsonb_build_object('from', p_from::text, 'to', p_to::text, 'locations', (select jsonb_agg(id) from locations));
begin
  r := public.report_run(p_key, flt, p_group);
  perform pg_temp.eq(p_name || ' rows', format('select e from jsonb_array_elements(%L::jsonb -> ''rows'') e', r::text));
  perform pg_temp.eq(p_name || ' totals', format('select %L::jsonb -> ''totals''', r::text));
  perform pg_temp.eq(p_name || ' cols', format('select %L::jsonb -> ''cols''', r::text));
exception when others then raise notice 'EQ % ERROR %', p_name, sqlerrm;
end $$;
create or replace function pg_temp.cases(p_tag text, p_long boolean) returns void language plpgsql as $$
declare dm date := current_setting('perf.dmax')::date; d30 date := dm - 30; d365 date := dm - 365; locs int[] := (select array_agg(id) from locations);
begin
  perform pg_temp.eq(p_tag || ' biz_daily 30d', format('select * from biz_daily(%L, %L, null)', d30, dm));
  perform pg_temp.eq(p_tag || ' biz_items 30d', format('select * from biz_items(%L, %L, null)', d30, dm));
  perform pg_temp.eq(p_tag || ' _p27_pl 30d', format('select * from _p27_pl(%L, %L, %L)', d30, dm, locs));
  perform pg_temp.eq(p_tag || ' _cogs_lines72 30d', format('select * from _cogs_lines72(%L, %L, %L)', d30, dm, locs));
  perform pg_temp.eq(p_tag || ' items_with_cost', 'select * from items_with_cost()');
  perform pg_temp.eq(p_tag || ' _item_cost_eff88', 'select * from _item_cost_eff88()');
  perform pg_temp.rr(p_tag || ' item_sales item 30d', 'item_sales', d30, dm, 'item');
  perform pg_temp.rr(p_tag || ' item_sales category 30d', 'item_sales', d30, dm, 'category');
  perform pg_temp.rr(p_tag || ' category_sales category 30d', 'category_sales', d30, dm, 'category');
  perform pg_temp.rr(p_tag || ' sales_summary day 30d', 'sales_summary', d30, dm, 'day');
  perform pg_temp.rr(p_tag || ' sales_combined location 30d', 'sales_combined', d30, dm, 'location');
  perform pg_temp.rr(p_tag || ' quick_unlisted line_kind 30d', 'quick_unlisted', d30, dm, 'line_kind');
  perform pg_temp.rr(p_tag || ' sales_trend day 30d (no cost)', 'sales_trend', d30, dm, 'day');
  if p_long then
    perform pg_temp.eq(p_tag || ' biz_daily 365d', format('select * from biz_daily(%L, %L, null)', d365, dm));
    perform pg_temp.eq(p_tag || ' biz_items 365d', format('select * from biz_items(%L, %L, null)', d365, dm));
    perform pg_temp.eq(p_tag || ' _p27_pl 365d', format('select * from _p27_pl(%L, %L, %L)', d365, dm, locs));
    perform pg_temp.rr(p_tag || ' item_sales item 365d', 'item_sales', d365, dm, 'item');
    perform pg_temp.rr(p_tag || ' sales_summary day 365d', 'sales_summary', d365, dm, 'day');
    perform pg_temp.rr(p_tag || ' category_sales category 365d', 'category_sales', d365, dm, 'category');
  end if;
end $$;

\echo == default cost source
begin;
select set_config('request.jwt.claim.sub', :'own', true) is not null as x \gset
select pg_temp.cases('default', true);
-- the other functions (not cost-source dependent)
select pg_temp.eq('inventory_vs_gl today', 'select inventory_vs_gl(current_date, null)');
select pg_temp.eq('inventory_vs_gl dmax', format('select inventory_vs_gl(%L, null)', :'dmax'::date));
select pg_temp.eq('unmatched_forms default', 'select unmatched_forms()');
select pg_temp.eq('unmatched_forms 365d', format('select unmatched_forms(%L, %L, null)', :'dmax'::date - 365, :'dmax'::date));
select pg_temp.eq('_acct_docs', 'select * from _acct_docs(_acct_start())');
select pg_temp.eq('_acct_stock_moves85', 'select * from _acct_stock_moves85(_acct_start())');
select pg_temp.eq('acct_post_pending dry', $q$select acct_post_pending(true, 5000) - 'preview'$q$);
select pg_temp.eq('acct_post_pending dry preview', $q$select acct_post_pending(true, 5000) -> 'preview'$q$);
select pg_temp.eq('inbox_list 100', 'select inbox_list(null, null, 100)');
select pg_temp.eq('inbox_list new 50 loc1', $q$select inbox_list(1, 'new', 50)$q$);
select pg_temp.eq('item history audit', $q$select id, action, table_name, record_id from audit_log where table_name = 'items' order by id desc limit 100$q$);
rollback;

\echo == real posting, then journal compare (rolled back)
begin;
select set_config('request.jwt.claim.sub', :'own', true) is not null as x \gset
select acct_post_pending(false, 5000) is not null as posted \gset
select pg_temp.eq('journal after post', $q$select e.source_type, e.source_id, e.entry_date, e.location_id, e.memo, e.status, e.flags, l.line_no, l.account_id, l.debit, l.credit, l.location_id lloc, l.party_type, l.party_id from journal_entries e join journal_lines l on l.entry_id = e.id$q$);
select pg_temp.eq('trial balance', $q$select l.account_id, sum(l.debit) d, sum(l.credit) c from journal_lines l group by 1$q$);
select 'EQ trial balance diff ' || coalesce(sum(debit) - sum(credit), 0) from journal_lines;
rollback;

\echo == cost source ledger_avg / item_costs / ledger_then_item_costs
begin;
select set_config('request.jwt.claim.sub', :'own', true) is not null as x \gset
select set_rule('report_cost_source', '"ledger_avg"'::jsonb) is not null as y \gset
select pg_temp.cases('ledger_avg', false);
rollback;
begin;
select set_config('request.jwt.claim.sub', :'own', true) is not null as x \gset
select set_rule('report_cost_source', '"item_costs"'::jsonb) is not null as y \gset
select pg_temp.cases('item_costs', false);
rollback;
begin;
select set_config('request.jwt.claim.sub', :'own', true) is not null as x \gset
select set_rule('report_cost_source', '"ledger_then_item_costs"'::jsonb) is not null as y \gset
select pg_temp.cases('ledger_then_item_costs', false);
rollback;
