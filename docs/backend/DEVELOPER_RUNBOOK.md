# Developer runbook

Sources: `docs/PASTE_ORDER.md`, `docs/briefs_p2p3/COMMON.md` and the step reports, `tests/README_RUN.md`, `tests/web/README_TESTS.md`, `tests/sql/*.sh`, `docs/HANDOVER_*.md`. Environment facts that are not in the repo are marked **UNKNOWN**.

## 0. Ground rules (do not break)
* The owner works from a phone and pastes SQL himself. An agent can **never** run SQL on the live database (the sandbox cannot reach Supabase). Everything is built and tested on a scratch Postgres 16 (socket `/tmp`, port `5544`, user `postgres`; env `PGSOCK`, `PGPORT`). Use scratch database names that start with your phase/step id and drop them afterwards.
* No `service_role` key, no password, no token, no real person's name in any file, test, report or chat. Test data are invented (`owner1@s.app` style).
* Do not edit an old phase file or an old test. Add a new phase, or a `phaseNNb_test.sql` copy when an old assertion became false *by design*.
* Defaults equal today's behaviour; a new switch is OFF/empty; the app only *recommends* (setup advisor).
* Every user-visible string exists in bn / mix / en (`B.L`); English mode contains no Bangla letters (`lang_en_test`).

## 1. How to add a phase safely (SQL)

### 1.1 Checklist
1. **Find the last file of the chain.** Today it is `phase103.sql` (see `docs/PASTE_ORDER.md` section G). Your phase number must be new (next free number above the highest existing file; parallel branches pick their own - check `git branch -a` and the PASTE_ORDER table first). Branch from `integration/p72-p79`.
2. **Write `supabase/phaseNNN.sql`** with this shape (copy the header style from `phase99.sql` / `phase103.sql`):
   * Header comment: what is added, which phases it needs, "Additive, paste-twice safe", every switch and its default, the tag `bosNNN`, what is NOT done.
   * **Guard block** at the top: `do $g$ ... raise exception 'phaseNNN needs phases ... pasted first (see docs/PASTE_ORDER.md); missing:%', miss; ...` - one marker object per prerequisite phase (`to_regprocedure(...)`/`to_regclass(...)`), plus `position('bos98' in pg_get_functiondef(...))` checks when you rely on a merged body.
   * Rules/grants as inserts with `on conflict do nothing` (labels in bn, mix, en; `sort` number; kind switch/number/choice/text; default OFF).
   * Tables with `create table if not exists`, RLS enabled, `revoke all ... from public, anon, authenticated` then `grant select` only on what the browser may read; append-only tables get a trigger (copy `_append_only23`).
   * Functions: `create or replace function ... security definer set search_path = public`; first lines `is_active()` -> `can_loc()` -> `has_grant()`/`is_owner()`; a `p_client uuid` for anything that creates a record; `revoke all on function ... from public, anon; grant execute ... to authenticated;`.
   * Advisor rows (`setup_rec_defs81`, `ON CONFLICT DO NOTHING`) so the guide can recommend your switches (or add them to the next phase101-style file).
3. **Re-creating an existing function? Use the LATEST body rule (1.2).**
4. **Write `supabase/phaseNNN_test.sql`** (scaffold: copy the top 20 lines of `phase51_test.sql` - schema `tt`, `tt.chk(name, ok)`, `tt.err(name, sql, msg)`, `tt.as(uuid)`; insert test users/roles/`user_locations`; end with a line that prints `RESULT <n> pass, <m> fail`, which `run_all_sql.sh` parses). Include a "paste twice = identical function bodies (md5 of `pg_get_functiondef`)" check and a test that fails on a database built WITHOUT your phase (every defect/feature has a failing-before assertion - see phase94/103 reports).
5. **Build and test** (section 3): fresh build -> your suite -> paste your file a second time (no error) -> regression suites of every function you touched.
6. **Update `docs/PASTE_ORDER.md`** (new row in table B with "needs", guard note, and the list of functions you re-create; update the "last file" statement and the rules section), **`tests/sql/baseline_fails.txt`** (a line `suite known_fails known_passes`), and write `docs/briefs_p2p3/<step>_REPORT.md` (<= 60 lines: what was built per gap, switches and defaults, test counts, regression, ia.js lines, honest "NOT done / UNVERIFIED").
7. **Web part (if any):** new file `web/<name>.js` (IIFE, `const A = window.BOS_APP, B = window.BOS;`, handlers on `A.H` with a unique `data-act` prefix, `BOS.ui.state`), one `rec(...)` line in `web/ia.js`, one `<script>` tag in `web/index.html` after the files it uses, a `tests/web/<name>_test.js` using `_paths.js`. Run `node --check`, `ia_test`, `order_test`, `lang_en_test`.
8. **Commit** one logical step per commit; never force-push shared branches.

