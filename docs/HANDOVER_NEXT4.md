# HANDOVER NEXT4 - full app handover (read first in a new session)
> **NOTE (added at merge time, 2026-10-25):** this file describes the state at the end of the audit/fix session (last phase 121, branch tip 1298b58). The same branch later received other sessions' work: phases 122-135 (Group ERP stages: org scope switch `org_scope_on`, master data and permissions kept apart per business, one profile per business, create places of a business from the app), reports phase 131, integration 8, setup pages up to run 21. That work is NOT described or verified here - read the newest HANDOVER/REMAINING/TODO files on the branch and `git log` for it before acting. Sections 1-4 below are still correct for phases 72-121; the canonical paste order now continues past 121 (see docs/PASTE_ORDER.md).

Date written: 2026-10-25. Supersedes nothing: HANDOVER_6.md has the detailed phase/test lists, HANDOFF_6.md has how-to-work rules; this file is the one-stop overview.
Owner style: Bangla, phone only, short answers, MCQ for decisions. Backend, code and docs in English. Never put secrets or real person names in the repo. Never rewrite existing UI texts.

## 1. What the app is - main claim and feature list
**Islamia BOS** = Business Operating System for a sweets/bakery business (showrooms, a factory, godown/hub, online). Supabase (Postgres, RLS, RPC) backend + plain-JavaScript PWA front end (no build step for source; `tools/build_web.sh` makes the minified dist). Phone-first, Bangla/English/mixed labels, offline POS queue.
Core promise: one source of truth for sales, stock, production cost, cash and books, with strict controls (cost secrecy, per-location rights, audit trail, idempotent writes), where every new rule is an ON/OFF switch whose default keeps today's behaviour.
Feature areas (all built unless marked):
- **POS and sales**: cash/card/credit, returns, voids, invoice after sale, offline queue, 1369-item catalog with category picker, cash drawer option, item photos on/off.
- **Stock**: locations (showroom/factory/godown/hub/online), ledger + batches/expiry, transfers with in-transit/short/late-receive/marked return, counts, opening stock, wastage, units/conversions.
- **Purchasing**: purchase bills + print, GRN, landed cost (built, OFF by default), supplier refunds.
- **Production and costing**: recipes/BOM, production runs on actual yield, overhead pools and drivers, cost attribution to places, standard-vs-actual variance, semi-finished ingredients, re-price/re-cost tools.
- **Accounting**: double-entry journal, auto-posting from documents, period lock, bank statement matching, card settlement, day book, trial balance, `inventory_vs_gl`.
- **Reports and dashboards**: ~65 reports, report builder, owner dashboard with 36 metrics and 10 chart types (drag/drop), Liquid Glass theme, reconciliation statements (stock, factory-to-branch, net profit per branch/product).
- **People and controls**: staff ID+PIN, grants matrix (`has_grant`, `can_do`, `can_loc`), approvals, emergency requests, audit log, client error log, backup coverage check.
- **Channels**: inbox, web order form, webhooks, Telegram/WhatsApp links (edge functions NOT deployed yet), AI scan of invoices (key NOT set).
- **Templates**: 120 print/export templates (tpl_* system), printed forms 05-3, 05-4, 10-2 never auto-changed.
- **Setup advisor** (`setup_rec_defs81`), what's-new screen, UAT checklist.

