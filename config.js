// ICTC 보드 공유 저장소 설정
//
// [방법 A] D드라이브 로컬 서버 (server/ictc_server.py) 로 서비스할 때:
//   서버가 이 파일을 자동으로 대체하므로 수정할 필요가 없습니다.
//
// [방법 B] GitHub Pages + Supabase 로 운영할 때:
//   supabaseUrl, supabaseAnonKey 를 채우세요. (URL 은 https://xxxx.supabase.co 까지만)
//
// 둘 다 비어 있으면 '브라우저 저장 모드'(개인용)로 동작합니다.
window.ICTC_CONFIG = {
  supabaseUrl: "https://bcajgbpsfjufgkppxshm.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjYWpnYnBzZmp1ZmdrcHB4c2htIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI2MDY5NDIsImV4cCI6MjEwODE4Mjk0Mn0.nOv2Q_Vg2ZHuDy8BfU1cjaHyvOb2U0zWSOWsWJTs3Fg",
  pollSeconds: 30,
  fileMaxMB: 50          // 41망 첨부 파일당 한도(MB). Supabase 무료 요금제는 50MB. 고르는 순간 막아 다 올린 뒤 실패하지 않게,
  // 카카오톡 공유(선택). developers.kakao.com → 내 애플리케이션 → 앱 추가 → [앱 키] JavaScript 키 를 넣고,
  // [플랫폼] Web 에 사이트 도메인(예: https://kwonyujin119.github.io)을 등록하면 '브리핑 테스트' 뒤 카카오톡이 바로 열려 '나와의 채팅'을 고르면 됨.
  // 비워 두면 폰의 공유 창(카카오톡 선택)으로 대신함. JavaScript 키는 공개해도 되는 키(도메인 제한)
  kakaoJsKey: ""
};
