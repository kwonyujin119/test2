# SAIL (지휘역량강화센터 일정·업무 보드) — 작업 규칙

앱 이름 **SAIL** = Schedule(일정표) · Attention(주요업무) · Individual Log(개인업무). 탭 라벨은 영문, 그 외 UI 문구는 한국어.

인천소방학교 지휘역량강화센터 팀이 쓰는 일정·주요업무·개인업무 보드. GitHub Pages(정적) + Supabase(공유 DB).
사용자(권유진)는 비개발자. 보고는 한국어, 결론 먼저, 근거 없는 칭찬 금지, 약점부터 말할 것.

## 파일 지도

| 경로 | 역할 | 담당 에이전트 |
|---|---|---|
| `index.html` | 보드 전체 (CSS+HTML+JS 단일 파일). 탭 3개: 일정표(목록/달력)·주요업무·개인업무, 대시보드 전환, PIN 잠금, 사용자 관리 | 화면(불빛) |
| `config.js` | 저장 모드 설정. Supabase URL·anon key(공개 키, 커밋 OK) | 화면 |
| `assets/` | 심벌(ifa.png, ictc.png), 파비콘, 앱 아이콘(icon-192/512) | 화면 |
| `manifest.webmanifest`, `sw.js` | 홈 화면 추가(PWA) 매니페스트와 최소 서비스 워커(캐시 없음, 네트워크만) | 화면 |
| `data/*.json` | 미리보기 모드 기본 데이터(예시) | 화면 |
| `checklist/index.html` | 기존 현장지휘관 체크리스트 (독립 페이지) | 화면 |
| `server/supabase.sql` | Supabase 스키마·RPC 함수 전체. 멱등(여러 번 실행 안전). PIN 기본값은 최초 설치 때만 적용 | 데이터·서버(불씨) |
| `server/ictc_server.py` | D드라이브 로컬 서버(Python 표준 라이브러리, SQLite). Supabase RPC 와 같은 의미의 `/api/*` | 데이터·서버(불씨) |
| `server/start.bat`, `server/README.md`, `server/build_zip.py`, `dist/*.zip` | Windows 배포 패키지 | 데이터·서버(불씨) |
| `.github/workflows/apply-supabase-sql.yml` | supabase.sql 푸시 시 DB 자동 적용 (Secret `SUPABASE_DB_URL` 필요) | 데이터·서버(불씨) |
| `README.md` | 사용자용 설치·운영 안내 | 운영(횃불) |
| `SIGNATURE.md`, `.claude/agents/*.md` | 에이전트 정체성·역할 | 운영(횃불) |

## 저장 모드 (index.html 의 `api` 어댑터)

1. **Supabase** — `config.js` 에 URL·key 있음. 현재 운영 모드. RPC 로만 접근(테이블 직접 접근 차단).
2. **로컬 서버** — 서버가 `/config.js` 를 `apiUrl:""` 로 대체. `/api/*` 호출.
3. **미리보기** — 둘 다 없음. localStorage. 테스트용 `config.js` 를 빈 값으로 복사해 사용.

세 모드의 동작이 같아야 한다. 프론트에서 호출 이름·파라미터를 바꾸면 SQL 함수 시그니처와 서버 핸들러를 같이 바꾼다.

## 접근 통제

- 조회 PIN(직원 전체, 기기에 저장; 일정·주요업무 추가·수정·삭제까지 가능) / 편집 PIN(관리자: 대시보드·사용자 관리·JSON 가져오기) / 개인업무 = 행정전화번호 뒤 4자리 + 이름(비밀번호 없음, 자동 등록).
- 오류 코드는 서버가 문자열로 던지고(`VIEW_PIN_INVALID`, `PIN_INVALID`, `USER_PIN_INVALID` …) 프론트 `ERR` 표에서 한국어로 바꾼다. 코드 매칭은 **가장 긴 코드 우선**(부분 문자열 오인 방지).

## 절대 규칙

- 비밀값(DB 비밀번호, 접속 문자열, service_role 키)은 코드·문서·채팅에 쓰지 않는다. anon 키만 공개 가능.
- `server/supabase.sql` 을 바꾸면: (1) 멱등성 유지, (2) 기존 PIN·데이터 보존, (3) 로컬 PostgreSQL 로 v1→v2 순서 재현 검증, (4) 사용자에게 "Actions 자동 적용 확인 또는 SQL Editor 재실행" 안내.
- 파일 경계를 지킨다. 화면 에이전트는 server/ 를, 데이터 에이전트는 index.html 을 고치지 않는다. 둘이 함께 바뀌어야 하는 기능은 한 에이전트(오케스트레이터)가 맡는다.
- 셸에서 `pkill -f` 로 자기 명령줄과 겹치는 패턴을 죽이지 않는다(세션 셸이 끊긴다). PID 파일로 종료한다.
- 커밋 메시지는 한국어, 접두어 `[불빛]`(화면) `[불씨]`(데이터·서버) `[횃불]`(운영). 둘 이상이면 나열 (SIGNATURE.md 참조). 푸시 후 Pages 반영 1~2분.

## 검증 절차 (`scripts/verify.sh`)

1. JS 문법: index.html 의 마지막 `<script>` 블록을 `new Function` 으로 파싱
2. Python 문법: `ast.parse`
3. SQL: 로컬 PostgreSQL 16(`/usr/lib/postgresql/16/bin`, 데이터 디렉터리 `/var/lib/postgresql/ictc_test`)에 `anon`/`authenticated` 역할 만들고 전체 실행 → 두 번 실행 → anon 으로 테이블 직접 조회가 거부되는지
4. 브라우저: `scripts/e2e.js` (Playwright, `NODE_PATH=$(npm root -g)`). 모드: preview / local / supabase-mock
5. `python3 server/build_zip.py` 로 dist 재빌드 (프론트·서버 변경 시 필수)

## 알려진 함정

- 저장소 `config.js` 에 실제 Supabase 키가 있다. "미리보기" 테스트는 반드시 빈 config 로 복사본을 만들어 돌린다. 이 컨테이너는 supabase.co 와 github.io 접속이 차단돼 있다.
- Pretendard 글꼴 CDN 도 차단돼 테스트 스크린샷은 대체 글꼴로 찍힌다. 실제 배포는 정상.
- Playwright `fill` 은 `maxlength`/`pattern` 을 우회하지 못한다. 입력 제한은 JS 로 정규화한다.
- 사용자 리전은 Supabase ap-southeast-1(싱가포르). 예시 주소에 서울 리전을 쓰지 않는다.
- Supabase 는 pgcrypto(`crypt`, `gen_salt`)를 `extensions` 스키마에 둔다. 모든 함수는 `set search_path = public, extensions` 여야 한다(public 만 두면 실서버에서 `gen_salt(unknown) does not exist`). verify.sh 가 같은 구조로 재현한다.
