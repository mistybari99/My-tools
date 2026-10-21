#!/usr/bin/env python3
"""Owner word list for NEW screens: Save = সেভ, Date = ডেট (mix: Date), Approve = অ্যাপ্রুভ (mix: Approve), Save in mix = Save.
Rewrites only the bn and mix slots of L(bn, en, mix) triples and of { bn: "..", mix: ".." } rows in web/*.js; the en slot and code are never touched.
Rules (see docs/i18n/BANGLA_REVIEW.md, docs/briefs_p2p3/step_Wording_REPORT.md): bn mode writes the common English word in Bangla letters; mix mode writes it in Latin.
Only the exact owner words are changed; related words (অনুমোদনকারী = approver, অনুমোদিত = approved) are left as the advanced line left them.

usage: python3 tools/apply_owner_words.py [--dry-run] [--only-lines FILE] file.js [file.js ...]       (idempotent: a second run changes nothing)
"""
import re
import sys

BN = [('সংরক্ষণ', 'সেভ'), ('তারিখ', 'ডেট')]
MIX = [('সংরক্ষণ', 'Save'), ('তারিখ', 'Date')]
APPROVE_BN = re.compile(r'অনুমোদন(?![ািীুূৃেৈোৌ্ংঃঁ‌‍]|কারী|িত|ের)')   # the bare word (also followed by a space / punctuation / করুন)
APPROVE_MIX = APPROVE_BN
Q = r'''(?:'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|`(?:\\.|[^`\\])*`)'''
TRIPLE = re.compile(r'(\bL\(\s*)(' + Q + r')(\s*,\s*' + Q + r'\s*,\s*)(' + Q + r')(\s*\))')
OBJ = re.compile(r'(\bbn:\s*)(' + Q + r')(\s*,\s*mix:\s*)(' + Q + r')')


def fix_bn(s):
    for a, b in BN:
        s = s.replace(a, b)
    return APPROVE_BN.sub('অ্যাপ্রুভ', s)


def fix_mix(s):
    for a, b in MIX:
        s = s.replace(a, b)
    return APPROVE_MIX.sub('Approve', s)


def run(path, dry, only=None):
    t = open(path, encoding='utf-8').read()
    n = [0]
    if only is not None:      # only the lines in the set (lines our line added to a file that also holds older texts; older texts are never reworded)
        out = []
        for line in t.split('\n'):
            out.append(run_text(line, n) if line.strip() in only else line)
        u = '\n'.join(out)
        if u != t and not dry:
            open(path, 'w', encoding='utf-8').write(u)
        return n[0]

    u = run_text(t, n)
    if u != t and not dry:
        open(path, 'w', encoding='utf-8').write(u)
    return n[0]


def run_text(t, n):
    def tri(m):
        a, b = fix_bn(m.group(2)), fix_mix(m.group(4))
        if a != m.group(2) or b != m.group(4):
            n[0] += 1
        return m.group(1) + a + m.group(3) + b + m.group(5)

    def obj(m):
        a, b = fix_bn(m.group(2)), fix_mix(m.group(4))
        if a != m.group(2) or b != m.group(4):
            n[0] += 1
        return m.group(1) + a + m.group(3) + b

    return OBJ.sub(obj, TRIPLE.sub(tri, t))


if __name__ == '__main__':
    dry = '--dry-run' in sys.argv
    only = None
    if '--only-lines' in sys.argv:
        i = sys.argv.index('--only-lines')
        only = set(l.strip() for l in open(sys.argv[i + 1], encoding='utf-8').read().split('\n'))
        del sys.argv[i:i + 2]
    tot = 0
    for p in [a for a in sys.argv[1:] if not a.startswith('--')]:
        c = run(p, dry, only)
        tot += c
        if c:
            print('%s: %d string(s)' % (p, c))
    print('total', tot, '(dry run)' if dry else '')
