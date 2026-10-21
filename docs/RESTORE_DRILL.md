# Restore drill - owner steps / রিস্টোর ড্রিল

**Status: UNVERIFIED on a real Supabase project.** The tool and the SQL were tested only on a local Postgres 16 (a fresh database built from every phase file, seeded, backed up with the real `tools/backup_dump.py` SQL functions, restored into a second "scratch" database). Nobody has yet restored a *real* Supabase backup. The drill below is that missing proof; it is an owner step.

**Why / কেন:** a backup that was never restored is only a hope. The drill proves the files restore, the table list matches the app, every table has row level security, the journal still balances (debit = credit) and the stock ledger still adds up to the stock balances. It never touches the live project: the tool refuses any database that is not on localhost **and** whose name does not contain `scratch`.

## What you need (a computer, not the phone) / যা লাগবে
* Postgres 16 server you control, a superuser (e.g. `postgres`), the `psql` client, Python 3, and a clone of the repo `mistybari99/My-tools` (for `tools/` and `supabase/`).
* Time: about 10-20 minutes.

## Step 1 - get the newest backup / সর্বশেষ ব্যাকআপ নামান
The nightly workflow commits the dump to the **`backups` branch** of the private repo (`latest/` = newest, `YYYY/MM/DD/` = that day). (Do not use an Actions "artifact": the workflow publishes the branch, not an artifact.)
```
git clone --branch backups --single-branch https://github.com/mistybari99/My-tools.git bos-backups
ls bos-backups/data/latest      # manifest.json + one <table>.ndjson.gz per table  (folder name may differ: check the branch README)
```
Optional Google Drive copy works the same: download the folder that holds `manifest.json`.

## Step 2 - build an empty scratch database with the app schema / খালি scratch ডাটাবেস
The backup holds data only; the schema comes from the repo's phase files (the same files you pasted into Supabase). With Postgres reachable by `psql -h /tmp -p 5544 -U postgres` run, from the code clone:
```
ORDER="$(grep -v '^#' tests/sql/ORDER.txt)" \
  bash tests/sql/build_fresh_db.sh bos_scratch
```
(`tests/sql/build_fresh_db.sh` uses socket `/tmp`, port `5544`; edit its `P=` line for another server. `tests/sql/ORDER.txt` lists every phase file in the owner paste order up to phase 99 (the same as `ORDER=all`); drop the names you have not pasted on Supabase. The database **must** be named with `scratch`.)

## Step 3 - run the drill / ড্রিল চালান
```
python3 tools/restore_drill.py bos-backups/data/latest --dsn "postgresql://postgres@/bos_scratch?host=/tmp&port=5544" --report drill.json
```
(`--dsn postgresql://postgres@localhost:5432/bos_scratch` for a TCP server.) The folder may also hold several backups: the newest `finished_at` is used. Exit code 0 = PASS, 1 = FAIL, 2 = refused / could not run. The JSON on screen lists each check:

| check | meaning |
|---|---|
| backup_intact | every file matches `manifest.json` (sha256, row count) |
| restore | `restore_backup.py --truncate` SQL applied without error (scratch tables are emptied first) |
| tables_list | tables in the backup == `_backup_tables()` of the schema (a mismatch = schema drift or a table the dump lost) |
| functions | key functions exist |
| rls | row level security is on for **every** table in `public` |
| row_counts | rows per table after restore == rows in the manifest |
| journal | every journal entry has debit = credit |
| stock | per item and place: sum of `stock_ledger` == `stock_balance` |

## Step 4 - record it in the app / অ্যাপে লিখে রাখুন
Open **#/restoredrill** (owner), fill the backup name, result (pass/fail), the two ticks (`tables_ok` = backup_intact, restore, tables_list, functions, rls; `rows_ok` = row_counts, journal, stock; the JSON prints both) and save. The page warns when no passing drill is recorded within 90 days (rule `restore_drill_warn_days`, change it in the Switchboard/Rules).

## What the backup does NOT contain (read before a real disaster) / ব্যাকআপে যা নেই
* **Auth users (logins)** live in Supabase Auth, not in schema `public`. A restore into a *new* project needs the same user ids created first (`profiles.id` = `auth.users.id`); passwords/PINs are not saved. Restoring into the *same* project keeps them.
* **Photos** (Storage): `tools/backup_photos.py`, not part of this drill.
* **Skipped by design** (`public._backup_tables()`, listed in the report as `skipped_by_dump`): `attendance_devices` (has `token_hash` - devices must be enrolled again), `ops_accounts` (bot marks - redo with `ops_account_set`), `login_failures / login_attempts / login_throttle`, `backup_runs`, `notifications`, `notification_reads` (re-created by use), anything named `*_secret*` or with a password/pin_hash/secret/token/salt/api_key column.
* Phase 70 un-hides `assistant_usage` (its `tokens_in/tokens_out` are plain counters; the old filter matched the word "token"). Nothing else was widened: PIN/token hashes stay out of a backup on purpose.
* The drill proves the data and the checks above, not that the app *screens* work on the restored copy, and not Supabase-specific things (Auth hooks, Storage policies, extensions, cron).

## If it FAILS / ব্যর্থ হলে
Do not panic and do not touch the live project. Save `drill.json`, record the fail in #/restoredrill, and send the JSON to the lead. A `tables_list` fail usually means a phase file is missing in step 2; a `row_counts` fail means a table file is damaged or a table was dumped while the schema changed.
