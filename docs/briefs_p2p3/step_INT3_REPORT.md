# Step INT3 - phase98 (merge of phase96 + phase97) + canonical order + full regression

Branch `fix/phase-INT3` (from `integration/p72-p79` = phases 72-97 merged). New files: `supabase/phase98.sql`, `supabase/phase98_test.sql`, `supabase/phase89c_test.sql`, this report. Edited: `docs/PASTE_ORDER.md`, `tests/sql/final_build.sh`. No old phase file, no old test file, no web file was edited. Nothing touched a live database; every number comes from scratch Postgres 16 databases (socket /tmp port 5544, names `i3_*`, dropped).

## যাচাই হয়েছে (measured on fresh builds)

### 1. Per-phase diff (fresh build, canonical order, `pg_get_functiondef` md5 + bosNN tags of all 1212 public functions after EVERY phase)
Order: 72..88, 90, 91, 89, 92, 93, 95, 94, 96, 97. Tags lost by a later phase:

| function | tag lost | lost by | repaired by |
|---|---|---|---|
| `production_post(6 args)` | bos72 / bos73 | 73 / 74 | wrapper since 74 (by design) |
| `_acct_docs(date)` | bos72 | 74 | phase79 |
| `_r3q_l1_pnl`, `_r3q_l3_shop_pnl` | bos72 | 78 | phase79 |
| `_sale_stock_out()` | bos82 | 83 | phase89 |
| `_acct_docs(date)` | bos80 | 85 | phase89 |
| `_cogs_lines72(...)` | bos80 | 88 | phase89 |
| **`_acct_docs(date)`** | **bos96** (3 `stock_ledger_eff96` reads) | **97** | **phase98 (new)** |

Findings: phase94 loses nothing in this order (its `_sale_stock_out` lines are already inside phase89.sql: 3 `bos94` lines). phase96 re-creates 5 functions (`_acct_docs`, `_acct_inv_split72`, `_acct_stock_moves85`, `_pvar85`, `inventory_vs_gl`); phase97 re-creates only `_acct_docs`. So in the order 96 then 97 the only lost tags are the bos96 lines of `_acct_docs`. Measured effect without phase98: phase96_test = 113 pass / 11 fail (cost-waiting documents are not journalled from the waiting list); with phase98: 124 / 0. In the reverse order (97 then 96) phase96's own body guard refuses (it sees bos97). A second case: phase89 pasted again puts back older `_acct_docs` AND `inventory_vs_gl` (bos96 lost in both) - phase98 repairs that too, so the rule is: paste phase98 again after any re-paste of 89 / 96 / 97.

### 2. phase98.sql (46 KB, 5 `create or replace function`, nothing else)
* `_acct_docs(date)` = 3-way merge, base = body after phase94 (phase89 body), A = after phase96, B = after phase97: no conflict. Result carries bos50 52 72 74 80 85 89 96 97 + bos98 (one comment line). The other four functions are the phase96 bodies, byte-identical.
* Guard 1: 24 marker objects (phases 72..78, 80..88, 90..97, phase79 via bos72 in the 7-arg `production_post`, phase89 via bos89 in `_acct_docs`) -> `phase98 needs phases 72..97 pasted first (see docs/PASTE_ORDER.md); missing: <numbers>`. Guard 2 (body guard): a live body with a tag not in the known list stops it. The creates run only if both guards passed (session flag), so a client that keeps going after an error changes nothing (tested).
* Applied to the build 72..97: **exactly 1 function hash changes (`_acct_docs`)**, the other 1211 identical; second paste: 0 changes; ACL / SECURITY DEFINER / volatility / search_path of all 1212 functions identical; table ACL + RLS flags, triggers, policies, rewrite rules, `rules` rows identical.
* `phase98_test.sql`: **27 pass / 0 fail** (tags, merge shape, no conflict marks, view `stock_ledger_eff96`, re-paste of 97 loses bos96 and 98 restores the identical hash, paste twice = no body / ACL / table change, guard with a missing phase marker, body guard with a foreign tag, recovery).
* `phase89c_test.sql` (copy of phase89_test; P2 = phase89 then phase98 gives identical bodies; P2a: phase89 alone changes exactly `_acct_docs` and `inventory_vs_gl`): **65 / 0**. The old `phase89_test.sql` on the final build is 63 / 1 (only P2 "second paste identical", false by design once phase96/97 exist; not edited).

