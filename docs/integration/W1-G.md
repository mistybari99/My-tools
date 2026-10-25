# Integration note W1-G: journal freshness and switch-coupling warning (U-11), data protection (U-12)

SQL number: **phase98** only. Paste after phase87 (and after the other Wave 1 phases 88-97 in any order: it reads only the phase 40/46/48/72 engine). Paste-twice safe. **No existing file is edited** except the two files this package owns (`tools/backup_dump.py`; `data/items_seed.csv` is NOT changed, see 5). Every shared SQL function is untouched: nothing here is re-created from an old body, so re-pasting an older phase can never remove anything of phase98.

Owner rules kept: every choice is a setting with a safe default and an English label and hint; setting changes land in `audit_log` through the existing `audit_rules` trigger; nothing switches itself on; no historic figure changes (proved, section 6); English labels only; no approver is hard-coded.

## 1. What phase98 adds (all names start `_w1g_` / `w1g_`)

| Name | Kind | Notes |
|---|---|---|
| `_w1g_post_scheduled(p_dry boolean default false)` | function (API) | The scheduled poster. Same engine calls as `acct_post_pending` (`_acct_docs` -> `_acct_resolve(_acct_merge(..))` -> `_acct_write` / `_acct_reverse`, same advisory lock `acct_post`, same `acct_post_errors72` bookkeeping, same closed-period test). Adds: watermark per source type, cap per run, fair rotation between source types (the type served longest ago goes first; oldest document first inside a type; a document that failed before goes last), optional source-type list, optional look-back window, one `audit_log` line per run that posted, one `w1g_post_runs` line per run that posted/reversed/failed/hit the cap. Allowed: the ops bot with purpose `notify`, the owner, an accounts manager (`_acct_manage`), or the database's own scheduler (no login, `session_user` postgres or supabase_admin, role none). Refused for everyone else, including a login with no grant and a browser session with no login. A real run answers `{"ran":false,"skipped":"switch_off"}` while the switch is OFF; a dry run (`p_dry:=true`) works while OFF and writes nothing. Also skipped: `data_needed`, `accounting_off`, `busy` (another session is posting). |
| `_w1g_freshness()` | function (API, read only) | Data for the "last posted at" strip: `status` (`fresh`, `waiting`, `stale`, `off`, `data_needed`), `last_posted_at`, `age_minutes`, `pending`, `oldest_pending`, `errors`, `last_check_at` (when the scheduler last looked, even with nothing to post), `by_type[]` (watermark per source type). Needs accounts view. |
| `_w1g_acct_readiness()` | function (API, read only) | G2: five checks (start date, accounting on, opening entry, mappings point to active postable accounts, no posting error) plus pending / locked / waiting counts. Needs accounts view. The plan called it `acct_readiness()`; the integrator may add a thin alias in phase99. |
| `_w1g_switch_coupling_warning(key, value)` | function (API, read only) | English text, `severity`, `locks`, `unlocks`, per-action list, `fix`, and `show` / `confirm` flags following the setting. Keys: `forms_post_to_ledger`, `path:<domain>` (value `"a"`, `"b"`, `"first"`), `journal_sched_post_on`. Unknown key = `known:false`. Needs owner or accounts view. |
| `_w1g_switch_coupling_ack(key, value, note)` | function (API, owner) | The owner confirms a warning: one `switch_coupling_confirm` line in `audit_log`, one single-use row in `w1g_switch_acks` (valid one hour). |
| trigger `rules_coupling_guard98` on `rules` | trigger | Only when `switch_coupling_warning = confirm`: turning `forms_post_to_ledger` or `journal_sched_post_on` ON is refused (`coupling_confirm_needed`) without a fresh confirmation. OFF is never held back. In the default mode `warn` the trigger does nothing. |
| `_w1g_backup_settings()` | function (API) | `{encrypt_on, retention_days}` for the backup bot (purpose backup or notify) and the owner. |
| tables `w1g_post_watermark`, `w1g_sched_state`, `w1g_post_runs`, `w1g_switch_acks` | tables | RLS on, closed to browser roles, no hard delete. Read through the functions above. |
| internal helpers | `_w1g_present`, `_w1g_bump`, `_w1g_oldest`, `_w1g_coupled_keys`, `_w1g_primary_if`, `_w1g_rules_coupling_guard` | closed to browsers |

### Settings added (all default to today's behaviour)

