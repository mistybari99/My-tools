#!/usr/bin/env python3
"""Builds the owner's SQL paste pages from the repository: parts of at most 500 KB and the copy page setup-all.html.

Nothing here talks to a database or to the network and nothing is pushed anywhere. The owner (or an agent on his explicit go) uploads the result to the public pages repository.

Two sets are built, both into docs/paste_parts/ (or --out DIR):

  FRESH   a NEW Supabase project: the base files (schema, phase2, phase3, phase4, ALL_NEW) and then every phase of tests/sql/ORDER.txt, in that order.
          Files part01.sql, part02.sql, ... Each phase file goes whole into one part (a phase file is never cut in the middle); a part is closed before it would pass 500 KB.
  DELTA   the OWNER'S CURRENT LIVE DATABASE (parts 1-13 of the earlier sqlparts + the advanced line's phases 72-135 pasted): only the phases that bring it to the merged state,
          listed in tools/build_paste_parts.py DELTA (see docs/LIVE_DELTA.md). Files delta01.sql, ...

Every part starts with a comment that names its phases and ends with the one-line check the owner runs after it. The page setup-all.html lists the parts in order, with a copy button
for each (it fetches the part file from sqlparts/<name> and falls back to <name> next to the page) and the checks. Nothing is copied or run by the page itself except the copy to the clipboard.

usage:  python3 tools/build_paste_parts.py [--out docs/paste_parts] [--check]
        --check   build into a temporary folder and compare with --out (exit 1 when the files in --out are out of date)
"""
import argparse
import hashlib
import html
import json
import os
import re
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SQL = os.path.join(ROOT, 'supabase')
LIMIT = 500 * 1024
BASE = ['schema', 'phase2', 'phase3', 'phase4', 'ALL_NEW']
# the delta for the live database (docs/LIVE_DELTA.md): what a database built from the earlier sqlparts + the advanced phases 72-135 still needs. Read docs/LIVE_DELTA.md before pasting.
DELTA = ['phase499', 'phase501', 'phase502', 'phase503', 'phase504', 'phase505', 'phase529', 'phase530', 'phase531', 'phase532', 'phase533', 'phase534']
CHECK = {
    'fresh_last': "select * from public._i2_state() where not present;   -- must return no rows",
    'delta_last': "select * from public._i2_state() where not present;   -- must return no rows\nselect fn, saved_at, why from public._union_fn_backup order by id;   -- the bodies that were saved before a change",
}


def order():
    words = []
    with open(os.path.join(ROOT, 'tests', 'sql', 'ORDER.txt'), encoding='utf-8') as fh:
        for line in fh:
            if not line.lstrip().startswith('#'):
                words += line.split()
    return words


def read(name):
    with open(os.path.join(SQL, name + '.sql'), encoding='utf-8') as fh:
        return fh.read()


def split(names, prefix):
    parts, cur, size = [], [], 0
    for n in names:
        s = len(read(n).encode('utf-8')) + 200
        if cur and size + s > LIMIT:
            parts.append(cur)
            cur, size = [], 0
        cur.append(n)
        size += s
    if cur:
        parts.append(cur)
    return parts


def part_text(label, idx, total, names, last_check):
    head = ['-- ' + '=' * 76,
            '-- %s part %d of %d. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.' % (label, idx, total),
            '-- Phases in this part, in this order: ' + ' '.join(names),
            '-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.',
            '-- ' + '=' * 76, '']
    body = []
    for n in names:
        body.append('-- ---------------------------------------------------------------- %s.sql' % n)
        body.append(read(n).rstrip('\n'))
        body.append('')
    tail = ['-- ' + '=' * 76, '-- End of %s part %d of %d.' % (label, idx, total)]
    if last_check:
        tail.append('-- Now run this check (it only reads):')
        tail.extend('-- ' + l for l in last_check.split('\n'))
    return '\n'.join(head + body + tail) + '\n'


def build(out):
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if re.match(r'(part|delta)\d+\.sql$|setup-all\.html$|manifest\.json$', f):
            os.remove(os.path.join(out, f))
    fresh_names = BASE + order()
    for n in fresh_names:
        if not os.path.exists(os.path.join(SQL, n + '.sql')):
            raise SystemExit('missing file supabase/%s.sql' % n)
    sets = []
    for label, prefix, names, chk in (('FRESH', 'part', fresh_names, CHECK['fresh_last']), ('DELTA', 'delta', DELTA, CHECK['delta_last'])):
        parts = split(names, prefix)
        files = []
        for i, p in enumerate(parts, 1):
            fn = '%s%02d.sql' % (prefix, i)
            txt = part_text(label, i, len(parts), p, chk if i == len(parts) else '')
            with open(os.path.join(out, fn), 'w', encoding='utf-8') as fh:
                fh.write(txt)
            files.append({'file': fn, 'phases': p, 'bytes': len(txt.encode('utf-8')), 'sha256': hashlib.sha256(txt.encode('utf-8')).hexdigest()})
        sets.append({'set': label, 'files': files})
    man = {'limit_bytes': LIMIT, 'sets': sets}
    with open(os.path.join(out, 'manifest.json'), 'w', encoding='utf-8') as fh:
        json.dump(man, fh, indent=1)
    with open(os.path.join(out, 'setup-all.html'), 'w', encoding='utf-8') as fh:
        fh.write(page(man))
    return man


