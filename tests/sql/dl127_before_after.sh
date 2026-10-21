#!/bin/bash
# Dealer business (phases 127-129) proof of "sweets behaviour unchanged": on a build WITHOUT phase127/128/129 (e.g. final_build.sh <db> with them removed from ORDER), seed the A3/A5 scenario
# (phase118_test.sql), fingerprint several existing report functions, paste phase127, 128, 129, fingerprint again, diff. Prints OK / DIFFERENT. (Same pattern as tests/sql/b1_before_after.sh.)
# usage: bash tests/sql/dl127_before_after.sh <db_without_127_129> [<scratch_db_name>]    (the db is cloned; the clone is dropped at the end)  env PGSOCK=/tmp PGPORT=5544
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}
PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-5544}; PSQL="psql -h $PGSOCK -p $PGPORT -U postgres"
SRC=$1; DB=${2:-dl127_ba_$$}
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
select 'sale_payments_rows ' || count(*) || ' ' || coalesce(sum(amount), 0) from sale_payments;
select 'supplier_payments_rows ' || count(*) || ' ' || coalesce(sum(amount), 0) from supplier_payments;
select 'customer_dues ' || md5(coalesce((select string_agg(to_jsonb(r)::text, '|' order by to_jsonb(r)::text) from customer_dues() r), ''));
select 'can_loc_def ' || md5(pg_get_functiondef('public.can_loc'::regproc));
select 'old_functions ' || md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text))
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.proname !~ '(cheque|scheme|claim_|tint_|post_dated|^_dl_)';
select 'rules_other ' || md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r where key not in ('dealer_cheque_on', 'dealer_scheme_on', 'dealer_tint_on');
SQL
$PSQL -d $DB -qAt -f $FP > /tmp/b1_before.txt 2>&1
for ph in phase127 phase128 phase129; do $PSQL -d $DB -qAt -v ON_ERROR_STOP=1 -f "$REPO/supabase/$ph.sql" > /dev/null 2>&1 || echo "$ph paste FAILED"; done
$PSQL -d $DB -qAt -f $FP > /tmp/b1_after.txt 2>&1
cat /tmp/b1_before.txt
if diff -q /tmp/b1_before.txt /tmp/b1_after.txt >/dev/null; then echo "DEALER BEFORE/AFTER: OK (identical, $(wc -l < /tmp/b1_before.txt) fingerprints)"; else echo "DEALER BEFORE/AFTER: DIFFERENT"; diff /tmp/b1_before.txt /tmp/b1_after.txt; fi
$PSQL -q -c "drop database if exists $DB" >/dev/null 2>&1; rm -f $FP