## 2. Progress - done / remaining
DONE (detail and test numbers in HANDOVER_6.md):
- Phases 72..111 (ledger/COGS truth, recipes+costing, channels, shadow paths, security, backup, concurrency, perf indexes) installed on the owner's database.
- This session: five audits (docs/audit2/A1..A5) then fix batches: phases 112-113 (profit and books truth), 114-115 (stock safety), 116-117 (manufacturing cost), 118 (reconciliation reports + screens), 121 (security fixes). Owner pasted setup-run-15; check showed 8/8 phases done. All 29 new switches are OFF.
- Web build `1a9e6c6b70` pushed to the public repo `main` (0d0b14c): load-speed fix (Home 15.5 s -> 3.5 s on throttled laptop; POS 1369 items 3.4 s -> 0.66 s, loading states), cost screens, transfer challan/return, reconciliation screens.
- Verification: with the 29 switches ON, 35 audit gaps PASS; at defaults 5 PASS (docs/audit2/VERIFY_STATUS.md). Merged tip: SQL 8379 pass / 49 baseline fails, e2e 206/0 + 207/0, concurrency 236/0.
REMAINING (full list in HANDOVER_6.md PENDING P1-P8):
1. Merge branch `impl/c4` = phase120 (report speed; tested 38/0, 621 outputs identical), renumber after 118, build setup-run-16, owner paste on explicit "push".
2. Switch roll-out one at a time with the accountant (docs/guide/AUDIT_SWITCHES.md), UAT checks 65-94.
3. Remaining audit gaps (A1 G5/G9/G11-G14, A2 G7/G10-G15, A3 G7/G11-G17, A4 G02/G06/G07/G09-G20, A5 GAP-5/7/11-13) and 23 gaps with no machine probe.
4. Older backlog: wording decisions (docs/i18n/NEEDS_DECISION.md), Category phase 2, dashboard phase 2, security leftovers (`anon_exec_audit94()` on live), accounting review, year-view report speed (5-7 s), hygiene (stale worktrees/branches).
5. Owner/phone-only: edge function deploy, Telegram bot, AI scan key, pg_cron, printer/cash drawer/WhatsApp tests, storage backup, data entry (prices, units, Bangla category names).

## 3. Open problems and decisions
Open problems / unverified:
- Nothing verified on a real phone; speed numbers are from a throttled laptop. The public Pages URLs could not be fetched from the build sandbox, so the live build id was not confirmed by us (owner only reported pasting run 15).
- SQL suites phase16 (7 fails), phase18 (1), phase21 (17), phase21b (17) fail on the merged tip and on the previous tip; probable clock cause, not proven; `baseline_fails.txt` not updated for them.
- Web tests navfold, dashx, ownerboard, nav_b, allforms fail in the sandbox also on base; a11y_test/errlog_test fail 4 assertions on the minified bundle; full tests/web/run_all.sh never completed.
- Accounting effects of new postings (5800 cash short, 5810 bank fee, 4900 interest, 2400 overhead pool, transit loss) not reviewed by an accountant.
- Switch conflicts: `transit_short_mode=loss` blocks `stock_receive_more`; `transfer_needs_stock` blocks over-sending; salary sheet 02-2 without month/year is double counted next to payroll-app payments.
- CSP: the earlier CSP meta serialized 110 script loads; perf branch handled it its own way. Re-check CSP on a real phone before calling it done.
- Disk in the build sandbox is nearly full; scratch Postgres logs grow fast (truncate /tmp/pg5544.log).
Decisions already taken (do not re-ask): all new behaviour defaults OFF/today's behaviour; additive paste-twice-safe migrations only; public repo push only on owner's explicit "push"; `acct_manual_prod_in103` stays OFF until the accountant confirms; landed cost OFF; printed forms 05-3/05-4/10-2 never auto-changed; PIN item #16 postponed; owner chose "defaults as before, switch on one by one".
Decisions still open (ask owner as short MCQs): which switch to turn on first; whether to build the risky gaps (combo/kit, by-products, several bank accounts, VAT journal, partner profit-share base); the 3 wording items about "cancel/void"; group-ERP direction (below).
Multi-business plan (decided in another chat): several separate businesses (sweets/bakery, dealership, hardware+paint, tech, construction, online), each own licence/books/data, one owner, one Mother ERP + master dashboard. The sweets system stays ONE business and is not rebuilt. Keep all new work location/business scoped, nothing hardcoded. Impact list is in HANDOVER_6.md ("MULTI-BUSINESS PLAN"). Blueprint: docs/GROUP_ERP_STAGE_A.md on PR #3 (do not edit).

