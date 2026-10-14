# HANDOFF 6 — start here in the next session

Language: owner talks Bangla (phone only, short answers, MCQ for decisions). All backend/dev work and docs in English. Report format: short; "done end-to-end + next specific task". No scripts/terminal asks to the owner. Never put secrets or real person names in the repo. Never rewrite existing UI texts; new strings: English mode ALL English, Bangla mode keeps common words English written in Bangla letters, Bng/Eng mix uses Latin letters.

## Repos and branches
- Work repo: mistybari99/My-tools. Integration branch: `integration/p72-p79` (holds everything merged). Default branch `ccr-78d03e25-k7ksyo` was fast-forwarded to phase 79 only; later work lives on integration. Local worktrees were under /home/user/wt-* (ephemeral; re-create from origin).
- Public site repo: mistybari99/islamia-bos-app (GitHub Pages root = repo root). Web deploy = copy `web/` via the bundle script (scratchpad make_bundle.sh, NOT in repo — see docs/backend/DEVELOPER_RUNBOOK.md for the steps; it adds ?v=<build> to every local script/css, bumps sw.js VERSION, keeps config.js, setup-*.html, audit-a.html, PUBLISH_NOTES.md). Pushing to the public repo needs the owner's explicit "push/deploy" each time (classifier blocks otherwise).
- Rules file for owner rules: docs/WORK_TRACKER.md (branch docs/work-tracker) — 13 rules.

## Live state (owner's Supabase)
Installed in canonical order (docs/PASTE_ORDER.md, checked by tools/check_paste_order.py): phases 72..103. Paste pages: setup-run-1..11.html on the public site (one big Copy each, chain lock). New SQL phases always go AFTER the last installed one: next = 104..108 (see below). Never re-paste earlier phases (phase89/98/103 re-paste notes in PASTE_ORDER.md).
Web live on public site: build 1ee329c49d (Cat, Img, Opt, PBill, Q4, Pol, Kbd, Navfold, SW precache). NOT yet live: whatsnew, glass theme, errlog, coldstart, charts/dash, a11y, sec2 web fixes, wording.
Owner settings already chosen: pos_show_invoice_after_sale = always. Decisions made: acct_manual_prod_in103 stays OFF until accountant confirms; three accounting backlog switches (acct_count_adjust, acct_issue_out, acct_purchase_variance) one at a time; Bangla mode = English words in Bangla letters.

## Merged on integration, SQL NOT yet pasted by owner
- phase106 (backup coverage, docs/d4) — merged.
- phase107 (client error log + Report a problem) — merged.
Pending SQL on branches (merge, test, then build Run pages): phase104 (dashboard layouts, branch feat/dash), phase105 (security fixes #2, branch fix/phase-Sec2), phase108 (wording: label updates, branch fix/wording). Build ONE Run page per ~200 KB: Run 12 = 105,106,107,(104),(108) in numeric order; re-run tools/check_paste_order.py and update PASTE_ORDER.md; run tests/sql/run_all_sql.sh + e2e (tests/sql/e2e/run.sh both modes) first.

## Web branches pending merge/deploy
feat/dash (owner dashboard #/dashx + feat/charts library, 10 chart types), fix/phase-Sec2 web part, fix/a11y, fix/wording (re-runnable tools/apply_bangla_review.py), qa/errlog (merged), fix/coldstart (merged), feat/glass (merged), docs/h5 whatsnew (merged). After merging: re-run tests/web/run_all.sh (+ lang_all_test, order_test), rebuild bundle, owner says "push" → deploy → owner refreshes phone.

## Open results to read first (scratchpad, may be gone — regenerate if needed)
QA_COVERAGE.md, SECURITY_REVIEW(2).md, E2E_REPORT.md, PERF_REPORT.md, WEBFULL.md, CONCURRENCY_REPORT.md (tests/sql/concurrency/ on branch qa/conc), A11Y_REPORT.md, VISUAL_QA.md, docs/i18n/BANGLA_REVIEW.md. Step reports: docs/briefs_p2p3/*_REPORT.md (index: docs/briefs_p2p3/INDEX.md).

## NEW TASKS NOT STARTED (plan, in priority order)
1. **Concurrency fixes** — read tests/sql/concurrency/CONCURRENCY_REPORT.md; for each FAIL (deadlock, lost update, duplicate) write fixes as a new additive phase (>=109), recreate functions from latest body keeping bosNN tags, add tests.
2. **Performance indexes / slow paths** — read PERF_REPORT.md; ready-to-paste additive index SQL as new phase; re-measure POS paths (<300 ms) and reports (<3 s).
3. **Wording decisions** — docs/i18n/NEEDS_DECISION.md (282 items): ask the owner as short MCQs (Void vs Cancel vs Reject; Cost vs Expense; Due/Left/Waiting), then re-run tools/apply_bangla_review.py after merges.
4. **Category phase 2 (Cat2)** — items Cat left: sub-category in scan create (needs scan_* function recreation), category on labels/price tags (tpl_labels), cost board / recipe book / GRN / landed screens, server-side sub filter in stock_levels, sub-category dimension in the report builder, bulk grid column.
5. **Dashboard phase 2** — more metrics, targets (gauge/bullet need target rules), per-location layouts, share/export tile as image, owner-approved default layout per role; add to ia/whatsnew.
6. **Security leftovers** — anon sweep of the ~24 definer functions still anon-executable in the scratch DB (record_sale, resolve_exception, staff_directory...): verify live ACLs with `select * from anon_exec_audit94()` (owner runs) then revoke; CSP header (meta CSP only if proven safe; else document header); public site exposes setup-run pages (no secrets) — owner decides.
7. **Accounting review with the owner's accountant** — acct_manual_prod_in103 account choice (overhead absorbed), card settlement/stock_adjust/transit accounts (5110-5140), opening stock helper numbers; then turn switches on ONE at a time with setup_flow_check after each (docs/guide/ROLLOUT_PLAN.md).
8. **Phone-impossible / needs a computer (owner)** — deploy edge functions (scan-extract, telegram-webhook, meta-webhook, web-order) and set function secrets; Telegram bot + secret token; AI scan key; pg_cron for autopost scheduler; real printer/cash-drawer/WhatsApp tests; Supabase storage (photos) backup copy; real-phone UAT using docs/guide/UAT_CHECKLIST.md (64 checks) and send screenshots.
9. **Hygiene** — remove stale local worktrees/branches after merge (remote branch deletion needs owner OK); keep tests/web/*.png churn out of commits; superseded tests list tests/web/superseded.txt; rotate nothing (no secrets in repo).
10. **Not built by decision** — printed forms 05-3, 05-4, 10-2 are never auto-changed; #16 PIN postponed; landed cost is built (phase97) but OFF by default.

## How to work (what worked)
Parallel agents each in their own git worktree/branch from integration, new files only, tagged `bosNN` minimal edits, additive paste-twice-safe SQL with guards, tests before/after, 3-part reports (verified / read-only / unverified) in docs/briefs_p2p3/step_*_REPORT.md, lead merges one by one (conflicts only in web/index.html script list and web/ia.js rec list: union both sides; script tests/…/res.py pattern), runs conflict-marker grep + node --check, pushes integration. Postgres 16 scratch: socket /tmp port 5544 (restart: su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg5544 -o '-p 5544 -k /tmp' -l /tmp/pg5544.log start"); build with tests/sql/final_build.sh; run all with tests/sql/run_all_sql.sh and tests/web/run_all.sh (baseline files: tests/sql/baseline_fails.txt, tests/web/superseded.txt).
