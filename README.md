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

| 모드 | 조건 | 동작 |
|---|---|---|
| **사내 서버 모드** (권장) | `server/ictc_server.py` 를 본인 PC(D드라이브)에서 실행 | DB가 PC의 `ictc.db` 파일에 저장. 같은 네트워크 팀원이 `http://PC주소:8080` 으로 접속해 조회, PIN 아는 사람만 편집. 15초마다 자동 갱신 |
| Supabase 모드 | `ictc/config.js` 에 Supabase URL·anon key 입력 | 외부 클라우드 DB. GitHub Pages 주소 그대로 사용 가능 |
| 브라우저 저장 모드 | 위 둘 다 아님 (GitHub Pages 기본 상태) | 수정 내용이 각자 브라우저에만 저장 |

**사내 서버 모드 설치 방법은 [`server/README.md`](server/README.md) 를 보세요.** (Python 설치 → 폴더 복사 → start.bat 실행)

Supabase 모드는 `ictc/supabase.sql` 을 SQL Editor 에서 실행한 뒤 `config.js` 를 채우면 됩니다.

### 일정 구분(카테고리)

교육 · 평가 · 회의 · 방문 · 출장 · 기타 6종 고정이며 색으로 구분됩니다.
일정의 **시간을 클릭**하면 일시만 바꾸는 작은 창이, **제목을 클릭**하면 제목·장소·담당·메모 수정 창이 열립니다.

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

`status`는 `예정` / `진행중` / `완료` / `보류` 중 하나. `id`가 없으면 자동 생성됩니다.
