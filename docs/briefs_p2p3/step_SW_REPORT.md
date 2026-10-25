# Step SW report: old public bundle -> new bundle, service worker, offline POS

Test: `node tests/web/swupdate_test.js` (Chromium, https + h2 + gzip, Pages-like headers; OLD = islamia-bos-app `origin/main` (build a70e358993), NEW = this checkout's `web/` through `make_bundle.sh` (copy in `tests/web/fixtures/`)). Supabase is mocked.
Why https: `swreg.js` registers the worker only on https, so plain http://localhost tests nothing. "Offline" = `setOffline` plus the server dropping connections (Playwright's `setOffline` does not reach the service worker's own fetches).

## Result: 50 checks, all pass with the bos110 fix in `web/sw.js`

| # | Question | Result |
|---|----------|--------|
| 1 | Update OLD -> NEW, 2 reloads | New index, every local js/css carries the same `?v=` build, old cache `bos-sw-a70e358993` deleted, one cache left, no console errors, app boots. Cache keys of both builds never mix. |
| 2 | Offline on NEW | Shell loads from cache, POS opens, 2 offline sales queue in `bos_pos_queue_<uid>` (localStorage), replay once each (repeated flush does not resend), refused sale (`insufficient_stock`) stays a failed card and shows on the Today tab. |
| 3 | Sale queued under OLD code | Queue made by the real old bundle survives the update and is sent exactly once by NEW. |
| 4 | Signed URLs (itemimg.js) | Expired link is never reused (memory) and not restored from the `cache_hours` localStorage copy; image host is cross-origin so the worker never caches it. |
| 5 | Update mid-sale | NO forced reload. Page object lives, sheet stays open, sale completes once. The open page keeps running the OLD scripts until its next reload (controllerchange fires once; the new worker precaches in the background). |
| 6 | Fast 3G cold first load (562 ms RTT, 1.6 Mbps) | OLD 8.3 s / 1103 KB gzip / 103 requests; NEW 8.7 s / 1162 KB / 110 requests; x1.05 (limit 2x, not flagged). |

## Real findings

1. **SW-1 (fixed, bos110, `web/sw.js`)**: after an update the new cache `bos-sw-<build>` was EMPTY (0 files). `install` did not precache and `activate` deleted the old cache that held the files the page had just loaded. A phone going offline before one more online load got "offline" (503). Same cause as **SW-3**: on the very first visit the cache stays empty until the second load. Fix: `install` fetches index.html and every local script/css/manifest/icon it names (`cache:'reload'`), puts them in the new cache, then `skipWaiting`; any failure still installs as before. Verified: 110 files cached after one visit, offline start works right after the swap. Cost: the first visit/update downloads the files a second time in the background (about +1.1 MB gzip).
2. **APP-1 (not fixed, outside sw.js/swreg.js)**: a COLD start with no internet shows the login screen, not the POS: `app.js start()` calls `my_context`, on error `fail()` + `viewAuth()`. Offline POS works only if the app was open when the connection dropped (tested: queues and replays once). Suggested fix: cache the last `my_context` in localStorage and use it when the call fails with a network error.
3. Informational: the hard-reload/HTTP cache (Pages `max-age=600`) did not produce a stale index in the tests (a normal visit after deploy showed the new build); phones with no network at all keep the old consistent set.

Notes: test infra only otherwise; no live DB, no main. The test needs a clean committed `web/` (make_bundle refuses a dirty source). While setting up I deleted two scratch dirs named `old` and `new` in the session scratchpad (re-created by this work).
