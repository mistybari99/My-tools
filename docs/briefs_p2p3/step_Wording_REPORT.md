# Step Wording - apply the Bangla review (branch fix/wording)

Source: `docs/i18n/BANGLA_REVIEW.csv` (+ `.md`). Owner decisions: (a) bn mode = common English word in Bangla letters, mix mode = Latin; (b) fixes only for NEW strings (added since 04eefa4), old texts never touched; (c) clear cases follow the 71-term table, two-meaning cases are left and listed in `docs/i18n/NEEDS_DECISION.md`.

## Result

| item | count |
|---|---|
| web rows with a suggestion (unique file/en/bn/mix/suggestion) | 1125 |
| applied | 1120 (77 files; 905 changed lines = see `git diff --stat`) |
| already equal to the suggestion (re-run) | 0 first run, 1119 on the second run (idempotent: second run applied 0) |
| old-text-protected (triple exists unchanged in `git show 04eefa4:<file>`) | 3 |
| skipped, needs a decision (Void/Cancel/Reject etc.) | 2 web + 1 sql -> `docs/i18n/NEEDS_DECISION.md` (3 items, all recommended A) |
| skipped, anchor missing / text changed | 0 |
| rough "≈" mix drafts (reviewer says "polish by hand") | 72 web rows: NOT applied (only the bn part of those rows was applied) |
| SQL seed rows -> `supabase/phase108.sql` | 124 guarded UPDATE statements (rules 77, setup_check_defs81 30, grant_defs 9, manual_reason_codes85 5, grant_separation_pairs 2, cost_component_types 1); 1 row not handled (setup_topic_defs81, no key in CSV), 1 needs a decision |

`setup_rec_defs81` reason texts: the CSV holds no review rows for them, so nothing was emitted (add rows to the CSV and re-run `--emit-sql`).
en slots: unchanged (checked: the ordered list of en slots of every changed file is identical to HEAD; `lang_en_test` 0 Bangla in en).

## Tool: `tools/apply_bangla_review.py`

- Reads the CSV; for each row finds the `L(bn, en, mix)` call (or the `{bn, mix, en}` object in `web/i18n.js`) in the row's file whose **en slot** equals the CSV `en` and whose bn slot equals `current_bn`; rewrites only the bn (and mix) string literal, keeping the original quote style.
- Skips when the anchor is missing, when bn/mix no longer equal the CSV "current" text (owner/other-branch edit), when bn already equals the suggestion, when the triple is old (04eefa4), and for two-meaning words (বাতিল, খরচ, বাকি, ফেরত, জমা: applied only when the English text has exactly one of the meanings; খরচ -> কস্ট only for "cost").
- Options: `--dry-run`, `--files 'web/pos*.js'` (glob on the CSV path), `--csv`, `--base 04eefa4`, `--needs-decision <md>`, `--emit-sql <sql>`, `-v`. Prints applied / already / skipped / old-text-protected.

### Re-run after other branches merge new code
```
git merge <branches>                       # new code with new L() strings
python3 tools/apply_bangla_review.py --dry-run         # counts first
python3 tools/apply_bangla_review.py --needs-decision docs/i18n/NEEDS_DECISION.md
node --check web/*.js; node tests/web/lang_all_test.js   # NEW must be 0
```
Strings added by those branches are only touched if the CSV has a row with the same file + en + current bn (i.e. reviewed). For strings added after the review, regenerate the CSV first. `phase108.sql` is regenerated whole by `--emit-sql supabase/phase108.sql`; its UPDATEs only fire while the column still holds the old seed text, so it is safe to paste after owner edits and twice.

## Verification

- `node --check web/*.js`: all 103 OK.
- `lang_all_test`: violations 2861 = baseline 2861, NEW 0. `lang_en_test`: 0 Bangla in en. `order_test`: 37 pass / 0 fail.
- SQL: `bash tests/sql/run_all_sql.sh` (full): TOTAL fail 31 = baseline 31, no suite changed; new `supabase/phase108_test.sql` 11 pass / 0 fail (reviewed text applied, paste-twice identical, owner edit survives, old seed text gets fixed, guard refuses when the phase103 marker is missing and changes nothing). run_all_sql.sh appends phase108 automatically after phase103.
- Screen tests run before/after (old tests NOT edited): unchanged (0 fail): groupab, ia, nav2, ownerboard, itemmaster, rules, daybook, notifications, q4_pw, landed_pw (+ order/lang tests above).

## Old tests that hard-code an old Bangla string (lead decides; NOT edited)

| test | assertion | old string now changed |
|---|---|---|
| setupadvisor_test.js:35 | Bangla mode renders Bangla | `প্রস্তাবিত প্রয়োগ` -> `প্রস্তাবিতগুলো অ্যাপ্লাই করুন` |
| costsources_test.js:133 | Bangla status labels | `বিল বাকি` / `অভাগিত` (reviewer: waiting/over-formal word) |
| costing_test.js:138,140 | Bangla title / cost sheet labels | `খরচ`, `রূপান্তর খরচ অসম্পূর্ণ`, `আজকের কেনা দাম` -> কস্ট / প্রাইস |
| costattrib_test.js:181 | Bangla switch labels | `রেসিপি অনুমোদন` -> `রেসিপি অ্যাপ্রুভ` |
| accounts_test.js:230 | Bangla labels | `মোট সম্পদ` -> `টোটাল সম্পদ` |
| invoiceview_test.js:121 | Bangla no-printer text keeps Share / Download in English | now শেয়ার/ডাউনলোড in Bangla letters (owner rule (a) says শেয়ার) |
| s1setup_test.js:96,97 | Bangla title / cost_missing label | `খরচ`, `খরচ অজানা` -> `কস্ট ... ` |

Each failure is the new text from the owner rule, not a code defect; the fix is a one-line regex update in the test (or revert that row in the CSV).
