# r17 REPORT - gap #17 restore drill (phase70)

## Built
1. **tools/restore_drill.py** (stdlib + psql). Takes a backup folder (or a folder of backups: newest `finished_at`), restores it with the existing `restore_backup.py --truncate`
   into a SCRATCH Postgres, then prints ONE JSON report (PASS/FAIL; exit 0/1; 2 = refused). Checks: backup_intact (sha256+rows), restore, tables_list (manifest vs the
   schema's `_backup_tables()`), functions (16 key ones), rls (every public table), row_counts (per table vs manifest), journal (debit=credit per entry), stock (ledger sum vs stock_balance).
   Also prints `skipped_by_dump` (with reason), `not_in_backup` (auth users, photos, hashes) and a `record_hint` for the app form.
   SAFETY: refuses (exit 2, nothing run) unless host is localhost/127.0.0.1/::1/unix socket AND db name contains "scratch"; refuses anything with supabase/pooler in it,
   multi-host DSNs, a non-superuser, a non-loopback server address after connecting, or a DB without the app schema. Never reads SUPABASE_* env.
2. **supabase/phase70.sql**: table `restore_drills` (append-only trigger `_append_only70`, RLS owner-read, no direct writes), owner-only `restore_drill_record(name,result,tables_ok,rows_ok,notes,drilled_at)`
   (a pass needs both ticks; future date refused), `restore_drill_list(n)`, `restore_drill_status()` (last drill, age_days, last_pass_age_days, never, warn, last_failed),
   rule `restore_drill_warn_days` = 90 (min 7, max 730; warn = no PASSING drill within N days). Grants: authenticated only; anon none.
3. **Dump gaps (audit §7.2)**: what the dump skips: `attendance_devices` (token_hash), `ops_accounts`, `login_failures/attempts/throttle`, `backup_runs`, `notifications`, `notification_reads`,
   and `assistant_usage` (false positive: tokens_in/tokens_out are counters). ONLY `assistant_usage` was un-hidden (`_backup_tables()` re-created, tag bos70, regex excludes `^tokens_(in|out)$`);
   hashes/tokens deliberately stay out (PIN-hash exposure would allow brute force). `entries` etc. were already in the dump. Auth users are not in the dump: documented.
4. **web/restoredrill.js** `#/restoredrill` (owner; non-owner makes no RPC): status card + warning chip, 3-step how-to, record form (validation: name required, pass needs both ticks), history list, bn/mix/en, 360px, friendly message if phase70 not installed.
5. **docs/RESTORE_DRILL.md**: exact owner steps. NOTE: the nightly backup is committed to the `backups` branch (data/latest/), NOT an Actions artifact; the doc says so.

## Tests
* SQL `supabase/phase70_test.sql` on a fresh DB through phase62+70: **28 pass / 0 fail**. Re-apply phase70 a 2nd time: error-free.
* Regression `phase46_test.sql` (touches `_backup_tables`): 117 pass / 0 fail on DB with phase70 and on DB through phase62 (identical).
* `python3 -m unittest tools/test_restore_drill.py`: **11 tests OK** (4 unit: DSN refusals incl. supabase/remote/non-scratch/multi-host, newest pick; 7 end-to-end on local Postgres :5544: build template with
  all phases, seed stock+journal, backup with the REAL backup_dump.run via the real SQL functions, restore into p70drill_scratch -> PASS; damaged file -> FAIL; deleted rows / unbalanced journal / stock mismatch /
  RLS off / dropped function each -> the right check FAIL; table missing from manifest and ghost table -> FAIL; empty DB / non-scratch name refused; CLI stdout is pure JSON). `tools/test_ops.py` unchanged: 34 OK.
* Web `node tests/web/restoredrill_test.js /home/user/My-tools/tests/web` (Playwright, as notifications_test): **0 assert failures, errors: none**.

## For the lead (not done by me)
ia.js (tag: owner only):
`rec('restoredrill', 'settings', ['রিস্টোর ড্রিল', 'Restore drill', 'Restore drill'], { icon: 'settings', ok: owner, kw: ['restore', 'drill', 'backup test', 'recovery', 'রিস্টোর', 'ড্রিল', 'ব্যাকআপ যাচাই'] }),`
index.html (after paths.js / notifications.js): `<script src="restoredrill.js"></script>`
Build order: ... phase62 phase70. Optional later: a backup-status card/notification link to #/restoredrill when `restore_drill_status().warn`.

## NOT done / UNVERIFIED
* The REAL Supabase restore drill (spare project, real backup from the `backups` branch) was NOT run: UNVERIFIED. Owner step in docs/RESTORE_DRILL.md.
* The scratch schema is rebuilt from the repo's phase files, not from the live project, so live-only drift shows up as a `tables_list`/`functions` fail (intended, but unproven on real data; a 146+-table live DB was never restored).
* Row counts in the drill compare file vs restored rows; they cannot detect rows the dump itself never read. Auth users, Storage photos, Supabase Auth hooks/extensions are outside the drill.
* No notification/Home tile is wired to `restore_drill_status().warn` (page only). `tests/sql/build_fresh_db.sh` is hard-coded to /tmp:5544 (documented).
* Scratch test DBs (p70*, r17src) were dropped after the run.
