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
| Finished Good | Finished good | 208 | yes | yes (and only when a selling price is written) |
| Stock/Direct Sale | Resale (Stock/Direct Sale) | 303 | yes | yes (and only when a selling price is written) |
| Raw Material | Raw material | 149 | yes | no |
| Packaging | Packaging | 94 | yes | no |
| Consumable | Consumable | 141 | no | no |
| Asset | Asset | 162 | no | no |
| Controlled Item | Controlled item (tools) | 238 | no (until tools stock switch) | no |
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

### By category (25 categories, stored as option list `item_categories`, value c01..c25, English names; Bangla name stays empty = shown as Data needed)

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

## 2. The 57 old seed items (prices untouched)

`tools/map_seed_items.py` compared each old item's Bangla name, unit and category with the dictionary **Finished Good** items (categories 13-16). Result file: `docs/inputs/seed_item_mapping.csv`.
Only a match with confidence >= 0.85 and a clear lead (>= 0.08) over the runner-up is linked automatically.

* **Auto-linked: 1** of 57
* **Needs your decision: 56** of 57 (these stay exactly as they are until you decide, in the app: Products > ⋮ > Old items to master codes)

Honest note: the dictionary lists classical sweets (Rasgulla, Chomchom, ...) but not the shop's own names (সাদা মিষ্টি, কালো লম্বা, পোড়াবাড়ি, মালাইকারি ...), so most old items have no true twin in the dictionary. For those the best candidate below is only a hint; the sensible answer is often "keep apart". Linking never changes the old item's code or price; the dictionary twin is hidden from the pickers so nothing is sold twice.

### Auto-linked

| Old item | Unit | Linked to | Confidence |
|---|---|---|---|
| I-016 রসমালাই - কেজি | kg | 14-028 রসমালাই (Rosh Malai / Rasmalai) | 1.000 |

### Needs decision (best candidate, confidence, runner-up)

