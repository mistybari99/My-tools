# HANDOVER 3 — start of a new session (read this first)

State: phases 23–28 and 40–47 built, tested, published. Owner DB is at phase28; phases 40–47 are pasted by the owner from
https://mistybari99.github.io/islamia-bos-app/setup-sql.html (6 parts, in order 1..6; paste-twice safe). Ask the owner which parts they ran.

Repos: PRIVATE mistybari99/My-tools (branch ccr-2f54f832-rkdi5z, everything) ; PUBLIC mistybari99/islamia-bos-app (web/ copy + setup-sql.html).
Publish: python3 tools/build_kb.py ; copy web/ files (except setup-sql.html) to the public repo ; commit ; git push origin main.

Modules 40–47: accounts(40) employees(41) attendance/payroll(42) customer tiers(43) partners(44) owner board(45) notifications/backup(46) AI assistant(47).
Docs: OPS_SETUP.md, FINGERPRINT.md, ASSISTANT.md, ASSISTANT_AUDIT.md, briefs/, regs/.

Tests: Postgres 16 on /tmp port 5544 (see BUILD-LOG); tests/sql/build_fresh_db.sh with ORDER; web tests `node tests/web/<x>_test.js /home/user/My-tools/tests/web` (run one at a time). Last full web run: all pass.

Lessons: action names in the global handler map must be unique across web/*.js (two clashes found); icon keys must exist in icons3d.js.

Not verified on real Supabase / phone / GitHub Actions / fingerprint device. Owner setup still open: accounting start date + opening balances, grants, tier discounts, backup+Gmail secrets (OPS_SETUP.md), AI stays local (llm_proxy not deployed).
Owner style: phone only, Bangla/Bng-Eng, short honest replies, only pastes SQL, I do all pushes.
