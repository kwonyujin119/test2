// 아침 브리핑 웹 푸시 발송 (GitHub Actions 의 briefing-push.yml 이 실행). 표준 web-push 라이브러리 사용.
// 입력 JSON: { day, vapid: { publicKey, privateKey, subject }, texts: { <톡방id>: 브리핑 본문 }, subs: [{ endpoint, sub, room }] }
// 출력 JSON: { sent: [endpoint], gone: [endpoint], failed: [{ endpoint, status, error }] }
// 사용: node server/push_send.js in.json out.json [--dry]   (--dry: 보내지 않고 본문만 만든다 · 로컬 검증용)
const fs = require('fs');
const [,, inFile, outFile, flag] = process.argv; const dry = flag === '--dry';
const IN = JSON.parse(fs.readFileSync(inFile, 'utf8'));
// 알림 본문: 첫 줄(날짜·톡방) → 제목, '오늘 일정 n건' + 첫 일정 2개 + 뉴스 건수 → 본문
function payload(room, text) {
  const L = (text || '').split('\n'); const head = L[0] || '';
  const m = head.match(/(\d+월 \d+일\([^)]*\))/); const date = m ? m[1] : '';
  const nm = head.match(/·\s*([^·]+?)\s*(·|$)/); const roomName = nm ? nm[1].trim() : room;
  const todayN = (L.find(l => /^오늘 일정 \d+건/.test(l)) || '').match(/\d+/); const newsN = L.filter(l => /^ \d\. /.test(l)).length;
  const items = L.filter(l => /^ \S+ /.test(l) && !/^ \d\. /.test(l) && !/^ … 외/.test(l)).slice(0, 2).map(l => l.trim().replace(/ · .*$/, ''));
  const body = [`오늘 일정 ${todayN ? todayN[0] : 0}건${newsN ? ` · 소방 뉴스 ${newsN}건` : ''}`, ...items].join('\n');
  return { title: `아침 브리핑 · ${date} · ${roomName}`, body: body.slice(0, 300), tag: `sail41-brief-${IN.day}`, url: `./#chat=${encodeURIComponent(room)}` };
}
(async () => {
  const out = { sent: [], gone: [], failed: [], preview: {} };
  for (const room of Object.keys(IN.texts || {})) out.preview[room] = payload(room, IN.texts[room]);
  if (!dry) {
    const webpush = require('web-push');
    webpush.setVapidDetails(IN.vapid.subject || 'mailto:admin@example.com', IN.vapid.publicKey, IN.vapid.privateKey);
    for (const s of IN.subs || []) {
      const text = IN.texts[s.room]; if (!text) continue;   // 그 톡방의 오늘 브리핑이 없으면(주말 등) 보내지 않음
      try { await webpush.sendNotification(s.sub, JSON.stringify(payload(s.room, text)), { TTL: 6 * 3600, urgency: 'high' }); out.sent.push(s.endpoint); }
      catch (e) { const st = e && e.statusCode; if (st === 404 || st === 410) out.gone.push(s.endpoint); else out.failed.push({ endpoint: s.endpoint, status: st || 0, error: String(e && e.message || e).slice(0, 200) }); }
    }
  }
  fs.writeFileSync(outFile, JSON.stringify(out));
  console.log(`푸시: 보냄 ${out.sent.length} · 만료 ${out.gone.length} · 실패 ${out.failed.length}${dry ? ' (dry)' : ''}`);
})();
