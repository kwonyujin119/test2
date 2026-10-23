# SAIL:41 로컬 서버 (D드라이브 운영용, 대안 모드)

데이터를 외부 클라우드 없이 **본인 PC의 `D:\일정표,주요업무\` 폴더(SQLite 파일)** 에 저장하고,
같은 사무실 네트워크의 팀원이 브라우저로 접속해 보는 방식입니다.

**현재 팀은 Supabase 모드(https://kwonyujin119.github.io/test2/)로 운영 중이므로 이 서버는 설치하지 않아도 됩니다.**
외부 클라우드를 쓸 수 없게 되거나 사내망 전용 운영이 필요할 때의 대안입니다. 두 모드의 화면과 기능은 같습니다.

## 다운로드

- 설치 패키지(ZIP): https://github.com/kwonyujin119/test2/raw/main/dist/ictc-board-server.zip
- 저장소 전체: https://github.com/kwonyujin119/test2/archive/refs/heads/main.zip (ZIP 패키지가 더 간단합니다)

## 1회 설치

1. Python 설치 (이미 있으면 생략): https://www.python.org/downloads/
   설치 첫 화면에서 **"Add python.exe to PATH" 체크** 후 Install Now.
2. 위 ZIP을 받아 아무 곳(예: `D:\ICTC보드\`)에 압축을 풉니다. 구성:
   ```
   ictc-board-server\
   ├─ ictc_server.py
   ├─ start.bat
   ├─ 설치안내.txt
   ├─ README.md        (이 문서)
   └─ site\            (웹앱 화면: index.html, config.js, data\, assets\, checklist\, manifest.webmanifest, sw.js)
   ```
3. `start.bat` 더블클릭. 처음 실행하면 **`D:\일정표,주요업무\`** 폴더가 자동으로 만들어지고 그 안에
   `ictc.db`(전체 데이터), `pin.txt`(편집 PIN, 기본 1234), `view_pin.txt`(조회 PIN, 기본 0000)가 생깁니다.
4. Windows 방화벽 창이 뜨면 **"개인 네트워크"와 "공용 네트워크" 모두 체크 → 액세스 허용**.
   (허용하지 않으면 본인만 접속되고 팀원은 접속이 안 됩니다.)
5. 검은 창에 표시되는 `팀원 접속 : http://192.168.x.x:8080` 주소를 팀원에게 공유합니다.
6. `D:\일정표,주요업무\pin.txt`(편집 PIN)와 `view_pin.txt`(조회 PIN)를 메모장으로 열어 바꾸세요. 서버 재시작 없이 바로 적용됩니다.
   `view_pin.txt` 내용을 비우면 링크를 아는 누구나 조회할 수 있습니다.

