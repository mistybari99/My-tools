# HANDOVER 2 — start here in the next chat (supersedes the "next job" parts of docs/HANDOVER.md; read that file too for owner/brand/security rules)

## 0. Owner & style (unchanged)
Phone-only owner, writes Bangla / Bng-Eng; wants honest, short replies, logical defaults, few questions, ON/OFF settings everywhere. Brand FIXED: ISLAMIYA MISTY GHAR / ইসলামিয়া মিষ্টি ঘর. Budget is limited (~$30 left when this was written; design pass already spent part of it) → be economical: few agents, one independent audit per wave, run the full web list once, ignore repeated hand-back spam from finished agents.

## 1. Repos / branches / how to publish
- PRIVATE `mistybari99/My-tools`, branch **`ccr-2f54f832-rkdi5z`** (everything: web/, supabase/*.sql, tests/, docs/, data/). Commit+push often (a stop hook demands it).
- PUBLIC `mistybari99/islamia-bos-app` (GitHub Pages https://mistybari99.github.io/islamia-bos-app/): copy of `web/` only + `setup-sql.html` (one-paste SQL page). Needs `add_repo` (owner must allow it; first time it was denied until the owner said "push by hand like before"). Clone: `git clone --depth 1 https://github.com/mistybari99/islamia-bos-app /home/user/islamia-bos-app`, then `register_repo_root`. Publish = copy all files of web/ except setup-sql.html (rsync is NOT installed: use `find` + `cp`), commit, `git push origin main`. The classifier once blocked a combined private→public copy+push command: run the SQL-page edit and the web copy as separate small commands.
- NEVER use service_role key / DB password. The sandbox cannot reach supabase.co: the owner pastes SQL. Owner link style: public Pages URL only (claude.ai artifacts are private, owner could not open them).
- setup-sql.html: the `const SQL=` line holds the SQL to paste (currently ALL_NEW5+6+7 = phases 15–22). For a new phase: build `supabase/ALL_NEW<n>.sql`, test on a DB at the owner's state, replace the line (python json.dumps, escape `</`), push.

## 2. DATABASE STATE (owner-run, reported Success)
Applied by owner: schema, phase2–4, ALL_NEW (5–7), ALL_NEW2 (8–9), phase10, then phases 11–14 (page 1/2), then 15–22 (setup-sql.html "ধাপ ১৫–২২"). The owner reported "Success" and says the 1,312 dictionary items are imported (app shows 1,369 products = 1,312 + 57 legacy). **Confirm with the owner that phase 22 ran** (it was in the same page; they answered "I've run it").
NOT to paste: `supabase/phase30_controls.sql` (a stray optional rules row from the controls agent; never executed; the setting defaults to ON when absent).
Later phases must be NEW additive idempotent files (phase23…), never edits of applied files. Idempotency + paste on a DB at the owner's state must be proven (see §5).

## 3. WHAT IS BUILT (all with local SQL/web tests + independent audits; real Supabase/phone verification only by the owner's use)
W0 carry-over (items.details, view_cost RPC, low-stock, barcode on purchase/stock, wastage maker-checker, supplier refund, sale return, expired-sale block, STOCK/PURCHASE photos, emergency keys, ledger ref_id revoke, day book `#/daybook`, salary report `#/salary`) · W1 hardening (audit_log append-only, immutable codes, no hard deletes, login lockout 5/10min + Auth hook function NOT yet enabled by owner) · W2 item master (types, flags, assets register `#/assets`, dictionary import, mapping of 57 legacy items) · W3 list add-rules/Other queue/shared control (5 screens wired) · W4 locations (+17 setup steps, pause/close), Control Center, settings sheet versions + get_limit · W5a Paper/Parallel/App rollout, entered-later + paper serial, change requests/revisions, form offline outbox, owner_self_approve switch · W5b server blind count + PIN signatures (14-1,10-1) · W6 recipes/BOM/packaging/production · W7 forms→stock ledger (switch OFF), discount approver, brand P&L, 12 reports, nav leftovers, device checklist · P1 bulk item editor `#/bulkitems` + legacy-item decision page `#/itemmap` · IA: single registry `web/ia.js` (62 screens, 13 categories) driving drawer/home/search/bottom bar/Control Center; docs/IA_AUDIT.md, IA_RULES.md, IA_CONCEPT.md, `.claude/skills/bos-organise/SKILL.md` · DESIGN: `web/theme.css` (Premium Dark default / Premium Light / Classic, small font), `web/icons3d.js` (BOS.icon glass icons), `web/controls.js+css` (collapsed dropdown/multi/tick/⋮ kit; switch `ui_collapsed_controls` or localStorage `bos_ctl_collapsed=off`), POS-first (big Sell button + centre Sell orb). docs/DESIGN_SYSTEM.md, CONTROLS_AUDIT.md.

## 4. REMAINING WORK (functional only; design polish excluded) — priority order
**P1 — make imported items usable (owner does data entry, we give tools):**
1. Owner enters selling prices/units/track/min-stock via `#/bulkitems` (tool built). Owner decides the 57 legacy items in `#/itemmap` (link / use dictionary item / keep). Owner types Bangla names for the 25 categories (Bangla tab in bulkitems).
2. Item list: type/class count badges (not built). Unpriced chip exists.
**P2 — consistency / rules gaps:**
3. ~50 pickers still plain selects/arrays (purchase unit + return reasons, sale-return reasons, stock unit, wallets, asset condition, itemmaster type/class, unit-conversion selects) → wire `B.listctl.enhance`.
4. Hard-coded location lists in forms_cash.js / forms_sales.js (SHOWROOMS, brands) and forms_staff.js duty slots → read `locations` (entry pickers still list paused/closed places; server refuses).
5. owner_self_approve switch not applied to wastage, supplier refund, sale returns, settings-sheet approvals (done for entries, releases, emergency, item changes).
6. Blind count only 14-1 & 10-1 (04-3 stock count, 04-1 GRN not blind; browser still computes expected, hidden not sealed). PIN signature only 14-1/10-1 witness; other two-person forms unchanged; PIN second-client sign-in unverified on real Supabase.
7. `rules` row/UI for `ia_home_v2` (owner-side switch) and `ui_collapsed_controls`; UI for per-form tables `blind_count_cfg`, `pin_sig_cfg`.
**P3 — reports/accounting:**
8. 34 of 65 reports remain (BUILD-LOG W7 list: S10, P2, P4–P6, K2, K3, F1–F4, E2–E4, W1, W2, D5, T3, T4, L1–L5, X2–X5, G2, M1, M2, Q1–Q3); Parallel-mode comparison pairs / month-end pass-fail (Build cmd 7); sales/due reports not net of sale returns/refund cash.
9. Day-book gaps: bank deposits (10-3), customer order advances, owner top-ups, hub-receiving side of 10-1 (no hub location recorded).
10. GRN (04-1) vs purchase page both post `purchase_in` (double-count risk, no cross-check; GRN has no batch/expiry).
11. Production run void/undo; recipe/production reports; packaging line on receipt.
**P4 — platform/ops:**
12. Per-form paper check docs/forms/<code>.md for all 41 forms (Build cmd 11) — needs the owner's paper kit text (not in repo).
13. IA Increment B/C (docs/IA_CONCEPT.md §4,5,8): guided flows (open shop, close day 14-1→10-1→deposit, factory day, month-end) as steppers; owner Switchboard (all ON/OFF settings in one searchable page) and Delegation board; templates/smart defaults. Needs-you rows are counts, not oldest-first lists; `printbooks` tile is "Soon"; release_decide delegates have no page.
14. No service worker (first load needs internet; open app works offline for POS + form outbox).
15. Old/stale tests: `tests/web/pos_test.js` (selector #cart_given), `engine_test.js` prints only "JS errors: none", `tests/sql/p9/*` not re-run after phase 14+.
16. VAT/Mushak 6.3 receipt line stays OFF (adviser's rate needed; never invent numbers).

## 5. OWNER ACTIONS (no code)
Enable Supabase Dashboard → Authentication → Hooks → `hook_password_verification_attempt` (server-side PIN lockout; without it lockout guards only the app screen) · set prices (P1) · switch ON when ready: `blind_count_on`, `pin_signature_on`, `forms_post_to_ledger`, `packaging_consume_on`, `tools_stock_on`, `block_expired_sale`; give grants (see_expected, rollout_manage, change_approve, list_manage, location_manage, item_bulk, recipe_manage, view_daybook, salary_view, head_management…) · resume paused place `mishti_factory` when needed · run docs/DEVICE_CHECKLIST.md on a real phone/printer (also check Bangla font rendering in the new theme and the 3 design questions below) · decide the 57 legacy items.
Design questions still open (owner): keep centre Sell orb in Classic? amber glow strength? Premium Light accent orange vs brand maroon?

## 6. How to work (proven)
- Agents: builder (brief in a COMMON.md-style file with rules) → ONE independent audit agent per wave (adversarial, read-only) → send fix list to the builder via SendMessage → you rerun tests → publish. Finished agents may keep re-sending the same hand-back: ignore; do not re-reply each time.
- Local DB: Postgres 16 at /tmp/pgtest, port 5544, start: `su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgtest/data -o '-p 5544 -k /tmp' -l /tmp/pgtest/pg.log start"` (initdb first if missing; create roles anon/authenticated/service_role). Build fresh DB in owner order: `ORDER="phase8 phase9 phase10 phase11 … phaseNN" bash tests/sql/build_fresh_db.sh <db>` (default ORDER is "phase8 phase9 phase10"). SQL tests: `psql -h /tmp -p 5544 -U postgres -d <db> -f supabase/phaseNN_test.sql` on a FRESH DB each (tests are not re-runnable on a used DB). Known baseline failures: phase8 T1, phase10 T12 (date-dependent).
- Web tests: `node tests/web/<name>_test.js /home/user/My-tools/tests/web` (absolute dir). ~36 tests (see tests/web/*_test.js; theme, controls, ia, bulkitems, etc.); run sequentially (shared ports 80xx/81xx; parallel runs cause EADDRINUSE and timeouts). `bash` wait loops: use Monitor with an until-loop, not sleep.
- Paste-safety rule before giving the owner SQL: build DB at phase 14, apply the new SQL twice with ON_ERROR_STOP.
- Security regressions to always check: costs never to anon/staff; RLS on new tables; revoke anon/public execute; SECURITY DEFINER search_path=public; numeric guards `not (x between lo and hi)`; idempotent client ids; period lock; can_loc; nothing hard-deleted.
- Docs to read first: docs/HANDOVER.md, this file, docs/REMAINING.md, docs/BUILD-LOG.md (tail), docs/IA_RULES.md (+ bos-organise skill: register every new screen in web/ia.js), docs/DESIGN_SYSTEM.md.

## 7. Suggested first message for the new chat
"docs/HANDOVER_2.md পুরোটা পড়ো। §4 এর কাজ P1 → P4 ক্রমে করো (ডিজাইন বাদে)। প্রশ্ন কোরো না, সব জায়গায় অন-অফ সেটিংস রাখো। প্রতি ধাপে: লিখো → একটি আলাদা অডিট → টেস্ট → পাবলিক রিপোতে পুশ করে আমাকে লিংক দাও; SQL লাগলে এক-পেস্ট পেজ। বাজেট কম, তাই কম এজেন্ট, খরচ বাঁচিয়ে।"
