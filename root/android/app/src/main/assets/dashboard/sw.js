// Retire service workers left by a previously bundled panel.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    for (const client of clients) {
      if (client.url.startsWith(self.registration.scope)) await client.navigate(client.url);
    }
  })());
});
