#!/usr/bin/env python3
"""Read-only UI inventory extractor (Python standard library + the preinstalled node).

It reads the CODE and the SQL seed files of this repository (never a database, never a network) and produces one
machine-readable inventory of everything a person can reach in the app: routes, menu entries, paper forms with
their fields and options, screen controls (buttons, tabs, inputs, selects, RPC calls) and settings keys.

    python3 tools/build_ui_inventory.py                 # write tests/ui_inventory/baseline.json (first time / full rebuild)
    python3 tools/build_ui_inventory.py --stdout        # print the inventory instead
    python3 tools/build_ui_inventory.py --root DIR      # inventory another copy of the tree

Day-to-day use is tools/check_ui_inventory.py (compare, never drop). See docs/UI_NO_LOSS_RULE.md.

How it works (two sources, both static):
  1. tools/ui_inventory_runtime.js loads web/*.js in index.html order inside a throw-away node sandbox with a ghost DOM
     and returns the DATA the scripts build at load time (route registry, form specs, settings catalogue, i18n texts).
     Confidence: high, because the real code builds those structures.
  2. Careful text parsing (this file) of the HTML inside web/*.js and web/index.html for buttons, tabs, inputs, selects,
     options and RPC names, and of supabase/*.sql INSERT ... VALUES lists for forms, rules, grants and option lists.
     Confidence: high when the label is a plain text or an i18n key, medium when it contains a computed part.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

VERSION = 1
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.dirname(HERE)
BASELINE_REL = os.path.join('tests', 'ui_inventory', 'baseline.json')
LANGS = ('bn', 'en', 'mix')

CONTROL_KINDS = ('button', 'tab', 'link', 'action', 'input', 'select', 'textarea', 'rpc')
CATEGORY_OF = {
    'route': 'routes', 'form': 'forms', 'field': 'fields', 'option': 'options', 'ctl_option': 'options',
    'setting': 'settings keys',
}
for _k in CONTROL_KINDS:
    CATEGORY_OF[_k] = 'controls'


def category(kind):
    return CATEGORY_OF.get(kind, 'other')


# ---------------------------------------------------------------------------------------------- item store
class Items:
    """Collects items; same id twice = merged (labels kept, texts united, the weaker confidence wins)."""

    def __init__(self):
        self.by_id = {}

    def add(self, id_, kind, source, level='must', conf='high', labels=None, texts=None, attrs=None):
        it = self.by_id.get(id_)
        if it is None:
            it = {'id': id_, 'kind': kind, 'level': level, 'conf': conf, 'source': source}
            if labels:
                it['labels'] = dict(labels)
            if texts:
                it['texts'] = sorted(set(texts))
            if attrs:
                it['attrs'] = attrs
            self.by_id[id_] = it
            return it
        if conf == 'medium':
            it['conf'] = 'medium'
        if texts:
            it['texts'] = sorted(set(it.get('texts', [])) | set(texts))
        if labels:
            lab = it.setdefault('labels', {})
            for k, v in labels.items():
                lab.setdefault(k, v)
        if attrs:
            at = it.setdefault('attrs', {})
            at['count'] = at.get('count', 1) + 1
            for k, v in attrs.items():
                at.setdefault(k, v)
        else:
            at = it.setdefault('attrs', {})
            at['count'] = at.get('count', 1) + 1
        return it

    def sorted(self):
        out = []
        for id_ in sorted(self.by_id):
            it = self.by_id[id_]
            if 'attrs' in it and it['attrs'].get('count') == 1 and len(it['attrs']) == 1:
                del it['attrs']
            out.append(it)
        return out


def slug(s, n=40):
    s = re.sub(r'\s+', ' ', str(s or '')).strip().lower()
    s = re.sub(r'[^\wঀ-৿]+', '-', s).strip('-')
    return s[:n] or 'x'


# ---------------------------------------------------------------------------------------------- runtime (node)
def run_runtime(root):
    web = os.path.join(root, 'web')
    helper = os.path.join(HERE, 'ui_inventory_runtime.js')
    try:
        p = subprocess.run(['node', helper, web], capture_output=True, text=True, timeout=180)
    except FileNotFoundError:
        raise SystemExit('ERROR: node is required (preinstalled on GitHub runners) to read the route and form registries.')
    if p.returncode != 0 or not p.stdout.strip():
        raise SystemExit('ERROR: node helper failed: ' + (p.stderr or p.stdout)[:500])
    return json.loads(p.stdout)


def lang_labels(label, i18n):
    """label is 't:key', a [bn, en, mix?] list or a {bn,en,mix} dict -> ({lang: text}, ref or None)."""
    if isinstance(label, str) and label.startswith('t:'):
        key = label[2:]
        t = i18n.get(key) or {}
        return {k: t[k] for k in LANGS if t.get(k)}, label
    if isinstance(label, list):
        return {k: v for k, v in zip(LANGS, label) if v}, None
    if isinstance(label, dict):
        return {k: label[k] for k in LANGS if label.get(k)}, None
    if isinstance(label, str):
        return {'en': label}, None
    return {}, None


def fn_src(v):
    return v['$fn'] if isinstance(v, dict) and '$fn' in v else v


# ---------------------------------------------------------------------------------------------- routes
def routes_from_runtime(rt, items):
    i18n = rt['i18n']
    ia = rt['ia']
    for r in ia:
        labels, ref = lang_labels(r.get('label'), i18n)
        attrs = {}
        for k, v in r.items():
            if k in ('id', 'route', 'label', 'kw'):
                continue
            if k == 'qa':
                attrs['qa'] = [q.get('route') for q in v]
                continue
            attrs[k] = fn_src(v)
        if ref:
            attrs['label_ref'] = ref
        g = next((x for x in rt['ia_extra']['groups'] if x['id'] == r['group']), None)
        rid = 'route:' + r['route']
        items.add(rid, 'route', 'web/ia.js', 'must', 'high', labels, attrs=attrs)
        for q in r.get('qa', []):
            ql, _ = lang_labels(q.get('label'), i18n)
            items.add('qa:%s:%s' % (r['route'], q.get('route')), 'qa', 'web/ia.js', 'must', 'high', ql,
                      attrs={'ok': fn_src(q.get('ok'))})
        for w in r.get('kw', []):
            items.add('kw:%s:%s' % (r['route'], w.lower()), 'keyword', 'web/ia.js', 'info', 'high', {'text': w})
    for g in rt['ia_extra']['groups']:
        items.add('group:' + g['id'], 'group', 'web/ia.js', 'must', 'high', lang_labels(g['label'], i18n)[0])
    for a, g in (rt['ia_extra']['area_g'] or {}).items():
        items.add('place:area:' + a, 'placement', 'web/ia.js', 'info', 'high', attrs={'group': g})
    for persona, lst in (rt['ia_extra']['quick_by'] or {}).items():
        for pos, rid in enumerate(lst):
            items.add('place:quick:%s:%s' % (persona, rid), 'placement', 'web/ia.js', 'info', 'high', attrs={'pos': pos})
    for persona, lst in (rt['ia_extra']['slots_by'] or {}).items():
        for pos, rid in enumerate(lst):
            items.add('place:slot:%s:%s' % (persona, rid), 'placement', 'web/ia.js', 'info', 'high', attrs={'pos': pos})
    for mode, lst in (rt['ia_extra']['home_keys'] or {}).items():
        for pos, k in enumerate(lst or []):
            items.add('place:home:%s:%s' % (mode, k), 'placement', 'web/ia.js', 'info', 'high', attrs={'pos': pos})
    for d in rt['ia_extra']['dof'] or []:
        items.add('do:' + d['id'], 'do', 'web/ia.js', 'must', 'high', lang_labels(d.get('label'), i18n)[0],
                  attrs={k: fn_src(v) for k, v in d.items() if k not in ('id', 'label')})
    for p in rt['pages']:
        items.add('page:' + p, 'page', 'web/*.js', 'must', 'high')
    for k, t in sorted(i18n.items()):
        items.add('text:' + k, 'text', 'web/i18n.js', 'must', 'high', {x: t[x] for x in LANGS if isinstance(t, dict) and t.get(x)})


# ---------------------------------------------------------------------------------------------- SQL seeds
def strip_sql_comments(s):
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == "'":
            j = i + 1
            while j < n:
                if s[j] == "'":
                    if j + 1 < n and s[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            out.append(s[i:j + 1]); i = j + 1
        elif c == '-' and s.startswith('--', i):
            j = s.find('\n', i)
            i = n if j < 0 else j
        elif c == '/' and s.startswith('/*', i):
            j = s.find('*/', i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c); i += 1
    return ''.join(out)


def _skip_ws(s, i):
    while i < len(s) and s[i] in ' \t\r\n':
        i += 1
    return i


def _convert(raw):
    raw = raw.strip()
    parts = re.split(r"\s*\|\|\s*", raw)
    if len(parts) > 1:
        conv = [_convert(p) for p in parts]
        if all(isinstance(x, str) for x in conv):
            return ''.join(conv)
        return {'raw': raw}
    m = re.fullmatch(r"(?:[eE])?'((?:[^']|'')*)'(?:::[\w\[\] ]+)?", raw, re.S)
    if m:
        return m.group(1).replace("''", "'")
    if re.fullmatch(r'null', raw, re.I):
        return None
    if re.fullmatch(r'true|false', raw, re.I):
        return raw.lower() == 'true'
    if re.fullmatch(r'-?\d+(\.\d+)?', raw):
        return float(raw) if '.' in raw else int(raw)
    return {'raw': raw}


def parse_tuple(s, i):
    """s[i] == '(' -> (index after ')', [values])."""
    n = len(s)
    i += 1
    vals, start, depth = [], i, 0
    while i < n:
        c = s[i]
        if c == "'":
            i += 1
            while i < n:
                if s[i] == "'":
                    if i + 1 < n and s[i + 1] == "'":
                        i += 2
                        continue
                    break
                i += 1
            i += 1
            continue
        if c == '(':
            depth += 1
        elif c == ')':
            if depth == 0:
                vals.append(_convert(s[start:i]))
                return i + 1, vals
            depth -= 1
        elif c == ',' and depth == 0:
            vals.append(_convert(s[start:i]))
            start = i + 1
        i += 1
    raise ValueError('unterminated tuple')


def parse_values(s, i):
    rows = []
    while True:
        i = _skip_ws(s, i)
        if i >= len(s) or s[i] != '(':
            break
        i, row = parse_tuple(s, i)
        rows.append(row)
        j = _skip_ws(s, i)
        if j < len(s) and s[j] == ',':
            i = j + 1
            continue
        i = j
        break
    return i, rows


INSERT_RE = re.compile(r'insert\s+into\s+(?:public\.)?(\w+)\s*\(([^)]*)\)\s*values', re.I)
VALUES_ALIAS_RE = re.compile(r'\(\s*values\b', re.I)
TABLES = ('forms', 'rules', 'grant_defs', 'option_lists')


def sql_files(root):
    d = os.path.join(root, 'supabase')
    if not os.path.isdir(d):
        return []
    names = []
    for f in os.listdir(d):
        if not f.endswith('.sql'):
            continue
        if f.endswith('_test.sql') or f.startswith('ALL_NEW') or 'test_project_only' in f or f.startswith('audit_'):
            continue
        names.append(f)

    def nat(f):
        m = re.search(r'(\d+)', f)
        return (0 if f == 'schema.sql' else 1, int(m.group(1)) if m else 0, f)
    return [os.path.join(d, f) for f in sorted(names, key=nat)]


HEAD_RE = re.compile(r'insert\s+into\s+(?:public\.)?(\w+)\s*\(([^)]*)\)\s*(values|select)\b', re.I)
ALIAS_COLS_RE = re.compile(r'\s*\)\s*(?:as\s+)?\w+\s*\(([^)]*)\)', re.I)
STOP_RE = re.compile(r'(from|where|on\s+conflict)\b', re.I)


def split_top(s, i):
    """Comma separated expressions from i up to a top-level FROM / WHERE / ON CONFLICT / ';' -> (index, [values])."""
    n = len(s)
    vals, start, depth = [], i, 0
    while i < n:
        c = s[i]
        if c == "'":
            i += 1
            while i < n:
                if s[i] == "'":
                    if i + 1 < n and s[i + 1] == "'":
                        i += 2
                        continue
                    break
                i += 1
            i += 1
            continue
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        elif depth == 0 and (c == ';' or (c.isalpha() and (i == 0 or not (s[i - 1].isalnum() or s[i - 1] in '_.')) and STOP_RE.match(s, i))):
            vals.append(_convert(s[start:i]))
            return i, vals
        elif c == ',' and depth == 0:
            vals.append(_convert(s[start:i]))
            start = i + 1
        i += 1
    vals.append(_convert(s[start:]))
    return n, vals


def _eval(v, ref, mapping):
    """A select-list / loop expression -> value, resolving alias.column references through mapping."""
    if isinstance(v, dict) and 'raw' in v:
        m = re.fullmatch(r'(\w+)\.(\w+)(?:::\w+)?', v['raw'].strip())
        if m and m.group(2).lower() in mapping:
            return mapping[m.group(2).lower()]
    return v


def parse_seed_rows(root, stats):
    """-> {table: [(rowdict, source_file, conf)]} from INSERT..VALUES, INSERT..SELECT (literal / from (values ...) v(cols))
    and the plpgsql loop form for the four tables that feed settings, forms and option lists."""
    out = {t: [] for t in TABLES}
    for path in sql_files(root):
        rel = os.path.relpath(path, root).replace(os.sep, '/')
        s = strip_sql_comments(open(path, encoding='utf-8', errors='replace').read())
        for m in HEAD_RE.finditer(s):
            t = m.group(1).lower()
            if t not in TABLES:
                continue
            cols = [c.strip().lower() for c in m.group(2).split(',')]
            if m.group(3).lower() == 'values':
                try:
                    end, rows = parse_values(s, m.end())
                except ValueError:
                    stats['unparsed'].append('%s: %s insert not parsed' % (rel, t)); continue
                for r in rows:
                    if len(r) != len(cols):
                        stats['unparsed'].append('%s: %s row width mismatch' % (rel, t)); continue
                    if any(isinstance(x, dict) and re.match(r'\w+\.\w+$', x.get('raw', '')) for x in r) and cols[0] in ('grant_code', 'key', 'list_code', 'code'):
                        continue  # loop form: handled below from the (values ...) list
                    out[t].append((dict(zip(cols, r)), rel, 'high'))
                continue
            # INSERT ... SELECT
            end, exprs = split_top(s, m.end())
            if len(exprs) != len(cols):
                stats['unparsed'].append('%s: %s INSERT..SELECT column count differs (not read)' % (rel, t)); continue
            rest = s[end:]
            mv = re.match(r'\s*from\s*\(\s*values\b', rest, re.I)
            if mv:
                try:
                    vend, vrows = parse_values(rest, mv.end())
                except ValueError:
                    stats['unparsed'].append('%s: %s INSERT..SELECT values not parsed' % (rel, t)); continue
                ma = ALIAS_COLS_RE.match(rest[vend:])
                if not ma:
                    stats['unparsed'].append('%s: %s INSERT..SELECT without alias columns (not read)' % (rel, t)); continue
                acols = [c.strip().lower() for c in ma.group(1).split(',')]
                for vr in vrows:
                    mapping = dict(zip(acols, vr))
                    out[t].append((dict(zip(cols, [_eval(e, None, mapping) for e in exprs])), rel, 'high'))
            elif re.match(r'\s*(where\b|;|on\s+conflict|$)', rest, re.I):
                out[t].append((dict(zip(cols, exprs)), rel, 'high'))
            else:
                stats['unparsed'].append('%s: %s filled by INSERT..SELECT from a table (not readable statically)' % (rel, t))
        # plpgsql loop: for r in select * from (values (...)) v(code, sort, bn, mix, en) loop ... insert into public.T (cols) values (r.code, ...)
        for m in VALUES_ALIAS_RE.finditer(s):
            try:
                end, rows = parse_values(s, m.end())
            except ValueError:
                continue
            ma = ALIAS_COLS_RE.match(s[end:])
            if not ma:
                continue
            acols = [c.strip().lower() for c in ma.group(1).split(',')]
            tail = s[end:end + 900]
            mh = HEAD_RE.search(tail)
            if not mh or mh.group(3).lower() != 'values' or mh.group(1).lower() not in TABLES or not re.search(r'\bloop\b', tail[:mh.start()], re.I):
                continue
            t = mh.group(1).lower()
            cols = [c.strip().lower() for c in mh.group(2).split(',')]
            try:
                _, ivals = parse_values(tail, mh.end())
            except ValueError:
                continue
            if len(ivals) != 1 or len(ivals[0]) != len(cols):
                continue
            for vr in rows:
                if len(vr) != len(acols):
                    continue
                mapping = dict(zip(acols, vr))
                out[t].append((dict(zip(cols, [_eval(e, None, mapping) for e in ivals[0]])), rel, 'medium'))
    return out


def jsonish(v):
    if isinstance(v, str):
        try:
            return json.loads(v)
        except ValueError:
            return v
    return v


def settings_from_seed(rows, items, stats):
    seen = set()
    for r, src, conf in rows['rules']:
        key = r.get('key')
        if not isinstance(key, str) or ('rule', key) in seen:
            continue
        seen.add(('rule', key))
        labels = {k: r['label_' + k] for k in LANGS if isinstance(r.get('label_' + k), str) and r.get('label_' + k)}
        attrs = {k: r.get(k) for k in ('module', 'kind', 'default_value', 'unit', 'min_value', 'max_value', 'sort') if r.get(k) is not None}
        for k in ('hint_en', 'hint_bn'):
            if isinstance(r.get(k), str):
                attrs[k] = r[k]
        ch = jsonish(r.get('choices'))
        if ch is not None and not isinstance(ch, dict):
            attrs['choices'] = ch
        items.add('setting:rule:' + key, 'setting', src, 'must', conf, labels, attrs=attrs)
        if isinstance(ch, list):
            for c in ch:
                val = c if isinstance(c, str) else (c.get('value') if isinstance(c, dict) else None)
                if val is not None:
                    items.add('option:rule:%s:%s' % (key, val), 'option', src, 'must', 'medium',
                              {'text': json.dumps(c, ensure_ascii=False) if isinstance(c, dict) else str(c)})
    for r, src, conf in rows['grant_defs']:
        key = r.get('grant_code')
        if not isinstance(key, str) or ('grant', key) in seen:
            continue
        seen.add(('grant', key))
        labels = {k: r['label_' + k] for k in LANGS if isinstance(r.get('label_' + k), str) and r.get('label_' + k)}
        attrs = {k: r.get(k) for k in ('module', 'sort', 'window_type', 'emergency_rule') if r.get(k) is not None and not isinstance(r.get(k), dict)}
        items.add('setting:grant:' + key, 'setting', src, 'must', conf, labels, attrs=attrs)
    for r, src, conf in rows['option_lists']:
        lc, vc = r.get('list_code'), r.get('value_code')
        if not isinstance(lc, str) or not isinstance(vc, str) or ('opt', lc, vc) in seen:
            continue
        seen.add(('opt', lc, vc))
        labels = {k: r['label_' + k] for k in LANGS if isinstance(r.get('label_' + k), str) and r.get('label_' + k)}
        items.add('option:list:%s:%s' % (lc, vc), 'option', src, 'must', conf, labels)


# ---------------------------------------------------------------------------------------------- forms
def pseudo_option(v):
    return isinstance(v, str) and v.startswith('__')


def forms_from_runtime(rt, rows, items, stats):
    i18n = rt['i18n']
    seed = {}
    for r, src, conf in rows['forms']:
        c = r.get('code')
        if isinstance(c, str) and c not in seed:
            seed[c] = (r, src)
    specs = rt['forms']
    for code in sorted(set(seed) | set(specs)):
        labels, attrs = {}, {}
        if code in seed:
            r, src = seed[code]
            for k in LANGS:
                v = r.get('name_' + k)
                if isinstance(v, str) and v:
                    labels[k] = v
            attrs.update({k: r.get(k) for k in ('area', 'version', 'sort') if r.get(k) is not None})
        if code in specs:
            tl, _ = lang_labels(specs[code].get('title'), i18n)
            for k in LANGS:
                if tl.get(k):
                    labels['spec_' + k] = tl[k]
            attrs['has_spec'] = True
            attrs['spec_keys'] = sorted(specs[code].keys())
        else:
            attrs['has_spec'] = False
        items.add('form:' + code, 'form', 'supabase/*.sql + web/forms*.js', 'must', 'high', labels, attrs=attrs)
    for code, sp in sorted(specs.items()):
        def one(f, parent, zone, section):
            if f.get('type') == 'note':
                tx, _ = lang_labels(f.get('text'), i18n)
                h = hashlib.sha1((tx.get('bn', '') + '|' + tx.get('en', '')).encode('utf-8')).hexdigest()[:8]
                items.add('note:%s:%s' % (code, h), 'note', 'web/forms*.js', 'info', 'high', tx)
                return
            fid = f.get('id')
            if not fid:
                stats['unparsed'].append('form %s: a field without id (type %s)' % (code, f.get('type')))
                return
            path = (parent + '.' + fid) if parent else fid
            labels, _ = lang_labels(f.get('label'), i18n)
            attrs = {'type': f.get('type'), 'zone': zone}
            if section:
                attrs['section'] = section
            for k in ('req', 'show', 'who', 'min', 'max', 'rows', 'fmt', 'wide', 'big', 'hint', 'list'):
                if k in f:
                    attrs[k] = fn_src(f[k])
            opt = f.get('options')
            items.add('field:%s:%s' % (code, path), 'field', 'web/forms*.js', 'must', 'high', labels, attrs=attrs)
            if isinstance(opt, dict):
                dyn = bool(opt.get('dynamic'))
                for ov in opt.get('value') or []:
                    if not (isinstance(ov, list) and len(ov) >= 2) or pseudo_option(ov[0]):
                        continue
                    ol, _ = lang_labels(ov[1], i18n) if not isinstance(ov[1], str) else ({'text': ov[1]}, None)
                    items.add('option:%s:%s:%s' % (code, path, ov[0]), 'option', 'web/forms*.js', 'must',
                              'medium' if dyn else 'high', ol, attrs={'dynamic': True} if dyn else None)
                if dyn and not opt.get('value'):
                    stats['unparsed'].append('form %s field %s: options depend on live data (none seen statically)' % (code, path))
            for c in f.get('cols') or []:
                one(c, path, zone, section)
        for f in sp.get('head') or []:
            one(f, '', 'head', None)
        for s in sp.get('sections') or []:
            tl, _ = lang_labels(s.get('title'), i18n)
            stitle = tl.get('en') or tl.get('bn') or 'section'
            items.add('section:%s:%s' % (code, slug(stitle, 50)), 'section', 'web/forms*.js', 'info', 'high', tl)
            for f in s.get('fields') or []:
                one(f, '', 'body', slug(stitle, 30))
    for s in rt['setting_defs']:
        items.add('setting:loc:' + s['key'], 'setting', 'web/entry.js', 'must', 'high', lang_labels(s.get('label'), i18n)[0],
                  attrs={k: s.get(k) for k in ('group', 'kind', 'unit') if s.get(k)})


# ---------------------------------------------------------------------------------------------- controls (static HTML in JS)
TAG_RE = re.compile(r'<([a-zA-Z][\w-]*)(?=[\s/>])((?:[^>"\'`$]|"[^"]*"|\'[^\']*\'|\$\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\})*)>')
ATTR_RE = re.compile(r'([\w:@.-]+)\s*=\s*(?:"([^"]*)"|\'([^\']*)\')')
T_CALL = re.compile(r"\b(?:A\.)?(\w+)\(\s*(['\"])([\w.\-]+)\2\s*\)")
L_CALL = re.compile(r"\bL\(\s*(?:'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\")\s*,\s*(?:'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\")(?:\s*,\s*(?:'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\"))?\s*\)")
STR_ONLY = re.compile(r"^\s*(?:esc\(\s*)?(?:'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\")\s*\)?\s*$")
WRAP = re.compile(r'\b(?:A\.esc|esc|lab|BOS\.lab|B\.lab|String)\s*\(')
SKIP_JS = {'sw.js', 'swreg.js'}


def strip_js_comments(s):
    s = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), s, flags=re.S)
    return re.sub(r'(?m)^\s*//.*$', '', s)


def split_template(content):
    """Split into literal text and ${...} expressions (balanced braces)."""
    parts, i, n, buf = [], 0, len(content), []
    while i < n:
        if content.startswith('${', i):
            if buf:
                parts.append(('lit', ''.join(buf))); buf = []
            depth, j = 1, i + 2
            while j < n and depth:
                if content[j] == '{':
                    depth += 1
                elif content[j] == '}':
                    depth -= 1
                j += 1
            parts.append(('expr', content[i + 2:j - 1]))
            i = j
        else:
            buf.append(content[i]); i += 1
    if buf:
        parts.append(('lit', ''.join(buf)))
    return parts


def unesc(x):
    return x.replace("\\'", "'").replace('\\"', '"').replace('\\n', ' ')


class Resolver:
    """Resolves T('key') / t('key') calls in one file: the file's own text table (const X = { key: L(bn, en, mix) }
    used through const T = (k) => lab(X[k])) first, then the global i18n table."""

    def __init__(self, src, i18n):
        self.i18n = i18n
        self.fn = {}
        for m in re.finditer(r'const\s+(\w+)\s*=\s*\(\s*(\w+)\s*\)\s*=>\s*(?:[\w.]*lab\()?\s*(\w+)\[\2\]', src):
            self.fn[m.group(1)] = m.group(3)
        self.dicts = {}
        for name in set(self.fn.values()):
            self.dicts[name] = self._dict(src, name)

    @staticmethod
    def _dict(src, name):
        m = re.search(r'\b(?:const|let|var)\s+' + re.escape(name) + r'\s*=\s*\{', src)
        if not m:
            return {}
        i, depth, n, q = m.end(), 1, len(src), None
        while i < n and depth:
            c = src[i]
            if q:
                if c == '\\':
                    i += 1
                elif c == q:
                    q = None
            elif c in '\'"`':
                q = c
            elif c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
            i += 1
        block = src[m.end():i]
        out = {}
        for ml in L_CALL.finditer(block):
            km = re.search(r"([\w$]+|'[^']+'|\"[^\"]+\")\s*:\s*$", block[max(0, ml.start() - 60):ml.start()])
            if km:
                strs = [unesc(g) for g in (ml.group(1) or ml.group(2), ml.group(3) or ml.group(4), ml.group(5) or ml.group(6)) if g is not None]
                out.setdefault(km.group(1).strip('\'"'), strs)
        return out

    def lookup(self, fname, key):
        d = self.fn.get(fname)
        if d is not None and key in self.dicts.get(d, {}):
            return self.dicts[d][key]
        if fname in ('t', 'T') or (d is None and fname.lower() in ('t', 'tt')):
            t = self.i18n.get(key)
            if isinstance(t, dict):
                return [t.get('bn', ''), t.get('en', ''), t.get('mix', '')]
        return None


def canon(content, res):
    """Visible text of a control -> (canonical label string, confidence). A resolved text key becomes
    'L:bn|en|mix' (so a renamed or emptied text is noticed); an unresolved key stays 't:key' with medium confidence."""
    if content is None:
        return '', 'high'
    pieces, conf = [], 'high'
    for kind, val in split_template(content):
        if kind == 'lit':
            txt = re.sub(r'<[^>]*>', ' ', val)
            txt = re.sub(r'&nbsp;', ' ', txt)
            txt = re.sub(r'\s+', ' ', txt).strip()
            if txt:
                pieces.append(txt)
            continue
        m = STR_ONLY.match(val)
        if m:
            pieces.append(unesc(m.group(1) if m.group(1) is not None else m.group(2)))
            continue
        refs = []
        for mt in T_CALL.finditer(val):
            fname, key = mt.group(1), mt.group(3)
            if fname in ('esc', 'lab', 'String', 'L'):
                continue
            got = res.lookup(fname, key)
            if got is not None:
                refs.append('L:' + '|'.join(got))
            elif fname in res.fn or fname in ('t', 'T', 'tt'):
                refs.append('t:' + key)
                conf = 'medium'
        for ml in L_CALL.finditer(val):
            strs = [unesc(g) for g in (ml.group(1) or ml.group(2), ml.group(3) or ml.group(4), ml.group(5) or ml.group(6)) if g is not None]
            refs.append('L:' + '|'.join(strs))
        rest = T_CALL.sub('', val)
        rest = L_CALL.sub('', rest)
        rest = WRAP.sub('', rest)
        rest = re.sub(r'[\s()]', '', rest)
        pieces.extend(refs)
        if rest or not refs:
            pieces.append('{...}')
            conf = 'medium'
    return ' '.join(pieces).strip(), conf


def attrs_of(body):
    a = {}
    for m in ATTR_RE.finditer(body):
        a.setdefault(m.group(1).lower(), m.group(2) if m.group(2) is not None else m.group(3))
    return a


def norm_key(v):
    return re.sub(r'\$\{[^}]*\}', '*', v or '').strip()


def key_of(attrs, order):
    for name in order:
        v = attrs.get(name)
        if v:
            return norm_key(v), name
    for name, v in attrs.items():
        if name.startswith('data-') and name not in ('data-act', 'data-v', 'data-i') and v:
            return name + '=' + norm_key(v), name
    return None, None


def scan_controls(root, files, i18n, items, stats):
    for rel in files:
        path = os.path.join(root, rel)
        raw = open(path, encoding='utf-8', errors='replace').read()
        src = strip_js_comments(raw) if rel.endswith('.js') else raw
        file_id = rel[4:] if rel.startswith('web/') else rel
        res = Resolver(src, i18n)
        label_for = {}
        for m in re.finditer(r'<label\b([^>]*)>(.{0,300}?)</label>', src, re.S):
            at = attrs_of(m.group(1))
            if at.get('for') and '${' not in at['for']:
                label_for[at['for']] = canon(m.group(2), res)
        for m in re.finditer(r'\.rpc\(\s*([\'"`])([\w]+)\1', src):
            items.add('rpc:%s:%s' % (file_id, m.group(2)), 'rpc', rel, 'must', 'high')
        for m in TAG_RE.finditer(src):
            tag = m.group(1).lower()
            body = m.group(2)
            at = attrs_of(body)
            end = m.end()
            if tag in ('button', 'a', 'div', 'span', 'li', 'summary', 'td', 'th', 'tr', 'label', 'p'):
                act = at.get('data-act')
                role = (at.get('role') or '').lower()
                cls = ' '.join((at.get('class') or '').split()).lower()
                is_tab = role == 'tab' or (tag == 'button' and bool(re.search(r'(^|\s)tabs?(\s|$)', cls)))
                if not (tag == 'button' or act or (tag == 'a' and at.get('href'))):
                    continue
                if tag == 'button':
                    kind = 'tab' if is_tab else 'button'
                elif act:
                    kind = 'tab' if role == 'tab' else 'action'
                else:
                    href = at.get('href', '')
                    if not href or href.startswith(('http', 'mailto', 'tel', 'javascript')) or len(norm_key(href)) < 3:
                        continue
                    kind = 'link'
                close = src.find('</' + tag, end, end + 700)
                content = src[end:close] if close >= 0 else (src[end:end + 200] if tag == 'button' else None)
                lab, conf = canon(content, res)
                if not lab:
                    al = at.get('aria-label') or at.get('title') or at.get('placeholder') or ''
                    if al:
                        lab, _ = canon(al, res)
                        conf = 'medium'
                v = at.get('data-v')
                if act and '${' not in act:
                    key = act + ('#' + v if v and '${' not in v and len(v) < 40 else '')
                elif at.get('id') and '${' not in at['id']:
                    key = '#' + at['id']
                elif kind == 'link':
                    key = norm_key(at.get('href'))
                elif act:
                    key, conf = norm_key(act), 'medium'
                else:
                    key, conf = 'label-' + slug(lab), 'medium'
                if not lab and kind != 'link':
                    conf = 'medium'
                items.add('ctl:%s:%s:%s' % (file_id, kind, key), kind, rel, 'must', conf, texts=[lab] if lab else None)
                continue
            if tag in ('input', 'textarea', 'select'):
                typ = (at.get('type') or 'text').lower() if tag == 'input' else tag
                if typ == 'hidden':
                    continue
                kind = tag
                key, _kname = key_of(at, ('id', 'data-k', 'data-f', 'name', 'data-fld', 'data-key', 'data-in'))
                conf, lab = 'high', ''
                lid = at.get('id')
                if lid and lid in label_for:
                    lab, conf = label_for[lid]
                else:
                    pre = src[max(0, m.start() - 400):m.start()]
                    mm = re.search(r'<label\b[^>]*>((?:(?!</label>).){0,300})</label>\s*(?:<div[^>]*>\s*)?$', pre, re.S)
                    mw = re.search(r'<label\b[^>]*>(?!.*</label>)((?:.){0,200})$', pre, re.S)
                    if mm:
                        lab, conf = canon(mm.group(1), res)
                    elif mw and canon(mw.group(1), res)[0]:
                        lab, _ = canon(mw.group(1), res)
                        conf = 'medium'
                    elif at.get('placeholder'):
                        lab, _ = canon(at['placeholder'], res)
                        conf = 'medium'
                    elif at.get('aria-label'):
                        lab, _ = canon(at['aria-label'], res)
                        conf = 'medium'
                if not key:
                    if lab:
                        key, conf = 'label-' + slug(lab), 'medium'
                    else:
                        stats['unparsed'].append('%s: <%s> without id, name or label (not inventoried)' % (rel, tag))
                        continue
                it = items.add('ctl:%s:%s:%s' % (file_id, kind, key), kind, rel, 'must', conf,
                               texts=[lab] if lab else None, attrs={'type': typ} if tag == 'input' else None)
                if tag == 'select':
                    close = src.find('</select', end, end + 6000)
                    inner = src[end:close] if close >= 0 else ''
                    leftover = re.sub(r'<option\b[^>]*>.*?</option>', '', inner, flags=re.S)
                    dynamic = '${' in leftover
                    for om in re.finditer(r'<option\b([^>]*)>(.*?)</option>', inner, re.S):
                        val = attrs_of(om.group(1)).get('value')
                        if val is None or '${' in val:
                            dynamic = True
                            continue
                        ol, oc = canon(om.group(2), res)
                        items.add('ctl:%s:option:%s:%s' % (file_id, key, val), 'ctl_option', rel, 'must', oc,
                                  texts=[ol] if ol else None)
                    if dynamic:
                        it['conf'] = 'medium'
                        it.setdefault('attrs', {})['dynamic_options'] = True


def control_files(root):
    web = os.path.join(root, 'web')
    out = []
    for f in sorted(os.listdir(web)):
        if f in SKIP_JS:
            continue
        if f.endswith('.js') or f == 'index.html':
            out.append('web/' + f)
    return out


# ---------------------------------------------------------------------------------------------- build
def build(root=DEFAULT_ROOT):
    root = os.path.abspath(root)
    stats = {'unparsed': []}
    rt = run_runtime(root)
    items = Items()
    routes_from_runtime(rt, items)
    rows = parse_seed_rows(root, stats)
    settings_from_seed(rows, items, stats)
    forms_from_runtime(rt, rows, items, stats)
    scan_controls(root, control_files(root), rt['i18n'], items, stats)
    for p in rt['problems']:
        stats['unparsed'].append('script did not load completely in the sandbox: ' + p)
    for f in rt.get('not_in_index', []):
        stats['unparsed'].append('web/%s is not referenced by web/index.html (inventoried anyway)' % f)
    return {
        'version': VERSION,
        'note': 'Generated by tools/build_ui_inventory.py. Do not edit by hand; see tests/ui_inventory/README.md.',
        'items': items.sorted(),
        'unparsed': sorted(set(stats['unparsed'])),
    }


def dumps(inv):
    """One item per line, stable key order: small diffs in git."""
    lines = [json.dumps(it, ensure_ascii=False, sort_keys=True) for it in inv['items']]
    head = json.dumps({'version': inv['version'], 'note': inv['note']}, ensure_ascii=False, sort_keys=True)[:-1]
    un = json.dumps(inv.get('unparsed', []), ensure_ascii=False, indent=0).replace('\n', '')
    return head + ',\n"unparsed": ' + un + ',\n"items": [\n' + ',\n'.join(lines) + '\n]}\n'


def counts(inv):
    c, medium = {}, 0
    for it in inv['items']:
        c[category(it['kind'])] = c.get(category(it['kind']), 0) + 1
        if it.get('conf') == 'medium':
            medium += 1
    return c, medium


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--root', default=DEFAULT_ROOT)
    ap.add_argument('--stdout', action='store_true')
    ap.add_argument('--out', default=None)
    a = ap.parse_args(argv)
    inv = build(a.root)
    text = dumps(inv)
    if a.stdout:
        sys.stdout.write(text)
        return 0
    out = a.out or os.path.join(a.root, BASELINE_REL)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        f.write(text)
    c, med = counts(inv)
    print('wrote %s: %d items, %s, medium confidence %d' % (os.path.relpath(out, a.root), len(inv['items']), c, med))
    return 0


if __name__ == '__main__':
    sys.exit(main())
