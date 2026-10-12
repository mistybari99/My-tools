# DRY-RUN: item master import (read this BEFORE the real import)

Generated on a scratch Postgres 16 database (fresh build with phase8..phase14, loaded with the 57 seed items and their prices). The real database was not touched.
`item_master_import_preview` was run with all 1312 dictionary rows: it WROTE NOTHING (items 57 -> 57, option lists 61 -> 61, audit lines 533 -> 533, import batches 0 -> 0).
Afterwards the import was rehearsed on the same scratch database (apply in chunks of 200, then again = nothing new) to prove the preview numbers.

## 1. What would be created

| | rows |
|---|---|
| Rows in the dictionary file | 1312 |
| Would be created | 1312 |
| ... of which active | 1305 |
| ... of which RETIRED codes (created inactive, code reserved, never reused) | 7 |
| Already in the item table (skipped) | 0 |
| Conflicts (bad code / unknown unit / unmapped class / duplicate code) | 0 |
| Items that get a selling price | 0 (the dictionary has no prices; every imported item shows "Data needed") |

### By item type (class mapping is an editable settings table; these are the defaults)

| Dictionary class | Item type | Rows | Counted in business (stock/COGS/profit) | For sale |
|---|---|---|---|---|
| Finished Good | Finished good | 208 | yes | yes, only once a selling price is written |
| Stock/Direct Sale | Resale (Stock/Direct Sale) | 303 | yes | yes, only once a selling price is written |
| Raw Material | Raw material | 149 | yes | no |
| Packaging | Packaging | 94 | yes | no |
| Consumable | Consumable | 141 | no | no |
| Asset | Asset | 162 | no | no |
| Controlled Item | Controlled item (tools) | 238 | no (until the tools-stock switch) | no |
| Infrastructure Material | Infrastructure material | 17 | no | no |

The 7 retired rows are counted above in their class; they are created inactive and not counted in the business.

### By unit

| Dictionary unit | stored as | rows |
|---|---|---|
| pc | pc | 891 |
| pack | pack | 150 |
| kg | kg | 149 |
| lb | lb (dictionary: pound) | 38 |
| ltr | ltr (new unit value) | 35 |
| set | set (new) | 26 |
| pair | pair (new) | 9 |
| box | box | 6 |
| meter | meter (new) | 5 |
| gram | gram (dictionary: gm) | 3 |

New unit values added to the units list (additively; nothing renamed): ltr, set, pair, meter.

### By category (25 categories, option list `item_categories`, value c01..c25, English names; Bangla name stays empty = shown as Data needed)

| No | Category | to create | of which retired |
|---|---|---|---|
| 01 | Fixed Assets & Machinery | 91 | 0 |
| 02 | IT POS Office Tech | 35 | 0 |
| 03 | Raw Materials Cake Bakery | 112 | 0 |
| 04 | Raw Materials Sweet Dairy | 38 | 7 |
| 05 | Packaging Materials | 102 | 0 |
| 06 | DirectPurchase IceCream | 32 | 0 |
| 07 | Direct Purchase Beverages | 43 | 0 |
| 08 | Biscuits Toast Chanachur | 53 | 0 |
| 09 | Foreign Chocolate | 62 | 0 |
| 10 | Indian Regional Chocolate | 34 | 0 |
| 11 | Gift Chocolate | 14 | 0 |
| 12 | Birthday Party Celebration | 65 | 0 |
| 13 | Finished Goods Cake | 66 | 0 |
| 14 | Finished Goods Sweet | 55 | 0 |
| 15 | Finished Goods Doi Dairy | 37 | 0 |
| 16 | Finished Goods Bakery | 50 | 0 |
| 17 | Production Kitchen Tools | 82 | 0 |
| 18 | Small Maintenance Tools | 64 | 0 |
| 19 | Electrical Items Utilities | 46 | 0 |
| 20 | Cleaning Hygiene Sanitation | 48 | 0 |
| 21 | Safety PPE | 33 | 0 |
| 22 | Storage Material Handling | 27 | 0 |
| 23 | Spare Parts Maintenance | 39 | 0 |
| 24 | Plumbing Materials | 34 | 0 |
| 25 | Other Operational Items | 50 | 0 |

Subcategories (201) are created in the list `item_subcategories` with the category in `extra`.

### Spare rows and the next code

The Excel sheets contain spare, blank rows (for example 01-092 .. 01-116 in category 01). They are NOT imported (only filled rows are). The next code the software gives in a category continues after the highest code that exists as an item, so after the import the next new item of category 01 is 01-092 only if no higher imported code exists; the blank rows are not reserved. A retired code stays an item row and is never given out again.

## 2. The 57 old seed items (prices untouched)

`tools/map_seed_items.py` compares each old item's Bangla name, unit family and category with the dictionary **Finished Good** items (categories 13-16) by their meaningful words (size and unit words ignored, spelling folded). Result: `docs/inputs/seed_item_mapping.csv`.
A candidate is suggested only when at least half of the old name's words are in the dictionary name, the unit is in the same family (kg / pc-pack-box / pound) and the score is >= 0.6. Auto-link needs score >= 0.85, a lead of 0.08 over the runner-up AND an identical word set.

* **Auto-linked: 1** of 57
* **Suggested, needs your decision: 13**
* **No suggestion (stay exactly as they are; no true twin in the dictionary): 43**

