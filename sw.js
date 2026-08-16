const CACHE='champions-coach-v41';
const SHELL=['./index.html','./manifest.json','./icon.svg'];

self.addEventListener('install',e=>{
  e.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting()));
});

self.addEventListener('activate',e=>{
  e.waitUntil(
    caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))
    .then(()=>self.clients.claim())
  );
});

self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET')return;
  const url=new URL(e.request.url);
  /* HTML (navigatie + index.html zelf) was stale-while-revalidate: de OUDE cache-versie werd
     altijd meteen teruggegeven, de nieuwe fetch bijgewerkt "voor de volgende keer" -- dus na
     elke echte deploy zag je pas bij de TWEEDE herlaad de update, en leek een net gepushte
     wijziging simpelweg afwezig. Voor HTML nu netwerk-eerst: altijd de laatste versie zodra er
     verbinding is, alleen terugvallen op cache als het netwerk echt faalt (offline). Overige
     same-origin bestanden (manifest/icon) blijven cache-eerst, die veranderen zelden en hoeven
     niet elke load opnieuw opgehaald. */
  const isHTML=e.request.mode==='navigate'||url.pathname.endsWith('.html');
  if(isHTML){
    e.respondWith(
      fetch(e.request).then(res=>{
        if(res&&res.ok){const clone=res.clone();caches.open(CACHE).then(c=>c.put(e.request,clone));}
        return res;
      }).catch(()=>caches.match(e.request))
    );
  }else if(url.origin===location.origin){
    e.respondWith(
      caches.match(e.request).then(cached=>{
        const fetchPromise=fetch(e.request).then(res=>{
          if(res&&res.ok){const clone=res.clone();caches.open(CACHE).then(c=>c.put(e.request,clone));}
          return res;
        }).catch(()=>cached);
        return cached||fetchPromise;
      })
    );
  }else{
    e.respondWith(
      caches.match(e.request).then(cached=>cached||fetch(e.request).then(res=>{
        if(res&&res.ok){const clone=res.clone();caches.open(CACHE).then(c=>c.put(e.request,clone));}
        return res;
      }).catch(()=>cached))
    );
  }
});
