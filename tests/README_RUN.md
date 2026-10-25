# Running the tests (any checkout, any directory)

## Web (`tests/web`)
* `tests/web/_paths.js` exports `WEB_DIR` (env `WEB_DIR`, else `<repo>/web`), `TESTS_DIR`, `REPO_DIR`, `freePort()` (env `PORT`, else a free OS port). Every test uses it; no test contains `/home/user/...` or a fixed port any more.
* One test: `node tests/web/pos2_test.js` (argument optional; it defaults to the tests/web dir). Test another web folder: `WEB_DIR=/path/to/web node tests/web/ia_test.js`.
* All tests, one at a time, 300 s each, continue after failures, summary table, exit 1 if any exit code != 0:
  `bash tests/web/run_all.sh [name-filter]` (env `TIMEOUT`, `WEB_DIR`, `PORT`; logs kept in the dir printed at the end).
* New tests: `const _P = require('./_paths');` then `_P.WEB_DIR`, `_P.freePort()`; never hard-code a path or port.

## SQL (`tests/sql`)
* Needs a scratch Postgres on socket `/tmp` port `5544` (user `postgres`; env `PGSOCK`, `PGPORT`). Never a live database.
* `bash tests/sql/run_all_sql.sh [suite ...]` builds one final DB in the order of `docs/PASTE_ORDER.md` (via `tests/sql/final_build.sh`, repo root = env `REPO`, default this checkout), runs every `supabase/*_test.sql` (or only the named suites, e.g. `phase8 phase72 phase89c phase99`) on its own clone, prints pass/fail per suite and compares the fail count with `tests/sql/baseline_fails.txt` (the 22 known failures of `docs/briefs_p2p3/step_INT3_REPORT.md` + the post-INT3 suites). Exit 0 only if every suite equals the baseline. Env: `TEMPLATE=<db>` reuse a built db, `KEEP=1`, `TIMEOUT`, `LOGDIR`.
* When a fix changes a baseline number, edit `baseline_fails.txt` in the same commit.

## Known limits (25 Oct 2026)
* Ports: `final_build.sh` defaults to `PGPORT=5544`, `run_all_sql.sh` to `PORT=5570`. Pass `PORT=5544` (or start the scratch server on 5570).
* A fresh cluster needs the Supabase roles first: `create role anon nologin; create role authenticated nologin; create role service_role nologin;` (otherwise `mock_auth2.sql` fails).
* `run_all_sql.sh` builds "base = phases up to 87, then the rest", which does not match the union order of `ORDER.txt` (506.., 100-135 come before 80-87). On the union chain phases 113, 117, 121, 133-135 refuse and the counts are not valid, and the script still exits 0 when psql cannot connect. Until it is fixed, use the end-to-end build: `REPO=. PGPORT=5544 bash tests/sql/final_build.sh e2e`, then run each `supabase/<phase>_test.sql` ONCE on its own clone (`create database c template e2e`).
* Web tests: 139 files launch `/opt/pw-browsers/chromium-1194/chrome-linux/chrome`. Where another Chromium build is installed, link that path to it (outside the repo) or the tests crash before any check.
