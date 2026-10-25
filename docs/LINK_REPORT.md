# Doc link and path report

Produced by `tools/check_doc_links.py` on branch `docs/h4`. Scope: all 131 `*.md` files under `docs/`.

Run: `python3 tools/check_doc_links.py` (exit 1 when a finding other than SHORTHAND_PATH exists).

## Result

| Check | Count |
|---|---|
| Broken relative markdown links | 0 |
| Missing backtick paths (MISSING_PATH) | 13 |
| Shorthand paths that resolve to a repo file (SHORTHAND_PATH, info only) | 3 |
| Stale "coming" facts (branch, phase or report described as coming but now exists) | 0 |

Fixed in this branch (provable from the repo):

- `docs/briefs_p2p3/step_Q3_REPORT.md:9`: `p9/*.sh` changed to `tests/sql/p9/*.sh` (the directory is `tests/sql/p9/`).

## Findings in docs/guide/**, docs/backend/**, docs/i18n/** (not edited)

These folders belong to other agents. Nothing in them was changed.

- `docs/backend/DEVELOPER_RUNBOOK.md:52` `setup-sql.html`: the page is a temporary one-paste SQL page. It was never committed (no git history for it). The runbook should say it is generated locally, or the reference should be removed.
- `docs/backend/TROUBLESHOOTING.md:58` and `:62` `scan-extract/index.ts`, `telegram-webhook/index.ts`: shorthand for `supabase/functions/<name>/index.ts`. Both exist. Full paths would make the references unambiguous.
- `docs/guide/OWNER_GUIDE.md:4` and `docs/i18n/BANGLA_REVIEW.md:3` `supabase/phase72..103.sql`: range notation. All 32 files (phase72 to phase103) exist. Not an error.
- `docs/guide/OWNER_GUIDE.md:756`, `:1223`; `docs/guide/PHONE_ONLY_STEPS.md:11`; `docs/guide/ROLLOUT_PLAN.md:297` `step_Sec2_REPORT.md`: correctly missing. Phase 105 is still "coming".
- Stale-check note: `feat/dash`, `feat/glass` and `fix/phase-Sec2` exist only as local branches. No `origin/` remote-tracking ref exists for them (checked with `git for-each-ref refs/remotes`). The "coming" wording in `docs/guide/OWNER_GUIDE.md:756`, `:1224`, `:1225` and `docs/guide/PHONE_ONLY_STEPS.md:11` is therefore still accurate. Owner should re-check if these branches are pushed.

## Findings in other docs (not edited, for the owner)

- `docs/ERP_AUDIT_ROADMAP.md:92`, `docs/HANDOVER.md:12`, `docs/HANDOVER_2.md:8` `setup-sql.html`: same temporary page as above. Not in the repo.
- `docs/HANDOVER_2.md:39` `tests/web/pos_test.js`: deleted in commit d01b202 ("pos_test retired"). The sentence lists it as a stale test, so the reference is historical. Decide whether to keep it.
- `docs/OPS_SETUP.md:105` `restore.part01.sql`, `docs/OPS_SETUP.md:123` `photos_manifest.json`, `docs/RESTORE_DRILL.md:55` `drill.json`: runtime outputs written by `tools/restore_backup.py`, `tools/backup_photos.py` and `tools/restore_drill.py --report`. Not expected in the repo.
- `docs/briefs_p2p3/step_INT2_G_REPORT.md:145` `scratchpad/audit/a1..a4/*.sql` and `q.sql`: scratch files that were never committed.

## Shorthand paths (info only, no change)

- `docs/regs/assistant.md:16` `data/kb.json`: relative to `web/` in context. Resolves to `web/data/kb.json`. Left as written.
- `docs/backend/TROUBLESHOOTING.md:58`, `:62`: see above.
