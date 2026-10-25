#!/usr/bin/env python3
"""Stage C3 helper: enumerate the exposed SECURITY DEFINER functions of a BUILT database and say which of them are scope-aware.
usage: python3 tools/scope_enum133.py <db> [--tsv out.tsv] [--unscoped]      (env PGSOCK=/tmp PGPORT=5544)
 exposed  = EXECUTE is granted to role authenticated (in the scratch build the default privileges of Supabase are mimicked, so a function without an explicit revoke is exposed)
 aware    = its body calls a scope primitive (can_loc, can_scope, _biz_ok123, ...) directly, or calls a function that is aware (fixpoint over the call graph, by name)
 gate     = what the body checks first (owner / grant / can_do / active / uid / none), a hint for the classification, not a proof
 tables   = public tables the body mentions (words that match a table name)
Prints one line per exposed, non-aware function: kind|name(args)|gate|tables.  With --tsv writes the full list (aware ones too)."""
import os, re, subprocess, sys, collections
db = sys.argv[1]
SOCK, PORT = os.environ.get('PGSOCK', '/tmp'), os.environ.get('PGPORT', '5544')
def q(sql):
    r = subprocess.run(['psql', '-h', SOCK, '-p', PORT, '-U', 'postgres', '-d', db, '-qAt', '-F', '\x1f', '-R', '\x1e', '-c', sql], capture_output=True, text=True)
    if r.returncode: sys.exit(r.stderr)
    return [row.split('\x1f') for row in r.stdout.split('\x1e') if row.strip('\n')]
fns = q("""select p.oid, p.proname, pg_get_function_identity_arguments(p.oid), p.prosrc, p.prosecdef, has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('anon', p.oid, 'execute'),
  p.prorettype::regtype::text, (select lanname from pg_language where oid = p.prolang) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')""")
tables = {r[0] for r in q("select tablename from pg_tables where schemaname='public' union select viewname from pg_views where schemaname='public'")}
def strip(s):
    s = re.sub(r'--[^\n]*', ' ', s); s = re.sub(r'/\*.*?\*/', ' ', s, flags=re.S); return s.lower()
F = {}
for oid, name, args, src, sd, ea, an, rt, lang in fns:
    F[oid] = dict(name=name, args=args, src=strip(src), sd=sd == 't', exp=ea == 't', anon=an == 't', rt=rt, lang=lang, nargs=len([a for a in args.split(',') if a.strip()]) if args.strip() else 0, set=rt in ('record',) or rt.startswith('SETOF'))
names = collections.defaultdict(list)
for oid, f in F.items(): names[f['name']].append(oid)
word = re.compile(r'[a-z_][a-z0-9_]*')
callre = re.compile(r'([a-z_][a-z0-9_]*)\s*\(')
calls = {oid: {w for w in callre.findall(f['src']) if w in names and w != f['name']} for oid, f in F.items()}
BASE = {'can_loc', 'can_scope', 'business_of_location', '_biz_ok123', '_my_biz123', '_user_biz123', '_business_of_loc123', 'org_unit_scope', '_loc_vis123', '_shares_biz123', '_mgmt_covers123',
        '_biz_vis125', '_my_biz125', '_dl_ok127', '_caller_biz133', '_can_grant_in133'}
# has_grant(code) / can_do(form, act) WITHOUT a place, is_owner, is_active, rule_* only say who the caller is, not which rows are theirs: they never make a function aware
NOPROP = {'has_grant', 'can_grant', 'can_do', 'is_owner', 'is_active', 'rule_on', 'rule_num', 'rule_txt', 'rule_val', '_acct_view', '_acct_all', '_all_locs', 'biz_ok', 'biz_cost_ok', 'rpt_cost_ok', 'rpt_access', '_is_ops', '_org_on123'}
_LA = r'(?:p_[a-z_]*(?:loc|place|site)[a-z_]*|[a-z]+\.(?:location_id|from_location_id|to_location_id|primary_location_id)|v_loc[a-z_]*|loc|new\.[a-z_]*location_id|old\.[a-z_]*location_id)'
LOCARG = [re.compile(r'has_grant\(\s*[^,()]+,\s*' + _LA + r'\s*\)'), re.compile(r'can_do\(\s*[^,()]+,\s*[^,()]+,\s*' + _LA + r'\s*\)')]
aware = {}
for oid, f in F.items():
    if f['name'] in BASE: aware[oid] = 'primitive'
    elif calls[oid] & BASE: aware[oid] = 'direct:' + sorted(calls[oid] & BASE)[0]
    elif f['name'] not in NOPROP and any(r.search(f['src']) for r in LOCARG): aware[oid] = 'direct:grant_or_can_do_with_place'
