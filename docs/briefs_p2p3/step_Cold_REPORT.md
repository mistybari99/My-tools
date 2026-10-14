# Step Cold (bos112) - offline cold start

Problem: app closed and reopened with no internet showed the login screen (my_context failed), so offline POS only worked if the app was already open.

## What changed (all tagged bos112)
- `web/coldstart.js` (new): saved snapshot, network-vs-auth test, banner, "Needs internet" state, environment (locations/rules/lists/items) fallback.
- `web/app.js`: save context after each good my_context; `start()` boots offline from the snapshot only on a NETWORK error (or an expired token that cannot refresh offline: supabase-js then returns no session, so the stored sign-in user id is read from its own `sb-*-auth-token` key, never the token); background retry every 30 s + `online`; logout/disabled/SIGNED_OUT clear the snapshot; offline sign-in says "Internet needed for first sign-in" instead of "wrong PIN".
- `web/pos.js`: POS had NO item cache (load() threw offline). Added: save the item list after each good load, use it on a network error.
- `index.html` (script tag), `styles.css` (banner).

## Rules
- Kept (localStorage `bos_cs_*`, v1, try/catch, size-capped): my_context answer, locations, rules, option lists, grant defs, item list with SELL prices (allow-listed fields). Never: token/password/PIN, cost prices, staff directory. Language/theme already live in localStorage.
- Fixed 14-day cap (`MAX_AGE_DAYS`) since the last good my_context; older = offline start refused with a message.
- Reconnect: my_context ok -> S.ctx refreshed, banner removed, queues resend (client_id, once), page NOT reloaded. Inactive/removed/auth error -> snapshot cleared, signed out, login with message; the unsent sale queue stays on the phone.
- Offline mode allows Home and POS; every other screen shows "Needs internet" and fills itself in on reconnect.
- Network error = no server answer (fetch failed, offline, 502/503/504). Anything with a PostgREST/auth code or other HTTP status is an auth/permission error, not offline.

## Tests
`tests/web/coldstart_test.js` 45 checks pass (story, needs-internet, deactivated, sign-out, no cache, 14-day cap, net vs auth, lang, 360px, no page errors). Existing order, swupdate (55), pos2b, posfail, invoiceview, kbd, nav_b, ia, lang_all, lang_en unchanged and passing.

## Limits
- Offline start needs one earlier online sign-in on that phone and the service worker cache (bos110).
- Env/items are saved when POS/forms load, or by a once-a-day background warm-up for POS users; a user who never loaded them online cannot sell offline.