def page(man):
    rows = {}
    for s in man['sets']:
        r = []
        for i, f in enumerate(s['files'], 1):
            ph = f['phases']
            r.append('<li class="part"><div class="hd"><b>%s</b> <span class="muted">%d KB &middot; %s</span></div>'
                     '<div class="ph">%s</div>'
                     '<div class="row"><button type="button" data-copy="%s">Copy this part</button> <a href="sqlparts/%s" data-alt="%s" download>Download</a> <span class="st" aria-live="polite"></span></div></li>'
                     % (html.escape(f['file']), round(f['bytes'] / 1024), html.escape(('phases ' + ph[0] + ' ... ' + ph[-1]) if len(ph) > 3 else ' '.join(ph)),
                        html.escape(' '.join(ph)), html.escape(f['file']), html.escape(f['file']), html.escape(f['file'])))
        rows[s['set']] = '\n'.join(r)
    css = ('body{font:16px/1.5 system-ui,sans-serif;margin:0;background:#fbf5ee;color:#222}main{max-width:760px;margin:0 auto;padding:16px}h1{font-size:1.35rem}h2{font-size:1.1rem;margin-top:28px}'
           'ul{list-style:none;padding:0}li.part{background:#fff;border:1px solid #e4d6c4;border-radius:12px;padding:12px;margin:10px 0}.hd{font-size:1rem}.muted{color:#6b6257;font-size:.85rem}'
           '.ph{font-size:.8rem;color:#6b6257;word-break:break-word;margin:4px 0 8px}button,a{min-height:44px;display:inline-flex;align-items:center;padding:0 14px;border-radius:10px;border:1px solid #a1111e;'
           'background:#a1111e;color:#fff;font:inherit;text-decoration:none;cursor:pointer}a{background:#fff;color:#a1111e}.row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}'
           '.note{background:#fff7e0;border:1px solid #ecd48a;border-radius:10px;padding:10px;font-size:.9rem}code{background:#f1e8dc;padding:1px 4px;border-radius:4px;word-break:break-all}'
           '@media (prefers-color-scheme:dark){body{background:#17181c;color:#eee}li.part{background:#23252b;border-color:#3a3d45}.muted,.ph{color:#b8b0a5}a{background:#23252b}.note{background:#3a3320;border-color:#6b5c2a}code{background:#2d2f36}}')
    js = ("(function(){function get(n,alt){return fetch('sqlparts/'+n).then(function(r){if(!r.ok)throw 0;return r.text()}).catch(function(){return fetch(alt||n).then(function(r){if(!r.ok)throw 0;return r.text()})})}"
          "document.addEventListener('click',function(e){var b=e.target.closest('button[data-copy]');if(!b)return;var st=b.parentNode.querySelector('.st');st.textContent='...';"
          "get(b.getAttribute('data-copy')).then(function(t){return navigator.clipboard.writeText(t).then(function(){st.textContent='Copied ('+Math.round(t.length/1024)+' KB). Now paste it into the SQL editor and press Run.'})})"
          ".catch(function(){st.textContent='Copy failed: use Download and open the file.'})});})();")
    return ('<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex">'
            '<title>SQL paste parts</title><style>%s</style></head><body><main>\n'
            '<h1>SQL paste parts (merged version)</h1>\n'
            '<p class="note">Made by <code>tools/build_paste_parts.py</code> from the repository. Each part is at most 500 KB. Paste ONE part at a time, in order, into the Supabase SQL editor and wait for Success. '
            'Never paste a test file. The agent never pastes anything; the owner does. Read <code>docs/LIVE_DELTA.md</code> first if the project already holds data.</p>\n'
            '<h2>A. New project (fresh build): parts in this order</h2>\n<ul>\n%s\n</ul>\n'
            '<p>After the last part run: <code>select * from public._i2_state() where not present;</code> It must return no rows.</p>\n'
            '<h2>B. The current live project (only what is still missing): read docs/LIVE_DELTA.md, run its read-only probe first, then these parts in this order</h2>\n<ul>\n%s\n</ul>\n'
            '<p>After the last delta part run: <code>select * from public._i2_state() where not present;</code> (no rows) and look at <code>select fn, saved_at, why from public._union_fn_backup order by id;</code>.</p>\n'
            '</main><script>%s</script></body></html>\n') % (css, rows['FRESH'], rows['DELTA'], js)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(ROOT, 'docs', 'paste_parts'))
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args(argv)
    if a.check:
        with tempfile.TemporaryDirectory() as tmp:
            build(tmp)
            bad = []
            for f in sorted(os.listdir(tmp)):
                p = os.path.join(a.out, f)
                if not os.path.exists(p) or open(p, 'rb').read() != open(os.path.join(tmp, f), 'rb').read():
                    bad.append(f)
            extra = [f for f in os.listdir(a.out) if re.match(r'(part|delta)\d+\.sql$', f) and f not in os.listdir(tmp)] if os.path.isdir(a.out) else []
            if bad or extra:
                print('OUT OF DATE:', ' '.join(bad + extra))
                return 1
            print('OK: paste parts are up to date')
            return 0
    man = build(a.out)
    for s in man['sets']:
        print(s['set'], len(s['files']), 'parts,', sum(f['bytes'] for f in s['files']) // 1024, 'KB, largest', max(f['bytes'] for f in s['files']) // 1024, 'KB')
    return 0


if __name__ == '__main__':
    sys.exit(main())
