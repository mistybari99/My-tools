# Recovery merge rehearsal: dry run of 20 Oct 2026

Produced by `python3 tools/recovery_merge.py` (default dry run). Scratch worktree and temp branch were removed afterwards; nothing was merged, committed on the designated branch, or pushed. The scratch paths below no longer exist. Re-run: `git fetch origin && python3 tools/recovery_merge.py`.

Generated 20261020-010704 UTC by tools/recovery_merge.py (dry run). Nothing was merged into claude/supabase-readonly-audit-xo3qkp, nothing was pushed.

- Ours: `claude/supabase-readonly-audit-xo3qkp` at `551eb71b`
- Source: `origin/ccr-9c1f9be7-3s9qnz` at `0bc142b1` (235 commits ahead, 202 behind, merge base `dbecc255`)
- Temp branch (local only): `recovery-trial-20261020-010704`; scratch worktree: `/tmp/claude-0/-home-user/109c3315-8257-55f9-8445-4e17b4fb685c/scratchpad/rec/recovery_merge_xmv8clpd`
- Disk used at start: 6.5%
- git merge exit code: 1 (1 = conflicts, expected)

## 1. Conflicts per area

| area | conflicted files |
|---|---:|
| sql | 46 |
| web | 16 |
| tests | 13 |
| docs | 2 |
| tools | 0 |
| ci | 0 |
| other | 1 |
| **total** | **78** |

Merged without conflict: 1304 files added from the source (51 under web/, 89 under supabase/), 302 files modified.

### Conflicted files: web

- `UU` web/app.js
- `UU` web/costing.js
- `UU` web/daybook.js
- `UU` web/filters.js
- `UU` web/i18n.js
- `UU` web/ia.js
- `UU` web/index.html
- `UU` web/itemmaster.js
- `UU` web/nav.js
- `UU` web/pos.js
- `UU` web/recipes.js
- `UU` web/salereturn.js
- `AA` web/scan.js
- `UU` web/stockx.js
- `UU` web/sw.js
- `UU` web/switchboard.js

### Conflicted files: other

- `UU` .gitignore

### Conflicted files: docs

- `UU` docs/BUILD-LOG.md
- `AA` docs/PASTE_ORDER.md

### Conflicted SQL phase numbers (23 numbers, test files counted with their phase)

80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 120, 131, 132

### Conflicted test files: .js x3, .png x7, .sh x3

## 2. Source-only web files that merged cleanly (51)

a11yfix.js, badges107.js, bizctx.js, books85.js, books96.js, cashdrawer.js, catpick.js, chanedit.js, charts.js, cheques127.js, coldstart.js, cost116.js, costboard.js, dashx.js, dashx_metrics.js, errlog.js, formscreens.js, guards.js, impexp124.js, invoiceview.js, itemimg.js, kbdfix.js, landed.js, landed_q4.js, lazy.js, optionsx.js, optviews.js, org122.js, packflags.js, places135.js, posfail.js, profile134.js, purchaseprint.js, recon118.js, reports131.js, s1setup.js, schemes128.js, setupadvisor.js, setupundo.js, stepw_common.js, theme_glass.css, theme_glass.js, tinting129.js, tpl_docs.js, tpl_labels.js, tpl_msgs.js, tpl_registry.js, tpl_samples.js, tplpicker.js, variants125.js, whatsnew.js

Note: a file that merged cleanly is NOT wired in. Wiring is `web/index.html`, `web/ia.js`, `web/sw.js` (all conflicted) - see the roadmap, phase P1.

## 3. Phase number collisions and the proposed renumbering (rules of tools/renumber.py: numbers <= 478 of this branch never change)

Same number, different content on the two sides: **23** numbers: 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 120, 131, 132

Source-only numbers that are free here and keep their number (31): 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 121, 122, 123, 124, 125, 126, 127, 128, 129, 133, 134, 135

| source phase (original name) | imported as | note |
|---|---|---|
| phase80 | phase506 | source side moves; ours keeps 80 |
| phase81 | phase507 | source side moves; ours keeps 81 |
| phase82 | phase508 | source side moves; ours keeps 82 |
| phase83 | phase509 | source side moves; ours keeps 83 |
| phase84 | phase510 | source side moves; ours keeps 84 |
| phase85 | phase511 | source side moves; ours keeps 85 |
| phase86 | phase512 | source side moves; ours keeps 86 |
| phase87 | phase513 | source side moves; ours keeps 87 |
| phase88 | phase514 | source side moves; ours keeps 88 |
| phase89 | phase515 | source side moves; ours keeps 89 |
| phase90 | phase516 | source side moves; ours keeps 90 |
| phase91 | phase517 | source side moves; ours keeps 91 |
| phase92 | phase518 | source side moves; ours keeps 92 |
| phase93 | phase519 | source side moves; ours keeps 93 |
| phase94 | phase520 | source side moves; ours keeps 94 |
| phase95 | phase521 | source side moves; ours keeps 95 |
| phase96 | phase522 | source side moves; ours keeps 96 |
| phase97 | phase523 | source side moves; ours keeps 97 |
| phase98 | phase524 | source side moves; ours keeps 98 |
| phase99 | phase525 | source side moves; ours keeps 99 |
| phase120 | phase526 | source side moves; ours keeps 120 |
| phase131 | phase527 | source side moves; ours keeps 131 |
| phase132 | phase528 | source side moves; ours keeps 132 |

