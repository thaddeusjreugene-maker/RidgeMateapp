const APP='ridgeline-teams-v6';
const SHELL=['./','./vendor/jspdf.umd.min.js','./index.html','./app.css','./config.js','./js/app.js','./js/api/demo.js','./js/api/shape.js','./js/api/supabase.js','./vendor/leaflet.js','./vendor/leaflet.css','./vendor/supabase.esm.js','./manifest.webmanifest','./push-sw.js','./icon-180.png','./icon-192.png','./icon-512.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(APP).then(c=>Promise.all(SHELL.map(u=>c.add(u).catch(()=>{})))).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==APP).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{const r=e.request;if(r.method!=='GET')return;const u=new URL(r.url);
  if(u.hostname==='cdnjs.cloudflare.com'){e.respondWith(caches.open(APP).then(async c=>{const hit=await c.match(r);if(hit)return hit;const res=await fetch(r);if(res.ok)c.put(r,res.clone());return res}));return}
  // the Supabase library from the CDN: cache so the app opens with weak signal
  if(u.hostname==='cdn.jsdelivr.net'){e.respondWith(caches.open(APP).then(async c=>{const hit=await c.match(r);if(hit)return hit;const res=await fetch(r);if(res.ok)c.put(r,res.clone());return res}));return}
  if(u.origin===location.origin||u.hostname.endsWith('fonts.googleapis.com')||u.hostname.endsWith('fonts.gstatic.com')){
    e.respondWith(fetch(r).then(res=>{if(res.ok){const cp=res.clone();caches.open(APP).then(c=>c.put(r,cp))}return res}).catch(()=>caches.match(r).then(m=>m||caches.match('./index.html'))))}
});

// notifications
const PUSH_ICON = 'icon-192.png';
self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data ? e.data.text() : '' }; }
  e.waitUntil(self.registration.showNotification(d.title || 'RUVA', {
    body: d.body || '', tag: d.tag || undefined, renotify: !!d.tag,
    icon: PUSH_ICON, badge: PUSH_ICON, data: { url: d.url || './' }
  }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || './', self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cs => {
    for (const c of cs) if ('focus' in c) { c.postMessage({ open: url }); return c.focus(); }
    return self.clients.openWindow(url);
  }));
});
