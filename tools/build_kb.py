#!/usr/bin/env python3
"""Islamia BOS - knowledge base generator for the in-app assistant (Module G).

Builds web/data/kb.json from the REAL sources (never hand-edited):
  * web/ia.js                  screens: route, group, labels (bn/en/mix), search keywords
  * supabase/phase*.sql        rules seeds (key, module, kind, default, labels, hints) and grant_defs seeds
  * supabase/schema.sql+phase3 forms table seeds; web/forms*.js form titles
  * docs/BUILD-LOG.md, TODO.md, HANDOVER_2.md, DEVICE_CHECKLIST.md, plan_v2/*.md   chunked by heading
  * tools/kb_playbooks/*.md    hand-written setup playbooks (validated!)
  * supabase/phase47.sql       the assistant_health() finding codes (playbook checks "health:<code>")

Guard ("refresh when the system changes"): the build FAILS (exit 1) when a playbook names a route, rule key, grant or health code that does not
exist. A playbook with `optional_phase: phaseNN` (+ `optional_route: x`) is skipped (and listed as skipped) while that phase file is absent or its screen is not
registered yet; once both exist it is validated strictly.

Usage:  python3 tools/build_kb.py            (writes web/data/kb.json)
        python3 tools/build_kb.py --check    (validate only, write nothing)
Content hash (sha256 of the content, 12 hex) = "knowledge version" shown in the app.
"""
import glob, hashlib, json, os, re, sys, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
J = lambda *p: os.path.join(ROOT, *p)
read = lambda p: open(p, encoding='utf-8').read()
MAX_CHUNK = 1400


# ---------- a tiny SQL literal reader (tuples of 'text', numbers, null, casts) ----------
def sql_values(s):
    """Split a tuple body 'a', 'b''c', null, 3, '["x"]'::jsonb into python values (strings keep their text, casts are dropped)."""
    out, i, n = [], 0, len(s)
    while i < n:
        while i < n and s[i] in ' \t\r\n,':
            i += 1
        if i >= n:
            break
        if s[i] == "'":
            j, buf = i + 1, []
            while j < n:
                if s[j] == "'" and j + 1 < n and s[j + 1] == "'":
                    buf.append("'"); j += 2; continue
                if s[j] == "'":
                    break
                buf.append(s[j]); j += 1
            val = ''.join(buf); i = j + 1
        else:
            j = i; depth = 0
            while j < n and not (s[j] == ',' and depth == 0):
                if s[j] == '(':
                    depth += 1
                elif s[j] == ')':
                    depth -= 1
                j += 1
            tok = s[i:j].strip(); i = j
            val = None if tok.lower() == 'null' else tok
        while i < n and s[i] == ':':          # ::jsonb / ::text[]
            j = i
            while j < n and s[j] not in ',': j += 1
            i = j
        out.append(val)
    return out


def tuples(body):
    """Top-level (...) groups of a VALUES list ('' inside a string is an escaped quote)."""
    res, depth, start, q, k, n = [], 0, None, False, 0, len(body)
    while k < n:
        ch = body[k]
        if q:
            if ch == "'":
                if k + 1 < n and body[k + 1] == "'": k += 2; continue
                q = False
        elif ch == "'": q = True
        elif ch == '(':
            if depth == 0: start = k + 1
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0 and start is not None: res.append(body[start:k]); start = None
        elif ch == ';' and depth == 0: break
        k += 1
    return res


def sql_statement_after(src, pos):
    """Text from pos to the end of the statement (a ';' outside quotes)."""
    q = False
    for k in range(pos, len(src)):
        ch = src[k]
        if ch == "'":
            q = not q
        elif ch == ';' and not q:
            return src[pos:k]
    return src[pos:]


def phase_files():
    fs = [f for f in glob.glob(J('supabase', '*.sql')) if not f.endswith('_test.sql') and 'ALL_NEW' not in f and 'phase30_controls' not in f and 'import' not in f]
    def key(f):
        b = os.path.basename(f)
        if b == 'schema.sql': return -1
        m = re.match(r'phase(\d+)', b)
        return int(m.group(1)) if m else 999
    return sorted(fs, key=key)