Number 500 is retired (docs/NUMBERING.md section 8) and is skipped. The numbers above are a proposal: the live database already holds the source phases under their ORIGINAL numbers, so the imported files keep a note of the original number in their first comment line.

## 4. Repo checks

Rehearsed tree policy: conflicts resolved `ours`; leftover unmerged paths after resolution: 0.

| check | baseline (HEAD) | rehearsed merge | rehearsed output (last lines) |
|---|---|---|---|
| demo leak | OK | FAIL(1) | LEAK  tests/web/reports131_test.js:0  test file uses a roster staff name (2 hit(s)); use neutral test_* names / FAIL: 8 reference(s) to demo material in app code |
| numbering | OK | OK | [order]  ORDER.txt: 190 phases, duplicates none, missing files none / RESULT: PASS (0 failure(s), 0 warning(s)) |
| phase477 build | OK | OK | OK phase477.sql is up to date |
| test-only files | OK | FAIL(1) | Ran 8 tests in 14.183s / FAILED (failures=2) |
| info coverage | OK | FAIL(1) | rule:transit_loss_gl_fix  (phase 115) / rule:variants_on  (phase 125) |
| ui inventory | OK | FAIL(1) | checked 8823 baseline items against the current tree: 1490 added since the baseline, 5 accepted through aliases. / FAIL: 164 problem(s). Nothing may be lost silently (docs/UI_NO_LOSS_RULE.md). |
| report registry | OK | OK | OK |
| backup guard | OK | OK | OK: backup guard first, fails closed, no data artifact upload, only backup.yml pushes or moves dumps. / RESULT: PASS |

### Detail: demo leak (first lines of the failure)

```
LEAK  supabase/phase127_test.sql:0  test file uses a roster staff name (10 hit(s)); use neutral test_* names
LEAK  supabase/phase129_test.sql:0  test file uses a roster staff name (6 hit(s)); use neutral test_* names
LEAK  supabase/phase21b_test.sql:0  test file uses a roster staff name (7 hit(s)); use neutral test_* names
LEAK  tests/web/dashx_test.js:0  test file uses a roster staff name (2 hit(s)); use neutral test_* names
LEAK  tests/web/dealer127_test.js:0  test file uses a roster staff name (6 hit(s)); use neutral test_* names
LEAK  tests/web/items2_b_test.js:0  test file uses a roster staff name (6 hit(s)); use neutral test_* names
LEAK  tests/web/pos2b_test.js:0  test file uses a roster staff name (1 hit(s)); use neutral test_* names
LEAK  tests/web/reports131_test.js:0  test file uses a roster staff name (2 hit(s)); use neutral test_* names
FAIL: 8 reference(s) to demo material in app code
```

### Detail: test-only files (first lines of the failure)

```
FAIL: test_a_new_test_file_with_a_roster_name_fails_in_any_letter_case (__main__.DemoLeakRatchet.test_a_new_test_file_with_a_roster_name_fails_in_any_letter_case)
FAIL: test_clean_repository_passes (__main__.DemoLeakRatchet.test_clean_repository_passes)
LEAK  supabase/phase129_test.sql:0  test file uses a roster staff name (6 hit(s)); use neutral test_* names
LEAK  supabase/phase21b_test.sql:0  test file uses a roster staff name (7 hit(s)); use neutral test_* names
LEAK  tests/web/dashx_test.js:0  test file uses a roster staff name (2 hit(s)); use neutral test_* names
LEAK  tests/web/dealer127_test.js:0  test file uses a roster staff name (6 hit(s)); use neutral test_* names
LEAK  tests/web/items2_b_test.js:0  test file uses a roster staff name (6 hit(s)); use neutral test_* names
LEAK  tests/web/pos2b_test.js:0  test file uses a roster staff name (1 hit(s)); use neutral test_* names
LEAK  tests/web/reports131_test.js:0  test file uses a roster staff name (2 hit(s)); use neutral test_* names
FAIL: 8 reference(s) to demo material in app code
FAILED (failures=2)
```

### Detail: info coverage (first lines of the failure)

```
FAIL: rules added in phase 80 or later WITHOUT an entry:
```

### Detail: ui inventory (first lines of the failure)

```
MISSING (in the baseline, gone from the tree; 22):
RENAMED (label text changed; add an alias with a reason if intended; 142):
FAIL: 164 problem(s). Nothing may be lost silently (docs/UI_NO_LOSS_RULE.md).
```


## 5. Reading this report

- Conflicts are expected: the two lines reuse phase numbers 80-99, 120, 131, 132 for different work and both rewrote web/index.html, ia.js, nav.js, sw.js.
- A FAIL in the rehearsed column that is OK in the baseline column is work the real merge must do (wire scripts, add info entries, register phases in ORDER.txt, remove demo-like text).
- This is a rehearsal under policy `ours`; it does not decide any owner question.