### 3. Canonical order (docs/PASTE_ORDER.md, tests/sql/final_build.sh)
72..88, 90, 91, 89, 92, 93, 95, 94, 96, 97, **98**. The diff analysis showed no better order; the invariant holds (98 last; phase96 guard needs bos85 + bos89 in `_acct_docs`: satisfied; phase97 guard satisfied). Build from nothing with the committed script: 1212 functions; the build without 96/97/98 has 1152.

### 4. Full SQL regression - every `supabase/*_test.sql`, each on its own fresh clone, with the sweeps after each (negative stock / stock cache vs ledger / unbalanced entries / trial balance = journal lines / profit_source_check)
| suite | final build (72..97 + 98) | same build without 96, 97, 98 |
|---|---|---|
| phase8 | 106/1 | 106/1 |
| phase10 | 306/1 | 306/1 |
| phase11 | 68/0 | 68/0 |
| phase12 | 97/0 | 97/0 |
| phase13 | 76/0 | 76/0 |
| phase14 | 153/0 | 153/0 |
| phase15 | 113/1 | 113/1 |
| phase16 | 167/0 | 167/0 |
| phase17 | 147/0 | 147/0 |
| phase18 | 108/0 | 108/0 |
| phase19 | 93/1 | 93/1 |
| phase20 | 63/0 | 63/0 |
| phase21 | 75/1 | 75/1 |
| phase21b | 75/1 | 75/1 |
| phase22 | 71/8 | 71/8 |
| phase22b | 82/0 | 82/0 |
| phase23 | 91/1 | 91/1 |
| phase24 | 22/0 | 22/0 |
| phase25 | 91/0 | 91/0 |
| phase26 | 117/0 | 117/0 |
| phase27 | 55/0 | 55/0 |
| phase28 | 41/0 | 41/0 |
| phase40 | 119/0 | 119/0 |
| phase41 | 171/0 | 171/0 |
| phase42 | 160/0 | 160/0 |
| phase43 | 144/0 | 144/0 |
| phase44 | 181/0 | 181/0 |
| phase45 | 46/0 | 46/0 |
| phase46 | 117/0 | 117/0 |
| phase47 | 70/2 | 70/2 |
| phase48 | 54/0 | 54/0 |
| phase49 | 16/0 | 16/0 |
| phase50 | 45/0 | 45/0 |
| phase51 | 23/0 | 23/0 |
| phase52 | 33/0 | 33/0 |
| phase53 | 112/0 | 112/0 |
| phase54 | 84/0 | 84/0 |
| phase60 | 62/0 | 62/0 |
| phase61 | 114/0 | 114/0 |
| phase62 | 74/0 | 74/0 |
| phase70 | 28/0 | 28/0 |
| phase71 | 26/0 | 26/0 |
| phase72 | 70/1 | 70/1 |
| phase72b | 71/0 | 71/0 |
| phase73 | 96/2 | 96/2 |
| phase73b | 98/0 | 98/0 |
| phase74 | 96/0 | 96/0 |
| phase75 | 76/0 | 76/0 |
| phase76 | 106/1 | 106/1 |
| phase76b | 107/0 | 107/0 |
| phase77 | 26/0 | 26/0 |
| phase78 | 101/0 | 101/0 |
| phase79 | 77/0 | 77/0 |
| phase80 | 86/0 | 86/0 |
| phase81 | 64/0 | 64/0 |
| phase82 | 57/0 | 57/0 |
| phase83 | 76/0 | 76/0 |
| phase84 | 64/0 | 64/0 |
| phase85 | 85/0 | 85/0 |
| phase86 | 65/0 | 65/0 |
| phase87 | 53/0 | 53/0 |
| phase88 | 47/0 | 47/0 |
| phase89 | 63/1 | 64/0 (differs) |
| phase89c | 65/0 | 64/1 (differs) |
| phase90 | 119/0 | 119/0 |
| phase91 | 97/0 | 97/0 |
| phase92 | 46/0 | 46/0 |
| phase93 | 18/0 | 18/0 |
| phase94 | 80/0 | 80/0 |
| phase95 | 48/0 | 48/0 |
| phase96 | 124/0 | 17/51 (differs) |
| phase97 | 155/0 | 25/41 (differs) |
| phase98 | 27/0 | 16/11 (differs) |
| TOTAL (73 files) | 6259/22 | 6011/125 |

