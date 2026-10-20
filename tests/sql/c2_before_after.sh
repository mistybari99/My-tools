#!/bin/bash
# Stage C2 proof "switch OFF = byte-identical behaviour": on a build WITHOUT phase132 (final_build.sh with phase132 removed from ORDER), seed the A3/A5 scenario (phase118_test.sql),
# a matrix of users (owner, a management user, staff with and without a place, a B-like user) and masters, then
#   1. fingerprint what every user can SEE through the master readers (find_customer, customer_pos_info, customer_directory, supplier_pick, scan_match_*, artisan_list, category_list,
#      item_dup_check, items_search) and through direct SELECT with the browser role on every master table (the org_unit_id column of phase132 left out),
#   2. run a fixed WRITE script through the master writers (record_sale2 with a new and an old mobile, customer_save, save_supplier, item_new, item_apply) and fingerprint the resulting rows
#      (ids, timestamps and the org_unit_id column left out) plus the report fingerprints of c1_before_after.sh,
#   3. paste phase132.sql, run the SAME script on a second clone of the before-state, fingerprint again, diff.
# Then the same read fingerprints are taken with the switch ON for the OWNER only (must be identical: the owner sees everything).
# usage: bash tests/sql/c2_before_after.sh <db_without_132> [<scratch_db_prefix>]    (the db is cloned twice; the clones are dropped at the end)  env PGSOCK=/tmp PGPORT=5544
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}
PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-5544}; PSQL="psql -h $PGSOCK -p $PGPORT -U postgres"
SRC=$1; PRE=${2:-c2_ba_$$}; DB1=${PRE}_a; DB2=${PRE}_b
for d in $DB1 $DB2; do $PSQL -q -c "drop database if exists $d" -c "create database $d template $SRC" 2>&1 | grep -v NOTICE; done
SEED=$(mktemp); FP=$(mktemp); WR=$(mktemp)
cat > $SEED <<'SQL'
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000201','m1@c2.app','{"full_name":"Mgmt One"}'),('00000000-0000-0000-0000-000000000202','s1@c2.app','{"full_name":"Staff One"}'),
 ('00000000-0000-0000-0000-000000000203','s0@c2.app','{"full_name":"Staff None"}'),('00000000-0000-0000-0000-000000000204','p1@c2.app','{"full_name":"Purchaser"}') on conflict do nothing;
update profiles set status = 'active' where id::text like '00000000-0000-0000-0000-0000000002%';
insert into user_roles values ('00000000-0000-0000-0000-000000000201','management'),('00000000-0000-0000-0000-000000000202','salesperson'),('00000000-0000-0000-0000-000000000203','salesperson'),
 ('00000000-0000-0000-0000-000000000204','purchasing') on conflict do nothing;
insert into user_locations values ('00000000-0000-0000-0000-000000000201',1),('00000000-0000-0000-0000-000000000202',1),('00000000-0000-0000-0000-000000000204',2) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values ('00000000-0000-0000-0000-000000000201','supplier_manage',null),('00000000-0000-0000-0000-000000000201','item_create',null),
 ('00000000-0000-0000-0000-000000000201','customer_manage',null),('00000000-0000-0000-0000-000000000201','recipe_view',null) on conflict do nothing;