| Old item | Unit | Best candidate | Cand. unit | Confidence | Runner-up |
|---|---|---|---|---|---|
| I-025 টক দই | pc | 15-007 টক দই ১ কেজি | pc | 0.831 | 15-006 (0.760) |
| I-015 ক্ষির আইটেম – কেজি | kg | 14-034 ক্ষীর | kg | 0.673 | 14-008 (0.385) |
| I-054 ভ্যানিলা স্লাইস (৮ পিস) | pc | 13-058 কেক স্লাইস, ভ্যানিলা | pc | 0.667 | 13-031 (0.613) |
| I-055 চকলেট স্লাইস ( ৮ পিস ) | pc | 13-052 চিজকেক স্লাইস | pc | 0.664 | 13-056 (0.561) |
| I-024 কাপ দই | pc | 14-037 ভাপা দই | pc | 0.640 | 15-008 (0.561) |
| I-013 কাজু সন্দেশ – কেজি | kg | 14-009 ভাপা সন্দেশ | kg | 0.628 | 14-022 (0.613) |
| I-029 সাদা মিষ্টি – পিস | pc | 14-036 মিষ্টি দই | pc | 0.613 | 14-032 (0.477) |
| I-030 কালো মিষ্টি – পিস | pc | 14-036 মিষ্টি দই | pc | 0.613 | 14-032 (0.477) |
| I-046 ভ্যানিলা স্পেশাল ১ পাউন্ড | pound | 13-001 ভ্যানিলা স্পঞ্জ কেক | pound | 0.592 | 13-062 (0.536) |
| I-050 ভ্যানিলা স্পেশাল ২ পাউন্ড | pound | 13-001 ভ্যানিলা স্পঞ্জ কেক | pound | 0.592 | 13-062 (0.536) |
| I-012 গুড়ের সন্দেশ – কেজি | kg | 14-007 সন্দেশ, কড়া | kg | 0.584 | 14-008 (0.584) |
| I-034 স্পঞ্জ মিষ্টি – পিস | pc | 14-036 মিষ্টি দই | pc | 0.584 | 14-032 (0.465) |
| I-036 সাদা লাড্ডু – পিস | pc | 14-048 বুন্দিয়া লাড্ডু | pc | 0.584 | 14-047 (0.505) |
| I-052 ভ্যানিলা হাফ পাউন্ড | pound | 13-015 ভ্যানিলা বাটার কেক | pound | 0.583 | 13-001 (0.541) |
| I-006 স্পঞ্জ মিষ্টি – কেজি | kg | 14-004 স্পঞ্জ রসগোল্লা | kg | 0.577 | 14-031 (0.550) |
| I-056 অরেঞ্জ স্লাইস( ৮ পিস) | pc | 13-052 চিজকেক স্লাইস | pc | 0.577 | 13-056 (0.518) |
| I-001 সাদা মিষ্টি – কেজি | kg | 14-031 মিষ্টি নিমকি | kg | 0.571 | 14-003 (0.516) |
| I-002 কালো মিষ্টি – কেজি | kg | 14-031 মিষ্টি নিমকি | kg | 0.571 | 14-013 (0.459) |
| I-028 রসগোল্লা বড় – পিস | pc | 14-001 রসগোল্লা | kg | 0.557 | 14-004 (0.384) |
| I-021 স্বরা দই (বাংলা) | pc | 14-036 মিষ্টি দই | pc | 0.555 | 14-037 (0.523) |
| I-022 স্বরা দই (বাটি) | pc | 14-036 মিষ্টি দই | pc | 0.555 | 14-037 (0.523) |
| I-023 স্বরা দই (প্লেট) | pc | 14-036 মিষ্টি দই | pc | 0.555 | 14-037 (0.523) |
| I-035 লাল লাড্ডু – পিস | pc | 14-048 বুন্দিয়া লাড্ডু | pc | 0.552 | 14-047 (0.516) |
| I-044 ভ্যানিলা রেগুলার ১ পাউন্ড | pound | 13-015 ভ্যানিলা বাটার কেক | pound | 0.547 | 13-001 (0.512) |
| I-048 ভ্যানিলা রেগুলার ২ পাউন্ড | pound | 13-015 ভ্যানিলা বাটার কেক | pound | 0.547 | 13-001 (0.512) |
| I-008 সাদা লাড্ডু – কেজি | kg | 14-003 চমচম, সাদা | kg | 0.540 | 14-028 (0.435) |
| I-003 পোড়াবাড়ি – কেজি | kg | 14-035 রাবড়ি | kg | 0.538 | 14-017 (0.420) |
| I-027 রসগোল্লা ছোট – পিস | pc | 14-001 রসগোল্লা | kg | 0.532 | 14-004 (0.371) |
| I-004 সাদা লম্বা – কেজি | kg | 14-003 চমচম, সাদা | kg | 0.527 | 14-028 (0.420) |
| I-010 কালো ক্রিমজাম – কেজি | kg | 14-013 কালোজাম | kg | 0.524 | 14-014 (0.376) |
| I-057 জার কেক | pc | 13-047 নারিকেল লোফ কেক | pc | 0.522 | 13-026 (0.496) |
| I-047 চকলেট স্পেশাল ১ পাউন্ড | pound | 13-061 ঈদ স্পেশাল কেক | pound | 0.518 | 13-062 (0.500) |
| I-051 চকলেট স্পেশাল ২ পাউন্ড | pound | 13-061 ঈদ স্পেশাল কেক | pound | 0.518 | 13-062 (0.500) |
| I-041 কাজু সন্দেশ – পিস | pc | 14-053 সন্দেশ গিফট বক্স | pc | 0.510 | 14-009 (0.428) |
| I-040 গুড়ের সন্দেশ – পিস | pc | 14-053 সন্দেশ গিফট বক্স | pc | 0.501 | 14-007 (0.384) |
| I-009 সাদা ক্রিমজাম – কেজি | kg | 14-003 চমচম, সাদা | kg | 0.496 | 14-025 (0.391) |
| I-005 কালো লম্বা – কেজি | kg | 14-013 কালোজাম | kg | 0.475 | 14-005 (0.444) |
| I-043 ক্ষির আইটেম – পিস | pc | 14-034 ক্ষীর | kg | 0.473 | 14-051 (0.363) |
| I-053 চকলেট হাফ পাউন্ড | pound | 13-016 চকোলেট ফাজ কেক | pound | 0.464 | 13-050 (0.420) |
| I-019 সাদা দই বড় মালসা | pc | 14-037 ভাপা দই | pc | 0.457 | 15-008 (0.428) |
| I-045 চকলেট রেগুলার ১ পাউন্ড | pound | 13-050 চকোলেট চিজকেক, গোটা | pound | 0.443 | 13-016 (0.411) |
| I-049 চকলেট রেগুলার ২ পাউন্ড | pound | 13-050 চকোলেট চিজকেক, গোটা | pound | 0.443 | 13-016 (0.411) |
| I-020 সাদা দই মাঝারি মালসা | pc | 15-005 মিষ্টি দই, মাটির পাত্র স্পেশাল | pc | 0.434 | 14-037 (0.425) |
| I-038 কালো ক্রিমজাম – পিস | pc | 14-029 মালপোয়া | pc | 0.432 | 14-042 (0.368) |
| I-039 সরপুরিয়া – পিস | pc | 14-030 ঘুঘরা / গুজিয়া | pc | 0.432 | 14-042 (0.407) |
| I-017 লাল দই বড় মালসা | pc | 15-012 মিষ্টি লাচ্ছি, বড় গ্লাস | pc | 0.422 | 14-037 (0.419) |
| I-011 সরপুরিয়া – কেজি | kg | 14-014 পান্তুয়া | kg | 0.420 | 14-035 (0.403) |
| I-014 ইলিশপেটি – কেজি | kg | 14-027 লেডিকেনি | kg | 0.420 | 14-031 (0.385) |
| I-026 মালাইকারি – পিস | pc | 14-029 মালপোয়া | pc | 0.420 | 14-046 (0.420) |
| I-033 কালো লম্বা – পিস | pc | 14-029 মালপোয়া | pc | 0.420 | 14-046 (0.365) |
| I-042 ইলিশপেটি – পিস | pc | 14-036 মিষ্টি দই | pc | 0.420 | 14-032 (0.357) |
| I-018 লাল দই মাঝারি মালসা | pc | 15-005 মিষ্টি দই, মাটির পাত্র স্পেশাল | pc | 0.417 | 15-034 (0.403) |
| I-037 সাদা ক্রিমজাম – পিস | pc | 14-042 চিড়ার মোয়া | pc | 0.410 | 14-041 (0.365) |
| I-007 লাল লাড্ডু – কেজি | kg | 14-015 গোলাপ জামুন | kg | 0.407 | 14-013 (0.389) |
| I-032 সাদা লম্বা – পিস | pc | 14-054 ঈদ স্পেশাল মিষ্টির বক্স | pc | 0.382 | 14-055 (0.370) |
| I-031 পোড়াবাড়ি – পিস | pc | 14-029 মালপোয়া | pc | 0.376 | 14-039 (0.355) |

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

* Total items after: 57 + 1312 = 1369. Applying a second time: 0 created, all skipped. One audit line per batch (no per-row audit lines).
* The 57 old items: same code, same selling price, still sellable. Their mapping rows: 1 linked, 56 pending.
* Nothing imported has a selling price, so the POS shows none of the new items until you write a price (and the item type allows selling).
* Controlled items (tools) are not counted until the "tools stock" switch is turned on (Rules hub, module items).

## 4. How to run it for real (after you read the above)

Option A, in the app (owner login): Products > ⋮ > Item master import > Load the file > Preview > Apply (200 rows per request, resumes if the network drops).
Option B, in the Supabase SQL editor: run `supabase/phase14.sql`, then `supabase/phase14_import.sql`: PART 1 is a SELECT-only preview; PART 2 refuses to run until you switch it on with the one statement written at the top of the file.
