# Step INT4 - integration of phases 104..109 (+ phase111), paste order, tag-loss check

Branch `fix/phase-INT4` (from integration tip 9824741). Owner has installed 72..103. Pending: 104, 105, 106, 107, 108, 109, **111 (new)**. phase110 (Perf) is NOT in this branch: it exists only as uncommitted files in `/home/user/wt-perf` (branch fix/phase-Perf at fb73a6a, nothing pushed). When it is pushed: add `phase110` before `phase111` in `tests/sql/paste_order.env`, add its row 39 (111 becomes 40) in docs/PASTE_ORDER.md, change phase111's guard text to 72..110, re-run `bash tests/sql/tag_loss_check.sh`. Its function list (`_acct_stock_moves85 _cogs_lines72 _item_cost_eff88 _rcs88 inbox_list rpt_agg_sql`) does not overlap any function re-created by 104..109, so no new merge is expected.

## 1. Paste order (one place)
`tests/sql/paste_order.env` holds FOUNDATION + NEW; `final_build.sh`, `run_all_sql.sh`, `concurrency/build_template.sh` source it; `tools/check_paste_order.py` compares docs/PASTE_ORDER.md section B with it (clean: rows 1..39, no un-numbered rows, 104 present). Rows 1-32 unchanged (72..88, 90, 91, 89, 92, 93, 95, 94, 96..103), rows 33-39 = 104, 105, 106, 107, 108, 109, 111. "Live status" is now a bullet list (installed 72..103, pending list), not table rows.

## 2. Tag-loss check (`bash tests/sql/tag_loss_check.sh`)
Fresh build to the owner's state (72..103), then 104, 105, 106, 107, 108, 109 one at a time; md5(pg_get_functiondef) + bosNN tags of all 1263+ public functions after every phase (`tests/sql/fn_snapshot.sh`, `tools/tag_loss.py`).
- 104: 0 changed (2 new functions). 106: only `_backup_tables` (no other phase). 107: 10 new functions, 0 changed. 108: data only, 0 functions.
- 105: 13 functions changed, none loses a tag (bos105 added).
- 109: **FAILED to paste after 105**: its body guard raised on `_bp_pay99` (carries bos105). Without the guard it would have erased the bos105 L4 line (`client_id_reused`). `_bp_pay99` is the ONLY function re-created by two of the phases 104..109. The other 11 functions of 109 and the other 12 of 105 are disjoint, nothing else lost (no bos107/bos108 loss: 107/108 re-create no existing function).
- Fix: phase109 knows bos105/bos111 on `_bp_pay99` and skips that one function when bos105 is present; phase105 symmetric (knows bos109/bos111, skips `_bp_pay99` when bos109 is present, so a re-paste of 105 on the final DB leaves the merge alone); **phase111** = 3-way merge (phase103 body + bos105 line + bos109 `FOR NO KEY UPDATE`, tag bos111). Net result after 111: 0 tags lost between the phase103 baseline and the final build; every other function body equals what its own phase intends (hash-compared with 103+109 and 103+105 builds).

## 3. Regression
- `tests/sql/run_all_sql.sh` (all suites, final order incl. 111): see section 6.
- Replacement copies (old tests untouched): `phase89g_test.sql` (replaces 89f: re-pasting 89 now changes 8 functions, repaired by 103,105,109,111), `phase103c_test.sql` (replaces 103b: paste 103,105,109,111), `phase111_test.sql` (new). baseline_fails.txt updated (89f 2, 103b 1 by design; 98b 0; new suites 104 107 108 111 89g 103c = 0).
- e2e `rec`: 0 FAIL; `def`: 0 FAIL (one run showed `V1 readable TABLE rows containing cost fingerprints act=2` on sale timestamps = digit coincidence of the fingerprint match; a fresh run is 0). `final_sweep.sql`: unbalanced 0, cache mismatch 0, trial balance diff 0.00 (negbal=1 is the e2e's own deliberate negative-stock case, same as before).
- `tests/sql/concurrency/verify_fixes.sh both`: before 47 PASS / 10 FAIL (expected), **after 57 PASS / 0 FAIL**. (build_template now uses paste_order.env, so "after" includes 105 and 111.)
- Paste-twice on a DB built exactly as the owner's (72..103, owner order): each of 104, 105, 106, 107, 108, 109, 111 pasted twice in sequence; md5 over all function definitions identical after the second paste of every phase (no error on any second paste).
- Re-paste chains: `103 105 109 111`, `89 103 105 109 111`, `89 98 103 105 109 111` on the final DB change no function.

## 4. FINAL paste list (owner pastes in this order)
| # | phase | bytes | sha256 |
|---|-------|------:|--------|
| 1 | phase104.sql | 7284 | 4832bf18b4cd0fc1428368794d23f0b84991f8fedb3e8e925d4c2ba040e3ebbe |
| 2 | phase105.sql | 42703 | f0151974a83824491c8adc4c9d60ff60c63aee17a209e01f93e3fdf2efeff0ec |
| 3 | phase106.sql | 7404 | 4d241a03cf80b5b92fc946659a1e2a00bbfd577727a4f40ec29ee0acf4d4a471 |
| 4 | phase107.sql | 27576 | 5285df741bacb3583edc13c9eeaf4c6b6fff018cba8c6edd9403fa3132bd537f |
| 5 | phase108.sql | 38713 | f2a6686ce7966815b0644f241edd1a9aad3e841524d0e7728ccb77be234cfd04 |
| 6 | phase109.sql | 63402 | 5123cd02eda8362e52da20aff4a2d7e48cbc21305e92412fce4318a87c52540b |
| 7 | phase111.sql | 10251 | d3e824359485c5f7b1e4e927de6c88d0cf002be77933bccb44494ab7eaa06a01 |

Total 197,333 bytes (192.7 KiB). With phase110 (27,298 bytes in the unpushed WIP, size will change) the total is about 224 KB.

## 5. Run 12 paste pages (<= 200 KB each)
All seven files together are 197,333 bytes: they would fit ONE page only with a 2.7 KB margin (no room for page wrapper text) and phase110 cannot be added, so use **2 pages** (never split a file):
- Page 1 (123,680 bytes): phase104, phase105, phase106, phase107, phase108.
- Page 2 (73,653 bytes): phase109, phase111 (+ phase110 between them when it exists: about 101 KB). 
Page 2 must be pasted after page 1 completes; phase111 is always the last paste.

## 6. Full run_all_sql result
`bash tests/sql/run_all_sql.sh` on the final order (72..109 + 111, 97 suites incl. new ones): TOTAL pass=7369 fail=37, equal to baseline_fails.txt in every suite (0 REGRESSION, 0 NEW FAILS, 0 IMPROVED). The 37 known failures are the documented ones of step_INT3_REPORT plus the by-design ones listed above.