* Final build: **6259 pass / 22 fail over 73 files**. The 22 fails are the same carried, understood baseline as in step INT2 (phase8 T1, phase10 T12, phase15 T0, phase19 T0, phase21 T1, phase21b T1, phase22 M2 x8 [replaced by phase22b 82/0], phase23 T0, phase47 T1 x2, phase72 T0 [72b 71/0], phase73 T4 x2 [73b 98/0], phase76 T1 [76b 107/0], phase89 P2 [89c 65/0]). Compared with the build without 96/97/98 the only differing rows are the phase96/97/98 suites themselves (absent phases) and phase89 / phase89c (P2).
* Sweeps on 146 clones (73 files x 2 builds): unbalanced entries 0 everywhere; trial balance diff 0.00 and rows = journal lines in all 19 clones that have journal entries; stock cache = ledger everywhere except the deliberate fixtures of phase21 / 21b / 22 / 22b (identical on both builds); negative-stock counts come from deliberate fixtures and are identical on both builds. Sweep strings final vs without 96/97/98 differ only in phase96 and phase97 (more journal entries because their scenarios work: 18 vs 9, 38 vs 21; all balanced).
* Same suites 96/97 on the build 72..97 WITHOUT phase98: phase96 113/11, phase97 155/0; WITH phase98: 124/0 and 155/0.

### 5. Web (copy of the tree at /tmp, hard-coded root replaced, one script at a time, exit codes)
* `grep -rn '^<<<<<<<\|^>>>>>>>' web supabase docs`: 0 lines. `node --check` on all 95 `web/*.js`: 0 errors. All 95 `<script src>` of `web/index.html` exist. `ia_test` (registry: no duplicate id/route, every live route resolves to a handler, drawer entries present): 0 failures. `lang_en_test`: 87 English strings, 0 Bangla.
* All 83 scripts (`*_test.js` + `smoke.js`): **83 / 83 exit code 0**, assertion lines all 0 failures except one carried assertion: `pos2_test` prints `FAIL: old queued payload sent` / `discount asserts failed: 1` (exit 0). It fails identically on the commit before phase95 (8ce3bef^), so it is not caused by 94-98 or by this step; not fixed (no web edit in this step).

