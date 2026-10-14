# PASTE ORDER (the single canonical order)

Branch `fix/phase-INT2`. Every file is additive and paste-twice safe. Nothing is edited in an old phase file; later phases only `create or replace`.
This is the order that was built and tested from nothing (fresh Postgres 16, see docs/briefs_p2p3/step_INT2_G_REPORT.md). Any other order is untested.

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
| 20 | **phase89.sql - LAST** | 72..88, 90, 91 | guard raises `phase89 needs phases 72..88, 90, 91 pasted first ... missing: <numbers>` if any is absent |

(The number 89 is out of sequence on purpose: it was reserved for this integration fix. It is pasted last.)

## C. Why phase89 must be last

Each phase was written on its own branch, from the function text that existed there, so a later number could silently put an older body back.
Found by comparing `pg_get_functiondef` after every phase on a fresh build: phase83 dropped the phase82 `unit_conv_required` rule from `_sale_stock_out`,
phase85 dropped the phase80 free-cost rule from `_acct_docs`, phase88 dropped it from `_cogs_lines72`. phase89 re-creates those three as merges and re-asserts
the final body of every other function that two or more phases re-create (28 more), so the result does not depend on who was pasted when.
After phase89 the only functions whose text differs from "numeric order without 89" are those three.

## D. Rules for the next phase (92, 93, ...)

1. Paste it after phase89, then compare `pg_get_functiondef` before/after for every function it re-creates; if it re-creates one that appears in phase89, merge the new lines into the phase89 text (or paste a new phase89 version) and keep every `bosNN` tag.
2. Run `supabase/phase89_test.sql` (T0 lists 50 function/tag pairs) after the new phase; a lost tag shows up as a FAIL.
3. Never edit an old phase file; add a `phaseNNb_test.sql` copy when an old assertion becomes false by design (done for 72b, 73b, 76b).
