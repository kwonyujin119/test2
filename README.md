# test2

인천소방학교 현장지휘관 체크리스트 및 ICTC 일정·업무 보드 (GitHub Pages)

| 페이지 | 주소 | 파일 |
|---|---|---|
| 현장지휘관 체크리스트 | https://kwonyujin119.github.io/test2/ | `index.html` |
| ICTC 일정 · 주요업무 | https://kwonyujin119.github.io/test2/ictc/ | `ictc/index.html` |

## ICTC 일정 · 주요업무 (웹앱 초안)

팀원이 브라우저에서 일정과 업무를 직접 추가·수정·삭제할 수 있는 보드입니다.

- 일정표: 날짜별 그룹, 오늘 강조, 구분(교육/회의 …) 필터
- 주요업무: 상태(예정/진행중/완료/보류) 필터, 기한 지연 표시, 상태 배지 클릭으로 상태 순환
- PC: 좌측 고정 사이드바(요약·필터·버튼) + 우측 콘텐츠 2단, 1400px 이상에서 업무 3열
- 모바일: 바텀시트 입력, 플로팅 추가 버튼
- 단축키: `N` 새 항목, `1`/`2` 탭 전환, `Esc` 닫기
- 다크모드 자동 대응

### 데이터 저장 방식

두 가지 모드가 있으며 `ictc/config.js` 로 결정됩니다.

| 모드 | 조건 | 동작 |
|---|---|---|
| **팀 공유 모드** (권장) | `config.js`에 Supabase URL·anon key 입력 | 누구나 조회, PIN을 아는 사람만 편집. 저장 즉시 모든 팀원에게 반영, 30초마다 자동 새로고침 |
| 브라우저 저장 모드 | `config.js` 값이 비어 있음 | `ictc/data/*.json`을 기본값으로 읽고, 수정은 각자 브라우저에만 저장 |

### 팀 공유 모드 설정 (약 5분, 1회)

1. https://supabase.com 에 가입(GitHub 계정으로 가능) → **New project** 생성. Region은 Northeast Asia (Seoul) 권장.
2. 좌측 **SQL Editor** → **New query** → 저장소의 `ictc/supabase.sql` 내용을 전부 붙여넣기.
   파일 안의 `'1234'` 를 팀 편집 PIN으로 바꾼 뒤 **Run**.
3. 좌측 **Project Settings → API** 에서 **Project URL** 과 **anon public** 키를 복사.
4. `ictc/config.js` 의 `supabaseUrl`, `supabaseAnonKey` 에 붙여넣고 커밋·푸시.
5. 사이트를 열면 안내 문구가 "팀 공유 모드"로 바뀝니다. 편집 시 처음 한 번 PIN을 묻고 브라우저에 기억합니다.

- anon 키는 공개용 키입니다(브라우저에 노출되도록 설계됨). 쓰기 권한은 모두 PIN 검증 함수를 거치므로 키만으로는 편집할 수 없습니다.
- PIN 변경: SQL Editor에서 `select ictc_set_pin('기존PIN', '새PIN');`
- 기존 `ictc/data/*.json` 데이터를 서버로 올리려면 ⋮ 메뉴 → **JSON 가져오기**.
- 무료 플랜은 1주일간 접속이 없으면 프로젝트가 일시중지됩니다. 대시보드에서 Restore 하면 데이터는 그대로 복구됩니다.

### JSON 형식

```json
// schedule.json 항목
{ "id": "s001", "date": "2026-10-22", "start": "09:00", "end": "12:00",
  "title": "일정 제목", "place": "장소", "owner": "담당", "tag": "교육", "note": "메모" }

// tasks.json 항목
{ "id": "t001", "category": "교육운영", "title": "업무명", "status": "진행중",
  "due": "2026-11-14", "owner": "담당", "detail": "상세 내용" }
```

`status`는 `예정` / `진행중` / `완료` / `보류` 중 하나. `id`가 없으면 자동 생성됩니다.
