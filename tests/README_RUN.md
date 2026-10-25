# Running the tests (any checkout, any directory)

## Web (`tests/web`)
* `tests/web/_paths.js` exports `WEB_DIR` (env `WEB_DIR`, else `<repo>/web`), `TESTS_DIR`, `REPO_DIR`, `freePort()` (env `PORT`, else a free OS port). Every test uses it; no test contains `/home/user/...` or a fixed port any more.
* One test: `node tests/web/pos2_test.js` (argument optional; it defaults to the tests/web dir). Test another web folder: `WEB_DIR=/path/to/web node tests/web/ia_test.js`.
* All tests, one at a time, 300 s each, continue after failures, summary table, exit 1 if any exit code != 0:
  `bash tests/web/run_all.sh [name-filter]` (env `TIMEOUT`, `WEB_DIR`, `PORT`; logs kept in the dir printed at the end).
* New tests: `const _P = require('./_paths');` then `_P.WEB_DIR`, `_P.freePort()`; never hard-code a path or port.

## SQL (`tests/sql`)
* Needs a scratch Postgres on socket `/tmp` port `5544` (user `postgres`; env `PGSOCK`, `PGPORT`). Never a live database.
* Fresh cluster: `initdb -U postgres -A trust`, start it on `-k /tmp -p 5544`. The runner creates the roles `anon`, `authenticated`, `service_role` when they are missing.
* `bash tests/sql/run_all_sql.sh [suite ...]` builds two databases with `tests/sql/final_build.sh`, both strictly in the order of `tests/sql/ORDER.txt`: **base** = ORDER.txt up to and including `phase87` (by position: 506-529 and 100-135 come before 80-87 there) and **final** = all of ORDER.txt. Every `supabase/*_test.sql` (or only the named suites, e.g. `phase8 phase113 phase543`) runs once on its own clone: base when its phase is inside the base part, final otherwise. It prints pass/fail per suite and compares the fail count with `tests/sql/baseline_fails.txt`. Exit 0 only if every suite equals the baseline; 1 if a suite differs, times out, prints no result or cannot be cloned; 2 if there is no connection, a role is missing or a build fails (fail closed: never a green run without a database). Env: `PGSOCK`, `PGPORT` (`PORT` is an alias), `JOBS`, `TIMEOUT`, `LOGDIR`, `KEEP=1`, `PFX`.
* `tests/sql/run_all_union.sh` is the older chain runner (paste-twice check, every suite at its own position); `run_all_sql_adv.sh` runs everything on the final build only.

### Known limits
* A suite runs on base or final, not on the database through its own phase. Suites that assert "package X not installed yet" / "hooks not installed yet" therefore count those checks as fails on final; the numbers in `baseline_fails.txt` are measured that way, so a difference still means a change.
* Suites that paste their own phase and need the chain WITHOUT it are listed in `PRE_OWN` in `run_all_sql.sh` (now `phase543`); the runner builds ORDER.txt minus that phase for each. `phase543_test.sql` stops with one FAIL (no foreign-key errors) when its phase is already on the database.
* `phase84_test` gets `phase84_test_project_only.sql` pasted on its clone first; the test-project files are for TEST databases only and are never pasted on the live project.
* Every database is a local throwaway; nothing here connects to the live Supabase project.
* When a fix changes a baseline number, edit `baseline_fails.txt` in the same commit.
