#!/usr/bin/env python3
"""Maps the 57 old seed items (data/items_seed.csv) onto the dictionary 'Finished Good' items by best match.
Output: docs/inputs/seed_item_mapping.csv  (seed_code, seed_name, seed_unit, seed_price, best_code, best_name, best_unit, confidence, auto, runner_up)
Only confidence >= HIGH (and a clear lead over the runner-up) is flagged auto=1 (auto-linked); the rest are 'needs decision'.
Prices are NOT written to the output (the mapping file is safe to share). seed_code = I-001.. in file order, as the database numbers them.
Run from the repo root:  python3 tools/map_seed_items.py"""
import csv, os, re, unicodedata, difflib
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIGH = 0.85      # auto-link at or above this (and every word of the old name must equal the dictionary name's words)
SUGGEST = 0.6    # below this nothing is suggested
LEAD = 0.08      # and at least this far above the runner-up
seed = list(csv.DictReader(open(os.path.join(root, 'data', 'items_seed.csv'), encoding='utf-8')))
dic = list(csv.DictReader(open(os.path.join(root, 'data', 'item_dictionary.csv'), encoding='utf-8')))
cands = [d for d in dic if d['control_class'] == 'Finished Good' and not d['name_en'].startswith('RETIRED')]

BN2EN = str.maketrans('০১২৩৪৫৬৭৮৯', '0123456789')
SYN = [('ক্ষীর', 'ক্ষির'), ('ী', 'ি'), ('ূ', 'ু'), ('শ', 'স'), ('ষ', 'স'), ('য়', 'য'), ('ড়', 'র'), ('ঢ়', 'র'), ('ণ', 'ন'), ('জ', 'য'),
       ('চকলেট', 'চকোলেট'), ('গোল্লা', 'গোলা'), ('কালোজাম', 'কালো জাম'), ('ক্রিমজাম', 'ক্রিম জাম'), ('লাড্ডু', 'লাডু'), ('লাডডু', 'লাডু'), ('নাড়ু', 'লাডু')]
STOP = {'কেজি', 'পিস', 'পাউন্ড', 'গ্রাম', 'মিলি', 'লিটার', 'প্যাক', 'এর', 'ও', 'রেগুলার', 'স্পেশাল', 'ছোট', 'বড়', 'মাঝারি', 'হাফ', 'স্লাইস৮'}
def norm(s):
    s = unicodedata.normalize('NFC', s).translate(BN2EN).lower()
    s = re.sub(r'\(.*?\)', ' ', s)
    s = re.sub(r'[–—\-,/।.:()]', ' ', s)
    s = ' '.join(t for t in s.split() if t not in STOP and not t.isdigit())      # unit / size words go before the spelling fold (it changes জ)
    for a, b in SYN: s = s.replace(a, b)
    return s
def toks(s): return set(norm(s).split())
FAMILY = {'kg': {'kg'}, 'pc': {'pc', 'pack', 'box'}, 'pound': {'pound'}}
def unit_of(s):
    t = s['product_name']
    if s['category'].endswith('KG') or 'কেজি' in t: return 'kg'
    if 'পাউন্ড' in t or s['category'].startswith('Cake / Pound'): return 'pound'
    return 'pc'
def parts(s, d):
    a, b = toks(s['product_name']), toks(d['name_bn'])
    if not a or not b: return 0.0, 0.0
    inter = len(a & b)
    return inter / len(a), inter / len(a | b)
def score(s, d):
    """0 when the unit family or the category is wrong or less than half of the old name's words are in the dictionary name (then nothing is suggested)"""
    if d['unit'] not in FAMILY[unit_of(s)]: return 0.0, 0.0, 0.0
    c = d['cat_no']; k = s['category']
    if (k.startswith('Misty') and c != '14') or (k == 'Doi' and c not in ('15', '14')) or (k.startswith('Cake') and c != '13'): return 0.0, 0.0, 0.0
    cont, jac = parts(s, d)
    if cont < 0.5: return 0.0, cont, jac
    return round(0.6 * cont + 0.4 * jac, 3), cont, jac
rows = []
for i, s in enumerate(seed, 1):
    sc = sorted(((score(s, d), d) for d in cands), key=lambda x: (-x[0][0], x[1]['code']))
    ((b, bc, bj), bd), ((r, _, _), rd) = sc[0], sc[1]
    if b < SUGGEST:
        rows.append({'seed_code': 'I-%03d' % i, 'seed_name': s['product_name'], 'seed_unit': unit_of(s), 'best_code': '', 'best_name': '', 'best_unit': '', 'confidence': '0.000', 'auto': 0, 'runner_up': ''}); continue
    auto = 1 if (b >= HIGH and b - r >= LEAD and bc == 1.0 and bj == 1.0) else 0
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
for r in rows: print(r['seed_code'], r['seed_name'], '=>', r['best_code'] or '-', r['best_name'], r['confidence'], 'AUTO' if r['auto'] else '')
