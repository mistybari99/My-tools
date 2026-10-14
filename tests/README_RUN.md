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