-- masters seen by the readers
insert into suppliers (name) values ('C2 Sup One'), ('C2 Sup Two');
insert into customers (mobile, name, type) values ('01811000001', 'C2 Cust One', 'retail'), ('01811000002', 'C2 Cust Two', 'wholesale');
insert into artisans (post, name, work_type, location_id) values ('karigor', 'C2 Artisan', 'mishti', 1);
insert into item_categories (code, name_bn, name_en, name_mix, sort) values ('C2BA', 'ক', 'C2 ba category', 'C2 ba category', 98);
insert into option_lists (list_code, value_code, label_bn, label_en, label_mix, sort) values ('expense_heads', 'c2_ba', 'এ', 'C2 head', 'C2 head', 97) on conflict do nothing;
SQL
USERS="00000000-0000-0000-0000-000000000001 00000000-0000-0000-0000-000000000201 00000000-0000-0000-0000-000000000202 00000000-0000-0000-0000-000000000203 00000000-0000-0000-0000-000000000204"
{
echo "\\set ON_ERROR_STOP off"
for u in $USERS; do
cat <<SQL
select set_config('request.jwt.claim.sub', '$u', false) \\gset
select '== user $u';
select 'find_customer ' || coalesce(md5(find_customer('01811000001')::text), 'err');
select 'find_customer_none ' || coalesce(md5(find_customer('01899999999')::text), 'err');
select 'customer_pos_info ' || coalesce(md5(customer_pos_info('01811000002')::text), 'err');
select 'customer_directory ' || count(*) || ' ' || md5(coalesce(string_agg(to_jsonb(d)::text, '|' order by to_jsonb(d)::text), '')) from customer_directory(500) d;
select 'supplier_pick ' || count(*) || ' ' || md5(coalesce(string_agg(to_jsonb(d)::text, '|' order by to_jsonb(d)::text), '')) from supplier_pick() d;
select 'scan_match_suppliers ' || count(*) from scan_match_suppliers('C2 Sup One', 10);
select 'scan_match_items ' || count(*) || ' ' || md5(coalesce(string_agg(to_jsonb(d)::text, '|' order by to_jsonb(d)::text), '')) from scan_match_items('item', 10) d;
select 'artisan_list ' || coalesce(md5(artisan_list(true)::text), 'err');
select 'category_list ' || count(*) || ' ' || md5(coalesce(string_agg(to_jsonb(d)::text, '|' order by to_jsonb(d)::text), '')) from category_list(true) d;
select 'item_dup_check ' || count(*) from item_dup_check('x', 'x');
select 'items_search ' || coalesce(md5((items_search(null, null, '{}'::jsonb, 50, 0) - 'rows')::text), 'err');
select 'customer_dues ' || count(*) || ' ' || coalesce(sum(balance), 0) from customer_dues();
set role authenticated;
select 'direct ' || t || ' ' || n from (
  select 'items' t, count(*) n from items union all select 'customers', count(*) from customers union all select 'option_lists', count(*) from option_lists
  union all select 'list_defs', count(*) from list_defs union all select 'item_categories', count(*) from item_categories union all select 'item_costs', count(*) from item_costs
  union all select 'item_price_history', count(*) from item_price_history union all select 'recipes', count(*) from recipes union all select 'recipe_lines', count(*) from recipe_lines
  union all select 'unit_conversions', count(*) from unit_conversions union all select 'employees', count(*) from employees union all select 'customer_tiers', count(*) from customer_tiers) z order by t;
reset role;
SQL
done
cat <<'SQL'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false) \gset
select (current_date - 90)::text as f, current_date::text as t \gset
select '== reports';
select 'trial_balance ' || md5(acct_trial_balance(:'f', :'t')::text);
select 'net_profit_report ' || md5(coalesce((select string_agg(to_jsonb(r)::text, '|' order by to_jsonb(r)::text) from net_profit_report(:'f', :'t') r), ''));
select 'stock_recon_statement ' || md5(coalesce((select string_agg(to_jsonb(r)::text, '|' order by to_jsonb(r)::text) from stock_recon_statement(:'f', :'t') r), ''));
select 'factory_branch_statement ' || md5(coalesce((select string_agg(to_jsonb(r)::text, '|' order by to_jsonb(r)::text) from factory_branch_statement(:'f', :'t') r), ''));
select 'sales_rows ' || count(*) || ' ' || coalesce(sum(total), 0) from sales;
select 'stock_ledger ' || count(*) || ' ' || coalesce(sum(qty_delta), 0) from stock_ledger;
select 'journal_lines ' || count(*) || ' ' || coalesce(sum(debit), 0) || ' ' || coalesce(sum(credit), 0) from journal_lines;
select 'rules_other ' || md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r where key <> 'org_scope_on';
SQL
} > $FP
# the fixed WRITE script (the same text runs before and after); ids / timestamps / org_unit_id never enter a fingerprint
cat > $WR <<'SQL'
\set ON_ERROR_STOP off
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000202', false) \gset
select 'w_sale_new ' || (record_sale2('00000000-0000-0000-0000-00000000c201'::uuid, 1, format('[{"item_id":"%s","qty":1,"price":100}]', (select id from items where is_active and tracked order by code limit 1))::jsonb, 0, '[{"mode":"cash","amount":100}]', '01877000001', 'W New Cust', 'retail', null, false) ->> 'total');
select 'w_sale_old ' || (record_sale2('00000000-0000-0000-0000-00000000c202'::uuid, 1, format('[{"item_id":"%s","qty":2,"price":50}]', (select id from items where is_active and tracked order by code limit 1))::jsonb, 0, '[{"mode":"cash","amount":100}]', '01811000001', 'ignored', 'retail', null, false) ->> 'total');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000201', false) \gset
select 'w_cust_save ' || (customer_save(null, '{"mobile":"01877000002","name":"W Saved","note":"n"}'::jsonb, '00000000-0000-0000-0000-00000000c203'::uuid) ->> 'dup');
select 'w_cust_dup ' || (customer_save(null, '{"mobile":"01811000002","name":"W Dup"}'::jsonb, '00000000-0000-0000-0000-00000000c204'::uuid) ->> 'dup');
select 'w_cust_upd ' || (customer_save((select id from customers where mobile like '%1811000001'), '{"note":"upd"}'::jsonb, '00000000-0000-0000-0000-00000000c205'::uuid) ->> 'name');
select 'w_supplier ' || (select count(*) from (select save_supplier(null, '{"name":"W Supplier"}')) q);
select 'w_item_new ' || (item_new('{"name_bn":"w","name_en":"W item","unit":"pc","sell_price":11,"item_type":"finished_good"}'::jsonb) ->> 'status');
select 'w_item_apply ' || (item_apply((select id from items where code = (select code from items order by code limit 1)), '{"sell_price":123}'::jsonb) ->> 'status');
select 'w_opening ' || (select count(*) from (select stock_opening((select id from items where is_active and tracked order by code limit 1), 1, 5, 10)) q);
select '== written rows';
select 'customers ' || md5(string_agg(c.mobile || '|' || c.name || '|' || c.type || '|' || coalesce(c.note, '') || '|' || c.active::text, ';' order by c.mobile)) from customers c;
select 'suppliers ' || md5(string_agg(name || '|' || coalesce(mobile, '') || '|' || active::text, ';' order by name)) from suppliers;
select 'items ' || md5(string_agg(code || '|' || coalesce(name_en, '') || '|' || coalesce(sell_price::text, '') || '|' || is_active::text, ';' order by code)) from items;
select 'sales ' || count(*) || ' ' || sum(total) || ' ' || md5(string_agg(receipt::text || '|' || total::text || '|' || (select coalesce(c.mobile, '') from customers c where c.id = s.customer_id), ';' order by receipt::text)) from sales s;
select 'stock ' || md5(string_agg(i.code || '|' || l.location_id::text || '|' || l.qty_delta::text, ';' order by i.code, l.location_id, l.id)) from stock_ledger l join items i on i.id = l.item_id;
select 'price_history ' || count(*) from item_price_history;
select 'customer_dues_w ' || count(*) || ' ' || coalesce(sum(balance), 0) from customer_dues();
SQL
# BEFORE: seed + reads + writes on the build without phase132
(cd "$REPO" && $PSQL -d $DB1 -qAt -f supabase/phase118_test.sql 2>&1 | grep -E '^RESULT')
$PSQL -d $DB1 -qAt -f $SEED >/dev/null 2>&1
# the second clone gets the SAME seed state: copy the seeded database
$PSQL -q -c "drop database if exists $DB2" -c "create database $DB2 template $DB1" 2>&1 | grep -v NOTICE
$PSQL -d $DB1 -qAt -f $FP > /tmp/c2_before_reads.txt 2>&1
$PSQL -d $DB1 -qAt -f $WR > /tmp/c2_before_writes.txt 2>&1
# AFTER: paste phase132 on the second clone (twice), same reads, same writes
$PSQL -d $DB2 -qAt -v ON_ERROR_STOP=1 -f "$REPO/supabase/phase132.sql" > /dev/null 2>&1 || echo "phase132 paste FAILED"
$PSQL -d $DB2 -qAt -v ON_ERROR_STOP=1 -f "$REPO/supabase/phase132.sql" > /dev/null 2>&1 || echo "phase132 second paste FAILED"
$PSQL -d $DB2 -qAt -f $FP > /tmp/c2_after_reads.txt 2>&1
# switch ON, OWNER only: the reads must equal the OFF reads (taken before the writes, on the same state)
$PSQL -d $DB2 -qAt -c "update rules set value = 'true'::jsonb where key = 'org_scope_on'" >/dev/null
$PSQL -d $DB2 -qAt -f $FP > /tmp/c2_on_reads.txt 2>&1
$PSQL -d $DB2 -qAt -c "update rules set value = null where key = 'org_scope_on'" >/dev/null
$PSQL -d $DB2 -qAt -f $WR > /tmp/c2_after_writes.txt 2>&1
echo "fingerprint lines: reads $(wc -l < /tmp/c2_before_reads.txt), writes $(wc -l < /tmp/c2_before_writes.txt) (errors inside the read file: $(grep -c ERROR /tmp/c2_before_reads.txt), write file: $(grep -c ERROR /tmp/c2_before_writes.txt))"
ok=1
if diff -q /tmp/c2_before_reads.txt /tmp/c2_after_reads.txt >/dev/null; then echo "C2 READS, SWITCH OFF BEFORE/AFTER: OK (identical)"; else echo "C2 READS, SWITCH OFF BEFORE/AFTER: DIFFERENT"; diff /tmp/c2_before_reads.txt /tmp/c2_after_reads.txt | head -30; ok=0; fi
if diff -q /tmp/c2_before_writes.txt /tmp/c2_after_writes.txt >/dev/null; then echo "C2 WRITES, SWITCH OFF BEFORE/AFTER: OK (identical)"; else echo "C2 WRITES, SWITCH OFF BEFORE/AFTER: DIFFERENT"; diff /tmp/c2_before_writes.txt /tmp/c2_after_writes.txt | head -30; ok=0; fi
# every function that phase132 does NOT patch or add must be byte-identical
$PSQL -d $DB1 -qAt -c "select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' order by 1" > /tmp/c2_fn_before.txt
$PSQL -d $DB2 -qAt -c "select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and position('/* m132' in pg_get_functiondef(p.oid)) = 0 and p.proname !~ '(m132|^org_masters|^master_|132\$)' order by 1" > /tmp/c2_fn_after.txt
# the after side lists only unpatched, non-new functions: compare against the before side restricted to the same signatures (exact match; a signature may contain spaces)
python3 - <<'PY'
before = dict(l.rstrip("\n").rsplit(" ", 1) for l in open("/tmp/c2_fn_before.txt") if l.strip())
after = dict(l.rstrip("\n").rsplit(" ", 1) for l in open("/tmp/c2_fn_after.txt") if l.strip())
open("/tmp/c2_fn_before_cut.txt", "w").write("".join("%s %s\n" % (k, before.get(k, "MISSING")) for k in sorted(after)))
open("/tmp/c2_fn_after_s.txt", "w").write("".join("%s %s\n" % (k, after[k]) for k in sorted(after)))
open("/tmp/c2_fn_patched.txt", "w").write("".join("%s\n" % k for k in sorted(set(before) - set(after))))
PY
if diff -q /tmp/c2_fn_before_cut.txt /tmp/c2_fn_after_s.txt >/dev/null; then echo "C2 OTHER FUNCTIONS: OK ($(wc -l < /tmp/c2_fn_after_s.txt) functions byte-identical; $(wc -l < /tmp/c2_fn_patched.txt) patched by phase132, the rest of the difference is the new functions)"; else echo "C2 OTHER FUNCTIONS: DIFFERENT"; diff /tmp/c2_fn_before_cut.txt /tmp/c2_fn_after_s.txt | head; ok=0; fi
OWN='00000000-0000-0000-0000-000000000001'
awk -v u="$OWN" '/^== user /{p=($3==u)} /^== reports/{p=1} p' /tmp/c2_before_reads.txt > /tmp/c2_own_before.txt
awk -v u="$OWN" '/^== user /{p=($3==u)} /^== reports/{p=1} p' /tmp/c2_on_reads.txt > /tmp/c2_own_on.txt
if diff -q /tmp/c2_own_before.txt /tmp/c2_own_on.txt >/dev/null; then echo "C2 SWITCH ON, OWNER: OK (identical to before)"; else echo "C2 SWITCH ON, OWNER: DIFFERENT"; diff /tmp/c2_own_before.txt /tmp/c2_own_on.txt | head -20; ok=0; fi
for d in $DB1 $DB2; do $PSQL -q -c "drop database if exists $d" >/dev/null 2>&1; done; rm -f $FP $SEED $WR
[ $ok = 1 ] && echo "C2 BEFORE/AFTER: ALL OK" || echo "C2 BEFORE/AFTER: SOME DIFFERENT"
