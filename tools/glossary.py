#!/usr/bin/env python3
"""Language standard for the Islamia BOS app.
  python3 tools/glossary.py          -> report words/phrases that have more than one English rendering
  python3 tools/glossary.py --fix    -> rewrite the English of the STANDARD terms below in web/*.js
Rules (also in docs/LANGUAGE.md): brand and location names are fixed and never translated; units, dates and common
words use ONE English term each; numbers use Latin digits everywhere. Add a term here when two places disagree."""
import re, glob, sys, collections
STANDARD = {
 'কেজি': 'KG', 'পিস': 'Piece', 'পাউন্ড': 'Pound', 'লিটার': 'Litre',
 'পরিমাণ': 'Quantity', 'মন্তব্য': 'Remark', 'ডিসকাউন্ট': 'Discount', 'ঠিক': 'OK',
 'শুরুর তারিখ': 'Start date', 'শেষের তারিখ': 'End date',
 'সীমার ভেতরে': 'Within the limit', 'সীমার বাইরে': 'Outside the limit',
 'অবস্থা': 'Status', 'লোকেশন': 'Location', 'শোরুম': 'Showroom',
 'পারচেজ রিকুইজিশন (PR) নং': 'Purchase Requisition (PR) no.',
 'পণ্যের বিবরণ': 'Product description',
}
PAT = re.compile(r"L\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'")
files = [f for f in glob.glob('web/*.js')]
if '--fix' in sys.argv:
    n = 0
    for f in files:
        s = open(f, encoding='utf-8').read()
        def sub(m):
            global n
            b = m.group(1).strip()
            if b in STANDARD and m.group(2) != STANDARD[b]:
                n += 1
                return "L('%s', '%s'" % (m.group(1), STANDARD[b])
            return m.group(0)
        t = PAT.sub(sub, s)
        if t != s: open(f, 'w', encoding='utf-8').write(t)
    print('standardised', n)
else:
    bn = collections.defaultdict(collections.Counter)
    for f in files:
        for m in PAT.finditer(open(f, encoding='utf-8').read()): bn[m.group(1).strip()][m.group(2).strip()] += 1
    bad = {b: c for b, c in bn.items() if len(c) > 1 and b in STANDARD}
    for b, c in bad.items(): print(repr(b), dict(c))
    print('terms still inconsistent:', len(bad))
    sys.exit(1 if bad else 0)