def parse_inserts(table):
    rows = []
    for f in phase_files():
        src = read(f)
        for m in re.finditer(r'insert into public\.' + table + r'\s*\(([^)]*)\)', src, re.I):
            cols = [c.strip() for c in m.group(1).split(',')]
            stmt = sql_statement_after(src, m.end())
            st = stmt.lstrip()
            if st.lower().startswith('values'):
                for t in tuples(st[6:]):
                    v = sql_values(t)
                    if len(v) == len(cols): rows.append((dict(zip(cols, v)), os.path.basename(f)))
            elif st.lower().startswith('select'):
                sel = re.split(r'\swhere\s', st[6:], maxsplit=1, flags=re.I)[0]
                v = sql_values(sel)
                if len(v) == len(cols):
                    rows.append((dict(zip(cols, v)), os.path.basename(f)))
    return rows


def rules():
    out = {}
    for r, f in parse_inserts('rules'):
        k = r.get('key')
        if not k or not re.match(r'^[a-z0-9_]+$', k) or k in out: continue
        out[k] = {'key': k, 'module': r.get('module'), 'kind': r.get('kind'), 'default': r.get('default_value'),
                  'label_bn': r.get('label_bn'), 'label_en': r.get('label_en') or r.get('label_bn'), 'hint_bn': r.get('hint_bn'), 'hint_en': r.get('hint_en'), 'file': f}
    return out


def grants():
    out = {}
    for r, f in parse_inserts('grant_defs'):
        k = r.get('grant_code')
        if not k or not re.match(r'^[a-z0-9_]+$', k) or k in out: continue
        out[k] = {'code': k, 'module': r.get('module'), 'label_bn': r.get('label_bn'), 'label_en': r.get('label_en') or r.get('label_bn'), 'file': f}
    return out


def forms():
    out = {}
    for f in [J('supabase', 'schema.sql'), J('supabase', 'phase3.sql')]:
        src = read(f)
        for m in re.finditer(r'insert into public\.forms\s*\(([^)]*)\)\s*values', src, re.I):
            cols = [c.strip() for c in m.group(1).split(',')]
            for t in tuples(sql_statement_after(src, m.end())):
                v = sql_values(t)
                if len(v) == len(cols):
                    d = dict(zip(cols, v))
                    out.setdefault(d['code'], {'code': d['code'], 'area': d.get('area'), 'name_bn': d.get('name_bn'), 'name_en': d.get('name_en')})
    for f in sorted(glob.glob(J('web', 'forms*.js'))):
        src = read(f)
        for m in re.finditer(r"B\.forms\['([0-9A-Za-z-]+)'\]\s*=\s*\{\s*title:\s*L\('((?:[^'\\]|\\.)*)',\s*'((?:[^'\\]|\\.)*)'", src):
            d = out.setdefault(m.group(1), {'code': m.group(1)})
            d['title_bn'], d['title_en'], d['in_app'] = m.group(2), m.group(3), True
    return out


def i18n():
    src, T = read(J('web', 'i18n.js')), {}
    for m in re.finditer(r'^\s*([a-z0-9_]+):\s*\{\s*bn:\s*"([^"]*)",\s*mix:\s*"([^"]*)",\s*en:\s*"([^"]*)"', src, re.M):
        T[m.group(1)] = (m.group(2), m.group(4), m.group(3))
    return T


def screens():
    src, T, out = read(J('web', 'ia.js')), i18n(), []
    for m in re.finditer(r"rec\('([^']+)',\s*'([a-z]+)',\s*(\[[^\]]*\]|'t:[a-z0-9_]+')(.*?)\)\s*,?\s*$", src, re.M):
        rid, grp, lab, rest = m.groups()
        if lab.startswith("'t:"):
            bn, en, mix = T.get(lab[3:-1], (rid, rid, rid))
        else:
            parts = re.findall(r"'((?:[^'\\]|\\.)*)'", lab) + [None, None, None]
            bn, en, mix = parts[0], parts[1] or parts[0], parts[2] or parts[0]
        kw = re.search(r"kw:\s*\[([^\]]*)\]", rest)
        kws = re.findall(r"'((?:[^'\\]|\\.)*)'", kw.group(1)) if kw else []
        hidden = "status: 'hidden'" in rest
        out.append({'route': rid, 'group': grp, 'bn': bn, 'en': en, 'mix': mix, 'kw': kws, 'hidden': hidden})
    return out


