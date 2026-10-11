# BOS tool setup (Phase 1)

1. Supabase project exists (URL and publishable key are in `web/config.js`).
2. Authentication -> Sign In / Providers -> Email -> turn **Confirm email OFF**, Save.
3. SQL Editor -> New query -> paste all of `supabase/schema.sql` -> Run (once, on the empty project).
4. Open the app and **register first**: the first account becomes the active owner automatically.
   Everyone after that stays "pending" until the owner approves them in Staff & approval.
5. Backup: Home -> Backup -> download JSON, keep it in Google Drive (free plan has no auto-backup).

Notes
- `supabase/schema.sql` and `data/items_seed.csv` contain cost prices. Keep this repository private.
- `web/` contains no secrets (only the public publishable key) and can be hosted publicly.
- Never put the `service_role` / secret key anywhere in this repo.
- Wrong-PIN lock is checked by the app and recorded in the database; it is not a hard server-side
  block against someone calling the login API directly (Supabase's own rate limits still apply).
