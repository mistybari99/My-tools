# HANDOVER_NEXT3 — Islamia BOS full handover (read first)

Owner: phone only, Bangla/Bng-Eng, short honest replies, wants clickable options one question at a time. Owner only pastes SQL; agent does all pushes. Links given to owner: only public GitHub Pages.
Never use/ask for service_role, DB password or any secret. Never invent numbers (empty = "Data needed").

## 1. What the app is (core claim + features)
"ইসলামিয়া মিষ্টি ঘর" (ISLAMIYA MISTY GHAR) sweets/cake/bakery chain: hub + 7 locations (main, branch2, mishti_bari, al_cakes, cake_factory, mishti_factory[paused], godown). Free stack: Supabase + GitHub Pages, plain-JS no-build app.
Origin: paper BOS Build Kit (42 forms) + Business Guide. App keeps every paper form and adds faster tabs/automation. Core principle: nothing deleted; everything a setting (on/off, edit, lock, hide, delegate); 3 languages (Bangla / Bng-Eng / English).
Features built (evidence: web/ia.js 70 routes, ~146 tables, phases 2–47):
- 41 of 42 forms as JS specs in `entries.data` (0-1 = locset/locsheet screens)
- POS (split/partial pay, offline queue), customers, dues, tiers, loyalty (phase43)
- Purchase, payables, stock ledger, transfers, counts, wastage, batch/expiry
- Recipes/BOM/production, item master (1,312 items), assets register
- Accounts (phase40): CoA, journals, TB, P&L, BS, cash flow, party ledger
- Employees (41), attendance + payroll (42; fingerprint device bridge + optional app punch), partners (44)
- Owner board (45), notifications + backup (46), AI assistant local (47)
- Controls: exceptions, releases, emergency, change requests, audit log, roles/grants, 65-report engine

## 2. Progress
DONE (before this session): phases 23–28, 40–47 built + tested locally; owner ran SQL parts 1–6 (phases 40–47) on Supabase, all Success.
DONE (this session, docs only, no code/data change): full ERP audit → docs/ERP_AUDIT_ROADMAP.md (§1–13); Form Kit saved to docs/inputs/BOS-BUILD-KIT_All_Forms_v1_39.js (2984 lines, 42 forms); HANDOVER_4.md; draft PR #2.
NOT STARTED (approved scope, owner chose ALL numbers):
- P1 Foundation + duplicates: 24 payroll, 25 stock, 26 production, 27 owner top-up/draw, 28 expense guards via shadow-copy; 15 day book↔journal reconcile; 19 forms retry queue; 20 server-side form equations; first task = map Kit fields to the 41 forms
- P2 Accounts + attendance: 1 bank reconcile, 2 year-end close, 3 VAT ledger, 4 depreciation, 5 budget, 6 auto-post (payroll/advance/partner/20-x/10-x), 17 restore drill, 18 2FA, 29 attendance
- P3 Rest: 7 reorder, 8 wastage list, 9 batch on GRN, 10 QC, 11 online order, 12 20-x↔sales link, 13 benefits, 14 BI export, 21 SMS/WhatsApp, 22 payment gateway, 23 accounting export, 30 AI side tab
- 16 PIN hardening POSTPONED by owner
Order: one part at a time, ask owner before each: build → test → owner OK.

## 3. Open problems and decisions
Decisions (owner, final):
1. Payroll: app payroll entered ⇒ 02-2 form locked/hidden + hidden time-stamped shadow copy; counted once.
2. Stock/production forms vs screens: owner switch with all modes (screen-primary / form-primary / either-locked); default screen-primary, form = shadow. Never both posting.
3. Expense: day-book quick entry gets shadow copy in 10-2 at day end, one click confirm. SYSTEM-WIDE RULE: every logical path is a separate option (use one / both open / lock one) but count exactly once via shadow copy.
4. Owner top-up/draw: same switch pattern; default Partner capital primary, Cash moves shadow.
5. Attendance (29): staff self-punch in software (owner can lock per person/role); fingerprint/face registration optional; owner can grant a manager to mark others' daily attendance, rest time, closing time via device/finger/face or manual entry. "Staff attendance" vs "daily attendance" as two systems: owner's exact meaning NOT yet confirmed — ask.
   Honest limits: browser face/WebAuthn proves phone owner, not employee → evidence (photo + manager approval) only; fingerprint only via external device; GPS spoofable (soft flag).
