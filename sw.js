// 설치(홈 화면 추가) 요건용 최소 서비스 워커. 캐시하지 않고 항상 네트워크를 사용한다.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
