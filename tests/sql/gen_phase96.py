#!/usr/bin/env python3
"""Builds supabase/phase96.sql = phase96_parts/10_head.sql + re-created functions + phase96_parts/20_tail.sql.
The re-created functions are taken from the LATEST definition in a database built through the last earlier phase (pass its name),
then only the lines marked bos96 are changed (plain text substitutions; every one must hit exactly the expected number of times).
Re-run this after phase89 (INT2) is merged: build a DB through phase89, run   python3 tests/sql/gen_phase96.py <db>   and commit the result.
usage: gen_phase96.py <dbname> [outfile]"""
import re, subprocess, sys, os
db = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, 'supabase', 'phase96.sql')
parts = os.path.join(root, 'tests', 'sql', 'phase96_parts')

def psql(sql):
    r = subprocess.run(['psql', '-h', '/tmp', '-p', '5544', '-U', 'postgres', '-d', db, '-qAt', '-c', sql], capture_output=True, text=True)
    if r.returncode: sys.exit(r.stderr)
    return r.stdout.rstrip('\n')

def fdef(sig):
    return psql("select pg_get_functiondef('public.%s'::regprocedure)" % sig)

TAG = '/* bos96 */'
# (signature, [(old, new, expected_count)])
SUBS = [
 ('_acct_inv_split72(text[],text,text[],integer)', [
   ("from public.stock_ledger l join public.items it on it.id = l.item_id", "from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id " + TAG, 1)]),
 ('_acct_stock_moves85(date)', [
   ("from public.stock_ledger l join public.items it on it.id = l.item_id left join public.stock_ledger o on o.id = l.reverses_id",
    "from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id left join public.stock_ledger o on o.id = l.reverses_id " + TAG, 1),
   ("select s.unit_cost from public.stock_ledger s where s.reason = 'transfer_out'", "select s.unit_cost from public.stock_ledger_eff96 s where s.reason = 'transfer_out'", 1),
   ("  where m.cls is not null and m.d >= cfg.f\n",
    "  where m.cls is not null and m.d >= cfg.f\n"
    "    and not (m.cls = 'opening' and exists (select 1 from public.opening_stock_actions96 a where m.id = any (a.covered_ids) and (a.location_id is null or a.location_id = m.location_id))) /* bos96: an opening that a decision of the opening-stock helper covers is not posted twice */\n", 1)]),
 ('_pvar85(uuid)', [
   ("from public.stock_ledger l join public.items it", "from public.stock_ledger_eff96 l join public.items it " + TAG, 1)]),
 ('_acct_docs(date)', [
   ("from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c",
    "from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c", 1),
   ("from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c",
    "from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c", 1),
   ("from public.stock_ledger s where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c",
    "from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c", 1)]),
 ('inventory_vs_gl(date,integer)', [
   ("from public.stock_ledger sl join public.items it on it.id = sl.item_id\n            where public._acct_inv_key(it.item_type) = k",
    "from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id /* bos96 */\n            where public._acct_inv_key(it.item_type) = k", 1),
   ("from public.stock_ledger sl join public.items it on it.id = sl.item_id\n                                where sl.ref_type = 'purchase' and sl.reason = 'purchase_return'",
    "from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id /* bos96 */\n                                where sl.ref_type = 'purchase' and sl.reason = 'purchase_return'", 1),
   ("e.source_type in ('opening', 'stock_opening') /* bos85 */", "e.source_type in ('opening', 'stock_opening', 'opening_stock96') /* bos85 bos96 */", 1)]),
]

head = open(os.path.join(parts, '10_head.sql')).read()
tail = open(os.path.join(parts, '20_tail.sql')).read()
body = []
guard = []
for sig, subs in SUBS:
    d = fdef(sig)
    tags = sorted(set(re.findall(r'bos\d+', d)) - {'bos96'})
    for old, new, n in subs:
        c = d.count(old)
        if c != n:
            sys.exit('substitution for %s hit %d times (expected %d): %r' % (sig, c, n, old[:80]))
        d = d.replace(old, new)
    if 'bos96' not in d: sys.exit('no bos96 tag in ' + sig)
    body.append(d.rstrip() + ';\n')
    guard.append((sig, tags))

g = ["do $g$ declare d text; t text[]; ok boolean := true; begin"]
for sig, tags in guard:
    g.append("  d := pg_get_functiondef('public.%s'::regprocedure);" % sig)
    g.append("  if position('bos96' in d) = 0 then")
    g.append("    select array_agg(distinct m[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') m;")
    g.append("    if t is not null and not (t <@ array[%s]::text[]) then raise exception 'phase96: %s carries tags newer than the ones this file was built from (%%); re-run tests/sql/gen_phase96.py on a database built through the latest phase', t; end if;" % (', '.join("'%s'" % x for x in tags) if tags else "''", sig.split('(')[0]))
    g.append("  end if;")
g.append("end $g$;\n")
head = head.replace('-- @@BODY_GUARD@@', '-- BODY GUARD: the live function must not carry a tag this file does not know (it would be overwritten by an older body)\n' + '\n'.join(g))
sep = "\n-- ---------- re-created functions (latest definitions, only bos96 lines changed; generated by tests/sql/gen_phase96.py from database '%s') ----------\n" % 'built through the last earlier phase'
open(out, 'w').write(head + sep + '\n'.join(body) + '\n' + tail)
print('wrote', out, os.path.getsize(out))
