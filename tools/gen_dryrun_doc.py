#!/usr/bin/env python3
"""Writes docs/DRYRUN_item_master.md from docs/inputs/dryrun_preview.json (output of item_master_import_preview on a scratch db) and docs/inputs/seed_item_mapping.csv."""
import json, csv, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = lambda *a: os.path.join(root, *a)
pv = json.load(open(P('docs', 'inputs', 'dryrun_preview.json')))
rows = list(csv.DictReader(open(P('docs', 'inputs', 'seed_item_mapping.csv'), encoding='utf-8')))
dic = {r['code']: r for r in csv.DictReader(open(P('data', 'item_dictionary.csv'), encoding='utf-8'))}
tl = {'finished_good': 'Finished good', 'resale': 'Resale (Stock/Direct Sale)', 'raw_material': 'Raw material', 'packaging': 'Packaging', 'consumable': 'Consumable', 'asset': 'Asset', 'controlled': 'Controlled item (tools)', 'infrastructure': 'Infrastructure material'}
cls = {'finished_good': 'Finished Good', 'resale': 'Stock/Direct Sale', 'raw_material': 'Raw Material', 'packaging': 'Packaging', 'consumable': 'Consumable', 'asset': 'Asset', 'controlled': 'Controlled Item', 'infrastructure': 'Infrastructure Material'}
dflt = {'finished_good': ('yes', 'yes'), 'resale': ('yes', 'yes'), 'raw_material': ('yes', 'no'), 'packaging': ('yes', 'no'), 'consumable': ('no', 'no'), 'asset': ('no', 'no'), 'controlled': ('no (until the tools-stock switch)', 'no'), 'infrastructure': ('no', 'no')}
o = []
o.append("""# DRY-RUN: item master import (read this BEFORE the real import)

Generated on a scratch Postgres 16 database (fresh build with phase8..phase14, loaded with the 57 seed items and their prices). The real database was not touched.
`item_master_import_preview` was run with all 1312 dictionary rows: it WROTE NOTHING (items 57 -> 57, option lists 61 -> 61, audit lines 533 -> 533, import batches 0 -> 0).
Afterwards the import was rehearsed on the same scratch database (apply in chunks of 200, then again = nothing new) to prove the preview numbers.

## 1. What would be created

| | rows |
|---|---|
| Rows in the dictionary file | %d |
| Would be created | %d |
| ... of which active | %d |
| ... of which RETIRED codes (created inactive, code reserved, never reused) | %d |
| Already in the item table (skipped) | %d |
| Conflicts (bad code / unknown unit / unmapped class / duplicate code) | %d |
| Items that get a selling price | 0 (the dictionary has no prices; every imported item shows "Data needed") |

### By item type (class mapping is an editable settings table; these are the defaults)

| Dictionary class | Item type | Rows | Counted in business (stock/COGS/profit) | For sale |
|---|---|---|---|---|""" % (pv['total'], pv['to_create'], pv['to_create_active'], pv['to_create_retired'], pv['skip_existing'], pv['conflicts']))
for k in cls:
    sale = 'yes, only once a selling price is written' if dflt[k][1] == 'yes' else 'no'
    o.append(f"| {cls[k]} | {tl[k]} | {pv['by_type'].get(k, 0)} | {dflt[k][0]} | {sale} |")
