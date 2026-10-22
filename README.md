# 지휘역량강화센터 일정 · 업무 보드

인천소방학교 지휘역량강화센터 팀 보드와 현장지휘관 체크리스트 (GitHub Pages)

| 페이지 | 주소 | 파일 |
|---|---|---|
| 지휘역량강화센터 일정 · 업무 보드 (메인) | https://kwonyujin119.github.io/test2/ | `index.html` |
| 현장지휘관 체크리스트 | https://kwonyujin119.github.io/test2/checklist/ | `checklist/index.html` |

문서 안내: 직원용 → [`docs/직원안내.md`](docs/직원안내.md) · 담당자용 → [`docs/담당자-운영가이드.md`](docs/담당자-운영가이드.md) · 에이전트 시그니처 → [`SIGNATURE.md`](SIGNATURE.md)

## 보드 기능

팀원이 브라우저에서 일정과 업무를 직접 추가·수정·삭제할 수 있는 보드입니다.

- 헤더: 인천소방학교 심벌(클릭 → sachil47.com 새 창), 지휘역량강화센터 심벌(클릭 → 보드 홈)
- 대시보드: 제목을 누르면 목록이 열리고, 옆의 + 로 새 대시보드 추가(편집 PIN). 대시보드마다 일정·주요업무가 따로 저장됨. ⋮ 메뉴에서 이름 변경·삭제(기본 대시보드는 삭제 불가)
- 탭 3개: 일정표 · 주요업무 · 개인업무
- 일정표: 날짜별 그룹, 오늘 강조, 구분(교육/평가/회의/방문/출장/기타) 색·필터. 탭을 **한 번 더** 클릭하면 월 달력 보기 ↔ 목록 보기 전환. 달력의 빈 날짜 클릭 → 그 날짜로 새 일정
- 주요업무: 상태(예정/진행중/완료/보류) · 분류 · 담당자 필터 조합, 기한 지연 표시, 상태 배지 클릭으로 상태 순환
- 개인업무: 행정전화번호 뒤 4자리 + 이름만 입력. 처음이면 자동 등록, 이후 어떤 기기에서도 같은 정보로 내 업무 조회·기록 (비밀번호 없음). 로그아웃은 ⋮ 메뉴
- PC: 좌측 고정 사이드바(요약·필터·버튼) + 우측 콘텐츠 2단, 1400px 이상에서 업무 3열
- 모바일: 바텀시트 입력, 플로팅 추가 버튼
- 단축키: `N` 새 항목, `1`/`2`/`3` 탭 전환, `C` 달력 전환, `Esc` 닫기
- 다크모드 자동 대응, 브라우저 탭·홈화면 아이콘은 인천소방학교 심벌

### 데이터 저장 방식

**현재 운영 모드는 Supabase 모드입니다.** `config.js` 에 프로젝트 URL·anon 키가 들어 있어, https://kwonyujin119.github.io/test2/ 하나로 어디서나 같은 데이터를 봅니다.

