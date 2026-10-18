/* Storefront service worker (PWA-light). Caches ONLY the static shell of this site, never API or storage calls.
   Network first for pages, cache fallback offline. Bump CACHE when a file changes. */
const CACHE = 'site-shell-v1';
const SHELL = ['index.html', 'catalogue.html', 'product.html', 'cart.html', 'checkout.html', 'confirm.html', 'track.html', 'custom-cake.html',
  'contact.html', 'policies.html', 'assets/site.css', 'assets/site.js', 'assets/icon.svg', 'manifest.webmanifest', 'config.js'];
self.addEventListener('install', (e) => { e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', (e) => { e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', (e) => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== self.location.origin) { return; }   // API, storage and third-party calls are never cached
  e.respondWith(fetch(e.request).then((r) => { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)).catch(() => {}); return r; })
    .catch(() => caches.match(e.request).then((m) => m || caches.match('index.html'))));
});