프로그램(압축 푼 폴더)과 데이터(`D:\일정표,주요업무\`)가 분리되어 있어, 프로그램을 새 버전으로 바꿔도 데이터는 유지됩니다.

## 매일 사용

- PC를 켜고 `start.bat` 실행 → 검은 창을 그대로 둡니다. 창을 닫으면 서버가 꺼집니다.
- 본인: http://localhost:8080 / 팀원: 공유받은 주소
- 권한은 Supabase 모드와 같습니다. 직원은 처음 접속 때 조회 PIN(화면 문구 "팀 PIN")을 한 번 입력(기기에 저장)하면 일정·주요업무를 **누구나 추가·수정·삭제**할 수 있습니다. 대시보드 관리·JSON 내보내기/가져오기·사용자 관리·휴지통·41망 관리만 편집 PIN(화면 문구 "관리자 PIN", ⋮ 맨 아래 **관리자 로그인**). 개인업무는 뒤 4자리 + 비밀번호 4자리(처음이면 확인창 한 번으로 등록, 이름은 ⋮ → 내 이름 변경). 비밀번호 초기화·이름 수정은 관리자 모드 ⋮ → **개인업무 사용자 관리**(API 로는 `/api/user_reset_pin`, `/api/user_rename`, 편집 PIN).
- 41망 톡방·입장코드(기본값 Supabase 와 동일: 지휘역량강화센터 5948 · 교육지원과 5914 · 교육기획과 5926 · 훈련운영과 5527, 최초 실행 때만 생성)도 같은 화면으로 관리합니다. 첨부파일은 DB 파일 옆 **`D:\일정표,주요업무\files\`** 폴더에 저장되고(파일당 100MB, 허용 형식은 Supabase 버킷과 동일: 사진·PDF·텍스트·ZIP·한글·오피스 등, 그 밖은 "올릴 수 없는 파일 형식") `/files/<난수id>/<파일명>` 주소로 열립니다. 사진·PDF·텍스트만 브라우저에서 바로 열리고 나머지는 내려받기로만 제공됩니다(html 등이 서버 주소에서 실행되는 것을 막기 위함). 받다가 끊긴 파일은 저장되지 않습니다.
- 화면은 15초마다 자동 갱신(서버가 `config.js` 를 `pollSeconds: 15` 로 내려 줍니다).
- PIN을 10분 안에 10번 틀리면 그 PC는 잠시 차단됩니다("틀린 시도가 너무 많아요. 10분 뒤에 다시 하세요"). 정상 사용에는 영향 없습니다.
- 항목 한 건은 64KB, JSON 가져오기 본문은 32MB·1만 건까지입니다(넘으면 영문 코드 `ITEM_TOO_LARGE`).
- 홈 화면 추가(PWA)는 `http://` 주소라 크롬에서 "앱 설치"가 뜨지 않을 수 있습니다. 북마크나 바로가기로 쓰세요.

### Supabase 에서 로컬 서버로 옮길 때

1. Supabase 화면에서 관리자 모드로 ⋮ → **JSON 내보내기**. Schedule·Attention 탭 각각, 대시보드마다 받습니다.
2. 로컬 서버 화면(팀원 접속 주소)에서 편집 PIN 으로 ⋮ → **JSON 가져오기**. 대시보드는 먼저 같은 이름으로 만들어 둡니다.
3. 개인업무·41망 글은 JSON 으로 옮길 수 없습니다. 직원이 새 서버에서 Individual Log 탭에 뒤 4자리 + 비밀번호를 넣고 "새로 등록할까요?" 확인으로 다시 등록한 뒤(이름은 ⋮ → 내 이름 변경), 필요한 내용은 엑셀 가져오기나 직접 입력으로 각자 옮깁니다. 톡방 입장코드는 새 서버에서 관리자 모드로 다시 정합니다.
4. GitHub 의 `config.js` 두 값을 비우면 Pages 주소는 "테스트 모드"(각자 브라우저 저장)로 바뀌고, 화면 상단 배너의 **사내 서버 주소 연결**에 팀원 접속 주소를 넣어 두면 버튼 한 번으로 서버 화면으로 넘어갑니다.

### 부팅 시 자동 실행 (선택)

`Win + R` → `shell:startup` → 열린 폴더에 `start.bat` 의 바로가기를 넣으면 로그인 시 자동 시작됩니다.
전원 옵션에서 **절전 모드를 "안 함"** 으로 두어야 자리를 비운 동안에도 팀원이 접속할 수 있습니다.

## 백업

`D:\일정표,주요업무\ictc.db` 파일이 전체 데이터(일정·업무·대시보드·개인업무·41망 글·톡방·휴지통)입니다. 41망 첨부파일은 옆의 `files\` 폴더에 있으니 **두 개를 함께** 복사해 두면 됩니다.
서버를 켤 때마다 `D:\일정표,주요업무\backups\ictc-YYYYMMDD.db` 사본이 자동으로 생기고 최근 7개를 보관합니다.
웹앱 ⋮ 메뉴의 **JSON 내보내기** 로도 백업할 수 있습니다.

### 휴지통 (잘못 지운 항목 복구)

조회 PIN 을 아는 직원 누구나 일정·주요업무를 지울 수 있으므로, 지운 항목은 DB 안의 `items_deleted` 표에 **30일** 보관됩니다
(삭제 · JSON 가져오기로 덮어쓴 항목 · 대시보드 삭제 · 개인업무 삭제 · 41망 글 삭제 모두 포함. 30일이 지나면 다음 삭제 때 자동 정리. 톡방이 300개를 넘어 밀려난 옛 글은 보관하지 않음).

복구는 Supabase 모드와 같이 화면에서 합니다: 관리자 모드(⋮ 맨 아래 **관리자 로그인** → 편집 PIN) → ⋮ → **휴지통** → 항목 옆 **복구**.

화면을 쓸 수 없을 때는 서버 PC 의 PowerShell 에서 API 로도 됩니다(편집 PIN 1234 예시):

```powershell
# 최근 삭제 목록 (seq, kind, board, data.title, deleted_at)
Invoke-RestMethod -Method Post -Uri http://localhost:8080/api/deleted_list -ContentType 'application/json' -Body '{"pin":"1234"}' | Select-Object seq,kind,board,deleted_at,reason,@{n='title';e={$_.data.title}}
# seq 번호로 복구
Invoke-RestMethod -Method Post -Uri http://localhost:8080/api/restore -ContentType 'application/json' -Body '{"pin":"1234","seq":12}'
```

Supabase 모드의 SQL 은 `select * from ictc_deleted_list('편집PIN');` → `select ictc_restore('편집PIN', seq);` 입니다.

## 한계

- PC가 꺼져 있거나 절전 상태면 팀원이 접속할 수 없습니다.
- 사무실 네트워크 밖(외부, 휴대폰 LTE)에서는 접속되지 않습니다.
- PC의 IP가 바뀌면(DHCP) 접속 주소도 바뀝니다. 전산 담당자에게 고정 IP를 요청하면 해결됩니다.
- 41망 첨부는 서버 PC 디스크를 씁니다(`files\`). 글을 지워도 파일은 남으므로 디스크가 차면 오래된 파일을 직접 지웁니다.
- PIN 을 10분 안에 10번 틀리면 그 PC 는 "틀린 시도가 너무 많아요. 10분 뒤에 다시 하세요" 로 잠시 차단됩니다(서버를 재시작하면 풀림).
- 화면에 `SERVER_ERROR` 가 뜨면 서버 PC 의 검은 창에 `[오류]` 로 원인이 남습니다(디스크 부족, DB 파일 손상 등). 그 내용을 담당자에게 전달하세요.

## 옵션

start.bat 을 메모장으로 열어 수정하거나, 직접 실행할 때:
```
python ictc_server.py --port 9000                          포트 변경
python ictc_server.py --db "E:\백업\ictc.db" --pin-file "E:\백업\pin.txt"   데이터 위치 변경
python ictc_server.py --host 127.0.0.1                     이 PC에서만 접속 (테스트용)
python ictc_server.py --poll 30                            팀원 화면 자동 새로고침 주기(초, 기본 15)
```
