# GO LIVE: the owner's steps (no agent deploys anything)

Nothing in this file is done by an agent. The owner does each step himself, after review. Nothing turns a feature on by itself: every new switch starts OFF or blank (see section 4 for the few exceptions).

## 1. Before you start

1. Backup: Home > Backup, download the JSON, keep a copy outside the phone.
2. Restore that backup once into a spare (test) Supabase project and open the app there. A backup that was never restored is not proved.
3. Free-tier projects pause after 7 days without use; GitHub disables scheduled workflows after 60 days without repository activity. Check both before you start.

## 2. SQL: paste the files in order

This repository now holds ONE merged version of the two lines (the advanced line and our line). Read `docs/LIVE_DELTA.md` first if the project already holds data.

- **New (empty) project:** paste `docs/paste_parts/part01.sql` ... `part20.sql` in order (made by `tools/build_paste_parts.py`, copy page `docs/paste_parts/setup-all.html`), or the single files in the order of `docs/PASTE_ORDER.md` section B (= `tests/sql/ORDER.txt`). The parts are at most 500 KB each.
- **The current live project:** do NOT paste that list. Run the read-only probe of `docs/LIVE_DELTA.md` section 3, then paste only `docs/paste_parts/delta01.sql` and `delta02.sql` (phases 499, 501-505 and 529-539). They change nothing silently: every replaced function text is saved in `public._union_fn_backup`, and an unknown text stops the file with one message.
- Paste ONE part (or file) at a time into the Supabase SQL editor (the live project only after review). Wait for "Success" before the next.
- Never paste: `supabase/phase84_test_project_only.sql`, `supabase/phase84b_*`, `supabase/phase84c_*`, any `*_test.sql`, `ALL_NEW2` to `ALL_NEW11*`.
- After the last file run: `select * from public._i2_state() where not present;` (no rows) and `select state, count(*) from public._union_audit() group by 1;` (only `merged`, 156).

### Old phase files, if you ever paste one again
Old files re-create functions and remove the hooks other phases added. If you paste one again: paste phase 477, then 478, then 499 and 501 to 505, then the union files 529 to 539 again (all safe to paste twice). Never paste phase 40 or `ALL_NEW10.sql` after the advanced phase 511 without 529 after it (see `docs/PASTE_ORDER.md`). Run the two checks above.

## 3. Web app (the ERP screens)

1. The web app is the `web/` folder, but **the public site is the BUILD of it**: `tools/build_web.sh --out <folder>` (needs node; installs `terser` and `esbuild` once) makes `core.js` (the start-up files in one), the lazy screen files, `app.css`, `index.html` with the content hash `?v=` on every file, and `sw.js` with a matching cache name. Before building, run `python3 tools/build_kb.py` if `docs/ai_kb/` changed.
2. Do not copy `web/` to the public repository as it is any more (that is what lost the advanced screens before). Do not run `tools/bump_sw.py` for the public build: the build writes the cache name itself (`bos-sw-<build id>`). `web/sw.js` carries `bos-sw-v6` only for a plain copy of `web/`.
3. Put the build into the public Pages repository on a **preview** location first, check it on the phone with the list at the end of `docs/RECOVERY_ROADMAP.md` (Appendix C), then publish. `tools/build_web.sh --to <public clone on a pages/* branch>` copies the build and never pushes; it prints the files it removed. The public repository is changed only by the owner.
4. On each phone: reload the app once, then reload again (the service worker is network-first, and a new build replaces the cache by itself).

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