### 1.2 Latest-body rule (`pg_get_functiondef` with `bosNN` tags)
Why: `create or replace` replaces the whole body. If you copy a function from an old file you erase every change that later phases made. The history of this repo (phases 79, 89, 98, 103 are pure merges) shows what happens otherwise.
Procedure:
1. Build a fresh DB through the canonical order (`bash tests/sql/final_build.sh db "<order>"`).
2. For each function you must change: `select pg_get_functiondef('public.fn(argtypes)'::regprocedure);` - this is the LATEST body. Also record its `security definer`, volatility, `search_path`, and ACL (`\df+`, `has_function_privilege`).
3. Change only your lines and mark each with a comment containing your tag (`-- bos104`). **Keep every older `bosNN` tag.** Keep the signature; if you must change it, drop the old overload explicitly (as phase94 did) - two overloads make calls ambiguous.
4. If the function is already in a merge file (phase89 list, phase98 `_acct_docs` family, phase103's 20 functions), **merge your lines into the last merge file** (a new version of it) instead of creating a competing copy; PASTE_ORDER section G lists them (`_acct_docs`, `inventory_vs_gl`, `recipe_cost`, `_setup_chk81`, `setup_recommendations`, `setup_recommend_apply`, `inbox_list`, `customer_directory`, `find_customer`, `_acct_stock_moves85`, `_cw_*96`, `_ob_*96`, `opening_stock_apply96`, `_inb_pii_*99`, `online_order(s)_get/list`).
5. Add a **BODY GUARD** like `phase96/98/103`: stop the paste if the live body carries a tag your file does not know (it is newer than you) and set a session flag so the `create or replace` blocks run only when both guards passed.
6. Verify: for every public function, store `md5(pg_get_functiondef)` + the sorted `bosNN` tags before and after your phase. Only the functions you intended may change; tags may only be added. Check ACL/security definer/volatility/search_path unchanged. Second paste: zero changes. (This is the method of `step_INT3_REPORT.md`; the generator `tests/sql/gen_phase96.py` + `tests/sql/phase96_parts/` shows how a big file was produced from a built database.)
7. Run the tag tests: `phase89c_test` (+ `phase89d/e`), `phase94_test`, `phase96_test`, `phase98_test` (+ `98b`), `phase99_test`, `phase101_test`, `phase103_test`. A lost tag shows up as FAIL.

### 1.3 Paste order and the "last file" invariant
* Canonical order is only what `docs/PASTE_ORDER.md` lists: foundation (never re-paste) then 72..88, 90, 91, **89**, 92, 93, 95, **94**, 96, 97, **98**, 99, 100, 101, [102], **103 last**. Any other order is untested.
* If you ever paste phase89, 94, 96, 97, 98 or 99 again, paste phase98 (only after 89/94/96/97) and then phase103 again.
* Never paste phase21 after 24, phase40/`ALL_NEW10` after 85, phase76 after 94.
* `run_all_sql.sh` builds the order from the PASTE_ORDER table rows (`| N | phaseNN.sql`) and **appends any `phase1NN.sql` that is not in the table** in numeric order. Consequence (read from the script): the unnumbered row "(31) phase102" is not matched, so 102 is appended after 103 in that build - harmless because 102 re-creates no function. Give a new phase a numbered row.

## 2. Public paste page and web publishing

What the repo says (HANDOVER_2/3, DECISIONS):
* The web app is static (`web/`, no build step). It is hosted on free static hosting from a **separate PUBLIC repository** that holds only a copy of `web/` (no secrets: `web/config.js` has only the public project URL and publishable key; no cost data). The private repo keeps schema, data and docs. Cost prices must never reach the public repo.
* Publish steps recorded in `docs/HANDOVER_3.md`: run `python3 tools/build_kb.py` (rebuilds the assistant knowledge `web/data/kb.json`); copy the `web/` files (except the temporary paste page) into the public repo; commit; push to its main branch. Bump `VERSION` in `web/sw.js` when script names/order change (see TROUBLESHOOTING section 6).
* **Public one-paste SQL page (`setup-sql.html`):** a temporary page in the public repo whose script has a single line `const SQL=` holding the SQL to paste, so the owner can copy it on a phone. Recorded method (`docs/HANDOVER_2.md`): build the SQL (a bundle of the phase files in PASTE_ORDER order, e.g. `ALL_NEW<n>.sql`), test it on a database at the owner's current state, replace that one line using Python `json.dumps` and escape `</` as `<\/`, commit, push. The roadmap flags that this page exposes the SQL logic publicly (no secrets or costs found) and says to delete it when no longer needed (`docs/ERP_AUDIT_ROADMAP.md`).
* **The helper scripts used for this (`make_bundle`, `pages` scripts) live in an agent scratchpad and are NOT in this repository** - their names, location and exact options are UNKNOWN here. Reproduce the steps: (1) take the ordered list from PASTE_ORDER section B, (2) concatenate only files the owner has not pasted yet (never the foundation list), (3) split into parts small enough for a phone paste (HANDOVER_3 mentions 6 parts "in order 1..6"), (4) embed with `json.dumps`, (5) test that the bundle builds on the scratch DB from the owner's state, (6) publish. Phases after 48-51 were **not** rebuilt into the page as of `HANDOVER_5.md`.
* The page publishes SQL for the owner to paste; it never carries secrets, and no agent may paste for him.

## 3. How to run the tests

### 3.1 SQL (`tests/sql`, doc: `tests/README_RUN.md`)
```
# scratch Postgres 16 must be running on /tmp:5544  (see COMMON.md for the pg_ctl line; never a live database)
bash tests/sql/run_all_sql.sh                       # build final DB per PASTE_ORDER, run every supabase/*_test.sql on its own clone, compare with baseline_fails.txt
bash tests/sql/run_all_sql.sh phase8 phase72 phase89c phase99 phase103   # only some suites
TEMPLATE=<db> bash tests/sql/run_all_sql.sh ...      # reuse an already built final db
KEEP=1  TIMEOUT=600  LOGDIR=<dir>  REPO=<checkout>   # options
bash tests/sql/final_build.sh <db> "<order>"         # build only (default order ends at phase98; run_all_sql passes the full order)
bash tests/sql/img_build.sh <db>                     # final order + 99, 101, 102
bash tests/sql/build_fresh_db.sh <db> ...            # older builder used by early phases (foundation list)
psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phaseNNN_test.sql | grep -E 'FAIL|RESULT'
```
Exit code 0 only if every suite equals `tests/sql/baseline_fails.txt` (columns: suite, known fails, known passes). Change a baseline number in the same commit as the fix. Known fails are listed per report (INT3: 22; after E2E 31 fails in total, all understood).
Other SQL scripts: `tests/sql/final_sweep.sql` (unbalanced entries, trial-balance difference, cache mismatches, negative stock - run after each suite in the regression method), `tests/sql/e2e/run.sh <rec|def> <db> files...` (independent end-to-end run, files `00_common` ... `11_extra`; `rec` = recommended switch values, `def` = defaults; the E2E report expects 0 FAIL in both), `tests/sql/p9/run_regress.sh` (phase-9 report outputs diffed between a phase-9 DB and a full DB), `tests/sql/p14_conc.sh` (concurrency), `tests/sql/phase101_run.sh`, `tests/sql/opt_build.sh`.

### 3.2 Web (`tests/web`, docs: `tests/README_RUN.md`, `tests/web/README_TESTS.md`)
```
node tests/web/pos2b_test.js                 # one test (jsdom/Playwright style; argument optional)
WEB_DIR=/path/to/web node tests/web/ia_test.js
bash tests/web/run_all.sh [name-filter]       # one at a time, 300 s each (env TIMEOUT, WEB_DIR, PORT), summary table, exit 1 on any non-zero exit
RUN_SUPERSEDED=1 bash tests/web/run_all.sh    # include the tests listed in tests/web/superseded.txt
```
* New tests: `const _P = require('./_paths');` then `_P.WEB_DIR`, `_P.freePort()`; never hard-code a path or port. Run **one test at a time** (shared ports/browsers).
* `order_test.js` asserts script order/uniqueness and that every non-soon IA route has a page handler; `ia_test`, `lang_en_test` (0 Bangla letters in English mode), `nav_b_test` are the structural checks.
* Superseded tests (brittle "X is the LAST script" assertions) are skipped by default; their maintained replacements are listed in `README_TESTS.md`.
* Browser tests use Playwright. `smoke.js` loads it from `/opt/node22/lib/node_modules/playwright` and needs `BOS_REPO_DIR`; availability on another machine is **UNKNOWN**. No test ran on a real phone or against a real Supabase (every step report says so).

### 3.3 Python and ops
`python3 tests/py/test_item_import.py` (needs the scratch Postgres for part 4); `python3 -m unittest tools/test_ops.py -v`, `tools/test_restore_drill.py`, `tools/test_fingerprint_bridge.py` (fake local Supabase, no network, no secrets). Edge functions are only syntax-checked as TypeScript (no Deno run, no provider calls) - treat them as untested until deployed.

### 3.4 Definition of done for a phase
New suite 0 fail; paste twice error-free and body-identical; old suites equal baseline; tag tests green; `final_sweep.sql` clean; web `run_all.sh` exit 0 for the files you touched; report written with honest NOT-done list; PASTE_ORDER + baseline updated.

## 4. How to deploy

| What | Who / how |
|---|---|
| SQL | The owner pastes whole files in the Supabase SQL editor, in PASTE_ORDER order, each once. He may run a file twice harmlessly. Tell him which file, and what to check afterwards (e.g. `select anon_exec_audit94()`). |
| Web | Copy `web/` to the public hosting repo (section 2), bump `sw.js VERSION` if needed, push. The rule `offline_cache_on` and `localStorage.bos_sw` switch the cache off on a phone. Nothing else is built. |
| Edge functions | Source only. Needs a computer + Supabase CLI: `supabase functions deploy scan-extract` (JWT verification ON) and `supabase functions deploy telegram-webhook --no-verify-jwt`; secrets via `supabase secrets set NAME=...` (names in SECURITY_MODEL.md section 8). **Paste phase94 before deploying the new scan-extract.** Setup guides: `docs/SCAN_SETUP.md`, `docs/TELEGRAM_SETUP.md`, `docs/INTEGRATIONS_P3C.md` (SMS/WhatsApp queue, payment gateway, CSV export, assistant access); the Meta / web-order / assistant-proxy edge sources are in `tools/edge/` (setup notes: step_H report, docs/ASSISTANT.md). |
| Backup / notify | `.github/workflows/backup.yml` and `notify.yml`; scheduled workflows run only from the repository default branch; secrets only as GitHub secrets (`docs/OPS_SETUP.md`). Proof of restore: `tools/restore_drill.py` then record it in the app. |
| Auth settings | Confirm-email OFF (docs/SETUP.md); MFA enabled in the dashboard (docs/TWOFA.md). |

## 5. Branch and worktree conventions (as observed)
* Integration branch: `integration/p72-p79` (holds phases 72..103 + web). Step branches are named `fix/phase-<Step>` (e.g. `fix/phase-Sec`, `fix/phase-E2E`), QA branches `qa/<topic>`, feature branches `feat/<topic>`, docs branches `docs/<name>` (this documentation: `docs/d2`). Step branches start from `integration/p72-p79` and are merged back with merge commits ("Merge remote-tracking branch 'origin/fix/phase-X' into integration/p72-p79").
* One git **worktree** per branch, as a sibling directory `/home/user/wt-<name>`; work only inside your own worktree; `git worktree list` shows them. The shared checkout directory is not used for edits.
* Parallel agents in ONE tree (older steps, `docs/briefs_p2p3/COMMON.md`) touched only their own files: `supabase/phaseNN*.sql`, `web/<name>.js`, `tests/web/<name>_test.js`, `docs/briefs_p2p3/<name>_REPORT.md`; the lead integrated `web/ia.js`, `web/index.html`, `docs/BUILD-LOG.md`, PASTE_ORDER. Keep to that when in doubt: put the exact `rec(...)` line and `<script>` tag in your report.
* Never use bare `git stash`/`pop` (the stash stack is shared across worktrees); commit work-in-progress instead. Do not commit or push unless asked.
* Commit message: short summary line of the step, e.g. `Step E2E (bos103): ...`. Docs-only branches create only new files under `docs/`.
* Keep reports honest: separate "verified (run and measured)" from "UNVERIFIED".