changed = True
while changed:
    changed = False
    for oid in F:
        if oid in aware: continue
        for c in calls[oid]:
            if c not in NOPROP and any(o in aware and (F[o]['nargs'] > 0 or F[o]['set']) for o in names[c]) and not F[oid]['name'] == c:
                aware[oid] = 'via:' + c; changed = True; break
def gate(f):
    s = f['src']; g = []
    if re.search(r'is_owner\(\)', s): g.append('owner')
    if re.search(r'has_grant\(|can_grant\(', s): g.append('grant')
    if re.search(r'can_do\(', s): g.append('can_do')
    if re.search(r'auth\.uid\(\)', s): g.append('uid')
    if re.search(r'is_active\(\)', s): g.append('active')
    return '+'.join(g) or 'none'
OWNER_HARD = re.compile(r'not\s+(\(\s*)?(public\.)?(is_owner\(\)|\(?\s*public\.is_active\(\)\s+and\s+public\.is_owner\(\))\s*\)?\s*then\s+raise|not\s*\(?\s*public\.is_active\(\)\s+and\s+public\.is_owner\(\)\s*\)?\s*then\s+raise')
def owner_hard(f):
    s = f['src']
    if re.search(r'has_grant\(|can_grant\(|can_do\(|_acct_view|_loc_mgr|biz_ok|_list_mgr|_cs_view|_sheet_viewer|_setup_view|_recipe_', s): return False
    if OWNER_HARD.search(s): return True
    return bool(re.search(r'is_owner\(\)', s)) and f['sd'] and bool(re.search(r'language sql', f.get('lang', ''))) and not re.search(r'is_owner\(\)\s+or\b|\bor\s+(public\.)?is_owner\(\)', s)
def kind(f):
    s = f['src']
    w = bool(re.search(r'\b(insert\s+into|update\s+public|update\s+\w+\s+set|delete\s+from|perform\s+public\._?\w*(post|save|set|create|void|apply|record|update|delete|close|approve)\w*)', s))
    r = bool(re.search(r'\bfrom\s+(public\.)?\w+|\bjoin\s+', s))
    return ('rw' if w and r else 'w' if w else 'r' if r else 'none')
# business tables = a table with a place / unit column, or whose policy calls can_loc (the data a business must not see of another)
BT = {r[0] for r in q("""select table_name from information_schema.columns where table_schema = 'public' and column_name in ('location_id', 'from_location_id', 'to_location_id', 'primary_location_id', 'org_unit_id', 'legal_entity_id')
  union select tablename from pg_policies where schemaname = 'public' and (qual ilike '%can_loc%' or qual ilike '%_biz_ok123%')""")}
MASTER = {'items', 'customers', 'suppliers', 'recipes', 'recipe_lines', 'artisans', 'coa_accounts', 'acct_mappings', 'year_closes', 'option_lists', 'list_defs', 'item_categories', 'customer_tiers', 'gift_rules', 'unit_conversions', 'shelf_life_rules'}
rows = []
for oid, f in F.items():
    if not (f['sd'] and f['exp']) or f['rt'] == 'trigger': continue
    t = sorted(w for w in set(word.findall(f['src'])) if w in tables)
    bt = [x for x in t if x in BT and x not in ()] if False else [x for x in t if x in BT]
    direct = aware.get(oid, '').startswith(('primitive', 'direct'))
    # class: O hard owner gate (group owner only) | D direct primitive in the body | T aware only through a callee while the body touches no business table | G body touches business tables itself without a primitive (candidate gap)
    # N no business table in the body (config, own rows, masters, plumbing)
    if owner_hard(f) and not direct: cls0 = 'O'
    else: cls0 = None
    cls = cls0 or ('D' if direct else ('T' if aware.get(oid) and not bt else ('G' if bt else 'N')))
    rows.append((cls + ':' + aware.get(oid, '-'), kind(f), f['name'] + '(' + f['args'] + ')', gate(f), ','.join(t), 'anon' if f['anon'] else '', ','.join(bt)))
rows.sort(key=lambda r: (r[0][0], r[2]))
if '--tsv' in sys.argv:
    with open(sys.argv[sys.argv.index('--tsv') + 1], 'w') as fh:
        for r in rows: fh.write('\t'.join(r) + '\n')
cnt = collections.Counter(r[0][0] for r in rows)
un = [r for r in rows if r[0][0] in 'GN']
print(f'exposed security definer functions: {len(rows)}; D direct primitive {cnt["D"]}; T aware through a callee only {cnt["T"]}; G touches business tables with no primitive {cnt["G"]}; N no business table {cnt["N"]}', file=sys.stderr)
if '--unscoped' in sys.argv:
    for r in un: print('|'.join((r[0][0],) + r[1:]))