| script | exit | last line |
|---|---|---|
| accounts_test.js | 0 | assert failures: 0 |
| allforms_test.js | 0 | errors: none |
| assistant_test.js | 0 | assert failures: 0 |
| attend2_test.js | 0 | assert failures: 0 |
| attendance_test.js | 0 | assert failures: 0 |
| barcode_test.js | 0 | assert failures: 0 |
| biz_test.js | 0 | errors: none |
| blind_test.js | 0 | assert failures: 0 |
| blindstock_test.js | 0 | assert failures: 0 |
| books85_test.js | 0 | checked 38, failed 0 |
| books96_test.js | 0 | checked 356, failed 0 |
| bulkitems_test.js | 0 | assert failures: 0 |
| cashdrawer_test.js | 0 | cashdrawer_test: 97 pass / 0 fail |
| cd_test.js | 0 | assert failures: 0 |
| control_test.js | 0 | assert failures: 0 |
| controls_test.js | 0 | assert failures: 0 |
| costattrib_test.js | 0 | assert failures: 0 |
| costing_test.js | 0 | assert failures: 0 |
| costsources_test.js | 0 | assert failures: 0 |
| customers_test.js | 0 | assert failures: 0 |
| daybook_test.js | 0 | assert failures: 0 |
| dscr_test.js | 0 | checked 351, failed 0 |
| employees_test.js | 0 | assert failures: 0 |
| engine_test.js | 0 | assert failures: 0 |
| favsync_test.js | 0 | errors: none | fails 0 |
| finance2_test.js | 0 | assert failures: 0 |
| forms_links_test.js | 0 | assert failures: 0 |
| groupab_test.js | 0 | assert failures: 0 |
| guards_test.js | 0 | guards_test: 35 pass / 0 fail |
| ia_test.js | 0 | assert failures: 0 |
| inbox_test.js | 0 | RESULT pass=47 fail=0 |
| integrations_test.js | 0 | RESULT pass=15 fail=0 |
| invoice_test.js | 0 | assert failures: 0 |
| invoiceview_pw_test.js | 0 | invoiceview_pw_test: 37 pass / 0 fail | page errors: none |
| invoiceview_test.js | 0 | invoiceview_test: 65 pass / 0 fail |
| itemmaster_test.js | 0 | assert failures: 0 |
| items2_test.js | 0 | assert failures: 0 |
| items3_test.js | 0 | assert failures: 0 |
| landed_pw_test.js | 0 | assert failures: 0 |
| landed_test.js | 0 | landed_test: 18 pass / 0 fail |
| lang_en_test.js | 0 | checked 87 English strings, bangla found in 0 |
| listctl_test.js | 0 | assert failures: 0 |
| lists_test.js | 0 | errors: none |
| locations_test.js | 0 | assert failures: 0 |
| nav2_test.js | 0 | assert failures: 0 |
| nav_test.js | 0 | errors: none |
| notifications_test.js | 0 | assert failures: 0 |
| optviews_test.js | 0 | optviews_test: pass=58 fail=0 |
| optviews_ui_test.js | 0 | assert failures: 0 |
| outbox_test.js | 0 | assert failures: 0 |
| ownerboard_test.js | 0 | ownerboard_test fails: 0 |
| partners_test.js | 0 | assert failures: 0 |
| payroll_test.js | 0 | assert failures: 0 |
| photo_test.js | 0 | errors: none |
| pos2_test.js | 0 | errors: none |
| pos_units_test.js | 0 | assert failures: 0 |
| posfail_test.js | 0 | RESULT 23 pass / 0 fail |
| purchase3_test.js | 0 | assert failures: 0 |
| purchase_test.js | 0 | assert failures: 0 |
| recipebook_test.js | 0 | assert failures: 0 |
| recipes_test.js | 0 | assert failures: 0 |
| reports_test.js | 0 | errors: none |
| restoredrill_test.js | 0 | assert failures: 0 |
| rollout_test.js | 0 | assert failures: 0 |
| rules_test.js | 0 | errors: none |
| s1setup_test.js | 0 | assert failures: 0 |
| salary_test.js | 0 | assert failures: 0 |
| salereturn_test.js | 0 | assert failures: 0 |
| salesx_test.js | 0 | assert failures: 0 |
| scan_pw_test.js | 0 | scan_pw_test: 31 pass / 0 fail |
| scan_test.js | 0 | scan_test: 65 pass / 0 fail |
| settings2_test.js | 0 | assert failures: 0 |
| setupadvisor_test.js | 0 | setupadvisor: 22 pass, 0 fail |
| sign_test.js | 0 | assert failures: 0 |
| smoke.js | 0 | JS errors: none |
| stepw_test.js | 0 | stepw_test: 75 pass / 0 fail |
| stock2_test.js | 0 | assert failures: 0 |
| stock3_test.js | 0 | assert failures: 0 |
| stockx_test.js | 0 | assert failures: 0 |
| theme_test.js | 0 | assert failures: 0 |
| tpl_test.js | 0 | tpl_test: 2248 pass / 0 fail |
| tplpicker_test.js | 0 | tplpicker_test: 52 pass / 0 fail |
| twofa_test.js | 0 | web twofa: 31 pass / 0 fail |

### 6. Language
No UI string, no web file touched. phase98 has no user-visible text (SQL comments and the guard exception are English, same style as phase89). `lang_en_test` 87 strings / 0 Bangla.

## পড়ে বোঝা (read, not run)
* The 3-way merge reasoning (which lines belong to bos96 / bos97) rests on the diff output: bos96 = 3 `stock_ledger_eff96` substitutions, bos97 = two appended `return query` blocks; the merged text was also exercised by phase96_test (124/0), phase97_test (155/0) and phase98_test (27/0).
* Supabase SQL editor behaviour (whole paste in one transaction) is assumed; the file is also safe when a client continues after an error (flag).
* pos2_test failure cause not analysed (only shown to pre-date phase95).

