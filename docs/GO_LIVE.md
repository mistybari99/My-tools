# GO LIVE: the owner's steps (no agent deploys anything)

Nothing in this file is done by an agent. The owner does each step himself, after review. Nothing turns a feature on by itself: every new switch starts OFF or blank (see section 4 for the few exceptions).

## 1. Before you start

1. Backup: Home > Backup, download the JSON, keep a copy outside the phone.
2. Restore that backup once into a spare (test) Supabase project and open the app there. A backup that was never restored is not proved.
3. Free-tier projects pause after 7 days without use; GitHub disables scheduled workflows after 60 days without repository activity. Check both before you start.

## 2. SQL: paste the files in order

- The full list, one line per file, is `docs/PASTE_ORDER.md` (phases 8 to 498, with the position of each file).
- Paste ONE file at a time into the Supabase SQL editor (the live project only after review). Wait for "Success" before the next one.
- Never paste: `supabase/phase84_test_project_only.sql`, `supabase/phase84b_*`, `supabase/phase84c_*`, any `*_test.sql`, `ALL_NEW*.sql`.
- XB phases 491 to 493 are not yet in `tests/sql/ORDER.txt`; they are listed in `docs/PASTE_ORDER.md` at their numeric position. Run the local build once before pasting them.
- After the last file run: `select * from public._i2_state() where not present;` It must return no rows.

### Old phase files (3 to 98), if you ever paste one again
Old files re-create functions and remove the hooks other phases added. If you paste one again: paste every file from that phase up to phase 98 in order, then paste phase 99 (or phase 477 by itself, which calls `public._i2_apply_all()`), then paste phase 478 again (it closes the helper functions to anon). Finish with the `_i2_state()` check in section 2.

## 3. Web app (the ERP screens)

1. The web app is the `web/` folder (static files). Before publishing, run `python3 tools/build_kb.py` if `docs/ai_kb/` changed.
2. Bump the service-worker cache version whenever a file under `web/` changes: `python3 tools/bump_sw.py` (dry run), then `python3 tools/bump_sw.py --write`, then `python3 tests/py/test_xc_bump_sw.py`. This branch is already bumped to `bos-sw-v3`; bump again if you change `web/` after this.
3. Copy the `web/` folder (except `setup-sql.html`) to the public Pages repository used by the app, commit and push it there.
4. On each phone: reload the app once, then reload again (the service worker is network-first).

## 4. Storefront (the public shop, `site/`)

- Read `docs/WEBSITE_DEPLOY.md` first. Everything starts OFF in the app's Website screen.
- The site is built and deployed only by hand: Actions > **site** > Run workflow. `deploy` stays `false` until the final https address is known (GitHub Pages needs its Source set to "GitHub Actions" once).
- No secret is needed by the site. Never put a secret key in `site/` or `web/`.

## 5. Switches: where to turn things on

Settings (the Switchboard), group "module". Each row has an (i) button that says what changes. Turn on one module at a time, smallest first, and check the figures after each.

Facts from the phase files (verified in `supabase/*.sql`):
- New modules default to OFF: e.g. `automation_on`, `social_on`, `social_publish_on`, `crm_lead_on`, `website_on`, `website_pay_cod_on`, `xc_summary_on`, `xc_summary_email_on`, `xc_summary_telegram_on`.
- Blank values stay blank on purpose (for example the markdown % and the rise threshold): with them blank, the feature says "not set" and invents no number.
- ON by default but inert until their module is on: `shift_mates_on` (needs `shift_on`), `crm_unmask_reason_required` (needs `crm_pii_guard_on`), `crm_complaint_fs_exception_on` and `crm_complaint_breach_exception_on` (need `crm_complaints_on`).
- Older base switches (phases 7 to 47, for example the notification switches of phase 46) were already ON before this build. They are not new. Check them in Settings if you want them different.

## 6. Scheduled jobs and outside calls

- `automation.yml` runs every 30 minutes in DRY RUN. A live run needs BOTH the repository variable `X1_AUTOMATION_LIVE = true` (or the manual input) AND the switch `automation_on` ON.
- `social.yml` is manual. A real post needs the input `send = true`, the repository variable `SOCIAL_SEND_ENABLED = 1`, and the switch `social_publish_on` ON.
- `owner_summary.yml` runs twice a day, but `tools/owner_summary.py` sends nothing while `xc_summary_on` is OFF.
- `notify.yml` and `backup.yml` are older schedules that were already in use.
- Secrets (SMS, Meta, Telegram, e-mail) are entered only in GitHub Settings > Secrets, never in the repository.

## 7. First day checklist

1. Owner logs in, Home loads, no red exception appears.
2. A test sale and a test purchase, then undo them as the app allows.
3. Backup downloaded and opened.
4. The Website screen (if used): one test order placed, tracked, cancelled.