| Rule key (module) | Default | English label |
|---|---|---|
| `journal_sched_post_on` (books, switch) | **OFF** | Post new documents to the books on a schedule |
| `journal_sched_post_cap` (books, number 1-5000) | 1500 (= the batch of Post now; a technical size, not a business limit) | Most documents one scheduled run may post |
| `journal_sched_post_types` (books, text) | blank = every source type | Scheduled posting: only these source types |
| `journal_sched_post_lookback_days` (books, number 1-3650) | blank = scan everything since the start date | Scheduled posting: look back this many days |
| `journal_stale_warn_hours` (books, number) | blank = the strip never turns red by itself | Warn when waiting documents are not posted for this many hours |
| `switch_coupling_warning` (settings, choice off / warn / confirm) | **warn** | Warning before a switch that locks other screens |
| `backup_encrypt_on` (notify, switch) | **OFF** | Encrypt the nightly backup files |
| `backup_retention_days` (notify, number 1-36500) | blank = keep every dated folder | Keep dated backup folders for this many days |

Deliberate exception to "default = no new behaviour": `switch_coupling_warning` defaults to `warn`. It only shows text before a switch is saved, blocks nothing and changes no figure; set it to `off` to remove even that. The plan's exit test ("warning shown before the switch is saved") needs it visible by default.

### Facts verified

* The phase48-51 behaviour the warning describes is real: with `forms_post_to_ledger` ON the four actions stock issue, stock transfer, stock count and factory production flip from the screen (path a) to the paper form (path b) unless the owner has an explicit setting on `#/paths`; the stock screen is then refused with `path_locked` (test T12 runs the real `stock_issue` before, during and after).
* pg_cron: Supabase documents `pg_cron` as available on the hosted platform (Database > Extensions or Integrations > Cron; `cron.schedule(name, '* * * * *', $$ sql $$)`). Whether the owner's plan and project have it enabled is **[unverified]** (no live project was touched). The notify workflow route needs nothing extra, so it is the primary route; pg_cron is the optional second one (3.1).

## 2. Paste and fresh-build order

`phase98` after `phase87` (and after 88-97 when they exist). Add `phase98` to the integrator's `ORDER` string, and `phase98_test.sql`, `tests/web/freshness_test.js` to the test lists. Needs: `_p87_present`, `_acct_docs(date)`, `_acct_write`, `_acct_reverse`, `_is_ops`, `acct_post_errors72`, `path_domains` (the file stops with a clear message if one is missing).

## 3. Hooks needed (integrator). Each text below was applied to a SCRATCH COPY and proved by `tools/test_w1g_hooks.py`; that test also checks that every added line is printed here verbatim.

### 3.1 Notify workflow: one hook in `tools/notify_digest.py`, no change to `notify.yml`

The workflow already runs this script every 30 minutes as the ops bot (purpose notify). Add, right after the scan line in `run()`, exactly:

```python
        try:   # bos98 (W1-G): scheduled journal posting. The server answers "skipped" while the switch journal_sched_post_on is OFF (default).
            jp = api.rpc('_w1g_post_scheduled', {'p_dry': False})
            res['journal'] = {k: jp.get(k) for k in ('posted', 'reversed', 'left', 'skipped')} if isinstance(jp, dict) else None
            oc.log('journal posting:', res['journal'])
        except Exception as e:   # the alerts and the digest must never stop because the books could not be posted
            res['journal'] = {'error': type(e).__name__}
            oc.log('journal posting failed:', type(e).__name__)
```

after the existing line `oc.log(f"scan: {sc.get('created')} new notification(s)")` (inside `if not dry:`). Proof: with the patched scratch copy the 34 existing `test_ops` tests pass; the new behaviour (asked right after the scan, switch OFF = skipped, counts carried, a failing or missing function never stops the alerts, dry run makes no call) is tested in `tools/test_w1g_hooks.py`. The bot needs no new grant: `_w1g_post_scheduled` accepts `_is_ops('notify')`. Posting happens at most every 30 minutes (every hour if the owner follows the minutes advice in `notify.yml`); a cap of 1500 documents per run clears a normal day in one run.