## 4. Repos, branches, Supabase, URLs
- **Work repo**: https://github.com/mistybari99/My-tools . **Designated branch**: `ccr-9c1f9be7-3s9qnz` (= `int/audit-fixes`), last commit `1298b58` ("docs: HANDOVER_6, REMAINING and TODO ..."). **Draft PR #4** (https://github.com/mistybari99/My-tools/pull/4), base `ccr-78d03e25-k7ksyo` (default branch, fast-forwarded only to phase 79; most work lives on `integration/p72-p79` and the branches below). PR #2 (`ccr-9ef9353a-q2wsec`, ERP audit roadmap) and PR #3 (`ccr-46b26d91-81vl9s`, Group ERP Stage A) belong to other chats - do not touch.
- **Feature/support branches** (all pushed, private repo): `impl/b1`..`impl/b6`, `impl/c1`, `impl/c2`, `impl/c4` (phase120, NOT merged), `impl/c5`, `impl/e1`, `audit/a1`..`audit/a5`, `perf/webload`. Already merged into the designated branch: all except `impl/c4`. Remote branch deletion needs owner OK.
- **Public web repo**: https://github.com/mistybari99/islamia-bos-app (GitHub Pages root = repo root). `main` = `0d0b14c`, build `1a9e6c6b70`. Protected, never overwrite: `config.js`, `audit-a.html`, `make_bundle.sh`. Publish with `tools/build_web.sh --to <checkout>`; notes in its PUBLISH_NOTES.md.
- **URLs**: app https://mistybari99.github.io/islamia-bos-app/ (open once with `?v=1a9e6c6b70`); SQL paste pages `setup-run-1.html` .. `setup-run-15.html` at the same base (run 15 = phases 112-118 and 121); `setup-sql.html` links them. Chain lock inside the pages; each page has a read-only CHECK button; combined check SQL: docs/CHECK_RUNS_11_14.sql and docs/CHECK_RUNS_15.sql.
- **Supabase**: the app's real project URL/anon key live only in the public repo `config.js` (protected, owner-managed; the repo docs only contain the placeholder `https://xxxx.supabase.co`). The Supabase connector in the 2026-10-25 session listed exactly one project: name `IMG-ERP`, ref `bammboumqbbdfhspmear`, region ap-southeast-2, Postgres 17, ACTIVE_HEALTHY, created 2026-10-24. **Not verified** that this is the project that holds phases 72..121 (it was created the day after most of this work); it may be the new group-ERP project. Confirm with the owner before running anything against it. No query was run against it.
- **Order of SQL**: docs/PASTE_ORDER.md (rows 1-48), tools/check_paste_order.py; canonical tail ...111,112..118,121 (phase119 = test only; phase120 pending). After re-pasting 89/94/96/97/98/103/105/109/110/111, paste 112..118 and 121 again (89 and 96 need 89,103,105,109,110,111 first).
- **Local tooling**: scratch Postgres 16 socket /tmp port 5544 (restart: `su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg5544 -o '-p 5544 -k /tmp' -l /tmp/pg5544.log start"`); `tests/sql/final_build.sh <db>`, `tests/sql/run_all_sql.sh`, `tests/sql/e2e/run.sh` (def/rec), `tests/sql/concurrency/run_all.sh`, `tests/sql/audit2/run_all.sh --matrix`, `tests/web/run_all.sh`. Keep `tests/web/*.png` out of commits.

## Continue prompt
"Read docs/HANDOVER_NEXT4.md, docs/HANDOVER_6.md and docs/HANDOFF_6.md on branch ccr-9c1f9be7-3s9qnz of mistybari99/My-tools. Do not start new features. First confirm with me which Supabase project is the live one, then continue PENDING P1 (merge impl/c4 = phase120, renumber after 118, run all checks, build setup-run-16, wait for my explicit 'push'). Owner talks Bangla, short MCQs; docs and code in English; everything location/business scoped."
