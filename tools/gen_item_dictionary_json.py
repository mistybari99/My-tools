#!/usr/bin/env python3
"""data/item_dictionary.csv -> web/data/item_dictionary.json (the file the Item master import page fetches).
No prices or costs exist in the dictionary, so the file is safe for the public app repo.
Run from the repo root:  python3 tools/gen_item_dictionary_json.py"""
import csv, json, os, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = os.path.join(root, 'data', 'item_dictionary.csv')
dst = os.path.join(root, 'web', 'data', 'item_dictionary.json')
rows = list(csv.DictReader(open(src, encoding='utf-8')))
keys = ['code', 'cat_no', 'category', 'name_en', 'name_bn', 'subcategory', 'unit', 'control_class', 'note']
out = [{k: (r.get(k) or '').strip() for k in keys} for r in rows]
codes = [r['code'] for r in out]
assert len(codes) == len(set(codes)), 'duplicate codes'
os.makedirs(os.path.dirname(dst), exist_ok=True)
json.dump(out, open(dst, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print('rows', len(out), '->', dst, os.path.getsize(dst), 'bytes')
