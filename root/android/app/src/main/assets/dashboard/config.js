// Use zashboard's supported URL parameters to connect to the local core.
const backend = new URL(window.location.origin);
const url = new URL(window.location.href);
if (!url.searchParams.has('hostname')) {
  url.searchParams.set('hostname', backend.hostname);
  url.searchParams.set('port', backend.port || (backend.protocol === 'https:' ? '443' : '80'));
  url.searchParams.set('protocol', backend.protocol.replace(':', ''));
  url.searchParams.set('secret', '');
  window.history.replaceState(null, '', url);
}
// The local core already serves the offline bundle; release an older panel's worker.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then((registrations) => {
    for (const registration of registrations) {
      if (registration.scope === new URL('./', window.location.href).href.split('?')[0]) {
        registration.unregister();
      }
    }
  });
}
