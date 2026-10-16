#!/usr/bin/env bash
# Build a clean branch (single commit, no demo history) from the current work branch, ready for a pull request to the default branch.
# Usage: tools/make_clean_branch.sh <work-branch> <base-branch> <new-clean-branch>
# Example: tools/make_clean_branch.sh claude/supabase-readonly-audit-xo3qkp ccr-78d03e25-k7ksyo clean/accounting-update
# Safe: it only creates a NEW local branch; it never rewrites, deletes or force-pushes an existing branch.
set -euo pipefail
WORK="${1:?work branch}"; BASE="${2:?base branch}"; NEW="${3:?new clean branch name}"
git fetch -q origin "$WORK" "$BASE"
git rev-parse --verify -q "refs/heads/$NEW" >/dev/null && { echo "branch $NEW already exists locally; choose another name"; exit 1; }
git checkout -q -b "$NEW" "origin/$BASE"
git checkout -q "origin/$WORK" -- .
# files deleted on the work branch must be deleted here too
git diff --name-only --diff-filter=D "origin/$BASE" "origin/$WORK" | xargs -r git rm -q --cached -- 2>/dev/null || true
python3 tools/check_no_demo_leak.py
git add -A
git commit -q -m "Accounting update: opening balance, money accounts, shortages, month close, wallets, balance check (no demo history)"
echo "Created local branch $NEW with one commit and no demo history."
echo "Check:  git diff --stat origin/$BASE $NEW   and   git log --oneline $NEW | head"
echo "Then push it yourself:  git push -u origin $NEW   and open the pull request from $NEW."
