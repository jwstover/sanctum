const CACHE_NAME = 'sanctum-v1';

self.addEventListener('install', (event) => {
  console.log('Service Worker: Installing');
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  console.log('Service Worker: Activating');
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cache) => {
          if (cache !== CACHE_NAME) {
            console.log('Service Worker: Clearing Old Cache');
            return caches.delete(cache);
          }
        })
      );
    })
  );
});

self.addEventListener('fetch', (event) => {
  console.log('Service Worker: Fetching');
  event.respondWith(fetch(event.request));
});