o.append("\nThe 7 retired rows are counted above in their class; they are created inactive and not counted in the business.\n\n### By unit\n\n| Dictionary unit | stored as | rows |\n|---|---|---|")
um = {'pc': 'pc', 'pack': 'pack', 'kg': 'kg', 'lb': 'lb (dictionary: pound)', 'ltr': 'ltr (new unit value)', 'set': 'set (new)', 'pair': 'pair (new)', 'box': 'box', 'meter': 'meter (new)', 'gram': 'gram (dictionary: gm)'}
for k, v in sorted(pv['by_unit'].items(), key=lambda x: -x[1]): o.append(f"| {k} | {um.get(k, k)} | {v} |")
o.append("\nNew unit values added to the units list (additively; nothing renamed): ltr, set, pair, meter.\n\n### By category (25 categories, option list `item_categories`, value c01..c25, English names; Bangla name stays empty = shown as Data needed)\n\n| No | Category | to create | of which retired |\n|---|---|---|---|")
for c in pv['by_category']: o.append(f"| {c['cat_no']} | {c['category']} | {c['to_create']} | {c['retired']} |")
o.append("""
Subcategories (201) are created in the list `item_subcategories` with the category in `extra`.

### Spare rows and the next code

The Excel sheets contain spare, blank rows (for example 01-092 .. 01-116 in category 01). They are NOT imported (only filled rows are). The next code the software gives in a category continues after the highest code that exists as an item, so after the import the next new item of category 01 is 01-092 only if no higher imported code exists; the blank rows are not reserved. A retired code stays an item row and is never given out again.

## 2. The 57 old seed items (prices untouched)
""")
auto = [r for r in rows if r['auto'] == '1']; sug = [r for r in rows if r['auto'] == '0' and r['best_code']]; none = [r for r in rows if not r['best_code']]
o.append(f"""`tools/map_seed_items.py` compares each old item's Bangla name, unit family and category with the dictionary **Finished Good** items (categories 13-16) by their meaningful words (size and unit words ignored, spelling folded). Result: `docs/inputs/seed_item_mapping.csv`.
A candidate is suggested only when at least half of the old name's words are in the dictionary name, the unit is in the same family (kg / pc-pack-box / pound) and the score is >= 0.6. Auto-link needs score >= 0.85, a lead of 0.08 over the runner-up AND an identical word set.

* **Auto-linked: {len(auto)}** of 57
* **Suggested, needs your decision: {len(sug)}**
* **No suggestion (stay exactly as they are; no true twin in the dictionary): {len(none)}**

The dictionary lists classical sweets (Rasgulla, Chomchom, ...) but not the shop's own names (সাদা মিষ্টি, কালো লম্বা, পোড়াবাড়ি, মালাইকারি ...), so most old items have no twin. Weak guesses are no longer shown. Linking never changes the old item's code or price; the dictionary twin is hidden from the pickers so nothing is sold twice. Linking an old item to a material / asset / tool code is refused unless the owner confirms.

### Auto-linked

| Old item | Unit | Linked to | Score |
|---|---|---|---|""")
for r in auto: o.append(f"| {r['seed_code']} {r['seed_name']} | {r['seed_unit']} | {r['best_code']} {r['best_name']} ({dic[r['best_code']]['name_en']}) | {r['confidence']} |")
o.append("\n### Suggested (needs decision)\n\n| Old item | Unit | Suggestion | Cand. unit | Score | Runner-up |\n|---|---|---|---|---|---|")
for r in sorted(sug, key=lambda r: -float(r['confidence'])): o.append(f"| {r['seed_code']} {r['seed_name']} | {r['seed_unit']} | {r['best_code']} {r['best_name']} | {r['best_unit']} | {r['confidence']} | {r['runner_up']} |")
o.append("\n### No suggestion\n\n" + ', '.join(f"{r['seed_code']} {r['seed_name']}" for r in none) + "\n")
o.append("""
## 3. Rehearsal result on the scratch database (after applying)

| Item type | rows | counted | sellable now (flag + price) | inactive |
|---|---|---|---|---|
| asset | 162 | 0 | 0 | 0 |
| consumable | 141 | 0 | 0 | 0 |
| controlled | 238 | 0 | 0 | 0 |
| finished_good | 265 (208 + 57 old) | 265 | 57 (the old priced items) | 0 |
| infrastructure | 17 | 0 | 0 | 0 |
| packaging | 94 | 94 | 0 | 0 |
| raw_material | 149 | 142 | 0 | 7 (retired) |
| resale | 303 | 303 | 0 | 0 |

* Total items after: 57 + 1312 = 1369. Applying a second time: 0 created, all skipped. One audit line per batch.
* The 57 old items: same code, same selling price, still sellable.
* Nothing imported has a selling price, so the POS shows none of the new items until a price is written (and the type allows selling).
* Item lists are read in pages of 1000 rows by the app, so the 1369 items (more than the server's 1000-row cut) all show.
* Controlled items (tools) are not counted until the "tools stock" switch is on (Rules hub, module items).

## 4. How to run it for real (after you read the above)

Option A, in the app (owner login): Products > ⋮ > Item master import > Load the file > Preview > Apply (200 rows per request, resumes if the network drops).
Option B, in the Supabase SQL editor: run `supabase/phase14.sql`, then `supabase/phase14_import.sql`: PART 1 is a SELECT-only preview; PART 2 refuses to run until you switch it on with the one statement written at the top of the file.
""")
open(P('docs', 'DRYRUN_item_master.md'), 'w', encoding='utf-8').write('\n'.join(o))
