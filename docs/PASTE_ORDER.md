# PASTE ORDER (the single canonical order)

Branch `fix/phase-INT3` (supersedes the INT2 list; phase96, phase97 and phase98 added). Every file is additive and paste-twice safe. Nothing is edited in an old phase file; later phases only `create or replace`.
This is the order that was built and tested from nothing (fresh Postgres 16, see docs/briefs_p2p3/step_INT2_G_REPORT.md and step_INT3_REPORT.md). Any other order is untested.

## A. Foundation (already on the live database - do NOT paste again)

`schema.sql`, `phase2.sql`, `phase3.sql`, `phase4.sql`, `ALL_NEW.sql`, then
`phase8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 60 61 62 70 71`
(exactly the list in `tests/sql/build_fresh_db.sh`). Never re-paste phase21 after phase24, and never re-paste phase40 / ALL_NEW10 after phase85
(they would bring back the 7-argument `acct_journal_post`; if it ever happens, paste phase89 again - it removes the old overload).

## B. New files, strictly in this order, each once

| # | file | needs (from the file's own header) | note |
|---|------|---------------|------|
| 1 | phase72.sql | foundation | |
| 2 | phase73.sql | foundation (recipes from phase19) | |
| 3 | phase74.sql | 73 | |
| 4 | phase75.sql | 73, 74 | |
| 5 | phase76.sql | 61, 62, 70, 71 | |
| 6 | phase77.sql | 76 | |
| 7 | phase78.sql | 73, 74, 75 | |
| 8 | phase79.sql | 72..78 | merge of 72..78 function bodies; guard inside |
| 9 | phase80.sql | 72..79 | guard inside |
| 10 | phase81.sql | 72..79 | guard inside (does not need 80) |
| 11 | phase82.sql | 78 | |
| 12 | phase83.sql | foundation | |
| 13 | phase84.sql | 78 | |
| 14 | phase85.sql | 72..79 | guard inside |
| 15 | phase86.sql | 76 (and 77..79) | |
| 16 | phase87.sql | 72..79, 82, 84 | guard inside |
| 17 | phase88.sql | 72..79, 82, 83, 84 | guard inside |
| 18 | phase90.sql | foundation .. 84 | guard inside (lists the missing phases) |
| 19 | phase91.sql | 86 | guard inside (checks its tables) |
| 20 | **phase89.sql** (merged function bodies) | 72..88, 90, 91 | guard raises `phase89 needs phases 72..88, 90, 91 pasted first ... missing: <numbers>` if any is absent |
| 21 | phase92.sql | 72..88 | guard inside (invoice on screen) |
| 22 | phase93.sql | base schema | guard inside (print templates) |
| 23 | phase95.sql | base + 8 | guard inside (cash drawer option) |
| 24 | **phase94.sql** | 76, 80, 81, 85, 86, 89, 90, 92, 93 | guard raises `phase94 needs phases 76, 80, 81, 85, 86, 89, 90, 92, 93 pasted first ...`. Security step (docs/briefs_p2p3/step_Sec_REPORT.md): re-creates 9 functions with the tag bos94 (none of them is in phase89's list) and gives `inbound_message_receive` / `web_order_submit` one extra defaulted argument. Do NOT paste phase76 again afterwards (it would bring back the old signatures next to the new ones). |
| 25 | phase96.sql | 80, 85, 89 | guard inside (needs `bos85` and `bos89` in `_acct_docs`; refuses a body with a tag it does not know). Opening-stock helper + cost waiting. Re-creates `_acct_docs`, `_acct_inv_split72`, `_acct_stock_moves85`, `_pvar85`, `inventory_vs_gl` |
| 26 | phase97.sql | 72..88, 90, 91, 89 | guard inside. Landed cost. Re-creates `_acct_docs` from the phase89 body + bos97 blocks, so on its own it ERASES every bos96 line |
| 27 | **phase98.sql** | 72..97 | guard inside (24 marker objects + `bos89`; raises `phase98 needs phases 72..97 pasted first ... missing: <numbers>`). Re-creates 5 functions only: `_acct_docs` = phase89 body + all bos96 lines + both bos97 blocks (tag bos98 on one comment line), and the 4 other phase96 functions byte-identical. Creates run only if both guards passed. No table, rule, data, privilege or trigger |
| 28 | phase99.sql | 72..98 | guard inside (one marker object per phase 72..97 + `bos89` + `bos98` in `_acct_docs`; raises `phase99 needs phases 72..98 pasted first ... missing: <numbers>`). Step Opt: two OPTIONS (bill payment, inbox masking), all default OFF. Re-creates 5 functions only (`inbox_list`, `inbox_get`, `online_orders_list`, `online_order_get`, `telegram_chat_info`, tag bos99) - none of them is touched by phase98, and phase99 does not touch `_acct_docs`. If a later phase re-creates one of the five, merge into the phase99 text. See docs/briefs_p2p3/step_Opt_REPORT.md |
| 29 | phase100.sql | 72..97 | guard inside (Step Cat: one category / sub-category master, rule `category_required_on_item`). Re-creates no existing function. See docs/briefs_p2p3/step_Cat_REPORT.md |
| 30 | phase101.sql | 72..98 | guard inside (Step Rec: setup advisor rows for every rule of phases 82..98; only `setup_rec_defs81` rows, ON CONFLICT DO NOTHING). See docs/briefs_p2p3/step_Rec_REPORT.md |
| 31 | phase102.sql | item images (built on branch `fix/phase-Img`, now in this branch); re-creates no accounting function | goes between 101 and 103; phase103 does not need it |
| 32 | **phase103.sql - LAST** | 72..101 | guard inside (one marker object per phase 72..99 + `bos98` in `_acct_docs` + `item_categories` (100) + the phase101 advisor row; raises `phase103 needs phases 72..101 pasted first ... missing: <numbers>`). Step E2E: defects D-1..D-8 of the independent end-to-end run. Re-creates 20 functions from their LATEST bodies (`_acct_docs`, `_acct_stock_moves85`, `inventory_vs_gl`, `_cw_docs96`, `_cw_rows96`, `_cw_posted96`, `_ob_rows96`, `_ob_plan96`, `opening_stock_apply96`, `recipe_cost`, `_setup_chk81`, `setup_recommendations`, `setup_recommend_apply`, `_inb_pii_f99`, `_inb_pii_json99`, `inbox_list`, `customer_directory`, `find_customer`, and `online_order_get` / `online_orders_list` byte-identical so one paste repairs a re-paste of phase89; every older bosNN tag kept, new tag bos103), adds 3 internal helpers, 1 switch `acct_manual_prod_in103` (default OFF), 1 flow check row, 1 grant def, 1 append-only table `opening_stock_followups103` + view `opening_covered103`. A body with a tag it does not know stops the paste. See docs/briefs_p2p3/step_E2E_REPORT.md |

**Invariant: phase103 is the last file (it re-creates the final bodies of what phase96 / 98 / 99 / 81 / 73 / 74 re-create). If phase89, phase94, phase96, phase97, phase98 or phase99 is ever pasted again, paste phase98 (if it was 89 / 94 / 96 / 97) and then phase103 again after it** (phase89 alone puts the older `_acct_docs` and `inventory_vs_gl` back; phase97 alone drops the bos96 lines).

(The number 89 is out of sequence on purpose: it was reserved for this integration fix. It is pasted after 90 and 91; 92, 93, 95 and then 94 (the security step, also out of sequence) follow. `tests/sql/final_build.sh` builds exactly this order; 96 and 97 follow 94 and 98 closes the chain.)

## C. Why phase89 comes after 90 and 91

Each phase was written on its own branch, from the function text that existed there, so a later number could silently put an older body back.
Found by comparing `pg_get_functiondef` after every phase on a fresh build: phase83 dropped the phase82 `unit_conv_required` rule from `_sale_stock_out`,
phase85 dropped the phase80 free-cost rule from `_acct_docs`, phase88 dropped it from `_cogs_lines72`. phase89 re-creates those three as merges and re-asserts
the final body of every other function that two or more phases re-create (28 more), so the result does not depend on who was pasted when.
After phase89 the only functions whose text differs from "numeric order without 89" are those three.

## D. Rules for the next phase (92, 93, ...)

1. Paste it after phase94 (or, if it re-creates a function of phase94, merge into that text), then compare `pg_get_functiondef` before/after for every function it re-creates; if it re-creates one that appears in phase89, merge the new lines into the phase89 text (or paste a new phase89 version) and keep every `bosNN` tag.
2. Run `supabase/phase89_test.sql` (T0 lists 50 function/tag pairs) and `supabase/phase94_test.sql` after the new phase; a lost tag shows up as a FAIL.
3. Never edit an old phase file; add a `phaseNNb_test.sql` copy when an old assertion becomes false by design (done for 72b, 73b, 76b).

## E. Step INT3 (phase96/97/98) - what the per-phase diff showed

Method: fresh build to phase71, then every phase in the order above, `md5(pg_get_functiondef)` + `bosNN` tags of all 1212 public functions stored after each phase. Tags lost by a later phase in this order: only `_acct_docs(date)` (bos96 lost by phase97). All earlier losses (bos72/73/80/82 by phases 73, 74, 78, 83, 85, 88) are repaired by phase79 / phase89 as before. phase94 loses nothing. Phase98 merges the one remaining loss.
`supabase/phase89_test.sql` P2 ("second paste identical") is false by design once phase96/97 exist (phase89 alone is not the end of the chain); use `supabase/phase89c_test.sql` (P2 = phase89 then phase98 = identical, and P2a: phase89 alone changes exactly `_acct_docs` and `inventory_vs_gl`). Do not edit phase89_test.sql.

## F. Rules for the next phase (99, ...)

Same as D, but the last file is now phase98: a phase that re-creates `_acct_docs`, `_acct_inv_split72`, `_acct_stock_moves85`, `_pvar85` or `inventory_vs_gl` must merge into the phase98 text (new phase98 version) and keep every `bosNN` tag; run phase89c_test, phase94_test, phase96_test, phase97_test and phase98_test.

## G. Rules for the next phase (104, ...) - the last file is now phase103

Same as D and F, with phase103 as the last file: a phase that re-creates any of the 20 functions listed in row 32 (or `_acct_docs`, `inventory_vs_gl`, `recipe_cost`, `_setup_chk81`, `setup_recommendations`, `setup_recommend_apply`, `inbox_list`, `customer_directory`, `find_customer`) must merge into the phase103 text (a new phase103 version) and keep every `bosNN` tag. Run phase89c_test, phase89d_test, phase94_test, phase96_test, phase98_test, phase99_test, phase101_test and phase103_test. Old assertions that are false by design once phase103 exists are copied to a `phaseNNb_test.sql` (never edit the old file); see docs/briefs_p2p3/step_E2E_REPORT.md for the list.
Build: `bash tests/sql/final_build.sh <db> "<canonical order ... phase98 phase99 phase100 phase101 phase103>"` (tests/sql/run_all_sql.sh appends every `supabase/phase1NN.sql` that is not in the table above, in numeric order).

## H. Live status

Installed on the owner's live database, in this order (72..103 - all 32 new files, each once). Checked with `python3 tools/check_paste_order.py`.

| order | file | status |
|-------|------|--------|
| 1-10 | phase72 .. phase81 | installed |
| 11-27 | phase82, 83, 84, 85, 86, 87, 88, 90, 91, 89, 92, 93, 95, 94, 96, 97, 98 | installed |
| 28-31 | phase99, phase100, phase101, phase102 | installed |
| 32 | phase103 (LAST) | installed |

Next file: phase104 (see section G).
