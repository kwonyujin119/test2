# -*- coding: utf-8 -*-
"""dist/ictc-board-server.zip 생성. 프론트(index.html, manifest, sw, assets, data, checklist)나 서버 파일이 바뀌면 다시 실행해 커밋하세요.
사용: python server/build_zip.py  (저장소 루트에서)"""
import os, zipfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'dist', 'ictc-board-server.zip')
TOP = 'ictc-board-server/'
GUIDE = """SAIL:41 (지휘역량강화센터 일정·업무 보드) 로컬 서버 - 설치 안내

1. Python 설치 (https://www.python.org/downloads/)
   설치 첫 화면에서 "Add python.exe to PATH" 를 반드시 체크하세요.
2. start.bat 더블클릭
   -> D:\\일정표,주요업무\\ 폴더가 자동 생성되고 그 안에 ictc.db(데이터), pin.txt(편집 PIN, 기본 1234), view_pin.txt(조회 PIN, 기본 0000)가 만들어집니다.
3. Windows 방화벽 창이 뜨면 개인/공용 네트워크 모두 체크 후 "액세스 허용".
4. 검은 창의 "팀원 접속: http://192.168.x.x:8080" 주소를 팀원에게 공유합니다.
   본인은 http://localhost:8080 으로 접속합니다.
5. PIN 변경: D:\\일정표,주요업무\\pin.txt(편집 PIN), view_pin.txt(조회 PIN, 비우면 누구나 조회)를 메모장으로 수정 (즉시 적용).
   조회 PIN 을 아는 직원은 일정·주요업무를 추가·수정·삭제할 수 있고, 편집 PIN 은 대시보드·사용자 관리 등 관리 작업에만 쓰입니다.
   개인업무는 뒤 4자리 + 이름으로 로그인합니다 (비밀번호 없음).
6. 백업: 서버를 켤 때마다 D:\\일정표,주요업무\\backups\\ 에 날짜별 사본이 생깁니다 (최근 7개 보관).
   삭제한 항목은 DB 안에 30일 보관됩니다 (복구 방법은 README '휴지통' 참조).

* 창을 닫으면 서버가 꺼집니다. PC 절전은 "안 함"으로 두세요.
* 수동 백업은 D:\\일정표,주요업무\\ictc.db 파일 하나만 복사하면 됩니다.
* 자세한 내용: https://github.com/kwonyujin119/test2/blob/main/server/README.md
"""
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
    for name in ('ictc_server.py', 'start.bat'):
        z.write(os.path.join(ROOT, 'server', name), TOP + name)
    z.writestr(TOP + '설치안내.txt', GUIDE.replace('\n', '\r\n').encode('utf-8-sig'))
    z.write(os.path.join(ROOT, 'index.html'), TOP + 'site/index.html')
    # 로컬 서버는 /config.js 를 동적으로 대체하므로, 패키지에는 빈 설정만 넣는다 (Supabase 키 미포함)
    z.writestr(TOP + 'site/config.js', '// 로컬 서버가 이 파일을 자동으로 대체합니다. 수정하지 마세요.\nwindow.ICTC_CONFIG = { supabaseUrl: "", supabaseAnonKey: "" };\n')
    for extra in ('manifest.webmanifest', 'sw.js'):
        z.write(os.path.join(ROOT, extra), TOP + 'site/' + extra)
    for sub in ('data', 'checklist', 'assets'):
        for dirpath, _, files in os.walk(os.path.join(ROOT, sub)):
            for f in sorted(files):
                full = os.path.join(dirpath, f)
                z.write(full, TOP + 'site/' + os.path.relpath(full, ROOT).replace(os.sep, '/'))
print('wrote', os.path.relpath(OUT, ROOT), os.path.getsize(OUT), 'bytes')
with zipfile.ZipFile(OUT) as z:
    for i in z.infolist(): print('  ', i.filename)
