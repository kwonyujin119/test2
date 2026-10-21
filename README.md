# test2

인천소방학교 현장지휘관 체크리스트 및 ICTC 일정·업무 보드 (GitHub Pages)

| 페이지 | 주소 | 파일 |
|---|---|---|
| ICTC 일정 · 주요업무 (메인) | https://kwonyujin119.github.io/test2/ | `index.html` |
| 현장지휘관 체크리스트 | https://kwonyujin119.github.io/test2/checklist/ | `checklist/index.html` |

## ICTC 일정 · 주요업무 (웹앱 초안)

팀원이 브라우저에서 일정과 업무를 직접 추가·수정·삭제할 수 있는 보드입니다.

- 일정표: 날짜별 그룹, 오늘 강조, 구분(교육/회의 …) 필터
- 주요업무: 상태(예정/진행중/완료/보류) 필터, 기한 지연 표시, 상태 배지 클릭으로 상태 순환
- PC: 좌측 고정 사이드바(요약·필터·버튼) + 우측 콘텐츠 2단, 1400px 이상에서 업무 3열
- 모바일: 바텀시트 입력, 플로팅 추가 버튼
- 단축키: `N` 새 항목, `1`/`2` 탭 전환, `Esc` 닫기
- 다크모드 자동 대응

### 데이터 저장 방식

| 모드 | 조건 | 동작 |
|---|---|---|
| **사내 서버 모드** (권장) | 설치 패키지([ZIP 다운로드](https://github.com/kwonyujin119/test2/raw/main/dist/ictc-board-server.zip))를 본인 PC에서 실행 | DB가 PC의 `D:\일정표,주요업무\ictc.db` 에 저장. 같은 네트워크 팀원이 `http://PC주소:8080` 으로 접속. 조회 PIN·편집 PIN 2단계. 15초마다 자동 갱신 |
| Supabase 모드 | `config.js` 에 Supabase URL·anon key 입력 | 외부 클라우드 DB. GitHub Pages 주소 그대로 사용 가능 |
| 미리보기(브라우저 저장) 모드 | 위 둘 다 아님 = **GitHub Pages 주소의 기본 상태** | 수정 내용이 각자 브라우저에만 저장. 상단 안내의 "사내 서버 주소 연결"에 PC 서버 주소를 넣어 두면 "사내 서버로 이동" 버튼으로 바로 넘어갈 수 있음 |

GitHub Pages(HTTPS)는 사내 PC 서버(HTTP)의 데이터를 직접 읽을 수 없습니다(브라우저 보안 정책). 팀 공유 데이터는 반드시 PC 서버 주소(`http://PC주소:8080`)로 접속해서 봐야 합니다.

**사내 서버 모드 설치 방법은 [`server/README.md`](server/README.md) 를 보세요.** (Python 설치 → 폴더 복사 → start.bat 실행)

### Supabase 모드 설정 (약 10분, 1회) — 링크 하나로 어디서나 공유

1. https://supabase.com 가입(GitHub 계정 로그인 가능) → **New project**. Region은 Northeast Asia (Seoul).
2. 좌측 **SQL Editor** → **New query** → 저장소의 `server/supabase.sql` 내용을 전부 붙여넣기.
   파일 상단의 `'1234'`(편집 PIN)와 `'0000'`(조회 PIN)을 팀 PIN으로 바꾼 뒤 **Run**.
3. **Project Settings → API** 에서 **Project URL** 과 **anon public** 키를 복사.
4. `config.js` 의 `supabaseUrl`, `supabaseAnonKey` 에 붙여넣고 커밋·푸시.
5. https://kwonyujin119.github.io/test2/ 를 열면 조회 PIN 잠금 화면이 뜨고, 통과하면 "팀 공유 모드"가 됩니다.

anon 키는 브라우저에 노출되도록 설계된 공개 키입니다. 조회·편집 모두 PIN을 검증하는 DB 함수만 거치므로 키만으로는 데이터를 읽거나 쓸 수 없습니다.
무료 플랜은 1주일간 접속이 없으면 프로젝트가 일시중지되며, 대시보드에서 Restore 하면 데이터는 그대로 복구됩니다.

### 접근 통제 (PIN 2종)

| PIN | 용도 | 기본값 | 변경 |
|---|---|---|---|
| 조회 PIN | 링크를 여는 직원이 처음 한 번 입력. 기기에 저장됨 | `0000` | Supabase: `select ictc_set_view_pin('편집PIN', '새PIN');` / 로컬 서버: `view_pin.txt` |
| 편집 PIN | 추가·수정·삭제 시 처음 한 번 입력 | `1234` | Supabase: `select ictc_set_pin('기존PIN', '새PIN');` / 로컬 서버: `pin.txt` |

조회 PIN을 빈 문자열로 두면 링크를 아는 누구나 조회할 수 있습니다. 편집 PIN은 조회 PIN을 겸합니다.
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

프론트나 서버 파일을 수정한 뒤에는 `python server/build_zip.py` 로 설치 패키지를 다시 만들어 커밋하세요.
