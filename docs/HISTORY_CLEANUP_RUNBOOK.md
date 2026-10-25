# Keeping demo material out of the main app: runbook

## Current state
- Demo files were committed on the work branch `claude/supabase-readonly-audit-xo3qkp` (97 commits at the time of writing) and removed from the working tree in commit `6f7872b`. They still exist inside the older commits of that branch.
- Commits that added demo files: `c9957bc`, `a471a1a`, `76ae69e`, `25daa57`, `6b7bd5a`, `7f47ccc`, `7004d99` (moved to `docs/demo/`), removed in `6f7872b`.
- The default branch (`ccr-78d03e25-k7ksyo`) and all other branches contain no demo file.

## Rule (decided by the owner)
1. Never merge the work branch or pull request #5 as it is: its history contains demo files.
2. To deliver the real work, build a clean branch with ONE commit and no demo history:
   `tools/make_clean_branch.sh claude/supabase-readonly-audit-xo3qkp ccr-78d03e25-k7ksyo clean/accounting-update`
   Then compare (`git diff --stat origin/ccr-78d03e25-k7ksyo clean/accounting-update`), push the new branch and open the pull request from it. The script only creates a NEW branch; it never rewrites or deletes anything.
3. GitHub Actions `no-demo-leak` runs `tools/check_no_demo_leak.py` on every push and pull request. Turn on "require status checks" for the default branch in GitHub settings (owner action).

## If the owner later wants the history itself cleaned
Do it only when no agent is working, in this order:
1. Backup: `git branch backup/before-history-clean origin/claude/supabase-readonly-audit-xo3qkp` and push that backup branch; keep a zip of the repository.
2. Clean a COPY (fresh clone), not the working repository: `git filter-repo --invert-paths --path docs/demo --path-glob 'docs/DEMO_*' --path docs/FINAL_DEMO_BUSINESS_GUIDE.md --path docs/IMAGINED_FUTURE_SYSTEM_DEMO.md --path docs/REAL_LIFE_DAILY_WORKFLOW_GUIDE.md --path docs/REAL_LIFE_STORY_GUIDE.md`.
3. Prove nothing else changed: the file list and every file's content in the cleaned branch tip must equal the pre-clean tip, except the removed demo paths (`git diff --stat <old-tip> <new-tip>` must show only those paths, and none exist at the tip already).
4. Only after the proof, with the owner's explicit approval, push the cleaned branch under a NEW name, open the pull request from it, and delete the old branch last. Never force-push over the only copy.
5. Close pull request #5 and tell every agent that old commit hashes changed.