def page_routes():
    """Routes that exist as pages even when ia.js does not list them (BOS_PAGES keys + app.js local pages + pending registrations in docs/regs)."""
    r = set()
    for f in glob.glob(J('web', '*.js')):
        src = read(f)
        for m in re.finditer(r'BOS_PAGES\s*(?:=|\|\|)[^;]*?\{([^}]*)\}', src):
            r.update(re.findall(r'([a-z0-9_]+)\s*:', m.group(1)))
    app = read(J('web', 'app.js'))
    m = re.search(r'const local = \{([^}]*)\}', app)
    if m: r.update(re.findall(r'([a-z0-9_]+)\s*:', m.group(1)))
    for f in glob.glob(J('docs', 'regs', '*.md')):
        r.update(re.findall(r"rec\('([^']+)'", read(f)))
    return r


def health_codes():
    src = read(J('supabase', 'phase47.sql'))
    codes = set(re.findall(r"_ah\('([a-z0-9_]+)'", src))
    codes.update('only_owner_' + g for g in re.findall(r"'(release_decide|wastage_approve|change_approve)'", src))
    return codes


def doc_chunks():
    files = [J('docs', 'BUILD-LOG.md'), J('docs', 'TODO.md'), J('docs', 'HANDOVER_2.md'), J('docs', 'DEVICE_CHECKLIST.md')] + sorted(glob.glob(J('docs', 'plan_v2', '*.md')))
    out = []
    for f in files:
        if not os.path.exists(f): continue
        rel = os.path.relpath(f, ROOT); cur_title, buf, n = os.path.basename(f), [], 0
        def flush():
            nonlocal buf, n
            text = '\n'.join(buf).strip()
            while text:
                piece, text = text[:MAX_CHUNK], text[MAX_CHUNK:]
                n += 1
                out.append({'id': f'doc:{rel}#{n}', 'kind': 'doc', 'title_bn': cur_title, 'title_en': cur_title, 'text': piece, 'source': rel})
            buf = []
        for line in read(f).splitlines():
            if re.match(r'^#{1,4}\s', line):
                flush(); cur_title = line.lstrip('#').strip()[:120]
            else:
                buf.append(line)
        flush()
    return out


def parse_playbook(path):
    src = read(path)
    m = re.match(r'---\n(.*?)\n---\n?(.*)$', src, re.S)
    if not m: raise ValueError(path + ': missing --- header ---')
    head, body = m.group(1), m.group(2).strip()
    pb, steps = {'steps': []}, None
    for line in head.splitlines():
        if line.startswith('- ') and steps is not None:
            st = {}
            for part in line[2:].split(' | '):
                k, _, v = part.partition(':'); st[k.strip()] = v.strip()
            pb['steps'].append(st)
        elif ':' in line:
            k, _, v = line.partition(':'); k = k.strip(); v = v.strip()
            if k == 'steps': steps = True
            else: pb[k] = v
    pb['tags'] = [t.strip() for t in pb.get('tags', '').split(',') if t.strip()]
    pb['requires'] = [t.strip() for t in pb.get('requires', '').split(',') if t.strip()]
    pb['body'] = body
    return pb


