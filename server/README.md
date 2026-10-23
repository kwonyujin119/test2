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
- 권한은 Supabase 모드와 같습니다. 직원은 처음 접속 때 조회 PIN을 한 번 입력(기기에 저장)하면 일정·주요업무를 **누구나 추가·수정·삭제**할 수 있습니다. 대시보드 관리·JSON 가져오기·사용자 관리만 편집 PIN. 개인업무는 뒤 4자리 + 비밀번호 4자리(v4). 비밀번호 초기화·이름 수정은 `/api/user_reset_pin`, `/api/user_rename`(편집 PIN).
- 화면은 15초마다 자동 갱신(서버가 `config.js` 를 `pollSeconds: 15` 로 내려 줍니다).
- PIN을 10분 안에 10번 틀리면 그 PC는 잠시 차단됩니다("시도가 너무 많습니다"). 정상 사용에는 영향 없습니다.
- 홈 화면 추가(PWA)는 `http://` 주소라 크롬에서 "앱 설치"가 뜨지 않을 수 있습니다. 북마크나 바로가기로 쓰세요.

### Supabase 에서 로컬 서버로 옮길 때

1. Supabase 화면에서 관리자 모드로 ⋮ → **JSON 내보내기**. Schedule·Attention 탭 각각, 대시보드마다 받습니다.
2. 로컬 서버 화면(팀원 접속 주소)에서 편집 PIN 으로 ⋮ → **JSON 가져오기**. 대시보드는 먼저 같은 이름으로 만들어 둡니다.
3. 개인업무는 JSON 으로 옮길 수 없습니다. 직원이 새 서버에서 '처음 등록'으로 다시 등록(뒤 4자리 + 이름 + 비밀번호)하고, 필요한 내용은 엑셀 가져오기나 직접 입력으로 각자 옮깁니다.
4. GitHub 의 `config.js` 두 값을 비우면 Pages 주소는 "테스트 모드"(각자 브라우저 저장)로 바뀌고, 화면 상단 배너의 **사내 서버 주소 연결**에 팀원 접속 주소를 넣어 두면 버튼 한 번으로 서버 화면으로 넘어갑니다.

### 부팅 시 자동 실행 (선택)

`Win + R` → `shell:startup` → 열린 폴더에 `start.bat` 의 바로가기를 넣으면 로그인 시 자동 시작됩니다.
전원 옵션에서 **절전 모드를 "안 함"** 으로 두어야 자리를 비운 동안에도 팀원이 접속할 수 있습니다.

## 백업

`D:\일정표,주요업무\ictc.db` 파일 하나가 전체 데이터(일정·업무·대시보드·개인업무 사용자)입니다. 주기적으로 복사해 두면 됩니다.
서버를 켤 때마다 `D:\일정표,주요업무\backups\ictc-YYYYMMDD.db` 사본이 자동으로 생기고 최근 7개를 보관합니다.
웹앱 ⋮ 메뉴의 **JSON 내보내기** 로도 백업할 수 있습니다.

### 휴지통 (잘못 지운 항목 복구)

조회 PIN 을 아는 직원 누구나 일정·주요업무를 지울 수 있으므로, 지운 항목은 DB 안의 `items_deleted` 표에 **30일** 보관됩니다
(삭제 · JSON 가져오기로 덮어쓴 항목 · 대시보드 삭제 · 개인업무 삭제 모두 포함. 30일이 지나면 다음 삭제 때 자동 정리).
아직 화면 메뉴는 없고, 서버 PC 에서 API 로 복구합니다. PowerShell 에서(편집 PIN 1234 예시):

```powershell
# 최근 삭제 목록 (seq, kind, board, data.title, deleted_at)
Invoke-RestMethod -Method Post -Uri http://localhost:8080/api/deleted_list -ContentType 'application/json' -Body '{"pin":"1234"}' | Select-Object seq,kind,board,deleted_at,reason,@{n='title';e={$_.data.title}}
# seq 번호로 복구
Invoke-RestMethod -Method Post -Uri http://localhost:8080/api/restore -ContentType 'application/json' -Body '{"pin":"1234","seq":12}'
```

Supabase 모드에서는 SQL Editor 에서 `select * from ictc_deleted_list('편집PIN');` → `select ictc_restore('편집PIN', seq);` 로 같은 일을 합니다.

## 한계

- PC가 꺼져 있거나 절전 상태면 팀원이 접속할 수 없습니다.
- 사무실 네트워크 밖(외부, 휴대폰 LTE)에서는 접속되지 않습니다.
- PC의 IP가 바뀌면(DHCP) 접속 주소도 바뀝니다. 전산 담당자에게 고정 IP를 요청하면 해결됩니다.

## 옵션

start.bat 을 메모장으로 열어 수정하거나, 직접 실행할 때:
```
python ictc_server.py --port 9000                          포트 변경
python ictc_server.py --db "E:\백업\ictc.db" --pin-file "E:\백업\pin.txt"   데이터 위치 변경
python ictc_server.py --host 127.0.0.1                     이 PC에서만 접속 (테스트용)
```
