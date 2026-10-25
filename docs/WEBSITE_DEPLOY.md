# Website deploy guide (storefront in `site/`)

The storefront is plain files (HTML, CSS, JavaScript). It has no build step and no server of its own. It talks only to the public
database functions with the publishable key, so it can be hosted on any static host. Nothing is hosted or bought by this build.

## 0. Today (no domain, no hosting)

1. In the ERP open **Website** (Sale group). Everything starts OFF.
2. Turn **Website (online shop) on** and choose the **branch that receives web orders**. Enter the shop names (Bangla and English).
3. Publish items: **Items & photos** tab, one by one or by category. Items must be active, sellable and priced.
4. Test locally: `python3 -m http.server 8000 --directory site` and open `http://localhost:8000/`. The page reads the live public
   settings, so the switch above must be on. Use a test order and cancel it.
5. Check the packaging (no network needed): `python3 tools/build_site.py --check` prints `OK` when the config is valid and the folder is clean.

## 1. The day you buy a domain or hosting (what the owner must do)

1. Choose a host from section 2 and deploy: `python3 tools/build_site.py --out dist/site --base-url https://YOUR-DOMAIN --zip`,
   then upload `dist/site` (or the zip) to the host.
2. Make sure the address is **https://** and opens the home page.
3. In the ERP **Website** screen, **Settings** tab: enter the address in **Public address** (`website_public_url`). Save.
4. Set the **WhatsApp number** (with the country code, e.g. 8801XXXXXXXXX) and, if used, the **Messenger page link**.
5. Set the pickup branch(es) (**Branches, zones, closures** tab): tick "Show on web" and enter opening hours.
6. Set delivery zones and charges if home delivery is offered; set the minimum order and the same-day cut-off if wanted.
7. Set the policy texts (privacy, terms, refund) in Settings. Until then the pages say "coming soon".
8. Open the **Status** tab and read the **go-live checklist**. Every *required* line must be OK. Optional lines may wait.
9. Place one real test order from the new address, track it, cancel it. Keep the order code in the shop's records.
10. Only then tell customers the address. Do not switch on the optional features (hard stock reservation, custom cake, Facebook Pixel,
    Google Analytics) until you have read their Settings hint; each one is a separate owner decision.

Nothing else changes in the database when the domain arrives. No secret is needed by the site. If the host or the project URL changes,
run `tools/build_site.py` again with the new `web/config.js` values.

## 2. Hosts (choose one; each takes about 15 minutes the first time)

### GitHub Pages (free, with the repository)
- Repository **Settings > Pages > Build and deployment > Source: GitHub Actions**.
- Actions > **site** > **Run workflow**: set `base_url` to the final https address and `deploy` to `true`. Leave `deploy` as `false`
  to only build and download the artifact. The workflow is manual only; it never runs on push.
- Custom domain: add it under Pages, then set the DNS records GitHub shows. Keep `base_url` equal to that domain.

### Netlify (free tier)
- Drag and drop the folder `dist/site` (or the zip) on the Netlify dashboard, or connect the repository and set
  **Publish directory** to `site` (no build command).
- Domain: Site configuration > Domain management > add the domain; Netlify gives the HTTPS certificate automatically.

### Cloudflare Pages (free tier)
- Create a Pages project, choose **Direct upload**, upload `dist/site`, or connect the repository with build output directory `site`
  and no build command.
- Custom domain: Pages project > Custom domains > add the domain (the zone must be on Cloudflare DNS).

### Supabase Storage (fallback only)
- Create a **public** bucket, upload the files of `dist/site` (keep the folder paths). The site works from
  `https://<project>.supabase.co/storage/v1/object/public/<bucket>/index.html`.
- Limits: no custom domain on the free plan, no automatic index routing (always write `index.html` in the address), and the
  content type must be right on upload. Test every page before you use it. Prefer one of the hosts above for a real shop.
- Do not put the service key anywhere. Upload from the dashboard with the owner's own login.

## 3. What the packaging script does (and does not)

- Reads only the public values in `web/config.js` (project URL and publishable key). Refuses a secret key (`sb_secret_`) or a
  service-role JWT.
- Writes `site/config.js` (generated; the only file that differs between a test copy and a live copy).
- Lints every file: no secret words, no private key block, only the allowed external hosts (Supabase, schema.org, WhatsApp,
  and the analytics hosts that load only when the owner sets an ID and the visitor accepts cookies).
- With `--base-url`, writes `robots.txt` and `sitemap.xml`. Without it, prints a warning: a sitemap needs the final address.
- Does not upload anything, does not call the network, does not change the database.

## 4. Privacy and consent (what the site does with personal data)

- The cart is kept on the visitor's device only. Orders carry the name, mobile and address that the customer types.
- Analytics (Facebook Pixel / Google Analytics) load only when the owner has set an ID **and** the visitor pressed "Accept".
- Campaign links (`utm_source`, `utm_medium`, `utm_campaign`) are kept for the visit and stored with the order.
- The custom-cake photo goes to a **private** bucket (`web-refs`, 3 MB, jpeg/png/webp). Only the owner can open it.
- The browser sends a random device token (not the IP address) to limit repeated submissions. The database never stores the raw token.

## 5. Keep it working

- After each change to `site/`, run `python3 tools/build_site.py --check` and deploy again.
- If a page looks wrong on a phone, check it at 360 px width first (the test in `tests/web/site_pages_test.js` does this).
- A new browser version may show the site from its cache; the service worker updates when `CACHE` in `site/sw.js` is changed.
