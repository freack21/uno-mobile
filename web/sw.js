// Offline support for the Last Card PWA.
//
// - Install: precache the app shell listed in precache_manifest.json
//   (emitted by `flutter build web --web-content-hash`).
// - Runtime: same-origin requests are cached on first use, so the renderer
//   (canvaskit) the browser picked also works offline after the first visit.
// - Entry files (index.html, bootstrap, manifests) are network-first so new
//   deploys are picked up; everything else is content-hashed or versioned with
//   the build and served cache-first.
//
// tool/build_web.sh replaces the version placeholder so every build ships a
// byte-different sw.js, which is what makes browsers install the update.
const VERSION = '__BUILD_VERSION__';
const CACHE = `last-card-${VERSION}`;

const NETWORK_FIRST = [
  '',
  'index.html',
  'flutter_bootstrap.js',
  'manifest.json',
  'version.json',
  'precache_manifest.json',
];
// Large files fetched lazily at runtime rather than on install.
const SKIP_PRECACHE = /^(canvaskit\/|assets\/NOTICES)/;

const scope = new URL(self.registration.scope);
const rel = (url) => new URL(url, scope).href.slice(scope.href.length).split('?')[0];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      const res = await fetch('precache_manifest.json', { cache: 'no-cache' });
      const { entries } = await res.json();
      const urls = entries.map((e) => e.url).filter((u) => !SKIP_PRECACHE.test(u));
      await cache.addAll(['./', ...urls]);
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names.filter((n) => n.startsWith('last-card-') && n !== CACHE).map((n) => caches.delete(n)),
      );
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type === 'skip-waiting') self.skipWaiting();
  if (data.type === 'cache-urls' && Array.isArray(data.urls)) {
    // URLs the page already loaded before this worker controlled it.
    event.waitUntil(
      caches.open(CACHE).then((cache) =>
        Promise.all(
          data.urls
            .filter((u) => u.startsWith(scope.href))
            .map((u) => cache.match(u).then((hit) => hit || cache.add(u).catch(() => {}))),
        ),
      ),
    );
  }
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET' || !req.url.startsWith(scope.href)) return;
  const path = rel(req.url);
  if (req.mode === 'navigate' || NETWORK_FIRST.includes(path)) {
    event.respondWith(networkFirst(req, req.mode === 'navigate'));
  } else {
    event.respondWith(cacheFirst(req));
  }
});

async function networkFirst(req, isPage) {
  const cache = await caches.open(CACHE);
  try {
    const res = await fetch(req, { cache: 'no-cache' });
    if (res.ok) cache.put(isPage ? './' : req, res.clone());
    return res;
  } catch (err) {
    const hit = await cache.match(isPage ? './' : req, { ignoreSearch: true });
    if (hit) return hit;
    throw err;
  }
}

async function cacheFirst(req) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(req, { ignoreSearch: true });
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok && res.type === 'basic') cache.put(req, res.clone());
  return res;
}