6. AI Assistant (30): side tab; default owner only; others only by explicit grant; invisible without grant. Verify existing `assistant` route/grants first.
Open problems (details in ERP_AUDIT_ROADMAP.md §3, §7):
- HIGH duplicate risks: payroll 02-2 vs payroll_payments (phase13.sql:162 / phase42.sql:1543); stock forms vs stock2 (phase20.sql:84); 05-1 vs recipes; owner money cash_moves vs partner_capital.
- Accounting has no auto-post source for payroll, advances, partners, 20-x, 10-1/10-3/14-1 (typed manual journals meanwhile).
- PIN login weak: password `${pin}-bos`, lockout only counted by browser (web/app.js:128); owner action (Auth hook) postponed.
- Backup workflow never proven on real Supabase; restore tested at 91 of 146 tables; `token_hash` tables excluded.
- Nothing verified on real phone/printer/fingerprint device; no CI; several modules/phases without own tests.
- VAT/Mushak stays OFF (adviser rate needed). Accounting start date + opening balances not set.
- Owner setup still open: grants, tier discounts, backup/Gmail secrets (OPS_SETUP.md), AI stays local (llm_proxy not deployed).
Design rule for build: one transaction record + linked locked shadow copies (type, source_id, locked flag, created_at); posting unique on (source_type, source_id); guards/warnings when two paths could double-count. Do not silently merge/delete existing records; find suspected duplicates with read-only reports first.
Lessons: global handler action names unique across web/*.js; icon keys must exist in icons3d.js; docs/MODULE_MAP.md is stale (use web/ia.js + SQL as truth).

## 4. Repos, branches, Supabase, URLs
- PRIVATE `mistybari99/My-tools`: working branch `ccr-9ef9353a-q2wsec` (contains all work; fast-forwarded from `ccr-2f54f832-rkdi5z`). Draft PR #2 (base `ccr-2f54f832-rkdi5z`, docs only). PR #1 = `ccr-2f54f832-rkdi5z` → `ccr-78d03e25-k7ksyo`. Subscribed to PR #2 events.
- PUBLIC `mistybari99/islamia-bos-app`: web/ copy + setup-sql.html (read-only clone at /home/user/mistybari99/islamia-bos-app; to push, add_repo with access:"push").
- App URL (GitHub Pages): https://mistybari99.github.io/islamia-bos-app/ ; SQL page: https://mistybari99.github.io/islamia-bos-app/setup-sql.html
- Supabase project URL (public): https://rpqrcmesbhwtyrikabhy.supabase.co (publishable key in web/config.js; project ref `rpqrcmesbhwtyrikabhy`, free plan, Singapore). Sandbox cannot reach supabase.co → agent never runs SQL on real DB; owner pastes (backup first, quiet time). Supabase MCP tools appeared deferred this session but were NOT used and need owner authorization.
- Publish flow: `python3 tools/build_kb.py`; copy web/ (except setup-sql.html) to the public repo; commit; `git push origin main`.
- Tests: Postgres 16 on /tmp port 5544 (docs/BUILD-LOG.md); `tests/sql/build_fresh_db.sh`; web tests `node tests/web/<x>_test.js /home/user/My-tools/tests/web` (one at a time). Last full run (pre-session): all pass; not re-run this session.
- Key docs: HANDOVER_3.md, HANDOVER_4.md, ERP_AUDIT_ROADMAP.md, OPS_SETUP.md, FINGERPRINT.md, ASSISTANT.md, REMAINING.md, TODO.md, DECISIONS.md, briefs/, regs/.

## First steps in the new session
1. Read this file + ERP_AUDIT_ROADMAP.md §3, §5, §11–13 + Form Kit header.
2. Ask owner which SQL parts they have run (all 6 reported Success).
3. Start P1 task 1: Kit-vs-form field map (read-only), show owner, then build.
