#!/usr/bin/env python3
"""No-loss check for the UI: compares the CURRENT tree with tests/ui_inventory/baseline.json.

    python3 tools/check_ui_inventory.py                    # exit 0 = nothing lost, exit 1 = something lost or renamed
    python3 tools/check_ui_inventory.py --report           # counts per category (baseline vs current) and confidence split
    python3 tools/check_ui_inventory.py --update-baseline  # ADD new items to the baseline (never drops, never edits)

Fails (exit 1) when a baseline item of level "must" (route, form, field, option, button/tab/input/select, RPC name,
settings key, group, text ...) is missing from the tree, or its label text changed. A rename is only accepted when
tests/ui_inventory/aliases.json holds an explicit entry with a reason. Additions are always allowed.
Items of level "info" (search keywords, form sections, notes, placement lists) are listed as notes, not failures
(use --strict-info to fail on them too).

Standard library only; node (preinstalled) is used by the extractor. Rules: docs/UI_NO_LOSS_RULE.md.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_ui_inventory as B  # noqa: E402

ALIASES_REL = os.path.join('tests', 'ui_inventory', 'aliases.json')
PLACEMENT_ATTRS = ('group', 'drawer', 'status', 'mob', 'mod', 'home', 'cc', 'parent')
MAX_LINES = 60


def load_json(path, default=None):
    if not os.path.exists(path):
        return default
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def load_aliases(path):
    """-> (alias set structures, errors). Every alias must carry a non-empty reason."""
    data = load_json(path, {'aliases': []}) or {'aliases': []}
    errors = []
    ren, prefix, labels, waivers = {}, [], {}, set()
    for n, a in enumerate(data.get('aliases', [])):
        where = 'aliases.json entry #%d' % (n + 1)
        if not isinstance(a, dict) or not str(a.get('reason', '')).strip():
            errors.append('%s has no "reason" (an alias without a reason is not accepted)' % where)
            continue
        t = a.get('type') or ('rename' if 'to' in a and 'id' not in a else '')
        if t == 'rename' and a.get('from') and a.get('to'):
            ren[a['from']] = a['to']
        elif t == 'prefix' and a.get('from') and a.get('to'):
            prefix.append((a['from'], a['to']))
        elif t == 'label' and a.get('id') and a.get('lang') and 'from' in a and 'to' in a:
            labels[(a['id'], a['lang'], a['from'])] = a['to']
        elif t == 'placement' and a.get('id') and a.get('attr'):
            waivers.add((a['id'], a['attr']))
        else:
            errors.append('%s is not understood (types: rename, prefix, label, placement; see docs/UI_NO_LOSS_RULE.md)' % where)
    return {'rename': ren, 'prefix': prefix, 'labels': labels, 'waivers': waivers}, errors


def resolve_id(i, al):
    if i in al['rename']:
        return al['rename'][i]
    for a, b in al['prefix']:
        if i.startswith(a):
            return b + i[len(a):]
    return i


def compare(base_items, cur_items, al):
    cur = {it['id']: it for it in cur_items}
    res = {'missing': [], 'renamed': [], 'moved': [], 'downgraded': [], 'covered': 0}
    mapped = set()
    for b in base_items:
        cid = resolve_id(b['id'], al)
        c = cur.get(cid)
        info = b.get('level') == 'info'
        if c is None:
            res['missing'].append((b, cid))
            continue
        mapped.add(cid)
        if cid != b['id']:
            res['covered'] += 1
        for lang, old in sorted((b.get('labels') or {}).items()):
            new = (c.get('labels') or {}).get(lang)
            if new != old:
                if al['labels'].get((b['id'], lang, old)) == new and new is not None:
                    res['covered'] += 1
                    continue
                res['renamed'].append((b, lang, old, new))
        cur_texts = c.get('texts') or []
        for old in b.get('texts') or []:
            if old not in cur_texts:
                tgt = al['labels'].get((b['id'], 'texts', old))
                if tgt is not None and tgt in cur_texts:
                    res['covered'] += 1
                    continue
                res['renamed'].append((b, 'texts', old, ' | '.join(cur_texts) if cur_texts else None))
        ba, ca = b.get('attrs') or {}, c.get('attrs') or {}
        if b['kind'] == 'route':
            if ba.get('status') == 'live' and ca.get('status') != 'live' and (b['id'], 'status') not in al['waivers']:
                res['downgraded'].append((b, 'status', ba.get('status'), ca.get('status')))
            if ba.get('drawer') is True and ca.get('drawer') is not True and (b['id'], 'drawer') not in al['waivers']:
                res['downgraded'].append((b, 'drawer', ba.get('drawer'), ca.get('drawer')))
            for k in PLACEMENT_ATTRS:
                if k in ('status', 'drawer'):
                    continue
                if ba.get(k) != ca.get(k):
                    res['moved'].append((b, k, ba.get(k), ca.get(k)))
        elif b['kind'] == 'placement' and ba != ca:
            res['moved'].append((b, 'position', ba, ca))
    res['added'] = [it for it in cur_items if it['id'] not in mapped and it['id'] not in {x['id'] for x in base_items}]
    return res


def show(title, lines):
    if not lines:
        return
    print(title)
    for ln in lines[:MAX_LINES]:
        print('  ' + ln)
    if len(lines) > MAX_LINES:
        print('  ... and %d more' % (len(lines) - MAX_LINES))


def describe(it):
    lab = it.get('labels') or {}
    name = lab.get('en') or lab.get('bn') or lab.get('text') or ''
    if not name and it.get('texts'):
        name = it['texts'][0]
    return '%s%s' % (it['id'], ('  ("%s")' % name[:60]) if name else '')


def report(inv, title):
    c, med = B.counts(inv)
    total = len(inv['items'])
    print('%s: %d items, medium confidence %d (%.1f%%)' % (title, total, med, 100.0 * med / max(1, total)))
    for k in ('routes', 'forms', 'fields', 'options', 'controls', 'settings keys', 'other'):
        print('  %-14s %d' % (k, c.get(k, 0)))
    kinds = {}
    for it in inv['items']:
        kinds[it['kind']] = kinds.get(it['kind'], 0) + 1
    print('  by kind: ' + ', '.join('%s=%d' % (k, kinds[k]) for k in sorted(kinds)))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--root', default=B.DEFAULT_ROOT, help='tree to check (default: this repository)')
    ap.add_argument('--baseline', default=None)
    ap.add_argument('--aliases', default=None)
    ap.add_argument('--report', action='store_true', help='print counts per category')
    ap.add_argument('--update-baseline', action='store_true', help='add new items to the baseline (never drops or edits)')
    ap.add_argument('--strict-info', action='store_true', help='also fail when info-level items (keywords, sections, notes) are lost')
    ap.add_argument('--strict-placement', action='store_true', help='also fail when a route moves to another group / slot')
    a = ap.parse_args(argv)
    root = os.path.abspath(a.root)
    base_path = a.baseline or os.path.join(root, B.BASELINE_REL)
    alias_path = a.aliases or os.path.join(root, ALIASES_REL)

    baseline = load_json(base_path)
    if baseline is None:
        print('ERROR: no baseline at %s. Create it once with: python3 tools/build_ui_inventory.py' % base_path)
        return 2
    cur_inv = B.build(root)

    if a.report:
        report(baseline, 'baseline')
        report(cur_inv, 'current ')
        un = cur_inv.get('unparsed', [])
        print('not statically readable / notes: %d' % len(un))
        for u in un:
            print('  - ' + u)
        return 0

    al, alias_errors = load_aliases(alias_path)
    res = compare(baseline['items'], cur_inv['items'], al)

    if a.update_baseline:
        known = {it['id'] for it in baseline['items']}
        new = [it for it in cur_inv['items'] if it['id'] not in known]
        if new:
            merged = dict(baseline)
            merged['items'] = sorted(baseline['items'] + new, key=lambda x: x['id'])
            merged['unparsed'] = sorted(set(baseline.get('unparsed', [])) | set(cur_inv.get('unparsed', [])))
            with open(base_path, 'w', encoding='utf-8') as f:
                f.write(B.dumps(merged))
        print('baseline updated: %d new items added, %d existing items untouched, none dropped.' % (len(new), len(baseline['items'])))

    fatal = []
    for e in alias_errors:
        fatal.append(e)
    missing_must = [(b, cid) for b, cid in res['missing'] if b.get('level') != 'info']
    missing_info = [(b, cid) for b, cid in res['missing'] if b.get('level') == 'info']
    ren_must = [r for r in res['renamed'] if r[0].get('level') != 'info']
    ren_info = [r for r in res['renamed'] if r[0].get('level') == 'info']

    show('MISSING (in the baseline, gone from the tree; %d):' % len(missing_must),
         ['%s%s' % (describe(b), ('  -> alias target %s does not exist' % cid) if cid != b['id'] else '') for b, cid in missing_must])
    show('RENAMED (label text changed; add an alias with a reason if intended; %d):' % len(ren_must),
         ['%s [%s] "%s" -> %s' % (b['id'], lang, str(old)[:70], ('"%s"' % str(new)[:70]) if new is not None else 'MISSING') for b, lang, old, new in ren_must])
    show('MENU ENTRY NO LONGER REACHABLE (route not live / not in the drawer; %d):' % len(res['downgraded']),
         ['%s  %s: %s -> %s' % (b['id'], k, o, n) for b, k, o, n in res['downgraded']])
    show('ALIAS PROBLEMS:', alias_errors)
    notes = []
    notes += ['info item gone: ' + describe(b) for b, _ in missing_info]
    notes += ['info label changed: %s [%s] "%s" -> %s' % (b['id'], lang, str(old)[:60], new) for b, lang, old, new in ren_info]
    notes += ['moved: %s  %s: %s -> %s' % (b['id'], k, o, n) for b, k, o, n in res['moved']]
    show('NOTES (not failures unless --strict-info / --strict-placement; %d):' % len(notes), notes)

    n_fatal = len(missing_must) + len(ren_must) + len(res['downgraded']) + len(alias_errors)
    if a.strict_info:
        n_fatal += len(missing_info) + len(ren_info)
    if a.strict_placement:
        n_fatal += len(res['moved'])
    total = len(baseline['items'])
    print('checked %d baseline items against the current tree: %d added since the baseline, %d accepted through aliases.'
          % (total, len(res['added']), res['covered']))
    if n_fatal:
        print('FAIL: %d problem(s). Nothing may be lost silently (docs/UI_NO_LOSS_RULE.md).' % n_fatal)
        return 1
    print('OK: nothing lost, nothing renamed silently.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
