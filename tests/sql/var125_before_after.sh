#!/bin/bash
# Phase 125/126 proof of "sweets behaves identically": on a build WITHOUT phase125 (but with phase122), seed the A3/A5 scenario (phase118_test.sql), fingerprint the existing
# reports, the item list, stock and journal totals, paste phase125.sql + phase126.sql, fingerprint again, diff. Prints OK / DIFFERENT. Pattern = tests/sql/b1_before_after.sh.
# usage: bash tests/sql/var125_before_after.sh <db_without_125> [<scratch_db_name>]    (the db is cloned; the clone is dropped at the end)  env PGSOCK=/tmp PGPORT=5544
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}
PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-5544}; PSQL="psql -h $PGSOCK -p $PGPORT -U postgres"
SRC=$1; DB=${2:-var125_ba_$$}
$PSQL -q -c "drop database if exists $DB" -c "create database $DB template $SRC" 2>&1 | grep -v NOTICE
(cd "$REPO" && $PSQL -d $DB -qAt -f supabase/phase118_test.sql 2>&1 | grep -E '^RESULT')
FP=$(mktemp)
cat > $FP <<'SQL'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false) \gset
select (current_date - 90)::text as f, current_date::text as t \gset
select 'trial_balance ' || md5(acct_trial_balance(:'f', :'t')::text);
select 'profit_truth112 ' || md5((select string_agg(r::text, '|' order by r::text) from jsonb_array_elements(profit_truth112(:'f', :'t', null)->'rows') r) || (profit_truth112(:'f', :'t', null) - 'rows')::text);   -- row order is not defined, so rows are sorted
select 'net_profit_report ' || md5(coalesce((select string_agg(to_jsonb(r)::text, '|' order by to_jsonb(r)::text) from net_profit_report(:'f', :'t') r), ''));
select 'stock_recon_statement ' || md5(coalesce((select string_agg(to_jsonb(r)::text, '|' order by to_jsonb(r)::text) from stock_recon_statement(:'f', :'t') r), ''));
select 'factory_branch_statement ' || md5(coalesce((select string_agg(to_jsonb(r)::text, '|' order by to_jsonb(r)::text) from factory_branch_statement(:'f', :'t') r), ''));
select 'brand_pnl ' || md5(brand_pnl(:'f', :'t')::text) where to_regprocedure('public.brand_pnl(date,date)') is not null;
select 'sales_rows ' || count(*) || ' ' || coalesce(sum(total), 0) from sales;
select 'stock_ledger ' || count(*) || ' ' || coalesce(sum(qty_delta), 0) from stock_ledger;
select 'journal_lines ' || count(*) || ' ' || coalesce(sum(debit), 0) || ' ' || coalesce(sum(credit), 0) from journal_lines;
select 'can_loc_def ' || md5(pg_get_functiondef('public.can_loc'::regproc));
select 'old_functions ' || md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text))
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.proname !~ '^(_biz_|_my_biz125|_var_gate125|_items_org125|_ean13_125|option_set_save|option_values_save|style_save|variants_|variant_matrix|my_businesses125|price_list|price_for125|items_search)';
select 'rules_other ' || md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r where key <> 'variants_on';
select 'items_list ' || count(*) || ' ' || coalesce(sum(sell_price), 0) || ' ' || md5(string_agg(code || '|' || name_bn || '|' || coalesce(category, '') || '|' || coalesce(unit, '') || '|' || coalesce(sell_price::text, '') || '|' || coalesce(barcode, '') || '|' || is_active::text, ';' order by id)) from items;
select 'stock_balance ' || count(*) || ' ' || coalesce(sum(qty), 0) from stock_balance;
SQL
$PSQL -d $DB -qAt -f $FP > /tmp/var125_before.txt 2>&1
$PSQL -d $DB -qAt -v ON_ERROR_STOP=1 -f "$REPO/supabase/phase125.sql" > /dev/null 2>&1 || echo "phase125 paste FAILED"
$PSQL -d $DB -qAt -v ON_ERROR_STOP=1 -f "$REPO/supabase/phase126.sql" > /dev/null 2>&1 || echo "phase126 paste FAILED"
$PSQL -d $DB -qAt -f $FP > /tmp/var125_after.txt 2>&1
cat /tmp/var125_before.txt
if diff -q /tmp/var125_before.txt /tmp/var125_after.txt >/dev/null; then echo "VAR125 BEFORE/AFTER: OK (identical, $(wc -l < /tmp/var125_before.txt) fingerprints)"; else echo "VAR125 BEFORE/AFTER: DIFFERENT"; diff /tmp/var125_before.txt /tmp/var125_after.txt; fi
$PSQL -q -c "drop database if exists $DB" >/dev/null 2>&1; rm -f $FP