Optional second route, pg_cron (no workflow minutes used) **[unverified on the owner's plan]**; pasted by the owner after phase98, only if the extension is on:

```sql
select cron.schedule('bos_journal_post', '*/30 * * * *', $$select public._w1g_post_scheduled(false)$$);
-- stop it: select cron.unschedule('bos_journal_post');
```

The job runs as postgres with no login, which the function accepts as `database_scheduler` (tested). Its journal entries then have an empty author. Use one route, not both (they are safe together: the second finds nothing, and a busy lock is skipped).

### 3.2 Backup workflow: four small patches in `.github/workflows/backup.yml` (only needed when the owner turns encryption ON)

Add the secret references to the job `env:` (a missing secret is an empty string and means "no encryption key"):

```yaml
      BACKUP_PASSPHRASE: ${{ secrets.BACKUP_PASSPHRASE }}
      BACKUP_KDF_SALT: ${{ secrets.BACKUP_KDF_SALT }}
```

(after `BOT_PASSWORD: ${{ secrets.BOT_PASSWORD }}`). In the step "Put the dump into latest/ and the dated folder" replace

```
-type f \( -name '*.ndjson.gz' -o -name 'manifest.json' \) -delete
```
with
```
-type f \( -name '*.ndjson.gz' -o -name '*.ndjson.gz.enc' -o -name 'manifest.json' \) -delete
```

and the two copy lines `cp out/*.ndjson.gz out/manifest.json data/latest/` and `cp out/*.ndjson.gz out/manifest.json "data/$DAY/"` with

```
cp out/*.ndjson.gz* out/manifest.json data/latest/
cp out/*.ndjson.gz* out/manifest.json "data/$DAY/"
```

and in the Google Drive step replace `--include '*.ndjson.gz' --include 'manifest.json'` with

```
--include '*.ndjson.gz' --include '*.ndjson.gz.enc' --include 'manifest.json'
```

Proof (`tools/test_w1g_hooks.py`, real step text run in a scratch folder): the UNPATCHED step fails on encrypted output (that is why the hook is needed); patched, a plain run still ends with plain files only, an encrypted run with encrypted files only, a stale file of the other kind is removed, `photos/` is kept. The passphrase appears only as a secret reference. Until the owner turns `backup_encrypt_on` ON these patches change nothing.

### 3.3 Web hooks

* `web/index.html`: `<script src="freshness.js"></script>` after `app.js` (next to `accounts.js`). `web/sw.js`: add `freshness.js` to the precache list if the screen files are listed there [not checked].
* `web/ia.js` (one line, next to the `balancecheck` record, group `acc`; the test injects this same line):

```js
  rec('freshness', 'acc', ['Books freshness', 'Books freshness', 'Books freshness'], { icon: 'check', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['books freshness', 'last posted', 'scheduled posting', 'journal', 'posted to books', 'books up to date'] }),
```

  No Home tile or bottom-bar slot. Do not rename the route `freshness`. `ia_test` record count +1 (intentional).
* Switch warning on `#/ledgerlinks` (`web/forms_stock.js`, function `lk_set`), after the line `const [k, v] = a.dataset.v.split(':'), on = v === '1';` add:

```js
    if (k === 'master' && on && window.BOS.freshness && !(await window.BOS.freshness.confirmSwitch('forms_post_to_ledger', true))) return;   // bos98 (W1-G): say what the switch will lock, before it is saved
```

* Switch warning on `#/paths` (`web/paths.js`, function `setSw`), after the line `const d = D.sw.find((x) => x.domain === dom), c = Object.assign({}, d.cfg, patch);` add:

```js
  if (patch.primary && window.BOS.freshness && !(await window.BOS.freshness.confirmSwitch('path:' + dom, patch.primary))) return;   // bos98 (W1-G)
```

  Proof: with both hooks applied to a scratch copy of `web/` the existing `forms_links_test.js` still passes (the hook is inert when `freshness.js` is not loaded or the server has no phase98). `confirmSwitch` itself is covered by `tests/web/freshness_test.js` (warning shown before the call, Cancel / outside tap / Continue, confirm mode with the checkbox and the server confirmation, server refusal, warning unreadable = not blocked).
* "Last posted at" strip on Home and Accounts: add an empty element where the strip should sit and call `window.BOS.freshness && window.BOS.freshness.mount(el)` after the screen is drawn. `mount` draws nothing when the server has no phase98 or the person has no accounts view, so it is safe on every screen. (`accounts.js` and the Home file are integrator-owned: **not applied or tested here**; `mount` itself is tested.)
* `#/freshness` page: strip, readiness checklist, per-source-type watermark, a read-only "Check now" (dry run) button, and for the owner the ON/OFF button for scheduled posting (through the same warning, then `set_rule`).

## 4. Data protection (U-12): what was built, what the owner must decide

| Piece | Where | State |
|---|---|---|
| Client-side encryption of the dump | `tools/backup_crypto.py` (new) + `tools/backup_dump.py` (owned) | Built, tested (28 tests). OFF until the owner turns on `backup_encrypt_on` AND supplies the passphrase. |
| Cost-free copy of the item seed | `tools/make_public_seed.py` (new) | Built, tested. **The seed file itself is NOT changed** (decision OD-15 is the owner's). |
| Retention of dated backup folders | `tools/backup_retention.py` (new) + rule `backup_retention_days` | Built, tested. Dry run by default, blank = keep everything. |
| Restore drill on an encrypted backup | `tools/backup_crypto.py decrypt` then the existing `tools/restore_drill.py` | Decrypt + restore SQL generation tested; the full Postgres drill on a decrypted copy is the owner's quarterly step (section 4.4). |

### 4.1 Backup encryption: how it works and what the owner holds

* Owner holds a passphrase of at least 16 characters (a random 5-word phrase is fine). It goes into the GitHub secret `BACKUP_PASSPHRASE` and into the owner's own safe place (password manager and a paper copy). **Lose it and the encrypted backups cannot be opened by anyone.** Never put it in a file, chat or screenshot. Optional secret `BACKUP_KDF_SALT` (hex); blank uses a fixed public application salt (the passphrase is the secret).
* Turn on in this order: (1) store the secret, (2) apply the 3.2 patches, (3) run the backup once by hand with `backup_encrypt_on` OFF, (4) switch it ON in the Switchboard (module Alerts and backup), (5) run the backup by hand and confirm the log says `(encrypted)`, (6) do the restore drill (4.4) before trusting it.
* Fail-closed: ON with a missing or short passphrase makes the run FAIL and be logged as failed (the app already warns about a stale backup); it never falls back to plain files. A run with the switch ON writes only `<table>.ndjson.gz.enc`; no plain file is left in the output folder.
* Format `BOSENC1`: scrypt key, per-file sub-keys bound to the table name, SHAKE-256 keystream, HMAC-SHA256 tag used as a synthetic IV so unchanged tables give identical bytes night after night (git history only grows by real changes; it does reveal WHICH tables changed on which night, not their content). `manifest.json` stays readable (row counts, sha256, schema fingerprint, an `encryption` block with no secret). It is built only from standard primitives and has **not had an independent cryptography review**; for a stronger guarantee use an audited tool (`age`, `gpg --symmetric`) and keep this as the dependency-free fallback.
* Auth users, photos and the skipped tables are unchanged by this: Auth users are still NOT in the dump (see `docs/RESTORE_DRILL.md`); photos (`tools/backup_photos.py`) are not encrypted by this work **[open: owner decision]**.

### 4.2 Retention (owner states the period in writing)

Owner statement to fill in and keep with the backup documents (no number is invented here): `Retention period: ____ days, stated by ____ on ____`. Then set `backup_retention_days` to that number. On a checkout of the `backups` branch: `python3 tools/backup_retention.py --root <folder holding latest/ and YYYY/> --days N` lists (dry run); add `--apply` to remove. Never touched: `latest/`, anything not named `YYYY/MM/DD`, the newest dated folder. **Git keeps old files in history**: removing a folder frees nothing in `.git` and does not make old data unreadable to someone holding the repository; that needs a history rewrite of the backups branch (owner-approved, `docs/HISTORY_CLEANUP_RUNBOOK.md`). Retention is not run automatically by any workflow.

### 4.3 Cost column in the seed file (OD-15)

`data/items_seed.csv` carries `cost_price` for 57 items. The repository is documented as PRIVATE (`docs/SETUP.md`, `docs/HANDOVER.md`) and `backup.yml` refuses to run in a public one; whether any copy is public is an owner fact **[unverified]**. Nothing was removed. If the owner says a public copy exists:

1. `python3 tools/make_public_seed.py check` (counts only);
2. `python3 tools/make_public_seed.py public-copy --out <file>` for a cost-free copy with the seed untouched; or
3. `python3 tools/make_public_seed.py strip --private-costs <file outside the repo> --owner-decision OD-15` (dry run), then add `--apply`. The costs move to the private file (mode 600); the seed loses the column. Undo: `restore --private-costs <same file> --apply` gives the original file back byte for byte (tested). It refuses to run without `--owner-decision OD-15`, to write the private file inside the repository, or to overwrite an existing file.
4. History still holds the old file: separate owner-approved step, `docs/HISTORY_CLEANUP_RUNBOOK.md` and `tools/make_clean_branch.sh` (never rewrite the only copy).

Readers of the seed: only `tools/map_seed_items.py`, which does not read the cost column. Run `python3 tools/check_no_demo_leak.py` after any of it.

### 4.4 Quarterly restore drill (owner step, result logged on `#/restoredrill`)

1. Get the newest dated folder of the `backups` branch. 2. If it holds `.enc` files: `BACKUP_PASSPHRASE=... python3 tools/backup_crypto.py decrypt <folder> <plain_folder>` (or `--passphrase-file`). A wrong passphrase fails at once with nothing written. 3. Follow `docs/RESTORE_DRILL.md` steps 2-4 on a scratch database with `<plain_folder>`. 4. Record the result on `#/restoredrill`. Setting `restore_drill_warn_days` (existing) keeps the reminder. Add phase98 to the `ORDER` list in step 2 of that document.

## 5. Tests and proofs (local throwaway Postgres 16, port 5567; a fresh build through phase 87, then phase98)

* `supabase/phase98_test.sql`: 110 pass, 0 fail. Includes negative tests: switch OFF posts nothing; dry run writes nothing; unapproved bot of the wrong purpose, salesperson, accounts viewer, no-login and anon refused on the server; closed period held back for the bot; a failing document recorded, retried and never blocking the others; cap and rotation proved run by run; look-back and type list; void reversed once; accounting off skipped; database scheduler allowed only with no login and role none; warning text equals the real behaviour (explicit owner setting respected; real `stock_issue` refused with `path_locked` while ON); `confirm` mode refused without the confirmation, single use, owner only; bad setting values refused; logs cannot be deleted; paste twice; every entry balances.
* `tests/sql/phase98_before_after.sh` (pattern of `phase87_before_after.sh`): 12 snapshots before and after pasting phase98 twice, 0 differ (P&L, income statement, balance sheet, trial balance, cash flow, day book, journal lines, balance check core, posting dry run). With the switch OFF nothing posts. Then, on twin databases, scheduled posting (cap 2, run by the notify bot, six calls) gives journal lines and every report equal to the manual `acct_post_pending` on the twin, including the reversal of a voided sale; a second session holding the posting lock makes the scheduler answer `busy`.
* Older suites with phase98 pasted versus without: phase20, 48, 51, 84, 85, 86, 87 give the identical set of failing lines (phase84 keeps its known 12 without its test-project file).
* `tests/web/freshness_test.js`: 0 assert failures, no console errors (360x780, three language modes read the same English text).
* `tools/test_backup_crypto.py` 28 pass; `tools/test_data_protection.py` 19 pass; `tools/test_w1g_hooks.py` (hooks on scratch copies); existing `tools/test_ops.py` 34 pass unchanged after the `backup_dump.py` edit.

## 6. Not done / UNTESTED / owner decisions

* Not run on a real Supabase project, a real phone, or the real GitHub runner (no workflow was run; the patched step text was run locally in a scratch folder). The full Postgres restore drill on a decrypted backup and `tools/test_restore_drill.py` end-to-end were not run here (they are hard-wired to port 5544 and the main checkout paths); the 8 unit tests of that file that need no database pass.
* pg_cron availability on the owner's plan: unverified (3.1).
* Strip on Home and Accounts: hooks written, not applied (integrator-owned files).
* Decisions only the owner can make (plan section 5, items 14 and 15): is any copy of this repository public (then the cost column and history); passphrase holder and the written retention period; whether photos should also be encrypted; whether a scheduler may run (GitHub notify job, recommended, or pg_cron).
* The poster re-implements the posting loop of `acct_post_pending` instead of calling it (that function refuses non-accountants and is integrator-owned). If the integrator changes the engine loop in `acct_post_pending`, mirror the change in `_w1g_post_scheduled`; `phase98_before_after.sh` fails if the two ever differ.
* Look-back window: documents older than the window are never posted by the scheduler (Post now still sees them); blank is the safe default.
* A document whose posting keeps failing is retried at every run (it is ordered last, so it never starves others) until someone fixes the cause; the error is in the Accounts status strip and in readiness.
