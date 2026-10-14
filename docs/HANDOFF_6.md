# HANDOFF 6 — start here in the next session

Language: owner talks Bangla (phone only, short answers, MCQ for decisions). All backend/dev work and docs in English. Report format: short; "done end-to-end + next specific task". No scripts/terminal asks to the owner. Never put secrets or real person names in the repo. Never rewrite existing UI texts; new strings: English mode ALL English, Bangla mode keeps common words English written in Bangla letters, Bng/Eng mix uses Latin letters.

## Repos and branches
- Work repo: mistybari99/My-tools. Integration branch: `integration/p72-p79` (holds everything merged). Default branch `ccr-78d03e25-k7ksyo` was fast-forwarded to phase 79 only; later work lives on integration. Local worktrees were under /home/user/wt-* (ephemeral; re-create from origin).
- Public site repo: mistybari99/islamia-bos-app (GitHub Pages root = repo root). Web deploy = copy `web/` via the bundle script (scratchpad make_bundle.sh, NOT in repo — see docs/backend/DEVELOPER_RUNBOOK.md for the steps; it adds ?v=<build> to every local script/css, bumps sw.js VERSION, keeps config.js, setup-*.html, audit-a.html, PUBLISH_NOTES.md). Pushing to the public repo needs the owner's explicit "push/deploy" each time (classifier blocks otherwise).
- Rules file for owner rules: docs/WORK_TRACKER.md (branch docs/work-tracker) — 13 rules.
- Fix-batch branches (work repo, cut from integration): `impl/b1` .. `impl/b5`, and `impl/b6` (this handoff + audit summary). See "Fix batches in progress" below.

## Live state (owner's Supabase)
- SQL: phases 72..111 installed in canonical order (docs/PASTE_ORDER.md, checked by tools/check_paste_order.py). Paste pages: setup-run-1..11.html on the public site (one big Copy each, chain lock). New SQL phases always go AFTER the last installed one, i.e. next = 112 onward. Never re-paste earlier phases (phase89/98/103 re-paste notes in PASTE_ORDER.md).
- Web: build d92f6e1bd3 is live on the public site.
- Performance: branch `perf/webload` (web speed fix) is in progress; not yet merged.
- Audits: five audits are done, reports in docs/audit2/ (A1..A5). Summary for the owner: docs/audit2/SUMMARY.md. Each audit's gap list is the input for the fix batches below.
- Owner settings already chosen: pos_show_invoice_after_sale = always. Decisions made: acct_manual_prod_in103 stays OFF until accountant confirms; three accounting backlog switches (acct_count_adjust, acct_issue_out, acct_purchase_variance) one at a time; Bangla mode = English words in Bangla letters.

## Fix batches in progress (from the audits)
Each batch is a branch; SQL phases are additive and must be numbered after 111.
- impl/b1 — phases 112-113: profit and books (gaps from A3 real profit and A4 cash/accounting reconciliation).
- impl/b2 — phases 114-115: stock safety (movement gaps from A2 sales-to-stock and A5 factory-to-branch).
- impl/b3 — phases 116-117: manufacturing cost (gaps from A1).
- impl/b4 — phase 118: reconciliation reports (new report screens and statements).
- impl/b5 — audit regression harness (turns the audit scenarios into repeatable tests).
- impl/b6 — this docs refresh and docs/audit2/SUMMARY.md (docs only).
Check each batch's branch for its current state before starting work on it. Do not renumber phases already claimed above.

