# ICTC 보드 로컬 서버 (D드라이브 운영용)

데이터를 외부 클라우드 없이 **본인 PC의 `D:\일정표,주요업무\` 폴더(SQLite 파일)** 에 저장하고,
같은 사무실 네트워크의 팀원이 브라우저로 접속해 보는 방식입니다.

## 다운로드

- 설치 패키지(ZIP): https://github.com/kwonyujin119/test2/raw/main/dist/ictc-board-server.zip
- 저장소 전체: https://github.com/kwonyujin119/test2/archive/refs/heads/main.zip (`server\` 와 `ictc\` 폴더만 사용)

## 1회 설치

1. Python 설치 (이미 있으면 생략): https://www.python.org/downloads/
   설치 첫 화면에서 **"Add python.exe to PATH" 체크** 후 Install Now.
2. 위 ZIP을 받아 아무 곳(예: `D:\ICTC보드\`)에 압축을 풉니다. 구성:
   ```
   ictc-board-server\
   ├─ ictc_server.py
   ├─ start.bat
   ├─ 설치안내.txt
   └─ ictc\            (웹앱 화면)
   ```
3. `start.bat` 더블클릭. 처음 실행하면 **`D:\일정표,주요업무\`** 폴더가 자동으로 만들어지고 그 안에
   `ictc.db`(전체 데이터)와 `pin.txt`(편집 PIN, 기본 1234)가 생깁니다.
4. Windows 방화벽 창이 뜨면 **"개인 네트워크"와 "공용 네트워크" 모두 체크 → 액세스 허용**.
   (허용하지 않으면 본인만 접속되고 팀원은 접속이 안 됩니다.)
5. 검은 창에 표시되는 `팀원 접속 : http://192.168.x.x:8080` 주소를 팀원에게 공유합니다.
6. `D:\일정표,주요업무\pin.txt` 를 메모장으로 열어 PIN을 바꾸세요. 서버 재시작 없이 바로 적용됩니다.

프로그램(압축 푼 폴더)과 데이터(`D:\일정표,주요업무\`)가 분리되어 있어, 프로그램을 새 버전으로 바꿔도 데이터는 유지됩니다.

## 매일 사용

- PC를 켜고 `start.bat` 실행 → 검은 창을 그대로 둡니다. 창을 닫으면 서버가 꺼집니다.
- 본인: http://localhost:8080 / 팀원: 공유받은 주소
- 조회는 누구나, 추가·수정·삭제는 PIN 입력 후 가능. 팀원 화면은 15초마다 자동 갱신.

### 부팅 시 자동 실행 (선택)

`Win + R` → `shell:startup` → 열린 폴더에 `start.bat` 의 바로가기를 넣으면 로그인 시 자동 시작됩니다.
전원 옵션에서 **절전 모드를 "안 함"** 으로 두어야 자리를 비운 동안에도 팀원이 접속할 수 있습니다.

## 백업

`D:\일정표,주요업무\ictc.db` 파일 하나가 전체 데이터입니다. 주기적으로 복사해 두면 됩니다.
웹앱 ⋮ 메뉴의 **JSON 내보내기** 로도 백업할 수 있습니다.

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
