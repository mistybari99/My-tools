#!/usr/bin/env python3
"""Maps the 57 old seed items (data/items_seed.csv) onto the dictionary 'Finished Good' items by best match.
Output: docs/inputs/seed_item_mapping.csv  (seed_code, seed_name, seed_unit, seed_price, best_code, best_name, best_unit, confidence, auto, runner_up)
Only confidence >= HIGH (and a clear lead over the runner-up) is flagged auto=1 (auto-linked); the rest are 'needs decision'.
Prices are NOT written to the output (the mapping file is safe to share). seed_code = I-001.. in file order, as the database numbers them.
Run from the repo root:  python3 tools/map_seed_items.py"""
import csv, os, re, unicodedata, difflib
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIGH = 0.85      # auto-link at or above this
LEAD = 0.08      # and at least this far above the runner-up
seed = list(csv.DictReader(open(os.path.join(root, 'data', 'items_seed.csv'), encoding='utf-8')))
dic = list(csv.DictReader(open(os.path.join(root, 'data', 'item_dictionary.csv'), encoding='utf-8')))
cands = [d for d in dic if d['control_class'] == 'Finished Good' and not d['name_en'].startswith('RETIRED')]

BN2EN = str.maketrans('০১২৩৪৫৬৭৮৯', '0123456789')
SYN = [('ক্ষীর', 'ক্ষির'), ('ী', 'ি'), ('ূ', 'ু'), ('শ', 'স'), ('ষ', 'স'), ('য়', 'য'), ('ড়', 'র'), ('ঢ়', 'র'), ('ণ', 'ন'), ('জ', 'য'),
       ('গোল্লা', 'গোলা'), ('জামুন', 'জাম'), ('কালোজাম', 'কালো জাম'), ('ক্রিমজাম', 'ক্রিম জাম'), ('লাড্ডু', 'লাডু'), ('লাডডু', 'লাডু'), ('নাড়ু', 'লাডু')]
STOP = {'কেজি', 'পিস', 'পাউন্ড', 'গ্রাম', 'প্যাক', 'এর', 'ও'}
def norm(s):
    s = unicodedata.normalize('NFC', s).translate(BN2EN).lower()
    s = re.sub(r'\(.*?\)', ' ', s)
    s = re.sub(r'[–—\-,/।.:()]', ' ', s)
    s = ' '.join(t for t in s.split() if t not in STOP)       # unit words go before the spelling fold (it changes জ)
    for a, b in SYN: s = s.replace(a, b)
    return s
def toks(s): return [t for t in norm(s).split() if t not in STOP]
def sim(a, b):
    ta, tb = toks(a), toks(b)
    if not ta or not tb: return 0.0
    ja = len(set(ta) & set(tb)) / len(set(ta) | set(tb))
    ca, cb = ''.join(ta), ''.join(tb)
    cs = difflib.SequenceMatcher(None, ca, cb).ratio()
    return 0.45 * ja + 0.55 * cs
def unit_of(s):
    t = s['product_name']
    if s['category'].endswith('KG') or 'কেজি' in t: return 'kg'
    if 'পাউন্ড' in t or s['category'].startswith('Cake / Pound'): return 'pound'
    return 'pc'
def score(s, d):
    n = sim(s['product_name'], d['name_bn'])
    su, du = unit_of(s), d['unit']
    u = 1.0 if su == du else (0.5 if {su, du} <= {'pc', 'pack', 'box'} else 0.0)
    cat_ok = 1.0
    c = d['cat_no']; k = s['category']
    if k.startswith('Misty') and c != '14': cat_ok = 0.0
    if k == 'Doi' and c not in ('15', '14'): cat_ok = 0.0
    if k.startswith('Cake') and c != '13': cat_ok = 0.0
    return round(max(0.0, 0.8 * n + 0.2 * u) * (1.0 if cat_ok else 0.7), 3)
rows = []
for i, s in enumerate(seed, 1):
    sc = sorted(((score(s, d), d) for d in cands), key=lambda x: -x[0])
    (b, bd), (r, rd) = sc[0], sc[1]
    auto = 1 if (b >= HIGH and b - r >= LEAD) else 0
    rows.append({'seed_code': 'I-%03d' % i, 'seed_name': s['product_name'], 'seed_unit': unit_of(s), 'best_code': bd['code'], 'best_name': bd['name_bn'], 'best_unit': bd['unit'],
                 'confidence': '%.3f' % b, 'auto': auto, 'runner_up': '%s (%.3f)' % (rd['code'], r)})
out = os.path.join(root, 'docs', 'inputs', 'seed_item_mapping.csv')
with open(out, 'w', encoding='utf-8', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
import json
jr = [{'seed_code': r['seed_code'], 'seed_name': r['seed_name'], 'best_code': r['best_code'], 'confidence': float(r['confidence']), 'auto': int(r['auto'])} for r in rows]
jp = os.path.join(root, 'web', 'data', 'seed_item_mapping.json')
os.makedirs(os.path.dirname(jp), exist_ok=True)
json.dump(jr, open(jp, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))     # names only, no prices: safe for the public app repo
print('seed items', len(rows), 'auto', sum(r['auto'] for r in rows), 'needs decision', sum(1 - r['auto'] for r in rows), '->', out)
for r in rows: print(r['seed_code'], r['seed_name'], '=>', r['best_code'], r['best_name'], r['confidence'], 'AUTO' if r['auto'] else '')
