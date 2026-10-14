# Step C-0 (phase73) - recipe master: artisan register, versions + approval, steps, artisan-wise recipe book
Branch `fix/phase-C0` (from `65145c9`). Files: `supabase/phase73.sql`, `supabase/phase73_test.sql`, `web/recipebook.js`, `tests/web/recipebook_test.js`, this report.
Paste order: ... phase71, **phase73**. Paste-twice safe (2nd run clean, checked). No old phase file edited.

## What was built (per brief point)
- **C0.1 artisans** (`phase73.sql:44`): id (identity, never reused, no delete trigger), code `artisan-N`, post (কারিগর / শেফ / সহকারী কারিগর / অন্য + typed text), work type (মিষ্টি / দই / জিলাপি / কেক / বেকারি / অন্য + typed text), place, active/retired (+ reason), optional login link. The **name column is NOT readable by browsers** (column grant omits it, `phase73.sql` privileges block); the only readers are `artisan_register()` (owner / grant `artisan_manage`, audited as a view). The audit trigger `_artisan_audit` writes the row WITHOUT the name (`name_changed:true` only). Pickers (`artisan_list`), the recipe book, history rows, exceptions, print/share text show only `artisan-N` + পদ + কাজের ধরন + জায়গা.
- **C0.2** `recipes.artisan_id` (blank for every existing recipe), `recipe_set_artisan`, `recipe_unassigned()` = list "কারিগর নির্ধারিত নয়". Dropdown in `web/recipebook.js` ends with `☐ অন্য: নতুন কারিগর যোগ` (owner / artisan_manage opens the register form; others are told the owner adds). A copy to a new version of the same product keeps the artisan and steps; a copy to another product leaves the artisan blank.
- **C0.3** `recipe_versions` append-only history (who, when, version no, previous values `prev`, new values `snap`, trigger blocks update/delete). Events: created / edited / steps_edited / artisan_set / approved. `recipe_approve` needs grant `recipe_approve` (new role `recipe_approver` holds it); **the last changer (`changed_by`, else `created_by`) can never approve** (`self_approve_refused`) unless the owner flips rule `recipe_self_approve` (default OFF). An approved version is frozen (yield, lines, steps) by triggers - a change is a new version. Rule `recipe_approval_required` = off (default, today) | warn (yellow line `recipe_not_approved` on each production) | on (`recipe_cost` and `production_post` refuse an unapproved recipe) - this is the 05-3 "no costing before approval" rule, switchable because every existing recipe is unapproved.
- **C0.4** `recipe_steps` (step no, name, free text, minutes, people, fuel গ্যাস/বিদ্যুৎ/অন্য+text, flame note, equipment, QC note, responsible post). `recipe_steps_save` replaces the ordered list (array order = step no; old steps retired not deleted; previous list kept in history). UI: "ধাপ যোগ করো" button, one card per step, ↑ ↓ ✕, live "অনুমান: শ্রম-ঘণ্টা" = Σ minutes×people/60 (`recipe_labour_suggest`, flagged অসম্পূর্ণ when a box is blank). **Nothing reads it for cost** (tested: recipe_cost and production unit cost identical before/after steps).
- **C0.5** `recipe_book(artisan, with_cost, loc)`: all ACTIVE recipes of the artisan - product, yield, ingredients (qty, unit, waste%, "তথ্য দরকার" when blank), steps, version, approval date, card reference. Default view has no cost key; `with_cost` is honoured only for `_recipe_cost_ok()` holders. Web: print (print-only copy so the app's other print CSS cannot blank it), share (navigator.share, else copy text), Bangla.
- **C0.6** grant `recipe_view` (default: owner + role `recipe_approver` only), rule `artisan_self_view` (default OFF): a login linked to an artisan sees only that artisan's book (`recipe_book()` with no argument = own). Every `recipe_book` / `artisan_register` call writes an audit row (action `view`, no names). `_recipe_read()` was re-created to include `recipe_view`/`recipe_approve` (an approver must read what he approves).
- Re-created with `bos73` tags: `recipe_save`, `recipe_copy` (history/changer/steps/artisan), `recipe_cost` (approval gate + `approved` key only), `production_post` (approval gate only), `_recipe_read`.
- `recipe_save_full` = one atomic call (lines + steps + artisan + 05-3 card reference). Written but **the existing recipes.js editor still calls `recipe_save`** and was not changed (it has no artisan/steps boxes); the new page `#/recipebook` carries the artisan dropdown, steps editor and approval instead.

## যাচাই হয়েছে (চালিয়ে)
- `supabase/phase73_test.sql`: **98 pass / 0 fail** on a fresh DB (phase8..71 + 73). Covers: artisan pick + typed "other" + id never reused + name column denied + audit without name; blank-artisan recipe still costs (44.4) and produces; artisan set + history row with previous value; version 2 is a new row and v1 unchanged; draft edit keeps previous values; used / approved versions refuse edits; changer (manager with the grant, and the owner) cannot approve, separate approver can; approval switch off/warn/on for recipe_cost and production_post; step save/reorder/old steps kept/validation; suggestion 2.75 h; steps do not change recipe_cost or the posted unit cost (24); atomic save + client-id dup; copy keeps/clears the artisan; book contents, no name, no cost key by default, cost for cost-right holder, hidden for a non-cost user asking for it; other artisan's book invisible with `artisan_self_view` on; unlinked user refused; audit view rows without names.
- `tests/web/recipebook_test.js` (Playwright, 360px phone viewport, stub Supabase): **49 assertions, 0 failures**, no console errors. Checked: picker shows id+post only, book render, no cost by default, cost block only when returned, share text, no register tab without the grant, server refusal shows nothing, unassigned list + assign + last "add new" option (owner opens the form, non-owner told), steps add / move / Bangla-digit minutes / live suggestion / client id / name required, approved version read-only, approve + "changer cannot approve" message, register is the only place with names, save + retire with reason, Bangla title/text, print-only copy, no horizontal overflow on book / steps / register.
- **Bangla font check**: rendered `#/recipebook` in Chromium at 360px in bn mode and read the screenshot and a PDF of the printed book: conjuncts (জ্বাল, স্ট, ক্র), matras and Bangla digits show correctly, no broken boxes, no overflow. NOTE: the sandbox blocks Google Fonts, so this was drawn with the system Bengali fallback font, not Anek Bangla / Hind Siliguri.
- **Regression** (every `supabase/phase*_test.sql`, fresh DB each, built through phase71 vs through phase73): result **identical for all 41 suites** (see table). The only FAIL lines are the pre-existing ones, same before and after: phase8 T1 "staff direct update rules" (1), phase10 T12 (1), phase15 T0 (1), phase21 T1 (1), phase47 T1 x2 (the two intentional asserts phase62 tightens). Pass counts e.g. 19: 94, 23: 92, 26: 117, 40: 119, 50: 45, 52: 33, 62: 74, 71: 26 - unchanged.

## পড়ে বোঝা (code read, not run)
- `web/recipes.js` (existing editor) still saves through `recipe_save`; because that function was re-created it now also writes history/changed_by, so the old screen works unchanged (not browser-run against the real DB).
- `recipe_book` reads `recipe_lines` of the artisan's active recipes; a recipe whose ingredient is later retired still shows (no join filter on item active).
- 05-3 / 05-4 are paper forms: no code links them to `recipes` (grep of supabase/*.sql: only `_r3q_f2_yield` reads 05-4). `form_ref` is therefore a typed reference only.

## যাচাই হয়নি (not verified)
- Nothing was opened on a real phone or against the live database; no live recipe has an artisan yet.
- Web fonts (Anek Bangla / Hind Siliguri) not loaded in the sandbox; print on a real phone/printer not tried (PDF emulation only).
- `ia.js` navigation (below) not integrated; `c.GF.recipe_view` must exist in the grant-flag list the lead uses for `ok:`.
- `artisan_self_view` hides the book only. The raw `recipes` / `recipe_lines` tables stay readable by anyone with `stock_production` / `stock_issue` / `recipe_manage` (phase19 policy) - a factory in-charge can still read other artisans' recipes through those tables. Not changed because stock people need them.
- `recipe_approval_required = on` makes every existing (unapproved) recipe uncostable until approved: not tried against live data.

## Mismatches with the printed forms (NOT changed, listed)
1. **05-3 head/informant**: the paper card has "তথ্যদাতা — কারিগরের নাম / পদ" as typed text (`web/forms_factory.js:208`). Our rule keeps names only in the register, so the app side stores `artisan_id`; the paper keeps a typed name. Nothing links the two (only `recipes.form_ref`, the card number).
2. **05-3 sections**: paper has Section A (base) / B (product) / C (packaging) ingredient tables and "base obtained from Step 1" (`forms_factory.js:184-196`); `recipe_lines` is one flat list (packaging is separate in `product_packaging`). Section structure and the base-yield box have no home in the database.
3. **05-3 time/people/equipment**: paper has card-level `cook_min, cook_heat, rest_min, total_min, headcount, machines` (`forms_factory.js:200-203`); `recipe_steps` has the same facts per step. If both are filled the same fact lives in two places - the paper is the original, the steps are the app copy; no reconciliation. Per the rule "one place holds detail": consider dropping the card-level boxes or deriving them (owner decision).
4. **05-3 steps** on paper are one free-text column (`forms_factory.js:198`); our steps add minutes / people / fuel / QC / responsible post columns the paper does not have.
5. **05-3 family** (ছানা / ভাজা / দই / খোয়া / কেক / অন্য) differs from artisan work type (মিষ্টি / দই / জিলাপি / কেক / বেকারি / অন্য).
6. **05-3 approval** is the form's own checker approval (entries); `recipe_approve` is a separate, second approval in the recipe master - two approvals for one card unless the owner treats the paper as the sign-off.

## Owner decisions needed
1. Who approves recipes? Create a login with role `recipe_approver`; until then the owner cannot approve his own change (or switch `recipe_self_approve` ON).
2. Switch `recipe_approval_required`: keep off / warn / on (on blocks cost and production of every unapproved recipe - all existing ones).
3. Should a recipe's artisan be a required field later? (now optional, "কারিগর নির্ধারিত নয়" list shown)
4. Turn `artisan_self_view` on? (needs each artisan's login linked in the register)
5. Who may add artisans: owner only today (grant `artisan_manage` can delegate).
6. Paper vs app steps (mismatch 3) and Section A/B/C (mismatch 2).
7. Whether names may appear in the picker for the owner (now: never, only in the register tab).

## Cannot be done on a phone (needs the lead / a computer)
- Pasting `phase73.sql` into the Supabase SQL editor (owner has pasted SQL himself before - paste order after phase71, twice is safe).
- Integrating `web/ia.js` and `web/index.html` (below) and any rebuild of setup-sql.html.
- Creating the logins and assigning role `recipe_approver` can be done by the owner in the app (users screen), but linking a login to an artisan is in the register form.

## For web/ia.js and web/index.html (lead integrates; I did not edit them)
```js
rec('recipebook', 'factory', ['কারিগরের রেসিপি বই', 'Artisan recipe book', 'Artisan-এর recipe book'], { icon: 'doc', ok: (c) => c.own || c.GF.recipe_view === true || c.GF.recipe_manage === true, kw: ['artisan', 'recipe book', 'steps', 'karigor', 'কারিগর', 'রেসিপি বই', 'ধাপ', 'শেফ'] }),
```
`<script src="recipebook.js"></script>` right after `<script src="recipes.js"></script>` in `web/index.html`. Web test serves `web/` of the checkout and injects that tag itself.