| 모드 | 조건 | 동작 |
|---|---|---|
| **Supabase 모드** (현재 운영) | `config.js` 에 Supabase URL·anon key 입력 | 외부 클라우드 DB(싱가포르 리전). GitHub Pages 주소 그대로 사용. 조회 PIN·편집 PIN 2단계. 30초마다 자동 갱신 |
| 사내 서버 모드 (대안) | 설치 패키지([ZIP 다운로드](https://github.com/kwonyujin119/test2/raw/main/dist/ictc-board-server.zip))를 본인 PC에서 실행 | DB가 PC의 `D:\일정표,주요업무\ictc.db` 에 저장. 같은 네트워크 팀원이 `http://PC주소:8080` 으로 접속. PC가 켜져 있을 때만 동작. 15초마다 자동 갱신 |
| 미리보기(브라우저 저장) 모드 | `config.js` 가 비어 있을 때 | 수정 내용이 각자 브라우저에만 저장. 테스트용 |

세 모드의 화면과 기능은 같고 저장 위치만 다릅니다. 사내 서버 모드로 바꾸려면 `config.js` 의 두 값을 비우고 [`server/README.md`](server/README.md) 를 따르세요. 외부 클라우드를 쓸 수 없는 규정이 생겼을 때의 대안입니다.

### Supabase 모드 설정 (약 10분, 1회) — 링크 하나로 어디서나 공유

1. https://supabase.com 가입(GitHub 계정 로그인 가능) → **New project**. Region은 가까운 곳(서울 또는 싱가포르). 현재 운영 프로젝트는 Southeast Asia (Singapore, `ap-southeast-1`) 입니다. 이 단계는 이미 끝났습니다.
2. 좌측 **SQL Editor** → **New query** → 저장소의 `server/supabase.sql` 내용을 전부 붙여넣기.
   파일 상단의 `'1234'`(편집 PIN)와 `'0000'`(조회 PIN)을 팀 PIN으로 바꾼 뒤 **Run**.
   **보드가 업데이트되면 이 SQL을 다시 Run** 해야 새 기능이 동작합니다. 여러 번 실행해도 기존 데이터와 PIN은 유지됩니다.
   아래 "SQL 자동 적용"을 설정해 두면 이 재실행이 자동으로 됩니다.
3. 키 2개 복사. 왼쪽 메뉴 맨 아래 **Project Settings**(톱니바퀴) 에서
   - **API Keys** → Publishable key(`sb_publishable_…`) 또는 "Legacy anon, service_role API keys" 탭의 **anon public** 키. 둘 중 하나면 됩니다. `service_role` / `sb_secret_…` 는 절대 쓰지 않습니다.
   - **Data API** → **Project URL** (`https://프로젝트ID.supabase.co`). 보이지 않으면 **General** 의 Project ID 로 `https://프로젝트ID.supabase.co` 를 만듭니다.
4. `config.js` 의 `supabaseUrl`, `supabaseAnonKey` 에 붙여넣고 커밋·푸시.
5. https://kwonyujin119.github.io/test2/ 를 열면 조회 PIN 잠금 화면이 뜨고, 통과하면 "팀 공유 모드"가 됩니다.

anon 키는 브라우저에 노출되도록 설계된 공개 키입니다. 조회·편집 모두 PIN을 검증하는 DB 함수만 거치므로 키만으로는 데이터를 읽거나 쓸 수 없습니다.
무료 플랜은 1주일간 접속이 없으면 프로젝트가 일시중지되며, 대시보드에서 Restore 하면 데이터는 그대로 복구됩니다.

### SQL 자동 적용 (1회 설정, 2분)

`server/supabase.sql` 이 바뀌어 푸시되면 GitHub Actions 가 Supabase DB 에 자동으로 실행합니다. 설정은 한 번만 하면 됩니다.

1. Supabase 대시보드 상단의 **Connect** 버튼을 누릅니다. PC에서는 초록색 "Connect" 글자 버튼, 휴대폰에서는 프로젝트 이름 오른쪽의 **플러그 모양 동그란 아이콘**입니다.
   열리는 창에서 **Direct / Connection string** 카드 → Type **URI** → Method **Session pooler** 를 고르고 문자열을 복사합니다.
   `postgresql://postgres.xxxx:[YOUR-PASSWORD]@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres` 형태이며(`aws-0` 은 `aws-1` 일 수도 있음, 화면 그대로 사용), `[YOUR-PASSWORD]` 를 대괄호까지 지우고 DB 비밀번호를 넣습니다.
   비밀번호를 모르면 Project Settings → **Database** → **Reset database password** 로 새로 정합니다. 영문·숫자만 쓰면 주소에 넣을 때 문제가 없습니다.
   "Direct connection"·"Transaction pooler" 주소는 GitHub 서버에서 접속이 안 되므로 반드시 Session pooler 를 씁니다.
2. GitHub 저장소 → **Settings → Secrets and variables → Actions → New repository secret**
   Name: `SUPABASE_DB_URL`, Secret: 1번 값. **Add secret**.
3. 확인: 저장소 **Actions** 탭 → "Apply Supabase SQL" → **Run workflow** → 초록 체크가 뜨면 완료.

이후에는 SQL이 바뀔 때마다 자동 실행되고, Actions 탭에서 결과를 볼 수 있습니다. 실패하면 빨간 표시와 함께 원인이 로그에 남습니다.
이 비밀값은 DB 전체 권한이므로 채팅이나 코드에 절대 적지 마세요. GitHub Secret 에만 넣습니다.

### 접근 통제 (PIN 2종)

| PIN | 용도 | 기본값 | 변경 |
|---|---|---|---|
| 조회 PIN | 링크를 여는 직원이 처음 한 번 입력. 기기에 저장됨 | `0000` | Supabase: `select ictc_set_view_pin('편집PIN', '새PIN');` / 로컬 서버: `view_pin.txt` |
| 편집 PIN | 추가·수정·삭제, 대시보드 관리 시 처음 한 번 입력 | `1234` | Supabase: `select ictc_set_pin('기존PIN', '새PIN');` / 로컬 서버: `pin.txt` |
| 개인업무 식별 | 행정전화번호 뒤 4자리 + 이름. 비밀번호 없음 → 번호와 이름을 아는 사람은 누구나 그 개인업무를 볼 수 있음 | 없음 | 이름 오타 정정(담당자): `select ictc_user_reset_pin('편집PIN', '뒤4자리', '바른이름');` 이후 직원은 바른 이름으로 다시 들어감 |

조회 PIN을 빈 문자열로 두면 링크를 아는 누구나 조회할 수 있습니다. 편집 PIN은 조회 PIN을 겸합니다.
개인업무 등록은 조회 PIN을 통과한 사람(직원)만 할 수 있고, 아이디는 전화번호 뒤 4자리입니다(전체 번호를 넣어도 뒤 4자리만 사용).
PIN을 바꾸면 직원 기기에 잠금 화면이 다시 뜨므로 새 PIN을 공지해야 합니다.

### 구분(카테고리)와 필터

- 일정: 교육 · 평가 · 회의 · 방문 · 출장 · 기타 6종 고정, 색으로 구분. **시간 클릭** → 일시 변경 창, **제목 클릭** → 제목·장소·담당·메모 수정 창.
- 주요업무: 교육운영 · 행정 · 시설장비 · 대외협력 · 예산 · 기타 6종 고정, 카드 왼쪽 색 막대로 구분. 상태 · 분류 · 담당자 필터를 조합할 수 있습니다.
- 카테고리 이름을 바꾸려면 `index.html` 스크립트 상단의 `CATEGORIES`, `TASK_CATEGORIES` 와 같은 이름의 색 변수(`--c-*`, `--t-*`)를 함께 수정합니다.

### JSON 형식

```json
// schedule.json 항목
{ "id": "s001", "date": "2026-10-22", "start": "09:00", "end": "12:00",
  "title": "일정 제목", "place": "장소", "owner": "담당", "tag": "교육", "note": "메모" }
// tag: 교육 / 평가 / 회의 / 방문 / 출장 / 기타

// tasks.json 항목
{ "id": "t001", "category": "교육운영", "title": "업무명", "status": "진행중",
  "due": "2026-11-14", "owner": "담당", "detail": "상세 내용" }
```

`status`는 `예정` / `진행중` / `완료` / `보류`, `category`는 `교육운영` / `행정` / `시설장비` / `대외협력` / `예산` / `기타` 중 하나. `id`가 없으면 자동 생성됩니다.

### 화면에 뜨는 오류 문구와 뜻

| 문구 | 뜻 | 조치 |
|---|---|---|
| 조회 PIN이 필요합니다 / 올바르지 않습니다 | 잠금 화면 PIN 불일치 | 담당자에게 조회 PIN 확인. ⋮ 메뉴 → 조회 PIN 다시 입력 |
| 편집 PIN이 올바르지 않습니다 | 추가·수정·삭제 시 PIN 불일치. 저장된 PIN은 지워짐 | 다음 저장 때 다시 입력. ⋮ 메뉴 → 편집 PIN 입력/변경 |
| 이 번호는 다른 이름으로 등록되어 있습니다 | 개인업무: 뒤 4자리는 있는데 이름이 다름 | 등록 때 쓴 이름 그대로 입력. 오타면 담당자가 정정 |
| 이름은 2자 이상 / 뒤 4자리를 확인하세요 | 개인업무 입력값 형식 오류 | 숫자 4자리, 이름 2자 이상 |
| 이미 있는 대시보드입니다 / 기본 대시보드는 삭제할 수 없습니다 | 대시보드 관리 제한 | 다른 이름 사용 / 기본 보드는 유지 |
| 서버에 연결하지 못했어요 / 연결 안 됨 | 네트워크 또는 Supabase 일시중지 | 잠시 후 재시도. 계속되면 담당자가 Supabase 대시보드에서 프로젝트 상태 확인(Restore) |
| 서버 응답 404 (function … does not exist) | DB에 최신 SQL이 적용되지 않음 | 담당자가 Actions 자동 적용 확인 또는 SQL Editor 에서 `server/supabase.sql` 재실행 |

프론트나 서버 파일을 수정한 뒤에는 `python server/build_zip.py` 로 설치 패키지를 다시 만들어 커밋하세요.
