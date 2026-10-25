#!/usr/bin/env python3
"""Integrator tool: converts the docs/integration/<pkg>_info.json files of the packages (several shapes) into the entry shape of web/data/info.json
(docs/integration/INFO-1.md section 4) and merges them with tools/check_info_coverage.py --merge.

Key rule: a setting that is seeded in supabase/*.sql (insert into rules, or a *_rule_seed( call) becomes rule:<key>; a grant seeded in grant_defs becomes grant:<key>;
everything else (screens, reports, columns, captures, features) becomes feature:<name>. A key that already exists is kept (first package wins) and listed.
usage: python3 tools/merge_pkg_info.py [--dry]
"""
import json, glob, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
DRY = '--dry' in sys.argv

sql = {}
for f in glob.glob('supabase/phase*.sql') + ['supabase/schema.sql']:
    if f.endswith('_test.sql') or not os.path.exists(f):
        continue
    sql[f] = open(f, encoding='utf8').read()


def seeded(name, table):
    pat = re.compile(r"(\(\s*|seed\(\s*)'%s'\s*," % re.escape(name))
    for f, t in sql.items():
        if table == 'rules' and re.search(r'insert\s+into\s+(public\.)?rules\b|_rule_seed\(', t, re.I) and pat.search(t):
            return True
        if table == 'grant_defs' and re.search(r'insert\s+into\s+(public\.)?grant_defs\b', t, re.I) and pat.search(t):
            return True
    return False


ia = open('web/ia.js', encoding='utf8').read()
ROUTES = set(re.findall(r"rec\('([a-z0-9_]+)'", ia))
info_now = json.load(open('web/data/info.json', encoding='utf8'))['entries']


def one(s):
    s = re.sub(r'\s+', ' ', str(s or '')).strip()
    if len(s) > 410:
        cut = s[:410]
        k = max(cut.rfind('. '), cut.rfind('; '))
        s = cut[:k + 1] if k > 150 else cut.rsplit(' ', 1)[0] + '...'
    return s


def sentences(s):
    return [x.strip() for x in re.findall(r'[^.!?]+[.!?]+(?=\s|$)|[^.!?]+$', s) if x.strip()]


def lim(s, n):
    # the (i) sheet keeps each part short (tests/web/infohint_test.js): does 1-3 sentences, why 1, change 1-2. The full text stays in the package note.
    parts = sentences(s)
    return ' '.join(parts[:n]) if len(parts) > n else s


def sane(name):
    return re.sub(r'[^a-z0-9_]+', '_', name.lower()).strip('_')


def convert(pkg, e):
    key = e.get('key') or e.get('route')
    kind = e.get('kind')
    title = e.get('title') or e.get('label') or e.get('title_en') or key
    does = e.get('what_it_does') or e.get('info_en') or ''
    out = {'title': one(title)[:120], 'does': lim(one(does), 3),
           'why': lim(one(e.get('why_it_matters')), 1), 'default': one(e.get('default')),
           'change': lim(one(e.get('what_changes_if_switched') or e.get('if_switched')), 2),
           'who': one(e.get('who_can_change')), 'verified': True, 'src': pkg + ' (docs/integration/%s_info.json)' % pkg}
    miss = e.get('missing_field_named')
    if not (out['why'] and out['default'] and out['change'] and out['who']):
        out['verified'] = False
        for k in ('why', 'default', 'change', 'who'):
            if not out[k]:
                out.pop(k)
        if miss:
            out['does'] = lim(one(lim(out['does'], 2) + ' Missing data is shown as "data not captured: ' + str(miss) + '".'), 3)
    names = [x.strip() for x in str(key).split(' / ')]
    res = {}
    for nm in names:
        if kind in ('setting', None, 'right', 'grant') and seeded(nm, 'rules') and kind in ('setting', None):
            k = 'rule:' + nm
        elif kind in ('grant', 'right') or (kind is None and seeded(nm, 'grant_defs')):
            k = 'grant:' + nm if seeded(nm, 'grant_defs') else 'feature:' + sane(nm)
        elif kind == 'screen' and nm in ROUTES:
            k = 'screen:' + nm
        else:
            k = 'feature:' + sane(nm.replace('feature_', '', 1) if nm.startswith('feature_') else nm)
        res[k] = out
    return res


files = sorted(glob.glob('docs/integration/*_info.json'))
total_new = 0
kept = []
for f in files:
    pkg = os.path.basename(f)[:-len('_info.json')]
    d = json.load(open(f, encoding='utf8'))
    ent = d.get('entries', d) if isinstance(d, dict) else d
    if isinstance(ent, dict):
        conv = {k: dict(v, **{f: lim(v[f], n) for f, n in (('does', 3), ('why', 1), ('change', 2)) if isinstance(v.get(f), str)}) for k, v in ent.items()}      # already in the web/data/info.json shape
    else:
        conv = {}
        for e in ent:
            conv.update(convert(pkg, e))
    new = {k: v for k, v in conv.items() if k not in info_now}
    for k in conv:
        if k in info_now:
            kept.append((pkg, k))
    if not new:
        continue
    tmp = os.path.join(tempfile.mkdtemp(), pkg + '.json')
    json.dump({'entries': new}, open(tmp, 'w', encoding='utf8'), ensure_ascii=False, indent=1)
    cmd = [sys.executable, 'tools/check_info_coverage.py', '--merge', tmp] + (['--dry'] if DRY else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    print(pkg, r.stdout.strip().replace('\n', ' | ')[:300], r.stderr.strip()[:200])
    if not DRY:
        info_now = json.load(open('web/data/info.json', encoding='utf8'))['entries']
    else:
        info_now = dict(info_now, **new)
    total_new += len(new)
print('merged entries:', total_new, ' kept (already there, first wins):', kept)
