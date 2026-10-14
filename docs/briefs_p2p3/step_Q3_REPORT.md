# Step Q3 - test infrastructure (no product code)

Branch `fix/phase-Q3` (from `integration/p72-p79`). Only `tests/` and this report changed. No live DB, no web/ or supabase/ file edited.

## What changed
* `tests/web/_paths.js` (new): `WEB_DIR` (env `WEB_DIR` or `<repo>/web`), `TESTS_DIR`, `REPO_DIR`, `freePort()` (env `PORT`, else port 0 found synchronously). It also sets `process.env.BOS_REPO_DIR`, because the data block of `smoke.js` is evaluated through `new Function` in ~26 tests (no `require` there).
* 86 existing `tests/web/*.js` edited only on path / port / SP-default lines: `/home/user/My-tools/web`, `path.join(__dirname,'..','..','web')`, `path.resolve(SP,'../../web')`, `SP+'/../../web/..'` -> `_P.WEB_DIR`; `data/` and `supabase/` reads -> `_P.REPO_DIR`; every fixed port (8077..8497, incl. ia_test 8472) -> `_P.freePort()` / `PORT`; `SP = process.argv[2]` -> `|| _P.TESTS_DIR`, so the argument is now optional. Assertions untouched. `grep -rn My-tools tests` is now only in the SQL side-scripts fixed below (0 hits).
* `tests/web/run_all.sh` (new): one test at a time, `TIMEOUT` (default 300 s), continues after failures, table (test, exit, parsed pass/fail), exit 1 if any exit code != 0.
* `tests/sql/final_build.sh`, `build_fresh_db.sh`, `p9/*.sh`, `run_all_p8.sh`: hard-coded `/home/user/My-tools` replaced by `REPO` (default = repo root of the script); `final_build.sh` also takes `PGSOCK`/`PGPORT` and uses a private temp file for errors (parallel-safe).
* `tests/sql/run_all_sql.sh` (new): reads the order from `docs/PASTE_ORDER.md` (foundation list + table, + any `phase1NN.sql` not in the table), builds one template DB, runs each `supabase/*_test.sql` on its own clone, compares fail counts with `tests/sql/baseline_fails.txt`.
* `tests/sql/baseline_fails.txt` (new): 73 suites from step_INT3_REPORT section 4 (22 known failures: phase8 1, 10 1, 15 1, 19 1, 21 1, 21b 1, 22 8, 23 1, 47 2, 72 1, 73 2, 76 1, 89 1) + 3 suites newer than INT3, measured here.
* `tests/README_RUN.md` (new, short usage).

## Verification
* Web, 8 tests run from `/` : old (HEAD tests with the path text-replaced) vs new vs new with `WEB_DIR=<copy of web>`: ia 0 fails, kbd 69/0, tpl 2248/0, scan 65/0, books85 38/0, optviews_ui "assert failures: 0", pos2 exit 0 with its 1 known FAIL (`old queued payload sent`) - all outputs byte-identical across the three runs. The old pos2 run crashed with `EADDRINUSE 8084` while 8 tests ran in parallel - the fixed-port problem this step removes. `nav_test` fails identically before and after (30 s timeout on `#navDrawer [data-act=lang][data-v=en]`, pre-existing on the integration branch, not caused here). `run_all.sh tpl` and `run_all.sh books` (also with `WEB_DIR`) give the table and exit 0.
* SQL: `run_all_sql.sh phase8 phase72 phase89c phase99 phase89d phase101` (build of the PASTE_ORDER chain 72..99 + phase101 took ~1 min): phase8 106/1 = baseline, phase72 70/1 = baseline, phase99 148/0, phase89d 65/0. Two suites differ from the INT3 numbers because the chain now continues past 98: `phase89c` 63/2 (INT3: 65/0 on 72..98; P2/P2a see phase99's re-created `online_order_get` / `online_orders_list`; `phase89d_test` is its replacement) and `phase101` 3 fails (T0/T3 count rows for the chain without phase99, see tests/sql/phase101_run.sh). Both recorded in the baseline with a note. The full 76-suite run was not repeated.
* Not run: all 87 web tests (only the 8 above + 5 via run_all); the full SQL sweep. `grep` for conflict markers in tests/ and docs: empty.

## Merge notes
Q1 (pos2) / Q2 (optviews) / Cat / Img / PBill only add new test files; the edits here to existing tests are 1-4 lines at the top of each file plus the `localhost:<port>` lines. New tests should start with `const _P = require('./_paths');`; a new test that still hard-codes a port or path keeps working but is not parallel-safe.
