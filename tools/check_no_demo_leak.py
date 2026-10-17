#!/usr/bin/env python3
"""Guard: demo material (docs/demo) must never reach the app or the database.
Run from the repo root:  python3 tools/check_no_demo_leak.py   (exit 0 = clean, 1 = leak found)
Checks (read-only, writes nothing):
  1. App code (web/ except tests, supabase/*.sql except *_test.sql, data/, tools/ except tests, .github/) must not mention docs/demo,
     a demo file name, or a demo staff name (Karim, Salma, Rahim, ...).
  2. web/data/kb.json (the knowledge base shipped to the browser) must not contain them either.
  3. tools/build_kb.py must not read docs/demo or glob docs/*.md broadly.
  6. Test files (tests/, *_test.sql, *_test.js, test_*.py) are scanned for the same roster names, in any letter case ("karim02" counts).
     Test files that already carried such names when this check was added are frozen in tools/demo_leak_test_baseline.json (file -> count of hits,
     never the names themselves): the count may go DOWN but never up, and any other test file must have none. New fixtures use neutral test_* names.
     To refresh the baseline after removing names:  python3 tools/check_no_demo_leak.py --write-baseline   (refuses to raise a count or add a file).
"""
import json, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEMO_FILES = ['DEMO_DAY_SCREENS_STORIES_LEDGER_EN', 'DEMO_FULL_WORKFLOW_AND_LEDGER', 'DEMO_STAFF_ROSTER', 'FINAL_DEMO_BUSINESS_GUIDE',
              'IMAGINED_FUTURE_SYSTEM_DEMO', 'REAL_LIFE_DAILY_WORKFLOW_GUIDE', 'REAL_LIFE_STORY_GUIDE']
NAMES = ['Karim', 'Salma', 'Rahim', 'Ayesha', 'Shirin', 'Lipi', 'Nasrin', 'Tania', 'Jamal', 'Selim', 'Mitu', 'Hasan', 'Fatema', 'Ruma', 'Anwar', 'Sohel', 'Nazia']
PAT = re.compile(r'docs/demo|' + '|'.join(DEMO_FILES) + r'|\b(?:' + '|'.join(NAMES) + r')\b')
SKIP_DIRS = {'.git', '.claude', 'node_modules', 'vendor', '__pycache__'}
def is_test(rel):
    b = os.path.basename(rel)
    return rel.startswith('tests/') or b.endswith('_test.sql') or b.endswith('_test.js') or b.startswith('test_') or rel.endswith('check_no_demo_leak.py')
def scan(top):
    for d, dirs, files in os.walk(os.path.join(ROOT, top)):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
        for f in files:
            if not f.endswith(('.js', '.json', '.sql', '.py', '.html', '.css', '.csv', '.yml', '.yaml', '.ts', '.md', '.sh')): continue
            p = os.path.join(d, f); rel = os.path.relpath(p, ROOT)
            if is_test(rel): continue
            try: txt = open(p, encoding='utf-8', errors='ignore').read()
            except OSError: continue
            for m in PAT.finditer(txt):
                yield rel, txt.count('\n', 0, m.start()) + 1, m.group(0)
bad = []
for top in ['web', 'supabase', 'data', 'tools', '.github']:
    if os.path.isdir(os.path.join(ROOT, top)): bad += list(scan(top))
kb = open(os.path.join(ROOT, 'tools', 'build_kb.py'), encoding='utf-8').read()
if re.search(r"docs['\"],\s*['\"]demo|docs/demo", kb): bad.append(('tools/build_kb.py', 0, 'reads docs/demo'))
if re.search(r"glob\([^)]*J\('docs',\s*'\*", kb): bad.append(('tools/build_kb.py', 0, "globs docs/* broadly"))
# 4. demo material must not be in the repository at all (path and name check on every file, any folder)
for d, dirs, files in os.walk(ROOT):
    dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
    rel_d = os.path.relpath(d, ROOT)
    if rel_d == os.path.join('docs', 'demo') or rel_d.startswith(os.path.join('docs', 'demo') + os.sep):
        bad.append((rel_d, 0, 'docs/demo folder must not exist in the repository'))
    for f in files:
        if any(f.startswith(x) for x in DEMO_FILES):
            bad.append((os.path.join(rel_d, f), 0, 'demo file committed'))
# 5. a document naming many demo staff at once is demo material (ordinary tests use one or two first names)
for d, dirs, files in os.walk(os.path.join(ROOT, 'docs')):
    for f in files:
        if not f.endswith('.md') or f in ('BUILD_PLAN_GAPS.md', 'BUILD-LOG.md'): continue
        t = open(os.path.join(d, f), encoding='utf-8', errors='ignore').read()
        if len({n for n in NAMES if re.search(r'\b' + n + r'\b', t)}) >= 5:
            bad.append((os.path.relpath(os.path.join(d, f), ROOT), 0, '5 or more demo staff names in one document'))
# 6. test files: the roster names are frozen at the baseline (ratchet), nothing new may carry them
TEST_PAT = re.compile(r'(?<![A-Za-z])(?:' + '|'.join(NAMES) + r')(?![A-Za-z])', re.I)
BASELINE = os.path.join(ROOT, 'tools', 'demo_leak_test_baseline.json')
def test_hits():
    out = {}
    for d, dirs, files in os.walk(ROOT):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
        for f in files:
            if not f.endswith(('.js', '.json', '.sql', '.py', '.html', '.css', '.csv', '.yml', '.yaml', '.ts', '.md', '.sh')): continue
            p = os.path.join(d, f); rel = os.path.relpath(p, ROOT).replace(os.sep, '/')
            if not is_test(rel) or rel.endswith('check_no_demo_leak.py'): continue
            try: txt = open(p, encoding='utf-8', errors='ignore').read()
            except OSError: continue
            n = len(TEST_PAT.findall(txt))
            if n: out[rel] = n
    return out
try: base = json.load(open(BASELINE, encoding='utf-8'))
except (OSError, ValueError): base = {}
hits = test_hits()
if '--write-baseline' in sys.argv:
    new = {k: v for k, v in hits.items() if k in base and v <= base[k]}
    refused = [k for k, v in hits.items() if k not in base or v > base[k]]
    if refused:
        for k in refused: print('REFUSED  %s has %d roster name hit(s), more than the baseline allows' % (k, hits[k]))
        sys.exit(1)
    json.dump(dict(sorted(new.items())), open(BASELINE, 'w', encoding='utf-8'), indent=1); open(BASELINE, 'a').write('\n')
    print('baseline written: %d file(s), %d hit(s)' % (len(new), sum(new.values()))); sys.exit(0)
for rel, n in sorted(hits.items()):
    if rel not in base: bad.append((rel, 0, 'test file uses a roster staff name (%d hit(s)); use neutral test_* names' % n))
    elif n > base[rel]: bad.append((rel, 0, 'more roster staff names than the frozen baseline (%d > %d); use neutral test_* names' % (n, base[rel])))
if bad:
    for r, n, w in bad[:50]: print('LEAK  %s:%s  %s' % (r, n, w))
    print('FAIL: %d reference(s) to demo material in app code' % len(bad)); sys.exit(1)
print('OK: no demo file name, demo staff name or docs/demo reference in app code, kb.json or build_kb.py; test files carry no new roster names')