The dictionary lists classical sweets (Rasgulla, Chomchom, ...) but not the shop's own names (সাদা মিষ্টি, কালো লম্বা, পোড়াবাড়ি, মালাইকারি ...), so most old items have no twin. Weak guesses are no longer shown. Linking never changes the old item's code or price; the dictionary twin is hidden from the pickers so nothing is sold twice. Linking an old item to a material / asset / tool code is refused unless the owner confirms.

### Auto-linked

| Old item | Unit | Linked to | Score |
|---|---|---|---|
| I-016 রসমালাই - কেজি | kg | 14-028 রসমালাই (Rosh Malai / Rasmalai) | 1.000 |

### Suggested (needs decision)

| Old item | Unit | Suggestion | Cand. unit | Score | Runner-up |
|---|---|---|---|---|---|
| I-025 টক দই | pc | 15-006 টক দই ৪০০ গ্রাম | pc | 1.000 | 15-007 (1.000) |
| I-054 ভ্যানিলা স্লাইস (৮ পিস) | pc | 13-058 কেক স্লাইস, ভ্যানিলা | pc | 0.867 | 13-031 (0.433) |
| I-055 চকলেট স্লাইস ( ৮ পিস ) | pc | 13-056 কেক স্লাইস, চকোলেট | pc | 0.867 | 13-028 (0.433) |
| I-044 ভ্যানিলা রেগুলার ১ পাউন্ড | pound | 13-001 ভ্যানিলা স্পঞ্জ কেক | pound | 0.733 | 13-015 (0.733) |
| I-045 চকলেট রেগুলার ১ পাউন্ড | pound | 13-002 চকোলেট স্পঞ্জ কেক | pound | 0.733 | 13-016 (0.733) |
| I-046 ভ্যানিলা স্পেশাল ১ পাউন্ড | pound | 13-001 ভ্যানিলা স্পঞ্জ কেক | pound | 0.733 | 13-015 (0.733) |
| I-047 চকলেট স্পেশাল ১ পাউন্ড | pound | 13-002 চকোলেট স্পঞ্জ কেক | pound | 0.733 | 13-016 (0.733) |
| I-048 ভ্যানিলা রেগুলার ২ পাউন্ড | pound | 13-001 ভ্যানিলা স্পঞ্জ কেক | pound | 0.733 | 13-015 (0.733) |
| I-049 চকলেট রেগুলার ২ পাউন্ড | pound | 13-002 চকোলেট স্পঞ্জ কেক | pound | 0.733 | 13-016 (0.733) |
| I-050 ভ্যানিলা স্পেশাল ২ পাউন্ড | pound | 13-001 ভ্যানিলা স্পঞ্জ কেক | pound | 0.733 | 13-015 (0.733) |
| I-051 চকলেট স্পেশাল ২ পাউন্ড | pound | 13-002 চকোলেট স্পঞ্জ কেক | pound | 0.733 | 13-016 (0.733) |
| I-052 ভ্যানিলা হাফ পাউন্ড | pound | 13-001 ভ্যানিলা স্পঞ্জ কেক | pound | 0.733 | 13-015 (0.733) |
| I-053 চকলেট হাফ পাউন্ড | pound | 13-002 চকোলেট স্পঞ্জ কেক | pound | 0.733 | 13-016 (0.733) |

### No suggestion

I-001 সাদা মিষ্টি – কেজি, I-002 কালো মিষ্টি – কেজি, I-003 পোড়াবাড়ি – কেজি, I-004 সাদা লম্বা – কেজি, I-005 কালো লম্বা – কেজি, I-006 স্পঞ্জ মিষ্টি – কেজি, I-007 লাল লাড্ডু – কেজি, I-008 সাদা লাড্ডু – কেজি, I-009 সাদা ক্রিমজাম – কেজি, I-010 কালো ক্রিমজাম – কেজি, I-011 সরপুরিয়া – কেজি, I-012 গুড়ের সন্দেশ – কেজি, I-013 কাজু সন্দেশ – কেজি, I-014 ইলিশপেটি – কেজি, I-015 ক্ষির আইটেম – কেজি, I-017 লাল দই বড় মালসা, I-018 লাল দই মাঝারি মালসা, I-019 সাদা দই বড় মালসা, I-020 সাদা দই মাঝারি মালসা, I-021 স্বরা দই (বাংলা), I-022 স্বরা দই (বাটি), I-023 স্বরা দই (প্লেট), I-024 কাপ দই, I-026 মালাইকারি – পিস, I-027 রসগোল্লা ছোট – পিস, I-028 রসগোল্লা বড় – পিস, I-029 সাদা মিষ্টি – পিস, I-030 কালো মিষ্টি – পিস, I-031 পোড়াবাড়ি – পিস, I-032 সাদা লম্বা – পিস, I-033 কালো লম্বা – পিস, I-034 স্পঞ্জ মিষ্টি – পিস, I-035 লাল লাড্ডু – পিস, I-036 সাদা লাড্ডু – পিস, I-037 সাদা ক্রিমজাম – পিস, I-038 কালো ক্রিমজাম – পিস, I-039 সরপুরিয়া – পিস, I-040 গুড়ের সন্দেশ – পিস, I-041 কাজু সন্দেশ – পিস, I-042 ইলিশপেটি – পিস, I-043 ক্ষির আইটেম – পিস, I-056 অরেঞ্জ স্লাইস( ৮ পিস), I-057 জার কেক


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
