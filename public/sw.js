/* وصّلها — Service Worker
 * Strategy:
 *  - Navigations: network-first, fall back to cache, then offline page.
 *  - Static assets (css/js/fonts/images): stale-while-revalidate.
 *  - Supabase / Google Maps / any cross-origin API: NEVER cached
 *    (live orders, driver locations and maps must always be fresh).
 */
const VERSION = 'wslha-v3';
const SHELL_CACHE = `${VERSION}-shell`;
const ASSET_CACHE = `${VERSION}-assets`;

// Core app shell — precached on install for instant + offline loads.
const SHELL = [
  '/',
  '/stores',
  '/track',
  '/services',
  '/offline.html',
  '/global.css',
  '/icon-192.png',
  '/icon-512.png',
];

// Hosts whose responses must always hit the network (live data / maps).
const NEVER_CACHE_HOSTS = [
  'supabase.co',
  'supabase.in',
  'maps.googleapis.com',
  'maps.gstatic.com',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      .then((c) => c.addAll(SHELL).catch(() => {}))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => !k.startsWith(VERSION)).map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

function isNeverCache(url) {
  return NEVER_CACHE_HOSTS.some((h) => url.hostname === h || url.hostname.endsWith('.' + h));
}

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // Always go to network for live APIs / maps — do not touch the cache.
  if (isNeverCache(url)) return;

  // Page navigations: network-first with offline fallback.
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((res) => {
          const copy = res.clone();
          caches.open(SHELL_CACHE).then((c) => c.put(request, copy)).catch(() => {});
          return res;
        })
        .catch(() =>
          caches.match(request).then((cached) => cached || caches.match('/offline.html'))
        )
    );
    return;
  }

  // Same-origin static assets: stale-while-revalidate.
  if (url.origin === self.location.origin) {
    event.respondWith(
      caches.match(request).then((cached) => {
        const network = fetch(request)
          .then((res) => {
            if (res && res.status === 200) {
              const copy = res.clone();
              caches.open(ASSET_CACHE).then((c) => c.put(request, copy)).catch(() => {});
            }
            return res;
          })
          .catch(() => cached);
        return cached || network;
      })
    );
    return;
  }

  // Cross-origin (e.g. Google Fonts): cache-first, fall back to network.
  event.respondWith(
    caches.match(request).then((cached) => cached || fetch(request).then((res) => {
      if (res && res.status === 200) {
        const copy = res.clone();
        caches.open(ASSET_CACHE).then((c) => c.put(request, copy)).catch(() => {});
      }
      return res;
    }).catch(() => cached))
  );
});

// Allow the page to trigger an immediate SW update.
self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting') self.skipWaiting();
});
