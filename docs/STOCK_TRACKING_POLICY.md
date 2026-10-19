# Stock tracking policy by item type (proposal for owner review)

Owner task 3 of the audit of 19 Oct 2026, finding F-10. The audit found that all 1,369 live items have `tracked = false`, including all 265 finished goods, so the sale stock-out does not reduce stock for any of them. The owner's instruction: **do not flip `tracked` on all rows; write a reviewed policy by item type.** This file is that proposal. Nothing is changed by it.

The mapping tool is in `supabase/phase505.sql` (default OFF). It can show the plan, record a review, and apply a reviewed type. It does not change an item until the owner switches `tracking_map_apply_on` on and reviews the type.

## 1. The rule behind every proposal

An item is **tracked** when the business needs to know how many are in the store or factory, because the stock is sold, made, used in a recipe, or can be lost. It is **not tracked** when it is a fixed asset, a building material, or a small consumable that is expensed on purchase. Tracking has a cost: every tracked item needs an opening count before it is tracked, otherwise the first sale makes it negative.

Opening stock is counted by the owner's own count (the existing opening-stock flow) and is never guessed. A tracked item with no count shows negative stock after its first sale, and the warning is then correct.

## 2. Counts and proposals (from the item dictionary in the repository)

The dictionary (`data/item_dictionary.csv`) has 1,312 items. The live database had 1,369 items (audit), so about 57 items are not in the dictionary. The counts below are the dictionary's, not the live database's. The owner will see the live split with `stock_tracking_plan()` after phase 505 is pasted (the query needs the owner's login).

| Control class in the dictionary | Items | Maps to item type | Proposal | Reason |
|---|---:|---|---|---|
| Finished Good (cake, sweet, bakery, doi dairy) | 208 | `finished_good` | **Track** | Made and sold. Needed for sale, production, waste and expiry. Count the opening stock first. |
| Stock / Direct Sale (birthday party, foreign and Indian chocolate, biscuits, beverages, ice cream) | 303 | `resale` | **Track** | Bought and resold. Stock and cost are needed for each sale. Biscuits, chocolate and drinks are the bulk. |
| Raw Material (cake and bakery, sweet and dairy) | 149 | `raw_material` | **Track** | Consumed by the recipe at production. Without tracking, production does not reduce the stock. |
| Packaging (boxes, boards, bags) | 94 | `packaging` | **Track** | Consumed per cake or sweet. Tracking records the real use. The audit's planned-yield packaging path is a separate open item (docs/PLAN_NEXT.md). |
| Consumable (spare parts, cleaning, office, electrical, PPE) | 141 | `consumable` | **Do not track** (owner may choose) | Expensed when bought. Tracking them adds counts with little value. |
| Controlled Item (production kitchen tools, small tools, plumbing, PPE) | 238 | `controlled` | **Do not change here** | The existing rule `tools_stock_on` already decides. This map does not override it. |
| Asset (fixed machines, furniture, IT, computers) | 162 | `asset` | **Do not track** | A register, not stock. Depreciation is a separate matter. |
| Infrastructure Material (electrical utilities) | 17 | `infrastructure` | **Do not track** | Building and utility materials. |

Totals: 1,312 items. Proposed tracked: 208 + 303 + 149 + 94 = **754**. Not tracked: 141 + 162 + 17 = **320**. Controlled (238): decided by its own rule.

## 3. Points for the owner to decide before any apply

1. **Counts before switching on.** For each tracked type the owner counts the opening stock at each place and enters it through opening stock. Until then, sales of that type go negative (warn) or are refused (block).
2. **Birthday party and chocolate lines.** These 127 resale items are many and low value. If the owner does not want them counted, change the proposal for `resale` to `false` before applying, or track only the fast sellers. The map gives one answer per type, so a per-item exception is a separate decision.
3. **Consumables.** Set to not tracked. If the owner wants cleaning or spare parts counted, change the `consumable` proposal.
4. **Controlled tools.** The rule `tools_stock_on` remains the owner's switch.
5. **Items with no type.** Items with an empty `item_type` cannot be mapped. The plan shows them as "(not classified)". The owner must classify them first.
6. **Sale line with no item id.** The audit found one sale line with no item id. It is not fixed by tracking; the owner checks it on the sale (see docs/PLAN_NEXT.md).

## 4. Order of work (proposal)

1. Owner pastes phase 505 (after the earlier SW phases). Nothing changes.
2. Owner runs `stock_tracking_plan()` (in the app or the SQL editor as the owner) and checks the live split and the "(not classified)" row.
3. Owner classifies unclassified items, then counts opening stock for the finished goods and raw materials first (the largest effect).
4. Owner reviews each type with `stock_tracking_review(type, note)`. A note is required.
5. Owner switches `tracking_map_apply_on` on (Settings, stock rules), runs `stock_tracking_apply(type, true)` (dry run: counts only), then `stock_tracking_apply(type, false)`.
6. Owner runs the sales-versus-stock check (not yet built: see docs/PLAN_NEXT.md, item 2.9) and turns the switch off again if needed.

## 5. What this file does not decide

- The live item counts (the owner's query).
- Per-item exceptions inside a type.
- The opening stock values (they are counted, never guessed).
- Whether stock-negative mode should be `block` (owner setting; see docs/PLAN_NEXT.md, decision D-07).