def main():
    check_only = '--check' in sys.argv
    R, G, F, SC = rules(), grants(), forms(), screens()
    routes = {s['route'] for s in SC} | page_routes()
    HC = health_codes()
    errors, skipped, playbooks = [], [], []
    route_ok = lambda r: r in routes or r.split('/')[0] in routes
    for p in sorted(glob.glob(J('tools', 'kb_playbooks', '*.md'))):
        pb = parse_playbook(p); name = os.path.basename(p)
        op = pb.get('optional_phase')
        if op and not os.path.exists(J('supabase', op + '.sql')):
            skipped.append(f'{name} (needs {op}.sql)'); continue
        orr = pb.get('optional_route')
        if op and orr and not route_ok(orr):
            skipped.append(f'{name} (route {orr} not registered yet)'); continue
        for k in ('id', 'title_bn', 'title_en'):
            if not pb.get(k): errors.append(f'{name}: missing {k}')
        if not pb['steps']: errors.append(f'{name}: no steps')
        for i, st in enumerate(pb['steps'], 1):
            r, c = st.get('route', ''), st.get('check', 'none')
            if not r or not route_ok(r): errors.append(f'{name} step {i}: route "{r}" does not exist')
            if not st.get('bn') or not st.get('en'): errors.append(f'{name} step {i}: needs bn and en text')
            kind, _, val = c.partition(':')
            if kind in ('rule', 'rule_on', 'rule_set') and val not in R: errors.append(f'{name} step {i}: rule "{val}" does not exist')
            elif kind == 'grant' and val not in G: errors.append(f'{name} step {i}: grant "{val}" does not exist')
            elif kind == 'health' and val not in HC: errors.append(f'{name} step {i}: health check "{val}" does not exist')
            elif kind not in ('rule', 'rule_on', 'rule_set', 'grant', 'health', 'none'): errors.append(f'{name} step {i}: unknown check "{c}"')
        for q in pb['requires']:
            kind, _, val = q.partition(':')
            if kind == 'rule' and val not in R: errors.append(f'{name}: requires unknown rule {val}')
        playbooks.append({'id': pb['id'], 'title_bn': pb['title_bn'], 'title_en': pb['title_en'], 'tags': pb['tags'], 'requires': pb['requires'],
                          'steps': [{'route': s['route'], 'check': s.get('check', 'none'), 'bn': s['bn'], 'en': s['en']} for s in pb['steps']], 'body': pb['body']})
    if len(playbooks) < 12: errors.append(f'only {len(playbooks)} playbooks (need at least 12)')
    if errors:
        print('KB BUILD FAILED:'); [print('  - ' + e) for e in errors]; sys.exit(1)

    chunks = []
    for s in SC:
        if s['hidden']: continue
        chunks.append({'id': 'screen:' + s['route'], 'kind': 'screen', 'title_bn': s['bn'], 'title_en': s['en'], 'route': s['route'], 'text': ' '.join(s['kw']) + ' ' + s['group']})
    for r in R.values():
        chunks.append({'id': 'rule:' + r['key'], 'kind': 'rule', 'key': r['key'], 'title_bn': r['label_bn'], 'title_en': r['label_en'], 'route': 'switchboard',
                       'text': ' '.join(x for x in [r['key'], r['module'], r['kind'], 'default ' + str(r['default']), r['hint_en'] or '', r['hint_bn'] or ''] if x)})
    for g in G.values():
        chunks.append({'id': 'grant:' + g['code'], 'kind': 'grant', 'key': g['code'], 'title_bn': g['label_bn'], 'title_en': g['label_en'], 'route': 'delegation', 'text': g['code'] + ' ' + (g['module'] or '')})
    for f in F.values():
        chunks.append({'id': 'form:' + f['code'], 'kind': 'form', 'key': f['code'], 'title_bn': f.get('title_bn') or f.get('name_bn') or f['code'], 'title_en': f.get('title_en') or f.get('name_en') or f['code'],
                       'route': {'POS': 'pos', 'ITEMS': 'items', 'ITEM_COST': 'items'}.get(f['code'], 'form/' + f['code']), 'text': f['code'] + ' ' + (f.get('area') or '') + (' in app' if f.get('in_app') else ' paper only')})
    for p in playbooks:
        chunks.append({'id': 'playbook:' + p['id'], 'kind': 'playbook', 'key': p['id'], 'title_bn': p['title_bn'], 'title_en': p['title_en'],
                       'text': ' '.join(p['tags']) + ' ' + ' '.join(s['en'] + ' ' + s['bn'] for s in p['steps']) + ' ' + p['body']})
    chunks += doc_chunks()
    content = {'screens': [{k: s[k] for k in ('route', 'group', 'bn', 'en', 'mix', 'kw')} for s in SC if not s['hidden']],
               'rules': sorted(R.keys()), 'grants': sorted(G.keys()), 'health_codes': sorted(HC), 'playbooks': playbooks, 'chunks': chunks}
    blob = json.dumps(content, ensure_ascii=False, sort_keys=True)
    version = hashlib.sha256(blob.encode('utf-8')).hexdigest()[:12]
    out = dict(content, version=version, generated_at=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
               counts={'screens': len(content['screens']), 'rules': len(R), 'grants': len(G), 'forms': len(F), 'playbooks': len(playbooks), 'chunks': len(chunks)}, skipped=skipped)
    print(f"KB ok: version {version}; {out['counts']}; skipped playbooks: {skipped or 'none'}")
    if check_only: return
    os.makedirs(J('web', 'data'), exist_ok=True)
    with open(J('web', 'data', 'kb.json'), 'w', encoding='utf-8') as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(',', ':'))
    print('wrote web/data/kb.json', os.path.getsize(J('web', 'data', 'kb.json')), 'bytes')


if __name__ == '__main__':
    main()
