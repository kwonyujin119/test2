# -*- coding: utf-8 -*-
"""dist/ictc-board-server.zip 생성. 프론트(ictc/)나 서버 파일이 바뀌면 다시 실행해 커밋하세요.
사용: python server/build_zip.py  (저장소 루트에서)"""
import os, zipfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'dist', 'ictc-board-server.zip')
TOP = 'ictc-board-server/'
GUIDE = """ICTC 일정·업무 보드 - 설치 안내

1. Python 설치 (https://www.python.org/downloads/)
   설치 첫 화면에서 "Add python.exe to PATH" 를 반드시 체크하세요.
2. start.bat 더블클릭
   -> D:\\일정표,주요업무\\ 폴더가 자동 생성되고 그 안에 ictc.db(데이터), pin.txt(편집 PIN, 기본 1234)가 만들어집니다.
3. Windows 방화벽 창이 뜨면 개인/공용 네트워크 모두 체크 후 "액세스 허용".
4. 검은 창의 "팀원 접속: http://192.168.x.x:8080" 주소를 팀원에게 공유합니다.
   본인은 http://localhost:8080 으로 접속합니다.
5. PIN 변경: D:\\일정표,주요업무\\pin.txt 를 메모장으로 수정 (즉시 적용).

* 창을 닫으면 서버가 꺼집니다. PC 절전은 "안 함"으로 두세요.
* 백업은 D:\\일정표,주요업무\\ictc.db 파일 하나만 복사하면 됩니다.
* 자세한 내용: https://github.com/kwonyujin119/test2/blob/main/server/README.md
"""
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
    for name in ('ictc_server.py', 'start.bat'):
        z.write(os.path.join(ROOT, 'server', name), TOP + name)
    z.writestr(TOP + '설치안내.txt', GUIDE.replace('\n', '\r\n').encode('utf-8-sig'))
    z.write(os.path.join(ROOT, 'index.html'), TOP + 'site/index.html')
    z.write(os.path.join(ROOT, 'config.js'), TOP + 'site/config.js')
    for sub in ('data', 'checklist'):
        for dirpath, _, files in os.walk(os.path.join(ROOT, sub)):
            for f in sorted(files):
                full = os.path.join(dirpath, f)
                z.write(full, TOP + 'site/' + os.path.relpath(full, ROOT).replace(os.sep, '/'))
print('wrote', os.path.relpath(OUT, ROOT), os.path.getsize(OUT), 'bytes')
with zipfile.ZipFile(OUT) as z:
    for i in z.infolist(): print('  ', i.filename)
