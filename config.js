// ICTC 보드 공유 저장소 설정
//
// [방법 A] D드라이브 로컬 서버 (server/ictc_server.py) 로 서비스할 때:
//   서버가 이 파일을 자동으로 대체하므로 수정할 필요가 없습니다.
//
// [방법 B] GitHub Pages + Supabase 로 운영할 때:
//   supabaseUrl, supabaseAnonKey 를 채우세요.
//
// 둘 다 비어 있으면 '브라우저 저장 모드'(개인용)로 동작합니다.
window.ICTC_CONFIG = {
  supabaseUrl: "",
  supabaseAnonKey: "",
  pollSeconds: 30
};
