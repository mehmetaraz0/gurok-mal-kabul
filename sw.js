const CACHE = 'gurok-mal-kabul-v2';
// icon.svg repoda yok (icon.png var) — addAll tek dosyada bile başarısız olursa
// TÜM cache kurulumu reddedilir, bu yüzden yalnızca gerçekten var olan dosyalar listelenmeli.
const FILES = ['./index.html', './manifest.json', './icon.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
  ));
  self.clients.claim();
});

// network-first: kod güncellemesinden sonra kullanıcı bayat index.html'de kalmasın.
// Ağ yoksa (offline PWA senaryosu) cache'e düşülür — eski cache-first davranışın
// tek amacı buydu, o da korunuyor.
self.addEventListener('fetch', e => {
  e.respondWith(
    fetch(e.request).then(r => {
      if (r.ok && FILES.some(f => e.request.url.endsWith(f.replace('./', '/')))) {
        const kopya = r.clone();
        caches.open(CACHE).then(c => c.put(e.request, kopya));
      }
      return r;
    }).catch(() => caches.match(e.request))
  );
});
