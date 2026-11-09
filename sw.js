// 설치(홈 화면 추가) 요건용 최소 서비스 워커. 캐시하지 않고 항상 네트워크를 사용한다.
// v2: 아침 브리핑 푸시 알림(상태표시줄) 수신 · 누르면 앱의 해당 톡방 열기
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data ? e.data.text() : '' }; }
  e.waitUntil(self.registration.showNotification(d.title || 'SAIL:41 아침 브리핑', {
    body: d.body || '', icon: 'assets/icon-192.png', badge: 'assets/icon-192.png', tag: d.tag || 'sail41-brief', renotify: false, lang: 'ko',
    data: { url: d.url || './' } }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || './', self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(ws => {
    for (const w of ws) { if (w.url.startsWith(self.registration.scope) && 'focus' in w) { return (w.navigate ? w.navigate(url) : Promise.resolve(w)).then(x => (x || w).focus()); } }
    return self.clients.openWindow(url);
  }));
});