## Open results to read first (scratchpad, may be gone — regenerate if needed)
QA_COVERAGE.md, SECURITY_REVIEW(2).md, E2E_REPORT.md, PERF_REPORT.md, WEBFULL.md, CONCURRENCY_REPORT.md (tests/sql/concurrency/ on branch qa/conc), A11Y_REPORT.md, VISUAL_QA.md, docs/i18n/BANGLA_REVIEW.md. Step reports: docs/briefs_p2p3/*_REPORT.md (index: docs/briefs_p2p3/INDEX.md). Audit reports: docs/audit2/A1_manufacturing_cost.md, A2_sales_stock_reconciliation.md, A3_real_profit.md, A4_cash_accounting_reconciliation.md, A5_factory_branch_reconciliation.md.

## Web branches pending merge/deploy
feat/dash (owner dashboard #/dashx + feat/charts library, 10 chart types), fix/phase-Sec2 web part, fix/a11y, fix/wording (re-runnable tools/apply_bangla_review.py), perf/webload (web speed fix, in progress). Already merged: qa/errlog, fix/coldstart, feat/glass, docs/h5 whatsnew. After merging: re-run tests/web/run_all.sh (+ lang_all_test, order_test), rebuild bundle, owner says "push" → deploy → owner refreshes phone.

## Pending tasks (priority order, carried over from the previous handoff)
Status note: phases 109-111 are installed. Before starting items 1 and 2, check whether those phases already cover them.
1. **Concurrency fixes** — read tests/sql/concurrency/CONCURRENCY_REPORT.md; for each FAIL (deadlock, lost update, duplicate) write fixes as a new additive phase (>=112, after the last installed one), recreate functions from latest body keeping bosNN tags, add tests.
2. **Performance indexes / slow paths** — read PERF_REPORT.md; ready-to-paste additive index SQL as new phase; re-measure POS paths (<300 ms) and reports (<3 s).
3. **Wording decisions** — docs/i18n/NEEDS_DECISION.md (282 items): ask the owner as short MCQs (Void vs Cancel vs Reject; Cost vs Expense; Due/Left/Waiting), then re-run tools/apply_bangla_review.py after merges.
4. **Category phase 2 (Cat2)** — items Cat left: sub-category in scan create (needs scan_* function recreation), category on labels/price tags (tpl_labels), cost board / recipe book / GRN / landed screens, server-side sub filter in stock_levels, sub-category dimension in the report builder, bulk grid column.
5. **Dashboard phase 2** — more metrics, targets (gauge/bullet need target rules), per-location layouts, share/export tile as image, owner-approved default layout per role; add to ia/whatsnew.
6. **Security leftovers** — anon sweep of the ~24 definer functions still anon-executable in the scratch DB (record_sale, resolve_exception, staff_directory...): verify live ACLs with `select * from anon_exec_audit94()` (owner runs) then revoke; CSP header (meta CSP only if proven safe; else document header); public site exposes setup-run pages (no secrets) — owner decides.
7. **Accounting review with the owner's accountant** — acct_manual_prod_in103 account choice (overhead absorbed), card settlement/stock_adjust/transit accounts (5110-5140), opening stock helper numbers; then turn switches on ONE at a time with setup_flow_check after each (docs/guide/ROLLOUT_PLAN.md).
8. **Phone-impossible / needs a computer (owner)** — deploy edge functions (scan-extract, telegram-webhook, meta-webhook, web-order) and set function secrets; Telegram bot + secret token; AI scan key; pg_cron for autopost scheduler; real printer/cash-drawer/WhatsApp tests; Supabase storage (photos) backup copy; real-phone UAT using docs/guide/UAT_CHECKLIST.md (64 checks) and send screenshots.
9. **Hygiene** — remove stale local worktrees/branches after merge (remote branch deletion needs owner OK); keep tests/web/*.png churn out of commits; superseded tests list tests/web/superseded.txt; rotate nothing (no secrets in repo).
10. **Not built by decision** — printed forms 05-3, 05-4, 10-2 are never auto-changed; #16 PIN postponed; landed cost is built (phase97) but OFF by default.

## How to work — reminders (from this file)
- Talk to the owner in short answers, phone-friendly, MCQ for decisions; no scripts or terminal steps for the owner.
- Report format: "done end-to-end + next specific task"; 3-part reports (verified / read-only / unverified) in docs/briefs_p2p3/step_*_REPORT.md.
- Never put secrets or real person names in the repo. Never rewrite existing UI texts.
- New strings: English mode all English; Bangla mode keeps common words in Bangla letters; Bng/Eng mix uses Latin letters.
- SQL is additive and paste-twice-safe with guards. New phases go after the last installed one. Never re-paste earlier phases.
- Build ONE Run page per ~200 KB; re-run tools/check_paste_order.py and update docs/PASTE_ORDER.md.
- Public site: push/deploy only on the owner's explicit "push" or "deploy" each time.
- Parallel agents each work in their own git worktree/branch from integration, new files only, tagged `bosNN` minimal edits.
- Lead merges one by one. Conflicts only in web/index.html script list and web/ia.js rec list: union both sides.
- Before pushing: conflict-marker grep + node --check; run tests/sql/run_all_sql.sh and tests/web/run_all.sh (baseline: tests/sql/baseline_fails.txt, tests/web/superseded.txt).
- Postgres 16 scratch: socket /tmp port 5544 (restart: su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg5544 -o '-p 5544 -k /tmp' -l /tmp/pg5544.log start"); build with tests/sql/final_build.sh.
