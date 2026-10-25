#!/usr/bin/env python3
"""Self-test for tools/check_ui_inventory.py: proves the check really fails when something is lost.

For each case a temporary copy of the tree (web/*.js, web/index.html, supabase/ by symlink) is changed and the checker
is run against the committed baseline:
  passes   : unmodified tree; a new route, new button and new option added; an intended rename WITH an alias
  must fail: (i) a route removed  (ii) a form field removed  (iii) a form option removed
             (iv) a button label removed, a button removed, a button label changed
             a rename without alias, an alias without a reason
  and: --update-baseline only adds (every old item stays byte-identical).
Usage: python3 tools/test_ui_inventory.py        (exit 0 = all cases behave as required)
Standard library + preinstalled node only. Writes only into a temporary folder.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
CHECK = os.path.join(HERE, 'check_ui_inventory.py')
BASELINE = os.path.join(REPO, 'tests', 'ui_inventory', 'baseline.json')

results = []


def make_tree(tmp):
    root = tempfile.mkdtemp(prefix='tree_', dir=tmp)
    os.makedirs(os.path.join(root, 'web'))
    for f in os.listdir(os.path.join(REPO, 'web')):
        if f.endswith('.js') or f == 'index.html':
            shutil.copy(os.path.join(REPO, 'web', f), os.path.join(root, 'web', f))
    os.symlink(os.path.join(REPO, 'supabase'), os.path.join(root, 'supabase'))
    return root


def edit(root, rel, fn):
    p = os.path.join(root, rel)
    s = open(p, encoding='utf-8').read()
    t = fn(s)
    if t == s:
        raise SystemExit('test setup error: the edit did not change %s (the code moved? update tools/test_ui_inventory.py)' % rel)
    open(p, 'w', encoding='utf-8').write(t)


def replace_once(old, new):
    def f(s):
        if old not in s:
            raise SystemExit('test setup error: text not found: ' + old[:70])
        return s.replace(old, new, 1)
    return f


def replace_all(old, new):
    def f(s):
        if old not in s:
            raise SystemExit('test setup error: text not found: ' + old[:70])
        return s.replace(old, new)
    return f


def drop_line(starts):
    def f(s):
        lines = s.split('\n')
        keep = [ln for ln in lines if not ln.lstrip().startswith(starts)]
        if len(keep) == len(lines):
            raise SystemExit('test setup error: no line starts with ' + starts)
        return '\n'.join(keep)
    return f


def repo_aliases():
    p = os.path.join(REPO, 'tests', 'ui_inventory', 'aliases.json')
    return json.load(open(p, encoding='utf-8')).get('aliases', []) if os.path.exists(p) else []


def run(root, extra=None, aliases=None, baseline=BASELINE):
    cmd = [sys.executable, CHECK, '--root', root, '--baseline', baseline]
    if aliases:
        cmd += ['--aliases', aliases]
    else:
        # every case without its own alias file uses the repository's own aliases (the intended renames, each with a reason), so a tree that has such a rename still passes unmodified
        al = os.path.join(root, 'no_aliases.json')
        repo_al = os.path.join(REPO, 'tests', 'ui_inventory', 'aliases.json')
        shutil.copy(repo_al, al) if os.path.exists(repo_al) else open(al, 'w').write('{"aliases": []}')
        cmd += ['--aliases', al]
    cmd += extra or []
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def case(name, expect_rc, root, must_contain=(), **kw):
    rc, out = run(root, **kw)
    ok = rc == expect_rc and all(m in out for m in must_contain)
    results.append(ok)
    print('%s  %s  (exit %d, expected %d)' % ('PASS' if ok else 'FAIL', name, rc, expect_rc))
    if not ok:
        print('\n'.join('      | ' + ln for ln in out.splitlines()[-25:]))


def main():
    if not os.path.exists(BASELINE):
        print('ERROR: baseline missing; run tools/build_ui_inventory.py first')
        return 2
    tmp = tempfile.mkdtemp(prefix='ui_inv_test_')
    try:
        # 0. unmodified tree passes
        r0 = make_tree(tmp)
        case('unmodified tree passes', 0, r0, ['OK: nothing lost'])

        # (i) a route removed
        r = make_tree(tmp)
        edit(r, 'web/ia.js', drop_line("rec('bulkitems'"))
        case('(i) route removed -> fails', 1, r, ['MISSING', 'route:bulkitems'])

        # (ii) a form field removed
        r = make_tree(tmp)
        edit(r, 'web/forms.js', replace_once(", T('sheet_no', L('দৈনিক শোরুম শিট নং', 'Daily showroom sheet no.'))", ''))
        case('(ii) form field removed -> fails', 1, r, ['MISSING', 'field:11-1:sheet_no'])

        # (iii) a form option removed
        r = make_tree(tmp)
        edit(r, 'web/forms.js', replace_once("['hospitality', L('কাস্টমার আপ্যায়ন', 'Customer hospitality')],", ''))
        case('(iii) form option removed -> fails', 1, r, ['MISSING', 'option:11-1:lines.head:hospitality'])

        # (iv) button label removed / button removed / label changed
        r = make_tree(tmp)
        edit(r, 'web/dues.js', replace_all('data-act="closesheet">${esc(T(\'close\'))}', 'data-act="closesheet">'))
        case('(iv) button label removed -> fails', 1, r, ['RENAMED', 'ctl:dues.js:button:closesheet'])

        r = make_tree(tmp)
        edit(r, 'web/dues.js', replace_once('<button class="primary" data-act="du_limit" style="align-self:flex-end">${esc(T(\'save\'))}</button>', ''))
        case('(iv) button removed -> fails', 1, r, ['MISSING', 'ctl:dues.js:button:du_limit'])

        r = make_tree(tmp)
        edit(r, 'web/dues.js', replace_once("save: L('সেভ', 'Save', 'Save')", "save: L('সেভ', 'Store', 'Store')"))
        case('(iv) button label renamed -> fails', 1, r, ['RENAMED', 'ctl:dues.js:button:du_limit'])

        # an input/select (screen option) removed
        r = make_tree(tmp)
        edit(r, 'web/dues.js', replace_once('<input id="du_note">', ''))
        case('screen input removed -> fails', 1, r, ['MISSING', 'ctl:dues.js:input:du_note'])

        # additions are allowed
        r = make_tree(tmp)
        src = open(os.path.join(r, 'web', 'ia.js'), encoding='utf-8').read().split('\n')
        line = next(ln for ln in src if ln.lstrip().startswith("rec('bulkitems'"))
        edit(r, 'web/ia.js', replace_once(line, line + '\n  ' + line.strip().replace("rec('bulkitems'", "rec('zz_new_screen'", 1)))
        edit(r, 'web/dues.js', replace_once('<input id="du_note">', '<input id="du_note"><button data-act="zz_new_btn">New</button>'))
        edit(r, 'web/forms.js', replace_once("['hospitality', L('কাস্টমার আপ্যায়ন', 'Customer hospitality')],", "['hospitality', L('কাস্টমার আপ্যায়ন', 'Customer hospitality')], ['zz_new_head', L('নতুন', 'New head')],"))
        case('new route + button + option added -> passes', 0, r, ['added since the baseline', 'OK: nothing lost'])
        rc, out = run(r)
        results.append(': 0 added' not in out)
        print('%s  additions are counted' % ('PASS' if ': 0 added' not in out else 'FAIL'))

        # --update-baseline only adds
        bcopy = os.path.join(tmp, 'baseline_copy.json')
        shutil.copy(BASELINE, bcopy)
        rc, out = run(r, extra=['--update-baseline'], baseline=bcopy)
        old = {i['id']: i for i in json.load(open(BASELINE, encoding='utf-8'))['items']}
        new = {i['id']: i for i in json.load(open(bcopy, encoding='utf-8'))['items']}
        ok = rc == 0 and set(old) < set(new) and all(new[k] == v for k, v in old.items()) \
            and {'route:zz_new_screen', 'ctl:dues.js:button:zz_new_btn', 'option:11-1:lines.head:zz_new_head'} <= set(new)
        results.append(ok)
        print('%s  --update-baseline adds %d new items and leaves every old item untouched' % ('PASS' if ok else 'FAIL', len(new) - len(old)))
        # a removed item stays in the baseline even after --update-baseline on a tree that lost it
        r = make_tree(tmp)
        edit(r, 'web/ia.js', drop_line("rec('bulkitems'"))
        bcopy2 = os.path.join(tmp, 'baseline_copy2.json')
        shutil.copy(BASELINE, bcopy2)
        rc, out = run(r, extra=['--update-baseline'], baseline=bcopy2)
        still = 'route:bulkitems' in {i['id'] for i in json.load(open(bcopy2, encoding='utf-8'))['items']}
        ok = rc == 1 and still
        results.append(ok)
        print('%s  --update-baseline never drops a lost item (and the check still fails)' % ('PASS' if ok else 'FAIL'))

        # rename: fails without alias, passes with alias + reason, fails when the alias has no reason
        r = make_tree(tmp)
        edit(r, 'web/ia.js', replace_once("rec('bulkitems',", "rec('bulkitems2',"))
        case('route renamed without alias -> fails', 1, r, ['MISSING', 'route:bulkitems'])
        al = os.path.join(tmp, 'aliases_ok.json')
        json.dump({'aliases': repo_aliases() + [{'type': 'rename', 'from': 'route:bulkitems', 'to': 'route:bulkitems2', 'reason': 'self-test: intended rename'}]},
                  open(al, 'w'))
        case('route renamed WITH alias + reason -> passes', 0, r, ['OK: nothing lost'], aliases=al)
        al2 = os.path.join(tmp, 'aliases_noreason.json')
        json.dump({'aliases': [{'type': 'rename', 'from': 'route:bulkitems', 'to': 'route:bulkitems2'}]}, open(al2, 'w'))
        case('alias without a reason -> fails', 1, r, ['reason'], aliases=al2)

        # label alias
        r = make_tree(tmp)
        edit(r, 'web/dues.js', replace_once("save: L('সেভ', 'Save', 'Save')", "save: L('সেভ', 'Store', 'Store')"))
        al3 = os.path.join(tmp, 'aliases_label.json')
        json.dump({'aliases': repo_aliases() + [{'type': 'label', 'id': 'ctl:dues.js:button:du_limit', 'lang': 'texts',
                                'from': 'L:সংরক্ষণ|Save|Save', 'to': 'L:সেভ|Store|Store', 'reason': 'self-test: intended label change'},
                               {'type': 'label', 'id': 'ctl:dues.js:button:du_limit', 'lang': 'texts',
                                'from': 'L:সংরক্ষণ|Save|Save', 'to': 'L:সেভ|Store|Store', 'reason': 'duplicate is harmless'}]}, open(al3, 'w'))
        rc, out = run(r, aliases=al3)
        # other buttons share the same text table key 'save' in dues.js, so each needs its own alias; the one aliased item must no longer be listed
        listed = 'ctl:dues.js:button:du_limit' in out.split('NOTES')[0]
        results.append(not listed)
        print('%s  label alias silences exactly the aliased item' % ('PASS' if not listed else 'FAIL'))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    bad = results.count(False)
    print('\n%d checks, %d failed' % (len(results), bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