## যাচাই হয়নি (not verified)
* Nothing was run on the live database; the live state may differ from the fresh build (e.g. functions pasted in another order earlier): check with the hash/tag query before pasting phase98 there (`_acct_docs` must carry bos89; the body guard stops on unknown tags).
* Real browsers on devices (Playwright runs are headless Chromium with stubbed backend); the real Supabase auth/RLS roles (the build harness grants ALL to `authenticated`, so phase8 T1 stays a harness artefact).
* Orders other than the canonical one (e.g. 97 before 96, or 94 before 89) were not built beyond the guard behaviour.

## FINAL canonical paste list (phase numbers, bytes, SHA256 of every file)
Foundation (rows 1-46) is already on the live database; paste NEW files strictly in this order, each once: **72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 90, 91, 89, 92, 93, 95, 94, 96, 97, 98** (98 last; paste it again after any later re-paste of 89, 96 or 97). Rows below are in this order.

| # | file | bytes | sha256 |
|---|---|---|---|
| 1 | schema.sql | 48785 | eb2c9a75f66e29d567cd0c6a0beed14f8efeff01dddededc4192833a27af0268 |
| 2 | phase2.sql | 18911 | f10f4b74c01e084049428998dea5689dd80fbefb510602e3f4350a00e604a352 |
| 3 | phase3.sql | 12969 | 990f7e80e859faf4d8634218607dea0b1c8e150843b7f2c6292173f16646c73b |
| 4 | phase4.sql | 15554 | ef44712a2acbd8ba4d3807d64566c3dec970251d9a4a8fad2ddb5b8637db7f81 |
| 5 | ALL_NEW.sql | 74941 | 29ac5d7683831bb5f9bf60a3c0dc20dcc83fba63bbe12efd6cfd681be4a5c584 |
| 6 | phase8.sql | 60979 | 3667b66218be4d1ee025f42095000926fccb843cfc349ec711c138e0ce136ddb |
| 7 | phase9.sql | 102341 | 8d071b04f1c3aac6b313fb65fb277cf7bf769e51400adc27ca26286e1d28f210 |
| 8 | phase10.sql | 117287 | c145110b313c2e4055371425dba15f7eda305e9d795d759b4474461890a8857b |
| 9 | phase11.sql | 16952 | 85064b015b51823647dc86c64685600b8344d3f1c6e29adeec8a89ff0da99384 |
| 10 | phase12.sql | 66681 | aa782a487bce5468ed405a95c55e4785f8734c027325fefa68008e2f51a115c9 |
| 11 | phase13.sql | 39899 | 38b13e77c31adfdabb57f9ef6ec5acea17db48e70e972b49f2b1ca88447a9781 |
| 12 | phase14.sql | 82257 | f3bf5f26cedaa2d99857a66a868eeca74e4ca181c104fece40a2d0bb3d2eebdb |
| 13 | phase15.sql | 38266 | a20ed3b9930eb029f03c097f18eb6e9846b61a7ea4409b277c060854ea83f794 |
| 14 | phase16.sql | 71785 | 2b290d05f3c3363db42551098658802746e6b7725e65a33fa6d5153e1c4bc92c |
| 15 | phase17.sql | 55842 | dd29093983bd16ef3a5334cd792b97ccf1ab839a4247115ba0ac79c9dbe55280 |
| 16 | phase18.sql | 42204 | ab775197cfb11a08b58aa5c6383342ded49dfa7202e15d44010b9eae8d1dfcf0 |
| 17 | phase19.sql | 45803 | 2bee4ad1a12ba07193ea09530045abc9ca6229507a63c5a34c45187051ec3aeb |
| 18 | phase20.sql | 38116 | e5c69eb0fbc92212c84caa22478e315ada1a2117fb84e039474ad5fceeb23afa |
| 19 | phase21.sql | 52508 | da4384652b4bd741b3e1843df1b35957c5ed5a5831a72e5f8ea9719fea4737c0 |
| 20 | phase22.sql | 32847 | 403d9fd12acae6bc4a7b5d78e2d96c35cd5b857d7d4a88a69965c93c7d263ce5 |
| 21 | phase23.sql | 59798 | 674ea0940fe253452924f4197cc16cbf8a6388b844be9beaf44fbcc0296b48a2 |
| 22 | phase24.sql | 15036 | 4d333db91982951e591fdd05e4da218f9bda13b5a0f4182eda391da15fa4c0f7 |
| 23 | phase25.sql | 38231 | f32b70135b1754ff3fb4a8a88bfee197221d0e5e1b787de859605d8bc00fcaba |
| 24 | phase26.sql | 57971 | 5a17708c8cb941708dd6215b3c319d9c50bab06501a99d22315e8d2f9c0e435d |
| 25 | phase27.sql | 30460 | fcc480200920fd424c958c231b4e4227d52aeb1345c793659408fb7b9782c9e6 |
| 26 | phase28.sql | 33912 | 9300144f3d44a2608fa3403b76a3bd5b8693d8a8441c269b3b1fa8d3b0f445fa |
| 27 | phase40.sql | 92940 | 567e5bb1aa58beadb5df42f43209ee58f4e8d9deece8b0fd93fd872bad7b186b |
| 28 | phase41.sql | 93475 | c77c19005715be965e3da1094e346c1c4d30eb34ea5ac0f0e4a5a8c44d4f0ed6 |
| 29 | phase42.sql | 144562 | a1e20014898a59f527b8cb6c234f8b3074a94f6ea1c85c886a88ec26998a9f97 |
| 30 | phase43.sql | 86418 | fc07905ce4664425bfbc161fabf90edca5a946e1103fa195aff4a28c80b6ee29 |
| 31 | phase44.sql | 101542 | 182865a236bb5849c4a9fe86b3be8840bf2f6598821fc7f3d156653b33943452 |
| 32 | phase45.sql | 9666 | 886ce666ec970be73a479a93841c85f12f1c0574554dd8f2203f0fec2e40cef8 |
| 33 | phase46.sql | 50082 | 5d9e3b4d5d6107004a26cf8976f7d43abe341fe11d967fc2daa0762e1405e0cd |
| 34 | phase47.sql | 41785 | 642cb0b95adf3c173babf3018f093f1eab74b1cdf064f5c11bf7ec1249464a30 |
| 35 | phase48.sql | 23432 | 440c77f447b46e74fe02ddd87d2042f11bdc1729f41ec3fea434c2e376ce796c |
| 36 | phase49.sql | 9075 | 332761b6f6afd1c45dadc0a71daf9c33f491733babdcbba794e485fe20a02fe3 |
| 37 | phase50.sql | 52411 | 1a06796a8b348904ceff31b204833c0040524b0764b62e7c3fad2fa88cd1dacb |
| 38 | phase51.sql | 18889 | 30f7a00ca0e291f2133252cef504e7cbed929c2f46b7350a2b66d36663a40386 |
| 39 | phase52.sql | 37154 | dc5148cfe93257c92d1db3fd3bf852ecebaa6034b78d0a9226f772234ae35e91 |
| 40 | phase53.sql | 72392 | 0a13207194b7d6b40f95760c484fc280373d438b6bcc505e41be00338fe7a1b0 |
| 41 | phase54.sql | 56084 | b0c491ccde98d77b131006527e06dc11039b4990cb416c729df107943b4f5daf |
| 42 | phase60.sql | 30781 | 6cad65228edc034fadb60fe4ca66d651c0390ebe7c87e18f54da6e3c0147d23b |
| 43 | phase61.sql | 60128 | 839452d17a29d6a7eaca144d9b7c9ea7ec4bf074709dc24702434709b3dbb508 |
| 44 | phase62.sql | 42084 | d41749fb51fe69537f86ae408856ef271eaf99070f9ff3342eacc073544ff6e1 |
| 45 | phase70.sql | 8136 | 5d6f9b35d6462dd0d2d82f1721cf25a4906cc44ebeafd6d1fad32c03f51ec185 |
| 46 | phase71.sql | 8372 | 5287908e77a5e221d62c7b1f801e5f19ac42d29d387b470f967c4cee8fd1fa7f |
| | (foundation above is already on the live DB; new files below) | | |
| 47 | phase72.sql | 78993 | 8b9a5ca868d8a4c39e13b577d2910e09ba838257371072806c1d4eaac17652e8 |
| 48 | phase73.sql | 53075 | b1b4f37682f62f8c73c37305f6492f1f7d90e3221613bc62b425c7a1de85f4d7 |
| 49 | phase74.sql | 77437 | 4ef3837cf9260fffe0fdc8d4a365695dfa21ddf4182b5063ddd86b67bab9dc72 |
| 50 | phase75.sql | 55469 | c450df969e4d6cde4ee723b47307a4f99070835d3c9f16b5ef34693584f2afba |
| 51 | phase76.sql | 67945 | d7a8bfdcbcfb966d7e301d2751b4e689bf041471512d49a02f10bba3545bbaaf |
| 52 | phase77.sql | 20754 | 5938a8a5cf343d605f864e737a5c9786a7432b4b71ec132efece0b13278a63ae |
| 53 | phase78.sql | 37377 | 5a8c2f306fdc3aa4f2c7c0879f5a03c3c34a9f99fa0dc716e5fcd60368e2fbb4 |
| 54 | phase79.sql | 46298 | 7a1a5d4dd3ac9f2491c248021b8dadb9af3d5551eb791df3d5d0318c05e65dd5 |
| 55 | phase80.sql | 94090 | c5143b460a0fb2e8d7171644b8963b2dcf8c8b04896838199128d159eeee90d3 |
| 56 | phase81.sql | 66194 | 5985766b48667d68c565fe26ae5b8523257b5ad7fa141e044896bf0fdac6691d |
| 57 | phase82.sql | 49642 | 61439adc346e3328c89a0d17309443cfacfc08a6e63b29cffb636b5e6665495a |
| 58 | phase83.sql | 68300 | 848328e519c1f4d9d63d47609cbed49e677c60e049151deb46367e39ca68e514 |
| 59 | phase84.sql | 11944 | 603f631fe38c2823bd3b8a954c4ff97584c8ddda377d0e516ca505a30c37c1d1 |
| 60 | phase85.sql | 84301 | 7b7f39d1e3b53216f216d6a8df0b1cff5af3eb182d08008fbdab4eff1f6b7a5e |
| 61 | phase86.sql | 24535 | ded9e918140ece5a1e187821982011bd5172b33485e77a0b9ad6c2a2fa73f993 |
| 62 | phase87.sql | 56635 | 37c6cc8fdcd18b30d29294a7707bbd0d373c6e8a3173448a9126ff5423c95e1a |
| 63 | phase88.sql | 22291 | 1e675266dc2729f7f52a39f7cc1eff29b7d14be041f89ff0ffdb625db5922dad |
| 64 | phase90.sql | 53322 | caf3bf9f2b21e1f7f88571ed252959b35a03897c1837903993cb24af84c9e6dc |
| 65 | phase91.sql | 43807 | c11e2663bce92cee7df14819b17c84c0be5c88250df06111122e2647fe661a5a |
| 66 | phase89.sql | 177201 | e32f027d9ed9222a969c7a1e37e9d9892518b69366cc89a192d931d2b8d2b1e0 |
| 67 | phase92.sql | 12337 | 8289d6bed95d0cea79a37d5f95cdc24f0dc301975c9fa72d4ead0607dd146534 |
| 68 | phase93.sql | 5497 | 0f43319cc7b54f85efcac24acac371fa036fe9e30e274d2718573f146ed4671e |
| 69 | phase95.sql | 15952 | 6d5e099b27c49a569e898cd43088ded58b9cfcc83be35b5a974cd3171302f150 |
| 70 | phase94.sql | 51353 | 78a7be33c5bb83860532f19550d2fc1234654eaeca6709eb09ac8dcbf746b1bc |
| 71 | phase96.sql | 101854 | 944c8c1cc8484895754771d8b89dfa23f562bd1efc04665a744261d0c1dc217d |
| 72 | phase97.sql | 151589 | e5966fb62ae9bdc02e504b4169c1b3141496b4475e7a9faeed9c0620882cca6a |
| 73 | phase98.sql | 47058 | d18772a45739a45747b553afd5b53ca34be6249497f513ea6ba6b4f1c0ebc5ac |

