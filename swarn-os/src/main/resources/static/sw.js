// Caches the app shell so the screens open even when the network drops.
// Data always comes from the shop server (local mode needs no internet).
const CACHE = 'swarn-os-v1';
const SHELL = ['./', 'index.html', 'app.css', 'icon.svg', 'manifest.webmanifest', 'vendor/qrcode.js', 'vendor/jsQR.js',
  'js/app.js', 'js/core.js', 'js/views.js', 'js/trade.js', 'js/stock.js', 'js/admin.js'];
self.addEventListener('install', e => e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())));
self.addEventListener('activate', e => e.waitUntil(caches.keys().then(keys =>
  Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.pathname.startsWith('/api/')) return;
  e.respondWith(fetch(e.request).then(res => {
    const copy = res.clone();
    caches.open(CACHE).then(c => c.put(e.request, copy));
    return res;
  }).catch(() => caches.match(e.request)));
});
