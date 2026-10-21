#!/usr/bin/env python3
"""Coverage check for the (i) information entries in web/data/info.json.

What it does
  * Lists critical rules, grants and screens that have NO entry in web/data/info.json.
  * Exits 1 only when a RULE added in phase 80 or later has no `rule:<key>` entry.
    Everything else (older critical rules, screens, grants) is printed as information.
  * `--strict` also fails on a missing Wave 1 / critical screen entry.
  * `--merge FILE` merges a package file docs/integration/<pkg>_info.json into
    web/data/info.json (see docs/integration/INFO-1.md). It refuses a key that exists
    already unless `--replace` is given. `--dry` shows what it would do.

Critical means
  * rule: it has safe-default / effective-from / exception semantics (name or kind says so),
          or it was added in phase 80 or later;
  * screen: a Wave 1 route or one of the screens built with the Wave R1 to R4 phases.

Read only (except --merge). Needs no database. Run: python3 tools/check_info_coverage.py
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INFO = os.path.join(ROOT, 'web', 'data', 'info.json')
SQL_DIR = os.path.join(ROOT, 'supabase')
IA = os.path.join(ROOT, 'web', 'ia.js')

FIRST_NEW_PHASE = 80
WAVE1_ROUTES = ['openparties', 'periodlock', 'returnrules', 'profitcheck', 'moneycontrols', 'otherincome', 'bankreceipt', 'freshness']
OTHER_CRITICAL_ROUTES = ['accounts', 'moneyaccounts', 'balancecheck', 'shortages', 'wallets', 'monthclose', 'exceptions', 'ledgerlinks', 'paths']
# older rules that have no phase80+ marker are critical when their name or kind says so
CRIT_NAME = re.compile(r'(lock|approv|exception|override|_from$|_policy|_mode$|required|window|period|ledger|accounting|neg_|closed)')

RULE_BLOCK = re.compile(r'insert\s+into\s+(?:public\.)?rules\b(.*?)(?:on\s+conflict|;[ \t]*(?:--[^\n]*)?\n)', re.S | re.I)   # a ; inside a hint text is not the end
RULE_KEY_A = re.compile(r"\(\s*'([a-z][a-z0-9_]*)'\s*,\s*'[a-z_]+'\s*,\s*'(switch|choice|number|text|date)'")   # (key, module, kind
RULE_KEY_B = re.compile(r"\(\s*'([a-z][a-z0-9_]*)'\s*,\s*'(switch|choice|number|text|date)'\s*,")             # (key, kind  (module comes from select)
GRANT_BLOCK = re.compile(r'insert\s+into\s+(?:public\.)?grant_defs\b(.*?)(?:on\s+conflict|;[ \t]*(?:--[^\n]*)?\n)', re.S | re.I)
GRANT_KEY = re.compile(r"\(\s*'([a-z][a-z0-9_]*)'\s*,\s*'[a-z_]+'\s*,\s*\d+\s*,")


def phase_of(name):
    m = re.match(r'phase(\d+)', name)
    return int(m.group(1)) if m else None


def sql_files():
    for n in sorted(os.listdir(SQL_DIR)):
        if not n.endswith('.sql') or n.endswith('_test.sql') or n.startswith(('ALL_NEW', 'audit_')) or n == 'schema.sql':
            continue
        p = phase_of(n)
        if p is not None:
            yield p, os.path.join(SQL_DIR, n)


def seed_rules():
    """{key: (first_phase, kind)} from the seed SQL."""
    out = {}
    for p, path in sql_files():
        text = open(path, encoding='utf-8').read()
        for blk in RULE_BLOCK.finditer(text):
            body = blk.group(1)
            for rx in (RULE_KEY_A, RULE_KEY_B):
                for m in rx.finditer(body):
                    k, kind = m.group(1), m.group(2)
                    if k not in out or p < out[k][0]:
                        out[k] = (p, kind)
    return out


def seed_grants():
    out = {}
    for p, path in sql_files():
        text = open(path, encoding='utf-8').read()
        for blk in GRANT_BLOCK.finditer(text):
            for m in GRANT_KEY.finditer(blk.group(1)):
                k = m.group(1)
                if k not in out or p < out[k]:
                    out[k] = p
    return out


def ia_routes():
    if not os.path.exists(IA):
        return set()
    return set(re.findall(r"rec\('([a-z0-9_]+)'", open(IA, encoding='utf-8').read()))


def load_info():
    if not os.path.exists(INFO):
        return {}
    d = json.load(open(INFO, encoding='utf-8'))
    return d.get('entries', {}) if isinstance(d, dict) else {}


def merge(path, replace, dry):
    new = json.load(open(path, encoding='utf-8'))
    new = new.get('entries', new) if isinstance(new, dict) else {}
    doc = json.load(open(INFO, encoding='utf-8'))
    cur = doc.setdefault('entries', {})
    clash = [k for k in new if k in cur]
    if clash and not replace:
        print('REFUSED: these keys exist already (use --replace to overwrite):')
        for k in clash:
            print('  ' + k)
        return 1
    bad = [k for k in new if not re.match(r'^(rule|screen|grant|switch|feature):', k)]
    if bad:
        print('REFUSED: keys must start with rule: screen: grant: switch: or feature: :', ', '.join(bad))
        return 1
    print(('would merge ' if dry else 'merged ') + str(len(new)) + ' entries (' + str(len(clash)) + ' replaced)')
    if not dry:
        cur.update(new)
        doc['entries'] = {k: cur[k] for k in sorted(cur)}
        with open(INFO, 'w', encoding='utf-8') as f:
            json.dump(doc, f, indent=1, ensure_ascii=False)
            f.write('\n')
    return 0


def main(argv):
    if '--merge' in argv:
        i = argv.index('--merge')
        return merge(argv[i + 1], '--replace' in argv, '--dry' in argv)
    strict = '--strict' in argv
    info = load_info()
    rules = seed_rules()
    grants = seed_grants()
    routes = ia_routes()

    new_rules = sorted(k for k, (p, _) in rules.items() if p >= FIRST_NEW_PHASE)
    missing_new = [k for k in new_rules if 'rule:' + k not in info]
    old_crit = sorted(k for k, (p, kind) in rules.items() if p < FIRST_NEW_PHASE and (kind == 'choice' or CRIT_NAME.search(k)))
    missing_old = [k for k in old_crit if 'rule:' + k not in info]
    crit_screens = [r for r in WAVE1_ROUTES + OTHER_CRITICAL_ROUTES if r in routes or not routes]
    missing_screens = [r for r in crit_screens if 'screen:' + r not in info]
    new_grants = sorted(k for k, p in grants.items() if p >= FIRST_NEW_PHASE)
    missing_grants = [k for k in new_grants if 'grant:' + k not in info]

    print('info entries: %d' % len(info))
    print('rules added in phase %d or later: %d, with an entry: %d' % (FIRST_NEW_PHASE, len(new_rules), len(new_rules) - len(missing_new)))
    print('grants added in phase %d or later: %d, with an entry: %d' % (FIRST_NEW_PHASE, len(new_grants), len(new_grants) - len(missing_grants)))
    print('critical screens: %d, with an entry: %d' % (len(crit_screens), len(crit_screens) - len(missing_screens)))
    if missing_grants:
        print('\nInformation: grants since phase %d WITHOUT an entry:' % FIRST_NEW_PHASE)
        for k in missing_grants:
            print('  grant:' + k)
    if missing_screens:
        print('\nInformation: critical screens WITHOUT an entry%s:' % (' (FAILS in --strict)' if strict else ''))
        for r in missing_screens:
            print('  screen:' + r)
    if missing_old:
        print('\nInformation: older critical rules (before phase %d) WITHOUT an entry:' % FIRST_NEW_PHASE)
        for k in missing_old:
            print('  rule:%s  (phase %d)' % (k, rules[k][0]))
    if missing_new:
        print('\nFAIL: rules added in phase %d or later WITHOUT an entry:' % FIRST_NEW_PHASE)
        for k in missing_new:
            print('  rule:%s  (phase %d)' % (k, rules[k][0]))
        return 1
    if strict and missing_screens:
        return 1
    print('\nOK: every rule added in phase %d or later has an entry.' % FIRST_NEW_PHASE)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
